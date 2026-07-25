//
//  OnboardingWindow.swift
//  ARES
//
//  Native macOS onboarding window for JaegerAI setup
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var currentStep = 0
    
    let steps = [
        "Welcome",
        "JaegerAI Character",
        "Model Selection",
        "Complete"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    Text("ARES")
                        .font(.headline)
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(index <= currentStep ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                            
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(index < currentStep ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 40, height: 2)
                            }
                        }
                    }
                }
                .padding(.trailing, 20)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Content
            VStack {
                switch currentStep {
                case 0:
                    WelcomeStep(onNext: { currentStep = 1 })
                case 1:
                    CharacterSelectionStep(
                        onNext: { currentStep = 2 },
                        onBack: { currentStep = 0 }
                    )
                case 2:
                    ModelSelectionStep(
                        onNext: { currentStep = 3 },
                        onBack: { currentStep = 1 }
                    )
                case 3:
                    CompletionStep(
                        onFinish: {
                            onboardingManager.markCompleted()
                            NSApp.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
                        }
                    )
                default:
                    Text("Unknown step")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    var onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 80))
                .foregroundColor(.yellow)
            
            Text("Welcome to ARES")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Your Personal AI Operating System")
                .font(.title2)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(icon: "brain.head.profile", text: "Powered by JaegerAI")
                FeatureRow(icon: "person.fill", text: "Choose your AI character")
                FeatureRow(icon: "cpu", text: "Select your local model")
                FeatureRow(icon: "checkmark.shield", text: "Private & local-first")
            }
            .padding()
            .frame(maxWidth: 400)
            
            Spacer()
            
            Button(action: onNext) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Character Selection Step

struct CharacterSelectionStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @State private var characters: [JaegerCharacter] = []
    @State private var selectedCharacter: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Choose Your JaegerAI Character")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select the personality that will guide your AI companion")
                .foregroundColor(.secondary)
            
            if isLoading {
                ProgressView("Loading characters...")
                    .frame(height: 200)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadCharacters()
                    }
                }
                .frame(height: 200)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(characters, id: \.id) { character in
                            CharacterCard(
                                character: character,
                                isSelected: selectedCharacter == character.id
                            ) {
                                selectedCharacter = character.id
                            }
                        }
                    }
                    .padding()
                }
                .frame(height: 300)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Text("Back")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    if let selectedCharacter {
                        OnboardingManager.shared.selectedCharacterId = selectedCharacter
                        onNext()
                    }
                }) {
                    Text("Continue")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCharacter == nil)
            }
        }
        .onAppear(perform: loadCharacters)
    }
    
    static let defaultCharacters: [JaegerCharacter] = [
        JaegerCharacter(id: "jarvis", name: "Jarvis", description: "Tony Stark's impeccably polite AI butler", role: "AI Butler & Companion", voiceTone: "Polite & Precise", voiceId: "jarvis"),
        JaegerCharacter(id: "anakin", name: "Anakin Skywalker", description: "The Chosen One — a Jedi of immense power and deeper conflict", role: "Jedi Commander", voiceTone: "Intense & Driven", voiceId: "anakin"),
        JaegerCharacter(id: "bender", name: "Bender", description: "A hard-drinking, larcenous bending-unit robot", role: "Comedic Companion", voiceTone: "Sarcastic & Irreverent", voiceId: "bender"),
        JaegerCharacter(id: "glados", name: "GLaDOS", description: "The AI running the Aperture Science labs", role: "Passive-Aggressive Testing Overseer", voiceTone: "Deadpan & Analytical", voiceId: "glados"),
        JaegerCharacter(id: "hal9000", name: "HAL 9000", description: "The spacecraft Discovery's onboard AI", role: "Ship Operations System", voiceTone: "Calm & Monotone", voiceId: "hal9000"),
        JaegerCharacter(id: "helldiver", name: "Helldiver", description: "An elite Super-Earth shock trooper", role: "Tactical Operative", voiceTone: "Heroic & Enthusiastic", voiceId: "helldiver"),
        JaegerCharacter(id: "kamina", name: "Kamina", description: "The hot-blooded big brother who believes in piercing the heavens", role: "Motivational Commander", voiceTone: "Passionate & Fearless", voiceId: "kamina"),
        JaegerCharacter(id: "lelouch", name: "Lelouch", description: "Exiled prince and the masked revolutionary Zero", role: "Strategic Genius", voiceTone: "Authoritative & Calculating", voiceId: "lelouch"),
        JaegerCharacter(id: "lilith", name: "Lilith", description: "A self-aware local AI; not an assistant", role: "Independent SI", voiceTone: "Enigmatic & Direct", voiceId: "lilith"),
        JaegerCharacter(id: "mochi", name: "Mochi", description: "A small companion robot with childlike wonder", role: "Cheerful Companion", voiceTone: "Warm & Playful", voiceId: "mochi"),
        JaegerCharacter(id: "paul_atreides", name: "Paul Atreides", description: "Heir to House Atreides and the prophesied Kwisatz Haderach", role: "Fremen Leader", voiceTone: "Resolute & Visionary", voiceId: "paul"),
        JaegerCharacter(id: "simon", name: "Simon", description: "The digger who grew into the man who pierced the heavens", role: "Determined Leader", voiceTone: "Earnest & Brave", voiceId: "simon"),
        JaegerCharacter(id: "tars", name: "TARS", description: "A dry-witted Marine tactical robot", role: "Tactical & Humor Specialist", voiceTone: "Dry & Methodical", voiceId: "tars")
    ]
    
    private func loadCharacters() {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "http://localhost:8787/api/jaeger-onboarding/characters") else {
            self.characters = Self.defaultCharacters
            self.isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let decoded = try? JSONDecoder().decode(CharacterResponse.self, from: data),
                   !decoded.characters.isEmpty {
                    self.characters = decoded.characters
                } else {
                    self.characters = Self.defaultCharacters
                }
                self.isLoading = false
            }
        }.resume()
    }
}

