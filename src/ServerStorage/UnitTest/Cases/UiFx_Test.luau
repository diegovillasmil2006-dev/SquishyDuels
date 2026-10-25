--!strict
-- UiFx_Test: StarterPlayerScripts.Client.UI.UiFx, the UI FINAL R2 design effects added next to the Candy tiers (plan
-- work/ui/PLAN.md §2.1: the design's burst, ring, rain and float, hud-lib.js lib:215-268, and the events that fire
-- them, Config.UI.Fx). Server only (ServerStorage.UnitTest), Edit mode: the pure parts with a seeded Random; the
-- drawing cases use an unparented ScreenGui inside a Folder as the layer and destroy it.
-- Contract:
--   * the Candy tiers are unchanged (UiFx.TIERS, counts);
--   * sparks: Config.UI.Fx.sparks.n pieces (the design's count with fewerEffects too: PR14 halves the rain only),
--     about `stars` of them stars, colours in
--     turn, sizes size × 0.55..1.45, launched spread × 0.35..1.2 out (and `up` higher), each over ms + 0..jitterMs; a
--     piece starts at the centre unseen (scale 0) and ends at its landing (+grav), scale 0.1 and clear (lib:229-233);
--   * rain (PR14): n pieces, halved (once) on a compact screen or with fewerEffects, across the layer or a caller's
--     overlay;
--     ring and float exist; a float keeps the role's flat 3 px outline (lib:259) at any size, and draws in a
--     caller's frame when given one; no cap on the effects running at once (the design has none);
--   * under ReducedMotion sparks, rings, rain and jolts draw nothing (lib:220, 237, 244, 300); a float still shows,
--     holding still;
--   * the burst's stars are the img.fx.spark picture tinted, a 45° diamond while it has no id (T10);
--   * every colour Config.UI.Fx names is an Art/Palette colour (or a rarity colour the caller passes);
--   * the box reveal's moving frames stay within its budget (§9.15: 1 rays picture + the 2 rings + 21 pieces = 24);
--   * jolt (T6, lib:299-303): Config.UI.Fx.jolt.frames random offsets no larger than px x (1 - i / frames), then 0,
--     linear over its ms; none with Camera shake off (the gate) or under ReducedMotion; no 9 px cap.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local GuiService = game:GetService("GuiService")

return function(t: Context)
	local expect = t.expect
	local UiFx = t.requireClient("UI/UiFx")
	local UiPrefs = t.requireClient("UI/UiPrefs")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local Theme = t.requireClient("UI/Theme")
	local AssetTable = t.requireShared("AssetTable")
	local FX = Config.UI.Fx
	local SPARKS = FX.sparks
	local systemReduced = GuiService.ReducedMotionEnabled

	local function layer(): (Folder, ScreenGui)
		local folder = Instance.new("Folder")
		local gui = Instance.new("ScreenGui")
		gui.Name = "SD_Overlay"
		gui.Parent = folder
		UiFx.setLayer(gui)
		return folder, gui
	end

	local function done(folder: Folder)
		UiPrefs.set("reduceMotion", false)
		UiPrefs.set("fewerEffects", false)
		UiFx.setLayer(nil)
		folder:Destroy()
	end

	t.test("the Candy tiers stay as they were", function()
		expect.deepEqual(UiFx.TIERS.small, {
			radius = 70,
			seconds = 0.6,
			rings = 1,
			rays = 0,
			sparkles = 5,
			confetti = 0,
			droplets = 0,
		})
		expect.equal(UiFx.counts("medium", false).rays, 10)
		expect.equal(UiFx.counts("large", true).confetti, 6)
		expect.equal(UiFx.MAX_ACTIVE, 4)
	end)

	t.test("spark counts: the design's (16 by default), fewer effects or not (PR14 halves only the rain)", function()
		expect.equal(SPARKS.n, 16)
		expect.equal(UiFx.sparkCount(nil), 16)
		expect.equal(UiFx.sparkCount(7), 7)
		expect.equal(UiFx.sparkCount(7.9), 7)
		expect.equal(UiFx.sparkCount(0), 0)
		expect.equal(UiFx.sparkCount(-3), 0)
	end)

	t.test("spark pieces: the star share, colours in turn, sizes, reach and lives of lib:221-233", function()
		local rng = Random.new(7)
		local colors = { Palette.StickerFxYellow, Palette.StickerFxPink, Palette.White }
		local opts = { n = 4000, spread = 200, up = 50, size = 10, stars = 0.55, colors = colors, ms = 600 }
		local pieces = UiFx.sparkPieces(opts, rng)
		expect.equal(#pieces, 4000)
		local stars = 0
		for index, piece in pieces do
			if piece.star then
				stars += 1
			end
			expect.equal(piece.color, colors[(index - 1) % 3 + 1])
			expect.truthy(piece.size >= 10 * 0.55 - 1e-9 and piece.size <= 10 * 1.45 + 1e-9)
			local reach = Vector2.new(piece.dx, piece.dy + 50).Magnitude
			expect.truthy(reach >= 200 * 0.35 - 1e-6 and reach <= 200 * 1.2 + 1e-6)
			expect.truthy(piece.ms >= 600 and piece.ms <= 600 + SPARKS.jitterMs)
		end
		expect.near(stars / 4000, 0.55, 0.04)
		-- Defaults: the design's five colours and its star share.
		local default = UiFx.sparkPieces(nil, Random.new(3))
		expect.equal(#default, SPARKS.n)
		expect.equal(default[1].color, Palette[SPARKS.colors[1]])
		expect.equal(default[5].color, Palette[SPARKS.colors[5]])
	end)

	t.test("a spark starts unseen at the centre and ends at its landing, small and clear", function()
		local piece = UiFx.sparkPieces({ n = 1, spread = 150, size = 12 }, Random.new(11))[1]
		local at0, scale0, _, clear0 = UiFx.sparkAt(piece, 0)
		expect.near(at0.X, 0, 1e-6)
		expect.near(at0.Y, 0, 1e-6)
		expect.near(scale0, 0, 1e-6)
		expect.near(clear0, 0, 1e-6)
		local at1, scale1, rot1, clear1 = UiFx.sparkAt(piece, 1)
		expect.near(at1.X, piece.dx, 1e-4) -- a Vector2 holds 32-bit floats
		expect.near(at1.Y, piece.dy + SPARKS.grav, 1e-4)
		expect.near(scale1, SPARKS.endScale, 1e-6)
		expect.near(rot1, piece.spin, 1e-6)
		expect.near(clear1, 1, 1e-6)
	end)

	t.test(
		"converge (MATCH FOUND's charge, hud-lib.js L:345-360): from a ring into the centre, gone at the end",
		function()
			local spec = FX.converge
			local pieces = UiFx.convergePieces({ n = 8, reach = 100, size = 10 }, Random.new(5))
			expect.equal(#pieces, 8)
			for index, piece in pieces do
				local reach = math.sqrt(piece.dx ^ 2 + piece.dy ^ 2)
				expect.truthy(
					reach >= 100 * spec.reachMin - 1e-6 and reach <= 100 * (spec.reachMin + spec.reachSpan) + 1e-6
				)
				expect.truthy(
					piece.size >= 10 * spec.sizeMin - 1e-6 and piece.size <= 10 * (spec.sizeMin + spec.sizeSpan)
				)
				expect.truthy(piece.delayMs >= 0 and piece.delayMs <= spec.delayMs)
				local angle = math.atan2(piece.dy, piece.dx) % (2 * math.pi)
				local turn = (index - 1) / 8 * 2 * math.pi
				expect.truthy((angle - turn) % (2 * math.pi) <= spec.angleJitter + 1e-6) -- the i-th at i / n of the turn
			end
			local piece = pieces[1]
			local at0, scale0, _, clear0 = UiFx.convergeAt(piece, 0)
			expect.near(at0.X, piece.dx, 1e-3)
			expect.near(scale0, 0.4, 1e-6)
			expect.near(clear0, 1, 1e-6)
			local at1, scale1, rot1, clear1 = UiFx.convergeAt(piece, 1)
			expect.near(at1.X, 0, 1e-6)
			expect.near(at1.Y, 0, 1e-6)
			expect.near(scale1, 0, 1e-6)
			expect.near(rot1, 300, 1e-6)
			expect.near(clear1, 1, 1e-6)
			expect.equal(#UiFx.convergePieces(nil, Random.new(1)), spec.n)
		end
	)

	t.test(
		"rain counts (PR14): the design's on a regular screen, halved once on compact or with fewer effects",
		function()
			expect.equal(FX.rain.n, 60)
			expect.equal(UiFx.rainCount(nil, false, false), 60)
			expect.equal(UiFx.rainCount(90, false, false), 90) -- the purchase rain, H:871
			expect.equal(UiFx.rainCount(90, true, false), 45)
			expect.equal(UiFx.rainCount(90, false, true), 45)
			expect.equal(UiFx.rainCount(90, true, true), 45)
			expect.equal(UiFx.rainCount(1, true, false), 1)
		end
	)

	t.test("jolt offsets (lib:301): 8 decaying offsets then 0, linear over 380 ms; no 9 px cap", function()
		expect.equal(FX.jolt.frames, 8)
		expect.equal(FX.jolt.ms, 380)
		local offsets = UiFx.joltOffsets(14, FX.jolt.frames, Random.new(5))
		expect.equal(#offsets, 9)
		for i = 0, 7 do
			local reach = 14 * (1 - i / 8)
			local o = offsets[i + 1]
			expect.truthy(math.abs(o.X) <= reach + 1e-9 and math.abs(o.Y) <= reach + 1e-9)
		end
		expect.equal(offsets[9], Vector2.zero)
		-- The design's 14 px jolt reaches past 9 px somewhere in a long draw (UiFx.shake's SHAKE_PX does not cap it).
		local widest = 0
		for _, o in UiFx.joltOffsets(14, 8, Random.new(9)) do
			widest = math.max(widest, math.abs(o.X), math.abs(o.Y))
		end
		local many = 0
		for seed = 1, 40 do
			for _, o in UiFx.joltOffsets(14, 8, Random.new(seed)) do
				many = math.max(many, math.abs(o.X), math.abs(o.Y))
			end
		end
		expect.truthy(many > 9)
		expect.truthy(widest <= 14)
		-- joltAt: the first offset at 0, linear to the next, back at 0 at the end.
		local steps = { Vector2.new(8, 0), Vector2.new(0, 4), Vector2.zero }
		expect.equal(UiFx.joltAt(steps, 0), Vector2.new(8, 0))
		expect.near(UiFx.joltAt(steps, FX.jolt.ms / 1000 / 4).X, 4, 1e-6)
		expect.equal(UiFx.joltAt(steps, FX.jolt.ms / 1000), Vector2.zero)
	end)

	t.test(
		"jolt: none with Camera shake off (the gate) or under ReducedMotion; the root unmoved until it steps",
		function()
			local folder = Instance.new("Folder")
			local root = Instance.new("Frame")
			root.Position = UDim2.fromOffset(3, 4)
			root.Parent = folder
			UiFx.setShakeGate(function(): boolean
				return false
			end)
			expect.equal(UiFx.jolt(root, 6), false)
			UiFx.setShakeGate(nil)
			UiPrefs.set("reduceMotion", true)
			expect.equal(UiFx.jolt(root, 6), false)
			UiPrefs.set("reduceMotion", false)
			expect.equal(UiFx.jolt(root, 0), false)
			if not systemReduced then
				expect.equal(UiFx.jolt(root, 6), true)
			end
			expect.equal(root.Position, UDim2.fromOffset(3, 4)) -- written by its Scheduler steps only
			folder:Destroy()
		end
	)

	t.test("every colour Config.UI.Fx names is a Palette colour (or a rarity colour the caller passes)", function()
		local sentinels = { rarityBase = true, rarityLight = true }
		local seen = 0
		local function check(value: any, path: string)
			if type(value) == "table" then
				for key, inner in value do
					check(inner, `{path}.{tostring(key)}`)
				end
			elseif type(value) == "string" and (string.find(path, "color", 1, true) ~= nil) then
				seen += 1
				if not (sentinels[value] or typeof(Palette[value]) == "Color3") then
					error(`{path} = {value} is not an Art/Palette colour`)
				end
			end
		end
		check(FX, "Config.UI.Fx")
		expect.truthy(seen >= 20)
		-- UiFx.colors resolves names, the caller's rarity colours, and white for anything unknown.
		local red = Color3.new(1, 0, 0)
		local resolved = UiFx.colors({ "StickerFxCyan", "rarityBase", "NotAColour" }, { rarityBase = red })
		expect.equal(resolved[1], Palette.StickerFxCyan)
		expect.equal(resolved[2], red)
		expect.equal(resolved[3], Palette.White)
	end)

	t.test("the box reveal's moving frames fit its budget (§9.15: the rays picture, the rings, the burst)", function()
		local burst = FX.events.boxBurst
		-- Every animated frame counts (BoxController :60): the rings live 0-520 ms, over the burst from 120 ms.
		expect.truthy(1 + #burst.rings + burst.maxPieces <= 24)
		-- The rarest reveal asks the most: capped.
		local asked = burst.sparks.n + 3 * burst.perRarity
		expect.truthy(1 + #burst.rings + math.min(asked, burst.maxPieces) <= 24)
		expect.equal(burst.rain, nil) -- no rain during the reveal
	end)

	t.test("drawing: sparks, a ring, rain and a float in the layer; none of the motion under ReducedMotion", function()
		local folder, gui = layer()
		local before = UiFx.designCount()
		if not systemReduced then
			expect.equal(UiFx.sparks(Vector2.new(100, 100), { n = 5, stars = 1 }), true)
			local holder = gui:FindFirstChild("SD_Sparks")
			expect.truthy(holder ~= nil)
			expect.equal(#(holder :: Instance):GetChildren(), 5)
			-- T10: the stars are the img.fx.spark picture, tinted; a 45° diamond while it has no id.
			local first = (holder :: Instance):GetChildren()[1]
			if AssetTable.image("img.fx.spark") then
				expect.truthy(first:IsA("ImageLabel"))
			else
				expect.truthy(first:IsA("Frame") and (first :: Frame).Rotation == 45)
			end
			expect.equal(UiFx.ring(Vector2.new(100, 100), Palette.StickerCoinText, 160), true)
			expect.truthy(gui:FindFirstChild("SD_Ring") ~= nil)
			expect.equal(UiFx.rain(4), true)
			expect.truthy(gui:FindFirstChild("SD_Rain") ~= nil)
			expect.truthy(UiFx.designCount() >= before + 3)
			-- A rain over an overlay falls inside it (and goes with it).
			local overlay = Instance.new("Frame")
			overlay.Size = UDim2.fromOffset(300, 200)
			overlay.Parent = gui
			expect.equal(UiFx.rain(4, nil, overlay), true)
			expect.truthy(overlay:FindFirstChild("SD_Rain") ~= nil)
			-- No cap (the design has none): 13 more effects all run, none ended early.
			local running = UiFx.designCount()
			for _ = 1, 13 do
				UiFx.ring(Vector2.new(100, 100))
			end
			expect.equal(UiFx.designCount(), running + 13)
		end
		UiPrefs.set("reduceMotion", true)
		local after = #gui:GetChildren()
		expect.equal(UiFx.sparks(Vector2.new(100, 100), { n = 5 }), false)
		expect.equal(UiFx.ring(Vector2.new(100, 100)), false)
		expect.equal(UiFx.rain(10), false)
		expect.equal(#gui:GetChildren(), after)
		-- A float still tells the number, holding still.
		local made = UiFx.float(Vector2.new(50, 50), "+25", Palette.StickerCoinText, "Name")
		expect.truthy(made ~= nil) -- its label (a caller may change its text while it rises)
		local float = gui:FindFirstChild("SD_Float")
		expect.truthy(float ~= nil)
		local text = (float :: Instance):FindFirstChild("Text") :: TextLabel
		expect.equal(made, text)
		expect.equal(text.Text, "+25")
		expect.equal(text.Position, UDim2.new())
		-- The role's flat stroke (lib:259: 6 px, half outside), not the Name kind's own 3.5 px.
		local outline = text:FindFirstChild("SD_Outline")
		expect.truthy(outline ~= nil and outline:IsA("UIStroke") and outline.Enabled)
		expect.near((outline :: UIStroke).Thickness, Config.UI.Sticker.text.float.stroke / 2, 1e-6)
		expect.equal(text.TextSize, Theme.textSize("Name")) -- the call's size, not the role's Title
		-- In a caller's frame (the HUD's squeeze floats keep SD_Hud's layer): drawn there, at `at` in its base px.
		local frame = Instance.new("Frame")
		frame.Parent = gui
		expect.truthy(UiFx.float(Vector2.new(30, 40), "+3", nil, "H2", { parent = frame }) ~= nil)
		local held = frame:FindFirstChild("SD_Float") :: Frame
		expect.truthy(frame:FindFirstChild("SD_Float") ~= nil)
		expect.equal(held.Position, UDim2.fromOffset(30, 40))
		done(folder)
	end)
end
