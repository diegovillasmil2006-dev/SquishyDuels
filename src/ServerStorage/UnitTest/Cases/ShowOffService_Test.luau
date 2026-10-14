--!strict
-- ShowOffService_Test: ServerScriptService.Server.Services.ShowOffService, the player list columns, the weekly wins
-- board and the badges (Batch 3, review #10). Server only (ServerStorage.UnitTest). Edit mode: init()/start() are
-- never called; every collaborator is a fake passed through useDeps (players are FakePlayers, the board is the
-- service's own memory store with failures injected, badges are recorders, spawn runs at once).
-- Contract (Config.Social.Board / Badges):
--   * leaderstats: Wins then Grip Lv (Strings names), from the profile's stats.duelsWon (re-read, never + 1) and the
--     Grip level, on load, on a level change and after a duel; the folder goes with the player;
--   * the board counts only a fully paid win (eligible, x1, Coins paid) of a real player over a real player: never
--     the test dummy, a bot (no Player) or userId <= 0 on a live server (Studio's local test players count there);
--   * weeks start Monday 00:00 UTC; Studio uses memory unless studioMode is "datastore" (then the _STUDIO name);
--   * a refresh sends every player the top 5 with names and their own place (or their week's wins when outside the
--     read); a failed read or write is logged and never raised, and keeps the last board; while no read has worked
--     yet, every player is told the board is unavailable; the live store checks the ordered stores' own budgets
--     (OrderedWrite / OrderedRead) before a write or a read, never OrderedList (its budget always reads 0);
--   * badges: each earned badge with an id is awarded once per session (one owned already is not awarded again);
--     never one without an id (logged once), in Studio or for userId <= 0; an error is retried on later sweeps, at
--     most maxTries times; Duel Buddies after a finished duel started on the pads or by Rematch.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type World = {
	time: number,
	studio: boolean,
	players: { any },
	profiles: { [any]: any },
	levels: { [any]: number },
	views: { [any]: any },
	open: (week: number) -> any,
	failRead: boolean,
	failWrite: boolean,
	names: { [number]: string },
	owned: { [string]: boolean },
	awards: { string },
	hasCalls: number,
	hasErrors: number,
	alwaysError: boolean,
	logs: { string },
	friend: { [string]: boolean },
	badges: { any },
}

local MONDAY = 1_791_763_200 -- 2026-10-12 00:00 UTC, a Monday

return function(t: Context)
	local expect = t.expect
	local ShowOffService = t.requireServer("Services/ShowOffService")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local FakePlayer = t.requireFake("FakePlayer")
	local BOARD = Config.Social.Board

	local function profile(won: number?): any
		return {
			owned = { kitty_bread = { at = 1, src = "starter" } },
			stats = { duelsPlayed = won or 0, duelsWon = won or 0 },
			capsules = { slots = 1, list = { { level = 1 } } },
		}
	end

	local function setup(): World
		local w: World = {
			time = MONDAY + 3600,
			studio = false,
			players = {},
			profiles = {},
			levels = {},
			views = {},
			open = ShowOffService.memoryStore(),
			failRead = false,
			failWrite = false,
			names = {},
			owned = {},
			awards = {},
			hasCalls = 0,
			hasErrors = 0,
			alwaysError = false,
			logs = {},
			friend = {},
			badges = {
				{ key = "welcome", id = 111, rule = { kind = "joined" } },
				{ key = "first_win", rule = { kind = "stat", stat = "duelsWon", atLeast = 1 } }, -- no id yet
				{ key = "first_duel", id = 333, rule = { kind = "stat", stat = "duelsPlayed", atLeast = 1 } },
				{ key = "duel_buddies", id = 444, rule = { kind = "flag", flag = "duelBuddies" } },
			},
		}
		local function record(_self: any, ...: any)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(w.logs, table.concat(parts, " "))
		end
		ShowOffService.useDeps({
			now = function(): number
				return w.time
			end,
			isStudio = function(): boolean
				return w.studio
			end,
			players = function(): { any }
				return w.players
			end,
			profileOf = function(player: any): any
				return w.profiles[player]
			end,
			levelOf = function(player: any): number
				return w.levels[player] or 0
			end,
			store = function(week: number): any
				local inner = w.open(week)
				return {
					increment = function(key: string, delta: number): number
						if w.failWrite then
							error("throttled")
						end
						return inner.increment(key, delta)
					end,
					get = inner.get,
					top = function(count: number): { any }
						if w.failRead then
							error("Studio access to API services is off")
						end
						return inner.top(count)
					end,
				}
			end,
			nameOf = function(userId: number): string?
				local name = w.names[userId]
				if name == nil then
					error("UserService failed")
				end
				return name
			end,
			hasBadge = function(userId: number, badgeId: number): boolean
				w.hasCalls += 1
				if w.alwaysError or w.hasErrors > 0 then
					w.hasErrors -= 1
					error("BadgeService is down")
				end
				return w.owned[`{userId}:{badgeId}`] == true
			end,
			awardBadge = function(userId: number, badgeId: number): boolean
				table.insert(w.awards, `{userId}:{badgeId}`)
				w.owned[`{userId}:{badgeId}`] = true
				return true
			end,
			badges = function(): { any }
				return w.badges
			end,
			setTopWins = function(player: any, view: any)
				w.views[player] = view
			end,
			isFriendMatch = function(matchId: string): boolean
				return w.friend[matchId] == true
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
			log = { info = record, warn = record, debug = record },
		})
		return w
	end

	local function join(w: World, userId: number, name: string?): any
		local player = FakePlayer.new(userId, name)
		table.insert(w.players, player)
		ShowOffService.playerAdded(player)
		return player
	end

	local function finish(w: World)
		for _, player in table.clone(w.players) do
			ShowOffService.playerRemoving(player)
		end
	end

	-- One participant's summary (DuelService.ParticipantSummary's fields this service reads).
	local function part(player: any, outcome: string, extra: { [string]: any }?): any
		local p: { [string]: any } = {
			userId = player.UserId,
			player = player,
			isTestDummy = false,
			outcome = outcome,
			reward = { eligible = true, multiplier = 1 },
			coinsGranted = if outcome == "win" then 600 else 0,
		}
		local given: { [string]: any } = extra or {}
		for key, value in given do
			p[key] = value
		end
		return p
	end

	local function summary(a: any, b: any, matchId: string?, outcome: string?): any
		return { matchId = matchId or "m1", outcome = outcome or "win", participants = { a, b }, bailers = {} }
	end

	local function count(list: { string }, text: string): number
		local n = 0
		for _, line in list do
			if string.find(line, text, 1, true) then
				n += 1
			end
		end
		return n
	end

	t.test(
		"leaderstats: Wins then Grip Lv, re-read from the profile and the Grip level; gone with the player",
		function()
			local w = setup()
			local p = join(w, 5)
			local folder = ShowOffService.leaderstatsOf(p)
			expect.equal(folder.Name, "leaderstats")
			local children = folder:GetChildren()
			expect.equal(#children, 2)
			expect.equal(children[1].Name, Strings.social.statWins)
			expect.equal(children[2].Name, Strings.social.statLevel)
			expect.equal(children[1].Name, "Wins")
			expect.equal(children[2].Name, "Grip Lv")
			local wins = folder:FindFirstChild("Wins") :: IntValue
			local level = folder:FindFirstChild("Grip Lv") :: IntValue
			expect.equal(wins.Value, 0)
			w.profiles[p] = profile(7)
			w.levels[p] = 23
			ShowOffService.profileLoaded(p)
			expect.equal(wins.Value, 7)
			expect.equal(level.Value, 23)
			ShowOffService.levelChanged(p, 23, 24)
			expect.equal(level.Value, 24)
			w.profiles[p].stats.duelsWon = 8
			local other = join(w, 6)
			ShowOffService.handleMatchEnded(summary(part(p, "win"), part(other, "loss")))
			ShowOffService.handleMatchEnded(summary(part(p, "win"), part(other, "loss")))
			expect.equal(wins.Value, 8) -- re-read, never + 1
			ShowOffService.playerRemoving(p)
			expect.equal(folder.Parent, nil)
			expect.equal(ShowOffService.leaderstatsOf(p), nil)
			finish(w)
		end
	)

	t.test("the board counts only a fully paid win of a real player over a real player", function()
		local a, b = FakePlayer.new(5), FakePlayer.new(6)
		local function counts(winner: any, loser: any, studio: boolean?): boolean
			return ShowOffService.countsForBoard(summary(winner, loser), winner, studio == true)
		end
		expect.truthy(counts(part(a, "win"), part(b, "loss")))
		expect.falsy(counts(part(a, "loss"), part(b, "win")))
		expect.falsy(counts(part(a, "win", { reward = { eligible = true, multiplier = 0.25 } }), part(b, "loss")))
		expect.falsy(counts(part(a, "win", { reward = { eligible = false, multiplier = 1 } }), part(b, "loss")))
		expect.falsy(counts(part(a, "win", { reward = false }), part(b, "loss"))) -- no reward computed
		expect.falsy(counts(part(a, "win", { coinsGranted = 0 }), part(b, "loss")))
		local dummy = { userId = -100001, isTestDummy = true, outcome = "loss" }
		expect.falsy(counts(part(a, "win"), dummy))
		local bot = { userId = -200001, isTestDummy = false, outcome = "loss" } -- no Player behind it
		expect.falsy(counts(part(a, "win"), bot))
		local local1, local2 = FakePlayer.new(-1), FakePlayer.new(-2) -- Studio's local test players
		expect.falsy(counts(part(local1, "win"), part(local2, "loss")))
		expect.truthy(counts(part(local1, "win"), part(local2, "loss"), true))
		expect.falsy(counts(part(local1, "win"), bot, true))
	end)

	t.test("a counted win adds one to this week's board; others add nothing; a failed write is only logged", function()
		local w = setup()
		local a, b = join(w, 5), join(w, 6)
		ShowOffService.handleMatchEnded(summary(part(a, "win"), part(b, "loss")))
		ShowOffService.handleMatchEnded(summary(part(a, "draw"), part(b, "draw")))
		ShowOffService.handleMatchEnded(
			summary(part(a, "win", { reward = { eligible = true, multiplier = 0.25 } }), part(b, "loss"))
		)
		local week = w.open(ShowOffService.weekIndex(w.time))
		expect.equal(week.get("5"), 1)
		expect.equal(week.get("6"), nil)
		w.failWrite = true
		ShowOffService.handleMatchEnded(summary(part(b, "win"), part(a, "loss")))
		expect.equal(week.get("6"), nil)
		expect.equal(count(w.logs, "board"), 1)
		finish(w)
	end)

	t.test("weeks start on Monday 00:00 UTC", function()
		expect.equal(ShowOffService.weekIndex(345_600), 0) -- 1970-01-05, the first Monday
		expect.equal(ShowOffService.weekIndex(345_599), -1)
		local week = ShowOffService.weekIndex(MONDAY)
		expect.equal(ShowOffService.weekIndex(MONDAY - 1), week - 1)
		expect.equal(ShowOffService.weekIndex(MONDAY + 7 * 86400 - 1), week)
		expect.equal(ShowOffService.weekIndex(MONDAY + 7 * 86400), week + 1)
	end)

	t.test("a refresh: the top 5 with names, every player's place, their week's wins outside the read", function()
		local w = setup()
		local ana = join(w, 5, "Ana")
		local bo = join(w, 6, "Bo")
		w.names[77] = "Cy"
		local week = w.open(ShowOffService.weekIndex(w.time))
		for i = 1, BOARD.readSize + 1 do
			week.increment(tostring(1000 + i), 1000 - i) -- 101 players ahead of Bo
		end
		week.increment("77", 5000)
		week.increment("5", 2000)
		week.increment("6", 1)
		expect.equal(w.views[ana], nil) -- nothing before the first read
		ShowOffService.playerRemoving(bo)
		ShowOffService.playerAdded(bo) -- the join reads Bo's own wins (1)
		ShowOffService.refreshBoard()
		local view = w.views[ana]
		expect.equal(view.loaded, true)
		expect.equal(#view.top, BOARD.size)
		expect.deepEqual(view.top[1], { name = "Cy", wins = 5000 })
		expect.deepEqual(view.top[2], { name = "Ana", wins = 2000 })
		expect.deepEqual(view.top[3], { name = Strings.board.someone, wins = 999 }) -- the name lookup failed
		expect.equal(view.place, 2)
		expect.equal(view.wins, 2000)
		local mine = w.views[bo]
		expect.equal(mine.place, nil)
		expect.equal(mine.wins, 1)
		w.failRead = true
		ShowOffService.refreshBoard()
		expect.equal(w.views[ana], view) -- kept
		expect.equal(count(w.logs, "board"), 1)
		finish(w)
	end)

	t.test("an empty week: loaded with no lines; a counted win updates the winner's own line at once", function()
		local w = setup()
		local a, b = join(w, 5), join(w, 6)
		ShowOffService.refreshBoard()
		expect.deepEqual(w.views[a], { loaded = true, top = {}, wins = 0 })
		ShowOffService.handleMatchEnded(summary(part(a, "win"), part(b, "loss")))
		expect.equal(w.views[a].wins, 1)
		finish(w)
	end)

	t.test("reads failing from the start: every player is told the board is unavailable, until a read works", function()
		local w = setup()
		local a = join(w, 5)
		w.failRead = true
		ShowOffService.refreshBoard()
		expect.deepEqual(w.views[a], { loaded = true, unavailable = true, top = {}, wins = 0 })
		w.failRead = false
		ShowOffService.refreshBoard()
		expect.deepEqual(w.views[a], { loaded = true, top = {}, wins = 0 })
		finish(w)
	end)

	t.test(
		"the live board checks OrderedWrite and OrderedRead budgets, never OrderedList (always 0 per the docs)",
		function()
			local asked: { Enum.DataStoreRequestType } = {}
			local calls: { string } = {}
			local budget = 1
			local ordered: any = {
				IncrementAsync = function(_self: any, key: string, delta: number): number
					table.insert(calls, `increment {key} {delta}`)
					return 7
				end,
				GetAsync = function(_self: any, key: string): number?
					table.insert(calls, `get {key}`)
					return 3
				end,
				GetSortedAsync = function(_self: any, ascending: boolean, count: number): any
					table.insert(calls, `top {ascending} {count}`)
					return {
						GetCurrentPage = function(_page: any): { any }
							return { { key = "5", value = 9 } }
						end,
					}
				end,
			}
			local service: any = {
				GetRequestBudgetForRequestType = function(_self: any, kind: Enum.DataStoreRequestType): number
					table.insert(asked, kind)
					return budget
				end,
				GetOrderedDataStore = function(_self: any, name: string, scope: string): any
					table.insert(calls, `open {name} {scope}`)
					return ordered
				end,
			}
			local open = ShowOffService.liveStore("WeeklyWins_Test_STUDIO", service)
			local week = open(42)
			expect.equal(week.increment("5", 1), 7)
			expect.equal(week.get("5"), 3)
			expect.deepEqual(week.top(5), { { key = "5", value = 9 } })
			local kinds = Enum.DataStoreRequestType
			expect.deepEqual(asked, { kinds.OrderedWrite, kinds.OrderedRead })
			expect.equal(open(42), week) -- one store per week
			expect.deepEqual(calls, { "open WeeklyWins_Test_STUDIO w42", "increment 5 1", "get 5", "top false 5" })
			budget = 0
			expect.falsy((pcall(week.increment, "5", 1))) -- no budget left: an error for the caller to log, and no call
			expect.falsy((pcall(week.get, "5")))
			expect.equal(#calls, 4)
			expect.equal(#week.top(5), 1) -- the list is never gated (its budget reads 0 even when there is room)
		end
	)

	t.test("Studio keeps the board in memory unless studioMode is datastore, then the _STUDIO store", function()
		expect.equal(ShowOffService.storeNameFor(true, "memory"), nil)
		expect.equal(ShowOffService.storeNameFor(true, "datastore"), BOARD.studioStoreName)
		expect.equal(string.sub(BOARD.studioStoreName, -7), "_STUDIO")
		expect.equal(ShowOffService.storeNameFor(false, "memory"), BOARD.storeName)
		local open = ShowOffService.memoryStore()
		local week = open(10)
		expect.equal(week.increment("5", 1), 1)
		expect.equal(week.increment("5", 1), 2)
		week.increment("7", 1)
		week.increment("3", 1)
		expect.deepEqual(week.top(2), { { key = "5", value = 2 }, { key = "3", value = 1 } })
		expect.equal(week.get("9"), nil)
		expect.deepEqual(open(11).top(5), {})
	end)

	t.test(
		"badges: each earned one with an id once per session; none without an id, in Studio or below id 1",
		function()
			local w = setup()
			local p = join(w, 5)
			w.profiles[p] = profile(1)
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
			expect.deepEqual(w.awards, { "5:111", "5:333" })
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
			expect.equal(#w.awards, 2)
			expect.equal(count(w.logs, "first_win"), 1) -- earned, but no badge id yet: logged once
			local owner = join(w, 8)
			w.profiles[owner] = profile(0)
			w.owned["8:111"] = true -- owned from an earlier session
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
			expect.equal(#w.awards, 2)
			local localPlayer = join(w, -1)
			w.profiles[localPlayer] = profile(1)
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
			expect.equal(#w.awards, 2)
			finish(w)

			local s = setup()
			s.studio = true
			local studioPlayer = join(s, 9)
			s.profiles[studioPlayer] = profile(1)
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
			ShowOffService.sweepBadges()
			expect.equal(s.hasCalls, 0)
			expect.equal(#s.awards, 0)
			expect.equal(count(s.logs, "would award welcome"), 1)
			finish(s)
		end
	)

	t.test("a badge error is retried on later sweeps, at most maxTries times", function()
		local w = setup()
		w.badges = { w.badges[1] }
		local p = join(w, 5)
		w.profiles[p] = profile(0)
		w.hasErrors = 1
		for _ = 1, 2 do
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
		end
		expect.deepEqual(w.awards, { "5:111" })
		finish(w)

		local v = setup()
		v.badges = { v.badges[1] }
		v.alwaysError = true
		local q = join(v, 6)
		v.profiles[q] = profile(0)
		for _ = 1, Config.Social.Badges.maxTries + 3 do
			ShowOffService.sweepBadges()
			ShowOffService.processBadges()
		end
		expect.equal(v.hasCalls, Config.Social.Badges.maxTries)
		expect.equal(#v.awards, 0)
		finish(v)
	end)

	t.test("Duel Buddies after a finished duel from the pads or Rematch; not a cancel or the dummy", function()
		local w = setup()
		w.badges = { { key = "duel_buddies", id = 444, rule = { kind = "flag", flag = "duelBuddies" } } }
		local a, b, c = join(w, 5), join(w, 6), join(w, 7)
		for _, player in { a, b, c } do
			w.profiles[player] = profile(0)
		end
		w.friend = { f1 = true, f2 = true, f3 = true }
		ShowOffService.handleMatchEnded(summary(part(c, "win"), part(b, "loss"), "plain"))
		ShowOffService.handleMatchEnded(summary(part(c, "draw"), part(b, "draw"), "f2", "cancelled"))
		ShowOffService.handleMatchEnded(
			summary(part(c, "win"), { userId = -100001, isTestDummy = true, outcome = "loss" }, "f3")
		)
		ShowOffService.sweepBadges()
		ShowOffService.processBadges()
		expect.equal(#w.awards, 0)
		ShowOffService.handleMatchEnded(summary(part(a, "win"), part(b, "loss"), "f1"))
		ShowOffService.sweepBadges()
		ShowOffService.processBadges()
		table.sort(w.awards)
		expect.deepEqual(w.awards, { "5:444", "6:444" })
		finish(w)
	end)
end
