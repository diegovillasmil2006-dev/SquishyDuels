--!strict
-- SqueezeFeel (client only). SqueezeController's squeeze glue on the held squishy rig (squishy overhaul spec
-- 2026-10-09 §3.2); not a controller: no init or start, the bootstrap does not load it.
-- A squeeze is a tap on the rig of the player's held model (HeldSquishyController owns and steps it). The rig is the
-- only clock: this module plays what its one-shot events say, so a hitch can never desync sound from motion. Every
-- timing point stays where it was (DESIGN §9.6, §18.5.1 A1-A2):
--   * squish (the end of anticipation, 70 ms): sfx.squish;
--   * peak (peak compression): the rarity's puffs (another player's: othersPuffs, given in play's options);
--   * releaseStart: the Exclusive squeezeFx hook's steam puffs from the Nostril* parts (own squeezes only);
--   * popEnd (390 ms; 430 ms for Uncommon and Epic): sfx.squeezeRelease and, for an own squeeze, the release pop
--     sparkles, or every rhythm.popEvery-th the big pop with sfx.pop.
-- No arm moves (spec 2026-10-11 §4: the holding arm stays in its hold pose; only the held squishy squishes). Every
-- click pays (startKind, interruptFx): an own press restarts the rig at once; one before the running squeeze's pop end
-- merges that squeeze's pop (and, at most once per release pop, its puffs) into the press; another player's squeeze
-- waits for the pop end ("busy"). The twist, the springy recovery, the release kick, the squish face and Dragon's
-- section flare are the rig's (spec Q38: the old fast extras, the 8.3 Hz twist, the Epic jiggle and the 14 Hz horn /
-- wing flutter, are gone).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local SqueezeRhythm = require(Client.Anim.SqueezeRhythm)
local SquishRig = require(Client.Anim.SquishRig)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local SoundController = require(script.Parent.SoundController)

-- Types

