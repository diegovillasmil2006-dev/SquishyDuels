--!strict
-- Kit: the types and data helpers shared by the blueprint modules of Art/SquishyBlueprints (DESIGN §8.1, §8.2; squishy
-- overhaul spec 2026-10-09 §3.1, §3.2). Shared, data only: requiring it builds nothing. Not a blueprint (init.luau
-- lists the blueprint modules by name, so Kit stays out of the map).
--
-- PartSpec fields (units studs, model space: +Y up, the face looks toward -Z, so x < 0 is the squishy's own left):
--   name      unique within the blueprint ("L"/"R" suffix for mirrored pairs)
--   shape     "E" ellipsoid, "B" box, "W" wedge, "TRI" flat isosceles triangle (two W halves), "RB" rounded box
--   size      Vector3 (E, B, W, RB);  TRI uses w (base width), h (height), t (thickness) instead
--   pos       part centre relative to the pivot (default 0)
--   rot       degrees, CFrame.Angles(rx, ry, rz) order; for face/attach parts applied in the feature's own frame
--   face      F(x, y, embed, side?): placed by the builder's +Z ray through (x, y) against the body parts (§8.1 #6);
--             side "back": the ray runs along -Z from behind and the part is turned 180° (it looks toward +Z)
--   attach    { to = <part name>, offset }: centre at that part's CFrame * offset (its frame, not model space);
--             used for "pupil + (...)" style placements (shines, chocolate pupils, tongues)
--   color     hex "RRGGBB"
--   body      true = a face-ray target (E, B or RB only)
--   rigidity  0-1, resists the part's own stretching in SquishDeformer (default 0)
--   group     optional animation group read by presentation code: "lid" (gift_box lid pop), "jaw" (Rush head chomp)
--   look      the part's role in the face states (§3.2 table): "eye", "eyeArc", "shine", "mouth", "mouthOpen",
--             "cheek", "squishEye", "squishMouth", "tongue", "detail". The squish set (squishEye, squishMouth, tongue)
--             is built hidden (Transparency 1); no look part casts a shadow.
--   section   the name of a hinged section in the blueprint's `sections` map (ears, wings, tails, gills)
--   contact   a point in the part's unit space (half size = 1), e.g. (0, -1, 0) for a straw's bottom, that must stay
--             inside `contactWith` at rest and at every squeeze extreme. Face and attach parts default to their back
--             point (0, 0, 1); every other non-body part of a redesigned toy declares one.
--   contactWith  the part holding the contact point (default: any body part; attach parts: their anchor)
-- Mirrored pairs ("∓x … ±r" in §8.2) are written once as the left part: x, ry, rz, attach offsets and the contact's x
-- flip for the right part; rx does not; names ending in "L" (section, attach anchor, contactWith) become "R".
-- Order matters only for face/attach parts: they are placed in list order after all plain parts, so a face part
-- flagged body (Chocolate squares) is a ray target for the face parts listed after it, and an attach anchor must
-- come before the parts attached to it.
--
-- Blueprint = { version, scale, parts, sections?, motion? }. `scale` is the blueprint's own size factor; the builder
-- multiplies it by the caller's scale.
--   sections  { [name]: Section }: the part turns about `pivot` (blueprint units, model space, inside a body part and
--             inside the section's first part) on `axis`; `amp` is the bounce gain, `sign` its direction (default 1),
--             `maxDeg` the soft limit (default 30), `flap` the flight flap size (degrees) and phase offset.
--   motion    the toy's spring squeeze, feel and flight rows (§4): squeeze { depth, widen, kRel, cRel, pitch? },
--             feel "foam" | "mochi" | "jelly" | "plush", flight { style, amp?, pulse? } (pulse: the peak stretch along
--             travel, Mochi Fox 1.15).
--
-- Face kit v1 (gift box, Rush head, giant pads and the 8 blueprints until their redesign): eyes, blush, giantPad.
-- Face kit v2 (the 14 squishies, §3.1): eyes2, happyEyes, catMouth, smileStrokes, blush2, squishFace. Ink 1B1220 for
-- pupils and line mouths, open mouth 8A2440, tongue FF7F96, blush FF8FA8; one shine per eye at the viewer's upper
-- left (+X, +Y from the pupil). Tongues and shines are attach parts with an explicit -Z offset (>= 0.01 stud at
-- scale 1), never face-placed by their own ray, so they never hide behind or z-fight their mouth or pupil.
--
-- Kit.extremes(motion, axis) -> { { label, S } }: the per-axis squeeze scales a toy's rig can reach (SquishRig.extremes
-- calls it; the contact tests and the Inspect framing read it). See the function.

local Config = require(script.Parent.Parent.Parent.Config)

-- Types

export type Shape = "E" | "B" | "W" | "TRI" | "RB"
export type Look =
	"eye"
	| "eyeArc"
	| "shine"
	| "mouth"
	| "mouthOpen"
	| "cheek"
	| "squishEye"
	| "squishMouth"
	| "tongue"
	| "detail"
export type FacePlacement = { x: number, y: number, embed: number, side: ("front" | "back")? }
export type Attachment = { to: string, offset: Vector3 }
export type PartSpec = {
	name: string,
	shape: Shape,
	color: string,
	size: Vector3?,
	w: number?,
	h: number?,
	t: number?,
	pos: Vector3?,
	rot: Vector3?,
	face: FacePlacement?,
	attach: Attachment?,
	body: boolean?,
	rigidity: number?,
	group: string?,
	look: Look?,
	section: string?,
	contact: Vector3?,
	contactWith: string?,
}
export type Axis = "X" | "Y" | "Z"
export type Section = {
	pivot: Vector3,
	axis: Axis,
	amp: number,
	sign: number?,
	maxDeg: number?,
	flap: { deg: number, phase: number? }?,
}
export type Feel = "foam" | "mochi" | "jelly" | "plush"
export type Motion = {
	squeeze: { depth: number, widen: number, kRel: number, cRel: number, pitch: number? },
	feel: Feel,
	flight: { style: string, amp: number?, pulse: number? },
}
export type Blueprint = {
	version: number,
	scale: number,
	parts: { PartSpec },
	sections: { [string]: Section }?,
	motion: Motion?,
}
export type Extreme = { label: string, S: Vector3 }
export type SquishMouth = { y: number, w: number, tongue: boolean? }

-- Module table

local Kit = {}

-- Constants

-- Face kit v1 (§8.1 #7).
local KIT_PUPIL = Vector3.new(0.15, 0.19, 0.08)
local KIT_PUPIL_EMBED = 0.6
local KIT_SHINE = Vector3.new(0.06, 0.06, 0.03)
local KIT_SHINE_OFFSET = Vector3.new(-0.03, 0.05, -0.04)
local BLUSH = "FF9FB8"
local BLUSH_EMBED = 0.65
Kit.PUPIL_COLOR = "2B1E26"
Kit.WHITE = "FFFFFF"
Kit.MOUTH = "7A2E3E"
Kit.MOUTH_EMBED = 0.6

-- Face kit v2 (§3.1). Sizes are fractions of the eye radius r or the mouth width w (studs at blueprint scale).
Kit.INK = "1B1220"
Kit.MOUTH_OPEN = "8A2440"
Kit.TONGUE = "FF7F96"
Kit.BLUSH2 = "FF8FA8"
local V2_EMBED = 0.55 -- "half-sunk", just past the surface so the centre stays inside the body
local V2_LINE_EMBED = 0.6
local PUPIL2 = Vector3.new(2, 2.32, 1) -- × r (the design's radii r, 1.16r, 0.5r)
local SHINE2 = Vector3.new(0.8, 0.8, 0.36) -- × r
local SHINE2_OFFSET = Vector3.new(0.28, 0.4, -0.4) -- × r, in the pupil's frame: the viewer's upper left, in front
local ARC_STROKE = Vector3.new(1.5, 0.6, 0.45) -- × r, two per happy eye
local ARC_DX, ARC_DY, ARC_DEG = 0.61, -0.1, 35 -- × r; turned so the inner ends meet at the top ("^")
local CAT_STROKE = Vector3.new(0.5, 0.3, 0.2) -- × w; "ω": inner ends lift to the middle cusp
local CAT_DX, CAT_DEG = 0.25, 15
local SMILE_STROKE = Vector3.new(0.56, 0.26, 0.2) -- × w; "‿": outer ends lift
local SMILE_DX, SMILE_DY, SMILE_DEG = 0.25, 0.05, 20
local BLUSH2_SIZE = Vector3.new(2.6, 1.56, 0.44) -- × r
local CHEVRON = Vector3.new(0.6, 1.75, 0.3) -- × eye r: one stroke of a squish-eye chevron
local CHEVRON_DY, CHEVRON_DEG = 0.42, 54.4 -- the design's 0.42r and 0.95 rad
local SQUISH_MOUTH = Vector3.new(1.9, 1.24, 0.5) -- × ow = max(w / 2, 0.9 r)
local SQUISH_TONGUE = Vector3.new(1.1, 0.6, 0.4) -- × ow
local TONGUE_DROP = 0.25 -- × ow below the mouth centre
local TONGUE_FRONT, TONGUE_FRONT_MIN = 0.1, 0.012 -- -Z offset: × ow, at least this many studs

-- The largest feel-jiggle cap (§3.2: the hit boing squash peaks at 0.15, capped at 0.18; release and movement kicks
-- stay under 0.08), used for the jiggle extremes.
Kit.JIGGLE_CAP = 0.18

-- Data helpers

function Kit.v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

function Kit.F(x: number, y: number, embed: number, side: ("front" | "back")?): FacePlacement
	return { x = x, y = y, embed = embed, side = side }
end

local function rightName(name: string): string
	assert(string.sub(name, -1) == "L", `[SD][SquishyBlueprints] a mirrored pair is written as its left part: {name}`)
	return string.sub(name, 1, -2) .. "R"
end

-- "FooL" -> "FooR"; any other name stays (a shared anchor or section).
local function mirrorName(name: string): string
	return if string.sub(name, -1) == "L" then rightName(name) else name
end

local function mirrorX(vector: Vector3): Vector3
	return Vector3.new(-vector.X, vector.Y, vector.Z)
end

-- { left, right } from the left part (see the header for what flips).
function Kit.pair(left: PartSpec): { PartSpec }
	local right = table.clone(left)
	right.name = rightName(left.name)
	if left.pos then
		right.pos = mirrorX(left.pos)
	end
	if left.rot then
		right.rot = Vector3.new(left.rot.X, -left.rot.Y, -left.rot.Z)
	end
	if left.face then
		right.face = Kit.F(-left.face.x, left.face.y, left.face.embed, left.face.side)
	end
	if left.attach then
		right.attach = { to = mirrorName(left.attach.to), offset = mirrorX(left.attach.offset) }
	end
	if left.section then
		right.section = mirrorName(left.section)
	end
	if left.contact then
		right.contact = mirrorX(left.contact)
	end
	if left.contactWith then
		right.contactWith = mirrorName(left.contactWith)
	end
	return { left, right }
end

-- { [name] = left, [name with "R"] = right }: the right section's pivot x flips, and its sign flips for Y and Z axes
-- (a mirror across x keeps a turn about X and reverses turns about Y and Z, as pair() does with rot).
function Kit.pairSection(name: string, left: Section): { [string]: Section }
	local right = table.clone(left)
	right.pivot = mirrorX(left.pivot)
	if left.axis ~= "X" then
		right.sign = -(left.sign or 1)
	end
	return { [name] = left, [rightName(name)] = right }
end

-- Merges section maps (pairSection results and single sections) into one; a name may appear once.
function Kit.mergeSections(...: { [string]: Section }): { [string]: Section }
	local out: { [string]: Section } = {}
	for i = 1, select("#", ...) do
		local map: { [string]: Section } = select(i, ...)
		for name, section in map do
			assert(out[name] == nil, `[SD][SquishyBlueprints] section {name} is listed twice`)
			out[name] = section
		end
	end
	return out
end

function Kit.concat(...: { PartSpec }): { PartSpec }
	local out: { PartSpec } = {}
	for i = 1, select("#", ...) do
		local list: { PartSpec } = select(i, ...)
		for _, spec in list do
			table.insert(out, spec)
		end
	end
	return out
end

-- Face kit v1 ---------------------------------------------------------------------------------------------------------

-- Kit eyes: pupils EyeL/EyeR at F(±x, y, 0.6) (x = the left eye's x, negative) and their shines (default offset:
-- the kit's; the same offset on both eyes: one light).
function Kit.eyes(x: number, y: number, pupil: Vector3?, shineOffset: Vector3?): { PartSpec }
	local size = pupil or KIT_PUPIL
	local offset = shineOffset or KIT_SHINE_OFFSET
	return {
		{ name = "EyeL", shape = "E", size = size, face = Kit.F(x, y, KIT_PUPIL_EMBED), color = Kit.PUPIL_COLOR },
		{ name = "EyeR", shape = "E", size = size, face = Kit.F(-x, y, KIT_PUPIL_EMBED), color = Kit.PUPIL_COLOR },
		{
			name = "ShineL",
			shape = "E",
			size = KIT_SHINE,
			attach = { to = "EyeL", offset = offset },
			color = Kit.WHITE,
		},
		{
			name = "ShineR",
			shape = "E",
			size = KIT_SHINE,
			attach = { to = "EyeR", offset = offset },
			color = Kit.WHITE,
		},
	}
end

function Kit.blush(x: number, y: number, size: Vector3): { PartSpec }
	return Kit.pair({ name = "BlushL", shape = "E", size = size, face = Kit.F(x, y, BLUSH_EMBED), color = BLUSH })
end

-- Giant squishy pads (§17.6, §17.6.1): giant_jelly, giant_marshmallow, giant_cushion (the Royal Cushion). Placeholder
-- design (§17.11 names them; §8.2 has no table): a Body RB of the pad's footprint × rest top from
-- World/WorldLayout.GiantPads (8 × 1.5 × 8, 8 × 1.6 × 8, 9 × 1.7 × 9 studs at scale 1) and the §8.1 #7 face kit made
-- giant: 8 parts + Root. The lobby generator uses ONLY the face parts: it builds each pad's Body itself (rounded base +
-- quilted path B tiles), stands this blueprint's lowest point on the floor and moves the face parts onto the side
-- that looks toward the pad's faceDirection. The face sits on the lower half of the side (eyes at 0.42 × rest top
-- above the floor), under the widest bulge of the quilted tiles, and stands out of the flat side by 0.4 (eyes),
-- 0.24 (mouth) and 0.14 (blush) so the tiles never hide it.
local GIANT_EYE = Vector3.new(0.5, 0.62, 1.0)
local GIANT_EYE_X = -1.1 -- the left eye (§8.2 convention: x < 0 is the squishy's own left)
local GIANT_SHINE_OFFSET = Vector3.new(-0.1, 0.14, -0.38) -- on the eye's front, up and to its left
local GIANT_SHINE = Vector3.new(0.16, 0.16, 0.1)
local GIANT_MOUTH = Vector3.new(0.42, 0.22, 0.6)
local GIANT_MOUTH_DROP = 0.32 -- below the eye centre
local GIANT_BLUSH = Vector3.new(0.6, 0.26, 0.4)
local GIANT_BLUSH_X = -1.95
local GIANT_BLUSH_DROP = 0.25
local GIANT_EYE_HEIGHT = 0.42 -- eye centre above the floor, as a fraction of the rest top

function Kit.giantPad(footprint: number, restTop: number, bodyColor: string): Blueprint
	-- Model space is centred on the Body, so the floor is at -restTop / 2.
	local eyeY = GIANT_EYE_HEIGHT * restTop - restTop / 2
	local eyes = {
		{
			name = "EyeL",
			shape = "E",
			size = GIANT_EYE,
			face = Kit.F(GIANT_EYE_X, eyeY, KIT_PUPIL_EMBED),
			color = Kit.PUPIL_COLOR,
		},
		{
			name = "EyeR",
			shape = "E",
			size = GIANT_EYE,
			face = Kit.F(-GIANT_EYE_X, eyeY, KIT_PUPIL_EMBED),
			color = Kit.PUPIL_COLOR,
		},
		{
			name = "ShineL",
			shape = "E",
			size = GIANT_SHINE,
			attach = { to = "EyeL", offset = GIANT_SHINE_OFFSET },
			color = Kit.WHITE,
		},
		{
			name = "ShineR",
			shape = "E",
			size = GIANT_SHINE,
			attach = { to = "EyeR", offset = GIANT_SHINE_OFFSET },
			color = Kit.WHITE,
		},
	} :: { PartSpec }
	return {
		version = 1,
		scale = 1,
		parts = Kit.concat(
			{
				{
					name = "Body",
					shape = "RB",
					size = Vector3.new(footprint, restTop, footprint),
					color = bodyColor,
					body = true,
				},
			},
			eyes,
			{
				{
					name = "Mouth",
					shape = "E",
					size = GIANT_MOUTH,
					face = Kit.F(0, eyeY - GIANT_MOUTH_DROP, Kit.MOUTH_EMBED),
					color = Kit.MOUTH,
				},
			},
			Kit.blush(GIANT_BLUSH_X, eyeY - GIANT_BLUSH_DROP, GIANT_BLUSH)
		),
	}
end

-- Face kit v2 ---------------------------------------------------------------------------------------------------------
-- x is the left eye's x (negative), r the eye radius, w a mouth's full width; mouths are centred (x = 0).

-- Pupils EyeL/EyeR (look "eye", 2r × 2.32r × r, half-sunk) and one shine each (look "shine", attached in front at the
-- viewer's upper left).
function Kit.eyes2(x: number, y: number, r: number): { PartSpec }
	local out: { PartSpec } = {}
	for _, side in { "L", "R" } do
		local ex = if side == "L" then x else -x
		table.insert(out, {
			name = "Eye" .. side,
			shape = "E",
			size = PUPIL2 * r,
			face = Kit.F(ex, y, V2_EMBED),
			color = Kit.INK,
			look = "eye",
		})
	end
	for _, side in { "L", "R" } do
		table.insert(out, {
			name = "Shine" .. side,
			shape = "E",
			size = SHINE2 * r,
			attach = { to = "Eye" .. side, offset = SHINE2_OFFSET * r },
			color = Kit.WHITE,
			look = "shine",
		})
	end
	return out
end

-- Happy "^" eyes (Mochi Fox): per eye two E strokes (look "eyeArc", no blink), the inner ends meeting at the top.
function Kit.happyEyes(x: number, y: number, r: number): { PartSpec }
	local function stroke(name: string, dx: number): PartSpec
		return {
			name = name,
			shape = "E",
			size = ARC_STROKE * r,
			face = Kit.F(x + dx * r, y + ARC_DY * r, V2_LINE_EMBED),
			rot = Vector3.new(0, 0, if dx > 0 then -ARC_DEG else ARC_DEG),
			color = Kit.INK,
			look = "eyeArc",
		}
	end
	return Kit.concat(Kit.pair(stroke("EyeArcOutL", -ARC_DX)), Kit.pair(stroke("EyeArcInL", ARC_DX)))
end

-- A cat "ω" mouth: two E strokes MouthL/MouthR (look "mouth") whose inner ends lift to the middle cusp.
function Kit.catMouth(y: number, w: number): { PartSpec }
	return Kit.pair({
		name = "MouthL",
		shape = "E",
		size = CAT_STROKE * w,
		face = Kit.F(-CAT_DX * w, y, V2_LINE_EMBED),
		rot = Vector3.new(0, 0, CAT_DEG),
		color = Kit.INK,
		look = "mouth",
	})
end

-- A smile "‿": two E strokes MouthL/MouthR (look "mouth") at ∓20° whose outer ends lift.
function Kit.smileStrokes(y: number, w: number): { PartSpec }
	return Kit.pair({
		name = "MouthL",
		shape = "E",
		size = SMILE_STROKE * w,
		face = Kit.F(-SMILE_DX * w, y + SMILE_DY * w, V2_LINE_EMBED),
		rot = Vector3.new(0, 0, -SMILE_DEG),
		color = Kit.INK,
		look = "mouth",
	})
end

-- Cheeks BlushL/BlushR (look "cheek", 2.6r × 1.56r × 0.44r) at F(±x, y).
function Kit.blush2(x: number, y: number, r: number): { PartSpec }
	return Kit.pair({
		name = "BlushL",
		shape = "E",
		size = BLUSH2_SIZE * r,
		face = Kit.F(x, y, V2_LINE_EMBED),
		color = Kit.BLUSH2,
		look = "cheek",
	})
end

-- The hidden squish set (§3.1): per eye a "> <" chevron of 2 thin E strokes (look "squishEye", 0.6r × 1.75r × 0.3r,
-- ±54°, the point toward the face centre) at the eye; with `mouth` an open mouth SquishMouth (look "squishMouth",
-- 1.9 × 1.24 × 0.5 of ow = max(mouth.w / 2, 0.9r)) at F(0, mouth.y) and, unless mouth.tongue == false, a tongue
-- SquishTongue (look "tongue") attached in front of it. 6 parts; 4 without a mouth (Birdie, Butter), 5 without the
-- tongue (Donut and Dragon at the 31-part cap).
function Kit.squishFace(x: number, y: number, r: number, mouth: SquishMouth?): { PartSpec }
	local function stroke(name: string, dy: number, deg: number): PartSpec
		return {
			name = name,
			shape = "E",
			size = CHEVRON * r,
			face = Kit.F(x, y + dy * r, V2_EMBED),
			rot = Vector3.new(0, 0, deg),
			color = Kit.INK,
			look = "squishEye",
		}
	end
	-- Left eye (x < 0): the upper stroke's top end leans outward (-X), so the point faces the centre (+X).
	local out = Kit.concat(
		Kit.pair(stroke("SquishEyeUpL", CHEVRON_DY, CHEVRON_DEG)),
		Kit.pair(stroke("SquishEyeDownL", -CHEVRON_DY, -CHEVRON_DEG))
	)
	if mouth then
		local ow = math.max(mouth.w / 2, 0.9 * r)
		table.insert(out, {
			name = "SquishMouth",
			shape = "E",
			size = SQUISH_MOUTH * ow,
			face = Kit.F(0, mouth.y, V2_EMBED),
			color = Kit.MOUTH_OPEN,
			look = "squishMouth",
		})
		if mouth.tongue ~= false then
			table.insert(out, {
				name = "SquishTongue",
				shape = "E",
				size = SQUISH_TONGUE * ow,
				attach = {
					to = "SquishMouth",
					offset = Vector3.new(0, -TONGUE_DROP * ow, -math.max(TONGUE_FRONT * ow, TONGUE_FRONT_MIN)),
				},
				color = Kit.TONGUE,
				look = "tongue",
			})
		end
	end
	return out
end

-- Squeeze extremes ----------------------------------------------------------------------------------------------------

local function axisScale(c: number, w: number, axis: Axis): Vector3
	local lo, hi = Config.Anim.deform.scaleMin, Config.Anim.deform.scaleMax
	local along, across = math.clamp(c, lo, hi), math.clamp(w, lo, hi)
	if axis == "X" then
		return Vector3.new(along, across, across)
	elseif axis == "Y" then
		return Vector3.new(across, along, across)
	end
	return Vector3.new(across, across, along)
end

-- The squeeze shapes a toy's rig can reach (§3.2), as per-axis scales S (the squeeze axis gets c, the other two w),
-- clamped to Config.Anim.deform.scaleMin..scaleMax like the deformer:
--   "rest" (1, 1, 1);
--   one per Config.Anim.squeeze.phases keyframe (the single source), scaled to the toy:
--     c' = 1 - (1 - c)(1 - depth) / (1 - deepest c), w = 1 + (1 - c') widen, so the deepest phase reaches depth;
--   "overshoot": the release spring's first overshoot from full depth (ω = √kRel, ζ = cRel / (2ω); the §4 upper
--     bound), when ζ < 1;
--   "jiggleSquash" / "jiggleStretch": the feel jiggle at Kit.JIGGLE_CAP, c = 1 ∓ cap, w = 1 ± cap / 2.
-- The widest w is the press depth's 1 + (1 - depth) widen (the jiggle caps stay below it).
function Kit.extremes(motion: Motion, axis: Axis): { Extreme }
	local squeeze = motion.squeeze
	local phases = Config.Anim.squeeze.phases
	local deepest = math.huge
	for _, phase in phases do
		deepest = math.min(deepest, phase.c)
	end
	local function toyC(c: number): number
		return 1 - (1 - c) * (1 - squeeze.depth) / (1 - deepest)
	end
	local function width(c: number): number
		return 1 + (1 - c) * squeeze.widen
	end
	local out: { Extreme } = { { label = "rest", S = Vector3.one } }
	for _, phase in phases do
		local c = toyC(phase.c)
		table.insert(out, { label = phase.name, S = axisScale(c, width(c), axis) })
	end
	local omega = math.sqrt(squeeze.kRel)
	local zeta = squeeze.cRel / (2 * omega)
	if zeta < 1 then
		local c = 1 + (1 - squeeze.depth) * math.exp(-math.pi * zeta / math.sqrt(1 - zeta * zeta))
		table.insert(out, { label = "overshoot", S = axisScale(c, width(c), axis) })
	end
	local cap = Kit.JIGGLE_CAP
	table.insert(out, { label = "jiggleSquash", S = axisScale(1 - cap, 1 + cap / 2, axis) })
	table.insert(out, { label = "jiggleStretch", S = axisScale(1 + cap, 1 - cap / 2, axis) })
	return out
end

return Kit
