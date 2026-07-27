"""
ARES Email AI Assistant

Production-grade AI email management on top of native Mail.app.
"""

from .mail_assistant import MailAssistant, get_mail_assistant, EmailMessage, ThreadNode

__all__ = [
    "MailAssistant",
    "get_mail_assistant",
    "EmailMessage",
    "ThreadNode",
]
