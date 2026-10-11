--!strict
-- KeyText_Test: StarterPlayerScripts.Client.UI.KeyText (text by Strings key at run time). Server only
-- (ServerStorage.UnitTest). Pure apart from one warning per missing key.
-- Contract (DESIGN §2.11: no player-facing literals outside Strings):
--   * get(key, args) is the Strings text, formatted; has(key) tells whether it exists;
--   * plural(key, n, args) picks one / many and passes {n};
--   * a missing key returns the key itself (a visible gap, never a blank label).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local KeyText = t.requireClient("UI/KeyText")
	local Strings = t.requireShared("Strings")

	t.test("get and has", function()
		expect.equal(KeyText.get("common.close"), Strings.common.close)
		expect.equal(
			KeyText.get("inventory.collected", { n = 3, total = 8 }),
			Strings.format(Strings.inventory.collected, { n = 3, total = 8 })
		)
		expect.equal(KeyText.has("common.close"), true)
		expect.equal(KeyText.has("common.noSuchKey"), false)
		expect.equal(KeyText.has("common"), false) -- a table, not a text
	end)

	t.test("plural: one / many with {n}", function()
		local pair = Strings.common.needCoins
		expect.equal(KeyText.plural("common.needCoins", 1, { missing = 1 }), Strings.format(pair.one, { missing = 1 }))
		expect.equal(KeyText.plural("common.needCoins", 5, { missing = 5 }), Strings.format(pair.many, { missing = 5 }))
		local lives = Strings.duel.lives
		expect.equal(KeyText.plural("duel.lives", 2), Strings.format(lives.many, { n = 2 }))
	end)

	t.test("missing keys show the key itself", function()
		expect.equal(KeyText.get("common.noSuchKey"), "common.noSuchKey")
		expect.equal(KeyText.plural("common.close", 2), "common.close") -- not a { one, many } pair
	end)
end
