import Foundation

extension ConnectionProfile {
    /// Transport kind for this connection. Defaults to .ssh for existing profiles.
    /// .local connections use HTTP/WebSocket to talk to a local Hermes instance directly.
    var transportKind: TransportKind {
        // If sshHost is empty (new local profile), this is a local connection
        // For backward compat, existing SSH profiles remain .ssh
        sshHost.isEmpty && sshAlias.isEmpty ? .local : .ssh
    }

    /// HTTP base URL for local Hermes API connections (port 8642)
    var httpBaseURL: URL {
        // Default to localhost:8642 for local connections
        // Custom port can be configured via sshPort field reused as HTTP port
        let port = resolvedPort ?? 8642
        return URL(string: "http://localhost:\(port)")!
    }

    /// API key for local Hermes API connections
    var apiKey: String? {
        // For local connections, we'll use a stored API key
        // This will be populated from the connection editor
        // For now, nil means no auth required (local network)
        return nil
    }
}
