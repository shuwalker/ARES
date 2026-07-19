import SwiftUI
import ARESCore
import Network
import CoreImage.CIFilterBuiltins

struct PendingApproval: Identifiable, Codable {
    var id: String { approval_id }
    let session_id: String
    let approval_id: String
    let command: String
    let type: String
    let created_at: String
    let tool_name: String
}

struct AuditLogEntry: Identifiable, Codable {
    var id: String { timestamp + session_id }
    let timestamp: String
    let session_id: String
    let action: String
    let details: String
    let status: String
}

struct ApprovalListResponse: Codable {
    let approvals: [PendingApproval]
}

struct AuditLogResponse: Codable {
    let logs: [AuditLogEntry]
}

struct RuntimeConnectionOption: Codable, Identifiable {
    let id: String
    let name: String
    let kind: String
    let selected: Bool
}

struct RuntimeConnectionsResponse: Codable {
    let selected: String
    let connections: [RuntimeConnectionOption]
}

struct BackendSetResponse: Codable {
    let ok: Bool?
    let backend: String?
}

public struct ARESSettingsView: View {
    @ObservedObject var config = ARESConfiguration.shared
    @ObservedObject var serverManager = WebUIServerManager.shared
    
    @State private var activeTab = 0
    
    // Remote Access
    @State private var lanIP: String? = nil
    @State private var tailscaleIP: String? = nil
    
    // Backends status
    @State private var activeBackend = UserDefaults.standard.string(forKey: "ares.backend.selected") ?? ""
    @State private var runtimeOptions: [RuntimeConnectionOption] = []
    @State private var backendSelectionError: String? = nil
    @State private var jrosLive = false
    @State private var hermesLive = false
    @State private var checkTimer: Timer? = nil
    
