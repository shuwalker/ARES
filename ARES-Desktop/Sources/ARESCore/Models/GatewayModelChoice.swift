import Foundation

/// Represents a model available from a GatewayProvider.
public struct GatewayModelChoice: Identifiable, Hashable, Sendable {
    public let provider: String
    public let model: String
    public let displayName: String
    public let summary: String

    public var id: String { "\(provider)/\(model)" }

    public init(
        provider: String,
        model: String,
        displayName: String,
        summary: String
    ) {
        self.provider = provider
        self.model = model
        self.displayName = displayName
        self.summary = summary
    }
}
