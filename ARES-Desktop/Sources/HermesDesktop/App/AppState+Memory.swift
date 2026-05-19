import Foundation

extension AppState {
    // MARK: - Memory

    func loadMemory() async {
        isLoadingMemory = true
        memoryError = nil
        do {
            let response = try await dashboardAPIService.fetchMemory()
            memoryEntries = response.entries
            isLoadingMemory = false
        } catch {
            isLoadingMemory = false
            memoryError = error.localizedDescription
        }
    }

    func deleteMemoryEntry(id: String) async {
        do {
            try await dashboardAPIService.deleteMemoryEntry(id: id)
            memoryEntries.removeAll { $0.id == id }
        } catch {
            memoryError = error.localizedDescription
        }
    }

    func updateMemoryEntry(id: String, content: String) async {
        do {
            try await dashboardAPIService.updateMemoryEntry(id: id, content: content)
            if let idx = memoryEntries.firstIndex(where: { $0.id == id }) {
                let old = memoryEntries[idx]
                memoryEntries[idx] = MemoryEntry(
                    id: old.id,
                    content: content,
                    createdAt: old.createdAt,
                    source: old.source
                )
            }
        } catch {
            memoryError = error.localizedDescription
        }
    }
}
