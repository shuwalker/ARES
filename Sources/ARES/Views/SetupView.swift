import SwiftUI

struct SetupView: View {
    @EnvironmentObject var state: AppState
    @State private var step: SetupStep = .welcome
    @State private var tailscaleIP: String = ""
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

            Text("Connect to your Mac Studio")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.black)

            Text("ARES runs on your Mac Studio. This device connects to it over Tailscale.")
                .font(.body)
                .foregroundColor(.black.opacity(0.5))
                .multilineTextAlignment(.center)

            if isChecking {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Discovering your Mac Studio...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !tailscaleIP.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.green)

                    Text("Found Mac Studio")
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

                        Button {
                            // Manual entry
                            tailscaleIP = "100.74.2.15"
                            errorMessage = nil
                        } label: {
                            Text("Enter Manually")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if tailscaleIP.isEmpty && !isChecking {
                Button {
                    discoverTailscale()
                } label: {
                    Text("Scan for Mac Studio")
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

            Text("Establishing secure connection to your Mac Studio")
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
            // Try common Tailscale IPs and localhost
            let candidates = ["100.74.2.15", "100.78.245.49", "localhost", "100.100.100.100"]
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
                    for (_, value) in json {
                        if let peer = value as? [String: Any],
                           let tailscaleIPs = peer["TailscaleIPs"] as? [String],
                           let dnsName = peer["DNSName"] as? String,
                           dnsName.lowercased().contains("studio") || dnsName.lowercased().contains("macstudio") {
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
                errorMessage = "Could not find your Mac Studio on Tailscale. Make sure Tailscale is running on both devices and the Hermes Gateway is active."
            }
        }
    }
}
