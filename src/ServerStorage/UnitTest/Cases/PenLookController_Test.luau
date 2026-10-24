--!strict
-- PenLookController_Test: unit tests for StarterPlayerScripts.Client.Controllers.PenLookController (pens3 phase 10: the
-- motion of the base gates, lobby design v6; wb: no pen fence any more, so no fence growth). Server only
-- (ServerStorage.UnitTest). Edit mode: no LocalPlayer and no running BaseService, so start() finds no base; its pure
-- parts are tested here.
-- Contract (work/pens3/PLAN.md "PHASE 10"; kit.json K, "Squishy Lobby 3D.html" P3D):
--   * Config.UI.Pen holds K's keys: A10 SignAssignPop (K:5607-5639) 0.2 -> 1.15 (Back Out, 0.25 s) -> 1 (Sine Out,
--     0.4 s); A12 GateBowWiggle (K:5673-5710) 0 -> 12° (Quad Out, 0.15 s) -> -8° (Sine InOut, 0.35 s) -> 0 (Sine Out,
--     0.6 s); E17 (K:4662-4676) 1 white of 0.8 for 0.4 s; wb: no A14 FenceGrow or E15 PenUpgradePoof keys (K's
--     triggers are new fence segments: the pen has none now; a bought spot plays A13 on its sign, PenController);
--   * changes(old, new): nothing at first sight; a new owner (the base was given) -> A10 only; the same owner reaching
--     tier III -> A12; an owner gone, or the same owner at the same tier (a bought spot), -> nothing;
--   * inside(point): a plot-local point on the base's fenced floor (wb: the pen is the whole base; the owner walked in
--     through the Donut Arch), never in the arch, past the fence or in the back wall;
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

	t.test("Config.UI.Pen holds K's A10, A12 and E17; no fence growth (wb)", function()
		expect.deepEqual(rows(P.signAssign), { "0 0.2 - -", "250 1.15 Back Out", "400 1 Sine Out" })
		expect.deepEqual(rows(P.gateBow), { "0 0 - -", "150 12 Quad Out", "350 -8 Sine InOut", "600 0 Sine Out" })
		expect.equal(P.fenceGrow, nil)
		expect.equal(P.growStaggerMs, nil)
		expect.equal(P.poof, nil)
		expect.equal(P.glint.count, 1)
		expect.equal(P.glint.size, 0.8)
		expect.equal(P.glint.seconds, 0.4)
	end)

	t.test("changes: first sight nothing; a new owner A10; reaching tier III A12; a bought spot nothing", function()
		local none = { assign = false, bow = false }
		expect.deepEqual(PenLookController.changes(nil, { owner = 7, tier = 1 }), none)
		-- A player is given the base: the gate shows a new owner (an open plot had none; another owner left).
		expect.deepEqual(
			PenLookController.changes({ tier = nil, owner = nil }, { owner = 7, tier = 2 }),
			{ assign = true, bow = false }
		)
		-- Another owner on a Royal pen: only the sign pops (no bow across owners).
		expect.deepEqual(
			PenLookController.changes({ owner = 5, tier = 1 }, { owner = 7, tier = 3 }),
			{ assign = true, bow = false }
		)
		-- Reaching tier III: the bow wiggles; past it, nothing.
		expect.deepEqual(
			PenLookController.changes({ owner = 7, tier = 2 }, { owner = 7, tier = 3 }),
			{ assign = false, bow = true }
		)
		expect.equal(PenLookController.changes({ owner = 7, tier = 3 }, { owner = 7, tier = 3 }).bow, false)
		-- The owner left (no pen): nothing; the same tier redrawn (a spot bought, a squishy granted): nothing.
		expect.deepEqual(PenLookController.changes({ owner = 7, tier = 1 }, { owner = nil, tier = nil }), none)
		expect.deepEqual(PenLookController.changes({ owner = 7, tier = 1 }, { owner = 7, tier = 1 }), none)
	end)

	t.test("inside: a point on the pen's floor (Neon Sugar part 4: Diego's WalkArea)", function()
		expect.truthy(PenLookController.inside(Vector3.new(0, 2, 15)))
		expect.truthy(PenLookController.inside(Vector3.new(0, 2, 24))) -- just inside the arch
		expect.truthy(PenLookController.inside(Vector3.new(18.5, 2, -17))) -- a back corner
		expect.falsy(PenLookController.inside(Vector3.new(0, 2, 25.6))) -- in the arch
		expect.falsy(PenLookController.inside(Vector3.new(0, 2, 33))) -- on the path, at the spawn
		expect.falsy(PenLookController.inside(Vector3.new(19.5, 2, 0))) -- past the side fence
		expect.falsy(PenLookController.inside(Vector3.new(0, 2, -18))) -- by the shelf
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