    // Safety & Approvals
    @State private var pendingApprovals: [PendingApproval] = []
    @State private var auditLogs: [AuditLogEntry] = []
    @State private var pathMonitor: NWPathMonitor? = nil
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $activeTab) {
            serverTab
                .tabItem {
                    Label("Server & Network", systemImage: "server.rack")
                }
                .tag(0)
                
            backendsTab
                .tabItem {
                    Label("Backend Runtimes", systemImage: "cpu")
                }
                .tag(1)
                
            remoteAccessTab
                .tabItem {
                    Label("Remote Access", systemImage: "qrcode")
                }
                .tag(2)
                
            safetyTab
                .tabItem {
                    Label("Safety & Approvals", systemImage: "shield.checkered")
                }
                .tag(3)
        }
        .frame(width: 650, height: 480)
        .padding()
        .onAppear {
            refreshNetworkIPs()
            refreshBackendSelection()
            startLivenessChecks()
            refreshApprovalsAndLogs()
            
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { _ in
                DispatchQueue.main.async {
                    self.refreshNetworkIPs()
                }
            }
            monitor.start(queue: .global())
            self.pathMonitor = monitor
        }
        .onDisappear {
            checkTimer?.invalidate()
            pathMonitor?.cancel()
        }
    }
    
    // MARK: - Server Tab
    private var serverTab: some View {
        Form {
            Section(header: Text("Web UI Server Control").font(.headline)) {
                HStack(spacing: 16) {
                    Circle()
                        .fill(serverColor)
                        .frame(width: 12, height: 12)
                    Text("Server Status: \(serverManager.serverHealth)")
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 4)
                
                HStack {
                    Button("Start Server") {
                        Task { await serverManager.start() }
                    }
                    .disabled(serverManager.isRunning)
                    
                    Button("Stop Server") {
                        serverManager.stop()
                    }
                    .disabled(!serverManager.isRunning)
                    
                    Button("Restart Server") {
                        Task { await serverManager.restart() }
                    }
                }
                .padding(.bottom, 8)
            }
            
            Section(header: Text("Configuration Settings").font(.headline)) {
                TextField("WebUI Host", text: $config.webuiHost)
                    .textFieldStyle(.roundedBorder)
                
                TextField("WebUI Port", value: $config.webuiPort, formatter: NumberFormatter())
                    .textFieldStyle(.roundedBorder)
                    
                Toggle("Start WebUI Server on App Launch", isOn: $config.autoLaunchOnStart)
                Toggle("Enable Live Reload / Dev Mode", isOn: $config.reloadDevMode)
            }

            Section(header: Text("ARES Device Mesh").font(.headline)) {
                Picker("This Mac", selection: $config.aresRole) {
                    Text("Primary AI Body").tag("primary")
                    Text("Joined ARES Device").tag("device")
                }
                .pickerStyle(.segmented)

                TextField("Device ID", text: $config.aresDeviceID)
                    .textFieldStyle(.roundedBorder)

                TextField("AI ID", text: $config.aresAIID)
                    .textFieldStyle(.roundedBorder)

                TextField("Primary ARES URL", text: $config.aresPrimaryURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(config.aresRole == "primary")

                TextField("Continuity Folder", text: $config.aresContinuityDir)
                    .textFieldStyle(.roundedBorder)

                Text(config.aresRole == "primary"
                     ? "This Mac owns the canonical ARES identity and device registry."
                     : "This Mac joins an existing AI and can contribute app access, local tools, and compute.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Paths & Logs").font(.headline)) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config Directory: ~/.ares")
                    Text("State Database: ~/.ares/state.db")
                }
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.vertical, 2)
                
                NavigationLink("View Console Logs") {
                    ScrollView {
                        Text(serverManager.recentLogs.isEmpty ? "No recent logs." : serverManager.recentLogs)
                            .font(.system(.footnote, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .frame(width: 600, height: 300)
                }
            }
        }
        .padding()
    }
    
    // MARK: - Backends Tab
    private var backendsTab: some View {
        Form {
            Section(header: Text("Default Runtime Selection").font(.headline)) {
                Picker("Default Chat Runtime", selection: Binding(
                    get: { activeBackend },
                    set: { val in
                        writeBackendSelection(val)
                    }
                )) {
                    if activeBackend.isEmpty {
                        Text("Choose a runtime").tag("")
                    }
                    ForEach(runtimeOptions.filter { $0.kind == "runtime" }) { runtime in
                        Text(runtime.name).tag(runtime.id)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(!serverManager.isRunning || runtimeOptions.isEmpty)

                if !serverManager.isRunning {
                    Text("Start the Web UI server to change the default runtime.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let backendSelectionError {
                    Text(backendSelectionError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Section(header: Text("Backend Liveness").font(.headline)) {
                HStack(spacing: 24) {
                    statusCard(title: "Hermes Gateway", isLive: hermesLive, url: config.hermesURL)
                    statusCard(title: "JROS Gateway", isLive: jrosLive, url: config.jrosURL)
                }
            }
            
            Section(header: Text("Gateway Configurations").font(.headline)) {
                TextField("Hermes Gateway URL", text: $config.hermesURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("Hermes API Key", text: $config.hermesAPIKey)
                    .textFieldStyle(.roundedBorder)
                TextField("JROS Gateway URL", text: $config.jrosURL)
                    .textFieldStyle(.roundedBorder)
                SecureField("JROS Gateway Key", text: $config.jrosAPIKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }
    
    // MARK: - Remote Access Tab
    private var remoteAccessTab: some View {
        VStack(spacing: 16) {
            Text("Access ARES From Mobile / Tablet")
                .font(.headline)
            
            HStack(spacing: 32) {
                if let url = qrCodeURL, let qrImage = generateQRCode(from: url) {
                    VStack {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 160, height: 160)
                            .border(Color.gray.opacity(0.3))
                        Text("Scan to connect")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 80))
                            .foregroundColor(.secondary)
                        Text("Connect server first")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connection URLs:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Text("Local: http://\(config.webuiHost):\(config.webuiPort)")
                        .font(.system(.body, design: .monospaced))
                    
                    if let lan = lanIP {
                        Text("LAN IP: http://\(lan):\(config.webuiPort)")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("LAN IP: Not connected to Wi-Fi/Ethernet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let ts = tailscaleIP {
                        Text("Tailscale: http://\(ts):\(config.webuiPort)")
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("Tailscale IP: Not detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 6) {
                Label("Secure Microphone Constraints", systemImage: "mic.badge.xmark")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.amber)
                Text("Modern browsers (iOS Safari, Chrome) block microphone access on unencrypted connections. Accessing the Web UI over LAN/Tailscale HTTP will disable voice input. To use voice, run ARES locally or configure HTTPS.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
    }
    
    // MARK: - Safety & Approvals Tab
    private var safetyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pending Risk Clearances")
                .font(.headline)
            
            if pendingApprovals.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                    Text("No pending risk actions requiring approval.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(pendingApprovals) { app in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.tool_name.isEmpty ? "System Tool" : app.tool_name)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(app.command)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                HStack {
                                    Button("Approve") {
                                        respondToApproval(app, choice: "once")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    
                                    Button("Deny") {
                                        respondToApproval(app, choice: "deny")
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            
            Divider()
            
            Text("Audit Logs")
                .font(.headline)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if auditLogs.isEmpty {
                        Text("No audit events logged yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(auditLogs) { entry in
                            HStack {
                                Text(formatTime(entry.timestamp))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                Text(entry.action)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                Text(entry.details)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(entry.status.uppercased())
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(entry.status == "deny" ? .red : .green)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)
            
            Button("Refresh Approvals & Logs") {
                refreshApprovalsAndLogs()
            }
        }
        .padding()
    }
    
    // MARK: - Helpers
    private var serverColor: Color {
        switch serverManager.serverHealth {
        case "Running (Healthy)": return .green
        case "Starting...": return .orange
        case "Stopped": return .gray
        default: return .red
        }
    }
    
    private var qrCodeURL: String? {
        if let lan = lanIP {
            return "http://\(lan):\(config.webuiPort)"
        }
        return nil
    }
    
    private func statusCard(title: String, isLive: Bool, url: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.bold)
            HStack {
                Circle()
                    .fill(isLive ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isLive ? "Online" : "Offline")
                    .font(.caption)
            }
            Text(url)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
    
    private func generateQRCode(from string: String) -> NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            let transform = CGAffineTransform(scaleX: 10, y: 10)
            let scaledImage = outputImage.transformed(by: transform)
            
            if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
                return NSImage(cgImage: cgImage, size: NSSize(width: 160, height: 160))
            }
        }
        return nil
    }
    
    private func refreshNetworkIPs() {
        var lanAddress: String? = nil
        var tailscaleAddress: String? = nil

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return }
        defer { freeifaddrs(ifaddr) }

        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }

            guard let interface = ptr?.pointee,
                  let interfaceAddr = interface.ifa_addr else { continue }
            let addrFamily = interfaceAddr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interfaceAddr, socklen_t(interfaceAddr.pointee.sa_len),
                            &hostname, socklen_t(hostname.count),
                            nil, 0, NI_NUMERICHOST)
                let ipAddress = String(cString: hostname)
                
                if name.contains("utun") {
                    if ipAddress.hasPrefix("100.") {
                        tailscaleAddress = ipAddress
                    }
                } else if name.hasPrefix("en") || name.hasPrefix("ap") {
                    if !ipAddress.hasPrefix("127.") && !ipAddress.hasPrefix("169.254") {
                        lanAddress = ipAddress
                    }
                }
            }
        }
        self.lanIP = lanAddress
        self.tailscaleIP = tailscaleAddress
    }
    
    private func startLivenessChecks() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                await performLivenessProbes()
                refreshBackendSelection()
                refreshApprovalsAndLogs()
            }
        }
        Task {
            await performLivenessProbes()
        }
    }
    
    private func performLivenessProbes() async {
        // Probe Hermes
        if let hermesUrl = endpointURL(base: config.hermesURL, path: "/health") {
            var request = URLRequest(url: hermesUrl)
            request.timeoutInterval = 1.0
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    self.hermesLive = true
                } else {
                    self.hermesLive = false
                }
            } catch {
                self.hermesLive = false
            }
        } else {
            self.hermesLive = false
        }
        
        // Probe JROS
        if let jrosUrl = endpointURL(base: config.jrosURL, path: "/v1/health") {
            var request = URLRequest(url: jrosUrl)
            request.timeoutInterval = 1.0
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let ok = json["ok"] as? Bool {
                        self.jrosLive = ok
                    } else {
                        self.jrosLive = false
                    }
                } else {
                    self.jrosLive = false
                }
            } catch {
                self.jrosLive = false
            }
        } else {
            self.jrosLive = false
        }
    }
    
    private func refreshApprovalsAndLogs() {
        guard serverManager.isRunning else {
            self.pendingApprovals = []
            self.auditLogs = []
            return
        }
        
        let host = config.webuiHost
        let port = config.webuiPort
        
        // Fetch Approvals
        guard let approvalsUrl = URL(string: "http://\(host):\(port)/api/ares/approvals/pending") else { return }
        URLSession.shared.dataTask(with: approvalsUrl) { data, _, error in
            if let data = data, let decoded = try? JSONDecoder().decode(ApprovalListResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.pendingApprovals = decoded.approvals
                }
            }
        }.resume()
        
        // Fetch Logs
        guard let logsUrl = URL(string: "http://\(host):\(port)/api/ares/audit/logs") else { return }
        URLSession.shared.dataTask(with: logsUrl) { data, _, error in
            if let data = data, let decoded = try? JSONDecoder().decode(AuditLogResponse.self, from: data) {
                DispatchQueue.main.async {
                    self.auditLogs = decoded.logs
                }
            }
        }.resume()
    }
    
    private func respondToApproval(_ app: PendingApproval, choice: String) {
        let host = config.webuiHost
        let port = config.webuiPort
        
        guard let url = URL(string: "http://\(host):\(port)/api/approval/respond") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "session_id": app.session_id,
            "approval_id": app.approval_id,
            "choice": choice
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { _, _, _ in
            DispatchQueue.main.async {
                refreshApprovalsAndLogs()
            }
        }.resume()
    }
    
    private func writeBackendSelection(_ val: String) {
        let host = config.webuiHost
        let port = config.webuiPort
        let previous = activeBackend
        activeBackend = val
        backendSelectionError = nil
        
        guard let url = URL(string: "http://\(host):\(port)/api/ares/backend/set") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = ["backend": val]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error {
                    activeBackend = previous
                    backendSelectionError = "Failed to save default runtime: \(error.localizedDescription)"
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    activeBackend = previous
                    backendSelectionError = "Failed to save default runtime."
                    return
                }
                if let data,
                   let decoded = try? JSONDecoder().decode(BackendSetResponse.self, from: data),
                   decoded.ok == false {
                    activeBackend = previous
                    backendSelectionError = "Failed to save default runtime."
                    return
                }
                let confirmed = (data.flatMap { try? JSONDecoder().decode(BackendSetResponse.self, from: $0) }?.backend) ?? val
                activeBackend = confirmed
                UserDefaults.standard.set(confirmed, forKey: "ares.backend.selected")
            }
        }.resume()
    }

    private func refreshBackendSelection() {
        guard serverManager.isRunning else { return }
        let host = config.webuiHost
        let port = config.webuiPort
        guard let url = URL(string: "http://\(host):\(port)/api/connections") else { return }

        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data,
               let decoded = try? JSONDecoder().decode(RuntimeConnectionsResponse.self, from: data) {
                DispatchQueue.main.async {
                    runtimeOptions = decoded.connections.filter { $0.kind == "runtime" }
                    activeBackend = decoded.selected
                    UserDefaults.standard.set(decoded.selected, forKey: "ares.backend.selected")
                }
            }
        }.resume()
    }

    private func endpointURL(base: String, path: String) -> URL? {
        var trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmedBase.hasSuffix("/") {
            trimmedBase.removeLast()
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: trimmedBase + normalizedPath)
    }
    
    private func formatTime(_ raw: String) -> String {
        // Returns the time part of ISO timestamp
        if let idx = raw.firstIndex(of: "T") {
            let start = raw.index(after: idx)
            let end = raw.index(start, offsetBy: 8, limitedBy: raw.endIndex) ?? raw.endIndex
            return String(raw[start..<end])
        }
        return raw
    }
}

fileprivate extension Color {
    static let amber = Color(red: 0.85, green: 0.65, blue: 0.15)
}
