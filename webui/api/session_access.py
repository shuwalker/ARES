"""Session ownership and mutation-boundary checks."""

from __future__ import annotations

from pathlib import Path
import json
import sqlite3


def state_db_session_source(session_id: str) -> str:
    from api.models import _active_state_db_path, is_safe_session_id

    if not session_id or not is_safe_session_id(session_id):
        return ""
    try:
        path = _active_state_db_path()
        if not path or not Path(path).exists():
            return ""
        with sqlite3.connect(str(path)) as connection:
            row = connection.execute(
                "SELECT source FROM sessions WHERE id = ?",
                (session_id,),
            ).fetchone()
    except Exception:
        return ""
    return str(row[0] or "").strip().lower() if row else ""


def is_subagent_child_session_id(session_id: str) -> bool:
    return state_db_session_source(session_id) == "subagent"


def session_is_subagent_view_only(session_id: str) -> bool:
    if is_subagent_child_session_id(session_id):
        return True
    try:
        from api.models import get_session

        session = get_session(session_id)
    except Exception:
        return False
    source = str(
        getattr(session, "source_tag", "")
        or getattr(session, "raw_source", "")
        or getattr(session, "session_source", "")
        or ""
    ).strip().lower()
    return source == "subagent"


def ensure_full_session_before_mutation(session_id: str, session):
    """Upgrade a cached metadata-only session before any persisted mutation."""

    if not getattr(session, "_loaded_metadata_only", False):
        return session
    from api.config import LOCK, SESSIONS
    from api.models import Session, _evict_sessions_over_cap

    loaded = Session.load(session_id)
    if loaded is None:
        raise KeyError(session_id)
    with LOCK:
        SESSIONS[session_id] = loaded
        SESSIONS.move_to_end(session_id)
        _evict_sessions_over_cap()
    return loaded


def lookup_cli_session_metadata(session_id: str, *, all_profiles: bool = False) -> dict:
    if not session_id:
        return {}
    try:
        from api.models import get_cli_sessions

        return next(
            (
                row
                for row in get_cli_sessions(all_profiles=all_profiles)
                if row.get("session_id") == session_id
            ),
            {},
        )
    except Exception:
        return {}


def is_messaging_session_record(session) -> bool:
    if not session:
        return False
    field = session.get if isinstance(session, dict) else lambda key, default=None: getattr(session, key, default)
    if field("session_source") == "messaging":
        return True
    from api.agent_sessions import MESSAGING_SOURCES

    for key in ("raw_source", "source_tag", "source", "source_label"):
        value = str(field(key) or "").strip().lower()
        if value in MESSAGING_SOURCES:
            return True
    return False


def apply_source_metadata(session, metadata: dict) -> None:
    from api.agent_sessions import is_cli_session_row

    session.is_cli_session = is_cli_session_row(metadata)
    session.source_tag = metadata.get("source_tag")
    session.raw_source = metadata.get("raw_source") or metadata.get("source_tag")
    session.session_source = metadata.get("session_source")
    session.source_label = metadata.get("source_label")
    for field in (
        "user_id",
        "chat_id",
        "chat_type",
        "thread_id",
        "session_key",
        "platform",
    ):
        setattr(session, field, metadata.get(field))


def session_index_marks_was_webui(session_id: str) -> bool:
    from api.config import SESSION_INDEX_FILE

    try:
        entries = json.loads(Path(SESSION_INDEX_FILE).read_text(encoding="utf-8"))
    except Exception:
        return False
    for entry in entries if isinstance(entries, list) else []:
        if entry.get("session_id") != session_id:
            continue
        sources = [
            str(entry.get(key) or "").strip().lower()
            for key in ("source_tag", "raw_source", "session_source")
        ]
        explicit = [source for source in sources if source]
        if any(source in {"webui", "fork"} for source in explicit):
            return True
        if explicit:
            return False
        return not bool(entry.get("is_cli_session") is True or entry.get("read_only") or entry.get("is_read_only"))
    return False


def is_claimable_cli_source(metadata: dict, state_source: str = "") -> tuple[bool, str]:
    values = metadata or {}
    if bool(values.get("read_only")):
        return False, "explicit_readonly"
    session_source = str(values.get("session_source") or "").strip().lower()
    if session_source in {"messaging", "external_agent", "external-agent"}:
        return False, f"session_source={session_source}"
    source = str(values.get("source_tag") or values.get("raw_source") or "").strip().lower()
    denied = {"claude_code", "cron", "external_agent", "gateway", "messaging", "subagent", "unknown"}
    if source in denied:
        return False, f"cli_meta_source={source}"
    if is_messaging_session_record(values):
        return False, "messaging_record"
    state_source = str(state_source or "").strip().lower()
    if not source and state_source in denied:
        return False, f"state_db_source={state_source}"
    return True, ""


