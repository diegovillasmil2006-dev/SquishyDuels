--!strict
-- QuestService_Test: unit tests for ServerScriptService.Server.Services.QuestService with injected fakes (a fake data
-- port over plain profiles, a fake Unix clock, a Coin recorder; players are plain tables). Server only
-- (ServerStorage.UnitTest). Edit mode: init() and start() are not called; the hooks are called directly. Quests are
-- generated with the seeded FakeRng (QuestLogic's rng factory), so the expected lists repeat on every runner.
-- Contract (DESIGN §6.8, §2.8 QuestClaim / QuestSwap / DuelResult.questProgress, §3.4, §17.7, §17.12 Part 7):
--   * ensureQuests: a READY profile gets today's quests from QuestLogic.generate (same player and day -> same quests),
--     once; the rollover grants every done-but-unclaimed quest once (reason "quest", quest.autoCollected), lets the
--     unfinished ones expire and resets swapsUsed; a stored day after today is kept; nothing for a profile that is
--     not ready;
--   * progress only from server hooks: squeezes (starter_squeeze; starter_jelly went with the giant pads, build plan
--     Phase 6, and onSqueezed takes no tier), practice
--     hits that count for quests, duel hits held until the result, the duel result (cancelled / void count nothing,
--     not even their hits; the test dummy's hits never count); an event after midnight counts for the new day; a quest
--     that becomes done toasts quest.complete; DuelResult lines list the quests the match moved;
--   * QuestClaim: data.notReady / net.invalid / quest.notReady / quest.alreadyClaimed; a claim pays once ("quest" for a
--     daily quest, "starter" for a starter task) and saves "soon"; every reward is counted in squeezes and pays × the
--     squeeze value of the moment it is granted (Phase 3, spec 2026-10-12 §9), the rollover's auto-claims included;
--   * QuestSwap: one free swap of an unfinished daily quest (QuestLogic.swap with swap number 1), then quest.swapUsed;
--     a done quest or a starter task is net.invalid;
--   * a profile load or an OFFLINE profile never moves progress or pays.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local DAY = 20000
local NOON = DAY * 86400 + 12 * 3600
local VALUE = 1_385 -- the squeeze value of the test profile: Toast (×1) in a Lv 30 capsule (CP 1,385)

return function(t: Context)
	local expect = t.expect
	local QuestService = t.requireServer("Services/QuestService")
	local QuestLogic = t.requireServer("Logic/QuestLogic")
	local FakeClock = t.requireFake("FakeClock")
	local FakeRng = t.requireFake("FakeRng")
	local TableUtil = t.requireShared("Util/TableUtil")
	local CapsuleMath = t.requireShared("CapsuleMath")

	type World = {
		clock: any,
		player: any,
		status: string,
		profile: any,
		dirty: { string },
		saves: { string },
		notices: { { code: string, args: any } },
		grants: { { amount: number, reason: string } },
	}

	local function newProfile(): any
		return {
			coins = 0,
			owned = {
				kitty_bread = { at = 1, src = "starter" },
				toast = { at = 2, src = "box" },
			},
			equipped = "toast",
			quests = { day = -1, swapsUsed = 0, active = {} },
			starter = { progress = {}, claimed = {} },
			capsules = { slots = 1, list = { { level = 30, squishyId = "toast" } } },
		}
	end

	local function fresh(): World
		local w: World = {
			clock = FakeClock.new(NOON),
			player = { UserId = 777 },
			status = "ready",
			profile = newProfile(),
			dirty = {},
			saves = {},
			notices = {},
			grants = {},
		}
		QuestService.useDeps({
			data = {
				getProfile = function(_player: any): any
					return if w.status == "loading" then nil else w.profile
				end,
				status = function(_player: any): string
					return w.status
				end,
				persisted = function(_player: any): boolean
					return true
				end,
				savePending = function(_player: any): boolean
					return false
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				-- Like DataService.mutate: READY sessions only.
				mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
					if w.status ~= "ready" then
						return false, "data.notReady"
					end
					return true, fn(w.profile)
				end,
				requestSave = function(_player: any, reason: string)
					table.insert(w.saves, reason)
				end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			markDirty = function(_player: any, field: string)
				table.insert(w.dirty, field)
			end,
			notify = function(_player: any, code: string, args: any)
				table.insert(w.notices, { code = code, args = args })
			end,
			grantCoins = function(_player: any, amount: number, reason: string): (number, string?)
				if w.status ~= "ready" then
					return 0, "notReady"
				end
				w.profile.coins += amount
				table.insert(w.grants, { amount = amount, reason = reason })
				return amount, nil
			end,
			unixNow = w.clock.now,
			onlinePlayers = function(): { any }
				return { w.player }
			end,
			debugAllowed = function(): boolean
				return true
			end,
			newRng = FakeRng.new, -- seeded: the same stream for the same seed on every runner
		})
		return w
	end

	local function finish()
		QuestService.useDeps(nil)
	end

	local function entry(slot: number, def: string, goal: number, reward: number, squishy: string?): any
		return {
			id = string.format("q%d_%d", DAY, slot),
			def = def,
			squishy = squishy,
			progress = 0,
			goal = goal,
			reward = reward,
			done = false,
			claimed = false,
		}
	end

	-- Today's quests set by hand (known templates and small goals).
	local function withQuests(w: World, list: { any })
		w.profile.quests = { day = DAY, swapsUsed = 0, active = list }
	end

	local function codes(w: World): { string }
		local list = {}
		for _, n in w.notices do
			table.insert(list, n.code)
		end
		return list
	end

	local function count(list: { string }, value: string): number
		local n = 0
		for _, v in list do
			if v == value then
				n += 1
			end
		end
		return n
	end

	local function hit(player: any, matchId: string, squishyId: string, isTestDummy: boolean?): any
		return {
			matchId = matchId,
			attacker = { player = player, isTestDummy = isTestDummy == true, squishyId = squishyId },
		}
	end

	local function result(outcome: string, squishyId: string, throws: number): any
		return { userId = 777, outcome = outcome, squishyId = squishyId, throws = throws, isTestDummy = false }
	end

	local function info(matchId: string, kind: string): any
		return { matchId = matchId, outcome = kind, reason = "eliminated", activeSeconds = 60 }
	end

	-- Generation and rollover -----------------------------------------------------------------------------------------

	t.test("a ready profile gets today's quests from QuestLogic.generate, once", function()
		local w = fresh()
		expect.truthy(QuestService.ensureQuests(w.player))
		local expected = QuestLogic.generate({
			userId = 777,
			day = DAY,
			owned = { "kitty_bread", "toast" },
			equipped = "toast",
		}, FakeRng.new)
		expect.deepEqual(w.profile.quests, { day = DAY, swapsUsed = 0, active = expected })
		expect.equal(#w.profile.quests.active, 3)
		expect.deepEqual(w.dirty, { "quests" })
		expect.falsy(QuestService.ensureQuests(w.player)) -- same day: nothing
		expect.equal(#w.dirty, 1)
		expect.equal(#w.grants, 0)
		finish()
	end)

	t.test("a profile that is not ready gets nothing", function()
		local w = fresh()
		for _, status in { "loading", "offline", "readonly" } do
			w.status = status
			expect.falsy(QuestService.ensureQuests(w.player))
		end
		expect.equal(w.profile.quests.day, -1)
		finish()
	end)

	t.test("rollover: done-but-unclaimed quests pay once, unfinished ones expire, swapsUsed resets", function()
		local w = fresh()
		local done = entry(1, "squeeze_any", 3, 150)
		done.progress, done.done = 3, true
		local claimed = entry(2, "duel_win", 1, 250)
		claimed.progress, claimed.done, claimed.claimed = 1, true, true
		local open = entry(3, "practice_hits", 20, 100)
		open.progress = 19
		w.profile.quests = { day = DAY - 1, swapsUsed = 1, active = { done, claimed, open } }
		expect.truthy(QuestService.ensureQuests(w.player))
		expect.deepEqual(w.grants, { { amount = 150 * VALUE, reason = "quest" } })
		expect.equal(w.profile.coins, 150 * VALUE)
		expect.deepEqual(codes(w), { "quest.autoCollected" })
		expect.equal(w.notices[1].args.coins, 150 * VALUE)
		expect.equal(w.profile.quests.day, DAY)
		expect.equal(w.profile.quests.swapsUsed, 0)
		expect.equal(#w.profile.quests.active, 3)
		for _, q in w.profile.quests.active do
			expect.equal(q.progress, 0)
			expect.equal(string.sub(q.id, 1, 7), "q20000_")
		end
		-- Running the check again the same day pays nothing more.
		QuestService.ensureQuests(w.player)
		expect.equal(#w.grants, 1)
		finish()
	end)

	t.test("a stored day after today (another server's clock) is kept, never rolled back", function()
		local w = fresh()
		local future = entry(1, "squeeze_any", 3, 150)
		future.id = string.format("q%d_1", DAY + 1)
		w.profile.quests = { day = DAY + 1, swapsUsed = 0, active = { future } }
		expect.falsy(QuestService.ensureQuests(w.player))
		expect.equal(w.profile.quests.day, DAY + 1)
		expect.equal(w.profile.quests.active[1], future)
		finish()
	end)

	t.test("an event after midnight rolls the day over first and counts for the new day", function()
		local w = fresh()
		withQuests(w, { entry(1, "squeeze_any", 3, 150) })
		w.clock.advance(24 * 3600) -- the next day
		QuestService.onSqueezed(w.player, "toast")
		expect.equal(w.profile.quests.day, DAY + 1)
		local expected = QuestLogic.generate({
			userId = 777,
			day = DAY + 1,
			owned = { "kitty_bread", "toast" },
			equipped = "toast",
		}, FakeRng.new)
		QuestLogic.apply(expected, { kind = "squeeze", squishyId = "toast" })
		expect.deepEqual(w.profile.quests.active, expected)
		expect.equal(w.profile.starter.progress.starter_squeeze, 1)
		finish()
	end)

	-- Progress --------------------------------------------------------------------------------------------------------

	t.test("squeezes move squeeze quests and starter_squeeze; quest.complete when one is done", function()
		local w = fresh()
		withQuests(w, { entry(1, "squeeze_any", 2, 150), entry(2, "squeeze_with", 2, 200, "toast") })
		QuestService.onSqueezed(w.player, "toast")
		QuestService.onSqueezed(w.player, "kitty_bread")
		local quests = w.profile.quests.active
		expect.equal(quests[1].progress, 2)
		expect.truthy(quests[1].done)
		expect.equal(quests[2].progress, 1)
		expect.falsy(quests[2].done)
		expect.equal(w.profile.starter.progress.starter_squeeze, 2)
		expect.equal(count(codes(w), "quest.complete"), 1)
		expect.equal(#w.grants, 0) -- progress never pays by itself
		finish()
	end)

	t.test("starter_jelly is gone (build plan Phase 6): squeezes move starter_squeeze only", function()
		local w = fresh()
		withQuests(w, {})
		for _ = 1, 3 do
			QuestService.onSqueezed(w.player, "toast")
		end
		expect.equal(w.profile.starter.progress.starter_jelly, nil)
		expect.equal(w.profile.starter.progress.starter_squeeze, 3)
		finish()
	end)

	t.test("practice hits count only when the target counts for quests", function()
		local w = fresh()
		withQuests(w, { entry(3, "practice_hits", 20, 100) })
		QuestService.onTargetHit(w.player, "T1", 10, true)
		QuestService.onTargetHit(w.player, "T1", 10.5, false)
		QuestService.onTargetHit(w.player, "T2", 11, true)
		expect.equal(w.profile.quests.active[1].progress, 2)
		expect.equal(w.profile.starter.progress.starter_practice, 2)
		finish()
	end)

	t.test("duel hits are held until the result, then counted with it; the lines list what the match moved", function()
		local w = fresh()
		withQuests(w, {
			entry(1, "squeeze_any", 100, 150),
			entry(2, "duel_win_with", 1, 300, "toast"),
			entry(3, "hits_with", 2, 250, "toast"),
		})
		local m = "match-1"
		QuestService.onHit(hit(w.player, m, "toast"))
		QuestService.onHit(hit(w.player, m, "toast"))
		QuestService.onHit(hit(w.player, m, "toast"))
		expect.equal(w.profile.quests.active[3].progress, 0) -- held, not counted yet
		local lines = QuestService.onDuelResult(w.player, result("win", "toast", 5), info(m, "win"))
		expect.equal(w.profile.quests.active[3].progress, 2)
		expect.truthy(w.profile.quests.active[3].done)
		expect.truthy(w.profile.quests.active[2].done)
		expect.equal(w.profile.starter.progress.starter_duel, 1)
		local byId: { [string]: any } = {}
		for _, line in lines do
			byId[line.questId] = line
		end
		expect.deepEqual(byId[string.format("q%d_3", DAY)], {
			questId = string.format("q%d_3", DAY),
			progress = 2,
			goal = 2,
			done = true,
		})
		expect.truthy(byId[string.format("q%d_2", DAY)].done)
		expect.deepEqual(byId.starter_duel, { questId = "starter_duel", progress = 1, goal = 1, done = true })
		expect.equal(byId[string.format("q%d_1", DAY)], nil) -- the squeeze quest was not touched
		expect.equal(#lines, 3)
		expect.equal(count(codes(w), "quest.complete"), 3)
		-- The held hits were used: a later result of another match does not count them again.
		QuestService.onDuelResult(w.player, result("loss", "toast", 5), info("match-2", "win"))
		expect.equal(w.profile.quests.active[3].progress, 2)
		finish()
	end)

	t.test("cancelled and void matches count nothing, not even their hits", function()
		local w = fresh()
		withQuests(w, { entry(2, "duel_finish", 2, 200), entry(3, "hits_with", 8, 250, "toast") })
		for _, kind in { "cancelled", "void" } do
			local m = "match-" .. kind
			QuestService.onHit(hit(w.player, m, "toast"))
			local lines = QuestService.onDuelResult(w.player, result(kind, "toast", 9), info(m, kind))
			expect.deepEqual(lines, {})
		end
		expect.equal(w.profile.quests.active[1].progress, 0)
		expect.equal(w.profile.quests.active[2].progress, 0)
		expect.equal(w.profile.starter.progress.starter_duel, nil)
		-- Their held hits are gone: the next finished match counts only its own.
		QuestService.onHit(hit(w.player, "match-3", "toast"))
		QuestService.onDuelResult(w.player, result("loss", "toast", 3), info("match-3", "win"))
		expect.equal(w.profile.quests.active[2].progress, 1)
		expect.equal(w.profile.quests.active[1].progress, 1)
		finish()
	end)

	t.test("too few own throws finish nothing; the test dummy's hits never count", function()
		local w = fresh()
		withQuests(w, { entry(2, "duel_finish", 2, 200), entry(3, "hits_with", 8, 250, "toast") })
		QuestService.onHit(hit(nil, "m", "toast", true))
		QuestService.onHit(hit(w.player, "m", "toast", true))
		local lines = QuestService.onDuelResult(w.player, result("win", "toast", 2), info("m", "win"))
		expect.deepEqual(lines, {})
		expect.equal(w.profile.quests.active[1].progress, 0)
		expect.equal(w.profile.quests.active[2].progress, 0)
		finish()
	end)

	t.test("an OFFLINE profile never moves progress", function()
		local w = fresh()
		withQuests(w, { entry(1, "squeeze_any", 2, 150) })
		w.status = "offline"
		QuestService.onSqueezed(w.player, "toast")
		QuestService.onTargetHit(w.player, "T1", 1, true)
		expect.deepEqual(QuestService.onDuelResult(w.player, result("win", "toast", 9), info("m", "win")), {})
		expect.equal(w.profile.quests.active[1].progress, 0)
		expect.deepEqual(w.profile.starter.progress, {})
		finish()
	end)

	-- Claims ----------------------------------------------------------------------------------------------------------

	t.test("QuestClaim: not done, then done (pays once with 'quest' and saves soon), then already claimed", function()
		local w = fresh()
		withQuests(w, { entry(1, "squeeze_any", 1, 150) })
		local id = string.format("q%d_1", DAY)
		local early = QuestService.claim(w.player, id)
		expect.equal(early.ok, false)
		expect.equal(early.reason, "quest.notReady")
		QuestService.onSqueezed(w.player, "toast")
		local reply = QuestService.claim(w.player, id)
		expect.equal(reply.ok, true)
		expect.deepEqual(w.grants, { { amount = 150 * VALUE, reason = "quest" } })
		expect.truthy(w.profile.quests.active[1].claimed)
		expect.deepEqual(w.saves, { "soon" })
		local again = QuestService.claim(w.player, id)
		expect.equal(again.ok, false)
		expect.equal(again.reason, "quest.alreadyClaimed")
		expect.equal(#w.grants, 1)
		expect.equal(w.profile.coins, 150 * VALUE)
		finish()
	end)

	t.test("a quest pays its squeezes at the squeeze value of the claim's moment (spec 2026-10-12 §9)", function()
		local w = fresh()
		local done = entry(1, "squeeze_any", 1, 150)
		done.progress, done.done = 1, true
		withQuests(w, { done })
		w.profile.capsules =
			{ slots = 2, list = { { level = 30, squishyId = "toast" }, { level = 11, squishyId = "dragon" } } }
		expect.equal(QuestService.claim(w.player, done.id).ok, true)
		expect.deepEqual(w.grants, { { amount = 150 * 64 * (CapsuleMath.power(11) :: number), reason = "quest" } })
		finish()
	end)

	t.test("QuestClaim: a starter task pays its QuestDefs reward with 'starter', once", function()
		local w = fresh()
		withQuests(w, {})
		w.profile.starter.progress.starter_practice = 5
		local reply = QuestService.claim(w.player, "starter_practice")
		expect.equal(reply.ok, true)
		expect.deepEqual(w.grants, { { amount = 50 * VALUE, reason = "starter" } })
		expect.truthy(w.profile.starter.claimed.starter_practice)
		expect.equal(QuestService.claim(w.player, "starter_practice").reason, "quest.alreadyClaimed")
		expect.equal(QuestService.claim(w.player, "starter_duel").reason, "quest.notReady")
		-- A claimed task never moves again.
		QuestService.onTargetHit(w.player, "T9", 3, true)
		expect.equal(w.profile.starter.progress.starter_practice, 5)
		expect.equal(#w.grants, 1)
		finish()
	end)

	t.test("QuestClaim of yesterday's done quest just after midnight: collected once, then alreadyClaimed", function()
		local w = fresh()
		local done = entry(1, "squeeze_any", 1, 150)
		done.progress, done.done = 1, true
		withQuests(w, { done })
		w.clock.advance(24 * 3600)
		local reply = QuestService.claim(w.player, done.id)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, "quest.alreadyClaimed")
		expect.deepEqual(w.grants, { { amount = 150 * VALUE, reason = "quest" } })
		expect.deepEqual(codes(w), { "quest.autoCollected" })
		expect.equal(w.profile.quests.day, DAY + 1)
		finish()
	end)

	t.test("QuestClaim: unknown ids are net.invalid; a profile that is not ready is data.notReady", function()
		local w = fresh()
		withQuests(w, { entry(1, "squeeze_any", 1, 150) })
		expect.equal(QuestService.claim(w.player, "q1_1").reason, "net.invalid")
		expect.equal(QuestService.claim(w.player, "starter_unknown").reason, "net.invalid")
		expect.equal(QuestService.claim(w.player, 5).reason, "net.invalid")
		w.status = "offline"
		expect.equal(QuestService.claim(w.player, string.format("q%d_1", DAY)).reason, "data.notReady")
		expect.equal(#w.grants, 0)
		finish()
	end)

	-- Swaps -----------------------------------------------------------------------------------------------------------

	t.test("QuestSwap: one free swap of an unfinished daily quest, then quest.swapUsed", function()
		local w = fresh()
		QuestService.ensureQuests(w.player)
		local before = TableUtil.deepCopy(w.profile.quests.active)
		local id = before[3].id
		local expected = QuestLogic.swap(before, id, {
			userId = 777,
			day = DAY,
			swapNumber = 1,
			owned = { "kitty_bread", "toast" },
			equipped = "toast",
		}, FakeRng.new)
		local reply = QuestService.swap(w.player, id)
		expect.equal(reply.ok, true)
		expect.deepEqual(w.profile.quests.active, expected)
		expect.equal(w.profile.quests.swapsUsed, 1)
		expect.deepEqual(w.saves, { "soon" })
		local again = QuestService.swap(w.player, before[1].id)
		expect.equal(again.reason, "quest.swapUsed")
		expect.equal(w.profile.quests.swapsUsed, 1)
		finish()
	end)

	t.test("QuestSwap: a done quest, a starter task or an unknown id is net.invalid", function()
		local w = fresh()
		local done = entry(1, "squeeze_any", 1, 150)
		done.progress, done.done = 1, true
		withQuests(w, { done, entry(2, "duel_win", 1, 250) })
		expect.equal(QuestService.swap(w.player, done.id).reason, "net.invalid")
		expect.equal(QuestService.swap(w.player, "starter_squeeze").reason, "net.invalid")
		expect.equal(QuestService.swap(w.player, "q1_1").reason, "net.invalid")
		expect.equal(w.profile.quests.swapsUsed, 0)
		w.status = "offline"
		expect.equal(QuestService.swap(w.player, string.format("q%d_2", DAY)).reason, "data.notReady")
		finish()
	end)

	-- Studio debug ----------------------------------------------------------------------------------------------------

	t.test("debug: setProgress then a forced rollover auto-collects the quest", function()
		local w = fresh()
		QuestService.ensureQuests(w.player)
		local first = w.profile.quests.active[1]
		expect.truthy(QuestService.debugSetProgress(w.player, first.id, first.goal))
		expect.truthy(first.done)
		expect.equal(#w.grants, 0) -- setting progress never pays
		local summary = QuestService.debugRollover(w.player)
		expect.equal(summary.autoClaimed, 1)
		expect.equal(summary.coins, first.reward * VALUE)
		expect.truthy(summary.generated)
		expect.equal(w.profile.quests.day, DAY)
		local state = QuestService.debugState(w.player)
		expect.equal(state.day, DAY)
		expect.equal(#state.starter, 3) -- starter_jelly went with the giant pads (Phase 6)
		expect.falsy(QuestService.debugRollover(w.player, DAY)) -- not a day before today
		finish()
	end)
end
