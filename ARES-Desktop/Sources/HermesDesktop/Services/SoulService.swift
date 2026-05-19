import Foundation

final class SoulService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func fetchSoul(connection: ConnectionProfile) async throws -> String {
        let soulPath = connection.remoteHermesHomePath + "/SOUL.md"
        let script = try RemotePythonScript.wrap(
            SoulRequest(path: soulPath),
            body: """
            import pathlib

            soul_path = pathlib.Path(payload["path"]).expanduser()
            if not soul_path.exists():
                print(json.dumps({"ok": True, "content": ""}))
            else:
                try:
                    content = soul_path.read_text(encoding="utf-8")
                    print(json.dumps({"ok": True, "content": content}))
                except Exception as exc:
                    fail(f"Unable to read SOUL.md: {exc}")
            """
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SoulReadResponse.self
        )
        return response.content ?? ""
    }

    func saveSoul(_ content: String, connection: ConnectionProfile) async throws {
        let soulPath = connection.remoteHermesHomePath + "/SOUL.md"
        let script = try RemotePythonScript.wrap(
            SoulWriteRequest(path: soulPath, content: content),
            body: """
            import pathlib

            soul_path = pathlib.Path(payload["path"]).expanduser()
            soul_path.parent.mkdir(parents=True, exist_ok=True)
            try:
                soul_path.write_text(payload["content"], encoding="utf-8")
                print(json.dumps({"ok": True}))
            except Exception as exc:
                fail(f"Unable to write SOUL.md: {exc}")
            """
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SoulWriteResponse.self
        )
        guard response.ok else {
            throw SoulServiceError.writeFailed
        }
    }
}

// MARK: - Request / Response types

private struct SoulRequest: Encodable {
    let path: String
}

private struct SoulWriteRequest: Encodable {
    let path: String
    let content: String
}

private struct SoulReadResponse: Decodable {
    let ok: Bool
    let content: String?
}

private struct SoulWriteResponse: Decodable {
    let ok: Bool
}

enum SoulServiceError: Error, LocalizedError {
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .writeFailed: "Failed to write SOUL.md to the remote host."
        }
    }
}
