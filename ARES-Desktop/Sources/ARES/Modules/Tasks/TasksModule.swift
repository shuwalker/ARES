import Foundation
import EventKit
import Combine
import os

@MainActor
final class TasksModule: ObservableObject {
    @Published var tasks: [EKReminder] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.ares", category: "TasksModule")

    func requestAccess() async {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToReminders()
            } else {
                granted = try await store.requestAccess(to: .reminder)
            }
            authorizationStatus = granted ? .fullAccess : .denied
            if granted { await fetchTasks() }
        } catch {
            logger.error("Reminders access error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func fetchTasks() async {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { [weak self] reminders in
                Task { @MainActor in
                    self?.tasks = (reminders ?? []).sorted { r1, r2 in
                        (r1.dueDateComponents?.date ?? Date.distantFuture) < (r2.dueDateComponents?.date ?? Date.distantFuture)
                    }
                    continuation.resume()
                }
            }
        }
    }

    func toggleComplete(_ reminder: EKReminder) {
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            tasks.removeAll { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }
        } catch {
            logger.error("Failed to save reminder: \(error.localizedDescription)")
        }
    }

    func addTask(title: String, dueDate: Date?) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: due)
        }
        try store.save(reminder, commit: true)
        Task { await fetchTasks() }
    }
}
