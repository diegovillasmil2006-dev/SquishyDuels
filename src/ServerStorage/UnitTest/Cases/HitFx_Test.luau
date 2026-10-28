--!strict
-- HitFx_Test: the physics upgrade's part 2 (2026-10-28, getting hit; the co-owner's Claude Design page
-- docs/squishy-fx-spec/hit.html, data in Config.HitFx). Server only (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * HitFxController (pure): the moment of a hit (final K.O., squished, ultimate, charged, normal); a match K.O. wins
--     the match at the K.O. target (FFA K.O.s, TDM team score) from the view before it; the design's knockback speeds
--     (ultimate = normal x 1.5), held, then the air drag, then the skid to 0; the flat speed is under the movement
--     guard's maxHorizontalSpeed by the time its hit grace ends (the knockback starts after the hit-stop);
--   * FeelFx.slowAt: the design's slow motion (1 -> speed -> 1, then over);
--   * Config.HitFx: every name a moment plays exists (poses, rings, pops, glows, lights, flashes, screens, camera moves,
--     slow motion, sounds, calls, and FeelVfxBuilder's templates); views are the design's three; the design's hard
--     rules (CONFIG.rules): hit-stops <= 0.12 s, shakes <= 2 deg, FOV kicks <= 8 deg, flashes <= 0.1 s at <= 30 %, every
--     effect over within 1.5 s; pose keys rig joints only, each step under 180 deg.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local HIT = t.requireShared("Config/HitFx")
	local FeelFx = t.requireClient("Anim/FeelFx")
	local HitFx = t.requireClient("Controllers/HitFxController")

	local function builder(): any
		local SDTools = game:GetService("ServerStorage"):FindFirstChild("SDTools")
		local builders = SDTools and SDTools:FindFirstChild("Builders")
		local module = builders and builders:FindFirstChild("FeelVfxBuilder")
		return if module then (require :: any)(module:Clone()) else nil
	end

	t.test("momentFor: final K.O., squished, ultimate, charged, normal", function()
		expect.equal(HitFx.momentFor(true, false, false, false, 0), "finalKO") -- a duel's last life
		expect.equal(HitFx.momentFor(true, true, true, false, 0), "finalKO") -- the match's winning K.O.
		expect.equal(HitFx.momentFor(true, true, false, true, 1), "squished") -- any other match K.O.
		expect.equal(HitFx.momentFor(false, false, false, true, 1), "hitUltimate")
		expect.equal(HitFx.momentFor(false, true, false, false, HIT.chargedFrom), "hitCharged")
		expect.equal(HitFx.momentFor(false, false, false, false, HIT.chargedFrom - 0.01), "hitNormal")
		expect.equal(HitFx.momentFor(nil, false, false, false, nil), "hitNormal")
	end)

	t.test("matchWins: FFA K.O.s and TDM team score reach the target", function()
		local ffa = {
			mode = "ffa",
			koTarget = 10,
			players = { { userId = 1, kos = 9 }, { userId = 2, kos = 3 } },
		}
		expect.truthy(HitFx.matchWins(ffa, 1))
		expect.falsy(HitFx.matchWins(ffa, 2))
		expect.falsy(HitFx.matchWins(ffa, 99))
		expect.falsy(HitFx.matchWins(ffa, nil))
		expect.falsy(HitFx.matchWins(nil, 1))
		local tdm = {
			mode = "tdm",
			koTarget = 20,
			teamScore = { Mint = 19, Berry = 4 },
			players = { { userId = 1, kos = 0, team = "Mint" }, { userId = 2, kos = 15, team = "Berry" } },
		}
		expect.truthy(HitFx.matchWins(tdm, 1))
		expect.falsy(HitFx.matchWins(tdm, 2))
	end)

	t.test("the knockback: the design's speeds, held, air drag, skid to 0", function()
		local h, v, hold = HitFx.knockFor("normal")
		expect.equal(h, 34)
		expect.equal(v, 34)
		expect.equal(hold, 0.12)
		h, v, hold = HitFx.knockFor("charged")
		expect.equal(h, 44)
		expect.equal(v, 40)
		expect.equal(hold, 0.14)
		h, v, hold = HitFx.knockFor("ultimate")
		expect.near(h, 51, 1e-9)
		expect.near(v, 51, 1e-9)
		expect.equal(hold, 0.12)
		local K = HIT.knockback
		expect.equal(HitFx.knockSpeed(34, 0.12, 0.1, nil), 34)
		expect.near(HitFx.knockSpeed(34, 0.12, 0.62, nil), 34 * math.exp(-K.airDrag * 0.5), 1e-9)
		local atLand = 34 * math.exp(-K.airDrag * 0.2)
		expect.near(HitFx.knockSpeed(34, 0.12, 0.32 + 0.05, 0.32), atLand - K.groundDecel * 0.05, 1e-9)
		expect.equal(HitFx.knockSpeed(34, 0.12, 5, 0.32), 0)
	end)

	t.test("the knockback is under the movement guard's speed when its hit grace ends", function()
		local guard = Config.Combat.MovementGuard
		for kind, moment in { normal = "hitNormal", charged = "hitCharged", ultimate = "hitUltimate" } do
			local h, _, hold = HitFx.knockFor(kind)
			local t0 = HIT.hitStop[moment] -- the knockback starts after the hit-stop
			local speed = HitFx.knockSpeed(h, hold, guard.hitGraceSeconds - t0, nil)
			if speed >= guard.maxHorizontalSpeed then
				error(`{kind}: {speed} studs/s when the grace ends`)
			end
		end
	end)

	t.test("slowAt: 1 -> speed -> 1, then over", function()
		local def = HIT.slowmos.finalSlow
		expect.near(FeelFx.slowAt(def, 0), 1, 1e-9)
		expect.near(FeelFx.slowAt(def, def.fadeIn), def.speed, 1e-9)
		expect.near(FeelFx.slowAt(def, def.fadeIn + def.hold / 2), def.speed, 1e-9)
		local late = FeelFx.slowAt(def, def.fadeIn + def.hold + def.fadeOut * 0.99)
		expect.truthy(late ~= nil and late > def.speed and late <= 1)
		expect.equal(FeelFx.slowAt(def, def.fadeIn + def.hold + def.fadeOut), nil)
	end)

	t.test("every name a moment plays exists; the design's hard rules hold", function()
		local build = builder()
		expect.truthy(build ~= nil)
		local specs = if build then build.SPECS else {}
		local trails = if build then build.TRAILS else {}
		local kinds = {
			pose = HIT.poses,
			ring = HIT.rings,
			pop = HIT.texts,
			glow = HIT.glows,
			light = HIT.lights,
			flash = HIT.flashes,
			screen = HIT.screens,
			shake = HIT.shakes,
			fov = HIT.fovs,
			punch = HIT.punches,
			slowmo = HIT.slowmos,
			sound = HIT.sounds,
			burst = specs,
			emit = specs,
			trail = trails,
			call = { knockback = true, hide = true, show = true },
		}
		local views = { V1P = true, A1P = true, OBS = true }
		for moment, events in HIT.moments do
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
				expect.equal(found, 1)
				for _, view in ev.views or {} do
					expect.truthy(views[view])
				end
				if ev.emit then
					expect.truthy(specs[ev.emit].Rate ~= nil)
				elseif ev.burst then
					expect.truthy(specs[ev.burst].Count ~= nil)
				end
				if ev.call == "knockback" then
					expect.truthy(ev.kind == "normal" or ev.kind == "charged" or ev.kind == "ultimate")
				end
			end
		end
		local rules = { maxEffectTime = 1.5, maxShake = 2, maxFovKick = 8, maxHitStop = 0.12 }
		for _, s in HIT.hitStop do
			expect.truthy(s <= rules.maxHitStop)
		end
		for _, def in HIT.shakes do
			expect.truthy(def.amplitude <= rules.maxShake and def.time <= rules.maxEffectTime)
		end
		for _, def in HIT.fovs do
			expect.truthy(math.abs(def.delta) <= rules.maxFovKick)
			expect.truthy(def.attack + def.hold + def.release <= rules.maxEffectTime)
		end
		for _, def in HIT.flashes do
			expect.truthy(def.fadeIn + def.fadeOut <= 0.1 and def.opacity <= 0.3)
		end
		for _, list in { HIT.rings, HIT.texts, HIT.glows, HIT.lights } do
			for _, def in list do
				expect.truthy(def.time <= rules.maxEffectTime)
			end
		end
		local splat = HIT.screens.edgeSplat
		expect.truthy(splat.popTime + splat.hold + splat.fadeTime + splat.stagger * splat.count <= rules.maxEffectTime)
		local bars = HIT.screens.koBars
		expect.truthy(bars.fadeIn + bars.hold + bars.fadeOut <= rules.maxEffectTime)
	end)

	t.test("pose keys: rig joints only, sorted, each step under 180 deg", function()
		local joints = Config.Anim.joints.R15
		for name, def in HIT.poses do
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
end
