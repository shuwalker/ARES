"""
ARES WebUI — Email API routes.

Thin wrapper around tools/email_ai_assistant/mail_assistant.py MailAssistant.
Exposes read-only + action endpoints for the Email panel.
"""

from __future__ import annotations

import importlib.util
import logging
from dataclasses import asdict
from pathlib import Path
from urllib.parse import parse_qs

from api.helpers import bad, j

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Lazy import helper — avoids hitting Mail.app at module-load time and keeps
# the import robust when running on non-macOS or without the repo on sys.path.
# ---------------------------------------------------------------------------

_mail_assistant_cls = None


def _get_mail_assistant_cls():
    """Import MailAssistant on first use and cache the class reference.

    Uses importlib.util to load directly from the repo's ``tools/`` directory
    so that no other ``tools`` package on ``sys.path`` can shadow it.
    """
    global _mail_assistant_cls
    if _mail_assistant_cls is not None:
        return _mail_assistant_cls

    # Resolve the MailAssistant module by absolute filesystem path so that
    # a different ``tools`` package on sys.path cannot shadow the real one.
    repo_root = Path(__file__).resolve().parent.parent.parent
    mod_path = repo_root / "tools" / "email_ai_assistant" / "mail_assistant.py"

    spec = importlib.util.spec_from_file_location(
        "tools.email_ai_assistant.mail_assistant",
        str(mod_path),
        submodule_search_locations=[],
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot find MailAssistant module at {mod_path}")

    mod = importlib.util.module_from_spec(spec)
    # Register under the fully-qualified name so relative imports inside
    # the module resolve correctly.
    import sys as _sys

    _sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)

    _mail_assistant_cls = mod.MailAssistant
    return _mail_assistant_cls


def _new_assistant():
    """Instantiate a MailAssistant, returning (assistant, error_response).

    Returns (assistant, None) on success, or (None, error_payload_dict) on
    failure so the caller can return ``bad(handler, ...)`` directly.
    """
    try:
        cls = _get_mail_assistant_cls()
        return cls(), None
    except Exception as exc:
        logger.exception("MailAssistant init failed")
        # Sanitize — never expose env vars / API keys / filesystem paths.
        msg = str(exc)
        for secret in ("OLLAMA_API_KEY", "API_KEY", "PASSWORD"):
            if secret in msg.upper():
                msg = "internal configuration error"
                break
        return None, msg


# ---------------------------------------------------------------------------
# EmailMessage → JSON-safe dict
# ---------------------------------------------------------------------------

def _message_to_dict(msg) -> dict:
    """Convert an EmailMessage dataclass to a JSON-safe dict."""
    d = asdict(msg)
    # Strip potentially large HTML; the frontend can request it explicitly
    # via the message detail endpoint if needed.
    if "body_html" in d and len(d.get("body_html", "")) > 50000:
        d["body_html_truncated"] = True
        d["body_html"] = d["body_html"][:50000]
    return d


# ---------------------------------------------------------------------------
# GET /api/email/unread
# ---------------------------------------------------------------------------

def handle_email_unread_get(handler, parsed) -> bool:
    """GET /api/email/unread?limit=10 → {ok: true, messages: [...]}"""
    query = parse_qs(parsed.query or "")
    raw_limit = query.get("limit", ["20"])[0]
    try:
        limit = int(raw_limit)
    except (ValueError, TypeError):
        limit = 20
    # Clamp to [1, 50]
    limit = max(1, min(limit, 50))

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        messages = assistant.list_unread(limit=limit)
    except Exception:
        logger.exception("list_unread failed")
        return bad(handler, "failed to list unread messages", status=500)

    return j(handler, {
        "ok": True,
        "messages": [_message_to_dict(m) for m in messages],
    })


# ---------------------------------------------------------------------------
# GET /api/email/all  (scan_all — read + unread)
# ---------------------------------------------------------------------------

