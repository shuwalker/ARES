import Foundation

/// Service that calls the Hermes dashboard web API (port 9119) using HTTPTransport.
/// Authenticates via the ephemeral session token injected into the dashboard SPA HTML.
final class DashboardAPIService: @unchecked Sendable {
    internal let httpTransport: HTTPTransport
    var baseURL: URL

    /// Ephemeral session token obtained from the dashboard HTML.
    /// Regenerated on each server start; must be fetched before making authenticated requests.
    internal var sessionToken: String?

    /// Creates a new dashboard API service.
    /// - Parameters:
    ///   - httpTransport: The transport layer for making HTTP requests.
    ///   - baseURL: The root URL of the dashboard API. Defaults to `http://localhost:9119`.
    init(
        httpTransport: HTTPTransport,
        baseURL: URL = URL(string: "http://localhost:9119")!
    ) {
        self.httpTransport = httpTransport
        self.baseURL = baseURL
    }

    // MARK: - Authentication

    /// Fetches the session token from the dashboard HTML if we don't have one yet.
    func ensureSessionToken() async throws {
        guard sessionToken == nil else { return }

        let data = try await httpTransport.get(
            path: "/",
            baseURL: baseURL,
            apiKey: nil
        )

        guard let html = String(data: data, encoding: .utf8) else {
            throw TransportError.localFailure("Dashboard HTML was not valid UTF-8")
        }

        // Extract: window.__HERMES_SESSION_TOKEN__="...value...";
        let pattern = #"__HERMES_SESSION_TOKEN__=\\"([^"]+)\\""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tokenRange = Range(match.range(at: 1), in: html) else {
            // If no token found, the dashboard might be running without auth.
            // Leave sessionToken nil — requests will try without token.
            return
        }

        sessionToken = String(html[tokenRange])
    }

    func authenticatedGet(path: String) async throws -> Data {
        try await ensureSessionToken()

        // Try with session token header first
        if let token = sessionToken {
            do {
                return try await httpTransport.getWithHeaders(
                    path: path,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                // If we get 401, the token may have expired (server restart).
                // Clear it and retry.
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.getWithHeaders(
                            path: path,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        // No token available — try unauthenticated (some endpoints don't require auth)
        return try await httpTransport.get(path: path, baseURL: baseURL, apiKey: nil)
    }

    func authenticatedPost(path: String, body: Data) async throws -> Data {
        try await ensureSessionToken()

        if let token = sessionToken {
            do {
                return try await httpTransport.postWithHeaders(
                    path: path,
                    body: body,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.postWithHeaders(
                            path: path,
                            body: body,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        return try await httpTransport.post(path: path, body: body, baseURL: baseURL, apiKey: nil)
    }

    func authenticatedPut(path: String, body: Data) async throws -> Data {
        try await ensureSessionToken()

        if let token = sessionToken {
            do {
                return try await httpTransport.putWithHeaders(
                    path: path,
                    body: body,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.putWithHeaders(
                            path: path,
                            body: body,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        return try await httpTransport.put(path: path, body: body, baseURL: baseURL, apiKey: nil)
    }

    func authenticatedDelete(path: String) async throws -> Data {
        try await ensureSessionToken()

        if let token = sessionToken {
            do {
                return try await httpTransport.deleteWithHeaders(
                    path: path,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.deleteWithHeaders(
                            path: path,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        return try await httpTransport.delete(path: path, baseURL: baseURL, apiKey: nil)
    }

    // MARK: - Status (public, no auth needed)

    func fetchStatus() async throws -> StatusResponse {
        let data = try await httpTransport.get(
            path: "api/status",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }
}
