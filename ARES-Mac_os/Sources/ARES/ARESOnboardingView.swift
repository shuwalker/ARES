//
//  ARESOnboardingView.swift
//  ARES
//
//  Native macOS onboarding — detects JaegerAI, marks others Pending
//

import SwiftUI
import ARESCore

struct ARESOnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var jaegerDetected = false
    @State private var jaegerPath: String = ""
    @State private var isCompleting = false
    @State private var error: String?
    let onComplete: () -> Void
    
    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case detect
        case configure
        case complete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.primary)
                Text("ARES Setup")
                    .font(.headline)
                Spacer()
                if step != .welcome {
                    Button(action: { exit(0) }) {
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
            
            // Content
            VStack(spacing: 32) {
                switch step {
                case .welcome:
                    WelcomeStep(onContinue: { step = .detect })
                    
                case .detect:
                    DetectionStep(
                        jaegerDetected: $jaegerDetected,
                        jaegerPath: $jaegerPath,
                        onContinue: { step = .configure }
                    )
                    
                case .configure:
                    ConfigureStep(
                        jaegerDetected: jaegerDetected,
                        jaegerPath: jaegerPath,
                        isCompleting: $isCompleting,
                        error: $error,
                        onComplete: { step = .complete }
                    )
                    
                case .complete:
                    CompleteStep(onFinish: {
                        NSApp.keyWindow?.close()
                    })
                }
            }
            .padding(40)
            .frame(maxWidth: 500, maxHeight: .infinity)
        }
        .frame(width: 580, height: 480)
        .background(.regularMaterial)
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            
            VStack(spacing: 8) {
                Text("Welcome to ARES")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Your local AI Companion")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text("ARES connects you to AI runtimes like JaegerAI, Hermes, and cloud providers. Let's get you set up.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Detection Step

struct DetectionStep: View {
    @Binding var jaegerDetected: Bool
    @Binding var jaegerPath: String
    let onContinue: () -> Void
    
    @State private var isDetecting = true
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            if isDetecting {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Detecting AI runtimes…")
                    .font(.headline)
            } else {
                Image(systemName: jaegerDetected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(jaegerDetected ? .green : .orange)
                
                VStack(spacing: 8) {
                    Text(jaegerDetected ? "JaegerAI Detected" : "No Runtimes Found")
                        .font(.title)
                        .fontWeight(.semibold)
                    if jaegerDetected {
                        Text(jaegerPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if jaegerDetected {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            Text("JaegerAI is ready to use")
                                .font(.subheadline)
                        }
                        
                        HStack {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.secondary)
                            Text("Other adapters marked as Pending")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
                } else {
                    Text("You can configure runtimes later in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Button(jaegerDetected ? "Continue" : "Skip") {
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isDetecting)
        }
        .task {
            await detectRuntimes()
        }
    }
    
    @MainActor
    private func detectRuntimes() async {
        // Check common JaegerAI locations
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("jaeger"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("GitHub/JaegerAI"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".jaeger")
        ]
        
        for path in candidates {
            let jaegerExecutable = path.appendingPathComponent("jaeger")
            if FileManager.default.fileExists(atPath: jaegerExecutable.path) {
                jaegerDetected = true
                jaegerPath = path.path
                isDetecting = false
                return
            }
        }
        
        isDetecting = false
    }
}

// MARK: - Configure Step

struct ConfigureStep: View {
    let jaegerDetected: Bool
    let jaegerPath: String
    @Binding var isCompleting: Bool
    @Binding var error: String?
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "gearshape")
                .font(.system(size: 64))
                .foregroundStyle(.primary)
            
            VStack(spacing: 8) {
                Text("Configuration")
                    .font(.title)
                    .fontWeight(.semibold)
                if jaegerDetected {
                    Text("ARES will use JaegerAI as your primary runtime")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Configure runtimes later in Settings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                RuntimeStatusRow(
                    name: "JaegerAI",
                    status: jaegerDetected ? .ready : .pending,
                    path: jaegerPath
                )
                RuntimeStatusRow(name: "Hermes", status: .pending, path: "")
                RuntimeStatusRow(name: "Ollama Cloud", status: .pending, path: "")
                RuntimeStatusRow(name: "Anthropic", status: .pending, path: "")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button(action: completeSetup) {
                if isCompleting {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Completing…")
                } else {
                    Text(jaegerDetected ? "Finish Setup" : "Continue")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isCompleting)
        }
    }
    
    private func completeSetup() {
        isCompleting = true
        error = nil
        
        // Write config to mark JaegerAI as primary
        if jaegerDetected {
            let configDir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".ares")
            
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            
            let configURL = configDir.appendingPathComponent("backend.yaml")
            let config = """
            # Auto-generated by ARES onboarding
            backend:
              primary: jros_local
              jros_path: \(jaegerPath)
            
            fallback:
              - provider: ollama-cloud
                model: qwen3.5:cloud
              - provider: anthropic
            
            adapters:
              - name: JaegerAI
                status: ready
                path: \(jaegerPath)
              - name: Hermes
                status: pending
              - name: Ollama Cloud
                status: pending
              - name: Anthropic
                status: pending
            """
            
            do {
                try config.write(to: configURL, atomically: true, encoding: .utf8)
                onComplete()
            } catch {
                self.error = "Could not save configuration: \(error.localizedDescription)"
            }
        } else {
            onComplete()
        }
        
        isCompleting = false
    }
}

// MARK: - Complete Step

struct CompleteStep: View {
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Setup Complete")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("ARES is ready to use")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Text("You can configure additional runtimes in Settings → Connections")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            Button("Get Started", action: onFinish)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

// MARK: - Helpers

struct RuntimeStatusRow: View {
    let name: String
    let status: RuntimeStatus
    let path: String
    
    enum RuntimeStatus {
        case ready
        case pending
    }
    
    var body: some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundStyle(status.color)
                .frame(width: 20)
            Text(name)
                .font(.subheadline)
            Spacer()
            if !path.isEmpty {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Text(status.label)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(status.color.opacity(0.1))
                .foregroundStyle(status.color)
                .cornerRadius(4)
        }
    }
}

extension RuntimeStatusRow.RuntimeStatus {
    var icon: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .pending: return "clock.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .ready: return .green
        case .pending: return .orange
        }
    }
    
    var label: String {
        switch self {
        case .ready: return "Ready"
        case .pending: return "Pending"
        }
    }
}

#Preview {
    ARESOnboardingView(onComplete: {})
}
