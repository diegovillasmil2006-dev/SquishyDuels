--!strict
-- ValidateMatchHud_Test: ReplicatedStorage.Shared.Config.ValidateMatchHud (Match HUD M4, 2026-10-16: the
-- Config.UI.Match part of Config.validate, called from Config/ValidateMatch). Server only (ServerStorage.UnitTest).
-- Like ValidateMatch_Test: the checker is built straight from the module with this file's copies of Config/init's check
-- helpers and a deep copy of Config.UI, so a case breaks one value and reads the problems; one case breaks a copy of
-- the Shared folder before Config loads, to prove Config.validate reaches the check through ValidateMatch.
-- Contract: the live Config.UI.Match has no problem; Match must be a table; gui.displayOrder a whole number >= 0 used
-- by no Config.UI.ScreenGuis entry nor by a controller-owned layer (SD_Touch 12, ...); every enabled switch a
-- boolean; compact.fitMin in (0, 1]; anywhere under Match a `text` / `...Text` field names a Config.UI.TextSize kind
-- and a `curve` / `wholeRun` field a Config.UI.curves entry.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

-- Config/init's check helpers, restated (they are private there).
local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function show(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function add(problems: { string }, message: string)
	table.insert(problems, message)
end

local function expect(problems: { string }, ok: boolean, message: string)
	if not ok then
		add(problems, message)
	end
end

local HELPERS = {
	add = add,
	expect = expect,
	expectCount = function(problems: { string }, path: string, value: unknown, min: number)
		expect(
			problems,
			isNumber(value) and math.floor(value :: number) == value and (value :: number) >= min,
			`{path} must be a whole number >= {min} (got {show(value)})`
		)
	end,
	expectBoolean = function(problems: { string }, path: string, value: unknown)
		expect(problems, type(value) == "boolean", `{path} must be a boolean (got {show(value)})`)
	end,
	isNumber = isNumber,
	show = show,
	sortedKeys = function(tbl: any): { any }
		local keys = {}
		for key in tbl do
			table.insert(keys, key)
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		return keys
	end,
}

local function containsText(list: { string }, text: string): boolean
	for _, entry in list do
		if string.find(entry, text, 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- `require` with a runtime ModuleScript (a clone of the Shared folder).
local dynamicRequire = require :: (any) -> any

return function(t: Context)
	local expectT = t.expect
	local Config = t.requireShared("Config")
	local ValidateMatchHud = t.requireShared("Config/ValidateMatchHud")

	-- The problems of a Config.UI copy changed by `breakIt`.
	local function problemsOf(breakIt: ((ui: any) -> ())?): { string }
		local ui = deepCopy(Config.UI)
		if breakIt then
			breakIt(ui)
		end
		local problems: { string } = {}
		ValidateMatchHud(HELPERS, ui)(problems)
		return problems
	end

	t.test("the live Config.UI.Match has no problem", function()
		local problems = problemsOf(nil)
		if #problems > 0 then
			error(table.concat(problems, "\n"))
		end
	end)

	t.test("Match must be a table", function()
		local problems = problemsOf(function(ui: any)
			ui.Match = nil
		end)
		expectT.truthy(containsText(problems, "Config.UI.Match must be a table"))
	end)

	t.test("gui.displayOrder: a whole number >= 0 that no ScreenGuis entry uses", function()
		local shared = problemsOf(function(ui: any)
			ui.Match.gui.displayOrder = ui.ScreenGuis.SD_DuelHud.displayOrder
		end)
		expectT.truthy(
			containsText(shared, "Config.UI.Match.gui shares displayOrder 11 with Config.UI.ScreenGuis.SD_DuelHud")
		)
		local negative = problemsOf(function(ui: any)
			ui.Match.gui.displayOrder = -1
		end)
		expectT.truthy(containsText(negative, "Config.UI.Match.gui.displayOrder must be a whole number >= 0"))
	end)

	-- Critic fix (2026-10-16): the layers controllers own outside Config.UI.ScreenGuis keep their DisplayOrder in
	-- private constants, so the validator cannot see them; this case pins them. SD_Touch 12 (ControlsController
	-- TOUCH_DISPLAY_ORDER), SD_PracticeReticle 13 (PracticeController RETICLE_DISPLAY_ORDER), SD_Vfx 29
	-- (VfxController GUI_DISPLAY_ORDER), SD_CatchFlash 0 (CatchController FLASH_GUI_SPEC), the Studio SoundPicker 35;
	-- Config.FirstPerson's own three are read from Config. A tie draws in no set order (the HUD under the buttons).
	t.test("gui.displayOrder is none of the controller-owned layers' (SD_Touch 12, ...)", function()
		local order = Config.UI.Match.gui.displayOrder
		local fp = Config.FirstPerson
		local taken = { 0, 12, 13, 29, 35, fp.gui.displayOrder, fp.padGui.displayOrder, fp.touchGuiFallbackOrder }
		for _, other in taken do
			expectT.truthy(order ~= other)
		end
	end)

	t.test("every enabled switch is a boolean", function()
		local problems = problemsOf(function(ui: any)
			ui.Match.enabled.feed = "yes"
		end)
		expectT.truthy(containsText(problems, "Config.UI.Match.enabled.feed must be a boolean"))
	end)

	t.test("compact.fitMin is in (0, 1]", function()
		for _, bad in { 0, 1.5, "big" } :: { any } do
			local problems = problemsOf(function(ui: any)
				ui.Match.compact.fitMin = bad
			end)
			expectT.truthy(containsText(problems, "Config.UI.Match.compact.fitMin must be a number in (0, 1]"))
		end
		expectT.equal(#problemsOf(function(ui: any)
			ui.Match.compact.fitMin = 1
		end), 0)
	end)

	t.test("a text field names a TextSize kind; a curve field names a curves entry (the steps to come)", function()
		local problems = problemsOf(function(ui: any)
			ui.Match.feed = { row = { text = 24, nameText = "Nope", curve = "zigzag" }, out = { wholeRun = "easeIn" } }
		end)
		expectT.truthy(containsText(problems, "Config.UI.Match.feed.row.text must name a Config.UI.TextSize kind"))
		expectT.truthy(containsText(problems, "Config.UI.Match.feed.row.nameText must name a Config.UI.TextSize kind"))
		expectT.truthy(containsText(problems, "Config.UI.Match.feed.row.curve must name a Config.UI.curves entry"))
		expectT.equal(containsText(problems, "feed.out.wholeRun"), false) -- easeIn exists
		local fine = problemsOf(function(ui: any)
			ui.Match.feed = { row = { text = "Body", curve = "beat" } }
		end)
		expectT.equal(#fine, 0)
	end)

	t.test("Config.validate reaches the check through Config/ValidateMatch", function()
		local shared = t.Shared
		assert(shared ~= nil, "no Shared folder to copy")
		local copy = shared:Clone()
		local ok, result = pcall(function(): any
			local config = copy:FindFirstChild("Config")
			local ui = dynamicRequire((config :: any).UI)
			ui.Match.compact.fitMin = 2
			return dynamicRequire(config).validate()
		end)
		copy:Destroy()
		if not ok then
			error(result, 0)
		end
		expectT.truthy(containsText(result, "Config.UI.Match.compact.fitMin must be a number in (0, 1]"))
	end)
end
