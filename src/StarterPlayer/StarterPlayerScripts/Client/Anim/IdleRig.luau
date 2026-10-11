--!strict
-- IdleRig (client only). The idle life of a squishy model that waits to be looked at (squishy overhaul spec 2026-10-09
-- §3.2 "Idle life"): the box reveal's model (BoxController) and the Collection displays (CollectionController). One
-- Anim/SquishRig per model, stepped once a frame by its one owner and written by the model's Anim/SquishDeformer in one
-- apply(); the lobby breath multiplies the rig's scale (an owner overlay, as the deformer allows).
--   IdleRig.breath(t, phase, reduced) -> Vector3   pure: the lobby breath (Config.Anim.held.lobbyIdle ampY and
--                                                  periodSeconds), one-sided like the lobby breathers (AmbientMath
--                                                  .breathe), so a model on a stand never lifts off it; phase in
--                                                  periods; (1, 1, 1) under ReducedMotion
--   IdleRig.new(model, squishyId, options?) -> IdleRig?   nil without a squishy motion row; attaches and writes nothing
--     options: blink (default true; false for the Lavender silhouettes), detail (default "near"; "hero" also bounces
--     the sections), twist (the deformer's twist target: "pivot" for a model Inspect adopts, which then shares this
--     deformer), phase (of the breath, in periods), reduced (ReducedMotion), seed (the blink timing)
--   life:start(wowSeconds?)   the first call attaches the deformer (the model must sit at its built rest pose: no rig
--                             or deformer writes before it) and, with wowSeconds, shows the wow face that long. A
--                             "hero" life (the box reveal's) counts as a hero rig (Anim/HeroRigs, the rig budget) from
--                             then until handOff() or destroy()
--   life:isStarted()
--   life:step(dt)             one frame; nothing before start(), after handOff() or destroy(). The breath runs on the
--                             life's own clock and fades in over lobbyIdle.crossfadeSeconds from a start or a rest, so
--                             it never jumps whatever its phase
--   life:breathNow() -> (amount, rising)   the breath shown now: S.Y = 1 + lobbyIdle.ampY × amount (0-1, the fade-in
--                             included; 0 before start(), at rest, after handOff() and under ReducedMotion) and whether
--                             the next frame shows more. Inspect goes on from it when it takes the rig (no jump)
--   life:rest()               back to the rest pose (rig reset, base values written once); the next step() resumes
--   life:handOff() -> rig?    stops here for good and returns the rig for its next owner (InspectController.takeRig);
--                             the deformer stays attached for it. nil once handed off or destroyed
--   life:destroy()            rests the model and detaches the deformer (not after handOff); safe twice
--   life.out                  the rig's last frame (tests, debug)
-- No instances, connections or threads of its own.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local AmbientMath = require(script.Parent.AmbientMath)
local HeroRigs = require(script.Parent.HeroRigs)
local SquishDeformer = require(script.Parent.SquishDeformer)
local SquishRig = require(script.Parent.SquishRig)

-- Types

export type Options = {
	blink: boolean?,
	detail: SquishRig.Detail?,
	twist: SquishDeformer.TwistTarget?,
	phase: number?,
	reduced: boolean?,
	seed: number?,
}

type IdleRigData = {
	model: Model,
	out: SquishRig.Out,
	_rig: SquishRig.Rig?,
	_deformer: SquishDeformer.Deformer?,
	_twist: SquishDeformer.TwistTarget?,
	_phase: number,
	_reduced: boolean,
	_t: number, -- seconds since the start or the last rest (the breath's clock)
	_resting: boolean,
	_done: boolean, -- handed off or destroyed
	_hero: boolean, -- detail "hero": counts in HeroRigs while started
}

-- Constants

local LOBBY = Config.Anim.held.lobbyIdle
local FADE_IN_SECONDS = LOBBY.crossfadeSeconds -- the breath fades in from a start or a rest (no jump)
local NEXT_FRAME = 1 / 60 -- breathNow's "rising": the breath one frame later

-- Module table

local IdleRigClass = {}
IdleRigClass.__index = IdleRigClass

export type IdleRig = typeof(setmetatable({} :: IdleRigData, IdleRigClass))

local IdleRig = {}

-- The box reveal's wow once the rise ends (spec §3.2 idle life table).
IdleRig.REVEAL_WOW_SECONDS = 0.4

-- Methods

function IdleRigClass.start(self: IdleRig, wowSeconds: number?)
	if self._done or self._deformer ~= nil then
		return
	end
	self._deformer = SquishDeformer.attach(self.model, { twist = self._twist })
	local rig = self._rig
	if rig and wowSeconds and wowSeconds > 0 then
		rig:setFace("wow", wowSeconds)
	end
	self._t = 0
	self._resting = false
	if self._hero then
		HeroRigs.set(self, true)
	end
end

function IdleRigClass.isStarted(self: IdleRig): boolean
	return not self._done and self._deformer ~= nil
end

function IdleRigClass.step(self: IdleRig, dt: number)
	local rig, deformer = self._rig, self._deformer
	if self._done or rig == nil or deformer == nil then
		return
	end
	local h = if dt == dt and dt > 0 then dt else 0
	self._t += h
	local out = self.out
	rig:step(h, out)
	local breath = IdleRig.breath(self._t, self._phase, self._reduced)
	local fadeIn = math.min(self._t / FADE_IN_SECONDS, 1)
	out.S = out.S * (Vector3.one + (breath - Vector3.one) * fadeIn)
	deformer:apply(out)
	self._resting = false
end

-- The breath amount at the life's clock time t, the fade-in included (step's S.Y = 1 + ampY × this).
local function amountAt(self: IdleRig, t: number): number
	return (IdleRig.breath(t, self._phase, self._reduced).Y - 1) / LOBBY.ampY * math.min(t / FADE_IN_SECONDS, 1)
end

function IdleRigClass.breathNow(self: IdleRig): (number, boolean)
	if self._done or self._deformer == nil or self._resting or self._reduced then
		return 0, true
	end
	local now = amountAt(self, self._t)
	return now, amountAt(self, self._t + NEXT_FRAME) > now
end

function IdleRigClass.rest(self: IdleRig)
	local rig, deformer = self._rig, self._deformer
	if self._done or self._resting or rig == nil or deformer == nil then
		return
	end
	self._resting = true
	self._t = 0
	rig:reset()
	deformer:rest()
end

function IdleRigClass.handOff(self: IdleRig): SquishRig.Rig?
	if self._done then
		return nil
	end
	local rig = self._rig
	self._done = true
	self._rig, self._deformer = nil, nil
	HeroRigs.set(self, false)
	return rig
end

function IdleRigClass.destroy(self: IdleRig)
	if self._done then
		return
	end
	self._done = true
	HeroRigs.set(self, false)
	local deformer = self._deformer
	self._rig, self._deformer = nil, nil
	if deformer then
		deformer:destroy()
	end
end

-- Public

function IdleRig.breath(t: number, phase: number, reduced: boolean): Vector3
	if reduced then
		return Vector3.one
	end
	return AmbientMath.breathe(LOBBY.ampY, LOBBY.periodSeconds, t, phase)
end

function IdleRig.new(model: Model, squishyId: string, options: Options?): IdleRig?
	local def = Catalog.get(squishyId)
	local blueprint = if def then SquishyBlueprints[def.blueprintId] else nil
	local motion = if blueprint then blueprint.motion else nil
	if def == nil or blueprint == nil or motion == nil then
		return nil
	end
	local opts: Options = options or {}
	local reduced = opts.reduced == true
	local rig = SquishRig.new(motion, {
		axis = def.anim.squeezeAxis,
		rarity = def.rarity :: string,
		reduced = reduced,
		seed = opts.seed,
		sections = blueprint.sections,
		foamRecoveryT = def.anim.foamRecoveryT,
		blink = opts.blink ~= false,
	})
	local detail: SquishRig.Detail = opts.detail or "near"
	rig:setDetail(detail)
	local data: IdleRigData = {
		model = model,
		out = SquishRig.newOut(),
		_rig = rig,
		_deformer = nil,
		_twist = opts.twist,
		_phase = opts.phase or 0,
		_reduced = reduced,
		_t = 0,
		_resting = true,
		_done = false,
		_hero = detail == "hero",
	}
	return setmetatable(data, IdleRigClass)
end

return IdleRig
