--!strict
-- SqueezeController_Test: unit tests for StarterPlayerScripts.Client.Controllers.SqueezeController (Part 5: the pure
-- send, hold, result and label helpers). Server only (ServerStorage.UnitTest). Edit mode: init() and playLocal() are
-- not called. The squeeze feel itself (the rig's timing points, startKind, interruptFx) is SqueezeFeel_Test's.
-- Contract (DESIGN §9.6, Config.Anim.squeeze):
--   * the deepest squash is the controlled widening (c 0.66), after the Compression phase (c 0.70);
--   * Uncommon and Epic widen wideningExtraMs longer; Common and Exclusive use the base timeline;
-- Part 5 (DESIGN §6.3, §17.3.2, §17.7, §17.10), with every click pays (2026-10-06):
--   * sendDue: a fresh press always goes at once (no reply, nextAt or rhythm to wait for); a hold repeat goes at
--     max(nextAt + leadSeconds, lastSend + Hold.repeatSeconds), one full squeeze animation; with no reply the next
--     repeat waits repeatSeconds + replyGraceSeconds;
--   * underCap: the client sends at most bucketCapacity (12) requests inside 1 s, so clicking as fast as a human can
--     sends every press and never gets squeeze.tooFast from the server's anti-autoclicker cap; a 13th inside the
--     same second is not sent;
--   * holdStopReason: every §17.3.2 stop rule (release, match, context, block, 600 s, 60 s while Searching); since
--     spec 2026-10-11 §5 (squeeze anywhere) where the player stands never stops a hold (no "station" or "locked" stop);
--     a simulated 60 Hz hold against the server's cap repeats every repeatSeconds, never gets tooFast and stops at
--     600 s;
--   * normalizeResult; lineText: "+N" above the squishy, "+N Coins" at the first-person toy, "+N Grip" or
--     "+N Grip (xM)";
--   * lockedLevel, stationLabel (GripMath with the WorldLayout tier); panelLabel (spec 2026-10-11 §5): the pad's label
--     on an unlocked pad, else the base amount (grip.stationLabelBase, tier 1), never a limit line;
--   * hudOffsetOf (spec 2026-10-11 §3.8): the overlay toy's viewport point as an SD_Hud offset, for the lines that
--     float next to the first-person toy.
-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2; the squeeze panel and its button are gone):
--   * pressOf: a left click is a mouse press, a touch a touch press with its InputObject and where it began; keys and
--     gamepads as before; touchHeld: a world touch holds its squeeze until it lifts or is cancelled, or moves 8 px
--     (Config.Inspect.Input.tapMaxPixels: a camera drag; the first squeeze already happened); buttonReleases: only that
--     finger's own lift releases it (any left mouse release a mouse hold); buttonStillDown: End or Cancel is released;
--   * labelShownFor: the floating label shows on the held squishy in the lobby, hidden in a match, while the lobby is
--     locked, while not holding, while a screen is open and in a first-person look; labelSize: the nameplates' chip
--     around its text;
--   * lineLiftPx: a reply's lines start above the label (Coins, then Grip, then slow training one step higher each).
-- Feel pass (DESIGN §18.5.1 A1, A3, A4):
--   * othersPuffs: another player's squeeze emits 4 puffs within 40 studs, none farther out;
--   * matPulseColor: the base colour at 0 ms and from 150 ms on, the peak (base:Lerp(Lemon, 0.55)) at 40 ms, rising
--     then falling, never past the peak;
--   * the "+N" popup: 1.2 -> 2.7 studs over 0.6 s, UIScale 0.6 -> 1 in 140 ms, fading from 0.4 s, done at 0.6 s
--     (ReducedMotion: no rise or pop, 0.5 s then a fade within 120 ms); a pool that reuses the oldest; a reply within
--     foldSeconds (0.2 s above the squishy, 0.35 s at the first-person toy) of the newest line of its kind folds its
--     amount into it, so up to 12 replies a second keep the Coins and Grip lines of the one pool apart, never snap a
--     slot back before its fade, and show the same totals.
-- Foam UI (2026-10-09): popupColor: the floating lines are CoinGold for Coins only, Mint for Grip and Lilac for slow
-- training.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local SqueezeController = t.requireClient("Controllers/SqueezeController")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local squeeze = Config.Anim.squeeze

	-- Phase name -> { start, end } of the base (Common) timeline, and the phase with the smallest c.
	local base: { [string]: { number } } = {}
	local deepest = squeeze.phases[1]
	for _, phase in squeeze.phases do
		base[phase.name] = { phase.startMs, phase.endMs }
		if phase.c < deepest.c then
			deepest = phase
		end
	end

	t.test("the deepest squash is the controlled widening, after the compression phase", function()
		expect.equal(deepest.name, "widening")
		expect.truthy(deepest.endMs > base.compression[2])
	end)

	t.test("Uncommon and Epic widen longer; Common and Exclusive do not", function()
		for _, def in Catalog.list() do
			local extra = squeeze.flourish[def.rarity].wideningExtraMs or 0
			if def.rarity == "Uncommon" or def.rarity == "Epic" then
				expect.truthy(extra > 0)
			else
				expect.equal(extra, 0)
			end
		end
	end)

	-- Part 5: sending, hold-to-squeeze, results, the station label (§6.3, §17.3.2, §17.7, §17.10) -------------------

	local Strings = t.requireShared("Strings")
	local GripMath = t.requireShared("GripMath")
	local Format = t.requireShared("Util/Format")
	local HOLD = Config.Grip.Hold
	local REPEAT = HOLD.repeatSeconds
	local CAP = Config.Squeeze.bucketCapacity
	local CYCLE = Config.Squeeze.cycleSeconds -- the cap's refill (1/12 s), not a squeeze timer
	local WINDOW = CAP * CYCLE
	local T0 = 1_800_000_000 -- a server time (GetServerTimeNow scale)

	local function s(key: string, args: { [string]: any }?): string
		local template = Strings.resolve(key)
		assert(template ~= nil, `missing Strings key {key}`)
		return Strings.format(template, args)
	end

	-- A HoldCheck with nothing stopping the hold.
	local function okCheck(): { [string]: any }
		return {
			held = true,
			heldFor = 1,
			sinceFresh = 1,
			inMatch = false,
			lobbyLive = true,
			blocked = false,
			queued = false,
		}
	end

	t.test("DESIGN values: hold repeats one full squeeze animation (0.45 s), the cap is 12 per second", function()
		local SqueezeFeel = t.requireClient("Controllers/SqueezeFeel")
		expect.equal(REPEAT, 0.45)
		expect.equal(CAP, 12)
		expect.near(WINDOW, 1, 1e-9)
		-- One full squeeze animation: never before the release pop end of any of the 14 squishies.
		expect.equal(#Catalog.list(), 14)
		for _, def in Catalog.list() do
			expect.truthy(REPEAT * 1000 >= SqueezeFeel.timing(def).popEndMs)
		end
	end)

	t.test("sendDue: a fresh press always goes at once (no reply, nextAt or rhythm to wait for)", function()
		local cases: { { lastSendAt: number?, replied: boolean, nextAt: number } } = {
			{ lastSendAt = nil, replied = true, nextAt = 0 },
			{ lastSendAt = T0, replied = true, nextAt = T0 + 0.4 }, -- the cap's bucket says "later"
			{ lastSendAt = T0, replied = false, nextAt = T0 }, -- the last reply has not come yet
		}
		for _, state in cases do
			expect.equal(SqueezeController.sendDue(state, true, HOLD), -math.huge)
		end
		expect.equal(
			SqueezeController.sendDue({ lastSendAt = nil, replied = true, nextAt = 0 }, false, HOLD),
			-math.huge
		)
	end)

	t.test("sendDue: a hold repeat goes at max(nextAt + lead, lastSend + repeatSeconds)", function()
		-- A token was left (nextAt = the reply time): one full squeeze animation per repeat.
		local tokenLeft = { lastSendAt = T0, replied = true, nextAt = T0 + 0.1 }
		expect.near(SqueezeController.sendDue(tokenLeft, false, HOLD), T0 + REPEAT, 1e-6)
		-- The cap's bucket was empty (after fast clicking): wait for the token plus the lead.
		local empty = { lastSendAt = T0, replied = true, nextAt = T0 + 2 }
		expect.near(SqueezeController.sendDue(empty, false, HOLD), T0 + 2 + HOLD.leadSeconds, 1e-6)
	end)

	t.test(
		"sendDue: with no reply (a flood-guard drop) the next repeat waits repeatSeconds + replyGraceSeconds",
		function()
			local state = { lastSendAt = T0, replied = false, nextAt = T0 }
			expect.near(SqueezeController.sendDue(state, false, HOLD), T0 + REPEAT + HOLD.replyGraceSeconds, 1e-6)
		end
	)

	-- Every click pays: the client side of the anti-autoclicker cap -------------------------------------------------

	-- Presses at `pressAt` (clock seconds) through underCap the way trySend keeps its recent sends (the last CAP).
	-- Returns the times that were sent.
	local function sendPresses(pressAt: { number }): { number }
		local recent: { number } = {}
		local sent: { number } = {}
		for _, at in pressAt do
			if SqueezeController.underCap(recent, at, CAP, WINDOW) then
				table.insert(recent, at)
				while #recent > CAP do
					table.remove(recent, 1)
				end
				table.insert(sent, at)
			end
		end
		return sent
	end

	-- The server's cap (Config.Squeeze bucket) over sends at `sentAt`: how many it would call squeeze.tooFast.
	local function serverTooFast(sentAt: { number }): number
		local tokens, at, tooFast = CAP, sentAt[1] or 0, 0
		for _, t in sentAt do
			tokens = math.min(CAP, tokens + (t - at) / CYCLE)
			at = t
			if tokens >= 1 - 1e-6 then
				tokens = math.max(0, tokens - 1)
			else
				tooFast += 1
			end
		end
		return tooFast
	end

	t.test("underCap: 12 presses in 1 s are all sent; a 13th in the same second is not", function()
		local burst = {}
		for i = 1, CAP + 1 do
			table.insert(burst, T0 + (i - 1) * 0.01)
		end
		local sent = sendPresses(burst)
		expect.equal(#sent, CAP)
		expect.equal(serverTooFast(sent), 0)
		-- Exactly one window after the first send, the next one goes again.
		expect.truthy(SqueezeController.underCap(sent, T0 + WINDOW, CAP, WINDOW))
		expect.falsy(SqueezeController.underCap(sent, T0 + WINDOW - 0.001, CAP, WINDOW))
		expect.truthy(SqueezeController.underCap({}, T0, CAP, WINDOW))
	end)

	t.test("clicking as fast as a human can: every press is sent and the server never says tooFast", function()
		-- Steady 8, 10 and 12 clicks a second for a minute (12 is the cap: the fastest a client sends).
		for _, rate in { 8, 10, 12 } do
			local presses = {}
			for i = 1, 60 * rate do
				table.insert(presses, T0 + (i - 1) / rate)
			end
			local sent = sendPresses(presses)
			expect.equal(#sent, #presses)
			expect.equal(serverTooFast(sent), 0)
		end
		-- A jittery 11 a second: gaps from 40 to 130 ms (mean 91 ms).
		local jitter, at = {}, T0
		local gaps = { 0.04, 0.13, 0.07, 0.11, 0.09, 0.105 }
		for i = 1, 660 do
			table.insert(jitter, at)
			at += gaps[(i - 1) % #gaps + 1]
		end
		local sent = sendPresses(jitter)
		expect.equal(#sent, #jitter)
		expect.equal(serverTooFast(sent), 0)
		-- Never more than the cap inside any 1 s, so never near the 20/s flood guard.
		for i = 1, #sent do
			local inside = 0
			for j = i, #sent do
				if sent[j] - sent[i] < WINDOW - 1e-6 then
					inside += 1
				end
			end
			if inside > CAP then
				error(`{inside} sends inside 1 s from {sent[i] - T0}`)
			end
		end
		expect.truthy(CAP <= Config.Squeeze.floodPerSecond)
	end)

	t.test("a macro at 30 clicks a second: the client sends at most 12 a second", function()
		local presses = {}
		for i = 1, 300 do
			table.insert(presses, T0 + (i - 1) / 30)
		end
		local sent = sendPresses(presses)
		expect.truthy(#sent <= CAP * 10 + CAP)
		expect.equal(serverTooFast(sent), 0)
	end)

	t.test("12 presses a second stay inside the squeeze particle budget", function()
		-- Worst case per second at the cap: every press merges a big pop's sparkles, puffs at most once per release
		-- pop (the largest flourish, 12) plus Dragon's steam never (a cut squeeze has not reached its release yet).
		local maxPuffs = 0
		for _, flourish in squeeze.flourish do
			maxPuffs = math.max(maxPuffs, flourish.particles)
		end
		local rhythm = squeeze.rhythm
		local sparkles = CAP * math.max(rhythm.popSparkles, rhythm.bigPopSparkles)
		local puffs = math.ceil(1 / (squeeze.phases[#squeeze.phases].endMs / 1000)) * maxPuffs
		local longest = math.max(squeeze.particles.lifetimeMax, 0.35)
		local live = (sparkles + puffs) * longest
		expect.truthy(live <= Config.Vfx.Budgets.liveParticlesPerEffect)
		expect.truthy(live <= Config.Vfx.Budgets.liveParticlesTotal / 2)
		-- The squeeze sounds' key cooldown (90 ms) is at least the 83 ms between capped presses: never more than one
		-- sfx.squish (or sfx.squeezeRelease) per press, whatever the click speed.
		expect.truthy(Config.Audio.cooldownMs.squeeze >= 1000 * CYCLE)
	end)

	t.test("holdStopReason: nothing stops a good hold; each §17.3.2 rule stops it", function()
		expect.equal(SqueezeController.holdStopReason(okCheck(), HOLD), nil)
		local cases: { { field: string, value: any, reason: string } } = {
			{ field = "held", value = false, reason = "released" },
			{ field = "inMatch", value = true, reason = "match" },
			{ field = "lobbyLive", value = false, reason = "context" },
			{ field = "blocked", value = true, reason = "blocked" },
			{ field = "heldFor", value = HOLD.maxSeconds, reason = "maxTime" },
		}
		for _, case in cases do
			local check = okCheck()
			check[case.field] = case.value
			expect.equal(SqueezeController.holdStopReason(check, HOLD), case.reason)
		end
		-- The physical release wins over everything else.
		local all = okCheck()
		all.held, all.inMatch, all.blocked = false, true, true
		expect.equal(SqueezeController.holdStopReason(all, HOLD), "released")
	end)

	t.test(
		"holdStopReason: where the player stands never stops a hold (squeeze anywhere, spec 2026-10-11 §5)",
		function()
			local check = okCheck()
			check.atStation, check.locked = false, true -- the old station and locked-pad facts mean nothing now
			expect.equal(SqueezeController.holdStopReason(check, HOLD), nil)
		end
	)

	t.test("holdStopReason: the 10-minute pause is exactly Hold.maxSeconds of continuous hold", function()
		expect.equal(HOLD.maxSeconds, 600)
		local check = okCheck()
		check.heldFor = HOLD.maxSeconds - 0.01
		expect.equal(SqueezeController.holdStopReason(check, HOLD), nil)
		check.heldFor = HOLD.maxSeconds
		expect.equal(SqueezeController.holdStopReason(check, HOLD), "maxTime")
	end)

	t.test("holdStopReason: while Searching, the hold stops Hold.queuedSeconds after the last fresh press", function()
		local check = okCheck()
		check.queued = true
		check.sinceFresh = HOLD.queuedSeconds - 0.01
		expect.equal(SqueezeController.holdStopReason(check, HOLD), nil)
		check.sinceFresh = HOLD.queuedSeconds
		expect.equal(SqueezeController.holdStopReason(check, HOLD), "queued")
		-- Not queued: the queue rule never applies.
		check.queued = false
		check.sinceFresh = HOLD.maxSeconds - 1
		check.heldFor = HOLD.maxSeconds - 1
		expect.equal(SqueezeController.holdStopReason(check, HOLD), nil)
	end)

	-- Drives sendDue / holdStopReason the way step() does (60 Hz) against a model of the server's anti-autoclicker cap
	-- (capacity bucketCapacity, 1 token per cycleSeconds, nextAt = now + max(0, 1 - tokens) × cycleSeconds), starting
	-- with `tokens0` tokens (after fast clicking it can be empty). `reply` = the server answers.
	local function simulateHold(seconds: number, reply: boolean, tokens0: number?): ({ number }, number)
		local dt = 1 / 60
		local sendsAt: { number } = {}
		local rejected = 0
		local state = { lastSendAt = nil :: number?, replied = true, nextAt = 0 }
		local tokens, tokensAt = tokens0 or CAP, T0
		local now = T0
		local fresh = true
		while now - T0 < seconds do
			local check = okCheck()
			check.heldFor = now - T0
			check.sinceFresh = now - T0
			if SqueezeController.holdStopReason(check, HOLD) ~= nil then
				break
			end
			if now >= SqueezeController.sendDue(state, fresh, HOLD) then
				table.insert(sendsAt, now)
				state.lastSendAt = now
				state.replied = false
				if reply then
					tokens = math.min(CAP, tokens + (now - tokensAt) / CYCLE)
					tokensAt = now
					if tokens >= 1 - 1e-6 then
						tokens = math.max(0, tokens - 1)
					else
						rejected += 1
					end
					state.replied = true
					state.nextAt = now + math.max(0, 1 - tokens) * CYCLE
				end
				fresh = false
			end
			now += dt
		end
		return sendsAt, rejected
	end

	t.test("holding repeats one full squeeze animation (repeatSeconds), never too fast, and stops at 600 s", function()
		local sendsAt, rejected = simulateHold(HOLD.maxSeconds + 60, true)
		expect.truthy(#sendsAt > 0)
		expect.equal(rejected, 0) -- the server's cap never has to say squeeze.tooFast
		for i = 2, #sendsAt do
			local gap = sendsAt[i] - sendsAt[i - 1]
			if gap < REPEAT - 1e-6 or gap > REPEAT + 1 / 60 + 1e-6 then
				error(`repeat {i} came {gap} s after the last one`)
			end
		end
		-- About 2.2 squeezes a second for the whole 10 minutes (clicking can be faster), none after the pause.
		expect.truthy(#sendsAt >= math.floor(HOLD.maxSeconds / (REPEAT + 1 / 60)))
		expect.truthy(#sendsAt <= math.ceil(HOLD.maxSeconds / REPEAT) + 1)
		expect.truthy(sendsAt[#sendsAt] - T0 < HOLD.maxSeconds)
	end)

	t.test("a hold right after fast clicking (the press took the cap's last token) is never too fast", function()
		local sendsAt, rejected = simulateHold(10, true, 1)
		expect.truthy(#sendsAt >= 2)
		expect.equal(rejected, 0)
	end)

	t.test("with no replies the hold keeps going at repeatSeconds + replyGraceSeconds (no stall)", function()
		local sendsAt = simulateHold(30, false)
		expect.truthy(#sendsAt >= 2)
		for i = 2, #sendsAt do
			expect.near(sendsAt[i] - sendsAt[i - 1], REPEAT + HOLD.replyGraceSeconds, 1 / 60 + 1e-6)
		end
	end)

	t.test("normalizeResult reads a SqueezeResult and rejects a malformed one", function()
		expect.equal(SqueezeController.normalizeResult(nil), nil)
		expect.equal(SqueezeController.normalizeResult({ coins = 5 }), nil)
		local result = SqueezeController.normalizeResult({
			ok = true,
			coins = 6.9,
			total = 120,
			limit = 299.5,
			nextAt = T0 + 1.5,
			grip = 30,
			gripTotal = 1030,
			doubled = true,
		})
		expect.deepEqual(result, {
			ok = true,
			coins = 6,
			total = 120,
			limit = 299.5,
			nextAt = T0 + 1.5,
			grip = 30,
			gripTotal = 1030,
			doubled = true,
		})
		local rejected = SqueezeController.normalizeResult({
			ok = false,
			coins = -3,
			reason = "squeeze.inDuel",
			nextAt = 0 / 0,
			grip = "lots",
			doubled = 1,
		})
		expect.deepEqual(rejected, { ok = false, coins = 0, reason = "squeeze.inDuel", grip = 0, doubled = false })
		expect.equal(SqueezeController.normalizeResult({ ok = false, reason = "" }).reason, nil)
	end)

	t.test("lineText: +N above the squishy, +N Coins at the first-person toy, +N Grip or +N Grip (xM)", function()
		local mult = Config.Grip.Rested.mult
		-- Above the squishy the coin icon says what the number is; at the first-person toy the line says it.
		expect.equal(SqueezeController.lineText("coins", 6, false, false), s("common.plusAmount", { n = "6" }))
		expect.equal(SqueezeController.lineText("coins", 6, false, true), s("common.coinsGain", { coins = "6" }))
		for _, overlay in { false, true } do
			expect.equal(SqueezeController.lineText("grip", 30, false, overlay), s("grip.popup", { n = "30" }))
			expect.equal(
				SqueezeController.lineText("grip", 60, true, overlay),
				s("grip.popupDouble", { n = "60", mult = mult })
			)
		end
		-- Large amounts use Format.coins.
		expect.equal(
			SqueezeController.lineText("grip", 1500, false, false),
			s("grip.popup", { n = Format.coins(1500) })
		)
		expect.equal(
			SqueezeController.lineText("coins", 1500, false, true),
			s("common.coinsGain", { coins = Format.coins(1500) })
		)
	end)

	t.test("lockedLevel: the pad's level while the local level is below it; never locked while unknown", function()
		local pads = Config.Grip.Pads
		expect.equal(SqueezeController.lockedLevel(nil, 4), nil)
		expect.equal(SqueezeController.lockedLevel(1, 1), nil)
		for tier = 2, #pads do
			local need = pads[tier].level
			expect.equal(SqueezeController.lockedLevel(need - 1, tier), need)
			expect.equal(SqueezeController.lockedLevel(need, tier), nil)
		end
		expect.equal(SqueezeController.lockedLevel(50, #pads + 1), nil)
	end)

	t.test("the station label uses GripMath with the WorldLayout tier, the trainer and the equipped squishy", function()
		local pads = Config.Grip.Pads
		for _, id in { "kitty_bread", "dragon" } do
			for tier = 1, #pads do
				for _, trainer in { 1, 3, 8 } do
					local expected = s("grip.stationLabel", {
						pad = s("grip.pad." .. pads[tier].key),
						coins = Format.coins(GripMath.squeezeCoins(Catalog.getSqueezeCoins(id), tier, true)),
						grip = Format.coins(GripMath.squeezeGrip(trainer, tier)),
					})
					expect.equal(SqueezeController.stationLabel(tier, trainer, id), expected)
				end
			end
		end
		-- §17.3.1 table: Rubber Ball (trainer 3) on the Jelly Pad = 30 Grip; a Common on the Jelly Pad = 1 + 1 Coins
		-- (spec 2026-10-11 §5).
		expect.equal(
			SqueezeController.stationLabel(2, 3, "kitty_bread"),
			s("grip.stationLabel", { pad = s("grip.pad.jelly"), coins = "2", grip = "30" })
		)
		expect.equal(SqueezeController.stationLabel(#pads + 1, 1, "kitty_bread"), "")
	end)

	-- Squeeze anywhere (spec 2026-10-11 §5) -----------------------------------------------------------------------

	t.test("panelLabel: the pad's label on an unlocked pad; off a pad or on a locked one, the base amount", function()
		local pads = Config.Grip.Pads
		for _, id in { "kitty_bread", "dragon" } do
			for _, trainer in { 1, 3, 8 } do
				local base = s("grip.stationLabelBase", {
					coins = Format.coins(GripMath.squeezeCoins(Catalog.getSqueezeCoins(id), 1, true)),
					grip = Format.coins(GripMath.squeezeGrip(trainer, 1)),
				})
				expect.equal(SqueezeController.panelLabel(nil, 50, trainer, id), base)
				expect.equal(SqueezeController.panelLabel(nil, nil, trainer, id), base)
				for tier = 1, #pads do
					local need = pads[tier].level
					local padLabel = SqueezeController.stationLabel(tier, trainer, id)
					expect.equal(SqueezeController.panelLabel(tier, need, trainer, id), padLabel)
					expect.equal(SqueezeController.panelLabel(tier, nil, trainer, id), padLabel) -- level unknown
					if need > 1 then
						expect.equal(SqueezeController.panelLabel(tier, need - 1, trainer, id), base)
					end
				end
				expect.equal(SqueezeController.panelLabel(#pads + 1, 50, trainer, id), base)
			end
		end
		-- §17.3.1 table: a Common off a pad = 1 Coin and the Foam Mats Grip (10 for the first trainer).
		expect.equal(
			SqueezeController.panelLabel(nil, 1, 1, "kitty_bread"),
			s("grip.stationLabelBase", { coins = "1", grip = "10" })
		)
	end)

	-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): the info floats on the held squishy ----------------------

	t.test(
		"labelShownFor: on the held squishy in the lobby; hidden in a match, locked, not holding, a screen open, first person",
		function()
			local function lobby(): { [string]: any }
				return { holding = true, inMatch = false, lobbyLocked = false, blocked = false, firstPerson = false }
			end
			expect.truthy(SqueezeController.labelShownFor(lobby() :: any))
			local hides: { { field: string, value: any } } = {
				{ field = "holding", value = false },
				{ field = "inMatch", value = true },
				{ field = "lobbyLocked", value = true },
				{ field = "blocked", value = true },
				{ field = "firstPerson", value = true },
			}
			for _, case in hides do
				local c = lobby()
				c[case.field] = case.value
				if SqueezeController.labelShownFor(c :: any) then
					error(`the label shows with {case.field} = {tostring(case.value)}`)
				end
			end
		end
	)

	t.test("the squeeze panel is gone: no panel hooks are left for the HUD", function()
		local api = SqueezeController :: any
		expect.equal(api.panelShown, nil)
		expect.equal(api.panelRoot, nil)
		expect.equal(api.PanelChanged, nil)
	end)

	t.test("labelSize: the nameplates' chip around the label's text (px: the same size at any distance)", function()
		local Theme = t.requireClient("UI/Theme")
		local bands = Theme.Foam.chip
		local across = 2 * (Theme.Padding.medium + Theme.Stroke.bar)
		local tall = 2 * (Theme.Padding.small + Theme.Stroke.bar) + bands.bevel + bands.drop
		local size = SqueezeController.labelSize(Vector2.new(200, 40))
		expect.equal(size.X, 200 + across)
		expect.equal(size.Y, 40 + tall)
		-- A fraction rounds up (the text never clips); a bad measure gives the empty chip.
		expect.equal(SqueezeController.labelSize(Vector2.new(199.25, 39.5)), size)
		local empty = SqueezeController.labelSize(Vector2.new(0 / 0, -5))
		expect.equal(empty.X, across)
		expect.equal(empty.Y, tall)
	end)

	t.test("lineLiftPx: a reply's lines start above the label: Coins, then Grip, then slow training", function()
		local POPUP = Config.Vfx.CoinPopup
		local half = POPUP.heightPx / 2
		for _, labelPx in { 0, 30, 61 } do
			local coins = SqueezeController.lineLiftPx("coins", labelPx)
			local grip = SqueezeController.lineLiftPx("grip", labelPx)
			local afk = SqueezeController.lineLiftPx("afk", labelPx)
			-- The label's bottom is on the anchor, so its top is labelPx above it: the lowest line's bottom sits higher.
			expect.truthy(coins - half >= labelPx)
			-- One step between the kinds, at least a HudNumber line tall, so a reply's lines never start on each other.
			expect.truthy(grip - coins >= Config.UI.TextSize.HudNumber)
			expect.equal(afk - grip, grip - coins)
		end
		-- A taller label lifts every line by as much.
		expect.equal(
			SqueezeController.lineLiftPx("grip", 61) - SqueezeController.lineLiftPx("grip", 30),
			SqueezeController.lineLiftPx("coins", 61) - SqueezeController.lineLiftPx("coins", 30)
		)
	end)

	t.test(
		"hudOffsetOf: a viewport point minus the GUI inset and the HUD origin, in base px under the UIScale",
		function()
			-- Vector2 holds single-precision floats.
			local at = SqueezeController.hudOffsetOf(Vector2.new(960, 600), Vector2.new(0, 58), Vector2.new(0, 0), 1.25)
			expect.near(at.X, 768, 1e-3)
			expect.near(at.Y, (600 - 58) / 1.25, 1e-3)
			local shifted =
				SqueezeController.hudOffsetOf(Vector2.new(100, 100), Vector2.new(0, 36), Vector2.new(20, 4), 1)
			expect.near(shifted.X, 80, 1e-3)
			expect.near(shifted.Y, 60, 1e-3)
			-- A bad scale never divides by zero.
			local bad = SqueezeController.hudOffsetOf(Vector2.new(50, 50), Vector2.zero, Vector2.zero, 0)
			expect.near(bad.X, 50, 1e-3)
		end
	)

	-- Feel pass (§18.5.1 A1, A3, A4) ------------------------------------------------------------------------------

	local Palette = t.requireShared("Art/Palette")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local EFFECTS = Config.Vfx.Effects
	local MAT = Config.Vfx.MatPulse
	local POPUP = Config.Vfx.CoinPopup

	local function sameColor(a: Color3, b: Color3): boolean
		return math.abs(a.R - b.R) < 1e-6 and math.abs(a.G - b.G) < 1e-6 and math.abs(a.B - b.B) < 1e-6
	end

	t.test("others' squeezes: 4 puffs within 40 studs, none farther out", function()
		expect.equal(EFFECTS.othersSqueezePuffs, 4)
		expect.equal(EFFECTS.othersSqueezeStuds, 40)
		expect.equal(SqueezeController.othersPuffs(0), 4)
		expect.equal(SqueezeController.othersPuffs(40), 4)
		expect.equal(SqueezeController.othersPuffs(40.01), 0)
		expect.equal(SqueezeController.othersPuffs(59), 0) -- the animation still plays (othersCullStuds 60)
		expect.equal(SqueezeController.othersPuffs(0 / 0), 0)
	end)

	t.test("the mat pulse: base at 0 ms and from 150 ms on, the peak at 40 ms", function()
		expect.equal(MAT.upMs + MAT.downMs, EFFECTS.matPulseSeconds * 1000)
		local base = Palette[WorldLayout.SqueezeZone.matColor]
		local peakColor = base:Lerp(Palette[WorldLayout.SqueezeZone.pulseColor], MAT.towardPulseColor)
		local atZero, doneAtZero = SqueezeController.matPulseColor(0)
		expect.truthy(sameColor(atZero, base))
		expect.falsy(doneAtZero)
		local atPeak = SqueezeController.matPulseColor(MAT.upMs)
		expect.truthy(sameColor(atPeak, peakColor))
		expect.near(SqueezeController.matPulseMix(MAT.upMs), MAT.towardPulseColor, 1e-9)
		for _, ms in { 150, 151, 400, 10_000 } do
			local color, done = SqueezeController.matPulseColor(ms)
			expect.truthy(sameColor(color, base))
			expect.truthy(done)
		end
		-- Rises to the peak, then falls; never past it.
		local last = 0
		for ms = 0, MAT.upMs do
			local mix = SqueezeController.matPulseMix(ms)
			expect.truthy(mix >= last - 1e-12 and mix <= MAT.towardPulseColor + 1e-12)
			last = mix
		end
		for ms = MAT.upMs, MAT.upMs + MAT.downMs do
			local mix = SqueezeController.matPulseMix(ms)
			expect.truthy(mix <= last + 1e-12)
			last = mix
		end
		expect.equal(last, 0)
	end)

	t.test("the +N popup rises 1.2 -> 2.7 studs, pops 0.6 -> 1 and fades out by 0.6 s", function()
		local start = SqueezeController.coinPopupSample(0, false)
		expect.near(start.offsetY, POPUP.startStuds, 1e-9)
		expect.near(start.scale, POPUP.popFrom, 1e-9)
		expect.equal(start.fade, 0)
		expect.falsy(start.done)
		local popped = SqueezeController.coinPopupSample(POPUP.popMs / 1000, false)
		expect.near(popped.scale, 1, 1e-9)
		local overshoot = 0
		for ms = 0, POPUP.popMs do
			overshoot = math.max(overshoot, SqueezeController.coinPopupSample(ms / 1000, false).scale)
		end
		expect.truthy(overshoot > 1 and overshoot < 1.15) -- Back Out
		expect.equal(SqueezeController.coinPopupSample(POPUP.fadeFromSeconds, false).fade, 0)
		local finish = SqueezeController.coinPopupSample(EFFECTS.coinPopupSeconds, false)
		expect.near(finish.offsetY, POPUP.startStuds + EFFECTS.coinPopupRiseStuds, 1e-9)
		expect.near(finish.offsetY, 2.7, 1e-9)
		expect.equal(finish.fade, 1)
		expect.truthy(finish.done)
		-- ReducedMotion: no rise and no pop; 0.5 s, then a fade within 120 ms.
		local still = SqueezeController.coinPopupSample(0.3, true)
		expect.deepEqual(still, { offsetY = POPUP.startStuds, scale = 1, fade = 0, done = false })
		expect.equal(SqueezeController.coinPopupSample(0.5, true).fade, 0)
		local gone = SqueezeController.coinPopupSample(0.5 + Config.UI.motion.reducedMotionMaxFadeMs / 1000, true)
		expect.equal(gone.fade, 1)
		expect.truthy(gone.done)
	end)

	t.test("the popup pool: a free slot first, else the oldest is reused (3 at most)", function()
		local max = EFFECTS.coinPopupMaxVisible
		expect.equal(max, 3)
		expect.equal(SqueezeController.popupSlot({}, max), 1)
		expect.equal(SqueezeController.popupSlot({ [1] = 10 }, max), 2)
		expect.equal(SqueezeController.popupSlot({ [1] = 10, [3] = 11 }, max), 2)
		expect.equal(SqueezeController.popupSlot({ [1] = 10, [2] = 9, [3] = 11 }, max), 2)
		expect.equal(SqueezeController.popupSlot({ [1] = 12, [2] = 13, [3] = 11 }, max), 3)
	end)

	t.test("popup colours (foam UI): CoinGold only for Coins, Grip Mint, slow training Lilac", function()
		local Palette = t.requireShared("Art/Palette")
		expect.equal(SqueezeController.popupColor("coins"), Palette.CoinGold)
		-- Candy UI (2026-10-11): the Mint and Lavender accents.
		expect.equal(SqueezeController.popupColor("grip"), Palette.CandyMint)
		expect.equal(SqueezeController.popupColor("afk"), Palette.CandyLavender)
		-- The reserved coin colours never mark a Grip line.
		for _, kind in { "grip", "afk" } do
			local color = SqueezeController.popupColor(kind)
			for _, reserved in { Palette.CoinGold, Palette.CoinRing, Palette.CoinHighlight, Palette.Danger } do
				expect.truthy(color ~= reserved)
			end
		end
	end)

	-- Review fix (every click pays): at fast clicking each reply used to stack a new "+N Grip" line (six within 0-28 px,
	-- a smear) and snap a "+N" slot back to its start at full opacity. A reply within foldSeconds of the newest line
	-- now adds its amount to that line instead.
	t.test("foldSeconds / foldsInto: a reply folds into a line younger than its window", function()
		local coinWindow = SqueezeController.foldSeconds("coins")
		local gripWindow = SqueezeController.foldSeconds("grip")
		expect.near(coinWindow, EFFECTS.coinPopupSeconds / EFFECTS.coinPopupMaxVisible, 1e-12) -- 0.2 s
		expect.near(gripWindow, Config.UI.motion.coinCounter.floatMs / 2000, 1e-12) -- 0.35 s
		expect.falsy(SqueezeController.foldsInto(nil, 5, coinWindow))
		expect.truthy(SqueezeController.foldsInto(5, 5, coinWindow))
		expect.truthy(SqueezeController.foldsInto(5, 5 + coinWindow - 0.01, coinWindow))
		expect.falsy(SqueezeController.foldsInto(5, 5 + coinWindow, coinWindow))
		expect.falsy(SqueezeController.foldsInto(5, 4.9, coinWindow)) -- a clock that went back starts a new line
	end)

	-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): the "+N Grip" lines float from the squishy in the "+N" pool
	-- too, so a reply's two lines share it.
	t.test(
		"up to 12 replies a second: the Coins and Grip lines share the pool, never reuse a slot early, same totals",
		function()
			local window = SqueezeController.foldSeconds("coins")
			local pool = SqueezeController.POPUP_POOL
			expect.equal(pool, EFFECTS.coinPopupMaxVisible * 3) -- a share each for Coins, Grip and slow training
			for _, rate in { 12, 10, 8, 6, 4, 2 } do
				local slots: { [number]: number } = {} -- slot -> start, while its popup shows
				local kinds: { [number]: string } = {} -- slot -> the kind it shows
				local newest: { [string]: number } = {} -- kind -> its newest slot
				local shown: { [string]: number } = { coins = 0, grip = 0 }
				local lines: { [string]: number } = { coins = 0, grip = 0 }
				local replies = 3 * rate
				for i = 0, replies - 1 do
					local now = i / rate
					for index, startedAt in slots do
						if SqueezeController.coinPopupSample(now - startedAt, false).done then
							slots[index] = nil -- stepCoinPopups frees a slot whose popup ended
						end
					end
					-- "+7" and "+30 Grip" above the squishy.
					for _, line in { { kind = "coins", amount = 7 }, { kind = "grip", amount = 30 } } do
						local slot = newest[line.kind]
						if
							slot ~= nil
							and kinds[slot] == line.kind
							and SqueezeController.foldsInto(slots[slot], now, window)
						then
							shown[line.kind] += line.amount
						else
							local index = SqueezeController.popupSlot(slots, pool)
							local reused = slots[index]
							if reused ~= nil and SqueezeController.coinPopupSample(now - reused, false).fade <= 0 then
								error(
									`{rate}/s, reply {i}: slot {index} snapped back {now - reused} s in, before its fade`
								)
							end
							slots[index], kinds[index], newest[line.kind] = now, line.kind, index
							shown[line.kind] += line.amount
							lines[line.kind] += 1
						end
					end
				end
				-- Every reply's amount is shown (in a folded line or its own).
				expect.equal(shown.coins, replies * 7)
				expect.equal(shown.grip, replies * 30)
				for _, kind in { "coins", "grip" } do
					if rate >= 6 then
						expect.truthy(lines[kind] < replies) -- fast clicking folds
					else
						expect.equal(lines[kind], replies) -- normal clicking: one line per reply
					end
				end
			end
		end
	)

	-- Part 8 (§17.12 L5), kept for the world touch (lobby HUD spec §2): only the pressing finger's own end releases --

	t.test("buttonReleases: only the finger that pressed (wherever it lifts) or a mouse release", function()
		local touch, mouse = Enum.UserInputType.Touch, Enum.UserInputType.MouseButton1
		local fingerA, fingerB = { name = "A" }, { name = "B" }
		-- Not held: nothing releases.
		expect.falsy(SqueezeController.buttonReleases(false, fingerA, fingerA, touch))
		expect.falsy(SqueezeController.buttonReleases(false, nil, fingerA, mouse))
		-- The pressing finger lifts: on the button (its InputEnded) or after sliding off (UserInputService.TouchEnded
		-- reports the same InputObject).
		expect.truthy(SqueezeController.buttonReleases(true, fingerA, fingerA, touch))
		-- Another finger lifting (the thumbstick thumb) never releases it.
		expect.falsy(SqueezeController.buttonReleases(true, fingerA, fingerB, touch))
		-- A press with no recorded input is released by any touch end; any left mouse release releases it.
		expect.truthy(SqueezeController.buttonReleases(true, nil, fingerB, touch))
		expect.truthy(SqueezeController.buttonReleases(true, fingerA, fingerB, mouse))
		-- Other inputs never release it.
		for _, kind in { Enum.UserInputType.MouseButton2, Enum.UserInputType.Keyboard, Enum.UserInputType.Gamepad1 } do
			expect.falsy(SqueezeController.buttonReleases(true, fingerA, fingerA, kind))
		end
	end)

	t.test("buttonStillDown: the hold ends once the pressing touch is End or Cancel, even with no event", function()
		local State = Enum.UserInputState
		expect.truthy(SqueezeController.buttonStillDown(true, nil)) -- unknown state: the flag decides
		expect.truthy(SqueezeController.buttonStillDown(true, State.Begin))
		expect.truthy(SqueezeController.buttonStillDown(true, State.Change)) -- the finger moves (also off the button)
		expect.falsy(SqueezeController.buttonStillDown(true, State.End))
		expect.falsy(SqueezeController.buttonStillDown(true, State.Cancel)) -- taken over, e.g. by the camera
		expect.falsy(SqueezeController.buttonStillDown(false, State.Begin))
		expect.falsy(SqueezeController.buttonStillDown(false, nil))
	end)

	-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): tap or click the world to squeeze; holding keeps squeezing --

	t.test(
		"pressOf: a left click is a mouse press, a touch a touch press with where it began; keys as before",
		function()
			local State = Enum.UserInputState
			expect.deepEqual(SqueezeController.pressOf(nil), { source = "virtual" })
			local key =
				{ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.E, UserInputState = State.Begin }
			expect.deepEqual(SqueezeController.pressOf(key), { source = "keyboard", keyCode = Enum.KeyCode.E })
			local pad = { UserInputType = Enum.UserInputType.Gamepad1, KeyCode = Enum.KeyCode.ButtonX }
			expect.deepEqual(
				SqueezeController.pressOf(pad),
				{ source = "gamepad", keyCode = Enum.KeyCode.ButtonX, gamepad = Enum.UserInputType.Gamepad1 }
			)
			local click = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(640, 360, 0) }
			local mouse = SqueezeController.pressOf(click)
			expect.equal(mouse.source, "mouse")
			expect.equal(mouse.input, click)
			local finger = { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(300, 200, 0) }
			local touch = SqueezeController.pressOf(finger)
			expect.equal(touch.source, "touch")
			expect.equal(touch.input, finger)
			expect.equal(touch.from, Vector3.new(300, 200, 0))
			-- Any other input is a virtual press, as before.
			expect.equal(
				SqueezeController.pressOf({ UserInputType = Enum.UserInputType.MouseButton2 }).source,
				"virtual"
			)
		end
	)

	t.test("touchHeld: a world touch holds until it lifts, is cancelled or moves 8 px (a camera drag)", function()
		local State = Enum.UserInputState
		local max = Config.Inspect.Input.tapMaxPixels
		expect.equal(max, 8)
		local from = Vector3.new(400, 300, 0)
		expect.truthy(SqueezeController.touchHeld(State.Begin, from, from, max))
		expect.truthy(SqueezeController.touchHeld(State.Change, from, from + Vector3.new(5, 5, 0), max)) -- 7.1 px
		expect.falsy(SqueezeController.touchHeld(State.Change, from, from + Vector3.new(8, 0, 0), max)) -- 8 px: a drag
		expect.falsy(SqueezeController.touchHeld(State.Change, from, from + Vector3.new(0, -40, 0), max))
		expect.falsy(SqueezeController.touchHeld(State.End, from, from, max))
		expect.falsy(SqueezeController.touchHeld(State.Cancel, from, from, max)) -- taken over, with no end event
		expect.truthy(SqueezeController.touchHeld(nil, from, from, max)) -- an unknown state: the distance decides
	end)

	t.test("a world touch squeezes at once, holds while still, and a camera drag ends the hold (the flow)", function()
		local State = Enum.UserInputState
		local max = Config.Inspect.Input.tapMaxPixels
		-- The controller's flow: the press (pressOf) starts a hold on that finger and squeezes at once; every frame
		-- isHeld checks it (touchHeld); an End releases a pointer hold only for that finger (buttonReleases).
		local finger = {
			UserInputType = Enum.UserInputType.Touch,
			UserInputState = State.Begin,
			Position = Vector3.new(200, 200, 0),
		}
		local press = SqueezeController.pressOf(finger)
		local function held(): boolean
			return SqueezeController.touchHeld(finger.UserInputState, press.from, finger.Position, max)
		end
		expect.truthy(held())
		finger.UserInputState = State.Change
		finger.Position = Vector3.new(203, 198, 0) -- a finger held still wobbles a little
		expect.truthy(held())
		finger.Position = Vector3.new(230, 200, 0) -- a camera drag: the hold ends (the first squeeze already happened)
		expect.falsy(held())
		-- Another finger lifting (the thumbstick thumb) never releases a touch hold; its own lift does.
		local thumb = { UserInputType = Enum.UserInputType.Touch }
		expect.falsy(SqueezeController.buttonReleases(true, finger, thumb, Enum.UserInputType.Touch))
		expect.truthy(SqueezeController.buttonReleases(true, finger, finger, Enum.UserInputType.Touch))
	end)
end
