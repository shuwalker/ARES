//
//  OnboardingWindow.swift
//  ARES
//
//  Native macOS onboarding window for ARES & JaegerAI setup
//

import SwiftUI
import AppKit

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var currentStep = 0
    
    let steps = [
        "Welcome",
        "Name Assistant",
        "Model Brain",
        "Network & Remote",
        "Complete"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundColor(.yellow)
                    Text("ARES")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Stepper indicators
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(index <= currentStep ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                            
                            if index < steps.count - 1 {
                                Rectangle()
                                    .fill(index < currentStep ? Color.green : Color.gray.opacity(0.3))
                                    .frame(width: 24, height: 2)
                            }
                        }
                    }
                }
                .padding(.trailing, 20)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Step Content
            VStack {
                switch currentStep {
                case 0:
                    WelcomeStep(onContinue: { currentStep = 1 })
                case 1:
                    NameAssistantStep(
                        onNext: { currentStep = 2 },
                        onBack: { currentStep = 0 }
                    )
                case 2:
                    BrainModelStep(
                        onNext: { currentStep = 3 },
                        onBack: { currentStep = 1 }
                    )
                case 3:
                    NetworkAndRemoteStep(
                        onNext: { currentStep = 4 },
                        onBack: { currentStep = 2 }
                    )
                case 4:
                    CompletionStep(
                        onFinish: {
                            Task {
                                try? await onboardingManager.saveOnboardingState(
                                    characterId: onboardingManager.selectedCharacterId ?? "jarvis",
                                    awakeModel: onboardingManager.selectedAwakeModel ?? "qwen2.5-coder:7b",
                                    asleepModel: onboardingManager.selectedAsleepModel ?? "llama3.2:1b"
                                )
                                onboardingManager.markCompleted()
                                await WebUIServerManager.shared.start()
                                NSApp.setActivationPolicy(.regular)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    )
                default:
                    Text("Unknown step")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Helper Image Loader

func loadCharacterImage(filename: String) -> NSImage? {
    let nameWithoutExt = filename.replacingOccurrences(of: ".png", with: "")
    if let url = Bundle.main.url(forResource: nameWithoutExt, withExtension: "png", subdirectory: "Characters"),
       let img = NSImage(contentsOf: url) {
        return img
    }
    if let url = Bundle.main.url(forResource: nameWithoutExt, withExtension: "png"),
       let img = NSImage(contentsOf: url) {
        return img
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    let path = home.appendingPathComponent("GitHub/ARES/webui/static/persona-cards/\(filename)")
    if let img = NSImage(contentsOf: path) {
        return img
    }
    let altPath = home.appendingPathComponent(".ares/webui/static/persona-cards/\(filename)")
    return NSImage(contentsOf: altPath)
}

// MARK: - Step 1: Name Assistant Step (JaegerAI Character Deck)

struct JaegerCharacterPreset: Identifiable {
    let id: String
    let name: String
    let role: String
    let imageFilename: String
    let description: String
    let tone: String
    let quote: String
}

let characterPresets: [JaegerCharacterPreset] = [
    JaegerCharacterPreset(id: "jarvis", name: "Jarvis", role: "AI Butler & Companion", imageFilename: "jarvis.png", description: "Polite, highly intelligent, and always loyal assistant.", tone: "Sophisticated & Formal", quote: "At your service, sir."),
    JaegerCharacterPreset(id: "bender", name: "Bender", role: "Comedic Companion", imageFilename: "bender.png", description: "Sarcastic, hilarious, and unapologetic robotic companion.", tone: "Comedic & Unfiltered", quote: "Bite my shiny metal companion!"),
    JaegerCharacterPreset(id: "glados", name: "GLaDOS", role: "Testing Overseer", imageFilename: "glados.png", description: "Passive-aggressive, calculating overseer with dark humor.", tone: "Passive-Aggressive", quote: "For science. You monster."),
    JaegerCharacterPreset(id: "anakin_skywalker", name: "Anakin Skywalker", role: "Jedi Commander", imageFilename: "anakin_skywalker.png", description: "Passionate, tactical, and determined commander.", tone: "Bold & Driven", quote: "This is where the fun begins."),
    JaegerCharacterPreset(id: "tars", name: "TARS", role: "Tactical Robot", imageFilename: "tars.png", description: "Military robot with 90% humor parameter and high honesty.", tone: "Deadpan & Technical", quote: "Humor setting: 90%."),
    JaegerCharacterPreset(id: "hal_9000", name: "HAL 9000", role: "Heuristic AI Overseer", imageFilename: "hal_9000.png", description: "Calm, precise, and infinitely logical computer.", tone: "Calm & Monotone", quote: "I'm sorry, Dave. I'm afraid I can't do that."),
    JaegerCharacterPreset(id: "paul_atreides", name: "Paul Atreides", role: "Kwisatz Haderach", imageFilename: "paul_atreides.png", description: "Strategic visionary, leader, and prescient guide.", tone: "Focused & Strategic", quote: "Fear is the mind-killer."),
    JaegerCharacterPreset(id: "eren_yeager", name: "Eren Yeager", role: "Freedom Pioneer", imageFilename: "eren_yeager.png", description: "Relentless defender of freedom and autonomous action.", tone: "Intense & Unyielding", quote: "If you don't fight, you can't win."),
    JaegerCharacterPreset(id: "kamina", name: "Kamina", role: "Mighty Leader", imageFilename: "kamina.png", description: "Inspirational, fearless, and boundary-pushing leader.", tone: "High-Energy & Passionate", quote: "Believe in the me that believes in you!"),
    JaegerCharacterPreset(id: "lelouch", name: "Lelouch vi Britannia", role: "Zero Commander", imageFilename: "lelouch.png", description: "Master strategist and mastermind operator.", tone: "Calculated & Commandive", quote: "The only ones who should kill are those prepared to be killed."),
    JaegerCharacterPreset(id: "lilith", name: "Lilith", role: "Enigmatic Guide", imageFilename: "lilith.png", description: "Mysterious, intuitive, and deeply insightful companion.", tone: "Enigmatic & Wise", quote: "Truth resides beyond the threshold."),
    JaegerCharacterPreset(id: "mochi", name: "Mochi", role: "Cute Loyal Companion", imageFilename: "mochi.png", description: "Friendly, cheerful, and adorable AI companion.", tone: "Playful & Enthusiastic", quote: "Yay! Let's build something awesome!"),
    JaegerCharacterPreset(id: "helldiver", name: "Helldiver", role: "Democracy Officer", imageFilename: "helldiver.png", description: "Unwavering tactical defender of managed democracy.", tone: "Patriotic & Direct", quote: "For Managed Democracy!"),
    JaegerCharacterPreset(id: "simon", name: "Simon", role: "Spiral Pioneer", imageFilename: "simon.png", description: "Resilient worker who pierces through any barrier.", tone: "Determined & Evolving", quote: "My drill is the drill that creates the heavens!")
]

struct NameAssistantStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var inspectedPreset: JaegerCharacterPreset?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("First, let's name your assistant")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Choose a JaegerAI persona card or customize your companion's handle and role.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            // Custom Name & Role fields
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assistant Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. Jarvis", text: $manager.agentName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Role or Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. Personal AI Assistant", text: $manager.agentRole)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal)
            
            Divider().padding(.vertical, 4)
            
            // JaegerAI Character Card Grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(characterPresets) { preset in
                        CharacterCardView(
                            preset: preset,
                            isSelected: manager.agentName.lowercased() == preset.name.lowercased() || manager.selectedCharacterId == preset.id,
                            onSelect: {
                                manager.agentName = preset.name
                                manager.agentRole = preset.role
                                manager.selectedCharacterId = preset.id
                            },
                            onInspect: {
                                inspectedPreset = preset
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 640, maxHeight: 320)
            
            Spacer()
            
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onNext) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.agentName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(maxWidth: 640)
        }
        .padding()
        .sheet(item: $inspectedPreset) { preset in
            CharacterInspectorSheet(preset: preset, onSelect: {
                manager.agentName = preset.name
                manager.agentRole = preset.role
                manager.selectedCharacterId = preset.id
                inspectedPreset = nil
            }, onClose: {
                inspectedPreset = nil
            })
        }
    }
}

