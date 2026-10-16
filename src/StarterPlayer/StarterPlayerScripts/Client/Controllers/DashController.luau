--!strict
-- DashController (client only). Spec phase 5 §1.2, §3.3: the dash (design: avatar.js:77-162, fp.js:506-541). Numbers
-- in Config.Duel.Rules.Dash (the move), Config.Anim.dash (the pose clip) and Config.Vfx.Dash (the effects); colours in
-- Art/Palette Dash*. The server decides (DashService, Logic/DashRules); this module predicts the own dash and animates
-- every dash.
--
-- * Input (user decision 2026-10-11): Dash / PracticeDash (ControlsController: C, ButtonB, the touch Dash button) in
--   the Duel and Practice contexts. A press dashes when gate() lets it (pure; the server's rules, never looser): a duel
--   in Active or SuddenDeath with the HRP inside the own half + Config.Combat.Throw.zoneToleranceStuds, or the practice
--   range; alive; not dashing; not rooted by an ultimate nor in its cast, not in a throw windup (ThrowController
--   getUltState / localUlt / localWindup); on the ground (Humanoid.FloorMaterial, and the HRP at most the standing
--   height + groundToleranceStuds over the floor, as the server checks); cooldownSeconds since the own last dash (no
--   tolerance: the client is the stricter side). A refused press does nothing (the design has no refusal cue).
-- * Direction (user decision): Humanoid.MoveDirection snapped to the camera's nearest forward / back / left / right on
--   the ground (Shared/DashMath.snapDirection); no input = the camera's forward. The pose key (the design's F/B/L/R,
--   avatar.js:102) is that direction seen from the character's facing (DashMath.poseKey).
-- * The end point, worked out as the server does: distanceStuds along the direction, cut where a Spherecast of
--   bodyRadiusStuds from the HRP meets cover (Default collision group, so arena barriers and dividers are skipped by
--   their groups as on the server; every character and Workspace.SD_ClientFx left out) and kept bodyRadiusStuds inside
--   the own half (practice: PracticeTargets.BOUNDS) by DashMath.clampToZone, so it never reaches the neutral band. A
--   dash blocked at once still plays (it spends the cooldown on the server too).
-- * Prediction: DashRequest(seq, dir, clientTime) through NetController (nothing sent = no dash), and the move starts at
--   once: a LinearVelocity (Plane, world X and Z, on its own Attachment in the HRP) takes the HRP along the design's
--   ease toward the end point (DashMath.offsetAt, fp.js:537), each joint phase aiming at the eased offset for the end of
--   the frame (speed capped at the curve's start speed, 3 · distance / seconds), so walls still stop the body. Jumping
--   is off while it moves (the design ignores a jump during a dash, fp.js:532). At `seconds` the constraint goes and
--   the horizontal speed is zeroed. A dash the server refuses is not pulled back: the server's movement guard handles
--   that move like any other (the gate makes it a race only).
-- * Pose (third person, R15 only: no R6 dash pose, NOT IN DESIGN): the design's dash keys (Config.Anim.dash; its legs
--   and pelvis offset have no joint here) sampled at visualFps (DashMath.sampleKeys) as the "dash" override layer at
--   DashMath.weightAt and Config.Anim.dash.priority, plus the held arm's `hold` degrees as the "dashHold" additive
--   layer on RightShoulder X (-hold at holdWeight) while the hold pose shows and no throw or ultimate pose does (the
--   design's throw replaces the held arm, avatar.js:185-191).
-- * Effects (design: fp.js:516-517, 529, 539; FxPool, FxShapes): at the push-off (pushoffFrame) 12 cream puffs and a
--   white ring at the push-off foot (pushoffFoot) and sfx.dash; at the plant (plantFrame) 8 puffs at the plant foot
--   (plantFoot) and sfx.dashPlant; the design's puffs fly nearly flat (fx.js:103), Roblox has no flat burst, so they
--   fly in a dome (no puff under the floor). For ribbonSeconds: three camera-facing ribbons (Trails on the HRP;
--   reading: the design's waist is the HRP's centre) in the dasher's team tint (tintFor) and tiny white specks flying
--   back along the dash (the design's 60% a frame, at 60 fps; fewer with ReducedMotion, FxPool halves the puffs).
-- * Other players: DashStarted {userId, dir, from, to, startAt} plays the same pose, effects and sounds on their
--   character from its arrival (their movement arrives through replication with the same delay). The own DashStarted
--   is ignored (the dash already plays). Sounds of a player who is neither this one nor the duel opponent play at the
--   other-player priority (-1).
-- * Touch: the Dash button's cooldown look every render frame while the touch buttons show
--   (ControlsController.setTouchState, the throw button's format).
-- API: gate(facts), pushoffFoot(key), plantFoot(key), holdWeight(frame), tintFor(side), parseDashStarted(raw) (pure,
--   unit-tested); isDashing(), counts(); init(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local DashMath = require(Shared.DashMath)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local FxShapes = require(Client.Anim.FxShapes)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local CatchController = require(script.Parent.CatchController)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)

-- Types

export type DashKey = DashMath.DashKey
export type Foot = "Left" | "Right"

-- What the gate needs to know about the local player at a press (gathered fresh for each press).
export type GateFacts = {
	context: string?, -- the live input context: "duel" | "practice"
	phase: string?, -- duel: the match phase
	alive: boolean,
	inZone: boolean, -- duel: the HRP inside the own half + zoneToleranceStuds (practice: ignored)
	dashing: boolean,
	rooted: boolean, -- an ultimate's telegraph or recovery
	windup: boolean, -- a throw windup
	ultBusy: boolean, -- an ultimate's cast or telegraph
	crushing: boolean?, -- feature 1: the hands hold a caught toy (user decision 2026-10-11: no dash while crushing)
	grounded: boolean,
	now: number, -- server time
	lastDashAt: number, -- server time of the own last dash (-math.huge before one)
}

-- One dash on screen (the own predicted one, or another player's from DashStarted).
type Dash = {
	player: Player,
	character: Model,
	root: BasePart,
	key: DashKey,
	dir: Vector3, -- flat unit
	tint: Color3,
	soundPriority: number,
	startClock: number, -- os.clock() of the press (own) or the arrival (others)
	pushed: boolean,
	planted: boolean,
	trails: { Trail },
	trailsStopped: boolean,
	specks: ParticleEmitter?,
	-- The own dash's move:
	from: Vector3?,
	distance: number,
	mover: LinearVelocity?,
	attachment: Attachment?,
	humanoid: Humanoid?,
	jumpOff: boolean,
}

-- Constants

local DASH = Config.Duel.Rules.Dash
local ANIM = Config.Anim.dash
local KEYS = ANIM.keys :: any -- { [DashKey]: { DashMath.Key } }
local FX = Config.Vfx.Dash
local TEXTURES = Config.Vfx.Textures
local HITBOX = Config.Combat.Hitbox
local ZONE_TOLERANCE = Config.Combat.Throw.zoneToleranceStuds
local REDUCED_MULTIPLIER = Config.Vfx.reducedParticleMultiplier
local STANDING_HEIGHT = HITBOX.radius - HITBOX.bottomOffset -- the HRP over the floor when standing (3.0)
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local REASON_CONTEXT = "dash.context"
local REASON_BUSY = "dash.busy"
local REASON_AIRBORNE = "dash.airborne"
local REASON_COOLDOWN = "dash.cooldown"
local LAYER_DASH = "dash"
local LAYER_DASH_HOLD = "dashHold"
local LAYER_HOLD = "hold" -- CharacterAnimController's hold pose
local LAYER_THROW = "throw" -- ThrowController's throw and ultimate poses
local LAYER_ULT = "ult"
local RIG_R15 = "R15"
local CLIENT_FX = "SD_ClientFx"
local MOVER_NAME = "SD_Dash"
local SOUND_DASH = "sfx.dash"
local SOUND_PLANT = "sfx.dashPlant"
local OTHER_SOUND_PRIORITY = -1 -- as VfxController's other players' sounds
local FOOT_LIFT = 0.03 / 0.28 -- design: fp.js:515 (the foot point 0.03 m over the floor)
local DESIGN_FPS = 60 -- the design's "a frame" chances run at 60 fps
local DOME_SPREAD = Vector2.new(90, 90) -- a burst over the upper half (see the header)
local MIN_STEP = 1 / 240
local PUFF_COLORS = { Palette.DashPuff, Palette.DashPuffShade } -- design: fp.js:516-517
local CLIP_SECONDS = DashMath.eventSeconds(DASH.visualFrames)
local LIVE_SECONDS = (function(): number
	local longest = 0
	for _, ribbon in FX.ribbons do
		longest = math.max(longest, ribbon.lifetime)
	end
	return math.max(CLIP_SECONDS, DASH.ribbonSeconds + longest)
end)()

-- Module table

local DashController = {}

-- Private state

local log = Log.new("Dash")
local cleanup: Cleanup.Cleanup? = nil
local dashes: { [Player]: Dash } = {}
local lastDashAt = -math.huge -- server time of the own last dash
local random = Random.new()
local stats = { sent = 0, refused = 0, remote = 0 }

-- Private: helpers

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function localPlayer(): Player
	return Players.LocalPlayer
end

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function humanoidOf(character: Model?): Humanoid?
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

local function isFiniteVector(value: unknown): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	local v = value :: Vector3
	return isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
end

local function playSound(key: string, options: SoundController.PlayOptions?)
	local ok, err = pcall(SoundController.play, key, options)
	if not ok then
		log:warn(`sound {key} failed:`, err)
	end
end

local function currentContext(): string?
	if ControlsController.isContextActive("Duel") then
		return "duel"
	elseif ControlsController.isContextActive("Practice") then
		return "practice"
	end
	return nil
end

-- The box a dash stays inside: the own half (duel) or the practice range bounds; nil when the view has none yet.
local function zoneFor(context: string): Types.ArenaZone?
	if context == "practice" then
		local bounds = PracticeTargets.BOUNDS
		return { cframe = CFrame.new(bounds.position), size = bounds.size }
	end
	local view = StateController.duel()
	if view == nil then
		return nil
	end
	local zones = view.arena and view.arena.zones
	local zone = if zones then zones["Half" .. tostring(view.you.side)] else nil
	if zone == nil or typeof(zone.cframe) ~= "CFrame" or typeof(zone.size) ~= "Vector3" then
		return nil
	end
	return zone
end

-- The floor under a dasher: the arena slot's (duel) or the lane's (practice).
local function floorYFor(context: string?): number?
	if context == "practice" then
		return PracticeTargets.FLOOR_Y
	end
	local view = StateController.duel()
	local arena = view and view.arena
	return if arena and type(arena.floorY) == "number" then arena.floorY else nil
end

-- As Logic/HitMath.inZone on the server: X and Z widened by `margin`; true when the zone is unknown (the server
-- decides).
local function insideZone(zone: Types.ArenaZone?, position: Vector3, margin: number): boolean
	if zone == nil then
		return true
	end
	local p = zone.cframe:PointToObjectSpace(position)
	local half = zone.size / 2
	return math.abs(p.X) <= half.X + margin and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z + margin
end

local function sideOf(userId: number): string?
	local view = StateController.duel()
	if view == nil then
		return nil
	elseif view.you.userId == userId then
		return view.you.side
	elseif view.opponent.userId == userId then
		return view.opponent.side
	end
	return nil
end

local function soundPriorityFor(userId: number): number
	local view = StateController.duel()
	if userId == localPlayer().UserId or (view ~= nil and view.opponent.userId == userId) then
		return 0
	end
	return OTHER_SOUND_PRIORITY
end

-- Private: the gate

local function windupBusy(): boolean
	local tau, _, _, releaseStart, cancelled = ThrowController.localWindup()
	return tau ~= nil and releaseStart == nil and not cancelled
end

local function ultBusy(): boolean
	local phase = ThrowController.localUlt()
	return phase == "cast" or phase == "telegraph"
end

local function factsNow(now: number, root: BasePart?, humanoid: Humanoid?): GateFacts
	local context = currentContext()
	local view = StateController.duel()
	local inZone = true
	local grounded = humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	if root ~= nil then
		if context == "duel" then
			inZone = insideZone(zoneFor("duel"), root.Position, ZONE_TOLERANCE)
		end
		local floorY = floorYFor(context)
		if floorY ~= nil and root.Position.Y - floorY > STANDING_HEIGHT + DASH.groundToleranceStuds then
			grounded = false
		end
	end
	return {
		context = context,
		phase = if view then view.phase else nil,
		alive = root ~= nil and humanoid ~= nil and humanoid.Health > 0,
		inZone = inZone,
		dashing = dashes[localPlayer()] ~= nil,
		rooted = ThrowController.getUltState().rooted,
		windup = windupBusy(),
		ultBusy = ultBusy(),
		crushing = CatchController.state().crushing, -- feature 1
		grounded = grounded,
		now = now,
		lastDashAt = lastDashAt,
	}
end

-- Private: the end point

local function coverParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.CollisionGroup = "Default"
	params.IgnoreWater = true
	local exclude: { Instance } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			table.insert(exclude, character)
		end
	end
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	if fx then
		table.insert(exclude, fx)
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- The dash's length: distanceStuds, cut at cover and walls and kept inside the zone. The Spherecast starts one body
-- radius BEHIND the HRP (bug fix 2026-10-15): a shapecast skips parts it already overlaps at its start, so cover the
-- body is touching was ignored and a dash into it got its full 14 studs of push (a player was flung).
function DashController.endDistance(origin: Vector3, dir: Vector3, zone: Types.ArenaZone?): number
	local distance = DASH.distanceStuds
	local back = DASH.bodyRadiusStuds
	local hit = Workspace:Spherecast(origin - dir * back, DASH.bodyRadiusStuds, dir * (distance + back), coverParams())
	if hit then
		distance = math.clamp(hit.Distance - back, 0, distance)
	end
	if zone ~= nil then
		distance = math.min(distance, DashMath.clampToZone(origin, dir, distance, zone, DASH.bodyRadiusStuds))
	end
	return distance
end

-- Private: the move (own dash)

local function endMove(dash: Dash)
	local mover, attachment = dash.mover, dash.attachment
	dash.mover = nil
	dash.attachment = nil
	if mover then
		mover:Destroy()
		local root = dash.root
		if root.Parent ~= nil then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end
	if attachment then
		attachment:Destroy()
	end
	local humanoid = dash.humanoid
	if humanoid and dash.jumpOff then
		dash.jumpOff = false
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
end

local function startMove(dash: Dash)
	local humanoid = humanoidOf(dash.character)
	if humanoid == nil then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = MOVER_NAME
	local mover = Instance.new("LinearVelocity")
	mover.Name = MOVER_NAME
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.MaxForce = dash.root.AssemblyMass * DASH.maxAccelStuds -- never an unlimited push (bug fix 2026-10-15)
	mover.PlaneVelocity = Vector2.zero
	attachment.Parent = dash.root
	mover.Parent = dash.root
	dash.attachment = attachment
	dash.mover = mover
	dash.humanoid = humanoid
	if humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping) then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		dash.jumpOff = true
	end
end

-- One joint phase of the own move: the speed that reaches the eased offset at the end of this frame.
local function stepMove(dash: Dash, dt: number)
	local mover, from = dash.mover, dash.from
	if mover == nil or from == nil then
		return
	end
	local t = os.clock() - dash.startClock
	if t >= DASH.seconds or dash.root.Parent == nil then
		endMove(dash)
		return
	end
	local step = math.max(dt, MIN_STEP)
	local travelled = (dash.root.Position - from):Dot(dash.dir)
	if DashController.blocked(DashMath.offsetAt(t, dash.distance, DASH.seconds) - travelled) then
		endMove(dash) -- it ran into something: stop pushing (bug fix 2026-10-15)
		return
	end
	local target = DashMath.offsetAt(t + step, dash.distance, DASH.seconds)
	local speed = math.clamp((target - travelled) / step, 0, DashMath.speedAt(0, dash.distance, DASH.seconds))
	mover.PlaneVelocity = Vector2.new(dash.dir.X * speed, dash.dir.Z * speed)
end

-- Private: the pose

local function clearPose(player: Player)
	local layer = CharacterAnimController.getLayer(player)
	if layer == nil then
		return
	end
	for _, id in { LAYER_DASH, LAYER_DASH_HOLD } do
		if layer:has(id) then
			layer:clear(id)
		end
	end
end

local function applyPose(dash: Dash, frame: number)
	local layer = CharacterAnimController.getLayer(dash.player)
	if layer == nil or not layer:isReady() or layer:getRig() ~= RIG_R15 then
		return
	end
	if frame >= DASH.visualFrames then
		clearPose(dash.player)
		return
	end
	local anyLayer: any = layer
	local angles, hold = DashMath.sampleKeys(KEYS[dash.key], frame)
	anyLayer:setAngles(LAYER_DASH, "override", angles, DashMath.weightAt(frame), ANIM.priority)
	if layer:has(LAYER_HOLD) and not layer:has(LAYER_THROW) and not layer:has(LAYER_ULT) then
		local arm = { RightShoulder = Vector3.new(-hold, 0, 0) }
		anyLayer:setAngles(LAYER_DASH_HOLD, "additive", arm, DashController.holdWeight(frame), ANIM.priority)
	elseif layer:has(LAYER_DASH_HOLD) then
		layer:clear(LAYER_DASH_HOLD)
	end
end

-- Private: effects

-- The design's foot point (fp.js:515): under the foot, FOOT_LIFT over the floor.
local function footPoint(dash: Dash, foot: Foot): Vector3
	local character = dash.character
	local part = character:FindFirstChild(foot .. "Foot") or character:FindFirstChild(foot .. " Leg")
	local root = dash.root
	if part and part:IsA("BasePart") then
		local p = part.Position
		return Vector3.new(p.X, p.Y - part.Size.Y / 2 + FOOT_LIFT, p.Z)
	end
	local p = root.Position
	return Vector3.new(p.X, p.Y - STANDING_HEIGHT + FOOT_LIFT, p.Z)
end

local function puffs(
	at: Vector3,
	count: number,
	speed: number,
	size: number,
	lifetime: number,
	drag: number,
	gravity: number
)
	local pool = FxPool.default()
	local each = math.max(1, math.floor(count / #PUFF_COLORS))
	for _, color in PUFF_COLORS do
		pool:emit(at, each, {
			Texture = TEXTURES.smoke,
			Color = ColorSequence.new(color),
			Size = NumberSequence.new(size, 0),
			Lifetime = NumberRange.new(lifetime * 0.7, lifetime * 1.3), -- design: fx.js:104-105
			Speed = NumberRange.new(speed * 0.45, speed * 1.2), -- design: fx.js:104
			SpreadAngle = DOME_SPREAD,
			Drag = drag,
			Acceleration = Vector3.new(0, gravity, 0),
			LightEmission = 0,
			Rate = 0,
		})
	end
end

local function pushoff(dash: Dash)
	local at = footPoint(dash, DashController.pushoffFoot(dash.key))
	puffs(at, FX.pushoffPuffs, FX.pushoffSpeed, FX.pushoffSize, FX.pushoffLifetime, FX.pushoffDrag, FX.pushoffGravity)
	FxShapes.ring(at, Vector3.yAxis, FX.ringToStuds, FX.ringSeconds, Palette.White, FX.ringTransparencyFrom)
	playSound(SOUND_DASH, { at = at, priority = dash.soundPriority })
end

local function plant(dash: Dash)
	local at = footPoint(dash, DashController.plantFoot(dash.key))
	puffs(at, FX.plantPuffs, FX.plantSpeed, FX.plantSize, FX.plantLifetime, FX.plantDrag, FX.plantGravity)
	playSound(SOUND_PLANT, { at = at, priority = dash.soundPriority })
end

local function startTrails(dash: Dash)
	local pool = FxPool.default()
	for _, ribbon in FX.ribbons do
		local half = ribbon.width / 2
		local color = if ribbon.tintFirst
			then ColorSequence.new(dash.tint, Palette.White)
			else ColorSequence.new(Palette.White, dash.tint)
		local trail = pool:acquireTrail(
			dash.root,
			Vector3.new(0, ribbon.height + half, 0),
			Vector3.new(0, ribbon.height - half, 0),
			{
				Lifetime = ribbon.lifetime,
				Color = color,
				Transparency = NumberSequence.new(1 - ribbon.opacity, 1),
				WidthScale = NumberSequence.new(1, 0),
				FaceCamera = true,
				LightEmission = 0,
			}
		)
		if trail then
			table.insert(dash.trails, trail)
		end
	end
	local rate = FX.speedLineChance * DESIGN_FPS * (if Tweens.reducedMotion() then REDUCED_MULTIPLIER else 1)
	local specks = pool:acquireEmitter({
		Texture = TEXTURES.smoke,
		Color = ColorSequence.new(Palette.White),
		Size = NumberSequence.new(FX.speedLineSize),
		Lifetime = NumberRange.new(FX.speedLineLifetime),
		Speed = NumberRange.new(FX.speedLineSpeed),
		SpreadAngle = Vector2.zero,
		EmissionDirection = Enum.NormalId.Front,
		Drag = FX.speedLineDrag,
		Acceleration = Vector3.zero,
		LightEmission = 0,
		Rate = rate,
	})
	dash.specks = specks
end

-- The specks' emitter jumps to a random point of the spread box around the waist each frame, facing back along the
-- dash (EmissionDirection Front), so each speck starts somewhere else (design: fp.js:539).
local function moveSpecks(dash: Dash)
	local specks = dash.specks
	local attachment = if specks then specks.Parent else nil
	if specks == nil or attachment == nil or not attachment:IsA("Attachment") then
		return
	end
	local spread = FX.speedLineSpread
	local offset = Vector3.new(
		random:NextNumber(-1, 1) * spread.X,
		FX.speedLineLift + random:NextNumber(-1, 1) * spread.Y,
		random:NextNumber(-1, 1) * spread.Z
	)
	local at = dash.root.Position + offset
	attachment.WorldCFrame = CFrame.lookAt(at, at - dash.dir)
	specks.Enabled = true
end

local function stopTrails(dash: Dash)
	dash.trailsStopped = true
	for _, trail in dash.trails do
		trail.Enabled = false -- the drawn ribbon fades over its lifetime, then finishDash releases it
	end
	local specks = dash.specks
	if specks then
		specks.Enabled = false
	end
end

local function finishDash(dash: Dash)
	endMove(dash)
	local pool = FxPool.default()
	for _, trail in dash.trails do
		pool:release(trail)
	end
	table.clear(dash.trails)
	local specks = dash.specks
	if specks then
		dash.specks = nil
		pool:release(specks)
	end
	clearPose(dash.player)
	if dashes[dash.player] == dash then
		dashes[dash.player] = nil
	end
end

local function startDash(player: Player, character: Model, root: BasePart, dir: Vector3, distance: number, own: boolean)
	local old = dashes[player]
	if old then
		finishDash(old)
	end
	local dash: Dash = {
		player = player,
		character = character,
		root = root,
		key = DashMath.poseKey(dir, root.CFrame.LookVector),
		dir = dir,
		tint = DashController.tintFor(sideOf(player.UserId)),
		soundPriority = soundPriorityFor(player.UserId),
		startClock = os.clock(),
		pushed = false,
		planted = false,
		trails = {},
		trailsStopped = false,
		specks = nil,
		from = if own then root.Position else nil,
		distance = distance,
		mover = nil,
		attachment = nil,
		humanoid = nil,
		jumpOff = false,
	}
	dashes[player] = dash
	startTrails(dash)
	if own then
		startMove(dash)
	end
end

-- One render frame of a dash: its pose, its push-off and plant, its ribbons. False once it is over.
local function stepDash(dash: Dash): boolean
	if dash.root.Parent == nil then
		return false
	end
	local t = os.clock() - dash.startClock
	local frame = DashMath.frameAt(t)
	applyPose(dash, frame)
	if not dash.pushed and frame >= DASH.pushoffFrame then
		dash.pushed = true
		pushoff(dash)
	end
	if not dash.planted and frame >= DASH.plantFrame then
		dash.planted = true
		plant(dash)
	end
	if t < DASH.ribbonSeconds then
		moveSpecks(dash)
	elseif not dash.trailsStopped then
		stopTrails(dash)
	end
	return t < LIVE_SECONDS
end

-- Private: input, network, frames

local function tryDash(): boolean
	local player = localPlayer()
	local character = player.Character
	local root = rootOf(character)
	local humanoid = humanoidOf(character)
	local now = serverNow()
	local facts = factsNow(now, root, humanoid)
	local context = facts.context
	if DashController.gate(facts) ~= nil or character == nil or root == nil or humanoid == nil or context == nil then
		stats.refused += 1
		return false
	end
	local camera = Workspace.CurrentCamera
	local frame = if camera then camera.CFrame else root.CFrame
	local _, dir = DashMath.snapDirection(humanoid.MoveDirection, frame.LookVector, frame.RightVector)
	local distance = DashController.endDistance(root.Position, dir, zoneFor(context))
	if NetController.dashRequest(dir, now) == nil then
		stats.refused += 1
		return false
	end
	stats.sent += 1
	lastDashAt = now
	startDash(player, character, root, dir, distance, true)
	return true
end

local function onDashInput(inputState: Enum.UserInputState, _input: InputObject?): boolean?
	if inputState ~= Enum.UserInputState.Begin then
		return false
	end
	return tryDash()
end

local function onDashStarted(raw: unknown)
	local payload = DashController.parseDashStarted(raw)
	if payload == nil or payload.userId == localPlayer().UserId then
		return -- the own dash already plays (predicted at the press)
	end
	local player = Players:GetPlayerByUserId(payload.userId)
	local character = if player then player.Character else nil
	local root = rootOf(character)
	if player == nil or character == nil or root == nil then
		return
	end
	stats.remote += 1
	startDash(player, character, root, payload.dir, (payload.to - payload.from).Magnitude, false)
end

local function updateTouch(now: number)
	if not ControlsController.touchButtonsShown() then
		return
	end
	local ready = lastDashAt + DASH.cooldownSeconds
	local progress = ThrowController.cooldownProgress(now, lastDashAt, ready)
	local label: string? = nil
	if progress < 1 then
		local template = Strings.resolve("common.secondsShort")
		if template then
			label = Strings.format(template, { seconds = string.format("%.1f", math.max(ready - now, 0)) })
		end
	end
	ControlsController.setTouchState("Dash", progress, label)
end

local function stepJoint(dt: number, _now: number): boolean
	local own = dashes[localPlayer()]
	if own and own.mover then
		stepMove(own, dt)
	end
	return true
end

local function stepRender(_dt: number, _now: number): boolean
	for _, dash in dashes do
		if not stepDash(dash) then
			finishDash(dash)
		end
	end
	updateTouch(serverNow())
	return true
end

-- Public: pure helpers (unit-tested)

-- The reason code a press is refused for (the server's codes, Logic/DashRules), or nil when it may dash.
-- True when the body lags more than blockedLagStuds behind the dash's eased path: it ran into something. Pure.
function DashController.blocked(lagStuds: number): boolean
	return lagStuds > DASH.blockedLagStuds
end

function DashController.gate(facts: GateFacts): string?
	local context = facts.context
	if context == nil or not facts.alive then
		return REASON_CONTEXT
	end
	if context == "duel" and (not LIVE_PHASES[facts.phase or ""] or not facts.inZone) then
		return REASON_CONTEXT
	end
	if facts.dashing or facts.rooted or facts.windup or facts.ultBusy or facts.crushing == true then
		return REASON_BUSY
	end
	if not facts.grounded then
		return REASON_AIRBORNE
	end
	if facts.now < facts.lastDashAt + DASH.cooldownSeconds then
		return REASON_COOLDOWN
	end
	return nil
end

-- The push-off puff's foot (design: fp.js:516): the right foot for an L dash, else the left.
function DashController.pushoffFoot(key: DashKey): Foot
	return if key == "L" then "Right" else "Left"
end

-- The plant puff's foot (design: fp.js:517): the right foot for an R dash, else the left.
function DashController.plantFoot(key: DashKey): Foot
	return if key == "R" then "Right" else "Left"
end

-- The held arm's offset weight at a clip frame (design: avatar.js:160): in over holdFadeInFrames, out over the
-- frames after fadeFromFrame.
function DashController.holdWeight(frame: number): number
	local fadeIn = math.clamp(frame / ANIM.holdFadeInFrames, 0, 1)
	if frame <= DASH.fadeFromFrame then
		return fadeIn
	end
	return fadeIn * math.max(0, (DASH.visualFrames - frame) / (DASH.visualFrames - DASH.fadeFromFrame))
end

-- The ribbons' team tint: side B Mint, else (side A, practice) Strawberry, the design runner's (fp.js:510, 529).
function DashController.tintFor(side: string?): Color3
	return if side == "B" then Palette.DashRibbonMint else Palette.DashRibbonStrawberry
end

-- A DashStarted payload, or nil when a field is missing, of the wrong type or not finite, or dir is not a flat unit.
function DashController.parseDashStarted(raw: unknown): Types.DashStartedPayload?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if
		not isFiniteNumber(t.userId)
		or not isFiniteVector(t.dir)
		or not isFiniteVector(t.from)
		or not isFiniteVector(t.to)
		or not isFiniteNumber(t.startAt)
	then
		return nil
	end
	local dir = t.dir :: Vector3
	if not DashMath.isFlatUnit(dir) then
		return nil
	end
	return {
		userId = t.userId,
		dir = Vector3.new(dir.X, 0, dir.Z).Unit,
		from = t.from,
		to = t.to,
		startAt = t.startAt,
	}
end

-- Public: state

-- True while the own dash moves the character.
function DashController.isDashing(): boolean
	local own = dashes[localPlayer()]
	return own ~= nil and own.mover ~= nil
end

-- Studio / debug counters.
function DashController.counts(): { [string]: any }
	local live = 0
	for _ in dashes do
		live += 1
	end
	return { live = live, sent = stats.sent, refused = stats.refused, remote = stats.remote, lastDashAt = lastDashAt }
end

-- Lifecycle

function DashController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(ControlsController.bindAction("Dash", onDashInput))
	c:add(ControlsController.bindAction("PracticeDash", onDashInput))
	c:add(NetController.on("DashStarted", onDashStarted))
	c:add(Scheduler.add(stepJoint, "joint"))
	c:add(Scheduler.add(stepRender, "render"))
	c:add(ControlsController.ContextChanged:connect(function(context: string, on: boolean)
		if (context == "Duel" or context == "Practice") and not on then
			local own = dashes[localPlayer()]
			if own then
				endMove(own) -- the move stops with its context; its effects play out
			end
		end
	end))
	c:add(function()
		for _, dash in dashes do
			finishDash(dash)
		end
		table.clear(dashes)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function DashController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return DashController
