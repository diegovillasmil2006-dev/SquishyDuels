--!strict
-- Config/MatchLooks (big job item 7, 2026-11-10; the owner's "Match looks: power-ups shown on the player, teammate and
-- enemy colours, spawn protection, bot looks"; Diego drew none of it, so these are Claude's, in the game's own look).
-- Required directly (Config/init is near Roblox's 200,000-character limit). What Client/Controllers/
-- MatchLooksController draws on the OTHER fighters of a Team or Free for All match, and what the server's bots wear.
-- LihFolk vault: "Auras, Shields and Status Effects" (a few particles on an Attachment, a ForceField shell for a
-- shield, nothing welded to the body, one or two layers per state), "Nametags and Overhead Bars" (teammates' tags show
-- through walls, enemies' never), "Colour-Blind Safe Design" (a team colour always has a second sign: the heart on a
-- teammate's tag), "HumanoidDescription and Outfit Systems" (a few template looks, cloned).
-- A colour here is an Art/Palette token (never a "...Key" field: Config.validate reads those as Strings paths).

local MatchLooks = {
	enabled = true, -- false: no tags, rings, power-up signs or bubbles (the match plays as before)
	-- Diego's team colours of the match HUD (M:389-390), in Config.Match.teamNames' order (Strawberry, Blueberry).
	teams = { "MatchTeamRedEnd", "MatchTeamBlueEnd" },
	foe = "MatchTeamRedEnd", -- Free for All: everyone else is an enemy
	-- The name tag over a fighter's head: a chip in the team colour; a teammate's has a heart and shows through walls.
	Tag = {
		enabled = true,
		heightPx = 24,
		headOffsetStuds = 2.4, -- above the Head's centre (the ult READY badge of duels sits at 2.6)
		rootToHeadStuds = 2, -- a rig without a Head: this much higher above the root
		maxDistance = 120, -- an enemy's tag (and only in sight: walls hide it)
		mateMaxDistance = 400, -- a teammate's tag
		heartPx = 16,
	},
	-- The ring on the floor under a fighter (the candy kit's ring picture, tinted in the team colour).
	Ring = {
		enabled = true,
		diameterStuds = 6,
		belowRootStuds = 2.85, -- an R15 root's centre is about 3 studs over the soles
		transparency = 0.1,
	},
	-- A live power-up: its HUD icon in a bubble over the head (Diego's pod pictures and colours, UI/PodFormat.look)
	-- and a few sparkles in that colour round the body.
	Power = {
		enabled = true,
		iconPx = 30,
		gapPx = 4, -- the bubble sits this far over the name tag, at any distance (BillboardGui.SizeOffset)
		maxDistance = 160,
		sparkleRate = 8, -- per second (the vault: 3 to 8 for a lasting layer)
		sparkleLifetime = NumberRange.new(0.6, 0.9),
		sparkleSpeed = NumberRange.new(5, 8), -- they pop out of the body, then the drag stops them round it
		sparkleDrag = 3,
		sparkleSizeStuds = 0.55, -- 0.9 read as a logo on the shirt (seen 2026-11-10)
	},
	-- The shield power-up: a see-through shell round the fighter (Material ForceField), in the shield's colour.
	Shield = {
		diameterStuds = 8.5,
		growSeconds = 0.22, -- the vault's grow-in
		transparency = 0.25,
	},
	-- Spawn protection (Config.Match.spawnProtectSeconds): a pale shell that blinks until hits count again.
	Protect = {
		enabled = true,
		color = "Cream",
		diameterStuds = 7.5,
		blinkHz = 4,
		transparencyMin = 0.15,
		transparencyMax = 0.75,
	},
	refreshSeconds = 0.2, -- how often the fighters, their characters and the timers are looked at again
	-- What the bots wear (BotService.buildRigAsync): free avatar items made by Roblox, each checked on 2026-11-10
	-- (MarketplaceService:GetProductInfo: creator "Roblox", on sale, price 0). A match's bots are clones of
	-- `templates` different looks; each clone gets its own skin tone.
	Bots = {
		enabled = true, -- false: the plain character with no look (all black), as before
		templates = 6,
		hatChance = 0.3,
		skins = {
			Color3.fromRGB(255, 219, 172),
			Color3.fromRGB(241, 194, 125),
			Color3.fromRGB(224, 172, 105),
			Color3.fromRGB(198, 134, 66),
			Color3.fromRGB(141, 85, 36),
			Color3.fromRGB(105, 64, 40),
		},
		shirts = { 144076358, 398633584, 4047884046, 4047886060, 144076436, 607785314, 398635081, 398634295 },
		pants = { 144076760, 398633812, 382537569, 398635338, 398634487 },
		hair = { 63690008, 62234425, 376524487, 451220849, 451221329 },
		hats = { 48474313, 607702162 },
	},
}

return MatchLooks
