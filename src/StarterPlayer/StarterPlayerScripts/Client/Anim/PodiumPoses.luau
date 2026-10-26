--!strict
-- PodiumPoses (client only, pure). End screens round B1 (2026-10-26; owner: "Yes, build step 1 of round B like that.
-- You can make and upload the sounds."): Diego's podium and "good game" pose clips for the R15 rig (`P:n` = his
-- uploads/sd/poses.js line n, `A:n` = uploads/sd/avatar.js), as plain numbers: no instances, connections or clock
-- reads. UI/Match/MatchPodium plays them on the podium's copies of the players.
-- * Keys at FPS = 30 (P:7): each joint is the design's Euler XYZ degrees, `off` the root offset in studs (P:2). A key
--   names only what it changes; every other joint carries over from the key before (P:200-211), and a joint it names
--   with fewer than 3 numbers has 0 for the rest (P:202). A segment eases by its end key's easing (P:221-225).
-- * The held squishy is a prop track (P:3): where it sits ("hand", "head", "chest", "hands" between them, "air" at a
--   point of the slot), its offset `o` (studs), turn `r` (Euler XYZ degrees) and squash `sc` (P:209-210).
-- * The design's avatar faces +Z with its left arm on +X (A:33, 44); ours faces -Z with it on -X: a 180° turn about Y,
--   so a design rotation Rx(a)·Ry(b)·Rz(c) is Rx(-a)·Ry(b)·Rz(-c) here (jointCFrame) and an offset (x, y, z) is
--   (-x, y, -z) (flip); the rule of Config.Anim.poses.hold, here with the XYZ order kept (the spins turn about Y).
-- API
--   PodiumPoses.FPS, CLIPS, VICTORY_ORDER, DEFEAT_ORDER (P:195-196), JOINTS (design name -> R15 part, Motor6D)
--   PodiumPoses.legIK(d, fwd?, rootPitch?) -> (hip, knee, ankle)   P:11-17: a crouch d studs deep, the foot flat
--   PodiumPoses.frameAt(clip, t) -> number        P:217-220: the frame t s after the clip starts (its loop after len)
--   PodiumPoses.samplePose(clip, f) -> Pose        P:226-231
--   PodiumPoses.sampleProp(clip, f) -> (PropKey, PropKey, number)   P:232: the two keys and the eased share between
--   PodiumPoses.jointCFrame(deg) -> CFrame         a design joint's degrees as our Motor6D.Transform rotation
--   PodiumPoses.flip(v) -> Vector3                 a design offset { x, y, z } in our frame

-- Types

export type Vec = { number }

export type Pose = { [string]: Vec } -- "off" and every JOINTS name

export type Key = { f: number, e: string, pose: Pose }

export type PropKey = { f: number, e: string, m: string, o: Vec, r: Vec, sc: Vec }

export type Clip = {
	id: string,
	name: string,
	len: number, -- frames
	hit: number?, -- the HIT frame (camera, effects, sound fire); nil for the "good game" clips
	loop: { number }, -- frames { a, b }: held from b on as a loop of a..b
	keys: { Key },
	props: { PropKey },
	events: { { f: number, k: string } },
}

-- Constants

local FPS = 30
local DEG = 180 / math.pi
local RAD = math.pi / 180
-- A:4, 5: the design's joints and our R15 part and Motor6D for each.
local JOINTS: { [string]: { string } } = {
	root = { "LowerTorso", "Root" },
	waist = { "UpperTorso", "Waist" },
	neck = { "Head", "Neck" },
	lShoulder = { "LeftUpperArm", "LeftShoulder" },
	lElbow = { "LeftLowerArm", "LeftElbow" },
	lWrist = { "LeftHand", "LeftWrist" },
	rShoulder = { "RightUpperArm", "RightShoulder" },
	rElbow = { "RightLowerArm", "RightElbow" },
	rWrist = { "RightHand", "RightWrist" },
	lHip = { "LeftUpperLeg", "LeftHip" },
	lKnee = { "LeftLowerLeg", "LeftKnee" },
	lAnkle = { "LeftFoot", "LeftAnkle" },
	rHip = { "RightUpperLeg", "RightHip" },
	rKnee = { "RightLowerLeg", "RightKnee" },
	rAnkle = { "RightFoot", "RightAnkle" },
}
local ORDER = {
	"root",
	"waist",
	"neck",
	"lShoulder",
	"lElbow",
	"lWrist",
	"rShoulder",
	"rElbow",
	"rWrist",
	"lHip",
	"lKnee",
	"lAnkle",
	"rHip",
	"rKnee",
	"rAnkle",
}

-- Module table

local PodiumPoses = {}

-- Private: the design's helpers (P:8-26) ---------------------------------------------------------------------------

local function clamp(x: number, a: number, b: number): number
	return math.min(b, math.max(a, x))
end

