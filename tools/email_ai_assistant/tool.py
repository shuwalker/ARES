"""
Hermes Tool: email-ai-assistant

Exposes the native Mail.app AI assistant as a callable tool for agents.
"""

from typing import Any, Dict

from .mail_assistant import get_mail_assistant


def list_unread_emails(limit: int = 20) -> Dict[str, Any]:
    """List unread messages from the unified inbox."""
    assistant = get_mail_assistant()
    messages = assistant.list_unread(limit=limit)
    return {
        "count": len(messages),
        "messages": [
            {
                "id": m.id,
                "subject": m.subject,
                "sender": m.sender,
                "date": m.date_received,
                "account": m.account,
            }
            for m in messages
        ],
    }


def read_email(message_id: str) -> Dict[str, Any]:
    """Read a full email message."""
    assistant = get_mail_assistant()
    msg = assistant.read_message(message_id)
    return {
        "id": msg.id,
        "subject": msg.subject,
        "sender": msg.sender,
        "date": msg.date_received,
        "is_read": msg.is_read,
        "body_plain": msg.body_plain[:2000] if msg.body_plain else "",
        "account": msg.account,
    }


def draft_reply(message_id: str, instruction: str) -> Dict[str, Any]:
    """Generate a draft reply for a message."""
    assistant = get_mail_assistant()
    draft = assistant.draft_reply(message_id, instruction)
    return {
        "message_id": message_id,
        "draft": draft,
        "status": "draft_generated",
    }


# Tool registry for Hermes
TOOLS = {
    "list_unread_emails": list_unread_emails,
    "read_email": read_email,
    "draft_reply": draft_reply,
}
