import SwiftUI

struct CompanionView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var personalityExpanded = false
    @State private var avatarPulse = false
    @State private var showStats = false
    @FocusState private var chatFocused: Bool

    var body: some View {
        HSplitView {
            // Left: Avatar + presence
            avatarPanel
                .frame(minWidth: 280, idealWidth: 340)
                .background(ARESColors.background)

            // Right: Chat (always visible)
            chatPanel
                .frame(minWidth: 440)
                .background(ARESColors.surface)
        }
        .background(ARESColors.background)
    }

    // MARK: - Avatar

    private var avatarPanel: some View {
        VStack(spacing: 24) {
            Spacer()

            // Core avatar
            ZStack {
                // Outer ring — breathing
                Circle()
                    .stroke(appState.voiceState.color.opacity(0.4), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(avatarPulse ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                               value: avatarPulse)

                // Mid ring
                Circle()
                    .fill(ARESColors.background)
                    .frame(width: 180, height: 180)

                // Inner circle
                Circle()
                    .fill(ARESColors.gradient)
                    .frame(width: 160, height: 160)

                // Spartan helmet silhouette
                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: appState.voiceState.color.opacity(0.5), radius: 20)

                // Voice dot
                Circle()
                    .fill(appState.voiceState.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(appState.voiceState.color.opacity(0.4), lineWidth: 3)
                            .scaleEffect(appState.voiceState == .speaking ? 1.8 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(),
                                       value: appState.voiceState == .speaking)
                    )
                    .offset(x: 55, y: 55)
            }
            .padding(.bottom, 8)

            // Nameplate
            Text("ARES")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(ARESColors.textPrimary)
                .tracking(4)

            // Voice state
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.voiceState.color)
                    .frame(width: 6, height: 6)
                Text(appState.voiceState.label.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .tracking(2)
                    .foregroundStyle(appState.voiceState.color)
            }

            Spacer()

            // Quick actions
            HStack(spacing: 16) {
                Button(action: { appState.voiceState = .listening }) {
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill")
                        Text("TALK")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(1)
                    }
                    .frame(width: 100, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(ARESColors.accent)
                .disabled(appState.voiceState == .listening)

                Button(action: { showStats.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                        Text(showStats ? "HIDE" : "STATS")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(1)
                    }
                    .frame(width: 100, height: 36)
                }
                .buttonStyle(.bordered)
                .tint(showStats ? ARESColors.gold : ARESColors.textSecondary)
            }
            .padding(.bottom, 40)
        }
        .onAppear { avatarPulse = true }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Header with stats toggle
            HStack {
                Circle()
                    .fill(appState.voiceState.color)
                    .frame(width: 8, height: 8)
                Text("ARES CHAT")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(ARESColors.textSecondary)
                Spacer()
                Button(action: { showStats.toggle() }) {
                    Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                        .font(.caption)
                        .foregroundStyle(ARESColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().background(ARESColors.divider)

            // Content: stats or messages
            if showStats {
                statsGrid
            } else {
                messagesArea
            }
        }
    }

    private var messagesArea: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if appState.chatMessages.isEmpty {
                            VStack(spacing: 10) {
                                Spacer().frame(height: 30)
                                Image(systemName: "shield.righthalf.filled")
                                    .font(.largeTitle)
                                    .foregroundStyle(ARESColors.gold.opacity(0.4))
                                Text("Speak to ARES.")
                                    .font(.subheadline)
                                    .foregroundStyle(ARESColors.textTertiary)
                                Text("Type your message below.")
                                    .font(.caption)
                                    .foregroundStyle(ARESColors.textTertiary.opacity(0.6))
                            }
                        }

                        ForEach(appState.chatMessages) { msg in
                            HStack {
                                if msg.role == .assistant {
                                    ChatBubbleView(bubble: msg)
                                    Spacer(minLength: 60)
                                } else {
                                    Spacer(minLength: 60)
                                    ChatBubbleView(bubble: msg)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if appState.isChatProcessing {
                            HStack {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .tint(ARESColors.gold)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(ARESColors.textTertiary)
                                }
                                .padding(10)
                                .background(ARESColors.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                Spacer(minLength: 60)
                            }
                            .padding(.horizontal, 16)
                            .id("thinking")
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onChange(of: appState.chatMessages.count) { _, _ in
                    if let last = appState.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id) }
                    }
                }
                .onChange(of: appState.isChatProcessing) { _, _ in
                    withAnimation { proxy.scrollTo("thinking") }
                }
            }

            Divider().background(ARESColors.divider)

            // Input
            HStack(spacing: 8) {
                TextField("Message ARES...", text: $appState.chatInput)
                    .textFieldStyle(.plain)
                    .focused($chatFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(ARESColors.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ARESColors.divider, lineWidth: 1)
                    )
                    .disabled(appState.isChatProcessing)
                    .onSubmit { appState.sendChat() }

                Button(action: { appState.sendChat() }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(
                            appState.chatInput.isEmpty || appState.isChatProcessing
                                ? ARESColors.textTertiary
                                : ARESColors.gold
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(appState.chatInput.isEmpty || appState.isChatProcessing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    StatusCard(
                        title: "SKILLS",
                        value: "\(appState.skillCount)",
                        subtitle: "optimized",
                        icon: "bolt.fill",
                        color: ARESColors.gold
                    )
                    StatusCard(
                        title: "SESSIONS",
                        value: "\(appState.sessionCount)",
                        subtitle: "today",
                        icon: "bubble.left.and.bubble.right.fill",
                        color: ARESColors.purple
                    )
                    StatusCard(
                        title: "MEMORY",
                        value: "\(appState.memoryPercent)%",
                        subtitle: "capacity",
                        icon: "brain.head.profile.fill",
                        color: ARESColors.orange
                    )
                    StatusCard(
                        title: "HERMES",
                        value: appState.hermesRunning ? "ONLINE" : "OFFLINE",
                        subtitle: appState.hermesRunning ? "connected" : "unreachable",
                        icon: appState.hermesRunning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                        color: appState.hermesRunning ? ARESColors.green : ARESColors.red
                    )
                }

                Divider().background(ARESColors.divider)

                // Self-model
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: { withAnimation { personalityExpanded.toggle() } }) {
                        HStack {
                            Image(systemName: "scroll.fill")
                                .foregroundStyle(ARESColors.gold)
                            Text("WHAT ARES KNOWS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .tracking(2)
                                .foregroundStyle(ARESColors.textSecondary)
                            Spacer()
                            Image(systemName: personalityExpanded ? "chevron.down" : "chevron.right")
                                .foregroundStyle(ARESColors.textSecondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)

                    if personalityExpanded {
                        if appState.selfModelContent.isEmpty {
                            Text("No self-model yet. Run self-reflection to build your profile.")
                                .font(.caption)
                                .foregroundStyle(ARESColors.textTertiary)
                                .padding(.leading, 4)
                        } else {
                            Text(appState.selfModelContent)
                                .font(.callout)
                                .foregroundStyle(ARESColors.textSecondary)
                                .lineLimit(nil)
                                .padding(14)
                                .background(ARESColors.surfaceElevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(ARESColors.gold.opacity(0.2), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 16)

                Divider().background(ARESColors.divider)
                    .padding(.horizontal, 16)

                // Quick links
                VStack(alignment: .leading, spacing: 8) {
                    Text("QUICK LINKS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textSecondary)

                    SpartanLink("Hermes WebUI", url: "http://localhost:9119", icon: "globe")
                    SpartanLink("SearXNG Search", url: "http://localhost:8080", icon: "magnifyingglass")
                    SpartanLink("Ollama Models", url: "http://localhost:11434", icon: "cpu.fill")
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 24)
            }
            .padding(.vertical, 20)
        }
    }
}

// MARK: - Chat bubble

struct ChatBubbleView: View {
    let bubble: ChatBubble

    var body: some View {
        VStack(alignment: bubble.role == .user ? .trailing : .leading, spacing: 2) {
            Text(bubble.role == .user ? "YOU" : "ARES")
                .font(.system(size: 8))
                .fontWeight(.bold)
                .tracking(1.5)
                .foregroundStyle(bubble.role == .user ? ARESColors.textTertiary : ARESColors.gold)

            Text(bubble.content)
                .font(.callout)
                .foregroundStyle(ARESColors.textPrimary)
                .padding(10)
                .background(
                    bubble.role == .user
                        ? ARESColors.accent.opacity(0.2)
                        : ARESColors.surfaceElevated
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Spartan Status Card

struct StatusCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Spacer()
                Text(title)
                    .font(.system(size: 9))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(ARESColors.textTertiary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(ARESColors.textPrimary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(ARESColors.textTertiary)
        }
        .padding(14)
        .background(ARESColors.surfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Spartan Link

struct SpartanLink: View {
    let label: String
    let url: String
    let icon: String

    init(_ label: String, url: String, icon: String) {
        self.label = label
        self.url = url
        self.icon = icon
    }

    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(ARESColors.textSecondary)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(ARESColors.textSecondary)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundStyle(ARESColors.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ARESColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ARES Design System

struct ARESColors {
    // Spartan palette — dark cinematic, C# minor energy
    static let background   = Color(red: 0.06, green: 0.06, blue: 0.08)  // near-black
    static let surface      = Color(red: 0.09, green: 0.09, blue: 0.12)  // dark grey
    static let surfaceElevated = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let textPrimary  = Color(white: 0.92)
    static let textSecondary = Color(white: 0.65)
    static let textTertiary = Color(white: 0.40)
    static let accent       = Color(red: 0.85, green: 0.25, blue: 0.20)  // Spartan crimson
    static let gold          = Color(red: 0.82, green: 0.67, blue: 0.28)  // Spartan gold
    static let green         = Color(red: 0.20, green: 0.78, blue: 0.35)
    static let red           = Color(red: 0.85, green: 0.25, blue: 0.20)
    static let orange        = Color(red: 0.88, green: 0.50, blue: 0.15)
    static let purple        = Color(red: 0.55, green: 0.30, blue: 0.85)
    static let divider       = Color(white: 0.15)
    static let gradient      = Color(red: 0.25, green: 0.25, blue: 0.35)
}
