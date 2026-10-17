--!strict
-- QuestLogic_Test: unit tests for ServerScriptService.Server.Logic.QuestLogic. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.8, §17.10, §17.12 Part 7, §13.2 Part 7 L1): the seed is userId × 100000 + day % 100000
-- (+ 7919 × swapNumber); the same seed gives the same quests; a quest never names an unowned squishy (new players get
-- Kitty Bread quests); slot 1 is a squeeze template, slot 2 a duel template, slot 3 any template not chosen, ids
-- "q<day>_<slot>"; a swap uses the swap seed, keeps the slot id, picks a template not in the list from another
-- category, refuses done / unknown / starter quests (net.invalid) and a second swap (quest.swapUsed), and leaves the
-- input unchanged; progress counts only what each template counts (cancelled and void duels never count; duel_finish
-- needs >= 3 own throws, duel_win / duel_win_with count every win, §6.8), stops at the goal and reports one line per
-- changed quest; every accepted squeeze moves starter_squeeze (starter_jelly and the squeeze event's tier went with
-- the giant pads, build plan Phase 6; a slow-training tick, a level-up or a load move nothing); claimed
-- tasks never move; the rollover auto-claims done-but-unclaimed quests of an old day. Weekly quests (2026-10-17):
-- generateWeekly lists every QuestDefs.weekly() quest in order (ids "w<week>_<slot>", the same list every week), and
-- apply moves them with the daily kinds' rules.
-- Determinism uses Fakes/FakeRng seeded factories (the same on every runner); one case also checks Random.new.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local USER = 1234
local DAY = 20368
local ALL_OWNED = { "banana", "bird", "butter", "chocolate", "donut", "dragon", "kitty_bread", "toast" }

