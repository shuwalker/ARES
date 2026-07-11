import SwiftUI
import AppKit
import WebKit
import ARESCore

@MainActor
@main
struct ARESApp: App {
    @NSApplicationDelegateAdaptor(ARESAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ARESWebView()
                .frame(minWidth: 1024, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ARES") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
        }
    }
}

// MARK: - WKWebView Wrapper

struct ARESWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "ARES/1.0"
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        if let url = URL(string: "http://127.0.0.1:8787") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // WebUI not running yet — show a placeholder
            if (error as NSError).code == -1003 {
                webView.loadHTMLString(fallbackHTML, baseURL: URL(string: "http://127.0.0.1:8787"))
            }
        }
    }

    static let fallbackHTML = """
    <html><body style="background:#101014;color:#fff;font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
    <div style="text-align:center">
    <h1 style="color:#d9b256;font-weight:300">ARES</h1>
    <p style="color:#888">Starting WebUI server…</p>
    <p style="color:#555;font-size:12px">http://127.0.0.1:8787</p>
    </div></body></html>
    """
}

// MARK: - App Delegate

@MainActor
final class ARESAppDelegate: NSObject, NSApplicationDelegate {
    private var webuiProcess: Process?
    private var menuBarController: ARESMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        launchWebUIServer()
        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        webuiProcess?.terminate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - WebUI Server

    private func launchWebUIServer() {
        let webuiDir = findWebUIDir()
        guard let dir = webuiDir else {
            print("[ARES] WebUI directory not found")
            return
        }

        let process = Process()
        process.currentDirectoryURL = dir
        process.executableURL = dir.appendingPathComponent(".venv/bin/python")
        process.arguments = ["server.py"]
        process.environment = [
            "HERMES_WEBUI_HOST": "127.0.0.1",
            "HERMES_WEBUI_PORT": "8787",
            "ARES_WEBUI_RELOAD": "0",
        ]
        // Inherit PATH, HOME, etc.
        var env = ProcessInfo.processInfo.environment
        env["HERMES_WEBUI_HOST"] = "127.0.0.1"
        env["HERMES_WEBUI_PORT"] = "8787"
        env["ARES_WEBUI_RELOAD"] = "0"
        process.environment = env

        do {
            try process.run()
            webuiProcess = process
            print("[ARES] WebUI server started on http://127.0.0.1:8787")
        } catch {
            print("[ARES] Failed to start WebUI server: \(error)")
        }
    }

    private func findWebUIDir() -> URL? {
        // Check relative to the app bundle first
        if let bundlePath = Bundle.main.resourceURL?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() {
            let webuiPath = bundlePath.appendingPathComponent("webui")
            if FileManager.default.fileExists(atPath: webuiPath.appendingPathComponent("server.py").path) {
                return webuiPath
            }
        }
        // Fallback: check ~/GitHub/ARES/webui
        let home = FileManager.default.homeDirectoryForCurrentUser
        let devPath = home.appendingPathComponent("GitHub/ARES/webui")
        if FileManager.default.fileExists(atPath: devPath.appendingPathComponent("server.py").path) {
            return devPath
        }
        return nil
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        menuBarController = ARESMenuBarController()
    }
}

// MARK: - Menu Bar (JROS-style tray)

@MainActor
final class ARESMenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    override init() {
        super.init()
        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "spartan-helmet", accessibilityDescription: "ARES")
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open ARES", action: #selector(openWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "WebUI Status", action: #selector(showStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ARES", action: #selector(terminate), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
        } else {
            let p = NSPopover()
            p.contentViewController = NSHostingController(rootView: MenuBarPopoverView())
            p.behavior = .transient
            p.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            self.popover = p
        }
    }

    @objc private func openWindow() {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showStatus() {
        let task = Process()
        task.launchPath = "/usr/bin/curl"
        task.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "http://127.0.0.1:8787/health"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let code = String(data: data, encoding: .utf8) ?? "?"

        let alert = NSAlert()
        alert.messageText = "ARES WebUI Status"
        alert.informativeText = code == "200" ? "Running on http://127.0.0.1:8787" : "Not responding (HTTP \(code))"
        alert.runModal()
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }
}

// MARK: - Menu Bar Popover

struct MenuBarPopoverView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "spartan-helmet")
                .font(.largeTitle)
                .foregroundColor(Color(red: 0.85, green: 0.70, blue: 0.35))
            Text("ARES")
                .font(.headline)
            Text("http://127.0.0.1:8787")
                .font(.caption)
                .foregroundColor(.secondary)
            Divider()
            Button("Open WebUI") {
                NSWorkspace.shared.open(URL(string: "http://127.0.0.1:8787")!)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(width: 200)
    }
}
