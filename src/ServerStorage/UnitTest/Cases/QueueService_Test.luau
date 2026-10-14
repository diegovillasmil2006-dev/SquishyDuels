--!strict
-- QueueService_Test: unit tests for ServerScriptService.Server.Services.QueueService.
-- Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never called; every collaborator is a fake passed
-- through useDeps (players are plain tables, the arena is a counter, DuelService is a recorder, time is a FakeClock),
-- and deferred pairing is switched off so each case decides when pairing runs. Logic/Matchmaker is the real one.
-- Contract (DESIGN §2.8 QueueJoin/QueueLeave/ReportIdle/QueueStatus, §5.4, §12 #15, #21):
--   * join: Searching with a position; refusals in §2.8 order (alreadyQueued, paused while restarting or closing,
--     unavailable without an arena, while not accepting, or for the test dummy, notReady without a live character,
--     cooldown);
--   * pairing: the head and the next ticket, one slot each, DuelService.startMatch(a, b, slot) with the slot handed
--     off; no free slot = nobody paired and queue.waitingArena; a failed start releases the slot and holds the pair;
--     requeued tickets go first; the last opponent is avoided while another partner exists;
--   * leave / ReportIdle / time-out remove a Searching ticket with their Notify code; a Matched player cannot leave;
--   * Matched -> Idle once DuelService no longer has the match (after the grace), with the 3 s requeue cooldown;
--     MatchEnded: the bailer gets 15 s, the innocent player is requeued at the front;
--   * readMatchEnded understands DuelRules-shaped (side-keyed) and userId-shaped summaries;
--   * the board gets count-only QueueStatus payloads (no `state`).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	clock: any,
	logged: { string },
	sent: { { name: string, player: any, payload: any } },
	broadcasts: { any },
	notices: { { player: any, code: string, args: any, kind: string? } },
	started: { { a: any, b: any, slot: any } },
	matches: { [any]: any },
	arena: { free: number, inUse: number, available: boolean, handoff: any, released: number },
	flags: { closing: boolean, restart: boolean, startFails: boolean, startErrors: boolean },
	players: { any },
}

