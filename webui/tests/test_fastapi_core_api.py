"""Step 2 contract tests for the modular FastAPI core API."""

from __future__ import annotations

import asyncio
from pathlib import Path

import httpx
import pytest

from fastapi_app.errors import CoreApiError
from fastapi_app.main import create_app
from fastapi_app.request_context import (
    RequestIdentity,
    require_identity,
    require_mutation_identity,
)


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class FakeCoreService:
    def health(self, *, deep=False):
        payload = {
            "status": "ok",
            "sessions": 2,
            "active_streams": 0,
            "uptime_seconds": 12.5,
        }
        if deep:
            payload["checks"] = {"state_dir": {"status": "ok"}}
        return payload, 200

    def agent_health(self):
        return {"alive": False, "reason": "runtime_not_connected"}

    def settings(self, *, profile):
        assert profile in {None, "default"}
        return {
            "bot_name": "Ares",
            "auth_enabled": False,
            "webui_version": "2.0.0",
            "future_setting": True,
        }

    def update_settings(self, update, *, profile):
        payload = self.settings(profile=profile)
        payload.update(update.model_dump(exclude_unset=True))
        return payload

    def sessions(self, *, profile, exclude_hidden, include_archived):
        assert (profile, exclude_hidden, include_archived) == ("default", True, False)
        return {
            "sessions": [
                {
                    "session_id": "session-1",
                    "title": "Today",
                    "workspace": "/tmp/workspace",
                    "active_stream_id": None,
                    "read_only": False,
                }
            ],
            "active_profile": profile,
        }

    def session(self, session_id, *, profile, load_messages, message_limit):
        if session_id == "missing":
            raise CoreApiError(404, "Session not found")
        assert (profile, load_messages, message_limit) == ("default", True, 200)
        return {
            "session": {
                "session_id": session_id,
                "title": "Today",
                "workspace": "/tmp/workspace",
                "messages": [{"role": "assistant", "content": "Ready"}],
                "messages_has_more": False,
            }
        }

    def create_session(self, request, *, profile):
        assert profile == "default"
        return {
            "session": {
                "session_id": "new-session",
                "title": "Untitled",
                "workspace": request.workspace or "/tmp/workspace",
                "profile": request.profile or profile,
                "messages": [],
            }
        }

    def workspaces(self, *, profile):
        assert profile == "default"
        return {
            "workspaces": [{"path": "/tmp/workspace", "name": "Home"}],
            "last": "/tmp/workspace",
            "terminal_remote_backend": False,
        }

    def list_workspace(self, session_id, relative_path, *, profile):
        assert (session_id, relative_path, profile) == ("session-1", ".", "default")
        return {
            "entries": [{"name": "README.md", "path": "README.md", "type": "file"}],
            "path": relative_path,
            "signature": "signature",
        }


@pytest.fixture
def app(tmp_path: Path):
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    application = create_app(frontend_root=frontend, core_service=FakeCoreService())
    application.dependency_overrides[require_identity] = lambda: IDENTITY
    application.dependency_overrides[require_mutation_identity] = lambda: IDENTITY
    return application


def request(app, method: str, path: str, **kwargs) -> httpx.Response:
    async def run() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        cookies = kwargs.pop("cookies", None)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://testserver",
            cookies=cookies,
        ) as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(run())


def test_health_contract_is_public_and_supports_deep_check(app):
    response = request(app, "GET", "/health?deep=1")

    assert response.status_code == 200
    assert response.json()["checks"]["state_dir"]["status"] == "ok"


def test_api_health_alias_preserves_namespaced_contract(app):
    response = request(app, "GET", "/api/health")

    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_legacy_adapter_inventory_handles_app_automation_backends(app, monkeypatch):
    # A configured instance without an optional JROS source checkout used to
    # abort the entire inventory while resolving its identity projection.
    monkeypatch.setenv("ARES_JROS_INSTANCE", "inventory-test")
    monkeypatch.delenv("ARES_JROS_DIR", raising=False)
    response = request(app, "GET", "/api/ares/adapters")

    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["gemini_antigravity"]["label"] == "Gemini (Antigravity IDE)"
    assert isinstance(payload["gemini_antigravity"]["available"], bool)
    assert payload["jros_local"]["available"] is False
    assert payload["jros_local"]["health"]["status"] == "degraded"


