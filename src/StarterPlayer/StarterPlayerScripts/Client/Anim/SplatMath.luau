--!strict
-- SplatMath (client only; pure: no instances, no connections, no clock). DESIGN §18.4.1, Config.Vfx.Splat.
-- The numbers behind SplatController's splats: colour, droplets, the timeline sample, the size spec, the eviction
-- choice and the practice floor fix.
--
-- * color(accent): accent:Lerp(White, whiten 0.25); a hue within redHueDeg (15°) of red with HSV saturation above
--   redMinSaturation (0.45) whitens by redGuardWhiten (0.6) instead (pink, never red: whitening by t leaves a
--   saturation of at most 1 - t).
-- * droplets(rng, d): `droplets` (4) of size 0.16-0.30 d at 0.55-0.85 d from the centre, spread around the blob.
-- * sample(t, isWall, reduced?): main blob 0 -> 1.12 at 70 ms (Quad Out) -> 1.0 at 160 ms (Sine InOut); droplets from
--   40 ms, 0 -> 1 in 80 ms (Back Out); held until 1.6 s, then Transparency 0.1 -> 1 and scale 1 -> 0.9 by 2.5 s (Quad
--   In); on a wall the lowest droplet slides dripStuds down between 0.3 s and 1.6 s (Quad In), stretching 1 -> 1.4.
--   ReducedMotion: full size at once (no overshoot, droplet pop or drip); the slow fade stays.
-- * spec(radius, curved, normal): d = 2.2 × the throw radius; on a curved part (a gumdrop's Ball or Cylinder) the
--   main blob only, d <= 1.6, no droplets or drip.
-- Easing curves are the standard Roblox ones (TweenService), written out so this module needs no service.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

-- Types

export type Droplet = {
	size: number, -- studs (the droplet's diameter)
	dist: number, -- studs from the splat centre
	angle: number, -- radians about the normal
}

export type Spec = {
	d: number, -- main blob diameter, studs
	curved: boolean,
	wall: boolean,
	droplets: boolean,
	drip: boolean,
}

export type Sample = {
	main: number, -- main blob scale (× its full size)
	droplet: number, -- droplet scale (× each droplet's size)
	transparency: number,
	drip: number, -- 0..1 of the lowest droplet's slide (× dripStuds)
	dripStretch: number, -- 1 .. dripStretch
	done: boolean,
}

-- What pickEvict needs to know about a live splat.
export type Evictable = { bornAt: number, low: boolean? }

-- Constants

local SPLAT = Config.Vfx.Splat
local WHITE = Palette.White
local BACK_S = 1.70158
local HOLD_S = SPLAT.holdSeconds
local FADE_S = SPLAT.fadeSeconds
local GROW_S = SPLAT.growMs / 1000
local SETTLE_S = SPLAT.settleMs / 1000
local DROP_DELAY_S = SPLAT.dropletDelayMs / 1000
local DROP_GROW_S = SPLAT.dropletGrowMs / 1000
-- reading (not in DESIGN): droplets sit evenly around the blob, each turned by up to ±30% of its share at random,
-- so they never clump on one side.
local ANGLE_JITTER = 0.3
-- reading: a practice floor impact sits at FLOOR_Y + radius (CombatService's analytic floor test); this much
-- rounding is allowed above that.
local FLOOR_TOLERANCE = 0.05

-- Module table

local SplatMath = {}

-- Private

local function clamp01(u: number): number
	return math.clamp(u, 0, 1)
end

local function quadOut(u: number): number
	local x = clamp01(u)
	return 1 - (1 - x) * (1 - x)
end

local function quadIn(u: number): number
	local x = clamp01(u)
	return x * x
end

local function sineInOut(u: number): number
	local x = clamp01(u)
	return -(math.cos(math.pi * x) - 1) / 2
end

local function backOut(u: number): number
	local x = clamp01(u) - 1
	return 1 + (BACK_S + 1) * x * x * x + BACK_S * x * x
end

-- Public

-- True for a colour SplatMath must never show: a hue within redHueDeg of red with saturation above redMinSaturation.
function SplatMath.isRed(color: Color3): boolean
	local h, s = color:ToHSV()
	local hueDeg = h * 360
	local fromRed = math.min(hueDeg, 360 - hueDeg)
	return fromRed <= SPLAT.redHueDeg and s > SPLAT.redMinSaturation
end

-- The splat (and geometry puff) colour for a squishy accent.
function SplatMath.color(accent: Color3): Color3
	local t = if SplatMath.isRed(accent) then SPLAT.redGuardWhiten else SPLAT.whiten
	return accent:Lerp(WHITE, t)
end

-- `Splat.droplets` droplets for a blob of diameter d, from `rng` (a Random: the same seed gives the same droplets).
function SplatMath.droplets(rng: Random, d: number): { Droplet }
	local count = SPLAT.droplets
	local list: { Droplet } = {}
	local share = 2 * math.pi / math.max(count, 1)
	local offset = rng:NextNumber(0, 2 * math.pi)
	for i = 1, count do
		table.insert(list, {
			size = d * rng:NextNumber(SPLAT.dropletSizeMin, SPLAT.dropletSizeMax),
			dist = d * rng:NextNumber(SPLAT.dropletDistMin, SPLAT.dropletDistMax),
			angle = offset + (i - 1) * share + rng:NextNumber(-ANGLE_JITTER, ANGLE_JITTER) * share,
		})
	end
	return list
end

-- True when the surface is a wall (|n.Y| below wallNormalMaxY): its splat drips.
function SplatMath.isWall(normal: Vector3): boolean
	return math.abs(normal.Y) < SPLAT.wallNormalMaxY
end

-- The size spec of a splat for a throw of `radius` on a surface with `normal`; curved = a Ball or Cylinder part.
function SplatMath.spec(radius: number, curved: boolean, normal: Vector3): Spec
	local d = SPLAT.diameterPerRadius * radius
	local wall = SplatMath.isWall(normal)
	if curved then
		return {
			d = math.min(d, SPLAT.curvedMaxDiameter),
			curved = true,
			wall = wall,
			droplets = false,
			drip = false,
		}
	end
	return { d = d, curved = false, wall = wall, droplets = SPLAT.droplets > 0, drip = wall }
end

-- The splat `t` seconds after it appeared. isWall: it drips. reduced: ReducedMotion (full size at once, no drip).
function SplatMath.sample(t: number, isWall: boolean, reduced: boolean?): Sample
	local time = math.max(t, 0)
	local main: number
	local droplet: number
	if reduced == true then
		main, droplet = 1, 1
	else
		if time < GROW_S then
			main = SPLAT.overshoot * quadOut(time / GROW_S)
		elseif time < GROW_S + SETTLE_S then
			main = SPLAT.overshoot + (1 - SPLAT.overshoot) * sineInOut((time - GROW_S) / SETTLE_S)
		else
			main = 1
		end
		if time < DROP_DELAY_S then
			droplet = 0
		else
			droplet = backOut((time - DROP_DELAY_S) / DROP_GROW_S)
		end
	end
	local drip, stretch = 0, 1
	if isWall and reduced ~= true and time > SPLAT.dripFromSeconds then
		drip = quadIn((time - SPLAT.dripFromSeconds) / math.max(HOLD_S - SPLAT.dripFromSeconds, 1e-3))
		stretch = 1 + (SPLAT.dripStretch - 1) * drip
	end
	local transparency = SPLAT.transparency
	if time > HOLD_S then
		local u = quadIn((time - HOLD_S) / FADE_S)
		transparency += (1 - SPLAT.transparency) * u
		local shrink = 1 + (SPLAT.fadeScaleTo - 1) * u
		main *= shrink
		droplet *= shrink
	end
	return {
		main = main,
		droplet = droplet,
		transparency = transparency,
		drip = drip,
		dripStretch = stretch,
		done = time >= HOLD_S + FADE_S,
	}
end

-- An evicted splat's transparency `elapsed` seconds into its evictFadeSeconds fade from `from`, and whether it is gone.
function SplatMath.evicted(from: number, elapsed: number): (number, boolean)
	local u = clamp01(elapsed / math.max(SPLAT.evictFadeSeconds, 1e-3))
	return from + (1 - from) * u, u >= 1
end

-- The lift off the surface for the splat with this serial: newer splats sit on top, so nothing flickers.
function SplatMath.lift(serial: number): number
	return SPLAT.lift + (serial % SPLAT.layers) * SPLAT.layerStep
end

-- Which live splat to evict for a new one (index into `splats`), or nil for an empty list: the oldest of other
-- players' practice splats (`low`, dropped first), else the oldest.
function SplatMath.pickEvict(splats: { Evictable }): number?
	local best: number? = nil
	local bestLow = false
	local bestBorn = math.huge
	for index, splat in splats do
		local low = splat.low == true
		if best == nil or (low and not bestLow) or (low == bestLow and splat.bornAt < bestBorn) then
			best, bestLow, bestBorn = index, low, splat.bornAt
		end
	end
	return best
end

-- Where a splat (or ring) goes for an impact at `position`: a practice lane-floor hit carries the projectile centre
-- (FLOOR_Y + radius, normal exactly up: CombatService's analytic floor test), so it is dropped to floorY. Every other
-- impact is already on its surface.
function SplatMath.surfacePoint(
	position: Vector3,
	normal: Vector3,
	radius: number,
	practice: boolean,
	floorY: number
): Vector3
	if practice and normal.Y > 0.999 and position.Y <= floorY + radius + FLOOR_TOLERANCE then
		return Vector3.new(position.X, floorY, position.Z)
	end
	return position
end

return SplatMath
