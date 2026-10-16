--!strict
-- MatchService_Test: unit tests for ServerScriptService.Server.Services.MatchService (FFA/TDM v1, 2026-10-15). Server
-- only (ServerStorage.UnitTest). Edit mode: init() is never called; every collaborator is a fake passed through
-- useDeps (players are FakePlayers with plain-table roots and humanoids, CombatService / AbilityService / the map
-- registry are recorders, time is a FakeClock that wait() moves, deferred work runs when the case flushes it), and the
-- rules are the real Logic/MatchRules and Logic/MatchSpawns with the test's own Config.Match copy.
-- Contract (SPEC D1-D6, D11, C1-C4):
--   * joins: refused with a match.refused.* toast while closing, already queued, in a match, in the duel queue,
--     practicing or with no map of the mode; minPlayers start the gather (gatherSeconds), the whole server queued or
--     maxPlayers start at once on a free map; a ticket of a player now in the duel queue is dropped;
--   * a match: SD_MatchId "match:<GUID>", SD_DuelPhase (the D1 name), SD_MatchPhase, SD_MatchMode, SD_Team (TDM); the
--     port (ffa, teams, Bounds only, the D1 phase, cooldown 1); the first MatchState view; each player teleported to
--     its MatchSpawns spot and frozen (arrived); Countdown, then Active with the match movement and nextThrowAt;
--   * a hit is a K.O. (eliminated, TDM team lives, no team hits): frozen and unhittable, back at a respawn spot after
--     respawnSeconds with protection; out of bounds is a re-pivot (silent before Active), never a K.O.; a character
--     found outside the map is placed back; the TDM storm samples standing players into a storm K.O.;
--   * the end: toasts, the outcome in the view, MatchEnded; Result, then the final "Returning" view and the return
--     (lobby point, movement restored, attributes cleared, port unregistered, map released); /leave, a player who
--     never arrives (dropped, or the match cancelled), shutdown (void).
--   * review fixes (2026-10-15): a leaver / a player who never arrived / one who left the game is detached and
--     released (AbilityService.detachFighter, CombatService.releaseFighter) and the others' views drop them; /leave
--     while a teleport streams (the first one, a D5 re-placement) still ends in the lobby, not frozen; an
--     out-of-bounds far from the map is the streamed re-placement; a dead character never fills the storm bar; no
--     re-placement in Result; a tick with no timer due steps nothing; every map in use: one waitingMap, a later
--     joiner hears it too, the match starts once a map is free; a failed registration is undone; QueueService.Joined
--     drops the ticket; RestartScheduled voids only a match that can't finish (maxRemaining); match.voidError.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	clock: any,
	cfg: any,
	players: { any },
	roots: { [number]: any },
	humanoids: { [number]: any },
	failTeleport: { [number]: boolean },
	duringTeleport: { [number]: () -> () }, -- runs once inside that user's next teleport (it "streams" meanwhile)
	dead: { [number]: boolean }, -- the Humanoid died: the corpse's root is still there
	queueState: { [number]: string },
	practicing: { [number]: boolean },
	flags: { closing: boolean, restart: boolean, canFinish: boolean, failRegister: boolean },
	asked: number?, -- the seconds of the last canFinishBeforeRestart call
	maps: { any },
	released: number,
	deferred: { { fn: (...any) -> ...any, args: { any } } },
	sent: { { name: string, player: any, payload: any } },
	notices: { { player: any, code: string, args: any, kind: string? } },
	teleports: { { userId: number, cf: CFrame } },
	pivots: { { userId: number, cf: CFrame } },
	port: any,
	unregistered: { string },
	attached: number,
	detached: { string },
	releasedFighters: { any }, -- CombatService.releaseFighter calls
	detachedUsers: { number }, -- AbilityService.detachFighter calls
	syncs: number, -- CombatService.syncTo calls
	flush: () -> (),
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

