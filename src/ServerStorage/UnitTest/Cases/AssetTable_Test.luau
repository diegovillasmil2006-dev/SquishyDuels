--!strict
-- AssetTable_Test: unit tests for ReplicatedStorage.Shared.AssetTable. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §14, §18.6, §18.7, §18.10 L1):
--   * the sound key set is exactly the 37 of §18.6 (the 34 of §14.2 plus ui.gripUnlock, sfx.jellyWobble, sfx.pop),
--     the 10 of spec phase 5 (the dash and the four Epic ultimates), the 16 of the Inspect showcases (final polish
--     2026-10-11: the design's own inspect one-shots, 2D SFX) and the 5 of feature 1 (2026-10-11: the charge throw and
--     the catch, each note naming its file), 68 in all;
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

	t.test("the sound key set is the 37 of §18.6, spec phase 5's 10, the 16 inspect ones and feature 1's 5", function()
		local keys = {}
		local seen: { [string]: boolean } = {}
		for _, slot in soundSlots() do
			expect.falsy(seen[slot.key])
			seen[slot.key] = true
			-- The knead's wax sounds (spec phase2-squeeze §3.10) are checked on their own (WAX_KEYS, below).
			if string.sub(slot.key, 1, #WAX_PREFIX) ~= WAX_PREFIX then
				table.insert(keys, slot.key)
			end
		end
		expect.equal(#keys, 68)
		expect.deepEqual(sorted(keys), sorted(SOUND_KEYS))
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
