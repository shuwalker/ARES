import Foundation

/// Three-phase remote bootstrap: check → install → verify.
/// Runs over SSH via SSHTransport, same transport the rest of ARES uses.
@MainActor
final class RemoteBootstrapService: ObservableObject {
    
    enum BootstrapPhase {
        case idle
        case checking
        case installing
        case verifying
        case done
        case failed(String)
    }
    
    struct RemoteCheckResult {
        let hermesInstalled: Bool
        let hermesVersion: String?
        let hermesHomeExists: Bool
        let configExists: Bool
        let ollamaInstalled: Bool
        let gatewayRunning: Bool
        let diskSpaceGB: Int?
        let hostname: String
    }
    
    struct InstallResult {
        let success: Bool
        let output: String
        let duration: TimeInterval
    }
    
    @Published var phase: BootstrapPhase = .idle
    @Published var checkResult: RemoteCheckResult?
    @Published var installResult: InstallResult?
    @Published var log: [String] = []
    @Published var progressMessage: String = ""
    
    private let sshTransport: SSHTransport
    private let connection: ConnectionProfile
    
    init(sshTransport: SSHTransport, connection: ConnectionProfile) {
        self.sshTransport = sshTransport
        self.connection = connection
    }
    
    // MARK: - Phase 1: Check
    
    /// SSH in and check what's already installed on the remote Mac.
    func checkRemote() async throws -> RemoteCheckResult {
        phase = .checking
        log = []
        appendLog("Checking remote Mac at \(connection.effectiveTarget)...")
        
        let script = """
        echo "HOSTNAME=$(hostname)"
        echo "DISK_GB=$(df -g / | tail -1 | awk '{print $4}')"
        if command -v hermes &>/dev/null; then
            echo "HERMES=yes"
            hermes --version 2>/dev/null | head -1 | sed 's/^/HERMES_VERSION=/'
        else
            echo "HERMES=no"
        fi
        if [ -d "$HOME/.hermes" ]; then echo "HERMES_HOME=yes"; else echo "HERMES_HOME=no"; fi
        if [ -f "$HOME/.hermes/config.yaml" ]; then echo "CONFIG=yes"; else echo "CONFIG=no"; fi
        if command -v ollama &>/dev/null; then echo "OLLAMA=yes"; else echo "OLLAMA=no"; fi
        if lsof -i :9119 &>/dev/null; then echo "GATEWAY=yes"; else echo "GATEWAY=no"; fi
        """
        
        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: connection.remoteServiceCommand("sh -s"),
            standardInput: Data(script.utf8),
            allocateTTY: false
        )
        
        guard result.exitCode == 0 else {
            phase = .failed("SSH check failed: \(result.stderr)")
            throw SSHTransportError.remoteFailure("Exit code \(result.exitCode): \(result.stderr)")
        }
        
