--!strict
-- OnboardingFormat (client only, pure). DESIGN §11.8 (onboarding card, Config/Onboarding), §6.6 (the cheapest shop
-- price), §11.7 (input kinds). What the onboarding tip card shows, as plain data. Onboarding never pays Coins.
--   currentStep(done, unavailable?)   the lowest Config.Onboarding step not in `done` (steps complete in any order)
--                            and not unavailable, or nil
--   isComplete(done, unavailable?)    every available step done
--   goal()                   the Coins goal of the firstBox step: the cheapest Catalog shopPrice (a 10,000 Common; Batch
--                            1: the 150,000 Snack Box was out of a new player's reach; a box still completes the step)
--   squeezeHint(input)       onboarding.squeezeHint.<keyboard | touch | gamepad> (spec 2026-10-11: "Click or press E",
--                            "Tap the screen", "Press X")
--   guidance(step)           (waypoint, pulse): a WorldLayout.waypoint name ("shop", "duel") or a HudController.element
--                            name ("squishies": the inspect step); the squeeze and capsule steps have neither
--   text(step, ctx)          the step's text with {starterName}, {squeezeHint}, {coins}/{goal} filled in
--   capsuleBought(new, old)  the replay's sign of the capsule step: the capsules state's slot count or a capsule's level
--                            rose (a swap or an auto-filled squishy changes neither)
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
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)

-- Types

export type InputKind = "keyboard" | "touch" | "gamepad"

export type Step = {
	id: string,
	textKey: string,
	recordedBy: string,
	guidance: string,
}

export type Context = {
	onboarding: any?, -- the profile's onboarding state {v, done, skipped}
	ready: boolean, -- the profile is ready (not loading, offline or read-only)
	replay: { [string]: boolean }?, -- replay mode: the steps done in this local replay (saved flags ignored)
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
local DEFAULT_INPUT: InputKind = "keyboard"
-- Config.Onboarding guidance -> (waypoint, pulse). The firstBox step points everyone to the Shop (Batch 1). The squeeze
-- step's waypointMat maps to no waypoint: its text says squeeze anywhere (spec 2026-10-11 §5).
local WAYPOINTS: { [string]: string } = {
	waypointShop = "shop",
	waypointPodium = "duel",
}
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

function OnboardingFormat.goal(): number
	return cheapestShopPrice() or 0
end

function OnboardingFormat.squeezeHint(input: InputKind?): string
	local hints = Strings.onboarding.squeezeHint :: any
	return hints[input or DEFAULT_INPUT] or hints[DEFAULT_INPUT]
end

-- The waypoint target name and the HUD element to pulse for a step (either may be nil).
function OnboardingFormat.guidance(step: Step): (string?, string?)
	return WAYPOINTS[step.guidance], PULSES[step.guidance]
end

function OnboardingFormat.text(step: Step, ctx: Context): string
	local template = Strings.resolve(step.textKey) or ""
	local goal = OnboardingFormat.goal()
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
	local waypoint, pulse = OnboardingFormat.guidance(step)
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

-- Batch 1: the replay's sign of the capsule step: the slot count or a capsule's level rose (an upgrade or an unlock).
function OnboardingFormat.capsuleBought(new: any, old: any): boolean
	if type(new) ~= "table" or type(old) ~= "table" or type(new.list) ~= "table" or type(old.list) ~= "table" then
		return false
	end
	if finite(new.slots) and finite(old.slots) and new.slots > old.slots then
		return true
	end
	for slot, capsule in new.list do
		local before = old.list[slot]
		if
			type(capsule) == "table"
			and type(before) == "table"
			and finite(capsule.level)
			and finite(before.level)
			and capsule.level > before.level
		then
			return true
		end
	end
	return false
end

return OnboardingFormat
