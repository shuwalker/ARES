-- Ares Butler Junk Cleanup — FAST PASS v2
-- Only targets 100%-junk domains. Uses Mail sender filter (fast).

tell application "Mail"
    set trashCount to 0
    
    -- 100% junk — these are spam-only senders
    set junkDomains to {"zippyblinkoshop.com", "financebalancestrong.com", "budgetcontrolfinancehub.info", "bestshoppingcollective.info", "ordertopbrands.info", "skayouth.co.uk", "completecapitalplan.com", "clickaddcartandenjoy.info", "homelivingspace.info", "approvedfinancialwork.org", "capitalinsightpro.info", "trustedhomesolutionshub.info", "allaroundhomesolution.info", "mail.award-headquarters.com", "mail.smilegeneration.com", "notify.hobbyking.com", "e.epiqnotice.com", "mail.stubhub.com", "mail.comms.yahoo.net"}
    
    repeat with term in junkDomains
        try
            set matching to (every message of inbox whose sender contains term)
            repeat with m in matching
                try
                    delete m
                    set trashCount to trashCount + 1
                end try
            end repeat
        end try
    end repeat
    
    -- Also hit specific phishing/scam senders
    set junkExact to {"@financebalancestrong.com", "@bestshoppingcollective.info", "@ordertopbrands.info"}
    repeat with term in junkExact
        try
            set matching to (every message of inbox whose sender contains term)
            repeat with m in matching
                try
                    delete m
                    set trashCount to trashCount + 1
                end try
            end repeat
        end try
    end repeat
    
    return "Trashed: " & trashCount
end tell