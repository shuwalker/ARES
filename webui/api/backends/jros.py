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
            "label": "JROS" if available else "JROS (not found)",
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
            }
        }
