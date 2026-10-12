--!strict
-- Strings_Test: unit tests for ReplicatedStorage.Shared.Strings. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.2, §2.10): every server reason code of §2.10 has a text under `reason.*`, read with
-- Strings.reasonText(code). Part 4: the duel, queue and practice texts DESIGN quotes keep their exact wording, and
-- every text the Part 4 screens and DuelResult.reasonKey use exists. Part 5: the data banners, restart notice,
-- settings, Squishies and every §17.7 Grip text keep DESIGN's wording; the Part 5 codes and readings exist; no duel
-- text mentions Grip (§17.2 rule 1). Part 7: the
-- §17.7 trainer reason texts and quest.starterTask.jelly keep DESIGN's wording; the Part 7 readings (box.title,
-- box.freeOnly, box.boardHeader, box.boardLine, daily.today) exist, and box.freeOnly names the Config free box day.
-- Foam fix 2: the Grip card's short goal lines (grip.hudGoal*); grip.stationLabel and grip.idleBody keep DESIGN's words
-- with a line break. Squeeze anywhere (spec 2026-10-11 §5): the onboarding step, Inspect's preview lines, the off-pad
-- label (grip.stationLabelBase), the Foam Mats card (grip.padPerksBase) and grip.limitNote never send you to a mat;
-- the mat, pad-level, limit and locked-button texts are gone. Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): the
-- squeeze hints name a click or a tap, grip.holdPaused names no button (it left DESIGN's words), the Inspect step opens
-- Squishies, and the Squeeze button's key texts are gone. Final polish (2026-10-11): the duel key hints also name the
-- dash and the squeeze (they left DESIGN's "Click Throw · Q Ultimate"), and the "In the lane!" warning exists.
-- (tools/check.ps1 (c) is meant to cover the codes the server actually emits; until it exists, this case pins the
-- §2.10 list.)

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- DESIGN §2.10, in its order.
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
	"box.restricted",
	"box.checking",
	"box.unknown",
	"box.complete",
	"box.paused",
	"box.saving",
	"shop.priceChanged",
	"shop.notForSale",
	"shop.owned",
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
	["settings.cameraShake"] = "Camera shake",
	["settings.showTips"] = "Show tips",
	["settings.replayTutorial"] = "Replay tutorial",
	["settings.noMusic"] = "No music yet",
	["settings.noSfx"] = "No sound effects yet",
	["settings.firstPerson"] = "First-person duels", -- first-person spec 2026-10-10 §3.8
	["inventory.showNotOwned"] = "Show not owned",
	["inventory.new"] = "NEW",
	["common.equipped"] = "Equipped",
	["common.notOwned"] = "Not owned",
	-- §17.7 HUD
	["grip.hudLevel"] = "Grip Lv {level} · {rank}",
	["grip.hudLevelCompact"] = "Lv {level} · {rank}",
	["grip.hudBar"] = "{have} / {need} Grip",
	["grip.hudMax"] = "Max level",
	["grip.restedChip"] = "Double Grip: about {minutes} min",
	["grip.upgradeBadge"] = "Upgrade available",
	-- §17.7 next goal
	["grip.goalUpgrade"] = "Upgrade ready: {trainer} for {coins} Coins",
	["grip.goalPad"] = "Next: {pad} at Grip Lv {level}",
	["grip.goalTrainer"] = "Next: {trainer} unlocks at Grip Lv {level}",
	["grip.goalRank"] = "Next rank: {rank} at Grip Lv {level}",
	["grip.goalMax"] = "Max level! You're a Squish Master.",
	-- §17.7 at a pad
	["grip.popup"] = "+{n} Grip",
	["grip.popupDouble"] = "+{n} Grip (x{mult})",
	["grip.afkPopup"] = "+{n} Grip (slow training)",
	-- Foam fix 2 (2026-10-09): DESIGN's words with the pad name on its own line (one line left "squeeze" alone).
	["grip.stationLabel"] = "{pad}\n+{coins} Coins · +{grip} Grip per squeeze",
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
	["grip.pad.jelly"] = "Jelly Pad",
	["grip.pad.marshmallow"] = "Marshmallow Pad",
	["grip.pad.royal"] = "Royal Cushion",
	["grip.trainer.foam"] = "Foam Ball",
	["grip.trainer.sponge"] = "Sponge Ball",
	["grip.trainer.rubber"] = "Rubber Ball",
	["grip.trainer.spring"] = "Spring Gripper",
	["grip.trainer.jelly"] = "Jelly Gripper",
	["grip.trainer.steel"] = "Steel Gripper",
	["grip.trainer.gold"] = "Gold Gripper",
	["grip.trainer.diamond"] = "Diamond Gripper",
	-- §17.7 panel
	["grip.panelTitle"] = "Grip Training",
	["grip.panelIntro"] = "Every squeeze trains your Grip. Higher Grip opens better squeeze pads.",
	["grip.padsHeader"] = "Squeeze pads",
	["grip.padNeeds"] = "Needs Grip Lv {level}",
	["grip.padPerks"] = "+{coins} Coins and x{mult} Grip per squeeze",
	["grip.padOpen"] = "Open",
	["grip.padLocked"] = "Locked",
	["grip.showMe"] = "Show me",
	["grip.trainerHeader"] = "Trainer",
	["grip.trainerNow"] = "Now: {trainer} (+{grip} Grip per squeeze)",
	["grip.trainerNext"] = "Next: {trainer} (+{grip} Grip per squeeze)",
	["grip.trainerBuy"] = "Upgrade: {coins} Coins",
	["grip.trainerNeedLevel"] = "Reach Grip Lv {level}",
	["grip.trainerNeedCoins"] = "Need {coins} more Coins",
	["grip.trainerMax"] = "Best trainer owned!",
	["grip.trainerNote"] = "Upgrades make training faster. They never change duels.",
	["grip.restedHelp"] = "Double Grip fills up over time, even while you're away. While it lasts, each squeeze trains x{mult} Grip.",
	-- Spec 2026-10-11 §5: no hourly limit any more; the note says where squeezing pays.
	["grip.limitNote"] = "Every squeeze earns Coins and trains Grip, anywhere in the lobby. Squeeze pads give a boost.",
	["grip.afkHelp"] = "Standing on an open pad slowly trains Grip, even when you're not squeezing. It never gives Coins, and it stops if Roblox disconnects you for being idle.",
	["grip.afkBank"] = "Slow training at full speed: about {minutes} min left",
	["grip.duelNote"] = "Grip only helps in the lobby. It never changes duels, and it can't be bought.",
	-- §17.7 toasts
	["grip.levelUp"] = "Grip Lv {level}!",
	["grip.padUnlocked"] = "{pad} unlocked! +{coins} Coins and x{mult} Grip per squeeze there.",
	["grip.rankUp"] = "{name} reached {rank}!",
	["grip.trainerBought"] = "{trainer} unlocked! +{grip} Grip per squeeze.",
	["grip.intro"] = "You trained your Grip! Squeeze more to open better pads.",
	["grip.welcome"] = "Double Grip is full: your first squeezes train x{mult} Grip!",
	["grip.welcomeBack"] = "Welcome back! Double Grip: about {minutes} min.",
	["grip.headStart"] = "Your past squeezes count: you start at Grip Lv {level}!",
	-- §17.7 idle card and world
	["grip.idleTitle"] = "Still there?",
	-- Foam fix 2: DESIGN's two sentences, one per line (the wrap broke the line after "Slow").
	["grip.idleBody"] = "Roblox disconnects players who are idle for 20 minutes.\nSlow training stops when that happens.",
	["grip.idleButton"] = "Keep going",
	["grip.gymTitle"] = "GRIP GYM",
	["grip.signLocked"] = "Needs Grip Lv {level} · You: Lv {have}",
	["grip.signOpen"] = "Open · +{coins} Coins · x{mult} Grip",
	["grip.nameplate"] = "Lv {level} · {rank}",
}

-- Part 5 texts with no DESIGN wording (readings) that the Part 5 screens read.
local PART5_KEYS = {
	"inventory.title",
	"inventory.filterCount",
	"inventory.filterAll",
	"inventory.collected",
	"inventory.empty",
	"inventory.goToBoxes",
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
	"grip.padUnlocked",
	"grip.rankUp",
	"grip.welcome",
	"grip.welcomeBack",
	"grip.headStart",
	"grip.trainerBought",
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
	-- switch "First-person duels" (first-person spec 2026-10-10 §3.8); an in-game "Reduce motion" switch is an
	-- unapproved §16 proposal, so the settings texts hold nothing else.
	t.test("the settings texts are exactly §11.6's rows and the first-person switch (no Reduce motion)", function()
		local expected = {
			"cameraShake",
			"firstPerson",
			"music",
			"noMusic",
			"noSfx",
			"replayTutorial",
			"sfx",
			"showTips",
			"title",
		}
		local keys = {}
		for key in Strings.settings do
			table.insert(keys, key)
		end
		table.sort(keys)
		expect.deepEqual(keys, expected)
		expect.equal(Strings.resolve("settings.reducedMotion"), nil)
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

	-- G6 from the Strings side: every rank, pad and trainer of Config.Grip has its name.
	t.test("every Config.Grip rank, pad and trainer has a grip.* name", function()
		local Config = t.requireShared("Config")
		local missing = {}
		local groups: { { prefix: string, list: { any } } } = {
			{ prefix = "grip.rank.", list = Config.Grip.Ranks },
			{ prefix = "grip.pad.", list = Config.Grip.Pads },
			{ prefix = "grip.trainer.", list = Config.Grip.Trainer },
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

	-- Part 7 ----------------------------------------------------------------------------------------------------

	-- §17.7 quotes these word for word; the trainer codes are server reason codes (§17.10).
	t.test("Part 7 texts DESIGN quotes keep their exact wording", function()
		local wording: { [string]: string } = {
			["reason.trainer.notNext"] = "Buy the trainers in order.",
			["reason.trainer.locked"] = "Your Grip level is too low for this trainer.",
			["reason.trainer.priceChanged"] = "The price changed. Please check it again.",
			["reason.trainer.paused"] = "Upgrades are paused for a moment. Try again soon.",
			["quest.starterTask.jelly.one"] = "Squeeze once on the Jelly Pad",
			["quest.starterTask.jelly.many"] = "Squeeze {n} times on the Jelly Pad",
		}
		local wrong = {}
		for key, text in wording do
			if Strings.resolve(key) ~= text then
				table.insert(wrong, string.format("%s = %q", key, tostring(Strings.resolve(key))))
			end
		end
		table.sort(wrong)
		if #wrong > 0 then
			error("not the DESIGN wording: " .. table.concat(wrong, "; "))
		end
		for _, code in { "trainer.notNext", "trainer.locked", "trainer.priceChanged", "trainer.paused" } do
			expect.equal(Strings.reasonText(code), Strings.resolve("reason." .. code))
		end
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
		expect.equal(Strings.daily.panelTitle, "Daily Reward")
		expect.equal(Strings.inspect.previewNotOwned, "Preview · Not owned")
		expect.equal(Strings.resolve("quest.title"), "QUESTS")
		expect.equal(Strings.resolve("daily.title"), "DAILY REWARD")
		for _, title in { Strings.quest.panelTitle, Strings.daily.panelTitle, Strings.inspect.previewNotOwned } do
			expect.truthy(string.upper(title) ~= title) -- never all capitals
		end
	end)

	-- Foam fix 2 (2026-10-09): the regular Grip card's goal line is a short form of grip.goalPad / goalTrainer /
	-- goalRank (the panel and the compact layout's toast keep those), so it fits the card's info column on one line.
	t.test("the Grip card's short goal lines exist with their placeholders", function()
		expect.equal(
			Strings.format(Strings.grip.hudGoalPad, { pad = "Jelly Pad", level = 5 }),
			"Next: Jelly Pad at Lv 5"
		)
		expect.equal(
			Strings.format(Strings.grip.hudGoalTrainer, { trainer = "Sponge Ball", level = 3 }),
			"Next: Sponge Ball at Lv 3"
		)
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
		expect.equal(
			Strings.format(Strings.onboarding.squeeze, { squeezeHint = hint.keyboard }),
			"Squeeze squishies anywhere to earn Coins. Click or press E. Squeeze pads give a boost."
		)
		expect.equal(
			Strings.format(Strings.onboarding.squeeze, { squeezeHint = hint.touch }),
			"Squeeze squishies anywhere to earn Coins. Tap the screen. Squeeze pads give a boost."
		)
		expect.equal(Strings.inspect.preview, "Preview only. Squeeze in the lobby to earn Coins.")
		expect.equal(Strings.inspect.coinsPerSqueezeSub, "per squeeze")
		-- Off a pad the floating label reads the base amount (no pad name).
		expect.equal(
			Strings.format(Strings.grip.stationLabelBase, { coins = "1", grip = "10" }),
			"+1 Coins · +10 Grip per squeeze"
		)
		-- The Foam Mats card: the base amount, no boost.
		expect.equal(Strings.grip.padPerksBase, "No boost: the same Coins and Grip as anywhere")
		-- No text sends the player to a mat any more.
		for _, key in { "onboarding.squeeze", "inspect.preview", "inspect.coinsPerSqueezeSub", "grip.limitNote" } do
			local text = Strings.resolve(key)
			expect.truthy(type(text) == "string" and string.find(string.lower(text), "mat", 1, true) == nil)
		end
		-- The mat, pad-level, limit and locked-button texts are gone with what showed them.
		for _, key in
			{
				"reason.squeeze.notAtStation",
				"reason.squeeze.needGrip",
				"squeeze.limitLabel",
				"squeeze.limitEmpty",
				"squeeze.limitHelp",
				"grip.padLockedButton",
			}
		do
			expect.equal(Strings.resolve(key), nil)
		end
	end)

	-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): no squeeze panel, no Squeeze button, no dock.
	t.test("the tap-to-squeeze texts: the Inspect step opens Squishies; no text names the Squeeze button", function()
		expect.equal(
			Strings.onboarding.inspect,
			"Open Squishies and press Inspect to see it in 3D. Drag to spin it, then try Squeeze."
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
	-- squeeze (F / ButtonX) after DESIGN's throw and ultimate; the lane warning under the duel bar.
	t.test("the duel key hints name the dash and the squeeze; the lane warning exists", function()
		expect.equal(Strings.duel.hintMouse, "Click Throw · Q Ultimate · C Dash · F Squeeze")
		expect.equal(Strings.duel.hintGamepad, "R2 Throw · L2 Ultimate · B Dash · X Squeeze")
		expect.equal(Strings.duel.hintMouseNoUlt, "Click Throw · C Dash · F Squeeze")
		expect.equal(Strings.duel.hintGamepadNoUlt, "R2 Throw · B Dash · X Squeeze")
		local key = Strings.duel.key
		expect.equal(key.dashMouse, "C")
		expect.equal(key.dashGamepad, "B")
		expect.equal(key.squeezeMouse, "F")
		expect.equal(key.squeezeGamepad, "X")
		expect.equal(Strings.duel.inLane, "In the lane!")
	end)
end
