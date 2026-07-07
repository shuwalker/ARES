import Foundation

/// Test/default owner model provider. It is intentionally generic and contains
/// no real owner data.
public final class DummyOwnerModelProvider: OwnerModelProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var model: OwnerModel

    public init(model: OwnerModel = OwnerModel()) {
        self.model = model
    }

    public func getOwnerModel() async throws -> OwnerModel {
        lock.withLock { model }
    }

    public func recordPreference(_ preference: OwnerPreference) async throws {
        lock.withLock {
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
        lock.withLock {
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
        lock.withLock {
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
            relevantAcceptedPatterns: Array(snapshot.acceptedPatterns.suffix(10)),
            relevantRejectedPatterns: Array(snapshot.rejectedPatterns.suffix(10)),
            recentCorrections: Array(snapshot.corrections.suffix(10)),
            confidence: snapshot.confidence
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
