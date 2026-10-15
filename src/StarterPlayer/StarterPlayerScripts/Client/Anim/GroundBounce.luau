--!strict
-- GroundBounce (client only, pure): what a thrown squishy does after it meets the ground or a wall (2026-10-15 throw
-- overhaul; cosmetic only, the server decided the throw at its impact). Plain numbers and CFrames: no instances,
-- connections or clock reads; the caller passes dt and a cast function (its own raycast).
--
-- Phases: "air" (gravity; a contact faster than BOUNCE_MIN along its normal bounces with the feel's restitution, the
-- tangential speed kept by `keep`, a squash kick and a tumble spin; the first is "land", the rest "bounce"; slower
-- ones start rolling) -> "roll" (gravity along the surface, so it runs down slopes; rolling friction; walls bounce it
-- back; an edge drops it into "air") -> at rest (speed < REST_SPEED, or out of time) the design's ground splat
-- (design: fp.js groundStart / 'ground'): "flat" (it turns face up and flattens, holds), "peel" (it springs back up,
-- facing `lookBack`), "idle" (a breath), "poof" (it pops away) -> "done".
-- Feels (Config.Anim.rig.feels names): foam medium, mochi sticky, jelly bouncy, plush soft. Duel throws (opts.duel)
-- keep it short: fewer bounces, a shorter flat and idle, so it never lingers on the court.
--
-- API
--   GroundBounce.new(position, velocity, normal, radius, gravity, feel, opts?) -> (State, { Event })
--       the state right after the first contact (its "land" event, or "roll" when it came in slow)
--   GroundBounce.step(state, dt, cast) -> { Event }   cast(origin, direction) -> (hitPosition?, hitNormal?)
--   GroundBounce.pose(state) -> (CFrame, Vector3)      the model's pivot and its deformer scale (pivot space, Z the face)
--   GroundBounce.fade(state) -> number                 its parts' fade (the poof's end; the deformer stops at scaleMin)
--   Event = { kind = "land" | "bounce" | "skid" | "rest" | "peel" | "poof" | "done", position, normal, speed, on }

-- Types

export type Feel = {
	restitution: number, -- bounce speed share along the normal
	keep: number, -- tangential speed kept by a bounce
	rollFriction: number, -- studs/s² against the roll
	squashPerSpeed: number, -- squash kick per stud/s of normal speed
	omega: number, -- squash spring
	zeta: number,
	maxBounces: number,
}

export type Options = {
	duel: boolean?, -- short version (duels)
	lookBack: Vector3?, -- where it faces when it peels up (e.g. toward the thrower); nil = back along its path
}

export type Event = {
	kind: string,
	position: Vector3,
	normal: Vector3,
	speed: number,
	on: boolean?,
}

export type State = {
	position: Vector3,
	velocity: Vector3,
	normal: Vector3,
	radius: number,
	gravity: number,
	feel: Feel,
	duel: boolean,
	lookBack: Vector3?,
	rot: CFrame, -- orientation only
	spin: Vector3, -- angular velocity, rad/s (world axis × rate)
	squash: number, -- spring displacement, + = compressed along squashAxis
	squashVel: number,
	squashAxis: Vector3,
	phase: string,
	phaseT: number,
	t: number,
	bounces: number,
	skidding: boolean,
	startY: number,
	restFrame: CFrame?,
	upFrame: CFrame?,
}

-- Constants

local FEELS: { [string]: Feel } = {
	-- Tuned in Play 2026-10-15: a practice throw into the lane floor rolled ~30 studs back past the thrower at
	-- rollFriction 7; with these and ROLL_DAMP it stops within about a third of that.
	foam = { restitution = 0.42, keep = 0.62, rollFriction = 16, squashPerSpeed = 0.012, omega = 22, zeta = 0.32, maxBounces = 4 },
	mochi = { restitution = 0.22, keep = 0.45, rollFriction = 26, squashPerSpeed = 0.016, omega = 15, zeta = 0.28, maxBounces = 2 },
	jelly = { restitution = 0.62, keep = 0.72, rollFriction = 11, squashPerSpeed = 0.015, omega = 26, zeta = 0.16, maxBounces = 6 },
	plush = { restitution = 0.3, keep = 0.55, rollFriction = 20, squashPerSpeed = 0.011, omega = 18, zeta = 0.45, maxBounces = 3 },
}
local DEFAULT_FEEL = "foam"

