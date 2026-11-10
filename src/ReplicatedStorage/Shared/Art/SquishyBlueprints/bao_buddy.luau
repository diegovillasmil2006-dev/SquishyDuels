--!strict
-- Bao Buddy (Rare, Series 01, 2026-11-10): Claude Design's BaoBuddy ("Squishies 50 Lineup", sd/toys2.js) in E parts. Its
-- real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and the size,
-- sections and motion every view reads. A pearl-white bun in a bamboo steamer, its top knot twists back (section Knot),
-- two paws on the rim, happy-arc eyes, an open mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's 1.5-1.7 like its
-- siblings), turned 180° about Y and re-based on the bun's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.47, 0.1636
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.175, dx 0.075, eyeR 0.022 × 1.22 happy arcs, open mouth mw 0.024, blush 0.128).
local EYE_X, EYE_Y, EYE_R = -0.0755 * K, (0.1758 - Y0) * K, 0.0268 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Bun",
				shape = "E",
				size = size(0.38, 0.2468, 0.38),
				pos = at(0, 0.1636, 0),
				color = "FFFBFD",
				body = true,
			},
			-- The steamer, as wide as its bands (the slot fits its longest side to this).
			{
				name = "Steamer",
				shape = "E",
				size = size(0.461, 0.114, 0.461),
				pos = at(0, 0.057, 0),
				color = "E8C892",
				body = true,
			},
			{
				name = "Knot",
				shape = "E",
				size = size(0.06, 0.032, 0.06),
				pos = at(0, 0.287, 0),
				color = "FFF4F9",
				section = "Knot",
				contact = v(0, -0.8, 0),
			},
		},
		-- The paws sit 0.016 further in than the design's, so their backs touch the bun in this E-part look.
		pair({
			name = "PawL",
			shape = "E",
			size = size(0.068, 0.044, 0.0495),
			pos = at(0.1, 0.118, 0.17),
			color = "FFF1F6",
			contact = v(0, 0.4, 1),
		}),
		Kit.happyEyes(EYE_X, EYE_Y, EYE_R),
		{
			{
				name = "Mouth",
				shape = "E",
				size = size(0.04, 0.0318, 0.0136),
				face = F(0, (0.1328 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0256, 0.0159, 0.0107),
				attach = { to = "Mouth", offset = size(0, -0.0064, -0.003) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		Kit.blush2(-0.128 * K, (0.147 - Y0) * K, 0.021 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = {
		Knot = { pivot = at(0, 0.283, 0), axis = "Z", amp = 1.0, sign = -1, flap = { deg = 10 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.58, widen 0.78, kRel 28, cRel 8, pitch 0.95) and flight (upright).
	motion = {
		squeeze = { depth = 0.58, widen = 0.78, kRel = 28, cRel = 8, pitch = 0.95 },
		feel = "mochi",
		flight = { style = "upright" },
	},
}

return blueprint
