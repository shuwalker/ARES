import Foundation

/// Manages SSH key pair generation and distribution for ARES remote connections.
/// Generates an ed25519 key, then helps the user install the public key on the remote Mac.
@MainActor
final class SSHKeyExchange {
    
    struct KeyExchangeResult {
        let keyPath: String           // ~/.ssh/arens_bootstrap_key
        let publicKeyPath: String     // ~/.ssh/arens_bootstrap_key.pub
        let fingerprint: String       // SHA256:abc123...
    }
    
    enum KeyExchangeError: LocalizedError {
        case keyGenerationFailed(String)
        case sshCopyIdFailed(String)
        case verificationFailed(String)
        case keyAlreadyExists(String)
        
        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed(let msg): return "Key generation failed: \(msg)"
            case .sshCopyIdFailed(let msg): return "ssh-copy-id failed: \(msg)"
            case .verificationFailed(let msg): return "Connection verification failed: \(msg)"
            case .keyAlreadyExists(let path): return "Key already exists at \(path)"
            }
        }
    }
    
    private let keyName = "arens_bootstrap_key"
    private let sshTransport: SSHTransport
    private let paths: AppPaths
    
    var keyPath: String { "\(paths.sshDirectory)/\(keyName)" }
    var publicKeyPath: String { "\(keyPath).pub" }
    
    init(sshTransport: SSHTransport, paths: AppPaths) {
        self.sshTransport = sshTransport
        self.paths = paths
    }
    
    // MARK: - Key Generation
    
    /// Generate a new ed25519 keypair for ARES remote connections.
    /// Returns the path and fingerprint. If key already exists, returns its info.
    func generateKey() throws -> KeyExchangeResult {
        let sshDir = paths.sshDirectory
        let fm = FileManager.default
        
        // Ensure ~/.ssh exists
        try fm.createDirectory(atPath: sshDir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: sshDir)
        
        let privPath = keyPath
        let pubPath = publicKeyPath
        
        // If key exists, verify it works
        if fm.fileExists(atPath: privPath) {
            let fingerprint = getFingerprint(for: privPath)
            return KeyExchangeResult(
                keyPath: privPath,
                publicKeyPath: pubPath,
                fingerprint: fingerprint ?? "unknown"
            )
        }
        
        // Generate ed25519 key
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = [
            "-t", "ed25519",
            "-f", privPath,
            "-N", "",                        // no passphrase
            "-C", "ares@\(Host.current().localizedName ?? "local")"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw KeyExchangeError.keyGenerationFailed("ssh-keygen exited with \(process.terminationStatus)")
        }
        
        // Set permissions
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privPath)
        try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: pubPath)
        
        let fingerprint = getFingerprint(for: privPath) ?? "unknown"
        
        return KeyExchangeResult(
            keyPath: privPath,
            publicKeyPath: pubPath,
            fingerprint: fingerprint
        )
    }
    
    // MARK: - Key Distribution
    
    /// Copy the public key to the remote Mac using ssh-copy-id.
    /// Requires password auth for the initial copy, then the key works for all future connections.
    func copyKeyToRemote(connection: ConnectionProfile) async throws {
        let pubPath = publicKeyPath
        
        // Use ssh-copy-id which handles the authorized_keys insertion
        let args = [
            "-i", pubPath,
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "IdentitiesOnly=yes",
            connection.effectiveTarget
        ]
        .filter { !$0.isEmpty }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-copy-id")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw KeyExchangeError.sshCopyIdFailed("ssh-copy-id exited with \(process.terminationStatus)")
        }
    }
    
    /// Verify the key-based auth works by attempting an SSH connection.
    func verifyConnection(connection: ConnectionProfile) async throws -> Bool {
        let testCommand = "echo ARENS_SSH_OK && hermes --version || echo HERMES_NOT_FOUND"
        
        do {
            let result = try await sshTransport.execute(
                on: connection,
                remoteCommand: testCommand,
                allocateTTY: false
            )
            return result.exitCode == 0 && result.stdout.contains("ARENS_SSH_OK")
        } catch {
            return false
        }
    }
    
    /// Get the public key content for manual copy (when ssh-copy-id fails).
    func getPublicKeyContent() -> String? {
        try? String(contentsOfFile: publicKeyPath, encoding: .utf8)
    }
    
    // MARK: - Private
    
    private func getFingerprint(for privateKeyPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh-keygen")
        process.arguments = ["-lf", privateKeyPath]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}