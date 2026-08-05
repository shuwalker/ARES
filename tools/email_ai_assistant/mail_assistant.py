#!/usr/bin/env python3
"""
ARES Email AI Assistant — Native Mail.app Edition

This module provides production-grade AI assistant capabilities for email
using the already-authenticated native Mail.app as the single source of truth.

It replaces the custom IMAP layer from Odysseus with AppleScript access
while preserving the high-value MCP-style tool surface and thread parsing.

Core capabilities:
- List unread / all messages (unified inbox)
- Read full message content (subject, sender, body, attachments metadata)
- Parse threaded conversations
- Generate AI drafts for replies
- Classify messages (heuristic + LLM fallback)
- Auto-clean: move junk/newsletters to junk, archive receipts/statements
- Save categorized archives to NAS

Mail philosophy (configurable per operator, see ares_mail_config.py):
Inbox = TO-DO list. Junk/newsletters = trash. Receipts/statements = archive.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
import urllib.request
import urllib.error
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

try:
    from . import ares_mail_config as _cfg
except ImportError:
    # Running as a standalone script (python mail_assistant.py ...) rather
    # than as a package member — fall back to a path-based import.
    import sys as _sys

    _sys.path.insert(0, str(Path(__file__).resolve().parent))
    import ares_mail_config as _cfg

# Reuse proven patterns from apple-mail-management skill
# (sender-filter batching, unified inbox, macOS 27 workarounds)

APPLESCRIPT_TIMEOUT = 60  # seconds for long operations

# ── Classification categories ──────────────────────────────────────────

class Classification:
    KEEP = "keep"
    JUNK = "junk"
    NEWSLETTER = "newsletter"
    ARCHIVE = "archive"

# ── Known junk domains (heuristic — fast path, no LLM needed) ──────────

JUNK_DOMAINS = [
    "senheguang.com", "hankukevent.com", "enableearn.com",
    "exclusiveeoffers.org", "preservented.nl", "horisora.net",
    "scandigenough.com", "freiraffirm.net", "tumorosa.media",
    "palaceextend.com", "itchynumberless.org", "friencept.net",
    "paxgoods.store", "chichahejiu.com", "zippyblinkoshop.com",
    "financebalancestrong.com", "budgetcontrolfinancehub.info",
    "bestshoppingcollective.info", "ordertopbrands.info",
    "skayouth.co.uk", "completecapitalplan.com",
    "clickaddcartandenjoy.info", "homelivingspace.info",
    "approvedfinancialwork.org", "capitalinsightpro.info",
    "trustedhomesolutionshub.info", "allaroundhomesolution.info",
    "smartfinanceinfrastructure.org", "globalwealthinsight.info",
    "financeloanmasters.com", "financialelevations.info",
    "stronghealthcareplan.com", "efficienthomeplans.com",
    "homeevolutionstudio.com", "investwithclarity.info",
    "modernlivingsolutions.org", "practiallfinancehelp.info",
    "dwellingmodernization.info", "refinancefinsolutions.info",
    "creativelivingspot.info", "sustainpersonalfinance.com",
    "savespendandinvest.com", "connectedfinancehub.info",
    "ifw.insightfulword.com", "news.theinvestorforge.com",
    "delamoms.com", "9K8hcmKAO1Yw4i.com",
    "nokiamail.com", "datehookup.com", "chatroulette.com",
    "instantloves.xyz", "boganet.cl", "steampowers.net",
    "uvvu.com", "flixstermail.com", "twxcarry.net",
    "iemail.moneylion.com", "coalax.com",
    # Financial scam domains (2026-06-25)
    "smartfinanceinfrastructure.org", "globalwealthinsight.info",
    "financeloanmasters.com", "financialelevations.info",
    "stronghealthcareplan.com", "efficienthomeplans.com",
    "homeevolutionstudio.com", "investwithclarity.info",
    "modernlivingsolutions.org", "practiallfinancehelp.info",
    "dwellingmodernization.info", "refinancefinsolutions.info",
    "creativelivingspot.info", "sustainpersonalfinance.com",
    "savespendandinvest.com", "connectedfinancehub.info",
    "saleseasonsaviornow.info", "financereservefund.com",
    "financialsolutionnavigator.info", "alternativeassetacquisition.com",
    "advancedcapitalwealth.info", "comenfr.com", "wealthifedebtfree.info",
    "quickdealshopping.info", "shoppingcartsonline.info",
    "shoppointcloud.com", "digitalshoppingcart.info",
    "smartcartdeals.org", "capitalequityfinance.com",
    "bagitandtagitfast.com", "settledebtdirect.com",
    "basketanalysiszone.com", "dreamhomerealtymaker.info",
    "primeshoptrack.com", "connectedfinancialsystems.info",
    "wealthgrowthcapital.com", "fixhomemaintenance.info",
    "goodsbuyzone.info", "debtreliefres.com", "digitalerafinance4u.com",
    "securehealth-plans.com", "personalfinancegrowth.com",
    "finnovawealthsolutions.com", "elegantnestplan.com",
    "toptierfinance.info", "helpingsllfinances.info",
    "creditstandingpro.com", "healthcaremediplus.com",
    "getfinancialwisdom.info", "healthfirstwellness.org",
    "realhomecomforts.com", "inspiredhomevision.org",
    "codeiog.com", "grabgearshop.com", "reviveyourresidence.com",
    "releasablepastiche.net",
    "mail.smilegeneration.com", "mail.award-headquarters.com",
    "e.epiqnotice.com", "clientexperience.citi.com",
]

# ── Known newsletter/promo domains (heuristic — archive, not trash) ────

NEWSLETTER_DOMAINS = [
    "journeys.com", "beehiiv.com", "coinbase.com",
    "sierraattahoe.com", "stubhub.com", "505games.com",
    "greatworkperks.com", "august.com", "cyncsmart.com",
    "keto-mojo.com", "forged4x4.com", "ecoflow.com",
    "wallethub.com", "harborfreight.com", "atlassian.com",
    "eufymega.com", "progressive.com", "onewheel.com",
    "rocketmoney.com", "hilton.com", "sonos.com",
    "sparkmailapp.com", "23andme.com", "dbrand.com",
    "shein.com", "dominos.com", "sephora.com",
    "e-email.guns.com", "email.benihana.com", "mail.quicken.com",
    "mail.visible.com", "paperlike.com", "spotify.com",
    "greenchef.com", "audible.com", "withings.com",
    "norwegianreward.com", "petlink.net", "expedia.com",
    "groupon.com", "runtastic.com", "samsungcareplus",
    "instagram.com", "joinhoney.com", "withflex.com",
    "smithsonianstore.com", "moviesanywhere.com",
    "bananarepublic.com", "creditkarma.com", "experian.com",
    "ollama.com", "anthropic.com", "hm.com", "email.hm.com",
    "vanswarpedtour", "butcherbox.com", "zagg.com",
    "lovisa.com", "cgtrader.com", "bluerabbitrx.com",
    "a1storage.com", "dmea1.com", "demodaysfestival.com",
    "emails_BarclaysUS_com", "email_amctheatres_com",
    "renfairnews", "onyxhomes.com", "rise-a.intercom-mail.com",
    "docusign.com", "msftfort@microsoft.com", "google-noreply@google.com",
    "scholarships.com", "tangocard.com", "kik.com",
    "windowsinsiderprogram", "dropboxmail.com",
    "ancestry.com", "grabcad.com", "getpure.org", "welcome.pure.app",
    "filabotpfm", "sonyericsson.com", "safeopt_com",
    "mooselabsllc.com", "digital-downloads.com",
    "wgresorts.com", "incogni.com", "sendowl.com",
    "amctheatres", "hollywoodparkca", "enigmalabs",
    "sidewalkfoodtours", "medallia.com", "agenda_com",
    "vello.idexx.com", "jointheflyover.com", "outskill_com",
    "honey.com", "mar_medallia", "moneylion.com",
]

# ── Known important domains (never classify as junk) ────────────────────

KEEP_DOMAINS = [
    "amazon.com", "paypal.com", "chase.com", "fpcu.org",
    "savvymoney.com", "x.ai", "plaid.com", "facebookmail.com",
    "facebook.com", "apple.com", "applepay.apple.com",
    "applecard.apple.com", "synchrony.com", "synchronybank.com",
    "intuit.com", "fordcredit.com", "vanguard.com",
    "guideline.com", "carta.com", "marcus.com",
    "bamboohr.com",
    "gethired.com", "naviabenefits.com", "kellybenefits.com",
    "indeed.com", "indeedemail.com", "axelon.com",
    "github.com", "accounts.google.com", "docker.com",
    "discord.com", "steampowered.com", "playstation.com",
    "starlink.com", "twingate.com", "anthropic.com",
    "uber.com", "lyftmail.com", "microsoft.com",
    "t-mobile.com", "verizonwireless.com", "yahoo.com",
    "microcenter.com", "bestbuy.com", "citi.com",
    "ups.com", "enterprise.com", "erac.com",
    "egyptair.com", "selectegypt.com",
    "questdiagnostics.com", "optum.com",
    "pineanimalhospital.com", "ezyvet.com",
    "michaelsutter.com", "lastpass.com",
    "icloud.com", "trello.com",
    "dmv.ca.gov", "wildlifelicense.com",
] + _cfg.extra_keep_addresses()

# ── Junk subject patterns ───────────────────────────────────────────────

JUNK_SUBJECTS = [
    r"memory loss", r"knee pain", r"weight loss", r"male enhancement",
    r"erection", r"portable ac", r"glp-1", r"carshield",
    r"pre-ipo", r"pre ipo", r"no medical exam",
    r"clogged gutters", r"storage runs out",
    r"get hard", r"stay hard", r"brain rot",
    r"ice.?water hack", r"melts \d+lbs",
    r"home warranty", r"roofing", r"gutter sav",
    r"tax relief", r"irs relief", r"debt relief",
    r"home ins", r"veterans.*buying", r"term life",
    r"clinical trials", r"canvas print", r"wall art",
    r"final reminder.*payment", r"past due",
]

# ── Archive domain categories (for NAS save) ────────────────────────────

ARCHIVE_CATEGORIES = {
    "Receipts": [
        "paypal.com", "service.paypal.com", "microcenter.com",
        "apple.com", "email.apple.com", "applepay.apple.com",
        "paddle.com", "cindori.com", "hmshost.com",
        "uber.com", "lyftmail.com",
    ],
    "Statements": [
        "fpcu.org", "estatements@fpcu.org", "e.savvymoney.com",
        "chase.com", "no.reply.alerts@chase.com",
        "fordcredit.com", "accountmanager@fordcredit.com",
        "synchrony.com", "synchronybank.com", "synchronyfinancial.com",
        "servicing.synchrony.com", "citi.com", "info6.citi.com", "info15.citi.com",
        "BestBuyCard@citi.com", "vanguard.com", "vanguardretirement.com",
        "guideline.com", "marcus.com", "savings.marcus.com",
        "applecard.apple.com", "post.applecard.apple", "post.gs-savings.apple",
        "turbotax@intuit.com", "naviabenefits.com", "kellybenefits.com",
    ],
    "Shipping": [
        "amazon.com", "shipment-tracking@amazon.com", "auto-confirm@amazon.com",
        "order-update@amazon.com", "return@amazon.com",
        "noreply@amazon.com", "no-reply@amazon.com",
        "ups.com", "mcinfo@ups.com",
    ],
    "Security_Alerts": [
        "accounts.google.com", "facebookmail.com", "facebook.com",
        "github.com", "noreply@github.com", "notify.docker.com",
        "cc.yahoo.com", "cc.yahoo-inc.com",
        "discord.com", "x.ai", "anthropic.com",
        "microsoft.com", "microsoftonline.com",
        "starlink.com", "twingate.com",
    ],
    "Travel": [
        "email.aa.com", "egyptair.com", "selectegypt.com",
        "enterprise.com", "erac.com", "expedia.com",
        "norwegianreward.com", "hilton.com",
    ],
    "Work": [
        "bamboohr.com",
        "gethired.com", "indeed.com", "indeedemail.com", "axelon.com",
    ] + _cfg.extra_work_domains(),
    "Purchases": [
        "steampowered.com", "playstation.com", "txn-email.playstation.com",
        "sonyentertainmentnetwork.com", "email.playstation.com",
        "dbrand.com", "ebay.com",
    ],
    "Government": [
        "dmv.ca.gov", "wildlifelicense.com",
    ],
}

# Domains that should be archived when read (receipts, statements, alerts)
ARCHIVE_WHEN_READ_DOMAINS = [
    "paypal.com", "service.paypal.com", "servicing.synchrony.com",
    "synchronybank.com", "synchronyfinancial.com",
    "estatements@fpcu.org", "e.savvymoney.com",
    "no.reply.alerts@chase.com", "fraudalert.chase.com",
    "accountmanager@fordcredit.com",
    "shipment-tracking@amazon.com", "auto-confirm@amazon.com",
    "order-update@amazon.com", "return@amazon.com",
    "noreply@amazon.com", "no-reply@amazon.com",
    "mcinfo@ups.com",
    "no-reply@accounts.google.com",
    "security@facebookmail.com",
    "noreply@github.com", "notify.docker.com",
    "no-reply@cc.yahoo.com", "no-reply@cc.yahoo-inc.com",
    "email.apple.com", "applepay.apple.com", "applecard.apple.com",
    "post.applecard.apple", "post.gs-savings.apple",
    "noreply@steampowered.com",
    "email.playstation.com", "txn-email.playstation.com",
    "sonyentertainmentnetwork.com",
    "microcenter.com",
    "BestBuyCard@citi.com", "citi.com",
    "cardServices@citi.com", "info6.citi.com", "info15.citi.com",
    "noreply@starlink.com",
    "turbotax@intuit.com",
    "donotreply@vanguard.com", "vanguardretirement.com",
    "guideline.com",
    "no-reply@carta.com",
    "noreply@savings.marcus.com", "noreply@marcus.com",
    "email.aa.com",
    "egyptair.com", "selectegypt.com",
    "hmshost.com",
    "enterprise.com", "erac.com",
    "ca.wildlifelicense.com", "dmv.ca.gov",
    "digital-delivery.com",
    "verizonwireless.com",
    "app.bamboohr.com",
    "gethired.com",
    "michaelsutter.com",
    "edovia.com",
    "paddle.com", "cindori.com",
    "support@synchrony.com",
]

# Optional archive export path (e.g. a NAS mount). Empty when unconfigured —
# save_to_nas() then no-ops rather than writing anywhere.
def _nas_mail_archive() -> str:
    return _cfg.nas_archive_path()


@dataclass
class EmailMessage:
    """Normalized email message for agent consumption."""
    id: str
    subject: str
    sender: str
    date_received: str
    is_read: bool
    body_plain: str = ""
    body_html: str = ""
    thread_level: int = 0
    meta: Optional[str] = None
    account: str = ""
    mailbox: str = ""


@dataclass
class ThreadNode:
    """Parsed conversation thread node."""
    level: int
    body: str
    meta: Optional[str] = None
    children: List["ThreadNode"] = field(default_factory=list)


@dataclass
class ClassificationResult:
    """Result of classifying a single message."""
    message_id: str
    sender: str
    subject: str
    classification: str  # keep, junk, newsletter, archive
    method: str  # heuristic or llm


class MailAssistant:
    """
    AI Email Assistant backed by native Mail.app.

    This is the production implementation for ARES.
    It exposes the same logical tool surface the Odysseus MCP server provided,
    but routes all reads/writes through the existing authenticated Mail.app.
    """

    def _verify_mail_app(self) -> None:
        """Quick sanity check that Mail.app is available."""
        try:
            result = subprocess.run(
                ["osascript", "-e", 'tell application "Mail" to name'],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if "Mail" not in result.stdout:
                raise RuntimeError("Mail.app not responding")
        except Exception as e:
            raise RuntimeError(f"Mail.app verification failed: {e}") from e

    # ------------------------------------------------------------------
    # Core AppleScript helpers (battle-tested patterns)
    # ------------------------------------------------------------------

    def _run_applescript(self, script: str, timeout: int = APPLESCRIPT_TIMEOUT) -> str:
        """Execute AppleScript and return stdout. Uses return-based output."""
        with tempfile.NamedTemporaryFile(mode="w", suffix=".scpt", delete=False) as f:
            f.write(script)
            script_path = f.name

        try:
            result = subprocess.run(
                ["osascript", script_path],
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            if result.returncode != 0:
                raise RuntimeError(f"AppleScript error: {result.stderr}")
            return result.stdout.strip()
        finally:
            os.unlink(script_path)

    # ------------------------------------------------------------------
    # Tool surface (matches Odysseus MCP email_server intent)
    # ------------------------------------------------------------------

    def list_unread(self, limit: int = 50) -> List[EmailMessage]:
        """
        List unread messages from the unified inbox.

        Uses the fast sender-filter + batch pattern to avoid 30s+ timeouts
        on large inboxes (1300+ messages).
        """
        script = f'''
        tell application "Mail"
            set unreadMessages to (every message of inbox whose read status is false)
            set msgCount to count of unreadMessages
            set output to ""
            repeat with i from 1 to {min(limit, 200)}
                if i > msgCount then exit repeat
                set msg to item i of unreadMessages
                set msgID to id of msg as string
                set subj to subject of msg
                set sndr to sender of msg
                set dt to date received of msg as string
                set isRead to read status of msg
                set acctName to name of account of mailbox of msg
                set readFlag to "U"
                if isRead then set readFlag to "R"
                set output to output & msgID & "||" & subj & "||" & sndr & "||" & dt & "||" & readFlag & "||" & acctName & "\\n"
            end repeat
            return output
        end tell
        '''

        raw = self._run_applescript(script)
        messages: List[EmailMessage] = []

        for line in raw.splitlines():
            if not line.strip():
                continue
            parts = line.split("||")
            if len(parts) >= 6:
                messages.append(
                    EmailMessage(
                        id=parts[0],
                        subject=parts[1],
                        sender=parts[2],
                        date_received=parts[3],
                        is_read=(parts[4] == "R"),
                        account=parts[5],
                    )
                )

        return messages

    def scan_all(self, limit: int = 500) -> List[EmailMessage]:
        """
        Scan ALL inbox messages (read + unread).

        Inbox is a TO-DO list — read messages that don't need action
        get archived. Only truly pending items stay in inbox.
        """
        script = f'''
        tell application "Mail"
            set inboxMsgs to messages of inbox
            set msgCount to count of inboxMsgs
            set maxNum to {min(limit, 500)}
            if msgCount < maxNum then set maxNum to msgCount
            set output to ""
            repeat with i from 1 to maxNum
                set msg to item i of inboxMsgs
                set msgID to id of msg as string
                set subj to subject of msg
                set sndr to sender of msg
                set dt to date received of msg as string
                set isRead to read status of msg
                set readFlag to "R"
                if not isRead then set readFlag to "U"
                set acctName to name of account of mailbox of msg
                set output to output & msgID & "||" & subj & "||" & sndr & "||" & dt & "||" & readFlag & "||" & acctName & "\\n"
            end repeat
            return output
        end tell
        '''

        # UI inventory calls must be bounded. Mail.app can otherwise leave a
        # request hanging for three minutes while permissions or account sync
        # are unavailable; callers can refresh after Mail becomes responsive.
        raw = self._run_applescript(script, timeout=20)
        messages: List[EmailMessage] = []

        for line in raw.splitlines():
            if not line.strip():
                continue
            parts = line.split("||")
            if len(parts) >= 6:
                messages.append(
                    EmailMessage(
                        id=parts[0],
                        subject=parts[1],
                        sender=parts[2],
                        date_received=parts[3],
                        is_read=(parts[4] == "R"),
                        account=parts[5],
                    )
                )

        return messages

    def read_message(self, message_id: str) -> EmailMessage:
        """Fetch full content of a single message by ID."""
        script = f'''
        tell application "Mail"
            set msg to first message of inbox whose id is {message_id}
            set subj to subject of msg
            set sndr to sender of msg
            set dt to date received of msg as string
            set isRead to read status of msg
            set bodyPlain to content of msg
            set bodyHTML to ""
            try
                set bodyHTML to source of msg
            end try
            set acctName to name of account of mailbox of msg
            return subj & "|||" & sndr & "|||" & dt & "|||" & (isRead as string) & "|||" & acctName & "|||" & bodyPlain & "|||" & bodyHTML
        end tell
        '''

        raw = self._run_applescript(script, timeout=30)
        parts = raw.split("|||")

        if len(parts) < 7:
            raise RuntimeError(f"Failed to parse message {message_id}")

        return EmailMessage(
            id=message_id,
            subject=parts[0],
            sender=parts[1],
            date_received=parts[2],
            is_read=parts[3].lower() == "true",
            body_plain=parts[5],
            body_html=parts[6],
            account=parts[4],
        )

    def parse_thread(self, message: EmailMessage) -> List[ThreadNode]:
        """
        Parse the email into a threaded conversation tree.

        Uses the ported logic from Odysseus email_thread_parser.py.
        """
        # For now, return a single-node tree.
        # Full multilingual parser will be ported in the next iteration.
        return [
            ThreadNode(
                level=0,
                body=message.body_plain or message.body_html,
                meta=f"{message.sender} · {message.date_received}",
            )
        ]

    # ------------------------------------------------------------------
    # Classification (heuristic + LLM fallback)
    # ------------------------------------------------------------------

    @staticmethod
    def heuristic_classify(sender: str, subject: str) -> Optional[str]:
        """
        Fast domain/subject matching. Returns 'keep', 'junk',
        'newsletter', or None (uncertain — needs LLM).
        """
        combined = f"{sender.lower()} {subject.lower()}"

        # Check keep domains first — never touch these
        for d in KEEP_DOMAINS:
            if d in combined:
                return Classification.KEEP

        # Check junk domains
        for d in JUNK_DOMAINS:
            if d in combined:
                return Classification.JUNK

        # Check junk subjects
        for p in JUNK_SUBJECTS:
            if re.search(p, combined):
                return Classification.JUNK

        # Check newsletter domains
        for d in NEWSLETTER_DOMAINS:
            if d in combined:
                return Classification.NEWSLETTER

        return None

    @staticmethod
    def should_archive_when_read(sender: str) -> bool:
        """Check if a read message from this sender should be auto-archived."""
        sender_lower = sender.lower()
        for d in ARCHIVE_WHEN_READ_DOMAINS:
            if d in sender_lower:
                return True
        return False

    @staticmethod
    def get_archive_subfolder(sender: str) -> str:
        """Determine which NAS subfolder an archived email belongs to."""
        sender_lower = sender.lower()
        for category, domains in ARCHIVE_CATEGORIES.items():
            for d in domains:
                if d in sender_lower:
                    return category
        return "Misc"

    def classify_message(
        self, message: EmailMessage, use_llm: bool = True
    ) -> ClassificationResult:
        """
        Classify a single message using heuristic-first, LLM-fallback.

        For read messages, adds 'archive' as an option — read messages that
        are receipts/statements/alerts should be archived, not kept in inbox.
        """
        # Try heuristic first (fast, no API call)
        classification = self.heuristic_classify(message.sender, message.subject)

        if classification == Classification.KEEP:
            # KEEP_DOMAINS hit — but if it's read and matches archive domains, archive it
            if message.is_read and self.should_archive_when_read(message.sender):
                classification = Classification.ARCHIVE
            else:
                return ClassificationResult(
                    message_id=message.id,
                    sender=message.sender,
                    subject=message.subject,
                    classification=Classification.KEEP,
                    method="heuristic",
                )
        elif classification:
            # Heuristic hit (junk, newsletter, archive)
            # If read and from a keep domain that should be archived, override
            if message.is_read and classification == Classification.KEEP and self.should_archive_when_read(message.sender):
                classification = Classification.ARCHIVE
            return ClassificationResult(
                message_id=message.id,
                sender=message.sender,
                subject=message.subject,
                classification=classification,
                method="heuristic",
            )

        # Fall back to LLM for uncertain messages
        if use_llm:
            return self._llm_classify(message)

        return ClassificationResult(
            message_id=message.id,
            sender=message.sender,
            subject=message.subject,
            classification=Classification.KEEP,  # safe default
            method="default",
        )

    def _llm_classify(self, message: EmailMessage) -> ClassificationResult:
        """Use cloud LLM to classify uncertain messages."""
        if message.is_read:
            categories = """- archive: receipts, statements, shipping notifications, security alerts, order confirmations — already seen, keep for records but don't need action
