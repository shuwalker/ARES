import ARESCore
import Foundation

// MARK: - FileSystem-backed Identity
//
// Persists identity to a JSON file on disk. The file is stored at the
// configured path (default: ~/.ares/identity.json).
//
// Identity is immutable for the session once loaded — only `updateDisplayName`
// and `reset()` mutate state. Both are thread-safe via NSLock.
//
// On first launch, if no identity file exists, one is created with hardware
// profile auto-detected from the current machine and a default display name.

public final class FileSystemIdentity: Identity, @unchecked Sendable {
    private let filePath: String
    private let lock = NSLock()
    private var identityData: IdentityData

    // MARK: - Identity Protocol Properties

    public var id: UUID { lock.withLock { identityData.id } }
    public var displayName: String { lock.withLock { identityData.displayName } }
    public var ownerInfo: [String: AnyCodable] {
        lock.withLock { identityData.ownerInfo }
    }
    public var hardware: HardwareProfile {
        lock.withLock { identityData.hardware }
    }
    public var createdAt: Date {
        lock.withLock { identityData.createdAt }
    }

    // MARK: - Init

    public init(path: String) throws {
        let expandedPath = NSString(string: path).expandingTildeInPath
        self.filePath = expandedPath

        // Ensure parent directory exists
        let dir = NSString(string: expandedPath).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Load existing identity or create a new one
        if FileManager.default.fileExists(atPath: expandedPath) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: expandedPath))
                self.identityData = try JSONDecoder().decode(IdentityData.self, from: data)
                print("✅ [IDENTITY] Loaded identity: \(identityData.displayName) (\(identityData.id))")
            } catch {
                print("⚠️  [IDENTITY] Failed to parse identity file, creating new: \(error)")
                self.identityData = Self.createDefaultIdentity()
                try saveToDisk()
            }
        } else {
            self.identityData = Self.createDefaultIdentity()
            try saveToDisk()
            print("✅ [IDENTITY] Created new identity: \(identityData.displayName) (\(identityData.id))")
        }
    }

    // MARK: - Identity Protocol Methods

    public func getMetadata() async throws -> IdentityMetadata {
        lock.withLock {
            IdentityMetadata(
                id: identityData.id,
                displayName: identityData.displayName,
                ownerEmail: identityData.ownerEmail,
                createdAt: identityData.createdAt,
                lastUpdatedAt: identityData.lastUpdatedAt,
                hardwareProfile: identityData.hardware,
                version: identityData.version
            )
        }
    }

    public func updateDisplayName(_ name: String) async throws {
        lock.withLock {
            identityData.displayName = name
            identityData.lastUpdatedAt = Date()
        }
        try saveToDisk()
        print("✏️ [IDENTITY] Display name → \(name)")
    }

    public func reset() async throws {
        print("⚠️  [IDENTITY] Reset called — regenerating identity")
        lock.withLock {
            identityData = Self.createDefaultIdentity()
        }
        try saveToDisk()
    }

    // MARK: - Persistence

    private func saveToDisk() throws {
        let data = try lock.withLock { try JSONEncoder().encode(identityData) }
        try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
    }

    // MARK: - Default Identity Creation

    private static func createDefaultIdentity() -> IdentityData {
        let hw = detectHardwareProfile()
        return IdentityData(
            id: UUID(),
            displayName: "ARES (\(hw.deviceModel))",
            ownerEmail: nil,
            ownerInfo: [:],
            createdAt: Date(),
            lastUpdatedAt: Date(),
            hardware: hw,
            version: "1.0.0"
        )
    }

    // MARK: - Hardware Detection

    private static func detectHardwareProfile() -> HardwareProfile {
        let deviceModel = getDeviceModel()
        let macAddress = getMacAddress()
        let serialNumber = getSerialNumber()
        let cpuCoreCount = ProcessInfo.processInfo.activeProcessorCount
        let totalMemoryGB = ProcessInfo.processInfo.physicalMemory / 1_073_741_824  // bytes to GB

        return HardwareProfile(
            deviceModel: deviceModel,
            macAddress: macAddress,
            serialNumber: serialNumber,
            cpuCoreCount: cpuCoreCount,
            totalMemoryGB: Int(totalMemoryGB)
        )
    }

    private static func getDeviceModel() -> String {
        // Read from system_profiler or sysctl
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelStr = String(cString: model)

        // Map hardware model codes to friendly names
        switch modelStr {
        case let m where m.hasPrefix("Mac14,") || m.hasPrefix("Mac15,"):
            return "Mac Studio"
        case let m where m.hasPrefix("MacBookPro"):
            return "MacBook Pro"
        case let m where m.hasPrefix("MacBookAir"):
            return "MacBook Air"
        default:
            return modelStr.isEmpty ? "Unknown Mac" : modelStr
        }
    }

    private static func getMacAddress() -> String {
        // Use en0's MAC address as the primary identifier
        let interface = "en0"
        var macAddress = ""

        // Try IOKit approach via system call
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        process.arguments = [interface]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse ether line: "ether xx:xx:xx:xx:xx:xx"
            if let range = output.range(of: "ether ") {
                let afterEther = output[range.upperBound...]
                if let endRange = afterEther.firstIndex(where: { $0.isWhitespace || $0 == "\n" }) {
                    macAddress = String(afterEther[..<endRange])
                }
            }
        } catch {
            macAddress = "00:00:00:00:00:00"
        }

        return macAddress.isEmpty ? "00:00:00:00:00:00" : macAddress
    }

    private static func getSerialNumber() -> String {
        // Use IOKit to get hardware serial
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse "IOPlatformSerialNumber" = "XXXXXXXXXXX"
            if let range = output.range(of: #"IOPlatformSerialNumber" = ""#) {
                let afterKey = output[range.upperBound...]
                if let endQuote = afterKey.firstIndex(of: "\"") {
                    return String(afterKey[..<endQuote])
                }
            }
        } catch {
            // Fallback
        }

        return "UNKNOWN"
    }
}

// MARK: - Internal Storage Model

private struct IdentityData: Codable {
    let id: UUID
    var displayName: String
    var ownerEmail: String?
    var ownerInfo: [String: AnyCodable]
    let createdAt: Date
    var lastUpdatedAt: Date
    let hardware: HardwareProfile
    let version: String
}

// MARK: - NSLock Extension

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
