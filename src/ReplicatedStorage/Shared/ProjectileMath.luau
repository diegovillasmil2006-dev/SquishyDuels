--!strict
-- ProjectileMath: the one trajectory formula for the server simulation (CombatService, PracticeService,
-- AbilityService) and the client renderer (ProjectileRenderer, the ThrowController reticle) (DESIGN §5.5, §5.7, §9.7).
-- Shared, pure: no instances, no clock, no randomness. The same inputs always give the same positions, so the server's
-- hit test and the client's drawing follow one path.
-- * positionAt(o, v, g, t) = o + v·t + (0, -½·g·t², 0), analytic in `t`. `g` is the squishy's own gravity (studs/s²,
--   Catalog throw.gravity), never Workspace.Gravity. Dragon Rush is the same formula with g = 0 (a straight lane).
-- * solveLaunchDir(origin, target, speed, g): the low-arc launch direction that lands on `target`
--   (tanθ = (v² - √(v⁴ - g(g·x² + 2y·v²))) / (g·x)); no solution -> Config.Combat.Throw.noSolutionPitchDeg toward the
--   target; pitch clamped to [pitchMinDeg, pitchMaxDeg] (§5.5). The reticle therefore predicts where the throw lands.
-- * subSteps (§5.7): the server sweeps each projectile over equal sub-steps [a, b] of its local time,
--   n = clamp(ceil((tNow - tPrev) · substepsPerSecond), 1, maxSubsteps); every boundary is a fresh positionAt (no
--   accumulated error). A hit at fraction f of a sub-step happened at impactTime = releaseAt + a + f·(b - a).
-- * settledPositionAt (§9.7): the client's flight path, which starts in the hand and settles onto the server path,
--   P = positionAt(o, v, g, τ) + offset·e^(-τ / pathSettleTau).
-- Times: `t` and `tau` are seconds since release ("local time"); `releaseAt` and `serverTime` are
-- workspace:GetServerTimeNow() values.

local Config = require(script.Parent.Config)

-- A projectile as ThrowStarted describes it (origin, velocity, gravity, releaseAt; §2.8).
export type Trajectory = {
	origin: Vector3,
	velocity: Vector3,
	gravity: number,
	releaseAt: number,
}

-- One sub-step of a sweep: local times a < b and the positions there.
export type SubStep = {
	a: number,
	b: number,
	p0: Vector3,
	p1: Vector3,
}

-- Pitch rules of a launch direction, in degrees. Default: Config.Combat.Throw.
export type PitchLimits = {
	minDeg: number,
	maxDeg: number,
	noSolutionDeg: number,
}

local EPSILON = 1e-9
-- A target closer than this horizontally has no horizontal direction of its own.
local FLAT_EPSILON = 1e-6
-- Reading (not in DESIGN): a clamped pitch is kept this far inside the band, so the float32 round trip of a Vector3
-- (client -> server) can never put a clamped direction a hair outside ThrowRules' pitch check.
local PITCH_INSET_DEG = 1e-3
-- Reading: the horizontal direction used when the target is straight above or below the origin.
local DEFAULT_FORWARD = Vector3.new(0, 0, -1)
local UP = Vector3.new(0, 1, 0)
-- ceil() guard: a span of exactly k sub-steps (1/60 × 60 = 1.0000000000000002) must not round up to k + 1.
local CEIL_GUARD = 1e-9

local THROW = Config.Combat.Throw
local DEFAULT_LIMITS: PitchLimits = table.freeze({
	minDeg = THROW.pitchMinDeg,
	maxDeg = THROW.pitchMaxDeg,
	noSolutionDeg = THROW.noSolutionPitchDeg,
})

local ProjectileMath = {}

ProjectileMath.DEFAULT_LIMITS = DEFAULT_LIMITS
ProjectileMath.PITCH_INSET_DEG = PITCH_INSET_DEG

-- Trajectory ---------------------------------------------------------------------------------------------------------

-- Position `t` seconds after release.
function ProjectileMath.positionAt(o: Vector3, v: Vector3, g: number, t: number): Vector3
	return o + v * t + Vector3.new(0, -0.5 * g * t * t, 0)
end

