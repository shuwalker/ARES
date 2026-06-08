import SwiftUI
import WebKit
import ARESCore

// MARK: - Avatar Widget
//
// Renders ARES avatar via WKWebView (HyperFrames composition).
// Falls back to animated SwiftUI face if HyperFrames not available.
// Emotion is driven by real app state: voice state drives emotion,
// chat processing drives thinking animation.

struct AvatarWidget: View {
    @EnvironmentObject var appState: ARESAppState
    @State private var hyperframesReady = false
    @State private var mimicryTask: Task<Void, Never>?
    @State private var webViewCoordinator: WebViewCoordinator?

    var body: some View {
        VStack(spacing: 12) {
            if hyperframesReady {
                AvatarWebView(coordinator: $webViewCoordinator)
                    .frame(minHeight: 200)
            } else {
                AvatarFallbackView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 200)
        .onAppear {
            AvatarCompositionInstaller.installIfNeeded()
            startHyperFrames()
        }
        .onDisappear {
            mimicryTask?.cancel()
        }
        .onChange(of: appState.voiceState) { _, newState in
            // Push real voice state changes to the WebView
            let (emotion, state) = voiceStateToEmotionState(newState)
            webViewCoordinator?.setEmotion(emotion, intensity: 1.0, state: state)
        }
        .onChange(of: appState.isChatProcessing) { _, processing in
            if processing {
                webViewCoordinator?.setEmotion("thinking", intensity: 0.8, state: "thinking")
            } else {
                let (emotion, state) = voiceStateToEmotionState(appState.voiceState)
                webViewCoordinator?.setEmotion(emotion, intensity: 0.5, state: state)
            }
        }
    }

    /// Map real voice state to avatar emotion representation.
    private func voiceStateToEmotionState(_ vs: VoiceState) -> (emotion: String, state: String) {
        switch vs {
        case .idle:
            return ("neutral", "idle")
        case .listening:
            return ("curious", "listening")
        case .thinking:
            return ("thinking", "thinking")
        case .speaking:
            return ("happy", "speaking")
        case .sleeping:
            return ("sleepy", "sleeping")
        }
    }

    private func startHyperFrames() {
        Task {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = ["npx", "hyperframes", "preview", "--port", "3002"]
            proc.currentDirectoryURL = AvatarCompositionInstaller.avatarDir
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    hyperframesReady = true
                    print("✅ [AVATAR] HyperFrames preview server started at localhost:3002")
                    // Set initial emotion from current app state
                    let (emotion, state) = voiceStateToEmotionState(appState.voiceState)
                    webViewCoordinator?.setEmotion(emotion, intensity: 0.5, state: state)
                }
            } catch {
                print("⚠️  [AVATAR] Failed to start HyperFrames: \(error)")
            }
        }
    }
}

// MARK: - Avatar WebView (HyperFrames)

struct AvatarWebView: NSViewRepresentable {
    @Binding var coordinator: WebViewCoordinator?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)

        let coordinator = WebViewCoordinator(webView: webView)
        self.coordinator = coordinator

        let url = URL(string: "http://localhost:3002")!
        webView.load(URLRequest(url: url))

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - WebView Coordinator

@MainActor
class WebViewCoordinator: NSObject {
    let webView: WKWebView

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    func setEmotion(_ emotion: String, intensity: Double, state: String) {
        let js = "window.setEmotion('\(emotion)', \(intensity), '\(state)')"
        webView.evaluateJavaScript(js) { result, error in
            if let error = error {
                print("⚠️  [AVATAR] JS error: \(error)")
            }
        }
    }
}

// MARK: - Avatar Fallback (Animated SwiftUI face)

struct AvatarFallbackView: View {
    @EnvironmentObject var appState: ARESAppState
    @State private var pulseScale: CGFloat = 1.0
    @State private var blinkOpacity: Double = 1.0
    @State private var blinkTimer: Timer?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Background circle that subtly pulses based on activity
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                circleColor.opacity(0.4 * pulseScale),
                                circleColor.opacity(0.1)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(height: 180)
                    .animation(.easeInOut(duration: 1.5), value: pulseScale)

                VStack(spacing: 20) {
                    // Eyes — blink periodically, look different when thinking
                    HStack(spacing: 24) {
                        eyeView
                        eyeView
                    }
                    .frame(height: 40)

                    // Mouth — reacts to voice state
                    Group {
                        switch appState.voiceState {
                        case .speaking:
                            // Open mouth animation
                            Path { path in
                                path.addArc(center: CGPoint(x: 0, y: 0), radius: 16, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                            }
                            .fill(circleColor.opacity(0.6))
                        case .listening:
                            // Slight smile
                            Path { path in
                                path.addArc(center: CGPoint(x: 0, y: -4), radius: 14, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                            }
                            .stroke(circleColor, lineWidth: 2)
                        case .thinking:
                            // Small circle (contemplating)
                            Circle()
                                .stroke(circleColor, lineWidth: 2)
                                .frame(width: 10, height: 10)
                        case .sleeping:
                            // Little 'o' (sleeping)
                            Ellipse()
                                .stroke(circleColor, lineWidth: 2)
                                .frame(width: 10, height: 14)
                        case .idle:
                            // Neutral line
                            Path { path in
                                path.move(to: CGPoint(x: -15, y: 0))
                                path.addLine(to: CGPoint(x: 15, y: 0))
                            }
                            .stroke(circleColor, lineWidth: 2)
                        }
                    }
                    .frame(height: 30)
                    .animation(.spring(duration: 0.3), value: appState.voiceState)
                }
                .frame(width: 100)
            }

            // Status indicators — driven from real state, not buttons
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.hermesRunning ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(appState.hermesRunning ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if appState.isChatProcessing {
                Text("Thinking...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .onAppear {
            startBlinking()
            startPulse()
        }
        .onDisappear {
            blinkTimer?.invalidate()
        }
    }

    /// Eye view with blink animation
    private var eyeView: some View {
        Ellipse()
            .fill(Color.black)
            .frame(width: 12, height: blinkOpacity < 0.5 ? 2 : 12)
            .animation(.easeIn(duration: 0.1), value: blinkOpacity)
    }

    /// Color that shifts based on voice state
    private var circleColor: Color {
        switch appState.voiceState {
        case .idle: return .blue
        case .listening: return .cyan
        case .thinking: return .purple
        case .speaking: return .green
        case .sleeping: return .indigo
        }
    }

    private func startBlinking() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                blinkOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    blinkOpacity = 1
                }
            }
        }
    }

    private func startPulse() {
        // Subtly pulse the background when speaking or thinking
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            guard appState.isChatProcessing || appState.voiceState == .speaking else {
                pulseScale = 1.0
                return
            }
            withAnimation(.easeInOut(duration: 1.0)) {
                pulseScale = pulseScale == 1.0 ? 1.15 : 1.0
            }
        }
    }
}

#Preview {
    AvatarWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}