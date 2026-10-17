--!strict
-- BoxReveal (client only). UI FINAL R7 (plan work/ui/PLAN.md R7 G7.1-G7.14, G7.20, PR16, PR18, PR21, T13, T14;
-- `H:n` = "Squishy Duels HUD.dc.html" line n, `stage:n` = Diego's uploads/box-stage.html line n; numbers in
-- Config.UI.Boxes.reveal and Config.Anim.boxReveal, the timeline and the curves in UI/BoxFormat): the design's box
-- reveal overlay, its own full-screen layer (not a window). BoxController owns the queue, the remotes and the result
-- holds; this module draws one reveal:
--   local run = BoxReveal.start(spec)   -- the box drops at once (G7.20: no wait for the BoxOpen reply)
--   run:setResult(reveal, savePending)  -- the reply is in: the last tap may burst
--   run:skip()                          -- PR21: straight to the result (only once the reply is in)
--   run:close(reason)                   -- the close (H:837-840): fade + grow over 200 ms, removed at 190 ms; "inspect"
--                                       -- leaves the squishy on the shared stage at rest for Inspect to adopt
-- The layers (H:470-505): the scrim (H:471, img.fx.radial.revealScrim, fading in over .3 s), from the burst the rarity
-- tint (H:473, img.fx.radial.revealTint<Rarity>, .4 s) and the 1500 px rays (H:474); the shared ViewportStage across
-- the whole screen (H:478: no frame, no backdrop, SD_OwnBackdrop; its camera the design's: FOV 34 at (0, 2.3, 8.4) on
-- (0, 1.05, 0), the key light from (3, 6, 5), Ambient #D9C8F0: G7.8, the viewport's only lights), fading in over 250 ms;
-- the texts and buttons in the safe area (spec.safeArea's rect) at the UI scale; the flash on top (H:503, PR16).
-- The 3D timeline (stage:254-342): the box (Art/BoxBuilder) drops 7 units on easeOutBounce with its yaw unwinding and
-- the floor blob growing, lands (the squash spring, the floor wave, 26 dust sparkles, the low stamp, jolt 6); idles
-- (bob, roll, yaw, the lid ajar, the inner light, the sparkles, Soft's ears, Royal's crown and seam); each tap (the
-- player's on the stage, or one every 1.1 s) advances one: squash, hop, lid kick, light, the seam sparkles, the HUD
-- burst 6 + 5j and jolt 3 + 3j (H:815-816) and box.shake; the third tap bursts once the reply is in (else the box keeps
-- its idle until it is): the beam (img.fx.beam, while it has an id), the wave, the lid swings or (Sweet) flies, Royal's
-- 16 coins, the box swells, spins and goes with a poof, the squishy grows on the design's elastic, rises and spins in,
-- fading in; 1.5 s later the result idle: the turntable (13.2°/s), the bob, 4 sparkles a second, drag to spin, the
-- wheel / pinch / triggers to zoom (4-11 units), the right stick to turn; a tap on the squishy (not a drag) = Inspect.
-- At the burst (H:822-830): box.open, the flash (peak .3 at 80 ms, PR16), jolt 14, the white 420 and the rarity light
-- 700 rings at (50%, 48%), 120 ms later reveal.<rarity> and the burst (30 + 12 x the rarity index pieces, PR18), then
-- for Epic and Exclusive the rain once those pieces are gone. Every jolt for every rarity, only with Camera shake on
-- (UiFx.jolt). The results (H:487-500) count from the burst: NEW! +.3 s (sdReveal), the name +.35, the rarity pill +.45
-- (mixed case, its own pill, G7.12), the duplicate line +.5 (PR21; pens3 phase 5: a copy, no Coins; measured at the
-- drawn size, Theme.textBoundsAt, so its slot holds the drawn text), the buttons +.6 (EQUIP when the
-- squishy is not equipped, AGAIN on a paid box, NICE!), the drag hint +1 s. Skip (PR21) is the reset pill's look,
-- bottom right, from 0 ms.
-- §9.15 (PR18): 1 viewport and at most Config.Vfx.Effects.boxRevealUiFrames animated UI frames: the rays picture, the
-- rings, the UiFx sparks and this module's own sparkles share one ledger (BoxFormat.budgetTake); the 3D sparkles of the
-- design are budgeted 2D pieces; no ParticleEmitter renders in a ViewportFrame (stated).
-- ReducedMotion (§18.1): no drop, bob, roll, hop, squash, spin or orbit; the taps still advance (with their sounds), the
-- burst hides the box and the squishy fades in at rest; UiFx draws no sparks, rings, rain or jolts.
-- Readings: the texts' slots are measured (no AutomaticSize on labels: wrong under a UIScale); the saving note sits
-- under the duplicate line; a tap that moves less than tapMovePx is a tap, more a drag.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local BoxBuilder = require(Shared.Art.BoxBuilder)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Art.Palette)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Client = UI.Parent
local BoxFormat = require(UI.BoxFormat)
local Button = require(UI.Components.Button)
local CoinIcon = require(UI.Components.CoinIcon)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local ViewportStage = require(UI.ViewportStage)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)
local SquishyCache = require(Client.Models.SquishyCache)

-- Types

export type Reason = "nice" | "back" | "again" | "inspect" | "close" | "matched" | "failed"

export type Spec = {
	layer: ScreenGui, -- Config.UI.Boxes.reveal.layer (full screen, no insets)
	safeArea: GuiBase2d?, -- the safe area (SD_Modal: the texts and buttons stay inside it)
	boxId: string,
	reveal: BoxFormat.Reveal?, -- nil while the BoxOpen reply is on its way
	savePending: boolean?,
	canEquip: boolean, -- false for a Studio preview
	equipped: boolean?, -- the squishy is the equipped one already (no EQUIP, H:1019)
	againPrice: number?, -- AGAIN on a paid box (nil: none)
	againOff: boolean?, -- AGAIN's off state (short of Coins, P11)
	inspectable: boolean,
	scale: number,
	trackScale: ((uiScale: UIScale) -> ())?,
	sound: (cue: BoxFormat.SoundCue) -> (),
	onResult: () -> (), -- the result is on screen (natural or skipped): BoxController acknowledges it
	onEquip: () -> (),
	onAgain: () -> (),
	onNice: () -> (),
	onInspect: () -> (),
	onSkip: () -> (),
}

export type Run = {
	root: Frame,
	skipButton: TextButton,
	equip: Button.Button,
	again: Button.Button,
	nice: Button.Button,
	setResult: (self: Run, reveal: BoxFormat.Reveal, savePending: boolean) -> (),
	hasResult: (self: Run) -> boolean,
	skip: (self: Run) -> boolean,
	isFinal: (self: Run) -> boolean,
	inputOpen: (self: Run) -> boolean,
	setEquip: (self: Run, state: "normal" | "loading" | "equipped") -> (),
	setAgainOff: (self: Run, off: boolean) -> (),
	primary: (self: Run) -> GuiObject,
	close: (self: Run, reason: Reason) -> (),
	destroy: (self: Run) -> (),
	debug: (self: Run) -> { [string]: any },
}

type Sparkle = {
	pos: Vector3,
	vel: Vector3,
	life: number,
	max: number,
	grav: number,
	seed: number,
	frame: ImageLabel,
}
type Coin = { part: BasePart, vel: Vector3, spin: Vector3, life: number }
type ScalePart = {
	part: BasePart,
	rel: CFrame,
	size: Vector3,
	mesh: DataModelMesh?,
	offset: Vector3,
	meshScale: Vector3,
	fileMesh: boolean,
	base: number,
}

-- Constants

local R = Config.UI.Boxes.reveal
local A = Config.Anim.boxReveal
local FX = Config.UI.Fx.events
local FRAME_BUDGET = Config.Vfx.Effects.boxRevealUiFrames
local LOOP_HINT = Config.UI.motion.loops.hint
local UP_FRAMES = Config.UI.Shop.congrats.up.frames -- H:44 sdUp (30 px lower and clear -> rest)
local REVEAL_FRAMES = Config.UI.Shop.congrats.icon.frames -- H:38 sdReveal
local WHITE = Color3.new(1, 1, 1)
local SCRIM_KEY = "img.fx.radial.revealScrim"
local TINT_PREFIX = "img.fx.radial.revealTint"
local FLASH_KEY = "img.fx.radial.revealFlash"
local RAYS_KEY = "img.fx.raysReveal"
local BEAM_KEY = "img.fx.beam"
local BLOB_KEY = "img.fx.blob"
local GLOW_KEY = "img.fx.glow"
local SPARK_KEY = "img.fx.spark"
local SPARKLE_SIZE = 0.26 -- stage:192: PointsMaterial size (units, attenuated)
local DRAG = 1.4 -- stage:208: the sparkles' air drag per second
local LIGHT_SPREAD = 3 -- reading: the inner light's glow is this many units wide at full strength
local RING_FRAMES = 2 -- H:826
local RINGS_LIFE_S = Config.UI.Fx.ring.ms / 1000
local RAIN_LIFE_S = (Config.UI.Fx.rain.ms + Config.UI.Fx.rain.jitterMs + Config.UI.Fx.rain.delayMs) / 1000
local SPARKS_LIFE_S = (Config.UI.Fx.sparks.ms + Config.UI.Fx.sparks.jitterMs) / 1000

-- Module table

local BoxReveal = {}

-- Private --------------------------------------------------------------------------------------------------------

local function color(name: string): Color3
	local value = (Palette :: any)[name]
	return if typeof(value) == "Color3" then value else WHITE
end

local function rarityColors(rarity: string): (Color3, Color3, Color3)
	local style = RarityStyle.get(rarity)
	local ui = if style then style.ui else nil
	local base = if ui and ui.base then ui.base else if style then style.color else WHITE
	return base, if ui and ui.light then ui.light else base, if ui and ui.dark then ui.dark else base
end

-- stage:311: three.js Color.setHSL (h, s, l in 0..1).
local function hsl(h: number, sat: number, l: number): Color3
	local q = if l < 0.5 then l * (1 + sat) else l + sat - l * sat
	local p = 2 * l - q
	local function channel(t: number): number
		local u = t % 1
		if u < 1 / 6 then
			return p + (q - p) * 6 * u
		elseif u < 1 / 2 then
			return q
		elseif u < 2 / 3 then
			return p + (q - p) * (2 / 3 - u) * 6
		end
		return p
	end
	return Color3.new(channel(h + 1 / 3), channel(h), channel(h - 1 / 3))
end

-- `scale` (the layer's UIScale): measured at the drawn size (Theme.textBoundsAt).
local function textSize(text: string, role: string, wrap: number?, scale: number?): Vector2
	local kind = (Theme.Sticker.text[role] :: any).kind
	local bounds = if scale
		then Theme.textBoundsAt(text, kind, wrap, scale)
		else Theme.textBounds(text, kind, nil, wrap)
	return Vector2.new(math.ceil(bounds.X) + 6, math.ceil(bounds.Y) + 2)
end

-- A measured label in a sticker role, centred in its own pose holder (the design's animated element).
local function roleLabel(
	parent: Instance,
	name: string,
	order: number,
	text: string,
	role: string,
	wrap: number?,
	scale: number?
): (Frame, TextLabel)
	local size = textSize(text, role, wrap, scale)
	local slot: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size.X, size.Y),
		LayoutOrder = order,
		Parent = parent,
	})
	local label = Theme.label({
		Name = "Text",
		Text = text,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = wrap ~= nil,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = slot,
	}, (Theme.Sticker.text[role] :: any).kind)
	Theme.stickerText(label, role)
	return slot, label
