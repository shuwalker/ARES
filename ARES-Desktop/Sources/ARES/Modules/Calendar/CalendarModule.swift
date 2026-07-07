import Foundation
import EventKit
import Combine
import os

@MainActor
final class CalendarModule: ObservableObject {
    @Published var upcomingEvents: [EKEvent] = []
    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?

    private let store = EKEventStore()
    private let logger = Logger(subsystem: "com.ares", category: "CalendarModule")

    func requestAccess() async {
        do {
            let granted: Bool
            if #available(macOS 14.0, *) {
                granted = try await store.requestFullAccessToEvents()
            } else {
                granted = try await store.requestAccess(to: .event)
            }
            authorizationStatus = granted ? .fullAccess : .denied
            if granted { await fetchUpcomingEvents() }
        } catch {
            logger.error("Calendar access error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    func fetchUpcomingEvents() async {
        let now = Date()
        let weekLater = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: now, end: weekLater, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
        self.upcomingEvents = events
    }

    func addEvent(title: String, startDate: Date, endDate: Date) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent)
        Task { await fetchUpcomingEvents() }
    }
}
