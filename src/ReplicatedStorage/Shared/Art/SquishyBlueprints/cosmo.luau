--!strict
-- Cosmo (Exclusive, shown Legendary; Series 01, 2026-11-10): Claude Design's Cosmo ("Squishies 50 Lineup",
-- sd/toys2.js) in E parts. Its real look is its ReplicatedStorage.SD_Models slot (the design's own meshes: the torus
-- ring, the beads); this is the fallback and the size, sections and motion every view reads. A galaxy-gel planet, a
-- tilted ring that tilts against the squeeze (section Ring, here a flat disc without the moons), a star antenna that boings
-- (section Antenna), big eyes, an open mouth, cheeks.

local Kit = require(script.Parent.Kit)

local v, F, concat = Kit.v, Kit.F, Kit.concat

-- Design metres (the export's frame, face +Z) to studs: K studs a metre (this look's ring disc, 0.72 wide, about 1.75
-- studs, a little bigger than the Commons like the Dragon), turned 180° about Y and re-based on the body's middle
-- (design y = Y0, the slot model's pivot).
local K, Y0 = 2.43, 0.191
local function at(x: number, y: number, z: number): Vector3
	return v(-x * K, (y - Y0) * K, -z * K)
end
local function size(x: number, y: number, z: number): Vector3
	return v(x * K, y * K, z * K)
end

-- Face (design face(): y 0.01, dx 0.082, eyeR 0.026 × 1.22 big eyes, open mouth mw 0.022 at 0.046 below, blush 0.135).
local EYE_X, EYE_Y, EYE_R = -0.082 * K, (0.1921 - Y0) * K, 0.0317 * K
-- The ring: the design's torus R 0.305 in a plane tilted 0.32 rad toward the front and 0.12 rad about Z.
local RING_ROT = v(-18.3, 0, -6.9)

local blueprint: Kit.Blueprint = {
	version = 1,
	scale = 1,
	parts = concat(
		{
			{
				name = "Planet",
				shape = "E",
				size = size(0.41, 0.3821, 0.39),
				pos = at(0, 0.191, 0),
				color = "C9D2FF",
				body = true,
			},
			{
				name = "Ring",
				shape = "E",
				-- Wider and thicker than the design's torus line (0.61 wide), so the moons on it stay inside the disc
				-- through every squeeze, tilted or not.
				size = size(0.72, 0.16, 0.72),
				pos = at(0, 0.1821, 0),
				rot = RING_ROT,
				color = "FFE7A6",
				section = "Ring",
				-- No rigidity here (the real model's ring has SD_Rigidity 0.6): a stiff disc would leave its moons behind
				-- as the squeeze moves them.
				contact = v(0, 0, 0), -- its middle is the planet's
			},
			-- No moons in this look: far out on the ring, a turned and squeezed disc leaves them behind (the real model
			-- has them as its own ring pieces).
			-- The stalk runs from the hinge (inside the planet) up to the star's middle, leaning 41° to the toy's right.
			{
				name = "Antenna",
				shape = "E",
				size = size(0.05, 0.19, 0.05), -- longer and thicker than the design's stalk: the star's middle stays inside
				pos = at(0.059, 0.405, -0.0189),
				rot = v(0, 0, 41),
				color = "C7A0FF",
				section = "Antenna",
				contact = v(0, -0.8, 0),
			},
			-- The star sits on the stalk's line near its top, held at its middle.
			{
				name = "Star",
				shape = "E",
				size = size(0.1, 0.0997, 0.0408),
				attach = { to = "Antenna", offset = size(0, 0.06, 0) },
				rot = v(0, 0, -41),
				color = "FFE27A",
				section = "Antenna",
				contact = v(0, 0, 0),
				contactWith = "Antenna",
			},
		},
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		{
			{
				name = "Mouth",
				shape = "E",
				size = size(0.0366, 0.0288, 0.0132),
				face = F(0, (0.1464 - Y0) * K, 0.6),
				color = Kit.MOUTH_OPEN,
				look = "mouthOpen",
			},
			{
				name = "Tongue",
				shape = "E",
				size = size(0.0234, 0.0145, 0.01),
				attach = { to = "Mouth", offset = size(0, -0.0063, -0.003) },
				color = Kit.TONGUE,
				look = "mouthOpen",
			},
		},
		Kit.blush2(-0.135 * K, (0.1621 - Y0) * K, 0.0205 * K),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R)
	),
	sections = {
		-- The ring wraps the body, so its tilt is held to 15° to limit clipping.
		Ring = { pivot = at(0, 0.1821, 0), axis = "Z", amp = 0.6, sign = -1, maxDeg = 15 },
		Antenna = { pivot = at(0.0284, 0.369, -0.0189), axis = "X", amp = 1.2, sign = -1, flap = { deg = 15 } },
	},
	-- The design's CATALOG2 squeeze (depth 0.62, widen 0.66, kRel 44, cRel 7, pitch 1.1) and flight (spiral).
	motion = {
		squeeze = { depth = 0.62, widen = 0.66, kRel = 44, cRel = 7, pitch = 1.1 },
		feel = "jelly",
		flight = { style = "spiral" },
	},
}

return blueprint
