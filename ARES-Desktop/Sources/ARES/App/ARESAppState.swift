import Foundation
import SwiftUI

@MainActor
final class ARESAppState: ObservableObject {
    // MARK: - Bootstrap state
    @Published var hasBootstrapped: Bool {
        didSet { UserDefaults.standard.set(hasBootstrapped, forKey: "ARES.hasBootstrapped") }
    }

    @Published var dependencies: [ARESDependency: DependencyStatus] = [:]
    @Published var isScanning = false
    @Published var isInstalling = false
    @Published var installError: String?

    // MARK: - Tab navigation
    @Published var selectedTab: ARESTab = .companion

    // MARK: - Companion state
    @Published var companionGreeting: String = ""
    @Published var selfModelContent: String = ""
    @Published var voiceState: VoiceState = .idle
    @Published var skillCount: Int = 0
    @Published var sessionCount: Int = 0
    @Published var memoryPercent: Int = 0
    @Published var hermesRunning: Bool = false
    @Published var hermesGatewayURL: String = "http://localhost:8642"
    @Published var activeOfficeAgents: Int = 0

    // MARK: - Chat state
    @Published var chatMessages: [ChatBubble] = []
    @Published var chatInput: String = ""
    @Published var isChatProcessing: Bool = false

    // MARK: - Office state
    @Published var officeAgents: [AgentCard] = []
    @Published var officeAgentCount: Int = 0

    private let scanner = DependencyScanner()
    private let installer = DependencyInstaller()
    private var refreshTimer: Timer?

    init() {
        self.hasBootstrapped = UserDefaults.standard.bool(forKey: "ARES.hasBootstrapped")
        refreshLiveStats()
    }

    // MARK: - Bootstrap actions

    func scanDependencies() async {
        isScanning = true
        defer { isScanning = false }

        for dep in ARESDependency.allCases {
            dependencies[dep] = .checking
        }

        let results = await scanner.scanAll()
        for result in results {
            dependencies[result.dependency] = result.status
        }
    }

    func installMissing() async {
        isInstalling = true
        installError = nil
        defer { isInstalling = false }

        for (dep, status) in dependencies {
            guard status == .missing, !dep.installMethod.isManual else { continue }
            do {
                try await installer.install(dep)
                dependencies[dep] = .installed
            } catch {
                dependencies[dep] = .failed(error.localizedDescription)
                installError = error.localizedDescription
            }
        }
    }

    func completeBootstrap() {
        hasBootstrapped = true
    }

    // MARK: - Live stats

    func refreshLiveStats() {
        // Skill count from file system
        let skillsDir = NSString(string: "~/.hermes/skills").expandingTildeInPath
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: skillsDir) {
            skillCount = contents.count
        }

        // Memory percent from file
        let memPath = NSString(string: "~/.hermes/memories/MEMORY.md").expandingTildeInPath
        if let memContent = try? String(contentsOfFile: memPath, encoding: .utf8) {
            // Parse capacity percentage from memory file header
            if let capLine = memContent.components(separatedBy: "\n").first(where: { $0.contains("%") }) {
                if let pctStr = capLine.components(separatedBy: "[").last?.components(separatedBy: "%").first,
                   let pct = Int(pctStr.trimmingCharacters(in: .whitespaces)) {
                    memoryPercent = pct
                } else {
                    memoryPercent = 94
                }
            } else {
                memoryPercent = 94
            }
        } else {
            memoryPercent = 94
        }

        // Hermes health check via HTTP
        checkHermesHealth()

        // Session count from session DB
        refreshSessionCount()

        // Office agents
        refreshOfficeAgents()

