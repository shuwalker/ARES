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
    @State private var isGeneratingAvatar = false
    @State private var avatarGenerationError: String? = nil

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

                if isGeneratingAvatar {
                    Circle()
                        .fill(ARESColors.gradient)
                        .frame(width: 160, height: 160)
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                } else if let imagePath = appState.avatarImagePath,
                          let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 160, height: 160)
                        .clipShape(Circle())
                } else {
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
            }

            // Voice state label
            Text(appState.voiceState.label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(appState.voiceState.color)

            // Generate Avatar button
            Button(action: generateAvatar) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("GENERATE AVATAR")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .frame(height: 28)
            }
            .buttonStyle(.bordered)
            .tint(ARESColors.gold)
            .disabled(isGeneratingAvatar)

            if let errorMsg = avatarGenerationError {
                Text(errorMsg)
                    .font(.caption2)
                    .foregroundStyle(ARESColors.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 4_000_000_000)
                            avatarGenerationError = nil
                        }
                    }
            }

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
            } else if let messageBus = samRuntime.companionMessageBus {
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
        .task {
            // Idempotent — the conversation lives on SAMRuntime now, so it
            // survives tab switches and only the first appearance creates it.
            samRuntime.ensureCompanionConversation()
        }
        .onAppear {
            // Ensure chat input receives keyboard focus after ChatWidget renders.
            // ChatWidget sets isInputFocused=true internally but the window may not yet
            // be key when CompanionView first appears. We resign first responder and then
            // re-trigger focus after a brief layout pass so the TextEditor wins it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.keyWindow?.makeFirstResponder(nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.firstResponder)
                }
            }
        }
    }

    // MARK: - Avatar Generation

    private func generateAvatar() {
        isGeneratingAvatar = true
        avatarGenerationError = nil

        Task { @MainActor in
            do {
                let service = ALICEImageGenerationService()
                let result = try await service.generate(
                    prompt: "anime sci-fi AI companion, silver hair, glowing orange eyes, white tech-wear spacesuit, helmet visor, NPR cel-shaded illustration, clean background",
                    negativePrompt: "realistic, photo, blur, watermark, text",
                    model: nil,
                    steps: 20,
                    guidanceScale: 7.5,
                    scheduler: "euler_a",
                    seed: nil,
                    width: 512,
                    height: 512
                )
                if let firstPath = result.localPaths.first {
                    appState.avatarImagePath = firstPath
                    UserDefaults.standard.set(firstPath, forKey: "ares_avatar_image_path")
                }
            } catch {
                avatarGenerationError = "Avatar generation failed: \(error.localizedDescription)"
            }
            isGeneratingAvatar = false
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
