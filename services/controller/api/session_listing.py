"""Session-list reconciliation policies shared by API transports.

This module owns sidebar-specific cleanup.  Keeping the policy here prevents
the HTTP transport from becoming the owner of session durability rules.
"""

from __future__ import annotations


def session_lineage_ids(session: dict) -> set[str]:
    if not isinstance(session, dict):
        return set()
    return {
        str(session[key])
        for key in ("session_id", "_lineage_root_id", "_lineage_tip_id")
        if session.get(key)
    }


def session_source_is_webui(session: dict) -> bool:
    if not isinstance(session, dict):
        return False
    values = {
        str(session.get(key) or "").strip().lower().replace("-", "_")
        for key in ("source", "source_tag", "raw_source", "session_source", "source_label")
    }
    return bool(values & {"webui", "web_ui", "web"})


def is_duplicate_webui_state_projection(session: dict, represented_webui_ids: set[str]) -> bool:
    return session_source_is_webui(session) and bool(
        session_lineage_ids(session) & represented_webui_ids
    )


_is_duplicate_webui_state_projection = is_duplicate_webui_state_projection


def _numeric_count(value) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def prune_orphaned_agent_sidecars(rows: list[dict], cli_rows: list[dict]) -> list[dict]:
    """Drop imported CLI/API sidecars whose authoritative state row vanished.

    Native WebUI rows are never candidates, even when they carry ancestry from
    a CLI conversation.  The state database probe deliberately fails open.
    """

    from api.agent_sessions import is_cli_session_row
    from api.models import agent_session_rows_existing, prune_session_from_index

    visible_cli_ids = {
        str(row.get("session_id") or "").strip()
        for row in cli_rows
        if isinstance(row, dict) and str(row.get("session_id") or "").strip()
    }
    candidates: list[dict] = []
    kept: list[dict] = []
    for row in rows:
        sid = str(row.get("session_id") or "").strip() if isinstance(row, dict) else ""
        source = str((row or {}).get("source_tag") or (row or {}).get("source") or "").lower()
        imported = is_cli_session_row(row) or source in {"api", "api_server", "api-server"}
        if sid and imported and not session_source_is_webui(row) and sid not in visible_cli_ids:
            candidates.append(row)
        else:
            kept.append(row)
    by_profile: dict[str | None, list[dict]] = {}
    for row in candidates:
        by_profile.setdefault(row.get("profile"), []).append(row)
    for profile, profile_rows in by_profile.items():
        ids = [str(row.get("session_id") or "").strip() for row in profile_rows]
        existing = agent_session_rows_existing(ids, profile=profile or None)
        for row in profile_rows:
            sid = str(row.get("session_id") or "").strip()
            if sid in existing:
                kept.append(row)
                continue
            prune_session_from_index(sid)
    return kept


def prune_orphaned_webui_zero_message_sessions(rows: list[dict]) -> list[dict]:
    """Hide native WebUI sidebar rows with no durable transcript.

    Active, pending, and worktree-bound rows are protected.  A sidecar with
    messages is also authoritative enough to retain the row while state.db is
    catching up.  Tombstones prevent the index recovery loop from recreating a
    confirmed empty row and self-heal when messages later appear.
    """

    from api.models import (
        Session,
        _clear_webui_zero_message_orphan_tombstone,
        _load_webui_zero_message_orphan_tombstone,
        _record_webui_zero_message_orphan_tombstone,
        agent_session_zero_message_sids,
        prune_session_from_index,
    )

    protected: list[dict] = []
    candidates: list[dict] = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        candidate = (
            session_source_is_webui(row)
            and not row.get("active_stream_id")
            and not row.get("has_pending_user_message")
            and not row.get("pending_user_message")
            and not row.get("worktree_path")
            and (
                str(row.get("title") or "Untitled") != "Untitled"
                or _numeric_count(row.get("message_count")) > 0
            )
        )
        (candidates if candidate else protected).append(row)
    if not candidates:
        return list(rows)

    tombstoned = set(_load_webui_zero_message_orphan_tombstone())
    by_profile: dict[str | None, list[dict]] = {}
    for row in candidates:
        by_profile.setdefault(row.get("profile"), []).append(row)
    retained = list(protected)
    for profile, profile_rows in by_profile.items():
        ids = [str(row.get("session_id") or "").strip() for row in profile_rows]
        empty_ids = set(agent_session_zero_message_sids(ids, profile=profile or None))
        for row in profile_rows:
            sid = str(row.get("session_id") or "").strip()
            if sid not in empty_ids:
                if sid in tombstoned:
                    _clear_webui_zero_message_orphan_tombstone(sid)
                retained.append(row)
                continue
            try:
                sidecar = Session.load(sid)
                has_sidecar_messages = bool(sidecar and list(sidecar.messages or []))
            except Exception:
                has_sidecar_messages = False
            if has_sidecar_messages:
                if sid in tombstoned:
                    _clear_webui_zero_message_orphan_tombstone(sid)
                retained.append(row)
                continue
            if sid not in tombstoned:
                prune_session_from_index(sid)
                _record_webui_zero_message_orphan_tombstone(sid)
    return retained


__all__ = [
    "is_duplicate_webui_state_projection",
    "prune_orphaned_agent_sidecars",
    "prune_orphaned_webui_zero_message_sessions",
    "session_lineage_ids",
    "session_source_is_webui",
]
