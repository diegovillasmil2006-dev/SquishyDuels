--!strict
-- Matchmaker_Test: unit tests for ServerScriptService.Server.Logic.Matchmaker. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §5.4 Queue, §2.8 QueueJoin, §12 #15, #21, §17.12): one FIFO queue ordered by priority (requeued
-- after an opponent's bail = front) then joinedAt; the head pairs with the first later ticket that canPair, skipping
-- its last opponent while another partner exists; at most `capacity` pairs (free arena slots); getRating is nil, so
-- canPair is pure FIFO; a rating window applies only when both ratings exist; tickets built from two profiles that
-- differ only in the lobby Grip stat are identical and pair identically; the Studio test dummy is never in the real
-- queue; requeue cooldowns are 3 s after any match and 15 s after a bail; tickets time out after QueueMaxSeconds;
-- joinCheck runs the §2.8 checks in order.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local NOW = 2000

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

return function(t: Context)
	local Matchmaker = t.requireServer("Logic/Matchmaker")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local MM = Config.Duel.Matchmaking
	local RULES = Config.Duel.Rules

	local function ticket(userId: number, joinedAt: number, extra: { [string]: any }?): any
		local entry: { [string]: any } = { userId = userId, joinedAt = joinedAt, priority = MM.NormalPriority }
		if extra then
			for key, value in extra do
				entry[key] = value
			end
		end
		return entry
	end

	-- The pairs as { {a.userId, b.userId}, ... }.
	local function ids(found: { any }): { { number } }
		local out = {}
		for _, pair in found do
			table.insert(out, { pair.a.userId, pair.b.userId })
		end
		return out
	end

	local function join(overrides: { [string]: any }?): any
		local info: { [string]: any } = {
			closing = false,
			paused = false,
			arenaAvailable = true,
			isTestDummy = false,
			queued = false,
			inMatch = false,
			alive = true,
			cooldownUntil = nil,
		}
		if overrides then
			for key, value in overrides do
				info[key] = value
			end
		end
		return info
	end

	-- Rating hook and lobby stats --------------------------------------------------------------------------------------

	t.test("getRating is nil for any player: pure FIFO", function()
		expect.equal(Matchmaker.getRating({ userId = 1 }), nil)
		expect.equal(Matchmaker.getRating(nil), nil)
	end)

	t.test("lobby stats never matter: two profiles differing only in grip give identical tickets and pairs", function()
		local low = { userId = 7, grip = 0, level = 1 }
		local high = { userId = 7, grip = 100_000_000, level = 50 }
		local lowEntry = Matchmaker.newEntry(low, NOW, nil, nil, Config)
		local highEntry = Matchmaker.newEntry(high, NOW, nil, nil, Config)
		expect.deepEqual(lowEntry, highEntry)
		expect.equal(lowEntry.rating, nil)
		expect.equal((lowEntry :: any).grip, nil)
		-- In a queue with the same other tickets they pair the same way.
		local others = { ticket(1, NOW - 30), ticket(2, NOW - 20), ticket(3, NOW + 5) }
		local withLow = table.clone(others)
		table.insert(withLow, lowEntry)
		local withHigh = table.clone(others)
		table.insert(withHigh, highEntry)
		expect.deepEqual(
			ids(Matchmaker.pair(withLow, NOW + 10, nil, Config)),
			ids(Matchmaker.pair(withHigh, NOW + 10, nil, Config))
		)
	end)

	t.test("newEntry: default priority is NormalPriority; the last opponent is kept", function()
		local entry = Matchmaker.newEntry({ userId = 5 }, NOW, nil, 9, Config)
		expect.equal(entry.priority, MM.NormalPriority)
		expect.equal(entry.lastOpponentUserId, 9)
		expect.equal(entry.joinedAt, NOW)
		local requeued = Matchmaker.newEntry({ userId = 5 }, NOW, MM.RequeuePriority, nil, Config)
		expect.equal(requeued.priority, MM.RequeuePriority)
	end)

	-- FIFO and priority -------------------------------------------------------------------------------------------------

	t.test("FIFO: the earliest tickets pair first, in join order", function()
		local queue = { ticket(4, NOW - 1), ticket(1, NOW - 40), ticket(3, NOW - 10), ticket(2, NOW - 20) }
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 1, 2 }, { 3, 4 } })
	end)

	t.test("an odd ticket waits; one ticket alone never pairs", function()
		expect.deepEqual(
			ids(Matchmaker.pair({ ticket(1, NOW - 3), ticket(2, NOW - 2), ticket(3, NOW - 1) }, NOW, nil, Config)),
			{ { 1, 2 } }
		)
		expect.equal(#Matchmaker.pair({ ticket(1, NOW) }, NOW, nil, Config), 0)
		expect.equal(#Matchmaker.pair({}, NOW, nil, Config), 0)
	end)

	t.test("a ticket requeued after an opponent's bail goes to the front", function()
		local queue = {
			ticket(1, NOW - 50),
			ticket(2, NOW - 40),
			ticket(3, NOW - 1, { priority = MM.RequeuePriority }),
		}
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 3, 1 } })
		expect.equal(Matchmaker.position(queue, 3), 1)
		expect.equal(Matchmaker.position(queue, 1), 2)
		expect.equal(Matchmaker.position(queue, 2), 3)
		expect.equal(Matchmaker.position(queue, 99), nil)
	end)

	t.test("equal join times are ordered by userId (deterministic)", function()
		local queue = { ticket(30, NOW), ticket(10, NOW), ticket(20, NOW) }
		local ordered = Matchmaker.order(queue)
		expect.equal(ordered[1].userId, 10)
		expect.equal(ordered[2].userId, 20)
		expect.equal(ordered[3].userId, 30)
	end)

	-- Capacity = arena slots ---------------------------------------------------------------------------------------

	t.test("capacity limits the pairs to the free arena slots", function()
		local queue = {}
		for userId = 1, 8 do
			table.insert(queue, ticket(userId, NOW - 100 + userId))
		end
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, 2, Config)), { { 1, 2 }, { 3, 4 } })
		expect.equal(#Matchmaker.pair(queue, NOW, 0, Config), 0)
		expect.equal(#Matchmaker.pair(queue, NOW, nil, Config), 4)
		expect.equal(#Matchmaker.pair(queue, NOW, Config.Duel.Arena.MaxSlots, Config), 4)
	end)

	-- Immediate rematch ----------------------------------------------------------------------------------------------

	t.test("the head skips its last opponent while another partner exists", function()
		local queue = {
			ticket(1, NOW - 30, { lastOpponentUserId = 2 }),
			ticket(2, NOW - 20, { lastOpponentUserId = 1 }),
			ticket(3, NOW - 10),
		}
		expect.truthy(MM.AvoidImmediateRematch)
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 1, 3 } })
	end)

	t.test("a rematch is skipped even when only the other ticket remembers it", function()
		local queue = {
			ticket(1, NOW - 30),
			ticket(2, NOW - 20, { lastOpponentUserId = 1 }),
			ticket(3, NOW - 10),
		}
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 1, 3 } })
	end)

	t.test("with no other partner, last opponents are paired again", function()
		local queue =
			{ ticket(1, NOW - 30, { lastOpponentUserId = 2 }), ticket(2, NOW - 20, { lastOpponentUserId = 1 }) }
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 1, 2 } })
	end)

	t.test("AvoidImmediateRematch = false pairs plain FIFO", function()
		local duel = deepCopy(Config.Duel)
		duel.Matchmaking.AvoidImmediateRematch = false
		local queue = {
			ticket(1, NOW - 30, { lastOpponentUserId = 2 }),
			ticket(2, NOW - 20),
			ticket(3, NOW - 10),
		}
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, { Duel = duel })), { { 1, 2 } })
	end)

	-- canPair and the rating window ---------------------------------------------------------------------------------

	t.test("canPair: nil ratings always pair; a player never pairs with themself", function()
		expect.truthy(Matchmaker.canPair(ticket(1, NOW), ticket(2, NOW), NOW, Config))
		expect.truthy(Matchmaker.canPair(ticket(1, NOW, { rating = 1500 }), ticket(2, NOW), NOW, Config))
		expect.falsy(Matchmaker.canPair(ticket(1, NOW), ticket(1, NOW), NOW, Config))
	end)

	t.test("canPair: with both ratings, |a - b| <= base + growth × the longer wait", function()
		local duel = deepCopy(Config.Duel)
		duel.Matchmaking.RatingWindow = { base = 100, growthPerSecond = 10 }
		local cfg = { Duel = duel }
		local a = ticket(1, NOW, { rating = 1000 })
		local b = ticket(2, NOW + 2, { rating = 1150 })
		expect.falsy(Matchmaker.canPair(a, b, NOW, cfg)) -- window 100
		expect.falsy(Matchmaker.canPair(a, b, NOW + 4.9, cfg)) -- window 149
		expect.truthy(Matchmaker.canPair(a, b, NOW + 5, cfg)) -- window 150 (a has waited 5 s)
		-- The live Config window (unused in v1) is zero wide: only equal ratings pair.
		expect.truthy(Matchmaker.canPair(ticket(1, NOW, { rating = 7 }), ticket(2, NOW, { rating = 7 }), NOW, Config))
	end)

	t.test("pairing skips a head that cannot pair and serves the next one", function()
		local duel = deepCopy(Config.Duel)
		duel.Matchmaking.RatingWindow = { base = 10, growthPerSecond = 0 }
		local queue = {
			ticket(1, NOW - 30, { rating = 5000 }),
			ticket(2, NOW - 20, { rating = 1000 }),
			ticket(3, NOW - 10, { rating = 1005 }),
		}
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, { Duel = duel })), { { 2, 3 } })
	end)

	-- Never a Studio dummy in the real queue ---------------------------------------------------------------------------

	t.test("the Studio test dummy is never paired, ordered or counted in the real queue", function()
		local dummy = ticket(-1, NOW - 100, { isTestDummy = true })
		local queue = { dummy, ticket(1, NOW - 20), ticket(2, NOW - 10) }
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 1, 2 } })
		expect.equal(#Matchmaker.order(queue), 2)
		expect.equal(Matchmaker.position(queue, -1), nil)
		expect.equal(Matchmaker.position(queue, 1), 1)
		expect.falsy(Matchmaker.canPair(dummy, ticket(1, NOW), NOW, Config))
		expect.equal(#Matchmaker.pair({ dummy, ticket(1, NOW) }, NOW, nil, Config), 0)
		local dummyEntry = Matchmaker.newEntry({ userId = -1, isTestDummy = true }, NOW, nil, nil, Config)
		expect.truthy(dummyEntry.isTestDummy)
		local ok, reason = Matchmaker.joinCheck(join({ isTestDummy = true }), NOW)
		expect.falsy(ok)
		expect.equal(reason, "queue.unavailable")
	end)

	t.test("Studio test players with userIds <= 0 are real players and do pair", function()
		expect.deepEqual(
			ids(Matchmaker.pair({ ticket(-1, NOW - 2), ticket(-2, NOW - 1) }, NOW, nil, Config)),
			{ { -1, -2 } }
		)
	end)

	t.test("a second ticket for the same player is ignored", function()
		local queue = { ticket(1, NOW - 30), ticket(1, NOW - 20), ticket(2, NOW - 10) }
		expect.deepEqual(ids(Matchmaker.pair(queue, NOW, nil, Config)), { { 1, 2 } })
	end)

	t.test("pair and order never reorder or change the given list", function()
		local queue = { ticket(2, NOW - 10), ticket(1, NOW - 20) }
		Matchmaker.pair(queue, NOW, nil, Config)
		Matchmaker.order(queue)
		expect.equal(queue[1].userId, 2)
		expect.equal(queue[2].userId, 1)
	end)

	-- Timeouts and cooldowns -------------------------------------------------------------------------------------------

	t.test("a ticket times out after QueueMaxSeconds (queue.timedOut)", function()
		local entry = ticket(1, NOW)
		expect.equal(MM.QueueMaxSeconds, 300)
		expect.falsy(Matchmaker.isTimedOut(entry, NOW + MM.QueueMaxSeconds - 0.1, Config))
		expect.truthy(Matchmaker.isTimedOut(entry, NOW + MM.QueueMaxSeconds, Config))
	end)

	t.test("requeue cooldown: 3 s after any match", function()
		expect.equal(RULES.RequeueCooldownSeconds, 3)
		local untilTime = Matchmaker.cooldownUntil(NOW, false, Config)
		expect.equal(untilTime, NOW + 3)
		local ok, reason = Matchmaker.joinCheck(join({ cooldownUntil = untilTime }), NOW + 2.9)
		expect.falsy(ok)
		expect.equal(reason, "queue.cooldown")
		expect.truthy((Matchmaker.joinCheck(join({ cooldownUntil = untilTime }), NOW + 3)))
	end)

	t.test("requeue cooldown: 15 s after a bail", function()
		expect.equal(RULES.BailRequeueCooldownSeconds, 15)
		local untilTime = Matchmaker.cooldownUntil(NOW, true, Config)
		expect.equal(untilTime, NOW + 15)
		local ok, reason = Matchmaker.joinCheck(join({ cooldownUntil = untilTime }), NOW + 14.9)
		expect.falsy(ok)
		expect.equal(reason, "queue.cooldown")
		expect.truthy((Matchmaker.joinCheck(join({ cooldownUntil = untilTime }), NOW + 15)))
	end)

	-- QueueJoin checks (§2.8) --------------------------------------------------------------------------------------------

	t.test("joinCheck: each QueueJoin rejection, in DESIGN order", function()
		local cases: { { any } } = {
			{ { closing = true }, "queue.paused" },
			{ { paused = true }, "queue.paused" },
			{ { arenaAvailable = false }, "queue.unavailable" },
			{ { queued = true }, "queue.alreadyQueued" },
			{ { inMatch = true }, "queue.alreadyQueued" },
			{ { alive = false }, "queue.unavailable" },
			{ { cooldownUntil = NOW + 1 }, "queue.cooldown" },
			-- Several problems: the first check names the reason.
			{ { paused = true, queued = true, cooldownUntil = NOW + 1 }, "queue.paused" },
			{ { queued = true, alive = false }, "queue.alreadyQueued" },
		}
		for _, case in cases do
			local ok, reason = Matchmaker.joinCheck(join(case[1]), NOW)
			expect.falsy(ok)
			expect.equal(reason, case[2])
		end
		local ok, reason = Matchmaker.joinCheck(join(), NOW)
		expect.truthy(ok)
		expect.equal(reason, nil)
	end)
end
