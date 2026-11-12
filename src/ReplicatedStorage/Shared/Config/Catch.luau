--!strict
-- Config.Economy.Catch: the throw catches squishies (rework Option A, owner 2026-11-12 "Yes, build it"; the rules on the
-- vault page "Plan - Rework from top games 2026-11", step 1, the look on Claude's design canvas "Squishy Duels: catch
-- squishies on the highway"). Shared, data only; Shared/CatchMath does the math and checks these (CatchMath.validate,
-- run by HighwayService at init: a problem stops with an error).
-- * zoneBoxes: the box each highway zone's wild squishies come from (zones 1-7, then 8 = the Golden Gates), with that
--   box's own weights (the odds board's table: one table for both).
-- * A throw's chance = share x its Coins / the box's price, at least minChance and at most maxChance, and never so much
--   that the catch's expected sell value beats the throw's own Coins (step 3's money check: a new player's 1,065-Coin
--   throw against a Soft Box catch worth about 36,900 to sell; that cap only holds for the first catches, until the pen
--   earns about 35 a second).
-- * pity: a sure catch after pity / chance throws without one (the CATCH meter). A new player's first throw and the
--   first landing in a new zone always catch (they replace the zone gifts of 2026-10-18).
-- * wild: the wild squishies the client stands around a throw's landing spot (decoration only: the server decides the
--   catch): how many, how much bigger than the pen copies they are drawn, where beside the lane (lane-local studs),
--   how close they run to the landing, and how long they stay.
-- * ui: the CATCH meter and the catch card (UI tokens here: Config/UI is over the go-back tool's 200,000-character
--   limit, audit row 8). Base px like every Config.UI size; motion in milliseconds.

local Catch = {
	zoneBoxes = { "snack", "snack", "sweet", "frosty", "lava", "prism", "halo", "halo" },
	share = 0.25,
	minChance = 1 / 20,
	maxChance = 1 / 4,
	pity = 2,

	-- The landing shot holds holdSeconds (instead of Config.UI.Highway.landingShot.holdSeconds) when the throw caught,
	-- so the run, the hop and the bubble are seen: "!" at alertSeconds, the run over runSeconds, then the hop.
	wild = {
		count = 7,
		scale = 5,
		sideMin = 8,
		sideMax = 22,
		behind = 14,
		ahead = 30,
		runTo = 7, -- studs from the landing where a running wild one stops
		alertSeconds = 0.2,
		runSeconds = 0.6,
		hopStuds = 5, -- (9 put the bubble behind the flight lines at the top of a phone's screen)
		hopSeconds = 0.35,
		holdSeconds = 2.8,
		staySeconds = 6,
		alertPx = 34,
		alertHoldSeconds = 1.2, -- the "!" shows this long (Catch: gone by the hop)
		bobShare = 0.25, -- a running one bobs up to this share of its height
	},
	-- The catch shot (the canvas's Landing / Catch pictures were taken from here): a landing that caught leaves the close
	-- landing shot for a wider one, lane-local from the squishy: `side` right of, `up` above and `back` behind it,
	-- looking `ahead` past it, `lookUp` above it, so the wild ones and the bubble are in view.
	shot = { side = 12, up = 13, back = 22, ahead = 12, lookUp = 2 },
	-- The catch's sounds (AssetTable keys; no new sounds): the "!", the hop into the bubble, a Rare-or-better catch, the
	-- bubble reaching the Squishies button.
	sounds = { alert = "ui.pop", catch = "sfx.catch", rare = "sfx.inspect.sparkle", home = "ui.coin" },

	-- Base px = the canvas's 844x390 phone px / 0.85 (a phone's UI scale); text kinds are Config.UI.TextSize's.
	ui = {
		meter = {
			width = 258,
			padX = 14,
			padTop = 9,
			padBottom = 12,
			gap = 7,
			barHeight = 16,
			barBorder = 2,
			starPx = 28,
			top = 122,
			right = 18,
			radius = 19,
			border = 3,
			lip = 5,
			titleKind = "Button",
			hereKind = "D17",
		},
		-- NewZone: "Your first catch here is sure!" under the meter, pulsing (UiIdle's pulse, once every pulseS).
		chip = {
			height = 40,
			padX = 10,
			gap = 7,
			starPx = 26,
			below = 10,
			border = 3,
			kind = "D19",
			pulseS = 1.4,
		},
		card = {
			width = 334,
			height = 144,
			pad = 12,
			gap = 14,
			rowGap = 5,
			picPx = 104,
			picBorder = 3,
			picRadius = 21,
			radius = 26,
			border = 4,
			lip = 6,
			ring = 5, -- Rare and up: the rarity ring outside the ink border, and its glow (glowPx bigger)
			glowPx = 52,
			pillHeight = 26,
			pillPadX = 9,
			pipPx = 8,
			barHeight = 9,
			badgeHeight = 30,
			badgePadX = 12,
			badgeTurn = 8,
			starPx = { 30, 26 }, -- Epic and up: the two twinkling stars
			raysPx = 420, -- Legendary: the turning rays behind the card
			raysAlpha = 0.42,
			raysPeriodS = 14,
			slidePx = 70,
			titleKind = "HudNumber",
			nameKind = "Button",
			nameKindLong = "Small", -- a name too wide for nameKind
			pillKind = "Small",
			zoneKind = "Small",
			badgeKind = "Chip",
			holdMs = 2600,
			inMs = 350,
			outMs = 250,
		},
		-- Home: the bubble flies from (fromX, fromY) of the screen to the Squishies button, then "+1" beside it.
		fly = { px = 72, ms = 700, arc = 0.35, fromX = 0.52, fromY = 0.3, plusMs = 900, plusKind = "Found", halo = 3 },
		bubble = { scale = 1.6, transparency = 0.55 },
		beam = { height = 40, width = 6, transparency = 0.45 },
	},
}

return Catch
