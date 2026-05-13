import SwiftUI

// Memory Inspector — reveals what ARES remembers so the "persistent agent"
// promise is verifiable. Pulls from /api/memory/episodics and /api/memory/recall.

struct MemoryInspectorView: View {
    @EnvironmentObject var brain: BrainConnection
    @State private var episodics: [EpisodicRow] = []
    @State private var query: String = ""
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))
            searchBar
            Divider().background(.white.opacity(0.08))
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial)
        .task { await refresh() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
            Text("Memory")
                .font(.title3.weight(.semibold))
            Spacer()
            if loading {
                ProgressView().controlSize(.small)
            }
            Text("\(episodics.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.white.opacity(0.08)))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("recall…", text: $query)
                .textFieldStyle(.plain)
                .onSubmit { Task { await runRecall() } }
            if !query.isEmpty {
                Button {
                    query = ""
                    Task { await refresh() }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if let errorText {
                    Text(errorText).font(.caption).foregroundStyle(.red).padding(.horizontal, 14)
                }
                ForEach(episodics) { row in
                    EpisodicCard(row: row, onDelete: {
                        Task { await delete(row) }
                    })
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Network

    private func refresh() async {
        loading = true
        defer { loading = false }
        guard let url = URL(string: "http://localhost:7860/api/memory/episodics?limit=100") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(EpisodicList.self, from: data)
            await MainActor.run { episodics = decoded.items }
        } catch {
            await MainActor.run { errorText = "list failed: \(error.localizedDescription)" }
        }
    }

    private func runRecall() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { await refresh(); return }
        loading = true
        defer { loading = false }
        guard let url = URL(string: "http://localhost:7860/api/memory/recall") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": q, "k": 20])
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(RecallResult.self, from: data)
            await MainActor.run {
                episodics = decoded.hits.map {
                    EpisodicRow(id: $0.id, text: $0.text, metadata: [:], createdAt: 0, score: $0.score)
                }
            }
        } catch {
            await MainActor.run { errorText = "recall failed: \(error.localizedDescription)" }
        }
    }

    private func delete(_ row: EpisodicRow) async {
        guard let url = URL(string: "http://localhost:7860/api/memory/episodics/\(row.id)") else { return }
        var req = URLRequest(url: url); req.httpMethod = "DELETE"
        _ = try? await URLSession.shared.data(for: req)
        await refresh()
    }
}

private struct EpisodicCard: View {
    let row: EpisodicRow
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.timestampLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let score = row.score {
                    Text(String(format: "sim %.2f", score))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.cyan.opacity(0.8))
                }
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary.opacity(0.6))
            }
            Text(row.text)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
        )
        .padding(.horizontal, 14)
    }
}

// MARK: - DTOs

struct EpisodicRow: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let metadata: [String: AnyCodableNull]
    let createdAt: Double
    var score: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, text, metadata, score
        case createdAt = "created_at"
    }

    var timestampLabel: String {
        guard createdAt > 0 else { return "" }
        let date = Date(timeIntervalSince1970: createdAt)
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }
}

struct EpisodicList: Codable {
    let items: [EpisodicRow]
    let count: Int
}

struct RecallResult: Codable {
    let hits: [MemoryHitBlock]
}

// Skinny "anything-or-null" decoder so the metadata dict doesn't choke
// on mixed-type values. We don't render metadata in v1 anyway.
struct AnyCodableNull: Codable, Equatable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer().decodeNil()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encodeNil()
    }
}
