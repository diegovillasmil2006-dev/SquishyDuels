--!strict
-- FriendDuelService_Test: ServerScriptService.Server.Services.FriendDuelService, the duel pads and Rematch (Batch 3,
-- review #6). Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never called; every collaborator is
-- a fake passed through useDeps (players are FakePlayers, roots are positions, QueueService.startDirect is a recorder,
-- time is a FakeClock) and each case runs tick() by hand. Logic/DuelPads is the real one.
-- Contract (Config.Social.Pads / Rematch):
--   * two players on facing pads both hear who and the countdown (duel.padReady); one duel starts through
--     startDirect once the hold is over (no toast then: the queue's banner names the opponent);
--   * a cooldown or a full arena retries on the next check (the full arena toasted once); another refusal is toasted
--     once and not retried while they keep standing;
--   * the rings follow off / on / ready (setGlow); bindRings paints a lobby's queue_pad_ring parts (on = the team
--     colour, ready = butter, both Neon; off = the part's own colour and material again);
--   * a player who may not stand (in a match, dead, the test dummy) never counts on a pad;
--   * Rematch: a finished duel (win or draw, no bailer) between two real players in the server offers it both ways
--     (SD_RematchWith); a press sets the player's own wish (SD_RematchWant), a second press takes it back; both
--     wishes start one duel on the next check, retried each check until the window ends; offers expire silently, and
--     leaving or joining the queue clears them; a press without an offer does nothing; pad and Rematch duels are
--     friend matches.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	clock: any,
	players: { any },
	roots: { [any]: Vector3 },
	blocked: { [any]: boolean },
	started: { { a: any, b: any } },
	refusals: { string },
	notices: { { player: any, code: string, args: any } },
	glows: { [number]: string },
	matches: number,
}

return function(t: Context)
	local expect = t.expect
	local FriendDuelService = t.requireServer("Services/FriendDuelService")
	local DuelPads = t.requireServer("Logic/DuelPads")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local FakeClock = t.requireFake("FakeClock")
	local FakePlayer = t.requireFake("FakePlayer")
	local PADS = WorldLayout.QueuePads
	local LANES = DuelPads.lanes(PADS)
	local M, S = LANES[1].mint, LANES[1].strawberry
	local HOLD = Config.Social.Pads.holdSeconds
	local WINDOW = Config.Social.Rematch.windowSeconds

	local function setup(count: number): World
		local w: World = {
			clock = FakeClock.new(1000),
			players = {},
			roots = {},
			blocked = {},
			started = {},
			refusals = {},
			notices = {},
			glows = {},
			matches = 0,
		}
		FriendDuelService.useDeps({
			now = w.clock.now,
			players = function(): { any }
				return w.players
			end,
			rootPosition = function(player: any): Vector3?
				return w.roots[player]
			end,
			canStand = function(player: any): boolean
				return not w.blocked[player]
			end,
			startDirect = function(a: any, b: any): (boolean, any)
				table.insert(w.started, { a = a, b = b })
				local refusal = table.remove(w.refusals, 1)
				if refusal then
					return false, refusal
				end
				w.matches += 1
				return true, { matchId = `m{w.matches}` }
			end,
			notify = function(player: any, code: string, args: any)
				table.insert(w.notices, { player = player, code = code, args = args })
			end,
			setGlow = function(pad: number, look: string)
				w.glows[pad] = look
			end,
		})
		for i = 1, count do
			table.insert(w.players, FakePlayer.new(i, `P{i}`))
		end
		return w
	end

	local function stand(w: World, player: any, pad: number?)
		w.roots[player] = if pad then PADS[pad].position + Vector3.new(0, 3, 0) else nil
	end

	local function codes(w: World, player: any): { string }
		local list = {}
		for _, notice in w.notices do
			if notice.player == player then
				table.insert(list, notice.code)
			end
		end
		return list
	end

	-- A finished duel's MatchEnded summary (DuelService.MatchSummary's fields this service reads).
	local function ended(a: any, b: any, outcome: string?, bailers: { number }?, dummyB: boolean?): any
		return {
			matchId = "old",
			outcome = outcome or "win",
			participants = {
				{ userId = a.UserId, player = a, isTestDummy = false },
				{ userId = b.UserId, player = if dummyB then nil else b, isTestDummy = dummyB == true },
			},
			bailers = bailers or {},
		}
	end

	t.test("two friends on facing pads hear who and the countdown; one duel after the hold", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		stand(w, p1, M)
		stand(w, p2, S)
		FriendDuelService.tick()
		expect.equal(#w.started, 0)
		expect.deepEqual(codes(w, p1), { "duel.padReady" })
		expect.deepEqual(codes(w, p2), { "duel.padReady" })
		expect.deepEqual(w.notices[1].args, { name = "P2", seconds = HOLD }) -- p1 (mint) hears p2's name
		expect.deepEqual(w.notices[2].args, { name = "P1", seconds = HOLD })
		w.clock.advance(HOLD)
		FriendDuelService.tick()
		expect.equal(#w.started, 1)
		expect.equal(w.started[1].a, p1) -- the mint player first
		expect.equal(w.started[1].b, p2)
		expect.equal(#w.notices, 2) -- no toast at the start: the queue's "Opponent found" banner names the opponent
		expect.truthy(FriendDuelService.isFriendMatch("m1"))
		expect.falsy(FriendDuelService.isFriendMatch("other"))
		w.clock.advance(1)
		FriendDuelService.tick()
		expect.equal(#w.started, 1) -- once
	end)

	t.test("a lone player hears the waiting toast; the partner's team names the pad they need", function()
		local w = setup(2)
		stand(w, w.players[1], M)
		stand(w, w.players[2], LANES[2].strawberry)
		FriendDuelService.tick()
		expect.deepEqual(codes(w, w.players[1]), { "duel.padWaitingStrawberry" })
		expect.deepEqual(codes(w, w.players[2]), { "duel.padWaitingMint" })
	end)

	t.test("a cooldown or a full arena retries each check (the full arena toasted once); others toast once", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		w.refusals = { "queue.cooldown", "queue.waitingArena", "queue.waitingArena" }
		stand(w, p1, M)
		stand(w, p2, S)
		FriendDuelService.tick()
		w.clock.advance(HOLD)
		for _ = 1, 4 do
			FriendDuelService.tick()
			w.clock.advance(0.2)
		end
		expect.equal(#w.started, 4)
		expect.deepEqual(codes(w, p1), { "duel.padReady", "queue.waitingArena" })

		local v = setup(2)
		local q1, q2 = v.players[1], v.players[2]
		v.refusals = { "queue.paused" }
		stand(v, q1, M)
		stand(v, q2, S)
		FriendDuelService.tick()
		v.clock.advance(HOLD)
		for _ = 1, 3 do
			FriendDuelService.tick()
			v.clock.advance(0.2)
		end
		expect.equal(#v.started, 1)
		expect.deepEqual(codes(v, q2), { "duel.padReady", "queue.paused" })
	end)

	t.test("the rings follow off / on / ready", function()
		local w = setup(2)
		stand(w, w.players[1], M)
		FriendDuelService.tick()
		expect.equal(w.glows[M], "on")
		stand(w, w.players[2], S)
		FriendDuelService.tick()
		expect.equal(w.glows[M], "ready")
		expect.equal(w.glows[S], "ready")
		stand(w, w.players[1], nil)
		stand(w, w.players[2], nil)
		FriendDuelService.tick()
		expect.equal(w.glows[M], "off")
		expect.equal(w.glows[S], "off")
	end)

	t.test("bindRings: the team colour or butter in Neon, then the ring's own look again", function()
		local gate = Instance.new("Model")
		for index, pad in PADS do
			local ring = Instance.new("Part")
			ring.Name = "queue_pad_ring"
			ring.Color = Palette.LobbyPebble
			ring.Material = Enum.Material.SmoothPlastic
			ring.Position = pad.position - Vector3.new(0, 0.3, 0)
			ring.Parent = gate
			ring:SetAttribute("Index", index)
		end
		local other = Instance.new("Part") -- not a ring: never painted
		other.Name = "queue_pad"
		other.Parent = gate
		local setGlow, bound = FriendDuelService.bindRings(gate)
		expect.equal(bound, 10)
		local function ring(index: number): Part
			for _, child in gate:GetChildren() do
				if child:GetAttribute("Index") == index then
					return child :: Part
				end
			end
			error("no ring " .. index)
		end
		setGlow(M, "on")
		setGlow(S, "on")
		expect.equal(ring(M).Color, Palette.LobbyMint)
		expect.equal(ring(S).Color, Palette.LobbyStrawberry)
		expect.equal(ring(M).Material, Enum.Material.Neon)
		setGlow(M, "ready")
		expect.equal(ring(M).Color, Palette.LobbyButter)
		setGlow(M, "off")
		expect.equal(ring(M).Color, Palette.LobbyPebble)
		expect.equal(ring(M).Material, Enum.Material.SmoothPlastic)
		expect.equal(other.Material, Enum.Material.Plastic)
		gate:Destroy()
		local _, none = FriendDuelService.bindRings(nil)
		expect.equal(none, 0)
	end)

	t.test("a player who may not stand (in a match, dead, the dummy) never counts on a pad", function()
		local w = setup(2)
		stand(w, w.players[1], M)
		stand(w, w.players[2], S)
		w.blocked[w.players[2]] = true
		FriendDuelService.tick()
		w.clock.advance(HOLD + 1)
		FriendDuelService.tick()
		expect.equal(#w.started, 0)
		expect.equal(w.glows[S], nil)
	end)

	t.test("Rematch is offered both ways after a win or a draw; not after a cancel, a bail or the dummy", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		FriendDuelService.handleMatchEnded(ended(p1, p2))
		expect.equal(p1:GetAttribute("SD_RematchWith"), 2)
		expect.equal(p2:GetAttribute("SD_RematchWith"), 1)
		local draw = setup(2)
		FriendDuelService.handleMatchEnded(ended(draw.players[1], draw.players[2], "draw"))
		expect.equal(draw.players[1]:GetAttribute("SD_RematchWith"), 2)
		local noOffer = {
			function(a: any, b: any): any
				return ended(a, b, "cancelled")
			end,
			function(a: any, b: any): any
				return ended(a, b, "win", { 2 }) -- the loser forfeited or left
			end,
			function(a: any, b: any): any
				return ended(a, b, "win", nil, true) -- the Studio test dummy
			end,
		}
		for _, make in noOffer do
			local v = setup(2)
			FriendDuelService.handleMatchEnded(make(v.players[1], v.players[2]))
			expect.equal(v.players[1]:GetAttribute("SD_RematchWith"), nil)
			expect.equal(v.players[2]:GetAttribute("SD_RematchWith"), nil)
		end
		local gone = setup(2)
		gone.players[2].Parent = nil -- left before the result
		FriendDuelService.handleMatchEnded(ended(gone.players[1], gone.players[2]))
		expect.equal(gone.players[1]:GetAttribute("SD_RematchWith"), nil)
	end)

	t.test("one press sets the wish; both start one duel on the next check; spam never starts two", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		FriendDuelService.handleMatchEnded(ended(p1, p2))
		FriendDuelService.requestRematch(p1)
		expect.equal(p1:GetAttribute("SD_RematchWant"), 2)
		FriendDuelService.tick()
		expect.equal(#w.started, 0)
		FriendDuelService.requestRematch(p2)
		FriendDuelService.tick()
		expect.equal(#w.started, 1)
		expect.truthy(FriendDuelService.isFriendMatch("m1"))
		for _, player in { p1, p2 } do
			expect.equal(player:GetAttribute("SD_RematchWith"), nil)
			expect.equal(player:GetAttribute("SD_RematchWant"), nil)
		end
		FriendDuelService.requestRematch(p1)
		FriendDuelService.requestRematch(p2)
		FriendDuelService.tick()
		expect.equal(#w.started, 1)
		expect.equal(p1:GetAttribute("SD_RematchWant"), nil) -- no offer any more
	end)

	t.test("a second press takes the wish back (the card closed by hand): no duel when the other presses", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		FriendDuelService.handleMatchEnded(ended(p1, p2))
		FriendDuelService.requestRematch(p1)
		FriendDuelService.requestRematch(p1)
		expect.equal(p1:GetAttribute("SD_RematchWant"), nil)
		FriendDuelService.requestRematch(p2)
		FriendDuelService.tick()
		expect.equal(#w.started, 0)
		expect.equal(p2:GetAttribute("SD_RematchWant"), 1)
		FriendDuelService.requestRematch(p1) -- p1 changes their mind again
		FriendDuelService.tick()
		expect.equal(#w.started, 1)
	end)

	t.test("a refused rematch is tried each check until it starts or the window ends", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		w.refusals = { "queue.alreadyQueued", "queue.cooldown" }
		FriendDuelService.handleMatchEnded(ended(p1, p2))
		FriendDuelService.requestRematch(p1)
		FriendDuelService.requestRematch(p2)
		for _ = 1, 3 do
			FriendDuelService.tick()
			w.clock.advance(0.2)
		end
		expect.equal(#w.started, 3)
		expect.truthy(FriendDuelService.isFriendMatch("m1"))

		local v = setup(2)
		v.refusals = { "queue.paused", "queue.paused", "queue.paused" }
		FriendDuelService.handleMatchEnded(ended(v.players[1], v.players[2]))
		FriendDuelService.requestRematch(v.players[1])
		FriendDuelService.requestRematch(v.players[2])
		FriendDuelService.tick()
		v.clock.advance(WINDOW)
		FriendDuelService.tick()
		expect.equal(#v.started, 1) -- the window is over: no more tries, the offer is gone
		expect.equal(v.players[1]:GetAttribute("SD_RematchWith"), nil)
	end)

	t.test("offers expire silently; leaving or joining the queue clears both; no offer, no wish", function()
		local w = setup(3)
		local p1, p2, p3 = w.players[1], w.players[2], w.players[3]
		FriendDuelService.requestRematch(p3)
		expect.equal(p3:GetAttribute("SD_RematchWant"), nil)
		FriendDuelService.handleMatchEnded(ended(p1, p2))
		w.clock.advance(WINDOW + 0.01)
		FriendDuelService.tick()
		expect.equal(p1:GetAttribute("SD_RematchWith"), nil)
		expect.equal(p2:GetAttribute("SD_RematchWith"), nil)
		FriendDuelService.requestRematch(p1)
		expect.equal(p1:GetAttribute("SD_RematchWant"), nil)
		expect.equal(#w.notices, 0)

		FriendDuelService.handleMatchEnded(ended(p1, p2))
		FriendDuelService.requestRematch(p2)
		FriendDuelService.playerRemoving(p1)
		expect.equal(p2:GetAttribute("SD_RematchWith"), nil)
		expect.equal(p2:GetAttribute("SD_RematchWant"), nil)

		FriendDuelService.handleMatchEnded(ended(p2, p3))
		FriendDuelService.cancelRematch(p3) -- p3 joined the queue
		expect.equal(p2:GetAttribute("SD_RematchWith"), nil)
		expect.equal(p3:GetAttribute("SD_RematchWith"), nil)
	end)
end
