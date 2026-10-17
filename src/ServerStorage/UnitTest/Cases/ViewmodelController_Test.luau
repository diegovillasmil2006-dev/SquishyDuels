--!strict
-- ViewmodelController_Test: unit tests for StarterPlayerScripts.Client.Controllers.ViewmodelController (spec 2026-10-11
-- §3, §3.8; design: sd/fp.js). Server only (ServerStorage.UnitTest). Edit mode: useDeps() swaps every side-effecting
-- surface (the look, the held model and its rig, throws, controls, the net, state, sound, the ScreenGuis, the world
-- camera's FOV and shake, the scheduler, the motion setting, the camera and the clock) for a stand-in; the overlay
-- builds real instances (SquishyCache, SquishDeformer, DesignArm) unparented to any PlayerGui.
-- Contract:
--   * the overlay shows while a look is on ("duel", "practice" or "lobby") and the local player has a held model; it
--     hides (gui disabled, 0 parts, no Scheduler job, the mirror cleared, the world FOV given back) when the look ends;
--   * the arms are the local character's own R15 arms (Anim/OwnArm: three parts a side, its skin, no sleeve colour)
--     when it has usable ones; else (R6, a part or rig attachment missing, a hidden part, no character) the design's
--     two arms of five parts (hand, thumb, forearm, cuff, sleeve); skin #F5CDA4; the sleeve is the duel side's team
--     colour, mint in practice and the lobby; a changed avatar rebuilds the arms within ownArms.recheckSeconds with
--     the hands staying put; the character is only read; the overlay camera's FOV is 70 and its light overlayLight();
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
--   * debugPose freezes the named poses and nil lets the overlay live again;
--   * final polish 2026-10-11, the Inspect showcases (Anim/InspectTracks; design: fp.js:111-194, 405-412): HandInspect
--     plays the held toy's showcase in the lobby look and the practice range when the toy rests in the hand (never in a
--     duel, during the pop-in or another showcase); each event fires once with its sound (the material ones at the
--     toy's pitch), its kick, its shake and its specks (parts in the overlay; ReducedMotion: half of them, no kick);
--     at dur the hold comes back without unwinding the turns; a squeeze, a throw windup or the toy leaving the hand
--     ends it; debugInspect freezes it at t with no event; the touch Inspect button is made on touch in the lobby look
--     and the range only;
--   * feature 1 (2026-10-11, the charge throw and the catch; design: the combat-effects page "Squishy Combat FP v2.html",
--     html:498-570): a running charge (ThrowController.localCharge, a stand-in here) puts the overlay in the charge
--     pose with the glow from c 0.2 and the orbit from 0.4 and narrows the world FOV; its end gives the hold back with
--     the effect parts hidden; the catch (CatchController.localCatch, a stand-in) opens the hands, then the crush shows
--     the caught toy's own copy and bursts it at burstAt (rings), and the hold comes back when the hands are free;
--   * phone speed fix (2026-10-16): on the low tier (a compact screen) the overlay steps every 2nd 60 Hz frame with
--     the time it skipped (the showcase's specks all come, on time); the world FOV still moves on every frame of a
--     squeeze focus, as on the high tier; the high tier steps every frame; a throw's release makes half the specks
--     there (batch B, owner 2026-10-17).

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
	local SKIN = Color3.fromRGB(234, 184, 146) -- the stand-in character's arms
	local BROWN = Color3.fromRGB(90, 60, 40)

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
		charge: { any }, -- feature 1: what ThrowController.localCharge returns (c, t, full)
		catch: { any }, -- feature 1: what CatchController.localCatch returns (phase, t, id, burstAt)
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
		preferred: Enum.PreferredInput, -- ControlsController.preferredInput()
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
			charge = { nil, nil, false },
			catch = { nil, nil, nil, nil },
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
			preferred = Enum.PreferredInput.KeyboardAndMouse,
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
				localCharge = function(): (number?, number?, boolean)
					return w.charge[1], w.charge[2], w.charge[3] == true
				end,
			},
			Catch = {
				localCatch = function(): (string?, number?, string?, number?)
					return w.catch[1], w.catch[2], w.catch[3], w.catch[4]
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
					return w.preferred
				end,
				-- An empty layout (no touch buttons): ControlsController.touchLayout always returns a table, and
				-- ViewmodelMath.touchPadRect iterates it.
				touchLayout = function(): any
					return {}
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
				scale = function(): number
					return 1
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

	-- A local character with usable R15 arms (test sizes, not Roblox's): a Humanoid (R15), the six arm MeshParts with
	-- their rig attachments (arms straight down), a Shirt and BodyColors.
	local function r15Character(): Model
		local model = Instance.new("Model")
		model.Name = "Tester"
		local humanoid = Instance.new("Humanoid")
		humanoid.RigType = Enum.HumanoidRigType.R15
		humanoid.Parent = model
		for _, side in { "Left", "Right" } do
			local function part(kind: string, size: Vector3): MeshPart
				local p = Instance.new("MeshPart")
				p.Name = side .. kind
				p.Size = size
				p.Color = SKIN
				p.Parent = model
				return p
			end
			local function rig(parent: Instance, name: string, y: number)
				local a = Instance.new("Attachment")
				a.Name = side .. name
				a.CFrame = CFrame.new(0, y, 0)
				a.Parent = parent
			end
			local hand = part("Hand", Vector3.new(1, 0.3, 1))
			local lower = part("LowerArm", Vector3.new(1, 1.05, 1))
			local upper = part("UpperArm", Vector3.new(1, 1.17, 1))
			rig(hand, "WristRigAttachment", 0.125)
			rig(lower, "WristRigAttachment", -0.5)
			rig(lower, "ElbowRigAttachment", 0.2)
			rig(upper, "ElbowRigAttachment", -0.33)
			rig(upper, "ShoulderRigAttachment", 0.42)
		end
		Instance.new("Shirt").Parent = model
		-- As on a real character, BodyColors holds the arms' colours (its defaults would repaint them).
		local colours = Instance.new("BodyColors")
		colours.LeftArmColor3, colours.RightArmColor3 = SKIN, SKIN
		colours.Parent = model
		return model
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

	t.test("no character: the design arms of five parts; sleeve by duel side, mint elsewhere; FOV 70", function()
		local w = setup()
		w.duel = { phase = "Active", phaseEndsAt = w.clock + 60, you = { side = "A" }, opponent = { side = "B" } }
		enter(w, "duel")
		local state = Viewmodel.debugState()
		expect.equal(state.arms, "design")
		expect.equal(state.armsWhy, "noCharacter")
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

	t.test("own arms: R15 arms, 3 parts a side, in the design's hold; the character only read", function()
		local w = setup()
		local character = r15Character()
		local count = #character:GetDescendants()
		local realHand = character:FindFirstChild("RightHand") :: BasePart
		local realFrame = realHand.CFrame
		local player: any = w.player
		player.Character = character
		enter(w, "lobby")
		frames(w, 120)
		local state = Viewmodel.debugState()
		expect.equal(state.arms, "own")
		expect.equal(state.armsWhy, nil)
		expect.deepEqual(state.leftParts, { "LeftHand", "LeftLowerArm", "LeftUpperArm" })
		expect.deepEqual(state.rightParts, { "RightHand", "RightLowerArm", "RightUpperArm" })
		expect.equal(state.skin, SKIN:ToHex())
		expect.equal(state.sleeve, nil)
		-- The design's motions: both hands at the toy's sides, the design's rolls.
		local left, right = ViewmodelMath.sides(state.toyPos, state.hw)
		expect.truthy(close(state.leftPos, left, 0.01) and close(state.rightPos, right, 0.01))
		expect.near(state.leftRoll, FP.arm.roll, 1e-3)
		expect.near(state.rightRoll, -FP.arm.roll, 1e-3)
		-- One model in the overlay with its Humanoid and the Shirt; the right hand's centre on the hand point.
		local viewport = w.guis.SD_Viewmodel:FindFirstChildOfClass("ViewportFrame") :: ViewportFrame
		local found = viewport:FindFirstChild("SD_OwnArms")
		expect.truthy(found ~= nil)
		local model = found :: Model
		expect.truthy(model:FindFirstChildOfClass("Humanoid") ~= nil)
		expect.truthy(model:FindFirstChildOfClass("Shirt") ~= nil)
		local hand = model:FindFirstChild("RightHand") :: BasePart
		expect.truthy((hand.Position - state.rightPos * FP.overlayStudsPerDu).Magnitude < 1e-3)
		-- The character is only read.
		expect.equal(#character:GetDescendants(), count)
		expect.equal(realHand.CFrame, realFrame)
		expect.equal(realHand.Parent, character)
		leave(w)
		expect.equal(overlayParts(w), 0)
		expect.equal(viewport:FindFirstChild("SD_OwnArms"), nil)
		teardown()
		character:Destroy()
	end)

	t.test("own arms: a changed avatar rebuilds them, hands staying put; R6 or a missing part: design arms", function()
		local w = setup()
		local character = r15Character()
		local player: any = w.player
		player.Character = character
		enter(w, "lobby")
		frames(w, 120)
		local before = Viewmodel.debugState()
		local check = math.ceil(FP.ownArms.recheckSeconds / FRAME) + 2
		local rightHand = character:FindFirstChild("RightHand") :: BasePart
		rightHand.Color = BROWN
		frames(w, check)
		local after = Viewmodel.debugState()
		expect.equal(after.arms, "own")
		expect.equal(after.skin, BROWN:ToHex())
		expect.truthy(close(after.rightPos, before.rightPos, 0.01))
		local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid
		humanoid.RigType = Enum.HumanoidRigType.R6
		frames(w, check)
		local design = Viewmodel.debugState()
		expect.equal(design.arms, "design")
		expect.equal(design.armsWhy, "notR15")
		expect.deepEqual(design.rightParts, PARTS)
		expect.equal(design.skin, FP.colours.skin:ToHex())
		expect.truthy(close(design.rightPos, before.rightPos, 0.01))
		-- Back to R15 with a hand missing: still the design arms, with the reason.
		humanoid.RigType = Enum.HumanoidRigType.R15
		rightHand:Destroy()
		frames(w, check)
		expect.equal(Viewmodel.debugState().armsWhy, "missing:RightHand")
		teardown()
		character:Destroy()
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

	-- Feature 1 (2026-10-11) -------------------------------------------------------------------------------------------

	local function shownParts(w: World, name: string): number
		local gui = w.guis.SD_Viewmodel
		local count = 0
		if gui then
			for _, d in gui:GetDescendants() do
				if d.Name == name and d:IsA("BasePart") and d.Transparency < 1 then
					count += 1
				end
			end
		end
		return count
	end

	t.test(
		"feature 1, the charge: the charge pose, its glow and orbit, the world FOV narrowed; then the hold",
		function()
			local w = setup()
			enter(w, "duel")
			frames(w, 60)
			local fovBefore = #w.fov
			w.charge = { 0.6, 0.6, false }
			frames(w, 30)
			local state = Viewmodel.debugState()
			expect.equal(state.kind, "charge")
			expect.near(state.charge, 0.6, 1e-9)
			expect.equal(shownParts(w, "ChargeGlow"), 1)
			expect.equal(shownParts(w, "ChargeOrbit"), FP.charge.orbitCount)
			expect.equal(shownParts(w, "ChargeOutline"), 0) -- only at full
			expect.truthy(#w.fov > fovBefore and w.fov[#w.fov] < 0) -- the world FOV narrows (design: html:463)
			w.charge = { 1, 1.2, true }
			frames(w, 5)
			expect.equal(shownParts(w, "ChargeOutline"), 1)
			w.charge = { nil, nil, false }
			frames(w, 30)
			state = Viewmodel.debugState()
			expect.truthy(state.kind ~= "charge")
			expect.equal(shownParts(w, "ChargeGlow"), 0)
			expect.equal(shownParts(w, "ChargeOrbit"), 0)
			expect.equal(shownParts(w, "ChargeOutline"), 0)
			teardown()
		end
	)

	t.test("feature 1, the catch: open hands, the caught toy crushed, its burst at burstAt, then the hold", function()
		local w = setup()
		enter(w, "duel")
		frames(w, 60)
		w.catch = { "open", 0.1, nil, nil }
		frames(w, 10)
		expect.equal(Viewmodel.debugState().kind, "catch")
		w.catch = { "crush", 0.05, w.squishyId, w.clock + 0.4 }
		frames(w, 6)
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "crush")
		expect.equal(state.caught, w.squishyId)
		expect.falsy(state.caughtBurst)
		frames(w, 30) -- past burstAt
		state = Viewmodel.debugState()
		expect.truthy(state.caughtBurst)
		expect.truthy(state.fxRings > 0) -- the burst's rings (design: html:559)
		w.catch = { "after", 1.3, w.squishyId, w.clock - 0.5 }
		frames(w, 5)
		expect.equal(Viewmodel.debugState().kind, "crush")
		w.catch = { nil, nil, nil, nil }
		frames(w, 60)
		state = Viewmodel.debugState()
		expect.truthy(state.kind ~= "crush" and state.kind ~= "catch")
		expect.equal(state.caught, nil)
		teardown()
	end)

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

	-- Spec phase 5: every ultimate's first-person wind-up runs over its own telegraph (the design's charge) with its
	-- glow in the design's colour: Dragon's orange, else the owning squishy's rarity colour (Art/RarityStyle).
	t.test("each ultimate's wind-up length and glow colour", function()
		local Config = t.requireShared("Config")
		local RarityStyle = t.requireShared("Art/RarityStyle")
		expect.equal(Viewmodel.ultTelegraphSeconds(nil), Config.Abilities.dragon_rush.telegraphSeconds)
		expect.equal(Viewmodel.ultTelegraphSeconds("flock_volley"), 0.35)
		expect.equal(Viewmodel.ultTelegraphSeconds("rain_check"), 0.6)
		expect.equal(Viewmodel.ultGlowColour(nil), Config.FirstPerson.ult.glowColour)
		expect.equal(Viewmodel.ultGlowColour("dragon_rush"), Config.FirstPerson.ult.glowColour)
		local epic = RarityStyle.get("Epic").color
		for _, id in { "flock_volley", "sprinkle_roller", "rain_check", "bubble_pop" } do
			expect.equal(Viewmodel.ultGlowColour(id), epic)
		end
	end)
	-- Final polish 2026-10-11: the 14 first-person Inspect showcases (design: fp.js:111-194, 405-412).
	local InspectTracks = t.requireClient("Anim/InspectTracks")

	-- HandInspect (R) as ControlsController would press it; whether the overlay took it.
	local function pressInspect(w: World): boolean
		local handler = w.handlers.HandInspect
		return handler ~= nil and handler(BEGIN, nil) == true
	end

	local function countOf(list: { string }, key: string): number
		local n = 0
		for _, item in list do
			if item == key then
				n += 1
			end
		end
		return n
	end

	t.test("HandInspect plays the held toy's showcase in the lobby look and the range, never in a duel", function()
		local w = setup("kitty_bread")
		enter(w, "duel")
		frames(w, 60)
		expect.falsy(pressInspect(w)) -- never in a duel
		expect.equal(Viewmodel.debugState().kind, "idle")
		leave(w)
		enter(w, "lobby")
		expect.falsy(pressInspect(w)) -- the pop-in is on
		frames(w, 60)
		expect.truthy(pressInspect(w))
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "inspect")
		expect.falsy(pressInspect(w)) -- one at a time
		-- Kitty Bread (fp.js:114-115): the ear flick at 0.68 s, the pat at 2.04 s.
		frames(w, 42) -- 0.7 s
		expect.equal(countOf(w.sounds, "sfx.inspect.flick"), 1)
		frames(w, 81) -- 2.05 s
		expect.equal(countOf(w.sounds, "sfx.squish"), 1)
		expect.near(w.soundOptions[#w.soundOptions].pitch, 1) -- the material sound at the toy's pitch
		state = Viewmodel.debugState()
		expect.equal(state.specks, 5) -- the pat's puffs (fp.js:174)
		expect.truthy(state.squash < 1) -- its kick (-2) on the squash spring
		frames(w, 40) -- past dur (2.5 s)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "idle")
		expect.falsy(state.inspecting)
		expect.truthy(math.abs(state.toyRot.Y - FP.held.rot.Y) < 0.05) -- the hold yaw, not 2π + 0.25
		expect.equal(countOf(w.sounds, "sfx.inspect.flick"), 1) -- each event once
		frames(w, 60)
		state = Viewmodel.debugState()
		expect.equal(state.specks, 0) -- the puffs are gone
		expect.equal(state.squash, 1)
		leave(w)
		enter(w, "practice")
		frames(w, 60)
		expect.truthy(pressInspect(w))
		teardown()
	end)

	t.test("a squeeze, a throw windup or the toy leaving the hand ends a showcase; turns not unwound", function()
		local w = setup("toast") -- the card flip: rx to 2π (fp.js:116)
		enter(w, "lobby")
		frames(w, 60)
		expect.truthy(pressInspect(w))
		frames(w, 66) -- 1.1 s: rx near 2π
		press(w, 0.5) -- a squeeze through the mirror
		frames(w, 1)
		local state = Viewmodel.debugState()
		expect.equal(state.kind, "idle")
		expect.falsy(state.inspecting)
		expect.truthy(math.abs(state.toyRot.X) <= math.pi + 0.1) -- wrapped: the flip is not wound back
		press(w, 0)
		frames(w, 120)
		leave(w)
		enter(w, "practice")
		frames(w, 60)
		expect.truthy(pressInspect(w))
		frames(w, 30)
		w.windup = { FRAME, 0.18, nil, nil, false } -- a throw: it takes over from where the hands are
		frames(w, 1)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "throw")
		expect.falsy(state.inspecting)
		w.windup = { FRAME, 0.18, nil, nil, true }
		frames(w, 120)
		expect.equal(Viewmodel.debugState().kind, "idle")
		expect.truthy(pressInspect(w))
		w.holding = false -- out of the hand
		frames(w, 1)
		state = Viewmodel.debugState()
		expect.equal(state.kind, "empty")
		expect.falsy(state.inspecting)
		teardown()
	end)

	t.test("debugInspect freezes a showcase at t for pictures (no event); nil lets it live again", function()
		local w = setup("kitty_bread")
		enter(w, "lobby")
		frames(w, 60)
		expect.truthy(Viewmodel.debugInspect(0.35))
		frames(w, 3)
		local state = Viewmodel.debugState()
		expect.deepEqual({ state.pose, state.kind, state.inspecting }, { "inspect", "inspect", true } :: { any })
		local track = InspectTracks.get("kitty_bread")
		local offset, rot = InspectTracks.toyAt(track, 0.35)
		expect.truthy(close(state.toyPos, FP.held.pos + offset, FP.idle.breath + 1e-4))
		expect.truthy(close(state.toyRot, rot, 1e-4))
		local sideL, sideR = ViewmodelMath.sides(state.toyPos, state.hw)
		expect.truthy(close(state.leftPos, sideL, 1e-4) and close(state.rightPos, sideR, 1e-4))
		expect.near(state.inspectTime, 0.35, 1e-9)
		expect.truthy(Viewmodel.debugInspect(2.05)) -- the pat: the right hand on the head (fp.js:115)
		frames(w, 2)
		state = Viewmodel.debugState()
		local _, sideR2 = ViewmodelMath.sides(state.toyPos, state.hw)
		expect.truthy(close(state.rightPos, sideR2 + Vector3.new(-0.07, 0.085, 0), 1e-4))
		expect.equal(countOf(w.sounds, "sfx.inspect.flick") + countOf(w.sounds, "sfx.squish"), 0) -- no event
		expect.equal(state.specks, 0)
		expect.truthy(Viewmodel.debugInspect(nil))
		frames(w, 120)
		state = Viewmodel.debugState()
		expect.equal(state.pose, nil)
		expect.equal(state.kind, "idle")
		teardown()
	end)

	t.test("the Dragon's roar: embers in the overlay and the shake; ReducedMotion: half the specks, no kick", function()
		local w = setup("dragon")
		enter(w, "lobby")
		frames(w, 60)
		expect.truthy(pressInspect(w))
		frames(w, 50) -- 0.83 s: the roar (fp.js:128-129, 182)
		local state = Viewmodel.debugState()
		expect.equal(countOf(w.sounds, "sfx.dragonRoar"), 1)
		expect.equal(state.specks, 14)
		expect.truthy(#w.shakes > 0) -- shake >= 0.25 (the camera shake setting is on)
		local parts = 0
		for _, d in w.guis.SD_Viewmodel:GetDescendants() do
			if d.Name == "InspectSpeck" and d:IsA("BasePart") then
				parts += 1
			end
		end
		expect.equal(parts, 14)
		frames(w, 40)
		expect.equal(Viewmodel.debugState().specks, 0) -- life 0.5 s
		teardown()
		local r = setup("bird")
		r.reduced = true
		enter(r, "lobby")
		frames(r, 60)
		expect.truthy(pressInspect(r))
		frames(r, 25) -- 0.42 s: the first flap (kick 3, 4 petals; fp.js:124, 180)
		state = Viewmodel.debugState()
		expect.equal(countOf(r.sounds, "sfx.inspect.flap"), 1)
		expect.equal(state.specks, 2) -- × Config.Vfx.reducedParticleMultiplier
		expect.equal(state.squash, 1) -- no kick
		teardown()
	end)

	t.test("the touch Inspect button: made on touch in the lobby look and the range, never in a duel", function()
		local w = setup("kitty_bread")
		w.preferred = Enum.PreferredInput.Touch
		local cases = {
			{ look = "lobby", wanted = true },
			{ look = "practice", wanted = true },
			{ look = "duel", wanted = false },
		}
		for _, case in cases do
			enter(w, case.look)
			frames(w, 3)
			local pad = w.guis.SD_ViewmodelPad
			local found = if pad then pad:FindFirstChild("Viewmodel_InspectButton") else nil
			expect.equal(found ~= nil, case.wanted)
			if found then
				local label = found:FindFirstChild("Label", true)
				-- UI FINAL R1: a secondary button shows its label in capitals (Q5).
				local shown = t.requireClient("UI/Components/Button").displayText("Inspect", "secondary")
				expect.truthy(label ~= nil and (label :: TextLabel).Text == shown)
			end
			leave(w)
			expect.equal(if pad then pad:FindFirstChild("Viewmodel_InspectButton") else nil, nil) -- gone with it
		end
		w.preferred = Enum.PreferredInput.KeyboardAndMouse
		enter(w, "lobby")
		frames(w, 3)
		local pad = w.guis.SD_ViewmodelPad
		expect.equal(if pad then pad:FindFirstChild("Viewmodel_InspectButton") else nil, nil) -- keys: R
		teardown()
	end)

	t.test("phone fix: the low tier steps every 2nd 60 Hz frame, with the skipped time; all the specks", function()
		local w = setup("dragon")
		w.camera.ViewportSize = Vector2.new(640, 360) -- a compact screen: MeshQuality "Low"
		enter(w, "lobby")
		expect.truthy(Viewmodel.debugState().lowTier)
		frames(w, 2) -- the first two frames step (the cap starts due)
		local before = Viewmodel.debugState().scale -- the pop-in's scale moves on every step
		frames(w, 1)
		expect.equal(Viewmodel.debugState().scale, before) -- skipped: nothing is written
		frames(w, 1)
		local after = Viewmodel.debugState().scale
		expect.truthy(after ~= before)
		-- The step got both frames: the pop-in's scale is the one two 60 Hz steps reach.
		expect.near(after, ViewmodelMath.backOut(4 * FRAME / FP.equip.seconds), 1e-6)
		frames(w, 60)
		expect.truthy(pressInspect(w))
		frames(w, 50) -- 0.83 s: the roar on time (fp.js:128-129, 182)
		expect.equal(countOf(w.sounds, "sfx.dragonRoar"), 1)
		expect.equal(Viewmodel.debugState().specks, 14) -- all 14 embers (a showcase keeps every speck, batch B)
		teardown()
		-- The high tier (a wide screen, keyboard and mouse) steps every frame.
		local h = setup("dragon")
		enter(h, "lobby")
		expect.falsy(Viewmodel.debugState().lowTier)
		frames(h, 2)
		local first = Viewmodel.debugState().scale
		frames(h, 1)
		expect.truthy(Viewmodel.debugState().scale ~= first)
		teardown()
	end)

	t.test("phone fix: on the low tier the world FOV still moves on every frame of a squeeze focus", function()
		-- The world FOV offsets of 20 frames of a squeeze, after 20 frames into it (the focus on its way to 64.5°).
		local function squeezeFov(viewport: Vector2): ({ number }, boolean)
			local w = setup()
			w.camera.ViewportSize = viewport
			enter(w, "lobby")
			local low = Viewmodel.debugState().lowTier
			frames(w, 60)
			for _ = 1, 20 do
				press(w, 0.5, 0.15)
				frames(w, 1)
			end
			table.clear(w.fov)
			for _ = 1, 20 do
				press(w, 0.5, 0.15)
				frames(w, 1)
			end
			local list = table.clone(w.fov)
			teardown()
			return list, low
		end
		local low, isLow = squeezeFov(Vector2.new(640, 360)) -- a compact screen: MeshQuality "Low"
		expect.truthy(isLow)
		-- One write a frame (the overlay steps only every 2nd one), each a new value: the zoom never moves in 30 Hz steps.
		expect.equal(#low, 20)
		for i = 2, #low do
			expect.truthy(low[i] < 0 and low[i] ~= low[i - 1])
		end
		-- The same zoom as the high tier's, within a small fraction of a degree.
		local high, isHigh = squeezeFov(Vector2.new(1920, 1080))
		expect.falsy(isHigh)
		expect.equal(#high, 20)
		expect.near(low[20], high[20], 0.25)
	end)

	-- Batch B (owner 2026-10-17: "throws make half the sparkles"): the release's specks on the low tier are
	-- lowTier.speckShare of the high tier's (each burst rounded as Anim/Specks does); the showcase case above keeps all 14.
	t.test("phone fix: on the low tier a throw's release makes half the sparkles; the high tier all of them", function()
		local function releaseSpecks(viewport: Vector2?): (number, boolean)
			local w = setup()
			if viewport then
				w.camera.ViewportSize = viewport
			end
			enter(w, "duel")
			frames(w, 60)
			throwOnce(w, 0.18, 0.1)
			frames(w, 2) -- the low tier steps every 2nd 60 Hz frame
			local state = Viewmodel.debugState()
			teardown()
			return state.specks, state.lowTier
		end
		local high, highTier = releaseSpecks(nil)
		local low, lowTier = releaseSpecks(Vector2.new(640, 360)) -- a compact screen: MeshQuality "Low"
		expect.falsy(highTier)
		expect.truthy(lowTier)
		expect.truthy(high >= 4)
		expect.truthy(low >= 1 and low < high)
		expect.truthy(low <= math.ceil(high * FP.lowTier.speckShare) + 1) -- two bursts, each rounded half up
	end)
end
