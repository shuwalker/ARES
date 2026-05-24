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
    @Published var activeOfficeAgents: Int = 0

    private let scanner = DependencyScanner()
    private let installer = DependencyInstaller()

    init() {
        self.hasBootstrapped = UserDefaults.standard.bool(forKey: "ARES.hasBootstrapped")
        refreshLiveStats()
    }

    // MARK: - Bootstrap actions

    func scanDependencies() async {
        isScanning = true
        defer { isScanning = false }

        // Set all to checking first
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
            guard status == .missing, !dep.installMethod.isManual else {
                continue
            }

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

        // Memory usage
        // TODO: read from Hermes API when available
        memoryPercent = 94

        // Hermes running
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        try? process.run()
        _ = semaphore.wait(timeout: .now() + .seconds(2))

        if let data = try? pipe.fileHandleForReading.readToEnd(),
           let output = String(data: data, encoding: .utf8) {
            hermesRunning = output.contains("hermes")
        }

        // Session count (placeholder — wire to Hermes API in Phase 4)
        sessionCount = 4
    }

    // MARK: - Companion helpers

    func loadSelfModel() {
        let path = NSString(string: "~/.hermes/state/self_model.md").expandingTildeInPath
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            companionGreeting = "Welcome to ARES."
            selfModelContent = ""
            return
        }
        selfModelContent = content
        companionGreeting = "Good to see you."
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
