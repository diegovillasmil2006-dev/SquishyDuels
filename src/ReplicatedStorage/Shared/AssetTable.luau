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

-- soundSlot's `approved` argument (§18.7 "Approved slot format"); nil = PENDING, which is every slot today.
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

-- §14.2 sound slots and §14.3 animation and image slots, in document order.
local SLOTS: { AssetSlot } = {
	-- SFX (§14.2)
	soundSlot(
		"sfx.squish",
		"SFX",
		true,
		nil,
		"3 variants; 0.15–0.5 s; search: soft+squish, squishy+toy+squeeze, foam+squeeze, stress+ball+squeeze"
	),
	soundSlot("sfx.squeezeRelease", "SFX", true, 0.3, "0.3–0.8 s; search: soft+air+release, pillow+squeeze"),
	soundSlot(
		"sfx.throw",
		"SFX",
		true,
		nil,
		"3 variants; 0.15–0.4 s; search: whoosh+short, swoosh+light, air+swipe+quick"
	),
	soundSlot("sfx.throwDragon", "SFX", true, nil, "0.4–1.0 s; search: fireball+whoosh, magic+whoosh"),
	soundSlot("sfx.dragonTelegraph", "SFX", true, nil, "0.5–0.9 s; search: power+up+short, magic+charge"),
	soundSlot("sfx.dragonChomp", "SFX", true, nil, "0.3–0.7 s; search: cartoon+chomp, cartoon+bite"),
	optional(
		soundSlot(
			"sfx.dragonRoar",
			"SFX",
			false,
			nil,
			"optional; ≤ 1 s; search: cute+dragon+roar, cartoon+roar+short"
		)
	),
	soundSlot("sfx.impactBoing", "SFX", true, nil, "2 variants; 0.2–0.6 s; search: cartoon+boing, rubber+bounce"),
	soundSlot("sfx.impactSoft", "SFX", true, nil, "≤ 0.4 s; search: soft+thud, pillow+hit"),
	soundSlot("sfx.elimination", "SFX", true, nil, "0.3–0.8 s; search: cartoon+poof, puff+cartoon"),
	-- Feel pass SFX (§18.6): optional, so the user can skip them in the picker.
	optional(
		soundSlot(
			"sfx.jellyWobble",
			"SFX",
			true,
			0.5,
			"optional; the jelly ripple on walls and cover; 0.2–0.6 s; search: jelly+wobble, jello+wobble, slime+wobble"
		)
	),
	optional(
		soundSlot(
			"sfx.pop",
			"SFX",
			true,
			0.35,
			"optional; throw ready again, the big squeeze pop, ult READY; ≤ 0.3 s; search: bubble+pop+soft, cute+pop"
		)
	),

	-- Moves (spec phase 5): the dash and the four Epic ultimates. Rendered from the design's own synth recipes
	-- (scratchpad sounds-out; spec sounds.md Tier 2), waiting for the upload, check and approval pipeline.
	soundSlot(
		"sfx.dash",
		"SFX",
		true,
		nil,
		"the dash push-off (frame 2); design fx.js:45 dash(), fp.js:516; 2 variants rendered (sfx_dash_1/2.wav, 0.2 s)"
	),
	soundSlot(
		"sfx.dashPlant",
		"SFX",
		true,
		nil,
		"the dash plant (frame 7); design fx.js:47 land(false), fp.js:517; rendered sfx_dashPlant.wav (0.23 s)"
	),
	soundSlot(
		"sfx.ultCharge.bird",
		"SFX",
		true,
		nil,
		"Flock Volley wind-up (0.35 s); design fp.js:463 sawtooth 120->420 Hz + sparkle(4); sfx_ultCharge_bird.wav"
	),
	soundSlot(
		"sfx.ultCharge.donut",
		"SFX",
		true,
		nil,
		"Sprinkle Roller wind-up (0.45 s); design fp.js:463 sawtooth 120->420 Hz + sparkle(4); sfx_ultCharge_donut.wav"
	),
	soundSlot(
		"sfx.ultCharge.cloud_bunny",
		"SFX",
		true,
		nil,
		"Rain Check wind-up (0.6 s); design fp.js:463; rendered sfx_ultCharge_cloud_bunny.wav"
	),
	soundSlot(
		"sfx.ultCharge.cupcake_axolotl",
		"SFX",
		true,
		nil,
		"Bubble Pop wind-up (0.5 s); design fp.js:463; rendered sfx_ultCharge_cupcake_axolotl.wav"
	),
	soundSlot(
		"sfx.ultRelease",
		"SFX",
		true,
		nil,
		"every Epic ultimate's release; design fx.js:39 whoosh(0.6), fp.js:334; rendered sfx_ultRelease.wav (0.55 s)"
	),
	soundSlot(
		"sfx.ultRainDrop",
		"SFX",
		true,
		nil,
		"a Rain Check drop lands; design fp.js:372 sine 900->400 Hz 0.08 s; rendered sfx_ultRainDrop.wav (0.15 s)"
	),
	soundSlot(
		"sfx.ultCloudHover",
		"SFX",
		true,
		nil,
		"the Rain Check cloud parks; design fx.js:41 sparkle(4), fp.js:255; rendered sfx_ultCloudHover.wav (0.37 s)"
	),
	soundSlot(
		"sfx.ultBubblePop",
		"SFX",
		true,
		nil,
		"Bubble Pop pops; design fp.js:165 blub, fp.js:361; rendered sfx_ultBubblePop.wav (0.4 s)"
	),

	-- The charge throw and the catch (feature 1, 2026-10-11; design: the combat-effects page "Squishy Combat FP
	-- v2.html" and its squishy-lib-v2.js sfx). PENDING: renders of the design's own synth recipes are expected in the
	-- upload folder under the file names below. The tone and the ping are the own player's (2D); the catch sounds play
	-- 2D for the catcher and 3D at the catcher's hands for the thrower.
	soundSlot(
		"sfx.chargeLoop",
		"SFX",
		false,
		nil,
		"PENDING; the charge tone, looped (CatchController / ThrowController drive its pitch and volume, Config.Audio.charge); design squishy-lib-v2.js:378-386 triangle + sine (×1.505) through a 700-2500 Hz low-pass; a steady 1.6 s loop at 250 Hz (c 0.28: PlaybackSpeed 0.6..2 gives the design's 150..510 Hz); file 'sfx.charge - loop.wav'"
	),
	soundSlot(
		"sfx.chargeFull",
		"SFX",
		false,
		nil,
		"PENDING; the full-charge ping (with the white ring); design html:514 sfx.squish(release, 0.6), squishy-lib-v2.js:367 (0.15 s); file 'sfx.charge - full ping.wav'"
	),
	soundSlot(
		"sfx.catch",
		"SFX",
		true,
		nil,
		"PENDING; a throw is caught; design html:351 sfx.catch, squishy-lib-v2.js:371 high-pass noise 1800->900 Hz + sine 220->120 Hz (0.14 s); file 'sfx.catch - catch.wav'"
	),
	soundSlot(
		"sfx.crushSqueak",
		"SFX",
		true,
		nil,
		"PENDING; the caught toy squeaks as the crush starts (0.12 s in); design html:553 sfx.squish(press, 1), squishy-lib-v2.js:365 (0.22 s); file 'sfx.catch - crush squeak.wav'"
	),
	soundSlot(
		"sfx.crushBurst",
		"SFX",
		true,
		nil,
		"PENDING; the caught toy bursts; design html:560 sfx.explode, squishy-lib-v2.js:373-377 low-pass noise 4000->250 Hz + sine 130->38 Hz + chimes (0.7 s); file 'sfx.catch - burst.wav'"
	),

	-- The knead's wax crunch (spec phase2-squeeze §3.10): renders of the design's own generators (squish.js:676-709,
	-- 829-833, fx.js:41), 48 kHz mono, in the scratchpad's work/sounds-out (the sheets are also "wax crack sheet -
	-- <feel>.wav" in the upload folder's Extras). 2D; Controllers/KneadAudio plays them in the Wax group at the levels of
	-- Config.Audio.wax (volume 1 here). A sheet is played one region at a time (Sound.PlaybackRegion): 54 bursts, 48
	-- grains, 5 taps (layout: Config.Audio.wax).
	soundSlot("sfx.wax.foam", "SFX", false, 1, "upload wax_sheet_foam.wav (9.58 s): foam crack sheet, by region"),
	soundSlot("sfx.wax.mochi", "SFX", false, 1, "upload wax_sheet_mochi.wav (9.58 s): mochi crack sheet, by region"),
	soundSlot("sfx.wax.jelly", "SFX", false, 1, "upload wax_sheet_jelly.wav (9.58 s): jelly crack sheet, by region"),
	soundSlot("sfx.wax.plush", "SFX", false, 1, "upload wax_sheet_plush.wav (9.58 s): plush crack sheet, by region"),
	soundSlot("sfx.wax.haze.foam", "SFX", false, 1, "upload wax_haze_foam.wav (2 s loop): micro-crackle haze bed"),
	soundSlot("sfx.wax.haze.mochi", "SFX", false, 1, "upload wax_haze_mochi.wav (2 s loop): micro-crackle haze bed"),
	soundSlot("sfx.wax.haze.jelly", "SFX", false, 1, "upload wax_haze_jelly.wav (2 s loop): micro-crackle haze bed"),
	soundSlot("sfx.wax.haze.plush", "SFX", false, 1, "upload wax_haze_plush.wav (2 s loop): micro-crackle haze bed"),
	soundSlot("sfx.wax.body.foam", "SFX", false, 1, "upload wax_body_foam.wav (2 s loop): foam body bed"),
	soundSlot("sfx.wax.body.mochi", "SFX", false, 1, "upload wax_body_mochi.wav (2 s loop): foam body bed"),
	soundSlot("sfx.wax.body.jelly", "SFX", false, 1, "upload wax_body_jelly.wav (2 s loop): foam body bed"),
	soundSlot("sfx.wax.body.plush", "SFX", false, 1, "upload wax_body_plush.wav (2 s loop): foam body bed"),
	soundSlot("sfx.wax.thump", "SFX", false, 1, "upload wax_thump.wav (0.22 s): palm / thumb press thump, p = 1"),
	soundSlot("sfx.wax.snapThump", "SFX", false, 1, "upload wax_snapThump.wav (0.26 s): stretch let-go thump, p = 1"),
	soundSlot(
		"sfx.wax.rewax",
		"SFX",
		false,
		1,
		"upload wax_rewax_1.wav and wax_rewax_2.wav (≤ 0.4 s; the second as a variant): the re-wax sparkle"
	),

	-- Inspect showcases (final polish 2026-10-11): the design's own first-person inspect one-shots (fp.js:159-192),
	-- 2D (the toy is in your hands), played by ViewmodelController (Anim/InspectTracks recipes). Pat, plop and snapback
	-- play sfx.squish / sfx.squeezeRelease at the toy's pitch, the hop sfx.pop and the roar sfx.dragonRoar (the slots
	-- that already hold those design sounds). The expected files are in "Squishy Duels sounds to upload\2 Extras
	-- (optional)\" (renders of the design recipes); the two whooshes are not rendered yet.
	soundSlot(
		"sfx.inspect.flick",
		"SFX",
		false,
		nil,
		"Kitty Bread's ear flick; design fp.js:173 triangle 900->1300 Hz 0.08 s (0.09 s); file 'inspect - ear flick.wav'"
	),
	soundSlot(
		"sfx.inspect.whoosh",
		"SFX",
		false,
		nil,
		"flip / twirl / toss / swish (Toast, Banana, Donut, Pancake Pup, Mochi Fox); design fx.js:39 whoosh(0.22), fp.js:175 (0.22 s); file 'inspect - flip or twirl whoosh.wav'"
	),
	soundSlot(
		"sfx.inspect.flap",
		"SFX",
		false,
		nil,
		"Birdie's and the Dragon's wing flap; design fx.js:39 whoosh(0.12), fp.js:180 (0.12 s); file 'inspect - wing flap.wav'"
	),
	soundSlot(
		"sfx.inspect.tap",
		"SFX",
		false,
		nil,
		"Toast's crust tap; design fp.js:176 triangle 620->560 Hz 0.05 s (0.06 s); file 'inspect - crust tap.wav'"
	),
	soundSlot(
		"sfx.inspect.ring",
		"SFX",
		false,
		nil,
		"the banana phone; design fp.js:166 two square 1320 Hz beeps (0.25 s); file 'inspect - Banana phone ring.wav'"
	),
	soundSlot(
		"sfx.inspect.spread",
		"SFX",
		false,
		nil,
		"Butter's spreading slide; design fp.js:177 lowpass noise 900->500 Hz 0.4 s; file 'inspect - Butter spread.wav'"
	),
	soundSlot(
		"sfx.inspect.peek",
		"SFX",
		false,
		nil,
		"peek / sniff (Butter, Donut, Pancake Pup); design fp.js:178 sine 700->980 Hz 0.12 s; file 'inspect - peek or sniff.wav'"
	),
	soundSlot(
		"sfx.inspect.snap",
		"SFX",
		false,
		nil,
		"Chocolate's snap test with the foil glint; design fp.js:164 (0.37 s); file 'inspect - Chocolate snap.wav'"
	),
	soundSlot(
		"sfx.inspect.tweet",
		"SFX",
		false,
		nil,
		"Birdie's tweet; design fp.js:160 three sine chirps (0.23 s); file 'inspect - Birdie tweet.wav'"
	),
	soundSlot(
		"sfx.inspect.stretch",
		"SFX",
		false,
		nil,
		"Mochi Fox's mochi stretch; design fp.js:183 squish at 0.8 x pitch + sine 200->120 Hz 0.5 s; file 'inspect - Mochi Fox stretch.wav'"
	),
	soundSlot(
		"sfx.inspect.ribbit",
		"SFX",
		false,
		nil,
		"Strawberry Frog's ribbit; design fp.js:161 two sawtooth croaks (0.31 s); file 'inspect - Strawberry Frog ribbit.wav'"
	),
	soundSlot(
		"sfx.inspect.rattle",
		"SFX",
		false,
		nil,
		"Boba Bear's pearl rattle; design fp.js:162 six bandpass noise clicks (0.59 s); file 'inspect - Boba Bear pearl rattle.wav'"
	),
	soundSlot(
		"sfx.inspect.slurp",
		"SFX",
		false,
		nil,
		"Boba Bear's straw sip; design fp.js:163 bandpass noise 400->1400 Hz 0.45 s; file 'inspect - Boba Bear straw slurp.wav'"
	),
	soundSlot(
		"sfx.inspect.sparkle",
		"SFX",
		false,
		nil,
		"Cloud Bunny's float sparkle; design fx.js:41 sparkle(3), fp.js:189 (0.37 s); file 'sparkle.wav'"
	),
	soundSlot(
		"sfx.inspect.wiggle",
		"SFX",
		false,
		nil,
		"Cupcake Axolotl's gill wiggle; design fp.js:190 sine 500->800 Hz 0.1 s; file 'inspect - Cupcake Axolotl wiggle.wav'"
	),
	soundSlot(
		"sfx.inspect.blub",
		"SFX",
		false,
		nil,
		"Cupcake Axolotl's peek bubbles; design fp.js:165 blub (0.34 s); file 'inspect - Cupcake Axolotl bubbles.wav'"
	),

	-- UI (§14.2)
	soundSlot("ui.click", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.hover", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.back", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.error", "UI", false, nil, "≤ 0.25 s; search: ui+error+soft"),
	soundSlot("ui.open", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.toast", "UI", false, nil, "≤ 0.25 s; search: ui+click+soft, button+pop, menu+tick"),
	soundSlot("ui.coin", "UI", false, nil, "batched; ≤ 0.4 s; search: coin+collect, coin+ding"),
	soundSlot("ui.purchase", "UI", false, nil, "≤ 1 s; search: purchase+success+chime"),
	soundSlot("ui.hitConfirm", "UI", false, nil, "attacker only; ≤ 0.2 s; search: bubble+pop, ui+pop+soft"),
	soundSlot("box.shake", "UI", false, nil, "≤ 0.5 s; search: gift+box+shake"),
	soundSlot("box.open", "UI", false, nil, "≤ 0.5 s; search: gift+open+pop"),
	soundSlot("reveal.common", "UI", false, nil, "escalating; 0.5–2.5 s; search: chime+short"),
	soundSlot("reveal.uncommon", "UI", false, nil, "escalating; 0.5–2.5 s; search: chime+sparkle"),
	soundSlot("reveal.epic", "UI", false, nil, "escalating; 0.5–2.5 s; search: magic+reveal"),
	soundSlot("reveal.exclusive", "UI", false, nil, "escalating; 0.5–2.5 s; search: fanfare+short"),
	soundSlot("duel.countdownTick", "UI", false, nil, "≤ 0.4 s; search: countdown+beep"),
	soundSlot("duel.go", "UI", false, nil, "≤ 1 s; search: start+whistle"),
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
}

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
