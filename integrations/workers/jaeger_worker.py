"""Jaeger AI Worker Integration for ARES Dispatch.

Supports both local (bridge mode) and cloud (gateway mode) execution.
Uses auto-detection: no hardcoded paths, respects environment variables.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


def is_jaeger_available() -> bool:
    """Check if Jaeger AI is available (either bridge or gateway)."""
    from integrations.providers.jaeger.status import status

    try:
        s = status()
        return s.get("available", False)
    except Exception as e:
        logger.debug("Jaeger availability check failed: %s", e)
        return False


def get_jaeger_models() -> Dict[str, Any]:
    """Get available Jaeger AI models (local and cloud).

    Returns dict with model info from active Jaeger instance.
    """
    from integrations.providers.jaeger.gateway_streaming import (
        jros_gateway_base_url,
        jros_gateway_health,
        local_jros_root,
    )

    models = {}

    # Try gateway first (cloud models)
    try:
        gateway_url = jros_gateway_base_url()
        if gateway_url:
            reply = jros_gateway_health(timeout=1.0)
            if reply:
                models["cloud"] = {
                    "model": reply.get("model"),
                    "provider": reply.get("provider"),
                    "mode": "gateway",
                    "url": gateway_url,
                }
    except Exception as e:
        logger.debug("Gateway model detection failed: %s", e)

    # Try bridge (local models)
    try:
        root = local_jros_root()
        if root:
            models["local"] = {
                "mode": "bridge",
                "root": str(root),
            }
    except Exception as e:
        logger.debug("Bridge detection failed: %s", e)

    return models


class JaegerWorker:
    """Jaeger AI worker adapter for dispatch service.

    Abstracts local (bridge) and cloud (gateway) execution modes.
    Auto-detects configuration from environment variables.
    """

    name = "jaeger_local"
    model_name = "jaeger-ai"  # Generic name for cost calculation
    supports_tools = True
    supports_streaming = True

    def __init__(self):
        self.mode = None  # "bridge" or "gateway"
        self.gateway_url = None
        self.bridge_root = None
        self._probe_availability()

    def _probe_availability(self):
        """Detect which mode is available."""
        from integrations.providers.jaeger.gateway_streaming import (
            jros_gateway_base_url,
            local_jros_root,
        )

        # Check gateway first
        try:
            url = jros_gateway_base_url()
            if url:
                self.gateway_url = url
                self.mode = "gateway"
                logger.info("Jaeger AI using gateway mode: %s", url)
                return
        except Exception:
            pass

        # Fallback to bridge
        try:
            root = local_jros_root()
            if root:
                self.bridge_root = root
                self.mode = "bridge"
                logger.info("Jaeger AI using bridge mode: %s", root)
                return
        except Exception:
            pass

        logger.warning("Jaeger AI not available: neither gateway nor bridge detected")
        self.mode = None

    def is_available(self) -> bool:
        """Check if this worker is ready to execute."""
        return self.mode is not None

    def run_turn(self, message: str, session_id: str, model: str | None = None, model_provider: str | None = None, **kwargs) -> Dict[str, Any]:
        """Execute a turn in Jaeger AI.

        Returns structured result with text, tokens, model info.
        """
        if not self.is_available():
            return {
                "error": "Jaeger AI is not available",
                "text": "Jaeger AI worker is not configured or available",
            }

        try:
            if self.mode == "gateway":
                return self._execute_gateway(message, session_id, model=model, model_provider=model_provider, **kwargs)
            elif self.mode == "bridge":
                return self._execute_bridge(message, session_id, model=model, model_provider=model_provider, **kwargs)
            else:
                return {"error": "Unknown Jaeger mode", "text": ""}
        except Exception as e:
            logger.error("Jaeger execution failed: %s", e, exc_info=True)
            return {
                "error": f"Jaeger execution failed: {str(e)}",
                "text": f"Error: {str(e)}",
            }

    def _execute_gateway(self, message: str, session_id: str, model: str | None = None, model_provider: str | None = None, **kwargs) -> Dict[str, Any]:
        """Execute via Jaeger gateway (HTTP, cloud models)."""
        import requests

        try:
            payload = {
                "message": message,
                "session_id": session_id,
                **kwargs,
            }
            if model:
                payload["model"] = model
            if model_provider:
                payload["provider"] = model_provider
            response = requests.post(
                f"{self.gateway_url}/turn",
                json=payload,
                timeout=60.0,
            )
            response.raise_for_status()
            data = response.json()

            return {
                "text": data.get("response", data.get("text", "")),
                "model": data.get("model", self.model_name),
                "provider": data.get("provider", "jaeger"),
                "input_tokens": data.get("input_tokens", 0),
                "output_tokens": data.get("output_tokens", 0),
                "mode": "gateway",
            }
        except Exception as e:
            logger.error("Gateway execution failed: %s", e)
            raise

    def _execute_bridge(self, message: str, session_id: str, model: str | None = None, model_provider: str | None = None, **kwargs) -> Dict[str, Any]:
        """Execute via Jaeger bridge — a persistent NDJSON session, not a
        one-shot subprocess call.

        The real ``jaeger bridge`` process announces readiness, boots an LLM
        (plus tool/voice models — multi-second cold start), and then expects
        stdin to stay open across turns; it only exits on an explicit "quit"
        op or a crash. A previous version of this method used
        ``subprocess.run(input=...)``, which writes once and closes stdin
        immediately — the bridge read that early EOF as shutdown and exited
        mid-boot, before ever answering, so every call silently returned
        empty text. Delegating to jros_session_manager keeps one real
        JrosClient (integrations.providers.jaeger.bridge_client — ARES's own
        already-hardened client, not a hand-rolled reimplementation) alive
        per ARES session_id across the many short-lived JaegerWorker
        instances BackendRegistry.get_available() creates.
        """
        from integrations.workers.jros_session_manager import run_turn as bridge_run_turn

        # Pass the root JaegerWorker already detected as available (not a
        # raw command), so JrosClient's own launcher+instance resolution
        # runs — that resolution is what fixes a known JROS 0.7
        # "ready-then-stall" bug on the implicit default bridge.
        # model/model_provider aren't part of the v1 wire contract's send op
        # (bridge_client.send_op only carries text + session) — the bridge
        # picks its own model at boot. Nothing here silently drops them:
        # there is simply no such parameter on the real protocol to pass.
        result = bridge_run_turn(session_id, message, jaeger_home=str(self.bridge_root))

        return {
            "text": result.get("text", ""),
            "error": result.get("error"),
            "model": self.model_name,
            "provider": "jaeger",
            "input_tokens": 0,
            "output_tokens": 0,
            "mode": "bridge",
        }

    def health(self) -> Dict[str, Any]:
        """Health check status."""
        return {
            "status": "ok" if self.is_available() else "error",
            "mode": self.mode,
            "gateway_url": self.gateway_url if self.mode == "gateway" else None,
        }

    def capabilities(self) -> Dict[str, Any]:
        """Declare supported capabilities."""
        return {
            "chat": True,
            "tools": self.supports_tools,
            "streaming": self.supports_streaming,
            "models": get_jaeger_models(),
        }
