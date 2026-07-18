"""Transport-neutral email operations for the ARES local Mail integration."""

from __future__ import annotations

import importlib.util
import logging
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any


logger = logging.getLogger(__name__)
_mail_assistant_cls = None


class EmailServiceError(RuntimeError):
    """Expected email integration failure with an HTTP-compatible status."""

    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def _get_mail_assistant_cls():
    global _mail_assistant_cls
    if _mail_assistant_cls is not None:
        return _mail_assistant_cls
    repo_root = Path(__file__).resolve().parent.parent.parent
    module_path = repo_root / "tools" / "email_ai_assistant" / "mail_assistant.py"
    spec = importlib.util.spec_from_file_location(
        "tools.email_ai_assistant.mail_assistant",
        str(module_path),
        submodule_search_locations=[],
    )
    if spec is None or spec.loader is None:
        raise EmailServiceError("email integration is not installed", 503)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        logger.exception("MailAssistant import failed")
        raise EmailServiceError("email integration is unavailable", 503) from exc
    _mail_assistant_cls = module.MailAssistant
    return _mail_assistant_cls


def _assistant():
    try:
        return _get_mail_assistant_cls()()
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("MailAssistant initialization failed")
        raise EmailServiceError("email integration is unavailable", 503) from exc


def _message_payload(message) -> dict[str, Any]:
    payload = asdict(message)
    body_html = payload.get("body_html")
    if isinstance(body_html, str) and len(body_html) > 50_000:
        payload["body_html_truncated"] = True
        payload["body_html"] = body_html[:50_000]
    return payload


def _message_id(value: Any) -> str:
    message_id = str(value or "").strip()
    if not message_id:
        raise EmailServiceError("missing required message id")
    if not message_id.isdigit():
        raise EmailServiceError("invalid message id")
    return message_id


def unread_messages(limit: int = 20) -> dict[str, Any]:
    try:
        messages = _assistant().list_unread(limit=max(1, min(int(limit), 50)))
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("list_unread failed")
        raise EmailServiceError("failed to list unread messages", 500) from exc
    return {"ok": True, "messages": [_message_payload(item) for item in messages]}


def all_messages(limit: int = 200) -> dict[str, Any]:
    limit = max(1, min(int(limit), 500))
    try:
        messages = _assistant().scan_all(limit=limit)
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("scan_all failed")
        raise EmailServiceError("failed to scan all messages", 500) from exc
    return {
        "ok": True,
        "total": len(messages),
        "unread": sum(1 for item in messages if not item.is_read),
        "read": sum(1 for item in messages if item.is_read),
        "messages": [_message_payload(item) for item in messages],
    }


def message_detail(message_id: Any) -> dict[str, Any]:
    message_id = _message_id(message_id)
    try:
        message = _assistant().read_message(message_id)
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("read_message failed for id=%s", message_id)
        raise EmailServiceError("failed to read message", 500) from exc
    return {"ok": True, "message": _message_payload(message)}


def classify_message(message_id: Any) -> dict[str, Any]:
    message_id = _message_id(message_id)
    try:
        assistant = _assistant()
        result = assistant.classify_message(assistant.read_message(message_id))
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("classify failed for id=%s", message_id)
        raise EmailServiceError("failed to classify message", 500) from exc
    return {
        "ok": True,
        "message_id": result.message_id,
        "sender": result.sender,
        "subject": result.subject,
        "classification": result.classification,
        "method": result.method,
    }


def message_thread(message_id: Any) -> dict[str, Any]:
    message_id = _message_id(message_id)
    try:
        assistant = _assistant()
        nodes = assistant.parse_thread(assistant.read_message(message_id))
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("thread parse failed for id=%s", message_id)
        raise EmailServiceError("failed to parse thread", 500) from exc
    return {
        "ok": True,
        "message_id": message_id,
        "thread": [
            {"level": node.level, "body": node.body, "meta": node.meta}
            for node in nodes
        ],
    }


def draft_reply(payload: dict[str, Any]) -> dict[str, Any]:
    message_id = _message_id(payload.get("id") or payload.get("message_id"))
    try:
        draft = _assistant().draft_reply(
            message_id,
            prompt=str(payload.get("instruction") or ""),
        )
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("draft_reply failed for id=%s", message_id)
        raise EmailServiceError("failed to generate draft", 500) from exc
    return {"ok": True, "draft": draft}


def clean_inbox(payload: dict[str, Any]) -> dict[str, Any]:
    try:
        limit = int(payload.get("limit", 200))
    except (TypeError, ValueError):
        limit = 200
    try:
        result = _assistant().auto_clean(
            limit=max(1, min(limit, 500)),
            dry_run=bool(payload.get("dry_run", True)),
        )
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("auto_clean failed")
        raise EmailServiceError("failed to clean inbox", 500) from exc
    return {"ok": True, "result": result}


def move_message(payload: dict[str, Any]) -> dict[str, Any]:
    message_id = _message_id(payload.get("id"))
    action = str(payload.get("action") or "")
    if action not in {"junk", "archive"}:
        raise EmailServiceError("action must be 'junk' or 'archive'")
    try:
        assistant = _assistant()
        if action == "junk":
            success = assistant.move_to_junk(message_id)
        else:
            success = assistant.move_to_archive(
                message_id,
                sender=str(payload.get("sender") or ""),
                subject=str(payload.get("subject") or ""),
            )
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("move failed for id=%s action=%s", message_id, action)
        raise EmailServiceError(f"failed to move message to {action}", 500) from exc
    return {"ok": True, "moved_to": action if success else "failed", "message_id": message_id}


def mark_message_read(payload: dict[str, Any]) -> dict[str, Any]:
    message_id = _message_id(payload.get("id") or payload.get("message_id"))
    try:
        success = _assistant().mark_read(message_id)
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("mark_read failed for id=%s", message_id)
        raise EmailServiceError("failed to mark message as read", 500) from exc
    return {"ok": True, "message_id": message_id, "marked_read": success}


def save_message_to_nas(payload: dict[str, Any]) -> dict[str, Any]:
    message_id = _message_id(payload.get("id") or payload.get("message_id"))
    sender = str(payload.get("sender") or "")
    subject = str(payload.get("subject") or "")
    try:
        assistant = _assistant()
        if not sender or not subject:
            message = assistant.read_message(message_id)
            sender = sender or message.sender
            subject = subject or message.subject
        subfolder = assistant.get_archive_subfolder(sender)
        saved = assistant.save_to_nas(message_id, sender, subject, subfolder)
    except EmailServiceError:
        raise
    except Exception as exc:
        logger.exception("save_to_nas failed for id=%s", message_id)
        raise EmailServiceError("failed to save to NAS", 500) from exc
    return {
        "ok": True,
        "message_id": message_id,
        "saved": saved,
        "subfolder": subfolder if saved else None,
    }


__all__ = [
    "EmailServiceError", "all_messages", "classify_message", "clean_inbox",
    "draft_reply", "mark_message_read", "message_detail", "message_thread",
    "move_message", "save_message_to_nas", "unread_messages",
]
