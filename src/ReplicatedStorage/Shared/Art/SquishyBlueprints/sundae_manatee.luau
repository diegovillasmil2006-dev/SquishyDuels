--!strict
-- Sundae Manatee (Rare, Frosty Box, 2026-11-10): Claude Design's SundaeManatee ("Squishies 50 Lineup",
-- sd/toys2.js:261-281) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes, with
-- the dripping syrup); this is the fallback and the size, sections and motion every view reads. A chubby lavender
-- manatee under a chocolate syrup cap, a whipped-cream swirl and a cherry on top, a big muzzle, a tail that paddles
-- (section Tail), flippers (sections FlipperL/FlipperR), happy-arc eyes, a smile, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 2.8, 0.1429
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.03, dx 0.072, eyeR 0.021 × 1.22 happy arcs, smile mw 0.02 at 0.085 below, blush 0.13).
local EYE_X, EYE_Y, EYE_R = -0.0724 * K, (0.1686 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.0819 - Y0) * K, 0.0581 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Manatee",
				shape = "E",
				size = size(0.379, 0.269, 0.4519),
				pos = at(0, 0.1429, 0.0067),
				color = "E8E4FC",
				body = true,
			},
			-- The syrup over the top (the slot's syrup drips; here a brown cap a little wider).
			{
				name = "Syrup",
				shape = "E",
				size = size(0.388, 0.16, 0.46),
				pos = at(0, 0.2, 0.006),
				color = "8A4F3A",
				body = true,
			},
			-- The muzzle is a ray target for the mouth.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.1495, 0.0969, 0.0828),
				face = F(0, (0.1062 - Y0) * K, 0.7),
				color = "F6F3FF",
				body = true,
			},
			{
				name = "Cream",
				shape = "E",
				size = size(0.1531, 0.088, 0.1531),
				pos = at(0, 0.3104, -0.03),
				color = "FFF8F0",
				contact = v(0, -0.9, 0),
			},
			{
				name = "Cherry",
				shape = "E",
				size = size(0.06, 0.06, 0.0571),
				pos = at(0, 0.3764, -0.03),
				color = "F0445E",
				contact = v(0, -1, 0),
				contactWith = "Cream",
			},
			-- The tail reaches into the body from behind: its contact is the hinge, inside the body.
			{
				name = "Tail",
				shape = "E",
				size = size(0.19, 0.05, 0.17),
				pos = at(0, 0.105, -0.235),
				color = "B0AAE6",
				section = "Tail",
				contact = v(0, 0.2, -0.765),
			},
		},
		-- Each flipper reaches into the body's side: its contact is the hinge, inside the body.
		pair({
			name = "FlipperL",
			shape = "E",
			size = size(0.09, 0.11, 0.07),
			pos = at(0.17, 0.075, 0.07),
			color = "C1BCEE",
			section = "FlipperL",
			contact = v(0.667, 0.455, 0),
		}),
		Kit.happyEyes(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.13 * K, (0.1374 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("FlipperL", { pivot = at(0.14, 0.1, 0.07), axis = "Z", amp = 1.3, sign = -1, flap = { deg = 20 } }),
		{ Tail = { pivot = at(0, 0.11, -0.17), axis = "X", amp = 1.2, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.58, widen 0.78, kRel 26, cRel 8, pitch 0.85) and flight (glide).
	motion = {
		squeeze = { depth = 0.58, widen = 0.78, kRel = 26, cRel = 8, pitch = 0.85 },
		feel = "mochi",
		flight = { style = "glide" },
	},
}

return blueprint
