import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Analytics",
                    subtitle: "Session activity, token usage, and cost overview for the selected period."
                ) {
                    periodPicker
                }

                dashboardContent
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingDashboard && appState.dashboardOverview != nil {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadDashboardOverview()
        }
        .onChange(of: appState.dashboardPeriod) { _, _ in
            Task { await appState.loadDashboardOverview() }
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("Period", selection: $appState.dashboardPeriod) {
            Text("7d").tag(7)
            Text("14d").tag(14)
            Text("30d").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
    }

    // MARK: - Content

    @ViewBuilder
    private var dashboardContent: some View {
        if !appState.dashboardAPIAvailable {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Dashboard Analytics Unavailable",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Analytics requires a local Hermes connection or an active SSH tunnel.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if appState.isLoadingDashboard && appState.dashboardOverview == nil {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading analytics…", minHeight: 320)
            }
        } else if let overview = appState.dashboardOverview {
            VStack(alignment: .leading, spacing: 20) {
                statsCardsRow(overview: overview)
                chartSection(overview: overview)
                recentSessionsSection
            }
        } else {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No Analytics Data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("No dashboard data is available for this period.")
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
    }

    // MARK: - Stats Cards

    private func statsCardsRow(overview: DashboardOverview) -> some View {
        HFlow {
            statCard(
                title: "Sessions",
                value: "\(overview.totalSessions)",
                icon: "clock.arrow.circlepath"
            )
            statCard(
                title: "Messages",
                value: "\(overview.totalMessages)",
                icon: "bubble.left.and.bubble.right"
            )
            statCard(
                title: "Tool Calls",
                value: "\(overview.totalToolCalls)",
                icon: "wrench.and.screwdriver"
            )
            statCard(
                title: "Tokens",
                value: formatTokens(overview.totalTokens),
                icon: "text.word.spacing"
            )
            statCard(
                title: "Est. Cost",
                value: formatCost(overview.estimatedCost),
                icon: "dollarsign.circle"
            )
            if let efficiency = overview.cacheEfficiency {
                statCard(
                    title: "Cache Efficiency",
                    value: String(format: "%.1f%%", efficiency * 100),
                    icon: "memorychip"
                )
            }
        }
    }

    private func statCard(title: String, value: String, icon: String) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(value)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }
            .padding(14)
        }
    }

    // MARK: - Daily Chart

    private func chartSection(overview: DashboardOverview) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Activity")
                    .font(.headline)

                if overview.dailyStats.isEmpty {
                    ContentUnavailableView(
                        "No Daily Data",
                        systemImage: "chart.bar",
                        description: Text("No day-by-day stats for this period.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    Chart {
                        ForEach(overview.dailyStats) { stat in
                            BarMark(
                                x: .value("Date", shortDate(stat.date)),
                                y: .value("Sessions", stat.sessions),
                                width: .ratio(0.4)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                            .position(by: .value("Series", "Sessions"))

                            BarMark(
                                x: .value("Date", shortDate(stat.date)),
                                y: .value("Messages", stat.messages),
                                width: .ratio(0.4)
                            )
                            .foregroundStyle(Color.orange.opacity(0.7))
                            .position(by: .value("Series", "Messages"))
                        }
                    }
                    .chartLegend(position: .bottom, alignment: .leading)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisValueLabel()
                                .font(.caption2)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(minHeight: 200)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Recent Sessions

    private var recentSessionsSection: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Sessions")
                    .font(.headline)

                if appState.sessions.isEmpty {
                    Text("No recent sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 0) {
                        recentSessionsHeader
                        Divider()
                        ForEach(appState.sessions.prefix(10)) { session in
                            recentSessionRow(session: session)
                            Divider()
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var recentSessionsHeader: some View {
        HStack {
            Text("Session ID")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Messages")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text("Model")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text("Status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    private func recentSessionRow(session: SessionSummary) -> some View {
        HStack {
            Text(session.id.prefix(16) + "…")
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(session.messageCount ?? 0)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            Text(session.model ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 80, alignment: .trailing)

            Text(session.status ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func formatCost(_ cost: Double) -> String {
        if cost < 0.001 {
            return String(format: "$%.6f", cost)
        } else if cost < 0.01 {
            return String(format: "$%.4f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.1fK", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    private func shortDate(_ dateString: String) -> String {
        // dateString is expected as "YYYY-MM-DD"; show "MM/DD"
        let parts = dateString.split(separator: "-")
        if parts.count == 3 {
            return "\(parts[1])/\(parts[2])"
        }
        return dateString
    }
}

// MARK: - HFlow helper (wrapping layout)

private struct HFlow: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var rowX: CGFloat = 0
        var rowY: CGFloat = 0
        var maxRowH: CGFloat = 0
        var totalH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > width && rowX > 0 {
                totalH += maxRowH + spacing
                rowX = 0
                maxRowH = 0
            }
            rowX += size.width + spacing
            maxRowH = max(maxRowH, size.height)
        }
        totalH += maxRowH
        _ = rowY
        return CGSize(width: width, height: totalH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rowX: CGFloat = bounds.minX
        var rowY: CGFloat = bounds.minY
        var maxRowH: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > bounds.maxX && rowX > bounds.minX {
                rowY += maxRowH + spacing
                rowX = bounds.minX
                maxRowH = 0
            }
            subview.place(at: CGPoint(x: rowX, y: rowY), proposal: ProposedViewSize(size))
            rowX += size.width + spacing
            maxRowH = max(maxRowH, size.height)
        }
    }
}
