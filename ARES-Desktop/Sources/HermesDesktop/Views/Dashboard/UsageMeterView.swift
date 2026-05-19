import SwiftUI

/// Persistent token-usage indicator shown in the sidebar footer.
struct UsageMeterView: View {
    @EnvironmentObject private var appState: AppState

    private var used: Int { appState.sessionContextUsed }
    private var limit: Int { max(appState.sessionContextLimit, 1) }
    private var dailyCost: Double { appState.sessionDailyCost }

    private var pct: Int {
        Int(Double(used) / Double(limit) * 100)
    }

    private var meterTint: Color {
        if pct > 90 { return .red }
        if pct > 75 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Context")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pct)%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(meterTint)
            }

            ProgressView(value: Double(used), total: Double(limit))
                .tint(meterTint)
                .progressViewStyle(.linear)

            Text("$\(String(format: "%.4f", dailyCost)) today")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .padding(.top, 4)
    }
}
