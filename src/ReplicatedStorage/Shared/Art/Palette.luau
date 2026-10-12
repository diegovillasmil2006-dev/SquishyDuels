--!strict
-- Palette: the one colour palette for world and UI (DESIGN §7.2). Shared (server, client and edit-time
-- generators). Constants only: every token is a Color3 made from its DESIGN hex with Color3.fromHex.
-- Rarity colours are not here: they live in Art/RarityStyle (§4.3).
-- Reserved gameplay colours (CoinGold, CoinRing, CoinHighlight, Danger) are never used for decoration; their names
-- are listed in Palette.RESERVED so generators and tests can keep decoration away from them.

-- Module table

local Palette = {
	-- World and UI tokens (§7.2)
	Cream = Color3.fromHex("#FFF4E6"), -- sign panels, trims, UI background
	Vanilla = Color3.fromHex("#F6E3CC"), -- lobby floor
	Strawberry = Color3.fromHex("#FF8FB1"), -- main accent: awnings, gift box, promenade edging, Side A
	Bubblegum = Color3.fromHex("#FFC7DA"), -- promenade carpet, spawn pad, Side A tint
	Mint = Color3.fromHex("#8EDFC4"), -- ribbons, gumdrops
	MintCream = Color3.fromHex("#CFF3E6"), -- squeeze rug, Side B tint
	Lemon = Color3.fromHex("#FFD86B"), -- daily reward, firing line, waypoint beam
	Sky = Color3.fromHex("#8CC8FF"), -- practice range trims
	Lavender = Color3.fromHex("#B9A6E8"), -- trims, practice targets, unowned silhouettes
	LaneLilac = Color3.fromHex("#E4DCF7"), -- practice lane floor
	Blueberry = Color3.fromHex("#8E84C8"), -- arena cover (no squishy uses this hue)
	LavenderMilkA = Color3.fromHex("#DCD3EC"), -- arena floor bands
	LavenderMilkB = Color3.fromHex("#D0C6E4"),
	Cocoa = Color3.fromHex("#6B4A3A"), -- wood shelves and frames
	Ink = Color3.fromHex("#3B2A35"), -- all text, outlines, projectile outline, focus ring inner stroke
	UIPanel = Color3.fromHex("#FFFFFF"), -- UI panels
	UIStroke = Color3.fromHex("#E9D9C8"),
	UIPrimary = Color3.fromHex("#E0466A"), -- primary buttons; white text only on >= 20 px bold labels (≈ 4.0:1)
	-- reading: §7.2 has no "White" token, but §4.3 (Epic label text), §8.1 (face shine) and §9.10 use plain white.
	White = Color3.fromHex("#FFFFFF"),
	-- The dark duel transition fade (§9.12, §9.14): the only full-screen overlay allowed above 30% opacity.
	DuelFade = Color3.fromHex("#2B2440"),

	-- Design arenas (phase 4 spec 2026-10-11): the world colours of the 5 Claude Design arenas (World/Arenas cover,
	-- SDTools Builders/Arenas), named after the design's materials (sd/arena.js, sd/blox.js, sd/arenas2.js and the
	-- shared palette, sd/lobby.js:71-83). World only; plain colours (the design's glows stay unlit, D6).
	ArenaTeamMint = Color3.fromHex("#5FD3AE"), -- team_mint, sd/lobby.js:74
	ArenaTeamStrawberry = Color3.fromHex("#F2687F"), -- team_strawberry, sd/lobby.js:74
	ArenaCourtMint = Color3.fromHex("#BDEAD6"), -- court_mint, sd/arena.js:18
	ArenaCourtStrawberry = Color3.fromHex("#F8CAD4"), -- court_strawberry, sd/arena.js:18
	ArenaCushionCream = Color3.fromHex("#FFF3E2"), -- cushion_cream, sd/arena.js:19
	ArenaTrimWhite = Color3.fromHex("#FFFDF8"), -- trim_white / court_line, sd/lobby.js:75, sd/arena.js:18
	ArenaButter = Color3.fromHex("#FFD25E"), -- butter_yellow, sd/lobby.js:75
	ArenaLilac = Color3.fromHex("#D9C6F5"), -- lilac / marshmallow_band, sd/lobby.js:75, sd/arena.js:21
	ArenaViolet = Color3.fromHex("#B892F0"), -- violet / brick_lilac, sd/lobby.js:75, sd/arenas2.js:182
	ArenaSky = Color3.fromHex("#8FD3F4"), -- sky_blue, sd/lobby.js:76
	ArenaPlum = Color3.fromHex("#3F3756"), -- scoreboard_plum, sd/arena.js:21
	ArenaGold = Color3.fromHex("#E8B84A"), -- gold_trim, sd/lobby.js:77 (small accents only: near the reserved CoinGold)
	ArenaStrawberryRed = Color3.fromHex("#EE4A5C"), -- strawberry_red, sd/arena.js:22 (small accents only: near the reserved Danger)
	ArenaFrogGreen = Color3.fromHex("#6CC56A"), -- frog_green, sd/arena.js:22
	ArenaPebble = Color3.fromHex("#E8DCCB"), -- pebble, sd/lobby.js:80
	ArenaInk = Color3.fromHex("#2B2233"), -- ink_dark, sd/lobby.js:80
	ArenaLampGlow = Color3.fromHex("#FFF6DC"), -- lamp_glow / bulb_glow, sd/arena.js:22, sd/arenas2.js:182 (no glow, D6)
	ArenaGlowCream = Color3.fromHex("#FFF1C2"), -- marquee_glow / lantern_glow, sd/arenas2.js:182, sd/blox.js:20 (no glow, D6)
	ArenaGlass = Color3.fromHex("#E4F6FF"), -- glass, sd/lobby.js:77
	ArenaFloorCream = Color3.fromHex("#F4E6D3"), -- arena_floor_cream, sd/arena.js:18
	ArenaWafer = Color3.fromHex("#E5B06C"), -- wafer, sd/arena.js:20
	ArenaWaferGroove = Color3.fromHex("#C98F4B"), -- wafer_groove, sd/arena.js:20
	ArenaWaferCream = Color3.fromHex("#FFF6E8"), -- wafer_cream, sd/arena.js:20
	ArenaCakeSponge = Color3.fromHex("#F2C98F"), -- cake_sponge, sd/arena.js:20
	ArenaMarshmallow = Color3.fromHex("#FFF9F4"), -- marshmallow, sd/arena.js:21
	ArenaScoreboardScreen = Color3.fromHex("#261F38"), -- scoreboard_screen, sd/arena.js:112
	ArenaCaneWhite = Color3.fromHex("#FFF8F2"), -- cane_white, sd/arena.js:123
	ArenaCrowdBlue = Color3.fromHex("#6EC6F5"), -- crowd gumdrop, sd/arena.js:94
	ArenaGrass = Color3.fromHex("#6CC24A"), -- grass, sd/blox.js:16
	ArenaGrassDark = Color3.fromHex("#58AE3E"), -- grass_dark, sd/blox.js:16
	ArenaPlankLight = Color3.fromHex("#D39A5E"), -- plank_light, sd/blox.js:16
	ArenaPlankMid = Color3.fromHex("#C48850"), -- plank_mid, sd/blox.js:16
	ArenaPlankDark = Color3.fromHex("#8E5A33"), -- plank_dark, sd/blox.js:16
	ArenaLogBark = Color3.fromHex("#9A6236"), -- log_bark, sd/blox.js:17
	ArenaLogEnd = Color3.fromHex("#E8C08A"), -- log_end, sd/blox.js:17
	ArenaPineLeaves = Color3.fromHex("#2F8F4E"), -- pine_leaves, sd/blox.js:17
	ArenaOakLeaves = Color3.fromHex("#4FB252"), -- oak_leaves, sd/blox.js:17
	ArenaTrunk = Color3.fromHex("#7A4E2E"), -- trunk, sd/blox.js:17
	ArenaRock = Color3.fromHex("#9BA2AB"), -- rock, sd/blox.js:18
	ArenaPaintWhite = Color3.fromHex("#FFF8EE"), -- paint_white, sd/blox.js:18
	ArenaCabinRoof = Color3.fromHex("#6E4632"), -- cabin_roof, sd/blox.js:19
	ArenaCabinWindow = Color3.fromHex("#9FD8F2"), -- cabin_window, sd/blox.js:19
	ArenaChimneyStone = Color3.fromHex("#A9A39B"), -- chimney_stone, sd/blox.js:19
	ArenaFireCore = Color3.fromHex("#FFB43B"), -- fire_core, sd/blox.js:19 (no glow, D6)
	ArenaFireTip = Color3.fromHex("#FFE27A"), -- fire_tip, sd/blox.js:19 (no glow, D6)
	ArenaIron = Color3.fromHex("#3B3640"), -- iron, sd/blox.js:20
	ArenaStumpRing = Color3.fromHex("#D8A46C"), -- stump_ring, sd/blox.js:60
	ArenaPlayroomRug = Color3.fromHex("#E6DAF2"), -- playroom_rug, sd/arenas2.js:50
	ArenaQuiltMint = Color3.fromHex("#CDEFE2"), -- quilt_mint, sd/arenas2.js:50
	ArenaQuiltStrawberry = Color3.fromHex("#FAD6DE"), -- quilt_strawberry, sd/arenas2.js:50
	ArenaPeriwinkle = Color3.fromHex("#A9B4F0"), -- periwinkle_velvet, sd/arenas2.js:50
	ArenaPeriwinkleDeep = Color3.fromHex("#8C98E0"), -- periwinkle_deep, sd/arenas2.js:50
	ArenaToyWood = Color3.fromHex("#D6A06A"), -- toy_wood, sd/arenas2.js:50
	ArenaToyWoodDark = Color3.fromHex("#B07A48"), -- toy_wood_dark, sd/arenas2.js:50
	ArenaPillowMintPrint = Color3.fromHex("#A9E8D2"), -- pillow_mint_print, sd/arenas2.js:50
	ArenaPillowStrawberryPrint = Color3.fromHex("#F9B3C2"), -- pillow_berry_print, sd/arenas2.js:50
	ArenaReefSand = Color3.fromHex("#F3DFB4"), -- reef_sand, sd/arenas2.js:121
	ArenaCourtAqua = Color3.fromHex("#BDEDEE"), -- court_aqua, sd/arenas2.js:121
	ArenaCourtCoral = Color3.fromHex("#FFD6CC"), -- court_coral, sd/arenas2.js:121
	ArenaSponge = Color3.fromHex("#F9D35B"), -- sponge_yellow, sd/arenas2.js:121
	ArenaSpongePore = Color3.fromHex("#D9A534"), -- sponge_pore, sd/arenas2.js:121
	ArenaClamShell = Color3.fromHex("#FFE3EC"), -- clam_shell, sd/arenas2.js:121
	ArenaPearl = Color3.fromHex("#FFF6FA"), -- pearl, sd/arenas2.js:121
	ArenaClamInner = Color3.fromHex("#F8A8BD"), -- clam_inner, sd/arenas2.js:121
	ArenaBrainCoral = Color3.fromHex("#F49AC1"), -- brain_coral, sd/arenas2.js:121
	ArenaSeaGlass = Color3.fromHex("#9FE3C9"), -- sea_glass, sd/arenas2.js:121
	ArenaSeaGlassTop = Color3.fromHex("#D2F5E8"), -- sea_glass_top, sd/arenas2.js:121
	ArenaAquariumWater = Color3.fromHex("#6CC8EA"), -- aquarium_water, sd/arenas2.js:121 (no glow, D6)
	ArenaKelp = Color3.fromHex("#5DBB7A"), -- kelp, sd/arenas2.js:121
	ArenaKelpDark = Color3.fromHex("#3E9C5F"), -- kelp_dark, sd/arenas2.js:121
	ArenaReefRock = Color3.fromHex("#B6A6C9"), -- reef_rock, sd/arenas2.js:121
	ArenaReefRockWarm = Color3.fromHex("#D8B9A6"), -- reef_rock_warm, sd/arenas2.js:121
	ArenaTubeCoralOrange = Color3.fromHex("#FFB070"), -- tube_coral_orange, sd/arenas2.js:121
	ArenaTubeCoralLilac = Color3.fromHex("#C6A3F4"), -- tube_coral_lilac, sd/arenas2.js:121
	ArenaBubble = Color3.fromHex("#EFFBFF"), -- bubble, sd/arenas2.js:121
	ArenaTankGlass = Color3.fromHex("#CFF3FF"), -- tank_glass, sd/arenas2.js:121
	ArenaFishOrange = Color3.fromHex("#FF9A4D"), -- fish_orange, sd/arenas2.js:160
	ArenaFishPink = Color3.fromHex("#F68FB4"), -- fish_pink, sd/arenas2.js:160
	ArenaCarpet = Color3.fromHex("#45407A"), -- arcade_carpet, sd/arenas2.js:182
	ArenaTileMintA = Color3.fromHex("#A8E6D2"), -- tile_mint_a, sd/arenas2.js:182
	ArenaTileMintB = Color3.fromHex("#DDF6EE"), -- tile_mint_b, sd/arenas2.js:182
	ArenaTileStrawberryA = Color3.fromHex("#F9B9C6"), -- tile_berry_a, sd/arenas2.js:182
	ArenaTileStrawberryB = Color3.fromHex("#FDE3E9"), -- tile_berry_b, sd/arenas2.js:182
	ArenaBrickSky = Color3.fromHex("#7FC8F8"), -- brick_sky, sd/arenas2.js:182
	ArenaBrickGreen = Color3.fromHex("#8BE3A1"), -- brick_green, sd/arenas2.js:182
	ArenaCabinetScreen = Color3.fromHex("#2A2342"), -- cabinet_screen, sd/arenas2.js:182 (no glow, D6)
	ArenaConveyorBelt = Color3.fromHex("#4A4560"), -- conveyor_belt, sd/arenas2.js:182

	-- Foam UI tokens (UI only; foam UI restyle spec 2026-10-09, read through UI/Theme). The world keeps the tokens
	-- above.
	-- Paper:
	Frosting = Color3.fromHex("#FFF6EA"), -- panel face
	PanelAlt = Color3.fromHex("#FFF9F1"),
	Biscuit = Color3.fromHex("#F1DEC4"), -- bar tracks, inset fields
	Bevel = Color3.fromHex("#EBD7BC"), -- the cream bevel shade
	InkUI = Color3.fromHex("#2B2233"), -- UI outlines and text (14.2:1 on Frosting)
	Ink2 = Color3.fromHex("#6A5F70"), -- captions (5.6:1 on Frosting)
	-- Accent pairs, face / bevel shade (InkUI text on every face >= 5.1:1).
	UIStrawberry = Color3.fromHex("#F2687F"), -- primary CTA, Squishies tile
	UIStrawberryShade = Color3.fromHex("#D04B66"),
	UIMint = Color3.fromHex("#5FD3AE"), -- progress fills
	UIMintShade = Color3.fromHex("#36AE89"),
	UIQuestMint = Color3.fromHex("#4FCBA3"), -- Quests tile
	UIQuestMintShade = Color3.fromHex("#2FA884"),
	UILilac = Color3.fromHex("#A98BE8"), -- Boxes tile, locked
	UILilacShade = Color3.fromHex("#8668CF"),
	UISkyBlue = Color3.fromHex("#5DB8F0"), -- Daily tile, info
	UISkyBlueShade = Color3.fromHex("#3C97D4"),
	-- Shop tile ("Apple"; the spec's hue rule): hue 90.5°, so 47.5° from CoinGold (43.0°), 55.8° from Exclusive
	-- (34.6°) and 86.4° from Danger (4.1°); 70.2° from the Quests tile, 100.5° from Strawberry, 112.4° from Sky blue
	-- and 168.9° from Lilac; InkUI text 8.3:1, white text only with the InkUI outline.
	UIApple = Color3.fromHex("#8FD14F"),
	UIAppleShade = Color3.fromHex("#6AAE2E"),
	-- Disabled surfaces.
	DisabledFace = Color3.fromHex("#E9E1D6"),
	DisabledStroke = Color3.fromHex("#A79FAB"),
	DisabledShade = Color3.fromHex("#D9CFC2"),
	DisabledText = Color3.fromHex("#8C8290"),

	-- Candy UI tokens (UI overhaul 2026-10-11: the bold, outlined look of the Steal an Egg references in Squishy Duels'
	-- own candy colours; read through UI/Theme, which maps them to its semantic names). Windows are dark plum with heavy
	-- plum outlines; colour carries purpose: Coral brand / duel, Lavender boxes and reveals, Cyan info and daily, Mint
	-- quests and success, Lime shop and buying, Gold Coins and celebration, Red close / cancel / errors. Each accent has a
	-- face and a bevel shade. Text on the dark surfaces is WarmWhite (14.1:1 on PanelBody), captions TextMuted (8.0:1),
	-- hints TextFaint (4.9:1); text on an accent face is white with the PlumInk outline (display kinds) or PlumInk.
	CandyCoral = Color3.fromHex("#FF5B91"),
	CandyCoralShade = Color3.fromHex("#D93C75"),
	CandyLavender = Color3.fromHex("#AB78FF"),
	CandyLavenderShade = Color3.fromHex("#8452E6"),
	CandyCyan = Color3.fromHex("#36C9FF"),
	CandyCyanShade = Color3.fromHex("#169FDA"),
	CandyMint = Color3.fromHex("#47D7AE"),
	CandyMintShade = Color3.fromHex("#22AE88"),
	CandyLime = Color3.fromHex("#8DEE42"),
	CandyLimeShade = Color3.fromHex("#5CBF1D"),
	CandyGold = Color3.fromHex("#FFD451"),
	CandyGoldShade = Color3.fromHex("#E0A72A"),
	CandyRed = Color3.fromHex("#FF414F"),
	CandyRedShade = Color3.fromHex("#C92738"),
	CandyPlum = Color3.fromHex("#5E4F78"), -- the neutral (secondary) button face; white text
	CandyPlumShade = Color3.fromHex("#45395A"),
	-- Surfaces.
	PlumInk = Color3.fromHex("#251B32"), -- every UI outline; text on light faces
	PanelBody = Color3.fromHex("#30283E"), -- window and card body
	PanelRaised = Color3.fromHex("#443951"), -- a raised card or row on a window
	PanelRecess = Color3.fromHex("#1F1829"), -- recessed fields
	PanelTrack = Color3.fromHex("#140F1B"), -- bar, slider and switch tracks (darker than a recessed field)
	PanelBevel = Color3.fromHex("#211A2C"), -- the dark bevel band under a dark surface
	PanelRim = Color3.fromHex("#8E7BB0"), -- the inner rim highlight (drawn mostly transparent)
	WarmWhite = Color3.fromHex("#FFF8EE"), -- text on dark surfaces; the light "sticker" face
	TextMuted = Color3.fromHex("#C9BEDA"), -- captions on dark surfaces
	TextFaint = Color3.fromHex("#9D91B0"), -- hints on dark surfaces
	StickerBevel = Color3.fromHex("#E3CFB4"), -- the bevel band under a light sticker (chips, world labels)
	DisabledFaceDark = Color3.fromHex("#4A4159"),
	DisabledShadeDark = Color3.fromHex("#3A3248"),
	DisabledTextDark = Color3.fromHex("#ABA0BB"),
	Backdrop = Color3.fromHex("#140E1C"), -- the modal dimmer and wash

	-- Moves (spec phase 5): the design's dash and Epic ultimate effect colours, world only (VfxController, DashController,
	-- Anim/UltFx). Where the design uses its own rarity colour, the game's Art/RarityStyle colour is used instead.
	DashPuff = Color3.fromHex("#FFF6EA"), -- design: fp.js:516 (push-off and plant puffs)
	DashPuffShade = Color3.fromHex("#E6D2B5"), -- design: fp.js:516
	DashRibbonStrawberry = Color3.fromHex("#F8CAD4"), -- design: fp.js:529 (the strawberry runner's ribbons)
	DashRibbonMint = Color3.fromHex("#BDEAD6"), -- design: main.js:341, arena.js:186 (the mint team's)
	UltSprinkleLane = Color3.fromHex("#F68FB4"), -- design: fp.js:340 (Sprinkle Roller's lane), fp.js:243 (a sprinkle)
	UltSprinkleBlue = Color3.fromHex("#7FD3F7"), -- design: fp.js:243
	UltSprinkleYellow = Color3.fromHex("#FFD25E"), -- design: fp.js:243
	UltSprinkleGreen = Color3.fromHex("#8BE3A1"), -- design: fp.js:243
	UltRainZone = Color3.fromHex("#B892F0"), -- design: fp.js:348 (Rain Check's zone ring)
	UltRainShadow = Color3.fromHex("#6A5A9A"), -- design: fp.js:355 (a drop's shadow)
	UltRainDrop = Color3.fromHex("#9DB8FF"), -- design: fp.js:356, 372 (a drop and its splash)
	UltRainDrizzle = Color3.fromHex("#E6DEFF"), -- design: fp.js:267 (the hovering bunny's drizzle)
	UltBubbleShell = Color3.fromHex("#CFF3FF"), -- design: fp.js:360 (Bubble Pop's bubble)
	UltBubblePop = Color3.fromHex("#8FDCC4"), -- design: fp.js:361 (the pop ring and burst)
	UltBubbleFoam = Color3.fromHex("#DDF4FF"), -- design: fp.js:361
	UltBubblePink = Color3.fromHex("#F9AFCB"), -- design: fp.js:361

	-- Reserved gameplay colours (§7.2): never decoration.
	CoinGold = Color3.fromHex("#FFC83D"),
	CoinRing = Color3.fromHex("#D99A1E"),
	CoinHighlight = Color3.fromHex("#FFE08A"),
	Danger = Color3.fromHex("#FF5A4E"), -- Dragon Rush lane and error states only

	-- Names of the reserved gameplay colours above.
	RESERVED = table.freeze({ "CoinGold", "CoinRing", "CoinHighlight", "Danger" }),
}

return table.freeze(Palette)