- keep: something that still needs a response or action (unpaid bill, work email, family message, job application)
- junk: spam, scam, phishing, unsolicited ads
- newsletter: marketing promos, store newsletters, sale notifications"""
            default = Classification.ARCHIVE
        else:
            categories = """- keep: receipts, banking, work, family, account security, packages, government, medical — anything important
- junk: spam, scam, phishing, unsolicited ads, fake offers, dating spam
- newsletter: marketing promos, store newsletters, sale notifications, product updates"""
            default = Classification.KEEP

        # Use body if available, otherwise subject
        body = (message.body_plain or "")[:800]
        prompt_text = f"From: {message.sender}\nSubject: {message.subject}"
        if body:
            prompt_text += f"\nBody: {body}"

        owner = _cfg.assistant_name() or "the account owner"
        prompt = f"""You are {owner}'s email classifier. Classify this email as exactly one of:
{categories}

Be aggressive — if it's a promo or marketing email, it's newsletter. If it's spam or scam, it's junk. A read receipt or statement should be archive, not keep. Only keep in inbox if it needs action.

Email:
{prompt_text}

Respond with exactly one word: keep, junk, newsletter, or archive"""

        try:
            result = self._call_llm(
                system_prompt="You are a concise email classifier. Respond with exactly one word.",
                user_prompt=prompt,
                max_tokens=10,
            )
            result = result.strip().lower()
            if "junk" in result:
                classification = Classification.JUNK
            elif "newsletter" in result:
                classification = Classification.NEWSLETTER
            elif "archive" in result:
                classification = Classification.ARCHIVE
            elif "keep" in result:
                classification = Classification.KEEP
            else:
                classification = default
        except Exception:
            classification = default

        return ClassificationResult(
            message_id=message.id,
            sender=message.sender,
            subject=message.subject,
            classification=classification,
            method="llm",
        )

    def auto_clean(self, limit: int = 500, dry_run: bool = False) -> Dict[str, Any]:
        """
        Scan all inbox messages, classify, and take action.

        Actions:
        - junk → move to Junk
        - newsletter → move to Junk
        - archive → save to NAS (if available) + move to Archive
        - keep → leave in inbox

        Args:
            limit: Max messages to scan (default 500).
            dry_run: If True, classify but don't move anything.

        Returns:
            Dict with classification counts and actions taken.
        """
        messages = self.scan_all(limit=limit)

        results: Dict[str, List] = {
            "junk": [],
            "newsletter": [],
            "archive": [],
            "keep": [],
        }
        heuristic_hits = 0
        llm_calls = 0

        for msg in messages:
            classification = self.classify_message(msg, use_llm=True)

            if classification.method == "heuristic":
                heuristic_hits += 1
            elif classification.method == "llm":
                llm_calls += 1

            if classification.classification in results:
                results[classification.classification].append(classification)
            else:
                results["keep"].append(classification)

        # Take action
        moved_junk = 0
        moved_archive = 0
        nas_saved = 0

        if not dry_run:
            # Move junk + newsletters to junk
            for item in results["junk"] + results["newsletter"]:
                if self.move_to_junk(item.message_id):
                    moved_junk += 1

            # Archive read receipts/statements
            for item in results["archive"]:
                # Try NAS save first, if an archive path is configured
                if os.path.exists(_nas_mail_archive()):
                    subfolder = self.get_archive_subfolder(item.sender)
                    if self.save_to_nas(item.message_id, item.sender, item.subject, subfolder):
                        nas_saved += 1
                # Move to Mail.app Archive
                if self.move_to_archive(item.message_id, item.sender, item.subject):
                    moved_archive += 1

        return {
            "total_scanned": len(messages),
            "junk": len(results["junk"]),
            "newsletter": len(results["newsletter"]),
            "archive": len(results["archive"]),
            "keep": len(results["keep"]),
            "heuristic_hits": heuristic_hits,
            "llm_calls": llm_calls,
            "moved_junk": moved_junk,
            "moved_archive": moved_archive,
            "nas_saved": nas_saved,
            "dry_run": dry_run,
        }

    # ------------------------------------------------------------------
    # Mail actions
    # ------------------------------------------------------------------

    def mark_read(self, message_id: str) -> bool:
        """Mark a message as read."""
        script = f'''
        tell application "Mail"
            set msg to first message of inbox whose id is {message_id}
            set read status of msg to true
            return "OK"
        end tell
        '''
        result = self._run_applescript(script)
        return "OK" in result

    def move_to_junk(self, message_id: str) -> bool:
        """Move message to Junk (respects account-specific junk mailbox)."""
        script = f'''
        tell application "Mail"
            set msg to first message of inbox whose id is {message_id}
            set acctName to name of account of mailbox of msg
            if acctName is "Exchange" then
                set target to mailbox "Junk Email" of account "Exchange"
            else if acctName is "Yahoo!" then
                set target to mailbox "Bulk" of account "Yahoo!"
            else if acctName is "Google" then
                set target to mailbox "Spam" of account "Google"
            else
                set target to junk mailbox of account acctName
            end if
            move msg to target
            return "MOVED"
        end tell
        '''
        result = self._run_applescript(script)
        return "MOVED" in result

    def move_to_archive(self, message_id: str, sender: str = "", subject: str = "") -> bool:
        """Move message to Mail.app Archive mailbox (per-account routing)."""
        script = f'''
        tell application "Mail"
            try
                set msg to first message of inbox whose id is {message_id}
                set acctName to name of account of mailbox of msg
                -- Try account-specific archive first
                try
                    set target to mailbox "Archive" of account acctName
                    move msg to target
                    return "OK"
                on error
                    -- Fall back to iCloud Archive
                    move msg to mailbox "Archive" of account "iCloud"
                    return "OK"
                end try
            on error
                try
                    set msg to first message of inbox whose id is {message_id}
                    move msg to junk mailbox
                    return "OK"
                on error
                    return "FAIL"
                end try
            end try
        end tell
        '''
        try:
            result = self._run_applescript(script, timeout=15)
            return "OK" in result
        except Exception:
            return False

    def save_to_nas(self, message_id: str, sender: str, subject: str, subfolder: str) -> bool:
        """Save email content to the configured archive path, if any."""
        nas_root = _nas_mail_archive()
        if not nas_root or not os.path.exists(nas_root):
            return False

        # Ensure subfolder exists
        folder_path = os.path.join(nas_root, subfolder)
        os.makedirs(folder_path, exist_ok=True)

        # Fetch message content
        try:
            msg = self.read_message(message_id)
        except Exception:
            return False

        # Sanitize filename
        safe_subj = re.sub(r'[^\w\s.-]', '', subject)[:60].strip()
        safe_sender = re.sub(r'[^\w\s@.-]', '', sender)[:50].strip()
        date_str = datetime.now().strftime('%Y-%m-%d')
        filename = f"{date_str}_{safe_sender}_{safe_subj}.eml"
        filepath = os.path.join(folder_path, filename)

        try:
            with open(filepath, 'w') as f:
                f.write(f"From: {sender}\nSubject: {subject}\nArchived: {datetime.now().isoformat()}\n\n")
                f.write(msg.body_plain or msg.body_html or "(no content)")
            return True
        except Exception:
            return False

    # ------------------------------------------------------------------
    # LLM integration
    # ------------------------------------------------------------------

    # Ollama Cloud (OpenAI-compatible) endpoint configuration.
    # Uses the same provider routing as Ares Agent: glm-5.1 via ollama-cloud.
    # API key is read from OLLAMA_API_KEY env var, falling back to ~/.ares/.env
    _LLM_BASE_URL = os.environ.get("OLLAMA_CLOUD_URL", "https://ollama.com/v1")
    _LLM_API_KEY: str = ""  # resolved in __init__
    _LLM_MODEL = os.environ.get("ARES_MAIL_MODEL", "glm-5.1")

    @staticmethod
    def _resolve_api_key() -> str:
        """Resolve API key from env var, falling back to ~/.ares/.env."""
        key = os.environ.get("OLLAMA_API_KEY", "")
        if key:
            return key
        env_file = Path.home() / ".ares" / ".env"
        if env_file.exists():
            for line in env_file.read_text().splitlines():
                line = line.strip()
                if line.startswith("OLLAMA_API_KEY=") and not line.startswith("#"):
                    return line.split("=", 1)[1].strip()
        return ""

    def __init__(self):
        self._verify_mail_app()
        self._LLM_API_KEY = self._resolve_api_key()

    def _call_llm(self, system_prompt: str, user_prompt: str, max_tokens: int = 512) -> str:
        """Call the configured LLM via OpenAI-compatible API.

        Routes through Ollama Cloud (glm-5.1) by default — same provider
        chain used by Ares Agent for delegation tasks.
        """
        payload = {
            "model": self._LLM_MODEL,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "max_tokens": max_tokens,
            "temperature": 0.4,
        }

        headers = {
            "Content-Type": "application/json",
        }
        if self._LLM_API_KEY:
            headers["Authorization"] = f"Bearer {self._LLM_API_KEY}"

        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{self._LLM_BASE_URL}/chat/completions",
            data=data,
            headers=headers,
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode("utf-8"))
            return result["choices"][0]["message"]["content"].strip()
        except (urllib.error.URLError, KeyError, json.JSONDecodeError) as e:
            raise RuntimeError(f"LLM call failed: {e}") from e

    def draft_reply(self, message_id: str, prompt: str = "") -> str:
        """
        Generate a draft reply using the LLM.

        Reads the message, constructs a system prompt for a concise,
        action-oriented reply style, and calls the configured cloud model.

        Args:
            message_id: AppleScript message ID to reply to.
            prompt: Optional additional instructions (e.g. "be formal",
                    "ask about pricing", "decline politely").

        Returns:
            Draft reply text ready for review.
        """
        msg = self.read_message(message_id)

        owner = _cfg.assistant_name()
        for_clause = f" for {owner}" if owner else ""
        system_prompt = (
            f"You are an email assistant{for_clause}. "
            "Draft concise, professional replies: direct, no filler, action-oriented. "
            "Keep replies under 150 words unless the email needs detail. "
            "Never add fake specifics or hallucinate details. "
            "If unsure about something, say so rather than guessing."
        )

        thread = self.parse_thread(msg)
        thread_text = "\n\n".join(
            f"[{node.meta}] {node.body[:2000]}" for node in thread
        )

        user_prompt = f"""Email from: {msg.sender}
