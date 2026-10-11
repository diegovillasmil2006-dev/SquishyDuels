--!strict
-- FirstPersonController_Test: StarterPlayerScripts.Client.Controllers.FirstPersonController (first-person spec
-- 2026-10-10 §3.1, §3.8, §6). Server only (ServerStorage.UnitTest). Edit mode: init() is not called; the camera
-- machine (FirstPersonController.Machine) runs on stand-ins for the local player, the camera, UserInputService, the
-- menu, ReducedMotion, the shoulder offset and the two facings, stepped by hand on a FakeClock.
-- Contract:
--   * the phase -> camera table: Preparing / Positioning today's camera; Countdown, Active, SuddenDeath first person;
--     Result first person for resultHoldSeconds (0.4 s) only when already in it; Returning, Cancelled, Void, the view
--     gone, death or the character removed, the switch off: today's camera at once;
--   * entry saves CameraMode, the min / max zoom, the zoom distance and MouseIconEnabled, then LockFirstPerson; exit puts
--     CameraMode and MouseIconEnabled back and holds the min zoom at the saved distance for one frame (two steps)
--     before the saved min comes back: each written once, and a second end writes nothing; under ReducedMotion entry
--     holds the max zoom at 0.5 for one frame the same way; no CameraController.save() snapshot is held (the camera
--     stays Custom, so a punch still starts);
--   * the mouse icon hides only while first person is on, MouseBehavior is LockCenter, the Roblox menu is closed and
--     the forfeit dialog is closed;
--   * the switch starts on (Config.FirstPerson.defaultOn), is session only and never a saved setting;
--   * faceOpponent: a level look ahead (countdownPitchDeg) in first person, today's faceBehindCharacter otherwise;
--   * the shoulder offset is suppressed while first person is on (duel and practice);
--   * practice: the zone turning on enters ("practice", no facing); off for practiceExitDelaySeconds (0.3 s) exits,
--     off then on within it does not; a match, death, a block or the switch off exits at once; the block ending in
--     the zone enters again (also after the switch was turned on while blocked); a duel phase always wins; never in
--     first person outside the box once the delay has passed;
--   * the look (spec 2026-10-11 §3.8): the mode while one is on, else "lobby" only while the head is hidden, alive, not
--     in a match, no phase, not in the box and not blocked (whatever the switch), else nil; the lobby look writes no
--     camera, zoom, cursor or shoulder offset and leaves mode() and Changed alone; practice hands over to the lobby with
--     no gap when the player was already in the head; no lobby look while the exit pushes the camera back out to a
--     third-person distance; LookChanged fires once per change.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type Rig = {
	m: any,
	clock: any,
	player: any,
	camera: any,
	input: any,
	writes: { [string]: number },
	shoulder: { boolean },
	faced: { string },
	changes: { string },
	looks: { string },
	world: { menu: boolean, reduced: boolean },
	step: (frames: number?) -> (),
}

local SAVED_MIN, SAVED_MAX, DISTANCE = 0.5, 128, 12

