import SwiftUI
import RealityKit

struct ARESRootView: View {
    @EnvironmentObject var brain: BrainConnection
    @EnvironmentObject var voice: VoiceManager
    @State private var showLaunchAnimation = true
    @State private var currentStyle: AvatarStyle = .blackFire
    @State private var cognitiveExpanded = false
    @State private var selectedPage: DashboardPage = .chat

    var body: some View {
        ZStack {
            backgroundLayer

            if showLaunchAnimation {
                LaunchRipple()
                    .transition(.opacity)
                    .zIndex(1000)
            }

            HStack(spacing: 0) {
                if brain.immersionLevel != .full {
                    SidebarView(selectedPage: $selectedPage)
                }

                VStack(spacing: 0) {
                    ImmersionBar(cognitiveExpanded: $cognitiveExpanded)

                    if cognitiveExpanded {
                        CognitiveActivityPanel()
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    AvatarSceneView(style: $currentStyle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ChatStream()
                    CommandBar()
                }
            }
            .opacity(showLaunchAnimation ? 0 : 1)
            .animation(.easeIn(duration: 1.0).delay(1.8), value: showLaunchAnimation)
        }
        .task {
            brain.connect()
            // Dismiss launch animation after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeInOut(duration: 1.2)) {
                    showLaunchAnimation = false
                }
            }
        }
        .onChange(of: voice.transcript) { _, text in
            if !text.isEmpty && !voice.isListening {
                brain.sendMessage(text)
            }
        }
    }
    
    @ViewBuilder
    var backgroundLayer: some View {
        if brain.immersionLevel == .full {
            Color.black.ignoresSafeArea()
        } else {
            VisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        }
    }
}

// MARK: - Launch Ripple Animation

struct LaunchRipple: View {
    @State private var startTime: Double = 0
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince1970
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = hypot(size.width, size.height)
                
                // Dark water surface
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(.black.opacity(0.85)))
                
                // Ripple rings
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
                
                // Droplet impact point — fades out
                let dropletAlpha = max(0, 1 - t / 1.5)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)),
                    with: .color(.white.opacity(dropletAlpha))
                )
            }
        }
    }
}

// MARK: - Visual Effect Helper

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