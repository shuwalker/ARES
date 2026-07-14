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

        // Production installs are owned by launchd. If a menu action stopped
        // that service, load it again before falling back to an app-owned
        // Python process.
        if FileManager.default.fileExists(atPath: launchAgentPlist.path), !isLaunchAgentLoaded {
            _ = runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentPlist.path])
            _ = runLaunchctl(["kickstart", "gui/\(getuid())/com.ares.webui"])
            try? await Task.sleep(nanoseconds: 750_000_000)
        }

        let config = ARESConfiguration.shared
        let host = config.webuiHost
        let port = config.webuiPort

        serverHealth = "Checking port..."

        // Check if the port is already in use before touching anything
        let inUse = await isPortInUse(port, host: host)
        if inUse {
            // A healthy server is already there (launchd or prior session) — adopt it
            if await isServerHealthy(host: host, port: port) {
                portConflict = false
                isRunning = true
                serverHealth = "Running (Healthy)"
                print("[ARES] Adopted existing WebUI server on http://\(host):\(port)")
                return
            }
            // Our server.py is on the port but still starting — don't kill it
            if isPortHeldByOurServer(port) {
                portConflict = false
                isRunning = true
                serverHealth = "Starting..."
                print("[ARES] WebUI server starting on port \(port) — waiting for health")
                return
            }
            // Something else is holding the port — reclaim and start fresh
            reclaimPort(port)
            let stillInUse = await isPortInUse(port, host: host)
            if stillInUse {
                portConflict = true
                serverHealth = "Port \(port) conflict detected"
                return
            }
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
        let venvPython = dir.appendingPathComponent("venv/bin/python")
        let dotVenvPython = dir.appendingPathComponent(".venv/bin/python")
        let fm = FileManager.default
        process.executableURL = fm.fileExists(atPath: venvPython.path) ? venvPython : dotVenvPython
        process.arguments = ["server.py"]
        
        var env = ProcessInfo.processInfo.environment
        env["HERMES_WEBUI_HOST"] = host
        env["HERMES_WEBUI_PORT"] = String(port)
        env["ARES_WEBUI_RELOAD"] = config.reloadDevMode ? "1" : "0"
        env["HERMES_API_URL"] = config.hermesURL
        env["ARES_JROS_GATEWAY_URL"] = config.jrosURL
        env["ARES_ROLE"] = config.aresRole
        env["ARES_DEVICE_ID"] = config.aresDeviceID
        env["ARES_AI_ID"] = config.aresAIID
        env["ARES_PRIMARY_URL"] = config.aresPrimaryURL
        env["ARES_CONTINUITY_DIR"] = config.aresContinuityDir
        if !config.hermesAPIKey.isEmpty {
            env["HERMES_WEBUI_GATEWAY_API_KEY"] = config.hermesAPIKey
        }
        if !config.jrosAPIKey.isEmpty {
            env["ARES_JROS_GATEWAY_KEY"] = config.jrosAPIKey
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

    public func stop(persistently: Bool = false) {
        if persistently, isLaunchAgentLoaded {
            _ = runLaunchctl(["bootout", "gui/\(getuid())", launchAgentPlist.path])
        }
        if let p = process {
            p.terminate()
            process = nil
        }
        isRunning = false
        serverHealth = "Stopped"
    }

    public func restart() async {
        stop(persistently: true)
        try? await Task.sleep(nanoseconds: 1_000_000_000) // Wait 1 second
        await start()
    }

    private var launchAgentPlist: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.ares.webui.plist")
    }

    private var isLaunchAgentLoaded: Bool {
        runLaunchctl(["print", "gui/\(getuid())/com.ares.webui"]) == 0
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) -> Int32 {
        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        command.arguments = arguments
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        do {
            try command.run()
            command.waitUntilExit()
            return command.terminationStatus
        } catch {
            return -1
        }
    }

    private func checkHealth() async {
        // If we own the process and it exited, mark as exited
        if let p = process, !p.isRunning {
            isRunning = false
            process = nil
            serverHealth = "Exited (code: \(p.terminationStatus))"
            return
        }

        guard isRunning else {
            if serverHealth.hasPrefix("Running") || serverHealth == "Starting..." {
                serverHealth = "Stopped"
            }
            return
        }

        // Always confirm via HTTP — works whether process was spawned by us or launchd
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
            // Keep isRunning true so the timer retries — launchd will restart the server
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
        // 1. Packaged App resources check
        if let bundlePath = Bundle.main.resourceURL {
            let webuiPath = bundlePath.appendingPathComponent("webui")
            if FileManager.default.fileExists(atPath: webuiPath.appendingPathComponent("server.py").path) {
                return webuiPath
            }
        }
        // 2. Traversal up from executable to support swift run / Xcode dev.
        // Only accept a webui dir here if a venv also exists — otherwise the
        // dev-checkout webui/ (which has server.py but no venv) silently wins
        // over the production install at ~/.ares/webui where the venv lives.
        var dir = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<5 {
            if let currentDir = dir {
                let webuiPath = currentDir.appendingPathComponent("webui")
                let hasServer = FileManager.default.fileExists(atPath: webuiPath.appendingPathComponent("server.py").path)
                let hasVenv = FileManager.default.fileExists(atPath: webuiPath.appendingPathComponent("venv/bin/python").path)
                    || FileManager.default.fileExists(atPath: webuiPath.appendingPathComponent(".venv/bin/python").path)
                if hasServer && hasVenv {
                    return webuiPath
                }
                dir = currentDir.deletingLastPathComponent()
            }
        }
        // 3. Production install — installer default: ~/.ares/webui
        let home = FileManager.default.homeDirectoryForCurrentUser
        let prodPath = home.appendingPathComponent(".ares/webui")
        if FileManager.default.fileExists(atPath: prodPath.appendingPathComponent("server.py").path) {
            return prodPath
        }
        // 4. ARES_HOME override — respect explicit install location
        if let aresHome = ProcessInfo.processInfo.environment["ARES_HOME"],
           !aresHome.isEmpty {
            let overridePath = URL(fileURLWithPath: aresHome).appendingPathComponent("webui")
            if FileManager.default.fileExists(atPath: overridePath.appendingPathComponent("server.py").path) {
                return overridePath
            }
        }
        // 5. Dev checkout fallback — only used during development
        let devPath = home.appendingPathComponent("GitHub/ARES/webui")
        if FileManager.default.fileExists(atPath: devPath.appendingPathComponent("server.py").path) {
            return devPath
        }
        return nil
    }

    private func isServerHealthy(host: String, port: Int) async -> Bool {
        guard let url = URL(string: "http://\(host):\(port)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func isPortHeldByOurServer(_ port: Int) -> Bool {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-t", "-i", "tcp:\(port)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        try? lsof.run()
        lsof.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let pids = output.components(separatedBy: .newlines).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        for pid in pids {
            let ps = Process()
            ps.executableURL = URL(fileURLWithPath: "/bin/ps")
            ps.arguments = ["-o", "command=", "-p", String(pid)]
            let psPipe = Pipe()
            ps.standardOutput = psPipe
            try? ps.run()
            ps.waitUntilExit()
            let cmd = String(data: psPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            if cmd.contains("server.py") { return true }
        }
        return false
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
                       command.contains("server.py") {
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
}
