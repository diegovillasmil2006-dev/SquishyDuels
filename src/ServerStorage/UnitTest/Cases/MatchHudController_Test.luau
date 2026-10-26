--!strict
-- MatchHudController_Test: StarterPlayerScripts.Client.Controllers.MatchHudController (Match HUD M4, 2026-10-16: the
-- base layer of the in-match screens; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.9). Server only
-- (ServerStorage.UnitTest), Edit mode in Studio: no LocalPlayer (the ScreenGui stays unparented), Config.Debug
-- .debugHooks is on, so the Studio preview runs. Fake pieces (in PIECES instead of the real ones, which are put back)
-- record their calls.
-- Contract:
--   * init / start / destroy run cleanly with no match;
--   * a real match view (fired on StateController.MatchChanged) builds only the pieces whose Config.UI.Match.enabled
--     switch is on (Match HUD M6 / M7: feed, card, respawn; the medal and the killer camera stay off), so a piece with
--     no switch makes no piece and no per-frame effect; the view's end stops the session;
--   * Match HUD M6 / M7: PIECES are the respawn bar, the card and the feed, in that draw order;
--   * debugShow(state) builds every piece of a preview whatever its switch, updates each once at once, plays the
--     state's moments once in seq order, and debugShow(nil) destroys the pieces (last built first) and lists the
--     states; an unknown state is refused with the list;
--   * a piece that fails to build or to update never stops the others;
--   * a real match view ends a preview; no preview starts during a real match.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Hud = t.requireClient("Controllers/MatchHudController")
	local StateController = t.requireClient("Controllers/StateController")
	local Fixtures = t.requireClient("Studio/MatchHudFixtures")
	local Config = t.requireShared("Config")

	-- A piece that writes "<name>:<call>" into `calls`; opts.failNew / failUpdate make that call error.
	local function fake(name: string, calls: { string }, opts: { failNew: boolean?, failUpdate: boolean? }?): any
		return {
			name = name,
			new = function(ctx: any): any
				table.insert(calls, name .. ":new")
				assert(ctx.root ~= nil and ctx.preview ~= nil and type(ctx.fit) == "function", "bad ctx")
				if opts and opts.failNew then
					error("fake new failed")
				end
				return {
					update = function(_self: any, view: any, _now: number)
						assert(view ~= nil, "no view")
						if opts and opts.failUpdate then
							error("fake update failed")
						end
						table.insert(calls, name .. ":update")
					end,
					onMoment = function(_self: any, moment: any, _view: any)
						table.insert(calls, name .. ":moment:" .. moment.seq)
					end,
					destroy = function(_self: any)
						table.insert(calls, name .. ":destroy")
					end,
				}
			end,
		}
	end

	-- Runs `fn` with only `specs` in PIECES (Match HUD M6 / M7: the real pieces are set aside), then puts the list back
	-- and ends any session.
	local function withPieces(specs: { any }, fn: () -> ...any)
		local real = table.clone(Hud.PIECES)
		table.clear(Hud.PIECES)
		for _, spec in specs do
			table.insert(Hud.PIECES, spec)
		end
		local ok, err = pcall(fn)
		Hud.destroy()
		table.clear(Hud.PIECES)
		for _, spec in real do
			table.insert(Hud.PIECES, spec)
		end
		if not ok then
			error(err, 0)
		end
	end

	local function count(calls: { string }, entry: string): number
		local n = 0
		for _, c in calls do
			if c == entry then
				n += 1
			end
		end
		return n
	end

	t.test("the pieces are respawn, card, feed, intro, finish in draw order, each with its switch", function()
		local names = {}
		for _, spec in Hud.PIECES do
			table.insert(names, spec.name)
			expect.truthy(type(Config.UI.Match.enabled[spec.name]) == "boolean")
		end
		expect.deepEqual(names, { "respawn", "card", "feed", "intro", "finish" })
	end)

	t.test("init / start / destroy run cleanly in Edit mode (no LocalPlayer, no match)", function()
		Hud.init()
		Hud.start()
		expect.equal(Hud.debugState().matchId, nil)
		Hud.destroy()
	end)

	t.test("a real match builds only switched-on pieces: none with no switch, no per-frame effect then", function()
		for name, on in Config.UI.Match.enabled do
			expect.truthy(type(on) == "boolean")
			expect.truthy(type(name) == "string")
		end
		-- Match HUD M6 / M7: the medal (Diego's kill banner is that moment) and the killer camera are not built.
		expect.equal(Config.UI.Match.enabled.medal, false)
		expect.equal(Config.UI.Match.enabled.killerCam, false)
		local calls = {}
		withPieces({ fake("noSwitch", calls) }, function()
			Hud.init()
			local view = assert(Fixtures.build("tdm_live", 1.8e9, { youId = 7 })).view
			StateController.MatchChanged:fire(view, nil)
			local state = Hud.debugState()
			expect.equal(state.matchId, view.matchId)
			expect.equal(state.preview, false)
			expect.deepEqual(state.pieces, {})
			expect.equal(state.effect, false)
			expect.deepEqual(calls, {})
			StateController.MatchChanged:fire(nil, view)
			expect.equal(Hud.debugState().matchId, nil)
		end)
	end)

	t.test("debugShow: every piece built, updated at once, the state's moments played once in order", function()
		local calls = {}
		withPieces({ fake("a", calls), fake("b", calls) }, function()
			local reply = Hud.debugShow("tdm_feedBusy", { youId = 7 })
			expect.equal(reply.ok, true)
			expect.deepEqual(reply.pieces, { "a", "b" })
			expect.equal(reply.moments, 3)
			expect.equal(reply.players, 12)
			expect.deepEqual(calls, {
				"a:new",
				"b:new",
				"a:update",
				"b:update",
				"a:moment:1",
				"b:moment:1",
				"a:moment:2",
				"b:moment:2",
				"a:moment:3",
				"b:moment:3",
			})
			local state = Hud.debugState()
			expect.equal(state.preview, true)
			expect.equal(state.effect, true)
			table.clear(calls)
			local done = Hud.debugShow(nil)
			expect.equal(done.ok, true)
			expect.truthy(table.find(done.states, "ffa_endWin") ~= nil)
			expect.deepEqual(calls, { "b:destroy", "a:destroy" })
			expect.equal(Hud.debugState().matchId, nil)
			expect.equal(Hud.debugState().effect, false)
		end)
	end)

	t.test("debugShow: an unknown state is refused with the list; a new state replaces the old preview", function()
		local calls = {}
		withPieces({ fake("a", calls) }, function()
			local bad = Hud.debugShow("tdm_nope")
			expect.equal(bad.ok, false)
			expect.truthy(table.find(bad.states, "tdm_live") ~= nil)
			expect.equal(Hud.debugShow("ffa_endWin").outcome, "win")
			table.clear(calls)
			expect.equal(Hud.debugShow("ffa_live").ok, true)
			expect.equal(calls[1], "a:destroy")
			expect.equal(count(calls, "a:new"), 1)
		end)
	end)

	t.test("a piece that fails to build or to update never stops the others", function()
		local calls = {}
		withPieces({
			fake("bad", calls, { failNew = true }),
			fake("worse", calls, { failUpdate = true }),
			fake("good", calls),
		}, function()
			local reply = Hud.debugShow("ffa_yourSquish")
			expect.equal(reply.ok, true)
			expect.deepEqual(reply.pieces, { "worse", "good" })
			expect.equal(count(calls, "good:update"), 1)
			expect.equal(count(calls, "worse:moment:2"), 1)
			expect.equal(count(calls, "good:moment:2"), 1)
		end)
	end)

	t.test("a real match view ends a preview; no preview starts during a real match", function()
		local calls = {}
		withPieces({ fake("a", calls) }, function()
			Hud.init()
			expect.equal(Hud.debugShow("tdm_live").ok, true)
			local view = assert(Fixtures.build("ffa_live", 1.8e9, { youId = 7 })).view
			local real = table.clone(view)
			real.matchId = "match:real-1"
			StateController.MatchChanged:fire(real, nil)
			expect.equal(count(calls, "a:destroy"), 1)
			expect.equal(Hud.debugState().matchId, "match:real-1")
			expect.equal(Hud.debugState().preview, false)
			expect.equal(Hud.debugShow("ffa_live").ok, false)
			StateController.MatchChanged:fire(nil, real)
			expect.equal(Hud.debugState().matchId, nil)
			expect.equal(Hud.debugShow("ffa_live").ok, true)
		end)
	end)
end
