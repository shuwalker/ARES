import XCTest
import ARESCore

/// Contract tests for the real implementations the app actually ships.
///
/// The native provider layer (FileSystemIdentity, FileSystemOwnerModelProvider,
/// FileSystemWorkflow, SQLiteMemoryStore) was removed when the macOS app became
/// a WKWebView shell over webui/ — those tests were cut with it (originals
/// preserved in the Desktop retirement archive alongside the providers).
final class ARESConfigurationTests: XCTestCase {
    func testMalformedURLsFallBackToDefaults() {
        let config = ARESConfiguration.shared
        let savedGateway = config.gatewayURL
        let savedOllama = config.ollamaURL
        defer {
            config.gatewayURL = savedGateway
            config.ollamaURL = savedOllama
        }

        // The gateway has no default endpoint — an unparseable value yields nil
        // rather than silently pointing the app at some assumed local port.
        config.gatewayURL = "not a url at all"
        config.ollamaURL = ""
        XCTAssertNil(config.gatewayBaseURL)
        XCTAssertEqual(config.ollamaBaseURL.absoluteString, "http://localhost:11434")
    }

    func testCustomURLsParse() {
        let config = ARESConfiguration.shared
        let saved = config.gatewayURL
        defer { config.gatewayURL = saved }

        config.gatewayURL = "http://198.51.100.11:8642"
        XCTAssertEqual(config.gatewayBaseURL?.host, "198.51.100.11")
        XCTAssertEqual(config.gatewayBaseURL?.port, 8642)
    }
}
