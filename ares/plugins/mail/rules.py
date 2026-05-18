"""ARES Mail Triage — Classification rules engine.

Deterministic regex + allowlist classifier. No LLM. No API. No tokens.
Same logic as legacy mail_clean.py, refactored into typed Pydantic rules.
"""

from __future__ import annotations

import re
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from .models import EmailMessage, ClassificationLabel

# ---------------------------------------------------------------------------
# SENDER patterns → JUNK
# ---------------------------------------------------------------------------
JUNK_SENDER_PATTERNS = [
    # Generic automated sender signals
    r"no.?reply",
    r"do.?not.?reply",
    r"donotreply",
    r"noreply",
    r"auto.?mailer",
    r"mailer.?daemon",
    r"postmaster",
    r"bounce",
    r"unsubscribe",
    r"optout",
    # Bulk-mail subdomain patterns
    r"@email\.",
    r"@em\.",
    r"@mail\.",
    r"@e\.",
    r"@updates\.",
    r"@news\.",
    r"@notify\.",
    r"@notifications\.",
    r"@promo\.",
    r"@promos\.",
    r"@marketing\.",
    r"@offers\.",
    r"@deals\.",
    r"@info\.",
    r"@hello\.",
    r"@reply\.",
    r"@messages\.",
    r"@send\.",
    r"@mg\.",        # Mailgun
    r"@sg\.",        # SendGrid
    r"@sparkpost\.",
    r"shared1\.",
    r"ccsend\.",
    r"rsgsv\.net",
    r"exacttarget\.com",
    r"salesforce\.com",
    r"marketo\.net",
    r"hubspot\.com",
    r"mailchimp\.com",
    r"klaviyo\.com",
    r"constantcontact\.com",
    r"sendgrid\.net",
    r"amazonses\.com",
    # Common marketing sender name patterns
    r"^deals@",
    r"^offers@",
    r"^promo@",
    r"^promos@",
    r"^news@",
    r"^newsletter@",
    r"^newsletters@",
    r"^alerts@",
    r"^notifications@",
    r"^notify@",
    r"^digest@",
    r"^weekly@",
    r"^daily@",
    r"^updates@",
]

# ---------------------------------------------------------------------------
# SUBJECT patterns → JUNK
# ---------------------------------------------------------------------------
JUNK_SUBJECT_PATTERNS = [
    r"\d+\s*%\s*off",
    r"\$\d+\s*off",
    r"free shipping",
    r"flash sale",
    r"sale ends",
    r"sale starts",
    r"up to \d+",
    r"save \d+",
    r"save up to",
    r"limited.?time",
    r"limited offer",
    r"exclusive offer",
    r"exclusive deal",
    r"special offer",
    r"act now",
    r"don\'t miss",
    r"don't miss out",
    r"last chance",
    r"ends (today|tonight|soon|sunday|monday|tuesday|wednesday|thursday|friday|saturday)",
    r"today only",
    r"this week only",
    r"hurry",
    r"deal of the day",
    r"daily deal",
    r"new arrivals",
    r"shop now",
    r"buy now",
    r"order now",
    # Subscription signals
    r"you\'re (now )?subscribed",
    r"you\'ve been subscribed",
    r"unsubscribe",
    r"manage (your )?preferences",
    r"email preferences",
    r"newsletter",
    r"weekly (digest|update|roundup)",
    r"monthly (digest|update|roundup|newsletter)",
    # Win / reward
    r"you\'ve (been selected|won|earned)",
    r"you were selected",
    r"claim your",
    r"reward(s)? (waiting|inside|available)",
    r"loyalty (points|reward)",
    r"refer a friend",
    r"referral (bonus|reward)",
    # Marketing openers
    r"^(re: )?(hi|hey|hello) (there|friend|\w+),?\s*$",
    r"we miss you",
    r"come back",
    r"it\'s been a while",
    r"we noticed you",
    r"check out what\'s new",
    r"see what\'s new",
    r"your (weekly|monthly|daily) (summary|digest|update|report)",
    # Phishing / scam
    r"all your devices.*out of protection",
    r"your (passwords|photos|banking).{0,20}(danger|serious|risk)",
    r"unlock (your |access )",
]