return function(t: Context)
	local QuestLogic = t.requireServer("Logic/QuestLogic")
	local QuestDefs = t.requireShared("QuestDefs")
	local Config = t.requireShared("Config")
	local FakeRng = t.requireFake("FakeRng")
	local expect = t.expect

	local MIN_THROWS = Config.Economy.DuelRewards.minOwnThrows

	local function generate(userId: number, day: number, owned: { string }, equipped: string?): { any }
		return QuestLogic.generate({ userId = userId, day = day, owned = owned, equipped = equipped }, FakeRng.new)
	end

	local function entry(def: string, goal: number, squishy: string?): any
		return {
			id = "q1_1",
			def = def,
			squishy = squishy,
			progress = 0,
			goal = goal,
			reward = 100,
			done = false,
			claimed = false,
		}
	end

	local function freshStarter(): any
		return { progress = {}, claimed = {} }
	end

	local function squeeze(squishyId: string): any
		return { kind = "squeeze", squishyId = squishyId }
	end

	local function duel(outcome: string, squishyId: string, throws: number): any
		return { kind = "duel", outcome = outcome, squishyId = squishyId, throws = throws }
	end

	-- seed / generate -------------------------------------------------------------------------------------------

	t.test("seed is userId × 100000 + day % 100000 + 7919 × swapNumber", function()
		expect.equal(QuestLogic.seed(1, 2), 100002)
		expect.equal(QuestLogic.seed(1, 2, 1), 100002 + 7919)
		expect.equal(QuestLogic.seed(USER, DAY), USER * 100000 + DAY)
		expect.equal(QuestLogic.seed(1, 100005), 100005) -- the day wraps at 100000
		expect.equal(QuestLogic.seed(-1, 5), -100000 + 5) -- Studio test players have userIds <= 0
	end)

	t.test("generate seeds its rng with seed(userId, day)", function()
		local seeds = {}
		QuestLogic.generate({ userId = USER, day = DAY, owned = ALL_OWNED, equipped = "toast" }, function(seed: number)
			table.insert(seeds, seed)
			return FakeRng.new(seed)
		end)
		expect.deepEqual(seeds, { QuestLogic.seed(USER, DAY) })
	end)

	t.test("the same seed gives the same quests; another day or player gives other ones", function()
		local first = generate(USER, DAY, ALL_OWNED, "dragon")
		expect.deepEqual(generate(USER, DAY, ALL_OWNED, "dragon"), first)
		-- The owned list's order does not matter (it is sorted first).
		local shuffled = { "toast", "dragon", "kitty_bread", "bird", "butter", "donut", "banana", "chocolate" }
		expect.deepEqual(generate(USER, DAY, shuffled, "dragon"), first)
		local differs = 0
		for day = DAY + 1, DAY + 20 do
			local other = generate(USER, day, ALL_OWNED, "dragon")
			for slot, quest in other do
				if quest.def ~= first[slot].def or quest.goal ~= first[slot].goal then
					differs += 1
					break
				end
			end
		end
		expect.truthy(differs > 0)
	end)

	t.test("with the game's Random.new the same seed gives the same quests", function()
		local ctx = { userId = USER, day = DAY, owned = ALL_OWNED, equipped = "dragon" }
		local a = QuestLogic.generate(ctx)
		local b = QuestLogic.generate(ctx)
		expect.equal(#a, Config.Economy.Quests.perDay)
		-- Reading: the offline Lune runner stands in an unseeded Random; in Studio Random.new(seed) is repeatable.
		local first, second = Random.new(7), Random.new(7)
		local seeded = true
		for _ = 1, 3 do
			seeded = seeded and first:NextInteger(1, 1e6) == second:NextInteger(1, 1e6)
		end
		if seeded then
			expect.deepEqual(a, b)
		end
	end)

	t.test("slot 1 is a squeeze template, slot 2 a duel template, slot 3 any other; ids q<day>_<slot>", function()
		for day = DAY, DAY + 60 do
			local quests = generate(USER, day, ALL_OWNED, "toast")
			expect.equal(#quests, Config.Economy.Quests.perDay)
			expect.equal(QuestDefs.get(quests[1].def).category, "squeeze")
			expect.equal(QuestDefs.get(quests[2].def).category, "duel")
			local defs: { [string]: boolean } = {}
			for slot, quest in quests do
				expect.equal(quest.id, `q{day}_{slot}`)
				expect.truthy(not defs[quest.def])
				defs[quest.def] = true
				local def = QuestDefs.get(quest.def)
				expect.equal(def.kind, "daily")
				-- goal and reward are one of the template's variants
				local matches = false
				for _, variant in def.variants do
					matches = matches or (variant.goal == quest.goal and variant.reward == quest.reward)
				end
				expect.truthy(matches)
				expect.equal(quest.progress, 0)
				expect.equal(quest.done, false)
				expect.equal(quest.claimed, false)
				expect.equal(quest.squishy ~= nil, def.needsSquishy)
			end
		end
	end)

	t.test("a quest never names an unowned squishy (and never an unowned equipped one)", function()
		local ownedSets = {
			{ "kitty_bread" },
			{ "kitty_bread", "toast" },
			{ "dragon", "kitty_bread", "banana" },
			ALL_OWNED,
		}
		for _, owned in ownedSets do
			local isOwned: { [string]: boolean } = {}
			for _, id in owned do
				isOwned[id] = true
			end
			for day = DAY, DAY + 40 do
				for _, equipped in { "dragon", "kitty_bread", "bird" } do
					for _, quest in generate(USER + day, day, owned, equipped) do
						if quest.squishy ~= nil and not isOwned[quest.squishy] then
							error(`day {day}: {quest.def} names {quest.squishy}, which is not owned`)
						end
					end
				end
			end
		end
	end)

	t.test("new players get Kitty Bread quests; unknown or duplicate owned ids are ignored", function()
		for day = DAY, DAY + 30 do
			for _, quest in generate(USER, day, { "kitty_bread" }, "kitty_bread") do
				if quest.squishy ~= nil then
					expect.equal(quest.squishy, "kitty_bread")
				end
			end
			for _, quest in generate(USER, day, { "not_a_squishy", "kitty_bread", "kitty_bread" }, "not_a_squishy") do
				if quest.squishy ~= nil then
					expect.equal(quest.squishy, "kitty_bread")
				end
			end
		end
	end)

	t.test("the equipped squishy is picked more often than a uniform pick would", function()
		local equippedPicks, named = 0, 0
		for day = DAY, DAY + 400 do
			for _, quest in generate(USER, day, ALL_OWNED, "dragon") do
				if quest.squishy ~= nil then
					named += 1
					if quest.squishy == "dragon" then
						equippedPicks += 1
					end
				end
			end
		end
		-- Expected share: 0.5 + 0.5 / 8 = 56%; uniform would be 12.5%.
		expect.truthy(named > 100)
		expect.truthy(equippedPicks / named > 0.4)
	end)

	-- swap -------------------------------------------------------------------------------------------------------

	local function swapCtx(swapNumber: number): any
		return { userId = USER, day = DAY, swapNumber = swapNumber, owned = ALL_OWNED, equipped = "toast" }
	end

	t.test("swap uses seed(userId, day, swapNumber), keeps the slot id and picks a template not in the list", function()
		local quests = generate(USER, DAY, ALL_OWNED, "toast")
		local before = table.clone(quests)
		local seeds = {}
		local swapped, reason = QuestLogic.swap(quests, quests[2].id, swapCtx(1), function(seed: number)
			table.insert(seeds, seed)
			return FakeRng.new(seed)
		end)
		expect.equal(reason, nil)
		expect.deepEqual(seeds, { QuestLogic.seed(USER, DAY, 1) })
		local new = swapped[2]
		expect.equal(new.id, quests[2].id)
		for _, quest in quests do
			expect.truthy(new.def ~= quest.def)
		end
		expect.equal(new.progress, 0)
		expect.falsy(new.done)
		expect.deepEqual(swapped[1], quests[1])
		expect.deepEqual(swapped[3], quests[3])
		-- The input list is unchanged.
		expect.deepEqual(quests, before)
		expect.equal(quests[2].def, before[2].def)
	end)

	t.test("swap prefers another category (a duel quest can become a squeeze or practice quest)", function()
		for day = DAY, DAY + 40 do
			local quests = generate(USER, day, ALL_OWNED, "toast")
			local ctx = { userId = USER, day = day, swapNumber = 1, owned = ALL_OWNED, equipped = "toast" }
			local swapped = QuestLogic.swap(quests, quests[2].id, ctx, FakeRng.new)
			expect.truthy(swapped ~= nil)
			local oldCategory = QuestDefs.get(quests[2].def).category
			local newCategory = QuestDefs.get((swapped :: any)[2].def).category
			expect.truthy(newCategory ~= oldCategory)
		end
	end)

	t.test("swap is the same for the same seed", function()
		local quests = generate(USER, DAY, ALL_OWNED, "toast")
		local a = QuestLogic.swap(quests, quests[1].id, swapCtx(1), FakeRng.new)
		local b = QuestLogic.swap(quests, quests[1].id, swapCtx(1), FakeRng.new)
		expect.deepEqual(a, b)
	end)

	t.test("swap refuses unknown, done and claimed quests (net.invalid) and a second swap (quest.swapUsed)", function()
		local quests = generate(USER, DAY, ALL_OWNED, "toast")
		local none, why = QuestLogic.swap(quests, "q1_9", swapCtx(1), FakeRng.new)
		expect.equal(none, nil)
		expect.equal(why, "net.invalid")
		local done = table.clone(quests)
		done[1] = table.clone(quests[1])
		done[1].done = true
		local _, doneWhy = QuestLogic.swap(done, done[1].id, swapCtx(1), FakeRng.new)
		expect.equal(doneWhy, "net.invalid")
		local claimed = table.clone(quests)
		claimed[3] = table.clone(quests[3])
		claimed[3].claimed = true
		local _, claimedWhy = QuestLogic.swap(claimed, claimed[3].id, swapCtx(1), FakeRng.new)
		expect.equal(claimedWhy, "net.invalid")
		local second, secondWhy = QuestLogic.swap(quests, quests[1].id, swapCtx(2), FakeRng.new)
		expect.equal(second, nil)
		expect.equal(secondWhy, "quest.swapUsed")
		local _, zeroWhy = QuestLogic.swap(quests, quests[1].id, swapCtx(0), FakeRng.new)
		expect.equal(zeroWhy, "quest.swapUsed")
	end)

	-- apply -------------------------------------------------------------------------------------------------------

	t.test("squeezes count for squeeze_any, and for squeeze_with only with the quest's squishy", function()
		local any = entry("squeeze_any", 2)
		local with = entry("squeeze_with", 60, "toast")
		local quests = { any, with }
		local lines = QuestLogic.apply(quests, squeeze("banana"))
		expect.deepEqual(lines, { { questId = any.id, progress = 1, goal = 2, done = false } })
		QuestLogic.apply(quests, squeeze("toast"))
		expect.equal(any.progress, 2)
		expect.truthy(any.done)
		expect.equal(with.progress, 1)
		-- A done quest does not move again.
		expect.deepEqual(QuestLogic.apply({ any }, squeeze("toast")), {})
		expect.equal(any.progress, 2)
	end)

	t.test("a finished duel needs a win, loss or draw with >= 3 own throws; cancelled and void never count", function()
		local finish = entry("duel_finish", 10)
		local quests = { finish }
		for _, outcome in { "cancelled", "void" } do
			expect.deepEqual(QuestLogic.apply(quests, duel(outcome, "toast", 20)), {})
		end
		expect.deepEqual(QuestLogic.apply(quests, duel("loss", "toast", MIN_THROWS - 1)), {})
		expect.equal(finish.progress, 0)
		for _, outcome in { "win", "loss", "draw" } do
			QuestLogic.apply(quests, duel(outcome, "toast", MIN_THROWS))
		end
		expect.equal(finish.progress, 3)
	end)

	t.test("duel_win counts every win; duel_win_with only with the quest's squishy", function()
		local win = entry("duel_win", 5)
		local winWith = entry("duel_win_with", 5, "dragon")
		local quests = { win, winWith }
		QuestLogic.apply(quests, duel("loss", "dragon", 9))
		QuestLogic.apply(quests, duel("draw", "dragon", 9))
		QuestLogic.apply(quests, duel("cancelled", "dragon", 9))
		QuestLogic.apply(quests, duel("void", "dragon", 9))
		expect.equal(win.progress, 0)
		expect.equal(winWith.progress, 0)
		QuestLogic.apply(quests, duel("win", "toast", 9))
		expect.equal(win.progress, 1)
		expect.equal(winWith.progress, 0)
		local lines = QuestLogic.apply(quests, duel("win", "dragon", 9))
		expect.equal(win.progress, 2)
		expect.equal(winWith.progress, 1)
		expect.equal(#lines, 2)
	end)

	t.test("a forfeit win with < 3 own throws counts for duel_win / duel_win_with, never for duel_finish", function()
		-- §6.8: duel_win counts "wins (incl. forfeit wins after 20 s)" and duel_win_with "wins where the match snapshot
		-- squishyId == X", with no own-throw minimum; only duel_finish needs >= 3 own throws (Part 7 review fix).
		local win = entry("duel_win", 5)
		local winWith = entry("duel_win_with", 5, "dragon")
		local finish = entry("duel_finish", 5)
		local quests = { win, winWith, finish }
		local lines = QuestLogic.apply(quests, duel("win", "dragon", MIN_THROWS - 1))
		expect.equal(win.progress, 1)
		expect.equal(winWith.progress, 1)
		expect.equal(finish.progress, 0)
		expect.equal(#lines, 2)
		QuestLogic.apply(quests, duel("win", "toast", 0))
		expect.equal(win.progress, 2)
		expect.equal(winWith.progress, 1)
		expect.equal(finish.progress, 0)
	end)

	t.test("hits_with counts hits with the quest's squishy; practice_hits counts target hits", function()
		local hits = entry("hits_with", 2, "bird")
		local practice = entry("practice_hits", 20)
		local quests = { hits, practice }
		QuestLogic.apply(quests, { kind = "hit", squishyId = "toast" })
		expect.equal(hits.progress, 0)
		QuestLogic.apply(quests, { kind = "hit", squishyId = "bird" })
		local lines = QuestLogic.apply(quests, { kind = "hit", squishyId = "bird" })
		expect.deepEqual(lines, { { questId = hits.id, progress = 2, goal = 2, done = true } })
		QuestLogic.apply(quests, { kind = "practiceHit" })
		expect.equal(practice.progress, 1)
		-- Practice hits and squeezes never count for duel templates.
		local finish = entry("duel_finish", 2)
		QuestLogic.apply({ finish }, { kind = "practiceHit" })
		QuestLogic.apply({ finish }, squeeze("toast"))
		expect.equal(finish.progress, 0)
	end)

	t.test("claimed quests, starter ids and unknown templates in the list never move", function()
		local claimed = entry("squeeze_any", 5)
		claimed.claimed = true
		local unknown = entry("gone_template", 5)
		local starterLike = entry("starter_squeeze", 20)
		expect.deepEqual(QuestLogic.apply({ claimed, unknown, starterLike }, squeeze("toast")), {})
		expect.equal(claimed.progress, 0)
		expect.equal(unknown.progress, 0)
		expect.equal(starterLike.progress, 0)
	end)

	-- starter tasks -------------------------------------------------------------------------------------------------

	t.test("every accepted squeeze moves starter_squeeze; starter_jelly is gone (build plan Phase 6)", function()
		local starter = freshStarter()
		expect.deepEqual(QuestLogic.applyStarter(starter, squeeze("toast")), { "starter_squeeze" })
		-- An old-style event's tier changes nothing.
		local old = { kind = "squeeze", squishyId = "toast", tier = 4 } :: any
		expect.deepEqual(QuestLogic.applyStarter(starter, old), { "starter_squeeze" })
		expect.equal(starter.progress.starter_squeeze, 2)
		expect.equal(starter.progress.starter_jelly, nil)
	end)

	t.test("a slow-training tick, a level-up or a profile load leave every starter task unchanged", function()
		-- QuestLogic only knows squeeze, duel, hit and practiceHit events; QuestService never feeds it Grip events.
		local starter = freshStarter()
		for _, kind in { "afkTick", "levelUp", "load", "gripTick" } do
			expect.deepEqual(QuestLogic.applyStarter(starter, { kind = kind, tier = 4 } :: any), {})
			expect.deepEqual(QuestLogic.apply({ entry("squeeze_any", 5) }, { kind = kind, tier = 4 } :: any), {})
		end
		expect.deepEqual(starter, freshStarter())
	end)

	t.test("starter practice and duel tasks; progress stops at the goal; claimed tasks never move", function()
		local starter = freshStarter()
		for _ = 1, 7 do
			QuestLogic.applyStarter(starter, { kind = "practiceHit" })
		end
		expect.equal(starter.progress.starter_practice, 5)
		QuestLogic.applyStarter(starter, duel("cancelled", "toast", 9))
		expect.equal(starter.progress.starter_duel, nil)
		expect.deepEqual(QuestLogic.applyStarter(starter, duel("loss", "toast", MIN_THROWS)), { "starter_duel" })
		expect.equal(starter.progress.starter_duel, 1)
		starter.claimed.starter_squeeze = true
		expect.deepEqual(QuestLogic.applyStarter(starter, squeeze("toast")), {})
		expect.equal(starter.progress.starter_squeeze, nil)
	end)

	t.test(
		"starterView lists every starter task with progress, goal, reward, done and claimed (not starter_jelly)",
		function()
			local starter = {
				progress = { starter_squeeze = 20, starter_jelly = 4, starter_practice = 99 },
				claimed = {
					starter_squeeze = true,
				},
			}
			expect.deepEqual(QuestLogic.starterView(starter), {
				{ id = "starter_squeeze", progress = 20, goal = 20, reward = 100, done = true, claimed = true },
				{ id = "starter_practice", progress = 5, goal = 5, reward = 50, done = true, claimed = false },
				{ id = "starter_duel", progress = 0, goal = 1, reward = 150, done = false, claimed = false },
			})
		end
	)

	-- rollover ---------------------------------------------------------------------------------------------------------

	t.test("rollover auto-claims done-but-unclaimed quests of an old day; the same day does nothing", function()
		local doneUnclaimed = entry("squeeze_any", 1)
		doneUnclaimed.done = true
		doneUnclaimed.progress = 1
		local doneClaimed = entry("duel_win", 1)
		doneClaimed.done = true
		doneClaimed.claimed = true
		local unfinished = entry("practice_hits", 20)
		local quests = { day = DAY - 1, swapsUsed = 1, active = { doneUnclaimed, doneClaimed, unfinished } }
		local result = QuestLogic.rollover(quests, DAY)
		expect.truthy(result.regenerate)
		expect.equal(#result.autoClaim, 1)
		expect.equal(result.autoClaim[1], doneUnclaimed) -- the stored entry itself (QuestService marks it claimed)
		local same = QuestLogic.rollover({ day = DAY, swapsUsed = 0, active = { doneUnclaimed } }, DAY)
		expect.deepEqual(same, { autoClaim = {}, regenerate = false })
		local newPlayer = QuestLogic.rollover({ day = -1, swapsUsed = 0, active = {} }, DAY)
		expect.deepEqual(newPlayer, { autoClaim = {}, regenerate = true })
	end)

	-- weekly quests (2026-10-17) -----------------------------------------------------------------------------------

	t.test("generateWeekly: every weekly quest in order, ids w<week>_<slot>, goal and reward, no squishy", function()
		local defs = QuestDefs.weekly()
		local list = QuestLogic.generateWeekly(2856)
		expect.equal(#list, #defs)
		expect.equal(#list, 4)
		for slot, def in defs do
			expect.deepEqual(list[slot], {
				id = string.format("w2856_%d", slot),
				def = def.id,
				progress = 0,
				goal = def.variants[1].goal,
				reward = def.variants[1].reward,
				done = false,
				claimed = false,
			})
		end
		expect.deepEqual(QuestLogic.generateWeekly(2857)[1].def, list[1].def) -- the same list every week
		expect.equal(QuestLogic.generateWeekly(2857)[1].id, "w2857_1")
	end)

	t.test("apply moves weekly quests with the daily kinds' rules and stops at the goal", function()
		local list = QuestLogic.generateWeekly(7) -- squeeze, duel win, duel finish, practice
		list[1].goal = 2
		for _ = 1, 3 do
			QuestLogic.apply(list, squeeze("toast"))
		end
		expect.equal(list[1].progress, 2)
		expect.truthy(list[1].done)
		local lines = QuestLogic.apply(list, duel("win", "toast", MIN_THROWS - 1))
		expect.deepEqual(lines, { { questId = "w7_2", progress = 1, goal = list[2].goal, done = false } })
		QuestLogic.apply(list, duel("loss", "toast", MIN_THROWS))
		expect.equal(list[2].progress, 1)
		expect.equal(list[3].progress, 1)
		QuestLogic.apply(list, { kind = "practiceHit" })
		QuestLogic.apply(list, duel("void", "toast", 9))
		expect.equal(list[4].progress, 1)
		expect.equal(list[3].progress, 1)
	end)
end
