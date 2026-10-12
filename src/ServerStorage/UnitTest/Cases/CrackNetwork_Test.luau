--!strict
-- CrackNetwork_Test: unit tests for StarterPlayerScripts.Client.Anim.CrackNetwork, the precomputed crack-line network
-- (spec phase2-squeeze §1.14, §3.4 "Crack canvas" 1-2, §3.14). Server only (ServerStorage.UnitTest). Pure: arrays only.
-- Run on Butter's soft shell (ShellGeometry, Low). Contract (numbers from sd/squish.js):
--   * the design's jittered Voronoi: a seed per integer cell at cell + hash3(cell)·0.85 + 0.075, an edge's random value
--     fract(sin((c1 + c2)·(12.9898, 78.233, 37.719))·43758.5453) (squish.js:71-78);
--   * every segment lies on the bisector of its two seeds (both ends equally far from them, in its octave's space:
--     rest / (cell·maxDim), octave 2 × 2.3 + 7.13), inside its shell triangle (barycentric weights >= 0, summing to 1),
--     its UVs inside its part's tile; octave 2 is the finer one (more segments);
--   * reveal: octave 1 at smoothstep(0.03 + 0.8·a.y, 0.1 + 0.8·a.y, crack), octave 2 only past 0.38 at smoothstep(0.38
--     + 0.55·b.y, 0.46 + 0.55·b.y, crack), nothing below 0.015; shown in steps of 0.25; a change only when a segment's
--     step changed, with its previous alpha; line = 0.92·alpha (octave 2 × 0.85), halo = 0.6·alpha (octave 2 × 0.6);
--     reset hides every segment.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local CrackNetwork = t.requireClient("Anim/CrackNetwork")
	local ShellGeometry = t.requireClient("Anim/ShellGeometry")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local LINES = Config.Wax.lines

	local function butterShell(): any
		local blueprint = Blueprints.butter
		local parts = {}
		for _, spec in blueprint.parts do
			if spec.body and spec.face == nil and spec.attach == nil then
				table.insert(parts, {
					shape = spec.shape,
					cframe = CFrame.new((spec.pos or Vector3.zero) * blueprint.scale),
					size = spec.size * blueprint.scale,
				})
			end
		end
		return ShellGeometry.build(parts, "Low")
	end

	local shell = butterShell()
	local network = CrackNetwork.build(shell, "foam")

	local function fract(x: number): number
		return x - math.floor(x)
	end

	local function smoothstep(a: number, b: number, x: number): number
		local u = math.clamp((x - a) / (b - a), 0, 1)
		return u * u * (3 - 2 * u)
	end

	-- What the shader shows for a crack value (squish.js:83-91), as reveal's step.
	local function wanted(octave: number, threshold: number, crack: number): number
		local rv = 0
		if crack >= LINES.skipBelow then
			if octave == 1 then
				rv = smoothstep(0.03 + 0.8 * threshold, 0.1 + 0.8 * threshold, crack)
			elseif crack > 0.38 then
				rv = smoothstep(0.38 + 0.55 * threshold, 0.46 + 0.55 * threshold, crack)
			end
		end
		return math.floor(rv * 4 + 1e-9) / 4
	end

	local function allTouched(): ({ number }, number)
		local touched = {}
		for i = 1, shell.count do
			touched[i] = i
		end
		return touched, shell.count
	end

	local function uniform(value: number): { number }
		local damage = {}
		for i = 1, shell.count do
			damage[i] = value
		end
		return damage
	end

	t.test("the design's seeds and edge values (squish.js:71-78)", function()
		local cx, cy, cz = 1, -2, 3
		local px = cx * 127.1 + cy * 311.7 + cz * 74.7
		local py = cx * 269.5 + cy * 183.3 + cz * 246.1
		local pz = cx * 113.5 + cy * 271.9 + cz * 124.6
		local sx, sy, sz = CrackNetwork.seed(cx, cy, cz)
		expect.near(sx, cx + fract(math.sin(px) * 43758.5453) * 0.85 + 0.075, 1e-9)
		expect.near(sy, cy + fract(math.sin(py) * 43758.5453) * 0.85 + 0.075, 1e-9)
		expect.near(sz, cz + fract(math.sin(pz) * 43758.5453) * 0.85 + 0.075, 1e-9)
		local value = CrackNetwork.edgeValue(1, -2, 3, 2, -2, 3)
		expect.near(value, fract(math.sin(3 * 12.9898 - 4 * 78.233 + 6 * 37.719) * 43758.5453), 1e-9)
		expect.equal(CrackNetwork.edgeValue(2, -2, 3, 1, -2, 3), value)
	end)

	t.test("segments: on the bisector of their seeds, inside their triangle, UVs inside their part's tile", function()
		expect.truthy(network.count > 200)
		local perOctave = { 0, 0 }
		for s = 1, network.count do
			local octave = network.octave[s]
			perOctave[octave] += 1
			local ax, ay, az = CrackNetwork.seed(network.cellAx[s], network.cellAy[s], network.cellAz[s])
			local bx, by, bz = CrackNetwork.seed(network.cellBx[s], network.cellBy[s], network.cellBz[s])
			local A, B = Vector3.new(ax, ay, az), Vector3.new(bx, by, bz)
			for _, p in
				{
					Vector3.new(network.qx0[s], network.qy0[s], network.qz0[s]),
					Vector3.new(network.qx1[s], network.qy1[s], network.qz1[s]),
				}
			do
				expect.near((p - A).Magnitude - (p - B).Magnitude, 0, 1e-4)
			end
			local wa, wb, wc = network.wa[s], network.wb[s], network.wc[s]
			expect.truthy(wa >= -1e-9 and wb >= -1e-9 and wc >= -1e-9)
			expect.near(wa + wb + wc, 1, 1e-9)
			expect.equal(network.part[s], shell.triPart[network.tri[s]])
			expect.equal(
				network.threshold[s],
				CrackNetwork.edgeValue(
					network.cellAx[s],
					network.cellAy[s],
					network.cellAz[s],
					network.cellBx[s],
					network.cellBy[s],
					network.cellBz[s]
				)
			)
			local tile = shell.parts[network.part[s]].tile
			for _, uv in { { network.u0[s], network.v0[s] }, { network.u1[s], network.v1[s] } } do
				expect.truthy(uv[1] >= tile[1] - 1e-9 and uv[1] <= tile[3] + 1e-9)
				expect.truthy(uv[2] >= tile[2] - 1e-9 and uv[2] <= tile[4] + 1e-9)
			end
		end
		expect.truthy(perOctave[1] > 100)
		expect.truthy(perOctave[2] > perOctave[1]) -- the finer octave (× 2.3) has more edges
		expect.near(network.cellSize, Config.Wax.coats.foam.cell * shell.maxDim, 1e-9)
	end)

	t.test("reveal: octave 1 by its edge value, octave 2 past 0.38, steps of 0.25 (squish.js:83-91)", function()
		network:reset()
		local touched, count = allTouched()
		expect.equal(#network:reveal(uniform(0.01), touched, count), 0) -- below 0.015: nothing
		local seenOctave2 = false
		for _, crack in { 0.2, 0.37, 0.6, 0.9 } do
			local before = table.clone(network.alpha)
			local changes = network:reveal(uniform(crack), touched, count)
			local changed: { [number]: boolean } = {}
			for _, change in changes do
				local s = change.segment
				changed[s] = true
				expect.equal(change.previous, before[s])
				expect.equal(change.alpha, network.alpha[s])
				expect.equal(change.octave, network.octave[s])
				expect.equal(change.part, network.part[s])
				expect.deepEqual({ change.u0, change.v0, change.u1, change.v1 }, {
					network.u0[s],
					network.v0[s],
					network.u1[s],
					network.v1[s],
				})
				local octave2 = change.octave == 2
				expect.near(change.line, change.alpha * 0.92 * (if octave2 then 0.85 else 1), 1e-12)
				expect.near(change.halo, change.alpha * 0.6 * (if octave2 then 0.6 else 1), 1e-12)
				if octave2 then
					seenOctave2 = true
					expect.truthy(crack > 0.38)
				end
			end
			for s = 1, network.count do
				expect.equal(network.alpha[s], wanted(network.octave[s], network.threshold[s], crack))
				expect.equal(changed[s] == true, network.alpha[s] ~= before[s])
			end
		end
		expect.truthy(seenOctave2)
		-- Nothing new at the same damage.
		expect.equal(#network:reveal(uniform(0.9), touched, count), 0)
		network:reset()
		for s = 1, network.count do
			expect.equal(network.alpha[s], 0)
		end
		expect.truthy(#network:reveal(uniform(0.9), touched, count) > 0)
	end)

	t.test("buildStep: built in slices over frames it is the same network", function()
		local sliced = CrackNetwork.new(shell, "foam")
		expect.falsy(sliced.finished)
		local slices = 1
		while not sliced:buildStep(250) do
			slices += 1
		end
		expect.truthy(slices > 4)
		expect.truthy(sliced.finished)
		expect.equal(sliced.count, network.count)
		for s = 1, network.count, 37 do
			expect.deepEqual(
				{ sliced.octave[s], sliced.tri[s], sliced.u0[s], sliced.v0[s], sliced.u1[s], sliced.v1[s] },
				{ network.octave[s], network.tri[s], network.u0[s], network.v0[s], network.u1[s], network.v1[s] }
			)
			expect.equal(sliced.threshold[s], network.threshold[s])
		end
	end)

	t.test("reveal reads the damage at each segment's middle and only the segments of the touched vertices", function()
		network:reset()
		local damage = uniform(0)
		local touched = {}
		-- Damage one vertex fully: only segments of its triangles can show, at their interpolated crack value.
		local v = shell.tris[3 * 40 - 2]
		damage[v] = 1
		touched[1] = v
		local changes = network:reveal(damage, touched, 1)
		for _, change in changes do
			local s = change.segment
			local tri = network.tri[s]
			local a, b, c = shell.tris[3 * tri - 2], shell.tris[3 * tri - 1], shell.tris[3 * tri]
			expect.truthy(a == v or b == v or c == v)
			local crack = network.wa[s] * damage[a] + network.wb[s] * damage[b] + network.wc[s] * damage[c]
			expect.equal(change.alpha, wanted(network.octave[s], network.threshold[s], crack))
		end
		-- A vertex not in the touched list is never read.
		local other = shell.tris[3 * 400 - 2]
		damage[other] = 1
		local again = network:reveal(damage, touched, 1)
		for _, change in again do
			local tri = network.tri[change.segment]
			local a, b, c = shell.tris[3 * tri - 2], shell.tris[3 * tri - 1], shell.tris[3 * tri]
			expect.truthy(a == v or b == v or c == v)
		end
	end)
end
