-- Ares Butler: Install Mail.app Rules
-- Uses correct AppleScript enum names from Mail.sdef:
--   rule type: from header, subject header, etc.
--   qualifier: does contain value, begins with value, etc.
--   move message: mailbox object
--
-- Re-run this on any Mac. Saved at:
--   ~/.ares/scripts/mail-rules/install-rules.applescript
--   ~/GitHub/ARES/tools/mail-butler/install-rules.applescript

tell application "Mail"
	
	-- Remove any old Ares rules first
	try
		repeat with r in rules
			if name of r starts with "Ares" then delete r
		end repeat
	end try
	
	-- Delete existing Junk mailbox rules that Ares created
	-- (Mail.app stores rules persistently, so clean slate)
	
	-- ══════════════════════════════════════════════
	-- JUNK DOMAINS — Move to Junk mailbox
	-- ══════════════════════════════════════════════
	
	set junkDomains to {"zippyblinkoshop.com", "financebalancestrong.com", "budgetcontrolfinancehub.info", "bestshoppingcollective.info", "ordertopbrands.info", "skayouth.co.uk", "completecapitalplan.com", "clickaddcartandenjoy.info", "homelivingspace.info", "approvedfinancialwork.org", "capitalinsightpro.info", "trustedhomesolutionshub.info", "allaroundhomesolution.info", "mail.award-headquarters.com", "mail.smilegeneration.com", "notify.hobbyking.com", "e.epiqnotice.com", "mail.clientexperience.citi.com"}
	
	repeat with d in junkDomains
		try
			set r to make new rule with properties {name:"Ares Junk: " & d, enabled:true}
			make new rule condition at end of rule conditions of r with properties {rule type:from header, qualifier:does contain value, expression:d}
			set move message of r to mailbox "Junk" of account "iCloud"
		end try
	end repeat
	
	-- ══════════════════════════════════════════════
	-- NEWSLETTER SENDERS — Mark as Read (archive behavior)
	-- ══════════════════════════════════════════════
	
	set newsDomains to {"journeys@em.journeys.com", "no-reply@journeys.com", "mail.beehiiv.com", "thestretch@mail.beehiiv.com", "newsletter@mail.coinbase.com", "enews.sierraattahoe.com", "events@mail.stubhub.com", "mail.comms.yahoo.net", "hello@505games.com", "e-rewards.dominos.com", "dominosemail.smg.com", "e-confirmation.dominos.com", "gwp@greatworkperks.com", "noreply@august.com"}
	
	repeat with d in newsDomains
		try
			set r to make new rule with properties {name:"Ares Archive: " & d, enabled:true}
			make new rule condition at end of rule conditions of r with properties {rule type:from header, qualifier:does contain value, expression:d}
			set mark read of r to true
		end try
	end repeat
	
	-- ══════════════════════════════════════════════
	-- RETURN-PATH SPAM (news.enableearn.com is a known spam origin)
	-- ══════════════════════════════════════════════
	
	try
		set r to make new rule with properties {name:"Ares Junk: enableearn.com", enabled:true}
		make new rule condition at end of rule conditions of r with properties {rule type:from header, qualifier:does contain value, expression:"news.enableearn.com"}
		set move message of r to mailbox "Junk" of account "iCloud"
	end try
	
	log "Ares Mail Rules installed."
	set ruleCount to count of rules
	log "Total rules in Mail.app: " & ruleCount
	
	return "Installed Ares mail rules"
end tell