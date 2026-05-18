import Foundation

// MARK: - Plugin Manifest

struct PluginManifest: Codable, Identifiable {
    let name: String
    let label: String?
    let description: String?
    let icon: String?
    let version: String?
    let tab: String?
    let path: String?
    let slots: [String]?
    let entry: String?
    let hasAPI: Bool?
    let source: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, label, description, icon, version, tab, path, slots, entry, source
        case hasAPI = "has_api"
    }
}

// MARK: - Plugin Runtime Status

enum PluginRuntimeStatus: String, Codable {
    case disabled
    case enabled
    case inactive
}

// MARK: - Hub Agent Plugin Row

struct HubAgentPluginRow: Codable, Identifiable {
    let name: String
    let version: String?
    let description: String?
    let source: String?
    let runtimeStatus: PluginRuntimeStatus
    let hasDashboardManifest: Bool?
    let dashboardManifest: PluginManifest?
    let path: String?
    let canRemove: Bool?
    let canUpdateGit: Bool?
    let authRequired: Bool?
    let authCommand: String?
    let userHidden: Bool?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, version, description, source, path
        case runtimeStatus = "runtime_status"
        case hasDashboardManifest = "has_dashboard_manifest"
        case dashboardManifest = "dashboard_manifest"
        case canRemove = "can_remove"
        case canUpdateGit = "can_update_git"
        case authRequired = "auth_required"
        case authCommand = "auth_command"
        case userHidden = "user_hidden"
    }
}

// MARK: - Provider Option

struct ProviderOption: Codable, Identifiable {
    let name: String
    let description: String?

    var id: String { name }
}

// MARK: - Plugins Hub Providers

struct PluginsHubProviders: Codable {
    let memoryProvider: String?
    let memoryOptions: [ProviderOption]?
    let contextEngine: String?
    let contextOptions: [ProviderOption]?

    enum CodingKeys: String, CodingKey {
        case memoryProvider = "memory_provider"
        case memoryOptions = "memory_options"
        case contextEngine = "context_engine"
        case contextOptions = "context_options"
    }
}

// MARK: - Plugins Hub Response

struct PluginsHubResponse: Codable {
    let plugins: [HubAgentPluginRow]
    let orphanDashboardPlugins: [PluginManifest]?
    let providers: PluginsHubProviders?

    enum CodingKeys: String, CodingKey {
        case plugins, providers
        case orphanDashboardPlugins = "orphan_dashboard_plugins"
    }
}

// MARK: - Install Request / Response

struct AgentPluginInstallRequest: Codable {
    let identifier: String
    let force: Bool
    let enable: Bool
}

struct AgentPluginInstallResponse: Codable {
    let ok: Bool
    let pluginName: String?
    let warnings: [String]?
    let missingEnv: [String]?
    let afterInstallPath: String?
    let enabled: Bool?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case ok, warnings, enabled, error
        case pluginName = "plugin_name"
        case missingEnv = "missing_env"
        case afterInstallPath = "after_install_path"
    }
}

// MARK: - Enable / Disable / Remove Response

struct AgentPluginToggleResponse: Codable {
    let ok: Bool
    let name: String?
}

// MARK: - Update Response

struct AgentPluginUpdateResponse: Codable {
    let ok: Bool
    let name: String?
    let output: String?
    let unchanged: Bool?
    let error: String?
}

// MARK: - Save Providers Response

struct SavePluginProvidersResponse: Codable {
    let ok: Bool
}

// MARK: - Rescan Response

struct RescanPluginsResponse: Codable {
    let ok: Bool
    let count: Int?
}
