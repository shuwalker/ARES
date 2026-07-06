import SwiftUI

struct SetupView: View {
    @EnvironmentObject var state: AppState
    @State private var step: SetupStep = .welcome
    @State private var tailscaleIP: String = ""
    @State private var manualHost: String = ""
    @State private var isChecking = false
    @State private var errorMessage: String?

    enum SetupStep {
        case welcome
        case tailscale
        case connecting
        case complete
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                switch step {
                case .welcome:
                    welcomeStep
                case .tailscale:
                    tailscaleStep
                case .connecting:
                    connectingStep
                case .complete:
                    completeStep
                }

                Spacer()
            }
            .padding(60)
        }
        .onAppear {
            // Skip setup if already configured
            if let saved = UserDefaults.standard.string(forKey: "ares_gateway_url") {
                state.gateway = HermesGateway(url: saved)
                state.setupComplete = true
            }
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.righthalf.filled")
                .font(.system(size: 60))
                .foregroundColor(.black.opacity(0.8))

            Text("ARES")
                .font(.system(size: 48, weight: .bold, design: .serif))
                .tracking(8)
                .foregroundColor(.black)

            Text("Your AI platform. One face for all your intelligence.")
                .font(.system(size: 16, weight: .light))
                .foregroundColor(.black.opacity(0.5))

            Button {
                withAnimation { step = .tailscale }
            } label: {
                Text("Get Started")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 14)
                    .background(Color.black)
                    .cornerRadius(20)
            }
            .buttonStyle(.plain)
        }
    }

    private var tailscaleStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "network")
                .font(.system(size: 40))
                .foregroundColor(.black.opacity(0.6))

            Text("Connect to your ARES host")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.black)

            Text("ARES runs on your computer, server, homelab, or another backend host. This device connects to it over Tailscale or a private network.")
                .font(.body)
                .foregroundColor(.black.opacity(0.5))
                .multilineTextAlignment(.center)

            if isChecking {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Discovering your ARES host...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !tailscaleIP.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)

                    Text("Found ARES host")
                        .fontWeight(.medium)

                    Text(tailscaleIP)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(8)

                    Text("Gateway is responding")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        state.gateway = HermesGateway(url: "http://\(tailscaleIP):8642")
                        UserDefaults.standard.set("http://\(tailscaleIP):8642", forKey: "ares_gateway_url")
                        withAnimation { step = .connecting }
                    } label: {
                        Text("Connect")
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 14)
                            .background(Color.black)
                            .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundColor(.orange)

                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        Button {
                            tailscaleIP = ""
                            errorMessage = nil
                            discoverTailscale()
                        } label: {
                            Text("Try Again")
                                .foregroundColor(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.black.opacity(0.08))
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 8) {
                            TextField("100.x.y.z or hostname", text: $manualHost)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                            Button {
                                let trimmed = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    tailscaleIP = trimmed
                                    errorMessage = nil
                                }
                            } label: {
                                Text("Use Manual Host")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if tailscaleIP.isEmpty && !isChecking {
                Button {
                    discoverTailscale()
                } label: {
                    Text("Scan for ARES Host")
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                        .background(Color.black)
                        .cornerRadius(20)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var connectingStep: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting to ARES...")
                .font(.title3)
                .foregroundColor(.black)

            Text("Establishing secure connection to your ARES host")
                .font(.body)
                .foregroundColor(.black.opacity(0.5))
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                state.setupComplete = true
            }
        }
    }

    private var completeStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("Ready")
                .font(.title)
                .fontWeight(.bold)

            Text("ARES is connected. The Gate is open.")
                .foregroundColor(.secondary)
        }
    }

    private func discoverTailscale() {
        isChecking = true
        errorMessage = nil

        Task {
            // Try local development first; remote hosts are discovered from the user's Tailscale peers below.
            let candidates = ["localhost", "127.0.0.1"]
            for ip in candidates {
                let url = "http://\(ip):8642"
                if let healthy = try? await HermesGateway(url: url).health(), healthy {
                    await MainActor.run {
                        tailscaleIP = ip
                        isChecking = false
                    }
                    return
                }
            }

            // Try to get Tailscale status
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = ["tailscale", "status", "--json"]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let peers = (json["Peer"] as? [String: Any]) ?? json
                    for (_, value) in peers {
                        if let peer = value as? [String: Any],
                           let tailscaleIPs = peer["TailscaleIPs"] as? [String] {
                            if let ip = tailscaleIPs.first {
                                let url = "http://\(ip):8642"
                                if let healthy = try? await HermesGateway(url: url).health(), healthy {
                                    await MainActor.run {
                                        tailscaleIP = ip
                                        isChecking = false
                                    }
                                    return
                                }
                            }
                        }
                    }
                }
            } catch {}

            await MainActor.run {
                isChecking = false
                errorMessage = "Could not find an ARES host on Tailscale. Make sure Tailscale is running on both devices and the backend gateway is active, or enter the host manually."
            }
        }
    }
}