def test_agent_health_preserves_runtime_disconnected_state(app):
    response = request(app, "GET", "/api/health/agent")

    assert response.status_code == 200
    assert response.json() == {"alive": False, "reason": "runtime_not_connected"}


def test_settings_read_preserves_extensible_fields(app):
    response = request(app, "GET", "/api/settings")

    assert response.status_code == 200
    assert response.json()["future_setting"] is True


def test_settings_update_is_strict_and_normalizes_name(app):
    response = request(app, "POST", "/api/settings", json={"bot_name": "  Kinni  "})

    assert response.status_code == 200
    assert response.json()["bot_name"] == "Kinni"

    rejected = request(
        app,
        "POST",
        "/api/settings",
        json={"bot_name": "Ares", "password_hash": "must-not-pass"},
    )
    assert rejected.status_code == 400
    assert rejected.json()["error"] == "Invalid request"

    status_rejected = request(
        app,
        "POST",
        "/api/settings",
        json={"auth_enabled": True, "webui_version": "forged"},
    )
    assert status_rejected.status_code == 400


def test_settings_update_accepts_complete_local_profile(app):
    response = request(
        app,
        "POST",
        "/api/settings",
        json={
            "owner_name": "Matthew",
            "bot_name": "Ares",
            "local_profile_voice": "disabled",
            "local_profile_reachability": "private-network",
            "context_store_enabled": True,
        },
    )

    assert response.status_code == 200
    assert response.json()["owner_name"] == "Matthew"
    assert response.json()["local_profile_voice"] == "disabled"
    assert response.json()["local_profile_reachability"] == "private-network"
    assert response.json()["context_store_enabled"] is True

    rejected = request(
        app,
        "POST",
        "/api/settings",
        json={"local_profile_reachability": "public-internet"},
    )
    assert rejected.status_code == 400


def test_upload_and_transcription_routes_parse_bounded_multipart(app, monkeypatch):
    captured = {}

    def save_upload(session_id, filename, content):
        captured["upload"] = (session_id, filename, content)
        return {"filename": filename, "path": "/tmp/photo.png", "size": len(content)}

    def transcribe(filename, content):
        captured["transcribe"] = (filename, content)
        return {"ok": True, "transcript": "hello ARES"}

    monkeypatch.setattr("api.upload.save_session_upload", save_upload)
    monkeypatch.setattr("api.upload.transcribe_upload", transcribe)

    uploaded = request(
        app,
        "POST",
        "/api/upload",
        data={"session_id": "session-1"},
        files={"file": ("photo.png", b"image-bytes", "image/png")},
    )
    transcript = request(
        app,
        "POST",
        "/api/transcribe",
        files={"file": ("voice.webm", b"audio-bytes", "audio/webm")},
    )

    assert uploaded.status_code == 200
    assert uploaded.json()["filename"] == "photo.png"
    assert captured["upload"] == ("session-1", "photo.png", b"image-bytes")
    assert transcript.status_code == 200
    assert transcript.json()["transcript"] == "hello ARES"
    assert captured["transcribe"] == ("voice.webm", b"audio-bytes")


def test_upload_rejects_missing_file_without_touching_service(app):
    boundary = "ares-test-boundary"
    content = (
        f"--{boundary}\r\n"
        'Content-Disposition: form-data; name="session_id"\r\n\r\n'
        "session-1\r\n"
        f"--{boundary}--\r\n"
    ).encode()
    response = request(
        app,
        "POST",
        "/api/upload",
        content=content,
        headers={"content-type": f"multipart/form-data; boundary={boundary}"},
    )

    assert response.status_code == 400
    assert response.json()["error"] == "No file field in request"


