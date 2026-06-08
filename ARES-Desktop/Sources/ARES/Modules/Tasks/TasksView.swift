import SwiftUI
import EventKit

struct TasksView: View {
    @StateObject private var module = TasksModule()
    @State private var showAddTask = false
    @State private var newTitle = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks").font(.title2).bold()
                Spacer()
                Button("Add Task") { showAddTask = true }
                    .disabled(module.authorizationStatus == .denied)
            }
            .padding()

            if module.authorizationStatus == .notDetermined {
                VStack(spacing: 12) {
                    Text("ARES needs Reminders access to show your tasks.")
                    Button("Allow Access") { Task { await module.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if module.authorizationStatus == .denied {
                Text("Reminders access denied. Enable in System Settings → Privacy → Reminders.")
                    .foregroundColor(.secondary).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if module.tasks.isEmpty {
                Text("No pending tasks.").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(module.tasks, id: \.calendarItemIdentifier) { task in
                    HStack(spacing: 12) {
                        Button {
                            module.toggleComplete(task)
                        } label: {
                            Image(systemName: "circle")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title ?? "Untitled")
                            if let components = task.dueDateComponents, let date = components.date {
                                Text(date, style: .date).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showAddTask) {
            AddTaskSheet(title: $newTitle, hasDueDate: $hasDueDate, dueDate: $dueDate) {
                try? module.addTask(title: newTitle, dueDate: hasDueDate ? dueDate : nil)
                showAddTask = false
                newTitle = ""
                hasDueDate = false
            }
        }
        .task { await module.requestAccess() }
    }
}

struct AddTaskSheet: View {
    @Binding var title: String
    @Binding var hasDueDate: Bool
    @Binding var dueDate: Date
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New Task").font(.headline)
            TextField("Title", text: $title)
            Toggle("Due Date", isOn: $hasDueDate)
            if hasDueDate { DatePicker("Due", selection: $dueDate, displayedComponents: [.date, .hourAndMinute]) }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { onSave() }
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
