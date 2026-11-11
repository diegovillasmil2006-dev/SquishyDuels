--!strict
-- Peppermint Puffin (Epic, Christmas, big job item 11, 2026-11-10): Claude Design's PeppermintPuffin ("Squishies
-- 50 Lineup", sd/toys2.js:826-843) in E parts. This is the fallback and the size, sections and motion every view
-- reads (its real look will be its ReplicatedStorage.SD_Models slot, the design's own meshes: the red peppermint
-- swirl on its white body lives there). A round white puffin with an orange beak, a green scarf whose end swings
-- (section ScarfTail), red wings that flap (sections WingL/WingR), a red tail (section Tail) and orange feet; big
-- eyes, no mouth (the beak).
-- Written by Claude-Backups/2026-11-10-xmas/tools/gen_bp_xmas.py: hinges and contacts are the point deepest inside
-- both the part and its holder (|q| <= 0.84); a part is moved toward its holder only where the design's spot left
-- no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.2, 0.171
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.06, dx 0.064, eyeR 0.023 × 1.22 big eyes, no mouth, blush 0.105 at 0.05 below).
local EYE_X, EYE_Y, EYE_R = -0.064 * K, (0.2221 - Y0) * K, 0.0281 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.31, 0.3421, 0.3),
				pos = at(0, 0.171, 0),
				color = "FFFFFF",
				body = true,
			},
			{
				name = "Scarf",
				shape = "E",
				size = size(0.344, 0.044, 0.344),
				pos = at(0, 0.137, 0),
				color = "5DCB8A",
				contact = v(0, 0, 0),
			},
			{
				name = "Beak",
				shape = "E",
				size = size(0.072, 0.056, 0.086),
				pos = at(0, 0.178, 0.16),
				color = "FF8A4A",
				contact = v(0, 0, 0.84),
			},
			{
				name = "ScarfTail",
				shape = "E",
				size = size(0.052, 0.1, 0.024),
				pos = at(0.0958, 0.1019, 0.095), -- 0.024 toward its holder
				color = "5DCB8A",
				section = "ScarfTail",
				contact = v(0.56, 0.56, 0.28),
			},
			{
				name = "Tail",
				shape = "E",
				size = size(0.08, 0.028, 0.07),
				pos = at(0, 0.0905, -0.1341), -- 0.036 toward its holder
				color = "F04A5E",
				section = "Tail",
				contact = v(0, 0, -0.84),
			},
		},
		pair({
			name = "WingL",
			shape = "E",
			size = size(0.048, 0.124, 0.084),
			pos = at(0.1435, 0.1118, -0.0224), -- 0.018 toward its holder
			color = "F04A5E",
			section = "WingL",
			contact = v(0.7, 0.42, -0.14),
		}),
		pair({
			name = "FootL",
			shape = "E",
			size = size(0.058, 0.026, 0.03),
			pos = at(0.0454, 0.0497, 0.0784), -- 0.032 toward its holder
			color = "FF8A4A",
			contact = v(0.28, 0.56, 0.56),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.105 * K, (0.172 - Y0) * K, 0.0225 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = at(0.1267, 0.1378, -0.0165), axis = "Z", amp = 1.5, sign = 1, flap = { deg = 15 } }),
		{
			ScarfTail = { pivot = at(0.0813, 0.1299, 0.0916), axis = "X", amp = 1.3, sign = 1 },
			Tail = { pivot = at(0, 0.0905, -0.1047), axis = "X", amp = 1.2, sign = 1 },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 46, cRel 7.5, pitch 1.3) and flight (spiral).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 46, cRel = 7.5, pitch = 1.3 },
		feel = "jelly",
		flight = { style = "spiral" },
	},
}

return blueprint
