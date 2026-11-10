--!strict
-- Boxes: the box definitions and their odds (DESIGN §6.4, §6.10). Shared (server and client): BoxService and
-- Logic/BoxDraw draw from the same data the odds panel and the in-world board show, so the display always equals the
-- draw. Data only plus pure helpers; no instances, no yields.
--
-- Rules (§6.4): weights are integers that sum to exactly WeightTotal (10,000) per box, so a chance is weight / 100
-- with two exact decimals ("32.00"; no rounding disclaimer). Items are ordered arrays (draws and displays are
-- deterministic). Kitty Bread is in no box. Snack and Sweet are paid random items (Coins); the Treat Box is free-only
-- (day 7 of Daily Rewards), has no cost and can never be bought. Config.validate checks the sums, ids and the free box;
-- Pricing derives the shop price ceilings from these weights.
-- Pens3 phase 5 (copies): a box always gives a squishy (a copy when you own it), so isComplete is gone. Restricted
-- accounts (PolicyGateService: anything but "eligible") open the paid boxes in a fixed order instead of a random draw
-- (D1:235, V3:163): each paid box's `fixedCycle` items, built once from its weights by smooth weighted round-robin
-- (SIM sequenceOf, V4:248-252: every step adds each item's weight to its counter, takes the item with the highest
-- counter, a tie to the earlier item, and takes WeightTotal off it), so a rare item comes at its fair place and each
-- item comes as often as its weight says (rounded). The order repeats; profile.boxOrder[boxId] counts the opens.
--
-- API:
--   Boxes.WeightTotal                -> 10000
--   Boxes.List                       -> { BoxDef } (frozen, §6.4 order: snack, sweet, frosty, treat)
--   Boxes.get(id)                    -> BoxDef? (nil for an unknown id or a non-string)
--   Boxes.isOpenFor(boxId, biome)    -> boolean: the box has no zone, or `biome` (profile.highway.biome, the highest
--                                       highway biome reached) is at least its zone; false for an unknown box, and a
--                                       biome that is not a number counts as 1 (fail closed)
--   Boxes.list()                     -> { BoxDef } in list order (a new array each call; the defs are frozen)
--   Boxes.paidById                   -> { [boxId]: BoxDef } of the paid boxes only (frozen; BoxService opens only these)
--   Boxes.percentText(weight)        -> "32.00": weight / 100 with two decimals, integer math (no float rounding)
--   Boxes.odds(boxId)                -> { OddsRow } {id, weight, percent, text} in item order (empty for an unknown id)
--   Boxes.byRarity(boxId)            -> { RarityRow } {rarity, weight, percent, text}, rarity descending
--                                       (Snack: Rare 8.00 · Uncommon 16.00 · Common 76.00)
--   Boxes.totalText(boxId)           -> "100.00" (the sum of the weights), nil for an unknown id
--   Boxes.containing(squishyId)      -> { ContainingRow } {boxId, weight, percent, text, paid} in list order
--   Boxes.fixedItem(boxId, n)        -> string?: the squishy of open n + 1 in the box's fixed order (n = the opens so
--                                       far, a whole number >= 0; the order repeats every fixedCycle); nil for a free
--                                       or unknown box or a bad n. The server opens it, the box card shows it first.
--
-- Readings:
--   * Items are `{ id = "toast", weight = 2000 }` instead of DESIGN's positional `{"toast", 3200}` pairs (same order;
--     the weights are the spec 2026-10-12 §8 split) so strict types can describe them; Config.validate's box check
--     accepts both forms.
--   * `percent` (= weight / 100, a number) is the field DESIGN §2.2 names for odds rows; `text` is the exact display
--     string. Screens show `text` (never format `percent` themselves).
--   * Rows whose squishy is not in the Catalog are left out of byRarity (Config.validate reports such an item).

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Catalog = require(script.Parent.Catalog)
local Rarity = require(script.Parent.Rarity)

-- Types

export type BoxItem = { id: string, weight: number }

