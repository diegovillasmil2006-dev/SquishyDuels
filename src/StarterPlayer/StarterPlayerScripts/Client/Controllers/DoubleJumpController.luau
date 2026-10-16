--!strict
-- DoubleJumpController (client only; 2026-10-15, VillasmilGaming: "implement [the double jump] and add it to the game
-- (only when dueling)"). Numbers in Config.Duel.Rules.DoubleJump (the move), Config.Anim.doubleJump (the flip) and
-- Config.Vfx.DoubleJump (the effects); the effects are the VFX Studio library's (ReplicatedStorage.SD_MoveVfx,
-- DoubleJump/*, played by Anim/MoveVfx) in the jumper's team glow (DashController.glowFor). The server tells the match
-- (DoubleJumpService, Logic/DoubleJumpRules); this module moves the own character and animates every double jump.
--
-- * Input: UserInputService.JumpRequest, the one jump signal of every device (Space, ButtonA, the touch jump button).
--   A held key repeats it every frame, so a request counts as a press only after pressGapSeconds without one
--   (isFreshPress). A press jumps a second time when gate() lets it (pure): the Duel input context in Active or
--   SuddenDeath; alive; in the air for at least minAirSeconds (Humanoid.FloorMaterial Air); fewer than maxPerAir double
--   jumps since the last landing; the character can jump at all (JumpHeight / JumpPower > 0: the Countdown freeze and
--   an ultimate's root set them to 0), not rooted nor casting an ultimate, not dashing. Nothing in the practice range
--   or the lobby.
-- * The move: the HRP's vertical speed becomes launchSpeed(Workspace.Gravity, heightStuds) (a jump of heightStuds from
--   wherever it is, also while falling); with movement input the horizontal speed turns to it at the WalkSpeed, so the
--   second jump can change direction. The client owns its physics (as for the dash), so this replicates as is.
-- * The flip (third person, R15 only): poseAt(key, t) as the "doubleJump" override layer at Config.Anim.doubleJump
--   .priority (over the hold, under the throw and ultimate poses): the body tucks (hips, knees, waist, neck, the free
--   left arm; the held right arm keeps the hold pose) and turns once about the Root joint in spinSeconds, a front flip
--   for F (no input or forward), a back flip for B, a side flip for L / R (the key is the movement seen from the
--   character's facing, DashMath.poseKey). Under ReducedMotion it tucks without turning.
-- * Effects: DoubleJump/Burst under the feet, DoubleJump/Body on the HRP for bodySeconds, DoubleJump/FootTrail on both
--   feet for footTrailSeconds (the flip's arcs), one afterimage where it pushed off, sfx.doubleJump and sfx.dash
--   (pitched up: the push on the air). The own jump also gets a small FOV kick (CameraController.punch, off with
--   settings.cameraShake or ReducedMotion, and while a throw holds the FOV). When it lands within landWithinSeconds
--   (a ray down from the HRP meets the floor within the standing height + landSlackStuds while it falls):
--   DoubleJump/Land and sfx.dashPlant.
-- * Network: DoubleJumpRequest(seq, key, clientTime) through NetController; DoubleJumped {userId, key, at, startAt}
--   plays the same flip, effects and sounds on the other player's character from its arrival. The own one is ignored.
-- API: gate(facts), isFreshPress(now, last), launchSpeed(gravity, height), poseAt(key, t, reduced), spinAxis(key),
--   parseDoubleJumped(raw) (pure, unit-tested); counts(); init(), destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local DashMath = require(Shared.DashMath)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local Afterimage = require(Client.Anim.Afterimage)
local MoveVfx = require(Client.Anim.MoveVfx)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local CameraController = require(script.Parent.CameraController)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local DashController = require(script.Parent.DashController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)

-- Types

export type Key = "F" | "B" | "L" | "R"

-- What the gate needs to know about the local player at a press (gathered fresh for each press).
export type GateFacts = {
	inDuel: boolean, -- the Duel input context is on
	phase: string?, -- the match phase
	alive: boolean,
	airborneFor: number?, -- seconds in the air (nil = on the ground)
	used: number, -- double jumps since the last landing
	canJump: boolean, -- JumpHeight / JumpPower > 0
	rooted: boolean, -- an ultimate's telegraph or recovery
	ultBusy: boolean, -- an ultimate's cast or telegraph
	dashing: boolean,
}

-- One double jump on screen (the own one, or another player's from DoubleJumped).
type Jump = {
	player: Player,
	character: Model,
	root: BasePart,
	key: Key,
	glow: Color3,
	soundPriority: number,
	low: boolean,
	own: boolean,
	reduced: boolean,
	startClock: number,
	body: MoveVfx.Handle?,
	landed: boolean,
}

-- Constants

local RULES = Config.Duel.Rules.DoubleJump
local ANIM = Config.Anim.doubleJump
local FX = Config.Vfx.DoubleJump
local HITBOX = Config.Combat.Hitbox
local STANDING_HEIGHT = HITBOX.radius - HITBOX.bottomOffset -- the HRP over the floor when standing (3.0)
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local REASON_CONTEXT = "jump.context"
local REASON_GROUNDED = "jump.grounded"
local REASON_USED = "jump.used"
local REASON_BUSY = "jump.busy"
local LAYER = "doubleJump"
local RIG_R15 = "R15"
local CLIENT_FX = "SD_ClientFx"
local REMOTE_REQUEST = "DoubleJumpRequest"
local SOUND_JUMP = "sfx.doubleJump"
local SOUND_PUSH = "sfx.dash"
local SOUND_LAND = "sfx.dashPlant"
local VFX_BURST = "DoubleJump/Burst"
local VFX_BODY = "DoubleJump/Body"
local VFX_FEET = "DoubleJump/FootTrail"
local VFX_LAND = "DoubleJump/Land"
local OTHER_SOUND_PRIORITY = -1
local NO_INPUT = 0.1
local SPIN: { [Key]: Vector3 } = {
	F = Vector3.new(-1, 0, 0), -- Root -X leans forward (Config.Anim.dash F)
	B = Vector3.new(1, 0, 0),
	L = Vector3.new(0, 0, 1), -- Root +Z leans into an L dash (Config.Anim.dash L)
	R = Vector3.new(0, 0, -1),
}
local LIVE_SECONDS = math.max(ANIM.seconds, FX.bodySeconds, FX.footTrailSeconds)

-- Module table

local DoubleJumpController = {}

-- Private state

local log = Log.new("DoubleJump")
local cleanup: Cleanup.Cleanup? = nil
local jumps: { [Player]: Jump } = {}
local lastRequestAt = -math.huge -- os.clock() of the last JumpRequest
local airborneSince: number? = nil -- os.clock() when the own character left the ground
local usedThisAir = 0
local stats = { sent = 0, refused = 0, remote = 0, landed = 0 }

-- Pure helpers ---------------------------------------------------------------------------------------------------------

local function smooth(x: number): number
	local u = math.clamp(x, 0, 1)
	return u * u * (3 - 2 * u)
end

-- The reason code a press is refused for, or nil when it may jump again.
function DoubleJumpController.gate(facts: GateFacts): string?
	if not facts.inDuel or not LIVE_PHASES[facts.phase or ""] or not facts.alive then
		return REASON_CONTEXT
	end
	if facts.airborneFor == nil or facts.airborneFor < RULES.minAirSeconds then
		return REASON_GROUNDED
	end
	if facts.used >= RULES.maxPerAir then
		return REASON_USED
	end
	if not facts.canJump or facts.rooted or facts.ultBusy or facts.dashing then
		return REASON_BUSY
	end
	return nil
end

-- A JumpRequest is a new press when none came in the last pressGapSeconds (a held key repeats it every frame).
function DoubleJumpController.isFreshPress(now: number, last: number): boolean
	return now - last >= RULES.pressGapSeconds
end

-- The take-off speed of a jump `height` studs high under `gravity` (studs/s²): sqrt(2·g·h).
function DoubleJumpController.launchSpeed(gravity: number, height: number): number
	if not (gravity > 0) or not (height > 0) then
		return 0
	end
	return math.sqrt(2 * gravity * height)
end

-- The flip's turning axis in Root joint degrees (a unit vector with its sign).
function DoubleJumpController.spinAxis(key: string): Vector3
	return SPIN[key :: Key] or SPIN.F
end

-- The flip at t seconds: (joint degrees, layer weight). The tuck comes in over tuckInSeconds and goes from
-- tuckOutFromSeconds to spinSeconds; the Root turns spinDegrees (Quad Out) over spinSeconds unless `reduced`; the
-- weight is 1 until fadeFromSeconds, then w² to 0 at seconds.
function DoubleJumpController.poseAt(key: string, t: number, reduced: boolean?): ({ [string]: Vector3 }, number)
	local time = if t == t then math.max(t, 0) else 0
	local weight = 1
	if time >= ANIM.seconds then
		weight = 0
	elseif time > ANIM.fadeFromSeconds then
		local w = (ANIM.seconds - time) / (ANIM.seconds - ANIM.fadeFromSeconds)
		weight = w * w
	end
	local tuck
	if time < ANIM.tuckInSeconds then
		tuck = smooth(time / ANIM.tuckInSeconds)
	elseif time < ANIM.tuckOutFromSeconds then
		tuck = 1
	else
		tuck = 1 - smooth((time - ANIM.tuckOutFromSeconds) / (ANIM.spinSeconds - ANIM.tuckOutFromSeconds))
	end
	local angles: { [string]: Vector3 } = {}
	for joint, degrees in ANIM.tuck :: { [string]: Vector3 } do
		angles[joint] = degrees * tuck
	end
	local spin = 0
	if reduced ~= true then
		local u = math.clamp(time / ANIM.spinSeconds, 0, 1)
		spin = ANIM.spinDegrees * (1 - (1 - u) * (1 - u))
	end
	angles.Root = (angles.Root or Vector3.zero) + DoubleJumpController.spinAxis(key) * spin
	return angles, weight
end

local function isFiniteNumber(value: unknown): boolean
	return type(value) == "number" and value == value and math.abs(value) ~= math.huge
end

-- A DoubleJumped payload, or nil when a field is missing, of the wrong type or not finite, or key is not F/B/L/R.
function DoubleJumpController.parseDoubleJumped(raw: unknown): Types.DoubleJumpedPayload?
	if type(raw) ~= "table" then
		return nil
	end
	local t = raw :: any
	if not isFiniteNumber(t.userId) or not isFiniteNumber(t.startAt) or SPIN[t.key] == nil then
		return nil
	end
	local at = t.at
	if typeof(at) ~= "Vector3" or not isFiniteNumber(at.X) or not isFiniteNumber(at.Y) or not isFiniteNumber(at.Z) then
		return nil
	end
	return { userId = t.userId, key = t.key, at = at, startAt = t.startAt }
end

-- Private ------------------------------------------------------------------------------------------------------------

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

local function playSound(key: string, options: SoundController.PlayOptions?)
	local ok, err = pcall(SoundController.play, key, options)
	if not ok then
		log:warn(`sound {key} failed:`, err)
	end
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

local function canJump(humanoid: Humanoid): boolean
	if humanoid.UseJumpPower then
		return humanoid.JumpPower > 0
	end
	return humanoid.JumpHeight > 0
end

local function factsNow(humanoid: Humanoid?, root: BasePart?): GateFacts
	local view = StateController.duel()
	local ult = ThrowController.localUlt()
	return {
		inDuel = ControlsController.isContextActive("Duel"),
		phase = if view then view.phase else nil,
		alive = humanoid ~= nil and root ~= nil and humanoid.Health > 0,
		airborneFor = if airborneSince then os.clock() - airborneSince else nil,
		used = usedThisAir,
		canJump = humanoid ~= nil and canJump(humanoid),
		rooted = ThrowController.getUltState().rooted,
		ultBusy = ult == "cast" or ult == "telegraph",
		dashing = DashController.isDashing(),
	}
end

local function downParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
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

-- The floor point under a character's HRP within `reach` studs, or nil.
local function floorBelow(root: BasePart, reach: number): Vector3?
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), downParams())
	return if hit then hit.Position else nil
end

-- The character's flat facing (forward when it looks straight up or down).
local function facingOf(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

local function vfxOptions(jump: Jump): MoveVfx.Options
	return { tint = jump.glow, low = jump.low }
end

local function feetOf(character: Model): { BasePart }
	local feet: { BasePart } = {}
	for _, name in { "LeftFoot", "RightFoot", "Left Leg", "Right Leg" } do
		local part = character:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(feet, part)
		end
	end
	return feet
end

local function fovKick()
	if not StateController.settings().cameraShake or CameraController.fovOwner() ~= nil then
		return
	end
	CameraController.punch(FX.fovKickDeg, FX.fovKickAttackMs, FX.fovKickReleaseMs)
end

local function clearPose(player: Player)
	local layer = CharacterAnimController.getLayer(player)
	if layer and layer:has(LAYER) then
		layer:clear(LAYER)
	end
end

local function applyPose(jump: Jump, t: number)
	local layer = CharacterAnimController.getLayer(jump.player)
	if layer == nil or not layer:isReady() or layer:getRig() ~= RIG_R15 then
		return
	end
	if t >= ANIM.seconds then
		clearPose(jump.player)
		return
	end
	local angles, weight = DoubleJumpController.poseAt(jump.key, t, jump.reduced)
	local anyLayer: any = layer
	anyLayer:setAngles(LAYER, "override", angles, weight, ANIM.priority)
end

local function startEffects(jump: Jump)
	local root = jump.root
	local p = root.Position
	local facing = facingOf(root)
	local feet = Vector3.new(p.X, p.Y - STANDING_HEIGHT, p.Z)
	MoveVfx.burst(VFX_BURST, CFrame.lookAt(feet, feet + facing), vfxOptions(jump))
	jump.body = MoveVfx.hold(VFX_BODY, vfxOptions(jump))
	if jump.body then
		jump.body:set(CFrame.lookAt(p, p + facing))
		jump.body:setOn(true)
	end
	MoveVfx.onParts(VFX_FEET, feetOf(jump.character), FX.footTrailSeconds, vfxOptions(jump))
	Afterimage.spawn(jump.character, jump.glow:Lerp(Palette.White, FX.ghostTintToWhite), {
		transparency = FX.ghostTransparency,
		seconds = FX.ghostSeconds,
	})
	playSound(SOUND_JUMP, { at = root, priority = jump.soundPriority, pitch = FX.whooshPitch })
	playSound(SOUND_PUSH, { at = feet, priority = jump.soundPriority, pitch = FX.pushPitch, volume = FX.pushVolume })
	if jump.own then
		fovKick()
	end
end

local function finishJump(jump: Jump)
	local body = jump.body
	jump.body = nil
	if body then
		body:stop()
	end
	clearPose(jump.player)
	if jumps[jump.player] == jump then
		jumps[jump.player] = nil
	end
end

local function startJump(player: Player, character: Model, root: BasePart, key: Key, own: boolean)
	local old = jumps[player]
	if old then
		finishJump(old)
	end
	local priority = soundPriorityFor(player.UserId)
	local jump: Jump = {
		player = player,
		character = character,
		root = root,
		key = key,
		glow = DashController.glowFor(sideOf(player.UserId)),
		soundPriority = priority,
		low = priority < 0,
		own = own,
		reduced = Tweens.reducedMotion(),
		startClock = os.clock(),
		body = nil,
		landed = false,
	}
	jumps[player] = jump
	startEffects(jump)
end

-- Landing: falling, and the floor within the standing height + landSlackStuds under the HRP.
local function checkLanding(jump: Jump, t: number)
	if jump.landed or t < FX.landMinSeconds then
		return
	end
	if jump.root.AssemblyLinearVelocity.Y > 0 then
		return
	end
	local floor = floorBelow(jump.root, STANDING_HEIGHT + FX.landSlackStuds)
	if floor == nil then
		return
	end
	jump.landed = true
	stats.landed += 1
	local facing = facingOf(jump.root)
	MoveVfx.burst(VFX_LAND, CFrame.lookAt(floor, floor + facing), vfxOptions(jump))
	playSound(SOUND_LAND, { at = floor, priority = jump.soundPriority, volume = FX.landVolume })
end

-- One render frame of a double jump. False once it is over (posed out, effects done, landed or timed out).
local function stepJump(jump: Jump): boolean
	if jump.root.Parent == nil then
		return false
	end
	local t = os.clock() - jump.startClock
	applyPose(jump, t)
	local body = jump.body
	if body then
		if t < FX.bodySeconds then
			local p = jump.root.Position
			body:set(CFrame.lookAt(p, p + facingOf(jump.root)))
		else
			jump.body = nil
			body:stop()
		end
	end
	checkLanding(jump, t)
	return t < LIVE_SECONDS or (not jump.landed and t < FX.landWithinSeconds)
end

-- The own jump: the move, the request, the show.
local function tryDoubleJump(): boolean
	local player = localPlayer()
	local character = player.Character
	local root = rootOf(character)
	local humanoid = humanoidOf(character)
	if DoubleJumpController.gate(factsNow(humanoid, root)) ~= nil or character == nil or root == nil or humanoid == nil then
		stats.refused += 1
		return false
	end
	local move = humanoid.MoveDirection
	local flatMove = Vector3.new(move.X, 0, move.Z)
	local key: Key = "F"
	if flatMove.Magnitude >= NO_INPUT then
		key = DashMath.poseKey(flatMove.Unit, root.CFrame.LookVector) :: Key
	end
	local v = root.AssemblyLinearVelocity
	local launch = DoubleJumpController.launchSpeed(Workspace.Gravity, RULES.heightStuds)
	local horizontal = Vector3.new(v.X, 0, v.Z)
	if flatMove.Magnitude >= NO_INPUT then
		horizontal = flatMove.Unit * math.max(humanoid.WalkSpeed, horizontal.Magnitude)
	end
	root.AssemblyLinearVelocity = Vector3.new(horizontal.X, launch, horizontal.Z)
	usedThisAir += 1
	local seq = NetController.nextSeq(REMOTE_REQUEST)
	if NetController.fire(REMOTE_REQUEST, seq, key, Workspace:GetServerTimeNow()) then
		stats.sent += 1
	end
	startJump(player, character, root, key, true)
	return true
end

local function onJumpRequest()
	local now = os.clock()
	local fresh = DoubleJumpController.isFreshPress(now, lastRequestAt)
	lastRequestAt = now
	if fresh then
		tryDoubleJump()
	end
end

local function onDoubleJumped(raw: unknown)
	local payload = DoubleJumpController.parseDoubleJumped(raw)
	if payload == nil or payload.userId == localPlayer().UserId then
		return -- the own jump already plays
	end
	local player = Players:GetPlayerByUserId(payload.userId)
	local character = if player then player.Character else nil
	local root = rootOf(character)
	if player == nil or character == nil or root == nil then
		return
	end
	stats.remote += 1
	startJump(player, character, root, payload.key :: Key, false)
end

-- Tracks the own air time (every render frame).
local function trackAir()
	local humanoid = humanoidOf(localPlayer().Character)
	if humanoid == nil or humanoid.FloorMaterial ~= Enum.Material.Air then
		airborneSince = nil
		usedThisAir = 0
	elseif airborneSince == nil then
		airborneSince = os.clock()
	end
end

local function stepRender(_dt: number, _now: number): boolean
	trackAir()
	for _, jump in jumps do
		if not stepJump(jump) then
			finishJump(jump)
		end
	end
	return true
end

-- Public: state

-- Studio / debug counters.
function DoubleJumpController.counts(): { [string]: any }
	local live = 0
	for _ in jumps do
		live += 1
	end
	return {
		live = live,
		sent = stats.sent,
		refused = stats.refused,
		remote = stats.remote,
		landed = stats.landed,
		usedThisAir = usedThisAir,
		airborne = airborneSince ~= nil,
	}
end

-- Lifecycle

function DoubleJumpController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UserInputService.JumpRequest:Connect(onJumpRequest))
	c:add(NetController.on("DoubleJumped", onDoubleJumped))
	c:add(Scheduler.add(stepRender, "render"))
	c:add(function()
		for _, jump in jumps do
			finishJump(jump)
		end
		table.clear(jumps)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function DoubleJumpController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return DoubleJumpController