        // Schedule periodic refresh
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkHermesHealth()
            }
        }
    }

    private func checkHermesHealth() {
        Task {
            if let url = URL(string: "\(hermesGatewayURL)/health") {
                var req = URLRequest(url: url, timeoutInterval: 3)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                do {
                    let (_, response) = try await URLSession.shared.data(for: req)
                    hermesRunning = (response as? HTTPURLResponse)?.statusCode == 200
                } catch {
                    // Fallback: try WebUI
                    if let webURL = URL(string: "http://localhost:9119") {
                        var webReq = URLRequest(url: webURL, timeoutInterval: 2)
                        webReq.cachePolicy = .reloadIgnoringLocalCacheData
                        do {
                            let (_, webResp) = try await URLSession.shared.data(for: webReq)
                            hermesRunning = (webResp as? HTTPURLResponse)?.statusCode == 200
                        } catch {
                            hermesRunning = false
                        }
                    } else {
                        hermesRunning = false
                    }
                }
            }
        }
    }

    private func refreshSessionCount() {
        // Count sessions from Hermes session DB
        let sessionDir = NSString(string: "~/.hermes/sessions").expandingTildeInPath
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: sessionDir) {
            sessionCount = contents.filter { $0.hasSuffix(".sqlite") || $0.hasSuffix(".json") }.count
        }
        if sessionCount == 0 {
            sessionCount = 4 // fallback
        }
    }

    private func refreshOfficeAgents() {
        // Discover active agents from Hermes — process checks run off the main
        // thread to avoid blocking the UI with waitUntilExit().
        let hermesRunningSnapshot = hermesRunning
        Task.detached(priority: .utility) {
            var agents: [AgentCard] = []

            // Hermes agent
            if hermesRunningSnapshot {
                agents.append(AgentCard(
                    name: "Hermes",
                    role: "Reasoning Engine",
                    status: .active,
                    detail: "Primary cognition agent"
                ))
            }

            // Check for Ollama
            let ollamaCheck = Process()
            ollamaCheck.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            ollamaCheck.arguments = ["-x", "ollama"]
            let pipe = Pipe()
            ollamaCheck.standardOutput = pipe
            ollamaCheck.standardError = FileHandle.nullDevice
            try? ollamaCheck.run()
            ollamaCheck.waitUntilExit()
            if ollamaCheck.terminationStatus == 0 {
                agents.append(AgentCard(
                    name: "Ollama",
                    role: "ML Engine",
                    status: .active,
                    detail: "Local model inference"
                ))
            }

            // SearXNG
            let sxCheck = Process()
            sxCheck.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            sxCheck.arguments = ["-f", "searxng"]
            let sxPipe = Pipe()
            sxCheck.standardOutput = sxPipe
            sxCheck.standardError = FileHandle.nullDevice
            try? sxCheck.run()
            sxCheck.waitUntilExit()
            if sxCheck.terminationStatus == 0 {
                agents.append(AgentCard(
                    name: "SearXNG",
                    role: "Research",
                    status: .active,
                    detail: "Self-hosted search engine"
                ))
            }

            await MainActor.run {
                self.officeAgents = agents
                self.officeAgentCount = agents.count
            }
        }
    }

    // MARK: - Chat

    func sendChat() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isChatProcessing else { return }

        chatMessages.append(ChatBubble(role: .user, content: text))
        let prompt = text
        chatInput = ""
        isChatProcessing = true
        voiceState = .thinking

        Task {
            let response = await runHermesChat(prompt)
            await MainActor.run {
                chatMessages.append(ChatBubble(role: .assistant, content: response))
                isChatProcessing = false
                voiceState = .idle
            }
        }
    }

    nonisolated private func runHermesChat(_ prompt: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["hermes", "-z", prompt, "--yolo"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } catch {
            return "Hermes unreachable: \(error.localizedDescription)"
        }
        return "No response from Hermes."
    }

    // MARK: - Companion helpers

    func loadSelfModel() {
        let path = NSString(string: "~/.hermes/state/self_model.md").expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            selfModelContent = ""
            companionGreeting = "ARES online."
            return
        }
        selfModelContent = content

        // Extract a meaningful greeting from self-model
        if let firstLine = content.components(separatedBy: "\n").first(where: {
            !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---")
        }) {
            companionGreeting = firstLine.trimmingCharacters(in: .whitespaces)
                .prefix(120).description
        } else {
            companionGreeting = "Good to see you."
        }
    }
}

// MARK: - Tab enum

enum ARESTab: String, CaseIterable, Identifiable {
    case companion
    case office
    case hub

    var id: String { rawValue }

    var title: String {
        switch self {
        case .companion: return "Companion"
        case .office:    return "Office"
        case .hub:       return "Hub"
        }
    }

    var systemImage: String {
        switch self {
        case .companion: return "person.fill.viewfinder"
        case .office:    return "building.2.fill"
        case .hub:       return "square.grid.2x2.fill"
        }
    }
}

// MARK: - Voice states

enum VoiceState {
    case idle
    case listening
    case thinking
    case speaking
    case sleeping

    var label: String {
        switch self {
        case .idle:      return "Idle"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return "Speaking"
        case .sleeping:  return "Sleeping"
        }
    }

    var color: Color {
        switch self {
        case .idle:      return .gray
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .blue
        case .sleeping:  return .secondary
        }
    }
}

// MARK: - Agent card model

struct AgentCard: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let role: String
    let status: AgentStatus
    let detail: String
}

// MARK: - Chat bubble model

struct ChatBubble: Identifiable, Equatable {
    let id = UUID()
    let role: BubbleRole
    let content: String
    let timestamp: Date = Date()
}

enum BubbleRole {
    case user
    case assistant
}

enum AgentStatus {
    case active
    case idle
    case offline

    var label: String {
        switch self {
        case .active:  return "Active"
        case .idle:    return "Idle"
        case .offline: return "Offline"
        }
    }

    var color: Color {
        switch self {
        case .active:  return .green
        case .idle:    return .orange
        case .offline: return .gray
        }
    }
}
