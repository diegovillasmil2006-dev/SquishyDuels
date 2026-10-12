--!strict
-- InspectTracks (client only, pure): the 14 first-person Inspect showcases (final polish 2026-10-11; the user moved
-- them to the final polish, FP spec answer 5). The 3D Lab's INS table verbatim (design: sd/fp.js:111-142), keyed by
-- Catalog id (the design's id in each comment), and its event recipes vEv (fp.js:158-194), in du, camera space (-Z
-- forward, +Y up, +X right; the overlay draws them × overlayStudsPerDu). ViewmodelController plays them; no instances,
-- connections or clock reads: the caller passes every time.
-- Rows are the design's (fp.js:112: P0 = the hold, HF = both hands on the toy):
--   toy   [t, x, y, z, rx, ry, rz]: x, y, z added to the hold point; rx, ry, rz the toy's rotation (replaces the hold's)
--         (fp.js:408-409)
--   hands [t, blend, lx, ly, lz, rx, ry, rz]: each hand is (REST + its offset) lerped to the toy's side (+ the same
--         offset) by the blend (fp.js:410)
--   sq    [t, sx, sy, sz]: the toy's scale keys (fp.js:409), where the design has them
--   events [t, name]: each fires once when t passes its time (fp.js:411); its recipe (recipe(name)) is vEv's
-- Each segment is eased cosine in-out (design: fp.js:13, 19); the values are targets for the overlay's springs. At dur
-- the hold comes back with the rotation spring wrapped into (-π, π] (wrap, the design's wrapRot, fp.js:109, 412).
-- Recipes (fp.js:169-194): `sound` is an AssetTable key (the design's own one-shots in sfx.inspect.*, PENDING until
-- uploaded; the squeeze's material sounds sfx.squish / sfx.squeezeRelease at the toy's pitch for pat / plop / snapback,
-- sfx.pop for the hop and sfx.dragonRoar for the roar, the slots that already hold those design sounds); `kick` is
-- the design's Squisher.kick(v) (toys.js:442: v on its squash spring's speed); `shake` the camera shake value;
-- `specks` the design's particle call (Anim/Specks).
--
-- API
--   InspectTracks.ids() -> { string }              the 14 Catalog ids with a showcase, sorted
--   InspectTracks.get(squishyId) -> Track?          one showcase (frozen)
--   InspectTracks.toyAt(track, t) -> (Vector3, Vector3)   the toy's offset (du) and rotation (rx, ry, rz) at t
--   InspectTracks.handsAt(track, t, sideL, sideR, restL, restR) -> (Vector3, Vector3)   the left and right hand
--       targets at t; sideL / sideR are the hands at the toy's sides now (ViewmodelMath.sides), restL / restR the
--       empty hands (Config.FirstPerson.rest, X × side)
--   InspectTracks.scaleAt(track, t) -> Vector3     the toy's scale keys at t; (1, 1, 1) without them
--   InspectTracks.firedBy(track, t) -> number      how many of its events are due at t (they are in time order)
--   InspectTracks.wrap(rot) -> Vector3             each angle into (-π, π] (fp.js:109)
--   InspectTracks.recipe(name) -> Recipe?          an event's recipe
--   InspectTracks.squashScale(y, widen) -> Vector3   the design's squash node (w, y, w), w = 1 + (1 - y)·widen
--       (toys.js:454-455): what a kick shows on the toy

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Palette = require(ReplicatedStorage.Shared.Art.Palette)
local Specks = require(script.Parent.Specks)

-- Types

export type Row = { number }
export type Event = { t: number, name: string }
export type Track = {
	name: string, -- the design's toy id (its INS key)
	dur: number,
	toy: { Row },
	hands: { Row },
	sq: { Row }?,
	events: { Event },
}
export type Recipe = {
	sound: string,
	pitched: boolean?, -- at the toy's squeeze pitch (the material sounds)
	kick: number?,
	shake: number?,
	specks: Specks.Spec?,
}

-- Constants

local TAU = 2 * math.pi
local PI = math.pi

-- Module table

local InspectTracks = {}

-- Private

local function ease(u: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(u, 0, 1)) -- design: fp.js:13
end

-- Row i's three values from column `from`.
local function triple(row: Row, from: number): Vector3
	return Vector3.new(row[from], row[from + 1], row[from + 2])
