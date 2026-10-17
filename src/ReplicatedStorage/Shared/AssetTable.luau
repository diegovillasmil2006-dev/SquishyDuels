--!strict
-- Every asset id slot the game can use: sounds, animation clips and images (shared: server and client).
-- DESIGN §14. Every id starts as nil (PENDING). A nil id means the feature is disabled: silent audio, procedural
-- animation, icons built from UI shapes. Callers warn once per missing key (SoundController does it at startup).
--
-- An id is added here only after the §14.1 pipeline and the user's approval (Part 8, manual step M8), together
-- with `source`, `license` and `verifiedAt`. Never invent an id. This is the only file allowed to hold asset ids
-- (tools/check.ps1). Built-in engine files (rbxasset://textures/particles/*, built-in fonts) are not slots and do
-- not live here (§14.3).
--
-- Feel pass (§18.6, §18.7): a sound slot can carry `variants` (extra approved ids, each with its own volume, so
-- SoundController never repeats the last pick) and `optional` (the Studio sound picker may skip it). Approved sounds
-- are written only through the picker flow (§18.7 steps 10-13) as soundSlot's `approved` argument.

export type AssetKind = "sound" | "animation" | "image"
export type SoundGroupName = "Music" | "SFX" | "UI" | "Ambient"

-- One extra approved id of a sound slot (§18.6).
export type SoundVariant = {
	id: number,
	volume: number,
	source: string,
	license: string,
	verifiedAt: string, -- "YYYY-MM-DD"
	notes: string?,
}

export type AssetSlot = {
	key: string,
	kind: AssetKind,
	id: number?, -- nil = PENDING / disabled
	group: SoundGroupName?, -- sounds only
	volume: number?, -- sounds only; per-asset level inside its SoundGroup
	spatial: boolean?, -- sounds only; true = 3D at the source, false = 2D
	source: string?, -- where the id came from (Creator Store asset, group upload, ...)
	license: string?, -- licence / permission evidence
	verifiedAt: string?, -- "YYYY-MM-DD" of the last successful check (PreloadAsync, TimeLength > 0)
	variants: { SoundVariant }?, -- sounds only; extra approved ids (nil while PENDING)
	optional: boolean?, -- sounds only; true = the sound picker may skip this key (§18.7)
	notes: string, -- target length, planned variants and the §14.2 search queries for the Part 8 shortlist
}

-- soundSlot's `approved` argument (§18.7 "Approved slot format"); nil = PENDING.
export type ApprovedSound = {
	id: number,
	volume: number,
	source: string,
	license: string,
	verifiedAt: string,
	variants: { SoundVariant }?,
}

-- One playable choice of a sound key (soundChoices): the slot's own id or one of its variants.
export type SoundChoice = {
	id: number,
	content: string, -- "rbxassetid://<id>"
	volume: number,
}

local CONTENT_PREFIX = "rbxassetid://"
local DEFAULT_VOLUME = 1
local MAX_EXACT_ID = 2 ^ 53 -- larger numbers are not exact integers

local AssetTable = {}

local function soundSlot(
	key: string,
	group: SoundGroupName,
	spatial: boolean,
	volume: number?,
	notes: string,
	approved: ApprovedSound?
): AssetSlot
	return {
		key = key,
		kind = "sound",
		id = if approved then approved.id else nil,
		group = group,
		volume = if approved then approved.volume else volume or DEFAULT_VOLUME, -- the approved volume wins
		spatial = spatial,
		source = if approved then approved.source else nil,
		license = if approved then approved.license else nil,
		verifiedAt = if approved then approved.verifiedAt else nil,
		variants = if approved then approved.variants else nil,
		optional = nil,
		notes = notes,
	}
end

-- Marks a sound slot the picker may skip (§18.6 "(optional)" keys).
local function optional(slot: AssetSlot): AssetSlot
	slot.optional = true
	return slot
end

local function otherSlot(key: string, kind: AssetKind, notes: string): AssetSlot
	return {
		key = key,
		kind = kind,
		id = nil,
		source = nil,
		license = nil,
		verifiedAt = nil,
		notes = notes,
	}
end

local ANIMATION_NOTE =
	"PENDING. v1 is procedural (§9.1). Needs a clip published by the DIJAY Studios group or granted to this experience (§14.1, M8)."
local IMAGE_NOTE = "PENDING. v1 builds this icon from UI shapes (§11.2)."

-- Sounds uploaded by the DIJAY Studios group on 2026-10-12: renders of the Claude Design files' own sound recipes
-- ("Squishy Duels sounds to upload", folders 1 and 4). Checked that day: group-owned audio, the uploaded name, and it
-- loads (PreloadAsync; TimeLength > 0 in Play). `file` is the uploaded file; the volume is the slot's planned one.
local UPLOAD_DATE = "2026-10-12"
local UPLOAD_LICENSE = "Group-owned upload; an original render of the design's own synth recipe (no third-party audio)"

local function upload(id: number, volume: number, file: string): SoundVariant
	return {
		id = id,
		volume = volume,
		source = `DIJAY Studios group upload: '{file}'`,
		license = UPLOAD_LICENSE,
		verifiedAt = UPLOAD_DATE,
	}
end

-- soundSlot's `approved` argument for an upload, with the slot's other uploads as variants.
local function uploaded(id: number, volume: number, file: string, variants: { SoundVariant }?): ApprovedSound
	local main = upload(id, volume, file)
	return {
		id = main.id,
		volume = main.volume,
		source = main.source,
		license = main.license,
		verifiedAt = main.verifiedAt,
		variants = variants,
	}
end

-- Free Creator Store sounds from Roblox's licensed Pro Sound Effects library (2026-10-15 dash + double jump overhaul,
-- VillasmilGaming; no ElevenLabs key on that PC): each loads in this place (ContentProvider:PreloadAsync Success that
-- day). `name` is the Creator Store title and take number.
local STORE_DATE = "2026-10-15"
local PSE_LICENSE =
	"Free Creator Store audio from Roblox's licensed Pro Sound Effects library ('Courtesy of Pro Sound Effects')"
local PSE_SEARCH = "Wood Swish Ruler Whoosh"

local function pse(id: number, volume: number, name: string): SoundVariant
	return {
		id = id,
		volume = volume,
		source = `Creator Store audio '{name}' by ProSoundEffects (search: "{PSE_SEARCH}")`,
		license = PSE_LICENSE,
		verifiedAt = STORE_DATE,
	}
end

-- soundSlot's `approved` argument from Pro Sound Effects takes: the first is the slot's id, the rest its variants.
local function pseSlot(main: SoundVariant, variants: { SoundVariant }): ApprovedSound
	return {
		id = main.id,
		volume = main.volume,
		source = main.source,
		license = main.license,
		verifiedAt = main.verifiedAt,
		variants = variants,
	}
end

-- Kill banners (2026-10-16, VillasmilGaming: Valorant-style kill banners; v2 2026-10-17: punchier sheets, emblems). The
-- sound sheets are original synthesis (tools/audio/killsynth.py: no samples, no third-party audio), uploaded to the DIJAY
-- Studios group through Open Cloud; each sheet holds a kill set's 6 escalating kill sounds, one per
-- Config.Audio.killBanner slot. The emblems are low-fidelity stickers rendered from the game's own squishy models
-- (uploaded by VillasmilGaming, 2026-10-17; each loads in this place, PreloadAsync Success). The
-- textures are public Image assets from the VFX Studio plugin's texture library (the plugin lists them for use in
-- experiences); each loads in this place (ContentProvider:PreloadAsync Success, 2026-10-16).
local KILL_DATE = "2026-10-17" -- v2 sheets and the emblems (checked that day)
local KILL_SOUND_LICENSE = "Group-owned upload; original synthesis (KillSynth 2026-10-16), no third-party audio"
local VFX_STUDIO_LICENSE = "Public Image asset listed in the VFX Studio plugin's texture library (for use in experiences)"
local EMBLEM_LICENSE = "Own upload (VillasmilGaming); a render of the game's own squishy models (no third-party art)"

