import Foundation
import AppKit

// MARK: - Task Manager
// Bridges ARES to Apple Reminders + Calendar via osascript
// No third-party dependencies. No API keys. Uses what's on the machine.

@MainActor
final class TaskManager: ObservableObject {
    static let shared = TaskManager()
    
    @Published var todayTasks: [ARESTask] = []
    @Published var overdueTasks: [ARESTask] = []
    @Published var thisWeekTasks: [ARESTask] = []
    @Published var inboxCount: Int = 0
    @Published var todayEvents: [ARESEvent] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    
    // MARK: - Task CRUD
    
    /// Create a task in Apple Reminders
    func createTask(
        title: String,
        list: String = "Inbox",
        dueDate: Date? = nil,
        priority: Int = 0,
        notes: String = "",
        recurrence: RecurrenceRule? = nil
    ) async -> Bool {
        let dateStr = dueDate.map { formatAppleScriptDate($0) } ?? "missing value"
        let priorityStr = "\(priority)"
        let notesEscaped = notes.replacingOccurrences(of: "\"", with: "\\\"")
        
        let script: String
        if let due = dueDate {
            script = """
            tell application "Reminders"
                tell list "\(list)"
                    make new reminder with properties {name:"\(title.escapedForAppleScript)", due date:\(dateStr), priority:\(priorityStr), body:"\(notesEscaped)"}
                end tell
            end tell
            """
        } else {
            script = """
            tell application "Reminders"
                tell list "\(list)"
                    make new reminder with properties {name:"\(title.escapedForAppleScript)", priority:\(priorityStr), body:"\(notesEscaped)"}
                end tell
            end tell
            """
        }
        
        return await runOSAScript(script)
    }
    
    /// Mark a task complete
    func completeTask(title: String, list: String = "Today") async -> Bool {
        let script = """
        tell application "Reminders"
            set r to first reminder of list "\(list)" whose name is "\(title.escapedForAppleScript)"
            set completed of r to true
        end tell
        """
        return await runOSAScript(script)
    }
    
    /// Reschedule a task to a new date
    func rescheduleTask(title: String, list: String, newDate: Date) async -> Bool {
        let dateStr = formatAppleScriptDate(newDate)
        let script = """
        tell application "Reminders"
            set r to first reminder of list "\(list)" whose name is "\(title.escapedForAppleScript)"
            set due date of r to \(dateStr)
        end tell
        """
        return await runOSAScript(script)
    }
    
    /// Move task to a different list
    func moveTask(title: String, fromList: String, toList: String) async -> Bool {
        let script = """
        tell application "Reminders"
            set r to first reminder of list "\(fromList)" whose name is "\(title.escapedForAppleScript)"
            move r to list "\(toList)"
        end tell
        """
        return await runOSAScript(script)
    }
    
    /// Delete a task
    func deleteTask(title: String, list: String) async -> Bool {
        let script = """
        tell application "Reminders"
            set r to first reminder of list "\(list)" whose name is "\(title.escapedForAppleScript)"
            delete r
        end tell
        """
        return await runOSAScript(script)
    }
    
    // MARK: - Reading Data
    
    /// Refresh all task data from Apple Reminders
    func refreshAll() async {
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
        let script = """
        tell application "Reminders"
            set todayDate to current date
            set hours of todayDate to 0
            set minutes of todayDate to 0
            set seconds of todayDate to 0
            set output to ""
            repeat with eachList in lists
                repeat with eachReminder in reminders of eachList
                    if due date of eachReminder is not missing value then
                        if due date of eachReminder < todayDate and completed of eachReminder is false then
                            set daysOverdue to (todayDate - due date of eachReminder) div days
                            set p to priority of eachReminder
                            set output to output & name of eachReminder & "|" & name of eachList & "|" & daysOverdue & "|" & p & "|" & (id of eachReminder as text) & linefeed
                        end if
                    end if
                end repeat
            end repeat
            return output
        end tell
        """
        
        if let result = await runOSAScriptWithOutput(script) {
            let tasks = parseTaskLines(result)
            await MainActor.run { self.overdueTasks = tasks }
        }
    }
    
