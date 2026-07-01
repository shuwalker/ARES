#!/usr/bin/env python3
"""
Ares Smart Mail Classifier v6
Scans inbox via Mail.app AppleScript, classifies unread messages using
heuristic + cloud LLM, moves junk/newsletters to junk mailbox.

Single script — no separate scan step needed.
Uses Mail.app's existing login (no passwords required).
Classifies as: keep (important), junk (spam/scam), newsletter (promo/marketing).
Junk and newsletters are moved to junk mailbox (permanent deletion on empty).
"""

import subprocess
import re
import json
import os
import sys
from datetime import datetime

# ── Config ──────────────────────────────────────────
LLM_MODEL = "glm-5.2"
LLM_URL = "http://localhost:11434/api/generate"
MAX_UNREAD_TO_PROCESS = 500  # Process all unread in one pass
MAX_BODY_LENGTH = 1500

# ── Known junk domains (heuristic — fast path, no LLM needed) ──
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
]

# ── Known newsletter/promo domains (heuristic — archive, not trash) ──
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

# ── Known important domains (never classify as junk) ──
KEEP_DOMAINS = [
    "amazon.com", "paypal.com", "chase.com", "fpcu.org",
    "savvymoney.com", "x.ai", "plaid.com", "facebookmail.com",
    "facebook.com", "apple.com", "applepay.apple.com",
    "applecard.apple.com", "synchrony.com", "synchronybank.com",
    "intuit.com", "fordcredit.com", "vanguard.com",
    "guideline.com", "carta.com", "marcus.com",
    "quantumspace.us", "phasefour.io", "bamboohr.com",
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
    "dnljenkins5@yahoo.com", "tc935@aol.com",
    "dmv.ca.gov", "wildlifelicense.com",
]

# ── Junk subject patterns ──
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


def scan_inbox():
    """Scan ALL inbox messages via AppleScript. Returns list of dicts.
    Processes every message — read or unread — because the inbox is a
    TO-DO list, not a storage folder. Read messages that don't need action
    get archived. Only truly pending items stay in inbox."""
    script = '''tell application "Mail"
    set inboxMsgs to messages of inbox
    set msgCount to count of inboxMsgs
    set maxNum to ''' + str(MAX_UNREAD_TO_PROCESS) + '''
    if msgCount < maxNum then set maxNum to msgCount
    repeat with idx from 1 to maxNum
        set msg to item idx of inboxMsgs
        set msgId to id of msg
        set isRead to read status of msg
        set senderName to sender of msg
        set subj to subject of msg
        set msgDate to date received of msg
        if isRead then
            set readFlag to "R"
        else
            set readFlag to "U"
        end if
        log msgId & "|||" & readFlag & "|||" & senderName & "|||" & subj
    end repeat
end tell'''
    with open('/tmp/ares_scan.applescript', 'w') as f:
        f.write(script)
    try:
        result = subprocess.run(
            ['osascript', '/tmp/ares_scan.applescript'],
            capture_output=True, text=True, timeout=180
        )
        # AppleScript log output goes to stderr, not stdout
        output = result.stderr if result.stderr else result.stdout
        messages = []
        for line in output.strip().split('\n'):
            line = line.strip()
            if '|||' not in line:
                continue
            parts = line.split('|||', 3)
            if len(parts) < 4:
                continue
            messages.append({
                'id': parts[0].strip().rstrip(','),
                'unread': parts[1].strip().rstrip(',') == 'U',
                'sender': parts[2].strip().rstrip(','),
                'subject': parts[3].strip().rstrip(','),
            })
        return messages
    except subprocess.TimeoutExpired:
        print("Scan timed out")
        return []
    except Exception as e:
        print(f"Scan error: {e}")
        return []


