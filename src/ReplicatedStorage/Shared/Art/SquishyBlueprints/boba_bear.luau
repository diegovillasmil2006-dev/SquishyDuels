--!strict
-- Boba Bear (Common, new; spec 2026-10-09 §4): the 3D Lab BobaBear (sd/toys.js) in E/B parts. A 2-E tapered milk-tea cup
-- with a cream rim, the bear head as the lid (body), round ears with inner (sections EarL/EarR), a muzzle flagged body
-- carrying the nose and the ω mouth, 5 pearls and a pink straw attached to the head. 24 visible + 6 hidden squish-face
-- parts + Root.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design units (toys.js metres, face +Z, cup base at y = 0) to studs at scale 1: K studs per unit, turned 180° about Y
-- (x -> -x, z -> -z) and re-based so the pivot sits at the middle of cup + head (design y = Y0).
local K, Y0 = 2.64, 0.23
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local TEA, BROWN, PEARL = "DDB68D", "B07A52", "3A2420"
-- Face (design face(): y 0.405, dx 0.065, eyeR 0.02 × 1.22, blush 0.11 / 0.04). The ω mouth sits just under the nose and
-- is wider than the design's (mw 0.016 would be 0.05 studs) so it reads at duel distance.
local EYE_X, EYE_Y, EYE_R = -0.065 * K, (0.405 - Y0) * K, 0.0244 * K
local MOUTH_Y, MOUTH_W = (0.335 - Y0) * K, 0.05 * K
-- Ears: on the head top at x ±0.115, tilted out with the surface normal (28°), the pivot 0.012 under the surface.
local EAR_PIVOT = at(0.109, 0.428, -0.005)

type PartSpec = Kit.PartSpec

-- One pearl, face-placed on the cup at design (x, y); x is the bear's left (design +x).
local function pearl(name: string, x: number, y: number): PartSpec
	return {
		name = name,
		shape = "E",
		size = size(0.052, 0.052, 0.052),
		face = F(-x * K, (y - Y0) * K, 0.55),
		color = PEARL,
		look = "detail",
	}
end

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			-- The two cup halves overlap deeply so the taper shows only a slight waist; the rim hides the lid joint.
			{
				name = "CupLow",
				shape = "E",
				size = size(0.29, 0.27, 0.29),
				pos = at(0, 0.13, 0),
				color = TEA,
				body = true,
			},
			{
				name = "CupTop",
				shape = "E",
				size = size(0.356, 0.26, 0.356),
				pos = at(0, 0.27, 0),
				color = TEA,
				body = true,
			},
			-- A body part so Inspect's knead dents it with the cup (user bug 2026-10-24: as a rider it stayed a stiff band
			-- that slid off the dented cup).
			{
				name = "Rim",
				shape = "E",
				size = size(0.388, 0.048, 0.388),
				pos = at(0, 0.305, 0),
				color = "FFF0DA",
				body = true,
			},
			{
				name = "Head",
				shape = "E",
				size = size(0.372, 0.25, 0.372),
				pos = at(0, 0.34, 0),
				color = BROWN,
				body = true,
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.1, 0.096, 0.06),
			pos = at(0.124, 0.452, -0.005),
			rot = v(0, 0, 28),
			color = BROWN,
			section = "EarL",
			contact = v(0, -0.7, 0),
		}),
		{
			-- The muzzle is a ray target for the nose and the mouth.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.124, 0.084, 0.06),
				face = F(0, (0.345 - Y0) * K, 0.7),
				color = "F6E2C6",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.045, 0.03, 0.025),
				face = F(0, (0.36 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.11 * K, (0.365 - Y0) * K, 0.022 * K),
		-- Pearls: 3 low, 2 high, on the front of the cup.
		{ pearl("PearlMid", 0, 0.045) },
		pair(pearl("PearlLowL", 0.09, 0.045)),
		pair(pearl("PearlHighL", 0.045, 0.09)),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W }),
		{
			-- The straw leans to the bear's left and back; its bottom end stays inside the head.
			{
				name = "Straw",
				shape = "B",
				size = size(0.038, 0.253, 0.038),
				attach = { to = "Head", offset = size(-0.0772, 0.16, 0.06) },
				rot = v(14, 0, 12.4),
				color = "FF8FB0",
				rigidity = 0.8,
				contact = v(0, -1, 0),
			},
		},
		pair({
			name = "InnerEarL",
			shape = "E",
			size = size(0.06, 0.06, 0.04),
			attach = { to = "EarL", offset = size(0, 0, -0.014) },
			color = "E8C29A",
			section = "EarL",
		})
	),
	sections = Kit.pairSection("EarL", { pivot = EAR_PIVOT, axis = "X", amp = 0.7, sign = -1 }),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.70, widen = 0.50, kRel = 44, cRel = 9, pitch = 0.95 },
		feel = "foam",
		flight = { style = "upright" },
	},
}

return blueprint
