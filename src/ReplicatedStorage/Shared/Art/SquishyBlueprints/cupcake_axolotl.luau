--!strict
-- Cupcake Axolotl (Epic, new; spec 2026-10-09 §4): the 3D Lab CupcakeAxolotl (sd/toys.js) in E parts. A 2-E mint liner
-- with a rim and 3 pleats, the pink frosting head (body), 6 one-E gills that ripple (sections GillLow/Mid/Top L + R; each
-- inner end sits inside the frosting, which fixes the design's floating top gill), hands on the rim and 2 sprinkles on
-- top. 25 visible + 6 hidden squish-face parts + Root.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design units (toys.js metres, face +Z, liner base at y = 0) to studs at scale 1: K studs per unit, turned 180° about Y
-- (x -> -x, z -> -z) and re-based so the pivot sits at the middle of liner + frosting (design y = Y0).
local K, Y0 = 3.0, 0.15
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local MINT, PINK, GILL = "8FDCC4", "F9AFCB", "E7609F"
-- Face (design face(): y 0.245, dx 0.084, eyeR 0.02 × 1.22, smile mw 0.03 × 1.11 at 0.045 below, blush 0.135 / 0.03).
local EYE_X, EYE_Y, EYE_R = -0.084 * K, (0.245 - Y0) * K, 0.0244 * K
local MOUTH_Y, MOUTH_W = (0.2 - Y0) * K, 0.0666 * K
-- Gill ripple: each pair is offset in flap phase (radians) so the ripple runs up the gills in flight.
local GILL_FLAP = 20

type PartSpec = Kit.PartSpec

-- A left gill (pair() makes the right one): one E along its local X, `length` long in design units, turned so its inner
-- end (local +X, the contact) sits inside the frosting; its section has the gill's name.
local function gill(name: string, length: number, centre: Vector3, rot: Vector3): PartSpec
	return {
		name = name,
		shape = "E",
		size = size(length, 0.036, 0.03),
		pos = centre,
		rot = rot,
		color = GILL,
		section = name,
		contact = v(0.8, 0, 0),
	}
end

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			-- Liner: a tall E for the taper (its top half hides in the frosting) and a small rounded foot.
			{
				name = "LinerLow",
				shape = "E",
				size = size(0.27, 0.1, 0.27),
				pos = at(0, 0.04, 0),
				color = MINT,
				body = true,
			},
			{
				name = "LinerTop",
				shape = "E",
				size = size(0.37, 0.3, 0.37),
				pos = at(0, 0.15, 0),
				color = MINT,
				body = true,
			},
			-- The rim holds the hands; it sits a little low so it also covers the frosting's edge.
			{
				name = "Rim",
				shape = "E",
				size = size(0.392, 0.04, 0.392),
				pos = at(0, 0.155, 0),
				color = "C4F0E1",
				body = true,
			},
			-- The frosting is as deep as it is wide (design 0.36 + its ripple), so the liner top stays well inside it.
			{
				name = "Frosting",
				shape = "E",
				size = size(0.38, 0.25, 0.38),
				pos = at(0, 0.185, 0),
				color = PINK,
				body = true,
			},
		},
		-- Gills: inner ends 0.02-0.06 inside the frosting (the top one starts lower and further in than the design's).
		pair(gill("GillLowL", 0.151, at(0.1925, 0.2015, -0.02), v(0, 9.1, 5.9))),
		pair(gill("GillMidL", 0.158, at(0.1925, 0.2625, -0.02), v(0, 9.1, -19.6))),
		pair(gill("GillTopL", 0.212, at(0.1775, 0.3225, -0.02), v(0, 7.3, -33.9))),
		pair({
			name = "HandL",
			shape = "E",
			size = size(0.06, 0.04, 0.044),
			pos = at(0.07, 0.158, 0.185),
			color = "F7A0C0",
			contact = v(0, 0, 0.8),
			contactWith = "Rim",
		}),
		{
			-- Two sprinkles lying on the frosting top.
			{
				name = "SprinkleA",
				shape = "E",
				size = size(0.04, 0.014, 0.014),
				pos = at(0.04, 0.302, -0.03),
				rot = v(0, 30, 0),
				color = "FFD54A",
				look = "detail",
				contact = v(0, -1, 0),
			},
			{
				name = "SprinkleB",
				shape = "E",
				size = size(0.04, 0.014, 0.014),
				pos = at(-0.05, 0.302, 0.01),
				rot = v(0, -50, 0),
				color = "6EC6F5",
				look = "detail",
				contact = v(0, -1, 0),
			},
			-- Pleats: darker folds on the liner front, leaning with its taper.
			{
				name = "PleatMid",
				shape = "E",
				size = size(0.012, 0.09, 0.012),
				face = F(0, (0.085 - Y0) * K, 0.7),
				rot = v(-27, 0, 0),
				color = "6FC4AA",
				look = "detail",
			},
		},
		pair({
			name = "PleatL",
			shape = "E",
			size = size(0.012, 0.09, 0.012),
			face = F(-0.075 * K, (0.085 - Y0) * K, 0.7),
			rot = v(-27, 0, 0),
			color = "6FC4AA",
			look = "detail",
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.135 * K, (0.215 - Y0) * K, 0.0264 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("GillLowL", {
			pivot = at(0.17, 0.2038, -0.0164),
			axis = "Z",
			amp = 1.4,
			sign = -1,
			flap = { deg = GILL_FLAP, phase = 0 },
		}),
		Kit.pairSection("GillMidL", {
			pivot = at(0.145, 0.2454, -0.0124),
			axis = "Z",
			amp = 1.4,
			sign = -1,
			flap = { deg = GILL_FLAP, phase = 1.05 },
		}),
		Kit.pairSection("GillTopL", {
			pivot = at(0.1066, 0.2745, -0.0108),
			axis = "Z",
			amp = 1.4,
			sign = -1,
			flap = { deg = GILL_FLAP, phase = 2.1 },
		})
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.64, widen = 0.62, kRel = 44, cRel = 7.5, pitch = 1.25 },
		feel = "jelly",
		flight = { style = "sway" },
	},
}

return blueprint
