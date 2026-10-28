--!strict
-- FlightFx_Test: the physics upgrade's part 3 (2026-10-28, squishies flying in duels; the co-owner's Claude Design page
-- docs/squishy-fx-spec/duelflight.html, data in Config.FlightFx). Server only (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * FlightFxController (pure): the design's squash tracks at their keys and held after the last; a wobble within its
--     amplitude and 1 outside its time; flightShape = the release pop over its last key (1 once the pop is over: the
--     game keeps its cruise stretch) x the jiggle, and the spin at 540 / 900 deg/s; isCharged from chargedFrom;
--   * Config.FlightFx: every name a moment plays exists (poses, rings, pops, glows, screens, camera moves, calls and
--     FeelVfxBuilder's templates); views are "1P" / "3P" / "R1P" / "OBS"; the design's hard rules (CONFIG.rules): every
--     effect over within 1.5 s, camera turns within 2 deg, FOV kicks within 8 deg, at most 60 particles an effect; pose
--     keys rig joints only, each step under 180 deg; the design's KEEP: the 1 s charge;
--   * FeelVfxBuilder: the charge sparkles are drawn inward.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local FX = t.requireShared("Config/FlightFx")
	local Flight = t.requireClient("Controllers/FlightFxController")

	local function builder(): any
		local SDTools = game:GetService("ServerStorage"):FindFirstChild("SDTools")
		local builders = SDTools and SDTools:FindFirstChild("Builders")
		local module = builders and builders:FindFirstChild("FeelVfxBuilder")
		return if module then (require :: any)(module:Clone()) else nil
	end

	t.test("squash tracks and wobbles: the design's curves", function()
		local grow = FX.squashes.chargeGrow
		expect.equal(Flight.squashAt(grow, 0), Vector3.one)
		expect.truthy((Flight.squashAt(grow, 1) - Vector3.one * 1.18).Magnitude < 1e-9)
		expect.truthy((Flight.squashAt(grow, 3) - Vector3.one * 1.18).Magnitude < 1e-9) -- held
		local rel = FX.squashes.releaseStretch
		expect.truthy((Flight.squashAt(rel, 0) - Vector3.new(0.8, 0.8, 1.45)).Magnitude < 1e-9)
		expect.truthy((Flight.squashAt(rel, 0.06) - Vector3.new(1.1, 1.1, 0.88)).Magnitude < 1e-9)
		local jiggle = FX.wobbles.flightJiggle
		for i = 0, 40 do
			local w = Flight.wobbleAt(jiggle, jiggle.time * i / 40)
			expect.truthy(math.abs(w.X - 1) <= jiggle.amplitude + 1e-9 and math.abs(w.Y - 1) <= jiggle.amplitude + 1e-9)
			expect.near(w.X, w.Z, 1e-12)
		end
		expect.equal(Flight.wobbleAt(jiggle, jiggle.time + 0.01), Vector3.one)
		expect.equal(Flight.wobbleAt(jiggle, -0.01), Vector3.one)
	end)

	t.test("flightShape: the pop over its last key, the jiggle, the spin", function()
		local shape, spin = Flight.flightShape(0, false)
		expect.truthy((shape - Vector3.new(0.8, 0.8, 1.45) / Vector3.new(1, 1, 1.05)).Magnitude < 1e-9)
		expect.equal(spin, 0)
		local late, lateSpin = Flight.flightShape(FX.wobbles.flightJiggle.time + 0.1, false)
		expect.truthy((late - Vector3.one).Magnitude < 1e-9) -- the pop and the jiggle are over: the game's cruise stretch
		expect.near(lateSpin, math.rad(FX.spin.tap) * (FX.wobbles.flightJiggle.time + 0.1), 1e-9)
		local big, bigSpin = Flight.flightShape(0.5, true)
		expect.truthy(big.Magnitude > 0)
		expect.near(bigSpin, math.rad(FX.spin.charged) * 0.5, 1e-9)
		local first = Flight.flightShape(0, true)
		expect.truthy((first - Vector3.new(0.72, 0.72, 1.6) / Vector3.new(0.97, 0.97, 1.08)).Magnitude < 1e-9)
		expect.truthy(Flight.isCharged(FX.chargedFrom))
		expect.falsy(Flight.isCharged(FX.chargedFrom - 0.01))
		expect.falsy(Flight.isCharged(nil))
	end)

	t.test("every name a moment plays exists; the design's hard rules hold", function()
		local build = builder()
		expect.truthy(build ~= nil)
		local specs = if build then build.SPECS else {}
		local kinds = {
			pose = FX.poses,
			ring = FX.rings,
			pop = FX.texts,
			glow = FX.glows,
			screen = FX.screens,
			punch = FX.punches,
			fov = FX.fovs,
			sound = FX.sounds,
			burst = specs,
			emit = specs,
			call = { readyMirror = true },
		}
		local views = { ["1P"] = true, ["3P"] = true, R1P = true, OBS = true }
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
				if ev.stop == nil then
					expect.equal(found, 1)
				else
					expect.truthy(specs[ev.stop] ~= nil)
				end
				for _, view in ev.views or {} do
					expect.truthy(views[view])
				end
				if ev.emit then
					expect.truthy(specs[ev.emit].Rate ~= nil)
				elseif ev.burst then
					expect.truthy(specs[ev.burst].Count ~= nil)
				end
			end
		end
		for _, list in { FX.rings, FX.texts, FX.glows } do
			for _, def in list do
				expect.truthy(def.time <= 1.5)
			end
		end
		for _, def in FX.screens do
			expect.equal(def.kind, "banner")
			expect.truthy(def.fadeIn + def.hold + def.fadeOut <= 1.5)
		end
		for _, def in FX.punches do
			expect.truthy(def.rotation.Magnitude <= 2 and def.attack + def.hold + def.release <= 1.5)
		end
		for _, def in FX.fovs do
			expect.truthy(math.abs(def.delta) <= 8 and def.attack + def.hold + def.release <= 1.5)
		end
		for name, spec in specs do
			local live = if spec.Count then spec.Count else spec.Rate * spec.Lifetime[2]
			if live > 60 then
				error(`{name}: {live} particles`)
			end
		end
		-- The design's KEEP: a full charge takes 1 s, when the charge moment's sparkles end.
		expect.equal(Config.Combat.Charge.seconds, 1)
	end)

	t.test("pose keys: rig joints only, sorted, each step under 180 deg", function()
		local joints = Config.Anim.joints.R15
		for name, def in FX.poses do
			local lastT = -1
			for i, key in def.keys do
				expect.truthy(key.t > lastT)
				lastT = key.t
				for joint in key.joints do
					if joints[joint] == nil then
						error(`{name}: {joint} is not a rig joint`)
					end
				end
				local nextKey = def.keys[i + 1]
				if nextKey then
					for joint, angles in key.joints do
						local to = nextKey.joints[joint] or Vector3.zero
						for _, axis in { "X", "Y", "Z" } do
							if math.abs((to :: any)[axis] - (angles :: any)[axis]) >= 180 then
								error(`{name} key {i}: {joint}.{axis} jumps 180 deg or more`)
							end
						end
					end
				end
			end
		end
	end)

	t.test("FeelVfxBuilder: the charge sparkles are drawn inward", function()
		local build = builder()
		if build == nil then
			error("no FeelVfxBuilder")
		end
		local root = build.build(nil)
		for _, name in { "chargeSparksA", "chargeSparksB" } do
			local part = root:FindFirstChild(name)
			local e = part and part:FindFirstChildOfClass("ParticleEmitter")
			expect.truthy(e ~= nil and e.ShapeInOut == Enum.ParticleEmitterShapeInOut.Inward)
		end
		local aura = root:FindFirstChild("chargedAura")
		local e = aura and aura:FindFirstChildOfClass("ParticleEmitter")
		expect.truthy(e ~= nil and e.ShapeInOut == Enum.ParticleEmitterShapeInOut.Outward)
		root:Destroy()
	end)
end