# ---------------------------------------------------------------------------
# PRIORITY — never junk these senders
# ---------------------------------------------------------------------------
PRIORITY_ALLOWLIST = [
    r"dnljenkins5@yahoo\.com",
    r"@yahoo\.com$",
    # Anthropic (iCloud relay)
    r"_at_mail_anthropic_com",
    r"@anthropic\.com",
    # Ollama
    r"_at_ollama_com",
    # GitHub
    r"notifications@github\.com",
    # Apple
    r"@post\.applecard\.apple",
    r"@post\.gs-savings\.apple",
    r"@email\.apple\.com",
    r"@[^@]*apple\.com",
    # Chase
    r"no\.reply\.alerts@chase\.com",
    r"@chase\.com",
    # PayPal
    r"noreply@service\.paypal\.com",
    r"@paypal\.com",
    # FPCU
    r"@estmt\.fpcu\.org",
    # Intuit
    r"turbotax@em[0-9]*\.turbotax\.intuit\.com",
    r"@intuit\.com",
    r"@[^@]*intuit\.com",
    # Google
    r"no-reply@accounts\.google\.com",
    # Healthcare
    r"@avidiahealthcaresolutions\.com",
    # Storage
    r"a1paramount@a1storage\.com",
    # Travel
    r"info@selectegyth\.com",
    # Dental
    r"smile@downeypromenadedentalgroup\.com",
    # Citi
    r"@info[0-9]*\.citi\.com",
    r"@citi\.com",
]

# ---------------------------------------------------------------------------
# KEEP — transactional, not priority
# ---------------------------------------------------------------------------
KEEP_ALLOWLIST = [
    r"shipment-tracking@amazon\.com",
    r"order-update@amazon\.com",
    r"auto-confirm@amazon\.com",
    r"@amazon\.com$",
    r"@amazon\.",
    r"@fedex\.com",
    r"@usps\.com",
    r"@ups\.com",
    r"noreply@uber\.com",
    r"@synchronybank\.com",
    r"@barclays\.",
    r"@e\.fordcredit\.com",
    r"@e\.progressive\.com",
    r"@vanguardretirement\.com",
    r"@vanguard\.com",
    r"@account\.onepay\.com",
    r"@servicing\.one\.app",
    r"@h5\.hilton\.com",
    r"@email-marriott\.com",
    r"_at_email_amctheatres_com",
    r"@s\.usa\.experian\.com",
    r"@experian\.com",
    r"@mail\.nordpass\.com",
    r"niels@ejectify\.app",
    r"info@onewheel\.com",
    r"rewards@e-rewards\.dominos\.com",
    r"_at_emails_barclaysus_com",
    r"_at_services_barclaysus_com",
    r"@barclaysus\.com",
    r"@barclays\.com$",
    r"_at_loyalty_ms_aa_com",
    r"@aa\.com",
    r"@e-email\.guns\.com",
    r"@e-info\.guns\.com",
]

