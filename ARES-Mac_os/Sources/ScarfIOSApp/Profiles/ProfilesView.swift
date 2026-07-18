import SwiftUI
import ScarfCore
import ScarfDesign

/// iOS read-only Profiles view (v2.6).
///
/// Lists `hermes profile list` output and highlights the active profile.
/// Profile switching, creation, deletion, and import/export remain on
/// the Mac app — those involve writing data we don't want to risk
/// fat-fingering on a phone (e.g., wiping the active profile by accident).
struct ProfilesView: View {
    let config: IOSServerConfig

    @State private var profiles: [ProfileRow] = []
    @State private var activeProfile: String?
    @State private var isLoading = true
    @State private var lastError: String?
    @Environment(\.serverContext) private var contextFromEnv

    private var context: ServerContext {
        config.toServerContext(id: contextFromEnv.id)
    }

    var body: some View {
        List {
            if let err = lastError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(ScarfColor.warning)
                }
            }

            if profiles.isEmpty && !isLoading {
                Section {
                    ContentUnavailableView(
                        "No profiles",
                        systemImage: "person.2.crop.square.stack",
                        description: Text("Hermes profiles let you keep multiple HERMES_HOME directories side-by-side. Create one with `hermes profile create <name>` from the Mac app.")
                    )
                }
            } else {
                Section {
                    ForEach(profiles) { p in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .font(.body)
                                if let aliases = p.aliasesLabel {
                                    Text(aliases)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if p.name == activeProfile {
                                ScarfBadge("Active", kind: .success)
                            }
                        }
                    }
                } header: {
                    if let active = activeProfile {
                        Text("Active profile: \(active)")
                    } else {
                        Text("All profiles")
                    }
                } footer: {
                    Text("Switching profiles, creating new ones, and import/export live in the Mac app — they touch enough state that we keep them off the phone.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Profiles")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let ctx = context
        let result = await Task.detached { () -> (output: String, active: String?) in
            let listOut = Self.runHermes(context: ctx, args: ["profile", "list"])
            // Active profile lives at ~/.hermes/active_profile (text file
            // with one line). Reading directly is faster than another
            // CLI round-trip.
            let activeRaw = ctx.readText(ctx.paths.home + "/active_profile")
            let active = activeRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (listOut, active)
        }.value
        self.profiles = Self.parse(result.output)
        self.activeProfile = result.active.flatMap { $0.isEmpty ? nil : $0 }
    }

    nonisolated private static func runHermes(context: ServerContext, args: [String]) -> String {
        let transport = context.makeTransport()
        do {
            let r = try transport.runProcess(
                executable: context.paths.hermesBinary,
                args: args,
                stdin: nil,
                timeout: 30
            )
            return r.stdoutString + r.stderrString
        } catch {
            return ""
        }
    }

    /// Tolerant parser for `hermes profile list`. The CLI prints a
    /// table-like format with the profile name on the leading column
    /// and optional alias / path columns afterwards. We surface the
    /// name (always present); aliases collapse into a comma-separated
    /// label in the row when present.
    nonisolated private static func parse(_ output: String) -> [ProfileRow] {
        var results: [ProfileRow] = []
        for raw in output.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // Skip table-rule and header lines.
            if trimmed.hasPrefix("┃") || trimmed.hasPrefix("┏") || trimmed.hasPrefix("┡")
                || trimmed.hasPrefix("┗") || trimmed.hasPrefix("━") || trimmed.hasPrefix("│") {
                // Strip box-drawing chars and try to extract the leading column.
                let body = trimmed
                    .replacingOccurrences(of: "│", with: "|")
                    .replacingOccurrences(of: "┃", with: "|")
                if !body.contains("|") { continue }
                let cols = body.split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let name = cols.first, !name.isEmpty,
                      name.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
                else { continue }
                let aliases = cols.dropFirst().filter { !$0.isEmpty }.joined(separator: ", ")
                results.append(ProfileRow(name: name, aliasesLabel: aliases.isEmpty ? nil : aliases))
                continue
            }
            // Plain-text fallback: first whitespace-delimited token is the name.
            if let name = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first,
               name.range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil {
                results.append(ProfileRow(name: String(name), aliasesLabel: nil))
            }
        }
        // Dedupe (the table-row + plain-text passes can overlap).
        var seen = Set<String>()
        return results.filter { seen.insert($0.name).inserted }
    }

    private struct ProfileRow: Identifiable {
        var id: String { name }
        let name: String
        let aliasesLabel: String?
    }
}