-- P:11-17
local function legIK(d: number, fwd: number?, rootPitch: number?): (number, number, number)
	local L1, L2 = 1.2, 1.15
	local dy, dz = 2.35 - d, fwd or 0
	local D = math.min(L1 + L2 - 1e-3, math.sqrt(dy * dy + dz * dz))
	local phi = math.atan2(dz, dy)
	local alpha = math.acos(clamp((L1 * L1 + D * D - L2 * L2) / (2 * L1 * D), -1, 1))
	local k = math.pi - math.acos(clamp((L1 * L1 + L2 * L2 - D * D) / (2 * L1 * L2), -1, 1))
	local a = phi + alpha
	return -a * DEG - (rootPitch or 0), k * DEG, (a - k) * DEG
end

type LegOptions = { r: number?, w: number?, lf: number?, rf: number?, la: number?, ra: number? }

-- P:18-21
local function legs(d: number?, o: LegOptions?): Pose
	local opts: LegOptions = o or {}
	local r, w = opts.r or 0, opts.w or 4
	local lh, lk, la = legIK(d or 0, opts.lf or 0, r)
	local rh, rk, ra = legIK(d or 0, opts.rf or 0, r)
	return {
		lHip = { lh, 0, w },
		lKnee = { lk, 0, 0 },
		lAnkle = { la + (opts.la or 0), 0, 0 },
		rHip = { rh, 0, -w },
		rKnee = { rk, 0, 0 },
		rAnkle = { ra + (opts.ra or 0), 0, 0 },
	}
end

-- P:22
local HOLD: Pose = {
	lShoulder = { 5, 0, 9 },
	lElbow = { -14, 0, 0 },
	rShoulder = { -32, 0, -6 },
	rElbow = { -76, 0, 0 },
	lWrist = { 0, 0, 0 },
	rWrist = { 0, 0, 0 },
}

local function merge(...: Pose): Pose
	local out: Pose = {}
	for i = 1, select("#", ...) do
		for name, v in select(i, ...) :: Pose do
			out[name] = v
		end
	end
	return out
end

-- P:23: standing, holding the squishy
local function ST(x: Pose?): Pose
	return merge(
		{ off = { 0, 0, 0 }, root = { 0, 0, 0 }, waist = { 0, 0, 0 }, neck = { 0, 0, 0 } },
		HOLD,
		legs(0),
		x or {}
	)
end

-- P:24: both arms overhead
local OVER: Pose = { rShoulder = { -172, 0, -14 }, rElbow = { -22 }, lShoulder = { -172, 0, 14 }, lElbow = { -22 } }

-- P:25: the right leg forward in a crouch d deep
local function RF(d: number, r: number): Pose
	local hip, knee, ankle = legIK(d, 1.3, r)
	return { rHip = { hip, 0, -6 }, rKnee = { knee }, rAnkle = { ankle } }
end

-- P:26: the left knee down
local function KNEEL(r: number): Pose
	return { lHip = { 10 - r, 0, 4 }, lKnee = { 80 }, lAnkle = { 0 } }
end

type RawKey = { f: number, e: string?, pose: Pose }

local function key(f: number, e: string?, ...: Pose): RawKey
	return { f = f, e = e, pose = merge(...) }
end

type RawProp = { f: number, m: string?, o: Vec?, r: Vec?, sc: Vec?, e: string? }

-- Private: the clips (P:28-196) ------------------------------------------------------------------------------------

