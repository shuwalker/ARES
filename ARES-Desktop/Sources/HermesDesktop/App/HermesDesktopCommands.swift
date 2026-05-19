import SwiftUI

struct ARESCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu(L10n.string("Hermes")) {
            Button(L10n.string("New Host")) {
                appState.requestNewConnectionEditorFromCommand()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(L10n.string("New Chat")) {
                appState.requestNewSessionFromCommand()
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(appState.activeConnection == nil || appState.isSendingSessionMessage)

            Button(L10n.string("New Terminal Tab")) {
                appState.openNewTerminalTabFromCommand()
            }
            .keyboardShortcut("t", modifiers: [.command, .option])
            .disabled(appState.activeConnection == nil)

            Divider()

            Button(L10n.string("Refresh Current Section")) {
                Task {
                    await appState.refreshCurrentSectionFromCommand()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!appState.canRefreshCurrentSection)

            Button(L10n.string("Find in Current Section")) {
                appState.requestSearchFocusFromCommand()
            }
            .keyboardShortcut("f", modifiers: [.command])
            .disabled(!appState.canFocusSearchCurrentSection)

            Button(L10n.string("Search…")) {
                appState.isSearchVisible = true
            }
            .keyboardShortcut("k", modifiers: .command)

            Button(L10n.string("Save Current File")) {
                Task {
                    await appState.saveSelectedWorkspaceFile()
                }
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(!appState.canSaveCurrentWorkspaceFile)

            Divider()

            Toggle(
                L10n.string("Check Automatically for ARES Updates"),
                isOn: Binding(
                    get: { appState.connectionStore.automaticallyChecksForUpdates },
                    set: { appState.updateAutomaticUpdateChecks($0) }
                )
            )

            Button(L10n.string("Check for ARES Updates…")) {
                Task {
                    await appState.checkForUpdatesFromCommand()
                }
            }
            .disabled(appState.isCheckingForUpdates)
        }

        CommandMenu(L10n.string("Navigate")) {
            // ⌘1–⌘9: switch to the first 9 sections in order
            ForEach(
                Array(AppSection.allCases.prefix(9).enumerated()),
                id: \.offset
            ) { index, section in
                Button(L10n.string("Show %@", section.title)) {
                    appState.requestSectionSelection(section)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command])
                .disabled(!appState.isSectionAvailable(section))
            }

            Divider()

            // Remaining sections without numeric shortcuts
            ForEach(Array(AppSection.allCases.dropFirst(9))) { section in
                if let shortcut = section.navigationShortcutKey {
                    Button(L10n.string("Show %@", section.title)) {
                        appState.requestSectionSelection(section)
                    }
                    .keyboardShortcut(shortcut, modifiers: [.command])
                    .disabled(!appState.isSectionAvailable(section))
                } else {
                    Button(L10n.string("Show %@", section.title)) {
                        appState.requestSectionSelection(section)
                    }
                    .disabled(!appState.isSectionAvailable(section))
                }
            }
        }
    }
}
