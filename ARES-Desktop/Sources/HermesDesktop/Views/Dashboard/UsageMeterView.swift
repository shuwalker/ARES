import SwiftUI
import UserNotifications

/// Persistent token-usage indicator shown in the sidebar footer.
struct UsageMeterView: View {
    @EnvironmentObject private var appState: AppState

    /// Tracks the highest threshold that has already been alerted so the alert
    /// does not re-fire every time the view reappears.
    @AppStorage("lastAlertThreshold") private var lastAlertThreshold: Int = 0

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
        .onChange(of: pct) { _, newPct in
            fireThresholdAlertIfNeeded(pct: newPct)
        }
        .onAppear {
            fireThresholdAlertIfNeeded(pct: pct)
        }
    }

    // MARK: - Threshold alerting

    /// Only fires an alert when a new, higher threshold is crossed.
    /// Stores the highest threshold alerted in @AppStorage so it survives
    /// view destruction / reappearance without re-alerting.
    private func fireThresholdAlertIfNeeded(pct: Int) {
        let thresholds = [90, 75, 50]
        for threshold in thresholds {
            guard pct >= threshold, threshold > lastAlertThreshold else { continue }
            lastAlertThreshold = threshold
            postContextAlert(threshold: threshold)
            break
        }
    }

    private func postContextAlert(threshold: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Context Window \(threshold)% Full"
        content.body = "The active session context has reached \(threshold)%. Consider starting a new session soon."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "context-threshold-\(threshold)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
