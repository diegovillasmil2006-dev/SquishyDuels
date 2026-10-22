--!strict
-- ShowOffTracks (client only, pure): the 14 shelf show-off loops (pens3 phase 11; lobby design v6 kit.json
-- "showoff", K:6982-7829, one per squishy kind, `K:n` = kit.json line n, `P3D:n` = "Squishy Lobby 3D.html" line n),
-- keyed by Catalog id, verbatim: each loop is `length` s long, each track a K prop ("posY", "rotX", "rotY", "rotZ" in
-- degrees, "scale" {x, y, z}, "scaleY") with its keys {time s, value, ease}; a key's ease shapes the segment that
-- arrives at it (P3D:486 sample: "Sine InOut", "Quad Out", ...; "-" linear), and a track that ends before the loop
-- holds its last value. PenController plays them on the shelf's and the TOP spot's squishies. No instances,
-- connections or clock reads: the caller passes the time.
--
-- API
--   ShowOffTracks.ids() -> { string }                 the Catalog ids with a loop, sorted
--   ShowOffTracks.get(kind) -> Loop?                  one loop (frozen data)
--   ShowOffTracks.poseAt(kind, t, studs) -> (lift, turn)   the squishy's pose `t` s into its loop (looped): `lift`
--       studs up (posY × studs / 2: P3D:401 plays posY at k = studs / 2) and `turn` the rotation about its middle
--       (CFrame.Angles(rx, ry, rz)). The design's toy faces +Z, a Roblox squishy model -Z (SquishyCache), so rotX and
--       rotZ change sign (rotY does not): a nod or a roll reads the same (the Dragon still lifts its head).
--       shortcut: the scale / scaleY tracks are not shown (a part-built squishy squashes only through a SquishDeformer
--       slot, and Config.Vfx.Budgets.deformingRigs is full); give the shelf deform slots to show them.
--       qb1 (owner 2026-10-15: every shelf squishy has its own show-off animation): Kitty Bread's and Butter's loops
--       are scale-only, so they play a posY / rot stand-in of the same idea and timing (STAND_INS) instead of standing
--       still; get() still returns the design's loop.
--       An unknown kind: (0, CFrame.identity).

-- Requires

local Timeline = require(script.Parent.Timeline)

-- Types

export type Key = { any } -- { time s, value (number or { x, y, z }), ease }
export type Track = { prop: string, keys: { Key } }
export type Loop = { length: number, tracks: { Track } }

-- Constants

local COMMON_HALF = 2 -- P3D:401: posY plays at k = studs / 2
local EASES: { [string]: { Enum.EasingStyle | Enum.EasingDirection } } = {
	["-"] = { Enum.EasingStyle.Linear, Enum.EasingDirection.Out },
	["Sine In"] = { Enum.EasingStyle.Sine, Enum.EasingDirection.In },
	["Sine Out"] = { Enum.EasingStyle.Sine, Enum.EasingDirection.Out },
	["Sine InOut"] = { Enum.EasingStyle.Sine, Enum.EasingDirection.InOut },
	["Quad In"] = { Enum.EasingStyle.Quad, Enum.EasingDirection.In },
	["Quad Out"] = { Enum.EasingStyle.Quad, Enum.EasingDirection.Out },
	["Quad InOut"] = { Enum.EasingStyle.Quad, Enum.EasingDirection.InOut },
	["Back Out"] = { Enum.EasingStyle.Back, Enum.EasingDirection.Out },
}