return function(t: Context)
	local expect = t.expect
	local MatchService = t.requireServer("Services/MatchService")
	local MatchMapService = t.requireServer("Services/MatchMapService")
	local MatchSpawns = t.requireServer("Logic/MatchSpawns")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local FakePlayer = t.requireFake("FakePlayer")
	local FakeRng = t.requireFake("FakeRng")

	local T0 = 5000
	local seenCodes: { [string]: boolean } = {} -- every Notify code the cases saw (checked by the last case)
	local CENTRE = Vector3.new(6000, 0, 0)
	local LOBBY = Vector3.new(0, 3, 0)

	-- Config.Match with every value the cases rely on spelled out (the place's Config may be an older copy).
	local function baseConfig(): any
		local cfg = deepCopy(Config.Match)
		cfg.waitSeconds = 20
		cfg.countdownSeconds = 3
		cfg.respawnSeconds = 3
		cfg.spawnProtectSeconds = 2
		cfg.resultSeconds = 8
		cfg.minPlayers = 2
		cfg.gatherSeconds = 10
		cfg.rewardCoins = 0
		cfg.outOfBoundsIsKo = false
		cfg.returnSpreadStuds = 4
		cfg.Maps = {
			footprint = { TDM = Vector3.new(160, 0, 240), FFA = Vector3.new(200, 0, 200) },
			boundsBottomOffset = -15,
			boundsTop = 100,
		}
		cfg.Spawns = { spotsPerPad = { tdm = 6, ffa = 2 }, edgeStuds = 4, occupiedStuds = 4, raycastUpStuds = 40 }
		cfg.Storm.sampleHz = 5
		cfg.Storm.respawnInsetStuds = 6
		return cfg
	end

	local function mapRecord(cfg: any, modeId: string, name: string): any
		local footprint = cfg.Maps.footprint[string.upper(modeId)]
		local pads: { any } = {}
		local function pad(x: number, z: number, team: string?)
			table.insert(
				pads,
				{ cframe = CFrame.new(CENTRE.X + x, -0.25, z), size = Vector3.new(30, 0.5, 20), team = team }
			)
		end
		if modeId == "tdm" then
			pad(0, -100, cfg.teamNames[1])
			pad(0, 100, cfg.teamNames[2])
		else
			pad(-60, -60)
			pad(60, -60)
			pad(60, 60)
			pad(-60, 60)
		end
		return {
			model = nil,
			name = name,
			code = name,
			modeId = modeId,
			centre = CENTRE,
			floorY = 0,
			footprint = footprint,
			startRadius = math.sqrt(footprint.X * footprint.X + footprint.Z * footprint.Z) / 2,
			bounds = MatchMapService.boundsFor(CENTRE, 0, footprint, cfg),
			raycastParams = RaycastParams.new(),
			overlapParams = OverlapParams.new(),
			pads = pads,
			spawns = MatchSpawns.build(pads, CENTRE, 0, modeId, cfg),
			powerUpPads = {},
			raycast = function(): Vector3?
				return nil
			end,
			inUse = false,
			matchId = nil,
		}
	end

	-- A world of `count` players in the server, nobody queued yet.
	local function setup(count: number, cfg: any?): World
		local c = cfg or baseConfig()
		local w: World = {
			clock = FakeClock.new(T0),
			cfg = c,
			players = {},
			roots = {},
			humanoids = {},
			failTeleport = {},
			duringTeleport = {},
			dead = {},
			queueState = {},
			practicing = {},
			flags = { closing = false, restart = false, canFinish = true, failRegister = false },
			asked = nil,
			maps = { mapRecord(c, "ffa", "JAR"), mapRecord(c, "tdm", "TBC") },
			released = 0,
			deferred = {},
			sent = {},
			notices = {},
			teleports = {},
			pivots = {},
			port = nil,
			unregistered = {},
			attached = 0,
			detached = {},
			releasedFighters = {},
			detachedUsers = {},
			syncs = 0,
			flush = function() end,
		}
		w.flush = function()
			while #w.deferred > 0 do
				local job = table.remove(w.deferred, 1) :: any
				job.fn(table.unpack(job.args))
			end
		end
		for i = 1, count do
			local player = FakePlayer.new(i, `P{i}`)
			table.insert(w.players, player)
			w.roots[i] = {
				Position = LOBBY + Vector3.new(i, 0, 0),
				CFrame = CFrame.new(LOBBY),
				Size = Vector3.new(2, 2, 1),
			}
			w.humanoids[i] = {
				WalkSpeed = 16,
				JumpHeight = 7.2,
				JumpPower = 50,
				UseJumpPower = false,
				AutoRotate = true,
				RigType = Enum.HumanoidRigType.R15,
				HipHeight = 2,
			}
		end
		local function moveRoot(userId: number, cf: CFrame)
			local root = w.roots[userId]
			root.Position = cf.Position
			root.CFrame = cf
		end
		MatchService.useDeps({
			now = w.clock.now,
			clock = w.clock.now,
			wait = function(seconds: number)
				w.clock.advance(seconds)
			end,
			defer = function(fn: (...any) -> ...any, ...: any)
				table.insert(w.deferred, { fn = fn, args = { ... } })
			end,
			spawn = function(fn: (...any) -> ...any, ...: any)
				fn(...)
			end,
			rng = FakeRng.new(7),
			isPlayer = function(ref: any): boolean
				return type(ref) == "table" and ref.Parent ~= nil
			end,
			playerCount = function(): number
				local n = 0
				for _, p in w.players do
					if p.Parent ~= nil then
						n += 1
					end
				end
				return n
			end,
			getRoot = function(ref: any): any?
				return w.roots[ref.UserId]
			end,
			humanoid = function(ref: any): any?
				return w.humanoids[ref.UserId]
			end,
			isAlive = function(ref: any): boolean
				return w.roots[ref.UserId] ~= nil and not w.dead[ref.UserId]
			end,
			teleportAsync = function(ref: any, cf: CFrame): (boolean, string?)
				local during = w.duringTeleport[ref.UserId]
				if during then
					w.duringTeleport[ref.UserId] = nil
					during() -- what happens while the real teleport waits for streaming
				end
				if w.failTeleport[ref.UserId] or w.roots[ref.UserId] == nil or w.dead[ref.UserId] then
					return false, "noCharacter"
				end
				moveRoot(ref.UserId, cf)
				table.insert(w.teleports, { userId = ref.UserId, cf = cf })
				return true, nil
			end,
			equipped = function(_ref: any): string?
				return nil -- the starter
			end,
			queueState = function(ref: any): string
				return w.queueState[ref.UserId] or "Idle"
			end,
			isPracticing = function(ref: any): boolean
				return w.practicing[ref.UserId] == true
			end,
			closing = function(): boolean
				return w.flags.closing
			end,
			restartPending = function(): boolean
				return w.flags.restart
			end,
			canFinishBeforeRestart = function(seconds: number): boolean
				w.asked = seconds
				return w.flags.canFinish
			end,
			fire = function(name: string, player: any, payload: any)
				table.insert(w.sent, { name = name, player = player, payload = payload })
			end,
			notify = function(player: any, code: string, args: any, kind: string?)
				table.insert(w.notices, { player = player, code = code, args = args, kind = kind })
				seenCodes[code] = true
			end,
			combat = {
				newFighter = function(spec: any): any
					return {
						userId = spec.userId,
						player = spec.player,
						isTestDummy = false,
						side = spec.side,
						squishyId = spec.squishyId,
						getRoot = spec.getRoot,
						isAlive = spec.isAlive,
						nextThrowAt = spec.now,
						invulnUntil = -math.huge,
					}
				end,
				registerMatch = function(port: any)
					if w.flags.failRegister then
						error("registerMatch failed (test)")
					end
					w.port = port
				end,
				unregisterMatch = function(matchId: string)
					table.insert(w.unregistered, matchId)
				end,
				pivotFighter = function(fighter: any, cf: CFrame): boolean
					if w.roots[fighter.userId] == nil then
						return false
					end
					moveRoot(fighter.userId, cf)
					table.insert(w.pivots, { userId = fighter.userId, cf = cf })
					return true
				end,
				noteTeleport = function() end,
				syncTo = function()
					w.syncs += 1
				end,
				-- As area A's releaseFighter: the port gets a new fighters list without that fighter.
				releaseFighter = function(fighter: any): boolean
					table.insert(w.releasedFighters, fighter)
					if w.port == nil then
						return false
					end
					local kept = {}
					for _, other in w.port.fighters do
						if other ~= fighter then
							table.insert(kept, other)
						end
					end
					w.port.fighters = kept
					return true
				end,
			},
			ability = {
				attachMatch = function()
					w.attached += 1
				end,
				detachMatch = function(matchId: string)
					table.insert(w.detached, matchId)
				end,
				detachFighter = function(userId: number)
					table.insert(w.detachedUsers, userId)
				end,
				isReady = function(): boolean
					return false
				end,
			},
			maps = {
				acquire = function(modeId: string, matchId: string): any?
					for _, record in w.maps do
						if record.modeId == modeId and not record.inUse then
							record.inUse = true
							record.matchId = matchId
							return record
						end
					end
					return nil
				end,
				release = function(record: any)
					record.inUse = false
					w.released += 1
				end,
				hasMode = function(modeId: string): boolean
					for _, record in w.maps do
						if record.modeId == modeId then
							return true
						end
					end
					return false
				end,
			},
			heartbeat = false,
			matchConfig = c,
		})
		return w
	end

	local function close()
		MatchService.useDeps(nil)
	end

	local function codesOf(w: World, player: any?): { string }
		local out = {}
		for _, n in w.notices do
			if player == nil or n.player == player then
				table.insert(out, n.code)
			end
		end
		return out
	end

	local function lastView(w: World, player: any): any
		for i = #w.sent, 1, -1 do
			local entry = w.sent[i]
			if entry.name == "MatchState" and entry.player == player then
				return entry.payload
			end
		end
		return nil
	end

	local function fighterOf(w: World, userId: number): any
		for _, fighter in w.port.fighters do
			if fighter.userId == userId then
				return fighter
			end
		end
		error(`no fighter {userId}`)
	end

	-- Everyone queued for `modeId` (the whole server: the match starts at once), positioned, then Active.
	-- Returns the Active start time.
	local function live(w: World, modeId: string): number
		for _, player in w.players do
			MatchService.join(player, modeId)
		end
		expect.truthy(w.port ~= nil)
		w.flush() -- the first teleports: every player arrived, so the Countdown starts
		expect.equal(w.port.phase(), "Countdown")
		local activeAt = w.clock.now() + w.cfg.countdownSeconds
		w.clock.set(activeAt)
		MatchService.tick(activeAt)
		expect.equal(w.port.phase(), "Active")
		return activeAt
	end

	local function hit(w: World, victim: number, by: number, at: number): any
		local outcomes = w.port.applyHits({
			{
				attacker = fighterOf(w, by),
				victim = fighterOf(w, victim),
				at = at,
				kind = "throw",
				projId = 1,
				position = w.roots[victim].Position,
			},
		}, at)
		w.port.flush()
		return outcomes[1]
	end

	local function inMap(position: Vector3): boolean
		return Vector3.new(position.X - CENTRE.X, 0, position.Z - CENTRE.Z).Magnitude < 200
	end

	-- Phases on the wire --------------------------------------------------------------------------------------------

	t.test("D1: MatchRules phases go out as DuelPhase names (Overtime is Active, never SuddenDeath)", function()
		expect.equal(MatchService.wirePhase("Waiting"), "Positioning")
		expect.equal(MatchService.wirePhase("Countdown"), "Countdown")
		expect.equal(MatchService.wirePhase("Active"), "Active")
		expect.equal(MatchService.wirePhase("Overtime"), "Active")
		expect.equal(MatchService.wirePhase("Result"), "Result")
		expect.equal(MatchService.wirePhase("Closed"), "Returning")
	end)

	-- Queues ------------------------------------------------------------------------------------------------------------

	t.test("joins are refused with their toast: closing, queued, in a match, duel queue, practice, no map", function()
		local w = setup(6)
		local p = w.players
		w.flags.closing = true
		expect.equal(select(2, MatchService.join(p[1], "ffa")), "match.refused.closing")
		w.flags.closing = false
		w.flags.restart = true
		expect.equal(select(2, MatchService.join(p[1], "ffa")), "match.refused.closing")
		w.flags.restart = false
		expect.truthy((MatchService.join(p[1], "ffa")))
		expect.equal(select(2, MatchService.join(p[1], "tdm")), "match.refused.alreadyQueued")
		p[2]:SetAttribute("SD_MatchId", "duel-guid")
		expect.equal(select(2, MatchService.join(p[2], "ffa")), "match.refused.inMatch")
		w.queueState[3] = "Searching"
		expect.equal(select(2, MatchService.join(p[3], "ffa")), "match.refused.duelQueue")
		w.practicing[4] = true
		expect.equal(select(2, MatchService.join(p[4], "ffa")), "match.refused.practice")
		w.maps = { w.maps[2] } -- TDM only
		expect.equal(select(2, MatchService.join(p[5], "ffa")), "match.refused.noMaps")
		expect.equal(select(2, MatchService.join(p[5], "duel")), nil) -- an unknown mode: no toast
		expect.deepEqual(
			codesOf(w, p[1]),
			{ "match.refused.closing", "match.refused.closing", "match.joined", "match.refused.alreadyQueued" }
		)
		expect.equal(w.notices[3].args.count, 1)
		expect.equal(w.notices[3].args.max, w.cfg.Modes.ffa.maxPlayers)
		expect.equal(MatchService.queued(p[1]), "ffa")
		expect.equal(w.port, nil)
		close()
	end)

	t.test("minPlayers start the gather; the match starts after gatherSeconds with the queued players", function()
		local w = setup(3)
		MatchService.join(w.players[1], "ffa")
		MatchService.join(w.players[2], "ffa")
		expect.equal(w.port, nil)
		expect.deepEqual(codesOf(w, w.players[1]), { "match.joined", "match.startingIn" })
		expect.equal(w.notices[#w.notices].args.seconds, w.cfg.gatherSeconds)
		MatchService.tick(T0 + w.cfg.gatherSeconds - 0.1)
		expect.equal(w.port, nil)
		MatchService.tick(T0 + w.cfg.gatherSeconds)
		expect.truthy(w.port ~= nil)
		expect.equal(#w.port.fighters, 2)
		expect.equal(MatchService.queueCount("ffa"), 0)
		expect.equal(MatchService.getMatch(w.players[3]), nil)
		close()
	end)

	t.test("a ticket of a player who joined the duel queue is dropped; /leave drops one with a toast", function()
		local w = setup(4)
		MatchService.join(w.players[1], "ffa")
		MatchService.join(w.players[2], "ffa")
		w.queueState[2] = "Searching"
		MatchService.tick(T0 + 1)
		expect.equal(MatchService.queueCount("ffa"), 1)
		expect.truthy(MatchService.leave(w.players[1]))
		expect.equal(MatchService.queued(w.players[1]), nil)
		expect.equal(codesOf(w, w.players[1])[#codesOf(w, w.players[1])], "match.left")
		expect.falsy(MatchService.leave(w.players[3]))
		expect.deepEqual(codesOf(w, w.players[3]), { "match.notQueued" })
		-- QueueService.Joined (joining the duel queue or a friend duel): the ticket goes with match.leftForDuel.
		MatchService.join(w.players[4], "tdm")
		MatchService.onDuelQueueJoined(w.players[4])
		expect.equal(MatchService.queued(w.players[4]), nil)
		expect.deepEqual(codesOf(w, w.players[4]), { "match.joined", "match.leftForDuel" })
		close()
	end)

	t.test(
		"every map of the mode in use: one waitingMap toast, a later joiner hears the same, then it starts",
		function()
			local w = setup(3)
			w.maps[1].inUse = true -- the only FFA map is held by another match
			MatchService.join(w.players[1], "ffa")
			MatchService.join(w.players[2], "ffa")
			MatchService.tick(T0 + w.cfg.gatherSeconds)
			MatchService.tick(T0 + w.cfg.gatherSeconds + 0.5)
			expect.equal(w.port, nil)
			local waits = 0
			for _, code in codesOf(w, w.players[1]) do
				if code == "match.waitingMap" then
					waits += 1
				end
			end
			expect.equal(waits, 1) -- once, not every retry
			MatchService.join(w.players[3], "ffa") -- the whole server queued: it would start at once, but no map is free
			expect.equal(w.port, nil)
			expect.deepEqual(codesOf(w, w.players[3]), { "match.joined", "match.waitingMap" }) -- not "starts in 0 seconds"
			w.maps[1].inUse = false -- that match ended
			MatchService.tick(T0 + w.cfg.gatherSeconds + 1)
			expect.truthy(w.port ~= nil)
			expect.equal(#w.port.fighters, 3)
			expect.equal(MatchService.queueCount("ffa"), 0)
			close()
		end
	)

	-- A match ------------------------------------------------------------------------------------------------------------

	t.test("everyone queued: the match starts at once on a free map with the attributes and the first view", function()
		local w = setup(2)
		MatchService.join(w.players[1], "ffa")
		MatchService.join(w.players[2], "ffa")
		local port = w.port
		expect.truthy(port ~= nil)
		expect.equal(string.sub(port.matchId, 1, 6), "match:")
		expect.truthy(port.ffa)
		expect.falsy(port.teams)
		expect.equal(port.cooldownMultiplier(), 1)
		expect.equal(port.phase(), "Positioning")
		expect.truthy(port.arena.zones.Bounds ~= nil)
		expect.equal(port.arena.zones.HalfA, nil)
		expect.equal(w.maps[1].inUse, true)
		expect.equal(w.attached, 1)
		for _, player in w.players do
			expect.equal(player:GetAttribute("SD_MatchId"), port.matchId)
			expect.equal(player:GetAttribute("SD_DuelPhase"), "Positioning")
			expect.equal(player:GetAttribute("SD_MatchPhase"), "Waiting")
			expect.equal(player:GetAttribute("SD_MatchMode"), "ffa")
			expect.equal(player:GetAttribute("SD_Team"), nil)
			local view = lastView(w, player)
			expect.equal(view.matchId, port.matchId)
			expect.equal(view.mode, "ffa")
			expect.equal(view.mapCode, "JAR")
			expect.equal(view.phase, "Positioning")
			expect.equal(view.matchPhase, "Waiting")
			expect.equal(#view.players, 2)
			expect.equal(view.koTarget, w.cfg.Modes.ffa.koTarget)
			expect.equal(view.teamLives, nil)
			expect.equal(view.storm, nil)
			expect.equal(view.you.userId, player.UserId)
			expect.equal(view.you.protectUntil, 0)
		end
		expect.equal(fighterOf(w, 1).side, "A")
		expect.equal(fighterOf(w, 2).side, "A")
		close()
	end)

	t.test(
		"a match that fails to register is undone at once: nobody stays in it, the map is free, a retry works",
		function()
			local w = setup(2)
			w.flags.failRegister = true
			MatchService.join(w.players[1], "ffa")
			MatchService.join(w.players[2], "ffa")
			expect.equal(w.port, nil)
			expect.equal(MatchService.matchCount(), 0)
			expect.falsy(w.maps[1].inUse)
			expect.equal(#w.unregistered, 1)
			for _, player in w.players do
				expect.equal(MatchService.getMatch(player), nil)
				expect.equal(player:GetAttribute("SD_DuelPhase") or "", "")
				expect.equal(MatchService.queued(player), "ffa") -- still queued
			end
			w.flags.failRegister = false
			MatchService.tick(T0 + w.cfg.gatherSeconds)
			expect.truthy(w.port ~= nil)
			expect.equal(w.players[1]:GetAttribute("SD_MatchId"), w.port.matchId)
			close()
		end
	)

	t.test("Waiting -> Countdown -> Active: teleported to the spots and frozen, then the match movement", function()
		local w = setup(2)
		MatchService.join(w.players[1], "ffa")
		MatchService.join(w.players[2], "ffa")
		expect.equal(#w.teleports, 0) -- deferred
		w.flush()
		expect.equal(#w.teleports, 2)
		for i = 1, 2 do
			expect.truthy(inMap(w.roots[i].Position))
			expect.equal(w.humanoids[i].WalkSpeed, 0)
			expect.equal(w.humanoids[i].JumpHeight, 0)
			local placement = w.port.placement(fighterOf(w, i))
			expect.near((placement.Position - w.roots[i].Position).Magnitude, 0, 1e-6)
			expect.near(placement.Position.Y, 3.1, 1e-6) -- pad top 0 + R15 stand height (2 + 1 + 0.1)
		end
		expect.truthy((w.roots[1].Position - w.roots[2].Position).Magnitude > 4)
		expect.equal(w.port.phase(), "Countdown")
		expect.equal(w.players[1]:GetAttribute("SD_DuelPhase"), "Countdown")
		expect.equal(lastView(w, w.players[1]).phase, "Countdown")
		local activeAt = w.clock.now() + w.cfg.countdownSeconds
		MatchService.tick(activeAt - 0.01)
		expect.equal(w.port.phase(), "Countdown")
		MatchService.tick(activeAt)
		expect.equal(w.port.phase(), "Active")
		for i = 1, 2 do
			expect.equal(w.humanoids[i].WalkSpeed, Config.Duel.Rules.Movement.WalkSpeed)
			expect.equal(fighterOf(w, i).nextThrowAt, activeAt)
			expect.truthy(fighterOf(w, i).isAlive())
		end
		expect.equal(lastView(w, w.players[2]).activeStartedAt, activeAt)
		-- A Heartbeat with no timer due steps nothing (no projectile sweep); combat's port.sync still does.
		local syncs = w.syncs
		MatchService.tick(activeAt + 0.5)
		expect.equal(w.syncs, syncs)
		w.port.sync(activeAt + 0.6)
		expect.equal(w.syncs, syncs + 1)
		close()
	end)

	t.test(
		"a hit is a K.O.: frozen and unhittable, back at a respawn spot after respawnSeconds with protection",
		function()
			local w = setup(3)
			for _, player in w.players do
				MatchService.join(player, "ffa")
			end
			w.flush()
			local a = w.clock.now() + w.cfg.countdownSeconds
			MatchService.tick(a)
			local f1, f2 = fighterOf(w, 1), fighterOf(w, 2)
			expect.truthy(w.port.canBeHit(f2, a + 1, f1))
			expect.falsy(w.port.canBeHit(f1, a + 1, f1)) -- never oneself
			local outcome = hit(w, 2, 1, a + 1)
			expect.deepEqual(outcome, { lives = 0, invulnUntil = a + 1, eliminated = true })
			local fellAt = w.roots[2].Position
			expect.equal(w.humanoids[2].WalkSpeed, 0)
			expect.equal(w.humanoids[2].AutoRotate, false)
			expect.falsy(f2.isAlive())
			expect.falsy(w.port.canBeHit(f2, a + 1.5, f1))
			local view = lastView(w, w.players[2])
			expect.falsy(view.you.alive)
			expect.equal(view.you.respawnAt, a + 1 + w.cfg.respawnSeconds)
			local shooter = lastView(w, w.players[1])
			for _, row in shooter.players do
				if row.userId == 1 then
					expect.equal(row.kos, 1)
				end
			end
			-- A second hit on the knocked-out body is refused (the projectile flies on).
			expect.equal(hit(w, 2, 3, a + 2), nil)
			MatchService.tick(a + 1 + w.cfg.respawnSeconds - 0.01)
			expect.near((w.roots[2].Position - fellAt).Magnitude, 0, 1e-6) -- still where it fell
			local back = a + 1 + w.cfg.respawnSeconds
			MatchService.tick(back)
			expect.truthy(f2.isAlive())
			expect.equal(w.pivots[#w.pivots].userId, 2)
			expect.truthy(inMap(w.roots[2].Position))
			expect.equal(w.humanoids[2].WalkSpeed, Config.Duel.Rules.Movement.WalkSpeed)
			expect.equal(w.humanoids[2].AutoRotate, true)
			expect.falsy(w.port.canBeHit(f2, back + w.cfg.spawnProtectSeconds - 0.1, f1))
			expect.truthy(w.port.canBeHit(f2, back + w.cfg.spawnProtectSeconds, f1))
			expect.equal(lastView(w, w.players[2]).you.protectUntil, back + w.cfg.spawnProtectSeconds)
			close()
		end
	)

	t.test("TDM: Red / Blue dealt by turns, sides A / B, no team hits, team lives in each K.O.", function()
		local w = setup(4)
		live(w, "tdm")
		local red, blue = {}, {}
		for _, player in w.players do
			local team = player:GetAttribute("SD_Team")
			local side = fighterOf(w, player.UserId).side
			if team == w.cfg.teamNames[1] then
				table.insert(red, player.UserId)
				expect.equal(side, "A")
			else
				expect.equal(team, w.cfg.teamNames[2])
				table.insert(blue, player.UserId)
				expect.equal(side, "B")
			end
			expect.equal(player:GetAttribute("SD_MatchMode"), "tdm")
		end
		expect.equal(#red, 2)
		expect.equal(#blue, 2)
		expect.truthy(w.port.teams)
		local a = w.clock.now()
		expect.falsy(w.port.canBeHit(fighterOf(w, red[2]), a + 1, fighterOf(w, red[1])))
		expect.equal(hit(w, red[2], red[1], a + 1), nil)
		local outcome = hit(w, blue[1], red[1], a + 1)
		expect.equal(outcome.lives, w.cfg.Modes.tdm.teamLives - 1)
		local view = lastView(w, w.players[1])
		expect.equal(view.teamLives[w.cfg.teamNames[2]], w.cfg.Modes.tdm.teamLives - 1)
		expect.equal(view.storm.startRadius, w.maps[2].startRadius)
		close()
	end)

	t.test(
		"out of bounds: a silent re-pivot in the Countdown, a respawn spot and a toast in Active, never a K.O.",
		function()
			local w = setup(2)
			MatchService.join(w.players[1], "ffa")
			MatchService.join(w.players[2], "ffa")
			w.flush()
			local spot = w.roots[1].Position
			w.roots[1].Position = spot - Vector3.new(0, 40, 0) -- fell under the floor
			w.port.outOfBounds(fighterOf(w, 1))
			expect.near((w.roots[1].Position - spot).Magnitude, 0, 1e-6)
			expect.equal(table.find(codesOf(w, w.players[1]), "match.outOfBounds"), nil)
			local a = w.clock.now() + w.cfg.countdownSeconds
			MatchService.tick(a)
			w.roots[1].Position = Vector3.new(CENTRE.X, -40, 0)
			w.port.outOfBounds(fighterOf(w, 1))
			expect.truthy(inMap(w.roots[1].Position))
			expect.truthy(w.roots[1].Position.Y > 0)
			expect.truthy(table.find(codesOf(w, w.players[1]), "match.outOfBounds") ~= nil)
			expect.truthy(fighterOf(w, 1).isAlive())
			expect.equal(lastView(w, w.players[1]).players[1].knockedOut, 0)
			-- Nowhere near the map (a new character in the lobby): the streamed D5 re-placement, no toast.
			local toasts, pivots, teleports = #codesOf(w, w.players[1]), #w.pivots, #w.teleports
			w.roots[1].Position = LOBBY
			w.port.outOfBounds(fighterOf(w, 1))
			expect.equal(#w.pivots, pivots)
			expect.equal(#w.teleports, teleports + 1)
			expect.truthy(inMap(w.roots[1].Position))
			expect.equal(#codesOf(w, w.players[1]), toasts)
			close()
		end
	)

	t.test("out of bounds with outOfBoundsIsKo: out of the void, then a K.O. (no attacker) that respawns", function()
		local c = baseConfig()
		c.outOfBoundsIsKo = true
		local w = setup(2, c)
		local a = live(w, "ffa")
		w.roots[1].Position = Vector3.new(CENTRE.X, -40, 0) -- fell off the map
		w.port.outOfBounds(fighterOf(w, 1))
		expect.truthy(inMap(w.roots[1].Position))
		expect.truthy(w.roots[1].Position.Y > 0)
		expect.truthy(table.find(codesOf(w, w.players[1]), "match.outOfBoundsKo") ~= nil)
		expect.falsy(fighterOf(w, 1).isAlive())
		local view = lastView(w, w.players[1])
		expect.equal(view.you.alive, false)
		expect.equal(view.players[1].knockedOut + view.players[2].knockedOut, 1)
		expect.equal(view.players[1].kos + view.players[2].kos, 0)
		local back = w.clock.now() + w.cfg.respawnSeconds
		w.clock.set(back)
		MatchService.tick(back)
		expect.truthy(fighterOf(w, 1).isAlive())
		expect.truthy(a > 0)
		close()
	end)

	t.test("a character found alive outside the map (a death, a reset) is placed back, with no K.O.", function()
		local w = setup(2)
		local a = live(w, "ffa")
		local teleports = #w.teleports
		w.roots[2] = { Position = LOBBY, CFrame = CFrame.new(LOBBY), Size = Vector3.new(2, 2, 1) } -- a new character
		MatchService.tick(a + 5)
		expect.equal(#w.teleports, teleports + 1)
		expect.truthy(inMap(w.roots[2].Position))
		expect.truthy(fighterOf(w, 2).isAlive())
		expect.equal(w.humanoids[2].WalkSpeed, Config.Duel.Rules.Movement.WalkSpeed)
		close()
	end)

	t.test("/leave while the first teleport is still streaming: the player still ends up in the lobby, free", function()
		local w = setup(3)
		w.duringTeleport[3] = function()
			MatchService.leave(w.players[3])
		end
		for _, player in w.players do
			MatchService.join(player, "ffa")
		end
		local f3 = fighterOf(w, 3)
		w.flush() -- player 3's teleport lands after the /leave
		expect.falsy(inMap(w.roots[3].Position))
		expect.equal(w.humanoids[3].WalkSpeed, 16)
		expect.equal(w.humanoids[3].JumpHeight, 7.2)
		expect.equal(w.humanoids[3].AutoRotate, true)
		expect.equal(w.players[3]:GetAttribute("SD_MatchId"), "")
		expect.equal(MatchService.getMatch(w.players[3]), nil)
		expect.truthy(table.find(w.releasedFighters, f3) ~= nil)
		expect.equal(w.port.phase(), "Countdown") -- the other two play on
		expect.equal(#lastView(w, w.players[1]).players, 2)
		close()
	end)

	t.test("/leave while a re-placement teleport is streaming: back in the lobby, not frozen", function()
		local w = setup(3)
		local a = live(w, "ffa")
		w.roots[2] = { Position = LOBBY, CFrame = CFrame.new(LOBBY), Size = Vector3.new(2, 2, 1) } -- a new character
		w.duringTeleport[2] = function()
			MatchService.leave(w.players[2])
		end
		MatchService.tick(a + 5)
		expect.falsy(inMap(w.roots[2].Position))
		expect.equal(w.humanoids[2].WalkSpeed, 16)
		expect.equal(w.humanoids[2].JumpHeight, 7.2)
		expect.equal(w.humanoids[2].AutoRotate, true)
		expect.equal(w.players[2]:GetAttribute("SD_MatchId"), "")
		expect.equal(w.port.phase(), "Active")
		close()
	end)

	t.test("TDM storm: a player outside the circle fills the bar (own views) into a storm K.O.", function()
		local cfg = baseConfig()
		cfg.Storm.stormStartSeconds = 10
		cfg.Storm.steps = { { shrinkAt = 10, shrinkSeconds = 10, radiusFraction = 0.1 } }
		cfg.Storm.barFillSeconds = 1
		cfg.Storm.sampleHz = 5
		local w = setup(2, cfg)
		local a = live(w, "tdm")
		-- Before the storm is up nothing is sampled.
		MatchService.tick(a + 5)
		local blueId = if w.players[1]:GetAttribute("SD_Team") == cfg.teamNames[2] then 1 else 2
		local redId = 3 - blueId
		w.roots[blueId].Position = Vector3.new(CENTRE.X, 3, 100) -- far outside the last circle (14.4 studs)
		w.roots[redId].Position = Vector3.new(CENTRE.X, 3, 0) -- in the middle
		local sentBefore = #w.sent
		local now = a + 20
		local koAt: number? = nil
		for _ = 1, 20 do
			MatchService.tick(now)
			if not fighterOf(w, blueId).isAlive() then
				koAt = now
				break
			end
			now += 0.2
		end
		expect.truthy(koAt ~= nil)
		expect.truthy(fighterOf(w, redId).isAlive())
		local bars = {}
		for i = sentBefore + 1, #w.sent do
			local entry = w.sent[i]
			if entry.player == w.players[blueId] then
				table.insert(bars, entry.payload.you.stormBar)
			end
		end
		expect.truthy(#bars >= 3)
		expect.truthy(bars[2] > bars[1] or bars[1] > 0)
		local view = lastView(w, w.players[blueId])
		expect.falsy(view.you.alive)
		expect.equal(view.teamLives[cfg.teamNames[2]], cfg.Modes.tdm.teamLives - 1)
		close()
	end)

	t.test("TDM storm: a dead character (Reset, a fall) is never sampled: no storm K.O., no team life (D5)", function()
		local cfg = baseConfig()
		cfg.Storm.stormStartSeconds = 10
		cfg.Storm.steps = { { shrinkAt = 10, shrinkSeconds = 10, radiusFraction = 0.1 } }
		cfg.Storm.barFillSeconds = 1
		cfg.Storm.sampleHz = 5
		local w = setup(2, cfg)
		local a = live(w, "tdm")
		local blueId = if w.players[1]:GetAttribute("SD_Team") == cfg.teamNames[2] then 1 else 2
		w.roots[blueId].Position = Vector3.new(CENTRE.X, 3, 100) -- the corpse lies far outside the last circle
		w.dead[blueId] = true
		w.roots[3 - blueId].Position = Vector3.new(CENTRE.X, 3, 0) -- the other one stands in the middle
		local now = a + 20
		for _ = 1, 20 do -- 4 s of samples: a live player there would be knocked out after 1 s
			MatchService.tick(now)
			now += 0.2
		end
		local view = lastView(w, w.players[3 - blueId])
		expect.equal(view.teamLives[cfg.teamNames[2]], cfg.Modes.tdm.teamLives)
		for _, row in view.players do
			expect.truthy(row.alive)
			expect.equal(row.knockedOut, 0)
		end
		close()
	end)

	-- The end ------------------------------------------------------------------------------------------------------------

	t.test("the end: toasts, the outcome, MatchEnded; after Result everyone goes back and the match is gone", function()
		local cfg = baseConfig()
		cfg.Modes.ffa.koTarget = 1
		local w = setup(2, cfg)
		local ended: any = nil
		local connection = MatchService.MatchEnded:connect(function(summary: any)
			ended = summary
		end)
		local a = live(w, "ffa")
		local matchId = w.port.matchId
		hit(w, 2, 1, a + 1)
		expect.truthy(table.find(codesOf(w, w.players[1]), "match.youWin") ~= nil)
		local loser = codesOf(w, w.players[2])
		expect.equal(loser[#loser], "match.winner")
		expect.equal(w.notices[#w.notices].args.name, "P1")
		local view = lastView(w, w.players[2])
		expect.equal(view.phase, "Result")
		expect.equal(view.outcome.kind, "win")
		expect.equal(view.outcome.winnerUserId, 1)
		expect.truthy(ended ~= nil)
		expect.equal(ended.matchId, matchId)
		expect.equal(ended.reason, "koTarget")
		connection:disconnect()

		MatchService.tick(a + 1 + cfg.resultSeconds)
		expect.equal(lastView(w, w.players[1]).phase, "Returning")
		expect.equal(w.players[1]:GetAttribute("SD_DuelPhase"), "Returning")
		w.flush() -- the return
		for i = 1, 2 do
			local player = w.players[i]
			expect.falsy(inMap(w.roots[i].Position))
			expect.equal(w.humanoids[i].WalkSpeed, 16)
			expect.equal(w.humanoids[i].JumpHeight, 7.2)
			expect.equal(w.humanoids[i].AutoRotate, true)
			expect.equal(player:GetAttribute("SD_MatchId"), "")
			expect.equal(player:GetAttribute("SD_DuelPhase"), "")
			expect.equal(player:GetAttribute("SD_MatchPhase"), nil)
			expect.equal(player:GetAttribute("SD_MatchMode"), nil)
			expect.equal(MatchService.getMatch(player), nil)
		end
		expect.truthy((w.roots[1].Position - w.roots[2].Position).Magnitude > 1) -- spread at the return points
		expect.deepEqual(w.unregistered, { matchId })
		expect.deepEqual(w.detached, { matchId })
		expect.equal(w.released, 1)
		expect.falsy(w.maps[1].inUse)
		expect.equal(MatchService.matchCount(), 0)
		close()
	end)

	t.test("Result: a character that respawned in the lobby stays there (the return is seconds away)", function()
		local cfg = baseConfig()
		cfg.Modes.ffa.koTarget = 1
		local w = setup(2, cfg)
		local a = live(w, "ffa")
		hit(w, 2, 1, a + 1)
		expect.equal(w.port.phase(), "Result")
		local teleports = #w.teleports
		w.roots[2] = { Position = LOBBY, CFrame = CFrame.new(LOBBY), Size = Vector3.new(2, 2, 1) } -- died, respawned
		MatchService.tick(a + 2)
		expect.equal(#w.teleports, teleports)
		expect.falsy(inMap(w.roots[2].Position))
		MatchService.tick(a + 1 + cfg.resultSeconds)
		w.flush()
		expect.equal(w.players[2]:GetAttribute("SD_MatchId"), "")
		expect.equal(w.humanoids[2].WalkSpeed, 16)
		expect.falsy(inMap(w.roots[2].Position))
		close()
	end)

	t.test("/leave in a match: back to the lobby at once, the others play on; the last one standing wins", function()
		local w = setup(3)
		local a = live(w, "ffa")
		local f3 = fighterOf(w, 3)
		expect.truthy(MatchService.leave(w.players[3]))
		expect.falsy(inMap(w.roots[3].Position))
		expect.equal(w.players[3]:GetAttribute("SD_MatchId"), "")
		expect.equal(w.humanoids[3].WalkSpeed, 16)
		expect.equal(MatchService.getMatch(w.players[3]), nil)
		expect.truthy(table.find(codesOf(w, w.players[3]), "match.youLeft") ~= nil)
		expect.equal(w.port.phase(), "Active")
		expect.falsy(f3.isAlive())
		-- No longer a fighter or caster of the match (lobby practice works again), detached before released.
		expect.deepEqual(w.detachedUsers, { 3 })
		expect.deepEqual(w.releasedFighters, { f3 })
		expect.equal(#w.port.fighters, 2)
		-- The others get a view without the leaver at once (nothing else changed).
		local rows = lastView(w, w.players[1]).players
		expect.equal(#rows, 2)
		for _, row in rows do
			expect.truthy(row.userId ~= 3)
		end
		MatchService.tick(a + 2)
		MatchService.leave(w.players[2])
		local view = lastView(w, w.players[1])
		expect.equal(view.outcome.kind, "win")
		expect.equal(view.outcome.reason, "lastPlayer")
		expect.equal(view.outcome.winnerUserId, 1)
		close()
	end)

	t.test("leaving the game mid-match: the fighter is released and the others get a view without them", function()
		local w = setup(3)
		live(w, "ffa")
		local f3 = fighterOf(w, 3)
		w.players[3].Parent = nil
		MatchService.playerRemoving(w.players[3])
		expect.deepEqual(w.detachedUsers, { 3 })
		expect.deepEqual(w.releasedFighters, { f3 })
		expect.equal(#lastView(w, w.players[1]).players, 2)
		expect.equal(w.port.phase(), "Active")
		close()
	end)

	t.test("a player who never arrives is dropped at the Countdown; too few present cancels the match", function()
		local w = setup(3)
		w.failTeleport[3] = true
		for _, player in w.players do
			MatchService.join(player, "ffa")
		end
		w.flush() -- player 3's teleport retries until the wait is over
		MatchService.tick(w.clock.now())
		expect.equal(w.port.phase(), "Countdown")
		expect.equal(w.players[3]:GetAttribute("SD_MatchId"), "")
		expect.equal(MatchService.getMatch(w.players[3]), nil)
		expect.truthy(table.find(codesOf(w, w.players[3]), "match.notArrived") ~= nil)
		expect.equal(w.players[1]:GetAttribute("SD_DuelPhase"), "Countdown")
		expect.deepEqual(w.detachedUsers, { 3 }) -- released like a leaver
		expect.equal(#w.releasedFighters, 1)
		expect.equal(#w.port.fighters, 2)
		close()

		local v = setup(2)
		v.failTeleport[2] = true
		MatchService.join(v.players[1], "ffa")
		MatchService.join(v.players[2], "ffa")
		v.flush()
		MatchService.tick(v.clock.now())
		expect.equal(lastView(v, v.players[1]).outcome.kind, "cancelled")
		expect.truthy(table.find(codesOf(v, v.players[1]), "match.cancelled") ~= nil)
		close()
	end)

	t.test("shutdown voids every match at once and the players go back", function()
		local w = setup(2)
		live(w, "ffa")
		MatchService.voidAll("shutdown")
		expect.truthy(table.find(codesOf(w, w.players[1]), "match.void") ~= nil)
		expect.equal(lastView(w, w.players[1]).phase, "Returning")
		w.flush()
		expect.equal(w.players[1]:GetAttribute("SD_MatchId"), "")
		expect.equal(MatchService.matchCount(), 0)
		expect.equal(w.released, 1)
		close()

		-- A void after an error does not claim the server is shutting down.
		local v = setup(2)
		live(v, "ffa")
		MatchService.voidAll("error")
		expect.truthy(table.find(codesOf(v, v.players[1]), "match.voidError") ~= nil)
		expect.equal(table.find(codesOf(v, v.players[1]), "match.void"), nil)
		close()
	end)

	t.test("RestartScheduled: the queues clear; a match is voided only when it can't end before the restart", function()
		local w = setup(3)
		MatchService.join(w.players[1], "ffa")
		MatchService.join(w.players[2], "ffa")
		MatchService.tick(T0 + w.cfg.gatherSeconds)
		expect.truthy(w.port ~= nil)
		w.clock.set(T0 + w.cfg.gatherSeconds)
		w.flush()
		local a = w.clock.now() + w.cfg.countdownSeconds
		w.clock.set(a)
		MatchService.tick(a)
		expect.equal(w.port.phase(), "Active")
		MatchService.join(w.players[3], "tdm")
		w.clock.set(a + 1)
		MatchService.onRestartScheduled()
		expect.equal(MatchService.queueCount("tdm"), 0)
		local codes = codesOf(w, w.players[3])
		expect.equal(codes[#codes], "match.refused.closing")
		-- The longest it may still take: what is left of Active, then overtime and Result.
		local left = w.cfg.Modes.ffa.matchSeconds - 1
		expect.near(w.asked :: number, left + w.cfg.overtimeMaxSeconds + w.cfg.resultSeconds, 1e-6)
		expect.equal(w.port.phase(), "Active") -- it can finish
		w.flags.canFinish = false
		MatchService.onRestartScheduled()
		expect.equal(lastView(w, w.players[1]).outcome.kind, "void")
		expect.truthy(table.find(codesOf(w, w.players[1]), "match.void") ~= nil)
		close()
	end)

	t.test("TDM at 0 team lives: the K.O.'d player is out (stays frozen), a wiped team loses", function()
		local cfg = baseConfig()
		cfg.Modes.tdm.teamLives = 0
		local w = setup(2, cfg)
		local a = live(w, "tdm")
		local blueId = if w.players[1]:GetAttribute("SD_Team") == cfg.teamNames[2] then 1 else 2
		local redId = 3 - blueId
		local outcome = hit(w, blueId, redId, a + 1)
		expect.deepEqual(outcome, { lives = 0, invulnUntil = a + 1, eliminated = true })
		expect.truthy(table.find(codesOf(w, w.players[blueId]), "match.outNoLives") ~= nil)
		local view = lastView(w, w.players[blueId])
		expect.truthy(view.you.out)
		expect.equal(view.you.respawnAt, nil)
		expect.equal(view.outcome.winnerTeam, cfg.teamNames[1])
		local winners = w.notices[#w.notices]
		expect.equal(winners.code, "match.teamWins")
		expect.equal(winners.args.team, "Red")
		MatchService.tick(a + 1 + cfg.respawnSeconds)
		expect.equal(w.humanoids[blueId].WalkSpeed, 0) -- out: no respawn
		close()
	end)

	-- Runs last: every code the cases above saw (and every other one MatchService sends) has its Strings text.
	t.test("every toast MatchService sends has a match.* text with its placeholders", function()
		local Strings = t.requireShared("Strings")
		local all = {
			"match.joined",
			"match.left",
			"match.leftForDuel",
			"match.startingIn",
			"match.waitingPlayers",
			"match.waitingMap",
			"match.youLeft",
			"match.notQueued",
			"match.notArrived",
			"match.outOfBounds",
			"match.outOfBoundsKo",
			"match.outNoLives",
			"match.youWin",
			"match.winner",
			"match.teamWins",
			"match.draw",
			"match.cancelled",
			"match.void",
			"match.voidError",
			"match.refused.closing",
			"match.refused.alreadyQueued",
			"match.refused.inMatch",
			"match.refused.duelQueue",
			"match.refused.practice",
			"match.refused.noMaps",
		}
		for code in seenCodes do
			if not table.find(all, code) then
				table.insert(all, code)
			end
		end
		expect.truthy(seenCodes["match.joined"])
		for _, code in all do
			if Strings.resolve(code) == nil then
				error(`{code} has no Strings text`)
			end
		end
		expect.truthy(string.find(Strings.match.joined, "{count}/{max}", 1, true) ~= nil)
		expect.truthy(string.find(Strings.match.startingIn, "{seconds}", 1, true) ~= nil)
		expect.truthy(string.find(Strings.match.winner, "{name}", 1, true) ~= nil)
		expect.truthy(string.find(Strings.match.teamWins, "{team}", 1, true) ~= nil)
		for _, team in Config.Match.teamNames do
			expect.truthy(Strings.resolve(`match.team.{string.lower(team)}`) ~= nil)
		end
		for modeId in Config.Match.Modes do
			expect.truthy(Strings.resolve(`match.mode.{modeId}`) ~= nil)
		end
	end)
end