-- A Config.Anim.squeeze.squeezeFx hook entry (Dragon's steam).
export type SqueezeFx = typeof(Config.Anim.squeeze.squeezeFx.dragon_steam)

-- What one squeeze of a squishy emits: its rarity's puffs and its steam hook (Exclusive).
export type Plan = { particles: number, steam: SqueezeFx? }

-- play() options (§18.5.1 A1). Another player's squeeze passes particles = othersPuffs(distance) and other = true.
export type PlayOptions = {
	particles: number?, -- puffs at peak compression (default: the plan's)
	other: boolean?, -- another player's squeeze: no steam, no release pop, no rhythm
}

-- What a new squeeze does with the squeeze still playing on the same model (startKind).
export type StartKind = "start" | "restart" | "interrupt" | "busy"

-- What an own squeeze cut short by the next press still plays at that moment (interruptFx).
export type MergedFx = { sparkles: number, bigPop: boolean, puffs: number }

type Active = {
	player: Player,
	def: Types.SquishyDef,
	model: Model,
	rig: SquishRig.Rig,
	particles: number,
	particleColor: Color3,
	steam: SqueezeFx?,
	emitted: boolean, -- the peak puffs are out
	other: boolean,
	beat: SqueezeRhythm.Beat?, -- the own squeeze's place in the streak (A2)
	c: number, -- the rig's last scale on the squeeze axis and across it (debugState)
	w: number,
}

-- Constants

local SQUEEZE = Config.Anim.squeeze
local EVENTS = SquishRig.EVENTS
local OVERLAY = "squeeze"
local NOSTRIL_PREFIX = "Nostril" -- Dragon's steam comes out of these parts (Art/SquishyBlueprints)
local SOUND_SQUISH = "sfx.squish"
local SOUND_RELEASE = "sfx.squeezeRelease"
local SOUND_POP = "sfx.pop" -- the big pop every rhythm.popEvery-th squeeze (§18.6)
local OWN_SOUND_PRIORITY = 1 -- §18.6 priorities: 0 UI and ambience, 1 own sounds (others' default to -1)
-- A1 release pop look. Reading: DESIGN §18.5.1 A1 gives these numbers and §18.8 has no Config key for them.
local RELEASE_POP = {
	lifetimeMin = 0.25,
	lifetimeMax = 0.35,
	sizeFrom = 0.25,
	sizeTo = 0,
	speedMin = 2,
	speedMax = 4,
}

-- Module table

local SqueezeFeel = {}

-- Private

local actives: { [Player]: Active } = {}
local rhythm: SqueezeRhythm.State = SqueezeRhythm.new() -- the own squeeze streak (A2)
local lastOwnPuffsAt = -math.huge -- os.clock() of the last own puff burst (interruptFx's puff gap)

local function particleProps(color: Color3, speed: NumberRange?): FxPool.Props
	local p = SQUEEZE.particles
	return {
		Texture = Config.Vfx.Textures.smoke,
		Lifetime = NumberRange.new(p.lifetimeMin, p.lifetimeMax),
		Size = NumberSequence.new(p.sizeFrom, p.sizeTo),
		Speed = speed or NumberRange.new(p.speedMin, p.speedMax),
		SpreadAngle = Vector2.new(p.spreadDeg, p.spreadDeg),
		Color = ColorSequence.new(color),
	}
end

local function isOwn(state: Active): boolean
	return not state.other and state.player == Players.LocalPlayer
end

local function emitPuffs(state: Active, now: number)
	if state.particles > 0 and state.model.Parent ~= nil then
		FxPool.default():emit(state.model:GetPivot().Position, state.particles, particleProps(state.particleColor))
		if isOwn(state) then
			lastOwnPuffsAt = now
		end
	end
end

local function emitSteam(state: Active)
	local fx = state.steam
	if fx == nil or fx.steamPuffs <= 0 or state.other then
		return
	end
	local nostrils: { BasePart } = {}
	for _, descendant in state.model:GetDescendants() do
		if descendant:IsA("BasePart") and string.sub(descendant.Name, 1, #NOSTRIL_PREFIX) == NOSTRIL_PREFIX then
			table.insert(nostrils, descendant)
		end
	end
	if #nostrils == 0 then
		return
	end
	local pool = FxPool.default()
	local speed = NumberRange.new(fx.steamSpeedMin, fx.steamSpeedMax)
	for index = 1, fx.steamPuffs do
		local nostril = nostrils[(index - 1) % #nostrils + 1]
		pool:emit(nostril.Position, 1, particleProps(Palette.White, speed))
	end
end

-- A squeeze sound from the held model; another player's squeeze is distance- and count-limited (§11.9, other =
-- "squeeze"). An own squeeze carries its rhythm beat (A2): `pitch` multiplies the random pitch, `variance` replaces
-- the key's random variance once the streak is >= 2 (nil keeps it).
local function playSound(state: Active, key: string)
	if state.model.Parent == nil then
		return
	end
	local beat = state.beat
	local other = state.player ~= Players.LocalPlayer
	SoundController.play(key, {
		at = state.model:GetPivot().Position,
		other = if other then "squeeze" else nil,
		priority = if other then nil else OWN_SOUND_PRIORITY,
		pitch = if beat then beat.pitch else nil,
		variance = if beat then beat.variance else nil,
	})
end

-- The release pop's sparkles and, for the big pop, sfx.pop (A1, A2) at the held model.
local function emitPop(state: Active, sparkles: number, bigPop: boolean)
	if state.model.Parent == nil then
		return
	end
	local at = state.model:GetPivot().Position
	if sparkles > 0 then
		local p = RELEASE_POP
		FxPool.default():emit(at, sparkles, {
			Texture = Config.Vfx.Textures.sparkles,
			Lifetime = NumberRange.new(p.lifetimeMin, p.lifetimeMax),
			Size = NumberSequence.new(p.sizeFrom, p.sizeTo),
			Speed = NumberRange.new(p.speedMin, p.speedMax),
			SpreadAngle = Vector2.new(SQUEEZE.particles.spreadDeg, SQUEEZE.particles.spreadDeg),
			Color = ColorSequence.new(state.particleColor),
		})
	end
	if bigPop then
		SoundController.play(SOUND_POP, { at = at, priority = OWN_SOUND_PRIORITY })
	end
end

-- The release pop (A1, A2): the beat's sparkles (popSparkles, or bigPopSparkles plus sfx.pop every popEvery-th own
-- squeeze). Own squeezes only.
local function releasePop(state: Active)
	local beat = state.beat
	if beat == nil or state.other then
		return
	end
	emitPop(state, beat.sparkles, beat.bigPop)
end

-- An own squeeze cut short by the next press before its pop end (every click pays): its effects merge into the press
-- (interruptFx), so the rhythm's big pop still comes every 8th squeeze and the budgets hold at 12 a second.
local function mergeInterrupted(state: Active, now: number)
	if state.model.Parent == nil then
		return
	end
	local fx = SqueezeFeel.interruptFx(
		state.beat,
		state.emitted,
		state.particles,
		now - lastOwnPuffsAt,
		state.rig.timing.popEndMs / 1000
	)
	if fx.puffs > 0 then
		state.emitted = true
		FxPool.default():emit(state.model:GetPivot().Position, fx.puffs, particleProps(state.particleColor))
		lastOwnPuffsAt = now
	end
	emitPop(state, fx.sparkles, fx.bigPop)
end

-- The scale on the squeeze axis and across it.
local function alongAcross(S: Vector3, axis: string): (number, number)
	if axis == "X" then
		return S.X, S.Y
	elseif axis == "Z" then
		return S.Z, S.X
	end
	return S.Y, S.X
end

-- One frame of a squeeze (HeldSquishyController calls it right after it stepped the rig): this step's events. It stays
-- while the rig plays the squeeze (until its recovery settles).
local function stepActive(state: Active, now: number, out: SquishRig.Out): (Vector3, number, boolean)
	local events = out.events
	if events ~= 0 then
		local squish, puffs, steam, release, pop = SqueezeFeel.effects(events, state.other)
		if squish then
			playSound(state, SOUND_SQUISH)
		end
		if puffs then
			state.emitted = true
			emitPuffs(state, now)
		end
		if steam then
			emitSteam(state)
		end
		if release then
			playSound(state, SOUND_RELEASE)
		end
		if pop then
			releasePop(state)
		end
	end
	state.c, state.w = alongAcross(out.S, state.def.anim.squeezeAxis)
	return Vector3.one, 0, state.rig:elapsedMs() ~= nil
end

-- Public: pure helpers (unit-tested) --------------------------------------------------------------------------------

-- The timing points of a squeeze of `def` (its rarity's widening extra included): the rig's, read from
-- Config.Anim.squeeze.phases (squish 70 ms, peak, release start, pop end).
function SqueezeFeel.timing(def: Types.SquishyDef): SquishRig.Timing
	return SquishRig.timingFor(def.rarity)
end

-- What one squeeze of `def` emits: its rarity's puffs and, for an Exclusive with a Catalog anim.squeezeFx hook, that
-- hook (the steam). ReducedMotion keeps both (FxPool halves the puffs, §18.1).
function SqueezeFeel.plan(def: Types.SquishyDef): Plan
	local flourish = SQUEEZE.flourish[def.rarity] or SQUEEZE.flourish.Common
	local hook = def.anim.squeezeFx
	return {
		particles = flourish.particles,
		steam = if flourish.useSqueezeFx and hook then SQUEEZE.squeezeFx[hook] else nil,
	}
end

-- What one rig step's `events` play, in this order: the squish sound, the peak puffs, the steam (the release start;
-- own squeezes only), the release sound and the release pop (the pop end; the pop own squeezes only).
function SqueezeFeel.effects(events: number, other: boolean): (boolean, boolean, boolean, boolean, boolean)
	local popEnd = bit32.band(events, EVENTS.popEnd) ~= 0
	return bit32.band(events, EVENTS.squish) ~= 0,
		bit32.band(events, EVENTS.peak) ~= 0,
		bit32.band(events, EVENTS.releaseStart) ~= 0 and not other,
		popEnd,
		popEnd and not other
end

-- What a new squeeze does with the squeeze still playing on the same model, `tMs` into it (nil = none) whose release
-- pop ends at `endMs`; `recovering`: the rig is past that pop end (its spring recovery runs) (every click pays,
-- 2026-10-06). "start": nothing plays; "restart": the running one recovers, which the next squeeze may always cut
-- (§6.3); "interrupt": an own squeeze before its pop end still restarts at once (the cut one merges its pop into the
-- press, interruptFx); "busy": another player's squeeze waits for theirs to reach its pop end (others' effects stay at
-- one squeeze per release pop however fast they click). An own squeeze is decided by `recovering`, not the clock: a
-- press just after endMs can find a rig whose step has not crossed the pop end yet; it merges that pop too.
function SqueezeFeel.startKind(tMs: number?, endMs: number, own: boolean, recovering: boolean): StartKind
	if tMs == nil then
		return "start"
	end
	if own then
		return if recovering then "restart" else "interrupt"
	end
	return if tMs >= endMs then "restart" else "busy"
end

-- What an own squeeze cut short before its pop end still plays when the next press interrupts it (pure; the budgets
-- hold at the 12-per-second cap): the beat's sparkles and big pop (popSparkles, or bigPopSparkles + sfx.pop on every
-- rhythm.popEvery-th squeeze, so the big pop still comes with fast clicking); its peak puffs (`particles`) only when it
-- never emitted them (`emitted` false) and the last own puff burst is at least `puffGapSeconds` old (its pop end: own
-- puffs never come faster than back-to-back full squeezes). No sfx.squeezeRelease: the next press's sfx.squish takes
-- its place. No beat (not an own squeeze): nothing.
function SqueezeFeel.interruptFx(
	beat: SqueezeRhythm.Beat?,
	emitted: boolean,
	particles: number,
	sincePuffsSeconds: number,
	puffGapSeconds: number
): MergedFx
	if beat == nil then
		return { sparkles = 0, bigPop = false, puffs = 0 }
	end
	local puffs = if not emitted and sincePuffsSeconds >= puffGapSeconds then math.max(0, particles) else 0
	return { sparkles = beat.sparkles, bigPop = beat.bigPop, puffs = puffs }
end

-- Public: the squeeze --------------------------------------------------------------------------------------------------

-- Plays a squeeze on a player's held model: a tap on its rig (the local player's for prediction; others' from
-- SD_SqueezeAt with opts = { particles = othersPuffs(distance), other = true }, §18.5.1 A1). The local player's
-- squeeze counts in the rhythm streak (A2). Returns false and a reason when it cannot play now ("noHeldModel": none
-- shown or not animating; "busy": another player's squeeze before its pop end).
function SqueezeFeel.play(player: Player, opts: PlayOptions?): (boolean, string?)
	local model = HeldSquishyController.getModel(player)
	local squishyId = HeldSquishyController.getSquishyId(player)
	local def = if squishyId then Catalog.get(squishyId) else nil
	local rig = HeldSquishyController.getRig(player)
	if model == nil or def == nil or rig == nil or not HeldSquishyController.isHolding(player) then
		return false, "noHeldModel"
	end
	local own = player == Players.LocalPlayer and not (opts ~= nil and opts.other == true)
	local current = actives[player]
	local from = if current and current.model == model and current.rig == rig then current else nil
	local clock = os.clock()
	local kind =
		SqueezeFeel.startKind(if from then rig:elapsedMs() else nil, rig.timing.popEndMs, own, rig:isRecovering())
	if kind == "busy" then
		return false, "busy"
	end
	if kind == "interrupt" and from and isOwn(from) then
		mergeInterrupted(from, clock)
	end
	local plan = SqueezeFeel.plan(def :: Types.SquishyDef)
	local particles = if opts and opts.particles ~= nil then math.max(0, math.floor(opts.particles)) else nil
	local state: Active = {
		player = player,
		def = def :: Types.SquishyDef,
		model = model :: Model,
		rig = rig :: SquishRig.Rig,
		particles = particles or plan.particles,
		particleColor = if (def :: Types.SquishyDef).rarity == "Common"
			then Palette.White
			else Color3.fromHex((def :: Types.SquishyDef).visuals.accent),
		steam = plan.steam,
		emitted = false,
		other = not own,
		beat = nil,
		c = 1,
		w = 1,
	}
	actives[player] = state
	local accepted = HeldSquishyController.setOverlay(player, OVERLAY, {
		step = function(_dt: number, now: number, out: SquishRig.Out): (Vector3, number, boolean)
			return stepActive(state, now, out)
		end,
		removed = function()
			if actives[player] == state then
				actives[player] = nil
			end
		end,
	})
	if not accepted then
		actives[player] = nil
		return false, "noHeldModel"
	end
	rig:tap()
	if own then
		state.beat = SqueezeRhythm.beat(rhythm, clock)
	end
	return true, nil
end

-- A2: any rejection but squeeze.tooFast ends the own streak.
function SqueezeFeel.reject(reason: string?)
	SqueezeRhythm.reject(rhythm, reason)
end

-- A player who left: their squeeze is forgotten (their held model goes with them).
function SqueezeFeel.forget(player: Player)
	actives[player] = nil
end

-- Every squeeze stops (its overlay goes), a fresh streak (SqueezeController's cleanup).
function SqueezeFeel.clear()
	for player in table.clone(actives) do
		HeldSquishyController.setOverlay(player, OVERLAY, nil)
	end
	table.clear(actives)
	SqueezeRhythm.reset(rhythm)
	lastOwnPuffsAt = -math.huge
end

-- Small table for SqueezeController.debugState: the squeeze of `player` and how many other players squeeze.
function SqueezeFeel.debugState(player: Player?): { [string]: any }
	local state = if player then actives[player] else nil
	local others = 0
	for other in actives do
		if other ~= player then
			others += 1
		end
	end
	return {
		active = state ~= nil,
		squishyId = if state then state.def.id else nil,
		rarity = if state then state.def.rarity else nil,
		tMs = if state then state.rig:elapsedMs() else nil,
		c = if state then state.c else nil,
		w = if state then state.w else nil,
		recovering = if state then state.rig:isRecovering() else nil,
		othersSqueezing = others,
	}
end

return SqueezeFeel