# ---------------------------------------------------------------------------
# KEEP_SUBJECT Patterns — protect transactional from no-reply senders
# ---------------------------------------------------------------------------
KEEP_SUBJECT_PATTERNS = [
    r"your.{0,25}statement",
    r"statement (is |is now )?ready",
    r"statement (is )?(now )?available",
    r"account (activity|alert|summary|update|notice)",
    r"transaction (alert|notification|receipt)",
    r"payment (received|confirmed|processed|due|reminder|has been received|scheduled)",
    r"automatic payment",
    r"invoice #?\d",
    r"receipt for",
    r"your (recent )?purchase",
    r"your receipt (from|for)",
    r"receipt from",
    r"order (confirmed|confirmation|shipped|delivered|#|number)",
    r"order no\.?\s*\d",
    r"your order (has|is|\w{1,10} been)",
    r"shipment (update|notification|tracking)",
    r"tracking (number|update)",
    r"delivery (update|confirmation|scheduled)",
    r"you\'ve connected your (bank|account)",
    r"credit card (statement|payment)",
    r"declined.{0,20}(apple card|transaction)",
    r"(apple card|your).{0,15}(payment|statement|savings)",
    r"sign.?in (attempt|from|to|alert)",
    r"new (sign.?in|login|device)",
    r"password (reset|changed|updated)",
    r"verify your",
    r"verification code",
    r"security (alert|notice|code|update)",
    r"two.?factor",
    r"2fa",
    r"appointment (confirmed|reminder|cancelled|canceled|rescheduled)",
    r"(cancelled|canceled|confirmed|rescheduled).{0,20}appointment",
    r"you have.{0,15}(cancelled|canceled|confirmed|upcoming).{0,15}appointment",
    r"reservation (confirmed|reminder|cancelled)",
    r"booking (confirmed|reminder|cancelled)",
    r"tax (document|form|return|statement)",
    r"w.?2|1099|1040|5498",
    r"tax forms? (are |is )?(available|ready)",
    r"(federal|state) return (accepted|rejected)",
    r"irs tax form",
    r"(hsa).{0,20}(statement|form|document)",
    r"(scheduled )?payment (reminder|due|alert)",
    r"invoice.{0,10}(unit|storage|rental)",
    r"run failed",
    r"pr run failed",
]

# ---------------------------------------------------------------------------
# Spoof / suspicious detection
# ---------------------------------------------------------------------------
_SPOOF_BRAND_RE = re.compile(
    r"apple\s+support|apple\s+card|paypal\s+support|amazon\s+support|"
    r"google\s+support|microsoft\s+support|netflix\s+support|"
    r"chase\s+bank|bank\s+of\s+america|wells\s+fargo|capital\s+one",
    re.IGNORECASE,
)

_SUSPICIOUS_DOMAINS = re.compile(
    r"(hostnewdaels|dataart|community\.host|cdn\.host|"
    r"appreconnect|szgwbn|luoyue|sina\.com|oga\.gr|"
    r"moe-dl\.edu|busarc|tunnelbec|sawayn|hankukevent|"
    r"organishing|borrimme|linnthomas|senheguang|idesignspot|"
    r"ccsend|shared1|rsgsv|exacttarget|"
    r"girlreview|homfriends|staygenerator|"
    r"goldandcryptoinsights|nexirocompass|lurniinsight|"
    r"mayantial|typicaribbean|wfuv|"
    r"lovelyfun|unlock.*access|hostnewdaels)",
    re.IGNORECASE,
)

_BULK_SENDER_RE = re.compile(
    r"no.?reply|newsletter|promo|marketing|@email\.|@em\.|@mail\.|"
    r"@updates\.|@news\.|@notify\.|mailchimp|klaviyo|sendgrid|amazonses|"
    r"hubspot|marketo|constantcontact",
    re.IGNORECASE,
)

_RESCUE_SUBJECT_RE = re.compile(
    r"statement|invoice|receipt|your order|shipment|tracking|"
    r"security alert|sign.?in|password|verify|verification|"
    r"job alert|application|interview|offer letter|"
    r"appointment|reminder|reservation|booking|"
    r"bank|account activity|transaction|"
    r"declined|payment (received|has been received|scheduled)|"
    r"credit card statement",
    re.IGNORECASE,
)

_RESCUE_SENDER_RE = re.compile(
    r"^[a-zA-Z][\w.\-]+@[a-zA-Z][\w.\-]+\.[a-zA-Z]{2,}$"
)

# Max messages to scan from junk folders
JUNK_SCAN_LIMIT = 100


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def extract_real_domain(sender_lower: str) -> str:
    """Extract real domain, handling iCloud relay addresses."""
    relay_match = re.match(
        r".*?_at_([^_]+)_([a-z]+)(?:_[a-z0-9]+)*@icloud\.com",
        sender_lower,
    )
    if relay_match:
        return f"{relay_match.group(1)}.{relay_match.group(2)}"
    if "privaterelay.appleid.com" in sender_lower:
        return "privaterelay.appleid.com"
    if "@" in sender_lower:
        return sender_lower.split("@")[-1]
    return sender_lower


