-- Ares Butler Junk Cleanup
-- Trash known spam senders from unified inbox

tell application "Mail"
    set inboxMsgs to messages of inbox
    set trashCount to 0
    set totalCount to count of inboxMsgs
    
    -- Known junk domains (auto-trash)
    set junkDomains to {"zippyblinkoshop.com", "financebalancestrong.com", "budgetcontrolfinancehub.info", "bestshoppingcollective.info", "ordertopbrands.info", "skayouth.co.uk", "completecapitalplan.com", "clickaddcartandenjoy.info", "homelivingspace.info", "mail.beehiiv.com", "news.enableearn.com", "approvedfinancialwork.org", "notify.hobbyking.com", "mail.smilegeneration.com", "mail.award-headquarters.com", "my.joinhoney.com", "match.indeed.com", "marketing.moviepass.com", "mail.coinbase.com", "clientexperience.citi.com", "251835611.mailchimpapp.com", "e.epiqnotice.com", "505games.com", "mail.synchronybank.com"}
    
    -- Known junk senders (from triage DB)
    set junkSenders to {"gwp@greatworkperks.com", "noreply@august.com", "bd@revopoint3d.com", "sales@abcrifle.com", "thestretch@mail.beehiiv.com"}
    
    -- Newsletter/high-volume senders to mark read + archive
    set newsletterSenders to {"journeys@em.journeys.com", "no-reply@journeys.com", "coinbase bytes", "info@news.enableearn.com", "stubhub.com", "yahoo.net", "yahoogroups.com"}
    
    repeat with m in inboxMsgs
        try
            set msgSender to sender of m
            if msgSender is missing value then set msgSender to ""
            
            -- Check if sender matches junk patterns
            set isJunk to false
            repeat with d in junkDomains
                if msgSender contains d then
                    set isJunk to true
                    exit repeat
                end if
            end repeat
            
            if not isJunk then
                repeat with s in junkSenders
                    if msgSender contains s then
                        set isJunk to true
                        exit repeat
                    end if
                end repeat
            end if
            
            if isJunk then
                delete m
                set trashCount to trashCount + 1
            end if
        end try
    end repeat
    
    log "Total inbox: " & totalCount & " | Trashed: " & trashCount
    return "Total: " & totalCount & " | Trashed: " & trashCount
end tell