end

-- A design pill (H:489, H:491): `fill`'s face, the ink border inside, full radius, the lip under it, an optional top
-- highlight, the label in `role` centred on the face; returns the pill's slot (face + lip tall).
local function pill(
	parent: Instance,
	name: string,
	order: number,
	text: string,
	spec: any,
	fill: Color3,
	fillEnd: Color3
): Frame
	local size = textSize(text, spec.role)
	local width = size.X + 2 * (spec.padX + spec.border)
	local height = math.max(spec.height, size.Y + 2 * spec.border)
	local slot: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(width, height + spec.lip),
		LayoutOrder = order,
		Parent = parent,
	})
	local pose: Frame = Create("Frame", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = slot,
	})
	local lip: Frame = Create("Frame", {
		Name = "Lip",
		BackgroundColor3 = Theme.Colors.inkUI,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, spec.lip),
		Size = UDim2.new(1, 0, 0, height),
		Parent = pose,
	})
	Theme.corner(height, lip)
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, height),
		ZIndex = 2,
		Parent = pose,
	})
	local highlight = spec.highlight
	Theme.foam(face, {
		radius = height,
		stroke = spec.border,
		inner = true,
		top = if highlight then spec.border + highlight.px else 0,
		colors = {
			face = fill,
			faceEnd = fillEnd,
			top = if highlight then fill:Lerp(WHITE, highlight.alpha) else fill,
		},
	})
	local label = Theme.label({
		Name = "Text",
		Text = text,
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 3,
		Parent = face,
	}, (Theme.Sticker.text[spec.role] :: any).kind)
	Theme.stickerText(label, spec.role)
	return slot
end

