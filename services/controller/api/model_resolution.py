"""Model/provider resolution shared by HTTP, WebSocket, and background turns."""

from __future__ import annotations

import logging
import os
import threading
import time

from api.config import DEFAULT_MODEL, _provider_is_known_or_configured, get_available_models

logger = logging.getLogger(__name__)
_PROVIDER_ALIASES = {
    "claude": "anthropic", "gpt": "openai", "gemini": "google",
    "openai-codex": "openai", "openai-api": "openai",
    "google-gemini": "google", "google-ai-studio": "google",
    "claude-code": "anthropic",
}
_PROFILE_CONFIG_CACHE: "dict[tuple, tuple[float, str, dict]]" = {}
_PROFILE_CONFIG_CACHE_TTL_SECONDS = 60.0
_PROFILE_CONFIG_CACHE_LOCK = threading.Lock()

def _starts_token(raw: str, prefix: str) -> bool:
    if not raw.startswith(prefix):
        return False
    rest = raw[len(prefix):]
    return rest == "" or rest[0] in ":/"


def _normalize_provider_id(value: str | None) -> str:
    raw = str(value or "").strip().lower()
    if not raw:
        return ""
    if raw in _PROVIDER_ALIASES:
        return _PROVIDER_ALIASES[raw]
    for prefix, normalized in (
        ("openai-codex", "openai"),
        ("openai", "openai"),
        ("anthropic", "anthropic"),
        ("claude", "anthropic"),
        ("google", "google"),
        ("gemini", "google"),
        ("openrouter", "openrouter"),
        ("custom", "custom"),
    ):
        if _starts_token(raw, prefix):
            return normalized
    # Unknown prefix — return empty so callers treat it as "no match" and pass
    # the model through unchanged rather than incorrectly stripping it.
    return "" 


def _catalog_provider_id_sets(catalog: dict) -> tuple[set[str], set[str]]:
    raw_provider_ids: set[str] = set()
    normalized_provider_ids: set[str] = set()
    for group in catalog.get("groups") or []:
        raw = str(group.get("provider_id") or "").strip().lower()
        if not raw:
            continue
        raw_provider_ids.add(raw)
        normalized = _normalize_provider_id(raw)
        if normalized:
            normalized_provider_ids.add(normalized)
    return raw_provider_ids, normalized_provider_ids


def _catalog_has_provider(
    provider_raw: str,
    provider_normalized: str,
    raw_provider_ids: set[str],
    normalized_provider_ids: set[str],
) -> bool:
    return (
        provider_raw in raw_provider_ids
        or (provider_normalized and provider_normalized in raw_provider_ids)
        or (provider_normalized and provider_normalized in normalized_provider_ids)

    )


def _model_matches_active_provider_family(
    model: str,
    active_provider: str,
) -> bool:
    model_lower = model.lower()
    for bare_prefix in ("gpt", "claude", "gemini"):
        if model_lower.startswith(bare_prefix):
            return _normalize_provider_id(bare_prefix) == active_provider
    return False


def _catalog_model_id_matches(candidate: str, model: str) -> bool:
    candidate = str(candidate or "").strip()
    if candidate.startswith("@") and ":" in candidate:
        candidate = candidate.rsplit(":", 1)[1]
    if "/" in candidate:
        candidate = candidate.split("/", 1)[1]
    return candidate.replace("-", ".").lower() == model.replace("-", ".").lower()


def _catalog_group_owns_exact_model(group: dict, model: str) -> bool:
    provider_id = str(group.get("provider_id") or "").strip()
    wrapper = f"@{provider_id}:"
    for bucket in ("models", "extra_models"):
        for entry in group.get(bucket) or []:
            if not isinstance(entry, dict):
                continue
            candidate = str(entry.get("id") or "").strip()
            if candidate.lower().startswith(wrapper.lower()):
                candidate = candidate[len(wrapper):]
            if candidate == model or _catalog_model_id_matches(candidate, model):
                return True
    return False


def _repair_foreign_session_model_provider(
    session,
    *,
    requested_model: str,
    requested_provider: str | None,
    resolved_model: str,
    resolved_provider: str | None,
    explicit_model_pick: bool,
    profile_provider: str | None,
) -> str | None:
    """Repair a stale provider only when the cached catalog names one owner."""
    stored_model = str(getattr(session, "model", "") or "").strip()
    stored_provider = _clean_session_model_provider(getattr(session, "model_provider", None))
    requested_provider = _clean_session_model_provider(requested_provider)
    resolved_provider = _clean_session_model_provider(resolved_provider)
    profile_provider = _clean_session_model_provider(profile_provider)
    _, qualified_provider = _split_provider_qualified_model(requested_model)
    if (
        explicit_model_pick
        or qualified_provider
        or not stored_model
        or not stored_provider
        or (
            str(requested_model or "").strip() != stored_model
            and not _catalog_model_id_matches(str(requested_model or "").strip(), stored_model)
        )
        or requested_provider != stored_provider
        or (
            resolved_model != stored_model
            and not _catalog_model_id_matches(resolved_model, stored_model)
        )
        or resolved_provider != stored_provider
        or not profile_provider
        or profile_provider == stored_provider
    ):
        return resolved_provider

    try:
        catalog = get_available_models(prefer_cache=True)
    except Exception:
        return resolved_provider
    groups = [group for group in catalog.get("groups") or [] if isinstance(group, dict)]
    stored_groups = [
        group
        for group in groups
        if str(group.get("provider_id") or "").strip().lower() == stored_provider
    ]
    if (
        not stored_groups
        or any(group.get("models_endpoint_error") for group in stored_groups)
        or any(_catalog_group_owns_exact_model(group, stored_model) for group in stored_groups)
    ):
        return resolved_provider
    owners = [
        group
        for group in groups
        if str(group.get("provider_id") or "").strip().lower() != stored_provider
        and _catalog_group_owns_exact_model(group, stored_model)
    ]
    if len(owners) != 1:
        return resolved_provider
    return str(owners[0].get("provider_id") or "").strip() or resolved_provider


