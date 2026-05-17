import Foundation

final class SecondBrainService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func searchSecondBrain(
        query: String,
        limit: Int = 10,
        connection: ConnectionProfile
    ) async throws -> [SecondBrainResult] {
        let script = try RemotePythonScript.wrap(
            SecondBrainSearchRequest(
                query: query,
                limit: limit,
                hermesHome: connection.remoteHermesHomePath
            ),
            body: searchBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: SecondBrainSearchResponse.self
        )

        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.message ?? "Unknown Second Brain search error")
        }

        return response.items
    }

    private var searchBody: String {
        """
        import json
        import os
        import pathlib
        import sys

        def lancedb_search(query, limit=10):
            try:
                import lancedb
            except ImportError:
                return None, "lancedb is not installed on the remote host."

            home = pathlib.Path.home()
            hermes_home = resolved_hermes_home()
            db_path = hermes_home / "second_brain_lancedb" / "documents.lance"

            if not db_path.exists():
                return None, f"No LanceDB found at {db_path}"

            try:
                db = lancedb.connect(str(db_path.parent))
                table = db.open_table("documents")
                results = table.search(query).limit(limit).to_list()
            except Exception as exc:
                return None, str(exc)

            items = []
            for row in results:
                items.append({
                    "id": str(row.get("id", "")),
                    "title": str(row.get("title", "") or row.get("source", "Untitled")),
                    "content": str(row.get("content", "") or row.get("text", "") or ""),
                    "source": str(row.get("source", "") or row.get("file_path", "") or ""),
                    "relevance_score": float(row.get("_distance", 0.0) if "_distance" in row else row.get("score", 0.0)),
                })
            return items, None

        request = payload
        query = normalize_text(request.get("query"))
        if not query:
            fail("Search query is required.")

        limit = int(request.get("limit", 10))
        items, error_message = lancedb_search(query, limit)

        if error_message is not None:
            print(json.dumps({
                "ok": False,
                "items": [],
                "total_count": 0,
                "message": error_message,
            }, ensure_ascii=False))
            sys.exit(0)

        print(json.dumps({
            "ok": True,
            "items": items,
            "total_count": len(items),
        }, ensure_ascii=False))
        """
    }
}