def handle_email_all_get(handler, parsed) -> bool:
    """GET /api/email/all?limit=200 → {ok: true, messages: [...], unread: N, read: N}"""
    query = parse_qs(parsed.query or "")
    raw_limit = query.get("limit", ["200"])[0]
    try:
        limit = int(raw_limit)
    except (ValueError, TypeError):
        limit = 200
    limit = max(1, min(limit, 500))

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        messages = assistant.scan_all(limit=limit)
    except Exception:
        logger.exception("scan_all failed")
        return bad(handler, "failed to scan all messages", status=500)

    return j(handler, {
        "ok": True,
        "total": len(messages),
        "unread": sum(1 for m in messages if not m.is_read),
        "read": sum(1 for m in messages if m.is_read),
        "messages": [_message_to_dict(m) for m in messages],
    })


# ---------------------------------------------------------------------------
# GET /api/email/message
# ---------------------------------------------------------------------------

def handle_email_message_get(handler, parsed) -> bool:
    """GET /api/email/message?id=… → {ok: true, message: {…}}"""
    query = parse_qs(parsed.query or "")
    message_id = (query.get("id") or [""])[0].strip()
    if not message_id:
        return bad(handler, "missing required query param: id", status=400)
    if not message_id.isdigit():
        return bad(handler, "invalid message id", status=400)

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        msg = assistant.read_message(message_id)
    except Exception:
        logger.exception("read_message failed for id=%s", message_id)
        return bad(handler, "failed to read message", status=500)

    return j(handler, {"ok": True, "message": _message_to_dict(msg)})


# ---------------------------------------------------------------------------
# GET /api/email/classify
# ---------------------------------------------------------------------------

def handle_email_classify_get(handler, parsed) -> bool:
    """GET /api/email/classify?id=… → {ok: true, classification, method, sender, subject}"""
    query = parse_qs(parsed.query or "")
    message_id = (query.get("id") or [""])[0].strip()
    if not message_id:
        return bad(handler, "missing required query param: id", status=400)
    if not message_id.isdigit():
        return bad(handler, "invalid message id", status=400)

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        msg = assistant.read_message(message_id)
        result = assistant.classify_message(msg)
    except Exception:
        logger.exception("classify failed for id=%s", message_id)
        return bad(handler, "failed to classify message", status=500)

    return j(handler, {
        "ok": True,
        "message_id": result.message_id,
        "sender": result.sender,
        "subject": result.subject,
        "classification": result.classification,
        "method": result.method,
    })


# ---------------------------------------------------------------------------
# POST /api/email/draft
# ---------------------------------------------------------------------------

def handle_email_draft_post(handler, parsed, body: dict) -> bool:
    """POST /api/email/draft → {ok: true, draft: '…'}

    Body: {id or message_id: str, instruction?: str}
    """
    message_id = body.get("id") or body.get("message_id") or ""
    if isinstance(message_id, str):
        message_id = message_id.strip()
    if not message_id:
        return bad(handler, "missing required field: id (or message_id)", status=400)
    if not str(message_id).isdigit():
        return bad(handler, "invalid message id", status=400)

    instruction = body.get("instruction") or ""

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        draft = assistant.draft_reply(str(message_id), prompt=str(instruction))
    except Exception:
        logger.exception("draft_reply failed for id=%s", message_id)
        return bad(handler, "failed to generate draft", status=500)

    return j(handler, {"ok": True, "draft": draft})


# ---------------------------------------------------------------------------
# POST /api/email/clean
# ---------------------------------------------------------------------------

def handle_email_clean_post(handler, parsed, body: dict) -> bool:
    """POST /api/email/clean → {ok: true, result: {…}}

    Body: {dry_run?: bool, limit?: int}
    Default is dry_run=true (safe preview). Set dry_run=false to actually move messages.
    """
    dry_run = body.get("dry_run", True)
    limit = body.get("limit", 200)
    try:
        limit = int(limit)
    except (ValueError, TypeError):
        limit = 200
    limit = max(1, min(limit, 500))

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        result = assistant.auto_clean(limit=limit, dry_run=bool(dry_run))
    except Exception:
        logger.exception("auto_clean failed")
        return bad(handler, "failed to clean inbox", status=500)

    # Remove messages list from result to keep response small
    return j(handler, {"ok": True, "result": result})


# ---------------------------------------------------------------------------
# POST /api/email/move
# ---------------------------------------------------------------------------

