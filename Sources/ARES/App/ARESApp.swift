import SwiftUI
import Speech
import AVFoundation

@main
struct ARESApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            if state.setupComplete {
                ContentView()
                    .environmentObject(state)
                    .preferredColorScheme(.dark)
            } else {
                SetupView()
                    .environmentObject(state)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 800)
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var setupComplete = false
    @Published var showHermex = false
    @Published var isListening = false
    @Published var isProcessing = false
    @Published var messages: [Message] = []
    @Published var inputText = ""
    @Published var activeEngine = "hermes"
    @Published var selectedTab: HermexView.Tab = .briefing

    var gateway = HermesGateway(url: "http://localhost:8642")
    let renderer = ThreeJsAvatarRenderer()
    let speech = SpeechService()
    let router = AIRouter.shared
    let persona = PersonaService.shared
    let taskManager = TaskManager.shared

    struct Message: Identifiable {
        let id = UUID()
        let role: String
        let content: String
        let engine: String?
        init(role: String, content: String, engine: String? = nil) {
            self.role = role
            self.content = content
            self.engine = engine
        }
    }

    func initializeEngines() {
        // Hermes — primary engine
        let hermes = HermesEngine(url: UserDefaults.standard.string(forKey: "ares_gateway_url") ?? "http://localhost:8642")
        router.register(hermes)

        // Claude CLI — direct pipe, no API key needed
        router.register(ClaudeCliEngine())

        // Gemini — if API key available
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !key.isEmpty {
            router.register(GeminiEngine(apiKey: key))
        }

        // Claude API — if API key available
        if let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            router.register(ClaudeEngine(apiKey: key))
        }

        // Local — always available if Ollama is running
        router.register(LocalEngine())
    }

    func send(_ text: String) {
        // OBSERVE
        persona.observe(userText: text)

        let msg = Message(role: "user", content: text)
        messages.append(msg)
        inputText = ""
        isProcessing = true
        renderer.showFloatingText(text, role: "user")

        Task {
            do {
                // DECIDE — inject persona context
                let systemContext = persona.buildSystemContext()
                var chatMessages = messages.map { ["role": $0.role, "content": $0.content] }
                chatMessages.insert(["role": "system", "content": systemContext], at: 0)

                let result = try await router.chat(messages: chatMessages)
                let response = Message(role: "ares", content: result, engine: activeEngine)
                messages.append(response)
                renderer.showFloatingText(result, role: "ares")
                speech.speak(result)

                // REMEMBER
                persona.remember(response: result, engine: activeEngine)
            } catch {
                let err = Message(role: "ares", content: "Error: \(error.localizedDescription)")
                messages.append(err)
            }
            isProcessing = false
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack {
            if state.showHermex {
                HermexView()
                    .transition(.move(edge: .trailing))
            } else {
                SanctumView()
                    .transition(.move(edge: .leading))
            }

            VStack {
                HStack {
                    Button(action: { withAnimation(.spring()) { state.showHermex.toggle() }}) {
                        Image(systemName: state.showHermex ? "sparkles" : "square.grid.2x2")
                            .font(.title3)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(state.showHermex ? "Sanctum" : "Interface")
                    Spacer()
                }
                .padding()
                Spacer()
            }
        }
        .onAppear {
            state.initializeEngines()
            state.renderer.showFloatingText("...", role: "system")
            state.speech.startListening { text in
                state.send(text)
            }
        }
    }
}
