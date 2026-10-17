--!strict
-- Config: every tunable game value, merged from the section modules and deep-frozen (DESIGN §2.2). Shared.
-- Read values as Config.<Section>.<key>. Requiring this module has no side effects beyond freezing the section
-- tables in place (no instances, connections or yields).
--
-- Config.validate(deps?): {string} returns human-readable problems (an empty list = valid). It checks Config-internal
-- rules and the cross-references with sibling modules of Shared: Remotes and Strings always (Part 1); Rarity,
-- Catalog, Art/SquishyBlueprints, Boxes, Pricing, QuestDefs and World/WorldLayout only once they exist (checks that
-- need a missing module are skipped without error). Sibling modules are required lazily inside validate(), so they
-- may require Config themselves. The throw power budget (§5.8) is checked by the server bootstrap with server
-- Logic/PowerBudget. `deps.WorldLayout` replaces the WorldLayout module (unit tests pass a deliberately broken copy;
-- WorldLayout is frozen on load); `deps.Catalog` replaces the Catalog module (unit tests pass a broken one);
-- `deps.QuestDefs` replaces the QuestDefs module (unit tests pass broken quest definitions).
-- Grip rules (§17.9, Part 3): G1 levels, G2 pads (the Foam Mats row), G5 caps and timers, G8 world (Config.Grip with
-- WorldLayout). G10 (giant-pad animation) and G8's giant-pad and gate rules are gone with the giant pads (Phase 6).
-- Grip rules (Part 5): G3 squeeze ceiling (a squeeze count since spec 2026-10-12 §12),
-- G6 Strings names (every rank and pad key has its grip.rank / grip.pad text); plus the Part 5
-- values of Data (size budget, timer skew), UI.Grip and the Grip nameplate and toast settings. G9 is gone with
-- slow training (build plan Phase 6); its pad margins are Config.Squeeze's now, checked there. G4 (trainer) and G6's
-- wiring half (the "trainer" Coin reason, the TrainerUpgrade rate) are gone with the trainers (Phase 6).
-- Grip rules (Part 7): G7 Robux allowlist and G7b bundles-off-while-Grip, both through the pure
-- Config.robuxProblems(monetization,
-- grip, resolveText) (also called by Config_Test with fake tables). Part 7 also checks: QuestDefs (kind, category,
-- counts, positive integer goal/reward variants, the textPair's .one/.many texts, the daily templates cover squeeze,
-- duel and practice, starter ids), Onboarding.skipStepId (camelCase, not a
-- step id), UI.Boxes and UI.Shop; and, now that Boxes, Pricing and QuestDefs exist, the box/price checks below run.
-- Part 6 (Inspect): Config.Inspect's drag speed filter, the R2 / L2 zoom deadzone (in [0, 1)), the squeeze preview dots
-- (positive, dotSpeedMinPx <= dotSpeedMaxPx) and the Collection displays (positive check period, sway period and
-- nameplate, non-negative margin and sway).
-- Part 8 (nameplate polish, §17.11): Config.Grip.Nameplate.fadeStuds in (0, maxDistance), checkSeconds > 0,
-- ownHideStuds >= 0.
-- Duel rules (Part 4, §5.2-§5.9): phase timings, matchmaking priorities, the Preparing stream wait inside its
-- phase, movement guard, ability telegraph/interval/lane height, and (with WorldLayout) that every in-band throw
-- reaches the far end of the court.
-- Feel pass rules (§18.9, F1-F11; each has a planted bad value in Config_Test): F1 squeeze particle total, F2
-- elimination particles and confetti parts, F3 FOV punch, F4 hit-stop, F5 splat parts, F6 mat pulse timing, F7 jelly
-- ripple (wave stability with the WorldLayout cover and backstop sizes, springs, path B amounts, the whole-piece
-- jiggle, rings, skin mode), F8
-- audio (pitch range, countdown pitches, caps, and with AssetTable: every toastSounds and perKeyCap key is a sound
-- slot), F9 UI juice timings and the 3 Hz spring rule, F10 editable meshes per client, F11 the splat red guard.
-- Squishy overhaul (spec 2026-10-09 §3.2, §6): every Catalog blueprint has a `motion` row, each row inside the §6
-- ranges with a known feel and flight style; the SquishRig block (Config.Anim.rig) <= 3 Hz (flaps 2.5 Hz, spins 2
-- turns a second), its face toggles and kicks within their caps; the detail budgets fit; Inspect's widen margin.
-- First person (spec 2026-10-10 §4.1): Config.FirstPerson's ranges, every spring in it <= 3 Hz, the idle drift <= 3 Hz
-- and the squeeze axis (step 2's hand, bob and per-toy offsets went on 2026-10-11). Design fidelity (spec 2026-10-11
-- §3, §5, §6): the 3D Lab viewmodel values (arm parts, colours, outline, held toy, pop-in, squeeze, focus, throw extras,
-- Dragon charge), Inspect's squeeze axis, and Grip.squeezeAlertPerHour in 1..maxSqueezesPerHour.
-- Big-number progression (spec 2026-10-12, Phase 1): G1 over 100 levels (the totals rise strictly; a level may cost
-- less than the one before), G3 as a squeeze count, G5 covering 4 × the top pen squeeze, the Capsule block (tiers fit
-- maxLevel, intervals fall, Grip gates rise, growth > 1, slot prices rise from a free slot 1, the biggest price fits
-- maxCoins), SquishyPower and a Catalog `power` override (whole numbers >= 1), the refund share (Economy.DuplicateRefund,
-- under 100%, its free-box price from a paid box), and "capsule" among the G7 training words. Phase 3: the capsule
-- tick and tap push (CoinsByRarity and the Catalog `squeezeCoins` override are gone: own squeezes pay the squeeze
-- value).
-- Squeeze feel (spec phase2-squeeze §3.11): Config.Knead and Config.Wax have a row for every Config.Anim.rig feel, each
-- share, time and gain in range and every spring <= 3 Hz except jelly's per-vertex knead spring (the design's own 3.59
-- Hz wobble, a documented exception); the crunch rhythm <= 3 presses a second; the wax switch Config.Wax.enabled (user
-- 2026-10-12) is a boolean.
-- Batch 3 (friends, review #6 and #10): Config.Social's pads, rematch window (it outlives the result card), weekly
-- board (a Studio store name ends in "_STUDIO", at most 100 entries a read) and badges (unique keys, an id only once
-- the owners made the badge, known rule kinds, whole thresholds, Catalog squishies and rarities).
-- UI FINAL R1 (the look kit): Config.UI.Sticker's borders, lips, radii, surfaces, bars and toggles are whole px >= 0
-- with alphas in 0..1, and every text role names a TextSize kind with a positive stroke.
-- FFA/TDM v1 (2026-10-15): Config.Match's in-server queue, maps, spawn spots, storm sampling and test wall
-- (Config/ValidateMatch; the wall colour is an Art/Palette token, never a "...Key" field: that reads as a Strings key).
-- UI FINAL R2 (the motion kit; F8 and F9): Config/ValidateUIMotion's checks (its header lists them); Config.UI.Scale's
-- referenceWidth > 0 and a soft text drop's px and alpha.
-- Convention: every string field whose name ends in "Key" (nameKey, textKey, ...) is a Strings path; validate()
-- resolves each one with Strings.resolve, in Config and in the Catalog, Boxes and QuestDefs data.

local Abilities = require(script.Abilities)
local Anim = require(script.Anim)
local Audio = require(script.Audio)
local Combat = require(script.Combat)
local Data = require(script.Data)
local Debug = require(script.Debug)
local Duel = require(script.Duel)
local Economy = require(script.Economy)
local FirstPerson = require(script.FirstPerson)
local Grip = require(script.Grip)
local Inspect = require(script.Inspect)
local Knead = require(script.Knead)
local Match = require(script.Match)
local Monetization = require(script.Monetization)
local Net = require(script.Net)
local Onboarding = require(script.Onboarding)
local Social = require(script.Social)
local Squeeze = require(script.Squeeze)
local UI = require(script.UI)
local Vfx = require(script.Vfx)
local Wax = require(script.Wax)

type Problems = { string }
type KeyRef = { path: string, key: string }
type NumberCheck = (problems: Problems, path: string, value: unknown) -> ()

-- Optional replacements for sibling modules, used by unit tests.
export type ValidateDeps = {
	WorldLayout: any?, -- replaces Shared/World/WorldLayout
	Catalog: any?, -- replaces Shared/Catalog (list, starterId)
	QuestDefs: any?, -- replaces Shared/QuestDefs (list); it is frozen on load, so tests pass a broken fake
}

-- Canonical decisions (DESIGN §0.3, §2.7, §5.9) that Config and the catalog modules must agree on.
local RARITY_ORDER = { "Common", "Uncommon", "Epic", "Exclusive" } -- Rarity.ORDER must match once it exists
local STARTER_ID = "kitty_bread"
local ID_PATTERN = "^[a-z_]+$" -- squishyId, boxId, bundleKey, passKey, ultimateId
local ID_MAX_LENGTH = 24
local STARTER_TASK_PATTERN = "^starter_[a-z]+$"
local STARTER_TASK_PREFIX = "starter_"
local BOX_WEIGHT_TOTAL = 10000
-- QuestDefs (§6.8): the allowed field values; the daily templates must cover every category.
local QUEST_KINDS = { daily = true, starter = true }
local QUEST_CATEGORIES = { "squeeze", "duel", "practice" }
local QUEST_COUNTS = {
	squeeze = true,
	squeezeWith = true,
	duelFinish = true,
	duelWin = true,
	duelWinWith = true,
	hitsWith = true,
	practiceHit = true,
}
-- G7 (§17.9): a coin bundle has exactly these fields; no Robux name may mention the lobby training (capsules too, lobby
-- spec 2026-10-11 §11).
local BUNDLE_FIELDS = { key = true, nameKey = true, productId = true, coins = true, onSale = true }
local ROBUX_BANNED_WORDS = { "grip", "train", "rested", "afk", "idle", "squeeze", "pad", "cushion", "level", "capsule" }
-- Every ability: telegraph >= this, visible to the opponent. §5.9's 0.6 s, lowered by the user's decision of
-- 2026-10-11 so the design's wind-ups pass (design numbers win; ults.js:3-6: 0.35, 0.45, 0.6, 0.5 s).
local MIN_TELEGRAPH_SECONDS = 0.35
local MIN_ABILITY_INTERVAL_SECONDS = 20
-- Spec phase 5: the ability kinds AbilityService runs (Config.Abilities header), and the kinds whose sphere flies above
-- the floor (laneHeightAboveFloor > radius).
local ABILITY_KINDS: { [string]: boolean } = { lane = true, volley = true, roller = true, rain = true, bubble = true }
local FLYING_KINDS: { [string]: boolean } = { lane = true, volley = true, roller = true, bubble = true }
local MAX_VOLLEY_COUNT = 8 -- reading: a fan wider than this is a typo
local ULTIMATE_RARITIES: { [string]: boolean } = { Epic = true, Exclusive = true } -- design: fp.js:576
local BIND_TO_CLOSE_LIMIT_SECONDS = 30 -- Roblox gives BindToClose 30 s
local MAX_HIGHLIGHTS = 255 -- engine cap
local THROW_STATS = { "speed", "radius", "cooldown", "windup", "gravity" }
local AIM_INPUTS = { "Gamepad", "Touch", "KeyboardAndMouse" } -- Enum.PreferredInput item names
local AUDIO_GROUPS = { "Music", "SFX", "UI", "Ambient", "Wax" } -- Wax: spec phase2-squeeze §3.9
local HEX_COLOR_PATTERN = "^#%x%x%x%x%x%x$"
local STATION_ID_PATTERN = "^squeeze_%d%d$" -- §2.7
local MAX_IDLE_KICK_SECONDS = 1200 -- G5: Roblox disconnects idle players after 20 minutes
local MAX_QUEUED_HOLD_SECONDS = 120 -- G5
local MAX_WAVE_COURANT = 0.5 -- F7: the ripple's wave speed × substep / spacing
local SECONDS_PER_HOUR = 3600
local PERCENT = 100
local MAX_PAD_MARGIN = 2 -- Config.Squeeze.padMargin (G9's limit before Phase 6)
local MAX_PAD_HEIGHT_ABOVE = 8 -- Config.Squeeze.heightAbove (G9's limit before Phase 6)
local DATASTORE_VALUE_LIMIT = 4_194_304 -- characters per DataStore value (§3.5)
local MAX_FLICKER_HZ = 3 -- F9: nothing wobbles faster than 3 Hz (§9.12, §18.1 #4)
local MAX_FOV_PUNCH_DEG = 4 -- F3 (§18.4.3)
local MAX_SPLAT_PARTS = 60 -- F5: <= 12 live splats × 5 parts (§18.9)
-- F7: path B and the path A jiggle |x| <= 0.3. Was 0.1 (§18.3.5); raised after the user's test of 2026-10-07 ("too
-- weak, need more animation like 10x"): the whole-piece squash now peaks at about 0.18 (Rush 0.28).
local MAX_RIPPLE_AMOUNT = 0.3
local MAX_JIGGLE_HZ = 2.5 -- F7: the jiggle's omega / 2π (with the dent wave every vertex stays <= 3 Hz, §9.12)
local SKIN_MODES = { "onHit", "always" } -- F7 (§18.3.4)
local COUNTDOWN_PITCHES = 3 -- F8: one pitch each for 3, 2, 1
local FEEL_SLACK = 1e-9 -- F9 / F11: float slack on the limits
-- Squishy overhaul (spec 2026-10-09 §3.2, §6): each blueprint motion row's ranges; flight flaps <= 2.5 Hz and spins
-- <= 2 turns a second (the rest of the rig <= MAX_FLICKER_HZ).
local MOTION_RANGES: { [string]: { number } } =
	{ depth = { 0.55, 0.72 }, widen = { 0.4, 0.85 }, kRel = { 20, 60 }, cRel = { 6, 10 } }
local MOTION_FIELDS = { "depth", "widen", "kRel", "cRel" }
local MAX_FLAP_HZ = 2.5
local MAX_ROLL_DEG_PER_SECOND = 720
-- A network stall delivers an honest client's queued SqueezeRequests at once; the remote burst
-- holds this many seconds of the paid-squeeze cap, so they are never violations (Config.Net.Remotes.SqueezeRequest).
local SQUEEZE_BACKLOG_SECONDS = 5
-- F7: face sizes when WorldLayout is not available (§18.3.1: a wall 6 × 8 × 2.5, a block 6 × 8 × 6; §18.3.7: the
-- practice backstop 2 × 12 × 34).
local DEFAULT_WALL_SIZE = Vector3.new(6, 8, 2.5)
local DEFAULT_BLOCK_SIZE = Vector3.new(6, 8, 6)
local DEFAULT_BACKSTOP_SIZE = Vector3.new(2, 12, 34)
-- Batch 3: GetSortedAsync reads at most 100 entries a page; the rule kinds Logic/BadgeRules knows; a week in seconds.
local MAX_SORTED_PAGE = 100
local BADGE_RULES: { [string]: boolean } = {
	joined = true,
	stat = true,
	gripLevel = true,
	ownRarityAll = true,
	own = true,
	flag = true,
}
local BADGE_KEY_PATTERN = "^[a-z0-9_]+$"
local SECONDS_PER_WEEK = 7 * 86400
local STUDIO_STORE_SUFFIX = "_STUDIO"

local Config = {
	Abilities = Abilities,
	Anim = Anim,
	Audio = Audio,
	Combat = Combat,
	Data = Data,
	Debug = Debug,
	Duel = Duel,
	Economy = Economy,
	FirstPerson = FirstPerson,
	Grip = Grip,
	Inspect = Inspect,
	Knead = Knead,
	Match = Match,
	Monetization = Monetization,
	Net = Net,
	Onboarding = Onboarding,
	Social = Social,
	Squeeze = Squeeze,
	UI = UI,
	Vfx = Vfx,
	Wax = Wax,
}

-- Private: freezing -------------------------------------------------------------------------------------------------

-- Freezes every table reachable from `value` (keys and values), in place. Non-table values are left alone.
local function deepFreeze(value: any, seen: { [any]: boolean })
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	for key, child in value do
		deepFreeze(key, seen)
		deepFreeze(child, seen)
	end
	if not table.isfrozen(value) then
		table.freeze(value)
	end
end

-- Private: check helpers --------------------------------------------------------------------------------------------

local function isNumber(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function isInteger(value: unknown): boolean
	return isNumber(value) and math.floor(value :: number) == value
end

local function show(value: unknown): string
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

local function add(problems: Problems, message: string)
	table.insert(problems, message)
end

local function expect(problems: Problems, ok: boolean, message: string)
	if not ok then
		add(problems, message)
	end
end

local function expectPositive(problems: Problems, path: string, value: unknown)
	expect(problems, isNumber(value) and (value :: number) > 0, `{path} must be a number > 0 (got {show(value)})`)
end

local function expectNonNegative(problems: Problems, path: string, value: unknown)
	expect(problems, isNumber(value) and (value :: number) >= 0, `{path} must be a number >= 0 (got {show(value)})`)
end

local function expectCount(problems: Problems, path: string, value: unknown, min: number)
	expect(
		problems,
		isInteger(value) and (value :: number) >= min,
		`{path} must be an integer >= {min} (got {show(value)})`
	)
end

local function expectBetween(problems: Problems, path: string, value: unknown, min: number, max: number)
	expect(
		problems,
		isNumber(value) and (value :: number) >= min and (value :: number) <= max,
		`{path} must be a number in [{min}, {max}] (got {show(value)})`
	)
end

local function expectBoolean(problems: Problems, path: string, value: unknown)
	expect(problems, type(value) == "boolean", `{path} must be a boolean (got {show(value)})`)
end

local function expectText(problems: Problems, path: string, value: unknown)
	expect(problems, type(value) == "string" and value ~= "", `{path} must be a non-empty string (got {show(value)})`)
end

local function expectId(problems: Problems, path: string, value: unknown)
	expect(
		problems,
		type(value) == "string" and #value <= ID_MAX_LENGTH and string.match(value, ID_PATTERN) ~= nil,
		`{path} must match {ID_PATTERN} with at most {ID_MAX_LENGTH} characters (got {show(value)})`
	)
end

-- A Coin amount: an integer >= 0.
local function expectCoins(problems: Problems, path: string, value: unknown)
	expectCount(problems, path, value, 0)
end

local function eachField(problems: Problems, path: string, tbl: any, fields: { string }, check: NumberCheck)
	for _, field in fields do
		check(problems, `{path}.{field}`, tbl[field])
	end
end

local function keyOrder(a: any, b: any): boolean
	local ta, tb = type(a), type(b)
	if ta == tb and (ta == "number" or ta == "string") then
		return a < b
	end
	return ta < tb
end

local function sortedKeys(tbl: any): { any }
	local keys = {}
	for key in tbl do
		table.insert(keys, key)
	end
	table.sort(keys, keyOrder)
	return keys
end

-- Every string field named "<x>Key" under `value`, in a stable order.
local function collectStringKeys(value: any, path: string, out: { KeyRef }, seen: { [any]: boolean })
	if type(value) ~= "table" or seen[value] then
		return
	end
	seen[value] = true
	for _, key in sortedKeys(value) do
		local child = value[key]
		local childPath = if type(key) == "number" then `{path}[{key}]` else `{path}.{tostring(key)}`
		if type(key) == "string" and type(child) == "string" and string.sub(key, -3) == "Key" then
			table.insert(out, { path = childPath, key = child })
		else
			collectStringKeys(child, childPath, out, seen)
		end
	end
end

-- Requires a module of Shared by its path below Shared ("Catalog", "Art/SquishyBlueprints"). Returns (module, nil)
-- when it loaded, (nil, message) when it exists but failed to load, and (nil, nil) when it does not exist yet.
local function loadSibling(path: string): (any, string?)
	local instance: Instance? = script.Parent
	for name in string.gmatch(path, "[^/]+") do
		instance = if instance then instance:FindFirstChild(name) else nil
	end
	if instance == nil or not instance:IsA("ModuleScript") then
		return nil, nil
	end
	local ok, result = pcall(require, instance)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

-- Calls `module[fnName]()` if it is a function. Returns (result, nil) or (nil, problem message).
local function callList(module: any, moduleName: string, fnName: string): (any, string?)
	local fn = module[fnName]
	if type(fn) ~= "function" then
		return nil, `{moduleName}.{fnName}() is missing`
	end
	local ok, result = pcall(fn)
	if not ok then
		return nil, `{moduleName}.{fnName}() failed: {tostring(result)}`
	end
	if type(result) ~= "table" then
		return nil, `{moduleName}.{fnName}() must return a table (got {show(result)})`
	end
	return result, nil
end

-- Private: Config-internal checks -----------------------------------------------------------------------------------

local function checkRarityTable(problems: Problems, path: string, tbl: { [string]: number }, rarities: { string })
	local known = {}
	for _, rarity in rarities do
		known[rarity] = true
		if tbl[rarity] == nil then
			add(problems, `{path} has no entry for rarity {rarity}`)
		end
	end
	for _, rarity in sortedKeys(tbl) do
		if not known[rarity] then
			add(problems, `{path}.{tostring(rarity)} is not a rarity`)
		end
	end
end

local function checkEconomy(problems: Problems, rarities: { string })
	local p = "Config.Economy"
	expectCount(problems, `{p}.maxCoins`, Economy.maxCoins, 1)
	expectCount(problems, `{p}.startingCoins`, Economy.startingCoins, 0)
	expect(
		problems,
		Economy.startingCoins <= Economy.maxCoins,
		`{p}.startingCoins ({Economy.startingCoins}) must not exceed maxCoins ({Economy.maxCoins})`
	)

	local reasons = {}
	for index, reason in Economy.CoinReasons do
		expectText(problems, `{p}.CoinReasons[{index}]`, reason)
		expect(problems, not reasons[reason], `{p}.CoinReasons lists {show(reason)} twice`)
		reasons[reason] = true
	end

	checkRarityTable(problems, `{p}.SquishyPower`, Economy.SquishyPower, rarities)
	for rarity, power in Economy.SquishyPower do
		expectCount(problems, `{p}.SquishyPower.{rarity}`, power, 1)
	end
	-- Spec 2026-10-12 §8: below 100%, so opening a paid box can never earn Coins (checkBoxes checks freeBoxPriceOf).
	local refund = Economy.DuplicateRefund
	expect(
		problems,
		isInteger(refund.percent) and refund.percent >= 0 and refund.percent < PERCENT,
		`{p}.DuplicateRefund.percent must be a whole number in 0..99 (got {show(refund.percent)})`
	)
	expectId(problems, `{p}.DuplicateRefund.freeBoxPriceOf`, refund.freeBoxPriceOf)

	local limit = Economy.SqueezeLimit
	expectBoolean(problems, `{p}.SqueezeLimit.enabled`, limit.enabled)
	expectPositive(problems, `{p}.SqueezeLimit.perHour`, limit.perHour)
	expectCount(problems, `{p}.SqueezeLimit.burst`, limit.burst, 1)
	expectCount(problems, `{p}.SqueezeLimit.emptyCoins`, limit.emptyCoins, 0)

	local duel = Economy.DuelRewards
	eachField(problems, `{p}.DuelRewards`, duel, { "win", "loss", "draw" }, expectCoins)
	expectCount(problems, `{p}.DuelRewards.minOwnThrows`, duel.minOwnThrows, 1)
	expectNonNegative(problems, `{p}.DuelRewards.lossMinActiveSeconds`, duel.lossMinActiveSeconds)
	expect(
		problems,
		isNumber(duel.winMinActiveSeconds) and duel.winMinActiveSeconds >= Duel.Rules.EarlyForfeitSeconds,
		`{p}.DuelRewards.winMinActiveSeconds ({duel.winMinActiveSeconds}) must be >= `
			.. `Config.Duel.Rules.EarlyForfeitSeconds ({Duel.Rules.EarlyForfeitSeconds})`
	)
	expectCount(problems, `{p}.DuelRewards.samePairFullRewards`, duel.samePairFullRewards, 1)
	expectPositive(problems, `{p}.DuelRewards.samePairWindowSeconds`, duel.samePairWindowSeconds)
	expectBetween(problems, `{p}.DuelRewards.samePairMultiplier`, duel.samePairMultiplier, 0, 1)
	-- (the same-pair limit is counted from profile.samePair, trimmed by time, not from the capped duelLog;
	-- Config.Data.caps.samePair is checked with the other caps)

	local daily = Economy.Daily
	expect(problems, #daily.coinsByDay >= 1, `{p}.Daily.coinsByDay must list at least one day`)
	for day, coins in daily.coinsByDay do
		expectCount(problems, `{p}.Daily.coinsByDay[{day}]`, coins, 1)
	end
	expectBetween(problems, `{p}.Daily.freeBoxDay`, daily.freeBoxDay, 1, #daily.coinsByDay)
	expectCount(problems, `{p}.Daily.freeBoxDay`, daily.freeBoxDay, 1)
	expectId(problems, `{p}.Daily.freeBoxId`, daily.freeBoxId)

	local quests = Economy.Quests
	expectCount(problems, `{p}.Quests.perDay`, quests.perDay, 1)
	expectCount(problems, `{p}.Quests.freeSwapsPerDay`, quests.freeSwapsPerDay, 0)
	expectPositive(problems, `{p}.Quests.rolloverCheckSeconds`, quests.rolloverCheckSeconds)
	expectBetween(problems, `{p}.Quests.equippedPickChance`, quests.equippedPickChance, 0, 1)
	expectNonNegative(problems, `{p}.Quests.practiceTargetRepeatSeconds`, quests.practiceTargetRepeatSeconds)

	local policy: string = Economy.DuplicatePolicy
	if policy == "exclude_owned" then
		add(problems, `{p}.DuplicatePolicy "exclude_owned" is not built (it needs per-player odds, DESIGN §6.5)`)
	elseif policy ~= "refund" then
		add(problems, `{p}.DuplicatePolicy must be "refund" or "exclude_owned" (got {show(policy)})`)
	end
	expectBoolean(problems, `{p}.AllowOpenWhenComplete`, Economy.AllowOpenWhenComplete)
	expectPositive(problems, `{p}.MinSecondsBetweenOpens`, Economy.MinSecondsBetweenOpens)

	local tip = Economy.LossTip
	expectCount(problems, `{p}.LossTip.lossStreak`, tip.lossStreak, 1)
	expectCount(problems, `{p}.LossTip.minOwnThrows`, tip.minOwnThrows, 1)
	expectNonNegative(problems, `{p}.LossTip.minSecondsBetween`, tip.minSecondsBetween)
	expectCount(problems, `{p}.LossTip.maxPerSession`, tip.maxPerSession, 0)
end

local function checkSqueeze(problems: Problems)
	local p = "Config.Squeeze"
	eachField(
		problems,
		p,
		Squeeze,
		{ "stationRadius", "cycleSeconds", "floodPerSecond", "floodLogWindowSeconds", "othersCullStuds" },
		expectPositive
	)
	expectNonNegative(problems, `{p}.radiusTolerance`, Squeeze.radiusTolerance)
	expectCount(problems, `{p}.bucketCapacity`, Squeeze.bucketCapacity, 1)
	expectCount(problems, `{p}.floodLogDrops`, Squeeze.floodLogDrops, 1)
	-- The pad test (moved from G9 with Config.Grip.Afk's margins, build plan Phase 6).
	expect(
		problems,
		isNumber(Squeeze.padMargin) and Squeeze.padMargin >= 0 and Squeeze.padMargin <= MAX_PAD_MARGIN,
		`{p}.padMargin must be in [0, {MAX_PAD_MARGIN}] studs (got {show(Squeeze.padMargin)})`
	)
	expect(
		problems,
		isNumber(Squeeze.heightAbove) and Squeeze.heightAbove > 0 and Squeeze.heightAbove <= MAX_PAD_HEIGHT_ABOVE,
		`{p}.heightAbove must be in (0, {MAX_PAD_HEIGHT_ABOVE}] studs (got {show(Squeeze.heightAbove)})`
	)

	-- Batch 1 #2: the bucket is the paid-squeeze cap (bucketCapacity at once, 1 per cycleSeconds = the hold rhythm).
	-- The flood guard must let at least the cap through, so an honest client's sends are never dropped.
	local capacity, cycle, floodRate = Squeeze.bucketCapacity, Squeeze.cycleSeconds, Squeeze.floodPerSecond
	if isNumber(capacity) and isNumber(cycle) and cycle > 0 and isNumber(floodRate) then
		local capPerSecond = math.max(capacity, 1 / cycle)
		expect(
			problems,
			floodRate + FEEL_SLACK >= capPerSecond,
			`{p}.floodPerSecond ({floodRate}) must be >= the paid-squeeze cap ({capPerSecond} per second: `
				.. `bucketCapacity {capacity}, 1 / cycleSeconds {1 / cycle})`
		)
	end
	-- The cap's rhythm is the hold's: clicking pays no faster than holding, and a hold is never refused.
	local holdRepeat = Grip.Hold.repeatSeconds
	expect(
		problems,
		isNumber(cycle) and isNumber(holdRepeat) and math.abs(cycle - holdRepeat) <= FEEL_SLACK,
		`{p}.cycleSeconds ({show(cycle)}) must equal Config.Grip.Hold.repeatSeconds ({show(holdRepeat)}), so `
			.. `clicking pays no faster than holding`
	)

	-- Hold-to-squeeze repeats one full squeeze animation: never before the release pop end of any rarity (§9.6).
	local phases = Anim.squeeze.phases
	local last = phases[#phases]
	if last and isNumber(last.endMs) then
		local extraMs = 0
		for _, flourish in Anim.squeeze.flourish do
			local extra = flourish.wideningExtraMs
			if type(extra) == "number" then
				extraMs = math.max(extraMs, extra)
			end
		end
		local popEnd = (last.endMs + extraMs) / 1000
		local repeatSeconds = Grip.Hold.repeatSeconds
		expect(
			problems,
			isNumber(repeatSeconds) and repeatSeconds + FEEL_SLACK >= popEnd,
			`Config.Grip.Hold.repeatSeconds ({show(repeatSeconds)}) must be >= the end of the squeeze release pop `
				.. `of every rarity ({popEnd} s, Config.Anim.squeeze.phases + the largest wideningExtraMs)`
		)
	end
	expectPositive(problems, "Config.Anim.squeeze.rhythm.streakSeconds", Anim.squeeze.rhythm.streakSeconds)

	-- The remote guard's bucket is the flood guard (same rate). Its burst holds SQUEEZE_BACKLOG_SECONDS (5 s) of the
	-- paid-squeeze cap (an honest clicker's presses queued by a network stall arrive at once and must never count as
	-- violations), and the global cap's burst and rate hold this remote's.
	local flood = Net.Remotes.SqueezeRequest
	expect(
		problems,
		flood == nil or flood.rate == Squeeze.floodPerSecond,
		`Config.Net.Remotes.SqueezeRequest.rate must equal {p}.floodPerSecond ({Squeeze.floodPerSecond})`
	)
	if flood ~= nil and isNumber(capacity) and isNumber(cycle) and cycle > 0 then
		local backlog = math.max(capacity, SQUEEZE_BACKLOG_SECONDS / cycle)
		local seconds = SQUEEZE_BACKLOG_SECONDS
		expect(
			problems,
			isNumber(flood.burst) and flood.burst + FEEL_SLACK >= backlog,
			`Config.Net.Remotes.SqueezeRequest.burst ({show(flood.burst)}) must be >= {seconds} s of the paid-squeeze `
				.. `cap ({string.format("%.10g", backlog)} = max({p}.bucketCapacity, {seconds} / cycleSeconds)), so a `
				.. `network stall never turns honest clicking into violations`
		)
		-- That backlog arrives at once: the flood guard drops all but floodPerSecond of it, and must not log it as abuse.
		local floodLogDrops = Squeeze.floodLogDrops
		expect(
			problems,
			isNumber(flood.burst)
				and isNumber(floodRate)
				and isNumber(floodLogDrops)
				and floodLogDrops >= flood.burst - floodRate,
			`{p}.floodLogDrops ({show(floodLogDrops)}) must be >= Config.Net.Remotes.SqueezeRequest.burst - `
				.. `{p}.floodPerSecond ({show(flood.burst)} - {show(floodRate)}), so a stall's backlog is not logged as abuse`
		)
		expect(
			problems,
			isNumber(Net.Global.burst) and isNumber(flood.burst) and Net.Global.burst >= flood.burst,
			`Config.Net.Global.burst ({show(Net.Global.burst)}) must be >= Config.Net.Remotes.SqueezeRequest.burst `
				.. `({show(flood.burst)})`
		)
		expect(
			problems,
			isNumber(Net.Global.rate) and isNumber(flood.rate) and Net.Global.rate >= flood.rate,
			`Config.Net.Global.rate ({show(Net.Global.rate)}) must be >= Config.Net.Remotes.SqueezeRequest.rate `
				.. `({show(flood.rate)})`
		)
	end
end

local function checkCombat(problems: Problems)
	local p = "Config.Combat"
	local hitbox = Combat.Hitbox
	expectPositive(problems, `{p}.Hitbox.radius`, hitbox.radius)
	expect(problems, hitbox.topOffset > hitbox.bottomOffset, `{p}.Hitbox.topOffset must be above bottomOffset`)
	expect(problems, typeof(Combat.ReleaseOffset) == "Vector3", `{p}.ReleaseOffset must be a Vector3`)

	expectPositive(problems, `{p}.Projectile.substepsPerSecond`, Combat.Projectile.substepsPerSecond)
	expectCount(problems, `{p}.Projectile.maxSubsteps`, Combat.Projectile.maxSubsteps, 1)
	expectPositive(problems, `{p}.Projectile.practiceBroadcastStuds`, Combat.Projectile.practiceBroadcastStuds)

	local throw = Combat.Throw
	expectCount(problems, `{p}.Throw.seqWindow`, throw.seqWindow, 1)
	expect(
		problems,
		throw.aimMagnitudeMin > 0 and throw.aimMagnitudeMin <= 1 and throw.aimMagnitudeMax >= 1,
		`{p}.Throw.aimMagnitudeMin/Max must satisfy 0 < min <= 1 <= max`
	)
	expect(
		problems,
		throw.pitchMinDeg >= -90 and throw.pitchMinDeg < throw.pitchMaxDeg and throw.pitchMaxDeg <= 90,
		`{p}.Throw.pitchMinDeg/pitchMaxDeg must satisfy -90 <= min < max <= 90`
	)
	expectBetween(
		problems,
		`{p}.Throw.noSolutionPitchDeg`,
		throw.noSolutionPitchDeg,
		throw.pitchMinDeg,
		throw.pitchMaxDeg
	)
	expectBetween(problems, `{p}.Throw.practiceConeDeg`, throw.practiceConeDeg, 0, 180)
	eachField(
		problems,
		`{p}.Throw`,
		throw,
		{ "zoneToleranceStuds", "originBaseStuds", "originPerPingStuds", "originPingCapSeconds" },
		expectNonNegative
	)

	local lag = Combat.Lag
	expect(problems, lag.TargetRewindMs == 0, `{p}.Lag.TargetRewindMs is reserved: v1 never rewinds, keep it 0`)
	eachField(
		problems,
		`{p}.Lag`,
		lag,
		{ "maxCompensationSeconds", "halfPingExtraSeconds", "clientTimeEarlySeconds", "clientTimeLateSeconds" },
		expectNonNegative
	)

	local guard = Combat.MovementGuard
	eachField(problems, `{p}.MovementGuard`, guard, { "checkHz", "maxHorizontalSpeed" }, expectPositive)
	expectCount(problems, `{p}.MovementGuard.overSpeedSamples`, guard.overSpeedSamples, 1)
	expectNonNegative(problems, `{p}.MovementGuard.hitGraceSeconds`, guard.hitGraceSeconds)
	expectNonNegative(problems, `{p}.MovementGuard.teleportGraceSeconds`, guard.teleportGraceSeconds)
	expectPositive(problems, `{p}.MovementGuard.holdToleranceStuds`, guard.holdToleranceStuds)
	local probe: any = guard.geometryProbeSize
	expect(
		problems,
		typeof(probe) == "Vector3" and probe.X > 0 and probe.Y > 0 and probe.Z > 0,
		`{p}.MovementGuard.geometryProbeSize must be a Vector3 with every side > 0`
	)

	for _, input in AIM_INPUTS do
		local assist = Combat.AimAssist[input]
		local path = `{p}.AimAssist.{input}`
		if assist == nil then
			add(problems, `{path} is missing`)
		else
			expectBoolean(problems, `{path}.enabled`, assist.enabled)
			expectBetween(problems, `{path}.coneDeg`, assist.coneDeg, 0, 90)
			expectBetween(problems, `{path}.strength`, assist.strength, 0, 1)
		end
	end

	expectPositive(problems, `{p}.Aim.maxRayStuds`, Combat.Aim.maxRayStuds)
	expectNonNegative(problems, `{p}.Aim.farHitMarginStuds`, Combat.Aim.farHitMarginStuds)
	expectNonNegative(problems, `{p}.Aim.touchShoulderOffsetStuds`, Combat.Aim.touchShoulderOffsetStuds)
	expectBetween(problems, `{p}.Aim.triggerThreshold`, Combat.Aim.triggerThreshold, 0, 1)

	for _, stat in THROW_STATS do
		local band = Combat.Bands[stat]
		local path = `{p}.Bands.{stat}`
		if band == nil then
			add(problems, `{path} is missing`)
		else
			expectPositive(problems, `{path}.min`, band.min)
			expect(problems, band.min < band.max, `{path}.min ({band.min}) must be below max ({band.max})`)
		end
	end

	local clamp = Duel.Rules.CooldownClamp
	local cooldown = Combat.Bands.cooldown
	if cooldown then
		expect(
			problems,
			cooldown.min >= clamp.Min and cooldown.max <= clamp.Max,
			`{p}.Bands.cooldown must lie inside Config.Duel.Rules.CooldownClamp ({clamp.Min}-{clamp.Max} s)`
		)
	end
	-- Every windup is longer than the largest lag compensation, so releaseAt is always in the future (§5.6 #7).
	local windup = Combat.Bands.windup
	if windup then
		expect(
			problems,
			windup.min > lag.maxCompensationSeconds,
			`{p}.Bands.windup.min ({windup.min}) must exceed {p}.Lag.maxCompensationSeconds `
				.. `({lag.maxCompensationSeconds}) so the server never fast-forwards a throw`
		)
	end

	local budget = Combat.PowerBudget
	eachField(
		problems,
		`{p}.PowerBudget`,
		budget,
		{ "referenceDistance", "dodgeSpeed", "studsPerPoint", "ratePerPoint" },
		expectPositive
	)
	eachField(problems, `{p}.PowerBudget`, budget, { "reactionSeconds", "tolerance" }, expectNonNegative)
	for _, stat in { "speed", "radius", "cooldown", "windup" } do
		local band = Combat.Bands[stat]
		local value = (budget.baseline :: any)[stat]
		if band then
			expectBetween(problems, `{p}.PowerBudget.baseline.{stat}`, value, band.min, band.max)
		end
	end
	expect(
		problems,
		budget.dodgeSpeed == Duel.Rules.Movement.WalkSpeed,
		`{p}.PowerBudget.dodgeSpeed ({budget.dodgeSpeed}) must equal Config.Duel.Rules.Movement.WalkSpeed `
			.. `({Duel.Rules.Movement.WalkSpeed})`
	)
	expectPositive(problems, `{p}.Practice.targetDownSeconds`, Combat.Practice.targetDownSeconds)
end

local function checkDuel(problems: Problems)
	local p = "Config.Duel.Rules"
	local rules = Duel.Rules
	expectCount(problems, `{p}.Lives`, rules.Lives, 1)
	eachField(problems, p, rules, {
		"MatchSeconds",
		"PreparingTimeoutSeconds",
		"PositioningTimeoutSeconds",
		"CountdownSeconds",
		"ResultSeconds",
		"ProjectileMaxLifetime",
	}, expectPositive)
	eachField(problems, p, rules, {
		"SuddenDeathSeconds",
		"HitInvulnSeconds",
		"OutOfBoundsInvulnSeconds",
		"CooldownToleranceSeconds",
		"InputBufferSeconds",
		"EarlyForfeitSeconds",
		"RequeueCooldownSeconds",
		"BailRequeueCooldownSeconds",
	}, expectNonNegative)
	expect(
		problems,
		rules.SuddenDeathCooldownMultiplier > 0 and rules.SuddenDeathCooldownMultiplier <= 1,
		`{p}.SuddenDeathCooldownMultiplier must be in (0, 1]`
	)
	expect(
		problems,
		rules.CooldownClamp.Min > 0 and rules.CooldownClamp.Min < rules.CooldownClamp.Max,
		`{p}.CooldownClamp must satisfy 0 < Min < Max`
	)
	expectBoolean(problems, `{p}.HoldToCharge`, rules.HoldToCharge) -- feature 1 (was HoldToRepeat)
	expectCount(problems, `{p}.MaxActiveProjectilesPerPlayer`, rules.MaxActiveProjectilesPerPlayer, 1)
	expect(
		problems,
		rules.EarlyForfeitSeconds < rules.MatchSeconds,
		`{p}.EarlyForfeitSeconds must be shorter than MatchSeconds`
	)
	local oob = rules.OutOfBounds
	expectPositive(problems, `{p}.OutOfBounds.CheckHz`, oob.CheckHz)
	expect(problems, oob.KillYOffset < 0, `{p}.OutOfBounds.KillYOffset must be below the floor (< 0)`)
	expectBetween(problems, `{p}.OutOfBounds.LifePenalty`, oob.LifePenalty, 0, rules.Lives)
	expectCount(problems, `{p}.OutOfBounds.LifePenalty`, oob.LifePenalty, 0)
	expectCount(problems, `{p}.OutOfBounds.MaxPerMatch`, oob.MaxPerMatch, 0)
	expectNonNegative(problems, `{p}.OutOfBounds.HalfToleranceStuds`, oob.HalfToleranceStuds)
	expectPositive(problems, `{p}.Movement.WalkSpeed`, rules.Movement.WalkSpeed)
	expectNonNegative(problems, `{p}.Movement.JumpHeight`, rules.Movement.JumpHeight)
	expectNonNegative(problems, `{p}.Knockback.Horizontal`, rules.Knockback.Horizontal)
	expectNonNegative(problems, `{p}.Knockback.Vertical`, rules.Knockback.Vertical)

	-- Spec phase 5: the dash (the design's numbers and the server's tolerances).
	local dash = rules.Dash
	local d = `{p}.Dash`
	eachField(problems, d, dash, {
		"distanceStuds",
		"seconds",
		"visualFrames",
		"visualFps",
		"ribbonSeconds",
		"cooldownSeconds",
		"bodyRadiusStuds",
		"maxAccelStuds",
		"blockedLagStuds",
	}, expectPositive)
	eachField(problems, d, dash, {
		"cooldownToleranceSeconds",
		"groundToleranceStuds",
		"guardSlackStuds",
		"guardLeadSeconds",
		"guardTailSeconds",
	}, expectNonNegative)
	for _, field in { "pushoffFrame", "plantFrame", "fadeFromFrame" } do
		expectBetween(problems, `{d}.{field}`, dash[field], 0, dash.visualFrames)
	end
	expect(
		problems,
		isNumber(dash.cooldownToleranceSeconds) and dash.cooldownToleranceSeconds < dash.cooldownSeconds,
		`{d}.cooldownToleranceSeconds must be shorter than cooldownSeconds`
	)

	local mm = Duel.Matchmaking
	eachField(
		problems,
		"Config.Duel.Matchmaking",
		mm,
		{ "PairIntervalSeconds", "NoOpponentHintSeconds", "QueueMaxSeconds" },
		expectPositive
	)
	expectBoolean(problems, "Config.Duel.Matchmaking.AvoidImmediateRematch", mm.AvoidImmediateRematch)
	expectCount(problems, "Config.Duel.Matchmaking.NormalPriority", mm.NormalPriority, 0)
	expectCount(problems, "Config.Duel.Matchmaking.RequeuePriority", mm.RequeuePriority, 0)
	expect(
		problems,
		mm.RequeuePriority > mm.NormalPriority,
		"Config.Duel.Matchmaking.RequeuePriority must be above NormalPriority (a requeued player goes first, §5.4)"
	)
	expectNonNegative(problems, "Config.Duel.Matchmaking.RatingWindow.base", mm.RatingWindow.base)
	expectNonNegative(problems, "Config.Duel.Matchmaking.RatingWindow.growthPerSecond", mm.RatingWindow.growthPerSecond)

	local positioning = Duel.Positioning
	eachField(problems, "Config.Duel.Positioning", positioning, {
		"StreamAroundTimeoutSeconds",
		"R6Height",
		"RespawnWaitSeconds",
		"MissingRootSeconds",
		"CameraBehindStuds",
	}, expectPositive)
	expectNonNegative(problems, "Config.Duel.Positioning.CameraHeightStuds", positioning.CameraHeightStuds)
	expectNonNegative(problems, "Config.Duel.Positioning.R15ExtraHeight", positioning.R15ExtraHeight)
	expectNonNegative(problems, "Config.Duel.Positioning.ReturnFadeSeconds", positioning.ReturnFadeSeconds)
	-- Preparing streams both pads "in pcall, both done or 3 s" (§5.4): the stream wait fits inside the phase.
	expect(
		problems,
		positioning.StreamAroundTimeoutSeconds <= rules.PreparingTimeoutSeconds,
		`Config.Duel.Positioning.StreamAroundTimeoutSeconds ({positioning.StreamAroundTimeoutSeconds}) must not `
			.. `exceed {p}.PreparingTimeoutSeconds ({rules.PreparingTimeoutSeconds})`
	)

	local arena = Duel.Arena
	local a = "Config.Duel.Arena"
	expectCount(problems, `{a}.MaxSlots`, arena.MaxSlots, 1)
	expect(
		problems,
		arena.MaxSlots <= #arena.SlotOrigins,
		`{a}.MaxSlots ({arena.MaxSlots}) exceeds the {#arena.SlotOrigins} SlotOrigins`
	)
	expectBetween(problems, `{a}.PrewarmSlots`, arena.PrewarmSlots, 0, arena.MaxSlots)
	expectCount(problems, `{a}.PrewarmSlots`, arena.PrewarmSlots, 0)
	expectNonNegative(problems, `{a}.LeaseGraceSeconds`, arena.LeaseGraceSeconds)
	expectPositive(problems, `{a}.JanitorIntervalSeconds`, arena.JanitorIntervalSeconds)
	-- After a lease expires the owner returns its players and releases the slot; the drain must outlast that return
	-- (two stream waits, the fade and a janitor pass) or a new pair could land on the old players.
	local returnSeconds = 2 * positioning.StreamAroundTimeoutSeconds + positioning.ReturnFadeSeconds
	expect(
		problems,
		type(arena.LeaseDrainSeconds) == "number" and arena.LeaseDrainSeconds > returnSeconds,
		`{a}.LeaseDrainSeconds must be a number above {returnSeconds} (the longest return)`
	)
	for index, origin in arena.SlotOrigins do
		for other = index + 1, #arena.SlotOrigins do
			expect(problems, origin ~= arena.SlotOrigins[other], `{a}.SlotOrigins[{index}] and [{other}] are equal`)
		end
	end
	expectNonNegative(problems, "Config.Duel.RestartMarginSeconds", Duel.RestartMarginSeconds)
end

local function checkAbilities(problems: Problems)
	for _, id in sortedKeys(Abilities) do
		local ability = Abilities[id]
		local p = `Config.Abilities.{id}`
		expectId(problems, p, id)
		expectPositive(problems, `{p}.chargeMax`, ability.chargeMax)
		expectBetween(problems, `{p}.startCharge`, ability.startCharge, 0, ability.chargeMax)
		eachField(problems, p, ability, {
			"chargePerSecond",
			"chargePerHitLanded",
			"chargePerLifeLost",
			"recoverySeconds",
			"budgetCost",
			"originForwardStuds",
		}, expectNonNegative)
		eachField(
			problems,
			p,
			ability,
			{ "radius", "laneHeightAboveFloor", "speed", "maxLength", "knockbackMultiplier", "practiceCooldownSeconds" },
			expectPositive
		)
		expect(
			problems,
			ability.telegraphSeconds >= MIN_TELEGRAPH_SECONDS,
			`{p}.telegraphSeconds must be >= {MIN_TELEGRAPH_SECONDS} (opponent warning, DESIGN §5.9)`
		)
		expect(
			problems,
			ability.minIntervalSeconds >= MIN_ABILITY_INTERVAL_SECONDS,
			`{p}.minIntervalSeconds must be >= {MIN_ABILITY_INTERVAL_SECONDS} (DESIGN §5.9)`
		)
		expectBoolean(problems, `{p}.cancelOnHitDuringTelegraph`, ability.cancelOnHitDuringTelegraph)
		expectBetween(problems, `{p}.refundOnCancel`, ability.refundOnCancel, 0, 1)
		expectBetween(problems, `{p}.livesCost`, ability.livesCost, 1, Duel.Rules.Lives)
		expectCount(problems, `{p}.livesCost`, ability.livesCost, 1)
		expect(
			problems,
			ability.minHorizontalAim > 0 and ability.minHorizontalAim <= 1,
			`{p}.minHorizontalAim must be in (0, 1]`
		)
		local kind = ability.kind
		expect(problems, ABILITY_KINDS[kind] == true, `{p}.kind {show(kind)} is not an ability kind`)
		-- The lane sphere flies at a fixed height; it must clear the floor (§5.9: floor+0.5 .. floor+8.5).
		if FLYING_KINDS[kind] then
			expect(
				problems,
				ability.laneHeightAboveFloor > ability.radius,
				`{p}.laneHeightAboveFloor ({ability.laneHeightAboveFloor}) must be above radius ({ability.radius}) so `
					.. "the lane sphere stays above the floor"
			)
		end
		-- Spec phase 5: each kind's own fields (Config.Abilities header).
		if kind == "volley" then
			expectCount(problems, `{p}.count`, ability.count, 1)
			expect(
				problems,
				isInteger(ability.count) and (ability.count :: number) <= MAX_VOLLEY_COUNT,
				`{p}.count must be at most {MAX_VOLLEY_COUNT}`
			)
			expectBetween(problems, `{p}.fanDeg`, ability.fanDeg, 0, 180)
			expectNonNegative(problems, `{p}.staggerSeconds`, ability.staggerSeconds)
		elseif kind == "roller" then
			expectPositive(problems, `{p}.clearHeight`, ability.clearHeight)
		elseif kind == "bubble" then
			expectPositive(problems, `{p}.popSeconds`, ability.popSeconds)
			expectPositive(problems, `{p}.splashRadius`, ability.splashRadius)
		elseif kind == "rain" then
			expectCount(problems, `{p}.drops`, ability.drops, 1)
			eachField(problems, p, ability, {
				"firstShadowSeconds",
				"dropStepSeconds",
				"shadowSeconds",
				"fallSeconds",
				"dropHitRadius",
				"dropAngleStep",
				"targetRadius",
			}, expectPositive)
			local radii = ability.dropRadii
			local radiiOk = false
			if radii ~= nil and type(radii) == "table" and #radii > 0 then
				radiiOk = true
				for _, r in radii do
					radiiOk = radiiOk and isNumber(r) and r >= 0 and r <= ability.radius
				end
			end
			expect(
				problems,
				radiiOk,
				`{p}.dropRadii must be a non-empty list of numbers in [0, radius {show(ability.radius)}] (drops land in the zone)`
			)
		end
	end
end

-- Every in-band throw can reach the far end of the court: max range speed² / gravity (§5.8) with the slowest
-- speed and the strongest gravity, against the court length (WorldLayout.Arena, playable Z ±halfZ). Otherwise
-- ProjectileMath.solveLaunchDir would fall back to 45° for a reticle inside the arena.
local function checkCombatReach(problems: Problems, layout: any)
	local arena = layout.Arena
	if type(arena) ~= "table" or not isNumber(arena.halfZ) then
		return
	end
	local speed, gravity = Combat.Bands.speed, Combat.Bands.gravity
	if speed == nil or gravity == nil then
		return
	end
	local court = 2 * arena.halfZ
	local reach = speed.min * speed.min / gravity.max
	expect(
		problems,
		reach >= court,
		`Config.Combat.Bands: the shortest throw range (speed.min² / gravity.max = {string.format("%.2f", reach)} `
			.. `studs) must reach the court length ({court} studs, WorldLayout.Arena)`
	)
end

local function checkData(problems: Problems)
	local p = "Config.Data"
	expectText(problems, `{p}.storeName`, Data.storeName)
	expectText(problems, `{p}.studioStoreName`, Data.studioStoreName)
	expectText(problems, `{p}.keyPrefix`, Data.keyPrefix)
	-- Studio can never touch real players' data (§3.1).
	expect(
		problems,
		string.sub(Data.studioStoreName, -7) == "_STUDIO",
		`{p}.studioStoreName must end in "_STUDIO" (got {show(Data.studioStoreName)})`
	)
	expect(
		problems,
		string.sub(Data.storeName, -7) ~= "_STUDIO" and Data.storeName ~= Data.studioStoreName,
		`{p}.storeName must be the live store, distinct from studioStoreName`
	)
	local mode: string = Data.studioMode
	expect(
		problems,
		mode == "memory" or mode == "datastore",
		`{p}.studioMode must be "memory" or "datastore" (got {show(mode)})`
	)

	eachField(problems, p, Data, {
		"autosaveInterval",
		"autosaveBudgetRetrySeconds",
		"lockStaleAfter",
		"lockWaitMax",
		"lockPoll",
		"retryCap",
		"offlineRetry",
		"closeDeadline",
	}, expectPositive)
	eachField(
		problems,
		p,
		Data,
		{ "autosaveBudgetFloor", "saveSoonDelay", "minWriteGap", "lockPollJitter", "retryJitter" },
		expectNonNegative
	)
	expect(problems, Data.lockPollJitter < Data.lockPoll, `{p}.lockPollJitter must be smaller than lockPoll`)
	expectCount(problems, `{p}.retryAttempts`, Data.retryAttempts, 1)
	expectCount(problems, `{p}.offlineRetryCount`, Data.offlineRetryCount, 0)
	expect(
		problems,
		Data.closeDeadline < BIND_TO_CLOSE_LIMIT_SECONDS,
		`{p}.closeDeadline must be below the {BIND_TO_CLOSE_LIMIT_SECONDS} s BindToClose limit`
	)
	for _, cap in { "boxLog", "shopLog", "receipts", "duelLog", "samePair" } do
		expectCount(problems, `{p}.caps.{cap}`, (Data.caps :: any)[cap], 1)
	end
	-- §3.5: the size test's bound sits below the DataStore limit; §17.9 #6: the timer skew is a duration.
	expect(
		problems,
		isInteger(Data.profileSizeLimitBytes)
			and Data.profileSizeLimitBytes >= 1
			and Data.profileSizeLimitBytes < DATASTORE_VALUE_LIMIT,
		`{p}.profileSizeLimitBytes must be an integer in [1, {DATASTORE_VALUE_LIMIT}) (got {show(
			Data.profileSizeLimitBytes
		)})`
	)
	expectNonNegative(problems, `{p}.timestampSkewSeconds`, Data.timestampSkewSeconds)

	local seen: { [number]: string } = {}
	for _, class in sortedKeys(Data.ErrorCodes) do
		for _, code in (Data.ErrorCodes :: any)[class] do
			expectCount(problems, `{p}.ErrorCodes.{class}`, code, 1)
			if seen[code] then
				add(problems, `{p}.ErrorCodes lists {code} in both {seen[code]} and {class}`)
			end
			seen[code] = class
		end
	end

	local settings = Data.DefaultSettings
	expect(problems, Data.settingsMin < Data.settingsMax, `{p}.settingsMin must be below settingsMax`)
	for _, volume in { "music", "sfx" } do
		local value = (settings :: any)[volume]
		expectBetween(problems, `{p}.DefaultSettings.{volume}`, value, Data.settingsMin, Data.settingsMax)
		expectCount(problems, `{p}.DefaultSettings.{volume}`, value, Data.settingsMin)
	end
	expectBoolean(problems, `{p}.DefaultSettings.cameraShake`, settings.cameraShake)
	expectBoolean(problems, `{p}.DefaultSettings.showTips`, settings.showTips)
end

local function checkNet(problems: Problems)
	local p = "Config.Net"
	for _, name in sortedKeys(Net.Remotes) do
		local entry = Net.Remotes[name]
		expectPositive(problems, `{p}.Remotes.{name}.rate`, entry.rate)
		expectCount(problems, `{p}.Remotes.{name}.burst`, entry.burst, 1)
		expect(
			problems,
			entry.oneInFlight == nil or type(entry.oneInFlight) == "boolean",
			`{p}.Remotes.{name}.oneInFlight must be nil or a boolean`
		)
	end
	expectPositive(problems, `{p}.Global.rate`, Net.Global.rate)
	expectCount(problems, `{p}.Global.burst`, Net.Global.burst, 1)
	expectCount(problems, `{p}.Abuse.violations`, Net.Abuse.violations, 1)
	expectPositive(problems, `{p}.Abuse.windowSeconds`, Net.Abuse.windowSeconds)
	expectPositive(problems, `{p}.Abuse.muteSeconds`, Net.Abuse.muteSeconds)
	expectBoolean(problems, `{p}.kickOnAbuse`, Net.kickOnAbuse)
	expectPositive(problems, `{p}.maxAbsNumber`, Net.maxAbsNumber)
	-- GetServerTimeNow() is Unix seconds, so the bound must lie above the current Unix time.
	local unixNow = os.time()
	expect(
		problems,
		isNumber(Net.maxAbsServerTime) and Net.maxAbsServerTime > unixNow,
		`{p}.maxAbsServerTime must be a number above the current Unix time ({unixNow}) so real `
			.. `GetServerTimeNow() timestamps pass (got {show(Net.maxAbsServerTime)})`
	)
	eachField(problems, `{p}.Broadcast`, Net.Broadcast, { "queueStatusMaxHz", "ultimateChargeMaxHz" }, expectPositive)
	eachField(
		problems,
		`{p}.Client`,
		Net.Client,
		{ "connectTimeoutSeconds", "snapshotRetrySeconds", "snapshotWaitSeconds" },
		expectPositive
	)

	-- An honest client polling RequestSnapshot every snapshotRetrySeconds while loading (§2.6) must never be
	-- rate-limited: the bucket refills at least one token per poll.
	local snapshot = Net.Remotes.RequestSnapshot
	if snapshot ~= nil and isNumber(snapshot.rate) and isNumber(Net.Client.snapshotRetrySeconds) then
		expect(
			problems,
			snapshot.rate * Net.Client.snapshotRetrySeconds >= 1,
			`{p}.Remotes.RequestSnapshot.rate ({snapshot.rate}) must be >= 1 / Client.snapshotRetrySeconds `
				.. `({Net.Client.snapshotRetrySeconds} s), or loading clients are rate-limited`
		)
	end
end

-- Every client -> server remote in Remotes.SPEC has a rate entry, and every rate entry is a C->S remote.
local function checkRemoteRates(problems: Problems, Remotes: any)
	local spec = Remotes.SPEC
	if type(spec) ~= "table" then
		add(problems, "Remotes.SPEC is missing: remote rate entries were not checked")
		return
	end
	for _, name in sortedKeys(spec) do
		local entry = spec[name]
		if type(entry) == "table" and entry.dir == "c2s" and Net.Remotes[name] == nil then
			add(problems, `Config.Net.Remotes has no rate entry for the client -> server remote {tostring(name)}`)
		end
	end
	for _, name in sortedKeys(Net.Remotes) do
		local entry = spec[name]
		if type(entry) ~= "table" then
			add(problems, `Config.Net.Remotes.{name} is not a remote in Remotes.SPEC`)
		elseif entry.dir ~= "c2s" then
			add(problems, `Config.Net.Remotes.{name} is not a client -> server remote`)
		end
	end
end

local function checkMonetization(problems: Problems)
	local p = "Config.Monetization"
	local keys: { [string]: boolean } = {}
	local productIds: { [number]: boolean } = {}
	local configured = 0
	for index, bundle in Monetization.CoinBundles do
		local path = `{p}.CoinBundles[{index}]`
		expectId(problems, `{path}.key`, bundle.key)
		expect(problems, not keys[bundle.key], `{path}.key {show(bundle.key)} is used twice`)
		keys[bundle.key] = true
		expectText(problems, `{path}.nameKey`, bundle.nameKey)
		expectCount(problems, `{path}.coins`, bundle.coins, 1)
		expectBoolean(problems, `{path}.onSale`, bundle.onSale)
		local productId = bundle.productId
		if productId ~= nil then
			configured += 1
			expectCount(problems, `{path}.productId`, productId, 1)
			expect(problems, not productIds[productId], `{path}.productId {productId} is used twice`)
			productIds[productId] = true
			expect(
				problems,
				Monetization.byProductId[productId] == bundle,
				`{p}.byProductId[{productId}] must point to {path}`
			)
		end
	end
	local indexed = 0
	for _ in Monetization.byProductId do
		indexed += 1
	end
	expect(problems, indexed == configured, `{p}.byProductId must index exactly the bundles that have a productId`)

	local passKeys: { [string]: boolean } = {}
	for index, pass in Monetization.GamePasses do
		local path = `{p}.GamePasses[{index}]`
		expectId(problems, `{path}.key`, pass.key)
		expect(problems, not passKeys[pass.key], `{path}.key {show(pass.key)} is used twice`)
		passKeys[pass.key] = true
		expectText(problems, `{path}.nameKey`, pass.nameKey)
		if pass.passId ~= nil then
			expectCount(problems, `{path}.passId`, pass.passId, 1)
		end
	end
	expectBoolean(problems, `{p}.ShowPassesComingSoon`, Monetization.ShowPassesComingSoon)
	expectCount(problems, `{p}.creatorGroupId`, Monetization.creatorGroupId, 1)
	expectCount(problems, `{p}.productInfoRetries`, Monetization.productInfoRetries, 0)
	expectCount(problems, `{p}.passCheckRetries`, Monetization.passCheckRetries, 0)

	local policy = Monetization.Policy
	expectCount(problems, `{p}.Policy.attempts`, policy.attempts, 1)
	expect(
		problems,
		#policy.waitSeconds >= policy.attempts - 1,
		`{p}.Policy.waitSeconds needs a wait after each failed attempt but the last`
	)
	for index, wait in policy.waitSeconds do
		expectPositive(problems, `{p}.Policy.waitSeconds[{index}]`, wait)
	end
	expectPositive(problems, `{p}.Policy.manualRetryMinSeconds`, policy.manualRetryMinSeconds)
	expectCount(problems, `{p}.Policy.manualRetryMaxPerSession`, policy.manualRetryMaxPerSession, 0)
end

local function checkUI(problems: Problems)
	local p = "Config.UI"
	local scale = UI.Scale
	expectPositive(problems, `{p}.Scale.referenceHeight`, scale.referenceHeight)
	expectPositive(problems, `{p}.Scale.referenceWidth`, scale.referenceWidth)
	expect(problems, scale.min > 0 and scale.min <= scale.max, `{p}.Scale must satisfy 0 < min <= max`)
	eachField(
		problems,
		`{p}.Breakpoints`,
		UI.Breakpoints,
		{ "compactBelowHeight", "compactBelowWidth" },
		expectPositive
	)
	expectPositive(problems, `{p}.modalMaxWidth`, UI.modalMaxWidth)
	expectCount(problems, `{p}.modalStackMax`, UI.modalStackMax, 1)

	local touch = UI.Touch
	eachField(problems, `{p}.Touch`, touch, {
		"minTarget",
		"minTargetFloor",
		"primaryButton",
		"closeButton",
		"throwButton",
		"throwButtonMin",
		"ultButton",
		"dashButton",
		"gap",
	}, expectPositive)
	expectBetween(problems, `{p}.Touch.thumbstickZoneWidth`, touch.thumbstickZoneWidth, 0, 1)
	expectBetween(problems, `{p}.Touch.thumbstickZoneHeight`, touch.thumbstickZoneHeight, 0, 1)
	expect(
		problems,
		touch.minTarget * scale.min >= touch.minTargetFloor,
		`{p}.Touch.minTarget × Scale.min must be >= minTargetFloor ({touch.minTargetFloor} px)`
	)
	expect(
		problems,
		touch.throwButton * scale.min >= touch.throwButtonMin,
		`{p}.Touch.throwButton × Scale.min must be >= throwButtonMin ({touch.throwButtonMin} px)`
	)

	expectPositive(problems, `{p}.minTextSize`, UI.minTextSize)
	for _, name in sortedKeys(UI.TextSize) do
		local size = UI.TextSize[name]
		expect(
			problems,
			isNumber(size) and size * scale.min >= UI.minTextSize,
			`{p}.TextSize.{name} ({size}) × Scale.min must be >= minTextSize ({UI.minTextSize})`
		)
	end
	for _, name in sortedKeys(UI.PreferredTextScale) do
		expectPositive(problems, `{p}.PreferredTextScale.{name}`, UI.PreferredTextScale[name])
	end

	local orders: { [number]: string } = {}
	for _, name in sortedKeys(UI.ScreenGuis) do
		local gui = UI.ScreenGuis[name]
		expect(problems, string.sub(name, 1, 3) == "SD_", `{p}.ScreenGuis.{name} must use the SD_ prefix`)
		expectCount(problems, `{p}.ScreenGuis.{name}.displayOrder`, gui.displayOrder, 0)
		if orders[gui.displayOrder] then
			add(
				problems,
				`{p}.ScreenGuis.{name} shares displayOrder {gui.displayOrder} with {orders[gui.displayOrder]}`
			)
		end
		orders[gui.displayOrder] = name
	end

	local motion = UI.motion
	for _, name in sortedKeys(motion) do
		local entry = (motion :: any)[name]
		if type(entry) == "table" then
			for _, field in { "ms", "countUpMs", "floatMs" } do
				if entry[field] ~= nil then
					expectPositive(problems, `{p}.motion.{name}.{field}`, entry[field])
				end
			end
		end
	end
	expectBetween(problems, `{p}.motion.disabledTextOpacity`, motion.disabledTextOpacity, 0, 1)
	expectPositive(problems, `{p}.motion.reducedMotionMaxFadeMs`, motion.reducedMotionMaxFadeMs)

	expectPositive(problems, `{p}.confirmSeconds`, UI.confirmSeconds)
	expectPositive(problems, `{p}.Controls.playerModuleWaitSeconds`, UI.Controls.playerModuleWaitSeconds)
	expectCount(problems, `{p}.Settings.sliderStep`, UI.Settings.sliderStep, 1)
	expect(
		problems,
		(Data.settingsMax - Data.settingsMin) % UI.Settings.sliderStep == 0,
		`{p}.Settings.sliderStep must divide the Config.Data settings range`
	)
	expectPositive(problems, `{p}.Settings.saveDebounceSeconds`, UI.Settings.saveDebounceSeconds)
	expectPositive(problems, `{p}.Queue.matchedBannerSeconds`, UI.Queue.matchedBannerSeconds)
	expectPositive(problems, `{p}.Result.autoCloseAfterReturnSeconds`, UI.Result.autoCloseAfterReturnSeconds)
	eachField(
		problems,
		`{p}.Result.rematchPulse`,
		UI.Result.rematchPulse,
		{ "scale", "upMs", "downMs" },
		expectPositive
	)
	local inventory = UI.Inventory
	expectPositive(problems, `{p}.Inventory.cardWidth`, inventory.cardWidth)
	expect(
		problems,
		inventory.gridWidthMin > 0 and inventory.gridWidthMin <= inventory.gridWidthMax and inventory.gridWidthMax < 1,
		`{p}.Inventory grid width must satisfy 0 < gridWidthMin <= gridWidthMax < 1`
	)
	expectCount(problems, `{p}.Inventory.lazyIconsAbove`, inventory.lazyIconsAbove, 1)
	-- Boxes and Shop screens (§11.6, Part 7).
	expectPositive(problems, `{p}.Boxes.stillCheckingSeconds`, UI.Boxes.stillCheckingSeconds)
	expectPositive(problems, `{p}.Boxes.revealHoldMaxSeconds`, UI.Boxes.revealHoldMaxSeconds)
	expectPositive(problems, `{p}.Shop.cardWidth`, UI.Shop.cardWidth)

	-- Grip HUD card (§17.7): one compact row with a thinner bar; the left column stays above the thumbstick zone.
	local grip = UI.Grip
	expectPositive(problems, `{p}.Grip.compactRowMaxHeight`, grip.compactRowMaxHeight)
	expect(
		problems,
		isNumber(grip.compactBarHeight)
			and grip.compactBarHeight > 0
			and grip.compactBarHeight < grip.compactRowMaxHeight,
		`{p}.Grip.compactBarHeight must be > 0 and below compactRowMaxHeight`
	)
	expect(
		problems,
		isNumber(grip.leftColumnMaxFraction)
			and grip.leftColumnMaxFraction > 0
			and grip.leftColumnMaxFraction <= 1 - touch.thumbstickZoneHeight + 1e-9, -- (float slack: 1 - 0.45 vs 0.55)
		`{p}.Grip.leftColumnMaxFraction must be in (0, 1 - Touch.thumbstickZoneHeight] so the left HUD column stays `
			.. "clear of the thumbstick zone"
	)
	expectCount(problems, `{p}.Grip.heldToastsMax`, grip.heldToastsMax, 1)

	-- UI FINAL (R1, the look kit): the sticker shapes are whole px >= 0, the alphas are in 0..1, every text role draws
	-- in a TextSize kind with a positive stroke.
	local sticker = UI.Sticker :: any
	for _, group in { "border", "lip", "radius" } do
		for _, name in sortedKeys(sticker[group]) do
			expectCount(problems, `{p}.Sticker.{group}.{name}`, sticker[group][name], 0)
		end
	end
	for _, group in { "surfaces", "bars", "toggles" } do
		for _, name in sortedKeys(sticker[group]) do
			local entry = sticker[group][name]
			for _, field in sortedKeys(entry) do
				local path = `{p}.Sticker.{group}.{name}.{field}`
				if string.sub(field, -5) == "Alpha" then
					expectBetween(problems, path, entry[field], 0, 1)
				else
					expectCount(problems, path, entry[field], 0)
				end
			end
		end
	end
	for _, name in sortedKeys(sticker.text) do
		local role = sticker.text[name]
		local path = `{p}.Sticker.text.{name}`
		expect(
			problems,
			type(role.kind) == "string" and isNumber(UI.TextSize[role.kind]),
			`{path}.kind must be a Config.UI.TextSize kind (got {show(role.kind)})`
		)
		expectPositive(problems, `{path}.stroke`, role.stroke)
		if role.drop ~= nil then
			expectCount(problems, `{path}.drop`, role.drop, 0)
		end
		if role.color ~= nil then
			expectText(problems, `{path}.color`, role.color)
		end
		local soft = role.soft
		if soft ~= nil then
			expectCount(problems, `{path}.soft.px`, soft.px, 1)
			expectBetween(problems, `{path}.soft.alpha`, soft.alpha, 0, 1)
		end
	end
	expectBoolean(problems, `{p}.Sticker.buttonCaps`, sticker.buttonCaps)
end

local function checkAudio(problems: Problems)
	local p = "Config.Audio"
	for _, name in AUDIO_GROUPS do
		local group = Audio.Groups[name]
		if group == nil then
			add(problems, `{p}.Groups.{name} is missing`)
		else
			expectBetween(problems, `{p}.Groups.{name}.maxVolume`, group.maxVolume, 0, 1)
			expect(
				problems,
				type((Data.DefaultSettings :: any)[group.slider]) == "number",
				`{p}.Groups.{name}.slider {show(group.slider)} must be a volume in Config.Data.DefaultSettings`
			)
		end
	end
	for _, name in sortedKeys(Audio.VoiceCaps) do
		expectCount(problems, `{p}.VoiceCaps.{name}`, (Audio.VoiceCaps :: any)[name], 1)
	end
	expect(
		problems,
		Audio.VoiceCaps.MusicDuringCrossfade >= Audio.VoiceCaps.Music,
		`{p}.VoiceCaps.MusicDuringCrossfade must be >= Music`
	)
	expectPositive(problems, `{p}.crossfadeSeconds`, Audio.crossfadeSeconds)
	expectNonNegative(problems, `{p}.stealFadeMs`, Audio.stealFadeMs)
	expectPositive(problems, `{p}.zoneCheckSeconds`, Audio.zoneCheckSeconds)
	for _, name in sortedKeys(Audio.cooldownMs) do
		expectNonNegative(problems, `{p}.cooldownMs.{name}`, (Audio.cooldownMs :: any)[name])
	end
	expectPositive(problems, `{p}.coinBatchSeconds`, Audio.coinBatchSeconds)
	for _, name in sortedKeys(Audio.pitchVariance) do
		expectBetween(problems, `{p}.pitchVariance.{name}`, (Audio.pitchVariance :: any)[name], 0, 0.5)
	end
	local spatial = Audio.Spatial
	expect(
		problems,
		spatial.minDistance > 0 and spatial.minDistance < spatial.maxDistance,
		`{p}.Spatial must satisfy 0 < minDistance < maxDistance`
	)
	expectPositive(problems, `{p}.Spatial.othersSqueezeStuds`, spatial.othersSqueezeStuds)
	expectCount(problems, `{p}.Spatial.othersSqueezeMax`, spatial.othersSqueezeMax, 1)
	for _, name in { "boxReveal", "countdown", "result", "inspect" } do
		expectBetween(problems, `{p}.Ducking.{name}`, (Audio.Ducking :: any)[name], 0, 1)
	end
	expectNonNegative(problems, `{p}.Ducking.rampMs`, Audio.Ducking.rampMs)
end

local function checkOnboarding(problems: Problems)
	local p = "Config.Onboarding"
	expectCount(problems, `{p}.version`, Onboarding.version, 1)
	expect(problems, #Onboarding.Steps >= 1, `{p}.Steps must list at least one step`)
	local ids: { [string]: boolean } = {}
	for index, step in Onboarding.Steps do
		local path = `{p}.Steps[{index}]`
		expect(
			problems,
			string.match(step.id, "^[a-z][A-Za-z]*$") ~= nil,
			`{path}.id must be camelCase (got {show(step.id)})`
		)
		expect(problems, not ids[step.id], `{path}.id {show(step.id)} is used twice`)
		ids[step.id] = true
		local recordedBy: string = step.recordedBy
		expect(
			problems,
			recordedBy == "client" or recordedBy == "server",
			`{path}.recordedBy must be "client" or "server"`
		)
	end
	-- The "Skip tutorial" id (Part 7): sent through OnboardingStep like a step id, but never a step itself.
	local skip: unknown = Onboarding.skipStepId
	expect(
		problems,
		type(skip) == "string" and string.match(skip, "^[a-z][A-Za-z]*$") ~= nil,
		`{p}.skipStepId must be a camelCase id (got {show(skip)})`
	)
	expect(
		problems,
		type(skip) ~= "string" or not ids[skip],
		`{p}.skipStepId {show(skip)} must not be a Steps id (skipping is not a step)`
	)
	expectNonNegative(problems, `{p}.waypointHideStuds`, Onboarding.waypointHideStuds)
end

local function checkInspect(problems: Problems)
	local p = "Config.Inspect"
	local framing = Inspect.Framing
	expectBetween(problems, `{p}.Framing.vFovDeg`, framing.vFovDeg, 1, 120)
	expect(problems, framing.fitPadding >= 1, `{p}.Framing.fitPadding must be >= 1`)
	expect(
		problems,
		framing.zoomMin > 0 and framing.zoomMin < framing.zoomMax,
		`{p}.Framing must satisfy 0 < zoomMin < zoomMax`
	)
	expectPositive(problems, `{p}.Framing.nearPlane`, framing.nearPlane)
	expect(
		problems,
		framing.minClearance >= framing.nearPlane,
		`{p}.Framing.minClearance must be >= nearPlane ({framing.nearPlane})`
	)
	-- The frame must hold the widest squeeze (§10.5).
	local widest = 1
	for _, phase in Anim.squeeze.phases do
		widest = math.max(widest, phase.w)
	end
	expect(
		problems,
		framing.squeezeWidening >= widest,
		`{p}.Framing.squeezeWidening ({framing.squeezeWidening}) must be >= the widest squeeze w ({widest}, `
			.. `Config.Anim.squeeze.phases)`
	)
	-- Squishy overhaul: each toy frames its widest scale + widenMargin (SquishRig.framingWidening).
	expect(
		problems,
		isNumber(framing.widenMargin) and framing.widenMargin > 0 and framing.widenMargin <= 0.2,
		`{p}.Framing.widenMargin must be a number in (0, 0.2] (got {show(framing.widenMargin)})`
	)

	local orbit = Inspect.Orbit
	expect(problems, orbit.pitchMinDeg < orbit.pitchMaxDeg, `{p}.Orbit.pitchMinDeg must be below pitchMaxDeg`)
	expectBetween(problems, `{p}.Orbit.defaultPitchDeg`, orbit.defaultPitchDeg, orbit.pitchMinDeg, orbit.pitchMaxDeg)
	eachField(
		problems,
		`{p}.Orbit`,
		orbit,
		{ "rotateSmoothSeconds", "zoomSmoothSeconds", "inertiaDecay", "resetSmoothSeconds" },
		expectPositive
	)

	local lighting = Inspect.Lighting
	expect(problems, typeof(lighting.lightColor) == "Color3", `{p}.Lighting.lightColor must be a Color3`)
	expect(problems, typeof(lighting.ambient) == "Color3", `{p}.Lighting.ambient must be a Color3`)
	expect(
		problems,
		typeof(lighting.lightDirection) == "Vector3" and lighting.lightDirection.Magnitude > 0,
		`{p}.Lighting.lightDirection must be a non-zero Vector3`
	)

	local background = Inspect.Background
	for _, field in { "gradientFrom", "gradientTo" } do
		local hex = (background :: any)[field]
		expect(
			problems,
			type(hex) == "string" and string.match(hex, HEX_COLOR_PATTERN) ~= nil,
			`{p}.Background.{field} must be a "#RRGGBB" colour (got {show(hex)})`
		)
	end
	expectBetween(problems, `{p}.Background.ellipseTransparency`, background.ellipseTransparency, 0, 1)
	expectBetween(problems, `{p}.Background.contactShadowTransparency`, background.contactShadowTransparency, 0, 1)

	local input = Inspect.Input
	eachField(problems, `{p}.Input`, input, {
		"dragYawDegPerHeight",
		"dragPitchDegPerHeight",
		"keyDegPerSecond",
		"stickExponent",
		"stickYawDegPerSecond",
		"stickPitchDegPerSecond",
		"triggerZoomPerSecond",
		"tapMaxPixels",
		"tapMaxMs",
	}, expectPositive)
	expect(problems, input.stickDeadzone >= 0 and input.stickDeadzone < 1, `{p}.Input.stickDeadzone must be in [0, 1)`)
	local triggerDeadzone = input.triggerDeadzone
	expect(
		problems,
		isNumber(triggerDeadzone) and triggerDeadzone >= 0 and triggerDeadzone < 1,
		`{p}.Input.triggerDeadzone must be a number in [0, 1) (got {show(triggerDeadzone)})`
	)
	expect(problems, input.wheelZoomFactor > 1, `{p}.Input.wheelZoomFactor must be > 1`)
	expectPositive(problems, `{p}.Input.dragSpeedSmoothSeconds`, input.dragSpeedSmoothSeconds)

	-- Squeeze preview (§10.7) and its 2D dots (Part 6 readings).
	local preview = Inspect.Preview
	local axis = preview.squeezeAxis
	expect(
		problems,
		axis == "X" or axis == "Y" or axis == "Z",
		`{p}.Preview.squeezeAxis must be "X", "Y" or "Z" ({show(axis)})`
	)
	expectPositive(problems, `{p}.Preview.maxPerSecond`, preview.maxPerSecond)
	expectNonNegative(problems, `{p}.Preview.soundCooldownMs`, preview.soundCooldownMs)
	eachField(
		problems,
		`{p}.Preview`,
		preview,
		{ "dotSizePx", "dotSpeedMinPx", "dotSpeedMaxPx", "dotLifeSeconds" },
		expectPositive
	)
	expect(
		problems,
		not isNumber(preview.dotSpeedMinPx)
			or not isNumber(preview.dotSpeedMaxPx)
			or preview.dotSpeedMinPx <= preview.dotSpeedMaxPx,
		`{p}.Preview.dotSpeedMinPx ({show(preview.dotSpeedMinPx)}) must be <= dotSpeedMaxPx `
			.. `({show(preview.dotSpeedMaxPx)})`
	)

	-- Collection pedestal displays (§7.6, §7.7; Part 6 readings).
	local collection = Inspect.Collection
	eachField(
		problems,
		`{p}.Collection`,
		collection,
		{ "checkSeconds", "nameplateOffsetStuds", "swayPeriodSeconds" },
		expectPositive
	)
	eachField(problems, `{p}.Collection`, collection, { "hysteresisStuds", "swayDeg" }, expectNonNegative)
	expectPositive(problems, `{p}.Collection.idleStuds`, collection.idleStuds)
	expectCount(problems, `{p}.Collection.idleMax`, collection.idleMax, 1)
	local plate = collection.nameplateSizeStuds
	expect(
		problems,
		typeof(plate) == "Vector2" and plate.X > 0 and plate.Y > 0,
		`{p}.Collection.nameplateSizeStuds must be a Vector2 with both sizes > 0 (got {show(plate)})`
	)
end

local function checkPoseAngles(problems: Problems, path: string, angles: { [string]: Vector3 }, rigJoints: any)
	for _, joint in sortedKeys(angles) do
		expect(problems, rigJoints[joint] ~= nil, `{path}.{joint} is not a joint in Config.Anim.joints`)
		expect(problems, typeof(angles[joint]) == "Vector3", `{path}.{joint} must be a Vector3 of degrees`)
	end
end

local function checkAnim(problems: Problems, rarities: { string })
	local p = "Config.Anim"
	local scheduler = Anim.Scheduler
	eachField(problems, `{p}.Scheduler`, scheduler, { "maxDt", "springSubstep", "springSubstepAbove" }, expectPositive)

	local deform = Anim.deform
	expect(problems, deform.maxSquash > 0 and deform.maxSquash < 1, `{p}.deform.maxSquash must be in (0, 1)`)
	expect(
		problems,
		deform.scaleMin > 0 and deform.scaleMin < 1 and deform.scaleMax > 1,
		`{p}.deform must satisfy 0 < scaleMin < 1 < scaleMax`
	)
	expect(
		problems,
		deform.writeEpsilon >= 0 and deform.writeEpsilon <= 1e-3,
		`{p}.deform.writeEpsilon must be in [0, 0.001] studs (a skipped write must stay invisible)`
	)

	expectPositive(problems, `{p}.joints.springSettleEpsilon`, Anim.joints.springSettleEpsilon)

	for _, name in sortedKeys(Anim.poses) do
		local pose = Anim.poses[name]
		local path = `{p}.poses.{name}`
		local mode: string = pose.mode
		expect(problems, mode == "override" or mode == "additive", `{path}.mode must be "override" or "additive"`)
		checkPoseAngles(problems, `{path}.R15`, pose.R15, Anim.joints.R15)
		checkPoseAngles(problems, `{path}.R6`, pose.R6, Anim.joints.R6)
		local sway = pose.sway
		if sway then
			expect(problems, Anim.joints.R15[sway.joint] ~= nil, `{path}.sway.joint is not a joint`)
			expectPositive(problems, `{path}.sway.hz`, sway.hz)
		end
	end

	-- Squeeze timeline: contiguous phases from 0 ms, inside the deformer limits (§9.3, §9.6).
	local squeeze = Anim.squeeze
	local cursor = 0
	for index, phase in squeeze.phases do
		local path = `{p}.squeeze.phases[{index}]`
		expect(
			problems,
			phase.startMs == cursor and phase.endMs > phase.startMs,
			`{path} must start where the previous phase ends ({cursor} ms) and last > 0 ms`
		)
		cursor = phase.endMs
		expect(
			problems,
			phase.c >= 1 - deform.maxSquash,
			`{path}.c ({phase.c}) squashes more than deform.maxSquash ({deform.maxSquash}) allows`
		)
		expectBetween(problems, `{path}.w`, phase.w, deform.scaleMin, deform.scaleMax)
	end
	expect(problems, #squeeze.phases >= 1, `{p}.squeeze.phases must list at least one phase`)
	expect(
		problems,
		squeeze.foamRecoveryMin > 0 and squeeze.foamRecoveryMin <= squeeze.foamRecoveryMax,
		`{p}.squeeze must satisfy 0 < foamRecoveryMin <= foamRecoveryMax`
	)
	for _, rarity in rarities do
		local flourish = squeeze.flourish[rarity]
		local path = `{p}.squeeze.flourish.{rarity}`
		if flourish == nil then
			add(problems, `{path} is missing`)
		else
			expectCount(problems, `{path}.particles`, flourish.particles, 0)
			expect(
				problems,
				flourish.particles <= Vfx.Effects.squeezePuffs,
				`{path}.particles ({flourish.particles}) exceeds Config.Vfx.Effects.squeezePuffs ({Vfx.Effects.squeezePuffs})`
			)
		end
	end

	local particles = squeeze.particles
	expect(
		problems,
		particles.lifetimeMin > 0 and particles.lifetimeMin <= particles.lifetimeMax,
		`{p}.squeeze.particles must satisfy 0 < lifetimeMin <= lifetimeMax`
	)
	expect(
		problems,
		particles.speedMin >= 0 and particles.speedMin <= particles.speedMax,
		`{p}.squeeze.particles must satisfy 0 <= speedMin <= speedMax`
	)
	expectBetween(problems, `{p}.squeeze.particles.spreadDeg`, particles.spreadDeg, 0, 180)
	for _, name in sortedKeys(squeeze.squeezeFx) do
		local fx = squeeze.squeezeFx[name]
		local path = `{p}.squeeze.squeezeFx.{name}`
		expectBetween(problems, `{path}.rigidity`, fx.rigidity, 0, 1)
		expectCount(problems, `{path}.steamPuffs`, fx.steamPuffs, 0)
		expect(
			problems,
			fx.steamSpeedMin >= 0 and fx.steamSpeedMin <= fx.steamSpeedMax,
			`{path} must satisfy 0 <= steamSpeedMin <= steamSpeedMax`
		)
	end

	local held = Anim.held
	expect(problems, held.buildStuds < held.destroyStuds, `{p}.held.buildStuds must be below destroyStuds`)
	expectPositive(problems, `{p}.held.idlePeriodSeconds`, held.idlePeriodSeconds)
	expectPositive(problems, `{p}.held.rangeCheckSeconds`, held.rangeCheckSeconds)

	local throw = Anim.throw
	expect(
		problems,
		throw.timeWarpMin > 0 and throw.timeWarpMin <= 1 and throw.timeWarpMax >= 1,
		`{p}.throw must satisfy 0 < timeWarpMin <= 1 <= timeWarpMax`
	)
	expect(
		problems,
		throw.releaseSnapMs < throw.followEndMs and throw.followEndMs < throw.returnEndMs,
		`{p}.throw must satisfy releaseSnapMs < followEndMs < returnEndMs`
	)
	expectBetween(problems, `{p}.throw.windupReachFraction`, throw.windupReachFraction, 0, 1)

	local elimination = Anim.elimination
	expectBoolean(problems, `{p}.elimination.epicEnabled`, elimination.epicEnabled)
	expect(
		problems,
		elimination.flinchEndMs < elimination.dizzyEndMs and elimination.dizzyEndMs < elimination.endMs,
		`{p}.elimination must satisfy flinchEndMs < dizzyEndMs < endMs`
	)
	-- The confetti + sparkles budget is feel pass rule F2 (checkEliminationBudget).

	local box = Anim.boxReveal
	expect(
		problems,
		box.dropMs > 0 and box.autoTapS > 0 and box.taps >= 1 and box.resultAtS > box.toy.fromS,
		`{p}.boxReveal needs dropMs > 0, autoTapS > 0, taps >= 1 and resultAtS > toy.fromS`
	)
	expectBetween(problems, `{p}.boxReveal.orbit.damping`, box.orbit.damping, 0, 1)
	expectBetween(problems, `{p}.boxReveal.resultInputGuardMs`, box.resultInputGuardMs, 0, 1000)
end

-- The damped frequency (Hz) of x'' = -k x - c x'.
local function dampedHz(k: number, c: number): number
	local omega = math.sqrt(k)
	local zeta = c / (2 * omega)
	return omega * math.sqrt(math.max(0, 1 - zeta * zeta)) / (2 * math.pi)
end

-- A spring (k, c) at `path` wobbles at most MAX_FLICKER_HZ.
local function expectCalmSpring(problems: Problems, path: string, k: unknown, c: unknown)
	if isNumber(k) and (k :: number) > 0 and isNumber(c) then
		local hz = dampedHz(k :: number, c :: number)
		expect(problems, hz <= MAX_FLICKER_HZ + FEEL_SLACK, `{path} wobbles at {hz} Hz, above {MAX_FLICKER_HZ} Hz`)
	end
end

-- Squishy overhaul (spec 2026-10-09 §3.2, §6): one blueprint's motion row (the §6 ranges, a known feel and flight
-- style, its release spring <= 3 Hz).
local function checkMotion(problems: Problems, path: string, motion: any)
	local squeeze = if type(motion) == "table" then motion.squeeze else nil
	if type(squeeze) ~= "table" then
		add(problems, `{path} needs a squeeze row`)
		return
	end
	for _, field in MOTION_FIELDS do
		local range = MOTION_RANGES[field]
		expectBetween(problems, `{path}.squeeze.{field}`, squeeze[field], range[1], range[2])
	end
	expectCalmSpring(problems, `{path}.squeeze (kRel, cRel)`, squeeze.kRel, squeeze.cRel)
	expect(
		problems,
		type(motion.feel) == "string" and Anim.rig.feels[motion.feel] ~= nil,
		`{path}.feel {show(motion.feel)} is not a Config.Anim.rig.feels entry`
	)
	local flight = motion.flight
	local style = if type(flight) == "table" then flight.style else nil
	expect(
		problems,
		type(style) == "string" and Anim.rig.flight[style] ~= nil,
		`{path}.flight.style {show(style)} is not a Config.Anim.rig.flight style`
	)
	if type(flight) == "table" then
		if flight.amp ~= nil then
			expectBetween(problems, `{path}.flight.amp`, flight.amp, 0, 1.5)
		end
		if flight.pulse ~= nil then
			expectBetween(problems, `{path}.flight.pulse`, flight.pulse, 1, 1.3)
		end
	end
end

-- Squishy overhaul (spec 2026-10-09 §3.2): the SquishRig block. Every motion <= MAX_FLICKER_HZ (flaps <=
-- MAX_FLAP_HZ, spins <= MAX_ROLL_DEG_PER_SECOND), the face held long enough for that, the kicks inside their caps, the
-- flight fallbacks equal today's Catalog spins and the press twist one slow half-swing.
local function checkRig(problems: Problems)
	local p = "Config.Anim.rig"
	local rig = Anim.rig
	for _, name in sortedKeys(rig.feels) do
		local feel = rig.feels[name]
		eachField(problems, `{p}.feels.{name}`, feel, { "k", "c", "gain" }, expectPositive)
		expectCalmSpring(problems, `{p}.feels.{name}`, feel.k, feel.c)
	end
	eachField(problems, p, rig, { "releaseKick", "releaseKickMax", "hitKick" }, expectPositive)
	local maxJ = Anim.held.motionJiggle.maxJ
	expect(
		problems,
		rig.releaseKickMax <= maxJ + FEEL_SLACK,
		`{p}.releaseKickMax ({show(rig.releaseKickMax)}) must not exceed Config.Anim.held.motionJiggle.maxJ ({maxJ})`
	)
	local Kit = loadSibling("Art/SquishyBlueprints/Kit")
	if Kit ~= nil and isNumber(Kit.JIGGLE_CAP) then
		expect(
			problems,
			rig.hitKick <= Kit.JIGGLE_CAP + FEEL_SLACK,
			`{p}.hitKick ({show(rig.hitKick)}) must not exceed Art/SquishyBlueprints/Kit.JIGGLE_CAP ({Kit.JIGGLE_CAP})`
		)
	end

	local face = rig.face
	expect(
		problems,
		face.squishBelow > 0 and face.squishBelow < face.squishAbove and face.squishAbove <= 1,
		`{p}.face must satisfy 0 < squishBelow < squishAbove <= 1`
	)
	expect(
		problems,
		isNumber(face.minHoldSeconds) and face.minHoldSeconds * 2 * MAX_FLICKER_HZ >= 1 - FEEL_SLACK,
		`{p}.face.minHoldSeconds ({show(face.minHoldSeconds)}) must be >= 1 / (2 × {MAX_FLICKER_HZ}) s (no face `
			.. `flicker above {MAX_FLICKER_HZ} Hz)`
	)
	eachField(problems, `{p}.face`, face, { "hitSeconds", "wowSeconds" }, expectPositive)
	local blink = rig.blink
	expect(
		problems,
		blink.minSeconds > 0 and blink.minSeconds <= blink.maxSeconds and blink.seconds > 0,
		`{p}.blink must satisfy 0 < minSeconds <= maxSeconds and seconds > 0`
	)
	expect(
		problems,
		blink.closedY > 0 and blink.closedY < blink.shineHideBelow and blink.shineHideBelow <= 1,
		`{p}.blink must satisfy 0 < closedY < shineHideBelow <= 1`
	)
	expectNonNegative(problems, `{p}.looks.cheekPuff`, rig.looks.cheekPuff)
	expectPositive(problems, `{p}.looks.wowEye`, rig.looks.wowEye)

	local sections = rig.sections
	eachField(problems, `{p}.sections`, sections, { "k", "c", "gain", "maxDeg" }, expectPositive)
	expectCalmSpring(problems, `{p}.sections`, sections.k, sections.c)
	expectBetween(problems, `{p}.sections.maxDeg`, sections.maxDeg, 0, 90)

	for _, name in sortedKeys(rig.flight) do
		local style = rig.flight[name]
		local path = `{p}.flight.{name}`
		for _, field in { "wobbleHz", "nodHz", "pulseHz" } do
			local hz = style[field]
			if hz ~= nil then
				expectBetween(problems, `{path}.{field}`, hz, 0, MAX_FLICKER_HZ)
			end
		end
		if style.flapHz ~= nil then
			expectBetween(problems, `{path}.flapHz`, style.flapHz, 0, MAX_FLAP_HZ)
		end
		if style.rollDegPerSecond ~= nil then
			expectBetween(problems, `{path}.rollDegPerSecond`, style.rollDegPerSecond, 0, MAX_ROLL_DEG_PER_SECOND)
		end
		for _, field in { "wobbleDeg", "nodDeg", "flapDeg" } do
			if style[field] ~= nil then
				expectBetween(problems, `{path}.{field}`, style[field], 0, 45)
			end
		end
		if style.pulseAmp ~= nil then
			expectBetween(problems, `{path}.pulseAmp`, style.pulseAmp, 0, 0.3)
		end
	end
	local throw = Anim.throw
	local wobble, roll = rig.flight.wobble, rig.flight.roll
	expect(
		problems,
		wobble ~= nil and wobble.wobbleDeg == throw.wobbleRollDeg,
		`{p}.flight.wobble must be today's Catalog "wobble" (Config.Anim.throw.wobbleRollDeg {throw.wobbleRollDeg})`
	)
	expect(
		problems,
		roll ~= nil and roll.rollDegPerSecond == throw.rollDegPerSecond,
		`{p}.flight.roll must be today's Catalog "roll" (Config.Anim.throw.rollDegPerSecond {throw.rollDegPerSecond})`
	)

	-- The press twist is one half-swing from the anticipation end to the peak (the widening end).
	local phases = Anim.squeeze.phases
	for _, rarity in sortedKeys(Anim.squeeze.flourish) do
		local flourish = Anim.squeeze.flourish[rarity]
		local path = `Config.Anim.squeeze.flourish.{rarity}`
		if flourish.releaseKick ~= nil then
			expectBetween(problems, `{path}.releaseKick`, flourish.releaseKick, 1, 2)
		end
		if flourish.sectionFlareDeg ~= nil then
			expectBetween(problems, `{path}.sectionFlareDeg`, flourish.sectionFlareDeg, 0, sections.maxDeg)
		end
		if flourish.twistDeg ~= nil and #phases >= 2 then
			local shift, peakC, peakMs = 0, math.huge, 0
			for _, phase in phases do
				if phase.name == "widening" then
					shift += flourish.wideningExtraMs or 0
				end
				if phase.c < peakC then
					peakC, peakMs = phase.c, phase.endMs + shift
				end
			end
			local hz = 1000 / (2 * math.max(peakMs - phases[1].endMs, 1))
			expect(problems, hz <= MAX_FLICKER_HZ + FEEL_SLACK, `{path}.twistDeg swings at {hz} Hz, above 3 Hz`)
		end
	end
end

-- First person (spec 2026-10-10 §4.1): the ranges, every spring and the idle drift <= MAX_FLICKER_HZ.
-- Design fidelity (spec 2026-10-11 §3): the light and colours are Color3s; the arm has hand, thumb, forearm, cuff and
-- sleeve once each, every size > 0, exponent >= 1 and colour a colours key; the outline, held toy, pop-in, squeeze,
-- focus, shake, throw extras and Dragon charge in range.
local function checkFirstPerson(problems: Problems)
	local p = "Config.FirstPerson"
	local fp: any = FirstPerson
	local function expectVector(path: string, value: unknown, positive: boolean?)
		local ok = typeof(value) == "Vector3"
		if ok and positive then
			local v = value :: Vector3
			ok = v.X > 0 and v.Y > 0 and v.Z > 0
		end
		expect(
			problems,
			ok,
			`{path} must be a Vector3{if positive then " with every side > 0" else ""} (got {show(value)})`
		)
	end
	local function expectSpring(path: string, spring: any)
		local k, c =
			if type(spring) == "table" then spring[1] else nil, if type(spring) == "table" then spring[2] else nil
		expectPositive(problems, `{path}[1] (k)`, k)
		expectNonNegative(problems, `{path}[2] (c)`, c)
		expectCalmSpring(problems, path, k, c)
	end

	expectBoolean(problems, `{p}.defaultOn`, fp.defaultOn)
	for _, name in { "gui", "padGui" } do
		local gui = fp[name]
		expect(problems, isInteger(gui.displayOrder), `{p}.{name}.displayOrder must be an integer`)
		expect(problems, typeof(gui.insets) == "EnumItem", `{p}.{name}.insets must be an Enum.ScreenInsets item`)
	end
	expectCount(problems, `{p}.touchGuiFallbackOrder`, fp.touchGuiFallbackOrder, 0)
	local axis = fp.squeezeAxis
	expect(
		problems,
		axis == "X" or axis == "Y" or axis == "Z",
		`{p}.squeezeAxis must be "X", "Y" or "Z" ({show(axis)})`
	)
	eachField(problems, p, fp, { "practiceExitDelaySeconds", "overlayStudsPerDu", "toyLongestDu" }, expectPositive)
	expectBetween(problems, `{p}.fovDeg`, fp.fovDeg, 1, 120)
	expectNonNegative(problems, `{p}.resultHoldSeconds`, fp.resultHoldSeconds)
	expectBetween(problems, `{p}.countdownPitchDeg`, fp.countdownPitchDeg, -90, 90)
	for _, name in { "invulnTransparency", "ownRingScale", "victimImpactScale" } do
		expectBetween(problems, `{p}.{name}`, fp[name], 0, 1)
	end
	for _, name in { "nearFade", "rushFadeIn" } do
		local band = fp[name]
		expect(
			problems,
			isNumber(band.from) and isNumber(band.to) and band.from >= 0 and band.from < band.to,
			`{p}.{name} must satisfy 0 <= from < to`
		)
	end

	-- Poses (du).
	for _, name in { "rest", "shoulder", "equipFrom" } do
		expectVector(`{p}.{name}`, fp[name])
	end

	-- Motion: every spring and wobble <= 3 Hz.
	for _, name in sortedKeys(fp.springs) do
		expectSpring(`{p}.springs.{name}`, fp.springs[name])
	end
	local idle = fp.idle
	eachField(problems, `{p}.idle`, idle, { "x", "y", "breath", "kickY", "kickPitch" }, expectNonNegative)
	expectBetween(problems, `{p}.idle.xHz`, idle.xHz, 0, MAX_FLICKER_HZ)
	expectBetween(problems, `{p}.idle.yHz`, idle.yHz, 0, MAX_FLICKER_HZ)
	expectBetween(problems, `{p}.idle.breathRate`, idle.breathRate, 0, 2 * math.pi * MAX_FLICKER_HZ)
	expect(problems, isNumber(fp.kick.release), `{p}.kick.release must be a number`)

	-- The 3D Lab design port (spec 2026-10-11 §3).
	local function expectColour(path: string, value: unknown)
		expect(problems, typeof(value) == "Color3", `{path} must be a Color3 (got {show(value)})`)
	end
	local light = fp.light
	for _, name in { "sky", "ground", "key", "viewportAmbient", "viewportLight" } do
		expectColour(`{p}.light.{name}`, light[name])
	end
	eachField(problems, `{p}.light`, light, { "hemisphere", "keyIntensity" }, expectNonNegative)
	expect(
		problems,
		typeof(light.keyFrom) == "Vector3" and (light.keyFrom :: Vector3).Magnitude > 0,
		`{p}.light.keyFrom must be a non-zero Vector3`
	)
	for _, name in { "skin", "cuff", "sleeve" } do
		expectColour(`{p}.colours.{name}`, fp.colours[name])
	end
	for _, side in { "A", "B" } do
		expectColour(`{p}.teamSleeves.{side}`, fp.teamSleeves[side])
	end
	-- The arm: hand, thumb, forearm, cuff and sleeve once each.
	local armParts = { hand = true, thumb = true, forearm = true, cuff = true, sleeve = true }
	local arm = fp.arm
	local seen: { [string]: boolean } = {}
	for index, part in arm.parts do
		local path = `{p}.arm.parts[{index}]`
		local known = armParts[part.name] == true
		expect(
			problems,
			known and not seen[part.name],
			`{path}.name {show(part.name)} must be one of hand, thumb, forearm, cuff, sleeve, each once`
		)
		if known then
			seen[part.name] = true
		end
		expectVector(`{path}.size`, part.size, true)
		expect(
			problems,
			isNumber(part.exponent) and part.exponent >= 1,
			`{path}.exponent must be a number >= 1 (got {show(part.exponent)})`
		)
		expect(
			problems,
			type(part.colour) == "string" and fp.colours[part.colour] ~= nil,
			`{path}.colour {show(part.colour)} is not a Config.FirstPerson.colours key`
		)
		expectVector(`{path}.pos`, part.pos)
		expectVector(`{path}.rot`, part.rot)
	end
	for _, name in sortedKeys(armParts) do
		expect(problems, seen[name] == true, `{p}.arm.parts has no {name}`)
	end
	expectCount(problems, `{p}.arm.segments[1]`, arm.segments[1], 3)
	expectCount(problems, `{p}.arm.segments[2]`, arm.segments[2], 2)
	expectVector(`{p}.arm.startPos`, arm.startPos)
	expectNonNegative(problems, `{p}.arm.roll`, arm.roll)
	local outline = fp.outline
	expectColour(`{p}.outline.colour`, outline.colour)
	eachField(problems, `{p}.outline`, outline, { "px", "refHeightPx", "refDepthDu" }, expectPositive)
	-- The player's own arms (Anim/OwnArm).
	local own = fp.ownArms
	expect(problems, type(own) == "table", `{p}.ownArms must be a table`)
	if type(own) == "table" then
		expect(
			problems,
			type(own.enabled) == "boolean",
			`{p}.ownArms.enabled must be a boolean (got {show(own.enabled)})`
		)
		eachField(
			problems,
			`{p}.ownArms`,
			own,
			{ "handWidthDu", "reachDu", "maxWidthDu", "maxHandLengthDu", "minPartStuds", "recheckSeconds" },
			expectPositive
		)
		expect(
			problems,
			isNumber(own.maxStretch) and own.maxStretch >= 1,
			`{p}.ownArms.maxStretch must be a number >= 1 (got {show(own.maxStretch)})`
		)
		expect(
			problems,
			isNumber(own.maxTransparency) and own.maxTransparency > 0 and own.maxTransparency <= 1,
			`{p}.ownArms.maxTransparency must be in (0, 1] (got {show(own.maxTransparency)})`
		)
		expect(problems, isNumber(own.palmRoll), `{p}.ownArms.palmRoll must be a number (got {show(own.palmRoll)})`)
	end
	-- The held toy, pop-in, squeeze, focus, shake, throw extras and Dragon charge.
	local held = fp.held
	expectVector(`{p}.held.pos`, held.pos)
	expectVector(`{p}.held.rot`, held.rot)
	expectNonNegative(problems, `{p}.held.sideGap`, held.sideGap)
	expect(problems, isNumber(held.sideY) and isNumber(held.sideZ), `{p}.held.sideY / sideZ must be numbers`)
	eachField(problems, `{p}.equip`, fp.equip, { "seconds", "backOutC" }, expectPositive)
	expect(
		problems,
		isNumber(fp.equip.minScale) and fp.equip.minScale > 0 and fp.equip.minScale < 1,
		`{p}.equip.minScale must be in (0, 1)`
	)
	local squeeze = fp.squeeze
	expectBetween(problems, `{p}.squeeze.inset`, squeeze.inset, 0, 1)
	expectBetween(problems, `{p}.squeeze.toyTremorShare`, squeeze.toyTremorShare, 0, 1)
	expect(problems, isNumber(squeeze.y) and isNumber(squeeze.z), `{p}.squeeze.y / z must be numbers`)
	eachField(
		problems,
		`{p}.squeeze`,
		squeeze,
		{ "rollPress", "tremorAfterSeconds", "tremor", "shake" },
		expectNonNegative
	)
	eachField(problems, `{p}.squeeze`, squeeze, { "tremorRateL", "tremorRateR", "toyTremorRate" }, expectPositive)
	local focus = fp.focus
	expectVector(`{p}.focus.pos`, focus.pos)
	expectVector(`{p}.focus.rot`, focus.rot)
	expectNonNegative(problems, `{p}.focus.lingerSeconds`, focus.lingerSeconds)
	expect(problems, isNumber(focus.worldFovTarget), `{p}.focus.worldFovTarget must be a number`)
	expectPositive(problems, `{p}.focus.worldFovPerUnit`, focus.worldFovPerUnit)
	expectPositive(problems, `{p}.shake.decayPerSecond`, fp.shake.decayPerSecond)
	expectNonNegative(problems, `{p}.shake.radPerShakeSq`, fp.shake.radPerShakeSq)
	local throwFx = fp.throwFx
	eachField(problems, `{p}.throwFx`, throwFx, {
		"rollCocked",
		"fovKick",
		"shake",
		"shoveJitter",
		"shoveShake",
		"slingShake",
		"slingFrom",
		"dragonRoarShake",
	}, expectNonNegative)
	expect(problems, isNumber(throwFx.rollL), `{p}.throwFx.rollL must be a number`)
	expectPositive(problems, `{p}.throwFx.shoveUntil`, throwFx.shoveUntil)
	expect(
		problems,
		isNumber(throwFx.slingFrom) and isNumber(throwFx.slingUntil) and throwFx.slingFrom < throwFx.slingUntil,
		`{p}.throwFx must satisfy slingFrom < slingUntil`
	)
	-- The squeeze tremor (47-53 rad/s), the Dragon wobble (40) and glow pulse (30) are the design's own and above
	-- MAX_FLICKER_HZ: kept as spec 2026-10-11 §3.4 / §3.6 port them (the tremor is about 1 px and off under
	-- ReducedMotion), so they are not checked against it.
	local ult = fp.ult
	expectVector(`{p}.ult.pos`, ult.pos)
	expect(problems, isNumber(ult.pitch), `{p}.ult.pitch must be a number`)
	eachField(
		problems,
		`{p}.ult`,
		ult,
		{ "wobble", "jitter", "glowPulse", "shake", "fovPullPerSecond", "releaseFovKick", "releaseShake" },
		expectNonNegative
	)
	expect(problems, isNumber(ult.releaseKick), `{p}.ult.releaseKick must be a number`)
	eachField(problems, `{p}.ult`, ult, { "wobbleRate", "glowRadius", "glowPulseRate", "glowFadeRate" }, expectPositive)
	expectBetween(problems, `{p}.ult.squashY`, ult.squashY, 0, 1)
	expectBetween(problems, `{p}.ult.glowOpacity`, ult.glowOpacity, 0, 1)
	expectColour(`{p}.ult.glowColour`, ult.glowColour)
end

-- Squeeze feel (spec phase2-squeeze §3.11): Config.Knead has a row for every Config.Anim.rig feel, every share, time
-- and gain in range, and every spring and rhythm <= MAX_FLICKER_HZ. Jelly's per-vertex knead spring (k 520, c 7)
-- wobbles at 3.59 Hz: the design's own "springs straight back and wobbles" (squish.js:31), kept as decided (spec
-- phase2 §3.13-6, 2026-10-11), so it is not checked against MAX_FLICKER_HZ.
local KNEAD_SPRING_EXCEPTIONS: { [string]: boolean } = { jelly = true }

local function checkKnead(problems: Problems)
	local p = "Config.Knead"
	local knead: any = Knead
	for _, feel in sortedKeys(Anim.rig.feels) do
		local row = knead.feels[feel]
		local path = `{p}.feels.{feel}`
		if type(row) ~= "table" then
			add(problems, `{path} is missing (every Config.Anim.rig feel needs one)`)
			continue
		end
		eachField(problems, path, row, { "rise", "k", "gamma", "pull", "pullR" }, expectPositive)
		eachField(problems, path, row, { "c", "beta", "smear", "neck" }, expectNonNegative)
		for _, field in { "fast", "plastic", "lump" } do
			expectBetween(problems, `{path}.{field}`, row[field], 0, 1)
		end
		if not KNEAD_SPRING_EXCEPTIONS[feel] then
			expectCalmSpring(problems, `{path} (k, c)`, row.k, row.c)
		end
	end
	expect(
		problems,
		type(knead.defaultFeel) == "string" and knead.feels[knead.defaultFeel] ~= nil,
		`{p}.defaultFeel {show(knead.defaultFeel)} is not a Config.Knead.feels entry`
	)
	expectCount(problems, `{p}.brushSlots`, knead.brushSlots, 1)
	local finger, palm, thumb = knead.finger, knead.palm, knead.thumb
	eachField(problems, `{p}.finger`, finger, { "radius", "depthOfRadius", "depthOfMinDim", "falloff" }, expectPositive)
	eachField(
		problems,
		`{p}.palm`,
		palm,
		{ "radius", "falloff", "depthOfX", "depthOfSqueeze", "power" },
		expectPositive
	)
	eachField(problems, `{p}.thumb`, thumb, { "radius", "falloff", "depthOfRadius", "depthOfMinDim" }, expectPositive)
	expectBetween(problems, `{p}.palm.betaShare`, palm.betaShare, 0, 1)
	expectBetween(problems, `{p}.thumb.betaShare`, thumb.betaShare, 0, 1)
	local depth = knead.depth
	eachField(
		problems,
		`{p}.depth`,
		depth,
		{ "riseFinger", "risePalm", "creepSeconds", "substepsPerSecond", "retireDepth", "retireSpeed" },
		expectPositive
	)
	eachField(problems, `{p}.depth`, depth, { "delayFinger", "delayPalm" }, expectNonNegative)
	expectBetween(problems, `{p}.depth.settle`, depth.settle, 0, 1)
	local spring = depth.spring
	local k, c = if type(spring) == "table" then spring[1] else nil, if type(spring) == "table" then spring[2] else nil
	expectPositive(problems, `{p}.depth.spring[1] (k)`, k)
	expectNonNegative(problems, `{p}.depth.spring[2] (c)`, c)
	expectCalmSpring(problems, `{p}.depth.spring`, k, c)
	local memory = knead.memory
	eachField(
		problems,
		`{p}.memory`,
		memory,
		{ "stampSpacing", "maxStrokeOfRadius", "smearSideways", "capOfRadius" },
		expectPositive
	)
	expectBetween(problems, `{p}.memory.keepBelow`, memory.keepBelow, 0, 1)
	expectBetween(problems, `{p}.memory.smearMin`, memory.smearMin, 0, 1)
	eachField(
		problems,
		p,
		knead,
		{ "lumpScale", "springSubstepsPerSecond", "restEpsilon", "movingEpsilon", "sleepSeconds" },
		expectPositive
	)
	expectPositive(problems, `{p}.bulge.rate`, knead.bulge.rate)
	expect(
		problems,
		isNumber(knead.bulge.dentShare) and knead.bulge.dentShare > 0 and knead.bulge.dentShare <= 1,
		`{p}.bulge.dentShare must be in (0, 1] (got {show(knead.bulge.dentShare)})`
	)
	local pull = knead.pull
	eachField(problems, `{p}.pull`, pull, { "slip", "radiusGrowth", "neckGain" }, expectPositive)
	for _, field in { "tug", "plasticMin", "plasticWeightMin" } do
		expectBetween(problems, `{p}.pull.{field}`, pull[field], 0, 1)
	end
	-- The crunch presses once a period: a rhythm, so at most MAX_FLICKER_HZ presses a second.
	local crunch = knead.crunch
	expect(
		problems,
		isNumber(crunch.period) and crunch.period > 0 and 1 / crunch.period <= MAX_FLICKER_HZ + FEEL_SLACK,
		`{p}.crunch.period ({show(crunch.period)}) must be > 0 with at most {MAX_FLICKER_HZ} presses a second`
	)
	expect(
		problems,
		isNumber(crunch.pressEnd)
			and isNumber(crunch.holdEnd)
			and crunch.pressEnd > 0
			and crunch.pressEnd <= crunch.holdEnd
			and crunch.holdEnd < 1,
		`{p}.crunch must satisfy 0 < pressEnd <= holdEnd < 1`
	)
	for _, field in { "low", "releaseDrop", "startAmount", "frontMinZ" } do
		expectBetween(problems, `{p}.crunch.{field}`, crunch[field], 0, 1)
	end
	eachField(
		problems,
		`{p}.crunch`,
		crunch,
		{ "follow", "gap", "spanX", "spanY", "releaseRate", "releaseMinRise", "snap" },
		expectPositive
	)
	eachField(problems, `{p}.crunch`, crunch, { "jitterU", "jitterV", "slide", "height" }, expectNonNegative)
	expect(
		problems,
		isNumber(crunch.slide) and isNumber(crunch.gap) and crunch.slide < crunch.gap,
		`{p}.crunch.slide must be < gap (the thumbs never cross)`
	)
	local pinch = knead.pinch
	for _, field in sortedKeys(pinch) do
		expectNonNegative(problems, `{p}.pinch.{field}`, pinch[field])
	end
	eachField(problems, `{p}.pinch`, pinch, { "dipSpan", "frontSpan", "pullIn" }, expectPositive)
	for _, name in sortedKeys(knead.kicks) do
		local kick = knead.kicks[name]
		for _, field in sortedKeys(kick) do
			expect(
				problems,
				isNumber(kick[field]),
				`{p}.kicks.{name}.{field} must be a number (got {show(kick[field])})`
			)
		end
	end
	for _, field in sortedKeys(knead.sounds) do
		expectBetween(problems, `{p}.sounds.{field}`, knead.sounds[field], 0, 1)
	end
	local face = knead.face
	expect(
		problems,
		isNumber(face.palmOn)
			and isNumber(face.palmOff)
			and face.palmOff > 0
			and face.palmOff <= face.palmOn
			and face.palmOn <= 1,
		`{p}.face must satisfy 0 < palmOff <= palmOn <= 1`
	)
	eachField(
		problems,
		`{p}.face`,
		face,
		{ "fingerDepth", "reach", "pull", "crunch", "fallbackRadius", "minRadius" },
		expectPositive
	)
	expectNonNegative(problems, `{p}.face.fallbackLift`, face.fallbackLift)
	-- The soft shell: a budget below one closed grid of 2 cuts a side (26 vertices) builds nothing smaller.
	local shell = knead.shell
	expectCount(problems, `{p}.shell.minSegments`, shell.minSegments, 1)
	expectCount(problems, `{p}.shell.lowVertices`, shell.lowVertices, 26)
	expectCount(problems, `{p}.shell.highVertices`, shell.highVertices, 26)
	expect(
		problems,
		isNumber(shell.lowVertices) and isNumber(shell.highVertices) and shell.lowVertices <= shell.highVertices,
		`{p}.shell.lowVertices must not exceed highVertices`
	)
	eachField(problems, `{p}.shell`, shell, { "anchorReach", "anchorLeg" }, expectPositive)
	expectCount(problems, `{p}.shell.atlas.High`, shell.atlas.High, 1)
	expectCount(problems, `{p}.shell.atlas.Low`, shell.atlas.Low, 1)
	expectNonNegative(problems, `{p}.shell.gutterTexels`, shell.gutterTexels)
end

-- Squeeze feel (spec phase2-squeeze §3.11): Config.Wax has a coat for every Config.Anim.rig feel, the cell, stress and
-- crack rules in range, and the line reveal steps in order. User 2026-10-12: its switch `enabled` is a boolean.
local function checkWax(problems: Problems)
	local p = "Config.Wax"
	local wax: any = Wax
	expectBoolean(problems, `{p}.enabled`, wax.enabled)
	for _, feel in sortedKeys(Anim.rig.feels) do
		local coat = wax.coats[feel]
		local path = `{p}.coats.{feel}`
		if type(coat) ~= "table" then
			add(problems, `{path} is missing (every Config.Anim.rig feel needs one)`)
			continue
		end
		eachField(problems, path, coat, { "cell", "th" }, expectPositive)
		expectNonNegative(problems, `{path}.gloss`, coat.gloss)
		expect(
			problems,
			isNumber(coat.wear) and coat.wear > 0 and coat.wear <= 1,
			`{path}.wear must be in (0, 1] (got {show(coat.wear)})`
		)
	end
	expectPositive(problems, `{p}.thScale`, wax.thScale)
	local cells = wax.cells
	eachField(problems, `{p}.cells`, cells, { "spacing", "neighbourRadius", "footprintRadius" }, expectPositive)
	expectCount(problems, `{p}.cells.maxCells`, cells.maxCells, 1)
	expectNonNegative(problems, `{p}.cells.thSpread`, cells.thSpread)
	local stress = wax.stress
	expectPositive(problems, `{p}.stress.relax`, stress.relax)
	expectNonNegative(problems, `{p}.stress.bend`, stress.bend)
	expectBetween(problems, `{p}.stress.worn`, stress.worn, 0, 1)
	local cracks = wax.cracks
	expect(
		problems,
		isNumber(cracks.energyMin)
			and isNumber(cracks.energyMax)
			and cracks.energyMin > 0
			and cracks.energyMin < cracks.energyMax,
		`{p}.cracks must satisfy 0 < energyMin < energyMax`
	)
	expectNonNegative(problems, `{p}.cracks.energySpread`, cracks.energySpread)
	for _, field in { "energyWorn", "dropMin", "crunchinessRate", "damage", "cascade" } do
		expectBetween(problems, `{p}.cracks.{field}`, cracks[field], 0, 1)
	end
	expectCount(problems, `{p}.cracks.sounding`, cracks.sounding, 1)
	eachField(problems, p, wax, { "driveStrain", "shineDecay" }, expectPositive)
	expectNonNegative(problems, `{p}.shineGain`, wax.shineGain)
	local lines = wax.lines
	for _, field in sortedKeys(lines) do
		expectNonNegative(problems, `{p}.lines.{field}`, lines[field])
	end
	expect(
		problems,
		isNumber(lines.revealLow) and isNumber(lines.revealHigh) and lines.revealLow < lines.revealHigh,
		`{p}.lines.revealLow must be < revealHigh`
	)
	expect(
		problems,
		isNumber(lines.octave2Low) and isNumber(lines.octave2High) and lines.octave2Low < lines.octave2High,
		`{p}.lines.octave2Low must be < octave2High`
	)
	expectBetween(problems, `{p}.lines.skipBelow`, lines.skipBelow, 0, 1)
	expect(
		problems,
		isNumber(lines.alphaStep) and lines.alphaStep > 0 and lines.alphaStep <= 1,
		`{p}.lines.alphaStep must be in (0, 1] (got {show(lines.alphaStep)})`
	)
	expectPositive(problems, `{p}.lines.pointsPerCell`, lines.pointsPerCell)
end

-- Phase 2b, the knead screen in Inspect (spec phase2-squeeze §3.4-§3.11): the knead view inside Inspect's orbit, the
-- flakes, jolt, sparkle, HUD thresholds and crack canvas of Config.Wax, the HUD / vignette / ring layout of
-- Config.UI.Knead and the wax mix of Config.Audio.wax: positives, shares in range, min <= max, the vignette stops in
-- order and the flakes' spin <= MAX_FLICKER_HZ turns a second.
local function checkKneadScreen(problems: Problems)
	local knead: any, wax: any, ui: any, audio: any = Knead, Wax, UI, Audio
	local function expectRange(path: string, low: unknown, high: unknown)
		expect(
			problems,
			isNumber(low) and isNumber(high) and (low :: number) <= (high :: number),
			`{path} must be numbers with min <= max (got {show(low)}, {show(high)})`
		)
	end
	local p = "Config.Knead.view"
	local view = knead.view
	eachField(
		problems,
		p,
		view,
		{ "crunchRate", "homeRate", "settleSeconds", "fitDepth", "toyLongestDu", "cameraFovDeg" },
		expectPositive
	)
	for _, field in { "homePitchRad", "crunchPitchRad" } do
		expectBetween(
			problems,
			`{p}.{field}`,
			view[field],
			math.rad(Inspect.Orbit.pitchMinDeg),
			math.rad(Inspect.Orbit.pitchMaxDeg)
		)
	end
	expectBetween(problems, `{p}.fitWidth`, view.fitWidth, 0, 1)
	expectBetween(problems, `{p}.fitHeight`, view.fitHeight, 0, 1)
	expectBetween(problems, `{p}.cameraFovDeg`, view.cameraFovDeg, 1, 179)
	expectPositive(problems, "Config.Knead.kickVelocity", knead.kickVelocity)
	expectBoolean(problems, "Config.Knead.shell.uvFlipV", knead.shell.uvFlipV)

	p = "Config.Wax.flakes"
	local flakes = wax.flakes
	eachField(problems, p, flakes, {
		"minEnergy",
		"offset",
		"speedMax",
		"sizeMin",
		"lifeMin",
		"drag",
		"spinMin",
		"startAngleMax",
		"chipDepth",
		"popPeak",
		"popArc",
		"fadePower",
	}, expectPositive)
	eachField(problems, p, flakes, { "speedMin", "sideways", "upMin", "depth" }, expectNonNegative)
	for _, field in { "chanceBase", "chanceIntact", "extraChance", "whiten", "zoomShare" } do
		expectBetween(problems, `{p}.{field}`, flakes[field], 0, 1)
	end
	expectRange(`{p}.speedMin / speedMax`, flakes.speedMin, flakes.speedMax)
	expectRange(`{p}.upMin / upMax`, flakes.upMin, flakes.upMax)
	expectRange(`{p}.sizeMin / sizeMax`, flakes.sizeMin, flakes.sizeMax)
	expectRange(`{p}.lifeMin / lifeMax`, flakes.lifeMin, flakes.lifeMax)
	expectRange(`{p}.spinMin / spinMax`, flakes.spinMin, flakes.spinMax)
	expect(
		problems,
		isNumber(flakes.gravity) and flakes.gravity <= 0,
		`{p}.gravity must be <= 0 (it falls; got {show(flakes.gravity)})`
	)
	expect(
		problems,
		isNumber(flakes.spinMax) and flakes.spinMax / (2 * math.pi) <= MAX_FLICKER_HZ,
		`{p}.spinMax ({show(flakes.spinMax)} rad/s) must be <= {MAX_FLICKER_HZ} turns a second`
	)
	expect(problems, type(flakes.chip) == "table" and #flakes.chip >= 3, `{p}.chip must list at least 3 outline radii`)
	for index, radius in (if type(flakes.chip) == "table" then flakes.chip else {}) :: { any } do
		expectPositive(problems, `{p}.chip[{index}]`, radius)
	end
	expect(
		problems,
		isNumber(flakes.popEnd)
			and isNumber(flakes.fadeStart)
			and flakes.popEnd > 0
			and flakes.popEnd < flakes.fadeStart
			and flakes.fadeStart < 1,
		`{p} must satisfy 0 < popEnd < fadeStart < 1`
	)
	expectCount(problems, `{p}.cap`, flakes.cap, 1)
	eachField(problems, "Config.Wax.jolt", wax.jolt, { "minEnergy", "gain", "decay" }, expectPositive)
	expectBetween(problems, "Config.Wax.jolt.intactBase", wax.jolt.intactBase, 0, 1)
	local sparkle = wax.sparkle
	expectCount(problems, "Config.Wax.sparkle.count", sparkle.count, 1)
	eachField(problems, "Config.Wax.sparkle", sparkle, { "speed", "sizeDu", "life", "drag", "spread" }, expectPositive)
	local star = sparkle.star
	expect(
		problems,
		typeof(star) == "Vector3" and star.X > 0 and star.Y > 0 and star.Z > 0,
		"Config.Wax.sparkle.star must be a Vector3 with every side > 0"
	)
	local hud = wax.hud
	expect(
		problems,
		isNumber(hud.crackled)
			and isNumber(hud.crunchy)
			and hud.crackled > 0
			and hud.crackled < hud.crunchy
			and hud.crunchy < 1,
		"Config.Wax.hud must satisfy 0 < crackled < crunchy < 1"
	)
	local canvas = wax.canvas
	expectCount(problems, "Config.Wax.canvas.drawPerFrame", canvas.drawPerFrame, 1)
	eachField(problems, "Config.Wax.canvas.buildMsPerFrame", canvas.buildMsPerFrame, { "High", "Low" }, expectPositive)
	expectBetween(problems, "Config.Wax.canvas.haloFalloff", canvas.haloFalloff, 0, 1)
	local last = 0
	for index, offset in canvas.haloOffsets :: { any } do
		expect(
			problems,
			isInteger(offset) and offset > last,
			`Config.Wax.canvas.haloOffsets[{index}] must be a whole number of px above the one before`
		)
		last = if isNumber(offset) then offset else last
	end

	p = "Config.UI.Knead"
	local hudUi = ui.Knead
	eachField(problems, p, hudUi, {
		"hudGapPx",
		"hudPadX",
		"hudPadY",
		"hudRadius",
		"hudStrokePx",
		"trackWidth",
		"trackHeight",
		"trackStrokePx",
		"stateMinWidth",
		"refreshSeconds",
		"fillMs",
		"vignetteMs",
		"ringPx",
		"ringPressPx",
		"ringPullPx",
		"ringStrokePx",
		"ringOutlinePx",
		"ringSizeMs",
	}, expectPositive)
	eachField(problems, p, hudUi, { "hudTopPx", "hudDropPx" }, expectNonNegative)
	expectBetween(problems, `{p}.countTransparency`, hudUi.countTransparency, 0, 1)
	expectBetween(problems, `{p}.ringPressTransparency`, hudUi.ringPressTransparency, 0, 1)
	expectCount(problems, `{p}.vignetteTexels`, hudUi.vignetteTexels, 2)
	local vignette = hudUi.vignette
	eachField(problems, `{p}.vignette`, vignette, { "rx", "ry" }, expectPositive)
	expectBetween(problems, `{p}.vignette.cx`, vignette.cx, 0, 1)
	expectBetween(problems, `{p}.vignette.cy`, vignette.cy, 0, 1)
	local stops, alphas = vignette.stops, vignette.alphas
	expect(
		problems,
		type(stops) == "table" and type(alphas) == "table" and #stops >= 2 and #stops == #alphas,
		`{p}.vignette needs as many alphas as stops (at least 2)`
	)
	local before = -1
	for index, stop in (if type(stops) == "table" then stops else {}) :: { any } do
		expect(
			problems,
			isNumber(stop) and stop > before and stop <= 1,
			`{p}.vignette.stops[{index}] must rise and stay <= 1`
		)
		before = if isNumber(stop) then stop else before
		expectBetween(problems, `{p}.vignette.alphas[{index}]`, (alphas :: any)[index], 0, 1)
	end

	p = "Config.Audio.wax"
	local mix = audio.wax
	for _, feel in sortedKeys(Anim.rig.feels) do
		expectPositive(problems, `{p}.gain.{feel}`, mix.gain[feel])
		expect(problems, isNumber(mix.sheetLevelDb[feel]), `{p}.sheetLevelDb.{feel} must be a number`)
	end
	for _, field in { "loopLevelDb", "thumpLevelDb", "snapThumpLevelDb", "rewaxLevelDb", "energyDb" } do
		expect(problems, isNumber(mix[field]), `{p}.{field} must be a number (got {show(mix[field])})`)
	end
	eachField(problems, p, mix, {
		"busGain",
		"masterGain",
		"trim",
		"burstSlot",
		"grainStart",
		"grainSlot",
		"grainGain",
		"tapStart",
		"tapSlot",
		"tapGain",
		"tickPower",
		"releaseSpan",
		"airSpanMax",
		"airSpanRise",
		"releaseGain",
		"airGain",
		"fingerTap",
		"pressTapA",
		"pressTapB",
		"thumpGain",
		"snapE",
		"echoE",
		"snapThumpGain",
		"hazeGain",
		"bodyGain",
		"hazeTau",
		"bodyTau",
		"quietHazeTau",
		"quietBodyTau",
		"bedEpsilon",
		"startMax",
	}, expectPositive)
	eachField(problems, p, mix, { "releaseDelay", "airDelay", "echoDelay", "echoShare" }, expectNonNegative)
	for _, field in { "intactBase", "tickGainMin", "tickFade", "releaseExtraChance", "hazeBase", "bodyBase" } do
		expectBetween(problems, `{p}.{field}`, mix[field], 0, 1)
	end
	for _, field in { "burstVariants", "grainCount", "tapCount", "tickGrains", "releaseFinger", "releasePress" } do
		expectCount(problems, `{p}.{field}`, mix[field], 1)
	end
	expect(
		problems,
		isInteger(mix.tickGrains) and isInteger(mix.grainCount) and mix.tickGrains <= mix.grainCount,
		`{p}.tickGrains must not exceed grainCount`
	)
	local ranges = {
		{ "burstSpeedMin", "burstSpeedMax" },
		{ "tickSpeedMin", "tickSpeedMax" },
		{ "airMin", "airMax" },
		{ "fingerSpeedMin", "fingerSpeedMax" },
		{ "pressSpeedAMin", "pressSpeedAMax" },
		{ "pressSpeedBMin", "pressSpeedBMax" },
		{ "pressGapMin", "pressGapMax" },
	}
	for _, pair in ranges do
		expectRange(`{p}.{pair[1]} / {pair[2]}`, mix[pair[1]], mix[pair[2]])
		expectPositive(problems, `{p}.{pair[1]}`, mix[pair[1]])
	end
	for _, list in { "burstEnergies", "burstIntacts" } do
		local values = mix[list]
		expect(problems, type(values) == "table" and #values >= 1, `{p}.{list} must list at least one value`)
		for index, value in (if type(values) == "table" then values else {}) :: { any } do
			expectPositive(problems, `{p}.{list}[{index}]`, value)
		end
	end
	expect(
		problems,
		isNumber(mix.grainStart)
			and isNumber(mix.tapStart)
			and type(mix.burstEnergies) == "table"
			and type(mix.burstIntacts) == "table"
			and #mix.burstEnergies * #mix.burstIntacts * mix.burstVariants * mix.burstSlot <= mix.grainStart + 1e-6
			and mix.grainStart + mix.grainCount * mix.grainSlot <= mix.tapStart + 1e-6,
		`{p}: the bursts, grains and taps of a sheet must not overlap`
	)
	local compressor = (Audio.Groups.Wax :: any).compressor
	expect(problems, type(compressor) == "table", "Config.Audio.Groups.Wax.compressor is missing")
	if type(compressor) == "table" then
		expect(
			problems,
			isNumber(compressor.threshold) and compressor.threshold <= 0,
			"Config.Audio.Groups.Wax.compressor.threshold must be <= 0 dB"
		)
		expect(
			problems,
			isNumber(compressor.ratio) and compressor.ratio >= 1,
			"Config.Audio.Groups.Wax.compressor.ratio must be >= 1"
		)
		eachField(problems, "Config.Audio.Groups.Wax.compressor", compressor, { "attack", "release" }, expectPositive)
		expectNonNegative(problems, "Config.Audio.Groups.Wax.compressor.makeup", compressor.makeup)
	end
	-- User 2026-10-12: the knead's softened let-go ticks with the wax off (one tick in crackleStride, at crackleGain).
	expectCount(problems, "Config.Audio.kneadSoft.crackleStride", Audio.kneadSoft.crackleStride, 1)
	expectBetween(problems, "Config.Audio.kneadSoft.crackleGain", Audio.kneadSoft.crackleGain, 0, 1)
end

local function checkVfx(problems: Problems)
	local p = "Config.Vfx"
	for _, name in sortedKeys(Vfx.Textures) do
		local path = (Vfx.Textures :: any)[name]
		expect(
			problems,
			type(path) == "string" and string.sub(path, 1, 11) == "rbxasset://",
			`{p}.Textures.{name} must be a built-in rbxasset:// path (asset ids live only in AssetTable)`
		)
	end

	local flash = Vfx.Flash
	expectBetween(problems, `{p}.Flash.maxOverlayOpacity`, flash.maxOverlayOpacity, 0, 1)
	expect(
		problems,
		Vfx.Hit.vignetteMaxOpacity <= flash.maxOverlayOpacity,
		`{p}.Hit.vignetteMaxOpacity must not exceed Flash.maxOverlayOpacity ({flash.maxOverlayOpacity})`
	)
	expect(
		problems,
		Vfx.Hit.vignetteInMs >= flash.minPeakMs,
		`{p}.Hit.vignetteInMs must be >= Flash.minPeakMs ({flash.minPeakMs})`
	)

	local shake = Vfx.Shake
	expectBetween(problems, `{p}.Shake.maxAmplitudeDeg`, shake.maxAmplitudeDeg, 0, 1)
	for _, name in { "hitReceived", "eliminated", "dragonRushNearby" } do
		local preset = (shake :: any)[name]
		expectBetween(problems, `{p}.Shake.{name}.amplitudeDeg`, preset.amplitudeDeg, 0, shake.maxAmplitudeDeg)
		expectPositive(problems, `{p}.Shake.{name}.ms`, preset.ms)
	end
	-- §9.12: the shake runs after the camera module (Camera + priorityOffset) and its undo before it, so the module
	-- never builds a frame from a shaken camera (no drift).
	expect(
		problems,
		shake.priorityOffset > 0 and shake.undoPriorityOffset < 0 and shake.bindName ~= shake.undoBindName,
		`{p}.Shake: priorityOffset must be > 0, undoPriorityOffset < 0 and the two bind names different`
	)

	local budgets = Vfx.Budgets
	for _, name in sortedKeys(budgets) do
		expectCount(problems, `{p}.Budgets.{name}`, (budgets :: any)[name], 1)
	end
	expect(
		problems,
		budgets.liveParticlesPerEffect <= budgets.liveParticlesTotal,
		`{p}.Budgets.liveParticlesPerEffect must not exceed liveParticlesTotal`
	)
	expect(problems, budgets.highlights <= MAX_HIGHLIGHTS, `{p}.Budgets.highlights exceeds the engine cap`)
	-- Squishy overhaul detail levels (spec 2026-10-09 §3.2): hero + near fit in the rigs, and phones never get more.
	expect(
		problems,
		budgets.heroRigs + budgets.nearRigs <= budgets.deformingRigs,
		`{p}.Budgets: heroRigs + nearRigs ({budgets.heroRigs + budgets.nearRigs}) must fit in deformingRigs `
			.. `({budgets.deformingRigs})`
	)
	expect(
		problems,
		budgets.heroRigsLow + budgets.nearRigsLow <= budgets.deformingRigsLow,
		`{p}.Budgets: heroRigsLow + nearRigsLow ({budgets.heroRigsLow + budgets.nearRigsLow}) must fit in `
			.. `deformingRigsLow ({budgets.deformingRigsLow})`
	)
	for _, name in { "deformingRigs", "heroRigs", "nearRigs", "flightDetailModels" } do
		local low, high = (budgets :: any)[name .. "Low"], (budgets :: any)[name]
		expect(
			problems,
			isNumber(low) and isNumber(high) and low <= high,
			`{p}.Budgets.{name}Low ({show(low)}) must not exceed {name} ({show(high)})`
		)
	end

	local effects = Vfx.Effects
	for _, name in
		{
			"squeezePuffs",
			"projectileParticles",
			"impactParticles",
			"eliminationParticles",
			"dragonRushParticles",
		}
	do
		local count = (effects :: any)[name]
		expectCount(problems, `{p}.Effects.{name}`, count, 0)
		expect(
			problems,
			isNumber(count) and count <= budgets.liveParticlesPerEffect,
			`{p}.Effects.{name} exceeds Budgets.liveParticlesPerEffect ({budgets.liveParticlesPerEffect})`
		)
	end
	expect(
		problems,
		effects.projectileTrails <= budgets.activeTrails,
		`{p}.Effects.projectileTrails exceeds Budgets.activeTrails`
	)
	expectBetween(problems, `{p}.reducedParticleMultiplier`, Vfx.reducedParticleMultiplier, 0, 1)

	local rush = Vfx.DragonRush
	for _, field in { "indicatorEdgeTransparency", "indicatorFillTransparency", "jawOpenAt" } do
		expectBetween(problems, `{p}.DragonRush.{field}`, (rush :: any)[field], 0, 1)
	end
	expectPositive(problems, `{p}.DragonRush.headScale`, rush.headScale)

	expectCount(problems, `{p}.Pool.idlePerKind`, Vfx.Pool.idlePerKind, 0)
	expectNonNegative(problems, `{p}.Pool.releaseMarginSeconds`, Vfx.Pool.releaseMarginSeconds)

	-- Flight size tolerance (§8.1 #9): a fraction of throw.radius.
	local tolerance = Vfx.Projectile.flightRadiusTolerance
	expect(
		problems,
		isNumber(tolerance) and tolerance > 0 and tolerance < 1,
		`{p}.Projectile.flightRadiusTolerance must be a fraction in (0, 1) (got {show(tolerance)})`
	)

	-- Zone presets (§7.4): ColorCorrectionEffect Contrast/Saturation in [-1, 1], Atmosphere.Density in [0, 1].
	local zones = Vfx.ZonePresets
	expectNonNegative(problems, `{p}.ZonePresets.tweenSeconds`, zones.tweenSeconds)
	local arena = zones.Arena
	expectBetween(problems, `{p}.ZonePresets.Arena.contrast`, arena.contrast, -1, 1)
	expectBetween(problems, `{p}.ZonePresets.Arena.saturation`, arena.saturation, -1, 1)
	expectBetween(problems, `{p}.ZonePresets.Arena.atmosphereDensity`, arena.atmosphereDensity, 0, 1)
end

-- Spec phase 5: the dash's pose clip (Config.Anim.dash) and the effects of the dash and the Epic ultimates
-- (Config.Vfx.Dash, Config.Vfx.Ultimates) keep the joint, flicker, spin and particle limits.
local function checkMoves(problems: Problems)
	local dash = Anim.dash
	local p = "Config.Anim.dash"
	expectPositive(problems, `{p}.priority`, dash.priority)
	expectPositive(problems, `{p}.holdFadeInFrames`, dash.holdFadeInFrames)
	local frames = Duel.Rules.Dash.visualFrames
	for _, key in { "F", "B", "L", "R" } do
		local keys = (dash.keys :: any)[key]
		local path = `{p}.keys.{key}`
		if type(keys) ~= "table" or #keys < 2 then
			add(problems, `{path} must list at least two keys`)
			continue
		end
		expect(problems, keys[1].f == 0 and keys[#keys].f == frames, `{path} must run from frame 0 to {frames}`)
		for index, entry in keys do
			if index > 1 then
				expect(problems, entry.f > keys[index - 1].f, `{path}[{index}].f must come after the key before`)
			end
			expect(problems, isNumber(entry.hold), `{path}[{index}].hold must be a number`)
			checkPoseAngles(problems, `{path}[{index}].angles`, entry.angles, Anim.joints.R15)
		end
	end

	-- The 2026-10-15 overhaul: the dash's ghosts and FOV kick, the afterimages, and the double jump (its move, flip and
	-- effects). The particles themselves are the VFX Studio library's (MoveVfx_Test checks their budgets).
	local fx = Vfx.Dash
	local f = "Config.Vfx.Dash"
	eachField(problems, f, fx, { "ghostEverySeconds", "ghostSeconds", "fovKickAttackMs", "fovKickReleaseMs" }, expectPositive)
	expect(
		problems,
		isInteger(fx.ghosts) and fx.ghosts >= 0 and fx.ghosts <= Vfx.Afterimage.maxLive,
		`{f}.ghosts must be a whole number from 0 to Config.Vfx.Afterimage.maxLive`
	)
	for _, field in { "ghostTransparency", "ghostTintToWhite" } do
		expectBetween(problems, `{f}.{field}`, fx[field], 0, 1)
	end
	expectBetween(problems, `{f}.fovKickDeg`, fx.fovKickDeg, 0, Vfx.Punch.maxFovDeg)
	local ghost = Vfx.Afterimage
	expectBetween(problems, "Config.Vfx.Afterimage.transparency", ghost.transparency, 0, 1)
	expectPositive(problems, "Config.Vfx.Afterimage.seconds", ghost.seconds)
	expectCount(problems, "Config.Vfx.Afterimage.maxLive", ghost.maxLive, 1)

	local jfx = Vfx.DoubleJump
	local jf = "Config.Vfx.DoubleJump"
	eachField(problems, jf, jfx, {
		"bodySeconds",
		"footTrailSeconds",
		"ghostSeconds",
		"whooshPitch",
		"pushPitch",
		"pushVolume",
		"landVolume",
		"landMinSeconds",
		"landSlackStuds",
		"landWithinSeconds",
		"fovKickAttackMs",
		"fovKickReleaseMs",
	}, expectPositive)
	for _, field in { "ghostTransparency", "ghostTintToWhite" } do
		expectBetween(problems, `{jf}.{field}`, jfx[field], 0, 1)
	end
	expectBetween(problems, `{jf}.fovKickDeg`, jfx.fovKickDeg, 0, Vfx.Punch.maxFovDeg)
	expect(problems, jfx.landWithinSeconds > jfx.landMinSeconds, `{jf}.landWithinSeconds must be above landMinSeconds`)

	local jump = Duel.Rules.DoubleJump
	local jr = "Config.Duel.Rules.DoubleJump"
	eachField(
		problems,
		jr,
		jump,
		{ "heightStuds", "minAirSeconds", "pressGapSeconds", "serverIntervalSeconds" },
		expectPositive
	)
	expectCount(problems, `{jr}.maxPerAir`, jump.maxPerAir, 1)

	local flip = Anim.doubleJump
	local fp = "Config.Anim.doubleJump"
	eachField(problems, fp, flip, { "priority", "seconds", "spinSeconds", "tuckInSeconds" }, expectPositive)
	expect(
		problems,
		flip.tuckInSeconds < flip.tuckOutFromSeconds
			and flip.tuckOutFromSeconds < flip.spinSeconds
			and flip.spinSeconds <= flip.fadeFromSeconds
			and flip.fadeFromSeconds < flip.seconds,
		`{fp} must keep tuckInSeconds < tuckOutFromSeconds < spinSeconds <= fadeFromSeconds < seconds`
	)
	expect(
		problems,
		isNumber(flip.spinDegrees) and flip.spinDegrees >= 0 and flip.spinDegrees / flip.spinSeconds <= MAX_ROLL_DEG_PER_SECOND + FEEL_SLACK,
		`{fp}.spinDegrees / spinSeconds must stay at or under {MAX_ROLL_DEG_PER_SECOND} deg/s on average`
	)
	checkPoseAngles(problems, `{fp}.tuck`, flip.tuck, Anim.joints.R15)

	local ult = Vfx.Ultimates
	local u = "Config.Vfx.Ultimates"
	for _, field in { "zonePulseHz", "shadowPulseHz" } do
		expectBetween(problems, `{u}.{field}`, ult[field], 0, MAX_FLICKER_HZ + FEEL_SLACK)
	end
	for _, field in { "glideRollRate", "rollerTiltRate" } do
		expect(
			problems,
			isNumber(ult[field]) and ult[field] / (2 * math.pi) <= MAX_FLICKER_HZ + FEEL_SLACK,
			`{u}.{field} must stay at or under {MAX_FLICKER_HZ} Hz (rad/s / 2π)`
		)
	end
	expectBetween(
		problems,
		`{u}.rollerSpinDegPerSecond`,
		ult.rollerSpinDegPerSecond,
		0,
		MAX_ROLL_DEG_PER_SECOND + FEEL_SLACK
	)
	for _, field in { "popPuffs", "splashPuffs" } do
		expectBetween(problems, `{u}.{field}`, ult[field], 1, Vfx.Budgets.liveParticlesPerEffect)
	end
end

-- Feature 1 (2026-10-11): the charge throw and the catch (Config.Combat.Charge / Catch and their looks in
-- Config.FirstPerson, Config.Vfx, Config.UI and Config.Audio): the server's numbers, the 3 Hz flicker limit, the flash
-- and hit-stop caps and the particle budgets.
local function checkChargeCatch(problems: Problems)
	local charge, catch = Combat.Charge, Combat.Catch
	local p, q = "Config.Combat.Charge", "Config.Combat.Catch"
	local maxHold = Vfx.HitStop.maxPerWindow
	local budget = Vfx.Budgets.liveParticlesPerEffect
	local flicker = MAX_FLICKER_HZ + FEEL_SLACK
	eachField(problems, p, charge, { "seconds", "fovNarrowDeg" }, expectPositive)
	expectNonNegative(problems, `{p}.speedGain`, charge.speedGain)
	expectBetween(problems, `{p}.walkFactor`, charge.walkFactor, 0.1, 1)
	expectBetween(problems, `{p}.hitStopSeconds`, charge.hitStopSeconds, 0, maxHold)
	eachField(problems, q, catch, { "windowSeconds", "cooldownSeconds", "radiusStuds", "crushSeconds" }, expectPositive)
	expectNonNegative(problems, `{q}.centreAboveRootStuds`, catch.centreAboveRootStuds)
	expect(
		problems,
		isNumber(catch.windowSeconds) and catch.windowSeconds <= catch.cooldownSeconds,
		`{q}.windowSeconds must not outlast cooldownSeconds (one window at a time)`
	)
	expect(
		problems,
		isNumber(catch.handsBackSeconds) and catch.handsBackSeconds >= catch.crushSeconds,
		`{q}.handsBackSeconds must be >= crushSeconds (the hands come back after the burst)`
	)
	expectBetween(problems, `{q}.burstHitStopSeconds`, catch.burstHitStopSeconds, 0, maxHold)
	expectBoolean(problems, `{q}.burstIgnoresInvuln`, catch.burstIgnoresInvuln)
	expect(
		problems,
		isNumber(catch.cooldownToleranceSeconds)
			and catch.cooldownToleranceSeconds >= 0
			and catch.cooldownToleranceSeconds < catch.cooldownSeconds,
		`{q}.cooldownToleranceSeconds must be in [0, cooldownSeconds)`
	)
	-- Review quick win 2026-10-14: a real catch keeps its timing (the first press once the hands are back always passes
	-- the cooldown, even lag-compensated); only a missed catch waits the longer cooldown.
	local maxLag = Combat.Lag.maxCompensationSeconds
	expect(
		problems,
		isNumber(catch.cooldownSeconds)
			and isNumber(catch.cooldownToleranceSeconds)
			and isNumber(catch.handsBackSeconds)
			and isNumber(maxLag)
			and catch.cooldownSeconds - catch.cooldownToleranceSeconds
				<= catch.handsBackSeconds - maxLag + FEEL_SLACK,
		`{q}.cooldownSeconds - cooldownToleranceSeconds must be <= handsBackSeconds - `
			.. `Config.Combat.Lag.maxCompensationSeconds, so a real catch keeps its timing`
	)

	local fp = "Config.FirstPerson"
	local v2, fc, fk, fr = FirstPerson.v2, FirstPerson.charge, FirstPerson.catch, FirstPerson.crush
	eachField(problems, `{fp}.v2`, v2, { "depthScale", "fovScale", "toyRadius", "kickPerRecoil" }, expectPositive)
	expectBetween(problems, `{fp}.v2.hitStopTimeScale`, v2.hitStopTimeScale, 0, 1)
	-- The glow's flicker is a light: held to 3 Hz (§9.12). The squash pulse and the crush wobble are shape motion, kept
	-- at the design's rates as the Rush wobble is (FirstPerson.ult.wobbleRate) and off under ReducedMotion.
	expect(
		problems,
		isNumber(fc.glowPulseRate) and fc.glowPulseRate / (2 * math.pi) <= flicker,
		`{fp}.charge.glowPulseRate must stay at or under {MAX_FLICKER_HZ} Hz (rad/s / 2π)`
	)
	expectBetween(problems, `{fp}.charge.glowMax`, fc.glowMax, 0, 1)
	expectBetween(problems, `{fp}.charge.sparkMaxLive`, fc.sparkMaxLive, 1, budget)
	expectBetween(problems, `{fp}.crush.speckMaxLive`, fr.speckMaxLive, 1, budget)
	expectBetween(problems, `{fp}.crush.glowFlickerHz`, fr.glowFlickerHz, 0, flicker)
	expectCalmSpring(problems, `{fp}.crush.spring`, fr.spring[1], fr.spring[2])
	expectPositive(problems, `{fp}.catch.openSeconds`, fk.openSeconds)
	expectBetween(problems, `{fp}.catch.hitStopSeconds`, fk.hitStopSeconds, 0, maxHold)
	expect(
		problems,
		fr.burstPieces + fr.burstSparks + fr.burstPuffs + fr.burstWhite <= budget,
		`{fp}.crush burst pieces must total at most Config.Vfx.Budgets.liveParticlesPerEffect ({budget})`
	)

	local vc, vk = Vfx.Charge, Vfx.Catch
	local v = "Config.Vfx"
	for _, field in
		{ "trailWidthGain", "trailLifeGain", "releasePuffGain", "releaseRingGain", "fovKickGain", "kickGain" }
	do
		expectNonNegative(problems, `{v}.Charge.{field}`, (vc :: any)[field])
	end
	eachField(problems, `{v}.Charge`, vc, {
		"powerRingStuds",
		"powerRingSeconds",
		"speckRate",
		"speckLifetimeMin",
		"speckLifetimeMax",
		"speckSize",
		"speckSpeed",
	}, expectPositive)
	expectBetween(problems, `{v}.Charge.powerRingGain`, vc.powerRingGain, 0, 1)
	expect(
		problems,
		isNumber(vc.speckLifetimeMax) and vc.speckLifetimeMin <= vc.speckLifetimeMax,
		`{v}.Charge.speckLifetimeMin must be <= speckLifetimeMax`
	)
	expect(
		problems,
		vk.sparks <= budget and vk.burstPieces + vk.burstSparks + vk.burstPuffs <= budget,
		`{v}.Catch sparks and burst pieces must each stay within Budgets.liveParticlesPerEffect ({budget})`
	)
	eachField(problems, `{v}.Catch`, vk, {
		"ringStuds",
		"ringSeconds",
		"sparkSizeStuds",
		"flyInSeconds",
		"burstRingStuds",
		"burstGravity",
		"burstDrag",
	}, expectPositive)

	local reticle = UI.Reticle
	local r = "Config.UI.Reticle"
	expectBetween(problems, `{r}.chargeFillTransparency`, reticle.chargeFillTransparency, 0, 1)
	expect(
		problems,
		isNumber(reticle.chargePulseRate) and reticle.chargePulseRate / (2 * math.pi) <= flicker,
		`{r}.chargePulseRate must stay at or under {MAX_FLICKER_HZ} Hz (rad/s / 2π)`
	)
	expectBetween(problems, `{r}.catchPromptHz`, reticle.catchPromptHz, 0, flicker)
	-- The prompt's opacity swings catchPromptFrom ± (1 - catchPromptFrom): never below 0.
	expectBetween(problems, `{r}.catchPromptFrom`, reticle.catchPromptFrom, 0.5, 1)
	expectPositive(problems, `{r}.catchPromptStuds`, reticle.catchPromptStuds)
	expectPositive(problems, `{r}.bigWordSeconds`, reticle.bigWordSeconds)
	expect(
		problems,
		isNumber(UI.Touch.catchButton) and UI.Touch.catchButton >= UI.Touch.minTargetFloor,
		`Config.UI.Touch.catchButton must be >= minTargetFloor ({UI.Touch.minTargetFloor})`
	)

	local tone = Audio.charge
	local a = "Config.Audio.charge"
	for _, field in { "pitchFrom", "pitchTo" } do
		expectBetween(problems, `{a}.{field}`, (tone :: any)[field], Audio.pitchMin, Audio.pitchMax)
	end
	expectBetween(problems, `{a}.volumeFrom`, tone.volumeFrom, 0, 1)
	expectBetween(problems, `{a}.tremolo`, tone.tremolo, 0, 0.99)
	expectNonNegative(problems, `{a}.tremoloRate`, tone.tremoloRate)
	expectNonNegative(problems, `{a}.stopFadeMs`, tone.stopFadeMs)
end

local function checkDebug(problems: Problems)
	for _, name in sortedKeys(Debug) do
		local value = (Debug :: any)[name]
		expectBoolean(problems, `Config.Debug.{name}`, value)
		expect(
			problems,
			Debug.isStudio or name == "isStudio" or value == false,
			`Config.Debug.{name} must be false outside Studio`
		)
	end
end

-- Config.Match (Free for All / Team Deathmatch, user 2026-10-15): Config/ValidateMatch's checks (its header lists them;
-- apart, so this script stays under Roblox's 200,000-character Source limit).
local checkMatch = require(script.ValidateMatch)({
	add = add,
	expect = expect,
	expectPositive = expectPositive,
	expectNonNegative = expectNonNegative,
	expectCount = expectCount,
	expectBetween = expectBetween,
	expectBoolean = expectBoolean,
	expectText = expectText,
	expectCoins = expectCoins,
	isNumber = isNumber,
	show = show,
	sortedKeys = sortedKeys,
}, Match, Duel, function(): any
	return (loadSibling("Art/Palette"))
end)

-- Private: Grip checks (DESIGN §17.9 table; each rule has a negative unit test in Config_Test) ----------------------

local function studs(value: number): string
	return string.format("%.2f", value)
end

-- G1 Levels: LevelTotals has maxLevel integers, starts at 0, rises strictly and ends at <= maxGrip. Also the ranks that
-- read those levels: from Lv 1, rising, within maxLevel. Spec 2026-10-12's totals make Lv 3 and Lv 11 cost less than
-- the level before, so the old "a level never costs less than the one before" rule is gone.
local function checkGripLevels(problems: Problems)
	local p = "Config.Grip"
	expectBoolean(problems, `{p}.enabled`, Grip.enabled)
	expectCount(problems, `{p}.maxLevel`, Grip.maxLevel, 1)
	expectCount(problems, `{p}.maxGrip`, Grip.maxGrip, 1)

	local totals: { any } = Grip.LevelTotals
	expect(
		problems,
		#totals == Grip.maxLevel,
		`G1: {p}.LevelTotals must list {Grip.maxLevel} levels (maxLevel), got {#totals}`
	)
	expect(problems, totals[1] == 0, `G1: {p}.LevelTotals[1] must be 0 (got {show(totals[1])})`)
	for level, total in totals do
		if not isInteger(total) or total < 0 then
			add(problems, `G1: {p}.LevelTotals[{level}] must be an integer >= 0 (got {show(total)})`)
			continue
		end
		local before = totals[level - 1]
		if level > 1 and isInteger(before) then
			expect(
				problems,
				total > before,
				`G1: {p}.LevelTotals must rise strictly (Lv {level}: {total} after {before})`
			)
		end
	end
	local last = totals[#totals]
	expect(
		problems,
		isNumber(last) and isNumber(Grip.maxGrip) and last <= Grip.maxGrip,
		`G1: {p}.LevelTotals ends at {show(last)}, above maxGrip ({show(Grip.maxGrip)})`
	)

	local ranks: { any } = Grip.Ranks
	expect(problems, #ranks >= 1 and ranks[1].level == 1, `G1: {p}.Ranks must start at Lv 1`)
	for index, rank in ranks do
		local path = `{p}.Ranks[{index}]`
		expectId(problems, `{path}.key`, rank.key)
		expectBetween(problems, `G1: {path}.level`, rank.level, 1, Grip.maxLevel)
		local before = ranks[index - 1]
		if before then
			expect(problems, rank.level > before.level, `G1: {p}.Ranks levels must rise strictly ({path})`)
		end
	end
end

-- G2 Pads: Pads[1], the Foam Mats (the only row since the giant pads went, build plan Phase 6), has an id key, level
-- 1, coinBonus 0 and gripPercent 100.
local function checkGripPads(problems: Problems)
	local p = "Config.Grip.Pads"
	local first = (Grip.Pads :: { any })[1]
	expect(
		problems,
		first ~= nil and first.level == 1 and first.coinBonus == 0 and first.gripPercent == 100,
		`G2: {p}[1] (the Foam Mats) must be level 1, coinBonus 0, gripPercent 100`
	)
	if first ~= nil then
		expectId(problems, `{p}[1].key`, first.key)
	end
end

-- The Coins from capsule level to level + 1, from the Config.Grip.Capsule data (CapsuleMath's formula, spec
-- 2026-10-12 §5: Config cannot require CapsuleMath, which requires Config).
local function capsulePrice(capsule: any, level: number): number
	local price = capsule.price
	local raw = price.base * price.growth ^ (level - 1)
	local scale = math.max(1, 10 ^ (math.floor(math.log10(raw)) + 1 - price.digits))
	local rounded = math.round(raw / scale) * scale
	return if level % capsule.levelsPerTier == 0 then rounded * price.evolveMultiplier else rounded
end

-- G5 Caps and timers: maxGripPerEvent covers 4 × the top squeeze value (pens3 phase 2: Double Grip × 2, the Squeaky
-- Ring × 2; each placed spot a top Exclusive of Economy.Pen); Double Grip refills slower
-- than holding Squeeze spends it; Hold.maxSeconds < idleReminderSeconds < 1200 (idle kick); Hold.queuedSeconds < 120.
-- Reading (2026-10-06): the refill rule compared with 3600 / Squeeze.cycleSeconds, the accepted rate
-- when the cycle was the 1.5 s squeeze timer; the rule uses the hold-to-squeeze rhythm, 3600 / Hold.repeatSeconds
-- (since Batch 1 #2 also the paid-squeeze cap's rate).
local function checkGripCaps(problems: Problems)
	local p = "Config.Grip"
	local rested, hold = Grip.Rested, Grip.Hold
	expectBoolean(problems, `{p}.Rested.enabled`, rested.enabled)
	expectPositive(problems, `{p}.Rested.perHour`, rested.perHour)
	expectCount(problems, `{p}.Rested.burst`, rested.burst, 1)
	expect(problems, isNumber(rested.mult) and rested.mult >= 1, `{p}.Rested.mult must be a number >= 1`)
	local pen = Economy.Pen
	local event = pen.placedMax
		* pen.coinsPerPower
		* Economy.SquishyPower.Exclusive
		* pen.formMult[#pen.formMult]
		* pen.coatMult[#pen.coatMult]
		* pen.levelGain ^ (pen.maxLevel - 1)
		* 4
	expect(
		problems,
		isNumber(Grip.maxGripPerEvent) and Grip.maxGripPerEvent >= event,
		`G5: {p}.maxGripPerEvent ({show(Grip.maxGripPerEvent)}) must be >= 4 × the top squeeze value`
			.. ` ({string.format("%.4g", event)})`
	)
	expectPositive(problems, `{p}.Hold.repeatSeconds`, hold.repeatSeconds)
	if isNumber(hold.repeatSeconds) and hold.repeatSeconds > 0 then
		local holdingRate = SECONDS_PER_HOUR / hold.repeatSeconds
		expect(
			problems,
			rested.perHour < holdingRate,
			`G5: {p}.Rested.perHour ({rested.perHour}) must be below the holding squeeze rate `
				.. `(3600 / Config.Grip.Hold.repeatSeconds = {string.format("%.10g", holdingRate)})`
		)
	end
	expectPositive(problems, `{p}.Hold.maxSeconds`, hold.maxSeconds)
	expect(
		problems,
		hold.maxSeconds < Grip.idleReminderSeconds and Grip.idleReminderSeconds < MAX_IDLE_KICK_SECONDS,
		`G5: Hold.maxSeconds ({hold.maxSeconds}) < idleReminderSeconds ({Grip.idleReminderSeconds}) < `
			.. `{MAX_IDLE_KICK_SECONDS} must hold`
	)
	expect(
		problems,
		isNumber(hold.queuedSeconds) and hold.queuedSeconds > 0 and hold.queuedSeconds < MAX_QUEUED_HOLD_SECONDS,
		`G5: {p}.Hold.queuedSeconds ({show(hold.queuedSeconds)}) must be in (0, {MAX_QUEUED_HOLD_SECONDS})`
	)
	eachField(problems, `{p}.Hold`, hold, { "leadSeconds", "replyGraceSeconds" }, expectNonNegative)
end

-- G8 World: every WorldLayout station has a unique squeeze_NN id and a GripTier in 1..#Pads (the giant pads' rules
-- went with them, build plan Phase 6).
local function checkGripWorld(problems: Problems, layout: any)
	local tierCount = #Grip.Pads
	local stations = layout.Stations
	if type(stations) ~= "table" then
		add(problems, "G8: WorldLayout.Stations is missing")
		return
	end

	local byId: { [string]: any } = {}
	for index, station in stations do
		local id = station.id
		local label = `WorldLayout.Stations[{index}] ({show(id)})`
		expect(
			problems,
			type(id) == "string" and string.match(id, STATION_ID_PATTERN) ~= nil,
			`G8: {label} id must match {STATION_ID_PATTERN}`
		)
		if type(id) == "string" then
			expect(problems, byId[id] == nil, `G8: {label} is listed twice`)
			byId[id] = station
		end
		local tier = station.tier
		expect(
			problems,
			isInteger(tier) and tier >= 1 and tier <= tierCount,
			`G8: {label} has GripTier {show(tier)}; it must be an integer in 1..{tierCount} (#Config.Grip.Pads)`
		)
	end
end

local function num(value: number): string
	return string.format("%.10g", value)
end

-- G3 Squeeze ceiling (Part 5; a squeeze count since spec 2026-10-12 §12, because Coins per squeeze now grow with the
-- capsules): attempts = 3600 / Squeeze.cycleSeconds (the most squeezes the server accepts in an hour: the paid cap at
-- the hold rhythm since Batch 1 #2); paid = L.enabled and min(L.perHour, attempts) or attempts
-- (L = Economy.SqueezeLimit) must be <= Grip.maxSqueezesPerHour (8,000).
local function checkGripSqueezeCeiling(problems: Problems)
	local limit = Economy.SqueezeLimit
	local attempts = SECONDS_PER_HOUR / Squeeze.cycleSeconds
	local paid = if limit.enabled then math.min(limit.perHour, attempts) else attempts
	expect(
		problems,
		isNumber(Grip.maxSqueezesPerHour) and paid <= Grip.maxSqueezesPerHour,
		`G3: the server can pay {num(paid)} squeezes an hour, above Config.Grip.maxSqueezesPerHour `
			.. `({show(Grip.maxSqueezesPerHour)}) ({num(attempts)} attempts/h from Config.Squeeze.cycleSeconds; `
			.. `Config.Economy.SqueezeLimit.enabled = {tostring(limit.enabled)}, perHour {num(limit.perHour)})`
	)
end

-- Capsules (spec 2026-10-12 §4-§7): the tiers fill maxLevel; intervals fall and Grip gates rise (tier 1 needs none);
-- power and price grow (> 1); slot prices rise from a free slot 1; every price fits Economy.maxCoins; the Phase 3 tick
-- and tap push are positive (a push at most one squeeze).
local function checkGripCapsules(problems: Problems)
	local p = "Config.Grip.Capsule"
	local capsule = Grip.Capsule
	local tiers: { any } = capsule.Tiers
	expectCount(problems, `{p}.levelsPerTier`, capsule.levelsPerTier, 1)
	expect(
		problems,
		#tiers * capsule.levelsPerTier == capsule.maxLevel,
		`{p}: {#tiers} tiers of {show(capsule.levelsPerTier)} levels must make maxLevel ({show(capsule.maxLevel)})`
	)
	expect(problems, tiers[1] ~= nil and tiers[1].gripLevel == 0, `{p}.Tiers[1] must need no Grip level (gripLevel 0)`)
	for index, tier in tiers do
		local path = `{p}.Tiers[{index}]`
		expectId(problems, `{path}.key`, tier.key)
		expectPositive(problems, `{path}.seconds`, tier.seconds)
		expectBetween(problems, `{path}.gripLevel`, tier.gripLevel, 0, Grip.maxLevel)
		local before = tiers[index - 1]
		if before then
			expect(problems, tier.seconds < before.seconds, `{p}: intervals must fall tier by tier ({path}.seconds)`)
			expect(problems, tier.gripLevel > before.gripLevel, `{p}: Grip gates must rise tier by tier ({path})`)
		end
	end
	local power, price = capsule.power, capsule.price
	expectCount(problems, `{p}.power.base`, power.base, 1)
	expect(problems, isNumber(power.growth) and power.growth > 1, `{p}.power.growth must be > 1`)
	expect(
		problems,
		isNumber(power.tierMultiplier) and power.tierMultiplier >= 1,
		`{p}.power.tierMultiplier must be >= 1`
	)
	expectCount(problems, `{p}.price.base`, price.base, 1)
	expect(problems, isNumber(price.growth) and price.growth > 1, `{p}.price.growth must be > 1`)
	expectCount(problems, `{p}.price.digits`, price.digits, 1)
	expect(
		problems,
		isNumber(price.evolveMultiplier) and price.evolveMultiplier >= 1,
		`{p}.price.evolveMultiplier must be >= 1`
	)
	expectPositive(problems, `{p}.tickSeconds`, capsule.tickSeconds)
	expectPositive(problems, `{p}.tapPush`, capsule.tapPush)
	expect(problems, isNumber(capsule.tapPush) and capsule.tapPush <= 1, `{p}.tapPush must be at most 1 squeeze`)
	local slots: { any } = capsule.slotPrices
	expect(problems, slots[1] == 0, `{p}.slotPrices[1] must be 0 (the first capsule is free)`)
	for index, coins in slots do
		expectCoins(problems, `{p}.slotPrices[{index}]`, coins)
		if index > 1 and isNumber(coins) and isNumber(slots[index - 1]) then
			expect(problems, coins > slots[index - 1], `{p}.slotPrices must rise ({p}.slotPrices[{index}])`)
		end
	end
	local biggest = 0
	for level = 1, capsule.maxLevel - 1 do
		biggest = math.max(biggest, capsulePrice(capsule, level))
	end
	expect(
		problems,
		biggest <= Economy.maxCoins,
		`{p}: a level up costs up to {num(biggest)} Coins, above Config.Economy.maxCoins ({show(Economy.maxCoins)})`
	)
end

-- G6 Strings names (Part 5 half): every rank and pad key has its Strings text grip.rank.<key>, grip.pad.<key>.
local function checkGripStrings(problems: Problems, Strings: any)
	local resolve = Strings.resolve
	if type(resolve) ~= "function" then
		return -- reported by the Strings keys check
	end
	local groups: { { path: string, prefix: string, list: { any } } } = {
		{ path = "Ranks", prefix = "grip.rank.", list = Grip.Ranks },
		{ path = "Pads", prefix = "grip.pad.", list = Grip.Pads },
	}
	for _, group in groups do
		for index, entry in group.list do
			local key = group.prefix .. tostring(entry.key)
			local ok, text = pcall(resolve, key)
			expect(
				problems,
				ok and type(text) == "string" and text ~= "",
				`G6: Config.Grip.{group.path}[{index}] needs the Strings text {key}`
			)
		end
	end
end

-- The other Part 5 Grip values: nameplate, toasts and the caps the services read.
local function checkGripSettings(problems: Problems)
	local p = "Config.Grip"
	local plate = Grip.Nameplate
	expectBoolean(problems, `{p}.Nameplate.enabled`, plate.enabled)
	expectPositive(problems, `{p}.Nameplate.maxDistance`, plate.maxDistance)
	expectNonNegative(problems, `{p}.Nameplate.headOffsetStuds`, plate.headOffsetStuds)
	expect(problems, isNumber(plate.popScale) and plate.popScale >= 1, `{p}.Nameplate.popScale must be a number >= 1`)
	expectNonNegative(problems, `{p}.Nameplate.popSeconds`, plate.popSeconds)
	-- Part 8 polish (§17.11): the distance fade ends at maxDistance and starts inside it; one check loop; the own plate.
	expect(
		problems,
		isNumber(plate.fadeStuds)
			and isNumber(plate.maxDistance)
			and plate.fadeStuds > 0
			and plate.fadeStuds < plate.maxDistance,
		`{p}.Nameplate.fadeStuds must be > 0 and below maxDistance (got {show(plate.fadeStuds)})`
	)
	expectPositive(problems, `{p}.Nameplate.checkSeconds`, plate.checkSeconds)
	expectNonNegative(problems, `{p}.Nameplate.ownHideStuds`, plate.ownHideStuds)
	expectCount(problems, `{p}.welcomeBackMinGain`, Grip.welcomeBackMinGain, 0)
	expect(
		problems,
		isNumber(Grip.welcomeBackMinGain) and Grip.welcomeBackMinGain <= Grip.Rested.burst,
		`{p}.welcomeBackMinGain must not exceed Rested.burst ({show(Grip.Rested.burst)}), or the toast never shows`
	)
	expectBoolean(problems, `{p}.allowBundlesWithCapsules`, Grip.allowBundlesWithCapsules)
	expectPositive(problems, `{p}.maxSqueezesPerHour`, Grip.maxSqueezesPerHour)
	-- Spec 2026-10-12 §12: the paid-squeeze alert log; above the ceiling it could never fire.
	expect(
		problems,
		isInteger(Grip.squeezeAlertPerHour)
			and Grip.squeezeAlertPerHour >= 1
			and isNumber(Grip.maxSqueezesPerHour)
			and Grip.squeezeAlertPerHour <= Grip.maxSqueezesPerHour,
		`{p}.squeezeAlertPerHour must be a whole number in 1..maxSqueezesPerHour (got {show(Grip.squeezeAlertPerHour)})`
	)
	expectCount(problems, `{p}.maxGripPerEvent`, Grip.maxGripPerEvent, 1)
	expect(
		problems,
		isNumber(Grip.gripAlertPerHour) and Grip.gripAlertPerHour >= Grip.maxGripPerEvent,
		`{p}.gripAlertPerHour must be >= maxGripPerEvent (got {show(Grip.gripAlertPerHour)})`
	)
end

-- Private: feel pass checks (DESIGN §18.9 "New Config.validate rules"; each has a planted bad value in Config_Test) --

-- F1 Squeeze total: for every rarity, flourish.particles + (the squeezeFx hook's steamPuffs when the flourish has
-- useSqueezeFx, else 0) + max(rhythm.popSparkles, rhythm.bigPopSparkles) <= Effects.squeezePuffs (the big pop replaces
-- the release pop). Reading: Config can't tell which catalog hook a rarity's squishies run, so the largest steamPuffs
-- of any listed hook counts.
local function checkSqueezeTotal(problems: Problems, rarities: { string })
	local squeeze = Anim.squeeze
	local rhythm = squeeze.rhythm
	local p = "F1: Config.Anim.squeeze"
	expectCount(problems, `{p}.rhythm.popSparkles`, rhythm.popSparkles, 0)
	expectCount(problems, `{p}.rhythm.bigPopSparkles`, rhythm.bigPopSparkles, 0)
	local steam = 0
	for _, name in sortedKeys(squeeze.squeezeFx) do
		local puffs = squeeze.squeezeFx[name].steamPuffs
		if isNumber(puffs) then
			steam = math.max(steam, puffs)
		end
	end
	local pops = math.max(rhythm.popSparkles, rhythm.bigPopSparkles)
	local limit = Vfx.Effects.squeezePuffs
	for _, rarity in rarities do
		local flourish = squeeze.flourish[rarity]
		if flourish == nil then
			continue -- reported by checkAnim
		end
		local steamPuffs = if flourish.useSqueezeFx then steam else 0
		local total = flourish.particles + steamPuffs + pops
		expect(
			problems,
			total <= limit,
			`{p}.flourish.{rarity}: particles ({flourish.particles}) + steam puffs ({steamPuffs}) + release pop `
				.. `sparkles ({pops}) = {total} exceeds Config.Vfx.Effects.squeezePuffs ({limit})`
		)
	end
end

-- F2 Elimination: confettiParticles + sparkles <= Effects.eliminationParticles; Confetti.parts ==
-- Effects.eliminationConfettiParts (the FxPool confetti parts are not particles).
local function checkEliminationBudget(problems: Problems)
	local elimination = Anim.elimination
	local effects = Vfx.Effects
	expect(
		problems,
		elimination.confettiParticles + elimination.sparkles <= effects.eliminationParticles,
		`F2: Config.Anim.elimination confetti + sparkles ({elimination.confettiParticles} + {elimination.sparkles}) `
			.. `exceed Config.Vfx.Effects.eliminationParticles ({effects.eliminationParticles})`
	)
	local parts = Vfx.Confetti.parts
	expectCount(problems, "F2: Config.Vfx.Confetti.parts", parts, 1)
	expect(
		problems,
		parts == effects.eliminationConfettiParts,
		`F2: Config.Vfx.Confetti.parts ({show(parts)}) must equal Config.Vfx.Effects.eliminationConfettiParts `
			.. `({show(effects.eliminationConfettiParts)})`
	)
end

-- F3 Screen punch: maxFovDeg in (0, 4]; every Punch.<event>.fovDeg within ±maxFovDeg; attack and release > 0 ms.
local function checkPunch(problems: Problems)
	local punch = Vfx.Punch :: any
	local p = "F3: Config.Vfx.Punch"
	local maxDeg = punch.maxFovDeg
	local maxOk = isNumber(maxDeg) and maxDeg > 0 and maxDeg <= MAX_FOV_PUNCH_DEG
	expect(problems, maxOk, `{p}.maxFovDeg must be in (0, {MAX_FOV_PUNCH_DEG}] (got {show(maxDeg)})`)
	for _, name in sortedKeys(punch) do
		local spec = punch[name]
		if type(spec) ~= "table" then
			continue
		end
		expect(
			problems,
			maxOk and isNumber(spec.fovDeg) and math.abs(spec.fovDeg) <= maxDeg,
			`{p}.{name}.fovDeg ({show(spec.fovDeg)}) must be within ±maxFovDeg ({show(maxDeg)})`
		)
		expectPositive(problems, `{p}.{name}.attackMs`, spec.attackMs)
		expectPositive(problems, `{p}.{name}.releaseMs`, spec.releaseMs)
	end
end

-- F4 Hit-stop: every hold (playerHit, elimination, practiceTarget) in (0, maxPerWindow]; maxPerWindow <= windowSeconds.
local function checkHitStop(problems: Problems)
	local hitStop = Vfx.HitStop :: any
	local p = "F4: Config.Vfx.HitStop"
	local cap, window = hitStop.maxPerWindow, hitStop.windowSeconds
	expectPositive(problems, `{p}.maxPerWindow`, cap)
	expectPositive(problems, `{p}.windowSeconds`, window)
	expect(
		problems,
		isNumber(cap) and isNumber(window) and cap <= window,
		`{p}.maxPerWindow ({show(cap)}) must be <= windowSeconds ({show(window)})`
	)
	for _, name in sortedKeys(hitStop) do
		if name == "maxPerWindow" or name == "windowSeconds" then
			continue
		end
		local hold = hitStop[name]
		expect(
			problems,
			isNumber(hold) and hold > 0 and isNumber(cap) and hold <= cap,
			`{p}.{name} ({show(hold)}) must be in (0, maxPerWindow ({show(cap)})]`
		)
	end
end

-- F5 Splats: maxLive × (1 + droplets) <= 60 parts. Reading: maxLive also stays within Budgets.splats (§18.9's row).
local function checkSplatBudget(problems: Problems)
	local splat = Vfx.Splat
	local p = "F5: Config.Vfx.Splat"
	expectCount(problems, `{p}.maxLive`, splat.maxLive, 1)
	expectCount(problems, `{p}.droplets`, splat.droplets, 0)
	local parts = splat.maxLive * (1 + splat.droplets)
	expect(
		problems,
		parts <= MAX_SPLAT_PARTS,
		`{p}.maxLive × (1 + droplets) = {parts} parts exceeds {MAX_SPLAT_PARTS}`
	)
	expect(
		problems,
		splat.maxLive <= Vfx.Budgets.splats,
		`{p}.maxLive ({splat.maxLive}) exceeds Config.Vfx.Budgets.splats ({Vfx.Budgets.splats})`
	)
end

-- F6 Mat pulse: MatPulse.upMs + downMs == Effects.matPulseSeconds × 1000.
local function checkMatPulse(problems: Problems)
	local pulse = Vfx.MatPulse
	local p = "F6: Config.Vfx.MatPulse"
	expectPositive(problems, `{p}.upMs`, pulse.upMs)
	expectPositive(problems, `{p}.downMs`, pulse.downMs)
	local total = pulse.upMs + pulse.downMs
	local wanted = Vfx.Effects.matPulseSeconds * 1000
	expect(
		problems,
		math.abs(total - wanted) < 1e-6,
		`{p}.upMs + downMs ({num(total)}) must equal Config.Vfx.Effects.matPulseSeconds × 1000 ({num(wanted)})`
	)
end

-- The size of the first cover part of a piece kind ("wall", "block") in WorldLayout.Arena.cover, else `default`.
local function coverSize(layout: any, kind: string, default: Vector3): Vector3
	local arena = if layout ~= nil then layout.Arena else nil
	if type(arena) == "table" and type(arena.cover) == "table" then
		for _, piece in arena.cover do
			local part = if piece.kind == kind and type(piece.parts) == "table" then piece.parts[1] else nil
			if part ~= nil and typeof(part.size) == "Vector3" then
				return part.size
			end
		end
	end
	return default
end

-- The smallest grid spacing of the ripple's moving faces at one quality (§18.3.4 layout, §18.3.7): wall big faces
-- (wallCols across the wall's X, rows wallRowStuds apart), wall sides (wallSideCols across its Z), the wall top
-- (wallTopCols × wallTopRows; 0 × 0 = fixed corners only), block sides (blockCols across X and Z, blockRows up Y) and
-- the backstop's front face (cols across its Z, rows up its Y). Adds a problem per malformed count.
local function rippleSpacing(
	problems: Problems,
	path: string,
	grid: any,
	backstopCols: unknown,
	backstopRows: unknown,
	sizes: { wall: Vector3, block: Vector3, backstop: Vector3 }
): number
	local smallest = math.huge
	local function across(length: number, count: unknown, label: string)
		if isInteger(count) and (count :: number) >= 2 then
			smallest = math.min(smallest, length / ((count :: number) - 1))
		else
			add(problems, `F7: {label} must be an integer >= 2 (got {show(count)})`)
		end
	end
	local wall, block, backstop = sizes.wall, sizes.block, sizes.backstop
	across(wall.X, grid.wallCols, `{path}.wallCols`)
	across(wall.Z, grid.wallSideCols, `{path}.wallSideCols`)
	expectPositive(problems, `F7: {path}.wallRowStuds`, grid.wallRowStuds)
	if isNumber(grid.wallRowStuds) and grid.wallRowStuds > 0 then
		smallest = math.min(smallest, grid.wallRowStuds)
	end
	if grid.wallTopCols ~= 0 or grid.wallTopRows ~= 0 then
		across(wall.X, grid.wallTopCols, `{path}.wallTopCols`)
		across(wall.Z, grid.wallTopRows, `{path}.wallTopRows`)
	end
	across(math.min(block.X, block.Z), grid.blockCols, `{path}.blockCols`)
	across(block.Y, grid.blockRows, `{path}.blockRows`)
	across(backstop.Z, backstopCols, `{path} backstop cols`)
	across(backstop.Y, backstopRows, `{path} backstop rows`)
	return smallest
end

-- F7 jiggle (the path A whole-piece jiggle): omega > 0 with omega / 2π <= MAX_JIGGLE_HZ, 0 < zeta < 1, 0 < amount,
-- rushAmount and backstopAmount <= maxAmount <= MAX_RIPPLE_AMOUNT, verticalShare in [0, 1], maxPieces and
-- writesPerFrame integers >= 1, writesPerFrameLow an integer in [1, writesPerFrame] (phones get the smaller budget),
-- and the strongest jiggle is at rest within faceSeconds: its envelope maxAmount / s
-- (s = the first swing's share of it, e^(-ζω·t)·sin(ω_d·t) at its peak t = atan2(ω_d, ζω) / ω_d) decays under
-- Anim.deform.restEpsilon by then.
local function checkJiggle(problems: Problems, ripple: any, p: string)
	local jiggle = ripple.jiggle
	local q = `{p}.jiggle`
	local omega, zeta = jiggle.omega, jiggle.zeta
	local omegaOk = isNumber(omega) and omega > 0
	local zetaOk = isNumber(zeta) and zeta > 0 and zeta < 1
	expect(
		problems,
		omegaOk and omega / (2 * math.pi) <= MAX_JIGGLE_HZ + FEEL_SLACK,
		`{q}.omega ({show(omega)}) must be > 0 with omega / 2π <= {MAX_JIGGLE_HZ} Hz`
	)
	expect(problems, zetaOk, `{q}.zeta must be in (0, 1) (got {show(zeta)})`)
	local maxAmount = jiggle.maxAmount
	local maxOk = isNumber(maxAmount) and maxAmount > 0 and maxAmount <= MAX_RIPPLE_AMOUNT
	expect(problems, maxOk, `{q}.maxAmount must be in (0, {MAX_RIPPLE_AMOUNT}] (got {show(maxAmount)})`)
	for _, name in { "amount", "rushAmount", "backstopAmount" } do
		local amount = jiggle[name]
		expect(
			problems,
			isNumber(amount) and amount > 0 and maxOk and amount <= maxAmount,
			`{q}.{name} ({show(amount)}) must be in (0, jiggle.maxAmount ({show(maxAmount)})]`
		)
	end
	expectBetween(problems, `{q}.verticalShare`, jiggle.verticalShare, 0, 1)
	expectCount(problems, `{q}.maxPieces`, jiggle.maxPieces, 1)
	expectCount(problems, `{q}.writesPerFrame`, jiggle.writesPerFrame, 1)
	local low, high = jiggle.writesPerFrameLow, jiggle.writesPerFrame
	expect(
		problems,
		isInteger(low) and low >= 1 and (not isNumber(high) or low <= high),
		`{q}.writesPerFrameLow must be an integer in [1, jiggle.writesPerFrame ({show(high)})] (got {show(low)})`
	)
	local rest = Anim.deform.restEpsilon
	if omegaOk and zetaOk and maxOk and isNumber(ripple.faceSeconds) and isNumber(rest) and rest > 0 then
		local damped = omega * math.sqrt(1 - zeta * zeta)
		local peakAt = math.atan2(damped, zeta * omega) / damped
		local swing = math.exp(-zeta * omega * peakAt) * math.sin(damped * peakAt)
		local left = maxAmount / swing * math.exp(-zeta * omega * ripple.faceSeconds)
		expect(
			problems,
			left <= rest,
			`{q}: the strongest jiggle still swings {string.format("%.4f", left)} after faceSeconds `
				.. `({show(ripple.faceSeconds)}), above Config.Anim.deform.restEpsilon ({show(rest)}): raise zeta`
		)
	end
end

-- F7 Jelly ripple: with path A, 2 · waveStudsPerSecond · substep / smallest spacing <= 0.5 at both qualities (PadDent's
-- waveSpeed is 2 × the real speed; the spacings follow from gridHigh / gridLow and the WorldLayout face sizes);
-- 0 < springZeta < 1; pathB.amount and roundAmount <= pathB.maxAmount <= MAX_RIPPLE_AMOUNT (0.3); 0 <
-- pathB.reducedScale <= 1; the jiggle (checkJiggle); Effects.impactRings >= the floor's ring count; skinMode is "onHit"
-- or "always". The vertex and triangle caps are JellySkin_Test's (client module).
local function checkJellyRipple(problems: Problems, layout: any)
	local ripple = Anim.jellyRipple
	local p = "F7: Config.Anim.jellyRipple"
	expect(
		problems,
		table.find(SKIN_MODES, ripple.skinMode) ~= nil,
		`{p}.skinMode must be "onHit" or "always" (got {show(ripple.skinMode)})`
	)
	expectPositive(problems, `{p}.springOmega`, ripple.springOmega)
	expect(
		problems,
		isNumber(ripple.springZeta) and ripple.springZeta > 0 and ripple.springZeta < 1,
		`{p}.springZeta must be in (0, 1) (got {show(ripple.springZeta)})`
	)
	local pathB = ripple.pathB
	expect(
		problems,
		isNumber(pathB.maxAmount) and pathB.maxAmount > 0 and pathB.maxAmount <= MAX_RIPPLE_AMOUNT,
		`{p}.pathB.maxAmount must be in (0, {MAX_RIPPLE_AMOUNT}] (got {show(pathB.maxAmount)})`
	)
	for _, name in { "amount", "roundAmount" } do
		local amount = (pathB :: any)[name]
		expect(
			problems,
			isNumber(amount) and amount > 0 and isNumber(pathB.maxAmount) and amount <= pathB.maxAmount,
			`{p}.pathB.{name} ({show(amount)}) must be in (0, pathB.maxAmount ({show(pathB.maxAmount)})]`
		)
	end
	expect(
		problems,
		isNumber(pathB.reducedScale) and pathB.reducedScale > 0 and pathB.reducedScale <= 1,
		`{p}.pathB.reducedScale must be in (0, 1] (got {show(pathB.reducedScale)})`
	)
	checkJiggle(problems, ripple, p)
	local floorRings = #ripple.rings.floorDiameters
	expect(
		problems,
		isNumber(Vfx.Effects.impactRings) and Vfx.Effects.impactRings >= floorRings,
		`F7: Config.Vfx.Effects.impactRings ({show(Vfx.Effects.impactRings)}) must be >= the {floorRings} floor rings `
			.. "of Config.Anim.jellyRipple.rings.floorDiameters"
	)
	if ripple.pathA == false then
		return
	end
	expectNonNegative(problems, `{p}.waveStudsPerSecond`, ripple.waveStudsPerSecond)
	expectPositive(problems, `{p}.substep`, ripple.substep)
	local practice = if layout ~= nil then layout.PracticeRange else nil
	local backstopBox = if type(practice) == "table" then practice.backstop else nil
	local sizes = {
		wall = coverSize(layout, "wall", DEFAULT_WALL_SIZE),
		block = coverSize(layout, "block", DEFAULT_BLOCK_SIZE),
		backstop = if type(backstopBox) == "table" and typeof(backstopBox.size) == "Vector3"
			then backstopBox.size
			else DEFAULT_BACKSTOP_SIZE,
	}
	local backstop = ripple.backstop
	local qualities: { { any } } = {
		{ "gridHigh", backstop.colsHigh, backstop.rowsHigh },
		{ "gridLow", backstop.colsLow, backstop.rowsLow },
	}
	for _, quality in qualities do
		local name = quality[1] :: string
		local spacing = rippleSpacing(problems, `{p}.{name}`, (ripple :: any)[name], quality[2], quality[3], sizes)
		if spacing == math.huge or spacing <= 0 then
			continue
		end
		local courant = 2 * ripple.waveStudsPerSecond * ripple.substep / spacing
		expect(
			problems,
			courant <= MAX_WAVE_COURANT,
			`{p}: 2 · waveStudsPerSecond · substep / spacing = {studs(courant)} for {name} (smallest spacing `
				.. `{studs(spacing)}) must be <= {MAX_WAVE_COURANT}, or the ripple is unstable`
		)
	end
end

-- UI FINAL R2: the motion kit's F8 / F9 checks (Config/ValidateUIMotion: apart, so this script stays under Roblox's
-- 200,000-character Source limit), on this script's check helpers.
local uiMotion = require(script.ValidateUIMotion)({
	add = add,
	expect = expect,
	expectPositive = expectPositive,
	expectNonNegative = expectNonNegative,
	expectCount = expectCount,
	expectBetween = expectBetween,
	expectBoolean = expectBoolean,
	isNumber = isNumber,
	show = show,
	studs = studs,
	sortedKeys = sortedKeys,
	maxFlickerHz = MAX_FLICKER_HZ,
	feelSlack = FEEL_SLACK,
}, UI, Audio)

-- F8 Audio: pitchMin in (0, 1], pitchMax >= 1; countdownPitch has 3 values within [pitchMin, pitchMax] (and the
-- sudden-death go pitch too); every cap >= 1 (perKeyCap, othersThrowMax; VoiceCaps and the cooldowns >= 0 are
-- checkAudio's); the new ducks within [0, 1]; and, with AssetTable, every toastSounds and perKeyCap key is a sound slot.
local function checkFeelAudio(problems: Problems, AssetTableModule: any?)
	local p = "F8: Config.Audio"
	local low, high = Audio.pitchMin, Audio.pitchMax
	local rangeOk = isNumber(low) and isNumber(high) and low > 0 and low <= 1 and high >= 1
	expect(problems, rangeOk, `{p} must satisfy 0 < pitchMin <= 1 <= pitchMax (got {show(low)}, {show(high)})`)
	local pitches = Audio.countdownPitch
	expect(
		problems,
		#pitches == COUNTDOWN_PITCHES,
		`{p}.countdownPitch must list {COUNTDOWN_PITCHES} pitches (got {#pitches})`
	)
	if rangeOk then
		for index, pitch in pitches do
			expectBetween(problems, `{p}.countdownPitch[{index}]`, pitch, low, high)
		end
		expectBetween(problems, `{p}.suddenDeathGoPitch`, Audio.suddenDeathGoPitch, low, high)
		uiMotion.pitches(problems, p, low, high) -- UI FINAL R2: the UI pitches
	end
	local perKeyCap = Audio.perKeyCap :: { [string]: number }
	for _, key in sortedKeys(perKeyCap) do
		expectCount(problems, `{p}.perKeyCap[{show(key)}]`, perKeyCap[key], 1)
	end
	expectPositive(problems, `{p}.Spatial.othersThrowStuds`, Audio.Spatial.othersThrowStuds)
	expectCount(problems, `{p}.Spatial.othersThrowMax`, Audio.Spatial.othersThrowMax, 1)
	expectBetween(problems, `{p}.Ducking.knockout`, Audio.Ducking.knockout, 0, 1)
	expectBetween(problems, `{p}.Ducking.telegraph`, Audio.Ducking.telegraph, 0, 1)
	expectPositive(problems, `{p}.Ducking.knockoutSeconds`, Audio.Ducking.knockoutSeconds)
	expectNonNegative(problems, `{p}.wobbleAfterImpactMs`, Audio.wobbleAfterImpactMs)
	expectBetween(problems, `{p}.softImpactMinorVolume`, Audio.softImpactMinorVolume, 0, 1)
	expectNonNegative(problems, `{p}.trackedStopFadeMs`, Audio.trackedStopFadeMs)
	expectCount(problems, `{p}.recentLogSize`, Audio.recentLogSize, 1)

	if AssetTableModule == nil then
		return
	end
	local slots, slotsErr = callList(AssetTableModule, "AssetTable", "all")
	if slots == nil then
		add(problems, `F8: {slotsErr}`)
		return
	end
	local soundKeys: { [string]: boolean } = {}
	for _, slot in slots do
		if type(slot) == "table" and slot.kind == "sound" and type(slot.key) == "string" then
			soundKeys[slot.key] = true
		end
	end
	local toastSounds = Audio.toastSounds :: { [string]: string }
	for _, code in sortedKeys(toastSounds) do
		local key = toastSounds[code]
		expect(
			problems,
			type(key) == "string" and soundKeys[key] == true,
			`{p}.toastSounds[{show(code)}] = {show(key)} is not a sound key in AssetTable`
		)
	end
	for _, key in sortedKeys(perKeyCap) do
		expect(problems, soundKeys[key] == true, `{p}.perKeyCap[{show(key)}] is not a sound key in AssetTable`)
	end
end

-- One feel pass spring (F9): ω > 0, 0 < ζ < 1 and the damped frequency ω·√(1 − ζ²) / 2π <= 3 Hz.
local function checkFeelSpring(problems: Problems, path: string, omega: unknown, zeta: unknown)
	local omegaOk = isNumber(omega) and (omega :: number) > 0
	local zetaOk = isNumber(zeta) and (zeta :: number) > 0 and (zeta :: number) < 1
	expect(problems, omegaOk, `F9: {path} omega must be > 0 (got {show(omega)})`)
	expect(problems, zetaOk, `F9: {path} zeta must be in (0, 1) (got {show(zeta)})`)
	if omegaOk and zetaOk then
		local w, z = omega :: number, zeta :: number
		local hz = w * math.sqrt(1 - z * z) / (2 * math.pi)
		expect(
			problems,
			hz <= MAX_FLICKER_HZ + FEEL_SLACK,
			`F9: {path} wobbles at {studs(hz)} Hz (ω·√(1 − ζ²) / 2π), above {MAX_FLICKER_HZ} Hz (§9.12)`
		)
	end
end

-- F9 UI juice: ms > 0 for buttonShake, buttonPress, coinFlight, toast, badgePop and readyPop; 1 <= coinFlight.count <=
-- maxCoins; the springs (Vfx.HeldBoing, Anim.held.motionJiggle, Anim.jellyRipple.pathB) pass checkFeelSpring. Also
-- <= 3 Hz (§9.12, §18.1 #4): the coin pill bounce (1000 / coinFlight.bounceMinGapMs: a flight's coins land about 60 ms
-- apart, so the gap sets the rate). UI FINAL R2 (the motion kit; checkUIJuice's R2 half below): the curves, the loops,
-- the swings, the tracks, the bars, toggles and shines, the coin flight and the design effects.
local function checkUIJuice(problems: Problems)
	local motion = UI.motion :: any
	local p = "F9: Config.UI.motion"
	for _, name in { "buttonShake", "buttonPress", "coinFlight", "toast", "badgePop", "readyPop" } do
		local entry = motion[name]
		expectPositive(problems, `{p}.{name}.ms`, if type(entry) == "table" then entry.ms else nil)
	end
	local flight = motion.coinFlight
	expectPositive(problems, `{p}.coinFlight.bounceMinGapMs`, flight.bounceMinGapMs)
	if isNumber(flight.bounceMinGapMs) and flight.bounceMinGapMs > 0 then
		local hz = 1000 / flight.bounceMinGapMs
		expect(
			problems,
			hz <= MAX_FLICKER_HZ + FEEL_SLACK,
			`{p}.coinFlight.bounceMinGapMs lets the pill bounce at {studs(hz)} Hz, above {MAX_FLICKER_HZ} Hz (§9.12)`
		)
	end
	expectCount(problems, `{p}.coinFlight.count`, flight.count, 1)
	expect(
		problems,
		isNumber(flight.count) and isNumber(flight.maxCoins) and flight.count <= flight.maxCoins,
		`{p}.coinFlight.count ({show(flight.count)}) must be <= maxCoins ({show(flight.maxCoins)})`
	)
	checkFeelSpring(problems, "Config.Vfx.HeldBoing", Vfx.HeldBoing.omega, Vfx.HeldBoing.zeta)
	local jiggle = Anim.held.motionJiggle
	checkFeelSpring(problems, "Config.Anim.held.motionJiggle", jiggle.omega, jiggle.zeta)
	local pathB = Anim.jellyRipple.pathB
	checkFeelSpring(problems, "Config.Anim.jellyRipple.pathB", pathB.omega, pathB.zeta)
	uiMotion.motion(problems)
end

-- F10 Editable meshes per client: Budgets.editableMeshes >= (1 when jellyRipple.pathA) + 1: one ripple skin, never two
-- skins (§18.3.4), plus Inspect's knead shell (spec phase2-squeeze §3.2, MeshQuota key "soft"). The giant pads' meshes
-- went with the pads (build plan Phase 6).
local KNEAD_SHELL_MESHES = 1

local function checkEditableMeshes(problems: Problems)
	local skins = if Anim.jellyRipple.pathA ~= false then 1 else 0
	local budget = Vfx.Budgets.editableMeshes
	expect(
		problems,
		isNumber(budget) and budget >= skins + KNEAD_SHELL_MESHES,
		`F10: Config.Vfx.Budgets.editableMeshes ({show(budget)}) must be >= the ripple skin ({skins}) + the knead `
			.. `shell ({KNEAD_SHELL_MESHES})`
	)
end

-- F11 Splat red guard: redGuardWhiten >= 1 - redMinSaturation (whitening by t leaves a saturation <= 1 - t, so no
-- accent can stay red).
local function checkSplatRedGuard(problems: Problems)
	local splat = Vfx.Splat
	local p = "F11: Config.Vfx.Splat"
	expectBetween(problems, `{p}.redGuardWhiten`, splat.redGuardWhiten, 0, 1)
	expectBetween(problems, `{p}.redMinSaturation`, splat.redMinSaturation, 0, 1)
	expect(
		problems,
		splat.redGuardWhiten >= 1 - splat.redMinSaturation - FEEL_SLACK,
		`{p}.redGuardWhiten ({num(splat.redGuardWhiten)}) must be >= 1 - redMinSaturation `
			.. `({num(1 - splat.redMinSaturation)}), or a red accent stays red`
	)
end

-- Private: cross-module checks (modules added in later parts) -------------------------------------------------------

local function checkRarityModule(problems: Problems, Rarity: any): { string }
	local order = Rarity.ORDER
	local same = type(order) == "table" and #order == #RARITY_ORDER
	if same then
		for index, rarity in RARITY_ORDER do
			same = same and order[index] == rarity
		end
	end
	if not same then
		add(problems, `Rarity.ORDER must be {table.concat(RARITY_ORDER, ", ")} (DESIGN §0.3)`)
		return RARITY_ORDER
	end
	return order
end

-- Returns the catalog defs by id (nil when the catalog can't be read). `blueprints` is Art/SquishyBlueprints (nil
-- while it does not exist: the blueprintId check is skipped).
local function checkCatalog(problems: Problems, Catalog: any, rarities: { string }, blueprints: any): { [string]: any }?
	local list, err = callList(Catalog, "Catalog", "list")
	if err then
		add(problems, err)
		return nil
	end
	local isRarity: { [string]: boolean } = {}
	for _, rarity in rarities do
		isRarity[rarity] = true
	end

	local byId: { [string]: any } = {}
	for index, def in list do
		if type(def) ~= "table" or type(def.id) ~= "string" then
			add(problems, `Catalog entry {index} has no string id`)
			continue
		end
		local path = `Catalog.{def.id}`
		expectId(problems, `{path}.id`, def.id)
		expect(problems, byId[def.id] == nil, `{path} is listed twice`)
		byId[def.id] = def
		expect(problems, isRarity[def.rarity] == true, `{path}.rarity {show(def.rarity)} is not a rarity`)

		local throw = def.throw
		if type(throw) ~= "table" then
			add(problems, `{path}.throw is missing`)
		else
			for _, stat in THROW_STATS do
				local band = Combat.Bands[stat]
				if band then
					expectBetween(problems, `{path}.throw.{stat}`, throw[stat], band.min, band.max)
				end
			end
		end

		if def.ultimateId ~= nil then
			local ability = if type(def.ultimateId) == "string" then Abilities[def.ultimateId] else nil
			expect(problems, ability ~= nil, `{path}.ultimateId {show(def.ultimateId)} is not in Config.Abilities`)
			-- User decision 2026-10-11 (design: fp.js:576): "Ultimates are reserved for Epic and Exclusive squishies".
			expect(
				problems,
				ULTIMATE_RARITIES[def.rarity] == true,
				`{path} has an ultimate but only Epics and Exclusives get one`
			)
			-- Spec phase 5: a volley's or a bubble's projectile is the squishy's own throw size (the game's normal
			-- projectile hit radius, user decision 2026-10-11).
			if ability ~= nil and (ability.kind == "volley" or ability.kind == "bubble") and type(throw) == "table" then
				expect(
					problems,
					ability.radius == throw.radius,
					`{path}.throw.radius {show(throw.radius)} must equal Config.Abilities.{def.ultimateId}.radius `
						.. `{show(ability.radius)} (its projectiles are the squishy's own throw size)`
				)
			end
		end
		if def.power ~= nil then
			expectCount(problems, `{path}.power`, def.power, 1)
		end
		if def.shopPrice ~= nil then
			expectCount(problems, `{path}.shopPrice`, def.shopPrice, 1)
		end
		if type(def.anim) == "table" then
			expectBetween(
				problems,
				`{path}.anim.foamRecoveryT`,
				def.anim.foamRecoveryT,
				Anim.squeeze.foamRecoveryMin,
				Anim.squeeze.foamRecoveryMax
			)
			local fxName = def.anim.squeezeFx
			expect(
				problems,
				fxName == nil or (type(fxName) == "string" and Anim.squeeze.squeezeFx[fxName] ~= nil),
				`{path}.anim.squeezeFx {show(fxName)} is not a hook in Config.Anim.squeeze.squeezeFx`
			)
		end
		-- §4.1: the blueprint exists (Art/SquishyBuilder builds every model the game shows from it), with its squishy
		-- overhaul motion row (spec 2026-10-09 §3.2: the rig's squeeze, feel and flight).
		if type(def.blueprintId) ~= "string" then
			add(problems, `{path}.blueprintId must be a string (got {show(def.blueprintId)})`)
		elseif blueprints ~= nil then
			local blueprint = blueprints[def.blueprintId]
			expect(
				problems,
				blueprint ~= nil,
				`{path}.blueprintId {show(def.blueprintId)} is not in Art/SquishyBlueprints`
			)
			expect(
				problems,
				blueprint == nil or blueprint.motion ~= nil,
				`{path}: blueprint {show(def.blueprintId)} has no motion row (Art/SquishyBlueprints, spec 2026-10-09 §3.2)`
			)
		end
	end

	for id, def in byId do
		if def.robuxOnly then
			local equivalent = if type(def.equivalentId) == "string" then byId[def.equivalentId] else nil
			expect(
				problems,
				equivalent ~= nil and not equivalent.robuxOnly and equivalent.shopPrice ~= nil,
				`Catalog.{id}.equivalentId must point to a Coin-buyable squishy (DESIGN §6.12)`
			)
		end
	end

	local starterFn = Catalog.starterId
	if type(starterFn) ~= "function" then
		add(problems, "Catalog.starterId() is missing")
	else
		local ok, starterId = pcall(starterFn)
		expect(
			problems,
			ok and starterId == STARTER_ID,
			`Catalog.starterId() must be {show(STARTER_ID)} (got {show(starterId)})`
		)
	end
	local starter = byId[STARTER_ID]
	if starter == nil then
		add(problems, `Catalog has no starter {show(STARTER_ID)}`)
	else
		expect(problems, starter.rarity == "Common", `Catalog.{STARTER_ID} must be Common`)
		expect(problems, starter.shopPrice == nil, `Catalog.{STARTER_ID} is the free starter and must not be sold`)
	end
	return byId
end

local function boxItem(item: any): (any, any)
	if type(item) ~= "table" then
		return nil, nil
	end
	return item.id or item[1], item.weight or item[2]
end

-- Returns the box list (nil when Boxes can't be read).
local function checkBoxes(problems: Problems, Boxes: any, defs: { [string]: any }?): { any }?
	local list: any
	if type(Boxes.list) == "function" then
		local err
		list, err = callList(Boxes, "Boxes", "list")
		if err then
			add(problems, err)
			return nil
		end
	elseif type(Boxes.List) == "table" then
		list = Boxes.List
	else
		add(problems, "Boxes has neither list() nor List")
		return nil
	end
	if Boxes.WeightTotal ~= nil then
		expect(problems, Boxes.WeightTotal == BOX_WEIGHT_TOTAL, `Boxes.WeightTotal must be {BOX_WEIGHT_TOTAL}`)
	end

	local byId: { [string]: any } = {}
	for index, box in list do
		if type(box) ~= "table" or type(box.id) ~= "string" then
			add(problems, `Boxes entry {index} has no string id`)
			continue
		end
		local path = `Boxes.{box.id}`
		expectId(problems, `{path}.id`, box.id)
		expect(problems, byId[box.id] == nil, `{path} is listed twice`)
		byId[box.id] = box
		if box.paid == true then
			expectCount(problems, `{path}.cost`, box.cost, 1)
		else
			expect(problems, box.cost == nil, `{path} is free-only and must have no cost`)
		end

		local items = box.items
		if type(items) ~= "table" or #items == 0 then
			add(problems, `{path}.items must list at least one squishy`)
			continue
		end
		local total = 0
		local inBox: { [string]: boolean } = {}
		for itemIndex, item in items do
			local id, weight = boxItem(item)
			local itemPath = `{path}.items[{itemIndex}]`
			expectCount(problems, `{itemPath} weight`, weight, 1)
			total += if isNumber(weight) then weight else 0
			if type(id) ~= "string" then
				add(problems, `{itemPath} has no squishy id`)
				continue
			end
			expect(problems, not inBox[id], `{path} lists {id} twice`)
			inBox[id] = true
			expect(problems, id ~= STARTER_ID, `{path} must not contain the free starter {STARTER_ID}`)
			if defs then
				local def = defs[id]
				if def == nil then
					add(problems, `{itemPath} squishy {show(id)} is not in the Catalog`)
				else
					expect(problems, not def.robuxOnly, `{path} must not contain the Robux-only squishy {id}`)
				end
			end
		end
		expect(problems, total == BOX_WEIGHT_TOTAL, `{path} item weights sum to {total}, not {BOX_WEIGHT_TOTAL}`)
	end

	local freeBox = byId[Economy.Daily.freeBoxId]
	expect(
		problems,
		freeBox ~= nil and freeBox.paid ~= true,
		`Config.Economy.Daily.freeBoxId {show(Economy.Daily.freeBoxId)} must be a free-only box in Boxes`
	)
	-- Spec 2026-10-12 §8: a free box's double refunds a share of this paid box's price.
	local pricedAs = Economy.DuplicateRefund.freeBoxPriceOf
	local priced = byId[pricedAs]
	expect(
		problems,
		priced ~= nil and priced.paid == true,
		`Config.Economy.DuplicateRefund.freeBoxPriceOf {show(pricedAs)} must be a paid box in Boxes`
	)
	return list
end

local function checkPricing(problems: Problems, Pricing: any, defs: { [string]: any })
	local ceiling = Pricing.ceiling
	if type(ceiling) ~= "function" then
		add(problems, "Pricing.ceiling() is missing")
		return
	end
	for _, id in sortedKeys(defs) do
		local price = defs[id].shopPrice
		if isNumber(price) then
			local ok, limit = pcall(ceiling, id)
			if not ok then
				add(problems, `Pricing.ceiling({show(id)}) failed: {tostring(limit)}`)
			elseif isNumber(limit) then
				expect(
					problems,
					price <= limit,
					`Catalog.{id}.shopPrice ({price}) must not exceed Pricing.ceiling ({limit}, DESIGN §6.6)`
				)
			end
		end
	end
end

-- Returns the quest def list (nil when QuestDefs can't be read).
local function checkQuestDefs(problems: Problems, QuestDefs: any): { any }?
	local list, err = callList(QuestDefs, "QuestDefs", "list")
	if err then
		add(problems, err)
		return nil
	end
	local ids: { [string]: boolean } = {}
	local daily = 0
	local dailyCategories: { [string]: boolean } = {}
	local isCategory: { [string]: boolean } = {}
	for _, category in QUEST_CATEGORIES do
		isCategory[category] = true
	end
	for index, def in list do
		if type(def) ~= "table" or type(def.id) ~= "string" then
			add(problems, `QuestDefs entry {index} has no string id`)
			continue
		end
		local path = `QuestDefs.{def.id}`
		expect(problems, not ids[def.id], `{path} is listed twice`)
		ids[def.id] = true
		local isStarter = string.sub(def.id, 1, #STARTER_TASK_PREFIX) == STARTER_TASK_PREFIX
		if isStarter then
			expect(
				problems,
				#def.id <= ID_MAX_LENGTH and string.match(def.id, STARTER_TASK_PATTERN) ~= nil,
				`{path} must match {STARTER_TASK_PATTERN} with at most {ID_MAX_LENGTH} characters`
			)
		else
			expectId(problems, `{path}.id`, def.id)
			daily += 1
			if type(def.category) == "string" then
				dailyCategories[def.category] = true
			end
		end

		-- Part 7 fields (§6.8): kind matches the id, known category and counts, positive integer variants.
		expect(
			problems,
			QUEST_KINDS[def.kind] == true,
			`{path}.kind must be "daily" or "starter" (got {show(def.kind)})`
		)
		expect(
			problems,
			(def.kind == "starter") == isStarter,
			`{path}.kind {show(def.kind)} must be "starter" exactly when the id starts with {STARTER_TASK_PREFIX}`
		)
		expect(
			problems,
			type(def.category) == "string" and isCategory[def.category] == true,
			`{path}.category must be one of {table.concat(QUEST_CATEGORIES, ", ")} (got {show(def.category)})`
		)
		expect(
			problems,
			type(def.counts) == "string" and QUEST_COUNTS[def.counts] == true,
			`{path}.counts {show(def.counts)} is not a progress rule QuestLogic knows`
		)
		expectBoolean(problems, `{path}.needsSquishy`, def.needsSquishy)
		expectText(problems, `{path}.textPair`, def.textPair)
		local variants = def.variants
		if type(variants) ~= "table" or #variants == 0 then
			add(problems, `{path}.variants must list at least one goal/reward pair`)
		else
			expect(
				problems,
				not isStarter or #variants == 1,
				`{path} is a starter task and must have exactly one variant`
			)
			for variantIndex, variant in variants do
				local variantPath = `{path}.variants[{variantIndex}]`
				if type(variant) ~= "table" then
					add(problems, `{variantPath} must be a goal/reward pair`)
				else
					expectCount(problems, `{variantPath}.goal`, variant.goal, 1)
					expectCount(problems, `{variantPath}.reward`, variant.reward, 1)
				end
			end
		end
	end
	expect(
		problems,
		daily >= Economy.Quests.perDay,
		`QuestDefs has {daily} daily templates; Config.Economy.Quests.perDay needs {Economy.Quests.perDay}`
	)
	-- Slot 1 is a squeeze template, slot 2 a duel template, and a swap may turn a duel quest into a squeeze or practice
	-- quest (§6.8): the daily templates must cover all three categories.
	for _, category in QUEST_CATEGORIES do
		expect(problems, dailyCategories[category] == true, `QuestDefs has no daily template of category {category}`)
	end
	return list
end

-- Every quest's textPair names a Strings { one, many } pair (QuestDefs.text picks one with Strings.plural).
local function checkQuestTexts(problems: Problems, quests: { any }, Strings: any)
	local resolve = Strings.resolve
	if type(resolve) ~= "function" then
		return -- reported by the Strings keys check
	end
	for _, def in quests do
		if type(def) == "table" and type(def.textPair) == "string" then
			for _, form in { "one", "many" } do
				local key = `{def.textPair}.{form}`
				local ok, text = pcall(resolve, key)
				expect(
					problems,
					ok and type(text) == "string" and text ~= "",
					`QuestDefs.{tostring(def.id)}.textPair needs the Strings text {key}`
				)
			end
		end
	end
end

local function checkStrings(problems: Problems, Strings: any, refs: { KeyRef })
	local resolve = Strings.resolve
	if type(resolve) ~= "function" then
		add(problems, "Strings.resolve() is missing: Strings keys were not checked")
		return
	end
	for _, ref in refs do
		local ok, text = pcall(resolve, ref.key)
		expect(problems, ok and type(text) == "string", `{ref.path}: Strings key {show(ref.key)} does not exist`)
	end
end

-- Runs one group of checks. The checks assume each value has the shape the section files give it; when a value is
-- missing or has the wrong type a check can raise (e.g. comparing nil). That is reported as one problem line and
-- the remaining groups still run, so validate() never errors (the bootstraps rely on it to warn and fail closed).
-- Batch 3 (friends): Config.Social. `defs` (the checked Catalog, nil when it did not load) names the squishies a badge
-- may ask for.
local function checkSocial(problems: Problems, rarities: { string }, defs: { [string]: any }?)
	local p = "Config.Social"
	local pads = Social.Pads
	eachField(problems, `{p}.Pads`, pads, { "checkHz", "holdSeconds", "radiusStuds", "heightStuds" }, expectPositive)
	expectNonNegative(problems, `{p}.Pads.waitingToastSeconds`, pads.waitingToastSeconds)

	-- The offer outlives the result card: the Result phase, both return fades, the card's auto-close after the return
	-- and the requeue cooldown a rematch waits out.
	local window = Social.Rematch.windowSeconds
	local need = Duel.Rules.ResultSeconds
		+ 2 * Duel.Positioning.ReturnFadeSeconds
		+ UI.Result.autoCloseAfterReturnSeconds
		+ Duel.Rules.RequeueCooldownSeconds
	expect(
		problems,
		isNumber(window) and window >= need,
		`{p}.Rematch.windowSeconds ({show(window)}) must be >= {need} s: the Result phase, both return fades, the `
			.. `result card's auto-close and the requeue cooldown, so the card never outlives the offer`
	)

	local board = Social.Board
	expectCount(problems, `{p}.Board.size`, board.size, 1)
	expect(
		problems,
		isInteger(board.readSize) and board.readSize >= board.size and board.readSize <= MAX_SORTED_PAGE,
		`{p}.Board.readSize must be a whole number in {show(board.size)}..{MAX_SORTED_PAGE} `
			.. `(got {show(board.readSize)})`
	)
	expectPositive(problems, `{p}.Board.refreshSeconds`, board.refreshSeconds)
	expectText(problems, `{p}.Board.storeName`, board.storeName)
	expect(
		problems,
		type(board.studioStoreName) == "string"
			and string.sub(board.studioStoreName, -#STUDIO_STORE_SUFFIX) == STUDIO_STORE_SUFFIX,
		`{p}.Board.studioStoreName must end in "{STUDIO_STORE_SUFFIX}" (got {show(board.studioStoreName)})`
	)
	expect(
		problems,
		isNumber(board.weekOffsetSeconds)
			and board.weekOffsetSeconds >= 0
			and board.weekOffsetSeconds < SECONDS_PER_WEEK,
		`{p}.Board.weekOffsetSeconds must be in [0, {SECONDS_PER_WEEK}) (got {show(board.weekOffsetSeconds)})`
	)

	local badges = Social.Badges
	expectPositive(problems, `{p}.Badges.checkSeconds`, badges.checkSeconds)
	expectCount(problems, `{p}.Badges.maxTries`, badges.maxTries, 1)
	local known: { [string]: boolean } = {}
	for _, rarity in rarities do
		known[rarity] = true
	end
	local keys: { [string]: boolean } = {}
	for index, badge in badges.list do
		local at = `{p}.Badges.list[{index}]`
		local key = badge.key
		expect(
			problems,
			type(key) == "string" and string.match(key, BADGE_KEY_PATTERN) ~= nil,
			`{at}.key must match {BADGE_KEY_PATTERN} (got {show(key)})`
		)
		if type(key) == "string" then
			expect(problems, not keys[key], `{at}.key {show(key)} is used twice`)
			keys[key] = true
		end
		expect(
			problems,
			badge.id == nil or (isInteger(badge.id) and (badge.id :: number) > 0),
			`{at}.id must be nil (not created yet) or a whole number > 0 (got {show(badge.id)})`
		)
		local rule = badge.rule
		local kind = if type(rule) == "table" then rule.kind else nil
		if type(kind) ~= "string" or not BADGE_RULES[kind] then
			add(problems, `{at}.rule.kind {show(kind)} is not a badge rule`)
		elseif kind == "stat" or kind == "gripLevel" then
			expectCount(problems, `{at}.rule.atLeast`, rule.atLeast, 1)
			if kind == "stat" then
				expectText(problems, `{at}.rule.stat`, rule.stat)
			end
		elseif kind == "ownRarityAll" then
			expect(problems, known[rule.rarity or ""] == true, `{at}.rule.rarity {show(rule.rarity)} is not a rarity`)
		elseif kind == "own" then
			expect(
				problems,
				defs == nil or (type(rule.squishyId) == "string" and defs[rule.squishyId] ~= nil),
				`{at}.rule.squishyId {show(rule.squishyId)} is not a Catalog squishy`
			)
		elseif kind == "flag" then
			expectText(problems, `{at}.rule.flag`, rule.flag)
		end
	end
end

local function guarded(problems: Problems, label: string, run: () -> ...any)
	local ok, err = pcall(run)
	if not ok then
		add(problems, `{label} check crashed (a value is missing or has the wrong type): {tostring(err)}`)
	end
end

-- Public ----------------------------------------------------------------------------------------------------------

-- G7 Robux allowlist and G7b bundles-off-while-Grip (§17.9, §6.11; Part 7) on plain tables: `monetization` shaped
-- like Config.Monetization, `grip` like Config.Grip, `resolveText(key)` -> the Strings text of a key (nil = unknown;
-- nil function = no text checks). Returns "G7: ..." / "G7b: ..." lines (empty = valid) and never errors, so tests can
-- pass broken fakes (a nameKey whose text is "Golden Gripper") that a frozen Strings could not hold.
--   G7: every coin bundle has only the fields key, nameKey, productId, coins, onSale; every game pass has a `benefit`
--       listed in CosmeticBenefits; no bundle or pass key, pass benefit, nameKey or nameKey text contains (lower-cased,
--       plain find) grip, train, rested, afk, idle, squeeze, pad, cushion, level or capsule.
--   G7b: while Grip is on and allowBundlesWithCapsules is false, no coin bundle has a productId (G-E). Reading: fails
--        closed, so a missing `enabled` counts as on and anything but allowBundlesWithCapsules = true counts as false.
function Config.robuxProblems(monetization: any, grip: any, resolveText: ((key: string) -> string?)?): { string }
	local problems: Problems = {}
	local p = "Config.Monetization"
	if type(monetization) ~= "table" then
		add(problems, `G7: {p} must be a table (got {show(monetization)})`)
		return problems
	end

	local function textOf(key: unknown): string?
		if resolveText == nil or type(key) ~= "string" then
			return nil
		end
		local ok, text = pcall(resolveText, key)
		return if ok and type(text) == "string" then text else nil
	end
	-- One line per value that names the lobby training (the first banned word found).
	local function noTraining(label: string, value: unknown)
		if type(value) ~= "string" then
			return
		end
		local lower = string.lower(value)
		for _, word in ROBUX_BANNED_WORDS do
			if string.find(lower, word, 1, true) ~= nil then
				add(
					problems,
					`G7: {label} {show(value)} mentions {show(word)}: Robux never buys or names the lobby training `
						.. "(§6.11, §17.2 rule 4)"
				)
				return
			end
		end
	end
	local function noTrainingName(path: string, nameKey: unknown)
		noTraining(`{path}.nameKey`, nameKey)
		noTraining(`{path}.nameKey {show(nameKey)} text`, textOf(nameKey))
	end

	local benefits: { [string]: boolean } = {}
	local cosmetic = monetization.CosmeticBenefits
	if type(cosmetic) ~= "table" then
		add(problems, `G7: {p}.CosmeticBenefits must be a list of benefit names (got {show(cosmetic)})`)
	else
		for index, benefit in cosmetic do
			if type(benefit) ~= "string" or benefit == "" then
				add(problems, `G7: {p}.CosmeticBenefits[{tostring(index)}] must be a non-empty string`)
			else
				benefits[benefit] = true
			end
		end
	end

	local configured: { string } = {}
	local bundles = monetization.CoinBundles
	if type(bundles) ~= "table" then
		add(problems, `G7: {p}.CoinBundles must be a list (got {show(bundles)})`)
	else
		for index, bundle in bundles do
			local path = `{p}.CoinBundles[{tostring(index)}]`
			if type(bundle) ~= "table" then
				add(problems, `G7: {path} must be a table`)
				continue
			end
			for _, field in sortedKeys(bundle) do
				expect(
					problems,
					type(field) == "string" and BUNDLE_FIELDS[field] == true,
					`G7: {path} has the field {show(field)}; a coin bundle may only have key, nameKey, productId, `
						.. "coins and onSale"
				)
			end
			noTraining(`{path}.key`, bundle.key)
			noTrainingName(path, bundle.nameKey)
			if bundle.productId ~= nil then
				table.insert(configured, path)
			end
		end
	end

	local passes = monetization.GamePasses
	if type(passes) ~= "table" then
		add(problems, `G7: {p}.GamePasses must be a list (got {show(passes)})`)
	else
		for index, pass in passes do
			local path = `{p}.GamePasses[{tostring(index)}]`
			if type(pass) ~= "table" then
				add(problems, `G7: {path} must be a table`)
				continue
			end
			local benefit = pass.benefit
			expect(
				problems,
				type(benefit) == "string" and benefits[benefit] == true,
				`G7: {path}.benefit {show(benefit)} must be one of {p}.CosmeticBenefits`
			)
			noTraining(`{path}.key`, pass.key)
			noTraining(`{path}.benefit`, benefit)
			noTrainingName(path, pass.nameKey)
		end
	end

	local gripOn = type(grip) ~= "table" or grip.enabled ~= false
	local bundlesAllowed = type(grip) == "table" and grip.allowBundlesWithCapsules == true
	if gripOn and not bundlesAllowed then
		for _, path in configured do
			add(
				problems,
				`G7b: {path}.productId is set while Config.Grip.enabled and allowBundlesWithCapsules is false: coin `
					.. "bundles stay off while Grip is on (G-E, §6.11)"
			)
		end
	end
	return problems
end

-- Returns every problem found, as human-readable lines (empty = valid). Never errors: a check that crashes on a
-- malformed section becomes a problem line. `deps` is optional (see ValidateDeps).
function Config.validate(deps: ValidateDeps?): { string }
	local problems: Problems = {}

	local rarities = RARITY_ORDER
	local Rarity, rarityErr = loadSibling("Rarity")
	if rarityErr then
		add(problems, `Rarity failed to load: {rarityErr}`)
	elseif Rarity ~= nil then
		guarded(problems, "Rarity", function()
			rarities = checkRarityModule(problems, Rarity)
		end)
	end

	guarded(problems, "Config.Economy", function()
		checkEconomy(problems, rarities)
	end)
	guarded(problems, "Config.Squeeze", function()
		checkSqueeze(problems)
	end)
	guarded(problems, "Config.Combat", function()
		checkCombat(problems)
	end)
	guarded(problems, "Config.Duel", function()
		checkDuel(problems)
	end)
	guarded(problems, "Config.Abilities", function()
		checkAbilities(problems)
	end)
	guarded(problems, "Config.Data", function()
		checkData(problems)
	end)
	guarded(problems, "Config.Net", function()
		checkNet(problems)
	end)
	guarded(problems, "Config.Monetization", function()
		checkMonetization(problems)
	end)
	guarded(problems, "Config.UI", function()
		checkUI(problems)
	end)
	guarded(problems, "Config.Audio", function()
		checkAudio(problems)
	end)
	guarded(problems, "Config.Onboarding", function()
		checkOnboarding(problems)
	end)
	guarded(problems, "Config.Inspect", function()
		checkInspect(problems)
	end)
	guarded(problems, "Config.Anim", function()
		checkAnim(problems, rarities)
	end)
	guarded(problems, "Config.Anim.rig", function()
		checkRig(problems)
	end)
	guarded(problems, "Config.Vfx", function()
		checkVfx(problems)
	end)
	guarded(problems, "Config moves (dash and Epic ultimates)", function()
		checkMoves(problems)
	end)
	guarded(problems, "Config feature 1 (charge throw and catch)", function()
		checkChargeCatch(problems)
	end)
	guarded(problems, "Config.Debug", function()
		checkDebug(problems)
	end)
	guarded(problems, "Config.Match", function()
		checkMatch(problems)
	end)

	-- Grip (§17.9): G1-G3, G5 and the Capsule block on Config alone; G8 with WorldLayout.
	guarded(problems, "Config.Grip G1", function()
		checkGripLevels(problems)
	end)
	guarded(problems, "Config.Grip G2", function()
		checkGripPads(problems)
	end)
	guarded(problems, "Config.Grip G5", function()
		checkGripCaps(problems)
	end)
	guarded(problems, "Config.Grip G3", function()
		checkGripSqueezeCeiling(problems)
	end)
	guarded(problems, "Config.Grip.Capsule", function()
		checkGripCapsules(problems)
	end)
	guarded(problems, "Config.Grip settings", function()
		checkGripSettings(problems)
	end)
	local layout: any = if deps then deps.WorldLayout else nil
	if layout == nil then
		local loaded, layoutErr = loadSibling("World/WorldLayout")
		if layoutErr then
			add(problems, `World/WorldLayout failed to load: {layoutErr}`)
		end
		layout = loaded
	end
	if layout ~= nil then
		guarded(problems, "Config.Grip G8", function()
			checkGripWorld(problems, layout)
		end)
		guarded(problems, "Config.Combat reach", function()
			checkCombatReach(problems, layout)
		end)
	end

	-- Feel pass (§18.9): F1-F11; F7 reads the WorldLayout face sizes, F8 the AssetTable sound keys.
	local AssetTableModule, assetErr = loadSibling("AssetTable")
	if assetErr then
		add(problems, `AssetTable failed to load: {assetErr}`)
	end
	local feelChecks: { { any } } = {
		{ "F1", checkSqueezeTotal, rarities },
		{ "F2", checkEliminationBudget },
		{ "F3", checkPunch },
		{ "F4", checkHitStop },
		{ "F5", checkSplatBudget },
		{ "F6", checkMatPulse },
		{ "F7", checkJellyRipple, layout },
		{ "F8", checkFeelAudio, AssetTableModule },
		{ "F9", checkUIJuice },
		{ "F10", checkEditableMeshes },
		{ "F11", checkSplatRedGuard },
	}
	for _, entry in feelChecks do
		local check = entry[2] :: (Problems, any) -> ()
		guarded(problems, `Config feel pass {entry[1]}`, function()
			check(problems, entry[3])
		end)
	end

	-- Part 1 siblings: required.
	local Remotes, remotesErr = loadSibling("Remotes")
	if remotesErr then
		add(problems, `Remotes failed to load: {remotesErr}`)
	elseif Remotes == nil then
		add(problems, "Remotes.luau is missing: remote rate entries were not checked")
	else
		guarded(problems, "Remotes rate entries", function()
			checkRemoteRates(problems, Remotes)
		end)
	end

	-- Later parts: each check runs only once its module exists.
	local refs: { KeyRef } = {}
	guarded(problems, "Config Strings keys", function()
		collectStringKeys(Config, "Config", refs, {})
	end)

	local defs: { [string]: any }? = nil
	local Blueprints, blueprintsErr = loadSibling("Art/SquishyBlueprints")
	if blueprintsErr then
		add(problems, `Art/SquishyBlueprints failed to load: {blueprintsErr}`)
	elseif Blueprints ~= nil then
		guarded(problems, "Art/SquishyBlueprints motion", function()
			for _, id in sortedKeys(Blueprints) do
				local motion = Blueprints[id].motion
				if motion ~= nil then
					checkMotion(problems, `Art/SquishyBlueprints.{id}.motion`, motion)
				end
			end
		end)
	end
	local Catalog: any, catalogErr: string? = if deps then deps.Catalog else nil, nil
	if Catalog == nil then
		Catalog, catalogErr = loadSibling("Catalog")
	end
	if catalogErr then
		add(problems, `Catalog failed to load: {catalogErr}`)
	elseif Catalog ~= nil then
		guarded(problems, "Catalog", function()
			local found = checkCatalog(problems, Catalog, rarities, Blueprints)
			defs = found
			if found then
				collectStringKeys(found, "Catalog", refs, {})
			end
		end)
	end
	guarded(problems, "Config.Social", function()
		checkSocial(problems, rarities, defs)
	end)
	guarded(problems, "Config.FirstPerson", function()
		checkFirstPerson(problems)
	end)
	guarded(problems, "Config.Knead", function()
		checkKnead(problems)
	end)
	guarded(problems, "Config.Wax", function()
		checkWax(problems)
	end)
	guarded(problems, "Config knead screen", function()
		checkKneadScreen(problems)
	end)

	local Boxes, boxesErr = loadSibling("Boxes")
	if boxesErr then
		add(problems, `Boxes failed to load: {boxesErr}`)
	elseif Boxes ~= nil then
		guarded(problems, "Boxes", function()
			local boxes = checkBoxes(problems, Boxes, defs)
			if boxes then
				collectStringKeys(boxes, "Boxes", refs, {})
			end
		end)
	end

	local Pricing, pricingErr = loadSibling("Pricing")
	if pricingErr then
		add(problems, `Pricing failed to load: {pricingErr}`)
	elseif Pricing ~= nil and defs ~= nil then
		local catalogDefs: { [string]: any } = defs
		guarded(problems, "Pricing", function()
			checkPricing(problems, Pricing, catalogDefs)
		end)
	end

	local quests: { any }? = nil
	local QuestDefs: any, questErr: string? = if deps then deps.QuestDefs else nil, nil
	if QuestDefs == nil then
		QuestDefs, questErr = loadSibling("QuestDefs")
	end
	if questErr then
		add(problems, `QuestDefs failed to load: {questErr}`)
	elseif QuestDefs ~= nil then
		guarded(problems, "QuestDefs", function()
			quests = checkQuestDefs(problems, QuestDefs)
			if quests then
				collectStringKeys(quests, "QuestDefs", refs, {})
			end
		end)
	end

	local Strings, stringsErr = loadSibling("Strings")
	if stringsErr then
		add(problems, `Strings failed to load: {stringsErr}`)
	elseif Strings == nil then
		add(problems, "Strings.luau is missing: Strings keys were not checked")
	else
		guarded(problems, "Strings keys", function()
			checkStrings(problems, Strings, refs)
		end)
		guarded(problems, "Config.Grip G6", function()
			checkGripStrings(problems, Strings)
		end)
		local questList = quests
		if questList ~= nil then
			guarded(problems, "QuestDefs texts", function()
				checkQuestTexts(problems, questList, Strings)
			end)
		end
	end

	-- G7 / G7b (Part 7): the Robux guards, with the Strings texts of the names when Strings loaded.
	guarded(problems, "Config.Monetization G7", function()
		local resolveText = if Strings ~= nil and type(Strings.resolve) == "function" then Strings.resolve else nil
		for _, line in Config.robuxProblems(Monetization, Grip, resolveText) do
			add(problems, line)
		end
	end)

	return problems
end

deepFreeze(Config, {})

return Config
