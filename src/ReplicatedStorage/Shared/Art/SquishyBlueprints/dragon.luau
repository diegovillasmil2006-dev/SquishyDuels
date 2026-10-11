--!strict
-- Dragon (Exclusive; 3D Lab redesign, spec 2026-10-09 §4): 30 parts + Root, 6 hidden squish-face parts, 5 sections:
-- WingL, WingR (Y, mirrored), FinL, FinR (X) and the Tail (Y). A gourd body (2 E), a small light muzzle with nostrils,
-- a cream belly, arms and feet; lilac accents: W wings, ear-fins, 2 back spikes and the tail spade; the tail curls to
-- its left. One fang (look "mouth", so the squish face hides 7 parts and shows 6). Cuts to stay under the cap: no belly
-- plates, 2 spikes, round single-part horns (the design's horns are round cones), which leaves 3 parts for the tail.
-- Presentation code reads the name prefixes Horn…, Wing… and Nostril… (horns stay rigid, no section).
-- Authored in design studs (the 3D Lab's metres / 0.28, turned to face -Z, the origin 0.28 m above the base, at the
-- waist); `scale` fits the hand. The two body ellipsoids overlap deeply so the waist stays a gentle gourd (the design's
-- waist is about 0.8 of the widest point). Hinged parts are placed in their hinge frame and stored as plain pos/rot.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

local TEAL = "4FBE9B" -- arms, feet, tail: darker than the body
local LILAC = "B892F0"
local EYE_X, EYE_Y, EYE_R = -0.279, 0.614, 0.113
local MOUTH_Y, MOUTH_W = 0.264, 0.19
-- Hinges of the left fin and wing (the right ones are their mirrors) and of the tail, inside the body.
local FIN_AT = v(-0.58, 0.536, 0.036)
local WING_AT, WING_TURN = v(-0.27, -0.06, 0.42), v(0, 30, -14.3)
local TAIL_AT = v(0, -0.714, 0.429)
-- The tail's curve (the design's tube points), curling back and round to the toy's left. The tip rises less than the
-- design's: a steep segment's far end slides off its line under a deep squeeze and would lose the spade.
local TAIL_MID, TAIL_END = v(-0.464, -0.893, 1.071), v(-0.893, -0.75, 0.607)
local TAIL_TIP_DIR = v(-0.33, 0.2, -0.92) -- the curve's direction at its end

local function frame(at: Vector3, turn: Vector3): CFrame
	return CFrame.new(at) * CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
end

-- A part's pos and rot (degrees, CFrame.Angles order) from its frame.
local function placed(cf: CFrame): (Vector3, Vector3)
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	return cf.Position, Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end

-- A tail segment from `a` to `b`: centred between them, its Z axis along the curve (+Z toward `a`, the root end).
local function segment(a: Vector3, b: Vector3): (Vector3, Vector3)
	return placed(CFrame.lookAt((a + b) / 2, b))
end