def resolve_chat_model_state(
    session,
    requested_model: str | None,
    requested_provider: str | None,
    *,
    explicit_model_pick: bool = False,
    prefer_cached_catalog: bool = False,
) -> tuple[str, str | None]:
    """Resolve and repair the model identity used for a new chat turn."""
    profile_provider, profile_default, profile_config = _read_profile_model_config(
        session,
        requested_provider,
    )
    model, provider, _changed = _resolve_compatible_session_model_state(
        requested_model,
        requested_provider,
        profile_provider=profile_provider,
        profile_default_model=profile_default,
        profile_config=profile_config,
        explicit_model_pick=explicit_model_pick,
        prefer_cached_catalog=prefer_cached_catalog,
    )
    provider = _repair_foreign_session_model_provider(
        session,
        requested_model=str(requested_model or ""),
        requested_provider=requested_provider,
        resolved_model=model,
        resolved_provider=provider,
        explicit_model_pick=explicit_model_pick,
        profile_provider=profile_provider,
    )
    return model, provider


def _clean_session_model_provider(value: str | None) -> str | None:
    provider = str(value or "").strip().lower()
    if not provider or provider == "default":
        return None
    if provider.startswith("@"):
        provider = provider[1:]
    return provider or None


def _split_provider_qualified_model(model: str) -> tuple[str, str | None]:
    model = str(model or "").strip()
    if model.startswith("@") and ":" in model:
        provider_hint, bare_model = model[1:].rsplit(":", 1)
        provider = _clean_session_model_provider(provider_hint)
        bare = bare_model.strip()
        if provider and bare:
            return bare, provider
    return model, None


def _model_matches_configured_default(
    session_model: str | None,
    cfg_default: str | None,
    provider: str | None = None,
) -> bool:
    """Return True when ``session_model`` refers to the configured ``model.default``.

    The global ``model.context_length`` cap applies ONLY to the default model
    (#3256/#3263). An exact string compare is not enough because ``model.default``
    and the session model can be stored in different but equivalent shapes:
      - bare:            ``claude-opus-4.8``
      - slash-prefixed:  ``anthropic/claude-opus-4.8``  (OpenRouter-style)
      - @provider:model: ``@anthropic:claude-opus-4.8``

    Matching rule (correct in both directions):
      1. Identical strings → match.
      2. Otherwise compare BARE model ids — BUT only after a provider-compatibility
         check: if BOTH sides carry an identifiable provider (from a ``provider/``
         prefix, an ``@provider:`` qualifier, or the explicit ``provider`` arg for
         the session side) and those providers DIFFER, it is NOT a match. This
         stops a non-default model on a different provider that happens to share a
         bare name (``openai/gpt-4o`` vs default ``openrouter/gpt-4o``) from being
         treated as the default and wrongly receiving its cap.
      3. When a provider can't be identified on one side, fall through to the bare
         comparison (lenient-when-unknown — a bare default config still matches a
         bare/prefixed session model).
    Empty default → no match.
    """
    sess = str(session_model or "").strip()
    default = str(cfg_default or "").strip()
    if not sess or not default:
        return False
    if sess == default:
        return True

    def _split(value: str) -> tuple[str, str | None]:
        """Return (bare_model, provider_or_None) for any of the 3 shapes."""
        value = str(value or "").strip()
        # @provider:model
        unq, q_prov = _split_provider_qualified_model(value)
        if q_prov:
            return unq.strip(), str(q_prov).strip().lower()
        # provider/model (single leading slash segment)
        if "/" in value:
            prefix, rest = value.split("/", 1)
            return rest.strip(), prefix.strip().lower()
        return value, None

    sess_bare, sess_prov = _split(sess)
    default_bare, default_prov = _split(default)
    # The explicit provider arg is the session side's provider when the model
    # string itself didn't carry one.
    if not sess_prov and provider:
        sess_prov = str(provider).strip().lower() or None

    if not sess_bare or not default_bare or sess_bare != default_bare:
        return False
    # Bare ids match. Reject only when both sides name DIFFERENT providers.
    if sess_prov and default_prov and sess_prov != default_prov:
        return False
    return True


def _should_attach_codex_provider_context(model: str, raw_active_provider: str, catalog: dict) -> bool:
    """Return True when a bare Codex model needs separate provider context.

    OpenAI, OpenAI Codex, Copilot, and OpenRouter can all expose GPT-looking
    bare names. If a session stores only ``gpt-...`` while Codex is active, a
    later provider-list/default-model round trip can lose the user's Codex
    choice. Store the provider separately instead of converting the persisted
    model to ``@openai-codex:model``.
    """
    if raw_active_provider != "openai-codex":
        return False
    if not model.lower().startswith("gpt"):
        return False
    for group in catalog.get("groups") or []:
        if str(group.get("provider_id") or "").strip().lower() != "openai-codex":
            continue
        return any(
            _catalog_model_id_matches(entry.get("id"), model)
            for entry in group.get("models", [])
            if isinstance(entry, dict)
        )
    return False