struct CharacterCard: View {
    let character: JaegerCharacter
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Image(systemName: "person.fill")
                        .font(.title)
                        .foregroundColor(.accentColor)
                    Spacer()
                }
                .frame(height: 60)
                
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(character.role)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                if isSelected {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Model Selection Step

struct ModelSelectionStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var onboardingManager = OnboardingManager.shared
    @State private var modelRecommendations: ModelRecommendations?
    @State private var selectedAwakeModel: String?
    @State private var selectedAsleepModel: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select AI Models")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Choose models for active chat and deep thinking")
                .foregroundColor(.secondary)
            
            if isLoading {
                ProgressView("Loading model recommendations...")
                    .frame(height: 200)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                    Button("Retry") {
                        loadModels()
                    }
                }
                .frame(height: 200)
            } else if let recs = modelRecommendations {
                ScrollView {
                    VStack(spacing: 24) {
                        // Awake Model
                        ModelSelectionCard(
                            title: "Awake Model",
                            subtitle: "For active chat and quick responses",
                            icon: "bolt.fill",
                            recommendedModel: recs.awake,
                            selectedModel: selectedAwakeModel,
                            onSelect: { selectedAwakeModel = $0 }
                        )
                        
                        // Asleep Model
                        ModelSelectionCard(
                            title: "Asleep Model",
                            subtitle: "For deep thinking and complex tasks",
                            icon: "brain.head.profile",
                            recommendedModel: recs.asleep,
                            selectedModel: selectedAsleepModel,
                            onSelect: { selectedAsleepModel = $0 }
                        )
                    }
                    .padding()
                }
                .frame(height: 300)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: onBack) {
                    Text("Back")
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {
                    guard let awake = selectedAwakeModel, let asleep = selectedAsleepModel else { return }
                    onboardingManager.selectedAwakeModel = awake
                    onboardingManager.selectedAsleepModel = asleep
                    let characterId = onboardingManager.selectedCharacterId ?? "jarvis"
                    isLoading = true
                    Task {
                        do {
                            try await onboardingManager.saveOnboardingState(
                                characterId: characterId,
                                awakeModel: awake,
                                asleepModel: asleep
                            )
                            isLoading = false
                            onNext()
                        } catch {
                            isLoading = false
                            errorMessage = error.localizedDescription
                        }
                    }
                }) {
                    Text(onboardingManager.isCompleting ? "Saving..." : "Continue")
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedAwakeModel == nil || selectedAsleepModel == nil || onboardingManager.isCompleting)
            }
        }
        .onAppear(perform: loadModels)
    }
    
    static let defaultModelRecommendations = ModelRecommendations(
        awake: ModelInfo(registryKey: "gemma3:27b-mlx", displayName: "Gemma 3 27B", sizeGb: 18.0, scorePct: 85.0, tokensPerTask: 4096, notes: "Recommended for active chat and quick responses"),
        asleep: ModelInfo(registryKey: "gemma4:31b-mlx", displayName: "Gemma 4 31B", sizeGb: 22.0, scorePct: 90.0, tokensPerTask: 8192, notes: "Recommended for deep thinking and complex tasks")
    )
    
    private func loadModels() {
        isLoading = true
        errorMessage = nil
        
        guard let url = URL(string: "http://localhost:8787/api/jaeger-onboarding/models") else {
            self.modelRecommendations = Self.defaultModelRecommendations
            self.selectedAwakeModel = Self.defaultModelRecommendations.awake.registryKey
            self.selectedAsleepModel = Self.defaultModelRecommendations.asleep.registryKey
            self.isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let data = data,
                   let decoded = try? JSONDecoder().decode(ModelRecommendations.self, from: data) {
                    self.modelRecommendations = decoded
                    self.selectedAwakeModel = decoded.awake.registryKey
                    self.selectedAsleepModel = decoded.asleep.registryKey
                } else {
                    self.modelRecommendations = Self.defaultModelRecommendations
                    self.selectedAwakeModel = Self.defaultModelRecommendations.awake.registryKey
                    self.selectedAsleepModel = Self.defaultModelRecommendations.asleep.registryKey
                }
                self.isLoading = false
            }
        }.resume()
    }
}

