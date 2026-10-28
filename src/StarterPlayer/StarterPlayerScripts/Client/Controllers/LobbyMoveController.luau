--!strict
-- LobbyMoveController (client only; 2026-10-17, VillasmilGaming: "change the movement a little bit in the lobby", the
-- lobby reference video: power slides). Numbers in Config.LobbyMove.Slide; the lobby run's speed is the server's
-- (LobbyMoveService).
-- * Input: LobbySlide (ControlsController: C, Left Ctrl, ButtonB in the Lobby context). A press slides when gate() lets
--   it (pure): the Lobby context live and the Practice one off (in the throw box C and ButtonB are PracticeDash: the
--   press passes), not in a duel or a match (SD_MatchId / SD_DuelPhase empty), alive, on the ground, running (a
--   horizontal speed of at least minSpeedShare x the walk speed), not sliding, cooldownSeconds since the last one.
-- * The move (the slider's own client moves its HumanoidRootPart, so it replicates as is): a LinearVelocity (Plane,
--   world X and Z) along the run at speedAt(t) (startSpeed easing out to endSpeed over `seconds`), turning toward the
--   move direction at steerPerSecond, pushing with at most maxAccel x the assembly's mass; the Humanoid's HipHeight
--   drops by hipDrop (never below minHipHeight) so the body sits low. A jump ends it at once (the run takes the speed
--   it has), and so does running into something (the body under half its slide speed for blockedSeconds) or
--   leaving the lobby. The HipHeight comes back at the end.
-- * SlideRequest(clientTime) tells the server (LobbyMoveService), which stamps the character's SD_SlideAt (server
--   time): every client plays the pose, the dust and the sound of a character whose SD_SlideAt changes (its own slide
--   already plays from the press).
-- * The pose (R15): Config.LobbyMove.Slide.pose as the "lobbySlide" override layer at Slide.priority, blended in over
--   blendInSeconds and out over blendOutSeconds (poseWeight, pure).
-- * Effects: the dash's skid (MoveVfx Dash/Skid on the floor under the HRP, in Sky) and sfx.dashWhoosh at Slide.pitch;
--   another player's at the other-player priority (-1) with fewer particles.
-- * Physics upgrade (2026-10-28, Config.MoveFx.enabled): instead of the pose, the skid, the sound and the HipHeight
--   drop, the design's slide moment (Anim/FeelFx, Config.MoveFx.moments.slide) through MoveFxController.actorFor;
--   "slideEnd" when the slide ends (an early end also stops its held dust, sprinkles and streak).
-- * Touch (phones and tablets, 2026-10-17): a round Slide button (its own ScreenGui SD_SlideTouch, safe insets, with the
--   duel's SD_Touch order) shows while touchShown() (pure): touch input, the Lobby context on, not the throw box, not in
--   a duel or a match, no screen blocking the controls, alive. touchRect() (pure) puts it left of Roblox's jump button,
--   bottoms aligned, Config.UI.Touch.gap apart, Touch.dashButton x the UI scale (at least the touch floor): inside the
--   duel Throw button's box, which the lobby HUD already keeps clear on narrow layouts. A press slides as C does (the
--   same gate). Its shade (touchProgress, pure): clear when a slide would start, clearing from the bottom while the
--   cooldown runs, shaded while standing or in the air. Studio: Workspace attribute SD_PhonePreview (the phone HUD
--   preview) shows it with the mouse too.
-- API: gate(facts), speedAt(t), poseWeight(t, length), touchShown(facts), touchRect(screen, uiScale, jump),
--   touchProgress(now, lastSlideAt, canSlide) (pure, unit-tested); isSliding(), counts(); init(), start(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local FeelFx = require(Client.Anim.FeelFx)
local MoveVfx = require(Client.Anim.MoveVfx)
local Scheduler = require(Client.Anim.Scheduler)
local Theme = require(Client.UI.Theme)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local MoveFxController = require(script.Parent.MoveFxController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)

-- Types

export type GateFacts = {
	lobby: boolean, -- the Lobby context is live
	practice: boolean, -- the Practice context is live (the throw box)
	inMatch: boolean, -- SD_MatchId or SD_DuelPhase set
	alive: boolean,
	grounded: boolean,
	speed: number, -- horizontal, studs/s
	walkSpeed: number,
	sliding: boolean,
	now: number, -- os.clock()
	lastSlideAt: number, -- os.clock()
}

export type TouchFacts = {
	touch: boolean, -- touch is the input (or the Studio phone preview)
	lobby: boolean,
	practice: boolean,
	inMatch: boolean,
	blocked: boolean, -- a screen blocks the controls (ControlsController.isBlocked)
	alive: boolean,
}

export type Rect = { x: number, y: number, w: number, h: number }

type TouchView = {
	gui: ScreenGui,
	button: TextButton,
	gradient: UIGradient,
	label: TextLabel,
	progress: number,
}

type Slide = {
	player: Player,
	character: Model,
	root: BasePart,
	own: boolean,
	startClock: number,
	length: number, -- seconds it lasts (an own slide that ends early shortens it)
	dir: Vector3,
	skid: MoveVfx.Handle?,
	feel: any, -- the physics upgrade's slide moment (Anim/FeelFx run), when Config.MoveFx.enabled
	ended: boolean,
	-- own only
	mover: LinearVelocity?,
	attachment: Attachment?,
	humanoid: Humanoid?,
	hipFrom: number?,
	hipSet: number?,
	slowFor: number,
	jumpConnection: RBXScriptConnection?,
}

-- Constants

local SLIDE = Config.LobbyMove.Slide
-- 2026-10-28 physics upgrade (docs/squishy-fx-spec/move.html "Power slide"): the design's slide moment (pose, dust,
-- sprinkles, the floor streak, the own camera drop, FOV and rumble) replaces the skid, the pose and the HipHeight drop
-- (the design lowers the body with the pose's Root) when Config.MoveFx.enabled.
local MOVE_FX = require(ReplicatedStorage.Shared.Config.MoveFx)
local ACTION = "LobbySlide"
local REMOTE_REQUEST = "SlideRequest"
local ATTR_SLIDE_AT = "SD_SlideAt"
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local LAYER = "lobbySlide"
local RIG_R15 = "R15"
local MOVER_NAME = "SD_SlideMover"
local VFX_SKID = "Dash/Skid"
local SOUND_WHOOSH = "sfx.dashWhoosh"
local OTHER_PRIORITY = -1
local FLOOR_PROBE = 8 -- studs down from the HRP to look for the floor under a slide
local FLOOR_LIFT = 0.1
local MIN_STEP = 1 / 240
local TOUCH = Config.UI.Touch
local TOUCH_GUI_NAME = "SD_SlideTouch"
local TOUCH_DISPLAY_ORDER = 12 -- with SD_Touch (the duel's round buttons, never shown in the lobby)
local TOUCH_ACCENT = "sky" -- as the duel's Dash
local TOUCH_SHADE_TRANSPARENCY = 0.45 -- the shaded part (ControlsController's touch buttons' look)
local PHONE_PREVIEW = "SD_PhonePreview" -- Studio: UIController's phone HUD preview

-- Module table

local LobbyMoveController = {}

-- Private state

local log = Log.new("LobbyMove")
local cleanup: Cleanup.Cleanup? = nil
local slides: { [Player]: Slide } = {}
local seen: { [Player]: number } = {} -- the last SD_SlideAt seen on each player's character
local lastSlideAt = -math.huge
local stats = { sent = 0, refused = 0, remote = 0 }
local touchView: TouchView? = nil

-- Pure ---------------------------------------------------------------------------------------------------------------

-- The reason a press does not slide, or nil when it slides.
function LobbyMoveController.gate(facts: GateFacts): string?
	if not facts.lobby or facts.practice or facts.inMatch then
		return "context"
	end
	if not facts.alive then
		return "dead"
	end
	if facts.sliding then
		return "busy"
	end
	if not facts.grounded then
		return "airborne"
	end
	if facts.speed < SLIDE.minSpeedShare * math.max(facts.walkSpeed, 1) then
		return "slow"
	end
	if facts.now < facts.lastSlideAt + SLIDE.cooldownSeconds then
		return "cooldown"
	end
	return nil
end

-- The slide's speed (studs/s) t seconds in: startSpeed easing out (quadratic) to endSpeed at `seconds`.
function LobbyMoveController.speedAt(t: number): number
	local u = math.clamp(if t == t then t / SLIDE.seconds else 1, 0, 1)
	local eased = 1 - (1 - u) * (1 - u)
	return SLIDE.startSpeed + (SLIDE.endSpeed - SLIDE.startSpeed) * eased
end

-- The pose's weight t seconds into a slide that lasts `length` seconds.
function LobbyMoveController.poseWeight(t: number, length: number): number
	if not (t == t and t >= 0) or t >= length then
		return 0
	end
	local into = math.clamp(t / SLIDE.blendInSeconds, 0, 1)
	local out = math.clamp((length - t) / SLIDE.blendOutSeconds, 0, 1)
	return math.min(into, out)
end

-- Whether the touch Slide button shows (see the header).
function LobbyMoveController.touchShown(facts: TouchFacts): boolean
	return facts.touch
		and facts.lobby
		and not facts.practice
		and not facts.inMatch
		and not facts.blocked
		and facts.alive
end

-- The touch Slide button's box in `screen` px (the safe-inset space) at `uiScale`, beside the jump button `jump` (nil:
-- Roblox's default spot, as ControlsController.touchLayout).
function LobbyMoveController.touchRect(screen: Vector2, uiScale: number, jump: Rect?): Rect
	local j = ControlsController.touchLayout(screen, uiScale, jump :: any).jump
	local size = math.max(TOUCH.dashButton * uiScale, TOUCH.minTargetFloor)
	local x = math.clamp(j.x - TOUCH.gap - size, 0, math.max(screen.X - size, 0))
	local y = math.clamp(j.y + j.h - size, 0, math.max(screen.Y - size, 0))
	return { x = x, y = y, w = size, h = size }
end

-- The button's clear share: the cooldown's progress while it runs (0 just used .. 1), then 1 when a slide would start
-- now and 0 when it would not (standing, in the air).
function LobbyMoveController.touchProgress(now: number, lastSlide: number, canSlide: boolean): number
	local cooled = math.clamp((now - lastSlide) / SLIDE.cooldownSeconds, 0, 1)
	if cooled < 1 then
		return cooled
	end
	return if canSlide then 1 else 0
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function localPlayer(): Player
	return Players.LocalPlayer
end

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function textOf(value: unknown): string
	return if type(value) == "string" then value else ""
end

local function playSound(key: string, options: SoundController.PlayOptions?)
	local ok, err = pcall(SoundController.play, key, options)
	if not ok then
		log:warn("sound failed:", err)
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The floor under a slider (characters and client effects ignored), or nil.
local function floorBelow(root: BasePart): Vector3?
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
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -FLOOR_PROBE, 0), params)
	return if hit then hit.Position else nil