def _match(text: str, patterns: list[str]) -> bool:
    t = text.lower()
    return any(re.search(p, t, re.IGNORECASE) for p in patterns)


def is_spoof(sender: str) -> bool:
    """Return True if sender display name spoofs a brand but domain is suspicious."""
    sender_name = sender.split("<")[0].strip() if "<" in sender else ""
    sender_lower = sender.lower()
    return bool(
        _SPOOF_BRAND_RE.search(sender_name) and _SUSPICIOUS_DOMAINS.search(sender_lower)
    )


# ---------------------------------------------------------------------------
# Main classifier
# ---------------------------------------------------------------------------

def classify(
    msg: EmailMessage,
    learned_keep: set[str] | None = None,
    learned_junk: set[str] | None = None,
    learned_domains: set[str] | None = None,
) -> tuple[ClassificationLabel, str | None]:
    """
    Return (label, matched_rule_name) for an inbox message.

    Evaluation order (matches allowlists first, then learned, then rules):
      1. PRIORITY_ALLOWLIST
      2. KEEP_ALLOWLIST
      3. Learned KEEP addresses
      4. List-Unsubscribe (unless KEEP_SUBJECT_PATTERNS protect it)
      5. Learned JUNK addresses
      6. Learned JUNK domains
      7. KEEP_SUBJECT_PATTERNS
      8. Spoof detection
      9. JUNK_SENDER_PATTERNS
     10. JUNK_SUBJECT_PATTERNS
     11. Default: PRIORITY
    """
    learned_keep = learned_keep or set()
    learned_junk = learned_junk or set()
    learned_domains = learned_domains or set()

    sender = msg.sender
    subject = msg.subject
    has_unsubscribe = msg.has_unsubscribe
    sender_lower = msg.sender_lower
    domain = msg.domain

    # 1. Priority allowlist
    if _match(sender, PRIORITY_ALLOWLIST):
        return "PRIORITY", "priority_allowlist"

    # 2. Keep allowlist
    if _match(msg.sender, KEEP_ALLOWLIST):
        return "KEEP", "keep_allowlist"

    # 3. Learned keep
    if sender_lower in learned_keep:
        return "KEEP", "learned_keep"

    # 4. List-Unsubscribe (strong junk signal unless protected)
    if has_unsubscribe and not _match(subject, KEEP_SUBJECT_PATTERNS):
        return "JUNK", "list_unsubscribe"

    # 5. Learned junk addresses
    if sender_lower in learned_junk:
        return "JUNK", "learned_junk_address"

    # 6. Learned junk domains
    if domain in learned_domains:
        return "JUNK", "learned_junk_domain"

    # 7. Keep subject patterns
    if _match(subject, KEEP_SUBJECT_PATTERNS):
        if _match(subject, JUNK_SUBJECT_PATTERNS):
            return "JUNK", "keep_subject_override_by_junk_pattern"
        return "KEEP", "keep_subject"

    # 8. Spoof detection
    if is_spoof(sender):
        return "JUNK", "spoof_detection"

    # 9. Junk sender patterns
    if _match(sender, JUNK_SENDER_PATTERNS):
        return "JUNK", "junk_sender_pattern"

    # 10. Junk subject patterns
    if _match(subject, JUNK_SUBJECT_PATTERNS):
        return "JUNK", "junk_subject_pattern"

    # 11. Default
    return "PRIORITY", "default_priority"


def should_rescue(msg: EmailMessage) -> bool:
    """True if a junk-folder message looks like it shouldn't be there."""
    sender = msg.sender
    subject = msg.subject
    sender_lower = sender.lower()

    # Never rescue spoofed brand email
    sender_name = sender.split("<")[0].strip() if "<" in sender else ""
    if _SPOOF_BRAND_RE.search(sender_name) and _SUSPICIOUS_DOMAINS.search(sender_lower):
        return False

    if _BULK_SENDER_RE.search(sender):
        return False

    if _SUSPICIOUS_DOMAINS.search(sender_lower):
        return False

    if _RESCUE_SUBJECT_RE.search(subject):
        return True

    if _RESCUE_SENDER_RE.match(sender.strip()):
        return True

    return False
