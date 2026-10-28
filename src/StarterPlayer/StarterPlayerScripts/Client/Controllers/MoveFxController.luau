--!strict
-- MoveFxController (client only; 2026-10-28, the physics upgrade's part 1, owner: "Yes, build it"). The own character's
-- movement feel from the co-owner's Claude Design page docs/squishy-fx-spec/move.html (numbers in Config.MoveFx), plus
-- the owner's 8 extras. Off when Config.MoveFx.enabled is false.
-- * Physics (the design's "New" feel, own character only: the client owns its body, so this replicates as is):
--   - while falling (vy < 0, in the air, not seated / climbing / swimming) a VectorForce pulls down with
--     (fallGravityMultiplier - 1) x the world gravity, so the rise and the 7.2-stud jump are untouched;
--   - the fall speed never passes maxFallSpeed;
--   - the jump cut: letting go of jump while still rising, at least jumpCutMinHold after the take-off, keeps
--     jumpCutKeep of the upward speed (a short hop). "Held" = a JumpRequest within the double jump's pressGapSeconds
--     (a held input repeats it every frame), Space, ButtonA or the touch jump button down. Only the ground jump: the
--     double jump keeps its height.
-- * The design's moments on the own character (Anim/FeelFx): run (a run starts after standing: the lean, the kick
--   puff; a step puff every run.strideStuds, alternating feet; runSettle when it stops), takeoff (jumpRise, the puff;
--   apex -> jumpFall), fall (walking off a ledge: fallFlail; falling faster than fastFallFrom: the wind and, in first
--   person, the screen lines), landing (soft / normal / hard by the landing speed: puffs, rings, the pose, the dip, the
--   hard shake, BOING!). The dash, the double jump and the slide play their own moments (DashController,
--   DoubleJumpController, LobbyMoveController) through actorFor().
-- * Extras (NOT IN DESIGN, Config.MoveFx.extras): 1 the held squishy's colour on tinted stars, rings and sparkles
--   (Catalog visuals.accent); 2 dust puffs tinted by the floor; 3 the hop chain (bigger landing puffs and a rising boing);
--   4 the mega landing after a big drop (SUPER BOING!, confetti, a bigger ring); 5 the flip variety (DoubleJumpController
--   picks it); 6 lobby footprints; 7 phone buzz (HapticEffect); 8 every movement sound a little higher or lower.
-- * Part 2 (getting hit): knock(seconds) while HitFxController's knockback flies and skids: no take-off, fall flail or
--   landing moment and no run (the hit plays its own), and a jump cut armed before the hit is dropped.
-- API: actorFor(player, character, root, extra?) -> FeelFx.Actor, floorColor(root), squishyTint(player), buzz(kind),
--   suppress(seconds), knock(seconds), noteDoubleJump(), heldNow() / landTier(speed) / chainScale(n) (pure parts
--   unit-tested), debugState(); init(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local MOVE_FX = require(Shared.Config.MoveFx)

local Client = script.Parent.Parent
local FeelFx = require(Client.Anim.FeelFx)
local Scheduler = require(Client.Anim.Scheduler)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local MoveFeelController = require(script.Parent.MoveFeelController)
local SoundController = require(script.Parent.SoundController)

-- Constants

local FEEL = MOVE_FX.feel
local MOMENTS = MOVE_FX.moments
local EXTRAS = MOVE_FX.extras
local RUN = MOVE_FX.run
local AIR = MOVE_FX.air
local PRESS_GAP = Config.Duel.Rules.DoubleJump.pressGapSeconds
local CREAM = Color3.fromHex("#FFF4E6") -- the design's puff colour
local FORCE_NAME = "SD_FallGravity"
local FOOTPRINT_LIFT = 0.03
local NO_FALL_STATES: { [Enum.HumanoidStateType]: boolean } = {
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Dead] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
}

-- Only the fall events of Moments.fall (the wind after a jump, which has no flail).
local WIND_EVENTS = {}
for _, ev in MOMENTS.fall do
	if ev.on ~= nil then
		table.insert(WIND_EVENTS, ev)
	end
end
-- The landing without its BOING! text: a mega landing says SUPER BOING! instead (never both on top of each other).
local LANDING_NO_POP = {}
for _, ev in MOMENTS.landing do
	if ev.pop == nil then
		table.insert(LANDING_NO_POP, ev)
	end
end

-- Module table

local MoveFxController = {}

-- Private state

local log = Log.new("MoveFx")
local cleanup: Cleanup.Cleanup? = nil
local force: VectorForce? = nil
local lastJumpRequest = -math.huge
local touchJumpHeld = false
local suppressUntil = 0
local knockedUntil = 0

-- The own character's air / run state.
local state = {
	grounded = true,
	airSince = 0,
	jumped = false, -- this air time began with a jump
	cutArmed = false,
	takeoffAt = 0,
	lastVy = 0,
	rising = false,
	maxY = 0,
	fastSent = false,
	fallSent = false,
	lastLandAt = -math.huge,
	chain = 0,
	running = false,
	standSince = 0,
	strideLeft = RUN.strideStuds,
	nextFoot = "Right",
	lastPos = nil :: Vector3?,
	takeoffRun = nil :: any,
	fallRun = nil :: any,
	runRun = nil :: any,
	actor = nil :: FeelFx.Actor?,
}
local footprints: { BasePart } = {}
local haptics: { [string]: Instance } = {}
local stats = { takeoffs = 0, landings = 0, cuts = 0, megas = 0, steps = 0 }

-- Pure -------------------------------------------------------------------------------------------------------------------

-- The design's landing tier for a landing speed (studs/s, positive down).
function MoveFxController.landTier(speed: number): string
	if speed < FEEL.landSoftBelow then
		return "landSoft"
	elseif speed >= FEEL.landHardFrom then
		return "landHard"
	end
	return "landNormal"
end

-- Extra 3: the landing puffs' count multiplier for a chain of n hops (0 = no chain).
function MoveFxController.chainScale(n: number): number
	return 1 + EXTRAS.chainCount * math.clamp(n, 0, EXTRAS.chainMax)
end

-- True while any jump input is held (see the header).
function MoveFxController.heldNow(now: number, lastRequest: number, keyDown: boolean, buttonDown: boolean, touch: boolean): boolean
	return now - lastRequest < PRESS_GAP or keyDown or buttonDown or touch
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function localCharacter(): (Model?, Humanoid?, BasePart?)
	local character = Players.LocalPlayer.Character
	if character == nil then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, root
end

local function downParams(): RaycastParams
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local fx = Workspace:FindFirstChild("SD_ClientFx")
	if fx then
		table.insert(ignore, fx)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	return params
end

-- Extra 2: the design's cream, tinted floorShare toward the floor under `root` (nil when nothing is under it).
function MoveFxController.floorColor(root: BasePart): Color3?
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -8, 0), downParams())
	if hit == nil then
		return nil
	end
	local color: Color3
	if hit.Instance:IsA("Terrain") then
		local ok, c = pcall(function()
			return Workspace.Terrain:GetMaterialColor(hit.Material)
		end)
		if not ok then
			return nil
		end
		color = c
	elseif hit.Instance:IsA("BasePart") then
		color = hit.Instance.Color
	else
		return nil
	end
	return CREAM:Lerp(color, EXTRAS.floorShare)
