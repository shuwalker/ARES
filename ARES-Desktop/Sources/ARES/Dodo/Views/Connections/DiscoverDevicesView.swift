import SwiftUI

/// Bonjour device discovery + manual entry sheet.
/// Shown when user taps "Add Device" in ConnectionsView.
struct DiscoverDevicesView: View {
    @StateObject private var bonjour = BonjourBrowser()
    @State private var manualHost = ""
    @State private var manualUser = ""
    @State private var manualAlias = ""
    @State private var showBootstrap = false
    @State private var bootstrapConnection: ConnectionProfile?
    @State private var showKeyExchange = false
    @State private var sshError: String?
    
    let onAdded: (ConnectionProfile) -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Bonjour section
                nearbySection
                
                Divider()
                
                // Manual entry section
                manualSection
                
                if let error = sshError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .navigationTitle("Add Remote Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { /* dismiss */ }
                }
            }
            .task {
                bonjour.startScanning()
            }
            .onDisappear {
                bonjour.stopScanning()
            }
            .sheet(isPresented: $showBootstrap) {
                if let connection = bootstrapConnection {
                    RemoteBootstrapSheet(
                        connection: connection,
                        onComplete: { profile in
                            onAdded(profile)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Nearby Devices
    
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Nearby Devices", systemImage: "desktopcomputer.and.arrow.down")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 16)
            
            if bonjour.isScanning && bonjour.devices.isEmpty {
                ProgressView("Scanning...")
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if bonjour.filteredDevices().isEmpty {
                Text("No devices found. Make sure Remote Login is enabled on the target Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                List(bonjour.filteredDevices()) { device in
                    deviceRow(device)
                }
                .frame(maxHeight: 200)
            }
        }
    }
    
    private func deviceRow(_ device: BonjourBrowser.DiscoveredDevice) -> some View {
        HStack {
            Image(systemName: device.isTailscale ? "antenna.radiowaves.left.and.right" : "desktopcomputer")
                .foregroundStyle(device.isTailscale ? .blue : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.body)
                Text("\(device.displayAddress) · :\(device.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Connect") {
                connectToDevice(device)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Manual Entry
    
    private var manualSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Or Enter Manually", systemImage: "keyboard")
                .font(.headline)
            
            GroupBox {
                LabeledContent("SSH Alias") {
                    TextField("macbook-lan", text: $manualAlias)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                
                LabeledContent("Host") {
                    TextField("100.76.210.48", text: $manualHost)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
                
                LabeledContent("User") {
                    TextField("matthewjenkins", text: $manualUser)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
            }
            
            HStack {
                Spacer()
                Button("Add Device") {
                    connectManual()
                }
                .buttonStyle(.borderedProminent)
                .disabled(manualAlias.isEmpty && manualHost.isEmpty)
            }
        }
        .padding()
    }
    
    // MARK: - Actions
    
    private func connectToDevice(_ device: BonjourBrowser.DiscoveredDevice) {
        let connection = ConnectionProfile(
            label: device.name,
            sshAlias: "",
            sshHost: device.addresses.first ?? device.hostName?.replacingOccurrences(of: ".", with: "") ?? "",
            sshPort: device.port == 22 ? nil : device.port,
            sshUser: ""   // Will prompt or use current username
        )
        
        bootstrapConnection = connection
        showBootstrap = true
    }
    
    private func connectManual() {
        let connection = ConnectionProfile(
            label: manualAlias.isEmpty ? manualHost : manualAlias,
            sshAlias: manualAlias,
            sshHost: manualHost,
            sshPort: nil,
            sshUser: manualUser
        )
        
        bootstrapConnection = connection
        showBootstrap = true
    }
}