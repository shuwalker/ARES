//
//  OnboardingWindow.swift
//  ARES
//
//  Native macOS onboarding window for ARES & JaegerAI setup
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var currentStep = 0
    
    let steps = [
        "Welcome",
        "Name Assistant",
        "Model Brain",
        "Network",
        "Tailscale",
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
                    WelcomeStep(onNext: { currentStep = 1 })
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
                    NetworkAccessStep(
                        onNext: { currentStep = 4 },
                        onBack: { currentStep = 2 }
                    )
                case 4:
                    TailscaleStep(
                        onNext: { currentStep = 5 },
                        onBack: { currentStep = 3 }
                    )
                case 5:
                    CompletionStep(
                        onFinish: {
                            Task {
                                try? await onboardingManager.saveOnboardingState(
                                    characterId: onboardingManager.selectedCharacterId ?? "jarvis",
                                    awakeModel: onboardingManager.selectedAwakeModel ?? "qwen2.5-coder:7b",
                                    asleepModel: onboardingManager.selectedAsleepModel ?? "llama3.2:1b"
                                )
                                onboardingManager.markCompleted()
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

// MARK: - Step 0: Welcome Step

struct WelcomeStep: View {
    var onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 72))
                .foregroundColor(.yellow)
            
            Text("Welcome to ARES")
                .font(.system(size: 28, weight: .bold))
            
            VStack(spacing: 12) {
                Text("ARES is the interface to your AI assistant. Jaeger AI can give a local LLM the tools needed to help across your devices.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: 520)
            }
            
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "brain.head.profile", title: "Local Tools & Automation", subtitle: "Grant your AI assistant tools to run terminal commands, view screens, and automate apps.")
                FeatureRow(icon: "cpu", title: "Local & Cloud LLMs", subtitle: "Connect Jaeger AI, Ollama, or cloud providers like OpenAI, Claude, and Gemini.")
                FeatureRow(icon: "shield.checkmark.fill", title: "Private & Local-First", titleColor: .green, subtitle: "Your data stays on your machine with optional local-only loopback.")
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))
            .frame(maxWidth: 560)
            
            Spacer()
            
            Button(action: onNext) {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .frame(width: 220, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    var titleColor: Color = .primary
    let subtitle: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(titleColor)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Step 1: Name Assistant Step

struct NameAssistantStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    
    let presets = [
        ("Jarvis", "AI Butler & Companion"),
        ("Bender", "Comedic Companion"),
        ("GLaDOS", "Testing Overseer"),
        ("Anakin", "Jedi Commander"),
        ("Friday", "Tactical Assistant"),
        ("Cortana", "Cybernetic Scout")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("First, let's name your assistant")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Give your AI companion a custom handle and role.")
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assistant Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. Jarvis", text: $manager.agentName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Role or Title")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("e.g. Personal AI Assistant", text: $manager.agentRole)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or choose a preset personality:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(presets, id: \.0) { preset in
                            Button(action: {
                                manager.agentName = preset.0
                                manager.agentRole = preset.1
                                manager.selectedCharacterId = preset.0.lowercased()
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(preset.0)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        Text(preset.1)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if manager.agentName == preset.0 {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.blue)
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(manager.agentName == preset.0 ? Color.blue : Color.gray.opacity(0.3), lineWidth: manager.agentName == preset.0 ? 2 : 1)
                                        .background(Color(NSColor.controlBackgroundColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 520)
            .padding()
            
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
            .frame(maxWidth: 520)
        }
        .padding()
    }
}

// MARK: - Step 2: Brain Model Step

struct BrainModelStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    
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
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Next, let's give it a brain")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Select and install local and cloud models for your assistant.")
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
            .frame(maxWidth: 540)
            
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
            .frame(maxWidth: 540)
        }
        .padding()
    }
}

// MARK: - Step 3: Network Access Step

struct NetworkAccessStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Where do you want to talk to your assistant?")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Do you want to only talk in the Mac app on device, or would you like to talk to it over the network?")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            
            VStack(spacing: 14) {
                // Card 1: Local Mac App
                Button(action: {
                    manager.networkMode = "local"
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 32))
                            .foregroundColor(.blue)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("On-Device Mac App Only")
                                .font(.headline)
                            Text("Binds WebUI server to local loopback (127.0.0.1). Maximum privacy; accessible only on this Mac.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: manager.networkMode == "local" ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(manager.networkMode == "local" ? .blue : .gray)
                    }
                    .padding(16)
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
                    HStack(spacing: 16) {
                        Image(systemName: "network")
                            .font(.system(size: 32))
                            .foregroundColor(.green)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Over the Network (WebUI Server)")
                                .font(.headline)
                            Text("Binds WebUI server to network IP (0.0.0.0). Access your assistant from any browser on your home network.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: manager.networkMode == "network" ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundColor(manager.networkMode == "network" ? .green : .gray)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(manager.networkMode == "network" ? Color.green : Color.gray.opacity(0.3), lineWidth: manager.networkMode == "network" ? 2 : 1)
                            .background(Color(NSColor.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                
                Toggle("Auto-launch WebUI server when ARES opens", isOn: $manager.autoLaunchWebUI)
                    .font(.subheadline)
                    .padding(.top, 8)
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

// MARK: - Step 4: Tailscale Step

struct TailscaleStep: View {
    var onNext: () -> Void
    var onBack: () -> Void
    
    @ObservedObject private var manager = OnboardingManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Reach your assistant anywhere")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Do you want to reach this on external devices anywhere?")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                Button(action: {
                    manager.enableTailscale.toggle()
                }) {
                    HStack(spacing: 16) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.purple)
                            .frame(width: 44)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Tailscale Remote Access")
                                .font(.headline)
                            Text("Connect securely to your assistant over a private Tailscale mesh network from any phone, laptop, or browser worldwide.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $manager.enableTailscale)
                            .labelsHidden()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(manager.enableTailscale ? Color.purple : Color.gray.opacity(0.3), lineWidth: manager.enableTailscale ? 2 : 1)
                            .background(Color(NSColor.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                
                if manager.enableTailscale {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.purple)
                        Text("Tailscale integration will expose your WebUI to your authenticated Tailnet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.1)))
                }
            }
            .frame(maxWidth: 520)
            
            Spacer()
            
            HStack {
                Button("Back", action: onBack)
                    .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: onNext) {
                    Text("Complete Setup")
                        .fontWeight(.semibold)
                        .frame(width: 140)
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