end

-- Extra 1: the held squishy's accent colour, or nil.
function MoveFxController.squishyTint(player: Player): Color3?
	if not EXTRAS.squishyColour then
		return nil
	end
	local id = HeldSquishyController.getSquishyId(player)
	local def: any = if id then Catalog.get(id) else nil
	local accent = def and def.visuals and def.visuals.accent
	if type(accent) == "string" then
		local ok, c = pcall(Color3.fromHex, accent)
		if ok then
			return c
		end
	end
	return nil
end

-- A FeelFx actor for any character: own or not (other players: fewer particles, the other-player sound priority).
function MoveFxController.actorFor(
	player: Player,
	character: Model,
	root: BasePart,
	extra: { [string]: any }?
): FeelFx.Actor
	local own = player == Players.LocalPlayer
	local actor: any = {
		character = character,
		root = root,
		player = player,
		own = own,
		low = not own,
		priority = if own then 0 else -1,
		tint = MoveFxController.squishyTint(player),
		floor = MoveFxController.floorColor(root),
	}
	for k, v in extra or {} do
		actor[k] = v
	end
	return actor
end

-- Extra 7: a short buzz on phones and gamepads (HapticEffect; nothing where the device has none).
function MoveFxController.buzz(kind: string)
	local typeName = EXTRAS.haptics[kind]
	if typeName == nil then
		return
	end
	local input = UserInputService.PreferredInput
	if input ~= Enum.PreferredInput.Touch and input ~= Enum.PreferredInput.Gamepad then
		return
	end
	local effect = haptics[typeName]
	if effect == nil then
		local ok, made = pcall(function()
			local h = Instance.new("HapticEffect")
			h.Type = (Enum.HapticEffectType :: any)[typeName]
			h.Parent = Workspace
			return h
		end)
		if not ok then
			return
		end
		effect = made
		haptics[typeName] = made
	end
	pcall(function()
		(effect :: any):Play()
	end)
