import SwiftUI
import ARESCore

struct ExtensionSpec: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let repoURL: String
    var isInstalled: Bool
    var isInstalling: Bool = false
    var installProgress: Double = 0.0
}

@MainActor
class ExtensionManager: ObservableObject {
    @Published var availableExtensions: [ExtensionSpec] = [
        ExtensionSpec(id: "hermes-agent", name: "Hermes Autonomous Agent", description: "The brains behind ARES. Enables advanced reasoning, web browsing, and code execution.", icon: "brain.head.profile", repoURL: "https://github.com/JenkinsRobotics/hermes-agent.git", isInstalled: false),
        ExtensionSpec(id: "open-sora", name: "Open-Sora Video Generation", description: "Generate short videos from text natively on your Mac.", icon: "video.fill", repoURL: "https://github.com/JenkinsRobotics/Open-Sora.git", isInstalled: false),
        ExtensionSpec(id: "sam", name: "Segment Anything Model", description: "Advanced computer vision allowing ARES to precisely click elements on your screen.", icon: "viewfinder", repoURL: "https://github.com/JenkinsRobotics/SAM.git", isInstalled: false),
        ExtensionSpec(id: "open-llm-vtuber", name: "Avatar Node", description: "Give ARES a fully animated, lip-synced 3D avatar.", icon: "person.crop.circle.badge.plus", repoURL: "https://github.com/JenkinsRobotics/Open-LLM-VTuber.git", isInstalled: false)
    ]

    func installExtension(_ ext: ExtensionSpec) {
        guard let index = availableExtensions.firstIndex(where: { $0.id == ext.id }) else { return }
        availableExtensions[index].isInstalling = true
        
        Task {
            do {
                try await NodeInstallerService.shared.install(repoURL: ext.repoURL, destination: ext.id) { progress in
                    Task { @MainActor in
                        self.availableExtensions[index].installProgress = progress
                    }
                }
                
                await MainActor.run {
                    self.availableExtensions[index].isInstalling = false
                    self.availableExtensions[index].isInstalled = true
                    self.availableExtensions[index].installProgress = 1.0
                }
            } catch {
                await MainActor.run {
                    self.availableExtensions[index].isInstalling = false
                    print("Installation failed: \(error)")
                }
            }
        }
    }
}

struct ExtensionStoreView: View {
    @StateObject private var manager = ExtensionManager()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pro Extensions")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            .background(.ultraThinMaterial)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(manager.availableExtensions) { ext in
                        ExtensionCard(ext: ext) {
                            manager.installExtension(ext)
                        }
                    }
                }
                .padding()
            }
        }
        .background(ARESColors.background)
    }
}

struct ExtensionCard: View {
    let ext: ExtensionSpec
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: ext.icon)
                    .font(.title)
                    .foregroundColor(.blue)
                Spacer()
                if ext.isInstalled {
                    Text("Installed")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                } else if ext.isInstalling {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(ext.name)
                    .font(.headline)
                Text(ext.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            Spacer()

            if ext.isInstalling {
                ProgressView(value: ext.installProgress)
                    .tint(.blue)
            } else if !ext.isInstalled {
                Button {
                    onInstall()
                } label: {
                    Text("Install")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    // Open Settings or Manage
                } label: {
                    Text("Manage")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(height: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}
