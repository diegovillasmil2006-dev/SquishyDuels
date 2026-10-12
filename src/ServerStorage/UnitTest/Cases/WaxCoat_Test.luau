--!strict
-- WaxCoat_Test: unit tests for StarterPlayerScripts.Client.Anim.WaxCoat, the port of the 3D Lab's wax coat crack model
-- (spec phase2-squeeze §1.13, §3.4, §3.14). Server only (ServerStorage.UnitTest). Pure: time injected, randomness
-- through FakeRng (seeded to build, scripted where a test checks one crack's numbers), no instances. Run on Butter's
-- soft shell (ShellGeometry) under a SoftBody. Contract (every number from sd/squish.js):
--   * cells: Poisson-disk samples over the coat's vertices at least dc = 0.085·maxDim apart, at most 480; a part with
--     wax = false gets none and is in no footprint; neighbours are exactly the cells within 2·dc; footprints are the
--     coat vertices within 1.7·dc, weight (1 - d² / rc²)²;
--   * load: s = s·exp(-1.4·dt) + (1.3·chord + |Δ|x|| / rF)·(0.3 + 0.7·I);
--   * a crack: E = clamp((s / th)·exp(0.45·g), 0.3, 3)·(0.45 + 0.55·I), s -= th·U(0.75, 1), I -= wear·E, the footprint's
--     damage += 0.14·E·w (<= 1), a new th, its neighbours s += th·0.07·U·I, crunchiness += (I - crunchiness)·0.04, and an
--     event with E, the intact share left, pan (design frame, × 0.55), the cell's position and normal;
--   * at most 6 cracks a frame sound (wear, damage, cascade, events); the others only lose their stress;
--   * waxLeft = the mean I before the frame's cracks; drive = min(1, strain / dt / cells / 3);
--   * the body's rest resets the cells' normals and m and halves their stress; re-wax resets the coat; shine 1 then
--     -1.1 a second;
--   * calibration: a 3 s thumb crunch on a fresh Butter gives 30-45 cracks a second (HANDOFF.md:38).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local FRAME = 1 / 60
local FRONT = Vector3.new(0, 0, -1)

return function(t: Context)
	local WaxCoat = t.requireClient("Anim/WaxCoat")
	local SoftBody = t.requireClient("Anim/SoftBody")
	local ShellGeometry = t.requireClient("Anim/ShellGeometry")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local Config = t.requireShared("Config")
	local FakeRng = t.requireFake("FakeRng")
	local expect = t.expect
	local WAX = Config.Wax

	-- Butter's soft shell; `noWax` names a part index that carries no coat.
	local function butterShell(quality: string, noWax: number?): any
		local blueprint = Blueprints.butter
		local parts = {}
		for _, spec in blueprint.parts do
			if spec.body and spec.face == nil and spec.attach == nil then
				table.insert(parts, {
					shape = spec.shape,
					cframe = CFrame.new((spec.pos or Vector3.zero) * blueprint.scale),
					size = spec.size * blueprint.scale,
					wax = #parts + 1 ~= noWax,
				})
			end
		end
		return ShellGeometry.build(parts, quality)
	end

	local function newPair(feel: string, quality: string?, noWax: number?): (any, any, any)
		local shell = butterShell(quality or "Low", noWax)
		local body = SoftBody.new(shell, { feel = feel, squeezeDepth = 0.62, rng = FakeRng.new(5) })
		local coat = WaxCoat.new(body, { rng = FakeRng.new(9) })
		return coat, body, shell
	end

	local function rest(shell: any, i: number): Vector3
		return Vector3.new(shell.px[i], shell.py[i], shell.pz[i])
	end

	-- A cell on Butter's flat front: its vertex and every vertex of its one-ring face -Z (rest normal = the faces').
	local function flatFrontCell(coat: any, shell: any): number
		for k = 1, coat.cellCount do
			local i = coat.cellVertex[k]
			local flat = shell.nz[i] < -0.99999
			for tri = 1, shell.triCount do
				local a, b, c = shell.tris[3 * tri - 2], shell.tris[3 * tri - 1], shell.tris[3 * tri]
				if a == i or b == i or c == i then
					for _, v in { a, b, c } do
						flat = flat and shell.nz[v] < -0.99999
					end
				end
			end
			if flat then
				return k
			end
		end
		error("no flat front cell")
	end

	-- Scripted rng values for one crack: gauss = 0 for E (u1 = 0.5, u2 = 0.25 gives cos(π / 2) = 0), the stress drop's
	-- U(0.75, 1) = `drop`, gauss = 0 for the new th, then `cascade` for each of `neighbours`.
	local function oneCrack(drop: number, cascade: number, neighbours: number): { number }
		local values = { 0.5, 0.25, drop, 0.5, 0.25 }
		for _ = 1, neighbours do
			table.insert(values, cascade)
		end
		return values
	end

	-- `count` cells no two of which are neighbours (so no cascade reaches another of them).
	local function apartCells(coat: any, count: number): { number }
		local chosen, blocked = {}, {}
		for k = 1, coat.cellCount do
			if not blocked[k] then
				table.insert(chosen, k)
				for j = coat.nbStart[k], coat.nbStart[k + 1] - 1 do
					blocked[coat.nbList[j]] = true
				end
				if #chosen == count then
					break
				end
			end
		end
		assert(#chosen == count, "not enough cells apart")
		return chosen
	end

	t.test("cells: Poisson-disk, at least dc = 0.085·maxDim apart, at most 480 (squish.js:231-249)", function()
		for _, quality in { "High", "Low" } do
			local coat, body, shell = newPair("foam", quality)
			local dc = 0.085 * body.maxDim
			expect.near(coat.spacing, dc, 1e-9)
			expect.truthy(coat.cellCount > 50 and coat.cellCount <= 480)
			for a = 1, coat.cellCount do
				local pa = rest(shell, coat.cellVertex[a])
				for b = a + 1, coat.cellCount do
					expect.truthy((rest(shell, coat.cellVertex[b]) - pa).Magnitude >= dc - 1e-6)
				end
			end
		end
		-- A coarse cube has room for more: capped at MAXC (squish.js:233).
		local cube = ShellGeometry.build({ { shape = "B", cframe = CFrame.new(), size = Vector3.one } }, "Low")
		local cubeBody = SoftBody.new(cube, { feel = "foam", squeezeDepth = 0.62 })
		expect.equal(WaxCoat.new(cubeBody, { rng = FakeRng.new(3) }).cellCount, 480)
	end)

	t.test("neighbours within 2·dc; footprints within 1.7·dc, weight (1 - d²/rc²)² (squish.js:250-265)", function()
		local coat, _, shell = newPair("foam", "Low", 2)
		local dc = coat.spacing
		local rc = 1.7 * dc
		for k = 1, coat.cellCount do
			local pk = rest(shell, coat.cellVertex[k])
			expect.truthy(shell.parts[2].first > coat.cellVertex[k] or coat.cellVertex[k] >= shell.parts[3].first)
			local listed: { [number]: boolean } = {}
			for j = coat.nbStart[k], coat.nbStart[k + 1] - 1 do
				listed[coat.nbList[j]] = true
			end
			for j = 1, coat.cellCount do
				local near = j ~= k and (rest(shell, coat.cellVertex[j]) - pk).Magnitude < 2 * dc
				expect.equal(listed[j] == true, near)
			end
			local weights: { [number]: number } = {}
			for j = coat.footStart[k], coat.footStart[k + 1] - 1 do
				weights[coat.footVertex[j]] = coat.footWeight[j]
			end
			for i = 1, shell.count do
				local d = (rest(shell, i) - pk).Magnitude
				local onWax = shell.vertexPart[i] ~= 2
				if onWax and d < rc - 1e-6 then
					local q = 1 - d * d / (rc * rc)
					expect.near(weights[i], q * q, 1e-5)
				elseif not onWax or d > rc + 1e-6 then
					expect.equal(weights[i], nil)
				end
			end
		end
	end)

	t.test("load: s = s·exp(-1.4·dt) + (1.3·chord + |Δ|x|| / rF)·(0.3 + 0.7·I) (squish.js:274-281)", function()
		local coat, body, shell = newPair("foam")
		local k = flatFrontCell(coat, shell)
		local i = coat.cellVertex[k]
		coat.cellI[k] = 0.6
		coat.cellS[k] = 0.1
		coat.cellTh[k] = 100 -- no crack here
		-- Swing every normal by 0.1 rad (turn the toy about X through the cell) and displace the cell's vertex.
		local pivot = rest(shell, i)
		local turn = CFrame.new(pivot) * CFrame.Angles(0.1, 0, 0) * CFrame.new(-pivot)
		for v = 1, shell.count do
			local p = turn * rest(shell, v)
			body.px[v], body.py[v], body.pz[v] = p.X, p.Y, p.Z
		end
		local m = 0.3 * body.rF
		body.xs[i], body.ys[i], body.zs[i] = 0, m, 0
		body.active = true
		coat:step(FRAME)
		local chord = 2 * math.sin(0.05)
		local load = 1.3 * chord + m / body.rF
		expect.near(coat.cellS[k], 0.1 * math.exp(-1.4 * FRAME) + load * (0.3 + 0.7 * 0.6), 1e-5)
		expect.near(coat.cellM[k], m, 1e-9)
		-- Unchanged next frame: only the relax.
		local before = coat.cellS[k]
		coat:step(FRAME)
		expect.near(coat.cellS[k], before * math.exp(-1.4 * FRAME), 1e-5)
	end)

	t.test("a crack: E, the stress drop, wear, footprint damage, a new th, the event (squish.js:286-295)", function()
		local coat, body, shell = newPair("foam")
		local k = flatFrontCell(coat, shell)
		for j = 1, coat.cellCount do
			coat.cellTh[j] = 100 -- only cell k cracks
		end
		local th = 0.8
		coat.cellTh[k] = th
		coat.cellS[k] = 2 * th
		local neighbours = coat.nbStart[k + 1] - coat.nbStart[k]
		coat.rng = FakeRng.new(oneCrack(0.875, 0.5, neighbours))
		body.active = true
		local sounded = coat:step(FRAME)
		expect.equal(sounded, 1)
		expect.equal(coat.cracks, 1)
		local s = 2 * th * math.exp(-1.4 * FRAME) -- no load: the toy is at rest
		local E = math.clamp(s / th, 0.3, 3) * (0.45 + 0.55 * 1)
		expect.near(coat.cellS[k], s - th * 0.875, 1e-6)
		expect.near(coat.cellTh[k], WAX.coats.foam.th * WAX.thScale, 1e-6)
		expect.near(coat.cellI[k], 1 - WAX.coats.foam.wear * E, 1e-6)
		expect.near(coat.crunchiness, 1, 1e-12) -- (I - local)·0.04 with I = 1 and local = 1
		for j = coat.footStart[k], coat.footStart[k + 1] - 1 do
			expect.near(coat.damage[coat.footVertex[j]], math.min(1, 0.14 * E * coat.footWeight[j]), 1e-9)
		end
		local events = coat:takeEvents()
		expect.equal(#events, 1)
		local event = events[1]
		expect.near(event.E, E, 1e-6)
		expect.near(event.intact, coat.cellI[k], 1e-12)
		local i = coat.cellVertex[k]
		local x = -shell.px[i] -- the design frame
		expect.near(event.pan, math.clamp((x - -body.center.X) / (body.size.X / 2), -1, 1) * 0.55, 1e-6)
		expect.near((event.position - rest(shell, i)).Magnitude, 0, 1e-6)
		expect.near((event.normal - FRONT).Magnitude, 0, 1e-4)
		expect.equal(event.cell, k)
		expect.truthy(coat.touchedCount > 0)
	end)

	t.test("E is clamped to [0.3, 3] before the worn share (squish.js:288)", function()
		-- gauss = sqrt(-2·ln u1)·cos(2π·u2): u2 = 0.5 gives -sqrt(-2·ln u1); u1 = exp(-4.5) gives -3.
		for _, case in { { s = 30, u1 = 0.5, u2 = 0.25, E = 3 }, { s = 1.05, u1 = math.exp(-4.5), u2 = 0.5, E = 0.3 } } do
			local coat, body, shell = newPair("foam")
			local k = flatFrontCell(coat, shell)
			for j = 1, coat.cellCount do
				coat.cellTh[j] = 1000
				coat.cellI[j] = 0.5
			end
			coat.cellTh[k] = 1
			coat.cellS[k] = case.s
			local values = { case.u1, case.u2, 0.875, 0.5, 0.25 }
			for _ = coat.nbStart[k], coat.nbStart[k + 1] - 1 do
				table.insert(values, 0.5)
			end
			coat.rng = FakeRng.new(values)
			body.active = true
			coat:step(FRAME)
			local event = coat:takeEvents()[1]
			expect.near(event.E, case.E * (0.45 + 0.55 * 0.5), 1e-9)
			expect.near(coat.cellI[k], 0.5 - WAX.coats.foam.wear * event.E, 1e-9)
		end
	end)

	t.test("cascade: each neighbour of a cracked cell gains its th·0.07·U·I (squish.js:292)", function()
		local coat, body, shell = newPair("foam")
		local k = flatFrontCell(coat, shell)
		for j = 1, coat.cellCount do
			coat.cellTh[j] = 100
			coat.cellI[j] = 0.8
		end
		coat.cellTh[k] = 1
		coat.cellS[k] = 2
		local neighbours = coat.nbStart[k + 1] - coat.nbStart[k]
		expect.truthy(neighbours > 0)
		coat.rng = FakeRng.new(oneCrack(0.875, 0.25, neighbours))
		body.active = true
		coat:step(FRAME)
		for j = coat.nbStart[k], coat.nbStart[k + 1] - 1 do
			local o = coat.nbList[j]
			expect.near(coat.cellS[o], 100 * 0.07 * 0.25 * 0.8, 1e-9)
		end
	end)

	t.test("at most 6 cracks a frame sound; the others only lose their stress (squish.js:286-290)", function()
		local coat, body = newPair("foam")
		for j = 1, coat.cellCount do
			coat.cellTh[j] = 100
		end
		local cells = apartCells(coat, 10)
		for rank, k in cells do
			coat.cellTh[k] = 1
			coat.cellS[k] = 3 + rank -- distinct s / th: the last one first
		end
		body.active = true
		local sounded = coat:step(FRAME)
		expect.equal(sounded, 6)
		expect.equal(coat.cracks, 6)
		expect.equal(#coat:takeEvents(), 6)
		for rank, k in cells do
			expect.truthy(coat.cellS[k] <= (3 + rank) * math.exp(-1.4 * FRAME) - 0.75 + 1e-9) -- every one dropped s
			expect.equal(coat.cellI[k] < 1, rank >= 5) -- only the 6 biggest wore
		end
	end)

	t.test("waxLeft = the mean I before the cracks; crunchiness 4% toward each I (squish.js:284, 291)", function()
		local coat, body = newPair("foam")
		local sum = 0
		for j = 1, coat.cellCount do
			coat.cellTh[j] = 100
			coat.cellI[j] = (j % 5) / 5
			sum += coat.cellI[j]
		end
		coat.cellTh[1] = 1
		coat.cellS[1] = 2
		local intact = coat.cellI[1]
		body.active = true
		coat:step(FRAME)
		expect.near(coat.waxLeft, sum / coat.cellCount, 1e-9)
		expect.near(coat.crunchiness, 1 + (intact - 1) * 0.04, 1e-9)
	end)

	t.test("rest: cell normals and m go back, stress halves (squish.js:646); no cells off the coat", function()
		local coat, body, shell = newPair("foam")
		local contact = 0
		for i = 1, shell.count do
			if shell.vertexPart[i] == 1 and shell.nz[i] < -0.9999 and math.abs(shell.px[i]) < 0.1 then
				contact = i
				break
			end
		end
		body:fingerDown(rest(shell, contact), Vector3.new(shell.nx[contact], shell.ny[contact], shell.nz[contact]))
		for _ = 1, 30 do
			body:step(FRAME)
			coat:step(FRAME)
		end
		body:fingerUp()
		local before = table.clone(coat.cellS)
		local rested = false
		for _ = 1, 600 do
			body:step(FRAME)
			if not body.active then
				before = table.clone(coat.cellS)
				coat:step(FRAME)
				rested = true
				break
			end
			coat:step(FRAME)
		end
		expect.truthy(rested)
		for k = 1, coat.cellCount do
			expect.near(coat.cellS[k], 0.5 * before[k], 1e-12)
			expect.equal(coat.cellM[k], 0)
			local i = coat.cellVertex[k]
			expect.equal(coat.cellNx[k], shell.nx[i])
			expect.equal(coat.cellNz[k], shell.nz[i])
		end
		local off = newPair("foam", "Low", 1)
		local body1 = off.body
		for k = 1, off.cellCount do
			expect.truthy(body1.shell.vertexPart[off.cellVertex[k]] ~= 1)
		end
	end)

	t.test("re-wax, the shine's fall and the audio drive (squish.js:305-309, 627-632)", function()
		local coat, body = newPair("foam")
		for j = 1, 8 do
			coat.cellTh[j] = 0.5
			coat.cellS[j] = 2
		end
		body.active = true
		coat:step(FRAME)
		expect.truthy(coat.cracks > 0)
		coat:rewax()
		expect.equal(coat.cracks, 0)
		expect.equal(coat.waxLeft, 1)
		expect.equal(coat.crunchiness, 1)
		expect.equal(coat.shine, 1)
		expect.equal(coat.rewaxCount, 1)
		expect.equal(coat.touchedCount, 0)
		for k = 1, coat.cellCount do
			expect.equal(coat.cellI[k], 1)
			expect.equal(coat.cellS[k], 0)
		end
		for i = 1, #coat.damage do
			expect.equal(coat.damage[i], 0)
		end
		body.active = false
		coat:step(0.5)
		expect.near(coat.shine, 1 - 1.1 * 0.5, 1e-12)
		coat:step(1)
		expect.equal(coat.shine, 0)
		-- drive: a known strain on a resting toy
		body.active = true
		local i = coat.cellVertex[1]
		body.xs[i] = 0.9 * body.rF
		coat:step(FRAME)
		local strain = 0.9 -- |Δ|x|| / rF on one cell
		expect.near(coat.drive, math.min(1, strain / FRAME / coat.cellCount / 3), 1e-6)
	end)

	t.test("calibration: a 3 s thumb crunch on a fresh Butter gives 30-45 cracks a second (HANDOFF.md:38)", function()
		-- The mean of three coats (one crunch varies by about ±7 cracks a second with the random thresholds).
		local shell = butterShell("High")
		local total = 0
		for seed = 1, 3 do
			local body = SoftBody.new(shell, { feel = "foam", squeezeDepth = 0.62, rng = FakeRng.new(seed) })
			local coat = WaxCoat.new(body, { rng = FakeRng.new(100 + seed) })
			body:thumbs(true)
			for _ = 1, 180 do
				body:step(FRAME)
				coat:step(FRAME)
			end
			total += coat.cracks / 3
		end
		local rate = total / 3
		expect.truthy(rate >= 30 and rate <= 45)
	end)
end
