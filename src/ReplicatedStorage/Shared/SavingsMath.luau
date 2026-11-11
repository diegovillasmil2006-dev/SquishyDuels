--!strict
-- SavingsMath (shared, pure). Big job item 8 (2026-11-10; the owner's "savings bar"; Diego drew none, so the rule is
-- Claude's with the LihFolk vault: "Progression Levels and Unlocks": every stage needs a near goal the player can see).
-- What the player's Coins are saved for = the CHEAPEST next thing Coins buy that lasts: the next pen spot
-- (PenMath.spotPrice) or the next step of a gear line (GearMath: held, platform, arm, armor). The bar is Coins / price.
-- No instances, no yields, no side effects.
--
-- API:
--   SavingsMath.goal(coins, pen?, gear?) -> Goal?: { kind = "pen" or a gear line, step = the spot or step to buy,
--                                           price, have = the Coins counted (never over the price), share 0..1,
--                                           ready = the Coins cover it }; nil when everything is bought (or neither a
--                                           pen nor a gear table is given). Equal prices: the pen spot first, then
--                                           GearMath.LINES' order.

local GearMath = require(script.Parent.GearMath)
local PenMath = require(script.Parent.PenMath)

export type Goal = {
	kind: string,
	step: number,
	price: number,
	have: number,
	share: number,
	ready: boolean,
}

local SavingsMath = {}

function SavingsMath.goal(coins: unknown, pen: any?, gear: any?): Goal?
	local have = if type(coins) == "number" and coins == coins then math.max(coins, 0) else 0
	local best: Goal? = nil
	local function offer(kind: string, step: number, price: number?)
		if price == nil or price ~= price or price <= 0 or (best ~= nil and price >= best.price) then
			return
		end
		best = {
			kind = kind,
			step = step,
			price = price,
			have = math.min(have, price),
			share = math.clamp(have / price, 0, 1),
			ready = have >= price,
		}
	end
	local spots = if type(pen) == "table" then pen.spots else nil
	if type(spots) == "number" then
		offer("pen", spots + 1, PenMath.spotPrice(spots + 1))
	end
	if type(gear) == "table" then
		for _, line in GearMath.LINES do
			local step = GearMath.steps(gear, line) + 1
			offer(line, step, GearMath.price(line, step))
		end
	end
	return best
end

return table.freeze(SavingsMath)
