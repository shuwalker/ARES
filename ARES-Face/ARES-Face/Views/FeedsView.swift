import SwiftUI

/// Adaptable feed dashboard — user-configurable data streams.
///
/// NOT a JR-specific dashboard. This is a generic feed framework.
/// The user adds adapters (stocks, social, sensors, GitHub, whatever).
/// We build the infrastructure; the user decides what flows through it.
struct FeedsView: View {
    @EnvironmentObject var feeds: FeedStore
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(.white.opacity(0.08))

            if feeds.cards.isEmpty && feeds.adapters.isEmpty {
                onboarding
            } else {
                cardGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .task { await feeds.refreshAll() }
        .sheet(isPresented: $showingAddSheet) {
            AddFeedSheet()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
            Text("Feeds")
                .font(.title3.weight(.semibold))
            Spacer()
            if feeds.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
            }
            // Layout toggle
            Picker("", selection: $feeds.layout) {
                ForEach(FeedLayout.allCases, id: \.self) { layout in
                    Image(systemName: layout == .grid ? "square.grid.2x2" : "list.bullet")
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Card Grid

    private var cardGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if feeds.layout == .grid {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ], spacing: 10) {
                    ForEach(feeds.cards) { card in
                        FeedCardView(card: card)
                    }
                    // Adapter management cards
                    ForEach(feeds.adapters) { adapter in
                        AdapterCard(adapter: adapter)
                    }
                }
                .padding(14)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(feeds.cards) { card in
                        FeedCardRow(card: card)
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Onboarding

    private var onboarding: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No feeds configured")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Add data sources like stock prices, sensor readings, social mentions, or build status. ARES shows you what matters.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            Button("Add Feed") {
                showingAddSheet = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Feed Card (Grid)

private struct FeedCardView: View {
    let card: FeedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
                .foregroundStyle(.secondary)

            switch card.style {
            case .number:
                Text(card.value)
                    .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
            case .status:
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(card.value))
                        .frame(width: 8, height: 8)
                    Text(card.value)
                        .font(.system(size: 14, weight: .medium))
                }
            case .list:
                Text(card.value)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(3)
            case .sparkline, .chart:
                Text(card.value)
                    .font(.system(size: 14, weight: .medium))
            }

            Text(card.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func statusColor(_ value: String) -> Color {
        let lower = value.lowercased()
        if lower.contains("ok") || lower.contains("online") || lower.contains("healthy") { return .green }
        if lower.contains("warn") || lower.contains("degraded") { return .yellow }
        if lower.contains("error") || lower.contains("down") || lower.contains("offline") { return .red }
        return .cyan
    }
}

// MARK: - Feed Card (List)

private struct FeedCardRow: View {
    let card: FeedCard

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.cyan.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "chart.bar")
                        .font(.system(size: 12))
                        .foregroundStyle(.cyan)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.system(size: 12, weight: .medium))
                Text(card.value)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(card.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

// MARK: - Adapter Card

private struct AdapterCard: View {
    let adapter: FeedAdapterConfig
    @EnvironmentObject var feeds: FeedStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(adapter.name)
                    .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(adapter.isEnabled ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)
            }
            Text(adapter.type.rawValue)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
            if let endpoint = adapter.endpoint {
                Text(endpoint)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(adapter.isEnabled ? 0.06 : 0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 0.5)
        )
        .onTapGesture {
            feeds.toggleAdapter(id: adapter.id)
        }
    }
}

// MARK: - Add Feed Sheet

struct AddFeedSheet: View {
    @EnvironmentObject var feeds: FeedStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = FeedAdapterConfig.AdapterType.httpJson
    @State private var endpoint = ""
    @State private var jsonPath = ""
    @State private var refreshInterval = 300.0
    @State private var cardStyle = FeedCard.CardStyle.number

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Feed Source")
                .font(.headline)

            // Name
            LabeledContent("Name") {
                TextField("My Feed", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }

            // Type
            LabeledContent("Type") {
                Picker("", selection: $type) {
                    ForEach(FeedAdapterConfig.AdapterType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .frame(width: 220)
            }

            // Endpoint
            if type != .hermesStatus {
                LabeledContent("URL") {
                    TextField("https://api.example.com/data", text: $endpoint)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                LabeledContent("JSON Path") {
                    TextField("data.value", text: $jsonPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }

            // Refresh interval
            LabeledContent("Refresh") {
                Picker("", selection: $refreshInterval) {
                    Text("30s").tag(30.0)
                    Text("1m").tag(60.0)
                    Text("5m").tag(300.0)
                    Text("15m").tag(900.0)
                    Text("1h").tag(3600.0)
                }
                .frame(width: 120)
            }

            // Card style
            LabeledContent("Display") {
                Picker("", selection: $cardStyle) {
                    ForEach(FeedCard.CardStyle.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s)
                    }
                }
                .frame(width: 120)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Add") {
                    let config = FeedAdapterConfig(
                        id: UUID().uuidString,
                        name: name.isEmpty ? type.rawValue : name,
                        type: type,
                        endpoint: endpoint.isEmpty ? nil : endpoint,
                        jsonPath: jsonPath.isEmpty ? nil : jsonPath,
                        refreshIntervalSeconds: refreshInterval,
                        isEnabled: true,
                        cardStyle: cardStyle
                    )
                    feeds.addAdapter(config)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty && type == .httpJson && endpoint.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}