--!strict
-- MovementRules: the duel movement guard (DESIGN §5.7 "Movement guard", §5.4 out of bounds, §12 #13). Server only,
-- pure: no instances, no yields, time comes in as `now`. CombatService samples each participant's server HRP at
-- Config.Combat.MovementGuard.checkHz (5 Hz) and calls evaluate() with one Guard per participant.
--
-- Checks per sample, in order:
--   1. HRP below KillY (floorY + OutOfBounds.KillYOffset) ............................... outOfBounds (killY)
--   2. HRP outside its own half grown by OutOfBounds.HalfToleranceStuds on X and Z ......... outOfBounds (outside)
--   3. HRP in the neutral zone or the opponent's half ........................... pivotBack (neutral / opponentHalf)
--   4. HRP inside a Geometry volume (the caller's GetPartBoundsInBox result) ................ pivotBack (geometry)
--   5. held (the Countdown freeze, a Dragon Rush root): HRP more than holdToleranceStuds + holdSlack from its anchor
--      (horizontally), outside grace ............................................................ pivotBack (held)
--   6. horizontal speed > maxHorizontalSpeed for overSpeedSamples samples in a row, outside grace .. pivotBack (speed)
-- otherwise ok. pivotBack carries `target` = the last position that passed every check (nil = use the own pad); a
-- `held` pivotBack carries the anchor instead.
-- Dash (spec phase 5 §3.3): allowDash(guard, startAt, untilTime, studs) records one validated dash (DashService). A
-- sample whose interval (previous sample .. now) overlaps [startAt, untilTime] may go `studs` further than
-- maxHorizontalSpeed allows, once in total: each such over-speed sample uses up its extra studs, and one that needs more
-- than is left counts as over-speed as usual. Checks 1-5 never change (a dash into the neutral zone still pulls back),
-- and the window ends with the first sample at or after untilTime. Never a blanket grace.
-- Held (§5.4 Countdown "frozen", §5.9 "Caster is rooted"): WalkSpeed / JumpHeight 0 is only a request to the client,
-- which owns its character's physics, so the server checks it. The anchor is sample.holdAt when the caller knows the
-- spot (the own pad in Countdown), else the position of the first held sample (kept until the hold ends, also across
-- a grace). sample.holdSlack widens the tolerance by the stopping distance the caller allows (CombatService: walk speed
-- × the player's ping for a root that starts while the player runs).
-- outOfBounds goes to DuelRules (event `oob`): it pivots to the own pad, gives invulnerability and counts; the
-- (MaxPerMatch + 1)th is a forfeit there. Before Active it is a silent re-pivot.
-- Grace: a pivotBack or outOfBounds verdict starts the teleport grace itself (teleportGraceSeconds); the caller adds
-- grace(guard, now + hitGraceSeconds) after a hit (knockback) and grace(guard, now + teleportGraceSeconds) after any
-- other server PivotTo. Samples inside a grace never count as over-speed, and the sample right after a grace starts
-- measures speed from scratch (no previous sample).
--
-- API:
--   MovementRules.new()                                    -> Guard
--   MovementRules.grace(guard, untilTime)                  extends the grace and forgets the previous sample
--   MovementRules.allowDash(guard, startAt, untilTime, studs) one validated dash's over-speed allowance (replaces any)
--   MovementRules.evaluate(guard, sample, zones, now, cfg?) -> Verdict (updates guard in place)
-- sample = { position = HRP position, insideGeometry = boolean?, held = boolean?, holdAt = Vector3?,
-- holdSlack = number? }; zones = { own, neutral?, opponent?, floorY } with
-- each zone a { cframe, size } box (Types.ArenaZone, sent in DuelState). `cfg` is a table with Config's Combat and Duel
-- sections (a test's copy of Config); nil = the live Config.
--
-- Readings: the neutral/opponent check uses the zones as they are (no margin), so the 2-stud band of the neutral zone
-- next to the own half is pulled back but never counted as out of bounds. An over-speed sample that is not yet the
-- overSpeedSamples-th is neither rejected nor remembered as a valid position. A sample with no time since the previous
-- one does not measure speed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)
local HitMath = require(script.Parent.HitMath)

-- Types

type Zone = Types.ArenaZone

export type Guard = {
	previous: { position: Vector3, t: number }?, -- the last sample, for speed
	lastValid: Vector3?, -- the last position that passed every check
	overSpeed: number, -- consecutive over-speed samples outside grace
	graceUntil: number, -- teleport / knockback grace end (server time)
	anchor: Vector3?, -- where a held player must stay (first held sample), nil when not held
	dash: DashAllowance?, -- one validated dash's allowance (allowDash), nil when none
}

-- The extra studs a validated dash may cover above maxHorizontalSpeed inside its window (server times).
export type DashAllowance = { startAt: number, untilTime: number, studs: number }

export type Sample = {
	position: Vector3,
	insideGeometry: boolean?,
	held: boolean?, -- must stand still (Countdown freeze, Dragon Rush root)
	holdAt: Vector3?, -- the spot to hold, when known (else the first held sample's position)
	holdSlack: number?, -- extra studs of tolerance (stopping distance); nil = 0
}

export type Zones = { own: Zone, neutral: Zone?, opponent: Zone?, floorY: number }

export type Action = "ok" | "pivotBack" | "outOfBounds"

export type Verdict = {
	action: Action,
	reason: string?, -- killY, outside, neutral, opponentHalf, geometry, held, speed
	target: Vector3?, -- pivotBack: the last valid position (nil = the own pad)
	speed: number?, -- horizontal speed measured on this sample, when there was one
}

export type MovementConfig = { Combat: any, Duel: any }

-- Module table

local MovementRules = {}

-- Private

local function config(cfg: MovementConfig?): MovementConfig
	return if cfg ~= nil then cfg else Config
end

local function horizontalDistance(a: Vector3, b: Vector3): number
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end

-- A verdict that moves the player: start the teleport grace so the pivot itself never counts as speed.
local function moved(guard: Guard, verdict: Verdict, now: number, c: MovementConfig): Verdict
	guard.overSpeed = 0
	guard.previous = nil
	guard.graceUntil = math.max(guard.graceUntil, now + c.Combat.MovementGuard.teleportGraceSeconds)
	return verdict
end

-- Public

function MovementRules.new(): Guard
	return { previous = nil, lastValid = nil, overSpeed = 0, graceUntil = -math.huge, anchor = nil, dash = nil }
end

function MovementRules.grace(guard: Guard, untilTime: number)
	guard.graceUntil = math.max(guard.graceUntil, untilTime)
	guard.previous = nil
	guard.overSpeed = 0
end

function MovementRules.allowDash(guard: Guard, startAt: number, untilTime: number, studs: number)
	guard.dash = { startAt = startAt, untilTime = untilTime, studs = math.max(studs, 0) }
end

function MovementRules.evaluate(guard: Guard, sample: Sample, zones: Zones, now: number, cfg: MovementConfig?): Verdict
	local c = config(cfg)
	local guardCfg = c.Combat.MovementGuard
	local oob = c.Duel.Rules.OutOfBounds
	local position = sample.position
	if sample.held ~= true then
		guard.anchor = nil -- the hold is over: the next one anchors afresh
	end

	-- 1-2. Out of bounds.
	if position.Y < zones.floorY + oob.KillYOffset then
		return moved(guard, { action = "outOfBounds", reason = "killY" }, now, c)
	end
	if not HitMath.inZone(position, zones.own, oob.HalfToleranceStuds) then
		return moved(guard, { action = "outOfBounds", reason = "outside" }, now, c)
	end

	-- 3-4. Places a player can never stand.
	local neutral, opponent = zones.neutral, zones.opponent
	if neutral ~= nil and HitMath.inZone(position, neutral, 0) then
		return moved(guard, { action = "pivotBack", reason = "neutral", target = guard.lastValid }, now, c)
	end
	if opponent ~= nil and HitMath.inZone(position, opponent, 0) then
		return moved(guard, { action = "pivotBack", reason = "opponentHalf", target = guard.lastValid }, now, c)
	end
	if sample.insideGeometry == true then
		return moved(guard, { action = "pivotBack", reason = "geometry", target = guard.lastValid }, now, c)
	end

	-- 5. Held in place.
	if sample.held == true then
		local anchor: Vector3 = sample.holdAt or guard.anchor or position
		if sample.holdAt == nil and guard.anchor == nil then
			guard.anchor = position -- the first held sample is the spot to hold
		end
		local slack = sample.holdSlack
		local tolerance = guardCfg.holdToleranceStuds + (if type(slack) == "number" and slack > 0 then slack else 0)
		if now >= guard.graceUntil and horizontalDistance(anchor, position) > tolerance then
			return moved(guard, { action = "pivotBack", reason = "held", target = anchor }, now, c)
		end
	end

	-- 6. Speed.
	local previous = guard.previous
	local speed: number? = nil
	local fast = false
	local dash = guard.dash
	if previous ~= nil and now > previous.t then
		local elapsed = now - previous.t
		local distance = horizontalDistance(previous.position, position)
		speed = distance / elapsed
		fast = distance / elapsed > guardCfg.maxHorizontalSpeed
		-- A validated dash's own studs, once, for a sample interval that overlaps its window.
		if fast and dash ~= nil and previous.t < dash.untilTime and now > dash.startAt then
			local extra = distance - guardCfg.maxHorizontalSpeed * elapsed
			if extra <= dash.studs then
				dash.studs -= extra
				fast = false
			end
		end
	end
	if dash ~= nil and now >= dash.untilTime then
		guard.dash = nil
	end
	guard.previous = { position = position, t = now }
	-- Inside a grace the streak is reset, never extended.
	if fast and now >= guard.graceUntil then
		guard.overSpeed += 1
	else
		guard.overSpeed = 0
	end
	if guard.overSpeed >= guardCfg.overSpeedSamples then
		return moved(guard, { action = "pivotBack", reason = "speed", target = guard.lastValid, speed = speed }, now, c)
	end
	if not fast then
		guard.lastValid = position
	end
	return { action = "ok", speed = speed }
end

return table.freeze(MovementRules)
