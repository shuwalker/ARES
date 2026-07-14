import SwiftUI
import AppKit
import WebKit
import ARESCore
import SwiftTerm

@MainActor
@main
struct ARESApp: App {
    @NSApplicationDelegateAdaptor(ARESAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ARESMainView()
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        
        Settings {
            ARESSettingsView()
        }
    }
    
    private func openSettings() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}

// MARK: - Main View

struct ARESMainView: View {
    var body: some View {
        // ARES is the product surface. Runtime consoles must attach to the
        // single supervised Companion; they must never spawn another model.
        ARESWebView()
    }
}

// MARK: - WKWebView Wrapper

struct ARESWebView: View {
    @ObservedObject var serverManager = WebUIServerManager.shared
    @ObservedObject var config = ARESConfiguration.shared

    var body: some View {
        if serverManager.serverHealth == "Running (Healthy)" {
            if let url = URL(string: "http://\(config.webuiHost):\(config.webuiPort)") {
                WebViewRepresentable(url: url, serverManager: serverManager)
            } else {
                Text("Invalid Server URL").foregroundColor(.red)
            }
        } else {
            ZStack {
                Color(red: 0.063, green: 0.063, blue: 0.078)
                    .ignoresSafeArea()
                VStack(spacing: 0) {
                    Spacer()
                    Text("✦")
                        .font(.system(size: 52))
                        .foregroundColor(Color(red: 0.85, green: 0.70, blue: 0.35))
                        .padding(.bottom, 12)
                    Text("ARES")
                        .font(.system(size: 32, weight: .light, design: .default))
                        .foregroundColor(.white)
                        .tracking(6)
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                        .colorMultiply(.white)
                        .padding(.bottom, 8)
                    Text(serverManager.isRunning ? serverManager.serverHealth : "Starting up…")
                        .foregroundColor(Color.white.opacity(0.4))
                        .font(.system(size: 12))
                    Spacer().frame(height: 48)
                }
            }
        }
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let url: URL
    @ObservedObject var serverManager: WebUIServerManager

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.applicationNameForUserAgent = "ARES/1.0"
        // Use a non-persistent store so stale service-worker offline pages
        // from previous sessions cannot block the fresh server load.
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        let isHealthy = serverManager.serverHealth == "Running (Healthy)"
        if !isHealthy {
            context.coordinator.hasReloadedForHealthyServer = false
        } else if !context.coordinator.hasReloadedForHealthyServer {
            context.coordinator.hasReloadedForHealthyServer = true
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            nsView.load(request)
            return
        }

        if let currentURL = nsView.url, currentURL.host == url.host, currentURL.port == url.port {
            // Keep current page, do not reload
        } else {
            nsView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable
        var hasReloadedForHealthyServer = false

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        private var pollingTimer: DispatchSourceTimer? = nil

        deinit {
            pollingTimer?.cancel()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            showFallback(webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            showFallback(webView)
        }

        private func showFallback(_ webView: WKWebView) {
            let host = parent.url.host ?? "127.0.0.1"
            let port = parent.url.port ?? 8787
            let fallbackHTML = """
            <html><body style="background:#101014;color:#fff;font-family:system-ui;display:flex;align-items:center;justify-content:center;height:100vh;margin:0">
            <div style="text-align:center">
            <h1 style="color:#d9b256;font-weight:300">ARES</h1>
            <p style="color:#888">Waiting for WebUI server to respond…</p>
            <p style="color:#555;font-size:12px">http://\(host):\(port)</p>
            </div></body></html>
            """
            webView.loadHTMLString(fallbackHTML, baseURL: parent.url)
            startPollingForRecovery(webView: webView)
        }

        private func startPollingForRecovery(webView: WKWebView) {
            pollingTimer?.cancel()
            
            let checkURL = self.parent.url.appendingPathComponent("health")
            let mainURL = self.parent.url
            
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            timer.schedule(deadline: .now(), repeating: 2.0)
            timer.setEventHandler { [weak self, weak webView] in
                guard let self = self, let webView = webView else { return }
                
                var request = URLRequest(url: checkURL)
                request.timeoutInterval = 1.0
                
                URLSession.shared.dataTask(with: request) { [weak self, weak webView] _, response, error in
                    if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                        DispatchQueue.main.async {
                            guard let self = self, let webView = webView else { return }
                            self.pollingTimer?.cancel()
                            self.pollingTimer = nil
                            webView.load(URLRequest(url: mainURL))
                        }
                    }
                }.resume()
            }
            timer.resume()
            self.pollingTimer = timer
        }
    }
}

// MARK: - App Delegate

@MainActor
final class ARESAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: ARESMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let config = ARESConfiguration.shared
        if config.autoLaunchOnStart {
            Task {
                await WebUIServerManager.shared.start()
            }
        }
        setupMenuBar()

