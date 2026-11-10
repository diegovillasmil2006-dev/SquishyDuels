--!strict
-- Gummy Pufferfish (Epic, Prism Box, 2026-11-10): Claude Design's GummyPufferfish ("Squishies 50 Lineup",
-- sd/toys2.js:611-628) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the gummy bumps); this is the fallback and the size, sections and motion every view reads. A round gummy puffer, side
-- fins that flutter (sections FinL/FinR), a tail fin (section Tail) and a top fin (section TopFin), big eyes, an open
-- mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side, fins included, about 1.6
-- studs), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.4, 0.1803
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y -0.005, dx 0.08, eyeR 0.026 × 1.22 big eyes, open mouth mw 0.018 at 0.05 below, blush 0.13).
local EYE_X, EYE_Y, EYE_R = -0.08 * K, (0.164 - Y0) * K, 0.0317 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3989, 0.3606, 0.3717),
				pos = at(0, 0.1803, 0),
				color = "FFC46B",
				body = true,
			},
			-- The tail fin and the top fin reach into the body: their contact is the hinge, inside the body.
			{
				name = "TailFin",
				shape = "E",
				size = size(0.0228, 0.1464, 0.0801),
				pos = at(0, 0.1708, -0.189), -- 0.036 into the body
				color = "FF8FB0",
				section = "Tail",
				contact = v(0, 0.08, -0.83),
			},
			{
				name = "TopFin",
				shape = "E",
				size = size(0.024, 0.0768, 0.0698),
				pos = at(0, 0.346, -0.0765),
				color = "FF8FB0",
				section = "TopFin",
				contact = v(0, -0.75, -0.33),
			},
			{
				name = "Mouth",
				shape = "E",
				size = size(0.03, 0.0229, 0.0122),
				face = Kit.F(0, (0.1145 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0192, 0.0116, 0.0085),
				attach = { to = "Mouth", offset = size(0, -0.005, -0.002) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		-- The side fins' contact is their hinge, just inside the body's side.
		pair({
			name = "FinL",
			shape = "E",
			size = size(0.0792, 0.0696, 0.0401),
			pos = at(0.1947, 0.1412, 0.0137), -- 0.021 into the body
			color = "FF8FB0",
			section = "FinL",
			contact = v(0.83, 0.08, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.13 * K, (0.134 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("FinL", { pivot = at(0.1617, 0.1441, 0.0137), axis = "Y", amp = 1.4, sign = 1, flap = { deg = 15 } }),
		{
			Tail = { pivot = at(0, 0.1769, -0.1557), axis = "Y", amp = 1.6, sign = 1, flap = { deg = 12 } },
			TopFin = { pivot = at(0, 0.3172, -0.0649), axis = "X", amp = 1.2, sign = -1, flap = { deg = 12 } },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.66, widen 0.6, kRel 52, cRel 7, pitch 1.4) and flight (float).
	motion = {
		squeeze = { depth = 0.66, widen = 0.6, kRel = 52, cRel = 7.2, pitch = 1.4 }, -- cRel: under 1 Hz (design 7)
		feel = "jelly",
		flight = { style = "float" },
	},
}

return blueprint
