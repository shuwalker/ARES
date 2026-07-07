import Foundation

/// Identity protocol: persistent, immutable self-model.
/// Conforming types: FileSystemIdentity, iCloudIdentity
///
/// Rules: Once set, identity is immutable for the session.
/// Only reset on explicit user action.
public protocol Identity: AnyObject, Sendable {
    /// Unique persistent identifier for this ARES instance.
    var id: UUID { get }

    /// User-facing name for this ARES instance.
    /// Examples: "ARES (Mac Studio)", "ARES (MacBook)"
    var displayName: String { get }

    /// Who's running this — user email, org, project ID, etc.
    var ownerInfo: [String: AnyCodable] { get }

    /// Hardware this instance is bound to (serial, MAC, etc.)
    var hardware: HardwareProfile { get }

    /// When this identity was created.
    var createdAt: Date { get }

    /// Get self metadata.
    func getMetadata() async throws -> IdentityMetadata

    /// Update display name only.
    func updateDisplayName(_ name: String) async throws

    /// Reset identity (dangerous; logs warning).
    func reset() async throws
}

/// Hardware profile bound to this ARES instance.
public struct HardwareProfile: Codable, Sendable, Equatable {
    public let deviceModel: String              // "Mac Studio", "MacBook Pro", etc.
    public let macAddress: String              // Primary network interface
    public let serialNumber: String             // Hardware serial
    public let cpuCoreCount: Int
    public let totalMemoryGB: Int
    public let timestamp: Date

    public init(
        deviceModel: String,
        macAddress: String,
        serialNumber: String,
        cpuCoreCount: Int,
        totalMemoryGB: Int,
        timestamp: Date = Date()
    ) {
        self.deviceModel = deviceModel
        self.macAddress = macAddress
        self.serialNumber = serialNumber
        self.cpuCoreCount = cpuCoreCount
        self.totalMemoryGB = totalMemoryGB
        self.timestamp = timestamp
    }
}

/// Identity metadata + version.
public struct IdentityMetadata: Codable, Sendable {
    public let id: UUID
    public let displayName: String
    public let ownerEmail: String?
    public let createdAt: Date
    public let lastUpdatedAt: Date
    public let hardwareProfile: HardwareProfile
    public let version: String

    public init(
        id: UUID,
        displayName: String,
        ownerEmail: String? = nil,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        hardwareProfile: HardwareProfile,
        version: String = "1.0.0"
    ) {
        self.id = id
        self.displayName = displayName
        self.ownerEmail = ownerEmail
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.hardwareProfile = hardwareProfile
        self.version = version
    }
}
