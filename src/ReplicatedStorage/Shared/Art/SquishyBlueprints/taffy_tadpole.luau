--!strict
-- Taffy Tadpole (Common, Prism Box, 2026-11-10): Claude Design's TaffyTadpole ("Squishies 50 Lineup",
-- sd/toys2.js:505-518) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the pink and blue taffy twist); this is the fallback and the size, sections and motion every view reads. A round taffy
-- body, a long curly tail that sways (section Tail; the real model carries its star on the tip), big eyes, a smile,
-- cheeks.

local Kit = require(script.Parent.Kit)

local v, concat = Kit.v, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side, tail included, about 1.6
-- studs), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 2.9, 0.131
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0, dx 0.07, eyeR 0.025 × 1.22 big eyes, smile mw 0.02 at 0.046 below, blush 0.12).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.1221 - Y0) * K, 0.0305 * K
local MOUTH_Y, MOUTH_W = (0.0749 - Y0) * K, 0.0581 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3189, 0.2621, 0.3365),
				pos = at(0, 0.131, 0),
				color = "FFD3E8",
				body = true,
			},
			-- The tail reaches into the body from behind: its contact is the hinge, inside the body.
			{
				name = "Tail",
				shape = "E",
				size = size(0.1456, 0.1391, 0.2641),
				pos = at(0.0143, 0.1297, -0.2479),
				color = "D3B6FF",
				section = "Tail",
				contact = v(0, 0, -0.83),
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.12 * K, (0.0921 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = {
		Tail = { pivot = at(0.0143, 0.1297, -0.1379), axis = "Y", amp = 1.4, sign = 1, flap = { deg = 12 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.7, kRel 44, cRel 7.5, pitch 1.3) and flight (wobble).
	motion = {
		squeeze = { depth = 0.6, widen = 0.7, kRel = 44, cRel = 7.5, pitch = 1.3 },
		feel = "mochi",
		flight = { style = "wobble" },
	},
}

return blueprint
