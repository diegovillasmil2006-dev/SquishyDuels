--!strict
-- BotRules_Test: unit tests for ServerScriptService.Server.Logic.BotRules (the 1v1 practice bot, 2026-10-16).
-- Server only (ServerStorage.UnitTest). Pure: seeded Random objects, plain zones, no instances.
-- Contract (Logic/BotRules header, Config/Bots):
--   * name: <start><end>[_]<number> from the Strings.bot word lists, letters + digits + at most one underscore (never
--     first or last), 3-20 characters; the underscore chance is honoured at 0 and 1;
--   * fillDelay inside [fillDelayMinSeconds, fillDelayMaxSeconds] (the owner's 8-10 s with the shipped config);
--   * watch: a lone waiter is due only after its own delay; nobody alone or a different waiter starts over;
--   * aim: the miss is flat and never larger than min(base + perStud × distance, max), grows with distance, is 0 with a
--     zero spread; the lead is leadFraction × the flat velocity × the flight time;
--   * moves stay inside the own half shrunk by edgeMarginStuds (also on a turned zone), at least moveMinStuds away when
--     possible, and prefer a covered spot when coverChance says so;
--   * the dodge is a flat unit direction across the line of fire.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BotRules = t.requireServer("Logic/BotRules")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local BOTS = Config.Duel.Bots
	local STARTS, ENDS = Strings.bot.nameStarts, Strings.bot.nameEnds

	local function with(changes: { [string]: any }): any
		local copy = table.clone(BOTS)
		for key, value in changes do
			copy[key] = value
		end
		return copy
	end

	local function contains(list: { string }, word: string): boolean
		return table.find(list, word) ~= nil
	end

	local ZONE = { cframe = CFrame.new(100, 5, -40), size = Vector3.new(30, 10, 20) }

	local function insideZone(zone: any, point: Vector3, margin: number): boolean
		local localPoint = zone.cframe:PointToObjectSpace(Vector3.new(point.X, zone.cframe.Position.Y, point.Z))
		return math.abs(localPoint.X) <= zone.size.X / 2 - margin + 1e-6
			and math.abs(localPoint.Z) <= zone.size.Z / 2 - margin + 1e-6
	end

	t.test("names look like usernames and come from the word lists", function()
		local rng = Random.new(7)
		local seenUnderscore, seenPlain = false, false
		for _ = 1, 300 do
			local name = BotRules.name(rng, STARTS, ENDS, BOTS)
			expect.truthy(#name >= 3 and #name <= 20)
			expect.truthy(string.match(name, "^%a+_?%d+$") ~= nil)
			local _, underscores = string.gsub(name, "_", "")
			expect.truthy(underscores <= 1)
			local letters = string.match(name, "^(%a+)") :: string
			local found = false
			for _, first in STARTS do
				if string.sub(letters, 1, #first) == first and contains(ENDS, string.sub(letters, #first + 1)) then
					found = true
					break
				end
			end
			expect.truthy(found)
			local number = tonumber(string.match(name, "(%d+)$")) :: number
			expect.truthy(number >= BOTS.nameDigitsMin and number <= BOTS.nameDigitsMax)
			if underscores == 1 then
				seenUnderscore = true
			else
				seenPlain = true
			end
		end
		expect.truthy(seenUnderscore and seenPlain)
		expect.equal(
			BotRules.name(
				Random.new(1),
				{ "Squish" },
				{ "Fan" },
				with({ nameUnderscoreChance = 1, nameDigitsMin = 23, nameDigitsMax = 23 })
			),
			"SquishFan_23"
		)
		expect.equal(
			BotRules.name(
				Random.new(1),
				{ "Squish" },
				{ "Fan" },
				with({ nameUnderscoreChance = 0, nameDigitsMin = 7, nameDigitsMax = 7 })
			),
			"SquishFan7"
		)
	end)

	t.test("the fill delay stays inside the owner's 8-10 s", function()
		expect.equal(BOTS.fillDelayMinSeconds, 8)
		expect.equal(BOTS.fillDelayMaxSeconds, 10)
		local rng = Random.new(3)
		local low, high = math.huge, -math.huge
		for _ = 1, 500 do
			local delay = BotRules.fillDelay(rng, BOTS)
			expect.truthy(delay >= 8 and delay <= 10)
			low = math.min(low, delay)
			high = math.max(high, delay)
		end
		expect.truthy(low < 8.3 and high > 9.7) -- the whole range is used
		expect.equal(BotRules.fillDelay(rng, with({ fillDelayMinSeconds = 5, fillDelayMaxSeconds = 5 })), 5)
	end)

	t.test("watch: due only after the lone waiter's own delay; nobody alone or someone else starts over", function()
		local rng = Random.new(11)
		local cfg = with({ fillDelayMinSeconds = 9, fillDelayMaxSeconds = 9 })
		local w, due = BotRules.watch(nil, nil, 100, rng, cfg)
		expect.equal(w, nil)
		expect.equal(due, false)
		w, due = BotRules.watch(nil, 42, 100, rng, cfg)
		expect.equal(due, false)
		expect.equal(w.userId, 42)
		expect.equal(w.delay, 9)
		w, due = BotRules.watch(w, 42, 108.9, rng, cfg)
		expect.equal(due, false)
		w, due = BotRules.watch(w, 42, 109, rng, cfg)
		expect.equal(due, true)
		-- someone else is alone now: a fresh timer
		w, due = BotRules.watch(w, 43, 109, rng, cfg)
		expect.equal(due, false)
		expect.equal(w.since, 109)
		-- the waiter got company (or left): the timer is gone, and coming back starts over
		w, due = BotRules.watch(w, nil, 110, rng, cfg)
		expect.equal(w, nil)
		w, due = BotRules.watch(w, 43, 111, rng, cfg)
		expect.equal(w.since, 111)
		expect.equal(due, false)
	end)

	t.test("the aim miss is flat, bounded, grows with distance and can be switched off", function()
		local rng = Random.new(5)
		local function biggest(distance: number, cfg: any): number
			local most = 0
			for _ = 1, 400 do
				local offset = BotRules.aimOffset(rng, distance, cfg)
				expect.equal(offset.Y, 0)
				most = math.max(most, offset.Magnitude)
			end
			return most
		end
		local near, far = biggest(5, BOTS), biggest(60, BOTS)
		local nearCap = math.min(BOTS.aimErrorBaseStuds + BOTS.aimErrorPerStud * 5, BOTS.aimErrorMaxStuds)
		local farCap = math.min(BOTS.aimErrorBaseStuds + BOTS.aimErrorPerStud * 60, BOTS.aimErrorMaxStuds)
		expect.truthy(near <= nearCap + 1e-9)
		expect.truthy(far <= farCap + 1e-9)
		expect.truthy(far > near)
		expect.truthy(biggest(10000, BOTS) <= BOTS.aimErrorMaxStuds + 1e-9) -- the cap
		local none = with({ aimErrorBaseStuds = 0, aimErrorPerStud = 0, aimErrorMaxStuds = 0 })
		expect.equal(BotRules.aimOffset(rng, 50, none), Vector3.zero)
	end)

	t.test("the aim point leads by leadFraction of the flat velocity over the flight time", function()
		local rng = Random.new(9)
		local exact = with({ aimErrorBaseStuds = 0, aimErrorPerStud = 0, aimErrorMaxStuds = 0, leadFraction = 0.5 })
		local target = Vector3.new(10, 3, 20)
		local point = BotRules.aimPoint(rng, target, Vector3.new(8, 50, -4), 0.5, 30, exact)
		expect.near(point.X, 12, 1e-9)
		expect.near(point.Y, 3, 1e-9) -- a jump's speed is never led
		expect.near(point.Z, 19, 1e-9)
		expect.equal(BotRules.aimPoint(rng, target, Vector3.new(8, 0, 0), 0, 30, exact), target)
	end)

	t.test("moves stay inside the own half and walk somewhere new", function()
		local rng = Random.new(13)
		local turned =
			{ cframe = CFrame.new(-20, 0, 60) * CFrame.Angles(0, math.rad(30), 0), size = Vector3.new(24, 8, 40) }
		for _, zone in { ZONE, turned } do
			local from = zone.cframe.Position + Vector3.new(0, 3, 0)
			for _ = 1, 200 do
				local point = BotRules.pickMove(rng, zone, from, BOTS)
				expect.truthy(insideZone(zone, point, BOTS.edgeMarginStuds))
				expect.equal(point.Y, from.Y)
				from = point
			end
		end
		-- a zone too small for moveMinStuds still gives a point inside it
		local tiny = { cframe = CFrame.new(0, 0, 0), size = Vector3.new(7, 4, 7) }
		local point = BotRules.pickMove(rng, tiny, Vector3.zero, BOTS)
		expect.truthy(insideZone(tiny, point, BOTS.edgeMarginStuds))
	end)

	t.test("with coverChance a covered spot is preferred; without it cover is never asked", function()
		local rng = Random.new(17)
		local always = with({ coverChance = 1, moveCandidates = 16 })
		local from = ZONE.cframe.Position
		local covered = function(point: Vector3): boolean
			return point.X > from.X -- the right half of the zone is behind cover
		end
		local hits = 0
		for _ = 1, 100 do
			if BotRules.pickMove(rng, ZONE, from, always, covered).X > from.X then
				hits += 1
			end
		end
		expect.truthy(hits >= 90) -- 16 tries, each far enough and covered about 1 time in 3: a miss is ~0.2%
		local asked = 0
		BotRules.pickMove(rng, ZONE, from, with({ coverChance = 0 }), function(_point: Vector3): boolean
			asked += 1
			return true
		end)
		expect.equal(asked, 0)
	end)

	t.test("the dodge goes across the line of fire, flat and unit; between stays in range", function()
		local rng = Random.new(19)
		local from, threat = Vector3.new(0, 3, 0), Vector3.new(0, 3, 30)
		local left, right = false, false
		for _ = 1, 50 do
			local dir = BotRules.dodgeDir(rng, from, threat)
			expect.near(dir.Magnitude, 1, 1e-6)
			expect.equal(dir.Y, 0)
			expect.near(dir:Dot(Vector3.new(0, 0, 1)), 0, 1e-6)
			if dir.X > 0 then
				right = true
			else
				left = true
			end
		end
		expect.truthy(left and right)
		expect.near(BotRules.dodgeDir(rng, from, from).Magnitude, 1, 1e-6) -- no line: still a direction
		for _ = 1, 50 do
			local v = BotRules.between(rng, 0.35, 0.8)
			expect.truthy(v >= 0.35 and v <= 0.8)
		end
		expect.equal(BotRules.between(rng, 2, 2), 2)
	end)
end
