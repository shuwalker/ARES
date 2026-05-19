import Security
import SwiftUI

// MARK: - UserDefaults key constants

private enum DefaultsKey {
    static let memoryProviders = "memory_providers"
}

// MARK: - Keychain helpers

private enum MemoryProviderKeychain {
    private static let service = "com.ares.memory-providers"

    static func saveAPIKey(_ key: String, for providerID: String) {
        let account = "provider-\(providerID)"
        let data = Data(key.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        if !key.isEmpty {
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func loadAPIKey(for providerID: String) -> String {
        let account = "provider-\(providerID)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return ""
        }
        return key
    }

    static func deleteAPIKey(for providerID: String) {
        let account = "provider-\(providerID)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Model

struct MemoryProvider: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let systemImage: String
    var isConfigured: Bool
    /// API key is NOT stored in this model on disk — it is stored in Keychain.
    /// This field is used only in-memory (the UI draft) and is not encoded to UserDefaults.
    var apiKey: String
    var endpoint: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, systemImage, isConfigured, endpoint
        // apiKey intentionally excluded from persistence — stored in Keychain
    }

    init(id: String, name: String, description: String, systemImage: String,
         isConfigured: Bool, apiKey: String, endpoint: String) {
        self.id = id
        self.name = name
        self.description = description
        self.systemImage = systemImage
        self.isConfigured = isConfigured
        self.apiKey = apiKey
        self.endpoint = endpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        systemImage = try container.decode(String.self, forKey: .systemImage)
        isConfigured = try container.decode(Bool.self, forKey: .isConfigured)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        // apiKey loaded from Keychain at the call site, not from disk
        apiKey = ""
    }
}

// MARK: - MemoryProvidersView

@MainActor
struct MemoryProvidersView: View {
    @State private var providers: [MemoryProvider] = Self.defaultProviders
    @State private var configuringProvider: MemoryProvider?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
                ForEach(providers) { provider in
                    ProviderCard(provider: provider) {
                        configuringProvider = provider
                    }
                }
            }
            .padding(16)
        }
        .sheet(item: $configuringProvider) { provider in
            ProviderConfigSheet(provider: provider) { updated in
                applyUpdate(updated)
            }
        }
        .onAppear {
            loadPersistedProviders()
        }
    }

    // MARK: - Persistence

    private func loadPersistedProviders() {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.memoryProviders),
              let saved = try? JSONDecoder().decode([MemoryProvider].self, from: data) else {
            return
        }
        // Merge saved config (endpoint, isConfigured) into the hardcoded list.
        // API keys are loaded from Keychain, not from disk.
        providers = providers.map { base in
            if let match = saved.first(where: { $0.id == base.id }) {
                var updated = base
                updated.apiKey = MemoryProviderKeychain.loadAPIKey(for: base.id)
                updated.endpoint = match.endpoint
                updated.isConfigured = match.isConfigured
                return updated
            }
            return base
        }
    }

    private func persistProviders() {
        // Encode without API keys (excluded by CodingKeys)
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.memoryProviders)
        }
    }

    private func applyUpdate(_ updated: MemoryProvider) {
        if let index = providers.firstIndex(where: { $0.id == updated.id }) {
            // Persist API key to Keychain
            if updated.isConfigured {
                MemoryProviderKeychain.saveAPIKey(updated.apiKey, for: updated.id)
            } else {
                MemoryProviderKeychain.deleteAPIKey(for: updated.id)
            }
            providers[index] = updated
            persistProviders()
        }
    }

    // MARK: - Default providers

    static let defaultProviders: [MemoryProvider] = [
        MemoryProvider(
            id: "honcho",
            name: "Honcho",
            description: L10n.string("User context and personalization layer that stores preferences and facts about each user across conversations."),
            systemImage: "person.crop.circle.fill",
            isConfigured: false,
            apiKey: "",
            endpoint: "https://api.honcho.dev"
        ),
        MemoryProvider(
            id: "mem0",
            name: "Mem0",
            description: L10n.string("Intelligent memory layer for AI apps that automatically extracts and retrieves relevant memories for each user."),
            systemImage: "memorychip",
            isConfigured: false,
            apiKey: "",
            endpoint: "https://api.mem0.ai"
        ),
        MemoryProvider(
            id: "hindsight",
            name: "Hindsight",
            description: L10n.string("Retrospective memory service that learns from past interactions to improve future AI responses automatically."),
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            isConfigured: false,
            apiKey: "",
            endpoint: "https://api.hindsight.dev"
        ),
        MemoryProvider(
            id: "supermemory",
            name: "Supermemory",
            description: L10n.string("Universal memory store for AI agents that indexes and surfaces the most relevant knowledge from any source."),
            systemImage: "brain.filled.head.profile",
            isConfigured: false,
            apiKey: "",
            endpoint: "https://api.supermemory.ai"
        ),
        MemoryProvider(
            id: "byterover",
            name: "ByteRover",
            description: L10n.string("Persistent memory and context management platform designed for long-running autonomous AI agents."),
            systemImage: "server.rack",
            isConfigured: false,
            apiKey: "",
            endpoint: "https://api.byterover.com"
        )
    ]
}

// MARK: - ProviderCard

private struct ProviderCard: View {
    let provider: MemoryProvider
    let onConfigure: () -> Void

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: provider.systemImage)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.name)
                            .font(.headline)

                        if provider.isConfigured {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)

                                Text(L10n.string("Connected"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                        }
                    }

                    Spacer()
                }

                Text(provider.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                Button(L10n.string("Configure"), action: onConfigure)
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - ProviderConfigSheet

private struct ProviderConfigSheet: View {
    @State private var draft: MemoryProvider
    let onSave: (MemoryProvider) -> Void

    @Environment(\.dismiss) private var dismiss

    init(provider: MemoryProvider, onSave: @escaping (MemoryProvider) -> Void) {
        _draft = State(initialValue: provider)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: draft.systemImage)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("Configure %@", draft.name))
                        .font(.headline)

                    Text(L10n.string("Stored locally — never sent to Hermes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("API Key"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField(L10n.string("Paste your API key here"), text: $draft.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("Endpoint URL"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField(L10n.string("https://"), text: $draft.endpoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            HStack {
                if draft.isConfigured {
                    Button(L10n.string("Disconnect"), role: .destructive) {
                        draft.isConfigured = false
                        draft.apiKey = ""
                        onSave(draft)
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                Button(L10n.string("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("Save")) {
                    draft.isConfigured = !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                          draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
