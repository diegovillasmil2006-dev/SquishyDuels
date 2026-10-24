--!strict
-- DuelPads_Test: ServerScriptService.Server.Logic.DuelPads, the rules of the duel pads under the Duel tower (Batch 3,
-- review #6). Server only (ServerStorage.UnitTest). Pure: no instances; time, positions and who stands where come in.
-- Contract (Config.Social.Pads, WorldLayout.QueuePads):
--   * the 10 queue pads form 5 lanes, each a mint pad and the strawberry pad straight across from it (Neon Sugar
--     lobby, 2026-10-24: a mint row and a strawberry row on Diego's Monument base);
--   * padAt: a root within radiusStuds of a pad's centre (horizontally) and 0..heightStuds above its top stands on it;
--   * a player alone lights their pad ("on") and gets the waiting toast; both pads of a lane go "ready" (gold, one
--     "ready" effect naming both players) and start once, holdSeconds later; stepping off before that resets the lane
--     (no start, the glow goes back);
--   * a pad belongs to the first player on it: a second player on it is ignored (the lower userId wins a tie);
--   * a lane whose owners change starts its hold again; retry lets a refused start fire on the next step;
--   * the waiting toast goes to one player at most once per waitingToastSeconds.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local DuelPads = t.requireServer("Logic/DuelPads")
	local Config = t.requireShared("Config")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local CFG = Config.Social.Pads
	local PADS = WorldLayout.QueuePads
	local LANES = DuelPads.lanes(PADS)
	local M, S = LANES[1].mint, LANES[1].strawberry -- lane 1's pads

	local function ofKind(effects: { any }, kind: string): { any }
		local found = {}
		for _, effect in effects do
			if effect.kind == kind then
				table.insert(found, effect)
			end
		end
		return found
	end

	-- The look each pad got from the glow effects (later effects win).
	local function looks(effects: { any }): { [number]: string }
		local out = {}
		for _, effect in ofKind(effects, "glow") do
			out[effect.pad] = effect.look
		end
		return out
	end

	t.test(
		"the pads: 10 on the Monument base, 5 lanes of a mint pad and the strawberry pad straight across from it",
		function()
			expect.equal(#PADS, 10)
			expect.equal(#LANES, 5)
			local seen: { [number]: boolean } = {}
			for lane, pair in LANES do
				local mint, berry = PADS[pair.mint], PADS[pair.strawberry]
				expect.equal(mint.team, "mint")
				expect.equal(berry.team, "strawberry")
				expect.equal(mint.lane, lane)
				expect.equal(berry.lane, lane)
				-- The mint row 5.2 south of the Monument's centre, the strawberry row 10: one lane = one column.
				expect.near(mint.position.X, -9.6 + (lane - 1) * 4.8, 1e-4)
				expect.near(berry.position.X, mint.position.X, 1e-6)
				expect.near(mint.position.Z, 5.2, 1e-6)
				expect.near(berry.position.Z, 10, 1e-6)
				expect.near(mint.position.Y, 2.3 + 0.5, 1e-6) -- the pad's top on Diego's Monument base (top 2.3)
				expect.near(berry.position.Y, mint.position.Y, 1e-6)
				seen[pair.mint], seen[pair.strawberry] = true, true
			end
			for index = 1, 10 do
				expect.truthy(seen[index])
			end
		end
	)

	t.test("padAt: within the radius and up to the height above the pad's top", function()
		local top = PADS[M].position
		expect.equal(DuelPads.padAt(PADS, top + Vector3.new(0, 3, 0), CFG), M)
		expect.equal(DuelPads.padAt(PADS, top + Vector3.new(0, 3, CFG.radiusStuds - 0.01), CFG), M)
		expect.equal(DuelPads.padAt(PADS, top + Vector3.new(0, 3, CFG.radiusStuds + 0.01), CFG), nil)
		expect.equal(DuelPads.padAt(PADS, top + Vector3.new(0, CFG.heightStuds + 0.01, 0), CFG), nil)
		expect.equal(DuelPads.padAt(PADS, top + Vector3.new(0, -0.5, 0), CFG), nil) -- under the pad
		expect.equal(DuelPads.padAt(PADS, Vector3.new(0, 3, 0), CFG), nil) -- the medallion in the middle
		expect.equal(DuelPads.padAt(PADS, PADS[S].position + Vector3.new(0.5, 2, 0), CFG), S)
	end)

	t.test(
		"alone: the pad lights and the toast goes out; the partner turns both gold; one start after the hold",
		function()
			local state = DuelPads.new()
			local fx = DuelPads.step(state, PADS, { [1] = M }, 0, CFG)
			expect.deepEqual(looks(fx), { [M] = "on" })
			expect.deepEqual(ofKind(fx, "waiting"), { { kind = "waiting", userId = 1, team = "mint" } })
			expect.equal(#DuelPads.step(state, PADS, { [1] = M }, 1, CFG), 0) -- nothing changed
			fx = DuelPads.step(state, PADS, { [1] = M, [2] = S }, 2, CFG)
			expect.deepEqual(looks(fx), { [M] = "ready", [S] = "ready" })
			expect.equal(#ofKind(fx, "waiting"), 0) -- the partner was already there
			expect.deepEqual(ofKind(fx, "ready"), { { kind = "ready", lane = 1, mint = 1, strawberry = 2 } })
			expect.equal(#ofKind(fx, "start"), 0)
			fx = DuelPads.step(state, PADS, { [1] = M, [2] = S }, 2 + CFG.holdSeconds - 0.01, CFG)
			expect.equal(#fx, 0)
			fx = DuelPads.step(state, PADS, { [1] = M, [2] = S }, 2 + CFG.holdSeconds, CFG)
			expect.deepEqual(fx, { { kind = "start", lane = 1, mint = 1, strawberry = 2 } })
			expect.equal(#DuelPads.step(state, PADS, { [1] = M, [2] = S }, 2 + CFG.holdSeconds + 1, CFG), 0) -- once
		end
	)

	t.test("stepping off before the hold resets the lane: no start, the glow goes back", function()
		local state = DuelPads.new()
		DuelPads.step(state, PADS, { [1] = M, [2] = S }, 0, CFG)
		local fx = DuelPads.step(state, PADS, { [1] = M }, 1, CFG)
		expect.deepEqual(looks(fx), { [M] = "on", [S] = "off" })
		fx = DuelPads.step(state, PADS, { [1] = M, [2] = S }, 2, CFG) -- back on: a new hold from now
		expect.deepEqual(looks(fx), { [M] = "ready", [S] = "ready" })
		expect.equal(#ofKind(DuelPads.step(state, PADS, { [1] = M, [2] = S }, CFG.holdSeconds, CFG), "start"), 0)
		expect.equal(#ofKind(DuelPads.step(state, PADS, { [1] = M, [2] = S }, 2 + CFG.holdSeconds, CFG), "start"), 1)
		fx = DuelPads.step(state, PADS, {}, 9, CFG)
		expect.deepEqual(looks(fx), { [M] = "off", [S] = "off" })
	end)

	t.test("a pad belongs to the first player on it; two arriving together: the lower userId", function()
		local state = DuelPads.new()
		DuelPads.step(state, PADS, { [5] = M }, 0, CFG)
		expect.equal(#DuelPads.step(state, PADS, { [5] = M, [3] = M }, 1, CFG), 0) -- 3 is ignored
		local fx = DuelPads.step(state, PADS, { [3] = M, [7] = S }, 2, CFG) -- 5 left: 3 takes the pad
		expect.equal(#ofKind(DuelPads.step(state, PADS, { [3] = M, [7] = S }, 2 + CFG.holdSeconds, CFG), "start"), 1)
		expect.deepEqual(looks(fx), { [M] = "ready", [S] = "ready" })
		local tie = DuelPads.new()
		fx = DuelPads.step(tie, PADS, { [9] = M, [4] = M }, 0, CFG)
		expect.deepEqual(ofKind(fx, "waiting"), { { kind = "waiting", userId = 4, team = "mint" } })
	end)

	t.test("new owners start the hold again; retry fires a refused start on the next step", function()
		local state = DuelPads.new()
		DuelPads.step(state, PADS, { [1] = M, [2] = S }, 0, CFG)
		DuelPads.step(state, PADS, { [1] = M, [3] = S }, 1, CFG) -- 2 left and 3 stepped on in one check
		expect.equal(#ofKind(DuelPads.step(state, PADS, { [1] = M, [3] = S }, CFG.holdSeconds, CFG), "start"), 0)
		local fx = DuelPads.step(state, PADS, { [1] = M, [3] = S }, 1 + CFG.holdSeconds, CFG)
		expect.deepEqual(ofKind(fx, "start"), { { kind = "start", lane = 1, mint = 1, strawberry = 3 } })
		DuelPads.retry(state, 1)
		fx = DuelPads.step(state, PADS, { [1] = M, [3] = S }, 1.2 + CFG.holdSeconds, CFG)
		expect.equal(#ofKind(fx, "start"), 1)
		expect.equal(#ofKind(fx, "ready"), 0) -- a retry is not a new countdown
	end)

	t.test("the waiting toast goes to a player at most once per waitingToastSeconds", function()
		local state = DuelPads.new()
		expect.equal(#ofKind(DuelPads.step(state, PADS, { [1] = M }, 0, CFG), "waiting"), 1)
		DuelPads.step(state, PADS, {}, 1, CFG)
		expect.equal(#ofKind(DuelPads.step(state, PADS, { [1] = S }, 2, CFG), "waiting"), 0)
		DuelPads.step(state, PADS, {}, 3, CFG)
		local fx = DuelPads.step(state, PADS, { [1] = S }, CFG.waitingToastSeconds + 0.01, CFG)
		expect.deepEqual(ofKind(fx, "waiting"), { { kind = "waiting", userId = 1, team = "strawberry" } })
	end)
end
