#!/usr/bin/env python3
"""
Ares Dynamic Mail Cleaner v4
Single AppleScript call - batch all domain checks.
"""

import subprocess
import re
from datetime import datetime

ALL_DOMAINS = [
    # Original spam domains
    "senheguang.com", "hankukevent.com", "enableearn.com",
    "exclusiveeoffers.org", "preservented.nl", "horisora.net",
    "scandigenough.com.de", "freiraffirm.net", "tumorosa.media",
    "palaceextend.com", "itchynumberless.org", "friencept.net",
    "paxgoods.store", "chichahejiu.com", "zippyblinkoshop.com",
    "financebalancestrong.com", "budgetcontrolfinancehub.info",
    "bestshoppingcollective.info", "ordertopbrands.info",
    "skayouth.co.uk", "completecapitalplan.com",
    "clickaddcartandenjoy.info", "homelivingspace.info",
    "approvedfinancialwork.org", "capitalinsightpro.info",
    "trustedhomesolutionshub.info", "allaroundhomesolution.info",
    "notify.hobbyking.com", "mail.clientexperience.citi.com",
    "luettgen.itchynumberless.org", "deckow.horisora.net",
    "hodkiewicz.adjustmenttowering.co.in", "howe.tumorosa.media",
    "xsxylzokap.friencept.net", "klein.scandigenough.com.de",
    "moe-dl.edu.my", "goldandcryptoinsights.me",
    "homfriends.us", "girlreview.us", "privzone.xyz",
    "zrtxemik.sdfv", "mail.smilegeneration.com",
    "e.epiqnotice.com", "mail.award-headquarters.com",
    # Financial scam domains (added 2026-06-25)
    "smartfinanceinfrastructure.org", "globalwealthinsight.info",
    "financeloanmasters.com", "financialelevations.info",
    "stronghealthcareplan.com", "efficienthomeplans.com",
    "homeevolutionstudio.com", "investwithclarity.info",
    "modernlivingsolutions.org", "practiallfinancehelp.info",
    "dwellingmodernization.info", "refinancefinsolutions.info",
    "creativelivingspot.info", "sustainpersonalfinance.com",
    "savespendandinvest.com", "connectedfinancehub.info",
    # Investment newsletter spam
    "ifw.insightfulword.com", "news.theinvestorforge.com",
    "delamoms.com", "9K8hcmKAO1Yw4i.com",
    # Marketing/newsletter domains
    "account.brilliant.org", "email.hm.com", "hm.com",
    "vanswarpedtour.insomniac.com", "butcherbox.com",
    "t.zagg.com", "lovisa.com", "welcome.pure.app",
    "eg.expedia.com", "email.moviesanywhere.com", "info.cgtrader.com",
    "bananarepublic.com", "notifications.creditkarma.com",
    "s.usa.experian.com", "ollama.com", "email.anthropic.com",
    "bluerabbitrx.com", "patreon.com", "a1storage.com",
    # Promotional/marketing
    "smithsonianstore.com", "r.groupon.com", "sender.runtastic.com",
    "twxcarry.net", "samsungcareplus.onpointwarranty.com",
    "mail.instagram.com", "joinhoney.com", "updates.withflex.com",
    "sendowl.com", "coalax.com", "iemail.moneylion.com",
    "instantloves.xyz", "quicken@mail.quicken.com", "mail.visible.com",
    "email.benihana.com", "hello@paperlike.com", "no-reply@spotify.com",
    "g.greenchef.com", "donotreply@audible.com", "renaissanceclub.co",
    "email-ws.withings.com", "email.norwegianreward.com",
    "noreply@steampowered.com", "petlink.net", "dmea1.com",
    "expediamail.com", "Expediapolicies@aig.com",
    # Guns.com marketing
    "e-email.guns.com",
    # Hawaiian Airlines credit card promos
    "emails_BarclaysUS_com",
    # AMC theatre receipts/promos
    "email_amctheatres_com",
    # Demo Days Festival
    "demodaysfestival.com",
    # Misc spam
    "editor.jointheflyover.com", "mail_outskill_com",
    "email_hollywoodparkca_com", "info_enigmalabs_io",
    "sidewalkfoodtours_com", "mar_medallia_com", "agenda_com",
    "vello.idexx.com", "steampowers.net", "nokiamail.com",
    "uvvu.com", "flixstermail.com", "ancestry.com", "grabcad.com",
    "chatroulette.com", "getpure.org", "Filabotpfm@gmail.com",
    "support.sonyericsson.com", "safeopt_com", "boganet.cl",
    "dropboxmail.com", "renfairnews-renfair.com@shared1.ccsend.com",
    "sarah@onyxhomes.com", "sarah.kahn@rise-a.intercom-mail.com",
    "docusign@docusign.com", "msftfort@microsoft.com",
    "google-noreply@google.com", "datehookup.com", "scholarships.com",
    "noreply@tangocard.com", "no-reply@kik.com", "ytegukby@gmail.com",
    "dcluttonbrock@gmail.com", "mayapynchon@gmail.com",
    "digital-downloads.com", "wgresorts.com", "dsr.incogni.com",
    "mooselabsllc.com", "windowsinsingerprogram@e-mail.microsoft.com",
    # Legacy newsletter/promo domains
    "505games.com", "greatworkperks.com", "august.com", "e.rasushi.com",
    "e.zagg.com", "cyncsmart.com", "keto-mojo.com", "forged4x4.com",
    "ecoflow.com", "wallethub.com", "jackery.com", "harborfreight.com",
    "atlassian.com", "hive.co", "eufymega.com", "discover.com",
    "progressive.com", "onewheel.com", "rocketmoney.com", "one.app",
    "hilton.com", "sonos.com", "sparkmailapp.com", "upgrade.com",
    "23andme.com", "we.team", "narvar.com", "lge.com", "shein.com",
    "dominos.com", "e-rewards.dominos.com", "e-confirmation.dominos.com",
    "reviveyourresidence.com", "smilegeneration.com",
    "beauty.sephora.com", "releasablepastiche.net",
    "saleseasonsaviornow.info", "jfpcrystal.co.uk",
    "financereservefund.com", "financialsolutionnavigator.info",
    "clickdealstream.com", "trendystoreonline.info",
    "alternativeassetacquisition.com", "advancedcapitalwealth.info",
    "comenfr.com", "wealthifedebtfree.info", "quickdealshopping.info",
    "shoppingcartsonline.info", "shoppointcloud.com",
    "digitalshoppingcart.info", "smartcartdeals.org",
    "capitalequityfinance.com", "bagitandtagitfast.com",
    "settledebtdirect.com", "basketanalysiszone.com",
    "journeys.com", "beehiiv.com", "coinbase.com",
    "sierraattahoe.com", "stubhub.com", "yahoo.net",
]

