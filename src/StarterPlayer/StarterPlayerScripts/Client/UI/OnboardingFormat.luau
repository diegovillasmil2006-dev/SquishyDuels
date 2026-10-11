--!strict
-- OnboardingFormat (client only, pure). DESIGN §11.8 (onboarding card, Config/Onboarding), §6.10 (eligible vs restricted
-- or unknown players), §6.4 / §6.6 (the first box price, the cheapest shop price), §11.7 (input kinds). What the
-- onboarding tip card shows, as plain data. Onboarding never pays Coins.
--   currentStep(done, unavailable?)   the lowest Config.Onboarding step not in `done` (steps complete in any order)
--                            and not unavailable, or nil
--   isComplete(done, unavailable?)    every available step done
--   isEligible(policy)       paid random boxes allowed: only "eligible" (checking / unknown / restricted fail closed)
--   goal(policy)             the Coins goal of the firstBox step: Boxes.get("snack").cost when eligible, else the
--                            cheapest Catalog shopPrice (§11.8 "{coins}/400" / "{coins}/1,200")
--   squeezeHint(input)       onboarding.squeezeHint.<keyboard | touch | gamepad> (spec 2026-10-11: "Click or press E",
--                            "Tap the screen", "Press X")
--   guidance(step, policy)   (waypoint, pulse): a WorldLayout.waypoint name ("giftBox" or "shop", "duel") or a
--                            HudController.element name ("squishies": the equip and inspect steps, since spec
--                            2026-10-11 Inspect is reached through the Squishies list); the squeeze step has neither
--   text(step, ctx)          the step's text with {starterName}, {squeezeHint}, {coins}/{goal} filled in; restricted or
--                            unknown players get the step's restrictedTextKey (onboarding.firstBoxShop)
--   visible(ctx) / model(ctx) the card, or nil when hidden: shown only for a ready profile that has not skipped and has
--                            a step left. Replay mode (ctx.replay = the steps done in this local replay) ignores the saved
--                            flags (done and skipped); the saved state never changes for a replay.
-- Readings: the welcome card has the one [Got it] button and no skip link; every other card has the one "Skip
-- tutorial" link (§11.8). {coins} is capped at the goal, so the line reads as progress ("400/400 Coins"). A wrong-shaped
-- saved state counts as nothing done and not skipped (the server owns the real flags). A step whose screen does not
-- exist yet (ctx.unavailable: the Inspect step until Part 6 registers "inspect") is passed over, so the card never
-- waits on a button that is not there (the §7.6 rule for stands, applied to the card).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)

-- Types

export type InputKind = "keyboard" | "touch" | "gamepad"

export type Step = {
	id: string,
	textKey: string,
	restrictedTextKey: string?,
	recordedBy: string,
	guidance: string,
}

export type Context = {
	onboarding: any?, -- the profile's onboarding state {v, done, skipped}
	ready: boolean, -- the profile is ready (not loading, offline or read-only)
	replay: { [string]: boolean }?, -- replay mode: the steps done in this local replay (saved flags ignored)
	policy: string?, -- StateDelta.policy
	coins: number?,
	input: InputKind?,
	unavailable: { [string]: boolean }?, -- step ids passed over (their screen is not registered)
}

export type Model = {
	stepId: string,
	text: string,
	gotIt: boolean, -- the welcome card's [Got it]
	skip: boolean, -- the "Skip tutorial" link
	waypoint: string?, -- WorldLayout.waypoint name
	pulse: string?, -- HudController.element name
}

-- Constants

local ONBOARDING = Config.Onboarding
local STEPS: { Step } = ONBOARDING.Steps :: any
local WELCOME = "welcome"
local ELIGIBLE = "eligible"
local FIRST_BOX_ID = "snack" -- the first paid box (§11.8 "{coins}/400"; the SD_BoxStand BoxId)
local DEFAULT_INPUT: InputKind = "keyboard"
-- Config.Onboarding guidance -> (waypoint, pulse). The box stand step points eligible players to the Gift Box counter
-- and everyone else to the Shop (§11.8 "waypoint to the box stand (or shop)"). The squeeze step's waypointMat maps to
-- no waypoint: its text says squeeze anywhere (spec 2026-10-11 §5), so it sends no one to a mat.
local WAYPOINTS: { [string]: string } = {
	waypointBoxStand = "giftBox",
	waypointPodium = "duel",
}
local SHOP_WAYPOINT = "shop"
local PULSES: { [string]: string } = {
	pulseSquishies = "squishies",
}

-- Module table

local OnboardingFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The saved done set as booleans only (a wrong shape = nothing done).
local function savedDone(onboarding: any): { [string]: boolean }
	local done: { [string]: boolean } = {}
	if type(onboarding) == "table" and type(onboarding.done) == "table" then
		for id, value in onboarding.done do
			if type(id) == "string" and value == true then
				done[id] = true
			end
		end
	end
	return done
end

local function doneSet(ctx: Context): { [string]: boolean }
	if ctx.replay ~= nil then
		return ctx.replay
	end
	return savedDone(ctx.onboarding)
end

local function skipped(ctx: Context): boolean
	if ctx.replay ~= nil then
		return false
	end
	local onboarding = ctx.onboarding
	return type(onboarding) == "table" and onboarding.skipped == true
end

local function cheapestShopPrice(): number?
	local best: number? = nil
	for _, def in Catalog.list() do
		local price = def.shopPrice
		if finite(price) and not def.robuxOnly and (best == nil or (price :: number) < (best :: number)) then
			best = price
		end
	end
	return best
end

local function starterName(): string
	local def = Catalog.get(Catalog.starterId())
	return if def then Strings.resolve(def.nameKey) or def.id else Catalog.starterId()
end

-- Public

function OnboardingFormat.steps(): { Step }
	return STEPS
end

function OnboardingFormat.currentStep(done: { [string]: boolean }?, unavailable: { [string]: boolean }?): Step?
	local set = done or {}
	local skip = unavailable or {}
	for _, step in STEPS do
		if set[step.id] ~= true and skip[step.id] ~= true then
			return step
		end
	end
	return nil
end

function OnboardingFormat.isComplete(done: { [string]: boolean }?, unavailable: { [string]: boolean }?): boolean
	return OnboardingFormat.currentStep(done, unavailable) == nil
end

function OnboardingFormat.isEligible(policy: unknown): boolean
	return policy == ELIGIBLE
end

function OnboardingFormat.goal(policy: unknown): number
	if OnboardingFormat.isEligible(policy) then
		local box = Boxes.get(FIRST_BOX_ID)
		local cost = if box then box.cost else nil
		if cost and finite(cost) then
			return cost
		end
	end
	return cheapestShopPrice() or 0
end

function OnboardingFormat.squeezeHint(input: InputKind?): string
	local hints = Strings.onboarding.squeezeHint :: any
	return hints[input or DEFAULT_INPUT] or hints[DEFAULT_INPUT]
end

-- The waypoint target name and the HUD element to pulse for a step (either may be nil).
function OnboardingFormat.guidance(step: Step, policy: unknown): (string?, string?)
	local waypoint = WAYPOINTS[step.guidance]
	if step.guidance == "waypointBoxStand" and not OnboardingFormat.isEligible(policy) then
		waypoint = SHOP_WAYPOINT
	end
	return waypoint, PULSES[step.guidance]
end

function OnboardingFormat.text(step: Step, ctx: Context): string
	local key = step.textKey
	if step.restrictedTextKey and not OnboardingFormat.isEligible(ctx.policy) then
		key = step.restrictedTextKey
	end
	local template = Strings.resolve(key) or ""
	local goal = OnboardingFormat.goal(ctx.policy)
	local coins = if finite(ctx.coins) then math.clamp(math.floor(ctx.coins :: number), 0, goal) else 0
	return Strings.format(template, {
		starterName = starterName(),
		squeezeHint = OnboardingFormat.squeezeHint(ctx.input),
		coins = Format.coins(coins),
		goal = Format.coins(goal),
	})
end

-- True when the card shows: a ready profile, not skipped (a replay ignores that) and a step left.
function OnboardingFormat.visible(ctx: Context): boolean
	if not ctx.ready or skipped(ctx) then
		return false
	end
	return OnboardingFormat.currentStep(doneSet(ctx), ctx.unavailable) ~= nil
end

function OnboardingFormat.model(ctx: Context): Model?
	if not OnboardingFormat.visible(ctx) then
		return nil
	end
	local step = OnboardingFormat.currentStep(doneSet(ctx), ctx.unavailable) :: Step
	local waypoint, pulse = OnboardingFormat.guidance(step, ctx.policy)
	local welcome = step.id == WELCOME
	return {
		stepId = step.id,
		text = OnboardingFormat.text(step, ctx),
		gotIt = welcome,
		skip = not welcome,
		waypoint = waypoint,
		pulse = pulse,
	}
end

-- The saved done set of an onboarding state (booleans only), for the controller's own checks.
function OnboardingFormat.done(onboarding: any): { [string]: boolean }
	return savedDone(onboarding)
end

return OnboardingFormat
