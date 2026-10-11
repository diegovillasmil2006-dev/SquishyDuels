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

	-- Reserved gameplay colours (§7.2): never decoration.
	CoinGold = Color3.fromHex("#FFC83D"),
	CoinRing = Color3.fromHex("#D99A1E"),
	CoinHighlight = Color3.fromHex("#FFE08A"),
	Danger = Color3.fromHex("#FF5A4E"), -- Dragon Rush lane and error states only

	-- Names of the reserved gameplay colours above.
	RESERVED = table.freeze({ "CoinGold", "CoinRing", "CoinHighlight", "Danger" }),
}

return table.freeze(Palette)
