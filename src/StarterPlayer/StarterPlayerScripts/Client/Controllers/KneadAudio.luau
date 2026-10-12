--!strict
-- KneadAudio (client only; not a controller: no init or start, the bootstrap does not load it). Spec phase2-squeeze
-- §1.22, §3.9, §3.10: the wax crunch of the knead screen in Inspect, the design's wax engine (sd/squish.js:796-945) on
-- pre-rendered files. There is no runtime synthesis: each feel's sheet (Config.Audio.wax: 54 baked bursts, 48 grains,
-- 5 taps) is played one region at a time (Sound.PlaybackRegion), the thumps at PlaybackSpeed = the toy's pitch, the
-- haze and body beds as loops whose volume follows the design's waxFrame formulas. Everything goes through
-- SoundController (the Wax group: no cooldown, its own voice cap and the design's bus compressor), mono and centred
-- (2D sounds have no pan). The ids are AssetTable's sfx.wax.* slots: PENDING (silent) until the user uploads the files.
--
-- Pure (unit-tested):
--   KneadAudio.burst(E, intact, rng) -> Shot        a crack (squish.js:856-866): the nearest baked E (log steps) and
--     intact, a random variant, × 10^(energyDb·(E - baked E) / 20) × the intact share ratio, speed U(burstSpeedMin,
--     burstSpeedMax). The burst's own 6-18 ms lead-in is baked into its slot.
--   KneadAudio.grain(index) / tap(index) -> (start, length)   the sheet's grain (0-47) and tap (0-4) regions
--   KneadAudio.release(brush, amount, feelGain, rng) / air(amount, rise, feelGain, rng) -> { Shot }   the ticks
--     (squish.js:874-876, 897, 905)
--   KneadAudio.press(brush, pitch, rng) -> ({ Shot }, thumpSpeed?)   squish.js:867-873
--   KneadAudio.beds(feelGain, drive, press, intact) -> (haze, body)  squish.js:846-850
--   KneadAudio.ease(current, target, tau, dt) -> number              setTargetAtTime's approach over one frame
-- A Shot is one sheet region: { start, length, volume (× the sheet's level), speed, delay (s from now) }.
-- Every random value is one rng:NextNumber() roll, in the design's order.
--
-- The player (one per knead session):
--   KneadAudio.new(feel, pitch, options?) -> Audio   options.player (default SoundController), options.rng,
--                                options.wax (the wax switch, user 2026-10-12: nil = Config.Wax.enabled)
--   audio:crack(E, intact)       a sounding crack (Anim/WaxCoat's events)
--   audio:event(e)               Anim/SoftBody's sound events: press, release, air, snap (kicks are ignored here)
--   audio:rewax()                the sparkle (fx.js:41)
--   audio:frame(dt, active, drive, press, intact)   every frame: the beds (started on the first active frame)
--   audio:destroy()              stops the beds; nothing plays after it (pending delays included)
-- Delays under one frame play at once (frame-quantised, spec §3.9); longer ones wait with task.delay.
-- With the wax off (user 2026-10-12: options.wax false) only the soft body sounds: the body bed (its loop; the caller
-- drives it as if there were no coat: drive 0, intact 0), the thumps (a press: its taps and, for palms and thumbs,
-- the thump; a stretch let go: the snap thump) and, for a press let go, the soft slime let-go (sfx.squeezeRelease on
-- the UI group, as Inspect's squeeze plays, at the toy's pitch; Config.Audio.kneadSoft). No crack bursts (crack, the
-- snap's two bursts), no crackle ticks (release, air), no haze loop and no re-wax sparkle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local SoundController = require(script.Parent.SoundController)

export type Shot = {
	start: number,
	length: number,
	volume: number,
	speed: number,
	delay: number,
}

export type Loop = {
	setVolume: (self: any, volume: number) -> (),
	stop: (self: any, fadeMs: number?) -> (),
}

export type Player = {
	play: (key: string, options: any) -> boolean,
	playLoop: (key: string, options: any) -> any,
}

export type Options = {
	player: Player?,
	rng: Random?,
	wax: boolean?, -- the wax switch (user 2026-10-12): nil = Config.Wax.enabled; false = the soft body sounds only
}

export type Event = {
	kind: string,
	amount: number?,
	brush: string?,
	pan: number?,
	slipped: boolean?,
}

type AudioData = {
	_player: Player,
	_rng: Random,
	_feel: string,
	_pitch: number,
	_gain: number,
	_rise: number,
	_sheet: string,
	_sheetLevel: number,
	_loopLevel: number,
	_haze: Loop?,
	_body: Loop?,
	_bedsTried: boolean,
	_hazeValue: number,
	_bodyValue: number,
	_hazeWritten: number,
	_bodyWritten: number,
	_wax: boolean,
	_dead: boolean,
}

local WAX = Config.Audio.wax
local FEELS = Config.Knead.feels
local DEFAULT_FEEL = Config.Knead.defaultFeel
local GROUP = "Wax"
local KEY_SHEET = "sfx.wax."
local KEY_HAZE = "sfx.wax.haze."
local KEY_BODY = "sfx.wax.body."
local KEY_THUMP = "sfx.wax.thump"
local KEY_SNAP_THUMP = "sfx.wax.snapThump"
local KEY_REWAX = "sfx.wax.rewax"
local KEY_LET_GO = "sfx.squeezeRelease" -- user 2026-10-12: the soft slime let-go (the wax off)
local LET_GO_GROUP = "UI" -- Inspect plays on UI (InspectController's squeeze)
local SOFT = Config.Audio.kneadSoft
local FRAME = 1 / 60 -- delays shorter than this play at once
local PRESS_LEAD = 0.003 -- design: squish.js:869 (a press starts 3 ms on)

local AudioClass = {}
AudioClass.__index = AudioClass

export type Audio = typeof(setmetatable({} :: AudioData, AudioClass))

local KneadAudio = {}

-- 10^(-db / 20): a file's normalisation undone.
local function level(db: number): number
	return 10 ^ (-db / 20)
end

local function between(rng: Random, a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

local function nearestLog(values: { number }, x: number): number
	local best, bestDistance = 1, math.huge
	local lx = math.log(math.max(x, 1e-6))
	for index, value in values do
		local distance = math.abs(lx - math.log(value))
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

local function nearest(values: { number }, x: number): number
	local best, bestDistance = 1, math.huge
	for index, value in values do
		local distance = math.abs(x - value)
		if distance < bestDistance then
			best, bestDistance = index, distance
		end
	end
	return best
end

local function intactShare(intact: number): number
	return WAX.intactBase + (1 - WAX.intactBase) * intact
end

-- A bed's eased value snaps to its target within bedEpsilon (the design writes a gain once it moved that much).
local function settle(value: number, target: number): number
	return if math.abs(value - target) < WAX.bedEpsilon then target else value
end

-- Whether a bed's value is worth a Volume write: it moved bedEpsilon, or it just reached its target.
local function changed(value: number, written: number, target: number): boolean
	return math.abs(value - written) > WAX.bedEpsilon or (value == target and written ~= target)
end

-- Public: pure

function KneadAudio.burst(E: number, intact: number, rng: Random): Shot
	local energies, intacts = WAX.burstEnergies, WAX.burstIntacts
	local e = nearestLog(energies, E)
	local i = nearest(intacts, intact)
	local variant = math.min(WAX.burstVariants - 1, math.floor(rng:NextNumber() * WAX.burstVariants))
	local slot = ((e - 1) * #intacts + (i - 1)) * WAX.burstVariants + variant
	local volume = 10 ^ (WAX.energyDb * (E - energies[e]) / 20) * intactShare(intact) / intactShare(intacts[i])
	return {
		start = slot * WAX.burstSlot,
		length = WAX.burstSlot,
		volume = volume,
		speed = between(rng, WAX.burstSpeedMin, WAX.burstSpeedMax),
		delay = 0,
	}
end

function KneadAudio.grain(index: number): (number, number)
	return WAX.grainStart + index * WAX.grainSlot, WAX.grainSlot
end

function KneadAudio.tap(index: number): (number, number)
	return WAX.tapStart + index * WAX.tapSlot, WAX.tapSlot
end

-- n ticks from `delay` over `span` s at `gain` (design: squish.js:874-876).
local function ticks(n: number, delay: number, span: number, gain: number, feelGain: number, rng: Random): { Shot }
	local shots: { Shot } = {}
	for _ = 1, n do
		local u = rng:NextNumber()
		local grain = math.min(WAX.tickGrains - 1, math.floor(rng:NextNumber() * WAX.tickGrains))
		local volume = gain * feelGain * between(rng, WAX.tickGainMin, 1) * (1 - WAX.tickFade * u) / WAX.grainGain
		local start, length = KneadAudio.grain(grain)
		table.insert(shots, {
			start = start,
			length = length,
			volume = volume,
			speed = between(rng, WAX.tickSpeedMin, WAX.tickSpeedMax),
			delay = delay + u ^ WAX.tickPower * span,
		})
	end
	return shots
end

function KneadAudio.release(brush: string, amount: number, feelGain: number, rng: Random): { Shot }
	local n = (if brush == "finger" then WAX.releaseFinger else WAX.releasePress)
		+ (if rng:NextNumber() < WAX.releaseExtraChance then 1 else 0)
	return ticks(n, WAX.releaseDelay, WAX.releaseSpan, WAX.releaseGain * (0.5 + 0.5 * amount), feelGain, rng)
end

function KneadAudio.air(amount: number, rise: number, feelGain: number, rng: Random): { Shot }
	local n = math.floor(between(rng, WAX.airMin, WAX.airMax) * (0.5 + 0.5 * amount) + 0.5)
	local span = math.min(WAX.airSpanMax, WAX.airSpanRise * rise)
	return ticks(n, WAX.airDelay, span, WAX.airGain * amount, feelGain, rng)
end

function KneadAudio.press(brush: string, pitch: number, rng: Random): ({ Shot }, number?)
	local root = math.sqrt(pitch)
	local function tapShot(gain: number, speedMin: number, speedMax: number, delay: number): Shot
		local index = math.min(WAX.tapCount - 1, math.floor(rng:NextNumber() * WAX.tapCount))
		local start, length = KneadAudio.tap(index)
		if delay < 0 then
			delay = PRESS_LEAD + between(rng, WAX.pressGapMin, WAX.pressGapMax)
		end
		return {
			start = start,
			length = length,
			volume = gain / WAX.tapGain,
			speed = root * between(rng, speedMin, speedMax),
			delay = delay,
		}
	end
	if brush == "finger" then
		return { tapShot(WAX.fingerTap, WAX.fingerSpeedMin, WAX.fingerSpeedMax, PRESS_LEAD) }, nil
	end
	local first = tapShot(WAX.pressTapA, WAX.pressSpeedAMin, WAX.pressSpeedAMax, PRESS_LEAD)
	local second = tapShot(WAX.pressTapB, WAX.pressSpeedBMin, WAX.pressSpeedBMax, -1)
	return { first, second }, pitch
end

function KneadAudio.beds(feelGain: number, drive: number, press: number, intact: number): (number, number)
	local haze = feelGain * WAX.hazeGain * drive * (WAX.hazeBase + (1 - WAX.hazeBase) * intact)
	local body = feelGain
		* WAX.bodyGain
		* math.min(1, WAX.bodyDrive * drive + WAX.bodyPress * press)
		* (WAX.bodyBase + WAX.bodyWorn * (1 - intact))
	return haze, body
end

function KneadAudio.ease(current: number, target: number, tau: number, dt: number): number
	if dt <= 0 or current == target then
		return current
	end
	return current + (target - current) * (1 - math.exp(-dt / tau))
end

-- Public: the player

function KneadAudio.new(feel: string, pitch: number, options: Options?): Audio
	local key = if WAX.gain[feel] ~= nil then feel else DEFAULT_FEEL
	local opts: Options = options or {}
	local data: AudioData = {
		_player = opts.player or SoundController :: any,
		_rng = opts.rng or Random.new(),
		_feel = key,
		_pitch = pitch,
		_gain = WAX.gain[key],
		_rise = FEELS[key].rise,
		_sheet = KEY_SHEET .. key,
		_sheetLevel = level(WAX.sheetLevelDb[key]) * WAX.trim,
		_loopLevel = level(WAX.loopLevelDb) * WAX.busGain * WAX.masterGain * WAX.trim,
		_haze = nil,
		_body = nil,
		_bedsTried = false,
		_hazeValue = 0,
		_bodyValue = 0,
		_hazeWritten = 0,
		_bodyWritten = 0,
		_wax = if opts.wax == nil then Config.Wax.enabled else opts.wax,
		_dead = false,
	}
	return setmetatable(data, AudioClass)
end

-- One sheet region now or after its delay.
function AudioClass._shot(self: Audio, shot: Shot)
	local function play()
		if self._dead then
			return
		end
		self._player.play(self._sheet, {
			group = GROUP,
			region = NumberRange.new(shot.start, shot.start + shot.length),
			volume = self._sheetLevel * shot.volume,
			pitch = shot.speed,
		})
	end
	if shot.delay < FRAME then
		play()
	else
		task.delay(shot.delay, play)
	end
end

function AudioClass._shots(self: Audio, shots: { Shot })
	for _, shot in shots do
		self:_shot(shot)
	end
end

function AudioClass._one(self: Audio, key: string, volume: number, speed: number)
	if self._dead then
		return
	end
	self._player.play(key, { group = GROUP, volume = volume * WAX.trim, pitch = speed })
end

function AudioClass.crack(self: Audio, E: number, intact: number)
	if self._dead or not self._wax then
		return
	end
	self:_shot(KneadAudio.burst(E, intact, self._rng))
end

-- User 2026-10-12: with the wax off a press let go plays the soft slime let-go, louder the deeper the press was:
-- letGoFloor + (1 - letGoFloor)·amount (Config.Audio.kneadSoft).
function AudioClass._letGo(self: Audio, amount: number)
	if self._dead then
		return
	end
	local floor = SOFT.letGoFloor
	self._player.play(KEY_LET_GO, {
		group = LET_GO_GROUP,
		volume = floor + (1 - floor) * math.clamp(amount, 0, 1),
		pitch = self._pitch,
	})
end

-- With the wax off (user 2026-10-12) a press let go plays the soft slime let-go instead of the release ticks; the
-- settling ticks (crackle grains) and the snap's bursts stay silent; the press (its taps and thump) and the snap thump
-- still play.
function AudioClass.event(self: Audio, e: Event)
	if self._dead then
		return
	end
	local kind = e.kind
	local rng = self._rng
	local wax = self._wax
	if kind == "press" then
		local shots, thump = KneadAudio.press(e.brush or "finger", self._pitch, rng)
		self:_shots(shots)
		if thump then
			self:_one(KEY_THUMP, level(WAX.thumpLevelDb), thump)
		end
	elseif kind == "release" then
		if wax then
			self:_shots(KneadAudio.release(e.brush or "finger", e.amount or 1, self._gain, rng))
		else
			self:_letGo(e.amount or 1)
		end
	elseif kind == "air" and wax then
		self:_shots(KneadAudio.air(e.amount or 1, self._rise, self._gain, rng))
	elseif kind == "snap" then
		local a = e.amount or 0
		if wax then
			self:_shot(KneadAudio.burst(WAX.snapE + a, 1, rng))
			local echo = KneadAudio.burst(WAX.echoE + WAX.echoShare * a, 1, rng)
			echo.delay = WAX.echoDelay
			self:_shot(echo)
		end
		self:_one(KEY_SNAP_THUMP, level(WAX.snapThumpLevelDb) * (0.5 + a), self._pitch)
	end
end

function AudioClass.rewax(self: Audio)
	if not self._wax then
		return -- no re-wax sparkle with the wax off (user 2026-10-12)
	end
	self:_one(KEY_REWAX, level(WAX.rewaxLevelDb), 1)
end

function AudioClass.frame(self: Audio, dt: number, active: boolean, drive: number, press: number, intact: number)
	if self._dead then
		return
	end
	if active and not self._bedsTried then
		self._bedsTried = true
		local rng = self._rng
		if self._wax then -- no crackle haze with the wax off (user 2026-10-12)
			self._haze = self._player.playLoop(
				KEY_HAZE .. self._feel,
				{ group = GROUP, volume = 0, timePosition = rng:NextNumber() * WAX.startMax }
			)
		end
		self._body = self._player.playLoop(
			KEY_BODY .. self._feel,
			{ group = GROUP, volume = 0, timePosition = rng:NextNumber() * WAX.startMax }
		)
	end
	local hazeTarget, bodyTarget = 0, 0
	local hazeTau, bodyTau = WAX.quietHazeTau, WAX.quietBodyTau
	if active then
		hazeTarget, bodyTarget = KneadAudio.beds(self._gain, drive, press, intact)
		hazeTau, bodyTau = WAX.hazeTau, WAX.bodyTau
	end
	self._hazeValue = settle(KneadAudio.ease(self._hazeValue, hazeTarget, hazeTau, dt), hazeTarget)
	self._bodyValue = settle(KneadAudio.ease(self._bodyValue, bodyTarget, bodyTau, dt), bodyTarget)
	local haze, body = self._haze, self._body
	if haze and changed(self._hazeValue, self._hazeWritten, hazeTarget) then
		self._hazeWritten = self._hazeValue
		haze:setVolume(self._hazeValue * self._loopLevel)
	end
	if body and changed(self._bodyValue, self._bodyWritten, bodyTarget) then
		self._bodyWritten = self._bodyValue
		body:setVolume(self._bodyValue * self._loopLevel)
	end
end

function AudioClass.destroy(self: Audio)
	if self._dead then
		return
	end
	self._dead = true
	for _, loop in { self._haze, self._body } do
		if loop then
			loop:stop()
		end
	end
	self._haze, self._body = nil, nil
end

return KneadAudio
