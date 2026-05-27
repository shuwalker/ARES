import Foundation

private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Discovers Macs on the local network that advertise SSH access via Bonjour.
/// Uses NetServiceBrowser to find `_ssh._tcp.` services, which every Mac with
/// Remote Login enabled broadcasts automatically — no custom service needed.
@MainActor
final class BonjourBrowser: NSObject, ObservableObject {
    
    struct DiscoveredDevice: Identifiable, Hashable {
        let id = UUID()
        let name: String           // e.g. "Matthews-MacBook-Pro"
        let serviceName: String    // NetService name
        let hostName: String?      // e.g. "matthews-macbook-pro.local."
        let addresses: [String]     // IP addresses
        let port: Int
        let txtRecord: [String: String]
        
        var displayAddress: String {
            addresses.first ?? hostName?.replacingOccurrences(of: ".", with: "") ?? "unknown"
        }
        
        var isTailscale: Bool {
            addresses.contains { $0.hasPrefix("100.") }
        }
    }
    
    @Published var devices: [DiscoveredDevice] = []
    @Published var isScanning = false
    @Published var error: String?
    
    private var browser: NetServiceBrowser?
    private var resolvedServices: [NetService] = []
    private let queue = DispatchQueue(label: "com.ares.bonjour", qos: .userInitiated)
    
    func startScanning() {
        guard !isScanning else { return }
        isScanning = true
        error = nil
        devices = []
        resolvedServices = []
        
        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: "_ssh._tcp.", inDomain: "local.")
        self.browser = browser
    }
    
    func stopScanning() {
        browser?.stop()
        browser = nil
        isScanning = false
    }
    
    /// Filter out the current machine (don't discover yourself).
    func filteredDevices(localHostName: String = Host.current().localizedName ?? "") -> [DiscoveredDevice] {
        devices.filter { device in
            // Don't show this Mac
            device.name != localHostName &&
            !device.name.hasPrefix(localHostName)
        }
    }
}

// MARK: - NetServiceBrowserDelegate

extension BonjourBrowser: NetServiceBrowserDelegate {
    
    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        let name = service.name
        let serviceBox = UncheckedSendableBox(service)
        Task { @MainActor in
            if !resolvedServices.contains(where: { $0.name == name }) {
                resolvedServices.append(serviceBox.value)
            }
        }
    }

    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let name = service.name
        Task { @MainActor in
            devices.removeAll { $0.serviceName == name }
            resolvedServices.removeAll { $0.name == name }
        }
    }
    
    nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: Int]
    ) {
        Task { @MainActor in
            error = "Bonjour search failed: \(errorDict)"
            isScanning = false
        }
    }
}

// MARK: - NetServiceDelegate (resolution)

extension BonjourBrowser: NetServiceDelegate {
    
    nonisolated func netServiceDidResolveAddress(
        _ sender: NetService,
        port: Int16
    ) {
        let addresses = sender.addresses?.compactMap { data -> String? in
            // Extract IP from sockaddr
            data.withUnsafeBytes { rawBuffer in
                guard let sa = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return nil }
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                return result == 0 ? String(cString: host) : nil
            }
        } ?? []
        
        let txtRecord: [String: String]
        if let data = sender.txtRecordData() {
            txtRecord = NetService.dictionary(fromTXTRecord: data)
                .mapValues { String(data: $0, encoding: .utf8) ?? "" }
        } else {
            txtRecord = [:]
        }
        
        let device = DiscoveredDevice(
            name: sender.name.replacingOccurrences(of: "._ssh._tcp.", with: ""),
            serviceName: sender.name,
            hostName: sender.hostName,
            addresses: addresses,
            port: Int(port),
            txtRecord: txtRecord
        )
        let serviceName = sender.name

        Task { @MainActor in
            // Update or add
            if let idx = devices.firstIndex(where: { $0.serviceName == serviceName }) {
                devices[idx] = device
            } else {
                devices.append(device)
            }
        }
    }
    
    nonisolated func netService(
        _ sender: NetService,
        didNotResolve errorDict: [String: Int]
    ) {
        // Resolution failed — just skip this device
    }
}