end

-- The design's kv (fp.js:19): the two rows around t and the eased share between them (row 1 before it, the last row
-- after the end).
local function kv(rows: { Row }, t: number): (Row, Row, number)
	if t <= rows[1][1] then
		return rows[1], rows[1], 0
	end
	for i = 1, #rows - 1 do
		local b = rows[i + 1]
		if t <= b[1] then
			local a = rows[i]
			return a, b, ease((t - a[1]) / (b[1] - a[1]))
		end
	end
	local last = rows[#rows]
	return last, last, 0
end

local function lerp3(a: Row, b: Row, u: number, from: number): Vector3
	return triple(a, from):Lerp(triple(b, from), u)
end

local function wrapAngle(x: number): number
	local r = x % TAU -- Luau: floored, so 0 <= r < 2π
	return if r > PI then r - TAU else r
end

-- One event: [t, name] (design: fp.js:113-141, `ev`).
local function at(t: number, name: string): Event
	return table.freeze({ t = t, name = name })
end

local function track(name: string, data: any): Track
	local events: { Event } = data.ev
	local function freezeRows(rows: { Row }?): { Row }?
		if rows == nil then
			return nil
		end
		for _, row in rows do
			table.freeze(row)
		end
		return table.freeze(rows)
	end
	return table.freeze({
		name = name,
		dur = data.dur,
		toy = freezeRows(data.toy) :: { Row },
		hands = freezeRows(data.hands) :: { Row },
		sq = freezeRows(data.sq),
		events = table.freeze(events),
	})
end

-- INS (design: fp.js:113-141), by Catalog id. The first rows are P0 and HF (fp.js:112) written out.
local TRACKS: { [string]: Track } = {
	kitty_bread = track("KittyBread", { -- design: fp.js:114-115
		dur = 2.5,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.35, 0, 0.05, 0.08, -0.15, 0, 0 },
			{ 0.7, 0, 0.05, 0.08, -0.1, 0, 0.38 },
			{ 0.9, 0, 0.05, 0.08, -0.1, 0, -0.1 },
			{ 1.4, 0, 0.06, 0.06, 0, PI, 0 },
			{ 1.85, 0, 0.05, 0.08, -0.1, TAU, 0 },
			{ 2.5, 0, 0, 0, 0, TAU + 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 1.85, 1, 0, 0, 0, 0, 0, 0 },
			{ 1.95, 1, 0, 0, 0, -0.07, 0.11, 0 },
			{ 2.05, 1, 0, 0, 0, -0.07, 0.085, 0 },
			{ 2.15, 1, 0, 0, 0, -0.07, 0.11, 0 },
			{ 2.4, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = { { 0, 1, 1, 1 }, { 1.98, 1, 1, 1 }, { 2.05, 1.08, 0.86, 1.08 }, { 2.2, 1, 1, 1 } },
		ev = { at(0.68, "flick"), at(2.04, "pat") },
	}),
	toast = track("Toast", { -- design: fp.js:116-117
		dur = 2.2,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.3, 0, 0.05, 0.05, 0, 0, 0 },
			{ 0.75, 0, 0.08, 0.05, PI, 0, 0 },
			{ 1.2, 0, 0.05, 0.05, TAU, 0, 0 },
			{ 1.9, 0, 0.03, 0.05, TAU, 0, 0 },
			{ 2.2, 0, 0, 0, TAU, 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.3, 0.3, 0, 0, 0, 0, 0, 0 },
			{ 1.2, 0.3, 0, 0, 0, 0, 0, 0 },
			{ 1.4, 1, 0, 0, 0, 0, 0, 0 },
			{ 1.55, 1, 0, 0, 0, -0.06, 0.06, 0.02 },
			{ 1.65, 1, 0, 0, 0, -0.06, 0.03, 0.02 },
			{ 1.75, 1, 0, 0, 0, -0.06, 0.06, 0.02 },
			{ 2.0, 1, 0, 0, 0, 0, 0, 0 },
		},
		ev = { at(0.3, "flip"), at(1.66, "tap") },
	}),
	banana = track("Banana", { -- design: fp.js:118-119
		dur = 2.6,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.2, 0.03, 0.02, 0.03, 0, 0, 0 },
			{ 1.3, 0.03, 0.02, 0.03, 0, 0, TAU * 2 },
			{ 1.7, 0.16, 0.11, 0.3, 0, -0.6, TAU * 2 + PI / 2 },
			{ 2.15, 0.16, 0.11, 0.3, 0, -0.6, TAU * 2 + PI / 2 },
			{ 2.6, 0, 0, 0, 0, 0.25, TAU * 2 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.2, 0.4, -0.05, -0.1, 0, 0.03, 0, 0 },
			{ 1.3, 0.4, -0.05, -0.1, 0, 0.03, 0, 0 },
			{ 1.7, 0.6, -0.1, -0.1, 0, 0.02, 0.0, 0 },
			{ 2.6, 1, 0, 0, 0, 0, 0, 0 },
		},
		ev = { at(0.25, "twirl"), at(0.8, "twirl"), at(1.75, "ring") },
	}),
	butter = track("Butter", { -- design: fp.js:120-121
		dur = 2.3,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.45, 0, 0.04, 0.06, 0.75, 0, 0 },
			{ 0.8, -0.05, 0.02, 0.05, 0.4, 0, 0 },
			{ 1.1, 0.05, 0.02, 0.05, 0.4, 0, 0 },
			{ 1.4, -0.03, 0.02, 0.05, 0.4, 0, 0 },
			{ 1.8, 0, 0.03, 0.05, 0, 0.7, 0 },
			{ 2.3, 0, 0, 0, 0, 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.6, 1, 0.02, 0.07, 0, 0, 0, 0 },
			{ 1.4, 1, 0.02, 0.07, 0, 0, 0, 0 },
			{ 1.8, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = { { 0, 1, 1, 1 }, { 0.8, 1.04, 0.92, 1.04 }, { 1.1, 1.04, 0.92, 1.04 }, { 1.4, 1, 1, 1 } },
		ev = { at(0.85, "spread"), at(1.8, "peek") },
	}),
	chocolate = track("Chocolate", { -- design: fp.js:122-123
		dur = 2.4,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.3, 0, 0.04, 0.06, 0, 0, 0 },
			{ 0.6, 0, 0.04, 0.06, 0.32, 0, 0 },
			{ 0.75, 0, 0.04, 0.06, -0.12, 0, 0 },
			{ 0.95, 0, 0.04, 0.06, 0, 0, 0 },
			{ 1.5, 0, 0.05, 0.05, 0, PI, 0 },
			{ 2.0, 0, 0.04, 0.06, 0, TAU, 0 },
			{ 2.4, 0, 0, 0, 0, TAU + 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.6, 1, 0, 0.03, 0.02, 0, 0.03, 0.02 },
			{ 0.95, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = { { 0, 1, 1, 1 }, { 0.6, 1, 0.94, 1 }, { 0.75, 1, 1.03, 1 }, { 0.9, 1, 1, 1 } },
		ev = { at(0.74, "snap") },
	}),
	bird = track("Birdie", { -- design: fp.js:124-125
		dur = 2.7,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.25, 0, -0.02, 0, 0, 0, 0 },
			{ 0.55, 0, 0.1, 0.04, 0, 0, 0 },
			{ 0.85, 0, 0.02, 0.06, 0, 0, 0 },
			{ 1.2, 0, 0.03, 0.1, 0, 0, 0.3 },
			{ 1.5, 0, 0.03, 0.1, 0, 0, -0.2 },
			{ 1.85, 0, 0.12, 0.06, 0, PI, 0 },
			{ 2.2, 0, 0.02, 0.04, 0, TAU, 0 },
			{ 2.7, 0, 0, 0, 0, TAU + 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.3, 0.5, -0.05, -0.08, 0.02, 0.05, -0.08, 0.02 },
			{ 2.3, 0.5, -0.05, -0.08, 0.02, 0.05, -0.08, 0.02 },
			{ 2.7, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = {
			{ 0, 1, 1, 1 },
			{ 0.3, 1.06, 0.88, 1.06 },
			{ 0.45, 0.94, 1.1, 0.94 },
			{ 0.85, 1.1, 0.86, 1.1 },
			{ 1.0, 1, 1, 1 },
		},
		ev = { at(0.4, "flap"), at(1.25, "tweet"), at(1.9, "flap"), at(2.2, "flap") },
	}),
	donut = track("Donut", { -- design: fp.js:126-127
		dur = 2.7,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.25, 0, 0.03, 0.03, 0, 0, 0 },
			{ 1.3, 0, 0.03, 0.03, 0, 0, -TAU * 3 },
			{ 1.75, 0, 0.13, 0.36, 0, 0, -TAU * 3 },
			{ 2.2, 0, 0.13, 0.36, 0, 0, -TAU * 3 },
			{ 2.7, 0, 0, 0, 0, 0.25, -TAU * 3 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.25, 0.55, 0, 0, 0, -0.05, -0.12, 0 },
			{ 1.3, 0.55, 0, 0, 0, -0.05, -0.12, 0 },
			{ 1.75, 0.8, -0.05, 0, 0, 0.05, 0, 0 },
			{ 2.7, 1, 0, 0, 0, 0, 0, 0 },
		},
		ev = { at(0.3, "twirl"), at(0.9, "twirl"), at(1.8, "peek") },
	}),
	dragon = track("Dragon", { -- design: fp.js:128-129
		dur = 2.9,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.45, 0, 0.1, 0.03, -0.2, 0, 0 },
			{ 0.9, 0, 0.11, 0.03, -0.25, 0, 0 },
			{ 1.3, 0, 0.08, 0.05, 0, 0, 0 },
			{ 1.85, 0, 0.05, 0.05, 0, PI, 0 },
			{ 2.35, 0, 0.04, 0.06, 0, TAU, 0 },
			{ 2.9, 0, 0, 0, 0, TAU + 0.25, 0 },
		},
		hands = { { 0, 1, 0, 0, 0, 0, 0, 0 }, { 0.45, 1, 0, -0.02, 0, 0, -0.02, 0 }, { 2.9, 1, 0, 0, 0, 0, 0, 0 } },
		sq = { { 0, 1, 1, 1 }, { 0.8, 0.94, 1.12, 0.94 }, { 1.0, 1.04, 0.95, 1.04 }, { 1.2, 1, 1, 1 } },
		ev = { at(0.82, "roar"), at(1.9, "flap") },
	}),
	mochi_fox = track("MochiFox", { -- design: fp.js:130-131
		dur = 2.6,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.3, 0, 0.03, 0.05, 0, 0, 0 },
			{ 0.95, 0, 0.03, 0.05, 0, 0, 0 },
			{ 1.15, 0, 0.03, 0.05, 0, 0, 0 },
			{ 1.5, 0, 0.03, 0.05, 0, -0.5, 0 },
			{ 1.85, 0, 0.03, 0.05, 0, 0.6, 0 },
			{ 2.6, 0, 0, 0, 0, 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.3, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.95, 1, -0.07, 0.01, 0, 0.07, 0.01, 0 },
			{ 1.05, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = {
			{ 0, 1, 1, 1 },
			{ 0.3, 1, 1, 1 },
			{ 0.95, 1.6, 0.74, 0.9 },
			{ 1.1, 0.85, 1.12, 1.05 },
			{ 1.3, 1.05, 0.96, 1 },
			{ 1.45, 1, 1, 1 },
		},
		ev = { at(0.35, "stretch"), at(1.0, "snapback"), at(1.5, "swish") },
	}),
	strawberry_frog = track("StrawberryFrog", { -- design: fp.js:132-133
		dur = 2.7,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.2, 0.09, 0.0, 0, 0, -0.3, 0 },
			{ 0.45, 0, 0.12, 0, 0, 0, 0 },
			{ 0.7, -0.09, 0.0, 0, 0, 0.3, 0 },
			{ 0.95, 0, 0.12, 0, 0, 0, 0 },
			{ 1.2, 0.0, 0.02, 0.06, 0, 0, 0 },
			{ 1.9, 0, 0.03, 0.06, 0, PI, 0 },
			{ 2.3, 0, 0.03, 0.06, 0, TAU, 0 },
			{ 2.7, 0, 0, 0, 0, TAU + 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.2, 0.35, -0.02, -0.06, 0, 0.02, -0.06, 0 },
			{ 1.2, 0.35, -0.02, -0.06, 0, 0.02, -0.06, 0 },
			{ 1.5, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = {
			{ 0, 1, 1, 1 },
			{ 0.2, 1.1, 0.85, 1.1 },
			{ 0.3, 0.92, 1.12, 0.92 },
			{ 0.7, 1.1, 0.85, 1.1 },
			{ 0.8, 0.92, 1.12, 0.92 },
			{ 1.2, 1.08, 0.9, 1.08 },
			{ 1.35, 1, 1, 1 },
		},
		ev = { at(0.22, "hop"), at(0.72, "hop"), at(1.3, "ribbit") },
	}),
	boba_bear = track("BobaBear", { -- design: fp.js:134-135
		dur = 2.5,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.2, 0, 0.03, 0.04, 0, 0, 0.25 },
			{ 0.32, 0, 0.03, 0.04, 0, 0, -0.25 },
			{ 0.44, 0, 0.03, 0.04, 0, 0, 0.25 },
			{ 0.56, 0, 0.03, 0.04, 0, 0, -0.25 },
			{ 0.68, 0, 0.03, 0.04, 0, 0, 0.25 },
			{ 0.85, 0, 0.03, 0.04, 0, 0, 0 },
			{ 1.3, 0, 0.12, 0.3, 0.55, 0, 0 },
			{ 1.85, 0, 0.12, 0.3, 0.55, 0, 0 },
			{ 2.5, 0, 0, 0, 0, 0.25, 0 },
		},
		hands = { { 0, 1, 0, 0, 0, 0, 0, 0 }, { 2.5, 1, 0, 0, 0, 0, 0, 0 } },
		ev = { at(0.2, "rattle"), at(1.35, "slurp") },
	}),
	pancake_pup = track("PancakePup", { -- design: fp.js:136-137
		dur = 2.6,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.18, 0, -0.03, 0, 0, 0, 0 },
			{ 0.55, 0, 0.2, 0, -PI, 0, 0 },
			{ 0.9, 0, -0.02, 0, -TAU, 0, 0 },
			{ 1.1, 0, 0.01, 0, -TAU, 0, 0 },
			{ 1.6, 0, 0.04, 0.16, -TAU - 0.25, 0, 0 },
			{ 2.0, 0, 0.04, 0.16, -TAU - 0.25, 0, 0 },
			{ 2.6, 0, 0, 0, -TAU, 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.18, 1, 0, -0.03, 0, 0, -0.03, 0 },
			{ 0.3, 0.3, 0, 0, 0, 0, 0, 0 },
			{ 0.8, 0.3, 0, 0, 0, 0, 0, 0 },
			{ 0.9, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = {
			{ 0, 1, 1, 1 },
			{ 0.9, 1, 1, 1 },
			{ 0.97, 1.18, 0.74, 1.18 },
			{ 1.15, 0.95, 1.06, 0.95 },
			{ 1.3, 1, 1, 1 },
		},
		ev = { at(0.2, "toss"), at(0.92, "plop"), at(1.65, "sniff") },
	}),
	cloud_bunny = track("CloudBunny", { -- design: fp.js:138-139
		dur = 2.9,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.35, 0, 0.06, 0, 0, 0, 0 },
			{ 0.8, 0.04, 0.13, 0.02, 0, 0.3, 0.12 },
			{ 1.25, -0.04, 0.15, 0.02, 0, -0.2, -0.12 },
			{ 1.7, 0.03, 0.13, 0.02, 0, 0.1, 0.08 },
			{ 2.3, 0, 0.0, 0, 0, 0.25, 0 },
			{ 2.9, 0, 0, 0, 0, 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.35, 0.25, 0, 0, 0, 0, 0, 0 },
			{ 2.0, 0.25, 0, 0, 0, 0, 0, 0 },
			{ 2.4, 1, 0, 0, 0, 0, 0, 0 },
		},
		sq = { { 0, 1, 1, 1 }, { 2.3, 1, 1, 1 }, { 2.4, 1.1, 0.88, 1.1 }, { 2.6, 1, 1, 1 } },
		ev = { at(0.4, "sparkle"), at(1.25, "sparkle"), at(2.35, "plop") },
	}),
	cupcake_axolotl = track("CupcakeAxolotl", { -- design: fp.js:140-141
		dur = 2.7,
		toy = {
			{ 0, 0, 0, 0, 0, 0.25, 0 },
			{ 0.25, 0, 0.04, 0.04, 0, 0, 0 },
			{ 1.6, 0, 0.04, 0.04, 0, TAU, 0 },
			{ 2.0, 0, 0.1, 0.14, 0.4, TAU, 0 },
			{ 2.3, 0, 0.1, 0.14, 0.4, TAU, 0 },
			{ 2.7, 0, 0, 0, 0, TAU + 0.25, 0 },
		},
		hands = {
			{ 0, 1, 0, 0, 0, 0, 0, 0 },
			{ 0.25, 0.5, 0, -0.02, 0, 0, -0.02, 0 },
			{ 1.6, 0.5, 0, -0.02, 0, 0, -0.02, 0 },
			{ 2.0, 1, 0, 0, 0, 0, 0, 0 },
		},
		ev = { at(0.3, "wiggle"), at(1.0, "wiggle"), at(2.0, "blub") },
	}),
}

