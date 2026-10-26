--!strict
-- Config/GearShop: the GEAR tab's and the TRAP! pop's numbers (gear step 3, 2026-10-26; owner "Yes, build step 3 like
-- that"). Shared, data only. [P] stand-ins until Diego draws the GEAR tab: the tabs are his picker well
-- (UI/Components/SegmentedTabs), the gear cards his pass cards (Config.UI.Shop.rows). A child module required directly
-- by ShopController and HighwayThrowController: Config/UI.luau is at 199.8k of Roblox's 200,000-character Source limit.

local GearShop = {
	-- The two tabs in the shop's gold band (ShopController): each picked face's gradient, Palette tokens top -> bottom.
	tabs = {
		shop = { top = "StickerPinkTop", bottom = "StickerPinkEnd" },
		gear = { top = "StickerGoldTop", bottom = "StickerGoldEnd" },
		rotation = 90,
	},
	-- A gear card: the pass card's look (Config.UI.Shop.rows) a little taller, its text stacked over its price chip
	-- (the long gear names need the room: "Starbeam Trebuchet ★7"), the chip chipGap under the line.
	card = { height = 140, chipGap = 6 },
	-- A gear card's tile: the tier number (a Sticker text role) over the stars bought (dots `pipPx`, a tier of 8 steps
	-- the smaller ones, `pipGap` apart, `pipBottom` up from the tile's bottom), the zone colour darkened by `endShade`
	-- towards ink at the bottom.
	tile = { numberRole = "packAmount", pipPx = 9, pipPxSmall = 6, pipGap = 2, pipBottom = 10, endShade = 0.25 },
	-- The page's power line under the cards (a Sticker text role).
	powerRole = "confirmDesc",
	-- TRAP! (HighwayThrowController): the pop's colour (a Palette token), its sound (an AssetTable key; the uploaded
	-- splat), and a short camera jolt (studs up and down, seconds; none under ReducedMotion: no camera shots then).
	trap = { color = "CandyLavender", sound = "match.splat", joltStuds = 0.6, joltSeconds = 0.3, joltHz = 18 },
}

return GearShop
