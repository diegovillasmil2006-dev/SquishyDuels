--!strict
-- InspectTracks_Test: unit tests for StarterPlayerScripts.Client.Anim.InspectTracks (final polish 2026-10-11: the 14
-- first-person Inspect showcases; design: sd/fp.js INS, fp.js:111-194). Server only (ServerStorage.UnitTest). Pure: no
-- instances.
-- Contract:
--   * one showcase per Catalog squishy (14), each the design's INS entry verbatim: dur, the toy rows [t, x, y, z, rx,
--     ry, rz], the hand rows [t, blend, lx, ly, lz, rx, ry, rz], the squash rows [t, sx, sy, sz] where the design has
--     them, the timed events (checked against a copy of the design rows below, typed from fp.js:113-141);
--   * keys are cosine-eased segments (design: fp.js:13, 19): on each key at its time, the plain mean of two keys at
--     the middle of their segment, row 1 before it and the last row after the end;
--   * the toy's offset is added to the hold point and its rotation replaces the hold rotation (fp.js:408-409);
--   * each hand is (REST + its offset) lerped to the toy's side (+ its offset) by the blend (fp.js:410);
--   * scaleAt is the squash keys, (1, 1, 1) without them; firedBy counts the events due at t (fp.js:411);
--   * wrap brings each angle into (-π, π] as wrapRot (fp.js:109), so the hold comes back without unwinding turns;
--   * every event has a recipe from vEv (fp.js:169-194): its sound slot (AssetTable), the toy's pitch for the three
--     material sounds, the kick, the shake and the specks; squashScale is the design's (w, y, w) (toys.js:454-455).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-6
-- Vector3 holds 32-bit floats: an angle near 2π is off by up to about 5e-7 before the wrap.
local ANGLE_EPS = 1e-5
local TAU = 2 * math.pi
local PI = math.pi

-- A copy of the design rows (fp.js:113-141), typed from the design file (P0 and HF spelled out, Math.PI as PI).
type Rows = { { number } }
type Design = { dur: number, toy: Rows, hands: Rows, sq: Rows?, ev: { { any } } }
local DESIGN: { [string]: Design } = {
	kitty_bread = { -- KittyBread, fp.js:114-115
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
		ev = { { 0.68, "flick" }, { 2.04, "pat" } },
	},
	toast = { -- Toast, fp.js:116-117
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
		ev = { { 0.3, "flip" }, { 1.66, "tap" } },
	},
	banana = { -- Banana, fp.js:118-119
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
		ev = { { 0.25, "twirl" }, { 0.8, "twirl" }, { 1.75, "ring" } },
	},
	butter = { -- Butter, fp.js:120-121
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
		ev = { { 0.85, "spread" }, { 1.8, "peek" } },
	},
	chocolate = { -- Chocolate, fp.js:122-123
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
		ev = { { 0.74, "snap" } },
	},
	bird = { -- Birdie, fp.js:124-125
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
		ev = { { 0.4, "flap" }, { 1.25, "tweet" }, { 1.9, "flap" }, { 2.2, "flap" } },
	},
	donut = { -- Donut, fp.js:126-127
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
		ev = { { 0.3, "twirl" }, { 0.9, "twirl" }, { 1.8, "peek" } },
	},
	dragon = { -- Dragon, fp.js:128-129
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
		ev = { { 0.82, "roar" }, { 1.9, "flap" } },
	},
	mochi_fox = { -- MochiFox, fp.js:130-131
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
		ev = { { 0.35, "stretch" }, { 1.0, "snapback" }, { 1.5, "swish" } },
	},
	strawberry_frog = { -- StrawberryFrog, fp.js:132-133
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
		ev = { { 0.22, "hop" }, { 0.72, "hop" }, { 1.3, "ribbit" } },
	},
	boba_bear = { -- BobaBear, fp.js:134-135
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
		ev = { { 0.2, "rattle" }, { 1.35, "slurp" } },
	},
	pancake_pup = { -- PancakePup, fp.js:136-137
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
		ev = { { 0.2, "toss" }, { 0.92, "plop" }, { 1.65, "sniff" } },
	},
	cloud_bunny = { -- CloudBunny, fp.js:138-139
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
		ev = { { 0.4, "sparkle" }, { 1.25, "sparkle" }, { 2.35, "plop" } },
	},
	cupcake_axolotl = { -- CupcakeAxolotl, fp.js:140-141
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
		ev = { { 0.3, "wiggle" }, { 1.0, "wiggle" }, { 2.0, "blub" } },
	},
}

