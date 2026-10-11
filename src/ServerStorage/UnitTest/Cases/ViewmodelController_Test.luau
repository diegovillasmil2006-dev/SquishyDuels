--!strict
-- ViewmodelController_Test: unit tests for StarterPlayerScripts.Client.Controllers.ViewmodelController (spec 2026-10-11
-- §3, §3.8; design: sd/fp.js). Server only (ServerStorage.UnitTest). Edit mode: useDeps() swaps every side-effecting
-- surface (the look, the held model and its rig, throws, controls, the net, state, sound, the ScreenGuis, the world
-- camera's FOV and shake, the scheduler, the motion setting, the camera and the clock) for a stand-in; the overlay
-- builds real instances (SquishyCache, SquishDeformer, DesignArm) unparented to any PlayerGui.
-- Contract:
--   * the overlay shows while a look is on ("duel", "practice" or "lobby") and the local player has a held model; it
--     hides (gui disabled, 0 parts, no Scheduler job, the mirror cleared, the world FOV given back) when the look ends;
--   * two arms of five parts (hand, thumb, forearm, cuff, sleeve); skin #F5CDA4; the sleeve is the duel side's team
--     colour, mint in practice and the lobby; the overlay camera's FOV is 70 and its light overlayLight();
--   * each show pops the toy in (scale backOut from ~0, from equipFrom), then the hold: the toy on held.pos (breathing)
--     and both hands at its sides with rolls ±0.4; the hands go to rest while the toy is out of the hand;
--   * the two-palm squeeze through the mirror: the palms on the toy's shown sides, rolls ±(0.4 + 0.3c), the toy to the
--     focus pose and the world FOV toward 64.5° (the FOV owner), the camera shake on (off with the setting); after the
--     press and 1.1 s the focus and the FOV go back and the hold on the FOV ends; ReducedMotion: no FOV, no tremor, the
--     overlay camera fixed;
--   * the hands ghost (40%) only until the own invulnUntil from ThrowImpact;
--   * DuelSqueeze passes while hidden and during a windup or a pop-in, and squeezes the toy in the hand; PracticeSqueeze
--     forwards each press to the lobby Squeeze (End only after its Begin; a hide ends it) and passes while hidden;
--   * the touch pad presses DuelSqueeze, PracticeSqueeze or the lobby Squeeze by the look, with its finger's
--     InputObject (lobby HUD spec 2026-10-11 §2: holding the pad keeps squeezing);
--   * the squeeze sounds play in duels only;
--   * a rebuilt held model mid-duel squeezes on X and pops in again; hiding gives the Catalog axis back;
--   * a throw: both hands start where they were, the toy on its track (the cocked key while the answer is out), the
--     release hides it with the overlay kick (-0.8) and the FOV kick (+80), the hands go to rest at dur and the toy pops
--     back in once it is in the hand; a cancelled windup goes back to the hold;
--   * lastReleasePoint: on the world camera's ray through where the toy was (factor 1), also when asked before the
--     overlay's frame; a wall cuts it to 0.5 in front (factor D / D0);
--   * Dragon Rush: the charge pose toward ult.pos with the glow ball, no squeeze meanwhile, back to the hold after;
--   * toyScreenPoint: nil while hidden, the toy's pixel point (below the centre) while it shows;
--   * debugPose freezes the named poses and nil lets the overlay live again.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local FRAME = 1 / 60
local BEGIN = Enum.UserInputState.Begin
local END = Enum.UserInputState.End

return function(t: Context)
	local Viewmodel = t.requireClient("Controllers/ViewmodelController")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local SquishRig = t.requireClient("Anim/SquishRig")
	local ThrowTracks = t.requireClient("Anim/ThrowTracks")
	local ViewmodelMath = t.requireClient("Anim/ViewmodelMath")
	local Signal = t.requireShared("Util/Signal")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local FakePlayer = t.requireFake("FakePlayer")
	local expect = t.expect
	local FP = Config.FirstPerson
	local PARTS = { "cuff", "forearm", "hand", "sleeve", "thumb" }

	type World = {
		clock: number,
		player: any,
		look: string?,
		holding: boolean,
		model: Instance?,
		squishyId: string,
		rig: any,
		mirror: any,
		windup: { any },
		ult: { any },
		duel: any,
		live: { [string]: boolean },
		handlers: { [string]: any },
		pressed: { string },
		pressedInputs: { [number]: any }, -- the input object each pressAction carried (false: none)
		sounds: { string },
		soundOptions: { any },
		guis: { [string]: ScreenGui },
		scheduler: any,
		lookChanged: any,
		heldChanged: any,
		impact: any,
		reduced: boolean,
		cameraShake: boolean,
		fov: { number }, -- every setFovOffset offset, in order
		fovHeld: boolean,
		shakes: { { number } },
		camera: { CFrame: CFrame, ViewportSize: Vector2 }, -- the world camera (a stand-in: Edit mode has no viewport)
		rayHit: number?, -- a wall this far along the release ray (Workspace:Raycast)
	}

	local function newRig(id: string): any
		local def = Catalog.get(id)
		return SquishRig.new(Blueprints[def.blueprintId].motion, {
			axis = def.anim.squeezeAxis,
			rarity = def.rarity,
			seed = 1,
			blink = false,
		})
	end

	-- A world with the overlay's dependencies as stand-ins; init() runs at the end.
	local function setup(id: string?): World
		local squishyId = id or "kitty_bread"
		local w: World = {
			clock = 100,
			player = FakePlayer.new(5),
			look = nil,
			holding = true,
			model = Instance.new("Model"),
			squishyId = squishyId,
			rig = newRig(squishyId),
			mirror = nil,
			windup = { nil, nil, nil, nil, false },
			ult = { nil, nil, nil },
			duel = nil,
			live = { DuelSqueeze = true, PracticeSqueeze = true, Squeeze = true },
			handlers = {},
			pressed = {},
			pressedInputs = {},
			sounds = {},
			soundOptions = {},
			guis = {},
			scheduler = Scheduler.new(false),
			lookChanged = Signal.new(),
			heldChanged = Signal.new(),
			impact = Signal.new(),
			reduced = false,
			cameraShake = true,
			fov = {},
			fovHeld = false,
			shakes = {},
			camera = { CFrame = CFrame.new(0, 5, 0), ViewportSize = Vector2.new(1920, 1080) },
			rayHit = nil,
		}
		local worldCamera = w.camera
		Viewmodel.useDeps({
			FirstPerson = {
				look = function(): string?
					return w.look
				end,
				LookChanged = w.lookChanged,
			},
			Held = {
				getModel = function(player: any): Instance?
					return if player == w.player then w.model else nil
				end,
				getRig = function(player: any): any
					return if player == w.player and w.model then w.rig else nil
				end,
				getSquishyId = function(player: any): string?
					return if player == w.player and w.model then w.squishyId else nil
				end,
				isHolding = function(player: any): boolean
					return player == w.player and w.model ~= nil and w.holding
				end,
				setMirror = function(fn: any)
					w.mirror = fn
				end,
				HeldChanged = w.heldChanged,
			},
			Throw = {
				localWindup = function(): (number?, number?, number?, number?, boolean)
					return w.windup[1], w.windup[2], w.windup[3], w.windup[4], w.windup[5] == true
				end,
				localUlt = function(): (string?, number?, number?)
					return w.ult[1], w.ult[2], w.ult[3]
				end,
			},
			Controls = {
				bindAction = function(action: string, handler: any): () -> ()
					w.handlers[action] = handler
					return function()
						w.handlers[action] = nil
					end
				end,
				pressAction = function(action: string, state: Enum.UserInputState, input: any?): boolean
					table.insert(w.pressed, `{action}:{state.Name}`)
					w.pressedInputs[#w.pressed] = input or false
					local handler = w.handlers[action]
					return handler ~= nil and w.live[action] == true and handler(state, nil) == true
				end,
				preferredInput = function(): Enum.PreferredInput
					return Enum.PreferredInput.KeyboardAndMouse
				end,
				touchLayout = function(): any
					return nil
				end,
			},
			Net = {
				onThrowImpact = function(handler: any): any
					return w.impact:connect(handler)
				end,
			},
			State = {
				duel = function(): any
					return w.duel
				end,
				settings = function(): any
					return { cameraShake = w.cameraShake }
				end,
			},
			Sound = {
				play = function(key: string, options: any): boolean
					table.insert(w.sounds, key)
					table.insert(w.soundOptions, options)
					return true
				end,
			},
			UI = {
				screenGui = function(name: string, spec: any): ScreenGui
					local gui: ScreenGui? = w.guis[name]
					if gui == nil then
						local created = Instance.new("ScreenGui")
						created.Name = name
						created.DisplayOrder = spec.displayOrder
						created.ScreenInsets = spec.insets
						w.guis[name] = created
						gui = created
					end
					return gui :: ScreenGui
				end,
			},
			Camera = {
				setFovOffset = function(owner: string, offsetDeg: number): boolean
					expect.equal(owner, "Viewmodel")
					table.insert(w.fov, offsetDeg)
					w.fovHeld = offsetDeg ~= 0 and not w.reduced
					return w.fovHeld
				end,
				shake = function(amplitudeDeg: number, seconds: number): boolean
					table.insert(w.shakes, { amplitudeDeg, seconds })
					return true
				end,
			},
			Scheduler = {
				add = function(effect: any, phase: any): any
					return w.scheduler:add(effect, phase)
				end,
			},
			Motion = {
				reducedMotion = function(): boolean
					return w.reduced
				end,
			},
			Workspace = {
				CurrentCamera = worldCamera,
				GetServerTimeNow = function(): number
					return w.clock
				end,
				Raycast = function(): any
					return if w.rayHit then { Distance = w.rayHit } else nil
				end,
				FindFirstChild = function(): any
					return nil
				end,
			},
			Players = { LocalPlayer = w.player },
		})
		Viewmodel.init()
		return w
	end

	local function teardown()
		Viewmodel.destroy()
		Viewmodel.useDeps(nil)
	end

	local function enter(w: World, look: string)
		w.look = look
		w.lookChanged:fire(look)
	end

	local function leave(w: World)
		w.look = nil
		w.lookChanged:fire(nil)
	end

	local function frames(w: World, n: number)
		for _ = 1, n do
			w.clock += FRAME
			w.scheduler:tick("render", FRAME, w.clock)
		end
	end

	local function overlayParts(w: World): number
		local gui = w.guis.SD_Viewmodel
		local count = 0
		if gui then
			for _, d in gui:GetDescendants() do
				if d:IsA("BasePart") then
					count += 1
				end
			end
		end
		return count
	end

	-- A mirrored rig frame: the rig's shown scale S (X narrowed by `narrow`), no idle, pop or overlay scale on top,
	-- press amount c.
	local function press(w: World, c: number, narrow: number?)
		local out = SquishRig.newOut()
		local x = 1 - (narrow or 0)
		out.S = Vector3.new(x, 1 / math.sqrt(x), 1 / math.sqrt(x))
		out.pressAmount = c
		w.mirror(out, Vector3.one)
	end

	local function close(a: Vector3, b: Vector3, tolerance: number?): boolean
		return (a - b).Magnitude <= (tolerance or 1e-3)
	end

	t.test(
		"shown while a look is on with a held model; hidden: disabled, 0 parts, no job, the FOV given back",
		function()
			local w = setup()
			expect.falsy(Viewmodel.isShown())
			expect.equal(w.scheduler:count("render"), 0)
			for _, look in { "duel", "practice", "lobby" } do
				enter(w, look)
				expect.truthy(Viewmodel.isShown())
				expect.truthy(w.guis.SD_Viewmodel.Enabled)
				expect.equal(w.guis.SD_Viewmodel.DisplayOrder, -1)
				expect.equal(w.guis.SD_Viewmodel.ScreenInsets, Enum.ScreenInsets.None)
				expect.equal(w.scheduler:count("render"), 1)
				expect.truthy(w.mirror ~= nil)
				frames(w, 3)
				expect.truthy(overlayParts(w) > 10) -- two arms of five and the toy
				leave(w)
				expect.falsy(Viewmodel.isShown())
				expect.falsy(w.guis.SD_Viewmodel.Enabled)
				expect.equal(overlayParts(w), 0)
				expect.equal(w.scheduler:count("render"), 0)
				expect.equal(w.mirror, nil)
				expect.equal(w.fov[#w.fov], 0) -- the hold on the world FOV ends with the base back
			end
			-- A look with no held model: no overlay; it shows once the model is built.
			local model = w.model
			w.model = nil
			enter(w, "lobby")
			expect.falsy(Viewmodel.isShown())
			w.model = model
			w.heldChanged:fire(w.player, model)
			expect.truthy(Viewmodel.isShown())
			teardown()
		end
	)

	t.test("two arms of five parts; the design's skin; the sleeve: the duel side's, mint elsewhere; FOV 70", function()
		local w = setup()
		w.duel = { phase = "Active", phaseEndsAt = w.clock + 60, you = { side = "A" }, opponent = { side = "B" } }
		enter(w, "duel")
		local state = Viewmodel.debugState()
		expect.deepEqual(state.leftParts, PARTS)
		expect.deepEqual(state.rightParts, PARTS)
		expect.equal(state.skin, FP.colours.skin:ToHex())
		expect.equal(state.sleeve, FP.teamSleeves.A:ToHex())
		local viewport = w.guis.SD_Viewmodel:FindFirstChildOfClass("ViewportFrame") :: ViewportFrame
		expect.equal((viewport:FindFirstChildOfClass("Camera") :: Camera).FieldOfView, 70)
		local ambient, colour, direction = ViewmodelMath.overlayLight()
		expect.equal(viewport.Ambient, ambient)
		expect.equal(viewport.LightColor, colour)
		expect.truthy((viewport.LightDirection - direction).Magnitude < 1e-5)
		leave(w)
		w.duel.you.side = "B"
		enter(w, "duel")
		expect.equal(Viewmodel.debugState().sleeve, FP.teamSleeves.B:ToHex())
		leave(w)
		w.duel = nil
		for _, look in { "practice", "lobby" } do
			enter(w, look)
			expect.equal(Viewmodel.debugState().sleeve, FP.colours.sleeve:ToHex())
			leave(w)
		end
		teardown()
	end)

	t.test("each show pops the toy in, then the hold: the toy on held.pos, both hands at its sides", function()
		local w = setup()
		enter(w, "lobby")
		frames(w, 1)
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "equip")
		expect.truthy(state.scale < 0.4) -- backOut from 0 (fp.js:403)
		expect.truthy(state.toyPos.Y < FP.held.pos.Y - 0.1) -- springing up from equipFrom
		frames(w, 12) -- 0.22 s: past the overshoot's start
		expect.truthy(Viewmodel.debugState().scale > 1)
		frames(w, 120)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "idle")
		expect.equal(state.scale, 1)
		expect.truthy(close(state.toyPos, FP.held.pos, FP.idle.breath + 1e-3))
		local left, right = ViewmodelMath.sides(state.toyPos, state.hw)
		expect.truthy(close(state.leftPos, left, 0.01) and close(state.rightPos, right, 0.01))
		expect.near(state.leftRoll, FP.arm.roll, 1e-3)
		expect.near(state.rightRoll, -FP.arm.roll, 1e-3)
		-- The hold's toy is 0.19 du on its longest side: its half width under that.
		expect.truthy(state.hw > 0.02 and state.hw <= 0.095 + 1e-6)
		-- Out of the hand (seated, thrown): empty hands at rest, the toy hidden.
		w.holding = false
		frames(w, 90)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "empty")
		expect.falsy(state.toyShown)
		expect.truthy(close(state.leftPos, Vector3.new(-FP.rest.X, FP.rest.Y, FP.rest.Z), 1e-3))
		expect.truthy(close(state.rightPos, FP.rest, 1e-3))
		-- Back in the hand: the pop-in again.
		w.holding = true
		frames(w, 1)
		expect.equal(Viewmodel.debugState().kind, "equip")
		teardown()
	end)

	t.test("the two-palm squeeze: palms on the shown sides, the focus pose, the FOV to 64.5°, the shake", function()
		local w = setup()
		enter(w, "lobby")
		frames(w, 60)
		table.clear(w.fov)
		-- A press 0.5 deep, the toy 15% narrower on X.
		for _ = 1, 90 do
			press(w, 0.5, 0.15)
			frames(w, 1)
		end
		local state = Viewmodel.debugState()
		expect.near(state.focus, 1, 0.02)
		expect.truthy(close(state.toyPos, FP.focus.pos, 0.003))
		local mirrored = Vector3.new(0.85, 1 / math.sqrt(0.85), 1 / math.sqrt(0.85))
		local left, right = ViewmodelMath.palms(state.toyPos, state.hw, mirrored, 1, 0.5, 0, 0, false)
		expect.truthy(close(state.leftPos, left, 0.004) and close(state.rightPos, right, 0.004)) -- ± the tremor
		expect.near(state.leftRoll, FP.arm.roll + FP.squeeze.rollPress * 0.5, 2e-3)
		expect.near(state.rightRoll, -(FP.arm.roll + FP.squeeze.rollPress * 0.5), 2e-3)
		-- The world FOV goes to 70 - 5.5 through the owner; the shake rose (the setting is on).
		expect.near(w.fov[#w.fov], FP.focus.worldFovTarget * FP.focus.worldFovPerUnit, 0.1)
		expect.truthy(#w.shakes > 0)
		-- Let go: the focus and the FOV come back after the 1.1-s linger, and the hold ends at 0.
		press(w, 0)
		frames(w, 30)
		expect.truthy(Viewmodel.debugState().focus > 0.9) -- lingering
		w.mirror(nil, Vector3.one)
		frames(w, 240)
		state = Viewmodel.debugState()
		expect.near(state.focus, 0, 1e-3)
		expect.equal(w.fov[#w.fov], 0)
		expect.falsy(w.fovHeld)
		-- With the Camera shake setting off, no shake.
		table.clear(w.shakes)
		w.cameraShake = false
		for _ = 1, 20 do
			press(w, 0.8, 0.2)
			frames(w, 1)
		end
		expect.equal(#w.shakes, 0)
		teardown()
	end)

	t.test("ReducedMotion: no world FOV, no tremor, the overlay camera fixed, no pop-in overshoot", function()
		local w = setup()
		w.reduced = true
		enter(w, "lobby")
		frames(w, 1)
		local first = Viewmodel.debugState().scale
		local most = first
		for _ = 1, 39 do
			frames(w, 1)
			most = math.max(most, Viewmodel.debugState().scale)
		end
		expect.truthy(first < 0.5) -- the pop-in still grows (DESIGN §9.12: only its overshoot goes) ...
		expect.equal(most, 1) -- ... and never past 1
		for _ = 1, 90 do
			press(w, 0.6, 0.2)
			frames(w, 1)
		end
		local state = Viewmodel.debugState()
		for _, offset in w.fov do
			expect.equal(offset, 0)
		end
		expect.truthy(state.camera == CFrame.identity)
		-- The left palm's x over 10 more frames of the same press: still (the target holds), unless it trembles.
		local function spread(): number
			local lo, hi = math.huge, -math.huge
			for _ = 1, 10 do
				press(w, 0.6, 0.2)
				frames(w, 1)
				local x = Viewmodel.debugState().leftPos.X
				lo, hi = math.min(lo, x), math.max(hi, x)
			end
			return hi - lo
		end
		expect.truthy(spread() < 1e-6) -- no tremor
		expect.equal(#w.shakes, 0)
		w.reduced = false
		expect.truthy(spread() > 1e-5) -- the same press without ReducedMotion trembles (fp.js:413-414)
		teardown()
	end)

	-- First-person spec 2026-10-10 §5 (low tier): a full-screen viewport redraws whenever anything in it changes, so on
	-- MeshQuality "Low" (a compact screen or touch only) the overlay has no idle drift and no breath; actions still move.
	t.test("low tier: at rest the overlay holds still (no idle drift, no breath)", function()
		local w = setup()
		w.camera.ViewportSize = Vector2.new(667, 375) -- compact: MeshQuality "Low"
		enter(w, "lobby")
		frames(w, 60) -- past the pop-in and the hands' springs
		local cameraAt, toyAt = Viewmodel.debugState().camera, Viewmodel.debugState().toyPos
		frames(w, 45)
		local state = Viewmodel.debugState()
		expect.truthy(state.camera == CFrame.identity)
		expect.truthy(cameraAt == state.camera)
		expect.truthy((state.toyPos - toyAt).Magnitude < 1e-6)
		teardown()
		-- The same rest on a regular screen drifts and breathes (fp.js:396, 660).
		local high = setup()
		enter(high, "lobby")
		frames(high, 60)
		local before = Viewmodel.debugState().toyPos
		frames(high, 45)
		expect.truthy((Viewmodel.debugState().toyPos - before).Magnitude > 1e-5)
		expect.falsy(Viewmodel.debugState().camera == CFrame.identity)
		teardown()
	end)

	t.test("ReducedMotion: the Dragon Rush's wobble and glow pulse hold still (DESIGN §9.12, §18.1 #4)", function()
		local w = setup("dragon")
		w.reduced = true
		enter(w, "duel")
		frames(w, 60)
		w.ult = { "telegraph", w.clock + Config.Abilities.dragon_rush.telegraphSeconds, nil }
		frames(w, 20)
		local viewport = w.guis.SD_Viewmodel:FindFirstChildOfClass("ViewportFrame") :: ViewportFrame
		local found = viewport:FindFirstChild("UltGlow")
		expect.truthy(found ~= nil and found:IsA("BasePart"))
		local glow = found :: BasePart
		local size = glow.Size
		for _ = 1, 12 do
			frames(w, 1)
			local state = Viewmodel.debugState()
			expect.equal(state.kind, "ult")
			expect.near(state.sq.X, 1, 1e-9) -- no 40 rad/s wobble (fp.js:453)
			expect.equal(glow.Size, size) -- no 30 rad/s pulse (fp.js:457)
		end
		-- The plain radius (a part's Size is stored to about 1e-5).
		expect.truthy((size - Vector3.one * (2 * FP.ult.glowRadius * FP.overlayStudsPerDu)).Magnitude < 1e-3)
		teardown()
	end)

	t.test(
		"the overlay shows the rig's own S: the held model's idle, pop-in and overlay scale is divided out",
		function()
			local w = setup()
			enter(w, "lobby")
			frames(w, 60)
			-- The held model's frame (finishOut): the rig at rest × its idle breath (not uniform) × a pop-in.
			local scale = Vector3.new(0.9825, 1.035, 0.9825) * 0.7
			local out = SquishRig.newOut()
			out.S = scale
			w.mirror(out, scale)
			frames(w, 1)
			expect.truthy(close(Viewmodel.debugState().shownScale, Vector3.one, 1e-6)) -- the design's toy has neither (fp.js:396)
			-- A squeeze 15% narrower on X under the same scale: the rig's own narrowing shows, the palms on its sides.
			local x = 0.85
			local rigS = Vector3.new(x, 1 / math.sqrt(x), 1 / math.sqrt(x))
			for _ = 1, 60 do
				out.S = rigS * scale
				out.pressAmount = 0.5
				w.mirror(out, scale)
				frames(w, 1)
			end
			local state = Viewmodel.debugState()
			expect.truthy(close(state.shownScale, rigS, 1e-6))
			local left, right = ViewmodelMath.palms(state.toyPos, state.hw, rigS, 1, 0.5, 0, 0, false)
			expect.truthy(close(state.leftPos, left, 0.004) and close(state.rightPos, right, 0.004)) -- ± the tremor
			teardown()
		end
	)

	t.test("the hands ghost at 40% only until the own invulnUntil", function()
		local w = setup()
		enter(w, "duel")
		frames(w, 2)
		expect.equal(Viewmodel.debugState().ghost, 0)
		w.impact:fire({ victimId = 999, invulnUntil = w.clock + 1 }) -- someone else's hit
		frames(w, 1)
		expect.equal(Viewmodel.debugState().ghost, 0)
		w.impact:fire({ victimId = w.player.UserId, invulnUntil = w.clock + 0.5 })
		frames(w, 1)
		expect.near(Viewmodel.debugState().ghost, FP.invulnTransparency, 1e-6)
		frames(w, 31)
		expect.equal(Viewmodel.debugState().ghost, 0)
		teardown()
	end)

	t.test("DuelSqueeze: passes while hidden and during a windup or a pop-in; squeezes the toy in the hand", function()
		local w = setup()
		local duel = w.handlers.DuelSqueeze
		expect.truthy(duel ~= nil)
		expect.equal(duel(BEGIN, nil), false) -- hidden: third-person duels are today's
		enter(w, "duel")
		frames(w, 2)
		expect.equal(duel(BEGIN, nil), false) -- popping in
		frames(w, 40)
		expect.equal(duel(BEGIN, nil), true)
		expect.truthy(w.rig:elapsedMs() ~= nil) -- pressed
		expect.equal(duel(END, nil), true)
		frames(w, 60)
		-- A windup: dropped and passed.
		w.windup = { 0.05, 0.18, nil, nil, false }
		frames(w, 1)
		expect.equal(duel(BEGIN, nil), false)
		expect.equal(duel(END, nil), false)
		teardown()
	end)

	t.test("PracticeSqueeze forwards each press to the lobby Squeeze; passes hidden; a hide ends a held one", function()
		local w = setup()
		local practice = w.handlers.PracticeSqueeze
		expect.equal(practice(BEGIN, nil), false) -- hidden: the lobby's Squeeze answers as today
		expect.equal(practice(END, nil), false)
		enter(w, "practice")
		frames(w, 30)
		expect.equal(practice(END, nil), false) -- no Begin of its own
		expect.equal(practice(BEGIN, nil), true)
		expect.equal(practice(END, nil), true)
		expect.deepEqual(w.pressed, { "Squeeze:Begin", "Squeeze:End" })
		-- During a windup too: the paid squeeze is the lobby's own business.
		w.windup = { 0.05, 0.18, nil, nil, false }
		frames(w, 1)
		expect.equal(practice(BEGIN, nil), true)
		-- Leaving the box with it held: the lobby squeeze gets its End.
		leave(w)
		expect.deepEqual(w.pressed, { "Squeeze:Begin", "Squeeze:End", "Squeeze:Begin", "Squeeze:End" })
		expect.equal(practice(END, nil), false)
		teardown()
	end)

	t.test(
		"PracticeSqueeze hands its key on, so a held F, E or ButtonX repeats the paid squeeze as in the lobby",
		function()
			local w = setup()
			local practice = w.handlers.PracticeSqueeze
			enter(w, "practice")
			frames(w, 30)
			local key = { UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.F } -- an InputObject stand-in
			expect.equal(practice(BEGIN, key), true)
			expect.equal(practice(END, key), true)
			expect.deepEqual(w.pressed, { "Squeeze:Begin", "Squeeze:End" })
			expect.equal(w.pressedInputs[1], key) -- SqueezeController holds while that key is down
			expect.equal(w.pressedInputs[2], key)
			teardown()
		end
	)

	t.test(
		"the touch pad presses DuelSqueeze, PracticeSqueeze or the lobby Squeeze by the look, with its finger",
		function()
			local w = setup()
			for _, case in { { "duel", "DuelSqueeze" }, { "practice", "PracticeSqueeze" }, { "lobby", "Squeeze" } } do
				enter(w, case[1])
				frames(w, 40)
				expect.equal(Viewmodel.padAction(), case[2])
				table.clear(w.pressed)
				table.clear(w.pressedInputs)
				-- Lobby HUD spec 2026-10-11 §2: the finger goes with the press, so holding the pad keeps squeezing.
				local finger = { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(400, 300, 0) }
				Viewmodel.pressPad(BEGIN, finger)
				Viewmodel.pressPad(END, finger)
				expect.equal(w.pressed[1], `{case[2]}:Begin`)
				expect.equal(w.pressedInputs[1], finger)
				expect.equal(w.pressed[#w.pressed], `{case[2] == "PracticeSqueeze" and "Squeeze" or case[2]}:End`)
				leave(w)
			end
			expect.equal(Viewmodel.padAction(), nil)
			teardown()
		end
	)

	t.test("the squeeze sounds play in duels only, at the toy's pitch", function()
		local w = setup("kitty_bread")
		for _, look in { "lobby", "practice", "duel" } do
			enter(w, look)
			frames(w, 2)
			local out = SquishRig.newOut()
			out.events = SquishRig.EVENTS.squish
			w.mirror(out, Vector3.one)
			out.events = SquishRig.EVENTS.popEnd
			w.mirror(out, Vector3.one)
			out.events = 0
			w.mirror(out, Vector3.one)
			leave(w)
		end
		expect.deepEqual(w.sounds, { "sfx.squish", "sfx.squeezeRelease" })
		local pitch = Blueprints.kitty_bread.motion.squeeze.pitch or 1
		expect.near(w.soundOptions[1].pitch, pitch, 1e-9)
		expect.near(w.soundOptions[1].variance, 0.06, 1e-9)
		expect.equal(w.soundOptions[1].at, nil) -- 2D
		teardown()
	end)

	t.test("a rebuilt held model mid-duel squeezes on X and pops in again; hiding gives the axis back", function()
		local w = setup("banana") -- Catalog axis Z
		enter(w, "duel")
		frames(w, 40)
		expect.equal(w.rig:axis(), "X") -- Config.FirstPerson.squeezeAxis (spec 2026-10-11 §3.4)
		local oldRig = w.rig
		w.squishyId = "strawberry_frog"
		w.rig = newRig("strawberry_frog")
		w.model = Instance.new("Model")
		w.heldChanged:fire(w.player, w.model)
		expect.equal(Viewmodel.debugState().kind, "equip")
		frames(w, 2)
		expect.equal(w.rig:axis(), "X")
		expect.equal(Viewmodel.debugState().toy, "strawberry_frog")
		w.squishyId = "banana"
		w.rig = oldRig
		w.heldChanged:fire(w.player, w.model)
		frames(w, 2)
		leave(w)
		expect.equal(oldRig:axis(), "Z")
		teardown()
	end)

	-- One local throw through the windup values ThrowController.localWindup gives: tau runs to W, the answer comes
	-- `lead` seconds ahead, then the release (the held model hides). Returns releaseAt.
	local function throwOnce(w: World, W: number, lead: number): number
		for i = 1, math.ceil(W / FRAME) + 2 do
			w.windup = { math.min(i * FRAME, W), W, nil, nil, false }
			frames(w, 1)
		end
		local releaseAt = w.clock + lead
		while w.clock + FRAME < releaseAt do
			w.windup = { W, W, releaseAt, nil, false }
			frames(w, 1)
		end
		w.windup = { W, W, releaseAt, releaseAt, false }
		w.holding = false
		return releaseAt
	end

	t.test("a throw: both hands from where they were, the toy on its track, the release kicks, then rest", function()
		local w = setup("kitty_bread") -- overhand
		enter(w, "duel")
		frames(w, 60)
		local before = Viewmodel.debugState()
		local track = ThrowTracks.get("overhand")
		local W = 0.18
		for i = 1, 14 do
			w.windup = { math.min(i * FRAME, W), W, nil, nil, false }
			frames(w, 1)
		end
		-- Cocked and waiting for the answer: the track holds the cocked key.
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "throw")
		expect.truthy(state.toyShown)
		expect.near(state.trackTime, track.cock, 1e-6)
		local cockPos = ThrowTracks.toyAt(track, track.cock)
		local cockL, cockR = ThrowTracks.handsAt(track, track.cock, before.leftPos, before.rightPos)
		frames(w, 30) -- (the answer is late: the springs reach the cocked pose)
		w.windup = { W, W, nil, nil, false }
		state = Viewmodel.debugState()
		expect.truthy(close(state.toyPos, cockPos, 0.01))
		expect.truthy(close(state.leftPos, cockL, 0.01) and close(state.rightPos, cockR, 0.01))
		expect.near(state.rightRoll, -(FP.arm.roll + FP.throwFx.rollCocked), 0.01)
		expect.near(state.leftRoll, FP.throwFx.rollL, 0.01)
		throwOnce(w, W, 0.1)
		frames(w, 1)
		state = Viewmodel.debugState()
		expect.truthy(state.released)
		expect.falsy(state.toyShown)
		expect.truthy(state.kickVelocity < -0.3) -- -0.8, one spring step in
		expect.truthy(state.fovVelocity > 40) -- +80, one spring step in
		expect.truthy(state.shake > 0.1)
		-- After dur the hands rest; the toy pops back in once it is in the hand.
		w.windup = { nil, nil, nil, nil, false }
		frames(w, 120)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "empty")
		expect.truthy(close(state.rightPos, FP.rest, 1e-3))
		w.holding = true
		frames(w, 1)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "equip")
		expect.truthy(state.toyShown)
		teardown()
	end)

	t.test("a cancelled windup goes back to the hold", function()
		local w = setup("kitty_bread")
		enter(w, "duel")
		frames(w, 60)
		for i = 1, 8 do
			w.windup = { i * FRAME, 0.18, nil, nil, false }
			frames(w, 1)
		end
		expect.equal(Viewmodel.debugState().kind, "throw")
		w.windup = { 8 * FRAME, 0.18, nil, nil, true }
		frames(w, 1)
		expect.equal(Viewmodel.debugState().kind, "idle")
		frames(w, 120)
		expect.truthy(close(Viewmodel.debugState().toyPos, FP.held.pos, FP.idle.breath + 1e-3))
		teardown()
	end)

	t.test(
		"lastReleasePoint: on the camera ray through the toy, as far as a held-size model there; cover cuts it",
		function()
			local w = setup()
			enter(w, "duel")
			frames(w, 60)
			expect.equal(Viewmodel.lastReleasePoint(), nil)
			throwOnce(w, 0.18, 0.1)
			local point, factor = Viewmodel.lastReleasePoint() -- asked before the overlay's own frame saw the release
			expect.truthy(point ~= nil)
			expect.near(factor :: number, 1, 1e-6)
			local camera = w.camera.CFrame
			local seen = camera:PointToObjectSpace(point :: Vector3)
			expect.truthy(seen.Z < 0) -- ahead, where the toy was
			local d0 = seen.Magnitude
			expect.truthy(d0 > 3 and d0 < 12) -- the overlay toy's distance ÷ its scale against the held one
			frames(w, 1)
			local again = Viewmodel.lastReleasePoint()
			expect.truthy(again ~= nil and ((again :: Vector3) - (point :: Vector3)).Magnitude < 1e-6)
			teardown()

			-- A wall 2 studs along that ray: 0.5 in front of it, the size factor D / D0.
			local walled = setup()
			walled.rayHit = 2
			enter(walled, "duel")
			frames(walled, 60)
			throwOnce(walled, 0.18, 0.1)
			frames(walled, 1)
			local cut, cutFactor = Viewmodel.lastReleasePoint()
			expect.near(((cut :: Vector3) - walled.camera.CFrame.Position).Magnitude, 1.5, 1e-3)
			expect.truthy((cutFactor :: number) < 1)
			teardown()
		end
	)

	t.test("Dragon Rush: the charge pose with the glow ball, no squeeze meanwhile, back to the hold after", function()
		local w = setup("dragon")
		local duel = w.handlers.DuelSqueeze
		enter(w, "duel")
		frames(w, 60)
		w.ult = { "telegraph", w.clock + Config.Abilities.dragon_rush.telegraphSeconds, nil }
		frames(w, 27) -- halfway
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "ult")
		expect.truthy(state.glow > 0.05 and state.glow < FP.ult.glowOpacity)
		expect.equal(duel(BEGIN, nil), false) -- no squeeze while charging
		local viewport = w.guis.SD_Viewmodel:FindFirstChildOfClass("ViewportFrame") :: ViewportFrame
		local found = viewport:FindFirstChild("UltGlow")
		expect.truthy(found ~= nil and found:IsA("BasePart"))
		local glow = found :: BasePart
		expect.equal(glow.Material, Enum.Material.Neon)
		expect.near(glow.Transparency, 1 - state.glow, 1e-6)
		frames(w, 40) -- charged
		state = Viewmodel.debugState()
		expect.truthy(close(state.toyPos, FP.ult.pos, 0.01))
		expect.near(state.toyRot.X, FP.ult.pitch, 0.01)
		w.ult = { "release", nil, w.clock }
		frames(w, 1)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "idle")
		-- The release (fp.js:331, 461): the glow off at once, the overlay kick, the world FOV kick, shake >= 0.3.
		expect.equal(state.glow, 0)
		expect.near(glow.Transparency, 1, 1e-9)
		expect.truthy(state.kickVelocity < -1) -- -1.2
		expect.truthy(state.fovVelocity > 80) -- +90
		expect.truthy(state.shake >= FP.ult.releaseShake - 1e-9)
		expect.near(w.shakes[#w.shakes][1], (ViewmodelMath.shakeFor(FP.ult.releaseShake)), 1e-9)
		w.ult = { nil, nil, nil }
		frames(w, 120)
		state = Viewmodel.debugState()
		expect.truthy(close(state.toyPos, FP.held.pos, FP.idle.breath + 1e-3))
		expect.equal(state.glow, 0)
		expect.equal(duel(BEGIN, nil), true)
		duel(END, nil)
		-- A cancelled charge: no release kick, and the glow fades out (fp.js:466).
		frames(w, 60)
		w.ult = { "telegraph", w.clock + Config.Abilities.dragon_rush.telegraphSeconds, nil }
		frames(w, 40)
		local charged = Viewmodel.debugState().glow
		w.ult = { "cancel", nil, nil }
		frames(w, 1)
		state = Viewmodel.debugState()
		expect.truthy(state.glow > 0 and state.glow < charged)
		expect.truthy(state.kickVelocity > -0.5)
		teardown()
	end)

	t.test("the Dragon roars as its throw starts: shake 0.25 (fp.js:181, 305); other toys do not", function()
		local w = setup("dragon")
		enter(w, "duel")
		frames(w, 60)
		w.windup = { FRAME, 0.18, nil, nil, false }
		frames(w, 1)
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "throw")
		expect.near(state.shake, FP.throwFx.dragonRoarShake, 1e-9)
		expect.near(w.shakes[#w.shakes][1], (ViewmodelMath.shakeFor(FP.throwFx.dragonRoarShake)), 1e-9)
		frames(w, 1) -- once, at the start
		expect.truthy(Viewmodel.debugState().shake < FP.throwFx.dragonRoarShake)
		teardown()
		local other = setup("kitty_bread")
		enter(other, "duel")
		frames(other, 60)
		other.windup = { FRAME, 0.18, nil, nil, false }
		frames(other, 1)
		expect.equal(Viewmodel.debugState().kind, "throw")
		expect.equal(Viewmodel.debugState().shake, 0)
		teardown()
	end)

	t.test("toyScreenPoint: nil while hidden; the toy's pixel point below the centre while it shows", function()
		local w = setup()
		expect.equal(Viewmodel.toyScreenPoint(), nil)
		enter(w, "lobby")
		frames(w, 60)
		local shown: Vector2? = Viewmodel.toyScreenPoint()
		expect.truthy(shown ~= nil)
		local point = shown :: Vector2
		expect.truthy(point.Y > 540 and point.Y < 1080) -- the hold is below the centre, on screen
		expect.near(point.X, 960, 960 * 0.05) -- and about in the middle
		w.holding = false -- thrown: no toy, no point
		frames(w, 2)
		expect.equal(Viewmodel.toyScreenPoint(), nil)
		leave(w)
		expect.equal(Viewmodel.toyScreenPoint(), nil)
		teardown()
	end)

	t.test("debugPose freezes the overlay for pictures; nil lets it live again", function()
		local w = setup("kitty_bread")
		enter(w, "duel")
		frames(w, 10)
		expect.falsy(Viewmodel.debugPose("nope"))
		expect.truthy(Viewmodel.debugPose("empty"))
		frames(w, 3)
		local state = Viewmodel.debugState()
		expect.deepEqual({ state.pose, state.kind, state.toyShown }, { "empty", "empty", false } :: { any })
		expect.truthy(close(state.rightPos, FP.rest, 1e-6))
		expect.truthy(Viewmodel.debugPose("windup"))
		frames(w, 3)
		state = Viewmodel.debugState()
		local track = ThrowTracks.get("overhand")
		expect.truthy(state.kind == "throw" and state.toyShown)
		expect.truthy(close(state.toyPos, (ThrowTracks.toyAt(track, track.cock)), 1e-6))
		expect.near(w.rig:squeezeY(), 1, 1e-6) -- the design's throw does not squash the toy (fp.js:430-443)
		expect.truthy(Viewmodel.debugPose("popin"))
		frames(w, 3)
		expect.near(Viewmodel.debugState().scale, ViewmodelMath.backOut(0.5), 1e-9)
		expect.truthy(Viewmodel.debugPose("rush"))
		frames(w, 3)
		state = Viewmodel.debugState()
		expect.truthy(state.kind == "ult" and state.glow > 0)
		expect.truthy(Viewmodel.debugPose("squeeze"))
		expect.truthy(w.rig:elapsedMs() ~= nil) -- pressed: the rig holds the press at its deepest
		expect.truthy(Viewmodel.debugPose(nil))
		frames(w, 120)
		state = Viewmodel.debugState()
		expect.equal(state.pose, nil)
		expect.equal(state.kind, "idle")
		expect.truthy(close(state.toyPos, FP.held.pos, FP.idle.breath + 1e-3))
		teardown()
	end)

	t.test(
		"the sling's stretch shows whole: the overlay copy's deformer keeps the design's 1.75 (fp.js:152)",
		function()
			local w = setup("mochi_fox") -- sling
			enter(w, "duel")
			frames(w, 60)
			expect.truthy(Viewmodel.debugPose("windup")) -- the cocked key: sq (0.78, 0.85, 1.75)
			frames(w, 2)
			local shown = Viewmodel.debugState().shownScale
			expect.truthy(close(shown, Vector3.new(0.78, 0.85, 1.75), 1e-6))
			teardown()
		end
	)
end
