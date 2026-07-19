"""Canonical external-runtime router contracts."""

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
