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
        let savedHermes = config.hermesURL
        let savedOllama = config.ollamaURL
        defer {
            config.hermesURL = savedHermes
            config.ollamaURL = savedOllama
        }

        config.hermesURL = "not a url at all"
        config.ollamaURL = ""
        XCTAssertEqual(config.hermesBaseURL.absoluteString, "http://localhost:8642")
        XCTAssertEqual(config.ollamaBaseURL.absoluteString, "http://localhost:11434")
    }

    func testCustomURLsParse() {
        let config = ARESConfiguration.shared
        let saved = config.hermesURL
        defer { config.hermesURL = saved }

        config.hermesURL = "http://198.51.100.11:8642"
        XCTAssertEqual(config.hermesBaseURL.host, "198.51.100.11")
        XCTAssertEqual(config.hermesBaseURL.port, 8642)
    }
}
