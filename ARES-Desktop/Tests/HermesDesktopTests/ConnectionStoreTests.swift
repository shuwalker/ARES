import Foundation
import Testing

@testable import HermesDesktop

@MainActor
struct ConnectionStoreTests {
    @Test
    func missingFilesLoadDefaultStateWithoutPersistenceError() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = ConnectionStore(paths: makeTestAppPaths(root: root))

        #expect(store.connections.isEmpty)
        #expect(store.lastConnectionID == nil)
        #expect(store.workspaceFileBookmarks.isEmpty)
        #expect(store.pinnedSessions.isEmpty)
        #expect(store.persistenceError == nil)
    }

    @Test
    func corruptedConnectionsJSONIsReportedAndIgnored() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = makeTestAppPaths(root: root)
        paths.ensureApplicationSupportDirectory()
        try Data("not-json".utf8).write(to: paths.connectionsURL)

        let store = ConnectionStore(paths: paths)

        #expect(store.connections.isEmpty)
        #expect(store.persistenceError?.contains("Unable to load saved hosts") == true)
    }

    @Test
    func corruptedPreferencesJSONFallsBackToDefaultsAndReportsError() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = makeTestAppPaths(root: root)
        paths.ensureApplicationSupportDirectory()
        try Data("{broken".utf8).write(to: paths.preferencesURL)

        let store = ConnectionStore(paths: paths)

        #expect(store.lastConnectionID == nil)
        #expect(store.terminalTheme == .defaultValue)
        #expect(store.automaticallyChecksForUpdates)
        #expect(store.workspaceFileBookmarks.isEmpty)
        #expect(store.pinnedSessions.isEmpty)
        #expect(store.persistenceError?.contains("Unable to load app preferences") == true)
    }

    @Test
    func savingRecreatesPrunedSupportDirectoryAndAppliesPrivatePermissions() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = makeTestAppPaths(root: root)
        let store = ConnectionStore(paths: paths)
        try FileManager.default.removeItem(at: paths.applicationSupportURL)

        store.lastConnectionID = UUID()
        store.upsert(
            ConnectionProfile(
                label: "Prod",
                sshHost: "example.com",
                sshUser: "alice"
            )
        )

        #expect(FileManager.default.fileExists(atPath: paths.preferencesURL.path))
        #expect(FileManager.default.fileExists(atPath: paths.connectionsURL.path))
        #expect(try posixPermissions(at: paths.preferencesURL) == 0o600)
        #expect(try posixPermissions(at: paths.connectionsURL) == 0o600)
    }
}

private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let number = try #require(attributes[.posixPermissions] as? NSNumber)
    return number.intValue
}
