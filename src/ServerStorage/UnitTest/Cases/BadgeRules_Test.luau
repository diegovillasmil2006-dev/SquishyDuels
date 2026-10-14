--!strict
-- BadgeRules_Test: ServerScriptService.Server.Logic.BadgeRules, which badges a profile has earned (Batch 3, review #10;
-- the user's 12 badges, Config.Social.Badges). Server only (ServerStorage.UnitTest). Pure: plain profile tables.
-- Contract: every rule kind just below and at its threshold (capsule Lv 10 / 11 and 90 / 91, Grip Lv 49 / 50, 1 and 2
-- capsule slots, the duel stats); all 5 Commons (the starter among them); the Dragon; the session flag; joined is
-- always earned; an unknown rule kind earns nothing; the shipped list is the plan's 12 badges with their rules.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BadgeRules = t.requireServer("Logic/BadgeRules")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")

	local function profile(): any
		return {
			owned = { kitty_bread = { at = 1, src = "starter" } },
			stats = { duelsPlayed = 0, duelsWon = 0 },
			capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } },
		}
	end

	local function earned(p: any, level: number?, flags: { [string]: boolean }?): { [string]: boolean }
		return BadgeRules.earned(p, level or 1, flags or {}, Config.Social.Badges.list)
	end

	t.test("the shipped list: the plan's 12 badges with their rules, in order", function()
		local keys = {}
		for _, badge in Config.Social.Badges.list do
			table.insert(keys, badge.key)
		end
		expect.deepEqual(keys, {
			"welcome",
			"first_duel",
			"first_win",
			"wins_10",
			"wins_100",
			"duel_buddies",
			"capsule_2",
			"capsule_jelly",
			"capsule_royal",
			"grip_master",
			"commons_all",
			"dragon",
		})
	end)

	t.test("a new player has only welcome", function()
		expect.deepEqual(earned(profile()), { welcome = true })
	end)

	t.test("duel stats: 1 duel, 1, 10 and 100 wins (just below earns nothing)", function()
		local p = profile()
		p.stats.duelsPlayed = 1
		expect.truthy(earned(p).first_duel)
		expect.falsy(earned(p).first_win)
		p.stats.duelsWon = 1
		expect.truthy(earned(p).first_win)
		p.stats.duelsWon = 9
		expect.falsy(earned(p).wins_10)
		p.stats.duelsWon = 10
		expect.truthy(earned(p).wins_10)
		p.stats.duelsWon = 99
		expect.falsy(earned(p).wins_100)
		p.stats.duelsWon = 100
		expect.truthy(earned(p).wins_100)
	end)

	t.test("capsules: a second slot, the best capsule at Lv 11 (Jelly) and Lv 91 (Royal)", function()
		local p = profile()
		expect.falsy(earned(p).capsule_2)
		p.capsules = { slots = 2, list = { { level = 10 }, { level = 3 } } }
		expect.truthy(earned(p).capsule_2)
		expect.falsy(earned(p).capsule_jelly)
		p.capsules.list[2].level = 11
		expect.truthy(earned(p).capsule_jelly)
		p.capsules.list[1].level = 90
		expect.falsy(earned(p).capsule_royal)
		p.capsules.list[1].level = 91
		expect.truthy(earned(p).capsule_royal)
	end)

	t.test("Grip Master at Grip Lv 50, not 49", function()
		expect.falsy(earned(profile(), 49).grip_master)
		expect.truthy(earned(profile(), 50).grip_master)
	end)

	t.test("every Common (the starter among them) and the Dragon", function()
		local p = profile()
		local commons = Catalog.byRarity("Common")
		expect.equal(#commons, 5)
		for index = 1, #commons - 1 do
			p.owned[commons[index].id] = { at = 1, src = "shop" }
		end
		expect.falsy(earned(p).commons_all)
		p.owned[commons[#commons].id] = { at = 1, src = "shop" }
		expect.truthy(earned(p).commons_all)
		expect.falsy(earned(p).dragon)
		p.owned.dragon = { at = 1, src = "shop" }
		expect.truthy(earned(p).dragon)
	end)

	t.test("Duel Buddies comes from the session flag", function()
		expect.falsy(earned(profile()).duel_buddies)
		expect.truthy(earned(profile(), 1, { duelBuddies = true }).duel_buddies)
	end)

	t.test("an unknown rule kind or a broken profile earns nothing and never errors", function()
		local list = {
			{ key = "odd", rule = { kind = "luckyBox" } },
			{ key = "fine", rule = { kind = "joined" } },
		}
		expect.deepEqual(BadgeRules.earned(profile(), 1, {}, list), { fine = true })
		expect.deepEqual(BadgeRules.earned({}, 1, {}, Config.Social.Badges.list), { welcome = true })
	end)
end