local SUBSTEP = 1 / 120
local BOUNCE_MIN = 7 -- studs/s along the normal: slower contacts roll
local REST_SPEED = 1.2 -- studs/s
local SKID_ON = 3 -- studs/s: the skid dust runs above this while rolling
local ROLL_DAMP = 0.9 -- per second: rolling speed lost on top of the friction (grass, carpet, foam)
local SQUASH_MAX = 0.42
local SPIN_SHARE = 0.85 -- the tumble after a bounce: this share of the rolling spin
local AIR_SPIN_DAMP = 0.6 -- per second
local GROUND_PROBE = 1.6 -- studs below the contact point checked for ground while rolling
local WALL_NORMAL_Y = 0.55 -- a roll contact with |n · surface| below this is a wall
local FALL_LIMIT = 80 -- studs below the first contact: gone
local DUEL_SECONDS = 1.6 -- the longest bounce-and-roll before it is put to rest
local PRACTICE_SECONDS = 4.5
local DUEL_BOUNCES = 2

-- The ground splat (seconds; duel / practice).
local FLAT_IN = 0.12
local FLAT_HOLD = { duel = 0.18, practice = 0.32 }
local PEEL = 0.36
local IDLE = { duel = 0.12, practice = 0.5 }
local POOF = 0.2
local FLAT_SCALE = Vector3.new(1.32, 1.32, 0.48) -- pivot space: Z is the face axis (up when face up)

-- Module table

local GroundBounce = {}
GroundBounce.FEELS = FEELS

-- Private

local function ev(kind: string, s: State, speed: number?, on: boolean?): Event
	return { kind = kind, position = s.position, normal = s.normal, speed = speed or 0, on = on }
end

local function horizontal(v: Vector3): Vector3
	local h = Vector3.new(v.X, 0, v.Z)
	return if h.Magnitude > 1e-4 then h.Unit else Vector3.new(0, 0, -1)
end

local function rotate(rot: CFrame, spin: Vector3, dt: number): CFrame
	local rate = spin.Magnitude
	if rate < 1e-4 then
		return rot
	end
	return CFrame.fromAxisAngle(spin / rate, rate * dt) * rot
end

local function springStep(s: State, dt: number)
	local f = s.feel
	local a = -f.omega * f.omega * s.squash - 2 * f.zeta * f.omega * s.squashVel
	s.squashVel += a * dt
	s.squash += s.squashVel * dt
end

local function limitSeconds(s: State): number
	return if s.duel then DUEL_SECONDS else PRACTICE_SECONDS
end

local function maxBounces(s: State): number
	return if s.duel then math.min(DUEL_BOUNCES, s.feel.maxBounces) else s.feel.maxBounces
end

