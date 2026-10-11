--!strict
-- Pricing: the price rules that tie the shop to the boxes (DESIGN §6.5, §6.6). Shared (Config.validate, server
-- BoxService / ShopService, client screens). Pure; no instances, no yields.
--
-- API:
--   Pricing.ceiling(id)            -> number?: floor(min over the paid boxes containing `id` of cost × 10000 / weight),
--                                     the expected box spend for that squishy (with 14 squishies, spec 2026-10-09:
--                                     Commons 2500, Uncommons 5333, Epics 15789, Dragon 37500); nil when no paid box
--                                     contains it (Kitty Bread). Config.validate checks every Catalog shopPrice <= its
--                                     ceiling (Roblox's "direct purchase priced on expected value" alternative, §6.6).
--   Pricing.duplicateRefund(rarity) -> Coins for a duplicate box result: Config.Economy.DuplicateRefund[rarity] under
--                                     DuplicatePolicy "refund", else 0 (also 0 for anything that is not a rarity).
--
-- Integer math only: floor(a / b) of whole numbers is (a // b), and the floor of a minimum is the minimum of the
-- floors, so no float noise can move a ceiling by one Coin.

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Boxes = require(script.Parent.Boxes)
local Config = require(script.Parent.Config)

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

function Pricing.duplicateRefund(rarity: string): number
	local economy = Config.Economy
	if economy.DuplicatePolicy ~= "refund" or type(rarity) ~= "string" then
		return 0
	end
	local refund = economy.DuplicateRefund[rarity]
	return if type(refund) == "number" then refund else 0
end

return table.freeze(Pricing)
