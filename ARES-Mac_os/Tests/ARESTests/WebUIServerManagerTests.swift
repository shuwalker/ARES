import Foundation
import XCTest
@testable import ARES

final class WebUIServerManagerTests: XCTestCase {
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
        XCTAssertEqual(environment["ARES_JROS_GATEWAY_URL"], "http://jros.example:8643")
        XCTAssertEqual(environment["ARES_JROS_GATEWAY_KEY"], "jros-secret")
        XCTAssertEqual(environment["UNCHANGED"], "yes")
    }

    func testEmptyGatewayKeysDoNotLeakInheritedCredentials() {
        let environment = WebUIServerManager.applyingGatewayEnvironment(
            to: [
                "ARES_WEBUI_GATEWAY_API_KEY": "stale-hermes",
                "ARES_JROS_GATEWAY_KEY": "stale-jros",
            ],
            hermesURL: "http://127.0.0.1:8642",
            hermesAPIKey: "",
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
        XCTAssertEqual(candidates[0].path, "/tmp/isolated-ares/webui")
        XCTAssertEqual(candidates[1].path, "/Users/example/.ares/webui")
    }

    func testPortReclamationRecognizesCurrentFastAPIProcessOnly() {
        XCTAssertTrue(WebUIServerManager.isManagedWebUICommand(
            "python -m uvicorn fastapi_app.main:app --port 8787"
        ))
        XCTAssertTrue(WebUIServerManager.isManagedWebUICommand("python server.py"))
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
