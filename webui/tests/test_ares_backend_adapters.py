import pytest
from api.backends.base import AgenticBackend
from api.backends.ares import AresBackend
from api.backends.jros import JROSBackend
from api.backends.hybrid import HybridBackend
from api.backends.router import get_router, get_default_router


def test_router_contains_all_adapters():
    router = get_default_router()
    assert "ares" in router.backends
    assert "jros" in router.backends
    assert "hybrid" in router.backends
    
    # Assert type
    assert isinstance(router.backends["ares"], AresBackend)
    assert isinstance(router.backends["jros"], JROSBackend)
    assert isinstance(router.backends["hybrid"], HybridBackend)


@pytest.mark.parametrize("backend_key", ["ares", "jros", "hybrid"])
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


def test_ares_adapter_metadata():
    backend = AresBackend()
    
    # Test health
    h = backend.health()
    assert h["status"] == "ok"
    assert h["latency_ms"] == 0.0
    assert "message" in h
    
    # Test identity projection
    ident = backend.identity_projection()
    assert "name" in ident
    assert "description" in ident
    assert ident["avatar_state"] == "idle"
    
    # Test capabilities
    caps = backend.capabilities()
    assert caps["chat"] is True
    assert caps["tools"] is True
    assert caps["persona"] is False
    assert caps["hybrid"] is False
    
    # Test chat support
    support = backend.chat_session_support()
    assert support["streaming"] is True
    assert support["context_window"] == 32768
    
    # Test tools
    t = backend.tools()
    assert isinstance(t, list)
    
    # Test settings schema
    schema = backend.settings_schema()
    assert schema["type"] == "object"
    assert "properties" in schema


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