        // Open the main window on first launch so the onboarding wizard is visible.
        // The window is closed by the user, not hidden — subsequent launches stay
        // tray-only until the user clicks "Open ARES" from the menu bar.
        openMainWindow()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let window = NSApp.windows.first(where: { $0.title != "" && $0.className != "NSStatusBarWindow" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let visibleWindows = NSApp.windows.filter { $0.isVisible && $0.title != "" && $0.className != "NSStatusBarWindow" }
            if visibleWindows.isEmpty {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WebUIServerManager.shared.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

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
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "shield", accessibilityDescription: "ARES")
            ?? NSImage(systemSymbolName: "gear", accessibilityDescription: "ARES")
        icon?.isTemplate = true
        statusItem?.button?.image = icon
        statusItem?.button?.action = #selector(togglePopover)
        statusItem?.button?.target = self

        let menu = NSMenu()
        // Items need an explicit target: with AppKit's auto-enabling, a nil-target
        // action resolves via the responder chain, this controller isn't in it,
        // and every item renders permanently disabled (greyed out).
        func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
            it.target = self
            return it
        }
        menu.addItem(item("Open ARES", #selector(openWindow), "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("WebUI: Start Server", #selector(startServer), ""))
        menu.addItem(item("WebUI: Stop Server", #selector(stopServer), ""))
        menu.addItem(item("WebUI: Restart Server", #selector(restartServer), ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Settings...", #selector(openSettings), ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(item("Quit ARES", #selector(terminate), "q"))

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
        appDelegate?.openMainWindow()
    }

    private var appDelegate: ARESAppDelegate? {
        NSApp.delegate as? ARESAppDelegate
    }

    @objc private func startServer() {
        Task {
            await WebUIServerManager.shared.start()
        }
    }

    @objc private func stopServer() {
        WebUIServerManager.shared.stop(persistently: true)
    }

    @objc private func restartServer() {
        Task {
            await WebUIServerManager.shared.restart()
        }
    }

    @objc private func openSettings() {
        NSApp.setActivationPolicy(.regular)
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func terminate() {
        NSApp.terminate(nil)
    }
}

// MARK: - Menu Bar Popover

struct MenuBarPopoverView: View {
    @ObservedObject var serverManager = WebUIServerManager.shared
    @ObservedObject var config = ARESConfiguration.shared

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.largeTitle)
                .foregroundColor(Color(red: 0.85, green: 0.70, blue: 0.35))
            
            Text("ARES WebUI Server")
                .font(.headline)
            
            Text("http://\(config.webuiHost):\(config.webuiPort)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Status: \(serverManager.serverHealth)")
                .font(.footnote)
                .foregroundColor(serverManager.isRunning ? .green : .red)
            
            Divider()
            
            HStack {
                if serverManager.isRunning {
                    Button("Open WebUI") {
                        if let url = URL(string: "http://\(config.webuiHost):\(config.webuiPort)") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Start Server") {
                        Task { await serverManager.start() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 220)
    }
}