local RAW: { [string]: any } = {
	-- P:29-52: MVP (rank 1)
	squishSlam = {
		name = "Squish Slam",
		len = 84,
		hit = 25,
		loop = { 48, 84 },
		keys = {
			key(0, nil, ST()),
			key(
				6,
				"out",
				{ off = { 0, -0.65, 0 }, root = { 14, 0, 0 }, waist = { 8, 0, 0 }, neck = { -14, 0, 0 } },
				legs(0.65, { r = 14 }),
				{ lShoulder = { 35, 0, 18 }, lElbow = { -30 }, rShoulder = { 10, 0, -12 }, rElbow = { -50 } }
			),
			key(
				10,
				"in",
				{ off = { 0, 0.3, 0 }, root = { -4, 0, 0 }, waist = { -6, 0, 0 }, neck = { -8, 0, 0 } },
				legs(0, { r = -4, la = 22, ra = 22 }),
				OVER
			),
			key(14, nil, {
				off = { 0, 2.0, 0 },
				root = { 0, 140, 0 },
				waist = { 0, 0, 0 },
				lHip = { -70, 0, 6 },
				lKnee = { 110 },
				lAnkle = { 10 },
				rHip = { -64, 0, -6 },
				rKnee = { 104 },
				rAnkle = { 10 },
			}),
			key(18, nil, { off = { 0, 2.9, 0 }, root = { 0, 280, 0 } }),
			key(22, "in", {
				off = { 0, 1.4, 0 },
				root = { 8, 360, 0 },
				lHip = { 8, 0, 6 },
				lKnee = { 60 },
				rHip = { -70, 0, -6 },
				rKnee = { 70 },
				rShoulder = { -120, 0, -10 },
				rElbow = { -14 },
				lShoulder = { -60, 0, 40 },
				lElbow = { -20 },
			}),
			key(
				25,
				"in",
				{ off = { 0, -1.0, 0 }, root = { 24, 360, 0 }, waist = { 14, 0, 0 }, neck = { -26, 0, 0 } },
				KNEEL(24),
				RF(1.0, 24),
				{ rShoulder = { -38, 0, -10 }, rElbow = { -8 }, lShoulder = { 42, 0, 55 }, lElbow = { -22 } }
			),
			key(
				30,
				nil,
				{ off = { 0, -1.1, 0 }, root = { 28, 360, 0 }, waist = { 16, 0, 0 }, neck = { -30, 0, 0 } },
				KNEEL(28),
				RF(1.1, 28),
				{ rShoulder = { -34, 0, -10 } }
			),
			key(
				36,
				"out",
				{ off = { 0, -1.0, 0 }, root = { 24, 360, 0 }, waist = { 14, 0, 0 }, neck = { -22, 0, 0 } },
				KNEEL(24),
				RF(1.0, 24),
				{ rShoulder = { -38, 0, -10 } }
			),
			key(
				44,
				nil,
				{ off = { 0, -0.5, 0 }, root = { 10, 360, 0 }, waist = { 6, 0, 0 }, neck = { -12, 0, 0 } },
				legs(0.5, { r = 10 }),
				{ rShoulder = { -120, 0, -10 }, rElbow = { -30 }, lShoulder = { -120, 0, 10 }, lElbow = { -30 } }
			),
			key(
				48,
				"out",
				{ off = { 0, 0, 0 }, root = { 0, 360, 0 }, waist = { -4, 0, 0 }, neck = { -8, 0, 0 } },
				legs(0),
				OVER
			),
			key(57, nil, { off = { 0, -0.15, 0 } }, legs(0.15), {
				neck = { -12, 0, 0 },
				rShoulder = { -165, 0, -18 },
				rElbow = { -48 },
				lShoulder = { -165, 0, 18 },
				lElbow = { -48 },
			}),
			key(66, nil, { off = { 0, 0, 0 } }, legs(0), { neck = { -8, 0, 0 } }, OVER),
			key(75, nil, { off = { 0, -0.15, 0 } }, legs(0.15), {
				neck = { -12, 0, 0 },
				rShoulder = { -165, 0, -18 },
				rElbow = { -48 },
				lShoulder = { -165, 0, 18 },
				lElbow = { -48 },
			}),
			key(84, nil, { off = { 0, 0, 0 } }, legs(0), { neck = { -8, 0, 0 } }, OVER),
		},
		props = {
			{ f = 0, m = "hand" },
			{ f = 22, m = "hand" },
			{ f = 25, m = "hand", sc = { 1.55, 0.42, 1.55 }, e = "in" },
			{ f = 31, m = "hand", sc = { 0.85, 1.2, 0.85 } },
			{ f = 38, m = "hand" },
			{ f = 48, m = "hand" },
			{ f = 57, m = "hand", sc = { 1.3, 0.62, 1.3 } },
			{ f = 66, m = "hand" },
			{ f = 75, m = "hand", sc = { 1.3, 0.62, 1.3 } },
			{ f = 84, m = "hand" },
		},
		events = { { f = 10, k = "jump" }, { f = 25, k = "hit" }, { f = 57, k = "squeeze" }, { f = 75, k = "squeeze" } },
	},
	-- P:53-71: rank 2
	squishyHug = {
		name = "Squishy Hug",
		len = 72,
		hit = 12,
		loop = { 36, 72 },
		keys = {
			key(0, nil, ST()),
			key(6, "out", {
				off = { 0, 0.04, 0 },
				waist = { -4, 0, 0 },
				neck = { -6, 0, 0 },
				rShoulder = { -60, 0, 8 },
				rElbow = { -90 },
				lShoulder = { -40, 0, -6 },
				lElbow = { -70 },
			}),
			key(
				12,
				"in",
				{ off = { 0, -0.18, 0 }, root = { 4, 0, 0 }, waist = { 12, 0, 0 }, neck = { 6, 0, 14 } },
				legs(0.18, { r = 4 }),
				{ lShoulder = { -62, 0, -30 }, lElbow = { -98 }, rShoulder = { -62, 0, 30 }, rElbow = { -98 } }
			),
			key(17, nil, { off = { 0, -0.24, 0 }, waist = { 15, 0, 0 }, neck = { 8, 0, 18 } }, legs(0.24, { r = 4 })),
			key(24, "out", { off = { 0, -0.12, 0 }, waist = { 10, 0, 0 }, neck = { 4, 0, 12 } }, legs(0.12, { r = 4 })),
			key(
				36,
				nil,
				{ off = { 0, 0, 0 }, root = { 0, 0, 0 }, waist = { -6, 0, 0 }, neck = { -10, 0, 0 } },
				legs(0),
				{ lShoulder = { -128, 0, -14 }, lElbow = { -26 }, rShoulder = { -128, 0, 14 }, rElbow = { -26 } }
			),
			key(45, nil, { off = { 0.12, 0, 0 }, root = { 0, 0, 6 }, waist = { -6, 0, -4 }, neck = { -10, 0, -6 } }),
			key(54, nil, { off = { 0, 0, 0 }, root = { 0, 0, 0 }, waist = { -6, 0, 0 }, neck = { -10, 0, 0 } }),
			key(63, nil, { off = { -0.12, 0, 0 }, root = { 0, 0, -6 }, waist = { -6, 0, 4 }, neck = { -10, 0, 6 } }),
			key(72, nil, { off = { 0, 0, 0 }, root = { 0, 0, 0 }, waist = { -6, 0, 0 }, neck = { -10, 0, 0 } }),
		},
		props = {
			{ f = 0, m = "hand" },
			{ f = 6, m = "chest", e = "out" },
			{ f = 12, m = "chest", sc = { 1.22, 1.18, 0.6 }, e = "in" },
			{ f = 17, m = "chest", sc = { 1.28, 1.22, 0.52 } },
			{ f = 24, m = "chest", sc = { 1.1, 1.08, 0.8 } },
			{ f = 36, m = "hands" },
			{ f = 45, m = "hands", sc = { 1.04, 0.97, 1.04 } },
			{ f = 54, m = "hands" },
			{ f = 63, m = "hands", sc = { 1.04, 0.97, 1.04 } },
			{ f = 72, m = "hands" },
		},
		events = { { f = 12, k = "hit" }, { f = 12, k = "hearts" } },
	},
	-- P:72-91: rank 3
	doubleFlex = {
		name = "Double Flex",
		len = 66,
		hit = 18,
		loop = { 30, 66 },
		keys = {
			key(0, nil, ST(), { root = { 0, -40, 0 } }),
			key(
				4,
				"out",
				{ off = { 0, -0.5, 0 }, root = { 8, -40, 0 } },
				legs(0.5, { r = 8 }),
				{ lShoulder = { 10, 0, 14 }, lElbow = { -20 }, rShoulder = { 10, 0, -14 }, rElbow = { -20 } }
			),
			key(8, "out", {
				off = { 0, 1.1, 0 },
				root = { 0, -15, 0 },
				lHip = { -20, 0, 6 },
				lKnee = { 40 },
				lAnkle = { 15 },
				rHip = { -20, 0, -6 },
				rKnee = { 40 },
				rAnkle = { 15 },
				lShoulder = { -60, 0, 50 },
				rShoulder = { -60, 0, -50 },
				lElbow = { -40 },
				rElbow = { -40 },
			}),
			key(13, "in", { off = { 0, -0.35, 0 }, root = { 4, 0, 0 } }, legs(0.35, { r = 4 })),
			key(
				18,
				"out",
				{ off = { 0, -0.1, 0 }, root = { 0, 0, 0 }, waist = { -8, 0, 0 }, neck = { -8, 0, 0 } },
				legs(0.1),
				{ lShoulder = { -90, 0, 92 }, lElbow = { -104 }, rShoulder = { -90, 0, -92 }, rElbow = { -104 } }
			),
			key(
				23,
				nil,
				{ off = { 0, -0.16, 0 }, waist = { -11, 0, 0 } },
				legs(0.16),
				{ lShoulder = { -90, 0, 100 }, lElbow = { -116 }, rShoulder = { -90, 0, -100 }, rElbow = { -116 } }
			),
			key(
				30,
				"out",
				{ off = { 0, -0.1, 0 }, waist = { -8, 0, 0 }, neck = { -8, 0, 0 } },
				legs(0.1),
				{ lShoulder = { -90, 0, 92 }, lElbow = { -104 }, rShoulder = { -90, 0, -92 }, rElbow = { -104 } }
			),
			key(
				39,
				nil,
				{ off = { 0, -0.06, 0 } },
				legs(0.06),
				{ waist = { -8, -8, 0 }, neck = { -8, -10, 0 }, lShoulder = { -90, 0, 98 }, lElbow = { -122 } }
			),
			key(
				48,
				nil,
				{ off = { 0, -0.1, 0 } },
				legs(0.1),
				{ waist = { -8, 0, 0 }, neck = { -8, 0, 0 }, lShoulder = { -90, 0, 92 }, lElbow = { -104 } }
			),
			key(
				57,
				nil,
				{ off = { 0, -0.06, 0 } },
				legs(0.06),
				{ waist = { -8, 8, 0 }, neck = { -8, 10, 0 }, rShoulder = { -90, 0, -98 }, rElbow = { -122 } }
			),
			key(
				66,
				nil,
				{ off = { 0, -0.1, 0 } },
				legs(0.1),
				{ waist = { -8, 0, 0 }, neck = { -8, 0, 0 }, rShoulder = { -90, 0, -92 }, rElbow = { -104 } }
			),
		},
		props = {
			{ f = 0, m = "hand" },
			{ f = 8, m = "air", o = { 0, 7.6, 0.2 }, e = "out" },
			{ f = 13, m = "head", sc = { 1.3, 0.7, 1.3 }, e = "in" },
			{ f = 18, m = "head", sc = { 0.9, 1.12, 0.9 } },
			{ f = 23, m = "head", sc = { 1.08, 0.94, 1.08 } },
			{ f = 30, m = "head" },
			{ f = 39, m = "head", o = { 0, 0.35, 0 }, sc = { 0.95, 1.06, 0.95 } },
			{ f = 44, m = "head", sc = { 1.15, 0.86, 1.15 } },
			{ f = 48, m = "head" },
			{ f = 57, m = "head", o = { 0, 0.35, 0 }, sc = { 0.95, 1.06, 0.95 } },
			{ f = 62, m = "head", sc = { 1.15, 0.86, 1.15 } },
			{ f = 66, m = "head" },
		},
		events = { { f = 8, k = "jump" }, { f = 18, k = "hit" } },
	},
	-- P:92-111: rank 4
	starJump = {
		name = "Star Jump",
		len = 62,
		hit = 22,
		loop = { 32, 62 },
		keys = {
			key(0, nil, ST()),
			key(
				5,
				"out",
				{ off = { 0, -0.6, 0 }, root = { 12, 0, 0 }, waist = { 6, 0, 0 }, neck = { -10, 0, 0 } },
				legs(0.6, { r = 12 }),
				{ lShoulder = { 30, 0, 12 }, lElbow = { -20 }, rShoulder = { 30, 0, -12 }, rElbow = { -20 } }
			),
			key(
				9,
				"in",
				{ off = { 0, 0.5, 0 }, root = { -4, 0, 0 }, waist = { -4, 0, 0 }, neck = { -8, 0, 0 } },
				legs(0, { r = -4, la = 22, ra = 22 }),
				{ lShoulder = { -100, 0, 40 }, rShoulder = { -100, 0, -40 }, lElbow = { -10 }, rElbow = { -10 } }
			),
			key(14, "out", {
				off = { 0, 2.6, 0 },
				root = { 0, 0, 0 },
				waist = { 0, 0, 0 },
				neck = { -12, 0, 0 },
				lShoulder = { 0, 0, 138 },
				rShoulder = { 0, 0, -138 },
				lElbow = { -4 },
				rElbow = { -4 },
				lHip = { 0, 0, 32 },
				rHip = { 0, 0, -32 },
				lKnee = { 4 },
				rKnee = { 4 },
				lAnkle = { 16 },
				rAnkle = { 16 },
			}),
			key(19, nil, {
				off = { 0, 1.0, 0 },
				lShoulder = { -30, 0, 60 },
				rShoulder = { -30, 0, -60 },
				lHip = { -10, 0, 6 },
				rHip = { -10, 0, -6 },
				lKnee = { 16 },
				rKnee = { 16 },
				lAnkle = { 6 },
				rAnkle = { 6 },
			}),
			key(
				22,
				"in",
				{ off = { 0, -0.6, 0 }, root = { 14, 0, 0 }, waist = { 10, 0, 0 }, neck = { -22, 0, 0 } },
				legs(0.6, { r = 14 }),
				{ lShoulder = { -40, 0, 26 }, lElbow = { -122 }, rShoulder = { -40, 0, -26 }, rElbow = { -122 } }
			),
			key(26, nil, { off = { 0, -0.7, 0 }, root = { 16, 0, 0 }, waist = { 13, 0, 0 } }, legs(0.7, { r = 16 })),
			key(
				32,
				"out",
				{ off = { 0, -0.2, 0 }, root = { 4, 0, 0 }, waist = { 4, 0, 0 }, neck = { -12, 0, 0 } },
				legs(0.2, { r = 4 }),
				{ lShoulder = { -160, 0, 18 }, lElbow = { -34 }, rShoulder = { -160, 0, -18 }, rElbow = { -34 } }
			),
			key(
				39,
				nil,
				{ off = { 0, -0.3, 0 }, waist = { 8, 0, 0 } },
				legs(0.3, { r = 4 }),
				{ lShoulder = { -70, 0, 26 }, lElbow = { -118 }, rShoulder = { -70, 0, -26 }, rElbow = { -118 } }
			),
			key(
				47,
				nil,
				{ off = { 0, -0.2, 0 }, waist = { 4, 0, 0 } },
				legs(0.2, { r = 4 }),
				{ lShoulder = { -160, 0, 18 }, lElbow = { -34 }, rShoulder = { -160, 0, -18 }, rElbow = { -34 } }
			),
			key(
				54,
				nil,
				{ off = { 0, -0.3, 0 }, waist = { 8, 0, 0 } },
				legs(0.3, { r = 4 }),
				{ lShoulder = { -70, 0, 26 }, lElbow = { -118 }, rShoulder = { -70, 0, -26 }, rElbow = { -118 } }
			),
			key(
				62,
				nil,
				{ off = { 0, -0.2, 0 }, waist = { 4, 0, 0 } },
				legs(0.2, { r = 4 }),
				{ lShoulder = { -160, 0, 18 }, lElbow = { -34 }, rShoulder = { -160, 0, -18 }, rElbow = { -34 } }
			),
		},
		props = {
			{ f = 0, m = "hand" },
			{ f = 22, m = "hand", sc = { 1.25, 0.75, 1.25 }, e = "in" },
			{ f = 26, m = "hand", sc = { 0.9, 1.1, 0.9 } },
			{ f = 32, m = "hand" },
			{ f = 39, m = "hand", sc = { 1.2, 0.8, 1.2 } },
			{ f = 47, m = "hand" },
			{ f = 54, m = "hand", sc = { 1.2, 0.8, 1.2 } },
			{ f = 62, m = "hand" },
		},
		events = { { f = 9, k = "jump" }, { f = 22, k = "hit" } },
	},
	-- P:112-131: rank 5
	crowdHype = {
		name = "Crowd Hype",
		len = 76,
		hit = 30,
		loop = { 40, 76 },
		keys = {
			key(0, nil, ST()),
			key(6, nil, {
				root = { 0, 38, 0 },
				waist = { 0, 10, 0 },
				neck = { -10, 0, 0 },
				lShoulder = { -160, 0, 30 },
				lElbow = { -20 },
				rShoulder = { -160, 0, -30 },
				rElbow = { -20 },
			}),
			key(12, nil, { off = { 0, 0.08, 0 }, lShoulder = { -150, 0, 50 }, rShoulder = { -170, 0, -10 } }),
			key(18, nil, { off = { 0, 0, 0 }, lShoulder = { -170, 0, 10 }, rShoulder = { -150, 0, -50 } }),
			key(24, nil, {
				root = { 0, 0, 0 },
				waist = { 6, 0, 0 },
				neck = { -6, 0, 0 },
				lShoulder = { -70, 0, 20 },
				lElbow = { -30 },
				rShoulder = { -70, 0, -20 },
				rElbow = { -30 },
			}),
			key(
				30,
				"in",
				{ off = { 0, -0.15, 0 }, waist = { 10, 0, 0 }, neck = { -14, 0, 0 } },
				legs(0.15),
				{ lShoulder = { -78, 0, 16 }, lElbow = { -100 }, rShoulder = { -78, 0, -16 }, rElbow = { -100 } }
			),
			key(
				34,
				nil,
				{ off = { 0, -0.2, 0 }, waist = { 13, 0, 0 } },
				legs(0.2),
				{ lElbow = { -110 }, rElbow = { -110 } }
			),
			key(
				40,
				"out",
				{ off = { 0, 0, 0 }, waist = { 0, 0, 0 }, neck = { -8, 0, 0 } },
				legs(0),
				{ lShoulder = { -165, 0, 26 }, lElbow = { -24 }, rShoulder = { -165, 0, -26 }, rElbow = { -24 } }
			),
			key(49, nil, {
				off = { 0.1, 0.06, 0 },
				root = { 0, 0, 6 },
				lShoulder = { -150, 0, 48 },
				rShoulder = { -172, 0, -8 },
			}),
			key(
				58,
				nil,
				{ off = { 0, 0, 0 }, root = { 0, 0, 0 }, lShoulder = { -165, 0, 26 }, rShoulder = { -165, 0, -26 } }
			),
			key(67, nil, {
				off = { -0.1, 0.06, 0 },
				root = { 0, 0, -6 },
				lShoulder = { -172, 0, 8 },
				rShoulder = { -150, 0, -48 },
			}),
			key(
				76,
				nil,
				{ off = { 0, 0, 0 }, root = { 0, 0, 0 }, lShoulder = { -165, 0, 26 }, rShoulder = { -165, 0, -26 } }
			),
		},
		props = {
			{ f = 0, m = "hand" },
			{ f = 30, m = "hand", sc = { 1.2, 0.82, 1.2 }, e = "in" },
			{ f = 34, m = "hand", sc = { 0.92, 1.08, 0.92 } },
			{ f = 40, m = "hand" },
			{ f = 76, m = "hand" },
		},
		events = { { f = 30, k = "hit" } },
	},
	-- P:132-155: rank 6
	plushToss = {
		name = "Plush Toss",
		len = 80,
		hit = 33,
		loop = { 44, 80 },
		keys = {
			key(0, nil, ST()),
			key(
				5,
				"out",
				{ off = { 0, -0.35, 0 }, waist = { 6, 0, 0 } },
				legs(0.35),
				{ rShoulder = { -5, 0, -10 }, rElbow = { -40 } }
			),
			key(
				9,
				"in",
				{ off = { 0, 0.12, 0 }, waist = { -6, 0, 0 }, neck = { -20, 0, 0 } },
				legs(0, { la = 14, ra = 14 }),
				{ rShoulder = { -176, 0, -6 }, rElbow = { -4 }, lShoulder = { -40, 0, 20 }, lElbow = { -20 } }
			),
			key(
				12,
				nil,
				{ off = { 0, 0, 0 }, root = { 0, 40, 0 }, neck = { -14, 0, 0 } },
				legs(0),
				{ rShoulder = { -60, 0, -50 }, rElbow = { -20 }, lShoulder = { -60, 0, 50 } }
			),
			key(18, nil, { root = { 0, 200, 0 } }),
			key(24, nil, { root = { 0, 360, 0 }, neck = { -24, 0, 0 } }),
			key(28, nil, {
				waist = { 8, 0, 0 },
				rShoulder = { 30, 0, -24 },
				rElbow = { -80 },
				lShoulder = { -30, 0, 30 },
				lElbow = { -30 },
			}),
			key(30, nil, { rShoulder = { 40, 0, -20 }, rElbow = { -76 } }),
			key(
				33,
				"in",
				{ off = { 0, -0.08, 0 }, waist = { 4, -10, 0 }, neck = { -6, 10, 0 } },
				legs(0.08),
				{ lShoulder = { -92, 0, 8 }, lElbow = { -4 } }
			),
			key(38, nil, { off = { 0, -0.12, 0 }, waist = { 6, -12, 0 } }, legs(0.12), { lShoulder = { -100, 0, 10 } }),
			key(44, "out", { off = { 0, 0, 0 }, waist = { 2, -8, 0 } }, legs(0), { lShoulder = { -88, 0, 8 } }),
			key(53, nil, { off = { 0, 0.14, 0 } }, legs(0, { la = 16, ra = 16 })),
			key(62, nil, { off = { 0, -0.06, 0 } }, legs(0.06)),
			key(71, nil, { off = { 0, 0.14, 0 } }, legs(0, { la = 16, ra = 16 })),
			key(80, nil, { off = { 0, 0, 0 } }, legs(0)),
		},
		props = {
			{ f = 0, m = "hand" },
			{ f = 9, m = "hand" },
			{ f = 20, m = "air", o = { -0.4, 12, 0.6 }, r = { 360, 0, 0 }, e = "out" },
			{ f = 30, m = "hand", r = { 720, 0, 0 }, e = "in" },
			{ f = 33, m = "hand", r = { 720, 0, 0 }, sc = { 1.15, 0.88, 1.15 } },
			{ f = 38, m = "hand", r = { 720, 0, 0 } },
			{ f = 80, m = "hand", r = { 720, 0, 0 } },
		},
		events = { { f = 9, k = "toss" }, { f = 30, k = "catch" }, { f = 33, k = "hit" } },
	},
	-- P:156-167: defeat (good game)
	shrug = {
		name = "Shrug",
		len = 60,
		loop = { 0, 60 },
		keys = {
			key(0, nil, ST()),
			key(10, "out", {
				off = { 0, 0.06, 0 },
				waist = { -3, 0, 0 },
				neck = { 4, 0, 12 },
				lShoulder = { -28, 0, 30 },
				lElbow = { -86 },
				rShoulder = { -34, 0, -26 },
				rElbow = { -88 },
			}),
			key(22, nil, { neck = { 4, 0, 14 } }),
			key(36, nil, ST()),
			key(60, nil, ST()),
		},
		props = { { f = 0, m = "hand" }, { f = 60, m = "hand" } },
		events = {},
	},
	-- P:168-179: defeat (good game)
	slowClap = {
		name = "Slow Clap",
		len = 48,
		loop = { 0, 48 },
		keys = {
			key(0, nil, ST(), {
				neck = { 6, 0, 0 },
				waist = { 2, 0, 0 },
				lShoulder = { -72, 0, 6 },
				lElbow = { -62 },
				rShoulder = { -72, 0, -6 },
				rElbow = { -62 },
			}),
			key(
				12,
				"in",
				{ lShoulder = { -72, 0, -12 }, rShoulder = { -72, 0, 12 }, lElbow = { -72 }, rElbow = { -72 } }
			),
			key(
				24,
				"out",
				{ lShoulder = { -72, 0, 6 }, rShoulder = { -72, 0, -6 }, lElbow = { -62 }, rElbow = { -62 } }
			),
			key(
				36,
				"in",
				{ lShoulder = { -72, 0, -12 }, rShoulder = { -72, 0, 12 }, lElbow = { -72 }, rElbow = { -72 } }
			),
			key(
				48,
				"out",
				{ lShoulder = { -72, 0, 6 }, rShoulder = { -72, 0, -6 }, lElbow = { -62 }, rElbow = { -62 } }
			),
		},
		props = {
			{ f = 0, m = "head" },
			{ f = 12, m = "head", sc = { 1.08, 0.93, 1.08 } },
			{ f = 24, m = "head" },
			{ f = 36, m = "head", sc = { 1.08, 0.93, 1.08 } },
			{ f = 48, m = "head" },
		},
		events = {},
	},
	-- P:180-193: defeat (good game)
	headPat = {
		name = "Head Pat",
		len = 60,
		loop = { 0, 60 },
		keys = {
			key(
				0,
				nil,
				ST(),
				{ waist = { 4, 0, 0 }, neck = { 10, 0, -8 }, lShoulder = { -150, 0, 40 }, lElbow = { -108 } }
			),
			key(8, nil, { lElbow = { -96 }, neck = { 8, 0, -8 } }),
			key(15, nil, { lElbow = { -114 }, neck = { 12, 0, -8 } }),
			key(22, nil, { lElbow = { -96 }, neck = { 8, 0, -8 } }),
			key(30, nil, { lElbow = { -114 }, neck = { 12, 0, -8 } }),
			key(45, nil, { lShoulder = { -150, 6, 44 }, lElbow = { -104 }, neck = { 9, 0, -10 } }),
			key(60, nil, { lShoulder = { -150, 0, 40 }, lElbow = { -108 }, neck = { 10, 0, -8 } }),
		},
		props = { { f = 0, m = "hand" }, { f = 60, m = "hand" } },
		events = {},
	},
}

