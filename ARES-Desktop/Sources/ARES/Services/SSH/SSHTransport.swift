import Foundation

/// Stub for SSHTransport — the real implementation was removed during the pure-ARES architecture refactor.
/// All methods fatalError at runtime. Replace with a real SSH transport layer before re-enabling remote features.

// MARK: - SSHTransportError

enum SSHTransportError: LocalizedError {
    case invalidResponse(String)
    case remoteFailure(String)
    case launchFailure(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message): return message
        case .remoteFailure(let message): return message
        case .launchFailure(let message): return message
        }
    }
}

// MARK: - SSHTransportResult

struct SSHTransportResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

// MARK: - SSHTransport

final class SSHTransport: @unchecked Sendable {
    let paths: AppPaths

    init(paths: AppPaths) {
        self.paths = paths
    }

    // MARK: - Execute (raw command)

    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data? = nil,
        allocateTTY: Bool = false
    ) async throws -> SSHTransportResult {
        fatalError("SSHTransport.execute(on:remoteCommand:standardInput:allocateTTY:) is not implemented")
    }

    // MARK: - Execute JSON (typed response)

    func executeJSON<T: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: T.Type
    ) async throws -> T {
        fatalError("SSHTransport.executeJSON(on:pythonScript:responseType:) is not implemented")
    }

    // MARK: - Validation helpers

    func validateSuccessfulExit(
        _ result: SSHTransportResult,
        for connection: ConnectionProfile
    ) throws {
        fatalError("SSHTransport.validateSuccessfulExit(_:for:) is not implemented")
    }

    // MARK: - Terminal / shell arguments

    func shellArguments(
        for connection: ConnectionProfile,
        startupCommandLine: String? = nil
    ) -> [String] {
        fatalError("SSHTransport.shellArguments(for:startupCommandLine:) is not implemented")
    }

    // MARK: - Service arguments (for Process-based SSH)

    func serviceArguments(
        for connection: ConnectionProfile,
        remoteCommand: String,
        allocateTTY: Bool
    ) -> [String] {
        fatalError("SSHTransport.serviceArguments(for:remoteCommand:allocateTTY:) is not implemented")
    }

    // MARK: - Diagnostics

    func describeRemoteFailure(
        stdout: String,
        stderr: String,
        exitCode: Int32,
        connection: ConnectionProfile
    ) -> String {
        fatalError("SSHTransport.describeRemoteFailure(stdout:stderr:exitCode:connection:) is not implemented")
    }
}