end

-- Dash and slide: no run start, steps or stop while it lasts (their own moment plays).
function MoveFxController.suppress(seconds: number)
	suppressUntil = math.max(suppressUntil, os.clock() + seconds)
end

-- A knockback (HitFxController): no take-off, fall or landing moment and no run while it lasts; never cut.
function MoveFxController.knock(seconds: number)
	knockedUntil = math.max(knockedUntil, os.clock() + seconds)
	suppressUntil = math.max(suppressUntil, knockedUntil)
	state.cutArmed = false
end

-- The own double jump: the ground jump's cut is over.
function MoveFxController.noteDoubleJump()
	state.cutArmed = false
	state.rising = true
	MoveFxController.buzz("doubleJump")
end

local function playSound(name: string, at: Instance | Vector3, priority: number, pitch: number, sounds: any?)
	local map = (sounds or MOVE_FX.sounds)[name]
	if not map then
		return
	end
	local ok, err = pcall(SoundController.play, map.key, {
		at = at :: any,
		priority = priority,
		volume = map.volume,
		pitch = (map.pitch or 1) * pitch,
		variance = EXTRAS.soundVariance,
	})
	if not ok then
		log:warn("sound failed:", err)
	end
end

local function ensureForce(root: BasePart): VectorForce
	local current = force
	if current and current.Parent == root then
		return current
	end
	local attachment = root:FindFirstChild(FORCE_NAME)
	if attachment == nil or not attachment:IsA("Attachment") then
		local made = Instance.new("Attachment")
		made.Name = FORCE_NAME
		made.Parent = root
		attachment = made
	end
	local vf = Instance.new("VectorForce")
	vf.Name = FORCE_NAME
	vf.Attachment0 = attachment :: Attachment
	vf.RelativeTo = Enum.ActuatorRelativeTo.World
	vf.ApplyAtCenterOfMass = true
	vf.Force = Vector3.zero
	vf.Enabled = false
	vf.Parent = root
	force = vf
	return vf
end

local function jumpHeld(now: number): boolean
	return MoveFxController.heldNow(
		now,
		lastJumpRequest,
		UserInputService:IsKeyDown(Enum.KeyCode.Space),
		UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA),
		touchJumpHeld
	)
end

-- PreSimulation: the extra fall gravity, the fall cap and the jump cut.
local function stepPhysics()
	if not MOVE_FX.enabled then
		return
	end
	local _, humanoid, root = localCharacter()
	if humanoid == nil or root == nil then
		return
	end
	local vf = ensureForce(root)
	local v = root.AssemblyLinearVelocity
	local airborne = humanoid.FloorMaterial == Enum.Material.Air
	local falling = airborne and v.Y < 0 and not NO_FALL_STATES[humanoid:GetState()] and not root.Anchored
	vf.Enabled = falling
	if falling then
		vf.Force = Vector3.new(0, -root.AssemblyMass * Workspace.Gravity * (FEEL.fallGravityMultiplier - 1), 0)
		if v.Y < -FEEL.maxFallSpeed then
			root.AssemblyLinearVelocity = Vector3.new(v.X, -FEEL.maxFallSpeed, v.Z)
		end
	end
	-- The cut reads the speed, not the floor: the Humanoid still reports its floor for a few frames after the take-off.
	if state.cutArmed then
		local now = os.clock()
		local since = now - state.takeoffAt
		if v.Y > 0 and since >= FEEL.jumpCutMinHold and not jumpHeld(now) then
			state.cutArmed = false
			stats.cuts += 1
			root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y * FEEL.jumpCutKeep, v.Z)
		elseif v.Y <= 0 and since > FEEL.jumpCutMinHold then
			state.cutArmed = false -- past the apex (or it never left the ground)
		end
	end
