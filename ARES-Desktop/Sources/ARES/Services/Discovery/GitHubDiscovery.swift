import Foundation
import SwiftUI

// MARK: - GitHub repository model
//
// Represents a repo — either a local clone (the user has it on disk)
// or a remote-only repo they don't have locally. We get info from:
//   - Local: parse .git/config for remote URL, latest mtime for activity
//   - Remote: `gh api` to fetch stars, description, language, last push
// Local + remote repos are unified into one list per `owner/name`.

struct GitHubRepo: Identifiable, Equatable {
    let id: String                  // "owner/name"
    let name: String                // "ARES"
    let owner: String               // "shuwalker"
    let localPath: String?          // absolute path if cloned
    let cloneStatus: CloneStatus
    let description: String?
    let language: String?
    let stars: Int
    let forks: Int
    let lastActivity: Date?         // last commit timestamp
    let isPrivate: Bool
    let defaultBranch: String
    let openPRs: Int

    enum CloneStatus: Equatable {
        case cloned                  // local copy exists
        case notCloned               // remote only
    }

    /// The full set of git remotes this repo appears in (deduplicated
    /// by `owner/name`). Used by the Hub card to show variants.
    let remoteURL: String?
}

// MARK: - GitHub discovery
//
// Scans ~/GitHub/ for local clones, parses their .git/config for
// remote URLs, then optionally queries `gh` CLI for live metadata
// (stars, description, language, last commit, open PRs).
//
// Network access only when `gh` is installed AND authed. Falls back
// gracefully to local-only info (path, mtime) when offline.

@MainActor
final class GitHubDiscovery: ObservableObject {

    @Published var repos: [GitHubRepo] = []
    @Published var lastScanDate: Date? = nil
    @Published var ghAvailable: Bool = false

    /// Default location to scan for clones. User can override later.
    var scanPaths: [String] = ["~/GitHub"]

    func scan() {
        ghAvailable = checkGhAvailable()

        var found: [GitHubRepo] = []

        // 1. Walk scan paths, find git repos
        let localRepos = scanLocalClones()
        for clone in localRepos {
            let owner = clone.owner ?? "local"
            let name = clone.name
            let id = "\(owner)/\(name)"

            // 2. Try to enrich with `gh` if available
            let enriched = enrichFromGh(owner: owner, name: name, local: clone)
            found.append(enriched)
        }

        // 3. Optionally add starred remote-only repos (gated by gh)
        if ghAvailable {
            let remoteOnly = fetchStarredRepos(excludingLocal: found)
            found.append(contentsOf: remoteOnly)
        }

        // Sort: cloned first, then by last activity desc
        found.sort { lhs, rhs in
            if lhs.cloneStatus != rhs.cloneStatus {
                return lhs.cloneStatus == .cloned
            }
            return (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast)
        }

        repos = found
        lastScanDate = Date()
    }

    // MARK: - Local clone scan

    private struct LocalClone {
        let path: String
        let owner: String?
        let name: String
        let remoteURL: String?
        let lastMtime: Date?
    }

    private func scanLocalClones() -> [LocalClone] {
        var found: [LocalClone] = []

        for scanPath in scanPaths {
            let expanded = NSString(string: scanPath).expandingTildeInPath
            let dir = URL(fileURLWithPath: expanded)
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in contents {
                let gitDir = entry.appendingPathComponent(".git")
                let isGitRepo = FileManager.default.fileExists(atPath: gitDir.path)

                // Some repos have no .git dir but are still git
                // workspaces — check for a `.git` file too (worktrees)
                let gitFile = entry.appendingPathComponent(".git")
                let isGitFile = FileManager.default.fileExists(atPath: gitFile.path)

                guard isGitRepo || isGitFile else { continue }

                let name = entry.lastPathComponent
                let (owner, url) = parseRemote(from: gitDir.path)
                let mtime = mtimeFor(entry.path)
                found.append(LocalClone(
                    path: entry.path,
                    owner: owner,
                    name: name,
                    remoteURL: url,
                    lastMtime: mtime
                ))
            }
        }
        return found
    }

