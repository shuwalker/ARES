import Foundation

// MARK: - Automation Registry Models
// Reads ~/.ares/automation-registry.json to display all automated systems in ARES.app

struct AutomationRegistry: Codable {
    let version: String
    let automations: [Automation]
    let categories: [String: AutomationCategory]
    let statusColors: [String: String]
    
    struct Automation: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let category: String
        let description: String
        let schedule: String
        let type: String
        let status: String
        let healthEndpoint: String?
        let icon: String?
        let lastRun: String?
        let pid: Int?
        
        enum CodingKeys: String, CodingKey {
            case id, name, category, description, schedule, type, status
            case healthEndpoint = "health_endpoint"
            case icon
            case lastRun = "last_run"
            case pid
        }
        
        var statusColor: String {
            switch status {
            case "active": return "green"
            case "inactive": return "gray"
            case "error": return "red"
            case "disabled": return "secondary"
            default: return "gray"
            }
        }
        
        var categoryLabel: String {
            switch category {
            case "cognitive": return "Cognitive"
            case "productivity": return "Productivity"
            case "maintenance": return "Maintenance"
            case "infrastructure": return "Infrastructure"
            case "content": return "Content"
            default: return category.capitalized
            }
        }
        
        var categoryColor: String {
            switch category {
            case "cognitive": return "purple"
            case "productivity": return "blue"
            case "maintenance": return "orange"
            case "infrastructure": return "gray"
            case "content": return "green"
            default: return "gray"
            }
        }
        
        var sfSymbol: String {
            icon ?? "gear"
        }
        
        var isRunning: Bool {
            status == "active"
        }
    }
    
    struct AutomationCategory: Codable {
        let label: String
        let color: String
        let icon: String
    }
}

// MARK: - Automation Registry Loader

enum AutomationRegistryLoader {
    static let registryPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".ares/automation-registry.json")
    
    static func load() -> AutomationRegistry? {
        guard FileManager.default.fileExists(atPath: registryPath.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: registryPath)
            return try JSONDecoder().decode(AutomationRegistry.self, from: data)
        } catch {
            print("Failed to load automation registry: \(error)")
            return nil
        }
    }
    
    static func loadAsync() async -> AutomationRegistry? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: load())
            }
        }
    }
}