--!strict
-- MovementRules_Test: unit tests for ServerScriptService.Server.Logic.MovementRules. Server only
-- (ServerStorage.UnitTest).
-- Contract (DESIGN §5.7 movement guard, §5.4 out of bounds, §12 #13): sampled at 5 Hz; below KillY (floor - 15) or
-- outside the own half + 2 studs is out of bounds; the neutral zone, the opponent's half or the inside of Geometry
-- pulls the player back to the last valid position; more than 30 studs/s horizontally for 3 samples in a row, outside
-- the teleport/knockback grace, pulls back too; a pull-back or out-of-bounds starts its own teleport grace. A player
-- who must stand still (Countdown on the pad, a Dragon Rush root) and drifts more than holdToleranceStuds (+ slack)
-- from the spot is pulled back to it, outside a grace. Repeated out-of-bounds in Active ends in a forfeit through
-- DuelRules (the 7th); before Active it never counts.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

local T0 = 300
local DT = 0.2 -- 5 Hz

-- Arena zones relative to a floor at Y 0 (WorldLayout.Arena.zones; Y -15..40).
local HALF_A = { cframe = CFrame.new(0, 12.5, -30), size = Vector3.new(72, 55, 44) }
local NEUTRAL = { cframe = CFrame.new(0, 12.5, 0), size = Vector3.new(72, 55, 16) }
local HALF_B = { cframe = CFrame.new(0, 12.5, 30), size = Vector3.new(72, 55, 44) }
local ZONES_A = { own = HALF_A, neutral = NEUTRAL, opponent = HALF_B, floorY = 0 }

return function(t: Context)
	local MovementRules = t.requireServer("Logic/MovementRules")
	local DuelRules = t.requireServer("Logic/DuelRules")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local GUARD = Config.Combat.MovementGuard
	local OOB = Config.Duel.Rules.OutOfBounds

	local function sample(x: number, y: number, z: number, insideGeometry: boolean?): any
		return { position = Vector3.new(x, y, z), insideGeometry = insideGeometry }
	end

	local function evaluate(guard: any, s: any, now: number, zones: any?): any
		return MovementRules.evaluate(guard, s, zones or ZONES_A, now, Config)
	end

	-- Config ------------------------------------------------------------------------------------------------------------

	t.test("the guard runs at 5 Hz with a 30 studs/s limit over 3 samples", function()
		expect.equal(GUARD.checkHz, 5)
		expect.equal(GUARD.maxHorizontalSpeed, 30)
		expect.equal(GUARD.overSpeedSamples, 3)
		expect.equal(OOB.KillYOffset, -15)
		expect.equal(OOB.HalfToleranceStuds, 2)
	end)

	-- Valid movement ------------------------------------------------------------------------------------------------------

	t.test("walking (16 studs/s) and jumping in the own half is fine", function()
		local guard = MovementRules.new()
		local z = -50 -- 11 samples at 3.2 studs each end at Z -18, well inside the half
		for i = 0, 10 do
			local y = if i % 2 == 0 then 3 else 8 -- jumping changes Y only
			local verdict = evaluate(guard, sample(0, y, z), T0 + i * DT)
			expect.equal(verdict.action, "ok")
			z += 16 * DT
		end
		expect.truthy(guard.lastValid ~= nil)
		expect.equal(guard.overSpeed, 0)
	end)

	t.test("falling fast is not horizontal speed", function()
		local guard = MovementRules.new()
		for i = 0, 5 do
			-- 40 studs/s straight down, from Y 30 to Y -10 (above KillY)
			expect.equal(evaluate(guard, sample(0, 30 - i * 8, -30), T0 + i * DT).action, "ok")
		end
	end)

	-- Out of bounds -----------------------------------------------------------------------------------------------------

	t.test("below KillY (floor - 15) is out of bounds", function()
		local guard = MovementRules.new()
		expect.equal(evaluate(guard, sample(0, -14.9, -30), T0).action, "ok")
		local verdict = evaluate(guard, sample(0, -15.1, -30), T0 + DT)
		expect.equal(verdict.action, "outOfBounds")
		expect.equal(verdict.reason, "killY")
		-- KillY follows the floor of the slot.
		local high = { own = HALF_A, neutral = NEUTRAL, opponent = HALF_B, floorY = 100 }
		expect.equal(evaluate(MovementRules.new(), sample(0, 80, -30), T0, high).reason, "killY")
	end)

	t.test("outside the own half + 2 studs is out of bounds", function()
		expect.equal(evaluate(MovementRules.new(), sample(37.9, 3, -30), T0).action, "ok") -- on the side gutter
		local wide = evaluate(MovementRules.new(), sample(38.1, 3, -30), T0)
		expect.equal(wide.action, "outOfBounds")
		expect.equal(wide.reason, "outside")
		expect.equal(evaluate(MovementRules.new(), sample(0, 3, -54.1), T0).reason, "outside")
		expect.equal(evaluate(MovementRules.new(), sample(0, 3, -5.9), T0).reason, "outside")
		expect.equal(evaluate(MovementRules.new(), sample(0, 3, 30), T0).reason, "outside") -- the opponent's half
	end)

	-- Pull back -------------------------------------------------------------------------------------------------------

	t.test("the neutral zone pulls back to the last valid position", function()
		local guard = MovementRules.new()
		evaluate(guard, sample(0, 3, -10), T0)
		local verdict = evaluate(guard, sample(0, 3, -7), T0 + DT) -- 1 stud into the neutral zone
		expect.equal(verdict.action, "pivotBack")
		expect.equal(verdict.reason, "neutral")
		expect.truthy(verdict.target ~= nil and (verdict.target - Vector3.new(0, 3, -10)).Magnitude < 1e-4)
	end)

	t.test("the opponent's half pulls back (layouts where it touches the own margin)", function()
		local zones = {
			own = HALF_A,
			opponent = { cframe = CFrame.new(0, 12.5, 22), size = Vector3.new(72, 55, 58) },
			floorY = 0,
		}
		local guard = MovementRules.new()
		evaluate(guard, sample(0, 3, -20), T0, zones)
		local verdict = evaluate(guard, sample(0, 3, -6.5), T0 + DT, zones)
		expect.equal(verdict.action, "pivotBack")
		expect.equal(verdict.reason, "opponentHalf")
	end)

	t.test("inside a Geometry volume pulls back", function()
		local guard = MovementRules.new()
		evaluate(guard, sample(5, 3, -30), T0)
		local verdict = evaluate(guard, sample(5.5, 3, -30, true), T0 + DT)
		expect.equal(verdict.action, "pivotBack")
		expect.equal(verdict.reason, "geometry")
		expect.truthy((verdict.target - Vector3.new(5, 3, -30)).Magnitude < 1e-4)
	end)

	t.test("a pull back before any valid sample has no target (use the own pad)", function()
		local verdict = evaluate(MovementRules.new(), sample(0, 3, -7), T0)
		expect.equal(verdict.action, "pivotBack")
		expect.equal(verdict.target, nil)
	end)

	-- Speed ---------------------------------------------------------------------------------------------------------------

	t.test("over 30 studs/s for 3 samples in a row pulls back to the last normal position", function()
		local guard = MovementRules.new()
		evaluate(guard, sample(0, 3, -50), T0) -- last normal position
		local z = -50
		local verdicts = {}
		for i = 1, 3 do
			z += 40 * DT -- 40 studs/s
			table.insert(verdicts, evaluate(guard, sample(0, 3, z), T0 + i * DT))
		end
		expect.equal(verdicts[1].action, "ok")
		expect.equal(verdicts[2].action, "ok")
		expect.equal(verdicts[3].action, "pivotBack")
		expect.equal(verdicts[3].reason, "speed")
		expect.near(verdicts[3].speed, 40, 1e-3)
		expect.truthy((verdicts[3].target - Vector3.new(0, 3, -50)).Magnitude < 1e-4)
	end)

	t.test("two fast samples then a normal one reset the streak", function()
		local guard = MovementRules.new()
		local positions = { -50, -42, -34, -31, -23, -15 } -- fast, fast, slow, fast, fast
		for i, z in positions do
			local verdict = evaluate(guard, sample(0, 3, z), T0 + (i - 1) * DT)
			expect.equal(verdict.action, "ok")
		end
	end)

	t.test("knockback grace: fast samples inside the grace never count", function()
		local guard = MovementRules.new()
		evaluate(guard, sample(0, 3, -50), T0)
		MovementRules.grace(guard, T0 + GUARD.hitGraceSeconds)
		local z = -50
		for i = 1, 2 do
			z += 40 * DT
			expect.equal(evaluate(guard, sample(0, 3, z), T0 + i * DT).action, "ok") -- inside the 0.5 s grace
		end
		-- After the grace the streak starts from scratch: two more fast samples are still fine.
		for i = 3, 4 do
			z += 40 * DT
			expect.equal(evaluate(guard, sample(0, 3, z), T0 + i * DT).action, "ok")
		end
		z += 40 * DT
		expect.equal(evaluate(guard, sample(0, 3, z), T0 + 5 * DT).action, "pivotBack")
	end)

	t.test("a pull back starts the teleport grace: the jump back to safety is not speed", function()
		local guard = MovementRules.new()
		evaluate(guard, sample(0, 3, -40), T0)
		local verdict = evaluate(guard, sample(0, 3, -7), T0 + DT)
		expect.equal(verdict.action, "pivotBack")
		expect.equal(guard.graceUntil, T0 + DT + GUARD.teleportGraceSeconds)
		expect.equal(guard.previous, nil)
		-- The server pivots back 33 studs: no previous sample, so no speed is measured.
		local back = evaluate(guard, sample(0, 3, -40), T0 + 2 * DT)
		expect.equal(back.action, "ok")
		expect.equal(back.speed, nil)
	end)

	t.test("a sample at the same time as the previous one measures no speed", function()
		local guard = MovementRules.new()
		evaluate(guard, sample(0, 3, -50), T0)
		local verdict = evaluate(guard, sample(0, 3, -20), T0)
		expect.equal(verdict.action, "ok")
		expect.equal(verdict.speed, nil)
	end)

	-- Held in place (§5.4 Countdown freeze, §5.9 Dragon Rush root; the server checks it, WalkSpeed 0 is client-side) ----

	local function held(x: number, z: number, holdAt: Vector3?, slack: number?): any
		return { position = Vector3.new(x, 3, z), held = true, holdAt = holdAt, holdSlack = slack }
	end

	t.test("held with a known spot (the own pad): a drift beyond holdToleranceStuds pivots back to it", function()
		local pad = Vector3.new(0, 3, -44)
		local guard = MovementRules.new()
		local inside = GUARD.holdToleranceStuds * 0.9
		expect.equal(evaluate(guard, held(inside, -44, pad), T0).action, "ok")
		local verdict = evaluate(guard, held(GUARD.holdToleranceStuds + 2, -44, pad), T0 + DT)
		expect.equal(verdict.action, "pivotBack")
		expect.equal(verdict.reason, "held")
		expect.truthy((verdict.target - pad).Magnitude < 1e-4)
		-- Jumping in place is not a drift (horizontal distance only).
		local up = { position = Vector3.new(0, 9, -44), held = true, holdAt = pad }
		expect.equal(evaluate(MovementRules.new(), up, T0).action, "ok")
	end)

	t.test("held without a spot (a root): the first held sample is the anchor until the hold ends", function()
		local guard = MovementRules.new()
		expect.equal(evaluate(guard, held(10, -30, nil), T0).action, "ok")
		expect.truthy(guard.anchor ~= nil and (guard.anchor - Vector3.new(10, 3, -30)).Magnitude < 1e-4)
		-- Walking 3.2 studs in a sample (a client that ignores WalkSpeed 0) is pulled back to the anchor.
		local verdict = evaluate(guard, held(10, -26.8, nil), T0 + DT)
		expect.equal(verdict.action, "pivotBack")
		expect.equal(verdict.reason, "held")
		expect.truthy((verdict.target - Vector3.new(10, 3, -30)).Magnitude < 1e-4)
		-- The pull back's grace does not move the anchor: after it, the same drift is pulled back again.
		local later = T0 + DT + GUARD.teleportGraceSeconds + DT
		expect.equal(evaluate(guard, held(10, -26.8, nil), later).reason, "held")
		-- The hold ends: free movement, and the next hold anchors afresh.
		expect.equal(evaluate(guard, sample(10, 3, -20), later + DT).action, "ok")
		expect.equal(guard.anchor, nil)
		expect.equal(evaluate(guard, held(10, -20, nil), later + 2 * DT).action, "ok")
		expect.truthy((guard.anchor - Vector3.new(10, 3, -20)).Magnitude < 1e-4)
	end)

	t.test("held: the slack (stopping distance at the player's ping) widens the tolerance; a grace skips it", function()
		local guard = MovementRules.new()
		evaluate(guard, held(0, -30, nil, 2), T0)
		local drift = GUARD.holdToleranceStuds + 1.5 -- inside tolerance + slack 2
		expect.equal(evaluate(guard, held(drift, -30, nil, 2), T0 + DT).action, "ok")
		expect.equal(evaluate(guard, held(drift, -30, nil, 0), T0 + 2 * DT).reason, "held")
		-- Knockback after a hit: inside the hit grace the drift is allowed.
		local knocked = MovementRules.new()
		evaluate(knocked, held(0, -30, nil), T0)
		MovementRules.grace(knocked, T0 + GUARD.hitGraceSeconds)
		expect.equal(evaluate(knocked, held(4, -30, nil), T0 + DT).action, "ok")
	end)

	-- Out of bounds -> forfeit after repeats (with DuelRules) ---------------------------------------------------------

	local function activeMatch(): (any, number)
		local s = DuelRules.new("m", { A = { userId = 1 }, B = { userId = 2 } }, T0, Config.Duel)
		s = DuelRules.step(s, { kind = "streamed", side = "A" }, T0)
		s = DuelRules.step(s, { kind = "streamed", side = "B" }, T0)
		s = DuelRules.step(s, { kind = "positioned", side = "A" }, T0)
		s = DuelRules.step(s, { kind = "positioned", side = "B" }, T0)
		local startAt = s.phaseEndsAt
		s = DuelRules.step(s, { kind = "tick" }, startAt)
		return s, startAt
	end

	t.test("repeated out-of-bounds in Active: the 7th is a forfeit", function()
		local s, startAt = activeMatch()
		local guard = MovementRules.new()
		local now = startAt + 25
		local outs = 0
		while not s.ended and outs < 20 do
			local verdict = evaluate(guard, sample(0, -20, -30), now) -- fell off: below KillY
			expect.equal(verdict.action, "outOfBounds")
			outs += 1
			local effects
			s, effects = DuelRules.step(s, { kind = "oob", side = "A" }, now)
			if not s.ended then
				local repivot
				for _, effect in effects do
					if effect.kind == "repivot" then
						repivot = effect
					end
				end
				expect.equal(repivot.count, outs)
				MovementRules.grace(guard, repivot.invulnUntil)
			end
			now += 2
		end
		expect.equal(outs, OOB.MaxPerMatch + 1)
		expect.equal(s.outcome.kind, "win")
		expect.equal(s.outcome.winner, "B")
	end)

	t.test("out of bounds during Countdown is only re-pivoted, never counted", function()
		local s = DuelRules.new("m", { A = { userId = 1 }, B = { userId = 2 } }, T0, Config.Duel)
		s = DuelRules.step(s, { kind = "streamed", side = "A" }, T0)
		s = DuelRules.step(s, { kind = "streamed", side = "B" }, T0)
		s = DuelRules.step(s, { kind = "positioned", side = "A" }, T0)
		s = DuelRules.step(s, { kind = "positioned", side = "B" }, T0)
		expect.equal(s.phase, "Countdown")
		for _ = 1, OOB.MaxPerMatch + 3 do
			s = DuelRules.step(s, { kind = "oob", side = "A" }, T0 + 1)
		end
		expect.falsy(s.ended)
		expect.equal(s.participants.A.outOfBounds, 0)
	end)
end