-- Velocity `t` seconds after release (the travel direction for the client's lookAt, §9.7).
function ProjectileMath.velocityAt(v: Vector3, g: number, t: number): Vector3
	return v + Vector3.new(0, -g * t, 0)
end

-- Position of a ThrowStarted-style trajectory at a server time. Before the release it stays at the origin.
function ProjectileMath.positionAtTime(trajectory: Trajectory, serverTime: number): Vector3
	local t = math.max(serverTime - trajectory.releaseAt, 0)
	return ProjectileMath.positionAt(trajectory.origin, trajectory.velocity, trajectory.gravity, t)
end

-- Local time of a projectile at a server time: serverTime - releaseAt, clamped to [0, maxLifetime]
-- (default Config.Duel.Rules.ProjectileMaxLifetime). Check serverTime >= releaseAt first: before the release the
-- projectile does not exist yet (§5.6 #12, §5.7).
function ProjectileMath.flightTime(serverTime: number, releaseAt: number, maxLifetime: number?): number
	local lifetime = if maxLifetime == nil then Config.Duel.Rules.ProjectileMaxLifetime else maxLifetime
	return math.clamp(serverTime - releaseAt, 0, math.max(lifetime, 0))
end

-- The client path (§9.7): starts at origin + offset (offset = hand position at release - origin) and settles onto
-- the exact server path. settleTau defaults to Config.Anim.throw.pathSettleTau; <= 0 means no offset at all.
function ProjectileMath.settledPositionAt(
	o: Vector3,
	v: Vector3,
	g: number,
	tau: number,
	offset: Vector3,
	settleTau: number?
): Vector3
	local t = math.max(tau, 0)
	local base = ProjectileMath.positionAt(o, v, g, t)
	local settle = if settleTau == nil then Config.Anim.throw.pathSettleTau else settleTau
	if settle <= 0 then
		return base
	end
	return base + offset * math.exp(-t / settle)
end

-- Longest range on flat ground (at 45°): speed² / g. A straight lane (g <= 0) has no limit.
function ProjectileMath.maxRange(speed: number, g: number): number
	if g <= EPSILON then
		return math.huge
	end
	return speed * speed / g
end

-- Aim ----------------------------------------------------------------------------------------------------------------

-- Pitch of a direction in degrees: + up, - down (0 for a zero vector).
function ProjectileMath.pitchDeg(dir: Vector3): number
	local horizontal = math.sqrt(dir.X * dir.X + dir.Z * dir.Z)
	if horizontal <= EPSILON and math.abs(dir.Y) <= EPSILON then
		return 0
	end
	return math.deg(math.atan2(dir.Y, horizontal))
end

-- Unit launch direction from `origin` that lands on `target` for a throw of `speed` and gravity `g` (§5.5).
-- Low-arc solution; no solution -> limits.noSolutionDeg toward the target; pitch clamped to the limits (kept
-- PITCH_INSET_DEG inside them). g <= 0 aims straight at the target. A target straight above or below aims along
-- DEFAULT_FORWARD at the clamped pitch. `limits` defaults to Config.Combat.Throw.
function ProjectileMath.solveLaunchDir(
	origin: Vector3,
	target: Vector3,
	speed: number,
	g: number,
	limits: PitchLimits?
): Vector3
	local pitchLimits = limits or DEFAULT_LIMITS
	local delta = target - origin
	local horizontal = Vector3.new(delta.X, 0, delta.Z)
	local x = horizontal.Magnitude
	local y = delta.Y

	local flat: Vector3
	local pitch: number
	if x < FLAT_EPSILON then
		flat = DEFAULT_FORWARD
		pitch = if y >= 0 then math.pi / 2 else -math.pi / 2
	else
		flat = horizontal / x
		if g <= EPSILON then
			pitch = math.atan2(y, x)
		elseif speed <= EPSILON then
			pitch = math.rad(pitchLimits.noSolutionDeg)
		else
			local v2 = speed * speed
			local discriminant = v2 * v2 - g * (g * x * x + 2 * y * v2)
			if discriminant < 0 then
				pitch = math.rad(pitchLimits.noSolutionDeg)
			else
				pitch = math.atan((v2 - math.sqrt(discriminant)) / (g * x))
			end
		end
	end

	local minRad = math.rad(pitchLimits.minDeg + PITCH_INSET_DEG)
	local maxRad = math.rad(pitchLimits.maxDeg - PITCH_INSET_DEG)
	pitch = math.clamp(pitch, math.min(minRad, maxRad), math.max(minRad, maxRad))
	return flat * math.cos(pitch) + UP * math.sin(pitch)
end

-- Sweep --------------------------------------------------------------------------------------------------------------

-- Sub-step count for a span of local time (§5.7): clamp(ceil(span · perSecond), 1, maxSteps). Defaults:
-- Config.Combat.Projectile.substepsPerSecond / maxSubsteps.
function ProjectileMath.substepCount(span: number, perSecond: number?, maxSteps: number?): number
	local rate = if perSecond == nil then Config.Combat.Projectile.substepsPerSecond else perSecond
	local cap = if maxSteps == nil then Config.Combat.Projectile.maxSubsteps else maxSteps
	local count = math.ceil(span * rate - CEIL_GUARD)
	return math.clamp(count, 1, math.max(cap, 1))
end

-- Equal sub-steps covering local time (tPrev, tNow], in order: steps[1].a = tPrev, steps[#steps].b = tNow exactly,
-- and each step starts where the previous one ends. Empty when tNow <= tPrev (nothing new to sweep).
function ProjectileMath.subSteps(
	o: Vector3,
	v: Vector3,
	g: number,
	tPrev: number,
	tNow: number,
	perSecond: number?,
	maxSteps: number?
): { SubStep }
	local steps: { SubStep } = {}
	if not (tNow > tPrev) then
		return steps
	end
	local count = ProjectileMath.substepCount(tNow - tPrev, perSecond, maxSteps)
	local width = (tNow - tPrev) / count
	local a = tPrev
	local p0 = ProjectileMath.positionAt(o, v, g, a)
	for index = 1, count do
		local b = if index == count then tNow else tPrev + width * index
		local p1 = ProjectileMath.positionAt(o, v, g, b)
		table.insert(steps, { a = a, b = b, p0 = p0, p1 = p1 })
		a, p0 = b, p1
	end
	return steps
end

-- Server time of a hit found at `fraction` (0..1) of the sub-step [a, b] of a projectile released at releaseAt.
function ProjectileMath.impactTime(releaseAt: number, a: number, b: number, fraction: number): number
	return releaseAt + a + math.clamp(fraction, 0, 1) * (b - a)
end

return table.freeze(ProjectileMath)