-- The ear-fin sticks out of the head side and sweeps back (the design's fin turned to the surface normal).
local finPos, finRot =
	placed(frame(FIN_AT, v(0, 0, 90)) * CFrame.Angles(math.rad(28.6), 0, 0) * CFrame.new(0, 0.107, 0))
-- The wing's W: thin along X, its tall edge (local +Z) is the outer edge and its slope the leading edge, swept back
-- and tilted up from the hinge, which sits inside the wedge near its root corner.
local wingPos, wingRot =
	placed(frame(WING_AT, WING_TURN) * CFrame.new(-0.153, 0.22, 0) * CFrame.Angles(0, math.rad(-90), 0))
local tail1Pos, tail1Rot = segment(TAIL_AT, TAIL_MID)
local tail2Pos, tail2Rot = segment(TAIL_MID, TAIL_END)
-- The spade is centred on the curve's end, so its back half wraps the thin tail tip and stays on it in a squeeze.
local spadePos, spadeRot = placed(CFrame.lookAt(TAIL_END, TAIL_END + TAIL_TIP_DIR))

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.82,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = v(1.44, 1.234, 1.296),
				pos = v(0, -0.383, 0),
				color = "5ECBA8",
				body = true,
			},
			{
				name = "Head",
				shape = "E",
				size = v(1.30, 1.326, 1.17),
				pos = v(0, 0.337, 0),
				color = "5ECBA8",
				body = true,
			},
		},
		pair({
			name = "FootL",
			shape = "E",
			size = v(0.393, 0.214, 0.429),
			pos = v(-0.304, -0.90, -0.464),
			color = TEAL,
			contact = v(0, 0.7, 0.7), -- the back top, under the body
		}),
		pair({
			name = "HornL",
			shape = "E",
			size = v(0.18, 0.30, 0.18),
			pos = v(-0.34, 1.0, 0.085),
			rot = v(20, 0, 25), -- leans back and out
			color = "FFE2A0",
			rigidity = 0.6,
			contact = v(0, -0.9, 0),
		}),
		pair({
			name = "FinL",
			shape = "E",
			size = v(0.243, 0.357, 0.071),
			pos = finPos,
			rot = finRot,
			color = LILAC,
			section = "FinL",
			contact = v(0, -0.6, 0), -- the hinge
		}),
		pair({
			name = "WingL",
			shape = "W",
			size = v(0.07, 0.55, 0.68),
			pos = wingPos,
			rot = wingRot,
			color = "C6A3F4",
			section = "WingL",
			contact = v(0, -0.8, -0.45), -- the hinge
		}),
		{
			{
				name = "Tail1",
				shape = "E",
				size = v(0.38, 0.38, 0.95),
				pos = tail1Pos,
				rot = tail1Rot,
				color = TEAL,
				section = "Tail",
				contact = v(0, 0, 0.85), -- the root end, at the hinge
			},
			{
				name = "Tail2",
				shape = "E",
				size = v(0.27, 0.27, 0.80),
				pos = tail2Pos,
				rot = tail2Rot,
				color = TEAL,
				section = "Tail",
				contact = v(0, 0, 0.8),
				contactWith = "Tail1",
			},
			{
				name = "TailSpade",
				shape = "E",
				size = v(0.09, 0.30, 0.44),
				pos = spadePos,
				rot = spadeRot,
				color = LILAC,
				section = "Tail",
				contact = v(0, 0, 0.6),
				contactWith = "Tail2",
			},
			-- The muzzle is a face-ray target for the nostrils, the mouth and the fang listed after it.
			{
				name = "Muzzle",
				shape = "E",
				size = v(0.75, 0.47, 0.50),
				face = F(0, 0.268, 0.75),
				color = "A9EBD4",
				body = true,
			},
			{ name = "Belly", shape = "E", size = v(0.89, 0.79, 0.36), face = F(0, -0.571, 0.76), color = "FFF0C8" },
			{
				name = "Spike1",
				shape = "W",
				size = v(0.09, 0.26, 0.22),
				face = F(0, 0.65, 0.55, "back"),
				rot = v(40, 0, 0), -- the tip points back; the tall edge is buried in the back
				color = LILAC,
			},
			{
				name = "Spike2",
				shape = "W",
				size = v(0.09, 0.26, 0.22),
				face = F(0, 0.22, 0.55, "back"),
				rot = v(40, 0, 0),
				color = LILAC,
			},
		},
		pair({
			name = "NostrilL",
			shape = "E",
			size = v(0.07, 0.05, 0.035),
			face = F(-0.107, 0.35, 0.6),
			color = "2F7D68",
			look = "detail",
		}),
		pair({ name = "ArmL", shape = "E", size = v(0.286, 0.214, 0.25), face = F(-0.482, -0.393, 0.73), color = TEAL }),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		{
			{
				name = "Fang",
				shape = "E",
				size = v(0.05, 0.07, 0.03),
				face = F(-0.052, 0.21, 0.6),
				color = "FFFAF0",
				look = "mouth",
			},
		},
		Kit.blush2(-0.482, 0.40, 0.094),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("FinL", { pivot = FIN_AT, axis = "X", amp = 0.8, sign = -1 }),
		Kit.pairSection("WingL", { pivot = WING_AT, axis = "Y", amp = 1.4, flap = { deg = 20 } }),
		{ Tail = { pivot = TAIL_AT, axis = "Y", amp = 0.8, flap = { deg = 15 } } }
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.64, widen = 0.66, kRel = 40, cRel = 7.5, pitch = 0.7 },
		feel = "plush",
		flight = { style = "face" },
	},
}

return blueprint
