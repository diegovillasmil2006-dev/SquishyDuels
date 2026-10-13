--!strict
-- Catalog_Test: unit tests for ReplicatedStorage.Shared.Catalog and the rarity language it uses (Rarity,
-- Art/RarityStyle, Art/Palette). Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §2.2, §4.1-§4.3, §7.2): the catalog holds exactly the 8 squishies of §4.2 in table order, then the
-- 6 of the squishy overhaul (spec 2026-10-09 §3.3), with their names, rarities, throw stats, prices, trails,
-- ultimates, elimination effects and presentation data; each new squishy throws exactly like its same-rarity sibling;
-- no accent trips the splat red guard; every nameKey exists in Strings and every blueprintId in
-- Art/SquishyBlueprints; throw stats sit inside Config.Combat.Bands; squishy power follows
-- Config.Economy.SquishyPower unless overridden (Phase 3: the per-squishy squeeze Coins are gone); shop prices are the
-- spec 2026-10-12 §6 ladder; the API is get, list, isValidId, starterId, byRarity and getPower; entries
-- cannot be changed. Rarity has the canonical ORDER, name keys, pips and hasTrail; RarityStyle and Palette carry the
-- §4.3 and §7.2 values, and every rarity label reaches 4.5:1 contrast on its colour.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type Expected = {
	id: string,
	name: string,
	rarity: string,
	speed: number,
	gravity: number,
	radius: number,
	cooldown: number,
	windup: number,
	trail: string?,
	ultimate: string?,
	elimination: string,
	shopPrice: number?,
}

type Presentation = {
	grip: Vector3,
	heldYaw: number,
	yaw: number,
	pitch: number,
	axis: string,
	foamT: number,
	accent: string,
	spin: string,
	fx: string?,
}

-- DESIGN §4.2 main table, in its order.
local EXPECTED: { Expected } = {
	{
		id = "kitty_bread",
		name = "Kitty Bread",
		rarity = "Common",
		speed = 95,
		gravity = 35,
		radius = 1.0,
		cooldown = 1.00,
		windup = 0.18,
		elimination = "standard",
	},
	{
		id = "toast",
		name = "Toast",
		rarity = "Common",
		speed = 105,
		gravity = 25,
		radius = 0.8,
		cooldown = 1.05,
		windup = 0.18,
		elimination = "standard",
		shopPrice = 10_000,
	},
	{
		id = "banana",
		name = "Banana",
		rarity = "Common",
		speed = 88,
		gravity = 50,
		radius = 1.2,
		cooldown = 0.95,
		windup = 0.18,
		elimination = "standard",
		shopPrice = 10_000,
	},
	{
		id = "butter",
		name = "Butter",
		rarity = "Uncommon",
		speed = 95,
		gravity = 30,
		radius = 0.9,
		cooldown = 1.05,
		windup = 0.15,
		trail = "ribbon",
		elimination = "standard",
		shopPrice = 2_700_000,
	},
	{
		id = "chocolate",
		name = "Chocolate",
		rarity = "Uncommon",
		speed = 90,
		gravity = 40,
		radius = 1.4,
		cooldown = 1.00,
		windup = 0.18,
		trail = "ribbon",
		elimination = "standard",
		shopPrice = 2_700_000,
	},
	{
		id = "bird",
		name = "Birdie",
		rarity = "Epic",
		speed = 110,
		gravity = 20,
		radius = 0.9,
		cooldown = 1.10,
		windup = 0.18,
		trail = "twinRibbon",
		ultimate = "flock_volley", -- spec phase 5: the design's Epic ultimates (ults.js:3)
		elimination = "epic_pending",
		shopPrice = 1_700_000_000,
	},
	{
		id = "donut",
		name = "Donut",
		rarity = "Epic",
		speed = 92,
		gravity = 38,
		radius = 1.3,
		cooldown = 1.00,
		windup = 0.19,
		trail = "twinRibbon",
		ultimate = "sprinkle_roller", -- ults.js:4
		elimination = "epic_pending",
		shopPrice = 1_700_000_000,
	},
	{
		id = "dragon",
		name = "Dragon",
		rarity = "Exclusive",
		speed = 92,
		gravity = 35,
		radius = 1.0,
		cooldown = 1.05,
		windup = 0.19,
		trail = "ember", -- "Ember comet"
		ultimate = "dragon_rush",
		elimination = "standard",
		shopPrice = 1_100_000_000_000,
	},
	-- Spec 2026-10-09 §3.3: appended after Dragon; each throw is a copy of a same-rarity sibling.
	{
		id = "boba_bear",
		name = "Boba Bear",
		rarity = "Common",
		speed = 95,
		gravity = 35,
		radius = 1.0,
		cooldown = 1.00,
		windup = 0.18,
		elimination = "standard",
		shopPrice = 10_000,
	},
	{
		id = "pancake_pup",
		name = "Pancake Pup",
		rarity = "Common",
		speed = 105,
		gravity = 25,
		radius = 0.8,
		cooldown = 1.05,
		windup = 0.18,
		elimination = "standard",
		shopPrice = 10_000,
	},
	{
		id = "mochi_fox",
		name = "Mochi Fox",
		rarity = "Uncommon",
		speed = 95,
		gravity = 30,
		radius = 0.9,
		cooldown = 1.05,
		windup = 0.15,
		trail = "ribbon",
		elimination = "standard",
		shopPrice = 2_700_000,
	},
	{
		id = "strawberry_frog",
		name = "Strawberry Frog",
		rarity = "Uncommon",
		speed = 90,
		gravity = 40,
		radius = 1.4,
		cooldown = 1.00,
		windup = 0.18,
		trail = "ribbon",
		elimination = "standard",
		shopPrice = 2_700_000,
	},
	{
		id = "cloud_bunny",
		name = "Cloud Bunny",
		rarity = "Epic",
		speed = 110,
		gravity = 20,
		radius = 0.9,
		cooldown = 1.10,
		windup = 0.18,
		trail = "twinRibbon",
		ultimate = "rain_check", -- ults.js:5
		elimination = "epic_pending",
		shopPrice = 1_700_000_000,
	},
	{
		id = "cupcake_axolotl",
		name = "Cupcake Axolotl",
		rarity = "Epic",
		speed = 92,
		gravity = 38,
		radius = 1.3,
		cooldown = 1.00,
		windup = 0.19,
		trail = "twinRibbon",
		ultimate = "bubble_pop", -- ults.js:6
		elimination = "epic_pending",
		shopPrice = 1_700_000_000,
	},
}

