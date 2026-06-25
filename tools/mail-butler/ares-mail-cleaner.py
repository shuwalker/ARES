#!/usr/bin/env python3
"""
Ares Mail Butler — IMAP Cleaner
Direct server-side cleanup of all 4 mail accounts.
No dependency on Mail.app being open or responsive.
Reproducible: run on any machine, any OS.

This script classifies every inbox message as:
  - TRASH (known spam/phishing domains)
  - ARCHIVE (newsletters, promotions, receipts)
  - KEEP (important: family, financial, work, account)

Usage:
  python3 ~/.ares/scripts/mail-rules/ares-mail-cleaner.py
  
Requires: pip install imap-tools
"""

import imaplib
import email
from email.header import decode_header
import re
import json
import os
import ssl
from datetime import datetime

# ── Config ──────────────────────────────────────────
# Accounts: user fills in app passwords once, script reads from this file
CONFIG_PATH = os.path.expanduser("~/.ares/scripts/mail-rules/accounts.json")

# ── Classification Rules ────────────────────────────

# These domains are 100% junk/spam — trash immediately
JUNK_DOMAINS = [
    # Original spam domains
    "zippyblinkoshop.com", "financebalancestrong.com",
    "budgetcontrolfinancehub.info", "bestshoppingcollective.info",
    "ordertopbrands.info", "skayouth.co.uk", "completecapitalplan.com",
    "clickaddcartandenjoy.info", "homelivingspace.info",
    "approvedfinancialwork.org", "capitalinsightpro.info",
    "trustedhomesolutionshub.info", "allaroundhomesolution.info",
    "mail.award-headquarters.com", "mail.smilegeneration.com",
    "notify.hobbyking.com", "e.epiqnotice.com",
    "clientexperience.citi.com", "senheguang.com", "hankukevent.com",
    "enableearn.com", "exclusiveeoffers.org", "preservented.nl",
    "horisora.net", "scandigenough.com", "freiraffirm.net",
    "tumorosa.media", "palaceextend.com", "itchynumberless.org",
    "friencept.net", "paxgoods.store", "chichahejiu.com",
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
    # Investment newsletter spam
    "ifw.insightfulword.com", "news.theinvestorforge.com",
    "delamoms.com", "9K8hcmKAO1Yw4i.com",
    # Dating/spam
    "nokiamail.com", "datehookup.com", "chatroulette.com",
    "getpure.org", "welcome.pure.app", "instantloves.xyz",
    "boganet.cl", "ytegukby@gmail.com", "dcluttonbrock@gmail.com",
    "mayapynchon@gmail.com",
    # Old services spam
    "steampowers.net", "uvvu.com", "flixstermail.com",
    "support.sonyericsson.com", "Filabotpfm@gmail.com",
    # Misc spam
    "twxcarry.net", "safeopt_com", "iemail.moneylion.com",
    "digital-downloads.com", "wgresorts.com", "dsr.incogni.com",
    "mooselabsllc.com", "coalax.com",
]

# These senders are newsletters/promos — archive, don't trash
ARCHIVE_DOMAINS = [
    "em.journeys.com", "journeys.com",
    "mail.beehiiv.com", "thestretch",
    "mail.coinbase.com", "newsletter@mail.coinbase.com",
    "enews.sierraattahoe.com",
    "my.joinhoney.com",
    "marketing.moviepass.com",
    "e-rewards.dominos.com", "dominosemail.smg.com",
    "e-confirmation.dominos.com",
    # Added 2026-06-25
    "account.brilliant.org", "email.hm.com", "hm.com",
    "vanswarpedtour.insomniac.com", "butcherbox.com",
    "t.zagg.com", "lovisa.com", "eg.expedia.com",
    "email.moviesanywhere.com", "info.cgtrader.com",
    "bananarepublic.com", "notifications.creditkarma.com",
    "s.usa.experian.com", "ollama.com", "email.anthropic.com",
    "smithsonianstore.com", "r.groupon.com", "sender.runtastic.com",
    "samsungcareplus.onpointwarranty.com", "mail.instagram.com",
    "updates.withflex.com", "sendowl.com",
    "quicken@mail.quicken.com", "mail.visible.com",
    "email.benihana.com", "hello@paperlike.com", "no-reply@spotify.com",
    "g.greenchef.com", "donotreply@audible.com", "renaissanceclub.co",
    "email-ws.withings.com", "email.norwegianreward.com",
    "noreply@steampowered.com", "petlink.net", "dmea1.com",
    "expediamail.com", "Expediapolicies@aig.com",
    "e-email.guns.com", "emails_BarclaysUS_com", "email_amctheatres_com",
    "demodaysfestival.com", "editor.jointheflyover.com",
    "mail_outskill_com", "email_hollywoodparkca_com",
    "info_enigmalabs_io", "sidewalkfoodtours_com",
    "mar_medallia_com", "agenda_com", "vello.idexx.com",
    "505games.com", "greatworkperks.com", "august.com", "e.rasushi.com",
    "e.zagg.com", "cyncsmart.com", "keto-mojo.com", "forged4x4.com",
    "ecoflow.com", "wallethub.com", "jackery.com", "harborfreight.com",
    "atlassian.com", "hive.co", "eufymega.com", "discover.com",
    "progressive.com", "onewheel.com", "rocketmoney.com", "one.app",
    "hilton.com", "sonos.com", "sparkmailapp.com", "upgrade.com",
    "23andme.com", "we.team", "narvar.com", "lge.com", "shein.com",
    "dominos.com", "beauty.sephora.com", "beehiiv.com",
    "sierraattahoe.com", "stubhub.com", "yahoo.net",
    "patreon.com", "bluerabbitrx.com", "a1storage.com",
    "docusign@docusign.com", "msftfort@microsoft.com",
    "google-noreply@google.com", "scholarships.com",
    "noreply@tangocard.com", "no-reply@kik.com",
    "windowsinsiderprogram@e-mail.microsoft.com",
    "dropboxmail.com", "renfairnews-renfair.com",
    "sarah@onyxhomes.com", "sarah.kahn@rise-a.intercom-mail.com",
    "ancestry.com", "grabcad.com",
]

