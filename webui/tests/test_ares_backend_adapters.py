import pytest
from api.backends.base import AgenticBackend
from api.backends.jros import JROSBackend
from api.backends.router import get_router, get_default_router
from api.backend_selector import backend_status, normalize_backend


def test_router_contains_only_jaeger_adapter():
    router = get_default_router()
    assert set(router.backends) == {"jros"}
    assert isinstance(router.backends["jros"], JROSBackend)


def test_legacy_backend_values_migrate_to_jaeger(monkeypatch):
    assert normalize_backend("hermes") == "jros"
    assert normalize_backend("hybrid") == "jros"
    monkeypatch.setattr("api.backend_selector.is_jros_available", lambda: True)
    status = backend_status()
    assert status["conversation_owner"] == "jros"
    assert status["delegated_workers"]["hermes"]["owns_sessions"] is False
    assert status["delegated_workers"]["hermes"]["owns_webui"] is False


@pytest.mark.parametrize("backend_key", ["jros"])
def test_backend_adapters_conform_to_contract(backend_key):
    router = get_default_router()
    backend = router.backends[backend_key]
    
    # Assert subclass
    assert isinstance(backend, AgenticBackend)
    
    # Assert attributes
    assert hasattr(backend, "name")
    assert hasattr(backend, "supports_tools")
    assert hasattr(backend, "supports_persona")
    assert hasattr(backend, "supports_hybrid")
    
    # Assert contract methods exist
    assert callable(getattr(backend, "is_available"))
    assert callable(getattr(backend, "run_turn"))
    assert callable(getattr(backend, "health"))
    assert callable(getattr(backend, "identity_projection"))
    assert callable(getattr(backend, "capabilities"))
    assert callable(getattr(backend, "chat_session_support"))
    assert callable(getattr(backend, "tools"))
    assert callable(getattr(backend, "presence_events"))
    assert callable(getattr(backend, "settings_schema"))

def test_jros_adapter_metadata(monkeypatch):
    backend = JROSBackend()
    
    # Mock JROS availability
    monkeypatch.setattr("api.backend_selector.is_jros_available", lambda: True)
    monkeypatch.setattr("api.jros_gateway_chat.jros_gateway_health", lambda timeout=1.0: {"ok": True})
    assert backend.is_available() is True
    
    h = backend.health()
    assert h["status"] in ("ok", "degraded")
    
    # Test capabilities
    caps = backend.capabilities()
    assert caps["chat"] is True
    assert caps["tools"] is True
    assert caps["persona"] is True
    assert caps["robotics"] is True
    
    # Test chat support
    support = backend.chat_session_support()
    assert support["context_window"] == 8192