def _read_profile_model_config(
    session,
    requested_provider: str | None,
) -> tuple[str | None, str | None, dict | None]:
    """Read model.provider, model.default, and the full profile config dict.

    Returns (profile_provider, profile_default_model, profile_config_dict).
    The first two are None when the session has no profile or the profile config
    is unreadable; profile_config_dict is None in the same cases so callers only
    pay for one YAML parse.

    When the session already has an explicit ``requested_provider``, the profile
    ``model.provider`` is not returned (first tuple element is None) so profile
    does not override the session provider. ``profile_default_model`` is still
    returned for suffix repair (#5127) only when the profile's configured
    provider matches ``requested_provider`` after normalization.

    perf(webui/session-load-latency) tier2a: the parse is wrapped in a
    per-process LRU keyed by (profile_name, config_mtime, size). The
    function fires on every chat-open for sessions under a named
    profile (resolve_model=1 path), and the YAML parse alone is
    hundreds of µs to single-digit ms on the Chromebook. Cache TTL
    60s is a backstop in case mtime resolution is poor on a given
    filesystem; under normal edits the mtime changes and invalidates
    immediately.
    """
    if not getattr(session, "profile", None):
        return None, None, None

    try:
        from api.profiles import get_ares_home_for_profile

        _profile_name = str(session.profile or "")
        _profile_home = get_ares_home_for_profile(_profile_name)
        _profile_cfg_path = os.path.join(str(_profile_home), "config.yaml")
        if not os.path.isfile(_profile_cfg_path):
            return None, None, None
        _pcfg = _read_profile_config_cached(_profile_name, _profile_cfg_path)
        if _pcfg is None:
            return None, None, None
        _model_cfg = _pcfg.get("model") or {}
        if not isinstance(_model_cfg, dict):
            return None, None, _pcfg
        _provider = (_model_cfg.get("provider") or "").strip() or None
        _default = (_model_cfg.get("default") or "").strip() or None
    except Exception:
        logger.warning(
            "profile provider read failed for %r",
            getattr(session, "profile", None),
            exc_info=True,
        )
        return None, None, None

    _requested = _clean_session_model_provider(requested_provider)
    if _requested:
        _profile_prov = _clean_session_model_provider(_provider)
        if _profile_prov != _requested:
            return None, None, _pcfg
        return None, _default, _pcfg
    return _provider, _default, _pcfg


def _read_profile_config_cached(profile_name: str, cfg_path: str) -> dict | None:
    """Return parsed profile config, caching by (inode, mtime, size) with
    TTL backstop and full-content verification.

    The full-content comparison reads the current file and compares it to a
    copy stored in the cache entry. This catches any in-place rewrite where
    inode+mtime+size are identical, regardless of where in the file the change
    occurs — unlike a fixed-length prefix comparison, edits to fields after the
    first N characters are always detected. Reading and comparing the full file
    content (~1-10KB for a typical config.yaml) is much cheaper than
    yaml.safe_load().

    NOTE: The cache key uses inode+mtime+size to handle the common cases
    (atomic-rename editors -> new inode; in-place editors -> mtime/size
    change). The full-content comparison is a backstop for the rare case where
    all three collide (e.g., sed -i on a filesystem with coarse mtime
    resolution, writing the same byte count).
    """
    try:
        st = os.stat(cfg_path)
    except OSError:
        return None
    mtime = float(getattr(st, "st_mtime", 0.0) or 0.0)
    size = int(getattr(st, "st_size", 0) or 0)
    inode = int(getattr(st, "st_ino", 0) or 0)
    key = (str(profile_name or ""), inode, mtime, size)
    now = time.monotonic()
    with _PROFILE_CONFIG_CACHE_LOCK:
        cached = _PROFILE_CONFIG_CACHE.get(key)
        if cached is not None:
            cached_at, cached_content, cached_dict = cached
            if (now - cached_at) <= _PROFILE_CONFIG_CACHE_TTL_SECONDS:
                # Full content comparison catches any in-place rewrite where
                # inode+mtime+size are identical but the file content changed.
                # Reading and comparing the full file (~1-10KB) is cheaper than
                # yaml.safe_load(). Unlike a fixed-length prefix, this detects
                # edits anywhere in the file. Greptile P1 (PR#5803).
                _current_content = None
                try:
                    with open(cfg_path, "r", encoding="utf-8") as _f:
                        _current_content = _f.read()
                except Exception:
                    pass
                if _current_content == cached_content:
                    return cached_dict
                # Content changed while key collided — fall through to re-parse
    import yaml
    try:
        with open(cfg_path, encoding="utf-8") as _f:
            content = _f.read()
            parsed = yaml.safe_load(content) or {}
    except Exception:
        return None
    if not isinstance(parsed, dict):
        return None
    with _PROFILE_CONFIG_CACHE_LOCK:
        _PROFILE_CONFIG_CACHE[key] = (now, content, parsed)
        # Cap the cache at 32 entries; profiles are bounded in practice
        # and unbounded growth would be a leak.
        if len(_PROFILE_CONFIG_CACHE) > 32:
            # Drop the oldest entry by insertion order (dict is ordered).
            for old_key in list(_PROFILE_CONFIG_CACHE.keys())[:max(0, len(_PROFILE_CONFIG_CACHE) - 32)]:
                _PROFILE_CONFIG_CACHE.pop(old_key, None)
    return parsed


