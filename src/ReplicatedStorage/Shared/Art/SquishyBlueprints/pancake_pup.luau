--!strict
-- Pancake Pup (Common, new; spec 2026-10-09 §4): the 3D Lab PancakePup (sd/toys.js) in E/B parts. Three pancake E (body),
-- a syrup band with 2 drips, a butter pat, floppy ears (sections EarL/EarR), nose, ω mouth with a small tongue, and a
-- curled tail (section Tail). 20 visible + 6 hidden squish-face parts + Root.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design units (toys.js metres, face +Z, stack base at y = 0) to studs at scale 1: K studs per unit, turned 180° about Y
-- (x -> -x, z -> -z) and re-based so the pivot sits at the middle pancake (design y = Y0).
local K, Y0 = 3.75, 0.11
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

local PANCAKE, SYRUP, BROWN = "EFC68B", "C8752A", "9B6338"
local PANCAKE_SIZE = size(0.36, 0.096, 0.36) -- plumper than the design's 0.034 half-height: E edges thin out
-- Face (design face(): y 0.168, dx 0.06, eyeR 0.02 × 1.22, blush 0.11 / 0.012). The ω sits under the nose and is wider
-- than the design's (mw 0.016) so it reads at duel distance.
local EYE_X, EYE_Y, EYE_R = -0.06 * K, (0.168 - Y0) * K, 0.0244 * K
local MOUTH_Y, MOUTH_W = (0.09 - Y0) * K, 0.05 * K
-- Ear hinge: deep inside the top pancake (at its middle plane), so the ear root stays in it through every squeeze and
-- flare (the design's x 0.165 sits outside an E pancake); the ears splay 20° (design 12.6°) to hang past the rim.
local EAR_PIVOT = at(0.13, 0.16, 0.03)
local TAIL_PIVOT = at(0, 0.105, -0.15)

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "PancakeBottom",
				shape = "E",
				size = PANCAKE_SIZE,
				pos = at(0.008, 0.034, 0),
				color = PANCAKE,
				body = true,
			},
			{
				name = "PancakeMiddle",
				shape = "E",
				size = PANCAKE_SIZE,
				pos = at(-0.008, 0.1, 0.004),
				color = PANCAKE,
				body = true,
			},
			{
				name = "PancakeTop",
				shape = "E",
				size = PANCAKE_SIZE,
				pos = at(0, 0.166, 0),
				color = PANCAKE,
				body = true,
			},
			-- Syrup: a cap over the top pancake that shows as a band above the eyes.
			{
				name = "Syrup",
				shape = "E",
				size = size(0.372, 0.06, 0.372),
				pos = at(0, 0.19, 0),
				color = SYRUP,
				contact = v(0, -1, 0),
			},
			{
				name = "Butter",
				shape = "B",
				size = size(0.09, 0.04, 0.09),
				pos = at(0.02, 0.23, -0.02),
				rot = v(0, 23, 0),
				color = "FBE38C",
				contact = v(0, -1, 0),
			},
		},
		-- Floppy ears hang from the top pancake, splayed outward at the bottom.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.1, 0.17, 0.044),
			pos = at(0.1539, 0.0942, 0.03),
			rot = v(0, 0, -20),
			color = BROWN,
			section = "EarL",
			contact = v(0, 0.8, 0),
		}),
		{
			{
				name = "Tail",
				shape = "E",
				size = size(0.045, 0.13, 0.045),
				pos = at(0.008, 0.14, -0.175),
				rot = v(40.8, 0, 15.7),
				color = BROWN,
				section = "Tail",
				contact = v(0, -0.7, 0),
			},
			-- Two syrup drips down the front sides (the design's 6, cut to the two that face the viewer).
			{
				name = "DripL",
				shape = "E",
				size = size(0.035, 0.08, 0.025),
				face = F(-0.15 * K, (0.15 - Y0) * K, 0.6),
				color = SYRUP,
				look = "detail",
			},
			{
				name = "DripR",
				shape = "E",
				size = size(0.04, 0.1, 0.025),
				face = F(0.13 * K, (0.155 - Y0) * K, 0.6),
				color = SYRUP,
				look = "detail",
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.044, 0.032, 0.024),
				face = F(0, (0.116 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		{
			-- The small tongue under the ω's left half, in front of it; its back stays inside MouthL.
			{
				name = "Tongue",
				shape = "E",
				size = size(0.024, 0.03, 0.011),
				attach = { to = "MouthL", offset = size(0.003, -0.006, -0.004) },
				color = Kit.TONGUE,
				look = "mouth",
			},
		},
		Kit.blush2(-0.11 * K, (0.156 - Y0) * K, 0.022 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = EAR_PIVOT, axis = "Z", amp = 1.6, sign = -1, flap = { deg = 25 } }),
		{ Tail = { pivot = TAIL_PIVOT, axis = "Z", amp = 2.0, sign = -1 } }
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.58, widen = 0.68, kRel = 36, cRel = 8.5, pitch = 1.1 },
		feel = "foam",
		flight = { style = "frisbee" },
	},
}

return blueprint
