--!strict
-- Custard Cherub (Rare, Halo Box, 2026-11-10): Claude Design's CustardCherub ("Squishies 50 Lineup",
-- sd/toys2.js:736-754) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes);
-- this is the fallback and the size, sections and motion every view reads. A custard bun with a curl on top, a gold
-- halo (section Halo; in this fallback it rests on the head, since a floating part has no hold), feather wings that
-- flutter (sections WingL/WingR), little arms and feet, big eyes, an open mouth, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4.6, 0.1578
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.01, dx 0.07, eyeR 0.024 × 1.22 big eyes, open mouth mw 0.02 at 0.046 below, blush 0.12).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.1607 - Y0) * K, 0.0293 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3289, 0.3157, 0.3071),
				pos = at(0, 0.1578, 0),
				color = "FFF3CC",
				body = true,
			},
			{
				name = "Halo",
				shape = "E",
				size = size(0.164, 0.03, 0.1589),
				pos = at(0, 0.3021, -0.0064), -- 0.083 toward its holder
				color = "F4D27A",
				section = "Halo",
				contact = v(0, -0.83, 0),
			},
			{
				name = "Curl",
				shape = "E",
				size = size(0.0578, 0.0675, 0.0357),
				pos = at(0.0137, 0.3103, 0.042), -- 0.015 toward its holder
				color = "F2C46A",
				contact = v(0.08, -0.83, 0),
			},
			{
				name = "Feet",
				shape = "E",
				size = size(0.1771, 0.036, 0.0647),
				pos = at(0, 0.0377, 0.0909), -- 0.015 toward its holder
				color = "FFE8B0",
				contact = v(0, 0.5, 0.67),
			},
			{
				name = "Mouth",
				shape = "E",
				size = size(0.0333, 0.0261, 0.0121),
				face = Kit.F(0, (0.115 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0213, 0.0132, 0.0091),
				attach = { to = "Mouth", offset = size(0, -0.005, -0.002) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		pair({
			name = "WingL",
			shape = "E",
			size = size(0.0868, 0.0764, 0.0808),
			pos = at(0.1146, 0.1801, -0.1201), -- 0.018 toward its holder
			color = "FFFFFF",
			section = "WingL",
			contact = v(0.5, -0.08, -0.67),
		}),
		pair({
			name = "ArmL",
			shape = "E",
			size = size(0.0548, 0.0443, 0.0546),
			pos = at(0.1112, 0.104, 0.0878),
			color = "FFE8B0",
			contact = v(0.58, 0.25, 0.5),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.12 * K, (0.1287 - Y0) * K, 0.028 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = at(0.0929, 0.1769, -0.0932), axis = "Y", amp = 1.5, sign = 1, flap = { deg = 15 } }),
		{
			Halo = { pivot = at(0, 0.2896, -0.0064), axis = "Z", amp = 0.5, sign = -1, maxDeg = 10 },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.72, kRel 34, cRel 7.5, pitch 1.35) and flight (float).
	motion = {
		squeeze = { depth = 0.6, widen = 0.72, kRel = 34, cRel = 7.5, pitch = 1.35 },
		feel = "jelly",
		flight = { style = "float" },
	},
}

return blueprint
