import Foundation

extension AppState {
    // MARK: - Soul

    func loadSoul() async {
        guard let connection = activeConnection else { return }
        soulError = nil
        do {
            let content = try await soulService.fetchSoul(connection: connection)
            guard isActiveWorkspace(connection) else { return }
            soulContent = content
        } catch {
            guard isActiveWorkspace(connection) else { return }
            soulError = error.localizedDescription
        }
    }

    func saveSoul(_ content: String) async {
        guard let connection = activeConnection else { return }
        isSavingSoul = true
        soulError = nil
        do {
            try await soulService.saveSoul(content, connection: connection)
            guard isActiveWorkspace(connection) else { return }
            soulContent = content
            isSavingSoul = false
        } catch {
            guard isActiveWorkspace(connection) else { return }
            isSavingSoul = false
            soulError = error.localizedDescription
        }
    }
}
