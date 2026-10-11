--!strict
-- Signs_Test: unit tests for ServerStorage.SDTools.Kit.Signs, the SurfaceGui signs of the world generators.
-- Server only (ServerStorage.UnitTest). Contract (DESIGN §1.6, §7.7, §17.6):
--   * a static line (textKey) is a TextLabel tagged SD_Sign with SD_TextKey, baked with its Strings text;
--   * a baked or live line has no SD_Sign and no SD_TextKey (two binders never write one label); a live bakeKey line
--     keeps its template as SD_LiveKey; placeholders are filled from the line's or the caller's bakeArgs;
--   * headings FredokaOne, body BuilderSansBold, LightInfluence 0.15, text never above the 100 px engine cap;
--   * a Front sign's readable face looks along `facing`; a Top floor plate's text top points along `textUp` and its
--     world footprint is `size`; a tag (SD_GripSign) and its GripTier go on the part carrying the SurfaceGui;
--   * a missing Strings key is an error, never a blank sign;
--   * every lobby sign's lines fit on its panel (measure: the stacked line boxes never pass the SurfaceGui's edges,
--     which clip them), with the layout's own alignment.
-- Uses a small fake Strings table; every instance stays in memory and is destroyed.

local ServerStorage = game:GetService("ServerStorage")

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

local TOLERANCE = 1e-3

-- `require` with a runtime-chosen ModuleScript; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

local TEXTS: { [string]: string } = {
	["test.title"] = "TITLE",
	["test.needs"] = "Needs Lv {level}",
	["test.count"] = "Waiting: {count}",
}

local FakeStrings = {
	resolve = function(key: string): string?
		return TEXTS[key]
	end,
	format = function(template: string, args: { [string]: any }?): string
		local result = string.gsub(template, "{(%w+)}", function(name: string): string
			local value = if args then args[name] else nil
			return if value == nil then "{" .. name .. "}" else tostring(value)
		end)
		return result
	end,
}

local STYLE = {
	panel = Color3.fromHex("#FFF4E6"),
	frame = Color3.fromHex("#6B4A3A"),
	text = Color3.fromHex("#3B2A35"),
	stroke = Color3.fromHex("#FFF4E6"),
}

local function loadSigns(): (any, Instance)
	local source = ServerStorage:FindFirstChild("SDTools")
	if source == nil then
		error("ServerStorage.SDTools not found (is Rojo connected?)")
	end
	local clone = source:Clone()
	local kit = clone:FindFirstChild("Kit")
	local module = if kit then kit:FindFirstChild("Signs") else nil
	if module == nil or not module:IsA("ModuleScript") then
		clone:Destroy()
		error("SDTools.Kit.Signs is missing")
	end
	return dynamicRequire(module), clone
end

local function label(root: Instance, name: string): TextLabel
	local found = root:FindFirstChild(name, true)
	if found == nil or not found:IsA("TextLabel") then
		error("no TextLabel " .. name)
	end
	return found
end

