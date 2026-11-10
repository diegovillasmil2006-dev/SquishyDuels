--!strict
-- Cayenne Kiwi (Uncommon, Lava Box, 2026-11-10): Claude Design's CayenneKiwi ("Squishies 50 Lineup",
-- sd/toys2.js:405-426) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes); this
-- is the fallback and the size, sections and motion every view reads. A fuzzy red-hot kiwi bird, peachy underneath, a
-- long beak, little feet, a chili-pepper cap with its stem that flicks (section Cap), a flame tuft behind that flicks
-- (section Flame), eyes, no mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, concat = Kit.v, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (its longest side about 1.6 studs, the hand's
-- 1.5-1.7 like its siblings), turned 180° about Y and re-based on the body's middle (design y = Y0, the slot model's
-- pivot).
local K, Y0 = 3.05, 0.15
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.042, dx 0.07, eyeR 0.019 × 1.22, no mouth, blush 0.112 / 0.014).
local EYE_X, EYE_Y, EYE_R = -0.07 * K, (0.182 - Y0) * K, 0.0232 * K

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Body",
				shape = "E",
				size = size(0.3387, 0.3, 0.3747),
				pos = at(0, 0.15, 0),
				color = "EE6A45",
				body = true,
			},
			-- The peachy front and belly (the design fades the red to peach low on the front).
			{
				name = "Belly",
				shape = "E",
				size = size(0.22, 0.16, 0.2),
				pos = at(0, 0.09, 0.09),
				color = "FFB884",
				body = true,
			},
			-- The beak leans down from the face; its back end is inside the body.
			{
				name = "Beak",
				shape = "E",
				size = size(0.0333, 0.0689, 0.1119),
				pos = at(0, 0.1152, 0.2304),
				color = "FFE2A8",
				contact = v(0, 0.2, 0.9),
			},
			{
				name = "Feet",
				shape = "E",
				size = size(0.184, 0.024, 0.0839),
				pos = at(0, 0.022, 0.0956),
				color = "F2A65A",
				contact = v(0, 0.9, 0.4),
			},
			-- The chili cap sits on the head top; its contact is the hinge, just inside the body.
			{
				name = "Cap",
				shape = "E",
				size = size(0.1054, 0.0307, 0.1051),
				pos = at(0, 0.2893, -0.0188),
				color = "5DB861",
				section = "Cap",
				contact = v(0, -0.8, 0),
			},
			{
				name = "CapStem",
				shape = "E",
				size = size(0.0307, 0.0549, 0.0307),
				attach = { to = "Cap", offset = size(-0.0081, 0.0266, 0.0076) },
				contact = v(0, -0.9, 0), -- its foot in the cap
				color = "4FA650",
				section = "Cap",
			},
			-- The flame tuft leans back from the body's back: its contact is the hinge, inside the body.
			{
				name = "Flame",
				shape = "E",
				size = size(0.0411, 0.0809, 0.0706),
				pos = at(0, 0.2073, -0.198), -- 0.005 into the back so its base overlaps the body
				color = "FFC24A",
				section = "Flame",
				contact = v(0, -0.4, -0.85),
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.blush2(-0.112 * K, (0.168 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = {
		Cap = { pivot = at(0, 0.2911, -0.0194), axis = "X", amp = 0.9, sign = -1, flap = { deg = 12 } },
		Flame = { pivot = at(0, 0.1911, -0.168), axis = "X", amp = 1.3, sign = -1, flap = { deg = 15 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 50, cRel 7.5, pitch 1.35) and flight (hop).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 50, cRel = 7.5, pitch = 1.35 },
		feel = "plush",
		flight = { style = "hop" },
	},
}

return blueprint
