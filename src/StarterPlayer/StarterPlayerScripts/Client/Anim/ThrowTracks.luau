--!strict
-- ThrowTracks (client only, pure): the first-person throw moves (spec 2026-10-11 §3.5). The 3D Lab's THROWS (design:
-- fp.js:143-155) verbatim, both hands, by its THROW_STYLE (design: ults.js:9-14), in du, camera space (-Z forward, +Y
-- up, +X right; the overlay draws them × overlayStudsPerDu). Rows are the design's: toy [t, x, y, z, rx, ry, rz] from
-- TH0 (the hold), the right and left hand [t, x, y, z] from RH0 / LH0 to RR / LR (the empty hands) at dur, and sling's
-- and shove's sq [t, sx, sy, sz] (the toy's scale). Each segment is eased cosine in-out (design: fp.js:13, 19); the
-- values are targets for the overlay's springs. No instances, connections or clock reads: the caller passes every
-- time. (speed and arc of the design rows are its world flight: the server owns ours.)
--
-- Timing fits the server, never the other way round (spec 2026-10-10 §3.6). A track's `cock` is its last toy key
-- before `rel`; the strike cock -> rel always lasts Config.Anim.throw.releaseSnapMs (70 ms):
--   * wind-up: track time = cock × clamp(tau / (W - strike), 0, 1), on ThrowController's own time-warped tau, so a
--     late answer shows the cocked pose held (tau waits at W), never a stalled, fully stretched arm;
--   * strike: from s0 = max(releaseAt - strike, the first call that knows releaseAt) (server time), track time moves
--     from where it is (normally cock) to rel over the strike; known >= 70 ms ahead, it reaches rel on releaseAt;
--   * after it: rel + (now - (s0 + strike)) at real speed, until dur. Track time never goes back.
--
-- API
--   ThrowTracks.styles() -> { string }          the 9 style names, sorted
--   ThrowTracks.get(style) -> Track             one track (frozen; its rows are the design's)
--   ThrowTracks.styleOf(squishyId) -> string    the Catalog toy's style (overhand for anything unknown)
--   ThrowTracks.toyAt(track, t) -> (Vector3, Vector3)   the toy's position (du) and design rotation (rx, ry, rz) at
--       track time t, on the toy keys up to rel (design: fp.js:431); past rel it stays on the release key
--   ThrowTracks.handsAt(track, t, fromL, fromR) -> (Vector3, Vector3)   the left and right hand points (du) at t, the
--       first row of each replaced by where that hand was at the press (design: fp.js:305), so nothing snaps
--   ThrowTracks.scaleAt(track, t) -> Vector3    the toy's scale keys at t (sling, shove); (1, 1, 1) for the others
--   ThrowTracks.flairAt(track, t) -> Vector3    2026-10-15 throw overhaul (not the design's rows): for a track without
--       scale keys, the toy squashes into the cock (wide, short) and stretches along the throw (Z) on the strike, then
--       springs back over FLAIR_BACK; (1, 1, 1) for sling and shove (their own keys already do it)
--   ThrowTracks.newClock() -> Clock / ThrowTracks.advance(clock, track, tau?, W?, releaseAt?, now) -> number
--       the track time this frame from ThrowController.localWindup()'s tau, W and releaseAt and the server time now
--       (tau nil = the windup record is gone: the clock runs on by itself)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type Row = { number } -- the design's key row: { t, values... }
export type Track = {
	name: string,
	dur: number,
	rel: number,
	cock: number,
	toy: { Row }, -- { t, x, y, z, rx, ry, rz }; row 1 is TH0
	R: { Row }, -- { t, x, y, z }; row 1 is RH0 (the press replaces it), the last RR at dur
	L: { Row }, -- { t, x, y, z }; row 1 is LH0, the last LR at dur
	sq: { Row }?, -- { t, sx, sy, sz }
}
export type Clock = {
	last: number, -- the track time last returned
	strikeAt: number?, -- s0 (server time), once releaseAt is known
	strikeFrom: number?, -- the track time the strike started from
}

-- Constants

local STRIKE = Config.Anim.throw.releaseSnapMs / 1000
local DEFAULT_STYLE = "overhand"
local FLAIR_COCK = Vector3.new(1.1, 0.88, 1.1) -- 2026-10-15: the squash into the cock
local FLAIR_STRIKE = Vector3.new(0.86, 0.86, 1.3) -- the stretch along the throw on the strike
local FLAIR_BACK = 0.12 -- seconds after rel back to (1, 1, 1)

-- The design's rows (fp.js:144): the toy at the hold, the hands at the press, the empty hands.
local TH0 = { 0, 0, -0.13, -0.5, 0, 0.25, 0 } -- design: fp.js:144
local RH0 = { 0, 0.14, -0.165, -0.465 } -- design: fp.js:144
local LH0 = { 0, -0.14, -0.165, -0.465 } -- design: fp.js:144
local RR = { 0.16, -0.23, -0.46 } -- design: fp.js:144
local LR = { -0.16, -0.23, -0.46 } -- design: fp.js:144

-- Module table

local ThrowTracks = {}

-- Private

-- [t, ...RR] (design: fp.js:146-154)
local function at(t: number, xyz: { number }): Row
	return { t, xyz[1], xyz[2], xyz[3] }
end

local function ease(u: number): number
	return 0.5 - 0.5 * math.cos(math.pi * math.clamp(u, 0, 1)) -- design: fp.js:13
end

-- One track from its design row; cock is its last toy key before rel.
local function track(name: string, row: { [string]: any }): Track
	local cock = 0
	for _, key in row.toy do
		if key[1] < row.rel then
			cock = key[1]
		end
	end
	return table.freeze({
		name = name,
		dur = row.dur,
		rel = row.rel,
		cock = cock,
		toy = table.freeze(row.toy),
		R = table.freeze(row.R),
		L = table.freeze(row.L),
		sq = if row.sq then table.freeze(row.sq) else nil,
	})
end

-- Row i's three values from column `from` (`first` replaces row 1's: the hands at the press).
local function rowValue(rows: { Row }, i: number, from: number, first: Vector3?): Vector3
	if i == 1 and first then
		return first
	end
	local row = rows[i]
	return Vector3.new(row[from], row[from + 1], row[from + 2])
end

-- The design's kv (fp.js:19): three values from column `from` of the rows at time t, each segment eased.
local function kv(rows: { Row }, t: number, from: number, first: Vector3?): Vector3
	if t <= rows[1][1] then
		return rowValue(rows, 1, from, first)
	end
	for i = 1, #rows - 1 do
		local b = rows[i + 1]
		if t <= b[1] then
			local a = rows[i]
			local u = ease((t - a[1]) / (b[1] - a[1]))
			return rowValue(rows, i, from, first):Lerp(rowValue(rows, i + 1, from, first), u)
		end
	end
	return rowValue(rows, #rows, from, first)
end

-- THROWS (design: fp.js:145-155).
local TRACKS: { [string]: Track } = {
	overhand = track("overhand", { -- design: fp.js:146
		dur = 0.75,
		rel = 0.27,
		toy = { TH0, { 0.17, 0.2, 0.03, -0.3, 0.5, 0, -0.4 }, { 0.27, 0.07, -0.04, -0.78, -0.6, 0, 0 } },
		R = {
			RH0,
			{ 0.17, 0.25, -0.02, -0.27 },
			{ 0.27, 0.1, -0.08, -0.72 },
			{ 0.45, -0.06, -0.34, -0.6 },
			at(0.75, RR),
		},
		L = { LH0, { 0.17, -0.1, -0.08, -0.68 }, { 0.3, -0.2, -0.3, -0.5 }, at(0.75, LR) },
	}),
	sidearm = track("sidearm", { -- design: fp.js:147
		dur = 0.75,
		rel = 0.25,
		toy = { TH0, { 0.16, -0.2, -0.18, -0.36, 0, 1.2, 0.3 }, { 0.25, 0.1, -0.16, -0.74, 0, -0.6, 0 } },
		R = {
			RH0,
			{ 0.16, -0.12, -0.22, -0.36 },
			{ 0.25, 0.18, -0.2, -0.7 },
			{ 0.45, 0.34, -0.24, -0.48 },
			at(0.75, RR),
		},
		L = { LH0, { 0.16, -0.3, -0.2, -0.36 }, { 0.3, -0.24, -0.34, -0.46 }, at(0.75, LR) },
	}),
	spiral = track("spiral", { -- design: fp.js:148
		dur = 0.78,
		rel = 0.29,
		toy = {
			TH0,
			{ 0.12, 0.12, -0.1, -0.4, 0, 1.57, 0 },
			{ 0.2, 0.2, 0.02, -0.26, 0.4, 1.57, 0 },
			{ 0.29, 0.06, -0.04, -0.8, -0.2, 1.57, 0 },
		},
		R = {
			RH0,
			{ 0.12, 0.16, -0.14, -0.4 },
			{ 0.2, 0.24, -0.02, -0.26 },
			{ 0.29, 0.1, -0.08, -0.72 },
			{ 0.47, -0.06, -0.34, -0.6 },
			at(0.78, RR),
		},
		L = { LH0, { 0.2, -0.1, -0.08, -0.68 }, { 0.32, -0.2, -0.3, -0.5 }, at(0.78, LR) },
	}),
	lob = track("lob", { -- design: fp.js:149
		dur = 0.85,
		rel = 0.32,
		toy = { TH0, { 0.18, 0.05, -0.42, -0.34, 0.6, 0.25, 0 }, { 0.32, 0.02, -0.06, -0.66, -0.4, 0.25, 0 } },
		R = { RH0, { 0.18, 0.14, -0.46, -0.32 }, { 0.32, 0.1, -0.1, -0.62 }, { 0.5, 0.12, 0.0, -0.6 }, at(0.85, RR) },
		L = { LH0, { 0.18, -0.18, -0.38, -0.4 }, { 0.4, -0.2, -0.3, -0.5 }, at(0.85, LR) },
	}),
	glide = track("glide", { -- design: fp.js:150
		dur = 0.8,
		rel = 0.26,
		toy = { TH0, { 0.14, 0, -0.27, -0.46, 0.2, 0, 0 }, { 0.26, 0, -0.02, -0.7, -0.3, 0, 0 } },
		R = {
			RH0,
			{ 0.14, 0.08, -0.33, -0.45 },
			{ 0.26, 0.08, -0.06, -0.66 },
			{ 0.45, 0.14, 0.02, -0.62 },
			at(0.8, RR),
		},
		L = {
			LH0,
			{ 0.14, -0.08, -0.33, -0.45 },
			{ 0.26, -0.08, -0.06, -0.66 },
			{ 0.45, -0.14, 0.02, -0.62 },
			at(0.8, LR),
		},
	}),
	skip = track("skip", { -- design: fp.js:151
		dur = 0.75,
		rel = 0.24,
		toy = { TH0, { 0.15, 0.26, -0.36, -0.32, 0, -0.8, 0.2 }, { 0.24, 0.04, -0.38, -0.72, 0, 0.4, 0 } },
		R = { RH0, { 0.15, 0.3, -0.4, -0.3 }, { 0.24, 0.08, -0.42, -0.66 }, { 0.42, -0.14, -0.4, -0.6 }, at(0.75, RR) },
		L = { LH0, { 0.15, -0.24, -0.26, -0.5 }, at(0.75, LR) },
	}),
	sling = track("sling", { -- design: fp.js:152
		dur = 0.95,
		rel = 0.52,
		toy = { TH0, { 0.45, 0.02, -0.16, -0.4, 0, 0, 0 }, { 0.52, 0.0, -0.14, -0.8, 0, 0, 0 } },
		sq = { { 0, 1, 1, 1 }, { 0.45, 0.78, 0.85, 1.75 }, { 0.52, 1, 1, 1 } },
		R = { RH0, { 0.45, 0.08, -0.17, -0.3 }, { 0.52, 0.1, -0.17, -0.4 }, at(0.95, RR) },
		L = {
			LH0,
			{ 0.2, -0.05, -0.16, -0.66 },
			{ 0.52, -0.05, -0.16, -0.66 },
			{ 0.7, -0.2, -0.3, -0.5 },
			at(0.95, LR),
		},
	}),
	bounce = track("bounce", { -- design: fp.js:153
		dur = 0.75,
		rel = 0.27,
		toy = { TH0, { 0.17, 0.18, 0.02, -0.32, 0.5, 0, -0.3 }, { 0.27, 0.05, -0.22, -0.78, 0.6, 0, 0 } },
		R = {
			RH0,
			{ 0.17, 0.23, -0.02, -0.3 },
			{ 0.27, 0.08, -0.24, -0.72 },
			{ 0.45, -0.04, -0.4, -0.58 },
			at(0.75, RR),
		},
		L = { LH0, { 0.17, -0.1, -0.1, -0.66 }, { 0.3, -0.2, -0.3, -0.5 }, at(0.75, LR) },
	}),
	shove = track("shove", { -- design: fp.js:154
		dur = 1.0,
		rel = 0.55,
		toy = { TH0, { 0.4, 0, -0.2, -0.34, 0, 0, 0 }, { 0.55, 0, -0.12, -0.86, 0, 0, 0 } },
		sq = { { 0, 1, 1, 1 }, { 0.38, 0.92, 1.1, 0.92 }, { 0.55, 1.08, 0.9, 1.1 }, { 0.6, 1, 1, 1 } },
		R = { RH0, { 0.4, 0.12, -0.22, -0.32 }, { 0.55, 0.1, -0.14, -0.78 }, at(1.0, RR) },
		L = { LH0, { 0.4, -0.12, -0.22, -0.32 }, { 0.55, -0.1, -0.14, -0.78 }, at(1.0, LR) },
	}),
}

-- THROW_STYLE (design: ults.js:9-14), by Catalog id (the design's id in each comment).
local STYLE_OF: { [string]: string } = {
	kitty_bread = "overhand", -- KittyBread
	toast = "sidearm", -- Toast
	banana = "spiral", -- Banana
	butter = "skip", -- Butter
	chocolate = "sidearm", -- Chocolate
	bird = "glide", -- Birdie
	donut = "sidearm", -- Donut
	dragon = "shove", -- Dragon
	mochi_fox = "sling", -- MochiFox
	strawberry_frog = "bounce", -- StrawberryFrog
	boba_bear = "lob", -- BobaBear
	pancake_pup = "sidearm", -- PancakePup
	cloud_bunny = "lob", -- CloudBunny
	cupcake_axolotl = "lob", -- CupcakeAxolotl
}

local STYLE_NAMES: { string } = {}
for name in TRACKS do
	table.insert(STYLE_NAMES, name)
end
table.sort(STYLE_NAMES)
table.freeze(STYLE_NAMES)

-- Public

function ThrowTracks.styles(): { string }
	return STYLE_NAMES
end

function ThrowTracks.get(style: string): Track
	local found = TRACKS[style]
	assert(found ~= nil, `[SD][ThrowTracks] unknown style {tostring(style)}`)
	return found
end

function ThrowTracks.styleOf(squishyId: string): string
	return STYLE_OF[squishyId] or DEFAULT_STYLE
end

function ThrowTracks.toyAt(t: Track, time: number): (Vector3, Vector3)
	local clamped = math.min(time, t.rel) -- design: fp.js:431
	return kv(t.toy, clamped, 2), kv(t.toy, clamped, 5)
end

function ThrowTracks.handsAt(t: Track, time: number, fromL: Vector3, fromR: Vector3): (Vector3, Vector3)
	return kv(t.L, time, 2, fromL), kv(t.R, time, 2, fromR)
end

function ThrowTracks.scaleAt(t: Track, time: number): Vector3
	local sq = t.sq
	return if sq then kv(sq, time, 2) else Vector3.one
end

function ThrowTracks.flairAt(t: Track, time: number): Vector3
	if t.sq ~= nil then
		return Vector3.one
	end
	if time <= t.cock then
		return Vector3.one:Lerp(FLAIR_COCK, ease(time / math.max(t.cock, 1e-3)))
	elseif time <= t.rel then
		return FLAIR_COCK:Lerp(FLAIR_STRIKE, ease((time - t.cock) / math.max(t.rel - t.cock, 1e-3)))
	end
	return FLAIR_STRIKE:Lerp(Vector3.one, ease((time - t.rel) / FLAIR_BACK))
end

function ThrowTracks.newClock(): Clock
	return { last = 0, strikeAt = nil, strikeFrom = nil }
end

function ThrowTracks.advance(
	clock: Clock,
	t: Track,
	tau: number?,
	windup: number?,
	releaseAt: number?,
	now: number
): number
	if clock.strikeAt == nil and releaseAt ~= nil then
		clock.strikeAt = math.max(releaseAt - STRIKE, now)
	end
	local strikeAt = clock.strikeAt
	local value = clock.last
	if strikeAt ~= nil and now >= strikeAt then
		local from = clock.strikeFrom or clock.last
		clock.strikeFrom = from
		local into = now - strikeAt
		if into >= STRIKE then
			value = t.rel + (into - STRIKE)
		else
			value = from + (t.rel - from) * (into / STRIKE)
		end
	elseif tau ~= nil and windup ~= nil then
		value = t.cock * math.clamp(tau / math.max(windup - STRIKE, 1e-3), 0, 1)
	end
	value = math.clamp(value, clock.last, t.dur)
	clock.last = value
	return value
end

return ThrowTracks
