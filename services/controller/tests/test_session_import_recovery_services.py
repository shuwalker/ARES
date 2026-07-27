"""Transport-neutral import and compression-recovery contracts."""

from __future__ import annotations

from collections import OrderedDict
from types import SimpleNamespace


class _FakeSession:
    def __init__(self, **values):
        self.__dict__.update(values)
        self.session_id = values.get("session_id", "new-session-1")
        self.messages = values.get("messages", [])
        self.tool_calls = values.get("tool_calls", [])
        self.saved = False

    def save(self, **_kwargs):
        self.saved = True

    def compact(self):
        return dict(self.__dict__)


def test_import_session_export_creates_profile_scoped_session(monkeypatch, tmp_path):
    from api.session_mutations import import_session_export

    cached = OrderedDict()
    monkeypatch.setattr("api.models.Session", _FakeSession)
    monkeypatch.setattr("api.config.SESSIONS", cached)
    monkeypatch.setattr("api.config.DEFAULT_WORKSPACE", tmp_path)
    monkeypatch.setattr("api.workspace.resolve_trusted_workspace", lambda value: tmp_path)
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "work")
    monkeypatch.setattr("api.models._evict_sessions_over_cap", lambda: None)
    monkeypatch.setattr("api.session_events.publish_session_list_changed", lambda *_a, **_k: None)

    session = import_session_export(
        {
            "title": "Imported",
            "messages": [{"role": "user", "content": "hello"}],
            "pinned": True,
        }
    )

    assert session.saved is True
    assert session.profile == "work"
    assert session.pinned is True
    assert cached[session.session_id] is session


def test_compression_recovery_is_idempotent_and_preserves_execution_lane(monkeypatch):
    from api.compression_recovery import build_compression_recovery_payload
    from api.session_mutations import start_compression_recovery

    source = SimpleNamespace(
        session_id="source-1",
        title="Long task",
        workspace="/tmp/workspace",
        model="provider/model",
        model_provider="provider",
        project_id="project-1",
        profile="work",
        personality="concise",
        enabled_toolsets=["terminal"],
        context_length=100_000,
        threshold_tokens=90_000,
        gateway_routing={"mode": "auto"},
        gateway_routing_history=[{"model": "provider/model"}],
        worktree_path="/tmp/worktree",
        worktree_branch="ares/task",
    )
    source.compression_recovery = build_compression_recovery_payload(source)
    cached = OrderedDict()
    existing = [None]
    events = []

    monkeypatch.setattr("api.models.Session", _FakeSession)
    monkeypatch.setattr("api.models.get_session", lambda sid: source)
    monkeypatch.setattr(
        "api.models.find_compression_recovery_session",
        lambda *_a, **_k: existing[0],
    )
    monkeypatch.setattr("api.models._evict_sessions_over_cap", lambda: None)
    monkeypatch.setattr("api.config.SESSIONS", cached)
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "work")
    monkeypatch.setattr("api.profiles._profiles_match", lambda left, right: left == right)
    monkeypatch.setattr("api.session_access.session_is_subagent_view_only", lambda sid: False)
    monkeypatch.setattr("api.workspace.get_last_workspace", lambda: "/tmp/fallback")
    monkeypatch.setattr(
        "api.session_events.publish_session_list_changed",
        lambda reason, **kwargs: events.append((reason, kwargs)),
    )

    created, was_created, action = start_compression_recovery(source.session_id)
    existing[0] = created
    reopened, was_reopened, reopened_action = start_compression_recovery(source.session_id)

    assert was_created is True
    assert was_reopened is False
    assert reopened is created
    assert reopened_action == action
    assert created.messages == []
    assert created.context_messages == []
    assert created.parent_session_id == source.session_id
    assert created.project_id == source.project_id
    assert created.worktree_path == source.worktree_path
    assert created.title == "Long task (focused continuation)"
    assert len(events) == 1
