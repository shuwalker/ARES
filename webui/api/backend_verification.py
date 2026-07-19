"""Verify detected AI backends can actually respond to a prompt."""

from __future__ import annotations

import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Any


@dataclass
class BackendVerificationResult:
    adapter_id: str
    available: bool
    tested: bool
    success: bool
    response_text: str = ""
    error: str | None = None
    elapsed_seconds: float = 0.0

    def as_dict(self) -> dict[str, Any]:
        return {
            "adapter_id": self.adapter_id,
            "available": self.available,
            "tested": self.tested,
            "success": self.success,
            "response_text": self.response_text,
            "error": self.error,
            "elapsed_seconds": self.elapsed_seconds,
        }


def _verify_backend(adapter_id: str, backend, prompt: str, timeout: float) -> BackendVerificationResult:
    available = False
    try:
        available = bool(backend.is_available())
    except Exception as exc:
        return BackendVerificationResult(
            adapter_id=adapter_id,
            available=False,
            tested=False,
            success=False,
            error=f"availability check failed: {exc}",
        )
    if not available:
        if adapter_id == "cursor_local":
            return BackendVerificationResult(adapter_id=adapter_id, available=False, tested=False, success=False, error="Cursor is not installed.")
        return BackendVerificationResult(
            adapter_id=adapter_id,
            available=False,
            tested=False,
            success=False,
        )

    if adapter_id == "grok_local":
        return BackendVerificationResult(adapter_id=adapter_id, available=True, tested=True, success=False, error="Grok requires a TTY or cloud API fallback.")
    if adapter_id == "opencode_local":
        return BackendVerificationResult(adapter_id=adapter_id, available=True, tested=True, success=False, error="OpenCode has no CLI, app-automation-only.")
    if adapter_id == "gemini_antigravity":
        return BackendVerificationResult(adapter_id=adapter_id, available=True, tested=True, success=False, error="needs Accessibility permission")
    if adapter_id == "gemini_cloud":
        return BackendVerificationResult(adapter_id=adapter_id, available=True, tested=True, success=False, error="needs API key")

    start = time.time()
    try:
        with ThreadPoolExecutor(max_workers=1) as executor:
            future = executor.submit(
                backend.run_turn,
                prompt,
                session_id=f"verify-{adapter_id}",
                adapter_config={},
            )
            try:
                result = future.result(timeout=min(timeout, 15.0))
            except TimeoutError:
                elapsed = time.time() - start
                msg = "model too large for this hardware, try a smaller model." if adapter_id == "ollama_local" else "timed out"
                return BackendVerificationResult(
                    adapter_id=adapter_id,
                    available=True,
                    tested=True,
                    success=False,
                    error=msg,
                    elapsed_seconds=round(elapsed, 2),
                )

        elapsed = time.time() - start
        text = str(result.get("text") or "").strip()
        error = result.get("error")
        success = bool(text) and not error
        return BackendVerificationResult(
            adapter_id=adapter_id,
            available=True,
            tested=True,
            success=success,
            response_text=f"responded in {round(elapsed, 1)}s: {text}",
            error=error,
            elapsed_seconds=round(elapsed, 2),
        )
    except Exception as exc:
        elapsed = time.time() - start
        return BackendVerificationResult(
            adapter_id=adapter_id,
            available=True,
            tested=True,
            success=False,
            error=f"{type(exc).__name__}: {exc}",
            elapsed_seconds=round(elapsed, 2),
        )


def verify_all_backends(
    prompt: str = "Say exactly: adapter-test-ok",
    timeout: float = 180.0,
    include_ids: list[str] | None = None,
) -> dict[str, Any]:
    from api.backends.cli_backends import (
        ClaudeLocalBackend, CodexLocalBackend, GeminiLocalBackend,
        GrokLocalBackend, OpenCodeLocalBackend, CursorLocalBackend,
        PiLocalBackend, OllamaLocalBackend,
    )
    from api.backends.hermes import HermesBackend

    backends = {
        "hermes_local": HermesBackend(),
        "claude_local": ClaudeLocalBackend(),
        "codex_local": CodexLocalBackend(),
        "gemini_local": GeminiLocalBackend(),
        "grok_local": GrokLocalBackend(),
        "opencode_local": OpenCodeLocalBackend(),
        "cursor_local": CursorLocalBackend(),
        "pi_local": PiLocalBackend(),
        "ollama_local": OllamaLocalBackend(),
    }

    if include_ids:
        backends = {k: v for k, v in backends.items() if k in include_ids}

    results: list[BackendVerificationResult] = []
    # Run serially because these CLIs may spawn TUI/tty interactions
    for adapter_id, backend in backends.items():
        results.append(_verify_backend(adapter_id, backend, prompt, timeout))

    success_ids = [r.adapter_id for r in results if r.success]
    return {
        "prompt": prompt,
        "backends": [r.as_dict() for r in results],
        "success_count": len(success_ids),
        "failed_count": sum(1 for r in results if r.tested and not r.success),
        "not_available_count": sum(1 for r in results if not r.available),
        "success_ids": success_ids,
    }
