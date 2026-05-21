import Foundation

// MARK: - Model Types

struct DiscoveredHermesHost: Identifiable, Sendable {
    let id = UUID()
    let displayName: String
    let hostname: String
    let port: Int
    let transport: DiscoveryTransport
    let hermesVersion: String?
}

enum DiscoveryTransport: Sendable, Equatable {
    case directHTTP
    case ssh
    case localhost
}

// MARK: - Service

@MainActor
final class HermesDiscoveryService: ObservableObject {
    @Published var discoveredHosts: [DiscoveredHermesHost] = []
    @Published var isScanning: Bool = false
    @Published var localHermesFound: Bool = false
    @Published var scanSummary: String?

    private var netServiceBrowser: NetServiceBrowser?
    private var bonjourDelegate: BonjourBrowserDelegate?
    private var scanTimeoutTask: Task<Void, Never>?

    // MARK: - Public API

    func startScan() async {
        stopScan()
        isScanning = true
        discoveredHosts = []
        localHermesFound = false
        scanSummary = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.checkLocalhost() }
            group.addTask { await self.scanSSHConfig() }
            await group.waitForAll()
        }

        startBonjourBrowse()

        // Auto-stop Bonjour after 10 seconds
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.finishScan()
        }
    }

    func stopScan() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isScanning = false
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        bonjourDelegate = nil
    }

    private func finishScan() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        isScanning = false
        netServiceBrowser?.stop()
        netServiceBrowser = nil
        bonjourDelegate = nil
        let count = discoveredHosts.count
        if count == 0 {
            scanSummary = L10n.string("Nothing found on this network")
        } else {
            scanSummary = L10n.string("Scan complete — %@ found", "\(count)")
        }
    }

    // MARK: - Tier 1: localhost direct check

    private func checkLocalhost() async {
        let localhostPort = 9119
        let urlString = "http://localhost:\(localhostPort)/api/status"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let version = parseVersion(from: data)
            let host = DiscoveredHermesHost(
                displayName: L10n.string("This Mac (localhost)"),
                hostname: "localhost",
                port: localhostPort,
                transport: .localhost,
                hermesVersion: version
            )
            discoveredHosts.append(host)
            localHermesFound = true
        } catch {
            // Localhost not reachable — that's fine
        }
    }

    // MARK: - Tier 2: Bonjour/mDNS

    private func startBonjourBrowse() {
        let delegate = BonjourBrowserDelegate { [weak self] displayName, hostname, port in
            Task { @MainActor [weak self] in
                await self?.addBonjourHost(displayName: displayName, hostname: hostname, port: port)
            }
        }
        bonjourDelegate = delegate

        let browser = NetServiceBrowser()
        browser.delegate = delegate
        netServiceBrowser = browser
        browser.searchForServices(ofType: "_hermes._tcp.", inDomain: "local.")
    }

    private func addBonjourHost(displayName: String, hostname: String, port: Int) async {
        // Try to fetch version from the resolved host
        let version = await fetchVersion(host: hostname, port: port)

        let host = DiscoveredHermesHost(
            displayName: displayName,
            hostname: hostname,
            port: port,
            transport: .directHTTP,
            hermesVersion: version
        )
        if !discoveredHosts.contains(where: { $0.hostname == hostname }) {
            discoveredHosts.append(host)
        }
    }

    // MARK: - Tier 3: ~/.ssh/config parsing

    private func scanSSHConfig() async {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let sshConfigURL = homeDir.appendingPathComponent(".ssh/config")

        guard let contents = try? String(contentsOf: sshConfigURL, encoding: .utf8) else {
            return
        }

        let parsed = parseSSHConfigHosts(contents)
        for entry in parsed {
            let host = DiscoveredHermesHost(
                displayName: L10n.string("SSH: %@", entry),
                hostname: entry,
                port: 9119,
                transport: .ssh,
                hermesVersion: nil
            )
            if !discoveredHosts.contains(where: { $0.hostname == entry }) {
                discoveredHosts.append(host)
            }
        }
    }

    private func parseSSHConfigHosts(_ contents: String) -> [String] {
        var hosts: [String] = []
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("host ") else { continue }

            let value = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            // Skip wildcards and empty values
            guard !value.isEmpty, !value.contains("*"), !value.contains("?") else { continue }

            // A Host line can have multiple space-separated patterns
            let patterns = value.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            for pattern in patterns where !pattern.contains("*") && !pattern.contains("?") {
                if !hosts.contains(pattern) {
                    hosts.append(pattern)
                }
            }
        }
        return hosts
    }

    // MARK: - Helpers

    private func fetchVersion(host: String, port: Int) async -> String? {
        guard let url = URL(string: "http://\(host):\(port)/api/status") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return parseVersion(from: data)
    }

    private func parseVersion(from data: Data) -> String? {
        guard let json = try? JSONDecoder().decode(StatusVersionSnippet.self, from: data) else {
            return nil
        }
        return json.version
    }
}

// MARK: - Minimal decodable for version sniffing

private struct StatusVersionSnippet: Decodable {
    let version: String?
}

// MARK: - Bonjour delegate bridge

/// Wraps NetServiceBrowser delegate callbacks into a Sendable closure.
/// The delegate is marked @unchecked Sendable because it owns its state
/// (pendingServices) exclusively from the main run loop where NetServiceBrowser
/// delivers all callbacks.
private final class BonjourBrowserDelegate: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    typealias ResolvedCallback = @Sendable (String, String, Int) -> Void
    private let onResolved: ResolvedCallback
    private var pendingServices: [NetService] = []

    init(onResolved: @escaping ResolvedCallback) {
        self.onResolved = onResolved
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        pendingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        // Discovery failed — silently ignore
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let displayName = sender.name
        let hostname = sender.hostName ?? "\(sender.name).local"
        let port = sender.port > 0 ? sender.port : 9119
        onResolved(displayName, hostname, port)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        // Resolution failed — silently ignore
    }
}
