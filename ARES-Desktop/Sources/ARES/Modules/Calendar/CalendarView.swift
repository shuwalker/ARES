import SwiftUI
import EventKit

struct CalendarView: View {
    @StateObject private var module = CalendarModule()
    @State private var showAddEvent = false
    @State private var newTitle = ""
    @State private var newStartDate = Date()
    @State private var newEndDate = Date().addingTimeInterval(3600)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Next 7 Days").font(.title2).bold()
                Spacer()
                Button("Add Event") { showAddEvent = true }
                    .disabled(module.authorizationStatus == .denied)
            }
            .padding()

            if module.authorizationStatus == .notDetermined {
                VStack(spacing: 12) {
                    Text("ARES needs calendar access to show your events.")
                    Button("Allow Access") { Task { await module.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if module.authorizationStatus == .denied {
                Text("Calendar access denied. Enable in System Settings → Privacy → Calendars.")
                    .foregroundColor(.secondary).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if module.upcomingEvents.isEmpty {
                Text("No events in the next 7 days.").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(module.upcomingEvents, id: \.eventIdentifier) { event in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(cgColor: event.calendar.cgColor))
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title ?? "Untitled").fontWeight(.medium)
                            Text(event.startDate, style: .time).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(event.startDate, style: .date).font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventSheet(title: $newTitle, startDate: $newStartDate, endDate: $newEndDate) {
                try? module.addEvent(title: newTitle, startDate: newStartDate, endDate: newEndDate)
                showAddEvent = false
                newTitle = ""
            }
        }
        .task { await module.requestAccess() }
    }
}

struct AddEventSheet: View {
    @Binding var title: String
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New Event").font(.headline)
            TextField("Title", text: $title)
            DatePicker("Start", selection: $startDate)
            DatePicker("End", selection: $endDate)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { onSave() }
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 340)
    }
}