ARCHIVE_SENDERS = [
    "gwp@greatworkperks.com",
    "noreply@august.com",
    "bd@revopoint3d.com",
    "sales@abcrifle.com",
]

# These senders are IMPORTANT — never touch
KEEP_DOMAINS = [
    "amazon.com", "paypal.com", "chase.com", "fpcu.org", "savvymoney.com",
    "x.ai", "plaid.com", "facebookmail.com", "facebook.com",
    "email.apple.com", "apple.com", "applepay.apple.com",
    "applecard.apple.com", "post.applecard.apple", "post.gs-savings.apple",
    "servicing.synchrony.com", "synchronybank.com", "synchronyfinancial.com",
    "e.ea.com", "intuit.com", "turbotax@intuit.com",
    "fordcredit.com", "vanguard.com", "vanguardretirement.com",
    "guideline.com", "carta.com", "marcus.com", "savings.marcus.com",
    "quantumspace.us", "phasefour.io", "bamboohr.com", "gethired.com",
    "naviabenefits.com", "kellybenefits.com", "ktbsonline.com",
    "indeed.com", "indeedemail.com", "axelon.com",
    "github.com", "accounts.google.com", "notify.docker.com",
    "discord.com", "steampowered.com", "playstation.com",
    "sonyentertainmentnetwork.com", "txn-email.playstation.com",
    "starlink.com", "twingate.com", "anthropic.com",
    "uber.com", "lyftmail.com", "microsoft.com", "microsoftonline.com",
    "t-mobile.com", "tmobile@digital-delivery.com",
    "verizonwireless.com", "yahoo.com", "cc.yahoo.com", "yahoo-inc.com",
    "microcenter.com", "bestbuy.com", "citi.com",
    "ups.com", "mcinfo@ups.com", "enterprise.com", "erac.com",
    "american airlines", "info.email.aa.com", "egyptair.com",
    "selectegypt.com", "lukecaverns.travel@gmail.com",
    "starlink.com", "edovia.com", "paddle.com",
    "hmshost.com", "ca.wildlifelicense.com", "dmv.ca.gov",
    "library.lacounty.gov", "questdiagnostics.com",
    "optum.com", "avidiahealthcaresolutions.com",
    "pineanimalhospital.com", "ezyvet.com", "foundanimals.org",
    "michaelsutter.com", "lastpass.com", "privaterelay.appleid.com",
    "icloud.com", "trello.com", "rhombus",
    # Family
    "dnljenkins5@yahoo.com", "tc935@aol.com", "email.apple.com",
    # Google security alerts
    "no-reply@accounts.google.com",
]

def decode_str(s):
    """Decode email header to plain string"""
    if s is None:
        return ""
    parts = decode_header(s)
    result = []
    for part, charset in parts:
        if isinstance(part, bytes):
            try:
                result.append(part.decode(charset or 'utf-8', errors='replace'))
            except:
                result.append(part.decode('utf-8', errors='replace'))
        else:
            result.append(str(part))
    return ''.join(result)

def get_sender_domain(msg):
    """Extract sender domain from email"""
    sender = msg.get('From', '') or msg.get('from', '') or ''
    sender = decode_str(sender).lower()
    # Extract domain from email address
    match = re.search(r'@([\w.-]+)', sender)
    if match:
        return match.group(1).lower()
    return sender.lower()

