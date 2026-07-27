"""Regression tests for #5420 profile-aware FastAPI session creation."""

from __future__ import annotations

import threading

import api.models as models


class _Session:
    def __init__(self, session_id: str, profile: str):
        self.session_id = session_id
        self.profile = profile
        self.messages = []

    def compact(self):
        return {"session_id": self.session_id, "profile": self.profile}


def _post_session_new(body: dict, *, profile: str):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    from fastapi_app.request_context import (
        RequestIdentity,
        require_mutation_identity,
    )

    app = create_app()
    app.dependency_overrides[require_mutation_identity] = lambda: RequestIdentity(
        None, profile, False
    )
    with TestClient(app) as client:
        return client.post("/api/session/new", json=body)


def test_session_new_route_is_owned_by_fastapi():
    response = _post_session_new({"prev_session_id": " "}, profile="default")
    assert response.status_code == 400


def test_session_new_ignores_cross_profile_previous_session(monkeypatch):
    created = {}

    monkeypatch.setattr(
        models,
        "get_session",
        lambda _sid, metadata_only=False: _Session("old-from-default", "default"),
    )

    def new_session(**kwargs):
        created.update(kwargs)
        return _Session("new123", kwargs["profile"])

    monkeypatch.setattr(models, "new_session", new_session)
    response = _post_session_new(
        {"profile": "work", "prev_session_id": "old-from-default"},
        profile="work",
    )

    assert response.status_code == 200
    assert response.json()["session"]["session_id"] == "new123"
    assert created["profile"] == "work"


def test_session_new_commits_same_profile_previous_session(monkeypatch):
    committed = threading.Event()
    monkeypatch.setattr(
        models,
        "get_session",
        lambda _sid, metadata_only=False: _Session("same-profile-old", "default"),
    )
    monkeypatch.setattr(
        models,
        "new_session",
        lambda **kwargs: _Session("new456", kwargs["profile"]),
    )
    monkeypatch.setattr(
        "api.session_lifecycle.commit_session_memory",
        lambda session_id: committed.set() if session_id == "same-profile-old" else None,
    )

    response = _post_session_new(
        {"prev_session_id": "same-profile-old"},
        profile="default",
    )

    assert response.status_code == 200
    assert response.json()["session"]["session_id"] == "new456"
    assert committed.wait(2), "previous-session memory commit did not run"
