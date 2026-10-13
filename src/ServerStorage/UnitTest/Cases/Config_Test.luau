--!strict
-- Config_Test: unit tests for ReplicatedStorage.Shared.Config. Server only (ServerStorage.UnitTest).
-- Squeeze feel (spec phase2-squeeze §3.11): Config.Knead and Config.Wax (the 18th and 19th sections) hold the design's
-- squish.js numbers (but the user's deeper finger dents of 2026-10-12); validate keeps jelly's 3.59 Hz knead spring as
-- the documented exception and reports a knead spring or depth spring above 3 Hz, a crunch faster than 3 presses a
-- second, broken shares, shell budgets and wax rules, and a wax switch (Config.Wax.enabled) that is not a boolean.
-- Contract (DESIGN §2.2, §0.3, §2.7, §2.8, §6.3, §6.11, §17.9): Config merges the 16 section modules and deep-freezes
-- them; Config.validate(): {string} returns human-readable problems, an empty list for the shipped config, and
-- reports broken cross-references (every client -> server remote needs a rate entry; every click pays, so the squeeze
-- rules are: the anti-autoclicker cap's bucketCapacity >= 1, floodPerSecond >= the cap, SqueezeRequest rate =
-- floodPerSecond with a burst of at least 5 s of the cap (a stall's backlog) and Global.burst >= it, and the
-- hold-to-squeeze repeat no shorter than any rarity's release pop; the RequestSnapshot bucket covers the loading
-- poll). It never errors: a
-- missing or mistyped value becomes a problem line. Robux stays off: no product or pass ids are configured.
-- Grip rules (§17.9 table, §17.12 Part 3): each of G1, G2, G5, G8 and G10 catches a deliberately broken copy.
-- Part 5 (§17.12): G3 (a squeeze count since spec 2026-10-12 §12: a 13-a-second cap and a ceiling of 43,199 fail, the
-- limit switched back on passes) and G6's Strings names; plus the Part 5 values of Data, UI.Grip and Config.Grip.
-- Feel pass (§18.8, §18.9, §18.10 L1): every §18.8 key holds its DESIGN value, and each rule F1-F11 catches a planted
-- bad value (among them: a 5° punch, a squeeze total of 20, an unstable wave speed and skinMode = "x").
-- Part 7 (§17.12 Part 7 L1): G7 and G7b
-- with the negatives of §17.12 word for word through Config.robuxProblems (pass benefit "grip", a bundle with an extra
-- rested field, pass keys grip_boost / afk_boost / slow_training_boost / royal_pad_pass, nameKey texts "Golden
-- Gripper" and "Royal Cushion VIP", a productId while allowBundlesWithCapsules is false; spec 2026-10-12 adds a
-- capsule_boost pass key); QuestDefs checks through
-- Config.validate({ QuestDefs = fake }); Onboarding.skipStepId; UI.Boxes / UI.Shop; the Part 7 values.
-- Part 6 (Inspect readings): the preview dot, drag speed filter and Collection display values, and their negatives
-- (non-positive sizes and times, dotSpeedMinPx above dotSpeedMaxPx, a negative margin or spin, a bad nameplate size).
-- Part 8 (nameplate polish readings): fadeStuds 10, checkSeconds 0.25, ownHideStuds 1.5, and their negatives (a fade of
-- 0 or of the whole maxDistance, a check period of 0, a negative own hide, missing values; 0 own hide is allowed).
-- Squishy overhaul (spec 2026-10-09 §3.2, §6): the SquishRig values (feels, kicks, face, blink, looks, sections,
-- flight styles, flourishes, framing margin, detail budgets); validate reports a motion row outside the §6 ranges (depth
-- 0.55-0.72, widen 0.4-0.85, kRel 20-60, cRel 6-10), an unknown feel or style, a Catalog squishy without a motion row,
-- rig motion above 3 Hz (flaps 2.5 Hz, roll 720°/s), a face that can toggle faster, kicks above their caps and detail
-- budgets that do not fit; Inspect frames each toy at its widest squeeze scale + 0.04, never below 1.28.
-- First person (spec 2026-10-10 §4.1, §6): Config.FirstPerson holds the spec's values (the 17th section), every spring
-- in it (the Inspect hand's rise and drop too) is at or under 3 Hz, 0 < maxHoldHeightDu <= toyLongestDu; validate
-- reports a spring above 3 Hz, a height cap above the longest side, a toys key that is not a Catalog id and an unknown
-- squeeze axis.
-- Design fidelity (spec 2026-10-11 §3, §5, §6): Config.FirstPerson holds the 3D Lab design's viewmodel numbers (the
-- view and light, the five arm parts, colours, team sleeves, outline, held toy, pop-in, squeeze, focus, shake, throw
-- extras and Dragon charge), squeezeAxis is "X" and Inspect's is "Y"; validate reports a broken arm part, outline,
-- pop-in, held pose, team sleeve or squeeze inset. Economy: pad Coin bonuses 0 / 1 / 2 / 3 (data only since Phase 3:
-- CoinsByRarity is gone), no hourly limit, G3's 43,200 squeezes an hour and the 30,000-squeeze alert (spec 2026-10-12
-- §12).
-- Big-number progression (spec 2026-10-12, Phase 1): the 9 Qa caps, 100 levels and their totals, the ranks, squishy
-- power, duel rewards, refunds and maxGripPerEvent = CP(100) × 2; negatives for G1's rising totals, G5's CP(100) event,
-- the Capsule block, SquishyPower, a Catalog power override and the refund share. Phase 3: the capsule tick (0.25 s)
-- and tap push (0.15), with their negatives.
-- Phase 6 (build plan: slow training removed): no Config.Grip.Afk (G9 went with it) and no slow-training popup values
-- in UI.Grip; the pad test's padMargin 1 and heightAbove 6 live in Config.Squeeze, which reports values above 2 and 8.
-- Phase 6 (trainers removed): no Config.Grip.Trainer (G4 and G6's wiring half went with it), no next-goal upgrade
-- price, no "trainer" Coin reason and no TrainerUpgrade rate.
--
-- How a "deliberately broken copy" is made without changing Config's API: clone the Shared folder, require one
-- section module of the clone and change it, then require the clone's Config. Its init receives the changed
-- section (require caches per ModuleScript), so validate() sees the broken value. The real Config is untouched.
-- WorldLayout is frozen on load, so G8 gets an unfrozen deep copy through Config.validate({ WorldLayout = copy }).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- The sections listed in DESIGN §2.2.
local SECTIONS = {
	"Economy",
	"Squeeze",
	"Combat",
	"Duel",
	"Abilities",
	"Data",
	"Net",
	"Monetization",
	"UI",
	"Audio",
	"Onboarding",
	"Anim",
	"Inspect",
	"Vfx",
	"Debug",
	"Grip",
	"FirstPerson", -- first person (spec 2026-10-10 §4.1)
	"Knead", -- the knead screen's soft body (spec phase2-squeeze §3.11)
	"Wax", -- the knead screen's wax coat (spec phase2-squeeze §3.11)
}

local CREATOR_GROUP_ID = 706867720 -- DIJAY Studios (DESIGN §1.1, verified)

-- `require` with a runtime-chosen ModuleScript.
local dynamicRequire = require :: (ModuleScript) -> any

-- Returns the path of the first table under `value` that is not frozen, or nil when all are frozen.
local function firstUnfrozen(value: any, path: string, seen: { [any]: boolean }): string?
	if type(value) ~= "table" or seen[value] then
		return nil
	end
	seen[value] = true
	if not table.isfrozen(value) then
		return path
	end
	for key, child in value do
		local found = firstUnfrozen(child, path .. "." .. tostring(key), seen)
		if found then
			return found
		end
	end
	return nil
end

local function findModule(root: Instance, path: { string }): ModuleScript
	local node: Instance = root
	for _, name in path do
		local child = node:FindFirstChild(name)
		assert(child ~= nil, "missing " .. table.concat(path, "/"))
		node = child
	end
	assert(node:IsA("ModuleScript"), table.concat(path, "/") .. " is not a ModuleScript")
	return node
end

-- Validates a fresh copy of Config whose section `sectionName` was changed by `breakIt` before Config loaded.
local function validateBrokenCopy(shared: Instance?, sectionName: string, breakIt: (section: any) -> ()): { string }
	assert(shared ~= nil, "no Shared folder to copy")
	local copy = shared:Clone()
	local ok, result = pcall(function()
		local section = dynamicRequire(findModule(copy, { "Config", sectionName }))
		breakIt(section)
		local brokenConfig = dynamicRequire(findModule(copy, { "Config" }))
		return brokenConfig.validate()
	end)
	copy:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end

-- Like validateBrokenCopy, with several sections changed (section name -> change) before Config loads.
local function validateBrokenSections(shared: Instance?, changes: { [string]: (section: any) -> () }): { string }
	assert(shared ~= nil, "no Shared folder to copy")
	local copy = shared:Clone()
	local ok, result = pcall(function()
		for sectionName, breakIt in changes do
			breakIt(dynamicRequire(findModule(copy, { "Config", sectionName })))
		end
		return dynamicRequire(findModule(copy, { "Config" })).validate()
	end)
	copy:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end

-- Validates a fresh copy of Config whose blueprint `id` (Art/SquishyBlueprints/<id>) was changed by `breakIt` before
-- the blueprint map loaded and froze it.
local function validateBrokenBlueprint(shared: Instance?, id: string, breakIt: (blueprint: any) -> ()): { string }
	assert(shared ~= nil, "no Shared folder to copy")
	local copy = shared:Clone()
	local ok, result = pcall(function()
		breakIt(dynamicRequire(findModule(copy, { "Art", "SquishyBlueprints", id })))
		return dynamicRequire(findModule(copy, { "Config" })).validate()
	end)
	copy:Destroy()
	if not ok then
		error(result, 0)
	end
	return result
end

local function containsText(list: { string }, text: string): boolean
	for _, entry in list do
		if type(entry) == "string" and string.find(entry, text, 1, true) ~= nil then
			return true
		end
	end
	return false
end

-- True when one problem line contains every text.
local function containsAll(list: { string }, texts: { string }): boolean
	for _, entry in list do
		local all = type(entry) == "string"
		for _, text in texts do
			all = all and string.find(entry, text, 1, true) ~= nil
		end
		if all then
			return true
		end
	end
	return false
end

-- The problem lines that start with a Grip rule prefix ("G8:").
local function ruleLines(list: { string }, rule: string): { string }
	local found = {}
	for _, entry in list do
		if string.sub(entry, 1, #rule + 1) == rule .. ":" then
			table.insert(found, entry)
		end
	end
	return found
end

-- An unfrozen copy of a (frozen) data table; functions and Vector3s are shared.
local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, child in value do
		copy[key] = deepCopy(child)
	end
	return copy
end

-- The first "<x>Zeta" key of a table, in sorted order (nil when there is none).
local function firstZetaKey(tbl: any): string?
	local keys = {}
	for key in tbl do
		if type(key) == "string" and string.sub(key, -4) == "Zeta" then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	return keys[1]
end

return function(t: Context)
	local Config = t.requireShared("Config")
	local expect = t.expect

	-- validate ----------------------------------------------------------------------------------------------

	-- The shipped config has no problems (Part 1 gate, DESIGN §13.2).
	t.test("validate returns an empty list for the shipped config", function()
		local problems = Config.validate()
		expect.equal(type(problems), "table")
		if #problems > 0 then
			error(string.format("%d problem(s):\n%s", #problems, table.concat(problems, "\n")))
		end
	end)

	-- A remote without a rate entry is a cross-reference error, reported by name.
	t.test("validate reports a client -> server remote with no rate entry", function()
		local problems = validateBrokenCopy(t.Shared, "Net", function(net)
			net.Remotes.SqueezeRequest = nil
		end)
		expect.truthy(#problems > 0)
		expect.truthy(containsText(problems, "SqueezeRequest"))
	end)

	-- Every click pays (2026-10-06): the squeeze timer is gone; Config.Squeeze is a hidden anti-autoclicker cap.
	t.test("the every-click-pays values: a 12-per-second cap, a 20/s flood guard, a 0.45 s hold repeat", function()
		local squeeze, net, grip = Config.Squeeze, Config.Net, Config.Grip
		expect.equal(squeeze.bucketCapacity, 12)
		expect.near(squeeze.cycleSeconds, 1 / 12, 1e-12)
		expect.equal(squeeze.floodPerSecond, 20)
		-- Burst 60 = 5 s of the cap: a network stall's backlog of honest presses is never a violation.
		expect.deepEqual(net.Remotes.SqueezeRequest, { rate = 20, burst = 60 })
		expect.deepEqual(net.Global, { rate = 30, burst = 80 })
		expect.equal(grip.Hold.repeatSeconds, 0.45)
		expect.equal(grip.gripAlertPerHour, (3600 * 12 + 12) * grip.maxGripPerEvent)
		-- Squeeze anywhere (spec 2026-10-11 §5): no hourly limit (the shared module stays, dormant).
		expect.deepEqual(Config.Economy.SqueezeLimit, { enabled = false, perHour = 600, burst = 300, emptyCoins = 0 })
	end)

	-- Squeeze anywhere, Coins every time (spec 2026-10-11 §5; the user: "Less per squeeze, no limit", "+0/+1/+2/+3").
	-- Phase 3: CoinsByRarity is gone (own squeezes pay the squeeze value) and the pad data no longer changes that pay.
	t.test("no CoinsByRarity, pad bonuses 0 / 1 / 2 / 3, no limit, G3 43,200 squeezes, alert 30,000", function()
		local economy, grip = Config.Economy, Config.Grip
		expect.equal((economy :: any).CoinsByRarity, nil)
		local bonuses, percents = {}, {}
		for tier, pad in grip.Pads do
			bonuses[tier], percents[tier] = pad.coinBonus, pad.gripPercent
		end
		expect.deepEqual(bonuses, { 0, 1, 2, 3 })
		expect.deepEqual(percents, { 100, 150, 200, 300 }) -- the Grip multipliers stay
		expect.equal(economy.SqueezeLimit.enabled, false)
		-- Spec 2026-10-12 §12: G3 counts squeezes, 43,200 an hour at the 12-a-second cap; the alert 30,000 of them.
		expect.equal(grip.maxSqueezesPerHour, 3600 * 12)
		expect.equal(grip.squeezeAlertPerHour, 30_000)
	end)

	t.test("validate reports a squeeze alert that is not a whole number in 1..maxSqueezesPerHour", function()
		local zero = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.squeezeAlertPerHour = 0
		end)
		expect.truthy(containsText(zero, "Config.Grip.squeezeAlertPerHour"))
		local above = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.squeezeAlertPerHour = 43_201
		end)
		expect.truthy(containsText(above, "Config.Grip.squeezeAlertPerHour"))
	end)

	t.test("validate reports a hold repeat shorter than the release pop of any rarity", function()
		local short = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Hold.repeatSeconds = 0.3 -- before even the base release pop (0.39 s)
		end)
		expect.truthy(containsText(short, "Hold.repeatSeconds"))
		local uncommon = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Hold.repeatSeconds = 0.4 -- after the base pop, before Uncommon / Epic's (0.43 s)
		end)
		expect.truthy(containsText(uncommon, "Hold.repeatSeconds"))
	end)

	t.test("validate reports a flood guard below the cap and a remote bucket that does not match it", function()
		local flood = validateBrokenCopy(t.Shared, "Squeeze", function(squeeze)
			squeeze.floodPerSecond = 8 -- below the cap of 12 a second: fast clicking would be dropped
		end)
		expect.truthy(containsText(flood, "floodPerSecond"))
		local fastCycle = validateBrokenCopy(t.Shared, "Squeeze", function(squeeze)
			squeeze.cycleSeconds = 1 / 30 -- a 30-per-second cap above the 20/s flood guard
		end)
		expect.truthy(containsText(fastCycle, "floodPerSecond"))
		local rate = validateBrokenCopy(t.Shared, "Net", function(net)
			net.Remotes.SqueezeRequest.rate = 4 -- the old 1.5 s cycle's guard
		end)
		expect.truthy(containsText(rate, "SqueezeRequest.rate"))
		local burst = validateBrokenCopy(t.Shared, "Net", function(net)
			net.Remotes.SqueezeRequest.burst = 4
		end)
		expect.truthy(containsText(burst, "SqueezeRequest.burst"))
		-- 59 is under 5 s of the 12-per-second cap (60): a stall's backlog would turn into violations.
		local shortBacklog = validateBrokenCopy(t.Shared, "Net", function(net)
			net.Remotes.SqueezeRequest.burst = 59
		end)
		expect.truthy(containsText(shortBacklog, "SqueezeRequest.burst"))
		local global = validateBrokenCopy(t.Shared, "Net", function(net)
			net.Global.burst = 40 -- the old global burst cannot hold SqueezeRequest's 60
		end)
		expect.truthy(containsText(global, "Global.burst"))
		local capacity = validateBrokenCopy(t.Shared, "Squeeze", function(squeeze)
			squeeze.bucketCapacity = 0
		end)
		expect.truthy(containsText(capacity, "bucketCapacity"))
	end)

	-- validate() never errors: a missing field that later checks compare against is reported, not raised.
	t.test("validate reports a missing maxCoins instead of throwing", function()
		local problems = validateBrokenCopy(t.Shared, "Economy", function(economy)
			economy.maxCoins = nil
		end)
		expect.truthy(containsText(problems, "maxCoins"))
	end)

	-- A malformed nested entry (a squeeze phase without `c`) is reported, not raised.
	t.test("validate reports a squeeze phase without c instead of throwing", function()
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.squeeze.phases[1].c = nil
		end)
		expect.truthy(containsText(problems, "Config.Anim"))
	end)

	-- A Catalog anim.squeezeFx names a hook of Config.Anim.squeeze.squeezeFx (DESIGN §4.1, §9.6): a missing hook is a
	-- cross-reference error, reported by name.
	t.test("validate reports a catalog squeezeFx hook that Config.Anim does not define", function()
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.squeeze.squeezeFx.dragon_steam = nil
		end)
		expect.truthy(containsText(problems, "dragon_steam"))
	end)

	-- Spec 2026-10-11 §4: the third-person hold is the design's HOLD (avatar.js:111, 185) in our joint space, an
	-- override under every other override pose (the throws, the ult and the cheer win), so the holding arm never
	-- swings; the squeeze no longer moves the arms (no squeezeTwoHand pose, no armSyncFullAtC).
	t.test("the hold pose is the design HOLD, an override under the others; no squeeze arm pose is left", function()
		local poses = Config.Anim.poses
		local hold = poses.hold
		expect.equal(hold.mode, "override")
		expect.deepEqual(hold.R15, {
			RightShoulder = Vector3.new(30, 0, 6),
			RightElbow = Vector3.new(75, 0, 0),
			RightWrist = Vector3.new(0, 0, 0),
		})
		expect.deepEqual(hold.R6, { RightShoulder = Vector3.new(0, -4.4, 75.5) })
		for name, pose in poses do
			if name ~= "hold" and pose.mode == "override" then
				expect.truthy((pose.priority or 0) > (hold.priority or 0))
			end
		end
		expect.equal(poses.squeezeTwoHand, nil)
		expect.equal(Config.Anim.squeeze.armSyncFullAtC, nil)
	end)

	-- An honest client polls RequestSnapshot every snapshotRetrySeconds while loading (DESIGN §2.6); the bucket
	-- must refill at least that fast or the client is rate-limited and counted as abusive.
	t.test("the RequestSnapshot bucket covers the client's loading poll", function()
		local net = Config.Net
		expect.truthy(net.Remotes.RequestSnapshot.rate * net.Client.snapshotRetrySeconds >= 1)
		local problems = validateBrokenCopy(t.Shared, "Net", function(brokenNet)
			brokenNet.Remotes.RequestSnapshot.rate = 0.5
		end)
		expect.truthy(containsText(problems, "RequestSnapshot.rate"))
	end)

	-- Problems are human-readable strings.
	t.test("validate returns its problems as strings", function()
		local problems = validateBrokenCopy(t.Shared, "Squeeze", function(squeeze)
			squeeze.floodPerSecond = 5
		end)
		expect.truthy(#problems > 0)
		for index, problem in problems do
			if type(problem) ~= "string" or problem == "" then
				error(string.format("problem %d is not a non-empty string: %s", index, tostring(problem)))
			end
		end
	end)

	-- Duel rules (Part 4, DESIGN §5.2-§5.9) -----------------------------------------------------------------------

	-- Every ability's telegraph is visible to the opponent for at least 0.35 s: §5.9's 0.6 s lowered by the user's
	-- decision of 2026-10-11 so the design's wind-ups pass (ults.js:3-6: 0.35, 0.45, 0.6, 0.5 s).
	t.test("validate reports an ability telegraph shorter than 0.35 s and a Rush interval under 20 s", function()
		local telegraph = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
			abilities.dragon_rush.telegraphSeconds = 0.3
		end)
		expect.truthy(containsAll(telegraph, { "dragon_rush", "telegraphSeconds" }))
		local interval = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
			abilities.dragon_rush.minIntervalSeconds = 10
		end)
		expect.truthy(containsAll(interval, { "dragon_rush", "minIntervalSeconds" }))
	end)

	-- Spec phase 5: the design's four Epic ultimates with the design's numbers (ults.js:3-6).
	t.test("the four Epic ultimates carry the design's wind-ups, intervals and main numbers", function()
		local A = Config.Abilities
		local rows: { { any } } = {
			{ "flock_volley", "volley", 0.35, 35 },
			{ "sprinkle_roller", "roller", 0.45, 38 },
			{ "rain_check", "rain", 0.6, 40 },
			{ "bubble_pop", "bubble", 0.5, 36 },
		}
		for _, row in rows do
			local ability = A[row[1]]
			expect.equal(ability.kind, row[2])
			expect.equal(ability.telegraphSeconds, row[3])
			expect.equal(ability.minIntervalSeconds, row[4])
			-- Dragon Rush's meter, fill rules and root / cancel / practice rules (user decisions 2026-10-11).
			for _, field in { "chargeMax", "chargePerSecond", "chargePerHitLanded", "chargePerLifeLost" } do
				expect.equal(ability[field], A.dragon_rush[field])
			end
			for _, field in { "recoverySeconds", "refundOnCancel", "practiceCooldownSeconds", "livesCost" } do
				expect.equal(ability[field], A.dragon_rush[field])
			end
			expect.truthy(ability.cancelOnHitDuringTelegraph)
		end
		expect.equal(A.dragon_rush.kind, "lane")
		expect.equal(A.flock_volley.count, 3)
		expect.equal(A.flock_volley.fanDeg, 24)
		expect.equal(A.flock_volley.speed, 75)
		expect.equal(A.sprinkle_roller.radius * 2, 6)
		expect.equal(A.sprinkle_roller.maxLength, 60)
		expect.equal(A.sprinkle_roller.speed, 55)
		expect.equal(A.sprinkle_roller.clearHeight, 3)
		expect.equal(A.rain_check.radius, 7)
		expect.equal(A.rain_check.drops, 5)
		expect.equal(A.rain_check.dropHitRadius, 1.5)
		expect.equal(A.bubble_pop.speed, 40)
		expect.equal(A.bubble_pop.popSeconds, 1.2)
		expect.equal(A.bubble_pop.splashRadius, 6)
		expect.near(A.bubble_pop.maxLength, A.bubble_pop.speed * A.bubble_pop.popSeconds, 1e-9)
	end)

	t.test("validate reports an unknown ability kind and each kind's missing field", function()
		local unknown = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
			abilities.flock_volley.kind = "laser"
		end)
		expect.truthy(containsAll(unknown, { "flock_volley", "kind" }))
		local cases = {
			{ "flock_volley", "count" },
			{ "flock_volley", "fanDeg" },
			{ "sprinkle_roller", "clearHeight" },
			{ "rain_check", "drops" },
			{ "rain_check", "dropRadii" },
			{ "bubble_pop", "splashRadius" },
			{ "bubble_pop", "popSeconds" },
		}
		for _, case in cases do
			local problems = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
				abilities[case[1]][case[2]] = nil
			end)
			if not containsAll(problems, { case[1], case[2] }) then
				error(`{case[1]}.{case[2]} missing was not reported: {table.concat(problems, "; ")}`)
			end
		end
		-- A rain drop outside the zone is reported too.
		local outside = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
			abilities.rain_check.dropRadii = { 2, 4, 8 }
		end)
		expect.truthy(containsAll(outside, { "rain_check", "dropRadii" }))
	end)

	-- User decision 2026-10-11 (design: fp.js:576): "Ultimates are reserved for Epic and Exclusive squishies"; a volley's
	-- or a bubble's hit radius is its squishy's own throw radius.
	t.test("validate reports an ultimate on an Uncommon and a volley radius that is not the throw radius", function()
		local Catalog = t.requireShared("Catalog")
		local function fakeCatalog(change: (copy: any) -> ()): any
			return {
				list = function()
					local list = {}
					for index, def in Catalog.list() do
						local copy = deepCopy(def)
						change(copy)
						list[index] = copy
					end
					return list
				end,
				starterId = Catalog.starterId,
				get = Catalog.get,
			}
		end
		local uncommon = Config.validate({
			Catalog = fakeCatalog(function(copy: any)
				if copy.id == "chocolate" then
					copy.ultimateId = "dragon_rush"
				end
			end),
		})
		expect.truthy(containsAll(uncommon, { "Catalog.chocolate", "only Epics and Exclusives" }))
		local radius = Config.validate({
			Catalog = fakeCatalog(function(copy: any)
				if copy.id == "bird" then
					copy.throw.radius = 1.0
				end
			end),
		})
		expect.truthy(containsAll(radius, { "Catalog.bird", "flock_volley", "radius" }))
		-- The real Catalog has neither problem.
		local real = Config.validate({ Catalog = Catalog })
		expect.falsy(containsText(real, "only Epics and Exclusives"))
	end)

	-- Spec phase 5 (user decision 2026-10-11): the moves keep the 3 Hz flicker, 720°/s spin and particle limits, and the
	-- dash's pose clip uses joints the joint layer has.
	t.test(
		"validate reports a dash pose on a missing joint, a pulse above 3 Hz and a roller spin above 720°/s",
		function()
			local joint = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.dash.keys.F[2].angles.LeftHip = Vector3.new(10, 0, 0)
			end)
			expect.truthy(containsAll(joint, { "Config.Anim.dash.keys.F", "LeftHip" }))
			local fade = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.dash.holdFadeInFrames = 0
			end)
			expect.truthy(containsAll(fade, { "Config.Anim.dash.holdFadeInFrames" }))
			local pulse = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
				vfx.Ultimates.shadowPulseHz = 30 / (2 * math.pi) -- the design's own 30 rad/s
			end)
			expect.truthy(containsAll(pulse, { "Ultimates", "shadowPulseHz" }))
			local spin = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
				vfx.Ultimates.rollerSpinDegPerSecond = math.deg(22) -- the design's own 22 rad/s
			end)
			expect.truthy(containsAll(spin, { "Ultimates", "rollerSpinDegPerSecond" }))
			local puffs = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
				vfx.Dash.plantPuffs = 20
			end)
			expect.truthy(containsAll(puffs, { "Config.Vfx.Dash", "plantPuffs" }))
		end
	)

	-- Spec phase 5: the dash's numbers (Config.Duel.Rules.Dash).
	t.test("validate reports a dash rule that is not positive and a pose event outside the clip", function()
		local problems = validateBrokenCopy(t.Shared, "Duel", function(duel)
			duel.Rules.Dash.seconds = 0
		end)
		expect.truthy(containsAll(problems, { "Dash", "seconds" }))
		local frames = validateBrokenCopy(t.Shared, "Duel", function(duel)
			duel.Rules.Dash.plantFrame = 20
		end)
		expect.truthy(containsAll(frames, { "Dash", "plantFrame" }))
	end)

	-- The Rush lane sphere flies at a fixed height above the floor (§5.9: floor+0.5 .. floor+8.5).
	t.test("validate reports a Dragon Rush lane sphere that dips into the floor", function()
		local problems = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
			abilities.dragon_rush.laneHeightAboveFloor = 3
		end)
		expect.truthy(containsAll(problems, { "dragon_rush", "laneHeightAboveFloor" }))
	end)

	-- The ability's banner, chip and cancel texts exist in Strings (the *Key convention).
	t.test("validate reports a Dragon Rush Strings key that does not exist", function()
		local problems = validateBrokenCopy(t.Shared, "Abilities", function(abilities)
			abilities.dragon_rush.readyKey = "ability.dragonRush.missing"
		end)
		expect.truthy(containsText(problems, "ability.dragonRush.missing"))
	end)

	-- §5.6 #7: every windup outlasts the largest lag compensation, so releaseAt is always in the future.
	t.test("validate reports a windup band that does not exceed the lag compensation", function()
		local problems = validateBrokenCopy(t.Shared, "Combat", function(combat)
			combat.Bands.windup.min = 0.1
		end)
		expect.truthy(containsAll(problems, { "windup.min", "maxCompensationSeconds" }))
	end)

	-- Every in-band throw can reach the far end of the court (§5.8 "max range ≥ 155 studs > arena length").
	t.test("validate reports in-band throws that cannot reach the far end of the court", function()
		local problems = validateBrokenCopy(t.Shared, "Combat", function(combat)
			combat.Bands.gravity.max = 80 -- 85² / 80 ≈ 90 studs < 104
		end)
		expect.truthy(containsText(problems, "court length"))
	end)

	t.test("validate reports a movement guard probe without a size", function()
		local problems = validateBrokenCopy(t.Shared, "Combat", function(combat)
			combat.MovementGuard.geometryProbeSize = Vector3.zero
		end)
		expect.truthy(containsText(problems, "geometryProbeSize"))
	end)

	-- §5.4: a player requeued after the opponent bailed goes to the front of the queue.
	t.test("validate reports a requeue priority that does not beat a normal ticket", function()
		local problems = validateBrokenCopy(t.Shared, "Duel", function(duel)
			duel.Matchmaking.RequeuePriority = duel.Matchmaking.NormalPriority
		end)
		expect.truthy(containsText(problems, "RequeuePriority"))
	end)

	-- §5.4 Preparing: "RequestStreamAroundAsync(pad, 3) in pcall for both | both done or 3 s".
	t.test("validate reports a Preparing phase shorter than the stream wait", function()
		local problems = validateBrokenCopy(t.Shared, "Duel", function(duel)
			duel.Rules.PreparingTimeoutSeconds = 2
		end)
		expect.truthy(containsAll(problems, { "StreamAroundTimeoutSeconds", "PreparingTimeoutSeconds" }))
	end)

	t.test("validate reports an early-forfeit window as long as the match", function()
		local problems = validateBrokenCopy(t.Shared, "Duel", function(duel)
			duel.Rules.EarlyForfeitSeconds = duel.Rules.MatchSeconds
		end)
		expect.truthy(containsText(problems, "EarlyForfeitSeconds"))
	end)

	-- Every duel remote of §2.8 has a rate entry (Part 4 remotes are rate-limited from their first call).
	t.test("every Part 4 client -> server remote has a rate entry", function()
		for _, name in { "QueueJoin", "QueueLeave", "DuelForfeit", "ReportIdle", "ThrowRequest", "UltimateRequest" } do
			local entry = Config.Net.Remotes[name]
			if entry == nil then
				error("Config.Net.Remotes." .. name .. " is missing")
			end
			expect.truthy(entry.rate > 0 and entry.burst >= 1)
		end
	end)

	-- §17.9 #8 at runtime: the duel config sections hold no key or text about the lobby stat (the L0 grep checks the
	-- source; this checks the loaded tables).
	t.test("the duel config sections never mention the lobby training stat", function()
		local function scan(value: any, path: string, seen: { [any]: boolean })
			if type(value) == "string" then
				if string.find(string.lower(value), "grip", 1, true) then
					error(path .. " mentions it: " .. value)
				end
			elseif type(value) == "table" and not seen[value] then
				seen[value] = true
				for key, child in value do
					scan(key, path .. " (key)", seen)
					scan(child, path .. "." .. tostring(key), seen)
				end
			end
		end
		for _, name in { "Combat", "Duel", "Abilities" } do
			scan(Config[name], "Config." .. name, {})
		end
	end)

	-- Grip rules (DESIGN §17.9; negatives from §17.12 Part 3) ---------------------------------------------------

	-- G1 Levels: 100 totals from 0, rising, <= maxGrip. Spec 2026-10-12's totals make Lv 3 and Lv 11 cost less than the
	-- level before, so that is no longer reported (the shipped config passes).
	t.test("G1 reports totals that stop rising", function()
		local problems = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.LevelTotals[10] = grip.LevelTotals[9] -- Lv 10 would cost nothing
		end)
		expect.truthy(containsAll(problems, { "G1:", "Lv 10" }))
	end)

	t.test("G1 reports a level table of the wrong length or start", function()
		local short = validateBrokenCopy(t.Shared, "Grip", function(grip)
			table.remove(grip.LevelTotals)
		end)
		expect.truthy(containsAll(short, { "G1:", "100 levels" }))
		local start = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.LevelTotals[1] = 10
		end)
		expect.truthy(containsAll(start, { "G1:", "LevelTotals[1]" }))
		local above = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.maxGrip = 99_000_000
		end)
		expect.truthy(containsAll(above, { "G1:", "maxGrip" }))
	end)

	-- G2 Pads: Pads[1] = {1, 0, 100%}; levels rise; bonuses and percents never decrease; percents x10, <= 300.
	t.test("G2 reports a bad Foam Mats row and pads out of order", function()
		local first = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Pads[1].coinBonus = 1
		end)
		expect.truthy(containsAll(first, { "G2:", "Pads[1]" }))
		local levels = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Pads[3].level = 5 -- same level as the Jelly Pad
		end)
		expect.truthy(containsAll(levels, { "G2:", "levels must rise" }))
		local bonus = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Pads[4].coinBonus = 1 -- below the Marshmallow Pad's 2
		end)
		expect.truthy(containsAll(bonus, { "G2:", "coin bonuses" }))
	end)

	t.test("G2 reports a Grip percent that is not a multiple of 10 or above 300", function()
		local odd = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Pads[2].gripPercent = 155
		end)
		expect.truthy(containsAll(odd, { "G2:", "Pads[2].gripPercent" }))
		local high = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Pads[4].gripPercent = 310
		end)
		expect.truthy(containsAll(high, { "G2:", "Pads[4].gripPercent" }))
	end)

	-- Phase 6 (build plan): the trainers are gone, and G4 and G6's wiring half with them.
	t.test("the trainers are gone: no Trainer block, goal price, trainer Coin reason or TrainerUpgrade", function()
		expect.equal((Config.Grip :: any).Trainer, nil)
		expect.equal((Config.Grip :: any).goalUpgradeMaxCostWhileCollecting, nil)
		expect.equal(table.find(Config.Economy.CoinReasons, "trainer"), nil)
		expect.equal(Config.Net.Remotes.TrainerUpgrade, nil)
	end)

	-- G5 Caps and timers.
	t.test("G5 reports Hold.maxSeconds = 900 (not below idleReminderSeconds)", function()
		local problems = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Hold.maxSeconds = 900
		end)
		expect.truthy(containsAll(problems, { "G5:", "Hold.maxSeconds" }))
	end)

	t.test("G5 reports a per-event cap below the biggest Grip event and a fast Double Grip refill", function()
		local cap = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.maxGripPerEvent = 599
		end)
		expect.truthy(containsAll(cap, { "G5:", "maxGripPerEvent" }))
		local refill = validateBrokenCopy(t.Shared, "Grip", function(grip)
			-- Every click pays: the holding rate is 3600 / Hold.repeatSeconds (8000 an hour), no longer 3600 / 1.5.
			grip.Rested.perHour = math.ceil(3600 / grip.Hold.repeatSeconds)
		end)
		expect.truthy(containsAll(refill, { "G5:", "Rested.perHour" }))
		local queued = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Hold.queuedSeconds = 120
		end)
		expect.truthy(containsAll(queued, { "G5:", "queuedSeconds" }))
	end)

	-- G8 World (Config.Grip with WorldLayout).
	local function validateWorld(breakIt: (layout: any) -> ()): { string }
		local layout = deepCopy(t.requireShared("World/WorldLayout"))
		breakIt(layout)
		return Config.validate({ WorldLayout = layout })
	end

	t.test("G8 passes the shipped WorldLayout and an unchanged copy of it", function()
		expect.equal(#ruleLines(Config.validate(), "G8"), 0)
		local lines = ruleLines(validateWorld(function() end), "G8")
		if #lines > 0 then
			error(table.concat(lines, "\n"))
		end
	end)

	t.test("G8 reports a station without a tier", function()
		local problems = validateWorld(function(layout)
			layout.Stations[1].tier = nil
		end)
		expect.truthy(containsAll(problems, { "G8:", "squeeze_01", "GripTier nil" }))
	end)

	t.test("G8 reports two tier-4 stations", function()
		local problems = validateWorld(function(layout)
			layout.Stations[8].tier = 4 -- squeeze_08 (the Marshmallow Pad) moved to the Royal tier
		end)
		expect.truthy(containsAll(problems, { "G8:", "GripTier 4", "exactly one" }))
		expect.truthy(containsAll(problems, { "G8:", "GripTier 3", "exactly one" }))
	end)

	t.test("G8 reports a giant pad whose corner pokes out of its gate", function()
		local problems = validateWorld(function(layout)
			layout.GiantPads.jelly.gate.diameter = 10
		end)
		expect.truthy(containsAll(problems, { "G8:", "GiantPads.jelly", "inside its gate" }))
	end)

	t.test("G8 reports the old 7.4 Marshmallow collision box (its corner leaves the rounded footprint)", function()
		local problems = validateWorld(function(layout)
			layout.GiantPads.marshmallow.collision.size = Vector3.new(7.4, 1, 7.4)
		end)
		expect.truthy(containsAll(problems, { "G8:", "GiantPads.marshmallow", "pokes out" }))
	end)

	t.test("G8 reports a giant pad whose collision top is not below its rest top", function()
		local problems = validateWorld(function(layout)
			layout.GiantPads.royal.restTop = 1.0
		end)
		expect.truthy(containsAll(problems, { "G8:", "GiantPads.royal.collisionTop" }))
	end)

	t.test("G8 is skipped cleanly when WorldLayout does not exist", function()
		assert(t.Shared ~= nil, "no Shared folder to copy")
		local copy = t.Shared:Clone()
		local ok, result = pcall(function()
			local world = copy:FindFirstChild("World")
			if world then
				world:Destroy()
			end
			return dynamicRequire(findModule(copy, { "Config" })).validate()
		end)
		copy:Destroy()
		if not ok then
			error(result, 0)
		end
		expect.equal(#ruleLines(result, "G8"), 0)
		expect.falsy(containsText(result, "WorldLayout"))
	end)

	-- G10 Giant-pad animation (Config.Anim.giantPad).
	t.test("G10 reports a path B spring with zeta = 0", function()
		local broken = ""
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			local giantPad = anim.giantPad
			assert(giantPad ~= nil, "Config.Anim.giantPad is missing (DESIGN §17.10, Part 3)")
			local springs = if type(giantPad.pathB) == "table" and firstZetaKey(giantPad.pathB)
				then giantPad.pathB
				else giantPad
			local key = firstZetaKey(springs)
			assert(key ~= nil, "Config.Anim.giantPad has no spring zeta")
			springs[key] = 0
			broken = key
		end)
		expect.truthy(containsAll(problems, { "G10:", broken }))
	end)

	t.test("G10 reports waveSpeed = 30 as an unstable ripple", function()
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			assert(anim.giantPad ~= nil, "Config.Anim.giantPad is missing (DESIGN §17.10, Part 3)")
			anim.giantPad.waveSpeed = 30
		end)
		expect.truthy(containsAll(problems, { "G10:", "waveSpeed", "gridHigh" }))
	end)

	t.test("G10 reports grids above the vertex cap and too many simulated pads", function()
		local grid = validateBrokenCopy(t.Shared, "Anim", function(anim)
			assert(anim.giantPad ~= nil, "Config.Anim.giantPad is missing (DESIGN §17.10, Part 3)")
			anim.giantPad.gridHigh = 40
		end)
		expect.truthy(containsAll(grid, { "G10:", "gridHigh", "maxVertices" }))
		local simulated = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.giantPad.maxSimulated = 4
		end)
		expect.truthy(containsAll(simulated, { "G10:", "maxSimulated" }))
	end)

	t.test("the box reveal's result input guard must be between 0 and 1000 ms", function()
		expect.equal(Config.Anim.boxReveal.resultInputGuardMs, 350)
		for _, bad in { -1, 1500, 0 / 0 } do
			local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.boxReveal.resultInputGuardMs = bad
			end)
			expect.truthy(containsAll(problems, { "boxReveal.resultInputGuardMs" }))
		end
	end)

	-- Grip rules, Part 5 (DESIGN §17.9 table; negatives from §17.12 Part 5) ------------------------------------------

	t.test("the shipped config passes G3 and G6", function()
		local problems = Config.validate()
		for _, rule in { "G3", "G6" } do
			local lines = ruleLines(problems, rule)
			if #lines > 0 then
				error(table.concat(lines, "\n"))
			end
		end
	end)

	-- G3 squeeze ceiling (spec 2026-10-12 §12): the paid squeezes an hour <= maxSqueezesPerHour (43,200). The limit is
	-- off (spec 2026-10-11 §5), so every one of the 43,200 squeezes an hour at the 12-a-second cap pays.
	t.test("G3 reports a 13-a-second squeeze cap (46,800 paid squeezes an hour)", function()
		local problems = validateBrokenCopy(t.Shared, "Squeeze", function(squeeze)
			squeeze.cycleSeconds = 1 / 13
		end)
		expect.truthy(containsAll(problems, { "G3:", "46800 squeezes", "maxSqueezesPerHour" }))
	end)

	t.test("G3 reports a ceiling of 43,199 squeezes an hour", function()
		local problems = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.maxSqueezesPerHour = 43_199
		end)
		expect.truthy(containsAll(problems, { "G3:", "43200 squeezes" }))
	end)

	t.test("G3 passes the limit switched back on (600 paid squeezes an hour)", function()
		local problems = validateBrokenCopy(t.Shared, "Economy", function(economy)
			economy.SqueezeLimit.enabled = true
		end)
		expect.equal(#ruleLines(problems, "G3"), 0)
	end)

	-- Big-number progression (spec 2026-10-12, Phase 1) --------------------------------------------------------------

	t.test("the big-number values: 9 Qa caps, 100 levels, ranks, squishy power, duel rewards, refunds", function()
		local economy, grip = Config.Economy, Config.Grip
		expect.equal(economy.maxCoins, 9_000_000_000_000_000)
		expect.equal(grip.maxGrip, 9_000_000_000_000_000)
		expect.equal(grip.maxLevel, 100)
		expect.equal(#grip.LevelTotals, 100)
		-- The appendix's milestones (spec §10): Lv10 76K, Lv20 1.1M, Lv50 1.1B, Lv100 380T.
		expect.equal(grip.LevelTotals[10], 76_000)
		expect.equal(grip.LevelTotals[20], 1_100_000)
		expect.equal(grip.LevelTotals[50], 1_100_000_000)
		expect.equal(grip.LevelTotals[100], 380_000_000_000_000)
		local ranks = {}
		for _, rank in grip.Ranks do
			table.insert(ranks, `{rank.level} {rank.key}`)
		end
		expect.equal(
			table.concat(ranks, ", "),
			"1 soft, 10 firm, 20 strong, 30 iron, 40 titan, 50 master, 60 legend, 70 mythic, 80 cosmic, 90 galaxy, "
				.. "100 infinite"
		)
		expect.deepEqual(economy.SquishyPower, { Common = 1, Uncommon = 4, Epic = 16, Exclusive = 64 })
		expect.equal(economy.DuelRewards.win, 600)
		expect.equal(economy.DuelRewards.draw, 300)
		expect.equal(economy.DuelRewards.loss, 180)
		expect.deepEqual(economy.DuplicateRefund, { percent = 25, freeBoxPriceOf = "snack" })
		expect.truthy(table.find(economy.CoinReasons, "capsule") ~= nil)
		-- CP(100) × Rested.mult (spec §12); the alert holds an hour of them at the cap (checked above).
		expect.equal(grip.maxGripPerEvent, 920_525_589 * grip.Rested.mult)
		expect.equal(grip.allowBundlesWithCapsules, false)
	end)

	t.test("G5 reports a per-event cap one Grip below CP(100) × Rested.mult", function()
		local problems = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.maxGripPerEvent = 1_841_051_177
		end)
		expect.truthy(containsAll(problems, { "G5:", "maxGripPerEvent", "CP(100)" }))
	end)

	t.test("validate reports capsule tiers that do not fill maxLevel, slower tiers and falling Grip gates", function()
		local short = validateBrokenCopy(t.Shared, "Grip", function(grip)
			table.remove(grip.Capsule.Tiers)
		end)
		expect.truthy(containsAll(short, { "Config.Grip.Capsule", "must make maxLevel" }))
		local slower = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.Tiers[2].seconds = 4.5
		end)
		expect.truthy(containsAll(slower, { "intervals must fall", "Tiers[2].seconds" }))
		local gate = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.Tiers[3].gripLevel = 10
		end)
		expect.truthy(containsAll(gate, { "Grip gates must rise", "Tiers[3]" }))
		local first = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.Tiers[1].gripLevel = 1
		end)
		expect.truthy(containsText(first, "Config.Grip.Capsule.Tiers[1] must need no Grip level"))
	end)

	t.test("validate reports capsule growth of 1, unordered or paid-first slots and a price above maxCoins", function()
		local flat = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.power.growth = 1
		end)
		expect.truthy(containsText(flat, "Config.Grip.Capsule.power.growth must be > 1"))
		local slots = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.slotPrices[3] = 2_500
		end)
		expect.truthy(containsAll(slots, { "slotPrices must rise", "slotPrices[3]" }))
		local paidFirst = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.slotPrices[1] = 10
		end)
		expect.truthy(containsText(paidFirst, "Config.Grip.Capsule.slotPrices[1] must be 0"))
		-- 1,000 × 1.5^98 is far above 9 Qa.
		local steep = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.price.growth = 1.5
		end)
		expect.truthy(containsAll(steep, { "Config.Grip.Capsule", "above Config.Economy.maxCoins" }))
	end)

	-- Phase 3 (lobby spec 2026-10-11 §6): the capsule tick and the home tap push.
	t.test("capsules tick every 0.25 s and a home tap pushes 0.15 of a squeeze; validate reports bad values", function()
		expect.equal(Config.Grip.Capsule.tickSeconds, 0.25)
		expect.equal(Config.Grip.Capsule.tapPush, 0.15)
		local stopped = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.tickSeconds = 0
		end)
		expect.truthy(containsText(stopped, "Config.Grip.Capsule.tickSeconds must be a number > 0"))
		local none = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.tapPush = 0
		end)
		expect.truthy(containsText(none, "Config.Grip.Capsule.tapPush must be a number > 0"))
		local big = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Capsule.tapPush = 1.5
		end)
		expect.truthy(containsText(big, "Config.Grip.Capsule.tapPush must be at most 1 squeeze"))
	end)

	t.test("validate reports a missing or zero squishy power and a Catalog power override of 0", function()
		local missing = validateBrokenCopy(t.Shared, "Economy", function(economy)
			economy.SquishyPower.Epic = nil
		end)
		expect.truthy(containsText(missing, "Config.Economy.SquishyPower has no entry for rarity Epic"))
		local zero = validateBrokenCopy(t.Shared, "Economy", function(economy)
			economy.SquishyPower.Common = 0
		end)
		expect.truthy(containsText(zero, "Config.Economy.SquishyPower.Common must be an integer >= 1"))
		local Catalog = t.requireShared("Catalog")
		local fake = {
			list = function()
				local list = {}
				for index, def in Catalog.list() do
					local copy = deepCopy(def)
					if copy.id == "dragon" then
						copy.power = 0
					end
					list[index] = copy
				end
				return list
			end,
			starterId = Catalog.starterId,
		}
		expect.truthy(containsText(Config.validate({ Catalog = fake }), "Catalog.dragon.power must be an integer >= 1"))
	end)

	t.test("validate reports a refund of the whole box price and a free-box price from a free box", function()
		local whole = validateBrokenCopy(t.Shared, "Economy", function(economy)
			economy.DuplicateRefund.percent = 100
		end)
		expect.truthy(containsText(whole, "Config.Economy.DuplicateRefund.percent"))
		local free = validateBrokenCopy(t.Shared, "Economy", function(economy)
			economy.DuplicateRefund.freeBoxPriceOf = "treat"
		end)
		expect.truthy(containsAll(free, { "DuplicateRefund.freeBoxPriceOf", "must be a paid box" }))
	end)

	-- G6 Strings names: every rank and pad key has its grip.* text.
	t.test("G6 reports a rank key without a Strings name", function()
		local problems = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.Ranks[3].key = "mighty"
		end)
		expect.truthy(containsAll(problems, { "G6:", "grip.rank.mighty" }))
	end)

	-- Phase 6 (build plan): slow training is gone, and G9 with it. The pad a squeeze boosts on is still the one under
	-- the root, with the margins Config.Grip.Afk held, now in Config.Squeeze (with G9's limits: 2 and 8 studs).
	t.test("slow training is gone: no Config.Grip.Afk or popup values; the pad test lives in Config.Squeeze", function()
		expect.equal((Config.Grip :: any).Afk, nil)
		expect.equal((Config.UI.Grip :: any).afkPopupScale, nil)
		expect.equal((Config.UI.Grip :: any).afkPopupTransparency, nil)
		expect.equal(Config.Squeeze.padMargin, 1)
		expect.equal(Config.Squeeze.heightAbove, 6)
		expect.equal(#ruleLines(Config.validate(), "G9"), 0)
	end)

	t.test("validate reports Config.Squeeze pad margins above the limits", function()
		local margin = validateBrokenCopy(t.Shared, "Squeeze", function(squeeze)
			squeeze.padMargin = 3
			squeeze.heightAbove = 9
		end)
		expect.truthy(containsAll(margin, { "Config.Squeeze.padMargin", "studs" }))
		expect.truthy(containsAll(margin, { "Config.Squeeze.heightAbove", "studs" }))
	end)

	-- Part 5 values outside the Grip rules.
	t.test("validate reports a profile size bound at the DataStore limit and a negative timer skew", function()
		local problems = validateBrokenCopy(t.Shared, "Data", function(data)
			data.profileSizeLimitBytes = 4_194_304
			data.timestampSkewSeconds = -1
		end)
		expect.truthy(containsText(problems, "profileSizeLimitBytes"))
		expect.truthy(containsText(problems, "timestampSkewSeconds"))
	end)

	t.test("validate reports a Grip HUD column that reaches the thumbstick zone", function()
		local problems = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.Grip.leftColumnMaxFraction = 0.6
		end)
		expect.truthy(containsText(problems, "leftColumnMaxFraction"))
	end)

	-- Part 8 (§17.11 nameplate polish; Readings: DESIGN lists no details).
	t.test(
		"the Part 8 nameplate keys: a 10-stud fade, a 0.25 s check loop, the own plate hidden within 1.5 studs",
		function()
			local plate = Config.Grip.Nameplate
			expect.equal(plate.maxDistance, 60)
			expect.equal(plate.fadeStuds, 10)
			expect.equal(plate.checkSeconds, 0.25)
			expect.equal(plate.ownHideStuds, 1.5)
			expect.truthy(plate.fadeStuds > 0 and plate.fadeStuds < plate.maxDistance)
		end
	)

	t.test(
		"validate reports a nameplate fade of 0 or of the whole distance, no check period, a negative own hide",
		function()
			local zero = validateBrokenCopy(t.Shared, "Grip", function(grip)
				grip.Nameplate.fadeStuds = 0
				grip.Nameplate.checkSeconds = 0
				grip.Nameplate.ownHideStuds = -1
			end)
			expect.truthy(containsAll(zero, { "Config.Grip.Nameplate.fadeStuds", "below maxDistance" }))
			expect.truthy(containsAll(zero, { "Config.Grip.Nameplate.checkSeconds", "> 0" }))
			expect.truthy(containsAll(zero, { "Config.Grip.Nameplate.ownHideStuds", ">= 0" }))
			local whole = validateBrokenCopy(t.Shared, "Grip", function(grip)
				grip.Nameplate.fadeStuds = grip.Nameplate.maxDistance
			end)
			expect.truthy(containsText(whole, "Config.Grip.Nameplate.fadeStuds"))
			-- Missing values are problem lines, not errors; a 0-stud own hide (never hidden) is allowed.
			local missing = validateBrokenCopy(t.Shared, "Grip", function(grip)
				grip.Nameplate.fadeStuds = nil
				grip.Nameplate.checkSeconds = nil
				grip.Nameplate.ownHideStuds = nil
			end)
			expect.truthy(containsText(missing, "Config.Grip.Nameplate.fadeStuds"))
			expect.truthy(containsText(missing, "Config.Grip.Nameplate.checkSeconds"))
			expect.truthy(containsText(missing, "Config.Grip.Nameplate.ownHideStuds"))
			local never = validateBrokenCopy(t.Shared, "Grip", function(grip)
				grip.Nameplate.ownHideStuds = 0
			end)
			expect.equal(containsText(never, "Config.Grip.Nameplate"), false)
		end
	)

	t.test("validate reports a welcome-back gain larger than Double Grip can hold", function()
		local problems = validateBrokenCopy(t.Shared, "Grip", function(grip)
			grip.welcomeBackMinGain = grip.Rested.burst + 1
		end)
		expect.truthy(containsText(problems, "welcomeBackMinGain"))
	end)

	t.test("every Part 5 client -> server remote has a rate entry", function()
		for _, name in { "RequestSnapshot", "EquipSquishy", "SqueezeRequest", "SetSettings", "OnboardingStep" } do
			local entry = Config.Net.Remotes[name]
			if entry == nil then
				error("Config.Net.Remotes." .. name .. " is missing")
			end
			expect.truthy(entry.rate > 0 and entry.burst >= 1)
		end
	end)

	-- Part 7 (DESIGN §17.9 G7 / G7b, §17.12 Part 7 negatives, §6.8 QuestDefs, §11.6, PROGRESS readings) ---------------

	t.test("the Part 7 values: no cosmetic benefits, skip id, UI readings", function()
		-- Phase 6: the "trainer" Coin reason is gone, so the capsule reason sits just before "debug".
		local reasons = Config.Economy.CoinReasons
		expect.equal(table.find(reasons, "capsule"), (table.find(reasons, "debug") :: number) - 1)
		expect.deepEqual(Config.Monetization.CosmeticBenefits, {})
		expect.equal(Config.Onboarding.skipStepId, "skip")
		expect.equal(Config.UI.Boxes.stillCheckingSeconds, 10)
		expect.equal(Config.UI.Boxes.revealHoldMaxSeconds, 30)
		expect.equal(Config.UI.Shop.cardWidth, 150)
		expect.equal(Config.Grip.allowBundlesWithCapsules, false)
	end)

	t.test("every Part 7 client -> server remote has a rate entry", function()
		local names = { "BoxOpen", "AckReveal", "ShopBuy", "QuestClaim", "QuestSwap", "DailyClaim" }
		for _, name in names do
			local entry = Config.Net.Remotes[name]
			if entry == nil then
				error("Config.Net.Remotes." .. name .. " is missing")
			end
			expect.truthy(entry.rate > 0 and entry.burst >= 1)
		end
	end)

	t.test("the shipped config passes G6, G7 and G7b", function()
		local problems = Config.validate()
		for _, rule in { "G6", "G7", "G7b" } do
			local lines = ruleLines(problems, rule)
			if #lines > 0 then
				error(table.concat(lines, "\n"))
			end
		end
		local Strings = t.requireShared("Strings")
		expect.deepEqual(Config.robuxProblems(Config.Monetization, Config.Grip, Strings.resolve), {})
	end)

	-- G7 / G7b through Config.robuxProblems with fake tables (§17.12 Part 7 negatives, word for word).
	local function monetization(bundles: { any }?, passes: { any }?, benefits: { string }?): any
		return { CoinBundles = bundles or {}, GamePasses = passes or {}, CosmeticBenefits = benefits or {} }
	end
	local function bundle(fields: { [string]: any }?): any
		local b: { [string]: any } =
			{ key = "coins_handful", nameKey = "bundle.handful", productId = nil, coins = 1000, onSale = true }
		if fields ~= nil then
			for key, value in fields do
				b[key] = value
			end
		end
		return b
	end
	local function noText(_key: string): string?
		return nil
	end
	local gripOn = { enabled = true, allowBundlesWithCapsules = false }

	t.test('G7 reports a pass benefit "grip" (not a cosmetic benefit, and it names the training)', function()
		local pass = { key = "vip", nameKey = "bundle.handful", benefit = "grip" }
		local problems = Config.robuxProblems(monetization(nil, { pass }), gripOn, noText)
		expect.truthy(containsAll(problems, { "G7:", "GamePasses[1].benefit", "CosmeticBenefits" }))
		expect.truthy(containsAll(problems, { "G7:", "GamePasses[1].benefit", 'mentions "grip"' }))
		-- Listing "grip" as a cosmetic benefit does not make it allowed.
		local listed = Config.robuxProblems(monetization(nil, { pass }, { "grip" }), gripOn, noText)
		expect.truthy(containsAll(listed, { "G7:", "GamePasses[1].benefit", 'mentions "grip"' }))
	end)

	t.test("G7 reports a coin bundle with an extra rested field (through Config.validate)", function()
		local problems = validateBrokenCopy(t.Shared, "Monetization", function(section)
			section.CoinBundles[1].rested = 1200
		end)
		expect.truthy(containsAll(problems, { "G7:", "CoinBundles[1]", '"rested"' }))
	end)

	t.test("G7 reports the pass keys grip_boost, afk_boost, slow_training_boost and royal_pad_pass", function()
		local cases = {
			{ key = "grip_boost", word = '"grip"' },
			{ key = "afk_boost", word = '"afk"' },
			{ key = "slow_training_boost", word = '"train"' },
			{ key = "royal_pad_pass", word = '"pad"' },
		}
		for _, case in cases do
			local pass = { key = case.key, nameKey = "bundle.handful", benefit = "hat" }
			local problems = Config.robuxProblems(monetization(nil, { pass }, { "hat" }), gripOn, noText)
			if not containsAll(problems, { "G7:", "GamePasses[1].key", case.key, case.word }) then
				error(`pass key {case.key} was not reported: {table.concat(problems, " | ")}`)
			end
		end
		-- Lobby spec 2026-10-11 §11: capsules are training too.
		local capsule = { key = "capsule_boost", nameKey = "bundle.handful", benefit = "hat" }
		local capsuleProblems = Config.robuxProblems(monetization(nil, { capsule }, { "hat" }), gripOn, noText)
		expect.truthy(containsAll(capsuleProblems, { "G7:", "GamePasses[1].key", '"capsule"' }))
		-- A cosmetic pass with a neutral name passes.
		local hat = { key = "party_hat", nameKey = "bundle.handful", benefit = "hat" }
		expect.deepEqual(Config.robuxProblems(monetization(nil, { hat }, { "hat" }), gripOn, noText), {})
	end)

	t.test('G7 reports a nameKey whose text is "Golden Gripper" and one whose text is "Royal Cushion VIP"', function()
		local texts: { [string]: string } =
			{ ["bundle.golden"] = "Golden Gripper", ["pass.royal"] = "Royal Cushion VIP" }
		local function resolve(key: string): string?
			return texts[key]
		end
		local golden = bundle({ key = "coins_golden", nameKey = "bundle.golden" })
		local problems = Config.robuxProblems(monetization({ golden }), gripOn, resolve)
		expect.truthy(containsAll(problems, { "G7:", "CoinBundles[1].nameKey", "Golden Gripper", '"grip"' }))
		local royal = { key = "vip", nameKey = "pass.royal", benefit = "hat" }
		local passProblems = Config.robuxProblems(monetization(nil, { royal }, { "hat" }), gripOn, resolve)
		expect.truthy(containsAll(passProblems, { "G7:", "GamePasses[1].nameKey", "Royal Cushion VIP", '"cushion"' }))
	end)

	t.test("G7b reports a productId set while allowBundlesWithCapsules is false (and only then)", function()
		-- A test value only: no product id is ever configured (§6.11, M7).
		local configured = bundle({ productId = 1 })
		local problems = Config.robuxProblems(monetization({ configured }), gripOn, noText)
		expect.truthy(containsAll(problems, { "G7b:", "CoinBundles[1].productId" }))
		local allowed = { enabled = true, allowBundlesWithCapsules = true }
		expect.equal(#ruleLines(Config.robuxProblems(monetization({ configured }), allowed, noText), "G7b"), 0)
		local gripOff = { enabled = false, allowBundlesWithCapsules = false }
		expect.equal(#ruleLines(Config.robuxProblems(monetization({ configured }), gripOff, noText), "G7b"), 0)
		-- Fail closed: a Grip table without the flag counts as "bundles not allowed".
		expect.truthy(#ruleLines(Config.robuxProblems(monetization({ configured }), {}, noText), "G7b") > 0)
		-- Through Config.validate as well.
		local validated = validateBrokenCopy(t.Shared, "Monetization", function(section)
			section.CoinBundles[2].productId = 1
		end)
		expect.truthy(containsAll(validated, { "G7b:", "CoinBundles[2].productId" }))
	end)

	t.test("robuxProblems never errors on malformed input", function()
		local oddBundles: { any } = { 5, { key = 3 } }
		local oddPasses: { any } = { "y", { benefit = 7 } }
		local bad: { { any } } = {
			{ nil, nil },
			{ "x", 5 },
			{ { CoinBundles = "x", GamePasses = 5 }, nil },
			{ { CoinBundles = oddBundles, GamePasses = oddPasses, CosmeticBenefits = { 1 } }, {} },
		}
		for _, case in bad do
			local ok, problems = pcall(Config.robuxProblems, case[1], case[2], function(_key: string): string?
				error("boom")
			end)
			expect.truthy(ok)
			expect.truthy(type(problems) == "table" and #problems > 0)
		end
	end)

	-- QuestDefs (§6.8): checked through Config.validate({ QuestDefs = fake }), because QuestDefs is frozen on load.
	local function questDefs(change: (defs: { any }) -> ()): any
		local QuestDefs = t.requireShared("QuestDefs")
		local defs = {}
		for _, def in QuestDefs.list() do
			table.insert(defs, deepCopy(def))
		end
		change(defs)
		return {
			list = function()
				return defs
			end,
		}
	end
	local function questProblems(change: (defs: { any }) -> ()): { string }
		return Config.validate({ QuestDefs = questDefs(change) })
	end
	local function findDef(defs: { any }, id: string): any
		for _, def in defs do
			if def.id == id then
				return def
			end
		end
		error("no quest def " .. id)
	end

	t.test("the shipped QuestDefs pass, and an unchanged copy passes too", function()
		local problems = questProblems(function() end)
		for _, line in problems do
			if string.find(line, "QuestDefs", 1, true) then
				error(line)
			end
		end
	end)

	t.test("QuestDefs reports a textPair without its Strings one/many texts", function()
		local problems = questProblems(function(defs)
			findDef(defs, "starter_jelly").textPair = "quest.starterTask.royal"
		end)
		expect.truthy(containsAll(problems, { "QuestDefs.starter_jelly.textPair", "quest.starterTask.royal.one" }))
		expect.truthy(containsAll(problems, { "QuestDefs.starter_jelly.textPair", "quest.starterTask.royal.many" }))
	end)

	t.test("QuestDefs reports variants that are not positive integer goal/reward pairs", function()
		local problems = questProblems(function(defs)
			findDef(defs, "squeeze_any").variants[1].goal = 0
			findDef(defs, "duel_win").variants[2].reward = 12.5
			findDef(defs, "practice_hits").variants = {}
		end)
		expect.truthy(containsAll(problems, { "QuestDefs.squeeze_any.variants[1].goal" }))
		expect.truthy(containsAll(problems, { "QuestDefs.duel_win.variants[2].reward" }))
		expect.truthy(containsAll(problems, { "QuestDefs.practice_hits.variants" }))
	end)

	t.test("QuestDefs reports an unknown category or counts rule and daily templates without a practice one", function()
		local problems = questProblems(function(defs)
			findDef(defs, "practice_hits").category = "fishing"
			findDef(defs, "hits_with").counts = "afkTicks"
		end)
		expect.truthy(containsAll(problems, { "QuestDefs.practice_hits.category", '"fishing"' }))
		expect.truthy(containsAll(problems, { "QuestDefs.hits_with.counts", '"afkTicks"' }))
		expect.truthy(containsAll(problems, { "no daily template of category practice" }))
	end)

	t.test(
		"QuestDefs reports a bad starter id, a kind that does not match the id and a minTier outside 2..4",
		function()
			local problems = questProblems(function(defs)
				findDef(defs, "starter_duel").id = "starter_Duel2"
				findDef(defs, "starter_squeeze").kind = "daily"
				findDef(defs, "starter_jelly").minTier = 1
				findDef(defs, "starter_practice").minTier = 5
			end)
			expect.truthy(containsAll(problems, { "QuestDefs.starter_Duel2", "^starter_[a-z]+$" }))
			expect.truthy(containsAll(problems, { "QuestDefs.starter_squeeze.kind" }))
			expect.truthy(containsAll(problems, { "QuestDefs.starter_jelly.minTier", "2..4" }))
			expect.truthy(containsAll(problems, { "QuestDefs.starter_practice.minTier", "2..4" }))
		end
	)

	t.test("Onboarding reports a skip id that is a step id or not camelCase", function()
		local asStep = validateBrokenCopy(t.Shared, "Onboarding", function(onboarding)
			onboarding.skipStepId = "welcome"
		end)
		expect.truthy(containsAll(asStep, { "skipStepId", "must not be a Steps id" }))
		local badCase = validateBrokenCopy(t.Shared, "Onboarding", function(onboarding)
			onboarding.skipStepId = "Skip!"
		end)
		expect.truthy(containsAll(badCase, { "skipStepId", "camelCase" }))
	end)

	t.test("UI reports a non-positive box timeout or shop card width", function()
		local problems = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.Boxes.stillCheckingSeconds = 0
			ui.Boxes.revealHoldMaxSeconds = 0
			ui.Shop.cardWidth = -1
		end)
		expect.truthy(containsText(problems, "Config.UI.Boxes.stillCheckingSeconds"))
		expect.truthy(containsText(problems, "Config.UI.Boxes.revealHoldMaxSeconds"))
		expect.truthy(containsText(problems, "Config.UI.Shop.cardWidth"))
	end)

	-- Part 6 (Inspect) -----------------------------------------------------------------------------------------------

	-- The Part 6 readings other lanes code against (DESIGN silent: preview dots, drag speed filter, Collection displays).
	t.test("the Part 6 Inspect keys hold their values", function()
		local inspect = Config.Inspect
		expect.equal(inspect.Input.dragSpeedSmoothSeconds, 0.05)
		expect.equal(inspect.Input.triggerDeadzone, 0.05)
		expect.equal(inspect.Preview.maxPerSecond, 8)
		expect.equal(inspect.Preview.soundCooldownMs, 90)
		expect.equal(inspect.Preview.dotSizePx, 10)
		expect.equal(inspect.Preview.dotSpeedMinPx, 140)
		expect.equal(inspect.Preview.dotSpeedMaxPx, 260)
		expect.equal(inspect.Preview.dotLifeSeconds, 0.45)
		expect.equal(inspect.Collection.checkSeconds, 0.5)
		expect.equal(inspect.Collection.hysteresisStuds, 5)
		expect.equal(inspect.Collection.swayDeg, 15)
		expect.equal(inspect.Collection.swayPeriodSeconds, 6)
		expect.equal(inspect.Collection.spinDegPerSecond, nil) -- no full turntable (Part 6 review: faces toward -X)
		expect.equal(inspect.Collection.nameplateOffsetStuds, 0.8)
		expect.equal(inspect.Collection.nameplateSizeStuds, Vector2.new(4.5, 1.4))
		-- The dot count stays in Config.Anim; the scale and radius stay in WorldLayout (not duplicated here).
		expect.equal(Config.Anim.squeeze.inspectDotsMin, 6)
		expect.equal(Config.Anim.squeeze.inspectDotsMax, 10)
		expect.equal(inspect.Collection.squishyScale, nil)
		expect.equal(inspect.Collection.buildStuds, nil)
	end)

	t.test("Inspect reports bad preview dots, drag filter and Collection display values", function()
		local problems = validateBrokenCopy(t.Shared, "Inspect", function(inspect)
			inspect.Input.dragSpeedSmoothSeconds = 0
			inspect.Input.triggerDeadzone = 1
			inspect.Preview.dotSizePx = 0
			inspect.Preview.dotLifeSeconds = -1
			inspect.Preview.dotSpeedMinPx = 300 -- above dotSpeedMaxPx (260)
			inspect.Collection.checkSeconds = 0
			inspect.Collection.hysteresisStuds = -1
			inspect.Collection.swayDeg = -15
			inspect.Collection.swayPeriodSeconds = 0
			inspect.Collection.nameplateOffsetStuds = 0
			inspect.Collection.nameplateSizeStuds = Vector2.new(0, 1.4)
		end)
		expect.truthy(containsText(problems, "Config.Inspect.Input.dragSpeedSmoothSeconds"))
		expect.truthy(containsAll(problems, { "Config.Inspect.Input.triggerDeadzone", "[0, 1)" }))
		expect.truthy(containsText(problems, "Config.Inspect.Preview.dotSizePx"))
		expect.truthy(containsText(problems, "Config.Inspect.Preview.dotLifeSeconds"))
		expect.truthy(containsAll(problems, { "Config.Inspect.Preview.dotSpeedMinPx", "<= dotSpeedMaxPx" }))
		expect.truthy(containsText(problems, "Config.Inspect.Collection.checkSeconds"))
		expect.truthy(containsAll(problems, { "Config.Inspect.Collection.hysteresisStuds", ">= 0" }))
		expect.truthy(containsAll(problems, { "Config.Inspect.Collection.swayDeg", ">= 0" }))
		expect.truthy(containsAll(problems, { "Config.Inspect.Collection.swayPeriodSeconds", "> 0" }))
		expect.truthy(containsText(problems, "Config.Inspect.Collection.nameplateOffsetStuds"))
		expect.truthy(containsText(problems, "Config.Inspect.Collection.nameplateSizeStuds"))
		-- A missing value or a nameplate size that is not a Vector2 is a problem line, not an error.
		local missing = validateBrokenCopy(t.Shared, "Inspect", function(inspect)
			inspect.Preview.dotSpeedMaxPx = nil
			inspect.Collection.nameplateSizeStuds = 4.5
		end)
		expect.truthy(containsText(missing, "Config.Inspect.Preview.dotSpeedMaxPx"))
		expect.truthy(containsText(missing, "Config.Inspect.Collection.nameplateSizeStuds"))
		-- Zero sway and zero margin are allowed (a still display, an exact edge).
		local still = validateBrokenCopy(t.Shared, "Inspect", function(inspect)
			inspect.Collection.swayDeg = 0
			inspect.Collection.hysteresisStuds = 0
		end)
		expect.equal(containsText(still, "Config.Inspect.Collection"), false)
	end)

	-- First person (spec 2026-10-10 §4.1, §6) -------------------------------------------------------------------

	t.test("Config.FirstPerson holds the spec's values", function()
		local fp = Config.FirstPerson
		expect.equal(fp.defaultOn, true)
		expect.equal(fp.gui.displayOrder, -1)
		expect.equal(fp.gui.insets, Enum.ScreenInsets.None)
		expect.equal(fp.padGui.displayOrder, 6)
		expect.equal(fp.padGui.insets, Enum.ScreenInsets.CoreUISafeInsets)
		expect.equal(fp.touchGuiFallbackOrder, 7)
		expect.equal(fp.practiceExitDelaySeconds, 0.3)
		expect.equal(fp.squeezeAxis, "X") -- spec 2026-10-11 §3.4: the two palms press in from the sides
		expect.equal(fp.fovDeg, 70)
		expect.equal(fp.overlayStudsPerDu, 4)
		expect.equal(fp.toyLongestDu, 0.19)
		expect.equal(fp.rest, Vector3.new(0.16, -0.23, -0.46))
		expect.equal(fp.shoulder, Vector3.new(0.5, -0.52, -0.04))
		expect.equal(fp.equipFrom, Vector3.new(0, -0.42, -0.44))
		expect.deepEqual(fp.springs, {
			hand = { 520, 40 },
			roll = { 300, 30 },
			toyPos = { 420, 36 },
			toyRot = { 260, 30 },
			toyScale = { 500, 30 }, -- spec 2026-10-11 §3.3 (fp.js:94)
			kick = { 150, 15 },
			focus = { 140, 24 }, -- spec 2026-10-11 §3.4 (fp.js:78)
			fov = { 170, 17 }, -- spec 2026-10-11 §3.4 (fp.js:49)
		})
		-- Spec 2026-10-11 §2 and §6: step 2's inventions and the Inspect hand are gone.
		for _, key in
			{
				"maxHoldHeightDu",
				"hold",
				"ultLift",
				"ultPush",
				"ultPushMs",
				"ultBackMs",
				"hand",
				"cup",
				"free",
				"modeBlendMs",
				"sway",
				"bob",
				"reticleClearPx",
				"inspect",
				"toys",
			}
		do
			expect.equal((fp :: any)[key], nil)
		end
		expect.equal(fp.idle.x, 0.002)
		expect.near(fp.idle.xHz, 0.9 / (2 * math.pi), 1e-12)
		expect.equal(fp.idle.y, 0.003)
		expect.near(fp.idle.yHz, 1.7 / (2 * math.pi), 1e-12)
		expect.deepEqual({ fp.idle.breath, fp.idle.breathRate }, { 0.004, 2.2 })
		expect.deepEqual(fp.kick, { release = -0.8 })
		expect.equal(fp.resultHoldSeconds, 0.4)
		expect.equal(fp.countdownPitchDeg, -3)
		expect.deepEqual(fp.nearFade, { from = 2.5, to = 4.5 })
		expect.deepEqual(fp.rushFadeIn, { from = 3, to = 8 })
		expect.equal(fp.invulnTransparency, 0.4)
		expect.equal(fp.ownRingScale, 0.5)
		expect.equal(fp.victimImpactScale, 0.25)
		-- The throw strike reads Config.Anim.throw.releaseSnapMs; there is no copy here.
		expect.equal(fp.strikeMs, nil)
		expect.equal(Config.Anim.throw.releaseSnapMs, 70)
	end)

	t.test("every first-person spring and the idle stay at or under 3 Hz", function()
		local fp = Config.FirstPerson
		local function hz(spring: { number }): number
			local omega = math.sqrt(spring[1])
			local zeta = spring[2] / (2 * omega)
			return omega * math.sqrt(math.max(0, 1 - zeta * zeta)) / (2 * math.pi)
		end
		local wanted = {
			hand = 1.74,
			roll = 1.38,
			toyPos = 1.56,
			toyRot = 0.94,
			toyScale = 2.64,
			kick = 1.54,
			focus = 0, -- overdamped (ζ 1.01)
			fov = 1.57,
		}
		for name, spring in fp.springs do
			expect.near(hz(spring), wanted[name], 0.01)
			expect.truthy(hz(spring) <= 3)
		end
		expect.truthy(fp.idle.xHz <= 3 and fp.idle.yHz <= 3 and fp.idle.breathRate / (2 * math.pi) <= 3)
	end)

	t.test("validate reports a first-person spring above 3 Hz and an unknown axis", function()
		local problems = validateBrokenCopy(t.Shared, "FirstPerson", function(fp)
			fp.springs.kick = { 1000, 1 }
			fp.squeezeAxis = "W"
		end)
		expect.truthy(containsText(problems, "Config.FirstPerson.springs.kick"))
		expect.truthy(containsText(problems, "Config.FirstPerson.squeezeAxis"))
	end)

	-- Design fidelity (spec 2026-10-11 §3): every value is the 3D Lab design's (sd/fp.js unless the Config comment says).
	t.test("Config.FirstPerson holds the 3D Lab design's viewmodel numbers (spec 2026-10-11 §3)", function()
		local fp = Config.FirstPerson
		-- §3.1 view, light, idle and kick (fp.js:28, 32-33, 49, 660)
		expect.equal(fp.fovDeg, 70)
		local light = fp.light
		expect.deepEqual(
			{ light.sky:ToHex():upper(), light.ground:ToHex():upper(), light.key:ToHex():upper() },
			{ "FFFFFF", "B8C9A8", "FFF3DC" }
		)
		expect.deepEqual({ light.hemisphere, light.keyIntensity }, { 1.1, 1.9 })
		expect.equal(light.keyFrom, Vector3.new(-0.4, 1, 0.6))
		expect.deepEqual({ fp.idle.x, fp.idle.y, fp.idle.kickY, fp.idle.kickPitch }, { 0.002, 0.003, 0.01, 0.02 })
		expect.near(fp.idle.xHz * 2 * math.pi, 0.9, 1e-12)
		expect.near(fp.idle.yHz * 2 * math.pi, 1.7, 1e-12)
		expect.deepEqual(fp.springs.kick, { 150, 15 })
		expect.equal(fp.kick.release, -0.8)
		-- §3.2 two arms of five superellipsoid parts (fp.js:65-73, kit.js:48)
		expect.deepEqual(fp.arm.parts, {
			{
				name = "hand",
				size = Vector3.new(0.1, 0.094, 0.112),
				exponent = 7,
				colour = "skin",
				pos = Vector3.zero,
				rot = Vector3.zero,
			},
			{
				name = "thumb",
				size = Vector3.new(0.036, 0.04, 0.062),
				exponent = 5,
				colour = "skin",
				pos = Vector3.new(-0.047, 0.026, -0.02), -- the right arm's; X × side
				rot = Vector3.new(0, 0.35, 0), -- Y × side
			},
			{
				name = "forearm",
				size = Vector3.new(0.09, 0.086, 0.3),
				exponent = 7,
				colour = "skin",
				pos = Vector3.new(0, 0, 0.2),
				rot = Vector3.zero,
			},
			{
				name = "cuff",
				size = Vector3.new(0.117, 0.114, 0.036),
				exponent = 8,
				colour = "cuff",
				pos = Vector3.new(0, 0, 0.35),
				rot = Vector3.zero,
			},
			{
				name = "sleeve",
				size = Vector3.new(0.114, 0.11, 0.42),
				exponent = 7,
				colour = "sleeve",
				pos = Vector3.new(0, 0, 0.57),
				rot = Vector3.zero,
			},
		})
		expect.deepEqual(fp.arm.segments, { 28, 20 })
		expect.equal(fp.arm.startPos, Vector3.new(0.16, -0.25, -0.46))
		expect.equal(fp.arm.roll, 0.4)
		expect.equal(fp.shoulder, Vector3.new(0.5, -0.52, -0.04))
		expect.deepEqual({ fp.springs.hand, fp.springs.roll }, { { 520, 40 }, { 300, 30 } })
		expect.deepEqual(
			{ fp.colours.skin:ToHex():upper(), fp.colours.cuff:ToHex():upper(), fp.colours.sleeve:ToHex():upper() },
			{ "F5CDA4", "FFF8EE", "5FD3AE" }
		)
		-- Side A is Strawberry and side B Mint (DuelFormat.sideColors); HANDOFF.md:83.
		expect.deepEqual({ fp.teamSleeves.A:ToHex():upper(), fp.teamSleeves.B:ToHex():upper() }, { "F2687F", "5FD3AE" })
		local outline = fp.outline
		expect.equal(outline.colour:ToHex():upper(), "1B1220")
		expect.deepEqual({ outline.px, outline.refHeightPx, outline.refDepthDu }, { 3, 1080, 0.46 })
		-- About 3 px at 1920 × 1080 at the hold depth is a hull about 0.0018 du thick (spec §3.2).
		local thickness = outline.px * 2 * outline.refDepthDu * math.tan(math.rad(fp.fovDeg) / 2) / outline.refHeightPx
		expect.near(thickness, 0.0018, 0.00005)
		-- §3.3 hold, rest, pop-in (fp.js:14, 77, 94, 99, 103, 393-396, 403)
		expect.equal(fp.toyLongestDu, 0.19)
		expect.deepEqual(fp.held, {
			pos = Vector3.new(0, -0.13, -0.5),
			rot = Vector3.new(0, 0.25, 0),
			sideGap = 0.05,
			sideY = -0.035,
			sideZ = 0.035,
		})
		expect.deepEqual({ fp.idle.breath, fp.idle.breathRate }, { 0.004, 2.2 })
		expect.deepEqual(
			{ fp.springs.toyPos, fp.springs.toyRot, fp.springs.toyScale },
			{ { 420, 36 }, { 260, 30 }, { 500, 30 } }
		)
		expect.equal(fp.rest, Vector3.new(0.16, -0.23, -0.46))
		expect.equal(fp.equipFrom, Vector3.new(0, -0.42, -0.44))
		expect.deepEqual(fp.equip, { seconds = 0.38, backOutC = 1.9, minScale = 0.0001 })
		-- §3.4 the two-palm squeeze, focus and shake (fp.js:49, 78, 399, 413-416, 652-656)
		expect.deepEqual(fp.squeeze, {
			inset = 0.94,
			y = -0.02,
			z = 0.03,
			rollPress = 0.3,
			tremorAfterSeconds = 0.3,
			tremor = 0.0008,
			tremorRateL = 53,
			tremorRateR = 49,
			toyTremorRate = 47,
			toyTremorShare = 0.6,
			shake = 0.025,
		})
		expect.deepEqual(fp.focus, {
			pos = Vector3.new(0, -0.105, -0.44),
			rot = Vector3.new(0.1, 0, 0),
			lingerSeconds = 1.1,
			worldFovTarget = -55,
			worldFovPerUnit = 0.1,
		})
		expect.near(fp.focus.worldFovTarget * fp.focus.worldFovPerUnit, -5.5, 1e-9) -- 70° -> 64.5°
		expect.deepEqual({ fp.springs.focus, fp.springs.fov }, { { 140, 24 }, { 170, 17 } })
		expect.deepEqual(fp.shake, { decayPerSecond = 1.4, radPerShakeSq = 0.03 })
		-- §3.5 throw extras (fp.js:433-437)
		expect.deepEqual(fp.throwFx, {
			rollCocked = 0.5,
			rollL = 0.3,
			fovKick = 80,
			shake = 0.18,
			shoveJitter = 0.006,
			shoveShake = 0.12,
			shoveUntil = 0.4,
			slingShake = 0.06,
			slingFrom = 0.1,
			slingUntil = 0.45,
			dragonRoarShake = 0.25, -- the Dragon's roar at its throw's start (fp.js:181, 305)
		})
		-- §3.6 Dragon Rush's charge (fp.js:453-459, 466) and its release (fp.js:331)
		local ult = fp.ult
		expect.equal(ult.pos, Vector3.new(0, -0.06, -0.47))
		expect.equal(ult.glowColour:ToHex():upper(), "FF9A4D") -- Dragon's
		expect.deepEqual({
			ult.pitch,
			ult.wobble,
			ult.wobbleRate,
			ult.squashY,
			ult.jitter,
			ult.glowRadius,
			ult.glowPulse,
			ult.glowPulseRate,
			ult.glowOpacity,
			ult.glowFadeRate,
			ult.shake,
			ult.fovPullPerSecond,
			ult.releaseFovKick,
			ult.releaseKick,
			ult.releaseShake,
		}, { -0.15, 0.08, 40, 0.06, 0.004, 0.13, 0.02, 30, 0.35, 8, 0.12, 36, 90, -1.2, 0.3 })
		-- §6: Inspect squashes every toy on Y (toys.js:455).
		expect.equal(Config.Inspect.Preview.squeezeAxis, "Y")
	end)

	t.test("validate reports a broken design arm, outline, pop-in, held pose, team sleeve or squeeze inset", function()
		local problems = validateBrokenCopy(t.Shared, "FirstPerson", function(fp)
			fp.arm.parts[2].size = Vector3.new(0.036, 0, 0.062) -- a flat thumb
			fp.arm.parts[3].colour = "plaid" -- not a colours key
			fp.arm.parts[4].exponent = 0
			fp.arm.parts[5].name = "hand" -- a second hand and no sleeve
			fp.outline.px = 0
			fp.equip.seconds = 0
			fp.held.pos = 3
			fp.teamSleeves.B = "#5FD3AE" -- a string, not a Color3
			fp.squeeze.inset = 1.5
			fp.throwFx.dragonRoarShake = -0.25
			fp.ult.releaseShake = -0.3
			fp.ult.releaseKick = "down"
		end)
		expect.truthy(containsText(problems, "Config.FirstPerson.throwFx.dragonRoarShake"))
		expect.truthy(containsText(problems, "Config.FirstPerson.ult.releaseShake"))
		expect.truthy(containsText(problems, "Config.FirstPerson.ult.releaseKick"))
		expect.truthy(containsText(problems, "Config.FirstPerson.arm.parts[2].size"))
		expect.truthy(containsAll(problems, { "Config.FirstPerson.arm.parts[3].colour", "plaid" }))
		expect.truthy(containsText(problems, "Config.FirstPerson.arm.parts[4].exponent"))
		expect.truthy(containsAll(problems, { "Config.FirstPerson.arm.parts", "sleeve" }))
		expect.truthy(containsAll(problems, { "Config.FirstPerson.arm.parts[5]", "hand" }))
		expect.truthy(containsText(problems, "Config.FirstPerson.outline.px"))
		expect.truthy(containsText(problems, "Config.FirstPerson.equip.seconds"))
		expect.truthy(containsText(problems, "Config.FirstPerson.held.pos"))
		expect.truthy(containsText(problems, "Config.FirstPerson.teamSleeves.B"))
		expect.truthy(containsText(problems, "Config.FirstPerson.squeeze.inset"))
		local axis = validateBrokenCopy(t.Shared, "Inspect", function(inspect)
			inspect.Preview.squeezeAxis = "W"
		end)
		expect.truthy(containsText(axis, "Config.Inspect.Preview.squeezeAxis"))
	end)

	t.test("FirstPerson.ownArms (the player's own arms): the limits; validate reports a broken copy", function()
		local own = Config.FirstPerson.ownArms
		expect.equal(own.enabled, true)
		expect.near(own.handWidthDu, Config.FirstPerson.arm.parts[1].size.X, 1e-6) -- the design hand's width (fp.js:67)
		expect.equal(own.reachDu, 0.45)
		expect.equal(own.maxStretch, 5)
		expect.equal(own.palmRoll, 0)
		expect.equal(own.recheckSeconds, 1)
		local problems = validateBrokenCopy(t.Shared, "FirstPerson", function(fp)
			fp.ownArms.enabled = "yes"
			fp.ownArms.reachDu = 0
			fp.ownArms.maxStretch = 0.5
			fp.ownArms.maxTransparency = 2
			fp.ownArms.palmRoll = "left"
		end)
		for _, key in { "enabled", "reachDu", "maxStretch", "maxTransparency", "palmRoll" } do
			expect.truthy(containsText(problems, "Config.FirstPerson.ownArms." .. key))
		end
	end)

	-- Squeeze feel (spec phase2-squeeze §3.11) ----------------------------------------------------------------

	t.test("Knead and Wax hold the design's numbers (squish.js:13-48, 173-174, 392, 425-457)", function()
		local knead, wax = Config.Knead, Config.Wax
		-- rise, fast, k, c, beta, gamma, smear, pull, pullR, neck, plastic, lump (squish.js:29-32)
		local fields =
			{ "rise", "fast", "k", "c", "beta", "gamma", "smear", "pull", "pullR", "neck", "plastic", "lump" }
		local rows: { [string]: { number } } = {
			foam = { 1.9, 0.12, 300, 20, 0.7, 2, 0.62, 0.36, 0.17, 0.6, 0.08, 0.32 },
			mochi = { 2.7, 0.05, 190, 11, 1, 2.3, 0.95, 0.62, 0.2, 0.85, 0.22, 0.18 },
			jelly = { 0.4, 0.8, 520, 7, 1.05, 2.7, 0.45, 0.3, 0.17, 0.45, 0, 0.08 },
			plush = { 1.1, 0.32, 320, 22, 0.7, 1.8, 0.42, 0.3, 0.19, 0.5, 0.06, 0.28 },
		}
		for feel, row in rows do
			for index, field in fields do
				expect.equal(knead.feels[feel][field], row[index])
			end
		end
		-- cell, th, wear, gloss (squish.js:41-47)
		local coats: { [string]: { number } } = {
			foam = { 0.075, 1.45, 0.05, 0.6 },
			mochi = { 0.06, 2.6, 0.045, 0.9 },
			jelly = { 0.095, 2.8, 0.065, 1 },
			plush = { 0.07, 2.4, 0.06, 0.35 },
		}
		for feel, row in coats do
			expect.deepEqual(wax.coats[feel], { cell = row[1], th = row[2], wear = row[3], gloss = row[4] })
		end
		-- Every rig feel (the blueprints' motion.feel) has a knead row and a coat.
		for feel in Config.Anim.rig.feels do
			expect.truthy(knead.feels[feel] ~= nil and wax.coats[feel] ~= nil)
		end
		expect.equal(knead.defaultFeel, "foam")
		expect.equal(knead.brushSlots, 4)
		-- User 2026-10-12: deeper finger dents (design: depthOfRadius 0.95, depthOfMinDim 0.42, squish.js:173-174).
		expect.deepEqual(knead.finger, { radius = 0.15, depthOfRadius = 1.5, depthOfMinDim = 0.55, falloff = 1.4 })
		expect.deepEqual(
			knead.palm,
			{ radius = 0.5, falloff = 0.55, depthOfX = 0.3, depthOfSqueeze = 0.55, betaShare = 0.35, power = 1.5 }
		)
		expect.deepEqual(
			knead.thumb,
			{ radius = 0.11, falloff = 1.35, depthOfRadius = 0.9, depthOfMinDim = 0.3, betaShare = 0.6 }
		)
		local crunch = knead.crunch
		expect.deepEqual(
			{ crunch.period, crunch.low, crunch.pressEnd, crunch.holdEnd, crunch.releaseDrop, crunch.follow },
			{ 0.56, 0.42, 0.5, 0.7, 0.58, 22 }
		)
		expect.deepEqual(
			{ crunch.gap, crunch.slide, crunch.height, crunch.spanX, crunch.spanY },
			{ 0.48, 0.2, 0.12, 0.36, 0.32 }
		)
		expect.equal(knead.memory.stampSpacing, 0.28)
		expect.equal(knead.memory.capOfRadius, 1.7) -- user 2026-10-12: deeper dents (design: 1.1, squish.js:174)
		expect.equal(knead.pull.slip, 1.75)
		expect.equal(knead.sleepSeconds, 0.12)
		expect.equal(knead.sounds.pan, 0.55) -- fp.js:103
		expect.deepEqual(
			wax.cells,
			{ spacing = 0.085, maxCells = 480, thSpread = 0.35, neighbourRadius = 2, footprintRadius = 1.7 }
		)
		expect.deepEqual(wax.stress, { relax = 1.4, bend = 1.3, worn = 0.3 })
		expect.equal(wax.cracks.sounding, 6)
		expect.equal(wax.cracks.damage, 0.14)
		expect.equal(wax.cracks.cascade, 0.07)
		expect.truthy(wax.thScale > 0)
	end)

	t.test("validate keeps jelly's 3.59 Hz knead spring as the exception; it reports broken Knead / Wax", function()
		-- The shipped Knead and Wax have no problem, jelly's k 520 / c 7 (3.59 Hz) included.
		for _, line in Config.validate() do
			expect.falsy(string.find(line, "Config.Knead", 1, true) or string.find(line, "Config.Wax", 1, true))
		end
		local problems = validateBrokenSections(t.Shared, {
			Knead = function(knead)
				knead.feels.foam.k = 2000 -- 7.1 Hz
				knead.feels.mochi.fast = 1.5
				knead.feels.jelly.k = 900 -- the exception: never checked against 3 Hz
				knead.depth.spring = { 6500, 5 } -- 12.8 Hz
				knead.crunch.period = 0.2 -- 5 presses a second
				knead.shell.lowVertices = 3000 -- above highVertices
				knead.sounds.pan = 2
			end,
			Wax = function(wax)
				wax.enabled = "yes" -- user 2026-10-12: the switch is a boolean
				wax.coats.plush.th = 0
				wax.thScale = -1
				wax.cells.maxCells = 0.5
				wax.cracks.sounding = 0
				wax.lines.revealHigh = 0.01 -- below revealLow
			end,
		})
		expect.truthy(containsAll(problems, { "Config.Knead.feels.foam", "Hz" }))
		expect.truthy(containsText(problems, "Config.Knead.feels.mochi.fast"))
		expect.falsy(containsText(problems, "Config.Knead.feels.jelly"))
		expect.truthy(containsAll(problems, { "Config.Knead.depth.spring", "Hz" }))
		expect.truthy(containsText(problems, "Config.Knead.crunch.period"))
		expect.truthy(containsText(problems, "Config.Knead.shell.lowVertices"))
		expect.truthy(containsText(problems, "Config.Knead.sounds.pan"))
		expect.truthy(containsText(problems, "Config.Wax.enabled"))
		expect.truthy(containsText(problems, "Config.Wax.coats.plush.th"))
		expect.truthy(containsText(problems, "Config.Wax.thScale"))
		expect.truthy(containsText(problems, "Config.Wax.cells.maxCells"))
		expect.truthy(containsText(problems, "Config.Wax.cracks.sounding"))
		expect.truthy(containsText(problems, "Config.Wax.lines.revealLow"))
		expect.falsy(containsText(problems, "check crashed"))
	end)

	-- Sections and freezing ---------------------------------------------------------------------------------

	-- Every section named in DESIGN §2.2 is merged into Config.
	t.test("every section from DESIGN is present", function()
		for _, name in SECTIONS do
			if type(Config[name]) ~= "table" then
				error("Config." .. name .. " is missing")
			end
		end
	end)

	-- Deep freeze: no table anywhere inside a section can be changed at runtime.
	t.test("every section is frozen all the way down", function()
		for _, name in SECTIONS do
			local unfrozen = firstUnfrozen(Config[name], "Config." .. name, {})
			if unfrozen then
				error(unfrozen .. " is not frozen")
			end
		end
	end)

	-- Writing to a frozen section raises and leaves the value unchanged.
	t.test("writing to a section raises an error", function()
		local before = Config.Squeeze.cycleSeconds
		expect.throws(function()
			Config.Squeeze.cycleSeconds = 0.1
		end)
		expect.equal(Config.Squeeze.cycleSeconds, before)
	end)

	-- Feel pass data step (DESIGN §18.8, §18.10 L1): every added or changed key holds its DESIGN value, so the other
	-- lanes can code against it. The §18.9 validators and their planted bad values come with the rest of lane L1.
	t.test("the feel pass keys of §18.8 hold their DESIGN values", function()
		local vfx, anim, ui, audio = Config.Vfx, Config.Anim, Config.UI, Config.Audio
		-- Config.Vfx
		expect.equal(vfx.Effects.squeezePuffs, 18)
		expect.equal(vfx.Effects.impactRings, 2)
		expect.equal(vfx.Effects.eliminationConfettiParts, 10)
		expect.deepEqual(vfx.Hit.geometryPuffs, { accent = 4, white = 4 })
		expect.equal(vfx.Hit.minorPuffs, 6)
		expect.equal(vfx.Hit.hitTextPopFrom, 1.3)
		expect.equal(vfx.Hit.hitTextPopMs, 200)
		expect.equal(vfx.Hit.hitTextTiltDeg, 6)
		expect.deepEqual(vfx.Splat, {
			diameterPerRadius = 2.2,
			thickness = 0.05,
			oval = 0.86,
			growMs = 70,
			overshoot = 1.12,
			settleMs = 90,
			droplets = 4,
			dropletDelayMs = 40,
			dropletGrowMs = 80,
			dropletSizeMin = 0.16,
			dropletSizeMax = 0.30,
			dropletDistMin = 0.55,
			dropletDistMax = 0.85,
			holdSeconds = 1.6,
			fadeSeconds = 0.9,
			fadeScaleTo = 0.9,
			transparency = 0.1,
			lift = 0.03,
			layerStep = 0.003,
			layers = 12,
			whiten = 0.25,
			redGuardWhiten = 0.6,
			redHueDeg = 15,
			redMinSaturation = 0.45,
			wallNormalMaxY = 0.35,
			dripStuds = 0.5,
			dripFromSeconds = 0.3,
			dripStretch = 1.4,
			maxLive = 12,
			evictFadeSeconds = 0.25,
			cullStuds = 120,
			othersCullStuds = 60,
			probeStuds = 1.0,
			minVisibleTransparency = 0.5,
			curvedMaxDiameter = 1.6,
		})
		expect.deepEqual(
			vfx.HitStop,
			{ playerHit = 0.06, elimination = 0.10, practiceTarget = 0.04, maxPerWindow = 0.12, windowSeconds = 0.5 }
		)
		expect.deepEqual(vfx.Punch, {
			maxFovDeg = 4,
			hitDealt = { fovDeg = -2.5, attackMs = 50, releaseMs = 200 },
			elimDealt = { fovDeg = -3.5, attackMs = 60, releaseMs = 260 },
			practiceHit = { fovDeg = -1.2, attackMs = 50, releaseMs = 180 },
		})
		expect.deepEqual(vfx.ImpactFlash, { fillFrom = 0.5, ms = 120 })
		expect.deepEqual(vfx.HeldBoing, { impulse = 0.10, omega = 18, zeta = 0.30, ms = 350 })
		expect.deepEqual(vfx.ThrowRing, { toStuds = 1.6, seconds = 0.18, transparencyFrom = 0.5 })
		expect.deepEqual(vfx.Confetti, {
			parts = 10,
			size = Vector3.new(0.3, 0.05, 0.45),
			upMin = 10,
			upMax = 16,
			outMin = 4,
			outMax = 8,
			gravity = 35,
			dragPerSecond = 1.2,
			spinMinDeg = 360,
			spinMaxDeg = 900,
			lifetime = 1.0,
			fadeSeconds = 0.35,
			popRingStuds = 3,
			popRingSeconds = 0.25,
		})
		expect.deepEqual(vfx.MatPulse, {
			towardPulseColor = 0.55,
			upMs = 40,
			downMs = 110,
			ringToStuds = 5,
			ringSeconds = 0.35,
			ringTransparencyFrom = 0.45,
		})
		expect.deepEqual(vfx.CoinPopup, {
			startStuds = 1.2,
			widthPx = 120,
			heightPx = 36,
			iconPx = 22,
			popFrom = 0.6,
			popMs = 140,
			fadeFromSeconds = 0.4,
		})
		expect.deepEqual(vfx.Ambient, {
			lollipopDegPerSecond = 10,
			giftSpinDegPerSecond = 18,
			giftBobStuds = 0.12,
			giftBobPeriod = 3.2,
			counterBreatheAmp = 0.02,
			counterBreathePeriod = 3.6,
			statueBreatheAmp = 0.012,
			statueBreathePeriod = 4.2,
			cullStuds = 120,
		})
		expect.equal(vfx.Budgets.splats, 12)
		expect.equal(vfx.Budgets.ambientMovers, 6)
		expect.equal(vfx.Budgets.uiJuiceFrames, 32)
		expect.equal(vfx.Budgets.editableMeshes, 5) -- spec phase2-squeeze §3.2: + the knead shell

		-- Config.Anim
		local ripple = anim.jellyRipple
		expect.equal(ripple.pathA, true)
		expect.equal(ripple.vertexColors, true)
		expect.equal(ripple.skinMode, "onHit")
		expect.equal(ripple.waveStudsPerSecond, 7)
		expect.equal(ripple.springOmega, 11)
		expect.equal(ripple.springZeta, 0.17)
		expect.equal(ripple.impulseSpeed, 26)
		expect.equal(ripple.impulseScaleMin, 0.85)
		expect.equal(ripple.impulseScaleMax, 1.2)
		expect.equal(ripple.impulseRadiusPerStud, 4.0)
		expect.equal(ripple.impulseRadiusMin, 3.2)
		expect.equal(ripple.impulseRadiusMax, 5.0)
		expect.equal(ripple.rushImpulseSpeed, 50)
		expect.equal(ripple.rushImpulseRadius, 5.5)
		expect.equal(ripple.rushProbeMarginStuds, 2)
		expect.equal(ripple.clampIn, 2.4)
		expect.equal(ripple.clampOut, 1.4)
		expect.equal(ripple.substep, 1 / 120)
		expect.equal(ripple.sleepEpsilon, 0.004)
		expect.equal(ripple.activeMargin, 1.5)
		expect.equal(ripple.faceSeconds, 3.2)
		expect.equal(ripple.rushFaceSeconds, 3.6)
		expect.equal(ripple.reducedImpulseScale, 0.3)
		expect.equal(ripple.edgeNormalMinDot, 0.8)
		expect.equal(ripple.floorNormalMinY, 0.8)
		expect.equal(ripple.mismatchStuds, 0.02)
		expect.deepEqual(ripple.gridHigh, {
			wallCols = 13,
			wallSideCols = 6,
			wallRowStuds = 0.5,
			wallTopCols = 7,
			wallTopRows = 4,
			blockCols = 12,
			blockRows = 13,
		})
		expect.deepEqual(ripple.gridLow, {
			wallCols = 7,
			wallSideCols = 3,
			wallRowStuds = 0.5,
			wallTopCols = 0,
			wallTopRows = 0,
			blockCols = 7,
			blockRows = 9,
		})
		expect.equal(ripple.maxVerticesHigh, 5600)
		expect.equal(ripple.maxTrianglesHigh, 9400)
		expect.equal(ripple.maxVerticesLow, 2600)
		expect.equal(ripple.maxTrianglesLow, 3800)
		expect.equal(ripple.boundsMargin, 0.6)
		expect.equal(ripple.writesPerFrame, 400)
		expect.equal(ripple.maxActiveFaces, 6)
		expect.equal(ripple.buildMsPerFrame, 2)
		expect.equal(ripple.presencePollSeconds, 0.25)
		expect.deepEqual(
			ripple.backstop,
			{ colsHigh = 35, rowsHigh = 13, colsLow = 24, rowsLow = 9, createStuds = 90, destroyStuds = 130 }
		)
		-- The whole-piece jiggle and path B's same feel (user test 2026-10-07, "too weak, need more animation like 10x").
		expect.deepEqual(ripple.jiggle, {
			amount = 0.18,
			rushAmount = 0.28,
			maxAmount = 0.3,
			backstopAmount = 0.06,
			omega = 14,
			zeta = 0.14,
			verticalShare = 0.4,
			maxPieces = 4,
			writesPerFrame = 1500,
			writesPerFrameLow = 800,
		})
		expect.deepEqual(ripple.pathB, {
			amount = 0.18,
			roundAmount = 0.2,
			rushScale = 1.55,
			omega = 14,
			zeta = 0.14,
			maxAmount = 0.3,
			reducedScale = 0.1,
			maxPieces = 6,
		})
		expect.deepEqual(ripple.rings, {
			coverDiameter = 2.5,
			coverSeconds = 0.3,
			floorDiameters = { 3.0, 1.8 },
			floorDelay = 0.1,
			floorSeconds = 0.35,
			transparencyFrom = 0.45,
		})
		expect.deepEqual(anim.squeeze.rhythm, {
			streakSeconds = 2.1, -- every click pays: its own value (was cycleSeconds 1.5 + gapSeconds 0.6)
			pitchPattern = { 1, 1.03, 1.06, 1.03 },
			pitchVariance = 0.01,
			popEvery = 8,
			popSparkles = 2,
			bigPopSparkles = 4,
		})
		expect.deepEqual(
			anim.held.lobbyIdle,
			{ periodSeconds = 2.8, ampY = 0.035, ampXZ = 0.0175, bobStuds = 0.05, crossfadeSeconds = 0.5 }
		)
		expect.deepEqual(anim.held.motionJiggle, {
			omega = 14,
			zeta = 0.35,
			perSpeed = 1 / 60,
			maxImpulse = 0.05,
			landingFromVy = -15,
			landingToVy = -1,
			landingImpulse = 0.06,
			maxJ = 0.08,
		})
		expect.equal(anim.held.equipPopPuffs, 6)
		expect.deepEqual(
			anim.giantPad.landing,
			{ minFallSpeed = 18, landedVy = -2, perSpeed = 0.004, min = 0.04, max = 0.14, seconds = 0.12 }
		)
		expect.equal(anim.elimination.confettiParticles, 18)
		expect.deepEqual(
			anim.duel.countdownBubble,
			{ px = 150, popFrom = 0.6, transparency = 0, burstScale = 1.25, burstMs = 120, tiltDeg = 6 }
		)
		expect.deepEqual(anim.duel.go, { popFrom = 1.6, popMs = 300, holdMs = 500, outMs = 250, outScale = 1.15 })
		expect.deepEqual(anim.duel.result, {
			lineSlidePx = 10,
			lineMs = 120,
			rewardCountMs = 600,
			rewardPulseScale = 1.12,
			rewardPulseMs = 200,
			titleTiltDeg = 4,
			defeatPopFrom = 1.15,
		})
		expect.deepEqual(anim.duel.confetti, {
			pieces = 18,
			drawPieces = 6,
			w = 8,
			h = 14,
			vxPx = 220,
			vyMinPx = 380,
			vyMaxPx = 520,
			gravityPx = 900,
			spinDeg = 360,
			lifetime = 1.2,
			fadeSeconds = 0.3,
		})

		-- Config.UI
		local motion = ui.motion
		-- UI overhaul (2026-10-11): the elastic modal pop (0.9 -> 1.03 -> 1 over 300 ms), a 150 ms squish on close,
		-- hover 1.05 over 120 ms, press 0.94 over 70 ms.
		expect.equal(motion.modalOpen.scaleFrom, 0.9)
		expect.equal(motion.modalOpen.overshoot, 1.03)
		expect.equal(motion.modalOpen.ms, 300)
		expect.equal(motion.modalClose.scaleTo, 0.9)
		expect.equal(motion.modalClose.visualMs, 150)
		expect.equal(motion.buttonHover.scale, 1.05)
		expect.equal(motion.buttonHover.ms, 120)
		expect.equal(motion.buttonPressed.scale, 0.94)
		expect.equal(motion.buttonPressed.ms, 70)
		expect.deepEqual(motion.buttonRelease.spring, { omega = 20, zeta = 0.35 })
		-- Reading (§18.1 #4 over B3's 2 cycles in 200 ms = 10 Hz): 1 cycle over 340 ms, 2.9 Hz.
		expect.deepEqual(motion.buttonError, { wigglePx = 4, cycles = 1, ms = 340 })
		expect.equal(motion.toast.popFrom, 0.9)
		expect.equal(motion.toast.nudgeScale, 1.06)
		expect.equal(motion.toast.nudgeMs, 160)
		expect.deepEqual(motion.badgePop, { from = 1.4, ms = 220 })
		expect.deepEqual(motion.readyPop, { from = 1.3, ms = 220 })
		expect.deepEqual(motion.coinCounter.pillBounce, { scale = 1.08, upMs = 70, downMs = 160 })
		expect.deepEqual(motion.coinCounter.spend, { scale = 0.95, downMs = 60, upMs = 140, countMs = 300 })
		expect.equal(motion.coinCounter.iconWiggleDeg, 12)
		expect.deepEqual(motion.coinFlight, {
			minAmount = 50,
			coinsPer = 40,
			minCoins = 3,
			maxCoins = 8,
			iconPx = 22,
			ms = 520,
			staggerMs = 45,
			arcPx = 120,
			startScale = 0.7,
			scaleInMs = 120,
			bounceMinGapMs = 334, -- reading (§18.1 #4 over B2's 60 ms): <= 3 Hz
			countTailMs = 400,
		})

		-- Config.Audio
		for category, ms in { throw = 60, wobble = 80, pop = 60, hover = 60, hitConfirm = 50, error = 250 } do
			expect.equal(audio.cooldownMs[category], ms)
		end
		for category, variance in { throw = 0.05, wobble = 0.08, pop = 0.06, hitConfirm = 0.03 } do
			expect.equal(audio.pitchVariance[category], variance)
		end
		expect.equal(audio.pitchMin, 0.5)
		expect.equal(audio.pitchMax, 2)
		expect.equal(audio.Spatial.othersThrowStuds, 60)
		expect.equal(audio.Spatial.othersThrowMax, 3)
		expect.deepEqual(audio.perKeyCap, { ["sfx.jellyWobble"] = 2 })
		expect.deepEqual(audio.countdownPitch, { 1.0, 1.06, 1.12 })
		expect.equal(audio.suddenDeathGoPitch, 0.9)
		expect.equal(audio.wobbleAfterImpactMs, 40)
		expect.equal(audio.softImpactMinorVolume, 0.5)
		expect.equal(audio.trackedStopFadeMs, 80)
		expect.equal(audio.Ducking.knockout, 0.5)
		expect.equal(audio.Ducking.knockoutSeconds, 0.6)
		expect.equal(audio.Ducking.telegraph, 0.8)
		expect.deepEqual(audio.toastSounds, {
			["grip.levelUp"] = "ui.gripUnlock",
			["grip.padUnlocked"] = "ui.gripUnlock",
			["grip.rankUp"] = "ui.gripUnlock",
		})
		expect.equal(audio.recentLogSize, 30)

		-- Config.Debug: Studio-only flags (the runner is in Studio, or Lune's IsStudio stub).
		expect.equal(Config.Debug.soundPicker, Config.Debug.isStudio)
		expect.equal(Config.Debug.forceRipplePathB, false)
	end)

	-- Feel pass rules F1-F11 (DESIGN §18.9; each with a planted bad value, §18.10 L1) ---------------------------------

	t.test("the shipped config and an unchanged WorldLayout copy pass F1-F11", function()
		for _, problems in { Config.validate(), validateWorld(function() end) } do
			local lines = {}
			for rule = 1, 11 do
				for _, line in ruleLines(problems, `F{rule}`) do
					table.insert(lines, line)
				end
			end
			if #lines > 0 then
				error(table.concat(lines, "\n"))
			end
			expect.falsy(containsText(problems, "Config feel pass"))
		end
	end)

	t.test("F1 reports a squeeze total of 20 (Exclusive 14 + 2 steam + 4 big pop sparkles)", function()
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.squeeze.flourish.Exclusive.particles = 14
		end)
		expect.truthy(containsAll(problems, { "F1:", "Exclusive", "= 20", "squeezePuffs" }))
		expect.equal(#ruleLines(problems, "F1"), 1)
		-- Below the 18 budget on its own, the flourish passes the older per-flourish rule.
		expect.falsy(containsText(problems, "particles (14) exceeds"))
	end)

	t.test("F1 counts the big pop's sparkles in place of the release pop's", function()
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.squeeze.rhythm.bigPopSparkles = 6 -- Exclusive: 12 + 2 + 6 = 20
		end)
		expect.truthy(containsAll(problems, { "F1:", "Exclusive", "= 20" }))
		expect.falsy(containsAll(problems, { "F1:", "Epic" })) -- 10 + 0 + 6 = 16
	end)

	t.test("F2 reports confetti parts that differ from the budget and too many elimination particles", function()
		local parts = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Confetti.parts = 12
		end)
		expect.truthy(containsAll(parts, { "F2:", "Confetti.parts", "eliminationConfettiParts" }))
		local particles = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.elimination.confettiParticles = 30 -- 30 + 12 sparkles > 40
		end)
		expect.truthy(containsAll(particles, { "F2:", "confetti + sparkles", "eliminationParticles" }))
	end)

	t.test("F3 reports a 5° punch and a punch cap above 4°", function()
		local punch = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Punch.hitDealt.fovDeg = -5
		end)
		expect.truthy(containsAll(punch, { "F3:", "hitDealt.fovDeg", "maxFovDeg" }))
		expect.equal(#ruleLines(punch, "F3"), 1)
		local cap = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Punch.maxFovDeg = 5
		end)
		expect.truthy(containsAll(cap, { "F3:", "Punch.maxFovDeg must be in (0, 4]" }))
	end)

	t.test("F4 reports a hold longer than the window cap and a cap longer than its window", function()
		local hold = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.HitStop.elimination = 0.2
		end)
		expect.truthy(containsAll(hold, { "F4:", "HitStop.elimination", "maxPerWindow" }))
		local window = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.HitStop.maxPerWindow = 0.6
		end)
		expect.truthy(containsAll(window, { "F4:", "maxPerWindow (0.6) must be <= windowSeconds" }))
	end)

	t.test("F5 reports 12 splats × 6 parts (72 > 60)", function()
		local problems = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Splat.droplets = 5
		end)
		expect.truthy(containsAll(problems, { "F5:", "= 72 parts exceeds 60" }))
	end)

	t.test("F6 reports a mat pulse that no longer adds up to matPulseSeconds", function()
		local problems = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.MatPulse.downMs = 120
		end)
		expect.truthy(containsAll(problems, { "F6:", "(160)", "matPulseSeconds × 1000 (150)" }))
	end)

	t.test("F7 reports an unstable wave speed at both qualities", function()
		local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.waveStudsPerSecond = 40 -- 2 · 40 / 120 / 0.5 = 1.33
		end)
		expect.truthy(containsAll(problems, { "F7:", "gridHigh", "unstable" }))
		expect.truthy(containsAll(problems, { "F7:", "gridLow", "unstable" }))
	end)

	t.test("F7 takes the wave spacing from the WorldLayout cover", function()
		-- A 2-stud-wide wall gives 2 / 12 = 0.17-stud columns at High: 2 · 7 / 120 / 0.17 = 0.7 > 0.5.
		local problems = validateWorld(function(layout)
			for _, piece in layout.Arena.cover do
				if piece.kind == "wall" then
					piece.parts[1].size = Vector3.new(2, 8, 2.5)
				end
			end
		end)
		expect.truthy(containsAll(problems, { "F7:", "gridHigh", "unstable" }))
		expect.falsy(containsAll(problems, { "F7:", "gridLow", "unstable" })) -- 2 / 6 = 0.33 at Low: 0.35
	end)

	t.test('F7 reports skinMode = "x", a path B amount above its cap, a zeta of 1 and too few impact rings', function()
		local skin = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.skinMode = "x"
		end)
		expect.truthy(containsAll(skin, { "F7:", "skinMode", '"x"' }))
		local amount = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.pathB.amount = 0.35
		end)
		expect.truthy(containsAll(amount, { "F7:", "pathB.amount (0.35)" }))
		local zeta = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.springZeta = 1
		end)
		expect.truthy(containsAll(zeta, { "F7:", "springZeta must be in (0, 1)" }))
		local rings = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Effects.impactRings = 1
		end)
		expect.truthy(containsAll(rings, { "F7:", "impactRings (1)", "floor rings" }))
	end)

	t.test("F7 caps path B and the jiggle at 0.3 (user test 2026-10-07) and reports a bad reducedScale", function()
		-- 0.3 is allowed now (was 0.1); above it is not.
		local allowed = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.pathB.maxAmount = 0.3
			anim.jellyRipple.pathB.amount = 0.3
		end)
		expect.equal(#ruleLines(allowed, "F7"), 0)
		local cap = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.pathB.maxAmount = 0.35
		end)
		expect.truthy(containsAll(cap, { "F7:", "pathB.maxAmount must be in (0, 0.3]", "0.35" }))
		local reduced = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.pathB.reducedScale = 0
		end)
		expect.truthy(containsAll(reduced, { "F7:", "pathB.reducedScale must be in (0, 1]" }))
	end)

	t.test("F7 reports a jiggle above 2.5 Hz, a zeta of 1, amounts above maxAmount and a cap above 0.3", function()
		local fast = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.jiggle.omega = 16.5 -- 2.63 Hz
		end)
		expect.truthy(containsAll(fast, { "F7:", "jiggle.omega (16.5)", "2.5 Hz" }))
		local zeta = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.jiggle.zeta = 1
		end)
		expect.truthy(containsAll(zeta, { "F7:", "jiggle.zeta must be in (0, 1)" }))
		local amounts = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.jiggle.amount = 0.32
			anim.jellyRipple.jiggle.rushAmount = 0.31
			anim.jellyRipple.jiggle.backstopAmount = 0
		end)
		expect.truthy(containsAll(amounts, { "F7:", "jiggle.amount (0.32)" }))
		expect.truthy(containsAll(amounts, { "F7:", "jiggle.rushAmount (0.31)" }))
		expect.truthy(containsAll(amounts, { "F7:", "jiggle.backstopAmount (0)" }))
		local cap = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.jellyRipple.jiggle.maxAmount = 0.4
		end)
		expect.truthy(containsAll(cap, { "F7:", "jiggle.maxAmount must be in (0, 0.3]" }))
	end)

	t.test(
		"F7 reports a jiggle that is still moving after faceSeconds and bad share, piece and write counts and Low budget",
		function()
			local slow = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.jellyRipple.jiggle.zeta = 0.05 -- e^(-0.7 · 3.2) leaves about 0.04 of the 0.3 cap
			end)
			expect.truthy(containsAll(slow, { "F7:", "still swings", "faceSeconds", "raise zeta" }))
			local counts = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.jellyRipple.jiggle.verticalShare = 1.5
				anim.jellyRipple.jiggle.maxPieces = 0
				anim.jellyRipple.jiggle.writesPerFrame = 2.5
			end)
			expect.truthy(containsAll(counts, { "F7:", "jiggle.verticalShare" }))
			expect.truthy(containsAll(counts, { "F7:", "jiggle.maxPieces must be an integer >= 1" }))
			expect.truthy(containsAll(counts, { "F7:", "jiggle.writesPerFrame must be an integer >= 1" }))
			-- Phones get the smaller budget: writesPerFrameLow in [1, writesPerFrame].
			local low = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.jellyRipple.jiggle.writesPerFrameLow = 2000
			end)
			expect.truthy(containsAll(low, { "F7:", "jiggle.writesPerFrameLow must be an integer in [1,", "2000" }))
			local none = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.jellyRipple.jiggle.writesPerFrameLow = 0
			end)
			expect.truthy(containsAll(none, { "F7:", "jiggle.writesPerFrameLow" }))
		end
	)

	t.test("F8 reports sound keys missing from AssetTable, a bad per-key cap and bad countdown pitches", function()
		local toast = validateBrokenCopy(t.Shared, "Audio", function(audio)
			audio.toastSounds["grip.levelUp"] = "ui.notAKey"
		end)
		expect.truthy(containsAll(toast, { "F8:", "toastSounds", "ui.notAKey", "AssetTable" }))
		local cap = validateBrokenCopy(t.Shared, "Audio", function(audio)
			audio.perKeyCap["sfx.notAKey"] = 0
		end)
		expect.truthy(containsAll(cap, { "F8:", "perKeyCap", "sfx.notAKey", "integer >= 1" }))
		expect.truthy(containsAll(cap, { "F8:", "perKeyCap", "sfx.notAKey", "not a sound key" }))
		local count = validateBrokenCopy(t.Shared, "Audio", function(audio)
			audio.countdownPitch = { 1, 1.06 }
		end)
		expect.truthy(containsAll(count, { "F8:", "countdownPitch must list 3 pitches" }))
		local range = validateBrokenCopy(t.Shared, "Audio", function(audio)
			audio.countdownPitch = { 1, 1.06, 2.5 }
		end)
		expect.truthy(containsAll(range, { "F8:", "countdownPitch[3]" }))
	end)

	t.test("F9 reports a 3.3 Hz boing, a zeta of 1, bad coin counts, bad wiggles and a fast pill bounce", function()
		-- §18.14 #9: ω 22 with ζ 0.3 wobbles at 3.34 Hz.
		local boing = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.HeldBoing.omega = 22
		end)
		expect.truthy(containsAll(boing, { "F9:", "HeldBoing", "Hz", "above 3 Hz" }))
		local spring = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.motion.buttonRelease.spring.zeta = 1
		end)
		expect.truthy(containsAll(spring, { "F9:", "buttonRelease.spring zeta" }))
		local coins = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.motion.coinFlight.minCoins = 9
		end)
		expect.truthy(containsAll(coins, { "F9:", "minCoins (9) must be <= maxCoins" }))
		local wiggle = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.motion.buttonError.ms = 0
		end)
		expect.truthy(containsAll(wiggle, { "F9:", "buttonError.ms" }))
		-- §18.1 #4: B3's literal "2 cycles over 200 ms" wiggles at 10 Hz; a 60 ms bounce gap bounces the pill at 16.7 Hz.
		local fastWiggle = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.motion.buttonError.cycles = 2
			ui.motion.buttonError.ms = 200
		end)
		expect.truthy(containsAll(fastWiggle, { "F9:", "buttonError wiggles at 10.00 Hz", "above 3 Hz" }))
		local fastBounce = validateBrokenCopy(t.Shared, "UI", function(ui)
			ui.motion.coinFlight.bounceMinGapMs = 60
		end)
		expect.truthy(containsAll(fastBounce, { "F9:", "bounceMinGapMs", "16.67 Hz", "above 3 Hz" }))
		local jiggle = validateBrokenCopy(t.Shared, "Anim", function(anim)
			anim.held.motionJiggle.omega = 30
		end)
		expect.truthy(containsAll(jiggle, { "F9:", "motionJiggle", "above 3 Hz" }))
	end)

	t.test("F10 reports room for 4 editable meshes when the pads, a ripple skin and the knead shell need 5", function()
		local problems = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Budgets.editableMeshes = 4
		end)
		expect.truthy(containsAll(problems, { "F10:", "editableMeshes (4)", "knead shell" }))
		-- Without the ripple's path A, 4 is enough again.
		local noSkin = validateBrokenSections(t.Shared, {
			Vfx = function(vfx)
				vfx.Budgets.editableMeshes = 4
			end,
			Anim = function(anim)
				anim.jellyRipple.pathA = false
			end,
		})
		expect.equal(#ruleLines(noSkin, "F10"), 0)
	end)

	t.test("F11 reports a red guard that leaves a red accent red (0.5 < 1 - 0.45)", function()
		local problems = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Splat.redGuardWhiten = 0.5
		end)
		expect.truthy(containsAll(problems, { "F11:", "redGuardWhiten (0.5)", "1 - redMinSaturation" }))
	end)

	t.test("a missing feel pass block is a problem line, not an error", function()
		local problems = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Punch = nil
		end)
		expect.truthy(containsAll(problems, { "Config feel pass F3", "crashed" }))
	end)

	-- Squishy overhaul (spec 2026-10-09 §3.2, §6) ------------------------------------------------------------

	t.test("the squishy rig keys hold the spec values", function()
		local anim = Config.Anim
		local rig = anim.rig
		expect.deepEqual(rig.feels, {
			foam = { k = 140, c = 10, gain = 0.55 },
			mochi = { k = 110, c = 8, gain = 0.85 },
			jelly = { k = 300, c = 4.5, gain = 1.3 },
			plush = { k = 170, c = 10, gain = 0.6 },
		})
		expect.equal(rig.releaseKick, 0.06)
		expect.equal(rig.releaseKickMax, 0.08)
		expect.equal(rig.hitKick, 0.15)
		expect.deepEqual(
			rig.face,
			{ squishBelow = 0.86, squishAbove = 0.9, minHoldSeconds = 0.2, hitSeconds = 0.3, wowSeconds = 0.3 }
		)
		expect.deepEqual(
			rig.blink,
			{ minSeconds = 2, maxSeconds = 5, seconds = 0.14, closedY = 0.12, shineHideBelow = 0.5 }
		)
		expect.deepEqual(rig.looks, {
			cheekPuff = 0.45,
			wowEye = 1.3,
			squishMouthOpen = Vector3.new(1.2, 1.5, 1),
			wowMouthOpen = Vector3.new(0.8, 0.8, 1),
			wowSquishMouth = Vector3.new(0.6, 1, 1),
		})
		expect.deepEqual(rig.sections, { k = 140, c = 8, gain = 0.12, maxDeg = 30 })
		expect.deepEqual(rig.flight, {
			tumble = {
				wobbleDeg = 14,
				wobbleHz = 1.6,
				nodDeg = 10,
				nodHz = 1.6,
				pulseHz = 1.4,
				flapDeg = 15,
				flapHz = 1.6,
			},
			frisbee = { rollDegPerSecond = 540, flapDeg = 25, flapHz = 2 },
			spiral = { rollDegPerSecond = 720 },
			wheel = { rollDegPerSecond = 540 },
			glide = { wobbleDeg = 9, wobbleHz = 1.5, flapDeg = 25, flapHz = 2.5 },
			face = { wobbleDeg = 6, wobbleHz = 1.5, flapDeg = 20, flapHz = 2 },
			hop = { pulseAmp = 0.1, pulseHz = 2, flapDeg = 20, flapHz = 2 },
			upright = { wobbleDeg = 6, wobbleHz = 1.2 },
			float = { wobbleDeg = 11, wobbleHz = 1, flapDeg = 20, flapHz = 1.2 },
			sway = { wobbleDeg = 16, wobbleHz = 2, flapDeg = 20, flapHz = 2.5 },
			wobble = { wobbleDeg = 8, wobbleHz = 2 },
			roll = { rollDegPerSecond = 360 },
		})
		local flourish = anim.squeeze.flourish
		expect.equal(flourish.Uncommon.twistDeg, 6)
		expect.equal(flourish.Epic.twistDeg, 6)
		expect.equal(flourish.Epic.releaseKick, 1.5)
		expect.equal(flourish.Exclusive.releaseKick, 1.5)
		expect.equal(flourish.Exclusive.sectionFlareDeg, 12)
		expect.equal(flourish.Common.releaseKick, nil)
		expect.equal(Config.Inspect.Framing.squeezeWidening, 1.28)
		expect.equal(Config.Inspect.Framing.widenMargin, 0.04)
		expect.equal(Config.Inspect.Collection.idleStuds, 20)
		expect.equal(Config.Inspect.Collection.idleMax, 8)
		local budgets = Config.Vfx.Budgets
		expect.equal(budgets.deformingRigs, 12)
		expect.equal(budgets.deformingRigsLow, 8)
		expect.equal(budgets.heroRigs, 3)
		expect.equal(budgets.heroRigsLow, 2)
		expect.equal(budgets.nearRigs, 6)
		expect.equal(budgets.nearRigsLow, 3)
		expect.equal(budgets.flightDetailModels, 2)
		expect.equal(budgets.flightDetailModelsLow, 1)
	end)

	t.test(
		"validate reports rig motion above 3 Hz, a face that can toggle faster and kicks above their caps",
		function()
			local problems = validateBrokenCopy(t.Shared, "Anim", function(anim)
				anim.rig.feels.jelly.k = 400 -- 3.17 Hz
				anim.rig.sections.k = 400
				anim.rig.flight.sway.flapHz = 3 -- flaps <= 2.5 Hz
				anim.rig.flight.spiral.rollDegPerSecond = 900 -- > 2 turns a second
				anim.rig.flight.glide.wobbleHz = 3.5
				anim.rig.face.minHoldSeconds = 0.1 -- 5 toggles a second
				anim.rig.hitKick = 0.2 -- above Kit.JIGGLE_CAP 0.18
				anim.rig.releaseKickMax = 0.1 -- above held.motionJiggle.maxJ
				anim.rig.flight.wobble.wobbleDeg = 9 -- no longer today's Catalog "wobble"
			end)
			expect.truthy(containsAll(problems, { "Config.Anim.rig.feels.jelly", "Hz" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.sections", "Hz" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.flight.sway.flapHz" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.flight.spiral.rollDegPerSecond" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.flight.glide.wobbleHz" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.face.minHoldSeconds" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.hitKick", "JIGGLE_CAP" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.releaseKickMax", "maxJ" }))
			expect.truthy(containsAll(problems, { "Config.Anim.rig.flight.wobble", "wobbleRollDeg" }))
		end
	)

	t.test(
		"validate reports a motion row outside the §6 ranges, an unknown feel or style, a squishy without one",
		function()
			local problems = validateBrokenBlueprint(t.Shared, "toast", function(blueprint)
				blueprint.motion.squeeze.depth = 0.5
				blueprint.motion.squeeze.widen = 0.9
				blueprint.motion.squeeze.kRel = 70
				blueprint.motion.squeeze.cRel = 5
				blueprint.motion.feel = "rubber"
				blueprint.motion.flight.style = "loop"
			end)
			local path = "Art/SquishyBlueprints.toast.motion"
			expect.truthy(containsAll(problems, { `{path}.squeeze.depth`, "[0.55, 0.72]" }))
			expect.truthy(containsAll(problems, { `{path}.squeeze.widen`, "[0.4, 0.85]" }))
			expect.truthy(containsAll(problems, { `{path}.squeeze.kRel`, "[20, 60]" }))
			expect.truthy(containsAll(problems, { `{path}.squeeze.cRel`, "[6, 10]" }))
			expect.truthy(containsAll(problems, { `{path}.feel`, "rubber" }))
			expect.truthy(containsAll(problems, { `{path}.flight.style`, "loop" }))
			local missing = validateBrokenBlueprint(t.Shared, "toast", function(blueprint)
				blueprint.motion = nil
			end)
			expect.truthy(containsAll(missing, { "Catalog.toast", "motion" }))
		end
	)

	t.test("validate reports detail budgets that do not fit and Low budgets above their own", function()
		local problems = validateBrokenCopy(t.Shared, "Vfx", function(vfx)
			vfx.Budgets.heroRigs = 8 -- 8 hero + 6 near > 12
			vfx.Budgets.nearRigsLow = 7 -- above nearRigs 6 and 2 + 7 > 8
			vfx.Budgets.flightDetailModelsLow = 3
		end)
		expect.truthy(containsAll(problems, { "Config.Vfx.Budgets", "heroRigs + nearRigs", "deformingRigs" }))
		expect.truthy(containsAll(problems, { "Config.Vfx.Budgets", "heroRigsLow + nearRigsLow" }))
		expect.truthy(containsAll(problems, { "Config.Vfx.Budgets.nearRigsLow" }))
		expect.truthy(containsAll(problems, { "Config.Vfx.Budgets.flightDetailModelsLow" }))
		local framing = validateBrokenCopy(t.Shared, "Inspect", function(inspect)
			inspect.Framing.widenMargin = 0
			inspect.Collection.idleMax = 0
		end)
		expect.truthy(containsAll(framing, { "Config.Inspect.Framing.widenMargin" }))
		expect.truthy(containsAll(framing, { "Config.Inspect.Collection.idleMax" }))
	end)

	t.test("Inspect frames each toy at its widest squeeze scale + 0.04, never below 1.28", function()
		local Blueprints = t.requireShared("Art/SquishyBlueprints")
		local Kit = t.requireShared("Art/SquishyBlueprints/Kit")
		local framing = Config.Inspect.Framing
		local count = 0
		for id, blueprint in Blueprints do
			local motion = blueprint.motion
			if motion then
				count += 1
				local widest = 1
				for _, extreme in Kit.extremes(motion, "Y") do
					widest = math.max(widest, extreme.S.X, extreme.S.Y, extreme.S.Z)
				end
				-- The widest is the press width at depth: the jiggle caps and the overshoot stay inside it.
				local press = 1 + (1 - motion.squeeze.depth) * motion.squeeze.widen
				expect.truthy(widest <= math.max(press, 1 + Kit.JIGGLE_CAP) + 1e-6)
				local frame = math.max(framing.squeezeWidening, widest + framing.widenMargin)
				expect.truthy(frame >= 1.28 and frame <= 1.42)
				expect.truthy(type(id) == "string")
			end
		end
		expect.truthy(count >= 14)
		local mochi = Blueprints.mochi_fox.motion.squeeze
		expect.near(1 + (1 - mochi.depth) * mochi.widen + framing.widenMargin, 1.4, 1e-9)
	end)

	-- Canonical decisions -----------------------------------------------------------------------------------

	-- No invented ids (DESIGN §0.3 #9, §6.11): every coin bundle ships without a product id.
	t.test("no coin bundle has a product id", function()
		for index, bundle in Config.Monetization.CoinBundles do
			if bundle.productId ~= nil then
				error(
					string.format("CoinBundles[%s].productId is set (%s)", tostring(index), tostring(bundle.productId))
				)
			end
		end
	end)

	-- No game passes and no "coming soon" pass line in v1 (DESIGN §2.2, §6.11).
	t.test("no game passes are configured and none are advertised", function()
		expect.equal(next(Config.Monetization.GamePasses), nil)
		expect.equal(Config.Monetization.ShowPassesComingSoon, false)
	end)

	-- Products are validated against the owning group (DESIGN §2.2, §12 #18).
	t.test("the creator group is DIJAY Studios", function()
		expect.equal(Config.Monetization.creatorGroupId, CREATOR_GROUP_ID)
	end)

	-- No automatic kicks in v1 (DESIGN §2.7).
	t.test("abuse never kicks automatically", function()
		expect.equal(Config.Net.kickOnAbuse, false)
	end)
end
