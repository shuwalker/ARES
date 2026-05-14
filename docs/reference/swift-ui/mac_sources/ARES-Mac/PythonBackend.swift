import Foundation

class PythonBackend {
    private var process: Process?
    private let session: URLSession
    private let baseURL = URL(string: "http://localhost:9876")!
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5
        session = URLSession(configuration: config)
    }
    
    func start() {
        guard process == nil else { return }
        
        let bundlePath = Bundle.main.bundleURL
            .appendingPathComponent("Sources/ARES-MacBackend/backend_main.py").path
        
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let pythonPath = "\(homeDir)/.hermes/hermes-agent/venv/bin/python3"
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [bundlePath]
        proc.environment = [
            "PATH": "/usr/local/bin:/usr/bin:/bin",
            "HOME": homeDir
        ]
        
        do {
            try proc.run()
            process = proc
            Logger().info("Python backend started")
        } catch {
            Logger().error("Failed to start backend: \(error)")
        }
    }
    
    func stop() {
        process?.terminate()
        process = nil
    }
    
    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.start()
        }
    }
    
    func wake() {
        post(path: "/wake", body: ["source": "user"])
    }
    
    func think(text: String) {
        post(path: "/think", body: ["text": text])
    }
    
    func idle() {
        post(path: "/idle", body: [:])
    }
    
    private func post(path: String, body: [String: Any]) {
        guard let url = URL(string: path, relativeTo: baseURL) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: req).resume()
    }
}