-- pc(n, o) (design: fp.js:171): the toy's own specks with these defaults, o over them.
local function puffs(count: number, overrides: { [string]: any }?): Specks.Spec
	local spec: { [string]: any } = {
		kind = "burst",
		count = count,
		shape = "puff",
		colours = nil,
		speed = 0.35,
		size = 0.006,
		life = 0.6,
		gravity = -0.6,
		drag = 3,
	}
	local extra: { [string]: any } = overrides or {}
	for key, value in extra do
		spec[key] = value
	end
	return table.freeze(spec) :: any
end

-- vEv (design: fp.js:169-194). sfx.inspect.* are the design's own inspect one-shots (fp.js:159-167, 173-192).
local WHOOSH = "sfx.inspect.whoosh" -- whoosh(0.22) (fp.js:175)
local RECIPES: { [string]: Recipe } = {
	flick = { sound = "sfx.inspect.flick", kick = -1.6 }, -- design: fp.js:173
	pat = { sound = "sfx.squish", pitched = true, kick = -2, specks = puffs(5, { normal = Vector3.yAxis }) }, -- fp.js:174
	plop = { sound = "sfx.squish", pitched = true, kick = -2, specks = puffs(5, { normal = Vector3.yAxis }) }, -- fp.js:174
	flip = { sound = WHOOSH }, -- design: fp.js:175
	twirl = { sound = WHOOSH }, -- design: fp.js:175
	toss = { sound = WHOOSH }, -- design: fp.js:175
	swish = { sound = WHOOSH }, -- design: fp.js:175
	tap = { sound = "sfx.inspect.tap", specks = puffs(3, { shape = "cube" }) }, -- design: fp.js:176
	spread = { sound = "sfx.inspect.spread" }, -- design: fp.js:177
	peek = { sound = "sfx.inspect.peek" }, -- design: fp.js:178
	sniff = { sound = "sfx.inspect.peek" }, -- design: fp.js:178 (the same tone as peek)
	snap = { -- design: fp.js:179 (spark burst: drag left at fx.js's 1.6)
		sound = "sfx.inspect.snap",
		specks = table.freeze({
			kind = "burst",
			count = 8,
			shape = "spark",
			colours = { Palette.InspectSnapGold, Palette.White },
			speed = 0.5,
			size = 0.006,
			life = 0.5,
			gravity = 0,
		}) :: any,
	},
	flap = { -- design: fp.js:180
		sound = "sfx.inspect.flap",
		kick = 3,
		specks = puffs(4, { shape = "petal", colours = { Palette.White, Palette.InspectFlapBlue } }),
	},
	tweet = { sound = "sfx.inspect.tweet" }, -- design: fp.js:181
	roar = { -- design: fp.js:182 (14 glowdrops at toyWorldPos(0.07), shake >= 0.25)
		sound = "sfx.dragonRoar",
		shake = 0.25,
		specks = table.freeze({
			kind = "emit",
			count = 14,
			shape = "glowdrop",
			colours = { Palette.InspectEmberOrange, Palette.InspectEmberYellow, Palette.InspectEmberPink },
			velMin = Vector3.new(-0.12, 0.15, 0.05),
			velMax = Vector3.new(0.12, 0.4, 0.3),
			size = 0.007,
			life = 0.5,
			gravity = 0.3,
			drag = 2,
			offsetY = 0.07,
		}) :: any,
	},
	stretch = { sound = "sfx.inspect.stretch" }, -- design: fp.js:183 (squish at 0.8 × pitch + a low tone, one file)
	snapback = { sound = "sfx.squeezeRelease", pitched = true, kick = 4, specks = puffs(6) }, -- design: fp.js:184
	hop = { sound = "sfx.pop" }, -- design: fp.js:185
	ribbit = { -- design: fp.js:186
		sound = "sfx.inspect.ribbit",
		specks = puffs(4, { shape = "heart", colours = { Palette.InspectRibbitRed } }),
	},
	rattle = { sound = "sfx.inspect.rattle" }, -- design: fp.js:187
	slurp = { sound = "sfx.inspect.slurp" }, -- design: fp.js:188
	sparkle = { -- design: fp.js:189 (spark burst: drag left at fx.js's 1.6)
		sound = "sfx.inspect.sparkle",
		specks = table.freeze({
			kind = "burst",
			count = 6,
			shape = "spark",
			colours = { Palette.InspectSparkleYellow, Palette.White, Palette.InspectSparkleLilac },
			speed = 0.3,
			size = 0.006,
			life = 0.6,
			gravity = 0,
		}) :: any,
	},
	wiggle = { sound = "sfx.inspect.wiggle", kick = 2.5 }, -- design: fp.js:190
	blub = { -- design: fp.js:191 (8 spheres at toyWorldPos(0.05))
		sound = "sfx.inspect.blub",
		specks = table.freeze({
			kind = "emit",
			count = 8,
			shape = "sphere",
			colours = { Palette.InspectBubble },
			velMin = Vector3.new(-0.05, 0.1, 0),
			velMax = Vector3.new(0.05, 0.25, 0.15),
			size = 0.006,
			life = 0.7,
			gravity = 0.2,
			drag = 1,
			offsetY = 0.05,
		}) :: any,
	},
	ring = { sound = "sfx.inspect.ring" }, -- design: fp.js:192
}
for _, recipe in RECIPES do
	table.freeze(recipe)
end

local IDS: { string } = {}
for id in TRACKS do
	table.insert(IDS, id)
end
table.sort(IDS)
table.freeze(IDS)

-- Public

function InspectTracks.ids(): { string }
	return IDS
end

function InspectTracks.get(squishyId: string): Track?
	return TRACKS[squishyId]
end

function InspectTracks.toyAt(t: Track, time: number): (Vector3, Vector3)
	local a, b, u = kv(t.toy, time)
	return lerp3(a, b, u, 2), lerp3(a, b, u, 5)
end

function InspectTracks.handsAt(
	t: Track,
	time: number,
	sideL: Vector3,
	sideR: Vector3,
	restL: Vector3,
	restR: Vector3
): (Vector3, Vector3)
	local a, b, u = kv(t.hands, time)
	local blend = a[2] + (b[2] - a[2]) * u
	local offL, offR = lerp3(a, b, u, 3), lerp3(a, b, u, 6)
	return (restL + offL):Lerp(sideL + offL, blend), (restR + offR):Lerp(sideR + offR, blend) -- design: fp.js:410
end

function InspectTracks.scaleAt(t: Track, time: number): Vector3
	local sq = t.sq
	if sq == nil then
		return Vector3.one
	end
	local a, b, u = kv(sq, time)
	return lerp3(a, b, u, 2)
end

function InspectTracks.firedBy(t: Track, time: number): number
	local count = 0
	for _, event in t.events do
		if time >= event.t then -- design: fp.js:411
			count += 1
		end
	end
	return count
end

function InspectTracks.wrap(rot: Vector3): Vector3
	return Vector3.new(wrapAngle(rot.X), wrapAngle(rot.Y), wrapAngle(rot.Z)) -- design: fp.js:109
end

function InspectTracks.recipe(name: string): Recipe?
	return RECIPES[name]
end

function InspectTracks.squashScale(y: number, widen: number): Vector3
	local w = 1 + (1 - y) * widen -- design: toys.js:454
	return Vector3.new(w, y, w)
end

return InspectTracks
