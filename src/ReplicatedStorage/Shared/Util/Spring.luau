--!strict
-- Spring (shared: server and client; used by the client animation runtime). An underdamped spring
-- x'' = -ω²(x - target) - 2ζω·x' (DESIGN §9.2), integrated with semi-implicit Euler (v += a·h, then x += v·h).
-- Used for wobble, flinch, pop-in and reveals (§9.4-§9.6, §9.11).
--
-- Substeps (§9.1 #4, Config.Anim.Scheduler): a dt up to springSubstepAbove (1/60 s) is one Euler step; a longer dt is
-- split into equal substeps of at most springSubstep (1/120 s), so a frame hitch never makes the spring blow up.
-- Values: number or Vector3 (one spring type for both; the kind is fixed by the first value).
-- Pure: no instances, connections, yields or clock reads; the caller passes dt (the Scheduler already clamps it to
-- <= 1/20 s). A dt that is <= 0 or not finite does nothing.
--
--   local s = Spring.new(0.6, 16, 0.55, 1)   -- position, omega, zeta, target (default = position)
--   s:step(dt)                                -- returns the new position
--   s:impulse(0.06)                           -- adds velocity
--   s:isSettled(0.002)                        -- |x - target| and |v| below epsilon

-- Requires

local Config = require(script.Parent.Parent.Config)

-- Types

export type Spring<T> = {
	position: T,
	velocity: T,
	target: T,
	omega: number,
	zeta: number,
	step: (self: Spring<T>, dt: number) -> T,
	impulse: (self: Spring<T>, velocity: T) -> (),
	setTarget: (self: Spring<T>, target: T) -> (),
	reset: (self: Spring<T>, position: T, velocity: T?) -> (),
	isSettled: (self: Spring<T>, epsilon: number) -> boolean,
}

-- Constants

local SUBSTEP = Config.Anim.Scheduler.springSubstep -- 1/120 s
local SUBSTEP_ABOVE = Config.Anim.Scheduler.springSubstepAbove -- 1/60 s
-- Safety bound on the work per call when a caller passes a huge dt (the Scheduler never does); the substep then grows
-- to dt / MAX_SUBSTEPS. Not a tunable.
local MAX_SUBSTEPS = 240

-- Module table

local SpringClass = {}
SpringClass.__index = SpringClass

local Spring = {}

-- Private

local function isFinite(n: number): boolean
	return n == n and n ~= math.huge and n ~= -math.huge
end

local function kindOf(value: unknown): string
	local kind = typeof(value)
	if kind == "number" then
		assert(isFinite(value :: number), "[SD][Spring] value must be a finite number")
		return kind
	elseif kind == "Vector3" then
		return kind
	end
	error(`[SD][Spring] value must be a number or a Vector3 (got {kind})`, 3)
end

local function zeroOf(kind: string): any
	return if kind == "number" then 0 else Vector3.zero
end

local function magnitude(value: any): number
	if type(value) == "number" then
		return math.abs(value)
	end
	return (value :: Vector3).Magnitude
end

-- One semi-implicit Euler step of length h. Values are numbers or Vector3s (same kind).
local function eulerStep(x: any, v: any, target: any, omega: number, zeta: number, h: number): (any, any)
	local a = (target - x) * (omega * omega) - v * (2 * zeta * omega)
	local nextV = v + a * h
	return x + nextV * h, nextV
end

-- Public: stateless

-- Advances (x, v) toward target by dt with the substep rule above and returns the new (x, v). x, v and target must
-- be the same kind (number or Vector3).
function Spring.integrate<T>(x: T, v: T, target: T, omega: number, zeta: number, dt: number): (T, T)
	if not (dt > 0) or not isFinite(dt) then
		return x, v
	end
	local steps = 1
	if dt > SUBSTEP_ABOVE then
		steps = math.min(math.ceil(dt / SUBSTEP - 1e-9), MAX_SUBSTEPS)
	end
	local h = dt / steps
	local px: any, pv: any = x, v
	for _ = 1, steps do
		px, pv = eulerStep(px, pv, target, omega, zeta, h)
	end
	return px, pv
end

-- Public: objects

-- Creates a spring at `position` (velocity 0) pulled toward `target` (default: position). omega > 0 (rad/s),
-- zeta >= 0 (< 1 = underdamped, overshoots).
function Spring.new<T>(position: T, omega: number, zeta: number, target: T?): Spring<T>
	local kind = kindOf(position)
	assert(type(omega) == "number" and isFinite(omega) and omega > 0, "[SD][Spring] omega must be a finite number > 0")
	assert(type(zeta) == "number" and isFinite(zeta) and zeta >= 0, "[SD][Spring] zeta must be a finite number >= 0")
	local goal: T = if target == nil then position else target
	assert(kindOf(goal) == kind, "[SD][Spring] target must be the same kind as position")
	local self = {
		position = position,
		velocity = zeroOf(kind),
		target = goal,
		omega = omega,
		zeta = zeta,
		_kind = kind,
	}
	return setmetatable(self, SpringClass) :: any
end

-- Advances by dt (seconds) and returns the new position.
function SpringClass.step(self: any, dt: number): any
	self.position, self.velocity =
		Spring.integrate(self.position, self.velocity, self.target, self.omega, self.zeta, dt)
	return self.position
end

-- Adds `velocity` to the current velocity (a kick).
function SpringClass.impulse(self: any, velocity: any)
	assert(kindOf(velocity) == self._kind, "[SD][Spring] impulse must be the same kind as the spring")
	self.velocity += velocity
end

function SpringClass.setTarget(self: any, target: any)
	assert(kindOf(target) == self._kind, "[SD][Spring] target must be the same kind as the spring")
	self.target = target
end

-- Jumps to `position` with `velocity` (default 0). The target is unchanged.
function SpringClass.reset(self: any, position: any, velocity: any?)
	assert(kindOf(position) == self._kind, "[SD][Spring] position must be the same kind as the spring")
	local v = if velocity == nil then zeroOf(self._kind) else velocity
	assert(kindOf(v) == self._kind, "[SD][Spring] velocity must be the same kind as the spring")
	self.position = position
	self.velocity = v
end

-- True when both the distance to the target and the speed are below epsilon.
function SpringClass.isSettled(self: any, epsilon: number): boolean
	return magnitude(self.position - self.target) < epsilon and magnitude(self.velocity) < epsilon
end

return Spring