end

local function clearPose(player: Player)
	local layer = CharacterAnimController.getLayer(player)
	if layer and layer:has(LAYER) then
		layer:clear(LAYER)
	end
end

local function applyPose(slide: Slide, t: number)
	local layer = CharacterAnimController.getLayer(slide.player)
	if layer == nil or not layer:isReady() or layer:getRig() ~= RIG_R15 then
		return
	end
	local weight = LobbyMoveController.poseWeight(t, slide.length)
	if weight <= 0 then
		clearPose(slide.player)
		return
	end
	local anyLayer: any = layer
	anyLayer:setAngles(LAYER, "override", SLIDE.pose, weight, SLIDE.priority)
end

-- The own move -----------------------------------------------------------------------------------------------------------

local function endMove(slide: Slide)
	local connection = slide.jumpConnection
	if connection then
		connection:Disconnect()
		slide.jumpConnection = nil
	end
	local mover, attachment = slide.mover, slide.attachment
	slide.mover, slide.attachment = nil, nil
	if mover then
		mover:Destroy()
	end
	if attachment then
		attachment:Destroy()
	end
	local humanoid, hipFrom, hipSet = slide.humanoid, slide.hipFrom, slide.hipSet
	slide.hipFrom, slide.hipSet = nil, nil
	if humanoid and hipFrom and hipSet and humanoid.Parent and math.abs(humanoid.HipHeight - hipSet) < 1e-3 then
		humanoid.HipHeight = hipFrom -- only if nothing else changed it meanwhile
	end
	-- An own slide that ends early shortens its pose (blending out from now).
	local t = os.clock() - slide.startClock
	if t < slide.length then
		slide.length = math.max(t + SLIDE.blendOutSeconds * 0.5, 0)
	end
