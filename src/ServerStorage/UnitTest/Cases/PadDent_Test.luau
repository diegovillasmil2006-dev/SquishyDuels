--!strict
-- PadDent_Test: unit tests for StarterPlayerScripts.Client.Anim.PadDent (the giant-pad dent model).
-- Server only (ServerStorage.UnitTest). Pure: time is injected through a FakeClock, no instances.
-- Contract (DESIGN §17.6.1, §17.12 Part 3), run with each pad's values (sinkDepth 0.5 / 0.6 / 0.7, the §17.6.1 table)
-- on the path A top grid (PadMesh High layout) and on the path B tile grid:
--   * one contact reaches -sinkDepth ± 0.02 within 0.5 s;
--   * after release the peak bulge is <= 0.3 x sinkDepth (about 0.25 expected) and below clampUp, and every
--     |h| < 0.002 within 4 s; then the pad sleeps and a sleeping pad makes zero writes;
--   * two contacts never go deeper than sinkDepth + 0.05, and overlapping dents take the max, not the sum;
--   * a squeeze pulse (contact `extra` = squeezeDip) shows its full extra dip (the clamp follows it), and after the
--     pulse the vertex rises back without a jump;
--   * restWriteCount() says how many vertices snapToRest() will write;
--   * dt 1/20 (and a huge dt, clamped) stays stable; 10,000 random steps stay finite and bounded;
--   * ReducedMotion gives no overshoot.
-- Feel pass additions (DESIGN §18.3.4, §18.11), for the jelly ripple:
--   * impulse(x, z, speed, radius) kicks v -= speed · w(r / radius) on exactly the non-pinned vertices within the
--     radius (also on a grid whose rows are spaced apart from its columns), never a pinned one, and wakes the dent;
--     a zero speed, a radius <= 0 or a value that is not finite kicks nothing;
--   * per-axis spacing: a grid whose row spacing is given and equal to its column spacing steps bit-for-bit like the
--     one-spacing grid (the giant pads' numbers are unchanged); with dz ~= dx one substep's coupling is
--     c² · ((meanX - h) / dx² + (meanZ - h) / dz²) / 2.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- The pad table (footprint, corner radius, rest top, sinkDepth): the design pads of phase 3 D5 (lobby.js:361, 364,
-- 384) with §17.6.1's sink depths.
local PADS = {
	{ key = "jelly", footprint = 10.2, cornerRadius = 3.6, restTop = 6.2, sinkDepth = 0.5, tiles = 10 },
	{ key = "marshmallow", footprint = 10, cornerRadius = 5, restTop = 6.6, sinkDepth = 0.6, tiles = 10 },
	{ key = "royal", footprint = 8.4, cornerRadius = 3.0, restTop = 4.8, sinkDepth = 0.7, tiles = 8 },
}
local FRAME = 1 / 60
local TILE_SPACING = 1.0 -- path B: tiles at 1.0-stud spacing (§17.6.1)

return function(t: Context)
	local expect = t.expect
	local PadDent = t.requireClient("Anim/PadDent")
	local PadMesh = t.requireClient("Anim/PadMesh")
	local FakeClock = t.requireFake("FakeClock")
	local Config = t.requireShared("Config")
	local G = Config.Anim.giantPad
	local MAX_DT = Config.Anim.Scheduler.maxDt

	-- A dent on the path A High top grid of `pad` (outer ring pinned), plus the index of the centre vertex.
	local function meshDent(pad: any): (any, number)
		local layout = PadMesh.build({
			footprint = pad.footprint,
			cornerRadius = pad.cornerRadius,
			restTop = pad.restTop,
			grid = G.gridHigh,
			bevel = G.bevel,
		})
		local dent = PadDent.new({
			cols = layout.grid,
			rows = layout.grid,
			spacing = layout.spacing,
			xs = table.move(layout.px, 1, layout.topCount, 1, {}),
			zs = table.move(layout.pz, 1, layout.topCount, 1, {}),
			pinned = layout.pinned,
		}, PadDent.paramsFrom(G, pad.sinkDepth, MAX_DT))
		local middle = (layout.grid + 1) // 2
		return dent, PadMesh.topIndex(layout.grid, middle, middle)
	end

	-- A dent on the path B tile grid of `pad` (no pinned ring).
	local function tileDent(pad: any): any
		return PadDent.new(
			PadDent.regularGrid(pad.tiles, pad.tiles, TILE_SPACING, false),
			PadDent.paramsFrom(G, pad.sinkDepth, MAX_DT)
		)
	end

	-- Steps `dent` for `seconds` of fake time at `dt`; calls onFrame(time) after each step.
	local function run(
		dent: any,
		clock: any,
		seconds: number,
		dt: number,
		contacts: { any },
		reduced: boolean?,
		onFrame: ((number) -> ())?
	)
		local stop = clock.now() + seconds
		while clock.now() < stop - 1e-9 do
			dent:step(dt, contacts, reduced)
			clock.advance(dt)
			if onFrame then
				onFrame(clock.now())
			end
		end
	end

	local function extremes(dent: any): (number, number)
		local low, high = math.huge, -math.huge
		for index = 1, dent:size() do
			local h = dent:height(index)
			low = math.min(low, h)
			high = math.max(high, h)
		end
		return low, high
	end

	t.test("dent shape w(x) = (1 - x^2)^2 inside the radius and 0 outside", function()
		expect.near(PadDent.shape(0), 1)
		expect.near(PadDent.shape(0.5), 0.5625)
		expect.near(PadDent.shape(1), 0)
		expect.near(PadDent.shape(1.5), 0)
		expect.near(PadDent.targetAt(0, 0, { { x = 0, z = 0 } }, 0.5, G.radius), -0.5)
		expect.near(PadDent.targetAt(G.radius, 0, { { x = 0, z = 0 } }, 0.5, G.radius), 0)
	end)

	t.test("one contact reaches -sinkDepth ± 0.02 within 0.5 s (each pad, path A grid)", function()
		for _, pad in PADS do
			local dent, centre = meshDent(pad)
			local clock = FakeClock.new(0)
			local reachedAt: number? = nil
			run(dent, clock, 0.5, FRAME, { { x = 0, z = 0 } }, false, function(now: number)
				if reachedAt == nil and math.abs(dent:height(centre) + pad.sinkDepth) <= 0.02 then
					reachedAt = now
				end
			end)
			expect.truthy(reachedAt ~= nil and (reachedAt :: number) <= 0.5 + 1e-9)
			expect.near(dent:height(centre), -pad.sinkDepth, 0.02)
		end
	end)

	t.test("one contact dents the path B tiles under it", function()
		for _, pad in PADS do
			local dent = tileDent(pad)
			local clock = FakeClock.new(0)
			-- A tile centre: tiles sit at (k - (n + 1) / 2) studs from the centre.
			local col = 3
			local x = (col - (pad.tiles + 1) / 2) * TILE_SPACING
			run(dent, clock, 0.5, FRAME, { { x = x, z = x } }, false)
			expect.near(dent:height((col - 1) * pad.tiles + col), -pad.sinkDepth, 0.02)
		end
	end)

	t.test("release: peak bulge <= 0.3 x sinkDepth and below clampUp, settled within 4 s, then asleep", function()
		for _, pad in PADS do
			local makers: { (any) -> any } = { meshDent :: any, tileDent }
			for _, make in makers do
				local dent = make(pad)
				local clock = FakeClock.new(0)
				run(dent, clock, 1, FRAME, { { x = 0.5, z = 0.5 } }, false)
				local peak = 0
				local settledAt: number? = nil
				local released = clock.now()
				run(dent, clock, 6, FRAME, {}, false, function(now: number)
					local low, high = extremes(dent)
					peak = math.max(peak, high)
					if settledAt == nil and math.max(-low, high) < G.sleepEpsilon then
						settledAt = now - released
					end
				end)
				expect.truthy(peak > 0.1 * pad.sinkDepth) -- the slow wave does overshoot
				expect.truthy(peak <= 0.3 * pad.sinkDepth)
				expect.truthy(peak < G.clampUp)
				expect.truthy(settledAt ~= nil and (settledAt :: number) <= 4)
				expect.truthy(dent:isAsleep())
				expect.equal(dent:step(FRAME, {}, false), 0)
			end
		end
	end)

	t.test("a sleeping pad makes zero writes; snapToRest writes once", function()
		local pad = PADS[1]
		local dent = tileDent(pad)
		expect.equal(dent:step(FRAME, {}, false), 0) -- fresh pad
		expect.truthy(dent:isAsleep())
		local clock = FakeClock.new(0)
		run(dent, clock, 0.5, FRAME, { { x = 0.5, z = 0.5 } }, false)
		expect.falsy(dent:isAsleep())
		local pending = dent:restWriteCount()
		local count = dent:snapToRest()
		expect.equal(count, pending)
		expect.equal(dent:restWriteCount(), 0)
		expect.truthy(count > 0)
		for k = 1, count do
			expect.equal(dent:height(dent.written[k]), 0)
		end
		expect.equal(dent:snapToRest(), 0)
		for _ = 1, 10 do
			expect.equal(dent:step(FRAME, {}, false), 0)
		end
	end)

	t.test("two contacts never go deeper than sinkDepth + 0.05 (max, not sum)", function()
		for _, pad in PADS do
			-- Overlapping dents: the target is the deeper single dent.
			local both = PadDent.targetAt(0, 0, { { x = -0.5, z = 0 }, { x = 0.5, z = 0 } }, pad.sinkDepth, G.radius)
			local one = PadDent.targetAt(0, 0, { { x = 0.5, z = 0 } }, pad.sinkDepth, G.radius)
			expect.near(both, one)
			-- Two contacts on the same spot, simulated.
			local dent = meshDent(pad)
			local clock = FakeClock.new(0)
			local lowest = 0
			run(dent, clock, 2, FRAME, { { x = 0, z = 0 }, { x = 0, z = 0 } }, false, function()
				local low = extremes(dent)
				lowest = math.min(lowest, low)
			end)
			expect.truthy(lowest >= -pad.sinkDepth - 0.05 - 1e-9)
		end
	end)

	-- §17.6.1 "an accepted squeeze adds a 0.1-stud extra dip": with the clamp at -sinkDepth - 0.05 the dip stopped
	-- half way. Held long enough, the centre settles at -(sinkDepth + squeezeDip) (neighbour coupling aside).
	t.test("a squeeze pulse shows its full extra dip on every pad, then rises back smoothly", function()
		for _, pad in PADS do
			local dent, centre = meshDent(pad)
			local clock = FakeClock.new(0)
			run(dent, clock, 1, FRAME, { { x = 0, z = 0, extra = G.squeezeDip } }, false)
			expect.near(dent:height(centre), -(pad.sinkDepth + G.squeezeDip), 0.02)
			-- Pulse over, still standing: back to -sinkDepth, never jumping more than a spring step per frame.
			local previous = dent:height(centre)
			local biggestStep = 0
			run(dent, clock, 1, FRAME, { { x = 0, z = 0 } }, false, function()
				local now = dent:height(centre)
				biggestStep = math.max(biggestStep, math.abs(now - previous))
				previous = now
			end)
			expect.near(dent:height(centre), -pad.sinkDepth, 0.02)
			expect.truthy(biggestStep < 0.02)
		end
	end)

	t.test("dt 1/20 and a clamped huge dt stay stable", function()
		for _, pad in PADS do
			for _, dt in { 1 / 20, 1 } do
				local dent, centre = meshDent(pad)
				local clock = FakeClock.new(0)
				-- A dt above maxDt is clamped, so the model advances maxDt per step: scale the fake time to match.
				local slow = dt / math.min(dt, MAX_DT)
				run(dent, clock, 1 * slow, dt, { { x = 0, z = 0 } }, false)
				expect.near(dent:height(centre), -pad.sinkDepth, 0.02)
				run(dent, clock, 8 * slow, dt, {}, false)
				local low, high = extremes(dent)
				expect.truthy(low >= -G.sleepEpsilon and high <= G.sleepEpsilon)
			end
		end
	end)

	t.test("10,000 random steps stay finite and bounded", function()
		local rng = Random.new(1234)
		for _, pad in PADS do
			local dent = meshDent(pad)
			-- The floor follows the deepest squeeze pulse among the contacts (§17.6.1 squeeze dip).
			local lo = -pad.sinkDepth - G.squeezeDip - G.clampExtra - 1e-9
			local hi = G.clampUp + 1e-9
			local footprintHalf = pad.footprint / 2
			for _ = 1, 10000 // #PADS do
				local contacts = {}
				for _ = 1, rng:NextInteger(0, 9) do
					table.insert(contacts, {
						x = rng:NextNumber(-footprintHalf, footprintHalf),
						z = rng:NextNumber(-footprintHalf, footprintHalf),
						extra = if rng:NextNumber() < 0.2 then G.squeezeDip else nil,
					})
				end
				dent:step(rng:NextNumber(0, 0.2), contacts, rng:NextNumber() < 0.3)
			end
			for index = 1, dent:size() do
				local h = dent:height(index)
				expect.truthy(h == h and h >= lo and h <= hi)
			end
		end
	end)

	t.test("ReducedMotion: no overshoot, the dent still follows the feet", function()
		for _, pad in PADS do
			local dent, centre = meshDent(pad)
			local clock = FakeClock.new(0)
			run(dent, clock, 1, FRAME, { { x = 0, z = 0 } }, true)
			expect.near(dent:height(centre), -pad.sinkDepth, 0.02)
			local peak = 0
			run(dent, clock, 5, FRAME, {}, true, function()
				local _, high = extremes(dent)
				peak = math.max(peak, high)
			end)
			expect.truthy(peak <= 1e-9)
			expect.truthy(dent:isAsleep())
		end
	end)

	t.test("pinned outer ring never moves", function()
		local pad = PADS[2]
		local dent = meshDent(pad)
		local clock = FakeClock.new(0)
		-- A contact right at the edge of the footprint.
		run(dent, clock, 1, FRAME, { { x = pad.footprint / 2 - 0.5, z = 0 } }, false)
		local n = G.gridHigh
		for col = 1, n do
			expect.equal(dent:height(PadMesh.topIndex(n, col, 1)), 0)
			expect.equal(dent:height(PadMesh.topIndex(n, col, n)), 0)
			expect.equal(dent:height(PadMesh.topIndex(n, 1, col)), 0)
			expect.equal(dent:height(PadMesh.topIndex(n, n, col)), 0)
		end
	end)

	-- Feel pass: impulses and per-axis spacing (the jelly ripple, §18.3.4) ----------------------------------------

	-- The nominal position of a vertex on a regular grid centred on 0 (columns `dx` apart, rows `dz` apart).
	local function nominal(
		cols: number,
		rows: number,
		dx: number,
		dz: number,
		index: number
	): (number, number, number, number)
		local row = (index - 1) // cols + 1
		local col = index - (row - 1) * cols
		return -(cols - 1) * dx / 2 + (col - 1) * dx, -(rows - 1) * dz / 2 + (row - 1) * dz, col, row
	end

	t.test("impulse kicks exactly the non-pinned vertices within the radius and wakes the dent", function()
		local cols, rows, dx, dz = 9, 7, 0.5, 1.0
		local dent = PadDent.new(PadDent.regularGrid(cols, rows, dx, true, dz), PadDent.paramsFrom(G, 0.5, MAX_DT))
		expect.truthy(dent:isAsleep())
		local x, z, speed, radius = -1.5, -2.5, 2, 1.6
		local kicked = dent:impulse(x, z, speed, radius)
		local expected = 0
		local pinnedInside = 0
		for index = 1, dent:size() do
			local vx, vz, col, row = nominal(cols, rows, dx, dz, index)
			local pinned = col == 1 or col == cols or row == 1 or row == rows
			local d2 = (vx - x) ^ 2 + (vz - z) ^ 2
			local wanted = 0
			if d2 < radius * radius then
				if pinned then
					pinnedInside += 1
				else
					expected += 1
					wanted = -speed * (1 - d2 / (radius * radius)) ^ 2
				end
			end
			expect.near(dent.v[index], wanted, 1e-12)
		end
		expect.truthy(pinnedInside > 0) -- the radius reaches the pinned ring, which must not move
		expect.equal(kicked, expected)
		expect.falsy(dent:isAsleep())
		expect.truthy(dent:step(FRAME, {}, false) > 0)
		local lowest = extremes(dent)
		expect.truthy(lowest < 0)
	end)

	t.test("impulse with a zero speed, a radius <= 0 or a value that is not finite kicks nothing", function()
		local dent = PadDent.new(PadDent.regularGrid(6, 6, 1, false), PadDent.paramsFrom(G, 0.5, MAX_DT))
		local nan = 0 / 0
		expect.equal(dent:impulse(0, 0, 0, 2), 0)
		expect.equal(dent:impulse(0, 0, 3, 0), 0)
		expect.equal(dent:impulse(0, 0, 3, -1), 0)
		expect.equal(dent:impulse(nan, 0, 3, 2), 0)
		expect.equal(dent:impulse(0, 0, math.huge, 2), 0)
		expect.equal(dent:impulse(100, 100, 3, 2), 0) -- off the grid
		expect.truthy(dent:isAsleep())
		expect.equal(dent:step(FRAME, {}, false), 0)
	end)

	t.test(
		"a row spacing equal to the column spacing steps bit-for-bit like one spacing (the pads are unchanged)",
		function()
			for _, pad in PADS do
				local layout = PadMesh.build({
					footprint = pad.footprint,
					cornerRadius = pad.cornerRadius,
					restTop = pad.restTop,
					grid = G.gridHigh,
					bevel = G.bevel,
				})
				local function make(withRows: boolean): any
					return PadDent.new({
						cols = layout.grid,
						rows = layout.grid,
						spacing = layout.spacing,
						spacingZ = if withRows then layout.spacing else nil,
						xs = table.move(layout.px, 1, layout.topCount, 1, {}),
						zs = table.move(layout.pz, 1, layout.topCount, 1, {}),
						pinned = layout.pinned,
					}, PadDent.paramsFrom(G, pad.sinkDepth, MAX_DT))
				end
				local one, both = make(false), make(true)
				local tiles = PadDent.regularGrid(pad.tiles, pad.tiles, TILE_SPACING, false)
				local tilesRows = PadDent.regularGrid(pad.tiles, pad.tiles, TILE_SPACING, false, TILE_SPACING)
				local oneTiles = PadDent.new(tiles, PadDent.paramsFrom(G, pad.sinkDepth, MAX_DT))
				local bothTiles = PadDent.new(tilesRows, PadDent.paramsFrom(G, pad.sinkDepth, MAX_DT))
				local rng = Random.new(77)
				for frame = 1, 240 do
					local contacts = {}
					if frame < 120 then
						table.insert(contacts, { x = rng:NextNumber(-2, 2), z = rng:NextNumber(-2, 2) })
					end
					if frame == 150 then
						one:impulse(0.5, -0.5, 2, 1.5)
						both:impulse(0.5, -0.5, 2, 1.5)
						oneTiles:impulse(0.5, -0.5, 2, 1.5)
						bothTiles:impulse(0.5, -0.5, 2, 1.5)
					end
					local reducedMotion = frame % 50 == 0
					expect.equal(one:step(FRAME, contacts, reducedMotion), both:step(FRAME, contacts, reducedMotion))
					expect.equal(
						oneTiles:step(FRAME, contacts, reducedMotion),
						bothTiles:step(FRAME, contacts, reducedMotion)
					)
					for index = 1, one:size() do
						expect.equal(one:height(index), both:height(index))
					end
					for index = 1, oneTiles:size() do
						expect.equal(oneTiles:height(index), bothTiles:height(index))
					end
				end
			end
		end
	)

	t.test(
		"with rows spaced apart from columns one substep follows c² · ((meanX - h)/dx² + (meanZ - h)/dz²) / 2",
		function()
			local cols, rows, dx, dz = 5, 5, 0.5, 1.0
			local params = table.clone(PadDent.paramsFrom(G, 0.5, MAX_DT))
			params.waveSpeed = 3
			params.substep = 1 / 120
			local dent = PadDent.new(PadDent.regularGrid(cols, rows, dx, false, dz), params)
			local centre = 13 -- row 3, col 3
			local left, right, down, up = 12, 14, 8, 18
			local a, b = 0.1, -0.05
			dent.h[left], dent.h[right] = a, a
			dent.h[down], dent.h[up] = b, b
			dent.moving = { left, right, down, up }
			dent.movingCount = 4
			dent:step(params.substep, {}, false)
			local c2 = params.waveSpeed * params.waveSpeed
			local acc = c2 * ((a - 0) / (dx * dx) + (b - 0) / (dz * dz)) / 2
			expect.near(dent.v[centre], acc * params.substep, 1e-12)
			expect.near(dent:height(centre), acc * params.substep * params.substep, 1e-12)
		end
	)
end
