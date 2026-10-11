--!strict
-- Birdie (Epic; 3D Lab redesign, spec 2026-10-09 §4): 24 parts + Root, 4 hidden squish-face parts (no mouth: chevrons
-- only), 3 sections: WingL, WingR (Z, mirrored) and the 3-feather Tail (X). Round body on a flatter, flared base,
-- cream belly, 2-part beak, slim wings with tips, a curl of 2 tufts, feet with toe bars. Face kit v2.
-- Authored in design studs (the 3D Lab's metres / 0.28, turned to face -Z); `scale` fits the hand. Hinged parts are
-- placed in their hinge frame (the design's pivot groups) and stored as plain pos/rot. Hinges sit well inside the
-- body: a tilted part's root drifts a little under a deep squeeze (the deformer scales it along its own axes).

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

local BODY = "7CC4F3"
local BLUE = "58A9E4" -- wings, tail and tufts: darker than the body so they read without outlines
local ORANGE = "FFA64D"
local EYE_X, EYE_Y, EYE_R = -0.257, 0.268, 0.1
-- Left wing hinge (the right one is its mirror) and the tail hinge, inside the body.
local WING_AT, WING_TURN = v(-0.60, 0.214, 0.036), v(-8.6, 0, -18.3)
local TAIL_AT = v(0, -0.21, 0.50)
local FEATHER_TILT, FEATHER_FAN = 54.4, 25.8 -- the fan leans back and up; outer feathers turn out

local function frame(at: Vector3, turn: Vector3): CFrame
	return CFrame.new(at) * CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z))
end

-- A part's pos and rot (degrees, CFrame.Angles order) from its frame.
local function placed(cf: CFrame): (Vector3, Vector3)
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	return cf.Position, Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end

local wingPos, wingRot = placed(frame(WING_AT, WING_TURN) * CFrame.new(0, -0.232, 0))
local tipPos, tipRot = placed(frame(WING_AT, WING_TURN) * CFrame.new(0, -0.429, 0.107))

-- One tail feather fanned out by `fan` degrees (positive: toward the toy's left).
local function feather(name: string, fan: number): Kit.PartSpec
	local pos, rot = placed(frame(TAIL_AT, v(FEATHER_TILT, 0, fan)) * CFrame.new(0, 0.25, 0))
	return {
		name = name,
		shape = "E",
		size = v(0.20, 0.54, 0.086),
		pos = pos,
		rot = rot,
		color = BLUE,
		section = "Tail",
		contact = v(0, -0.85, 0), -- the quill end, just past the hinge
	}
end

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.91,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = v(1.36, 1.38, 1.29),
				pos = v(0, 0.05, 0),
				color = BODY,
				body = true,
			},
			{
				name = "Base",
				shape = "E",
				size = v(1.14, 0.48, 1.08),
				pos = v(0, -0.43, 0),
				color = BODY,
				body = true,
			},
			feather("Tail", 0),
		},
		pair(feather("TailL", FEATHER_FAN)),
		pair({
			name = "WingL",
			shape = "E",
			size = v(0.214, 0.643, 0.464),
			pos = wingPos,
			rot = wingRot,
			color = BLUE,
			rigidity = 0.3,
			section = "WingL",
			contact = v(0.4, 0.72, 0), -- by the hinge, on the body side
		}),
		pair({
			name = "WingTipL",
			shape = "E",
			size = v(0.157, 0.286, 0.25),
			pos = tipPos,
			rot = tipRot,
			color = BLUE,
			rigidity = 0.3,
			section = "WingL",
			contact = v(0, 0, 0),
			contactWith = "WingL",
		}),
		{
			{
				name = "Tuft1",
				shape = "E",
				size = v(0.09, 0.28, 0.11),
				pos = v(0, 0.80, -0.03),
				rot = v(0, 0, -12),
				color = BLUE,
				contact = v(0, -0.85, 0),
			},
			{
				name = "Tuft2",
				shape = "E",
				size = v(0.08, 0.20, 0.09),
				pos = v(0.06, 0.77, 0.09),
				rot = v(-25, 0, 18),
				color = BLUE,
				contact = v(0, -0.85, 0),
			},
		},
		pair({
			name = "FootL",
			shape = "E",
			size = v(0.25, 0.10, 0.32),
			pos = v(-0.232, -0.63, -0.393),
			color = ORANGE,
			contact = v(0, 0.8, 0.6), -- the back top, tucked under the base
		}),
		pair({
			name = "ToeL",
			shape = "E",
			size = v(0.30, 0.08, 0.08),
			attach = { to = "FootL", offset = v(0, 0, -0.14) },
			color = ORANGE,
		}),
		{
			{ name = "Belly", shape = "E", size = v(0.80, 0.64, 0.32), face = F(0, -0.33, 0.78), color = "FFF4DA" },
			{
				name = "BeakTop",
				shape = "E",
				size = v(0.22, 0.12, 0.30),
				face = F(0, 0.14, 0.55),
				rot = v(-12, 0, 0),
				color = ORANGE,
			},
			{ name = "BeakBottom", shape = "E", size = v(0.15, 0.08, 0.18), face = F(0, 0.075, 0.6), color = "E8873A" },
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.429, 0.036, 0.094),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = WING_AT, axis = "Z", amp = 1.6, sign = -1, flap = { deg = 25 } }),
		{ Tail = { pivot = TAIL_AT, axis = "X", amp = 1.0, sign = -1 } }
	),
	-- §4 row (spec 2026-10-09; kRel 54, not the design's 56, keeps every recovery under 1 Hz).
	motion = {
		squeeze = { depth = 0.60, widen = 0.70, kRel = 54, cRel = 8, pitch = 1.45 },
		feel = "plush",
		flight = { style = "glide" },
	},
}

return blueprint
