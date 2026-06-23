import Foundation

final class HermesGateway: @unchecked Sendable {
    let baseURL: String

    init(url: String = "http://localhost:8642") {
        self.baseURL = url
    }

    func chat(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300

        let body: [String: Any] = [
            "messages": messages,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GatewayError.httpError
        }

        struct ChatResponse: Codable {
            let choices: [Choice]
            struct Choice: Codable {
                let message: Message
                struct Message: Codable {
                    let content: String
                }
            }
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        return decoded.choices.first?.message.content ?? ""
    }

    func health() async throws -> Bool {
        let url = URL(string: "\(baseURL)/health")!
        var req = URLRequest(url: url, timeoutInterval: 5)
        let (_, response) = try await URLSession.shared.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

enum GatewayError: LocalizedError {
    case httpError
    var errorDescription: String? {
        switch self {
        case .httpError: return "Gateway HTTP error"
        }
    }
}