end

local footprintTexture: string? = nil
local function placeFootprint(character: Model, foot: string)
	if not ControlsController.isContextActive("Lobby") or ControlsController.isContextActive("Practice") then
		return
	end
	if footprintTexture == nil then
		footprintTexture = AssetTable.image("img.kit.footprint") or ""
	end
	if footprintTexture == "" then
		return
	end
	local part = character:FindFirstChild(foot .. "Foot")
	if part == nil or not part:IsA("BasePart") then
		return
	end
	local hit = Workspace:Raycast(part.Position, Vector3.new(0, -3, 0), downParams())
	if hit == nil then
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local look = if root then root.CFrame.LookVector else Vector3.new(0, 0, -1)
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local mark = Instance.new("Part")
	mark.Name = "Footprint"
	mark.Anchored = true
	mark.CanCollide = false
	mark.CanQuery = false
	mark.CanTouch = false
	mark.CastShadow = false
	mark.Transparency = 1
	mark.Size = EXTRAS.footprintSize
	local at = hit.Position + hit.Normal * FOOTPRINT_LIFT
	mark.CFrame = CFrame.lookAt(at, at + flat.Unit)
	local decal = Instance.new("Decal")
	decal.Texture = footprintTexture
	decal.Face = Enum.NormalId.Top
	decal.Color3 = EXTRAS.footprintColor
	decal.Transparency = EXTRAS.footprintTransparency
	decal.Parent = mark
	local fx = Workspace:FindFirstChild("SD_ClientFx")
	mark.Parent = fx or Workspace
	table.insert(footprints, mark)
	while #footprints > EXTRAS.footprintMax do
		table.remove(footprints, 1):Destroy()
	end
	local start = os.clock()
	local from = EXTRAS.footprintTransparency
	task.spawn(function()
		while mark.Parent do
			local u = (os.clock() - start) / EXTRAS.footprintSeconds
			if u >= 1 then
				break
			end
			decal.Transparency = from + (1 - from) * u * u
			task.wait()
		end
		local index = table.find(footprints, mark)
		if index then
			table.remove(footprints, index)
		end
		mark:Destroy()
	end)
end

local function freshActor(character: Model, root: BasePart, extra: { [string]: any }?): FeelFx.Actor
	local actor = MoveFxController.actorFor(Players.LocalPlayer, character, root, extra)
	state.actor = actor
	return actor
end

local function takeoff(character: Model, root: BasePart)
	local now = os.clock()
	stats.takeoffs += 1
	state.jumped = true -- the cut itself is armed by the Jumping state only (onJumping): a launch is never cut
	state.rising = true
	if now - state.lastLandAt <= EXTRAS.chainSeconds then
		state.chain = math.min(state.chain + 1, EXTRAS.chainMax)
	else
		state.chain = 0
	end
	state.takeoffRun = FeelFx.play(MOMENTS.takeoff, freshActor(character, root))
end

