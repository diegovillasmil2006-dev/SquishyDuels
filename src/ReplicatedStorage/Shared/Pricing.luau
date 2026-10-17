--!strict
-- Pricing: the price rules that tie the shop to the boxes (DESIGN §6.5, §6.6). Shared (Config.validate, server
-- ShopService, client screens). Pure; no instances, no yields.
--
-- API:
--   Pricing.ceiling(id)             -> number?: floor(min over the paid boxes containing `id` of cost × 10000 / weight),
--                                      the expected box spend for that squishy (pens3 phase 5: Commons 789,473, Butter
--                                      and Chocolate 1,875,000, Mochi Fox and Strawberry Frog 3,750,000, Epics
--                                      1,800,720,288, Dragon 1,125,000,000,000); nil when no paid box contains it
--                                      (Kitty Bread). Config.validate checks every Catalog shopPrice <= its ceiling
--                                      (Roblox's "direct purchase priced on expected value" alternative, §6.6).
--   Pricing.shopPrice(id, owned)    -> number?: what the shop charges for `id` now (pens3 phase 5, D1:202): the Welcome
--                                      price (Config.Economy.Pen.welcomePrice[rarity], Commons 3,000) while `owned`
--                                      (profile.owned) has no entry for it, else the Catalog shopPrice; nil when it is
--                                      not sold. `owned` that is not a table pays the full price (fail closed).
--                                      Config/ValidatePen keeps every Welcome price at or below the shopPrice.
-- Pens3 phase 5: copies replaced the duplicate refund (Pricing.duplicateRefund is gone).
--
-- Integer math only: floor(a / b) of whole numbers is (a // b), and the floor of a minimum is the minimum of the
-- floors, so no float noise can move a ceiling by one Coin.

-- Requires (relative, so a test's cloned Shared folder uses its own copies)

local Boxes = require(script.Parent.Boxes)
local Catalog = require(script.Parent.Catalog)
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

function Pricing.shopPrice(id: unknown, owned: unknown): number?
	local def = Catalog.get(id)
	local price = if def then def.shopPrice else nil
	if def == nil or price == nil then
		return nil
	end
	local welcome = Config.Economy.Pen.welcomePrice[def.rarity]
	if welcome ~= nil and type(owned) == "table" and (owned :: any)[def.id] == nil then
		return welcome
	end
	return price
end

return table.freeze(Pricing)
