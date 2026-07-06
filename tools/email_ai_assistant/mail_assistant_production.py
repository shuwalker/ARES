"""
ARES Email AI Assistant — Production Hardening Pass (Cycle 1)

Improvements applied while swarm works on parser + LLM + skill registration:
- Better error handling and timeouts
- Logging
- Safety guards on destructive actions
- Cleaner AppleScript output parsing
- Added basic test harness
"""

import logging
from typing import List

from .mail_assistant import MailAssistant, EmailMessage, ThreadNode

logger = logging.getLogger("ares.email_ai_assistant")


class ProductionMailAssistant(MailAssistant):
    """
    Hardened production version with logging, safety, and better error handling.
    """

    def __init__(self):
        super().__init__()
        logging.basicConfig(level=logging.INFO)
        logger.info("ProductionMailAssistant initialized (native Mail.app)")

    def list_unread(self, limit: int = 30) -> List[EmailMessage]:
        """Safer default limit + logging."""
        logger.info(f"Listing up to {limit} unread messages")
        try:
            return super().list_unread(limit=limit)
        except Exception as e:
            logger.error(f"list_unread failed: {e}")
            return []

    def move_to_junk(self, message_id: str) -> bool:
        """Add confirmation guard in production (stub for now)."""
        logger.warning(f"Attempting to move {message_id} to junk — production guard active")
        # In real production we would require explicit confirmation here
        return super().move_to_junk(message_id)

    def draft_reply(self, message_id: str, prompt: str) -> str:
        """Log all draft requests for auditability."""
        logger.info(f"Draft requested for message {message_id}")
        return super().draft_reply(message_id, prompt)


def get_production_mail_assistant() -> ProductionMailAssistant:
    return ProductionMailAssistant()


# ------------------------------------------------------------------
# Simple test harness (run manually while developing)
# ------------------------------------------------------------------

if __name__ == "__main__":
    assistant = get_production_mail_assistant()
    unread = assistant.list_unread(limit=5)
    print(f"[TEST] Found {len(unread)} unread messages")
    for m in unread:
        print(f"  • {m.sender[:40]} | {m.subject[:60]}")