-- Every part of the squishy at rest, for its uniform scale and fade (the old reveal's capture, kept).
local function capture(model: Model): ({ ScalePart }, Vector3)
	local pivot = model:GetPivot()
	local parts: { ScalePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant ~= model.PrimaryPart then
			local part = descendant :: BasePart
			local mesh = part:FindFirstChildWhichIsA("DataModelMesh")
			table.insert(parts, {
				part = part,
				rel = pivot:ToObjectSpace(part.CFrame),
				size = part.Size,
				mesh = mesh,
				offset = if mesh then mesh.Offset else Vector3.zero,
				meshScale = if mesh then mesh.Scale else Vector3.one,
				fileMesh = mesh ~= nil
					and mesh:IsA("SpecialMesh")
					and (mesh :: SpecialMesh).MeshType == Enum.MeshType.FileMesh,
				base = part.Transparency,
			})
		end
	end
	local box = model:GetBoundingBox()
	return parts, pivot:PointToObjectSpace(box.Position)
end

-- The squishy at uniform scale `k` of its rest size with its box centre at `centre`, turned `yaw`, at `alpha`.
local function writeToy(
	parts: { ScalePart },
	root: BasePart?,
	offset: Vector3,
	k: number,
	centre: Vector3,
	yaw: number,
	alpha: number
)
	local pivot = CFrame.new(centre) * CFrame.Angles(0, yaw, 0) * CFrame.new(-offset * k)
	for _, data in parts do
		data.part.Size = data.size * k
		data.part.CFrame = pivot * CFrame.new(data.rel.Position * k) * data.rel.Rotation
		data.part.Transparency = data.base + (1 - data.base) * (1 - math.clamp(alpha, 0, 1))
		local mesh = data.mesh
		if mesh then
			mesh.Offset = data.offset * k
			if data.fileMesh then
				mesh.Scale = data.meshScale * k
			end
		end
	end
	if root then
		root.CFrame = pivot
	end
end

-- Public -----------------------------------------------------------------------------------------------------------

function BoxReveal.start(spec: Spec): Run
	local c = Cleanup.new()
	local reduced = Tweens.reducedMotion()
	local boxBlueprint = BoxBuilder.blueprint(spec.boxId) or (BoxBuilder.blueprint("snack") :: BoxBuilder.BoxBlueprint)
	local kind = boxBlueprint.kind
	local self = {} :: Run
	local result: BoxFormat.Reveal? = spec.reveal
	local savePending = spec.savePending == true
	local state = BoxFormat.revealStart()
	local closing = false
	local done = false
	local final = false
	local resultShownAt: number? = nil
	local tapped = false
	local skipWanted = false
	local ledger: BoxFormat.Ledger = {}
	local clock = 0
	local raysOn = false
	local focusToken = Focus.capture()

	-- The layers ---------------------------------------------------------------------------------------------------
	local root: Frame = Create("Frame", {
		Name = "SD_BoxReveal",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = true,
		ClipsDescendants = true,
	})
	c:add(root)
	local grow: UIScale = Create("UIScale", { Parent = root })
	local function layer(name: string, z: number): Frame
		return Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Active = false,
			ZIndex = z,
			Parent = root,
		})
	end
	-- H:471: the scrim, fading in (sdFade .3s ease)
	local scrim = layer("Scrim", 1)
	Theme.radial(scrim, SCRIM_KEY, {
		inner = Palette.StickerRevealScrimIn,
		outer = Palette.StickerRevealScrimOut,
		innerAlpha = R.scrimInnerAlpha,
		outerAlpha = R.scrimOuterAlpha,
		centre = Vector2.new(0.5, R.scrimCentreY),
	})
	-- H:473-474: the rarity tint and the rays, from the burst
	local tint = layer("Tint", 2)
	tint.Visible = false
	local raysHolder = layer("Rays", 3)
	-- H:478: the stage across the whole screen
	local stageHolder = layer("Stage", 4)
	stageHolder.Active = true
	stageHolder:SetAttribute("SD_OwnBackdrop", true)
	-- the texts and buttons, in the safe area at the UI scale
	local ui: Frame = Create("Frame", {
		Name = "Ui",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 5,
		Parent = root,
	})
	local uiScale: UIScale = Create("UIScale", { Scale = spec.scale, Parent = ui })
	if spec.trackScale then
		spec.trackScale(uiScale)
	end
	-- H:503: the flash on top
	local flash = layer("Flash", 6)
	Theme.radial(flash, FLASH_KEY, {
		inner = WHITE,
		mid = Palette.StickerRevealFlashMid,
		midAt = R.flash.midAt,
		outer = WHITE,
		innerAlpha = 1,
		midAlpha = 1,
		outerAlpha = R.flash.outerAlpha,
		centre = Vector2.new(0.5, R.flash.centreY),
	})
	local flashFade = Tweens.fadeGroup(flash)
	-- H:825: the burst's centre (50%, 48%), as a frame (UiFx draws in its own layer)
	local burstPoint: Frame = Create("Frame", {
		Name = "BurstPoint",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromOffset(2, 2),
		Active = false,
		Parent = root,
	})
	flashFade:setAlpha(0)
	root.Parent = spec.layer

	local function fitUi()
		local s = math.max(uiScale.Scale, 1e-3)
		local area = spec.safeArea
		local origin = root.AbsolutePosition
		local pos, size = Vector2.zero, root.AbsoluteSize
		if area and area.AbsoluteSize.X > 0 then
			pos, size = area.AbsolutePosition - origin, area.AbsoluteSize
		end
		ui.Position = UDim2.fromOffset(pos.X, pos.Y)
		ui.Size = UDim2.fromOffset(size.X / s, size.Y / s)
	end
	c:add(uiScale:GetPropertyChangedSignal("Scale"):Connect(fitUi))
	c:add(root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitUi))
	if spec.safeArea then
		c:add(spec.safeArea:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitUi))
		c:add(spec.safeArea:GetPropertyChangedSignal("AbsolutePosition"):Connect(fitUi))
	end
	fitUi()

	local scrimFade = Tweens.fadeGroup(scrim)
	scrimFade:setAlpha(0)

	-- One Scheduler effect runs every track of this reveal.
	local tracks: { (dt: number) -> boolean } = {}
	local function track(fn: (dt: number) -> boolean)
		table.insert(tracks, fn)
	end
	-- `fn(u)` 0 -> 1 over `ms` after `delayMs`, eased by `curve` (at once under ReducedMotion).
	local function run(ms: number, delayMs: number, curve: string, fn: (u: number) -> ())
		local ease = Tweens.curve(curve)
		local elapsed = -delayMs / 1000
		fn(0)
		track(function(dt: number): boolean
			elapsed += dt
			if elapsed < 0 then
				return true
			end
			local u = if reduced or ms <= 0 then 1 else math.clamp(elapsed * 1000 / ms, 0, 1)
			fn(ease(u))
			return u < 1
		end)
	end
	local function keyframes(holder: GuiObject, frames: any, ms: number, delayMs: number, curve: string)
		local k = Tweens.keyframes(holder, frames, { ms = ms, delayMs = delayMs, curve = curve })
		track(function(dt: number): boolean
			return k:step(dt, 0)
		end)
	end
	run(R.scrimFadeMs, 0, "ease", function(u: number)
		scrimFade:setAlpha(u)
	end)

	-- The stage ------------------------------------------------------------------------------------------------------
	local stage = ViewportStage.get()
	stage:clearModel()
	stage:clearLayers()
	stage:resetLook()
	stage:attach(stageHolder)
	local viewport = stage.viewport
	local camera = stage.camera
	local orbit = BoxFormat.orbitStart()
	local function placeCamera()
		stage:setManualCamera(
			CFrame.lookAt(BoxFormat.orbitEye(orbit), A.camera.target),
			A.camera.fovDeg,
			-A.keyLight,
			Palette.BoxStageAmbient,
			WHITE
		)
	end
	placeCamera()
	viewport.ImageTransparency = 1
	run(R.stageFadeMs, 0, "ease", function(u: number)
		if not closing then
			viewport.ImageTransparency = 1 - u
		end
	end)

	local function aspect(): number
		local size = viewport.AbsoluteSize
		return if size.Y > 0 then size.X / size.Y else 1
	end
	-- A point of the scene on the stage (0..1 of its size) and the px one unit covers there.
	local function project(point: Vector3): (Vector2?, number)
		local cam = camera.CFrame
		local share = ViewportStage.projectPoint(cam, A.camera.fovDeg, aspect(), point)
		local depth = -cam:PointToObjectSpace(point).Z
		local unitPx = if depth > 1e-3
			then viewport.AbsoluteSize.Y / (2 * math.tan(math.rad(A.camera.fovDeg) / 2) * depth)
			else 0
		return share, unitPx
	end

	local built = BoxBuilder.build(boxBlueprint, 1)
	stage:addProp(built.model)
	local boxShown = true

	-- 2D stand-ins on the stage's layers: the floor blob and the wave (behind), the beam (behind), the glow (front).
	local blobImage = AssetTable.image(BLOB_KEY) or AssetTable.image(GLOW_KEY)
	local blob: ImageLabel = Create("ImageLabel", {
		Name = "FloorBlob",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Image = blobImage or "",
		ImageColor3 = if AssetTable.image(BLOB_KEY) then WHITE else Palette.BoxFloorBlob,
		ImageTransparency = 1,
		Visible = blobImage ~= nil,
		Parent = stage.back,
	})
	local wave: Frame = Create("Frame", {
		Name = "FloorWave",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Visible = false,
		Parent = stage.back,
	})
	Theme.corner(9999, wave)
	local waveStroke = Theme.stroke(color(boxBlueprint.beam), 2, wave)
	local beamImage = AssetTable.image(BEAM_KEY)
	local beam: ImageLabel = Create("ImageLabel", {
		Name = "Beam",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Image = beamImage or "",
		ImageColor3 = color(boxBlueprint.beam),
		ImageTransparency = 1,
		Visible = false,
		Parent = stage.back,
	})
	local glowImage = AssetTable.image(GLOW_KEY)
	local glow: ImageLabel = Create("ImageLabel", {
		Name = "InnerLight",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Image = glowImage or "",
		ImageColor3 = color(boxBlueprint.light),
		ImageTransparency = 1,
		Visible = glowImage ~= nil,
		Parent = stage.front,
	})
	for _, extra in { blob, wave, beam, glow } :: { GuiObject } do
		c:add(extra)
	end
	local sparkImage = AssetTable.image(SPARK_KEY) or glowImage
	local blobScale = 0
	-- the floor's on-screen flattening: the sine of the camera's height angle over the floor (stage:248)
	local flatten = math.clamp(A.camera.eye.Y / A.camera.eye.Magnitude, 0.05, 1)

	-- The squishy (built once the reply is in) -----------------------------------------------------------------------
	local toy: Model? = nil
	local toyParts: { ScalePart } = {}
	local toyOffset = Vector3.zero
	local toyFit = 1
	local toyRoot: BasePart? = nil
	local function buildToy(reveal: BoxFormat.Reveal)
		if toy then
			return
		end
		local model = SquishyCache.clone(reveal.squishyId, "Viewport", 1)
		local parts, offset = capture(model)
		local _, size = model:GetBoundingBox()
		local largest = math.max(size.X, size.Y, size.Z)
		toyFit = if largest > 1e-3 then A.toy.fit / largest else 1
		toy, toyParts, toyOffset, toyRoot = model, parts, offset, model.PrimaryPart
		writeToy(parts, model.PrimaryPart, offset, 0.001, Vector3.new(0, A.toy.y, 0), math.pi, 0)
	end
	if result then
		buildToy(result)
	end

	-- Springs and the 3D extras (stage:229-231, 336-342) -------------------------------------------------------------
	local sq, sqv = 1, 0
	local lid, lidv, lidT = 0, 0, 0
	local hop, hopv = 0, 0
	local light = 0
	local flick = 0
	local crown = 0
	local rootY = A.dropHeight
	local yaw, roll = A.restYaw + math.pi * A.dropTurns, 0
	local waveT = 9
	local lidFly: { pos: Vector3, vel: Vector3, rx: number, ry: number, ax: number, ay: number }? = nil
	local coins: { Coin } = {}
	local sparkles: { Sparkle } = {}
	local poofed = false
	local burstAt: number? = nil
	local seed = 0

	-- §9.15: the frames left for the ledger once this module's live sparkles and the rays are counted.
	local function cap(): number
		return FRAME_BUDGET - #sparkles - (if raysOn then 1 else 0)
	end
	local function free(): number
		return BoxFormat.budgetFree(ledger, clock, cap())
	end
	-- stage:195-203: n sparkles from `at` (units), as budgeted 2D pieces in the stage's front layer.
	local function spawn(at: Vector3, n: number, o: { [string]: any })
		if reduced or sparkImage == nil then
			return
		end
		local count = math.min(n, free())
		local colors = o.colors :: { string }
		for k = 1, count do
			seed += 1
			local a = math.random() * math.pi * 2
			local e = (o.cone or 1) * math.random()
			local speed = (o.speed or 4) * (0.4 + math.random() * 0.8)
			local spread = o.spread or 0.3
			local life = (o.life or 1) * (0.6 + math.random() * 0.6)
			local frame: ImageLabel = Create("ImageLabel", {
				Name = "Sparkle",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Image = sparkImage,
				ImageColor3 = color(colors[(k - 1) % #colors + 1]),
				Active = false,
				Parent = stage.front,
			})
			table.insert(sparkles, {
				pos = at + Vector3.new((math.random() - 0.5) * spread, 0, (math.random() - 0.5) * spread),
				vel = Vector3.new(
					math.cos(a) * math.sin(e * 1.5) * speed,
					(o.up or 1) * math.cos(e * 1.5) * speed,
					math.sin(a) * math.sin(e * 1.5) * speed
				),
				life = life,
				max = life,
				grav = o.grav or 6,
				seed = seed,
				frame = frame,
			})
		end
	end
	local function stepSparkles(dt: number, total: number)
		for i = #sparkles, 1, -1 do
			local s = sparkles[i]
			s.life -= dt
			if s.life <= 0 then
				s.frame:Destroy()
				table.remove(sparkles, i)
			else
				local drag = 1 - DRAG * dt
				s.vel = Vector3.new(s.vel.X * drag, s.vel.Y - s.grav * dt, s.vel.Z * drag)
				s.pos += s.vel * dt
				local share, unitPx = project(s.pos)
				if share then
					local f = math.max(0, s.life / s.max) * (0.75 + 0.25 * math.sin(s.seed * 13 + total * 20))
					local px = SPARKLE_SIZE * unitPx
					s.frame.Visible = true
					s.frame.Position = UDim2.fromScale(share.X, share.Y)
					s.frame.Size = UDim2.fromOffset(px, px)
					s.frame.ImageTransparency = 1 - math.clamp(f, 0, 1)
				else
					s.frame.Visible = false
				end
			end
		end
	end
	local function seamPoint(): Vector3
		return Vector3.new(0, rootY + boxBlueprint.top + 0.05, 0)
	end
	local function designSparks(n: number, spread: number, colors: { string }, size: number?, extra: { [string]: any }?)
		local granted = BoxFormat.budgetTake(ledger, clock, n, SPARKS_LIFE_S, cap())
		if granted <= 0 then
			return
		end
		local opts: { [string]: any } = { n = granted, spread = spread, colors = UiFx.colors(colors), size = size }
		local more: { [string]: any } = extra or {}
		for key, value in more do
			opts[key] = value
		end
		UiFx.sparks(stageHolder, opts :: any)
	end

	-- The texts and buttons ------------------------------------------------------------------------------------------
	local boxBlock: Frame = Create("Frame", {
		Name = "BoxBlock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1 - R.boxBlock.bottom),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = ui,
	})
	Theme.list(Enum.FillDirection.Vertical, R.boxBlock.gap, boxBlock, Enum.HorizontalAlignment.Center)
	local _boxNameSlot, boxNameLabel =
		roleLabel(boxBlock, "BoxName", 1, BoxFormat.boxName(spec.boxId), R.boxBlock.nameRole)
	keyframes(boxNameLabel, UP_FRAMES, R.nameUp.ms, R.nameUp.delayMs, R.nameUp.curve)
	local _hintSlot, hintLabel = roleLabel(boxBlock, "Hint", 2, Strings.box.tapToOpen, R.boxBlock.hintRole)
	local hintHandle = UiIdle.addFrames(hintLabel, LOOP_HINT.frames, { periodS = R.hintS, curve = LOOP_HINT.curve })
	if hintHandle then
		c:add(function()
			hintHandle:remove()
		end)
	end

	local resultBlock: Frame = Create("Frame", {
		Name = "ResultBlock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, R.resultBlock.top),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = ui,
	})
	Theme.list(Enum.FillDirection.Vertical, R.resultBlock.gap, resultBlock, Enum.HorizontalAlignment.Center)

	local bottomBlock: Frame = Create("Frame", {
		Name = "BottomBlock",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1 - R.bottomBlock.bottom),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = ui,
	})
	Theme.list(Enum.FillDirection.Vertical, R.bottomBlock.gap, bottomBlock, Enum.HorizontalAlignment.Center)
	local _dragSlot, dragLabel = roleLabel(bottomBlock, "DragHint", 1, Strings.box.dragHint, R.dragRole)
	local row: Frame = Create("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = bottomBlock,
	})
	local rowPose: Frame = Create("Frame", {
		Name = "Pose",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = row,
	})
	local rowList = Theme.list(Enum.FillDirection.Horizontal, R.buttonGap, rowPose, Enum.HorizontalAlignment.Center)
	rowList.Wraps = true

	local function guarded(fn: () -> ()): () -> ()
		return function()
			if self:inputOpen() then
				fn()
			end
		end
	end
	-- H:497: EQUIP, cyan 180 x 62 + lip 5, 26 px stroke 6
	local equip = Button.new({
		name = "Reveal_EquipButton",
		text = Strings.common.equip,
		kind = "secondary",
		width = R.equip.width,
		height = R.equip.face,
		textRole = R.equip.role,
		layoutOrder = 1,
		parent = rowPose,
		onActivated = guarded(spec.onEquip),
	})
	c:add(equip)
	-- H:498: AGAIN, gold 230 x 62 (the `again` surface), the label, the coin 30 and the price, gap 8
	local again = Button.new({
		name = "Reveal_AgainButton",
		text = Strings.box.again,
		kind = "primary",
		accent = "gold",
		width = R.again.width,
		height = R.again.face,
		textRole = R.again.role,
		highlight = {
			px = Config.UI.Sticker.surfaces.again.highlightPx,
			a = Config.UI.Sticker.surfaces.again.highlightAlpha,
		},
		bevel = {
			px = Config.UI.Sticker.surfaces.again.bevelPx :: number,
			a = Config.UI.Sticker.surfaces.again.bevelAlpha :: number,
		},
		keycap = "", -- reserves the row: the coin, then the price
		clickSound = false, -- H:498 data-snd none
		layoutOrder = 2,
		parent = rowPose,
		onActivated = guarded(spec.onAgain),
	})
	c:add(again)
	local againPrice: TextLabel? = nil
	local againLine = again.visual:FindFirstChild("Line", true)
	if againLine then
		local list = againLine:FindFirstChildOfClass("UIListLayout")
		if list then
			list.Padding = UDim.new(0, R.again.gap)
		end
		local coin = CoinIcon.new({ name = "Coin", sizePx = R.again.coin, layoutOrder = 50, parent = againLine })
		c:add(coin)
		local priceText = Format.coins(spec.againPrice or 0)
		local size = textSize(priceText, R.again.priceRole)
		local label = Theme.label({
			Name = "Price",
			Text = priceText,
			Size = UDim2.fromOffset(size.X, size.Y),
			AutomaticSize = Enum.AutomaticSize.None,
			TextWrapped = false,
			LayoutOrder = 51,
			Parent = againLine,
		}, (Theme.Sticker.text[R.again.priceRole] :: any).kind)
		Theme.stickerText(label, R.again.priceRole)
		againPrice = label
	end
	-- H:499: NICE!, green 180 x 62, 26 px stroke 6
	local nice = Button.new({
		name = "Reveal_NiceButton",
		text = Strings.box.nice,
		kind = "primary",
		width = R.nice.width,
		height = R.nice.face,
		textRole = R.nice.role,
		clickSound = false, -- the close plays ui.pop (H:835)
		layoutOrder = 3,
		parent = rowPose,
		onActivated = guarded(spec.onNice),
	})
	c:add(nice)

	-- PR21: Skip, the reset pill's look (H:359), bottom right, from 0 ms; its hit box keeps the touch minimum.
	local skipSpec = R.skip
	local skipSize = textSize(Strings.common.skip, skipSpec.role)
	local skipWidth = skipSize.X + 2 * (skipSpec.padX + skipSpec.border)
	local skipButton: TextButton = Create("TextButton", {
		Name = "Reveal_SkipButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -skipSpec.margin, 1, -skipSpec.margin),
		Size = UDim2.fromOffset(math.max(skipWidth, Config.UI.Touch.minTarget), Config.UI.Touch.minTarget),
		Parent = ui,
	})
	local skipFace: Frame = Create("Frame", {
		Name = "SD_Visual",
		BackgroundColor3 = Palette.StickerWell,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(skipWidth, math.max(skipSpec.height, skipSize.Y + 2 * skipSpec.border)),
		Parent = skipButton,
	})
	Theme.corner(9999, skipFace)
	local skipStroke = Theme.stroke(Theme.Colors.inkUI, skipSpec.border, skipFace)
	pcall(function()
		(skipStroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local skipLabel = Theme.label({
		Name = "Label",
		Text = Strings.common.skip,
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = skipFace,
	}, (Theme.Sticker.text[skipSpec.role] :: any).kind)
	Theme.stickerText(skipLabel, skipSpec.role)
	Focus.decorate(skipButton, 9999)
	c:add(Button.decorate(skipButton))
	c:add(skipButton.Activated:Connect(function()
		spec.onSkip()
	end))

	-- The result is on screen (once): the buttons take presses after the guard, BoxController acknowledges it.
	local function reachResult()
		if final or done or closing then
			return
		end
		resultShownAt = os.clock()
		final = true
		spec.onResult()
		if Focus.isGamepad() then
			Focus.select(if equip.root.Visible then equip.root else nice.root)
		end
	end

	-- The result texts (built at the burst, when the squishy is known), each rising in on its delay from the burst
	-- (H:489-499); `instant` (a skip) shows them at rest.
	local function showResult(instant: boolean)
		local reveal = result
		if reveal == nil or resultBlock.Visible then
			return
		end
		local def = Catalog.get(reveal.squishyId)
		local rarity = if def then def.rarity else "Common"
		local base = rarityColors(rarity)
		local info = Rarity.get(rarity)
		local rarityText = if info then Strings.resolve(info.nameKey) or rarity else rarity
		local name = if def then Strings.resolve(def.nameKey) or reveal.squishyId else reveal.squishyId
		local wrap = math.max(1, ui.AbsoluteSize.X / math.max(uiScale.Scale, 1e-3) - 2 * skipSpec.margin)
		local delays = R.delays
		local function rise(holder: GuiObject, frames: any, ms: number, delayMs: number, curve: string)
			if not instant then
				keyframes(holder, frames, ms, delayMs, curve)
			end
		end
		if not reveal.isDuplicate then
			local newSlot = pill(
				resultBlock,
				"New",
				1,
				Strings.box.revealNew,
				R.newPill,
				Palette.StickerRedTop,
				Palette.StickerRedEnd
			)
			rise(newSlot:FindFirstChild("Pose") :: GuiObject, REVEAL_FRAMES, R.newMs, delays.newMs, R.newCurve)
		end
		local _nameSlot, nameLabel = roleLabel(resultBlock, "Name", 2, name, R.nameRole, wrap)
		rise(nameLabel, UP_FRAMES, R.upMs, delays.nameMs, R.upCurve)
		local raritySlot = pill(resultBlock, "Rarity", 3, rarityText, R.rarityPill, base, base)
		rise(raritySlot:FindFirstChild("Pose") :: GuiObject, UP_FRAMES, R.upMs, delays.rarityMs, R.upCurve)
		if reveal.isDuplicate then
			local text = BoxFormat.resultText(true)
			local _dupeSlot, dupeLabel = roleLabel(resultBlock, "Duplicate", 4, text, R.dupeRole, wrap, uiScale.Scale)
			rise(dupeLabel, UP_FRAMES, R.dupeUpMs, delays.dupeMs, "ease")
		end
		if savePending then
			roleLabel(resultBlock, "Saving", 5, Strings.reasonText("box.saving"), R.dupeRole, wrap)
		end
		resultBlock.Visible = true
		bottomBlock.Visible = true
		equip.root.Visible = spec.canEquip and spec.equipped ~= true
		again.root.Visible = spec.againPrice ~= nil
		if spec.againOff then
			self:setAgainOff(true)
		end
		rise(rowPose, UP_FRAMES, R.upMs, delays.buttonsMs, R.upCurve)
		rise(dragLabel, UP_FRAMES, R.dupeUpMs, delays.dragMs, "ease")
		skipButton.Visible = false
		if instant then
			reachResult()
		else
			task.delay(delays.buttonsMs / 1000, reachResult)
		end
	end

	-- The burst's 2D side (H:822-830): the rings, the flash, the tint, the rays, then the reveal sound, the pieces and
	-- (Epic, Exclusive) the rain.
	local function burstUi(instant: boolean)
		local reveal = result :: BoxFormat.Reveal
		local def = Catalog.get(reveal.squishyId)
		local rarity = if def then def.rarity else "Common"
		local base, lightTone, dark = rarityColors(rarity)
		boxBlock.Visible = false
		-- H:473: the tint
		tint.Visible = true
		Theme.radial(
			tint,
			TINT_PREFIX .. rarity,
			{ inner = base, outer = dark, innerAlpha = 1, outerAlpha = 1, centre = Vector2.new(0.5, R.tintCentreY) }
		)
		local tintFade = Tweens.fadeGroup(tint)
		run(if instant then 0 else R.tintFadeMs, 0, "ease", function(u: number)
			tintFade:setAlpha(u * R.tintAlpha)
		end)
		-- H:474: the rays (one animated frame from now on)
		if
			Theme.rays(
				raysHolder,
				RAYS_KEY,
				math.round(R.rays.px * spec.scale),
				R.rays.alpha,
				R.rays.spinS,
				R.rays.centreY
			)
		then
			raysOn = true
		end
		if instant then
			return
		end
		spec.sound(BoxFormat.soundCue("burst", rarity))
		-- PR16: the flash under the flash rule
		local ease = Tweens.curve("easeOut")
		local elapsed = 0
		track(function(dt: number): boolean
			elapsed += dt
			flashFade:setAlpha(BoxFormat.flashAlpha(elapsed * 1000, ease))
			return elapsed * 1000 < R.flash.ms
		end)
		UiFx.jolt(root, FX.boxBurst.jolt)
		-- H:826: the rings at (50%, 48%)
		local ringAt = burstPoint
		local rings = BoxFormat.budgetTake(ledger, clock, RING_FRAMES, RINGS_LIFE_S, cap())
		for index, ring in FX.boxBurst.rings do
			if index <= rings then
				local tone = if ring.color == "rarityLight" then lightTone else UiFx.colors({ ring.color })[1]
				UiFx.ring(ringAt, tone, ring.size)
			end
		end
		local cue = BoxFormat.soundCue("reveal", rarity)
		task.delay((cue.delayMs or 0) / 1000, function()
			if done or closing then
				return
			end
			spec.sound(cue)
			local n = BoxFormat.burstPieces(rarity, free())
			local life = (FX.boxBurst.sparks.ms + Config.UI.Fx.sparks.jitterMs) / 1000
			local granted = BoxFormat.budgetTake(ledger, clock, n, life, cap())
			if granted > 0 then
				local s = FX.boxBurst.sparks
				UiFx.sparks(ringAt, {
					n = granted,
					spread = s.spread,
					up = s.up,
					ms = s.ms,
					size = s.size,
					colors = { base, lightTone, WHITE, Palette.StickerFxYellow }, -- H:829: R.c, R.l, #FFFFFF, #FFD84A
				})
			end
			-- PR18: the rain once the burst's pieces are gone (Epic and Exclusive)
			task.delay(life, function()
				if done or closing then
					return
				end
				local rainN = BoxFormat.rainPieces(rarity, free())
				local rainGranted = BoxFormat.budgetTake(ledger, clock, rainN, RAIN_LIFE_S, cap())
				if rainGranted > 0 then
					UiFx.rain(rainGranted, { base, lightTone, WHITE, Palette.StickerFxYellow }, root)
				end
			end)
		end)
	end

	-- The burst's 3D side (stage:264-277).
	local function burst3d()
		light = A.light.burst
		waveT = 0
		if kind == "sweet" then
			lidFly = {
				pos = Vector3.zero,
				vel = Vector3.new((math.random() - 0.5) * 2 * A.lidFly.vx, A.lidFly.vy, A.lidFly.vz),
				rx = 0,
				ry = 0,
				ax = (math.random() - 0.5) * 2 * A.lidFly.tumble,
				ay = A.lidFly.spin,
			}
		elseif kind == "royal" and not reduced then
			local cfg = A.coins
			local from = seamPoint()
			for _ = 1, cfg.n do
				local part = Instance.new("Part")
				part.Name = "Coin"
				part.Shape = Enum.PartType.Cylinder
				part.Anchored = true
				part.CanCollide = false
				part.CanTouch = false
				part.CanQuery = false
				part.CastShadow = false
				part.Color = Palette.StickerGoldMid
				part.Material = Enum.Material.SmoothPlastic
				part.Size = Vector3.new(cfg.thick, 2 * cfg.radius, 2 * cfg.radius)
				part.CFrame = CFrame.new(from)
				part.Parent = viewport
				local a = math.random() * math.pi * 2
				local out = cfg.outMin + math.random() * cfg.outSpan
				local coin: Coin = {
					part = part,
					vel = Vector3.new(math.cos(a) * out, cfg.upMin + math.random() * cfg.upSpan, math.sin(a) * out),
					spin = Vector3.new(math.random() * cfg.spin, math.random() * cfg.spin, 0),
					life = cfg.lifeS,
				}
				table.insert(coins, coin)
			end
		end
		if toy then
			stage:addProp(toy)
		end
	end

	-- Input: taps, the orbit's drag, the wheel, the pinch, the gamepad ------------------------------------------------
	local press: { start: Vector2, last: Vector2, input: InputObject?, moved: number }? = nil
	local dragX, dragY, zoomTicks = 0, 0, 0
	local padX, padY, triggerIn, triggerOut = 0, 0, 0, 0
	local function onToy(at: Vector2): boolean
		local share, unitPx = project(Vector3.new(0, A.toy.y + A.toy.rise, 0))
		if share == nil then
			return false
		end
		local absolute = viewport.AbsolutePosition + Vector2.new(share.X, share.Y) * viewport.AbsoluteSize
		return (at - absolute).Magnitude <= A.toy.fit * 0.75 * unitPx
	end
	c:add(stageHolder.InputBegan:Connect(function(input: InputObject)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if state.phase == "idle" then
			tapped = true
		end
		press = { start = at, last = at, input = if t == Enum.UserInputType.Touch then input else nil, moved = 0 }
	end))
	c:add(UserInputService.InputChanged:Connect(function(input: InputObject)
		local t = input.UserInputType
		local p = press
		if p and (t == Enum.UserInputType.MouseMovement or (t == Enum.UserInputType.Touch and input == p.input)) then
			local at = Vector2.new(input.Position.X, input.Position.Y)
			local d = at - p.last
			p.last = at
			p.moved = math.max(p.moved, (at - p.start).Magnitude)
			if state.phase == "inspect" and p.moved >= R.tapMovePx then
				dragX += d.X
				dragY += d.Y
				orbit.auto = false -- stage:48: the first drag stops the turntable
			end
		elseif t == Enum.UserInputType.MouseWheel and state.phase == "inspect" then
			zoomTicks += input.Position.Z
		elseif t == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.Thumbstick2 then
				padX, padY = input.Position.X, -input.Position.Y
			elseif input.KeyCode == Enum.KeyCode.ButtonR2 then
				triggerIn = input.Position.Z
			elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
				triggerOut = input.Position.Z
			end
		end
	end))
	c:add(UserInputService.InputEnded:Connect(function(input: InputObject)
		local p = press
		local t = input.UserInputType
		if
			p == nil
			or not (t == Enum.UserInputType.MouseButton1 or (t == Enum.UserInputType.Touch and input == p.input))
		then
			return
		end
		press = nil
		if
			p.moved < R.tapMovePx
			and state.phase == "inspect"
			and spec.inspectable
			and self:inputOpen()
			and onToy(p.start)
		then
			spec.onInspect()
		end
	end))
	local pinchLast: number? = nil
	c:add(
		UserInputService.TouchPinch:Connect(
			function(_touches, scale: number, _velocity, pinchState: Enum.UserInputState)
				if state.phase ~= "inspect" or pinchState == Enum.UserInputState.End then
					pinchLast = nil
					return
				end
				local last = pinchLast
				if last and last > 0 and scale > 0 then
					orbit.radius /= scale / last -- spread the fingers = closer; orbitStep clamps it
				end
				pinchLast = scale
			end
		)
	)

	-- The frame ------------------------------------------------------------------------------------------------------
	local function step(dt: number)
		clock += dt
		local events = BoxFormat.revealAdvance(state, dt, tapped, result ~= nil)
		tapped = false
		local total = state.total
		for _, event in events do
			if event.kind == "land" then
				spec.sound(BoxFormat.soundCue("land"))
				UiFx.jolt(root, FX.boxLand.jolt)
				if not reduced then
					sqv += A.squash.land
				end
				waveT = 0
				spawn(Vector3.new(0, 0.1, 0), A.sparkles.dust, {
					colors = { "White", table.unpack(boxBlueprint.sparkles) },
					speed = 4,
					up = 0.35,
					cone = 1,
					life = 0.7,
					spread = 2,
					grav = 2,
				})
			elseif event.kind == "tap" then
				local j = event.tap or 0
				local taps = state.taps
				spec.sound(BoxFormat.soundCue("tap"))
				if not reduced then
					sqv -= A.squash.tap + taps * A.squash.tapPerTap
					hopv += A.hop.kick + taps * A.hop.kickPerTap
					lidv += A.lid.kick + taps * A.lid.kickPerTap
					flick = A.ears.flick
				end
				light = A.light.tap + taps * A.light.tapPerTap
				-- H:815-816: the HUD burst and the jolt for tap j
				local wobble = FX.boxWobble
				designSparks(
					wobble.sparks.n + j * wobble.perWobble.n,
					wobble.sparks.spread + j * wobble.perWobble.spread,
					wobble.sparks.colors,
					wobble.sparks.size
				)
				UiFx.jolt(root, wobble.jolt + j * wobble.perWobble.jolt)
				spawn(seamPoint(), A.sparkles.seam + taps * A.sparkles.seamPerTap, {
					colors = boxBlueprint.sparkles,
					speed = 3 + taps,
					up = 1,
					cone = 0.8,
					life = 0.9,
					spread = 1.2,
					grav = 5,
				})
			elseif event.kind == "burst" then
				burstAt = clock
				burst3d()
				burstUi(false)
				showResult(false)
			elseif event.kind == "ready" then
				orbit.auto = not reduced
			end
		end

		-- springs (stage:294-299)
		if not reduced then
			sq, sqv = BoxFormat.spring(sq, sqv, 1, A.squash.k, A.squash.c, dt)
			lid, lidv = BoxFormat.spring(lid, lidv, lidT, A.lid.k, A.lid.c, dt)
			hopv -= A.hop.gravity * dt
			hop += hopv * dt
			if hop < 0 then
				if hopv < A.hop.hardBelow then
					sqv -= math.min(A.hop.landSquashMax, -hopv * A.hop.landSquash)
				end
				hop, hopv = 0, 0
			end
			flick *= A.ears.decay ^ dt
			crown += dt * A.crownRadS
		end
		local y = math.max(A.squash.min, sq)
		local squash = Vector3.new(1 / math.sqrt(y), y, 1 / math.sqrt(y))
		local motion: { [string]: CFrame } = {}
		local phase = state.phase
		if phase == "drop" then
			local height, turn, scaleOfBlob, blobAlpha = BoxFormat.dropPose(state.t)
			if reduced then
				height, turn, scaleOfBlob, blobAlpha = 0, A.restYaw, 1, 1
			end
			rootY, yaw = height, turn
			blob.ImageTransparency = 1 - blobAlpha * (if AssetTable.image(BLOB_KEY) then 1 else A.floor.blobAlpha)
			blobScale = scaleOfBlob
		elseif phase == "idle" then
			local bob, wobble, turn = BoxFormat.idlePose(total, state.taps)
			if reduced then
				bob, wobble, turn = 0, 0, A.restYaw
			end
			rootY, roll, yaw = hop + bob, wobble, turn
			lidT = BoxFormat.lidTarget("idle", state.taps, kind)
			light = math.max(A.light.idle + state.taps * A.light.idlePerTap, light - dt * A.light.decay)
			local rate = A.sparkles.idle + state.taps * A.sparkles.idlePerTap
			if math.random() < dt * rate then
				spawn(
					Vector3.new((math.random() - 0.5) * 2.4, rootY + math.random() * 1.8, (math.random() - 0.5) * 2),
					1,
					{
						colors = boxBlueprint.sparkles,
						speed = 0.6,
						up = 1,
						cone = 0.3,
						life = 1.2,
						spread = 0.2,
						grav = -0.6,
					}
				)
			end
			local seam = built.named.Seam
			if seam then
				seam.Transparency = 1 - BoxFormat.seamAlpha(total, state.taps)
			end
			local keyhole = built.named.Keyhole
			if keyhole then
				keyhole.Color = hsl(0.13, 1, math.clamp(0.7 + state.taps * 0.08, 0, 1))
			end
		else -- open / inspect: t is the time since the burst
			local t = state.t
			rootY = math.max(0, rootY - dt * A.exit.sink)
			roll *= 0.01 ^ dt
			lidT = BoxFormat.lidTarget(phase :: BoxFormat.RevealStage, state.taps, kind)
			local seam = built.named.Seam
			if seam then
				seam.Transparency = 1 - math.max(0, 1 - t)
			end
			light = math.max(0, light - dt * A.light.burstDecay)
			local fly = lidFly
			if fly then
				fly.vel = Vector3.new(fly.vel.X, fly.vel.Y - A.lidFly.gravity * dt, fly.vel.Z)
				fly.pos += fly.vel * dt
				fly.ry += fly.ay * dt
				fly.rx += fly.ax * dt
			end
			-- stage:323: the beam
			if beamImage then
				local sx, sy, alpha = BoxFormat.beamPose(t)
				local share, unitPx = project(Vector3.new(0, 0, 0))
				beam.Visible = share ~= nil and alpha > 0
				if share then
					beam.Position = UDim2.fromScale(share.X, share.Y)
					beam.Size = UDim2.fromOffset(2 * A.beam.bottom * sx * unitPx, A.beam.height * sy * unitPx)
					beam.ImageTransparency = 1 - alpha
				end
			end
			-- stage:324-326: the exit
			local mul, spinning, hidden = BoxFormat.boxExit(t)
			if reduced then
				mul, spinning, hidden = 0, false, true
			end
			if spinning then
				yaw += dt * A.exit.spin
			end
			squash *= mul
			if hidden and boxShown then
				boxShown = false
				stage:removeProp(built.model, false)
				built.model.Parent = nil
			end
			if not poofed and BoxFormat.exitPoofs(t) then
				poofed = true
				spawn(Vector3.new(0, 0.6, 0), A.sparkles.poof, {
					colors = { "White", table.unpack(boxBlueprint.sparkles) },
					speed = 3.5,
					up = 0.6,
					cone = 1,
					life = 0.8,
					spread = 1.6,
					grav = 1,
				})
			end
			-- stage:327-330: the squishy
			if toy then
				local share, centreY, spin, alpha = BoxFormat.toyPose(t)
				if reduced then
					share, centreY, spin = 1, A.toy.y + A.toy.rise, 0
				end
				local bob = if phase == "inspect" and not reduced then BoxFormat.resultBob(total) else 0
				writeToy(
					toyParts,
					toyRoot,
					toyOffset,
					toyFit * share,
					Vector3.new(0, centreY + bob, 0),
					math.pi + spin,
					alpha
				)
			end
			if phase == "inspect" and math.random() < dt * A.sparkles.result then
				spawn(
					Vector3.new((math.random() - 0.5) * 2.6, 0.3 + math.random() * 2.2, (math.random() - 0.5) * 2.6),
					1,
					{
						colors = boxBlueprint.sparkles,
						speed = 0.4,
						up = 1,
						cone = 0.3,
						life = 1.4,
						spread = 0.1,
						grav = -0.5,
					}
				)
			end
		end
		-- the hinge (stage:334-335), the ears, the crown
		local fly = lidFly
		if fly then
			motion.hinge = CFrame.new(fly.pos) * CFrame.Angles(fly.rx, fly.ry, 0)
		elseif kind == "sweet" then
			motion.hinge = CFrame.new(0, -lid * A.sweetRise, 0) * CFrame.Angles(lid, 0, 0)
		else
			motion.hinge = CFrame.Angles(lid, 0, 0)
		end
		if flick ~= 0 then
			motion.earL = CFrame.Angles(-flick, 0, 0)
			motion.earR = CFrame.Angles(flick, 0, 0)
		end
		motion.crown = CFrame.Angles(0, crown, 0)
		if boxShown then
			BoxBuilder.write(built, CFrame.new(0, rootY, 0) * CFrame.Angles(0, yaw, roll), squash, motion)
		end
		-- the floor blob (stage:303), the wave (stage:342), the inner light's glow (G7.8)
		do
			local share, unitPx = project(Vector3.zero)
			if share then
				local px = A.floor.blob * blobScale * unitPx
				blob.Position = UDim2.fromScale(share.X, share.Y)
				blob.Size = UDim2.fromOffset(px, px * flatten)
				if waveT < 1 then
					waveT += dt * A.wave.rate
					local waveScale, waveAlpha = BoxFormat.wavePose(waveT)
					local wpx = 2 * waveScale * unitPx
					wave.Visible = waveAlpha > 0 and not reduced
					wave.Position = UDim2.fromScale(share.X, share.Y)
					wave.Size = UDim2.fromOffset(wpx, wpx * flatten)
					waveStroke.Thickness = math.max(1, (1 - A.wave.inner) * waveScale * unitPx * flatten)
					waveStroke.Transparency = 1 - waveAlpha
				else
					wave.Visible = false
				end
			end
			local glowShare, glowPx = project(seamPoint() + Vector3.new(0, -0.15, 0.3)) -- stage:310
			if glowShare and boxShown then
				local strength = math.clamp(light / A.lightGlowAt, 0, 1)
				local px = LIGHT_SPREAD * glowPx * (0.5 + 0.5 * strength)
				glow.Position = UDim2.fromScale(glowShare.X, glowShare.Y)
				glow.Size = UDim2.fromOffset(px, px)
				glow.ImageTransparency = 1 - strength * 0.9
			else
				glow.ImageTransparency = 1
			end
		end
		-- Royal's coins (stage:336-340)
		for i = #coins, 1, -1 do
			local coin = coins[i]
			local cfg = A.coins
			coin.life -= dt
			local vel = Vector3.new(coin.vel.X, coin.vel.Y - cfg.gravity * dt, coin.vel.Z)
			local pos = coin.part.Position + vel * dt
			if pos.Y < cfg.floor then
				pos = Vector3.new(pos.X, cfg.floor, pos.Z)
				vel = Vector3.new(vel.X * cfg.drag, vel.Y * cfg.bounce, vel.Z * cfg.drag)
			end
			coin.vel = vel
			coin.part.CFrame = CFrame.new(pos)
				* coin.part.CFrame.Rotation
				* CFrame.Angles(coin.spin.X * dt, coin.spin.Y * dt, 0)
			if coin.life < cfg.shrinkS then
				local k = math.max(0.001, coin.life / cfg.shrinkS)
				coin.part.Size = Vector3.new(cfg.thick, 2 * cfg.radius, 2 * cfg.radius) * k
			end
			if coin.life <= 0 then
				coin.part:Destroy()
				table.remove(coins, i)
			end
		end
		stepSparkles(dt, total)
		-- the orbit (T14): enabled in the result idle
		if state.phase == "inspect" then
			orbit = BoxFormat.orbitStep(orbit, dt, {
				dragX = dragX,
				dragY = dragY,
				height = viewport.AbsoluteSize.Y,
				zoom = zoomTicks + (triggerIn - triggerOut) * dt * 5,
				padX = padX,
				padY = padY,
			})
		end
		dragX, dragY, zoomTicks = 0, 0, 0
		placeCamera()
		-- PR21: a Skip pressed before the reply lands as soon as it is in
		if skipWanted and result ~= nil then
			skipWanted = false
			self:skip()
		end
	end

	c:add(Scheduler.add(function(dt: number): boolean
		if done then
			return false
		end
		local ok, err = pcall(function()
			step(dt)
		end)
		if not ok then
			warn("[SD][BoxReveal] step failed:", err)
			if result ~= nil and not final then
				pcall(function()
					self:skip()
				end)
			end
		end
		for i = #tracks, 1, -1 do
			local okTrack, alive = pcall(tracks[i], dt)
			if not okTrack or not alive then
				table.remove(tracks, i)
			end
		end
		return not done
	end, "render"))

	-- Public ---------------------------------------------------------------------------------------------------------
	self.root = root
	self.skipButton = skipButton
	self.equip = equip
	self.again = again
	self.nice = nice
	equip.root.Visible = false
	again.root.Visible = false

	function self.setResult(_: Run, reveal: BoxFormat.Reveal, pending: boolean)
		if result ~= nil or done then
			return
		end
		result = reveal
		savePending = pending
		buildToy(reveal)
	end

	function self.hasResult(_: Run): boolean
		return result ~= nil
	end

	-- PR21: straight to the result with every move done (the box gone, the coins and the lid away, the squishy at
	-- rest); before the reply it lands as soon as the reply is in. False when there is nothing to skip.
	function self.skip(_: Run): boolean
		if done or closing or final then
			return false
		end
		if result == nil then
			skipWanted = true
			return true
		end
		local reveal = result :: BoxFormat.Reveal
		local wasBurst = burstAt ~= nil
		BoxFormat.revealSkip(state)
		if not wasBurst then
			burstAt = clock
			burst3d()
			burstUi(true)
			local def = Catalog.get(reveal.squishyId)
			spec.sound(BoxFormat.soundCue("reveal", if def then def.rarity else nil)) -- the moment's sound (§18.1 #8)
		end
		showResult(true)
		reachResult()
		if boxShown then
			boxShown = false
			stage:removeProp(built.model, false)
		end
		for _, coin in coins do
			coin.part:Destroy()
		end
		table.clear(coins)
		lidFly = nil
		orbit.auto = not reduced
		return true
	end

	function self.isFinal(_: Run): boolean
		return final
	end

	function self.inputOpen(_: Run): boolean
		return final and not closing and BoxFormat.resultInputOpen(resultShownAt, os.clock(), A.resultInputGuardMs)
	end

	function self.setEquip(_: Run, equipState: "normal" | "loading" | "equipped")
		if equipState == "equipped" then
			equip:setText(Strings.common.equipped)
			equip:setState("disabled")
		else
			equip:setState(equipState)
		end
	end

	function self.setAgainOff(_: Run, off: boolean)
		again:setOff(off)
		if againPrice then
			againPrice.TextColor3 = if off then Palette.StickerPriceShort else WHITE
		end
	end

	function self.primary(_: Run): GuiObject
		if final then
			return if equip.root.Visible then equip.root else nice.root
		end
		return skipButton
	end

	-- The close (H:837-840): fade + grow over closeMs (linear), the stage fading over stageFadeMs, removed at
	-- removeMs. "inspect" leaves the squishy on the stage at rest (Inspect adopts it); "matched" / "failed" go at once.
	function self.close(_: Run, reason: Reason)
		if closing or done then
			return
		end
		closing = true
		if reason == "nice" then
			spec.sound(BoxFormat.soundCue("close"))
		end
		local quick = reason == "matched" or reason == "failed" or reason == "again"
		local fade = Tweens.fadeGroup(root)
		if not quick then
			run(R.closeMs, 0, "linear", function(u: number)
				fade:setAlpha(1 - u)
				grow.Scale = 1 + (R.closeScale - 1) * u
				if reason ~= "inspect" then
					viewport.ImageTransparency =
						math.max(viewport.ImageTransparency, math.clamp(u * R.closeMs / R.stageFadeMs, 0, 1))
				end
			end)
		end
		local function finish()
			self:destroy()
		end
		if reason == "inspect" then
			-- the 2D stand-ins go now (Inspect takes the stage), the squishy at rest (native size, the identity pivot)
			-- for Inspect to adopt with stage:setModel
			for _, extra in { blob, wave, beam, glow } :: { GuiObject } do
				extra.Visible = false
			end
			for _, sparkle in sparkles do
				sparkle.frame:Destroy()
			end
			table.clear(sparkles)
			if toy then
				writeToy(toyParts, toyRoot, toyOffset, 1, toyOffset, 0, 1)
				local model = toy
				toy = nil
				stage:removeProp(model, false)
				stage:resetLook()
				stage:setModel(model)
			end
		end
		if quick then
			finish()
		else
			task.delay(R.removeMs / 1000, finish)
		end
	end

	function self.destroy(_: Run)
		if done then
			return
		end
		done = true
		for _, sparkle in sparkles do
			sparkle.frame:Destroy()
		end
		table.clear(sparkles)
		for _, coin in coins do
			coin.part:Destroy()
		end
		table.clear(coins)
		stage:removeProp(built.model, true)
		local model = toy
		toy = nil
		if model then
			stage:removeProp(model, true)
		end
		-- The shared stage never goes with the overlay: unparent it first when it is still here (Inspect took it
		-- otherwise), and reset it when no one else holds a model on it.
		if stage.root:IsDescendantOf(stageHolder) then
			stage:detach()
		end
		if stage:model() == nil then
			stage:clearLayers()
			stage:resetLook()
		end
		Focus.restore(focusToken)
		c:clean()
	end

	function self.debug(_: Run): { [string]: any }
		return {
			phase = state.phase,
			taps = state.taps,
			held = state.held,
			t = state.t,
			total = state.total,
			final = final,
			result = result ~= nil,
			frames = FRAME_BUDGET - free(), -- §9.15: the animated UI frames alive now
			sparkles = #sparkles,
			coins = #coins,
			box = boxShown,
			toy = toy ~= nil,
		}
	end

	task.defer(function()
		if not done and Focus.isGamepad() then
			Focus.select(skipButton) -- ButtonA = Skip (PR21)
		end
	end)
	return self
end

return BoxReveal
