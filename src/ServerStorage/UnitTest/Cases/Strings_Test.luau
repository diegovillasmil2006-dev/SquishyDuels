--!strict
-- Strings_Test: unit tests for ReplicatedStorage.Shared.Strings. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.2, §2.10): every server reason code of §2.10 has a text under `reason.*`, read with
-- Strings.reasonText(code). Part 4: the duel, queue and practice texts DESIGN quotes keep their exact wording, and
-- every text the Part 4 screens and DuelResult.reasonKey use exists. Part 5: the data banners, restart notice,
-- settings, Squishies and every §17.7 Grip text keep DESIGN's wording; the Part 5 codes and readings exist; no duel
-- text mentions Grip (§17.2 rule 1). Part 7: the Part 7 readings (box.title,
-- box.freeOnly, box.boardHeader, box.boardLine, daily.today) exist, and box.freeOnly names the Config free box day.
-- Foam fix 2: the Grip card's short goal lines (grip.hudGoal*); grip.idleBody keeps its line break (Phase 6: its second
-- sentence names the capsules).
-- Squeeze anywhere (spec 2026-10-11 §5): the onboarding step, Inspect's preview lines, the off-pad label
-- (grip.stationLabelBase) and grip.limitNote never send you to a mat;
-- the mat, pad-level, limit and locked-button texts are gone. Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): the
-- squeeze hints name a click or a tap, grip.holdPaused names no button (it left DESIGN's words), the Inspect step opens
-- Squishies, and the Squeeze button's key texts are gone. Final polish (2026-10-11): the duel key hints also name the
-- dash and the squeeze (they left DESIGN's "Click Throw · Q Ultimate"), and the "In the lane!" warning exists.
-- Phase 5: pads and trainers no longer boost a squeeze, so no pad, trainer or onboarding text claims one (Grip opens
-- the capsule tiers); the pad label and "Coins per squeeze" are gone; the capsule card texts and a name for every
-- capsule tier exist. Phase 6: slow training is gone: its popup, help and bank texts are gone and no text names it
-- (pads change nothing a player earns now; the idle card says capsules stop paying); so are the trainers: every
-- trainer text, goal and reason is gone and no text names a trainer; and so are the giant pads and Jelly gates: their
-- names (only grip.pad.foam is left), pad cards, signs, unlock toast, pad goal and the starter_jelly task texts.
-- Batch 1: the tutorial points at the Shop (no equip or firstBoxShop text); grip.panelIntro / limitNote say squeezing
-- earns (Batch 1 #2). Pens3 phase 3: every capsule text is gone (the reason codes, the tutorial step, the card, the
-- goals, the UP! marker, the base plates); squishy.power / powerNote keep capsule.power's texts.
-- (tools/check.ps1 (c) is meant to cover the codes the server actually emits; until it exists, this case pins the
-- §2.10 list.)
-- Review quick win (2026-10-14): a missed day pauses the daily streak: daily.welcomeBack names the waiting day and no
-- daily text speaks of a reset.
-- Batch 3 (friends, review #6 and #10): the duel pad, Rematch, Invite, player list and weekly board texts, word for
-- word; none of them rewards inviting or mentions Robux.
-- Pens3 phase 1: the three Grip texts that named capsules now name what is true (grip.panelIntro, grip.intro, and
-- grip.idleBody's second line names the pen); every PenBuySpot refusal code has a text under reason.pen.*; the pen
-- sign, prompt, coin label, onboarding step and Grip goal texts exist with their placeholders. Pens3 phase 4: the
-- coins-while-away texts (away.*) exist with their placeholders, and none presses a kid (no countdown, no claim now).
-- Pens3 phase 5: reason.inventory.full (Toy Box full), shop.welcomePrice, box.nextItem (the fixed order's next item),
-- the firstBox step names the Welcome price; the box footer promises a copy (never Coins) and the restricted note says
-- boxes open in a fixed order; none of them presses a kid.
-- Pens3 phases 7-8: every SellItems / SellAll / BuyBack / Fuse refusal code has a text under reason.pen.*; the pen
-- screen's sell, buy-back and fusion texts exist with their placeholders, say what is true (what Sell All keeps, a free
-- fusion with no luck) and never press a kid (the buy-back time is a plain number, no "hurry").
-- Pens3 phase 9: every Config food has a name; every BuyFood / Feed / FeedAll refusal code has a text; the pen
-- screen's food texts (the hint, the food row, the BUY FOOD cards, the sell confirm's food line) exist with their
-- placeholders and never press a kid.
-- Pens3 phase 10: the gate's texts (P3D:250, :277): BASE n under the owner's name, the heart and 1 visitor / N
-- visitors on the visitor board.
-- Pens3 phase 11: PenBuyShelf's own refusal code (reason.pen.shelfMax); the SHELF SPOTS sign's title (P3D:255) and
-- prompt; the pen screen's shelf and TOP headings with their placeholders; none of them presses a kid. Wb: the MY PEN
-- window's shelf BUY button labels (BUY ROW / BUY TOP with the price, SHELF MAX), short and calm.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- DESIGN §2.10, in its order (pens3 phase 5: box.restricted, box.complete and shop.owned are gone, no server sends
-- them any more).
local REASON_CODES = {
	"error.generic",
	"error.connect",
	"net.rateLimited",
	"net.invalid",
	"data.notReady",
	"data.offline",
	"data.readOnly",
	"data.openedElsewhere",
	"data.waitingOtherServer",
	"economy.notEnoughCoins",
	"inventory.notOwned",
	"inventory.lockedInDuel",
	"queue.unavailable",
	"queue.paused",
	"queue.cooldown",
	"queue.alreadyQueued",
	"queue.removedIdle",
	"queue.timedOut",
	"duel.noRewardsOffline",
	"duel.rewardsReduced",
	"duel.tooShort",
	"throw.cooldown",
	"throw.context",
	"throw.direction",
	"throw.tooMany",
	"ult.notReady",
	"ult.noRoom",
	"squeeze.tooFast",
	"box.checking",
	"box.unknown",
	"box.paused",
	"box.saving",
	"shop.priceChanged",
	"shop.notForSale",
	"quest.notReady",
	"quest.alreadyClaimed",
	"quest.swapUsed",
	"daily.alreadyClaimed",
	"purchase.unavailable",
}

-- Part 4 (duel, queue, practice): the texts DESIGN quotes word for word (§5.4, §5.9, §5.11, §6.7, §7.7, §11.6).
local DESIGN_WORDING: { [string]: string } = {
	["queue.searching"] = "Looking for an opponent…",
	["queue.position"] = "You're #{n} in the queue",
	["queue.noOpponent"] = "No one else is in the queue right now.",
	["queue.waitingArena"] = "All arenas are in use. You're next.",
	["queue.left"] = "You left the queue.",
	["queue.matched"] = "Opponent found: {name}",
	["queue.joinFailed"] = "Couldn't join the queue. Try again.",
	["queue.boardTitle"] = "Duel Queue",
	["queue.boardHint"] = "Matches start automatically when an opponent is found.",
	["reason.queue.removedIdle"] = "You were removed from the queue for being idle.",
	["reason.queue.paused"] = "The server is restarting soon, so duels are paused.",
	["reason.queue.unavailable"] = "Duels are unavailable right now.",
	["reason.inventory.lockedInDuel"] = "You can change squishies after the duel.",
	["reason.duel.tooShort"] = "Match too short for rewards.",
	["reason.duel.rewardsReduced"] = "Reduced reward: you've played this opponent a lot in the last hour.",
	["reason.ult.noRoom"] = "Not enough room. Step away from the wall.",
	["duel.opponentLeftEarly"] = "Your opponent left before the duel started. You're back at the front of the queue.",
	["duel.suddenDeath"] = "Sudden death: next hit wins!",
	["duel.void"] = "The server is shutting down. This duel won't count.",
	["duel.countdownGo"] = "Throw!",
	["duel.forfeitConfirm"] = "Forfeit the duel?",
	["duel.sideA"] = "Strawberry side",
	["duel.sideB"] = "Mint side",
	["duel.ultReady"] = "READY",
	["duel.queueAgain"] = "Queue again",
	["duel.testDummy"] = "TEST DUMMY (Studio)",
	["duel.result.win"] = "VICTORY",
	["duel.result.loss"] = "DEFEAT",
	["duel.result.draw"] = "DRAW",
	["duel.result.cancelled"] = "Duel cancelled",
	["duel.result.void"] = "Duel didn't count",
	["duel.reward.win"] = "+{coins} Coins (win)",
	["combat.hit"] = "Hit!",
	["combat.out"] = "OUT!",
	["combat.ko"] = "K.O.!",
	["ability.dragonRush.name"] = "Dragon Rush",
	["ability.dragonRush.incoming"] = "Dragon Rush incoming!",
	["ability.dragonRush.ready"] = "Dragon Rush ready",
	["ability.interrupted"] = "Interrupted!",
	["practice.sign"] = "Practice range: targets don't pay Coins",
	["practice.targetName"] = "Foam Dummy",
	["prompt.joinQueue"] = "Join 1v1 Queue",
	["prompt.leaveQueue"] = "Leave Queue",
}

-- Part 4 texts every duel/queue/practice screen reads (DESIGN wording where it exists, readings otherwise).
local PART4_KEYS = {
	"queue.searchingTime",
	"queue.keepWaiting",
	"queue.practice",
	"queue.boardWaiting",
	"queue.boardActive",
	"common.cancel",
	"common.close",
	"common.percent",
	"common.secondsShort",
	"controls.throw",
	"controls.ultimate",
	"hud.nav.duel",
	"duel.you",
	"duel.opponent",
	"duel.forfeit",
	"duel.forfeitYes",
	"duel.forfeitNo",
	"duel.forfeitCancelNote",
	"duel.forfeitLoseNote",
	"duel.hintMouseNoUlt",
	"duel.hintGamepadNoUlt",
	"duel.waitingOpponent",
	"duel.reticle.ready",
	"duel.reticle.rooted",
	"duel.reticle.wrongZone",
	"duel.outOfBounds",
	"duel.reward.loss",
	"duel.reward.draw",
	"duel.rewardBlocked",
	"duel.questLine",
	"duel.lossTip",
	"stats.throws",
	"stats.hits",
	"stats.accuracy",
	"ability.dragonRush.description",
	"practice.title",
	"practice.panelTitle",
	"practice.waypoint",
	"practice.distanceLabel",
}

-- DuelResult.reasonKey values (Types.DuelResultPayload): one line per way a duel ends (§5.2, §5.4).
local RESULT_REASON_KEYS = {
	"duel.opponentOut",
	"duel.youOut",
	"duel.timeUpWin",
	"duel.timeUpLoss",
	"duel.suddenDeathWin",
	"duel.suddenDeathLoss",
	"duel.suddenDeathDraw",
	"duel.tieHit",
	"duel.opponentLeft",
	"duel.youLeft",
	"duel.youOutOfBounds",
	"duel.opponentOutOfBounds",
	"duel.cancelled",
	"duel.opponentLeftEarly",
	"duel.void",
}

-- Codes the Part 4 server may send that DESIGN §2.10 does not list (readings; check-reasons.ps1 also checks them).
local EXTRA_REASON_CODES = { "queue.notReady", "throw.rooted", "ult.context", "ult.direction" }

-- Part 5 (data, squeeze, settings, Squishies screen, Grip): the texts DESIGN quotes word for word (§3.1, §3.12,
-- §3.13, §6.3, §11.3, §11.6, §17.7).
local PART5_WORDING: { [string]: string } = {
	["data.studioMemory"] = "Studio test: progress is not saved.",
	["data.offlineRetrying"] = "Your progress couldn't load. Nothing will be saved right now. We're retrying.",
	["data.loaded"] = "Progress loaded!",
	["data.rejoin"] = "Please rejoin.",
	["data.newerVersion"] = "A new version is rolling out. Rejoin to keep earning.",
	["data.loadFailed"] = "Couldn't load your progress. Your saved progress is safe. Please rejoin.",
	["reason.data.notReady"] = "Coins are paused because your data didn't load. Please rejoin.",
	["reason.data.openedElsewhere"] = "Your progress was opened on another server. Please rejoin.",
	["reason.data.waitingOtherServer"] = "Your data is still closing on another server…",
	["server.restartSoon"] = "This server will restart in {time}.",
	["settings.music"] = "Music",
	["settings.sfx"] = "Sound effects",
	["settings.cameraShake"] = "Screen shake", -- UI FINAL R9 (H:979)
	["settings.reducedMotion"] = "Reduced motion", -- UI FINAL R9 (H:979, the user's Q6)
	["settings.volume"] = "Volume", -- UI FINAL R9 (H:442)
	["settings.showTips"] = "Show tips",
	["settings.replayTutorial"] = "Replay tutorial",
	["settings.noMusic"] = "No music yet",
	["settings.noSfx"] = "No sound effects yet",
	["settings.firstPerson"] = "First-person duels", -- first-person spec 2026-10-10 §3.8
	["inventory.showLockedLines"] = "Show\nlocked", -- UI FINAL R5 (H:196: the design's two lines)
	["inventory.new"] = "NEW",
	["common.equipped"] = "Equipped",
	["common.notOwned"] = "Not owned",
	-- §17.7 HUD
	["grip.hudLevel"] = "Grip Lv {level} · {rank}",
	["grip.hudLevelCompact"] = "Lv {level} · {rank}",
	["grip.hudBar"] = "{have} / {need} Grip",
	["grip.hudMax"] = "Max level",
	["grip.restedChip"] = "Double Grip: about {minutes} min",
	-- §17.7 next goal
	["grip.goalRank"] = "Next rank: {rank} at Grip Lv {level}",
	["grip.goalMax"] = "Max level! You've reached Infinite Grip.",
	-- §17.7 at a pad
	["grip.popup"] = "+{n} Grip",
	["grip.popupDouble"] = "+{n} Grip (x{mult})",
	-- Lobby HUD spec 2026-10-11 §2: there is no Squeeze button any more (DESIGN's words named it).
	["grip.holdPaused"] = "Squeeze again to keep training.",
	-- §17.3.3, §17.5, §17.7 names
	["grip.rank.soft"] = "Soft Grip",
	["grip.rank.firm"] = "Firm Grip",
	["grip.rank.strong"] = "Strong Grip",
	["grip.rank.iron"] = "Iron Grip",
	["grip.rank.titan"] = "Titan Grip",
	["grip.rank.master"] = "Squish Master",
	["grip.pad.foam"] = "Foam Mats",
	-- §17.7 panel. Phase 5 (build plan; progression spec 2026-10-12 §3): pads and trainers no longer boost a squeeze.
	-- Phase 6: slow training is gone, so DESIGN's pad and trainer lines lost their last claim (a pad pays the same as
	-- anywhere). Pens3 phase 1: no capsule tiers any more, so the intro says what squeezing does.
	["grip.panelTitle"] = "Grip Training",
	["grip.panelIntro"] = "Squeezing trains your Grip and earns Coins.",
	["grip.restedHelp"] = "Double Grip fills up over time, even while you're away. While it lasts, each squeeze trains x{mult} Grip.",
	-- Spec 2026-10-11 §5: no hourly limit any more; the note says where squeezing pays (Phase 5: no pad boost).
	["grip.limitNote"] = "Squeezing earns Coins and trains Grip, anywhere in the lobby.",
	["grip.duelNote"] = "Grip only helps in the lobby. It never changes duels, and it can't be bought.",
	-- §17.7 toasts
	["grip.levelUp"] = "Grip Lv {level}!",
	["grip.rankUp"] = "{name} reached {rank}!",
	["grip.intro"] = "You trained your Grip! Squeeze more to level it up.", -- pens3 phase 1: no capsule tiers
	["grip.welcome"] = "Double Grip is full: your first squeezes train x{mult} Grip!",
	["grip.welcomeBack"] = "Welcome back! Double Grip: about {minutes} min.",
	["grip.headStart"] = "Your past squeezes count: you start at Grip Lv {level}!",
	-- §17.7 idle card and world
	["grip.idleTitle"] = "Still there?",
	-- Foam fix 2: DESIGN's two sentences, one per line (the wrap broke the line after "Slow"). Pens3 phase 1: the second
	-- one names what still stops (the pen pays only while you are in the server).
	["grip.idleBody"] = "Roblox disconnects players who are idle for 20 minutes.\nYour pen stops paying when that happens.",
	["grip.idleButton"] = "Keep going",
	["grip.nameplate"] = "Lv {level} · {rank}",
}

-- Part 5 texts with no DESIGN wording (readings) that the Part 5 screens read.
local PART5_KEYS = {
	"inventory.title",
	"inventory.filterAll",
	"inventory.collected",
	"inventory.empty",
	"inventory.goToBoxes",
	-- UI FINAL R5 (the design's Squishies window, H:186-188, H:846, H:1013)
	"inventory.collectedLabel",
	"inventory.collectedCount",
	"inventory.ultimateChip",
	"inventory.equippedToast",
	"inspect.equippedToast",
	"inspect.equipFailed",
	"settings.title",
	"common.on",
	"common.off",
	"controls.squeeze",
	"controls.keyHint",
	"controls.key.inspectKeyboard",
	"controls.key.inspectGamepad",
	"controls.key.squishiesKeyboard",
	"controls.key.backKeyboard",
	"controls.key.backGamepad",
	"hud.nav.squishies",
	"hud.nav.settings",
	"common.coinsGain",
	"common.loading",
}

-- Codes the Part 5 server sends (Result reasons and Notify codes).
local PART5_CODES = {
	"data.notReady",
	"data.offline",
	"data.readOnly",
	"data.openedElsewhere",
	"data.waitingOtherServer",
	"inventory.notOwned",
	"inventory.lockedInDuel",
	"squeeze.tooFast",
	"squeeze.inDuel",
	"squeeze.noCharacter", -- spec 2026-10-11 §5: the one refusal left of the old station checks
	"duel.noRewardsOffline",
	"duel.rewardsReduced",
	"duel.tooShort",
	"server.restartSoon",
	"data.loaded",
	"grip.levelUp",
	"grip.rankUp",
	"grip.welcome",
	"grip.welcomeBack",
	"grip.headStart",
}

return function(t: Context)
	local Strings = t.requireShared("Strings")
	local expect = t.expect

	t.test("Part 4 texts DESIGN quotes keep their exact wording", function()
		local wrong = {}
		for key, text in DESIGN_WORDING do
			if Strings.resolve(key) ~= text then
				table.insert(wrong, string.format("%s = %q", key, tostring(Strings.resolve(key))))
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			error("not the DESIGN wording: " .. table.concat(wrong, "; "))
		end
	end)

	t.test("every Part 4 screen text, result line and extra reason code exists", function()
		local missing = {}
		for _, list in { PART4_KEYS, RESULT_REASON_KEYS } do
			for _, key in list do
				local text = Strings.resolve(key)
				if type(text) ~= "string" or text == "" then
					table.insert(missing, key)
				end
			end
		end
		for _, code in EXTRA_REASON_CODES do
			if Strings.resolve("reason." .. code) == nil then
				table.insert(missing, "reason." .. code)
			end
		end
		if #missing > 0 then
			error("missing: " .. table.concat(missing, ", "))
		end
	end)

	-- §5.4: "You left the queue after 5 minutes." with QueueMaxSeconds = 300 filled in as {minutes}.
	t.test("queue.timedOut reads the DESIGN sentence once the minutes are filled in", function()
		local Config = t.requireShared("Config")
		local minutes = Config.Duel.Matchmaking.QueueMaxSeconds / 60
		expect.equal(
			Strings.format(Strings.reasonText("queue.timedOut"), { minutes = minutes }),
			string.format("You left the queue after %d minutes. Join again any time.", minutes)
		)
	end)

	t.test("life counts use a singular and a plural text", function()
		local lives = Strings.duel.lives
		expect.equal(Strings.format(Strings.plural(1, lives.one, lives.many), { n = 1 }), "1 life")
		expect.equal(Strings.format(Strings.plural(3, lives.one, lives.many), { n = 3 }), "3 lives")
	end)

	-- Every §2.10 code resolves under reason.* (not only through the plain-key fallback of reasonText).
	t.test("every DESIGN §2.10 reason code has a text under reason.*", function()
		local missing = {}
		for _, code in REASON_CODES do
			local text = Strings.resolve("reason." .. code)
			if type(text) ~= "string" or text == "" then
				table.insert(missing, code)
			end
		end
		if #missing > 0 then
			error("no reason.* text for: " .. table.concat(missing, ", "))
		end
	end)

	-- reasonText returns the reason.* text for a known code.
	t.test("reasonText returns the reason text of a known code", function()
		expect.equal(Strings.reasonText("economy.notEnoughCoins"), Strings.resolve("reason.economy.notEnoughCoins"))
	end)

	-- Part 5 ----------------------------------------------------------------------------------------------------

	t.test("Part 5 texts DESIGN quotes keep their exact wording", function()
		local wrong = {}
		for key, text in PART5_WORDING do
			if Strings.resolve(key) ~= text then
				table.insert(wrong, string.format("%s = %q", key, tostring(Strings.resolve(key))))
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			error("not the DESIGN wording: " .. table.concat(wrong, "; "))
		end
	end)

	t.test("every Part 5 screen text exists and every Part 5 code has a text", function()
		local missing = {}
		for _, key in PART5_KEYS do
			local text = Strings.resolve(key)
			if type(text) ~= "string" or text == "" then
				table.insert(missing, key)
			end
		end
		for _, code in PART5_CODES do
			if Strings.resolve("reason." .. code) == nil and Strings.resolve(code) == nil then
				table.insert(missing, code)
			end
		end
		if #missing > 0 then
			error("missing: " .. table.concat(missing, ", "))
		end
	end)

	-- §11.6 lists the Settings rows (Music, Sound effects, Camera shake, Show tips, Replay tutorial), plus the session
	-- switch "First-person duels" (first-person spec 2026-10-10 §3.8). UI FINAL R9 (H:979, H:442; the user's Q6): the
	-- design's Reduced motion switch and its Volume row; the settings texts hold nothing else.
	t.test("the settings texts are §11.6's rows, the first-person switch and the design's two (R9)", function()
		local expected = {
			"cameraShake",
			"firstPerson",
			"music",
			"noMusic",
			"noSfx",
			"reducedMotion",
			"replayTutorial",
			"sfx",
			"showTips",
			"title",
			"volume",
		}
		local keys = {}
		for key in Strings.settings do
			table.insert(keys, key)
		end
		table.sort(keys)
		expect.deepEqual(keys, expected)
		expect.equal(Strings.resolve("settings.reducedMotion"), "Reduced motion")
	end)

	-- §17.7 "Changed text" and §17.2 rule 1: the loss tip shows on the duel result panel, so it never names the lobby
	-- stat; nothing else in the duel texts does either.
	t.test("the duel texts never mention Grip, and the loss tip covers training on pads", function()
		expect.truthy(
			string.find(Strings.duel.lossTip, "squeezing and training on pads don't make your throws stronger", 1, true)
		)
		local function scan(value: any, path: string)
			if type(value) == "string" then
				if string.find(string.lower(value), "grip", 1, true) then
					error(path .. " mentions Grip: " .. value)
				end
			elseif type(value) == "table" then
				for key, child in value do
					scan(child, path .. "." .. tostring(key))
				end
			end
		end
		scan(Strings.duel, "duel")
		scan(Strings.combat, "combat")
		scan(Strings.ability, "ability")
	end)

	-- G6 from the Strings side: every rank and pad of Config.Grip has its name.
	t.test("every Config.Grip rank and pad has a grip.* name", function()
		local Config = t.requireShared("Config")
		local missing = {}
		local groups: { { prefix: string, list: { any } } } = {
			{ prefix = "grip.rank.", list = Config.Grip.Ranks },
			{ prefix = "grip.pad.", list = Config.Grip.Pads },
		}
		for _, group in groups do
			for _, entry in group.list do
				local key = group.prefix .. entry.key
				if Strings.resolve(key) == nil then
					table.insert(missing, key)
				end
			end
		end
		if #missing > 0 then
			error("missing: " .. table.concat(missing, ", "))
		end
	end)

	t.test("the ranks above Lv 50 read Legend, Mythic, Cosmic, Galaxy and Infinite (spec 2026-10-12 §10)", function()
		local names = {}
		for _, key in { "legend", "mythic", "cosmic", "galaxy", "infinite" } do
			table.insert(names, Strings.resolve("grip.rank." .. key))
		end
		expect.deepEqual(names, { "Legend Grip", "Mythic Grip", "Cosmic Grip", "Galaxy Grip", "Infinite Grip" })
	end)

	-- Part 7 ----------------------------------------------------------------------------------------------------

	-- §17.7 quoted the starter_jelly texts word for word; Phase 6 removed them with the task (and the trainer reason
	-- texts with the trainers).
	t.test("Part 7: the starter_jelly task texts are gone with the giant pads (build plan Phase 6)", function()
		expect.equal((Strings.quest.starterTask :: any).jelly, nil)
		expect.equal(Strings.resolve("quest.starterTask.jelly.one"), nil)
		expect.equal(Strings.resolve("quest.starterTask.jelly.many"), nil)
	end)

	-- Readings the Part 7 screens use (DESIGN implies them but gives no words).
	t.test("the Part 7 reading texts exist with their placeholders", function()
		expect.equal(Strings.resolve("box.title"), "Squishy Boxes")
		expect.equal(Strings.resolve("daily.today"), "Today")
		expect.equal(
			Strings.format(Strings.box.boardHeader, { box = Strings.box.snack.name, cost = "400" }),
			"Snack Box: 400 Coins"
		)
		expect.equal(
			Strings.format(Strings.box.boardLine, { name = "Toast", rarity = "Common", percent = "32.00" }),
			"Toast (Common): 32.00%"
		)
	end)

	-- box.freeOnly names the free box day like box.restrictedNote does; it must match the Config day it describes.
	t.test("box.freeOnly and box.restrictedNote name Config.Economy.Daily.freeBoxDay", function()
		local Config = t.requireShared("Config")
		local day = tostring(Config.Economy.Daily.freeBoxDay)
		expect.equal(Strings.box.freeOnly, `Free on day {day} of Daily Rewards`)
		expect.truthy(string.find(Strings.box.restrictedNote, `day {day} of Daily Rewards`, 1, true) ~= nil)
	end)

	-- Foam fix batch (2026-10-09): every screen's header tab is in title case ("Squishies", "Shop", "Settings"), so the
	-- Quests and Daily tabs read their own panelTitle and the Inspect chip is in sentence case like the card chips; the
	-- world's board and sign keep their capitals (§7.7, WorldLayout_Test).
	t.test("the screen titles share one casing; the world signs keep theirs", function()
		expect.equal(Strings.quest.panelTitle, "Quests")
		expect.equal(Strings.daily.panelTitle, "Daily Rewards") -- UI FINAL R3: the design's title (H:386)
		expect.equal(Strings.inspect.previewNotOwned, "Preview · Not owned")
		expect.equal(Strings.resolve("quest.title"), "QUESTS")
		expect.equal(Strings.resolve("daily.title"), "DAILY REWARD")
		for _, title in { Strings.quest.panelTitle, Strings.daily.panelTitle, Strings.inspect.previewNotOwned } do
			expect.truthy(string.upper(title) ~= title) -- never all capitals
		end
	end)

	-- Foam fix 2 (2026-10-09): the regular Grip card's goal line is a short form of grip.goalRank (the panel and the
	-- compact layout's toast keep it), so it fits the card's info column on one line.
	t.test("the Grip card's short goal lines exist with their placeholders", function()
		expect.equal(
			Strings.format(Strings.grip.hudGoalRank, { rank = "Firm Grip", level = 10 }),
			"Next: Firm Grip at Lv 10"
		)
	end)

	t.test("a key hint reads as the action followed by its key", function()
		expect.equal(
			Strings.format(
				Strings.controls.keyHint,
				{ action = Strings.common.inspect, key = Strings.controls.key.inspectKeyboard }
			),
			"Inspect (V)"
		)
	end)

	-- Squeeze anywhere (spec 2026-10-11 §5): squeezing pays anywhere in the lobby; pads only give a boost.
	t.test("the squeeze-anywhere texts: onboarding, Inspect, the off-pad label and the Grip panel", function()
		local hint = Strings.onboarding.squeezeHint
		-- Lobby HUD spec 2026-10-11 §2: a click or a tap on the world squeezes (no Squeeze button any more).
		expect.deepEqual(
			{ hint.keyboard, hint.touch, hint.gamepad },
			{ "Click or press E", "Tap the screen", "Press X" } -- each starts a sentence
		)
		-- Phase 5: a pad no longer boosts a squeeze, so the step stops at the hint.
		expect.equal(
			Strings.format(Strings.onboarding.squeeze, { squeezeHint = hint.keyboard }),
			"Squeeze squishies anywhere to earn Coins. Click or press E."
		)
		expect.equal(
			Strings.format(Strings.onboarding.squeeze, { squeezeHint = hint.touch }),
			"Squeeze squishies anywhere to earn Coins. Tap the screen."
		)
		expect.equal(Strings.inspect.preview, "Preview only. Squeeze in the lobby to earn Coins.")
		-- The floating label reads what a squeeze pays (no pad name).
		expect.equal(
			Strings.format(Strings.grip.stationLabelBase, { coins = "1", grip = "10" }),
			"+1 Coins · +10 Grip per squeeze"
		)
		-- No text sends the player to a mat any more.
		for _, key in { "onboarding.squeeze", "inspect.preview", "squishy.powerNote", "grip.limitNote" } do
			local text = Strings.resolve(key)
			expect.truthy(type(text) == "string" and string.find(string.lower(text), "mat", 1, true) == nil)
		end
		-- The mat, pad-level, limit and locked-button texts are gone with what showed them; Phase 5: so are the pad label
		-- and the old "Coins per squeeze" line (a squishy's capsule power replaces it).
		for _, key in
			{
				"reason.squeeze.notAtStation",
				"reason.squeeze.needGrip",
				"squeeze.limitLabel",
				"squeeze.limitEmpty",
				"squeeze.limitHelp",
				"grip.padLockedButton",
				"grip.stationLabel",
				"inspect.coinsPerSqueeze",
				"inspect.coinsPerSqueezeSub",
			}
		do
			expect.equal(Strings.resolve(key), nil)
		end
	end)

	-- Phase 5 (build plan; lobby bases spec 2026-10-11 §9; progression spec 2026-10-12 §3-§6) ---------------------------

	t.test("no pad or onboarding text claims a squeeze bonus any more", function()
		for _, key in
			{
				"grip.limitNote",
				"grip.panelIntro",
				"grip.intro",
				"onboarding.squeeze",
			}
		do
			local text = string.lower(Strings.resolve(key) :: string)
			expect.equal(string.find(text, "per squeeze", 1, true), nil)
			expect.equal(string.find(text, "boost", 1, true), nil)
			expect.equal(string.find(text, "better pads", 1, true), nil)
			expect.equal(string.find(text, "better squeeze pads", 1, true), nil)
		end
	end)

	-- Phase 6 (build plan): slow training is gone.
	t.test("slow training is gone: its popup, help and bank texts are gone and no text names it", function()
		for _, key in { "grip.afkPopup", "grip.afkHelp", "grip.afkBank" } do
			expect.equal(Strings.resolve(key), nil)
		end
		local naming: { string } = {}
		local function scan(node: any, path: string)
			if type(node) == "string" then
				local text = string.lower(node)
				if string.find(text, "slow training", 1, true) or string.find(text, "slow-training", 1, true) then
					table.insert(naming, path)
				end
			elseif type(node) == "table" then
				for key, child in node do
					scan(child, path .. "." .. tostring(key))
				end
			end
		end
		scan(Strings, "Strings")
		table.sort(naming)
		expect.deepEqual(naming, {})
	end)

	-- Phase 6 (build plan): the trainers are gone too.
	t.test("the trainers are gone: their names, card, goal, toast and reason texts; no text names one", function()
		expect.equal((Strings.grip :: any).trainer, nil)
		expect.equal((Strings.reason :: any).trainer, nil)
		for _, key in
			{
				"grip.upgradeBadge",
				"grip.goalUpgrade",
				"grip.goalTrainer",
				"grip.hudGoalTrainer",
				"grip.trainerHeader",
				"grip.trainerNow",
				"grip.trainerNext",
				"grip.trainerBuy",
				"grip.trainerNeedLevel",
				"grip.trainerNeedCoins",
				"grip.trainerMax",
				"grip.trainerNote",
				"grip.trainerBought",
			}
		do
			expect.equal(Strings.resolve(key), nil)
		end
		local naming: { string } = {}
		local function scan(node: any, path: string)
			if type(node) == "string" then
				if string.find(string.lower(node), "trainer", 1, true) then
					table.insert(naming, path)
				end
			elseif type(node) == "table" then
				for key, child in node do
					scan(child, path .. "." .. tostring(key))
				end
			end
		end
		scan(Strings, "Strings")
		table.sort(naming)
		expect.deepEqual(naming, {})
	end)

	-- Phase 6 (build plan): the giant pads and the Jelly gates are gone too.
	t.test("the giant pads and Jelly gates are gone: their names, cards, signs, toast and goal texts", function()
		expect.deepEqual(Strings.grip.pad, { foam = "Foam Mats" })
		for _, key in
			{
				"grip.goalPad",
				"grip.hudGoalPad",
				"grip.padsHeader",
				"grip.padNeeds",
				"grip.padPerks",
				"grip.padPerksBase",
				"grip.padOpen",
				"grip.padLocked",
				"grip.showMe",
				"grip.padUnlocked",
				"grip.gymTitle",
				"grip.signLocked",
				"grip.signOpen",
			}
		do
			expect.equal(Strings.resolve(key), nil)
		end
	end)

	t.test("pens3 phase 3: squishy.power keeps capsule.power's text; the capsule card texts are gone", function()
		expect.equal(Strings.format(Strings.squishy.power, { n = 16 }), "x16 power")
		expect.equal(Strings.squishy.powerNote, "Pen Coins multiplier")
		local gone = { "capsule.title", "capsule.power", "capsule.powerNote", "base.capsuleLevel", "base.unlockPrice" }
		for _, key in gone do
			expect.equal(Strings.resolve(key), nil)
		end
	end)

	-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): no squeeze panel, no Squeeze button, no dock.
	t.test("the tap-to-squeeze texts: the Inspect step opens Squishies; no text names the Squeeze button", function()
		expect.equal(
			Strings.onboarding.inspect,
			"Open Squishies, press Inspect to see your squishy in 3D. Spin it, then try Squeeze."
		)
		expect.equal(Strings.grip.holdPaused, "Squeeze again to keep training.")
		-- The Squeeze button's key texts went with the button.
		for _, key in { "controls.key.squeezeKeyboard", "controls.key.squeezeGamepad" } do
			expect.equal(Strings.resolve(key), nil)
		end
		-- "then try Squeeze" is Inspect's own Squeeze button, which stays.
		expect.equal(Strings.controls.squeeze, "Squeeze")
	end)

	-- Final polish (2026-10-11): the duel key hints name the dash (spec phase 5: C / ButtonB) and the first-person
	-- squeeze (F / ButtonX) after DESIGN's throw and ultimate; the lane warning under the duel bar. Feature 1
	-- (2026-10-11): and the catch after the throw (RMB or E / ButtonL1; design: html:96).
	t.test("the duel key hints name the catch, the dash and the squeeze; the lane warning exists", function()
		expect.equal(Strings.duel.hintMouse, "Click Throw · RMB/E Catch · Q Ultimate · C Dash · F Squeeze")
		expect.equal(Strings.duel.hintGamepad, "R2 Throw · L1 Catch · L2 Ultimate · B Dash · X Squeeze")
		expect.equal(Strings.duel.hintMouseNoUlt, "Click Throw · RMB/E Catch · C Dash · F Squeeze")
		expect.equal(Strings.duel.hintGamepadNoUlt, "R2 Throw · L1 Catch · B Dash · X Squeeze")
		local key = Strings.duel.key
		expect.equal(key.dashMouse, "C")
		expect.equal(key.dashGamepad, "B")
		expect.equal(key.squeezeMouse, "F")
		expect.equal(key.squeezeGamepad, "X")
		expect.equal(key.catchMouse, "RMB/E")
		expect.equal(key.catchGamepad, "L1")
		expect.equal(Strings.duel.inLane, "In the lane!")
	end)

	-- Feature 1 (2026-10-11): the catch's words (design: html:88, 352, 563), the touch button and the refusal codes.
	t.test("the catch's words, its button and its refusal codes", function()
		expect.equal(Strings.duel.caught, "CAUGHT!")
		expect.equal(Strings.duel.squished, "SQUISHED!")
		expect.equal(Strings.duel.catchPrompt, "Catch!")
		expect.equal(Strings.format(Strings.duel.catchPromptKey, { key = "E" }), "Catch! E")
		expect.equal(Strings.controls.catch, "Catch")
		for _, code in { "catch.context", "catch.cooldown", "catch.busy", "throw.busy" } do
			local text = Strings.reasonText(code)
			expect.truthy(type(text) == "string" and text ~= "" and text ~= code)
		end
	end)

	t.test(
		"Batch 1: the tutorial points at the Shop; pens3 phase 3: no capsule step, goal, UP! or reason text",
		function()
			expect.equal(Strings.resolve("onboarding.equip"), nil)
			expect.equal(Strings.resolve("onboarding.firstBoxShop"), nil)
			expect.equal( -- pens3 phase 5: the first of each Common costs the Welcome price
				Strings.onboarding.firstBox,
				"Get a new squishy in the Shop: your first of each Common has a Welcome price! {coins}/{goal} Coins"
			)
			for _, key in
				{
					"onboarding.capsule",
					"grip.goalCapsuleReady",
					"grip.goalUnlockReady",
					"grip.goalCapsule",
					"grip.goalUnlock",
					"grip.hudGoalCapsule",
					"capsule.up",
					"reason.capsule.paused",
				}
			do
				expect.equal(Strings.resolve(key), nil)
			end
		end
	)

	t.test("daily: the welcome back line names the waiting day; no daily text speaks of a reset", function()
		expect.equal(Strings.format(Strings.daily.welcomeBack, { n = 4 }), "Welcome back! Day 4 is waiting.")
		expect.equal(Strings.resolve("daily.streakReset"), nil)
		for key, value in Strings.daily do
			local text = string.lower(value)
			if string.find(text, "reset", 1, true) or string.find(text, "restart", 1, true) then
				error(`daily.{key} speaks of a reset: {value}`)
			end
		end
	end)

	t.test("Batch 3: the duel pad, Rematch, Invite, player list and weekly board texts", function()
		expect.equal(Strings.duel.padWaitingMint, "Get a friend on the mint pad across from you to duel!")
		expect.equal(Strings.duel.padWaitingStrawberry, "Get a friend on the strawberry pad across from you to duel!")
		expect.equal(
			Strings.format(Strings.duel.padReady, { name = "Ana", seconds = 3 }),
			"Duel with Ana in 3 seconds! Step off to cancel."
		)
		expect.equal(Strings.duel.rematch, "Rematch")
		expect.equal(Strings.duel.rematchWaiting, "Waiting…")
		expect.equal(Strings.format(Strings.duel.rematchWaitingFor, { name = "Ana" }), "Waiting for Ana…")
		expect.equal(Strings.format(Strings.duel.rematchAsked, { name = "Ana" }), "Ana wants a rematch!")
		expect.equal(Strings.duel.rematchStarting, "Starting…")
		expect.equal(Strings.queue.inviteFriends, "Invite friends")
		expect.equal(Strings.social.statWins, "Wins")
		expect.equal(Strings.social.statLevel, "Grip Lv")
		local board = Strings.board
		expect.equal(board.title, "Top Wins This Week")
		expect.equal(Strings.format(board.line.many, { rank = 1, name = "Ana", wins = "12" }), "1. Ana · 12 wins")
		expect.equal(Strings.format(board.line.one, { rank = 2, name = "Bo", wins = "1" }), "2. Bo · 1 win")
		expect.equal(board.empty, "No wins yet this week. Be the first!")
		expect.equal(board.loading, "Checking the board…")
		expect.equal(board.unavailable, "The board is taking a break. Check back soon!")
		expect.equal(board.someone, "A player")
		expect.equal(Strings.format(board.you.many, { rank = 3, n = "12" }), "You: #3 · 12 wins")
		expect.equal(Strings.format(board.you.one, { rank = 3, n = "1" }), "You: #3 · 1 win")
		expect.equal(Strings.format(board.youUnranked.many, { n = "4" }), "You: 4 wins this week")
		expect.equal(board.youNone, "Win a duel against another player to get on the board!")
		for _, text in { Strings.queue.inviteFriends, board.title, board.youNone, Strings.duel.padWaitingMint } do
			local lower = string.lower(text)
			expect.falsy(string.find(lower, "robux", 1, true))
			expect.falsy(string.find(lower, "reward", 1, true))
		end
	end)

	-- Pens3 phase 1: the codes PenMath.buyDecision and PenService send (the others are shared: net.invalid,
	-- data.notReady, economy.notEnoughCoins, inventory.lockedInDuel).
	t.test("pens3 phase 1: every pen refusal code has a text under reason.pen", function()
		for _, name in { "max", "paused", "priceChanged" } do
			local text = Strings.resolve("reason.pen." .. name)
			expect.truthy(type(text) == "string" and text ~= "")
			expect.equal(Strings.reasonText("pen." .. name), text)
		end
	end)

	-- Pens3 phase 6: PenPlace / PenLock's own codes (the others are shared: net.invalid, data.notReady,
	-- inventory.notOwned, inventory.full, inventory.lockedInDuel).
	t.test("pens3 phase 6: the pen screen's refusal codes and texts, with their placeholders, calm", function()
		for _, name in { "spotClosed", "changePaused" } do
			local text = Strings.resolve("reason.pen." .. name)
			expect.truthy(type(text) == "string" and text ~= "")
			expect.equal(Strings.reasonText("pen." .. name), text)
		end
		for _, code in { "inventory.notOwned", "inventory.full", "inventory.lockedInDuel" } do
			expect.truthy(Strings.resolve("reason." .. code) ~= nil)
		end
		local screen = Strings.pen.screen
		expect.equal(
			Strings.format(screen.count, { placed = 2, spots = 3, toys = 4, max = 50 }),
			"Pen 2/3 · Toy Box 4/50"
		)
		expect.equal(Strings.format(screen.pickHint, { name = "Toast" }), "Tap a pen spot for Toast.")
		expect.equal(Strings.format(screen.level, { level = 7 }), "Lv 7")
		for _, key in { "title", "penHeading", "toyHeading", "empty", "toyEmpty", "selectHint", "place", "putAway" } do
			expect.truthy(type(screen[key]) == "string" and screen[key] ~= "")
		end
		for _, key in { "move", "swap", "lock", "unlock", "open" } do
			expect.truthy(type(screen[key]) == "string" and screen[key] ~= "")
		end
		for _, text in { screen.title, screen.selectHint, screen.pickHint, screen.toyEmpty } do
			expect.falsy(string.find(string.lower(text), "now", 1, true))
		end
	end)

	-- Pens3 phases 7-8: the codes PenMath.sellDecision / buyBackDecision / fuseDecision and PenService send (the others
	-- are shared: net.invalid, data.notReady, inventory.notOwned, inventory.full, inventory.lockedInDuel,
	-- pen.changePaused, pen.paused, economy.notEnoughCoins).
	t.test("pens3 phases 7-8: sell, buy-back and fusion codes and texts, true and calm", function()
		for _, name in
			{ "sellStarter", "locked", "lastCopy", "nothingToSell", "buyBackGone", "fuseMismatch", "fuseTop" }
		do
			local text = Strings.resolve("reason.pen." .. name)
			expect.truthy(type(text) == "string" and text ~= "")
			expect.equal(Strings.reasonText("pen." .. name), text)
		end
		local screen = Strings.pen.screen
		expect.equal(
			Strings.format(screen.confirmSell, { name = "Toast", coins = "1,000" }),
			"Sell Toast for 1,000 Coins?"
		)
		local all = screen.confirmSellAll
		expect.equal(
			Strings.format(Strings.plural(1, all.one, all.many), { n = 1, coins = "1K" }),
			"Sell 1 squishy for 1K Coins?"
		)
		expect.equal(
			Strings.format(Strings.plural(4, all.one, all.many), { n = 4, coins = "4K" }),
			"Sell 4 squishies for 4K Coins?"
		)
		expect.equal(Strings.format(screen.sellNote, { minutes = 10 }), "You can buy it back for 10 minutes.")
		expect.truthy(string.find(Strings.format(screen.sellAllNote, { minutes = 10 }), "locked", 1, true))
		expect.equal(
			Strings.format(screen.confirmBuyBack, { name = "Toast", coins = "1,000" }),
			"Buy back Toast for 1,000 Coins?"
		)
		expect.equal(
			Strings.format(screen.confirmFuse, { name = "Toast", result = "Golden Toast" }),
			"Fuse 3 Toast into 1 Golden Toast?"
		)
		local fuseNote = Strings.format(screen.fuseNote, { level = 7, rate = "+60/s" })
		expect.truthy(string.find(fuseNote, "Lv 7", 1, true))
		expect.truthy(string.find(string.lower(fuseNote), "free", 1, true)) -- no luck, free (D1:227)
		expect.equal(Strings.format(screen.formName, { form = screen.forms[1], name = "Toast" }), "Golden Toast")
		expect.equal(screen.forms[2], "Rainbow")
		expect.equal(Strings.format(screen.formLevel, { form = "Golden", level = 3 }), "Golden · Lv 3")
		expect.equal(Strings.format(screen.soldTime, { minutes = 7 }), "7 min")
		expect.equal(Strings.format(screen.fused, { name = "Golden Toast" }), "You made a Golden Toast!")
		for _, key in { "sell", "sellAll", "holdSell", "buyBack", "fuse", "coatNote", "soldHeading", "selectHint" } do
			expect.truthy(type(screen[key]) == "string" and screen[key] ~= "")
		end
		-- Calm: the buy-back time is information, never pressure.
		for _, text in
			{ screen.soldHeading, screen.sellNote, screen.sellAllNote, screen.soldTime, screen.confirmBuyBack }
		do
			for _, word in { "hurry", "now", "quick", "last chance", "expire", "only" } do
				expect.falsy(string.find(string.lower(text), word, 1, true))
			end
		end
	end)

	t.test("pens3 phase 1: the pen sign, prompt, coin label, onboarding step and Grip goal texts", function()
		expect.equal(Strings.pen.sign.title, "PEN SPACE")
		expect.equal(Strings.pen.sign.canBuy, "Walk up to buy")
		expect.equal(Strings.format(Strings.pen.sign.needMore, { coins = "1,200" }), "Need 1,200 more")
		expect.equal(Strings.pen.sign.max, "MAX")
		expect.equal(Strings.pen.prompt.action, "Buy")
		expect.equal(Strings.pen.prompt.object, "Pen space")
		expect.equal(Strings.format(Strings.pen.rate, { coins = "640" }), "+640/s")
		expect.equal(
			Strings.resolve("onboarding.pen"),
			"Your squishies earn Coins in your pen. Buy more pen space at the sign!"
		)
		-- GripMath.nextGoal step 0 (the client half): {need} is the next spot's price (GripController.goalArgs).
		expect.equal(Strings.format(Strings.grip.goalPen, { need = "1,500" }), "Next: pen space 1,500")
		expect.equal(Strings.grip.goalPenReady, "Buy pen space · READY!")
		-- No pen text pushes or times a kid (calm signs, no BUY NOW).
		for _, text in
			{ Strings.pen.sign.title, Strings.pen.sign.canBuy, Strings.pen.sign.needMore, Strings.grip.goalPen }
		do
			expect.falsy(string.find(string.lower(text), "now", 1, true))
			expect.falsy(string.find(text, "!", 1, true))
		end
	end)

	t.test("pens3 phase 11: the shelf's refusal code, sign, prompt and screen headings, true and calm", function()
		local text = Strings.resolve("reason.pen.shelfMax")
		expect.truthy(type(text) == "string" and text ~= "")
		expect.equal(Strings.reasonText("pen.shelfMax"), text)
		expect.equal(Strings.pen.shelfSign.title, "SHELF SPOTS") -- P3D:255
		expect.equal(Strings.pen.shelfPrompt.action, "Buy")
		expect.equal(Strings.pen.shelfPrompt.object, "Shelf spots")
		local screen = Strings.pen.screen
		expect.equal(Strings.format(screen.shelfHeading, { placed = 1, open = 2 }), "On your shelf 1/2")
		expect.equal(screen.topHeading, "TOP spot")
		-- Wb: the window's shelf BUY button (short labels: why it is off goes on the screen's reason row).
		expect.equal(Strings.format(screen.buyRow, { coins = "31M" }), "BUY ROW 31M")
		expect.equal(Strings.format(screen.buyTop, { coins = "140T" }), "BUY TOP 140T")
		expect.equal(screen.shelfMax, "SHELF MAX")
		for _, line in
			{
				Strings.pen.shelfSign.title,
				Strings.pen.shelfPrompt.object,
				screen.shelfHeading,
				screen.buyRow,
				screen.buyTop,
				screen.shelfMax,
			}
		do
			expect.falsy(string.find(string.lower(line), "now", 1, true))
			expect.falsy(string.find(line, "!", 1, true))
		end
	end)

	t.test("pens3 phase 10: the gate's texts: BASE n, the heart, 1 visitor and N visitors (P3D:250, :277)", function()
		expect.equal(Strings.format(Strings.pen.gate.base, { n = 3 }), "BASE 3")
		expect.equal(Strings.pen.gate.heart, "\u{2665}")
		expect.equal(Strings.format(Strings.pen.gate.visitor, { count = 1 }), "1 visitor")
		expect.equal(Strings.format(Strings.pen.gate.visitors, { count = 0 }), "0 visitors")
	end)

	t.test("pens3 phase 4: the away pop-up's texts exist with their placeholders and never press a kid", function()
		expect.equal(Strings.format(Strings.common.coinsAmount, { coins = "1,800" }), "1,800 Coins") -- the prize line
		expect.equal(
			Strings.format(Strings.away.body, { time = "1 h" }),
			"Your pen kept earning while you were away (1 h)."
		)
		expect.equal(Strings.format(Strings.away.hours, { h = 3 }), "3 h")
		expect.equal(Strings.format(Strings.away.hoursMinutes, { h = 1, m = 2 }), "1 h 2 min")
		expect.equal(Strings.format(Strings.away.minutes, { m = 10 }), "10 min")
		expect.equal(Strings.away.underMinute, "less than a minute")
		-- A gift, not a deal: no countdown, no "claim now", nothing to lose.
		for _, word in { "now", "hurry", "lose", "left", "expire", "only", "claim" } do
			expect.falsy(string.find(string.lower(Strings.away.body), word, 1, true))
		end
	end)

	t.test("pens3 phase 5: Toy Box full, the Welcome price, the next box item and copies, all true and calm", function()
		expect.equal(Strings.reasonText("inventory.full"), "Your Toy Box is full. Make room first!")
		expect.equal(Strings.format(Strings.shop.welcomePrice, { coins = "3K" }), "Welcome price: first one 3K")
		expect.equal(Strings.format(Strings.box.nextItem, { name = "Toast" }), "Next in this box: Toast")
		expect.equal(
			Strings.format(Strings.onboarding.firstBox, { coins = "1,200", goal = "3,000" }),
			"Get a new squishy in the Shop: your first of each Common has a Welcome price! 1,200/3,000 Coins"
		)
		-- Copies: a squishy you own again is never turned into Coins.
		expect.falsy(string.find(Strings.box.footer, "Coins", 1, true))
		expect.truthy(string.find(Strings.box.footer, "copy", 1, true))
		-- Restricted accounts open boxes in a fixed order and see what comes next.
		expect.truthy(string.find(Strings.box.restrictedNote, "fixed order", 1, true))
		expect.truthy(string.find(Strings.box.restrictedNote, "next", 1, true))
		-- The Welcome price never runs out: no timer, no pressure.
		for _, text in { Strings.shop.welcomePrice, Strings.box.nextItem, Strings.onboarding.firstBox } do
			for _, word in { "now", "hurry", "left", "expire", "only", "today", "limited", "ends" } do
				expect.falsy(string.find(string.lower(text), word, 1, true))
			end
		end
		-- The texts copies and fixed orders made untrue are gone with their last readers.
		for _, key in
			{
				"reason.box.restricted",
				"reason.box.complete",
				"reason.shop.owned",
				"box.refundLine",
				"box.revealRefund",
				"box.shopDirect",
			}
		do
			expect.equal(Strings.resolve(key), nil)
		end
	end)

	-- Pens3 phase 9: every food's name, the codes PenMath.buyFoodDecision / feedDecision and PenService send (the
	-- others are shared: net.invalid, data.notReady, inventory.notOwned, inventory.lockedInDuel, pen.changePaused,
	-- pen.paused, pen.priceChanged, economy.notEnoughCoins) and the pen screen's food texts.
	t.test("pens3 phase 9: food names, refusal codes and the pen screen's food texts, true and calm", function()
		local Config = t.requireShared("Config")
		for _, food in Config.Economy.Food.foods do
			local name = Strings.resolve(food.nameKey)
			expect.truthy(type(name) == "string" and name ~= "")
		end
		expect.equal(Strings.resolve("food.candyDrop.name"), "Candy Drop")
		expect.equal(Strings.resolve("food.haloPuff.name"), "Halo Puff")
		for _, code in { "food.notYet", "food.full", "food.notEnough", "pen.maxLevel", "pen.nothingToFeed" } do
			local text = Strings.resolve("reason." .. code)
			expect.truthy(type(text) == "string" and text ~= "")
			expect.equal(Strings.reasonText(code), text)
		end
		local screen = Strings.pen.screen
		expect.equal(
			Strings.format(screen.feedHint, { level = 3, next = 4, pieces = 2, food = "Candy Drop" }),
			"Lv 3 -> 4: 2 Candy Drop"
		)
		expect.equal(Strings.format(screen.feedTop, { level = 10 }), "Lv 10: the top level for now.")
		expect.equal(Strings.format(screen.needFood, { missing = 2, food = "Candy Drop" }), "Need 2 more Candy Drop")
		local item = Strings.format(screen.foodItem, { n = 12, food = "Candy Drop" })
		expect.equal(Strings.format(screen.foodLine, { list = item }), "Your food: 12 Candy Drop")
		expect.equal(Strings.format(screen.foodEach, { coins = "400" }), "400 each")
		expect.equal(Strings.format(screen.foodHave, { n = 3 }), "You have 3")
		expect.equal(
			Strings.format(screen.foodBuyHint, { food = "Candy Drop", coins = "400", n = 3 }),
			"Candy Drop: 400 Coins each. You have 3."
		)
		expect.equal(Strings.format(screen.buyFood, { n = 10 }), "BUY 10")
		expect.equal(Strings.format(screen.foodNote, { coins = "2,744" }), "Food inside: 2,744 Coins, not refunded.")
		local up = screen.levelsUp
		expect.equal(Strings.format(Strings.plural(1, up.one, up.many), { n = 1 }), "+1 level")
		expect.equal(Strings.format(Strings.plural(3, up.one, up.many), { n = 3 }), "+3 levels")
		for _, key in { "feed", "feedAll", "foodHeading", "foodNone" } do
			expect.truthy(type(screen[key]) == "string" and screen[key] ~= "")
		end
		expect.truthy(string.find(screen.selectHint, "feed", 1, true))
		-- Calm: buying food never presses a kid.
		for _, text in { screen.foodHeading, screen.foodBuyHint, screen.foodEach, screen.buyFood, screen.foodNone } do
			for _, word in { "hurry", "now", "quick", "last chance", "only", "!" } do
				expect.falsy(string.find(string.lower(text), word, 1, true))
			end
		end
	end)
end
