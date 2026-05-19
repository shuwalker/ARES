import Foundation

extension DashboardAPIService {

    // MARK: - Sessions

    /// PATCH /api/sessions/{id} — rename a session by updating its title.
    /// This is a best-effort call: if the endpoint is unavailable the error is propagated
    /// to the caller, which may choose to swallow it gracefully.
    func renameSession(id: String, title: String) async throws {
        try await ensureSessionToken()
        let path = "api/sessions/\(id)"
        let payload = try JSONEncoder().encode(["title": title])

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }
}
