--!strict
-- WorldBinder_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.WorldBinder.
-- Server only (ServerStorage.UnitTest). init() is never called (no LocalPlayer in Edit), so nothing is bound.
-- Contract (DESIGN §7.6, §7.7, §17.6):
--   * stand prompts are enabled only while a UI handler is registered for the tag (register/unregister; unknown tags
--     are refused);
--   * audio zones: the highest priority containing zone wins (the squeeze zone inside the lobby zone), nil outside;
--   * jelly gates (a latch): an open gate closes for a too-low level only once the viewer is beyond radius + padding
--     (anti-trap); a closed gate stays closed for a too-low level however close the viewer presses (a root against
--     the wall is within radius + padding), and opens only for a high enough level or a viewer inside the radius;
--   * a gate, pod sign or lock decor takes its pad (and so its tier) from WorldLayout by position, never from
--     GripTier;
--   * pod sign `Live` text: grip.signLocked "Needs Grip Lv {level} · You: Lv {have}" while locked,
--     grip.signOpen "Open · +{coins} Coins · x{mult} Grip" once open, from Config.Grip.Pads;
--   * the design's lock + rope decor (phase 3 D5, SD_GripLock): shown as built while the level is unknown, and per
--     viewer only while that viewer's level is below the pad's;
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
	local Config = t.requireShared("Config")
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
		local spawn = WorldBinder.pickZone(candidates, Vector3.new(0, 3, 0)) -- the design medallion
		expect.equal(spawn and spawn.zoneId, "lobby")
		local mat = WorldBinder.pickZone(candidates, Vector3.new(-47.58, 3, 42.65)) -- foam mat 2
		expect.equal(mat and mat.zoneId, "squeeze")
		local range = WorldBinder.pickZone(candidates, Vector3.new(99, 3, 62)) -- the middle lane
		expect.equal(range and range.zoneId, "practice")
		expect.equal(WorldBinder.pickZone(candidates, Vector3.new(400, 3, 0)), nil)
	end)

	t.test("an open gate closes for a too-low level only outside the anti-trap ring", function()
		-- Jelly gate: radius 6, padding 1.
		expect.equal(WorldBinder.gateShouldBlock(3, 5, 20, 6, 1), true)
		expect.equal(WorldBinder.gateShouldBlock(3, 5, 20, 6, 1, false), true)
		expect.equal(WorldBinder.gateShouldBlock(3, 5, 7, 6, 1, false), false) -- in the ring: never shut in
		expect.equal(WorldBinder.gateShouldBlock(3, 5, 2, 6, 1, false), false) -- inside the jelly
		expect.equal(WorldBinder.gateShouldBlock(5, 5, 20, 6, 1, false), false) -- unlocked
		expect.equal(WorldBinder.gateShouldBlock(40, 30, 20, 7, 1, false), false)
	end)

	-- §17.6 "only while the viewer's level is too low": a closed gate must stop someone pressing against it. An R15
	-- root pressed on the jelly wall is 0.5-1.0 studs out (6.5-7.0 from the axis of a radius-6 gate), inside the
	-- radius + 1 ring, so a plain distance test opened the gate and let the player walk in.
	t.test("a closed gate stays closed for a too-low level however close the viewer presses", function()
		local jelly = WorldLayout.GiantPads.jelly
		local radius = jelly.gate.diameter / 2
		local padding = Config.Grip.Gate.antiTrapPadding
		local required = Config.Grip.Pads[jelly.tier].level
		for _, distance in { radius + 0.5, radius + 1.0, radius + padding, radius, 20 } do
			expect.equal(WorldBinder.gateShouldBlock(required - 1, required, distance, radius, padding, true), true)
		end
		-- A high enough level opens it wherever the viewer stands.
		expect.equal(WorldBinder.gateShouldBlock(required, required, radius + 0.5, radius, padding, true), false)
		-- A viewer somehow inside the jelly (teleported, respawned) is let out.
		expect.equal(WorldBinder.gateShouldBlock(required - 1, required, radius - 1, radius, padding, true), false)
	end)

	t.test("a walk up to a locked gate: it closes far out and never opens on contact", function()
		local radius, padding = 6, 1
		local blocking = false
		for _, distance in { 15, 10, 8, 7.5, 7, 6.6, 6.5, 6.5, 7, 12 } do
			blocking = WorldBinder.gateShouldBlock(3, 5, distance, radius, padding, blocking)
			expect.equal(blocking, true)
		end
	end)

	t.test("gates, pod signs and lock decor find their pad by position (WorldLayout), not by GripTier", function()
		-- Compared by blueprintId: WorldBinder requires the real Shared, the test runner a clone, so the tables differ.
		local function idOf(found: any): string?
			return if found ~= nil then found.blueprintId else nil
		end
		local signs: { [string]: any } = {}
		for _, sign in WorldLayout.Signs do
			signs[sign.id] = sign
		end
		for _, key in WorldLayout.GiantPadKeys do
			local pad = WorldLayout.GiantPads[key]
			-- The gate sits on the pad centre, the lock decor pivots there, the pod sign plate stands in front of it.
			expect.equal(idOf(WorldBinder.padNear(pad.gate.position)), pad.blueprintId)
			expect.equal(idOf(WorldBinder.padNear(pad.center)), pad.blueprintId)
			expect.equal(idOf(WorldBinder.padNear(signs[pad.signId].position)), pad.blueprintId)
		end
		expect.equal(WorldBinder.padNear(Vector3.new(0, 4.5, 0)), nil) -- the spawn: no pad nearby
	end)

	t.test("the lock + rope decor shows as built while the level is unknown, then only for a too-low level", function()
		expect.equal(WorldBinder.lockVisible(nil, 5), true)
		expect.equal(WorldBinder.lockVisible(1, 5), true)
		expect.equal(WorldBinder.lockVisible(4, 5), true)
		expect.equal(WorldBinder.lockVisible(5, 5), false)
		expect.equal(WorldBinder.lockVisible(40, 30), false)
	end)

	t.test("pod sign live text follows Config.Grip.Pads and Strings", function()
		local pads = Config.Grip.Pads
		local marshmallow = pads[3]
		local locked = WorldBinder.podSignText(9, 3)
		expect.equal(
			locked,
			Strings.format(Strings.resolve("grip.signLocked") :: string, { level = marshmallow.level, have = 9 })
		)
		expect.truthy(string.find(locked :: string, tostring(marshmallow.level), 1, true) ~= nil)
		local open = WorldBinder.podSignText(marshmallow.level, 3)
		expect.equal(
			open,
			Strings.format(
				Strings.resolve("grip.signOpen") :: string,
				{ coins = marshmallow.coinBonus, mult = marshmallow.gripPercent / 100 }
			)
		)
		expect.equal(WorldBinder.podSignText(10, 99), nil) -- unknown tier: the baked text stays
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
