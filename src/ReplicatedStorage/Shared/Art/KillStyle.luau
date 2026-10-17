--!strict
-- KillStyle: the kill sets (2026-10-16, VillasmilGaming: Valorant-style kill banners, kill sounds and kill effects).
-- Shared, data only. A squishy's kill set is its Catalog eliminationEffectId: every Common and Uncommon squishy shares
-- "standard" (Candy Pop); each squishy above Uncommon (Epic, Exclusive) has its own set, built around that squishy.
--
-- A set names (colours are Art/Palette tokens, pictures AssetTable image keys):
--   nameKey          Strings key of its name (elimination.<id>, shown in Inspect)
--   squishyId        the squishy the set belongs to (nil: standard, every Common and Uncommon squishy)
--   emblem           v2 (2026-10-17): the banner's emblem, a low-fidelity sticker of the squishy (flat cel colours, ink
--                    outline; standard: a squished jelly blob with the game's squish face) — `emblemWhite` is its white
--                    silhouette (the slam's flash and the ink shadow, tinted)
--   disc, ring, glow the emblem's backing colours: `ring` the shock rings and slashes, `glow` the glow and rays
--   shards           the impact shards' colours (Palette tokens, used in turn)
--   frame            the outer frame ring (spins `spin` degrees/s; tinted, at `size` × the disc)
--   crownFrame       the extra ring of the 6k banner
--   ornament         one per K.O. (1k-5k) around the top of the medallion: a picture (`image`, `tint` or its own
--                    colours, `outline` = an ink copy behind it, a sticker edge) or a piece drawn from UI shapes (`donut`
--                    a mini glazed donut, `bubble` a cartoon bubble); `size` × the disc; `turn` degrees added to the
--                    slot's outward angle (the feather picture points right, so it turns -90 to point out)
--   crown            the 6k pieces: `count` per side, fanned `fan` degrees apart, at ±Config.UI.KillBanner.crownAngle
--   bannerVfx        SD_KillVfx Banner/<id> (the burst behind the banner)
--   killVfx          SD_KillVfx Kill/<id> (the kill effect where the K.O.'d squishy vanishes)
--   sound            the AssetTable sound sheet (6 kill sounds, Config.Audio.killBanner)
-- No gore (DESIGN brief): candy, glaze, feathers, clouds, bubbles and cartoon fire.
--
-- API:
--   KillStyle.STANDARD             "standard"
--   KillStyle.IDS                  every set id, standard first (frozen)
--   KillStyle.get(id)              -> Style? (nil for an unknown id)
--   KillStyle.resolve(effectId)    -> string: the id when it is a set, else "standard" ("epic_pending" too)

-- Types

export type Picture = {
	image: string?, -- AssetTable image key (nil with donut or bubble)
	donut: boolean?, -- a mini donut drawn from UI shapes instead of a picture
	bubble: boolean?, -- a cartoon bubble drawn from UI shapes instead of a picture
	tint: string?, -- Palette token; nil = the picture's own colours
	outline: boolean?, -- an ink copy behind it (a sticker edge)
	size: number, -- × the disc diameter
	turn: number?, -- degrees added to the outward angle (the picture's own "up")
	count: number?, -- crown pieces per side (default 1)
	fan: number?, -- degrees between crown pieces of one side
}

export type Ring = {
	image: string, -- AssetTable image key
	tint: string, -- Palette token
	size: number, -- × the disc diameter
	spin: number, -- degrees per second
}

export type Style = {
	id: string,
	nameKey: string,
	squishyId: string?,
	emblem: string,
	emblemWhite: string,
	shards: { string },
	disc: string,
	ring: string,
	glow: string,
	frame: Ring,
	crownFrame: Ring,
	ornament: Picture,
	crown: Picture,
	bannerVfx: string,
	killVfx: string,
	sound: string,
}

-- Constants

local STANDARD = "standard"

local STYLES: { [string]: Style } = {
	-- Candy Pop: every Common and Uncommon squishy. A squished jelly blob emblem, the game's own stars.
	standard = {
		id = "standard",
		nameKey = "elimination.standard",
		emblem = "img.kill.emblem.standard",
		emblemWhite = "img.kill.emblem.standard.white",
		shards = { "Lemon", "Strawberry", "Mint", "White" },
		disc = "Cream",
		ring = "Lemon",
		glow = "Strawberry",
		frame = { image = "img.kill.frameArcs", tint = "White", size = 1.52, spin = 24 },
		crownFrame = { image = "img.kill.frameSpikes", tint = "Lemon", size = 1.8, spin = -14 },
		ornament = { image = "img.icon.star", size = 0.36 },
		crown = { image = "img.icon.star", size = 0.46, count = 1 },
		bannerVfx = "Banner/standard",
		killVfx = "Kill/standard",
		sound = "sfx.kill.standard",
	},
	-- Feather Storm (Birdie, Epic): white feathers; the 6k banner spreads two wings of three blue feathers.
	feather_storm = {
		id = "feather_storm",
		nameKey = "elimination.feather_storm",
		emblem = "img.kill.emblem.feather_storm",
		emblemWhite = "img.kill.emblem.feather_storm.white",
		shards = { "White", "KillBirdBlue", "Sky" },
		squishyId = "bird",
		disc = "KillBirdSky",
		ring = "KillBirdBlue",
		glow = "Sky",
		frame = { image = "img.kill.frameNotch", tint = "White", size = 1.55, spin = 20 },
		crownFrame = { image = "img.kill.frameTicks", tint = "KillBirdBlue", size = 1.78, spin = -12 },
		ornament = { image = "img.kill.feather", tint = "White", outline = true, size = 0.4, turn = -90 },
		crown = { image = "img.kill.feather", tint = "KillBirdBlue", outline = true, size = 0.5, turn = -90, count = 3, fan = 20 },
		bannerVfx = "Banner/feather_storm",
		killVfx = "Kill/feather_storm",
		sound = "sfx.kill.feather_storm",
	},
	-- Sprinkle Blast (Donut, Epic): mini glazed donuts; the 6k banner adds two big ones.
	sprinkle_blast = {
		id = "sprinkle_blast",
		nameKey = "elimination.sprinkle_blast",
		emblem = "img.kill.emblem.sprinkle_blast",
		emblemWhite = "img.kill.emblem.sprinkle_blast.white",
		shards = { "Lemon", "Mint", "Sky", "Strawberry", "White" },
		squishyId = "donut",
		disc = "KillDonutCream",
		ring = "Strawberry",
		glow = "Bubblegum",
		frame = { image = "img.kill.frameSegments", tint = "White", size = 1.52, spin = 26 },
		crownFrame = { image = "img.kill.softRing", tint = "Strawberry", size = 1.75, spin = 0 },
		ornament = { donut = true, size = 0.32 },
		crown = { donut = true, size = 0.44, count = 1 },
		bannerVfx = "Banner/sprinkle_blast",
		killVfx = "Kill/sprinkle_blast",
		sound = "sfx.kill.sprinkle_blast",
	},
	-- Cloudburst (Cloud Bunny, Epic): cartoon clouds; the 6k banner strikes two lightning bolts under sun rays.
	cloudburst = {
		id = "cloudburst",
		nameKey = "elimination.cloudburst",
		emblem = "img.kill.emblem.cloudburst",
		emblemWhite = "img.kill.emblem.cloudburst.white",
		shards = { "White", "Lavender", "Lemon" },
		squishyId = "cloud_bunny",
		disc = "KillCloudMist",
		ring = "Lavender",
		glow = "KillCloudLilac",
		frame = { image = "img.kill.frameOrnate", tint = "White", size = 1.55, spin = 14 },
		crownFrame = { image = "img.fx.rays", tint = "KillCloudLilac", size = 2.2, spin = 18 },
		ornament = { image = "img.kill.cloud", tint = "White", outline = true, size = 0.42 },
		crown = { image = "img.icon.bolt", size = 0.5, turn = 0, count = 1 },
		bannerVfx = "Banner/cloudburst",
		killVfx = "Kill/cloudburst",
		sound = "sfx.kill.cloudburst",
	},
	-- Bubble Burst (Cupcake Axolotl, Epic): bubbles; the 6k banner grows the axolotl's gills, three a side.
	bubble_burst = {
		id = "bubble_burst",
		nameKey = "elimination.bubble_burst",
		emblem = "img.kill.emblem.bubble_burst",
		emblemWhite = "img.kill.emblem.bubble_burst.white",
		shards = { "KillAxolotlAqua", "KillAxolotlPink", "White" },
		squishyId = "cupcake_axolotl",
		disc = "KillAxolotlPearl",
		ring = "KillAxolotlPink",
		glow = "KillAxolotlAqua",
		frame = { image = "img.kill.shockRing", tint = "KillAxolotlAqua", size = 1.5, spin = 0 },
		crownFrame = { image = "img.kill.frameSun", tint = "KillAxolotlPink", size = 1.95, spin = 10 },
		ornament = { bubble = true, size = 0.3 },
		crown = { image = "img.kill.feather", tint = "KillAxolotlPink", outline = true, size = 0.48, turn = -90, count = 3, fan = 22 },
		bannerVfx = "Banner/bubble_burst",
		killVfx = "Kill/bubble_burst",
		sound = "sfx.kill.bubble_burst",
	},
	-- Dragon's Blaze (Dragon, Exclusive): a night medallion in the dragon ring, the game's flames; the 6k banner
	-- spreads two teal tribal dragons under fire rays.
	dragon_blaze = {
		id = "dragon_blaze",
		nameKey = "elimination.dragon_blaze",
		emblem = "img.kill.emblem.dragon_blaze",
		emblemWhite = "img.kill.emblem.dragon_blaze.white",
		shards = { "KillDragonFire", "ArenaFireTip", "KillDragonTeal" },
		squishyId = "dragon",
		disc = "KillDragonNight",
		ring = "KillDragonTeal",
		glow = "KillDragonFire",
		frame = { image = "img.kill.frameDragon", tint = "KillDragonTeal", size = 1.72, spin = 8 },
		crownFrame = { image = "img.fx.rays", tint = "KillDragonFire", size = 2.35, spin = 26 },
		ornament = { image = "img.icon.flame", size = 0.38 },
		crown = { image = "img.kill.dragonWing", tint = "KillDragonTeal", outline = true, size = 0.62, turn = 0, count = 1 },
		bannerVfx = "Banner/dragon_blaze",
		killVfx = "Kill/dragon_blaze",
		sound = "sfx.kill.dragon_blaze",
	},
}

local IDS: { string } = { "standard", "feather_storm", "sprinkle_blast", "cloudburst", "bubble_burst", "dragon_blaze" }

for _, style in STYLES do
	table.freeze(style.frame)
	table.freeze(style.crownFrame)
	table.freeze(style.ornament)
	table.freeze(style.crown)
	table.freeze(style.shards)
	table.freeze(style)
end
table.freeze(STYLES)
table.freeze(IDS)

-- Module table

local KillStyle = {
	STANDARD = STANDARD,
	IDS = IDS,
}

function KillStyle.get(id: unknown): Style?
	if type(id) ~= "string" then
		return nil
	end
	return STYLES[id]
end

function KillStyle.resolve(effectId: unknown): string
	if type(effectId) == "string" and STYLES[effectId] ~= nil then
		return effectId
	end
	return STANDARD
end

return table.freeze(KillStyle)
