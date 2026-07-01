import SwiftUI

struct HermexView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable {
        case dashboard, briefing, chat, sessions, workspace, memory, skills, tasks, automations, usage, settings

        var icon: String {
            switch self {
            case .dashboard: return "square.grid.2x2.fill"
            case .briefing: return "sun.max.fill"
            case .chat: return "message.fill"
            case .sessions: return "clock.fill"
            case .workspace: return "folder.fill"
            case .memory: return "brain"
            case .skills: return "wrench.and.hammer.fill"
            case .tasks: return "checklist"
            case .automations: return "gearshape.2.fill"
            case .usage: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }

        var label: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .briefing: return "Briefing"
            case .chat: return "Chat"
            case .sessions: return "Sessions"
            case .workspace: return "Files"
            case .memory: return "Memory"
            case .skills: return "Skills"
            case .tasks: return "Tasks"
            case .automations: return "Auto"
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
                case .dashboard: DashboardView()
                case .briefing: BriefingView()
                case .chat: ChatView()
                case .sessions: SessionsView()
                case .workspace: WorkspaceView()
                case .memory: MemoryView()
                case .skills: SkillsView()
                case .tasks: TasksView()
                case .automations: AutomationsView()
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
                // Quick engine switcher
                Menu {
                    ForEach(state.router.availableEngines, id: \.self) { engineId in
                        Button {
                            state.activeEngine = engineId
                        } label: {
                            if engineId == state.activeEngine {
                                Label(engineId.capitalized, systemImage: "checkmark")
                            } else {
                                Text(engineId.capitalized)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "cpu")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Switch AI engine")

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
            if state.messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No messages yet")
                        .font(.headline)
                    Text("Start a conversation in Chat")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                HStack {
                    Image(systemName: "message.fill")
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text("Current Session")
                            .fontWeight(.medium)
                        Text("\(state.messages.count) messages • \(state.activeEngine)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if state.isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
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
    @EnvironmentObject var state: AppState
    @State private var period = 0

    var body: some View {
        VStack(spacing: 16) {
            Picker("Period", selection: $period) {
                Text("Today").tag(0)
                Text("7 Days").tag(1)
                Text("30 Days").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(spacing: 8) {
                let userMessages = state.messages.filter { $0.role == "user" }.count
                let aresMessages = state.messages.filter { $0.role == "ares" }.count
                let totalChars = state.messages.reduce(0) { $0 + $1.content.count }
                let approxInputTokens = state.messages.filter { $0.role == "user" }.reduce(0) { $0 + $1.content.count / 4 }
                let approxOutputTokens = state.messages.filter { $0.role == "ares" }.reduce(0) { $0 + $1.content.count / 4 }

                StatRow("Messages", "\(state.messages.count)")
                StatRow("User Messages", "\(userMessages)")
                StatRow("ARES Responses", "\(aresMessages)")
                StatRow("Active Engine", state.activeEngine)
                StatRow("Total Chars", "\(totalChars)")
                StatRow("Est. Input Tokens", "\(approxInputTokens)")
                StatRow("Est. Output Tokens", "\(approxOutputTokens)")
                StatRow("Est. Total Tokens", "\(approxInputTokens + approxOutputTokens)")
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
    @State private var gatewayOnline = false
    @State private var checkingHealth = false

    var body: some View {
        Form {
            Section("Server") {
                HStack {
                    Text("Status")
                    Spacer()
                    if checkingHealth {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Checking...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if gatewayOnline {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Offline", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
                HStack {
                    Text("URL")
                    Spacer()
                    Text(state.gateway.baseURL)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("AI Engine") {
                ModelPickerView()
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
        .onAppear {
            checkGatewayHealth()
        }
    }

    private func checkGatewayHealth() {
        checkingHealth = true
        Task {
            do {
                gatewayOnline = try await state.gateway.health()
            } catch {
                gatewayOnline = false
            }
            checkingHealth = false
        }
    }
}

// MARK: - Model Picker Widget

struct ModelPickerView: View {
    @EnvironmentObject var state: AppState
    @State private var engineStatuses: [(id: String, name: String, available: Bool)] = []
    @State private var checkingEngines = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Active engine display
            HStack {
                Image(systemName: "cpu.fill")
                    .foregroundColor(.accentColor)
                Text("Active Engine")
                    .font(.headline)
                Spacer()
                Text(state.activeEngine.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(6)
            }

            // Engine selector
            if engineStatuses.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking engines...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(engineStatuses, id: \.id) { engine in
                    Button {
                        state.activeEngine = engine.id
                    } label: {
                        HStack {
                            Image(systemName: engine.id == state.activeEngine ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(engine.id == state.activeEngine ? .accentColor : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(engine.id)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if checkingEngines {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            } else {
                                Circle()
                                    .fill(engine.available ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Info text
            Text("Switching engines routes the next message through the selected AI. Lower-priority engines are fallbacks.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .onAppear {
            checkEngines()
        }
    }

    private func checkEngines() {
        checkingEngines = true
        let engines = state.router.availableEngines
        engineStatuses = engines.map { id in
            (id: id, name: id.capitalized, available: false)
        }

        Task {
            var results: [(id: String, name: String, available: Bool)] = []
            for id in engines {
                // For display, use a friendly name
                let displayName: String
                switch id.lowercased() {
                case "hermes": displayName = "Hermes Agent"
                case "claude-cli": displayName = "Claude Code CLI"
                case "claude": displayName = "Claude (Anthropic)"
                case "gemini": displayName = "Google Gemini"
                case "local": displayName = "Local (Ollama)"
                default: displayName = id.capitalized
                }
                // Quick availability probe
                let isAvailable = await probeEngine(id)
                results.append((id: id, name: displayName, available: isAvailable))
            }
            await MainActor.run {
                engineStatuses = results
                checkingEngines = false
            }
        }
    }

    private func probeEngine(_ id: String) async -> Bool {
        // Use the router's checkAvailability by finding the engine
        // Since AIEngine.checkAvailability is on the protocol, we'd need access.
        // For now, do a simple heuristic: if it's local/ollama, check the port.
        switch id.lowercased() {
        case "hermes":
            let health = try? await state.gateway.health()
            return health ?? false
        case "local":
            let url = URL(string: "http://localhost:11434/api/tags")!
            return (try? await URLSession.shared.data(from: url))
                .map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        case "claude-cli":
            return FileManager.default.isExecutableFile(atPath: NSHomeDirectory() + "/.local/bin/claude")
        default:
            return true // Assume cloud engines are available if registered
        }
    }
}
