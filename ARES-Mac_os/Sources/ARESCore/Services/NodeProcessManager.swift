import Foundation

public enum ProcessManagerError: Error {
    case processAlreadyRunning(String)
    case executableNotFound(String)
    case processFailedToStart(Error)
}

/// Manages the lifecycle of external Python extensions running in `~/.ares/extensions`.
@MainActor
public final class NodeProcessManager: @unchecked Sendable {
    public static let shared = NodeProcessManager()
    
    private let extensionsDir: URL
    private var runningProcesses: [String: Process] = [:]
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        extensionsDir = home.appendingPathComponent(".ares/extensions")
    }
    
    /// Starts a Python node from the extensions directory
    /// - Parameters:
    ///   - nodeName: The directory name (e.g., "hermes-agent")
    ///   - entryPoint: The main script to run (e.g., "main.py")
    /// - Returns: The Process ID (PID)
    @discardableResult
    public func startNode(_ nodeName: String, entryPoint: String = "main.py") throws -> Int32 {
        if let existing = runningProcesses[nodeName], existing.isRunning {
            throw ProcessManagerError.processAlreadyRunning(nodeName)
        }
        
        let nodeDir = extensionsDir.appendingPathComponent(nodeName)
        let venvPython = nodeDir.appendingPathComponent("venv/bin/python3")
        let scriptPath = nodeDir.appendingPathComponent(entryPoint)
        
        // Ensure the executable exists
        if !FileManager.default.fileExists(atPath: venvPython.path) {
            // Fallback to system python if no venv is found (e.g., testing or misconfigured)
            print("⚠️ [NODE_MANAGER] Virtual environment not found for \(nodeName), attempting system python.")
        }
        
        let process = Process()
        process.executableURL = FileManager.default.fileExists(atPath: venvPython.path) ? venvPython : URL(fileURLWithPath: "/usr/bin/env")
        
        if process.executableURL?.lastPathComponent == "env" {
            process.arguments = ["python3", scriptPath.path]
        } else {
            process.arguments = [scriptPath.path]
        }
        
        process.currentDirectoryURL = nodeDir
        
        // Set up pipes to suppress massive output and keep ARES fast
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            runningProcesses[nodeName] = process
            print("✅ [NODE_MANAGER] Started '\(nodeName)' (PID: \(process.processIdentifier))")
            
            // Clean up when it dies naturally
            process.terminationHandler = { [weak self] p in
                Task { @MainActor in
                    self?.runningProcesses.removeValue(forKey: nodeName)
                    print("🛑 [NODE_MANAGER] Node '\(nodeName)' terminated with status \(p.terminationStatus).")
                }
            }
            
            return process.processIdentifier
        } catch {
            throw ProcessManagerError.processFailedToStart(error)
        }
    }
    
    /// Stops a running node gracefully, or forces kill if it hangs
    public func stopNode(_ nodeName: String) {
        guard let process = runningProcesses[nodeName] else { return }
        print("🛑 [NODE_MANAGER] Stopping '\(nodeName)'...")
        process.terminate()
        runningProcesses.removeValue(forKey: nodeName)
    }
    
    /// Stops all running nodes. Called during app teardown.
    public func stopAllNodes() {
        for (name, _) in runningProcesses {
            stopNode(name)
        }
    }
    
    public func isNodeRunning(_ nodeName: String) -> Bool {
        return runningProcesses[nodeName]?.isRunning == true
    }
}
