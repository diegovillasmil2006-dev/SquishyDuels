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

	-- Lobby kit (phase 3, user decision 2026-10-11 "build the design's lobby"): the world colours of the Claude Design
	-- lobby (sd/lobby.js palette, lines 71-83, and its inline colours), named after the design's materials. World only,
	-- for the lobby generator (SDTools LobbyBuilder, Kit/Props); plain colours (the design's glows stay unlit except the
	-- lit state rings, D7).
	LobbyFloor = Color3.fromHex("#F4E6D3"), -- lobby_floor_cream, lobby.js:73
	LobbySeam = Color3.fromHex("#E8D6BF"), -- lobby_tile_seam, lobby.js:73
	LobbyPath = Color3.fromHex("#F8CAD4"), -- path_pink, lobby.js:73
	LobbyCurb = Color3.fromHex("#FFF6EA"), -- path_curb_cream, lobby.js:73
	LobbyMint = Color3.fromHex("#5FD3AE"), -- team_mint, lobby.js:74
	LobbyStrawberry = Color3.fromHex("#F2687F"), -- team_strawberry, lobby.js:74
	LobbyCourtMint = Color3.fromHex("#BDEAD6"), -- court_mint, lobby.js:74
	LobbyCourtStrawberry = Color3.fromHex("#F8CAD4"), -- court_strawberry, lobby.js:74
	LobbyCushionCream = Color3.fromHex("#FFF3E2"), -- cushion_cream, lobby.js:75
	LobbyTrimWhite = Color3.fromHex("#FFFDF8"), -- trim_white, lobby.js:75
	LobbyButter = Color3.fromHex("#FFD25E"), -- butter_yellow, lobby.js:75
	LobbyLilac = Color3.fromHex("#D9C6F5"), -- lilac, lobby.js:75
	LobbyViolet = Color3.fromHex("#B892F0"), -- violet, lobby.js:75
	LobbySky = Color3.fromHex("#8FD3F4"), -- sky_blue, lobby.js:76
	LobbyPlum = Color3.fromHex("#3F3756"), -- scoreboard_plum, lobby.js:76
	LobbyWafer = Color3.fromHex("#E5B06C"), -- wafer, lobby.js:76
	LobbyWaferGroove = Color3.fromHex("#C98F4B"), -- wafer_groove, lobby.js:76
	LobbyGold = Color3.fromHex("#E8B84A"), -- gold_trim, lobby.js:77
	LobbyRoyalVelvet = Color3.fromHex("#7E57C2"), -- royal_velvet, lobby.js:77
	LobbyVelvetRope = Color3.fromHex("#C9405A"), -- velvet_rope, lobby.js:77
	LobbyGlass = Color3.fromHex("#E4F6FF"), -- glass, lobby.js:77
	LobbyLampGlow = Color3.fromHex("#FFF6DC"), -- lamp_glow, lobby.js:78 (unlit, D7)
	LobbyStrawberryRed = Color3.fromHex("#EE4A5C"), -- strawberry_red, lobby.js:78
	LobbyCork = Color3.fromHex("#D9A06B"), -- cork, lobby.js:78
	LobbyJellyShell = Color3.fromHex("#FF6F86"), -- jelly_shell, lobby.js:79
	LobbyJellyCore = Color3.fromHex("#E8445C"), -- jelly_core, lobby.js:79
	LobbyMarshmallow = Color3.fromHex("#FFF9F4"), -- marshmallow, lobby.js:79
	LobbyMallowToast = Color3.fromHex("#E2A866"), -- mallow_toast, lobby.js:79
	LobbyPebble = Color3.fromHex("#E8DCCB"), -- pebble, lobby.js:80 (the unlit queue pad rings, lobby.js:193)
	LobbyInk = Color3.fromHex("#2B2233"), -- ink_dark, lobby.js:80 (also the plates' text and border, lobby.js:29-30)
	LobbyCottonPink = Color3.fromHex("#F9B8D0"), -- cotton_candy_pink, lobby.js:80
	LobbyCottonBlue = Color3.fromHex("#A9DDF6"), -- cotton_candy_blue, lobby.js:80
	LobbyCandyStick = Color3.fromHex("#FFF4E6"), -- candy_stick, lobby.js:80
	LobbyWindowSky = Color3.fromHex("#CFEFFF"), -- window_sky, lobby.js:81 (unlit, D7)
	LobbyPlate = Color3.fromHex("#FFF9F1"), -- the text plates' default background, lobby.js:29
	LobbyRangeArrow = Color3.fromHex("#FFB070"), -- the RANGE arrow, lobby.js:159
	LobbyCoinInner = Color3.fromHex("#F6CF63"), -- coin_inner, lobby.js:249
	LobbyQuestMint = Color3.fromHex("#D9F4EA"), -- the Daily quest cards, lobby.js:296
	LobbyQuestButter = Color3.fromHex("#FFF0C4"), -- the Weekly quest cards, lobby.js:296
	LobbyQuestPink = Color3.fromHex("#FBDDE3"), -- the Duels quest cards, lobby.js:296
	LobbyQuestBar = Color3.fromHex("#FFC93C"), -- the Weekly progress strips, lobby.js:296
	LobbyMallowCenter = Color3.fromHex("#F0C890"), -- mallow_toast_center, lobby.js:365

	-- Squish Island (lobby bases spec 2026-10-11 §8, build plan Phase 4): world only (SDTools LobbyBuilder, BaseService).
	IslandGrass = Color3.fromHex("#5CCB4E"), -- §8 grass
	IslandGrassEdge = Color3.fromHex("#3E9E3A"), -- §8 grass edge
	IslandSand = Color3.fromHex("#F5DC9B"), -- §8 sand
	IslandSea = Color3.fromHex("#2BA7E3"), -- §8 sea
	IslandShallow = Color3.fromHex("#6FD3F5"), -- §8 shallow water
	HubTile = Color3.fromHex("#F6F7F9"), -- §8 hub tiles
	HubTileB = Color3.fromHex("#E3E8EF"), -- §8 hub tiles (the paths)
	HubWood = Color3.fromHex("#A8673A"), -- §8 wood
	-- The 10 base colours, one per plot (§8, B1 -> B10), and their light shades (reading: 60% toward white) for the
	-- plinth; an open plot is grey (§4).
	BaseRed = Color3.fromHex("#E8343F"),
	BaseRedLight = Color3.fromHex("#F6AEB2"),
	BaseOrange = Color3.fromHex("#FF8A1F"),
	BaseOrangeLight = Color3.fromHex("#FFD0A5"),
	BaseYellow = Color3.fromHex("#FFC51F"),
	BaseYellowLight = Color3.fromHex("#FFE8A5"),
	BaseLime = Color3.fromHex("#9BE22B"),
	BaseLimeLight = Color3.fromHex("#D7F3AA"),
	BaseTeal = Color3.fromHex("#1FC7B6"),
	BaseTealLight = Color3.fromHex("#A5E9E2"),
	BaseSky = Color3.fromHex("#38B6FF"),
	BaseSkyLight = Color3.fromHex("#AFE2FF"),
	BaseBlue = Color3.fromHex("#2E7BF0"),
	BaseBlueLight = Color3.fromHex("#ABCAF9"),
	BaseNavy = Color3.fromHex("#2B3A8C"),
	BaseNavyLight = Color3.fromHex("#AAB0D1"),
	BasePurple = Color3.fromHex("#8E4FE0"),
	BasePurpleLight = Color3.fromHex("#D2B9F3"),
	BasePink = Color3.fromHex("#FF5FA2"),
	BasePinkLight = Color3.fromHex("#FFBFDA"),
	BaseOpen = Color3.fromHex("#A7ADB5"), -- reading: an open plot's rim and caps
	BaseOpenLight = Color3.fromHex("#D9DDE2"), -- reading: an open plot's floor
	-- The 10 capsule looks (progression spec 2026-10-12 §4; SDTools CapsuleBuilder's look table also uses lobby kit
	-- tokens): Foam cream, Jelly glossy red, Marshmallow white with toasted trim, Gummy see-through green, Taffy pink and
	-- white stripes, Caramel amber, Bubblegum bright pink, Rainbow stripes, Crystal icy see-through, Royal purple and
	-- gold. Readings: the hexes (the spec names the looks only).
	CapsuleFoam = Color3.fromHex("#FFF1DC"),
	CapsuleFoamTrim = Color3.fromHex("#F7B8C8"),
	CapsuleFoamGlass = Color3.fromHex("#FFF8EC"),
	CapsuleGummy = Color3.fromHex("#3FBF4F"),
	CapsuleGummyLight = Color3.fromHex("#A6F0A0"),
	CapsuleGummyGlass = Color3.fromHex("#6EE07A"),
	CapsuleTaffy = Color3.fromHex("#FF9EC4"),
	CapsuleTaffyGlass = Color3.fromHex("#FFD6E6"),
	CapsuleCaramel = Color3.fromHex("#D98A2B"),
	CapsuleCaramelDark = Color3.fromHex("#8E5A1F"),
	CapsuleCaramelGlass = Color3.fromHex("#F2B35E"),
	CapsuleBubblegum = Color3.fromHex("#FF5FB4"),
	CapsuleBubblegumLight = Color3.fromHex("#FFC2E2"),
	CapsuleBubblegumGlass = Color3.fromHex("#FF8ACB"),
	CapsuleRainbowGlass = Color3.fromHex("#E8F7FF"),
	CapsuleCrystal = Color3.fromHex("#BFE9FF"),
	CapsuleCrystalGlass = Color3.fromHex("#D8F4FF"),
	CapsuleRoyalGlass = Color3.fromHex("#CDB8F0"),

	-- The knead screen in Inspect (spec phase2-squeeze §1.16-§1.20; user decision 2026-10-11: the design's exact hex,
	-- read by UI/Components/WaxMeter, UI/KneadOverlay and Anim/FlakePool). The paper and ink of the design's HUD, its coat
	-- bar and state word, the vignette's warm stops (its outer stop is KneadInk) and the re-wax sparkle's cream.
	KneadPaper = Color3.fromHex("#FFF9F1"), -- design: html:20 (--paper)
	KneadInk = Color3.fromHex("#22172A"), -- design: html:20 (--ink); html:70 (the vignette's 100% stop)
	WaxBar = Color3.fromHex("#F2C94C"), -- design: html:76
	WaxState = Color3.fromHex("#C94860"), -- design: html:77
	VignetteGlow = Color3.fromHex("#FFD696"), -- design: html:70 (rgba(255,214,150,0) at 44%)
	VignetteWarm = Color3.fromHex("#FFBE78"), -- design: html:70 (rgba(255,190,120,.10) at 64%)
	WaxSparkle = Color3.fromHex("#FFF2B8"), -- design: fp.js:687 (with White)

	-- Moves (spec phase 5): the design's dash and Epic ultimate effect colours, world only (VfxController, DashController,
	-- Anim/UltFx). Where the design uses its own rarity colour, the game's Art/RarityStyle colour is used instead.
	DashPuff = Color3.fromHex("#FFF6EA"), -- design: fp.js:516 (push-off and plant puffs)
	DashPuffShade = Color3.fromHex("#E6D2B5"), -- design: fp.js:516
	DashRibbonStrawberry = Color3.fromHex("#F8CAD4"), -- design: fp.js:529 (the strawberry runner's ribbons)
	DashRibbonMint = Color3.fromHex("#BDEAD6"), -- design: main.js:341, arena.js:186 (the mint team's)
	-- 2026-10-15 dash + double jump overhaul: the effects' stronger team glow (Anim/MoveVfx tints, the afterimages).
	DashGlowStrawberry = Color3.fromHex("#FF7FAA"),
	DashGlowMint = Color3.fromHex("#4FD8AE"),
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
	UltBounceHeartRed = Color3.fromHex("#EE4A5C"), -- design: fp.js:239 (the Frog's bounce hearts; Bubble Pop's bounce)
	UltBounceHeartGreen = Color3.fromHex("#6CC56A"), -- design: fp.js:239

	-- Inspect showcases (final polish 2026-10-11): the design's own speck colours of the first-person inspect events,
	-- overlay only (Anim/InspectTracks). A toy's other specks use its Catalog accent and White.
	InspectFlapBlue = Color3.fromHex("#8BD0F3"), -- design: fp.js:180 (flap petals, with white)
	InspectRibbitRed = Color3.fromHex("#EE4A5C"), -- design: fp.js:186 (ribbit hearts; tiny, overlay only)
	InspectSnapGold = Color3.fromHex("#E8B84A"), -- design: fp.js:179 (the chocolate snap's foil glint, with white)
	InspectSparkleYellow = Color3.fromHex("#FFE27A"), -- design: fp.js:189 (sparkle, with white and lilac)
	InspectSparkleLilac = Color3.fromHex("#D5C8F6"), -- design: fp.js:189
	InspectEmberOrange = Color3.fromHex("#FF9A4D"), -- design: fp.js:182 (the Dragon's roar embers)
	InspectEmberYellow = Color3.fromHex("#FFD25E"), -- design: fp.js:182
	InspectEmberPink = Color3.fromHex("#FF6F7D"), -- design: fp.js:182
	InspectBubble = Color3.fromHex("#DDF4FF"), -- design: fp.js:191 (the axolotl's bubbles)

	-- The nameplate faces of the ranks above Lv 50 (progression spec 2026-10-12 §10; build plan Phase 5): light colours,
	-- so the plates' PlumInk text keeps at least 4.5:1 (NameplateController_Test). Readings: the hexes (the spec names the
	-- ranks only).
	RankLegend = Color3.fromHex("#FFB98A"),
	RankMythic = Color3.fromHex("#D2B4FF"),
	RankCosmic = Color3.fromHex("#AFC4FF"),
	RankGalaxy = Color3.fromHex("#F2B8F5"),
	RankInfinite = Color3.fromHex("#9FEADF"),

	-- Sticker UI (design 'Squishy Duels UI FINAL', 2026-10-14; plan work/ui/PLAN.md R1): the design's own hex, one
	-- token per hex, read through UI/Theme (which stops reading the Candy UI block above, but StickerBevel for the
	-- world plates). `H:n` = "Squishy Duels HUD.dc.html" line n, `lib:n` = uploads/hud-lib.js line n. The design's
	-- soft rgba() tints are these colours at an alpha (Config.UI Sticker). A design hex an older token already holds is
	-- read there: the cream sticker #FFF6EA (H:171) is Frosting.
	-- Ink and surfaces.
	StickerInk = Color3.fromHex("#1E1428"), -- H:75: every outline, lip and text stroke
	StickerInkDeep = Color3.fromHex("#120B1E"), -- H:240: the stat, odds and quest bar outlines
	StickerSwitchOff = Color3.fromHex("#1A1229"), -- H:980: a switch's off track
	StickerTrough = Color3.fromHex("#5130C7"), -- H:141: bar troughs and slots
	StickerWell = Color3.fromHex("#5B36D9"), -- H:236: the stats well, the reset / reward / timer pills
	StickerWindowTop = Color3.fromHex("#FFD6EC"), -- H:182: the windows' pink body
	StickerWindowBottom = Color3.fromHex("#FFAFD6"), -- H:182
	StickerCardTop = Color3.fromHex("#A385FF"), -- H:203: the purple cards, rows, off tabs and the default toast
	StickerCardBottom = Color3.fromHex("#7A57F2"), -- H:203
	StickerPillTop = Color3.fromHex("#9775FF"), -- H:75: the coin pill, the duel search bar
	StickerPillBottom = Color3.fromHex("#6C47F5"), -- H:75
	StickerToyTile = Color3.fromHex("#EFE6FF"), -- H:274: the toy thumbnail tiles
	StickerScrollThumb = Color3.fromHex("#5A4880"), -- H:22: the scroll bar thumb
	StickerScrimPurple = Color3.fromHex("#6E3CDC"), -- H:178: the modal scrim's outer colour (the dimmer)
	-- Text.
	StickerOnWindowText = Color3.fromHex("#8A2468"), -- H:196: text on the pink window body (6.3:1 / 4.9:1)
	StickerCoinText = Color3.fromHex("#FFE36B"), -- H:79: the coin number, prices and rewards
	StickerTextSoft = Color3.fromHex("#F3EDFF"), -- H:239: body text on the purple surfaces and the well
	StickerTextMuted = Color3.fromHex("#EDE4FF"), -- H:142: captions
	StickerTextChip = Color3.fromHex("#E9E1FA"), -- H:233: the throw-style chip's text
	StickerTabOff = Color3.fromHex("#D9CFF0"), -- H:929: an unselected tab's text
	StickerTextGrey = Color3.fromHex("#C9BFD9"), -- H:530: the level-up pill's old level
	StickerCollected = Color3.fromHex("#FFE3EF"), -- H:186: "Collected"
	StickerBoxHeaderText = Color3.fromHex("#0B4B5E"), -- H:260: the Boxes subtitle on the cyan band
	-- UI FINAL R7 (the Boxes window and the box reveal; `lib:n` = uploads/hud-lib.js, `stage:n` = uploads/box-stage.html):
	-- the card plates (lib:44-46; the Royal plate's top is StickerFeaturedTop), the reveal's scrim and flash (H:471,
	-- H:503), the stage's ambient and floor blob (stage:39, stage:71), the gift tints of the art's fallback, and the
	-- three box models (Art/BoxSoft, BoxSweet, BoxRoyal: stage:58-186, their beam and inner light colours).
	StickerBoxSnackTop = Color3.fromHex("#9BF1F8"), -- lib:44: the Soft box plate
	StickerBoxSnackEnd = Color3.fromHex("#2CB8D4"),
	StickerBoxSweetTop = Color3.fromHex("#D9B8FF"), -- lib:45
	StickerBoxSweetEnd = Color3.fromHex("#8D5BEA"),
	StickerBoxTreatEnd = Color3.fromHex("#F2A31B"), -- lib:46 (its top: StickerFeaturedTop #FFE58A)
	StickerRevealScrimIn = Color3.fromHex("#7850C8"), -- H:471: rgba(120,80,200,.9) at 0%
	StickerRevealScrimOut = Color3.fromHex("#1E103C"), -- H:471: rgba(30,16,60,.95) at 80%
	StickerRevealFlashMid = Color3.fromHex("#FFF6D8"), -- H:503: the flash's 45% stop
	BoxStageAmbient = Color3.fromHex("#D9C8F0"), -- stage:39: the hemisphere light's ground colour
	BoxFloorBlob = Color3.fromHex("#140A28"), -- stage:71: rgba(20,10,40,.55) -> 0
	BoxTintSweet = Color3.fromHex("#D9C6FF"), -- the Sweet box art's fallback gift tint
	BoxTintTreat = Color3.fromHex("#FFE6A6"), -- the Royal box art's fallback gift tint
	BoxSoftPolka = Color3.fromHex("#8FF3F8"), -- stage:58: the polka gradient's top (to #3FCFE2)
	BoxSoftRibbon = Color3.fromHex("#FF6F9E"), -- stage:103
	BoxSoftBlush = Color3.fromHex("#FF8FB8"), -- stage:112
	BoxSoftEar = Color3.fromHex("#7FE9F2"), -- stage:121
	BoxSoftEarInner = Color3.fromHex("#FFB3CF"), -- stage:122
	BoxSoftLight = Color3.fromHex("#FFE7F2"), -- stage:126
	BoxSoftPart = Color3.fromHex("#FF9CC2"), -- stage:126: its sparkles (with White, BoxSoftPolka, StickerCoinText)
	BoxSweetStripeA = Color3.fromHex("#FFB8DA"), -- stage:63
	BoxSweetStripeB = Color3.fromHex("#D7B4FF"), -- stage:63
	BoxSweetBand = Color3.fromHex("#7FF0C8"), -- stage:131
	BoxSweetCream = Color3.fromHex("#FFF5FA"), -- stage:132
	BoxSweetDome = Color3.fromHex("#FF8FC4"), -- stage:139
	BoxSweetCherry = Color3.fromHex("#FF2E55"), -- stage:151
	BoxSweetStem = Color3.fromHex("#3FAF5E"), -- stage:153
	BoxSweetLight = Color3.fromHex("#FFD6F0"), -- stage:155
	BoxSweetBeam = Color3.fromHex("#FFB8E0"), -- stage:155
	BoxSprinkleGreen = Color3.fromHex("#9BF58A"), -- stage:142 (with StickerCoinText, BoxSoftEar, White)
	BoxSprinklePurple = Color3.fromHex("#C9A0FF"), -- stage:142
	BoxSprinkleRed = Color3.fromHex("#FF6F7E"), -- stage:142
	BoxRoyalVelvet = Color3.fromHex("#6B2BE0"), -- stage:159 (the gold: StickerGoldMid #FFC23A, stage:78)
	BoxRoyalGemCyan = Color3.fromHex("#3FE0FF"), -- stage:176
	BoxRoyalGemPink = Color3.fromHex("#FF3FA4"), -- stage:167, stage:176
	BoxRoyalGemGreen = Color3.fromHex("#5CF27A"), -- stage:176
	BoxRoyalGemYellow = Color3.fromHex("#FFE14A"), -- stage:176
	BoxRoyalKeyhole = Color3.fromHex("#FFF3B0"), -- stage:168
	BoxRoyalSeam = Color3.fromHex("#FFE38A"), -- stage:169
	BoxRoyalLight = Color3.fromHex("#FFD36B"), -- stage:186 (its beam: Lemon #FFD86B)
	BoxRoyalSheen = Color3.fromHex("#FF9CF0"), -- stage:159, stage:186: the velvet sheen, a sparkle colour
	-- Buttons and badges (each a top / mid / end or top / end gradient, 180deg).
	StickerGreenTop = Color3.fromHex("#A6F796"), -- H:245: the primary (green) buttons
	StickerGreenMid = Color3.fromHex("#4CD45C"), -- H:245 (55%)
	StickerGreenEnd = Color3.fromHex("#2FB447"), -- H:245
	StickerGreen2End = Color3.fromHex("#38C150"), -- H:80: the small green chips and the switch's on track
	StickerToggleOnTop = Color3.fromHex("#9BF58A"), -- H:980: the switch's on track
	StickerCyanTop = Color3.fromHex("#9DEFFA"), -- H:247: the secondary (cyan) buttons
	StickerCyanMid = Color3.fromHex("#3CC6E2"), -- H:247 (55%)
	StickerCyanEnd = Color3.fromHex("#1FA6C9"), -- H:247
	StickerGoldTop = Color3.fromHex("#FFE88A"), -- H:498: AGAIN (coins and celebration only)
	StickerGoldMid = Color3.fromHex("#FFC23A"), -- H:498 (55%)
	StickerGoldEnd = Color3.fromHex("#F59A12"), -- H:498
	StickerRedTop = Color3.fromHex("#FF8A9A"), -- H:102: count badges, NEW, "Not enough coins!"
	StickerRedEnd = Color3.fromHex("#E83A5A"), -- H:102
	StickerCloseTop = Color3.fromHex("#FF9A9A"), -- H:252: every window's close X
	StickerCloseEnd = Color3.fromHex("#F0344A"), -- H:252
	StickerCancelRedTop = Color3.fromHex("#FF8A8A"), -- H:145: the duel search's cancel X (with StickerCloseEnd)
	StickerYellowTop = Color3.fromHex("#FFF08A"), -- H:120: the daily "!" badge
	StickerYellowEnd = Color3.fromHex("#FFB627"), -- H:120
	StickerMintTop = Color3.fromHex("#9AF5D2"), -- H:210: "Equipped", the selected quest tab
	StickerMintEnd = Color3.fromHex("#25B886"), -- H:210
	StickerDisabledTop = Color3.fromHex("#CBBDF2"), -- H:246: a disabled button (EQUIPPED)
	StickerDisabledEnd = Color3.fromHex("#A996E0"), -- H:246
	StickerCancelTop = Color3.fromHex("#C4B4F0"), -- H:462: CANCEL
	StickerCancelEnd = Color3.fromHex("#9B86DB"), -- H:462
	StickerPinkTop = Color3.fromHex("#FFA6C8"), -- H:126: the DUEL button
	StickerPinkMid = Color3.fromHex("#FF5D97"), -- H:126 (55%)
	StickerPinkEnd = Color3.fromHex("#EE3B7B"), -- H:126
	StickerDuelBevel = Color3.fromHex("#961446"), -- H:126: the DUEL button's bottom bevel tint (at .3)
	StickerFoundBevel = Color3.fromHex("#A05000"), -- H:149: MATCH FOUND's bottom bevel tint (at .25)
	-- Bars.
	StickerBlueBarTop = Color3.fromHex("#8BEBFF"), -- lib:37: the blue stat bars and quest bars
	StickerBlueBarEnd = Color3.fromHex("#25AEE6"), -- lib:37
	StickerPurpleBarTop = Color3.fromHex("#C9A8FF"), -- lib:39: the purple stat bars
	StickerPurpleBarEnd = Color3.fromHex("#8A55EE"), -- lib:39
	StickerGripTop = Color3.fromHex("#B5FBE0"), -- H:85: the Grip bar
	StickerGripEnd = Color3.fromHex("#2FC48F"), -- H:85
	StickerVolumeTop = Color3.fromHex("#FFB1CB"), -- H:444: the volume slider
	StickerVolumeEnd = Color3.fromHex("#FF5C93"), -- H:444
	-- Chips.
	StickerUltTop = Color3.fromHex("#FFD79A"), -- H:234: the Ultimate chip (with StickerGoldEnd)
	StickerUltText = Color3.fromHex("#4A2600"), -- H:234
	StickerThrowChip = Color3.fromHex("#4A3A6E"), -- H:233: the throw-style chip
	-- Effects (UI FINAL R2, the motion kit: UI/UiFx's design effects and Config.UI.Fx's events).
	StickerFxYellow = Color3.fromHex("#FFD84A"), -- lib:221: the burst and rain pieces
	StickerFxPink = Color3.fromHex("#FF6FA3"), -- lib:221
	StickerFxCyan = Color3.fromHex("#5FE0E8"), -- lib:221
	StickerFxGreen = Color3.fromHex("#8DF27A"), -- lib:221; the purchase ring (H:868)
	StickerFxPurple = Color3.fromHex("#B98CFF"), -- lib:221
	StickerFxIce = Color3.fromHex("#9EF7FF"), -- H:815: the box wobble's sparks
	StickerPinkSoft = Color3.fromHex("#FF9CC2"), -- H:774: the match found / level-up / squeeze sparks (H:139's dots)
	StickerGripFloat = Color3.fromHex("#9EF7D2"), -- H:704: the "+N Grip" float
	StickerCoinFlash = Color3.fromHex("#FFF3A0"), -- H:577: the coin landing's sparks and flash
	StickerSpendFloat = Color3.fromHex("#FF7A8A"), -- H:673: the "-N" spend float
	StickerPriceShort = Color3.fromHex("#FFB3BE"), -- H:946: an "off" button's price (OPEN, H:278; our coin BUY)
	-- The Shop window (UI FINAL R6): the featured card, the coin pack cards, the congrats radial (its alphas in
	-- Config.UI.Shop.congrats) and the confirm medallion's centre.
	StickerFeaturedTop = Color3.fromHex("#FFE58A"), -- H:295: the featured card (0%)
	StickerFeaturedMid = Color3.fromHex("#F5A623"), -- H:295 (45%)
	StickerFeaturedEnd = Color3.fromHex("#7B4FE0"), -- H:295 (100%)
	StickerPackTop = Color3.fromHex("#FFF3C4"), -- H:332: a coin pack card
	StickerPackEnd = Color3.fromHex("#FFD86B"), -- H:332
	StickerCongratsTop = Color3.fromHex("#FFD65A"), -- H:537: the congrats radial (0%)
	StickerCongratsMid = Color3.fromHex("#F58C1E"), -- H:537 (35%)
	StickerCongratsEnd = Color3.fromHex("#7828A0"), -- H:537 (100%)
	StickerMedallionTop = Color3.fromHex("#FFF6C8"), -- H:458: the confirm medallion's centre (to StickerGoldMid)
	-- The lobby HUD (UI FINAL R4; `N:n` = Diego's newer "Squishy Duels TDMFFA animations and hud/Squishy Duels
	-- HUD.dc.html" line n, its DUEL mode picker).
	StickerDuelSubDrop = Color3.fromHex("#780A32"), -- H:131: "Join the queue"'s soft drop (at .55)
	StickerCreamYellow = Color3.fromHex("#FFF3A6"), -- H:149: MATCH FOUND's top stop
	StickerFoundText = Color3.fromHex("#5A3200"), -- H:151: "Opponent: {name}" on MATCH FOUND
	StickerSlotMintTop = Color3.fromHex("#A8F6D8"), -- H:983: your queue slot (with StickerGripEnd)
	StickerSlotPinkTop = Color3.fromHex("#FFB3CB"), -- H:983: the opponent's queue slot
	StickerSlotPinkEnd = Color3.fromHex("#F2557F"), -- H:983
	StickerTrackerStatus = Color3.fromHex("#B9AEDA"), -- H:995: the tracker's "+N coins"; N:1256: an off mode tab
	StickerCoinGlowIn = Color3.fromHex("#FFF6AA"), -- H:76: the coin landing's glow (the radial's fallback)
	StickerCoinGlowMid = Color3.fromHex("#FFD63C"), -- H:76
	StickerCoinRays = Color3.fromHex("#FFF08C"), -- H:77: the coin landing's rays (the rays picture's tint)
	StickerShadowCta = Color3.fromHex("#3C1432"), -- H:126: the DUEL button's soft shadow (at .25)
	StickerPickerWell = Color3.fromHex("#2A1D45"), -- N:154: the mode picker's well
	StickerTdmRedTop = Color3.fromHex("#FF8597"), -- N:710: the TEAM DEATHMATCH tab (100deg, 4 stops)
	StickerTdmRed = Color3.fromHex("#FF6B81"), -- N:710 (32%)
	StickerTdmBlue = Color3.fromHex("#5DB4FF"), -- N:710 (68%)
	StickerTdmBlueEnd = Color3.fromHex("#7CC6FF"), -- N:710
	-- The window frame (UI FINAL R3): the header bands' end stops (their top stops StickerPinkTop H:183 and
	-- StickerMintTop H:353 are already here), the scrim, the sticker's drop shadow and the window's soft shadow.
	StickerHeaderPinkEnd = Color3.fromHex("#FF4F8E"), -- H:183: the Squishies band (and Inspect's, a reading)
	StickerHeaderCyanTop = Color3.fromHex("#8FF1F8"), -- H:258: the Boxes band
	StickerHeaderCyanEnd = Color3.fromHex("#1FB2D2"), -- H:258
	StickerHeaderGoldTop = Color3.fromHex("#FFE97A"), -- H:291: the Shop band (gold, Q9)
	StickerHeaderGoldEnd = Color3.fromHex("#FFA41C"), -- H:291
	StickerHeaderMintEnd = Color3.fromHex("#22B383"), -- H:353: the Quests band
	StickerHeaderPurpleTop = Color3.fromHex("#CDB2FF"), -- H:385: the Daily Rewards band
	StickerHeaderPurpleEnd = Color3.fromHex("#8052EE"), -- H:385
	StickerHeaderLilacTop = Color3.fromHex("#C9B6FF"), -- H:428: the Settings band
	StickerHeaderLilacEnd = Color3.fromHex("#8B63FF"), -- H:428
	StickerScrimPink = Color3.fromHex("#FF96D2"), -- H:178: the scrim's lighter centre (at .28)
	StickerStickerShadow = Color3.fromHex("#140A1E"), -- H:251: the window sticker's drop shadow (at .35)
	StickerShadowWindow = Color3.fromHex("#0F0819"), -- H:182: the window's soft shadow (at .5)
	-- UI FINAL R8 (the Daily and Quests windows): the streak pill (H:390), a claimed day card and its name (H:965-966)
	-- and the day 7 card's end stop (H:406; its 0% and 50% stops are StickerFeaturedTop and StickerFeaturedMid).
	StickerStreakTop = Color3.fromHex("#FFB25C"), -- H:390
	StickerStreakEnd = Color3.fromHex("#FF4F6E"), -- H:390
	StickerDayClaimedTop = Color3.fromHex("#D8CCF5"), -- H:965: a claimed day card
	StickerDayClaimedEnd = Color3.fromHex("#BBA9EA"), -- H:965
	StickerDayClaimedText = Color3.fromHex("#5B3FB0"), -- H:966: a claimed day's name
	StickerDay7End = Color3.fromHex("#9363F0"), -- H:406: the day 7 card (100%)
	-- UI FINAL R5 (the Squishies window): the All tab's top stop when on (H:928, with StickerHeaderPinkEnd).
	StickerTabAllTop = Color3.fromHex("#FF9CC4"),
	-- UI FINAL R9 (toasts, the quest pop and the level-up show): the mint toast and quest pop (H:162, H:846), the pop's
	-- tag (H:162), the teleport toast's end stop (H:779; its top is StickerPinkSoft), the level-up scrim (H:508), the
	-- number's top stop (H:519), the flash disc's 60% stop (H:514) and the ribbon (H:526).
	StickerToastMintTop = Color3.fromHex("#6FE8BC"), -- H:162, H:846
	StickerToastMintEnd = Color3.fromHex("#20A574"), -- H:162, H:846
	StickerQuestPopText = Color3.fromHex("#E6FFF4"), -- H:162: "QUEST COMPLETE"
	StickerToastPinkEnd = Color3.fromHex("#F2468A"), -- H:779
	StickerLevelScrimIn = Color3.fromHex("#FFF4D2"), -- H:508: rgba(255,244,210,.5) at 0%
	StickerLevelScrimOut = Color3.fromHex("#2E1256"), -- H:508: rgba(46,18,86,.6) at 72%
	StickerLevelGradTop = Color3.fromHex("#FFFBD0"), -- H:519: the number's 0% stop
	StickerFlashGlow = Color3.fromHex("#FFEC8C"), -- H:514: rgba(255,236,140,.8) at 60%
	StickerRibbonFace = Color3.fromHex("#FF5C9A"), -- H:526: the band
	StickerRibbonTail = Color3.fromHex("#C2306A"), -- H:526: the tails (the picture only)

	-- Match HUD M6 / M7 (2026-10-17; M = "Squishy Duels Match HUD.dc.html"): the players' colours (M:389-395: TDM
	-- Strawberry / Blueberry, the name and the 180deg head / pill stops around StickerTdmRed / StickerTdmBlue; FFA's six,
	-- top -> hex, three of them already here: StickerFxPink, StickerGoldMid over StickerCreamYellow), the kill feed row
	-- (M:122 rgba(36,24,58,.9)), its border when you were squished (M:656), TRIPLE! (M:525), the card's @handle and
	-- captions (M:180, M:184) and the vignette's stops (M:61, its picture's fallback).
	MatchTeamRedTop = Color3.fromHex("#FFB8C3"), -- M:389
	MatchTeamRedEnd = Color3.fromHex("#E84A64"),
	MatchTeamRedText = Color3.fromHex("#FF94A5"),
	MatchTeamBlueTop = Color3.fromHex("#B8E4FF"), -- M:390
	MatchTeamBlueEnd = Color3.fromHex("#3B93EE"),
	MatchTeamBlueText = Color3.fromHex("#8FCBFF"),
	MatchFfaPinkTop = Color3.fromHex("#FFC6DC"), -- M:392
	MatchFfaCyan = Color3.fromHex("#36C2DA"),
	MatchFfaCyanTop = Color3.fromHex("#B8F5FA"),
	MatchFfaMint = Color3.fromHex("#3FCC95"), -- M:393
	MatchFfaMintTop = Color3.fromHex("#C2F7E0"),
	MatchFfaPurple = Color3.fromHex("#A07BF5"), -- M:394
	MatchFfaPurpleTop = Color3.fromHex("#E4D4FF"),
	MatchFfaOrange = Color3.fromHex("#FF9A4D"),
	MatchFfaOrangeTop = Color3.fromHex("#FFD6B3"),
	MatchFeedRow = Color3.fromHex("#24183A"), -- M:122 (at .9)
	MatchFeedYouDown = Color3.fromHex("#FF5A6E"), -- M:656: your row when you were squished (and its .3 glow)
	MatchTripleTop = Color3.fromHex("#E4B8FF"), -- M:525
	MatchTripleEnd = Color3.fromHex("#9A63E8"),
	MatchCardHandle = Color3.fromHex("#E9E1FF"), -- M:180, M:184
	MatchVignetteMid = Color3.fromHex("#8C286E"), -- M:61: rgba(140,40,110,.35) at 75%
	MatchVignetteEdge = Color3.fromHex("#2E0E3A"), -- M:61: rgba(46,14,58,.72) at 100%

	-- Pens3 phase 1: the base pen (lobby design v6, `K:n` = kit.json line n, approved by the owner). World only
	-- (BaseService draws the fence and the sign; PenController the coin labels and the own sign's state).
	PenFenceWaferPost = Color3.fromHex("#E0A062"), -- K:4170-4189 tier 1 Wafer: post
	PenFenceWaferRail = Color3.fromHex("#FFF6EC"), -- rail and pickets
	PenFenceMintPost = Color3.fromHex("#FFF6EC"), -- tier 2 Mint
	PenFenceMintRail = Color3.fromHex("#8EEAD0"),
	PenFenceRoyalPost = Color3.fromHex("#FFC23C"), -- tier 3 Royal
	PenFenceRoyalRail = Color3.fromHex("#FF8FBF"),
	PenSignCanBuy = Color3.fromHex("#8EEAD0"), -- K:4239-4265 the sign's state trim: can buy (K:129 StateTint's default)
	PenSignTooExpensive = Color3.fromHex("#CFC8DA"), -- too expensive
	PenSignMax = Color3.fromHex("#FFC23C"), -- MAX
	PenSignPost = Color3.fromHex("#E0A062"), -- K:25 the material Wafer (the sign's post)
	PenSignFace = Color3.fromHex("#FFFDF6"), -- K:86 the material SignFace (the price face)
	PenSignText = Color3.fromHex("#1E1428"), -- K:92 the material Ink (the face's text)
	PenLabelText = Color3.fromHex("#FFFFFF"), -- K:4266-4270 the "+N/s" coin label: white text
	PenLabelStroke = Color3.fromHex("#1E1428"), -- its stroke

	-- Kill banners (2026-10-16, VillasmilGaming: Valorant-style kill banners; Art/KillStyle): the custom sets' own
	-- colours, from each squishy's look (Catalog accents). The Candy Pop set uses Cream, Lemon and Strawberry.
	KillBirdBlue = Color3.fromHex("#7CC0F5"), -- Birdie's accent: the Feather Storm ring and feathers
	KillBirdSky = Color3.fromHex("#DDF0FF"), -- the Feather Storm disc
	KillDonutCream = Color3.fromHex("#FFF0F4"), -- the Sprinkle Blast disc
	KillDonutDough = Color3.fromHex("#F6C27A"), -- the Sprinkle Blast mini donuts' dough
	KillCloudLilac = Color3.fromHex("#D5C8F6"), -- Cloud Bunny's accent: the Cloudburst glow
	KillCloudMist = Color3.fromHex("#F3EFFF"), -- the Cloudburst disc
	KillAxolotlPink = Color3.fromHex("#F9AFCB"), -- Cupcake Axolotl's accent: the Bubble Burst ring and gills
	KillAxolotlAqua = Color3.fromHex("#9FE3E0"), -- the Bubble Burst bubbles and glow
	KillAxolotlPearl = Color3.fromHex("#FFF4F8"), -- the Bubble Burst disc
	KillDragonTeal = Color3.fromHex("#3FB8AF"), -- the Dragon's accent: the Dragon's Blaze ring and wings
	KillDragonNight = Color3.fromHex("#2B2440"), -- the Dragon's Blaze disc
	KillDragonFire = Color3.fromHex("#FF9A3C"), -- the Dragon's Blaze glow

	-- Reserved gameplay colours (§7.2): never decoration.
	CoinGold = Color3.fromHex("#FFC83D"),
	CoinRing = Color3.fromHex("#D99A1E"),
	CoinHighlight = Color3.fromHex("#FFE08A"),
	Danger = Color3.fromHex("#FF5A4E"), -- Dragon Rush lane and error states only

	-- Names of the reserved gameplay colours above.
	RESERVED = table.freeze({ "CoinGold", "CoinRing", "CoinHighlight", "Danger" }),
}

return table.freeze(Palette)
