--!strict
-- SquishRig (client only, pure): one squishy's procedural animation as plain numbers (squishy overhaul spec
-- 2026-10-09 §3.2). It turns a blueprint's `motion` row and events (taps, presses, kicks, face locks, flight) into the
-- values Anim/SquishDeformer:apply(out) writes. No instances, connections, threads or clock reads: the owner passes dt
-- (clamped to Config.Anim.Scheduler.maxDt, as the Scheduler does). Deterministic for a seed (the blink intervals are
-- its only randomness). Exactly one owner steps a rig, once a frame, into its own `out` table.
--
-- API
--   SquishRig.new(motion, options?) -> rig
--     options: axis (the Catalog squeezeAxis, default "Y"), rarity (default "Common"), reduced (ReducedMotion), seed,
--     sections (the blueprint's sections map), foamRecoveryT (Catalog anim.foamRecoveryT, for ReducedMotion), blink
--     (false = never blinks; also setBlink).
--   rig:tap()                    a squeeze: press now, release at timing.releaseStartMs; restarts from the current
--                                state (every click pays, no jump)
--   rig:press(axis?) / rig:release()   press-and-hold (Inspect's hold; the first-person hand, one hand on "Y" in step 2)
--   rig:endPress()               a press let go before the release start becomes exactly a tap (popStart =
--                                releaseStartMs, popEnd = popEndMs, the Grip rule as seen at the press); later it is
--                                release(); nothing outside a press (first-person spec 2026-10-10 §3.5)
--   rig:setAxis(axis) / rig:axis()   the default squeeze axis (tap, press); a change, here or by press(axis), takes
--                                effect only at rest (no hold, no squeeze playing, every shown scale within
--                                AXIS_SWITCH_SLACK of 1), so it never jumps; until then the current axis carries on and
--                                a press uses it. axis() is the axis it squeezes on now (first-person spec §3.4)
--   rig:squeezeY()               the squeeze channel now (y on the squeeze axis before the jiggle; the hold included)
--   rig:hold(c) / rig:clearHold()      an outside squeeze value set directly (the throw windup's c 0.90): no spring,
--                                no events, no arm sync (pressAmount 0); clearHold recovers with the toy's spring
--   rig:kick(j, cap?)            feel jiggle (movement, landing): the shown squash peaks at j × the feel gain; the
--                                jiggle is shown at most ±cap (default Config.Anim.held.motionJiggle.maxJ)
--   rig:hit(strength?)           the hit boing: the squish face for face.hitSeconds and a squash peaking at
--                                hitKick × strength whatever the gain (cap Kit.JIGGLE_CAP)
--   rig:setFace(state, seconds?) lock "squish" or "wow" for `seconds` (nil = until setFace("normal"), which unlocks)
--   rig:flight(style?) / rig:clearFlight()   roll, nod and pulse from flightPose, section flaps, the squish face
--   rig:setReduced(on), rig:setDetail("hero" | "near" | "far"), rig:setBlink(on)
--   rig:reset()                  back to rest (pool return, tier drop): every channel, spring, lock and flight
--   rig:step(dt, out)            advances and fills `out` (SquishRig.newOut(); no table is made per step)
--   rig:isRecovering()           the current squeeze passed its pop end (a tap now restarts; before it, it merges)
--   rig:isAwake()                anything away from rest now (after a step, what out.awake says); every input above
--                                makes it true at once, so an owner may skip a sleeping "far" rig's frames (no blink
--                                clock runs there; HeldSquishyController.farStride)
--   rig:elapsedMs()              ms into the current squeeze (nil when none plays)
--   rig.timing                   { anticipationEndMs, peakMs, releaseStartMs, popEndMs } for its rarity
--   SquishRig.EVENTS             out.events bits: squish (anticipation end), peak (puffs), releaseStart, popEnd (the
--                                release sound and pop). Several in one step are all set; their order is this order.
--   SquishRig.timingFor(rarity), newOut(), sectionNames(sections), recoverySpring(squeeze), feelSpring(feel),
--   releaseKick(feel, rarity), extremes(motion, axis), framingWidening(motion, axis),
--   flightPose(style, t, reduced, amp?, pulsePeak?) -> (roll, nod, pulse, flapPhase)
--
-- out: S (squeeze × jiggle, pivot space, clamped like the deformer), twist (radians about the squeeze axis), face,
--   blink (the eye's Y factor: 1 open, down to blink.closedY shut), cheek (puff factor), sections (signed angle in
--   radians per slot, slots in sectionNames order), sectionsOn (hero detail, not reduced, the toy has sections), roll /
--   nod / pulse (flight; 0, 0, 1 otherwise), awake (anything away from rest), pressAmount (arm sync 0-1), events.
--
-- Squeeze (the single source is Config.Anim.squeeze.phases): the press is the phases but the last, the pop is the last
-- phase, each phase's c scaled to the toy, c' = 1 - (1 - c)(1 - depth)/(1 - deepest c), w = 1 + (1 - c')·widen (as
-- Kit.extremes); the "widening" phase is the flourish's wideningExtraMs longer. A tap starts from the current (y, w)
-- and twist. At the pop end the toy's release spring takes over (ω = √kRel, ζ = cRel/(2ω), from rest), with a release
-- kick on the feel jiggle; under ReducedMotion the recovery is today's SmoothDamp with foamRecoveryT and nothing jiggles,
-- twists, bounces, blinks or flaps. An early release() pops from where it is (never down to the pop value).
-- Twist (Uncommon, Epic): one half-swing twistDeg·sin(πu), u over [anticipation end, peak]; a restart fades the old
-- twist out over the anticipation. Exclusive: a section flare kick at the release start.
-- Face: squish below face.squishBelow, back above squishAbove (y on the squeeze axis, hold included), each state held
-- >= minHoldSeconds. Priority: a squish lock, then the squeeze's squish, then a wow lock, then normal. Grip rule: a tap
-- (or a press) while the face is squish keeps it until the recovery passes squishAbove with no newer tap.
-- Sections: a spring (Config.Anim.rig.sections) toward maxRad·tanh(-v·amp·gain/maxRad), v = d/dt of the shown
-- squeeze-axis scale, never clamped; out = angle × sign. In flight a section with a flap size (its flap.deg, else the
-- style's flapDeg) follows sign·flap·sin(flapPhase + flap.phase) instead (flap.phase in radians).
-- Detail: "near" drops the sections, "far" also the face states, blinks, cheeks and the jiggle.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Kit = require(Shared.Art.SquishyBlueprints.Kit)
local Spring = require(Shared.Util.Spring)
local OrbitCamera = require(script.Parent.Parent.UI.OrbitCamera)

-- Types

export type Axis = "X" | "Y" | "Z"
export type Face = "normal" | "squish" | "wow"
export type Detail = "hero" | "near" | "far"
export type Motion = Kit.Motion
export type Section = Kit.Section
export type Extreme = Kit.Extreme

export type Options = {
	axis: Axis?,
	rarity: string?,
	reduced: boolean?,
	seed: number?,
	sections: { [string]: Section }?,
	foamRecoveryT: number?,
	blink: boolean?,
}

export type Out = {
	S: Vector3,
	twist: number,
	face: Face,
	blink: number,
	cheek: number,
	sections: { number },
	sectionsOn: boolean,
	roll: number,
	nod: number,
	pulse: number,
	awake: boolean,
	pressAmount: number,
	events: number,
}

export type Timing = { anticipationEndMs: number, peakMs: number, releaseStartMs: number, popEndMs: number }

type Key = { startMs: number, endMs: number, c: number, style: Enum.EasingStyle, dir: Enum.EasingDirection }

type RigData = {
	timing: Timing,
	_motion: Motion,
	_axis: Axis,
	_curAxis: Axis,
	_wantAxis: Axis, -- the axis the next rest switches to (setAxis, press(axis), tap)
	_depth: number,
	_widen: number,
	_keys: { Key },
	_keyY: { number },
	_keyW: { number },
	_recOmega: number,
	_recZeta: number,
	_foamT: number,
	_feelOmega: number,
	_feelZeta: number,
	_gain: number,
	_kickVelocity: number, -- jiggle velocity per unit of first peak
	_releasePeak: number,
	_twistRad: number,
	_flareVelocity: number,
	_reduced: boolean,
	_detail: Detail,
	_blinkOn: boolean,
	-- squeeze
	_mode: number,
	_tMs: number,
	_holding: boolean,
	_y0: number,
	_w0: number,
	_twist0: number,
	_twist: number,
	_popStart: number,
	_popFromY: number,
	_popFromW: number,
	_popToY: number,
	_popToW: number,
	_evSquish: number,
	_evPeak: number,
	_evRelease: number,
	_evPopEnd: number,
	_fired: number,
	_y: number,
	_w: number,
	_vy: number,
	_vw: number,
	_hold: number?,
	-- jiggle
	_r: number,
	_vr: number,
	_rCap: number,
	-- sections (arrays by slot)
	_secCount: number,
	_secSign: { number },
	_secAmp: { number },
	_secMax: { number },
	_secFlap: { number }, -- radians; -1 = the flight style's flapDeg
	_secPhase: { number },
	_secA: { number },
	_secV: { number },
	_lastShown: number,
	_lastAcross: number,
	-- face
	_lock: Face?,
	_lockLeft: number,
	_flightLock: boolean,
	_squishOn: boolean,
	_sinceToggle: number,
	_grip: boolean,
	_face: Face,
	-- blink
	_rng: Random,
	_blinkIn: number,
	_blinkT: number, -- seconds into the blink, -1 = not blinking
	-- flight
	_flightStyle: string?,
	_flightT: number,
}

-- Constants

local TAU = 2 * math.pi
local ANIM = Config.Anim
local SQUEEZE = ANIM.squeeze
local RIG = ANIM.rig
local FACE = RIG.face
local BLINK = RIG.blink
local LOOKS = RIG.looks
local SECTIONS = RIG.sections
local FLIGHT = RIG.flight
local FRAMING = Config.Inspect.Framing
local SCALE_MIN = ANIM.deform.scaleMin
local SCALE_MAX = ANIM.deform.scaleMax
local REST_EPSILON = ANIM.deform.restEpsilon
local ANGLE_EPSILON = ANIM.deform.twistEpsilon
local MAX_DT = ANIM.Scheduler.maxDt
local SUBSTEP = ANIM.Scheduler.springSubstep
local MOVE_CAP = ANIM.held.motionJiggle.maxJ
local HIT_CAP = Kit.JIGGLE_CAP
local DEFAULT_FOAM_T = (SQUEEZE.foamRecoveryMin + SQUEEZE.foamRecoveryMax) / 2
local SECTION_OMEGA = math.sqrt(SECTIONS.k)
local SECTION_ZETA = SECTIONS.c / (2 * SECTION_OMEGA)
local DETAILS: { [string]: boolean } = { hero = true, near = true, far = true }
-- An axis switch waits until every shown scale is within this of 1, so it moves no axis by more than twice this.
local AXIS_SWITCH_SLACK = 0.01

local MODE_IDLE = 0
local MODE_SQUEEZE = 1 -- the press keyframes, the hold at depth (press) and the release pop
local MODE_RECOVER = 2

local EVENT_SQUISH = 1
local EVENT_PEAK = 2
local EVENT_RELEASE = 4
local EVENT_POP_END = 8

-- Module table

local RigClass = {}
RigClass.__index = RigClass

export type Rig = typeof(setmetatable({} :: RigData, RigClass))

local SquishRig = {}

SquishRig.EVENTS = table.freeze({
	squish = EVENT_SQUISH,
	peak = EVENT_PEAK,
	releaseStart = EVENT_RELEASE,
	popEnd = EVENT_POP_END,
})

-- Private

local keysCache: { [number]: { Key } } = {}
local timingCache: { [number]: Timing } = {}
local seedCounter = 0

local function flourishOf(rarity: string?): any
	return SQUEEZE.flourish[rarity or "Common"] or SQUEEZE.flourish.Common
end

-- The Config phases with the widening phase (and everything after it) extraMs later.
local function keysFor(extraMs: number): { Key }
	local cached = keysCache[extraMs]
	if cached then
		return cached
	end
	local keys: { Key } = {}
	local shift = 0
	for _, phase in SQUEEZE.phases do
		local startMs = phase.startMs + shift
		if phase.name == "widening" then
			shift += extraMs
		end
		table.insert(keys, {
			startMs = startMs,
			endMs = phase.endMs + shift,
			c = phase.c,
			style = phase.style,
			dir = phase.direction,
		})
	end
	keysCache[extraMs] = keys
	return keys
end

local function timingOf(extraMs: number): Timing
	local cached = timingCache[extraMs]
	if cached then
		return cached
	end
	local keys = keysFor(extraMs)
	local peakC, peakMs = math.huge, 0
	for _, key in keys do
		if key.c < peakC then
			peakC, peakMs = key.c, key.endMs
		end
	end
	local last = keys[#keys]
	local timing = table.freeze({
		anticipationEndMs = keys[1].endMs,
		peakMs = peakMs,
		releaseStartMs = last.startMs,
		popEndMs = last.endMs,
	})
	timingCache[extraMs] = timing
	return timing
end

local function deepestC(): number
	local deepest = math.huge
	for _, phase in SQUEEZE.phases do
		deepest = math.min(deepest, phase.c)
	end
	return deepest
end

-- The kick velocity that makes a spring at rest peak at 1 on its first swing.
local function peakVelocity(omega: number, zeta: number): number
	if zeta >= 1 then
		return omega * math.exp(1)
	end
	local damped = math.sqrt(1 - zeta * zeta)
	local peakAt = math.atan2(damped, zeta) / (omega * damped)
	return omega * math.exp(zeta * omega * peakAt)
end

local function clampScale(x: number): number
	return math.clamp(x, SCALE_MIN, SCALE_MAX)
end

local function axisScale(along: number, across: number, axis: Axis): Vector3
	if axis == "X" then
		return Vector3.new(along, across, across)
	elseif axis == "Y" then
		return Vector3.new(across, along, across)
	end
	return Vector3.new(across, across, along)
end

-- Advances one spring by `seconds` in substeps of at most Config.Anim.Scheduler.springSubstep.
local function integrate(x: number, v: number, target: number, omega: number, zeta: number, seconds: number)
	local steps = math.max(1, math.ceil(seconds / SUBSTEP - 1e-9))
	local h = seconds / steps
	for _ = 1, steps do
		x, v = Spring.integrate(x, v, target, omega, zeta, h)
	end
	return x, v
end

local function zeroJiggle(self: Rig)
	self._r, self._vr, self._rCap = 0, 0, MOVE_CAP
end

local function zeroSections(self: Rig)
	for i = 1, self._secCount do
		self._secA[i], self._secV[i] = 0, 0
	end
end

local function nextBlinkIn(self: Rig): number
	return self._rng:NextNumber(BLINK.minSeconds, BLINK.maxSeconds)
end

-- Takes a waiting axis change only at rest: no hold, no squeeze playing and the shown scales (along, across) within
-- AXIS_SWITCH_SLACK of 1, so the shown S never jumps (first-person spec 2026-10-10 §3.4).
local function switchAxisAtRest(self: Rig, along: number, across: number)
	if
		self._curAxis ~= self._wantAxis
		and self._hold == nil
		and self._mode ~= MODE_SQUEEZE
		and math.abs(along - 1) <= AXIS_SWITCH_SLACK
		and math.abs(across - 1) <= AXIS_SWITCH_SLACK
	then
		self._curAxis = self._wantAxis
	end
end

local function startSqueeze(self: Rig, holding: boolean)
	local timing = self.timing
	local keys, last = self._keys, #self._keys
	self._hold = nil
	self._mode = MODE_SQUEEZE
	self._tMs = 0
	self._holding = holding
	self._y0, self._w0 = self._y, self._w
	self._twist0 = if self._reduced then 0 else self._twist
	self._vy, self._vw = 0, 0
	self._fired = 0
	self._evSquish = timing.anticipationEndMs
	self._evPeak = timing.peakMs
	local popStart = if holding then math.huge else timing.releaseStartMs
	self._popStart = popStart
	self._evRelease = popStart
	self._evPopEnd = popStart + (keys[last].endMs - keys[last].startMs)
	self._popFromY, self._popFromW = self._keyY[last - 1], self._keyW[last - 1]
	self._popToY, self._popToW = self._keyY[last], self._keyW[last]
end

-- The press keyframes (every phase but the last) at tMs, from (y0, w0); past them, the last press key.
local function pressAt(self: Rig, tMs: number): (number, number)
	local keys = self._keys
	local count = #keys - 1
	for i = 1, count do
		local key = keys[i]
		if tMs < key.endMs then
			local fromY = if i == 1 then self._y0 else self._keyY[i - 1]
			local fromW = if i == 1 then self._w0 else self._keyW[i - 1]
			local span = key.endMs - key.startMs
			local u = if span > 0 then math.clamp((tMs - key.startMs) / span, 0, 1) else 1
			local alpha = TweenService:GetValue(u, key.style, key.dir)
			return fromY + (self._keyY[i] - fromY) * alpha, fromW + (self._keyW[i] - fromW) * alpha
		end
	end
	return self._keyY[count], self._keyW[count]
end

local function recover(self: Rig, seconds: number)
	if seconds <= 0 then
		return
	end
	if self._reduced then
		self._y, self._vy = OrbitCamera.smoothDamp(self._y, 1, self._vy, self._foamT, seconds)
		self._w, self._vw = OrbitCamera.smoothDamp(self._w, 1, self._vw, self._foamT, seconds)
	else
		self._y, self._vy = integrate(self._y, self._vy, 1, self._recOmega, self._recZeta, seconds)
		self._w, self._vw = integrate(self._w, self._vw, 1, self._recOmega, self._recZeta, seconds)
	end
	if
		math.abs(self._y - 1) < REST_EPSILON
		and math.abs(self._w - 1) < REST_EPSILON
		and math.abs(self._vy) < REST_EPSILON
		and math.abs(self._vw) < REST_EPSILON
	then
		self._y, self._w, self._vy, self._vw = 1, 1, 0, 0
		self._mode = MODE_IDLE
	end
end

local function fireEvents(self: Rig, tMs: number): number
	local fired = self._fired
	local events = 0
	if bit32.band(fired, EVENT_SQUISH) == 0 and tMs >= self._evSquish then
		events = bit32.bor(events, EVENT_SQUISH)
	end
	if bit32.band(fired, EVENT_PEAK) == 0 and tMs >= self._evPeak then
		events = bit32.bor(events, EVENT_PEAK)
	end
	if bit32.band(fired, EVENT_RELEASE) == 0 and tMs >= self._evRelease then
		events = bit32.bor(events, EVENT_RELEASE)
	end
	if bit32.band(fired, EVENT_POP_END) == 0 and tMs >= self._evPopEnd then
		events = bit32.bor(events, EVENT_POP_END)
	end
	self._fired = bit32.bor(fired, events)
	return events
end

-- One step of the squeeze channel (y, w). Returns the events crossed.
local function stepSqueeze(self: Rig, h: number): number
	local hold = self._hold
	if hold ~= nil then
		self._y, self._w = hold, 1 + (1 - hold) * self._widen
		return 0
	end
	if self._mode == MODE_RECOVER then
		self._tMs += h * 1000
		recover(self, h)
		return 0
	elseif self._mode ~= MODE_SQUEEZE then
		return 0
	end
	local tMs = self._tMs + h * 1000
	self._tMs = tMs
	local events = fireEvents(self, tMs)
	if tMs >= self._evPopEnd then
		-- The pop is over: the release spring takes over from rest, with the release kick on the jiggle.
		self._y, self._w, self._vy, self._vw = self._popToY, self._popToW, 0, 0
		self._mode = MODE_RECOVER
		if not self._reduced and self._detail ~= "far" then
			self._vr -= self._releasePeak * self._kickVelocity
		end
		recover(self, (tMs - self._evPopEnd) / 1000)
	elseif tMs >= self._popStart then
		local last = self._keys[#self._keys]
		local span = self._evPopEnd - self._popStart
		local u = if span > 0 then math.clamp((tMs - self._popStart) / span, 0, 1) else 1
		local alpha = TweenService:GetValue(u, last.style, last.dir)
		self._y = self._popFromY + (self._popToY - self._popFromY) * alpha
		self._w = self._popFromW + (self._popToW - self._popFromW) * alpha
	else
		self._y, self._w = pressAt(self, tMs)
	end
	return events
end

local function twistAt(self: Rig): number
	if self._reduced or self._hold ~= nil or self._mode == MODE_IDLE then
		return 0
	end
	local timing = self.timing
	local tMs = self._tMs
	local from = timing.anticipationEndMs
	local twist = 0
	if self._twist0 ~= 0 and tMs < from then
		twist = self._twist0 * (1 - math.max(tMs, 0) / from)
	end
	if self._twistRad ~= 0 then
		local u = (tMs - from) / math.max(timing.peakMs - from, 1)
		if u >= 0 and u <= 1 then
			twist += self._twistRad * math.sin(math.pi * u)
		end
	end
	return twist
end

local function stepJiggle(self: Rig, h: number): number
	if self._r == 0 and self._vr == 0 then
		return 0
	end
	if h > 0 then
		self._r, self._vr = integrate(self._r, self._vr, 0, self._feelOmega, self._feelZeta, h)
	end
	if math.abs(self._r) < REST_EPSILON and math.abs(self._vr) < REST_EPSILON then
		zeroJiggle(self)
		return 0
	end
	return math.clamp(self._r, -self._rCap, self._rCap)
end

local function stepFace(self: Rig, h: number): Face
	if self._lock ~= nil and self._lockLeft ~= math.huge then
		self._lockLeft -= h
		if self._lockLeft <= 0 then
			self._lock = nil
		end
	end
	self._sinceToggle += h
	local y = self._y
	if self._grip and self._mode ~= MODE_SQUEEZE and y > FACE.squishAbove then
		self._grip = false
	end
	if self._squishOn then
		if y > FACE.squishAbove and not self._grip and self._sinceToggle >= FACE.minHoldSeconds then
			self._squishOn, self._sinceToggle = false, 0
		end
	elseif y < FACE.squishBelow and self._sinceToggle >= FACE.minHoldSeconds then
		self._squishOn, self._sinceToggle = true, 0
	end
	local face: Face = "normal"
	if self._lock == "squish" or self._squishOn then
		face = "squish"
	elseif self._lock == "wow" then
		face = "wow"
	end
	if self._detail == "far" then
		face = "normal"
	end
	self._face = face
	return face
end

local function stepBlink(self: Rig, h: number): number
	if not self._blinkOn or self._reduced or self._detail == "far" then
		self._blinkT = -1
		return 1
	end
	if self._blinkT >= 0 then
		self._blinkT += h
		if self._blinkT >= BLINK.seconds then
			self._blinkT = -1
			self._blinkIn = nextBlinkIn(self)
		end
	else
		self._blinkIn -= h
		if self._blinkIn <= 0 then
			self._blinkT = -self._blinkIn
		end
	end
	if self._blinkT < 0 then
		return 1
	end
	return math.max(BLINK.closedY, math.abs(1 - self._blinkT / (BLINK.seconds / 2)))
end

-- Sections into out.sections; returns whether any is away from rest.
local function stepSections(
	self: Rig,
	h: number,
	speed: number,
	events: number,
	flapPhase: number,
	out: { number },
	active: boolean
): boolean
	local count = self._secCount
	if not active then
		for i = 1, count do
			out[i] = 0
		end
		return false
	end
	local style = if self._flightStyle then FLIGHT[self._flightStyle :: string] else nil
	local styleFlap = if style and style.flapHz and style.flapDeg then math.rad(style.flapDeg) else 0
	local flare = if bit32.band(events, EVENT_RELEASE) ~= 0 then self._flareVelocity else 0
	local moving = false
	for i = 1, count do
		local a, v = self._secA[i], self._secV[i] - flare
		local flap = if style and style.flapHz
			then (if self._secFlap[i] >= 0 then self._secFlap[i] else styleFlap)
			else 0
		if flap > 0 then
			a, v = flap * math.sin(flapPhase + self._secPhase[i]), 0
		else
			local maxRad = self._secMax[i]
			local target = maxRad * math.tanh(-speed * self._secAmp[i] * SECTIONS.gain / maxRad)
			-- At rest with no pull the spring would give exactly 0, 0 again: skip it (a resting hero rig's sections).
			if h > 0 and not (a == 0 and v == 0 and target == 0) then
				a, v = integrate(a, v, target, SECTION_OMEGA, SECTION_ZETA, h)
			end
			if math.abs(a) < ANGLE_EPSILON and math.abs(v) < ANGLE_EPSILON and math.abs(target) < ANGLE_EPSILON then
				a, v = 0, 0
			end
		end
		self._secA[i], self._secV[i] = a, v
		out[i] = a * self._secSign[i]
		moving = moving or a ~= 0 or v ~= 0
	end
	return moving
end

-- Rig methods

function RigClass.tap(self: Rig)
	local squished = self._face == "squish"
	self._wantAxis = self._axis
	switchAxisAtRest(self, self._lastShown, self._lastAcross)
	startSqueeze(self, false)
	if squished then
		self._grip = true -- Grip rule: repeated taps keep the squish face
	end
end

function RigClass.press(self: Rig, axis: Axis?)
	local squished = self._face == "squish"
	self._wantAxis = axis or self._axis
	switchAxisAtRest(self, self._lastShown, self._lastAcross)
	startSqueeze(self, true)
	if squished then
		self._grip = true -- as tap(), so a press let go early (endPress) is exactly a tap
	end
end

function RigClass.endPress(self: Rig)
	if self._mode ~= MODE_SQUEEZE or not self._holding then
		return
	end
	local releaseStart = self.timing.releaseStartMs
	if self._tMs >= releaseStart then
		self:release() -- past the release start a tap would already be popping: pop from where it is
		return
	end
	-- The tap's timeline from here on (startSqueeze with holding = false).
	local last = self._keys[#self._keys]
	self._holding = false
	self._popStart = releaseStart
	self._evRelease = releaseStart
	self._evPopEnd = releaseStart + (last.endMs - last.startMs)
end

function RigClass.setAxis(self: Rig, axis: Axis)
	self._axis = axis
	self._wantAxis = axis
	switchAxisAtRest(self, self._lastShown, self._lastAcross)
end

function RigClass.axis(self: Rig): Axis
	return self._curAxis
end

function RigClass.squeezeY(self: Rig): number
	return self._y
end

function RigClass.release(self: Rig)
	if self._mode ~= MODE_SQUEEZE or not self._holding then
		return
	end
	self._holding = false
	local now = self._tMs
	local last = self._keys[#self._keys]
	self._popStart = now
	self._evRelease = now
	self._evPopEnd = now + (last.endMs - last.startMs)
	self._evSquish = math.min(self._evSquish, now)
	self._evPeak = math.min(self._evPeak, now)
	self._popFromY, self._popFromW = self._y, self._w
	if self._y >= self._popToY then
		self._popToY, self._popToW = self._y, self._w -- released early: it never squeezes down to the pop
	end
end

function RigClass.hold(self: Rig, c: number)
	if c ~= c then
		return
	end
	local value = math.clamp(c, SCALE_MIN, SCALE_MAX)
	self._hold = value
	self._mode = MODE_IDLE
	self._y, self._w, self._vy, self._vw = value, 1 + (1 - value) * self._widen, 0, 0
end

function RigClass.clearHold(self: Rig)
	if self._hold == nil then
		return
	end
	self._hold = nil
	self._mode = MODE_RECOVER
	self._tMs = self.timing.popEndMs
	self._fired = bit32.bor(EVENT_SQUISH, EVENT_PEAK, EVENT_RELEASE, EVENT_POP_END)
	self._vy, self._vw = 0, 0
end

function RigClass.kick(self: Rig, j: number, cap: number?)
	if self._reduced or self._detail == "far" or j ~= j or j == 0 then
		return
	end
	self._vr += j * self._gain * self._kickVelocity
	self._rCap = math.max(self._rCap, cap or MOVE_CAP)
end

function RigClass.hit(self: Rig, strength: number?)
	if not (self._lock == "squish" and self._lockLeft == math.huge) then -- an open squish lock (flight) stays
		self:setFace("squish", FACE.hitSeconds)
	end
	if self._reduced or self._detail == "far" then
		return
	end
	local scale = if strength ~= nil and strength == strength then math.max(strength, 0) else 1
	self._vr += RIG.hitKick * scale * self._kickVelocity
	self._rCap = math.max(self._rCap, HIT_CAP)
end

function RigClass.setFace(self: Rig, state: Face, seconds: number?)
	self._flightLock = false
	if state == "normal" then
		self._lock = nil
		return
	end
	assert(state == "squish" or state == "wow", `[SD][SquishRig] unknown face {tostring(state)}`)
	self._lock = state
	self._lockLeft = if seconds ~= nil and seconds == seconds then seconds else math.huge
end

function RigClass.flight(self: Rig, style: string?)
	local name = style or self._motion.flight.style
	self._flightStyle = if FLIGHT[name] then name else "wobble"
	self._flightT = 0
	self._lock = "squish"
	self._lockLeft = math.huge
	self._flightLock = true
end

function RigClass.clearFlight(self: Rig)
	if self._flightStyle == nil then
		return
	end
	self._flightStyle = nil
	if self._flightLock then
		self._lock = nil
		self._flightLock = false
	end
end

function RigClass.setReduced(self: Rig, on: boolean)
	self._reduced = on
	if on then
		zeroJiggle(self)
		zeroSections(self)
		self._twist0 = 0
	end
end

function RigClass.setDetail(self: Rig, level: Detail)
	assert(DETAILS[level] == true, `[SD][SquishRig] unknown detail {tostring(level)}`)
	self._detail = level
	if level ~= "hero" then
		zeroSections(self)
	end
	if level == "far" then
		zeroJiggle(self)
	end
end

function RigClass.setBlink(self: Rig, on: boolean)
	self._blinkOn = on
end

function RigClass.reset(self: Rig)
	self._mode = MODE_IDLE
	self._tMs = 0
	self._holding = false
	self._fired = 0
	self._y, self._w, self._vy, self._vw = 1, 1, 0, 0
	self._hold = nil
	self._twist0, self._twist = 0, 0
	zeroJiggle(self)
	zeroSections(self)
	self._lastShown = 1
	self._lock = nil
	self._flightLock = false
	self._squishOn = false
	self._sinceToggle = math.huge
	self._grip = false
	self._face = "normal"
	self._blinkT = -1
	self._flightStyle = nil
	self._flightT = 0
	self._curAxis = self._axis
	self._wantAxis = self._axis
	self._lastAcross = 1
end

function RigClass.isRecovering(self: Rig): boolean
	return self._mode == MODE_RECOVER
end

function RigClass.isAwake(self: Rig): boolean
	if
		self._mode ~= MODE_IDLE
		or self._hold ~= nil
		or self._r ~= 0
		or self._vr ~= 0
		or self._flightStyle ~= nil
		or self._lock ~= nil
		or self._squishOn
		or self._blinkT >= 0
	then
		return true
	end
	for i = 1, self._secCount do
		if self._secA[i] ~= 0 or self._secV[i] ~= 0 then
			return true
		end
	end
	return false
end

function RigClass.elapsedMs(self: Rig): number?
	return if self._mode == MODE_IDLE then nil else self._tMs
end

function RigClass.step(self: Rig, dt: number, out: Out)
	local h = if dt == dt and dt > 0 then math.min(dt, MAX_DT) else 0
	local events = stepSqueeze(self, h)
	local twist = twistAt(self)
	self._twist = twist
	local jiggle = if self._detail == "far" then 0 else stepJiggle(self, h)

	local y, w = self._y, self._w
	local along = clampScale(y * (1 - jiggle))
	local across = clampScale(w * (1 + jiggle / 2))
	local speed = if h > 0 then (along - self._lastShown) / h else 0
	self._lastShown = along
	self._lastAcross = across
	switchAxisAtRest(self, along, across)

	local roll, nod, pulse, flapPhase = 0, 0, 1, 0
	local style = self._flightStyle
	if style ~= nil then
		self._flightT += h
		local flight = self._motion.flight
		roll, nod, pulse, flapPhase =
			SquishRig.flightPose(style, self._flightT, self._reduced, flight.amp, flight.pulse)
	end

	local sections = out.sections
	if sections == nil then
		sections = table.create(self._secCount, 0)
		out.sections = sections
	end
	local sectionsOn = self._secCount > 0 and self._detail == "hero" and not self._reduced
	local moving = stepSections(self, h, speed, events, flapPhase, sections, sectionsOn)

	local face: Face = stepFace(self, h)
	local blink = stepBlink(self, h)
	local amount = math.clamp((1 - y) / (1 - self._depth), 0, 1)

	out.S = axisScale(along, across, self._curAxis)
	out.twist = twist
	out.face = face
	out.blink = blink
	out.cheek = if self._detail == "far" then 1 else 1 + LOOKS.cheekPuff * amount
	out.sectionsOn = sectionsOn
	out.roll, out.nod, out.pulse = roll, nod, pulse
	out.pressAmount = if self._hold ~= nil then 0 else amount
	out.events = events
	out.awake = self._mode ~= MODE_IDLE
		or self._hold ~= nil
		or jiggle ~= 0
		or self._vr ~= 0
		or moving
		or style ~= nil
		or self._lock ~= nil
		or self._squishOn
		or self._blinkT >= 0
end

-- Public

-- The phase times of a squeeze of that rarity (its widening extra included).
function SquishRig.timingFor(rarity: string?): Timing
	return timingOf(flourishOf(rarity).wideningExtraMs or 0)
end

-- A fresh `out` table for one rig (the owner keeps it and passes it to every step).
function SquishRig.newOut(): Out
	return {
		S = Vector3.one,
		twist = 0,
		face = "normal",
		blink = 1,
		cheek = 1,
		sections = {},
		sectionsOn = false,
		roll = 0,
		nod = 0,
		pulse = 1,
		awake = false,
		pressAmount = 0,
		events = 0,
	}
end

-- The section slots: the names of a blueprint's sections map, sorted (the deformer uses the same order).
function SquishRig.sectionNames(sections: { [string]: Section }?): { string }
	local names: { string } = {}
	if sections then
		for name in sections do
			table.insert(names, name)
		end
		table.sort(names)
	end
	return names
end

-- The toy's release spring: ω = √kRel, ζ = cRel / (2ω).
function SquishRig.recoverySpring(squeeze: { kRel: number, cRel: number }): (number, number)
	local omega = math.sqrt(squeeze.kRel)
	return omega, squeeze.cRel / (2 * omega)
end

-- A feel's jiggle spring (ω, ζ) and gain; an unknown feel is foam.
function SquishRig.feelSpring(feel: string): (number, number, number)
	local spec = RIG.feels[feel] or RIG.feels.foam
	local omega = math.sqrt(spec.k)
	return omega, spec.c / (2 * omega), spec.gain
end

-- The release kick's shown peak: releaseKick × gain × the rarity factor, at most releaseKickMax.
function SquishRig.releaseKick(feel: string, rarity: string?): number
	local _, _, gain = SquishRig.feelSpring(feel)
	return math.min(RIG.releaseKick * (flourishOf(rarity).releaseKick or 1) * gain, RIG.releaseKickMax)
end

-- The squeeze shapes the toy reaches (rest, the scaled phases, the overshoot, the jiggle caps): Kit.extremes.
function SquishRig.extremes(motion: Motion, axis: Axis): { Extreme }
	return Kit.extremes(motion, axis)
end

-- Inspect framing for one toy: its widest scale on any axis + Framing.widenMargin, never below squeezeWidening.
function SquishRig.framingWidening(motion: Motion, axis: Axis): number
	local widest = 1
	for _, extreme in Kit.extremes(motion, axis) do
		local S = extreme.S
		widest = math.max(widest, S.X, S.Y, S.Z)
	end
	return math.max(FRAMING.squeezeWidening, widest + FRAMING.widenMargin)
end

-- A flight pose t seconds into the flight: roll about the travel line, a small nod (the face still leads), a stretch
-- pulse along travel, and the flap phase (radians) the sections use. ReducedMotion: today's Catalog flightSpin (a
-- spinning style rolls at the "roll" rate, the others wobble like "wobble"), no nod, pulse or flaps. amp scales the
-- wobble and nod (Butter 0.7); pulsePeak is a toy's motion.flight.pulse (Mochi Fox 1.15) at the style's pulseHz.
function SquishRig.flightPose(
	style: string,
	t: number,
	reduced: boolean,
	amp: number?,
	pulsePeak: number?
): (number, number, number, number)
	local spec = FLIGHT[style] or FLIGHT.wobble
	if reduced then
		if spec.rollDegPerSecond then
			return math.rad(FLIGHT.roll.rollDegPerSecond :: number) * t, 0, 1, 0
		end
		local wobble = FLIGHT.wobble
		return math.rad(wobble.wobbleDeg :: number) * math.sin(TAU * (wobble.wobbleHz :: number) * t), 0, 1, 0
	end
	local scale = amp or 1
	local roll = 0
	if spec.rollDegPerSecond then
		roll = math.rad(spec.rollDegPerSecond) * t
	end
	if spec.wobbleDeg and spec.wobbleHz then
		roll += math.rad(spec.wobbleDeg) * scale * math.sin(TAU * spec.wobbleHz * t)
	end
	local nod = 0
	if spec.nodDeg and spec.nodHz then
		nod = math.rad(spec.nodDeg) * scale * math.sin(TAU * spec.nodHz * t)
	end
	local pulse = 1
	if spec.pulseAmp and spec.pulseHz then
		pulse = 1 + spec.pulseAmp * math.sin(TAU * spec.pulseHz * t)
	elseif pulsePeak and spec.pulseHz then
		pulse = 1 + (pulsePeak - 1) * (0.5 - 0.5 * math.cos(TAU * spec.pulseHz * t))
	end
	local flapPhase = if spec.flapHz then TAU * spec.flapHz * t else 0
	return roll, nod, pulse, flapPhase
end

function SquishRig.new(motion: Motion, options: Options?): Rig
	assert(type(motion) == "table" and type(motion.squeeze) == "table", "[SD][SquishRig] new needs a motion row")
	local opts: Options = options or {}
	local rarity = opts.rarity or "Common"
	local flourish = flourishOf(rarity)
	local extraMs = flourish.wideningExtraMs or 0
	local keys = keysFor(extraMs)
	local squeeze = motion.squeeze
	local depth, widen = squeeze.depth, squeeze.widen
	local deepest = deepestC()
	local keyY: { number } = table.create(#keys)
	local keyW: { number } = table.create(#keys)
	for i, key in keys do
		local c = 1 - (1 - key.c) * (1 - depth) / (1 - deepest)
		keyY[i] = c
		keyW[i] = 1 + (1 - c) * widen
	end
	local recOmega, recZeta = SquishRig.recoverySpring(squeeze)
	local feelOmega, feelZeta, gain = SquishRig.feelSpring(motion.feel)

	local names = SquishRig.sectionNames(opts.sections)
	local count = #names
	local signs, amps, maxes = table.create(count, 1), table.create(count, 0), table.create(count, 0)
	local flaps, phases = table.create(count, -1), table.create(count, 0)
	for i, name in names do
		local section = (opts.sections :: { [string]: Section })[name]
		signs[i] = section.sign or 1
		amps[i] = section.amp
		maxes[i] = math.rad(section.maxDeg or SECTIONS.maxDeg)
		local flap = section.flap
		flaps[i] = if flap then math.rad(flap.deg) else -1
		phases[i] = if flap then flap.phase or 0 else 0
	end

	if opts.seed == nil then
		seedCounter += 1
	end
	local rng = Random.new(opts.seed or seedCounter)
	local axis: Axis = opts.axis or "Y"
	local data: RigData = {
		timing = timingOf(extraMs),
		_motion = motion,
		_axis = axis,
		_curAxis = axis,
		_wantAxis = axis,
		_depth = depth,
		_widen = widen,
		_keys = keys,
		_keyY = keyY,
		_keyW = keyW,
		_recOmega = recOmega,
		_recZeta = recZeta,
		_foamT = opts.foamRecoveryT or DEFAULT_FOAM_T,
		_feelOmega = feelOmega,
		_feelZeta = feelZeta,
		_gain = gain,
		_kickVelocity = peakVelocity(feelOmega, feelZeta),
		_releasePeak = SquishRig.releaseKick(motion.feel, rarity),
		_twistRad = math.rad(flourish.twistDeg or 0),
		_flareVelocity = math.rad(flourish.sectionFlareDeg or 0) * peakVelocity(SECTION_OMEGA, SECTION_ZETA),
		_reduced = opts.reduced == true,
		_detail = "hero",
		_blinkOn = opts.blink ~= false,
		_mode = MODE_IDLE,
		_tMs = 0,
		_holding = false,
		_y0 = 1,
		_w0 = 1,
		_twist0 = 0,
		_twist = 0,
		_popStart = math.huge,
		_popFromY = 1,
		_popFromW = 1,
		_popToY = 1,
		_popToW = 1,
		_evSquish = math.huge,
		_evPeak = math.huge,
		_evRelease = math.huge,
		_evPopEnd = math.huge,
		_fired = 0,
		_y = 1,
		_w = 1,
		_vy = 0,
		_vw = 0,
		_hold = nil,
		_r = 0,
		_vr = 0,
		_rCap = MOVE_CAP,
		_secCount = count,
		_secSign = signs,
		_secAmp = amps,
		_secMax = maxes,
		_secFlap = flaps,
		_secPhase = phases,
		_secA = table.create(count, 0),
		_secV = table.create(count, 0),
		_lastShown = 1,
		_lastAcross = 1,
		_lock = nil,
		_lockLeft = 0,
		_flightLock = false,
		_squishOn = false,
		_sinceToggle = math.huge,
		_grip = false,
		_face = "normal",
		_rng = rng,
		_blinkIn = 0,
		_blinkT = -1,
		_flightStyle = nil,
		_flightT = 0,
	}
	local rig = setmetatable(data, RigClass)
	rig._blinkIn = nextBlinkIn(rig)
	return rig
end

return SquishRig
