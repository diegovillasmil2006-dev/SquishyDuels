--!strict
-- Bumble Bun (Uncommon, Halo Box, 2026-11-10): Claude Design's BumbleBun ("Squishies 50 Lineup", sd/toys2.js:700-715)
-- in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and
-- the size, sections and motion every view reads. A striped honey bun with a dripping honey glaze, wings that buzz
-- (sections WingL/WingR), antennae that boing (sections AntennaL/AntennaR), big eyes, a smile, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.6, 0.1442
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0, dx 0.07, eyeR 0.023 × 1.22 big eyes, smile mw 0.02 at 0.045 below, blush 0.12).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.1333 - Y0) * K, 0.0281 * K
local MOUTH_Y, MOUTH_W = (0.0866 - Y0) * K, 0.0581 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.339, 0.2883, 0.3273),
				pos = at(0, 0.1442, 0),
				color = "FFEDB4",
				body = true,
			},
			{
				-- the honey glaze on top
				name = "Glaze",
				shape = "E",
				size = size(0.3444, 0.1018, 0.3318),
				pos = at(0, 0.2399, 0),
				color = "F0A830",
				contact = v(0, -0.5, 0),
			},
		},
		pair({
			name = "WingL",
			shape = "E",
			size = size(0.0857, 0.081, 0.0678),
			pos = at(0.0915, 0.2415, -0.0963), -- 0.059 toward its holder
			color = "FFFFFF",
			section = "WingL",
			contact = v(0.5, -0.58, -0.33),
		}),
		pair({
			name = "AntennaL",
			shape = "E",
			size = size(0.0598, 0.057, 0.0294),
			pos = at(0.0623, 0.2743, 0.0317), -- 0.028 toward its holder
			color = "8A5A44",
			section = "AntennaL",
			contact = v(0.33, -0.75, 0.08),
		}),
		pair({
			-- rides AntennaL, halfway inside it (a free part drifts off a thin stalk in a squeeze)
			name = "AntennaTipL",
			shape = "E",
			size = size(0.0309, 0.0317, 0.0314),
			attach = { to = "AntennaL", offset = v(-0.0081 * K, 0.0102 * K, -0.0032 * K) },
			color = "F0A830",
			section = "AntennaL",
			contact = v(0, 0, 0),
			contactWith = "AntennaL",
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.12 * K, (0.1033 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = at(0.0701, 0.2179, -0.085), axis = "Y", amp = 1.6, sign = 1, flap = { deg = 15 } }),
		Kit.pairSection("AntennaL", { pivot = at(0.0523, 0.253, 0.0305), axis = "X", amp = 1.3, sign = -1, flap = { deg = 12 } })
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.68, kRel 42, cRel 8, pitch 1.3) and flight (glide).
	motion = {
		squeeze = { depth = 0.62, widen = 0.68, kRel = 42, cRel = 8, pitch = 1.3 },
		feel = "mochi",
		flight = { style = "glide" },
	},
}

return blueprint
