--!strict
-- HeldSquishyController_Test: unit tests for StarterPlayerScripts.Client.Controllers.HeldSquishyController (the
-- pure weld rule). Server only (ServerStorage.UnitTest). Edit mode: init() is not called, no Players or characters;
-- hands are in-memory Parts.
-- Contract (DESIGN §9.5): the held model's weld C0 is the hand's RightGripAttachment.CFrame. A hand without that
-- attachment gets the stock attachment's frame (bottom of the hand, turned -90° about X as on the standard R15
-- RightHand and R6 Right Arm), so hold.grip and heldYaw (C1) point the squishy the same way on every rig.
-- Feel pass (DESIGN §18.5.1 A6, Config.Anim.held):
--   * the lobby idle (SD_DuelPhase "" or unset: period 2.8 s, ampY 0.035, ampXZ 0.0175, bob 0.05) vs the duel idle
--     (§9.5: 2.4 s, 0.025, 0.0125, 0.03), crossfaded over 0.5 s; ReducedMotion halves the idle;
--   * the movement jiggle: a horizontal speed change kicks clamp(|Δv| / 60, 0, 0.05); a landing (vy from <= -15 to
--     >= -1) kicks 0.06.
-- Squishy overhaul (spec 2026-10-09 §3.2): the kicks go to the toy's rig (its feel spring: a kick peaks at kick × the
-- feel gain, the shown jiggle never past maxJ 0.08); detail levels: the own model is "hero", the next 6 by distance
-- "near" (phone 3), the rest "far" up to deformingRigs 12 (phone 8, also while the quality is still unknown), none
-- beyond; the rig slots the held models leave go to the Collection displays first, the rest to the lobby breathers,
-- never counted twice. Follow-up (2026-10-10): the hero rigs outside the held models (Inspect, the box reveal) come out
-- of the budget first, inside deformingRigs and heroRigs (3; phone 2), and the own model is "near" when no hero slot
-- is left; lobbyPhaseFor gives the idle phase that shows a breath amount (Inspect goes on from the reveal's breath).
-- First person (spec 2026-10-10 §3.4): mirrorRule (the hidden own model is not written while the overlay mirrors it;
-- it blinks while mirrored); finishOut makes the frame's final out (rig × idle × pop-in × overlays), and the mirror
-- gets that scale with it, so the overlay divides it back out (spec 2026-10-11 §3.4); react fires Reacted (player,
-- kind, strength) even with no held model; setMirror takes a function or nil, isMirrored tells whether one is set.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local TOLERANCE = 1e-5
local STOCK_ROTATION = CFrame.Angles(-math.pi / 2, 0, 0)

return function(t: Context)
	local HeldSquishyController = t.requireClient("Controllers/HeldSquishyController")
	local expect = t.expect

	local function near(a: Vector3, b: Vector3): boolean
		return (a - b).Magnitude <= TOLERANCE
	end

	local function hand(size: Vector3, withGrip: boolean): Part
		local part = Instance.new("Part")
		part.Name = "RightHand"
		part.Size = size
		if withGrip then
			local grip = Instance.new("Attachment")
			grip.Name = "RightGripAttachment"
			grip.CFrame = CFrame.new(0, -size.Y / 2, 0) * STOCK_ROTATION
			grip.Parent = part
		end
		return part
	end

	t.test("C0 is the hand's RightGripAttachment.CFrame", function()
		local h = hand(Vector3.new(0.3, 0.3, 0.3), true)
		local grip = h:FindFirstChild("RightGripAttachment") :: Attachment
		grip.CFrame = CFrame.new(0.01, -0.12, 0.02) * CFrame.Angles(-math.pi / 2, 0.1, 0)
		local c0 = HeldSquishyController.gripC0(h)
		expect.truthy(near(c0.Position, grip.CFrame.Position))
		expect.truthy(near(c0.LookVector, grip.CFrame.LookVector) and near(c0.UpVector, grip.CFrame.UpVector))
		h:Destroy()
	end)

	t.test("without a grip attachment C0 matches the stock attachment (bottom of the hand, -90° about X)", function()
		for _, size in { Vector3.new(0.3, 0.3, 0.3), Vector3.new(1, 2, 1) } do
			local stock = hand(size, true)
			local bare = hand(size, false)
			local wanted = HeldSquishyController.gripC0(stock)
			local c0 = HeldSquishyController.gripC0(bare)
			expect.truthy(near(c0.Position, Vector3.new(0, -size.Y / 2, 0)))
			if not (near(c0.LookVector, wanted.LookVector) and near(c0.UpVector, wanted.UpVector)) then
				error(`fallback C0 {c0} does not face like the stock grip {wanted}`)
			end
			stock:Destroy()
			bare:Destroy()
		end
	end)

	-- Feel pass (§18.5.1 A6) -----------------------------------------------------------------------------------------

	local Config = t.requireShared("Config")
	local HELD = Config.Anim.held
	local LOBBY = HELD.lobbyIdle
	local JIGGLE = HELD.motionJiggle

	-- The largest S.Y and bob over one long window of the idle (60 Hz samples).
	local function idlePeaks(weight: number, reduced: boolean): (number, number, number)
		local topY, lowXZ, topBob = 0, 2, 0
		for frame = 0, 60 * 12 do
			local scale, bob = HeldSquishyController.idleSample(frame / 60, 0.7, weight, reduced)
			topY = math.max(topY, scale.Y)
			lowXZ = math.min(lowXZ, scale.X)
			topBob = math.max(topBob, bob)
			expect.near(scale.X, scale.Z, 1e-9)
		end
		return topY, lowXZ, topBob
	end

	t.test("DESIGN values: the lobby idle, the jiggle spring and the equip pop", function()
		expect.deepEqual(
			{ LOBBY.periodSeconds, LOBBY.ampY, LOBBY.ampXZ, LOBBY.bobStuds, LOBBY.crossfadeSeconds },
			{ 2.8, 0.035, 0.0175, 0.05, 0.5 }
		)
		expect.deepEqual(
			{ JIGGLE.omega, JIGGLE.zeta, JIGGLE.maxImpulse, JIGGLE.landingImpulse, JIGGLE.maxJ },
			{ 14, 0.35, 0.05, 0.06, 0.08 }
		)
		expect.near(JIGGLE.perSpeed, 1 / 60, 1e-12)
		expect.equal(HELD.equipPopPuffs, 6)
		-- §18.1 #4: the jiggle wobbles at ω·√(1 - ζ²) / 2π <= 3 Hz.
		expect.truthy(JIGGLE.omega * math.sqrt(1 - JIGGLE.zeta ^ 2) / (2 * math.pi) <= 3)
	end)

	t.test("the lobby idle is bigger and slower than the duel idle; the phase picks it", function()
		expect.truthy(HeldSquishyController.isLobbyPhase(""))
		expect.truthy(HeldSquishyController.isLobbyPhase(nil))
		expect.falsy(HeldSquishyController.isLobbyPhase("Countdown"))
		expect.falsy(HeldSquishyController.isLobbyPhase("Returning"))
		local duelY, duelXZ, duelBob = idlePeaks(0, false)
		expect.near(duelY, 1 + HELD.idleAmpY, 1e-3)
		expect.near(duelXZ, 1 - HELD.idleAmpXZ, 1e-3)
		expect.near(duelBob, HELD.bobStuds, 1e-3)
		local lobbyY, lobbyXZ, lobbyBob = idlePeaks(1, false)
		expect.near(lobbyY, 1 + LOBBY.ampY, 1e-3)
		expect.near(lobbyXZ, 1 - LOBBY.ampXZ, 1e-3)
		expect.near(lobbyBob, LOBBY.bobStuds, 1e-3)
		-- At weight 0 the §9.5 idle is exactly as built: S.Y = 1 + 0.025 sin φ, bob at φ + π/2.
		local scale, bob = HeldSquishyController.idleSample(1.3, 0.4, 0, false)
		local phi = 2 * math.pi * 1.3 / HELD.idlePeriodSeconds + 0.4
		expect.near(scale.Y, 1 + HELD.idleAmpY * math.sin(phi), 1e-6) -- Vector3 is single precision
		expect.near(scale.X, 1 - HELD.idleAmpXZ * math.sin(phi), 1e-6) -- Vector3 is single precision
		expect.near(bob, HELD.bobStuds * math.sin(phi + math.pi / 2), 1e-9)
	end)

	t.test("ReducedMotion halves the idle", function()
		local topY, lowXZ, topBob = idlePeaks(1, true)
		expect.near(topY, 1 + LOBBY.ampY / 2, 1e-3)
		expect.near(lowXZ, 1 - LOBBY.ampXZ / 2, 1e-3)
		expect.near(topBob, LOBBY.bobStuds / 2, 1e-3)
	end)

	t.test("the phase change crossfades over 0.5 s, never jumps", function()
		local weight = 0
		local frames = 0
		while weight < 1 do
			local nextWeight = HeldSquishyController.crossfade(weight, 1, 1 / 60, LOBBY.crossfadeSeconds)
			expect.truthy(nextWeight - weight <= 1 / 60 / LOBBY.crossfadeSeconds + 1e-9)
			weight = nextWeight
			frames += 1
			expect.truthy(frames <= 31)
		end
		expect.equal(weight, 1)
		expect.near(HeldSquishyController.crossfade(1, 0, 0.1, 0.5), 0.8, 1e-9)
		expect.equal(HeldSquishyController.crossfade(0.1, 0, 1, 0.5), 0)
		-- No frame of the blended idle jumps (the output is continuous while the weight moves).
		local lastScale = HeldSquishyController.idleSample(10, 0.2, 0, false)
		local w = 0
		for frame = 1, 60 do
			w = HeldSquishyController.crossfade(w, 1, 1 / 60, LOBBY.crossfadeSeconds)
			local scale = HeldSquishyController.idleSample(10 + frame / 60, 0.2, w, false)
			expect.truthy(math.abs(scale.Y - lastScale.Y) < 0.01)
			lastScale = scale
		end
	end)

	t.test("the jiggle kick: |Δspeed| / 60, clamped to 0.05", function()
		expect.equal(HeldSquishyController.jiggleKick(10, 10), 0)
		expect.near(HeldSquishyController.jiggleKick(0, 1.2), 0.02, 1e-9)
		expect.near(HeldSquishyController.jiggleKick(1.2, 0), 0.02, 1e-9) -- stopping kicks too
		expect.equal(HeldSquishyController.jiggleKick(0, 16), JIGGLE.maxImpulse)
		expect.equal(HeldSquishyController.jiggleKick(30, 0), JIGGLE.maxImpulse)
		expect.equal(HeldSquishyController.jiggleKick(0, 0 / 0), 0)
	end)

	t.test("landing detection: a fall at <= -15 then vy >= -1 is one landing", function()
		local landed, falling = HeldSquishyController.landingStep(false, -10)
		expect.falsy(landed)
		expect.falsy(falling) -- a slow step down is no fall
		landed, falling = HeldSquishyController.landingStep(false, -16)
		expect.falsy(landed)
		expect.truthy(falling)
		landed, falling = HeldSquishyController.landingStep(falling, -8) -- slowing down, still in the air
		expect.falsy(landed)
		expect.truthy(falling)
		landed, falling = HeldSquishyController.landingStep(falling, -0.5)
		expect.truthy(landed)
		expect.falsy(falling)
		landed = HeldSquishyController.landingStep(falling, 0)
		expect.falsy(landed) -- once per landing
		-- Without a fall, standing still or jumping up never lands.
		expect.falsy((HeldSquishyController.landingStep(false, 12)))
	end)

	-- Squishy overhaul (spec 2026-10-09 §3.2) ------------------------------------------------------------------------

	local SquishRig = t.requireClient("Anim/SquishRig")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local BUDGETS = Config.Vfx.Budgets

	t.test("movement and landing kicks use the toy's feel spring: kick × gain at most, never past maxJ", function()
		for _, id in { "kitty_bread", "strawberry_frog", "mochi_fox" } do
			local motion = Blueprints[id].motion
			local _, _, gain = SquishRig.feelSpring(motion.feel)
			for _, kick in
				{ 0.02, JIGGLE.maxImpulse, JIGGLE.landingImpulse, 2 * JIGGLE.maxImpulse + JIGGLE.landingImpulse }
			do
				local rig = SquishRig.new(motion, { seed = 1, blink = false })
				local out = SquishRig.newOut()
				rig:kick(kick)
				local peak = 0
				for _ = 1, 240 do
					rig:step(1 / 60, out)
					peak = math.max(peak, math.abs(1 - out.S.Y))
				end
				if
					peak > math.min(kick * gain, JIGGLE.maxJ) * 1.05 + 1e-4
					or peak < math.min(kick * gain, JIGGLE.maxJ) * 0.8
				then
					error(`{id}: a kick of {kick} peaked at {peak} (gain {gain}, cap {JIGGLE.maxJ})`)
				end
				expect.truthy(peak <= JIGGLE.maxJ + 1e-4)
			end
		end
	end)

	t.test("the rig budget: 12 rigs and 6 near on a computer, 8 and 3 on a phone or while unknown", function()
		local total, near = HeldSquishyController.rigBudget("High")
		expect.deepEqual({ total, near }, { BUDGETS.deformingRigs, BUDGETS.nearRigs })
		expect.deepEqual({ total, near }, { 12, 6 })
		local lowTotal, lowNear = HeldSquishyController.rigBudget("Low")
		expect.deepEqual({ lowTotal, lowNear }, { BUDGETS.deformingRigsLow, BUDGETS.nearRigsLow })
		expect.deepEqual({ lowTotal, lowNear }, { 8, 3 })
		local unknownTotal, unknownNear = HeldSquishyController.rigBudget(nil) -- the first frames count as a phone
		expect.deepEqual({ unknownTotal, unknownNear }, { 8, 3 })
	end)

	t.test("detail levels: own model hero, the next near ones, the rest far up to the budget, none beyond", function()
		local function details(own: boolean, total: number, near: number): { string }
			local list = {}
			for rank = 1, total + 2 do
				table.insert(list, HeldSquishyController.detailAt(rank, own, total, near) or "none")
			end
			return list
		end
		local h, n, f, x = "hero", "near", "far", "none"
		expect.deepEqual(details(true, 12, 6), { h, n, n, n, n, n, n, f, f, f, f, f, x, x })
		expect.deepEqual(details(true, 8, 3), { h, n, n, n, f, f, f, f, x, x })
		-- No own model in the list (none held): nobody is a hero.
		expect.deepEqual(details(false, 8, 3), { n, n, n, f, f, f, f, f, x, x })
		-- Other players' held models are never heroes, so they never get section (C0) writes.
		for rank = 2, 12 do
			expect.truthy(HeldSquishyController.detailAt(rank, true, 12, 6) ~= "hero")
		end
	end)

	t.test("hero rigs outside the held models (Inspect, the box reveal) count in the rig budget", function()
		-- (the rigs left for the held models, near, may the own model be a hero) as text, e.g. "11/6/true".
		local function budget(quality: string?, heroes: number?): string
			local total, nearCount, ownHero = HeldSquishyController.rigBudget(quality, heroes)
			return `{total}/{nearCount}/{ownHero}`
		end
		expect.deepEqual({ BUDGETS.heroRigs, BUDGETS.heroRigsLow }, { 3, 2 })
		expect.equal(budget("High"), "12/6/true")
		expect.equal(budget("High", 1), "11/6/true")
		expect.equal(budget("High", 2), "10/6/true")
		expect.equal(budget("High", 3), "9/6/false") -- every hero slot taken: the own model is not a hero
		expect.equal(budget("Low", 1), "7/3/true")
		expect.equal(budget("Low", 2), "6/3/false")
		expect.equal(budget(nil, 1), "7/3/true") -- the first frames count as a phone
		-- Without a hero slot the own model is one of the near ones (it takes a near slot).
		local list = {}
		for rank = 1, 8 do
			table.insert(list, HeldSquishyController.detailAt(rank, true, 6, 3, false) or "none")
		end
		expect.deepEqual(list, { "near", "near", "near", "far", "far", "far", "none", "none" })
	end)

	t.test("with heroes outside, all the rigs together stay inside deformingRigs, heroRigs and nearRigs", function()
		for _, quality in { "High", "Low" } do
			local high = quality == "High"
			local all = if high then BUDGETS.deformingRigs else BUDGETS.deformingRigsLow
			local heroCap = if high then BUDGETS.heroRigs else BUDGETS.heroRigsLow
			local nearCap = if high then BUDGETS.nearRigs else BUDGETS.nearRigsLow
			for heroes = 0, heroCap do
				local total, nearCount, ownHero = HeldSquishyController.rigBudget(quality, heroes)
				for _, own in { true, false } do
					local counts: { [string]: number } = { hero = heroes, near = 0, far = 0 }
					for rank = 1, 20 do
						local detail = HeldSquishyController.detailAt(rank, own, total, nearCount, ownHero)
						if detail then
							counts[detail] += 1
						end
					end
					local shown = `{quality}, {heroes} outside, own {own}: {counts.hero} / {counts.near} / {counts.far}`
					if
						counts.hero + counts.near + counts.far ~= all
						or counts.hero > heroCap
						or counts.near > nearCap
					then
						error(`over budget ({all} rigs, {heroCap} heroes, {nearCap} near): {shown}`)
					end
				end
			end
		end
	end)

	t.test("lobbyPhaseFor: the idle phase that shows a breath amount on its rising or falling side", function()
		local LOBBY_IDLE = Config.Anim.held.lobbyIdle
		expect.near(LOBBY_IDLE.ampXZ, LOBBY_IDLE.ampY / 2, 1e-9) -- the same shape as IdleRig.breath
		for _, amount in { 0, 0.3, 0.75, 1 } do
			for _, rising in { true, false } do
				for _, now in { 0, 13.7, 1234.5 } do
					local phase = HeldSquishyController.lobbyPhaseFor(amount, rising, now)
					local scale = HeldSquishyController.idleSample(now, phase, 1, false)
					expect.near(scale.Y, 1 + LOBBY_IDLE.ampY * amount, 1e-5) -- Vector3 is single precision
					expect.near(scale.X, 1 - LOBBY_IDLE.ampY / 2 * amount, 1e-5)
					if amount < 1 then
						local later = HeldSquishyController.idleSample(now + 0.02, phase, 1, false)
						expect.equal(later.Y > scale.Y, rising)
					end
				end
			end
		end
	end)

	t.test("far stride: a sleeping far rig writes every 2nd frame; awake, busy or nearer, every frame", function()
		-- (skip, next parity) over 6 frames from parity `odd`, as text, e.g. "-x-x-x" (x = skipped).
		local function frames(detail: string?, awake: boolean, busy: boolean, odd: boolean): string
			local shown = ""
			for _ = 1, 6 do
				local skip
				skip, odd = HeldSquishyController.farStride(detail, awake, busy, odd)
				shown ..= if skip then "x" else "-"
			end
			return shown
		end
		expect.equal(frames("far", false, false, false), "x-x-x-")
		expect.equal(frames("far", false, false, true), "-x-x-x") -- the random parity spreads the far models
		expect.equal(frames("hero", false, false, false), "------")
		expect.equal(frames("near", false, false, false), "------")
		expect.equal(frames(nil, false, false, false), "------")
		expect.equal(frames("far", true, false, false), "------") -- awake (any input wakes the rig at once)
		expect.equal(frames("far", false, true, false), "------") -- an overlay or the equip pop runs
		-- Waking keeps the parity, so the stride goes on where it stopped.
		local skip, odd = HeldSquishyController.farStride("far", true, false, true)
		expect.deepEqual({ skip, odd }, { false, true })
	end)

	t.test("left-over rig slots: the Collection displays first, the rest to the lobby breathers", function()
		local IDLE_MAX = Config.Inspect.Collection.idleMax
		local function split(left: number, answer: unknown): { number }
			local collection, ambient = HeldSquishyController.splitSlots(left, answer)
			expect.equal(collection + ambient, math.max(0, left)) -- never counted twice, none lost
			return { collection, ambient }
		end
		-- The Collection says how many it uses.
		expect.deepEqual(split(5, 3), { 3, 2 })
		expect.deepEqual(split(5, 0), { 0, 5 })
		expect.deepEqual(split(5, 9), { 5, 0 })
		expect.deepEqual(split(5, -2), { 0, 5 })
		-- No number from it: it may use up to idleMax, the breathers get what is left.
		expect.deepEqual(split(11, nil), { IDLE_MAX, 11 - IDLE_MAX })
		expect.deepEqual(split(3, nil), { 3, 0 })
		expect.deepEqual(split(4, 0 / 0), { 4, 0 })
		expect.deepEqual(split(0, nil), { 0, 0 })
		expect.deepEqual(split(-1, 2), { 0, 0 })
	end)

	-- First person (spec 2026-10-10 §3.4): the mirror and Reacted -----------------------------------------------------

	t.test("mirror rule: the hidden own model is not written while mirrored; it blinks while mirrored", function()
		-- (write the own model, blink) for the hand's LocalTransparencyModifier and whether a mirror is set.
		local function rule(modifier: number, mirrored: boolean): string
			local write, blink = HeldSquishyController.mirrorRule(modifier, mirrored)
			return `{write}/{blink}`
		end
		expect.equal(rule(0, false), "true/true") -- third person: written, blinking
		expect.equal(rule(1, false), "true/false") -- first person without the overlay: today's (no blink)
		expect.equal(rule(0.5, true), "true/true") -- the hand still fading out: both written
		expect.equal(rule(0.99, true), "false/true") -- Roblox hid it: only the mirror is written, and it blinks
		expect.equal(rule(1, true), "false/true")
	end)

	t.test(
		"finishOut: the rig's S times the frame's scale, the twist on top; S / scale gives the rig's back",
		function()
			local rig =
				SquishRig.new(Blueprints.kitty_bread.motion, { axis = "Y", seed = 1, blink = false, rarity = "Epic" })
			local out = SquishRig.newOut()
			rig:tap()
			for _ = 1, 9 do
				rig:step(1 / 60, out)
			end
			local rigS = out.S
			-- The idle (non-uniform), the equip pop and an overlay (uniform), as updateHeld multiplies them.
			local idle = HeldSquishyController.idleSample(1.7, 0.3, 1, false)
			local scale = idle * 0.8 * Vector3.one * 1.05
			HeldSquishyController.finishOut(out, scale, out.twist + 0.02)
			expect.truthy((out.S - rigS * scale).Magnitude < 1e-6)
			-- The mirror gets this scale with the out (spec 2026-10-11 §3.4): the overlay divides it back out, the
			-- breath's X/Y difference included, which its X alone could not.
			expect.truthy((out.S / scale - rigS).Magnitude < 1e-6)
			expect.truthy(math.abs(scale.X - scale.Y) > 1e-3)
		end
	)

	t.test("react fires Reacted (player, kind, strength), even with no held model", function()
		local FakePlayer = t.requireFake("FakePlayer")
		local player = FakePlayer.new(77)
		local seen: { any } = {}
		local connection = HeldSquishyController.Reacted:connect(function(who: any, kind: string, strength: number)
			table.insert(seen, { who, kind, strength })
		end)
		HeldSquishyController.react(player :: any, "hit", 0.6)
		HeldSquishyController.react(player :: any, "land")
		connection:disconnect()
		expect.equal(#seen, 2)
		expect.equal(seen[1][1], player)
		expect.deepEqual({ seen[1][2], seen[1][3] } :: { any }, { "hit", 0.6 } :: { any })
		expect.deepEqual({ seen[2][2], seen[2][3] } :: { any }, { "land", 1 } :: { any })
	end)

	t.test("setMirror takes a function or nil; isMirrored tells whether one is set", function()
		expect.falsy(HeldSquishyController.isMirrored())
		HeldSquishyController.setMirror(function(_out: any, _scale: Vector3) end)
		expect.truthy(HeldSquishyController.isMirrored())
		HeldSquishyController.setMirror(nil)
		expect.falsy(HeldSquishyController.isMirrored())
		expect.throws(function()
			HeldSquishyController.setMirror(42 :: any)
		end, "mirror")
	end)
end
