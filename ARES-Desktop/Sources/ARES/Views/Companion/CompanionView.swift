import SwiftUI
import UserInterface
import ConversationEngine
import APIFramework

struct CompanionView: View {
    @EnvironmentObject private var appState: ARESAppState
    @EnvironmentObject private var samRuntime: SAMRuntime
    @EnvironmentObject private var conversationManager: ConversationManager
    @EnvironmentObject private var endpointManager: EndpointManager
    @EnvironmentObject private var sharedConversationService: SharedConversationService

    @State private var avatarPulse = false
    @State private var showStats = false
    @State private var showingMiniPrompts = false
    @State private var activeMessageBus: ConversationMessageBus?
    @State private var hasCreatedConversation = false

    var body: some View {
        HSplitView {
            // Left: ARES avatar + presence (kept intact)
            avatarPanel
                .frame(minWidth: 280, idealWidth: 340)
                .background(ARESColors.background)

            // Right: SAM-powered chat
            samChatPanel
                .frame(minWidth: 440)
        }
        .background(ARESColors.background)
    }

    // MARK: - Avatar (unchanged from original ARES)

    private var avatarPanel: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(appState.voiceState.color.opacity(0.4), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(avatarPulse ? 1.12 : 1.0)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                               value: avatarPulse)

                Circle()
                    .fill(ARESColors.background)
                    .frame(width: 180, height: 180)

                Circle()
                    .fill(ARESColors.gradient)
                    .frame(width: 160, height: 160)

                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // Voice state label
            Text(appState.voiceState.label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(appState.voiceState.color)

            Spacer()

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
            .padding(.bottom, 40)
        }
        .onAppear { avatarPulse = true }
    }

    // MARK: - SAM Chat Panel

    private var samChatPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(appState.voiceState.color)
                    .frame(width: 8, height: 8)
                Text("HERMES")
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

            // Content: SAM Chat or stats
            if showStats {
                statsGrid
            } else if let messageBus = activeMessageBus {
                ChatWidget(
                    activeConversation: conversationManager.activeConversation,
                    messageBus: messageBus,
                    showingMiniPrompts: $showingMiniPrompts
                )
                .environmentObject(endpointManager)
                .environmentObject(conversationManager)
                .environmentObject(sharedConversationService)
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "shield.righthalf.filled")
                        .font(.largeTitle)
                        .foregroundStyle(ARESColors.gold.opacity(0.4))
                    Text("Hermes Ready")
                        .font(.subheadline)
                        .foregroundStyle(ARESColors.textTertiary)
                    Spacer()
                }
            }
        }
        .background(ARESColors.surface)
        .onAppear {
            if !hasCreatedConversation {
                activeMessageBus = samRuntime.createConversation()
                hasCreatedConversation = true
            }
        }
    }

    // MARK: - Stats (unchanged)

    private var statsGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatCard(
                    title: "SESSIONS",
                    value: "\(appState.sessionCount)",
                    icon: "bubble.left.and.bubble.right",
                    color: ARESColors.gold
                )
                StatCard(
                    title: "SKILLS",
                    value: "\(appState.skillCount)",
                    icon: "book.closed",
                    color: ARESColors.accent
                )
                StatCard(
                    title: "MEMORY",
                    value: "\(appState.memoryPercent)%",
                    icon: "brain.head.profile",
                    color: ARESColors.green
                )
                StatCard(
                    title: "AGENTS",
                    value: "\(appState.activeOfficeAgents)",
                    icon: "person.3",
                    color: ARESColors.purple
                )
            }
            .padding(16)
        }
    }
}
