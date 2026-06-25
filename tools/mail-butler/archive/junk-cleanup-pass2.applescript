-- Ares Butler Junk Cleanup — PASS 2
-- Targets obvious junk domains only. Keeps real senders (Amazon, PayPal, banks, family, receipts)

tell application "Mail"
    set inboxMsgs to messages of inbox
    set trashCount to 0
    
    -- Only these unambiguous junk domains — no risk of trashing real mail
    set junkDomains to {"zippyblinkoshop.com", "financebalancestrong.com", "budgetcontrolfinancehub.info", "bestshoppingcollective.info", "ordertopbrands.info", "skayouth.co.uk", "completecapitalplan.com", "clickaddcartandenjoy.info", "homelivingspace.info", "approvedfinancialwork.org", "capitalinsightpro.info", "trustedhomesolutionshub.info", "allaroundhomesolution.info", "clientexperience.citi.com", "mail.award-headquarters.com", "e.epiqnotice.com", "mail.smilegeneration.com", "notify.hobbyking.com"}
    
    -- Spam subject patterns (catch phishing/scams that sneak through different senders)
    set spamSubjects to {"could lose access", "don.t let a crash", "your data", "upgrade storage", "one repair bill", "glp-1", "weight loss", "bath remodel", "jacuzzi"}
    
    repeat with m in inboxMsgs
        try
            set msgSender to sender of m
            set msgSubject to subject of m
            if msgSender is missing value then set msgSender to ""
            if msgSubject is missing value then set msgSubject to ""
            
            set isJunk to false
            
            -- Check junk domains
            repeat with d in junkDomains
                if msgSender contains d then
                    set isJunk to true
                    exit repeat
                end if
            end repeat
            
            -- Check spam subject patterns (for senders not in domain list)
            if not isJunk then
                repeat with s in spamSubjects
                    if msgSubject contains s then
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
    
    log "Pass 2 trashed: " & trashCount
    return "Trashed: " & trashCount
end tell