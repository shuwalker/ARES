import Foundation
import SwiftUI

// MARK: - Installed Tool Model

/// Represents a CLI tool or installed application detected by the Hub.
/// ARES auto-discovers these on the host machine so the Hub can offer
/// the user the actual surface area available, not a hard-coded list.
struct InstalledTool: Identifiable, Equatable {
    let id: String          // unique identifier, e.g. "claude-code"
    let name: String        // display name, e.g. "Claude Code"
    let icon: String        // SF Symbol name
    let kind: ToolKind      // .cli or .webUI
    let isInstalled: Bool
    let lastUsedDate: Date? // newest mtime in the data dir, cheaply obtained
    let hint: String?       // e.g. "CLI tool — open in Terminal"
    /// For .cli kind: the executable name to spawn (resolved via /usr/bin/env PATH).
    /// For .webUI kind: optional URL to open in the embedded WKWebView.
    let command: String?    // for .cli
    let url: String?        // for .webUI
    let dataPath: String?   // tilde path for the tool's data dir (Claude/Gemini etc.)

    enum ToolKind: String, Equatable {
        case cli
        case webUI
    }
}

// MARK: - Integration Registry

/// Auto-discovers installed AI tools on this machine by checking for
/// well-known executables on PATH (with fallbacks to common install
/// locations) and well-known data directories. Detection is file-based
/// only — no process checks, no port probes, no CLI invocations.
@MainActor
final class IntegrationRegistry: ObservableObject {

    @Published var installedTools: [InstalledTool] = []
    @Published var lastScanDate: Date? = nil

    /// Catalog of well-known tools. The order here is the order they
    /// appear as Hub tabs. Add new tools to this list and they'll
    /// automatically show up if the host has them installed.
    private static let catalog: [ToolSpec] = [
        // Hermes — always the first tab if installed (the orchestration
        // backbone of ARES). Detected by ~/.hermes/ AND the `hermes` binary.
        ToolSpec(
            id: "hermes",
            name: "Hermes Agent",
            icon: "bolt.horizontal",
            kind: .webUI,
            command: "hermes",
            url: "http://localhost:9119",
            dataPath: "~/.hermes",
            hint: "ARES orchestration backbone",
            dataDirProbe: "~/.hermes",
            binaryProbes: ["~/.local/bin/hermes", "/usr/local/bin/hermes", "/opt/homebrew/bin/hermes"]
        ),
        // Claude Code — CLI tool, embeds the Claude Code TUI
        ToolSpec(
            id: "claude-code",
            name: "Claude Code",
            icon: "terminal.fill",
            kind: .cli,
            command: "claude",
            url: nil,
            dataPath: "~/.claude",
            hint: "Anthropic's CLI coding agent",
            dataDirProbe: "~/.claude",
            binaryProbes: ["~/.local/bin/claude", "/usr/local/bin/claude", "/opt/homebrew/bin/claude", "/usr/bin/claude"]
        ),
        // Gemini CLI — Google's CLI
        ToolSpec(
            id: "gemini-cli",
            name: "Gemini CLI",
            icon: "sparkles",
            kind: .cli,
            command: "gemini",
            url: nil,
            dataPath: "~/.gemini",
            hint: "Google's Gemini CLI",
            dataDirProbe: "~/.gemini",
            binaryProbes: ["~/.local/bin/gemini", "/usr/local/bin/gemini", "/opt/homebrew/bin/gemini", "/usr/bin/gemini"]
        ),
        // OpenAI Codex — OpenAI's CLI coding agent
        ToolSpec(
            id: "codex",
            name: "Codex",
            icon: "chevron.left.forwardslash.chevron.right",
            kind: .cli,
            command: "codex",
            url: nil,
            dataPath: "~/.codex",
            hint: "OpenAI's CLI coding agent",
            dataDirProbe: "~/.codex",
            binaryProbes: ["~/.local/bin/codex", "/usr/local/bin/codex", "/opt/homebrew/bin/codex", "/usr/bin/codex"]
        ),
        // Aider — popular AI pair-programming CLI
        ToolSpec(
            id: "aider",
            name: "Aider",
            icon: "person.2.fill",
            kind: .cli,
            command: "aider",
            url: nil,
            dataPath: "~/.aider",
            hint: "AI pair programming in your terminal",
            dataDirProbe: "~/.aider",
            binaryProbes: ["~/.local/bin/aider", "/usr/local/bin/aider", "/opt/homebrew/bin/aider", "/usr/bin/aider"]
        ),
        // OpenCode — go-based AI coding CLI
        ToolSpec(
            id: "opencode",
            name: "OpenCode",
            icon: "curlybraces",
            kind: .cli,
            command: "opencode",
            url: nil,
            dataPath: "~/.opencode",
            hint: "Go-based AI coding CLI",
            dataDirProbe: nil,
            binaryProbes: ["~/.local/bin/opencode", "/usr/local/bin/opencode", "/opt/homebrew/bin/opencode"]
        ),
        // Cline — VS Code extension CLI
        ToolSpec(
            id: "cline",
            name: "Cline",
            icon: "rectangle.3.group",
            kind: .cli,
            command: "cline",
            url: nil,
            dataPath: nil,
            hint: "AI coding agent for the terminal",
            dataDirProbe: nil,
            binaryProbes: ["~/.local/bin/cline", "/usr/local/bin/cline", "/opt/homebrew/bin/cline"]
        ),
        // Continue — dev tool CLI
        ToolSpec(
            id: "continue",
            name: "Continue",
            icon: "play.rectangle",
            kind: .cli,
            command: "continue",
            url: nil,
            dataPath: "~/.continue",
            hint: "Open-source AI code assistant",
            dataDirProbe: "~/.continue",
            binaryProbes: ["~/.local/bin/continue", "/usr/local/bin/continue", "/opt/homebrew/bin/continue"]
        ),
        // Goose — Block's AI coding agent
        ToolSpec(
            id: "goose",
            name: "Goose",
            icon: "bird.fill",
            kind: .cli,
            command: "goose",
            url: nil,
            dataPath: "~/.goose",
            hint: "Block's on-device AI agent",
            dataDirProbe: "~/.goose",
            binaryProbes: ["~/.local/bin/goose", "/usr/local/bin/goose", "/opt/homebrew/bin/goose"]
        ),
    ]

