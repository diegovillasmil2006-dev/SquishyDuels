--!strict
-- SqueezeRules_Test: unit tests for ServerScriptService.Server.Logic.SqueezeRules. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.3, §17.3.1, §17.10, §17.12 Part 5 "SqueezeService with fakes", pure part): the order flood guard
-- -> profile ready -> a living character -> not in a match -> the tier -> bucket -> earnings limit. Squeeze anywhere
-- (spec 2026-10-11 §5): the pad is the one the server-side root stands on (padUnder: WorldLayout.stationUnder with
-- Config.Squeeze's padMargin / heightAbove; Phase 6 moved them there from Config.Grip.Afk with slow training gone); off
-- a pad, or on a pad still locked for the
-- player's Grip level, the squeeze pays tier 1 (base Coins, no pad bonus) and uses a token like any other; only a
-- missing or dead character is refused (squeeze.noCharacter, no token). Every click pays (2026-10-06): the bucket is
-- the hidden anti-autoclicker cap, 12 at once and 12 per second on average (12 presses in 1 s all pay; a 13th at the
-- same instant is squeeze.tooFast; a macro at 25/s for 30 s gets at most 12 + 30 × 12 accepted; a rested 20/s macro
-- gets 20 in its first second); more than 20 requests in any second are dropped silently (a steady 20/s never is; more
-- than 40 drops in 10 s log once, so a 5 s backlog of 60 presses arriving at once is not logged); the shipped hourly
-- limit is off (spec 2026-10-11 §5), so every accepted squeeze pays and the limit state is left alone; with the limit
-- switched on (the rule stays, dormant) an empty limit still accepts but pays emptyCoins; a paid squeeze pays the
-- squeeze value the caller passes (Phase 3: a pad adds no Coin bonus, it only sets the tier); an unready profile earns
-- nothing (data.notReady); every reply's nextAt is a server time =
-- serverNow + max(0, 1 - tokens) × cycleSeconds. Clocks are plain numbers (os.clock, os.time and server time kept far
-- apart so a mix-up shows).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local CLOCK0 = 500 -- os.clock()
local OS0 = 1_790_000_000 -- os.time()
local SERVER0 = 1_790_000_123.25 -- workspace:GetServerTimeNow()
local MAT = Vector3.new(-33, 0.5, 37)
local ON_MAT = MAT + Vector3.new(0, 3, 0)

return function(t: Context)
	local SqueezeRules = t.requireServer("Logic/SqueezeRules")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local SQUEEZE = Config.Squeeze

	-- A request input with sensible defaults; `overrides` replaces fields.
	local function input(stateValue: any, overrides: { [string]: any }?): any
		local base: { [string]: any } = {
			now = CLOCK0,
			osNow = OS0,
			serverNow = SERVER0,
			state = stateValue,
			profileReady = true,
			station = { tier = 1 },
			rootPosition = ON_MAT,
			inMatch = false,
			level = 1,
			baseCoins = 5,
			limit = { value = 300, at = OS0 },
		}
		if overrides then
			for key, value in overrides do
				base[key] = value
			end
		end
		return base
	end

	local function fresh(): any
		return SqueezeRules.newState(CLOCK0)
	end

	-- The hourly limit is off since spec 2026-10-11 §5; the limit cases switch it back on (the rule stays, dormant).
	local LIMIT_ON = {
		Squeeze = Config.Squeeze,
		Grip = Config.Grip,
		Economy = { SqueezeLimit = { enabled = true, perHour = 600, burst = 300, emptyCoins = 0 } },
	}

	-- Bucket ------------------------------------------------------------------------------------------------------

	t.test("a new state has a full bucket", function()
		expect.equal(fresh().bucket.tokens, SQUEEZE.bucketCapacity)
	end)

	t.test("DESIGN values: a 12-per-second cap (capacity 12, 1/12 s cycle), a 20/s flood guard", function()
		expect.equal(SQUEEZE.bucketCapacity, 12)
		expect.near(SQUEEZE.cycleSeconds, 1 / 12, 1e-12)
		expect.equal(SQUEEZE.floodPerSecond, 20)
	end)

	t.test("the bucket accepts its capacity at once, then 1 per cycleSeconds", function()
		local bucket = fresh().bucket
		local accepted = 0
		for _ = 1, SQUEEZE.bucketCapacity + 3 do
			local ok
			ok, bucket = SqueezeRules.accept(bucket, CLOCK0)
			if ok then
				accepted += 1
			end
		end
		expect.equal(accepted, SQUEEZE.bucketCapacity)
		local early = SqueezeRules.accept(bucket, CLOCK0 + SQUEEZE.cycleSeconds - 0.01)
		expect.falsy(early)
		local onTime = SqueezeRules.accept(bucket, CLOCK0 + SQUEEZE.cycleSeconds)
		expect.truthy(onTime)
		expect.near(SqueezeRules.tokens(bucket, CLOCK0 + 100), SQUEEZE.bucketCapacity)
	end)

	t.test("secondsUntilNext = max(0, 1 - tokens) × cycleSeconds", function()
		local bucket = { tokens = 0, at = CLOCK0 }
		local half = SQUEEZE.cycleSeconds / 2
		expect.near(SqueezeRules.secondsUntilNext(bucket, CLOCK0), SQUEEZE.cycleSeconds)
		expect.near(SqueezeRules.secondsUntilNext(bucket, CLOCK0 + half), SQUEEZE.cycleSeconds - half)
		expect.equal(SqueezeRules.secondsUntilNext({ tokens = 1.5, at = CLOCK0 }, CLOCK0), 0)
	end)

	-- Flood guard -------------------------------------------------------------------------------------------------

	t.test("the flood guard lets floodPerSecond requests through in any second and drops the rest", function()
		local flood = fresh().flood
		local allowed = 0
		for i = 1, SQUEEZE.floodPerSecond + 3 do
			local ok
			ok, flood = SqueezeRules.flood(flood, CLOCK0 + i * 0.01)
			if ok then
				allowed += 1
			end
		end
		expect.equal(allowed, SQUEEZE.floodPerSecond)
		local later = SqueezeRules.flood(flood, CLOCK0 + 1.02)
		expect.truthy(later)
	end)

	t.test("more than floodLogDrops drops inside the log window log once", function()
		local flood = fresh().flood
		local logs = 0
		-- 2 × floodPerSecond requests per second for 3 s: floodPerSecond drops per second.
		local spacing = 1 / (2 * SQUEEZE.floodPerSecond)
		local count = math.floor(3 / spacing)
		for i = 1, count do
			local _, nextFlood, logNow = SqueezeRules.flood(flood, CLOCK0 + i * spacing)
			flood = nextFlood
			if logNow then
				logs += 1
			end
		end
		expect.equal(logs, 1)
		-- Quiet for longer than the window: the log re-arms and a new flood logs again.
		local restart = CLOCK0 + 3 + SQUEEZE.floodLogWindowSeconds + 1
		for i = 1, count do
			local _, nextFlood, logNow = SqueezeRules.flood(flood, restart + i * spacing)
			flood = nextFlood
			if logNow then
				logs += 1
			end
		end
		expect.equal(logs, 2)
	end)

	-- The pad under the player (spec 2026-10-11 §5) -------------------------------------------------------------------

	t.test("padUnder: the station the root stands on (Config.Squeeze's pad test), else nil", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		for _, id in WorldLayout.stationIds() do
			local station = WorldLayout.station(id)
			local standing = Vector3.new(station.position.X, station.top + 3, station.position.Z)
			local found = SqueezeRules.padUnder(standing)
			expect.equal(if found then found.id else nil, id)
			-- Too high above the pad top, or far off to the side: not on it.
			local above = Vector3.new(standing.X, station.top + SQUEEZE.heightAbove + 0.01, standing.Z)
			local high = SqueezeRules.padUnder(above)
			expect.truthy(high == nil or high.id ~= id)
		end
		expect.equal(SqueezeRules.padUnder(Vector3.new(0, 3, 40)), nil) -- the spawn: off every pad
		-- Phase 6: the margins come from the Squeeze section (Config.Grip has no slow-training block any more).
		local mat = WorldLayout.station("squeeze_01")
		local low = { Squeeze = { padMargin = 0, heightAbove = 2 }, Economy = Config.Economy, Grip = {} }
		local function at(height: number): Vector3
			return Vector3.new(mat.position.X, mat.top + height, mat.position.Z)
		end
		expect.equal(SqueezeRules.padUnder(at(3), low), nil)
		local found = SqueezeRules.padUnder(at(1), low)
		expect.equal(if found then found.id else nil, "squeeze_01")
	end)

	t.test("tierFor: the pad's tier when unlocked; off a pad, a locked pad or an unknown tier pay tier 1", function()
		local pads = Config.Grip.Pads
		expect.equal(SqueezeRules.tierFor(nil, 50), 1)
		for tier, pad in pads do
			expect.equal(SqueezeRules.tierFor({ tier = tier }, pad.level), tier)
			if pad.level > 1 then
				expect.equal(SqueezeRules.tierFor({ tier = tier }, pad.level - 1), 1)
			end
		end
		expect.equal(SqueezeRules.tierFor({ tier = #pads + 1 }, 50), 1)
	end)

	-- decide: the §6.3 order ------------------------------------------------------------------------------------

	t.test("an accepted squeeze at the Foam Mats pays the squishy's Coins and uses 1 limit point", function()
		local d = SqueezeRules.decide(input(fresh()), LIMIT_ON)
		expect.equal(d.outcome, "accepted")
		expect.equal(d.reason, nil)
		expect.truthy(d.paid)
		expect.equal(d.coins, 5)
		expect.equal(d.tier, 1)
		expect.near(d.limit.value, 299)
		expect.equal(d.limit.at, OS0)
		expect.near(d.state.bucket.tokens, SQUEEZE.bucketCapacity - 1)
	end)

	-- Phase 3 (spec 2026-10-12 §3): own squeezes pay the squeeze value; a pad adds no Coins (was + its coinBonus).
	t.test("an unlocked giant pad pays the same squeeze value and reports its tier", function()
		for tier, pad in Config.Grip.Pads do
			local d = SqueezeRules.decide(input(fresh(), { station = { tier = tier }, level = pad.level }), Config)
			expect.equal(d.outcome, "accepted")
			expect.equal(d.tier, tier)
			expect.equal(d.coins, 5)
		end
	end)

	t.test("a pad still locked for the player's level pays the base (tier 1): no pad bonus, one token", function()
		local royal = #Config.Grip.Pads
		local d = SqueezeRules.decide(input(fresh(), { station = { tier = royal }, level = 1 }), Config)
		expect.equal(d.outcome, "accepted")
		expect.equal(d.reason, nil)
		expect.truthy(d.paid)
		expect.equal(d.tier, 1)
		expect.equal(d.coins, 5)
		expect.near(d.state.bucket.tokens, SQUEEZE.bucketCapacity - 1)
	end)

	t.test("off a pad (no station under the player) the squeeze pays the base: tier 1, no pad bonus", function()
		local offPad = input(fresh(), { level = 50 })
		offPad.station = nil
		local d = SqueezeRules.decide(offPad, Config)
		expect.equal(d.outcome, "accepted")
		expect.truthy(d.paid)
		expect.equal(d.tier, 1)
		expect.equal(d.coins, 5)
	end)

	t.test("the shipped hourly limit is off: an empty limit state still pays full Coins and is left alone", function()
		expect.falsy(Config.Economy.SqueezeLimit.enabled)
		local limit = { value = 0, at = OS0 - 5 }
		local d = SqueezeRules.decide(input(fresh(), { limit = limit }), Config)
		expect.equal(d.outcome, "accepted")
		expect.truthy(d.paid)
		expect.equal(d.coins, 5)
		expect.deepEqual(d.limit, { value = 0, at = OS0 - 5 })
	end)

	t.test("an empty earnings limit still accepts the squeeze but pays emptyCoins", function()
		local d = SqueezeRules.decide(input(fresh(), { limit = { value = 0.5, at = OS0 } }), LIMIT_ON)
		expect.equal(d.outcome, "accepted")
		expect.falsy(d.paid)
		expect.equal(d.coins, LIMIT_ON.Economy.SqueezeLimit.emptyCoins)
		expect.near(d.limit.value, 0.5)
	end)

	t.test("a disabled earnings limit pays every squeeze and keeps the limit state", function()
		local cfg = {
			Squeeze = Config.Squeeze,
			Grip = Config.Grip,
			Economy = { SqueezeLimit = { enabled = false, perHour = 600, burst = 300, emptyCoins = 0 } },
		}
		local limit = { value = 0, at = OS0 }
		local d = SqueezeRules.decide(input(fresh(), { limit = limit }), cfg)
		expect.truthy(d.paid)
		expect.equal(d.coins, 5)
		expect.deepEqual(d.limit, { value = 0, at = OS0 })
	end)

	t.test("an unready profile earns nothing (data.notReady) and keeps its token", function()
		local d = SqueezeRules.decide(input(fresh(), { profileReady = false }), Config)
		expect.equal(d.outcome, "rejected")
		expect.equal(d.reason, "data.notReady")
		expect.equal(d.coins, 0)
		expect.equal(d.state.bucket.tokens, SQUEEZE.bucketCapacity)
	end)

	t.test("only a missing or dead character is refused (squeeze.noCharacter), with no token used", function()
		local noCharacter = input(fresh())
		noCharacter.rootPosition = nil
		local d = SqueezeRules.decide(noCharacter, Config)
		expect.equal(d.outcome, "rejected")
		expect.equal(d.reason, "squeeze.noCharacter")
		expect.equal(d.coins, 0)
		expect.falsy(d.paid)
		expect.equal(d.state.bucket.tokens, SQUEEZE.bucketCapacity)
		-- An unready profile is checked first (data.notReady), as before.
		noCharacter.profileReady = false
		expect.equal(SqueezeRules.decide(noCharacter, Config).reason, "data.notReady")
	end)

	t.test("a player in a match cannot squeeze (squeeze.inDuel)", function()
		local d = SqueezeRules.decide(input(fresh(), { inMatch = true }), Config)
		expect.equal(d.outcome, "rejected")
		expect.equal(d.reason, "squeeze.inDuel")
	end)

	t.test("an empty bucket gives squeeze.tooFast with nextAt at the next token, in server time", function()
		local s = fresh()
		for _ = 1, SQUEEZE.bucketCapacity do
			s = SqueezeRules.decide(input(s), Config).state
		end
		local quarter = SQUEEZE.cycleSeconds / 4
		local d = SqueezeRules.decide(input(s, { now = CLOCK0 + quarter, serverNow = SERVER0 + quarter }), Config)
		expect.equal(d.outcome, "rejected")
		expect.equal(d.reason, "squeeze.tooFast")
		expect.equal(d.coins, 0)
		expect.falsy(d.paid)
		expect.near(d.nextAt, SERVER0 + SQUEEZE.cycleSeconds, 1e-6)
	end)

	t.test("nextAt is serverNow + max(0, 1 - tokens) × cycleSeconds on every reply", function()
		local first = SqueezeRules.decide(input(fresh()), Config)
		expect.equal(first.nextAt, SERVER0) -- tokens left: the next squeeze can go now
		local s = first.state
		local last = first
		for _ = 2, SQUEEZE.bucketCapacity do
			last = SqueezeRules.decide(input(s), Config)
			s = last.state
		end
		expect.equal(last.outcome, "accepted")
		expect.near(last.nextAt, SERVER0 + SQUEEZE.cycleSeconds) -- the cap's bucket is empty now
		local rejected = SqueezeRules.decide(input(s, { profileReady = false }), Config)
		expect.near(rejected.nextAt, SERVER0 + SQUEEZE.cycleSeconds)
	end)

	t.test("a flooded request is dropped with no reason and no change to the bucket", function()
		local s = fresh()
		local outcomes = {}
		for i = 1, SQUEEZE.floodPerSecond + 1 do
			local d = SqueezeRules.decide(input(s, { now = CLOCK0 + i * 0.01 }), Config)
			s = d.state
			table.insert(outcomes, d.outcome)
		end
		expect.equal(outcomes[#outcomes], "dropped")
		local last = SqueezeRules.decide(input(s, { now = CLOCK0 + 0.06 }), Config)
		expect.equal(last.outcome, "dropped")
		expect.equal(last.reason, nil)
	end)

	-- Every click pays (2026-10-06) ---------------------------------------------------------------------------------

	-- `count` requests `spacing` seconds apart from CLOCK0 (os.clock and server time move together), with the limit
	-- carried from one to the next; returns the decisions in order and the state after them.
	local function presses(count: number, spacing: number, limit: any?, cfg: any?): ({ any }, any)
		local state = fresh()
		local decisions = {}
		local limitState = limit or { value = 300, at = OS0 }
		for i = 1, count do
			local t = (i - 1) * spacing
			local d = SqueezeRules.decide(
				input(state, { now = CLOCK0 + t, serverNow = SERVER0 + t, limit = limitState }),
				cfg or Config
			)
			state = d.state
			limitState = d.limit
			table.insert(decisions, d)
		end
		return decisions, state
	end

	t.test("12 presses in 1 s all pay (spread out or all at once)", function()
		for _, spacing in { 1 / 12, 0.05, 0 } do
			local decisions = presses(SQUEEZE.bucketCapacity, spacing)
			for i, d in decisions do
				if d.outcome ~= "accepted" or not d.paid or d.coins ~= 5 then
					error(`press {i} at {spacing} s spacing: {d.outcome} {tostring(d.reason)}, {d.coins} Coins`)
				end
			end
		end
	end)

	t.test("a 13th press in the same second is squeeze.tooFast with no Coins; the next cycle pays again", function()
		local decisions, s = presses(SQUEEZE.bucketCapacity + 1, 0)
		local last = decisions[#decisions]
		expect.equal(last.outcome, "rejected")
		expect.equal(last.reason, "squeeze.tooFast")
		expect.equal(last.coins, 0)
		expect.falsy(last.paid)
		expect.deepEqual(last.limit, decisions[#decisions - 1].limit) -- no limit point either
		local later = SqueezeRules.decide(
			input(s, { now = CLOCK0 + SQUEEZE.cycleSeconds, serverNow = SERVER0 + SQUEEZE.cycleSeconds }),
			Config
		)
		expect.equal(later.outcome, "accepted")
		expect.truthy(later.paid)
	end)

	t.test("clicking at 12 per second for 60 s: every press is accepted, never dropped or too fast", function()
		local decisions = presses(60 * 12, 1 / 12)
		for i, d in decisions do
			if d.outcome ~= "accepted" then
				error(`press {i}: {d.outcome} {tostring(d.reason)}`)
			end
		end
	end)

	t.test("a steady 20 requests per second for 30 s is never dropped by the flood guard", function()
		local decisions = presses(30 * 20, 1 / 20)
		local logged = false
		for i, d in decisions do
			if d.outcome == "dropped" then
				error(`request {i} was dropped`)
			end
			logged = logged or d.logFlood
		end
		expect.falsy(logged)
	end)

	t.test("fast clicking runs the earnings limit out: Coins stop, every press is still accepted", function()
		local decisions = presses(SQUEEZE.bucketCapacity, 1 / 12, { value = 5, at = OS0 }, LIMIT_ON)
		local paid, coins = 0, 0
		for _, d in decisions do
			expect.equal(d.outcome, "accepted")
			if d.paid then
				paid += 1
			end
			coins += d.coins
		end
		expect.equal(paid, 5)
		expect.equal(coins, 5 * 5 + (SQUEEZE.bucketCapacity - 5) * LIMIT_ON.Economy.SqueezeLimit.emptyCoins)
	end)

	t.test(
		"a 25/s macro for 30 s: the flood guard drops above 20/s, at most the burst plus 12/s is accepted",
		function()
			local s = fresh()
			local acceptedAt: { number } = {}
			local dropped, tooFast = 0, 0
			local spacing = 1 / 25
			for i = 1, 30 * 25 do
				local now = CLOCK0 + i * spacing
				local d = SqueezeRules.decide(input(s, { now = now, serverNow = SERVER0 + i * spacing }), Config)
				s = d.state
				if d.outcome == "accepted" then
					table.insert(acceptedAt, now)
				elseif d.outcome == "dropped" then
					dropped += 1
				elseif d.reason == "squeeze.tooFast" then
					tooFast += 1
				end
			end
			expect.truthy(dropped > 0)
			expect.truthy(tooFast > 0)
			local maxAccepted = SQUEEZE.bucketCapacity + math.floor(30 / SQUEEZE.cycleSeconds + 1e-6)
			expect.truthy(#acceptedAt <= maxAccepted)
			expect.truthy(#acceptedAt >= maxAccepted - 4) -- the limit really is the bucket, not something stricter
			-- The bucket bound for every stretch of time: squeezes accepted from the i-th to the j-th <= capacity +
			-- (t_j - t_i) / cycleSeconds.
			for i = 1, #acceptedAt do
				for j = i, #acceptedAt do
					local count = j - i + 1
					local bound = SQUEEZE.bucketCapacity + (acceptedAt[j] - acceptedAt[i]) / SQUEEZE.cycleSeconds + 1e-6
					if count > bound then
						error(
							string.format(
								"%d squeezes accepted between %.2f and %.2f",
								count,
								acceptedAt[i],
								acceptedAt[j]
							)
						)
					end
				end
			end
		end
	)

	-- Review: the cap is a bucket, so "12 a second" holds on average; a rested macro's first second gets up to the
	-- flood guard's 20. Kept on purpose (SqueezeRules header reading: a strict window would punish network jitter).
	t.test("a rested 20/s macro gets 20 in its first second, then 12 a second (12 + 12 × t in all)", function()
		local decisions = presses(4 * 20, 1 / 20)
		local perSecond = { 0, 0, 0, 0 }
		for i, d in decisions do
			if d.outcome == "accepted" then
				local second = math.floor((i - 1) / 20) + 1
				perSecond[second] += 1
			end
		end
		expect.equal(perSecond[1], SQUEEZE.floodPerSecond)
		expect.truthy(perSecond[4] <= 1 / SQUEEZE.cycleSeconds + 1)
		local total = perSecond[1] + perSecond[2] + perSecond[3] + perSecond[4]
		expect.truthy(total <= SQUEEZE.bucketCapacity + math.floor(4 / SQUEEZE.cycleSeconds + 1e-6))
	end)

	-- Review fix: a network stall delivers an honest clicker's queued presses at once (60 = 5 s of the cap, the
	-- SqueezeRequest remote burst). The flood guard lets 20 through (12 paid, 8 squeeze.tooFast with nothing earned),
	-- drops 40 silently and does not log it as a flood; the clicking after it is accepted again.
	t.test("a 5 s backlog arriving at once: 12 paid, 8 tooFast, 40 dropped, no flood log", function()
		local backlog = 5 * 12
		expect.truthy(Config.Net.Remotes.SqueezeRequest.burst >= backlog)
		local decisions, s = presses(backlog, 0)
		local paid, tooFast, dropped, logged = 0, 0, 0, false
		for _, d in decisions do
			logged = logged or d.logFlood
			if d.outcome == "accepted" and d.paid then
				paid += 1
			elseif d.outcome == "dropped" then
				dropped += 1
			elseif d.reason == "squeeze.tooFast" then
				tooFast += 1
				expect.equal(d.coins, 0)
			end
		end
		expect.equal(paid, SQUEEZE.bucketCapacity)
		expect.equal(tooFast, SQUEEZE.floodPerSecond - SQUEEZE.bucketCapacity)
		expect.equal(dropped, backlog - SQUEEZE.floodPerSecond)
		expect.falsy(logged)
		-- One second later the clicking (12 a second) is accepted again.
		for i = 1, 12 do
			local at = 1 + (i - 1) / 12
			local d = SqueezeRules.decide(input(s, { now = CLOCK0 + at, serverNow = SERVER0 + at }), Config)
			s = d.state
			if d.outcome ~= "accepted" then
				error(`press {i} after the backlog: {d.outcome} {tostring(d.reason)}`)
			end
		end
	end)
end
