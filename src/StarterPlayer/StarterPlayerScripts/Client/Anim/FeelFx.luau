--!strict
-- FeelFx (client only; 2026-10-28, the physics upgrade). Plays the co-owner's Claude Design timelines
-- (docs/squishy-fx-spec, the pages' CONFIG.moments; ported data in Config.MoveFx) on a character, the way the design's
-- preview engine does (squishy-fx.js exec): every event fires `t` seconds after the run starts, or after the signal
-- named by `on` (Run:signal). Kinds:
--   burst / emit / trail  the VFX Studio templates ReplicatedStorage.SD_MoveVfx.Feel.<name> through Anim/MoveVfx: a
--                         burst once at the anchor, an emitter or trail held on the anchor for `for` seconds (or until a
--                         `stop` event names it); their frame's UpVector is the aim
--   ring                  a flat Part with the kit ring on both faces, Size and Decal transparency eased (follow =
--                         stays on its anchor)
--   pop                   a text BillboardGui (height keys in studs, transparency keys)
--   pose                  a track of R15 joint keys on the character's JointLayer (two alternating override layers, so
--                         a new pose blends in over fadeIn from the old one); the held arm keeps the hold pose
--   dip / shake / fov     the own camera (hooks.camera: MoveFeelController); lines = the own screen speed lines
--   afterimage            Anim/Afterimage ghosts, `count` of them `interval` apart
--   sound                 hooks.sound with the design's sound name (Config.MoveFx.sounds maps it to our keys)
-- views "1P" / "3P" filter what the own camera sees (other characters are always 3P). Anchors and aims are the design's
-- (move.html hooks.anchor / aim): feet (CONFIG.stage.feetLift over the floor), chest (chestHeight over it), backFoot =
-- RightFoot, stepFoot = actor.foot, leadFoot = LeftFoot, the shoulders' joints, slideGround (groundLift, flat along the
-- character's right); aims up, down, back (against actor.dir or the facing), forward, backUp (back tilted backUpAngle up).
-- Cosmetic only, never replicated: everything lives under Workspace.SD_ClientFx.Feel or the PlayerGui.
--
-- API
--   FeelFx.play(events, actor, cfg?) -> Run      cfg = the data tables (default Config.MoveFx)
--   Run:signal(name) / Run:stop() / Run:isDone()
--   FeelFx.setHooks(hooks)                       camera, sound, layerFor, holding, firstPerson (controllers set them)
--   FeelFx.ease(name, u), envelope(...), evalPose(def, t), shakeAt(def, age, phases), flipVariant(def, kind),
--   aimVector(name, dir) (pure, unit-tested); counts(), clear()

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local MoveFxConfig = require(Shared.Config.MoveFx)

local Afterimage = require(script.Parent.Afterimage)
local MoveVfx = require(script.Parent.MoveVfx)
local Scheduler = require(script.Parent.Scheduler)
local Tweens = require(script.Parent.Tweens)

-- Types

export type Actor = {
	character: Model,
	root: BasePart,
	player: Player?,
	own: boolean,
	low: boolean?, -- fewer particles (far players)
	priority: number?, -- sound priority (other players -1)
	dir: Vector3?, -- flat travel direction ("back" = against it); default the facing
	tint: Color3?, -- extra 1: the held squishy's colour (tinted templates and rings)
	floor: Color3?, -- extra 2: the floor's colour (puff templates)
	scale: number?, -- extra 3: particle count multiplier
	foot: string?, -- stepFoot: "Left" | "Right"
	flip: string?, -- doubleFlip's variant (flipVariant)
	soundPitch: number?, -- x every sound's pitch
}

export type Hooks = {
	camera: {
		dip: (spec: any) -> (),
		shake: (spec: any) -> (),
		fov: (spec: any) -> (),
	}?,
	sound: ((name: string, at: Instance | Vector3, priority: number, pitch: number) -> ())?,
	layerFor: ((player: Player) -> any)?,
	holding: ((player: Player) -> boolean)?,
	firstPerson: (() -> boolean)?,
}

type Hold = { name: string, handle: MoveVfx.Handle, ev: any, untilAt: number }

type RunData = {
	actor: Actor,
	cfg: any,
	start: number,
	queue: { { at: number, ev: any } },
	holds: { Hold },
	stopped: boolean,
}

type Ring = {
	part: BasePart,
	decals: { Decal },
	def: any,
	age: number,
	actor: Actor?,
	ev: any,
	color: Color3,
}

type Pop = {
	part: BasePart,
	gui: BillboardGui,
	label: TextLabel,
	stroke: UIStroke,
	def: any,
	age: number,
}

