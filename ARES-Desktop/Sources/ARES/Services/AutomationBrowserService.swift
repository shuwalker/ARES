import Foundation
import ARESCore
import os

private let automationBrowserLog = Logger(subsystem: "com.ares", category: "AutomationBrowser")

// MARK: - Automation Browser Service

/// Discovers, inspects, and manages Automation scripts on the local filesystem.
/// Scans ~/.hermes/scripts/ (and any configured supplemental paths), detects
/// running processes via pgrep, reads companion files (logs, state JSON), and
/// provides start/stop actions.
final class AutomationBrowserService: @unchecked Sendable {

    // MARK: - Scan Paths

    static let defaultScanPaths: [String] = {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            ?? NSHomeDirectory() + "/.hermes"
        return [hermesHome + "/scripts"]
    }()

    // MARK: - Discover

    /// Scans configured directories for runnable scripts and returns Automation entries.
    func discoverAutomations(in paths: [String] = defaultScanPaths) async -> [Automation] {
        var automations: [Automation] = []

        for basePath in paths {
            let url = URL(fileURLWithPath: basePath)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else { continue }

            for fileURL in contents {
                let filename = fileURL.lastPathComponent
                let ext = fileURL.pathExtension.lowercased()

                // Classify language
                let language: AutomationLanguage
                switch ext {
                case "py":  language = .python
                case "sh", "bash": language = .shell
                default: continue  // skip non-script files
                }

                // File metadata
                let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let lastModified = attrs?[.modificationDate] as? Date
                let fileSize = attrs?[.size] as? Int64

                // Read name from frontmatter or derive from filename
                let (name, description) = Self.parseMetadata(from: fileURL.path)

                // Find companion files
                let companions = Self.discoverCompanionFiles(for: fileURL)

                // Build automation
                var automation = Automation(
                    filename: filename,
                    filePath: fileURL.path,
                    language: language,
                    name: name,
                    description: description,
                    lastModified: lastModified,
                    fileSize: fileSize,
                    companionFiles: companions,
                    status: .unknown
                )

                // Check if running
                let (isRunning, pid) = Self.checkRunning(filename: filename, path: fileURL.path)
                automation.status = isRunning ? .running : .idle
                automation.runningPID = pid

                automations.append(automation)
            }
        }

        // Sort: running first, then by name
        automations.sort { a, b in
            if a.status == .running && b.status != .running { return true }
            if a.status != .running && b.status == .running { return false }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        return automations
    }

    // MARK: - Read Log

    /// Reads the last N lines of a log companion file.
    func readLog(for companion: AutomationCompanionFile, tailLines: Int = 100) -> String? {
        guard companion.kind == .log || companion.kind == .other else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: companion.filePath)),
              let content = String(data: data, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")
        let start = max(0, lines.count - tailLines)
        return lines[start...].joined(separator: "\n")
    }

    // MARK: - Read State

