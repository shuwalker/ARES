import Foundation

final class YouTubePipelineService: @unchecked Sendable {
    private let sshTransport: SSHTransport

    init(sshTransport: SSHTransport) {
        self.sshTransport = sshTransport
    }

    func listPending(connection: ConnectionProfile, limit: Int = 50) async throws -> [YouTubeVideoEntry] {
        let script = try RemotePythonScript.wrap(
            YouTubePipelineRequest(
                status: "pending",
                limit: limit,
                hermesHome: connection.remoteHermesHomePath
            ),
            body: listBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: YouTubePipelineResponse.self
        )

        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.message ?? "Unknown YouTube Pipeline error")
        }

        return response.items
    }

    func approveVideo(connection: ConnectionProfile, videoID: String, title: String? = nil, description: String? = nil, tags: [String]? = nil) async throws {
        let script = try RemotePythonScript.wrap(
            YouTubeVideoApprovalRequest(
                videoID: videoID,
                action: "approve",
                hermesHome: connection.remoteHermesHomePath,
                title: title,
                description: description,
                tags: tags
            ),
            body: approvalBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: YouTubeApprovalResponse.self
        )

        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.message ?? "Unable to approve video")
        }
    }

    func rejectVideo(connection: ConnectionProfile, videoID: String) async throws {
        let script = try RemotePythonScript.wrap(
            YouTubeVideoApprovalRequest(
                videoID: videoID,
                action: "reject",
                hermesHome: connection.remoteHermesHomePath,
                title: nil,
                description: nil,
                tags: nil
            ),
            body: approvalBody
        )

        let response = try await sshTransport.executeJSON(
            on: connection,
            pythonScript: script,
            responseType: YouTubeApprovalResponse.self
        )

        guard response.ok else {
            throw SSHTransportError.invalidResponse(response.message ?? "Unable to reject video")
        }
    }

    private var listBody: String {
        """
        import json
        import os
        import pathlib

        def try_load_pipeline():
            hermes_home = resolved_hermes_home()
            pipeline_dir = hermes_home / "youtube_pipeline"
            if not pipeline_dir.exists():
                return [], f"No YouTube pipeline directory at {pipeline_dir}"

            pending_path = pipeline_dir / "pending.json"
            if not pending_path.exists():
                return [], None

            try:
                with open(pending_path, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
            except Exception as exc:
                return [], str(exc)

            items = []
            if isinstance(data, list):
                items = data
            elif isinstance(data, dict) and "items" in data:
                items = data["items"]
            elif isinstance(data, dict):
                items = list(data.values())

            normalized = []
            for item in items:
                if not isinstance(item, dict):
                    continue
                normalized.append({
                    "id": str(item.get("id", "")),
                    "title": str(item.get("title", "Untitled")),
                    "description": str(item.get("description", "") or ""),
                    "tags": item.get("tags", []) if isinstance(item.get("tags"), list) else [],
                    "thumbnail_url": str(item.get("thumbnail_url", "") or item.get("thumbnail", "") or ""),
                    "status": str(item.get("status", "pending")),
                    "channel_name": str(item.get("channel_name", "") or item.get("channel", "") or ""),
                    "upload_date": str(item.get("upload_date", "") or item.get("date", "") or ""),
                    "scheduled_publish_at": str(item.get("scheduled_publish_at", "") or ""),
                })
            return normalized, None

        request = payload
        limit = int(request.get("limit", 50))
        status_filter = normalize_text(request.get("status"))

        items, error_message = try_load_pipeline()
        if error_message is not None:
            fail(error_message)

        if status_filter:
            items = [item for item in items if item.get("status", "") == status_filter]

        items = items[:limit]

        print(json.dumps({
            "ok": True,
            "items": items,
            "message": None,
        }, ensure_ascii=False))
        """
    }

    private var approvalBody: String {
        """
        import json
        import os
        import pathlib

        def update_pipeline_status(video_id, action, title=None, description=None, tags=None):
            hermes_home = resolved_hermes_home()
            pipeline_dir = hermes_home / "youtube_pipeline"
            pending_path = pipeline_dir / "pending.json"
            approved_path = pipeline_dir / "approved.json"
            rejected_path = pipeline_dir / "rejected.json"

            if not pending_path.exists():
                return False, f"No pending pipeline at {pending_path}"

            try:
                with open(pending_path, "r", encoding="utf-8") as fh:
                    data = json.load(fh)
            except Exception as exc:
                return False, str(exc)

            items = []
            if isinstance(data, list):
                items = data
            elif isinstance(data, dict) and "items" in data:
                items = data["items"]
            elif isinstance(data, dict):
                items = list(data.values())

            found = None
            for item in items:
                if isinstance(item, dict) and str(item.get("id", "")) == video_id:
                    found = item
                    break

            if found is None:
                return False, f"Video {video_id} not found in pending pipeline."

            items.remove(found)
            with open(pending_path, "w", encoding="utf-8") as fh:
                json.dump(items, fh, indent=2, ensure_ascii=False)

            if action == "approve":
                found["status"] = "approved"
                if title is not None:
                    found["title"] = title
                if description is not None:
                    found["description"] = description
                if tags is not None:
                    found["tags"] = tags
                dest = approved_path
            elif action == "reject":
                found["status"] = "rejected"
                dest = rejected_path
            else:
                return False, f"Unknown action: {action}"

            dest.parent.mkdir(parents=True, exist_ok=True)
            existing = []
            if dest.exists():
                try:
                    with open(dest, "r", encoding="utf-8") as fh:
                        existing = json.load(fh)
                        if isinstance(existing, list):
                            pass
                        elif isinstance(existing, dict) and "items" in existing:
                            existing = existing["items"]
                        else:
                            existing = []
                except Exception:
                    existing = []
            existing.append(found)
            with open(dest, "w", encoding="utf-8") as fh:
                json.dump(existing, fh, indent=2, ensure_ascii=False)

            return True, None

        request = payload
        video_id = normalize_text(request.get("video_id"))
        action = normalize_text(request.get("action"))
        if not video_id or not action:
            fail("video_id and action are required.")

        title = normalize_text(request.get("title"))
        description = normalize_text(request.get("description"))
        tags = request.get("tags")

        ok, error_message = update_pipeline_status(video_id, action, title, description, tags)
        if not ok:
            fail(error_message or "Unknown error")

        print(json.dumps({
            "ok": True,
            "message": None,
        }, ensure_ascii=False))
        """
    }
}
