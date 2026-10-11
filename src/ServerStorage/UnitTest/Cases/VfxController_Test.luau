--!strict
-- VfxController_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.VfxController.
-- Server only (ServerStorage.UnitTest). Edit mode: init() is not called (no remotes, no GUIs, no effects).
-- Contract (DESIGN §5.2, §5.9, §9.8, §9.9, §9.10):
--   * the Dragon Rush indicator is built only from the UltimateEvent numbers: the rectangle is exactly 2 × radius wide
--     and `length` long, both caps are 2 × radius across, at floorY + 0.05 (floorY = lane origin - laneHeightAboveFloor);
--   * the dragon head flies O -> E at `speed` and stops at E; the jaw is open by 70% of the way and chomps shut in
--     100 ms at E;
--   * knockback: 22 studs/s along the flattened direction plus 8 up, × 1.5 for Dragon Rush;
--   * elimination registry: standard, epic_pending plays standard while the epic effect is off, unknown -> standard;
--   * arena lighting (§7.4, §7.8): Config.Vfx.ZonePresets.Arena from arena entry until the duel view ends, then the
--     values saved on entry;
--   * duel juice (§18.4): the hit-stop only for the local victim or thrower (never geometry, never spectators, never
--     under ReducedMotion); the FOV punch only for the local thrower, off under ReducedMotion or with the shake setting
--     off; geometry puffs 4 in the splat colour (never red) + 4 white; the hit-stop follow-ups are dropped by clear();
--     the elimination confetti parts (10, never Danger; ReducedMotion 5 without spin) fall and fade within their life;
--     the Dragon roar for the caster and the other duelist, the telegraph duck only for the targeted duelist;
--   * sound priorities (§18.6): impact and Dragon sounds keep theirs when the local player is the thrower, the victim
--     or the thrower's duel opponent; another player's throw or Rush plays at -1 (dropped first);
--   * Part 8 (§11.2): the "K.O.!" banner never covers the duel HUD's top bar, even at its pop, and stays on the screen
--     at 667×375, 1280×720 and 1920×1080, Medium and the largest text (30% down when there is room, as built);
--   * foam fix 2: the time the "K.O.!" banner has gone (1.2 s after this client's hit-stop), which the duel result
--     card waits for; nothing waits after clear().
-- First person (spec 2026-10-10 §3.10):
--   * no SD_HitFlash ghost on the own character in first person (a Highlight can draw on the hidden body); other
--     players' ghosts and the own one in third person as before;
--   * the local first-person victim's impact puffs and ring at a quarter (Config.FirstPerson.victimImpactScale);
--     everyone else's as before;
--   * the Dragon Rush head (Anim/NearFade.rushHead, resolved once per head): the local caster's own head fades in
--     over its first 3-8 studs in first person only (duel and practice: the same lane numbers); any first-person
--     viewer's head fades within 4.5 studs of the camera; third person keeps the end fade alone.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TOLERANCE = 1e-4

return function(t: Context)
	local VfxController = t.requireClient("Controllers/VfxController")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local rush = Config.Abilities.dragon_rush
	local rushVfx = Config.Vfx.DragonRush

	local function expectVectorNear(actual: Vector3, wanted: Vector3, tolerance: number?)
		local tol = tolerance or TOLERANCE
		expect.near(actual.X, wanted.X, tol)
		expect.near(actual.Y, wanted.Y, tol)
		expect.near(actual.Z, wanted.Z, tol)
	end

	-- Dragon Rush -------------------------------------------------------------------------------------------------------

	t.test("the Rush indicator rectangle and caps are exactly 2 × radius from the payload (§9.10)", function()
		local floorY = 0
		local origin = Vector3.new(0, floorY + rush.laneHeightAboveFloor, -38)
		for _, radius in { rush.radius, 2.5, 5 } do
			local indicator = VfxController.rushIndicator(origin, Vector3.new(0, 0, 1), 70, radius)
			expect.near(indicator.rect.size.X, 2 * radius, 1e-9)
			expect.near(indicator.rect.size.Z, 70, 1e-9)
			-- Caps are cylinders lying on their side: Size.Y and Size.Z are the diameter.
			expect.near(indicator.capO.size.Y, 2 * radius, 1e-9)
			expect.near(indicator.capO.size.Z, 2 * radius, 1e-9)
			expect.near(indicator.capE.size.Y, 2 * radius, 1e-9)
			expect.near(indicator.capE.size.Z, 2 * radius, 1e-9)
		end
	end)

	t.test("the Rush indicator lies on the arena floor along the flat lane, from O to E", function()
		local origin = Vector3.new(10, 4.5 + rush.laneHeightAboveFloor, -30)
		local indicator = VfxController.rushIndicator(origin, Vector3.new(3, 0.5, 4), 50, rush.radius)
		expect.near(indicator.floorY, 4.5, 1e-6)
		local y = 4.5 + rushVfx.indicatorYOffset
		expectVectorNear(indicator.dir, Vector3.new(0.6, 0, 0.8))
		expectVectorNear(indicator.capO.cframe.Position, Vector3.new(10, y, -30))
		expectVectorNear(indicator.capE.cframe.Position, Vector3.new(10 + 30, y, -30 + 40))
		expectVectorNear(indicator.rect.cframe.Position, Vector3.new(25, y, -10))
		expectVectorNear(indicator.rect.cframe.LookVector, Vector3.new(0.6, 0, 0.8))
		expectVectorNear(indicator.endpoint, origin + Vector3.new(30, 0, 40))
		-- The cap cylinders stand on end (axis = world up).
		expectVectorNear(indicator.capO.cframe.RightVector, Vector3.yAxis)
	end)

	t.test("the dragon head flies O -> E at the payload speed and stops at E", function()
		local origin, dir = Vector3.new(0, 4.5, -40), Vector3.new(0, 0, 1)
		local at, fraction = VfxController.rushHeadAt(origin, dir, 52, 260, 0.1)
		expectVectorNear(at, Vector3.new(0, 4.5, -14))
		expect.near(fraction, 0.5, 1e-9)
		local after, done = VfxController.rushHeadAt(origin, dir, 52, 260, 5)
		expectVectorNear(after, Vector3.new(0, 4.5, 12))
		expect.equal(done, 1)
		local before, none = VfxController.rushHeadAt(origin, dir, 52, 260, -1)
		expectVectorNear(before, origin)
		expect.equal(none, 0)
	end)

	t.test("the jaw is open by 70% of the way and chomps shut in 100 ms", function()
		expect.near(VfxController.jawAngle(0), 0, 1e-9)
		local open = VfxController.jawAngle(rushVfx.jawOpenAt)
		expect.truthy(open < -1)
		expect.near(VfxController.jawAngle(1), open, 1e-9)
		expect.near(VfxController.jawAngle(1, 0), open, 1e-9)
		expect.near(VfxController.jawAngle(1, rushVfx.jawChompMs / 2000), open / 2, 1e-9)
		expect.near(VfxController.jawAngle(1, rushVfx.jawChompMs / 1000), 0, 1e-9)
	end)

	-- Hits --------------------------------------------------------------------------------------------------------------

	t.test("knockback is 22 studs/s along the flattened direction plus 8 up, × 1.5 for Dragon Rush", function()
		local knockback = Config.Duel.Rules.Knockback
		local v = VfxController.knockbackVelocity(Vector3.new(3, 5, 4), 1)
		expectVectorNear(v, Vector3.new(0.6 * knockback.Horizontal, knockback.Vertical, 0.8 * knockback.Horizontal))
		local r = VfxController.knockbackVelocity(Vector3.new(0, 0, -2), rush.knockbackMultiplier)
		expectVectorNear(
			r,
			Vector3.new(
				0,
				knockback.Vertical * rush.knockbackMultiplier,
				-knockback.Horizontal * rush.knockbackMultiplier
			)
		)
		-- A straight-down direction pushes only up.
		expectVectorNear(
			VfxController.knockbackVelocity(Vector3.new(0, -1, 0), 1),
			Vector3.new(0, knockback.Vertical, 0)
		)
	end)

	t.test("the elimination registry plays the standard effect until the epic one is approved", function()
		expect.equal(VfxController.eliminationEffect("standard"), "standard")
		expect.equal(VfxController.eliminationEffect(nil), "standard")
		expect.equal(VfxController.eliminationEffect("confetti_cannon"), "standard")
		if not Config.Anim.elimination.epicEnabled then
			expect.equal(VfxController.eliminationEffect("epic_pending"), "standard")
		end
	end)

	t.test(
		"arena lighting: the preset from arena entry (Positioning) until the view ends, then the saved values",
		function()
			expect.falsy(VfxController.arenaLightingWanted(nil))
			expect.falsy(VfxController.arenaLightingWanted({ phase = "Preparing", positioned = false }))
			for _, phase in { "Positioning", "Countdown", "Active", "Result", "Returning", "Cancelled" } do
				expect.truthy(VfxController.arenaLightingWanted({ phase = phase, positioned = true }))
			end
			local arena = Config.Vfx.ZonePresets.Arena
			local goals = VfxController.lightingGoals(true, nil)
			expect.equal(goals.contrast, arena.contrast)
			expect.equal(goals.saturation, arena.saturation)
			expect.equal(goals.density, arena.atmosphereDensity)
			local saved = { contrast = 0.06, saturation = 0.05, density = 0.22 }
			expect.deepEqual(VfxController.lightingGoals(false, saved), saved)
			expect.equal(VfxController.lightingGoals(false, nil), nil)
		end
	)

	-- Duel juice (§18.4) ----------------------------------------------------------------------------------------------

	local hitStop = Config.Vfx.HitStop
	local punch = Config.Vfx.Punch
	local ME, THEM, OTHER = 1, 2, 3

	t.test("the hit-stop goes only to the local victim or thrower, never on walls or for spectators", function()
		-- Victim and thrower of a player hit.
		local asVictim = VfxController.hitJuice("player", false, ME, ME, THEM, false, true)
		expect.equal(asVictim.stopSeconds, hitStop.playerHit)
		expect.truthy(asVictim.localIsVictim)
		local asThrower = VfxController.hitJuice("player", false, ME, THEM, ME, false, true)
		expect.equal(asThrower.stopSeconds, hitStop.playerHit)
		expect.truthy(asThrower.localIsThrower)
		-- Elimination holds longer, for both.
		expect.equal(VfxController.hitJuice("player", true, ME, ME, THEM, false, true).stopSeconds, hitStop.elimination)
		expect.equal(VfxController.hitJuice("player", true, ME, THEM, ME, false, true).stopSeconds, hitStop.elimination)
		-- A spectator gets nothing.
		local spectator = VfxController.hitJuice("player", true, ME, THEM, OTHER, false, true)
		expect.equal(spectator.stopSeconds, nil)
		expect.equal(spectator.punch, nil)
		-- Practice target: the thrower only.
		expect.equal(
			VfxController.hitJuice("target", false, ME, nil, ME, false, true).stopSeconds,
			hitStop.practiceTarget
		)
		expect.equal(VfxController.hitJuice("target", false, ME, nil, OTHER, false, true).stopSeconds, nil)
		-- Walls, floors and misses never hold, not even for the thrower.
		for _, kind in { "geometry", "expired", "fizzle" } do
			expect.equal(VfxController.hitJuice(kind, false, ME, nil, ME, false, true).stopSeconds, nil)
		end
		-- ReducedMotion: no hold at all; the camera shake setting does not matter.
		expect.equal(VfxController.hitJuice("player", false, ME, ME, THEM, true, true).stopSeconds, nil)
		expect.equal(VfxController.hitJuice("player", false, ME, ME, THEM, false, false).stopSeconds, hitStop.playerHit)
		-- No local player (Edit mode): nothing.
		expect.equal(VfxController.hitJuice("player", false, nil, ME, THEM, false, true).stopSeconds, nil)
	end)

	t.test("the FOV punch goes only to the local thrower, with the shake's gates", function()
		expect.deepEqual(VfxController.hitJuice("player", false, ME, THEM, ME, false, true).punch, punch.hitDealt)
		expect.deepEqual(VfxController.hitJuice("player", true, ME, THEM, ME, false, true).punch, punch.elimDealt)
		expect.deepEqual(VfxController.hitJuice("target", false, ME, nil, ME, false, true).punch, punch.practiceHit)
		-- Never for the victim, a wall hit, ReducedMotion or the shake setting off.
		expect.equal(VfxController.hitJuice("player", false, ME, ME, THEM, false, true).punch, nil)
		expect.equal(VfxController.hitJuice("geometry", false, ME, nil, ME, false, true).punch, nil)
		expect.equal(VfxController.hitJuice("player", false, ME, THEM, ME, true, true).punch, nil)
		expect.equal(VfxController.hitJuice("player", false, ME, THEM, ME, false, false).punch, nil)
		-- Every punch stays within ±maxFovDeg (<= 4°).
		for _, spec in { punch.hitDealt, punch.elimDealt, punch.practiceHit } do
			expect.truthy(math.abs(spec.fovDeg) <= punch.maxFovDeg)
		end
		expect.truthy(punch.maxFovDeg <= 4)
	end)

	t.test("geometry puffs: 4 in the splat colour (never red) + 4 white", function()
		local white = Color3.new(1, 1, 1)
		local Catalog = t.requireShared("Catalog")
		local SplatMath = t.requireClient("Anim/SplatMath")
		local geometry = Config.Vfx.Hit.geometryPuffs
		expect.equal(geometry.accent, 4)
		expect.equal(geometry.white, 4)
		for _, def in Catalog.list() do
			local accent = Color3.fromHex(def.visuals.accent)
			local puffs = VfxController.geometryPuffs(accent)
			expect.equal(#puffs, 2)
			expect.equal(puffs[1].count, geometry.accent)
			expect.equal(puffs[2].count, geometry.white)
			local want = SplatMath.color(accent)
			expect.near(puffs[1].color.R, want.R, 1e-6)
			expect.near(puffs[1].color.G, want.G, 1e-6)
			expect.near(puffs[1].color.B, want.B, 1e-6)
			expect.falsy(SplatMath.isRed(puffs[1].color))
			expect.near(puffs[2].color.R, white.R, 1e-6)
			expect.near(puffs[2].color.B, white.B, 1e-6)
		end
		-- Still within the impact particle budget.
		expect.truthy(geometry.accent + geometry.white <= Config.Vfx.Effects.impactParticles)
	end)

	t.test("clear() drops what waits for the hit-stop", function()
		local HitStop = t.requireClient("Anim/HitStop")
		local now = os.clock()
		expect.truthy(HitStop.trigger(nil, hitStop.playerHit, now) ~= nil)
		local ran = false
		HitStop.after(function()
			ran = true
		end, now)
		expect.equal(HitStop.pending(), 1)
		VfxController.clear()
		expect.equal(HitStop.pending(), 0)
		HitStop.runDue(now + 1)
		expect.falsy(ran)
		expect.falsy(HitStop.holding(now + 0.01))
	end)

	t.test(
		"elimination confetti parts: 10 in four pastels (never Danger), 5 without spin under ReducedMotion",
		function()
			local confetti = Config.Vfx.Confetti
			local Palette = t.requireShared("Art/Palette")
			local pastel = { Palette.Strawberry, Palette.Mint, Palette.Lemon, Palette.Sky }
			local pieces = VfxController.confettiLaunch(Random.new(3), false)
			expect.equal(#pieces, confetti.parts)
			expect.equal(confetti.parts, Config.Vfx.Effects.eliminationConfettiParts)
			for _, piece in pieces do
				expect.truthy(piece.color ~= Palette.Danger)
				local known = false
				for _, color in pastel do
					if color == piece.color then
						known = true
					end
				end
				expect.truthy(known)
				expect.truthy(piece.velocity.Y >= confetti.upMin - 1e-4 and piece.velocity.Y <= confetti.upMax + 1e-4)
				local out = Vector3.new(piece.velocity.X, 0, piece.velocity.Z).Magnitude
				expect.truthy(out >= confetti.outMin - 1e-3 and out <= confetti.outMax + 1e-3)
				expect.truthy(piece.spinDeg >= confetti.spinMinDeg and piece.spinDeg <= confetti.spinMaxDeg)
				expect.near(piece.axis.Magnitude, 1, 1e-4)
			end
			local calm = VfxController.confettiLaunch(Random.new(3), true)
			expect.equal(#calm, 5)
			for _, piece in calm do
				expect.equal(piece.spinDeg, 0)
			end
		end
	)

	t.test("confetti falls under gravity with drag and is gone after its lifetime", function()
		local confetti = Config.Vfx.Confetti
		local position, velocity = Vector3.zero, Vector3.new(4, 12, 0)
		local peak = 0
		for _ = 1, 60 do
			position, velocity = VfxController.confettiStep(position, velocity, 1 / 60)
			peak = math.max(peak, position.Y)
		end
		expect.truthy(peak > 0)
		expect.truthy(velocity.Y < 0) -- after 1 s gravity has turned it around
		expect.truthy(math.abs(velocity.X) < 4 * math.exp(-confetti.dragPerSecond * 0.9)) -- drag slowed it
		local start, startGone = VfxController.confettiTransparency(0)
		expect.equal(start, 0)
		expect.falsy(startGone)
		local midFade = VfxController.confettiTransparency(confetti.lifetime - confetti.fadeSeconds / 2)
		expect.near(midFade, 0.5, 1e-6)
		local final, gone = VfxController.confettiTransparency(confetti.lifetime)
		expect.near(final, 1, 1e-9)
		expect.truthy(gone)
	end)

	t.test("Dragon audio: the roar for the caster and the other duelist, the duck only for the targeted one", function()
		local roar, duck = VfxController.rushListener(ME, ME, THEM)
		expect.truthy(roar)
		expect.falsy(duck)
		roar, duck = VfxController.rushListener(THEM, ME, THEM)
		expect.truthy(roar)
		expect.truthy(duck)
		roar, duck = VfxController.rushListener(OTHER, ME, THEM) -- someone else's duel, or practice
		expect.falsy(roar)
		expect.falsy(duck)
		roar, duck = VfxController.rushListener(THEM, ME, nil) -- not in a duel
		expect.falsy(roar)
		expect.falsy(duck)
	end)

	t.test("impact and Rush sounds of another player's throw play at -1, the local player's keep theirs", function()
		-- The local player threw, was hit, or faces the thrower in a duel: the sound keeps its priority.
		expect.equal(VfxController.soundPriority(2, ME, nil, ME, nil), 2)
		expect.equal(VfxController.soundPriority(2, OTHER, ME, ME, nil), 2)
		expect.equal(VfxController.soundPriority(1, THEM, nil, ME, THEM), 1)
		expect.equal(VfxController.soundPriority(3, THEM, nil, ME, THEM), 3)
		-- Another player's practice throw at a target or the backstop, or their practice Rush, nearby: -1.
		expect.equal(VfxController.soundPriority(2, OTHER, nil, ME, nil), -1)
		expect.equal(VfxController.soundPriority(1, OTHER, nil, ME, THEM), -1)
		expect.equal(VfxController.soundPriority(3, OTHER, nil, ME, nil), -1)
		-- Reading: an unknown thrower (or no local player, Edit mode) keeps the priority.
		expect.equal(VfxController.soundPriority(2, nil, nil, ME, nil), 2)
		expect.equal(VfxController.soundPriority(2, OTHER, nil, nil, nil), 2)
	end)

	t.test("K.O. banner (Part 8): under the duel top bar on short screens, 30% down otherwise, on screen", function()
		local Layout = t.requireClient("UI/Layout")
		local UI = Config.UI
		-- SD_Vfx is full-bleed without a UIScale: px are the screen's. The banner is 12% of the screen tall and pops
		-- from 1.3; the duel top bar (DuelController) is about 110 base px tall at Medium text, 12 px from the top
		-- (Part 8 numbers, kept as the model: the foam side cards made it about 102 base px, 135 with the opponent's
		-- Dragon Rush chip; koBannerCenterY reads the real bar at runtime, so a taller bar only moves the banner lower).
		local popHalf = 0.12 * 1.3 / 2
		for _, actual in { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) } do
			local scale = Layout.uiScale(actual.Y)
			for _, textScale in { 1, UI.PreferredTextScale.Largest } do
				local barBottom = (12 + 110 * textScale) * scale
				local centre = VfxController.koBannerCenterY(actual.Y, barBottom)
				local half = actual.Y * popHalf
				expect.truthy(centre >= actual.Y * 0.3 - 1e-6) -- never higher than as built
				expect.truthy(centre - half >= barBottom + 8 - 1e-6) -- the bar's lives stay in view
				expect.truthy(centre + half <= actual.Y - 12 + 1e-6) -- on the screen
				if actual.Y >= 1080 or (actual.Y >= 720 and textScale == 1) then
					expect.near(centre, actual.Y * 0.3, 1e-6) -- room to spare: as built
				end
			end
		end
		-- The phone: lower than 30% (the banner covered the lives row before).
		expect.truthy(VfxController.koBannerCenterY(375, (12 + 110) * Layout.uiScale(375)) > 375 * 0.3 + 1)
		-- No bar (the HUD hidden) or bad numbers: 30% down; a bar reaching the bottom: kept on screen.
		expect.near(VfxController.koBannerCenterY(375, nil), 112.5, 1e-6)
		expect.near(VfxController.koBannerCenterY(375, 0 / 0), 112.5, 1e-6)
		expect.near(VfxController.koBannerCenterY(375, 370), 375 - 12 - 375 * popHalf, 1e-6)
		expect.equal(VfxController.koBannerCenterY(0 / 0, 100), 0)
	end)

	t.test("K.O. banner (foam fix 2): when it has gone, for the duel result card to wait on", function()
		-- 1.2 s on screen, after this client's hit-stop when it has one.
		expect.near(VfxController.koBannerEndsAt(10, 0.1), 11.3, 1e-9)
		expect.near(VfxController.koBannerEndsAt(10, nil), 11.2, 1e-9)
		expect.near(VfxController.koBannerEndsAt(10, -1), 11.2, 1e-9)
		expect.near(VfxController.koBannerEndsAt(10, 0 / 0), 11.2, 1e-9)
		-- Nothing is waiting before any K.O. or after clear().
		VfxController.clear()
		expect.equal(VfxController.koBannerUntil(), 0)
	end)

	-- First person (spec 2026-10-10 §3.10) -----------------------------------------------------------------------------

	local fp = Config.FirstPerson

	t.test("no white ghost on the own character in first person; every other ghost as before", function()
		expect.falsy(VfxController.ghostWanted(true, true)) -- own body, hidden by first person
		expect.truthy(VfxController.ghostWanted(true, false)) -- own body in third person
		expect.truthy(VfxController.ghostWanted(false, true)) -- the opponent, seen from first person
		expect.truthy(VfxController.ghostWanted(false, false))
	end)

	t.test("the local first-person victim's impact puffs and ring are a quarter; everyone else's as before", function()
		local hit = Config.Vfx.Hit
		expect.equal(fp.victimImpactScale, 0.25)
		expect.equal(VfxController.impactScale(true, true), fp.victimImpactScale)
		expect.equal(VfxController.impactScale(true, false), 1) -- the victim in third person
		expect.equal(VfxController.impactScale(false, true), 1) -- the thrower or a spectator in first person
		expect.equal(VfxController.impactScale(false, false), 1)
		-- Full size: exactly the burst as before (half accent, half white, the 4-stud ring).
		local accent, white, ring = VfxController.majorBurst(1)
		expect.equal(accent, math.floor(hit.puffs / 2))
		expect.equal(accent + white, hit.puffs)
		expect.equal(ring, hit.ringToStuds)
		-- A quarter: about a quarter of the puffs (never none) and a quarter-size ring.
		accent, white, ring = VfxController.majorBurst(fp.victimImpactScale)
		expect.equal(accent + white, math.floor(hit.puffs * fp.victimImpactScale + 0.5))
		expect.truthy(accent >= 1 and white >= 1)
		expect.near(ring, hit.ringToStuds * fp.victimImpactScale, 1e-9)
	end)

	t.test("the Rush head: the caster's fades in over 3-8 studs and a near one fades, in first person only", function()
		local NearFade = t.requireClient("Anim/NearFade")
		-- A lane as the server sends it (duel and practice alike): from O, 260 studs/s.
		local origin, dir = Vector3.new(-20, 4.5, -40), Vector3.new(0, 0, 1)
		local length, speed = 52, rush.speed
		local camera = origin - dir * 2 -- the caster's eyes, about 2 studs behind O at eye height
		local function headFade(elapsed: number, isCaster: boolean, firstPerson: boolean, eye: Vector3): number
			local at = VfxController.rushHeadAt(origin, dir, length, speed, elapsed)
			return NearFade.rushHead(0, (at - origin).Magnitude, (at - eye).Magnitude, isCaster, firstPerson)
		end
		-- The caster in first person: clear at the release, still clear at 3 studs, solid from 8 studs on.
		expect.equal(headFade(0, true, true, camera), 1)
		expect.equal(headFade(3 / speed, true, true, camera), 1)
		expect.equal(headFade(8 / speed, true, true, camera), 0)
		expect.equal(headFade(0.1, true, true, camera), 0)
		-- The caster in third person: solid all the way, as before.
		for _, elapsed in { 0, 3 / speed, 0.1 } do
			expect.equal(headFade(elapsed, true, false, camera), 0)
		end
		-- The target in first person, standing at the far end of the lane: solid until it comes near, then it fades.
		local target = origin + dir * (length + 2)
		expect.equal(headFade(0, false, true, target), 0)
		expect.equal(headFade(length / speed, false, true, target), 1) -- 2 studs from the eyes
		expect.near(headFade((length - 1.5) / speed, false, true, target), 0.5, 1e-4) -- 3.5 studs
		-- The target in third person: never faded by distance.
		expect.equal(headFade(length / speed, false, false, target), 0)
		-- The end fade is never lowered by either.
		expect.equal(NearFade.rushHead(0.6, length, 20, true, true), 0.6)
	end)
end
