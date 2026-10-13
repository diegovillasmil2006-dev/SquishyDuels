--!strict
-- NameplateController_Test: unit tests for StarterPlayerScripts.Client.Controllers.NameplateController (Part 5, the
-- pure helpers). Server only (ServerStorage.UnitTest). Edit mode: init() / start() are not called (no LocalPlayer).
-- Contract (DESIGN §17.2 rule 1, §17.7 "World → Nameplate", §17.3.3):
--   * visible(enabled, viewerPhase, targetPhase, level): only with nameplates on, a known level, and neither the viewer
--     nor the target in a match (SD_DuelPhase ~= "" hides it);
--   * text(level): grip.nameplate "Lv {level} · {rank}" with the rank of that level;
--   * rankColor(level): one colour per rank (always shown with the rank's name), the same within a rank; Phase 5: the
--     ranks above Lv 50 have their own Palette faces (Rank*), and every face keeps the plate's text >= 4.5:1.
-- Part 8 polish (§17.11; Readings, DESIGN lists no details): fadeTransparency (solid until the last fadeStuds before
-- maxDistance, then linear to clear), ownHidden (the own plate hides with the camera within ownHideStuds of the Head),
-- plateSize (the plate fits "Lv 50 · <longest rank>" at every PreferredTextSize; foam UI: plus the chip bands under
-- the text). Foam fix 2: ownHidden also hides the own plate on the compact layout (phones).
-- Strings are compared by value through the test's own Strings copy (the controller requires the real one).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Nameplate = t.requireClient("Controllers/NameplateController")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local expect = t.expect
	local RANKS = Config.Grip.Ranks

	local function s(key: string, args: { [string]: any }?): string
		local template = Strings.resolve(key)
		assert(template ~= nil, `missing Strings key {key}`)
		return Strings.format(template, args)
	end

	t.test("a nameplate shows only in the lobby, with a level, while nameplates are on", function()
		expect.truthy(Nameplate.visible(true, "", "", 1))
		expect.falsy(Nameplate.visible(false, "", "", 1))
		expect.falsy(Nameplate.visible(true, "", "", nil))
		for _, phase in { "Preparing", "Positioning", "Countdown", "Active", "SuddenDeath", "Result", "Returning" } do
			expect.falsy(Nameplate.visible(true, phase, "", 12)) -- the viewer is in a match
			expect.falsy(Nameplate.visible(true, "", phase, 12)) -- the target is in a match
		end
	end)

	t.test("the plate reads Lv {level} · {rank} with the rank of that level", function()
		for _, rank in RANKS do
			local expected = s("grip.nameplate", { level = rank.level, rank = s("grip.rank." .. rank.key) })
			expect.equal(Nameplate.text(rank.level), expected)
		end
		expect.equal(Nameplate.text(23), s("grip.nameplate", { level = 23, rank = s("grip.rank.strong") }))
		expect.equal(Nameplate.text(9), s("grip.nameplate", { level = 9, rank = s("grip.rank.soft") }))
	end)

	t.test("each rank has its own plate colour, the same for every level of that rank", function()
		local seen: { [string]: boolean } = {}
		for index, rank in RANKS do
			local color = Nameplate.rankColor(rank.level)
			expect.equal(typeof(color), "Color3")
			local key = tostring(color)
			expect.falsy(seen[key])
			seen[key] = true
			local nextRank = RANKS[index + 1]
			local lastLevel = if nextRank then nextRank.level - 1 else Config.Grip.maxLevel
			expect.equal(Nameplate.rankColor(lastLevel), color)
		end
	end)

	-- Phase 5: the ranks above Lv 50 have their own Palette faces (Rank*), and every plate keeps its PlumInk text
	-- readable (WCAG 2 contrast >= 4.5:1, as Theme_Test checks the UI faces).
	t.test("every rank up to Lv 100 has a plate colour of its own that keeps the plate's text >= 4.5:1", function()
		local Palette = t.requireShared("Art/Palette")
		local function luminance(color: Color3): number
			local function channel(c: number): number
				return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
			end
			return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
		end
		local ink = luminance(Palette.PlumInk)
		for _, rank in RANKS do
			local face = luminance(Nameplate.rankColor(rank.level))
			expect.truthy((math.max(face, ink) + 0.05) / (math.min(face, ink) + 0.05) >= 4.5)
		end
		local tokens = {
			legend = "RankLegend",
			mythic = "RankMythic",
			cosmic = "RankCosmic",
			galaxy = "RankGalaxy",
			infinite = "RankInfinite",
		}
		for rankKey, token in tokens do
			local level = 0
			for _, rank in RANKS do
				if rank.key == rankKey then
					level = rank.level
				end
			end
			expect.equal(Nameplate.rankColor(level), Palette[token])
		end
	end)

	-- Part 8 polish (§17.11) -----------------------------------------------------------------------------------------

	local PLATE = Config.Grip.Nameplate

	t.test("the plate fades over the last fadeStuds before maxDistance: solid nearer, clear at the edge", function()
		local max, fade = PLATE.maxDistance, PLATE.fadeStuds
		expect.equal(max, 60)
		expect.equal(fade, 10)
		expect.equal(Nameplate.fadeTransparency(0, max, fade), 0)
		expect.equal(Nameplate.fadeTransparency(max - fade, max, fade), 0) -- 50 studs: still solid
		expect.near(Nameplate.fadeTransparency(max - fade / 2, max, fade), 0.5, 1e-9) -- 55 studs: half
		expect.near(Nameplate.fadeTransparency(max - fade / 10, max, fade), 0.9, 1e-9)
		expect.equal(Nameplate.fadeTransparency(max, max, fade), 1) -- 60 studs: clear (MaxDistance hides it beyond)
		expect.equal(Nameplate.fadeTransparency(max + 5, max, fade), 1)
		-- Never brighter farther away.
		local previous = 0
		for distance = 0, max + 2, 0.5 do
			local value = Nameplate.fadeTransparency(distance, max, fade)
			expect.truthy(value >= previous and value >= 0 and value <= 1)
			previous = value
		end
		-- A NaN distance counts as near; no fade length means no fade before the edge.
		expect.equal(Nameplate.fadeTransparency(0 / 0, max, fade), 0)
		expect.equal(Nameplate.fadeTransparency(59, max, 0), 0)
		expect.equal(Nameplate.fadeTransparency(59, max, 0 / 0), 0)
		expect.equal(Nameplate.fadeTransparency(math.huge, max, fade), 1)
	end)

	t.test("the own plate hides only while the camera is within ownHideStuds of the Head (first person)", function()
		local threshold = PLATE.ownHideStuds
		expect.equal(threshold, 1.5)
		expect.truthy(Nameplate.ownHidden(0, threshold))
		expect.truthy(Nameplate.ownHidden(0.5, threshold))
		expect.truthy(Nameplate.ownHidden(threshold, threshold))
		expect.falsy(Nameplate.ownHidden(threshold + 0.01, threshold))
		expect.falsy(Nameplate.ownHidden(12, threshold)) -- the usual third-person camera
		-- Non-finite input never hides it; a 0 threshold hides it only at the head itself.
		expect.falsy(Nameplate.ownHidden(0 / 0, threshold))
		expect.falsy(Nameplate.ownHidden(math.huge, threshold))
		expect.falsy(Nameplate.ownHidden(0.5, 0 / 0))
		expect.truthy(Nameplate.ownHidden(0, 0))
		expect.falsy(Nameplate.ownHidden(0.1, 0))
	end)

	-- Foam fix 2 (2026-10-09): on the compact layout (phones) the HUD's tile row sits at the own plate's height and the
	-- compact Grip card beside the coin capsule reads the same "Lv 8 · Soft Grip", so the own plate stays hidden there
	-- (other players still see it: their clients draw it).
	t.test("the own plate also hides on the compact layout, at any camera distance", function()
		local threshold = PLATE.ownHideStuds
		expect.truthy(Nameplate.ownHidden(12, threshold, true))
		expect.truthy(Nameplate.ownHidden(math.huge, threshold, true))
		expect.truthy(Nameplate.ownHidden(0 / 0, threshold, true))
		expect.falsy(Nameplate.ownHidden(12, threshold, false))
		expect.falsy(Nameplate.ownHidden(12, threshold, nil))
		expect.truthy(Nameplate.ownHidden(0.5, threshold, false)) -- first person still hides it
	end)

	t.test(
		"the plate fits 'Lv 50 · <longest rank>' at every PreferredTextSize, at least the built 30 px tall",
		function()
			local Layout = t.requireClient("UI/Layout")
			local longest = ""
			for _, rank in RANKS do
				local line = s("grip.nameplate", { level = Config.Grip.maxLevel, rank = s("grip.rank." .. rank.key) })
				if (utf8.len(line) or #line) > (utf8.len(longest) or #longest) then
					longest = line
				end
			end
			expect.truthy(string.find(longest, tostring(Config.Grip.maxLevel), 1, true) ~= nil)
			local chars = utf8.len(longest) or #longest
			local paddingX = Nameplate.PLATE.paddingX
			local previousWidth = 0
			for _, name in { "Medium", "Large", "Larger", "Largest" } do
				local size = Layout.textSize("Small", name)
				-- A generous text estimate (0.6 em a character, 1.25 lines): the label inside the padding still holds it.
				local bounds = Vector2.new(chars * size * 0.6, size * 1.25)
				local plate = Nameplate.plateSize(bounds)
				expect.truthy(plate.X - 2 * paddingX >= bounds.X)
				expect.truthy(plate.Y >= bounds.Y)
				expect.truthy(plate.Y >= Nameplate.PLATE.minHeight)
				expect.truthy(plate.X > previousWidth) -- larger text, wider plate
				previousWidth = plate.X
			end
			-- Foam UI: the chip's bevel and drop bands sit under the text, so a tall text still clears them.
			local Theme = t.requireClient("UI/Theme")
			expect.equal(Nameplate.PLATE.bandsPx, Theme.Foam.chip.bevel + Theme.Foam.chip.drop)
			local tall = Vector2.new(100, 40)
			expect.truthy(Nameplate.plateSize(tall).Y - tall.Y >= Nameplate.PLATE.bandsPx)
			-- Before the text is measured (no bounds, NaN): the smallest plate, never an error.
			local empty = Nameplate.plateSize(Vector2.zero)
			expect.equal(empty.Y, Nameplate.PLATE.minHeight)
			expect.truthy(empty.X >= 2 * paddingX)
			local nan = Nameplate.plateSize(Vector2.new(0 / 0, 0 / 0))
			expect.equal(nan.Y, Nameplate.PLATE.minHeight)
			expect.equal(nan.X, empty.X)
		end
	)
end
