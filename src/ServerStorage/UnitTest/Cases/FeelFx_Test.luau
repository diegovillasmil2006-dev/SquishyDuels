--!strict
-- FeelFx_Test: the physics upgrade's part 1 (2026-10-28; the co-owner's Claude Design page docs/squishy-fx-spec/move.html,
-- data in Config.MoveFx). Server only (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * FeelFx (pure): the design's easing and envelope; a shake within its amplitude and over at its time; a pose track
--     at its keys, turning the short way (the flip's -295 -> -360), its Root translation; the flip variants turn only
--     the Root about the right axis; the aims;
--   * MoveFxController (pure): the landing tiers at the design's speeds, the hop chain's scale, the jump hold, another
--     body's takeoff / apex / landing (otherStep);
--   * Config.MoveFx: every name a moment plays exists (poses, rings, camera moves, texts, lines, afterimages, sounds,
--     and the VFX Studio templates of SDTools.Builders.FeelVfxBuilder); the design's hard rules (CONFIG.rules): shakes
--     at most 2 deg, FOV kicks at most 8 deg, every effect over within 1.5 s, at most 60 particles an effect (a burst's
--     count, a held emitter's rate x lifetime, the landing tiers with the mega landing); pose keys < 180 deg apart and
--     only rig joints;
--   * the design's KEEP values are still the game's (walk, jump, dash, slide);
--   * FeelVfxBuilder builds one template per design name, kit pictures only.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local FX = t.requireShared("Config/MoveFx")
	local FeelFx = t.requireClient("Anim/FeelFx")
	local MoveFx = t.requireClient("Controllers/MoveFxController")

	local function builder(): any
		local SDTools = game:GetService("ServerStorage"):FindFirstChild("SDTools")
		local builders = SDTools and SDTools:FindFirstChild("Builders")
		local module = builders and builders:FindFirstChild("FeelVfxBuilder")
		if module == nil then
			return nil
		end
		return (require :: any)(module:Clone())
	end

	t.test("ease and envelope: the design's curves", function()
		expect.near(FeelFx.ease(nil, 0.3), 0.3, 1e-9)
		expect.near(FeelFx.ease("Linear", 2), 1, 1e-9)
		expect.near(FeelFx.ease("Quad Out", 0.5), 0.75, 1e-6)
		expect.near(FeelFx.ease("Quad In", 0.5), 0.25, 1e-6)
		expect.near(FeelFx.ease("Quad", 0.5), 0.75, 1e-6) -- no direction = Out
		expect.truthy(FeelFx.ease("Back Out", 0.6) > 1) -- overshoots, then settles
		expect.near(FeelFx.ease("Back Out", 1), 1, 1e-6)
		local d = FX.dips.landDipHard
		expect.equal(FeelFx.envelope(-0.1, d.down, d.hold, d.up, d.downEasing, d.upEasing), 0)
		expect.near(FeelFx.envelope(d.down, d.down, d.hold, d.up, d.downEasing, d.upEasing), 1, 1e-9)
		expect.near(FeelFx.envelope(d.down + d.hold + d.up, d.down, d.hold, d.up, d.downEasing, d.upEasing), 0, 1e-6)
	end)

	t.test("shakes stay within their amplitude and end at their time", function()
		local phases = { 0.1, 1.2, 2.3, 3.4, 4.5, 5.6 }
		for _, def in FX.shakes do
			local biggest = 0
			for i = 0, 40 do
				local a = FeelFx.shakeAt(def, def.time * i / 40, phases)
				biggest = math.max(biggest, math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
			end
			expect.truthy(biggest <= def.amplitude + 1e-9)
			expect.equal(FeelFx.shakeAt(def, def.time, phases), Vector3.zero)
		end
	end)

	t.test("pose tracks: keys, the short way round, the Root translation", function()
		local flip = FX.poses.doubleFlip
		local start = FeelFx.evalPose(flip, 0)
		expect.near(start.Root.X, 0, 1e-9)
		local last = FeelFx.evalPose(flip, 0.26)
		expect.near(last.Root.X % 360, 0, 1e-6)
		local mid, _, past = FeelFx.evalPose(flip, (0.19 + 0.26) / 2)
		expect.truthy(mid.Root.X < -295 + 1e-6 and mid.Root.X > -360 - 1e-6) -- between the keys, not the long way
		expect.falsy(past)
		local _, _, over = FeelFx.evalPose(flip, 0.3)
		expect.truthy(over)
		-- A joint the track keys somewhere and a key leaves out is 0 there (the flip's last key drops the Neck).
		expect.near(last.Neck.X, 0, 1e-9)
		local _, rootPos = FeelFx.evalPose(FX.poses.landHard, 0)
		expect.near(rootPos.Y, -1, 1e-9)
		local _, rootEnd = FeelFx.evalPose(FX.poses.landHard, 0.34)
		expect.near(rootEnd.Magnitude, 0, 1e-9)
	end)

	t.test("flip variants turn only the Root, about the right axis", function()
		local flip = FX.poses.doubleFlip
		expect.equal(FeelFx.flipVariant(flip, "front"), flip)
		local axes = { back = "X", left = "Z", right = "Z", spin = "Y" }
		for kind, axis in axes do
			local v = FeelFx.flipVariant(flip, kind)
			local key = v.keys[3] -- the design's -200
			local root = key.joints.Root
			expect.near(math.abs((root :: any)[axis]), 200, 1e-9)
			expect.equal(key.joints.LeftKnee, flip.keys[3].joints.LeftKnee)
		end
		expect.near(FeelFx.flipVariant(flip, "back").keys[3].joints.Root.X, 200, 1e-9)
	end)

	t.test("aims: up, down, back against the move, backUp tilted up", function()
		local dir = Vector3.new(0, 0, -1)
		expect.equal(FeelFx.aimVector("up", dir), Vector3.yAxis)
		expect.equal(FeelFx.aimVector("down", dir), -Vector3.yAxis)
		expect.truthy((FeelFx.aimVector("back", dir) - Vector3.new(0, 0, 1)).Magnitude < 1e-9)
		local backUp = FeelFx.aimVector("backUp", dir)
		expect.near(math.deg(math.asin(backUp.Y)), FX.stage.backUpAngle, 1e-6)
		expect.truthy(backUp.Z > 0)
	end)

	t.test("MoveFxController: landing tiers, the chain, the jump hold", function()
		local feel = FX.feel
		expect.equal(MoveFx.landTier(0), "landSoft")
		expect.equal(MoveFx.landTier(feel.landSoftBelow - 0.01), "landSoft")
		expect.equal(MoveFx.landTier(feel.landSoftBelow), "landNormal")
		expect.equal(MoveFx.landTier(feel.landHardFrom - 0.01), "landNormal")
		expect.equal(MoveFx.landTier(feel.landHardFrom), "landHard")
		expect.equal(MoveFx.landTier(feel.maxFallSpeed), "landHard")
		expect.equal(MoveFx.chainScale(0), 1)
		expect.near(MoveFx.chainScale(2), 1 + 2 * FX.extras.chainCount, 1e-9)
		expect.near(MoveFx.chainScale(99), 1 + FX.extras.chainMax * FX.extras.chainCount, 1e-9)
		local gap = Config.Duel.Rules.DoubleJump.pressGapSeconds
		expect.truthy(MoveFx.heldNow(10, 10 - gap / 2, false, false, false))
		expect.falsy(MoveFx.heldNow(10, 10 - gap * 2, false, false, false))
		expect.truthy(MoveFx.heldNow(10, -math.huge, true, false, false))
		expect.truthy(MoveFx.heldNow(10, -math.huge, false, false, true))
	end)

	t.test("MoveFxController.otherStep: another body's jump, apex and landing", function()
		local g = 196.2 * FX.feel.fallGravityMultiplier
		local o = { grounded = true, jumped = false, rising = false, fromY = 3, maxY = 3, takeoffRun = nil }
		expect.equal(MoveFx.otherStep(o, true, 3, g), nil) -- standing
		expect.equal(MoveFx.otherStep(o, false, 3.6, g), nil) -- left the floor
		expect.equal(MoveFx.otherStep(o, false, 3.6 + FX.others.riseStuds / 2, g), nil)
		expect.equal(MoveFx.otherStep(o, false, 3.61 + FX.others.riseStuds, g), "takeoff")
		expect.equal(MoveFx.otherStep(o, false, 10.2, g), nil)
		expect.equal(MoveFx.otherStep(o, false, 10.1, g), "apex")
		expect.equal(MoveFx.otherStep(o, false, 5, g), nil)
		-- The design's full jump (7.2 studs) lands at ~67 studs/s, the normal tier.
		local event, speed = MoveFx.otherStep(o, true, 3, g)
		expect.equal(event, "land")
		expect.near(speed, math.sqrt(2 * g * 7.2), 1e-6)
		expect.equal(MoveFx.landTier(speed), "landNormal")
		-- A step down without a jump is no landing; a fall without a jump is (capped at the fall speed cap).
		expect.equal(MoveFx.otherStep(o, false, 3, g), nil)
		expect.equal(MoveFx.otherStep(o, true, 2.99, g), nil)
		MoveFx.otherStep(o, false, 2.99, g)
		MoveFx.otherStep(o, false, -50, g)
		event, speed = MoveFx.otherStep(o, true, -60, g)
		expect.equal(event, "land")
		expect.equal(speed, FX.feel.maxFallSpeed)
	end)

	t.test("the design's KEEP values are still the game's", function()
		local rules = Config.Duel.Rules
		expect.equal(Config.LobbyMove.walkSpeed, 20)
		expect.equal(rules.Movement.WalkSpeed, 22)
		expect.equal(rules.Movement.JumpHeight, 7.2)
		expect.equal(rules.Dash.distanceStuds, 18)
		expect.equal(rules.Dash.seconds, 0.22)
		expect.equal(rules.Dash.cooldownSeconds, 2)
		expect.equal(rules.Dash.endSpeedStuds, rules.Movement.WalkSpeed)
		expect.equal(Config.LobbyMove.Slide.startSpeed, 40)
		expect.equal(Config.LobbyMove.Slide.endSpeed, 18)
		expect.equal(Config.LobbyMove.Slide.seconds, 0.7)
		-- The short hop: ~3.7 studs (the design's preview), from the 7.2-stud jump's take-off speed.
		local g = 196.2
		local v0 = math.sqrt(2 * g * rules.Movement.JumpHeight)
		local cut = v0 - g * FX.feel.jumpCutMinHold
		local h = v0 * FX.feel.jumpCutMinHold - g * FX.feel.jumpCutMinHold ^ 2 / 2 + (cut * FX.feel.jumpCutKeep) ^ 2 / (2 * g)
		expect.near(h, 3.7, 0.2)
	end)

	t.test("every name a moment plays exists; the design's hard rules hold", function()
		local build = builder()
		expect.truthy(build ~= nil)
		local specs = if build then build.SPECS else {}
		local trails = if build then build.TRAILS else {}
		local kinds = {
			pose = FX.poses,
			ring = FX.rings,
			dip = FX.dips,
			shake = FX.shakes,
			fov = FX.fovs,
			pop = FX.texts,
			lines = FX.lines,
			afterimage = FX.afterimages,
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
				if ev.stop == nil then
					expect.equal(found, 1)
				end
				if ev.emit then
					expect.truthy(specs[ev.emit] and specs[ev.emit].Rate ~= nil) -- held: a rate
				elseif ev.burst then
					expect.truthy(specs[ev.burst] and specs[ev.burst].Count ~= nil) -- once: a count
				end
			end
		end
		local rules = { maxParticles = 60, maxEffectTime = 1.5, maxShake = 2, maxFovKick = 8 }
		for _, def in FX.shakes do
			expect.truthy(def.amplitude <= rules.maxShake and def.time <= rules.maxEffectTime)
		end
		for _, def in FX.fovs do
			expect.truthy(def.delta <= rules.maxFovKick)
			expect.truthy(def.attack + def.hold + def.release <= rules.maxEffectTime)
		end
		for _, def in FX.dips do
			expect.truthy(def.down + def.hold + def.up <= rules.maxEffectTime)
		end
		for _, def in FX.rings do
			expect.truthy(def.time <= rules.maxEffectTime)
		end
		for _, def in FX.texts do
			expect.truthy(def.time <= rules.maxEffectTime)
		end
		for _, def in FX.lines do
			expect.truthy(def.time + def.stagger <= rules.maxEffectTime)
		end
		for name, spec in specs do
			if spec.Count then
				expect.truthy(spec.Count <= rules.maxParticles)
			else
				local live = spec.Rate * spec.Lifetime[2]
				if live > rules.maxParticles then
					error(`{name}: {live} particles live`)
				end
			end
			expect.truthy(spec.Lifetime[2] <= rules.maxEffectTime)
		end
		-- The heaviest moment: a mega landing (the hard tier and the mega pop at once, no chain).
		local total = 0
		for _, ev in FX.moments.landing do
			if ev.on == "landHard" and ev.burst then
				total += specs[ev.burst].Count
			end
		end
		for _, ev in FX.moments.mega do
			if ev.burst then
				total += specs[ev.burst].Count
			end
		end
		expect.truthy(total <= rules.maxParticles)
		-- A chain landing at most: the normal tier's puffs at the chain's biggest scale.
		expect.truthy(specs.landPuffHard.Count * MoveFx.chainScale(FX.extras.chainMax) + specs.landStarsHard.Count * MoveFx.chainScale(FX.extras.chainMax) <= rules.maxParticles)
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
			if not def.hold then
				expect.truthy(def.keys[#def.keys].t + (def.fadeOut or 0) <= 1.5)
			end
		end
	end)

	t.test("FeelVfxBuilder: one template per design name, kit pictures, the right roles", function()
		local build = builder()
		if build == nil then
			error("no FeelVfxBuilder")
		end
		local root = build.build(nil)
		for name, spec in build.SPECS do
			local part = root:FindFirstChild(name)
			expect.truthy(part ~= nil and part:IsA("BasePart"))
			local emitters = 0
			for _, d in part:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					emitters += 1
					expect.truthy(string.find(d.Texture, "rbxassetid://", 1, true) == 1)
					if spec.Rate then
						expect.equal(d:GetAttribute("SD_Role"), "while")
					else
						expect.truthy(type(d:GetAttribute("EmitCount")) == "number")
					end
				end
			end
			expect.equal(emitters, if spec.Tints then #spec.Tints else 1)
		end
		for name in build.TRAILS do
			local part = root:FindFirstChild(name)
			expect.truthy(part ~= nil and part:FindFirstChildOfClass("Trail") ~= nil)
		end
		root:Destroy()
	end)
end
