import SwiftUI

/// Root view that switches between Manual and Avatar Twin modes.
///
/// **Manual mode** — Native SwiftUI dashboard. Sidebar on left, content on right.
/// Sessions, Skills, Cron, Config, Logs — all real data from Hermes Dashboard API.
/// No WKWebView. No shortcuts. Native Metal-rendered SwiftUI.
///
/// **Avatar Twin mode** — Companion conversation. Face shows state (thinking,
/// listening, speaking). CaptionOverlay, ControlsIsland, ChatStream floating
/// over the avatar. The chat IS the companion. Not the face.
struct ARESRootView: View {
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @State private var currentStyle: AvatarStyle = .blackFire
    @State private var selectedPage: DashboardPage = .chat
    @State private var sidebarCollapsed = false
    @State private var cognitiveExpanded = false
    @State private var chatVisible = true

    var body: some View {
        BootGate {
            ZStack {
                backgroundLayer

                if brain.immersionLevel.showsOperatorDashboard {
                    manualLayout
                } else {
                    avatarTwinLayout
                }
            }
        }
        .task { brain.connect() }
        .onChange(of: voice.transcript) { _, text in
            if !text.isEmpty && !voice.isListening {
                brain.sendMessage(text)
            }
        }
        .onChange(of: voice.isSpeaking) { _, speaking in
            // Lip-sync feedback: voice TTS drives face state
            brain.isSpeaking = speaking
            brain.intensity = speaking ? FaceConfig.config(for: .speaking).intensity : 0.2
            brain.agentState = speaking ? .speaking : .idle
            brain.avatarExpression = speaking ? .happy : .neutral
        }
        .onChange(of: brain.immersionLevel) { _, newLevel in
            if newLevel == .avatarTwin {
                selectedPage = .chat
                cognitiveExpanded = false
            }
        }
    }

    // MARK: - Manual Layout