export type BoxDef = {
	id: string,
	nameKey: string, -- Strings key, "box.<id>.name"
	cost: number?, -- Coins; nil for the free-only box
	paid: boolean, -- a paid random item (§6.10): opened with Coins through BoxOpen
	freeOnly: boolean?, -- only granted for free (the day-7 Treat Box); never sold
	fixedCycle: number?, -- pens3 phase 5, paid boxes: the length of the fixed order restricted accounts open
	-- Plan "50 squishies" (zone boxes): opens once the player has reached this highway biome (profile.highway.biome,
	-- WorldLayout.Highway.biomes' order: 4 = Frozen Dessert Peaks); nil = always open.
	zone: number?,
	items: { BoxItem }, -- ordered; weights sum to WeightTotal
}

-- One row of the odds list (§6.10 #4).
export type OddsRow = { id: string, weight: number, percent: number, text: string }

-- One rarity of the "Chances by rarity" summary (§6.10 #2).
export type RarityRow = { rarity: string, weight: number, percent: number, text: string }

-- One box that contains a squishy (Inspect "How to get", the shop's "Shop squishies directly" filter).
export type ContainingRow = { boxId: string, weight: number, percent: number, text: string, paid: boolean }

-- Constants

local WEIGHT_TOTAL = 10000
local PERCENT_DIVISOR = 100

local function item(id: string, weight: number): BoxItem
	return { id = id, weight = weight }
end

-- §6.4, in order. Pens3 phase 5 (ECONOMY_V3:159-161; Snack = the Soft Box, Treat = the Royal Box): Soft 150K, the 4
-- Commons 19% each, Butter and Chocolate 8% each, Mochi Fox and Strawberry Frog 4% each (Rare since 2026-11-01,
-- phase 22); Sweet 450M, the 4 Epics 24.99% each and Dragon 0.04%; Royal (free on day 7, never sold) Commons 14%,
-- Butter and Chocolate 9%, Mochi Fox and Strawberry Frog 6%, Epics 3.5% each. New items sit right after their
-- same-rarity siblings and Dragon stays last.
-- Series 01 (2026-11-10, plan "50 squishies" step 3): the Soft Box keeps its rarity totals (Commons 76%, Uncommons
-- 16%, Rares 8%) as closely as one weight per rarity allows: 6 Commons 12.66% each (75.96%), 3 Uncommons 5.32%
-- (15.96%), 4 Rares 2.02% (8.08%); the Sweet Box gives Cosmo the Dragon's 0.04% (Dragon stays last) and its Epics
-- 24.98% each. Lower weights only raise the old shop price ceilings.
local LIST: { BoxDef } = {
	{
		id = "snack",
		nameKey = "box.snack.name",
		cost = 150_000,
		paid = true,
		fixedCycle = 150, -- each Common 19 times, each Uncommon 8, each Rare 3 (the first Rare, Mochi Fox, at box 16)
		items = {
			item("toast", 1266),
			item("banana", 1266),
			item("boba_bear", 1266),
			item("pancake_pup", 1266),
			item("berry_jelly", 1266),
			item("peachy", 1266),
			item("butter", 532),
			item("chocolate", 532),
			item("grapey", 532),
			item("mochi_fox", 202),
			item("strawberry_frog", 202),
			item("bao_buddy", 202),
			item("pando", 202),
		},
	},
	{
		id = "sweet",
		nameKey = "box.sweet.name",
		cost = 450_000_000,
		paid = true,
		fixedCycle = 2500, -- each Epic 624 or 625 times, Cosmo once (box 417), the Dragon once (box 834)
		items = {
			item("bird", 2498),
			item("donut", 2498),
			item("cloud_bunny", 2498),
			item("cupcake_axolotl", 2498),
			item("cosmo", 4),
			item("dragon", 4),
		},
	},
	-- Frosty Box (owner 2026-11-10 "lets build everything"; plan "50 squishies" step 4, money check 2026-11-01): the
	-- first zone box, 20B, opened once the player reaches Frozen Dessert Peaks (zone 4). 2 Commons 30% each, 2 Uncommons
	-- 13% each, the Rare 10%, the Epic 3.9%, the Legendary (Exclusive) 0.1%.
	{
		id = "frosty",
		nameKey = "box.frosty.name",
		cost = 20_000_000_000,
		paid = true,
		zone = 4,
		fixedCycle = 1000, -- each Common 300 times, each Uncommon 130, the Rare 100, the Epic 39, Parfait Wyvern once
		items = {
			item("cone_cub", 3000),
			item("slushy_seal", 3000),
			item("ice_pop_beaver", 1300),
			item("mint_chip_mouse", 1300),
			item("sundae_manatee", 1000),
			item("gelato_narwhal", 390),
			item("parfait_wyvern", 10),
		},
	},
	-- Plan "50 squishies" step 5 (2026-11-10): opens from Lava Volcano (biome 5) on; 30 / 30 / 13 / 13 / 10 / 3.9 / 0.1 %.
	{
		id = "lava",
		nameKey = "box.lava.name",
		cost = 600_000_000_000,
		paid = true,
		zone = 5,
		fixedCycle = 1000, -- each Common 300 times, each Uncommon 130, the Rare 100, the Epic 39, Mallow Behemoth once
		items = {
			item("cocoa_quokka", 3000),
			item("cinder_bun", 3000),
			item("smore_skunk", 1300),
			item("cayenne_kiwi", 1300),
			item("pizza_pangolin", 1000),
			item("lava_cake_hippo", 390),
			item("mallow_behemoth", 10),
		},
	},
	{
		id = "treat",
		nameKey = "box.treat.name",
		cost = nil,
		paid = false,
		freeOnly = true,
		items = {
			item("toast", 1400),
			item("banana", 1400),
			item("boba_bear", 1400),
			item("pancake_pup", 1400),
			item("butter", 900),
			item("chocolate", 900),
			item("mochi_fox", 600),
			item("strawberry_frog", 600),
			item("bird", 350),
			item("donut", 350),
			item("cloud_bunny", 350),
			item("cupcake_axolotl", 350),
		},
	},
}

-- The box's fixed order (see the header): `count` squishy ids by smooth weighted round-robin over its weights.
local function roundRobin(items: { BoxItem }, count: number): { string }
	local counters = table.create(#items, 0)
	local total = 0
	for _, entry in items do
		total += entry.weight
	end
	local order = table.create(count)
	for _ = 1, count do
		local best = 1
		for index, entry in items do
			counters[index] += entry.weight
			if counters[index] > counters[best] then
				best = index
			end
		end
		counters[best] -= total
		table.insert(order, items[best].id)
	end
	return order
end

local BY_ID: { [string]: BoxDef } = {}
local PAID_BY_ID: { [string]: BoxDef } = {}
local FIXED_ORDERS: { [string]: { string } } = {}
for _, box in LIST do
	BY_ID[box.id] = box
	if box.paid then
		PAID_BY_ID[box.id] = box
	end
	local cycle = box.fixedCycle
	if box.paid and type(cycle) == "number" and cycle >= 1 and math.floor(cycle) == cycle then
		FIXED_ORDERS[box.id] = table.freeze(roundRobin(box.items, cycle))
	end
	for _, entry in box.items do
		table.freeze(entry)
	end
	table.freeze(box.items)
	table.freeze(box)
end
table.freeze(LIST)
table.freeze(BY_ID)
table.freeze(PAID_BY_ID)
table.freeze(FIXED_ORDERS)

-- Module table

local Boxes = {
	WeightTotal = WEIGHT_TOTAL,
	List = LIST,
	paidById = PAID_BY_ID,
}

-- Private

-- A whole number >= 0 (anything else counts as 0).
local function whole(n: unknown): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n < 0 then
		return 0
	end
	return math.floor(n)
end

-- Public

function Boxes.get(id: unknown): BoxDef?
	if type(id) ~= "string" then
		return nil
	end
	return BY_ID[id]
end

function Boxes.list(): { BoxDef }
	return table.clone(LIST)
end

function Boxes.isOpenFor(boxId: unknown, biome: unknown): boolean
	local box = Boxes.get(boxId)
	if box == nil then
		return false
	end
	local zone = box.zone
	return zone == nil or (if type(biome) == "number" and biome == biome then biome else 1) >= zone
end

-- weight / 100 with exactly two decimals, from integers only: 3200 -> "32.00", 300 -> "3.00", 10000 -> "100.00",
-- 1 -> "0.01". A fraction or a negative/non-finite weight counts as its floor / 0.
function Boxes.percentText(weight: number): string
	local w = whole(weight)
	return string.format("%d.%02d", w // PERCENT_DIVISOR, w % PERCENT_DIVISOR)
end

function Boxes.odds(boxId: string): { OddsRow }
	local box = Boxes.get(boxId)
	local rows: { OddsRow } = {}
	if box == nil then
		return rows
	end
	for _, entry in box.items do
		table.insert(rows, {
			id = entry.id,
			weight = entry.weight,
			percent = entry.weight / PERCENT_DIVISOR,
			text = Boxes.percentText(entry.weight),
		})
	end
	return rows
end

function Boxes.byRarity(boxId: string): { RarityRow }
	local box = Boxes.get(boxId)
	local rows: { RarityRow } = {}
	if box == nil then
		return rows
	end
	local sums: { [string]: number } = {}
	for _, entry in box.items do
		local def = Catalog.get(entry.id)
		if def ~= nil then
			sums[def.rarity] = (sums[def.rarity] or 0) + entry.weight
		end
	end
	for index = #Rarity.ORDER, 1, -1 do
		local rarity = Rarity.ORDER[index]
		local weight = sums[rarity]
		if weight ~= nil then
			table.insert(rows, {
				rarity = rarity,
				weight = weight,
				percent = weight / PERCENT_DIVISOR,
				text = Boxes.percentText(weight),
			})
		end
	end
	return rows
end

function Boxes.totalText(boxId: string): string?
	local box = Boxes.get(boxId)
	if box == nil then
		return nil
	end
	local total = 0
	for _, entry in box.items do
		total += entry.weight
	end
	return Boxes.percentText(total)
end

function Boxes.fixedItem(boxId: unknown, n: unknown): string?
	local order = if type(boxId) == "string" then FIXED_ORDERS[boxId] else nil
	if order == nil or type(n) ~= "number" or n ~= n or n < 0 or n == math.huge or math.floor(n) ~= n then
		return nil
	end
	return order[n % #order + 1]
end

function Boxes.containing(squishyId: string): { ContainingRow }
	local rows: { ContainingRow } = {}
	for _, box in LIST do
		for _, entry in box.items do
			if entry.id == squishyId then
				table.insert(rows, {
					boxId = box.id,
					weight = entry.weight,
					percent = entry.weight / PERCENT_DIVISOR,
					text = Boxes.percentText(entry.weight),
					paid = box.paid,
				})
			end
		end
	end
	return rows
end

return table.freeze(Boxes)
