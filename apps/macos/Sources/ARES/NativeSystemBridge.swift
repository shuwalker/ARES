import AppKit
import Foundation
import ServiceManagement
import ARESCore

struct NativeSystemSettings: Codable, Equatable {
    var menuBarEnabled = true
    var launchAtLogin = false
    var quickLaunchEnabled = true
    var quickLaunchShortcut = "command+shift+space"
    var backgroundOperation = true

    enum CodingKeys: String, CodingKey {
        case menuBarEnabled = "menu_bar_enabled"
        case launchAtLogin = "launch_at_login"
        case quickLaunchEnabled = "quick_launch_enabled"
        case quickLaunchShortcut = "quick_launch_shortcut"
        case backgroundOperation = "background_operation"
    }
}

private struct NativeSystemCommand: Codable {
    let contractVersion: Int
    let id: String
    let action: String
    let requestedAtUnix: TimeInterval
    let instanceID: String

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case id
        case action
        case requestedAtUnix = "requested_at_unix"
        case instanceID = "instance_id"
    }
}

private struct NativeRuntimeSnapshot: Codable {
    let contractVersion: Int
    let instanceID: String
    let appPID: Int32
    let heartbeatUnix: TimeInterval
    let capabilities: [String: Bool]
    let effective: NativeSystemSettings
    let serverStatus: String
    let serverRunning: Bool
    let lastAction: [String: String]?

    enum CodingKeys: String, CodingKey {
        case contractVersion = "contract_version"
        case instanceID = "instance_id"
        case appPID = "app_pid"
        case heartbeatUnix = "heartbeat_unix"
        case capabilities
        case effective
        case serverStatus = "server_status"
        case serverRunning = "server_running"
        case lastAction = "last_action"
    }
}

/// Shared-file bridge used because the Web UI can run in Safari as well as in
/// WKWebView. The controller stores desired values; only this native process
/// applies them and reports effective state.
@MainActor
final class NativeSystemBridge {
    static let shared = NativeSystemBridge()

    let instanceID: String
    private(set) var desired = NativeSystemSettings()
    private(set) var effective = NativeSystemSettings()

    private let stateDirectory: URL
    private let fileManager: FileManager
    private var timer: Timer?
    private var applyMenuBar: ((Bool) -> Bool)?
    private var applyQuickLaunch: ((Bool, String) -> Bool)?
    private var applyBackgroundOperation: ((Bool) -> Bool)?
    private var restartServer: (() -> Void)?
    private weak var serverManager: WebUIServerManager?
    private var lastAction: [String: String]?

    init(
        stateDirectory: URL = ARESConfiguration.shared.configDirectory,
        fileManager: FileManager = .default,
        instanceID: String = UUID().uuidString
    ) {
        self.stateDirectory = stateDirectory
        self.fileManager = fileManager
        self.instanceID = instanceID
    }

    var settingsURL: URL { stateDirectory.appendingPathComponent("native-system-settings.json") }
    var runtimeURL: URL { stateDirectory.appendingPathComponent("native-runtime.json") }
    var commandURL: URL { stateDirectory.appendingPathComponent("native-command.json") }

    func start(
        serverManager: WebUIServerManager,
        applyMenuBar: @escaping (Bool) -> Bool,
        applyQuickLaunch: @escaping (Bool, String) -> Bool,
        applyBackgroundOperation: @escaping (Bool) -> Bool,
        restartServer: @escaping () -> Void
    ) {
        self.serverManager = serverManager
        self.applyMenuBar = applyMenuBar
        self.applyQuickLaunch = applyQuickLaunch
        self.applyBackgroundOperation = applyBackgroundOperation
        self.restartServer = restartServer
        ensureStateDirectory()
        desired = readSettings() ?? NativeSystemSettings()
        persistSettings(desired)
        applyDesiredSettings()
        writeRuntimeSnapshot()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        try? fileManager.removeItem(at: runtimeURL)
    }

