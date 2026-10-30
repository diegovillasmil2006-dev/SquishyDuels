--!strict
-- AssetTable_Test: unit tests for ReplicatedStorage.Shared.AssetTable. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §14, §18.6, §18.7, §18.10 L1):
--   * the sound key set is exactly the 37 of §18.6 (the 34 of §14.2 plus ui.gripUnlock, sfx.jellyWobble, sfx.pop),
--     the 10 of spec phase 5 (the dash and the four Epic ultimates), the 16 of the Inspect showcases (final polish
--     2026-10-11: the design's own inspect one-shots, 2D SFX) and the 5 of feature 1 (2026-10-11: the charge throw and
--     the catch, each note naming its file) and the 2 of the 2026-10-15 dash + double jump overhaul, 70 in all;
--   * UI FINAL R2's 2 sound keys (the design's ui.pop and ui.levelTone, plan work/ui/PLAN.md §3 pack 2) are counted
--     apart from those 70 (R2_SOUND_KEYS): each is a sound slot, once;
--   * a PENDING slot (id nil) carries no metadata (no source, licence, verifiedAt or variants);
--   * an approved slot has an integer id > 0, a volume in (0, 2], a source, a licence and verifiedAt as YYYY-MM-DD,
--     and so does each variant; no id repeats within a key;
--   * music and ambience are 2D; the new feel pass slots are optional (the picker may skip them);
--   * contentIdFor accepts positive integers only; soundChoices lists the slot's id then its variants, and nothing
--     for a PENDING or unknown key;
--   * Part 8, acceptance 10 "AssetTable audit" (§13.3, §14.1): a slot of ANY kind (sound, animation, image) that has
--     an id carries an integer id > 0, a source, a licence and verifiedAt as YYYY-MM-DD, and so does each variant
--     (until Part 8 only sound slots were checked for this metadata). Sound slots hold the group's uploads since
--     2026-10-12; a planted entry of each kind proves the check itself.
-- Pure data: runs in Edit mode on the Shared clone. Holds no asset ids (the approved branches check whatever the
-- table holds once the picker flow writes ids).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

-- §18.6: the 37 sound keys, then spec phase 5's 10, then the Inspect showcases' 16 (final polish 2026-10-11), then
-- feature 1's 5 (2026-10-11).
local SOUND_KEYS = {
	"sfx.squish",
	"sfx.squeezeRelease",
	"sfx.pop",
	"sfx.throw",
	"sfx.throwDragon",
	"sfx.dragonTelegraph",
	"sfx.dragonChomp",
	"sfx.dragonRoar",
	"sfx.impactBoing",
	"sfx.impactSoft",
	"sfx.jellyWobble",
	"sfx.elimination",
	"ui.click",
	"ui.hover",
	"ui.back",
	"ui.error",
	"ui.open",
	"ui.toast",
	"ui.coin",
	"ui.purchase",
	"ui.hitConfirm",
	"ui.gripUnlock",
	"box.shake",
	"box.open",
	"reveal.common",
	"reveal.uncommon",
	"reveal.epic",
	"reveal.exclusive",
	"duel.countdownTick",
	"duel.go",
	"duel.win",
	"duel.lose",
	"duel.draw",
	"music.lobby",
	"music.duel",
	"amb.lobby",
	"amb.arena",
	"sfx.dash",
	"sfx.dashPlant",
	"sfx.dashWhoosh", -- the 2026-10-15 dash + double jump overhaul
	"sfx.doubleJump",
	"sfx.ultCharge.bird",
	"sfx.ultCharge.donut",
	"sfx.ultCharge.cloud_bunny",
	"sfx.ultCharge.cupcake_axolotl",
	"sfx.ultRelease",
	"sfx.ultRainDrop",
	"sfx.ultCloudHover",
	"sfx.ultBubblePop",
	"sfx.inspect.flick",
	"sfx.inspect.whoosh",
	"sfx.inspect.flap",
	"sfx.inspect.tap",
	"sfx.inspect.ring",
	"sfx.inspect.spread",
	"sfx.inspect.peek",
	"sfx.inspect.snap",
	"sfx.inspect.tweet",
	"sfx.inspect.stretch",
	"sfx.inspect.ribbit",
	"sfx.inspect.rattle",
	"sfx.inspect.slurp",
	"sfx.inspect.sparkle",
	"sfx.inspect.wiggle",
	"sfx.inspect.blub",
	"sfx.chargeLoop",
	"sfx.chargeFull",
	"sfx.catch",
	"sfx.crushSqueak",
	"sfx.crushBurst",
}

-- UI FINAL R2 (plan work/ui/PLAN.md §3 pack 2): the design's two new clips, counted apart from SOUND_KEYS.
local R2_SOUND_KEYS = { "ui.pop", "ui.levelTone" }

