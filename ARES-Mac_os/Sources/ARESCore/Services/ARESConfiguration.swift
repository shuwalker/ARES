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

    public var ownerModelJSONPath: String {
        return configDirectory.appendingPathComponent("owner_model.json").path
    }

    public var workflowsPath: String {
        return configDirectory.appendingPathComponent("workflows").path
    }

    public var pluginsPath: String {
        return configDirectory.appendingPathComponent("plugins").path
    }

    // MARK: - Network Endpoints

    @Published public var webuiHost: String = UserDefaults.standard.string(forKey: "ares.config.webuiHost") ?? "127.0.0.1" {
        didSet { UserDefaults.standard.set(webuiHost, forKey: "ares.config.webuiHost") }
    }

    @Published public var webuiPort: Int = UserDefaults.standard.integer(forKey: "ares.config.webuiPort") == 0 ? 8787 : UserDefaults.standard.integer(forKey: "ares.config.webuiPort") {
        didSet { UserDefaults.standard.set(webuiPort, forKey: "ares.config.webuiPort") }
    }

    @Published public var aresRole: String = UserDefaults.standard.string(forKey: "ares.config.role") ?? "primary" {
        didSet { UserDefaults.standard.set(aresRole, forKey: "ares.config.role") }
    }

    @Published public var aresDeviceID: String = UserDefaults.standard.string(forKey: "ares.config.deviceID") ?? (Host.current().localizedName?.lowercased().replacingOccurrences(of: " ", with: "-") ?? "ares-device") {
        didSet { UserDefaults.standard.set(aresDeviceID, forKey: "ares.config.deviceID") }
    }

    @Published public var aresAIID: String = UserDefaults.standard.string(forKey: "ares.config.aiID") ?? "ares-main" {
        didSet { UserDefaults.standard.set(aresAIID, forKey: "ares.config.aiID") }
    }

    @Published public var aresPrimaryURL: String = UserDefaults.standard.string(forKey: "ares.config.primaryURL") ?? "" {
        didSet { UserDefaults.standard.set(aresPrimaryURL, forKey: "ares.config.primaryURL") }
    }

    @Published public var aresContinuityDir: String = UserDefaults.standard.string(forKey: "ares.config.continuityDir") ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/Desktop/ARES/00_System/ares" {
        didSet { UserDefaults.standard.set(aresContinuityDir, forKey: "ares.config.continuityDir") }
    }

    @Published public var autoLaunchOnStart: Bool = UserDefaults.standard.object(forKey: "ares.config.autoLaunchOnStart") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoLaunchOnStart, forKey: "ares.config.autoLaunchOnStart") }
    }

    @Published public var reloadDevMode: Bool = UserDefaults.standard.bool(forKey: "ares.config.reloadDevMode") {
        didSet { UserDefaults.standard.set(reloadDevMode, forKey: "ares.config.reloadDevMode") }
    }

    @Published public var hermesURL: String = UserDefaults.standard.string(forKey: "ares.config.hermesURL") ?? "http://localhost:8642" {
        didSet { UserDefaults.standard.set(hermesURL, forKey: "ares.config.hermesURL") }
    }

    @Published public var jrosURL: String = UserDefaults.standard.string(forKey: "ares.config.jrosURL") ?? "http://127.0.0.1:8643" {
        didSet { UserDefaults.standard.set(jrosURL, forKey: "ares.config.jrosURL") }
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

    @Published public var hermesDashboardURL: String = UserDefaults.standard.string(forKey: "ares.config.hermesDashboardURL") ?? "http://localhost:9119" {
        didSet { UserDefaults.standard.set(hermesDashboardURL, forKey: "ares.config.hermesDashboardURL") }
    }

    /// Hermes Gateway API key. Environment overrides win; persisted values
    /// live in Keychain and legacy UserDefaults values are migrated once.
    @Published public var hermesAPIKey: String = ARESSecretStore.loadMigratingLegacy(
        environmentKey: "API_SERVER_KEY",
        account: "hermes-gateway-api-key",
        legacyDefaultsKey: "ares.config.hermesAPIKey"
    ) {
        didSet {
            _ = ARESSecretStore.write(hermesAPIKey, account: "hermes-gateway-api-key")
            UserDefaults.standard.removeObject(forKey: "ares.config.hermesAPIKey")
        }
    }

    /// JROS/Jaeger Gateway API key. Stored locally for Finder-launched app
    /// sessions and exported as ARES_JROS_GATEWAY_KEY when ARES starts WebUI.
    @Published public var jrosAPIKey: String = ARESSecretStore.loadMigratingLegacy(
        environmentKey: "ARES_JROS_GATEWAY_KEY",
        account: "jros-gateway-api-key",
        legacyDefaultsKey: "ares.config.jrosAPIKey"
    ) {
        didSet {
            _ = ARESSecretStore.write(jrosAPIKey, account: "jros-gateway-api-key")
            UserDefaults.standard.removeObject(forKey: "ares.config.jrosAPIKey")
        }
    }

    // MARK: - Parsed URLs (fall back to defaults if the stored string is malformed)

    public var hermesBaseURL: URL {
        Self.validHTTPURL(from: hermesURL) ?? URL(string: "http://localhost:8642")!
    }

    public var jrosBaseURL: URL {
        Self.validHTTPURL(from: jrosURL) ?? URL(string: "http://127.0.0.1:8643")!
    }

    public var ollamaBaseURL: URL {
        Self.validHTTPURL(from: ollamaURL) ?? URL(string: "http://localhost:11434")!
    }

    private static func validHTTPURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}