def _load_profile_config_dict(session) -> dict | None:
    """Load the session profile's config.yaml as a dict, or None."""
    if not getattr(session, "profile", None):
        return None
    try:
        from api.profiles import get_ares_home_for_profile

        _profile_cfg_path = os.path.join(
            str(get_ares_home_for_profile(session.profile)),
            "config.yaml",
        )
        if not os.path.isfile(_profile_cfg_path):
            return None
        import yaml

        with open(_profile_cfg_path, encoding="utf-8") as _f:
            _pcfg = yaml.safe_load(_f) or {}
        return _pcfg if isinstance(_pcfg, dict) else None
    except Exception:
        logger.warning(
            "profile config read failed for %r",
            getattr(session, "profile", None),
            exc_info=True,
        )
        return None


def _ordered_custom_provider_model_ids(entry: dict) -> list[str]:
    """Model ids from a custom_providers entry (default model + dict/list models)."""
    ordered: list[str] = []
    _cp_model = str(entry.get("model") or "").strip()
    if _cp_model:
        ordered.append(_cp_model)
    _cp_models = entry.get("models")
    if isinstance(_cp_models, dict):
        for _key in _cp_models.keys():
            if isinstance(_key, str):
                _kid = _key.strip()
                if _kid and _kid not in ordered:
                    ordered.append(_kid)
    elif isinstance(_cp_models, list):
        for _item in _cp_models:
            if isinstance(_item, str):
                _mid = _item.strip()
                if _mid and _mid not in ordered:
                    ordered.append(_mid)
            elif isinstance(_item, dict):
                _mid = str(
                    _item.get("id") or _item.get("model") or _item.get("name") or ""
                ).strip()
                if _mid and _mid not in ordered:
                    ordered.append(_mid)
    return ordered


def _repair_bare_custom_provider_model(
    bare_model: str,
    provider: str | None,
    *,
    config_obj: dict | None = None,
) -> str | None:
    """Re-qualify a bare model ID using the named custom provider's config (#5314).

    Returns the fully namespaced model id when ``bare_model`` matches the suffix
    of a registered id on ``custom_providers``; otherwise None. Model ids are
    scanned in config declaration order (default ``model`` first, then
    ``models`` dict keys or list entries) so repair is deterministic when
    suffixes collide.

    When ``config_obj`` is set (typically the session profile's config.yaml),
    only that object's ``custom_providers`` are scanned. Otherwise uses
    ``get_config()`` for the active global config (not the raw ``cfg`` alias).
    """
    try:
        model = str(bare_model or "").strip()
        prov = _clean_session_model_provider(provider)
        if not model or "/" in model or not prov:
            return None
        if prov != "custom" and not str(prov).startswith("custom:"):
            return None
        from api.config import (
            _custom_provider_entries,
            _custom_provider_slug_from_name,
            get_config,
        )

        if isinstance(config_obj, dict):
            _entries = _custom_provider_entries(config_obj)
        else:
            _cfg = get_config()
            _entries = _custom_provider_entries(
                _cfg if isinstance(_cfg, dict) else None
            )
        prov_norm = str(prov).strip().lower()
        raw_suffix = prov_norm.removeprefix("custom:")
        _matching_cp = None
        for _entry in _entries:
            entry_name = str(_entry.get("name") or "").strip().lower()
            slug = _custom_provider_slug_from_name(_entry.get("name"))
            if not slug:
                continue
            if (
                prov_norm in {entry_name, slug}
                or raw_suffix == slug.removeprefix("custom:")
            ):
                _matching_cp = _entry
                break
        if not _matching_cp:
            return None
        for _id in _ordered_custom_provider_model_ids(_matching_cp):
            if "/" in _id and _id.rsplit("/", 1)[-1] == model:
                return _id
        return None
    except Exception:
        return None


def _moa_fast_path_model_state(model: str) -> tuple[str, str, bool]:
    """Strip an optional ``@moa:``/``moa/`` prefix from an MoA-routed model.

    Split out of ``_resolve_compatible_session_model_state`` so the MoA
    fast-path stays a single-line call in that function body (see
    ``test_issue1855_resolve_model_provider_fast_path.py``, the fast-path/
    catalog-call ordering check scans a bounded window of that function's
    source, and inlining this here previously pushed the catalog call just
    past that window).
    """
    if model.startswith("@moa:"):
        return model.split(":", 1)[1].strip(), "moa", True
    if model.lower().startswith("moa/"):
        return model.split("/", 1)[1].strip(), "moa", True
    return model, "moa", False


