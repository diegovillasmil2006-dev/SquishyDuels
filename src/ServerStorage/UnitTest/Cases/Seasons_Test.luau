--!strict
-- Seasons_Test: unit tests for ReplicatedStorage.Shared.Seasons and Config/Christmas (big job item 11, 2026-11-10: the
-- Christmas event, built and off until the owner sets its end date). Server only (ServerStorage.UnitTest). Pure.
-- Contract:
--   * isOn(untilAt, now): only while the end is a real time still ahead of now (no end, a broken one, a past one: off);
--   * defs(owned, on): the year-round squishies in catalog order, then each seasonal one that is on sale or owned;
--   * left(untilAt, now): the time left as the update countdown writes it, nil while off;
--   * the switch is the experience config `event_christmas`, published as the Workspace attribute SD_ChristmasUntil.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Seasons = t.requireShared("Seasons")
	local Catalog = t.requireShared("Catalog")
	local Christmas = t.requireShared("Config/Christmas")

	local function ids(list: { any }): { string }
		local out = {}
		for _, def in list do
			table.insert(out, def.id)
		end
		return out
	end

	t.test("isOn: only while the end is a real time ahead of now", function()
		expect.equal(Seasons.isOn(1000, 999), true)
		expect.equal(Seasons.isOn(1000, 1000), false)
		expect.equal(Seasons.isOn(1000, 1001), false)
		for _, bad in { "1000", 0 / 0, math.huge, true, {} } :: { any } do
			expect.equal(Seasons.isOn(bad, 5), false)
		end
		expect.equal(Seasons.isOn(nil, 5), false) -- no date set: the event is off
		expect.equal(Seasons.isOn(1000, nil), false)
	end)

	t.test("defs: the year-round squishies, then a seasonal one only while on sale or owned", function()
		local yearRound = ids(Catalog.list())
		expect.deepEqual(ids(Seasons.defs(nil, false)), yearRound)
		expect.deepEqual(ids(Seasons.defs({ toast = { at = 1 } }, false)), yearRound)
		expect.deepEqual(ids(Seasons.defs("garbage", false)), yearRound)
		local withPuffin = table.clone(yearRound)
		table.insert(withPuffin, "peppermint_puffin")
		expect.deepEqual(ids(Seasons.defs({ peppermint_puffin = { at = 1 } }, false)), withPuffin) -- owned: all year
		expect.deepEqual(ids(Seasons.defs(nil, true)), ids(Catalog.all())) -- on sale: both
		expect.deepEqual(ids(Seasons.defs(nil, "yes")), yearRound) -- only true turns it on
	end)

	t.test("left: the time left while it is on, as the update countdown writes it", function()
		expect.equal(Seasons.left(1000 + 2 * 86400 + 5 * 3600, 1000), "2d 05h")
		expect.equal(Seasons.left(1000 + 3 * 3600 + 12 * 60, 1000), "3h 12m")
		expect.equal(Seasons.left(1000, 1000), nil)
		expect.equal(Seasons.left(nil, 1000), nil)
	end)

	t.test("pill: the season's line takes the first seconds of every turn, only while on and no hourly event is live", function()
		local Strings = t.requireShared("Strings")
		local untilAt = 1000 + 86400
		local line = Strings.format(Strings.season.christmas.pill, { time = "1d 00h" })
		expect.equal(Seasons.pill("Candy rain in 4:08", false, untilAt, 1000), line)
		expect.equal(Seasons.pill("Candy rain in 4:08", false, untilAt, 1000 + Seasons.PILL_SECONDS), "Candy rain in 4:08")
		expect.equal(Seasons.pill("Candy rain!", true, untilAt, 1000), "Candy rain!") -- a live hourly event keeps the pill
		expect.equal(Seasons.pill("Update in 2d 05h", false, nil, 1000), "Update in 2d 05h") -- the season is off
		expect.equal(Seasons.pill("Update in 2d 05h", false, 999, 1000), "Update in 2d 05h") -- it has ended
	end)

	t.test("the snow: one light emitter (few flakes, small, slow)", function()
		local snow = Christmas.snow
		expect.truthy(snow.rate * snow.lifetime[2] <= 200) -- flakes alive at once
		expect.truthy(snow.sizeStuds[1] > 0 and snow.sizeStuds[1] <= snow.sizeStuds[2] and snow.sizeStuds[2] <= 0.6)
		expect.truthy(snow.speed[1] > 0 and snow.speed[1] <= snow.speed[2])
		expect.truthy(snow.lifetime[1] > 0 and snow.lifetime[1] <= snow.lifetime[2])
		expect.truthy(snow.speed[2] * snow.lifetime[2] >= snow.heightStuds) -- a flake can reach the ground
	end)

	t.test("the switch: one event, its config name and its attribute", function()
		expect.equal(Seasons.EVENT, "christmas")
		expect.equal(Christmas.event, Seasons.EVENT)
		expect.equal(Christmas.config, "event_christmas")
		expect.equal(Seasons.ATTRIBUTE, "SD_ChristmasUntil")
		expect.equal(#Catalog.seasonal(Seasons.EVENT), 2)
	end)
end
