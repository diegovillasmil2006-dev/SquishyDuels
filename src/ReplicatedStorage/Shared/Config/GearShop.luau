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
		income = { top = "StickerMintTop", bottom = "StickerMintEnd" }, -- INCOME step 2
		restock = { top = "StickerGoldTop", bottom = "StickerGoldEnd" }, -- 2026-10-31 shop restock
		rotation = 90,
	},
	-- INCOME step 2: the INCOME cards' tile colours (Palette tokens; UI/IncomeFormat), SQUISHY COINS and ALL EARNINGS.
	-- 2026-11-01 (restyle part 2, owner "All 3 cards"): each card's picture (AssetTable keys, Diego's hud-icons: the
	-- coin, the coin stack, the Grip blob) on its tile, the level in a badge (`tile.badge`).
	income = {
		colors = { coins = "Lemon", all = "UIMint", grip = "StickerGripTop" }, -- grip: 2026-10-31 buy Grip
		icons = { coins = "img.coin", all = "img.pack.1000", grip = "img.icon.grip" },
	},
	-- 2026-10-31 shop restock: the RESTOCK cards' tile colours by deal (Palette tokens; UI/RestockFormat).
	restock = { colors = { golden = "StickerGoldTop", rainbow = "StickerBoxSweetTop", rare = "UIMint" } },
	-- A gear card: the pass card's look (Config.UI.Shop.rows) a little taller, its text stacked over its price chip
	-- (the long gear names need the room: "Starbeam Trebuchet ★7"), the chip chipGap under the line.
	card = { height = 140, chipGap = 6 },
	-- A gear card's tile: the tier number (a Sticker text role) over the stars bought (dots `pipPx`, a tier of 8 steps
	-- the smaller ones, `pipGap` apart, `pipBottom` up from the tile's bottom), the zone colour darkened by `endShade`
	-- towards ink at the bottom. A tile with a picture (INCOME) shows the tier in a small CountBadge (`badge`: its accent,
	-- base px its corner sits outside the tile's bottom right). Big job item 9 (2026-11-10): a gear card's tile shows
	-- the piece's own 3D model (ReplicatedStorage.SD_Gear, a still ViewportFrame) with the tier in that badge; `model`:
	-- the camera's turn and height round the model in degrees (UI/Components/StaticIcon.viewDirection), a little from
	-- the side and above so a flat launcher shows its shape, and `fill`: the share of the tile the model's bounds
	-- take (the vault's icon rule: fill computed from bounds, about 82%). No model in the place: the tier number as
	-- before.
	tile = {
		numberRole = "packAmount",
		pipPx = 9,
		pipPxSmall = 6,
		pipGap = 2,
		pipBottom = 10,
		endShade = 0.25,
		badge = { accent = "plum", out = 6 },
		model = { yaw = 35, pitch = 18, fill = 0.86 },
	},
	-- The page's power line under the cards (a Sticker text role).
	powerRole = "confirmDesc",
	-- TRAP! (HighwayThrowController): the pop's colour (a Palette token), its sound (an AssetTable key; the uploaded
	-- splat), and a short camera jolt (studs up and down, seconds; none under ReducedMotion: no camera shots then).
	trap = { color = "CandyLavender", sound = "match.splat", joltStuds = 0.6, joltSeconds = 0.3, joltHz = 18 },
	-- 2026-10-31 boosters: the BOOSTER! pop as a throw bounces off a booster (the boost pop's colour and sound). `sign`
	-- (owner 2026-11-06, like Hit a Golf Ball's floating words; Art/HighwayBoosters): the "x2" floating over each booster:
	-- Palette tokens, the outline's px, its size in studs, how far over the model's top, and from how far it shows.
	booster = {
		color = "CandyCyan",
		sound = "sfx.dashWhoosh",
		sign = {
			color = "CandyGold",
			stroke = "PlumInk",
			strokePx = 3,
			widthStuds = 14,
			heightStuds = 8,
			liftStuds = 1,
			maxDistance = 400,
		},
	},
}

return GearShop