end

local function startMove(slide: Slide, humanoid: Humanoid)
	local attachment = Instance.new("Attachment")
	attachment.Name = MOVER_NAME
	local mover = Instance.new("LinearVelocity")
	mover.Name = MOVER_NAME
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.MaxForce = slide.root.AssemblyMass * SLIDE.maxAccel
	local speed = LobbyMoveController.speedAt(0)
	mover.PlaneVelocity = Vector2.new(slide.dir.X * speed, slide.dir.Z * speed)
	attachment.Parent = slide.root
	mover.Parent = slide.root
	slide.attachment = attachment
	slide.mover = mover
	slide.humanoid = humanoid
	local hipFrom = humanoid.HipHeight
	local hipSet = if MOVE_FX.enabled then hipFrom else math.max(hipFrom - SLIDE.hipDrop, SLIDE.minHipHeight)
	if hipSet < hipFrom then
		slide.hipFrom, slide.hipSet = hipFrom, hipSet
		humanoid.HipHeight = hipSet
	end
	slide.jumpConnection = humanoid.StateChanged:Connect(function(_old, new)
		if new == Enum.HumanoidStateType.Jumping then
			endMove(slide) -- jump out of the slide: the run keeps the speed it has
		end
	end)
end

-- One joint phase of the own move: the speed along the slide, a little steering, the end.
local function stepMove(slide: Slide, dt: number)
	local mover = slide.mover
	if mover == nil then
		return
	end
	local t = os.clock() - slide.startClock
	local humanoid = slide.humanoid
	local player = localPlayer()
	local inMatch = textOf(player:GetAttribute(ATTR_MATCH_ID)) ~= "" or textOf(player:GetAttribute(ATTR_DUEL_PHASE)) ~= ""
	if t >= SLIDE.seconds or slide.root.Parent == nil or humanoid == nil or humanoid.Health <= 0 or inMatch then
		endMove(slide)
		return
	end
	local step = math.max(dt, MIN_STEP)
	local want = flat(humanoid.MoveDirection)
	if want.Magnitude > 0.1 then
		local turn = math.clamp(SLIDE.steerPerSecond * step, 0, 1)
		local dir = slide.dir:Lerp(want.Unit, turn)
		if dir.Magnitude > 1e-3 then
			slide.dir = dir.Unit
		end
	end
	local speed = LobbyMoveController.speedAt(t)
	local actual = flat(slide.root.AssemblyLinearVelocity):Dot(slide.dir)
	if t > SLIDE.blockedSeconds and actual < speed * 0.5 then
		slide.slowFor += step
		if slide.slowFor >= SLIDE.blockedSeconds then
			endMove(slide) -- it ran into something: stop pushing
			return
		end
	else
		slide.slowFor = 0
	end
	mover.PlaneVelocity = Vector2.new(slide.dir.X * speed, slide.dir.Z * speed)
