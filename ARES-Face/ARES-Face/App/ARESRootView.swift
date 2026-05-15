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
    /// Each page fetches real data from Hermes Dashboard API (:9119).
    private var manualLayout: some View {
        HStack(spacing: 0) {
            SidebarView(selectedPage: $selectedPage)
            
            VStack(spacing: 0) {
                // Top bar: immersion slider
                ImmersionBar(cognitiveExpanded: $cognitiveExpanded)
                
                // Expandable cognitive panel
                if cognitiveExpanded {
                    CognitiveActivityPanel()
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // Content
                ZStack {
                    // Avatar always renders behind content
                    AvatarSceneView(style: $currentStyle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    // Dashboard pages overlay
                    manualPageContent
                        .transition(.opacity)
                }
            }
        }
    }
    
    /// The actual dashboard pages — native SwiftUI views, not web views.
    @ViewBuilder
    private var manualPageContent: some View {
        switch selectedPage {
        case .chat:
            VStack(spacing: 0) {
                ChatStream()
                    .frame(maxHeight: .infinity)
                CommandBar()
            }
        case .orchestration:
            OrchestrationView()
        case .tasks:
            TaskRunnerView()
        case .memory:
            MemoryInspectorView()
        case .feeds:
            FeedsView()
        case .activity:
            ActivityTimelineView()
        case .avatar:
            AvatarConfiguratorView(currentStyle: $currentStyle)
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
        case .persona:
            PersonaSlidersView()
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
                            .frame(maxHeight: 180)
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

// MARK: - Placeholder

struct PlaceholderPage: View {
    let title: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(title)
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("coming soon")
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
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

// MARK: - Launch Ripple Animation

/// Water ripple animation shown on first launch (BootGate).
struct ARESLaunchRipple: View {
    @State private var startTime: Double = 0

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince1970
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height)

                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.black.opacity(0.85)))

                for i in 0..<6 {
                    let delay = Double(i) * 0.25
                    let p = ((t - delay) / 2.0).truncatingRemainder(dividingBy: 1.0)
                    let r = p * maxR
                    let alpha = (1 - p) * (0.5 - Double(i) * 0.06)
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                width: r * 2, height: r * 2)),
                        with: .color(.cyan.opacity(max(0, alpha))),
                        lineWidth: 1.5
                    )
                }

                let dropletAlpha = max(0, 1 - t / 1.5)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)),
                    with: .color(.white.opacity(dropletAlpha))
                )
            }
        }
    }
}