    /// Native SwiftUI dashboard. Sidebar + content area.
    /// In manual mode, no avatar is rendered behind pages.
    private var manualLayout: some View {
        HStack(spacing: 0) {
            SidebarView(
                selectedPage: $selectedPage,
                isCollapsed: $sidebarCollapsed
            )
            
            VStack(spacing: 0) {
                // Top bar: immersion slider
                ImmersionBar(cognitiveExpanded: $cognitiveExpanded)
                
                // Expandable cognitive panel
                if cognitiveExpanded {
                    CognitiveActivityPanel()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Content area — no avatar behind pages in manual mode
                manualPageContent
                    .transition(.opacity)
            }
        }
    }
    
    /// The actual dashboard pages — native SwiftUI views, not web views.
    @ViewBuilder
    private var manualPageContent: some View {
        switch selectedPage {
        case .chat:
            ChatPage()
        case .tasks:
            TaskRunnerView()
        case .memory:
            MemoryInspectorView()
        case .sessions:
            SessionsView()
        case .skills:
            SkillsView()
        case .cron:
            CronView()
        case .logs:
            LogsView()
        case .config:
            ConfigView()
        }
    }

    // MARK: - Avatar Twin Layout

    /// Companion mode: full-screen face with floating overlays.
    private var avatarTwinLayout: some View {
        ZStack {
            AvatarSceneView(style: $currentStyle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            VStack {
                CaptionOverlay()
                Spacer()
            }

            // Stream overlay — top-right, shows what ARES is doing
            VStack {
                HStack {
                    Spacer()
                    StreamOverlay()
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
                Spacer()
            }

            VStack {
                Spacer()
                if chatVisible {
                    VStack(spacing: 8) {
                        ChatStream()
                            .frame(maxHeight: 280)
                        CommandBar()
                    }
                    .padding(.horizontal, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ControlsIsland()
                    .padding(.bottom, 12)
                HStack(spacing: 4) {
                    Image(systemName: ImmersionLevel.manual.icon)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    ImmersionBar(cognitiveExpanded: $cognitiveExpanded)
                        .frame(width: 140)
                    Image(systemName: ImmersionLevel.avatarTwin.icon)
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 8)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                chatVisible.toggle()
            }
        }
    }

    // MARK: - Background

    @ViewBuilder
    var backgroundLayer: some View {
        if brain.immersionLevel.isFullScreen {
            Color.black.ignoresSafeArea()
        } else {
            VisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Chat Page (Session Browser + Messages + Drawer)

/// Full chat page with three panels:
///   - Left: Session browser (like Hermes sidebar)
///   - Center: Messages + input
///   - Right: Terminal / Files drawer (collapsible)
struct ChatPage: View {
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @State private var selectedSessionID: String?
    @State private var drawerVisible = true
    @State private var drawerTab: DrawerTab = .terminal

    enum DrawerTab: String, CaseIterable {
        case terminal = "Terminal"
        case files = "Files"
        case info = "Info"

        var icon: String {
            switch self {
            case .terminal: return "terminal.fill"
            case .files: return "folder.fill"
            case .info: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: Session Browser ──
            SessionBrowser(selectedSessionID: $selectedSessionID)
                .frame(width: 240)
                .background(Color.black.opacity(0.2))

            // ── Center: Chat Stream (full bleed) ──
            VStack(spacing: 0) {
                ZStack {
                    ChatStream()
                        .frame(maxHeight: .infinity)
                    // Thinking/streaming status overlay at top center
                    if brain.agentState == .thinking {
                        thinkingBadge
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, 8)
                    }
                }

                CommandBar()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
            }
            .frame(minWidth: 400)

            // ── Right: Drawer ──
            if drawerVisible {
                drawerPanel
                    .frame(width: 260)
                    .background(Color.black.opacity(0.25))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: drawerVisible)
    }

    // MARK: - Thinking Badge

    private var thinkingBadge: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
            Text("ARES is thinking...")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.5))
                .background(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .stroke(ARESPalette.accent.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Drawer Panel

    private var drawerPanel: some View {
        VStack(spacing: 0) {
            // Drawer tabs
            HStack(spacing: 0) {
                ForEach(DrawerTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            drawerTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(drawerTab == tab ? ARESPalette.accent : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            drawerTab == tab
                            ? ARESPalette.accent.opacity(0.08)
                            : Color.clear
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Close drawer button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        drawerVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help("Close drawer")
            }
            .background(Color.black.opacity(0.15))

            Divider()
                .background(ARESPalette.surfaceBorder)

            // Drawer content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch drawerTab {
                    case .terminal:
                        terminalPlaceholder
                    case .files:
                        filesPlaceholder
                    case .info:
                        infoPlaceholder
                    }
                }
                .padding(12)
            }
        }
    }

    private var terminalPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Terminal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Session terminal output will appear here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineLimit(nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filesPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Attached Files")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No files attached to this session.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var infoPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("Model", brain.currentModel.isEmpty ? "—" : brain.currentModel)
            infoRow("State", brain.agentState.description)
            infoRow("Messages", "\(brain.messages.count)")
            infoRow("Backend", brain.backendConnected ? "Online" : "Offline")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - Session Browser

/// Left panel showing Hermes sessions from the dashboard API.
/// Mimics Hermes Web UI session sidebar with search + grouped list.
struct SessionBrowser: View {
    @Binding var selectedSessionID: String?
    @State private var sessions: [Session] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    var filteredSessions: [Session] {
        if searchText.isEmpty { return sessions }
        return sessions.filter { s in
            (s.preview?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            s.id.localizedCaseInsensitiveContains(searchText) ||
            (s.model?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sessions")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    loadSessions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
                .background(ARESPalette.surfaceBorder)

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("Search sessions...", text: $searchText)
                    .font(.system(size: 11))
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider()
                .background(ARESPalette.surfaceBorder)

            // Session list
            if isLoading {
                Spacer()
                ProgressView("Loading...")
                    .controlSize(.small)
                    .scaleEffect(0.8)
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Button("Retry") { loadSessions() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
            } else if filteredSessions.isEmpty {
                Spacer()
                Text(sessions.isEmpty ? "No sessions" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredSessions) { session in
                            SessionBrowserRow(
                                session: session,
                                isSelected: selectedSessionID == session.id
                            )
                            .onTapGesture {
                                selectedSessionID = session.id
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Bottom: count
            if !sessions.isEmpty {
                Divider()
                    .background(ARESPalette.surfaceBorder)
                HStack {
                    Text("\(filteredSessions.count) sessions")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .onAppear { loadSessions() }
    }

    private func loadSessions() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                sessions = try await HermesDashboardService.shared.listSessions(query: searchText)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct SessionBrowserRow: View {
    let session: Session
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // Status dot
            Circle()
                .fill(session.isActive == true ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.preview ?? "Session \(session.id.prefix(8))...")
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.primary.opacity(0.7))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let model = session.model {
                        Text(model)
                            .font(.system(size: 9))
                            .foregroundStyle(.cyan.opacity(0.7))
                    }
                    if let count = session.messageCount {
                        Text("\(count)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let last = session.lastActive {
                Text(formatTimestamp(last))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.4))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected
                      ? ARESPalette.accent.opacity(0.1)
                      : (isHovered ? Color.white.opacity(0.04) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? ARESPalette.accent.opacity(0.25) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Visual Effect

/// Visual effect backdrop
struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
