--!strict
-- HeroRigs (client only; no instances, connections or clock reads). Squishy overhaul spec 2026-10-09 §3.2 detail
-- levels and §5: the "hero" rigs that animate outside the held models, the Inspect model (InspectController) and the
-- box reveal's model (its Anim/IdleRig), so the rig allocator (HeldSquishyController) counts them against
-- Config.Vfx.Budgets (heroRigs / heroRigsLow inside deformingRigs / deformingRigsLow) and gives the held models only
-- what is left.
--   HeroRigs.set(owner, live)   owner = the table that steps the rig (the Inspect session, the reveal's IdleRig); true
--                               counts it once however often it is said, false frees it
--   HeroRigs.count() -> number  the owners holding a hero rig now
-- Owners are weak keys: an owner dropped without set(owner, false) stops counting once it is collected.

-- Module table

local HeroRigs = {}

-- Private

local live: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- Public

function HeroRigs.set(owner: any, on: boolean)
	if on then
		live[owner] = true
	else
		live[owner] = nil
	end
end

function HeroRigs.count(): number
	local n = 0
	for _ in live do
		n += 1
	end
	return n
end

return HeroRigs
