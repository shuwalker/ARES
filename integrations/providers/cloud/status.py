"""Readiness for credential-authenticated cloud providers.

OpenAI, xAI and Gemini differ only in which environment variable holds the key
and which endpoint verifies it, so they share one module rather than getting a
package each. A provider needing its own execution or discovery logic should
graduate to its own package — the shared status contract does not require them
to stay here.

Credentials are read through the active profile's isolated environment view and
are never returned in ``details``; only the variable *name* appears, matching
the repository rule that ARES records the env-var name, never the key.
"""
from __future__ import annotations

import logging

from api.providers.status_contract import (
    ProviderStatus,
    connected,
    needs_attention,
    not_configured,
)

logger = logging.getLogger(__name__)


def credential(name: str) -> str | None:
    """Resolve a credential through the active profile's env view."""
    from api.config import _thread_local_env_value

    return _thread_local_env_value(name).strip() or None


def first_credential(*names: str) -> tuple[str | None, str | None]:
    """Return the first present credential and the variable it came from."""
    for name in names:
        value = credential(name)
        if value:
            return value, name
    return None, None


def check_status(
    *,
    provider: str,
    display_name: str,
    base_url: str,
    env_vars: tuple[str, ...],
) -> ProviderStatus:
    """Whether ``provider`` has a credential, and whether it verifies.

    A missing key is ``not_configured`` — a setup step, not an outage. Reporting
    it as offline told users to restart something that was never running.
    """
    api_key, source_var = first_credential(*env_vars)
    if not api_key:
        primary = env_vars[0] if env_vars else "an API key"
        return not_configured(
            f"{display_name} is not configured. Set {primary} in Secrets to use it.",
            provider=provider,
            credential_env=primary,
        )

    from api.onboarding import probe_provider_endpoint

    try:
        result = probe_provider_endpoint(provider, base_url, api_key, timeout=5.0)
    except Exception as exc:
        logger.debug("%s credential probe raised", display_name, exc_info=True)
        return needs_attention(
            f"{display_name} credentials could not be verified ({exc}).",
            provider=provider,
            credential_env=source_var,
        )

    if result.get("ok"):
        return connected(
            f"{display_name} credentials verified.",
            provider=provider,
            credential_env=source_var,
        )

    error_code = str(result.get("error") or "unreachable")
    details = {"provider": provider, "credential_env": source_var, "error": error_code}
    status_code = result.get("status")
    if isinstance(status_code, int):
        details["status"] = status_code
    return needs_attention(
        f"{display_name} credential validation failed ({error_code}).",
        **details,
    )


_GEMINI_ENV_VARS = ("GEMINI_API_KEY", "GOOGLE_API_KEY")
_GEMINI_MODELS_URL = "https://generativelanguage.googleapis.com/v1beta/models"


def check_gemini_status() -> ProviderStatus:
    """Gemini readiness.

    Kept separate from :func:`check_status` because Google's API is not
    OpenAI-compatible — it authenticates with an ``x-goog-api-key`` header
    against its own endpoint, so it cannot share the generic probe.
    """
    import urllib.error
    import urllib.request

    api_key, source_var = first_credential(*_GEMINI_ENV_VARS)
    if not api_key:
        return not_configured(
            "Google Gemini is not configured. Set GEMINI_API_KEY in Secrets to use it.",
            provider="gemini",
            credential_env=_GEMINI_ENV_VARS[0],
        )

    request = urllib.request.Request(
        _GEMINI_MODELS_URL,
        headers={"Accept": "application/json", "x-goog-api-key": api_key},
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            if response.status == 200:
                return connected(
                    "Google Gemini credentials verified.",
                    provider="gemini",
                    credential_env=source_var,
                )
            return needs_attention(
                "Google Gemini credential validation failed.",
                provider="gemini",
                credential_env=source_var,
                status=int(response.status),
            )
    except urllib.error.HTTPError as exc:
        return needs_attention(
            "Google Gemini credential validation failed.",
            provider="gemini",
            credential_env=source_var,
            status=int(exc.code),
        )
    except (urllib.error.URLError, TimeoutError):
        return needs_attention(
            "Google Gemini could not be reached for credential validation.",
            provider="gemini",
            credential_env=source_var,
            error="unreachable",
        )
