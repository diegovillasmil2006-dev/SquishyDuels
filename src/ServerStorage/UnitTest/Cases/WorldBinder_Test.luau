--!strict
-- WorldBinder_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.WorldBinder.
-- Server only (ServerStorage.UnitTest). init() is never called (no LocalPlayer in Edit), so nothing is bound.
-- Contract (DESIGN §7.6, §7.7, §17.6):
--   * stand prompts are enabled only while a UI handler is registered for the tag (register/unregister; unknown tags
--     are refused);
--   * audio zones: the highest priority containing zone wins (the squeeze zone inside the lobby zone), nil outside;
--   * the Jelly gates, pod signs and lock decor are gone with the giant pads (build plan Phase 6): no gateShouldBlock,
--     padNear, lockVisible, podSignText or setGripSource;
--   * Part 8 (tools/mcp/stand-prompts.lua relies on it): the 7 stand tags, one prompt per tagged stand (6 stands + 14
--     pedestals = 20 since the design's collection, D4), each prompt key (and alt key) with a Strings text.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local WorldBinder = t.requireClient("Controllers/WorldBinder")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local Strings = t.requireShared("Strings")

	t.test("stand handlers: register, unregister, unknown tags refused", function()
		local tag = "SD_QuestBoard"
		expect.equal(WorldBinder.isStandRegistered(tag), false)
		local unregister = WorldBinder.registerStand(tag, function() end)
		expect.equal(WorldBinder.isStandRegistered(tag), true)
		unregister()
		expect.equal(WorldBinder.isStandRegistered(tag), false)
		unregister() -- idempotent
		expect.throws(function()
			WorldBinder.registerStand("SD_Sign", function() end)
		end, "not a stand tag")
		for _, standTag in WorldBinder.standTags() do
			expect.truthy(string.sub(standTag, 1, 3) == "SD_")
		end
	end)

	t.test("audio zones: highest priority wins, nil outside", function()
		local candidates = {}
		for _, zone in WorldLayout.AudioZones do
			table.insert(candidates, {
				zoneId = zone.zoneId,
				priority = zone.priority,
				musicKey = zone.musicKey,
				ambienceKey = zone.ambienceKey,
				musicMul = zone.musicMul,
				cframe = CFrame.new(zone.position),
				size = zone.size,
			})
		end
		local spawn = WorldBinder.pickZone(candidates, Vector3.new(0, 3, 0)) -- the hub spawn's medallion
		expect.equal(spawn and spawn.zoneId, "lobby")
		local mat = WorldBinder.pickZone(candidates, Vector3.new(-64, 3, 0)) -- foam mat 2
		expect.equal(mat and mat.zoneId, "squeeze")
		local range = WorldBinder.pickZone(candidates, Vector3.new(75, 3, 0)) -- the practice lane
		expect.equal(range and range.zoneId, "practice")
		local plot = WorldBinder.pickZone(candidates, Vector3.new(0, 3, -122)) -- plot 1, north of the hub
		expect.equal(plot and plot.zoneId, "lobby")
		expect.equal(WorldBinder.pickZone(candidates, Vector3.new(400, 3, 0)), nil)
	end)

	t.test("the Jelly gate, pod sign and lock decor helpers are gone (build plan Phase 6)", function()
		for _, name in { "gateShouldBlock", "padNear", "lockVisible", "podSignText", "setGripSource" } do
			expect.equal((WorldBinder :: any)[name], nil)
		end
	end)

	t.test(
		"stand prompts (Part 8 check): 7 stand tags, 20 prompts (6 stands + 14 pedestals), every text known",
		function()
			local tags = WorldBinder.standTags()
			table.sort(tags)
			expect.deepEqual(tags, {
				"SD_BoxStand",
				"SD_CollectionKiosk",
				"SD_CollectionPedestal",
				"SD_DailyStand",
				"SD_QuestBoard",
				"SD_QueuePodium",
				"SD_ShopCounter",
			})
			-- One prompt per tagged stand: the tag counts add up to the prompts the lobby carries.
			local tagged = 0
			for _, tag in tags do
				local count = WorldLayout.TagCounts[tag]
				expect.truthy(type(count) == "number" and count >= 1)
				tagged += count
			end
			local stands = {
				WorldLayout.QuestBoard,
				WorldLayout.DailyStand,
				WorldLayout.DuelGate,
				WorldLayout.GiftBoxCounter,
				WorldLayout.ShopCounter,
				WorldLayout.Collection,
			}
			local pedestals = WorldLayout.Collection.pedestals
			expect.equal(#stands + #pedestals, 20)
			expect.equal(tagged, 20)
			local specs: { any } = {}
			for _, stand in stands do
				table.insert(specs, (stand :: any).prompt)
			end
			for _, pedestal in pedestals do
				table.insert(specs, pedestal.prompt)
			end
			for _, spec in specs do
				expect.truthy(type(Strings.resolve(spec.actionKey)) == "string")
				if spec.altActionKey then
					expect.truthy(type(Strings.resolve(spec.altActionKey)) == "string")
				end
			end
		end
	)
end