-- Spec 2026-10-09 §3.3: each new squishy plays exactly like this same-rarity sibling.
local SIBLING: { [string]: string } = {
	boba_bear = "kitty_bread",
	pancake_pup = "toast",
	mochi_fox = "butter",
	strawberry_frog = "chocolate",
	cloud_bunny = "bird",
	cupcake_axolotl = "donut",
}

-- DESIGN §4.2 presentation table. The "ears/wings rigidity" notes are blueprint part rigidities (§8.2), not hooks.
local PRESENTATION: { [string]: Presentation } = {
	kitty_bread = {
		grip = Vector3.new(0, -0.42, 0.10),
		heldYaw = 35,
		yaw = 20,
		pitch = 8,
		axis = "Y",
		foamT = 0.32,
		accent = "#D98E47",
		spin = "wobble",
	},
	toast = {
		grip = Vector3.new(0, -0.42, 0.30), -- held from behind (play-check 2026-10-05)
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.26,
		accent = "#C9853F",
		spin = "roll",
	},
	banana = {
		grip = Vector3.new(0, -0.30, 0.32), -- held from behind (play-check 2026-10-05)
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Z",
		foamT = 0.30,
		accent = "#FFE066",
		spin = "roll",
	},
	butter = {
		grip = Vector3.new(0, -0.40, 0.05),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.42,
		accent = "#FFD86B",
		spin = "wobble",
	},
	chocolate = {
		grip = Vector3.new(0, -0.55, 0.30), -- held from behind (play-check 2026-10-05)
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.34,
		accent = "#7A4632",
		spin = "wobble",
	},
	bird = {
		grip = Vector3.new(0, -0.50, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.30,
		accent = "#7CC0F5",
		spin = "wobble",
	},
	donut = {
		grip = Vector3.new(0, -0.60, 0.32), -- held from behind (play-check 2026-10-05)
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.36,
		accent = "#FF8FB1",
		spin = "roll",
	},
	dragon = {
		grip = Vector3.new(0, -0.60, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.30,
		accent = "#3FB8AF",
		spin = "wobble",
		fx = "dragon_steam",
	},
	-- Spec 2026-10-09 §3.3 (grip and inspect [P], retuned in the Studio pass). Strawberry Frog's accent is the design's
	-- trail start: its body red (#EE4A5C) would trip the splat red guard.
	boba_bear = {
		grip = Vector3.new(0, -0.45, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.30,
		accent = "#B07A52",
		spin = "wobble",
	},
	pancake_pup = {
		grip = Vector3.new(0, -0.35, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 20,
		axis = "Y",
		foamT = 0.36,
		accent = "#C8752A",
		spin = "roll",
	},
	mochi_fox = {
		grip = Vector3.new(0, -0.40, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.42,
		accent = "#F39A4C",
		spin = "wobble",
	},
	strawberry_frog = {
		grip = Vector3.new(0, -0.50, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.28,
		accent = "#FF9AA8",
		spin = "wobble",
	},
	cloud_bunny = {
		grip = Vector3.new(0, -0.45, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.42,
		accent = "#D5C8F6",
		spin = "wobble",
	},
	cupcake_axolotl = {
		grip = Vector3.new(0, -0.50, 0.10),
		heldYaw = 35,
		yaw = 25,
		pitch = 12,
		axis = "Y",
		foamT = 0.32,
		accent = "#F9AFCB",
		spin = "wobble",
	},
}

local RARITY_ORDER = { "Common", "Uncommon", "Epic", "Exclusive" }

-- DESIGN §4.3 rarity table. contrast = label text on the rarity colour.
local RARITY_STYLE = {
	Common = { color = "#A9B4C2", pips = 1, shape = "dot", label = "Ink", contrast = 6.4, stroke = 2 },
	Uncommon = { color = "#4CC38A", pips = 2, shape = "dot", label = "Ink", contrast = 6.0, stroke = 3 },
	Epic = { color = "#7C3AED", pips = 3, shape = "dot", label = "White", contrast = 5.7, stroke = 3 },
	Exclusive = { color = "#FF9F1C", pips = 4, shape = "diamond", label = "Ink", contrast = 6.5, stroke = 4 },
}

-- DESIGN §7.2 tokens and reserved gameplay colours.
local PALETTE_HEX: { [string]: string } = {
	Cream = "#FFF4E6",
	Vanilla = "#F6E3CC",
	Strawberry = "#FF8FB1",
	Bubblegum = "#FFC7DA",
	Mint = "#8EDFC4",
	MintCream = "#CFF3E6",
	Lemon = "#FFD86B",
	Sky = "#8CC8FF",
	Lavender = "#B9A6E8",
	LaneLilac = "#E4DCF7",
	Blueberry = "#8E84C8",
	LavenderMilkA = "#DCD3EC",
	LavenderMilkB = "#D0C6E4",
	Cocoa = "#6B4A3A",
	Ink = "#3B2A35",
	UIPanel = "#FFFFFF",
	UIStroke = "#E9D9C8",
	UIPrimary = "#E0466A",
	CoinGold = "#FFC83D",
	CoinRing = "#D99A1E",
	CoinHighlight = "#FFE08A",
	Danger = "#FF5A4E",
}
local RESERVED = { "CoinGold", "CoinRing", "CoinHighlight", "Danger" }

local MIN_TEXT_CONTRAST = 4.5 -- §7.2 body text

-- Helpers ------------------------------------------------------------------------------------------------------------

local function sameColor(actual: unknown, hex: string): boolean
	return typeof(actual) == "Color3" and actual == Color3.fromHex(hex)
end

local function sameHex(actual: unknown, hex: string): boolean
	return type(actual) == "string" and string.upper(actual) == string.upper(hex)
end

-- WCAG 2 relative luminance and contrast ratio.
local function channel(c: number): number
	return if c <= 0.03928 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(color: Color3): number
	return 0.2126 * channel(color.R) + 0.7152 * channel(color.G) + 0.0722 * channel(color.B)
end

local function contrast(a: Color3, b: Color3): number
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

local function ids(defs: { any }): string
	local out = {}
	for _, def in defs do
		table.insert(out, tostring(def.id))
	end
	return table.concat(out, ",")
end

local function idsOfRarity(rarity: string): string
	local out = {}
	for _, row in EXPECTED do
		if row.rarity == rarity then
			table.insert(out, row.id)
		end
	end
	return table.concat(out, ",")
end

-- Looks a blueprint up without assuming more of Art/SquishyBlueprints' API than "data keyed by blueprint id" or a
-- get(id) function.
local function hasBlueprint(blueprints: any, blueprintId: string): boolean
	if type(blueprints) ~= "table" then
		return false
	end
	if type(blueprints.get) == "function" then
		local ok, found = pcall(blueprints.get, blueprintId)
		if ok and found ~= nil then
			return true
		end
	end
	return blueprints[blueprintId] ~= nil
end

return function(t: Context)
	local Catalog = t.requireShared("Catalog")
	local Rarity = t.requireShared("Rarity")
	local RarityStyle = t.requireShared("Art/RarityStyle")
	local Palette = t.requireShared("Art/Palette")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local expect = t.expect

	-- Catalog: content (§4.2) ---------------------------------------------------------------------------------------

	t.test("list returns the 8 squishies of DESIGN §4.2 in table order, then the 6 new ones", function()
		local list = Catalog.list()
		expect.equal(#list, 14)
		expect.equal(#list, #EXPECTED)
		expect.equal(ids(list), ids(EXPECTED))
	end)

	t.test("each new squishy throws exactly like its same-rarity sibling (spec 2026-10-09 §3.3)", function()
		local rows: { [string]: Expected } = {}
		for _, row in EXPECTED do
			rows[row.id] = row
		end
		for id, siblingId in SIBLING do
			local def, sibling = Catalog.get(id), Catalog.get(siblingId)
			assert(def ~= nil and sibling ~= nil, id .. " or " .. siblingId .. " is missing")
			expect.equal(def.rarity, sibling.rarity)
			expect.deepEqual(def.throw, sibling.throw)
			-- Spec phase 5: the Epics have their own ultimates (the design's, ults.js:3-6); the others have none.
			expect.equal(def.ultimateId, rows[id].ultimate)
		end
	end)

	t.test("no accent trips the splat red guard (Strawberry Frog's is #FF9AA8, not its body red)", function()
		local splat = Config.Vfx.Splat
		for _, def in Catalog.list() do
			local h, s = Color3.fromHex(def.visuals.accent):ToHSV()
			local fromRed = math.min(h * 360, 360 - h * 360)
			if fromRed <= splat.redHueDeg and s > splat.redMinSaturation then
				error(`{def.id} accent {def.visuals.accent} reads as red to the splat guard`)
			end
		end
	end)

	t.test("names, rarities and throw stats match DESIGN §4.2", function()
		for _, row in EXPECTED do
			local def = Catalog.get(row.id)
			assert(def ~= nil, row.id .. " is missing")
			expect.equal(Strings.resolve(def.nameKey), row.name)
			expect.equal(def.rarity, row.rarity)
			for _, stat in { "speed", "gravity", "radius", "cooldown", "windup" } do
				local wanted = (row :: any)[stat]
				if math.abs(def.throw[stat] - wanted) > 1e-9 then
					error(string.format("%s throw.%s = %s, DESIGN says %s", row.id, stat, def.throw[stat], wanted))
				end
			end
		end
	end)

	-- Spec 2026-10-12 §6: the squishy ladder (were DESIGN §4.2's 1,200 / 2,500 / 7,500 / 25,000).
	t.test("shop prices match the spec 2026-10-12 ladder and the starter is not sold", function()
		for _, row in EXPECTED do
			local def = Catalog.get(row.id)
			if def.shopPrice ~= row.shopPrice then
				error(
					string.format(
						"%s shopPrice = %s, the spec says %s",
						row.id,
						tostring(def.shopPrice),
						tostring(row.shopPrice)
					)
				)
			end
		end
	end)

	t.test("presentation data matches DESIGN §4.2", function()
		for _, row in EXPECTED do
			local def = Catalog.get(row.id)
			local want = PRESENTATION[row.id]
			local grip = def.hold.grip
			expect.equal(typeof(grip), "Vector3")
			expect.near(grip.X, want.grip.X, 1e-6)
			expect.near(grip.Y, want.grip.Y, 1e-6)
			expect.near(grip.Z, want.grip.Z, 1e-6)
			expect.equal(def.hold.heldYaw, want.heldYaw)
			expect.equal(def.inspect.yaw, want.yaw)
			expect.equal(def.inspect.pitch, want.pitch)
			expect.equal(def.anim.squeezeAxis, want.axis)
			expect.near(def.anim.foamRecoveryT, want.foamT, 1e-9)
			expect.equal(def.anim.squeezeFx, want.fx)
			expect.equal(def.visuals.flightSpin, want.spin)
			if not sameHex(def.visuals.accent, want.accent) then
				error(
					string.format("%s accent = %s, DESIGN says %s", row.id, tostring(def.visuals.accent), want.accent)
				)
			end
			-- The accent must be a usable colour.
			expect.equal(typeof(Color3.fromHex(def.visuals.accent)), "Color3")
		end
	end)

	t.test("squeezeFx names a hook in Config.Anim.squeeze.squeezeFx", function()
		for _, def in Catalog.list() do
			local fx = def.anim.squeezeFx
			if fx ~= nil and Config.Anim.squeeze.squeezeFx[fx] == nil then
				error(string.format("%s squeezeFx %q has no Config.Anim hook", def.id, fx))
			end
		end
	end)

	t.test("foam recovery times are inside the Config.Anim range", function()
		local squeeze = Config.Anim.squeeze
		for _, def in Catalog.list() do
			local value = def.anim.foamRecoveryT
			if value < squeeze.foamRecoveryMin or value > squeeze.foamRecoveryMax then
				error(
					string.format(
						"%s foamRecoveryT %s outside [%s, %s]",
						def.id,
						value,
						squeeze.foamRecoveryMin,
						squeeze.foamRecoveryMax
					)
				)
			end
		end
	end)

	t.test("trails: none for Commons, the §4.2 trail for every other squishy", function()
		for _, row in EXPECTED do
			local def = Catalog.get(row.id)
			expect.equal(def.visuals.trail, row.trail)
			local info = Rarity.get(def.rarity)
			expect.equal(def.visuals.trail ~= nil, info.hasTrail)
			if def.visuals.trail ~= nil then
				local style = RarityStyle.trail(def.visuals.trail)
				assert(style ~= nil, row.id .. " trail has no RarityStyle entry")
				expect.equal(type(Strings.resolve(style.nameKey)), "string")
			end
		end
	end)

	-- Spec phase 5 (user decision 2026-10-11): "Ultimates are reserved for Epic and Exclusive squishies" (design:
	-- fp.js:576); Dragon keeps Dragon Rush and the four Epics get the design's ultimates (ults.js:3-6).
	t.test("Dragon and the four Epics have ultimates, each in Config.Abilities; only Epics and Exclusives", function()
		local count = 0
		for _, row in EXPECTED do
			local def = Catalog.get(row.id)
			expect.equal(def.ultimateId, row.ultimate)
			if def.ultimateId ~= nil then
				count += 1
				expect.truthy(Config.Abilities[def.ultimateId] ~= nil)
				expect.truthy(def.rarity == "Epic" or def.rarity == "Exclusive")
			end
		end
		expect.equal(count, 5)
		for _, def in Catalog.byRarity("Epic") do
			expect.truthy(def.ultimateId ~= nil)
		end
	end)

	t.test("elimination effects match DESIGN §4.2", function()
		for _, row in EXPECTED do
			expect.equal(Catalog.get(row.id).eliminationEffectId, row.elimination)
		end
	end)

	t.test("every nameKey exists in Strings", function()
		local missing = {}
		for _, def in Catalog.list() do
			local text = Strings.resolve(def.nameKey)
			if type(text) ~= "string" or text == "" then
				table.insert(missing, def.id .. " -> " .. tostring(def.nameKey))
			end
		end
		if #missing > 0 then
			error("missing Strings keys: " .. table.concat(missing, ", "))
		end
	end)

	t.test("every blueprintId exists in Art/SquishyBlueprints", function()
		local art = if t.Shared then t.Shared:FindFirstChild("Art") else nil
		local module = if art then art:FindFirstChild("SquishyBlueprints") else nil
		assert(module ~= nil, "Shared/Art/SquishyBlueprints is missing")
		local blueprints = t.requireShared("Art/SquishyBlueprints")
		local missing = {}
		for _, def in Catalog.list() do
			if type(def.blueprintId) ~= "string" or not hasBlueprint(blueprints, def.blueprintId) then
				table.insert(missing, def.id .. " -> " .. tostring(def.blueprintId))
			end
		end
		if #missing > 0 then
			error("blueprints not found: " .. table.concat(missing, ", "))
		end
	end)

	t.test("every throw stat is inside Config.Combat.Bands", function()
		for _, def in Catalog.list() do
			for stat, band in Config.Combat.Bands do
				local value = def.throw[stat]
				if type(value) ~= "number" or value < band.min or value > band.max then
					error(
						string.format(
							"%s throw.%s = %s outside %s-%s",
							def.id,
							stat,
							tostring(value),
							band.min,
							band.max
						)
					)
				end
			end
		end
	end)

	t.test("Config.validate reports no Catalog or Rarity problem", function()
		local found = {}
		for _, problem in Config.validate() do
			local prefix = string.match(problem, "^%a+")
			if prefix == "Catalog" or prefix == "Rarity" or string.find(problem, "Catalog.", 1, true) then
				table.insert(found, problem)
			end
		end
		if #found > 0 then
			error(table.concat(found, "\n"))
		end
	end)

	-- Catalog: API (§2.2) -------------------------------------------------------------------------------------------

	t.test("get returns the def of every id and nil for anything else", function()
		for _, row in EXPECTED do
			expect.equal(Catalog.get(row.id).id, row.id)
		end
		for _, bad in { "unknown", "", "Kitty_Bread", "dragon_rush" } do
			expect.equal(Catalog.get(bad), nil)
		end
		expect.equal(Catalog.get(nil), nil)
		expect.equal(Catalog.get(5), nil)
		expect.equal(Catalog.get({}), nil)
	end)

	t.test("isValidId accepts exactly the catalog ids", function()
		for _, row in EXPECTED do
			expect.truthy(Catalog.isValidId(row.id))
		end
		for _, bad in { "unknown", "", "KITTY_BREAD", "gift_box", " toast" } do
			expect.falsy(Catalog.isValidId(bad))
		end
		expect.falsy(Catalog.isValidId(nil))
		expect.falsy(Catalog.isValidId(1))
		expect.falsy(Catalog.isValidId(true))
	end)

	t.test("starterId is kitty_bread, a Common that is not sold", function()
		local id = Catalog.starterId()
		expect.equal(id, "kitty_bread")
		local def = Catalog.get(id)
		expect.equal(def.rarity, "Common")
		expect.equal(def.shopPrice, nil)
	end)

	t.test("byRarity returns each rarity's squishies in catalog order", function()
		for _, rarity in RARITY_ORDER do
			expect.equal(ids(Catalog.byRarity(rarity)), idsOfRarity(rarity))
		end
		expect.equal(#Catalog.byRarity("Legendary"), 0)
		expect.equal(#Catalog.byRarity(nil), 0)
	end)

	t.test("getPower follows Config.Economy.SquishyPower (1 / 4 / 16 / 64) unless overridden", function()
		local byRarity = { Common = 1, Uncommon = 4, Epic = 16, Exclusive = 64 } -- spec 2026-10-12 §6
		for _, row in EXPECTED do
			local def = Catalog.get(row.id)
			expect.equal(Catalog.getPower(row.id), if def.power ~= nil then def.power else byRarity[row.rarity])
		end
		expect.equal(Catalog.getPower("unknown"), 0)
		expect.equal(Catalog.getPower(nil), 0)
	end)

	t.test("catalog entries cannot be changed", function()
		local def = Catalog.get("dragon")
		expect.throws(function()
			def.throw.speed = 200
		end)
		expect.throws(function()
			def.shopPrice = 1
		end)
		expect.equal(Catalog.get("dragon").throw.speed, 92)
	end)

	t.test("list and byRarity return new arrays", function()
		local list = Catalog.list()
		table.remove(list)
		expect.equal(#Catalog.list(), #EXPECTED)
		local commons = Catalog.byRarity("Common")
		table.clear(commons)
		expect.equal(#Catalog.byRarity("Common"), 5)
	end)

	-- Rarity (§2.2, §4.3, §6.5) --------------------------------------------------------------------------------------

	t.test("Rarity.ORDER is Common, Uncommon, Epic, Exclusive", function()
		expect.deepEqual(Rarity.ORDER, RARITY_ORDER)
		expect.truthy(table.isfrozen(Rarity.ORDER))
	end)

	t.test("Rarity.index and Rarity.compare follow ORDER", function()
		for position, rarity in RARITY_ORDER do
			expect.equal(Rarity.index(rarity), position)
			expect.truthy(Rarity.isValid(rarity))
		end
		expect.equal(Rarity.index("Legendary"), nil)
		expect.equal(Rarity.index(nil), nil)
		expect.falsy(Rarity.isValid("common"))
		expect.truthy(Rarity.compare("Common", "Epic") < 0)
		expect.truthy(Rarity.compare("Exclusive", "Uncommon") > 0)
		expect.equal(Rarity.compare("Epic", "Epic"), 0)
		expect.truthy(Rarity.compare("Legendary", "Common") < 0) -- not a rarity: ranks below Common
	end)

	t.test("Rarity.get: Strings name and label keys, pips 1-4, a trail for every rarity above Common", function()
		for position, rarity in RARITY_ORDER do
			local info = Rarity.get(rarity)
			assert(info ~= nil, rarity .. " has no info")
			expect.equal(info.rarity, rarity)
			expect.equal(type(Strings.resolve(info.nameKey)), "string")
			expect.equal(type(Strings.resolve(info.labelKey)), "string")
			expect.equal(info.pips, RARITY_STYLE[rarity].pips)
			expect.equal(info.hasTrail, position > 1)
		end
		expect.equal(Strings.resolve(Rarity.get("Epic").nameKey), "Epic")
		expect.equal(Rarity.get("Legendary"), nil)
	end)

	-- RarityStyle (§4.3) ----------------------------------------------------------------------------------------------

	t.test("rarity colours, pips, label colours and card frames match DESIGN §4.3", function()
		for _, rarity in RARITY_ORDER do
			local want = RARITY_STYLE[rarity]
			local style = RarityStyle.get(rarity)
			assert(style ~= nil, rarity .. " has no style")
			expect.truthy(sameColor(style.color, want.color))
			expect.equal(style.pips, want.pips)
			expect.equal(style.pipShape, want.shape)
			expect.equal(style.labelTextColor, Palette[want.label])
			expect.equal(style.card.strokePx, want.stroke)
		end
		expect.truthy(sameColor(RarityStyle.get("Epic").trailTint, "#B58CFF"))
		expect.truthy(RarityStyle.get("Epic").card.gradient ~= nil)
		local exclusive = RarityStyle.get("Exclusive").card
		expect.equal(exclusive.gradient.shimmerDegPerSecond, 45)
		expect.equal(type(Strings.resolve(exclusive.badgeKey)), "string")
		expect.equal(RarityStyle.get("Legendary"), nil)
	end)

	t.test("every rarity label reaches 4.5:1 contrast on its colour (DESIGN figures within 0.1)", function()
		for _, rarity in RARITY_ORDER do
			local style = RarityStyle.get(rarity)
			local ratio = contrast(style.labelTextColor, style.color)
			expect.truthy(ratio >= MIN_TEXT_CONTRAST)
			expect.near(ratio, RARITY_STYLE[rarity].contrast, 0.1)
		end
	end)

	t.test("default world trail per rarity: none, ribbon, twin ribbon, comet", function()
		expect.equal(RarityStyle.get("Common").trail, nil)
		expect.equal(RarityStyle.get("Uncommon").trail, "ribbon")
		expect.equal(RarityStyle.get("Epic").trail, "twinRibbon")
		expect.equal(RarityStyle.get("Exclusive").trail, "comet")
	end)

	t.test("trail styles carry the DESIGN §4.3 numbers", function()
		local ribbon = RarityStyle.trail("ribbon")
		expect.equal(#ribbon.offsets, 1)
		expect.near(ribbon.lifetime, 0.25)
		expect.near(ribbon.width, 0.6)
		expect.near(ribbon.widthScaleTo, 0)
		expect.near(ribbon.transparencyFrom, 0.25)
		expect.near(ribbon.transparencyTo, 1)
		expect.truthy(ribbon.startsWithAccent)
		expect.truthy(sameColor(ribbon.colors[#ribbon.colors], "#FFFFFF"))
		expect.equal(ribbon.faceCamera, true)
		expect.equal(ribbon.maxLength, 10)
		expect.near(ribbon.lightEmission, 0.2)

		local twin = RarityStyle.trail("twinRibbon")
		expect.deepEqual(twin.offsets, { -0.3, 0.3 })
		expect.near(twin.lifetime, 0.32)
		expect.truthy(twin.startsWithAccent)
		expect.truthy(sameColor(twin.colors[#twin.colors], "#B58CFF"))
		expect.equal(twin.maxLength, 12)
		expect.equal(twin.emitter.rate, 20)
		expect.near(twin.emitter.lifetimeMin, 0.25)
		expect.near(twin.emitter.lifetimeMax, 0.35)
		expect.equal(twin.emitter.maxLive, 8)

		for _, kind in { "comet", "ember" } do
			local comet = RarityStyle.trail(kind)
			expect.near(comet.lifetime, 0.4)
			expect.falsy(comet.startsWithAccent)
			expect.equal(#comet.colors, 3)
			expect.truthy(sameColor(comet.colors[1], "#FF4F8B"))
			expect.truthy(sameColor(comet.colors[2], "#FF9F1C"))
			expect.truthy(sameColor(comet.colors[3], "#FFD86B"))
			expect.equal(comet.maxLength, 14)
			expect.near(comet.lightEmission, 0.5)
			expect.equal(comet.emitter.rate, 30)
			expect.equal(comet.emitter.maxLive, 12)
		end
		expect.equal(RarityStyle.trail("comet").emitter.texture, "sparkles")
		expect.equal(RarityStyle.trail("ember").emitter.texture, "fire") -- Dragon uses embers
		expect.equal(RarityStyle.trail("laser"), nil)
	end)

	t.test("trail names and emitter textures resolve", function()
		for _, kind in { "ribbon", "twinRibbon", "comet", "ember" } do
			local style = RarityStyle.trail(kind)
			expect.equal(style.kind, kind)
			expect.equal(type(Strings.resolve(style.nameKey)), "string")
			if style.emitter then
				expect.equal(type(Config.Vfx.Textures[style.emitter.texture]), "string")
			end
		end
	end)

	t.test("trailColorSequence puts the accent first for ribbons and uses fixed stops for comets", function()
		local accent = Color3.fromHex("#FFD86B")
		local ribbon = RarityStyle.trailColorSequence("ribbon", accent)
		local points = ribbon.Keypoints
		expect.equal(points[1].Time, 0)
		expect.equal(points[#points].Time, 1)
		expect.truthy(sameColor(points[1].Value, "#FFD86B"))
		expect.truthy(sameColor(points[#points].Value, "#FFFFFF"))

		local comet = RarityStyle.trailColorSequence("comet", accent).Keypoints
		expect.equal(#comet, 3)
		expect.near(comet[2].Time, 0.5, 1e-6)
		expect.truthy(sameColor(comet[1].Value, "#FF4F8B"))
		expect.equal(RarityStyle.trailColorSequence("laser", accent), nil)
	end)

	-- Palette (§7.2) --------------------------------------------------------------------------------------------------

	t.test("palette tokens and reserved colours match DESIGN §7.2", function()
		for name, hex in PALETTE_HEX do
			if not sameColor(Palette[name], hex) then
				error(string.format("Palette.%s is %s, DESIGN says %s", name, tostring(Palette[name]), hex))
			end
		end
		expect.deepEqual(Palette.RESERVED, RESERVED)
	end)

	t.test("Ink on Cream reaches the DESIGN 12.3:1 contrast", function()
		expect.near(contrast(Palette.Ink, Palette.Cream), 12.3, 0.1)
	end)

	t.test("no rarity colour reuses a reserved gameplay colour", function()
		for _, rarity in RARITY_ORDER do
			local color = RarityStyle.get(rarity).color
			for _, name in RESERVED do
				if color == Palette[name] then
					error(rarity .. " uses the reserved colour " .. name)
				end
			end
		end
	end)
end