def get_message_body(message_id):
    """Fetch body of a single message via AppleScript."""
    script = f'''tell application "Mail"
    try
        set msg to (first message of inbox whose id is {message_id})
        return content of msg
    on error
        return ""
    end try
end tell'''
    try:
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, timeout=15
        )
        return result.stdout.strip()[:MAX_BODY_LENGTH] if result.returncode == 0 else ""
    except:
        return ""


def heuristic_classify(sender, subject):
    """Fast domain/subject matching. Returns 'junk', 'newsletter', or None."""
    combined = f"{sender.lower()} {subject.lower()}"

    # Check keep domains first — never touch these
    for d in KEEP_DOMAINS:
        if d in combined:
            return 'keep'

    # Check junk domains
    for d in JUNK_DOMAINS:
        if d in combined:
            return 'junk'

    # Check junk subjects
    for p in JUNK_SUBJECTS:
        if re.search(p, combined):
            return 'junk'

    # Check newsletter domains
    for d in NEWSLETTER_DOMAINS:
        if d in combined:
            return 'newsletter'

    return None


def llm_classify(sender, subject, body, is_read=False):
    """Use cloud LLM to classify uncertain messages.
    For read messages, adds 'archive' as an option — read messages that
    are receipts/statements/alerts should be archived, not kept in inbox."""
    if is_read:
        categories = """- archive: receipts, statements, shipping notifications, security alerts, order confirmations — already seen, keep for records but don't need action
- keep: something that still needs a response or action (unpaid bill, work email, family message, job application)
- junk: spam, scam, phishing, unsolicited ads
- newsletter: marketing promos, store newsletters, sale notifications"""
        default = "archive"
    else:
        categories = """- keep: receipts, banking, work, family, account security, packages, government, medical — anything important
- junk: spam, scam, phishing, unsolicited ads, fake offers, dating spam
- newsletter: marketing promos, store newsletters, sale notifications, product updates"""
        default = "keep"

    prompt = f"""You are Matthew's email classifier. Classify this email as exactly one of:
{categories}

Be aggressive — if it's a promo or marketing email, it's newsletter. If it's spam or scam, it's junk. A read receipt or statement should be archive, not keep. Only keep in inbox if it needs action.

Email:
From: {sender}
Subject: {subject}
Body: {body[:800]}

Respond with exactly one word: keep, junk, newsletter, or archive"""

    payload = json.dumps({
        "model": LLM_MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0.1, "num_predict": 10},
    })
    try:
        r = subprocess.run(
            ['curl', '-s', '-X', 'POST', LLM_URL,
             '-H', 'Content-Type: application/json',
             '-d', payload],
            capture_output=True, text=True, timeout=30
        )
        if r.returncode == 0:
            resp = json.loads(r.stdout).get('response', '').strip().lower()
            if 'junk' in resp: return 'junk'
            if 'newsletter' in resp: return 'newsletter'
            if 'archive' in resp: return 'archive'
            if 'keep' in resp: return 'keep'
    except:
        pass
    return default


# ── NAS Mail Archive ──
NAS_MAIL_ARCHIVE = "/Volumes/Personal-Drive/04_Archives/Mail"

# Map sender domains to archive subfolders
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
        "quantumspace.us", "phasefour.io", "bamboohr.com",
        "gethired.com", "indeed.com", "indeedemail.com", "axelon.com",
    ],
    "Purchases": [
        "steampowered.com", "playstation.com", "txn-email.playstation.com",
        "sonyentertainmentnetwork.com", "email.playstation.com",
        "dbrand.com", "ebay.com",
    ],
    "Government": [
        "dmv.ca.gov", "wildlifelicense.com",
    ],
}


def get_archive_subfolder(sender):
    """Determine which NAS subfolder an archived email belongs to."""
    sender_lower = sender.lower()
    for category, domains in ARCHIVE_CATEGORIES.items():
        for d in domains:
            if d in sender_lower:
                return category
    return "Misc"
