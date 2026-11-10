--!strict
-- Cinder Bun (Common, Lava Box, 2026-11-10): Claude Design's CinderBun ("Squishies 50 Lineup", sd/toys2.js:361-380) in E
-- parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this is the fallback and the
-- size, sections and motion every view reads. A worried, over-toasted bun (Kitty Bread's cousin): a toasted crust top,
-- pointy ears that wobble (sections EarL/EarR), a smoke curl that wobbles (section Smoke), a sweat drop, paws, dot eyes,
-- a small open mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, pair, concat = Kit.v, Kit.F, Kit.pair, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the bun's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 4.6, 0.1124
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0, dx 0.07, eyeR 0.021 × 1.22 dot eyes, open mouth mw 0.014 at 0.045 below, blush 0.12).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.0959 - Y0) * K, 0.0256 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Bun",
				shape = "E",
				size = size(0.34, 0.2247, 0.3188),
				pos = at(0, 0.1124, 0),
				color = "F6CE94",
				body = true,
			},
			-- The toasted top (the design darkens the dough by height).
			{
				name = "Crust",
				shape = "E",
				size = size(0.33, 0.13, 0.31),
				pos = at(0, 0.165, 0),
				color = "C9844A",
				body = true,
			},
			{
				name = "SweatDrop",
				shape = "E",
				size = size(0.0205, 0.0321, 0.0199),
				face = F(-0.1309 * K, (0.1536 - Y0) * K, 0.5),
				color = "9ED8FF",
				look = "detail",
			},
			-- The smoke curl's contact is its hinge, just inside the bun's top.
			{
				name = "Smoke",
				shape = "E",
				size = size(0.0562, 0.0882, 0.0549),
				pos = at(-0.0532, 0.2485, -0.0812),
				color = "E9E4EE",
				section = "Smoke",
				contact = v(-0.12, -0.83, -0.41),
			},
		},
		-- The ears' contact is just under the hinge, inside the bun.
		pair({
			name = "EarL",
			shape = "E",
			size = size(0.0938, 0.096, 0.0619),
			pos = at(0.1145, 0.1967, 0.0094),
			color = "B86F3F",
			section = "EarL",
			contact = v(0.45, -0.55, 0),
		}),
		pair({
			name = "InnerEarL",
			shape = "E",
			size = size(0.06, 0.0588, 0.03),
			attach = { to = "EarL", offset = size(0, 0.0023, -0.018) },
			color = "F2A08E",
			section = "EarL",
		}),
		pair({
			name = "PawL",
			shape = "E",
			size = size(0.0635, 0.0511, 0.0575),
			pos = at(0.0716, 0.041, 0.1237),
			color = "FCE6C6",
			contact = v(0.3, 0.5, 1),
		}),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		{
			{
				name = "Mouth",
				shape = "E",
				size = size(0.0233, 0.0177, 0.0097),
				face = F(0, (0.0515 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0149, 0.009, 0.0067),
				attach = { to = "Mouth", offset = size(0, -0.004, -0.003) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		Kit.blush2(-0.12 * K, (0.0679 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = Kit.mergeSections(
		Kit.pairSection("EarL", { pivot = at(0.0977, 0.1887, 0.0094), axis = "X", amp = 0.9, sign = -1, flap = { deg = 15 } }),
		{ Smoke = { pivot = at(-0.0497, 0.2117, -0.0699), axis = "Z", amp = 1.2, sign = -1, flap = { deg = 12 } } }
	),
	-- The design's CATALOG2 squeeze (depth 0.6, widen 0.74, kRel 30, cRel 8.5, pitch 0.95) and flight (tumble).
	motion = {
		squeeze = { depth = 0.6, widen = 0.74, kRel = 30, cRel = 8.5, pitch = 0.95 },
		feel = "foam",
		flight = { style = "tumble" },
	},
}

return blueprint
