--!strict
-- S'more Skunk (Uncommon, Lava Box, 2026-11-10): Claude Design's SmoreSkunk ("Squishies 50 Lineup", sd/toys2.js:382-403)
-- in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and
-- the size, sections and motion every view reads. A chocolate-brown skunk with a marshmallow stripe between two graham
-- crackers, a big fluffy mallow tail with a toasted tip (section Tail), ears that wobble (sections EarL/EarR), a muzzle
-- and nose, eyes, a cat mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.0, 0.151
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.004, dx 0.066, eyeR 0.021 × 1.22, cat mouth mw 0.014 at 0.056 below, blush 0.105).
local EYE_X, EYE_Y, EYE_R = -0.066 * K, (0.1461 - Y0) * K, 0.0256 * K
local MOUTH_Y, MOUTH_W = (0.0891 - Y0) * K, 0.047 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.2993, 0.3021, 0.3365),
				pos = at(0, 0.151, 0),
				color = "8E5E48",
				body = true,
			},
			-- The marshmallow stripe down the middle (the design colours the body white where |x| is small).
			{
				name = "Stripe",
				shape = "E",
				size = size(0.09, 0.3, 0.31),
				pos = at(0, 0.17, -0.01),
				color = "FFF8EE",
				body = true,
			},
			-- The muzzle is a ray target for the nose and the mouth.
			{
				name = "Muzzle",
				shape = "E",
				size = size(0.0959, 0.0624, 0.0436),
				face = F(0, (0.1043 - Y0) * K, 0.7),
				color = "F6E9DA",
				body = true,
			},
			{
				name = "Nose",
				shape = "E",
				size = size(0.028, 0.0199, 0.0138),
				face = F(0, (0.1139 - Y0) * K, 0.6),
				color = Kit.INK,
				look = "detail",
			},
			-- The tail rises from behind the body: its contact is the hinge, inside the body.
			{
				name = "Tail",
				shape = "E",
				size = size(0.1479, 0.3989, 0.2388),
				pos = at(0, 0.2556, -0.228),
				color = "FFF6EC",
				section = "Tail",
				contact = v(0, -0.36, -0.76), -- the hinge: the deepest point inside both the tail and the body
			},
			{
				name = "TailToast",
				shape = "E",
				size = size(0.06, 0.06, 0.0571),
				attach = { to = "Tail", offset = size(0, 0.124, -0.0805) }, -- 0.045 into the tail, so it stays on it in a squeeze
				contact = v(0, -1, 1), -- its corner toward the tail
				color = "E0A060",
				section = "Tail",
			},
		},
		-- The graham crackers on each side.
		pair({
			name = "CrackerL",
			shape = "B",
			size = size(0.0366, 0.2396, 0.28),
			pos = at(0.158, 0.1371, -0.01),
			color = "DCA466",
			body = true,
		}),
		-- The ears' contact is just under the hinge, inside the body.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0588, 0.0568, 0.0346),
			pos = at(0.0883, 0.2806, 0.0205),
			color = "7E5240",
			section = "EarL",
			contact = v(0.4, -0.6, 0.1),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.catMouth(MOUTH_Y, MOUTH_W),
		Kit.blush2(-0.105 * K, (0.1161 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0785, 0.2656, 0.0189), axis = "X", amp = 0.8, sign = -1, flap = { deg = 15 } }),
		{ Tail = { pivot = at(0, 0.184, -0.137), axis = "X", amp = 1.0, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.7, kRel 36, cRel 8, pitch 1) and flight (frisbee).
	motion = {
		squeeze = { depth = 0.62, widen = 0.7, kRel = 36, cRel = 8, pitch = 1 },
		feel = "mochi",
		flight = { style = "frisbee" },
	},
}

return blueprint
