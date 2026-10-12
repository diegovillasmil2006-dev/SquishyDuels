--!strict
-- Boxes: the three box definitions and their odds (DESIGN §6.4, §6.10). Shared (server and client): BoxService and
-- Logic/BoxDraw draw from the same data the odds panel and the in-world board show, so the display always equals the
-- draw. Data only plus pure helpers; no instances, no yields.
--
-- Rules (§6.4): weights are integers that sum to exactly WeightTotal (10,000) per box, so a chance is weight / 100
-- with two exact decimals ("32.00"; no rounding disclaimer). Items are ordered arrays (draws and displays are
-- deterministic). Kitty Bread is in no box. Snack and Sweet are paid random items (Coins); the Treat Box is free-only
-- (day 7 of Daily Rewards), has no cost and can never be bought. Config.validate checks the sums, ids, refunds and the
-- free box; Pricing derives the shop price ceilings from these weights.
--
-- API:
--   Boxes.WeightTotal                -> 10000
--   Boxes.List                       -> { BoxDef } (frozen, §6.4 order: snack, sweet, treat)
--   Boxes.get(id)                    -> BoxDef? (nil for an unknown id or a non-string)
--   Boxes.list()                     -> { BoxDef } in list order (a new array each call; the defs are frozen)
--   Boxes.paidById                   -> { [boxId]: BoxDef } of the paid boxes only (frozen; BoxService opens only these)
--   Boxes.percentText(weight)        -> "32.00": weight / 100 with two decimals, integer math (no float rounding)
--   Boxes.odds(boxId)                -> { OddsRow } {id, weight, percent, text} in item order (empty for an unknown id)
--   Boxes.byRarity(boxId)            -> { RarityRow } {rarity, weight, percent, text}, rarity descending
--                                       (Snack: Uncommon 20.00 · Common 80.00)
--   Boxes.totalText(boxId)           -> "100.00" (the sum of the weights), nil for an unknown id
--   Boxes.isComplete(boxId, owned)   -> true when every item of the box is a key of `owned` (profile.owned); false
--                                       for an unknown or empty box. BoxService refuses an open with box.complete while
--                                       Config.Economy.AllowOpenWhenComplete is false (§6.4).
--   Boxes.containing(squishyId)      -> { ContainingRow } {boxId, weight, percent, text, paid} in list order
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

-- §6.4, in order. Spec 2026-10-12 §8 (squishy prices now far apart, so each box covers a narrower range): Snack 150K,
-- Commons 80% (20% each) and Uncommons 20% (5% each), Epics left it; Sweet 450M, Uncommons 60% (15% each), Epics 39.96%
-- (9.99% each) and Dragon 0.04%; Treat unchanged (Commons 56%, Uncommons 34%, Epics 10%). A rarity's share is split
-- equally across its items (spec 2026-10-09 §3.3); new items sit right after their same-rarity siblings and Dragon
-- stays last.
local LIST: { BoxDef } = {
	{
		id = "snack",
		nameKey = "box.snack.name",
		cost = 150_000,
		paid = true,
		items = {
			item("toast", 2000),
			item("banana", 2000),
			item("boba_bear", 2000),
			item("pancake_pup", 2000),
			item("butter", 500),
			item("chocolate", 500),
			item("mochi_fox", 500),
			item("strawberry_frog", 500),
		},
	},
	{
		id = "sweet",
		nameKey = "box.sweet.name",
		cost = 450_000_000,
		paid = true,
		items = {
			item("butter", 1500),
			item("chocolate", 1500),
			item("mochi_fox", 1500),
			item("strawberry_frog", 1500),
			item("bird", 999),
			item("donut", 999),
			item("cloud_bunny", 999),
			item("cupcake_axolotl", 999),
			item("dragon", 4),
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
			item("butter", 850),
			item("chocolate", 850),
			item("mochi_fox", 850),
			item("strawberry_frog", 850),
			item("bird", 250),
			item("donut", 250),
			item("cloud_bunny", 250),
			item("cupcake_axolotl", 250),
		},
	},
}

local BY_ID: { [string]: BoxDef } = {}
local PAID_BY_ID: { [string]: BoxDef } = {}
for _, box in LIST do
	BY_ID[box.id] = box
	if box.paid then
		PAID_BY_ID[box.id] = box
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

function Boxes.isComplete(boxId: string, owned: { [string]: any }): boolean
	local box = Boxes.get(boxId)
	if box == nil or #box.items == 0 or type(owned) ~= "table" then
		return false
	end
	for _, entry in box.items do
		if owned[entry.id] == nil then
			return false
		end
	end
	return true
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
