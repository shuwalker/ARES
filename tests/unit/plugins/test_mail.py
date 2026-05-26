"""Unit tests for ARES mail triage classifier."""

from __future__ import annotations

import pytest

from ares.plugins.mail.models import EmailMessage
from ares.plugins.mail.rules import classify, extract_real_domain, is_spoof, should_rescue


@pytest.mark.parametrize(
    "sender, expected",
    [
        ("hello@example.com", "example.com"),
        ("hello_at_ollama_com_97j7zz9fsq0932_5a3bffed@icloud.com", "ollama.com"),
        ("update_at_dotcards_net_k5edgz70dw60kh_829n5010@icloud.com", "dotcards.net"),
        ("user@privaterelay.appleid.com", "privaterelay.appleid.com"),
    ],
)
def test_extract_real_domain(sender, expected):
    assert extract_real_domain(sender.lower()) == expected


def test_priority_family_email():
    msg = EmailMessage(id="1", account="mock", sender="dnljenkins5@yahoo.com", subject="Hey bro")
    label, rule = classify(msg)
    assert label == "PRIORITY"
    assert "priority_allowlist" in rule


def test_apple_card_statement_is_priority():
    """Apple Card is PRIORITY because it's in priority allowlist."""
    msg = EmailMessage(
        id="2", account="mock",
        sender="no-reply@post.applecard.apple",
        subject="Your Apple Card statement is ready",
    )
    label, rule = classify(msg)
    assert label == "PRIORITY"
    assert "priority_allowlist" in rule


def test_chase_alert_is_priority():
    msg = EmailMessage(
        id="3", account="mock",
        sender="no.reply.alerts@chase.com",
        subject="Payment has been received",
    )
    label, rule = classify(msg)
    assert label == "PRIORITY"
    assert "priority_allowlist" in rule


def test_paypal_is_priority():
    msg = EmailMessage(
        id="4", account="mock",
        sender="noreply@service.paypal.com",
        subject="New sign-in detected",
    )
    label, rule = classify(msg)
    assert label == "PRIORITY"
    assert "priority_allowlist" in rule


def test_transactional_keep_subject():
    """Subject patterns save no-reply transactional mail from junk."""
    msg = EmailMessage(
        id="5", account="mock",
        sender="noreply@somebank.com",
        subject="Payment has been received",
    )
    label, rule = classify(msg)
    assert label == "KEEP"
    assert "keep_subject" in rule


def test_marketing_sender_junk():
    msg = EmailMessage(
        id="6", account="mock", sender="deals@marketing.biz", subject="30% off today only!",
    )
    label, rule = classify(msg)
    assert label == "JUNK"
    assert "junk_sender" in rule


def test_bulk_subdomain_junk():
    msg = EmailMessage(
        id="7", account="mock", sender="update@email.brand.com", subject="Weekly digest",
    )
    label, rule = classify(msg)
    assert label == "JUNK"


def test_flash_sale_junk():
    msg = EmailMessage(
        id="8", account="mock", sender="newsletter@store.com", subject="Flash sale - 50% off!",
    )
    label, rule = classify(msg)
    assert label == "JUNK"


def test_list_unsubscribe_junk():
    msg = EmailMessage(
        id="9", account="mock",
        sender="noreply@promo.biz",
        subject="Hello there",
        has_unsubscribe=True,
    )
    label, rule = classify(msg)
    assert label == "JUNK"
    assert "list_unsubscribe" in rule


def test_list_unsubscribe_protected_by_keep_subject():
    """Amazon order confirmation with List-Unsubscribe should be KEPT."""
    msg = EmailMessage(
        id="10", account="mock",
        sender="order-update@amazon.com",
        subject="Your order has been confirmed",
        has_unsubscribe=True,
    )
    label, rule = classify(msg)
    assert label == "KEEP"


def test_apple_support_spoof():
    msg = EmailMessage(
        id="11", account="mock",
        sender="Apple Support Team <matthew_jenkins16@dataart.pro>",
        subject="Your account needs verification",
    )
    label, rule = classify(msg)
    assert label == "JUNK"
    assert "spoof" in rule


def test_unknown_real_person_priority():
    msg = EmailMessage(
        id="12", account="mock",
        sender="Jane Smith <jane.smith@company.com>",
        subject="Meeting tomorrow",
    )
    label, rule = classify(msg)
    assert label == "PRIORITY"


def test_rescue_bank_statement():
    msg = EmailMessage(id="13", account="mock", sender="nores@chase.com", subject="Your statement is ready")
    assert should_rescue(msg) is True


def test_no_rescue_marketing():
    msg = EmailMessage(id="14", account="mock", sender="deals@newsletter.bulk.com", subject="50% off sale!")
    assert should_rescue(msg) is False


def test_no_rescue_spoof():
    msg = EmailMessage(
        id="15", account="mock",
        sender="Apple Support <user@dataart.pro>",
        subject="Account alert",
    )
    assert should_rescue(msg) is False


def test_icloud_relay_priority():
    msg = EmailMessage(
        id="16", account="mock",
        sender="hello_at_ollama_com_97j7zz9fsq0932@icloud.com",
        subject="Ollama 0.6.0 released",
    )
    domain = extract_real_domain(msg.sender_lower)
    assert domain == "ollama.com"
    label, rule = classify(msg)
    assert label == "PRIORITY"


def test_verification_code_phishing_overrides():
    r"""Phishing with 'verification code ... unlock access' should be JUNK."""
    msg = EmailMessage(
        id="17", account="mock",
        sender="noreply@lovelyfun.com",
        subject="Verification Code - unlock your access to exclusive deals",
    )
    label, rule = classify(msg)
    assert label == "JUNK"
