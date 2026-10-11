--!strict
-- JellyRipple_Test: the jelly ripple's wave numbers, path B and the skin swap (StarterPlayerScripts.Client.Anim.JellySkin
-- with Anim/PadDent, and the pure parts of Controllers/JellyRippleController). Server only (ServerStorage.UnitTest).
-- Pure: Config values, fixed dt 1/60, the High 6 × 8 big face of B_Wall1 from JellySkin.arenaLayout; no instances.
-- Contract (DESIGN §18.3.4, §18.3.5, §18.3.8, §18.11 JellyRipple_Test):
--   * a centre hit (r = 1.0, on the vertex next to the face centre: rows sit at 0.25 + 0.5k) dents 1.5-1.85, rebounds
--     0.8-1.2, is still (every |h| < 0.01) after faceSeconds, and its bulge passes 2.5 studs out within 0.5 s (the
--     values of the user's tests of 2026-10-07);
--   * no vertex half-period under 1/6 s while |h| > 0.02 (<= 3 Hz, §9.12, §18.1 #4), for a centre and a corner hit.
--     Reading: a half-period is the time between two zero crossings of a vertex whose lobe between them peaks above
--     0.02; the first dent from rest starts at the impulse, not at a crossing, so it is not one. The corner hit is the
--     DESIGN table's near-corner case, 0.75 studs in from both edges (its dent is about -1.54);
--   * no blow-up over 10 s at dt 1/20; the faceSeconds snap leaves < 0.01 (Rush: rushFaceSeconds);
--   * ReducedMotion: h never above +0.002, a dent <= 0.6 × the normal dent, still within 0.6 s;
--   * path B: the squash peaks at about `amount` (± 15%) 70-120 ms after the hit and is at rest within faceSeconds;
--     under ReducedMotion it rises and falls without a wobble; hits along two axes add up within maxAmount (all axes
--     together); ReducedMotion turning on mid-wobble calms it (Wobble:calm: no swing past rest, at rest within 1 s);
--   * the whole-piece jiggle (path A, user test 2026-10-07): its first swing peaks at about the amount (± 15%) about
--     100 ms after the kick, it swings at <= 2.5 Hz, is visibly moving (|x| > 0.01) for 1.2-1.8 s and rests within
--     faceSeconds (Rush too); hits add up and |x| stays <= maxAmount (the backstop's cap is smaller); the map keeps
--     the bottom row on the floor, the lead face on its plane (it moves only with its dent; a later kick on another
--     axis too), the volume, and a block's height; every jiggled vertex stays inside the bounds anchors;
--     ReducedMotion: no jiggle (none is kicked, and one running stops at the next step);
--   * dent + jiggle as drawn (a Sim whose IO records every vertex): no vertex component of the whole piece swings
--     faster than 3 Hz above 0.02, for one hit (the dent test's cases plus a side face, a block face and the wall
--     top) and for a second hit on another face while the piece still moves (the review's failing cases of
--     2026-10-07: the opposite face, the top then the front, the front then the top, the end then the front);
--   * the lead face: while a piece moves only its lead face dents and a hit on another face only kicks the jiggle; a
--     jiggling top hit leads no face; the lead is chosen anew once the piece rests; jiggle-free hits dent any face
--     and lead nothing;
--   * the swap (Sim): a piece swaps in once, at its first hit, and shows its real parts again exactly when all its
--     faces have slept and its jiggle rests; a 7th rippling face snaps the oldest to rest; a 5th jiggling piece stops
--     the oldest jiggle and keeps its drawn shape until its write at rest, which comes within the budget;
--     whole-piece writes stay within the jiggle budget (writesPerFrame at High, writesPerFrameLow at Low; at least
--     one piece per step, the longest-unwritten first); a piece left out of a step is still drawn with one map
--     (review 2026-10-07); a face over the write budget (every other frame with both frames' dt) stays within 0.02
--     studs of a face stepped every frame at 20 and 30 fps (no lost time);
--   * camera guard (reading of §18.3.4 S2): blocksCamera is true for a wall holding the camera in front of it or one
--     the camera's line passes through, false for a wall beside the line, far past the camera, ahead of the player, or
--     in first person;
--   * JellyRippleController idle: offsetAt is 0, counts() shows no skin, clear() is safe without init().

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FRAME = 1 / 60
local CENTRE = { 0, 0.25 } -- the vertex next to the centre of the 6 × 8 face
local CORNER = { -2.25, -3.25 } -- 0.75 studs in from both edges (the DESIGN table's near-corner case)
local LOBE_PEAK = 0.02
local MIN_HALF_PERIOD = 1 / 6 -- 3 Hz

return function(t: Context)
	local expect = t.expect
	local JellySkin = t.requireClient("Anim/JellySkin")
	local PadDent = t.requireClient("Anim/PadDent")
	local Config = t.requireShared("Config")
	local RIPPLE = Config.Anim.jellyRipple
	local PATH_B = RIPPLE.pathB

	local layout = JellySkin.arenaLayout("High")
	local wallPiece: any = nil
	for _, piece in layout.pieces do
		if piece.name == "B_Wall1" then
			wallPiece = piece
		end
	end
	local bigFace = layout.faces[layout.faceOf[wallPiece.index]["+Z"]]

	-- A dent on the big face, hit at (u, v) by a throw of radius r (or a Rush lane).
	local function hitDent(u: number, v: number, r: number?, isRush: boolean?, isReduced: boolean?): any
		local dent = PadDent.new(JellySkin.faceGrid(bigFace), JellySkin.dentParams())
		local speed, reach = JellySkin.impulseFor(r or 1.0, isRush == true, isReduced == true)
		dent:impulse(u, v, speed, reach)
		return dent
	end

	local function nearestVertex(dent: any, u: number, v: number): number
		local best, bestDistance = 1, math.huge
		for index = 1, dent:size() do
			local d = (dent.xs[index] - u) ^ 2 + (dent.zs[index] - v) ^ 2
			if d < bestDistance then
				best, bestDistance = index, d
			end
		end
		return best
	end

	local function largest(dent: any): number
		local m = 0
		for index = 1, dent:size() do
			m = math.max(m, math.abs(dent:height(index)))
		end
		return m
	end

	-- Steps `dent` for `seconds` at dt, calling onFrame(time) after each step.
	local function run(dent: any, seconds: number, dt: number, isReduced: boolean?, onFrame: ((number) -> ())?)
		local frames = math.floor(seconds / dt + 0.5)
		for frame = 1, frames do
			dent:step(dt, {}, isReduced == true)
			if onFrame then
				onFrame(frame * dt)
			end
		end
	end

	-- The shortest half-period (see the header) over every vertex, and the peak of that lobe.
	local function shortestHalfPeriod(dent: any, seconds: number): (number, number)
		local n = dent:size()
		local previous = table.create(n, 0)
		local lastCross: { number? } = {}
		local peak = table.create(n, 0)
		local shortest, shortestPeak = math.huge, 0
		run(dent, seconds, FRAME, false, function(now: number)
			for index = 1, n do
				local h = dent:height(index)
				local p = previous[index]
				if (p < 0 and h >= 0) or (p > 0 and h <= 0) then
					local crossing = now - FRAME + FRAME * (p / (p - h))
					local last = lastCross[index]
					if last ~= nil and peak[index] > LOBE_PEAK and crossing - last < shortest then
						shortest, shortestPeak = crossing - last, peak[index]
					end
					lastCross[index] = crossing
					peak[index] = 0
				end
				peak[index] = math.max(peak[index], math.abs(h))
				previous[index] = h
			end
		end)
		return shortest, shortestPeak
	end

	-- Path A: the wave numbers ------------------------------------------------------------------------------------

	t.test(
		"a centre hit dents 1.5-1.85, rebounds 0.8-1.2, is still after faceSeconds; the bulge reaches 2.5 studs within 0.5 s",
		function()
			local dent = hitDent(CENTRE[1], CENTRE[2])
			local hit = nearestVertex(dent, CENTRE[1], CENTRE[2])
			local deepest, rebound, dipped = 0, 0, false
			local crestAt, crest = 0, 0
			local stillAfter = 0
			run(dent, RIPPLE.faceSeconds + 0.3, FRAME, false, function(now: number)
				for index = 1, dent:size() do
					local h = dent:height(index)
					deepest = math.min(deepest, h)
					local d = math.sqrt((dent.xs[index] - CENTRE[1]) ^ 2 + (dent.zs[index] - CENTRE[2]) ^ 2)
					if math.abs(d - 2.5) <= 0.15 and math.abs(h) > crest then
						crest, crestAt = math.abs(h), now
					end
				end
				local h = dent:height(hit)
				if h < -0.05 then
					dipped = true
				end
				if dipped then
					rebound = math.max(rebound, h)
				end
				if now > RIPPLE.faceSeconds + 1e-9 then
					stillAfter = math.max(stillAfter, largest(dent))
				end
			end)
			if -deepest < 1.5 or -deepest > 1.85 then
				error(`dent {-deepest} not in [1.5, 1.85]`)
			end
			if rebound < 0.8 or rebound > 1.2 then
				error(`rebound {rebound} not in [0.8, 1.2]`)
			end
			expect.truthy(stillAfter < 0.01)
			if crestAt <= 0 or crestAt > 0.5 then
				error(`the bulge reached 2.5 studs at {crestAt} s, not within 0.5 s`)
			end
		end
	)

	t.test("no vertex swings faster than 3 Hz above 0.02 (centre and corner hits)", function()
		for _, hit in { CENTRE, CORNER } do
			local shortest, peak = shortestHalfPeriod(hitDent(hit[1], hit[2]), 3)
			if shortest < MIN_HALF_PERIOD then
				error(`hit ({hit[1]}, {hit[2]}): a half-period of {shortest} s (peak {peak}) is under 1/6 s`)
			end
		end
	end)

	t.test("the near-corner hit dents about -1.54 (stronger tuning, user tests 2026-10-07)", function()
		local dent = hitDent(CORNER[1], CORNER[2])
		local deepest = 0
		run(dent, 0.5, FRAME, false, function()
			for index = 1, dent:size() do
				deepest = math.min(deepest, dent:height(index))
			end
		end)
		expect.near(deepest, -1.54, 0.05)
	end)

	t.test("no blow-up over 10 s at dt 1/20; the faceSeconds snap leaves < 0.01", function()
		local lo, hi = -RIPPLE.clampIn - 1e-9, RIPPLE.clampOut + 1e-9
		for _, case in { { r = 1.0, rush = false }, { r = 1.4, rush = false }, { r = 1.0, rush = true } } do
			local dent = hitDent(CENTRE[1], CENTRE[2], case.r, case.rush)
			run(dent, 10, 1 / 20, false, function()
				for index = 1, dent:size() do
					local h = dent:height(index)
					if not (h == h and h >= lo and h <= hi) then
						error(`height {h} out of bounds`)
					end
				end
			end)
			expect.truthy(largest(dent) < 0.01)
			-- What the snap to rest hides: the largest |h| left when faceSeconds (Rush: rushFaceSeconds) is up.
			local seconds = if case.rush then RIPPLE.rushFaceSeconds else RIPPLE.faceSeconds
			local again = hitDent(CENTRE[1], CENTRE[2], case.r, case.rush)
			run(again, seconds, FRAME)
			expect.truthy(largest(again) < 0.01)
		end
		-- Two quick hits on one face add up and still settle within the clamps.
		local both = hitDent(CENTRE[1], CENTRE[2])
		run(both, 0.1, FRAME)
		local speed, reach = JellySkin.impulseFor(1.4, false, false)
		both:impulse(1, -1, speed, reach)
		run(both, RIPPLE.faceSeconds, FRAME, false, function()
			for index = 1, both:size() do
				local h = both:height(index)
				expect.truthy(h >= lo and h <= hi)
			end
		end)
		expect.truthy(largest(both) < 0.01)
	end)

	t.test("ReducedMotion: no overshoot, a dent <= 0.6 × the normal one, still within 0.6 s", function()
		local normal = hitDent(CENTRE[1], CENTRE[2])
		local normalDent = 0
		run(normal, 1, FRAME, false, function()
			for index = 1, normal:size() do
				normalDent = math.min(normalDent, normal:height(index))
			end
		end)
		local dent = hitDent(CENTRE[1], CENTRE[2], 1.0, false, true)
		local deepest, highest, lateLargest = 0, 0, 0
		run(dent, 2, FRAME, true, function(now: number)
			for index = 1, dent:size() do
				local h = dent:height(index)
				deepest = math.min(deepest, h)
				highest = math.max(highest, h)
			end
			if now >= 0.6 - 1e-9 then
				lateLargest = math.max(lateLargest, largest(dent))
			end
		end)
		expect.truthy(highest <= 0.002)
		expect.truthy(deepest < 0)
		expect.truthy(-deepest <= 0.6 * -normalDent)
		expect.truthy(lateLargest < 0.01)
	end)

	-- Path B ------------------------------------------------------------------------------------------------------

	t.test("path B peaks at about amount (± 15%) 70-120 ms after the hit and rests within faceSeconds", function()
		for _, case in
			{ { kind = "wall", rush = false }, { kind = "gumdrop", rush = false }, { kind = "block", rush = true } }
		do
			local amount = JellySkin.pathBAmount(case.kind, case.rush, false)
			expect.truthy(amount <= PATH_B.maxAmount)
			local wobble = JellySkin.newWobble()
			wobble:hit("Z", amount, false)
			local peak, peakAt, settledAt = 0, 0, nil :: number?
			for frame = 1, math.floor(RIPPLE.faceSeconds / FRAME + 0.5) do
				wobble:step(FRAME)
				local x = wobble:amounts().Z
				if math.abs(x) > peak then
					peak, peakAt = math.abs(x), frame * FRAME
				end
				if settledAt == nil and wobble:settled() then
					settledAt = frame * FRAME
				end
			end
			if math.abs(peak - amount) > 0.15 * amount then
				error(`{case.kind}: peak {peak} is not within 15% of {amount}`)
			end
			if peakAt < 0.07 - 1e-9 or peakAt > 0.12 + 1e-9 then
				error(`{case.kind}: peak at {peakAt} s, not in [0.07, 0.12]`)
			end
			expect.truthy(settledAt ~= nil and (settledAt :: number) <= RIPPLE.faceSeconds + 1e-9)
			-- The squash keeps the volume (c = 1 + x, the bulge c^-share up and c^-(1 - share) across).
			for _, share in { 0.5, RIPPLE.jiggle.verticalShare } do
				local S = JellySkin.wobbleScale(Vector3.new(0, 0, -amount), share)
				expect.near(S.X * S.Y * S.Z, 1, 1e-5) -- Vector3 holds float32
			end
		end
		-- The amounts (the jiggle's feel since the user test of 2026-10-07): walls and blocks 0.18, gumdrops 0.2, ×
		-- the throw's radius scale, Rush × rushScale, ReducedMotion × reducedScale, at most maxAmount.
		expect.near(JellySkin.pathBAmount("wall", false, false), PATH_B.amount, 1e-9)
		expect.near(JellySkin.pathBAmount("gumdrop", false, false), PATH_B.roundAmount, 1e-9)
		expect.near(JellySkin.pathBAmount("gumdrop", true, false), PATH_B.maxAmount, 1e-9)
		expect.near(JellySkin.pathBAmount("wall", true, false), PATH_B.amount * PATH_B.rushScale, 1e-9)
		expect.near(JellySkin.pathBAmount("wall", false, true), PATH_B.amount * PATH_B.reducedScale, 1e-9)
		expect.near(JellySkin.pathBAmount("wall", false, false, 1.4), PATH_B.amount * RIPPLE.impulseScaleMax, 1e-9)
		expect.near(JellySkin.pathBAmount("wall", false, false, 0.5), PATH_B.amount * RIPPLE.impulseScaleMin, 1e-9)
	end)

	t.test("path B under ReducedMotion rises and falls without a wobble", function()
		local amount = JellySkin.pathBAmount("gumdrop", false, true)
		local wobble = JellySkin.newWobble()
		wobble:hit("Y", amount, true)
		local deepest, highest = 0, 0
		for _ = 1, 90 do
			wobble:step(FRAME)
			local x = wobble:amounts().Y
			deepest = math.min(deepest, x)
			highest = math.max(highest, x)
		end
		expect.truthy(deepest < -0.01)
		expect.equal(highest, 0)
		expect.truthy(wobble:settled())
	end)

	t.test("path B hits on two axes add up, within maxAmount together, and rest together", function()
		local wobble = JellySkin.newWobble()
		wobble:hit("X", PATH_B.maxAmount, false)
		wobble:hit("X", PATH_B.maxAmount, false)
		wobble:hit("Z", PATH_B.amount, false)
		local worst, both = 0, false
		for _ = 1, math.floor(RIPPLE.faceSeconds / FRAME + 0.5) do
			wobble:step(FRAME)
			local x = wobble:amounts()
			worst = math.max(worst, x.Magnitude)
			both = both or (math.abs(x.X) > 0.01 and math.abs(x.Z) > 0.01)
		end
		expect.truthy(both)
		expect.truthy(worst <= PATH_B.maxAmount + 1e-6) -- Vector3 holds float32
		expect.truthy(wobble:settled())
		expect.equal(wobble:scale(), Vector3.one)
	end)

	-- The whole-piece jiggle (path A) ---------------------------------------------------------------------------

	local JIGGLE = RIPPLE.jiggle
	local blockPiece: any = nil
	for _, piece in layout.pieces do
		if piece.name == "B_Block1" then
			blockPiece = piece
		end
	end

	-- Kicks a jiggle like a hit on `face` of a piece of `kind` (amount from jiggleAmount unless given).
	local function kicked(kind: string, axis: string, side: number, amount: number): any
		local wobble = JellySkin.newWobble(JellySkin.jiggleSpec(kind))
		wobble:hit(axis, amount, false, side)
		return wobble
	end

	t.test(
		"jiggle amounts: 0.18 × the radius scale, Rush 0.28, the backstop 0.06, none under ReducedMotion",
		function()
			expect.near(JellySkin.jiggleAmount("wall", 1.0, false, false), JIGGLE.amount, 1e-9)
			expect.near(
				JellySkin.jiggleAmount("block", 1.4, false, false),
				JIGGLE.amount * RIPPLE.impulseScaleMax,
				1e-9
			)
			expect.near(JellySkin.jiggleAmount("wall", 0.8, false, false), JIGGLE.amount * RIPPLE.impulseScaleMin, 1e-9)
			expect.near(JellySkin.jiggleAmount("wall", nil, true, false), JIGGLE.rushAmount, 1e-9)
			expect.near(JellySkin.jiggleAmount("backstop", 1.0, false, false), JIGGLE.backstopAmount, 1e-9)
			for _, kind in { "wall", "block", "backstop" } do
				expect.equal(JellySkin.jiggleAmount(kind, 1.0, false, true), 0)
				expect.equal(JellySkin.jiggleAmount(kind, 1.0, true, true), 0)
				expect.truthy(JellySkin.jiggleAmount(kind, 1.4, true, false) <= JellySkin.jiggleSpec(kind).maxAmount)
			end
			-- The springs: <= 2.5 Hz; the backstop's cap is maxAmount × backstopAmount / amount; a block keeps its height.
			expect.truthy(JIGGLE.omega / (2 * math.pi) <= 2.5)
			expect.near(
				JellySkin.jiggleSpec("backstop").maxAmount,
				JIGGLE.maxAmount * JIGGLE.backstopAmount / JIGGLE.amount,
				1e-9
			)
			expect.truthy(JellySkin.jiggleSpec("block").keepHeight)
			expect.falsy(JellySkin.jiggleSpec("wall").keepHeight)
		end
	)

	t.test(
		"jiggle: the first swing peaks at about the amount ~100 ms in, swings <= 2.5 Hz, moves 1.2-1.8 s, rests by faceSeconds",
		function()
			for _, case in
				{
					{ kind = "wall", r = 1.0, rush = false },
					{ kind = "block", r = 1.4, rush = false },
					{ kind = "wall", r = 1.0, rush = true },
					{ kind = "backstop", r = 1.0, rush = false },
				}
			do
				local amount = JellySkin.jiggleAmount(case.kind, case.r, case.rush, false)
				local wobble = kicked(case.kind, "Z", 1, amount)
				local peak, peakAt, movingUntil, settledAt = 0, 0, 0, nil :: number?
				local previous, lobe, lastCross = 0, 0, nil :: number?
				local shortest = math.huge
				local seconds = if case.rush then RIPPLE.rushFaceSeconds else RIPPLE.faceSeconds
				for frame = 1, math.floor(seconds / FRAME + 0.5) do
					wobble:step(FRAME)
					local now = frame * FRAME
					local x = wobble:amounts().Z
					if math.abs(x) > peak then
						peak, peakAt = math.abs(x), now
					end
					if math.abs(x) > 0.01 then
						movingUntil = now
					end
					if settledAt == nil and wobble:settled() then
						settledAt = now
					end
					-- Half-periods between zero crossings around lobes above 0.002 (the settle to exactly 0 is not one).
					if x ~= 0 and ((previous < 0 and x >= 0) or (previous > 0 and x <= 0)) then
						local crossing = now - FRAME + FRAME * (previous / (previous - x))
						if lastCross ~= nil and lobe > 0.002 then
							shortest = math.min(shortest, crossing - lastCross)
						end
						lastCross, lobe = crossing, 0
					end
					lobe = math.max(lobe, math.abs(x))
					previous = x
				end
				if math.abs(peak - amount) > 0.15 * amount then
					error(`{case.kind}: peak {peak} is not within 15% of {amount}`)
				end
				if peakAt < 0.07 - 1e-9 or peakAt > 0.13 + 1e-9 then
					error(`{case.kind}: peak at {peakAt} s, not in [0.07, 0.13]`)
				end
				if shortest < 1 / (2 * 2.5) - 1e-9 then
					error(`{case.kind}: a half-period of {shortest} s is faster than 2.5 Hz`)
				end
				expect.truthy(settledAt ~= nil and (settledAt :: number) <= seconds + 1e-9)
				if case.kind ~= "backstop" and (movingUntil < 1.2 or movingUntil > 1.8) then
					error(`{case.kind}: |x| > 0.01 until {movingUntil} s, not 1.2-1.8 s`)
				end
			end
		end
	)

	t.test("jiggle: hits add up and |x| stays <= maxAmount over all axes (the backstop's cap is smaller)", function()
		for _, kind in { "wall", "backstop" } do
			local spec = JellySkin.jiggleSpec(kind)
			local amount = JellySkin.jiggleAmount(kind, 1.4, false, false)
			local single = kicked(kind, "Z", 1, amount)
			local several = kicked(kind, "Z", 1, amount)
			local singlePeak, worst = 0, 0
			for frame = 1, math.floor(RIPPLE.faceSeconds / FRAME + 0.5) do
				if frame == 3 or frame == 5 then
					several:hit("Z", amount, false, 1)
				end
				if frame == 4 then
					several:hit("X", amount, false, -1)
				end
				single:step(FRAME)
				several:step(FRAME)
				singlePeak = math.max(singlePeak, single:amounts().Magnitude)
				worst = math.max(worst, several:amounts().Magnitude)
			end
			expect.truthy(worst > singlePeak + 0.01) -- they add up ...
			expect.truthy(worst <= spec.maxAmount + 1e-6) -- ... to the cap (Vector3 holds float32)
			expect.truthy(several:settled()) -- and still rest by faceSeconds after the last one
		end
	end)

	t.test(
		"the jiggle map: bottom row on the floor, the lead face on its plane (a later kick on another axis too), "
			.. "volume kept, a block keeps its height",
		function()
			for _, case in
				{
					{ piece = wallPiece, axis = "Z", side = 1, face = "+Z" },
					{ piece = wallPiece, axis = "X", side = -1, face = "-X" },
					{ piece = blockPiece, axis = "Z", side = -1, face = "-Z" },
					{ piece = wallPiece, axis = "Z", side = 1, face = "+Z", second = "X" },
					{ piece = blockPiece, axis = "Z", side = -1, face = "-Z", second = "X" },
				}
			do
				local piece = case.piece
				local amount = JellySkin.jiggleSpec(piece.kind).maxAmount
				local wobble = kicked(piece.kind, case.axis, case.side, amount)
				local hitFace = layout.faces[layout.faceOf[piece.index][case.face]]
				local unit = hitFace.normal
				local plane = hitFace.center:Dot(unit)
				local sawSquash, sawStretch = false, false
				for frame = 1, 40 do
					if case.second and frame == 6 then
						-- A kick on another axis (a hit on another face of the moving piece): its bulge must not move
						-- the lead face's plane either (it scales about it), and the lead's pivot stays.
						wobble:hit(case.second, amount / 2, false, 1)
					end
					wobble:step(FRAME)
					local K, T = wobble:map(piece.base, piece.size)
					local x = wobble:amounts():Dot(Vector3.new(math.abs(unit.X), math.abs(unit.Y), math.abs(unit.Z)))
					sawSquash = sawSquash or x < -0.1
					sawStretch = sawStretch or x > 0.03
					if piece.kind == "block" then
						expect.near(K.Y, 1, 1e-6)
						expect.near(T.Y, 0, 1e-5)
					else
						expect.near(K.X * K.Y * K.Z, 1, 1e-4) -- one axis moving: the volume is kept
					end
					for i = piece.first, piece.first + piece.count - 1 do
						local q = Vector3.new(layout.px[i], layout.py[i], layout.pz[i])
						local moved = JellySkin.jiggledPoint(q, K, T)
						if math.abs(q.Y - piece.base.Y) < 1e-9 then
							expect.near(moved.Y, piece.base.Y, 1e-4) -- the bottom row never lifts or sinks
						end
						expect.truthy(moved.Y >= piece.base.Y - 1e-4)
						if math.abs(q:Dot(unit) - plane) < 1e-9 then
							expect.near(moved:Dot(unit), plane, 1e-4) -- the hit face only moves with its dent
						end
					end
				end
				expect.truthy(sawSquash and sawStretch)
				wobble:reset()
				local K, T = wobble:map(piece.base, piece.size)
				expect.equal(K, Vector3.one)
				expect.equal(T, Vector3.zero)
			end
		end
	)

	t.test("every dented and jiggled vertex stays inside the bounds anchors", function()
		-- The map is axis-aligned affine, so the corners of a piece's box (its faces pushed out by clampOut; nothing
		-- goes below its bottom) bound every vertex it moves.
		local out = RIPPLE.clampOut
		for _, built in { layout, JellySkin.backstopLayout("High") } do
			local low, high = built.boundsMin - Vector3.one * 1e-4, built.boundsMax + Vector3.one * 1e-4
			for _, piece in built.pieces do
				if not piece.skinned then
					continue
				end
				local spec = JellySkin.jiggleSpec(piece.kind)
				local reachLow, reachHigh = JellySkin.jiggleReach(piece)
				expect.truthy(reachLow.X >= low.X and reachLow.Y >= low.Y and reachLow.Z >= low.Z)
				expect.truthy(reachHigh.X <= high.X and reachHigh.Y <= high.Y and reachHigh.Z <= high.Z)
				local half = piece.size / 2
				local corners: { Vector3 } = {}
				for _, sx in { -1, 1 } do
					for _, sz in { -1, 1 } do
						for _, y in { piece.base.Y, piece.base.Y + piece.size.Y + out } do
							local x = piece.base.X + sx * (half.X + out)
							local z = piece.base.Z + sz * (half.Z + out)
							table.insert(corners, Vector3.new(x, y, z))
						end
					end
				end
				-- Every axis and side at the cap, and two axes at once.
				local kicks: { { { axis: string, side: number } } } = {
					{ { axis = "X", side = 1 } },
					{ { axis = "X", side = -1 } },
					{ { axis = "Z", side = 1 } },
					{ { axis = "Z", side = -1 } },
					{ { axis = "Y", side = 0 } },
					{ { axis = "X", side = 1 }, { axis = "Z", side = -1 } },
				}
				for _, kick in kicks do
					local wobble = JellySkin.newWobble(spec)
					for _, hit in kick do
						wobble:pivot(hit.axis, hit.side) -- pivots are taken from rest only
					end
					for _, hit in kick do
						wobble:hit(hit.axis, spec.maxAmount, false)
					end
					for _ = 1, 60 do
						wobble:step(FRAME)
						local K, T = wobble:map(piece.base, piece.size)
						for _, corner in corners do
							local moved = JellySkin.jiggledPoint(corner, K, T)
							if moved.X < low.X or moved.Y < low.Y or moved.Z < low.Z then
								error(`{built.kind} {piece.name}: {moved} below the anchors {built.boundsMin}`)
							end
							if moved.X > high.X or moved.Y > high.Y or moved.Z > high.Z then
								error(`{built.kind} {piece.name}: {moved} above the anchors {built.boundsMax}`)
							end
						end
					end
				end
			end
		end
	end)

	-- A Sim on the High arena layout whose IO keeps every vertex's drawn displacement (drawn position - rest), as the
	-- controller would write it: swap-in and swap-out at rest, a face's written vertices at (rest + normal · h) ∘ K + T
	-- (positions skipped when normalsOnly), a whole piece at the map it is given with its faces' heights.
	local function drawingSim(options: any?): (any, { [number]: Vector3 }, { [number]: { K: Vector3, T: Vector3 } })
		local drawn: { [number]: Vector3 } = {}
		local maps: { [number]: { K: Vector3, T: Vector3 } } = {}
		local sim: any = nil
		local function rest(i: number): Vector3
			return Vector3.new(layout.px[i], layout.py[i], layout.pz[i])
		end
		local function atRest(piece: any)
			for i = piece.first, piece.first + piece.count - 1 do
				drawn[i] = Vector3.zero
				maps[i] = { K = Vector3.one, T = Vector3.zero }
			end
		end
		sim = JellySkin.newSim(layout, {
			swapIn = atRest,
			swapOut = atRest,
			writeFace = function(face: any, dent: any, count: number, K: Vector3?, T: Vector3?, normalsOnly: boolean?)
				if normalsOnly then
					return
				end
				for j = 1, count do
					local k = dent.written[j]
					local i = face.first + k - 1
					local q = rest(i) + face.normal * dent.h[k]
					local map = { K = K or Vector3.one, T = T or Vector3.zero }
					drawn[i] = q * map.K + map.T - rest(i)
					maps[i] = map
				end
			end,
			writePiece = function(piece: any, K: Vector3, T: Vector3)
				for _, faceIndex in piece.faces do
					local face = layout.faces[faceIndex]
					local h = sim:faceHeights(faceIndex)
					for k = 1, face.count do
						local i = face.first + k - 1
						local q = rest(i) + face.normal * (if h then h[k] else 0)
						drawn[i] = q * K + T - rest(i)
						maps[i] = { K = K, T = T }
					end
				end
			end,
		}, options)
		return sim, drawn, maps
	end

	-- Every vertex of `piece` as drawingSim draws it while `hits` land ({ face, u, v, at }: throws of r = 1.0 with their
	-- jiggle), until 3.6 s after the last one, at 60 fps: the shortest half-period above 0.02 (see the header) over the
	-- three axis components of every vertex's displacement, and the peak of that lobe. A half-period that spans a hit is
	-- not counted (a hit is an impulse, not a flicker).
	local function drawnHalfPeriod(piece: any, hits: { any }): (number, number)
		local sim, drawn = drawingSim()
		local count = piece.count
		local previous: { number } = table.create(3 * count, 0)
		local peak: { number } = table.create(3 * count, 0)
		local lastCross: { [number]: number } = {}
		local shortest, shortestPeak = math.huge, 0
		local fired: { [number]: boolean } = {}
		local speed, reach = JellySkin.impulseFor(1.0, false, false)
		local amount = JellySkin.jiggleAmount(piece.kind, 1.0, false, false)
		for frame = 1, math.floor((hits[#hits].at + 3.6) / FRAME + 0.5) do
			local now = frame * FRAME
			for index, hit in hits do
				if not fired[index] and now >= hit.at - 1e-9 then
					fired[index] = true
					local faceIndex = layout.faceOf[piece.index][hit.face]
					sim:impulse(faceIndex, hit.u, hit.v, speed, reach, now, RIPPLE.faceSeconds, amount)
					table.clear(lastCross)
				end
			end
			sim:step(FRAME, now, false)
			for k = 1, count do
				local d = drawn[piece.first + k - 1] or Vector3.zero
				for c = 1, 3 do
					local key = (c - 1) * count + k
					local value = if c == 1 then d.X elseif c == 2 then d.Y else d.Z
					local p = previous[key]
					if (p < 0 and value >= 0) or (p > 0 and value <= 0) then
						local crossing = now - FRAME + FRAME * (p / (p - value))
						local last = lastCross[key]
						if last ~= nil and peak[key] > LOBE_PEAK and crossing - last < shortest then
							shortest, shortestPeak = crossing - last, peak[key]
						end
						lastCross[key] = crossing
						peak[key] = 0
					end
					peak[key] = math.max(peak[key], math.abs(value))
					previous[key] = value
				end
			end
		end
		return shortest, shortestPeak
	end

	t.test(
		"dent + jiggle as drawn: no vertex of the piece swings faster than 3 Hz above 0.02, one hit or two on other faces",
		function()
			local cases = {
				-- One hit: the dent test's cases and more.
				{ wallPiece, { { face = "+Z", u = CENTRE[1], v = CENTRE[2], at = 0 } } },
				{ wallPiece, { { face = "+Z", u = CORNER[1], v = CORNER[2], at = 0 } } },
				{ wallPiece, { { face = "+X", u = 0, v = 0.25, at = 0 } } },
				{ blockPiece, { { face = "+Z", u = 0, v = 0, at = 0 } } },
				{ blockPiece, { { face = "+Z", u = -2.2, v = -3, at = 0 } } },
				{ wallPiece, { { face = "+Y", u = 0, v = 0, at = 0 } } },
				-- A second hit on another face while the piece still moves (review 2026-10-07: these beat at 3.2-5.4 Hz
				-- when that face dented too): the opposite face, the top then the front, the front then the top, the
				-- end then the front.
				{ wallPiece, { { face = "+Z", u = 0, v = 0.25, at = 0 }, { face = "-Z", u = 0, v = 0.25, at = 0.1 } } },
				{
					wallPiece,
					{ { face = "+Z", u = 0, v = 0.25, at = 0 }, { face = "-Z", u = -2.25, v = -3.25, at = 0.5 } },
				},
				{ blockPiece, { { face = "+Z", u = 0, v = 0, at = 0 }, { face = "-Z", u = 0, v = 0, at = 0.5 } } },
				{ blockPiece, { { face = "+Z", u = 0, v = 0, at = 0 }, { face = "-Z", u = -2.2, v = -3, at = 0.2 } } },
				{ blockPiece, { { face = "+Z", u = 0, v = 0, at = 0 }, { face = "-Z", u = 1.5, v = 2, at = 1.25 } } },
				{ wallPiece, { { face = "+Y", u = 0, v = 0, at = 0 }, { face = "+Z", u = 0, v = 0.25, at = 0.4 } } },
				{ wallPiece, { { face = "+Y", u = 0, v = 0, at = 0 }, { face = "+Z", u = 0, v = 0.25, at = 0.5 } } },
				{ wallPiece, { { face = "+Z", u = 0, v = 0.25, at = 0 }, { face = "+Y", u = 0, v = 0, at = 0.1 } } },
				{ wallPiece, { { face = "+X", u = 0, v = 0.25, at = 0 }, { face = "+Z", u = 0, v = 0.25, at = 0.4 } } },
			}
			for _, case in cases do
				local shortest, peak = drawnHalfPeriod(case[1], case[2])
				if shortest < MIN_HALF_PERIOD then
					local names = {}
					for _, hit in case[2] do
						table.insert(names, `{hit.face} ({hit.u}, {hit.v}) at {hit.at}`)
					end
					error(`{case[1].name} {table.concat(names, ", ")}: a half-period of {shortest} s (peak {peak})`)
				end
			end
		end
	)

	t.test("the lead face: while a piece moves only it dents; a hit on another face only kicks the jiggle", function()
		local sim = drawingSim()
		local speed, reach = JellySkin.impulseFor(1.0, false, false)
		local amount = JellySkin.jiggleAmount("wall", 1.0, false, false)
		local faces = layout.faceOf[wallPiece.index]
		local front, back, side, top = faces["+Z"], faces["-Z"], faces["+X"], faces["+Y"]
		local now = 0
		local function stepFor(seconds: number)
			for _ = 1, math.floor(seconds / FRAME + 0.5) do
				now += FRAME
				sim:step(FRAME, now, false)
			end
		end
		-- The first jiggling hit on the piece at rest leads: it dents and kicks.
		expect.truthy(sim:impulse(front, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.equal(sim:leadFace(wallPiece.index), front)
		expect.truthy(sim:isActive(front) and sim:isJiggling(wallPiece.index))
		-- A twin that only gets this first hit, to show what the later kicks change.
		local twin = drawingSim()
		twin:impulse(front, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount)
		local twinNow = now
		local function stepTwin(seconds: number)
			for _ = 1, math.floor(seconds / FRAME + 0.5) do
				twinNow += FRAME
				twin:step(FRAME, twinNow, false)
			end
		end
		stepFor(0.3)
		stepTwin(0.3)
		-- The opposite face and a side face: no dent, but a kick (the side one along X).
		expect.truthy(sim:impulse(back, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.truthy(sim:impulse(side, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.falsy(sim:isActive(back) or sim:isActive(side))
		expect.equal(sim:faceHeights(back), nil)
		expect.equal(sim:leadFace(wallPiece.index), front)
		stepFor(0.1)
		stepTwin(0.1)
		local K = sim:jiggleMap(wallPiece.index)
		local twinK = twin:jiggleMap(wallPiece.index)
		expect.truthy(K ~= nil and twinK ~= nil and math.abs((K :: Vector3).X - (twinK :: Vector3).X) > 0.01)
		-- The lead face itself dents again.
		expect.truthy(sim:impulse(front, 1, 1, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.truthy(sim:isActive(front))
		-- Once the piece rests (faces asleep, jiggle settled) the next jiggling hit leads anew.
		stepFor(RIPPLE.faceSeconds + 0.5)
		expect.falsy(sim:isSwapped(wallPiece.index))
		expect.truthy(sim:impulse(back, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.equal(sim:leadFace(wallPiece.index), back)
		expect.truthy(sim:isActive(back))
		stepFor(RIPPLE.faceSeconds + 0.5)
		-- A jiggling hit on the wall top (its plane always moves with Y) leads no face: no dent, a kick, and no other
		-- face dents either until the piece rests.
		expect.truthy(sim:impulse(top, 0, 0, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.equal(sim:leadFace(wallPiece.index), 0)
		expect.falsy(sim:isActive(top))
		expect.truthy(sim:isJiggling(wallPiece.index) and sim:isSwapped(wallPiece.index))
		stepFor(0.2)
		expect.truthy(sim:impulse(front, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.falsy(sim:isActive(front))
		stepFor(RIPPLE.faceSeconds + 0.5)
		expect.falsy(sim:isSwapped(wallPiece.index))
		-- Jiggle-free hits (ReducedMotion) dent any face and lead nothing; a jiggling hit then cannot kick while a face
		-- other than the lead ripples, so it dents only.
		expect.truthy(sim:impulse(front, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, 0))
		expect.truthy(sim:impulse(back, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, 0))
		expect.truthy(sim:isActive(front) and sim:isActive(back))
		expect.equal(sim:leadFace(wallPiece.index), nil)
		expect.truthy(sim:impulse(side, 0, 0.25, speed, reach, now, RIPPLE.faceSeconds, amount))
		expect.truthy(sim:isActive(side))
		expect.falsy(sim:isJiggling(wallPiece.index))
	end)

	-- The swap ----------------------------------------------------------------------------------------------------

	-- A Sim on the High arena layout whose IO records what it is asked to do.
	local function recordingSim(): (any, { { kind: string, piece: number, at: number } }, { now: number })
		local events: { { kind: string, piece: number, at: number } } = {}
		local clock = { now = 0 }
		local sim = JellySkin.newSim(layout, {
			swapIn = function(piece: any)
				table.insert(events, { kind = "in", piece = piece.index, at = clock.now })
			end,
			swapOut = function(piece: any)
				table.insert(events, { kind = "out", piece = piece.index, at = clock.now })
			end,
			writeFace = function() end,
		})
		return sim, events, clock
	end

	t.test(
		"a piece swaps in at its first hit and shows its real parts again exactly when all its faces sleep",
		function()
			local sim, events, clock = recordingSim()
			local front = layout.faceOf[wallPiece.index]["+Z"]
			local back = layout.faceOf[wallPiece.index]["-Z"]
			local speed, reach = JellySkin.impulseFor(1.0, false, false)
			expect.truthy(sim:impulse(front, 0, 0.25, speed, reach, 0, RIPPLE.faceSeconds))
			expect.equal(#events, 1)
			expect.equal(events[1].kind, "in")
			expect.truthy(sim:isSwapped(wallPiece.index))
			local secondAt = 0.5
			local hitBack = false
			local activeBefore = true
			for frame = 1, 300 do
				clock.now = frame * FRAME
				if not hitBack and clock.now >= secondAt then
					hitBack = true
					sim:impulse(back, 1, -1, speed, reach, clock.now, RIPPLE.faceSeconds)
				end
				local before = #events
				activeBefore = sim:isActive(front) or sim:isActive(back)
				sim:step(FRAME, clock.now, false)
				if #events > before then
					-- The swap-out comes on the frame the last face sleeps, not before.
					expect.equal(events[#events].kind, "out")
					expect.truthy(activeBefore)
					expect.falsy(sim:isActive(front) or sim:isActive(back))
				end
			end
			expect.equal(#events, 2)
			expect.equal(events[2].piece, wallPiece.index)
			expect.truthy(events[2].at > secondAt)
			expect.truthy(events[2].at <= secondAt + RIPPLE.faceSeconds + FRAME + 1e-9)
			expect.falsy(sim:isSwapped(wallPiece.index))
			expect.equal(sim:offset(front, 0, 0), 0)
			-- A face that never moves (a fixed face) is refused.
			local backstop = JellySkin.backstopLayout("High")
			local fixed = backstop.faceOf[1]["-X"]
			local still = JellySkin.newSim(
				backstop,
				{ swapIn = function() end, swapOut = function() end, writeFace = function() end }
			)
			expect.falsy(still:impulse(fixed, 0, 0, speed, reach, 0, 1))
		end
	)

	t.test("a face over the write budget loses no time: it steps every other frame with both frames' dt", function()
		-- 20 and 30 fps (the Scheduler's clamp, and a common phone rate) with a 1-write budget: the face steps on odd
		-- frames with 2 × dt. It must follow a dent stepped every frame (same simulated time), not run slow.
		local noop = function() end
		local speed, reach = JellySkin.impulseFor(1.0, false, false)
		local front = layout.faceOf[wallPiece.index]["+Z"]
		local points = { CENTRE, { 1, 1.25 }, { 2, 2.25 }, { -2.5, 0.25 }, { 0, 3.25 } }
		for _, dt in { Config.Anim.Scheduler.maxDt, 1 / 30 } do
			local sim = JellySkin.newSim(
				layout,
				{ swapIn = noop, swapOut = noop, writeFace = noop },
				{ writesPerFrame = 1 }
			)
			sim:impulse(front, CENTRE[1], CENTRE[2], speed, reach, 0, RIPPLE.faceSeconds)
			local reference = hitDent(CENTRE[1], CENTRE[2])
			local worst = 0
			for frame = 1, 31 do
				sim:step(dt, frame * dt, false)
				reference:step(dt, {}, false)
				if frame % 2 == 1 then
					for _, p in points do
						local shown = sim:offset(front, p[1], p[2])
						local wanted = JellySkin.sampleFace(bigFace, reference.h, p[1], p[2])
						worst = math.max(worst, math.abs(shown - wanted))
					end
				end
			end
			expect.truthy(worst < 0.02)
		end
	end)

	t.test("a 7th rippling face snaps the oldest to rest", function()
		local sim = recordingSim()
		local speed, reach = JellySkin.impulseFor(1.0, false, false)
		local faces: { number } = {}
		for _, face in layout.faces do
			if face.moves and #faces < RIPPLE.maxActiveFaces + 1 then
				table.insert(faces, face.index)
			end
		end
		for k, faceIndex in faces do
			sim:impulse(faceIndex, 0, 0, speed, reach, k * 0.01, RIPPLE.faceSeconds)
			sim:step(FRAME, k * 0.01, false)
		end
		expect.equal(sim:activeCount(), RIPPLE.maxActiveFaces)
		expect.falsy(sim:isActive(faces[1]))
		expect.truthy(sim:isActive(faces[#faces]))
	end)

	-- A Sim on the High arena layout that records swaps and whole-piece writes (piece index, step, the map's K).
	local function jiggleSim(options: any?): (any, { events: { any }, wholes: { any }, step: number, now: number })
		local log = { events = {}, wholes = {}, step = 0, now = 0 }
		local sim = JellySkin.newSim(layout, {
			swapIn = function(piece: any)
				table.insert(log.events, { kind = "in", piece = piece.index, at = log.now })
			end,
			swapOut = function(piece: any)
				table.insert(log.events, { kind = "out", piece = piece.index, at = log.now })
			end,
			writeFace = function() end,
			writePiece = function(piece: any, K: Vector3)
				table.insert(log.wholes, { piece = piece.index, step = log.step, K = K })
			end,
		}, options)
		return sim, log
	end

	local function stepSim(sim: any, log: any, reduced: boolean?)
		log.step += 1
		log.now = log.step * FRAME
		sim:step(FRAME, log.now, reduced == true)
	end

	t.test("the swap waits for the jiggle: real parts show again only when the dent and the jiggle rest", function()
		local sim, log = jiggleSim()
		local front = layout.faceOf[wallPiece.index]["+Z"]
		-- A tiny dent (it sleeps within about a second) with a full jiggle (it moves for about 2 s).
		local jiggle = JellySkin.jiggleAmount("wall", 1.0, false, false)
		expect.truthy(sim:impulse(front, CENTRE[1], CENTRE[2], 0.05, 1, 0, RIPPLE.faceSeconds, jiggle))
		expect.truthy(sim:isJiggling(wallPiece.index))
		local faceSleptAt, outAt = nil :: number?, nil :: number?
		local jigglingAtOut = true
		for _ = 1, math.floor((RIPPLE.faceSeconds + 0.5) / FRAME) do
			local before = #log.events
			stepSim(sim, log)
			if faceSleptAt == nil and not sim:isActive(front) then
				faceSleptAt = log.now
			end
			if #log.events > before and log.events[#log.events].kind == "out" then
				outAt = log.now
				jigglingAtOut = sim:isJiggling(wallPiece.index)
			end
		end
		expect.truthy(faceSleptAt ~= nil and outAt ~= nil)
		expect.truthy((outAt :: number) > (faceSleptAt :: number) + 0.3) -- the jiggle held the piece shown
		expect.falsy(jigglingAtOut)
		expect.truthy((outAt :: number) <= RIPPLE.faceSeconds + FRAME + 1e-9)
		expect.equal(#log.events, 2)
		-- While it jiggled, the piece was written whole every step (one piece: always within the budget).
		local steps: { [number]: boolean } = {}
		for _, whole in log.wholes do
			expect.equal(whole.piece, wallPiece.index)
			steps[whole.step] = true
		end
		for step = 1, math.floor((outAt :: number) / FRAME + 0.5) - 1 do
			expect.truthy(steps[step])
		end
		expect.equal(sim:offset(front, 0, 0), 0)
		expect.falsy(sim:isSwapped(wallPiece.index))
	end)

	t.test("whole-piece writes stay within the jiggle budget, the longest-unwritten piece first", function()
		-- Two walls (712 vertices each at High) on an 800-write budget: one per step, taking turns.
		local sim, log = jiggleSim({ jiggleWritesPerFrame = 800 })
		local walls: { any } = {}
		for _, piece in layout.pieces do
			if piece.kind == "wall" and #walls < 2 then
				table.insert(walls, piece)
			end
		end
		for _, piece in walls do
			local face = layout.faceOf[piece.index]["+Z"]
			sim:impulse(face, 0, 0.25, 20, 3, 0, RIPPLE.faceSeconds, JIGGLE.amount)
		end
		for _ = 1, 20 do
			stepSim(sim, log)
		end
		local perStep: { [number]: { number } } = {}
		for _, whole in log.wholes do
			perStep[whole.step] = perStep[whole.step] or {}
			table.insert(perStep[whole.step], whole.piece)
		end
		for step = 1, 20 do
			local list = perStep[step]
			expect.truthy(list ~= nil and #list == 1)
			if step > 1 then
				expect.truthy(list[1] ~= perStep[step - 1][1]) -- they take turns
			end
		end
		-- With the shipped budget both fit in one step.
		local roomy, roomyLog = jiggleSim()
		for _, piece in walls do
			roomy:impulse(layout.faceOf[piece.index]["+Z"], 0, 0.25, 20, 3, 0, RIPPLE.faceSeconds, JIGGLE.amount)
		end
		stepSim(roomy, roomyLog)
		expect.equal(#roomyLog.wholes, 2)
		expect.truthy(JIGGLE.writesPerFrame >= 2 * walls[1].count)
	end)

	t.test("a 5th jiggling piece stops the oldest jiggle; ReducedMotion stops every jiggle at the next step", function()
		local sim, log = jiggleSim()
		local pieces: { any } = {}
		for _, piece in layout.pieces do
			if piece.skinned and #pieces < JIGGLE.maxPieces + 1 then
				table.insert(pieces, piece)
			end
		end
		local function hit(piece: any, amount: number)
			sim:impulse(layout.faceOf[piece.index]["+Z"], 0, 0, 20, 3, log.now, RIPPLE.faceSeconds, amount)
		end
		for k = 1, JIGGLE.maxPieces do
			log.now = k * 0.01
			hit(pieces[k], JIGGLE.amount)
		end
		-- A few steps draw all four jiggled (two High pieces fit the budget per step).
		for _ = 1, 3 do
			stepSim(sim, log)
		end
		local drawnK = sim:jiggleMap(pieces[1].index)
		expect.truthy(drawnK ~= nil and drawnK ~= Vector3.one)
		hit(pieces[#pieces], JIGGLE.amount)
		expect.equal(sim:jiggleCount(), JIGGLE.maxPieces)
		expect.falsy(sim:isJiggling(pieces[1].index))
		expect.truthy(sim:isJiggling(pieces[#pieces].index))
		-- The stopped piece still ripples, so it stays shown: no write outside the budget, it keeps the shape it is
		-- drawn with until its whole-piece write at rest, which comes within the budget a step or two later.
		expect.truthy(sim:isSwapped(pieces[1].index))
		expect.equal(sim:jiggleMap(pieces[1].index), drawnK)
		expect.equal(sim:restingCount(), 1)
		local restWrite = nil :: number?
		for _ = 1, 3 do
			stepSim(sim, log)
			for _, whole in log.wholes do
				if whole.piece == pieces[1].index and whole.step == log.step then
					expect.equal(whole.K, Vector3.one)
					restWrite = log.step
				end
			end
			if restWrite == nil then
				expect.equal(sim:jiggleMap(pieces[1].index), drawnK)
			end
		end
		expect.truthy(restWrite ~= nil)
		expect.equal(sim:jiggleMap(pieces[1].index), nil)
		expect.equal(sim:restingCount(), 0)
		-- ReducedMotion: the next step stops them all; each still rippling piece gets its write at rest within the
		-- budget over the next steps, and there is no jiggle again.
		local firstReduced = log.step + 1
		for _ = 1, 4 do
			stepSim(sim, log, true)
		end
		expect.equal(sim:jiggleCount(), 0)
		expect.equal(sim:restingCount(), 0)
		for _, piece in pieces do
			expect.falsy(sim:isJiggling(piece.index))
			expect.equal(sim:jiggleMap(piece.index), nil)
		end
		local perStep: { [number]: number } = {}
		for _, whole in log.wholes do
			if whole.step >= firstReduced then
				expect.equal(whole.K, Vector3.one)
				perStep[whole.step] = (perStep[whole.step] or 0) + layout.pieces[whole.piece].count
			end
		end
		for _, writes in perStep do
			expect.truthy(writes <= JIGGLE.writesPerFrame)
		end
		hit(pieces[1], JellySkin.jiggleAmount("wall", 1.0, false, true))
		expect.falsy(sim:isJiggling(pieces[1].index))
	end)

	t.test("a piece left out of a step's whole writes is still drawn with one map (review 2026-10-07)", function()
		-- Three High walls (712 vertices each) on the 1500-write budget: one waits every step. Its dent writes must use
		-- the map it is drawn with, not the newer one, or its dent edge jumps out of line every other frame.
		local walls: { any } = {}
		for _, piece in layout.pieces do
			if piece.kind == "wall" and #walls < 3 then
				table.insert(walls, piece)
			end
		end
		expect.truthy(3 * walls[1].count > JIGGLE.writesPerFrame)
		for _, case in { { dt = FRAME, rush = false }, { dt = FRAME, rush = true }, { dt = 1 / 20, rush = false } } do
			local sim, _, maps = drawingSim()
			local speed, reach = JellySkin.impulseFor(1.0, case.rush, false)
			local amount = JellySkin.jiggleAmount("wall", 1.0, case.rush, false)
			for _, piece in walls do
				sim:impulse(layout.faceOf[piece.index]["+Z"], 0, 0.25, speed, reach, 0, RIPPLE.faceSeconds, amount)
			end
			local leftOut = 0
			for step = 1, math.floor(2 / case.dt + 0.5) do
				sim:step(case.dt, step * case.dt, false)
				if sim:jiggleCount() == #walls and sim.jiggleWrites < #walls * walls[1].count then
					leftOut += 1
				end
				for _, piece in walls do
					local ref = maps[piece.first]
					for i = piece.first, piece.first + piece.count - 1 do
						local map = maps[i]
						if map.K ~= ref.K or map.T ~= ref.T then
							error(
								`{piece.name} step {step}: vertex {i} drawn with {map.K} / {map.T}, {ref.K} / {ref.T} beside it`
							)
						end
					end
					local K, T = sim:jiggleMap(piece.index)
					expect.equal(K or Vector3.one, ref.K)
					expect.equal(T or Vector3.zero, ref.T)
				end
			end
			expect.truthy(leftOut > 0) -- the budget did leave pieces out
		end
	end)

	t.test("the jiggle budget: writesPerFrame at High, writesPerFrameLow at Low (phones), every step", function()
		local noop = function() end
		local io = { swapIn = noop, swapOut = noop, writeFace = noop, writePiece = noop }
		for _, quality in { "High", "Low" } do
			local built = JellySkin.arenaLayout(quality)
			local budget = if quality == "Low" then JIGGLE.writesPerFrameLow else JIGGLE.writesPerFrame
			local sim = JellySkin.newSim(built, io)
			expect.equal(sim.jiggleBudget, budget)
			local pieces: { any } = {}
			for _, piece in built.pieces do
				if piece.skinned and #pieces < JIGGLE.maxPieces then
					table.insert(pieces, piece)
				end
			end
			-- Two pieces always fit (so two hit pieces jiggle smoothly on phones too).
			table.sort(pieces, function(a: any, b: any)
				return a.count > b.count
			end)
			expect.truthy(pieces[1].count + pieces[2].count <= budget)
			for k, piece in pieces do
				local face = built.faceOf[piece.index]["+Z"]
				sim:impulse(face, 0, 0.25, 20, 3, k * 0.01, RIPPLE.faceSeconds, JIGGLE.amount)
			end
			for step = 1, 90 do
				sim:step(FRAME, 0.05 + step * FRAME, step > 60)
				expect.truthy(sim.jiggleWrites <= budget)
			end
		end
	end)

	t.test("path B: ReducedMotion turning on mid-wobble calms it (no swing past rest, at rest soon after)", function()
		for _, frames in { 3, 6, 10, 16, 30 } do
			local wobble = JellySkin.newWobble()
			wobble:hit("Z", JellySkin.pathBAmount("wall", false, false), false)
			for _ = 1, frames do
				wobble:step(FRAME)
			end
			local start = wobble:amounts().Z
			wobble:calm()
			local settledAt = nil :: number?
			for frame = 1, 90 do
				wobble:step(FRAME)
				local x = wobble:amounts().Z
				if x * start < 0 or math.abs(x) > math.abs(start) + 1e-9 then
					error(`calmed after {frames} frames at {start}: swung to {x}`)
				end
				if settledAt == nil and wobble:settled() then
					settledAt = frame * FRAME
				end
			end
			expect.truthy(settledAt ~= nil and (settledAt :: number) <= 1)
		end
		-- A later hit without ReducedMotion wobbles again.
		local wobble = JellySkin.newWobble()
		wobble:hit("Z", PATH_B.amount, false)
		wobble:calm()
		wobble:hit("Z", PATH_B.amount, false)
		local crossed, previous = false, 0
		for _ = 1, 60 do
			wobble:step(FRAME)
			local x = wobble:amounts().Z
			crossed = crossed or (previous < 0 and x > 0)
			previous = x
		end
		expect.truthy(crossed)
	end)

	-- The controller, idle ----------------------------------------------------------------------------------------

	t.test("camera guard: a piece on the camera's line is never swapped in (Popper skips hidden parts)", function()
		local JellyRippleController = t.requireClient("Controllers/JellyRippleController")
		-- A 6 × 8 × 2.5 wall whose big faces sit at z = ±1.25; the player's focus 8 studs in front of it, the camera
		-- behind the player, toward the wall.
		local wall = CFrame.new(0, 4, 0)
		local size = Vector3.new(6, 8, 2.5)
		local focus = Vector3.new(0, 5, 8)
		local blocks = JellyRippleController.blocksCamera
		-- The camera pulled in just in front of the wall (the wall holds it there): guarded.
		expect.truthy(blocks(focus, Vector3.new(0, 5, 1.6), wall, size))
		-- The camera behind the wall (the line goes through it): guarded.
		expect.truthy(blocks(focus, Vector3.new(0, 5, -4), wall, size))
		-- Near the edge, within the pad: guarded; well beside the wall: not.
		expect.truthy(blocks(focus, Vector3.new(3.3, 5, 1.6), wall, size))
		expect.falsy(blocks(focus, Vector3.new(6, 5, 1.6), wall, size))
		-- The camera far in front of the wall (the wall is 3.75 studs past it): not.
		expect.falsy(blocks(focus, Vector3.new(0, 5, 5), wall, size))
		-- A wall ahead of the player (between them and the opponent), the camera behind them: not.
		expect.falsy(blocks(Vector3.new(0, 5, -10), Vector3.new(0, 5, -22), wall, size))
		-- First person (the camera on its focus): not. A yawed wall works in its own axes.
		expect.falsy(blocks(focus, focus, wall, size))
		local yawed = CFrame.new(0, 4, 0) * CFrame.Angles(0, math.rad(90), 0) -- now 2.5 wide along X, 6 along Z
		expect.falsy(blocks(Vector3.new(4, 5, 0), Vector3.new(4, 5, -2), yawed, size))
		expect.truthy(blocks(Vector3.new(4, 5, 0), Vector3.new(1.9, 5, 0), yawed, size))
	end)

	t.test("JellyRippleController idle: offsetAt is 0, counts() shows no skin, clear() is safe", function()
		local JellyRippleController = t.requireClient("Controllers/JellyRippleController")
		expect.equal(JellyRippleController.offsetAt(Vector3.new(0, 4, 18.75), -Vector3.zAxis), 0)
		JellyRippleController.clear()
		local counts = JellyRippleController.counts()
		expect.equal(counts.skin, nil)
		expect.equal(counts.activeFaces, 0)
		expect.equal(counts.jiggling, 0)
		expect.equal(counts.wobbling, 0)
		expect.falsy(JellyRippleController.isHidden(Instance.new("Part")))
		local ok, reason = JellyRippleController.debugPoke("B_Wall1", "+Z", 0, 0)
		expect.equal(ok, false)
		expect.truthy(type(reason) == "string")
	end)
end
