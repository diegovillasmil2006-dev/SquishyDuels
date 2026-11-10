--!strict
-- Cotton Candy Alpaca (Uncommon, Prism Box, 2026-11-10): Claude Design's CottonCandyAlpaca ("Squishies 50 Lineup",
-- sd/toys2.js:541-558) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the fluffy bumps); this is the fallback and the size, sections and motion every view reads. A tall fluffy body, a
-- muzzle, ears that flop (sections EarL/EarR), hooves, eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side, ears included, about 1.6
-- studs), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.3, 0.2301
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.03, dx 0.068, eyeR 0.022 × 1.22 big eyes, cat mouth mw 0.013 at 0.072 below, blush 0.115).
local EYE_X, EYE_Y, EYE_R = -0.068 * K, (0.2433 - Y0) * K, 0.0268 * K
local MOUTH_Y, MOUTH_W = (0.1686 - Y0) * K, 0.043 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3621, 0.4603, 0.3468),
				pos = at(0, 0.2301, 0),
				color = "FFD6EC",
				body = true,
			},
			-- The muzzle's back is inside the body.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.0957, 0.0718, 0.0475),
				pos = at(0, 0.1825, 0.157),
				color = "FFF8EE",
				contact = v(0, 0.25, 0.75),
			},
			{
				name = "Hooves",
				shape = "E",
				size = size(0.1995, 0.032, 0.1933),
				pos = at(0, 0.0273, 0),
				color = "D9C8F5",
				contact = v(0, 0.75, 0),
			},
		},
		-- The ears' contact is their hinge, just inside the body's top.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.1099, 0.0708, 0.0346),
			pos = at(0.1038, 0.4211, -0.0009), -- 0.033 into the body
			color = "FFB8DA",
			section = "EarL",
			contact = v(0.67, -0.5, -0.08),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.115 * K, (0.2083 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.pairSection("EarL", { pivot = at(0.0672, 0.4034, 0.0006), axis = "Z", amp = 1.0, sign = -1, flap = { deg = 15 } }),
	-- The design's CATALOG2 squeeze (depth 0.54, widen 0.82, kRel 26, cRel 7, pitch 1.2) and flight (float).
	motion = {
		squeeze = { depth = 0.55, widen = 0.82, kRel = 26, cRel = 7, pitch = 1.2 }, -- depth: the game's lowest (0.55)
		feel = "foam",
		flight = { style = "float" },
	},
}

return blueprint
