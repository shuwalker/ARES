import Foundation
import Combine
import Network
import ARESCore

@MainActor
public final class WebUIServerManager: ObservableObject {
    public static let shared = WebUIServerManager()

    @Published public var isRunning = false
    @Published public var portConflict = false
    @Published public var serverHealth = "Stopped" // "Stopped", "Starting...", "Running (Healthy)", "Running (Degraded)", "Running (Unreachable)", "Failed"
    @Published public var recentLogs = ""

    private var process: Process?
    private var healthCheckTimer: Timer?
    private var logTimer: Timer?

    private init() {
        // Periodically check logs and health if running
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkHealth()
            }
        }
        
        logTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.readLastLogs()
            }
        }
    }

    public func start() async {
        guard process == nil else { return }
        
        let config = ARESConfiguration.shared
        let host = config.webuiHost
        let port = config.webuiPort
        
        serverHealth = "Checking port..."
        
        // Check if port is in use
        let inUse = await isPortInUse(port, host: host)
        if inUse {
            portConflict = true
            serverHealth = "Port \(port) conflict detected"
            return
        }
        portConflict = false
        serverHealth = "Starting..."

        let webuiDir = findWebUIDir()
        guard let dir = webuiDir else {
            serverHealth = "WebUI directory not found"
            return
        }

        let process = Process()
        process.currentDirectoryURL = dir
        process.executableURL = dir.appendingPathComponent(".venv/bin/python")
        process.arguments = ["server.py"]
        
        var env = ProcessInfo.processInfo.environment
        env["HERMES_WEBUI_HOST"] = host
        env["HERMES_WEBUI_PORT"] = String(port)
        env["ARES_WEBUI_RELOAD"] = config.reloadDevMode ? "1" : "0"
        process.environment = env

        // Redirect logs to webui.log
        let logFileURL = config.configDirectory.appendingPathComponent("webui.log")
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        if let logFileHandle = try? FileHandle(forWritingTo: logFileURL) {
            logFileHandle.seekToEndOfFile()
            process.standardOutput = logFileHandle
            process.standardError = logFileHandle
        }

        do {
            try process.run()
            self.process = process
            self.isRunning = true
            self.serverHealth = "Running (Healthy)"
            print("[ARES] WebUI server started on http://\(host):\(port)")
        } catch {
            self.serverHealth = "Failed: \(error.localizedDescription)"
            print("[ARES] Failed to start WebUI: \(error)")
        }
    }

    public func stop() {
        guard let p = process else { return }
        p.terminate()
        process = nil
        isRunning = false
        serverHealth = "Stopped"
    }

    public func restart() async {
        stop()
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        await start()
    }

    private func checkHealth() async {
        if let p = process, !p.isRunning {
            isRunning = false
            process = nil
            serverHealth = "Exited (code: \(p.terminationStatus))"
            return
        }

        guard isRunning, let _ = process else {
            if process == nil && (serverHealth.hasPrefix("Running") || serverHealth == "Starting...") {
                serverHealth = "Stopped"
                isRunning = false
            }
            return
        }

        let config = ARESConfiguration.shared
        let urlString = "http://\(config.webuiHost):\(config.webuiPort)/health"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                serverHealth = "Running (Healthy)"
            } else {
                serverHealth = "Running (Degraded)"
            }
        } catch {
            serverHealth = "Running (Unreachable)"
        }
    }

    private func readLastLogs() {
        let config = ARESConfiguration.shared
        let logFileURL = config.configDirectory.appendingPathComponent("webui.log")
        guard FileManager.default.fileExists(atPath: logFileURL.path) else { return }
        
        do {
            let content = try String(contentsOf: logFileURL, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let lastLines = lines.suffix(100)
            self.recentLogs = lastLines.joined(separator: "\n")
        } catch {}
    }

    private func isPortInUse(_ port: Int, host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
            let connection = NWConnection(to: endpoint, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    continuation.resume(returning: true)
                case .waiting(_):
                    connection.cancel()
                    continuation.resume(returning: false)
                case .failed(_):
                    connection.cancel()
                    continuation.resume(returning: false)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
                connection.cancel()
            }
        }
    }

    private func findWebUIDir() -> URL? {
        if let bundlePath = Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() {
            let webuiPath = bundlePath.appendingPathComponent("webui")
            if FileManager.default.fileExists(atPath: webuiPath.appendingPathComponent("server.py").path) {
                return webuiPath
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let devPath = home.appendingPathComponent("GitHub/ARES/webui")
        if FileManager.default.fileExists(atPath: devPath.appendingPathComponent("server.py").path) {
            return devPath
        }
        return nil
    }
}