def test_workspace_upload_routes_all_files_through_scoped_service(app, monkeypatch):
    captured = {}

    def save_workspace(session_id, path, files):
        captured.update(session_id=session_id, path=path, files=files)
        return {"files": [{"filename": value[0]} for value in files.values()], "count": len(files)}

    monkeypatch.setattr("api.upload.save_workspace_upload", save_workspace)

    response = request(
        app,
        "POST",
        "/api/workspace/upload",
        data={"session_id": "session-1", "path": "notes"},
        files={
            "first": ("one.md", b"one", "text/markdown"),
            "second": ("two.md", b"two", "text/markdown"),
        },
    )

    assert response.status_code == 200
    assert response.json()["count"] == 2
    assert captured["session_id"] == "session-1"
    assert captured["path"] == "notes"


def test_skills_routes_use_profile_scoped_service_contracts(app, monkeypatch):
    calls = []
    monkeypatch.setattr(
        "api.skills_store.list_skills",
        lambda category=None: {"skills": [{"name": "terminal", "category": category}]},
    )
    monkeypatch.setattr(
        "api.skills_store.save_skill",
        lambda name, content, category="": calls.append((name, content, category))
        or {"ok": True, "name": name, "path": "/tmp/SKILL.md"},
    )

    listed = request(app, "GET", "/api/skills?category=engineering")
    saved = request(
        app,
        "POST",
        "/api/skills/save",
        json={"name": "terminal", "content": "# Terminal", "category": "engineering"},
    )

    assert listed.status_code == 200
    assert listed.json()["skills"][0]["category"] == "engineering"
    assert saved.status_code == 200
    assert calls == [("terminal", "# Terminal", "engineering")]


def test_notes_search_keeps_profile_scope_inside_worker_thread(app, monkeypatch):
    def search_notes(query, source, limit):
        from api.profiles import get_active_profile_name

        return {
            "source": source,
            "query": query,
            "limit": limit,
            "profile": get_active_profile_name(),
            "results": [],
        }

    monkeypatch.setattr("api.notes_store.search_notes", search_notes)

    response = request(app, "GET", "/api/notes/search?q=architecture&limit=4")

    assert response.status_code == 200
    assert response.json() == {
        "source": "joplin",
        "query": "architecture",
        "limit": 4,
        "profile": "default",
        "results": [],
    }


def test_schedule_routes_keep_profile_scope_inside_worker_thread(app, monkeypatch):
    def list_schedules(*, all_profiles=False):
        from api.profiles import get_active_profile_name

        return {
            "jobs": [],
            "all_profiles": all_profiles,
            "active_profile": get_active_profile_name(),
            "other_profile_count": 0,
        }

    monkeypatch.setattr("api.schedules_store.list_schedules", list_schedules)

    response = request(app, "GET", "/api/crons?all_profiles=1")

    assert response.status_code == 200
    assert response.json()["all_profiles"] is True
    assert response.json()["active_profile"] == "default"


def test_schedule_output_and_recent_routes_preserve_legacy_query_defaults(app, monkeypatch):
    monkeypatch.setattr(
        "api.schedules_store.schedule_outputs",
        lambda job_id, limit: {"job_id": job_id, "limit": limit, "outputs": []},
    )
    monkeypatch.setattr(
        "api.schedules_store.recent_schedules",
        lambda since: {"since": float(since) if str(since).isdigit() else 0.0, "completions": []},
    )

    output = request(app, "GET", "/api/crons/output?job_id=job-1&limit=notanint")
    recent = request(app, "GET", "/api/crons/recent?since=notanumber")

    assert output.status_code == 200
    assert output.json()["limit"] == "notanint"
    assert recent.status_code == 200
    assert recent.json()["since"] == 0.0


