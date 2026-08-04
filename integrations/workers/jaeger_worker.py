"""Jaeger AI Worker Integration for ARES Dispatch.

Supports both local (bridge mode) and cloud (gateway mode) execution.
Uses auto-detection: no hardcoded paths, respects environment variables.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)


def is_jaeger_available() -> bool:
    """Check if Jaeger AI is available (either bridge or gateway)."""
    from api.providers.jaeger.status import status

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
    from api.providers.jaeger.gateway_streaming import (
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
        from api.providers.jaeger.gateway_streaming import (
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

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
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
                return self._execute_gateway(message, session_id, **kwargs)
            elif self.mode == "bridge":
                return self._execute_bridge(message, session_id, **kwargs)
            else:
                return {"error": "Unknown Jaeger mode", "text": ""}
        except Exception as e:
            logger.error("Jaeger execution failed: %s", e, exc_info=True)
            return {
                "error": f"Jaeger execution failed: {str(e)}",
                "text": f"Error: {str(e)}",
            }

    def _execute_gateway(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """Execute via Jaeger gateway (HTTP, cloud models)."""
        import requests

        try:
            response = requests.post(
                f"{self.gateway_url}/turn",
                json={
                    "message": message,
                    "session_id": session_id,
                    **kwargs,
                },
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

    def _execute_bridge(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """Execute via Jaeger bridge (subprocess, local models)."""
        import subprocess

        try:
            # Prepare input for bridge
            input_data = {
                "message": message,
                "session_id": session_id,
                **kwargs,
            }

            # Call jaeger bridge subprocess
            result = subprocess.run(
                [str(self.bridge_root / "jaeger"), "bridge"],
                input=json.dumps(input_data),
                capture_output=True,
                text=True,
                timeout=300.0,  # 5 minute timeout
                cwd=str(self.bridge_root),
            )

            if result.returncode != 0:
                logger.error("Bridge error: %s", result.stderr)
                raise RuntimeError(f"Bridge failed: {result.stderr}")

            # Parse output (NDJSON)
            lines = result.stdout.strip().split("\n")
            response_data = {}
            text = ""

            for line in lines:
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                    if obj.get("type") == "response":
                        response_data = obj
                        text = obj.get("text", text)
                except json.JSONDecodeError:
                    logger.debug("Non-JSON line from bridge: %s", line)

            return {
                "text": text,
                "model": response_data.get("model", self.model_name),
                "provider": response_data.get("provider", "jaeger"),
                "input_tokens": response_data.get("input_tokens", 0),
                "output_tokens": response_data.get("output_tokens", 0),
                "mode": "bridge",
            }
        except Exception as e:
            logger.error("Bridge execution failed: %s", e)
            raise

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
