--!strict
-- ThrowTracks_Test: unit tests for StarterPlayerScripts.Client.Anim.ThrowTracks (spec 2026-10-11 §3.5; the server
-- timing of spec 2026-10-10 §3.6). Server only (ServerStorage.UnitTest). Pure: no instances; ThrowController's own
-- windup records drive the timing cases, as they do in a duel.
-- Contract:
--   * the 9 tracks are the 3D Lab's THROWS verbatim (design: fp.js:143-155): dur, rel, the toy keys from TH0, the right
--     and the left hand's keys from RH0 / LH0 to RR / LR at dur, sling's and shove's sq keys (checked against a copy of
--     the design rows below); no other track has sq; cock is the last toy key before rel;
--   * the toy -> style map is THROW_STYLE (design: ults.js:9-14) for all 14 Catalog toys;
--   * keys are cosine-eased segments (design: fp.js:13, 19): on each key at its time, the plain mean of two keys at the
--     middle of their segment, row 1 before it and the last row after the end; the toy stops at rel; both hands start
--     from where they are (row 1 replaced) and end at REST_L / REST_R on dur; scaleAt is (1, 1, 1) without sq;
--   * timing fits the server: with ThrowStarted 0.1, 0.3 and 0.6 s after the press, track time never passes the cocked
--     key before the answer, and a late one leaves from the cock at releaseStart; with releaseAt known >= 70 ms ahead
--     the release frame lands on releaseStart (track time = rel + the time since releaseStart) for W 0.15, 0.18, 0.19
--     and through ThrowController's time-warp (rates 0.5 to 2.7); a strike that starts before the cock blends from
--     where it is; track time never goes back.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FRAME = 1 / 60
local EPS = 1e-6

-- A copy of the design rows (fp.js:144-155), typed from the design file, not from the module.
local TH0 = { 0, 0, -0.13, -0.5, 0, 0.25, 0 }
local RH0 = { 0, 0.14, -0.165, -0.465 }
local LH0 = { 0, -0.14, -0.165, -0.465 }
local RR = { 0.16, -0.23, -0.46 }
local LR = { -0.16, -0.23, -0.46 }
local function at(t: number, xyz: { number }): { number }
	return { t, xyz[1], xyz[2], xyz[3] }
end
type Rows = { { number } }
type Design = { dur: number, rel: number, toy: Rows, R: Rows, L: Rows, sq: Rows? }
local DESIGN: { [string]: Design } = {
	overhand = {
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
	},
	sidearm = {
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
	},
	spiral = {
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
	},
	lob = {
		dur = 0.85,
		rel = 0.32,
		toy = { TH0, { 0.18, 0.05, -0.42, -0.34, 0.6, 0.25, 0 }, { 0.32, 0.02, -0.06, -0.66, -0.4, 0.25, 0 } },
		R = { RH0, { 0.18, 0.14, -0.46, -0.32 }, { 0.32, 0.1, -0.1, -0.62 }, { 0.5, 0.12, 0.0, -0.6 }, at(0.85, RR) },
		L = { LH0, { 0.18, -0.18, -0.38, -0.4 }, { 0.4, -0.2, -0.3, -0.5 }, at(0.85, LR) },
	},
	glide = {
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
	},
	skip = {
		dur = 0.75,
		rel = 0.24,
		toy = { TH0, { 0.15, 0.26, -0.36, -0.32, 0, -0.8, 0.2 }, { 0.24, 0.04, -0.38, -0.72, 0, 0.4, 0 } },
		R = { RH0, { 0.15, 0.3, -0.4, -0.3 }, { 0.24, 0.08, -0.42, -0.66 }, { 0.42, -0.14, -0.4, -0.6 }, at(0.75, RR) },
		L = { LH0, { 0.15, -0.24, -0.26, -0.5 }, at(0.75, LR) },
	},
	sling = {
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
	},
	bounce = {
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
	},
	shove = {
		dur = 1.0,
		rel = 0.55,
		toy = { TH0, { 0.4, 0, -0.2, -0.34, 0, 0, 0 }, { 0.55, 0, -0.12, -0.86, 0, 0, 0 } },
		sq = { { 0, 1, 1, 1 }, { 0.38, 0.92, 1.1, 0.92 }, { 0.55, 1.08, 0.9, 1.1 }, { 0.6, 1, 1, 1 } },
		R = { RH0, { 0.4, 0.12, -0.22, -0.32 }, { 0.55, 0.1, -0.14, -0.78 }, at(1.0, RR) },
		L = { LH0, { 0.4, -0.12, -0.22, -0.32 }, { 0.55, -0.1, -0.14, -0.78 }, at(1.0, LR) },
	},
}
-- Each style's cock: its last toy key before rel.
local COCK = {
	overhand = 0.17,
	sidearm = 0.16,
	spiral = 0.20,
	lob = 0.18,
	glide = 0.14,
	skip = 0.15,
	sling = 0.45,
	bounce = 0.17,
	shove = 0.40,
}
-- THROW_STYLE (ults.js:9-14) by Catalog id (Birdie is "bird").
local STYLE_OF = {
	kitty_bread = "overhand",
	toast = "sidearm",
	banana = "spiral",
	butter = "skip",
	chocolate = "sidearm",
	bird = "glide",
	donut = "sidearm",
	dragon = "shove",
	mochi_fox = "sling",
	strawberry_frog = "bounce",
	boba_bear = "lob",
	pancake_pup = "sidearm",
	cloud_bunny = "lob",
	cupcake_axolotl = "lob",
}