local function close(a: Vector3, b: Vector3, tolerance: number?): boolean
	return (a - b).Magnitude <= (tolerance or EPS)
end

local function ease(u: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(u, 0, 1))
end

return function(t: Context)
	local Tracks = t.requireClient("Anim/InspectTracks")
	local Catalog = t.requireShared("Catalog")
	local AssetTable = t.requireShared("AssetTable")
	local expect = t.expect

	t.test("one showcase per Catalog squishy, each the design's INS entry verbatim (fp.js:113-141)", function()
		local catalogIds: { string } = {}
		for _, def in Catalog.list() do
			table.insert(catalogIds, def.id)
		end
		table.sort(catalogIds)
		expect.deepEqual(Tracks.ids(), catalogIds)
		expect.equal(#Tracks.ids(), 14)
		for id, design in DESIGN do
			local track = Tracks.get(id)
			if track == nil then
				error(`no showcase for {id}`)
			end
			expect.equal(track.dur, design.dur)
			expect.deepEqual(track.toy, design.toy)
			expect.deepEqual(track.hands, design.hands)
			expect.deepEqual(track.sq, design.sq)
			local events = {}
			for _, event in track.events do
				table.insert(events, { event.t, event.name })
			end
			expect.deepEqual(events, design.ev)
		end
		expect.equal(Tracks.get("no_such_toy"), nil)
	end)

	t.test("every track starts at the hold with both hands on the toy and ends at the hold yaw", function()
		for _, id in Tracks.ids() do
			local track = Tracks.get(id)
			expect.deepEqual(track.toy[1], { 0, 0, 0, 0, 0, 0.25, 0 }) -- P0 (fp.js:112)
			expect.deepEqual(track.hands[1], { 0, 1, 0, 0, 0, 0, 0, 0 }) -- HF (fp.js:112)
			local last = track.toy[#track.toy]
			expect.near(last[1], track.dur) -- the toy's last key at dur
			local _, rot = Tracks.toyAt(track, track.dur)
			expect.truthy(close(Tracks.wrap(rot), Vector3.new(0, 0.25, 0), ANGLE_EPS)) -- back to HOLD_R (fp.js:77)
			for _, rows in { track.toy, track.hands, track.sq or {} } do
				for i = 2, #rows do
					expect.truthy(rows[i][1] >= rows[i - 1][1])
				end
			end
			for i, event in track.events do
				expect.truthy(event.t >= 0 and event.t <= track.dur)
				if i > 1 then
					expect.truthy(event.t > track.events[i - 1].t)
				end
			end
		end
	end)

	t.test("toyAt: the offset and rotation on eased keys (fp.js:19, 408-409)", function()
		local track = Tracks.get("kitty_bread")
		local offset, rot = Tracks.toyAt(track, 0)
		expect.truthy(close(offset, Vector3.zero))
		expect.truthy(close(rot, Vector3.new(0, 0.25, 0)))
		offset, rot = Tracks.toyAt(track, 0.35) -- on a key
		expect.truthy(close(offset, Vector3.new(0, 0.05, 0.08)))
		expect.truthy(close(rot, Vector3.new(-0.15, 0, 0)))
		offset, rot = Tracks.toyAt(track, 0.175) -- the middle of the first segment: the plain mean
		expect.truthy(close(offset, Vector3.new(0, 0.025, 0.04)))
		expect.truthy(close(rot, Vector3.new(-0.075, 0.125, 0)))
		local u = ease((0.5 - 0.35) / (0.7 - 0.35)) -- an eased point
		offset, rot = Tracks.toyAt(track, 0.5)
		expect.truthy(close(rot, Vector3.new(-0.15 + 0.05 * u, 0, 0.38 * u)))
		offset, rot = Tracks.toyAt(track, -1) -- before row 1
		expect.truthy(close(rot, Vector3.new(0, 0.25, 0)))
		offset, rot = Tracks.toyAt(track, 9) -- after the end: the last row
		expect.truthy(close(offset, Vector3.zero))
		expect.truthy(close(rot, Vector3.new(0, TAU + 0.25, 0)))
	end)

	t.test("handsAt: REST + offset lerped to the toy's sides + offset by the blend (fp.js:410)", function()
		local restL, restR = Vector3.new(-0.16, -0.23, -0.46), Vector3.new(0.16, -0.23, -0.46)
		local sideL, sideR = Vector3.new(-0.15, -0.165, -0.465), Vector3.new(0.15, -0.165, -0.465)
		local kitty = Tracks.get("kitty_bread")
		local left, right = Tracks.handsAt(kitty, 0, sideL, sideR, restL, restR)
		expect.truthy(close(left, sideL)) -- blend 1: on the toy
		expect.truthy(close(right, sideR))
		left, right = Tracks.handsAt(kitty, 2.05, sideL, sideR, restL, restR) -- the pat (fp.js:115)
		expect.truthy(close(left, sideL))
		expect.truthy(close(right, sideR + Vector3.new(-0.07, 0.085, 0)))
		local toast = Tracks.get("toast")
		left, right = Tracks.handsAt(toast, 0.75, sideL, sideR, restL, restR) -- blend 0.3 through the flip
		expect.truthy(close(left, restL:Lerp(sideL, 0.3)))
		expect.truthy(close(right, restR:Lerp(sideR, 0.3)))
		local bird = Tracks.get("bird")
		left, right = Tracks.handsAt(bird, 1.0, sideL, sideR, restL, restR) -- blend 0.5, both offsets
		local offL, offR = Vector3.new(-0.05, -0.08, 0.02), Vector3.new(0.05, -0.08, 0.02)
		expect.truthy(close(left, (restL + offL):Lerp(sideL + offL, 0.5)))
		expect.truthy(close(right, (restR + offR):Lerp(sideR + offR, 0.5)))
	end)

	t.test("scaleAt: the squash keys, (1, 1, 1) without them", function()
		expect.truthy(close(Tracks.scaleAt(Tracks.get("kitty_bread"), 2.05), Vector3.new(1.08, 0.86, 1.08)))
		expect.truthy(close(Tracks.scaleAt(Tracks.get("mochi_fox"), 0.95), Vector3.new(1.6, 0.74, 0.9)))
		for _, at in { 0, 1, 2.2 } do
			expect.truthy(close(Tracks.scaleAt(Tracks.get("toast"), at), Vector3.one))
		end
	end)

	t.test("firedBy counts the events due at t (fp.js:411)", function()
		local track = Tracks.get("kitty_bread")
		expect.equal(Tracks.firedBy(track, 0), 0)
		expect.equal(Tracks.firedBy(track, 0.67), 0)
		expect.equal(Tracks.firedBy(track, 0.68), 1)
		expect.equal(Tracks.firedBy(track, 2.04), 2)
		expect.equal(Tracks.firedBy(track, 99), 2)
	end)

	t.test("wrap brings each angle into (-π, π] as wrapRot (fp.js:109)", function()
		local wrapped = Tracks.wrap(Vector3.new(TAU, TAU + 0.25, -TAU * 3))
		expect.truthy(close(wrapped, Vector3.new(0, 0.25, 0), ANGLE_EPS))
		local edge = Tracks.wrap(Vector3.new(PI - 0.01, -PI + 0.01, 4))
		expect.truthy(close(edge, Vector3.new(PI - 0.01, -PI + 0.01, 4 - TAU), ANGLE_EPS))
		local back = Tracks.wrap(Vector3.new(-TAU - 0.25, 0.1, -0.1))
		expect.truthy(close(back, Vector3.new(-0.25, 0.1, -0.1), ANGLE_EPS))
	end)

	t.test("every event has the design's recipe (fp.js:169-194) and its sound is an AssetTable slot", function()
		local sounds: { [string]: boolean } = {}
		for _, slot in AssetTable.all() do
			if slot.kind == "sound" then
				sounds[slot.key] = true
			end
		end
		for _, id in Tracks.ids() do
			for _, event in Tracks.get(id).events do
				local recipe = Tracks.recipe(event.name)
				if recipe == nil then
					error(`no recipe for {event.name}`)
				end
				if not sounds[recipe.sound] then
					error(`{event.name}: {tostring(recipe.sound)} is not a sound slot`)
				end
			end
		end
		expect.equal(Tracks.recipe("nope"), nil)
		-- The material sounds play the squeeze slots at the toy's pitch; the design's own one-shots their own slots.
		local pat = Tracks.recipe("pat")
		expect.equal(pat.sound, "sfx.squish")
		expect.truthy(pat.pitched)
		expect.equal(pat.kick, -2)
		expect.equal(pat.specks.count, 5)
		expect.truthy(close(pat.specks.normal, Vector3.yAxis))
		expect.equal(Tracks.recipe("plop").sound, "sfx.squish")
		local snapback = Tracks.recipe("snapback")
		expect.equal(snapback.sound, "sfx.squeezeRelease")
		expect.truthy(snapback.pitched)
		expect.equal(snapback.kick, 4)
		expect.equal(snapback.specks.count, 6)
		expect.equal(Tracks.recipe("hop").sound, "sfx.pop")
		local roar = Tracks.recipe("roar")
		expect.equal(roar.sound, "sfx.dragonRoar")
		expect.equal(roar.shake, 0.25)
		expect.equal(roar.specks.kind, "emit")
		expect.equal(roar.specks.count, 14)
		expect.equal(Tracks.recipe("flick").kick, -1.6)
		expect.equal(Tracks.recipe("flap").kick, 3)
		expect.equal(Tracks.recipe("flap").specks.count, 4)
		expect.equal(Tracks.recipe("wiggle").kick, 2.5)
		expect.equal(Tracks.recipe("snap").specks.count, 8)
		expect.equal(Tracks.recipe("sparkle").specks.count, 6)
		expect.equal(Tracks.recipe("blub").specks.count, 8)
		expect.equal(Tracks.recipe("tap").specks.shape, "cube")
		expect.equal(Tracks.recipe("ribbit").specks.shape, "heart")
		for _, name in { "flip", "twirl", "toss", "swish" } do
			expect.equal(Tracks.recipe(name).sound, "sfx.inspect.whoosh")
		end
		expect.equal(Tracks.recipe("peek").sound, Tracks.recipe("sniff").sound)
		for _, name in { "flick", "tap", "spread", "snap", "tweet", "stretch", "ribbit", "rattle", "slurp" } do
			expect.equal(Tracks.recipe(name).sound, "sfx.inspect." .. name)
			expect.falsy(Tracks.recipe(name).pitched)
		end
	end)

	t.test("squashScale: the design's squash node (w, y, w), w = 1 + (1 - y)·widen (toys.js:454-455)", function()
		expect.truthy(close(Tracks.squashScale(1, 0.72), Vector3.one))
		expect.truthy(close(Tracks.squashScale(0.9, 0.72), Vector3.new(1.072, 0.9, 1.072)))
		expect.truthy(close(Tracks.squashScale(1.1, 0.5), Vector3.new(0.95, 1.1, 0.95)))
	end)
end
