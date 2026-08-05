"""Canonical external-runtime router contracts."""
from __future__ import annotations

from types import SimpleNamespace

import pytest

from api.backend_selector import VALID_BACKENDS, normalize_backend
from api.providers.agentic_backend import AgenticBackend
from api.providers.jaeger.backend import JaegerBackend
from api.backends.router import get_default_router, BackendRouter
from api.backends.cli_backends import BackendRegistry


def test_router_contains_only_external_execution_backends():
    router = get_default_router()

    assert "ares" not in router.backends
    assert "ares_local" not in router.backends
    assert "hybrid" not in router.backends
    # The router only returns available backends. Check that registered
    # backends are a subset of VALID_BACKENDS (not an exact match, since
    # some may be unavailable and app automation backends are separate).
    for name in router.backends:
        if name.endswith("_app"):
            continue  # App automation backends are a separate category
        assert name in VALID_BACKENDS, f"{name} not in VALID_BACKENDS"
    assert "jaeger_local" in BackendRegistry._backends


@pytest.mark.parametrize("backend_key", VALID_BACKENDS)
def test_external_backends_conform_to_contract(backend_key):
    """Every registered backend must conform to AgenticBackend contract."""
    # Instantiate from the registry (not the router, which filters by availability)
    cls = BackendRegistry._backends.get(backend_key)
    if cls is None:
        pytest.skip(f"{backend_key} not in registry (may be a legacy name)")

    backend = cls()
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
    assert normalize_backend("jaeger") == "jaeger_local"
    assert normalize_backend("jros_local") == "jaeger_local"

    with pytest.raises(LookupError):
        get_default_router().select_worker("missing")


def test_app_automation_requires_target_application(monkeypatch):
    from api.backends import cli_backends

    backend = cli_backends.AppAutomationBackend("Missing App", ["type_message"])
    monkeypatch.setattr("shutil.which", lambda _name: "/usr/bin/osascript")
    monkeypatch.setattr(
        "subprocess.run",
        lambda *args, **kwargs: SimpleNamespace(returncode=1),
    )

    assert backend.is_available() is False


def test_hermes_probe_reports_hermes_version_line(monkeypatch):
    from api.providers.hermes import backend as hermes

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