    func tick() {
        let next = readSettings() ?? desired
        if next != desired {
            desired = next
            applyDesiredSettings()
        }
        processCommand()
        writeRuntimeSnapshot()
    }

    func readSettings() -> NativeSystemSettings? {
        guard let data = try? Data(contentsOf: settingsURL) else { return nil }
        return try? JSONDecoder().decode(NativeSystemSettings.self, from: data)
    }

    private func applyDesiredSettings() {
        effective.menuBarEnabled = applyMenuBar?(desired.menuBarEnabled) ?? false
        effective.quickLaunchEnabled = applyQuickLaunch?(
            desired.quickLaunchEnabled,
            desired.quickLaunchShortcut
        ) ?? false
        effective.quickLaunchShortcut = desired.quickLaunchShortcut
        effective.launchAtLogin = applyLaunchAtLogin(desired.launchAtLogin)

        effective.backgroundOperation = applyBackgroundOperation?(desired.backgroundOperation) ?? false
    }

    private func applyLaunchAtLogin(_ enabled: Bool) -> Bool {
        // SMAppService.mainApp applies only to a packaged .app bundle. A
        // development SwiftPM executable reports unavailable instead of
        // pretending the preference was applied.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return false }
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return SMAppService.mainApp.status == .enabled
        }
        return SMAppService.mainApp.status == .enabled
    }

    private func processCommand() {
        guard let data = try? Data(contentsOf: commandURL),
              let command = try? JSONDecoder().decode(NativeSystemCommand.self, from: data)
        else { return }

        guard command.instanceID == instanceID else {
            try? fileManager.removeItem(at: commandURL)
            lastAction = ["id": command.id, "action": command.action, "status": "stale"]
            return
        }

        // Remove before executing so a controller restart cannot replay it.
        try? fileManager.removeItem(at: commandURL)
        guard command.action == "restart_server" else {
            lastAction = ["id": command.id, "action": command.action, "status": "rejected"]
            return
        }
        lastAction = ["id": command.id, "action": command.action, "status": "accepted"]
        writeRuntimeSnapshot()
        restartServer?()
    }

    private func writeRuntimeSnapshot() {
        let snapshot = NativeRuntimeSnapshot(
            contractVersion: 1,
            instanceID: instanceID,
            appPID: ProcessInfo.processInfo.processIdentifier,
            heartbeatUnix: Date().timeIntervalSince1970,
            capabilities: [
                "menu_bar": true,
                "launch_at_login": Bundle.main.bundleURL.pathExtension == "app",
                "quick_launch": true,
                "background_operation": true,
                "server_restart": true,
            ],
            effective: effective,
            serverStatus: serverManager?.serverHealth ?? "Stopped",
            serverRunning: serverManager?.isRunning ?? false,
            lastAction: lastAction
        )
        guard let data = try? encoded(snapshot) else { return }
        atomicWrite(data, to: runtimeURL)
    }

    private func persistSettings(_ settings: NativeSystemSettings) {
        guard let data = try? encoded(settings) else { return }
        atomicWrite(data, to: settingsURL)
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value) + Data("\n".utf8)
    }

    private func ensureStateDirectory() {
        try? fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
    }

    private func atomicWrite(_ data: Data, to destination: URL) {
        ensureStateDirectory()
        let temporary = stateDirectory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temporary)
        }
    }
}

@MainActor
final class ARESGlobalQuickLaunchMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func apply(
        enabled: Bool,
        shortcut: String,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> Bool {
        stop()
        guard enabled, shortcut.lowercased() == "command+shift+space" else {
            return false
        }

        let matches: (NSEvent) -> Bool = { event in
            event.keyCode == 49
                && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift]
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard matches(event) else { return }
            Task { @MainActor in action() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if matches(event) {
                action()
                return nil
            }
            return event
        }
        return globalMonitor != nil && localMonitor != nil
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }
}