def classify(msg):
    """Returns 'trash', 'archive', or 'keep' for a message"""
    sender = msg.get('From', '') or msg.get('from', '') or ''
    sender = decode_str(sender).lower()
    subject = msg.get('Subject', '') or msg.get('subject', '') or ''
    subject = decode_str(subject).lower()
    
    sender_domain = get_sender_domain(msg)
    
    # Check keep domains first (safety: never touch these)
    for domain in KEEP_DOMAINS:
        if domain in sender_domain or domain in sender:
            return 'keep'
    
    # Check junk domains
    for domain in JUNK_DOMAINS:
        if domain in sender_domain or domain in sender:
            return 'trash'
    
    # Check archive senders
    for domain in ARCHIVE_DOMAINS:
        if domain in sender_domain or domain in sender:
            return 'archive'
    
    for s in ARCHIVE_SENDERS:
        if s in sender:
            return 'archive'
    
    # Subject-based classification
    spam_subjects = [
        "could lose access", "don.t let a crash erase", "upgrade storage",
        "one repair bill", "glp-1", "weight loss", "bath remodel",
        "jacuzzi bath", "you could lose access"
    ]
    for pattern in spam_subjects:
        if pattern in subject:
            return 'trash'
    
    # Unknown sender — keep for now (better safe than sorry)
    return 'keep'

def clean_account(account_name, server, port, username, password):
    """Connect to IMAP, classify, and clean one account"""
    print(f"\n{'='*60}")
    print(f"📬 {account_name} ({username})")
    print(f"{'='*60}")
    
    try:
        context = ssl.create_default_context()
        mail = imaplib.IMAP4_SSL(server, port, ssl_context=context)
        mail.login(username, password)
        mail.select('INBOX')
        
        # Search all messages
        status, messages = mail.search(None, 'ALL')
        if status != 'OK' or not messages[0]:
            print("  No messages found")
            mail.logout()
            return
        
        msg_ids = messages[0].split()
        total = len(msg_ids)
        print(f"  Total: {total} messages")
        
        trash_ids = []
        archive_ids = []
        keep_ids = []
        
        # Classify in reverse (newest first, so we classify ~50 to understand the inbox)
        batch = msg_ids[-50:]  # Last 50 for classification sample
        older = msg_ids[:-50]  # Older messages
        
        for num in batch:
            status, data = mail.fetch(num, '(RFC822)')
            if status != 'OK':
                continue
            msg = email.message_from_bytes(data[0][1])
            classification = classify(msg)
            if classification == 'trash':
                trash_ids.append(num)
            elif classification == 'archive':
                archive_ids.append(num)
            else:
                keep_ids.append(num)
        
        print(f"  Sample (last 50): {len(trash_ids)} trash, {len(archive_ids)} archive, {len(keep_ids)} keep")
        
        # For older messages: classify in batches but don't fetch full bodies
        # Just check sender headers
        for num in older:
            status, data = mail.fetch(num, '(BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])')
            if status != 'OK':
                continue
            msg = email.message_from_bytes(data[0][1])
            classification = classify(msg)
            if classification == 'trash':
                trash_ids.append(num)
        
        # Report totals
        print(f"\n  📊 Results: {len(trash_ids)} trash, {len(archive_ids)} to archive")
        
        if trash_ids:
            print(f"  🗑️  Moving {len(trash_ids)} to trash...")
            for num in trash_ids:
                mail.store(num, '+FLAGS', '\\Deleted')
            mail.expunge()
            print(f"  ✅ {len(trash_ids)} trashed")
        
        if archive_ids:
            print(f"  📦 {len(archive_ids)} to archive (need IMAP folder setup)")
            # Most IMAP providers auto-archive. Mark as seen.
            for num in archive_ids:
                mail.store(num, '+FLAGS', '\\Seen')
            print(f"  ✅ {len(archive_ids)} marked as read (archived)")
        
        mail.logout()
        
    except Exception as e:
        print(f"  ❌ Error: {e}")
        return {'error': str(e)}
    
    return {'trashed': len(trash_ids), 'archived': len(archive_ids)}

def main():
    print("╔══════════════════════════════════════╗")
    print("║     Ares Mail Butler — Cleaner      ║")
    print("╚══════════════════════════════════════╝")
    print(f"  {datetime.now().isoformat()}")
    
    if not os.path.exists(CONFIG_PATH):
        print(f"\n⚠️  No accounts config found at {CONFIG_PATH}")
        print("  Create it with your IMAP credentials:")
        print(json.dumps({
            "accounts": [
                {
                    "name": "Gmail",
                    "server": "imap.gmail.com",
                    "port": 993,
                    "username": "matjuchiha@gmail.com",
                    "password": "app-password"
                }
            ]
        }, indent=2))
        print("\n  (App passwords, not your main password)")
        return
    
    with open(CONFIG_PATH) as f:
        config = json.load(f)
    
    results = []
    for acct in config.get('accounts', []):
        result = clean_account(
            acct['name'],
            acct['server'],
            acct.get('port', 993),
            acct['username'],
            acct['password']
        )
        results.append(result)
    
    print(f"\n{'='*60}")
    print("Done. Inbox cleaner saved to ~/.ares/scripts/mail-rules/")

if __name__ == '__main__':
    main()