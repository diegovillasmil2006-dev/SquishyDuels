--!strict
-- Meringue Chick (Common, Halo Box, 2026-11-10): Claude Design's MeringueChick ("Squishies 50 Lineup",
-- sd/toys2.js:662-683) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes);
-- this is the fallback and the size, sections and motion every view reads. A meringue drop with a curled peak, a beak,
-- wings that flap (sections WingL/WingR), little feet, big eyes, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.3, 0.1587
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.035, dx 0.065, eyeR 0.021 × 1.22 big eyes, no mouth (the beak), blush 0.105).
local EYE_X, EYE_Y, EYE_R = -0.065 * K, (0.1725 - Y0) * K, 0.0256 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3278, 0.3175, 0.3124),
				pos = at(0, 0.1587, 0),
				color = "FFFDF6",
				body = true,
			},
			{
				-- the meringue peak
				name = "Curl",
				shape = "E",
				size = size(0.0635, 0.0731, 0.05),
				pos = at(0.0096, 0.3219, 0), -- 0.010 toward its holder
				color = "FFFDF6",
				contact = v(0.08, -0.83, 0),
			},
			{
				name = "Beak",
				shape = "E",
				size = size(0.0479, 0.0464, 0.0363),
				pos = at(-0.0003, 0.139, 0.1449), -- 0.013 toward its holder
				color = "FFA64D",
				contact = v(0, 0.08, 0.83),
			},
			{
				name = "Feet",
				shape = "E",
				size = size(0.164, 0.024, 0.0208),
				pos = at(0, 0.0477, 0.0877), -- 0.036 toward its holder
				color = "FFA64D",
				contact = v(0, 0.67, 0.5),
			},
		},
		pair({
			name = "WingL",
			shape = "E",
			size = size(0.0529, 0.0935, 0.0762),
			pos = at(0.1477, 0.0948, -0.0128), -- 0.012 toward its holder
			color = "FFF4DE",
			section = "WingL",
			contact = v(0.67, 0.5, -0.08),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.105 * K, (0.1275 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = at(0.1301, 0.1182, -0.0097), axis = "Z", amp = 1.5, sign = -1, flap = { deg = 15 } })
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 48, cRel 7.5, pitch 1.4) and flight (hop).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 48, cRel = 7.5, pitch = 1.4 },
		feel = "foam",
		flight = { style = "hop" },
	},
}

return blueprint