return function(t: Context)
	local FirstPersonController = t.requireClient("Controllers/FirstPersonController")
	local CameraController = t.requireClient("Controllers/CameraController")
	local SettingsFormat = t.requireClient("UI/SettingsFormat")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local expect = t.expect
	local Machine = FirstPersonController.Machine
	local FP = Config.FirstPerson
	local LOCK = Enum.CameraMode.LockFirstPerson
	local CLASSIC = Enum.CameraMode.Classic

	-- A stand-in world; `alive` (default true) is fed, the switch is on (defaultOn).
	local function rig(reduced: boolean?): Rig
		local clock = FakeClock.new(100)
		local writes: { [string]: number } = {}
		-- A table whose every write is counted by key.
		local function recorder(fields: { [string]: any }): any
			return setmetatable({}, {
				__index = fields,
				__newindex = function(_, key: string, value: any)
					fields[key] = value
					writes[key] = (writes[key] or 0) + 1
				end,
			})
		end
		local player = recorder({
			CameraMode = CLASSIC,
			CameraMinZoomDistance = SAVED_MIN,
			CameraMaxZoomDistance = SAVED_MAX,
		})
		local camera = {
			CFrame = CFrame.new(0, 10, DISTANCE),
			Focus = CFrame.new(0, 10, 0),
			CameraType = Enum.CameraType.Custom,
			FieldOfView = 70,
		}
		local input = recorder({ MouseIconEnabled = true, MouseBehavior = Enum.MouseBehavior.Default })
		local r = {
			clock = clock,
			player = player,
			camera = camera,
			input = input,
			writes = writes,
			shoulder = {},
			faced = {},
			changes = {},
			looks = {},
			world = { menu = false, reduced = reduced == true },
		} :: any
		r.m = Machine.new({
			now = clock.now,
			player = function(): any
				return player
			end,
			camera = function(): any
				return camera
			end,
			input = input,
			menuOpen = function(): boolean
				return r.world.menu
			end,
			reducedMotion = function(): boolean
				return r.world.reduced
			end,
			setShoulderSuppressed = function(on: boolean)
				table.insert(r.shoulder, on)
			end,
			faceForward = function(pitchDeg: number): boolean
				table.insert(r.faced, "forward " .. pitchDeg)
				return true
			end,
			faceBehind = function(distance: number, height: number): boolean
				table.insert(r.faced, "behind " .. distance .. " " .. height)
				return true
			end,
			changed = function(mode: string?)
				table.insert(r.changes, mode or "none")
			end,
			lookChanged = function(look: string?)
				table.insert(r.looks, look or "none")
			end,
			wake = function() end,
		})
		function r.step(frames: number?)
			for _ = 1, frames or 1 do
				clock.advance(1 / 60)
				Machine.step(r.m)
			end
		end
		Machine.setFlag(r.m, "alive", true)
		return r
	end

	-- Back to today's camera: CameraMode, the cursor and (after the one-frame push) the zoom limits as saved.
	local function expectRestored(r: Rig)
		expect.equal(r.m.mode, nil)
		expect.equal(r.player.CameraMode, CLASSIC)
		expect.equal(r.input.MouseIconEnabled, true)
		r.step(2)
		expect.equal(r.player.CameraMinZoomDistance, SAVED_MIN)
		expect.equal(r.player.CameraMaxZoomDistance, SAVED_MAX)
	end

	-- Duels ----------------------------------------------------------------------------------------------------------

	t.test("the phase table: first person from Countdown to Result + 0.4 s, today's camera around it", function()
		local r = rig()
		for _, phase in { "Preparing", "Positioning" } do
			Machine.setPhase(r.m, phase)
			expect.equal(r.m.mode, nil)
			expect.equal(r.player.CameraMode, CLASSIC)
		end
		for _, phase in { "Countdown", "Active", "SuddenDeath" } do
			Machine.setPhase(r.m, phase)
			expect.equal(r.m.mode, "duel")
			expect.equal(r.player.CameraMode, LOCK)
		end
		Machine.setPhase(r.m, "Result")
		expect.equal(r.m.mode, "duel")
		r.clock.advance(FP.resultHoldSeconds - 0.02)
		Machine.step(r.m)
		expect.equal(r.m.mode, "duel")
		r.clock.advance(0.04)
		Machine.step(r.m)
		expectRestored(r)
		Machine.setPhase(r.m, "Returning")
		expect.equal(r.m.mode, nil)
		expect.deepEqual(r.changes, { "duel", "none" })
		-- A view that starts at Result (a late join) never enters first person for its last moments.
		local late = rig()
		Machine.setPhase(late.m, "Result")
		expect.equal(late.m.mode, nil)
		expect.equal(late.writes.CameraMode, nil)
	end)

	t.test("every abnormal end gives today's camera back at once", function()
		local ends: { [string]: (r: Rig) -> () } = {
			Returning = function(r)
				Machine.setPhase(r.m, "Returning")
			end,
			Cancelled = function(r)
				Machine.setPhase(r.m, "Cancelled")
			end,
			Void = function(r)
				Machine.setPhase(r.m, "Void")
			end,
			viewGone = function(r)
				Machine.setPhase(r.m, nil)
			end,
			died = function(r)
				Machine.setFlag(r.m, "alive", false)
			end,
			switchOff = function(r)
				Machine.setFlag(r.m, "enabled", false)
			end,
		}
		for name, finish in ends do
			local r = rig()
			Machine.setFlag(r.m, "inMatch", true)
			Machine.setPhase(r.m, "Active")
			expect.equal(r.m.mode, "duel")
			finish(r)
			if r.m.mode ~= nil then
				error("still in first person after " .. name)
			end
			expectRestored(r)
		end
	end)

	t.test("entry saves and exit restores each value once; a second end writes nothing", function()
		local r = rig()
		r.input.MouseBehavior = Enum.MouseBehavior.LockCenter
		Machine.setPhase(r.m, "Countdown")
		expect.equal(r.player.CameraMode, LOCK)
		expect.equal(r.writes.CameraMaxZoomDistance, nil) -- a glide in: the max zoom is left alone
		r.step(3)
		expect.equal(r.input.MouseIconEnabled, false)
		Machine.setPhase(r.m, "Cancelled")
		-- The camera is pushed out to the saved distance at once (a cut), the saved min comes back a frame later.
		expect.equal(r.player.CameraMode, CLASSIC)
		expect.near(r.player.CameraMinZoomDistance, DISTANCE, 1e-4)
		expect.equal(r.player.CameraMaxZoomDistance, SAVED_MAX)
		r.step(2)
		expect.equal(r.player.CameraMinZoomDistance, SAVED_MIN)
		expect.equal(r.input.MouseIconEnabled, true)
		expect.equal(r.writes.CameraMode, 2)
		expect.equal(r.writes.CameraMinZoomDistance, 2)
		expect.equal(r.writes.CameraMaxZoomDistance, nil)
		local before = table.clone(r.writes)
		Machine.setPhase(r.m, nil)
		Machine.setFlag(r.m, "alive", false)
		r.step(5)
		expect.deepEqual(r.writes, before)
		expect.deepEqual(r.shoulder, { true, false })
	end)

	t.test("ReducedMotion: entry cuts in with the max zoom at 0.5 for one frame", function()
		local r = rig(true)
		Machine.setPhase(r.m, "Countdown")
		expect.equal(r.player.CameraMode, LOCK)
		expect.equal(r.player.CameraMaxZoomDistance, 0.5)
		r.step(2)
		expect.equal(r.player.CameraMaxZoomDistance, SAVED_MAX)
		expect.equal(r.writes.CameraMaxZoomDistance, 2)
		-- Ending before that frame puts the max back with the exit itself.
		local quick = rig(true)
		Machine.setPhase(quick.m, "Countdown")
		Machine.setPhase(quick.m, "Void")
		expect.equal(quick.player.CameraMaxZoomDistance, SAVED_MAX)
		expectRestored(quick)
	end)

	t.test("no save() snapshot is held: the camera stays Custom and a punch still starts", function()
		local r = rig()
		Machine.setPhase(r.m, "Active")
		r.step(2)
		expect.equal(r.camera.CameraType, Enum.CameraType.Custom)
		local state = CameraController.newPunchState()
		expect.truthy(CameraController.punchStart(state, r.camera, Config.Vfx.Punch.hitDealt, 0))
	end)

	t.test("the mouse icon hides only while locked, with the menu and the forfeit dialog closed", function()
		expect.falsy(FirstPersonController.mouseIconShown(true, Enum.MouseBehavior.LockCenter, false, false))
		expect.truthy(FirstPersonController.mouseIconShown(false, Enum.MouseBehavior.LockCenter, false, false))
		expect.truthy(FirstPersonController.mouseIconShown(true, Enum.MouseBehavior.Default, false, false))
		expect.truthy(FirstPersonController.mouseIconShown(true, Enum.MouseBehavior.LockCenter, true, false))
		expect.truthy(FirstPersonController.mouseIconShown(true, Enum.MouseBehavior.LockCenter, false, true))
		local r = rig()
		Machine.setPhase(r.m, "Active")
		r.input.MouseBehavior = Enum.MouseBehavior.LockCenter
		r.step()
		expect.equal(r.input.MouseIconEnabled, false)
		r.input.MouseBehavior = Enum.MouseBehavior.Default -- a Modal button freed the mouse
		r.step()
		expect.equal(r.input.MouseIconEnabled, true)
		r.input.MouseBehavior = Enum.MouseBehavior.LockCenter
		r.step()
		r.world.menu = true
		r.step()
		expect.equal(r.input.MouseIconEnabled, true)
		r.world.menu = false
		r.step()
		expect.equal(r.input.MouseIconEnabled, false)
		Machine.setFlag(r.m, "dialogOpen", true) -- at once, not a frame later
		expect.equal(r.input.MouseIconEnabled, true)
		Machine.setFlag(r.m, "dialogOpen", false)
		expect.equal(r.input.MouseIconEnabled, false)
	end)

	t.test("faceOpponent: a level look ahead in first person, today's facing otherwise", function()
		local r = rig()
		Machine.setPhase(r.m, "Countdown")
		expect.truthy(Machine.faceOpponent(r.m, 12, 4))
		expect.deepEqual(r.faced, { "forward " .. FP.countdownPitchDeg })
		local off = rig()
		Machine.setFlag(off.m, "enabled", false)
		Machine.setPhase(off.m, "Countdown")
		expect.truthy(Machine.faceOpponent(off.m, 12, 4))
		expect.deepEqual(off.faced, { "behind 12 4" })
		expect.equal(off.writes.CameraMode, nil)
	end)

	t.test("the switch starts on, is session only and is never a saved setting", function()
		expect.equal(FP.defaultOn, true)
		expect.equal(FirstPersonController.isEnabled(), FP.defaultOn)
		expect.equal(rig().m.enabled, FP.defaultOn)
		FirstPersonController.setEnabled(false)
		expect.falsy(FirstPersonController.isEnabled())
		FirstPersonController.setEnabled(true)
		expect.truthy(FirstPersonController.isEnabled())
		expect.equal(table.find(SettingsFormat.KEYS, "firstPerson"), nil)
		expect.equal((Config.Data.DefaultSettings :: any).firstPerson, nil)
		-- In Edit mode nothing is fed: not alive, so never active.
		expect.falsy(FirstPersonController.isActive())
		expect.equal(FirstPersonController.mode(), nil)
	end)

	t.test("the shoulder offset is suppressed while first person is on, duel and practice", function()
		local r = rig()
		Machine.setPhase(r.m, "Countdown")
		expect.deepEqual(r.shoulder, { true })
		Machine.setPhase(r.m, "Returning")
		expect.deepEqual(r.shoulder, { true, false })
		Machine.setPhase(r.m, nil)
		Machine.setZone(r.m, true)
		expect.deepEqual(r.shoulder, { true, false, true })
		Machine.setFlag(r.m, "blocked", true)
		expect.deepEqual(r.shoulder, { true, false, true, false })
	end)

	-- Practice range -------------------------------------------------------------------------------------------------

	t.test("practice: entering the throw box enters first person, with no facing", function()
		local r = rig()
		Machine.setZone(r.m, true)
		expect.equal(r.m.mode, "practice")
		expect.equal(r.player.CameraMode, LOCK)
		expect.deepEqual(r.faced, {})
		expect.deepEqual(r.changes, { "practice" })
	end)

	t.test("practice: leaving the box exits after 0.3 s; back in within it, nothing changes", function()
		local r = rig()
		Machine.setZone(r.m, true)
		Machine.setZone(r.m, false)
		r.clock.advance(FP.practiceExitDelaySeconds - 0.05)
		Machine.step(r.m)
		expect.equal(r.m.mode, "practice")
		Machine.setZone(r.m, true) -- walking along the edge
		r.clock.advance(1)
		Machine.step(r.m)
		expect.equal(r.m.mode, "practice")
		expect.equal(r.writes.CameraMode, 1)
		Machine.setZone(r.m, false)
		r.clock.advance(FP.practiceExitDelaySeconds - 1e-3)
		Machine.step(r.m)
		expect.equal(r.m.mode, "practice")
		r.clock.advance(2e-3)
		Machine.step(r.m)
		expectRestored(r)
	end)

	t.test("practice: a match, death, a block or the switch off exits at once", function()
		local ends: { [string]: (r: Rig) -> () } = {
			match = function(r)
				Machine.setFlag(r.m, "inMatch", true)
			end,
			died = function(r)
				Machine.setFlag(r.m, "alive", false)
			end,
			blocked = function(r)
				Machine.setFlag(r.m, "blocked", true)
			end,
			switchOff = function(r)
				Machine.setFlag(r.m, "enabled", false)
			end,
		}
		for name, finish in ends do
			local r = rig()
			Machine.setZone(r.m, true)
			finish(r)
			if r.m.mode ~= nil then
				error("still in first person after " .. name)
			end
			expectRestored(r)
		end
	end)

	t.test("practice: the block ending in the box enters again, also after the switch came on meanwhile", function()
		local r = rig()
		Machine.setZone(r.m, true)
		Machine.setFlag(r.m, "blocked", true) -- a screen opened over the range
		expect.equal(r.m.mode, nil)
		Machine.setFlag(r.m, "blocked", false)
		expect.equal(r.m.mode, "practice")
		local s = rig()
		Machine.setFlag(s.m, "enabled", false)
		Machine.setZone(s.m, true)
		Machine.setFlag(s.m, "blocked", true) -- Settings open
		Machine.setFlag(s.m, "enabled", true) -- the switch turned on in it
		expect.equal(s.m.mode, nil)
		Machine.setFlag(s.m, "blocked", false) -- Settings closed
		expect.equal(s.m.mode, "practice")
	end)

	t.test("practice: a block that ends within the exit's frame keeps the saved zoom, never the pushed one", function()
		local r = rig()
		Machine.setZone(r.m, true)
		Machine.setFlag(r.m, "blocked", true)
		r.camera.CFrame = CFrame.new(0, 10, 0.5) -- the camera has not moved out yet
		Machine.setFlag(r.m, "blocked", false)
		expect.equal(r.m.mode, "practice")
		expect.equal(r.player.CameraMinZoomDistance, SAVED_MIN)
		Machine.setZone(r.m, false)
		r.clock.advance(1)
		Machine.step(r.m)
		expect.equal(r.m.mode, nil)
		expect.near(r.player.CameraMinZoomDistance, DISTANCE, 1e-4) -- out to where it was before the first entry
		expectRestored(r)
	end)

	t.test("a duel phase always wins over the practice row", function()
		local r = rig()
		Machine.setZone(r.m, true)
		Machine.setFlag(r.m, "inMatch", true)
		Machine.setPhase(r.m, "Preparing")
		expect.equal(r.m.mode, nil)
		Machine.setPhase(r.m, "Countdown")
		expect.equal(r.m.mode, "duel")
		Machine.setFlag(r.m, "blocked", true) -- duels never block, but a block would not end a duel's first person
		expect.equal(r.m.mode, "duel")
		Machine.setPhase(r.m, "Returning")
		expect.equal(r.m.mode, nil)
	end)

	t.test("never in first person outside the box once the delay has passed", function()
		local rng = Random.new(7)
		local r = rig()
		local inside, offAt = false, -math.huge
		for _ = 1, 400 do
			if rng:NextNumber() < 0.3 then
				inside = not inside
				if not inside then
					offAt = r.clock.now()
				end
				Machine.setZone(r.m, inside)
			end
			r.clock.advance(rng:NextNumber(0.01, 0.2))
			Machine.step(r.m)
			if r.m.mode ~= nil and not inside and r.clock.now() - offAt >= FP.practiceExitDelaySeconds then
				error("still in first person outside the box")
			end
			if r.m.mode == nil and r.player.CameraMode ~= CLASSIC then
				error("CameraMode left locked")
			end
		end
	end)

	t.test("inMatchFrom: SD_MatchId or SD_DuelPhase set", function()
		expect.falsy(FirstPersonController.inMatchFrom(nil, nil))
		expect.falsy(FirstPersonController.inMatchFrom("", ""))
		expect.truthy(FirstPersonController.inMatchFrom("m1", ""))
		expect.truthy(FirstPersonController.inMatchFrom(nil, "Countdown"))
		expect.falsy(FirstPersonController.inMatchFrom(3, true))
	end)

	-- The look (spec 2026-10-11 §3.8) -----------------------------------------------------------------------------------

	t.test("look() and LookChanged stand apart from mode() and Changed; nothing fed in Edit mode", function()
		expect.equal(FirstPersonController.look(), nil)
		expect.truthy(FirstPersonController.LookChanged ~= nil)
		expect.truthy(FirstPersonController.LookChanged ~= FirstPersonController.Changed)
		local connection = FirstPersonController.LookChanged:connect(function() end)
		expect.truthy(connection.connected)
		connection:disconnect()
	end)

	t.test(
		"lobby: only while the head is hidden, alive, not in a match, no phase, not in the box, not blocked",
		function()
			local r = rig()
			expect.equal(Machine.look(r.m), nil)
			Machine.setFlag(r.m, "headHidden", true) -- Roblox's own zoom into the head
			expect.equal(Machine.look(r.m), "lobby")
			expect.equal(r.m.mode, nil) -- mode(), isActive() and Changed keep their meaning
			expect.deepEqual(r.changes, {})
			expect.deepEqual(r.looks, { "lobby" })
			-- Each fact: { turn it off, turn it back on }.
			local offs: { [string]: { (r: Rig) -> () } } = {
				died = {
					function(x)
						Machine.setFlag(x.m, "alive", false)
					end,
					function(x)
						Machine.setFlag(x.m, "alive", true)
					end,
				},
				inMatch = {
					function(x)
						Machine.setFlag(x.m, "inMatch", true)
					end,
					function(x)
						Machine.setFlag(x.m, "inMatch", false)
					end,
				},
				phase = {
					function(x)
						Machine.setPhase(x.m, "Preparing")
					end,
					function(x)
						Machine.setPhase(x.m, nil)
					end,
				},
				blocked = {
					function(x)
						Machine.setFlag(x.m, "blocked", true)
					end,
					function(x)
						Machine.setFlag(x.m, "blocked", false)
					end,
				},
				zoneSwitchOff = {
					function(x)
						Machine.setFlag(x.m, "enabled", false)
						Machine.setZone(x.m, true)
					end,
					function(x)
						Machine.setZone(x.m, false)
						Machine.setFlag(x.m, "enabled", true)
					end,
				},
				shown = {
					function(x)
						Machine.setFlag(x.m, "headHidden", false) -- zoomed out again
					end,
					function(x)
						Machine.setFlag(x.m, "headHidden", true)
					end,
				},
			}
			for name, pair in offs do
				pair[1](r)
				if Machine.look(r.m) ~= nil then
					error("still the lobby look with " .. name)
				end
				pair[2](r)
				if Machine.look(r.m) ~= "lobby" then
					error("no lobby look back after " .. name)
				end
			end
			expect.equal(r.m.mode, nil)
		end
	)

	t.test("the lobby look never writes the camera, the zoom, the cursor or the shoulder offset", function()
		local r = rig()
		Machine.setFlag(r.m, "headHidden", true)
		r.input.MouseBehavior = Enum.MouseBehavior.LockCenter -- Roblox locks the mouse in its own first person
		table.clear(r.writes) -- (the line above is the stand-in's write, not the machine's)
		r.step(10)
		Machine.setFlag(r.m, "headHidden", false)
		Machine.setFlag(r.m, "headHidden", true)
		r.step(3)
		expect.equal(Machine.look(r.m), "lobby")
		expect.deepEqual(r.writes, {})
		expect.deepEqual(r.shoulder, {})
		expect.deepEqual(r.faced, {})
		-- It does not depend on the "First-person duels" switch.
		Machine.setFlag(r.m, "enabled", false)
		expect.equal(Machine.look(r.m), "lobby")
	end)

	t.test("practice and the lobby hand over with no gap while the head stays hidden", function()
		local r = rig()
		Machine.setFlag(r.m, "headHidden", true)
		r.camera.CFrame = CFrame.new(0, 10, 0.5) -- zoomed into the head before walking into the box
		Machine.setZone(r.m, true)
		expect.equal(Machine.look(r.m), "practice")
		Machine.setZone(r.m, false)
		r.clock.advance(1)
		Machine.step(r.m)
		expect.equal(r.m.mode, nil)
		expect.equal(Machine.look(r.m), "lobby") -- the exit holds the zoom at 0.5: still in the head
		r.step(3)
		expect.deepEqual(r.looks, { "lobby", "practice", "lobby" })
	end)

	t.test("the exit's restore frames show no lobby look while the camera goes back out to third person", function()
		local r = rig()
		Machine.setZone(r.m, true) -- from third person (12 studs)
		Machine.setFlag(r.m, "headHidden", true) -- the forced first person hides the head
		expect.equal(Machine.look(r.m), "practice")
		Machine.setZone(r.m, false)
		r.clock.advance(1)
		Machine.step(r.m) -- the exit: the min zoom pushes the camera out to 12 for one frame
		expect.equal(Machine.look(r.m), nil) -- the head still reads hidden, but no overlay flash
		r.step(1)
		expect.equal(Machine.look(r.m), nil)
		Machine.setFlag(r.m, "headHidden", false) -- Roblox shows the head as the camera leaves it
		r.step(2)
		expect.equal(Machine.look(r.m), nil)
		expect.deepEqual(r.looks, { "practice", "none" })
		-- A head that somehow stays hidden after the restore is the player's own zoom again.
		Machine.setFlag(r.m, "headHidden", true)
		expect.equal(Machine.look(r.m), "lobby")
	end)

	t.test("a duel's look is its mode; LookChanged fires once per change", function()
		local r = rig()
		Machine.setFlag(r.m, "headHidden", true)
		Machine.setFlag(r.m, "inMatch", true)
		Machine.setPhase(r.m, "Preparing")
		expect.equal(Machine.look(r.m), nil)
		Machine.setPhase(r.m, "Countdown")
		Machine.setPhase(r.m, "Active")
		expect.equal(Machine.look(r.m), "duel")
		Machine.setPhase(r.m, "Returning")
		expect.equal(Machine.look(r.m), nil)
		Machine.setPhase(r.m, nil)
		Machine.setFlag(r.m, "inMatch", false)
		r.step(3)
		expect.equal(Machine.look(r.m), "lobby")
		expect.deepEqual(r.looks, { "lobby", "none", "duel", "none", "lobby" })
		expect.deepEqual(r.changes, { "duel", "none" })
	end)
end
