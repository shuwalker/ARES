import Foundation

/// Detects locally running AI brains on this Mac — Hermes gateway, Ollama, Claude Code.
/// Runs once on first launch to auto-create a "This Mac" connection.
enum LocalBrainDetector {
    
    /// Ports to probe on localhost
    private static let probePorts: [(port: Int, label: String)] = [
        (8321, "Hermes Gateway"),
        (9119, "Hermes Gateway (alt)"),
        (11434, "Ollama"),
    ]
    
    /// CLI tools that indicate a local brain
    private static let probeCLIs: [(command: String, label: String)] = [
        ("hermes", "Hermes"),
        ("claude", "Claude Code"),
        ("ollama", "Ollama CLI"),
    ]
    
    // MARK: - Public
    
    /// Scan for local brains and return a summary.
    /// Call on app launch (non-blocking — runs network checks asynchronously).
    static func detectLocalBrains() async -> LocalBrainScan {
        var results: [LocalBrainService] = []
        
        // Check running servers via port probes
        await withTaskGroup(of: LocalBrainService?.self) { group in
            for probe in probePorts {
                group.addTask {
                    if await isPortOpen(port: probe.port) {
                        return LocalBrainService(
                            name: probe.label,
                            port: probe.port,
                            kind: .server
                        )
                    }
                    return nil
                }
            }
            
            // Check CLI tools
            for cli in probeCLIs {
                group.addTask {
                    if isCLIAvailable(command: cli.command) {
                        return LocalBrainService(
                            name: cli.label,
                            port: nil,
                            kind: .cli
                        )
                    }
                    return nil
                }
            }
            
            for await result in group {
                if let service = result {
                    results.append(service)
                }
            }
        }
        
        return LocalBrainScan(
            timestamp: Date(),
            services: results,
            primaryGatewayPort: results.first(where: { $0.port == 8321 || $0.port == 9119 })?.port
        )
    }
    
    /// Create a "This Mac" connection if one doesn't exist yet.
    /// Returns the profile for "This Mac" or nil if one already exists.
    @MainActor
    static func createThisMacConnectionIfNeeded(in store: ConnectionStore) -> ConnectionProfile? {
        // Check if a localhost connection already exists
        let hasLocalhost = store.connections.contains { profile in
            profile.sshHost == "localhost" || 
            profile.sshHost == "127.0.0.1" ||
            profile.label.caseInsensitiveCompare("This Mac") == .orderedSame
        }
        
        guard !hasLocalhost else { return nil }
        
        var thisMac = ConnectionProfile()
        thisMac.label = "This Mac"
        thisMac.sshAlias = "localhost"
        thisMac.sshHost = "localhost"
        thisMac.sshUser = NSUserName()
        thisMac.sshPort = nil
        thisMac.hermesProfile = nil
        
        store.upsert(thisMac)
        return thisMac
    }
    
    /// Full onboarding: scan + create this-mac connection.
    /// Returns the connection to activate, or nil if one already existed.
    static func onboard() async -> (scan: LocalBrainScan, autoConnection: ConnectionProfile?)? {
        let scan = await detectLocalBrains()
        
        // Don't onboard if scan found nothing usable
        guard scan.hasAnyBrain else { return nil }
        
        // Create the connection via ConnectionStore singleton (injected from AppState)
        return (scan, nil) // actual connection creation happens in AppState
    }
    
    // MARK: - Private
    
    private static func isPortOpen(port: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let task = Task.detached {
                let sock = socket(AF_INET, SOCK_STREAM, 0)
                guard sock >= 0 else {
                    continuation.resume(returning: false)
                    return
                }
                defer { close(sock) }
                
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = UInt16(port).bigEndian
                addr.sin_addr.s_addr = inet_addr("127.0.0.1")
                
                // Set 200ms timeout
                var timeout = timeval(tv_sec: 0, tv_usec: 200_000)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                
                let result = withUnsafePointer(to: &addr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                
                continuation.resume(returning: result == 0)
            }
        }
    }
    
    private static func isCLIAvailable(command: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Models

struct LocalBrainScan {
    let timestamp: Date
    let services: [LocalBrainService]
    let primaryGatewayPort: Int?
    
    var hasAnyBrain: Bool { !services.isEmpty }
    var hasServer: Bool { services.contains(where: { $0.isServer }) }
    var hasCLI: Bool { services.contains(where: { $0.isCLI }) }
    
    var summary: String {
        let servers = services.filter(\.isServer).map(\.name).joined(separator: ", ")
        let clis = services.filter(\.isCLI).map(\.name).joined(separator: ", ")
        var parts: [String] = []
        if !servers.isEmpty { parts.append("Servers: \(servers)") }
        if !clis.isEmpty { parts.append("CLIs: \(clis)") }
        return parts.isEmpty ? "No local brains detected" : parts.joined(separator: " | ")
    }
}

struct LocalBrainService {
    enum Kind { case server, cli }
    
    let name: String
    let port: Int?
    let kind: Kind
    
    var isServer: Bool { kind == .server }
    var isCLI: Bool { kind == .cli }
}
