import Foundation
import SwiftUI

// MARK: - Discovered tool
//
// A single AI/dev tool found on the host. The shape is deliberately
// generic — we may not know exactly what the tool is, only that it
// looks like an AI tool and where it lives.

struct DiscoveredTool: Identifiable, Equatable {
    let id: String                    // stable id, derived from name
    let name: String                  // display name (e.g. "Claude Code")
    let category: ToolCategory        // coding agent, model server, etc.
    let icon: String                  // SF Symbol
    let kind: Kind
    let executablePath: String?       // for .cli / .binary
    let appBundlePath: String?        // for .app
    let webURL: String?               // for .webUI
    let dataPath: String?             // tilde path if known
    let lastUsed: Date?               // best-effort mtime

    enum Kind: Equatable {
        case cli                       // runnable command
        case app                       // .app bundle (launch via NSWorkspace)
        case webUI                     // opens in embedded WKWebView
    }

    enum ToolCategory: String, Equatable {
        case codingAgent              // claude, gemini, codex, aider, etc.
        case modelServer              // ollama, lm-studio
        case media                    // comfy, hyperframes, runway
        case research                 // odysseus, perplexity
        case utility                  // ares role profiles, etc.
        case github                   // local git repos
        case unknown

        var displayName: String {
            switch self {
            case .codingAgent: return "Coding Agents"
            case .modelServer: return "Model Servers"
            case .media:       return "Media"
            case .research:    return "Research"
            case .utility:     return "Utilities"
            case .github:      return "GitHub Repos"
            case .unknown:     return "Other"
            }
        }
    }
}

// MARK: - Tool Discovery
//
// Filesystem-driven auto-discovery. No hand-curated catalog of *specific*
// tools. Instead:
//   1. Walk well-known binary directories, collect every executable
//   2. Walk /Applications + ~/Applications, collect every .app
//   3. Walk ~/.<dir> hidden directories that look like tool data dirs
//   4. Cross-reference them with a small set of category *hints* (regex
//      patterns that decide what kind of tool something is)
//   5. For each candidate, resolve the real binary via `which` (PATH) so
//      npm/bun/nvm/asdf-installed tools are found
//
// The result: a deduplicated list of [DiscoveredTool] sorted by category
// then name. The Hub renders these as tabs — no enum, no hard-coding.

@MainActor
final class ToolDiscovery: ObservableObject {

    @Published var tools: [DiscoveredTool] = []
    @Published var lastScanDate: Date? = nil