-- soundSlot's `approved` argument for a kill banner sheet.
local function killSheet(id: number, file: string): ApprovedSound
	return {
		id = id,
		volume = 1,
		source = `DIJAY Studios group upload (Open Cloud): '{file}'`,
		license = KILL_SOUND_LICENSE,
		verifiedAt = KILL_DATE,
	}
end

-- An image slot holding a kill banner emblem (`file` is the uploaded PNG).
local function killEmblem(key: string, id: number, file: string, use: string): AssetSlot
	return {
		key = key,
		kind = "image",
		id = id,
		source = `VillasmilGaming upload (Studio): '{file}'`,
		license = EMBLEM_LICENSE,
		verifiedAt = KILL_DATE,
		notes = use,
	}
end

-- An image slot holding a VFX Studio library texture: `name` is its Creator Store title, `by` its creator.
local function vfxStudio(key: string, id: number, name: string, by: string, use: string): AssetSlot
	return {
		key = key,
		kind = "image",
		id = id,
		source = `VFX Studio plugin texture library: '{name}' by {by}`,
		license = VFX_STUDIO_LICENSE,
		verifiedAt = KILL_DATE,
		notes = use,
	}
end

-- §14.2 sound slots and §14.3 animation and image slots, in document order.
local SLOTS: { AssetSlot } = {
	-- SFX (§14.2)
	soundSlot(
		"sfx.squish",
		"SFX",
		true,
		nil,
		"3 variants; 0.15–0.5 s; search: soft+squish, squishy+toy+squeeze, foam+squeeze, stress+ball+squeeze",
		uploaded(98509885377412, 1, "sfx.squish - slime foam.wav")
	),
	soundSlot(
		"sfx.squeezeRelease",
		"SFX",
		true,
		0.3,
		"0.3–0.8 s; search: soft+air+release, pillow+squeeze",
		uploaded(70674943007768, 0.3, "sfx.squeezeRelease - slime foam.wav")
	),
	soundSlot(
		"sfx.throw",
		"SFX",
		true,
		nil,
		"3 variants; 0.15–0.4 s; search: whoosh+short, swoosh+light, air+swipe+quick",
		uploaded(
			130791298643341,
			1,
			"sfx.throw - 1.wav",
			{ upload(73064080482534, 1, "sfx.throw - 2.wav"), upload(71090957780502, 1, "sfx.throw - 3.wav") }
		)
	),
	soundSlot(
		"sfx.throwDragon",
		"SFX",
		true,
		nil,
		"0.4–1.0 s; search: fireball+whoosh, magic+whoosh",
		uploaded(105977784205012, 1, "sfx.throwDragon.wav")
	),
	soundSlot(
		"sfx.dragonTelegraph",
		"SFX",
		true,
		nil,
		"0.5–0.9 s; search: power+up+short, magic+charge",
		uploaded(95223295252433, 1, "sfx.dragonTelegraph.wav")
	),
	soundSlot(
		"sfx.dragonChomp",
		"SFX",
		true,
		nil,
		"0.3–0.7 s; search: cartoon+chomp, cartoon+bite",
		uploaded(96159623101269, 1, "sfx.dragonChomp.wav")
	),
	optional(
		soundSlot(
			"sfx.dragonRoar",
			"SFX",
			false,
			nil,
			"optional; ≤ 1 s; search: cute+dragon+roar, cartoon+roar+short",
			uploaded(96598054928717, 1, "sfx.dragonRoar.wav")
		)
	),
	soundSlot(
		"sfx.impactBoing",
		"SFX",
		true,
		nil,
		"2 variants; 0.2–0.6 s; search: cartoon+boing, rubber+bounce",
		uploaded(88787826055581, 1, "sfx.impactBoing - 1.wav", { upload(85924413183882, 1, "sfx.impactBoing - 2.wav") })
	),
	soundSlot(
		"sfx.impactSoft",
		"SFX",
		true,
		nil,
		"≤ 0.4 s; search: soft+thud, pillow+hit",
		uploaded(77122339335915, 1, "sfx.impactSoft.wav")
	),
	soundSlot("sfx.elimination", "SFX", true, nil, "0.3–0.8 s; search: cartoon+poof, puff+cartoon"),
	-- Feel pass SFX (§18.6): optional, so the user can skip them in the picker.
	optional(
		soundSlot(
			"sfx.jellyWobble",
			"SFX",
			true,
			0.5,
			"optional; the jelly ripple on walls and cover; 0.2–0.6 s; search: jelly+wobble, jello+wobble, slime+wobble",
			uploaded(122673685371216, 0.5, "sfx.jellyWobble.wav")
		)
	),
	optional(
		soundSlot(
			"sfx.pop",
			"SFX",
			true,
			0.35,
			"optional; throw ready again, the big squeeze pop, ult READY; ≤ 0.3 s; search: bubble+pop+soft, cute+pop",
			uploaded(130729416962656, 0.35, "sfx.pop.wav")
		)
	),

	-- Moves (spec phase 5): the dash and the four Epic ultimates. Rendered from the design's own synth recipes
	-- (scratchpad sounds-out; spec sounds.md Tier 2), uploaded by the group (2026-10-12).
	soundSlot(
		"sfx.dash",
		"SFX",
		true,
		nil,
		"the dash push-off (frame 2); design fx.js:45 dash(), fp.js:516; 2 variants rendered (sfx_dash_1/2.wav, 0.2 s)",
		uploaded(
			121443444989259,
			1,
			"sfx.dash - 1 (dash push-off).wav",
			{ upload(102962858079541, 1, "sfx.dash - 2 (dash push-off).wav") }
		)
	),
	soundSlot(
		"sfx.dashPlant",
		"SFX",
		true,
		nil,
		"the dash plant (frame 7); design fx.js:47 land(false), fp.js:517; rendered sfx_dashPlant.wav (0.23 s)",
		uploaded(74110085743096, 1, "sfx.dashPlant (dash landing).wav")
	),
	-- The 2026-10-15 dash + double jump overhaul: an air rush over the dash's push-off, and the double jump's whoosh.
	soundSlot(
		"sfx.dashWhoosh",
		"SFX",
		true,
		nil,
		"the dash's air rush at the start, over sfx.dash; 3 takes of PSE 'Wood Swish Ruler Whoosh Fast Movement In Air' (0.6 s)",
		pseSlot(pse(9126283272, 0.7, "Wood Swish Ruler Whoosh Fast Movement In Air 13 (SFX)"), {
			pse(9126284094, 0.7, "Wood Swish Ruler Whoosh Fast Movement In Air 5 (SFX)"),
			pse(9126283906, 0.7, "Wood Swish Ruler Whoosh Fast Movement In Air 2 (SFX)"),
		})
	),
	soundSlot(
		"sfx.doubleJump",
		"SFX",
		true,
		nil,
		"the double jump's whoosh (sfx.dash pitched up plays under it); 3 takes of the same PSE swish set (0.6 s)",
		pseSlot(pse(9126284298, 0.8, "Wood Swish Ruler Whoosh Fast Movement In Air 10 (SFX)"), {
			pse(9126284292, 0.8, "Wood Swish Ruler Whoosh Fast Movement In Air 8 (SFX)"),
			pse(9126283052, 0.8, "Wood Swish Ruler Whoosh Fast Movement In Air 6 (SFX)"),
		})
	),
	soundSlot(
		"sfx.ultCharge.bird",
		"SFX",
		true,
		nil,
		"Flock Volley wind-up (0.35 s); design fp.js:463 sawtooth 120->420 Hz + sparkle(4); sfx_ultCharge_bird.wav",
		uploaded(126898491785878, 1, "sfx.ultCharge.bird (Birdie ult charge-up).wav")
	),
	soundSlot(
		"sfx.ultCharge.donut",
		"SFX",
		true,
		nil,
		"Sprinkle Roller wind-up (0.45 s); design fp.js:463 sawtooth 120->420 Hz + sparkle(4); sfx_ultCharge_donut.wav",
		uploaded(133399262015268, 1, "sfx.ultCharge.donut (Donut ult charge-up).wav")
	),
	soundSlot(
		"sfx.ultCharge.cloud_bunny",
		"SFX",
		true,
		nil,
		"Rain Check wind-up (0.6 s); design fp.js:463; rendered sfx_ultCharge_cloud_bunny.wav",
		uploaded(114287899394348, 1, "sfx.ultCharge.cloud_bunny (Cloud Bunny ult charge-up).wav")
	),
	soundSlot(
		"sfx.ultCharge.cupcake_axolotl",
		"SFX",
		true,
		nil,
		"Bubble Pop wind-up (0.5 s); design fp.js:463; rendered sfx_ultCharge_cupcake_axolotl.wav",
		uploaded(107592384694914, 1, "sfx.ultCharge.cupcake_axolotl (Axolotl ult charge-up).wav")
	),
	soundSlot(
		"sfx.ultRelease",
		"SFX",
		true,
		nil,
		"every Epic ultimate's release; design fx.js:39 whoosh(0.6), fp.js:334; rendered sfx_ultRelease.wav (0.55 s)",
		uploaded(76516567043577, 1, "sfx.ultRelease (any ult firing).wav")
	),
	soundSlot(
		"sfx.ultRainDrop",
		"SFX",
		true,
		nil,
		"a Rain Check drop lands; design fp.js:372 sine 900->400 Hz 0.08 s; rendered sfx_ultRainDrop.wav (0.15 s)",
		uploaded(96427113240334, 1, "sfx.ultRainDrop (Cloud Bunny rain drop).wav")
	),
	soundSlot(
		"sfx.ultCloudHover",
		"SFX",
		true,
		nil,
		"the Rain Check cloud parks; design fx.js:41 sparkle(4), fp.js:255; rendered sfx_ultCloudHover.wav (0.37 s)",
		uploaded(110207730124200, 1, "sfx.ultCloudHover (Cloud Bunny cloud sparkle).wav")
	),
	soundSlot(
		"sfx.ultBubblePop",
		"SFX",
		true,
		nil,
		"Bubble Pop pops; design fp.js:165 blub, fp.js:361; rendered sfx_ultBubblePop.wav (0.4 s)",
		uploaded(112777592157671, 1, "sfx.ultBubblePop (Axolotl bubble pop).wav")
	),

	-- The charge throw and the catch (feature 1, 2026-10-11; design: the combat-effects page "Squishy Combat FP
	-- v2.html" and its squishy-lib-v2.js sfx): renders of the design's own synth recipes, uploaded by the group
	-- (2026-10-12) under the file names below. The tone and the ping are the own player's (2D); the catch sounds play
	-- 2D for the catcher and 3D at the catcher's hands for the thrower.
	soundSlot(
		"sfx.chargeLoop",
		"SFX",
		false,
		nil,
		"the charge tone, looped (CatchController / ThrowController drive its pitch and volume, Config.Audio.charge); design squishy-lib-v2.js:378-386 triangle + sine (×1.505) through a 700-2500 Hz low-pass; a steady 1.6 s loop at 250 Hz (c 0.28: PlaybackSpeed 0.6..2 gives the design's 150..510 Hz); file 'sfx.charge - loop.wav'",
		uploaded(128173053853061, 1, "sfx.charge - loop.wav")
	),
	soundSlot(
		"sfx.chargeFull",
		"SFX",
		false,
		nil,
		"the full-charge ping (with the white ring); design html:514 sfx.squish(release, 0.6), squishy-lib-v2.js:367 (0.15 s); file 'sfx.charge - full ping.wav'",
		uploaded(100338916285631, 1, "sfx.charge - full ping.wav")
	),
	soundSlot(
		"sfx.catch",
		"SFX",
		true,
		nil,
		"a throw is caught; design html:351 sfx.catch, squishy-lib-v2.js:371 high-pass noise 1800->900 Hz + sine 220->120 Hz (0.14 s); file 'sfx.catch - catch.wav'",
		uploaded(81399122297370, 1, "sfx.catch - catch.wav")
	),
	soundSlot(
		"sfx.crushSqueak",
		"SFX",
		true,
		nil,
		"the caught toy squeaks as the crush starts (0.12 s in); design html:553 sfx.squish(press, 1), squishy-lib-v2.js:365 (0.22 s); file 'sfx.catch - crush squeak.wav'",
		uploaded(130785661015129, 1, "sfx.catch - crush squeak.wav")
	),
	soundSlot(
		"sfx.crushBurst",
		"SFX",
		true,
		nil,
		"the caught toy bursts; design html:560 sfx.explode, squishy-lib-v2.js:373-377 low-pass noise 4000->250 Hz + sine 130->38 Hz + chimes (0.7 s); file 'sfx.catch - burst.wav'",
		uploaded(93505364528833, 1, "sfx.catch - burst.wav")
	),

	-- The knead's wax crunch (spec phase2-squeeze §3.10): renders of the design's own generators (squish.js:676-709,
	-- 829-833, fx.js:41), 48 kHz mono, in the scratchpad's work/sounds-out (the sheets are also "wax crack sheet -
	-- <feel>.wav" in the upload folder's Extras). 2D; Controllers/KneadAudio plays them in the Wax group at the levels of
	-- Config.Audio.wax (volume 1 here). A sheet is played one region at a time (Sound.PlaybackRegion): 54 bursts, 48
	-- grains, 5 taps (layout: Config.Audio.wax).
	soundSlot(
		"sfx.wax.foam",
		"SFX",
		false,
		1,
		"upload wax_sheet_foam.wav (9.58 s): foam crack sheet, by region",
		uploaded(119201911341069, 1, "sfx.wax.foam (wax cracks, foam toys).wav")
	),
	soundSlot(
		"sfx.wax.mochi",
		"SFX",
		false,
		1,
		"upload wax_sheet_mochi.wav (9.58 s): mochi crack sheet, by region",
		uploaded(110221785652484, 1, "sfx.wax.mochi (wax cracks, Mochi Fox).wav")
	),
	soundSlot(
		"sfx.wax.jelly",
		"SFX",
		false,
		1,
		"upload wax_sheet_jelly.wav (9.58 s): jelly crack sheet, by region",
		uploaded(87951703256560, 1, "sfx.wax.jelly (wax cracks, jelly toys).wav")
	),
	soundSlot(
		"sfx.wax.plush",
		"SFX",
		false,
		1,
		"upload wax_sheet_plush.wav (9.58 s): plush crack sheet, by region",
		uploaded(86195380452013, 1, "sfx.wax.plush (wax cracks, plush toys).wav")
	),
	soundSlot(
		"sfx.wax.haze.foam",
		"SFX",
		false,
		1,
		"upload wax_haze_foam.wav (2 s loop): micro-crackle haze bed",
		uploaded(85634255328406, 1, "sfx.wax.haze.foam (crackle loop, foam).wav")
	),
	soundSlot(
		"sfx.wax.haze.mochi",
		"SFX",
		false,
		1,
		"upload wax_haze_mochi.wav (2 s loop): micro-crackle haze bed",
		uploaded(92809310760268, 1, "sfx.wax.haze.mochi (crackle loop, mochi).wav")
	),
	soundSlot(
		"sfx.wax.haze.jelly",
		"SFX",
		false,
		1,
		"upload wax_haze_jelly.wav (2 s loop): micro-crackle haze bed",
		uploaded(111957268767421, 1, "sfx.wax.haze.jelly (crackle loop, jelly).wav")
	),
	soundSlot(
		"sfx.wax.haze.plush",
		"SFX",
		false,
		1,
		"upload wax_haze_plush.wav (2 s loop): micro-crackle haze bed",
		uploaded(105059409714904, 1, "sfx.wax.haze.plush (crackle loop, plush).wav")
	),
	soundSlot(
		"sfx.wax.body.foam",
		"SFX",
		false,
		1,
		"upload wax_body_foam.wav (2 s loop): foam body bed",
		uploaded(119922284408942, 1, "sfx.wax.body.foam (squish loop, foam).wav")
	),
	soundSlot(
		"sfx.wax.body.mochi",
		"SFX",
		false,
		1,
		"upload wax_body_mochi.wav (2 s loop): foam body bed",
		uploaded(121427245253220, 1, "sfx.wax.body.mochi (squish loop, mochi).wav")
	),
	soundSlot(
		"sfx.wax.body.jelly",
		"SFX",
		false,
		1,
		"upload wax_body_jelly.wav (2 s loop): foam body bed",
		uploaded(98563654094864, 1, "sfx.wax.body.jelly (squish loop, jelly).wav")
	),
	soundSlot(
		"sfx.wax.body.plush",
		"SFX",
		false,
		1,
		"upload wax_body_plush.wav (2 s loop): foam body bed",
		uploaded(105063440368383, 1, "sfx.wax.body.plush (squish loop, plush).wav")
	),
	soundSlot(
		"sfx.wax.thump",
		"SFX",
		false,
		1,
		"upload wax_thump.wav (0.22 s): palm / thumb press thump, p = 1",
		uploaded(137587557572411, 1, "sfx.wax.thump (thumb or palm press).wav")
	),
	soundSlot(
		"sfx.wax.snapThump",
		"SFX",
		false,
		1,
		"upload wax_snapThump.wav (0.26 s): stretch let-go thump, p = 1",
		uploaded(88772895242479, 1, "sfx.wax.snapThump (stretch let go).wav")
	),
	soundSlot(
		"sfx.wax.rewax",
		"SFX",
		false,
		1,
		"upload wax_rewax_1.wav and wax_rewax_2.wav (≤ 0.4 s; the second as a variant): the re-wax sparkle",
		uploaded(
			85448884149118,
			1,
			"sfx.wax.rewax - 1 (re-wax sparkle).wav",
			{ upload(129078053071491, 1, "sfx.wax.rewax - 2 (re-wax sparkle).wav") }
		)
	),

	-- Inspect showcases (final polish 2026-10-11): the design's own first-person inspect one-shots (fp.js:159-192),
	-- 2D (the toy is in your hands), played by ViewmodelController (Anim/InspectTracks recipes). Pat, plop and snapback
	-- play sfx.squish / sfx.squeezeRelease at the toy's pitch, the hop sfx.pop and the roar sfx.dragonRoar (the slots
	-- that already hold those design sounds). Renders of the design recipes, uploaded by the group (2026-10-12) from
	-- "Squishy Duels sounds to upload\4 New game spots (upload these too)\".
	soundSlot(
		"sfx.inspect.flick",
		"SFX",
		false,
		nil,
		"Kitty Bread's ear flick; design fp.js:173 triangle 900->1300 Hz 0.08 s (0.09 s); file 'inspect - ear flick.wav'",
		uploaded(71451604653051, 1, "sfx.inspect.flick (Kitty Bread ear flick).wav")
	),
	soundSlot(
		"sfx.inspect.whoosh",
		"SFX",
		false,
		nil,
		"flip / twirl / toss / swish (Toast, Banana, Donut, Pancake Pup, Mochi Fox); design fx.js:39 whoosh(0.22), fp.js:175 (0.22 s); file 'inspect - flip or twirl whoosh.wav'",
		uploaded(133182986036888, 1, "sfx.inspect.whoosh (show-off flip or twirl).wav")
	),
	soundSlot(
		"sfx.inspect.flap",
		"SFX",
		false,
		nil,
		"Birdie's and the Dragon's wing flap; design fx.js:39 whoosh(0.12), fp.js:180 (0.12 s); file 'inspect - wing flap.wav'",
		uploaded(101611943205869, 1, "sfx.inspect.flap (Birdie and Dragon wing flap).wav")
	),
	soundSlot(
		"sfx.inspect.tap",
		"SFX",
		false,
		nil,
		"Toast's crust tap; design fp.js:176 triangle 620->560 Hz 0.05 s (0.06 s); file 'inspect - crust tap.wav'",
		uploaded(98542890948375, 1, "sfx.inspect.tap (Toast crust tap).wav")
	),
	soundSlot(
		"sfx.inspect.ring",
		"SFX",
		false,
		nil,
		"the banana phone; design fp.js:166 two square 1320 Hz beeps (0.25 s); file 'inspect - Banana phone ring.wav'",
		uploaded(106690384463641, 1, "sfx.inspect.ring (Banana phone ring).wav")
	),
	soundSlot(
		"sfx.inspect.spread",
		"SFX",
		false,
		nil,
		"Butter's spreading slide; design fp.js:177 lowpass noise 900->500 Hz 0.4 s; file 'inspect - Butter spread.wav'",
		uploaded(136847272271316, 1, "sfx.inspect.spread (Butter spread).wav")
	),
	soundSlot(
		"sfx.inspect.peek",
		"SFX",
		false,
		nil,
		"peek / sniff (Butter, Donut, Pancake Pup); design fp.js:178 sine 700->980 Hz 0.12 s; file 'inspect - peek or sniff.wav'",
		uploaded(113993469428410, 1, "sfx.inspect.peek (peek or sniff).wav")
	),
	soundSlot(
		"sfx.inspect.snap",
		"SFX",
		false,
		nil,
		"Chocolate's snap test with the foil glint; design fp.js:164 (0.37 s); file 'inspect - Chocolate snap.wav'",
		uploaded(101845314096871, 1, "sfx.inspect.snap (Chocolate snap).wav")
	),
	soundSlot(
		"sfx.inspect.tweet",
		"SFX",
		false,
		nil,
		"Birdie's tweet; design fp.js:160 three sine chirps (0.23 s); file 'inspect - Birdie tweet.wav'",
		uploaded(108833044090769, 1, "sfx.inspect.tweet (Birdie tweet).wav")
	),
	soundSlot(
		"sfx.inspect.stretch",
		"SFX",
		false,
		nil,
		"Mochi Fox's mochi stretch; design fp.js:183 squish at 0.8 x pitch + sine 200->120 Hz 0.5 s; file 'inspect - Mochi Fox stretch.wav'",
		uploaded(125190323245324, 1, "sfx.inspect.stretch (Mochi Fox stretch).wav")
	),
	soundSlot(
		"sfx.inspect.ribbit",
		"SFX",
		false,
		nil,
		"Strawberry Frog's ribbit; design fp.js:161 two sawtooth croaks (0.31 s); file 'inspect - Strawberry Frog ribbit.wav'",
		uploaded(129941637516737, 1, "sfx.inspect.ribbit (Strawberry Frog ribbit).wav")
	),
	soundSlot(
		"sfx.inspect.rattle",
		"SFX",
		false,
		nil,
		"Boba Bear's pearl rattle; design fp.js:162 six bandpass noise clicks (0.59 s); file 'inspect - Boba Bear pearl rattle.wav'",
		uploaded(87609876695808, 1, "sfx.inspect.rattle (Boba Bear pearl rattle).wav")
	),
	soundSlot(
		"sfx.inspect.slurp",
		"SFX",
		false,
		nil,
		"Boba Bear's straw sip; design fp.js:163 bandpass noise 400->1400 Hz 0.45 s; file 'inspect - Boba Bear straw slurp.wav'",
		uploaded(75598629811299, 1, "sfx.inspect.slurp (Boba Bear straw slurp).wav")
	),
	soundSlot(
		"sfx.inspect.sparkle",
		"SFX",
		false,
		nil,
		"Cloud Bunny's float sparkle; design fx.js:41 sparkle(3), fp.js:189 (0.37 s); file 'sparkle.wav'",
		uploaded(134590039479670, 1, "sfx.inspect.sparkle (show-off sparkle).wav")
	),
	soundSlot(
		"sfx.inspect.wiggle",
		"SFX",
		false,
		nil,
		"Cupcake Axolotl's gill wiggle; design fp.js:190 sine 500->800 Hz 0.1 s; file 'inspect - Cupcake Axolotl wiggle.wav'",
		uploaded(71738952926616, 1, "sfx.inspect.wiggle (Axolotl gill wiggle).wav")
	),
	soundSlot(
		"sfx.inspect.blub",
		"SFX",
		false,
		nil,
		"Cupcake Axolotl's peek bubbles; design fp.js:165 blub (0.34 s); file 'inspect - Cupcake Axolotl bubbles.wav'",
		uploaded(97788899718008, 1, "sfx.inspect.blub (Axolotl bubbles).wav")
	),

	-- UI (§14.2)
	soundSlot(
		"ui.click",
		"UI",
		false,
		nil,
		"≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick",
		uploaded(108263514590892, 1, "ui.click.wav")
	),
	soundSlot("ui.hover", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.back", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.error", "UI", false, nil, "≤ 0.25 s; search: ui+error+soft"),
	soundSlot("ui.open", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.toast", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	-- UI FINAL R2 (plan §3 pack 2, §2.2): the design's own two clips, rendered from its WebAudio recipe in R0b and
	-- uploaded by the user (until then: ui.click at pitch 1 for the pop, no tone).
	soundSlot(
		"ui.pop",
		"UI",
		false,
		nil,
		"the design's pop (hud-lib.js lib:136; NICE!, AWESOME!, GO); file 'sfx_ui_pop.ogg' (R0b render)"
	),
	soundSlot(
		"ui.levelTone",
		"UI",
		false,
		nil,
		"the level-up rising tone (lib:107-120 with H:720's numbers, 0.45 s); file 'sfx_ui_levelTone.ogg' (R0b render)"
	),
	soundSlot(
		"ui.coin",
		"UI",
		false,
		nil,
		"batched; ≤ 0.4 s; search: coin+collect, coin+ding",
		uploaded(109744762908561, 1, "ui.coin.wav")
	),
	soundSlot("ui.purchase", "UI", false, nil, "≤ 1 s; search: purchase+success+chime"),
	soundSlot(
		"ui.hitConfirm",
		"UI",
		false,
		nil,
		"attacker only; ≤ 0.2 s; search: bubble+pop, ui+pop+soft",
		uploaded(136815270697069, 1, "ui.hitConfirm.wav")
	),
	soundSlot("box.shake", "UI", false, nil, "≤ 0.5 s; search: gift+box+shake"),
	soundSlot("box.open", "UI", false, nil, "≤ 0.5 s; search: gift+open+pop"),
	soundSlot("reveal.common", "UI", false, nil, "escalating; 0.5–2.5 s; search: chime+short"),
	soundSlot("reveal.uncommon", "UI", false, nil, "escalating; 0.5–2.5 s; search: chime+sparkle"),
	soundSlot("reveal.epic", "UI", false, nil, "escalating; 0.5–2.5 s; search: magic+reveal"),
	soundSlot("reveal.exclusive", "UI", false, nil, "escalating; 0.5–2.5 s; search: fanfare+short"),
	soundSlot(
		"duel.countdownTick",
		"UI",
		false,
		nil,
		"≤ 0.4 s; search: countdown+beep",
		uploaded(125727529381410, 1, "duel.countdownTick.wav")
	),
	soundSlot(
		"duel.go",
		"UI",
		false,
		nil,
		"≤ 1 s; search: start+whistle",
		uploaded(92607013701400, 1, "duel.go.wav")
	),
	soundSlot("duel.win", "UI", false, nil, "gentle; 1–4 s; search: victory+jingle+short"),
	soundSlot("duel.lose", "UI", false, nil, "gentle, never mocking; 1–4 s; search: lose+jingle+gentle"),
	soundSlot("duel.draw", "UI", false, nil, "gentle; 1–4 s; search: neutral+chime"),
	-- Feel pass UI (§18.6; named by §17 for Part 8): optional.
	optional(
		soundSlot(
			"ui.gripUnlock",
			"UI",
			false,
			0.6,
			"optional; level-up, pad unlock and rank-up toasts (Config.Audio.toastSounds); search: unlock+chime+soft, level+up+cute"
		)
	),

	-- Music and ambience (§14.2)
	soundSlot(
		"music.lobby",
		"Music",
		false,
		nil,
		"loop; ≥ 60 s; prefer licensed-partner music; search: toy+shop+music, music+box+loop, happy+ukulele+loop"
	),
	optional(soundSlot("music.duel", "Music", false, nil, "optional; loop; ≥ 60 s; search: playful+tension+loop")),
	-- Kill banners (2026-10-16): one sheet per kill set (Art/KillStyle), 2D for the killer only. Tier n (n K.O.s
	-- without being knocked out; 6 and up repeat the 6th) plays [(n - 1)·slot, (n - 1)·slot + soundSeconds] of the
	-- sheet (Config.Audio.killBanner, Sound.PlaybackRegion). 6 x 3 s = 18 s per file.
	soundSlot(
		"sfx.kill.standard",
		"SFX",
		false,
		nil,
		"kill banner sheet, Common and Uncommon squishies (Candy Pop: squishy pop, thump, marimba climb; 6k: bells and sparkles); file 'sfx_kill_standard_v2.ogg'",
		killSheet(85487378778158, "sfx_kill_standard_v2.ogg")
	),
	soundSlot(
		"sfx.kill.feather_storm",
		"SFX",
		false,
		nil,
		"kill banner sheet, Birdie (Feather Storm: wing flutter, whistled bird call; 6k: a flock and a bell); file 'sfx_kill_feather_storm_v2.ogg'",
		killSheet(101356866911300, "sfx_kill_feather_storm_v2.ogg")
	),
	soundSlot(
		"sfx.kill.sprinkle_blast",
		"SFX",
		false,
		nil,
		"kill banner sheet, Donut (Sprinkle Blast: rubbery boings, sprinkle tinkles; 6k: a boing chord and sprinkle rain); file 'sfx_kill_sprinkle_blast_v2.ogg'",
		killSheet(121984041164424, "sfx_kill_sprinkle_blast_v2.ogg")
	),
	soundSlot(
		"sfx.kill.cloudburst",
		"SFX",
		false,
		nil,
		"kill banner sheet, Cloud Bunny (Cloudburst: wind swell, harp; thunder from 4k; 6k: thunder crack and rain); file 'sfx_kill_cloudburst_v2.ogg'",
		killSheet(101952354509153, "sfx_kill_cloudburst_v2.ogg")
	),
	soundSlot(
		"sfx.kill.bubble_burst",
		"SFX",
		false,
		nil,
		"kill banner sheet, Cupcake Axolotl (Bubble Burst: tuned bubbles, underwater blub; 6k: a bubble cascade and a splash); file 'sfx_kill_bubble_burst_v2.ogg'",
		killSheet(132916717444884, "sfx_kill_bubble_burst_v2.ogg")
	),
	soundSlot(
		"sfx.kill.dragon_blaze",
		"SFX",
		false,
		nil,
		"kill banner sheet, Dragon (Dragon's Blaze: taiko, fire whoosh, brass stab; growl from 4k; 6k: roar, gong, full brass); file 'sfx_kill_dragon_blaze_v2.ogg'",
		killSheet(106352691173885, "sfx_kill_dragon_blaze_v2.ogg")
	),
	-- Match HUD M6 / M7 (2026-10-17; the M3 pack: the design's recipes rendered, uploaded by the user, normalised to
	-- -1 dBFS: set each volume from its normGainDb when the id comes in). While an id is nil a look-alike plays
	-- (UI/Match: sfx.impactSoft, ui.error, sfx.inspect.whoosh).
	soundSlot(
		"match.splat",
		"SFX",
		false,
		nil,
		"M:515 splat(1): a K.O. in the feed, you squished; file 'match_splat.wav'"
	),
	soundSlot(
		"match.knockedOut",
		"SFX",
		false,
		nil,
		"lib:151 error(): you got squished (M:548); file 'match_knockedOut.wav'"
	),
	soundSlot(
		"match.whoosh",
		"UI",
		false,
		nil,
		"lib:176 whoosh(true): the card comes in (M:560); file 'match_whoosh.wav'"
	),
	soundSlot(
		"amb.lobby",
		"Ambient",
		false,
		0.15,
		"loop; ≥ 30 s; avoid crowd murmur; search: shop+ambience+quiet, room+tone+light"
	),
	soundSlot(
		"amb.arena",
		"Ambient",
		false,
		0.15,
		"loop; ≥ 30 s; avoid crowd murmur; search: shop+ambience+quiet, room+tone+light"
	),

	-- Animation clips (§14.3)
	otherSlot("anim.throw", "animation", ANIMATION_NOTE),
	otherSlot("anim.cheer", "animation", ANIMATION_NOTE),
	otherSlot("anim.dragonCast", "animation", ANIMATION_NOTE),

	-- Images (§14.3). `img.rarity.*` = the four rarities; `img.nav.*` = the HUD navigation row (§11.6).
	otherSlot("img.coin", "image", IMAGE_NOTE),
	otherSlot("img.rarity.common", "image", IMAGE_NOTE),
	otherSlot("img.rarity.uncommon", "image", IMAGE_NOTE),
	otherSlot("img.rarity.epic", "image", IMAGE_NOTE),
	otherSlot("img.rarity.exclusive", "image", IMAGE_NOTE),
	otherSlot("img.nav.squishies", "image", IMAGE_NOTE),
	otherSlot("img.nav.boxes", "image", IMAGE_NOTE),
	otherSlot("img.nav.shop", "image", IMAGE_NOTE),
	otherSlot("img.nav.quests", "image", IMAGE_NOTE),
	otherSlot("img.nav.daily", "image", IMAGE_NOTE),
	otherSlot("img.nav.duel", "image", IMAGE_NOTE),
	otherSlot("img.nav.settings", "image", IMAGE_NOTE),
	-- Foam UI (spec 2026-10-09): `img.icon.*` = the other UI/Components/IconGlyph icons (`img.nav.*` covers the rest).
	otherSlot("img.icon.change", "image", IMAGE_NOTE),
	otherSlot("img.icon.clock", "image", IMAGE_NOTE),
	otherSlot("img.icon.upgrade", "image", IMAGE_NOTE),
	otherSlot("img.icon.inspect", "image", IMAGE_NOTE),
	-- UI overhaul (2026-10-11): the chunky close X of every window and the check of a claimed or owned state.
	otherSlot("img.icon.close", "image", IMAGE_NOTE),
	otherSlot("img.icon.check", "image", IMAGE_NOTE),
	-- UI FINAL (R1, plan work/ui/PLAN.md §3): the design's other pictures (rendered in R0, uploaded by the user). While
	-- an id is nil: the lock is shapes (UI/Components/LockIcon), the image-only icons hide (IconGlyph.image; the text
	-- beside them says it), the boxes stay the tinted gift, there are no rays or dots, and the radial fills are
	-- vertical gradients.
	otherSlot("img.icon.lock", "image", IMAGE_NOTE),
	otherSlot("img.icon.star", "image", IMAGE_NOTE),
	otherSlot("img.icon.bolt", "image", IMAGE_NOTE),
	otherSlot("img.icon.flame", "image", IMAGE_NOTE),
	otherSlot("img.icon.gift", "image", IMAGE_NOTE),
	otherSlot("img.icon.sound", "image", IMAGE_NOTE),
	otherSlot("img.icon.squeeze", "image", IMAGE_NOTE),
	otherSlot("img.icon.match", "image", IMAGE_NOTE),
	otherSlot("img.box.sweet", "image", IMAGE_NOTE),
	otherSlot("img.box.treat", "image", IMAGE_NOTE),
	otherSlot("img.fx.rays", "image", IMAGE_NOTE),
	otherSlot("img.fx.raysDetail", "image", IMAGE_NOTE),
	otherSlot("img.fx.raysReveal", "image", IMAGE_NOTE),
	otherSlot("img.fx.dots", "image", IMAGE_NOTE),
	otherSlot("img.fx.glow", "image", IMAGE_NOTE),
	-- UI FINAL R2 (plan work/ui/PLAN.md §3 pack 2, rendered in R0b, uploaded by the user, ids in R10b; every key has
	-- the fallback §3 names while its id is nil): the burst star, the game's squishies as pictures and their white
	-- copies, the nav and coin pictures' white copies, the exact CSS radial gradients, the two soft shadows and the
	-- other rays, ribbon and ring pictures of R3-R9.
	otherSlot("img.fx.spark", "image", IMAGE_NOTE),
	otherSlot("img.squishy.kitty_bread", "image", IMAGE_NOTE),
	otherSlot("img.squishy.toast", "image", IMAGE_NOTE),
	otherSlot("img.squishy.banana", "image", IMAGE_NOTE),
	otherSlot("img.squishy.butter", "image", IMAGE_NOTE),
	otherSlot("img.squishy.chocolate", "image", IMAGE_NOTE),
	otherSlot("img.squishy.bird", "image", IMAGE_NOTE),
	otherSlot("img.squishy.donut", "image", IMAGE_NOTE),
	otherSlot("img.squishy.dragon", "image", IMAGE_NOTE),
	otherSlot("img.squishy.boba_bear", "image", IMAGE_NOTE),
	otherSlot("img.squishy.pancake_pup", "image", IMAGE_NOTE),
	otherSlot("img.squishy.mochi_fox", "image", IMAGE_NOTE),
	otherSlot("img.squishy.strawberry_frog", "image", IMAGE_NOTE),
	otherSlot("img.squishy.cloud_bunny", "image", IMAGE_NOTE),
	otherSlot("img.squishy.cupcake_axolotl", "image", IMAGE_NOTE),
	otherSlot("img.squishy.kitty_bread.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.toast.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.banana.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.butter.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.chocolate.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.bird.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.donut.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.dragon.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.boba_bear.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.pancake_pup.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.mochi_fox.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.strawberry_frog.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.cloud_bunny.white", "image", IMAGE_NOTE),
	otherSlot("img.squishy.cupcake_axolotl.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.squishies.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.boxes.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.shop.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.quests.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.daily.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.duel.white", "image", IMAGE_NOTE),
	otherSlot("img.nav.settings.white", "image", IMAGE_NOTE),
	otherSlot("img.coin.white", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.coinGlow", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.scrimWindow", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.plateCommon", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.plateUncommon", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.plateEpic", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.plateExclusive", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.stageCommon", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.stageUncommon", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.stageEpic", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.stageExclusive", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.congrats", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.congratsDisc", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.revealScrim", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.revealTintCommon", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.revealTintUncommon", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.revealTintEpic", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.revealTintExclusive", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.revealFlash", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.levelScrim", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.bubble", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.flashDisc", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.medallion", "image", IMAGE_NOTE),
	otherSlot("img.fx.shadowWindow", "image", IMAGE_NOTE),
	otherSlot("img.fx.shadowCta", "image", IMAGE_NOTE),
	otherSlot("img.fx.raysCoin", "image", IMAGE_NOTE),
	otherSlot("img.icon.gem", "image", IMAGE_NOTE),
	otherSlot("img.fx.raysCongrats", "image", IMAGE_NOTE),
	otherSlot("img.fx.beam", "image", IMAGE_NOTE),
	otherSlot("img.fx.blob", "image", IMAGE_NOTE),
	otherSlot("img.fx.raysLevelUp", "image", IMAGE_NOTE),
	otherSlot("img.fx.ribbon", "image", IMAGE_NOTE),
	otherSlot("img.fx.halfRing", "image", IMAGE_NOTE),
	otherSlot("img.fx.dashRing", "image", IMAGE_NOTE),
	-- Match HUD M7 (2026-10-17; the M3 pack, "Squishy Duels match uploads", uploaded by the user): the "squished by"
	-- card's banner rays and dots, its Grip icon and the knocked-out vignette. While an id is nil the card uses
	-- img.fx.rays, img.fx.dots and img.icon.squeeze, and the vignette two edge gradients (UI/Match).
	otherSlot("img.fx.raysCard", "image", IMAGE_NOTE),
	otherSlot("img.fx.dotsCard", "image", IMAGE_NOTE),
	otherSlot("img.icon.grip", "image", IMAGE_NOTE),
	otherSlot("img.fx.radial.matchVignette", "image", IMAGE_NOTE),
	-- Pens3 phase 9: the food pictures (the pen screen's BUY FOOD cards show one when its id is set).
	otherSlot("img.food.candy_drop", "image", IMAGE_NOTE),
	otherSlot("img.food.butter_bun", "image", IMAGE_NOTE),
	otherSlot("img.food.boba_pearl_pop", "image", IMAGE_NOTE),
	otherSlot("img.food.frosty_scoop", "image", IMAGE_NOTE),
	otherSlot("img.food.lava_truffle", "image", IMAGE_NOTE),
	otherSlot("img.food.prism_tart", "image", IMAGE_NOTE),
	otherSlot("img.food.halo_puff", "image", IMAGE_NOTE),

	-- Kill banners and kill effects (2026-10-16): VFX Studio library textures for the SD_KillVfx emitters
	-- (SDTools.Builders.KillVfxBuilder) and the kill banner (UI/KillBanner). Sheets keep the library's grid.
	vfxStudio("img.kill.flash", 12934685982, "Images/Circle_Mask_01", "Code_ABU", "a soft round glow: banner flashes"),
	vfxStudio("img.kill.splat", 88765597194916, "Images/2024-02-28_14-11-52_Blast1", "XxOmqxXNerd", "a cartoon impact splat behind the banner"),
	vfxStudio("img.kill.burst", 14197758636, "Images/0034", "Quantum1zed", "a radial burst: the 5k and 6k rays"),
	vfxStudio("img.kill.shockRing", 16878151803, "Images/3 (1)", "Z0nito", "a thin glowing ring: shock rings"),
	vfxStudio("img.kill.softRing", 12363693873, "Images/rounded_14", "futabalIs", "a soft thick ring: donut and floor rings"),
	vfxStudio("img.kill.sparkle", 15452013947, "Images/star", "Crackop", "a solid four-point sparkle"),
	vfxStudio("img.kill.twinkle", 109202808131008, "Texture", "k3rxse", "a soft glowing twinkle"),
	vfxStudio("img.kill.feather", 6602421253, "Images/petal2", "Emi1o", "a petal: feathers and axolotl gills"),
	vfxStudio("img.kill.cloud", 290833005, "smoke", "Sofloann", "a cartoon cloud"),
	vfxStudio("img.kill.puffs", 13828988163, "Images/Mist3", "3k3x", "cartoon puffs, a 4x4 flipbook"),
	vfxStudio("img.kill.bubble", 12363676882, "Images/sphere_41", "futabalIs", "a glossy bubble"),
	vfxStudio("img.kill.bubblePop", 12800351913, "Images/Bubble03 - Copy", "Epistylia", "bubbles popping, a 2x2 flipbook"),
	vfxStudio("img.kill.splash", 136795493746726, "Texture", "k3rxse", "cartoon splashes, a 4x4 flipbook (glaze and water)"),
	vfxStudio("img.kill.sprinkle", 73401697522953, "Images/SmallTicTac (1)", "XxOmqxXNerd", "a pill: sprinkles and rain streaks"),
	vfxStudio("img.kill.fire", 91844401982114, "Images_cartoony_fire", "XxOmqxXNerd", "cartoon fire, a 2x2 flipbook"),
	vfxStudio("img.kill.explosion", 11696029985, "a", "ms_d0ss", "a cartoon explosion, a 4x4 flipbook"),
	vfxStudio("img.kill.tealSmoke", 14374273963, "Images/fluid14", "chunchbunch", "teal dragon smoke, a 4x4 flipbook"),
	vfxStudio("img.kill.heart", 107362491349840, "Images/Heart_01", "k3rxse", "a soft heart"),
	vfxStudio("img.kill.lightning", 14052694884, "Images/n1", "Quantum1zed", "a lightning bolt"),
	vfxStudio("img.kill.frameArcs", 12362768191, "Images/target_27", "ZZSSVVDD", "banner frame: four arcs (Candy Pop)"),
	vfxStudio("img.kill.frameNotch", 113974948433764, "Images/51_Sem_Titulo_20241208194817", "No²³ (group)", "banner frame: a notched ring (Feather Storm)"),
	vfxStudio("img.kill.frameTicks", 12362738407, "Images/target_2", "ZZSSVVDD", "banner frame: radial ticks (Feather Storm 6k)"),
	vfxStudio("img.kill.frameSpikes", 71625533541727, "Images/019e6ca4578af6ece3d8e70e92e63829", "No²³ (group)", "banner frame: a ring of spikes (Candy Pop 6k)"),
	vfxStudio("img.kill.frameOrnate", 75548700533773, "373 Sem Título2_20241115155826", "HF_185", "banner frame: an ornate ring (Cloudburst)"),
	vfxStudio("img.kill.frameSegments", 12362776008, "Images/target_34", "ZZSSVVDD", "banner frame: ring segments (Sprinkle Blast)"),
	vfxStudio("img.kill.frameSun", 794950602, "Cool Glowing Spawn Decal", "D0ubleH3lix", "banner frame: wavy sun rays (Bubble Burst 6k)"),
	vfxStudio("img.kill.frameDragon", 11902232976, "Images/circle (2)", "JamProfessional", "banner frame: a dragon ring (Dragon's Blaze)"),
	vfxStudio("img.kill.dragonWing", 12403174434, "211", "Ekzotericheskiy", "a tribal dragon: the Dragon's Blaze 6k wings"),
	-- Kill banners v2 (2026-10-17): each set's emblem and its white silhouette (the slam's flash, the ink shadow).
	killEmblem("img.kill.emblem.standard", 101070134805108, "kill_emblem_standard.png", "Candy Pop: a squished jelly blob with the game's squish face and a star"),
	killEmblem("img.kill.emblem.standard.white", 93336161763338, "kill_emblem_standard_white.png", "Candy Pop: a squished jelly blob with the game's squish face and a star: white silhouette"),
	killEmblem("img.kill.emblem.feather_storm", 106533902166698, "kill_emblem_feather_storm.png", "Feather Storm: Birdie, low-fidelity"),
	killEmblem("img.kill.emblem.feather_storm.white", 128305713938623, "kill_emblem_feather_storm_white.png", "Feather Storm: Birdie, low-fidelity: white silhouette"),
	killEmblem("img.kill.emblem.sprinkle_blast", 79552439839868, "kill_emblem_sprinkle_blast.png", "Sprinkle Blast: Donut, low-fidelity"),
	killEmblem("img.kill.emblem.sprinkle_blast.white", 137126921710110, "kill_emblem_sprinkle_blast_white.png", "Sprinkle Blast: Donut, low-fidelity: white silhouette"),
	killEmblem("img.kill.emblem.cloudburst", 88739962234384, "kill_emblem_cloudburst.png", "Cloudburst: Cloud Bunny, low-fidelity"),
	killEmblem("img.kill.emblem.cloudburst.white", 136570831520750, "kill_emblem_cloudburst_white.png", "Cloudburst: Cloud Bunny, low-fidelity: white silhouette"),
	killEmblem("img.kill.emblem.bubble_burst", 73334765893192, "kill_emblem_bubble_burst.png", "Bubble Burst: Cupcake Axolotl, low-fidelity"),
	killEmblem("img.kill.emblem.bubble_burst.white", 125496553543566, "kill_emblem_bubble_burst_white.png", "Bubble Burst: Cupcake Axolotl, low-fidelity: white silhouette"),
	killEmblem("img.kill.emblem.dragon_blaze", 107936827492507, "kill_emblem_dragon_blaze.png", "Dragon's Blaze: Dragon, low-fidelity"),
	killEmblem("img.kill.emblem.dragon_blaze.white", 112730103205754, "kill_emblem_dragon_blaze_white.png", "Dragon's Blaze: Dragon, low-fidelity: white silhouette"),
}

-- UI FINAL picture ids (plan work/ui/PLAN.md R10): the design's 26 pictures, rendered 1:1 from the co-owner's UI FINAL
-- files (R0) and uploaded by the user to the DIJAY Studios group on 2026-10-14 (Asset Manager import of "Squishy Duels
-- UI uploads/1 upload now"; each file is its key with "." -> "_" plus ".png"). Checked that day: group-owned Image
-- assets with those names (Studio search_asset), thumbnails state Completed. Filled in here, apart from the slot lines
-- above (some of them are the co-owner's), before the slots freeze.
local IMAGE_UPLOAD_DATE = "2026-10-14"
local IMAGE_UPLOAD_LICENSE = "Group-owned upload; rendered from the co-owner's own Claude Design UI FINAL files"
local IMAGE_IDS: { [string]: number } = {
	["img.coin"] = 90713766462731,
	["img.nav.squishies"] = 104894121342657,
	["img.nav.boxes"] = 92341248104176,
	["img.nav.shop"] = 93615172778327,
	["img.nav.quests"] = 73060299726151,
	["img.nav.daily"] = 133292280404049,
	["img.nav.duel"] = 86138187108930,
	["img.nav.settings"] = 106586140072962,
	["img.icon.check"] = 75504651196077,
	["img.icon.close"] = 118301423971613,
	["img.icon.clock"] = 78025365670037,
	["img.icon.lock"] = 106121352096349,
	["img.icon.star"] = 116982124354283,
	["img.icon.bolt"] = 108086298024901,
	["img.icon.flame"] = 103076380529363,
	["img.icon.gift"] = 93988585835101,
	["img.icon.sound"] = 126975592754375,
	["img.icon.squeeze"] = 77432147407452,
	["img.icon.match"] = 75650728481067,
	["img.box.sweet"] = 102246400652557,
	["img.box.treat"] = 108858759156594,
	["img.fx.rays"] = 127919808884928,
	["img.fx.raysDetail"] = 129278230460109,
	["img.fx.raysReveal"] = 104783140251190,
	["img.fx.dots"] = 85381713960011,
	["img.fx.glow"] = 107009283075080,
}
for _, slot in SLOTS do
	local id = IMAGE_IDS[slot.key]
	if id ~= nil and slot.kind == "image" then
		local file = string.gsub(slot.key, "%.", "_") .. ".png"
		slot.id = id
		slot.source = `DIJAY Studios group upload: '{file}'`
		slot.license = IMAGE_UPLOAD_LICENSE
		slot.verifiedAt = IMAGE_UPLOAD_DATE
		slot.notes = "UI FINAL design picture (R0 render of the design's own file)."
	end
end

-- The content string of an asset id: positive integers only, else nil.
local function contentFor(id: unknown): string?
	if type(id) ~= "number" or id ~= id or id < 1 or id > MAX_EXACT_ID or math.floor(id) ~= id then
		return nil
	end
	return CONTENT_PREFIX .. string.format("%d", id)
end

-- kind -> key -> slot, and sound key -> its choices (pure data, built once when required).
local BY_KIND: { [AssetKind]: { [string]: AssetSlot } } = { sound = {}, animation = {}, image = {} }
local CHOICES: { [string]: { SoundChoice } } = {}
local NO_CHOICES: { SoundChoice } = table.freeze({})
for _, slot in SLOTS do
	BY_KIND[slot.kind][slot.key] = slot
	if slot.kind == "sound" then
		local choices: { SoundChoice } = {}
		local mainContent = contentFor(slot.id)
		if mainContent ~= nil then
			table.insert(choices, {
				id = slot.id :: number,
				content = mainContent,
				volume = slot.volume or DEFAULT_VOLUME,
			})
			local slotVariants: { SoundVariant } = slot.variants or {}
			for _, variant in slotVariants do
				local content = contentFor(variant.id)
				if content ~= nil then
					table.insert(choices, { id = variant.id, content = content, volume = variant.volume })
				end
			end
		end
		for _, choice in choices do
			table.freeze(choice)
		end
		CHOICES[slot.key] = table.freeze(choices)
	end
	local variants = slot.variants
	if variants then
		for _, variant in variants do
			table.freeze(variant)
		end
		table.freeze(variants)
	end
	table.freeze(slot)
end
table.freeze(SLOTS)
for _, index in BY_KIND do
	table.freeze(index)
end
table.freeze(BY_KIND)
table.freeze(CHOICES)

-- Unknown keys (typos) that already produced a warning.
local warnedKeys: { [string]: boolean } = {}

local function slotOf(kind: AssetKind, key: string): AssetSlot?
	local slot = BY_KIND[kind][key]
	if slot == nil then
		local label = kind .. ":" .. key
		if not warnedKeys[label] then
			warnedKeys[label] = true
			warn(`[SD][AssetTable] Unknown {kind} key: {key}`)
		end
	end
	return slot
end

local function contentId(kind: AssetKind, key: string): string?
	local slot = slotOf(kind, key)
	if slot == nil then
		return nil
	end
	return contentFor(slot.id)
end

-- Content id ("rbxassetid://…") for a sound key, or nil when the slot is PENDING (disabled) or unknown.
function AssetTable.sound(key: string): string?
	return contentId("sound", key)
end

-- Content id for an animation clip key, or nil (v1: always nil, animation is procedural).
function AssetTable.animation(key: string): string?
	return contentId("animation", key)
end

-- Content id for an image key, or nil (v1: always nil, icons are UI shapes).
function AssetTable.image(key: string): string?
	return contentId("image", key)
end

-- Every slot with its metadata (frozen), in document order. Used for startup warnings, audio checks and audits.
function AssetTable.all(): { AssetSlot }
	return SLOTS
end

-- The playable choices of a sound key (§18.6): the slot's own id first, then each variant, each with its own volume
-- (frozen). Empty when the slot is PENDING or the key is unknown (warned once). SoundController picks among them
-- with pickVariant, never repeating the last pick when there are two or more.
function AssetTable.soundChoices(key: string): { SoundChoice }
	if slotOf("sound", key) == nil then
		return NO_CHOICES
	end
	return CHOICES[key] or NO_CHOICES
end

-- "rbxassetid://<id>" for a positive integer id, else nil (0, negative, fractional, NaN, infinite or not a number).
-- The Studio sound picker builds its audition content with this, so no other file spells the prefix (§18.6).
function AssetTable.contentIdFor(id: number): string?
	return contentFor(id)
end

return table.freeze(AssetTable)
