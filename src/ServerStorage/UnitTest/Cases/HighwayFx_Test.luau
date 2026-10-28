--!strict
-- HighwayFx_Test: the physics upgrade's part 4 (2026-10-28, the highway throw; the co-owner's Claude Design page
-- docs/squishy-fx-spec/highway.html, data in Config.HighwayFx). Server only (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * HighwayFxController.lagStep (pure): a slow motion holds the drawn clock back, then it runs catchUp x until it is
--     on the server's clock again, never past it; with the design's slow motions (the release's, and the apex hang of
--     a hangFrom throw) the drawn flight is back on the server's clock before the boost window closes, even on the
--     shortest throw;
--   * hopAt (pure): the roll's hops where HighwayMath.planAt draws them;
--   * squashAxes (pure): the design's up share on the axis nearest the world's up, the travel share along the lane;
--   * Config.HighwayFx: one design zone per game zone; every name a moment plays exists (rings, pops, glows, lights,
--     screens, lines, shakes, FOV kicks, slow motions, sounds, FeelVfxBuilder's templates); a ride-along burst
--     (emit of a counted template) is locked to its squishy; the design's hard rules (CONFIG.rules): shakes within
--     2 deg, FOV kicks within 8 deg, every effect over within 1.5 s, at most 60 particles an effect;
--   * FeelVfxBuilder: Rainbow Road's six bands are flat trails.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local FX = t.requireShared("Config/HighwayFx")
	local HighwayMath = t.requireShared("HighwayMath")
	local FeelFx = t.requireClient("Anim/FeelFx")
	local Highway = t.requireClient("Controllers/HighwayFxController")

	local function builder(): any
		local SDTools = game:GetService("ServerStorage"):FindFirstChild("SDTools")
		local builders = SDTools and SDTools:FindFirstChild("Builders")
		local module = builders and builders:FindFirstChild("FeelVfxBuilder")
		return if module then (require :: any)(module:Clone()) else nil
	end

	-- The drawn clock's lag over a flight with slow motions starting at the given times (real seconds).
	local function lagAt(slows: { { def: any, at: number } }, until_: number): number
		local dt = 1 / 60
		local lag = 0
		local tNow = 0
		while tNow < until_ do
			local scale = 1
			for _, s in slows do
				local v = FeelFx.slowAt(s.def, tNow - s.at)
				if tNow >= s.at and v ~= nil then
					scale = math.min(scale, v)
				end
			end
			lag = Highway.lagStep(lag, dt, scale, FX.catchUp)
			tNow += dt
		end
		return lag
	end

	t.test("lagStep: held back by a slow motion, then catching up, never past", function()
		local lag, rate = Highway.lagStep(0, 0.1, 0.3, 1.5)
		expect.near(lag, 0.07, 1e-9)
		expect.near(rate, 0.3, 1e-9)
		lag, rate = Highway.lagStep(0.07, 0.1, 1, 1.5)
		expect.near(lag, 0.02, 1e-9)
		expect.near(rate, 1.5, 1e-9)
		lag, rate = Highway.lagStep(0.02, 0.1, 1, 1.5)
		expect.equal(lag, 0)
		expect.near(rate, 1.2, 1e-9) -- just enough to land on the server's clock
		lag, rate = Highway.lagStep(0, 0.1, 1, 1.5)
		expect.equal(lag, 0)
		expect.equal(rate, 1)
	end)

	t.test("the drawn flight is back on the server's clock before the boost window closes", function()
		local F = Config.Economy.Highway.flight
		local B = Config.Economy.Highway.boost
		local slows = FX.slowmos
		-- The shortest throw: the release's slow motion only.
		local shortAir = F.airSeconds + F.airPerRoot * math.sqrt(F.carryMin / F.airRoot)
		expect.equal(lagAt({ { def = slows.releaseSlow, at = 0 } }, shortAir - B.beforeCarrySeconds), 0)
		-- A hangFrom throw: the release's and the apex hang at half its air.
		local carry = F.carryShare * FX.hangFrom
		local air = F.airSeconds + F.airPerRoot * math.sqrt(carry / F.airRoot)
		local both = { { def = slows.releaseSlow, at = 0 }, { def = slows.apexHang, at = air / 2 } }
		expect.equal(lagAt(both, air - B.beforeCarrySeconds), 0)
	end)

	t.test("hopAt: the roll's hops where HighwayMath draws them", function()
		local F = Config.Economy.Highway.flight
		local carry, studs = 100, 100 + 4 * F.hopEvery
		expect.equal((Highway.hopAt(carry, studs, 50)), -1)
		local first, hops = Highway.hopAt(carry, studs, carry)
		expect.equal(first, 0)
		expect.equal(hops, 4)
		expect.equal((Highway.hopAt(carry, studs, carry + F.hopEvery - 0.01)), 0)
		expect.equal((Highway.hopAt(carry, studs, carry + F.hopEvery)), 1)
		expect.equal((Highway.hopAt(carry, studs, studs)), 3)
		expect.equal((Highway.hopAt(carry, carry, carry + 5)), -1) -- no roll
		-- Each hop starts on the lane (HighwayMath.planAt's hop height is 0 at its start).
		local plan = {
			x0 = 0,
			arcs = { { startAt = 0, from = 0, y0 = 2, carry = carry, air = 2, peak = 10 } },
			roll = 1,
			studs = studs,
			landsAt = 3,
		}
		local onLane = HighwayMath.planAt(plan, 2)
		expect.near(onLane.Z, carry, 1e-6)
	end)

	t.test("squashAxes: up on the axis nearest the world's up, travel along the lane", function()
		local travel = Vector3.new(0, 0, -1)
		local s = Vector3.new(1.3, 0.7, 1.1)
		expect.equal(Highway.squashAxes(CFrame.identity, travel, s), Vector3.new(1.3, 0.7, 1.1))
		-- Tumbled a quarter turn about X: its Z axis points down, its Y axis along the lane.
		local tumbled = CFrame.Angles(math.pi / 2, 0, 0)
		local out = Highway.squashAxes(tumbled, travel, s)
		expect.near(out.X, 1.3, 1e-5) -- Vector3 holds 32-bit numbers
		expect.near(out.Y, 1.1, 1e-5)
		expect.near(out.Z, 0.7, 1e-5)
	end)

	t.test("every name a moment plays exists; the design's hard rules hold", function()
		expect.equal(#FX.zones, #Config.Economy.Highway.starts)
		local build = builder()
		expect.truthy(build ~= nil)
		local specs = if build then build.SPECS else {}
		local trails = if build then build.TRAILS else {}
		local kinds = {
			ring = FX.rings,
			pop = FX.texts,
			glow = FX.glows,
			light = FX.lights,
			screen = FX.screens,
			lines = FX.lines,
			shake = FX.shakes,
			fov = FX.fovs,
			slowmo = FX.slowmos,
			sound = FX.sounds,
			burst = specs,
			emit = specs,
			trail = trails,
		}
		for moment, events in FX.moments do
			for i, ev in events do
				local found = 0
				for kind, list in kinds do
					local name = ev[kind]
					if name ~= nil then
						found += 1
						if list[name] == nil then
							error(`{moment}[{i}]: no {kind} named {name}`)
						end
					end
				end
				if ev.freeze ~= nil then
					found += 1
					expect.truthy(ev.freeze <= 0.12)
				end
				if ev.stop == nil then
					expect.equal(found, 1)
				end
				if ev.emit and specs[ev.emit].Count ~= nil then
					-- a ride-along burst: locked to its squishy, held for its particles' life
					expect.truthy(specs[ev.emit].LockedToPart == true and ev["for"] ~= nil)
				end
			end
		end
		for _, def in FX.shakes do
			expect.truthy(def.amplitude <= 2 and def.time <= 1.5)
		end
		for _, def in FX.fovs do
			expect.truthy(math.abs(def.delta) <= 8 and def.attack + def.hold + def.release <= 1.5)
		end
		for _, list in { FX.rings, FX.texts, FX.glows, FX.lights } do
			for _, def in list do
				expect.truthy(def.time <= 1.5)
			end
		end
		for _, def in FX.screens do
			expect.truthy(def.fadeIn + def.hold + def.fadeOut <= 1.5)
		end
		for _, def in FX.slowmos do
			expect.truthy(def.speed > 0 and def.speed < 1)
		end
		expect.truthy(FX.hero.time <= 1.5 and FX.catchUp > 1)
		for name, spec in specs do
			local live = if spec.Count then spec.Count else spec.Rate * spec.Lifetime[2]
			if live > 60 then
				error(`{name}: {live} particles`)
			end
		end
	end)

	t.test("FeelVfxBuilder: Rainbow Road's bands are flat trails", function()
		local build = builder()
		if build == nil then
			error("no FeelVfxBuilder")
		end
		for _, name in { "bandRed", "bandOrange", "bandYellow", "bandMint", "bandSky", "bandViolet" } do
			local spec = build.TRAILS[name]
			expect.truthy(spec ~= nil and spec.Flat == true and spec.FaceCamera == false)
		end
	end)
end
