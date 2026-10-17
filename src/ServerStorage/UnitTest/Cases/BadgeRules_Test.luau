--!strict
-- BadgeRules_Test: ServerScriptService.Server.Logic.BadgeRules, which badges a profile has earned (Batch 3, review #10;
-- the user's badges, Config.Social.Badges). Server only (ServerStorage.UnitTest). Pure: plain profile tables.
-- Contract: every rule kind just below and at its threshold (Grip Lv 49 / 50, the duel stats); all 5 Commons (the
-- starter among them); the Dragon; the session flag; joined is always earned; an unknown rule kind earns nothing; the
-- shipped list is the plan's 12 badges less the 3 capsule ones (pens3 phase 2: an old save's capsules earn nothing).

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
		}
	end

	local function earned(p: any, level: number?, flags: { [string]: boolean }?): { [string]: boolean }
		return BadgeRules.earned(p, level or 1, flags or {}, Config.Social.Badges.list)
	end

	t.test("the shipped list: the plan's 12 badges less the 3 capsule ones, in order", function()
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

	-- Pens3 phase 2: capsuleSlots and capsuleLevel are no rule kinds any more; an old save's capsules earn nothing.
	t.test("an old save's capsules earn nothing: the capsule rule kinds are gone", function()
		local p = profile()
		p.capsules = { slots = 4, list = { { level = 100, squishyId = "kitty_bread" } } }
		local list = {
			{ key = "capsule_2", rule = { kind = "capsuleSlots", atLeast = 2 } },
			{ key = "capsule_royal", rule = { kind = "capsuleLevel", atLeast = 91 } },
		}
		expect.deepEqual(BadgeRules.earned(p, 1, {}, list), {})
		expect.deepEqual(earned(p), { welcome = true })
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
