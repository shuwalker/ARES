"""
Hermes Tool: email-ai-assistant

Exposes the native Mail.app AI assistant as callable tools for agents.
"""

from typing import Any, Dict, List

from .mail_assistant import MailAssistant, get_mail_assistant, Classification


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


def scan_all_emails(limit: int = 200) -> Dict[str, Any]:
    """Scan ALL inbox messages (read + unread). Inbox = TO-DO list."""
    assistant = get_mail_assistant()
    messages = assistant.scan_all(limit=limit)
    return {
        "count": len(messages),
        "unread": sum(1 for m in messages if not m.is_read),
        "read": sum(1 for m in messages if m.is_read),
        "messages": [
            {
                "id": m.id,
                "subject": m.subject,
                "sender": m.sender,
                "date": m.date_received,
                "is_read": m.is_read,
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


def classify_email(message_id: str) -> Dict[str, Any]:
    """Classify a single email (heuristic + LLM fallback)."""
    assistant = get_mail_assistant()
    msg = assistant.read_message(message_id)
    result = assistant.classify_message(msg)
    return {
        "message_id": result.message_id,
        "sender": result.sender,
        "subject": result.subject,
        "classification": result.classification,
        "method": result.method,
    }


def auto_clean_inbox(dry_run: bool = True, limit: int = 500) -> Dict[str, Any]:
    """
    Scan, classify, and clean the inbox.
    
    Actions: junk/newsletter → Junk, archive → NAS + Mail Archive, keep → inbox.
    Set dry_run=False to actually move messages.
    """
    assistant = get_mail_assistant()
    result = assistant.auto_clean(limit=limit, dry_run=dry_run)
    return result


def move_email_to_junk(message_id: str) -> Dict[str, Any]:
    """Move a message to Junk (account-aware routing)."""
    assistant = get_mail_assistant()
    success = assistant.move_to_junk(message_id)
    return {"message_id": message_id, "moved_to_junk": success}


def move_email_to_archive(message_id: str, sender: str = "", subject: str = "") -> Dict[str, Any]:
    """Move a message to Archive mailbox."""
    assistant = get_mail_assistant()
    success = assistant.move_to_archive(message_id, sender=sender, subject=subject)
    return {"message_id": message_id, "moved_to_archive": success}


# Tool registry for Hermes
TOOLS = {
    "list_unread_emails": list_unread_emails,
    "scan_all_emails": scan_all_emails,
    "read_email": read_email,
    "draft_reply": draft_reply,
    "classify_email": classify_email,
    "auto_clean_inbox": auto_clean_inbox,
    "move_email_to_junk": move_email_to_junk,
    "move_email_to_archive": move_email_to_archive,
}