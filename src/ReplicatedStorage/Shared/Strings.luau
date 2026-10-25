--!strict
-- All player-facing English text, as one nested, frozen table (shared: server and client).
-- DESIGN §0.3 #6, §2.2, §2.10. No player-facing literal may live anywhere else.
--
-- Rules:
-- * Keys are `area.camelCase`. Ids inside a key use camelCase too (`squishy.kittyBread.name`, like
--   `ability.dragonRush.incoming`); Catalog/Boxes/Config store the full key (`nameKey`), never derive it.
-- * Placeholders are `{name}`, filled by `Strings.format`. Every number that is a [P] Config value is a
--   placeholder (never typed into the text), so retuning Config never makes a text lie.
-- * Texts that depend on a count are `{ one = ..., many = ... }` pairs, chosen with `Strings.plural`.
-- * Server reason codes (§2.10) live only under `reason.*` and are read with `Strings.reasonText(code)`.
--   "No Coins were spent" is never part of a reason text: the client adds `common.noCoinsSpent` only when
--   the server's Result says `charged = false` (§2.10, §11.3).
-- FFA/TDM v1 (2026-10-15): match.* holds every Free for All / Team Deathmatch text (MatchService toasts, refusals, the
-- client's test readout).
-- Power-ups v1.1 (2026-10-16): match.powerUp.<kind> (the pickup toast), match.readout.powerUp and
-- match.readout.powerUpName.<kind> (the test readout's live power-ups).
-- Auto-clicker check (2026-10-16): reason.squeeze.autoClick (the warning) and autoClick.kick / kickNoBan / ban.
-- Bubble Pop bounce (2026-10-16): ability.bubblePop.description says it bounces off cover once.
-- Practice bot (2026-10-16): bot.nameStarts / bot.nameEnds, the word lists of the 1v1 bot's names (Logic/BotRules.name:
-- <start><end>[_]<number>, e.g. "SquishFan_23"; letters only, kind words, never a real username on purpose;
-- Config/ValidateBots checks that the longest name fits 20 characters).
-- Pens (pens3 phase 1, 2026-10-17; [P] texts): pen.* (the PEN SPACE sign, its prompt, the coin label over a walking
-- squishy), reason.pen.* (PenBuySpot), onboarding.pen, grip.goalPen / goalPenReady (the Next line's pen goal), and the
-- three Grip texts that named capsules (grip.panelIntro, grip.intro, grip.idleBody).
-- Pens3 phase 3: the capsule texts are gone (reason.capsule.*, onboarding.capsule, the capsule card, the capsule goals,
-- base.capsuleLevel / unlockPrice); capsule.power / powerNote are squishy.power / powerNote now (same texts).
-- Pens3 phase 4 ([P] texts): away.* (the coins-while-away pop-up).
-- Pens3 phase 5 ([P] texts): reason.inventory.full (the Toy Box is full), shop.welcomePrice (D1:202), box.nextItem (a
-- fixed-order box shows its next squishy before you open it, D1:235), onboarding.firstBox names the Welcome price; the
-- box footer and the restricted note say what is true now (a squishy you own again is a copy; restricted accounts
-- open boxes in a fixed order). With their last readers (the client half): reason.box.restricted / complete,
-- reason.shop.owned (no server sends them), box.refundLine / revealRefund (no refunds) and box.shopDirect (the
-- restricted Boxes card opens now) are gone.
-- Pens3 phase 6 ([P] texts): pen.screen.* (the stand-in pen screen: place, put away, swap, lock) and its refusals
-- reason.pen.spotClosed / changePaused (PenPlace, PenLock).
-- Pens3 phases 7-8 ([P] texts): the pen screen's sell, Sell All, buy-back and fusion texts (pen.screen.*) and their
-- refusals reason.pen.sellStarter / locked / lastCopy / nothingToSell / buyBackGone / fuseMismatch / fuseTop; the
-- buy-back time is a plain number of minutes (no countdown, no pressure); selectHint names selling and fusing.
-- Pens3 phase 9 ([P] texts): food.<id>.name (the 7 foods, V2:216-224's names), their refusals reason.food.notYet /
-- full / notEnough and reason.pen.maxLevel / nothingToFeed, and the pen screen's food texts (pen.screen.feed*, food*,
-- buyFood, levelsUp, the sell confirm's foodNote); selectHint names feeding. Calm: no "now", no countdown.
-- Pens3 phase 12: highway.* (the world's texts: the biome names on the launch gate and the arches, the launch board's
-- static lines, the distance markers' lines).
-- Access2 (2026-10-18, [P] texts): hud.nav.highway (the HUD's HIGHWAY stand-in tile) and reason.highway.* (GoHighway's
-- refusals; never a "busy" one: a full deck sends the trip onto the bridge's walk beside it).
-- Pens3 phase 13 ([P] texts): the throw's refusals reason.highway.* (HighwayThrow), the board's LAST THROWS heading
-- (it lists the last throws of everyone in the server now) and its empty line, highway.studs (a distance), and the
-- stand-in throw texts (the landing, a new best, a new biome, the biome gifts, the Food Bag). Calm: no "now", no
-- countdown; the auto-clicker warning names no number.
-- P13v3 (owner 2026-10-18: "Yes, above 20 a second", [P] texts): reason.squeeze.superFast and reason.highway.superFast,
-- the speed rule's calm warnings (AutoClickService; no number, no "now").
-- P13v4 (owner 2026-10-19: the TikTok throw screen, [P] words): highway.screen.* (the flight HUD: zone, rings, the
-- PERFECT bar's label, the boost button by input, its fuel line), highway.pop.* (PERFECT!, SQUISH! for the video's
-- QUACK!, LAST ONE!, BULLSEYE!, the rings, the landing, NEW BEST!) and reason.highway.noFuel; highway.flying (the
-- pill) is gone. Calm: no "now", no countdown.

export type FormatArgs = { [string]: any }

-- Shared texts (one definition, referenced from two keys).
local ERROR_TEXT = {
	generic = "Something went wrong. Please try again.",
	connect = "Couldn't connect to the game server. Please rejoin.",
}
local BOX_RESTRICTED_TEXT =
	"Coin boxes open in a fixed order on your account, so you see the next squishy first, and day 7 of Daily Rewards gives a free Royal Box."
local BOX_UNKNOWN_TEXT = "Couldn't check box availability. Try again."

local MAX_LOGGED_CODE_LENGTH = 64

local Strings = {
	-- Client-side errors before or outside a server reply (boot: `error.connect`, §2.6).
	error = ERROR_TEXT,

	-- Server reason codes (§2.10). Read through `Strings.reasonText(code)`.
	reason = {
		error = ERROR_TEXT,
		net = {
			rateLimited = "You're doing that too fast. Please wait a moment.",
			invalid = "That request wasn't valid. Please try again.",
		},
		data = {
			notReady = "Coins are paused because your data didn't load. Please rejoin.",
			offline = "Your progress couldn't load, so this is turned off for now.",
			readOnly = "Your progress can't be saved on this server, so this is turned off. Please rejoin.",
			openedElsewhere = "Your progress was opened on another server. Please rejoin.",
			waitingOtherServer = "Your data is still closing on another server…",
		},
		economy = {
			notEnoughCoins = "You don't have enough Coins.",
		},
		inventory = {
			notOwned = "You don't own this squishy yet.",
			lockedInDuel = "You can change squishies after the duel.",
			-- Pens3 phase 5: a paid box open or a shop buy while the Toy Box holds toyBoxMax unplaced squishies.
			full = "Your Toy Box is full. Make room first!",
		},
		queue = {
			unavailable = "Duels are unavailable right now.",
			paused = "The server is restarting soon, so duels are paused.",
			cooldown = "Please wait a moment before joining the queue again.",
			alreadyQueued = "You're already in the queue or in a duel.",
			removedIdle = "You were removed from the queue for being idle.",
			-- {minutes} = Config.Duel QueueMaxSeconds / 60 (filled by the sender or the client).
			timedOut = "You left the queue after {minutes} minutes. Join again any time.",
			-- Reading (not in §2.10): QueueJoin needs a living character (§2.8) and DESIGN names no code for it.
			notReady = "Wait until your character has loaded, then try again.",
		},
		duel = {
			noRewardsOffline = "Your progress didn't load, so duels can't earn rewards right now.",
			rewardsReduced = "Reduced reward: you've played this opponent a lot in the last hour.",
			tooShort = "Match too short for rewards.",
		},
		throw = {
			cooldown = "Not ready to throw yet.",
			context = "You can't throw here.",
			direction = "You can't throw in that direction.",
			tooMany = "Too many throws in the air. Wait a moment.",
			-- Reading (not in §2.10): §5.6 #4 "not rooted by Dragon Rush" (telegraph and recovery); spec phase 5: every
			-- ultimate roots its caster the same way.
			rooted = "You can't throw while using your ultimate.",
			-- Feature 1 (2026-10-11, not in §2.10): a throw while the hands are open for a catch or crushing a caught toy.
			busy = "Your hands are busy.",
		},
		-- Feature 1 (2026-10-11, not in §2.10): a CatchRequest the server refuses (Logic/CatchRules). The client's own
		-- gate mirrors these rules, so they are never shown; each code still has its text.
		catch = {
			context = "You can't catch here.",
			cooldown = "Not ready to catch yet.",
			busy = "Your hands are busy.",
		},
		ult = {
			notReady = "Your ultimate isn't ready yet.",
			noRoom = "Not enough room. Step away from the wall.",
			-- Reading (not in §2.10): §5.9 activation outside Active/SuddenDeath or the practice range, and an aim
			-- whose flattened (horizontal) part is under Config.Abilities minHorizontalAim.
			context = "You can't use your ultimate here.",
			direction = "Aim along the ground to use your ultimate.",
		},
		squeeze = {
			-- Batch 1 #2: only the paid-squeeze cap (the hold rhythm) sends this code, and the client never shows it
			-- (kept so every server reason has a text, §2.10).
			tooFast = "Squeezing too fast. Wait a moment.",
			-- Reading (not in §2.10): §6.3 step 5, a squeeze from a player in a match (Matched through Returning).
			inDuel = "You can squeeze again after the duel.",
			-- Spec 2026-10-11 §5 (squeeze anywhere): a squeeze with no living character, the one refusal left of the old
			-- station checks (the mat and pad-level codes are gone). Same words as queue.notReady.
			noCharacter = "Wait until your character has loaded, then try again.",
			-- Auto-clicker check (2026-10-16): the short warning of the first catch (once; the client shows it as a
			-- toast and stops a hold). The next catch is a kick (autoClick.kick).
			autoClick = "Robot-fast squeezes don't count! Turn off any auto-clicker, or you'll be removed from the game.",
			-- P13v3: the speed rule's warning (more than 20 presses a second for 3 s), shown once like autoClick.
			superFast = "Super-fast squeezes don't count! Turn off any auto-clicker, or you'll be removed from the "
				.. "game.",
		},
		box = {
			checking = "Checking box availability…",
			unknown = BOX_UNKNOWN_TEXT,
			paused = "Boxes are paused while the server restarts soon.",
			saving = "Saving your collection…",
		},
		shop = {
			priceChanged = "The price changed. Please check it and try again.",
			notForSale = "This squishy isn't sold in the shop.",
		},
		quest = {
			notReady = "This quest isn't finished yet.",
			alreadyClaimed = "You already claimed this reward.",
			swapUsed = "You already used today's free swap.",
		},
		daily = {
			alreadyClaimed = "Claimed! Come back in {time}.",
		},
		purchase = {
			unavailable = "This purchase isn't available right now.",
		},
		-- Pens3 phase 1 (PenBuySpot; PenMath.buyDecision, PenService).
		pen = {
			max = "Your pen is as big as it gets!",
			paused = "Buying is paused for a moment. Try again soon.",
			priceChanged = "The price changed. Please check it again.",
			-- Pens3 phase 6 (PenPlace / PenLock; PenMath.placeDecision, PenService).
			spotClosed = "That pen spot isn't open yet.",
			changePaused = "Your pen can't change for a moment. Try again soon.",
			-- Pens3 phases 7-8 (SellItems / SellAll / BuyBack / Fuse; PenMath.sellDecision, buyBackDecision,
			-- fuseDecision, PenService).
			sellStarter = "Kitty Bread stays with you. It can't be sold.",
			locked = "That squishy is locked. Unlock it first.",
			lastCopy = "Keep at least one of each squishy. Your last one can't be sold.",
			nothingToSell = "Nothing to sell. Sell All keeps your pen, levelled, Golden, Rainbow and locked squishies, and one of each.",
			buyBackGone = "That squishy can't be bought back any more.",
			fuseMismatch = "Fuse 3 of the same squishy, all in the same form.",
			fuseTop = "Rainbow is the top form. It can't be fused again.",
			-- Pens3 phase 9 (Feed / FeedAll; PenMath.feedDecision, feedAllPlan, PenService).
			maxLevel = "That squishy is at the top level for now.",
			nothingToFeed = "Nothing to feed. Your pen squishies need more food, or they are at the top level.",
			-- Pens3 phase 11 (PenBuyShelf; PenMath.shelfDecision, PenService).
			shelfMax = "Your whole shelf and the TOP spot are open!",
		},
		-- Pens3 phase 9 (BuyFood, Feed; PenMath.buyFoodDecision, feedDecision, PenService).
		food = {
			notYet = "You can buy this food once you reach its biome.",
			full = "You have as much of that food as you can carry.",
			notEnough = "Not enough food for that. Buy some in your pen.",
		},
		-- The highway: access2 (GoHighway, HighwayAccessService: the trip to the launch deck) and pens3 phase 13
		-- (HighwayThrow, HighwayService). paused is shared by both (the server closing, a restart pending, or for the
		-- throw a failed save still pending). inFlight answers a press while the own squishy flies (the client sends
		-- those for the auto-clicker check and shows nothing); autoClick is the calm warning of the first auto-clicker
		-- catch, tooFast the throws refused during its pause.
		highway = {
			noCharacter = "Wait until your character has loaded, then try again.",
			closed = "The highway isn't open in this server yet.",
			paused = "The highway is paused for a moment. Try again soon.",
			inDuel = "You can go to the highway after the match.",
			inQueue = "Leave the queue first, then go to the highway.",
			notInArea = "Walk onto the launch deck to throw.",
			inFlight = "Your squishy is still flying!",
			tooFast = "Throwing is paused for a little while.",
			autoClick = "Robot-steady throws don't count! Turn off any auto-clicker, or you'll be removed from the "
				.. "game.",
			-- P13v3: the speed rule's warning on the THROW presses, shown like autoClick.
			superFast = "Super-fast throws don't count! Turn off any auto-clicker, or you'll be removed from the game.",
			-- P13v4: a boost press with no boost left on this throw (the client shows nothing: its button says
			-- NO FUEL).
			noFuel = "No boost left on this throw.",
		},
	},

	-- Small texts reused by many screens.
	common = {
		close = "Close",
		cancel = "Cancel",
		equip = "Equip",
		equipped = "Equipped",
		inspect = "Inspect",
		owned = "Owned",
		notOwned = "Not owned",
		claim = "Claim",
		claimed = "Claimed",
		loading = "Loading…",
		tryAgain = "Try again",
		gotIt = "Got it",
		skip = "Skip",
		coinsAmount = "{coins} Coins",
		coinsGain = "+{coins} Coins",
		plusAmount = "+{n}",
		minusAmount = "-{n}", -- UI FINAL R4: a spend's float on the coin pill (H:673)
		percent = "{value}%",
		secondsShort = "{seconds}s", -- a cooldown's remaining seconds on a button (§11.6)
		progress = "{progress}/{goal}",
		needCoins = { one = "Need {missing} more Coin", many = "Need {missing} more Coins" },
		lockedInDuel = "Not available during a duel",
		noCoinsSpent = "No Coins were spent.",
		-- Reading: the two states of a toggle (UI/Components/Toggle: Camera shake, Show tips), always shown as text.
		on = "On",
		off = "Off",
	},

	-- Data status banners (§3.1, §3.13, §11.3).
	data = {
		studioMemory = "Studio test: progress is not saved.",
		offlineRetrying = "Your progress couldn't load. Nothing will be saved right now. We're retrying.",
		loaded = "Progress loaded!",
		rejoin = "Please rejoin.",
		newerVersion = "A new version is rolling out. Rejoin to keep earning.",
		loadFailed = "Couldn't load your progress. Your saved progress is safe. Please rejoin.",
	},

	-- `DataModel.ServerRestartScheduled` notice (§3.12).
	server = {
		restartSoon = "This server will restart in {time}.",
	},

	-- Auto-clicker check (2026-10-16; server AutoClickService): the kick message (Player:Kick, the 2nd catch) and the
	-- ban's DisplayReason (Players:BanAsync, at most 400 characters, filtered by Roblox; the 3rd catch). {hours} =
	-- Config.Net.AutoClick.banSeconds / 3600. Review fix (2026-10-16): kickNoBan is the kick when no ban can follow
	-- (Players.BanningEnabled off, or a test account), so the message never promises one. Batch B (owner 2026-10-17):
	-- banLonger is the DisplayReason of every later, longer ban (after a ban ends, the next catch); {days} =
	-- Config.Net.AutoClick.laterBanSeconds / 86400.
	autoClick = {
		kick = "You were removed for using an auto-clicker. Turn it off and come back! If it happens again soon, you can't play for {hours} hours.",
		kickNoBan = "You were removed for using an auto-clicker. Turn it off and come back!",
		ban = "Auto-clickers aren't allowed in Squishy Duels. You can play again in {hours} hours.",
		banLonger = "Auto-clickers aren't allowed in Squishy Duels, and this isn't the first time. You can play again in {days} days.",
	},

	-- Lobby HUD (§11.6).
	hud = {
		nav = {
			squishies = "Squishies",
			boxes = "Boxes",
			shop = "Shop",
			quests = "Quests",
			daily = "Daily",
			highway = "Highway", -- access2: the HIGHWAY stand-in tile
			duel = "Duel",
			settings = "Settings",
		},
		-- The DUEL button (top middle; UI FINAL R4, the design's H:130-131) and, while the 1v1 queue searches, its bar
		-- (H:139; the time is m:ss beside it), then MATCH FOUND with the opponent's name (H:151; the design's "Starting
		-- in 3…" is the arena's own countdown here, plan FD2).
		duelCta = "DUEL",
		duelJoin = "Join the queue",
		duelPick = "Pick a mode", -- LOBBY HUD L:168: the DUEL button opens the mode select
		-- Diego's mode select (2026-10-24, LOBBY HUD L:173-215, L:1358-1363; UI/ModeSelect): the three cards (keyed
		-- by Config.UI.ModeSelect.cards), the line under them and the close X's name.
		modeSelect = {
			title = "SELECT A GAME MODE",
			close = "Close",
			play = "Play",
			cards = {
				["1v1"] = { title = "DUEL", sub = "1 VS 1", ghost = "1v1" },
				tdm = { title = "TEAM\nDEATHMATCH", sub = "6 VS 6", ghost = "6v6" },
				ffa = { title = "FREE\nFOR ALL", sub = "12 PLAYERS", ghost = "12" },
			},
		},
		findingMatch = "Finding match",
		matchFound = "MATCH FOUND!",
		matchOpponent = "Opponent: {name}",
		-- UI FINAL R4: the DUEL mode picker for testers (Diego's newer file N:710-711; Config.Match.picker*); its short
		-- names when there is no room for the full ones (the design's MODES.*.tab, N:711-712, its search bar's chip).
		modes = {
			tdm = "TEAM DEATHMATCH",
			tdmChip = "6v6",
			tdmShort = "TEAM 6v6",
			ffa = "FREE FOR ALL",
			ffaChip = "SOLO",
			ffaShort = "FREE FOR ALL",
			-- [P] The owner's 1v1 tab (2026-10-16: keep all of 1v1, a 3rd tab now; not in Diego's design, he may
			-- rename it): "DUEL" + "1v1" like TEAM DEATHMATCH + 6v6; the short name alone where there is no room.
			duel = "DUEL",
			duelChip = "1v1",
			duelShort = "1v1",
		},
		-- The quest tracker card (top right): "Ready to claim!" in the coin yellow, else its reward (H:995).
		questReady = "Ready to claim!", -- UI overhaul: the tracker's quest is done and not claimed
		trackerReward = "+{coins} coins", -- H:995
		-- UI FINAL R4: the Double Grip chip beside the Grip bar (H:89; a pool of minutes, not a clock, plan FD3).
		gripBoost = "2x ~{minutes} min",
		notEnoughCoins = "Not enough coins!", -- H:676: a spend the Coins don't cover (the pill shakes)
		-- 2026-10-16 (the coin pill's "+", plan [UD5]): the green "+" at the pill's right end (H:80; the pill opens the
		-- Shop's Coins tab).
		coinsPlus = "+",
	},

	-- Touch / on-screen action buttons (§5.10, §6.3).
	controls = {
		throw = "Throw",
		ultimate = "Ultimate",
		dash = "Dash", -- spec phase 5: the touch Dash button (user decision 2026-10-11)
		slide = "Slide", -- 2026-10-17: the lobby's touch Slide button (LobbyMoveController)
		-- Feature 1 (2026-10-11): the touch Catch button and the dock's caption (design: html:96 "Catch").
		catch = "Catch",
		squeeze = "Squeeze",
		-- Text button prompts (§11.4: button prompts are text, "E", "X", "R2", "B"; §11.7 input map). Reading: shown
		-- as "{action} ({key})", e.g. "Inspect (V)".
		keyHint = "{action} ({key})",
		key = {
			inspectKeyboard = "V",
			inspectGamepad = "Y",
			squishiesKeyboard = "I",
			backKeyboard = "Backspace",
			backGamepad = "B",
		},
	},

	-- Practice range (§5.11, §7.7).
	practice = {
		title = "PRACTICE RANGE",
		sign = "Practice range: targets don't pay Coins",
		targetName = "Foam Dummy",
		-- Floor labels in front of the targets (§7.6 "with floor labels"; DESIGN gives no text: reading).
		-- {distance} = WorldLayout.PracticeRange target distance from the firing line.
		distanceLabel = "{distance} studs",
		-- Reading (DESIGN names the panel and the waypoint, not their titles): the session stats panel inside the
		-- zone (stats.* rows, §5.11) and the waypoint the queue's Practice button shows (§5.4).
		panelTitle = "Practice",
		waypoint = "Practice Range",
	},

	-- Queue pill, queue board and messages (§5.4, §7.7, §11.6).
	queue = {
		searching = "Looking for an opponent…",
		searchingTime = "Looking for an opponent… {time}",
		position = "You're #{n} in the queue",
		noOpponent = "No one else is in the queue right now.",
		keepWaiting = "Keep waiting",
		practice = "Practice",
		waitingArena = "All arenas are in use. You're next.",
		left = "You left the queue.",
		matched = "Opponent found: {name}",
		opponentFound = "Opponent found!",
		joinFailed = "Couldn't join the queue. Try again.",
		boardTitle = "Duel Queue",
		boardWaiting = "Waiting: {count}",
		boardActive = "Duels in progress: {count} of {max}",
		boardHint = "Matches start automatically when an opponent is found.",
		-- Batch 3 (review #6): beside Practice in the "no one else is in the queue" hint; Roblox's own invite window.
		inviteFriends = "Invite friends",
		-- UI FINAL R9 (G9.4, H:779): the pink toast when the move to the arena starts.
		teleporting = "Teleporting to the arena…",
	},

	-- Duel HUD, banners and result panel (§5.2, §5.4, §6.13, §9.14, §11.6).
	duel = {
		opponentLeftEarly = "Your opponent left before the duel started. You're back at the front of the queue.",
		suddenDeath = "Sudden death: next hit wins!",
		void = "The server is shutting down. This duel won't count.",
		-- §17.7 "Changed text": no word for the lobby stat here, because the tip is shown on the duel result panel.
		lossTip = "Tough streak! Squeezing earns Coins to unlock new squishies, and each one throws a little differently, but squeezing and training on pads don't make your throws stronger. The Practice Range is a great place to sharpen your aim.",
		countdownGo = "Throw!",
		you = "You",
		sideA = "Strawberry side",
		sideB = "Mint side",
		-- Final polish (2026-10-11): the hints also name the dash (spec phase 5: C / ButtonB) and the first-person squeeze
		-- (DuelSqueeze: F / ButtonX). Feature 1 (2026-10-11): and the catch (RMB or E / ButtonL1; design: html:96).
		-- Duel HUD (owner 2026-10-24, "Design keys"): Q catch, X ultimate, E dash (Duel HUD.dc.html:323).
		hintMouse = "Click Throw · Q Catch · X Ultimate · E Dash · F Squeeze",
		hintGamepad = "R2 Throw · L1 Catch · L2 Ultimate · B Dash · X Squeeze",
		-- Reading: the key hints when the locked loadout has no ultimate (the Ultimate button is hidden, §11.6).
		hintMouseNoUlt = "Click Throw · Q Catch · E Dash · F Squeeze",
		hintGamepadNoUlt = "R2 Throw · L1 Catch · B Dash · X Squeeze",
		-- Foam UI restyle (2026-10-09): the same key hints drawn as keycaps, one beside each meter's caption
		-- (controls.throw / controls.catch / controls.ultimate / controls.dash / controls.squeeze) in the bottom dock.
		key = {
			throwMouse = "Click",
			ultimateMouse = "X",
			throwGamepad = "R2",
			ultimateGamepad = "L2",
			dashMouse = "E",
			dashGamepad = "B",
			squeezeMouse = "F",
			squeezeGamepad = "X",
			catchMouse = "Q", -- Duel HUD 2026-10-24 (was "RMB/E"; the right mouse button still catches)
			catchGamepad = "L1", -- feature 1, build choice 2026-10-11 (NOT IN DESIGN: a mouse page)
		},
		-- Feature 1 (2026-10-11): the catch's big words (design: html:352, 563), and the prompt under the reticle while an
		-- opponent's throw comes at you (design: html:88 "Catch!" with its keys).
		caught = "CAUGHT!",
		squished = "SQUISHED!",
		abilityCatchTag = "CATCH!", -- Duel HUD part 2 (D:395): over the Catch button while the hands are open
		-- Duel HUD part 3 (D:57, 95, 166, 70; owner 2026-10-24: a duel is won at {n} = the lives, 3)
		topFirstTo = "First to {n}!",
		topFirstToPhone = "FIRST TO {n}",
		topMode = "Duel 1v1",
		topSquished = "SQUISHED",
		catchPrompt = "Catch!",
		catchPromptKey = "Catch! {key}",
		-- Final polish (2026-10-11): under the duel bar while an enemy lane ultimate's telegraph runs and your body is in
		-- its lane (Dragon Rush, Sprinkle Roller; UI/LaneCue).
		inLane = "In the lane!",
		forfeit = "Forfeit",
		forfeitConfirm = "Forfeit the duel?",
		-- Reading (DESIGN gives the question only): the confirm dialog's buttons and one line on what happens.
		-- {seconds} = Config.Duel.Rules.BailRequeueCooldownSeconds.
		forfeitYes = "Forfeit",
		forfeitNo = "Keep playing",
		forfeitCancelNote = "The duel hasn't counted yet, so it will be cancelled. You can queue again in {seconds} seconds.",
		forfeitLoseNote = "Your opponent wins if you forfeit now.",
		ultReady = "READY",
		-- Reading: life pips always come with this number (§11.6 "life pips plus a number").
		lives = { one = "{n} life", many = "{n} lives" },
		-- Reading: the opponent's label when no display name is known, and the off-screen arrow's label.
		opponent = "Opponent",
		-- Reading: Preparing / Positioning, before the countdown starts.
		waitingOpponent = "Waiting for your opponent…",
		-- Reticle states, shown as icon + text, never colour alone (§5.10). Cooling down shows common.secondsShort.
		reticle = {
			ready = "Ready",
			rooted = "Rooted",
			wrongZone = "Can't throw here",
		},
		-- Reading: Active / SuddenDeath out-of-bounds return to the pad (the Countdown re-pivot stays silent, §5.4).
		outOfBounds = "Out of bounds: back to your pad.",
		-- DuelResult.reasonKey lines under the result title, one per way a duel ends (§5.2 victory and draw rules,
		-- §5.4 edge cases). Reading: DESIGN names only `opponentLeft`; the others follow the same rules.
		opponentOut = "Your opponent is out of lives!",
		youOut = "You're out of lives.",
		timeUpWin = "Time's up! You had more lives left.",
		timeUpLoss = "Time's up! Your opponent had more lives left.",
		suddenDeathWin = "You landed the sudden-death hit!",
		suddenDeathLoss = "Your opponent landed the sudden-death hit.",
		suddenDeathDraw = "Sudden death ended with no hit.",
		tieHit = "You both landed the final hit at the same moment.",
		opponentLeft = "Your opponent left the duel.",
		youLeft = "You left the duel, so your opponent wins.",
		youOutOfBounds = "You left the court too many times.",
		opponentOutOfBounds = "Your opponent left the court too many times.",
		cancelled = "The duel was cancelled before it counted.",
		-- Reading: one quest line on the result panel ({quest} = the quest's own text).
		questLine = "{quest}: {progress}/{goal}",
		-- Keyed by DuelResult.outcome.
		result = {
			win = "VICTORY",
			loss = "DEFEAT",
			draw = "DRAW",
			cancelled = "Duel cancelled",
			void = "Duel didn't count",
		},
		reward = {
			win = "+{coins} Coins (win)",
			loss = "+{coins} Coins (loss)",
			draw = "+{coins} Coins (draw)",
		},
		-- {reason} = Strings.reasonText(DuelResult.coinsBlockedReason).
		rewardBlocked = "0 Coins: {reason}",
		queueAgain = "Queue again",
		testDummy = "TEST DUMMY (Studio)",
		-- Batch 3 (friends, review #6): the duel pads under the Duel tower (FriendDuelService) and Rematch on the
		-- result card. The waiting toasts name the pad the partner needs (a mint stander needs a friend on strawberry);
		-- padReady goes to both when a lane's two pads are taken ({seconds} = Config.Social.Pads.holdSeconds). The
		-- Rematch button stays short (rematchWaiting); the line over the buttons carries the name.
		padWaitingMint = "Get a friend on the mint pad across from you to duel!",
		padWaitingStrawberry = "Get a friend on the strawberry pad across from you to duel!",
		padReady = "Duel with {name} in {seconds} seconds! Step off to cancel.",
		rematch = "Rematch",
		rematchWaiting = "Waiting…",
		rematchWaitingFor = "Waiting for {name}…",
		rematchAsked = "{name} wants a rematch!",
		rematchStarting = "Starting…",
	},

	-- FFA/TDM v1 (2026-10-15): Free for All / Team Deathmatch inside the lobby server. The Notify toasts MatchService
	-- sends and the client's test readout (MatchController). Placeholders: {mode} = a match.mode.* name, {team} = a
	-- match.team.* name, {name} = a display name, {count} / {max} = players queued / the mode's maxPlayers, {seconds} =
	-- Config.Match.gatherSeconds (or what is left of it).
	match = {
		mode = {
			ffa = "Free for All",
			tdm = "Team Deathmatch",
		},
		-- Keyed by Config.Match.teamNames, lowercased.
		team = {
			strawberry = "Strawberry", -- owner 2026-10-16: STRAWBERRY vs BLUEBERRY
			blueberry = "Blueberry",
		},
		joined = "You joined the {mode} queue: {count}/{max} players.",
		left = "You left the {mode} queue.",
		leftForDuel = "You joined the duel queue, so you left the {mode} queue.",
		startingIn = "{mode} starts in {seconds} seconds!",
		waitingPlayers = "Waiting for more players to start {mode}…",
		waitingMap = "Every {mode} map is in use. You'll start when one is free.",
		notQueued = "You're not in a match queue.",
		youLeft = "You left the match.",
		notArrived = "You couldn't reach the map in time, so you're back in the lobby.",
		outOfBounds = "Out of bounds: back to a spawn.",
		outOfBoundsKo = "You fell off the map: squished!", -- Match HUD M7: the owner's word (plan §2)
		outNoLives = "Your team is out of lives, so you're out. Cheer on your team!",
		youWin = "You win the match!",
		winner = "{name} wins the match!",
		teamWins = "{team} team wins!",
		draw = "The match ended in a draw.",
		cancelled = "Not enough players arrived, so the match was cancelled.",
		void = "The server is shutting down. This match won't count.",
		voidError = "Something went wrong, so this match won't count.",
		-- qb1 (owner 2026-10-16): the match pay toast ({coins} / {grip} = Format.coins), until M9's results bar.
		paid = "+{coins} Coins, +{grip} Grip",
		-- MatchJoin refusals (the first that applies).
		refused = {
			closing = "The server is restarting soon, so matches are paused.",
			alreadyQueued = "You're already in a match queue. Type /leave to leave it.",
			inMatch = "You're already in a duel or a match.",
			duelQueue = "Leave the duel queue first.",
			practice = "Leave the Practice Range first.",
			noMaps = "{mode} isn't available on this server yet.",
		},
		-- Power-ups v1.1 (2026-10-16): the toast MatchService sends the player who took a pad, by Config.Match.PowerUps
		-- kind.
		powerUp = {
			shield = "SHIELD!",
			speed = "SPEED BOOST!",
			throwBoost = "THROW BOOST!",
			ultCharge = "ULT CHARGE!",
			dashBoost = "DASH BOOST!",
			rapidThrow = "RAPID THROW!",
			superJump = "SUPER JUMP!",
			teamLife = "+1 TEAM LIFE!",
		},
		-- The client's test readout (one Components/Chip at the top, until Diego's arena HUD): the mode's piece, then the
		-- extra pieces that apply, joined with `separator`. {mine} / {target} = your K.O.s / the mode's koTarget,
		-- {leaderName} / {leaderKos} = the leader, {redLives} / {blueLives} = the team lives, {time} = m:ss left in the
		-- phase, {pct} = your storm bar (0-100), {seconds} = seconds until you are back in. Power-ups v1.1 (2026-10-16):
		-- powerUp = one live power-up, {name} = its powerUpName.<kind> text below, {seconds} = whole seconds left.
		readout = {
			ffa = "SQUISHES {mine}/{target} · 1st {leaderName} {leaderKos} · {time}", -- owner 2026-10-16
			tdm = "STRAWBERRY {redLives} · BLUEBERRY {blueLives} · {time}",
			storm = "STORM {pct}%",
			overtime = "OVERTIME",
			backIn = "Back in {seconds}",
			out = "OUT",
			waiting = "Get ready…",
			separator = " · ",
			powerUp = "{name} {seconds}s",
			-- The short names of the timed power-ups (Config.Match.PowerUps kinds with seconds).
			powerUpName = {
				shield = "SHIELD",
				speed = "SPEED",
				throwBoost = "THROW",
				dashBoost = "DASH",
				rapidThrow = "RAPID",
				superJump = "JUMP",
			},
		},
	},

	-- Match HUD M6 / M7 (2026-10-17; M = "Squishy Duels Match HUD.dc.html"): the kill feed's tags (M:523-527) and its
	-- words for a K.O. with nobody to blame (owner 2026-10-16: a feed line for storm and fall K.O.s too, [P]); the
	-- "squished by" card (M:158-188; its storm / fall versions [P]); the RESPAWNING bar (M:197); the squishies'
	-- titles on the card (M:388, by Catalog id; Birdie is `bird`) and the title of one not in the list (M:664).
	matchHud = {
		you = "You", -- your own name in the feed and on the card (M:651, M:659)
		feed = {
			final = "FINAL KILL",
			firstBlood = "FIRST BLOOD",
			triple = "TRIPLE!",
			double = "DOUBLE!",
			streak = "{n} STREAK",
			-- The cause chip of a line with no attacker, by MatchRules' K.O. cause.
			cause = {
				storm = "STORM",
				outOfBounds = "FELL",
				other = "SQUISHED",
			},
		},
		card = {
			finalKill = "FINAL KILL",
			squishedBy = "squished by",
			title = "“{title}”",
			handle = "@{name}",
			gripLevel = "GRIP LEVEL",
			winStreak = "WIN STREAK",
			-- A K.O. with no attacker: the pill after "squished by", the big name and the line under it.
			cause = {
				storm = { pill = "THE STORM", name = "The Storm", line = "Stay inside the safe zone!" },
				outOfBounds = { pill = "A FALL", name = "Fell off!", line = "Watch your step near the edge!" },
				other = { pill = "BAD LUCK", name = "Squished!", line = "Shake it off and jump back in!" },
			},
		},
		respawn = {
			label = "RESPAWNING IN",
		},
		titles = {
			kitty_bread = "Loaf of Doom",
			toast = "Crispy Sniper",
			banana = "Peel Dealer",
			butter = "Smooth Operator",
			chocolate = "Cocoa Crusher",
			donut = "Ring Leader",
			boba_bear = "Pearl Pounder",
			pancake_pup = "Flapjack Flinger",
			mochi_fox = "Stretch Fox",
			strawberry_frog = "Berry Hopper",
			dragon = "Sky Scorcher",
			bird = "Fluff Flyer",
			cloud_bunny = "Cloud Crusher",
			cupcake_axolotl = "Frosting Fiend",
			fallback = "Squishy Slinger",
		},
	},

	-- Hit and elimination feedback (§9.8, §9.9).
	combat = {
		hit = "Hit!",
		out = "OUT!",
		ko = "K.O.!",
	},

	-- Abilities (§5.9). {seconds} = Config.Abilities.dragon_rush.telegraphSeconds. Spec phase 5: the four Epic
	-- ultimates use the design's names (ults.js:3-6) and short descriptions from its stats and counters (user decision
	-- 2026-10-11).
	ability = {
		interrupted = "Interrupted!",
		dragonRush = {
			-- Duel HUD (owner 2026-10-24, "Use 'Dragon Burst'"; design: Duel HUD.dc.html:229): renamed from Dragon Rush; it
			-- recharges on its own timer now (Config.Abilities header).
			name = "Dragon Burst",
			incoming = "Dragon Burst incoming!",
			ready = "Dragon Burst ready",
			description = "Shows a warning lane for {seconds} seconds, then a dragon head charges down it. If your opponent is touching the lane, they lose a life. Ready again 45 seconds after you use it.",
		},
		-- design: ults.js:3 ("Gaps between birdies open past ~30 st, so strafing between lanes beats it at range.")
		flockVolley = {
			name = "Flock Volley",
			incoming = "Flock Volley incoming!",
			ready = "Flock Volley ready",
			description = "Throws 3 Birdies in a fan. Each one that hits takes a life. Far away the gaps open, so strafe between them.",
		},
		-- design: ults.js:4 ("Jump over it or step out of the lane. The sprinkle trail is cosmetic.")
		sprinkleRoller = {
			name = "Sprinkle Roller",
			incoming = "Sprinkle Roller incoming!",
			ready = "Sprinkle Roller ready",
			description = "Rolls a giant Donut down a wide lane. Touching it takes a life. Jump over it or step out of the lane.",
		},
		-- design: ults.js:5 ("Every drop casts a shadow first; walk out of the zone.")
		rainCheck = {
			name = "Rain Check",
			incoming = "Rain Check incoming!",
			ready = "Rain Check ready",
			description = "A rain cloud parks over your opponent and drops 5 raindrops. Each drop casts a shadow first, so walk out of the zone.",
		},
		-- design: ults.js:6 ("Slow and very visible: back off or bait the early pop."). Bubble Pop bounce (2026-10-16):
		-- the design's "bounces once" (ults.js:6) off cover.
		bubblePop = {
			name = "Bubble Pop",
			incoming = "Bubble Pop incoming!",
			ready = "Bubble Pop ready",
			description = "Sends a slow bubble that bounces off cover once, then pops with a big splash when it touches someone, hits cover again or after a moment. Back off or make it pop early.",
		},
	},

	-- Throws / hits / accuracy (duel result and practice panel).
	stats = {
		throws = "Throws",
		hits = "Hits",
		accuracy = "Accuracy",
	},

	-- Loss-streak tip buttons (§6.13). The tip text is `duel.lossTip`.
	tip = {
		showWay = "Show me the way",
		dontShow = "Don't show tips",
	},

	-- Rarity names (§0.3 #3). Always shown with pips and colour too (§4.3).
	rarity = {
		common = { name = "Common", label = "COMMON" },
		uncommon = { name = "Uncommon", label = "UNCOMMON" },
		epic = { name = "Epic", label = "EPIC" },
		exclusive = { name = "Exclusive", label = "EXCLUSIVE" },
		ultimateBadge = "Ultimate",
	},

	-- Squishy names (§0.3 #2). Catalog `nameKey` = "squishy.<camelId>.name".
	squishy = {
		kittyBread = { name = "Kitty Bread" },
		toast = { name = "Toast" },
		banana = { name = "Banana" },
		butter = { name = "Butter" },
		chocolate = { name = "Chocolate" },
		bird = { name = "Birdie" },
		donut = { name = "Donut" },
		dragon = { name = "Dragon" },
		-- The squishy overhaul's 6 new squishies (spec 2026-10-09 §3.3).
		bobaBear = { name = "Boba Bear" },
		pancakePup = { name = "Pancake Pup" },
		mochiFox = { name = "Mochi Fox" },
		strawberryFrog = { name = "Strawberry Frog" },
		cloudBunny = { name = "Cloud Bunny" },
		cupcakeAxolotl = { name = "Cupcake Axolotl" },
		-- Squishies, Shop and Inspect: what a squishy multiplies (progression spec §3, §6; pens3 phase 1: in the pen).
		-- {n} = its power (Catalog.getPower).
		power = "x{n} power",
		powerNote = "Pen Coins multiplier",
	},

	-- Trail names, keyed by SquishyDef.visuals.trail (§4.2, §4.3, §10.8).
	trail = {
		label = "Trail: {name}",
		none = "No trail",
		ribbon = "Ribbon",
		twinRibbon = "Twin ribbon",
		comet = "Comet",
		ember = "Ember comet",
	},

	-- Elimination effect names (§9.9). `epic_pending` shows Standard until the Epic effect ships.
	elimination = {
		standard = "Standard",
		-- Kill banners 2026-10-16 (Art/KillStyle): each squishy above Uncommon has its own kill banner, kill sounds and
		-- kill effect.
		feather_storm = "Feather Storm",
		sprinkle_blast = "Sprinkle Blast",
		cloudburst = "Cloudburst",
		bubble_burst = "Bubble Burst",
		dragon_blaze = "Dragon's Blaze",
	},

	-- Inspect (§10.7, §10.8, §10.9, §10.6).
	inspect = {
		preview = "Preview only. Squeeze in the lobby to earn Coins.", -- spec 2026-10-11 §5 (squeeze anywhere)
		previewNotOwned = "Preview · Not owned", -- foam fix batch: sentence case like the other chips (was all caps)
		stat = {
			speed = "Speed",
			size = "Size",
			reload = "Reload",
			windup = "Windup",
			arc = "Arc",
		},
		statsCaption = "compared with other squishies",
		statsHint = "Shorter Reload and Windup throw sooner.", -- UI overhaul: the time bars show the value, not "better"
		statValue = "{value} {unit}",
		unit = {
			studsPerSecond = "studs/s",
			studsPerSecondSquared = "studs/s²",
			studs = "studs",
			seconds = "s",
		},
		ultimate = "Ultimate: {name}. {description}",
		elimination = "Elimination: {name}",
		howToGet = "How to get",
		boxChance = "{box}: {percent}%",
		shopPrice = "Shop: {price} Coins",
		viewInShop = "Buy", -- owner 2026-10-22: opens the Squishies screen on the squishy (its coin BUY)
		resetView = "Reset View",
		closeHint = "Close: Backspace / B",
		equippedToast = "Equipped!",
		equipFailed = "Couldn't equip. Try again.",
	},

	-- The knead screen in Inspect (spec phase2-squeeze §1.17-§1.19; design: the FP page html:95, fp.js:555-577, 701 and
	-- sd/squish.js:29-32, 41-48). {n} = a count; panelRow fills {row} (squeezeRow / coatRow), {label} and {note} (a feel
	-- or coat below) into a rich-text line. Reading: the coat notes speak to players, so foam's drops the design's "like
	-- your butter clip" (user to confirm); the help lines are the design's (fp.js:577) for this screen's own keys. User
	-- 2026-10-12: with the wax crunch off (Config.Wax.enabled) the thumbs press: thumbPress and helpNoWax replace
	-- thumbCrunch and help, and the wax texts (waxCoat, state, cracks, rewax, coatRow, coat) wait for the wax to come back.
	knead = {
		waxCoat = "Wax coat", -- design: html:95
		state = { crunchy = "Crunchy", crackled = "Crackled", soft = "Soft" }, -- design: fp.js:701
		cracks = { one = "{n} crack", many = "{n} cracks" }, -- design: fp.js:701
		thumbCrunch = "Thumb crunch", -- design: fp.js:557
		thumbPress = "Thumb press", -- user 2026-10-12: the thumb hold with the wax off
		rewax = "Re-wax", -- design: fp.js:559
		squeezeRow = "Squeeze", -- design: fp.js:569
		coatRow = "Coat", -- design: fp.js:570
		panelRow = "{row}: <b>{label}.</b> {note}",
		feel = {
			foam = {
				label = "Slow-rise foam",
				note = "Lumps and finger trails hold, then creep back over ~2 s. Drag off the edge to stretch it.",
			}, -- design: squish.js:29
			mochi = { label = "Stretchy mochi", note = "Stretches furthest and keeps a little of every pull." }, -- squish.js:30
			jelly = { label = "Jelly bounce", note = "Springs straight back and wobbles." }, -- design: squish.js:31
			plush = {
				label = "Plush stuffing",
				note = "Soft dents with folds, a gentle stretch, medium recovery.",
			}, -- design: squish.js:32
		},
		coat = {
			foam = {
				label = "Crunchy wax coat",
				note = "Wax-dipped: every bend cracks it with a dry crackle and fine lines spread from your thumbs. Keep kneading and it wears soft.",
			}, -- design: squish.js:41 (without "like your butter clip")
			mochi = {
				label = "Glossy wax coat",
				note = "A thin, shiny shell: finer cracks, crisper and a little higher than the butter.",
			}, -- design: squish.js:43
			jelly = {
				label = "Candy-glass shell",
				note = "A brittle candy shell over jelly: bigger shards, bright glassy ticks, then it wobbles.",
			}, -- design: squish.js:45
			plush = {
				label = "Soft wax coat",
				note = "Wax over fuzz: a muffled, lower crunch that wears soft quickly.",
			}, -- design: squish.js:47
		},
		-- The caption under the stage while kneading, per input (design: fp.js:577, with this screen's keys).
		help = {
			keyboard = "Drag it to knead, off its edge to stretch · hold F to crunch, Q to squeeze · W re-waxes",
			touch = "Drag it to knead, off its edge to stretch · hold Thumb crunch or Squeeze",
			gamepad = "Hold X to crunch, LB to squeeze · RB re-waxes · Y faces it front",
		},
		-- User 2026-10-12: the caption with the wax crunch off (no crunch, no re-wax).
		helpNoWax = {
			keyboard = "Drag it to knead, off its edge to stretch · hold F to press with your thumbs, Q to squeeze",
			touch = "Drag it to knead, off its edge to stretch · hold Thumb press or Squeeze",
			gamepad = "Hold X to press with your thumbs, LB to squeeze · Y faces it front",
		},
	},

	-- Squishies screen (§11.6). {rarity} = a rarity name. Badges and buttons use common.equipped / common.equip; Equip
	-- results use inventory.equippedToast / inspect.equipFailed; loading uses common.loading and a data error
	-- data.loadFailed.
	inventory = {
		-- Reading: the screen title (the HUD button says the same).
		title = "Squishies",
		filterAll = "All",
		collected = "Collected {n}/{total}",
		empty = "No {rarity} squishies yet.",
		new = "NEW",
		-- UI FINAL R5 (the design's Squishies window; `H:n` = "Squishy Duels HUD.dc.html" line n): the switch's two
		-- lines (H:196), the header pill (H:186-188), the locked squishy's button (H:247), the Ultimate chip (H:1013),
		-- the equip toast with the squishy's name (H:846), and each squishy's throw style by Catalog id (hud-lib.js
		-- lines 20-33, the design's toys matched by name).
		showLockedLines = "Show\nlocked",
		collectedLabel = "Collected",
		collectedCount = "{n} / {total}",
		goToBoxes = "Find in Boxes",
		ultimateChip = "Ultimate: {name}",
		equippedToast = "Equipped {name}!",
		throwStyle = {
			kitty_bread = "Overhand fastball",
			dragon = "Two-hand chest shove",
			bird = "Two-hand launch, glides",
			cloud_bunny = "Floaty lob",
			cupcake_axolotl = "Wobble lob",
			donut = "Sidearm wheel spin",
			butter = "Skipping-stone slide",
			chocolate = "Sidearm frisbee",
			mochi_fox = "Slingshot stretch",
			strawberry_frog = "Bounce pass",
			banana = "Football spiral",
			boba_bear = "Underhand lob",
			toast = "Sidearm card-flick",
			pancake_pup = "Frisbee flick",
		},
	},

	-- Inline two-step spend confirmation (§11.5).
	spend = {
		confirm = "Confirm: {price} Coins",
		balanceAfter = "Balance after: {balance}",
	},

	-- Boxes: names (Boxes `nameKey`), signs, odds disclosure, open flow and reveal (§6.4, §6.10, §7.7, §9.11).
	box = {
		snack = { name = "Soft Box" }, -- owner 2026-10-15 "Keep all": Soft / Sweet / Royal (ids kept)
		sweet = { name = "Sweet Box" },
		treat = { name = "Royal Box" },
		-- Readings (Part 7; DESIGN implies these texts but never words them): the Boxes screen title; the Treat Box
		-- row's note in place of Open (day = Config.Economy.Daily.freeBoxDay, worded like box.restrictedNote; Strings_Test
		-- checks they agree); the in-world odds board's heading ({box} = a box name, {cost} = Format.coins of its cost)
		-- and one line per item ({name}, {rarity} = rarity name, {percent} = Boxes.percentText, e.g. "32.00").
		title = "Squishy Boxes",
		freeOnly = "Free on day 7 of Daily Rewards",
		boardHeader = "{box}: {cost} Coins",
		boardLine = "{name} ({rarity}): {percent}%",
		-- Spec 2026-10-09 §3.3: one board line for a rarity whose items share one weight ({total} = the rarity's
		-- chance, {each} = each item's, {names} = the names joined with boardNameSeparator).
		boardGroupLine = "{rarity} {total}% — {each}% each: {names}",
		boardNameSeparator = ", ",
		standTitle = "SQUISHY BOXES",
		standSubtitle = "Odds are listed before you open",
		oddsTitle = "Box Odds",
		restrictedNote = BOX_RESTRICTED_TEXT,
		unknownNote = BOX_UNKNOWN_TEXT,
		openButton = "Open: {cost} Coins",
		checkingButton = "Checking…",
		chancesByRarity = "Chances by rarity: {list}",
		rarityChance = "{rarity} {percent}%",
		listSeparator = " · ",
		insideHeading = "What's inside & chances",
		total = "Total: {percent}%",
		footer = "Chances are the same for every player and never change. A squishy you already own is one more copy for your pen.",
		-- Pens3 phase 5: a fixed-order box's next squishy ({name} = its name), shown before you open (D1:235).
		nextItem = "Next in this box: {name}",
		details = "Details: items & chances",
		needCoins = { one = "You need {missing} more Coin", many = "You need {missing} more Coins" },
		howToEarn = "How to earn Coins",
		stillChecking = "Still checking your box…",
		revealNew = "NEW!",
		-- UI FINAL R7 (`H:n` = "Squishy Duels HUD.dc.html" line n): the duplicate line (H:492; pens3 phase 5: a copy
		-- for the pen, no Coins), the band's subtitle (H:260), OPEN (H:277), the hints (H:484, H:495) and the result
		-- buttons (H:498-499).
		revealDuplicate = "Already in your collection",
		subtitle = "Every box can hold a new squishy",
		open = "Open",
		tapToOpen = "Tap the box to open it!",
		dragHint = "Drag to spin · Scroll to zoom",
		again = "Again",
		nice = "Nice!",
	},

	-- Shop (§6.6, §6.11, §7.7, §11.6). Robux prices only come from GetProductInfoAsync.
	shop = {
		title = "SHOP",
		subtitle = "Squishies for Coins",
		tabSquishies = "Squishies",
		tabCoins = "Coins",
		buy = "Buy",
		success = "You got {name}!",
		equipNow = "Equip now",
		coinsUnavailable = "Coin packs aren't available yet. Robux purchases are turned off.",
		robuxLoading = "…",
		robuxUnavailable = "Unavailable",
		robuxPrice = "{price} Robux",
		-- UI FINAL R6 (the Shop window; `H:n` = "Squishy Duels HUD.dc.html" line n): the section heads (H:315, H:329),
		-- the featured line (H:309; {rarity} = a rarity name, {power} = the squishy's power), OWNED (H:311),
		-- the phone's way back from the featured card to the list, and the congrats overlay (H:539-547).
		sectionSquishies = "SQUISHIES",
		sectionCoins = "COINS",
		featuredLine = "{rarity} · x{power} power",
		owned = "OWNED",
		back = "Back",
		congratsTitle = "CONGRATULATIONS!",
		youGot = "You got",
		awesome = "AWESOME!",
		-- Pens3 phase 5 (D1:202): the first of each Common you don't own yet ({coins} = Format.coins of the Welcome
		-- price); it never runs out.
		welcomePrice = "Welcome price: first one {coins}",
		-- The shop = Diego's design exactly (owner 2026-10-22; `H:n` = his HUD file, lib = his hud-lib.js):
		-- GAME PASSES (H:338), the Dragon Bundle card (H:321, H:331-332: LIMITED, the name, "Exclusive Dragon +" before
		-- the coin and the amount; endsIn only for a real offer, {time} = Format.clock), BEST (H:357), his 4 passes
		-- (lib:51-54), and `soon`: the price of anything with no Robux product yet (the owner creates them).
		sectionPasses = "GAME PASSES",
		limited = "LIMITED",
		endsIn = "Ends in {time}",
		bundleName = "DRAGON BUNDLE",
		bundleLine = "Exclusive Dragon +",
		best = "BEST",
		soon = "Soon",
		comingSoon = "Coming soon!", -- a tap on a price that has no Robux product yet
		passes = {
			coins2 = { name = "2x Coins", desc = "Double coins from every squeeze." },
			grip2 = { name = "2x Grip", desc = "Double Grip from every squeeze." },
			lucky = { name = "Lucky Boxes", desc = "Epic and Exclusive odds ×1.5." },
			fast = { name = "Fast Open", desc = "Skip the shake, reveal instantly." },
		},
	},

	-- Coin bundle names (Config.Monetization.CoinBundles `nameKey`, §6.11).
	bundle = {
		handful = "Handful of Coins",
		jar = "Jar of Coins",
		tin = "Tin of Coins",
		barrel = "Barrel of Coins",
	},

	-- Quests and starter tasks (§6.8, §11.6). Templates take {n} (goal) and {squishy} (a squishy name).
	quest = {
		title = "QUESTS", -- the world board's sign (§7.7); the Quests screen's tab reads panelTitle
		panelTitle = "Quests", -- foam fix batch: title case like every other screen's header tab
		section = {
			daily = "Daily",
			weekly = "Weekly", -- the weekly quests' tab (H:959)
			starter = "Starter",
		},
		inProgress = "In progress",
		swap = "Swap",
		complete = "Quest complete! Claim your reward.",
		completeTag = "QUEST COMPLETE", -- UI FINAL R9 (H:162): the quest pop's tag over the quest's title
		autoCollected = "Quest reward collected",
		-- UI FINAL R8 (the design's reset pill, H:359, H:1027): {clock} is "{h}h {MM}m", or "m:ss" in the last hour.
		footer = "Resets in {clock}",
		empty = "No quests right now. Check back in {time}.",
		progress = "{progress} / {goal}", -- UI FINAL R8: a quest row's "x / y" (H:956)
		go = "Go", -- UI FINAL R8: GO (H:371; the button shows it in capitals, Q5)
		-- UI FINAL R8 (GO on a squeeze quest, H:750): the toast after the window closes; the key is the lobby squeeze's
		-- on keyboard / gamepad, none on touch.
		goSqueeze = "Squeeze your squishy! Press {key}",
		goSqueezeTouch = "Squeeze your squishy!",
		-- Keyed by daily quest template id (camelCase of `squeeze_any`, ...).
		template = {
			squeezeAny = { one = "Squeeze squishies once", many = "Squeeze squishies {n} times" },
			squeezeWith = { one = "Squeeze {squishy} once", many = "Squeeze {squishy} {n} times" },
			duelFinish = { one = "Finish {n} duel", many = "Finish {n} duels" },
			duelWin = { one = "Win {n} duel", many = "Win {n} duels" },
			duelWinWith = { one = "Defeat {n} player using {squishy}", many = "Defeat {n} players using {squishy}" },
			hitsWith = { one = "Land {n} hit with {squishy}", many = "Land {n} hits with {squishy}" },
			practiceHits = { one = "Hit {n} practice target", many = "Hit {n} practice targets" },
		},
		-- Keyed by starter task id (`starter_squeeze` -> squeeze, ...). QuestDefs `textPair` names the pair.
		starterTask = {
			squeeze = { one = "Squeeze once", many = "Squeeze {n} times" },
			practice = { one = "Hit {n} practice target", many = "Hit {n} practice targets" },
			duel = { one = "Finish your first duel", many = "Finish {n} duels" },
		},
	},

	-- Batch 3 (review #10): the Roblox player list's columns (leaderstats, ShowOffService), in this order.
	social = {
		statWins = "Wins",
		statLevel = "Grip Lv",
		statIncome = "Coins/s", -- qb1 (owner 2026-10-15): the pen's Coins a second
	},

	-- Batch 3 (review #10): "Top Wins This Week" in the Quests screen (ShowOffService's weekly board, UI/QuestFormat).
	-- Only fully paid wins over other players count; the board starts over every Monday.
	board = {
		title = "Top Wins This Week",
		line = { one = "{rank}. {name} · {wins} win", many = "{rank}. {name} · {wins} wins" },
		empty = "No wins yet this week. Be the first!",
		loading = "Checking the board…",
		unavailable = "The board is taking a break. Check back soon!", -- no read has worked yet (the server's store)
		someone = "A player", -- a name the server could not look up
		you = { one = "You: #{rank} · {n} win", many = "You: #{rank} · {n} wins" },
		youUnranked = { one = "You: {n} win this week", many = "You: {n} wins this week" },
		youNone = "Win a duel against another player to get on the board!",
	},

	-- Daily rewards (§6.9, §7.7, §11.6).
	daily = {
		title = "DAILY REWARD", -- the world sign (§7.7); the Daily screen's tab reads panelTitle
		-- UI FINAL R3: the design's "DAILY REWARDS" (H:386; the band shows its title in capitals, Q5)
		panelTitle = "Daily Rewards",
		ready = "Ready to claim!",
		wait = "Next reward in {time}",
		popup = "Daily reward ready",
		dayLabel = "Day {n}",
		comeBack = "Come back in {time}",
		-- Review quick win 2026-10-14: a missed day pauses the streak (never back to Day 1); the Daily panel and the join
		-- toast greet a returning player with the day that is waiting ({n} = that day).
		welcomeBack = "Welcome back! Day {n} is waiting.",
		treatBox = "Royal Box", -- foam fix round 2: "Free Treat Box" wrapped onto a third line on the 84 px day card
		-- Reading (Part 7; §11.6 "today highlighted" gives no text): the label on today's day card.
		today = "Today",
		-- UI FINAL R8 (the design's Daily window): the timer pill while a reward waits (H:1029; `ready` stays the world
		-- sign's, `wait` is the pill's other line), the CLAIM! chip (H:402), the next day's tag (H:403), the day 7 pill
		-- (H:409) and day 7's foot (H:964: Claimed = common.claimed / Claim! / Tomorrow = `tomorrow` / Locked).
		readyNow = "Your reward is ready!",
		claimTag = "CLAIM!",
		tomorrow = "Tomorrow",
		megaReward = "MEGA REWARD",
		footClaim = "Claim!",
		footLocked = "Locked",
	},

	-- Settings (§11.6). Keys match profile.settings fields.
	settings = {
		title = "Settings",
		music = "Music",
		sfx = "Sound effects",
		cameraShake = "Screen shake", -- UI FINAL R9 (H:979)
		showTips = "Show tips",
		firstPerson = "First-person duels", -- session switch, never saved (first-person spec 2026-10-10 §3.8)
		replayTutorial = "Replay tutorial",
		noMusic = "No music yet",
		noSfx = "No sound effects yet",
		-- UI FINAL R9 (H:979, H:442; Q6): the Reduced motion switch (a session switch, UiPrefs) and the volume row.
		reducedMotion = "Reduced motion",
		volume = "Volume",
	},

	-- Onboarding card (§11.8). Keyed by step id. {goal} = the cheapest shop price from the Catalog (Batch 1).
	onboarding = {
		welcome = "Welcome to Squishy Duels! Your first squishy is {starterName}.",
		-- Spec 2026-10-11 §5 (squeeze anywhere); Phase 5: a pad no longer boosts a squeeze (capsules set its pay).
		squeeze = "Squeeze squishies anywhere to earn Coins. {squeezeHint}.",
		-- Pens3 phase 1: the pen step (the first pen spot bought at the sign; it replaced Batch 1's capsule step).
		pen = "Your squishies earn Coins in your pen. Buy more pen space at the sign!",
		-- Pens3 phase 5: {goal} = the cheapest Welcome price (3K; V4:161 points new players to the cheap Commons).
		firstBox = "Get a new squishy in the Shop: your first of each Common has a Welcome price! {coins}/{goal} Coins",
		-- Lobby HUD spec 2026-10-11 §2: Inspect is in the Squishies screen now (no equipped card). Batch 1: it follows
		-- the capsule card, so it names the squishy.
		inspect = "Open Squishies, press Inspect to see your squishy in 3D. Spin it, then try Squeeze.",
		duel = "Ready? Step up to the Duel Gate to find an opponent.",
		done = "You're all set! Daily rewards and quests are in the menu.",
		skip = "Skip tutorial",
		-- {squeezeHint}, chosen from UserInputService.PreferredInput. It starts a sentence (spec 2026-10-11 §5; lobby HUD
		-- spec §2: a click or a tap on the world squeezes, there is no Squeeze button).
		squeezeHint = {
			keyboard = "Click or press E",
			touch = "Tap the screen",
			gamepad = "Press X",
		},
	},

	-- ProximityPrompt action texts at the lobby stands (§7.6, §7.7).
	prompt = {
		joinQueue = "Join 1v1 Queue",
		leaveQueue = "Leave Queue",
		seeBoxes = "See Boxes",
		shopDirect = "Shop Squishies",
		openShop = "Open Shop",
		openCollection = "Open Collection",
		viewQuests = "View Quests",
		dailyReward = "Daily Reward",
		inspect = "Inspect",
	},

	-- World signs (`SD_TextKey`, §7.7).
	world = {
		-- The design lobby's plates (phase 3, user decision 2026-10-11 "build the design's lobby"; D10: the design's
		-- words, sd/lobby.js). The plates that say "SHOP", "QUESTS" and "Kitty Bread" use shop.title, quest.title and
		-- squishy.kittyBread.name.
		logoTop = "Squishy", -- lobby.js:153
		logoBottom = "Duels", -- lobby.js:153
		squishSquare = "SQUISH SQUARE", -- lobby bases spec §2: the hub's name painted on the ground
		gateBadge = "DUELS", -- lobby.js:184
		teamMint = "MINT", -- lobby.js:196
		teamStrawberry = "STRAWBERRY", -- lobby.js:196
		mysteryBox = "?", -- lobby.js:216
		collectionKiosk = "Collection", -- lobby.js:276
		questsDaily = "Daily", -- lobby.js:296 (the quest board's column heads)
		questsWeekly = "Weekly",
		questsDuels = "Duels",
		number = "{n}", -- lobby.js:326, 348: the calendar's days and the foam mats' numbers ({n} = 1..7 / 1..6)
		practiceBoard = "PRACTICE", -- lobby.js:418
		practiceNoCoins = "no duel coins", -- lobby.js:418
		spawnLogo = "SQUISHY DUELS",
		spawnSafe = "Safe zone: duels happen in the arena",
		duelGateTitle = "DUEL ARENA",
		duelGateSubtitle = "1v1 duels • Queue at the pad",
		squeezeTitle = "SQUEEZE ZONE",
		squeezeSubtitle = "Squeeze your squishy to earn Coins",
		-- The design arenas' prop signs (phase 4 spec 2026-10-11, Arcade Toyworks: sd/arenas2.js:196, 220, 241, 251).
		arenaPlay = "PLAY",
		arenaToyworks = "TOYWORKS",
		arenaPrizes = "PRIZES",
	},

	-- The island's bases (lobby bases spec 2026-10-11 §4, §9; build plan Phase 4): the gate's name sign (BaseService
	-- writes the owner's display name, or openPlot).
	base = {
		openPlot = "OPEN PLOT", -- Neon Sugar part 4: Diego's arch nameplate text
	},

	-- The pen (pens3 phase 1): the PEN SPACE sign on the fence (its title, the owner's own state line under the price),
	-- the sign's ProximityPrompt and the coin label over each walking squishy. {coins} = Format.coins amounts.
	pen = {
		sign = {
			title = "PEN SPACE",
			canBuy = "Walk up to buy",
			needMore = "Need {coins} more",
			max = "MAX",
		},
		prompt = {
			action = "Buy",
			object = "Pen space",
		},
		-- Pens3 phase 11: the SHELF SPOTS sign (P3D:255; its can buy / need more / MAX lines are pen.sign's) and its
		-- prompt.
		shelfSign = {
			title = "SHELF SPOTS",
		},
		shelfPrompt = {
			action = "Buy",
			object = "Shelf spots",
		},
		-- Neon Sugar part 4: Diego's pen board (World/PenBoard): the next count after the arrow ({n}), the progress
		-- ({n} of {total}) and the button's caption.
		board = {
			spots = "{n} spots",
			progress = "{n}/{total}",
			buy = "BUY",
		},
		rate = "+{coins}/s",
		-- Pens3 phase 10: the base gate (lobby design v6, P3D:250 and :277): the line under the owner's name on the
		-- owner sign ({n} the base number) and the visitor board's heart and count ({count} the visitors who squeezed
		-- today; 0 until phase 18).
		gate = {
			base = "BASE {n}",
			heart = "\u{2665}",
			visitor = "{count} visitor",
			visitors = "{count} visitors",
		},
		-- Pens3 phase 6: the stand-in pen screen (PenController, UI/PenScreen; Diego draws the real one). {placed} /
		-- {spots} the squishies in the pen and its open spots, {toys} / {max} the Toy Box and its toyBoxMax, {name} a
		-- squishy's name, {level} its level.
		screen = {
			title = "MY PEN",
			count = "Pen {placed}/{spots} · Toy Box {toys}/{max}",
			penHeading = "In your pen",
			toyHeading = "Toy Box",
			empty = "Empty",
			toyEmpty = "Your Toy Box is empty.",
			selectHint = "Tap a squishy to move, lock, sell, fuse or feed it.",
			pickHint = "Tap a pen spot for {name}.",
			level = "Lv {level}",
			place = "PLACE",
			putAway = "PUT AWAY",
			move = "MOVE",
			swap = "SWAP",
			lock = "LOCK",
			unlock = "UNLOCK",
			open = "MY PEN", -- the Squishies window's button
			-- Pens3 phases 7-8: selling, the buy-back and fusion. {name} a squishy's name (formName for a Golden or
			-- Rainbow one: {form} = forms[form]), {coins} Coins, {n} how many, {minutes} Pen.buyBackSeconds in minutes
			-- (rounded up), {result} the fused squishy's name, {level} its level, {rate} its "+N/s".
			sell = "SELL",
			holdSell = "HOLD TO SELL", -- Golden, Rainbow, Lv 10+ and Epic+ (Pen.sellHold)
			sellAll = "SELL ALL",
			buyBack = "BUY BACK",
			fuse = "FUSE",
			forms = { "Golden", "Rainbow" },
			formName = "{form} {name}",
			formLevel = "{form} · Lv {level}",
			confirmSell = "Sell {name} for {coins} Coins?",
			confirmSellAll = {
				one = "Sell {n} squishy for {coins} Coins?",
				many = "Sell {n} squishies for {coins} Coins?",
			},
			sellNote = "You can buy it back for {minutes} minutes.",
			sellAllNote = "Your pen, levelled, Golden, Rainbow and locked squishies stay, and one of each. You can buy them back for {minutes} minutes.",
			confirmBuyBack = "Buy back {name} for {coins} Coins?",
			soldHeading = "Sold (you can buy them back)",
			soldTime = "{minutes} min",
			confirmFuse = "Fuse 3 {name} into 1 {result}?",
			fuseNote = "It keeps the highest level, Lv {level}, and earns {rate}. Fusing is free and always works.",
			coatNote = "Their coatings go to your bag.",
			fused = "You made a {name}!",
			-- Pens3 phase 9: feeding and the stand-in BUY FOOD section. {level} / {next} the levels of a step, {pieces}
			-- its pieces, {food} a food's name, {missing} / {n} counts, {coins} Coins, {list} foodItem texts joined
			-- with ", ".
			feed = "FEED",
			feedAll = "FEED ALL",
			feedHint = "Lv {level} -> {next}: {pieces} {food}",
			feedTop = "Lv {level}: the top level for now.",
			needFood = "Need {missing} more {food}",
			foodHeading = "Buy food",
			foodLine = "Your food: {list}",
			foodNone = "Your food: none yet.",
			foodItem = "{n} {food}",
			foodEach = "{coins} each",
			foodHave = "You have {n}",
			foodBuyHint = "{food}: {coins} Coins each. You have {n}.",
			buyFood = "BUY {n}",
			foodNote = "Food inside: {coins} Coins, not refunded.", -- the sell confirm (D1:223)
			levelsUp = { one = "+1 level", many = "+{n} levels" },
			-- Pens3 phase 11: the shelf's open spots ({placed} / {open}) and the TOP spot, each its own section.
			shelfHeading = "On your shelf {placed}/{open}",
			topHeading = "TOP spot",
			-- Wb (owner 2026-10-17): the window's shelf BUY button, the SHELF SPOTS sign's buy ({coins} = its price).
			buySpot = "BUY {coins}", -- Neon Sugar part 5: one cubby a buy (short: "BUY 300.00M" fits the button)
			buyTop = "BUY TOP {coins}",
			shelfMax = "SHELF MAX",
		},
	},

	-- Pens3 phase 9: the foods (Config.Economy.Food nameKey; V2:216-224).
	food = {
		candyDrop = { name = "Candy Drop" },
		butterBun = { name = "Butter Bun" },
		bobaPearlPop = { name = "Boba Pearl Pop" },
		frostyScoop = { name = "Frosty Scoop" },
		lavaTruffle = { name = "Lava Truffle" },
		prismTart = { name = "Prism Tart" },
		haloPuff = { name = "Halo Puff" },
	},

	-- Pens3 phase 12: the highway (SDTools HighwayBuilder; WorldLayout.Highway names the keys). The lobby design v6's
	-- words: the biome names as its launch gate banner and arches show them (layout.json:33, :533, :616, :723, :895,
	-- :1130, :1397), the launch board's static lines ("Squishy Lobby 3D.html":285-286; LAST THROW and SERVER BEST are
	-- filled in phase 13) and the distance markers (P3D:275: {distance} = the grouped number, then "studs").
	highway = {
		biome = {
			candyMeadow = "CANDY MEADOW",
			bakeryTown = "BAKERY TOWN",
			bobaLagoon = "BOBA LAGOON",
			frozenDessertPeaks = "FROZEN DESSERT PEAKS",
			lavaVolcano = "LAVA VOLCANO",
			rainbowRoad = "RAINBOW ROAD",
			divineHeaven = "DIVINE HEAVEN",
		},
		board = {
			title = "LAUNCH BOARD",
			lastThrow = "LAST THROWS", -- pens3 phase 13: the last throws of everyone in the server (v6: LAST THROW)
			serverBest = "SERVER BEST",
			empty = "Walk up and throw!", -- pens3 phase 13: no throw yet (v6's "Step on a spot to throw!", P3D:286)
		},
		marker = {
			distance = "{distance}",
			unit = "studs",
		},
		-- Pens3 phase 13 (the server's board lines and the client's stand-in HUD; {distance} = Format.distance,
		-- {coins} / {grip} = Format.coins, {biome} = a biome name, {name} = a squishy's name, {food} = a food's name).
		studs = "{distance} studs",
		landed = "{distance} studs! +{coins} Coins, +{grip} Grip",
		newBest = "New best: {distance} studs!",
		reached = "You reached {biome}!",
		gift = { one = "{name} joined your pen!", many = "{count} {name} squishies joined your pen!" },
		foodBag = "Food Bag: +{count} {food}",
		-- P13v4 [P] the throw screen (HighwayHud, the video's flight HUD; {n} = the zone's number 1..7, {biome} = its
		-- name, {hit} / {total} = rings, {fuel} = boosts left): the zone line, the rings line, the PERFECT bar's label,
		-- the boost button's action by input and its fuel line ("SQUISH!" for the video's "QUACK!").
		screen = {
			zone = "Zone {n} • {biome}",
			rings = "RINGS {hit}/{total}",
			perfectZone = "PERFECT",
			boost = { touch = "Tap to boost!", mouse = "Click to boost!", gamepad = "Press R2 to boost!" },
			fuel = "SQUISH! x{fuel}",
			noFuel = "NO FUEL",
			-- Owner 2026-10-22 (Break and Steal an Egg's zone banner; Claude Design's banner, HighwayHud zoneBanner):
			-- the line under a new zone's name, its label and its value ({power} = the throw power the zone starts at,
			-- Config.Economy.Highway.walls), and the difficulty tags by zone (Design's DIFF).
			recommended = "Recommended:",
			recommendedValue = "{power} Throw Power",
			difficulty = { "EASY", "NORMAL", "TRICKY", "HARD", "EXTREME", "INSANE", "BRUTAL" },
		},
		-- P13v4 [P] the big pops ({distance} = Format.distance).
		pop = {
			perfect = "PERFECT!",
			boost = "SQUISH!",
			lastOne = "LAST ONE!",
			bullseye = "BULLSEYE!",
			rings = "{hit}/{total} RINGS",
			landed = "{distance} studs!",
			newBest = "NEW BEST!",
		},
	},

	-- Coins while away (pens3 phase 4): the pop-up's line under the Coins (PenController; a stand-in on the shop's
	-- congrats overlay). {time} = hours / hoursMinutes / minutes / underMinute, {h} and {m} whole hours and minutes.
	-- A gift, not a deal: no countdown and nothing to claim (the Coins are already in the pill).
	away = {
		body = "Your pen kept earning while you were away ({time}).",
		hours = "{h} h",
		hoursMinutes = "{h} h {m} min",
		minutes = "{m} min",
		underMinute = "less than a minute",
	},

	-- Collection display (§7.6, §7.7).
	collection = {
		title = "MY COLLECTION",
		owned = "Owned",
		notOwned = "Not owned yet",
	},

	-- Grip training (§17.6, §17.7), a lobby-only stat. Never shown in duels: the client holds grip.* toasts back from
	-- Matched to Returning, and no duel text mentions it. Placeholders: {level} = a Grip Level (a rank's
	-- Config level, or the player's); {rank} = a grip.rank.* name;
	-- {coins} = a Coin amount (Coins per squeeze); {grip} = Grip
	-- per squeeze (PenMath.squeezeGrip); {mult} = a multiplier (Rested.mult);
	-- {minutes} = GripMath.restedMinutes; {n} = Grip gained. On the HUD bar {have}/{need} = Format.coins of the total
	-- and of the next level's total (GripMath.progress).
	-- Phase 5: pads and trainers no longer boost a squeeze (PenMath sets its pay); Phase 6: slow training is gone,
	-- and so are the trainers (their names, card, goal, toast and reason texts) and the giant pads and Jelly gates (the
	-- pad cards, signs, unlock toast and pad goal); grip.pad.foam names the Foam Mats' Config.Grip.Pads row.
	grip = {
		-- HUD card (top-left, under the Coins pill).
		hudLevel = "Grip Lv {level} · {rank}",
		hudLevelCompact = "Lv {level} · {rank}",
		hudBar = "{have} / {need} Grip",
		hudMax = "Max level",
		-- Foam restyle (spec 2026-10-09): the small label over the level number on the regular card's level tile.
		levelTag = "GRIP",
		restedChip = "Double Grip: about {minutes} min",
		-- Next goal (GripMath.nextGoal, first that applies).
		goalRank = "Next rank: {rank} at Grip Lv {level}",
		goalMax = "Max level! You've reached Infinite Grip.",
		-- Pens3 phase 1: the pen goal (GripMath.nextGoal step 0 while spots < 12; it replaced Batch 1 #7a's capsule
		-- goals). {need} = Format.coins of the next spot's price (GripController.goalArgs). Short (at
		-- most 21 characters), so the HUD card needs no short form.
		goalPen = "Next: pen space {need}",
		goalPenReady = "Buy pen space · READY!",
		-- Foam fix 2: the regular HUD card's goal line (one line in its info column); the panel and toasts keep the above.
		hudGoalRank = "Next: {rank} at Lv {level}",
		-- At a pad.
		popup = "+{n} Grip",
		popupDouble = "+{n} Grip (x{mult})",
		-- The floating label on the held squishy (lobby HUD spec 2026-10-11 §2): what one squeeze pays, the same anywhere
		-- (Phase 5: the squeeze value and its Grip, the pen's since pens3 phase 1; no pad name).
		stationLabelBase = "+{coins} Coins · +{grip} Grip per squeeze",
		-- Lobby HUD spec §2: there is no Squeeze button to press any more.
		holdPaused = "Squeeze again to keep training.",
		-- Keyed by Config.Grip.Ranks[i].key.
		rank = {
			soft = "Soft Grip",
			firm = "Firm Grip",
			strong = "Strong Grip",
			iron = "Iron Grip",
			titan = "Titan Grip",
			master = "Squish Master",
			-- Spec 2026-10-12 §10: the ranks above Lv 50.
			legend = "Legend Grip",
			mythic = "Mythic Grip",
			cosmic = "Cosmic Grip",
			galaxy = "Galaxy Grip",
			infinite = "Infinite Grip",
		},
		-- Keyed by Config.Grip.Pads[tier].key.
		pad = {
			foam = "Foam Mats",
		},
		-- Grip panel (one scrolling column).
		panelTitle = "Grip Training",
		panelIntro = "Squeezing trains your Grip and earns Coins.", -- pens3 phase 1: no capsule tiers any more
		restedHelp = "Double Grip fills up over time, even while you're away. While it lasts, each squeeze trains x{mult} Grip.",
		-- Spec 2026-10-11 §5: no hourly limit any more; the note says where squeezing pays.
		limitNote = "Squeezing earns Coins and trains Grip, anywhere in the lobby.",
		duelNote = "Grip only helps in the lobby. It never changes duels, and it can't be bought.",
		-- Toasts (Notify codes, Types.GripNotifyCode). rankUp: {name} = the player's display name.
		levelUp = "Grip Lv {level}!",
		rankUp = "{name} reached {rank}!",
		-- UI FINAL R9 (H:527, H:530-531, H:999): the level-up show's ribbon, pill and unlock line.
		levelUpRibbon = "GRIP LEVEL UP!",
		levelFrom = "Grip {from}",
		levelArrow = "→",
		unlockedPrefix = "Unlocked ",
		intro = "You trained your Grip! Squeeze more to level it up.",
		welcome = "Double Grip is full: your first squeezes train x{mult} Grip!",
		welcomeBack = "Welcome back! Double Grip: about {minutes} min.",
		headStart = "Your past squeezes count: you start at Grip Lv {level}!",
		-- Idle card (LocalPlayer.Idled after Config.Grip.idleReminderSeconds). The 20 minutes are Roblox's idle kick,
		-- not a game setting.
		idleTitle = "Still there?",
		-- Foam fix 2: one sentence per line. Pens3 phase 1: the second names what still stops (the pen).
		idleBody = "Roblox disconnects players who are idle for 20 minutes.\nYour pen stops paying when that happens.",
		idleButton = "Keep going",
		-- World: the lobby nameplate.
		nameplate = "Lv {level} · {rank}",
	},

	-- Practice bot (2026-10-16): the name word lists (see the header).
	bot = {
		nameStarts = {
			"Squish",
			"Bouncy",
			"Mochi",
			"Pudding",
			"Bubble",
			"Sprinkle",
			"Puffy",
			"Gummy",
			"Cocoa",
			"Cookie",
			"Noodle",
			"Pickle",
			"Waffle",
			"Biscuit",
			"Fluffy",
			"Sunny",
			"Comet",
			"Pixel",
			"Boba",
			"Taffy",
			"Doodle",
			"Sparkle",
			"Muffin",
			"Peachy",
			"Berry",
			"Toffee",
			"Squeaky",
			"Wobbly",
		},
		nameEnds = {
			"Fan",
			"King",
			"Queen",
			"Star",
			"Pro",
			"Kid",
			"Hero",
			"Champ",
			"Boss",
			"Buddy",
			"Pal",
			"Ace",
			"Wiz",
			"Bean",
			"Bun",
			"Pop",
			"Zoom",
			"Toss",
			"Ninja",
			"Master",
			"Legend",
			"Panda",
			"Fox",
			"Bear",
			"Cat",
			"Pup",
		},
	},
}

-- Codes that already produced a warning (warn once per code).
local warnedCodes: { [string]: boolean } = {}

local function deepFreeze(value: any)
	if type(value) ~= "table" or table.isfrozen(value) then
		return
	end
	for _, child in value do
		deepFreeze(child)
	end
	table.freeze(value)
end

-- Replaces every `{name}` with tostring(args[name]). Placeholders without a value are kept as they are.
function Strings.format(template: string, args: FormatArgs?): string
	if args == nil then
		return template
	end
	local values: FormatArgs = args
	local result = string.gsub(template, "{(%w+)}", function(name: string): string
		local value = values[name]
		if value == nil then
			return "{" .. name .. "}"
		end
		return tostring(value)
	end)
	return result
end

-- Picks the singular or plural template. Format it afterwards with the same count.
function Strings.plural(n: number, one: string, many: string): string
	return if n == 1 then one else many
end

-- Looks up a dotted key ("queue.searching"). Returns nil if it is missing or not a text.
function Strings.resolve(path: string): string?
	local node: any = Strings
	for segment in string.gmatch(path, "[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end
		node = node[segment]
	end
	return if type(node) == "string" then node else nil
end

-- Text for a server reason code (`reason.<code>`). A plain Strings key is accepted too, so Notify codes and
-- message keys go through one function. Unknown codes return `error.generic` and warn once.
function Strings.reasonText(code: string?): string
	if type(code) == "string" then
		local text = Strings.resolve("reason." .. code) or Strings.resolve(code)
		if text ~= nil then
			return text
		end
	end
	local label = if type(code) == "string" then string.sub(code, 1, MAX_LOGGED_CODE_LENGTH) else `<{typeof(code)}>`
	if not warnedCodes[label] then
		warnedCodes[label] = true
		warn(`[SD][Strings] Unknown reason code: {label}`)
	end
	return ERROR_TEXT.generic
end

deepFreeze(Strings)

return Strings
