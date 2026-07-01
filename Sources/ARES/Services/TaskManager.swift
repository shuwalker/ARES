import Foundation
import EventKit

// MARK: - Task Manager (EventKit Native)
// Bridges ARES to Apple Reminders + Calendar via EventKit.
// No osascript. No timeouts. Native Apple framework.

@MainActor
final class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    private let eventStore = EKEventStore()
    private var hasRemindersAccess = false
    private var hasCalendarAccess = false
    
    @Published var todayTasks: [ARESTask] = []
    @Published var overdueTasks: [ARESTask] = []
    @Published var inboxCount: Int = 0
    @Published var todayEvents: [ARESEvent] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    
    // MARK: - Permission
    
    func requestAccess() async -> Bool {
        do {
            hasRemindersAccess = try await eventStore.requestFullAccessToReminders()
            hasCalendarAccess = try await eventStore.requestFullAccessToEvents()
            return hasRemindersAccess && hasCalendarAccess
        } catch {
            lastError = "Permission denied: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Task CRUD
    
    func createTask(
        title: String,
        listName: String = "Inbox",
        dueDate: Date? = nil,
        priority: Int = 0,
        notes: String = ""
    ) async -> Bool {
        guard hasRemindersAccess else { return false }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.priority = priority
        reminder.notes = notes
        
        if let due = dueDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            reminder.dueDateComponents = components
        }
        
        if let calendar = findOrCreateList(named: listName) {
            reminder.calendar = calendar
        }
        
        do {
            try eventStore.save(reminder, commit: true)
            return true
        } catch {
            lastError = "Failed to create task: \(error.localizedDescription)"
            return false
        }
    }
    
    func completeTask(reminderID: String) async -> Bool {
        guard hasRemindersAccess else { return false }
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        
        let reminders = await fetchReminders(matching: predicate)
        if let reminder = reminders.first(where: { $0.calendarItemIdentifier == reminderID }) {
            reminder.isCompleted = true
            do {
                try eventStore.save(reminder, commit: true)
                return true
            } catch {
                lastError = "Failed to complete: \(error.localizedDescription)"
            }
        }
        return false
    }
    
    func rescheduleTask(reminderID: String, newDate: Date) async -> Bool {
        guard hasRemindersAccess else { return false }
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        
        let reminders = await fetchReminders(matching: predicate)
        if let reminder = reminders.first(where: { $0.calendarItemIdentifier == reminderID }) {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: newDate)
            reminder.dueDateComponents = components
            do {
                try eventStore.save(reminder, commit: true)
                return true
            } catch {
                lastError = "Failed to reschedule: \(error.localizedDescription)"
            }
        }
        return false
    }
    
    func deleteTask(reminderID: String) async -> Bool {
        guard hasRemindersAccess else { return false }
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil
        )
        
        let reminders = await fetchReminders(matching: predicate)
        if let reminder = reminders.first(where: { $0.calendarItemIdentifier == reminderID }) {
            do {
                try eventStore.remove(reminder, commit: true)
                return true
            } catch {
                lastError = "Failed to delete: \(error.localizedDescription)"
            }
        }
        return false
    }
    
    // MARK: - Reading Data
    
    func refreshAll() async {
        guard hasRemindersAccess else {
            lastError = "No Reminders access. Grant permission in System Settings."
            return
        }
        
        isRefreshing = true
        lastError = nil
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshOverdue() }
            group.addTask { await self.refreshToday() }
            group.addTask { await self.refreshInboxCount() }
            group.addTask { await self.refreshCalendarEvents() }
        }
        
        isRefreshing = false
    }
    
    private func refreshOverdue() async {
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: Calendar.current.startOfDay(for: Date()),
            calendars: nil
        )
        
        let reminders = await fetchReminders(matching: predicate)
        let now = Date()
        let tasks: [ARESTask] = reminders.compactMap { r in
            guard let due = r.dueDateComponents?.date else { return nil }
            let daysOverdue = Calendar.current.dateComponents([.day], from: due, to: now).day ?? 0
            return ARESTask(
                title: r.title,
                list: r.calendar?.title ?? "Unknown",
                daysOverdue: daysOverdue,
                priority: r.priority,
                reminderID: r.calendarItemIdentifier
            )
        }.sorted { $0.daysOverdue > $1.daysOverdue }
        
        await MainActor.run { self.overdueTasks = tasks }
    }
    
    private func refreshToday() async {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startOfDay,
            ending: endOfDay,
            calendars: nil
        )
        
        let reminders = await fetchReminders(matching: predicate)
        let tasks: [ARESTask] = reminders.map { r in
            ARESTask(
                title: r.title,
                list: r.calendar?.title ?? "Unknown",
                daysOverdue: 0,
                priority: r.priority,
                reminderID: r.calendarItemIdentifier
            )
        }.sorted { $0.priority > $1.priority }
        
        await MainActor.run { self.todayTasks = tasks }
    }
    
    private func refreshInboxCount() async {
        guard let inboxCalendar = eventStore.calendars(for: .reminder)
            .first(where: { $0.title.lowercased() == "inbox" }) else {
            await MainActor.run { self.inboxCount = 0 }
            return
        }
        
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [inboxCalendar]
        )
        
        let reminders = await fetchReminders(matching: predicate)
        await MainActor.run { self.inboxCount = reminders.count }
    }
    
    private func refreshCalendarEvents() async {
        guard hasCalendarAccess else { return }
        
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay, end: endOfDay, calendars: nil
        )
        
        let events = eventStore.events(matching: predicate)
        let aresEvents: [ARESEvent] = events.map { e in
            ARESEvent(
                title: e.title,
                calendar: e.calendar?.title ?? "Unknown",
                startDate: e.startDate,
                endDate: e.endDate
            )
        }
        
        await MainActor.run { self.todayEvents = aresEvents }
    }
    
    // MARK: - Morning Briefing
    
    func generateMorningBriefing() async -> MorningBriefing {
        await refreshAll()
        await writeCache()
        
        let bigTasks = todayTasks.filter { $0.priority >= 3 }.prefix(1)
        let mediumTasks = todayTasks.filter { $0.priority == 2 }.prefix(3)
        let smallTasks = todayTasks.filter { $0.priority <= 1 }.prefix(5)
        
        return MorningBriefing(
            date: Date(),
            overdueCount: overdueTasks.count,
            todayCount: todayTasks.count,
            inboxCount: inboxCount,
            eventCount: todayEvents.count,
            bigTasks: Array(bigTasks),
            mediumTasks: Array(mediumTasks),
            smallTasks: Array(smallTasks),
            overdueTasks: Array(overdueTasks.prefix(5)),
            events: todayEvents,
            suggestion: energySuggestion()
        )
    }
    
    // MARK: - Cache (for cron scripts)
    
    private func writeCache() async {
        let cache: [String: Any] = [
            "updated_at": ISO8601DateFormatter().string(from: Date()),
            "overdue": overdueTasks.map { t -> [String: Any] in
                ["title": t.title, "list": t.list, "daysOverdue": t.daysOverdue, "priority": t.priority, "reminderID": t.reminderID]
            },
            "today": todayTasks.map { t -> [String: Any] in
                ["title": t.title, "list": t.list, "priority": t.priority, "reminderID": t.reminderID]
            },
            "inbox_count": inboxCount
        ]
        
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ares")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cachePath = cacheDir.appendingPathComponent("task-cache.json")
        
        if let data = try? JSONSerialization.data(withJSONObject: cache, options: .prettyPrinted) {
            try? data.write(to: cachePath, options: .atomic)
        }
    }
    
    // MARK: - Helpers
    
    @MainActor
    private func fetchReminders(matching predicate: NSPredicate) async -> [EKReminder] {
        let store = self.eventStore
        // EventKit callbacks are non-Sendable; bridge through NSData
        let data = await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            store.fetchReminders(matching: predicate) { reminders in
                let result = reminders ?? []
                // Archive on the callback thread, resume with Sendable Data
                let archived = try? NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: false)
                continuation.resume(returning: archived ?? Data())
            }
        }
        // Unarchive on MainActor
        guard let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, EKReminder.self], from: data) as? [EKReminder] else {
            return []
        }
        return unarchived
    }
    
    private func findOrCreateList(named name: String) -> EKCalendar? {
        let reminderCalendars = eventStore.calendars(for: .reminder)
        
        if let existing = reminderCalendars.first(where: { $0.title.lowercased() == name.lowercased() }) {
            return existing
        }
        
        let newCalendar = EKCalendar(for: .reminder, eventStore: eventStore)
        newCalendar.title = name
        newCalendar.source = eventStore.defaultCalendarForNewReminders()?.source
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: true)
            return newCalendar
        } catch {
            return nil
        }
    }
    
    private func energySuggestion() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Morning energy is high. Consider deep work on your top priority task."
        } else if hour < 14 {
            return "Post-lunch dip. Good for admin tasks and quick wins."
        } else if hour < 17 {
            return "Afternoon window. Medium-focus tasks work well here."
        } else {
            return "Evening. Light tasks, planning tomorrow, or winding down."
        }
    }
}

// MARK: - Data Models

struct ARESTask: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let list: String
    let daysOverdue: Int
    let priority: Int
    let reminderID: String
    
    var priorityLabel: String {
        switch priority {
        case 4: return "🔴"
        case 3: return "🟡"
        case 2: return "🟢"
        case 1: return "⚪"
        default: return "⚪"
        }
    }
    
    var isOverdue: Bool { daysOverdue > 0 }
}

struct ARESEvent: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let calendar: String
    let startDate: Date
    let endDate: Date
}

struct MorningBriefing {
    let date: Date
    let overdueCount: Int
    let todayCount: Int
    let inboxCount: Int
    let eventCount: Int
    let bigTasks: [ARESTask]
    let mediumTasks: [ARESTask]
    let smallTasks: [ARESTask]
    let overdueTasks: [ARESTask]
    let events: [ARESEvent]
    let suggestion: String
}
