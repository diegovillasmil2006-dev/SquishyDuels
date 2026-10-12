--!strict
-- Pricing: the price rules that tie the shop to the boxes (DESIGN §6.5, §6.6). Shared (Config.validate, server
-- BoxService / ShopService / EconomyService, client screens). Pure; no instances, no yields.
--
-- API:
--   Pricing.ceiling(id)             -> number?: floor(min over the paid boxes containing `id` of cost × 10000 / weight),
--                                      the expected box spend for that squishy (spec 2026-10-12 §8: Commons 750,000,
--                                      Uncommons 3,000,000, Epics 4,504,504,504, Dragon 1,125,000,000,000); nil when
--                                      no paid box contains it (Kitty Bread). Config.validate checks every Catalog
--                                      shopPrice <= its ceiling (Roblox's "direct purchase priced on expected value"
--                                      alternative, §6.6).
--   Pricing.duplicateRefund(boxId)  -> Coins for a duplicate result of that box (spec 2026-10-12 §8):
--                                      floor(price × Config.Economy.DuplicateRefund.percent / 100) under DuplicatePolicy
--                                      "refund", where a free box (no cost: the day-7 Treat Box) counts the price of the
--                                      DuplicateRefund.freeBoxPriceOf box (Snack 37,500, Sweet 112,500,000, Treat
--                                      37,500); 0 for an unknown box, a non-string or another policy.
--
-- Integer math only: floor(a / b) of whole numbers is (a // b), and the floor of a minimum is the minimum of the
-- floors, so no float noise can move a ceiling or a refund by one Coin.

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Boxes = require(script.Parent.Boxes)
local Config = require(script.Parent.Config)

-- Constants

local PERCENT = 100

-- Module table

local Pricing = {}

-- Public

function Pricing.ceiling(id: string): number?
	local best: number? = nil
	for _, box in Boxes.list() do
		local cost = box.cost
		if box.paid and cost ~= nil then
			for _, entry in box.items do
				if entry.id == id and entry.weight > 0 then
					local limit = (cost * Boxes.WeightTotal) // entry.weight
					if best == nil or limit < best then
						best = limit
					end
				end
			end
		end
	end
	return best
end

function Pricing.duplicateRefund(boxId: unknown): number
	local economy = Config.Economy
	local box = Boxes.get(boxId)
	if economy.DuplicatePolicy ~= "refund" or box == nil then
		return 0
	end
	local refund = economy.DuplicateRefund
	local price = box.cost
	if price == nil then
		local priced = Boxes.get(refund.freeBoxPriceOf)
		price = if priced then priced.cost else nil
	end
	if type(price) ~= "number" then
		return 0
	end
	return (price * refund.percent) // PERCENT
end

return table.freeze(Pricing)