ARCHIVE_DOMAINS = [
    "paypal.com", "service.paypal.com", "servicing.synchrony.com",
    "synchronybank.com", "synchronyfinancial.com",
    "estatements@fpcu.org", "e.savvymoney.com",
    "no.reply.alerts@chase.com", "fraudalert.chase.com",
    "accountmanager@fordcredit.com",
    "shipment-tracking@amazon.com", "auto-confirm@amazon.com",
    "order-update@amazon.com", "return@amazon.com",
    "noreply@amazon.com", "no-reply@amazon.com",
    "mcinfo@ups.com",
    "no-reply@accounts.google.com",  # security alerts already dealt with
    "security@facebookmail.com",  # login alerts already seen
    "noreply@github.com",  # token notifications already handled
    "notify.docker.com",
    "no-reply@cc.yahoo.com", "no-reply@cc.yahoo-inc.com",
    "email.apple.com",  # receipts
    "applepay.apple.com", "applecard.apple.com",
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
    "email.aa.com",  # American Airlines confirmations
    "egyptair.com", "selectegypt.com",
    "hmshost.com",  # airport receipts
    "enterprise.com", "erac.com",
    "ca.wildlifelicense.com", "dmv.ca.gov",
    "digital-delivery.com",  # T-Mobile receipts
    "verizonwireless.com",
    "app.bamboohr.com",  # work onboarding (already done)
    "gethired.com",
    "michaelsutter.com",  # diploma
    "edovia.com",  # Screens Connect
    "paddle.com",  # software receipts
    "cindori.com",
    "support@synchrony.com",
]


def save_to_nas(message_id, sender, subject, subfolder):
    """Save email content to NAS archive before removing from inbox."""
    if not os.path.exists(NAS_MAIL_ARCHIVE):
        return False

    # Sanitize filename
    safe_subj = re.sub(r'[^\w\s.-]', '', subject)[:60].strip()
    safe_sender = re.sub(r'[^\w\s@.-]', '', sender)[:50].strip()
    date_str = datetime.now().strftime('%Y-%m-%d')
    filename = f"{date_str}_{safe_sender}_{safe_subj}.eml"
    filepath = os.path.join(NAS_MAIL_ARCHIVE, subfolder, filename)

    # Export the message via AppleScript
    script = f'''tell application "Mail"
    try
        set msg to (first message of inbox whose id is {message_id})
        set msgContent to content of msg
        set msgSender to sender of msg
        set msgSubject to subject of msg
        set msgDate to date received of msg
        return msgSender & "\\n" & msgSubject & "\\n" & msgDate & "\\n\\n" & msgContent
    on error
        return "ERROR"
    end try
end tell'''
    try:
        r = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, timeout=15
        )
        if r.returncode == 0 and r.stdout and 'ERROR' not in r.stdout:
            with open(filepath, 'w') as f:
                f.write(f"From: {sender}\nSubject: {subject}\nArchived: {datetime.now().isoformat()}\n\n{r.stdout}")
            return True
    except:
        pass
    return False


def move_to_archive(message_id, sender="", subject=""):
    """Save email to NAS archive, then move to Mail.app Archive mailbox."""
    subfolder = get_archive_subfolder(sender) if sender else "Misc"

    # Try to save to NAS first
    nas_saved = False
    if sender:
        nas_saved = save_to_nas(message_id, sender, subject, subfolder)

    # Move to Mail.app Archive
    script = f'''tell application "Mail"
    try
        set msg to (first message of inbox whose id is {message_id})
        move msg to mailbox "Archive" of account "iCloud"
        return "OK"
    on error
        try
            set msg to (first message of inbox whose id is {message_id})
            move msg to junk mailbox
            return "OK"
        on error
            return "FAIL"
        end try
    end try
end tell'''
    try:
        r = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, timeout=15
        )
        return r.returncode == 0 and 'OK' in r.stdout
    except:
        return False


