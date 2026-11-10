--!strict
-- Mint Chip Mouse (Uncommon, Frosty Box, 2026-11-10): Claude Design's MintChipMouse ("Squishies 50 Lineup",
-- sd/toys2.js:242-259) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- its chocolate chips); this is the fallback and the size, sections and motion every view reads. A mint scoop, big round
-- ears with pink insides that flop (sections EarL/EarR), a curly pink tail (section Tail), a wafer stick on top, a pink
-- nose, eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the scoop's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.9, 0.1342
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.004, dx 0.07, eyeR 0.022 × 1.22, cat mouth mw 0.015 at 0.045 below, blush 0.115).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.1224 - Y0) * K, 0.0268 * K
local MOUTH_Y, MOUTH_W = (0.0754 - Y0) * K, 0.05 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Scoop",
				shape = "E",
				size = size(0.3387, 0.2684, 0.3291),
				pos = at(0, 0.1342, 0),
				color = "D6F8E7",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.028, 0.0199, 0.0141),
				face = F(0, (0.0966 - Y0) * K, 0.6),
				color = "FF8FA8",
				look = "detail",
			},
			-- The wafer stands in the scoop's top: its bottom end is inside.
			{
				name = "Wafer",
				shape = "E",
				size = size(0.028, 0.108, 0.028),
				pos = at(-0.06, 0.27, -0.065),
				color = "E9C17E",
				contact = v(0, -0.9, 0),
			},
			-- The tail reaches into the scoop from behind: its contact is the hinge, inside the scoop.
			{
				name = "Tail",
				shape = "E",
				size = size(0.07, 0.1, 0.11),
				pos = at(0.025, 0.095, -0.17),
				color = "FF9FB6",
				section = "Tail",
				contact = v(0.43, -0.3, -0.727),
			},
		},
		-- The ears reach down to their hinges inside the scoop (the design's thin discs sit on its top).
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.12, 0.12, 0.034),
			pos = at(0.135, 0.245, -0.022),
			color = "A8EBCB",
			section = "EarL",
			contact = v(0.667, -0.5, -0.118),
		}),
		pair({
			name = "InnerEarL",
			shape = "E",
			size = size(0.0726, 0.0739, 0.0201),
			attach = { to = "EarL", offset = size(-0.008, 0.0107, -0.0073) },
			color = "FFB8C8",
			section = "EarL",
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.115 * K, (0.0944 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.095, 0.215, -0.02), axis = "Z", amp = 0.9, sign = -1, flap = { deg = 15 } }),
		{ Tail = { pivot = at(0.01, 0.08, -0.13), axis = "Y", amp = 1.0, sign = 1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.72, kRel 34, cRel 8, pitch 1.3) and flight (tumble).
	motion = {
		squeeze = { depth = 0.6, widen = 0.72, kRel = 34, cRel = 8, pitch = 1.3 },
		feel = "foam",
		flight = { style = "tumble" },
	},
}

return blueprint
