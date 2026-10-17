--!strict
-- ViewportStage (client only). DESIGN §10.2 (one viewport stage, created lazily once and reused by Inspect and the box
-- reveal), §10.5 (framing, orbit, camera-locked key light, background), §9.11 (the box reveal "uses the Inspect
-- viewport stage"), §9.15 (one animated viewport), §9.12 / §18.1 #4 (no lights, no Neon, no Highlight, no Sky, no
-- shadows, never a white flash).
-- Reading (§10.2 puts ViewportStage inside InspectController, which is Part 6 and not built yet): the stage is its own
-- UI module, so the box reveal (Part 7) uses it now and Inspect (Part 6) adopts the same one.
--   local stage = ViewportStage.get()     -- created on first use and kept for the session
--   stage:attach(container)               -- fills `container`; the key light and the contact shadow follow the camera
--                                         -- every frame (one Scheduler render effect) while attached
--   stage:setModel(model, widening?)      -- parents a SquishyCache "Viewport" clone and frames it (rest pose; widening
--                                         -- = the toy's own squeeze widening, else Framing.squeezeWidening)
--   stage:setView(yawDeg, pitchDeg, zoom?) -- the orbit camera: the camera moves, the model only deforms
--   stage:takeModel()                     -- hands the model over (unparented, no longer owned; e.g. box result ->
--                                         -- Inspect without a rebuild) / clearModel() destroys it and every prop
--   stage:detach()                        -- Visible = false and unparented: renders nothing; the stage is kept
-- Scene (§10.2, §10.5): a ViewportFrame with a Camera as CurrentCamera (FieldOfView = Config.Inspect.Framing.vFovDeg,
-- vertical), no WorldModel (deformation writes mesh properties; taps are analytic), LightColor and Ambient from
-- Config.Inspect.Lighting, LightDirection = cam.CFrame:VectorToWorldSpace(lightDirection.Unit) every frame. Behind the
-- model: the UIGradient #EFE7FA -> #FFF4E6 (Config.Inspect.Background), a soft white ellipse (Transparency 0.6) at the
-- model centre, an optional glow (setGlow) and a back layer for the caller's frames (the reveal's light rays); under
-- the model a 2D contact shadow (Ink at 85% transparency, UICorner) that widens with setShadowWiden; around it a
-- UIStroke in the rarity colour (setRarity; the panel stroke without one); above the viewport a front layer (confetti).
-- Foam UI restyle (spec 2026-10-09; look only): the neutral frame is the InkUI foam outline (Theme.Stroke.ink) and a
-- rarity keeps its colour at Theme.Stroke.thick (the cards' "rarity rim"); the corners are the tile radius; the
-- contact shadow is InkUI.
-- UI FINAL R5 (plan work/ui/PLAN.md R5): a container with the attribute SD_OwnBackdrop = true draws its own backdrop
-- (UI/StageLook: the design's Inspect stage): attached there the stage leaves out its background, its white ellipse
-- and its outline (the model, the contact shadow and the layers stay); attached anywhere else it draws them as before.
-- Framing (§10.5): r = size.Magnitude/2 × squeezeWidening; hFov = 2·atan(tan(vFov/2)·aspect) from the frame's
-- AbsoluteSize; fitDist = r / sin(min(vFov, hFov)/2) × fitPadding; dist = fitDist × zoom, never closer than
-- r + minClearance; recomputed on AbsoluteSize changes. Squishy overhaul (spec 2026-10-09 §3.2): a model framed with
-- its own widening (Inspect: SquishRig.framingWidening) uses that in place of squeezeWidening.
-- Reading (§10.5 orbit): DESIGN writes CFrame.fromEulerAnglesYXZ(−pitch, yaw, 0); with the camera placed at
-- centre + dir·dist that puts it BELOW the model for a positive pitch, while Catalog's default pitch (12°) and
-- StaticIcon.viewDirection mean "from above". orbitCFrame uses +pitch (from above), the same direction as StaticIcon.
-- UI FINAL R7 (the box reveal's full-screen stage, plan work/ui/PLAN.md R7 G7.1, G7.8): stage:setManualCamera(cframe,
-- fovDeg, lightDirection, ambient, lightColor) pins the camera where the caller puts it (the design's fixed camera and
-- its orbit, set again by the caller each frame): the fit and the orbit leave it alone, the key light keeps
-- lightDirection in world space (stage:40) and the viewport takes ambient / lightColor; resetLook() (and a new
-- setModel's caller) goes back to the fit, the Inspect lighting and Framing.vFovDeg.
-- Pure, unit-tested in Edit mode: fitDistance, orbitCFrame, projectPoint, lightDirection.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local RarityStyle = require(Shared.Art.RarityStyle)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)

-- Types

-- The Config.Inspect.Framing values the fit uses.
export type FitConfig = {
	squeezeWidening: number,
	fitPadding: number,
	minClearance: number,
}

-- What the camera frames: the model's rest bounding box.
export type Framing = {
	center: Vector3, -- the point the camera orbits (bounding-box centre)
	size: Vector3, -- the bounding box size, in the box's own axes
	radius: number, -- size.Magnitude/2 × squeezeWidening
	pivotRotation: CFrame, -- the model pivot's rotation: yaw 0 / pitch 0 looks at the face (its -Z)
	widening: number?, -- the squeeze widening framed (nil = Config.Inspect.Framing.squeezeWidening)
}

export type Stage = {
	root: Frame,
	viewport: ViewportFrame,
	camera: Camera,
	back: Frame, -- a layer behind the model for the caller's frames (cleared by clearLayers)
	front: Frame, -- a layer above the model (confetti), cleared by clearLayers
	attach: (self: Stage, container: GuiObject) -> boolean,
	detach: (self: Stage) -> (),
	isAttached: (self: Stage) -> boolean,
	setModel: (self: Stage, model: Model, widening: number?) -> Framing,
	takeModel: (self: Stage) -> Model?,
	clearModel: (self: Stage) -> (),
	model: (self: Stage) -> Model?,
	addProp: (self: Stage, model: Model) -> (),
	removeProp: (self: Stage, model: Model, destroy: boolean?) -> (),
	setFraming: (self: Stage, framing: Framing) -> (),
	framing: (self: Stage) -> Framing?,
	setView: (self: Stage, yawDeg: number, pitchDeg: number, zoom: number?) -> (),
	view: (self: Stage) -> (number, number, number),
	distance: (self: Stage) -> number,
	setRarity: (self: Stage, rarity: string?) -> (),
	setGlow: (self: Stage, color: Color3?, opacity: number) -> (),
	setTint: (self: Stage, color: Color3?, amount: number) -> (),
	setShadowWiden: (self: Stage, factor: number) -> (),
	setManualCamera: (
		self: Stage,
		cframe: CFrame,
		fovDeg: number,
		lightDirection: Vector3,
		ambient: Color3,
		lightColor: Color3
	) -> (),
	resetLook: (self: Stage) -> (),
	clearLayers: (self: Stage) -> (),
	isAlive: (self: Stage) -> boolean,
	destroy: (self: Stage) -> (),
}

-- Constants

local INSPECT = Config.Inspect
local FRAMING = INSPECT.Framing
local LIGHTING = INSPECT.Lighting
local BACKGROUND = INSPECT.Background
local ORBIT = INSPECT.Orbit
local GRADIENT_FROM = Color3.fromHex(BACKGROUND.gradientFrom)
local GRADIENT_TO = Color3.fromHex(BACKGROUND.gradientTo)
local GRADIENT_ROTATION = 90 -- top (gradientFrom) to bottom (gradientTo)
local ELLIPSE_SCALE = 0.62 -- reading: the soft white ellipse covers this share of the frame height, at the centre
local GLOW_SCALE = 0.9 -- reading: the glow ellipse is wider than the white one
local SHADOW_HEIGHT_SHARE = 0.22 -- reading: the contact shadow is an ellipse this many times as tall as it is wide
local SHADOW_MIN_WIDTH = 0.02 -- below this share of the frame width the shadow hides
local STROKE_PX = Theme.Stroke.thick -- a rarity rim
local NEUTRAL_STROKE_PX = Theme.Stroke.ink -- the foam ink outline without a rarity
local DEFAULT_ASPECT = 1
local EPSILON = 1e-4

-- Module table

local ViewportStage = {}

-- Private

local log = Log.new("ViewportStage")
local shared: Stage? = nil

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function positive(n: unknown, fallback: number): number
	if finite(n) and (n :: number) > 0 then
		return n :: number
	end
	return fallback
end

-- Public: pure maths (unit-tested) -------------------------------------------------------------------------------------

-- The camera distance that frames a bounding box of `size` (§10.5): r = size.Magnitude/2 × squeezeWidening, hFov from
-- the aspect (width / height), fitDist = r / sin(min(vFov, hFov)/2) × fitPadding, never closer than r + minClearance.
-- A bad size gives r = 1 (like StaticIcon), a bad aspect counts as 1, a bad FOV as Config.Inspect.Framing.vFovDeg.
-- Returns (distance, r).
function ViewportStage.fitDistance(size: Vector3, vFovDeg: number, aspect: number, cfg: FitConfig?): (number, number)
	local c: FitConfig = cfg or FRAMING
	local magnitude = if typeof(size) == "Vector3" then size.Magnitude else 0
	local r = positive(magnitude / 2 * c.squeezeWidening, 1)
	local vFov = math.rad(math.clamp(positive(vFovDeg, FRAMING.vFovDeg), 1, 179))
	local a = positive(aspect, DEFAULT_ASPECT)
	local hFov = 2 * math.atan(math.tan(vFov / 2) * a)
	local half = math.min(vFov, hFov) / 2
	local distance = r / math.sin(half) * c.fitPadding
	return math.max(distance, r + c.minClearance), r
end

-- The orbit camera (§10.5): dir = (pivotRotation · fromEulerAnglesYXZ(pitch, yaw, 0)).LookVector, the camera at
-- center + dir·dist looking at center. Yaw 0 / pitch 0 = in front of the face (the pivot's -Z side); a positive yaw
-- turns toward the model's own left (-X), a positive pitch looks from above (see the header's reading).
function ViewportStage.orbitCFrame(
	center: Vector3,
	pivotRotation: CFrame,
	yawDeg: number,
	pitchDeg: number,
	dist: number
): CFrame
	local yaw = math.rad(if finite(yawDeg) then yawDeg else 0)
	local pitch = math.rad(math.clamp(if finite(pitchDeg) then pitchDeg else 0, -89, 89))
	local dir = (pivotRotation.Rotation * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0)).LookVector
	local eye = center + dir * positive(dist, 1)
	-- Built from the axes (as CFrame.lookAt would, up = the pivot's up), so the result never depends on lookAt.
	local look = (center - eye).Unit
	local up = pivotRotation.UpVector
	local right = look:Cross(up)
	if right.Magnitude < EPSILON then
		right = look:Cross(pivotRotation.LookVector)
	end
	right = right.Unit
	return CFrame.fromMatrix(eye, right, right:Cross(look))
end

-- Where a world point lands in a view (frame scale: (0, 0) top-left, (1, 1) bottom-right), for a camera at
-- `cameraCFrame` with vertical FOV `vFovDeg` and `aspect` = width / height. nil when the point is behind the camera.
function ViewportStage.projectPoint(cameraCFrame: CFrame, vFovDeg: number, aspect: number, point: Vector3): Vector2?
	local p = cameraCFrame:PointToObjectSpace(point)
	if p.Z > -EPSILON then
		return nil
	end
	local tanV = math.tan(math.rad(math.clamp(positive(vFovDeg, FRAMING.vFovDeg), 1, 179)) / 2)
	local tanH = tanV * positive(aspect, DEFAULT_ASPECT)
	local x = (p.X / -p.Z) / tanH
	local y = (p.Y / -p.Z) / tanV
	return Vector2.new((x + 1) / 2, (1 - y) / 2)
end

-- The camera-locked key light (§10.5): Config.Inspect.Lighting.lightDirection (or `direction`) turned into world space
-- by the camera, so the face is lit from upper left behind the viewer from any angle.
function ViewportStage.lightDirection(cameraCFrame: CFrame, direction: Vector3?): Vector3
	local d = direction or LIGHTING.lightDirection
	if d.Magnitude < EPSILON then
		d = LIGHTING.lightDirection
	end
	return cameraCFrame:VectorToWorldSpace(d.Unit)
end

-- The framing of a model's rest pose: its bounding box (centre, size, radius) and its pivot's rotation; `widening` is
-- the model's own squeeze widening (nil = Framing.squeezeWidening).
function ViewportStage.framingOf(model: Model, widening: number?): Framing
	local cf, size = model:GetBoundingBox()
	local wide = positive(widening, FRAMING.squeezeWidening)
	return {
		center = cf.Position,
		size = size,
		radius = positive(size.Magnitude / 2 * wide, 1),
		pivotRotation = model:GetPivot().Rotation,
		widening = wide,
	}
end

-- Public: the shared stage -----------------------------------------------------------------------------------------------

local function build(): Stage
	local root: Frame = Create("Frame", {
		Name = "SD_ViewportStage",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ClipsDescendants = true,
		Visible = false,
	})
	Theme.corner(Theme.Radius.tile, root)
	local gradient: UIGradient = Create("UIGradient", {
		Name = "Background",
		Color = ColorSequence.new(GRADIENT_FROM, GRADIENT_TO),
		Rotation = GRADIENT_ROTATION,
		Parent = root,
	})
	local stroke = Theme.stroke(Theme.Colors.inkUI, NEUTRAL_STROKE_PX, root)
	stroke.Name = "RarityStroke"

	local function ellipse(name: string, scale: number, color: Color3, transparency: number, z: number): Frame
		local frame: Frame = Create("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(scale, scale),
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = z,
			Parent = root,
		})
		Create(
			"UIAspectRatioConstraint",
			{ AspectRatio = 1.25, DominantAxis = Enum.DominantAxis.Height, Parent = frame }
		)
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
		return frame
	end
	local whiteEllipse = ellipse("Ellipse", ELLIPSE_SCALE, Color3.new(1, 1, 1), BACKGROUND.ellipseTransparency, 1)
	local glow = ellipse("Glow", GLOW_SCALE, Theme.Colors.cream, 1, 2)
	glow.Visible = false

	local back: Frame = Create("Frame", {
		Name = "Back",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = root,
	})
	local shadow: Frame = Create("Frame", {
		Name = "ContactShadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Theme.Colors.inkUI,
		BackgroundTransparency = BACKGROUND.contactShadowTransparency,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 0),
		Visible = false,
		ZIndex = 4,
		Parent = root,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shadow })
	local viewport: ViewportFrame = Create("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = LIGHTING.ambient,
		LightColor = LIGHTING.lightColor,
		ZIndex = 5,
		Parent = root,
	})
	local camera: Camera = Create("Camera", {
		Name = "Camera",
		FieldOfView = FRAMING.vFovDeg,
		Parent = viewport,
	})
	viewport.CurrentCamera = camera
	local front: Frame = Create("Frame", {
		Name = "Front",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
		Parent = root,
	})

	local alive = true
	local attached = false
	local current: Model? = nil
	local props: { Model } = {}
	local framing: Framing? = nil
	local yaw, pitch, zoom = ORBIT.defaultYawDeg, ORBIT.defaultPitchDeg, 1
	local shadowWiden = 1
	local manualLight: Vector3? = nil -- UI FINAL R7: set while the caller drives the camera (setManualCamera)
	local effect: Scheduler.Handle? = nil
	local sizeConnection: RBXScriptConnection? = nil

	local function aspect(): number
		local size = viewport.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return DEFAULT_ASPECT
		end
		return size.X / size.Y
	end

	-- The fit's Framing values with the framed model's own widening (one table, reused every frame).
	local fitConfig: FitConfig = {
		squeezeWidening = FRAMING.squeezeWidening,
		fitPadding = FRAMING.fitPadding,
		minClearance = FRAMING.minClearance,
	}

	local function currentDistance(): number
		local f = framing
		if f == nil then
			return 1
		end
		fitConfig.squeezeWidening = f.widening or FRAMING.squeezeWidening
		local fit = ViewportStage.fitDistance(f.size, FRAMING.vFovDeg, aspect(), fitConfig)
		return math.max(fit * positive(zoom, 1), f.radius + FRAMING.minClearance)
	end

	local function applyCamera()
		local f = framing
		if f == nil or manualLight ~= nil then
			return
		end
		camera.CFrame = ViewportStage.orbitCFrame(f.center, f.pivotRotation, yaw, pitch, currentDistance())
	end

	local function updateShadow()
		local f = framing
		if f == nil or (current == nil and #props == 0) then
			shadow.Visible = false
			return
		end
		local up = f.pivotRotation.UpVector
		local right = f.pivotRotation.RightVector
		local bottom = f.center - up * (f.size.Y / 2)
		local half = math.max(f.size.X, f.size.Z) / 2
		local a = aspect()
		local cam = camera.CFrame
		local left = ViewportStage.projectPoint(cam, FRAMING.vFovDeg, a, bottom - right * half)
		local rightPoint = ViewportStage.projectPoint(cam, FRAMING.vFovDeg, a, bottom + right * half)
		local mid = ViewportStage.projectPoint(cam, FRAMING.vFovDeg, a, bottom)
		if left == nil or rightPoint == nil or mid == nil then
			shadow.Visible = false
			return
		end
		local width = math.abs(rightPoint.X - left.X) * shadowWiden
		if width < SHADOW_MIN_WIDTH then
			shadow.Visible = false
			return
		end
		local heightPx = width * viewport.AbsoluteSize.X * SHADOW_HEIGHT_SHARE
		shadow.Position = UDim2.fromScale(mid.X, mid.Y)
		shadow.Size = UDim2.new(width, 0, 0, heightPx)
		shadow.Visible = true
	end

	local function step(): boolean
		if not alive or not attached then
			effect = nil
			return false
		end
		local light = manualLight
		if light then
			viewport.LightDirection = light
			shadow.Visible = false
			return true
		end
		viewport.LightDirection = ViewportStage.lightDirection(camera.CFrame)
		updateShadow()
		return true
	end

	local function stopFollowing()
		if effect then
			effect:disconnect()
			effect = nil
		end
		if sizeConnection then
			sizeConnection:Disconnect()
			sizeConnection = nil
		end
	end

	local function destroyModel(model: Model?)
		if model then
			model:Destroy()
		end
	end

	local self = {} :: Stage
	self.root = root
	self.viewport = viewport
	self.camera = camera
	self.back = back
	self.front = front

	-- Shows the stage filling `container`. Returns false when the stage is gone (destroyed).
	function self.attach(_: Stage, container: GuiObject): boolean
		if not alive then
			return false
		end
		local ok, err = pcall(function()
			root.Parent = container
		end)
		if not ok then
			log:warn("attach failed:", err)
			return false
		end
		-- UI FINAL R5: a container with its own backdrop (SD_OwnBackdrop) keeps it; elsewhere the stage's own look.
		local own = container:GetAttribute("SD_OwnBackdrop") == true
		root.BackgroundTransparency = if own then 1 else 0
		whiteEllipse.Visible = not own
		stroke.Enabled = not own
		root.Visible = true
		attached = true
		stopFollowing()
		sizeConnection = viewport:GetPropertyChangedSignal("AbsoluteSize"):Connect(applyCamera)
		effect = Scheduler.add(step, "render")
		applyCamera()
		step()
		return true
	end

	function self.detach(_: Stage)
		attached = false
		stopFollowing()
		root.Visible = false
		if alive then
			root.Parent = nil
		end
	end

	function self.isAttached(_: Stage): boolean
		return attached
	end

	-- Parents `model` into the viewport as the stage's model (destroying the one before, unless it is the same) and
	-- frames its current pose, with its own squeeze widening when given. Returns the framing.
	function self.setModel(_: Stage, model: Model, widening: number?): Framing
		if current ~= model then
			destroyModel(current)
		end
		current = model
		model.Parent = viewport
		local f = ViewportStage.framingOf(model, widening)
		framing = f
		applyCamera()
		return f
	end

	-- Hands the model over: it is unparented and no longer owned (nor destroyed) by the stage.
	function self.takeModel(_: Stage): Model?
		local model = current
		current = nil
		if model then
			model.Parent = nil
		end
		return model
	end

	-- Destroys the model and every prop (§10.11: models are destroyed on close; the stage is kept).
	function self.clearModel(_: Stage)
		destroyModel(current)
		current = nil
		for _, prop in props do
			prop:Destroy()
		end
		table.clear(props)
		framing = nil
		shadow.Visible = false
	end

	function self.model(_: Stage): Model?
		return current
	end

	-- An extra model in the same viewport (the reveal's gift box next to the squishy); destroyed by clearModel.
	function self.addProp(_: Stage, model: Model)
		if table.find(props, model) == nil then
			table.insert(props, model)
		end
		model.Parent = viewport
	end

	function self.removeProp(_: Stage, model: Model, destroy: boolean?)
		local index = table.find(props, model)
		if index then
			table.remove(props, index)
		end
		if destroy then
			model:Destroy()
		elseif model.Parent == viewport then
			model.Parent = nil
		end
	end

	-- Frames an explicit pose (e.g. the reveal blending from the box to the squishy).
	function self.setFraming(_: Stage, f: Framing)
		framing = f
		applyCamera()
	end

	function self.framing(_: Stage): Framing?
		return framing
	end

	-- The orbit view: yaw / pitch in degrees (yaw wraps; Inspect clamps its pitch to Config.Inspect.Orbit) and a zoom
	-- multiplier (> 0; Inspect keeps it in [zoomMin, zoomMax]).
	function self.setView(_: Stage, yawDeg: number, pitchDeg: number, zoomMultiplier: number?)
		yaw = if finite(yawDeg) then yawDeg % 360 else yaw
		pitch = if finite(pitchDeg) then pitchDeg else pitch
		if zoomMultiplier ~= nil then
			zoom = positive(zoomMultiplier, 1)
		end
		applyCamera()
	end

	function self.view(_: Stage): (number, number, number)
		return yaw, pitch, zoom
	end

	function self.distance(_: Stage): number
		return currentDistance()
	end

	-- The rarity-coloured UIStroke around the viewport (nil = the neutral ink outline).
	function self.setRarity(_: Stage, rarity: string?)
		local style = if rarity then RarityStyle.get(rarity) else nil
		stroke.Color = if style then style.color else Theme.Colors.inkUI
		stroke.Thickness = if style then STROKE_PX else NEUTRAL_STROKE_PX
	end

	-- A soft glow behind the model; opacity 0..1 (the caller keeps it under its own cap, e.g. glowMaxOpacity).
	function self.setGlow(_: Stage, color: Color3?, opacity: number)
		local o = if finite(opacity) then math.clamp(opacity, 0, 1) else 0
		glow.BackgroundColor3 = color or Theme.Colors.cream
		glow.BackgroundTransparency = 1 - o
		glow.Visible = o > 0
	end

	-- Shifts the background gradient toward `color` by `amount` (0..1); nil or 0 = the neutral gradient.
	function self.setTint(_: Stage, color: Color3?, amount: number)
		local a = if finite(amount) then math.clamp(amount, 0, 1) else 0
		if color == nil or a <= 0 then
			gradient.Color = ColorSequence.new(GRADIENT_FROM, GRADIENT_TO)
			return
		end
		gradient.Color = ColorSequence.new(GRADIENT_FROM:Lerp(color, a), GRADIENT_TO:Lerp(color, a))
	end

	-- The contact shadow's width multiplier (1 = the model's footprint; it widens with the squash).
	function self.setShadowWiden(_: Stage, factor: number)
		shadowWiden = positive(factor, 1)
	end

	-- Back to the neutral look: no glow, no tint, the panel stroke, shadow 1, default view.
	-- UI FINAL R7: the caller's camera (see the header); resetLook() ends it.
	function self.setManualCamera(
		_: Stage,
		cframe: CFrame,
		fovDeg: number,
		lightDirection: Vector3,
		ambient: Color3,
		lightColor: Color3
	)
		manualLight = if lightDirection.Magnitude > EPSILON then lightDirection.Unit else LIGHTING.lightDirection.Unit
		camera.FieldOfView = math.clamp(positive(fovDeg, FRAMING.vFovDeg), 1, 120)
		camera.CFrame = cframe
		viewport.Ambient = ambient
		viewport.LightColor = lightColor
		viewport.LightDirection = manualLight :: Vector3
	end

	function self.resetLook(s: Stage)
		if manualLight then
			manualLight = nil
			camera.FieldOfView = FRAMING.vFovDeg
			viewport.Ambient = LIGHTING.ambient
			viewport.LightColor = LIGHTING.lightColor
			viewport.ImageTransparency = 0
		end
		s:setGlow(nil, 0)
		s:setTint(nil, 0)
		s:setRarity(nil)
		shadowWiden = 1
		yaw, pitch, zoom = ORBIT.defaultYawDeg, ORBIT.defaultPitchDeg, 1
		applyCamera()
	end

	-- Destroys every frame the callers put in the back and front layers.
	function self.clearLayers(_: Stage)
		for _, layer in { back, front } do
			for _, child in layer:GetChildren() do
				child:Destroy()
			end
		end
	end

	function self.isAlive(_: Stage): boolean
		return alive
	end

	function self.destroy(_: Stage)
		if not alive then
			return
		end
		alive = false
		attached = false
		stopFollowing()
		destroyModel(current)
		current = nil
		for _, prop in props do
			prop:Destroy()
		end
		table.clear(props)
		root:Destroy()
		if shared == self then
			shared = nil
		end
	end

	root.Destroying:Connect(function()
		if alive then
			alive = false
			attached = false
			stopFollowing()
			if shared == self then
				shared = nil
			end
		end
	end)

	return self
end

-- The shared stage, created on first use (a destroyed one is replaced).
function ViewportStage.get(): Stage
	local stage = shared
	if stage == nil or not stage:isAlive() then
		stage = build()
		shared = stage
	end
	return stage :: Stage
end

-- True once the shared stage exists (debug and leak checks; never creates it).
function ViewportStage.exists(): boolean
	local stage = shared
	return stage ~= nil and stage:isAlive()
end

return ViewportStage