type PoseState = {
	slot: string, -- the layer id the current track writes
	other: string?, -- the layer id still holding the previous track while the new one fades in
	def: any,
	start: number,
	player: Player,
	layer: any,
	mask: { [string]: boolean }?,
}

-- Constants

local FX_FOLDER = "SD_ClientFx"
local OWN_FOLDER = "Feel"
local LIB_PREFIX = "Feel/"
local SLOT_A = "feelA"
local SLOT_B = "feelB"
local RING_THICKNESS = 0.05
local MAX_RINGS = 24
local MAX_POPS = 6
local POP_TOWARD_CAMERA = 2.5 -- studs: BillboardGui.StudsOffset is camera space, +Z comes toward the camera
local MAX_RUNS = 48
local LINES_GUI = "SD_FeelLines"
local LINES_ORDER = 4 -- under the HUD (Diego's HUD layers are higher)
local REF_HEIGHT = 1080
local TAU = 2 * math.pi
local UP = Vector3.yAxis

-- Module table

local FeelFx = {}

-- Private state

local hooks: Hooks = {}
local runs: { [RunData]: boolean } = {}
local rings: { Ring } = {}
local pops: { Pop } = {}
local poses: { [Model]: PoseState } = {}
local lineSets: { { items: { any }, def: any, age: number } } = {}
local stepHandle: any = nil
local folder: Folder? = nil
local linesGui: ScreenGui? = nil
local rng = Random.new()

-- Pure -----------------------------------------------------------------------------------------------------------------

local STYLES: { [string]: Enum.EasingStyle } = {
	Linear = Enum.EasingStyle.Linear,
	Sine = Enum.EasingStyle.Sine,
	Quad = Enum.EasingStyle.Quad,
	Cubic = Enum.EasingStyle.Cubic,
	Quart = Enum.EasingStyle.Quart,
	Quint = Enum.EasingStyle.Quint,
	Exponential = Enum.EasingStyle.Exponential,
	Circular = Enum.EasingStyle.Circular,
	Back = Enum.EasingStyle.Back,
	Elastic = Enum.EasingStyle.Elastic,
	Bounce = Enum.EasingStyle.Bounce,
}
local DIRECTIONS: { [string]: Enum.EasingDirection } = {
	In = Enum.EasingDirection.In,
	Out = Enum.EasingDirection.Out,
	InOut = Enum.EasingDirection.InOut,
}

-- The design's ease(name, u): "Style Direction" (Out when left out), u clamped to [0, 1]; nil / "Linear" = u.
function FeelFx.ease(name: string?, u: number): number
	local x = math.clamp(if u == u then u else 0, 0, 1)
	if name == nil or name == "" or name == "Linear" then
		return x
	end
	if name == "Constant" then
		return if x >= 1 then 1 else 0
	end
	local styleName, dirName = string.match(name, "^(%a+)%s*(%a*)$")
	local style = STYLES[styleName or ""] or Enum.EasingStyle.Linear
	local direction = DIRECTIONS[if dirName and dirName ~= "" then dirName else "Out"] or Enum.EasingDirection.Out
	return TweenService:GetValue(x, style, direction)
end

-- The design's envelope (squishy-fx.js:779): rise over attack, hold, fall over release. 0 after.
function FeelFx.envelope(
	age: number,
	attack: number,
	hold: number,
	release: number,
	attackEasing: string?,
	releaseEasing: string?
): number
	if age < 0 then
		return 0
	end
	if age < attack then
		return FeelFx.ease(attackEasing, age / attack)
	end
	if age < attack + hold then
		return 1
	end
	if release <= 0 then
		return 0
	end
	return 1 - FeelFx.ease(releaseEasing, (age - attack - hold) / release)
end

-- A shake's angles (degrees: pitch, yaw, roll) `age` seconds in (squishy-fx.js:802-803): amplitude x (1 - ease) x the
-- two-sine noise, per-axis weights; `phases` = 6 random radians picked when it started.
function FeelFx.shakeAt(def: any, age: number, phases: { number }, noise: { number }?): Vector3
	if age >= def.time then
		return Vector3.zero
	end
	local n = noise or MoveFxConfig.shakeNoise
	local env = (1 - FeelFx.ease(def.easing, age / def.time)) * def.amplitude
	local w = TAU * def.frequency * age
	local out = { 0, 0, 0 }
	local axes = { def.axes.X, def.axes.Y, def.axes.Z }
	for i = 1, 3 do
		out[i] = env * axes[i] * (n[1] * math.sin(w + phases[i]) + n[2] * math.sin(w * n[3] + phases[i + 3]))
	end
	return Vector3.new(out[1], out[2], out[3])
end

local function wrap180(d: number): number
	return (d + 180) % 360 - 180
end

-- A pose track's joints at `t` (squishy-fx.js evalTrack): the key pair around t, eased by the earlier key's easing,
-- each angle the short way round (wrap180), rootPos linearly. Returns ({ [joint]: degrees }, rootPos, past the end).
function FeelFx.evalPose(def: any, t: number): ({ [string]: Vector3 }, Vector3, boolean)
	local keys = def.keys
	local keyed: { [string]: boolean } = {}
	local hasRootPos = false
	for _, key in keys do
		for joint in key.joints do
			keyed[joint] = true
		end
		if key.rootPos then
			hasRootPos = true
		end
	end
	local i = 1
	while i < #keys and t >= keys[i + 1].t do
		i += 1
	end
	local a = keys[i]
	local b = keys[math.min(i + 1, #keys)]
	local u = if a == b then 1 else FeelFx.ease(a.easing, (t - a.t) / (b.t - a.t))
	local out: { [string]: Vector3 } = {}
	for joint in keyed do
		local from = a.joints[joint] or Vector3.zero
		local to = b.joints[joint] or Vector3.zero
		out[joint] = Vector3.new(
			from.X + wrap180(to.X - from.X) * u,
			from.Y + wrap180(to.Y - from.Y) * u,
			from.Z + wrap180(to.Z - from.Z) * u
		)
	end
	local rootPos = Vector3.zero
	if hasRootPos then
		local ra = a.rootPos or Vector3.zero
		local rb = b.rootPos or Vector3.zero
		rootPos = ra:Lerp(rb, u)
	end
	return out, rootPos, t > keys[#keys].t
end

-- Extra 5 (NOT IN DESIGN): the double jump's flip turned onto another Root axis. "front" = the design's forward flip,
-- "back" = mirrored (+X), "left" / "right" = a side flip about Z, "spin" = a twirl about Y. Only the Root's angles move.
function FeelFx.flipVariant(def: any, kind: string?): any
	if kind == nil or kind == "front" then
		return def
	end
	local keys = {}
	for _, key in def.keys do
		local joints = table.clone(key.joints)
		local root = joints.Root
		if root then
			local a = root.X -- the design's forward turn (0 -> -360)
			joints.Root = if kind == "back"
				then Vector3.new(-a, 0, 0)
				elseif kind == "left" then Vector3.new(0, 0, -a)
				elseif kind == "right" then Vector3.new(0, 0, a)
				else Vector3.new(0, a, 0)
		end
		local copy = table.clone(key)
		copy.joints = joints
		table.insert(keys, copy)
	end
	local out = table.clone(def)
	out.keys = keys
	return out
end

-- A world aim: up, down, back (against `dir`), forward, backUp (back tilted `backUpAngle` degrees up), else up.
function FeelFx.aimVector(name: string?, dir: Vector3, backUpAngle: number?): Vector3
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local forward = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	if name == "down" then
		return -UP
	elseif name == "back" then
		return -forward
	elseif name == "forward" then
		return forward
	elseif name == "backUp" then
		local k = math.rad(backUpAngle or MoveFxConfig.stage.backUpAngle)
		return (-forward * math.cos(k) + UP * math.sin(k)).Unit
	end
	return UP
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function ownFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local fx = Workspace:FindFirstChild(FX_FOLDER)
	if fx == nil then
		local made = Instance.new("Folder")
		made.Name = FX_FOLDER
		made.Parent = Workspace
		fx = made
	end
	local own = (fx :: Instance):FindFirstChild(OWN_FOLDER)
	if own == nil or not own:IsA("Folder") then
		local made = Instance.new("Folder")
		made.Name = OWN_FOLDER
		made.Parent = fx
		own = made
	end
	folder = own :: Folder
	return own :: Folder
end

local function phone(): boolean
	return UserInputService.PreferredInput == Enum.PreferredInput.Touch
end

local function partOf(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)
	return if part and part:IsA("BasePart") then part else nil
end

local function facingOf(actor: Actor): Vector3
	local d = actor.dir
	if d and Vector3.new(d.X, 0, d.Z).Magnitude > 1e-3 then
		return Vector3.new(d.X, 0, d.Z).Unit
	end
	local look = actor.root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
end

-- The floor height under the character: the HRP less its hip height and half its own height.
local function feetY(actor: Actor): number
	local humanoid = actor.character:FindFirstChildOfClass("Humanoid")
	local hip = if humanoid then humanoid.HipHeight else 2
	return actor.root.Position.Y - hip - actor.root.Size.Y / 2
end

local function jointPosition(actor: Actor, partName: string, jointName: string): Vector3?
	local part = partOf(actor.character, partName)
	local joint = if part then part:FindFirstChild(jointName) else nil
	if joint and joint:IsA("Motor6D") and joint.Part1 then
		return (joint.Part1.CFrame * joint.C1).Position
	end
	return if part then part.Position else nil
end

-- An anchor's world position and (for slideGround) its side axis.
local function anchorOf(actor: Actor, name: string?): (Vector3, Vector3?)
	local stage = MoveFxConfig.stage
	local p = actor.root.Position
	local floor = feetY(actor)
	if name == "feet" then
		return Vector3.new(p.X, floor + stage.feetLift, p.Z), nil
	elseif name == "chest" then
		return Vector3.new(p.X, floor + stage.chestHeight, p.Z), nil
	elseif name == "slideGround" then
		local forward = facingOf(actor)
		return Vector3.new(p.X, floor + stage.groundLift, p.Z), forward:Cross(UP)
	elseif name == "backFoot" or name == "stepFoot" or name == "leadFoot" then
		local side = if name == "backFoot" then "Right" elseif name == "leadFoot" then "Left" else (actor.foot or "Right")
		local foot = partOf(actor.character, side .. "Foot") or partOf(actor.character, side .. " Leg")
		if foot then
			return Vector3.new(foot.Position.X, math.max(foot.Position.Y - foot.Size.Y / 2, floor) + stage.feetLift, foot.Position.Z),
				nil
		end
		return Vector3.new(p.X, floor + stage.feetLift, p.Z), nil
	elseif name == "leftShoulder" or name == "rightShoulder" then
		local side = if name == "leftShoulder" then "Left" else "Right"
		local at = jointPosition(actor, side .. "UpperArm", side .. "Shoulder")
		return at or p, nil
	end
	return p, nil
end

-- A frame at `at` whose UpVector is `up` (the templates emit from their Top) and whose LookVector is as close to
-- `look` as it can be.
local function frameUp(at: Vector3, up: Vector3, look: Vector3): CFrame
	local u = if up.Magnitude > 1e-3 then up.Unit else UP
	local right = look:Cross(u)
	if right.Magnitude < 1e-3 then
		right = Vector3.xAxis:Cross(u)
		if right.Magnitude < 1e-3 then
			right = Vector3.zAxis:Cross(u)
		end
	end
	right = right.Unit
	return CFrame.fromMatrix(at, right, u)
end

local function vfxOptions(actor: Actor): MoveVfx.Options
	local onPhone = phone()
	return {
		tint = actor.tint,
		floor = actor.floor,
		low = actor.low,
		scale = (actor.scale or 1) * (if onPhone then MoveFxConfig.phone.countShare else 1),
		trailScale = if onPhone then MoveFxConfig.phone.trailLifetimeScale else 1,
	}
end

-- Templates whose Cylinder stands along their X axis (FeelVfxBuilder's SD_AxisX): their X goes onto the aim.
local axisX: { [string]: boolean } = {}
local TURN_X_UP = CFrame.Angles(0, 0, math.rad(90))
local function standsOnX(name: string?): boolean
	if name == nil then
		return false
	end
	local known = axisX[name]
	if known == nil then
		local lib = ReplicatedStorage:FindFirstChild("SD_MoveVfx")
		local feel = lib and lib:FindFirstChild("Feel")
		local template = feel and feel:FindFirstChild(name)
		known = template ~= nil and template:GetAttribute("SD_AxisX") == true
		axisX[name] = known
	end
	return known
end

local function eventFrame(actor: Actor, ev: any): CFrame
	local at, side = anchorOf(actor, ev.at)
	local forward = facingOf(actor)
	if side then
		return CFrame.fromMatrix(at, side, UP) -- the slide's flat trail: its attachments lie along X
	end
	local frame = frameUp(at, FeelFx.aimVector(ev.aim, forward), forward)
	if standsOnX(ev.burst or ev.emit) then
		frame *= TURN_X_UP
	end
	return frame
end

local function seen(actor: Actor, ev: any): boolean
	local views = ev.views
	if views == nil then
		return true
	end
	local view = "3P"
	if actor.own and hooks.firstPerson and hooks.firstPerson() then
		view = "1P"
	end
	return table.find(views, view) ~= nil
end

-- Rings ------------------------------------------------------------------------------------------------------------------

local ringTexture: string? = nil
local function ringContent(): string?
	if ringTexture == nil then
		ringTexture = AssetTable.image("img.kit.ring") or ""
	end
	return if ringTexture ~= "" then ringTexture else nil
end

local function ringFrame(actor: Actor, ev: any): CFrame
	local at = anchorOf(actor, ev.at)
	local forward = facingOf(actor)
	local normal = if ev.face == "back" then -forward elseif ev.face == "forward" then forward else UP
	return frameUp(at, normal, forward)
end

local function startRing(actor: Actor, ev: any, def: any)
	local texture = ringContent()
	if texture == nil or #rings >= MAX_RINGS then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Ring"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(def.sizeStart, RING_THICKNESS, def.sizeStart)
	part.CFrame = ringFrame(actor, ev)
	local color = if def.tinted and actor.tint then actor.tint else def.color
	local decals = {}
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local decal = Instance.new("Decal")
		decal.Texture = texture
		decal.Face = face
		decal.Color3 = color
		decal.Transparency = def.transparencyStart
		decal.Parent = part
		table.insert(decals, decal)
	end
	part.Parent = ownFolder()
	table.insert(rings, {
		part = part,
		decals = decals,
		def = def,
		age = 0,
		actor = if def.follow then actor else nil,
		ev = ev,
		color = color,
	})
end

local function stepRing(ring: Ring, dt: number): boolean
	ring.age += dt
	local d = ring.def
	local u = ring.age / d.time
	if u >= 1 or ring.part.Parent == nil then
		ring.part:Destroy()
		return false
	end
	local s = d.sizeStart + (d.sizeEnd - d.sizeStart) * FeelFx.ease(d.easing, u)
	ring.part.Size = Vector3.new(math.max(s, 0.05), RING_THICKNESS, math.max(s, 0.05))
	local transparency = d.transparencyStart
		+ (d.transparencyEnd - d.transparencyStart) * FeelFx.ease(d.transparencyEasing, u)
	for _, decal in ring.decals do
		decal.Transparency = transparency
	end
	local actor = ring.actor
	if actor and actor.root.Parent then
		ring.part.CFrame = ringFrame(actor, ring.ev)
	end
	return true
end

-- Text pops ----------------------------------------------------------------------------------------------------------------

local function seqAt(keys: { { number } }, t: number): number
	if t <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, #keys do
		local b = keys[i]
		if t <= b[1] then
			local a = keys[i - 1]
			local span = b[1] - a[1]
			return a[2] + (b[2] - a[2]) * (if span > 0 then (t - a[1]) / span else 1)
		end
	end
	return keys[#keys][2]
end
FeelFx.seqAt = seqAt

local function startPop(actor: Actor, ev: any, def: any)
	if #pops >= MAX_POPS then
		return
	end
	local at = anchorOf(actor, ev.at) + def.offset
	local part = Instance.new("Part")
	part.Name = "Pop"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(at)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Text"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Size = UDim2.fromScale(0, 0)
	gui.StudsOffset = Vector3.new(0, 0, POP_TOWARD_CAMERA) -- in front of the body, so the text is never hidden by it
	gui.Adornee = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = def.text
	label.TextColor3 = def.color
	label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	label.TextScaled = true
	local stroke = Instance.new("UIStroke")
	stroke.Color = def.stroke
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = part
	part.Parent = ownFolder()
	table.insert(pops, { part = part, gui = gui, label = label, stroke = stroke, def = def, age = 0 })
end

local function stepPop(pop: Pop, dt: number, camera: Camera?): boolean
	pop.age += dt
	local d = pop.def
	if pop.age >= d.time or pop.part.Parent == nil then
		pop.part:Destroy()
		return false
	end
	local canvas = MoveFxConfig.textCanvas
	local h = math.max(seqAt(d.size, pop.age), 0)
	pop.gui.Size = UDim2.new(h * canvas.aspect, 0, h, 0)
	local transparency = math.clamp(seqAt(d.transparency, pop.age), 0, 1)
	pop.label.TextTransparency = transparency
	pop.stroke.Transparency = transparency
	-- The stroke is the design's share of the text height, in screen pixels (UIStroke does not scale with distance).
	if camera then
		local distance = math.max((camera.CFrame.Position - pop.part.Position).Magnitude, 1)
		local pixels = h / (2 * distance * math.tan(math.rad(camera.FieldOfView) / 2)) * camera.ViewportSize.Y
		pop.stroke.Thickness = math.clamp(pixels * canvas.fontShare * canvas.strokeShare, 0, 12)
	end
	return true
end

-- Screen speed lines -------------------------------------------------------------------------------------------------------

local lineTexture: string? = nil
local function linesParent(): ScreenGui?
	local current = linesGui
	if current and current.Parent then
		return current
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = LINES_GUI
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = LINES_ORDER
	gui.Parent = playerGui
	linesGui = gui
	return gui
end

local function rr(range: { number }): number
	return range[1] + rng:NextNumber() * (range[2] - range[1])
end

local function startLines(def: any)
	local gui = linesParent()
	if lineTexture == nil then
		lineTexture = AssetTable.image("img.kit.speedline") or ""
	end
	local camera = Workspace.CurrentCamera
	if gui == nil or lineTexture == "" or camera == nil then
		return
	end
	local n = def.count
	if phone() then
		n = math.ceil(n * MoveFxConfig.phone.countShare)
	end
	local view = camera.ViewportSize
	local k = view.Y / REF_HEIGHT
	local items = {}
	for i = 1, n do
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Image = lineTexture
		image.ImageColor3 = def.color
		image.ImageTransparency = 1
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		local len, wid = rr(def.lengthPx) * k, rr(def.widthPx) * k
		image.Size = UDim2.fromOffset(wid, len)
		image.Parent = gui
		table.insert(items, {
			image = image,
			a = (i - 1) / n * TAU + math.rad(rr({ -def.jitter, def.jitter })),
			r0 = rr({ def.inner, def.outer }),
			delay = rng:NextNumber() * def.stagger,
		})
	end
	table.insert(lineSets, { items = items, def = def, age = 0 })
end

local function stepLines(set: any, dt: number, camera: Camera?): boolean
	set.age += dt
	local def = set.def
	local done = set.age >= def.time + def.stagger
	local view = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local cx, cy = view.X / 2, view.Y / 2
	local radius = math.sqrt(cx * cx + cy * cy)
	for _, it in set.items do
		if done then
			it.image:Destroy()
			continue
		end
		local u = math.clamp((set.age - it.delay) / def.time, 0, 1)
		local r = (it.r0 - def.travel * FeelFx.ease(def.easing, u)) * radius
		it.image.Position = UDim2.fromOffset(cx + math.cos(it.a) * r, cy + math.sin(it.a) * r)
		it.image.Rotation = math.deg(it.a) - 90
		local opacity = if set.age < it.delay then 0 else def.opacity * (1 - FeelFx.ease(def.fadeEasing, u))
		it.image.ImageTransparency = 1 - opacity
	end
	return not done
end

-- Poses -------------------------------------------------------------------------------------------------------------------

local function poseFrames(def: any, t: number, mask: { [string]: boolean }?): ({ [string]: CFrame }, boolean)
	local degrees, rootPos, past = FeelFx.evalPose(def, t)
	local frames: { [string]: CFrame } = {}
	for joint, d in degrees do
		if mask and mask[joint] then
			continue
		end
		local cf = CFrame.Angles(math.rad(d.X), math.rad(d.Y), math.rad(d.Z))
		if joint == "Root" then
			cf = CFrame.new(rootPos) * cf
		end
		frames[joint] = cf
	end
	if frames.Root == nil and rootPos.Magnitude > 0 then
		frames.Root = CFrame.new(rootPos)
	end
	return frames, past
end

local function poseWeight(def: any, t: number): number
	local w = if def.fadeIn and def.fadeIn > 0 then math.clamp(t / def.fadeIn, 0, 1) else 1
	if not def.hold then
		local last = def.keys[#def.keys].t
		if t > last then
			local out = def.fadeOut or 0
			w = if out > 0 then w * math.clamp(1 - (t - last) / out, 0, 1) else 0
		end
	end
	return w
end

local function heldMask(player: Player): { [string]: boolean }?
	if hooks.holding and hooks.holding(player) then
		local mask = {}
		for _, joint in MoveFxConfig.heldArmJoints do
			mask[joint] = true
		end
		return mask
	end
	return nil
end

local function startPose(actor: Actor, def: any, cfg: any)
	local player = actor.player
	if player == nil or hooks.layerFor == nil then
		return
	end
	local layer = hooks.layerFor(player)
	if layer == nil or not layer:isReady() or layer:getRig() ~= "R15" then
		return
	end
	local old = poses[actor.character]
	local slot = SLOT_A
	local other: string? = nil
	if old then
		if old.other and layer:has(old.other) then
			layer:clear(old.other)
		end
		slot = if old.slot == SLOT_A then SLOT_B else SLOT_A
		other = old.slot -- keeps its last frames under the new track while that fades in
	end
	if layer:has(slot) then
		layer:clear(slot)
	end
	poses[actor.character] = {
		slot = slot,
		other = other,
		def = def,
		start = os.clock(),
		player = player,
		layer = layer,
		mask = heldMask(player),
	}
	local priority = cfg.posePriority or MoveFxConfig.posePriority
	local frames = poseFrames(def, 0, poses[actor.character].mask)
	layer:setFrames(slot, frames, poseWeight(def, 0), priority)
end

local function stepPose(character: Model, state: PoseState): boolean
	local layer = state.layer
	if character.Parent == nil or layer == nil then
		return false
	end
	local t = os.clock() - state.start
	local def = state.def
	local w = poseWeight(def, t)
	local frames, past = poseFrames(def, t, state.mask)
	local done = past and not def.hold and w <= 0
	if done then
		if layer:has(state.slot) then
			layer:clear(state.slot)
		end
		local other = state.other
		if other and layer:has(other) then
			layer:clear(other)
		end
		return false
	end
	layer:setFrames(state.slot, frames, w, MoveFxConfig.posePriority)
	local other = state.other
	if other and w >= 1 then
		if layer:has(other) then
			layer:clear(other) -- the new track is in full: the old one goes
		end
		state.other = nil
	end
	return true
end

-- Ends a character's feel pose at once (a respawn, a knockout, a stance the caller takes over).
function FeelFx.clearPose(character: Model)
	local state = poses[character]
	if state == nil then
		return
	end
	poses[character] = nil
	for _, id in { state.slot, state.other } do
		if id and state.layer and state.layer:has(id) then
			state.layer:clear(id)
		end
	end
end

-- The pose a character's feel layer plays now (its def), or nil.
function FeelFx.currentPose(character: Model): any
	local state = poses[character]
	return if state then state.def else nil
end

-- Events -------------------------------------------------------------------------------------------------------------------

local function stopNamed(run: RunData, name: string)
	for _, hold in run.holds do
		if hold.name == name then
			hold.untilAt = 0
		end
	end
end

local function startHold(run: RunData, ev: any, name: string)
	local actor = run.actor
	local handle = MoveVfx.hold(LIB_PREFIX .. name, vfxOptions(actor))
	if handle == nil then
		return
	end
	handle:set(eventFrame(actor, ev))
	handle:setOn(true)
	local seconds = if ev["for"] then ev["for"] else math.huge
	table.insert(run.holds, { name = name, handle = handle, ev = ev, untilAt = os.clock() + seconds })
end

local function fire(run: RunData, ev: any)
	local actor = run.actor
	local cfg = run.cfg
	if not seen(actor, ev) then
		return
	end
	if ev.burst then
		MoveVfx.burst(LIB_PREFIX .. ev.burst, eventFrame(actor, ev), vfxOptions(actor))
	elseif ev.emit then
		startHold(run, ev, ev.emit)
	elseif ev.trail then
		startHold(run, ev, ev.trail)
	elseif ev.stop then
		stopNamed(run, ev.stop)
	elseif ev.ring then
		local def = cfg.rings[ev.ring]
		if def then
			startRing(actor, ev, def)
		end
	elseif ev.pop then
		local def = cfg.texts[ev.pop]
		if def then
			startPop(actor, ev, def)
		end
	elseif ev.pose then
		local def = cfg.poses[ev.pose]
		if def then
			if ev.pose == "doubleFlip" and actor.flip then
				def = FeelFx.flipVariant(def, actor.flip)
			end
			startPose(actor, def, cfg)
		end
	elseif ev.dip or ev.shake or ev.fov then
		local camera = hooks.camera
		if actor.own and camera then
			if ev.dip and cfg.dips[ev.dip] then
				camera.dip(cfg.dips[ev.dip])
			elseif ev.shake and cfg.shakes[ev.shake] then
				camera.shake(cfg.shakes[ev.shake])
			elseif ev.fov and cfg.fovs[ev.fov] then
				camera.fov(cfg.fovs[ev.fov])
			end
		end
	elseif ev.lines then
		local def = cfg.lines[ev.lines]
		if def and actor.own and not Tweens.reducedMotion() then
			startLines(def)
		end
	elseif ev.afterimage then
		local def = cfg.afterimages[ev.afterimage]
		if def then
			local n = if phone() then math.ceil(def.count * MoveFxConfig.phone.countShare) else def.count
			for i = 0, n - 1 do
				task.delay(i * def.interval, function()
					if actor.character.Parent then
						Afterimage.spawn(actor.character, def.color, {
							transparency = def.transparencyStart,
							seconds = def.time,
						})
					end
				end)
			end
		end
	elseif ev.sound then
		local sound = hooks.sound
		if sound then
			local at: Instance | Vector3 = if ev.at then anchorOf(actor, ev.at) else actor.root
			sound(ev.sound, at, actor.priority or (if actor.own then 0 else -1), actor.soundPitch or 1)
		end
	end
end

local function stepRun(run: RunData, now: number): boolean
	if run.stopped or run.actor.root.Parent == nil then
		for _, hold in run.holds do
			hold.handle:stop()
		end
		run.holds = {}
		return false
	end
	local i = 1
	while i <= #run.queue do
		local item = run.queue[i]
		if now >= item.at then
			table.remove(run.queue, i)
			fire(run, item.ev)
		else
			i += 1
		end
	end
	local j = 1
	while j <= #run.holds do
		local hold = run.holds[j]
		if now >= hold.untilAt then
			hold.handle:stop()
			table.remove(run.holds, j)
		else
			hold.handle:set(eventFrame(run.actor, hold.ev))
			j += 1
		end
	end
	return true
end

local function step(dt: number, now: number): boolean
	local clock = os.clock()
	for run in runs do
		if not stepRun(run, clock) then
			runs[run] = nil
		end
	end
	local k = 1
	while k <= #rings do
		if stepRing(rings[k], dt) then
			k += 1
		else
			table.remove(rings, k)
		end
	end
	local camera = Workspace.CurrentCamera
	local m = 1
	while m <= #pops do
		if stepPop(pops[m], dt, camera) then
			m += 1
		else
			table.remove(pops, m)
		end
	end
	local n = 1
	while n <= #lineSets do
		if stepLines(lineSets[n], dt, camera) then
			n += 1
		else
			table.remove(lineSets, n)
		end
	end
	for character, state in poses do
		if not stepPose(character, state) then
			if poses[character] == state then
				poses[character] = nil
			end
		end
	end
	return true
end

local function ensureStep()
	if stepHandle == nil then
		stepHandle = Scheduler.add(step, "render")
	end
end

-- Runs ----------------------------------------------------------------------------------------------------------------------

local RunClass = {}
RunClass.__index = RunClass

-- Queues the events waiting for signal `name` (t counts from now). A run that is over ignores it.
function RunClass.signal(self: any, name: string)
	if self.stopped then
		return
	end
	local now = os.clock()
	local queued = false
	for _, ev in self.events do
		if ev.on == name then
			table.insert(self.queue, { at = now + (ev.t or 0), ev = ev })
			queued = true
		end
	end
	if queued then
		runs[self] = true
		ensureStep()
		stepRun(self, now) -- t = 0 events fire this frame
	end
end

-- Stops the run's held emitters and trails now (their particles fade on their own); poses play on.
function RunClass.stop(self: any)
	self.stopped = true
	for _, hold in self.holds do
		hold.handle:stop()
	end
	self.holds = {}
	runs[self] = nil
end

function RunClass.isDone(self: any): boolean
	return self.stopped or (#self.queue == 0 and #self.holds == 0)
end

function FeelFx.play(events: { any }, actor: Actor, cfg: any?): any
	local run = setmetatable({
		actor = actor,
		cfg = cfg or MoveFxConfig,
		events = events,
		start = os.clock(),
		queue = {},
		holds = {},
		stopped = false,
	}, RunClass)
	local count = 0
	for _ in runs do
		count += 1
	end
	if count >= MAX_RUNS then
		run.stopped = true
		return run
	end
	for _, ev in events do
		if ev.on == nil then
			table.insert(run.queue, { at = run.start + (ev.t or 0), ev = ev })
		end
	end
	runs[run :: any] = true
	ensureStep()
	stepRun(run :: any, run.start)
	return run
end

function FeelFx.setHooks(new: Hooks)
	for key, value in new :: any do
		(hooks :: any)[key] = value
	end
end

function FeelFx.counts(): { [string]: number }
	local live, posed = 0, 0
	for _ in runs do
		live += 1
	end
	for _ in poses do
		posed += 1
	end
	return { runs = live, rings = #rings, pops = #pops, lines = #lineSets, poses = posed }
end

function FeelFx.clear()
	for run in runs do
		(run :: any):stop()
	end
	table.clear(runs)
	for _, ring in rings do
		ring.part:Destroy()
	end
	table.clear(rings)
	for _, pop in pops do
		pop.part:Destroy()
	end
	table.clear(pops)
	for _, set in lineSets do
		for _, it in set.items do
			it.image:Destroy()
		end
	end
	table.clear(lineSets)
	for character in poses do
		FeelFx.clearPose(character)
	end
end

return FeelFx