-- P:199-211: every key filled from the one before; the props' anchors, offsets and turns carried as the design does.
local function z3(): Vec
	return { 0, 0, 0 }
end

local function expand(id: string, raw: any): Clip
	local prev: Pose = { off = z3() }
	for _, j in ORDER do
		prev[j] = z3()
	end
	local keys: { Key } = {}
	for _, k in raw.keys :: { RawKey } do
		local p: Pose = { off = table.clone(k.pose.off or prev.off) }
		for _, j in ORDER do
			local v = k.pose[j] or prev[j]
			p[j] = { v[1] or 0, v[2] or 0, v[3] or 0 }
		end
		table.insert(keys, { f = k.f, e = k.e or "io", pose = p })
		prev = p
	end
	local props: { PropKey } = {}
	local pp: PropKey = { f = 0, e = "io", m = "hand", o = z3(), r = z3(), sc = { 1, 1, 1 } }
	for _, k in raw.props :: { RawProp } do
		local m = k.m or pp.m
		pp = {
			f = k.f,
			e = k.e or "io",
			m = m,
			o = k.o or (if m == "air" and pp.m == "air" then pp.o else z3()),
			r = k.r or (if m == pp.m then pp.r else z3()),
			sc = k.sc or { 1, 1, 1 },
		}
		table.insert(props, pp)
	end
	return {
		id = id,
		name = raw.name,
		len = raw.len,
		hit = raw.hit,
		loop = raw.loop,
		keys = keys,
		props = props,
		events = raw.events,
	}
