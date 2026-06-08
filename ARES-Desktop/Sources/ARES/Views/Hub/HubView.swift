import SwiftUI
import WebKit
import ARESCore

struct HubView: View {
    @EnvironmentObject private var appState: ARESAppState
    @StateObject private var discovery = ToolDiscovery()
    @StateObject private var gitHub = GitHubDiscovery()
    @State private var selectedCategory: DiscoveredTool.ToolCategory? = nil

    /// Tools grouped by category, for the category strip. Within each
    /// category, tools are sorted by name.
    private var toolsByCategory: [(DiscoveredTool.ToolCategory, [DiscoveredTool])] {
        let groups = Dictionary(grouping: discovery.tools, by: \.category)
        return DiscoveredTool.ToolCategory.allOrdered.compactMap { cat in
            guard let tools = groups[cat], !tools.isEmpty else { return nil }
            return (cat, tools.sorted { $0.name < $1.name })
        }
    }

    private var displayedTools: [DiscoveredTool] {
        if let cat = selectedCategory {
            return toolsByCategory.first(where: { $0.0 == cat })?.1 ?? []
        }
        return discovery.tools
    }

    var body: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 900
            VStack(spacing: 0) {
                header
                Divider().background(ARESColors.divider)
                if discovery.tools.isEmpty && gitHub.repos.isEmpty {
                    emptyState
                } else {
                    categoryStrip(isNarrow: isNarrow)
                    Divider().background(ARESColors.divider)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            toolsSection(isNarrow: isNarrow)
                            if selectedCategory == nil || selectedCategory == .github {
                                githubSection(isNarrow: isNarrow)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 1400)
                        .frame(maxWidth: .infinity)
                    }
                    .background(ARESColors.background)
                }
            }
            .background(ARESColors.background)
            .task {
                await discovery.scan()
                await gitHub.scan()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title3)
                .foregroundStyle(ARESColors.gold)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hub")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(ARESColors.textPrimary)
                if let date = discovery.lastScanDate {
                    Text("\(discovery.tools.count) tool(s) detected · scanned \(relativeDate(date))")
                        .font(.caption)
                        .foregroundStyle(ARESColors.textSecondary)
                } else {
                    Text("Scanning…")
                        .font(.caption)
                        .foregroundStyle(ARESColors.textSecondary)
                }
            }

            Spacer()

            Button {
                Task {
                    await discovery.scan()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                    Text("RESCAN")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ARESColors.surface)
                .foregroundStyle(ARESColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ARESColors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(ARESColors.surface)
    }

    // MARK: - Category strip (filter chips)

    private func categoryStrip(isNarrow: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // "All" chip
                chipButton(
                    title: "All",
                    icon: "square.grid.2x2",
                    isActive: selectedCategory == nil
                ) {
                    selectedCategory = nil
                }
                ForEach(toolsByCategory, id: \.0) { cat, tools in
                    chipButton(
                        title: "\(cat.displayName) (\(tools.count))",
                        icon: nil,
                        isActive: selectedCategory == cat
                    ) {
                        selectedCategory = (selectedCategory == cat) ? nil : cat
                    }
                }
                // GitHub chip (separate from tools)
                if !gitHub.repos.isEmpty {
                    chipButton(
                        title: "GitHub Repos (\(gitHub.repos.count))",
                        icon: "chevron.left.forwardslash.chevron.right",
                        isActive: selectedCategory == .github
                    ) {
                        selectedCategory = (selectedCategory == .github) ? nil : .github
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(ARESColors.surface)
    }

    private func chipButton(title: String, icon: String?, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon).font(.caption2) }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? ARESColors.gold.opacity(0.18) : ARESColors.surfaceElevated)
            .foregroundStyle(isActive ? ARESColors.gold : ARESColors.textSecondary)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isActive ? ARESColors.gold.opacity(0.5) : ARESColors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tools section (clickable cards)

    @ViewBuilder
    private func toolsSection(isNarrow: Bool) -> some View {
        // Show only if not filtered to GitHub-only
        if selectedCategory != .github {
            VStack(alignment: .leading, spacing: 12) {
                if !displayedTools.isEmpty {
                    HStack {
                        Text("TOOLS")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .tracking(2)
                            .foregroundStyle(ARESColors.textTertiary)
                        Spacer()
                    }
                    let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12, alignment: .top)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(displayedTools) { tool in
                            ToolCard(tool: tool)
                        }
                    }
                }
            }
        }
    }

    // MARK: - GitHub section

    @ViewBuilder
    private func githubSection(isNarrow: Bool) -> some View {
        if !gitHub.repos.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.caption2)
                        .foregroundStyle(ARESColors.gold)
                    Text("GITHUB REPOS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textTertiary)
                    if gitHub.ghAvailable {
                        Text("· live via gh")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.green)
                    } else {
                        Text("· local clones only")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.textTertiary)
                    }
                    Spacer()
                }
                let columns = [GridItem(.adaptive(minimum: 260, maximum: 380), spacing: 12, alignment: .top)]
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(gitHub.repos) { repo in
                        GitHubRepoCard(repo: repo)
                    }
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 48))
                .foregroundStyle(ARESColors.textTertiary.opacity(0.5))
            Text("No AI tools detected")
                .font(.headline)
                .foregroundStyle(ARESColors.textPrimary)
            Text("Install a coding agent, model server, or media tool, then rescan.")
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)
            Button {
                Task {
                    await discovery.scan()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("SCAN AGAIN")
                        .fontWeight(.bold)
                        .tracking(1.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ARESColors.gold.opacity(0.15))
                .foregroundStyle(ARESColors.gold)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Tool card

struct ToolCard: View {
    let tool: DiscoveredTool
    @State private var showTerminal = false

    var body: some View {
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: tool.icon)
                        .font(.title3)
                        .foregroundStyle(tool.executablePath != nil || tool.appBundlePath != nil ? ARESColors.gold : ARESColors.textTertiary)
                    Spacer()
                    if tool.executablePath != nil || tool.appBundlePath != nil {
                        Circle()
                            .fill(ARESColors.green)
                            .frame(width: 6, height: 6)
                    } else {
                        Text("DETECTED")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(ARESColors.textTertiary)
                    }
                }

                Text(tool.name)
                    .font(.headline)
                    .foregroundStyle(ARESColors.textPrimary)
                    .lineLimit(1)

                Text(tool.category.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .tracking(1)
                    .foregroundStyle(ARESColors.gold.opacity(0.8))

                if let path = tool.executablePath {
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ARESColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let app = tool.appBundlePath {
                    Text(app)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ARESColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let data = tool.dataPath {
                    Text(data)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ARESColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                // Action hint
                HStack {
                    Image(systemName: actionIcon)
                        .font(.caption2)
                    Text(actionLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .foregroundStyle(canOpen ? ARESColors.gold : ARESColors.textTertiary)
            }
            .padding(14)
            .frame(minHeight: 140, alignment: .topLeading)
            .background(ARESColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ARESColors.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .opacity(canOpen ? 1.0 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!canOpen)
    }

    private var canOpen: Bool {
        tool.executablePath != nil || tool.appBundlePath != nil
    }

    private var actionIcon: String {
        switch tool.kind {
        case .cli:    return "terminal.fill"
        case .app:    return "arrow.up.right.square"
        case .webUI:  return "globe"
        }
    }

    private var actionLabel: String {
        switch tool.kind {
        case .cli:    return "RUN IN TERMINAL"
        case .app:    return "OPEN"
        case .webUI:  return "OPEN WEB UI"
        }
    }

    private func open() {
        switch tool.kind {
        case .cli:
            if let path = tool.executablePath {
                showTerminal = true
                // Trigger the sheet — but actually we just open Terminal.app for now
                let exe = (path as NSString).lastPathComponent
                let script = """
                tell application "Terminal"
                    activate
                    do script "\(exe)"
                end tell
                """
                if let s = NSAppleScript(source: script) {
                    var err: NSDictionary?
                    s.executeAndReturnError(&err)
                }
            }
        case .app:
            if let path = tool.appBundlePath {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        case .webUI:
            if let url = tool.webURL, let u = URL(string: url) {
                NSWorkspace.shared.open(u)
            }
        }
    }
}


// MARK: - GitHub repo card

struct GitHubRepoCard: View {
    let repo: GitHubRepo

    var body: some View {
        Button {
            open()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: repo.cloneStatus == .cloned ? "checkmark.circle.fill" : "icloud.and.arrow.down")
                        .font(.title3)
                        .foregroundStyle(repo.cloneStatus == .cloned ? ARESColors.green : ARESColors.textTertiary)
                    Spacer()
                    if repo.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .font(.headline)
                        .foregroundStyle(ARESColors.textPrimary)
                        .lineLimit(1)
                    Text(repo.owner)
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                        .lineLimit(1)
                }

                if let desc = repo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(ARESColors.textSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 10) {
                    if let lang = repo.language {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(languageColor(lang))
                                .frame(width: 7, height: 7)
                            Text(lang)
                                .font(.caption2)
                                .foregroundStyle(ARESColors.textSecondary)
                        }
                    }
                    if repo.stars > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(ARESColors.gold)
                            Text(formatCount(repo.stars))
                                .font(.caption2)
                                .foregroundStyle(ARESColors.textSecondary)
                        }
                    }
                    if repo.openPRs > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.pull")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("\(repo.openPRs)")
                                .font(.caption2)
                                .foregroundStyle(ARESColors.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 2)

                if let path = repo.localPath {
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ARESColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let url = repo.remoteURL {
                    Text(url)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ARESColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Image(systemName: actionIcon)
                        .font(.caption2)
                    Text(actionLabel)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .foregroundStyle(ARESColors.gold)
            }
            .padding(14)
            .frame(minHeight: 160, alignment: .topLeading)
            .background(ARESColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ARESColors.divider, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var actionIcon: String {
        if repo.localPath != nil {
            let bundleIDs = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed"]
            for id in bundleIDs {
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil {
                    return "chevron.left.forwardslash.chevron.right"
                }
            }
            return "folder"
        }
        return "icloud.and.arrow.down"
    }

    private var actionLabel: String {
        if repo.localPath != nil { return "OPEN" }
        return "CLONE"
    }

    private func open() {
        if let path = repo.localPath {
            let targetURL = URL(fileURLWithPath: path)
            let bundleIDs = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed"]
            for id in bundleIDs {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.open([targetURL], withApplicationAt: appURL, configuration: config)
                    return
                }
            }
            NSWorkspace.shared.open(targetURL)
        } else if let urlStr = repo.remoteURL, URL(string: urlStr) != nil {
            // Clone via gh
            let parent = NSString(string: "~/GitHub").expandingTildeInPath
            let target = (parent as NSString).appendingPathComponent(repo.name)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["gh", "repo", "clone", repo.id, target]
            p.currentDirectoryURL = URL(fileURLWithPath: parent)
            try? p.run()
        }
    }

    private func languageColor(_ lang: String) -> Color {
        switch lang.lowercased() {
        case "swift":        return .orange
        case "python":       return .blue
        case "javascript",
             "typescript":   return .yellow
        case "rust":         return .red
        case "go":           return .cyan
        case "shell",
             "bash":         return .green
        case "c",
             "c++":          return .gray
        default:             return ARESColors.gold
        }
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(n)"
    }
}

// MARK: - Category ordering

extension DiscoveredTool.ToolCategory {
    static let allOrdered: [DiscoveredTool.ToolCategory] = [
        .codingAgent, .modelServer, .github, .research, .media, .utility, .unknown
    ]
}

// MARK: - CLI terminal view
//
// Embeds a real terminal (SwiftTerm's LocalProcessTerminalView) running the
// tool's CLI as a child process. This is the work surface: the user types
// prompts, the CLI renders its TUI inline, full interactivity preserved.

struct CLITerminalView: NSViewRepresentable {
    let command: String
    let toolName: String
    let toolIcon: String
    let dataPath: String

    func makeNSView(context: Context) -> TerminalHostView {
        let view = TerminalHostView()
        view.apply(appearance: TerminalThemePreference.defaultValue.resolvedAppearance)
        view.translatesAutoresizingMaskIntoConstraints = false
        launchCommand(in: view)
        return view
    }

    func updateNSView(_ nsView: TerminalHostView, context: Context) {}

    private func launchCommand(in view: TerminalHostView) {
        // Resolve full path. SwiftTerm spawns the executable directly via posix_spawn,
        // so it needs the absolute path or a value that's on PATH via the shell.
        // Use /usr/bin/env to resolve via the user's PATH.
        let env = [
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            "PATH=\(ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:\(NSString(string: "~/.local/bin").expandingTildeInPath)")"
        ]
        view.terminalView.startProcess(
            executable: "/usr/bin/env",
            args: [command],
            environment: env
        )
    }
}

// MARK: - CLI tab content (header + terminal + extras)

struct CLITabContent: View {
    let command: String
    let toolName: String
    let toolIcon: String
    let dataPath: String

    @State private var isInstalled: Bool = false
    @State private var sessions: [UnifiedSession] = []
    @State private var showSessions: Bool = false
    @State private var showResetConfirm: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(ARESColors.divider)
            terminalArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .task { await refresh() }
        .sheet(isPresented: $showSessions) {
            SessionsSheet(toolName: toolName, sessions: sessions, onClose: { showSessions = false })
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: toolIcon)
                .font(.title3)
                .foregroundStyle(ARESColors.gold)

            VStack(alignment: .leading, spacing: 2) {
                Text(toolName)
                    .font(.headline)
                    .foregroundStyle(ARESColors.textPrimary)
                if isInstalled {
                    HStack(spacing: 4) {
                        Circle().fill(ARESColors.green).frame(width: 5, height: 5)
                        Text("Running")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.green)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                        Text("Not installed — `brew install \(command)` or check PATH")
                            .font(.caption2)
                            .foregroundStyle(ARESColors.red)
                    }
                }
            }

            Spacer()

            // Sessions button
            Button {
                Task {
                    await loadSessions()
                    showSessions = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                    Text("SESSIONS")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ARESColors.surface)
                .foregroundStyle(ARESColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ARESColors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isInstalled)

            // Open in Terminal.app
            Button {
                openInTerminalApp()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.caption2)
                    Text("OPEN IN TERMINAL")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ARESColors.surface)
                .foregroundStyle(ARESColors.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(ARESColors.divider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Open data dir
            Button {
                openDataDir()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text("DATA DIR")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ARESColors.gold.opacity(0.15))
                .foregroundStyle(ARESColors.gold)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ARESColors.surface)
    }

    // MARK: - Terminal area

    @ViewBuilder
    private var terminalArea: some View {
        if isInstalled {
            CLITerminalView(
                command: command,
                toolName: toolName,
                toolIcon: toolIcon,
                dataPath: dataPath
            )
        } else {
            notInstalledView
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 14) {
            Image(systemName: toolIcon)
                .font(.system(size: 48))
                .foregroundStyle(ARESColors.textTertiary.opacity(0.5))
            Text("\(toolName) is not installed")
                .font(.title3)
                .foregroundStyle(ARESColors.textPrimary)
            Text("Install with `brew install \(command)` (or check your PATH).")
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)
            Button {
                openInTerminalApp()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "macwindow")
                    Text("Open Terminal to install")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(ARESColors.gold.opacity(0.15))
                .foregroundStyle(ARESColors.gold)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    // MARK: - Actions

    private func refresh() async {
        isInstalled = FileManager.default.isExecutableFile(atPath: resolveCommandPath())
    }

    private func loadSessions() async {
        // Build the right SourceReader for this tool. HubView used to hard-code
        // only Claude and Gemini here, which silently broke Odysseus and Hermes —
        // their readers existed but were never instantiated.
        let reader: any SourceReader
        switch command {
        case "claude":  reader = ClaudeSessionReader()
        case "gemini":  reader = GeminiSessionReader()
        case "odysseus": reader = OdysseusSessionReader()
        case "hermes":  reader = HermesSessionReader()
        default:        reader = GeminiSessionReader()
        }
        if let result = try? reader.listSessions() {
            sessions = result
        }
    }

    private func resolveCommandPath() -> String {
        // Check ~/.local/bin, /usr/local/bin, /opt/homebrew/bin, /usr/bin
        let home = NSString(string: "~").expandingTildeInPath
        let candidates = [
            "\(home)/.local/bin/\(command)",
            "/usr/local/bin/\(command)",
            "/opt/homebrew/bin/\(command)",
            "/usr/bin/\(command)"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return "/usr/bin/\(command)" // fallback; notInstalledView will show
    }

    private func openInTerminalApp() {
        let script = """
        tell application "Terminal"
            activate
            do script "\(command)"
        end tell
        """
        if let s = NSAppleScript(source: script) {
            var err: NSDictionary?
            s.executeAndReturnError(&err)
        }
    }

    private func openDataDir() {
        let expanded = NSString(string: dataPath).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: expanded))
    }
}

// MARK: - Sessions sheet (read-only browser for the tool's past sessions)

struct SessionsSheet: View {
    let toolName: String
    let sessions: [UnifiedSession]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(toolName) Sessions")
                    .font(.headline)
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.plain)
                    .foregroundStyle(ARESColors.textSecondary)
            }
            .padding(16)
            Divider().background(ARESColors.divider)

            if sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.title)
                        .foregroundStyle(ARESColors.textTertiary)
                    Text("No past sessions found")
                        .font(.subheadline)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sessions) { session in
                            sessionRow(session)
                            Divider().background(ARESColors.divider)
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 500)
        .background(ARESColors.background)
    }

    private func sessionRow(_ session: UnifiedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? "Untitled session")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(ARESColors.textPrimary)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(session.id)
                    .font(.caption2)
                    .foregroundStyle(ARESColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let updated = session.updatedAt {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                    Text(relativeDate(updated))
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                }
                if let count = session.messageCount {
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                    Text("\(count) msg")
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Hub empty state (used by .desktop section)

struct HubEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36))
                .foregroundStyle(ARESColors.gold.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundStyle(ARESColors.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Backend embed (DISABLED: would re-render ARESRootView recursively)

/*
struct BackendWebView: NSViewRepresentable {
    @ObservedObject var state: ARESAppState

    func makeNSView(context: Context) -> NSView {
        let rootView = ARESRootView().environmentObject(state)
        let controller = NSHostingController(rootView: rootView)
        context.coordinator.controller = controller

        controller.view.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        container.clipsToBounds = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var controller: AnyObject?
    }
}
*/

// MARK: - Backend WebUI view

struct WebUIView: NSViewRepresentable {
    let url: String

    init(url: String = "http://localhost:9119") {
        self.url = url
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if let parsed = URL(string: url) {
            webView.load(URLRequest(url: parsed))
        }
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}


// MARK: - Spartan group box

struct SpartanGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
            configuration.content
                .background(ARESColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ARESColors.divider, lineWidth: 1)
                )
        }
    }
}

// MARK: - Hub section
//
// A dynamic wrapper around an InstalledTool. Built by HubView from
// the live IntegrationRegistry — not an enum of hard-coded tools.

struct HubSection: Identifiable {
    let tool: InstalledTool

    var id: String { tool.id }

    var title: String {
        // Use the registry's name verbatim (e.g. "Hermes Agent", "Codex").
        // Cap to ~20 chars for the tab to keep the bar readable.
        if tool.name.count <= 16 { return tool.name }
        return String(tool.name.prefix(14)) + "…"
    }

    /// Abbreviated title for narrow windows.
    var shortTitle: String {
        // For the tab, drop the last word if there's more than one.
        // "Claude Code" -> "Claude", "Hermes Agent" -> "Hermes", "Codex" -> "Codex"
        let parts = tool.name.split(separator: " ")
        if parts.count > 1 { return String(parts[0]) }
        if tool.name.count > 6 { return String(tool.name.prefix(6)) }
        return tool.name
    }
}