--!strict
-- InspectFormat_Test: the Inspect panel data and rules of StarterPlayerScripts.Client.UI.InspectFormat. Server only
-- (ServerStorage.UnitTest). Pure: no instances, no LocalPlayer.
-- Contract (DESIGN §10.1, §10.4, §10.7-§10.9):
--   * view(id, ctx) for all 14 squishies: every field comes from Catalog, Config, Boxes and Strings (name, rarity,
--     its capsule power "x{n} power" (Phase 5: CapsuleMath.squishyPower) over "Capsule Coins multiplier", the five stat
--     bars of InventoryFormat.statBars fully resolved, the trail (Commons "No
--     trail"), Dragon's ultimate from Config.Abilities, "Elimination: Standard", the Catalog `inspect` view); unowned
--     shows "Preview · Not owned" and "How to get" = one line per Boxes.containing row (the free Treat Box too) with
--     its exact percent, then "Shop: {price} Coins"; owned shows no How to get; View in Shop needs an unowned squishy
--     with a price and the shop screen; an unknown id gives nil;
--   * equipState follows the Squishies screen (InventoryFormat.equipState);
--   * openAction: Closed opens; otherwise the same id does nothing and another id selects;
--   * previewAllowed: at most Preview.maxPerSecond (8) in any 1 s, the input list untouched;
--   * closeToastKey: "matched" -> queue.opponentFound ("Opponent found!"), else nil;
--   * dotCount: inspectDotsMin (Common) .. inspectDotsMax (Exclusive), halved under ReducedMotion, at least 1;
--     dotSample: a dot that slows to a stop at dotLifeSeconds while it fades and shrinks.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local STAT_ORDER = { "speed", "size", "reload", "windup", "arc" }

return function(t: Context)
	local expect = t.expect
	local InspectFormat = t.requireClient("UI/InspectFormat")
	local InventoryFormat = t.requireClient("UI/InventoryFormat")
	local BoxFormat = t.requireClient("UI/BoxFormat")
	local Boxes = t.requireShared("Boxes")
	local CapsuleMath = t.requireShared("CapsuleMath")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Format = t.requireShared("Util/Format")
	local Rarity = t.requireShared("Rarity")
	local RarityStyle = t.requireShared("Art/RarityStyle")
	local Strings = t.requireShared("Strings")

	local UNOWNED = { owned = false, equipped = false, shopAvailable = true }

	local function sameSequence(actual: ColorSequence?, expected: ColorSequence?)
		if actual == nil or expected == nil then
			expect.equal(actual, expected)
			return
		end
		expect.equal(#actual.Keypoints, #expected.Keypoints)
		for i, keypoint in actual.Keypoints do
			local other = expected.Keypoints[i]
			expect.near(keypoint.Time, other.Time, 1e-6)
			expect.near(keypoint.Value.R, other.Value.R, 1e-6)
			expect.near(keypoint.Value.G, other.Value.G, 1e-6)
			expect.near(keypoint.Value.B, other.Value.B, 1e-6)
		end
	end

	-- The How to get lines built straight from Boxes, BoxFormat and Catalog.
	local function expectedHowToGet(def: any): { any }
		local lines = {}
		for _, row in Boxes.containing(def.id) do
			table.insert(lines, {
				kind = "box",
				text = Strings.format(
					Strings.inspect.boxChance,
					{ box = BoxFormat.boxName(row.boxId), percent = row.text }
				),
				boxId = row.boxId,
			})
		end
		if def.shopPrice then
			table.insert(lines, {
				kind = "shop",
				text = Strings.format(Strings.inspect.shopPrice, { price = Format.coins(def.shopPrice) }),
			})
		end
		return lines
	end

	-- view -----------------------------------------------------------------------------------------------------------

	t.test("view: every field of all 14 squishies comes from Catalog, Config, Boxes and Strings", function()
		local defs = Catalog.list()
		expect.equal(#defs, 14)
		for _, def in defs do
			local view = InspectFormat.view(def.id, UNOWNED)
			assert(view ~= nil, "no view for " .. def.id)
			local info = Rarity.get(def.rarity)
			expect.equal(view.id, def.id)
			expect.equal(view.blueprintId, def.blueprintId)
			expect.equal(view.name, Strings.resolve(def.nameKey))
			expect.equal(view.rarity, def.rarity)
			expect.equal(view.rarityName, Strings.resolve(info.nameKey))
			expect.equal(view.rarityLabel, Strings.resolve(info.labelKey))
			expect.equal(view.pips, info.pips)
			expect.equal(view.caption, Strings.inspect.preview)
			expect.equal(
				view.coinsText,
				Strings.format(Strings.capsule.power, { n = CapsuleMath.squishyPower(def.id) })
			)
			expect.equal(view.coinsSub, Strings.capsule.powerNote)
			expect.equal(view.statsCaption, Strings.inspect.statsCaption)
			expect.equal(view.elimination, "Elimination: Standard") -- §10.8 #7 (Epics too, until the effect ships)
			expect.equal(view.howToGetTitle, Strings.inspect.howToGet)
			expect.equal(view.shopPrice, def.shopPrice)
			expect.equal(view.yaw, def.inspect.yaw)
			expect.equal(view.pitch, def.inspect.pitch)

			-- The five stat bars (§10.8 #4), in order, fully resolved.
			local bars = InventoryFormat.statBars(def)
			expect.equal(#view.stats, #STAT_ORDER)
			for i, line in view.stats do
				local bar = bars[i]
				expect.equal(line.stat, STAT_ORDER[i])
				expect.equal(line.stat, bar.stat)
				expect.equal(line.label, Strings.inspect.stat[bar.stat])
				expect.equal(
					line.valueText,
					Strings.format(
						Strings.inspect.statValue,
						{ value = bar.value, unit = Strings.resolve(bar.unitKey) }
					)
				)
				expect.equal(line.fraction, bar.fraction)
			end

			-- Trail (§10.8 #5).
			local kind = def.visuals.trail
			local style = RarityStyle.trail(kind)
			if style == nil then
				expect.equal(view.trail.text, Strings.trail.none)
				expect.equal(view.trail.colors, nil)
			else
				expect.equal(
					view.trail.text,
					Strings.format(Strings.trail.label, { name = Strings.resolve(style.nameKey) })
				)
				sameSequence(
					view.trail.colors,
					RarityStyle.trailColorSequence(kind, Color3.fromHex(def.visuals.accent))
				)
			end

			-- Ultimate (§10.8 #6): Config.Abilities only.
			local ability = if def.ultimateId then Config.Abilities[def.ultimateId] else nil
			if ability == nil then
				expect.equal(view.ultimate, nil)
			else
				local description =
					Strings.format(Strings.resolve(ability.descriptionKey), { seconds = ability.telegraphSeconds })
				expect.equal(
					view.ultimate,
					Strings.format(
						Strings.inspect.ultimate,
						{ name = Strings.resolve(ability.nameKey), description = description }
					)
				)
			end
		end
	end)

	t.test("view: a literal spot check (Kitty Bread's speed, the Commons' trail, Dragon's ultimate)", function()
		local kitty = InspectFormat.view("kitty_bread", UNOWNED)
		assert(kitty ~= nil, "no view")
		expect.equal(kitty.name, "Kitty Bread")
		expect.equal(kitty.stats[1].label, "Speed")
		expect.equal(kitty.stats[1].valueText, "95 studs/s")
		for _, id in { "kitty_bread", "toast", "banana" } do
			local view = InspectFormat.view(id, UNOWNED)
			assert(view ~= nil, "no view")
			expect.equal(view.trail.text, "No trail")
			expect.equal(view.trail.colors, nil)
		end
		local butter = InspectFormat.view("butter", UNOWNED)
		assert(butter ~= nil, "no view")
		expect.equal(butter.trail.text, "Trail: Ribbon")
		expect.truthy(butter.trail.colors ~= nil)
		local dragon = InspectFormat.view("dragon", UNOWNED)
		assert(dragon ~= nil, "no view")
		-- Phase 5 (progression spec 2026-10-12 §6): capsule power by rarity, x1 / x4 / x16 / x64.
		expect.equal(kitty.coinsText, "x1 power")
		expect.equal(butter.coinsText, "x4 power")
		expect.equal(dragon.coinsText, "x64 power")
		local ultimate = dragon.ultimate
		assert(ultimate ~= nil, "Dragon has no ultimate text")
		expect.equal(string.sub(ultimate, 1, #"Ultimate: Dragon Rush. "), "Ultimate: Dragon Rush. ")
		expect.truthy(
			string.find(ultimate, tostring(Config.Abilities.dragon_rush.telegraphSeconds) .. " seconds", 1, true)
		)
		-- Spec phase 5: the four Epics show their own ultimates (the design's names, ults.js:3-6); the rest show none.
		for _, def in Catalog.list() do
			if def.id ~= "dragon" then
				local view = InspectFormat.view(def.id, UNOWNED)
				assert(view ~= nil, "no view")
				if def.ultimateId == nil then
					expect.equal(view.ultimate, nil)
				else
					local name = Strings.resolve(Config.Abilities[def.ultimateId].nameKey)
					local text = view.ultimate
					assert(text ~= nil, def.id .. " has no ultimate text")
					expect.equal(string.sub(text, 1, #`Ultimate: {name}. `), `Ultimate: {name}. `)
				end
			end
		end
	end)

	t.test(
		"view: unowned How to get = Boxes.containing (Treat Box too) with exact odds, then the shop price",
		function()
			for _, def in Catalog.list() do
				local view = InspectFormat.view(def.id, UNOWNED)
				assert(view ~= nil, "no view")
				expect.deepEqual(view.howToGet, expectedHowToGet(def))
				expect.equal(view.badgeKey, "common.notOwned")
				expect.equal(view.badgeText, Strings.common.notOwned)
				expect.equal(view.previewBadge, Strings.inspect.previewNotOwned)
				expect.equal(view.owned, false)
				expect.equal(view.equipped, false)
				expect.equal(view.canViewInShop, def.shopPrice ~= nil)
				-- Every box row's percent text appears exactly, with its % sign.
				local boxLines = 0
				for _, line in view.howToGet do
					if line.kind == "box" then
						boxLines += 1
					end
				end
				expect.equal(boxLines, #Boxes.containing(def.id))
			end
			-- §6.10 numbers (spec 2026-10-12 §6, §8: Epics left the Snack Box), as the player reads them.
			local bird = InspectFormat.view("bird", UNOWNED)
			assert(bird ~= nil, "no view")
			local texts = {}
			for _, line in bird.howToGet do
				table.insert(texts, line.text)
			end
			expect.deepEqual(texts, { "Sweet Box: 9.99%", "Treat Box: 2.50%", "Shop: 1.70B Coins" })
			expect.equal(bird.previewBadge, "Preview · Not owned") -- foam fix batch: sentence case, not all caps
			-- The free starter is in no box and not sold: nothing to list, no View in Shop.
			local kitty = InspectFormat.view("kitty_bread", UNOWNED)
			assert(kitty ~= nil, "no view")
			expect.deepEqual(kitty.howToGet, {})
			expect.equal(kitty.canViewInShop, false)
			expect.equal(kitty.shopPrice, nil)
		end
	)

	t.test("view: owned and equipped; View in Shop needs the shop screen", function()
		for _, def in Catalog.list() do
			local owned = InspectFormat.view(def.id, { owned = true, equipped = false, shopAvailable = true })
			assert(owned ~= nil, "no view")
			expect.deepEqual(owned.howToGet, {})
			expect.equal(owned.badgeKey, "common.owned")
			expect.equal(owned.badgeText, Strings.common.owned)
			expect.equal(owned.previewBadge, nil)
			expect.equal(owned.canViewInShop, false)
			expect.equal(owned.owned, true)
			expect.equal(owned.equipped, false)
			local equipped = InspectFormat.view(def.id, { owned = true, equipped = true })
			assert(equipped ~= nil, "no view")
			expect.equal(equipped.badgeKey, "common.equipped")
			expect.equal(equipped.badgeText, Strings.common.equipped)
			expect.equal(equipped.equipped, true)
			-- "Equipped" without owning it is not shown.
			local odd = InspectFormat.view(def.id, { owned = false, equipped = true, shopAvailable = true })
			assert(odd ~= nil, "no view")
			expect.equal(odd.equipped, false)
			expect.equal(odd.badgeKey, "common.notOwned")
			-- No shop screen: no View in Shop.
			local noShop = InspectFormat.view(def.id, { owned = false, equipped = false, shopAvailable = false })
			assert(noShop ~= nil, "no view")
			expect.equal(noShop.canViewInShop, false)
			local unset = InspectFormat.view(def.id, { owned = false, equipped = false })
			assert(unset ~= nil, "no view")
			expect.equal(unset.canViewInShop, false)
		end
		expect.equal(InspectFormat.view("not_a_squishy", UNOWNED), nil)
		expect.equal(InspectFormat.view("", UNOWNED), nil)
	end)

	-- equipState / openAction / previewAllowed / closeToastKey ---------------------------------------------------------

	t.test("equipState follows the Squishies screen's rule", function()
		local function state(ctx: any): string
			return InspectFormat.equipState("butter", ctx)
		end
		expect.equal(state({ owned = false, equipped = false, locked = false }), "notOwned")
		expect.equal(state({ owned = true, equipped = true, locked = false }), "equipped")
		expect.equal(state({ owned = true, equipped = false, locked = false, confirmed = "butter" }), "equipped")
		expect.equal(state({ owned = true, equipped = false, locked = false, pending = "butter" }), "loading")
		expect.equal(state({ owned = true, equipped = false, locked = true }), "locked")
		expect.equal(state({ owned = true, equipped = false, locked = false }), "equip")
		expect.equal(state({ owned = true, equipped = false, locked = false, pending = "toast" }), "equip")
		expect.equal(
			InspectFormat.equipState("not_a_squishy", { owned = true, equipped = false, locked = false }),
			"notOwned"
		)
		-- The same answers as InventoryFormat.equipState.
		local def = Catalog.get("butter")
		local entry = {
			id = "butter",
			def = def,
			name = "butter",
			rarity = def.rarity,
			owned = true,
			equipped = false,
			isNew = false,
		}
		expect.equal(
			state({ owned = true, equipped = false, locked = true, pending = "butter" }),
			InventoryFormat.equipState(entry, { locked = true, pending = "butter" })
		)
	end)

	t.test("openAction: the §10.4 guard", function()
		type Case = { phase: string, current: string?, new: string, want: string }
		local cases: { Case } = {
			{ phase = "Closed", current = nil, new = "toast", want = "open" },
			{ phase = "Closed", current = "toast", new = "toast", want = "open" },
			{ phase = "Open", current = "toast", new = "toast", want = "none" },
			{ phase = "Open", current = "toast", new = "bird", want = "select" },
			{ phase = "Opening", current = "toast", new = "toast", want = "none" },
			{ phase = "Opening", current = "toast", new = "bird", want = "select" },
			{ phase = "Closing", current = "toast", new = "toast", want = "none" },
			{ phase = "Closing", current = "toast", new = "bird", want = "select" },
		}
		for _, case in cases do
			expect.equal(InspectFormat.openAction(case.phase, case.current, case.new), case.want)
		end
	end)

	t.test("previewAllowed: at most 8 preview squeezes in any second", function()
		expect.equal(Config.Inspect.Preview.maxPerSecond, 8)
		local recent = {}
		for i = 0, 7 do
			local ok
			ok, recent = InspectFormat.previewAllowed(recent, 10 + i * 0.1)
			expect.equal(ok, true)
		end
		expect.equal(#recent, 8)
		local refused, after = InspectFormat.previewAllowed(recent, 10.75)
		expect.equal(refused, false)
		expect.equal(#after, 8)
		-- 10.0 leaves the window at 11.0.
		local again, kept = InspectFormat.previewAllowed(recent, 11)
		expect.equal(again, true)
		expect.equal(#kept, 8)
		-- The input list is never changed.
		local frozen = table.freeze({ 1, 1.5 })
		local okFrozen, fresh = InspectFormat.previewAllowed(frozen, 2)
		expect.equal(okFrozen, true)
		expect.deepEqual(frozen, { 1, 1.5 })
		expect.deepEqual(fresh, { 1.5, 2 })
		-- A custom limit; a bad clock refuses.
		expect.equal((InspectFormat.previewAllowed({}, 0, 1)), true)
		expect.equal((InspectFormat.previewAllowed({ 0 }, 0.5, 1)), false)
		expect.equal((InspectFormat.previewAllowed({}, 0 / 0)), false)
	end)

	t.test('closeToastKey: a found match says "Opponent found!"', function()
		local key = InspectFormat.closeToastKey("matched")
		expect.equal(key, "queue.opponentFound")
		expect.equal(Strings.resolve(key), "Opponent found!")
		expect.equal(InspectFormat.closeToastKey("button"), nil)
		expect.equal(InspectFormat.closeToastKey("menu"), nil)
		expect.equal(InspectFormat.closeToastKey(nil), nil)
	end)

	-- Dots ---------------------------------------------------------------------------------------------------------------

	t.test("dotCount: inspectDotsMin..Max by rarity, halved under ReducedMotion, at least 1", function()
		local squeeze = Config.Anim.squeeze
		local low, high = squeeze.inspectDotsMin, squeeze.inspectDotsMax
		expect.equal(InspectFormat.dotCount("Common", false), low)
		expect.equal(InspectFormat.dotCount("Exclusive", false), high)
		local previous = 0
		for _, rarity in Rarity.ORDER do
			local n = InspectFormat.dotCount(rarity, false)
			expect.truthy(n >= low and n <= high)
			expect.truthy(n >= previous)
			expect.equal(n, math.floor(n))
			previous = n
			local reduced = InspectFormat.dotCount(rarity, true)
			expect.equal(reduced, math.max(1, math.floor(n * Config.Vfx.reducedParticleMultiplier)))
			expect.truthy(reduced >= 1 and reduced <= n)
		end
		expect.equal(InspectFormat.dotCount("Nope", false), low)
	end)

	t.test("dotSample: slows to a stop at dotLifeSeconds while it fades and shrinks", function()
		local life = Config.Inspect.Preview.dotLifeSeconds
		local speed = 200
		local offset, transparency, scale, done = InspectFormat.dotSample(0, 0, speed)
		expect.near(offset.Magnitude, 0, 1e-9)
		expect.equal(transparency, 0)
		expect.equal(scale, 1)
		expect.equal(done, false)
		-- Halfway: 3/8 of speed × life (linear slow-down), half faded, half size.
		offset, transparency, scale, done = InspectFormat.dotSample(life / 2, 0, speed)
		expect.near(offset.X, speed * life * 0.375, 1e-6)
		expect.near(offset.Y, 0, 1e-6)
		expect.near(transparency, 0.5, 1e-9)
		expect.near(scale, 0.5, 1e-9)
		expect.equal(done, false)
		-- At the end: half of speed × life, gone.
		offset, transparency, scale, done = InspectFormat.dotSample(life, 0, speed)
		expect.near(offset.X, speed * life / 2, 1e-6)
		expect.equal(transparency, 1)
		expect.equal(scale, 0)
		expect.equal(done, true)
		local later = InspectFormat.dotSample(life * 3, 0, speed)
		expect.near(later.X, speed * life / 2, 1e-6)
		-- Screen axes: pi/2 = down.
		local down = InspectFormat.dotSample(life, math.pi / 2, speed)
		expect.near(down.X, 0, 1e-6)
		expect.near(down.Y, speed * life / 2, 1e-6)
		-- A custom life.
		local _, _, _, custom = InspectFormat.dotSample(0.9, 0, speed, { dotLifeSeconds = 1 })
		expect.equal(custom, false)
		-- The distance only grows.
		local last = -1
		for i = 0, 20 do
			local step = InspectFormat.dotSample(life * i / 20, 1, speed)
			expect.truthy(step.Magnitude >= last - 1e-9)
			last = step.Magnitude
		end
	end)
end
