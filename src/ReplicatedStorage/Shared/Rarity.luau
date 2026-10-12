--!strict
-- Rarity: the four rarities in canonical order and the facts every system shares about them (DESIGN §0.3, §2.2,
-- §4.3). Shared (server and client). Rarity is always shown as label text + pips + colour; the colours, pip
-- shapes, card frames and trail styles are in Art/RarityStyle.
--
-- API:
--   Rarity.ORDER            {"Common", "Uncommon", "Epic", "Exclusive"} (lowest first, frozen)
--   Rarity.get(r)           -> Info? (nil for anything that is not a rarity)
--   Rarity.index(r)         -> number? (1 = Common .. 4 = Exclusive; nil for anything else)
--   Rarity.isValid(r)       -> boolean
--   Rarity.compare(a, b)    -> number: < 0 when a ranks below b, 0 when equal, > 0 when above. Anything that is
--                              not a rarity ranks below Common. Sort "rarity descending" with compare(x, y) > 0.
-- A duplicate box result's refund no longer depends on the rarity (spec 2026-10-12 §8): Pricing.duplicateRefund(boxId)
-- (Rarity.refund is gone).

local Types = require(script.Parent.Types)

-- Types

type Rarity = Types.Rarity

export type Info = {
	rarity: Rarity,
	nameKey: string, -- Strings key of the rarity name ("Epic")
	labelKey: string, -- Strings key of the card label ("EPIC")
	pips: number, -- pip count shown next to the label (§4.3); the pip shape is in Art/RarityStyle
	hasTrail: boolean, -- thrown squishies of this rarity draw a trail in the world (§4.3)
}

-- Constants

local ORDER: { Rarity } = { "Common", "Uncommon", "Epic", "Exclusive" }

local INFO: { [string]: Info } = {
	Common = {
		rarity = "Common",
		nameKey = "rarity.common.name",
		labelKey = "rarity.common.label",
		pips = 1,
		hasTrail = false, -- shadow disc and size give readability
	},
	Uncommon = {
		rarity = "Uncommon",
		nameKey = "rarity.uncommon.name",
		labelKey = "rarity.uncommon.label",
		pips = 2,
		hasTrail = true,
	},
	Epic = {
		rarity = "Epic",
		nameKey = "rarity.epic.name",
		labelKey = "rarity.epic.label",
		pips = 3,
		hasTrail = true,
	},
	Exclusive = {
		rarity = "Exclusive",
		nameKey = "rarity.exclusive.name",
		labelKey = "rarity.exclusive.label",
		pips = 4,
		hasTrail = true,
	},
}

local INDEX: { [string]: number } = {}
for position, rarity in ORDER do
	INDEX[rarity] = position
end

for _, info in INFO do
	table.freeze(info)
end
table.freeze(ORDER)
table.freeze(INFO)
table.freeze(INDEX)

-- Module table

local Rarity = {
	ORDER = ORDER,
}

-- Public

function Rarity.get(r: unknown): Info?
	if type(r) ~= "string" then
		return nil
	end
	return INFO[r]
end

function Rarity.index(r: unknown): number?
	if type(r) ~= "string" then
		return nil
	end
	return INDEX[r]
end

function Rarity.isValid(r: unknown): boolean
	return Rarity.index(r) ~= nil
end

function Rarity.compare(a: unknown, b: unknown): number
	return (Rarity.index(a) or 0) - (Rarity.index(b) or 0)
end

return table.freeze(Rarity)
