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

export type FormatArgs = { [string]: any }

-- Shared texts (one definition, referenced from two keys).
local ERROR_TEXT = {
	generic = "Something went wrong. Please try again.",
	connect = "Couldn't connect to the game server. Please rejoin.",
}
local BOX_RESTRICTED_TEXT =
	"Coin boxes aren't available on your account. You can buy any squishy directly in the Shop, and day 7 of Daily Rewards gives a free Treat Box."
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
		},
		box = {
			restricted = BOX_RESTRICTED_TEXT,
			checking = "Checking box availability…",
			unknown = BOX_UNKNOWN_TEXT,
			complete = "You own every squishy in this box!",
			paused = "Boxes are paused while the server restarts soon.",
			saving = "Saving your collection…",
		},
		shop = {
			priceChanged = "The price changed. Please check it and try again.",
			notForSale = "This squishy isn't sold in the shop.",
			owned = "You already own this squishy.",
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
		-- Capsules (CapsuleUpgrade / CapsuleUnlock / CapsuleSet; lobby spec 2026-10-11 §6, Phase 3).
		capsule = {
			notNext = "Unlock the capsules in order.",
			locked = "Unlock this capsule first.",
			gripLocked = "Your Grip level is too low for the next capsule level.",
			maxLevel = "This capsule is at the top level.",
			priceChanged = "The price changed. Please check it again.",
			paused = "Upgrades are paused for a moment. Try again soon.",
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

	-- Lobby HUD (§11.6).
	hud = {
		nav = {
			squishies = "Squishies",
			boxes = "Boxes",
			shop = "Shop",
			quests = "Quests",
			daily = "Daily",
			duel = "Duel",
			settings = "Settings",
		},
		-- Foam restyle (spec 2026-10-09): the Duel CTA (top middle since the lobby HUD of 2026-10-11) and its queued state, which matches the queue
		-- pill's clock; {time} = m:ss since joining.
		duelCta = "DUEL",
		duelJoin = "Join the queue",
		duelQueued = "IN QUEUE",
		duelSearching = "Searching",
		duelSearchingTime = "Searching · {time}",
		-- The quest tracker card (top right): its label; the section name (quest.section.*) sits beside it.
		questTracker = "QUEST",
		questReady = "Ready to claim!", -- UI overhaul: the tracker's quest is done and not claimed
	},

	-- Touch / on-screen action buttons (§5.10, §6.3).
	controls = {
		throw = "Throw",
		ultimate = "Ultimate",
		dash = "Dash", -- spec phase 5: the touch Dash button (user decision 2026-10-11)
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
		hintMouse = "Click Throw · RMB/E Catch · Q Ultimate · C Dash · F Squeeze",
		hintGamepad = "R2 Throw · L1 Catch · L2 Ultimate · B Dash · X Squeeze",
		-- Reading: the key hints when the locked loadout has no ultimate (the Ultimate button is hidden, §11.6).
		hintMouseNoUlt = "Click Throw · RMB/E Catch · C Dash · F Squeeze",
		hintGamepadNoUlt = "R2 Throw · L1 Catch · B Dash · X Squeeze",
		-- Foam UI restyle (2026-10-09): the same key hints drawn as keycaps, one beside each meter's caption
		-- (controls.throw / controls.catch / controls.ultimate / controls.dash / controls.squeeze) in the bottom dock.
		key = {
			throwMouse = "Click",
			ultimateMouse = "Q",
			throwGamepad = "R2",
			ultimateGamepad = "L2",
			dashMouse = "C",
			dashGamepad = "B",
			squeezeMouse = "F",
			squeezeGamepad = "X",
			catchMouse = "RMB/E", -- feature 1 (design: html:96 "RMB / E")
			catchGamepad = "L1", -- feature 1, build choice 2026-10-11 (NOT IN DESIGN: a mouse page)
		},
		-- Feature 1 (2026-10-11): the catch's big words (design: html:352, 563), and the prompt under the reticle while an
		-- opponent's throw comes at you (design: html:88 "Catch!" with its keys).
		caught = "CAUGHT!",
		squished = "SQUISHED!",
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
			name = "Dragon Rush",
			incoming = "Dragon Rush incoming!",
			ready = "Dragon Rush ready",
			description = "Shows a warning lane for {seconds} seconds, then a dragon head charges down it. If your opponent is touching the lane, they lose a life. Charges over time, when you land hits and when you lose a life.",
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
		-- design: ults.js:6 ("Slow and very visible: back off or bait the early pop.")
		bubblePop = {
			name = "Bubble Pop",
			incoming = "Bubble Pop incoming!",
			ready = "Bubble Pop ready",
			description = "Sends a slow bubble that pops with a big splash when it touches someone, hits cover or after a moment. Back off or make it pop early.",
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
		viewInShop = "View in Shop",
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

	-- Squishies screen (§11.6). {rarity} = a rarity name. Badges and buttons use common.equipped / common.notOwned /
	-- common.equip / common.inspect; Equip results use inspect.equippedToast / inspect.equipFailed; loading uses
	-- common.loading and a data error data.loadFailed.
	inventory = {
		-- Reading: the screen title (the HUD button says the same).
		title = "Squishies",
		-- Reading: a filter chip with its count (§11.6 "Filter chips with counts"), e.g. "Epic (2)".
		filterCount = "{label} ({n})",
		filterAll = "All",
		showNotOwned = "Show not owned",
		collected = "Collected {n}/{total}",
		empty = "No {rarity} squishies yet.",
		goToBoxes = "Go to Boxes",
		new = "NEW",
	},

	-- Inline two-step spend confirmation (§11.5).
	spend = {
		confirm = "Confirm: {price} Coins",
		balanceAfter = "Balance after: {balance}",
	},

	-- Boxes: names (Boxes `nameKey`), signs, odds disclosure, open flow and reveal (§6.4, §6.10, §7.7, §9.11).
	box = {
		snack = { name = "Snack Box" },
		sweet = { name = "Sweet Box" },
		treat = { name = "Treat Box" },
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
		shopDirect = "Shop squishies directly",
		chancesByRarity = "Chances by rarity: {list}",
		rarityChance = "{rarity} {percent}%",
		listSeparator = " · ",
		insideHeading = "What's inside & chances",
		refundLine = "If you already own it: +{coins} Coins",
		total = "Total: {percent}%",
		footer = "Chances are the same for every player and never change. If you get a squishy you already own, you get the Coins shown instead.",
		details = "Details: items & chances",
		needCoins = { one = "You need {missing} more Coin", many = "You need {missing} more Coins" },
		howToEarn = "How to earn Coins",
		stillChecking = "Still checking your box…",
		revealNew = "NEW!",
		revealDuplicate = "Already owned: +{coins} Coins",
		openAnother = "Open another",
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
			starter = "Starter",
		},
		inProgress = "In progress",
		swap = "Swap",
		complete = "Quest complete! Claim your reward.",
		autoCollected = "Quest reward collected",
		footer = "New quests in {h}h {m}m",
		empty = "No quests right now. Check back in {time}.",
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
		panelTitle = "Daily Reward", -- foam fix batch: title case like every other screen's header tab
		ready = "Ready to claim!",
		wait = "Next reward in {time}",
		popup = "Daily reward ready",
		dayLabel = "Day {n}",
		comeBack = "Come back in {time}",
		-- Review quick win 2026-10-14: a missed day pauses the streak (never back to Day 1); the Daily panel and the join
		-- toast greet a returning player with the day that is waiting ({n} = that day).
		welcomeBack = "Welcome back! Day {n} is waiting.",
		treatBox = "Treat Box", -- foam fix round 2: "Free Treat Box" wrapped onto a third line on the 84 px day card
		-- Reading (Part 7; §11.6 "today highlighted" gives no text): the label on today's day card.
		today = "Today",
	},

	-- Settings (§11.6). Keys match profile.settings fields.
	settings = {
		title = "Settings",
		music = "Music",
		sfx = "Sound effects",
		cameraShake = "Camera shake",
		showTips = "Show tips",
		firstPerson = "First-person duels", -- session switch, never saved (first-person spec 2026-10-10 §3.8)
		replayTutorial = "Replay tutorial",
		noMusic = "No music yet",
		noSfx = "No sound effects yet",
	},

	-- Onboarding card (§11.8). Keyed by step id. {goal} = the cheapest shop price from the Catalog (Batch 1).
	onboarding = {
		welcome = "Welcome to Squishy Duels! Your first squishy is {starterName}.",
		-- Spec 2026-10-11 §5 (squeeze anywhere); Phase 5: a pad no longer boosts a squeeze (capsules set its pay).
		squeeze = "Squeeze squishies anywhere to earn Coins. {squeezeHint}.",
		-- Batch 1: the capsule step (the first capsule upgrade or unlock). It shows with about 10 Coins, so it waits
		-- for the UP! marker (CapsuleController: the upgrade is affordable) instead of pointing at a locked button.
		capsule = "Capsules in your base earn Coins! When Capsule 1 shows UP!, open it to Upgrade.",
		firstBox = "Get your first new squishy in the Shop. {coins}/{goal} Coins",
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
	-- writes the owner's display name, or openPlot) and the capsule plates. {level} = a capsule level 1..100;
	-- {coins} = a slot's unlock price, already formatted (Util/Format.coins).
	base = {
		openPlot = "Open plot",
		capsuleLevel = "Lv {level}",
		unlockPrice = "Unlock · {coins}",
	},

	-- The capsule card and its prompt (lobby bases spec 2026-10-11 §9; progression spec 2026-10-12 §3-§7; build plan
	-- Phase 5). {slot} = 1..4; {tier} = a capsule.tier.* name; {level} = a capsule level 1..100 (needGrip, evolveTo: a
	-- Grip Level); {seconds} / {next} = seconds between two squeezes (one decimal); {coins} / {grip} / {next} =
	-- Format.coins amounts; {name} = the base owner's display name; {n} = a squishy's capsule power (Catalog power). The
	-- squeeze pop reuses common.coinsGain and grip.popup, the Unlock button base.unlockPrice.
	capsule = {
		title = "Capsule {slot}",
		prompt = "Capsule",
		tierLevel = "{tier} · Lv {level}",
		-- Keyed by Config.Grip.Capsule.Tiers[i].key.
		tier = {
			foam = "Foam",
			jelly = "Jelly",
			marshmallow = "Marshmallow",
			gummy = "Gummy",
			taffy = "Taffy",
			caramel = "Caramel",
			bubblegum = "Bubblegum",
			rainbow = "Rainbow",
			crystal = "Crystal",
			royal = "Royal",
		},
		swap = "Tap to swap",
		empty = "Put a squishy in to start squeezing.",
		speed = "Squeezes every {seconds} s",
		speedNext = "Squeezes every {seconds} s → {next} s",
		coinsHour = "Coins/h: {coins}",
		coinsHourNext = "Coins/h: {coins} → {next}",
		gripHour = "Grip/h: {grip}",
		gripHourNext = "Grip/h: {grip} → {next}",
		evolveTo = "Next: {tier} look · needs Grip Lv {level}",
		upgrade = "Upgrade · {coins}",
		evolve = "Evolve · {coins}",
		needGrip = "Needs Grip Lv {level}",
		unlockFirst = "Unlock capsule {slot} first",
		locked = "Locked",
		max = "Top level!",
		visitor = "Only {name} can upgrade this.",
		pick = "Pick a squishy",
		inCapsule = "In capsule {slot}",
		back = "Back",
		-- Squishies, Shop and Inspect: what a squishy multiplies in a capsule (progression spec §3, §6).
		power = "x{n} power",
		powerNote = "Capsule Coins multiplier",
		-- Batch 1 #7b: the bouncing marker over an own capsule whose upgrade the Coins cover now (CapsuleController).
		up = "UP!",
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
	-- per squeeze (CapsuleMath.squeezeGrip); {mult} = a multiplier (Rested.mult);
	-- {minutes} = GripMath.restedMinutes; {n} = Grip gained. On the HUD bar {have}/{need} = Format.coins of the total
	-- and of the next level's total (GripMath.progress).
	-- Phase 5: pads and trainers no longer boost a squeeze (CapsuleMath sets its pay); Phase 6: slow training is gone,
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
		-- Batch 1 #7a: a capsule buy comes first. {slot} = a capsule 1..4; {level} = its next level; {have} / {need} =
		-- Format.coins of the Coins now (capped at the price) and the price.
		goalCapsuleReady = "Upgrade Capsule {slot} · READY!",
		goalUnlockReady = "Unlock Capsule {slot} · READY!",
		goalCapsule = "Next: upgrade Capsule {slot} to Lv {level} · {have}/{need} Coins",
		goalUnlock = "Next: unlock Capsule {slot} · {have}/{need} Coins",
		-- Foam fix 2: the regular HUD card's goal line (one line in its info column); the panel and toasts keep the above.
		hudGoalRank = "Next: {rank} at Lv {level}",
		-- Batch 1 #7a: the card's short form of goalCapsule and goalUnlock. It names Coins, as the bar line above it
		-- names Grip. One line (at most 30 characters) except a price of 100.00M .. 999.99M (31-32), which may take a
		-- second line: the card's height plan holds it (HudFormat.worstCaseTexts gripGoal). The READY lines are short.
		hudGoalCapsule = "Capsule {slot}: {have}/{need} Coins",
		-- At a pad.
		popup = "+{n} Grip",
		popupDouble = "+{n} Grip (x{mult})",
		-- The floating label on the held squishy (lobby HUD spec 2026-10-11 §2): what one squeeze pays, the same anywhere
		-- (Phase 5: the squeeze value and the best capsule's Grip; no pad name).
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
		panelIntro = "Squeezing trains your Grip. Higher Grip opens new capsule tiers.",
		restedHelp = "Double Grip fills up over time, even while you're away. While it lasts, each squeeze trains x{mult} Grip.",
		-- Spec 2026-10-11 §5: no hourly limit any more; the note says where squeezing pays.
		limitNote = "Squeezing earns Coins and trains Grip, anywhere in the lobby.",
		duelNote = "Grip only helps in the lobby. It never changes duels, and it can't be bought.",
		-- Toasts (Notify codes, Types.GripNotifyCode). rankUp: {name} = the player's display name.
		levelUp = "Grip Lv {level}!",
		rankUp = "{name} reached {rank}!",
		intro = "You trained your Grip! Squeeze more to open new capsule tiers.",
		welcome = "Double Grip is full: your first squeezes train x{mult} Grip!",
		welcomeBack = "Welcome back! Double Grip: about {minutes} min.",
		headStart = "Your past squeezes count: you start at Grip Lv {level}!",
		-- Idle card (LocalPlayer.Idled after Config.Grip.idleReminderSeconds). The 20 minutes are Roblox's idle kick,
		-- not a game setting.
		idleTitle = "Still there?",
		-- Foam fix 2: one sentence per line. Phase 6: the second names what still stops (the capsules).
		idleBody = "Roblox disconnects players who are idle for 20 minutes.\nCapsules stop paying when that happens.",
		idleButton = "Keep going",
		-- World: the lobby nameplate.
		nameplate = "Lv {level} · {rank}",
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
