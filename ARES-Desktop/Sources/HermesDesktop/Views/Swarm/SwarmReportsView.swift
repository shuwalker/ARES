import AppKit
import SwiftUI

// MARK: - Report Filter

enum SwarmReportFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case blocked = "Blocked"
    case done = "Done"

    var id: String { rawValue }
}

struct SwarmReportsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: SwarmReportFilter = .all

    private var filtered: [SwarmReport] {
        switch filter {
        case .all: return appState.swarmReports
        case .needsReview: return appState.swarmReports.filter { $0.status == "needs_review" }
        case .blocked: return appState.swarmReports.filter { $0.status == "blocked" }
        case .done: return appState.swarmReports.filter { $0.status == "done" }
        }
    }

    var body: some View {
        HermesPageContainer {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Mission Reports",
                    subtitle: "Aggregated mission results from all swarm workers."
                )

                // Error banner
                if let error = appState.swarmError {
                    SwarmErrorBanner(message: error) { appState.swarmError = nil }
                }

                Picker("Filter", selection: $filter) {
                    ForEach(SwarmReportFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                if appState.swarmError != nil && appState.swarmReports.isEmpty {
                    SwarmFeatureUnavailableView(
                        message: appState.swarmError ?? "",
                        onRetry: { Task { await appState.loadSwarmReports() } }
                    )
                } else if appState.swarmReports.isEmpty {
                    ContentUnavailableView(
                        "No Reports Yet",
                        systemImage: "doc.text",
                        description: Text("Mission reports will appear here when workers complete tasks.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Matching Reports",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No reports match the selected filter.")
                    )
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { report in
                            SwarmReportRow(report: report)
                        }
                    }
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadSwarmReports()
        }
    }
}

struct SwarmReportRow: View {
    let report: SwarmReport

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(report.missionTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(report.worker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = report.createdAt {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let summary = report.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            reportBadge
        }
        .padding(14)
        .background(HermesTheme.panelFill, in: RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke)
        )
    }

    private var reportBadge: some View {
        let (label, color): (String, Color) = {
            switch report.status {
            case "needs_review": return ("Needs Review", .orange)
            case "ready_to_merge": return ("Ready to Merge", .green)
            case "blocked": return ("Blocked", .red)
            case "done": return ("Done", Color(NSColor.systemGreen))
            default: return (report.status.replacingOccurrences(of: "_", with: " ").capitalized, .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
