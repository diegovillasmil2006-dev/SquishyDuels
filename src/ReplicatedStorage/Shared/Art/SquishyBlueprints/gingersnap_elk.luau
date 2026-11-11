--!strict
-- Gingersnap Elk (Rare, Christmas, big job item 11, 2026-11-10): Claude Design's GingersnapElk ("Squishies 50
-- Lineup", sd/toys2.js:799-824) in E parts. This is the fallback and the size, sections and motion every view
-- reads (its real look will be its ReplicatedStorage.SD_Models slot, the design's own meshes). A soft-baked cookie
-- elk: a white icing trim round its lower body, a red and a green gumdrop on its tummy, a cream muzzle with a red
-- nose, ears that flick (sections EarL/EarR), rigid antlers (their white icing tips: the real meshes only), hooves.
-- Written by Claude-Backups/2026-11-10-xmas/tools/gen_bp_xmas.py: hinges and contacts are the point deepest inside
-- both the part and its holder (|q| <= 0.84); a part is moved toward its holder only where the design's spot left
-- no room. The antlers are one flat piece a side here (the design's are three thin branches).

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.6, 0.151
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.06, dx 0.068, eyeR 0.021, smile mw 0.016 at 0.062 below, blush 0.12 at 0.045 below).
local EYE_X, EYE_Y, EYE_R = -0.068 * K, (0.2021 - Y0) * K, 0.021 * K
local MOUTH_Y, MOUTH_W = (0.138 - Y0) * K, 0.0465 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3398, 0.302, 0.3),
				pos = at(0, 0.151, 0),
				color = "F2C48C",
				body = true,
			},
			{
				name = "IcingTrim",
				shape = "E",
				size = size(0.352, 0.036, 0.316),
				pos = at(0, 0.087, 0),
				color = "FFFFFF",
				contact = v(0, 0, 0),
			},
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.1, 0.068, 0.048),
				pos = at(0, 0.161, 0.137),
				color = "FBE2C0",
				contact = v(0, 0, 0.84),
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.04, 0.032, 0.024),
				pos = at(0, 0.175, 0.155),
				color = "F04A5E",
				look = "detail",
				contactWith = "Muzzle",
				contact = v(0, -0.42, 0.7),
			},
			{
				name = "GumdropRed",
				shape = "E",
				size = size(0.032, 0.03, 0.022),
				pos = at(0, 0.083, 0.1179), -- 0.022 toward its holder
				color = "F04A5E",
				look = "detail",
				contact = v(0, 0.42, 0.7),
			},
			{
				name = "GumdropGreen",
				shape = "E",
				size = size(0.032, 0.032, 0.02),
				pos = at(0, 0.121, 0.1305), -- 0.018 toward its holder
				color = "5DCB8A",
				look = "detail",
				contact = v(0, 0.28, 0.77),
			},
		},
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.068, 0.06, 0.028),
			pos = at(0.1482, 0.2281, 0), -- 0.028 toward its holder
			color = "C98A4E",
			section = "EarL",
			contact = v(0.7, -0.42, 0),
		}),
		pair({
			name = "AntlerL",
			shape = "E",
			size = size(0.13, 0.17, 0.044),
			pos = at(0.0794, 0.3322, -0.0065), -- 0.014 toward its holder
			color = "B87A44",
			rigidity = 0.9,
			contact = v(0.28, -0.77, -0.14),
		}),
		pair({
			name = "HoofL",
			shape = "E",
			size = size(0.064, 0.036, 0.072),
			pos = at(0.0587, 0.0363, 0.0768), -- 0.016 toward its holder
			color = "9C6A3E",
			contact = v(0.28, 0.56, 0.56),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.12 * K, (0.157 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.1244, 0.2155, 0), axis = "Z", amp = 1, sign = 1 }),
		{
		}
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.68, kRel 36, cRel 8.5, pitch 1) and flight (tumble).
	motion = {
		squeeze = { depth = 0.62, widen = 0.68, kRel = 36, cRel = 8.5, pitch = 1 },
		feel = "foam",
		flight = { style = "tumble" },
	},
}

return blueprint
