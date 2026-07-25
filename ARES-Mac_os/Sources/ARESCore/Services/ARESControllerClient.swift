import Foundation

/// Shared HTTP client for the ARES controller (FastAPI).
/// Native Mac app and future remote clients use the same contracts as the WebUI.
public actor ARESControllerClient {
    public struct Readiness: Sendable, Equatable {
        public var profileReady: Bool
        public var connectionReady: Bool
        public var executionAvailable: Bool

        public init(profileReady: Bool, connectionReady: Bool, executionAvailable: Bool) {
            self.profileReady = profileReady
            self.connectionReady = connectionReady
            self.executionAvailable = executionAvailable
        }
    }

    public struct ConnectionRecord: Sendable, Identifiable, Equatable {
        public var id: String
        public var name: String
        public var kind: String
        public var state: String
        public var detail: String
        public var available: Bool
        public var selected: Bool

        public init(
            id: String,
            name: String,
            kind: String,
            state: String,
            detail: String,
            available: Bool,
            selected: Bool
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.state = state
            self.detail = detail
            self.available = available
            self.selected = selected
        }
    }

    private let session: URLSession
    private let baseURLProvider: @Sendable () -> URL

    public init(
        session: URLSession = .shared,
        baseURLProvider: @escaping @Sendable () -> URL
    ) {
        self.session = session
        self.baseURLProvider = baseURLProvider
    }

    public static func sharedForConfiguration() -> ARESControllerClient {
        ARESControllerClient {
            let config = ARESConfiguration.shared
            var components = URLComponents()
            components.scheme = "http"
            components.host = config.webuiHost
            components.port = config.webuiPort
            return components.url ?? URL(string: "http://127.0.0.1:8787")!
        }
    }

    public func fetchReadiness() async throws -> Readiness {
        let data = try await get(path: "/api/readiness")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return Readiness(
            profileReady: json["profile_ready"] as? Bool ?? false,
            connectionReady: json["connection_ready"] as? Bool ?? false,
            executionAvailable: json["execution_available"] as? Bool ?? false
        )
    }

    public func fetchConnections() async throws -> [ConnectionRecord] {
        let data = try await get(path: "/api/connections")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let rows = json["connections"] as? [[String: Any]]
            ?? json["items"] as? [[String: Any]]
            ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? String ?? row["adapter_id"] as? String else { return nil }
            let health = row["health"] as? [String: Any] ?? [:]
            return ConnectionRecord(
                id: id,
                name: row["name"] as? String ?? id,
                kind: row["kind"] as? String ?? "unknown",
                state: health["state"] as? String
                    ?? row["state"] as? String
                    ?? row["status"] as? String
                    ?? "offline",
                detail: health["message"] as? String
                    ?? row["detail"] as? String
                    ?? row["message"] as? String
                    ?? "",
                available: health["available"] as? Bool
                    ?? row["available"] as? Bool
                    ?? false,
                selected: row["selected"] as? Bool ?? false
            )
        }
    }

    public func healthOK() async -> Bool {
        do {
            _ = try await get(path: "/health")
            return true
        } catch {
            return false
        }
    }

    private func get(path: String) async throws -> Data {
        let base = baseURLProvider()
        guard let url = URL(string: path, relativeTo: base)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