-- Spec phase2-squeeze §3.10: the knead's wax sounds (Controllers/KneadAudio), counted apart from the §18.6 set.
local WAX_PREFIX = "sfx.wax."
local WAX_KEYS = {
	"sfx.wax.foam",
	"sfx.wax.mochi",
	"sfx.wax.jelly",
	"sfx.wax.plush",
	"sfx.wax.haze.foam",
	"sfx.wax.haze.mochi",
	"sfx.wax.haze.jelly",
	"sfx.wax.haze.plush",
	"sfx.wax.body.foam",
	"sfx.wax.body.mochi",
	"sfx.wax.body.jelly",
	"sfx.wax.body.plush",
	"sfx.wax.thump",
	"sfx.wax.snapThump",
	"sfx.wax.rewax",
}

-- §18.6 keys marked "(optional)": the three new slots, the Dragon roar and the duel music.
local OPTIONAL_KEYS = { "sfx.jellyWobble", "sfx.pop", "ui.gripUnlock", "sfx.dragonRoar", "music.duel" }

local CONTENT_PREFIX = "rbxassetid://"
local DATE_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"
local ASSET_KINDS = { sound = true, animation = true, image = true } -- AssetTable.AssetKind

local function sorted(list: { string }): { string }
	local copy = table.clone(list)
	table.sort(copy)
	return copy
end

local function isPositiveInteger(value: unknown): boolean
	return type(value) == "number" and value >= 1 and math.floor(value) == value
end

local function expectApproved(expect: any, label: string, entry: any)
	if not isPositiveInteger(entry.id) then
		error(`{label}: id must be an integer > 0`)
	end
	if not (type(entry.volume) == "number" and entry.volume > 0 and entry.volume <= 2) then
		error(`{label}: volume must be in (0, 2]`)
	end
	for _, field in { "source", "license" } do
		if not (type(entry[field]) == "string" and entry[field] ~= "") then
			error(`{label}: {field} is missing`)
		end
	end
	expect.truthy(type(entry.verifiedAt) == "string" and string.match(entry.verifiedAt, DATE_PATTERN) ~= nil)
end

-- Acceptance 10 (§13.3, §14.1): an approved id of any kind says where it came from. Errors on the first broken field.
local function expectProvenance(label: string, entry: any)
	if not isPositiveInteger(entry.id) then
		error(`{label}: id must be an integer > 0`)
	end
	for _, field in { "source", "license" } do
		if not (type(entry[field]) == "string" and entry[field] ~= "") then
			error(`{label}: {field} is missing`)
		end
	end
	if not (type(entry.verifiedAt) == "string" and string.match(entry.verifiedAt, DATE_PATTERN) ~= nil) then
		error(`{label}: verifiedAt must be YYYY-MM-DD`)
	end
end

-- Kill banners (2026-10-16): the 6 kill sound sheets (one per kill set of Art/KillStyle) and the VFX Studio library
-- textures, checked on their own below.
local KILL_SOUND_PREFIX = "sfx.kill."
local KILL_IMAGE_PREFIX = "img.kill."

-- Match HUD M6 / M7 (2026-10-17): the match screens' sounds of the M3 pack, checked on their own below.
local MATCH_SOUND_KEYS = { "match.splat", "match.knockedOut", "match.whoosh" }
-- MATCH FOUND (2026-10-25, round 2 of the match flow): the show's own 6 sounds (its whoosh is match.whoosh).
local FOUND_SOUND_KEYS = {
	"match.found.charge",
	"match.found.impact",
	"match.found.letters",
	"match.found.lettersSolo",
	"match.found.chime",
	"match.found.vs",
	-- The map vote (2026-10-25, round 3 of the match flow): its own 11 sounds (its press is ui.click, its whoosh
	-- match.whoosh).
	"match.vote.open",
	"match.vote.card",
	"match.vote.tick",
	"match.vote.tickUrgent",
	"match.vote.toss",
	"match.vote.land",
	"match.vote.landMine",
	"match.vote.stamp",
	"match.vote.roulette",
	"match.vote.fanfare",
	"match.vote.burst",
	-- The new short level-up (2026-10-25): its tone and jingle (its pop is ui.pop).
	"grip.levelUp.tone",
	"grip.levelUp.jingle",
	-- Round 1 of the match screens (2026-10-26): the intro's 5 cues and the countdown's slam.
	"match.intro.slam",
	"match.intro.whoosh",
	"match.intro.vs",
	"match.intro.cardPop",
	"match.intro.murmur",
	"match.count.slam",
	-- End screens round A (2026-10-26): its 13 renders.
	"match.end.finalHit",
	"match.end.slowmo",
	"match.end.letterPop",
	"match.end.titleBoom",
	"match.end.victory",
	"match.end.cheer",
	"match.end.defeat",
	"match.end.deflate",
	"match.end.aww",
	"match.end.jellyWipe",
	"match.end.coinTick",
	"match.end.gripFill",
	"match.end.streak",
	-- End screens round B1 (2026-10-26): the podium's 3 renders.
	"match.end.poseHit",
	"match.end.mvpSlam",
	"match.end.crownDrop",
	-- The squish medals (2026-10-26): the chime (hud-lib.js claim()).
	"match.medal.claim",
	-- The fancier box reveal (2026-10-26): its 11 renders.
	"box.ux.rattle1",
	"box.ux.rattle2",
	"box.ux.rattle3",
	"box.ux.rise",
	"box.ux.unboxCommon",
	"box.ux.unboxUncommon",
	"box.ux.unboxEpic",
	"box.ux.unboxExclusive",
	"box.ux.letterLow",
	"box.ux.letterHigh",
	"box.ux.stamp",
}