def test_kanban_routes_use_shared_service_with_worker_profile_scope(app, monkeypatch):
    def list_boards(parsed):
        from api.profiles import get_active_profile_name

        return {
            "boards": [],
            "current": "default",
            "profile": get_active_profile_name(),
            "query": parsed.query,
            "read_only": False,
        }

    monkeypatch.setattr("api.kanban_bridge._list_boards_payload", list_boards)

    response = request(app, "GET", "/api/kanban/boards?include_archived=1")

    assert response.status_code == 200
    assert response.json()["profile"] == "default"
    assert response.json()["query"] == "include_archived=1"


def test_session_list_and_message_window_contracts(app):
    listed = request(app, "GET", "/api/sessions?exclude_hidden=1")
    loaded = request(app, "GET", "/api/session?session_id=session-1&messages=1&msg_limit=200")

    assert listed.status_code == 200
    assert listed.json()["sessions"][0]["active_stream_id"] is None
    assert loaded.status_code == 200
    assert loaded.json()["session"]["messages"][0]["content"] == "Ready"


def test_session_error_shape_and_new_session_contract(app):
    missing = request(app, "GET", "/api/session?session_id=missing&msg_limit=200")
    created = request(
        app,
        "POST",
        "/api/session/new",
        json={"workspace": "/tmp/workspace", "profile": "default"},
    )

    assert missing.status_code == 404
    assert missing.json() == {"error": "Session not found"}
    assert created.status_code == 200
    assert created.json()["session"]["session_id"] == "new-session"


def test_workspace_contracts(app):
    workspaces = request(app, "GET", "/api/workspaces")
    listing = request(app, "GET", "/api/list?session_id=session-1&path=.")

    assert workspaces.status_code == 200
    assert workspaces.json()["terminal_remote_backend"] is False
    assert listing.status_code == 200
    assert listing.json()["entries"][0]["name"] == "README.md"


def test_unknown_api_route_remains_json_404(app):
    response = request(app, "GET", "/api/not-ported")

    assert response.status_code == 404
    assert response.json() == {"error": "not found"}


def test_session_lifecycle_mutations_use_typed_fastapi_contracts(app, monkeypatch):
    class Session:
        def __init__(self, title: str):
            self.title = title
            self.profile = "default"

        def compact(self):
            return {"session_id": "session-1", "title": self.title}

    monkeypatch.setattr(
        "api.models.get_session",
        lambda _session_id, metadata_only=False: Session("Existing"),
    )

    monkeypatch.setattr(
        "api.session_mutations.rename_session",
        lambda session_id, title: Session(title),
    )
    monkeypatch.setattr(
        "api.session_mutations.clear_session",
        lambda session_id: Session("Untitled"),
    )
    monkeypatch.setattr(
        "api.session_mutations.remove_session_worktree",
        lambda session_id, force=False: {"ok": True, "removed": force},
    )
    monkeypatch.setattr(
        "api.session_mutations.set_session_pinned",
        lambda session_id, pinned=True: Session("Pinned"),
    )
    monkeypatch.setattr(
        "api.session_mutations.set_session_archived",
        lambda session_id, archived=True: Session("Archived"),
    )
    monkeypatch.setattr("api.session_mutations.worktree_retained_payload", lambda session: {})
    monkeypatch.setattr(
        "api.session_mutations.move_session_to_project",
        lambda session_id, project_id: Session("Moved"),
    )
    monkeypatch.setattr("api.models.count_conversation_rounds", lambda session_id, since=None: 7)
    monkeypatch.setattr(
        "api.session_mutations.regenerate_session_title",
        lambda session_id, prefer_latest=False: (Session("Generated"), "ok", "raw"),
    )

    renamed = request(
        app,
        "POST",
        "/api/session/rename",
        json={"session_id": "session-1", "title": "Today"},
    )
    cleared = request(
        app,
        "POST",
        "/api/session/clear",
        json={"session_id": "session-1"},
    )
    removed = request(
        app,
        "POST",
        "/api/session/worktree/remove",
        json={"session_id": "session-1", "force": True},
    )
    pinned = request(
        app,
        "POST",
        "/api/session/pin",
        json={"session_id": "session-1", "pinned": True},
    )
    archived = request(
        app,
        "POST",
        "/api/session/archive",
        json={"session_id": "session-1", "archived": True},
    )
    moved = request(
        app,
        "POST",
        "/api/session/move",
        json={"session_id": "session-1", "project_id": "project-1"},
    )
    rounds = request(
        app,
        "POST",
        "/api/session/conversation-rounds",
        json={"session_id": "session-1", "since": 10},
    )
    regenerated = request(
        app,
        "POST",
        "/api/session/title/regenerate",
        json={"session_id": "session-1", "prefer_latest": True},
    )

    assert renamed.json()["session"]["title"] == "Today"
    assert cleared.json() == {
        "ok": True,
        "session": {"session_id": "session-1", "title": "Untitled"},
    }
    assert removed.json() == {"ok": True, "removed": True}
    assert pinned.json()["session"]["title"] == "Pinned"
    assert archived.json()["session"]["title"] == "Archived"
    assert moved.json()["session"]["title"] == "Moved"
    assert rounds.json()["rounds"] == 7
    assert regenerated.json()["title"] == "Generated"


