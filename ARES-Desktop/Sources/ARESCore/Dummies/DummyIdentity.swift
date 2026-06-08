import Foundation

/// In-memory identity for testing.
public final class DummyIdentity: Identity, @unchecked Sendable {
    private let _id = UUID()
    private var _displayName: String
    private let _hardware: HardwareProfile

    public var id: UUID { _id }
    public var displayName: String { _displayName }
    public var ownerInfo: [String: AnyCodable] {
        ["email": .string("user@example.com"), "org": .string("test")]
    }
    public var hardware: HardwareProfile { _hardware }
    public var createdAt: Date { Date() }

    public init() {
        _displayName = "ARES (Dummy)"
        _hardware = HardwareProfile(
            deviceModel: "Mac Studio (Test)",
            macAddress: "00:11:22:33:44:55",
            serialNumber: "DUMMY12345",
            cpuCoreCount: 8,
            totalMemoryGB: 32
        )
        print("🤖 [DUMMY] Identity: \(_id) created")
    }

    public func getMetadata() async throws -> IdentityMetadata {
        IdentityMetadata(
            id: _id,
            displayName: _displayName,
            ownerEmail: "user@example.com",
            hardwareProfile: _hardware
        )
    }

    public func updateDisplayName(_ name: String) async throws {
        _displayName = name
        print("🤖 [DUMMY] Identity name → \(name)")
    }

    public func reset() async throws {
        print("⚠️  [DUMMY] Identity reset called (no-op)")
    }
}
