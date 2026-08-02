import Foundation
import XCTest
@testable import ARES

final class NativeSystemBridgeTests: XCTestCase {
    func testSettingsContractUsesStableSnakeCaseKeys() throws {
        let settings = NativeSystemSettings(
            menuBarEnabled: false,
            launchAtLogin: true,
            quickLaunchEnabled: true,
            quickLaunchShortcut: "command+shift+space",
            backgroundOperation: false
        )

        let data = try JSONEncoder().encode(settings)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(payload["menu_bar_enabled"] as? Bool, false)
        XCTAssertEqual(payload["launch_at_login"] as? Bool, true)
        XCTAssertEqual(payload["quick_launch_enabled"] as? Bool, true)
        XCTAssertEqual(payload["quick_launch_shortcut"] as? String, "command+shift+space")
        XCTAssertEqual(payload["background_operation"] as? Bool, false)
    }

    @MainActor
    func testBridgeReadsControllerDesiredSettingsFromIsolatedDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-native-bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let bridge = NativeSystemBridge(
            stateDirectory: directory,
            instanceID: "test-instance"
        )
        let source = """
        {
          "menu_bar_enabled": false,
          "launch_at_login": false,
          "quick_launch_enabled": true,
          "quick_launch_shortcut": "command+shift+space",
          "background_operation": true
        }
        """
        try Data(source.utf8).write(to: bridge.settingsURL)

        let settings = try XCTUnwrap(bridge.readSettings())
        XCTAssertFalse(settings.menuBarEnabled)
        XCTAssertTrue(settings.quickLaunchEnabled)
        XCTAssertTrue(settings.backgroundOperation)
        XCTAssertEqual(bridge.instanceID, "test-instance")
    }
}
