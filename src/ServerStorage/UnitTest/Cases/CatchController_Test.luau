--!strict
-- CatchController_Test: unit tests for StarterPlayerScripts.Client.Controllers.CatchController's pure helpers (feature 1,
-- 2026-10-11: the catch; design: the combat-effects page "Squishy Combat FP v2.html", html:342-345, 538, 560, 673-675).
-- Server only (ServerStorage.UnitTest). Edit mode: init() is never called.
-- Contract:
--   * the gate mirrors the server's rules (Logic/CatchRules): a live duel and alive (catch.context), not crushing,
--     rooted or winding up (catch.busy), cooldownSeconds since the last press (catch.cooldown);
--   * progress: 0 while the hands crush, else the cooldown since the last press, 1 before any;
--   * the crush's ease e = clamp((t - 0.12) / 0.9, 0, 1) (design: html:538);
--   * the prompt: within reach and moving toward the centre (design: html:673);
--   * the flash: up to Vfx.Flash.maxOverlayOpacity (0.3) over minPeakMs, never faster, then exp(-6t) (design: html:560,
--     675; the photosensitivity caps of Config.Vfx.Flash);
--   * parseEvent keeps a well-formed CatchEvent and drops anything else.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-9
local NOW = 1_800_000_000

return function(t: Context)
	local Catch = t.requireClient("Controllers/CatchController")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local CATCH = Config.Combat.Catch
	local FLASH = Config.Vfx.Flash

	local function facts(overrides: { [string]: any }?): any
		local f: { [string]: any } = {
			inDuel = true,
			alive = true,
			now = NOW,
			lastPressAt = -math.huge,
			handsBackAt = -math.huge,
			rooted = false,
			windup = false,
		}
		if overrides then
			for key, value in overrides do
				f[key] = value
			end
		end
		return f
	end

	t.test("the gate: context, then busy, then the cooldown (the server's codes)", function()
		expect.equal(Catch.gate(facts()), nil)
		expect.equal(Catch.gate(facts({ inDuel = false })), "catch.context")
		expect.equal(Catch.gate(facts({ alive = false })), "catch.context")
		expect.equal(Catch.gate(facts({ handsBackAt = NOW + 0.5 })), "catch.busy")
		expect.equal(Catch.gate(facts({ rooted = true })), "catch.busy")
		expect.equal(Catch.gate(facts({ windup = true })), "catch.busy")
		expect.equal(Catch.gate(facts({ lastPressAt = NOW - 0.5 })), "catch.cooldown")
		expect.equal(Catch.gate(facts({ lastPressAt = NOW - CATCH.cooldownSeconds })), nil)
		expect.equal(Catch.gate(facts({ inDuel = false, rooted = true })), "catch.context")
	end)

	t.test("qb1: a match is live for the catch like a duel; the prompt follows enemies, never teammates", function()
		expect.equal(Catch.liveIn(nil, nil), false)
		expect.equal(Catch.liveIn({ phase = "Active" }, nil), true)
		expect.equal(Catch.liveIn(nil, { phase = "SuddenDeath" }), true)
		expect.equal(Catch.liveIn(nil, { phase = "Countdown" }), false)
		expect.equal(Catch.liveIn(nil, { phase = "Result" }), false)
		expect.equal(Catch.followsThrower({ opponent = { userId = 7 } }, nil, 7), true)
		expect.equal(Catch.followsThrower({ opponent = { userId = 7 } }, nil, 8), false)
		local function tdm(mode: string): any
			return {
				mode = mode,
				you = { userId = 1, team = "Strawberry" },
				players = {
					{ userId = 1, team = "Strawberry" },
					{ userId = 2, team = "Strawberry" },
					{ userId = 3, team = "Blueberry" },
				},
			}
		end
		expect.equal(Catch.followsThrower(nil, tdm("tdm"), 3), true) -- an enemy
		expect.equal(Catch.followsThrower(nil, tdm("tdm"), 2), false) -- a teammate
		expect.equal(Catch.followsThrower(nil, tdm("ffa"), 2), true) -- FFA: everyone else
		expect.equal(Catch.followsThrower(nil, tdm("ffa"), 1), false) -- never your own throw
		expect.equal(Catch.followsThrower(nil, nil, 3), false)
	end)

	t.test("progress: 1 before any press, the cooldown after one, 0 while crushing", function()
		expect.equal(Catch.progress(NOW, -math.huge, -math.huge), 1)
		expect.near(Catch.progress(NOW, NOW - CATCH.cooldownSeconds / 2, -math.huge), 0.5, 1e-6)
		expect.equal(Catch.progress(NOW, NOW - 5, -math.huge), 1)
		expect.equal(Catch.progress(NOW, NOW - 5, NOW + 0.2), 0)
	end)

	t.test("the crush's ease: 0 until 0.12 s, 1 at 1.02 s (design: html:538)", function()
		expect.equal(Catch.crushEase(0), 0)
		expect.equal(Catch.crushEase(0.12), 0)
		expect.near(Catch.crushEase(0.57), 0.5, 1e-9)
		expect.near(Catch.crushEase(1.02), 1, 1e-9)
		expect.equal(Catch.crushEase(3), 1)
	end)

	t.test("the prompt: within reach and moving toward the centre (design: html:673)", function()
		local centre = Vector3.new(0, 4.5, 0)
		local reach = Config.UI.Reticle.catchPromptStuds
		expect.near(reach, 9 / 0.28, 1e-9)
		expect.truthy(Catch.comingAt(Vector3.new(0, 4.5, 20), Vector3.new(0, 0, -50), centre, reach))
		expect.falsy(Catch.comingAt(Vector3.new(0, 4.5, 20), Vector3.new(0, 0, 50), centre, reach)) -- going away
		expect.falsy(Catch.comingAt(Vector3.new(0, 4.5, 40), Vector3.new(0, 0, -50), centre, reach)) -- too far
	end)

	t.test("the flash: up to the overlay cap over minPeakMs (never faster), then the design's decay", function()
		local rise = FLASH.minPeakMs / 1000
		expect.equal(Catch.flashOpacity(-0.1), 0)
		expect.equal(Catch.flashOpacity(0), 0)
		expect.near(Catch.flashOpacity(rise / 2), FLASH.maxOverlayOpacity / 2, 1e-9)
		expect.near(Catch.flashOpacity(rise), FLASH.maxOverlayOpacity, 1e-9)
		expect.near(Catch.flashOpacity(rise + 0.5), FLASH.maxOverlayOpacity * math.exp(-3), 1e-9)
		expect.truthy(FLASH.maxOverlayOpacity <= 0.3 + EPS and FLASH.minPeakMs >= 80)
	end)

	t.test("parseEvent keeps a well-formed CatchEvent and drops anything else", function()
		local good = {
			phase = "caught",
			matchId = "m",
			catcherId = 2,
			throwerId = 1,
			projId = 7,
			squishyId = "kitty_bread",
			position = Vector3.new(1, 2, 3),
			at = NOW,
			burstAt = NOW + CATCH.crushSeconds,
		}
		expect.truthy(Catch.parseEvent(good))
		local burst = table.clone(good)
		burst.phase = "burst"
		burst.livesLeft = 2
		burst.invulnUntil = NOW + 1
		expect.truthy(Catch.parseEvent(burst))
		expect.equal(Catch.parseEvent(nil), nil)
		expect.equal(Catch.parseEvent("caught"), nil)
		for field, bad in { phase = "thrown", catcherId = "2", position = "here", at = 0 / 0, squishyId = 5 } :: any do
			local copy = table.clone(good) :: any
			copy[field] = bad
			expect.equal(Catch.parseEvent(copy), nil)
		end
		local badLives = table.clone(burst) :: any
		badLives.livesLeft = "two"
		expect.equal(Catch.parseEvent(badLives), nil)
	end)

	t.test("outside a duel: not ready, not crushing, no prompt, nothing in the hands", function()
		local state = Catch.state()
		expect.falsy(state.ready)
		expect.falsy(state.crushing)
		expect.falsy(state.open)
		expect.falsy(Catch.incoming())
		expect.equal((Catch.localCatch()), nil)
	end)
end
