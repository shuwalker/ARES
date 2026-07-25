import Foundation
import XCTest
@testable import ARES

final class WebUIServerManagerTests: XCTestCase {
    func testGatewayEnvironmentMatchesFastAPIContract() {
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: ["UNCHANGED": "yes"],
            gatewayURL: "http://gateway.example:8642",
            gatewayAPIKey: "gateway-secret",
            jrosURL: "http://jros.example:8643",
            jrosAPIKey: "jros-secret"
        )

        XCTAssertEqual(environment["ARES_API_URL"], "http://gateway.example:8642")
        XCTAssertEqual(environment["ARES_WEBUI_GATEWAY_BASE_URL"], "http://gateway.example:8642")
        XCTAssertEqual(environment["ARES_WEBUI_GATEWAY_API_KEY"], "gateway-secret")
        XCTAssertEqual(environment["ARES_JROS_GATEWAY_URL"], "http://jros.example:8643")
        XCTAssertEqual(environment["ARES_JROS_GATEWAY_KEY"], "jros-secret")
        XCTAssertEqual(environment["UNCHANGED"], "yes")
    }

    func testLocalGatewayURLDoesNotForceRemoteHealthProbing() {
        // A loopback gateway URL must not export ARES_API_URL — that flips the
        // controller's agent health into remote-HTTP probing and skips the
        // local PID/state-file detection, reporting a healthy local gateway
        // as permanently down (no HTTP health port exists in local installs).
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: [
                "ARES_API_URL": "http://localhost:8642",
                "ARES_WEBUI_GATEWAY_BASE_URL": "http://localhost:8642",
            ],
            gatewayURL: "http://localhost:8642",
            gatewayAPIKey: "",
            jrosURL: "http://127.0.0.1:8643",
            jrosAPIKey: ""
        )

        XCTAssertNil(environment["ARES_API_URL"])
        XCTAssertNil(environment["ARES_WEBUI_GATEWAY_BASE_URL"])
        // JROS gateway URL is a real local HTTP service — always exported.
        XCTAssertEqual(environment["ARES_JROS_GATEWAY_URL"], "http://127.0.0.1:8643")

        XCTAssertTrue(WebUIServerManager.isLocalGatewayURL("http://127.0.0.1:8642"))
        XCTAssertTrue(WebUIServerManager.isLocalGatewayURL("http://localhost:8642"))
        XCTAssertFalse(WebUIServerManager.isLocalGatewayURL("http://gateway.example:8642"))
        XCTAssertFalse(WebUIServerManager.isLocalGatewayURL("https://ares.tailnet.example"))
    }

    func testEmptyGatewayKeysDoNotLeakInheritedCredentials() {
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: [
                "ARES_WEBUI_GATEWAY_API_KEY": "stale-key",
                "ARES_JROS_GATEWAY_KEY": "stale-jros",
            ],
            gatewayURL: "http://127.0.0.1:8642",
            gatewayAPIKey: "",
            jrosURL: "http://127.0.0.1:8643",
            jrosAPIKey: ""
        )

        XCTAssertNil(environment["ARES_WEBUI_GATEWAY_API_KEY"])
        XCTAssertNil(environment["ARES_JROS_GATEWAY_KEY"])
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

        let installerPython = try makeExecutable("venv/bin/python")
        XCTAssertEqual(
            WebUIServerManager.pythonExecutable(in: temporaryDirectory),
            installerPython,
            "The installer-created venv must take precedence when both layouts exist"
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
        XCTAssertEqual(candidates[0].path, "/workspace/webui")
        XCTAssertEqual(candidates[1].path, "/tmp/isolated-ares/webui")
        XCTAssertEqual(candidates[2].path, "/Users/example/.ares/webui")
    }

    func testPortReclamationRecognizesCurrentFastAPIProcessOnly() {
        XCTAssertTrue(WebUIServerManager.isManagedWebUICommand(
            "python -m uvicorn fastapi_app.main:app --port 8787"
        ))
        // Do NOT match generic server.py — that kills unrelated servers.
        XCTAssertFalse(WebUIServerManager.isManagedWebUICommand("python server.py"))
        XCTAssertFalse(WebUIServerManager.isManagedWebUICommand("python -m http.server 8787"))
        XCTAssertFalse(WebUIServerManager.isManagedWebUICommand("uvicorn another_app:app"))
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