end

-- Every slide (own and others) -------------------------------------------------------------------------------------------

local function stopSkid(slide: Slide)
	local skid = slide.skid
	slide.skid = nil
	if skid then
		skid:stop()
	end
end

-- The design's slide end: the puff and the pop, then its held dust, sprinkles and streak stop (an early end: a jump).
local function endFeel(slide: Slide)
	local feel = slide.feel
	if feel and not slide.ended then
		slide.ended = true
		feel:signal("slideEnd")
		feel:stop()
	end
end

local function finishSlide(slide: Slide)
	endMove(slide)
	stopSkid(slide)
	endFeel(slide)
	clearPose(slide.player)
	if slides[slide.player] == slide then
		slides[slide.player] = nil
	end
end

local function startSlide(player: Player, character: Model, root: BasePart, own: boolean): Slide
	local old = slides[player]
	if old then
		finishSlide(old)
	end
	local look = flat(root.AssemblyLinearVelocity)
	if look.Magnitude < 1 then
		look = flat(root.CFrame.LookVector)
	end
	local slide: Slide = {
		player = player,
		character = character,
		root = root,
		own = own,
		startClock = os.clock(),
		length = SLIDE.seconds,
		dir = if look.Magnitude > 1e-3 then look.Unit else Vector3.zAxis,
		skid = if MOVE_FX.enabled then nil else MoveVfx.hold(VFX_SKID, { tint = Palette.Sky, low = not own }),
		feel = nil,
		ended = false,
		mover = nil,
		attachment = nil,
		humanoid = nil,
		hipFrom = nil,
		hipSet = nil,
		slowFor = 0,
		jumpConnection = nil,
	}
	slides[player] = slide
	if MOVE_FX.enabled then
		slide.feel = FeelFx.play(
			MOVE_FX.moments.slide,
			MoveFxController.actorFor(player, character, root, {
				dir = slide.dir,
				low = not own,
				priority = if own then 0 else OTHER_PRIORITY,
			})
		)
		if own then
			MoveFxController.suppress(SLIDE.seconds + 0.1)
		end
		return slide
	end
	playSound(SOUND_WHOOSH, {
		at = root,
		pitch = SLIDE.pitch,
		priority = if own then 0 else OTHER_PRIORITY,
	})
	return slide
