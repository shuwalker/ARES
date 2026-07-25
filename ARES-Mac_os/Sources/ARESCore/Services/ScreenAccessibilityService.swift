import Foundation
#if canImport(ApplicationServices)
import ApplicationServices
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Result of a permission probe for a macOS system-category capability.
public enum ScreenCapabilityPermission: String, Codable, Sendable {
    /// Permission is granted; the capability can run.
    case granted
    /// Permission has not been granted (user must approve in System Settings).
    case denied
    /// The platform does not support this capability (non-macOS build).
    case unsupported
}

/// A single window in the accessibility/window snapshot.
public struct ScreenWindowInfo: Codable, Equatable, Sendable {
    public let ownerName: String
    public let windowTitle: String?
    public let layer: Int
    public let isOnScreen: Bool

    public init(ownerName: String, windowTitle: String?, layer: Int, isOnScreen: Bool) {
        self.ownerName = ownerName
        self.windowTitle = windowTitle
        self.layer = layer
        self.isOnScreen = isOnScreen
    }
}

/// Reads macOS accessibility / window state so ARES can "see" what the user is
/// doing — only when the OS permission is granted AND the caller has cleared
/// the consent gate. This service performs no capture on its own initiative;
/// callers must hold consent (see `AuthorizationManager`) before invoking it.
public struct ScreenAccessibilityService: Sendable {
    public init() {}

    /// Probe whether the macOS Accessibility permission is granted.
    ///
    /// Does not prompt — returns the current authorization status so ARES can
    /// report the capability as unavailable honestly rather than triggering a
    /// system prompt as a side effect.
    public func accessibilityPermission() -> ScreenCapabilityPermission {
        #if os(macOS)
        return AXIsProcessTrusted() ? .granted : .denied
        #else
        return .unsupported
        #endif
    }

    /// Snapshot the current on-screen windows (owner + title + layer).
    ///
    /// Requires macOS Screen Recording permission to include window titles.
    /// Returns an empty list on platforms without CoreGraphics window services.
    /// The caller is responsible for having obtained user consent first.
    public func windowSnapshot() -> [ScreenWindowInfo] {
        #if os(macOS)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return raw.map { entry in
            ScreenWindowInfo(
                ownerName: (entry[kCGWindowOwnerName as String] as? String) ?? "(unknown)",
                windowTitle: entry[kCGWindowName as String] as? String,
                layer: (entry[kCGWindowLayer as String] as? Int) ?? 0,
                isOnScreen: (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
            )
        }
        #else
        return []
        #endif
    }
}