def build_batch_script():
    lines = ['tell application "Mail"']
    for domain in ALL_DOMAINS:
        lines.append(f'    try')
        lines.append(f'        set matching to (every message of inbox whose sender contains "{domain}")')
        lines.append(f'        set c to count of matching')
        lines.append(f'        if c > 0 then')
        lines.append(f'            repeat with m in matching')
        lines.append(f'                move m to junk mailbox')
        lines.append(f'            end repeat')
        lines.append(f'            log "Moved " & c & " from {domain}"')
        lines.append(f'        end if')
        lines.append(f'    end try')
    lines.append(f'    log "DONE"')
    lines.append('end tell')
    return '\n'.join(lines)


def main():
    print("=== Ares Dynamic Mail Cleaner v4 ===")
    print(f"Run: {datetime.now().isoformat()}")
    print(f"Checking {len(ALL_DOMAINS)} domains...")
    
    script = build_batch_script()
    with open('/tmp/ares_batch_clean.applescript', 'w') as f:
        f.write(script)
    
    result = subprocess.run(
        ['osascript', '/tmp/ares_batch_clean.applescript'],
        capture_output=True, text=True, timeout=300
    )
    
    total_moved = 0
    if result.stdout:
        for line in result.stdout.strip().split('\n'):
            if 'Moved' in line:
                print(f"  {line}")
                m = re.search(r'Moved (\d+) from', line)
                if m:
                    total_moved += int(m.group(1))
    
    if result.stderr and 'DONE' not in result.stderr:
        print(f"Errors: {result.stderr[:500]}")
    
    # Check inbox count
    r = subprocess.run(
        ['osascript', '-e', 'tell application "Mail" to log count of messages of inbox'],
        capture_output=True, text=True, timeout=30
    )
    inbox_count = r.stdout.strip() if r.stdout else "?"
    
    print(f"\n=== Summary ===")
    print(f"Moved {total_moved} messages to junk")
    print(f"Inbox remaining: {inbox_count}")


if __name__ == '__main__':
    main()
