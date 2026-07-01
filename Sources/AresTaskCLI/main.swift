import Foundation
import EventKit

// MARK: - AresTask CLI
// Tiny Swift CLI that reads/writes Apple Reminders via EventKit.
// Called by Python cron scripts. Outputs JSON. No timeouts.

// Use a wrapper to avoid MainActor isolation issues
final class RemindersBridge: @unchecked Sendable {
    let store: EKEventStore
    
    init() {
        self.store = EKEventStore()
    }
    
    func requestAccess() -> (reminders: Bool, calendar: Bool) {
        let sem = DispatchSemaphore(value: 0)
        var reminders = false
        var calendar = false
        
        store.requestFullAccessToReminders { granted, _ in
            reminders = granted
            sem.signal()
        }
        sem.wait()
        
        store.requestFullAccessToEvents { granted, _ in
            calendar = granted
            sem.signal()
        }
        sem.wait()
        
        return (reminders, calendar)
    }
    
    func fetchReminders(matching predicate: NSPredicate) -> [EKReminder] {
        let sem = DispatchSemaphore(value: 0)
        var results: [EKReminder] = []
        store.fetchReminders(matching: predicate) { reminders in
            results = reminders ?? []
            sem.signal()
        }
        sem.wait()
        return results
    }
    
    func taskToJSON(_ r: EKReminder, daysOverdue: Int = 0) -> [String: Any] {
        return [
            "title": r.title ?? "",
            "list": r.calendar?.title ?? "Unknown",
            "priority": r.priority,
            "daysOverdue": daysOverdue,
            "reminderID": r.calendarItemIdentifier,
            "completed": r.isCompleted
        ]
    }
}

func printJSON(_ obj: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
          let str = String(data: data, encoding: .utf8) else {
        print("[]")
        return
    }
    print(str)
}

// Main
let args = CommandLine.arguments
func printUsage() {
    print("Usage: arestask <command> [args...]")
    print("Commands: overdue, today, inbox-count, events, create, complete, reschedule")
}

guard args.count >= 2 else {
    printUsage()
    exit(1)
}

let command = args[1]
if command == "--help" || command == "-h" || command == "help" {
    printUsage()
    exit(0)
}

let bridge = RemindersBridge()
let access = bridge.requestAccess()

guard access.reminders else {
    print("{\"error\": \"No Reminders access\"}")
    exit(1)
}

let store = bridge.store

switch command {
case "overdue":
    let predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: nil,
        ending: Calendar.current.startOfDay(for: Date()),
        calendars: nil
    )
    let reminders = bridge.fetchReminders(matching: predicate)
    let now = Date()
    let tasks = reminders.compactMap { r -> [String: Any]? in
        guard let due = r.dueDateComponents?.date else { return nil }
        let days = Calendar.current.dateComponents([.day], from: due, to: now).day ?? 0
        return bridge.taskToJSON(r, daysOverdue: days)
    }.sorted { ($0["daysOverdue"] as? Int ?? 0) > ($1["daysOverdue"] as? Int ?? 0) }
    printJSON(tasks)

case "today":
    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    let predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: start, ending: end, calendars: nil
    )
    let reminders = bridge.fetchReminders(matching: predicate)
    let tasks = reminders.map { bridge.taskToJSON($0) }
        .sorted { ($0["priority"] as? Int ?? 0) > ($1["priority"] as? Int ?? 0) }
    printJSON(tasks)

case "inbox-count":
    guard let inboxCal = store.calendars(for: .reminder)
        .first(where: { $0.title.lowercased() == "inbox" }) else {
        print("{\"count\": 0}")
        exit(0)
    }
    let predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: nil, ending: nil, calendars: [inboxCal]
    )
    let reminders = bridge.fetchReminders(matching: predicate)
    print("{\"count\": \(reminders.count)}")

case "events":
    guard access.calendar else {
        print("{\"error\": \"No Calendar access\"}")
        exit(1)
    }
    let start = Calendar.current.startOfDay(for: Date())
    let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
    let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
    let events = store.events(matching: predicate)
    let result = events.map { e -> [String: Any] in
        return ["title": e.title ?? "", "calendar": e.calendar?.title ?? "Unknown"]
    }
    printJSON(result)

case "create":
    guard args.count >= 4 else {
        print("{\"error\": \"Usage: arestask create <title> <list> [priority] [due_date]\"}")
        exit(1)
    }
    let title = args[2]
    let listName = args[3]
    let reminder = EKReminder(eventStore: store)
    reminder.title = title
    reminder.priority = args.count >= 5 ? Int(args[4]) ?? 0 : 0
    
    if args.count >= 6 {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let due = formatter.date(from: args[5]) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
        }
    }
    
    let calendars = store.calendars(for: .reminder)
    if let cal = calendars.first(where: { $0.title.lowercased() == listName.lowercased() }) {
        reminder.calendar = cal
    }
    
    do {
        try store.save(reminder, commit: true)
        print("{\"ok\": true, \"id\": \"\(reminder.calendarItemIdentifier)\"}")
    } catch {
        print("{\"error\": \"\(error.localizedDescription)\"}")
    }

case "complete":
    guard args.count >= 3 else {
        print("{\"error\": \"Usage: arestask complete <reminderID>\"}")
        exit(1)
    }
    let id = args[2]
    let predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: nil, ending: nil, calendars: nil
    )
    let reminders = bridge.fetchReminders(matching: predicate)
    if let r = reminders.first(where: { $0.calendarItemIdentifier == id }) {
        r.isCompleted = true
        do {
            try store.save(r, commit: true)
            print("{\"ok\": true}")
        } catch {
            print("{\"error\": \"\(error.localizedDescription)\"}")
        }
    } else {
        print("{\"error\": \"Reminder not found\"}")
    }

case "reschedule":
    guard args.count >= 4 else {
        print("{\"error\": \"Usage: arestask reschedule <reminderID> <new_date>\"}")
        exit(1)
    }
    let id = args[2]
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    guard let newDate = formatter.date(from: args[3]) else {
        print("{\"error\": \"Invalid date format. Use YYYY-MM-DD\"}")
        exit(1)
    }
    let predicate = store.predicateForIncompleteReminders(
        withDueDateStarting: nil, ending: nil, calendars: nil
    )
    let reminders = bridge.fetchReminders(matching: predicate)
    if let r = reminders.first(where: { $0.calendarItemIdentifier == id }) {
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: newDate)
        do {
            try store.save(r, commit: true)
            print("{\"ok\": true}")
        } catch {
            print("{\"error\": \"\(error.localizedDescription)\"}")
        }
    } else {
        print("{\"error\": \"Reminder not found\"}")
    }

default:
    print("{\"error\": \"Unknown command: \(command)\"}")
    exit(1)
}
