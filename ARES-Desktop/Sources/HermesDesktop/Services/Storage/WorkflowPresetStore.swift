import Foundation

/// Persists locally-stored workflow presets to ~/.ares/workflow-presets.json.
/// This store is workspace-independent and holds simple prompt templates for reuse.
final class WorkflowPresetStore: Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let aresDir = homeURL.appendingPathComponent(".ares", isDirectory: true)
        fileURL = aresDir.appendingPathComponent("workflow-presets.json")
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectory(aresDir)
    }

    func load() -> [StoredWorkflowPreset] {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let presets = try? decoder.decode([StoredWorkflowPreset].self, from: data) else {
            return []
        }
        return presets
    }

    func save(_ presets: [StoredWorkflowPreset]) {
        guard let data = try? encoder.encode(presets) else { return }
        try? data.write(to: fileURL, options: .atomicWrite)
    }

    func add(_ preset: StoredWorkflowPreset) {
        var presets = load()
        presets.append(preset)
        save(presets)
    }

    func delete(id: UUID) {
        var presets = load()
        presets.removeAll { $0.id == id }
        save(presets)
    }

    private func ensureDirectory(_ url: URL) {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
    }
}

/// A locally-persisted workflow prompt template, independent of any remote connection.
struct StoredWorkflowPreset: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var prompt: String
    var attachedSkills: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        attachedSkills: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.attachedSkills = attachedSkills
        self.createdAt = createdAt
    }

    var promptPreview: String {
        let compact = prompt
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard compact.count > 120 else { return compact }
        let index = compact.index(compact.startIndex, offsetBy: 120)
        return compact[..<index].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
