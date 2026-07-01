import SwiftUI

// MARK: - Morning Briefing View
// Shows today's tasks, calendar events, and suggestions

struct BriefingView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var taskManager = TaskManager.shared
    @State private var briefing: MorningBriefing?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Checking your day...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else if let briefing = briefing {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    headerView(briefing)
                    
                    Divider()
                    
                    // 1-3-5 Plan
                    if !briefing.bigTasks.isEmpty || !briefing.mediumTasks.isEmpty || !briefing.smallTasks.isEmpty {
                        planSection(briefing)
                        Divider()
                    }
                    
                    // Overdue
                    if !briefing.overdueTasks.isEmpty {
                        overdueSection(briefing)
                        Divider()
                    }
                    
                    // Calendar
                    if !briefing.events.isEmpty {
                        calendarSection(briefing)
                        Divider()
                    }
                    
                    // Suggestion
                    suggestionSection(briefing)
                    
                    // Quick Add
                    Divider()
                    quickAddSection()
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Could not load your tasks")
                        .font(.headline)
                    Text("Make sure Reminders.app is running")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        Task { await loadBriefing() }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .task {
            await loadBriefing()
        }
    }
    
    private func loadBriefing() async {
        isLoading = true
        briefing = await taskManager.generateMorningBriefing()
        isLoading = false
    }
    
    private func headerView(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .font(.title)
                    .foregroundColor(.yellow)
                VStack(alignment: .leading) {
                    Text("Good \(timeOfDay()), Matthew")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text(formattedDate(briefing.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 20) {
                statBadge(count: briefing.todayCount, label: "Today", color: .blue)
                statBadge(count: briefing.overdueCount, label: "Overdue", color: .red)
                statBadge(count: briefing.inboxCount, label: "Inbox", color: .orange)
                statBadge(count: briefing.eventCount, label: "Events", color: .green)
            }
        }
    }
    
    private func statBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 50)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func planSection(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Today's Plan", systemImage: "checklist")
                .font(.headline)
            
            if !briefing.bigTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🔴 BIG (1)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                    ForEach(briefing.bigTasks) { task in
                        TaskRow(task: task)
                    }
                }
            }
            
            if !briefing.mediumTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🟡 MEDIUM (\(briefing.mediumTasks.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                    ForEach(briefing.mediumTasks) { task in
                        TaskRow(task: task)
                    }
                }
            }
            
            if !briefing.smallTasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("🟢 SMALL (\(briefing.smallTasks.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                    ForEach(briefing.smallTasks) { task in
                        TaskRow(task: task)
                    }
                }
            }
        }
    }
    
    private func overdueSection(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("⚠️ Overdue", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundColor(.red)
            
            ForEach(briefing.overdueTasks) { task in
                HStack {
                    Text(task.priorityLabel)
                    Text(task.title)
                        .strikethrough(false)
                    Spacer()
                    Text("\(task.daysOverdue)d overdue")
                        .font(.caption)
                        .foregroundColor(.red)
                    Text(task.list)
                        .font(.caption2)
                        .padding(4)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(4)
                }
                .padding(8)
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            }
        }
    }
    
    private func calendarSection(_ briefing: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Today's Calendar", systemImage: "calendar")
                .font(.headline)
            
            ForEach(briefing.events) { event in
                HStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                    Text(event.title)
                    Spacer()
                    Text(event.calendar)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
    
    private func suggestionSection(_ briefing: MorningBriefing) -> some View {
        HStack {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
            Text(briefing.suggestion)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func quickAddSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Add", systemImage: "plus.circle")
                .font(.headline)
            
            HStack {
                TextField("Add task to Inbox...", text: $state.inputText)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)
                
                Button {
                    let text = state.inputText.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { return }
                    Task {
                        let _ = await TaskManager.shared.createTask(title: text)
                        state.inputText = ""
                        await loadBriefing()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(state.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    
    private func timeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "morning"
        case 12..<17: return "afternoon"
        default: return "evening"
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: ARESTask
    
    var body: some View {
        HStack {
            Text(task.priorityLabel)
                .font(.caption)
            Text(task.title)
                .font(.subheadline)
            Spacer()
            Text(task.list)
                .font(.caption2)
                .padding(4)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(4)
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Task List View

struct TaskListView: View {
    @StateObject private var taskManager = TaskManager.shared
    @State private var selectedList = "Today"
    @State private var tasks: [ARESTask] = []
    @State private var isLoading = true
    
    let lists = ["Today", "This Week", "Inbox", "Someday", "Projects"]
    
    var body: some View {
        VStack(spacing: 0) {
            // List selector
            Picker("List", selection: $selectedList) {
                ForEach(lists, id: \.self) { list in
                    Text(list).tag(list)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            if isLoading {
                Spacer()
                ProgressView()
                Spacer()
            } else if tasks.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundColor(.green)
                    Text("All clear!")
                        .font(.headline)
                    Text("No tasks in \(selectedList)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(tasks) { task in
                        TaskDetailRow(task: task, onComplete: {
                            Task {
                                await taskManager.completeTask(reminderID: task.id.uuidString)
                                await refresh()
                            }
                        })
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await refresh()
        }
        .onChange(of: selectedList) { _, _ in
            Task { await refresh() }
        }
    }
    
    private func refresh() async {
        isLoading = true
        await taskManager.refreshAll()
        switch selectedList {
        case "Today": tasks = taskManager.todayTasks
        case "Inbox": tasks = [] // Would need dedicated inbox query
        default: tasks = taskManager.todayTasks
        }
        isLoading = false
    }
}

// MARK: - Task Detail Row

struct TaskDetailRow: View {
    let task: ARESTask
    let onComplete: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading) {
                Text(task.title)
                    .font(.body)
                HStack {
                    Text(task.list)
                        .font(.caption2)
                        .padding(2)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(2)
                    if task.isOverdue {
                        Text("\(task.daysOverdue)d overdue")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            Spacer()
            
            Text(task.priorityLabel)
        }
        .padding(.vertical, 4)
    }
}
