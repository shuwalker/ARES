import AppKit
import SwiftUI
import ARESCore

/// Ensures the ARES window becomes visible on launch.
/// SwiftUI WindowGroup on macOS can fail to materialize a window on local builds,
/// especially when NavigationSplitView is the root view. If SwiftUI has not
/// created one, this delegate creates a real NSWindow around the same ARES
/// runtime objects instead of leaving a menu-only process.
@MainActor
final class ARESAppDelegate: NSObject, NSApplicationDelegate {
    private var fallbackWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force regular activation policy — the binary has no .app bundle
        // wrapper, so macOS defaults to BackgroundOnly. Without this the
        // window never receives first responder and the menu bar is empty.
        NSApp.setActivationPolicy(.regular)

        // Delay slightly to let SwiftUI create its WindowGroup first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.forceWindowVisible()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            NodeProcessManager.shared.stopAllNodes()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            forceWindowVisible()
        }
        return true
    }

    private func forceWindowVisible() {
        if let window = NSApp.windows.first(where: { $0.isVisible || $0.title.contains("ARES") || $0.title.isEmpty }) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        createFallbackMainWindow()
    }

    private func createFallbackMainWindow() {
        if let fallbackWindow {
            fallbackWindow.makeKeyAndOrderFront(nil)
            fallbackWindow.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ARESRootView()
            .environmentObject(ARESRuntime.appState)
            .frame(minWidth: 1024, minHeight: 600)
            .preferredColorScheme(.dark)

        let controller = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ARES"
        window.contentViewController = controller
        window.center()
        window.setFrameAutosaveName("ARESMainWindow")
        window.isReleasedWhenClosed = false

        fallbackWindow = window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
