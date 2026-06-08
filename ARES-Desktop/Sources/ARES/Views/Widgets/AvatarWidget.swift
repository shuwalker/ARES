import SwiftUI
import WebKit
import ARESCore

// MARK: - Avatar Widget
//
// Renders ARES avatar via WKWebView (HyperFrames composition).
// Falls back to hand-drawn face if HyperFrames not available.
// Emotion is driven by DummyMimicry (30fps stream).

struct AvatarWidget: View {
    @State private var hyperframesReady = false
    @State private var mimicryTask: Task<Void, Never>?
    @State private var webViewCoordinator: WebViewCoordinator?

    private let mimicry = DummyMimicry()
    let emotions = ["neutral", "happy", "curious", "thinking"]

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
            startMimicryStream()
        }
        .onDisappear {
            mimicryTask?.cancel()
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
                // Wait 2s for server to start
                try await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    hyperframesReady = true
                    print("✅ [AVATAR] HyperFrames preview server started at localhost:3002")
                }
            } catch {
                print("⚠️  [AVATAR] Failed to start HyperFrames: \(error)")
                // Fallback to hand-drawn face
            }
        }
    }

    private func startMimicryStream() {
        mimicryTask = Task {
            do {
                for try await frame in mimicry.mimicryStream {
                    let emotion = frame.expression.emotion
                    let intensity = frame.expression.intensity

                    await MainActor.run {
                        // Convert intensity to emotion state
                        let state: String = {
                            if emotion == "thinking" {
                                return "thinking"
                            } else if emotion == "happy" {
                                return "listening"  // happy emotion during interaction
                            } else {
                                return "idle"  // neutral or curious = idle
                            }
                        }()

                        webViewCoordinator?.setEmotion(emotion, intensity: intensity, state: state)
                    }
                }
            } catch is CancellationError {
                // Task was cancelled, that's fine
            } catch {
                print("⚠️  [AVATAR] Mimicry stream error: \(error)")
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

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed
    }
}

// MARK: - WebView Coordinator

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

// MARK: - Avatar Fallback (Hand-Drawn)

struct AvatarFallbackView: View {
    @State private var currentEmotion: String = "neutral"
    let emotions = ["neutral", "happy", "curious", "thinking"]

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.3),
                                Color.blue.opacity(0.1)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 100
                        )
                    )
                    .frame(height: 180)

                VStack(spacing: 20) {
                    HStack(spacing: 24) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(Color.black)
                            .frame(width: 12, height: 12)
                    }
                    .frame(height: 40)

                    Group {
                        if currentEmotion == "happy" {
                            Path { path in
                                path.addArc(center: CGPoint(x: 0, y: 0), radius: 20, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
                            }
                            .stroke(Color.black, lineWidth: 2)
                        } else if currentEmotion == "thinking" {
                            Circle()
                                .stroke(Color.black, lineWidth: 2)
                                .frame(width: 12, height: 12)
                        } else {
                            Path { path in
                                path.move(to: CGPoint(x: -15, y: 0))
                                path.addLine(to: CGPoint(x: 15, y: 0))
                            }
                            .stroke(Color.black, lineWidth: 2)
                        }
                    }
                    .frame(height: 30)
                }
                .frame(width: 100)
            }

            VStack(spacing: 8) {
                Text("State").font(.caption2).foregroundColor(.secondary)
                HStack(spacing: 4) {
                    ForEach(emotions, id: \.self) { emotion in
                        Button {
                            withAnimation(.spring()) {
                                currentEmotion = emotion
                            }
                        } label: {
                            Circle()
                                .fill(currentEmotion == emotion ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Online").font(.caption).foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    AvatarWidget()
        .padding()
        .background(Color(.windowBackgroundColor))
}