return function(t: Context)
	local expect = t.expect
	local QueueService = t.requireServer("Services/QueueService")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local Rules = Config.Duel.Rules
	local Matchmaking = Config.Duel.Matchmaking

	local nextSlotId = 0

	local function fakePlayer(userId: number): any
		return { UserId = userId, Name = `P{userId}`, fake = true, dead = false }
	end

	-- A fresh queue with `count` players already added. Pairing is deferred to the test (defer does nothing).
	local function setup(count: number, slots: number?): World
		local w: World = {
			clock = FakeClock.new(10000),
			logged = {},
			sent = {},
			broadcasts = {},
			notices = {},
			started = {},
			matches = {},
			arena = { free = slots or 6, inUse = 0, available = true, handoff = nil, released = 0 },
			flags = { closing = false, restart = false, startFails = false, startErrors = false },
			players = {},
		}
		QueueService.useDeps({
			now = w.clock.now,
			isPlayer = function(p: any): boolean
				return type(p) == "table" and p.fake == true
			end,
			isAlive = function(p: any): boolean
				return not p.dead
			end,
			arena = {
				available = function(): boolean
					return w.arena.available
				end,
				freeCount = function(): number
					return w.arena.free
				end,
				inUseCount = function(): number
					return w.arena.inUse
				end,
				acquire = function(): any?
					local handed = w.arena.handoff
					if handed ~= nil then
						w.arena.handoff = nil
						return handed
					end
					if w.arena.free <= 0 then
						return nil
					end
					w.arena.free -= 1
					w.arena.inUse += 1
					nextSlotId += 1
					return { id = nextSlotId, inUse = true }
				end,
				release = function(slot: any)
					if slot.inUse then
						slot.inUse = false
						w.arena.free += 1
						w.arena.inUse -= 1
						w.arena.released += 1
					end
				end,
				handoff = function(slot: any?)
					w.arena.handoff = slot
				end,
			},
			duel = {
				startMatch = function(a: any, b: any, slot: any): (any, any)
					if w.flags.startErrors then
						error("boom")
					end
					table.insert(w.started, { a = a, b = b, slot = slot })
					if w.flags.startFails then
						return nil, "noCharacter"
					end
					local match = { matchId = `m{#w.started}` }
					w.matches[a] = match
					w.matches[b] = match
					return match, nil
				end,
				inMatch = function(p: any): boolean
					return w.matches[p] ~= nil
				end,
			},
			fire = function(name: string, player: any, payload: any)
				table.insert(w.sent, { name = name, player = player, payload = payload })
			end,
			fireAll = function(_name: string, payload: any)
				table.insert(w.broadcasts, payload)
			end,
			notify = function(player: any, code: string, args: any, kind: string?)
				table.insert(w.notices, { player = player, code = code, args = args, kind = kind })
			end,
			closing = function(): boolean
				return w.flags.closing
			end,
			restartPending = function(): boolean
				return w.flags.restart
			end,
			dataStatus = function(p: any): string?
				return p.dataStatus -- nil unless a case sets it (Batch 3)
			end,
			defer = function(_fn: () -> ()) end,
			log = {
				warn = function(_self: any, ...: any)
					table.insert(w.logged, "warn " .. tostring((...)))
				end,
				error = function(_self: any, ...: any)
					table.insert(w.logged, "error " .. tostring((...)))
				end,
			},
		})
		for i = 1, count do
			local p = fakePlayer(i)
			table.insert(w.players, p)
			QueueService.playerAdded(p)
		end
		return w
	end

	local function lastStatus(w: World, player: any): any
		for i = #w.sent, 1, -1 do
			local entry = w.sent[i]
			if entry.player == player and entry.name == "QueueStatus" and entry.payload.state ~= nil then
				return entry.payload
			end
		end
		return nil
	end

	local function lastNotice(w: World, player: any): any
		for i = #w.notices, 1, -1 do
			if w.notices[i].player == player then
				return w.notices[i]
			end
		end
		return nil
	end

	local function join(w: World, index: number): any
		w.clock.advance(0.01) -- distinct joinedAt values
		return QueueService.join(w.players[index])
	end

	t.test("join: Searching with a position; a second join is alreadyQueued", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		local r1 = join(w, 1)
		expect.equal(r1.ok, true)
		expect.equal(r1.data.position, 1)
		expect.equal(QueueService.state(p1), "Searching")
		local status = lastStatus(w, p1)
		expect.equal(status.state, "Searching")
		expect.equal(status.position, 1)
		expect.equal(status.searching, 1)
		expect.truthy(status.joinedAt)
		local r2 = join(w, 2)
		expect.equal(r2.data.position, 2)
		expect.equal(QueueService.position(p2), 2)
		local again = join(w, 1)
		expect.equal(again.ok, false)
		expect.equal(again.reason, "queue.alreadyQueued")
	end)

	t.test("Joined fires once per accepted join, never for a refused one (onboarding step duel, §11.8)", function()
		local w = setup(1)
		local joined: { any } = {}
		local connection = QueueService.Joined:connect(function(player: any)
			table.insert(joined, player)
		end)
		local ok, err = pcall(function()
			expect.equal(join(w, 1).ok, true)
			expect.equal(join(w, 1).reason, "queue.alreadyQueued")
			expect.equal(#joined, 1)
			expect.equal(joined[1], w.players[1])
		end)
		connection:disconnect()
		if not ok then
			error(err, 0)
		end
	end)

	t.test("join refusals: paused, unavailable, no live character, not accepting, the test dummy", function()
		local w = setup(1)
		w.flags.restart = true
		expect.equal(join(w, 1).reason, "queue.paused")
		w.flags.restart = false
		w.flags.closing = true
		expect.equal(join(w, 1).reason, "queue.paused")
		w.flags.closing = false
		w.arena.available = false
		expect.equal(join(w, 1).reason, "queue.unavailable")
		w.arena.available = true
		w.players[1].dead = true
		expect.equal(join(w, 1).reason, "queue.notReady") -- no live character (reading: Strings reason.queue.notReady)
		w.players[1].dead = false
		QueueService.setAccepting(false)
		expect.equal(join(w, 1).reason, "queue.unavailable")
		QueueService.setAccepting(true)
		local dummy = { kind = "testDummy", isTestDummy = true, userId = -100001 }
		local refused = QueueService.join(dummy)
		expect.equal(refused.ok, false)
		expect.equal(refused.reason, "queue.unavailable")
		expect.equal(QueueService.searchingCount(), 0)
		expect.equal(join(w, 1).ok, true)
	end)

	t.test("pairing: oldest two get one slot each through the handoff, both Matched", function()
		local w = setup(3)
		join(w, 1)
		join(w, 2)
		join(w, 3)
		local started = QueueService.pairNow()
		expect.equal(started, 1)
		expect.equal(#w.started, 1)
		expect.equal(w.started[1].a, w.players[1])
		expect.equal(w.started[1].b, w.players[2])
		expect.truthy(w.started[1].slot)
		expect.equal(w.arena.handoff, nil) -- cleared after startMatch
		expect.equal(w.arena.inUse, 1)
		expect.equal(QueueService.state(w.players[1]), "Matched")
		expect.equal(QueueService.state(w.players[2]), "Matched")
		expect.truthy(QueueService.isLocked(w.players[1]))
		expect.equal(lastStatus(w, w.players[1]).state, "Matched")
		expect.equal(QueueService.position(w.players[3]), 1)
		expect.equal(QueueService.leave(w.players[1]), false) -- Matched: Cancel is ignored
	end)

	t.test("no free arena: nobody is paired and the head sees queue.waitingArena", function()
		local w = setup(2, 0)
		join(w, 1)
		join(w, 2)
		QueueService.tick()
		expect.equal(#w.started, 0)
		expect.equal(lastStatus(w, w.players[1]).messageKey, "queue.waitingArena")
		w.arena.free = 1
		QueueService.tick()
		expect.equal(#w.started, 1)
	end)

	t.test("alone for NoOpponentHintSeconds: queue.noOpponent", function()
		local w = setup(1)
		join(w, 1)
		QueueService.tick()
		expect.equal(lastStatus(w, w.players[1]).messageKey, nil)
		w.clock.advance(Matchmaking.NoOpponentHintSeconds)
		QueueService.tick()
		expect.equal(lastStatus(w, w.players[1]).messageKey, "queue.noOpponent")
	end)

	t.test("a failed start releases the slot, keeps both queued and holds the pair back", function()
		local w = setup(2)
		join(w, 1)
		join(w, 2)
		w.flags.startFails = true
		expect.equal(QueueService.pairNow(), 0)
		expect.equal(w.arena.released, 1)
		expect.equal(w.arena.inUse, 0)
		expect.equal(QueueService.state(w.players[1]), "Searching")
		w.flags.startFails = false
		expect.equal(QueueService.pairNow(), 0) -- held back
		w.clock.advance(2.1)
		expect.equal(QueueService.pairNow(), 1)
		-- An error inside startMatch is caught the same way.
		local w2 = setup(2)
		join(w2, 1)
		join(w2, 2)
		w2.flags.startErrors = true
		expect.equal(QueueService.pairNow(), 0)
		expect.equal(w2.arena.inUse, 0)
		expect.equal(QueueService.searchingCount(), 2)
		expect.truthy(string.find(w2.logged[1], "error", 1, true) == 1)
	end)

	t.test("leave, ReportIdle and the time-out remove the ticket with their codes", function()
		local w = setup(3)
		join(w, 1)
		join(w, 2)
		join(w, 3)
		w.arena.free = 0 -- nobody pairs
		expect.equal(QueueService.leave(w.players[1]), true)
		expect.equal(lastNotice(w, w.players[1]).code, "queue.left")
		expect.equal(lastStatus(w, w.players[1]).state, "Idle")
		expect.equal(QueueService.reportIdle(w.players[2]), true)
		expect.equal(lastNotice(w, w.players[2]).code, "queue.removedIdle")
		expect.equal(QueueService.reportIdle(w.players[2]), false) -- not queued any more
		w.clock.advance(Matchmaking.QueueMaxSeconds + 1)
		QueueService.tick()
		local notice = lastNotice(w, w.players[3])
		expect.equal(notice.code, "queue.timedOut")
		expect.equal(notice.args.minutes, Matchmaking.QueueMaxSeconds / 60)
		expect.equal(QueueService.state(w.players[3]), "Idle")
		expect.equal(QueueService.searchingCount(), 0)
	end)

	t.test("match over: Idle after the grace, then the 3 s requeue cooldown", function()
		local w = setup(2)
		join(w, 1)
		join(w, 2)
		QueueService.pairNow()
		local p1 = w.players[1]
		QueueService.tick() -- still in the match
		expect.equal(QueueService.state(p1), "Matched")
		w.matches = {} -- DuelService finished the match
		QueueService.tick() -- within the grace
		expect.equal(QueueService.state(p1), "Matched")
		w.clock.advance(2.1)
		QueueService.tick()
		expect.equal(QueueService.state(p1), "Idle")
		expect.equal(lastStatus(w, p1).state, "Idle")
		expect.equal(QueueService.join(p1).reason, "queue.cooldown")
		w.clock.advance(Rules.RequeueCooldownSeconds + 0.01)
		expect.equal(QueueService.join(p1).ok, true)
	end)

	t.test("MatchEnded: the bailer waits 15 s, the innocent player is requeued at the front", function()
		local w = setup(4)
		join(w, 1)
		join(w, 2)
		QueueService.pairNow()
		join(w, 3)
		local p1, p2 = w.players[1], w.players[2]
		QueueService.handleMatchEnded({
			matchId = "m1",
			participants = { A = { userId = 1 }, B = { userId = 2 } },
			outcome = { kind = "cancelled", bailer = "A", requeue = "B" },
		})
		w.matches = {}
		w.arena.free = 0 -- keep the requeued ticket waiting so its position can be read
		w.clock.advance(2.1)
		QueueService.tick()
		expect.equal(QueueService.state(p2), "Searching")
		expect.equal(QueueService.position(p2), 1) -- ahead of player 3, who joined earlier
		expect.equal(QueueService.state(p1), "Idle")
		w.clock.advance(Rules.RequeueCooldownSeconds + 1)
		expect.equal(QueueService.join(p1).reason, "queue.cooldown")
		w.clock.advance(Rules.BailRequeueCooldownSeconds)
		expect.equal(QueueService.join(p1).ok, true)
	end)

	t.test("MatchEnded in DuelService's MatchSummary shape: bailer cooldown, innocent requeued", function()
		local w = setup(3)
		join(w, 1)
		join(w, 2)
		QueueService.pairNow()
		join(w, 3)
		local p1, p2 = w.players[1], w.players[2]
		QueueService.handleMatchEnded({
			matchId = "m1",
			outcome = "cancelled",
			reason = "leave",
			endedFrom = "Preparing",
			activeSeconds = 0,
			result = { kind = "cancelled", bailer = "B", requeue = "A" },
			participants = {
				{ userId = 1, player = p1, isTestDummy = false, side = "A", bailed = false, requeueFront = true },
				{ userId = 2, player = p2, isTestDummy = false, side = "B", bailed = true, requeueFront = false },
			},
			bailers = { 2 },
			requeueUserIds = { 1 },
			noRequeue = false,
		})
		w.matches = {}
		w.arena.free = 0 -- keep the requeued ticket waiting so its position can be read
		w.clock.advance(2.1)
		QueueService.tick()
		expect.equal(QueueService.state(p1), "Searching")
		expect.equal(QueueService.position(p1), 1) -- ahead of player 3, who joined earlier
		expect.equal(QueueService.state(p2), "Idle")
		w.clock.advance(Rules.RequeueCooldownSeconds + 1)
		expect.equal(QueueService.join(p2).reason, "queue.cooldown")
	end)

	t.test("MatchEnded for a finished match (noRequeue): both go Idle with the normal cooldown", function()
		local w = setup(2)
		join(w, 1)
		join(w, 2)
		QueueService.pairNow()
		QueueService.handleMatchEnded({
			matchId = "m1",
			outcome = "win",
			result = { kind = "win", winner = "A" },
			participants = { { userId = 1, side = "A" }, { userId = 2, side = "B" } },
			bailers = {},
			requeueUserIds = {},
			noRequeue = true,
		})
		w.matches = {}
		w.clock.advance(2.1)
		QueueService.tick()
		expect.equal(QueueService.state(w.players[1]), "Idle")
		expect.equal(QueueService.state(w.players[2]), "Idle")
		expect.equal(QueueService.searchingCount(), 0)
		w.clock.advance(Rules.RequeueCooldownSeconds + 0.01)
		expect.equal(QueueService.join(w.players[2]).ok, true)
	end)

	t.test("a queued player who leaves the game loses the ticket", function()
		local w = setup(2)
		w.arena.free = 0
		join(w, 1)
		join(w, 2)
		QueueService.playerRemoving(w.players[1])
		expect.equal(QueueService.searchingCount(), 1)
		expect.equal(QueueService.position(w.players[2]), 1)
		expect.equal(QueueService.state(w.players[1]), "Idle")
		expect.equal(QueueService.join(w.players[1]).reason, "queue.unavailable") -- no record any more
	end)

	t.test("requeue: the last opponent is avoided while another partner exists", function()
		local w = setup(3)
		join(w, 1)
		join(w, 2)
		QueueService.pairNow()
		w.matches = {}
		w.clock.advance(2.1)
		QueueService.tick() -- both Idle, 3 s cooldown from now
		w.clock.advance(Rules.RequeueCooldownSeconds + 0.01)
		join(w, 1)
		join(w, 2)
		join(w, 3)
		expect.equal(QueueService.pairNow(), 1)
		local second = w.started[2]
		expect.equal(second.a, w.players[1])
		expect.equal(second.b, w.players[3])
	end)

	t.test(
		"a restart: no front requeue (bail cooldown still applies); setAccepting(false) empties the queue",
		function()
			local w = setup(3)
			join(w, 1)
			join(w, 2)
			QueueService.pairNow()
			join(w, 3)
			w.flags.restart = true
			QueueService.handleMatchEnded() -- harmless without a payload
			QueueService.handleMatchEnded({
				participants = { A = { userId = 1 }, B = { userId = 2 } },
				outcome = { kind = "cancelled", bailer = "A", requeue = "B" },
			})
			w.matches = {}
			w.clock.advance(2.1)
			QueueService.tick()
			expect.equal(QueueService.state(w.players[2]), "Idle")
			w.flags.restart = false
			w.clock.advance(Rules.RequeueCooldownSeconds + 1)
			expect.equal(QueueService.join(w.players[1]).reason, "queue.cooldown")
			QueueService.setAccepting(false)
			expect.equal(QueueService.searchingCount(), 0)
			expect.equal(lastNotice(w, w.players[3]).code, "queue.unavailable")
			QueueService.setAccepting(true)
		end
	)

	t.test("forceMatch: a player against the test dummy, outside the queue", function()
		local w = setup(1)
		join(w, 1)
		local dummy = { kind = "testDummy", isTestDummy = true, userId = -100001 }
		local ok, match = QueueService.forceMatch(w.players[1], dummy)
		expect.truthy(ok)
		expect.equal(match.matchId, "m1")
		expect.equal(w.started[1].b, dummy)
		expect.equal(QueueService.state(w.players[1]), "Matched")
		expect.equal(QueueService.searchingCount(), 0)
		local again = QueueService.forceMatch(w.players[1], dummy)
		expect.falsy(again)
	end)

	t.test(
		"startDirect (Batch 3 pads and Rematch): both start at once; tickets dropped, Matched, Joined twice",
		function()
			local w = setup(3)
			join(w, 1)
			join(w, 3)
			local joined: { any } = {}
			local connection = QueueService.Joined:connect(function(player: any)
				table.insert(joined, player)
			end)
			local ok, err = pcall(function()
				local started, match = QueueService.startDirect(w.players[1], w.players[2])
				expect.truthy(started)
				expect.equal(match.matchId, "m1")
				expect.equal(w.started[1].a, w.players[1])
				expect.equal(w.started[1].b, w.players[2])
				expect.equal(QueueService.state(w.players[1]), "Matched")
				expect.equal(QueueService.state(w.players[2]), "Matched")
				expect.equal(QueueService.searchingCount(), 1) -- player 3 is still waiting
				expect.equal(lastNotice(w, w.players[1]), nil) -- the ticket went without a "left the queue" toast
				expect.deepEqual(joined, { w.players[1], w.players[2] }) -- the tutorial's duel step for both
			end)
			connection:disconnect()
			if not ok then
				error(err, 0)
			end
		end
	)

	t.test("startDirect warns a player whose save did not load, as QueueJoin does", function()
		local w = setup(2)
		local p1, p2 = w.players[1], w.players[2]
		p2.dataStatus = "offline"
		expect.truthy((QueueService.startDirect(p1, p2)))
		expect.equal(lastNotice(w, p1), nil)
		local notice = lastNotice(w, p2)
		expect.equal(notice.code, "duel.noRewardsOffline")
		expect.equal(notice.kind, "warn")
	end)

	t.test("startDirect refuses in QueueJoin's order; a full arena before any ticket is touched", function()
		local w = setup(3)
		local p1, p2 = w.players[1], w.players[2]
		local function reason(a: any, b: any): any
			local started, why = QueueService.startDirect(a, b)
			expect.falsy(started)
			return why
		end
		expect.equal(reason(p1, { kind = "testDummy", isTestDummy = true, userId = -100001 }), "queue.unavailable")
		w.flags.restart = true
		expect.equal(reason(p1, p2), "queue.paused")
		w.flags.restart = false
		p2.dead = true
		expect.equal(reason(p1, p2), "queue.notReady")
		p2.dead = false
		join(w, 1)
		w.arena.free = 0
		expect.equal(reason(p1, p2), "queue.waitingArena")
		expect.equal(QueueService.state(p1), "Searching") -- the ticket is kept
		w.arena.free = 6
		QueueService.forceMatch(w.players[3], p2) -- Studio path (unit tests run in Studio): p2 is in a match now
		expect.equal(reason(p1, p2), "queue.alreadyQueued")
		w.matches = {}
		w.clock.advance(2.1)
		QueueService.tick() -- p2 back to Idle, with the 3 s cooldown
		expect.equal(reason(p2, p1), "queue.cooldown")
		QueueService.setAccepting(false)
		expect.equal(reason(p1, p2), "queue.unavailable")
		QueueService.setAccepting(true)
		w.clock.advance(Rules.RequeueCooldownSeconds + 0.01)
		expect.truthy((QueueService.startDirect(p2, p1)))
	end)

	t.test("board: count-only QueueStatus to everyone, on change", function()
		local w = setup(2)
		-- playerAdded sends each newcomer the board counts.
		local first = w.sent[1]
		expect.equal(first.name, "QueueStatus")
		expect.equal(first.payload.state, nil)
		join(w, 1)
		QueueService.tick()
		expect.equal(#w.broadcasts, 1)
		local board = w.broadcasts[1]
		expect.equal(board.state, nil)
		expect.equal(board.searching, 1)
		expect.equal(board.arenasFree, 6)
		QueueService.tick() -- nothing changed
		expect.equal(#w.broadcasts, 1)
		w.clock.advance(1)
		join(w, 2)
		QueueService.pairNow()
		QueueService.tick()
		expect.equal(#w.broadcasts, 2)
		expect.equal(w.broadcasts[2].duelsInProgress, 1)
	end)

	t.test("readMatchEnded: DuelRules state, an ended effect, and userId summaries", function()
		local fromState = QueueService.readMatchEnded({
			matchId = "abc",
			participants = { A = { userId = 11, side = "A" }, B = { userId = 22, side = "B" } },
			outcome = { kind = "cancelled", bailer = "B", requeue = "A" },
		})
		expect.equal(fromState.matchId, "abc")
		expect.equal(fromState.outcome, "cancelled")
		expect.deepEqual(fromState.bailers, { 22 })
		expect.deepEqual(fromState.requeue, { 11 })
		local fromEffect = QueueService.readMatchEnded({ kind = "ended", outcome = { kind = "win", winner = "A" } }, {
			participants = { A = { userId = 1 }, B = { userId = 2 } },
		})
		expect.equal(fromEffect.outcome, "win")
		expect.deepEqual(fromEffect.requeue, {})
		local p1, p2 = fakePlayer(5), fakePlayer(6)
		local fromIds = QueueService.readMatchEnded({ phase = "Cancelled", players = { p1, p2 }, bailerUserId = 6 })
		expect.deepEqual(fromIds.bailers, { 6 })
		expect.deepEqual(fromIds.requeue, { 5 }) -- derived: cancelled with a bailer
		local voided = QueueService.readMatchEnded({ phase = "Void", players = { p1, p2 }, noRequeue = true })
		expect.equal(voided.noRequeue, true)
		expect.deepEqual(voided.requeue, {})
		local empty = QueueService.readMatchEnded()
		expect.deepEqual(empty.participants, {})
	end)
end