end

-- One render frame of a slide: its pose and its skid. False once it is over.
local function stepSlide(slide: Slide): boolean
	if slide.root.Parent == nil then
		return false
	end
	local t = os.clock() - slide.startClock
	if slide.feel then
		local feel = slide.feel
		feel.actor.dir = slide.dir -- the streak and the dust follow the steering
		if t >= slide.length then
			endFeel(slide)
		end
		return t < slide.length
	end
	applyPose(slide, t)
	local skid = slide.skid
	if skid then
		local floor = floorBelow(slide.root)
		if floor then
			local at = floor + Vector3.new(0, FLOOR_LIFT, 0)
			local dir = if slide.dir.Magnitude > 1e-3 then slide.dir else Vector3.zAxis
			skid:set(CFrame.lookAt(at, at + dir))
		end
		skid:setOn(floor ~= nil) -- no dust in the air (a slide off a ledge)
		if t >= slide.length - SLIDE.blendOutSeconds then
			stopSkid(slide)
		end
	end
	return t < slide.length
end

-- Input and network --------------------------------------------------------------------------------------------------

local function factsNow(now: number, character: Model?, humanoid: Humanoid?, root: BasePart?): GateFacts
	local player = localPlayer()
	local velocity = if root then flat(root.AssemblyLinearVelocity) else Vector3.zero
	return {
		lobby = ControlsController.isContextActive("Lobby"),
		practice = ControlsController.isContextActive("Practice"),
		inMatch = textOf(player:GetAttribute(ATTR_MATCH_ID)) ~= "" or textOf(player:GetAttribute(ATTR_DUEL_PHASE)) ~= "",
		alive = character ~= nil and humanoid ~= nil and humanoid.Health > 0 and root ~= nil,
		grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air,
		speed = velocity.Magnitude,
		walkSpeed = if humanoid then humanoid.WalkSpeed else 0,
		sliding = slides[player] ~= nil and (slides[player] :: Slide).mover ~= nil,
		now = now,
		lastSlideAt = lastSlideAt,
	}
