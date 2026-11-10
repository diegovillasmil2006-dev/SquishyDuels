--!strict
-- Gumball Goat (Rare, Prism Box, 2026-11-10): Claude Design's GumballGoat ("Squishies 50 Lineup", sd/toys2.js:585-609)
-- in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with the gumballs inside
-- the glass); this is the fallback and the size, sections and motion every view reads. A gumball machine goat: the glass
-- globe on a red stand, a crank that spins (section Crank), the coin chute, a red cap, curly horns, ears that flap
-- (sections EarL/EarR), eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, pair, concat = Kit.v, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs),
-- turned 180° about Y and re-based on the globe's middle (design y = Y0, the slot model's pivot).
local K, Y0 = 3.3, 0.2821
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.262, dx 0.072, eyeR 0.022 × 1.22, cat mouth mw 0.015 at 0.048 below, blush 0.12).
local EYE_X, EYE_Y, EYE_R = -0.072 * K, (0.262 - Y0) * K, 0.0268 * K
local MOUTH_Y, MOUTH_W = (0.2127 - Y0) * K, 0.047 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Globe",
				shape = "E",
				size = size(0.3487, 0.3059, 0.3364),
				pos = at(0, 0.2821, 0),
				color = "F4FAFF",
				body = true,
			},
			{
				name = "Stand",
				shape = "E",
				size = size(0.284, 0.16, 0.284),
				pos = at(0, 0.08, 0),
				color = "F2667A",
				body = true,
			},
			-- The cap sits in the globe's top.
			{
				name = "Cap",
				shape = "E",
				size = size(0.1019, 0.03, 0.1019),
				pos = at(0, 0.423, 0), -- set into the globe's top
				color = "F2667A",
				contact = v(0, -0.83, 0),
			},
			-- The coin chute's back is inside the stand.
			{
				name = "Chute",
				shape = "E",
				size = size(0.05, 0.028, 0.02),
				pos = at(0, 0.045, 0.106),
				color = "8A3A4A",
				contact = v(0, 0.67, 0.42),
				contactWith = "Stand",
			},
			-- The crank disc's back is inside the stand: its contact is the hinge.
			{
				name = "Crank",
				shape = "E",
				size = size(0.06, 0.06, 0.016),
				pos = at(0, 0.1, 0.113),
				color = "DDE3F0",
				section = "Crank",
				contact = v(0, 0, 0.59),
				contactWith = "Stand",
			},
		},
		-- The horns curl back from the globe's top.
		pair({
			name = "HornL",
			shape = "E",
			size = size(0.1157, 0.0909, 0.1057),
			pos = at(0.0559, 0.4393, -0.0235), -- set into the globe's top
			color = "FFF0D6",
			contact = v(0.33, -0.75, -0.17),
		}),
		-- The ears' contact is their hinge, just inside the globe's side.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0939, 0.0497, 0.0495),
			pos = at(0.1843, 0.2935, 0),
			color = "F6E8D8",
			section = "EarL",
			contact = v(0.83, 0, 0),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.12 * K, (0.232 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.1452, 0.2935, 0), axis = "Z", amp = 1.2, sign = -1, flap = { deg = 15 } }),
		{ Crank = { pivot = at(0, 0.1, 0.1083), axis = "Z", amp = 1.4, sign = -1, flap = { deg = 20 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.64, widen 0.62, kRel 42, cRel 8.5, pitch 1.1) and flight (tumble).
	motion = {
		squeeze = { depth = 0.64, widen = 0.62, kRel = 42, cRel = 8.5, pitch = 1.1 },
		feel = "jelly",
		flight = { style = "tumble" },
	},
}

return blueprint
