--!strict
-- SoftBody_Test: unit tests for StarterPlayerScripts.Client.Anim.SoftBody, the port of the 3D Lab's SoftSquish (spec
-- phase2-squeeze §1.3-§1.12, §3.3, §3.14). Server only (ServerStorage.UnitTest). Pure: time is injected (60 fps
-- steps), randomness through FakeRng, no instances. Run on Butter's soft shell (ShellGeometry, its Body RB block and
-- two boxes; the toy faces -Z, so "the front" is its -Z side). Contract (every number from sd/squish.js, but the user's
-- deeper finger dents of 2026-10-12):
--   * new: the design's box sizes (rF, dF, the memory cap, maxPull, rP, eps) from the shell's rest bounds, dF and the cap
--     at the user's 1.5·rF / 0.55·minDim and 1.7·rF (design: 0.95 / 0.42, 1.1); an unknown feel is foam; at rest it
--     shows the rest positions, sleeps and steps nothing;
--   * profile: the live dent exp(-s - q2)·(1 - beta·s) and its derived rim peaks (foam/plush 6.2% of d at 1.56·r, mochi
--     13.5% at 1.41·r, jelly 14.9% at 1.40·r), cut off past 7; a held finger settles to dF·profile·lump along the
--     press, its rim raised, nothing sideways; a finger dent shows in the first frame and is half deep within 150 ms
--     (owner 2026-10-26: faster than the design's);
--   * memory: slowRise = 1 - smoothstep(age / rise): 50% at rise / 2; a released dent creeps back on it, gone at rise;
--   * stamping: a stroke is stamped ceil(len / (0.28·rF)) times; a jump past 3.5·rF has no stroke; the smear moves
--     memory sideways by (move)·smear·es only where es = exp(-0.7·s - q) >= 0.03;
--   * stretch: pullTo soft-clamps to maxPull·tanh(L / maxPull) and slips past 1.75·maxPull; mochi keeps 22% of a pull;
--   * the thumb crunch: its target rhythm (0.5 / 1 / 0.71 at phase 0.25 / 0.6 / 0.85, from 0.42 after the first cycle),
--     the thumbs at ctr.x ∓ (0.48 - 0.2·P)·0.36·s.x (0.1728·s.x out at P = 0, 0.1008·s.x at P = 1); the pinch field
--     ridges the front toward the camera between the thumbs, folds the top down and swells the ends;
--   * palms: two brushes at the box's X sides pressing inward with the design's sizes;
--   * kicks and sounds out; the squish face; restHit; written lists and positions (rest + displacement + bulge, inside
--     the anchored bounds); a long dt is clamped; 0.12 s after the motion settles it snaps to rest and sleeps.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local FRAME = 1 / 60
local FRONT = Vector3.new(0, 0, -1) -- the toys face -Z
local BODY_PART = 1 -- Butter's Body (RB), its biggest shell

return function(t: Context)
	local SoftBody = t.requireClient("Anim/SoftBody")
	local ShellGeometry = t.requireClient("Anim/ShellGeometry")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local Config = t.requireShared("Config")
	local FakeRng = t.requireFake("FakeRng")
	local expect = t.expect
	local KNEAD = Config.Knead

	local shells: { [string]: any } = {}

	-- Butter's soft shell (its plain body parts at blueprint scale), built once per quality.
	local function butterShell(quality: string): any
		if shells[quality] == nil then
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
			shells[quality] = ShellGeometry.build(parts, quality)
		end
		return shells[quality]
	end

	local function newBody(feel: string, quality: string?): (any, any)
		local shell = butterShell(quality or "Low")
		local body = SoftBody.new(shell, { feel = feel, squeezeDepth = 0.62, rng = FakeRng.new(7) })
		return body, shell
	end

	local function run(body: any, seconds: number)
		for _ = 1, math.round(seconds / FRAME) do
			body:step(FRAME)
		end
	end

	local function rest(shell: any, i: number): Vector3
		return Vector3.new(shell.px[i], shell.py[i], shell.pz[i])
	end

	local function normal(shell: any, i: number): Vector3
		return Vector3.new(shell.nx[i], shell.ny[i], shell.nz[i])
	end

	-- The vertex of `part` nearest `point` among those whose rest normal is within ~1° of `facing` (any when nil).
	local function nearest(shell: any, point: Vector3, facing: Vector3?, part: number?): number
		local best, bestDistance = 0, math.huge
		for i = 1, shell.count do
			if
				(part == nil or shell.vertexPart[i] == part)
				and (facing == nil or normal(shell, i):Dot(facing) > 0.9998)
			then
				local distance = (rest(shell, i) - point).Magnitude
				if distance < bestDistance then
					best, bestDistance = i, distance
				end
			end
		end
		assert(best > 0, "no vertex found")
		return best
	end

	-- A point on Butter's flat front (the Body's -Z face) at (x, y).
	local function frontVertex(shell: any, x: number, y: number): number
		return nearest(shell, Vector3.new(x, y, shell.restMin.Z), FRONT, BODY_PART)
	end

	local function press(body: any, shell: any, i: number)
		body:fingerDown(rest(shell, i), normal(shell, i))
	end

	local function kinds(events: { any }): { string }
		local out = {}
		for _, event in events do
			table.insert(out, event.kind)
		end
		return out
	end

	local function find(events: { any }, kind: string): any
		for _, event in events do
			if event.kind == kind then
				return event
			end
		end
		return nil
	end

	t.test("new: the design's box from the shell's rest bounds (squish.js:171-177); asleep at rest", function()
		local body, shell = newBody("foam")
		local size = shell.size
		local maxDim, minDim = math.max(size.X, size.Y, size.Z), math.min(size.X, size.Y, size.Z)
		expect.near(body.maxDim, maxDim, 1e-6)
		expect.near(body.minDim, minDim, 1e-6)
		expect.near(body.rF, 0.15 * maxDim, 1e-6)
		-- User 2026-10-12: deeper dents (design: 0.95·rF / 0.42·minDim and a 1.1·rF cap, squish.js:173-174).
		expect.near(body.dF, math.min(1.5 * 0.15 * maxDim, 0.55 * minDim), 1e-6)
		expect.near(body.cap, 1.7 * 0.15 * maxDim, 1e-6)
		expect.near(body.maxPull, 0.36 * maxDim, 1e-6)
		expect.near(body.rP, 0.17 * maxDim, 1e-6)
		expect.near(body.eps, 2e-4 * maxDim, 1e-9)
		expect.near((body.center - (shell.restMin + shell.restMax) / 2).Magnitude, 0, 1e-6)
		expect.equal(body.feel, "foam")
		expect.equal(SoftBody.new(shell, { feel = "lava", squeezeDepth = 0.62 }).feel, "foam") -- squish.js:35
		-- Lumps (squish.js:176-177): J in [1 - lump / 2, 1 + lump / 2], uneven.
		local lowest, highest = math.huge, -math.huge
		for i = 1, shell.count do
			lowest, highest = math.min(lowest, body.J[i]), math.max(highest, body.J[i])
			expect.equal(body.px[i], shell.px[i])
			expect.equal(body.py[i], shell.py[i])
			expect.equal(body.pz[i], shell.pz[i])
		end
		expect.truthy(lowest >= 1 - 0.16 and highest <= 1 + 0.16 and highest - lowest > 0.1)
		expect.falsy(body.active)
		expect.falsy(body:step(FRAME))
		expect.equal(body.writtenCount, 0)
	end)

	t.test("profile: the live dent and its derived rim peaks; cut off past 7 (squish.js:575-584)", function()
		expect.near(SoftBody.profile(0, 0, 0.7, 1), 1, 1e-12)
		expect.near(SoftBody.profile(0.5, 0.3, 0.7, 1), math.exp(-0.8) * (1 - 0.35), 1e-12)
		expect.near(SoftBody.profile(0.5, 0, 0.245, 1.5), math.exp(-(0.5 ^ 1.5)) * (1 - 0.245 * 0.5), 1e-12)
		expect.equal(SoftBody.profile(7.01, 0, 0.7, 1), 0)
		expect.equal(SoftBody.profile(1, 7.01, 0.7, 1), 0)
		-- beta, rim height (share of d), at sideways distance (× r): spec §1.5 (derived)
		for _, row in { { 0.7, 0.062, 1.56 }, { 1, 0.135, 1.41 }, { 1.05, 0.149, 1.40 } } do
			local lowest, at = 0, 0
			for k = 0, 7000 do
				local s = k * 1e-3
				local value = SoftBody.profile(s, 0, row[1], 1)
				if value < lowest then
					lowest, at = value, math.sqrt(s)
				end
			end
			expect.near(-lowest, row[2], 0.0006)
			expect.near(at, row[3], 0.006)
		end
	end)

	t.test("a held finger settles to dF·profile·lump along the press, the rim raised, nothing sideways", function()
		local body, shell = newBody("foam", "High")
		local contact = frontVertex(shell, 0, 0.15)
		press(body, shell, contact)
		run(body, 2)
		local c, u = rest(shell, contact), -normal(shell, contact) -- into the toy: +Z
		local checked, rim = 0, 0
		for i = 1, shell.count do
			if shell.vertexPart[i] == BODY_PART and normal(shell, i):Dot(FRONT) > 0.9998 then
				local side = rest(shell, i) - c
				local s = side:Dot(side) / (body.rF * body.rF)
				if s < 7 then
					local want = body.dF * SoftBody.profile(s, 0, 0.7, 1) * body.J[i]
					local x = body:displacement(i)
					expect.near(x:Dot(u), want, 0.02 * body.dF)
					expect.near((x - u * x:Dot(u)).Magnitude, 0, 0.02 * body.dF)
					checked += 1
					if want < -0.01 * body.dF then
						rim += 1
						expect.truthy(x:Dot(u) < 0) -- pushed out toward the finger
					end
				end
			end
		end
		expect.truthy(checked > 30)
		expect.truthy(rim > 4)
	end)

	-- Owner 2026-10-26 ("the dents trail behind my mouse, they show up late"): a finger dent starts in the first frame
	-- and reaches half its depth within 150 ms (the design's 35 ms wait, 90 ms ease-in and softer depth spring: 233 ms).
	t.test("a finger dent shows in the first frame and reaches half its depth within 150 ms (foam)", function()
		local body, shell = newBody("foam", "High")
		local contact = frontVertex(shell, 0, 0.15)
		local u = -normal(shell, contact)
		press(body, shell, contact)
		local depths = {}
		for f = 1, 120 do
			body:step(FRAME)
			depths[f] = body:displacement(contact):Dot(u)
		end
		local peak = 0
		for _, d in depths do
			peak = math.max(peak, d)
		end
		expect.truthy(depths[1] > 0)
		local half = 0
		for f, d in depths do
			if d >= 0.5 * peak then
				half = f
				break
			end
		end
		expect.truthy(half > 0 and half * FRAME <= 0.15)
	end)

	t.test("memory: slowRise = 1 - smoothstep(age / rise); a released dent creeps back (squish.js:562-566)", function()
		expect.near(SoftBody.slowRise(0, 1.9), 1, 1e-12)
		expect.near(SoftBody.slowRise(0.95, 1.9), 0.5, 1e-12)
		expect.near(SoftBody.slowRise(1.9, 1.9), 0, 1e-12)
		expect.near(SoftBody.slowRise(4, 1.9), 0, 1e-12)
		local body, shell = newBody("foam")
		local contact = frontVertex(shell, 0, 0.15)
		local u = -normal(shell, contact)
		press(body, shell, contact)
		run(body, 1.5)
		local kept = body:memory(contact):Dot(u)
		-- the stamp keeps (1 - fast) of the dent: dF·(1 - 0.12)·J at the contact (squish.js:489)
		expect.near(kept, body.dF * 0.88 * body.J[contact], 0.01 * body.dF)
		body:fingerUp()
		run(body, 0.95)
		expect.near(body:displacement(contact):Dot(u), 0.5 * kept, 0.08 * kept)
		run(body, 1.2)
		expect.equal(body:memory(contact).Magnitude, 0)
		expect.near(body:displacement(contact).Magnitude, 0, 0.02 * body.dF)
	end)

	t.test("stamping: ceil(len / (0.28·rF)) stamps; no stroke past 3.5·rF (squish.js:336-337, 512)", function()
		local body, shell = newBody("foam")
		local a = frontVertex(shell, -0.2, 0.15)
		local b = frontVertex(shell, 0.05, 0.15)
		press(body, shell, a)
		run(body, 0.2) -- pressed in (a brush stamps only once deeper than 1e-7, after its 35 ms delay: squish.js:531, 536)
		local before = body.stamps
		body:fingerMove(rest(shell, b), normal(shell, b))
		body:step(FRAME)
		local length = (rest(shell, b) - rest(shell, a)).Magnitude
		expect.truthy(length < 3.5 * body.rF)
		expect.equal(body.stamps - before, math.ceil(length / (0.28 * body.rF)))
		-- A held, unmoved brush stamps its own point once a frame (squish.js:536).
		before = body.stamps
		body:step(FRAME)
		expect.equal(body.stamps - before, 1)
		-- Jump to the back: no stroke, one stamp at the new point.
		local back = nearest(shell, rest(shell, b) * Vector3.new(1, 1, -1), -FRONT, BODY_PART)
		expect.truthy((rest(shell, back) - rest(shell, b)).Magnitude > 3.5 * body.rF)
		before = body.stamps
		body:fingerMove(rest(shell, back), normal(shell, back))
		body:step(FRAME)
		expect.equal(body.stamps - before, 1)
	end)

	t.test("smear: memory moves sideways by move·smear·es where es >= 0.03 (squish.js:491, 502-505)", function()
		local body, shell = newBody("foam", "High")
		local a = frontVertex(shell, 0, 0.12)
		press(body, shell, a)
		run(body, 0.2) -- pressed in: the stamps at A keep the memory along the press only
		local pb = rest(shell, a) + Vector3.new(0.2 * 0.28 * body.rF, 0, 0) -- one stamp, along the flat front
		body:fingerMove(pb, FRONT)
		body:step(FRAME)
		local move = pb - rest(shell, a)
		local u = -FRONT
		local smeared, still = 0, 0
		for i = 1, shell.count do
			local side = rest(shell, i) - pb
			local h = side:Dot(u)
			local across = side - u * h
			local ha = if h > 0 then h else 0.25 * h
			local q = ha * ha / (1.4 * body.rF) ^ 2
			local s = across:Dot(across) / (body.rF * body.rF)
			local es = math.exp(-0.7 * s - q)
			local memory = body:memory(i)
			local sideways = memory - u * memory:Dot(u)
			if es >= 0.03 and s <= 6 and q <= 6 then
				expect.near((sideways - move * 0.62 * es).Magnitude, 0, 1e-6)
				smeared += 1
			else
				expect.near(sideways.Magnitude, 0, 1e-6)
				still += 1
			end
		end
		expect.truthy(smeared > 20 and still > 20)
	end)

	t.test("stretch: maxPull·tanh(L / maxPull), slips past 1.75·maxPull (squish.js:344-359, 367-375)", function()
		local body, shell = newBody("foam")
		local g = frontVertex(shell, 0, 0.15)
		local pg, n = rest(shell, g), normal(shell, g)
		press(body, shell, g)
		run(body, 0.2)
		body:takeEvents()
		local L = 0.5 * body.maxPull
		body:pullTo(pg + n * L - Vector3.xAxis * 5, Vector3.xAxis) -- passes L in front of the grabbed point
		expect.truthy(body.pulling)
		expect.near(body.pullLength, body.maxPull * math.tanh(0.5), 1e-5)
		expect.near((body:pullVector() - n * body.pullLength).Magnitude, 0, 1e-5)
		local started = body:takeEvents()
		expect.deepEqual(kinds(started), { "squisherKick" })
		expect.equal(started[1].amount, -0.3)
		expect.equal(body:brush(1).on, false) -- the finger let go (squish.js:349)
		run(body, 0.3)
		body:pullTo(pg + n * (1.76 * body.maxPull) - Vector3.xAxis * 5, Vector3.xAxis)
		expect.falsy(body.pulling)
		local events = body:takeEvents()
		local snap = find(events, "snap")
		expect.truthy(snap ~= nil and snap.slipped == true)
		expect.near(snap.amount, math.tanh(0.5), 1e-6)
		expect.near(find(events, "air").amount, 0.4 * math.tanh(0.5), 1e-6)
		local kick = find(events, "kick")
		expect.near(kick.amount, -0.05 * math.tanh(0.5) - 0.012, 1e-6)
		expect.equal(kick.axis, "Z")
		expect.near(find(events, "squisherKick").amount, 1.2 * math.tanh(0.5), 1e-6)
	end)

	t.test("plastic: mochi keeps 22% of a pull as memory, which then slow-rises (squish.js:370, 376-388)", function()
		local body, shell = newBody("mochi")
		local g = frontVertex(shell, 0, 0.15)
		local pg = rest(shell, g)
		press(body, shell, g)
		run(body, 0.2)
		local L = 0.5 * body.maxPull
		body:pullTo(pg + Vector3.xAxis * L + FRONT * 5, -FRONT) -- along the face, L to the side
		run(body, 0.3)
		local pulled = body.pullLength
		expect.near(pulled, body.maxPull * math.tanh(0.5), 1e-6)
		body:fingerUp()
		expect.near(body:memory(g):Dot(Vector3.xAxis), 0.22 * pulled, 1e-6)
		expect.equal(body.age[g], 0)
		run(body, 2.8)
		expect.equal(body:memory(g).Magnitude, 0)
	end)

	t.test("crunchTarget: press in, hold, ease off; from the second cycle from 0.42 (squish.js:444-447)", function()
		expect.near(SoftBody.crunchTarget(0), 0, 1e-12)
		expect.near(SoftBody.crunchTarget(0.25 * 0.56), 0.5, 1e-9)
		expect.near(SoftBody.crunchTarget(0.6 * 0.56), 1, 1e-9)
		expect.near(SoftBody.crunchTarget(0.85 * 0.56), 1 - 0.58 * 0.5, 1e-9)
		expect.near(SoftBody.crunchTarget(0.56 + 0.001), 0.42, 0.001)
		expect.near(SoftBody.crunchTarget(0.56 + 0.25 * 0.56), 0.42 + 0.58 * 0.5, 1e-9)
		expect.near(SoftBody.crunchTarget(2 * 0.56 + 0.6 * 0.56), 1, 1e-9)
	end)

	t.test("thumbs: at ctr.x ∓ (0.48 - 0.2·P)·0.36·s.x, 0.0384·s.y up (squish.js:426-478)", function()
		local body, shell = newBody("foam", "High")
		local size, ctr = shell.size, body.center
		body:thumbs(true)
		body:step(FRAME)
		expect.truthy(body.crunchP < 0.01)
		local tolerance = 0.6 * shell.spacing
		local function check(P: number)
			local a, b = body:brush(1), body:brush(2)
			expect.equal(a.kind, "thumb")
			expect.equal(b.kind, "thumb")
			local out = (0.48 - 0.2 * P) * 0.36 * size.X
			-- Thumb A is the design's left (-x), our +X (the toy turned 180°): the viewer's left.
			expect.near(a.centre.X - ctr.X, out, tolerance)
			expect.near(b.centre.X - ctr.X, -out, tolerance)
			for _, thumb in { a, b } do
				expect.near(thumb.centre.Y - ctr.Y, 0.12 * 0.32 * size.Y, tolerance)
				expect.truthy(thumb.direction.Z >= 0.55) -- pressing into the front (+Z)
			end
		end
		check(body.crunchP)
		expect.near(body:brush(1).centre.X - ctr.X, 0.1728 * size.X, tolerance)
		run(body, 0.38)
		expect.truthy(body.crunchP > 0.97)
		check(body.crunchP)
		expect.near(body:brush(1).centre.X - ctr.X, 0.1008 * size.X, 1.2 * tolerance)
		local tip = body:thumbTip(1)
		local a = body:brush(1)
		expect.near((tip - (a.centre + a.direction * a.depth)).Magnitude, 0, 1e-6)
		expect.equal(body:thumbTip(3), nil)
	end)

	t.test("pinch: the front ridges toward the camera, the top folds, the ends swell (squish.js:549-574)", function()
		local body, shell = newBody("foam", "High")
		local size, ctr = shell.size, body.center
		body:thumbs(true)
		run(body, 0.39)
		expect.truthy(body.crunchP > 0.97)
		-- Between the thumbs on the front, clear of their dents (closer in, a dent's positive part wins the max and
		-- flattens the ridge, squish.js:582): toward the camera (-Z).
		local ridge = frontVertex(shell, ctr.X, ctr.Y + 0.4 * size.Y)
		expect.truthy(body:displacement(ridge).Z < -0.01 * size.Z)
		-- The top between the thumbs, front half: folds down.
		local top = nearest(shell, Vector3.new(ctr.X, shell.restMax.Y, ctr.Z - 0.3 * size.Z), Vector3.yAxis, BODY_PART)
		expect.truthy(body:displacement(top).Y < -0.03 * size.Y)
		-- The ends (0.45·s.x out, front, upper half): up, toward the camera and in toward the middle.
		for _, sign in { -1, 1 } do
			local x = ctr.X + sign * 0.45 * size.X
			local finish = nearest(shell, Vector3.new(x, ctr.Y + 0.3 * size.Y, shell.restMin.Z), nil, BODY_PART)
			local d = body:displacement(finish)
			expect.truthy(d.Y > 0.02 * size.Y)
			expect.truthy(d.Z < 0)
			expect.truthy(d.X * sign < 0)
		end
		expect.truthy(body.faceSquish) -- P > 0.3 (squish.js:620)
	end)

	t.test("palms: two inward brushes at the box's X sides with the design's sizes (squish.js:389-397)", function()
		local body, shell = newBody("foam")
		local size, ctr = shell.size, body.center
		body:palms(true)
		expect.truthy(body.holding)
		local seen = {}
		for slot = 1, 2 do
			local palm = body:brush(slot)
			expect.equal(palm.kind, "palm")
			local side = if palm.centre.X > ctr.X then 1 else -1
			seen[side] = true
			expect.near(palm.centre.X, if side > 0 then shell.restMax.X else shell.restMin.X, 1e-6)
			expect.near(palm.centre.Y, ctr.Y, 1e-6)
			expect.near(palm.centre.Z, ctr.Z, 1e-6)
			expect.near((palm.direction - Vector3.new(-side, 0, 0)).Magnitude, 0, 1e-6)
			expect.near(palm.radius, 0.5 * math.min(size.Y, size.Z), 1e-6)
			expect.near(palm.falloff, 0.55 * size.X, 1e-6)
			expect.near(palm.depthMax, math.min(0.3 * size.X, (1 - 0.62) * 0.55 * size.X), 1e-6)
			expect.near(palm.beta, 0.7 * 0.35, 1e-12)
			expect.equal(palm.power, 1.5)
		end
		expect.truthy(seen[1] and seen[-1])
		run(body, 0.6)
		expect.truthy(body.palmC > 0.85)
		-- squeezed in from both sides: the X ends move toward the middle
		local left = nearest(shell, Vector3.new(shell.restMin.X, ctr.Y, ctr.Z), -Vector3.xAxis, BODY_PART)
		expect.truthy(body:displacement(left).X > 0)
	end)

	t.test("kicks and sounds out (squish.js:327-328, 363-365, 395-402, 431-437)", function()
		local body, shell = newBody("foam")
		local contact = frontVertex(shell, 0, 0.15)
		press(body, shell, contact)
		local down = body:takeEvents()
		expect.deepEqual(kinds(down), { "kick", "squisherKick", "press" })
		expect.equal(down[1].amount, 0.022)
		expect.equal(down[1].axis, "Z")
		expect.equal(down[2].amount, -0.6)
		expect.equal(down[3].brush, "finger")
		expect.near(down[3].pan, 0, 0.02)
		run(body, 0.5)
		local depth = body:brush(1).depth / body:brush(1).depthMax
		body:fingerUp()
		local up = body:takeEvents()
		expect.deepEqual(kinds(up), { "kick", "squisherKick", "release", "air" })
		expect.equal(up[1].amount, -0.016)
		expect.equal(up[2].amount, 0.7)
		expect.near(up[3].amount, math.clamp(depth, 0.25, 1), 1e-9)
		expect.near(up[4].amount, 0.6 * math.clamp(depth, 0.25, 1), 1e-9)
		body:fingerUp() -- nothing held: nothing happens
		expect.equal(#body:takeEvents(), 0)
		body:palms(true)
		local on = body:takeEvents()
		expect.deepEqual(kinds(on), { "kick", "squisherKick", "press" })
		expect.deepEqual({ on[1].amount, on[2].amount, on[3].pan }, { 0.05, -0.6, 0 })
		expect.deepEqual({ on[1].axis, on[3].brush }, { "X", "palm" })
		run(body, 0.5)
		local palmC = body.palmC
		body:palms(false)
		local off = body:takeEvents()
		expect.deepEqual(kinds(off), { "kick", "squisherKick", "release", "air" })
		expect.deepEqual({ off[1].amount, off[2].amount }, { -0.045, 0.8 })
		expect.equal(off[1].axis, "X")
		expect.near(off[3].amount, math.clamp(palmC, 0.3, 1), 1e-9)
		expect.near(off[4].amount, math.clamp(palmC, 0.3, 1), 1e-9)
		body:thumbs(true)
		local thumbsOn = body:takeEvents()
		expect.deepEqual(kinds(thumbsOn), { "kick", "squisherKick", "press" })
		expect.deepEqual({ thumbsOn[1].amount, thumbsOn[2].amount }, { 0.035, -0.5 })
		expect.equal(thumbsOn[1].axis, "Z")
		expect.equal(thumbsOn[3].brush, "thumb")
		body:thumbs(false)
		local thumbsOff = body:takeEvents()
		expect.deepEqual(kinds(thumbsOff), { "kick", "squisherKick", "release", "air" })
		expect.deepEqual(
			{ thumbsOff[1].amount, thumbsOff[2].amount, thumbsOff[3].amount, thumbsOff[4].amount },
			{ -0.03, 0.6, 0.8, 0.8 }
		)
	end)

	t.test("the squish face: palms past 0.3 (held to 0.18), a deep finger, a long pull (squish.js:616-620)", function()
		local body, shell = newBody("foam")
		body:palms(true)
		run(body, 0.5)
		expect.truthy(body.faceSquish)
		body:palms(false)
		local sawHeld = false
		for _ = 1, 120 do
			body:step(FRAME)
			if body.palmC < 0.3 and body.palmC > 0.18 then
				sawHeld = true
				expect.truthy(body.faceSquish)
			elseif body.palmC < 0.18 then
				expect.falsy(body.faceSquish)
			end
		end
		expect.truthy(sawHeld)
		-- A deep foam finger on the back is far from the face: no squish face; on jelly it is.
		local cases: { [string]: boolean } = { foam = false, jelly = true }
		for feel, wanted in cases do
			local soft = newBody(feel)
			local back = nearest(shell, Vector3.new(0, 0.15, shell.restMax.Z), -FRONT, BODY_PART)
			press(soft, shell, back)
			run(soft, 0.4)
			expect.equal(soft.faceSquish, wanted)
		end
		-- A deep finger near the face (the fallback face centre: ctr.y + 0.15·s.y on the front).
		local near = newBody("foam")
		press(near, shell, frontVertex(shell, 0, near.center.Y + 0.15 * shell.size.Y))
		run(near, 0.4)
		expect.truthy(near.faceSquish)
		-- A pull longer than 0.3·maxPull.
		local pulling = newBody("plush")
		local g = frontVertex(shell, 0.3, 0.15)
		press(pulling, shell, g)
		pulling:step(FRAME)
		pulling:pullTo(rest(shell, g) + normal(shell, g) * (0.5 * pulling.maxPull) - Vector3.xAxis * 5, Vector3.xAxis)
		pulling:step(FRAME)
		expect.truthy(pulling.faceSquish)
	end)

	t.test("restHit: a barycentric hit to its rest point and normalized rest normal (squish.js:461-470)", function()
		local body, shell = newBody("foam")
		local a, b, c = shell.tris[28], shell.tris[29], shell.tris[30]
		local point, n = body:restHit(a, b, c, 0.2, 0.3, 0.5)
		local want = rest(shell, a) * 0.2 + rest(shell, b) * 0.3 + rest(shell, c) * 0.5
		local wantN = (normal(shell, a) * 0.2 + normal(shell, b) * 0.3 + normal(shell, c) * 0.5).Unit
		expect.near((point - want).Magnitude, 0, 1e-6)
		expect.near((n - wantN).Magnitude, 0, 1e-6)
	end)

	t.test("written: only moved vertices; shown = rest + displacement + bulge, inside the anchors", function()
		local body, shell = newBody("jelly")
		local contact = frontVertex(shell, 0, 0.15)
		press(body, shell, contact)
		local previous = table.clone(body.px)
		for _ = 1, 20 do
			body:step(FRAME)
			local seen: { [number]: boolean } = {}
			for k = 1, body.writtenCount do
				local i = body.written[k]
				expect.falsy(seen[i])
				seen[i] = true
			end
			for i = 1, shell.count do
				if not seen[i] then
					expect.equal(body.px[i], previous[i])
				end
				previous[i] = body.px[i]
				local x = body:displacement(i)
				-- this step's positions use the bulge from before its update (squish.js:555, 595, 611)
				local bulge = body.shownInflation * (1 - math.min(1, x.Magnitude / (0.25 * body.dF)))
				local want = rest(shell, i) + x + normal(shell, i) * bulge
				local shown = Vector3.new(body.px[i], body.py[i], body.pz[i])
				expect.near((shown - want).Magnitude, 0, 2 * body.writeEps + 1e-6)
				expect.truthy(shown.X >= shell.boundsMin.X and shown.X <= shell.boundsMax.X)
				expect.near(body.press[i], math.min(1, x.Magnitude / body.dF), 1e-5)
			end
		end
		expect.truthy(body.inflation > 0) -- the dent's volume swells the rest (squish.js:594-596, 611)
	end)

	t.test("a sleeping vertex sits exactly at rest: no displacement left behind", function()
		local body, shell = newBody("foam", "High")
		press(body, shell, frontVertex(shell, 0, 0.15))
		local sleepers = 0
		for frame = 1, 150 do
			if frame == 40 then
				body:fingerUp()
			end
			body:step(FRAME)
			for i = 1, shell.count do
				if body.sleeping[i] then
					sleepers += 1
					expect.equal(body.xs[i], 0)
					expect.equal(body.ys[i], 0)
					expect.equal(body.zs[i], 0)
				end
			end
		end
		expect.truthy(sleepers > 0)
	end)

	t.test("a long frame is clamped to Config.Anim.Scheduler.maxDt", function()
		local slow, shell = newBody("foam")
		local fast = newBody("foam")
		local contact = frontVertex(shell, 0, 0.15)
		press(slow, shell, contact)
		press(fast, shell, contact)
		slow:step(1)
		fast:step(Config.Anim.Scheduler.maxDt)
		for i = 1, shell.count do
			expect.equal(slow.px[i], fast.px[i])
		end
	end)

	t.test("sleep: 0.12 s after the motion settles it snaps to rest exactly and stops (squish.js:640-652)", function()
		local body, shell = newBody("foam")
		press(body, shell, frontVertex(shell, 0, 0.15))
		run(body, 0.3)
		body:fingerUp()
		local serial = body.restCount
		local seconds = 0
		while body.active and seconds < 6 do
			body:step(FRAME)
			seconds += FRAME
		end
		expect.falsy(body.active)
		expect.truthy(seconds > KNEAD.feels.foam.rise) -- the memory had to rise first
		expect.equal(body.restCount, serial + 1)
		for i = 1, shell.count do
			expect.equal(body.px[i], shell.px[i])
			expect.equal(body.py[i], shell.py[i])
			expect.equal(body.pz[i], shell.pz[i])
			expect.equal(body:displacement(i).Magnitude, 0)
			expect.equal(body.press[i], 0)
		end
		expect.equal(body.inflation, 0)
		expect.falsy(body.faceSquish)
		expect.falsy(body:step(FRAME))
	end)
end