    private func refreshToday() async {
        let script = """
        tell application "Reminders"
            set todayDate to current date
            set hours of todayDate to 0
            set minutes of todayDate to 0
            set seconds of todayDate to 0
            set endOfDay to todayDate + (1 * days)
            set output to ""
            repeat with eachList in lists
                repeat with eachReminder in reminders of eachList
                    if due date of eachReminder is not missing value then
                        set d to due date of eachReminder
                        if d >= todayDate and d < endOfDay and completed of eachReminder is false then
                            set p to priority of eachReminder
                            set output to output & name of eachReminder & "|" & name of eachList & "|0|" & p & "|" & (id of eachReminder as text) & linefeed
                        end if
                    end if
                end repeat
            end repeat
            return output
        end tell
        """
        
        if let result = await runOSAScriptWithOutput(script) {
            let tasks = parseTaskLines(result)
            await MainActor.run { self.todayTasks = tasks }
        }
    }
    
    private func refreshInboxCount() async {
        let script = """
        tell application "Reminders"
            set cnt to 0
            repeat with eachReminder in reminders of list "Inbox"
                if completed of eachReminder is false then set cnt to cnt + 1
            end repeat
            return cnt
        end tell
        """
        
        if let result = await runOSAScriptWithOutput(script),
           let count = Int(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            await MainActor.run { self.inboxCount = count }
        }
    }
    
    private func refreshCalendarEvents() async {
        let script = """
        tell application "Calendar"
            set todayDate to current date
            set hours of todayDate to 0
            set minutes of todayDate to 0
            set seconds of todayDate to 0
            set endOfDay to todayDate + (1 * days)
            set output to ""
            set calList to {"Work", "Jenkins Family", "Jenkins Robotics", "Ares", "Focus", "PERSONAL", "Planned", "Scheduled Reminders", "Birthdays", "US Holidays"}
            repeat with calName in calList
                try
                    set c to calendar calName
                    repeat with eachEvent in events of c
                        if start date of eachEvent >= todayDate and start date of eachEvent < endOfDay then
                            set s to start date of eachEvent
                            set e to end date of eachEvent
                            set output to output & summary of eachEvent & "|" & calName & "|" & s & "|" & e & linefeed
                        end if
                    end repeat
                end try
            end repeat
            return output
        end tell
        """
        
        if let result = await runOSAScriptWithOutput(script) {
            let events = parseEventLines(result)
            await MainActor.run { self.todayEvents = events }
        }
    }
    
    // MARK: - Morning Briefing
    
    func generateMorningBriefing() async -> MorningBriefing {
        await refreshAll()
        
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
            suggestion: generateSuggestion()
        )
    }
    
    private func generateSuggestion() -> String {
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
    
    // MARK: - Helpers
    
    private func runOSAScript(_ script: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }
    
    private func runOSAScriptWithOutput(_ script: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
    
    private func parseTaskLines(_ output: String) -> [ARESTask] {
        var tasks: [ARESTask] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 5 {
                let title = parts[0].trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                tasks.append(ARESTask(
                    title: title,
                    list: parts[1].trimmingCharacters(in: .whitespaces),
                    daysOverdue: Int(parts[2]) ?? 0,
                    priority: Int(parts[3]) ?? 0,
                    reminderID: parts[4].trimmingCharacters(in: .whitespaces)
                ))
            }
        }
        return tasks
    }
    
    private func parseEventLines(_ output: String) -> [ARESEvent] {
        var events: [ARESEvent] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: "|")
            if parts.count >= 4 {
                events.append(ARESEvent(
                    title: parts[0].trimmingCharacters(in: .whitespaces),
                    calendar: parts[1].trimmingCharacters(in: .whitespaces),
                    startDate: Date(),
                    endDate: Date()
                ))
            }
        }
        return events
    }
    
    private func formatAppleScriptDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy h:mm:ss a"
        formatter.locale = Locale(identifier: "en_US")
        return "date \"\(formatter.string(from: date))\""
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

enum RecurrenceRule {
    case daily
    case weekly
    case monthly
    case yearly
    case custom(String)
}

// MARK: - AppleScript String Escaping

extension String {
    var escapedForAppleScript: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