local function landing(character: Model, root: BasePart, speed: number)
	local now = os.clock()
	local airSeconds = now - state.airSince
	local fallRun = state.fallRun
	if fallRun then
		fallRun:signal("land")
		state.fallRun = nil
	end
	local current = FeelFx.currentPose(character)
	local poses = MOVE_FX.poses
	local airPose = current == poses.jumpRise or current == poses.jumpFall or current == poses.fallFlail
	if speed < AIR.minLandSpeed and not state.jumped then
		if airPose then
			FeelFx.clearPose(character)
		end
		return -- a step down, not a landing
	end
	stats.landings += 1
	state.lastLandAt = now
	local tier = MoveFxController.landTier(speed)
	local mega = tier == "landHard" and state.maxY - root.Position.Y >= EXTRAS.megaDrop
	-- The chain's bigger puffs never ride on a mega landing (the design's 60 particles an effect).
	local chain = if state.jumped and not mega then state.chain else 0
	local actor = freshActor(character, root, { scale = MoveFxController.chainScale(chain) })
	FeelFx.play(if mega then LANDING_NO_POP else MOMENTS.landing, actor):signal(tier)
	if chain >= 1 then
		playSound("chain_boing", root, 0, 1 + EXTRAS.chainPitch * chain)
	end
	if mega then
		stats.megas += 1
		FeelFx.play(MOMENTS.mega, actor)
		MoveFxController.buzz("mega")
	elseif tier == "landHard" then
		MoveFxController.buzz("landHard")
	end
	if airSeconds > 0 and state.running then
		state.strideLeft = RUN.strideStuds * 0.5 -- the run's next step comes soon after the landing
	end
end

-- Render: the air / run state machine and the moments.
local function stepRender(_dt: number, _now: number): boolean
	if not MOVE_FX.enabled then
		return true
	end
	local character, humanoid, root = localCharacter()
	if character == nil or humanoid == nil or root == nil then
		state.grounded = true
		state.running = false
		return true
	end
	local now = os.clock()
	local v = root.AssemblyLinearVelocity
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local busy = now < suppressUntil
	local knocked = now < knockedUntil
	if state.grounded and not grounded then
		-- Left the ground.
		state.grounded = false
		state.airSince = now
		state.maxY = root.Position.Y
		state.fastSent = false
		state.fallSent = false
		state.jumped = knocked -- a knockback is no walk off a ledge either (no fall flail)
		state.rising = v.Y > 0
		if not knocked and (humanoid:GetState() == Enum.HumanoidStateType.Jumping or v.Y > 10) then
			takeoff(character, root)
		end
	elseif not state.grounded and grounded then
		state.grounded = true
		if not knocked then
			landing(character, root, math.max(-state.lastVy, 0))
		end
	end
	if not grounded then
		state.maxY = math.max(state.maxY, root.Position.Y)
		if state.rising and v.Y <= 0 then
			state.rising = false
			local run = state.takeoffRun
			if run then
				run:signal("apex")
			end
		end
		if not state.jumped and not state.fallSent and v.Y < 0 and now - state.airSince >= AIR.fallAfterSeconds then
			state.fallSent = true
			state.fallRun = FeelFx.play(MOMENTS.fall, freshActor(character, root))
		end
		if not state.fastSent and -v.Y >= FEEL.fastFallFrom then
			state.fastSent = true
			local run = state.fallRun
			if run == nil then
				run = FeelFx.play(WIND_EVENTS, freshActor(character, root))
				state.fallRun = run
			end
			run:signal("fastFall")
		end
		state.lastVy = v.Y
	else
		state.lastVy = 0
	end
	-- The run: starts after standing, steps every strideStuds on the ground, settles when it stops.
	local flat = Vector3.new(v.X, 0, v.Z).Magnitude
	local walk = math.max(humanoid.WalkSpeed, 8)
	local pos = root.Position
	local last = state.lastPos
	state.lastPos = pos
	if busy then
		state.standSince = now
		return true
	end
	if grounded and flat < walk * RUN.stopBelowShare then
		if state.running then
			state.running = false
			local run = state.runRun
			if run and FeelFx.currentPose(character) == MOVE_FX.poses.runLean then
				run:signal("stop")
			end
		end
		state.standSince = if state.standSince > 0 then state.standSince else now
	elseif grounded and not state.running and flat >= walk * RUN.runFromShare then
		local stood = state.standSince > 0 and now - state.standSince >= RUN.standSeconds
		state.running = true
		state.standSince = 0
		state.strideLeft = RUN.strideStuds
		if stood then
			state.runRun = FeelFx.play(MOMENTS.run, freshActor(character, root, { dir = Vector3.new(v.X, 0, v.Z) }))
		end
	elseif not grounded then
		state.standSince = 0
	end
	if state.running and grounded and last then
		state.strideLeft -= Vector3.new(pos.X - last.X, 0, pos.Z - last.Z).Magnitude
		if state.strideLeft <= 0 then
			state.strideLeft += RUN.strideStuds
			local foot = state.nextFoot
			state.nextFoot = if foot == "Right" then "Left" else "Right"
			stats.steps += 1
			local run = state.runRun
			if run and not run.stopped then
				local actor = run.actor
				actor.foot = foot
				actor.floor = MoveFxController.floorColor(root)
				run:signal("step")
			end
			placeFootprint(character, foot)
		end
	end
	return true