    func scan() async {
        let discoveredTools = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return [DiscoveredTool]() }
            return self.performScan()
        }.value
        
        self.tools = discoveredTools
        self.lastScanDate = Date()
    }

    nonisolated private func performScan() -> [DiscoveredTool] {
        var all: [DiscoveredTool] = []
        all.append(contentsOf: scanBinaries())
        all.append(contentsOf: scanApplications())
        all.append(contentsOf: scanDataDirs())
        all = mergeDuplicates(all)
        all.sort { lhs, rhs in
            if lhs.category != rhs.category { return lhs.category.sortOrder < rhs.category.sortOrder }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return all
    }

    // MARK: - Binary scan
    //
    // Look for executables in standard locations. For each, run
    // `which <name>` so PATH resolution catches npm/bun/nvm/asdf installs.

    nonisolated private func scanBinaries() -> [DiscoveredTool] {
        let home = NSString(string: "~").expandingTildeInPath
        let dirs = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        var found: [DiscoveredTool] = []
        var seenBaseNames: Set<String> = []

        for dir in dirs {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for name in contents {
                let full = (dir as NSString).appendingPathComponent(name)
                guard FileManager.default.isExecutableFile(atPath: full) else { continue }
                guard let category = Self.categorize(name: name) else { continue }

                // Skip variants/subcommands of a tool we already have.
                let baseName = Self.baseBinaryName(name)
                if seenBaseNames.contains(baseName) { continue }
                seenBaseNames.insert(baseName)

                // Skip known false positives
                if Self.excludedBinaries.contains(name) { continue }

                let resolved = resolveOnPATH(name) ?? full
                let id = "bin-\(baseName)"

                // Some tools have a web UI — link it automatically.
                let webURL = Self.webURLFor(name: name)

                found.append(DiscoveredTool(
                    id: id,
                    name: Self.prettyName(name),
                    category: category,
                    icon: Self.iconFor(name: name, category: category),
                    kind: webURL != nil ? .webUI : .cli,
                    executablePath: resolved,
                    appBundlePath: nil,
                    webURL: webURL,
                    dataPath: Self.guessDataPath(for: name),
                    lastUsed: mtimeFor(resolved)
                ))
            }
        }
        return found
    }

    /// Extract the "base" of a binary name so we can dedup variants.
    /// `llama-server`, `llama-bench`, `llama-cli` → `llama`
    /// `comfy`, `comfy-cli`, `comfycli` → `comfy`  (the latter is
    ///   collapsed by `normalizeName` later — see mergeDuplicates)
    /// `claude`, `claude-code` → `claude`
    /// `ares-hermes`, `hermes` → `hermes`
    nonisolated private static func baseBinaryName(_ name: String) -> String {
        let lower = name.lowercased()
        // Hyphen/underscore split: take the first segment.
        if let firstHyphen = lower.firstIndex(of: "-") {
            return String(lower[..<firstHyphen])
        }
        if let firstUnderscore = lower.firstIndex(of: "_") {
            return String(lower[..<firstUnderscore])
        }
        return lower
    }

    /// Returns true if `b` is a prefix-extension of `a` (or vice versa).
    /// "comfy" and "comfycli" → true (comfy is prefix)
    /// "llama" and "llama-server" → already handled by baseBinaryName
    nonisolated private static func isVariantOf(_ a: String, _ b: String) -> Bool {
        let (shorter, longer) = a.count <= b.count ? (a, b) : (b, a)
        if shorter == longer { return true }
        return longer.hasPrefix(shorter) && longer.count <= shorter.count + 8
    }

    /// Normalize a name for cross-source dedup (bin, app, data dir).
    /// Strips spaces, hyphens, underscores, dots, suffixes.
    /// `HermesDesktopDodo` → `hermesdesktopdodo`
    /// `Claude Code URL Handler` → `claudecodeurlhandler`
    /// `comfy` → `comfy`, `comfycli` → `comfycli` (kept distinct from comfy)
    nonisolated private static func normalizeName(_ name: String) -> String {
        return name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    /// Binaries that pattern-matched but are NOT real AI tools. Add to
    /// this list as we discover false positives.
    nonisolated private static let excludedBinaries: Set<String> = [
        "sample",       // macOS audio utility, not "sam" research tool
        "sampleproc",   // ditto
    ]

    /// Apps that pattern-matched but aren't AI tools.
    nonisolated private static let excludedApps: Set<String> = [
        "Visual Studio Code",  // editor, not an AI tool
        "Xcode",               // ditto
    ]

    /// Map well-known tool binaries to their local web UI URL.
    /// Hermes Agent runs a control plane at :9119. Others could be added
    /// (e.g. ComfyUI :8188, Ollama :11434 web).
    nonisolated private static func webURLFor(name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("hermes") { return "http://localhost:9119" }
        if lower.contains("ollama") { return "http://localhost:11434" }
        if lower.contains("comfy")  { return "http://localhost:8188" }
        return nil
    }

    // MARK: - Application scan
    //
    // /Applications and ~/Applications — every .app we recognize.

    nonisolated private func scanApplications() -> [DiscoveredTool] {
        let dirs = ["/Applications", NSString(string: "~/Applications").expandingTildeInPath]
        var found: [DiscoveredTool] = []
        var seenIds: Set<String> = []

        for dir in dirs {
            let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
            for name in contents where name.hasSuffix(".app") {
                let bare = String(name.dropLast(".app".count))
                if Self.excludedApps.contains(bare) { continue }
                guard let category = Self.categorize(name: bare) else { continue }
                let full = (dir as NSString).appendingPathComponent(name)
                let id = "app-\(bare.lowercased())"
                guard !seenIds.contains(id) else { continue }
                seenIds.insert(id)

                found.append(DiscoveredTool(
                    id: id,
                    name: Self.prettyAppName(bare),
                    category: category,
                    icon: Self.iconFor(name: bare, category: category),
                    kind: .app,
                    executablePath: nil,
                    appBundlePath: full,
                    webURL: Self.webURLFor(name: bare),
                    dataPath: Self.guessDataPath(for: bare),
                    lastUsed: mtimeFor(full)
                ))
            }
        }
        return found
    }

    // MARK: - Data dir scan
    //
    // If we see ~/.claude, ~/.gemini etc. but the binary wasn't found in
    // the standard dirs (npm install, custom path), the data dir is
    // still a strong signal. Surface as a tool with kind .cli and a
    // best-guess command name (the data dir name = the command name).

    nonisolated private func scanDataDirs() -> [DiscoveredTool] {
        let home = NSString(string: "~").expandingTildeInPath
        let homeURL = URL(fileURLWithPath: home)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []

        var found: [DiscoveredTool] = []
        var seenIds: Set<String> = []

        for name in contents where name.hasPrefix(".") {
            let bare = String(name.dropFirst())
            // Skip obvious non-tool dirs
            if Self.systemHiddenDirs.contains(bare) { continue }
            if bare.hasPrefix("npm") || bare.hasPrefix("Trash") { continue }

            let full = (homeURL.appendingPathComponent(name).path)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: full, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            guard let category = Self.categorize(name: bare) else { continue }
            // Skip if we already found this via binary/app
            let id = "bin-\(bare)"
            if seenIds.contains(id) { continue }

            // Try to resolve the binary — if not on PATH, the tool will
            // surface but the embedded terminal will show "not installed".
            let resolved = resolveOnPATH(bare)
            let lastUsed = newestMtime(in: full)

            found.append(DiscoveredTool(
                id: id,
                name: Self.prettyName(bare),
                category: category,
                icon: Self.iconFor(name: bare, category: category),
                kind: .cli,
                executablePath: resolved,
                appBundlePath: nil,
                webURL: nil,
                dataPath: "~/\(name)",
                lastUsed: lastUsed
            ))
            seenIds.insert(id)
        }
        return found
    }

    // MARK: - Dedup
    //
    // Same tool may show up via multiple sources: binary + app + data dir.
    // Example: `claude` (binary) + `Claude.app` + `~/.claude` (data).
    // We want one card per logical tool. Keying: normalize the name
    // (strip spaces, hyphens, dots), then keep the most "informative"
    // variant (app > cli > data).

    nonisolated private func mergeDuplicates(_ tools: [DiscoveredTool]) -> [DiscoveredTool] {
        // Sort by priority (most "informative" first) so when we keep
        // one, it's the best representative.
        let priority: (DiscoveredTool) -> Int = { t in
            switch t.kind {
            case .app:   return 4
            case .cli:   return t.executablePath != nil ? 3 : 1
            case .webUI: return 4
            }
        }
        let sorted = tools.sorted { priority($0) > priority($1) }

        var kept: [DiscoveredTool] = []
        for tool in sorted {
            // Compute a "core token" for this tool. Hermes variants
            // (hermes, ares-hermes, hermes-desktop, HermesDesktopDodo)
            // all share the token "hermes" and should collapse.
            let coreTokens = Self.coreTokens(name: tool.name)
            let isDup = kept.contains { existing in
                if existing.category != tool.category { return false }
                let existingTokens = Self.coreTokens(name: existing.name)
                // If they share any core token in the same category, they're the same tool
                if !coreTokens.isEmpty && !existingTokens.isEmpty &&
                   !Set(coreTokens).isDisjoint(with: Set(existingTokens)) {
                    return true
                }
                // Fallback: original heuristics
                let existingNorm = Self.normalizeName(existing.name)
                let toolNorm = Self.normalizeName(tool.name)
                if existingNorm == toolNorm { return true }
                let existingBase = Self.baseBinaryName(existing.name)
                let toolBase = Self.baseBinaryName(tool.name)
                if existingBase == toolBase && !existingBase.isEmpty { return true }
                if Self.isVariantOf(existingBase, toolBase) { return true }
                return false
            }
            if !isDup {
                kept.append(tool)
            }
        }
        return kept
    }

    /// Extract "core tokens" from a tool name for dedup. A core token is
    /// a distinctive word that identifies the tool's identity.
    /// `hermes`, `ares-hermes`, `hermes-desktop`, `HermesDesktopDodo`
    ///   → all contain the token "hermes"
    /// `claude`, `claude-code`, `Claude.app`
    ///   → all contain the token "claude"
    /// `codex`, `Codex.app`
    ///   → all contain the token "codex"
    /// This handles the case where a tool has multiple binary/app
    /// spellings that share a common root word.
    nonisolated private static func coreTokens(name: String) -> [String] {
        let lower = name.lowercased()
        // Split on non-letter chars
        let parts = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let knownCores: Set<String> = [
            "hermes", "claude", "codex", "gemini", "opencode", "ollama",
            "llama", "comfy", "hyper", "sam", "odysseus", "dodo", "copilot",
            "cursor", "windsurf", "zed", "aider", "continue", "goose",
            "droid", "coder"
        ]
        return parts.filter { knownCores.contains($0) }
    }

    // MARK: - Heuristic categorization
    //
    // The ONLY hand-curated knowledge in the registry. Each entry is a
    // regex → category mapping. New tools don't need new entries; they
    // just need to match a pattern. If nothing matches, the tool is hidden.

    nonisolated private static let categoryPatterns: [(NSRegularExpression, DiscoveredTool.ToolCategory)] = {
        let patterns: [(String, DiscoveredTool.ToolCategory)] = [
            // Coding agents
            ("^(claude|gemini|codex|coder|cline|aider|cody|copilot|tabnine|continue|windsurf|zed|cursor|supermaven|q$|q-developer|opencode|goose)$", .codingAgent),
            ("claude", .codingAgent),
            ("gemini", .codingAgent),
            ("codex", .codingAgent),
            ("opencode", .codingAgent),
            ("hermes", .codingAgent),
            ("droid", .codingAgent),

            // Model servers
            ("ollama", .modelServer),
            ("lms|lm-studio|lmstudio", .modelServer),
            ("llama", .modelServer),
            // mlx is the Apple ML library, not a CLI tool — skip it
            // ("mlx", .modelServer),

            // Media
            ("comfy", .media),
            ("hyper", .media),
            ("suno|udio|runway|eleven", .media),
            ("ffmpeg", .media),
            ("aiavatarkit", .media),

            // Research
            ("odysseus", .research),
            ("perplexity|phind", .research),
            ("sam", .research),
            ("dodo", .research),
        ]
        return patterns.compactMap { pattern, cat in
            (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])).map { ($0, cat) }
        }
    }()

    nonisolated private static func categorize(name: String) -> DiscoveredTool.ToolCategory? {
        let lower = name.lowercased()
        for (regex, category) in categoryPatterns {
            let range = NSRange(lower.startIndex..<lower.endIndex, in: lower)
            if regex.firstMatch(in: lower, options: [], range: range) != nil {
                return category
            }
        }
        return nil
    }

    // MARK: - Display name cleanup
    //
    // "claude-code" -> "Claude Code", "codex" -> "Codex", "lm-studio" -> "LM Studio"

    nonisolated private static func prettyName(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == "-" || $0 == "_" })
        return parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    nonisolated private static func prettyAppName(_ name: String) -> String {
        // Apps sometimes have weird naming. Best effort.
        return name
    }

    // MARK: - Icon mapping
    //
    // Best-effort SF Symbol per tool name. Falls back to a category
    // generic symbol so unknown tools still get something reasonable.

    nonisolated private static func iconFor(name: String, category: DiscoveredTool.ToolCategory) -> String {
        let n = name.lowercased()
        if n.contains("claude") { return "sparkle" }
        if n.contains("gemini") { return "sparkles" }
        if n.contains("codex") { return "chevron.left.forwardslash.chevron.right" }
        if n.contains("opencode") { return "curlybraces" }
        if n.contains("ollama") { return "cpu.fill" }
        if n.contains("lms") || n.contains("lm-studio") { return "cpu" }
        if n.contains("hermes") { return "bolt.horizontal" }
        if n.contains("comfy") { return "wand.and.stars" }
        if n.contains("hyper") { return "play.rectangle.fill" }
        if n.contains("odysseus") { return "compass.drawing" }
        if n.contains("sam") { return "brain.head.profile" }
        if n.contains("dodo") { return "questionmark.bubble" }
        if n.contains("copilot") { return "airplane" }
        if n.contains("continue") { return "play.rectangle" }
        if n.contains("aider") { return "person.2.fill" }
        if n.contains("cline") { return "rectangle.3.group" }
        if n.contains("cursor") { return "arrow.up.left.and.arrow.down.right" }
        if n.contains("windsurf") { return "wind" }
        if n.contains("zed") { return "bolt" }
        if n.contains("goose") { return "bird.fill" }
        if n.contains("aiavatarkit") { return "person.crop.circle" }
        if n.contains("droid") { return "person.fill.viewfinder" }
        if n.contains("mistral") || n.contains("deepseek") || n.contains("qwen") { return "brain" }

        switch category {
        case .codingAgent: return "terminal.fill"
        case .modelServer: return "cpu"
        case .media:       return "play.rectangle"
        case .research:    return "magnifyingglass"
        case .utility:     return "wrench.and.screwdriver"
        case .github:      return "chevron.left.forwardslash.chevron.right"
        case .unknown:     return "questionmark.square"
        }
    }

    // MARK: - Data dir guess
    //
    // Most AI tools use ~/.<lowercased-name>/. Some exceptions (SAM uses
    // ~/sam). For .app names with spaces, we don't have a convention.

    nonisolated private static func guessDataPath(for name: String) -> String? {
        let bare = name.lowercased()
        if bare == "sam" { return "~/sam" }
        if bare.isEmpty { return nil }
        return "~/.\(bare)"
    }

    // MARK: - Binary resolution via `which`
    //
    // This is the key fix from before: we use the shell's PATH resolution
    // instead of probing 4 hard-coded paths. Catches npm/bun/nvm/asdf.

    nonisolated private func resolveOnPATH(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (out?.isEmpty == false) ? out : nil
    }

    // MARK: - System dirs to skip during data dir scan
    //
    // Most hidden dirs in ~ are noise (caches, app state). Only flag
    // ones that match a category pattern — that filter does most of the
    // work. This list is just a safety net.

    nonisolated private static let systemHiddenDirs: Set<String> = [
        "Trash", "Spotlight-V100", ".fseventsd", "Library", "Applications",
        "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
        "Public", "Creative Cloud Files", "Box", "iCloud Drive", "OneDrive",
        ".DS_Store", ".CFUserTextEncoding", "go", "cargo", "rustup",
        ".vim", ".viminfo", ".ssh", ".gnupg", ".aws", ".azure", ".gcloud",
        ".kube", ".docker", ".npm", ".bun", ".nvm", ".pyenv", ".rbenv",
        ".oh-my-zsh", ".zsh_sessions", ".zsh_history", ".zshrc",
        ".gitconfig", ".gitignore_global", ".git",
        ".cache", ".config", ".local", ".netrc", ".npmrc",
        ".vscode", ".cursor", ".trae", ".windsurf",  // editor state
    ]

    // MARK: - File helpers

    nonisolated private func mtimeFor(_ path: String) -> Date? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            return attrs[.modificationDate] as? Date
        } catch {
            return nil
        }
    }

    nonisolated private func newestMtime(in directoryPath: String) -> Date? {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: directoryPath) else {
            return nil
        }
        var newest: Date? = nil
        for item in contents {
            let full = (directoryPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                if let sub = try? fm.contentsOfDirectory(atPath: full) {
                    for s in sub {
                        let sp = (full as NSString).appendingPathComponent(s)
                        if let m = mtimeFor(sp), newest == nil || m > newest! {
                            newest = m
                        }
                    }
                }
            } else {
                if let m = mtimeFor(full), newest == nil || m > newest! {
                    newest = m
                }
            }
        }
        return newest
    }
}

extension DiscoveredTool.ToolCategory {
    var sortOrder: Int {
        switch self {
        case .codingAgent: return 0
        case .modelServer: return 1
        case .github:      return 2
        case .research:    return 3
        case .media:       return 4
        case .utility:     return 5
        case .unknown:     return 6
        }
    }
}
