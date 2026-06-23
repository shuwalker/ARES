import SwiftUI

struct HermexView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab: Tab = .chat

    enum Tab: String, CaseIterable {
        case briefing, chat, sessions, workspace, memory, skills, tasks, usage, settings

        var icon: String {
            switch self {
            case .briefing: return "sun.max.fill"
            case .chat: return "message.fill"
            case .sessions: return "clock.fill"
            case .workspace: return "folder.fill"
            case .memory: return "brain"
            case .skills: return "wrench.and.hammer.fill"
            case .tasks: return "checklist"
            case .usage: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var label: String {
            switch self {
            case .briefing: return "Briefing"
            case .chat: return "Chat"
            case .sessions: return "Sessions"
            case .workspace: return "Files"
            case .memory: return "Memory"
            case .skills: return "Skills"
            case .tasks: return "Tasks"
            case .usage: return "Usage"
            case .settings: return "Settings"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Content
            ZStack {
                switch selectedTab {
                case .briefing: BriefingView()
                case .chat: ChatView()
                case .sessions: SessionsView()
                case .workspace: WorkspaceView()
                case .memory: MemoryView()
                case .skills: SkillsView()
                case .tasks: TasksView()
                case .usage: UsageView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Tab bar
            Divider()
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                            Text(tab.label)
                                .font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Chat View

struct ChatView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.messages) { msg in
                        HStack {
                            if msg.role == "user" {
                                Spacer()
                                Text(msg.content)
                                    .font(.body)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(Color.accentColor.opacity(0.12))
                                    .cornerRadius(14)
                            } else {
                                Text(msg.content)
                                    .font(.body)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                Spacer()
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    if state.isProcessing {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }

            Divider()
            HStack(spacing: 8) {
                TextField("Ask anything...", text: $state.inputText)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(10)
                    .onSubmit {
                        let t = state.inputText.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        state.send(t)
                    }

                Button {
                    let t = state.inputText.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    state.send(t)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .disabled(state.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Placeholder Views

struct SessionsView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        List {
            ForEach(0..<5, id: \.self) { i in
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading) {
                        Text("Session \(i + 1)")
                            .fontWeight(.medium)
                        Text("\(i + 1) messages • Desktop")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(i + 1)m ago")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.plain)
    }
}

struct WorkspaceView: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search files...", text: .constant(""))
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .padding()

            List {
                ForEach(["workspace/", "Desktop/", "Downloads/", "Documents/"], id: \.self) { item in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(item)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
    }
}

struct MemoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Memory")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal)

            List {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text("User Profile")
                            .fontWeight(.medium)
                        Text("Modified 2h ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Image(systemName: "brain")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text("Preferences")
                            .fontWeight(.medium)
                        Text("Modified 1d ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
            }
            .listStyle(.plain)
        }
        .padding(.top)
    }
}

struct SkillsView: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search skills...", text: .constant(""))
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
            .padding()

            List {
                Section("Apple") {
                    SkillRow("apple-ecosystem", "Apple ecosystem integration")
                    SkillRow("apple-mail", "Mail management")
                    SkillRow("apple-notes", "Notes management")
                    SkillRow("apple-reminders", "Reminders management")
                }
                Section("Productivity") {
                    SkillRow("calendar", "Calendar operations")
                    SkillRow("tasks", "Task management")
                }
            }
            .listStyle(.sidebar)
        }
    }
}

struct SkillRow: View {
    let name: String
    let desc: String

    init(_ name: String, _ desc: String) {
        self.name = name
        self.desc = desc
    }

    var body: some View {
        HStack {
            Image(systemName: "hammer.fill")
                .foregroundColor(.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(name)
                    .fontWeight(.medium)
                Text(desc)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TasksView: View {
    var body: some View {
        List {
            HStack {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Review morning check-in")
                Spacer()
                Text("Today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack {
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text("Update YouTube pipeline")
                Spacer()
                Text("Tomorrow")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.plain)
        .padding()
    }
}

struct UsageView: View {
    var body: some View {
        VStack(spacing: 16) {
            Picker("Period", selection: .constant(0)) {
                Text("Today").tag(0)
                Text("7 Days").tag(1)
                Text("30 Days").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(spacing: 8) {
                StatRow("Sessions", "12")
                StatRow("Messages", "47")
                StatRow("Input Tokens", "28.4K")
                StatRow("Output Tokens", "15.2K")
                StatRow("Total Tokens", "43.6K")
                StatRow("Estimated Cost", "$0.08")
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            .padding(.horizontal)
        }
        .padding(.top)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Server") {
                HStack {
                    Text("Status")
                    Spacer()
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                HStack {
                    Text("URL")
                    Spacer()
                    Text("http://localhost:8642")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Appearance") {
                HStack {
                    Text("Theme")
                    Spacer()
                    Text("Dark")
                        .foregroundColor(.secondary)
                }
            }

            Section("App") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("0.1.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
