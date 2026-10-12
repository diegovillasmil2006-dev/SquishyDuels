--!strict
-- FlakePool (client only). Spec phase2-squeeze §1.15, §1.16, §3.5: the wax flakes a crack throws, the toy's jolt and the
-- re-wax sparkle of the knead screen in Inspect (design: fp.js:676-687, fx.js:64-67, 94-107, 134-141). Particles do not
-- render in a ViewportFrame (InspectController.luau:69-72), so each flake is a small pooled Part moved by script.
--
-- Pure (unit-tested; no instances):
--   FlakePool.crackSpecs(crack, rng) -> { Spec }   the flakes of one crack (crack: E, intact, position and normal of
--     the cell (world), the part's color, the camera's right / up / back (toward the viewer) axes, studsPerDu and kz
--     (KneadMath), reduced). A crack of E >= flakes.minEnergy throws with chance chanceBase + chanceIntact·intact (×
--     Config.Vfx.reducedParticleMultiplier under ReducedMotion), one flake plus one more with chance extraChance·E, in
--     the colour lerped `whiten` toward white, at the cell + normal·offset; velocity normal·U(speedMin, speedMax) +
--     right·U(±sideways) + up·U(upMin, upMax) + back·U(±depth); size U(sizeMin, sizeMax)·max(1, zoomShare·kz); life
--     U(lifeMin, lifeMax); spin U(spinMin, spinMax) rad/s about a random axis from U(0, startAngleMax) (no spin under
--     ReducedMotion); gravity along `up`. Lengths in du × studsPerDu. Every roll is rng:NextNumber() in [0, 1), in this
--     order: the gate, the count, then per flake speed, sideways, up, depth, size, life, spin, the axis' x, y, z, angle.
--   FlakePool.sparkleSpecs(centre, halfWidth, studsPerDu, rng, reduced) -> { Spec }   the re-wax burst (fp.js:687,
--     fx.js:97-107): sparkle.count stars (× reducedParticleMultiplier under ReducedMotion, at least 1) along random
--     directions d, at centre + d·spread·halfWidth, velocity d·speed·U(0.45, 1.2), size sizeDu·U(0.6, 1.4), life
--     life·U(0.7, 1.3), no gravity, drag `drag`, spin 6 rad/s (fx.js:94's default; none under ReducedMotion), White and
--     WaxSparkle in turn.
--   FlakePool.scaleAt(u, reduced) -> number   the size over u = age / life (fx.js:139): popPeak·sin(u / popEnd·popArc·π)
--     before popEnd (1 under ReducedMotion: no scale pops), 1, then 1 - ((u - fadeStart) / (1 - fadeStart))^fadePower
--   FlakePool.stepParticle(p, v, g, drag, dt) -> (p, v)   v += g·dt; v ×= e^(-drag·dt); p += v·dt (fx.js:135-136)
--   FlakePool.chipBox() -> Vector3   the chip's bounding box at size 1 (fx.js:67: radii `chip` every 60°, chipDepth deep)
--   FlakePool.joltAfter(jolt, E, intact, reduced) -> number   max(jolt, gain·E·(intactBase + (1 - intactBase)·intact))
--     du for E > jolt.minEnergy (fp.js:678); 0 under ReducedMotion (a shake)
--   FlakePool.joltDecay(jolt, dt) -> number   jolt·e^(-decay·dt) (fp.js:480)
-- The pool:
--   FlakePool.new(parent, cap) -> Pool   a Folder "SD_KneadFlakes" under `parent` (the stage's ViewportFrame)
--   pool:spawn(spec) -> boolean          false past `cap` live flakes (dropped); parts are reused
--   pool:step(dt)                        moves every live one (stepParticle, spin, scaleAt) and retires the old ones
--   pool:count() / clear() / destroy()
-- A flake is an anchored, non-colliding, non-queried SmoothPlastic block of the chip's box (a sparkle: the star's box)
-- × size × scaleAt (the closest shape without an uploaded mesh, spec §3.5).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

export type Crack = {
	E: number,
	intact: number,
	position: Vector3,
	normal: Vector3,
	color: Color3,
	right: Vector3,
	up: Vector3,
	back: Vector3,
	studsPerDu: number,
	kz: number,
	reduced: boolean,
}

export type Spec = {
	position: Vector3,
	velocity: Vector3,
	gravity: Vector3,
	drag: number,
	size: number, -- studs (× box)
	life: number,
	spin: number, -- rad/s
	axis: Vector3,
	angle: number,
	color: Color3,
	box: Vector3,
	reduced: boolean,
}

type Flake = {
	part: BasePart,
	spec: Spec,
	position: Vector3,
	velocity: Vector3,
	age: number,
}

type PoolData = {
	_root: Folder,
	_cap: number,
	_live: { Flake },
	_idle: { BasePart },
}

local FLAKES = Config.Wax.flakes
local SPARKLE = Config.Wax.sparkle
local JOLT = Config.Wax.jolt
local REDUCED_MULTIPLIER = Config.Vfx.reducedParticleMultiplier
local SPARKLE_SPIN = 6 -- rad/s: fx.js:94's default spin (o.spin ?? 6)
local SPARKLE_SPEED_MIN, SPARKLE_SPEED_SPAN = 0.45, 0.75 -- design: fx.js:103
local SPARKLE_SIZE_MIN, SPARKLE_SIZE_SPAN = 0.6, 0.8 -- design: fx.js:104
local SPARKLE_LIFE_MIN, SPARKLE_LIFE_SPAN = 0.7, 0.6 -- design: fx.js:104
local ROOT_NAME = "SD_KneadFlakes"
local PART_NAME = "Flake"
local MIN_AXIS = 1e-6
local WHITE = Color3.new(1, 1, 1)

local PoolClass = {}
PoolClass.__index = PoolClass

export type Pool = typeof(setmetatable({} :: PoolData, PoolClass))

local FlakePool = {}

-- A uniform value in [a, b) from one rng:NextNumber() roll.
local function between(rng: Random, a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

-- A random unit axis from three rolls (the design's V3(R - 0.5, R - 0.5, R - 0.5).normalize()).
local function randomAxis(rng: Random): Vector3
	local axis = Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5)
	return if axis.Magnitude < MIN_AXIS then Vector3.yAxis else axis.Unit
end

-- Public: pure

function FlakePool.crackSpecs(crack: Crack, rng: Random): { Spec }
	local specs: { Spec } = {}
	local E = crack.E
	if E < FLAKES.minEnergy then
		return specs
	end
	local chance = (FLAKES.chanceBase + FLAKES.chanceIntact * crack.intact)
		* (if crack.reduced then REDUCED_MULTIPLIER else 1)
	if rng:NextNumber() > chance then
		return specs
	end
	local count = 1 + (if rng:NextNumber() < FLAKES.extraChance * E then 1 else 0)
	local scale = crack.studsPerDu
	local color = crack.color:Lerp(WHITE, FLAKES.whiten)
	local gravity = crack.up * FLAKES.gravity * scale
	local start = crack.position + crack.normal * FLAKES.offset * scale
	local zoom = math.max(1, FLAKES.zoomShare * crack.kz)
	local box = FlakePool.chipBox()
	for _ = 1, count do
		local along = between(rng, FLAKES.speedMin, FLAKES.speedMax)
		local side = between(rng, -FLAKES.sideways, FLAKES.sideways)
		local up = between(rng, FLAKES.upMin, FLAKES.upMax)
		local depth = between(rng, -FLAKES.depth, FLAKES.depth)
		local size = between(rng, FLAKES.sizeMin, FLAKES.sizeMax)
		local life = between(rng, FLAKES.lifeMin, FLAKES.lifeMax)
		local spin = between(rng, FLAKES.spinMin, FLAKES.spinMax)
		local axis = randomAxis(rng)
		local angle = rng:NextNumber() * FLAKES.startAngleMax
		local velocity = crack.normal * along + crack.right * side + crack.up * up + crack.back * depth
		table.insert(specs, {
			position = start,
			velocity = velocity * scale,
			gravity = gravity,
			drag = FLAKES.drag,
			size = size * zoom * scale,
			life = life,
			spin = if crack.reduced then 0 else spin,
			axis = axis,
			angle = angle,
			color = color,
			box = box,
			reduced = crack.reduced,
		})
	end
	return specs
end

function FlakePool.sparkleSpecs(
	centre: Vector3,
	halfWidth: number,
	studsPerDu: number,
	rng: Random,
	reduced: boolean
): { Spec }
	local count = if reduced then math.max(1, math.floor(SPARKLE.count * REDUCED_MULTIPLIER)) else SPARKLE.count
	local colors = { Palette.White, Palette.WaxSparkle }
	local specs: { Spec } = {}
	for index = 1, count do
		local direction = randomAxis(rng)
		local speed = SPARKLE.speed * (SPARKLE_SPEED_MIN + rng:NextNumber() * SPARKLE_SPEED_SPAN)
		local size = SPARKLE.sizeDu * (SPARKLE_SIZE_MIN + rng:NextNumber() * SPARKLE_SIZE_SPAN)
		local life = SPARKLE.life * (SPARKLE_LIFE_MIN + rng:NextNumber() * SPARKLE_LIFE_SPAN)
		table.insert(specs, {
			position = centre + direction * SPARKLE.spread * halfWidth,
			velocity = direction * speed * studsPerDu,
			gravity = Vector3.zero,
			drag = SPARKLE.drag,
			size = size * studsPerDu,
			life = life,
			spin = if reduced then 0 else SPARKLE_SPIN,
			axis = randomAxis(rng),
			angle = rng:NextNumber() * FLAKES.startAngleMax,
			color = colors[(index - 1) % #colors + 1],
			box = SPARKLE.star,
			reduced = reduced,
		})
	end
	return specs
end

function FlakePool.scaleAt(u: number, reduced: boolean): number
	if u >= 1 then
		return 0
	elseif u < FLAKES.popEnd then
		return if reduced then 1 else FLAKES.popPeak * math.sin(u / FLAKES.popEnd * FLAKES.popArc * math.pi)
	elseif u > FLAKES.fadeStart then
		return 1 - ((u - FLAKES.fadeStart) / (1 - FLAKES.fadeStart)) ^ FLAKES.fadePower
	end
	return 1
end

function FlakePool.stepParticle(p: Vector3, v: Vector3, g: Vector3, drag: number, dt: number): (Vector3, Vector3)
	local velocity = (v + g * dt) * math.exp(-drag * dt)
	return p + velocity * dt, velocity
end

function FlakePool.chipBox(): Vector3
	local radii = FLAKES.chip
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for index, r in radii do
		local a = (index - 1) / #radii * 2 * math.pi
		local x, y = math.cos(a) * r, math.sin(a) * r
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minY, maxY = math.min(minY, y), math.max(maxY, y)
	end
	return Vector3.new(maxX - minX, maxY - minY, FLAKES.chipDepth)
end

function FlakePool.joltAfter(jolt: number, E: number, intact: number, reduced: boolean): number
	if reduced then
		return 0
	end
	if E <= JOLT.minEnergy then
		return jolt
	end
	return math.max(jolt, JOLT.gain * E * (JOLT.intactBase + (1 - JOLT.intactBase) * intact))
end

function FlakePool.joltDecay(jolt: number, dt: number): number
	return jolt * math.exp(-JOLT.decay * dt)
end

-- Public: the pool

function FlakePool.new(parent: Instance, cap: number): Pool
	local root = Instance.new("Folder")
	root.Name = ROOT_NAME
	root.Parent = parent
	local data: PoolData = { _root = root, _cap = cap, _live = {}, _idle = {} }
	return setmetatable(data, PoolClass)
end

local function newPart(): BasePart
	local part = Instance.new("Part")
	part.Name = PART_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Massless = true
	part.Material = Enum.Material.SmoothPlastic
	return part
end

local function place(flake: Flake)
	local spec = flake.spec
	local scale = FlakePool.scaleAt(flake.age / spec.life, spec.reduced)
	local part = flake.part
	part.Size = spec.box * math.max(spec.size * scale, 1e-3)
	part.CFrame = CFrame.new(flake.position) * CFrame.fromAxisAngle(spec.axis, spec.angle + spec.spin * flake.age)
end

function PoolClass.spawn(self: Pool, spec: Spec): boolean
	if #self._live >= self._cap or spec.life <= 0 then
		return false
	end
	local part = table.remove(self._idle) or newPart()
	part.Color = spec.color
	local flake: Flake = { part = part, spec = spec, position = spec.position, velocity = spec.velocity, age = 0 }
	place(flake)
	part.Parent = self._root
	table.insert(self._live, flake)
	return true
end

function PoolClass.step(self: Pool, dt: number)
	local live = self._live
	for index = #live, 1, -1 do
		local flake = live[index]
		flake.age += dt
		if flake.age >= flake.spec.life then
			flake.part.Parent = nil
			table.insert(self._idle, flake.part)
			live[index] = live[#live]
			live[#live] = nil
		else
			local spec = flake.spec
			flake.position, flake.velocity =
				FlakePool.stepParticle(flake.position, flake.velocity, spec.gravity, spec.drag, dt)
			place(flake)
		end
	end
end

function PoolClass.count(self: Pool): number
	return #self._live
end

function PoolClass.clear(self: Pool)
	for _, flake in self._live do
		flake.part.Parent = nil
		table.insert(self._idle, flake.part)
	end
	table.clear(self._live)
end

function PoolClass.destroy(self: Pool)
	table.clear(self._live)
	for _, part in self._idle do
		part:Destroy()
	end
	table.clear(self._idle)
	self._root:Destroy()
end

return FlakePool
