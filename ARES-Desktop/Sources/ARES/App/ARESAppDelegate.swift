import AppKit

/// Ensures the ARES window becomes visible on launch.
/// SwiftUI WindowGroup on macOS sometimes fails to open a window,
/// especially when NavigationSplitView is the root view.
/// This delegate forces the frontmost window to become key and visible
/// after the app finishes launching.
final class ARESAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Delay slightly to let SwiftUI create its window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.forceWindowVisible()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            forceWindowVisible()
        }
        return true
    }

    private func forceWindowVisible() {
        guard let window = NSApp.windows.first(where: { $0.isVisible || $0.title.contains("ARES") || $0.title.isEmpty }) else {
            // No window at all — trigger New Window command
            NSApp.keyWindow?.makeKeyAndOrderFront(nil)
            return
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}