import Foundation
import Combine

/// Central configuration manager for ARES.
/// Replaces hardcoded file paths and URLs with a dynamic, user-customizable source of truth.
public final class ARESConfiguration: ObservableObject, @unchecked Sendable {
    public static let shared = ARESConfiguration()

    private let fileManager = FileManager.default

    public let configDirectory: URL

    private init() {
        let homeDir = fileManager.homeDirectoryForCurrentUser
        self.configDirectory = homeDir.appendingPathComponent(".ares", isDirectory: true)
        ensureDirectoriesExist()
    }

    private func ensureDirectoriesExist() {
        let dirs = [
            configDirectory,
            configDirectory.appendingPathComponent("workflows", isDirectory: true),
            configDirectory.appendingPathComponent("plugins", isDirectory: true)
        ]

        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - File Paths

    public var memoryDBPath: String {
        return configDirectory.appendingPathComponent("state.db").path
    }

    public var identityJSONPath: String {
        return configDirectory.appendingPathComponent("identity.json").path
    }

    public var workflowsPath: String {
        return configDirectory.appendingPathComponent("workflows").path
    }

    public var pluginsPath: String {
        return configDirectory.appendingPathComponent("plugins").path
    }

    // MARK: - Network Endpoints

    @Published public var hermesURL: String = UserDefaults.standard.string(forKey: "ares.config.hermesURL") ?? "http://localhost:8642" {
        didSet { UserDefaults.standard.set(hermesURL, forKey: "ares.config.hermesURL") }
    }

    @Published public var ollamaURL: String = UserDefaults.standard.string(forKey: "ares.config.ollamaURL") ?? "http://localhost:11434" {
        didSet { UserDefaults.standard.set(ollamaURL, forKey: "ares.config.ollamaURL") }
    }

    @Published public var n8nWebhookBaseURL: String = UserDefaults.standard.string(forKey: "ares.config.n8nWebhookBaseURL") ?? "http://localhost:5678" {
        didSet { UserDefaults.standard.set(n8nWebhookBaseURL, forKey: "ares.config.n8nWebhookBaseURL") }
    }

    @Published public var localPerceiverWSURL: String = UserDefaults.standard.string(forKey: "ARES_PERCEIVER_WS") ?? "ws://localhost:9100" {
        didSet { UserDefaults.standard.set(localPerceiverWSURL, forKey: "ARES_PERCEIVER_WS") }
    }
}
