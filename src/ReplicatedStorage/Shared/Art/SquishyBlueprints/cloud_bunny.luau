--!strict
-- Cloud Bunny (Epic, new; spec 2026-10-09 §4): the 3D Lab CloudBunny (sd/toys.js) in E/B parts. A cloud core with a
-- lavender underside (both body) and 5 puffs (not body, so the hit sphere follows the core), asymmetric ears (left up,
-- right floppy; hand-written, not pair(); sections EarL/EarR), buck teeth and a 3-disc rainbow on the back, tilted so the
-- body hides the lower halves. 24 visible + 6 hidden squish-face parts + Root.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design units (toys.js metres, face +Z) to studs at scale 1: K studs per unit, turned 180° about Y (x -> -x, z -> -z)
-- and re-based so the pivot sits at the body's middle (design y = Y0).
local K, Y0 = 2.8, 0.02
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local CLOUD, EAR, EAR_INNER = "F8F5FF", "F3EEFF", "FFC2D6"
-- Face (design face(): y 0.02, dx 0.075, eyeR 0.025 × 1.22, blush 0.13 / 0.025). The smile and the teeth are wider than
-- the design's (mw 0.014 would be 0.04 studs) so they read at duel distance.
local EYE_X, EYE_Y, EYE_R = -0.075 * K, (0.02 - Y0) * K, 0.0305 * K
local MOUTH_Y, MOUTH_W = (-0.02 - Y0) * K, 0.05 * K
-- Rainbow: centred on the back at y -0.03, leaning 35° out at the top so its lower half sinks into the body.
local RAINBOW_ROT = v(35, 180, 0)

type PartSpec = Kit.PartSpec

-- A puff: centred inside the core (its contact is its centre), bulging out of it.
local function puff(name: string, pos: Vector3, puffSize: Vector3): PartSpec
	return { name = name, shape = "E", size = puffSize, pos = pos, color = CLOUD, contact = Vector3.zero }
end

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Core",
				shape = "E",
				size = size(0.51, 0.33, 0.41),
				pos = at(0, 0.02, 0),
				color = CLOUD,
				body = true,
			},
			{
				name = "Underside",
				shape = "E",
				size = size(0.5, 0.15, 0.41),
				pos = at(0, -0.08, 0),
				color = "D5C8F6",
				body = true,
			},
			puff("PuffTop", at(0, 0.165, -0.05), size(0.2, 0.14, 0.18)),
		},
		pair(puff("PuffUpperL", at(0.17, 0.12, 0), size(0.18, 0.15, 0.17))),
		pair(puff("PuffSideL", at(0.24, 0, -0.02), size(0.15, 0.17, 0.2))),
		{
			-- The left ear stands up, leaning back and a little out.
			{
				name = "EarL",
				shape = "E",
				size = size(0.08, 0.33, 0.05),
				pos = at(0.09, 0.29, -0.045),
				rot = v(15.2, 0, 7.5),
				color = EAR,
				section = "EarL",
				contact = v(0, -0.85, 0),
			},
			-- The right ear flops out to the side at 46°.
			{
				name = "EarR",
				shape = "E",
				size = size(0.075, 0.24, 0.05),
				pos = at(-0.145, 0.225, -0.012),
				rot = v(-4.1, 0, -46),
				color = EAR,
				section = "EarR",
				contact = v(0, -0.85, 0),
			},
			{
				name = "RainbowPink",
				shape = "E",
				size = size(0.175, 0.175, 0.012),
				pos = at(0, -0.03, -0.19),
				rot = RAINBOW_ROT,
				color = "FF9BB8",
				look = "detail",
				contact = v(0, -0.5, 0),
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		pair({
			name = "ToothL",
			shape = "B",
			size = size(0.016, 0.02, 0.008),
			face = F(-0.009 * K, MOUTH_Y - 0.016 * K, 0.6),
			color = "FFFFFF",
			look = "mouth",
		}),
		Kit.blush2(-0.13 * K, (-0.005 - Y0) * K, 0.0264 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W }),
		{
			-- Inner ears, in front of each ear.
			{
				name = "InnerEarL",
				shape = "E",
				size = size(0.044, 0.26, 0.02),
				attach = { to = "EarL", offset = size(0, 0.01, -0.02) },
				color = EAR_INNER,
				section = "EarL",
			},
			{
				name = "InnerEarR",
				shape = "E",
				size = size(0.04, 0.17, 0.02),
				attach = { to = "EarR", offset = size(0, 0.01, -0.02) },
				color = EAR_INNER,
				section = "EarR",
			},
			-- The rainbow's yellow and mint discs stack outward on the pink one.
			{
				name = "RainbowYellow",
				shape = "E",
				size = size(0.14, 0.14, 0.012),
				attach = { to = "RainbowPink", offset = size(0, 0, -0.008) },
				color = "FFE27A",
				look = "detail",
			},
			{
				name = "RainbowMint",
				shape = "E",
				size = size(0.105, 0.105, 0.012),
				attach = { to = "RainbowYellow", offset = size(0, 0, -0.008) },
				color = "8EE0C4",
				look = "detail",
			},
		}
	),
	-- Hand-written ear sections (the ears differ, so no pairSection); X hinges at each ear root.
	sections = {
		EarL = { pivot = at(0.075, 0.15, -0.006), axis = "X", amp = 1.1, sign = -1, flap = { deg = 20 } },
		EarR = { pivot = at(-0.075, 0.145, -0.015), axis = "X", amp = 1.1, sign = -1, flap = { deg = 20 } },
	},
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.56, widen = 0.80, kRel = 30, cRel = 7, pitch = 1.35 },
		feel = "plush",
		flight = { style = "float" },
	},
}

return blueprint
