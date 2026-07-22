"""JROS Backend Adapter for ARES.

This adapter wraps the ARES-side JROS gateway bridge
(``api.jros_gateway_chat``). JROS itself is never modified.
"""

from __future__ import annotations

from typing import Any, Dict, List, cast

from .base import AgenticBackend


class JROSBackend(AgenticBackend):
    name = "jros_local"
    supports_tools = True
    supports_persona = True

    def is_available(self) -> bool:
        from api.backend_selector import is_jros_available

        return is_jros_available()

    def get_worker_target(self) -> tuple:
        """Return the JROS streaming worker target."""
        from api.jros_gateway_chat import run_jros_streaming

        return run_jros_streaming, False, True

    def get_backend_name(self) -> str:
        return "JROS"

    def health(self) -> Dict[str, Any]:
        from api.jros_gateway_chat import jros_gateway_health
        health_payload = jros_gateway_health(timeout=1.0)
        if health_payload is not None:
            return {
                "status": "ok",
                "latency_ms": 0.0,
                "message": "JROS Gateway reachable",
                "details": health_payload,
            }
        
        # Check local path fallback
        from api.jros_gateway_chat import local_jros_root
        if local_jros_root() is not None:
            return {
                "status": "degraded",
                "latency_ms": 0.0,
                "message": "Gateway offline; falling back to local JROS checkout",
            }
            
        return {
            "status": "error",
            "latency_ms": 0.0,
            "message": "JROS Gateway unreachable and local checkout not found",
        }

    def identity_projection(self) -> Dict[str, Any]:
        from api.jros_paths import jros_instance_name
        instance = jros_instance_name()
        
        if instance:
            from api.persona import load_persona
            persona = load_persona(instance)
            if persona:
                return {
                    "name": persona.get("identity", {}).get("display_name") or persona.get("name") or instance.title(),
                    "description": persona.get("description") or f"JROS character: {instance}",
                    "avatar_state": "idle",
                }
            return {
                "name": instance.title(),
                "description": f"JROS instance: {instance}",
                "avatar_state": "idle",
            }
            
        return {
            "name": "JROS",
            "description": "JROS peer agent runtime",
            "avatar_state": "idle",
        }

    def capabilities(self) -> Dict[str, Any]:
        return {
            "chat": True,
            "tools": self.supports_tools,
            "persona": self.supports_persona,
            "voice": True,
            "embodiment": True,
            "robotics": True,
        }

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 8192, "multimodal": True}

    def tools(self) -> List[Dict[str, Any]]:
        # Returns standard list of JROS/Jaeger bridge command tools
        return [
            {
                "name": "jaeger_bridge_tool",
                "description": "Spawn JROS subprocess tool execution",
                "parameters": {"type": "object", "properties": {}},
            }
        ]

    def settings_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "jros_gateway_url": {
                    "type": "string",
                    "title": "JROS Gateway URL",
                    "default": "http://127.0.0.1:8643",
                },
                "jros_instance_name": {
                    "type": "string",
                    "title": "JROS Instance Name",
                    "default": "lilith",
                },
            },
        }

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        import threading

        from api.jros_gateway_chat import _run_local_jros_turn

        cancel_event = kwargs.get("cancel_event")
        event = cancel_event if hasattr(cancel_event, "is_set") else threading.Event()
        return_text, error, tool_activity = _run_local_jros_turn(
            message,
            session_id,
            cast(Any, event),
        )
        return {"text": return_text, "error": error, "tool_activity": tool_activity}

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        return {
            "available": available,
            "label": "JROS / JaegerAI" if available else "JROS (not found)",
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
            },
            "inventory": self.inventory(),
        }

    def inventory(self) -> Dict[str, Any]:
        """Catalog JaegerAI providers + installed/local models + gateways.

        Scans gateway health, instance config, and ``.jaeger_os/models/*.gguf``.
        """
        from api.backends.catalog import (
            finalize_inventory,
            gateway_entry,
            infer_model_location,
            mcp_entry,
            transport_entry,
        )
        from api.backends.model_discovery import discover_jros_models

        health: dict[str, Any] = {}
        try:
            from api.jros_gateway_chat import jros_gateway_health

            health = jros_gateway_health(timeout=1.0) or {}
        except Exception:
            health = {}

        instance = str(health.get("instance") or "").strip() or None
        booted = bool(health.get("booted"))
        gateway_ok = bool(health.get("ok"))
        discovered = discover_jros_models(instance=instance, gateway_health=health)
        models = list(discovered.get("models") or [])
        providers = list(discovered.get("providers") or [])
        default = discovered.get("default") or {}
        model_id = default.get("model")
        provider = default.get("provider")

        gateway_url = "http://127.0.0.1:8643"
        try:
            schema = self.settings_schema()
            props = (schema.get("properties") or {})
            default_url = (props.get("jros_gateway_url") or {}).get("default")
            if isinstance(default_url, str) and default_url.strip():
                gateway_url = default_url.strip()
        except Exception:
            pass

        transports = [
            transport_entry(
                id="http_gateway",
                kind="http_gateway",
                label="ARES JROS HTTP gateway",
                in_use=True,
                endpoint=f"{gateway_url}/v1/chat/completions",
                notes="Active ARES path: OpenAI-compatible chat completions via jros_gateway.py.",
            ),
            transport_entry(
                id="local_checkout",
                kind="subprocess",
                label="Local JROS checkout fallback",
                in_use=False,
                notes="Used when gateway is offline but a local JROS tree is present.",
            ),
            transport_entry(
                id="mcp",
                kind="mcp",
                label="JROS/Jaeger MCP (if configured)",
                in_use=False,
                notes="Catalog placeholder — declare MCP tools when JROS exposes them; ARES may not consume yet.",
            ),
        ]

        gateways = [
            gateway_entry(
                id="ares_jros_gateway",
                kind="openai_compatible",
                label="ARES jros_gateway",
                endpoint=gateway_url,
                in_use=gateway_ok,
                protocol="openai-chat-completions",
                notes="GET /v1/health, POST /v1/chat/completions, POST /v1/reset.",
            ),
            gateway_entry(
                id="jros_native_surfaces",
                kind="native_app",
                label="JROS native TUI / windowed app",
                in_use=False,
                protocol="jros-native",
                notes="JaegerAI desktop/TUI surfaces; not the ARES WebUI transport.",
            ),
        ]

        mcp = [
            mcp_entry(
                id="jros_mcp_optional",
                label="JROS MCP tools (optional)",
                in_use_by_ares=False,
                used_by=["external_mcp_clients"],
                notes="Reserved catalog slot for JROS-exposed MCP tools when present.",
            )
        ]

        return finalize_inventory(
            {
                "worker_id": self.name,
                "display_name": "JaegerAI (JROS)",
                "models": models,
                "providers": providers,
                "default": default,
                "transports": transports,
                "gateways": gateways,
                "mcp": mcp,
                "tools_summary": self.tools(),
                "active_execution": {
                    "available": self.is_available(),
                    "transport": "http_gateway",
                    "gateway_ok": gateway_ok,
                    "booted": booted,
                    "instance": instance or default.get("instance"),
                    "model": model_id,
                    "provider": provider,
                    "model_location": infer_model_location(provider, model_id),
                    "gateway_url": gateway_url,
                },
                "notes": (
                    "Models = gateway live model + instance config + installed GGUF under "
                    ".jaeger_os/models. Providers = local llama.cpp and any external_model."
                ),
            }
        )