end

-- The jump cut starts at the Humanoid's Jumping state (the floor reading lags a few frames behind it).
local stateConnection: RBXScriptConnection? = nil
local function bindHumanoid(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid == nil or not humanoid:IsA("Humanoid") or character ~= Players.LocalPlayer.Character then
		return
	end
	if stateConnection then
		stateConnection:Disconnect()
	end
	stateConnection = humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Jumping and MOVE_FX.enabled then
			state.cutArmed = true
			state.takeoffAt = os.clock()
		end
	end)
end

local function hookTouchJump(c: Cleanup.Cleanup)
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
	if playerGui == nil then
		return
	end
	local function bind(button: Instance)
		if not button:IsA("GuiObject") then
			return
		end
		c:add(button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				touchJumpHeld = true
			end
		end))
		c:add(button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.Touch then
				touchJumpHeld = false
			end
		end))
	end
	local function watch(gui: Instance)
		if gui.Name ~= "TouchGui" then
			return
		end
		task.spawn(function()
			local frame = gui:WaitForChild("TouchControlFrame", 10)
			local button = frame and frame:WaitForChild("JumpButton", 10)
			if button then
				bind(button)
			end
		end)
	end
	for _, gui in playerGui:GetChildren() do
		watch(gui)
	end
	c:add(playerGui.ChildAdded:Connect(watch))
end

-- Public -------------------------------------------------------------------------------------------------------------------

function MoveFxController.debugState(): { [string]: any }
	return {
		enabled = MOVE_FX.enabled,
		grounded = state.grounded,
		knocked = os.clock() < knockedUntil,
		running = state.running,
		chain = state.chain,
		cutArmed = state.cutArmed,
		forceOn = force ~= nil and force.Enabled,
		stats = table.clone(stats),
		feel = FeelFx.counts(),
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------------

function MoveFxController.init()
	local c = Cleanup.new()
	cleanup = c
	FeelFx.setHooks({
		camera = {
			dip = MoveFeelController.dip,
			shake = MoveFeelController.shake,
			fov = MoveFeelController.fovKick,
			punch = MoveFeelController.punch,
		},
		sound = playSound,
		layerFor = CharacterAnimController.getLayer,
		holding = HeldSquishyController.isHolding,
		firstPerson = MoveFeelController.isFirstPerson,
	})
	c:add(UserInputService.JumpRequest:Connect(function()
		lastJumpRequest = os.clock()
	end))
	c:add(RunService.PreSimulation:Connect(function()
		local ok, err = pcall(stepPhysics)
		if not ok then
			log:warn("physics step failed:", err)
		end
	end))
	c:add(Scheduler.add(function(dt: number, now: number): boolean
		local ok, err = pcall(stepRender, dt, now)
		if not ok then
			log:warn("step failed:", err)
		end
		return true
	end, "render"))
	c:add(Players.LocalPlayer.CharacterAdded:Connect(function(character: Model)
		force = nil
		state.grounded = true
		state.running = false
		state.cutArmed = false
		state.takeoffRun, state.fallRun, state.runRun = nil, nil, nil
		task.spawn(bindHumanoid, character)
	end))
	local current = Players.LocalPlayer.Character
	if current then
		task.spawn(bindHumanoid, current)
	end
	task.spawn(hookTouchJump, c)
	c:add(function()
		local connection = stateConnection
		stateConnection = nil
		if connection then
			connection:Disconnect()
		end
		local vf = force
		force = nil
		if vf then
			vf:Destroy()
		end
		for _, p in footprints do
			p:Destroy()
		end
		table.clear(footprints)
		for _, h in haptics do
			h:Destroy()
		end
		table.clear(haptics)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function MoveFxController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return MoveFxController
