import Foundation

struct AresAPI {
    let baseURL = "http://localhost:7860"

    // MARK: - Models

    struct Status: Codable {
        let name: String
        let version: String
        let faceState: String
        let websocketClients: Int
        let uptime: Double
    }

    struct Identity: Codable {
        let name: String
        let role: String
        let voice: String?
    }

    struct ChatRequest: Codable {
        let message: String
        let sessionId: String?
    }

    struct ChatResponse: Codable {
        let text: String
        let faceState: String
        let memory: [MemoryHit]?
    }

    struct MemoryHit: Codable {
        let id: String
        let text: String
        let score: Double
    }

    struct FaceState: Codable {
        let state: String
        let config: FaceConfig?
    }

    struct FaceConfig: Codable {
        let color: [Double]
        let opacity: Double
        let pulseSpeed: Double
        let pulseAmount: Double
    }

    // MARK: - API Methods

    func getStatus() async throws -> Status {
        let url = URL(string: "\(baseURL)/api/status")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Status.self, from: data)
    }

    func getIdentity() async throws -> Identity {
        let url = URL(string: "\(baseURL)/api/identity")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Identity.self, from: data)
    }

    func getFaceState() async throws -> FaceState {
        let url = URL(string: "\(baseURL)/api/face")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(FaceState.self, from: data)
    }

    func chat(message: String) async throws -> ChatResponse {
        let url = URL(string: "\(baseURL)/api/chat")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(ChatRequest(message: message, sessionId: nil))

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ChatResponse.self, from: data)
    }

    func getMemory() async throws -> [MemoryHit] {
        let url = URL(string: "\(baseURL)/api/memory/episodics")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([MemoryHit].self, from: data)
    }
}
