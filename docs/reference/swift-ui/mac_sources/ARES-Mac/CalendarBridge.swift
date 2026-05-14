import Foundation
import EventKit

class CalendarBridge {
    private let store = EKEventStore()
    private var authorized = false
    
    init() {
        requestAccess()
    }
    
    func requestAccess() {
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.authorized = granted
                if let error = error {
                    Logger().error("Calendar access denied: \(error)")
                }
            }
        }
    }
    
    func fetchTodaySchedule() -> String {
        guard authorized else { return "Calendar access not authorized" }
        
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
        
        guard !events.isEmpty else { return "No events today" }
        
        return events.map { event in
            let time = event.startDate.formatted(date: .omitted, time: .shortened)
            let duration = event.endDate.timeIntervalSince(event.startDate)
            let durStr = duration >= 3600
                ? "\(Int(duration / 3600))h"
                : "\(Int(duration / 60))m"
            return "  \(time) (\(durStr)) - \(event.title ?? "Untitled")"
        }.joined(separator: "\n")
    }
}
