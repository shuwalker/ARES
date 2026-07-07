import ARESCore
import Foundation

/// File-backed OwnerModelProvider.
///
/// The default app path is private runtime storage. Tests pass an explicit temp
/// path so no real user data is touched.
public final class FileSystemOwnerModelProvider: OwnerModelProvider, @unchecked Sendable {
    private let filePath: String
    private let lock = NSLock()
    private var model: OwnerModel

    public init(path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        self.filePath = expandedPath

        let dir = NSString(string: expandedPath).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: expandedPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
                self.model = try JSONDecoder.aresOwnerModelDecoder.decode(OwnerModel.self, from: data)
            } catch {
                self.model = OwnerModel()
                try Self.write(model: model, to: expandedPath)
            }
        } else {
            self.model = OwnerModel()
            try Self.write(model: model, to: expandedPath)
        }
    }

    public func getOwnerModel() async throws -> OwnerModel {
        lock.withLock { model }
    }

    public func recordPreference(_ preference: OwnerPreference) async throws {
        try mutate { model in
            model.acceptedPatterns.append(OwnerPattern(
                summary: "Preference: \(preference.key)=\(preference.value)",
                evidence: preference.evidence,
                confidence: preference.confidence,
                updatedAt: preference.updatedAt
            ))
            model.updatedAt = Date()
            model.confidence = min(1.0, model.confidence + 0.05)
        }
    }

    public func recordCorrection(_ correction: OwnerCorrection) async throws {
        try mutate { model in
            model.corrections.append(correction)
            model.rejectedPatterns.append(OwnerPattern(
                summary: correction.originalBehavior,
                evidence: correction.evidence,
                confidence: 0.7,
                updatedAt: correction.createdAt
            ))
            model.acceptedPatterns.append(OwnerPattern(
                summary: correction.correctedBehavior,
                evidence: correction.evidence,
                confidence: 0.7,
                updatedAt: correction.createdAt
            ))
            model.updatedAt = Date()
            model.confidence = min(1.0, model.confidence + 0.1)
        }
    }

    public func updateStandards(_ standards: [OwnerStandard]) async throws {
        try mutate { model in
            model.projectStandards = standards
            model.updatedAt = Date()
            model.confidence = min(1.0, model.confidence + 0.05)
        }
    }

    public func buildContext(for request: String) async throws -> OwnerModelContext {
        let snapshot = lock.withLock { model }
        return OwnerModelContext(
            request: request,
            communication: snapshot.communication,
            decisions: snapshot.decisions,
            activeStandards: snapshot.projectStandards,
            relevantAcceptedPatterns: relevantPatterns(snapshot.acceptedPatterns, for: request),
            relevantRejectedPatterns: relevantPatterns(snapshot.rejectedPatterns, for: request),
            recentCorrections: Array(snapshot.corrections.suffix(10)),
            confidence: snapshot.confidence
        )
    }

    private func mutate(_ body: (inout OwnerModel) -> Void) throws {
        var snapshot: OwnerModel!
        lock.withLock {
            body(&model)
            snapshot = model
        }
        try Self.write(model: snapshot, to: filePath)
    }

    private func relevantPatterns(_ patterns: [OwnerPattern], for request: String) -> [OwnerPattern] {
        let terms = Set(request.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let scored = patterns.map { pattern -> (OwnerPattern, Int) in
            let words = Set(pattern.summary.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
            return (pattern, words.intersection(terms).count)
        }
        let matches = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.map(\.0)
        return Array((matches.isEmpty ? patterns.suffix(10) : matches.prefix(10)))
    }

    private static func write(model: OwnerModel, to path: String) throws {
        let data = try JSONEncoder.aresOwnerModelEncoder.encode(model)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

private extension JSONEncoder {
    static var aresOwnerModelEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var aresOwnerModelDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
