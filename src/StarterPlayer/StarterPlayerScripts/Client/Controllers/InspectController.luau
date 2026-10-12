--!strict
-- InspectController (client only). DESIGN §10 (Inspect, the 3D view of a squishy), §11.7 (the Inspect context),
-- §18.6 (the preview's sfx.squish on the UI group). The "inspect" modal screen: the shared ViewportStage with one
-- SquishyCache "Viewport" clone, the pure UI/OrbitCamera, the squeeze preview, the info panel (UI/InspectPanel driven by
-- the pure UI/InspectFormat) and the equip flow.
--   InspectController.open(squishyId, { source, owned? }) -> boolean   the only path: UIController.open("inspect", ...)
--   InspectController.select(squishyId) -> boolean                    swap the model while open (no new snapshot)
--   InspectController.close(reason?) -> boolean                        UIController.close("inspect", reason)
--   InspectController.squeeze() -> boolean                             a preview tap (merged or rate-limited: false)
--   InspectController.isOpen() / debugState()
-- Entry points (§10.3): registering the screen turns on the Inspect buttons the other screens already built
-- (Squishies, Shop, Boxes rows, the reveal; they open {squishyId, owned, source}) and the onboarding step; this module
-- binds "InspectEquipped" (V / ButtonY, Lobby) and the 8 Collection pedestal prompts (WorldBinder, the pedestal's Slot ->
-- CollectionFormat.squishyForSlot). The kiosk prompt belongs to InventoryController.
-- Open (§10.4): an unknown id falls back to the equipped one; InspectFormat.openAction guards the state machine
-- (Closed -> Opening -> Open -> Closing): open, select (swap the model, reset the view, no new snapshot) or nothing.
-- The restore snapshot is taken once per open: CameraController.save() (CameraType, MouseIconEnabled), the release of
-- ControlsController.block("inspect") (on top of UIController's "modal" block), ProximityPromptService.Enabled (then
-- false). Then the world camera goes Scriptable, the model is built (or adopted from the box reveal: source "boxReveal"
-- and the stage's model has the def's SD_BlueprintId), the stage attaches to the panel's Inspect_Stage, the deformer
-- attaches (twist "pivot"), the Inspect context turns on, one Scheduler render effect runs the orbit, the preview and
-- the dots, the music ducks (Config.Audio.Ducking.inspect) and the panel shows InspectFormat.view / equipState.
-- Input (§10.6): ControlsController's Inspect actions act only while the phase is Open and "inspect" is the top modal
-- (otherwise they pass). Gestures start on the stage (MouseButton1 / Touch) and are followed through UserInputService:
-- drag = OrbitCamera.drag once per frame with the summed delta (H = the viewport height), release = endDrag (no
-- inertia under ReducedMotion), tap (< 8 px, < 300 ms) = the analytic tapRay + hitsBox test against the model's rest
-- bounding box (the stage's framing box; hit = squeeze), two touches = pinch zoom (no rotation; the finger left after a
-- pinch does nothing until lifted). Hold (squishy overhaul spec 2026-10-09 §3.2; stepHold): a press on the model held
-- tapMaxMs with < tapMaxPixels of movement presses the rig (one preview against maxPerSecond) until the finger lifts;
-- moving tapMaxPixels lets go and it is the orbit drag. F / ButtonX (InspectSqueeze) press on Begin and let go on End
-- (first-person spec 2026-10-10 §3.7). Arrow keys and the right stick turn per frame (keyRates /
-- stickRates), the wheel zooms only over the viewport, + / - are one notch, R2 / L2 zoom with Position.Z read from
-- Gamepad1 each frame while held. CAS Cancel, the context turning off and WindowFocusReleased end every drag, pinch,
-- hold and held key.
-- The model's rig (spec §3.2): Inspect owns the model's Anim/SquishRig (hero detail: everything), steps it once a frame
-- and writes the model once (deformer:apply): the wow face on open, then the lobby breathing (HeldSquishyController.
-- idleSample at the lobby weight) and blinks between squeezes, the squish face, bouncing sections; the contact shadow
-- widens with the scale across the squeeze axis. A model adopted from the box reveal goes on with the reveal's rig
-- (takeRig) and its breath: the breathing phase is set so the first frame shows the reveal's breath, going the same way
-- (HeldSquishyController.lobbyPhaseFor), so the shape never jumps at the hand-off. While open the rig counts as one
-- hero rig (Anim/HeroRigs) in the rig budget, and its stepping and write run in the "SD_Rigs" profiler scope (spec
-- §5). The framing uses the toy's own widening (SquishRig.framingWidening). Studio: debugPose freezes a pose.
-- First-person spec 2026-10-10 §3.7: every rig Inspect owns (its own and one adopted from the reveal) squeezes on
-- Config.Inspect.Preview.squeezeAxis (Y as the 3D Lab Inspect, spec 2026-10-11 §6; Banana's third person stays Z),
-- switched at rest (rig:setAxis), so a reveal squeeze in progress finishes first; the framing's widening, the contact
-- shadow and the debug pose read rig:axis().
-- Squeeze preview (§10.7): no remote, no Coins, at most Config.Inspect.Preview.maxPerSecond (InspectFormat.
-- previewAllowed). A preview is a squeeze through Anim/HoldSqueeze (never SqueezeController.play): a press, let go at
-- once for a tap (rig:endPress makes it exactly the rig's tap) or when the finger or key lifts; a press before the
-- running squeeze's pop end merges into it (the mashing cap, about 2.6 a second at most) and is not a preview. It plays
-- the toy's scaled press, its springy recovery and its rarity flourish (the Uncommon / Epic twist, the Epic release
-- kick, the Exclusive section flare; under ReducedMotion none, §18.1). The rig's events give sfx.squish on the UI group
-- at the end of anticipation and the 2D dots in the stage's front layer at peak compression. No hand shows (spec
-- 2026-10-11 §6: the 3D Lab Inspect squeezes the toy alone, design: main.js:95-136).
-- Equip (§10.9) mirrors the Squishies screen: loading, then "Equipped" (a 5 s local confirm) with the inspect.
-- equippedToast notice, or the reason / inspect.equipFailed toast. View in Shop closes Inspect, then opens the shop.
-- Close (§10.10): the Close button, Back / ButtonB / the Roblox menu / a match / another modal opening (UIController:
-- a full stack closes its top, and the spec's closeOnCover closes Inspect before any modal opens over it, so Inspect
-- is always the top modal while open), CharacterRemoving. onClose is idempotent and restores in order: camera
-- (CameraType, MouseIconEnabled) -> block release -> ProximityPromptService.Enabled -> Inspect context off, music back
-- (UIController then restores the gamepad focus and its own "modal" block). Then the deformer goes, the stage model is
-- destroyed if it is still ours, the stage's layers and look reset, the stage detaches if it still sits in our holder,
-- and the per-open Cleanup runs.
-- Readings (DESIGN silent):
-- * The stage is never taken while the box reveal holds it: opened over a lone reveal, Inspect closes itself ("busy").
--   BoxController waits for Inspect to close before it plays a queued reveal.
-- * "owned" shown = StateController.owns(id), or the reveal's owned = true for source "boxReveal" (its reveal hold may
--   lag the state); display only, the server checks every equip.
-- * The preview's dots take the squishy's accent colour (the world puffs' White would not show on the light viewport
--   background), with a thin InkUI outline that fades with them (foam UI restyle, spec 2026-10-09: the ink-outlined
--   look). Dragon's 2 nostril steam puffs are left out of the preview (particles don't render in a viewport, and
--   §10.7's 2D dots already stand for the puffs); its wings and tail flare (sections, they show).
-- * A held trigger whose Gamepad1 level reads 0 (another gamepad, a digital trigger) zooms at full press.
-- * open() without a source uses "api" (Studio hooks).
-- Knead (spec phase2-squeeze §3.1, §3.6; user decisions 2026-10-11): Inspect is the knead screen. buildModel starts
-- Controllers/KneadController on its model (deps.Knead, so tests swap it too; stopped before the model goes: select,
-- close). Once it is live a press on the toy kneads it and off its edge stretches it (the background still orbits, a
-- pinch still zooms), F / ButtonX hold the thumb crunch, Q / ButtonL1 the palm squeeze (InspectPalms), W / ButtonR1
-- re-wax (InspectRewax), R / ButtonY faces it front; the panel's Thumb crunch and Squeeze buttons are holds and Re-wax
-- a press; no hold squeeze, tap preview or Squeeze-button preview. While it builds, or when it cannot (no shell body,
-- the mesh quota, an engine failure), Inspect is exactly as described above. User 2026-10-12: with the wax crunch off
-- (Config.Wax.enabled) there is no re-wax: InspectRewax is not bound (W / ButtonR1 do nothing here) and the panel
-- shows no Re-wax (the knead's view); F / ButtonX are the thumb press.
-- Tests: useDeps(overrides) swaps the side-effecting surfaces (camera, controls, sound, state, UI, stage, cache,
-- deformer, scheduler, panel, input, prompts, Workspace, motion), screenSpec() returns the handlers init() registers
-- and actionHandlers() the ones it binds, so InspectController_Test drives open / select / close, the preview, the keys
-- and the gestures in Edit mode.

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local SquishyBlueprints = require(Shared.Art.SquishyBlueprints)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local HeroRigs = require(Client.Anim.HeroRigs)
local HoldSqueeze = require(Client.Anim.HoldSqueeze)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local SquishRig = require(Client.Anim.SquishRig)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local CollectionFormat = require(Client.UI.CollectionFormat)
local Create = require(Client.UI.Create)
local InspectFormat = require(Client.UI.InspectFormat)
local InspectPanel = require(Client.UI.InspectPanel)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local OrbitCamera = require(Client.UI.OrbitCamera)
local Theme = require(Client.UI.Theme)
local ViewportStage = require(Client.UI.ViewportStage)
local CameraController = require(script.Parent.CameraController)
local ControlsController = require(script.Parent.ControlsController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local KneadController = require(script.Parent.KneadController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

export type OpenOptions = {
	source: string?, -- "hud", "squishies", "shop", "boxes", "boxReveal", "pedestal", ...
	owned: boolean?, -- trusted for source "boxReveal" only (display)
}

-- A frozen frame for Studio checks (debugPose; DebugHooks rigPose): squash 0-1 of the toy's depth, a face, blink 0-1
-- (1 = shut), every section at `sections` × its maxDeg (-1.1 to 1.1; ±1 = ±max).
export type DebugPose = { squash: number?, face: string?, blink: number?, sections: number? }

type GestureMode = "none" | "drag" | "pinch" | "done" | "knead" -- knead: the press is the knead's (spec phase2-squeeze)

-- A pointer's hold gesture: not yet decided, pressing the rig, or over (a tap, the drag, or a finished hold).
type HoldState = "none" | "pressing" | "done"

type Pointer = {
	input: InputObject,
	touch: boolean,
	start: Vector2,
	last: Vector2,
	at: number, -- os.clock() of the press
	moved: number, -- the farthest distance from the start, px
	hold: HoldState,
}

type Gesture = {
	mode: GestureMode,
	pointers: { Pointer },
	pending: Vector2, -- drag delta not yet handed to OrbitCamera.drag (once per frame)
	pinchZoom: number,
	pinchDist: number,
}

type Dot = {
	frame: Frame,
	outline: UIStroke, -- the foam ink outline (foam UI restyle), fading with the dot
	at: number,
	angle: number,
	speed: number,
	center: Vector2, -- frame scale
}

type Session = {
	id: string,
	def: Types.SquishyDef,
	source: string,
	ownedOverride: boolean?,
	stage: ViewportStage.Stage,
	holder: GuiObject,
	model: Model?,
	deformer: SquishDeformer.Deformer?,
	rig: SquishRig.Rig?, -- the model's rig (Inspect steps it)
	out: SquishRig.Out, -- its one out table
	breath: number, -- the breathing's phase (random, or set from breathFrom)
	breathFrom: { amount: number, rising: boolean }?, -- the box reveal's breath at the hand-off, until the first frame
	reduced: boolean?, -- ReducedMotion as the rig last heard it (nil: tell it)
	pose: DebugPose?, -- a frozen debug pose (the rig waits)
	orbit: OrbitCamera.State,
	cleanup: Cleanup.Cleanup,
	-- The restore snapshot (§10.4 step 2), each part cleared once restored.
	camera: CameraController.Snapshot?,
	release: (() -> ())?,
	promptsEnabled: boolean,
	promptsPending: boolean,
	duckRelease: (() -> ())?,
	recent: { number }, -- os.clock() of the recent previews (previewAllowed)
	previews: number,
	keySqueeze: boolean, -- an F / ButtonX press started the squeeze playing (its End lets it go)
	dots: { Dot },
	gesture: Gesture,
	keys: { [Enum.KeyCode]: boolean }, -- arrow keys held
	stick: Vector2,
	triggers: { [Enum.KeyCode]: boolean }, -- R2 / L2 held
	shownKey: string?, -- what panel:show() last showed (id, owned, equipped, shop)
	equip: InspectFormat.EquipState?,
	knead: KneadController.Handle?, -- the knead screen (spec phase2-squeeze §3.6); nil: today's squeeze preview
}

-- Constants

local SCREEN = "inspect"
local REVEAL_SCREEN = "boxReveal"
local SHOP_SCREEN = "shop"
local SHOP_TAB = "squishies"
local SOURCE_REVEAL = "boxReveal"
local SOURCE_HUD = "hud"
local SOURCE_PEDESTAL = "pedestal"
local SOURCE_API = "api"
local CONTEXT: ControlsController.Context = "Inspect"
local BLOCK_REASON = "inspect"
local DUCK_REASON = "inspect"
local EQUIP_ACTION = "InspectEquipped"
local PEDESTAL_TAG = WorldLayout.Tags.CollectionPedestal
local ATTR_SLOT = WorldLayout.Attributes.Slot
local ATTR_BLUEPRINT = "SD_BlueprintId"
local SOUND_SQUISH = "sfx.squish"
local EQUIPPED_TOAST = "inspect.equippedToast"
local GENERIC = "error.generic"
local CONFIRM_SECONDS = 5 -- like the Squishies screen: how long "Equipped" shows before the StateDelta must be in
local PREVIEW_CFG = Config.Inspect.Preview
local INPUT = Config.Inspect.Input
local RIG = Config.Anim.rig
local EVENTS = SquishRig.EVENTS
-- Spec 2026-10-11 §6: Y (Config.validate keeps it "X", "Y" or "Z"; Config types it as a string).
local SQUEEZE_AXIS: SquishRig.Axis = PREVIEW_CFG.squeezeAxis :: any
local PROFILE_RIGS = "SD_Rigs" -- the profiler scope of rig stepping and writes (spec §5)
local TAU = 2 * math.pi
local GAMEPAD = Enum.UserInputType.Gamepad1
local CENTER = Vector2.new(0.5, 0.5)
local DOT_Z = 2

-- The side-effecting surfaces Inspect touches; tests swap them (useDeps).
local REAL_DEPS = {
	Camera = CameraController,
	Controls = ControlsController,
	Sound = SoundController,
	State = StateController,
	UI = UIController,
	Stage = ViewportStage,
	Cache = SquishyCache,
	Deformer = SquishDeformer,
	Scheduler = Scheduler,
	Panel = InspectPanel,
	Input = UserInputService,
	Prompts = ProximityPromptService,
	Workspace = Workspace,
	Motion = Tweens, -- reducedMotion()
	Knead = KneadController, -- start(args): the knead screen (spec phase2-squeeze)
}
type Deps = typeof(REAL_DEPS)

-- Module table

local InspectController = {}

-- Private

local log = Log.new("Inspect")
local deps: Deps = REAL_DEPS
local cleanup: Cleanup.Cleanup? = nil
local panel: InspectPanel.Panel? = nil
local phase: InspectFormat.Phase = "Closed"
local session: Session? = nil
local pendingEquip: string? = nil
local confirmedEquip: string? = nil
local confirmTimer: thread? = nil
local random = Random.new()
-- A rig handed over before the open that adopts its model (takeRig; the box reveal's), with the reveal's breath.
local handoff: { model: Model, rig: SquishRig.Rig, breath: { amount: number, rising: boolean }? }? = nil

local function guarded(label: string, fn: () -> ...any)
	local ok, err = pcall(fn)
	if not ok then
		log:error(`{label} failed:`, err)
	end
end

local function reduced(): boolean
	return deps.Motion.reducedMotion()
end

local function isTop(): boolean
	return deps.UI.topModal() == SCREEN
end

-- Inspect input acts only while it is open and the top modal (§10.6; another modal over it gets the keys).
local function inputLive(): boolean
	return phase == "Open" and session ~= nil and isTop()
end

local function ownedNow(s: Session): boolean
	return deps.State.owns(s.id) or s.ownedOverride == true
end

-- Spec phase2-squeeze §3.6: the knead screen is live (the toy kneads; no squeeze preview).
local function kneadLive(s: Session): boolean
	local knead = s.knead
	return knead ~= nil and knead:isLive()
end

local function equipStateOf(s: Session): InspectFormat.EquipState
	return InspectFormat.equipState(s.id, {
		owned = ownedNow(s),
		equipped = deps.State.equipped() == s.id,
		locked = deps.State.isLobbyLocked(),
		pending = pendingEquip,
		confirmed = confirmedEquip,
	})
end

-- Re-shows the panel when what it shows changed (or `force`), and the Equip button every time.
local function refresh(force: boolean?)
	local s, p = session, panel
	if s == nil or p == nil or (phase ~= "Open" and phase ~= "Opening") then
		return
	end
	local owned = ownedNow(s)
	local equipped = owned and deps.State.equipped() == s.id
	local shop = deps.UI.isRegistered(SHOP_SCREEN)
	local key = `{s.id}|{owned}|{equipped}|{shop}`
	if force or key ~= s.shownKey then
		local view = InspectFormat.view(s.id, { owned = owned, equipped = equipped, shopAvailable = shop })
		if view then
			p:show(view)
			s.shownKey = key
		end
	end
	local state: InspectFormat.EquipState = equipStateOf(s)
	s.equip = state
	p:setEquip(state)
end

local function accentOf(def: Types.SquishyDef): Color3
	local ok, color = pcall(Color3.fromHex, def.visuals.accent)
	return if ok then color else Theme.Colors.lavender
end

-- Squeeze preview and the model's rig ---------------------------------------------------------------------------------

-- The toy's rig for the Inspect model (hero detail: everything), squeezing on Y (not the Catalog axis).
local function newRig(def: Types.SquishyDef): SquishRig.Rig
	local blueprint = SquishyBlueprints[def.blueprintId]
	return SquishRig.new(blueprint.motion :: SquishRig.Motion, {
		axis = SQUEEZE_AXIS,
		rarity = def.rarity :: string,
		reduced = reduced(),
		sections = blueprint.sections,
		foamRecoveryT = def.anim.foamRecoveryT,
	})
end

-- A frozen debug pose in the rig's out shape (spec §6 Studio check 2), on the rig's axis.
local function writePose(def: Types.SquishyDef, pose: DebugPose, out: SquishRig.Out, axis: SquishRig.Axis)
	local blueprint = SquishyBlueprints[def.blueprintId]
	local squeeze = (blueprint.motion :: SquishRig.Motion).squeeze
	local squash = math.clamp(pose.squash or 0, 0, 1)
	local y = 1 - (1 - squeeze.depth) * squash
	out.S = SquishDeformer.axisScale(y, 1 + (1 - y) * squeeze.widen, axis)
	out.twist = 0
	out.face = if pose.face == "squish" or pose.face == "wow" then pose.face else "normal"
	out.blink = 1 - (1 - RIG.blink.closedY) * math.clamp(pose.blink or 0, 0, 1)
	out.cheek = 1 + RIG.looks.cheekPuff * squash
	local sections, turn = blueprint.sections, pose.sections
	out.sectionsOn = sections ~= nil and turn ~= nil
	if sections ~= nil and turn ~= nil then
		for index, name in SquishRig.sectionNames(sections) do
			local section = sections[name]
			local max = math.rad(section.maxDeg or RIG.sections.maxDeg)
			out.sections[index] = (section.sign or 1) * max * math.clamp(turn, -1.1, 1.1)
		end
	end
	out.roll, out.nod, out.pulse = 0, 0, 1
	out.pressAmount = squash
	out.events = 0
	out.awake = true
end

-- The scale across a squeeze axis (the contact shadow's width).
local function across(S: Vector3, axis: string): number
	return if axis == "X" then S.Y else S.X
end

local function clearDots(s: Session)
	for _, dot in s.dots do
		dot.frame:Destroy()
	end
	table.clear(s.dots)
end

-- Where the model centre shows in the view (frame scale), else the middle.
local function dotCenter(s: Session): Vector2
	local stage = s.stage
	local framing = stage:framing()
	local size = stage.viewport.AbsoluteSize
	if framing == nil or size.X <= 0 or size.Y <= 0 then
		return CENTER
	end
	local point =
		ViewportStage.projectPoint(stage.camera.CFrame, stage.camera.FieldOfView, size.X / size.Y, framing.center)
	return point or CENTER
end

local function spawnDots(s: Session, now: number)
	local count = InspectFormat.dotCount(s.def.rarity, reduced())
	local center = dotCenter(s)
	local color = accentOf(s.def)
	for _ = 1, count do
		local frame: Frame = Create("Frame", {
			Name = "PreviewDot",
			AnchorPoint = CENTER,
			Position = UDim2.fromScale(center.X, center.Y),
			Size = UDim2.fromOffset(PREVIEW_CFG.dotSizePx, PREVIEW_CFG.dotSizePx),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			ZIndex = DOT_Z,
		})
		Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = frame })
		local outline = Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.thin, frame)
		frame.Parent = s.stage.front
		table.insert(s.dots, {
			frame = frame,
			outline = outline,
			at = now,
			angle = random:NextNumber(0, TAU),
			speed = random:NextNumber(PREVIEW_CFG.dotSpeedMinPx, PREVIEW_CFG.dotSpeedMaxPx),
			center = center,
		})
	end
end

local function stepDots(s: Session, now: number)
	local dots = s.dots
	for i = #dots, 1, -1 do
		local dot = dots[i]
		local offset, transparency, scale, done = InspectFormat.dotSample(now - dot.at, dot.angle, dot.speed)
		if done or dot.frame.Parent == nil then
			dot.frame:Destroy()
			table.remove(dots, i)
		else
			local size = PREVIEW_CFG.dotSizePx * scale
			dot.frame.Position = UDim2.new(dot.center.X, offset.X, dot.center.Y, offset.Y)
			dot.frame.Size = UDim2.fromOffset(size, size)
			dot.frame.BackgroundTransparency = transparency
			dot.outline.Transparency = transparency
		end
	end
end

-- The model's one write per frame: its rig (squeezes, faces, blinks, sections) times the lobby breathing, or a frozen
-- debug pose. The rig's events give the preview's squish sound and dots.
local function stepRig(s: Session, dt: number, now: number)
	local rig, deformer = s.rig, s.deformer
	if rig == nil or deformer == nil then
		return
	end
	local out = s.out
	local pose = s.pose
	if pose then
		writePose(s.def, pose, out, rig:axis())
	else
		local isReduced = reduced()
		if isReduced ~= s.reduced then
			s.reduced = isReduced
			rig:setReduced(isReduced)
		end
		rig:step(dt, out)
		if bit32.band(out.events, EVENTS.squish) ~= 0 then
			deps.Sound.play(SOUND_SQUISH, { group = "UI" })
		end
		if bit32.band(out.events, EVENTS.peak) ~= 0 then
			spawnDots(s, now)
		end
		-- A model taken from the box reveal breathes on from the reveal's breath (same value, same way), no jump.
		local from = s.breathFrom
		if from then
			s.breathFrom = nil
			s.breath = HeldSquishyController.lobbyPhaseFor(from.amount, from.rising, now)
		end
		-- Between squeezes the lobby breathing (spec §3.2), as a held model's (the lobby weight, no bob).
		out.S *= HeldSquishyController.idleSample(now, s.breath, 1, isReduced)
	end
	deformer:apply(out)
	s.stage:setShadowWiden(across(out.S, rig:axis()))
end

-- One squeeze starts (§10.7; first-person spec §3.7): the rig presses on its axis through Anim/HoldSqueeze, where a
-- press before the running squeeze's pop end merges into it (the mashing cap: about 2.6 squeezes a second at most),
-- within Preview.maxPerSecond (InspectFormat.previewAllowed). Only a squeeze that starts counts as a preview. True when
-- it started.
local function beginSqueeze(s: Session): boolean
	local rig = s.rig
	if s.model == nil or s.deformer == nil or rig == nil then
		return false
	end
	local allowed, recent = InspectFormat.previewAllowed(s.recent, os.clock())
	if not allowed or not HoldSqueeze.begin(rig) then
		return false
	end
	s.recent = recent
	s.previews += 1
	return true
end

-- One preview squeeze (§10.7): a tap (a click or touch on the model, the Squeeze button, squeeze()) is a squeeze let go
-- at once, so the rig plays exactly its tap. True when it started.
local function previewSqueeze(s: Session): boolean
	local rig = s.rig
	if rig == nil or not beginSqueeze(s) then
		return false
	end
	HoldSqueeze.finish(rig)
	return true
end

-- The F / ButtonX press that started the squeeze playing is let go (End, Cancel): before the rig's release start it
-- is exactly a tap, later it pops from where it is.
local function endKeySqueeze(s: Session)
	local rig = s.rig
	if s.keySqueeze then
		s.keySqueeze = false
		if rig ~= nil then
			HoldSqueeze.finish(rig)
		end
	end
end

-- Gestures and held input (§10.6) ----------------------------------------------------------------------------------

-- A pointer's hold is over (it lifted, moved too far, a pinch began, input was cancelled): a pressing one lets the rig
-- go (HoldSqueeze.finish: its release pop, then its spring).
local function releaseHold(s: Session, pointer: Pointer)
	local rig = s.rig
	if pointer.hold == "pressing" and rig ~= nil then
		HoldSqueeze.finish(rig)
	end
	pointer.hold = "done"
end

local function endGestures(s: Session)
	local g = s.gesture
	if g.mode == "drag" then
		OrbitCamera.endDrag(s.orbit, true) -- an aborted drag never flings
	end
	for _, pointer in g.pointers do
		releaseHold(s, pointer)
	end
	table.clear(g.pointers)
	g.mode = "none"
	g.pending = Vector2.zero
end

local function cancelInput(s: Session)
	endGestures(s)
	endKeySqueeze(s)
	local knead = s.knead
	if knead then
		knead:cancel() -- every knead press and hold ends too
	end
	table.clear(s.keys)
	table.clear(s.triggers)
	s.stick = Vector2.zero
end

-- The analytic tap test (§10.6): the camera ray through the tap point against the model's bounding box (the stage's
-- framing box: the rest box, as GetBoundingBox gives it for a model that deforms its meshes only).
local function tapHitsModel(s: Session, position: Vector2): boolean
	local framing = s.stage:framing()
	local viewport = s.stage.viewport
	local size = viewport.AbsoluteSize
	if s.model == nil or framing == nil or size.X <= 0 or size.Y <= 0 then
		return false
	end
	local point = (position - viewport.AbsolutePosition) / size
	if point.X < 0 or point.X > 1 or point.Y < 0 or point.Y > 1 then
		return false
	end
	local camera = s.stage.camera
	local origin, direction = OrbitCamera.tapRay(camera.CFrame, camera.FieldOfView, size.X / size.Y, point)
	local boxCFrame = CFrame.new(framing.center) * framing.pivotRotation
	return OrbitCamera.hitsBox(origin, direction, boxCFrame, framing.size)
end

-- The hold gesture (spec §3.2) of a pointer down `heldMs` that moved at most `movedPx` from its press: "release" once
-- it moved tapMaxPixels (it is the orbit drag; a pressing hold lets go), "press" once it is held tapMaxMs while not yet
-- pressing, else nil.
local function holdStep(heldMs: number, movedPx: number, pressing: boolean): ("press" | "release")?
	if movedPx >= INPUT.tapMaxPixels then
		return "release"
	end
	if not pressing and heldMs >= INPUT.tapMaxMs then
		return "press"
	end
	return nil
end

-- The hold gesture of the one drag pointer, every frame: held still on the model for tapMaxMs, it presses the rig (one
-- preview against maxPerSecond) until it lifts or moves tapMaxPixels (then it is only the orbit drag).
local function stepHold(s: Session, now: number)
	local g = s.gesture
	local pointer = if g.mode == "drag" and #g.pointers == 1 then g.pointers[1] else nil
	if pointer == nil or pointer.hold == "done" then
		return
	end
	local action = holdStep((now - pointer.at) * 1000, pointer.moved, pointer.hold == "pressing")
	if action == "release" then
		releaseHold(s, pointer)
	elseif action == "press" then
		if s.rig ~= nil and inputLive() and tapHitsModel(s, pointer.start) and beginSqueeze(s) then
			pointer.hold = "pressing"
		else
			pointer.hold = "done"
		end
	end
end

local function positionOf(input: InputObject): Vector2
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function pointerBegan(s: Session, input: InputObject)
	local g = s.gesture
	local touch = input.UserInputType == Enum.UserInputType.Touch
	for _, pointer in g.pointers do
		if pointer.input == input or (not touch and not pointer.touch) then
			return -- the same press seen by another layer of the stage
		end
	end
	local position = positionOf(input)
	local pointer: Pointer =
		{ input = input, touch = touch, start = position, last = position, at = os.clock(), moved = 0, hold = "none" }
	if g.mode == "none" and #g.pointers == 0 then
		table.insert(g.pointers, pointer)
		local knead = s.knead
		if knead ~= nil and knead:pointerDown(position, touch) then
			g.mode = "knead" -- spec phase2-squeeze §3.6: a press on the toy kneads it (no orbit, no hold)
			pointer.hold = "done"
			return
		end
		g.mode = "drag"
		g.pending = Vector2.zero
		OrbitCamera.beginDrag(s.orbit)
	elseif g.mode == "drag" and #g.pointers == 1 and touch and g.pointers[1].touch then
		releaseHold(s, g.pointers[1]) -- a pinch is never a hold
		pointer.hold = "done"
		table.insert(g.pointers, pointer)
		g.mode = "pinch"
		g.pending = Vector2.zero
		OrbitCamera.endDrag(s.orbit, true) -- no rotation while pinching
		g.pinchZoom = s.orbit.targetZoom
		g.pinchDist = (position - g.pointers[1].last).Magnitude
	end
end

local function pointerChanged(s: Session, input: InputObject)
	local g = s.gesture
	local knead = s.knead
	if knead ~= nil and #g.pointers == 0 and input.UserInputType == Enum.UserInputType.MouseMovement then
		knead:hover(positionOf(input)) -- the fingertip ring over the toy (spec phase2-squeeze §3.6)
	end
	if #g.pointers == 0 then
		return
	end
	local kind = input.UserInputType
	local pointer: Pointer? = nil
	for _, candidate in g.pointers do
		if
			(kind == Enum.UserInputType.MouseMovement and not candidate.touch)
			or (kind == Enum.UserInputType.Touch and candidate.input == input)
		then
			pointer = candidate
			break
		end
	end
	if pointer == nil then
		return
	end
	local position = positionOf(input)
	local delta = position - pointer.last
	pointer.last = position
	pointer.moved = math.max(pointer.moved, (position - pointer.start).Magnitude)
	if g.mode == "drag" then
		g.pending += delta
	elseif g.mode == "knead" then
		if knead then
			knead:pointerMove(position)
		end
	elseif g.mode == "pinch" and #g.pointers == 2 then
		local distance = (g.pointers[1].last - g.pointers[2].last).Magnitude
		OrbitCamera.setZoom(s.orbit, OrbitCamera.pinchZoom(g.pinchZoom, g.pinchDist, distance))
	end
end

local function pointerEnded(s: Session, input: InputObject)
	local g = s.gesture
	local kind = input.UserInputType
	local index: number? = nil
	for i, candidate in g.pointers do
		if
			(kind == Enum.UserInputType.MouseButton1 and not candidate.touch)
			or (kind == Enum.UserInputType.Touch and candidate.input == input)
		then
			index = i
			break
		end
	end
	if index == nil then
		return
	end
	local pointer = table.remove(g.pointers, index) :: Pointer
	local undecided = pointer.hold == "none" -- a hold (or a would-be hold) is never also a tap
	releaseHold(s, pointer)
	if g.mode == "drag" then
		local height = s.stage.viewport.AbsoluteSize.Y
		if g.pending ~= Vector2.zero then
			OrbitCamera.drag(s.orbit, g.pending.X, g.pending.Y, height, 0)
		end
		g.pending = Vector2.zero
		g.mode = "none"
		local heldMs = (os.clock() - pointer.at) * 1000
		local tap = undecided and OrbitCamera.isTap(pointer.moved, heldMs)
		OrbitCamera.endDrag(s.orbit, tap or reduced())
		if tap and inputLive() and not kneadLive(s) and tapHitsModel(s, pointer.last) then
			previewSqueeze(s)
		end
	elseif g.mode == "knead" then
		local knead = s.knead
		if knead then
			knead:pointerUp()
		end
		g.mode = "none"
	elseif g.mode == "pinch" then
		g.mode = if #g.pointers > 0 then "done" else "none"
	end
	if #g.pointers == 0 then
		g.mode = "none"
		g.pending = Vector2.zero
	end
end

local function connectGestures(s: Session)
	local c = s.cleanup
	local function began(input: InputObject)
		local kind = input.UserInputType
		if session ~= s or not inputLive() then
			return
		end
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			pointerBegan(s, input)
		end
	end
	-- The press can land on any layer of the stage (the holder, the stage frame, the viewport): one pointer each.
	for _, target in { s.holder, s.stage.root, s.stage.viewport } :: { GuiObject } do
		c:add(target.InputBegan:Connect(began))
	end
	c:add(deps.Input.InputChanged:Connect(function(input: InputObject)
		if session == s then
			pointerChanged(s, input)
		end
	end))
	c:add(deps.Input.InputEnded:Connect(function(input: InputObject)
		if session == s then
			pointerEnded(s, input)
		end
	end))
	c:add(deps.Input.WindowFocusReleased:Connect(function()
		cancelInput(s)
	end))
	c:add(deps.Controls.ContextChanged:connect(function(context: string, on: boolean)
		if context == CONTEXT and not on then
			cancelInput(s)
		end
	end))
end

-- Gamepad1's trigger levels (Position.Z); a held trigger that reads 0 counts as fully pressed.
local function triggerLevels(s: Session): (number, number)
	local r2, l2 = 0, 0
	local ok, states = pcall(function(): { InputObject }
		return deps.Input:GetGamepadState(GAMEPAD)
	end)
	if ok then
		for _, state in states do
			if state.KeyCode == Enum.KeyCode.ButtonR2 then
				r2 = state.Position.Z
			elseif state.KeyCode == Enum.KeyCode.ButtonL2 then
				l2 = state.Position.Z
			end
		end
	end
	r2 = if s.triggers[Enum.KeyCode.ButtonR2] then (if r2 > 0 then r2 else 1) else 0
	l2 = if s.triggers[Enum.KeyCode.ButtonL2] then (if l2 > 0 then l2 else 1) else 0
	return r2, l2
end

-- Arrow keys, the right stick and the triggers, applied once per frame.
local function applyHeld(s: Session, dt: number)
	local right, up = 0, 0
	for key in s.keys do
		if not deps.Input:IsKeyDown(key) then
			s.keys[key] = nil -- a release that never reached us
		elseif key == Enum.KeyCode.Right then
			right += 1
		elseif key == Enum.KeyCode.Left then
			right -= 1
		elseif key == Enum.KeyCode.Up then
			up += 1
		elseif key == Enum.KeyCode.Down then
			up -= 1
		end
	end
	if right ~= 0 or up ~= 0 then
		local yawRate, pitchRate = OrbitCamera.keyRates(right, up)
		OrbitCamera.rotate(s.orbit, yawRate * dt, pitchRate * dt)
	end
	if s.stick ~= Vector2.zero then
		local yawRate, pitchRate = OrbitCamera.stickRates(s.stick.X, s.stick.Y)
		if yawRate ~= 0 or pitchRate ~= 0 then
			OrbitCamera.rotate(s.orbit, yawRate * dt, pitchRate * dt)
		end
	end
	if next(s.triggers) ~= nil then
		local r2, l2 = triggerLevels(s)
		local factor = OrbitCamera.triggerFactor(r2, l2, dt)
		if factor ~= 1 then
			OrbitCamera.zoomBy(s.orbit, factor)
		end
	end
end

-- The one per-open render effect: held input, the drag, the orbit, the hold, the model's rig and the preview's dots.
local function step(s: Session, dt: number, now: number): boolean
	if session ~= s or phase ~= "Open" then
		return false
	end
	local stage = s.stage
	if not stage:isAlive() then
		return true
	end
	if isTop() then
		applyHeld(s, dt)
	end
	local g = s.gesture
	if g.mode == "drag" then
		OrbitCamera.drag(s.orbit, g.pending.X, g.pending.Y, stage.viewport.AbsoluteSize.Y, dt)
		g.pending = Vector2.zero
	end
	local yaw, pitch, zoom = OrbitCamera.step(s.orbit, dt)
	if s.model ~= nil and stage:model() == s.model then
		stage:setView(yaw, pitch, zoom)
	end
	local knead = s.knead
	if knead == nil or not knead:isLive() then
		stepHold(s, now) -- kneading, a still press is the finger, not a squeeze
	end
	if knead then
		knead:step(dt, now) -- spec phase2-squeeze: before the rig, so its kicks and face land in this write
	end
	debug.profilebegin(PROFILE_RIGS)
	stepRig(s, dt, now)
	debug.profileend()
	stepDots(s, now)
	return true
end

-- Open, select, close ----------------------------------------------------------------------------------------------------

-- Spec phase2-squeeze §3.1, §3.6: the knead screen on the model buildModel just made (Controllers/KneadController). nil
-- (no shell body, no mesh quota slot) or a failed start keeps today's squeeze preview.
local function startKnead(s: Session)
	local model = s.model
	if model == nil then
		return
	end
	local ok, handle = pcall(deps.Knead.start, {
		model = model,
		def = s.def,
		stage = s.stage,
		orbit = s.orbit,
		rig = function(): SquishRig.Rig?
			return s.rig
		end,
		deformer = function(): SquishDeformer.Deformer?
			return s.deformer
		end,
		-- The deformer again, after the shell joined or left the model (it drives the shell as a solid part).
		reattach = function()
			if session ~= s or s.model ~= model then
				return
			end
			local old = s.deformer
			if old then
				old:destroy()
			end
			s.deformer = deps.Deformer.attach(model, { twist = "pivot" })
		end,
		onView = function(view: KneadController.View?)
			local p = panel
			if p ~= nil and session == s then
				p:setKnead(view)
			end
		end,
		reduced = reduced,
	})
	if ok then
		s.knead = handle
	else
		log:warn("knead start failed:", handle)
	end
end

-- The knead stops before its model goes (select, close): the model, the panel and the view defaults come back.
local function stopKnead(s: Session)
	local knead = s.knead
	s.knead = nil
	if knead then
		guarded("knead stop", function()
			knead:destroy()
		end)
	end
end

-- Builds (or adopts) the model of s.def on the stage, attaches its deformer, gives it its rig (the reveal's when it was
-- handed over, takeRig; else a new one with the wow face) on Y, and resets the view to its defaults.
local function buildModel(s: Session, adopt: boolean)
	local stage = s.stage
	local def = s.def
	local current = stage:model()
	local given = handoff
	handoff = nil
	local model: Model
	local rig: SquishRig.Rig? = nil
	s.breathFrom = nil
	if adopt and current ~= nil and current:GetAttribute(ATTR_BLUEPRINT) == def.blueprintId then
		-- §9.11 handoff: the reveal left its squishy on the stage; take it without a rebuild, with its rig and breath.
		model = stage:takeModel() :: Model
		stage:clearModel() -- any prop the reveal left
		if given ~= nil and given.model == model then
			rig = given.rig
			s.breathFrom = given.breath
		end
	else
		stage:clearModel()
		model = deps.Cache.clone(def.id, "Viewport", 1)
	end
	local own = if rig ~= nil then rig else newRig(def)
	if rig == nil then
		own:setFace("wow", RIG.face.wowSeconds) -- wow on open
	end
	-- Every Inspect rig squeezes on Y (spec 2026-10-11 §6, as the 3D Lab Inspect); the reveal's switches at rest, so
	-- a squeeze it left playing finishes on its own axis first.
	own:setAxis(SQUEEZE_AXIS)
	local motion = SquishyBlueprints[def.blueprintId].motion :: SquishRig.Motion
	stage:setModel(model, SquishRig.framingWidening(motion, own:axis()))
	stage:setRarity(def.rarity)
	s.model = model
	s.deformer = deps.Deformer.attach(model, { twist = "pivot" })
	s.rig = own
	s.out = SquishRig.newOut()
	s.reduced = nil
	s.pose = nil
	HeroRigs.set(s, true) -- one hero rig in the rig budget while open (HeldSquishyController makes room)
	local orbit = s.orbit
	OrbitCamera.setDefaults(orbit, def.inspect.yaw, def.inspect.pitch)
	OrbitCamera.reset(orbit)
	OrbitCamera.snap(orbit)
	stage:setView(OrbitCamera.view(orbit))
	startKnead(s)
end

-- §10.4 select: swap the model, reset the view; the restore snapshot stays.
local function selectInto(s: Session, def: Types.SquishyDef, source: string, owned: boolean?)
	cancelInput(s)
	stopKnead(s)
	clearDots(s)
	s.rig = nil
	s.pose = nil
	s.stage:setShadowWiden(1)
	local deformer = s.deformer
	s.deformer = nil
	if deformer then
		deformer:destroy()
	end
	local old = s.model
	s.model = nil
	if old ~= nil and s.stage:model() ~= old then
		old:Destroy() -- ours but no longer the stage's: nobody else will
	end
	s.id = def.id
	s.def = def
	s.source = source
	s.ownedOverride = if source == SOURCE_REVEAL and owned == true then true else nil
	s.shownKey = nil
	buildModel(s, false) -- clearModel destroys the old model
	refresh(true)
end

local function beginSession(def: Types.SquishyDef, source: string, owned: boolean?)
	local p = panel
	if p == nil then
		return
	end
	phase = "Opening"
	local stage = deps.Stage.get()
	local s: Session = {
		id = def.id,
		def = def,
		source = source,
		ownedOverride = if source == SOURCE_REVEAL and owned == true then true else nil,
		stage = stage,
		holder = p.stageHolder,
		model = nil,
		deformer = nil,
		rig = nil,
		out = SquishRig.newOut(),
		breath = random:NextNumber(0, TAU),
		breathFrom = nil,
		reduced = nil,
		pose = nil,
		orbit = OrbitCamera.new(def.inspect.yaw, def.inspect.pitch),
		cleanup = Cleanup.new(),
		camera = nil,
		release = nil,
		promptsEnabled = true,
		promptsPending = false,
		duckRelease = nil,
		recent = {},
		previews = 0,
		keySqueeze = false,
		dots = {},
		gesture = { mode = "none", pointers = {}, pending = Vector2.zero, pinchZoom = 1, pinchDist = 0 },
		keys = {},
		stick = Vector2.zero,
		triggers = {},
		shownKey = nil,
		equip = nil,
		knead = nil,
	}
	session = s
	-- §10.4 step 2: the restore snapshot, once per open.
	s.camera = deps.Camera.save()
	s.release = deps.Controls.block(BLOCK_REASON)
	s.promptsEnabled = deps.Prompts.Enabled
	s.promptsPending = true
	deps.Prompts.Enabled = false
	-- Step 3: the world camera freezes.
	local camera = deps.Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local ok, err = pcall(function()
		-- Step 5 (the effect first, so the stage's own light follows this frame's camera).
		s.cleanup:add(deps.Scheduler.add(function(dt: number, now: number): boolean
			return step(s, dt, now)
		end, "render"))
		buildModel(s, source == SOURCE_REVEAL)
		stage:attach(s.holder)
		-- Step 6.
		deps.Controls.setContext(CONTEXT, true)
		s.duckRelease = deps.Sound.duck(DUCK_REASON)
		connectGestures(s)
		phase = "Open"
		refresh(true)
	end)
	if not ok then
		log:error("open failed:", err)
		-- Still "Opening": the close below restores the snapshot and frees the stage.
		task.defer(function()
			if session == s then
				deps.UI.close(SCREEN, "failed")
			end
		end)
	end
end

-- UIController's onOpen: §10.4's guard, then open or select.
local function onOpen(params: any?)
	local p = if type(params) == "table" then params else {}
	local requested = p.squishyId
	local def = if type(requested) == "string" then Catalog.get(requested) else nil
	if def == nil then
		def = Catalog.get(deps.State.equipped())
	end
	if def == nil then
		return
	end
	local source = if type(p.source) == "string" then p.source else SOURCE_API
	local owned = if type(p.owned) == "boolean" then p.owned else nil
	local s = session
	local action = InspectFormat.openAction(phase, if s then s.id else nil, def.id)
	if s ~= nil then
		if action == "select" and phase == "Open" then
			selectInto(s, def, source, owned)
		end
		return
	end
	if deps.UI.isOpen(REVEAL_SCREEN) then
		-- The reveal holds the one viewport stage: Inspect never takes it from under it.
		task.defer(function()
			if session == nil then
				deps.UI.close(SCREEN, "busy")
			end
		end)
		return
	end
	beginSession(def, source, owned)
end

-- §10.10 restore, in order; each part runs once.
local function restore(s: Session)
	local snapshot = s.camera
	s.camera = nil
	if snapshot then
		guarded("camera restore", function()
			deps.Camera.restore(snapshot)
		end)
	end
	local release = s.release
	s.release = nil
	if release then
		guarded("controls release", release)
	end
	if s.promptsPending then
		s.promptsPending = false
		guarded("prompts restore", function()
			deps.Prompts.Enabled = s.promptsEnabled
		end)
	end
	guarded("context off", function()
		deps.Controls.setContext(CONTEXT, false)
	end)
	local duck = s.duckRelease
	s.duckRelease = nil
	if duck then
		guarded("music duck release", duck)
	end
end

-- UIController's onClose (idempotent): restore, then free the stage (§10.11).
local function onClose(reason: string)
	local s = session
	if s == nil or phase == "Closing" or phase == "Closed" then
		return
	end
	phase = "Closing"
	stopKnead(s) -- first: its cursor, the panel and the model are back before the snapshot restores
	restore(s)
	cancelInput(s)
	clearDots(s)
	s.rig = nil
	s.pose = nil
	HeroRigs.set(s, false)
	handoff = nil
	local deformer = s.deformer
	s.deformer = nil
	if deformer then
		guarded("deformer destroy", function()
			deformer:destroy()
		end)
	end
	local stage = s.stage
	if deps.Stage.exists() and stage:isAlive() then
		guarded("stage release", function()
			if s.model ~= nil and stage:model() == s.model then
				stage:clearModel()
			end
			stage:clearLayers()
			stage:resetLook()
			if stage.root.Parent == s.holder then
				stage:detach()
			end
		end)
	end
	s.model = nil
	s.cleanup:clean()
	session = nil
	phase = "Closed"
	local toastKey = InspectFormat.closeToastKey(reason)
	local text = if toastKey then Strings.resolve(toastKey) else nil
	if text then
		deps.UI.toast(text, "info")
	end
end

-- Panel buttons ----------------------------------------------------------------------------------------------------------

local function equip()
	local s = session
	if s == nil or phase ~= "Open" or pendingEquip ~= nil or equipStateOf(s) ~= "equip" then
		return
	end
	local id = s.id
	pendingEquip = id
	refresh()
	local result = NetController.equipSquishyAsync(id)
	pendingEquip = nil
	if result.ok then
		confirmedEquip = id
		if confirmTimer then
			task.cancel(confirmTimer)
		end
		confirmTimer = task.delay(CONFIRM_SECONDS, function()
			confirmTimer = nil
			confirmedEquip = nil
			refresh()
		end)
		NotifyController.show(EQUIPPED_TOAST, nil, "success")
	else
		local reason = result.reason
		local known = type(reason) == "string" and reason ~= GENERIC and KeyText.has("reason." .. reason)
		-- One sound per action (§18.5.2 B5): the toast carries ui.error.
		deps.UI.toast(
			if known then Strings.reasonText(reason) else Strings.inspect.equipFailed,
			"warn",
			{ sound = "ui.error" }
		)
	end
	refresh()
end

local function viewInShop()
	local s = session
	if s == nil or phase ~= "Open" then
		return
	end
	local id = s.id
	deps.UI.close(SCREEN, "viewInShop")
	deps.UI.open(SHOP_SCREEN, { tab = SHOP_TAB, squishyId = id })
end

local function resetView()
	local s = session
	if s ~= nil and phase == "Open" then
		OrbitCamera.reset(s.orbit)
	end
end

local callbacks: InspectPanel.Callbacks = {
	onClose = function()
		deps.UI.close(SCREEN, "button")
	end,
	onSqueeze = function()
		local s = session
		if s ~= nil and phase == "Open" and not kneadLive(s) then -- kneading, Squeeze is the palms' hold
			previewSqueeze(s)
		end
	end,
	onResetView = resetView,
	onEquip = equip,
	onViewInShop = viewInShop,
	-- Spec phase2-squeeze §3.6: the panel's Thumb crunch and Squeeze holds, and Re-wax.
	onKneadHold = function(action: string, down: boolean)
		local s = session
		local knead = if s ~= nil and phase == "Open" then s.knead else nil
		if knead == nil or (down and not (knead:isLive() and isTop())) then
			return
		end
		if action == "crunch" then
			knead:crunch(down)
		elseif action == "palms" then
			knead:palms(down)
		end
	end,
	onRewax = function()
		local s = session
		local knead = if s ~= nil and phase == "Open" then s.knead else nil
		if knead ~= nil and knead:isLive() and isTop() then
			knead:rewax()
		end
	end,
}

local screenSpec: UIController.ScreenSpec = {
	closeOnCover = true, -- §10.10: another modal opening over Inspect closes it (Inspect never sits under a screen)
	build = function(parent: Instance): GuiObject
		local p = deps.Panel.new(parent, callbacks)
		panel = p
		return p.root
	end,
	onOpen = onOpen,
	onClose = onClose,
	primary = function(): GuiObject?
		local p = panel
		return if p then p:primary() else nil
	end,
}

-- ControlsController handlers (§10.6) ------------------------------------------------------------------------------

-- Wraps an Inspect action: Cancel ends every gesture and held input and passes; otherwise `fn` runs only while Inspect
-- input is live (an End always reaches it, so a held key never sticks).
local function inspectAction(
	fn: (s: Session, state: Enum.UserInputState, input: InputObject?) -> boolean?
): ControlsController.Handler
	return function(state: Enum.UserInputState, input: InputObject?): boolean?
		local s = session
		if s == nil then
			return nil
		end
		if state == Enum.UserInputState.Cancel then
			cancelInput(s)
			return nil
		end
		local live = inputLive()
		if state == Enum.UserInputState.End then
			local handled = fn(s, state, input)
			return if live and handled then true else nil
		end
		if not live then
			return nil
		end
		return fn(s, state, input)
	end
end

local function onPress(fn: (s: Session) -> ()): ControlsController.Handler
	return inspectAction(function(s: Session, state: Enum.UserInputState): boolean?
		if state == Enum.UserInputState.Begin then
			fn(s)
		end
		return true
	end)
end

local function overViewport(s: Session, input: InputObject): boolean
	local viewport = s.stage.viewport
	local at, size = viewport.AbsolutePosition, viewport.AbsoluteSize
	local x, y = input.Position.X, input.Position.Y
	return x >= at.X and y >= at.Y and x <= at.X + size.X and y <= at.Y + size.Y
end

local HANDLERS: { [string]: ControlsController.Handler } = {
	InspectRotateKeys = inspectAction(function(s: Session, state: Enum.UserInputState, input: InputObject?): boolean?
		if input == nil then
			return nil
		end
		if state == Enum.UserInputState.Begin then
			s.keys[input.KeyCode] = true
		elseif state == Enum.UserInputState.End then
			s.keys[input.KeyCode] = nil
		end
		return true
	end),
	InspectZoomIn = onPress(function(s: Session)
		OrbitCamera.zoomBy(s.orbit, OrbitCamera.wheelFactor(1))
	end),
	InspectZoomOut = onPress(function(s: Session)
		OrbitCamera.zoomBy(s.orbit, OrbitCamera.wheelFactor(-1))
	end),
	InspectWheel = inspectAction(function(s: Session, state: Enum.UserInputState, input: InputObject?): boolean?
		if input == nil or state == Enum.UserInputState.End or not overViewport(s, input) then
			return nil -- off the viewport the info list scrolls
		end
		OrbitCamera.zoomBy(s.orbit, OrbitCamera.wheelFactor(input.Position.Z))
		return true
	end),
	-- F / ButtonX (first-person spec §3.7): down presses (HoldSqueeze), up lets go; a quick press is exactly a tap.
	-- Kneading (spec phase2-squeeze §3.6) they hold the thumb crunch instead.
	InspectSqueeze = inspectAction(function(s: Session, state: Enum.UserInputState): boolean?
		local knead = s.knead
		if state == Enum.UserInputState.Begin then
			if knead ~= nil and knead:isLive() then
				knead:crunch(true)
			elseif beginSqueeze(s) then
				s.keySqueeze = true
			end
		elseif state == Enum.UserInputState.End then
			endKeySqueeze(s)
			if knead then
				knead:crunch(false)
			end
		end
		return true
	end),
	-- Q / ButtonL1 hold the palm squeeze (spec phase2-squeeze §3.6); it passes unless kneading (W / ButtonR1: below).
	InspectPalms = inspectAction(function(s: Session, state: Enum.UserInputState): boolean?
		local knead = s.knead
		if knead == nil or (state == Enum.UserInputState.Begin and not knead:isLive()) then
			return nil
		end
		if state == Enum.UserInputState.Begin then
			knead:palms(true)
		elseif state == Enum.UserInputState.End then
			knead:palms(false)
		end
		return true
	end),
	InspectReset = onPress(function(s: Session)
		OrbitCamera.reset(s.orbit)
	end),
	InspectStick = inspectAction(function(s: Session, state: Enum.UserInputState, input: InputObject?): boolean?
		if state == Enum.UserInputState.End or input == nil then
			s.stick = Vector2.zero
		else
			s.stick = Vector2.new(input.Position.X, input.Position.Y)
		end
		return true
	end),
	InspectZoomTriggers = inspectAction(function(s: Session, state: Enum.UserInputState, input: InputObject?): boolean?
		if input == nil then
			return nil
		end
		if state == Enum.UserInputState.Begin then
			s.triggers[input.KeyCode] = true
		elseif state == Enum.UserInputState.End then
			s.triggers[input.KeyCode] = nil
		end
		return true
	end),
}
-- W / ButtonR1 re-wax (spec phase2-squeeze §3.6); it passes unless kneading. User 2026-10-12: only with the wax crunch
-- on (Config.Wax.enabled); off there is no re-wax and W / ButtonR1 are not bound.
if Config.Wax.enabled then
	HANDLERS.InspectRewax = inspectAction(function(s: Session, state: Enum.UserInputState): boolean?
		local knead = s.knead
		if knead == nil or not knead:isLive() then
			return nil
		end
		if state == Enum.UserInputState.Begin then
			knead:rewax()
		end
		return true
	end)
end

-- Public -----------------------------------------------------------------------------------------------------------------

-- Opens Inspect on a squishy (an unknown id shows the equipped one). True once it is open on it.
function InspectController.open(squishyId: string?, opts: OpenOptions?): boolean
	local params = {
		squishyId = squishyId,
		source = if opts and opts.source then opts.source else SOURCE_API,
		owned = if opts then opts.owned else nil,
	}
	local opened = deps.UI.open(SCREEN, params)
	return opened and phase == "Open"
end

-- Swaps the model while open (§10.4 select). False when closed or for an unknown id.
function InspectController.select(squishyId: string): boolean
	local s = session
	local def = Catalog.get(squishyId)
	if s == nil or phase ~= "Open" or def == nil then
		return false
	end
	if s.id ~= def.id then
		selectInto(s, def, s.source, nil)
	end
	return true
end

function InspectController.close(reason: string?): boolean
	return deps.UI.close(SCREEN, reason or "closed")
end

-- The squeeze preview (§10.7), a tap. False when closed, merged into the running squeeze or over the rate limit.
function InspectController.squeeze(): boolean
	local s = session
	if s == nil or phase ~= "Open" then
		return false
	end
	return previewSqueeze(s)
end

function InspectController.isOpen(): boolean
	return phase == "Open"
end

-- Takes over the squishy rig of a model Inspect adopts (the box reveal's model, see the header's Open paragraph): from
-- now on Inspect steps it and the giver stops (one owner per rig, spec 2026-10-09 §3.2). Before the open it waits for
-- the open that adopts that model (any other open drops it); on the model Inspect shows now it takes over at once.
-- breath / rising: the giver's breath at the hand-off (IdleRig:breathNow); Inspect's breathing goes on from it.
function InspectController.takeRig(model: Model, rig: SquishRig.Rig, breath: number?, rising: boolean?)
	local from = if breath ~= nil then { amount = breath, rising = rising ~= false } else nil
	local s = session
	if s ~= nil and s.model == model then
		handoff = nil
		rig:setAxis(SQUEEZE_AXIS) -- Y from its next rest, like every Inspect rig
		s.rig = rig
		s.reduced = nil
		s.breathFrom = from
		return
	end
	handoff = { model = model, rig = rig, breath = from }
end

-- Studio (DebugHooks rigPose): freezes the open model in `pose` (DebugPose; the rig waits), or lets it live again with
-- nil. False while Inspect is not open on a model.
function InspectController.debugPose(pose: DebugPose?): boolean
	local s = session
	if s == nil or phase ~= "Open" or s.rig == nil then
		return false
	end
	s.pose = pose
	return true
end

-- Studio debug hooks and the leak / restore checks (§10.11).
function InspectController.debugState(): { [string]: any }
	local s = session
	local stageExists = deps.Stage.exists()
	local stage = if stageExists then deps.Stage.get() else nil
	local camera = deps.Workspace.CurrentCamera
	local selected = GuiService.SelectedObject
	local view = { yaw = 0, pitch = 0, zoom = 1 }
	local rig = if s then s.rig else nil
	local knead = if s then s.knead else nil
	local pressing = false
	if s then
		local yaw, pitch, zoom = OrbitCamera.view(s.orbit)
		view = { yaw = yaw, pitch = pitch, zoom = zoom }
		for _, pointer in s.gesture.pointers do
			pressing = pressing or pointer.hold == "pressing"
		end
	elseif stage then
		local yaw, pitch, zoom = stage:view()
		view = { yaw = yaw, pitch = pitch, zoom = zoom }
	end
	return {
		squeezing = rig ~= nil and rig:elapsedMs() ~= nil, -- the rig plays a squeeze (a tap or a hold)
		pressing = pressing, -- a hold presses the rig
		face = if s then s.out.face else nil,
		posed = s ~= nil and s.pose ~= nil, -- a debug pose is frozen
		ok = true,
		phase = phase,
		squishyId = if s then s.id else nil,
		owned = if s then ownedNow(s) else nil,
		source = if s then s.source else nil,
		hasModel = s ~= nil and s.model ~= nil and stage ~= nil and stage:model() == s.model,
		stageAttached = stage ~= nil and stage:isAttached(),
		viewportDescendants = if stage then #stage.viewport:GetDescendants() else -1,
		view = view,
		previews = if s then s.previews else 0,
		dots = if s then #s.dots else 0,
		cameraType = if camera then camera.CameraType.Name else "none",
		mouseIconEnabled = deps.Input.MouseIconEnabled,
		promptsEnabled = deps.Prompts.Enabled,
		blocked = deps.Controls.isBlocked(),
		blockReasons = deps.Controls.blockReasons(),
		contexts = deps.Controls.activeContexts(),
		selectedObject = if selected then selected:GetFullName() else nil,
		musicDucked = s ~= nil and s.duckRelease ~= nil,
		restorePending = s ~= nil and (s.camera ~= nil or s.release ~= nil or s.promptsPending),
		equip = if s then s.equip else nil,
		pendingEquip = pendingEquip,
		knead = if knead then knead:debugState() else nil, -- spec phase2-squeeze §3.14 (Studio checks)
	}
end

-- Test seam (Edit mode): replaces some of the side-effecting surfaces (nil = the real ones again).
function InspectController.useDeps(overrides: { [string]: any }?)
	if overrides == nil then
		deps = REAL_DEPS
		return
	end
	local merged: { [string]: any } = table.clone(REAL_DEPS :: any)
	for key, value in overrides do
		assert(merged[key] ~= nil, `[SD][Inspect] unknown dependency {key}`)
		merged[key] = value
	end
	deps = merged :: any
end

-- The screen handlers init() registers (tests drive them without UIController).
function InspectController.screenSpec(): UIController.ScreenSpec
	return screenSpec
end

-- The Inspect action handlers init() binds (tests drive them without ControlsController).
function InspectController.actionHandlers(): { [string]: ControlsController.Handler }
	return HANDLERS
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function InspectController.init()
	local c = Cleanup.new()
	cleanup = c
	-- Added first, so it runs last (after the screen is unregistered and closed).
	c:add(function()
		if confirmTimer then
			task.cancel(confirmTimer)
			confirmTimer = nil
		end
		pendingEquip, confirmedEquip = nil, nil
		local p = panel
		panel = nil
		if p then
			p:destroy()
		end
	end)
	c:add(deps.UI.registerScreen(SCREEN, screenSpec))
	for action, handler in HANDLERS do
		c:add(deps.Controls.bindAction(action, handler))
	end
	c:add(deps.Controls.bindAction(EQUIP_ACTION, function(state: Enum.UserInputState): boolean?
		if state ~= Enum.UserInputState.Begin then
			return nil
		end
		return InspectController.open(deps.State.equipped(), { source = SOURCE_HUD })
	end))
	c:add(WorldBinder.registerStand(PEDESTAL_TAG, function(stand: Instance)
		local slot = stand:GetAttribute(ATTR_SLOT)
		local id = if type(slot) == "number" then CollectionFormat.squishyForSlot(slot) else nil
		if id then
			InspectController.open(id, { source = SOURCE_PEDESTAL })
		end
	end))
	for _, field in { "owned", "equipped" } do
		c:add(deps.State.changed(field):connect(function()
			if field == "equipped" then
				confirmedEquip = nil
			end
			refresh()
		end))
	end
	c:add(deps.State.LobbyLockChanged:connect(function()
		refresh()
	end))
	c:add(deps.UI.LayoutChanged:connect(function(class: Layout.LayoutClass)
		local p = panel
		if p then
			p:setLayout(class)
		end
	end))
	local player = Players.LocalPlayer
	if player then
		c:add(player.CharacterRemoving:Connect(function()
			if phase ~= "Closed" then
				InspectController.close("characterRemoving")
			end
		end))
	end
	log:debug("ready")
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function InspectController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return InspectController
