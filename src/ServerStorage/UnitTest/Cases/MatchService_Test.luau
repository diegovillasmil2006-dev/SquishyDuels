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
--   * power-ups v1.1 (2026-10-16): the views carry every pad ({name, readyAt}, 0 = ready) and you.buffs; a standing
--     player on a ready pad takes it in Active only (never in the Countdown, too high above it or knocked out), with the
--     match.powerUp.<kind> toast, the buff in their view and the pad's readyAt + padRefillSeconds in everyone's; the
--     nearer player takes a shared pad and nobody takes two in one sample; speed / super jump change the movement while
--     they live (not while rooted) and give it back when they end; the port's cooldownMultiplier(fighter),
--     throwSpeedMultiplier, dashCooldownFree and movement answer for the buffed fighter only; ult charge reaches
--     AbilityService; a shield makes one hit a blocked outcome; a TDM team life adds a life or brings back the
--     teammate out longest; every kind has its toast and every timed one its readout name.
--     Review fixes (2026-10-16): the rapid throw's multiplier gives the shortest cooldown (CooldownClamp.Min, never
--     below); a pad stays ready when the projectile sweep K.O.s its taker in that step, or the time-up ends the match
--     there; a speed boost that ends in Result gives the plain movement back.
--   * match HUD M1 (2026-10-16): each K.O. is one HUD event {seq, kind "ko", at, victim, by, cause, final, streak,
--     livesLeft} in the next view sent to everyone (seq 1, 2, ...; never twice); a storm or out-of-bounds K.O. has no
--     `by`; a view sent to one player (the storm bar) has no events; players carry respawnAt, out, protectUntil, streak
--     and bestStreak (a K.O. resets the victim's streak); livesLeft = the TDM team lives after it (0 when out); the
--     K.O. that wins by koTarget (an ultimate's too), wipes a team or wins overtime is final and is outcome.finalKo in
--     the same view (and every later one); a time-up or a wipe by a leave has none; a flush nested in stepMatch is a
--     batch of its own (only the deciding K.O. is final); outcome.standings = MatchRules order without a leaver, the
--     same list in every later view.
--   * match HUD M2 (2026-10-16): with Config.Match.Rewards off nothing is paid and outcome.mine is nil; on, the end
--     pays (through the fake EconomyService / GripService, with the test's own pay rules as deps.rewards.config) FFA
--     1st a duel win (+1 streak), the others a duel loss, the TDM winning team a win and the losers a loss, a draw a
--     duel draw (streak 0), each only with 3 own throws and the min Active time (else 0; a win still +1 streak, a loss
--     0); the same squeezes as Grip for the paid players; mine only in the receiver's view, repeated later, paid
--     once; SD_WinStreak follows every grant and refreshWinStreak sets it from the saved streak; leaving a live match
--     (Countdown, Active: /leave or the game) resets the streak with nothing paid, leaving while Waiting or in Result
--     does not; cancelled / void pay and touch nothing. Review fixes (2026-10-16): a leave that the step it starts
--     ends first (MatchRules took the end) is no leave: that player is paid as present and keeps the streak their
--     result gives; a grant that comes back alreadyGranted pays no Grip and no mine and writes no SD_WinStreak.

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
	onSync: ((now: number) -> ())?, -- runs once inside the next syncTo (a projectile the sweep brings in)
	charged: { { userId: number, fraction: number } }, -- power-ups v1.1: AbilityService.addChargeFraction calls
	-- Match HUD M2: the pay fakes (setup's withRewards): EconomyService.grantMatchResult / GripService.addFromMatch
	-- calls and each user's saved win streak.
	grants: { { userId: number, matchId: string, pay: any } },
	grips: { { userId: number, squeezes: number } },
	streaks: { [number]: number },
	grantedBefore: { [number]: boolean }, -- users whose grant comes back alreadyGranted (EconomyService's once rule)
	payRules: any, -- deps.rewards.config: this world's copy of PAY_RULES (a case may tune it)
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
	-- Match HUD M2 (review fix): the pay rules of every pay case (the duel's numbers spelled out), passed to
	-- MatchService as deps.rewards.config, so a tuned or stale Config.Economy changes no expectation.
	local PAY_RULES = {
		Economy = {
			DuelRewards = {
				win = 600,
				loss = 180,
				draw = 300,
				minOwnThrows = 3,
				winMinActiveSeconds = 20,
				lossMinActiveSeconds = 45,
			},
		},
	}

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
		cfg.Rewards = { enabled = false } -- Match HUD M2 (it replaced rewardCoins = 0): off unless a case turns it on
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
		-- Power-ups v1.1 (2026-10-16): the pickup reach and the timed power-ups' numbers.
		local pu = cfg.PowerUps
		pu.padRefillSeconds = 20
		pu.pickupRadiusStuds = 4
		pu.pickupHeightStuds = 6
		pu.kinds.shield.seconds = 6
		pu.kinds.speed.seconds = 6
		pu.kinds.speed.walkMultiplier = 1.6
		pu.kinds.superJump.seconds = 6
		pu.kinds.superJump.jumpMultiplier = 2
		pu.kinds.rapidThrow.seconds = 6
		pu.kinds.rapidThrow.cooldownMultiplier = 0
		pu.kinds.throwBoost.seconds = 6
		pu.kinds.throwBoost.speedMultiplier = 1.4
		pu.kinds.dashBoost.seconds = 5
		pu.kinds.ultCharge.ultFraction = 0.5
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

	-- A world of `count` players in the server, nobody queued yet. Match HUD M2: `withRewards` wires fake pay
	-- collaborators (a grant pays squeezes × 10 Coins and moves the saved streak; Grip pays squeezes × 10).
	local function setup(count: number, cfg: any?, withRewards: boolean?): World
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
			onSync = nil,
			charged = {},
			grants = {},
			grips = {},
			streaks = {},
			grantedBefore = {},
			payRules = deepCopy(PAY_RULES),
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
				syncTo = function(now: number)
					w.syncs += 1
					local hook = w.onSync
					if hook then
						w.onSync = nil
						hook(now)
					end
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
				addCharge = function(userId: number, fraction: number): boolean
					table.insert(w.charged, { userId = userId, fraction = fraction })
					return true
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
			rewards = if withRewards
				then {
					grant = function(ref: any, matchId: string, pay: any): any
						table.insert(w.grants, { userId = ref.UserId, matchId = matchId, pay = pay })
						local before = w.streaks[ref.UserId] or 0
						if w.grantedBefore[ref.UserId] then -- EconomyService's exactly-once: nothing happens
							return {
								coins = 0,
								recorded = false,
								alreadyGranted = true,
								streakBefore = before,
								streakAfter = before,
							}
						end
						local after = if pay.streakUp then before + 1 else 0
						w.streaks[ref.UserId] = after
						return {
							coins = pay.squeezes * 10,
							recorded = true,
							alreadyGranted = false,
							streakBefore = before,
							streakAfter = after,
						}
					end,
					addGrip = function(ref: any, squeezes: number): number
						table.insert(w.grips, { userId = ref.UserId, squeezes = squeezes })
						return squeezes * 10
					end,
					winStreak = function(ref: any): number
						return w.streaks[ref.UserId] or 0
					end,
					config = w.payRules,
				}
				else nil,
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

	-- Power-ups v1.1 (2026-10-16) ---------------------------------------------------------------------------------------

	-- One power-up pad on the map (40 studs from the centre on X and Z: no spawn spot or test position is near it), set
	-- before the match starts; its top is 0.5, so a standing R15 root is at 0.5 + 3.1.
	local PAD_AT = Vector3.new(CENTRE.X + 40, 0.25, 40)
	local PAD_NAME = "JAR_PowerUp_Pad_01"
	local function withPad(w: World, mapIndex: number?)
		w.maps[mapIndex or 1].powerUps = { { name = PAD_NAME, position = PAD_AT, top = 0.5 } }
	end
	local function onPad(w: World, userId: number, above: number?)
		w.roots[userId].Position = Vector3.new(PAD_AT.X + 1, 0.5 + 3.1 + (above or 0), PAD_AT.Z - 1)
	end
	local function offPad(w: World, userId: number)
		w.roots[userId].Position = Vector3.new(CENTRE.X - 30, 3.1, -30)
	end
	-- A Config.Match copy whose roll can only pick `kind`.
	local function onlyKind(kind: string, cfg: any?): any
		local c = cfg or baseConfig()
		c.PowerUps.order = { kind }
		return c
	end
	local function hasCode(w: World, player: any, code: string): boolean
		return table.find(codesOf(w, player), code) ~= nil
	end

	t.test("pads: a standing player on a ready pad takes it in Active only; the toast, the buff, the refill", function()
		local cfg = onlyKind("shield")
		local w = setup(3, cfg)
		withPad(w)
		for _, player in w.players do
			MatchService.join(player, "ffa")
		end
		local first = lastView(w, w.players[1])
		expect.deepEqual(first.pads, { { name = PAD_NAME, readyAt = 0 } }) -- every pad, ready
		expect.deepEqual(first.you.buffs, {})
		w.flush()
		expect.equal(w.port.phase(), "Countdown")
		onPad(w, 1)
		MatchService.tick(w.clock.now()) -- the Countdown: the pads are idle
		expect.falsy(hasCode(w, w.players[1], "match.powerUp.shield"))
		local a = w.clock.now() + cfg.countdownSeconds
		w.clock.set(a)
		MatchService.tick(a)
		expect.equal(w.port.phase(), "Active")
		local takenAt = a + 0.01
		MatchService.tick(takenAt)
		expect.truthy(hasCode(w, w.players[1], "match.powerUp.shield"))
		expect.equal(w.notices[#w.notices].kind, "success")
		local view = lastView(w, w.players[1])
		expect.equal(view.you.buffs.shield, takenAt + cfg.PowerUps.kinds.shield.seconds)
		expect.equal(view.pads[1].readyAt, takenAt + cfg.PowerUps.padRefillSeconds)
		expect.equal(lastView(w, w.players[2]).pads[1].readyAt, takenAt + cfg.PowerUps.padRefillSeconds) -- everyone
		expect.deepEqual(lastView(w, w.players[2]).you.buffs, {})
		-- Not ready: the next player on it gets nothing until it refills; then they do.
		offPad(w, 1)
		onPad(w, 2)
		MatchService.tick(takenAt + 1)
		expect.falsy(hasCode(w, w.players[2], "match.powerUp.shield"))
		MatchService.tick(takenAt + cfg.PowerUps.padRefillSeconds)
		expect.truthy(hasCode(w, w.players[2], "match.powerUp.shield"))
		-- Too high above it (a jump), or knocked out on it: no pickup.
		local again = takenAt + 2 * cfg.PowerUps.padRefillSeconds
		offPad(w, 2)
		onPad(w, 3, cfg.PowerUps.pickupHeightStuds + 1)
		MatchService.tick(again)
		expect.falsy(hasCode(w, w.players[3], "match.powerUp.shield"))
		hit(w, 3, 1, again + 0.1)
		expect.falsy(fighterOf(w, 3).isAlive())
		onPad(w, 3)
		MatchService.tick(again + 0.5)
		expect.falsy(hasCode(w, w.players[3], "match.powerUp.shield"))
		expect.equal(lastView(w, w.players[1]).pads[1].readyAt, again) -- still ready since player 2's pickup
		close()
	end)

	t.test("pads: two players on one pad: the nearer one takes it, and one pickup per player per sample", function()
		local cfg = onlyKind("speed")
		local w = setup(3, cfg)
		w.maps[1].powerUps = {
			{ name = "JAR_PowerUp_Pad_01", position = PAD_AT, top = 0.5 },
			{ name = "JAR_PowerUp_Pad_02", position = PAD_AT + Vector3.new(4, 0, 0), top = 0.5 },
		}
		local a = live(w, "ffa")
		-- Player 1 reaches both pads (1.5 and 2.5 studs); player 2 only the first (0.5 studs; 4.5 from the second).
		w.roots[1].Position = Vector3.new(PAD_AT.X + 1.5, 3.6, PAD_AT.Z)
		w.roots[2].Position = Vector3.new(PAD_AT.X - 0.5, 3.6, PAD_AT.Z)
		MatchService.tick(a + 0.01)
		-- The first pad went to the nearer player 2 (not to player 1, first in the list), the second to player 1.
		expect.truthy(hasCode(w, w.players[2], "match.powerUp.speed"))
		local count = 0
		for _, code in codesOf(w, w.players[1]) do
			if code == "match.powerUp.speed" then
				count += 1
			end
		end
		expect.equal(count, 1) -- one pickup per player per sample, though both pads were in reach
		local pads = lastView(w, w.players[1]).pads
		expect.truthy(pads[1].readyAt > 0 and pads[2].readyAt > 0)
		close()
	end)

	t.test(
		"pads review fix: the sweep's K.O. of the taker, or the time-up, lands first: the pad stays ready, no pickup",
		function()
			local w = setup(2, onlyKind("speed"))
			withPad(w)
			local a = live(w, "ffa")
			onPad(w, 1)
			-- A projectile the sample's sweep brings in hits player 1 on the pad (CombatService.syncTo -> applyHits).
			w.onSync = function(now: number)
				hit(w, 1, 2, now)
			end
			MatchService.tick(a + 0.01)
			expect.falsy(fighterOf(w, 1).isAlive())
			expect.falsy(hasCode(w, w.players[1], "match.powerUp.speed"))
			expect.equal(lastView(w, w.players[2]).pads[1].readyAt, 0) -- not used up
			expect.equal(w.humanoids[1].WalkSpeed, 0) -- frozen where it fell, no boost
			close()

			-- The time-up at the sample: player 1 leads, so the match ends there and nobody takes the pad.
			local v = setup(2, onlyKind("speed"))
			withPad(v)
			local b = live(v, "ffa")
			hit(v, 2, 1, b + 1) -- player 1 leads 1-0
			MatchService.tick(b + 1 + v.cfg.respawnSeconds) -- player 2 is back
			onPad(v, 1)
			MatchService.tick(b + v.cfg.Modes.ffa.matchSeconds)
			expect.equal(v.port.phase(), "Result")
			expect.falsy(hasCode(v, v.players[1], "match.powerUp.speed"))
			expect.equal(lastView(v, v.players[1]).pads[1].readyAt, 0)
			expect.deepEqual(lastView(v, v.players[1]).you.buffs, {})
			close()
		end
	)

	t.test("Result review fix: a speed boost that ends in Result gives the plain movement back", function()
		local MOVEMENT = Config.Duel.Rules.Movement
		local cfg = onlyKind("speed")
		cfg.Modes.ffa.koTarget = 1
		local w = setup(2, cfg)
		withPad(w)
		local a = live(w, "ffa")
		onPad(w, 1)
		local takenAt = a + 0.01
		MatchService.tick(takenAt)
		expect.near(w.humanoids[1].WalkSpeed, MOVEMENT.WalkSpeed * cfg.PowerUps.kinds.speed.walkMultiplier, 1e-9)
		hit(w, 2, 1, a + 1) -- the winning K.O.: Result (players still walk there)
		expect.equal(w.port.phase(), "Result")
		local ends = takenAt + cfg.PowerUps.kinds.speed.seconds
		expect.truthy(ends < a + 1 + cfg.resultSeconds) -- it ends inside Result
		MatchService.tick(ends)
		expect.equal(w.humanoids[1].WalkSpeed, MOVEMENT.WalkSpeed)
		expect.equal(lastView(w, w.players[1]).you.buffs.speed, nil)
		expect.equal(w.humanoids[2].WalkSpeed, 0) -- the K.O.'d body stays frozen
		close()
	end)

	t.test("speed and super jump: the movement × their multipliers while they live, back when they end", function()
		local MOVEMENT = Config.Duel.Rules.Movement
		local cfg = onlyKind("speed")
		local w = setup(2, cfg)
		withPad(w)
		local a = live(w, "ffa")
		onPad(w, 1)
		local takenAt = a + 0.01
		MatchService.tick(takenAt)
		local fast = MOVEMENT.WalkSpeed * cfg.PowerUps.kinds.speed.walkMultiplier
		expect.near(w.humanoids[1].WalkSpeed, fast, 1e-9)
		expect.equal(w.humanoids[2].WalkSpeed, MOVEMENT.WalkSpeed)
		local walk, jump = w.port.movement(fighterOf(w, 1))
		expect.near(walk, fast, 1e-9)
		expect.equal(jump, MOVEMENT.JumpHeight)
		expect.equal((w.port.movement(fighterOf(w, 2))), MOVEMENT.WalkSpeed)
		local ends = takenAt + cfg.PowerUps.kinds.speed.seconds
		MatchService.tick(ends - 0.05)
		expect.near(w.humanoids[1].WalkSpeed, fast, 1e-9)
		MatchService.tick(ends)
		expect.equal(w.humanoids[1].WalkSpeed, MOVEMENT.WalkSpeed)
		expect.equal(lastView(w, w.players[1]).you.buffs.speed, nil) -- its own view drops it
		w.clock.set(ends)
		expect.equal((w.port.movement(fighterOf(w, 1))), MOVEMENT.WalkSpeed)
		close()

		-- Super jump; and a player rooted by an ultimate keeps the root (the port still reports the buffed movement).
		local cfg2 = onlyKind("superJump")
		local v = setup(2, cfg2)
		withPad(v)
		local b = live(v, "ffa")
		onPad(v, 1)
		MatchService.tick(b + 0.01)
		expect.near(v.humanoids[1].JumpHeight, MOVEMENT.JumpHeight * cfg2.PowerUps.kinds.superJump.jumpMultiplier, 1e-9)
		expect.equal(v.humanoids[1].WalkSpeed, MOVEMENT.WalkSpeed)
		local rooted = fighterOf(v, 2)
		rooted.rootedUntil = b + 100
		v.humanoids[2].WalkSpeed, v.humanoids[2].JumpHeight = 0, 0 -- AbilityService's root
		offPad(v, 1)
		onPad(v, 2)
		MatchService.tick(b + 0.01 + cfg2.PowerUps.padRefillSeconds)
		expect.truthy(hasCode(v, v.players[2], "match.powerUp.superJump"))
		expect.equal(v.humanoids[2].JumpHeight, 0)
		v.clock.set(b + 0.02 + cfg2.PowerUps.padRefillSeconds)
		local _, rootedJump = v.port.movement(rooted)
		expect.near(rootedJump, MOVEMENT.JumpHeight * cfg2.PowerUps.kinds.superJump.jumpMultiplier, 1e-9)
		-- Gone from the match (AbilityService's detach un-roots them in the lobby): the plain movement, no boost.
		MatchService.leave(v.players[2])
		expect.equal(select(2, v.port.movement(rooted)), MOVEMENT.JumpHeight)
		close()
	end)

	t.test(
		"rapid throw, throw boost, dash boost: the port answers for the buffed fighter only, while it lives",
		function()
			local cfg = onlyKind("rapidThrow")
			cfg.PowerUps.padRefillSeconds = 1
			local w = setup(2, cfg)
			withPad(w)
			local a = live(w, "ffa")
			local f1, f2 = fighterOf(w, 1), fighterOf(w, 2)
			onPad(w, 1)
			MatchService.tick(a + 0.01)
			-- Review fix: "no wait" is the shortest cooldown, so the multiplier is Min / the thrower's clamped catalog
			-- cooldown (ThrowRules clamps first). The fake fighter has no throw stats: its squishy's (the starter's).
			local Catalog = t.requireShared("Catalog")
			local clamp = Config.Duel.Rules.CooldownClamp
			local starter = Catalog.get(Catalog.starterId()).throw.cooldown
			expect.near(w.port.cooldownMultiplier(f1), clamp.Min / math.clamp(starter, clamp.Min, clamp.Max), 1e-9)
			f1.throw = { cooldown = 1.5 }
			expect.near(w.port.cooldownMultiplier(f1), clamp.Min / 1.5, 1e-9)
			cfg.PowerUps.kinds.rapidThrow.cooldownMultiplier = 0.8 -- a gentler one (0.8 × 1.5 s > Min) stays as it is
			expect.near(w.port.cooldownMultiplier(f1), 0.8, 1e-9)
			cfg.PowerUps.kinds.rapidThrow.cooldownMultiplier = 0
			expect.equal(w.port.cooldownMultiplier(f2), 1)
			expect.equal(w.port.cooldownMultiplier(), 1)
			expect.equal(w.port.throwSpeedMultiplier(f1), 1)
			expect.falsy(w.port.dashCooldownFree(f1))
			cfg.PowerUps.order = { "throwBoost" }
			MatchService.tick(a + 1.01)
			expect.equal(w.port.throwSpeedMultiplier(f1), cfg.PowerUps.kinds.throwBoost.speedMultiplier)
			expect.equal(w.port.throwSpeedMultiplier(f2), 1)
			cfg.PowerUps.order = { "dashBoost" }
			MatchService.tick(a + 2.01)
			expect.truthy(w.port.dashCooldownFree(f1))
			expect.falsy(w.port.dashCooldownFree(f2))
			-- They end with their seconds (the clock is the callbacks' time).
			w.clock.set(a + 0.01 + cfg.PowerUps.kinds.rapidThrow.seconds)
			expect.equal(w.port.cooldownMultiplier(f1), 1)
			w.clock.set(a + 2.01 + cfg.PowerUps.kinds.dashBoost.seconds)
			expect.falsy(w.port.dashCooldownFree(f1))
			expect.equal(w.port.throwSpeedMultiplier(f1), 1)
			close()
		end
	)

	t.test(
		"ult charge goes to AbilityService; a shield blocks one hit (a blocked outcome), the next one K.O.s",
		function()
			local cfg = onlyKind("ultCharge")
			local w = setup(2, cfg)
			withPad(w)
			local a = live(w, "ffa")
			onPad(w, 1)
			MatchService.tick(a + 0.01)
			expect.deepEqual(w.charged, { { userId = 1, fraction = cfg.PowerUps.kinds.ultCharge.ultFraction } })
			expect.deepEqual(lastView(w, w.players[1]).you.buffs, {}) -- instant: no buff
			close()

			local v = setup(2, onlyKind("shield"))
			withPad(v)
			local b = live(v, "ffa")
			onPad(v, 2)
			MatchService.tick(b + 0.01)
			expect.truthy(lastView(v, v.players[2]).you.buffs.shield ~= nil)
			local blocked = hit(v, 2, 1, b + 1)
			expect.deepEqual(blocked, { lives = 0, invulnUntil = b + 1, eliminated = false, blocked = true })
			expect.truthy(fighterOf(v, 2).isAlive())
			expect.equal(lastView(v, v.players[2]).you.buffs.shield, nil) -- used up
			local ko = hit(v, 2, 1, b + 1.5)
			expect.equal(ko.eliminated, true)
			expect.equal(ko.blocked, nil)
			expect.falsy(fighterOf(v, 2).isAlive())
			close()
		end
	)

	t.test("TDM team life: +1 life for the picker's team; at 0 lives the teammate out longest comes back", function()
		local cfg = onlyKind("teamLife")
		local w = setup(2, cfg)
		withPad(w, 2)
		local a = live(w, "tdm")
		local team = w.players[1]:GetAttribute("SD_Team")
		onPad(w, 1)
		MatchService.tick(a + 0.01)
		expect.truthy(hasCode(w, w.players[1], "match.powerUp.teamLife"))
		expect.equal(lastView(w, w.players[2]).teamLives[team], cfg.Modes.tdm.teamLives + 1)
		close()

		local c2 = onlyKind("teamLife")
		c2.Modes.tdm.teamLives = 0
		local v = setup(4, c2)
		withPad(v, 2)
		local b = live(v, "tdm")
		local red, blue = {}, {}
		for _, player in v.players do
			table.insert(if player:GetAttribute("SD_Team") == c2.teamNames[1] then red else blue, player.UserId)
		end
		hit(v, red[1], blue[1], b + 1) -- no team life: out
		expect.truthy(lastView(v, v.players[red[1]]).you.out)
		onPad(v, red[2])
		MatchService.tick(b + 1.5)
		local back = lastView(v, v.players[red[1]])
		expect.truthy(back.you.alive)
		expect.falsy(back.you.out)
		expect.equal(back.teamLives[c2.teamNames[1]], 0) -- the new life was spent on the revive
		expect.truthy(fighterOf(v, red[1]).isAlive())
		expect.equal(v.humanoids[red[1]].WalkSpeed, Config.Duel.Rules.Movement.WalkSpeed)
		expect.truthy(inMap(v.roots[red[1]].Position))
		close()
	end)

	t.test("every power-up kind has its pickup toast; every timed one its readout name", function()
		local Strings = t.requireShared("Strings")
		for _, kind in Config.Match.PowerUps.order do
			if Strings.resolve(`match.powerUp.{kind}`) == nil then
				error(`match.powerUp.{kind} has no Strings text`)
			end
			if Config.Match.PowerUps.kinds[kind].seconds ~= nil then
				expect.truthy(Strings.resolve(`match.readout.powerUpName.{kind}`) ~= nil)
			end
		end
		local readout = Strings.match.readout.powerUp
		expect.truthy(string.find(readout, "{name}", 1, true) ~= nil)
		expect.truthy(string.find(readout, "{seconds}", 1, true) ~= nil)
	end)

	-- Match HUD M1 (2026-10-16) -----------------------------------------------------------------------------------------

	-- Every MatchState payload `player` got, oldest first.
	local function viewsOf(w: World, player: any): { any }
		local out = {}
		for _, entry in w.sent do
			if entry.name == "MatchState" and entry.player == player then
				table.insert(out, entry.payload)
			end
		end
		return out
	end

	-- Every HUD event `player` got, in the order they came.
	local function eventsOf(w: World, player: any): { any }
		local out = {}
		for _, view in viewsOf(w, player) do
			for _, event in view.events or {} do
				table.insert(out, event)
			end
		end
		return out
	end

	local function rowOf(view: any, userId: number): any
		for _, row in view.players do
			if row.userId == userId then
				return row
			end
		end
		return nil
	end

	-- The userIds of each TDM team (Red, Blue).
	local function teamsOf(w: World): ({ number }, { number })
		local red, blue = {}, {}
		for _, player in w.players do
			table.insert(if player:GetAttribute("SD_Team") == w.cfg.teamNames[1] then red else blue, player.UserId)
		end
		return red, blue
	end

	t.test("match HUD M1: a hit K.O. is one HUD event in everyone's next view; seq rises by 1; never twice", function()
		local w = setup(3)
		local a = live(w, "ffa")
		for _, player in w.players do
			expect.deepEqual(lastView(w, player).events, {}) -- a view sent to everyone always has the list
		end
		hit(w, 2, 1, a + 1)
		local first = { seq = 1, kind = "ko", at = a + 1, victim = 2, by = 1, cause = "hit", final = false, streak = 1 }
		for _, player in w.players do
			expect.deepEqual(lastView(w, player).events, { first })
		end
		hit(w, 3, 1, a + 1.5)
		local second =
			{ seq = 2, kind = "ko", at = a + 1.5, victim = 3, by = 1, cause = "hit", final = false, streak = 2 }
		for _, player in w.players do
			expect.deepEqual(lastView(w, player).events, { second })
			expect.deepEqual(eventsOf(w, player), { first, second })
		end
		close()
	end)

	t.test(
		"match HUD M1: players carry respawnAt, out, protectUntil, streak and bestStreak; a K.O. resets the victim's streak",
		function()
			local w = setup(3)
			local a = live(w, "ffa")
			for _, row in lastView(w, w.players[3]).players do
				expect.equal(row.respawnAt, nil)
				expect.equal(row.out, false)
				expect.equal(row.protectUntil, 0)
				expect.equal(row.streak, 0)
				expect.equal(row.bestStreak, 0)
			end
			hit(w, 2, 1, a + 1)
			hit(w, 3, 1, a + 1.2)
			local view = lastView(w, w.players[3])
			expect.equal(rowOf(view, 2).respawnAt, a + 1 + w.cfg.respawnSeconds)
			expect.equal(rowOf(view, 3).respawnAt, a + 1.2 + w.cfg.respawnSeconds)
			expect.equal(rowOf(view, 1).streak, 2)
			expect.equal(rowOf(view, 1).bestStreak, 2)
			local back = a + 1 + w.cfg.respawnSeconds
			MatchService.tick(back)
			view = lastView(w, w.players[3])
			expect.equal(rowOf(view, 2).respawnAt, nil)
			expect.equal(rowOf(view, 2).protectUntil, back + w.cfg.spawnProtectSeconds)
			-- Player 2, back, knocks player 1 out: 1's streak is 0 (the best stays 2), 2's is 1.
			hit(w, 1, 2, back + w.cfg.spawnProtectSeconds + 0.5)
			view = lastView(w, w.players[3])
			expect.equal(rowOf(view, 1).streak, 0)
			expect.equal(rowOf(view, 1).bestStreak, 2)
			expect.equal(rowOf(view, 2).streak, 1)
			expect.equal(rowOf(view, 2).bestStreak, 1)
			expect.equal(view.events[1].by, 2)
			expect.equal(view.events[1].streak, 1)
			-- Player 1's throw still in flight knocks player 3 out (an attacker need not stand): streak 1, the best stays 2.
			hit(w, 3, 1, back + w.cfg.spawnProtectSeconds + 0.6)
			view = lastView(w, w.players[3])
			expect.equal(rowOf(view, 1).streak, 1)
			expect.equal(rowOf(view, 1).bestStreak, 2)
			expect.equal(view.events[1].streak, 1)
			close()
		end
	)

	t.test(
		"match HUD M1: TDM K.O.s carry livesLeft (the team lives after it, 0 when out); out shows in players",
		function()
			local w = setup(2)
			local a = live(w, "tdm")
			local red, blue = teamsOf(w)
			hit(w, blue[1], red[1], a + 1)
			local view = lastView(w, w.players[red[1]])
			local lives = view.teamLives[w.cfg.teamNames[2]]
			expect.equal(lives, w.cfg.Modes.tdm.teamLives - 1)
			expect.deepEqual(view.events, {
				{
					seq = 1,
					kind = "ko",
					at = a + 1,
					victim = blue[1],
					by = red[1],
					cause = "hit",
					final = false,
					streak = 1,
					livesLeft = lives,
				},
			})
			close()

			-- Two K.O.s of one team in one batch: each has the lives right after it.
			local u = setup(4)
			local t0 = live(u, "tdm")
			local redU, blueU = teamsOf(u)
			local function request(victim: number, at: number): any
				return {
					attacker = fighterOf(u, redU[1]),
					victim = fighterOf(u, victim),
					at = at,
					kind = "throw",
					projId = 1,
					position = u.roots[victim].Position,
				}
			end
			u.port.applyHits({ request(blueU[1], t0 + 1), request(blueU[2], t0 + 1.1) }, t0 + 1.1)
			u.port.flush()
			local both = lastView(u, u.players[redU[1]]).events
			expect.equal(#both, 2)
			expect.equal(both[1].livesLeft, u.cfg.Modes.tdm.teamLives - 1)
			expect.equal(both[2].livesLeft, u.cfg.Modes.tdm.teamLives - 2)
			expect.equal(both[2].streak, 2)
			close()

			local c = baseConfig()
			c.Modes.tdm.teamLives = 0
			local v = setup(4, c)
			local b = live(v, "tdm")
			local red2, blue2 = teamsOf(v)
			hit(v, blue2[1], red2[1], b + 1)
			local after = lastView(v, v.players[red2[1]])
			expect.equal(after.outcome, nil) -- the other Blue player still stands
			expect.equal(after.events[1].livesLeft, 0)
			expect.equal(rowOf(after, blue2[1]).out, true)
			expect.equal(rowOf(after, blue2[1]).respawnAt, nil)
			close()
		end
	)

	t.test(
		"match HUD M1: the K.O. that reaches koTarget (an ultimate's too) is final and is outcome.finalKo",
		function()
			local cfg = baseConfig()
			cfg.Modes.ffa.koTarget = 2
			local w = setup(3, cfg)
			local a = live(w, "ffa")
			hit(w, 2, 1, a + 1)
			expect.equal(lastView(w, w.players[2]).outcome, nil)
			-- The deciding K.O. is an ultimate's (a Dragon Rush lane): its hit goes through applyHits like a throw's.
			w.port.applyHits({
				{
					attacker = fighterOf(w, 1),
					victim = fighterOf(w, 3),
					at = a + 2,
					kind = "lane",
					projId = 7,
					position = w.roots[3].Position,
				},
			}, a + 2)
			w.port.flush()
			local final =
				{ seq = 2, kind = "ko", at = a + 2, victim = 3, by = 1, cause = "hit", final = true, streak = 2 }
			for _, player in w.players do
				local view = lastView(w, player)
				expect.equal(view.phase, "Result")
				expect.equal(view.outcome.reason, "koTarget")
				expect.deepEqual(view.events, { final }) -- the same view as the outcome
				expect.deepEqual(view.outcome.finalKo, final)
			end
			-- Every later view repeats it (the last one, Returning), with no new events.
			MatchService.tick(a + 2 + cfg.resultSeconds)
			local returning = lastView(w, w.players[1])
			expect.equal(returning.phase, "Returning")
			expect.deepEqual(returning.outcome.finalKo, final)
			expect.deepEqual(returning.events, {})
			close()
		end
	)

	t.test(
		"match HUD M1: TDM: the K.O. that wipes a team, or wins overtime, is final and is outcome.finalKo",
		function()
			local c = baseConfig()
			c.Modes.tdm.teamLives = 0
			local w = setup(2, c)
			local a = live(w, "tdm")
			local red, blue = teamsOf(w)
			hit(w, blue[1], red[1], a + 1)
			local view = lastView(w, w.players[blue[1]])
			expect.equal(view.outcome.reason, "wiped")
			local final = {
				seq = 1,
				kind = "ko",
				at = a + 1,
				victim = blue[1],
				by = red[1],
				cause = "hit",
				final = true,
				streak = 1,
				livesLeft = 0,
			}
			expect.deepEqual(view.events, { final })
			expect.deepEqual(view.outcome.finalKo, final)
			close()

			-- Equal lives at time-up: Overtime, and the next K.O. decides it.
			local c2 = baseConfig()
			c2.Modes.tdm.storm = false
			local v = setup(2, c2)
			local b = live(v, "tdm")
			local red2, blue2 = teamsOf(v)
			local up = b + c2.Modes.tdm.matchSeconds
			v.clock.set(up)
			MatchService.tick(up)
			expect.equal(lastView(v, v.players[1]).matchPhase, "Overtime")
			hit(v, red2[1], blue2[1], up + 1)
			local ot = lastView(v, v.players[1])
			expect.equal(ot.outcome.reason, "overtime")
			expect.equal(ot.outcome.winnerTeam, c2.teamNames[2])
			local finalKo = ot.outcome.finalKo
			expect.equal(finalKo.victim, red2[1])
			expect.equal(finalKo.by, blue2[1])
			expect.equal(finalKo.cause, "hit")
			expect.equal(finalKo.final, true)
			expect.equal(finalKo.livesLeft, c2.Modes.tdm.teamLives - 1)
			expect.deepEqual(ot.events, { finalKo })
			close()
		end
	)

	t.test("match HUD M1: no finalKo for a time-up win, nor for a TDM wipe by a leave right after a K.O.", function()
		local w = setup(2)
		local a = live(w, "ffa")
		hit(w, 2, 1, a + 1)
		MatchService.tick(a + w.cfg.Modes.ffa.matchSeconds)
		local view = lastView(w, w.players[2])
		expect.equal(view.outcome.reason, "timeUp")
		expect.equal(view.outcome.finalKo, nil)
		close()

		local c = baseConfig()
		c.Modes.tdm.teamLives = 0
		local v = setup(4, c)
		local b = live(v, "tdm")
		local red, blue = teamsOf(v)
		-- The leave's projectile sweep brings a K.O. in (a batch of its own), then the leave wipes Blue.
		v.onSync = function(now: number)
			hit(v, blue[1], red[1], now)
		end
		v.clock.set(b + 1)
		MatchService.leave(v.players[blue[2]])
		local last = lastView(v, v.players[red[1]])
		expect.equal(last.outcome.reason, "wiped")
		expect.equal(last.outcome.winnerTeam, c.teamNames[1])
		expect.equal(last.outcome.finalKo, nil)
		local events = eventsOf(v, v.players[red[1]])
		expect.equal(#events, 1)
		expect.equal(events[1].victim, blue[1])
		expect.equal(events[1].final, false)
		close()
	end)

	t.test(
		"match HUD M1: a flush nested in stepMatch is a batch of its own: only the deciding K.O. is final",
		function()
			local c = baseConfig()
			c.Modes.tdm.teamLives = 0
			c.outOfBoundsIsKo = true
			local w = setup(4, c)
			local a = live(w, "tdm")
			local red, blue = teamsOf(w)
			-- The oob step's sweep (CombatService.syncTo) K.O.s blue[1] first: Blue still has blue[2] standing.
			w.onSync = function(now: number)
				hit(w, blue[1], red[1], now)
			end
			w.clock.set(a + 1)
			w.roots[blue[2]].Position = Vector3.new(CENTRE.X, -40, 0) -- then blue[2] falls off: Blue is wiped
			w.port.outOfBounds(fighterOf(w, blue[2]))
			local views = viewsOf(w, w.players[red[1]])
			local nested, last = views[#views - 1], views[#views]
			expect.deepEqual(nested.events, {
				{
					seq = 1,
					kind = "ko",
					at = a + 1,
					victim = blue[1],
					by = red[1],
					cause = "hit",
					final = false,
					streak = 1,
					livesLeft = 0,
				},
			})
			expect.equal(nested.outcome, nil)
			-- An out-of-bounds K.O. has no attacker (and no streak): the client never replays it.
			local final = {
				seq = 2,
				kind = "ko",
				at = a + 1,
				victim = blue[2],
				cause = "outOfBounds",
				final = true,
				livesLeft = 0,
			}
			expect.deepEqual(last.events, { final })
			expect.equal(last.outcome.reason, "wiped")
			expect.deepEqual(last.outcome.finalKo, final)
			close()
		end
	)

	t.test("match HUD M1: a storm K.O. has no attacker; storm-bar views (to one player) carry no events", function()
		local cfg = baseConfig()
		cfg.Storm.stormStartSeconds = 10
		cfg.Storm.steps = { { shrinkAt = 10, shrinkSeconds = 10, radiusFraction = 0.1 } }
		cfg.Storm.barFillSeconds = 1
		cfg.Storm.sampleHz = 5
		local w = setup(2, cfg)
		local a = live(w, "tdm")
		local red, blue = teamsOf(w)
		w.roots[blue[1]].Position = Vector3.new(CENTRE.X, 3, 100) -- far outside the last circle
		w.roots[red[1]].Position = Vector3.new(CENTRE.X, 3, 0)
		local sentBefore = #w.sent
		local now = a + 20
		for _ = 1, 20 do
			MatchService.tick(now)
			if not fighterOf(w, blue[1]).isAlive() then
				break
			end
			now += 0.2
		end
		local partial, events = 0, {}
		for i = sentBefore + 1, #w.sent do
			local entry = w.sent[i]
			if entry.player == w.players[blue[1]] then
				if entry.payload.events == nil then
					partial += 1
				else
					for _, event in entry.payload.events do
						table.insert(events, event)
					end
				end
			end
		end
		expect.truthy(partial >= 2)
		expect.equal(#events, 1)
		expect.equal(events[1].cause, "storm")
		expect.equal(events[1].victim, blue[1])
		expect.equal(events[1].by, nil)
		expect.equal(events[1].streak, nil)
		expect.equal(events[1].livesLeft, cfg.Modes.tdm.teamLives - 1)
		close()
	end)

	t.test(
		"match HUD M1: outcome.standings: MatchRules order, present players only, the same in later views",
		function()
			local w = setup(3)
			local a = live(w, "ffa")
			hit(w, 1, 3, a + 1) -- player 3 leads with 2 K.O.s ...
			hit(w, 2, 3, a + 1.1)
			local back = a + 1.1 + w.cfg.respawnSeconds + w.cfg.spawnProtectSeconds
			MatchService.tick(back)
			hit(w, 2, 1, back + 0.5) -- player 1: 1 K.O., best streak 1
			MatchService.leave(w.players[3]) -- ... and leaves: never on the podium
			MatchService.tick(a + w.cfg.Modes.ffa.matchSeconds)
			local view = lastView(w, w.players[1])
			expect.equal(view.outcome.reason, "timeUp")
			expect.equal(view.outcome.winnerUserId, 1)
			local standings = {
				{ userId = 1, kos = 1, knockedOut = 1, bestStreak = 1 },
				{ userId = 2, kos = 0, knockedOut = 2, bestStreak = 0 },
			}
			expect.deepEqual(view.outcome.standings, standings)
			expect.deepEqual(lastView(w, w.players[2]).outcome.standings, standings)
			-- Player 2 goes back to the lobby in Result: player 1's next view drops them from players, not the standings.
			MatchService.leave(w.players[2])
			local later = lastView(w, w.players[1])
			expect.equal(#later.players, 1)
			expect.deepEqual(later.outcome.standings, standings)
			close()
		end
	)

	-- Match HUD M2 (2026-10-16): the match pay and the win streak ------------------------------------------------------

	local DUEL_PAY = PAY_RULES.Economy.DuelRewards -- a match pays a duel's squeezes (the test's copy, deps.rewards.config)
	-- Active seconds that pay a win and a loss; that pay a win but not a loss; that pay neither.
	local PAYS_ALL = DUEL_PAY.lossMinActiveSeconds + 5
	local PAYS_WIN_ONLY = (DUEL_PAY.winMinActiveSeconds + DUEL_PAY.lossMinActiveSeconds) / 2
	local PAYS_NONE = DUEL_PAY.winMinActiveSeconds / 4

	-- `n` server-accepted throws for each of these users (CombatService's throwAccepted callback).
	local function throwsFor(w: World, userIds: { number }, n: number)
		for _, userId in userIds do
			for _ = 1, n do
				w.port.throwAccepted(fighterOf(w, userId))
			end
		end
	end

	local function payOf(result: string, squeezes: number, streakUp: boolean): any
		return { result = result, eligible = squeezes > 0, squeezes = squeezes, streakUp = streakUp }
	end

	t.test(
		"match HUD M2: Rewards off (the default): nothing paid, no mine; SD_WinStreak still shows the saved one",
		function()
			local cfg = baseConfig()
			cfg.Modes.ffa.koTarget = 1
			local w = setup(2, cfg, true)
			w.streaks[1] = 4
			MatchService.refreshWinStreak(w.players[1]) -- what init's DataService Loaded hook does
			expect.equal(w.players[1]:GetAttribute("SD_WinStreak"), 4)
			local a = live(w, "ffa")
			throwsFor(w, { 1, 2 }, 3)
			hit(w, 2, 1, a + 50)
			for _, player in w.players do
				local view = lastView(w, player)
				expect.equal(view.outcome.kind, "win")
				expect.equal(view.outcome.mine, nil)
			end
			expect.deepEqual(w.grants, {})
			expect.deepEqual(w.grips, {})
			expect.equal(w.streaks[1], 4)
			close()

			-- Without the pay collaborators (the older fakes) nothing is set at all.
			local v = setup(1)
			MatchService.refreshWinStreak(v.players[1])
			expect.equal(v.players[1]:GetAttribute("SD_WinStreak"), nil)
			close()
		end
	)

	t.test(
		"match HUD M2: FFA 1st is paid a duel win (+1 streak), the others a duel loss; mine only in their own view",
		function()
			local cfg = baseConfig()
			cfg.Modes.ffa.koTarget = 1
			cfg.Rewards.enabled = true
			local w = setup(3, cfg, true)
			w.streaks[1] = 2
			w.streaks[3] = 5
			local a = live(w, "ffa")
			local matchId = w.port.matchId
			throwsFor(w, { 1, 2 }, 3)
			throwsFor(w, { 3 }, 2) -- too few own throws (AFK): not paid; a loss, so the streak resets
			hit(w, 2, 1, a + PAYS_ALL) -- enough Active time for a win and a loss
			expect.deepEqual(w.grants, {
				{ userId = 1, matchId = matchId, pay = payOf("win", DUEL_PAY.win, true) },
				{ userId = 2, matchId = matchId, pay = payOf("loss", DUEL_PAY.loss, false) },
				{ userId = 3, matchId = matchId, pay = payOf("loss", 0, false) },
			})
			-- The same squeezes as Grip, only for the paid players.
			expect.deepEqual(
				w.grips,
				{ { userId = 1, squeezes = DUEL_PAY.win }, { userId = 2, squeezes = DUEL_PAY.loss } }
			)
			local first = { coins = DUEL_PAY.win * 10, grip = DUEL_PAY.win * 10, streakBefore = 2, streakAfter = 3 }
			local second = { coins = DUEL_PAY.loss * 10, grip = DUEL_PAY.loss * 10, streakBefore = 0, streakAfter = 0 }
			expect.deepEqual(lastView(w, w.players[1]).outcome.mine, first)
			expect.deepEqual(lastView(w, w.players[2]).outcome.mine, second)
			expect.equal(lastView(w, w.players[3]).outcome.mine, nil) -- not paid
			expect.equal(w.players[1]:GetAttribute("SD_WinStreak"), 3)
			expect.equal(w.players[2]:GetAttribute("SD_WinStreak"), 0)
			expect.equal(w.players[3]:GetAttribute("SD_WinStreak"), 0)
			-- Exactly once: the Returning view repeats mine and nothing is paid again.
			MatchService.tick(a + PAYS_ALL + cfg.resultSeconds)
			local returning = lastView(w, w.players[1])
			expect.equal(returning.phase, "Returning")
			expect.deepEqual(returning.outcome.mine, first)
			expect.equal(#w.grants, 3)
			expect.equal(#w.grips, 2)
			close()
		end
	)

	t.test(
		"match HUD M2: TDM: the winning team +1, the losers 0 (a short loss is not paid); a draw resets all",
		function()
			local c = baseConfig()
			c.Modes.tdm.teamLives = 0
			c.Rewards.enabled = true
			local w = setup(2, c, true)
			local a = live(w, "tdm")
			local red, blue = teamsOf(w)
			w.streaks[red[1]] = 1
			w.streaks[blue[1]] = 5
			throwsFor(w, { red[1], blue[1] }, 3)
			hit(w, blue[1], red[1], a + PAYS_WIN_ONLY) -- Blue wiped: long enough to pay the win, not the loss
			expect.equal(lastView(w, w.players[red[1]]).outcome.winnerTeam, c.teamNames[1])
			expect.deepEqual(w.grants, {
				{ userId = red[1], matchId = w.port.matchId, pay = payOf("win", DUEL_PAY.win, true) },
				{ userId = blue[1], matchId = w.port.matchId, pay = payOf("loss", 0, false) },
			})
			expect.equal(w.streaks[red[1]], 2)
			expect.equal(w.streaks[blue[1]], 0)
			expect.deepEqual(w.grips, { { userId = red[1], squeezes = DUEL_PAY.win } })
			expect.equal(lastView(w, w.players[red[1]]).outcome.mine.streakAfter, 2)
			expect.equal(lastView(w, w.players[blue[1]]).outcome.mine, nil)
			close()

			-- Equal lives at time-up, then overtime runs out: a draw, paid as a duel draw, every streak back to 0.
			local c2 = baseConfig()
			c2.Modes.tdm.storm = false
			c2.Rewards.enabled = true
			local v = setup(2, c2, true)
			local b = live(v, "tdm")
			v.streaks[1] = 3
			v.streaks[2] = 3
			throwsFor(v, { 1, 2 }, 3)
			local up = b + c2.Modes.tdm.matchSeconds
			v.clock.set(up)
			MatchService.tick(up)
			local over = up + c2.overtimeMaxSeconds
			v.clock.set(over)
			MatchService.tick(over)
			expect.equal(lastView(v, v.players[1]).outcome.kind, "draw")
			for _, grant in v.grants do
				expect.deepEqual(grant.pay, payOf("draw", DUEL_PAY.draw, false))
			end
			expect.equal(#v.grants, 2)
			expect.equal(v.streaks[1], 0)
			expect.equal(v.streaks[2], 0)
			expect.deepEqual(
				lastView(v, v.players[2]).outcome.mine,
				{ coins = DUEL_PAY.draw * 10, grip = DUEL_PAY.draw * 10, streakBefore = 3, streakAfter = 0 }
			)
			close()
		end
	)

	t.test(
		"match HUD M2: leaving a live match resets the streak (nothing paid), in Result not; cancelled / void: nothing",
		function()
			local cfg = baseConfig()
			cfg.Rewards.enabled = true
			local w = setup(3, cfg, true)
			w.streaks[2] = 2
			w.streaks[3] = 6
			local a = live(w, "ffa")
			local matchId = w.port.matchId
			MatchService.leave(w.players[3]) -- /leave in Active
			expect.deepEqual(w.grants, { { userId = 3, matchId = matchId, pay = payOf("left", 0, false) } })
			expect.equal(w.streaks[3], 0)
			expect.equal(w.players[3]:GetAttribute("SD_WinStreak"), 0)
			-- Leaving the game in Active: the same; it also ends the match (player 1 is the last one), a win that
			-- came too soon to pay (no Active time, no throws). Review fix (owner §12 Q4): still a win, so player 1's
			-- streak +1 (a quitter never wipes the winner's streak); nothing paid, so no mine.
			w.streaks[1] = 7
			w.clock.set(a + PAYS_NONE)
			w.players[2].Parent = nil
			MatchService.playerRemoving(w.players[2])
			expect.equal(lastView(w, w.players[1]).outcome.reason, "lastPlayer")
			expect.deepEqual(w.grants[2], { userId = 1, matchId = matchId, pay = payOf("win", 0, true) })
			expect.deepEqual(w.grants[3], { userId = 2, matchId = matchId, pay = payOf("left", 0, false) })
			expect.equal(w.streaks[1], 8)
			expect.equal(w.players[1]:GetAttribute("SD_WinStreak"), 8)
			expect.equal(w.streaks[2], 0)
			expect.deepEqual(w.grips, {})
			expect.equal(lastView(w, w.players[1]).outcome.mine, nil)
			close()

			-- Leaving in Result: the match is over, the pay is done: nothing more.
			local c2 = baseConfig()
			c2.Modes.ffa.koTarget = 1
			c2.Rewards.enabled = true
			local v = setup(2, c2, true)
			local b = live(v, "ffa")
			throwsFor(v, { 1, 2 }, 3)
			hit(v, 2, 1, b + PAYS_ALL)
			expect.equal(#v.grants, 2)
			MatchService.leave(v.players[2])
			expect.equal(#v.grants, 2)
			expect.equal(v.streaks[1], 1)
			close()

			-- Cancelled (too few arrived) and void (shutdown): nothing paid, no streak touched.
			local u = setup(2, c2, true)
			u.failTeleport[2] = true
			u.streaks[1] = 4
			MatchService.join(u.players[1], "ffa")
			MatchService.join(u.players[2], "ffa")
			u.flush()
			MatchService.tick(u.clock.now())
			expect.equal(lastView(u, u.players[1]).outcome.kind, "cancelled")
			expect.deepEqual(u.grants, {})
			expect.equal(u.streaks[1], 4)
			close()
			local s = setup(2, c2, true)
			live(s, "ffa")
			throwsFor(s, { 1, 2 }, 3)
			MatchService.voidAll("shutdown")
			expect.equal(lastView(s, s.players[1]).outcome.kind, "void")
			expect.deepEqual(s.grants, {})
			close()
		end
	)

	t.test(
		"match HUD M2 review fix: leaving in the Countdown resets the streak; leaving while Waiting does not",
		function()
			local cfg = baseConfig()
			cfg.Rewards.enabled = true
			local w = setup(4, cfg, true)
			for id = 1, 4 do
				w.streaks[id] = 3
			end
			for _, player in w.players do
				MatchService.join(player, "ffa")
			end
			local matchId = w.port.matchId
			expect.equal(w.port.phase(), "Positioning")
			MatchService.leave(w.players[4]) -- Waiting (Positioning): nothing at stake yet
			expect.deepEqual(w.grants, {})
			expect.equal(w.streaks[4], 3)
			w.flush() -- the other three arrive: the Countdown
			expect.equal(w.port.phase(), "Countdown")
			MatchService.leave(w.players[3]) -- the Countdown is leaving early
			expect.deepEqual(w.grants, { { userId = 3, matchId = matchId, pay = payOf("left", 0, false) } })
			expect.equal(w.streaks[3], 0)
			expect.equal(w.players[3]:GetAttribute("SD_WinStreak"), 0)
			-- A Countdown leave that cancels the match (too few left): only the leaver's streak goes.
			MatchService.leave(w.players[2])
			expect.equal(lastView(w, w.players[1]).outcome.kind, "cancelled")
			expect.equal(#w.grants, 2)
			expect.deepEqual(w.grants[2], { userId = 2, matchId = matchId, pay = payOf("left", 0, false) })
			expect.equal(w.streaks[2], 0)
			expect.equal(w.streaks[1], 3)
			close()
		end
	)

	t.test(
		"match HUD M2 review fix: a leave in the step that ends the match is no leave: paid as present, streak kept",
		function()
			for _, how in { "leave", "game" } do
				local cfg = baseConfig()
				cfg.Rewards.enabled = true
				local w = setup(3, cfg, true)
				w.streaks[2] = 4
				local a = live(w, "ffa")
				local matchId = w.port.matchId
				throwsFor(w, { 1, 2, 3 }, 3)
				hit(w, 1, 2, a + 1) -- player 2 leads 1-0
				-- The time-up is due but no tick has run: player 2's leave steps the match, MatchRules ends it first
				-- (player 2, still present, leads: they win) and ignores the leave.
				w.clock.set(a + cfg.Modes.ffa.matchSeconds)
				if how == "leave" then
					MatchService.leave(w.players[2])
				else
					w.players[2].Parent = nil
					MatchService.playerRemoving(w.players[2])
				end
				local view = lastView(w, w.players[1])
				expect.equal(view.outcome.reason, "timeUp")
				expect.equal(view.outcome.winnerUserId, 2)
				expect.equal(view.outcome.standings[1].userId, 2) -- the winner is in the standings
				expect.equal(#view.players, 2) -- but no longer in the match
				expect.deepEqual(w.grants, {
					{ userId = 1, matchId = matchId, pay = payOf("loss", DUEL_PAY.loss, false) },
					{ userId = 2, matchId = matchId, pay = payOf("win", DUEL_PAY.win, true) },
					{ userId = 3, matchId = matchId, pay = payOf("loss", DUEL_PAY.loss, false) },
				})
				expect.equal(w.streaks[2], 5) -- +1, never reset by the leave MatchRules did not take
				expect.equal(w.players[2]:GetAttribute("SD_WinStreak"), 5)
				expect.equal(#w.grips, 3)
				close()
			end
		end
	)

	t.test(
		"match HUD M2 review fix: the pay rules are deps.rewards.config's (the test's copy), not the live Config",
		function()
			local cfg = baseConfig()
			cfg.Modes.ffa.koTarget = 1
			cfg.Rewards.enabled = true
			local w = setup(2, cfg, true)
			w.payRules.Economy.DuelRewards.win = 900
			w.payRules.Economy.DuelRewards.minOwnThrows = 1
			local a = live(w, "ffa")
			throwsFor(w, { 1, 2 }, 1) -- one own throw each: paid only under the tuned copy
			hit(w, 2, 1, a + PAYS_ALL)
			expect.deepEqual(w.grants[1].pay, payOf("win", 900, true))
			expect.deepEqual(w.grants[2].pay, payOf("loss", DUEL_PAY.loss, false))
			close()
		end
	)

	t.test(
		"match HUD M2 review fix: a grant the profile refuses as already granted pays no Grip and no mine",
		function()
			local cfg = baseConfig()
			cfg.Modes.ffa.koTarget = 1
			cfg.Rewards.enabled = true
			local w = setup(2, cfg, true)
			w.streaks[2] = 3
			w.grantedBefore[2] = true
			local a = live(w, "ffa")
			throwsFor(w, { 1, 2 }, 3)
			hit(w, 2, 1, a + PAYS_ALL)
			expect.equal(#w.grants, 2) -- asked once each
			expect.deepEqual(w.grips, { { userId = 1, squeezes = DUEL_PAY.win } })
			expect.equal(lastView(w, w.players[2]).outcome.mine, nil)
			expect.equal(w.players[2]:GetAttribute("SD_WinStreak"), nil) -- not written by a refused grant
			expect.equal(w.streaks[2], 3)
			expect.truthy(lastView(w, w.players[1]).outcome.mine ~= nil)
			close()
		end
	)

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