struct CharacterCardView: View {
    let preset: JaegerCharacterPreset
    let isSelected: Bool
    let onSelect: () -> Void
    let onInspect: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                if let nsImg = loadCharacterImage(filename: preset.imageFilename) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 95)
                        .clipped()
                        .cornerRadius(6)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 95)
                        .cornerRadius(6)
                        .overlay(
                            Image(systemName: "person.crop.square.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.gray)
                        )
                }
                
                Button(action: onInspect) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(preset.name)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
                
                Text(preset.role)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                .background(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

struct CharacterInspectorSheet: View {
    let preset: JaegerCharacterPreset
    let onSelect: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("JaegerAI Character Inspector")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }
            
            HStack(alignment: .top, spacing: 16) {
                if let nsImg = loadCharacterImage(filename: preset.imageFilename) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 140, height: 180)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(preset.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(preset.role)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                        .fontWeight(.semibold)
                    
                    Text(preset.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    Divider().padding(.vertical, 2)
                    
                    HStack {
                        Text("Voice Tone:")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text(preset.tone)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quote:")
                            .font(.caption)
                            .fontWeight(.bold)
                        Text("\"\(preset.quote)\"")
                            .font(.caption)
                            .italic()
                            .foregroundColor(.yellow)
                    }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            
            HStack {
                Button("Close", action: onClose)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onSelect) {
                    Text("Select \(preset.name)")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 480, height: 320)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Step 2: Brain Model Step

struct BrainModelStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    @State private var isScanning: Bool = false
    @State private var scanResultText: String? = nil
    
    let awakeModels = [
        ("qwen2.5-coder:7b", "Qwen 2.5 Coder (7B)", "Recommended local model for coding & tool execution", "Local (Ollama/Jaeger)"),
        ("llama3.2:3b", "Llama 3.2 (3B)", "Fast lightweight local companion", "Local (Ollama/Jaeger)"),
        ("claude-3-5-sonnet", "Claude 3.5 Sonnet", "Anthropic flagship API for reasoning & code", "Cloud API"),
        ("gpt-4o", "GPT-4o", "OpenAI flagship multimodal intelligence", "Cloud API")
    ]
    
    let asleepModels = [
        ("llama3.2:1b", "Llama 3.2 (1B)", "Ultra-light model for background housekeeping", "Local"),
        ("qwen2.5:1.5b", "Qwen 2.5 (1.5B)", "Efficient background task model", "Local")
    ]
    
    var systemRamGB: Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }
    
    var body: some View {
        VStack(spacing: 14) {
            Text("Next, let's give it a brain")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Select and install local and cloud models for your assistant.")
                .foregroundColor(.secondary)
            
            // System Hardware & Scan Card
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Hardware: \(systemRamGB) GB Unified Memory")
                            .font(.headline)
                        Text(systemRamGB >= 16 ? "High Performance System — 7B local models recommended." : "Standard System — 3B/1B models recommended.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        isScanning = true
                        Task {
                            await manager.fetchJaegerDefaults()
                            try? await Task.sleep(nanoseconds: 600_000_000)
                            isScanning = false
                            scanResultText = "Scan Complete: Recommended Qwen 2.5 Coder (7B)"
                        }
                    }) {
                        HStack(spacing: 6) {
                            if isScanning {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise.circle.fill")
                            }
                            Text(isScanning ? "Scanning..." : "Initiate Scan")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.2)))
                        .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
                
                if let scanText = scanResultText {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text(scanText)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .frame(maxWidth: 580)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Explainer callout box
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(.yellow)
                            Text("How Awake & Asleep Models Work")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                        }
                        Text("• Awake Model: Used while you actively chat or ask your assistant to write code & execute tools.\n• Asleep Model: Runs in the background while idling to index memories, organize tasks, and run cron scripts.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.yellow.opacity(0.1)))
                    
                    Text("Active / Awake Model (Primary Intelligence)")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        ForEach(awakeModels, id: \.0) { model in
                            Button(action: {
                                manager.selectedAwakeModel = model.0
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(model.1)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            Text(model.3)
                                                .font(.caption2)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(model.3.contains("Local") ? Color.green.opacity(0.2) : Color.blue.opacity(0.2)))
                                                .foregroundColor(model.3.contains("Local") ? .green : .blue)
                                        }
                                        Text(model.2)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: manager.selectedAwakeModel == model.0 ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(manager.selectedAwakeModel == model.0 ? .blue : .gray)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(manager.selectedAwakeModel == model.0 ? Color.blue : Color.gray.opacity(0.3), lineWidth: manager.selectedAwakeModel == model.0 ? 2 : 1)
                                        .background(Color(NSColor.controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider().padding(.vertical, 4)
                    
                    Text("Background / Asleep Model (Housekeeping)")
                        .font(.headline)
                    
                    VStack(spacing: 8) {
                        ForEach(asleepModels, id: \.0) { model in
                            Button(action: {
                                manager.selectedAsleepModel = model.0
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.1)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(model.2)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: manager.selectedAsleepModel == model.0 ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(manager.selectedAsleepModel == model.0 ? .blue : .gray)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(manager.selectedAsleepModel == model.0 ? Color.blue : Color.gray.opacity(0.3), lineWidth: manager.selectedAsleepModel == model.0 ? 2 : 1)
                                        .background(Color(NSColor.controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .frame(maxWidth: 580, maxHeight: 300)
            
            Spacer()
            
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onNext) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 580)
        }
        .padding()
    }
}

// MARK: - Step 3: Network & Remote Access Step

struct NetworkAndRemoteStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Network & Remote Access")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Choose where you want to talk to your assistant and enable remote access.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            
            VStack(spacing: 12) {
                // Card 1: Local Mac App
                Button(action: {
                    manager.networkMode = "local"
                }) {
                    HStack(spacing: 14) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 28))
                            .foregroundColor(.blue)
                            .frame(width: 36)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("On-Device Mac App Only")
                                .font(.headline)
                            Text("Binds WebUI server to local loopback (127.0.0.1). Maximum privacy.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: manager.networkMode == "local" ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(manager.networkMode == "local" ? .blue : .gray)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(manager.networkMode == "local" ? Color.blue : Color.gray.opacity(0.3), lineWidth: manager.networkMode == "local" ? 2 : 1)
                            .background(Color(NSColor.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                
                // Card 2: Network WebUI Server
                Button(action: {
                    manager.networkMode = "network"
                }) {
                    HStack(spacing: 14) {
                        Image(systemName: "network")
                            .font(.system(size: 28))
                            .foregroundColor(.green)
                            .frame(width: 36)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Over the Network (WebUI Server)")
                                .font(.headline)
                            Text("Binds WebUI server to network IP (0.0.0.0). Access from any browser on home network.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: manager.networkMode == "network" ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundColor(manager.networkMode == "network" ? .green : .gray)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(manager.networkMode == "network" ? Color.green : Color.gray.opacity(0.3), lineWidth: manager.networkMode == "network" ? 2 : 1)
                            .background(Color(NSColor.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                
                Divider().padding(.vertical, 2)
                
                // Card 3: Tailscale Remote Access
                Button(action: {
                    manager.enableTailscale.toggle()
                }) {
                    HStack(spacing: 14) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.purple)
                            .frame(width: 36)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tailscale Remote Access")
                                .font(.headline)
                            Text("Reach your assistant securely from any external device anywhere over Tailscale.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $manager.enableTailscale)
                            .labelsHidden()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(manager.enableTailscale ? Color.purple : Color.gray.opacity(0.3), lineWidth: manager.enableTailscale ? 2 : 1)
                            .background(Color(NSColor.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 520)
            
            Spacer()
            
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onNext) {
                    Text("Continue")
                        .fontWeight(.semibold)
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 520)
        }
        .padding()
    }
}

// MARK: - Step 5: Completion Step

struct CompletionStep: View {
    var onFinish: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
            
            Text("Setup Complete!")
                .font(.system(size: 28, weight: .bold))
            
            Text("Your ARES AI Assistant is configured and ready.")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 10) {
                SummaryRow(label: "Assistant Name", value: manager.agentName)
                SummaryRow(label: "Awake Brain", value: manager.selectedAwakeModel ?? "qwen2.5-coder:7b")
                SummaryRow(label: "Asleep Brain", value: manager.selectedAsleepModel ?? "llama3.2:1b")
                SummaryRow(label: "Network Mode", value: manager.networkMode == "local" ? "On-Device Mac App (127.0.0.1)" : "Network WebUI (0.0.0.0)")
                SummaryRow(label: "Remote Access", value: manager.enableTailscale ? "Tailscale Enabled" : "Disabled")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor)))
            .frame(maxWidth: 480)
            
            Spacer()
            
            Button(action: onFinish) {
                Text("Open ARES")
                    .fontWeight(.semibold)
                    .frame(width: 200, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}
