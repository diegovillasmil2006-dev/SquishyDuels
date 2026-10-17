--!strict
-- MoveFeel_Test: the movement overhaul (2026-10-17, VillasmilGaming: Rivals-style duel movement with camera shake;
-- a quicker lobby run with power slides). Server only (ServerStorage.UnitTest), Edit mode.
-- Contract:
--   * duels are faster than the balance's reference speed (Config.Combat.PowerBudget.dodgeSpeed <= WalkSpeed), the
--     movement guard keeps its headroom over the walk, the dash's mover can still reach its eased peak in a frame;
--   * Config.Vfx.MoveFeel: its camera offset goes on after the shake and comes off before the shake's undo; every
--     movement shake within Shake.maxAmplitudeDeg;
--   * MoveFeelController (pure): fovTarget 0 when slow, growing with speed, capped at fovMaxDeg; rollTarget leans into
--     the run (right -> negative), smaller in third person, capped; bobOffset dips once a step, never up; landDip only
--     down, capped, smaller in third person;
--   * Config.LobbyMove: a quicker lobby run, a slide that pushes past the run and eases out, its pose over the dash's
--     and under the throw's; the remote, its rate and the LobbySlide action (C in the Lobby context);
--   * LobbyMoveController (pure): gate, speedAt, poseWeight; LobbyMoveService (pure): inLobby, validate.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")
	local Feel = t.requireClient("Controllers/MoveFeelController")
	local Slide = t.requireClient("Controllers/LobbyMoveController")
	local Controls = t.requireClient("Controllers/ControlsController")
	local Service = t.requireServer("Services/LobbyMoveService")
	local FEEL = Config.Vfx.MoveFeel
	local SHAKE = Config.Vfx.Shake
	local RULES = Config.Duel.Rules
	local MOVE = Config.LobbyMove
	local SLIDE = MOVE.Slide

	t.test("duels: faster than the balance's reference, the guard and the dash keep up", function()
		local walk = RULES.Movement.WalkSpeed
		expect.truthy(walk > 16)
		expect.truthy(Config.Combat.PowerBudget.dodgeSpeed <= walk)
		expect.truthy(Config.Combat.MovementGuard.maxHorizontalSpeed >= walk * 1.5)
		local dash = RULES.Dash
		local peak = 3 * dash.distanceStuds / dash.seconds
		expect.truthy(dash.maxAccelStuds / 60 >= peak) -- the eased start speed in one 60 Hz frame
		expect.truthy(dash.cooldownSeconds > dash.visualFrames / dash.visualFps) -- never two pose clips at once
		expect.truthy(RULES.DoubleJump.heightStuds > 0)
	end)

	t.test("the movement camera: after the shake, off before the shake's undo; shakes in bounds", function()
		expect.truthy(FEEL.priorityOffset > SHAKE.priorityOffset)
		expect.truthy(FEEL.undoPriorityOffset < SHAKE.undoPriorityOffset)
		expect.truthy(FEEL.bindName ~= SHAKE.bindName and FEEL.undoBindName ~= SHAKE.undoBindName)
		for _, name in { "dashStart", "doubleJump", "landHard", "elimDealt" } do
			local preset = SHAKE[name]
			expect.truthy(preset.amplitudeDeg > 0 and preset.amplitudeDeg <= SHAKE.maxAmplitudeDeg)
			expect.truthy(preset.ms > 0)
		end
		expect.truthy(FEEL.fovMaxDeg > 0 and FEEL.fovMaxDeg <= 12)
		expect.truthy(FEEL.rollDeg > 0 and FEEL.rollDeg <= 4)
		expect.truthy(FEEL.dipMaxStuds > 0 and FEEL.dipMaxStuds < 1)
		for _, spring in { FEEL.fovSpring, FEEL.rollSpring, FEEL.dipSpring } do
			expect.truthy(spring.omega > 0 and spring.zeta > 0)
		end
	end)

	t.test("fovTarget: nothing when slow, more with speed, capped (a dash reaches the cap)", function()
		local walk = RULES.Movement.WalkSpeed
		expect.equal(Feel.fovTarget(0, walk), 0)
		expect.equal(Feel.fovTarget(walk * FEEL.fovFromShare * 0.9, walk), 0)
		expect.equal(Feel.fovTarget(0 / 0, walk), 0)
		local run = Feel.fovTarget(walk, walk)
		expect.near(run, (1 - FEEL.fovFromShare) * FEEL.fovPerWalk, 1e-9)
		expect.truthy(Feel.fovTarget(walk * 1.5, walk) > run)
		local dashPeak = 3 * RULES.Dash.distanceStuds / RULES.Dash.seconds
		expect.equal(Feel.fovTarget(dashPeak, walk), FEEL.fovMaxDeg)
		expect.truthy(Feel.fovTarget(walk, 0) <= FEEL.fovMaxDeg) -- a frozen WalkSpeed never divides by 0
	end)

	t.test("rollTarget: leans into the run, smaller in third person, capped", function()
		local walk = RULES.Movement.WalkSpeed
		expect.equal(Feel.rollTarget(0, walk, true), 0)
		expect.near(Feel.rollTarget(walk, walk, true), -FEEL.rollDeg, 1e-9)
		expect.near(Feel.rollTarget(-walk, walk, true), FEEL.rollDeg, 1e-9)
		expect.near(Feel.rollTarget(walk * 5, walk, true), -FEEL.rollDeg, 1e-9)
		expect.near(Feel.rollTarget(walk, walk, false), -FEEL.rollDeg * FEEL.rollTpShare, 1e-9)
		expect.equal(Feel.rollTarget(0 / 0, walk, true), 0)
	end)

	t.test("bobOffset: still at amount 0, dips once a step, never up; landDip only down and capped", function()
		local x0, y0 = Feel.bobOffset(1.3, 0)
		expect.equal(x0, 0)
		expect.equal(y0, 0)
		local deepest = 0
		for i = 0, 64 do
			local _, y = Feel.bobOffset(i / 64 * math.pi, 1)
			expect.truthy(y <= 1e-12)
			deepest = math.min(deepest, y)
		end
		expect.near(deepest, -FEEL.bobStuds, 1e-6)
		local _, top = Feel.bobOffset(math.pi, 1)
		expect.near(top, 0, 1e-9) -- back up after one step
		local side = Feel.bobOffset(math.pi / 2, 1)
		expect.near(side, FEEL.swayStuds, 1e-9)
		expect.equal(Feel.landDip(0, true), 0)
		expect.equal(Feel.landDip(-5, true), 0)
		expect.near(Feel.landDip(10, true), -10 * FEEL.dipPerSpeed, 1e-9)
		expect.near(Feel.landDip(1000, true), -FEEL.dipMaxStuds, 1e-9)
		expect.near(Feel.landDip(1000, false), -FEEL.dipMaxStuds * FEEL.dipTpShare, 1e-9)
	end)

	t.test("lobby: a quicker run; the slide pushes past it, eases out, sits between the dash and the throw", function()
		expect.truthy(MOVE.walkSpeed > 16 and MOVE.walkSpeed <= RULES.Movement.WalkSpeed)
		expect.truthy(SLIDE.startSpeed > MOVE.walkSpeed)
		expect.truthy(SLIDE.endSpeed > 0 and SLIDE.endSpeed < SLIDE.startSpeed)
		expect.truthy(SLIDE.seconds > SLIDE.blendInSeconds + SLIDE.blendOutSeconds)
		expect.truthy(SLIDE.cooldownSeconds >= SLIDE.seconds)
		expect.truthy(SLIDE.cooldownToleranceSeconds > 0 and SLIDE.cooldownToleranceSeconds < SLIDE.cooldownSeconds)
		expect.truthy(SLIDE.hipDrop > 0 and SLIDE.minHipHeight > 0)
		expect.truthy(SLIDE.priority > Config.Anim.dash.priority and SLIDE.priority < 2)
		for joint, angles in SLIDE.pose do
			expect.equal(type(joint), "string")
			expect.equal(typeof(angles), "Vector3")
		end
		local spec = Remotes.SPEC.SlideRequest
		expect.truthy(spec ~= nil and spec.dir == "c2s" and spec.kind == "RemoteEvent")
		expect.truthy(Config.Net.Remotes.SlideRequest ~= nil)
		expect.truthy(Config.Net.Remotes.SlideRequest.rate >= 1 / SLIDE.cooldownSeconds)
		expect.equal(Controls.contextOf("LobbySlide"), "Lobby")
		local inputs = Controls.inputsOf("LobbySlide")
		expect.truthy(inputs ~= nil and table.find(inputs :: any, Enum.KeyCode.C) ~= nil)
	end)

	t.test("LobbyMoveController: the gate, the speed curve and the pose's weight", function()
		local function facts(over: { [string]: any }?): any
			local base = {
				lobby = true,
				practice = false,
				inMatch = false,
				alive = true,
				grounded = true,
				speed = MOVE.walkSpeed,
				walkSpeed = MOVE.walkSpeed,
				sliding = false,
				now = 100,
				lastSlideAt = 0,
			}
			for k, v in over or {} do
				base[k] = v
			end
			return base
		end
		expect.equal(Slide.gate(facts()), nil)
		expect.equal(Slide.gate(facts({ lobby = false })), "context")
		expect.equal(Slide.gate(facts({ practice = true })), "context")
		expect.equal(Slide.gate(facts({ inMatch = true })), "context")
		expect.equal(Slide.gate(facts({ alive = false })), "dead")
		expect.equal(Slide.gate(facts({ sliding = true })), "busy")
		expect.equal(Slide.gate(facts({ grounded = false })), "airborne")
		expect.equal(Slide.gate(facts({ speed = 1 })), "slow")
		expect.equal(Slide.gate(facts({ lastSlideAt = 100 - SLIDE.cooldownSeconds / 2 })), "cooldown")
		expect.near(Slide.speedAt(0), SLIDE.startSpeed, 1e-9)
		expect.near(Slide.speedAt(SLIDE.seconds), SLIDE.endSpeed, 1e-9)
		expect.near(Slide.speedAt(SLIDE.seconds * 4), SLIDE.endSpeed, 1e-9)
		local last = math.huge
		for i = 0, 20 do
			local v = Slide.speedAt(SLIDE.seconds * i / 20)
			expect.truthy(v <= last + 1e-9)
			last = v
		end
		expect.equal(Slide.poseWeight(0, SLIDE.seconds), 0)
		expect.near(Slide.poseWeight(SLIDE.seconds / 2, SLIDE.seconds), 1, 1e-9)
		expect.equal(Slide.poseWeight(SLIDE.seconds, SLIDE.seconds), 0)
		expect.equal(Slide.poseWeight(-1, SLIDE.seconds), 0)
		expect.equal(Slide.poseWeight(0 / 0, SLIDE.seconds), 0)
	end)

	t.test("LobbyMoveService: lobby only, alive, the cooldown with its tolerance", function()
		expect.truthy(Service.inLobby(nil, nil))
		expect.truthy(Service.inLobby("", ""))
		expect.falsy(Service.inLobby("m1", ""))
		expect.falsy(Service.inLobby("", "Active"))
		local function facts(over: { [string]: any }?): any
			local base = { inLobby = true, alive = true, now = 50, lastSlideAt = 0 }
			for k, v in over or {} do
				base[k] = v
			end
			return base
		end
		expect.equal(Service.validate(facts()), nil)
		expect.equal(Service.validate(facts({ inLobby = false })), "slide.context")
		expect.equal(Service.validate(facts({ alive = false })), "slide.dead")
		local edge = SLIDE.cooldownSeconds - SLIDE.cooldownToleranceSeconds
		expect.equal(Service.validate(facts({ lastSlideAt = 50 - edge })), nil) -- an honest client at the edge
		expect.equal(Service.validate(facts({ lastSlideAt = 50 - edge + 0.05 })), "slide.cooldown")
		expect.equal(Service.validate(facts({ lastSlideAt = -math.huge })), nil)
	end)
end