    private func parseRemote(from gitDir: String) -> (owner: String?, url: String?) {
        let configPath = (gitDir as NSString).appendingPathComponent("config")
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else {
            return (nil, nil)
        }
        var url: String? = nil
        var inRemoteOrigin = false
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[remote ") && trimmed.contains("origin") {
                inRemoteOrigin = true
                continue
            }
            if trimmed.hasPrefix("[") {
                inRemoteOrigin = false
            }
            if inRemoteOrigin, trimmed.hasPrefix("url = ") {
                url = String(trimmed.dropFirst("url = ".count))
                break
            }
        }
        guard let u = url else { return (nil, nil) }
        // Extract owner/repo from URL
        // git@github.com:owner/repo.git or https://github.com/owner/repo.git
        let ownerRepo = Self.extractOwnerRepo(from: u)
        return (ownerRepo?.owner, u)
    }

    private static func extractOwnerRepo(from url: String) -> (owner: String, repo: String)? {
        // Normalize: strip .git suffix
        var s = url
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        // SSH format: git@github.com:owner/repo
        if let colonRange = s.range(of: ":") {
            let afterColon = s[colonRange.upperBound...]
            let parts = afterColon.split(separator: "/").map(String.init)
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        // HTTPS format: https://github.com/owner/repo
        if let url = URL(string: s), let host = url.host {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.count >= 2 { return (parts[0], parts[1]) }
        }
        return nil
    }

    // MARK: - `gh` CLI enrichment

    private func checkGhAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "gh"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Query `gh api repos/{owner}/{name}` for live repo metadata.
    /// Returns the metadata as a dict, or nil on any error.
    private func ghAPI(_ endpoint: String) -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "api", endpoint]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Query `gh api` for a list response (e.g. user/starred).
    private func ghAPIArray(_ endpoint: String) -> [[String: Any]]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "api", endpoint]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private func ghAPICount(_ endpoint: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "api", endpoint, "--jq", "length"]
        let stdout = Pipe()
        process.standardError = Pipe()
        process.standardOutput = stdout
        do {
            try process.run()
            process.waitUntilExit()
        } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(s ?? "")
    }

    private func enrichFromGh(owner: String, name: String, local: LocalClone) -> GitHubRepo {
        let id = "\(owner)/\(name)"
        let endpoint = "repos/\(owner)/\(name)"

        guard let data = ghAPI(endpoint) else {
            // gh failed (auth, rate limit, repo not on this account)
            return GitHubRepo(
                id: id, name: name, owner: owner,
                localPath: local.path,
                cloneStatus: .cloned,
                description: nil, language: nil,
                stars: 0, forks: 0,
                lastActivity: local.lastMtime,
                isPrivate: false, defaultBranch: "main",
                openPRs: 0,
                remoteURL: local.remoteURL
            )
        }

        let desc = data["description"] as? String
        let lang = data["language"] as? String
        let stars = (data["stargazers_count"] as? Int) ?? 0
        let forks = (data["forks_count"] as? Int) ?? 0
        let priv = (data["private"] as? Bool) ?? false
        let branch = (data["default_branch"] as? String) ?? "main"

        // Last activity: prefer pushed_at, fall back to updated_at
        var lastActivity = local.lastMtime
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let df2 = ISO8601DateFormatter()
        if let pushed = data["pushed_at"] as? String {
            lastActivity = dateFormatter.date(from: pushed) ?? df2.date(from: pushed) ?? local.lastMtime
        } else if let updated = data["updated_at"] as? String {
            lastActivity = dateFormatter.date(from: updated) ?? df2.date(from: updated) ?? local.lastMtime
        }

        // Open PRs count
        let prs = ghAPICount("repos/\(owner)/\(name)/pulls?state=open") ?? 0

        return GitHubRepo(
            id: id, name: name, owner: owner,
            localPath: local.path,
            cloneStatus: .cloned,
            description: desc, language: lang,
            stars: stars, forks: forks,
            lastActivity: lastActivity,
            isPrivate: priv, defaultBranch: branch,
            openPRs: prs,
            remoteURL: local.remoteURL
        )
    }

    /// Fetch user's starred repos (paginated, first 100). Excludes
    /// anything already in the local list.
    private func fetchStarredRepos(excludingLocal: [GitHubRepo]) -> [GitHubRepo] {
        guard let arr = ghAPIArray("user/starred?per_page=100") else { return [] }
        let localIds = Set(excludingLocal.map { $0.id })

        var result: [GitHubRepo] = []
        for entry in arr {
            guard let fullName = entry["full_name"] as? String else { continue }
            guard !localIds.contains(fullName) else { continue }
            let parts = fullName.split(separator: "/").map(String.init)
            guard parts.count == 2 else { continue }
            let desc = entry["description"] as? String
            let lang = entry["language"] as? String
            let stars = (entry["stargazers_count"] as? Int) ?? 0
            let forks = (entry["forks_count"] as? Int) ?? 0
            let priv = (entry["private"] as? Bool) ?? false
            let branch = (entry["default_branch"] as? String) ?? "main"
            let htmlURL = entry["html_url"] as? String

            var lastActivity: Date? = nil
            let df = ISO8601DateFormatter()
            if let s = entry["pushed_at"] as? String {
                lastActivity = df.date(from: s)
            }

            result.append(GitHubRepo(
                id: fullName, name: parts[1], owner: parts[0],
                localPath: nil, cloneStatus: .notCloned,
                description: desc, language: lang,
                stars: stars, forks: forks,
                lastActivity: lastActivity,
                isPrivate: priv, defaultBranch: branch,
                openPRs: 0,
                remoteURL: htmlURL
            ))
        }
        return result
    }

    // MARK: - File helpers

    private func mtimeFor(_ path: String) -> Date? {
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            return attrs[.modificationDate] as? Date
        } catch {
            return nil
        }
    }
}