return function(t: Context)
	local ThrowTracks = t.requireClient("Anim/ThrowTracks")
	local ThrowController = t.requireClient("Controllers/ThrowController")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local STRIKE = Config.Anim.throw.releaseSnapMs / 1000

	local function close(a: Vector3, b: Vector3, tolerance: number?): boolean
		return (a - b).Magnitude <= (tolerance or 1e-5)
	end

	local function rowsEqual(name: string, got: Rows, want: Rows)
		if #got ~= #want then
			error(`{name}: {#got} rows, the design has {#want}`)
		end
		for i, row in want do
			for j, value in row do
				if math.abs(got[i][j] - value) > EPS then
					error(`{name} row {i} value {j}: {got[i][j]}, the design has {value}`)
				end
			end
		end
	end

	local function v3(row: { number }, from: number): Vector3
		return Vector3.new(row[from], row[from + 1], row[from + 2])
	end

	t.test("the 9 tracks are the design's THROWS verbatim (dur, rel, toy, R, L, sq); cock before rel", function()
		local names = ThrowTracks.styles()
		expect.equal(#names, 9)
		for _, name in names do
			local want = DESIGN[name]
			expect.truthy(want ~= nil)
			local track = ThrowTracks.get(name)
			expect.equal(track.name, name)
			expect.near(track.dur, want.dur, EPS)
			expect.near(track.rel, want.rel, EPS)
			rowsEqual(name .. " toy", track.toy, want.toy)
			rowsEqual(name .. " R", track.R, want.R)
			rowsEqual(name .. " L", track.L, want.L)
			if want.sq then
				rowsEqual(name .. " sq", track.sq :: Rows, want.sq)
			else
				expect.equal(track.sq, nil)
			end
			expect.near(track.cock, COCK[name], EPS)
		end
	end)

	t.test("the toy -> style map is THROW_STYLE for all 14 Catalog toys", function()
		local count = 0
		for _, def in Catalog.list() do
			count += 1
			expect.equal(ThrowTracks.styleOf(def.id), STYLE_OF[def.id])
		end
		expect.equal(count, 14)
		expect.equal(ThrowTracks.styleOf("no_such_toy"), "overhand") -- anything else throws overhand
	end)

	t.test(
		"cosine-eased keys: on each key, the mean at a segment's middle, the first row before, the last after",
		function()
			for _, name in ThrowTracks.styles() do
				local track = ThrowTracks.get(name)
				local want = DESIGN[name]
				-- The toy: on each key; past rel it stays on the release key.
				for _, row in want.toy do
					local pos, rot = ThrowTracks.toyAt(track, row[1])
					expect.truthy(close(pos, v3(row, 2)) and close(rot, v3(row, 5)))
				end
				local last = want.toy[#want.toy]
				expect.truthy(close((ThrowTracks.toyAt(track, track.dur)), v3(last, 2)))
				expect.truthy(close((ThrowTracks.toyAt(track, -1)), v3(TH0, 2)))
				-- ease(0.5) = 0.5: the middle of a segment is the plain mean of its two keys.
				local a, b = want.toy[1], want.toy[2]
				local mid = ThrowTracks.toyAt(track, (a[1] + b[1]) / 2)
				expect.truthy(close(mid, (v3(a, 2) + v3(b, 2)) / 2))
				-- A quarter in, cosine in-out: 0.5 - 0.5·cos(π/4) of the way.
				local quarter = ThrowTracks.toyAt(track, a[1] + (b[1] - a[1]) / 4)
				local u = 0.5 - 0.5 * math.cos(math.pi / 4)
				expect.truthy(close(quarter, v3(a, 2):Lerp(v3(b, 2), u)))
			end
		end
	)

	t.test("both hands start from where they are and end at REST_L / REST_R on dur", function()
		local fromL, fromR = Vector3.new(-0.21, -0.17, -0.47), Vector3.new(0.19, -0.16, -0.48)
		for _, name in ThrowTracks.styles() do
			local track = ThrowTracks.get(name)
			local want = DESIGN[name]
			local l, r = ThrowTracks.handsAt(track, 0, fromL, fromR)
			expect.truthy(close(l, fromL) and close(r, fromR)) -- row 1 is replaced: nothing snaps
			for i = 2, #want.R do
				local _, right = ThrowTracks.handsAt(track, want.R[i][1], fromL, fromR)
				expect.truthy(close(right, v3(want.R[i], 2)))
			end
			for i = 2, #want.L do
				local left = ThrowTracks.handsAt(track, want.L[i][1], fromL, fromR)
				expect.truthy(close(left, v3(want.L[i], 2)))
			end
			l, r = ThrowTracks.handsAt(track, track.dur + 1, fromL, fromR)
			expect.truthy(close(l, Vector3.new(LR[1], LR[2], LR[3])) and close(r, Vector3.new(RR[1], RR[2], RR[3])))
			-- The scale track: sling and shove only.
			if want.sq then
				for _, row in want.sq do
					expect.truthy(close(ThrowTracks.scaleAt(track, row[1]), v3(row, 2)))
				end
			else
				expect.truthy(close(ThrowTracks.scaleAt(track, track.rel), Vector3.one))
			end
		end
	end)

	-- One local throw through ThrowController's own windup record: the answer (releaseAt) arrives at `answerAt`.
	-- Returns the frames: { now, t, releaseStart } (server time = the clock, press at 0).
	type Frame = { now: number, t: number, releaseStart: number? }
	local function simulate(name: string, W: number, answerAt: number, releaseAt: number): { Frame }
		local track = ThrowTracks.get(name)
		local w = ThrowController.newWindup(W, W + Config.Anim.throw.cockedHoldMaxMs / 1000, false)
		local clock = ThrowTracks.newClock()
		local frames: { Frame } = {}
		local now = 0
		for _ = 1, 120 do
			now += FRAME
			if now >= answerAt and w.releaseAt == nil and not w.cancelled then
				w.releaseAt = releaseAt
			end
			ThrowController.stepWindup(w, FRAME, now)
			local tau, windup, knownAt, releaseStart, cancelled = ThrowController.windupValues(w)
			if cancelled then
				break
			end
			local trackTime = ThrowTracks.advance(clock, track, tau, windup, knownAt, now)
			table.insert(frames, { now = now, t = trackTime, releaseStart = releaseStart })
			if trackTime >= track.dur then
				break
			end
		end
		return frames
	end

	t.test("a late answer: track time never passes the cocked key before releaseStart", function()
		for _, name in ThrowTracks.styles() do
			local track = ThrowTracks.get(name)
			for _, W in { 0.15, 0.18, 0.19 } do
				for _, late in { 0.1, 0.3, 0.6 } do
					local frames = simulate(name, W, late, W)
					local released = false
					for _, frame in frames do
						-- Until the answer is known the arm holds the cock: never a stalled, fully stretched arm.
						if frame.now < late and frame.t > track.cock + EPS then
							error(`{name} W {W} late {late}: past the cock at {frame.now} before the answer`)
						end
						-- A late answer (releaseAt already passed): the toy leaves at releaseStart from the cock.
						if frame.releaseStart ~= nil and not released then
							released = true
							if late > W then
								expect.near(frame.t, track.cock, EPS)
							end
						end
					end
					expect.truthy(released)
				end
			end
		end
	end)

	t.test("on time: the release frame lands on releaseStart, through the time-warp (rates 0.5 to 2.7)", function()
		local rates = { slow = false, fast = false }
		for _, name in ThrowTracks.styles() do
			local track = ThrowTracks.get(name)
			for _, W in { 0.15, 0.18, 0.19 } do
				-- The answer on the first frame (tau 0); releaseAt 70 ms ahead (the fastest warp a 70-ms lead allows:
				-- W / 0.07, 2.1-2.7; the clamp's 3 needs a lead under 70 ms with W <= 0.19), at W, or far (the clamp's 0.5).
				for _, releaseAt in { FRAME + STRIKE, W, 2.5 * W } do
					local rate = math.clamp(W / (releaseAt - FRAME), 0.5, 3)
					rates.slow = rates.slow or rate <= 0.5
					rates.fast = rates.fast or rate >= 2
					local frames = simulate(name, W, 0, releaseAt)
					local found = false
					for i, frame in frames do
						if frame.releaseStart ~= nil then
							expect.near(frame.releaseStart, releaseAt, 1e-9)
							-- The release frame: track time = rel + the time since releaseStart (on the key at releaseAt).
							expect.near(frame.t, track.rel + (frame.now - releaseAt), 1e-6)
							for j = 1, i - 1 do
								expect.truthy(frames[j].t < track.rel)
							end
							found = true
							break
						end
					end
					expect.truthy(found)
				end
			end
		end
		expect.truthy(rates.slow and rates.fast)
	end)

	t.test("a strike that starts before the cock blends from where it is; track time never goes back", function()
		local blended = 0
		for _, name in ThrowTracks.styles() do
			local track = ThrowTracks.get(name)
			for _, W in { 0.15, 0.19 } do
				for _, releaseAt in { FRAME + STRIKE, W, 2.5 * W } do
					local frames = simulate(name, W, 0, releaseAt)
					local strikeAt = releaseAt - STRIKE
					for i = 2, #frames do
						local a, b = frames[i - 1], frames[i]
						expect.truthy(b.t >= a.t) -- never back
						if a.now < strikeAt and b.now >= strikeAt and a.t < track.cock - 1e-4 then
							blended += 1
							-- The first strike frame moves from where it was, never jumps to the cock first.
							local most = (track.rel - a.t) * math.min((b.now - strikeAt) / STRIKE, 1) + 1e-6
							expect.truthy(b.t - a.t <= most)
						end
					end
				end
			end
		end
		expect.truthy(blended > 0)
		-- Random calls (tau back and forth, releaseAt appearing, time jumps) never move track time back.
		local rng = Random.new(7)
		for _ = 1, 50 do
			local track = ThrowTracks.get(ThrowTracks.styles()[rng:NextInteger(1, 9)])
			local clock = ThrowTracks.newClock()
			local last, now = 0, 0
			local releaseAt: number? = nil
			for _ = 1, 60 do
				now += rng:NextNumber(0, 0.05)
				if releaseAt == nil and rng:NextNumber() < 0.1 then
					releaseAt = now + rng:NextNumber(-0.1, 0.3)
				end
				local tau = if rng:NextNumber() < 0.1 then nil else rng:NextNumber(0, 0.2)
				local value = ThrowTracks.advance(clock, track, tau, 0.18, releaseAt, now)
				expect.truthy(value >= last and value <= track.dur)
				last = value
			end
		end
	end)
end