    func scan() {
        var tools: [InstalledTool] = []

        for spec in Self.catalog {
            // A tool is considered installed if EITHER its data dir probe
            // OR one of its binary probes exists.
            let dataDirExists = spec.dataDirProbe.map(dirExists) ?? false
            let binaryFound = spec.binaryProbes.first(where: isExecutable)
            let installed = dataDirExists || binaryFound != nil

            // For lastUsedDate, prefer the data dir mtime, fall back to binary mtime
            var lastUsed: Date? = nil
            if let probe = spec.dataDirProbe {
                lastUsed = newestMtime(in: NSString(string: probe).expandingTildeInPath)
            }
            if lastUsed == nil, let bin = binaryFound {
                lastUsed = mtimeFor(bin)
            }

            tools.append(InstalledTool(
                id: spec.id,
                name: spec.name,
                icon: spec.icon,
                kind: spec.kind,
                isInstalled: installed,
                lastUsedDate: lastUsed,
                hint: spec.hint,
                command: spec.command,
                url: spec.url,
                dataPath: spec.dataPath
            ))
        }

        installedTools = tools
        lastScanDate = Date()
    }

    /// Returns only tools that are installed on this host.
    var detected: [InstalledTool] {
        installedTools.filter { $0.isInstalled }
    }

    // MARK: - Tool spec (internal catalog entry)

    private struct ToolSpec {
        let id: String
        let name: String
        let icon: String
        let kind: InstalledTool.ToolKind
        let command: String?
        let url: String?
        let dataPath: String?
        let hint: String?
        /// Tilde path of a well-known data dir; if it exists, the tool is installed.
        let dataDirProbe: String?
        /// Tilde paths of well-known binary install locations; if any exists, tool is installed.
        let binaryProbes: [String]
    }

    // MARK: - Helpers

    private func dirExists(_ path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
    }

    private func isExecutable(_ path: String) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath
        return FileManager.default.isExecutableFile(atPath: expanded)
    }

    /// Walks `directoryPath` and returns the most recent modification date
    /// of any file found (shallow — only top two levels to keep it cheap).
    private func newestMtime(in directoryPath: String) -> Date? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directoryPath) else {
            return nil
        }
        var newest: Date? = nil
        for item in contents {
            let fullPath = (directoryPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                // Recurse one level into subdirectories (e.g. session folders)
                if let subContents = try? fm.contentsOfDirectory(atPath: fullPath) {
                    for sub in subContents {
                        let subPath = (fullPath as NSString).appendingPathComponent(sub)
                        if let mtime = mtimeFor(subPath),
                           newest == nil || mtime > newest! {
                            newest = mtime
                        }
                    }
                }
            } else {
                if let mtime = mtimeFor(fullPath),
                   newest == nil || mtime > newest! {
                    newest = mtime
                }
            }
        }
        return newest
    }

    private func mtimeFor(_ path: String) -> Date? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            return attrs[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
}
