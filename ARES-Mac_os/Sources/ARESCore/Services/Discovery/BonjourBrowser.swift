import Foundation

/// Discovers Macs on the local network that advertise SSH access via Bonjour.
/// Uses NetServiceBrowser to find `_ssh._tcp.` services, which every Mac with
/// Remote Login enabled broadcasts automatically — no custom service needed.
///
/// Bonjour/NetService requires macOS. On other platforms, this class compiles
/// but `startScanning()` is a no-op and `devices` stays empty.
#if os(macOS)
@MainActor
public final class BonjourBrowser: NSObject, ObservableObject, @unchecked Sendable {
    
    public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let name: String           // e.g. "Matthews-MacBook-Pro"
        public let serviceName: String    // NetService name
        public let hostName: String?      // e.g. "matthews-macbook-pro.local."
        public let addresses: [String]    // IP addresses
        public let port: Int
        public let txtRecord: [String: String]
        
        public var displayAddress: String {
            addresses.first ?? hostName?.replacingOccurrences(of: ".", with: "") ?? "unknown"
        }
        
        public var isTailscale: Bool {
            addresses.contains { $0.hasPrefix("100.") }
        }
    }
    
    @Published public var devices: [DiscoveredDevice] = []
    @Published public var isScanning = false
    @Published public var error: String?
    
    private var browser: NetServiceBrowser?
    private nonisolated(unsafe) var resolvedServices: [NetService] = []
    private let queue = DispatchQueue(label: "com.ares.bonjour", qos: .userInitiated)
    
    public override init() {
        super.init()
    }
    
    public func startScanning() {
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
    
    public func stopScanning() {
        browser?.stop()
        browser = nil
        isScanning = false
    }
    
    /// Filter out the current machine (don't discover yourself).
    public func filteredDevices(localHostName: String = Host.current().localizedName ?? "") -> [DiscoveredDevice] {
        devices.filter { device in
            // Don't show this Mac
            device.name != localHostName &&
            !device.name.hasPrefix(localHostName)
        }
    }
}

// MARK: - NetServiceBrowserDelegate

extension BonjourBrowser: NetServiceBrowserDelegate {
    
    public nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        service.delegate = self
        service.resolve(withTimeout: 5.0)
        let serviceName = service.name
        nonisolated(unsafe) let capturedService = service
        Task { @MainActor in
            if !resolvedServices.contains(where: { $0.name == serviceName }) {
                resolvedServices.append(capturedService)
            }
        }
    }
    
    public nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let serviceName = service.name
        Task { @MainActor in
            devices.removeAll { $0.serviceName == serviceName }
            resolvedServices.removeAll { $0.name == serviceName }
        }
    }
    
    public nonisolated func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        Task { @MainActor in
            error = "Bonjour search failed: \(errorDict)"
            isScanning = false
        }
    }
}

// MARK: - NetServiceDelegate (resolution)

extension BonjourBrowser: NetServiceDelegate {
    
    public nonisolated func netServiceDidResolveAddress(
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
        
        let senderName = sender.name
        let senderHostName = sender.hostName
        
        let device = DiscoveredDevice(
            name: senderName.replacingOccurrences(of: "._ssh._tcp.", with: ""),
            serviceName: senderName,
            hostName: senderHostName,
            addresses: addresses,
            port: Int(port),
            txtRecord: txtRecord
        )
        
        Task { @MainActor in
            // Update or add
            if let idx = devices.firstIndex(where: { $0.serviceName == device.serviceName }) {
                devices[idx] = device
            } else {
                devices.append(device)
            }
        }
    }
    
    public nonisolated func netService(
        _ sender: NetService,
        didNotResolve errorDict: [String: NSNumber]
    ) {
        // Resolution failed — just skip this device
    }
}
#else
/// Stub for non-macOS platforms — Bonjour is unavailable.
@MainActor
public final class BonjourBrowser: ObservableObject, @unchecked Sendable {
    @Published public var devices: [DiscoveredDevice] = []
    @Published public var isScanning = false
    @Published public var error: String?

    public struct DiscoveredDevice: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let name: String
        public let serviceName: String
        public let hostName: String?
        public let addresses: [String]
        public let port: Int
        public let txtRecord: [String: String]

        public var displayAddress: String {
            addresses.first ?? hostName?.replacingOccurrences(of: ".", with: "") ?? "unknown"
        }
        public var isTailscale: Bool { addresses.contains { $0.hasPrefix("100.") } }

        public init(name: String = "", serviceName: String = "", hostName: String? = nil,
                    addresses: [String] = [], port: Int = 0, txtRecord: [String: String] = [:]) {
            self.name = name
            self.serviceName = serviceName
            self.hostName = hostName
            self.addresses = addresses
            self.port = port
            self.txtRecord = txtRecord
        }
    }

    public func startScanning() { /* no-op on non-macOS */ }
    public func stopScanning() { /* no-op on non-macOS */ }
    public func filteredDevices(localHostName: String = "") -> [DiscoveredDevice] { [] }
}
#endif