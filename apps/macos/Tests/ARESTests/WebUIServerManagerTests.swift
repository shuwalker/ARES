import Foundation
import XCTest
@testable import ARES

final class WebUIServerManagerTests: XCTestCase {
    func testExplicitWebUIDirectoryPrecedesDiscoveryCandidates() {
        let explicit = URL(fileURLWithPath: "/opt/ares/webui")
        let candidates = WebUIServerManager.webUICandidates(
            resourceURL: URL(fileURLWithPath: "/Applications/ARES.app/Contents/Resources"),
            executableURL: URL(fileURLWithPath: "/Applications/ARES.app/Contents/MacOS/ARES"),
            homeDirectory: URL(fileURLWithPath: "/Users/tester"),
            environment: ["ARES_WEBUI_DIR": explicit.path],
            currentDirectory: "/tmp"
        )
        XCTAssertEqual(candidates.first, explicit)
    }

    func testPythonDiscoveryPrefersCanonicalDotVenv() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-python-precedence-\(UUID().uuidString)")
        let dotVenv = root.appendingPathComponent(".venv/bin/python")
        let legacyVenv = root.appendingPathComponent("venv/bin/python")
        try FileManager.default.createDirectory(
            at: dotVenv.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyVenv.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: dotVenv.path, contents: Data())
        FileManager.default.createFile(atPath: legacyVenv.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dotVenv.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: legacyVenv.path)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(WebUIServerManager.pythonExecutable(in: root), dotVenv)
    }

    func testGatewayEnvironmentMatchesFastAPIContract() {
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: ["UNCHANGED": "yes"],
            hermesURL: "http://gateway.example:8642",
            hermesAPIKey: "hermes-secret",
            jrosURL: "http://jros.example:8643",
            jrosAPIKey: "jros-secret"
        )

        XCTAssertEqual(environment["ARES_API_URL"], "http://gateway.example:8642")
        XCTAssertEqual(environment["ARES_WEBUI_GATEWAY_BASE_URL"], "http://gateway.example:8642")
        XCTAssertEqual(environment["ARES_WEBUI_GATEWAY_API_KEY"], "hermes-secret")
        XCTAssertEqual(environment["ARES_JAEGER_GATEWAY_URL"], "http://jros.example:8643")
        XCTAssertEqual(environment["ARES_JAEGER_GATEWAY_KEY"], "jros-secret")
        XCTAssertNil(environment["ARES_JROS_GATEWAY_URL"])
        XCTAssertNil(environment["ARES_JROS_GATEWAY_KEY"])
        XCTAssertEqual(environment["UNCHANGED"], "yes")
    }

    func testLocalGatewayURLDoesNotForceRemoteHealthProbing() {
        // A loopback Hermes URL must not export ARES_API_URL — that flips the
        // controller's agent health into remote-HTTP probing and skips the
        // local PID/state-file detection, reporting a healthy local gateway
        // as permanently down (no HTTP health port exists in local installs).
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: [
                "ARES_API_URL": "http://localhost:8642",
                "ARES_WEBUI_GATEWAY_BASE_URL": "http://localhost:8642",
            ],
            hermesURL: "http://localhost:8642",
            hermesAPIKey: "",
            jrosURL: "http://127.0.0.1:8643",
            jrosAPIKey: ""
        )

        XCTAssertNil(environment["ARES_API_URL"])
        XCTAssertNil(environment["ARES_WEBUI_GATEWAY_BASE_URL"])
        // Jaeger AI gateway URL is a real local HTTP service — always exported.
        XCTAssertEqual(environment["ARES_JAEGER_GATEWAY_URL"], "http://127.0.0.1:8643")

        XCTAssertTrue(WebUIServerManager.isLocalGatewayURL("http://127.0.0.1:8642"))
        XCTAssertTrue(WebUIServerManager.isLocalGatewayURL("http://localhost:8642"))
        XCTAssertFalse(WebUIServerManager.isLocalGatewayURL("http://gateway.example:8642"))
        XCTAssertFalse(WebUIServerManager.isLocalGatewayURL("https://ares.tailnet.example"))
    }

    func testEmptyGatewayKeysDoNotLeakInheritedCredentials() {
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: [
                "ARES_WEBUI_GATEWAY_API_KEY": "stale-hermes",
                "ARES_JROS_GATEWAY_KEY": "stale-jros",
                "ARES_JAEGER_GATEWAY_KEY": "stale-jaeger",
            ],
            hermesURL: "http://127.0.0.1:8642",
            hermesAPIKey: "",
            jrosURL: "http://127.0.0.1:8643",
            jrosAPIKey: ""
        )

        XCTAssertNil(environment["ARES_WEBUI_GATEWAY_API_KEY"])
        XCTAssertNil(environment["ARES_JROS_GATEWAY_KEY"])
        XCTAssertNil(environment["ARES_JAEGER_GATEWAY_KEY"])
    }

    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-webui-manager-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testWebUIDiscoveryRequiresFastAPIEntrypoint() throws {
        let legacyEntrypoint = temporaryDirectory.appendingPathComponent("server.py")
        try Data().write(to: legacyEntrypoint)
        XCTAssertFalse(WebUIServerManager.containsWebUI(at: temporaryDirectory))

        let fastAPIEntrypoint = temporaryDirectory
            .appendingPathComponent(WebUIServerManager.webUIEntrypoint)
        try FileManager.default.createDirectory(
            at: fastAPIEntrypoint.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: fastAPIEntrypoint)
        XCTAssertTrue(WebUIServerManager.containsWebUI(at: temporaryDirectory))
    }

    func testPythonDiscoverySupportsInstallerAndDotVenvLayouts() throws {
        XCTAssertNil(WebUIServerManager.pythonExecutable(in: temporaryDirectory))

        let dotVenvPython = try makeExecutable(".venv/bin/python")
        XCTAssertEqual(
            WebUIServerManager.pythonExecutable(in: temporaryDirectory),
            dotVenvPython
        )

        _ = try makeExecutable("venv/bin/python")
        XCTAssertEqual(
            WebUIServerManager.pythonExecutable(in: temporaryDirectory),
            dotVenvPython,
            "The dependency-complete canonical .venv must take precedence over a stale legacy venv"
        )
    }

    func testExplicitAresHomePrecedesDefaultInstall() {
        let candidates = WebUIServerManager.webUICandidates(
            resourceURL: nil,
            executableURL: nil,
            homeDirectory: URL(fileURLWithPath: "/Users/example"),
            environment: ["ARES_HOME": "/tmp/isolated-ares"],
            currentDirectory: "/workspace"
        )
        XCTAssertEqual(candidates[0].path, "/workspace/services/controller")
        XCTAssertEqual(candidates[1].path, "/workspace/webui") // legacy
        XCTAssertEqual(candidates[2].path, "/tmp/isolated-ares/services/controller")
        XCTAssertEqual(candidates[3].path, "/tmp/isolated-ares/webui") // legacy
        XCTAssertEqual(candidates[4].path, "/Users/example/.ares/services/controller")
        XCTAssertEqual(candidates[5].path, "/Users/example/.ares/webui") // legacy
    }

    func testAresHealthResponseRequiresHealthyAresPayload() throws {
        let currentPayload = try JSONSerialization.data(withJSONObject: [
            "service": "ares-webui",
            "status": "ok",
        ])
        XCTAssertTrue(WebUIServerManager.isAresHealthResponse(statusCode: 200, data: currentPayload))

        let upgradePayload = try JSONSerialization.data(withJSONObject: [
            "status": "ok",
            "accept_loop": ["server": "uvicorn"],
        ])
        XCTAssertTrue(WebUIServerManager.isAresHealthResponse(statusCode: 200, data: upgradePayload))

        let unrelatedPayload = try JSONSerialization.data(withJSONObject: ["status": "ok"])
        XCTAssertFalse(WebUIServerManager.isAresHealthResponse(statusCode: 200, data: unrelatedPayload))
        XCTAssertFalse(WebUIServerManager.isAresHealthResponse(statusCode: 503, data: currentPayload))
    }

    private func makeExecutable(_ relativePath: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
        return url
    }
}
