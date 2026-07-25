import Foundation
import Combine
import Network
import ARESCore

@MainActor
public final class WebUIServerManager: ObservableObject {
    public static let shared = WebUIServerManager()

    nonisolated static let webUIEntrypoint = "fastapi_app/main.py"

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
        
        // Reclaim port if held by orphaned server.py process
        reclaimPort(port)
        
        // Check if port is in use
        let inUse = await isPortInUse(port, host: host)
        if inUse {
            let urlString = "http://\(host):\(port)/health"
            if let url = URL(string: urlString) {
                var request = URLRequest(url: url)
                request.timeoutInterval = 1.0
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                        self.isRunning = true
                        self.process = nil
                        self.serverHealth = "Running (External)"
                        self.portConflict = false
                        print("[ARES] Found running external WebUI server on http://\(host):\(port)")
                        return
                    }
                } catch {
                    // Ignore, fallback to port conflict
                }
            }
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
        // Try both "venv" (install.sh default) and ".venv" (common alternative).
        let fm = FileManager.default
        guard let python = Self.pythonExecutable(in: dir, fileManager: fm) else {
            serverHealth = "Python environment not found — run install.sh"
            return
        }
        process.executableURL = python
        process.arguments = ["-m", "uvicorn", "fastapi_app.main:app", "--port", String(port), "--host", host]
        
        var env = ProcessInfo.processInfo.environment
        env["ARES_WEBUI_HOST"] = host
        env["ARES_WEBUI_PORT"] = String(port)
        env["ARES_WEBUI_RELOAD"] = config.reloadDevMode ? "1" : "0"
        env = Self.applyingGatewayEnvironment(
            to: env,
            hermesURL: config.hermesURL,
            hermesAPIKey: config.hermesAPIKey,
            jrosURL: config.jrosURL,
            jrosAPIKey: config.jrosAPIKey
        )
        env["ARES_ROLE"] = config.aresRole
        env["ARES_DEVICE_ID"] = config.aresDeviceID
        env["ARES_AI_ID"] = config.aresAIID
        env["ARES_PRIMARY_URL"] = config.aresPrimaryURL
        env["ARES_CONTINUITY_DIR"] = config.aresContinuityDir
        if let nativeMCPCommand = Self.nativeMCPExecutable() {
            env["ARES_NATIVE_MCP_COMMAND"] = nativeMCPCommand.path
        }
        process.environment = env

        // Redirect logs to webui.log (truncate if > 10MB to avoid disk bloat)
        let logFileURL = config.configDirectory.appendingPathComponent("webui.log")
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
               let size = attrs[.size] as? UInt64, size > 10 * 1024 * 1024 {
                try? "".write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        } else {
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

    nonisolated static func applyingGatewayEnvironment(
        to base: [String: String],
        hermesURL: String,
        hermesAPIKey: String,
        jrosURL: String,
        jrosAPIKey: String
    ) -> [String: String] {
        var environment = base
        // ARES_API_URL drives remote gateway health/tasks. Gateway-backed chat
        // uses the more specific base URL variable; keep both in sync.
        environment["ARES_API_URL"] = hermesURL
        environment["ARES_WEBUI_GATEWAY_BASE_URL"] = hermesURL
        environment["ARES_JROS_GATEWAY_URL"] = jrosURL
        if hermesAPIKey.isEmpty {
            environment.removeValue(forKey: "ARES_WEBUI_GATEWAY_API_KEY")
        } else {
            environment["ARES_WEBUI_GATEWAY_API_KEY"] = hermesAPIKey
        }
        if jrosAPIKey.isEmpty {
            environment.removeValue(forKey: "ARES_JROS_GATEWAY_KEY")
        } else {
            environment["ARES_JROS_GATEWAY_KEY"] = jrosAPIKey
        }
        return environment
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

        guard isRunning else {
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
                serverHealth = process == nil ? "Running (External)" : "Running (Healthy)"
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
        for candidate in Self.webUICandidates() where Self.containsWebUI(at: candidate) {
            return candidate
        }
        return nil
    }

    nonisolated static func webUICandidates(
        resourceURL: URL? = Bundle.main.resourceURL,
        executableURL: URL? = Bundle.main.executableURL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        currentDirectory: String = FileManager.default.currentDirectoryPath
    ) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent("webui"))
        }
        var directory = executableURL?.deletingLastPathComponent()
        for _ in 0..<5 {
            guard let current = directory else { break }
            candidates.append(current.appendingPathComponent("webui"))
            directory = current.deletingLastPathComponent()
        }
        // An explicit install root must beat the default per-user install.
        if let aresHome = environment["ARES_HOME"], !aresHome.isEmpty {
            candidates.append(URL(fileURLWithPath: aresHome).appendingPathComponent("webui"))
        }
        candidates.append(homeDirectory.appendingPathComponent(".ares/webui"))
        candidates.append(URL(fileURLWithPath: currentDirectory).appendingPathComponent("webui"))
        return candidates
    }

    nonisolated static func containsWebUI(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.fileExists(
            atPath: directory.appendingPathComponent(webUIEntrypoint).path
        )
    }

    nonisolated static func pythonExecutable(
        in directory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        for relativePath in ["venv/bin/python", ".venv/bin/python"] {
            let candidate = directory.appendingPathComponent(relativePath)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    nonisolated static func nativeMCPExecutable(
        executableURL: URL? = Bundle.main.executableURL,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let executableURL else { return nil }
        let candidate = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("ARESNativeMCP")
        return fileManager.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private func reclaimPort(_ port: Int) {
        let lsofTask = Process()
        lsofTask.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsofTask.arguments = ["-t", "-i", "tcp:\(port)"]
        
        let pipe = Pipe()
        lsofTask.standardOutput = pipe
        
        do {
            try lsofTask.run()
            lsofTask.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty {
                let pids = output.components(separatedBy: .newlines).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                for pid in pids {
                    let psTask = Process()
                    psTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                    psTask.arguments = ["-o", "command=", "-p", String(pid)]
                    
                    let psPipe = Pipe()
                    psTask.standardOutput = psPipe
                    
                    try psTask.run()
                    psTask.waitUntilExit()
                    
                    let psData = psPipe.fileHandleForReading.readDataToEndOfFile()
                    if let command = String(data: psData, encoding: .utf8),
                       Self.isManagedWebUICommand(command) {
                        print("[ARES] Reclaiming port \(port) from orphaned process \(pid)")
                        let killTask = Process()
                        killTask.executableURL = URL(fileURLWithPath: "/bin/kill")
                        killTask.arguments = ["-9", String(pid)]
                        try killTask.run()
                        killTask.waitUntilExit()
                    }
                }
            }
        } catch {
            print("[ARES] Error reclaiming port \(port): \(error)")
        }
    }

    nonisolated static func isManagedWebUICommand(_ command: String) -> Bool {
        command.contains("server.py") ||
            (command.contains("uvicorn") && command.contains("fastapi_app.main:app"))
    }
}
