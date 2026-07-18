"""Direct Google Gemini cloud adapter (no Hermes proxy)."""

from __future__ import annotations

import os
from typing import Any, Dict
import requests

from .cli_backends import _cfg_str, _cfg_int


class GeminiCloudBackend:
    name = "gemini_cloud"
    display_label = "Google Gemini (Cloud API)"
    supports_tools = False

    def _api_key(self, config: Dict[str, Any]) -> str:
        # 1) explicit adapter config
        key = _cfg_str(config, "api_key")
        if key:
            return key
        # 2) env var
        key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
        if key:
            return key
        # 3) ARES secrets
        try:
            from api.config import load_settings
            s = load_settings()
            secrets = s.get("secrets", {})
            return secrets.get("gemini_api_key") or secrets.get("google_api_key") or ""
        except Exception:
            return ""

    def is_available(self) -> bool:
        # Available if any API key is configured
        return bool(self._api_key({}))

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        key = self._api_key(config)
        if not key:
            return {
                "text": "",
                "error": "No Gemini API key. Add GEMINI_API_KEY to ARES secrets or set the env var.",
                "tool_activity": [],
            }

        model = _cfg_str(config, "model") or "gemini-1.5-flash"
        if ":" in model:
            model = model.split(":")[-1]
        if not model.startswith("models/"):
            model = f"models/{model}"

        url = f"https://generativelanguage.googleapis.com/v1beta/{model}:generateContent?key={key}"
        payload = {
            "contents": [{"role": "user", "parts": [{"text": message}]}],
            "generationConfig": {
                "maxOutputTokens": _cfg_int(config, "max_tokens") or 1024,
                "temperature": config.get("temperature", 0.1),
            },
        }
        try:
            r = requests.post(url, json=payload, timeout=120)
            if r.status_code != 200:
                return {"text": "", "error": f"Gemini API error {r.status_code}: {r.text[:300]}", "tool_activity": []}
            data = r.json()
            candidates = data.get("candidates", [])
            if not candidates:
                return {"text": "", "error": "No candidates in Gemini response.", "tool_activity": []}
            text = "".join(
                part.get("text", "")
                for part in candidates[0].get("content", {}).get("parts", [])
            )
            return {"text": text.strip(), "error": None, "tool_activity": []}
        except Exception as exc:
            return {"text": "", "error": str(exc), "tool_activity": []}

__all__ = ["GeminiCloudBackend"]