    /// Reads a state companion file and returns it as a pretty-printed string.
    func readState(for companion: AutomationCompanionFile) -> String? {
        guard companion.kind == .state else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: companion.filePath)) else { return nil }

        // Try JSON pretty print
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(
               withJSONObject: json,
               options: [.prettyPrinted, .sortedKeys]
           ),
           let str = String(data: pretty, encoding: .utf8) {
            return str
        }

        // Fallback: raw text
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Start Script

    /// Starts a script as a background process. Returns the PID on success.
    @discardableResult
    func start(_ automation: Automation) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: automation.filePath)

        switch automation.language {
        case .python:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [automation.filePath]
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["bash", automation.filePath]
        }

        // Redirect stdout/stderr to the log file if one exists
        if let logCompanion = automation.companionFiles.first(where: { $0.kind == .log }) {
            let logURL = URL(fileURLWithPath: logCompanion.filePath)
            if let handle = try? FileHandle(forWritingTo: logURL) {
                handle.seekToEndOfFile()
                process.standardOutput = handle
                process.standardError = handle
            }
        }

        try process.run()
        return process.processIdentifier
    }

    // MARK: - Stop Script

    /// Stops a running automation by sending SIGTERM to the detected PID.
    func stop(_ automation: Automation) throws {
        guard let pid = automation.runningPID, pid > 0 else {
            throw AutomationError.notRunning(automation.name)
        }
        let result = kill(pid, SIGTERM)
        if result != 0 {
            throw AutomationError.stopFailed(automation.name, errno: errno)
        }
    }

    // MARK: - Read Source

    /// Reads the source code of the automation script.
    func readSource(_ automation: Automation) -> String? {
        try? String(contentsOfFile: automation.filePath, encoding: .utf8)
    }

    // MARK: - Private Helpers

    /// Parse script metadata from a frontmatter block or return derived defaults.
    private static func parseMetadata(from path: String) -> (name: String, description: String?) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return (humanize(filename: filename), nil)
        }

        // Check for YAML-like frontmatter: ---\nkey: value\n---
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            return (humanize(filename: filename), nil)
        }

        var name: String?
        var description: String?
        var inFrontmatter = true

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" { break }
            if !inFrontmatter { break }

            let parts = trimmed.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }

            switch parts[0] {
            case "name":         name = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            case "description":  description = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            default: break
            }
        }

        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        return (name ?? humanize(filename: filename), description)
    }

    /// Convert kebab/snake case filenames to human-readable names.
    private static func humanize(filename: String) -> String {
        filename
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split { $0.isWhitespace }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Find companion files (logs, state, config) alongside a script.
    private static func discoverCompanionFiles(for scriptURL: URL) -> [AutomationCompanionFile] {
        let dir = scriptURL.deletingLastPathComponent()
        let baseName = scriptURL.deletingPathExtension().lastPathComponent

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        let scriptFilename = scriptURL.lastPathComponent
        let scriptExtensions: Set<String> = ["py", "sh", "bash"]

        return contents.compactMap { fileURL in
            let filename = fileURL.lastPathComponent
            guard filename != scriptFilename else { return nil }
            guard !scriptExtensions.contains(fileURL.pathExtension.lowercased()) else { return nil }

            // Match: same basename + suffix (e.g. imsg-calendar-sync.log)
            // or exact known companion extensions
            let fnBase = fileURL.deletingPathExtension().lastPathComponent

            // Exact basename match or basename starts with script basename
            guard fnBase == baseName || fnBase.hasPrefix(baseName + ".") || filename.hasPrefix(baseName + "-") else {
                return nil
            }

            let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
            let lastModified = attrs?[.modificationDate] as? Date
            let fileSize = attrs?[.size] as? Int64

            return AutomationCompanionFile(
                filename: filename,
                filePath: fileURL.path,
                kind: AutomationCompanionKind.classify(filename: filename),
                fileSize: fileSize,
                lastModified: lastModified
            )
        }
        .sorted { a, b in
            // Logs first, then state, then config, then other
            let order: [AutomationCompanionKind] = [.log, .state, .config, .other]
            let aIdx = order.firstIndex(of: a.kind) ?? 3
            let bIdx = order.firstIndex(of: b.kind) ?? 3
            if aIdx != bIdx { return aIdx < bIdx }
            return a.filename.localizedCaseInsensitiveCompare(b.filename) == .orderedAscending
        }
    }

    /// Check if a script process is currently running via pgrep.
    private static func checkRunning(filename: String, path: String) -> (isRunning: Bool, pid: Int32?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let firstPID = output.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces)
                if let pidStr = firstPID, let pid = Int32(pidStr) {
                    return (true, pid)
                }
                return (true, nil)
            }
        } catch {
            // pgrep failed — assume not running
            automationBrowserLog.debug("pgrep failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public); assuming not running")
        }
        return (false, nil)
    }
}

// MARK: - Errors

enum AutomationError: LocalizedError {
    case notRunning(String)
    case stopFailed(String, errno: Int32)
    case startFailed(String, reason: String)

    var errorDescription: String? {
        switch self {
        case .notRunning(let name):
            return "\(name) is not running."
        case .stopFailed(let name, let errno):
            return "Failed to stop \(name) (errno \(errno))."
        case .startFailed(let name, let reason):
            return "Failed to start \(name): \(reason)"
        }
    }
}