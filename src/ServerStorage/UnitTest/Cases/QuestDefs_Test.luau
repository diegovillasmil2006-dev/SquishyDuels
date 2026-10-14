--!strict
-- QuestDefs_Test: unit tests for ReplicatedStorage.Shared.QuestDefs. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.8, §17.10): the 7 daily templates with their §6.8 targets and Coins, categories and counting
-- rules; the 3 starter tasks (squeeze 20/100, practice 5/50, duel 1/150; starter_jelly and minTier went with the giant
-- pads, build plan Phase 6); every textPair
-- resolves to a Strings {one, many} pair and text() fills {n} and {squishy} with the right plural; the lists are frozen
-- and get() rejects unknown ids. Tables are compared by value.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- §6.8: id -> category, counts, needsSquishy, { {goal, reward} }.
local DAILY: { { any } } = {
	{ "squeeze_any", "squeeze", "squeeze", false, { { 100, 150 }, { 150, 200 } } },
	{ "squeeze_with", "squeeze", "squeezeWith", true, { { 60, 200 } } },
	{ "duel_finish", "duel", "duelFinish", false, { { 2, 200 }, { 3, 300 } } },
	{ "duel_win", "duel", "duelWin", false, { { 1, 250 }, { 2, 400 } } },
	{ "duel_win_with", "duel", "duelWinWith", true, { { 1, 300 }, { 2, 450 } } },
	{ "hits_with", "duel", "hitsWith", true, { { 8, 250 }, { 12, 300 } } },
	{ "practice_hits", "practice", "practiceHit", false, { { 20, 100 } } },
}

-- §6.8: id -> category, counts, goal, reward.
local STARTER: { { any } } = {
	{ "starter_squeeze", "squeeze", "squeeze", 20, 100 },
	{ "starter_practice", "practice", "practiceHit", 5, 50 },
	{ "starter_duel", "duel", "duelFinish", 1, 150 },
}

return function(t: Context)
	local QuestDefs = t.requireShared("QuestDefs")
	local Strings = t.requireShared("Strings")
	local expect = t.expect

	local function variantsOf(def: any): { { number } }
		local out = {}
		for _, variant in def.variants do
			table.insert(out, { variant.goal, variant.reward })
		end
		return out
	end

	t.test("the 7 daily templates hold the §6.8 targets, Coins and counting rules, in order", function()
		local daily = QuestDefs.daily()
		expect.equal(#daily, #DAILY)
		for index, row in DAILY do
			local def = daily[index]
			expect.equal(def.id, row[1])
			expect.equal(def.kind, "daily")
			expect.equal(def.category, row[2])
			expect.equal(def.counts, row[3])
			expect.equal(def.needsSquishy, row[4])
			expect.deepEqual(variantsOf(def), row[5])
			expect.equal((def :: any).minTier, nil)
			expect.equal(QuestDefs.get(row[1]), def)
		end
	end)

	t.test("the 3 starter tasks: squeeze 20/100, practice 5/50, duel 1/150 (no starter_jelly since Phase 6)", function()
		local starter = QuestDefs.starter()
		expect.equal(#starter, #STARTER)
		for index, row in STARTER do
			local def = starter[index]
			expect.equal(def.id, row[1])
			expect.equal(def.kind, "starter")
			expect.equal(def.category, row[2])
			expect.equal(def.counts, row[3])
			expect.equal(def.needsSquishy, false)
			expect.deepEqual(variantsOf(def), { { row[4], row[5] } })
			expect.equal((def :: any).minTier, nil)
			expect.truthy(string.match(def.id, "^starter_[a-z]+$") ~= nil)
		end
		expect.equal(QuestDefs.get("starter_jelly"), nil)
	end)

	t.test("list() is the daily templates, then the starter tasks", function()
		local ids = {}
		for _, def in QuestDefs.list() do
			table.insert(ids, def.id)
		end
		local expected = {}
		for _, row in DAILY do
			table.insert(expected, row[1])
		end
		for _, row in STARTER do
			table.insert(expected, row[1])
		end
		expect.deepEqual(ids, expected)
	end)

	t.test("every textPair names a Strings {one, many} pair", function()
		for _, def in QuestDefs.list() do
			for _, form in { "one", "many" } do
				local text = Strings.resolve(`{def.textPair}.{form}`)
				if type(text) ~= "string" or text == "" then
					error(`{def.id}: no Strings text {def.textPair}.{form}`)
				end
			end
		end
	end)

	t.test("text() picks the plural form and fills {n} and {squishy}", function()
		expect.equal(QuestDefs.text("squeeze_any", 100), "Squeeze squishies 100 times")
		expect.equal(QuestDefs.text("squeeze_with", 60, "Toast"), "Squeeze Toast 60 times")
		expect.equal(QuestDefs.text("duel_finish", 2), "Finish 2 duels")
		expect.equal(QuestDefs.text("duel_win", 1), "Win 1 duel")
		expect.equal(QuestDefs.text("duel_win_with", 1, "Dragon"), "Defeat 1 player using Dragon")
		expect.equal(QuestDefs.text("duel_win_with", 2, "Dragon"), "Defeat 2 players using Dragon")
		expect.equal(QuestDefs.text("hits_with", 8, "Birdie"), "Land 8 hits with Birdie")
		expect.equal(QuestDefs.text("practice_hits", 20), "Hit 20 practice targets")
		expect.equal(QuestDefs.text("starter_squeeze", 20), "Squeeze 20 times")
		expect.equal(QuestDefs.text("starter_practice", 5), "Hit 5 practice targets")
		expect.equal(QuestDefs.text("starter_duel", 1), "Finish your first duel")
		expect.equal(QuestDefs.text("starter_jelly", 10), "") -- gone with the giant pads (Phase 6)
		expect.equal(QuestDefs.text("nope", 3), "")
	end)

	t.test("the daily templates cover the squeeze, duel and practice categories", function()
		local seen: { [string]: boolean } = {}
		for _, def in QuestDefs.daily() do
			seen[def.category] = true
		end
		expect.deepEqual(seen, { squeeze = true, duel = true, practice = true })
	end)

	t.test("get() rejects unknown ids; the definitions are frozen", function()
		expect.equal(QuestDefs.get("nope"), nil)
		expect.equal(QuestDefs.get(nil), nil)
		expect.equal(QuestDefs.get(3), nil)
		for _, def in QuestDefs.list() do
			expect.truthy(table.isfrozen(def))
			expect.truthy(table.isfrozen(def.variants))
			expect.truthy(table.isfrozen(def.variants[1]))
		end
		local daily = QuestDefs.daily()
		table.remove(daily)
		expect.equal(#QuestDefs.daily(), #DAILY)
	end)
end