def move_to_junk(message_id):
    """Move a message to junk mailbox via AppleScript."""
    script = f'''tell application "Mail"
    try
        set msg to (first message of inbox whose id is {message_id})
        move msg to junk mailbox
        return "OK"
    on error
        return "FAIL"
    end try
end tell'''
    try:
        r = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True, text=True, timeout=15
        )
        return r.returncode == 0 and 'OK' in r.stdout
    except:
        return False


def main():
    print(f"=== Ares Mail Classifier v6 ===")
    print(f"Run: {datetime.now().isoformat()}")
    print(f"Model: {LLM_MODEL}")
    print()

    # Step 1: Scan ALL inbox messages (read + unread)
    print("Scanning inbox...")
    messages = scan_inbox()
    if not messages:
        print("No messages found. Inbox is empty.")
        return

    unread_count = sum(1 for m in messages if m.get('unread', True))
    read_count = len(messages) - unread_count
    print(f"Found {len(messages)} messages ({unread_count} unread, {read_count} read)")
    print()

    # Step 2: Classify each message
    junk_ids = []
    newsletter_ids = []
    archive_ids = []
    keep_count = 0
    llm_calls = 0
    heuristic_hits = 0

    for i, msg in enumerate(messages):
        sender = msg['sender']
        subject = msg['subject']
        is_read = not msg.get('unread', True)

        # Try heuristic first (fast)
        classification = heuristic_classify(sender, subject)

        if classification == 'keep':
            # KEEP_DOMAINS hit — but if it's read and matches archive domains, archive it
            if is_read:
                for d in ARCHIVE_DOMAINS:
                    if d in sender.lower():
                        classification = 'archive'
                        break
            if classification == 'keep':
                keep_count += 1
                continue
        elif classification:
            heuristic_hits += 1
        else:
            # Fall back to LLM for uncertain messages
            body = get_message_body(msg['id'])
            classification = llm_classify(sender, subject, body, is_read=is_read)
            llm_calls += 1

        if classification == 'junk':
            junk_ids.append(msg['id'])
            print(f"  [{i+1}] JUNK       | {sender[:45]:45} | {subject[:50]}")
        elif classification == 'newsletter':
            newsletter_ids.append(msg['id'])
            print(f"  [{i+1}] NEWSLETTER | {sender[:45]:45} | {subject[:50]}")
        elif classification == 'archive':
            archive_ids.append(msg['id'])
            print(f"  [{i+1}] ARCHIVE    | {sender[:45]:45} | {subject[:50]}")
        else:
            keep_count += 1

        sys.stdout.flush()

    # Step 3: Move junk and newsletters to junk, archive to archive
    print()
    print(f"Classification: {len(junk_ids)} junk, {len(newsletter_ids)} newsletters, {len(archive_ids)} archive, {keep_count} keep")
    print(f"Method: {heuristic_hits} heuristic, {llm_calls} LLM calls")
    print()

    moved_junk = 0
    for msg_id in junk_ids + newsletter_ids:
        if move_to_junk(msg_id):
            moved_junk += 1

    moved_archive = 0
    for msg_id in archive_ids:
        # Find the sender/subject for NAS save
        arch_sender = ""
        arch_subject = ""
        for m in messages:
            if m['id'] == msg_id:
                arch_sender = m['sender']
                arch_subject = m['subject']
                break
        if move_to_archive(msg_id, arch_sender, arch_subject):
            moved_archive += 1

    if moved_junk > 0 or moved_archive > 0:
        print(f"🗑️  Moved {moved_junk} junk/newsletters to junk mailbox")
        print(f"📦 Archived {moved_archive} read receipts/statements/alerts")
    else:
        print("✅ Inbox is clean — nothing to move")

    # Step 4: Report final state
    print()
    r = subprocess.run(
        ['osascript', '-e',
         'tell application "Mail" to log (count of messages of inbox) & " total, " & (count of (messages of inbox whose read status is false)) & " unread"'],
        capture_output=True, text=True, timeout=30
    )
    if r.stdout:
        print(f"Inbox: {r.stdout.strip()}")


if __name__ == '__main__':
    main()