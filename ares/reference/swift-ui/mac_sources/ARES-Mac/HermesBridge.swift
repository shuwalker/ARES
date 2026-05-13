import Foundation

actor HermesBridge {
    private let baseURL: URL
    private let session: URLSession
    private let logger = Logger()
    
    init() {
        baseURL = URL(string: "http://localhost:9876")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }
    
    func think(query: String) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("think"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["text": query])
        
        let (data, _) = try await session.data(for: req)
        let response = try JSONDecoder().decode(ThinkResponse.self, from: data)
        return response.text
    }
    
    func checkHealth() async throws -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("checkpoint"))
        req.httpMethod = "GET"
        let (_, response) = try await session.data(for: req)
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

struct ThinkResponse: Codable {
    let text: String
}