Subject: {msg.subject}
Date: {msg.date_received}

Content:
{thread_text[:4000]}

{"Additional instructions: " + prompt if prompt else "Write an appropriate reply."}

Reply:"""

        return self._call_llm(system_prompt, user_prompt)


# ------------------------------------------------------------------
# Convenience entry point for Ares / agent use
# ------------------------------------------------------------------

def get_mail_assistant() -> MailAssistant:
    """Factory for the production Mail AI Assistant."""
    return MailAssistant()


if __name__ == "__main__":
    import sys
    assistant = get_mail_assistant()

    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        if cmd == "unread":
            limit = int(sys.argv[2]) if len(sys.argv) > 2 else 20
            messages = assistant.list_unread(limit=limit)
            print(f"Found {len(messages)} unread messages")
            for m in messages[:10]:
                print(f"  - {m.sender} | {m.subject}")
        elif cmd == "clean":
            dry_run = "--dry-run" in sys.argv
            result = assistant.auto_clean(dry_run=dry_run)
            print(f"=== Mail Cleaner ===")
            print(f"Scanned: {result['total_scanned']}")
            print(f"  Junk: {result['junk']} (heuristic: {result['heuristic_hits']}, LLM: {result['llm_calls']})")
            print(f"  Newsletter: {result['newsletter']}")
            print(f"  Archive: {result['archive']}")
            print(f"  Keep: {result['keep']}")
            if not dry_run:
                print(f"  Moved to Junk: {result['moved_junk']}")
                print(f"  Archived: {result['moved_archive']}")
                print(f"  NAS saved: {result['nas_saved']}")
            else:
                print("  (dry run — no actions taken)")
        elif cmd == "classify":
            # Classify a single message by ID
            msg_id = sys.argv[2] if len(sys.argv) > 2 else None
            if msg_id:
                msg = assistant.read_message(msg_id)
                result = assistant.classify_message(msg)
                print(f"  {result.classification} ({result.method}) | {result.sender} | {result.subject}")
        else:
            print(f"Unknown command: {cmd}")
            print("Usage: mail_assistant.py [unread|clean|classify] [args]")
    else:
        # Quick smoke test
        unread = assistant.list_unread(limit=5)
        print(f"Found {len(unread)} unread messages")
        for m in unread[:3]:
            print(f"  - {m.sender} | {m.subject}")