def _resolve_compatible_session_model_state(
    model_id: str | None,
    model_provider: str | None = None,
    *,
    profile_provider: str | None = None,
    profile_default_model: str | None = None,
    profile_config: dict | None = None,
    explicit_model_pick: bool = False,
    prefer_cached_catalog: bool = False,
) -> tuple[str, str | None, bool]:
    """Return (effective_model, effective_provider, model_was_normalized).

    Sessions can outlive provider changes. When an older session still points at
    a different provider namespace (for example `gemini/...` after switching the
    agent to OpenAI Codex), reusing that stale model causes chat startup to hit
    the wrong backend and fail. Normalize only obvious cross-provider mismatches.
    When a model has an explicit provider context, keep the model string itself
    in its picker/API shape and carry the provider as separate state.

    Fast path (#1855): when the caller supplies both a model and an explicit
    ``model_provider`` AND the model is not itself ``@provider:model``-qualified,
    we can return the inputs verbatim without calling ``get_available_models()``.
    The slow path below would arrive at the same answer via
    ``if requested_provider and not explicit_provider: return model, requested_provider, False``
    after paying the full catalog-build cost. Avoiding the catalog here keeps
    ``POST /api/chat/start`` snappy even when the model catalog is cold and the
    rebuild has to make network calls (custom OpenAI-compat endpoints,
    OpenRouter ``/models``, LM Studio ``/models``, credential pool refresh),
    those used to wedge the handler for >100s and trigger 502s on default-60s
    reverse proxies, even though the WebUI itself eventually responded.

    ``prefer_cached_catalog=True`` (ours-original) makes the catalog lookup
    non-blocking: it resolves from the warm/disk cache or a network-free
    minimal catalog and NEVER triggers a live per-provider rebuild (the
    Copilot token-exchange HTTPS call that hangs a server-initiated wakeup
    turn, see rebase report §1/§3/model-resolve-hang). Human-initiated
    chat/start leaves this False to keep full live discovery; a session that
    already has a persisted model still resolves correctly because the
    persisted model wins over the catalog and the catalog is only consulted
    for the default-model backstop.
    """
    model = str(model_id or "").strip()
    requested_provider = _clean_session_model_provider(model_provider)
    if model and requested_provider == "moa":
        return _moa_fast_path_model_state(model)
    if model and requested_provider and model.startswith(f"@{requested_provider}:"):
        try:
            from api.config import cfg as _active_cfg

            providers_cfg = _active_cfg.get("providers") if isinstance(_active_cfg, dict) else {}
        except Exception:
            providers_cfg = {}
        if isinstance(providers_cfg, dict) and requested_provider in providers_cfg:
            return model, requested_provider, False
    if model and requested_provider:
        # Only safe when the model itself does not carry an ``@provider:model``
        # qualifier — qualified strings require the catalog to decide whether
        # the qualifier matches the active provider (see slow path below).
        bare_model, explicit_provider = _split_provider_qualified_model(model)
        model_prefix = model.split("/", 1)[0].strip().lower() if "/" in model else ""
        stale_codex_openai_slash_id = (
            requested_provider == "openai-codex"
            and model_prefix == "openai"
        )
        if not explicit_provider and not stale_codex_openai_slash_id:
            _profile_default = str(profile_default_model or "").strip()
            _profile_prov = _clean_session_model_provider(profile_provider)
            _providers_match_for_repair = (
                _profile_prov is None or _profile_prov == requested_provider
            )
            if (
                _profile_default
                and "/" in _profile_default
                and "/" not in model
                and _profile_default.rsplit("/", 1)[-1] == model
                and _providers_match_for_repair
                and (
                    requested_provider == "custom"
                    or str(requested_provider).startswith("custom:")
                )
            ):
                return _profile_default, requested_provider, True

            _repaired_model = _repair_bare_custom_provider_model(
                model,
                requested_provider,
                config_obj=profile_config,
            )
            if _repaired_model:
                return _repaired_model, requested_provider, True

            return model, requested_provider, False

    # Default (human chat/start) path calls get_available_models() with NO
    # kwargs so it stays signature-compatible with the many tests that stub
    # get_available_models as a zero-arg callable. Only the server-side wakeup
    # path (prefer_cached_catalog=True) opts into the cache-only mode. Some
    # tests monkeypatch get_available_models as a zero-arg callable, so probe
    # the (possibly monkeypatched) signature for ``prefer_cache`` rather than
    # catching TypeError — a blanket ``except TypeError`` would also swallow a
    # genuine TypeError raised *inside* get_available_models(prefer_cache=True)
    # and silently fall back to the slow live provider rebuild that
    # prefer_cached_catalog=True is meant to avoid.
    if prefer_cached_catalog:
        import inspect as _inspect

        try:
            _gam_accepts_prefer_cache = (
                "prefer_cache" in _inspect.signature(get_available_models).parameters
            )
        except (TypeError, ValueError):
            # Builtins / C-callables can refuse introspection; assume the
            # zero-arg stub shape in that case.
            _gam_accepts_prefer_cache = False
        if _gam_accepts_prefer_cache:
            catalog = get_available_models(prefer_cache=True)
        else:
            catalog = get_available_models()
    else:
        catalog = get_available_models()
    default_model = str(catalog.get("default_model") or DEFAULT_MODEL or "").strip()

    # Profile-aware resolution: when the caller supplies profile context
    # (not an explicit per-chat override), use the profile's provider and
    # default model as the resolution context instead of the catalog's
    # active_provider / default_model. This preserves the repair path
    # (stale models still get normalized) but normalizes to the profile's
    # default model under the profile's provider rather than the global default.
    bare_model, explicit_provider = _split_provider_qualified_model(model) if model else ("", None)
    if profile_provider and not explicit_provider:
        _profile_provider_normalized = _normalize_provider_id(profile_provider)
        _profile_default = str(profile_default_model or "").strip()
        if not model:
            _fallback = _profile_default or default_model
            return _fallback, profile_provider, bool(_fallback)

        model_prefix = model.split("/", 1)[0].strip().lower() if "/" in model else ""
        model_provider_from_name = _normalize_provider_id(model_prefix) if "/" in model else ""

        model_family = ""
        if "/" not in model:
            model_lower = model.lower()
            for bare_prefix in ("gpt", "claude", "gemini"):
                if model_lower.startswith(bare_prefix):
                    model_family = _normalize_provider_id(bare_prefix)
                    break

        if model_family and model_family != _profile_provider_normalized:
            if explicit_model_pick:
                # User explicitly chose a cross-family model; honor it (#3737)
                return model, profile_provider, False
            _target = _profile_default or default_model
            return _target, profile_provider, True

        if (
            "/" in model
            and str(profile_provider).strip().lower() == "openai-codex"
            and model_provider_from_name == "openai"
        ):
            _target = _profile_default or default_model
            return _target, profile_provider, True

        # Slash-qualified models (e.g. openai/gpt-5.4-mini) are native IDs on
        # OpenRouter and custom providers, not cross-provider artifacts. Only
        # repair when the profile provider actually requires a different family.
        if "/" in model and _profile_provider_normalized in {"openrouter", "custom", ""}:
            return model, profile_provider, False

        if "/" in model and model_provider_from_name and model_provider_from_name != _profile_provider_normalized:
            _target = _profile_default or default_model
            return _target, profile_provider, True

        # Async server-side continuations (for example delegate_task completion
        # re-entry) can arrive here with profile context but without a usable
        # requested_provider, bypassing the fast-path custom-provider repair
        # above. If the profile's configured custom-provider default is a
        # slash-qualified model whose suffix matches the bare session model,
        # repair back to the profile default before the provider call (#5225).
        if (
            "/" not in model
            and _profile_default
            and "/" in _profile_default
            and _profile_default.rsplit("/", 1)[-1] == model
            and (
                _profile_provider_normalized == "custom"
                or str(profile_provider).startswith("custom:")
            )
        ):
            return _profile_default, profile_provider, True

        _repaired_model = _repair_bare_custom_provider_model(
            model,
            profile_provider,
            config_obj=profile_config,
        )
        if _repaired_model:
            return _repaired_model, profile_provider, True

        return model, profile_provider, False

    if not model:
        return default_model, requested_provider, bool(default_model)

    active_provider = _normalize_provider_id(catalog.get("active_provider"))
    # Also keep the raw active_provider slug for cross-provider detection with
    # non-listed providers (ollama-cloud, deepseek, xai, etc.) that _normalize_provider_id
    # returns "" for. If the raw provider is set but normalization returned "", we still
    # want to detect that a session model from a known provider (e.g. openai/gpt-5.4-mini)
    # is stale relative to this unknown active provider. (#1023)
    raw_active_provider = str(catalog.get("active_provider") or "").strip().lower()
    if not active_provider and not raw_active_provider:
        bare_model, explicit_provider = _split_provider_qualified_model(model)
        return model, explicit_provider or requested_provider, False

    bare_for_context, explicit_provider = _split_provider_qualified_model(model)
    if requested_provider and not explicit_provider:
        model_prefix = model.split("/", 1)[0].strip().lower() if "/" in model else ""
        stale_codex_openai_slash_id = (
            raw_active_provider == "openai-codex"
            and requested_provider == "openai-codex"
            and model_prefix == "openai"
        )
        if not stale_codex_openai_slash_id:
            return model, requested_provider, False

    if model.startswith("@") and ":" in model:
        provider_raw = explicit_provider or ""
        provider_normalized = _normalize_provider_id(provider_raw)
        bare_model = bare_for_context.strip()
        if not provider_raw or not bare_model:
            return model, requested_provider, False

        # A fresh, explicit user pick is by definition not a stale artifact, so
        # honor the @provider:model exactly as chosen — never reroute it via the
        # active-provider family repair or the cold-catalog fallback below (a bare
        # id like "gpt-oss-120b" under an OpenAI-active agent would otherwise get
        # pulled to OpenAI by the family-match branch). If the named provider is
        # unreachable the user sees a clear run-time error rather than a silent
        # model swap. Must sit above the family-match repair (#3737 principle).
        if explicit_model_pick:
            return model, provider_raw, False

        raw_provider_ids, normalized_provider_ids = _catalog_provider_id_sets(catalog)
        hint_matches_active = (
            provider_raw == raw_active_provider
            or provider_raw == active_provider
            or (provider_normalized and provider_normalized == active_provider)
        )
        if hint_matches_active:
            # The @provider:model hint explicitly names the active provider, so this
            # selection is intentional — not a stale cross-provider artifact. Return
            # the full @provider:model string unchanged so downstream (resolve_model_provider
            # in config.py) can route through the correct provider. Stripping the prefix
            # here would collapse duplicate model IDs from different providers back to the
            # bare ID, causing the first matching provider to win on the next UI render
            # and the wrong provider to be used for the agent run. (#1253)
            return model, provider_raw, False

        if _catalog_has_provider(
            provider_raw,
            provider_normalized,
            raw_provider_ids,
            normalized_provider_ids,
        ):
            return model, provider_raw, False

        if _model_matches_active_provider_family(bare_model, active_provider):
            provider_context = (
                raw_active_provider
                if _should_attach_codex_provider_context(bare_model, raw_active_provider, catalog)
                else None
            )
            return bare_model, provider_context, True
        # On NON-explicit resolves (2nd+ turn, chat switch — explicit picks already
        # returned above), preserve the selection only when all three hold:
        #
        #   * provider_normalized == "" — a non-first-party provider hint
        #     (ollama-cloud / deepseek / xai / a named custom proxy). First-party
        #     families fall through to the stale-cross-provider repair below.
        #
        #   * the BARE model is not a first-party family id (does not start with
        #     gpt/claude/gemini), i.e. not a misrouted first-party model that a
        #     vanished provider used to host (e.g. "@copilot:claude-opus-4.6").
        #
        #   * the provider is KNOWN or CONFIGURED. This is the load-bearing
        #     distinction: catalog-absence has two causes —
        #       (a) a cold live-discovery provider (ollama-cloud is configured; its
        #           group just isn't in this cached snapshot yet) → preserve, and
        #       (b) a genuinely removed/unknown provider ("@removed:mistral-large"
        #           configured nowhere) → fall through to the default so chat/start
        #           doesn't route to an unreachable provider.
        #     _provider_is_known_or_configured() decides this from the static
        #     provider registry + config state, NOT from the cold catalog snapshot
        #     (re-deriving that live would defeat the prefer_cached_catalog win).
        #
        # DELIBERATE: the registry test treats a KNOWN built-in (deepseek, minimax,
        # ollama-cloud, …) as preservable even when the user has no key configured
        # for it. We accept this on purpose. The only fully-reliable "is this
        # provider authenticated" signal is the live auth store / catalog rebuild —
        # exactly the cost this hot path avoids — and a cheap config/env-only check
        # would mis-classify providers configured via OAuth/auth-store (ollama-cloud
        # among them), re-introducing the original silent-revert bug for them. So a
        # known-but-unconfigured pick is kept; the user gets a clear run-time auth
        # error instead of a silent swap to the default. Pinned by
        # test_at_provider_known_unconfigured_builtin_is_intentionally_preserved.
        #
        # KNOWN LIMITATION: the first-party-family test is a bare-name prefix match
        # (the same approximation _model_matches_active_provider_family uses). A
        # genuine third-party model whose name merely *starts* with gpt/claude/
        # gemini (e.g. "@ollama:gpt4all-mini") is therefore still mis-classified as
        # first-party and reverted on non-explicit paths. A name-based check cannot
        # disambiguate that; the behavior is pinned by
        # test_at_provider_first_party_named_third_party_model_known_limitation.
        _bare_is_first_party_family = any(
            bare_model.lower().startswith(_p) for _p in ("gpt", "claude", "gemini")
        )
        if (
            not provider_normalized
            and not _bare_is_first_party_family
            and _provider_is_known_or_configured(provider_raw)
        ):
            return model, provider_raw, False
        if default_model:
            provider_context = (
                raw_active_provider
                if _should_attach_codex_provider_context(default_model, raw_active_provider, catalog)
                else None
            )
            return default_model, provider_context, True
        return model, provider_raw, False

    slash = model.find("/")
    if slash < 0:
        if explicit_model_pick:
            # User explicitly chose this model; don't second-guess (#3737)
            return model, requested_provider, False
        model_lower = model.lower()
        for bare_prefix in ("gpt", "claude", "gemini"):
            if model_lower.startswith(bare_prefix):
                model_provider = _normalize_provider_id(bare_prefix)
                if model_provider and model_provider != active_provider and default_model:
                    provider_context = (
                        raw_active_provider
                        if _should_attach_codex_provider_context(default_model, raw_active_provider, catalog)
                        else None
                    )
                    return default_model, provider_context, True
                provider_context = (
                    raw_active_provider
                    if _should_attach_codex_provider_context(model, raw_active_provider, catalog)
                    else requested_provider
                )
                return model, provider_context, False
        return model, requested_provider, False

    model_provider = _normalize_provider_id(model[:slash])

    # For custom/openrouter active providers: only skip normalization when the
    # model's namespace prefix is actually routable by a group in the catalog.
    # A user who only has custom_providers configured (active_provider="custom")
    # with a stale session model like "openai/gpt-5.4-mini" would otherwise
    # never get cleaned up, causing "(unavailable)" to appear in the picker.
    if active_provider in {"custom", "openrouter"}:
        # These namespaces are always routable as-is — preserve them.
        if model_provider in {"", "custom", "openrouter"}:
            return model, requested_provider, False
        # Check if any catalog group can actually route this model's prefix.
        groups = catalog.get("groups") or []
        routable_provider_ids = {
            _normalize_provider_id(g.get("provider_id") or "") for g in groups
        }
        # openrouter group can route any provider/model namespace
        has_openrouter_group = any(
            (g.get("provider_id") or "") == "openrouter" for g in groups
        )
        if model_provider in routable_provider_ids or has_openrouter_group:
            return model, requested_provider, False
        # Model prefix is not routable — stale cross-provider reference, clear it.
        if default_model:
            return default_model, requested_provider, True
        return model, requested_provider, False

    # Skip normalization for models on custom/openrouter namespaces — these are
    # user-controlled and should never be silently replaced.
    #
    # OpenAI Codex is intentionally normalized to the OpenAI family above so bare
    # GPT IDs survive provider switches. Slash-qualified OpenAI IDs are different:
    # ``openai/gpt-...`` is the OpenRouter shape for OpenAI models, and
    # resolve_model_provider() routes that through OpenRouter when Codex is the
    # configured provider. Legacy sessions can carry that stale slash ID without
    # a saved model_provider, so repair it to the active Codex default unless the
    # session/request explicitly says it is an OpenRouter selection. (#1734)
    if (
        raw_active_provider == "openai-codex"
        and model_provider == "openai"
        and requested_provider in {None, "openai-codex"}
        and default_model
    ):
        # Persist provider_context = "openai-codex" unconditionally on this
        # repair path so the resolved shape is stable across resolutions
        # (Opus stage-303 SHOULD-FIX: avoid redundant repair-writes per
        # chat-start when the catalog-coverage check fails — e.g. if a
        # future Codex default is itself slash-prefixed). Once we've
        # decided the session belongs to Codex, persist that decision.
        return default_model, raw_active_provider, True

    # Also normalize when the model is from a known provider but the active provider
    # is an unlisted one (e.g. ollama-cloud) — active_provider is "" in that case
    # but raw_active_provider is set. If model_provider doesn't start with the raw
    # active provider name, the session model is stale. (#1023)
    _active_for_compare = active_provider or raw_active_provider
    if model_provider and model_provider not in {"", "custom", "openrouter"} and model_provider != _active_for_compare and default_model:
        return default_model, requested_provider, True
    return model, requested_provider, False


