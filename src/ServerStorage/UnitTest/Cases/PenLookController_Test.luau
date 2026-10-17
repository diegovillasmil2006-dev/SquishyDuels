--!strict
-- PenLookController_Test: unit tests for StarterPlayerScripts.Client.Controllers.PenLookController (pens3 phase 10: the
-- motion of the base gates and fences, lobby design v6). Server only (ServerStorage.UnitTest). Edit mode: no
-- LocalPlayer and no running BaseService, so start() finds no base; its pure parts are tested here.
-- Contract (work/pens3/PLAN.md "PHASE 10"; kit.json K, "Squishy Lobby 3D.html" P3D):
--   * Config.UI.Pen holds K's keys: A10 SignAssignPop (K:5607-5639) 0.2 -> 1.15 (Back Out, 0.25 s) -> 1 (Sine Out,
--     0.4 s); A12 GateBowWiggle (K:5673-5710) 0 -> 12° (Quad Out, 0.15 s) -> -8° (Sine InOut, 0.35 s) -> 0 (Sine Out,
--     0.6 s); A14 FenceGrow (K:5749-5781) 0.01 -> 1.15 (Back Out, 0.25 s) -> 1 (Sine Out, 0.35 s), 0.04 s apart; E15
--     (K:4627-4645) 6 of 0.5 studs for 0.4 s in K's 5 colours; E17 (K:4662-4676) 1 white of 0.8 for 0.4 s;
--   * changes(old, new): nothing at first sight; a new owner (the base was given) -> A10 only; the same owner with more
--     spots -> A14 over PenMath.newSegments; the same owner reaching tier III -> A12; an owner gone -> nothing;
--   * grown(rel, size, scale): a fence part squashed toward the floor: its size along the plot's up and its height both
--     times the scale (a post stands on its X);
--   * inside(spots, point): a plot-local point inside the pen's fence (the owner walked in), never for no pen;
--   * glint(last, state, price, glinted): E17 when the own sign turns from too expensive to can buy at one price, once
--     per price; never at MAX, from can buy or across a price change;
--   * init / start / destroy run cleanly in Edit mode and leave nothing behind (no Scheduler effect). Engine only: the
--     plain offline runner has no CollectionService (the signals runner passes it).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PenLookController = t.requireClient("Controllers/PenLookController")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Config = t.requireShared("Config")
	local PenMath = t.requireShared("PenMath")
	local P = Config.UI.Pen

	-- A Timeline key list as "t_ms value style direction" rows (K's keys: seconds × 1000, the ease's two words).
	local function rows(keys: { any }): { string }
		local list = {}
		for _, key in keys do
			local style = if key.style then key.style.Name else "-"
			local dir = if key.dir then key.dir.Name else "-"
			table.insert(list, string.format("%g %g %s %s", key.t_ms, key.value, style, dir))
		end
		return list
	end

	t.test("Config.UI.Pen holds K's A10, A12, A14, E15 and E17", function()
		expect.deepEqual(rows(P.signAssign), { "0 0.2 - -", "250 1.15 Back Out", "400 1 Sine Out" })
		expect.deepEqual(rows(P.gateBow), { "0 0 - -", "150 12 Quad Out", "350 -8 Sine InOut", "600 0 Sine Out" })
		expect.deepEqual(rows(P.fenceGrow), { "0 0.01 - -", "250 1.15 Back Out", "350 1 Sine Out" })
		expect.equal(P.growStaggerMs, 40)
		expect.equal(P.poof.count, 6)
		expect.equal(P.poof.size, 0.5)
		expect.equal(P.poof.seconds, 0.4)
		local Palette = t.requireShared("Art/Palette")
		local want = { "#FFD84A", "#FF6FA3", "#5FE0E8", "#8DF27A", "#B98CFF" }
		expect.equal(#P.poof.colors, #want)
		for index, name in P.poof.colors do
			expect.equal(Palette[name], Color3.fromHex(want[index]))
		end
		expect.equal(P.glint.count, 1)
		expect.equal(P.glint.size, 0.8)
		expect.equal(P.glint.seconds, 0.4)
	end)

	t.test(
		"changes: first sight nothing; a new owner A10; the same owner growing A14; reaching tier III A12",
		function()
			local none = { assign = false, grow = {}, bow = false }
			expect.deepEqual(PenLookController.changes(nil, { owner = 7, spots = 3, tier = 1 }), none)
			-- A player is given the base: the gate shows a new owner (an open plot had none; another owner left).
			local given = PenLookController.changes(
				{ spots = nil, tier = nil, owner = nil },
				{ owner = 7, spots = 9, tier = 2 }
			)
			expect.deepEqual(given, { assign = true, grow = {}, bow = false })
			-- Another owner on a bigger pen: only the sign pops (no growth or bow across owners).
			local other = PenLookController.changes(
				{ owner = 5, spots = 3, tier = 1 },
				{ owner = 7, spots = 12, tier = 3 }
			)
			expect.deepEqual(other, { assign = true, grow = {}, bow = false })
			-- The same owner bought a spot: the new segments pop in, in build order.
			local grew = PenLookController.changes(
				{ owner = 7, spots = 3, tier = 1 },
				{ owner = 7, spots = 4, tier = 1 }
			)
			expect.equal(grew.assign, false)
			expect.equal(#grew.grow, #PenMath.newSegments(3, 4))
			for index, frame in grew.grow do
				expect.near((frame.Position - PenMath.newSegments(3, 4)[index].Position).Magnitude, 0, 1e-6)
			end
			-- Reaching tier III: the bow wiggles (9 -> 10 adds no segment).
			expect.deepEqual(
				PenLookController.changes({ owner = 7, spots = 9, tier = 2 }, { owner = 7, spots = 10, tier = 3 }),
				{ assign = false, grow = {}, bow = true }
			)
			expect.equal(
				PenLookController.changes({ owner = 7, spots = 10, tier = 3 }, { owner = 7, spots = 11, tier = 3 }).bow,
				false
			)
			-- The owner left (no pen): nothing; the same pen redrawn (a squishy granted): nothing.
			expect.deepEqual(
				PenLookController.changes({ owner = 7, spots = 5, tier = 1 }, { owner = nil, spots = nil, tier = nil }),
				none
			)
			expect.deepEqual(
				PenLookController.changes({ owner = 7, spots = 5, tier = 1 }, { owner = 7, spots = 5, tier = 1 }),
				none
			)
		end
	)

	t.test("grown: a fence part squashed toward the floor, its height and its size along the plot's up", function()
		-- A picket 0.5 × 2.6 × 0.25 standing from y 0.3 (centre 1.6).
		local rel, size = PenLookController.grown(CFrame.new(1, 1.6, 19), Vector3.new(0.5, 2.6, 0.25), 0.5)
		expect.near(rel.Position.Y, 0.8, 1e-6)
		expect.near(rel.Position.X, 1, 1e-6)
		expect.near(rel.Position.Z, 19, 1e-6)
		expect.near(size.Y, 1.3, 1e-6)
		expect.near(size.X, 0.5, 1e-6)
		-- A post stands on its X (turned 90° about Z): its X shrinks.
		local upright = CFrame.new(4, 1.6, 19) * CFrame.Angles(0, 0, math.pi / 2)
		local postRel, postSize = PenLookController.grown(upright, Vector3.new(3.2, 0.7, 0.7), 1.15)
		expect.near(postSize.X, 3.2 * 1.15, 1e-6)
		expect.near(postSize.Y, 0.7, 1e-6)
		expect.near(postRel.Position.Y, 1.6 * 1.15, 1e-6)
		expect.near((postRel.UpVector - upright.UpVector).Magnitude, 0, 1e-6) -- still turned
	end)

	t.test("inside: a point inside the pen's fence rectangle; never with no pen", function()
		-- 16 × 12 at 3 spots: x -8..8, z 7..19.
		expect.truthy(PenLookController.inside(3, Vector3.new(0, 2, 15)))
		expect.falsy(PenLookController.inside(3, Vector3.new(0, 2, 20))) -- in front of the gate
		expect.falsy(PenLookController.inside(3, Vector3.new(9, 2, 10))) -- beside it
		expect.falsy(PenLookController.inside(3, Vector3.new(0, 2, 6))) -- behind it
		expect.truthy(PenLookController.inside(12, Vector3.new(11, 2, -12))) -- 24 × 32: x -12..12, z -13..19
		expect.falsy(PenLookController.inside(nil, Vector3.new(0, 2, 15)))
	end)

	t.test("glint: too expensive -> can buy at one price, once per price; never at MAX or from can buy", function()
		local glinted: { [number]: boolean } = {}
		local last = { state = "tooExpensive", price = 1500 }
		expect.truthy(PenLookController.glint(last, "canBuy", 1500, glinted))
		glinted[1500] = true
		expect.falsy(PenLookController.glint(last, "canBuy", 1500, glinted)) -- once per price
		expect.falsy(PenLookController.glint({ state = "canBuy", price = 3100 }, "canBuy", 3100, glinted))
		expect.falsy(PenLookController.glint({ state = "tooExpensive", price = 3100 }, "max", nil, glinted))
		expect.falsy(PenLookController.glint({ state = "tooExpensive", price = 1500 }, "canBuy", 3100, glinted))
		expect.truthy(PenLookController.glint({ state = "tooExpensive", price = 3100 }, "canBuy", 3100, glinted))
		expect.falsy(PenLookController.glint(nil, "canBuy", 4650, glinted)) -- nothing seen before
	end)

	t.test("init / start / destroy run cleanly in Edit mode and leave nothing behind", function()
		local effects = Scheduler.count()
		PenLookController.init()
		PenLookController.start()
		expect.equal(PenLookController.debugState().started, true)
		PenLookController.destroy()
		expect.equal(Scheduler.count(), effects)
		expect.equal(PenLookController.debugState().started, false)
		expect.equal(PenLookController.debugState().bases, 0) -- the place's 10 bases are watched in Edit too: all let go
		PenLookController.destroy() -- twice is fine
	end)
end