return function(t: Context)
	local Signs, toolsClone = loadSigns()
	local expect = t.expect

	local function spec(overrides: { [string]: any }): any
		local base: { [string]: any } = {
			id = "testSign",
			position = Vector3.new(0, 10, 0),
			size = Vector3.new(8, 3, 0.4),
			facing = Vector3.new(0, 0, -1),
			face = "Front",
			lines = {
				{ name = "Title", textKey = "test.title", live = false, letterHeight = 2.4, font = "heading" },
				{ name = "Live", bakeKey = "test.needs", live = true, letterHeight = 0.6, font = "body" },
				{
					name = "Baked",
					bakeKey = "test.count",
					bakeArgs = { count = 3 },
					live = false,
					letterHeight = 0.8,
					font = "body",
				},
				{ name = "Empty", live = true, letterHeight = 0.6, font = "body" },
			} :: { any },
		}
		for key, value in overrides do
			base[key] = value
		end
		return base
	end

	t.test("line kinds follow the binder contract", function()
		local folder = Instance.new("Folder")
		local carrier =
			Signs.build(FakeStrings, spec({}), { style = STYLE, bakeArgs = { level = 15 }, parent = folder })
		local title = label(carrier, "Title")
		expect.equal(title.Text, "TITLE")
		expect.truthy(title:HasTag("SD_Sign"))
		expect.equal(title:GetAttribute("SD_TextKey"), "test.title")
		expect.equal(title.Font, Enum.Font.FredokaOne)

		local live = label(carrier, "Live")
		expect.equal(live.Text, "Needs Lv 15")
		expect.falsy(live:HasTag("SD_Sign"))
		expect.equal(live:GetAttribute("SD_TextKey"), nil)
		expect.equal(live:GetAttribute("SD_LiveKey"), "test.needs")
		expect.equal(live.Font, Enum.Font.BuilderSansBold)

		local baked = label(carrier, "Baked")
		expect.equal(baked.Text, "Waiting: 3") -- the line's own bakeArgs win
		expect.equal(baked:GetAttribute("SD_TextKey"), nil)
		expect.equal(baked:GetAttribute("SD_LiveKey"), nil)

		expect.equal(label(carrier, "Empty").Text, "")
		folder:Destroy()
	end)

	t.test("SurfaceGui settings and the 100 px text cap", function()
		local folder = Instance.new("Folder")
		local carrier = Signs.build(FakeStrings, spec({}), { style = STYLE, bakeArgs = { level = 1 }, parent = folder })
		local guiChild = carrier:FindFirstChildOfClass("SurfaceGui")
		expect.truthy(guiChild ~= nil)
		local gui = guiChild :: SurfaceGui
		expect.near(gui.LightInfluence, 0.15, 1e-4)
		expect.equal(gui.SizingMode, Enum.SurfaceGuiSizingMode.PixelsPerStud)
		expect.equal(gui.PixelsPerStud, math.floor(100 / 2.4)) -- largest letter 2.4 studs
		for _, d in gui:GetDescendants() do
			if d:IsA("UITextSizeConstraint") then
				expect.truthy(d.MaxTextSize <= 100)
			end
		end
		folder:Destroy()
	end)

	t.test("a Front panel looks along `facing`, has a Cocoa frame, and carries tag + GripTier", function()
		local folder = Instance.new("Folder")
		local carrier = Signs.build(
			FakeStrings,
			spec({ facing = Vector3.new(0, 0, 1), tag = "SD_GripSign", tier = 3 }),
			{ style = STYLE, bakeArgs = { level = 15 }, parent = folder }
		)
		expect.equal(carrier.Name, "Panel")
		expect.near((carrier.CFrame.LookVector - Vector3.new(0, 0, 1)).Magnitude, 0, TOLERANCE)
		expect.truthy(carrier:HasTag("SD_GripSign"))
		expect.equal(carrier:GetAttribute("GripTier"), 3)
		local model = carrier.Parent :: Instance
		expect.equal(model.Name, "testSign")
		local frameChild = model:FindFirstChild("Frame")
		expect.truthy(frameChild ~= nil and frameChild:IsA("BasePart"))
		expect.equal((frameChild :: BasePart).CanCollide, false)
		expect.equal(carrier.CanCollide, false)
		expect.equal(carrier.CanQuery, false)
		folder:Destroy()
	end)

	t.test("a Top floor plate points its text along textUp and keeps its world footprint", function()
		local folder = Instance.new("Folder")
		local carrier = Signs.build(
			FakeStrings,
			spec({
				face = "Top",
				facing = Vector3.new(0, 1, 0),
				textUp = Vector3.new(-1, 0, 0),
				size = Vector3.new(1.4, 0.02, 4),
				position = Vector3.new(-34, 0.07, -42),
				lines = { { name = "Label", textKey = "test.title", live = false, letterHeight = 0.8, font = "body" } },
			}),
			{ style = STYLE, parent = folder }
		)
		expect.near((Signs.topTextUp(carrier) - Vector3.new(-1, 0, 0)).Magnitude, 0, TOLERANCE)
		local gui = carrier:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
		expect.equal(gui.Face, Enum.NormalId.Top)
		-- the plate's world extent is 1.4 along X and 4 along Z whatever its rotation
		local cf, half = carrier.CFrame, carrier.Size / 2
		local extentX = math.abs(cf.XVector.X) * half.X
			+ math.abs(cf.YVector.X) * half.Y
			+ math.abs(cf.ZVector.X) * half.Z
		local extentZ = math.abs(cf.XVector.Z) * half.X
			+ math.abs(cf.YVector.Z) * half.Y
			+ math.abs(cf.ZVector.Z) * half.Z
		expect.near(extentX * 2, 1.4, TOLERANCE)
		expect.near(extentZ * 2, 4, TOLERANCE)
		expect.equal(carrier.Parent and carrier.Parent:FindFirstChild("Frame"), nil) -- floor plates have no frame
		folder:Destroy()
	end)

	t.test("a Top host plate (the spawn logo) is yawed so its text runs along its long side", function()
		-- Studio shows a Top-face SurfaceGui's text top at the part's -RightVector, so an unrotated 24 x 8 plate read
		-- its logo across the 8-stud side (cut off). The host must be yawed and keep its 24 x 8 footprint.
		local folder = Instance.new("Folder")
		local host = Instance.new("Part")
		host.Size = Vector3.new(24, 0.05, 8)
		host.CFrame = CFrame.new(0, 0.095, 28)
		host.Parent = folder
		Signs.build(
			FakeStrings,
			spec({
				face = "Top",
				facing = Vector3.new(0, 1, 0),
				textUp = Vector3.new(0, 0, -1),
				size = Vector3.new(24, 0.05, 8),
				position = Vector3.new(0, 0.095, 28),
				lines = { { name = "Logo", textKey = "test.title", live = false, letterHeight = 3, font = "heading" } },
			}),
			{ style = STYLE, host = host }
		)
		expect.near((Signs.topTextUp(host) - Vector3.new(0, 0, -1)).Magnitude, 0, TOLERANCE)
		expect.near((-host.CFrame.RightVector - Vector3.new(0, 0, -1)).Magnitude, 0, TOLERANCE)
		expect.near((host.Position - Vector3.new(0, 0.095, 28)).Magnitude, 0, TOLERANCE)
		local cf, half = host.CFrame, host.Size / 2
		expect.near(2 * (math.abs(cf.XVector.X) * half.X + math.abs(cf.ZVector.X) * half.Z), 24, TOLERANCE)
		expect.near(2 * (math.abs(cf.XVector.Z) * half.X + math.abs(cf.ZVector.Z) * half.Z), 8, TOLERANCE)
		folder:Destroy()
	end)

	t.test("a host part carries the SurfaceGui itself, with a frame next to it", function()
		local folder = Instance.new("Folder")
		local host = Instance.new("Part")
		host.Size = Vector3.new(16, 8, 0.6)
		host.CFrame = CFrame.new(0, 8, -51)
		host.Parent = folder
		local carrier = Signs.build(FakeStrings, spec({}), { style = STYLE, host = host, bakeArgs = { level = 1 } })
		expect.equal(carrier, host)
		expect.truthy(host:FindFirstChildOfClass("SurfaceGui") ~= nil)
		expect.truthy(folder:FindFirstChild("Frame") ~= nil)
		folder:Destroy()
	end)

	t.test("a missing Strings key is an error, never a blank sign", function()
		local bad = spec({
			lines = { { name = "Title", textKey = "test.missing", live = false, letterHeight = 1, font = "heading" } },
		})
		expect.throws(function()
			Signs.build(FakeStrings, bad, { style = STYLE })
		end, "test.missing")
	end)

	t.test("measure: a stack taller than the panel is reported, alignment moves it", function()
		-- 2.4 + 1.0 letters: 41 px/stud, boxes 123 + 52 and a 3 px gap = 178 px.
		local lines = {
			{ name = "Title", textKey = "test.title", live = false, letterHeight = 2.4, font = "heading" },
			{ name = "Subtitle", textKey = "test.title", live = false, letterHeight = 1.0, font = "body" },
		}
		local short = Signs.measure(spec({ size = Vector3.new(24, 3.8, 0.2), lines = lines }))
		expect.equal(short.pixelsPerStud, 41)
		expect.equal(short.contentPx, 178)
		expect.falsy(short.fits) -- 155.8 px tall: the subtitle was clipped (the old DUEL ARENA arch)
		local tall = Signs.measure(spec({ size = Vector3.new(24, 4.7, 0.2), lines = lines }))
		expect.truthy(tall.fits)
		local top = Signs.measure(spec({ size = Vector3.new(20, 5, 0.4), lines = lines }), "top")
		expect.equal(top.startPx, 6) -- below the 0.15-stud padding
		expect.truthy(top.fits)
		-- A Top floor plate measures along textUp.
		local plate = Signs.measure(spec({
			face = "Top",
			textUp = Vector3.new(-1, 0, 0),
			size = Vector3.new(1.4, 0.02, 4),
			lines = { { name = "Label", textKey = "test.title", live = false, letterHeight = 0.8, font = "body" } },
		}))
		expect.near(plate.canvasPx, 1.4 * 50, 1e-3) -- Vector3 sizes are single precision
	end)

	t.test("every lobby sign's lines fit on its panel (WorldLayout.Signs)", function()
		local WorldLayout = t.requireShared("World/WorldLayout")
		local clipped = {}
		for _, sign in WorldLayout.Signs do
			local fit = Signs.measure(sign, sign.align)
			if not fit.fits then
				table.insert(
					clipped,
					string.format("%s (%d px of lines on a %.1f px panel)", sign.id, fit.contentPx, fit.canvasPx)
				)
			end
		end
		if #clipped > 0 then
			error("signs whose lines are clipped: " .. table.concat(clipped, ", "))
		end
	end)

	t.test("keysOf lists static and baked keys", function()
		local keys = Signs.keysOf(spec({}), {})
		table.sort(keys)
		expect.deepEqual(keys, { "test.count", "test.needs", "test.title" })
	end)

	t.test("teardown", function()
		toolsClone:Destroy()
	end)
end
