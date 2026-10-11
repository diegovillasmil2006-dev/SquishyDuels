--!strict
-- Donut (Epic; 3D Lab redesign, spec 2026-10-09 §4): 30 parts + Root, 6 hidden squish-face parts, no sections. An
-- upright ring with a fatter, thinner-front-to-back tube and a smaller hole, a pink icing ring on the front only, 4
-- sprinkles on the upper half and the face low on the ring (face kit v2). No cheeks: the blush colour is the icing's
-- pink, so they would not show, and they would put the ring over the 31-part cap. Fry lines and drips are lost.
-- Authored in design studs (the 3D Lab's metres / 0.28, turned to face -Z, centred on the hole); `scale` fits the hand.
-- The ring is 10 dough + 10 icing segments (the 2026-10-05 play-check found 8 looked like beads): size X = tangent,
-- Y = radial after rz α+90; each segment is 2.5 steps long, so neighbours overlap a lot and the ring reads smooth.
-- The deformer is one exact linear map only for parts that are axis-aligned or turned about the squeeze axis; the ring
-- segments (rz α+90, squeezed on Y) are neither, so the sprinkles are 0.06 deep with embed 0.8: the visible 0.012
-- sticks out of the icing while the back half stays in it when the ring squeezes.

local Kit = require(script.Parent.Kit)

local v, F, concat = Kit.v, Kit.F, Kit.concat

type PartSpec = Kit.PartSpec

local RING_RADIUS = 0.60
local RING_SEGMENTS = 10
local RING_STEP = 360 / RING_SEGMENTS
local DOUGH = v(0.95, 0.64, 0.515)
local ICING = v(0.90, 0.58, 0.38) -- a front shell: it covers the dough's front, the dough shows at the edges
local ICING_Z = -0.085
local EYE_X, EYE_Y, EYE_R = -0.221, -0.543, 0.0915
local MOUTH_Y, MOUTH_W = -0.686, 0.159

local function ring(name: string, size: Vector3, z: number, color: string): { PartSpec }
	local out: { PartSpec } = {}
	for i = 0, RING_SEGMENTS - 1 do
		local alpha = i * RING_STEP
		local c, s = math.cos(math.rad(alpha)), math.sin(math.rad(alpha))
		local segment: PartSpec = {
			name = `{name}{i + 1}`,
			shape = "E",
			size = size,
			pos = v(RING_RADIUS * c, RING_RADIUS * s, z),
			rot = v(0, 0, alpha + 90),
			color = color,
			body = true,
		}
		table.insert(out, segment)
	end
	return out
end

-- Sprinkles on the upper half of the icing, clear of the face: α, radial offset from the ring radius, rz, colour.
local SPRINKLE_SIZE = Vector3.new(0.15, 0.05, 0.06)
local SPRINKLE_EMBED = 0.8

local function sprinkles(): { PartSpec }
	local rows = {
		{ alpha = 20, radial = 0.08, rz = 35, color = "FFFFFF" },
		{ alpha = 68, radial = -0.08, rz = -20, color = "6EC6F5" },
		{ alpha = 115, radial = 0.08, rz = 70, color = "FFD54A" },
		{ alpha = 162, radial = -0.07, rz = -45, color = "7EDDB5" },
	}
	local out: { PartSpec } = {}
	for i, row in rows do
		local r = RING_RADIUS + row.radial
		local a = math.rad(row.alpha)
		local sprinkle: PartSpec = {
			name = `Sprinkle{i}`,
			shape = "E",
			size = SPRINKLE_SIZE,
			face = F(r * math.cos(a), r * math.sin(a), SPRINKLE_EMBED),
			rot = v(0, 0, row.rz),
			color = row.color,
			look = "detail",
		}
		table.insert(out, sprinkle)
	end
	return out
end

local blueprint: Kit.Blueprint = {
	version = 2,
	scale = 0.84,
	parts = concat(
		ring("Dough", DOUGH, 0, "E6A35E"),
		ring("Icing", ICING, ICING_Z, "F68FB4"),
		sprinkles(),
		Kit.eyes2(EYE_X, EYE_Y, EYE_R),
		Kit.smileStrokes(MOUTH_Y, MOUTH_W),
		Kit.squishFace(EYE_X, EYE_Y, EYE_R, { y = MOUTH_Y, w = MOUTH_W })
	),
	-- §4 row (spec 2026-10-09).
	motion = {
		squeeze = { depth = 0.66, widen = 0.62, kRel = 46, cRel = 8.5, pitch = 1.05 },
		feel = "foam",
		flight = { style = "wheel" },
	},
}

return blueprint
