--!strict
-- Souffle Seraph (Epic, Halo Box, 2026-11-10): Claude Design's SouffleSeraph ("Squishies 50 Lineup",
-- sd/toys2.js:756-771) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes);
-- this is the fallback and the size, sections and motion every view reads. A souffle rising out of its ramekin, a gold
-- halo (section Halo; in this fallback it rests on the head), three feather wings a side that flap together (sections
-- WingL/WingR: a squishy has at most 6 sections), happy eyes, an open mouth, cheeks.
-- Hinges and contacts: the point deepest inside both the part and its holder (halo/gen_bp.mjs, |q| <= 0.84); a part is
-- moved toward its holder only where the design's spot left no room.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 4, 0.2327
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.228, dx 0.066, eyeR 0.022 × 1.22 happy eyes, open mouth mw 0.02 at 0.044 below, blush 0.11).
local EYE_X, EYE_Y, EYE_R = -0.066 * K, (0.2305 - Y0) * K, 0.0268 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.31, 0.2245, 0.31),
				pos = at(0, 0.2327, 0),
				color = "FFF4D0",
				body = true,
			},
			{
				-- the ramekin it rises out of
				name = "Ramekin",
				shape = "E",
				size = size(0.3443, 0.164, 0.344),
				pos = at(0, 0.082, 0),
				color = "FFFFFF",
				contact = v(0, 0.75, 0),
			},
			{
				name = "Halo",
				shape = "E",
				size = size(0.184, 0.03, 0.1783),
				pos = at(0, 0.3391, -0.0058), -- 0.076 toward its holder
				color = "F4D27A",
				section = "Halo",
				contact = v(0, -0.83, -0.08),
			},
			{
				name = "Mouth",
				shape = "E",
				size = size(0.0333, 0.0266, 0.0113),
				face = Kit.F(0, (0.1841 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0213, 0.0133, 0.0089),
				attach = { to = "Mouth", offset = size(0, -0.005, -0.002) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		pair({
			name = "Wing1L",
			shape = "E",
			size = size(0.0651, 0.0568, 0.0834),
			pos = at(0.1472, 0.2289, -0.0566), -- 0.023 toward its holder
			color = "FFFFFF",
			section = "WingL",
			contact = v(0.75, 0.17, -0.33),
		}),
		pair({
			name = "Wing2L",
			shape = "E",
			size = size(0.0723, 0.0665, 0.0678),
			pos = at(0.1365, 0.1701, -0.0153), -- 0.035 toward its holder
			color = "FFFFFF",
			section = "WingL",
			contact = v(0.67, 0.5, -0.08),
		}),
		pair({
			name = "Wing3L",
			shape = "E",
			size = size(0.0741, 0.0775, 0.0503),
			pos = at(0.1614, 0.082, -0.0626), -- 0.004 toward its holder
			color = "FFFFFF",
			section = "WingL",
			contact = v(0.75, 0, -0.33),
			contactWith = "Ramekin",
		}),
		Kit.happyEyes(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.11 * K, (0.2 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("WingL", { pivot = at(0.1228, 0.2336, -0.0427), axis = "Y", amp = 1.5, sign = 1, flap = { deg = 15 } }),
		{
			Halo = { pivot = at(0, 0.3266, 0.0016), axis = "Z", amp = 0.5, sign = -1, maxDeg = 10 },
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.58, widen 0.74, kRel 30, cRel 7.5, pitch 1.0) and flight (upright).
	motion = {
		squeeze = { depth = 0.58, widen = 0.74, kRel = 30, cRel = 7.5, pitch = 1.0 },
		feel = "foam",
		flight = { style = "upright" },
	},
}

return blueprint