end

local function trySlide(): boolean
	local player = localPlayer()
	local character = player.Character
	local humanoid = humanoidOf(character)
	local root = rootOf(character)
	local now = os.clock()
	if LobbyMoveController.gate(factsNow(now, character, humanoid, root)) ~= nil then
		stats.refused += 1
		return false
	end
	if character == nil or humanoid == nil or root == nil then
		return false
	end
	lastSlideAt = now
	NetController.fire(REMOTE_REQUEST, Workspace:GetServerTimeNow())
	stats.sent += 1
	local slide = startSlide(player, character, root, true)
	startMove(slide, humanoid)
	return true
end

local function onSlideInput(inputState: Enum.UserInputState, _input: InputObject?): boolean?
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	return trySlide()
end

-- The touch Slide button ---------------------------------------------------------------------------------------------

-- The shade over the button: its top (1 - progress) shaded, the clear part growing upward (ControlsController's look).
local function setShade(view: TouchView, progress: number)
	local edge = math.clamp(1 - progress, 0, 1)
	local shaded = TOUCH_SHADE_TRANSPARENCY
	local keys: { NumberSequenceKeypoint }
	if edge <= 0.001 then
		keys = { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) }
	elseif edge >= 0.999 then
		keys = { NumberSequenceKeypoint.new(0, shaded), NumberSequenceKeypoint.new(1, shaded) }
	else
		keys = {
			NumberSequenceKeypoint.new(0, shaded),
			NumberSequenceKeypoint.new(edge, shaded),
			NumberSequenceKeypoint.new(math.min(edge + 0.001, 0.999), 1),
			NumberSequenceKeypoint.new(1, 1),
		}
	end
	view.gradient.Transparency = NumberSequence.new(keys)
	view.progress = progress
end

local function buildTouch(c: Cleanup.Cleanup)
	local playerGui = localPlayer():FindFirstChildOfClass("PlayerGui")
	if playerGui == nil or touchView ~= nil then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = TOUCH_GUI_NAME
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = TOUCH_DISPLAY_ORDER
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false
	local button = Instance.new("TextButton")
	button.Name = "Touch_SlideButton"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 0
	button.Text = ""
	-- An opaque foam disc in Sky, as the duel's round buttons (ControlsController).
	local bands = Theme.Foam.tile
	Theme.foam(button, {
		radius = Theme.Radius.pill,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.accentColors(TOUCH_ACCENT, true),
		fixedHeight = TOUCH.dashButton,
	})
	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.Colors.inkUI
	shade.BorderSizePixel = 0
	shade.Active = false
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = shade
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90 -- keypoint 0 at the top, 1 at the bottom
	gradient.Parent = shade
	shade.Parent = button
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0, -(bands.bevel + bands.drop - bands.top) / 2 / TOUCH.dashButton)
	label.FontFace = Theme.font("Button")
	label.TextSize = Config.UI.TextSize.Button
	label.TextWrapped = true
	label.Text = Strings.controls.slide
	label.ZIndex = 2
	Theme.textOnColor(label, "Button") -- the outlined-text rule: white with the InkUI outline
	label.Parent = button
	button.Parent = gui
	c:add(button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			trySlide()
		end
	end))
	local view: TouchView = { gui = gui, button = button, gradient = gradient, label = label, progress = -1 }
	setShade(view, 0)
	touchView = view
	c:add(gui)
	c:add(function()
		touchView = nil
	end)
	gui.Parent = playerGui
end

local function touchInput(): boolean
	if ControlsController.preferredInput() == Enum.PreferredInput.Touch then
		return true
	end
	return RunService:IsStudio() and type(Workspace:GetAttribute(PHONE_PREVIEW)) == "number"
end