-- The face-up frame at rest: the face (-Z, the LookVector) looks along the surface normal, its top along the travel.
local function faceUpFrame(position: Vector3, normal: Vector3, travel: Vector3): CFrame
	local up = travel - normal * travel:Dot(normal)
	if up.Magnitude < 1e-3 then
		up = if math.abs(normal.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis
	end
	return CFrame.lookAt(position, position + normal, up.Unit)
end

local function toRest(s: State, events: { Event })
	if s.skidding then
		s.skidding = false
		table.insert(events, ev("skid", s, 0, false))
	end
	s.phase = "flat"
	s.phaseT = 0
	s.velocity = Vector3.zero
	local travel = if s.lookBack then -s.lookBack else s.rot.LookVector
	s.restFrame = faceUpFrame(s.position, s.normal, horizontal(travel))
	local back = s.lookBack or -horizontal(s.rot.LookVector)
	s.upFrame = CFrame.lookAt(s.position, s.position + horizontal(back))
	table.insert(events, ev("rest", s))
end

-- One contact while in the air. Returns true when it bounced (else it rolls).
local function contact(s: State, hitPosition: Vector3, n: Vector3, events: { Event }): boolean
	local vn = s.velocity:Dot(n)
	s.position = hitPosition + n * s.radius
	s.normal = n
	local speed = -vn
	if speed > BOUNCE_MIN and s.bounces < maxBounces(s) then
		local tangential = s.velocity - n * vn
		s.velocity = tangential * s.feel.keep + n * (speed * s.feel.restitution)
		s.squashAxis = n
		s.squashVel = 0
		s.squash = math.min(speed * s.feel.squashPerSpeed, SQUASH_MAX)
		s.spin = n:Cross(tangential) / s.radius * SPIN_SHARE
		s.bounces += 1
		table.insert(events, ev(if s.bounces == 1 then "land" else "bounce", s, speed))
		return true
	end
	-- Too slow to bounce: it rolls along the surface (a wall it slid down sends it on to the ground).
	s.velocity -= n * vn
	if s.bounces == 0 then
		s.bounces = 1
		s.squashAxis = n
		s.squash = math.min(math.max(speed, 4) * s.feel.squashPerSpeed, SQUASH_MAX)
		table.insert(events, ev("land", s, speed))
	end
	if math.abs(n.Y) >= WALL_NORMAL_Y then
		s.phase = "roll"
	end
	return false
end

local function stepAir(s: State, dt: number, cast: (Vector3, Vector3) -> (Vector3?, Vector3?), events: { Event })
	s.velocity += Vector3.new(0, -s.gravity, 0) * dt
	s.spin *= math.exp(-AIR_SPIN_DAMP * dt)
	s.rot = rotate(s.rot, s.spin, dt)
	local move = s.velocity * dt
	local length = move.Magnitude
	if length < 1e-6 then
		return
	end
	local dir = move / length
	local hit, n = cast(s.position, dir * (length + s.radius))
	if hit and n and s.velocity:Dot(n) < 0 then
		contact(s, hit, n, events)
		return
	end
	s.position += move
	-- Its underside: on a shallow path the forward ray reaches the floor late, so probe one radius straight down too.
	if s.velocity.Y < 0 then
		local below, bn = cast(s.position, Vector3.new(0, -s.radius, 0))
		if below and bn and s.velocity:Dot(bn) < 0 then
			contact(s, below, bn, events)
		end
	end
end

local function stepRoll(s: State, dt: number, cast: (Vector3, Vector3) -> (Vector3?, Vector3?), events: { Event })
	local n = s.normal
	local g = Vector3.new(0, -s.gravity, 0)
	local along = g - n * g:Dot(n) -- down the slope
	local v = (s.velocity + along * dt) * math.exp(-ROLL_DAMP * dt)
	local speed = v.Magnitude
	if speed > 1e-4 then
		local slow = math.min(s.feel.rollFriction * dt, speed)
		v -= v / speed * slow
	end
	s.velocity = v
	speed = v.Magnitude
	-- A wall ahead bounces it back.
	if speed > 1e-4 then
		local hit, wn = cast(s.position, v / speed * (speed * dt + s.radius))
		if hit and wn and math.abs(wn:Dot(n)) < WALL_NORMAL_Y and v:Dot(wn) < 0 then
			s.velocity = v - wn * (1 + s.feel.restitution) * v:Dot(wn)
			s.squashAxis = wn
			s.squash = math.min(speed * s.feel.squashPerSpeed, SQUASH_MAX)
			table.insert(events, ev("bounce", s, speed))
			return
		end
	end
	local nextPosition = s.position + s.velocity * dt
	-- Stay on the ground: probe along -n; nothing under it = an edge, it falls.
	local ground, gn = cast(nextPosition, -n * (s.radius + GROUND_PROBE))
	if ground and gn then
		s.position = ground + gn * s.radius
		s.normal = gn
	else
		s.position = nextPosition
		s.phase = "air"
		if s.skidding then
			s.skidding = false
			table.insert(events, ev("skid", s, speed, false))
		end
		return
	end
	-- True rolling for the look (a toy that is not round reads as a tumble: cartoon enough).
	s.spin = s.normal:Cross(s.velocity) / s.radius
	s.rot = rotate(s.rot, s.spin, dt)
	local skid = speed > SKID_ON
	if skid ~= s.skidding then
		s.skidding = skid
		table.insert(events, ev("skid", s, speed, skid))
	end
	-- It rests once slow, unless the slope pulls harder than the friction holds (then it rolls on downhill).
	if speed < REST_SPEED and along.Magnitude <= s.feel.rollFriction then
		toRest(s, events)
	end
end

local function holdFor(s: State, values: { duel: number, practice: number }): number
	return if s.duel then values.duel else values.practice
end

local function stepSplat(s: State, dt: number, events: { Event })
	s.phaseT += dt
	if s.phase == "flat" and s.phaseT >= FLAT_IN + holdFor(s, FLAT_HOLD) then
		s.phase, s.phaseT = "peel", 0
		table.insert(events, ev("peel", s))
	elseif s.phase == "peel" and s.phaseT >= PEEL then
		s.phase, s.phaseT = "idle", 0
	elseif s.phase == "idle" and s.phaseT >= holdFor(s, IDLE) then
		s.phase, s.phaseT = "poof", 0
		table.insert(events, ev("poof", s))
	elseif s.phase == "poof" and s.phaseT >= POOF then
		s.phase, s.phaseT = "done", 0
		table.insert(events, ev("done", s))
	end
end

local function backOut(u: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local x = math.clamp(u, 0, 1) - 1
	return 1 + c3 * x * x * x + c1 * x * x
end

local function smooth(u: number): number
	local x = math.clamp(u, 0, 1)
	return x * x * (3 - 2 * x)
end

-- Public

function GroundBounce.new(
	position: Vector3,
	velocity: Vector3,
	normal: Vector3,
	radius: number,
	gravity: number,
	feel: string?,
	opts: Options?
): (State, { Event })
	local n = if normal.Magnitude > 1e-4 then normal.Unit else Vector3.yAxis
	local look = if velocity.Magnitude > 1e-4 then velocity.Unit else Vector3.new(0, 0, -1)
	local s: State = {
		position = position,
		velocity = velocity,
		normal = n,
		radius = math.max(radius, 0.2),
		gravity = math.max(gravity, 1),
		feel = FEELS[feel or DEFAULT_FEEL] or FEELS[DEFAULT_FEEL],
		duel = opts ~= nil and opts.duel == true,
		lookBack = if opts and opts.lookBack and opts.lookBack.Magnitude > 1e-4 then horizontal(opts.lookBack) else nil,
		rot = CFrame.lookAt(Vector3.zero, look, if math.abs(look.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis),
		spin = Vector3.zero,
		squash = 0,
		squashVel = 0,
		squashAxis = n,
		phase = "air",
		phaseT = 0,
		t = 0,
		bounces = 0,
		skidding = false,
		startY = position.Y,
		restFrame = nil,
		upFrame = nil,
	}
	local events: { Event } = {}
	-- The first contact: back the centre off the surface along the normal, then bounce or roll.
	if velocity:Dot(n) < 0 then
		contact(s, position - n * s.radius, n, events)
	else
		table.insert(events, ev("land", s, 0))
		s.bounces = 1
	end
	return s, events
end

function GroundBounce.step(state: State, dt: number, cast: (Vector3, Vector3) -> (Vector3?, Vector3?)): { Event }
	local events: { Event } = {}
	local s = state
	if s.phase == "done" then
		return events
	end
	local remaining = math.max(dt, 0)
	while remaining > 1e-6 and s.phase ~= "done" do
		local h = math.min(remaining, SUBSTEP)
		remaining -= h
		s.t += h
		springStep(s, h)
		if s.phase == "air" or s.phase == "roll" then
			if s.t > limitSeconds(s) then
				toRest(s, events)
			elseif s.phase == "air" then
				stepAir(s, h, cast, events)
			else
				stepRoll(s, h, cast, events)
			end
			if s.position.Y < s.startY - FALL_LIMIT then
				s.phase = "done"
				table.insert(events, ev("done", s))
			end
		else
			stepSplat(s, h, events)
		end
	end
	return events
end

-- The model's pivot and deformer scale now (pivot space: X right, Y up, Z the face axis).
function GroundBounce.pose(state: State): (CFrame, Vector3)
	local s = state
	local phase = s.phase
	if phase == "air" or phase == "roll" then
		local frame = CFrame.new(s.position) * s.rot
		local q = math.clamp(s.squash, -0.25, SQUASH_MAX)
		-- Squash along the pivot axis closest to the last contact normal; the other two widen by half.
		local axis = frame:VectorToObjectSpace(s.squashAxis)
		local ax, ay, az = math.abs(axis.X), math.abs(axis.Y), math.abs(axis.Z)
		local wide = 1 + q * 0.5
		local scale = if ax >= ay and ax >= az
			then Vector3.new(1 - q, wide, wide)
			elseif ay >= az then Vector3.new(wide, 1 - q, wide)
			else Vector3.new(wide, wide, 1 - q)
		return frame, scale
	end
	local rest = s.restFrame or CFrame.new(s.position)
	local up = s.upFrame or rest
	-- Lying flat its centre sits lower: the squashed thickness rests on the surface.
	local sink = s.normal * (s.radius * (1 - FLAT_SCALE.Z))
	if phase == "flat" then
		local u = smooth(s.phaseT / FLAT_IN)
		local frame = s.rot:Lerp(rest - rest.Position, u) + s.position - sink * u
		local settleT = s.phaseT - FLAT_IN
		local over = if settleT > 0 then 0.04 * math.sin(settleT * 30) * math.exp(-settleT * 8) else 0
		local scale = Vector3.one:Lerp(FLAT_SCALE, backOut(s.phaseT / FLAT_IN)) + Vector3.new(over, over, -over)
		return frame, scale
	elseif phase == "peel" then
		local u = s.phaseT / PEEL
		local turn = smooth(u * 1.3)
		local hop = math.sin(math.clamp(u, 0, 1) * math.pi) * s.radius * 0.45
		local frame = (rest - rest.Position):Lerp(up - up.Position, turn) + s.position - sink * (1 - turn) + s.normal * hop
		local scale = FLAT_SCALE:Lerp(Vector3.one, backOut(u))
		return frame, scale
	elseif phase == "idle" then
		local b = 0.03 * math.sin(s.phaseT * 9)
		return up, Vector3.new(1 + b * 0.5, 1 + b * 0.5, 1 - b)
	elseif phase == "poof" then
		local u = math.clamp(s.phaseT / POOF, 0, 1)
		-- it swells, then shrinks while fade() takes it away (the deformer stops at its scaleMin anyway)
		local k = if u < 0.35 then 1 + 0.18 * smooth(u / 0.35) else 1.18 - 0.6 * smooth((u - 0.35) / 0.65)
		return up, Vector3.one * k
	end
	return up, Vector3.zero
end

-- The parts' fade now (0 shown .. 1 gone): the poof's second half fades, since the deformer stops at scaleMin.
function GroundBounce.fade(state: State): number
	if state.phase == "done" then
		return 1
	elseif state.phase ~= "poof" then
		return 0
	end
	local u = math.clamp(state.phaseT / POOF, 0, 1)
	return if u < 0.35 then 0 else smooth((u - 0.35) / 0.65)
end

return GroundBounce