def claim_or_synthesize_cli_session(session_id: str, cli_meta: dict | None = None):
    """Project a missing foreign session as writable or explicitly read-only."""

    from api.models import (
        DEFAULT_WORKSPACE,
        Session,
        _load_webui_deleted_session_tombstone,
        get_cli_session_messages,
        is_safe_session_id,
    )

    if not is_safe_session_id(session_id):
        return None, "invalid_sid"
    state_source = state_db_session_source(session_id)
    if (
        session_index_marks_was_webui(session_id)
        or (session_id in _load_webui_deleted_session_tombstone() and state_source in {"", "webui", "fork"})
    ) and state_source != "subagent":
        return None, "was_webui"
    metadata = dict(cli_meta if cli_meta is not None else lookup_cli_session_metadata(session_id))
    messages = get_cli_session_messages(session_id)
    if not messages:
        return None, "no_foreign_state"
    if state_source:
        metadata.setdefault("source_tag", state_source)
        metadata.setdefault("raw_source", state_source)
    workspace = metadata.get("workspace") or metadata.get("cwd")
    if not workspace:
        try:
            from api.workspace import get_last_workspace

            workspace = get_last_workspace()
        except Exception:
            workspace = DEFAULT_WORKSPACE
    claimable, _reason = is_claimable_cli_source(metadata, state_source)
    subagent = state_source == "subagent" or str(metadata.get("source_tag") or "").lower() == "subagent"
    session = Session(
        session_id=session_id,
        title=metadata.get("title") or "CLI Session",
        workspace=workspace,
        model=metadata.get("model") or "unknown",
        model_provider=metadata.get("model_provider"),
        messages=messages,
        created_at=metadata.get("created_at") or 0,
        updated_at=metadata.get("updated_at") or 0,
        profile=metadata.get("profile"),
        is_cli_session=not subagent,
        source_tag=metadata.get("source_tag"),
        raw_source=metadata.get("raw_source") or metadata.get("source_tag"),
        session_source=metadata.get("session_source"),
        source_label=metadata.get("source_label"),
        read_only=not claimable,
    )
    return session, "materialized" if claimable else "not_claimable"


_session_index_marks_was_webui = session_index_marks_was_webui
_is_claimable_cli_source = is_claimable_cli_source
_claim_or_synthesize_cli_session = claim_or_synthesize_cli_session


def get_or_materialize_session(session_id: str, *, refresh_cli_messages: bool = False):
    """Load a writable session, importing a regular CLI transcript when needed."""

    from api.models import (
        _session_messages_have_prefix,
        get_cli_session_messages,
        get_session,
        import_cli_session,
        title_from,
    )

    try:
        session = ensure_full_session_before_mutation(session_id, get_session(session_id))
        if getattr(session, "read_only", False):
            raise PermissionError("read-only imported session")
        source = str(
            getattr(session, "source_tag", "")
            or getattr(session, "raw_source", "")
            or ""
        ).strip().lower()
        if source == "subagent" or is_subagent_child_session_id(session_id):
            raise PermissionError("read-only subagent child session")
        if refresh_cli_messages and getattr(session, "is_cli_session", False):
            latest = get_cli_session_messages(
                session_id,
                profile=getattr(session, "profile", None),
            )
            current = list(getattr(session, "messages", None) or [])
            if latest and len(latest) >= len(current) and _session_messages_have_prefix(latest, current):
                session.messages = list(latest)
        return session
    except KeyError:
        pass

    metadata = lookup_cli_session_metadata(session_id)
    if not metadata:
        # Preserve the explicit foreign-session claiming seam for callers that
        # can classify a transcript even when it is absent from the aggregate
        # CLI catalog. Normal catalog entries continue through import_cli_session
        # below so durable history and metadata use one canonical importer.
        candidate, disposition = claim_or_synthesize_cli_session(session_id)
        if candidate is None:
            raise KeyError(session_id)
        if disposition != "materialized" or getattr(candidate, "read_only", False):
            raise PermissionError("read-only imported session")
        candidate.save()
        return candidate
    if bool(metadata.get("read_only")) or is_messaging_session_record(metadata):
        raise PermissionError("read-only imported session")

    messages = get_cli_session_messages(
        session_id,
        profile=metadata.get("profile"),
    )
    if not messages:
        raise KeyError(session_id)
    session = import_cli_session(
        session_id=session_id,
        title=metadata.get("title") or title_from(messages),
        messages=messages,
        model=metadata.get("model") or "unknown",
        profile=metadata.get("profile"),
        created_at=metadata.get("created_at"),
        updated_at=metadata.get("updated_at"),
        parent_session_id=metadata.get("parent_session_id"),
    )
    apply_source_metadata(session, metadata)
    return session


_state_db_session_source = state_db_session_source
_is_subagent_child_session_id = is_subagent_child_session_id
_session_is_subagent_view_only = session_is_subagent_view_only
_ensure_full_session_before_mutation = ensure_full_session_before_mutation
_get_or_materialize_session = get_or_materialize_session
_is_messaging_session_record = is_messaging_session_record
_lookup_cli_session_metadata = lookup_cli_session_metadata
