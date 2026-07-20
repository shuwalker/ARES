"""Canonical external-runtime router contracts."""

from types import SimpleNamespace

import pytest

from api.backend_selector import VALID_BACKENDS, normalize_backend
from api.backends.base import AgenticBackend
from api.backends.jros import JROSBackend
from api.backends.router import get_default_router


def test_router_contains_only_external_execution_backends():
    router = get_default_router()

    assert "ares" not in router.backends
    assert "ares_local" not in router.backends
    assert "hybrid" not in router.backends
    assert set(router.backends) == set(VALID_BACKENDS)
    assert isinstance(router.backends["jros_local"], JROSBackend)


@pytest.mark.parametrize("backend_key", VALID_BACKENDS)
def test_external_backends_conform_to_contract(backend_key):
    backend = get_default_router().backends[backend_key]

    assert isinstance(backend, AgenticBackend)
    assert callable(backend.is_available)
    assert callable(backend.run_turn)
    assert callable(backend.health)
    assert callable(backend.get_worker_target)


def test_runtime_selection_has_no_implicit_or_legacy_builtin_fallback():
    assert normalize_backend("") == ""
    assert normalize_backend("ares") == ""
    assert normalize_backend("hybrid") == ""
    assert normalize_backend("hermes") == "hermes_local"

    with pytest.raises(LookupError):
        get_default_router().select_worker("missing")


def test_app_automation_requires_target_application(monkeypatch):
    from api.backends import cli_backends

    backend = cli_backends.AppAutomationBackend("Missing App", ["type_message"])
    monkeypatch.setattr(cli_backends.shutil, "which", lambda _name: "/usr/bin/osascript")
    monkeypatch.setattr(
        cli_backends.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(returncode=1),
    )

    assert backend.is_available() is False


def test_hermes_probe_reports_hermes_version_line(monkeypatch):
    from api.backends import hermes

    monkeypatch.setattr(hermes, "_hermes_cli", lambda: "/tmp/hermes")
    monkeypatch.setattr(
        hermes.subprocess,
        "run",
        lambda *args, **kwargs: SimpleNamespace(
            returncode=0,
            stdout="Hermes Agent v0.18.2\nPython: 3.11\nOpenAI SDK: 2.24.0\n",
        ),
    )
    hermes._HERMES_AVAILABLE_CACHE = None
    hermes._HERMES_VERSION_CACHE = None
    hermes._HERMES_AVAILABLE_TS = 0.0

    available, version = hermes._probe_hermes()

    assert available is True
    assert version == "Hermes Agent v0.18.2"
    assert hermes._available_message(version) == "Hermes Agent v0.18.2 is available."
