import Foundation

extension ConnectionProfile {
    var transportKind: TransportKind {
        sshHost.isEmpty && sshAlias.isEmpty ? .local : .ssh
    }

    var httpBaseURL: URL {
        let port = sshPort ?? 8642
        return URL(string: "http://localhost:\(port)")!
    }

    var dashboardURL: URL {
        let port = sshPort ?? 9119
        let host = sshHost.isEmpty ? "localhost" : sshHost
        return URL(string: "http://\(host):\(port)")!
    }

    /// Returns the dashboard URL for direct HTTP (LAN) transport mode.
    var directHTTPBaseURL: URL {
        let host = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedHost = host.isEmpty ? "localhost" : host
        let port = dashboardPort ?? 9119
        return URL(string: "http://\(resolvedHost):\(port)")!
    }

    /// Returns the dashboard URL via an SSH local port-forward tunnel.
    func tunneledDashboardURL(localPort: Int) -> URL {
        URL(string: "http://localhost:\(localPort)")!
    }

    var apiKey: String? {
        return nil
    }
}