-- Each render frame: whether the button shows, where, and its shade.
local function stepTouch()
	local view = touchView
	if view == nil then
		return
	end
	local player = localPlayer()
	local character = player.Character
	local humanoid = humanoidOf(character)
	local root = rootOf(character)
	local facts = factsNow(os.clock(), character, humanoid, root)
	local shown = LobbyMoveController.touchShown({
		touch = touchInput(),
		lobby = facts.lobby,
		practice = facts.practice,
		inMatch = facts.inMatch,
		blocked = ControlsController.isBlocked(),
		alive = facts.alive,
	})
	if view.gui.Enabled ~= shown then
		view.gui.Enabled = shown
	end
	if not shown then
		return
	end
	local size = view.gui.AbsoluteSize
	if size.X > 0 and size.Y > 0 then
		local scale = ControlsController.touchScale(size)
		local rect = LobbyMoveController.touchRect(size, scale, ControlsController.jumpRectIn(view.gui))
		local position, dims = UDim2.fromOffset(rect.x, rect.y), UDim2.fromOffset(rect.w, rect.h)
		if view.button.Position ~= position then
			view.button.Position = position
		end
		if view.button.Size ~= dims then
			view.button.Size = dims
		end
		local textSize = math.max(Config.UI.minTextSize, math.floor(Config.UI.TextSize.Button * scale))
		if view.label.TextSize ~= textSize then
			view.label.TextSize = textSize
		end
	end
	local canSlide = LobbyMoveController.gate(facts) == nil
	local progress = LobbyMoveController.touchProgress(facts.now, lastSlideAt, canSlide)
	if math.abs(progress - view.progress) > 0.002 or (progress >= 1) ~= (view.progress >= 1) then
		setShade(view, progress)
	end
end

-- Other players' slides: their character's SD_SlideAt changed (the server accepted one).
local function watchOthers()
	local me = localPlayer()
	local serverNow = Workspace:GetServerTimeNow()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local at = if character then character:GetAttribute(ATTR_SLIDE_AT) else nil
		if type(at) ~= "number" then
			continue
		end
		if seen[player] == at then
			continue
		end
		seen[player] = at
		if player == me or serverNow - at > SLIDE.seconds then
			continue -- the own slide already plays; an old stamp (a late join) is not a slide
		end
		local root = rootOf(character)
		if character and root then
			stats.remote += 1
			startSlide(player, character, root, false)
		end
	end
	for player in seen do
		if player.Parent == nil then
			seen[player] = nil
		end
	end
end

local function stepJoint(dt: number, _now: number): boolean
	local own = slides[localPlayer()]
	if own and own.mover then
		stepMove(own, dt)
	end
	return true
end

local function stepRender(_dt: number, _now: number): boolean
	watchOthers()
	stepTouch()
	for _, slide in slides do
		if not stepSlide(slide) then
			finishSlide(slide)
		end
	end
	return true
end

-- Public -----------------------------------------------------------------------------------------------------------------

function LobbyMoveController.isSliding(): boolean
	local own = slides[localPlayer()]
	return own ~= nil and own.mover ~= nil
end

function LobbyMoveController.counts(): { [string]: number }
	local live = 0
	for _ in slides do
		live += 1
	end
	return { sent = stats.sent, refused = stats.refused, remote = stats.remote, live = live }
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

function LobbyMoveController.init()
	cleanup = Cleanup.new()
end

function LobbyMoveController.start()
	local c = cleanup or Cleanup.new()
	cleanup = c
	c:add(ControlsController.bindAction(ACTION, onSlideInput))
	buildTouch(c)
	c:add(Scheduler.add(stepJoint, "joint"))
	c:add(Scheduler.add(stepRender, "render"))
	c:add(function()
		for _, slide in slides do
			finishSlide(slide)
		end
	end)
end

function LobbyMoveController.destroy()
	local c = cleanup
	cleanup = nil
	if c then
		c:clean()
	end
	table.clear(seen)
	lastSlideAt = -math.huge
end

return LobbyMoveController
