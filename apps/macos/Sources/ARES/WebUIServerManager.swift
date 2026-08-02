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

        // The native app is the sole owner of this controller lifecycle. Never
        // adopt an unrelated or orphaned process merely because it answers an
        // ARES health check on the configured port.
        let inUse = await isPortInUse(port, host: host)
        if inUse {
            portConflict = true
            serverHealth = "Port \(port) is owned by another process"
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
        // Prefer the repository's canonical .venv. A stale legacy venv may
        // contain Python but not the WebUI dependencies (notably Uvicorn).
        let fm = FileManager.default
        guard let python = Self.pythonExecutable(in: dir, fileManager: fm) else {
            serverHealth = "Python environment not found — run install.sh"
            return
        }
        process.executableURL = python
        process.arguments = ["-m", "uvicorn", "fastapi_app.main:app", "--port", String(port), "--host", host]
        
        var env = ProcessInfo.processInfo.environment
        env = Self.applyingNativeRuntimeEnvironment(
            to: env,
            host: host,
            port: port,
            reloadDevMode: config.reloadDevMode,
            instanceID: NativeSystemBridge.shared.instanceID,
            stateDirectory: config.configDirectory
        )
        env = Self.applyingGatewayEnvironment(
            to: env,
            hermesURL: config.hermesURL,
            hermesAPIKey: config.hermesAPIKey,
            jrosURL: config.jrosURL,
            jrosAPIKey: config.jrosAPIKey
        )
        env = Self.applyingJaegerDependencyEnvironment(
            to: env,
            controllerDirectory: dir,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
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
            self.serverHealth = "Starting..."
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
        //
        // Only export them for a genuinely remote gateway. Setting ARES_API_URL
        // forces agent health into remote-HTTP probing and skips the local
        // PID/state-file detection — with the localhost default this reported
        // a healthy local Hermes gateway as permanently "down" because nothing
        // serves HTTP health on that port in a local install.
        let normalizedHermesURL = hermesURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedHermesURL.isEmpty || Self.isLocalGatewayURL(normalizedHermesURL) {
            environment.removeValue(forKey: "ARES_API_URL")
            environment.removeValue(forKey: "ARES_WEBUI_GATEWAY_BASE_URL")
        } else {
            environment["ARES_API_URL"] = normalizedHermesURL
            environment["ARES_WEBUI_GATEWAY_BASE_URL"] = normalizedHermesURL
        }
        let normalizedJROSURL = jrosURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never forward retired product variables into the controller. The
        // controller reads them only as compatibility input for older launchers.
        environment.removeValue(forKey: "ARES_JROS_GATEWAY_URL")
        environment.removeValue(forKey: "ARES_JROS_GATEWAY_KEY")
        if normalizedJROSURL.isEmpty {
            environment.removeValue(forKey: "ARES_JAEGER_GATEWAY_URL")
        } else {
            environment["ARES_JAEGER_GATEWAY_URL"] = normalizedJROSURL
        }
        if hermesAPIKey.isEmpty {
            environment.removeValue(forKey: "ARES_WEBUI_GATEWAY_API_KEY")
        } else {
            environment["ARES_WEBUI_GATEWAY_API_KEY"] = hermesAPIKey
        }
        if jrosAPIKey.isEmpty {
            environment.removeValue(forKey: "ARES_JAEGER_GATEWAY_KEY")
        } else {
            environment["ARES_JAEGER_GATEWAY_KEY"] = jrosAPIKey
        }
        return environment
    }

    nonisolated static func applyingNativeRuntimeEnvironment(
        to base: [String: String],
        host: String,
        port: Int,
        reloadDevMode: Bool,
        instanceID: String,
        stateDirectory: URL
    ) -> [String: String] {
        var environment = base
        environment["ARES_WEBUI_HOST"] = host
        environment["ARES_WEBUI_PORT"] = String(port)
        environment["ARES_WEBUI_RELOAD"] = reloadDevMode ? "1" : "0"
        environment["ARES_RUNTIME_OWNER"] = "mac_app"
        environment["ARES_RUNTIME_INSTANCE_ID"] = instanceID
        environment["ARES_NATIVE_STATE_DIR"] = stateDirectory.path
        return environment
    }

    nonisolated static func applyingJaegerDependencyEnvironment(
        to base: [String: String],
        controllerDirectory: URL,
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) -> [String: String] {
        var environment = base
        // Retired JROS variables are migration inputs inside the controller,
        // never values emitted by the current Mac launcher.
        for key in [
            "ARES_JROS_DIR", "ARES_JROS_CONFIG_PATH", "ARES_JROS_INSTANCE",
            "JROS_HOME", "JROS_INSTANCE_NAME",
        ] {
            environment.removeValue(forKey: key)
        }

        let aresRoot = controllerDirectory
            .deletingLastPathComponent() // services
            .deletingLastPathComponent() // ARES repository
        let siblingCheckout = aresRoot
            .deletingLastPathComponent()
            .appendingPathComponent("JaegerAI", isDirectory: true)
        let standardInstall = homeDirectory.appendingPathComponent("jaeger", isDirectory: true)

        let explicitSelection = ["ARES_JAEGER_HOME", "JAEGER_HOME", "ARES_JAEGER_SOURCE_DIR"]
            .compactMap { key -> (key: String, url: URL)? in
                guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty
                else { return nil }
                return (key, URL(fileURLWithPath: raw, isDirectory: true))
            }
            .first
        let selected: URL?
        let selectedIsSource: Bool
        if let explicitSelection {
            // Explicit dependency selection fails closed. A stale JROS path
            // must never be hidden by switching to another checkout.
            selected = isJaegerAIProductRoot(explicitSelection.url, fileManager: fileManager)
                ? explicitSelection.url
                : nil
            selectedIsSource = explicitSelection.key == "ARES_JAEGER_SOURCE_DIR"
        } else {
            // Repository builds prefer the adjacent development checkout.
            // Packaged installs fall through to the conventional top-level path.
            selected = [siblingCheckout, standardInstall].first(where: {
                isJaegerAIProductRoot($0, fileManager: fileManager)
            })
            selectedIsSource = selected?.standardizedFileURL == siblingCheckout.standardizedFileURL
        }

        guard let selected else {
            environment.removeValue(forKey: "ARES_JAEGER_HOME")
            environment.removeValue(forKey: "JAEGER_HOME")
            environment.removeValue(forKey: "ARES_JAEGER_SOURCE_DIR")
            environment.removeValue(forKey: "ARES_JAEGER_INSTANCE")
            return environment
        }

        environment["ARES_JAEGER_HOME"] = selected.path
        environment["JAEGER_HOME"] = selected.path
        if selectedIsSource {
            environment["ARES_JAEGER_SOURCE_DIR"] = selected.path
        } else {
            environment.removeValue(forKey: "ARES_JAEGER_SOURCE_DIR")
        }

        let activeFile = selected.appendingPathComponent(".jaeger_os/active_instance")
        if let active = try? String(contentsOf: activeFile, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !active.isEmpty,
           fileManager.fileExists(
               atPath: selected.appendingPathComponent(".jaeger_os/instances/\(active)").path
           ) {
            environment["ARES_JAEGER_INSTANCE"] = active
        } else {
            environment.removeValue(forKey: "ARES_JAEGER_INSTANCE")
        }
        return environment
    }

    nonisolated static func isJaegerAIProductRoot(
        _ root: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        var isDirectory: ObjCBool = false
        let package = root.appendingPathComponent("jaeger_ai", isDirectory: true)
        guard fileManager.fileExists(atPath: package.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return false }
        let launcher = root.appendingPathComponent("jaeger")
        return fileManager.isExecutableFile(atPath: launcher.path)
    }

    /// True when the configured Hermes gateway URL points at this machine —
    /// local installs detect the gateway via PID/state files, not HTTP.
    nonisolated static func isLocalGatewayURL(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              let host = url.host?.lowercased()
        else { return true }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "0.0.0.0"
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
        var exitedProcess: Process?
        if let p = process, !p.isRunning {
            exitedProcess = p
            process = nil
        }

        guard isRunning || exitedProcess != nil else {
            return
        }

        if let exitedProcess {
            recordHealthFailure(exitedProcess: exitedProcess, fallback: "Exited")
            return
        }

        let config = ARESConfiguration.shared
        let urlString = "http://\(config.webuiHost):\(config.webuiPort)/health"
        guard let url = URL(string: urlString) else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse,
               Self.isAresHealthResponse(statusCode: httpResp.statusCode, data: data) {
                isRunning = true
                serverHealth = "Running (Healthy)"
            } else {
                recordHealthFailure(exitedProcess: exitedProcess, fallback: "Running (Degraded)")
            }
        } catch {
            recordHealthFailure(exitedProcess: exitedProcess, fallback: "Running (Unreachable)")
        }
    }

    private func recordHealthFailure(exitedProcess: Process?, fallback: String) {
        if let exitedProcess {
            isRunning = false
            serverHealth = "Exited (code: \(exitedProcess.terminationStatus))"
        } else {
            serverHealth = fallback
        }
    }

    nonisolated static func isAresHealthResponse(statusCode: Int, data: Data) -> Bool {
        guard statusCode == 200,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        // New servers expose an explicit service identity. Keep compatibility
        // with existing ARES launch agents during an in-place app upgrade.
        if payload["service"] as? String == "ares-webui" {
            return true
        }
        if let acceptLoop = payload["accept_loop"] as? [String: Any],
           acceptLoop["server"] as? String == "uvicorn",
           payload["status"] as? String == "ok" {
            return true
        }
        return false
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
        if let explicitWebUI = environment["ARES_WEBUI_DIR"], !explicitWebUI.isEmpty {
            candidates.append(URL(fileURLWithPath: explicitWebUI))
        }
        if let resourceURL {
            candidates.append(resourceURL.appendingPathComponent("services/controller"))
            candidates.append(resourceURL.appendingPathComponent("webui")) // legacy path
        }
        var directory = executableURL?.deletingLastPathComponent()
        // A development bundle lives at apps/macos/ARES.app; reaching the
        // repository root from Contents/MacOS requires walking beyond the app
        // wrapper and both source-layout directories.
        for _ in 0..<8 {
            guard let current = directory else { break }
            candidates.append(current.appendingPathComponent("services/controller"))
            candidates.append(current.appendingPathComponent("webui")) // legacy path
            directory = current.deletingLastPathComponent()
        }
        candidates.append(URL(fileURLWithPath: currentDirectory).appendingPathComponent("services/controller"))
        candidates.append(URL(fileURLWithPath: currentDirectory).appendingPathComponent("webui")) // legacy path
        if let aresHome = environment["ARES_HOME"], !aresHome.isEmpty {
            candidates.append(URL(fileURLWithPath: aresHome).appendingPathComponent("services/controller"))
            candidates.append(URL(fileURLWithPath: aresHome).appendingPathComponent("webui")) // legacy path
        }
        candidates.append(homeDirectory.appendingPathComponent(".ares/services/controller"))
        candidates.append(homeDirectory.appendingPathComponent(".ares/webui")) // legacy path
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
        for relativePath in [".venv/bin/python", "venv/bin/python"] {
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

}