def _resolve_compatible_session_model(model_id: str | None) -> tuple[str, bool]:
    """Return (effective_model, model_was_normalized) for legacy callers."""
    effective_model, _provider, changed = _resolve_compatible_session_model_state(model_id)
    return effective_model, changed


def _normalize_session_model_in_place(session) -> str:
    original_model = getattr(session, "model", None) or ""
    original_provider = _clean_session_model_provider(
        getattr(session, "model_provider", None)
    )
    effective_model, effective_provider, changed = _resolve_compatible_session_model_state(
        original_model or None,
        original_provider,
    )
    provider_changed = effective_provider != original_provider
    # Only persist the correction if the session had an explicit model that needed changing.
    # Sessions with no model stored (empty/None) get the effective default returned without
    # a disk write — no need to rebuild the index for a fill-in-blank operation.
    if original_model and effective_model and (
        (changed and original_model != effective_model) or provider_changed
    ):
        if changed and original_model != effective_model:
            session.model = effective_model
        session.model_provider = effective_provider
        session.save(touch_updated_at=False)
    return effective_model


def _resolve_effective_session_model_for_display(session) -> str:
    """Resolve the model a session should display without mutating persisted state.

    `GET /api/session` should stay side-effect free. If a stale persisted model
    needs normalization for the current provider configuration, return the
    effective model for the response payload only and leave disk state alone.
    """
    original_model = getattr(session, "model", None) or ""
    requested_provider = getattr(session, "model_provider", None)
    _pp_provider, _pp_default, _pp_cfg = _read_profile_model_config(session, requested_provider)
    effective_model, _provider, _changed = _resolve_compatible_session_model_state(
        original_model or None,
        requested_provider,
        profile_provider=_pp_provider,
        profile_default_model=_pp_default,
        profile_config=_pp_cfg,
        # GET /api/session is a hot, side-effect-free per-tab/per-poll path.
        # It must never pay the cold live provider-catalog rebuild (a
        # botocore IMDS probe that cannot resolve on a non-AWS / WSL / corp
        # network, plus anthropic/openrouter /models). That rebuild is
        # un-cacheable here (auth.json fingerprint churn) so every cold call
        # cost ~10s and, run concurrently across browser tabs, serialized on
        # the models-cache lock and starved SSE/streaming -> BrokenPipe storm
        # (#multi-tab-streaming-interlock). The persisted session model is
        # authoritative; the catalog is only a default-model backstop, which
        # the network-free minimal catalog already provides.
        prefer_cached_catalog=True,
    )
    return effective_model or original_model


def _resolve_effective_session_model_provider_for_display(session) -> str | None:
    original_model = getattr(session, "model", None) or ""
    requested_provider = getattr(session, "model_provider", None)
    _pp_provider, _pp_default, _pp_cfg = _read_profile_model_config(session, requested_provider)
    _model, provider, _changed = _resolve_compatible_session_model_state(
        original_model or None,
        requested_provider,
        profile_provider=_pp_provider,
        profile_default_model=_pp_default,
        profile_config=_pp_cfg,
        # See _resolve_effective_session_model_for_display: same hot
        # side-effect-free GET /api/session path; must not trigger the cold
        # live rebuild. prefer_cached_catalog resolves from warm/disk cache
        # or the network-free minimal catalog.
        prefer_cached_catalog=True,
    )
    return provider

__all__ = ["_normalize_provider_id", "_read_profile_model_config", "_repair_bare_custom_provider_model", "_repair_foreign_session_model_provider", "_resolve_compatible_session_model_state", "_resolve_effective_session_model_for_display", "_resolve_effective_session_model_provider_for_display", "_split_provider_qualified_model", "resolve_chat_model_state"]