def handle_email_move_post(handler, parsed, body: dict) -> bool:
    """POST /api/email/move → {ok: true, moved_to: str}

    Body: {id: str, action: "junk"|"archive", sender?: str, subject?: str}
    """
    message_id = body.get("id") or ""
    action = body.get("action") or ""
    sender = body.get("sender") or ""
    subject = body.get("subject") or ""

    if not message_id:
        return bad(handler, "missing required field: id", status=400)
    if not str(message_id).isdigit():
        return bad(handler, "invalid message id", status=400)
    if action not in ("junk", "archive"):
        return bad(handler, "action must be 'junk' or 'archive'", status=400)

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        if action == "junk":
            success = assistant.move_to_junk(str(message_id))
            label = "junk"
        else:
            success = assistant.move_to_archive(str(message_id), sender=sender, subject=subject)
            label = "archive"
    except Exception:
        logger.exception("move failed for id=%s action=%s", message_id, action)
        return bad(handler, f"failed to move message to {label}", status=500)

    return j(handler, {"ok": True, "moved_to": label if success else "failed", "message_id": str(message_id)})


# ---------------------------------------------------------------------------
# POST /api/email/mark_read
# ---------------------------------------------------------------------------

def handle_email_mark_read_post(handler, parsed, body: dict) -> bool:
    """POST /api/email/mark_read → {ok: true, message_id: str}

    Body: {id: str}
    """
    message_id = body.get("id") or body.get("message_id") or ""
    if isinstance(message_id, str):
        message_id = message_id.strip()
    if not message_id:
        return bad(handler, "missing required field: id", status=400)
    if not str(message_id).isdigit():
        return bad(handler, "invalid message id", status=400)

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        success = assistant.mark_read(str(message_id))
    except Exception:
        logger.exception("mark_read failed for id=%s", message_id)
        return bad(handler, "failed to mark message as read", status=500)

    return j(handler, {"ok": True, "message_id": str(message_id), "marked_read": success})


# ---------------------------------------------------------------------------
# GET /api/email/thread
# ---------------------------------------------------------------------------

def handle_email_thread_get(handler, parsed) -> bool:
    """GET /api/email/thread?id=… → {ok: true, thread: [{level, body, meta}, …]}

    Parses the email thread structure from the message body.
    """
    query = parse_qs(parsed.query or "")
    message_id = (query.get("id") or [""])[0].strip()
    if not message_id:
        return bad(handler, "missing required query param: id", status=400)
    if not message_id.isdigit():
        return bad(handler, "invalid message id", status=400)

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        msg = assistant.read_message(message_id)
        thread = assistant.parse_thread(msg)
    except Exception:
        logger.exception("thread parse failed for id=%s", message_id)
        return bad(handler, "failed to parse thread", status=500)

    nodes = [{"level": n.level, "body": n.body, "meta": n.meta} for n in thread]
    return j(handler, {"ok": True, "message_id": str(message_id), "thread": nodes})


# ---------------------------------------------------------------------------
# POST /api/email/save_nas
# ---------------------------------------------------------------------------

def handle_email_save_nas_post(handler, parsed, body: dict) -> bool:
    """POST /api/email/save_nas → {ok: true, saved: bool}

    Body: {id: str, sender?: str, subject?: str}
    Saves email content to the NAS archive before removing from inbox.
    """
    message_id = body.get("id") or body.get("message_id") or ""
    if isinstance(message_id, str):
        message_id = message_id.strip()
    sender = body.get("sender") or ""
    subject = body.get("subject") or ""
    if not message_id:
        return bad(handler, "missing required field: id", status=400)
    if not str(message_id).isdigit():
        return bad(handler, "invalid message id", status=400)

    assistant, err = _new_assistant()
    if err is not None:
        return bad(handler, err, status=503)

    try:
        # Read the message to get sender/subject if not provided
        if not sender or not subject:
            msg = assistant.read_message(str(message_id))
            sender = sender or msg.sender
            subject = subject or msg.subject
        subfolder = assistant.get_archive_subfolder(sender)
        saved = assistant.save_to_nas(str(message_id), sender, subject, subfolder)
    except Exception:
        logger.exception("save_to_nas failed for id=%s", message_id)
        return bad(handler, "failed to save to NAS", status=500)

    return j(handler, {
        "ok": True,
        "message_id": str(message_id),
        "saved": saved,
        "subfolder": subfolder if saved else None,
    })