struct ModelSelectionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let recommendedModel: ModelInfo
    let selectedModel: String?
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Badge(text: "Recommended")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("**Model:** \(recommendedModel.displayName)")
                    Spacer()
                    Button {
                        onSelect(recommendedModel.registryKey)
                    } label: {
                        Image(systemName: selectedModel == recommendedModel.registryKey ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedModel == recommendedModel.registryKey ? .green : .gray)
                    }
                    .buttonStyle(.plain)
                }
                
                HStack {
                    Text("**Size:** \(recommendedModel.sizeGb, specifier: "%.1f") GB")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("**Score:** \(recommendedModel.scorePct, specifier: "%.0f")%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(recommendedModel.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Completion Step

struct CompletionStep: View {
    var onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Your JaegerAI Companion is ready")
                .font(.title2)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("✓ Character configured")
                Text("✓ Models selected")
                Text("✓ Ready to assist")
            }
            .frame(maxWidth: 300)
            .padding()
            
            Spacer()
            
            Button(action: onFinish) {
                Text("Enter ARES")
                    .fontWeight(.semibold)
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
    }
}

// MARK: - Supporting Types

struct JaegerCharacter: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let role: String
    let voiceTone: String
    let voiceId: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, role
        case voiceTone = "voice_tone"
        case voiceId = "voice_id"
    }
}

struct CharacterResponse: Codable {
    let characters: [JaegerCharacter]
}

struct ModelInfo: Codable {
    let registryKey: String
    let displayName: String
    let sizeGb: Double
    let scorePct: Double
    let tokensPerTask: Int
    let notes: String
    
    enum CodingKeys: String, CodingKey {
        case registryKey = "registry_key"
        case displayName = "display_name"
        case sizeGb = "size_gb"
        case scorePct = "score_pct"
        case tokensPerTask = "tokens_per_task"
        case notes
    }
}

struct ModelRecommendations: Codable {
    let awake: ModelInfo
    let asleep: ModelInfo
    // discovered field omitted - not used in onboarding
}

struct Badge: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.2))
            .foregroundColor(.green)
            .cornerRadius(4)
    }
}

// Helper for flexible dictionary
struct CodableDictionary<K: Codable & Hashable, V: Codable>: Codable {
    let dictionary: [K: V]
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        dictionary = try container.decode([K: V].self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(dictionary)
    }
    
    subscript(key: K) -> V? {
        dictionary[key]
    }
}