        let output = result.stdout
        let check = parseCheckOutput(output)
        checkResult = check
        phase = .idle
        appendLog("Check complete. Hermes: \(check.hermesInstalled ? "✓" : "✗") Ollama: \(check.ollamaInstalled ? "✓" : "✗")")
        return check
    }
    
    // MARK: - Phase 2: Install
    
    /// Install Hermes on the remote Mac via the official curl installer.
    /// Returns install result with success/failure and output.
    func installHermes(skipSetup: Bool = true, skipBrowser: Bool = true) async throws -> InstallResult {
        phase = .installing
        progressMessage = "Installing Hermes Agent on remote Mac..."
        appendLog("Starting remote Hermes installation...")
        
        var args = "--skip-browser"
        if skipSetup { args += " --skip-setup" }
        
        let installScript = """
        set -e
        echo "INSTALL_START"
        curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash -s -- \(args)
        EXIT_CODE=$?
        echo "INSTALL_EXIT_$EXIT_CODE"
        """
        
        let startTime = Date()
        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: connection.remoteServiceCommand("sh -s"),
            standardInput: Data(installScript.utf8),
            allocateTTY: false
        )
        let duration = Date().timeIntervalSince(startTime)
        
        let success = result.exitCode == 0 && result.stdout.contains("INSTALL_EXIT_0")
        let installResult = InstallResult(
            success: success,
            output: result.stdout + "\n" + result.stderr,
            duration: duration
        )
        self.installResult = installResult
        
        if success {
            appendLog("Hermes installed successfully in \(Int(duration))s")
            phase = .idle
        } else {
            appendLog("Installation failed: \(result.stderr)")
            phase = .failed("Install failed")
        }
        
        return installResult
    }
    
    /// Install Ollama on the remote Mac via Homebrew.
    func installOllama() async throws -> Bool {
        progressMessage = "Installing Ollama on remote Mac..."
        appendLog("Installing Ollama...")
        
        let result = try await sshTransport.execute(
            on: connection,
            remoteCommand: "brew install ollama 2>&1 || echo BREW_INSTALL_FAILED",
            allocateTTY: false
        )
        
        let success = result.exitCode == 0 && !result.stdout.contains("BREW_INSTALL_FAILED")
        appendLog(success ? "Ollama installed" : "Ollama install failed: \(result.stdout)")
        return success
    }
    
    // MARK: - Phase 3: Verify
    
    /// After installation, verify Hermes is working by running the discovery protocol.
    func verify() async throws -> Bool {
        phase = .verifying
        progressMessage = "Verifying remote Hermes..."
        appendLog("Running discovery protocol...")
        
        let discoverService = RemoteHermesService(sshTransport: sshTransport)
        do {
            let discovery = try await discoverService.discover(connection: connection)
            appendLog("Discovery complete. Sessions: \(discovery.sessionStore != nil ? "✓" : "✗")")
            phase = .done
            return true
        } catch {
            appendLog("Discovery failed: \(error.localizedDescription)")
            phase = .failed("Verification failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Full bootstrap flow: check → install (if needed) → verify.
    func runFullBootstrap() async throws -> ConnectionProfile {
        // Phase 1: Check
        progressMessage = "Checking remote Mac..."
        let check = try await checkRemote()
        
        // Phase 2: Install (conditional)
        if !check.hermesInstalled {
            let install = try await installHermes()
            guard install.success else {
                throw SSHTransportError.remoteFailure("Hermes installation failed")
            }
        }
        
        // Phase 3: Verify
        let verified = try await verify()
        guard verified else {
            throw SSHTransportError.remoteFailure("Hermes verification failed")
        }
        
        return connection
    }
    
    // MARK: - Parsing
    
    private func parseCheckOutput(_ output: String) -> RemoteCheckResult {
        let lines = output.components(separatedBy: "\n")
        var hermesInstalled = false
        var hermesVersion: String?
        var hermesHomeExists = false
        var configExists = false
        var ollamaInstalled = false
        var gatewayRunning = false
        var diskSpaceGB: Int?
        var hostname = "unknown"
        
        for line in lines {
            if line.hasPrefix("HOSTNAME=") {
                hostname = String(line.dropFirst("HOSTNAME=".count))
            } else if line == "HERMES=yes" {
                hermesInstalled = true
            } else if line.hasPrefix("HERMES_VERSION=") {
                hermesVersion = String(line.dropFirst("HERMES_VERSION=".count))
            } else if line == "HERMES_HOME=yes" {
                hermesHomeExists = true
            } else if line == "CONFIG=yes" {
                configExists = true
            } else if line == "OLLAMA=yes" {
                ollamaInstalled = true
            } else if line == "GATEWAY=yes" {
                gatewayRunning = true
            } else if line.hasPrefix("DISK_GB=") {
                diskSpaceGB = Int(line.dropFirst("DISK_GB=".count))
            }
        }
        
        return RemoteCheckResult(
            hermesInstalled: hermesInstalled,
            hermesVersion: hermesVersion,
            hermesHomeExists: hermesHomeExists,
            configExists: configExists,
            ollamaInstalled: ollamaInstalled,
            gatewayRunning: gatewayRunning,
            diskSpaceGB: diskSpaceGB,
            hostname: hostname
        )
    }
    
    private func appendLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        log.append("[\(timestamp)] \(message)")
    }
}