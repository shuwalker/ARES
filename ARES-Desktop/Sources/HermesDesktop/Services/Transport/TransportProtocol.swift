import Foundation

/// Result type for raw transport commands (mirrors SSHCommandResult)
struct TransportCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

/// Error type for transport operations
enum TransportError: LocalizedError, Equatable {
    case invalidConnection(String)
    case launchFailure(String)
    case localFailure(String)
    case remoteFailure(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidConnection(let msg),
             .launchFailure(let msg),
             .localFailure(let msg),
             .remoteFailure(let msg),
             .invalidResponse(let msg):
            msg
        }
    }
}

/// Transport kind discriminator for connection profiles
enum TransportKind: String, Codable, Sendable, CaseIterable {
    case ssh
    case local
}

/// Protocol abstracting transport for Hermes service calls.
/// SSHTransport conforms to this for remote connections.
/// HTTPTransport conforms to this for local Hermes API connections.
protocol HermesTransport: Sendable {
    func execute(
        on connection: ConnectionProfile,
        remoteCommand: String,
        standardInput: Data?,
        allocateTTY: Bool
    ) async throws -> TransportCommandResult

    func executeJSON<Response: Decodable>(
        on connection: ConnectionProfile,
        pythonScript: String,
        responseType: Response.Type
    ) async throws -> Response

    func validateSuccessfulExit(
        _ result: TransportCommandResult,
        for connection: ConnectionProfile?
    ) throws
}