-- K:6982-7829, verbatim (the kind's K name and its idea in each comment).
local LOOPS: { [string]: Loop } = {
	-- K:6984 KittyBread: Loaf Stretch. Stretches long like a rising loaf, then settles.
	kitty_bread = {
		length = 2.4,
		tracks = {
			{
				prop = "scale",
				keys = {
					{ 0, { 1, 1, 1 }, "-" },
					{ 0.7, { 1.2, 0.85, 1.1 }, "Sine InOut" },
					{ 1.4, { 1, 1, 1 }, "Sine InOut" },
					{ 2.4, { 1, 1, 1 }, "-" },
				},
			},
		},
	},
	-- K:7035 Toast: Pop-Up Flip. Pops up like out of a toaster and flips once.
	toast = {
		length = 2.8,
		tracks = {
			{
				prop = "posY",
				keys = { { 0, 0, "-" }, { 0.35, 1.2, "Quad Out" }, { 0.7, 0, "Quad In" }, { 2.8, 0, "-" } },
			},
			{ prop = "rotX", keys = { { 0, 0, "-" }, { 0.7, 360, "Sine InOut" }, { 2.8, 360, "-" } } },
		},
	},
	-- K:7091 Banana: Peel Twirl. Twirls on the spot.
	banana = {
		length = 2.6,
		tracks = {
			{ prop = "rotY", keys = { { 0, 0, "-" }, { 1.2, 360, "Sine InOut" }, { 2.6, 360, "-" } } },
			{ prop = "posY", keys = { { 0, 0, "-" }, { 0.6, 0.3, "Sine Out" }, { 1.2, 0, "Sine In" } } },
		},
	},
	-- K:7142 Butter: Melt & Reset. Melts a little, then springs back.
	butter = {
		length = 2.6,
		tracks = {
			{
				prop = "scale",
				keys = {
					{ 0, { 1, 1, 1 }, "-" },
					{ 0.8, { 1.15, 0.7, 1.15 }, "Sine Out" },
					{ 1.3, { 1, 1, 1 }, "Back Out" },
					{ 2.6, { 1, 1, 1 }, "-" },
				},
			},
		},
	},
	-- K:7193 Chocolate: Snap Wiggle. Quick side-to-side wiggle.
	chocolate = {
		length = 2.4,
		tracks = {
			{
				prop = "rotZ",
				keys = {
					{ 0, 0, "-" },
					{ 0.15, 8, "Quad Out" },
					{ 0.35, -8, "Sine InOut" },
					{ 0.55, 6, "Sine InOut" },
					{ 0.8, 0, "Sine Out" },
					{ 2.4, 0, "-" },
				},
			},
		},
	},
	-- K:7238 Birdie: Flutter Hop. Two little flutters in the air.
	bird = {
		length = 2.4,
		tracks = {
			{
				prop = "posY",
				keys = {
					{ 0, 0, "-" },
					{ 0.3, 0.8, "Quad Out" },
					{ 0.5, 0.5, "Sine InOut" },
					{ 0.7, 0.9, "Sine Out" },
					{ 1, 0, "Quad In" },
					{ 2.4, 0, "-" },
				},
			},
			{
				prop = "rotZ",
				keys = { { 0, 0, "-" }, { 0.3, -6, "Sine Out" }, { 0.7, 6, "Sine InOut" }, { 1, 0, "Sine In" } },
			},
		},
	},
	-- K:7309 Donut: Wheel Roll. Rolls once like a wheel, in place.
	donut = {
		length = 2.6,
		tracks = {
			{ prop = "rotZ", keys = { { 0, 0, "-" }, { 1, 360, "Sine InOut" }, { 2.6, 360, "-" } } },
		},
	},
	-- K:7339 Dragon: Roar Puff. Puffs up and lifts its head (no hop: biggest squishy).
	dragon = {
		length = 3,
		tracks = {
			{
				prop = "scale",
				keys = {
					{ 0, { 1, 1, 1 }, "-" },
					{ 0.4, { 1.12, 1.12, 1.12 }, "Back Out" },
					{ 0.8, { 1, 1, 1 }, "Sine Out" },
					{ 3, { 1, 1, 1 }, "-" },
				},
			},
			{ prop = "rotX", keys = { { 0, 0, "-" }, { 0.4, -10, "Quad Out" }, { 0.8, 0, "Sine InOut" } } },
		},
	},
	-- K:7411 MochiFox: Tail Spin. Hop-spin chasing its tail.
	mochi_fox = {
		length = 2.6,
		tracks = {
			{ prop = "rotY", keys = { { 0, 0, "-" }, { 0.8, -360, "Quad InOut" }, { 2.6, -360, "-" } } },
			{ prop = "posY", keys = { { 0, 0, "-" }, { 0.4, 0.4, "Quad Out" }, { 0.8, 0, "Quad In" } } },
		},
	},
	-- K:7462 StrawberryFrog: Double Hop. Big hop, small hop, squish on each landing.
	strawberry_frog = {
		length = 2.6,
		tracks = {
			{
				prop = "posY",
				keys = {
					{ 0, 0, "-" },
					{ 0.25, 0.9, "Quad Out" },
					{ 0.5, 0, "Quad In" },
					{ 0.7, 0.6, "Quad Out" },
					{ 0.95, 0, "Quad In" },
					{ 2.6, 0, "-" },
				},
			},
			{
				prop = "scale",
				keys = {
					{ 0, { 1, 1, 1 }, "-" },
					{ 0.45, { 1, 1, 1 }, "-" },
					{ 0.5, { 1.15, 0.85, 1.15 }, "Quad In" },
					{ 0.62, { 1, 1, 1 }, "Back Out" },
					{ 0.9, { 1, 1, 1 }, "-" },
					{ 0.95, { 1.12, 0.88, 1.12 }, "Quad In" },
					{ 1.1, { 1, 1, 1 }, "Back Out" },
				},
			},
		},
	},
	-- K:7576 BobaBear: Wobble Sip. Happy wobble like sipping boba.
	boba_bear = {
		length = 2.4,
		tracks = {
			{
				prop = "rotZ",
				keys = {
					{ 0, 0, "-" },
					{ 0.4, 6, "Sine InOut" },
					{ 0.8, -6, "Sine InOut" },
					{ 1.2, 0, "Sine InOut" },
					{ 2.4, 0, "-" },
				},
			},
			{ prop = "scaleY", keys = { { 0, 1, "-" }, { 0.6, 1.05, "Sine InOut" }, { 1.2, 1, "Sine InOut" } } },
		},
	},
	-- K:7637 PancakePup: Pancake Flip. Flips like a pancake in a pan.
	pancake_pup = {
		length = 3,
		tracks = {
			{
				prop = "posY",
				keys = { { 0, 0, "-" }, { 0.3, 1.4, "Quad Out" }, { 0.65, 0, "Quad In" }, { 3, 0, "-" } },
			},
			{ prop = "rotX", keys = { { 0, 0, "-" }, { 0.65, -360, "Sine InOut" }, { 3, -360, "-" } } },
		},
	},
	-- K:7693 CloudBunny: Float Bob. Floats up and down like a cloud.
	cloud_bunny = {
		length = 2.4,
		tracks = {
			{ prop = "posY", keys = { { 0, 0, "-" }, { 1.2, 0.8, "Sine InOut" }, { 2.4, 0, "Sine InOut" } } },
			{ prop = "rotZ", keys = { { 0, -3, "-" }, { 1.2, 3, "Sine InOut" }, { 2.4, -3, "Sine InOut" } } },
		},
	},
	-- K:7744 CupcakeAxolotl: Sprinkle Shimmy. Shimmies left and right.
	cupcake_axolotl = {
		length = 2.4,
		tracks = {
			{
				prop = "rotY",
				keys = { { 0, -15, "-" }, { 0.6, 15, "Sine InOut" }, { 1.2, -15, "Sine InOut" }, { 2.4, -15, "-" } },
			},
			{
				prop = "scale",
				keys = {
					{ 0, { 1, 1, 1 }, "-" },
					{ 0.3, { 1.05, 0.95, 1.05 }, "Sine InOut" },
					{ 0.6, { 1, 1, 1 }, "Sine InOut" },
					{ 0.9, { 1.05, 0.95, 1.05 }, "Sine InOut" },
					{ 1.2, { 1, 1, 1 }, "Sine InOut" },
				},
			},
		},
	},
}

-- qb1: the posY / rot stand-ins of the scale-only loops (same length and key times as K, the same eases).
local STAND_INS: { [string]: { Track } } = {
	-- Loaf Stretch: rises a little and tips its nose up as it stretches, then settles (K:6984's 0.7 / 1.4 s).
	kitty_bread = {
		{ prop = "posY", keys = { { 0, 0, "-" }, { 0.7, 0.35, "Sine InOut" }, { 1.4, 0, "Sine InOut" } } },
		{ prop = "rotX", keys = { { 0, 0, "-" }, { 0.7, -8, "Sine InOut" }, { 1.4, 0, "Sine InOut" } } },
	},
	-- Melt & Reset: slumps to one side as it melts, then springs back with a little hop (K:7142's 0.8 / 1.3 s).
	butter = {
		{ prop = "rotZ", keys = { { 0, 0, "-" }, { 0.8, 12, "Sine Out" }, { 1.3, 0, "Back Out" } } },
		{ prop = "posY", keys = { { 0, 0, "-" }, { 1.3, 0, "-" }, { 1.5, 0.3, "Quad Out" }, { 1.75, 0, "Quad In" } } },
	},
}

-- Module table

local ShowOffTracks = {}

-- Private

-- The number tracks of each loop as Timelines (ms), built once.
type Played = { prop: string, timeline: Timeline.Timeline<number> }
local played: { [string]: { Played } } = {}
for kind, loop in LOOPS do
	local list: { Played } = {}
	for _, track in STAND_INS[kind] or loop.tracks do
		if track.prop == "posY" or track.prop == "rotX" or track.prop == "rotY" or track.prop == "rotZ" then
			local keys = {}
			for _, key in track.keys do
				local ease = EASES[key[3]] or EASES["-"]
				table.insert(keys, { t_ms = key[1] * 1000, value = key[2], style = ease[1], dir = ease[2] })
			end
			local entry: Played = { prop = track.prop :: string, timeline = Timeline.new(keys :: any) }
			table.insert(list, entry)
		end
	end
	played[kind] = list
	table.freeze(loop)
end
table.freeze(LOOPS)

-- Public

function ShowOffTracks.ids(): { string }
	local ids = {}
	for kind in LOOPS do
		table.insert(ids, kind)
	end
	table.sort(ids)
	return ids
end

function ShowOffTracks.get(kind: string): Loop?
	return LOOPS[kind]
end

function ShowOffTracks.poseAt(kind: string, t: number, studs: number): (number, CFrame)
	local loop, tracks = LOOPS[kind], played[kind]
	if loop == nil or tracks == nil or #tracks == 0 then
		return 0, CFrame.identity
	end
	local ms = (t % loop.length) * 1000
	local lift, rx, ry, rz = 0, 0, 0, 0
	for _, track in tracks do
		local value = track.timeline:eval(ms)
		if track.prop == "posY" then
			lift = value * studs / COMMON_HALF
		elseif track.prop == "rotX" then
			rx = -value
		elseif track.prop == "rotY" then
			ry = value
		else
			rz = -value
		end
	end
	return lift, CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

return table.freeze(ShowOffTracks)