-- Diego's FULL FINAL lobby (2026-10-30): the portal trip's 7 cues and the practice island's 8, checked on their own below.
local LOBBY_SOUND_KEYS = {
	"portal.start",
	"portal.windup",
	"portal.suck",
	"portal.poof",
	"portal.spit",
	"portal.land",
	"portal.chime",
	"practice.squish",
	"practice.squishBig",
	"practice.ding",
	"practice.combo2",
	"practice.combo3",
	"practice.combo4",
	"practice.combo5",
	"practice.fanfare",
}

return function(t: Context)
	local expect = t.expect
	local AssetTable = t.requireShared("AssetTable")

	local function soundSlots(): { any }
		local found = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" then
				table.insert(found, slot)
			end
		end
		return found
	end

	t.test("the sound key set is the 37 of §18.6, spec phase 5's 10, the 16 inspect ones, feature 1's 5 and the 2026-10-15 overhaul's 2", function()
		local keys = {}
		local seen: { [string]: boolean } = {}
		for _, slot in soundSlots() do
			expect.falsy(seen[slot.key])
			seen[slot.key] = true
			-- The knead's wax sounds (spec phase2-squeeze §3.10) are checked on their own (WAX_KEYS, below), and so
			-- are UI FINAL R2's 2 (R2_SOUND_KEYS, below).
			if
				string.sub(slot.key, 1, #WAX_PREFIX) ~= WAX_PREFIX
				and not table.find(R2_SOUND_KEYS, slot.key)
				and string.sub(slot.key, 1, #KILL_SOUND_PREFIX) ~= KILL_SOUND_PREFIX -- kill banners: below
				and not table.find(MATCH_SOUND_KEYS, slot.key) -- Match HUD M6 / M7: below
				and not table.find(FOUND_SOUND_KEYS, slot.key) -- MATCH FOUND: below
				and not table.find(LOBBY_SOUND_KEYS, slot.key) -- FULL FINAL lobby: below
			then
				table.insert(keys, slot.key)
			end
		end
		expect.equal(#keys, 70)
		expect.deepEqual(sorted(keys), sorted(SOUND_KEYS))
	end)

	-- Match HUD M6 / M7 (2026-10-17): the M3 pack's 3 sounds the match screens play, once each, PENDING until the owner's
	-- upload (a look-alike plays meanwhile), 2D.
	t.test("Match HUD M6 / M7's 3 sound keys: match.splat, match.knockedOut, match.whoosh, once each, 2D", function()
		for _, key in MATCH_SOUND_KEYS do
			local found = 0
			for _, slot in soundSlots() do
				if slot.key == key then
					found += 1
					expect.equal(slot.spatial, false)
				end
			end
			expect.equal(found, 1)
		end
	end)

	-- MATCH FOUND (2026-10-25): the show's 6 sounds, once each, UI, 2D, each note naming its file; all uploaded
	-- 2026-10-26 (a look-alike still plays for a missing id, Config.UI.MatchFound.sounds).
	t.test("Made sound keys (found, vote, level-up, box reveal): once each, UI, 2D, naming a file, uploaded", function()
		for _, key in FOUND_SOUND_KEYS do
			local found = 0
			for _, slot in soundSlots() do
				if slot.key == key then
					found += 1
					expect.equal(slot.group, "UI")
					expect.equal(slot.spatial, false)
					expect.truthy(string.find(slot.notes, ".wav'", 1, true) ~= nil)
					expectApproved(expect, key, slot)
				end
			end
			expect.equal(found, 1)
		end
	end)

	-- FULL FINAL lobby (2026-10-30): the owner's picks, once each, SFX, 2D, uploaded, each note naming its file; the
	-- ElevenLabs takes (.mp3) carry their own licence.
	t.test("FULL FINAL lobby's 15 sound keys: once each, SFX, 2D, naming a file, uploaded", function()
		for _, key in LOBBY_SOUND_KEYS do
			local found = 0
			for _, slot in soundSlots() do
				if slot.key == key then
					found += 1
					expect.equal(slot.group, "SFX")
					expect.equal(slot.spatial, false)
					expect.truthy(string.find(slot.notes, "file 'lobby_", 1, true) ~= nil)
					expectApproved(expect, key, slot)
					local eleven = string.find(slot.notes, ".mp3'", 1, true) ~= nil
					expect.equal(string.find(slot.license, "ElevenLabs", 1, true) ~= nil, eleven)
				end
			end
			expect.equal(found, 1)
		end
	end)

	-- UI FINAL R2 (plan work/ui/PLAN.md §3 pack 2): ui.pop and ui.levelTone are sound slots, each once.
	t.test("UI FINAL R2's 2 sound keys: ui.pop and ui.levelTone, once each", function()
		for _, key in R2_SOUND_KEYS do
			local count = 0
			for _, slot in soundSlots() do
				if slot.key == key then
					count += 1
				end
			end
			expect.equal(count, 1)
		end
	end)

	-- Feature 1 (2026-10-11; uploaded 2026-10-12): the hand sounds 2D, the catch's 3D at the catch for the other
	-- duelist; each note names its file ('sfx.charge - loop.wav' ...).
	t.test("feature 1's sounds: SFX, each note naming its file", function()
		local spatial = {
			["sfx.chargeLoop"] = false,
			["sfx.chargeFull"] = false,
			["sfx.catch"] = true,
			["sfx.crushSqueak"] = true,
			["sfx.crushBurst"] = true,
		}
		local found = 0
		for _, slot in soundSlots() do
			local want = spatial[slot.key]
			if want ~= nil then
				found += 1
				expect.equal(slot.group, "SFX")
				expect.equal(slot.spatial, want)
				expect.truthy(string.find(slot.notes, ".wav'", 1, true) ~= nil)
			end
		end
		expect.equal(found, 5)
	end)

	-- Final polish 2026-10-11: the toy is in your hands, so its inspect sounds are 2D SFX, required (not optional).
	t.test("the Inspect showcase slots are 2D SFX, required, each naming its design line", function()
		for _, slot in soundSlots() do
			if string.sub(slot.key, 1, 12) == "sfx.inspect." then
				expect.equal(slot.group, "SFX")
				expect.equal(slot.spatial, false)
				expect.equal(slot.optional, nil)
				expect.truthy(string.find(slot.notes, "design ", 1, true) ~= nil)
			end
		end
	end)

	-- Spec phase2-squeeze §3.10: the knead's 15 wax sounds, PENDING until the user uploads the rendered files; 2D, volume 1
	-- (their levels are Config.Audio.wax), not optional (the picker never lists them), each note names its file.
	t.test("the knead's wax sounds: 4 sheets, 4 haze and 4 body loops, 2 thumps and the re-wax sparkle", function()
		local found: { string } = {}
		for _, slot in soundSlots() do
			if string.sub(slot.key, 1, #WAX_PREFIX) == WAX_PREFIX then
				table.insert(found, slot.key)
				expect.equal(slot.spatial, false)
				expect.equal(slot.optional, nil)
				expect.truthy(string.find(slot.notes, ".wav", 1, true) ~= nil)
				if slot.id == nil then
					expect.equal(slot.volume, 1)
				end
			end
		end
		expect.deepEqual(sorted(found), sorted(WAX_KEYS))
	end)

	-- UI FINAL R1 (plan work/ui/PLAN.md §3): the image keys, the existing 18 and the design's 15 pictures (rendered in
	-- R0, uploaded by the user; nil until then). UI FINAL R2: pack 2's 70 (§3: rendered in R0b, ids in R10b).
	t.test("the image key set: the existing 18, the design's 15 new pictures and pack 2's 70", function()
		local keys = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "image" and string.sub(slot.key, 1, #KILL_IMAGE_PREFIX) ~= KILL_IMAGE_PREFIX then
				table.insert(keys, slot.key)
			end
		end
		expect.deepEqual(
			sorted(keys),
			sorted({
				"img.coin",
				"img.rarity.common",
				"img.rarity.uncommon",
				"img.rarity.epic",
				"img.rarity.exclusive",
				"img.nav.squishies",
				"img.nav.boxes",
				"img.nav.shop",
				"img.nav.quests",
				"img.nav.daily",
				"img.nav.duel",
				"img.nav.settings",
				"img.nav.highway", -- access2: the HIGHWAY stand-in (id nil)
				"img.icon.change",
				"img.icon.clock",
				"img.icon.upgrade",
				"img.icon.inspect",
				"img.icon.close",
				"img.icon.check",
				"img.icon.lock",
				"img.icon.star",
				"img.icon.bolt",
				"img.icon.flame",
				"img.icon.gift",
				"img.icon.sound",
				"img.icon.squeeze",
				"img.icon.match",
				"img.box.sweet",
				"img.box.treat",
				"img.fx.rays",
				"img.fx.raysDetail",
				"img.fx.raysReveal",
				"img.fx.dots",
				"img.fx.glow",
				"img.fx.spark",
				"img.squishy.kitty_bread",
				"img.squishy.toast",
				"img.squishy.banana",
				"img.squishy.butter",
				"img.squishy.chocolate",
				"img.squishy.bird",
				"img.squishy.donut",
				"img.squishy.dragon",
				"img.squishy.boba_bear",
				"img.squishy.pancake_pup",
				"img.squishy.mochi_fox",
				"img.squishy.strawberry_frog",
				"img.squishy.cloud_bunny",
				"img.squishy.cupcake_axolotl",
				"img.squishy.kitty_bread.white",
				"img.squishy.toast.white",
				"img.squishy.banana.white",
				"img.squishy.butter.white",
				"img.squishy.chocolate.white",
				"img.squishy.bird.white",
				"img.squishy.donut.white",
				"img.squishy.dragon.white",
				"img.squishy.boba_bear.white",
				"img.squishy.pancake_pup.white",
				"img.squishy.mochi_fox.white",
				"img.squishy.strawberry_frog.white",
				"img.squishy.cloud_bunny.white",
				"img.squishy.cupcake_axolotl.white",
				"img.nav.squishies.white",
				"img.nav.boxes.white",
				"img.nav.shop.white",
				"img.nav.quests.white",
				"img.nav.daily.white",
				"img.nav.duel.white",
				"img.nav.settings.white",
				"img.nav.highway.white",
				"img.coin.white",
				"img.fx.radial.coinGlow",
				"img.fx.radial.scrimWindow",
				"img.fx.radial.plateCommon",
				"img.fx.radial.plateUncommon",
				"img.fx.radial.plateEpic",
				"img.fx.radial.plateExclusive",
				"img.fx.radial.stageCommon",
				"img.fx.radial.stageUncommon",
				"img.fx.radial.stageEpic",
				"img.fx.radial.stageExclusive",
				"img.fx.radial.congrats",
				"img.fx.radial.congratsDisc",
				"img.fx.radial.revealScrim",
				"img.fx.radial.revealTintCommon",
				"img.fx.radial.revealTintUncommon",
				"img.fx.radial.revealTintEpic",
				"img.fx.radial.revealTintExclusive",
				"img.fx.radial.revealFlash",
				"img.fx.radial.medallion",
				"img.fx.shadowWindow",
				"img.fx.shadowCta",
				"img.fx.raysCoin",
				"img.icon.gem",
				"img.fx.raysCongrats",
				"img.fx.beam",
				"img.fx.blob",
				"img.fx.halfRing",
				-- Match HUD M7 (2026-10-17): the M3 pack's card and vignette pictures.
				"img.fx.raysCard",
				"img.fx.dotsCard",
				"img.icon.grip",
				"img.fx.radial.matchVignette",
				-- Pens3 phase 9: the 7 food pictures (the BUY FOOD cards; nil until the owner uploads them).
				"img.food.candy_drop",
				"img.food.butter_bun",
				"img.food.boba_pearl_pop",
				"img.food.frosty_scoop",
				"img.food.lava_truffle",
				"img.food.prism_tart",
				"img.food.halo_puff",
				-- The shop = Diego's design: his pass and pack pictures and the Robux mark (nil until uploaded).
				"img.pass.coins2",
				"img.pass.grip2",
				"img.pass.lucky",
				"img.pass.fast",
				"img.pack.1000",
				"img.pack.3300",
				"img.pack.9600",
				"img.pack.32500",
				"img.icon.robux",
				-- Highway v2 (2026-10-23): Claude Design's floor checker.
				"img.highway.floorChecker",
				-- Duel HUD (2026-10-24): the 27 pictures of "Squishy Duels Duel HUD.dc.html".
				"img.duel.btn.catchDesk",
				"img.duel.btn.ultDesk",
				"img.duel.btn.dashDesk",
				"img.duel.btn.catchPhone",
				"img.duel.btn.ultPhone",
				"img.duel.btn.dashPhone",
				"img.duel.glow.ultDesk",
				"img.duel.glow.ultPhone",
				"img.duel.glow.catchDesk",
				"img.duel.glow.catchPhone",
				"img.duel.rays",
				"img.duel.icon.catch",
				"img.duel.icon.dash",
				"img.duel.icon.ult.Dragon",
				"img.duel.icon.ult.Birdie",
				"img.duel.icon.ult.CloudBunny",
				"img.duel.icon.ult.CupcakeAxolotl",
				"img.duel.icon.ult.Donut",
				"img.duel.plate.scoreYouDesk",
				"img.duel.plate.scoreFoeDesk",
				"img.duel.plate.timerDesk",
				"img.duel.plate.scoreYouPhone",
				"img.duel.plate.scoreFoePhone",
				"img.duel.plate.timerPhone",
				"img.duel.avatar.you",
				"img.duel.avatar.foe",
				"img.duel.star",
				-- Mode select (2026-10-24): the 17 pictures of "Squishy Duels LOBBY HUD.dc.html"'s mode select.
				"img.mode.art.duel",
				"img.mode.art.tdm",
				"img.mode.art.ffa",
				"img.mode.artMask.duel",
				"img.mode.artMask.tdm",
				"img.mode.artMask.ffa",
				"img.mode.bg",
				"img.mode.vignette",
				"img.mode.rays",
				"img.mode.raysCard",
				"img.mode.glow",
				"img.mode.shard",
				"img.mode.bubble",
				"img.mode.cardGlow",
				"img.mode.cardShadow",
				"img.mode.play",
				"img.mode.playMask",
				-- MATCH FOUND (2026-10-25, round 2 of the match flow): the show's 9 pictures.
				"img.mf.backdrop",
				"img.mf.glow",
				"img.mf.rays",
				"img.mf.orb",
				"img.mf.flash",
				"img.mf.banner",
				"img.mf.tailL",
				"img.mf.tailR",
				"img.mf.vs",
				-- The map vote (2026-10-25, round 3 of the match flow): each map's card and board, the heads, the tails,
				-- the glow and the timer ring.
				"img.vote.card.ToyBoxClash",
				"img.vote.card.SprinkleFactory",
				"img.vote.card.BubbleBathBay",
				"img.vote.card.JellyArcade",
				"img.vote.card.SundaePlaza",
				"img.vote.card.PillowFortPark",
				"img.vote.board.ToyBoxClash",
				"img.vote.board.SprinkleFactory",
				"img.vote.board.BubbleBathBay",
				"img.vote.board.JellyArcade",
				"img.vote.board.SundaePlaza",
				"img.vote.board.PillowFortPark",
				"img.vote.headTeam",
				"img.vote.headSolo",
				"img.vote.tailRed",
				"img.vote.tailBlue",
				"img.vote.tailPinkL",
				"img.vote.tailPinkR",
				"img.vote.glow",
				"img.vote.ring",
				-- The new short level-up (2026-10-25): the GRIP badge's disc, its stripes and its ring.
				"img.lv.badge",
				"img.lv.spin",
				"img.lv.ring",
				-- The fancier box reveal (2026-10-26): the rarity rays and the halo's two layers.
				"img.box.rays",
				"img.box.haloGlow",
				"img.box.haloCore",
				-- Round 1 of the match screens (2026-10-26): the squishies' banner tiles, the glow and the count's rays.
				"img.intro.pattern.kitty_bread",
				"img.intro.pattern.donut",
				"img.intro.pattern.bird",
				"img.intro.pattern.boba_bear",
				"img.intro.pattern.toast",
				"img.intro.pattern.banana",
				"img.intro.pattern.butter",
				"img.intro.pattern.chocolate",
				"img.intro.pattern.dragon",
				"img.intro.pattern.mochi_fox",
				"img.intro.pattern.strawberry_frog",
				"img.intro.pattern.pancake_pup",
				"img.intro.pattern.cloud_bunny",
				"img.intro.pattern.cupcake_axolotl",
				"img.intro.glow",
				"img.intro.countRays",
				-- End screens round A (2026-10-26): the two sunbursts.
				"img.end.sun18",
				"img.end.sun14",
				-- End screens round B2 (2026-10-26): the podium party's particles.
				"img.podium.star",
				"img.podium.heart",
				"img.podium.chip",
				"img.podium.petal",
				"img.podium.sprinkle",
				-- The squish medals (2026-10-26): the gold face and its rays.
				"img.medal.face",
				"img.medal.rays",
				-- The physics upgrade's kit (2026-10-28, docs/squishy-fx-spec/kit) and the lobby footprint (extra 6).
				"img.kit.puff",
				"img.kit.star",
				"img.kit.sparkle",
				"img.kit.pow",
				"img.kit.jelly",
				"img.kit.confetti",
				"img.kit.ring",
				"img.kit.speedline",
				"img.kit.footprint",
			})
		)
	end)

	t.test("a PENDING slot carries no metadata; an approved one carries all of it", function()
		for _, slot in AssetTable.all() do
			if slot.id == nil then
				expect.equal(slot.source, nil)
				expect.equal(slot.license, nil)
				expect.equal(slot.verifiedAt, nil)
				expect.equal(slot.variants, nil)
			elseif slot.kind == "sound" then
				expectApproved(expect, slot.key, slot)
				local ids: { [number]: boolean } = { [slot.id] = true }
				for index, variant in slot.variants or {} do
					expectApproved(expect, `{slot.key} variant {index}`, variant)
					if ids[variant.id] then
						error(`{slot.key}: id repeated in its variants`)
					end
					ids[variant.id] = true
				end
			else
				expect.truthy(isPositiveInteger(slot.id))
				expectProvenance(`{slot.kind} {slot.key}`, slot)
			end
		end
	end)

	t.test("acceptance 10: every slot of any kind with an id carries source, licence and verifiedAt", function()
		local checked = 0
		for _, slot in AssetTable.all() do
			expect.truthy(ASSET_KINDS[slot.kind] == true)
			checked += 1
			if slot.id ~= nil then
				expectProvenance(`{slot.kind} {slot.key}`, slot)
				for index, variant in slot.variants or {} do
					expectProvenance(`{slot.key} variant {index}`, variant)
				end
			end
		end
		expect.truthy(checked > 0)
	end)

	-- Animation and image ids are nil today, so the audit above never reaches their approved branch; this proves that
	-- branch on a fake entry of each kind (a fake, tiny id, as the approved-slot check below uses; never written to
	-- AssetTable) and on broken copies of it.
	t.test("the any-kind audit accepts a full entry and rejects each broken field", function()
		for _, kind in { "animation", "image", "sound" } do
			expect.truthy(ASSET_KINDS[kind] == true)
			local good = {
				kind = kind,
				id = 11,
				source = "Published by the DIJAY Studios group (Creator Hub)",
				license = "Group-owned asset",
				verifiedAt = "2026-10-07",
			}
			expectProvenance(kind, good)
			local broken: { { any } } = {
				{ "id", nil },
				{ "id", 0 },
				{ "id", 2.5 },
				{ "id", "11" },
				{ "source", nil },
				{ "source", "" },
				{ "license", nil },
				{ "license", "" },
				{ "verifiedAt", nil },
				{ "verifiedAt", "07/10/2026" },
				{ "verifiedAt", "2026-10-7" },
			}
			for _, case in broken do
				local entry = table.clone(good) :: any
				entry[case[1]] = case[2]
				expect.throws(function()
					expectProvenance(`broken {kind} {case[1]}`, entry)
				end)
			end
		end
	end)

	-- The check above runs its approved branch on the uploaded sounds; this also proves that branch on an entry in the
	-- §18.7 "Approved slot format" (a fake, tiny id) and on broken copies.
	t.test("the approved-slot check accepts the §18.7 format and rejects each broken field", function()
		local good = {
			id = 7,
			volume = 0.8,
			source = "Creator Store audio 'Soft squish' by Someone (search: soft+squish)",
			license = "Free Creator Store audio; GetProductInfo AssetTypeId 3, IsPublicDomain true",
			verifiedAt = "2026-10-06",
		}
		expectApproved(expect, "good", good)
		local broken: { { any } } = {
			{ "id", 0 },
			{ "id", -3 },
			{ "id", 1.5 },
			{ "id", "7" },
			{ "volume", 0 },
			{ "volume", 2.5 },
			{ "source", "" },
			{ "license", nil },
			{ "verifiedAt", "6/10/2026" },
			{ "verifiedAt", "2026-10-6" },
			{ "verifiedAt", nil },
		}
		for _, case in broken do
			local entry = table.clone(good) :: any
			entry[case[1]] = case[2]
			expect.throws(function()
				expectApproved(expect, `broken {case[1]}`, entry)
			end)
		end
	end)

	t.test("music and ambience are 2D; every sound slot has a group, a volume and notes", function()
		for _, slot in soundSlots() do
			expect.truthy(slot.group == "Music" or slot.group == "SFX" or slot.group == "UI" or slot.group == "Ambient")
			expect.truthy(type(slot.volume) == "number" and slot.volume > 0 and slot.volume <= 2)
			expect.equal(type(slot.spatial), "boolean")
			expect.truthy(type(slot.notes) == "string" and slot.notes ~= "")
			if slot.group == "Music" or slot.group == "Ambient" then
				expect.equal(slot.spatial, false)
			end
		end
	end)

	t.test("the feel pass slots: groups, 3D or 2D, optional (§18.6)", function()
		local byKey: { [string]: any } = {}
		for _, slot in soundSlots() do
			byKey[slot.key] = slot
		end
		expect.equal(byKey["sfx.jellyWobble"].group, "SFX")
		expect.equal(byKey["sfx.jellyWobble"].spatial, true)
		expect.equal(byKey["sfx.pop"].group, "SFX")
		expect.equal(byKey["sfx.pop"].spatial, true)
		expect.equal(byKey["ui.gripUnlock"].group, "UI")
		expect.equal(byKey["ui.gripUnlock"].spatial, false)
		local optionalKeys = {}
		for _, slot in soundSlots() do
			if slot.optional == true then
				table.insert(optionalKeys, slot.key)
			else
				expect.equal(slot.optional, nil)
			end
		end
		expect.deepEqual(sorted(optionalKeys), sorted(OPTIONAL_KEYS))
	end)

	-- Kill banners (2026-10-16): one sound sheet per kill set, 2D SFX, required, each with an approved group upload and its
	-- file named in the notes; every img.kill.* slot holds a VFX Studio library texture with its provenance, except the
	-- v2 emblems (img.kill.emblem.<set> and its .white silhouette, 2026-10-17): the owner's uploads of the game's own
	-- squishy renders, one pair per kill set.
	t.test("kill banners: a sound sheet per kill set and the VFX Studio textures", function()
		local KillStyle = t.requireShared("Art/KillStyle")
		local sheets: { string } = {}
		for _, slot in soundSlots() do
			if string.sub(slot.key, 1, #KILL_SOUND_PREFIX) == KILL_SOUND_PREFIX then
				table.insert(sheets, slot.key)
				expect.equal(slot.group, "SFX")
				expect.equal(slot.spatial, false)
				expect.equal(slot.optional, nil)
				expect.truthy(string.find(slot.notes, ".ogg'", 1, true) ~= nil)
				expectProvenance(slot.key, slot)
			end
		end
		local wanted: { string } = {}
		for _, id in KillStyle.IDS do
			table.insert(wanted, (KillStyle.get(id) :: any).sound)
		end
		expect.deepEqual(sorted(sheets), sorted(wanted))
		local images, emblems = 0, 0
		local EMBLEM_PREFIX = KILL_IMAGE_PREFIX .. "emblem."
		for _, slot in AssetTable.all() do
			if slot.kind == "image" and string.sub(slot.key, 1, #KILL_IMAGE_PREFIX) == KILL_IMAGE_PREFIX then
				expectProvenance(slot.key, slot)
				if string.sub(slot.key, 1, #EMBLEM_PREFIX) == EMBLEM_PREFIX then
					emblems += 1
					expect.truthy(string.find(slot.source, "VillasmilGaming upload", 1, true) ~= nil)
					expect.truthy(string.find(slot.source, ".png'", 1, true) ~= nil)
				else
					images += 1
					expect.truthy(string.find(slot.source, "VFX Studio", 1, true) ~= nil)
				end
			end
		end
		expect.truthy(images >= 20)
		expect.equal(emblems, 2 * #KillStyle.IDS)
		for _, id in KillStyle.IDS do
			local style = KillStyle.get(id) :: any
			expect.truthy(AssetTable.image(style.emblem) ~= nil)
			expect.truthy(AssetTable.image(style.emblemWhite) ~= nil)
		end
	end)

	t.test("contentIdFor accepts positive integers only", function()
		expect.equal(AssetTable.contentIdFor(1), CONTENT_PREFIX .. "1")
		expect.equal(AssetTable.contentIdFor(42), CONTENT_PREFIX .. "42")
		-- A long id keeps every digit (no exponent).
		expect.equal(AssetTable.contentIdFor(2 ^ 40), CONTENT_PREFIX .. string.format("%d", 2 ^ 40))
		for _, bad in { 0, -1, -42, 0.5, 42.25, 0 / 0, math.huge, -math.huge, 2 ^ 54 } do
			expect.equal(AssetTable.contentIdFor(bad), nil)
		end
		expect.equal(AssetTable.contentIdFor("42" :: any), nil)
		expect.equal(AssetTable.contentIdFor(nil :: any), nil)
	end)

	t.test("soundChoices: the slot's id, then each variant; nothing while PENDING", function()
		for _, slot in soundSlots() do
			local choices = AssetTable.soundChoices(slot.key)
			expect.truthy(table.isfrozen(choices))
			if slot.id == nil then
				expect.equal(#choices, 0)
				expect.equal(AssetTable.sound(slot.key), nil)
			else
				local variants = slot.variants or {}
				expect.equal(#choices, 1 + #variants)
				expect.equal(choices[1].id, slot.id)
				expect.equal(choices[1].content, AssetTable.sound(slot.key))
				expect.equal(choices[1].volume, slot.volume)
				for index, variant in variants do
					expect.deepEqual(choices[index + 1], {
						id = variant.id,
						content = AssetTable.contentIdFor(variant.id),
						volume = variant.volume,
					})
				end
			end
		end
		expect.equal(#AssetTable.soundChoices("sfx.notAKey"), 0) -- unknown: warned once, nothing to play
	end)

	t.test("the table is frozen all the way down", function()
		expect.truthy(table.isfrozen(AssetTable))
		expect.truthy(table.isfrozen(AssetTable.all()))
		for _, slot in AssetTable.all() do
			expect.truthy(table.isfrozen(slot))
			if slot.variants then
				expect.truthy(table.isfrozen(slot.variants))
				for _, variant in slot.variants do
					expect.truthy(table.isfrozen(variant))
				end
			end
		end
	end)
end