end

local CLIPS: { [string]: Clip } = {}
for id, raw in RAW do
	CLIPS[id] = expand(id, raw)
end

-- P:212-215
local EASE: { [string]: (number) -> number } = {
	io = function(t: number): number
		return t * t * (3 - 2 * t)
	end,
	lin = function(t: number): number
		return t
	end,
	["in"] = function(t: number): number
		return t * t * t
	end,
	out = function(t: number): number
		return 1 - (1 - t) ^ 3
	end,
	back = function(t: number): number
		local c = 1.70158
		t -= 1
		return 1 + (c + 1) * t * t * t + c * t * t
	end,
}

-- P:221-225: the keys around frame f and the eased share between them.
local function seg(list: { any }, f: number): (any, any, number)
	if f <= list[1].f then
		return list[1], list[1], 0
	end
	for i = 1, #list - 1 do
		local A, B = list[i], list[i + 1]
		if f <= B.f then
			return A, B, EASE[B.e]((f - A.f) / math.max(1e-6, B.f - A.f))
		end
	end
	local L = list[#list]
	return L, L, 0
end

-- Public ----------------------------------------------------------------------------------------------------------

PodiumPoses.FPS = FPS
PodiumPoses.JOINTS = JOINTS
PodiumPoses.ORDER = ORDER
PodiumPoses.CLIPS = CLIPS
PodiumPoses.VICTORY_ORDER = { "squishSlam", "squishyHug", "doubleFlex", "starJump", "crowdHype", "plushToss" }
PodiumPoses.DEFEAT_ORDER = { "shrug", "slowClap", "headPat", "slowClap", "shrug", "headPat" }
PodiumPoses.legIK = legIK

function PodiumPoses.frameAt(clip: Clip, t: number): number
	local f = math.max(0, t * FPS)
	local a, b = clip.loop[1], clip.loop[2]
	return if f < b then f else a + ((f - a) % math.max(1, b - a))
end

function PodiumPoses.samplePose(clip: Clip, f: number): Pose
	local A, B, t = seg(clip.keys, f)
	local out: Pose = {}
	local a, b = A.pose, B.pose
	for name, va in a do
		local vb = b[name]
		out[name] = { va[1] + (vb[1] - va[1]) * t, va[2] + (vb[2] - va[2]) * t, va[3] + (vb[3] - va[3]) * t }
	end
	return out
end

function PodiumPoses.sampleProp(clip: Clip, f: number): (PropKey, PropKey, number)
	return seg(clip.props, f)
end

function PodiumPoses.jointCFrame(deg: Vec): CFrame
	return CFrame.fromEulerAnglesXYZ(-deg[1] * RAD, deg[2] * RAD, -deg[3] * RAD)
end

function PodiumPoses.flip(v: Vec): Vector3
	return Vector3.new(-v[1], v[2], -v[3])
end

return PodiumPoses
