import SwiftUI

/// Three-phase bootstrap sheet: check → install (if needed) → verify.
/// Shown after user selects a remote device to connect to.
struct RemoteBootstrapSheet: View {
    
    @StateObject private var bootstrap: RemoteBootstrapService
    @State private var keyExchangeResult: SSHKeyExchange.KeyExchangeResult?
    @State private var showKeyInstructions = false
    @State private var publicKeyContent: String?
    
    let connection: ConnectionProfile
    let onComplete: (ConnectionProfile) -> Void
    
    init(connection: ConnectionProfile, onComplete: @escaping (ConnectionProfile) -> Void) {
        self.connection = connection
        self.onComplete = onComplete
        // SSHTransport and AppPaths need to be resolved from app state —
        // in production, inject these from the environment.
        let paths = AppPaths()
        let transport = SSHTransport(paths: paths)
        _bootstrap = StateObject(wrappedValue: RemoteBootstrapService(
            sshTransport: transport,
            connection: connection
        ))
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                phaseIcon
                    .font(.system(size: 48))
                
                Text(connection.effectiveTarget)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(phaseDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)
            
            // Progress / results
            Group {
                switch bootstrap.phase {
                case .idle:
                    if let check = bootstrap.checkResult {
                        checkResultView(check)
                    } else {
                        startButton
                    }
                case .checking, .installing, .verifying:
                    ProgressView(bootstrap.progressMessage)
                        .padding()
                case .done:
                    doneView
                case .failed(let message):
                    failureView(message)
                }
            }
            
            // Log
            if !bootstrap.log.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(bootstrap.log, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .frame(width: 480, height: 520)
    }
    
    // MARK: - Phase Views
    
    @ViewBuilder
    private var phaseIcon: some View {
        switch bootstrap.phase {
        case .idle:       Image(systemName: "desktopcomputer.and.arrow.down")
        case .checking:   Image(systemName: "magnifyingglass")
        case .installing: Image(systemName: "arrow.down.circle")
        case .verifying:  Image(systemName: "checkmark.shield")
        case .done:        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
        case .failed:      Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
        }
    }
    
    private var phaseDescription: String {
        switch bootstrap.phase {
        case .idle:       "Ready to set up \(connection.effectiveTarget)"
        case .checking:   "Checking what's already installed..."
        case .installing: "Installing Hermes Agent..."
        case .verifying:  "Verifying connection..."
        case .done:        "Connected and verified!"
        case .failed(let msg): msg
        }
    }
    
    private var startButton: some View {
        VStack(spacing: 12) {
            Button {
                Task { await runBootstrap() }
            } label: {
                Label("Check & Set Up", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            if showKeyInstructions, let pubKey = publicKeyContent {
                keyInstructionsSection(pubKey)
            }
        }
    }
    
    private func checkResultView(_ check: RemoteBootstrapService.RemoteCheckResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Found on \(check.hostname)")
                .font(.headline)
            
            LabeledContent("Hermes Agent") {
                if check.hermesInstalled {
                    Label(check.hermesVersion ?? "installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not installed", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            
            LabeledContent("Ollama") {
                if check.ollamaInstalled {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Not installed", systemImage: "xmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
            
            LabeledContent("Hermes Home") {
                Text(check.hermesHomeExists ? "✓" : "✗")
            }
            
            LabeledContent("Config") {
                Text(check.configExists ? "✓" : "✗")
            }
            
            if let gb = check.diskSpaceGB {
                LabeledContent("Disk Space") {
                    Text("\(gb) GB free")
                }
            }
            
            HStack {
                if !check.hermesInstalled {
                    Button {
                        Task { await runBootstrap() }
                    } label: {
                        Label("Install Hermes", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                if check.hermesInstalled {
                    Button {
                        Task { await verifyOnly() }
                    } label: {
                        Label("Connect", systemImage: "link")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.top, 8)
        }
        .padding()
    }
    
    private var doneView: some View {
        VStack(spacing: 16) {
            Text("Setup Complete")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("\(connection.effectiveTarget) is ready to use.")
                .foregroundStyle(.secondary)
            
            Button("Done") {
                onComplete(connection)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
    
    private func failureView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text("Setup Failed")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.red)
            
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task { await runBootstrap() }
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func keyInstructionsSection(_ pubKey: String) -> some View {
        GroupBox("SSH Key Authentication Required") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run this command on the remote Mac:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text("mkdir -p ~/.ssh && echo '\(pubKey)' >> ~/.ssh/authorized_keys")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)
                
                Button("Copy Command") {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("mkdir -p ~/.ssh && echo '\(pubKey)' >> ~/.ssh/authorized_keys", forType: .string)
                    #endif
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
    
    // MARK: - Actions
    
    private func runBootstrap() async {
        // First, try SSH key exchange
        let paths = AppPaths()
        let keyExchange = SSHKeyExchange(sshTransport: SSHTransport(paths: paths), paths: paths)
        
        do {
            let result = try keyExchange.generateKey()
            keyExchangeResult = result
            
            // Try connecting with the key
            let connected = (try? await keyExchange.verifyConnection(connection: connection)) ?? false
            if !connected {
                // Key doesn't work yet — show instructions
                publicKeyContent = keyExchange.getPublicKeyContent()
                showKeyInstructions = true
                return
            }
        } catch {
            // Key gen failed — fall through to bootstrap anyway
            // (password auth may work)
        }
        
        do {
            let _ = try await bootstrap.runFullBootstrap()
        } catch {
            // Error is shown in the bootstrap phase
        }
    }
    
    private func verifyOnly() async {
        _ = try? await bootstrap.verify()
    }
}