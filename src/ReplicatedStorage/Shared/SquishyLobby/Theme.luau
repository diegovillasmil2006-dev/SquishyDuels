-- Squishy Duels lobby · Neon Sugar (1b). Generated from the design file; colors are exact.
local Theme = {}

-- Fredoka One = the HUD-matching font from the design (Fredoka Bold)
Theme.Font = Font.new("rbxasset://fonts/families/FredokaOne.json")

-- MaterialVariant that gives SmoothPlastic parts the raised-square tile.
-- Upload assets/StudTile_Color.png + assets/StudTile_Normal.png, paste the ids here (and in MaterialService).
Theme.Stud = {
	Name = "SquishyStud",
	ColorMap = "rbxassetid://0",
	NormalMap = "rbxassetid://0",
	StudsPerTile = 2,
}

-- Part names that keep a flat finish (no tile)
Theme.FlatNames = { DeepWater = true, ShallowWater = true, Water = true, SignFace = true }

-- Shelf cubby back panel colours
Theme.Slot = {
	backOn = Color3.fromHex("2b7fa8"),
	backOff = Color3.fromHex("7a1f6e"),
}

-- Pen upgrade board (SurfaceGui 1024 x 640 on a 12.8 x 8 stud face)
Theme.Sign = {
	Canvas = Vector2.new(1024, 640),
	Colors = {
		frame = Color3.fromHex("3a2d7a"),
		bg = Color3.fromHex("1d1636"),
		card = Color3.fromHex("2a2150"),
		ink = Color3.fromHex("ffffff"),
		sub = Color3.fromHex("b9adf0"),
		tile = Color3.fromHex("8b5cff"),
		tileDark = Color3.fromHex("5a2fc0"),
		glyph = Color3.fromHex("ffffff"),
		go = Color3.fromHex("2fe04b"),
		goDark = Color3.fromHex("16862a"),
		no = Color3.fromHex("5d5385"),
		noDark = Color3.fromHex("3a3260"),
		track = Color3.fromHex("3a3066"),
		fill = Color3.fromHex("2fe04b"),
		need = Color3.fromHex("ff5cc8"),
		arrow = Color3.fromHex("3fd8ff"),
		max = Color3.fromHex("ffc21a"),
		maxDark = Color3.fromHex("d98a00"),
		coin = Color3.fromHex("ffd23f"),
		coinRim = Color3.fromHex("d98a00"),
		coinShine = Color3.fromHex("fff1a8"),
	},
	-- mock values from the design; drive real values with PenSign.setRow
	DemoRows = {
		{ title = "SHELF SPOTS", icon = "shelf", from = "6", to = "7 spots", filled = 6, total = 12, progress = "6/12", price = "25K", state = "buy", need = "" },
		{ title = "INCOME", icon = "income", from = "x1.5", to = "x2.0", filled = 4, total = 10, progress = "LV 4/10", price = "120K", state = "need", need = "Need 30.5K more" },
	},
}

-- Text plaques (part name -> style)
Theme.Labels = {
	Label_SquishSquare = { text = "SQUISH SQUARE", bg = Color3.fromHex("2a1d5c"), fg = Color3.fromHex("ffffff"), size = 0.6 },
	Label_Shop = { text = "SHOP", bg = Color3.fromHex("2a1d5c"), fg = Color3.fromHex("ffe14d"), size = 0.6 },
	Label_BoxQ = { text = "?", bg = Color3.fromHex("ffffff"), fg = Color3.fromHex("ff2d55"), size = 0.8 },
	Label_BoxOdds = { text = "BOX ODDS", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("3fd8ff"), size = 0.75 },
	Label_OddsCommon = { text = "COMMON  70%", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("ffffff"), size = 0.7 },
	Label_OddsRare = { text = "RARE  25%", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("3fd8ff"), size = 0.7 },
	Label_OddsLegend = { text = "LEGENDARY  5%", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("ffc21a"), size = 0.7 },
	Label_PortalPractice = { text = "TARGET PRACTICE", bg = Color3.fromHex("2a1d5c"), fg = Color3.fromHex("ffe14d"), size = 0.6 },
	Label_PortalHighway = { text = "HIGHWAY", bg = Color3.fromHex("2a1d5c"), fg = Color3.fromHex("ffc21a"), size = 0.6 },
	Label_DailyReward = { text = "DAILY REWARD", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("3fd8ff"), size = 0.6 },
	Label_DailyTimer = { text = "READY!", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("2fe04b"), size = 0.6 },
	Label_Quests = { text = "QUESTS", bg = Color3.fromHex("ffd23f"), fg = Color3.fromHex("2a1748"), size = 0.6 },
	Label_KittyBread = { text = "KITTY BREAD", bg = Color3.fromHex("2a1d5c"), fg = Color3.fromHex("ffd27a"), size = 0.6 },
	Label_PracticeTitle = { text = "TARGET PRACTICE", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("ffe14d"), size = 0.6 },
	Label_PracticeScore = { text = "SCORE 0", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("ffffff"), size = 0.6 },
	Label_PracticeBest = { text = "BEST 0", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("3fd8ff"), size = 0.6 },
	Label_PortalLobby = { text = "BACK TO LOBBY", bg = Color3.fromHex("2a1d5c"), fg = Color3.fromHex("3fd8ff"), size = 0.6 },
	Label_OpenPlot = { text = "OPEN PLOT", bg = Color3.fromHex("1d1636"), fg = Color3.fromHex("3fd8ff"), size = 0.6 },
}

return Theme
