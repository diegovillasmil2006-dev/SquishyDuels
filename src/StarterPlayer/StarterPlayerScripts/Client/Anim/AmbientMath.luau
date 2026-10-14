--!strict
-- AmbientMath (client only, pure). DESIGN §18.5.1 A8, §9.15 "Ambient": the lobby background motion of the SD_Ambient
-- decor, always as the built (base) pose × f(t), never added up frame by frame, so a model that was culled or paused
-- comes back exactly where the clock says and never drifts.
--
-- Kinds (attribute SD_AmbientKind, set by LobbyBuilder):
--   "spin"     the lollipops: about the stick's world Y (the model pivot is the stick's foot), lollipopDegPerSecond
--              (10°/s, 36 s a turn); odd-numbered ones (Lollipop1, 3) turn +, even ones (2, 4) turn -
--   "spinBob"  the daily gift box: giftSpinDegPerSecond (18°/s) plus a bob
--              giftBobStuds · (0.5 - 0.5 cos(2πt / giftBobPeriod)), always >= 0, so it never sinks into the pedestal
--   "breathe"  the counter gift box (counterBreathe*) and the statue (statueBreathe*, by its name "Statue"): a mesh-only
--              scale through SquishDeformer, S.Y = 1 + A·b and S.X = S.Z = 1 - (A/2)·b with b = 0.5 - 0.5 cos(2πt/T)
-- Reading (A8 writes "S.Y = 1 + A sin"; §18.11's AmbientMath_Test bound is "S in [1 - A/2, 1 + A]"): only a one-sided
-- breath (b in [0, 1], like the gift box bob) meets that bound; it also never lifts the model's foot above its stand
-- (the deformer scales about the model pivot, above the foot), and b = 0 is the exact built pose.
-- Each instance gets its own phase (0..1 of a period) from its name. ReducedMotion: the exact rest pose (identity
-- offset, scale 1). Culling: sphereOnScreen (a model moves only while its bounding sphere is on screen).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

-- Types

export type Kind = "spin" | "spinBob" | "breathe"

-- The motion of one SD_Ambient instance (spec()).
export type Spec = {
	kind: Kind,
	degPerSecond: number, -- signed spin rate (0 for breathers)
	bobStuds: number, -- 0 unless spinBob
	bobPeriod: number,
	breatheAmp: number, -- 0 unless breathe
	breathePeriod: number,
}

export type AmbientConfig = typeof(Config.Vfx.Ambient)

-- Constants

local AMBIENT: AmbientConfig = Config.Vfx.Ambient
local TAU = 2 * math.pi
local HASH_MODULUS = 4294967296 -- 2^32: the name hash stays an exact integer in a double
local HASH_MULTIPLIER = 33
local STATUE_NAME = "Statue" -- SqueezeZone/Statue (LobbyBuilder)
local KINDS: { [string]: boolean } = { spin = true, spinBob = true, breathe = true }

-- Module table

local AmbientMath = {}

-- Private

-- 0.5 - 0.5 cos(2π (t / period + phase)): 0 at rest, 1 at the top of the cycle.
local function swell(period: number, t: number, phase: number): number
	if not (period > 0) then
		return 0
	end
	return 0.5 - 0.5 * math.cos(TAU * (t / period + phase))
end

-- Public

-- True for a known SD_AmbientKind value.
function AmbientMath.isKind(value: unknown): boolean
	return type(value) == "string" and KINDS[value] == true
end

-- A stable phase in [0, 1) from an instance name (djb2-style hash), so every instance moves on its own beat.
function AmbientMath.phaseOf(name: string): number
	local h = 5381
	for index = 1, #name do
		h = (h * HASH_MULTIPLIER + string.byte(name, index)) % HASH_MODULUS
	end
	return h / HASH_MODULUS
end

-- +1 for a name ending in an odd number (or no number), -1 for an even one ("Lollipop2").
function AmbientMath.spinSign(name: string): number
	local digits = string.match(name, "(%d+)$")
	local n = if digits then tonumber(digits) else nil
	if n ~= nil and n % 2 == 0 then
		return -1
	end
	return 1
end

-- The motion spec of an SD_Ambient instance of `kind` named `name`, or nil for an unknown kind.
function AmbientMath.spec(kind: string, name: string, config: AmbientConfig?): Spec?
	local a = config or AMBIENT
	if kind == "spin" then
		return {
			kind = "spin",
			degPerSecond = a.lollipopDegPerSecond * AmbientMath.spinSign(name),
			bobStuds = 0,
			bobPeriod = 0,
			breatheAmp = 0,
			breathePeriod = 0,
		}
	elseif kind == "spinBob" then
		return {
			kind = "spinBob",
			degPerSecond = a.giftSpinDegPerSecond,
			bobStuds = a.giftBobStuds,
			bobPeriod = a.giftBobPeriod,
			breatheAmp = 0,
			breathePeriod = 0,
		}
	elseif kind == "breathe" then
		local statue = name == STATUE_NAME
		return {
			kind = "breathe",
			degPerSecond = 0,
			bobStuds = 0,
			bobPeriod = 0,
			breatheAmp = if statue then a.statueBreatheAmp else a.counterBreatheAmp,
			breathePeriod = if statue then a.statueBreathePeriod else a.counterBreathePeriod,
		}
	end
	return nil
end

-- The spin angle in degrees, [0, 360): the phase's angle plus rate · t, computed from t (never accumulated).
function AmbientMath.angleDeg(degPerSecond: number, t: number, phase: number): number
	return (phase * 360 + degPerSecond * t) % 360
end

-- The bob height in studs, in [0, studs].
function AmbientMath.bob(studs: number, period: number, t: number, phase: number): number
	return studs * swell(period, t, phase)
end

-- The breathing scale: S.Y = 1 + amp·b, S.X = S.Z = 1 - (amp/2)·b, b in [0, 1].
function AmbientMath.breathe(amp: number, period: number, t: number, phase: number): Vector3
	local b = swell(period, t, phase)
	local wide = 1 - amp / 2 * b
	return Vector3.new(wide, 1 + amp * b, wide)
end

-- The pivot offset of a mover (spin, spinBob) at time t: base pivot × this. Identity for breathers and under
-- ReducedMotion (the exact rest pose).
function AmbientMath.offset(spec: Spec, t: number, phase: number, reduced: boolean): CFrame
	if reduced or spec.kind == "breathe" then
		return CFrame.identity
	end
	local angle = math.rad(AmbientMath.angleDeg(spec.degPerSecond, t, phase))
	local lift = AmbientMath.bob(spec.bobStuds, spec.bobPeriod, t, phase)
	return CFrame.new(0, lift, 0) * CFrame.Angles(0, angle, 0)
end

-- The deformer scale of a breather at time t. (1, 1, 1) for movers and under ReducedMotion (the exact rest pose).
function AmbientMath.scale(spec: Spec, t: number, phase: number, reduced: boolean): Vector3
	if reduced or spec.kind ~= "breathe" then
		return Vector3.one
	end
	return AmbientMath.breathe(spec.breatheAmp, spec.breathePeriod, t, phase)
end

-- True for the kinds that move the model pivot (they use the ambientMovers budget); breathers deform meshes instead
-- (they count in deformingRigs at the lowest priority).
function AmbientMath.isMover(spec: Spec): boolean
	return spec.kind ~= "breathe"
end

-- Whether a bounding sphere is on screen (A8 culling), from Camera:WorldToViewportPoint of its centre (screenX,
-- screenY in pixels, depth in studs), its radius, the viewport size and tan(FieldOfView / 2) (vertical). Reading: the
-- giant pads' rule (they went in build plan Phase 6), restated here so the lobby decor needed no lobby pad controller
-- (and HeldSquishyController, which duel code requires, never reaches one through AmbientController).
function AmbientMath.sphereOnScreen(
	screenX: number,
	screenY: number,
	depth: number,
	radius: number,
	viewport: Vector2,
	tanHalfFov: number
): boolean
	if depth < -radius then
		return false -- wholly behind the camera
	end
	if depth <= radius then
		return true -- the camera is inside or right next to it
	end
	local pixels = radius * viewport.Y / (2 * depth * tanHalfFov)
	return screenX >= -pixels
		and screenX <= viewport.X + pixels
		and screenY >= -pixels
		and screenY <= viewport.Y + pixels
end

return AmbientMath
