import SwiftUI

/// Application settings panel.
///
/// Currently exposes the "Updates" section where the user can check the
/// current build version, trigger an on-demand update check, and open the
/// GitHub release page when a newer version is available.
struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            updatesSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480)
        .navigationTitle(L10n.string("Settings"))
    }

    // MARK: - Updates section

    @ViewBuilder
    private var updatesSection: some View {
        Section(L10n.string("Updates")) {
            // Current version row
            LabeledContent(L10n.string("Current Version")) {
                Text(UpdateCheckService.bundleShortVersion())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            // Update available banner
            if let update = appState.availableUpdate {
                updateAvailableBanner(update: update)
            }

            // Check for Updates button
            HStack {
                Button(L10n.string("Check for Updates")) {
                    Task {
                        await appState.checkForUpdatesFromCommand()
                    }
                }
                .disabled(appState.isCheckingForUpdates)

                if appState.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }
            }

            // Automatic updates toggle
            Toggle(
                L10n.string("Check Automatically for ARES Updates"),
                isOn: Binding(
                    get: { appState.connectionStore.automaticallyChecksForUpdates },
                    set: { appState.updateAutomaticUpdateChecks($0) }
                )
            )
            .toggleStyle(.checkbox)
        }
    }

    @ViewBuilder
    private func updateAvailableBanner(update: AvailableUpdate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.title3.weight(.medium))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string("ARES %@ is available", update.latestVersion))
                    .font(.headline)

                Text(
                    L10n.string(
                        "You are running ARES %@. The latest ARES release is %@.",
                        update.currentVersion,
                        update.latestVersion
                    )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button(L10n.string("Open Release on GitHub")) {
                    appState.noteOpenedRelease(for: update)
                    openURL(update.htmlURL)
                }
                .buttonStyle(.link)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}
