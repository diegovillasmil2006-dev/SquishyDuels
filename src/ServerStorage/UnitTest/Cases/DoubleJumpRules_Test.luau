--!strict
-- DoubleJumpRules_Test: unit tests for ServerScriptService.Server.Logic.DoubleJumpRules (2026-10-15 double jump).
-- Server only (ServerStorage.UnitTest). Pure: no instances.
-- Contract:
--   * a valid request in Active or SuddenDeath is accepted with its key; lastSeq advances to its seq;
--   * a bad seq, key or clientTime is a payload violation (net.invalid), a replayed seq too;
--   * refused without a violation: outside a duel or a live phase, dead (jump.context), rooted (jump.busy), sooner
--     than serverIntervalSeconds after the last accepted one (jump.cooldown);
--   * isKey accepts exactly "F", "B", "L", "R".

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Rules = t.requireServer("Logic/DoubleJumpRules")
	local Config = t.requireShared("Config")
	local INTERVAL = Config.Duel.Rules.DoubleJump.serverIntervalSeconds
	local NOW = 1.7e9 + 100

	local function state(overrides: { [string]: any }?): any
		local s: { [string]: any } = {
			lastSeq = 4,
			lastJumpAt = -math.huge,
			inDuel = true,
			matchPhase = "Active",
			alive = true,
			rooted = false,
		}
		for key, value in overrides or {} do
			s[key] = value
		end
		return s
	end

	local function input(seq: any, key: any, clientTime: any?): any
		return { seq = seq, key = key, clientTime = if clientTime == nil then NOW else clientTime }
	end

	t.test("a valid double jump in Active or SuddenDeath is accepted with its key", function()
		local d = Rules.validate(input(5, "F"), state(), nil, NOW)
		expect.truthy(d.ok)
		expect.equal(d.key, "F")
		expect.equal(d.lastSeq, 5)
		expect.falsy(d.violation)
		local sd = Rules.validate(input(9, "L"), state({ matchPhase = "SuddenDeath" }), nil, NOW)
		expect.truthy(sd.ok)
		expect.equal(sd.key, "L")
	end)

	t.test("a bad payload or a replayed seq is a violation", function()
		for _, bad in { input(4, "F"), input(3, "F"), input(5.5, "F"), input("6", "F") } do
			local d = Rules.validate(bad, state(), nil, NOW)
			expect.falsy(d.ok)
			expect.equal(d.reason, "net.invalid")
			expect.truthy(d.violation)
			expect.equal(d.lastSeq, 4)
		end
		for _, key in { "X", "", 1, nil :: any } do
			local d = Rules.validate(input(6, key), state(), nil, NOW)
			expect.equal(d.reason, "net.invalid")
			expect.truthy(d.violation)
			expect.equal(d.lastSeq, 6) -- the seq passed, so it can never be replayed
		end
		local late = Rules.validate(input(7, "F", "soon"), state(), nil, NOW)
		expect.equal(late.reason, "net.invalid")
	end)

	t.test("refused outside a live duel, when dead, rooted or too soon", function()
		expect.equal(Rules.validate(input(5, "F"), state({ inDuel = false }), nil, NOW).reason, "jump.context")
		for _, phase in { "Countdown", "Intro", "Result" } do
			expect.equal(Rules.validate(input(5, "F"), state({ matchPhase = phase }), nil, NOW).reason, "jump.context")
		end
		expect.equal(Rules.validate(input(5, "F"), state({ alive = false }), nil, NOW).reason, "jump.context")
		local rooted = Rules.validate(input(5, "F"), state({ rooted = true }), nil, NOW)
		expect.equal(rooted.reason, "jump.busy")
		expect.falsy(rooted.violation)
		local soon = Rules.validate(input(5, "F"), state({ lastJumpAt = NOW - INTERVAL / 2 }), nil, NOW)
		expect.equal(soon.reason, "jump.cooldown")
		expect.equal(soon.lastSeq, 5)
		expect.truthy(Rules.validate(input(5, "F"), state({ lastJumpAt = NOW - INTERVAL }), nil, NOW).ok)
	end)

	t.test("isKey accepts exactly F, B, L and R", function()
		for _, key in { "F", "B", "L", "R" } do
			expect.truthy(Rules.isKey(key))
		end
		for _, key in { "f", "U", "", "FB", 1, true, nil :: any } do
			expect.falsy(Rules.isKey(key))
		end
	end)
end
