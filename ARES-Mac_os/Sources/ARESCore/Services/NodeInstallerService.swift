import Foundation

public enum InstallerError: Error {
    case processFailed(String)
    case invalidPath
}

@MainActor
public final class NodeInstallerService: @unchecked Sendable {
    public static let shared = NodeInstallerService()
    
    private let extensionsDir: URL
    
    private init() {
        // We install extensions into ~/.ares/extensions
        let home = FileManager.default.homeDirectoryForCurrentUser
        extensionsDir = home.appendingPathComponent(".ares/extensions")
        
        try? FileManager.default.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
    }
    
    /// Installs a Node repository silently in the background
    /// - Parameters:
    ///   - repoURL: The Git URL of the repository
    ///   - destination: The folder name inside ~/.ares/extensions (e.g. "open-sora")
    ///   - progressHandler: Closure reporting progress 0.0 to 1.0
    public func install(repoURL: String, destination: String, progressHandler: @escaping (Double) -> Void) async throws {
        let targetDir = extensionsDir.appendingPathComponent(destination)
        
        // 1. Clean up existing directory if it exists
        if FileManager.default.fileExists(atPath: targetDir.path) {
            try FileManager.default.removeItem(at: targetDir)
        }
        
        // 2. Git Clone (Progress 0.0 -> 0.4)
        progressHandler(0.1)
        try await runCommand(command: "git clone \(repoURL) \(targetDir.path)")
        progressHandler(0.4)
        
        // 3. Create Python Venv (Progress 0.4 -> 0.6)
        try await runCommand(command: "python3 -m venv venv", currentDirectory: targetDir)
        progressHandler(0.6)
        
        // 4. Install Requirements if it exists (Progress 0.6 -> 0.9)
        let reqFile = targetDir.appendingPathComponent("requirements.txt")
        if FileManager.default.fileExists(atPath: reqFile.path) {
            try await runCommand(command: "./venv/bin/pip install -r requirements.txt", currentDirectory: targetDir)
        } else {
            // Check if there is an install.sh
            let installScript = targetDir.appendingPathComponent("install.sh")
            if FileManager.default.fileExists(atPath: installScript.path) {
                try await runCommand(command: "chmod +x install.sh && ./install.sh", currentDirectory: targetDir)
            }
        }
        progressHandler(0.9)
        
        // 5. Finishing up
        progressHandler(1.0)
    }
    
    private func runCommand(command: String, currentDirectory: URL? = nil) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            if let dir = currentDirectory {
                process.currentDirectoryURL = dir
            }
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? "Unknown Error"
                    continuation.resume(throwing: InstallerError.processFailed("Command failed: \(command)\nOutput: \(output)"))
                }
            } catch {
                continuation.resume(throwing: InstallerError.processFailed(error.localizedDescription))
            }
        }
    }
}
