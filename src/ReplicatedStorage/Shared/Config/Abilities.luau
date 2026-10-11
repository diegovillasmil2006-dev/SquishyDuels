--!strict
-- Config.Abilities: ultimates keyed by Catalog `ultimateId` (DESIGN §5.9). Shared, data only. All [P].
-- Dragon Rush is the only ability. Rules every ability must pass (checked by Config.validate()): telegraph >= 0.6 s,
-- minIntervalSeconds >= 20, a budget cost for PowerBudget, Strings for name, description and warnings, and a lane
-- sphere that stays above the floor (laneHeightAboveFloor > radius). The lane flies straight (gravity 0) through
-- ProjectileMath, like a throw.

export type Ability = {
	nameKey: string,
	descriptionKey: string,
	incomingKey: string, -- opponent banner during the telegraph
	readyKey: string, -- opponent chip when the caster's charge is full (§11.6)
	cancelKey: string, -- lane label when a hit on the caster cancels the telegraph (§9.10)
	chargeMax: number,
	startCharge: number,
	chargePerSecond: number, -- Active and SuddenDeath only
	chargePerHitLanded: number,
	chargePerLifeLost: number,
	minIntervalSeconds: number,
	telegraphSeconds: number,
	radius: number,
	laneHeightAboveFloor: number,
	speed: number,
	maxLength: number,
	recoverySeconds: number,
	cancelOnHitDuringTelegraph: boolean,
	refundOnCancel: number,
	livesCost: number,
	knockbackMultiplier: number,
	budgetCost: number,
	practiceCooldownSeconds: number,
	minHorizontalAim: number,
	originForwardStuds: number,
}

local Abilities = {
	dragon_rush = {
		nameKey = "ability.dragonRush.name",
		descriptionKey = "ability.dragonRush.description",
		incomingKey = "ability.dragonRush.incoming",
		readyKey = "ability.dragonRush.ready",
		cancelKey = "ability.interrupted",
		chargeMax = 100,
		startCharge = 0, -- every match
		chargePerSecond = 2.0, -- Active and SuddenDeath only
		chargePerHitLanded = 20, -- Dragon's normal throws
		chargePerLifeLost = 25, -- comeback help
		minIntervalSeconds = 20,
		telegraphSeconds = 0.9, -- caster rooted; lane + dragon head visible to both
		radius = 4.0, -- swept sphere radius = half the lane width
		laneHeightAboveFloor = 4.5, -- sphere spans floor+0.5 .. floor+8.5
		speed = 260, -- studs/s, no gravity
		maxLength = 110, -- capped by Geometry and Bounds
		recoverySeconds = 0.35, -- rooted after release
		cancelOnHitDuringTelegraph = true,
		refundOnCancel = 0.5, -- fraction of chargeMax refunded on cancel
		livesCost = 1,
		knockbackMultiplier = 1.5,
		budgetCost = 2.0, -- PowerBudget ultimateCost
		practiceCooldownSeconds = 10, -- practice range: no charge needed
		minHorizontalAim = 0.3, -- aimDir is flattened; its horizontal magnitude must reach this
		originForwardStuds = 2, -- O = (HRP.X, floorY + laneHeightAboveFloor, HRP.Z) + dir * originForwardStuds
	},
} :: { [string]: Ability }

return Abilities