def test_interaction_mutations_preserve_approval_and_stale_clarify_shapes(app, monkeypatch):
    monkeypatch.setattr(
        "api.route_approvals.respond_approval",
        lambda session_id, approval_id, choice: (
            {"ok": True, "choice": choice, "relayed": True},
            200,
        ),
    )
    approval = request(
        app,
        "POST",
        "/api/approval/respond",
        json={"session_id": "session-1", "approval_id": "approval-1", "choice": "once"},
    )
    monkeypatch.setattr("api.clarify.resolve_clarify_by_id", lambda *_args: False)
    clarify = request(
        app,
        "POST",
        "/api/clarify/respond",
        json={"session_id": "session-1", "clarify_id": "clarify-1", "response": "Yes"},
    )

    assert approval.json() == {"ok": True, "choice": "once", "relayed": True}
    assert clarify.status_code == 409
    assert clarify.json() == {
        "error": "Clarification prompt expired or not found. The agent may have already proceeded.",
        "ok": False,
        "stale": True,
    }


def test_authenticated_core_route_requires_valid_session(tmp_path: Path, monkeypatch):
    import api.auth as auth

    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.setattr(auth, "verify_session", lambda value: value == "valid-session")
    application = create_app(frontend_root=tmp_path, core_service=FakeCoreService())

    denied = request(application, "GET", "/api/settings")
    allowed = request(
        application,
        "GET",
        "/api/settings",
        cookies={auth._resolve_cookie_name(): "valid-session"},
    )

    assert denied.status_code == 401
    assert denied.json() == {"error": "Authentication required"}
    assert allowed.status_code == 200


def test_authenticated_mutation_requires_csrf(tmp_path: Path, monkeypatch):
    import api.auth as auth

    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.setattr(auth, "verify_session", lambda value: value == "valid-session")
    monkeypatch.setattr(
        auth,
        "verify_csrf_token",
        lambda cookie, token: cookie == "valid-session" and token == "valid-csrf",
    )
    application = create_app(frontend_root=tmp_path, core_service=FakeCoreService())
    cookies = {auth._resolve_cookie_name(): "valid-session"}

    denied = request(
        application,
        "POST",
        "/api/settings",
        cookies=cookies,
        json={"bot_name": "Kinni"},
    )
    allowed = request(
        application,
        "POST",
        "/api/settings",
        cookies=cookies,
        headers={auth.CSRF_HEADER_NAME: "valid-csrf"},
        json={"bot_name": "Kinni"},
    )

    assert denied.status_code == 403
    assert denied.json() == {"error": "Invalid CSRF token"}
    assert allowed.status_code == 200
