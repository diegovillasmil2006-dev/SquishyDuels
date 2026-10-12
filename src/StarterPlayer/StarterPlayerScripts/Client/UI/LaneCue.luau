--!strict
-- LaneCue (client only, pure): the "In the lane!" warning (final polish 2026-10-11; first-person spec 2026-10-10 §5
-- answer 5: "the 'In the lane!' cue for the Dragon Rush target"). In first person the floor lane under your feet is out
-- of view, so while an enemy lane ultimate's telegraph runs and your body is inside its lane, DuelController shows a
-- warning text under the duel bar. The lane is the UltimateEvent's own numbers (the same ones VfxController draws the
-- floor stadium from and the server sweeps), tested the way the server tests it, on the ground plane:
--   * Dragon Rush (kind "lane"): a sphere of `radius` swept O -> E against the capsule of a player standing on the
--     floor whatever the HRP's height (CombatService: only the HRP's X and Z count, jumping never avoids it);
--   * Sprinkle Roller (kind "roller"): a disc of `radius` along the floor against the capsule, horizontally
--     (Logic/UltRules.flatEntry; a high enough jump clears it, but the cue warns about the lane, not the jump).
-- Both reach the body when its HRP is within radius + Config.Combat.Hitbox.radius of the segment O -> O + dir·length
-- (round ends). Any other kind (the volley, the rain, the bubble) has no lane.
--
-- API
--   LaneCue.laneOf(event, kind) -> Lane?   the lane of a telegraph event of a lane kind ("lane", "roller"), else nil
--   LaneCue.inLane(lane, rootPosition) -> boolean   the HRP inside the lane (horizontal distance <= reach)
--   LaneCue.shows(lane?, rootPosition?, now) -> boolean   a lane, a body in it, before its telegraphEndsAt
--   LaneCue.top(barBottom, bannerTop?, bannerBottom?, gap) -> number   the cue's top (base px): `gap` under the duel
--       bar, or under the banner when one shows under the bar (the "incoming" banner of the same telegraph)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Lane = {
	a: Vector3, -- O on the ground plane (Y = 0)
	b: Vector3, -- E = O + dir·length on the ground plane
	reach: number, -- the lane's radius + the capsule's radius (studs)
	endsAt: number, -- telegraphEndsAt (server time)
}

-- Constants

local LANE_KINDS: { [string]: boolean } = { lane = true, roller = true }
local CAPSULE_RADIUS = Config.Combat.Hitbox.radius
local MIN_DIR = 1e-6
local BAR_SLACK = 1 -- base px: a banner whose top is this close above the bar's bottom still counts as under it

-- Module table

local LaneCue = {}

-- Private

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Public

function LaneCue.laneOf(event: any, kind: string?): Lane?
	if type(event) ~= "table" or event.phase ~= "telegraph" or kind == nil or not LANE_KINDS[kind] then
		return nil
	end
	local origin, dir = event.origin, event.dir
	if typeof(origin) ~= "Vector3" or typeof(dir) ~= "Vector3" then
		return nil
	end
	if not (finite(event.length) and finite(event.radius) and finite(event.telegraphEndsAt)) then
		return nil
	end
	local along = flat(dir)
	if along.Magnitude < MIN_DIR or event.length < 0 or event.radius < 0 then
		return nil
	end
	local a = flat(origin)
	return {
		a = a,
		b = a + along.Unit * event.length,
		reach = event.radius + CAPSULE_RADIUS,
		endsAt = event.telegraphEndsAt,
	}
end

function LaneCue.inLane(lane: Lane, rootPosition: Vector3): boolean
	local p = flat(rootPosition)
	local ab = lane.b - lane.a
	local length2 = ab:Dot(ab)
	local u = if length2 > 0 then math.clamp((p - lane.a):Dot(ab) / length2, 0, 1) else 0
	return (p - (lane.a + ab * u)).Magnitude <= lane.reach
end

function LaneCue.shows(lane: Lane?, rootPosition: Vector3?, now: number): boolean
	if lane == nil or rootPosition == nil or not (now < lane.endsAt) then
		return false
	end
	return LaneCue.inLane(lane, rootPosition)
end

function LaneCue.top(barBottom: number, bannerTop: number?, bannerBottom: number?, gap: number): number
	if bannerTop ~= nil and bannerBottom ~= nil and bannerTop >= barBottom - BAR_SLACK then
		return bannerBottom + gap
	end
	return barBottom + gap
end

return LaneCue
