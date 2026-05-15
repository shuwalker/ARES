import SwiftUI

/// Lilith 4-layer personality editor. Reads/writes /api/personality.
/// Layers: HEXACO, SPECIAL, Expression, Domains.
/// Each trait is 0.0-1.0. Neutral band (0.40-0.60) = no prompt effect.
struct PersonaSlidersView: View {
    @EnvironmentObject var brain: BrainConnection
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let personality = brain.personality {
                    LayerSection(title: "HEXACO", traits: personality.hexaco)
                    LayerSection(title: "SPECIAL", traits: personality.special)
                    LayerSection(title: "Expression", traits: personality.expression)
                    LayerSection(title: "Domains", traits: personality.domains)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading personality...")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .onAppear {
            Task {
                await brain.refreshPersonality()
            }
        }
    }
}

struct LayerSection: View {
    let title: String
    let traits: [String: Double]
    
    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(traits.keys.sorted()), id: \.self) { key in
                    TraitSlider(layer: title.lowercased(), trait: key, value: traits[key] ?? 0.5)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct TraitSlider: View {
    let layer: String
    let trait: String
    @State var value: Double
    @State private var debounceTask: Task<Void, Never>?
    
    private let neutralLow = 0.40
    private let neutralHigh = 0.60
    
    var isNeutral: Bool { value >= neutralLow && value <= neutralHigh }
    
    var label: String {
        switch value {
        case ..<0.2: return "very low"
        case ..<0.4: return "low"
        case ..<0.6: return "neutral"
        case ..<0.8: return "high"
        default: return "very high"
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(trait.capitalized)
                    .font(.caption.weight(.medium))
                    .frame(width: 120, alignment: .leading)
                Slider(value: $value, in: 0...1, step: 0.05)
                    .onChange(of: value) { _, newValue in
                        debounceTask?.cancel()
                        debounceTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000)
                            guard !Task.isCancelled else { return }
                            try? await HermesAdapter().setPersonality(layer: layer, trait: trait, value: newValue)
                        }
                    }
                Text("\(value, specifier: "%.2f")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isNeutral ? Color.secondary : Color.teal)
                    .frame(width: 60, alignment: .trailing)
            }
        }
    }
}