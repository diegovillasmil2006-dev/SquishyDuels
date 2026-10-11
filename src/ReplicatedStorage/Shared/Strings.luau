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
			-- Reading (not in §2.10): §5.6 #4 "not rooted by Dragon Rush" (telegraph and recovery).
			rooted = "You can't throw while using Dragon Rush.",
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
			-- Every click pays (2026-10-06): only the hidden anti-autoclicker cap (12 a second) sends this code, and
			-- the client never shows it (kept so every server reason has a text, §2.10).
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
		-- Grip trainer upgrades (TrainerUpgrade, §17.5, §17.7; Part 7).
		trainer = {
			notNext = "Buy the trainers in order.",
			locked = "Your Grip level is too low for this trainer.",
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
		hintMouse = "Click Throw · Q Ultimate",
		hintGamepad = "R2 Throw · L2 Ultimate",
		-- Reading: the key hints when the locked loadout has no ultimate (the Ultimate button is hidden, §11.6).
		hintMouseNoUlt = "Click Throw",
		hintGamepadNoUlt = "R2 Throw",
		-- Foam UI restyle (2026-10-09): the same key hints drawn as keycaps, one beside each meter's caption
		-- (controls.throw / controls.ultimate) in the bottom dock.
		key = {
			throwMouse = "Click",
			ultimateMouse = "Q",
			throwGamepad = "R2",
			ultimateGamepad = "L2",
		},
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
	},

	-- Hit and elimination feedback (§9.8, §9.9).
	combat = {
		hit = "Hit!",
		out = "OUT!",
		ko = "K.O.!",
	},

	-- Abilities (§5.9). {seconds} = Config.Abilities.dragon_rush.telegraphSeconds.
	ability = {
		interrupted = "Interrupted!",
		dragonRush = {
			name = "Dragon Rush",
			incoming = "Dragon Rush incoming!",
			ready = "Dragon Rush ready",
			description = "Shows a warning lane for {seconds} seconds, then a dragon head charges down it. If your opponent is touching the lane, they lose a life. Charges over time, when you land hits and when you lose a life.",
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
		coinsPerSqueeze = "Coins per squeeze: {n}",
		coinsPerSqueezeSub = "per squeeze", -- spec 2026-10-11 §5
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
			-- §17.7 (Part 7): squeezes at a tier >= 2 station only (the Jelly Pad and up).
			jelly = { one = "Squeeze once on the Jelly Pad", many = "Squeeze {n} times on the Jelly Pad" },
		},
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
		streakReset = "Your streak restarted at Day 1.",
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

	-- Onboarding card (§11.8). Keyed by step id. {goal} = the box cost or the cheapest shop price from Config/Catalog.
	onboarding = {
		welcome = "Welcome to Squishy Duels! Your first squishy is {starterName}.",
		-- Spec 2026-10-11 §5 (squeeze anywhere; pads only boost).
		squeeze = "Squeeze squishies anywhere to earn Coins. {squeezeHint}. Squeeze pads give a boost.",
		firstBox = "Open your first box at the Gift Box counter. {coins}/{goal} Coins",
		firstBoxShop = "Get your first new squishy in the Shop. {coins}/{goal} Coins",
		equip = "Equip your new squishy: open Squishies and press Equip.",
		-- Lobby HUD spec 2026-10-11 §2: Inspect is in the Squishies screen now (no equipped card).
		inspect = "Open Squishies and press Inspect to see it in 3D. Drag to spin it, then try Squeeze.",
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
		spawnLogo = "SQUISHY DUELS",
		spawnSafe = "Safe zone: duels happen in the arena",
		duelGateTitle = "DUEL ARENA",
		duelGateSubtitle = "1v1 duels • Queue at the pad",
		squeezeTitle = "SQUEEZE ZONE",
		squeezeSubtitle = "Squeeze your squishy to earn Coins",
	},

	-- Collection display (§7.6, §7.7).
	collection = {
		title = "MY COLLECTION",
		owned = "Owned",
		notOwned = "Not owned yet",
	},

	-- Grip training (§17.6, §17.7), a lobby-only stat. Never shown in duels: the client holds grip.* toasts back from
	-- Matched to Returning, and no duel text mentions it. Placeholders: {level} = a Grip Level (a pad's or trainer's
	-- Config level, or the player's); {rank} = a grip.rank.* name; {pad} = a grip.pad.* name; {trainer} = a
	-- grip.trainer.* name; {coins} = a Coin amount (a pad's coinBonus, a price, or Coins still missing); {grip} = Grip
	-- per squeeze (GripMath.squeezeGrip); {mult} = a multiplier (Pads[tier].gripPercent / 100 or Rested.mult);
	-- {minutes} = GripMath.restedMinutes / afkMinutes; {n} = Grip gained. {have}: on signLocked the viewer's Grip
	-- Level; on the HUD bar {have}/{need} = Format.coins of the total and of the next level's total (GripMath.progress).
	grip = {
		-- HUD card (top-left, under the Coins pill).
		hudLevel = "Grip Lv {level} · {rank}",
		hudLevelCompact = "Lv {level} · {rank}",
		hudBar = "{have} / {need} Grip",
		hudMax = "Max level",
		-- Foam restyle (spec 2026-10-09): the small label over the level number on the regular card's level tile.
		levelTag = "GRIP",
		restedChip = "Double Grip: about {minutes} min",
		upgradeBadge = "Upgrade available",
		-- Next goal (GripMath.nextGoal, first that applies).
		goalUpgrade = "Upgrade ready: {trainer} for {coins} Coins",
		goalPad = "Next: {pad} at Grip Lv {level}",
		goalTrainer = "Next: {trainer} unlocks at Grip Lv {level}",
		goalRank = "Next rank: {rank} at Grip Lv {level}",
		goalMax = "Max level! You're a Squish Master.",
		-- Foam fix 2: the regular HUD card's goal line (one line in its info column); the panel and toasts keep the above.
		hudGoalPad = "Next: {pad} at Lv {level}",
		hudGoalTrainer = "Next: {trainer} at Lv {level}",
		hudGoalRank = "Next: {rank} at Lv {level}",
		-- At a pad.
		popup = "+{n} Grip",
		popupDouble = "+{n} Grip (x{mult})",
		afkPopup = "+{n} Grip (slow training)",
		-- The floating label on the held squishy (lobby HUD spec 2026-10-11 §2): the pad name on its own line (foam fix
		-- 2: one line left "squeeze" alone).
		stationLabel = "{pad}\n+{coins} Coins · +{grip} Grip per squeeze",
		-- Spec 2026-10-11 §5: off a pad (or on one still locked) a squeeze pays the base amount, with no pad name.
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
		},
		-- Keyed by Config.Grip.Pads[tier].key.
		pad = {
			foam = "Foam Mats",
			jelly = "Jelly Pad",
			marshmallow = "Marshmallow Pad",
			royal = "Royal Cushion",
		},
		-- Keyed by Config.Grip.Trainer[i].key.
		trainer = {
			foam = "Foam Ball",
			sponge = "Sponge Ball",
			rubber = "Rubber Ball",
			spring = "Spring Gripper",
			jelly = "Jelly Gripper",
			steel = "Steel Gripper",
			gold = "Gold Gripper",
			diamond = "Diamond Gripper",
		},
		-- Grip panel (one scrolling column). The trainer card itself comes with Part 7.
		panelTitle = "Grip Training",
		panelIntro = "Every squeeze trains your Grip. Higher Grip opens better squeeze pads.",
		padsHeader = "Squeeze pads",
		padNeeds = "Needs Grip Lv {level}",
		padPerks = "+{coins} Coins and x{mult} Grip per squeeze",
		padPerksBase = "No boost: the same Coins and Grip as anywhere", -- the Foam Mats card (spec 2026-10-11 §5)
		padOpen = "Open",
		padLocked = "Locked",
		showMe = "Show me",
		trainerHeader = "Trainer",
		trainerNow = "Now: {trainer} (+{grip} Grip per squeeze)",
		trainerNext = "Next: {trainer} (+{grip} Grip per squeeze)",
		trainerBuy = "Upgrade: {coins} Coins",
		trainerNeedLevel = "Reach Grip Lv {level}",
		trainerNeedCoins = "Need {coins} more Coins",
		trainerMax = "Best trainer owned!",
		trainerNote = "Upgrades make training faster. They never change duels.",
		restedHelp = "Double Grip fills up over time, even while you're away. While it lasts, each squeeze trains x{mult} Grip.",
		-- Spec 2026-10-11 §5: no hourly limit any more; the note says where squeezing pays.
		limitNote = "Every squeeze earns Coins and trains Grip, anywhere in the lobby. Squeeze pads give a boost.",
		afkHelp = "Standing on an open pad slowly trains Grip, even when you're not squeezing. It never gives Coins, and it stops if Roblox disconnects you for being idle.",
		afkBank = "Slow training at full speed: about {minutes} min left",
		duelNote = "Grip only helps in the lobby. It never changes duels, and it can't be bought.",
		-- Toasts (Notify codes, Types.GripNotifyCode). rankUp: {name} = the player's display name.
		levelUp = "Grip Lv {level}!",
		padUnlocked = "{pad} unlocked! +{coins} Coins and x{mult} Grip per squeeze there.",
		rankUp = "{name} reached {rank}!",
		trainerBought = "{trainer} unlocked! +{grip} Grip per squeeze.",
		intro = "You trained your Grip! Squeeze more to open better pads.",
		welcome = "Double Grip is full: your first squeezes train x{mult} Grip!",
		welcomeBack = "Welcome back! Double Grip: about {minutes} min.",
		headStart = "Your past squeezes count: you start at Grip Lv {level}!",
		-- Idle card (LocalPlayer.Idled after Config.Grip.idleReminderSeconds). The 20 minutes are Roblox's idle kick,
		-- not a game setting.
		idleTitle = "Still there?",
		-- Foam fix 2: one sentence per line (the card's wrap broke the line after "Slow").
		idleBody = "Roblox disconnects players who are idle for 20 minutes.\nSlow training stops when that happens.",
		idleButton = "Keep going",
		-- World: the Jelly pod sign heading, the pod signs' Live line, the lobby nameplate.
		gymTitle = "GRIP GYM",
		signLocked = "Needs Grip Lv {level} · You: Lv {have}",
		signOpen = "Open · +{coins} Coins · x{mult} Grip",
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
