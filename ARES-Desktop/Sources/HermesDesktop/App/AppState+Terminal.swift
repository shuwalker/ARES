import Foundation

extension AppState {
    // MARK: - Terminal

    func ensureTerminalSession() {
        guard let profile = activeConnection else { return }
        terminalWorkspace.ensureInitialTab(for: profile)
    }

    func openNewTerminalTab(for profile: ConnectionProfile) {
        terminalWorkspace.addTab(for: profile)
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("New Terminal tab opened"))
    }
}
