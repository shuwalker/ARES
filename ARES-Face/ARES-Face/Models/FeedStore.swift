import Foundation
import Combine

/// Generic, adaptable data source system.
///
/// Not hardcoded to any specific data type. The user configures feed adapters
/// (stocks, social, sensors, smart home, GitHub, anything). Each adapter
/// conforms to the FeedAdapter protocol and produces FeedCard values.
///
/// Inspired by Hermes Desktop's unified inbox, but generalized:
/// ARES doesn't show "20 platform message feeds." It shows whatever
/// the user has configured. The app is a platform, not our personal dashboard.
@MainActor
final class FeedStore: ObservableObject {
    @Published var cards: [FeedCard] = []
    @Published var adapters: [FeedAdapterConfig] = []
    @Published var isLoading = false

    /// User-saved layout (which cards are visible, their positions).
    /// Persisted to UserDefaults for now — migrate to SQLite later.
    @Published var layout: FeedLayout = .grid

    private var refreshTasks: [String: Task<Void, Never>] = [:]

    init() {
        loadPersistedAdapters()
    }

    // MARK: - Adapter Management

    func addAdapter(_ config: FeedAdapterConfig) {
        adapters.append(config)
        persistAdapters()
        startRefreshing(config)
    }

    func removeAdapter(id: String) {
        adapters.removeAll { $0.id == id }
        refreshTasks[id]?.cancel()
        refreshTasks.removeValue(forKey: id)
        cards.removeAll { $0.sourceId == id }
        persistAdapters()
    }

    func toggleAdapter(id: String) {
        if let idx = adapters.firstIndex(where: { $0.id == id }) {
            adapters[idx].isEnabled.toggle()
            if adapters[idx].isEnabled {
                startRefreshing(adapters[idx])
            } else {
                refreshTasks[id]?.cancel()
                refreshTasks.removeValue(forKey: id)
                cards.removeAll { $0.sourceId == id }
            }
            persistAdapters()
        }
    }

    // MARK: - Refresh

    /// Manually trigger a full refresh of all enabled adapters.
    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }
        for adapter in adapters where adapter.isEnabled {
            await refreshAdapter(adapter)
        }
    }

    private func startRefreshing(_ config: FeedAdapterConfig) {
        refreshTasks[config.id]?.cancel()
        refreshTasks[config.id] = Task { [weak self] in
            // Initial fetch
            await self?.refreshAdapter(config)
            // Then poll on the configured interval
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(config.refreshIntervalSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.refreshAdapter(config)
            }
        }
    }

    private func refreshAdapter(_ config: FeedAdapterConfig) async {
        // Built-in adapter types — expand this as we add more
        switch config.type {
        case .hermesStatus:
            await fetchHermesStatus(config)
        case .httpJson:
            await fetchHTTPJson(config)
        case .shell:
            break // Future: run a shell command and parse output
        case .mqtt:
            break // Future: subscribe to MQTT topic
        }
    }

    // MARK: - Built-in Adapters

    private func fetchHermesStatus(_ config: FeedAdapterConfig) async {
        let service = HermesDashboardService()
        if let statusData = try? await service.getConfig() {
            let modelName = statusData.model ?? "unknown"
            let card = FeedCard(
                sourceId: config.id,
                title: "Hermes Agent",
                value: modelName,
                subtitle: "Active",
                style: .status
            )
            updateCard(card)
        }
    }

    private func fetchHTTPJson(_ config: FeedAdapterConfig) async {
        guard let url = URL(string: config.endpoint ?? "") else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            // Parse JSON and extract value at config.jsonPath
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = resolveJsonPath(json, path: config.jsonPath ?? "") {
                let card = FeedCard(
                    sourceId: config.id,
                    title: config.name,
                    value: String(describing: value),
                    subtitle: config.name,
                    style: config.cardStyle
                )
                updateCard(card)
            }
        } catch {
            // Silently fail — don't crash the feed for one bad adapter
        }
    }

    /// Resolve a dot-notation path like "data.temperature" into a JSON value.
    private func resolveJsonPath(_ json: [String: Any], path: String) -> Any? {
        var current: Any = json
        for key in path.split(separator: ".").map(String.init) {
            if let dict = current as? [String: Any], let val = dict[key] {
                current = val
            } else {
                return nil
            }
        }
        return current
    }

    // MARK: - Card Management

    private func updateCard(_ card: FeedCard) {
        if let idx = cards.firstIndex(where: { $0.sourceId == card.sourceId }) {
            cards[idx] = card
        } else {
            cards.append(card)
        }
    }

    // MARK: - Persistence

    private func persistAdapters() {
        if let data = try? JSONEncoder().encode(adapters) {
            UserDefaults.standard.set(data, forKey: "FeedStore.adapters")
        }
    }

    private func loadPersistedAdapters() {
        if let data = UserDefaults.standard.data(forKey: "FeedStore.adapters"),
           let decoded = try? JSONDecoder().decode([FeedAdapterConfig].self, from: data) {
            adapters = decoded
            for adapter in adapters where adapter.isEnabled {
                startRefreshing(adapter)
            }
        }
    }
}

// MARK: - Models

struct FeedCard: Identifiable, Equatable {
    let id = UUID().uuidString
    let sourceId: String
    let title: String
    let value: String
    let subtitle: String
    let style: CardStyle
    let timestamp = Date.now

    enum CardStyle: String, Codable, CaseIterable {
        case number      // Big number (42)
        case sparkline   // Mini chart (future)
        case status      // Green/yellow/red dot
        case list         // Bulleted items
        case chart        // Full chart (future)
    }
}

struct FeedAdapterConfig: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var type: AdapterType
    var endpoint: String?
    var jsonPath: String?
    var refreshIntervalSeconds: Double
    var isEnabled: Bool
    var cardStyle: FeedCard.CardStyle

    enum AdapterType: String, Codable, CaseIterable {
        case hermesStatus = "hermes"
        case httpJson = "http+json"
        case shell = "shell"
        case mqtt = "mqtt"
    }
}

enum FeedLayout: String, CaseIterable {
    case grid
    case list
}