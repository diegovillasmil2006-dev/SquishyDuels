--!strict
-- ThrowMotion (client only, pure): the third-person throw as every player sees it (2026-10-15 throw overhaul), one
-- full-body clip per throw style (Anim/ThrowTracks' nine, by the toy's THROW_STYLE). Replaces the one three-pose arm
-- swing (Config.Anim.poses throwWindup / throwRelease / throwFollow, still used by the ultimate caster and R6).
-- Timing stays ThrowController's (the server's windup W and releaseAt; DESIGN §9.7, spec 2026-10-10 §3.6): this
-- module only says where the joints are at windup share u = tau / W, or t seconds after the release.
--   windup keys: u = 0 the hold (Config.Anim.poses.hold), a gather, u = 1 the cocked pose (held while the server is
--     late); smooth (Sine InOut) between them.
--   release keys: 0 cocked, STRIKE (the snap, Quint Out, = Config.Anim.throw.releaseSnapMs), WHIP (the overshoot,
--     Quad Out), FOLLOW (the follow-through), SETTLE (back to the hold); ThrowController fades the layer weight over
--     the last part as before (followEndMs -> returnEndMs).
-- Degrees in joint space, Config.Anim.poses' convention: +X raises an arm or leg forward (and bends an elbow), -X
-- bends a knee back, +Y turns the waist / neck / root left (an arm raised forward turns across the body), +Z takes
-- the right arm out (-Z the left). Waist +X leans back. Legs (RightHip, LeftHip, RightKnee, LeftKnee) come only when
-- `legs` is true (ThrowController: the thrower is standing when the windup starts), so a running throw never
-- freezes the run; small bends only: the Humanoid keeps the hip height, so a deep crouch would lift the feet.
-- R6 has none of this (ThrowController keeps its old poses).
--
-- API
--   ThrowMotion.styles() -> { string }                        the styles with a clip (ThrowTracks' nine)
--   ThrowMotion.windup(style, u, legs) -> { [string]: Vector3 }   joint degrees at windup share u (0..1)
--   ThrowMotion.release(style, t, legs) -> { [string]: Vector3 }  joint degrees t seconds after the release
--   ThrowMotion.JOINTS / LEGS / STRIKE / WHIP / FOLLOW / SETTLE   (tests)

-- Types

export type Pose = { [string]: Vector3 }
type Compact = { [string]: { number } } -- short joint name -> { x, y, z }
type Key = { t: number, pose: Pose, ease: string }
type Clip = { windup: { Key }, release: { Key } }

-- Constants

local STRIKE = 0.07 -- = Config.Anim.throw.releaseSnapMs / 1000 (checked by the tests)
local WHIP = 0.13
local FOLLOW = 0.26
local SETTLE = 0.45 -- = Config.Anim.throw.returnEndMs / 1000

local NAMES: { [string]: string } = {
	RS = "RightShoulder",
	RE = "RightElbow",
	RW = "RightWrist",
	LS = "LeftShoulder",
	LE = "LeftElbow",
	W = "Waist",
	N = "Neck",
	R = "Root",
	RH = "RightHip",
	LH = "LeftHip",
	RK = "RightKnee",
	LK = "LeftKnee",
}
local JOINTS: { string } = {}
for _, name in NAMES do
	table.insert(JOINTS, name)
end
table.sort(JOINTS)
local LEGS: { [string]: boolean } = { RightHip = true, LeftHip = true, RightKnee = true, LeftKnee = true }

-- The hold (Config.Anim.poses.hold, R15): where every windup starts and every release ends.
local HOLD: Compact = { RS = { 30, 0, 6 }, RE = { 75, 0, 0 } }

-- Module table

local ThrowMotion = {}
ThrowMotion.STRIKE = STRIKE
ThrowMotion.WHIP = WHIP
ThrowMotion.FOLLOW = FOLLOW
ThrowMotion.SETTLE = SETTLE
ThrowMotion.LEGS = LEGS

-- Private

-- A compact pose with every joint present (0 where it is not named), so every key blends every joint.
local function full(compact: Compact): Pose
	local pose: Pose = {}
	for short, name in NAMES do
		local v = compact[short]
		pose[name] = if v then Vector3.new(v[1] or 0, v[2] or 0, v[3] or 0) else Vector3.zero
	end
	return table.freeze(pose)
end

local function mix(a: Compact, b: Compact, u: number): Compact
	local out: Compact = {}
	for short in NAMES do
		local va = a[short] or { 0, 0, 0 }
		local vb = b[short] or { 0, 0, 0 }
		out[short] = {
			(va[1] or 0) + ((vb[1] or 0) - (va[1] or 0)) * u,
			(va[2] or 0) + ((vb[2] or 0) - (va[2] or 0)) * u,
			(va[3] or 0) + ((vb[3] or 0) - (va[3] or 0)) * u,
		}
	end
	return out
end

-- A clip from its cocked pose, its gather (default: 60% of the way from the hold) and its strike, whip and follow
-- poses; the release ends on the hold.
local function clip(def: { cocked: Compact, gather: Compact?, strike: Compact, whip: Compact, follow: Compact }): Clip
	local gather = def.gather or mix(HOLD, def.cocked, 0.6)
	return table.freeze({
		windup = table.freeze({
			{ t = 0, pose = full(HOLD), ease = "smooth" },
			{ t = 0.45, pose = full(gather), ease = "smooth" },
			{ t = 1, pose = full(def.cocked), ease = "smooth" },
		}),
		release = table.freeze({
			{ t = 0, pose = full(def.cocked), ease = "snap" },
			{ t = STRIKE, pose = full(def.strike), ease = "whip" },
			{ t = WHIP, pose = full(def.whip), ease = "smooth" },
			{ t = FOLLOW, pose = full(def.follow), ease = "smooth" },
			{ t = SETTLE, pose = full(HOLD), ease = "smooth" },
		}),
	})
end

local CLIPS: { [string]: Clip } = {
	-- Kitty Bread: the classic. Step in with the left leg, coil right, whip through and across.
	overhand = clip({
		gather = { RS = { 115, -10, -5 }, RE = { 110 }, RW = { 15 }, LS = { 45, 0, -10 }, LE = { 30 }, W = { 3, -14 }, N = { 0, 10 }, LH = { 16 }, LK = { -20 }, RK = { -8 } },
		cocked = { RS = { 165, -15, -15 }, RE = { 115 }, RW = { 25 }, LS = { 85, 20, -5 }, LE = { 10 }, W = { 6, -32 }, N = { 0, 26 }, R = { 0, -6 }, LH = { 30 }, LK = { -34 }, RH = { -6 }, RK = { -14 } },
		strike = { RS = { 100, 15 }, RE = { 20 }, RW = { -20 }, LS = { 30, 0, -25 }, LE = { 70 }, W = { -14, 22 }, N = { -6, -16 }, R = { 0, 6 }, LH = { 20 }, LK = { -8 }, RH = { -20 }, RK = { -20 } },
		whip = { RS = { 70, 40 }, RE = { 10 }, RW = { -35 }, LS = { 15, 0, -30 }, LE = { 85 }, W = { -20, 34 }, N = { -8, -20 }, R = { 0, 8 }, LH = { 22 }, LK = { -12 }, RH = { -30 }, RK = { -36 } },
		follow = { RS = { 30, 50 }, RE = { 30 }, RW = { -10 }, LS = { 20, 0, -20 }, LE = { 60 }, W = { -14, 28 }, N = { -4, -14 }, R = { 0, 6 }, LH = { 14 }, LK = { -8 }, RH = { -20 }, RK = { -26 } },
	}),
	-- Toast, Chocolate, Donut, Pancake Pup: a flat sweep, the arm out wide, a big torso twist.
	sidearm = clip({
		cocked = { RS = { 85, -75, 10 }, RE = { 35 }, RW = { 10 }, LS = { 70, 40 }, LE = { 20 }, W = { -6, -42 }, N = { 0, 34 }, R = { 0, -8 }, LH = { 22 }, LK = { -24 }, RH = { 6 }, RK = { -16 } },
		strike = { RS = { 88, 5, 5 }, RE = { 15 }, RW = { -10 }, LS = { 30, 20, -20 }, LE = { 60 }, W = { -8, 20 }, N = { -4, -12 }, R = { 0, 8 }, LH = { 24 }, LK = { -14 }, RH = { -14 }, RK = { -22 } },
		whip = { RS = { 80, 55 }, RE = { 10 }, RW = { -25 }, LS = { 20, 0, -30 }, LE = { 80 }, W = { -10, 38 }, N = { -4, -24 }, R = { 0, 10 }, LH = { 20 }, LK = { -12 }, RH = { -24 }, RK = { -32 } },
		follow = { RS = { 50, 70 }, RE = { 30 }, RW = { -10 }, LS = { 20, 0, -20 }, LE = { 60 }, W = { -8, 32 }, N = { -2, -18 }, R = { 0, 8 }, LH = { 14 }, LK = { -8 }, RH = { -16 }, RK = { -22 } },
	}),
	-- Banana: overhand from higher up, the wrist rolling through the release (it leaves spinning).
	spiral = clip({
		cocked = { RS = { 170, -5, -10 }, RE = { 120 }, RW = { 30, -70 }, LS = { 90, 10 }, LE = { 0 }, W = { 8, -26 }, N = { 0, 22 }, R = { 0, -4 }, LH = { 26 }, LK = { -30 }, RH = { -6 }, RK = { -12 } },
		strike = { RS = { 130, 5 }, RE = { 10 }, RW = { -15, 80 }, LS = { 35, 0, -25 }, LE = { 60 }, W = { -10, 18 }, N = { -4, -12 }, R = { 0, 6 }, LH = { 20 }, LK = { -8 }, RH = { -18 }, RK = { -18 } },
		whip = { RS = { 95, 25 }, RE = { 5 }, RW = { -30, 140 }, LS = { 20, 0, -30 }, LE = { 80 }, W = { -16, 30 }, N = { -6, -18 }, R = { 0, 8 }, LH = { 22 }, LK = { -12 }, RH = { -28 }, RK = { -34 } },
		follow = { RS = { 55, 40 }, RE = { 20 }, RW = { -10, 90 }, LS = { 20, 0, -20 }, LE = { 60 }, W = { -12, 24 }, N = { -4, -12 }, R = { 0, 6 }, LH = { 14 }, LK = { -8 }, RH = { -18 }, RK = { -24 } },
	}),
	-- Boba Bear, Cloud Bunny, Cupcake Axolotl: an underhand scoop that lifts the whole body and watches it fly.
	lob = clip({
		cocked = { RS = { -50, 0, 12 }, RE = { 20 }, RW = { -25 }, LS = { 50, 0, -12 }, LE = { 30 }, W = { -16, -10 }, N = { 16, 6 }, R = { 0, -4 }, LH = { 14 }, LK = { -18 }, RH = { -10 }, RK = { -14 } },
		strike = { RS = { 70, 0, 5 }, RE = { 10 }, RW = { 10 }, LS = { 20, 0, -30 }, LE = { 40 }, W = { 4, 6 }, N = { 18, -2 }, R = { 0, 4 }, LH = { 8 }, LK = { -6 }, RH = { -6 }, RK = { -6 } },
		whip = { RS = { 125, 0, 5 }, RE = { 5 }, RW = { 20 }, LS = { 30, 0, -40 }, LE = { 30 }, W = { 10, 10 }, N = { 22, -4 }, R = { 0, 4 }, LH = { 6 }, LK = { -4 }, RH = { -4 }, RK = { -4 } },
		follow = { RS = { 150, 0, 8 }, RE = { 15 }, RW = { 10 }, LS = { 25, 0, -30 }, LE = { 30 }, W = { 8, 8 }, N = { 20 }, R = { 0, 2 } },
	}),
	-- Birdie: both hands at the chest, then pushed out and opened wide: "fly!"
	glide = clip({
		cocked = { RS = { 55, 25 }, RE = { 115 }, LS = { 55, -25 }, LE = { 115 }, W = { 8 }, N = { 4 }, LH = { 10 }, LK = { -14 }, RH = { -6 }, RK = { -8 } },
		strike = { RS = { 105, 12 }, RE = { 10 }, LS = { 105, -12 }, LE = { 10 }, W = { -10 }, N = { 4 }, LH = { 18 }, LK = { -10 }, RH = { -16 }, RK = { -16 } },
		whip = { RS = { 120, -25, 15 }, RE = { 5 }, LS = { 120, 25, -15 }, LE = { 5 }, W = { -6 }, N = { 12 }, LH = { 16 }, LK = { -8 }, RH = { -14 }, RK = { -14 } },
		follow = { RS = { 115, -45, 25 }, RE = { 10 }, LS = { 115, 45, -25 }, LE = { 10 }, W = { 2 }, N = { 14 }, LH = { 10 }, LK = { -6 }, RH = { -8 }, RK = { -8 } },
	}),
	-- Butter: a low side whip with a deep lean, skimming it along the ground.
	skip = clip({
		cocked = { RS = { 40, -70, 25 }, RE = { 25 }, RW = { 15 }, LS = { 60, 30, -10 }, LE = { 20 }, W = { -18, -40 }, N = { 14, 30 }, R = { 0, -6 }, LH = { 20 }, LK = { -24 }, RH = { -6 }, RK = { -18 } },
		strike = { RS = { 42, 0, 15 }, RE = { 10 }, RW = { -10 }, LS = { 30, 20, -25 }, LE = { 50 }, W = { -20, 14 }, N = { 10, -10 }, R = { 0, 6 }, LH = { 22 }, LK = { -16 }, RH = { -16 }, RK = { -22 } },
		whip = { RS = { 45, 50, 5 }, RE = { 5 }, RW = { -25 }, LS = { 20, 0, -30 }, LE = { 70 }, W = { -20, 32 }, N = { 8, -22 }, R = { 0, 8 }, LH = { 20 }, LK = { -14 }, RH = { -24 }, RK = { -30 } },
		follow = { RS = { 35, 65 }, RE = { 25 }, RW = { -10 }, LS = { 20, 0, -20 }, LE = { 60 }, W = { -14, 30 }, N = { 4, -16 }, R = { 0, 6 }, LH = { 14 }, LK = { -10 }, RH = { -16 }, RK = { -22 } },
	}),
	-- Mochi Fox: a slingshot. The left hand holds it out, the right pulls it back to the cheek and lets go.
	sling = clip({
		gather = { RS = { 92, -10 }, RE = { 110 }, LS = { 88, 5 }, LE = { 5 }, W = { 3, -8 }, N = { 0, 6 }, LH = { 10 }, LK = { -6 } },
		cocked = { RS = { 95, -20 }, RE = { 140 }, RW = { 10 }, LS = { 90, 5 }, LE = { 0 }, W = { 6, -14 }, N = { 0, 10 }, LH = { 16 }, LK = { -10 }, RH = { -10 }, RK = { -10 } },
		strike = { RS = { 95, 0 }, RE = { 20 }, RW = { -10 }, LS = { 92, 5 }, LE = { 0 }, W = { -6, 6 }, N = { -2, -2 }, LH = { 18 }, LK = { -8 }, RH = { -12 }, RK = { -12 } },
		whip = { RS = { 100, 10 }, RE = { 5 }, RW = { -15 }, LS = { 90, 0 }, LE = { 0 }, W = { -10, 10 }, N = { -2, -6 }, LH = { 18 }, LK = { -8 }, RH = { -14 }, RK = { -14 } },
		follow = { RS = { 80, 20 }, RE = { 20 }, LS = { 60, 0, -10 }, LE = { 30 }, W = { -6, 8 }, N = { 0, -4 }, LH = { 12 }, LK = { -6 }, RH = { -8 }, RK = { -8 } },
	}),
	-- Strawberry Frog: arms up high, arched back, then a spike straight down at the ground.
	bounce = clip({
		cocked = { RS = { 180, -5, -5 }, RE = { 60 }, RW = { 30 }, LS = { 110, 0, -20 }, LE = { 30 }, W = { 12, -14 }, N = { 8, 10 }, LH = { 18 }, LK = { -20 }, RH = { -8 }, RK = { -14 } },
		strike = { RS = { 70, 5 }, RE = { 10 }, RW = { -35 }, LS = { 30, 0, -25 }, LE = { 60 }, W = { -24, 10 }, N = { -14, -6 }, LH = { 22 }, LK = { -14 }, RH = { -18 }, RK = { -22 } },
		whip = { RS = { 35, 10 }, RE = { 5 }, RW = { -45 }, LS = { 20, 0, -30 }, LE = { 70 }, W = { -30, 14 }, N = { -18, -8 }, LH = { 22 }, LK = { -14 }, RH = { -22 }, RK = { -26 } },
		follow = { RS = { 20, 20 }, RE = { 20 }, RW = { -15 }, LS = { 20, 0, -20 }, LE = { 50 }, W = { -22, 10 }, N = { -10, -4 }, LH = { 16 }, LK = { -10 }, RH = { -16 }, RK = { -20 } },
	}),
	-- Dragon: a heavy two-handed shove with a lunge.
	shove = clip({
		gather = { RS = { 60, 25 }, RE = { 110 }, LS = { 60, -25 }, LE = { 110 }, W = { 6 }, N = { -2 }, LH = { 6 }, LK = { -8 } },
		cocked = { RS = { 70, 20 }, RE = { 120 }, LS = { 70, -20 }, LE = { 120 }, W = { 10 }, N = { -4 }, LH = { 8 }, LK = { -10 }, RH = { -4 }, RK = { -10 } },
		strike = { RS = { 92, 8 }, RE = { 5 }, LS = { 92, -8 }, LE = { 5 }, W = { -18 }, N = { -6 }, LH = { 28 }, LK = { -18 }, RH = { -24 }, RK = { -16 } },
		whip = { RS = { 96, 4 }, RE = { 0 }, LS = { 96, -4 }, LE = { 0 }, W = { -22 }, N = { -8 }, LH = { 30 }, LK = { -22 }, RH = { -28 }, RK = { -20 } },
		follow = { RS = { 88, 10 }, RE = { 10 }, LS = { 88, -10 }, LE = { 10 }, W = { -14 }, N = { -4 }, LH = { 22 }, LK = { -16 }, RH = { -20 }, RK = { -14 } },
	}),
}

local STYLE_NAMES: { string } = {}
for name in CLIPS do
	table.insert(STYLE_NAMES, name)
end
table.sort(STYLE_NAMES)
table.freeze(STYLE_NAMES)

local function easeOf(kind: string, u: number): number
	local x = math.clamp(u, 0, 1)
	if kind == "snap" then
		return 1 - (1 - x) ^ 5 -- Quint Out
	elseif kind == "whip" then
		return 1 - (1 - x) * (1 - x) -- Quad Out
	end
	return 0.5 - 0.5 * math.cos(math.pi * x) -- Sine InOut
end

local function sample(keys: { Key }, t: number, legs: boolean): Pose
	local a, b, u = keys[1], keys[1], 0
	if t >= keys[#keys].t then
		a, b, u = keys[#keys], keys[#keys], 0
	elseif t > keys[1].t then
		for i = 1, #keys - 1 do
			local k0, k1 = keys[i], keys[i + 1]
			if t <= k1.t then
				a, b = k0, k1
				u = easeOf(k0.ease, (t - k0.t) / (k1.t - k0.t))
				break
			end
		end
	end
	local out: Pose = {}
	for _, joint in JOINTS do
		if legs or not LEGS[joint] then
			out[joint] = a.pose[joint]:Lerp(b.pose[joint], u)
		end
	end
	return out
end

local function clipOf(style: string): Clip
	return CLIPS[style] or CLIPS.overhand
end

-- Public

ThrowMotion.JOINTS = table.freeze(table.clone(JOINTS))

function ThrowMotion.styles(): { string }
	return STYLE_NAMES
end

function ThrowMotion.windup(style: string, u: number, legs: boolean): Pose
	local share = if u == u then math.clamp(u, 0, 1) else 0
	return sample(clipOf(style).windup, share, legs)
end

function ThrowMotion.release(style: string, t: number, legs: boolean): Pose
	local time = if t == t then math.max(t, 0) else 0
	return sample(clipOf(style).release, time, legs)
end

return ThrowMotion
