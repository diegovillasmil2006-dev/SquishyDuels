--!strict
-- CapsuleController (client only). Lobby bases spec 2026-10-11 §5.3, §9; progression spec 2026-10-12 §3-§7; build plan
-- Phase 5. The island's capsules on this client: their feel and the capsule card. Nothing here decides anything: the
-- card only sends CapsuleUpgrade / CapsuleUnlock / CapsuleSet and shows the server's answer; the feel is cosmetic.
-- * Bases: every plot Model tagged WorldLayout.Tags.Base (attribute Plot). BaseService's "Capsules" Folder on it,
--   replaced on every redraw, holds Capsule<slot> (attributes SD_Level, SD_Squishy), Squishy<slot> and Lock<slot>. A
--   plot's owner is the player whose SD_Plot attribute is that plot. Models are containers (their parts stream in), so
--   every part is looked up when it is used and may be missing.
-- * Feel (Anim/CapsuleFeel, Config.UI.Capsule), only on a capsule within cullStuds of the camera and on the screen
--   (AmbientMath.sphereOnScreen), never under ReducedMotion (Tweens.reducedMotion):
--   - a rise of an owner's SD_Squeezes<slot> (CapsuleService counts every capsule squeeze) plays that capsule's
--     squeeze: its Press comes down and back up (its rod stretches with it) while the squishy squashes and springs
--     (SquishDeformer with a pivot twist, attached for the motion and destroyed after it, so the model is at rest
--     between motions). The owner also sees "+N Coins" / "+N Grip" (CapsuleFormat.popTexts) over the capsule in a
--     pooled BillboardGui, styled as the squeeze popups (SqueezeController.popupColor); it rises and fades
--     (CapsuleFeel.pop; under ReducedMotion it holds still and fades). Anyone else sees a few sparkles, never numbers.
--   - an accepted own squeeze (SqueezeController.ResultReceived) while the local root stands in the own plot
--     (WorldLayout.inPlot: the server pushes the capsules then) gives every own capsule with a squishy a small squish.
--   - a redrawn Capsule<slot> whose SD_Level rose under the same owner is an upgrade: a ring flash over the drum in its
--     trim colour (FxShapes.ring), the squishy stretches and spins, brick confetti in the capsule's own colours (FxPool
--     parts, Config.Vfx.Confetti speeds) and the level plate pops (UiFx.punch); a new tier look (an evolve) is the
--     bigger burst (a second, wider ring, more bricks, a bigger stretch, two turns). A plot seen for the first time or
--     for a new owner plays nothing.
--   - a motion never cuts a bigger one (tap < squeeze < upgrade < evolve), and a squeeze never cuts a squeeze whose
--     press still moves. One Scheduler render effect steps every motion, pop and brick from its start time (never
--     added up, so a frame skip changes nothing) and ends when nothing runs.
-- * Card (modal "capsule"; UI/CapsuleFormat; the house components): a foam panel with its header tab ("Capsule N",
--   Mint) and Close on its corner, a scrolling body (the squishy and "Tap to swap", tier and level, the evolve preview,
--   the speed, Coins/h, Grip/h; a locked slot shows the lock and its word) and a pinned footer: one ConfirmButton (the
--   §11.5 two-step spend: Upgrade / Evolve / Unlock with the price; disabled with its reason: Needs Grip Lv N, Unlock
--   capsule N first or a pause; not enough Coins shows the missing amount), or one line (Top level!, or "Only <name> can
--   upgrade this." for a visitor). Tap to swap shows the owned squishies (CapsuleFormat.swapList, the one already in
--   this capsule left out) as buttons with their power or where they sit, and Back; a pick sends CapsuleSet. The
--   owner's card reads StateController (capsules, Coins, Grip, data status); a visitor's reads the plot's models.
--   It opens from the ProximityPrompt this module puts in front of every capsule and lock (E / ButtonX within
--   promptStuds; SqueezeController holds a key squeeze while a prompt shows) or from a tap / click on a capsule:
--   ControlsController.setPointerClaim takes a world press whose camera ray first hits a capsule's drum, tube or cap
--   within clickStuds (so it is no squeeze), and the card opens on its release when that was a tap (under
--   Config.Inspect.Input tapMaxPixels and tapMaxMs; else it was a camera drag). With no params: the own capsule 1 (the
--   layout audit). A success bursts on the card (UiFx; "large" for an evolve or an unlock) with ui.purchase; a refusal
--   shows its reason (NotifyController.showResult). Its width is CapsuleFormat.cardWidth and its body scrolls within
--   heightShare of the screen (DailyFormat.bodyHeight, the Daily panel's rule). A visitor's card closes when the
--   owner leaves.
-- shortcut: no sound on a capsule squeeze (the spec gives none, and four capsules every 1.3-4 s would be noise); add an
-- AssetTable slot with roblox-audio if the user wants one.
-- Public: destroy() (tests and leak checks; the bootstrap never calls it).

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local GripMath = require(Shared.GripMath)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local AmbientMath = require(Client.Anim.AmbientMath)
local CapsuleFeel = require(Client.Anim.CapsuleFeel)
local FxPool = require(Client.Anim.FxPool)
local FxShapes = require(Client.Anim.FxShapes)
local Scheduler = require(Client.Anim.Scheduler)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local Tweens = require(Client.Anim.Tweens)
local Button = require(Client.UI.Components.Button)
local CapsuleFormat = require(Client.UI.CapsuleFormat)
local ConfirmButton = require(Client.UI.Components.ConfirmButton)
local Create = require(Client.UI.Create)
local DailyFormat = require(Client.UI.DailyFormat)
local Focus = require(Client.UI.Focus)
local LockIcon = require(Client.UI.Components.LockIcon)
local StaticIcon = require(Client.UI.Components.StaticIcon)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local ControlsController = require(script.Parent.ControlsController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local SqueezeController = require(script.Parent.SqueezeController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

type Kind = "tap" | "squeeze" | "upgrade" | "evolve"

-- A capsule's press at rest and how far it comes down (measured at the start of each squeeze, everything at rest).
type Rig = {
	press: BasePart,
	rod: BasePart?,
	pressBase: CFrame,
	rodBase: CFrame,
	rodSize: Vector3,
	travel: number, -- studs
	contact: number, -- the share of the travel where the press meets the squishy's top
}

type Motion = { kind: Kind, at: number, duration: number, squishy: Model?, rig: Rig? }

type Pop = { gui: BillboardGui, coins: TextLabel, grip: TextLabel, strokes: { UIStroke }, at: number? }

type Brick = { part: BasePart, from: Vector3, velocity: Vector3, spin: Vector3, at: number }

type Shown = { plot: number, slot: number }

type Tap = { input: InputObject, from: Vector3, at: number, plot: number, slot: number }

type Levels = { owner: number, slots: { [number]: number } }

type CardRefs = {
	root: Frame,
	title: TextLabel,
	tab: Frame,
	close: Button.Button,
	body: ScrollingFrame,
	bodyList: UIListLayout,
	info: Frame,
	squishyRow: TextButton,
	icon: StaticIcon.StaticIcon,
	name: TextLabel,
	swapHint: TextLabel,
	lockRow: Frame,
	lockText: TextLabel,
	tier: TextLabel,
	evolve: TextLabel,
	speed: TextLabel,
	coins: TextLabel,
	grip: TextLabel,
	empty: TextLabel,
	swapTitle: TextLabel,
	swapList: Frame,
	confirm: ConfirmButton.ConfirmButton,
	back: Button.Button,
	note: TextLabel,
}

-- Constants

local C = Config.UI.Capsule
local TOUCH = Config.UI.Touch
local TAP = Config.Inspect.Input -- the house tap: under tapMaxPixels and tapMaxMs
local PARTICLES = Config.Anim.squeeze.particles
local CONFETTI = Config.Vfx.Confetti
local SCREEN = "capsule"
local MODAL_GUI = "SD_Modal"
local CLIENT_FX = "SD_ClientFx"
local FOLDER = "Capsules" -- BaseService's folder on a plot model
local TAG_BASE = WorldLayout.Tags.Base
local ATTR_PLOT_MODEL = WorldLayout.Attributes.Plot
local ATTR_PLOT = "SD_Plot"
local ATTR_SQUEEZES = "SD_Squeezes" -- .. slot (CapsuleService)
local ATTR_LEVEL = "SD_Level"
local ATTR_SQUISHY = "SD_Squishy"
local SLOTS = #Config.Grip.Capsule.slotPrices
local RANK: { [Kind]: number } = { tap = 1, squeeze = 2, upgrade = 3, evolve = 4 }
local PRESS_SECONDS = (C.pressDownMs + C.pressHoldMs + C.pressUpMs) / 1000
local RAY_PARTS: { [string]: boolean } = { Drum = true, Tube = true, Cap = true } -- a capsule's parts a ray can hit
local BRICK_PARTS = { "Drum", "DrumTrim", "Band1", "Band2", "Band3" } -- the confetti takes their colours
local PROMPT_NAME = "SD_CapsulePrompt"
local SOUND_PURCHASE = "ui.purchase"
-- Readings on SDTools CapsuleBuilder's capsule (pivot at the drum's bottom centre, its front along -Z; the drum's top
-- at 1.5, the cap's top at 9.5, the knob's top at 10.9): the prompt point in front of the drum, the pop clear of the
-- knob (above the drum's centre, its Adornee), the ring just over the drum, the bricks from the cap's top, the bounding
-- sphere for the on-screen test.
local PROMPT_OFFSET = CFrame.new(0, 2.5, -4.2)
local POP_STUDS = 13
local RING_STUDS = 1.6
local BRICK_STUDS = 9.5
local SPHERE_UP = 5.5
local SPHERE_RADIUS = 6.5
local SECOND_RING = 1.4 -- the evolve's second ring: this much wider and slower
local POP_PX = Vector2.new(220, 56)
-- Foam UI (as the Daily panel): Close sits CLOSE_INSET from the panel's right edge; the body pads its rows.
local CLOSE_INSET = 16
local BODY_PAD_PX = 6
local SCROLLBAR_PX = 6
local ROW_GAP = 8
local LOCK_PX = 28

-- Module table

local CapsuleController = {}

-- Private

local cleanup: Cleanup.Cleanup? = nil
local plots: { [number]: Model } = {}
local plotCleanups: { [number]: Cleanup.Cleanup } = {} -- the prompts and connections of each plot's current folder
local playerCleanups: { [Player]: Cleanup.Cleanup } = {}
local levels: { [number]: Levels } = {}
local motions: { [Model]: Motion } = {} -- by capsule model
local pops: { [number]: Pop } = {} -- by own slot
local bricks: { Brick } = {}
local effect: Scheduler.Handle? = nil
local refs: CardRefs? = nil
local swapRows: Cleanup.Cleanup? = nil
local swapSignature: string? = nil
local firstSwap: GuiObject? = nil
local shown: Shown? = nil -- the card's plot and slot while it is open
local swapping = false
local pending = false -- a capsule remote is running
local pendingTap: Tap? = nil

local function ownerOf(plot: number): Player?
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(ATTR_PLOT) == plot then
			return player
		end
	end
	return nil
end

local function folderOf(plot: number): Instance?
	local model = plots[plot]
	return if model then model:FindFirstChild(FOLDER) else nil
end

local function modelIn(parent: Instance?, name: string): Model?
	local found = if parent then parent:FindFirstChild(name) else nil
	return if found and found:IsA("Model") then found else nil
end

local function hasParts(model: Model): boolean
	return model:FindFirstChildWhichIsA("BasePart", true) ~= nil
end

-- Within cullStuds of the camera and on the screen.
local function visible(capsule: Model): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil or not capsule:IsDescendantOf(Workspace) then
		return false
	end
	local pivot = capsule:GetPivot()
	local centre = pivot.Position + pivot.UpVector * SPHERE_UP
	if (centre - camera.CFrame.Position).Magnitude > C.cullStuds then
		return false
	end
	local point = camera:WorldToViewportPoint(centre)
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	return AmbientMath.sphereOnScreen(point.X, point.Y, point.Z, SPHERE_RADIUS, camera.ViewportSize, tanHalf)
end

-- The press, its rod and their travel (CapsuleBuilder: upright cylinders, their length along X; the squishy stands on
-- the drum, its pivot at its bottom centre), measured with everything at rest; nil when a part has not streamed in.
local function measure(capsule: Model, squishy: Model?): Rig?
	local press = capsule:FindFirstChild("Press")
	if squishy == nil or press == nil or not press:IsA("BasePart") or not hasParts(squishy) then
		return nil
	end
	local found = capsule:FindFirstChild("PressRod")
	local rod = if found and found:IsA("BasePart") then found else nil
	local pivot = capsule:GetPivot()
	local pressBottom = pivot:PointToObjectSpace(press.Position).Y - press.Size.X / 2
	local box, size = squishy:GetBoundingBox()
	local bottom = pivot:PointToObjectSpace(squishy:GetPivot().Position).Y
	local top = pivot:PointToObjectSpace(box.Position).Y + size.Y / 2
	local travel = pressBottom - (bottom + (top - bottom) * C.squashHeight)
	if not (travel > 0) then
		return nil
	end
	return {
		press = press,
		rod = rod,
		pressBase = press.CFrame,
		rodBase = if rod then rod.CFrame else CFrame.identity,
		rodSize = if rod then rod.Size else Vector3.zero,
		travel = travel,
		contact = math.clamp((pressBottom - top) / travel, 0, 1),
	}
end

local function setPress(capsule: Model, rig: Rig, share: number)
	local down = capsule:GetPivot().UpVector * (share * rig.travel)
	rig.press.CFrame = rig.pressBase - down
	local rod = rig.rod
	if rod then
		rod.Size = rig.rodSize + Vector3.new(share * rig.travel, 0, 0)
		rod.CFrame = rig.rodBase - down / 2
	end
end

-- The squishy at `height` (its width from CapsuleFeel.width), turned `turn` about its pivot.
local function shape(squishy: Model?, height: number, turn: number)
	if squishy == nil or not squishy:IsDescendantOf(Workspace) then
		return
	end
	local deformer = SquishDeformer.get(squishy) or SquishDeformer.attach(squishy, { twist = "pivot" })
	local width = CapsuleFeel.width(height)
	deformer:set(Vector3.new(width, height, width), turn)
end

-- The capsule as built again: the press up, the squishy's deformer destroyed (it rests the model first).
local function rest(capsule: Model, motion: Motion)
	local rig = motion.rig
	if rig then
		setPress(capsule, rig, 0)
	end
	local squishy = motion.squishy
	local deformer = if squishy then SquishDeformer.get(squishy) else nil
	if deformer then
		deformer:destroy()
	end
end

local function setPop(pop: Pop, rise: number, transparency: number)
	pop.gui.StudsOffsetWorldSpace = Vector3.new(0, POP_STUDS + rise, 0)
	pop.coins.TextTransparency = transparency
	pop.grip.TextTransparency = transparency
	for _, stroke in pop.strokes do
		stroke.Transparency = transparency
	end
end

-- One frame of every running motion, pop and brick (the one Scheduler effect; it ends when nothing runs).
local function step(_dt: number, _now: number): boolean
	local now = os.clock()
	for capsule, motion in motions do
		local t = now - motion.at
		if t >= motion.duration or not capsule:IsDescendantOf(Workspace) then
			rest(capsule, motion)
			motions[capsule] = nil
		elseif motion.kind == "squeeze" then
			local rig = motion.rig :: Rig
			local share, height = CapsuleFeel.squeeze(t, rig.contact)
			setPress(capsule, rig, share)
			shape(motion.squishy, height, 0)
		elseif motion.kind == "tap" then
			shape(motion.squishy, CapsuleFeel.spring(t, C.tapSquish), 0)
		else
			local height, turn = CapsuleFeel.upgrade(t, motion.kind == "evolve")
			shape(motion.squishy, height, turn)
		end
	end
	local busy = next(motions) ~= nil
	local reduced = Tweens.reducedMotion()
	for _, pop in pops do
		local at = pop.at
		if at then
			local rise, transparency, done = CapsuleFeel.pop(now - at, reduced)
			setPop(pop, rise, transparency)
			if done then
				pop.at = nil
				pop.gui.Enabled = false
			else
				busy = true
			end
		end
	end
	local pool = FxPool.default()
	for index = #bricks, 1, -1 do
		local brick = bricks[index]
		local t = now - brick.at
		local offset, transparency, done = CapsuleFeel.brick(brick.velocity, t)
		if done then
			pool:release(brick.part)
			table.remove(bricks, index)
		else
			local turn = brick.spin * t
			brick.part.CFrame = CFrame.new(brick.from + offset) * CFrame.Angles(turn.X, turn.Y, turn.Z)
			brick.part.Transparency = transparency
		end
	end
	if busy or #bricks > 0 then
		return true
	end
	effect = nil
	return false
end

local function wake()
	if effect == nil then
		effect = Scheduler.add(step, "render")
	end
end

-- Starts a motion on a visible capsule (see the header for what it may cut).
local function play(kind: Kind, capsule: Model, squishy: Model?)
	if Tweens.reducedMotion() or not visible(capsule) then
		return
	end
	local running = motions[capsule]
	if running then
		local pressMoving = running.kind == "squeeze" and os.clock() - running.at < PRESS_SECONDS
		if RANK[kind] < RANK[running.kind] or (kind == "squeeze" and pressMoving) then
			return
		end
		rest(capsule, running)
		motions[capsule] = nil
	end
	local rig = if kind == "squeeze" then measure(capsule, squishy) else nil
	if kind == "squeeze" and rig == nil then
		return
	end
	motions[capsule] = {
		kind = kind,
		at = os.clock(),
		duration = CapsuleFeel.duration(kind),
		squishy = squishy,
		rig = rig,
	}
	wake()
end

-- The pooled pop of an own slot (built on first use in the PlayerGui, kept across respawns).
local function popOf(slot: number): Pop?
	local known = pops[slot]
	if known then
		return known
	end
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if gui == nil then
		return nil
	end
	local billboard: BillboardGui = Create("BillboardGui", {
		Name = "SD_CapsulePop" .. slot,
		AlwaysOnTop = false, -- the player's body hides it, so it never covers the player
		LightInfluence = 0,
		ResetOnSpawn = false,
		MaxDistance = C.cullStuds,
		Size = UDim2.fromOffset(POP_PX.X, POP_PX.Y),
		Enabled = false,
		Parent = gui,
	})
	Theme.list(Enum.FillDirection.Vertical, 0, billboard)
	-- The squeeze popups' look: "+N Coins" InkUI with the white outline, "+N Grip" Mint with the InkUI outline.
	local coins = Theme.label(
		{ Name = "Coins", LayoutOrder = 1, TextWrapped = false, Parent = billboard },
		"Button",
		nil,
		Theme.Colors.inkUI
	)
	local grip = Theme.label(
		{ Name = "Grip", LayoutOrder = 2, TextWrapped = false, Parent = billboard },
		"Button",
		nil,
		SqueezeController.popupColor("grip")
	)
	local strokes = {
		Theme.stroke(Theme.Colors.white, Theme.Stroke.medium, coins),
		Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.text, grip),
	}
	for _, stroke in strokes do
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	end
	local pop: Pop = { gui = billboard, coins = coins, grip = grip, strokes = strokes, at = nil }
	pops[slot] = pop
	return pop
end

-- The owner's "+N Coins" / "+N Grip" over an own capsule.
local function showPop(slot: number, capsule: Model, squeezes: number)
	local capsules = StateController.get("capsules")
	local entry = if type(capsules) == "table" and type(capsules.list) == "table" then capsules.list[slot] else nil
	local coins, grip = CapsuleFormat.popTexts(true, squeezes, entry)
	local drum = capsule:FindFirstChild("Drum")
	if coins == nil or grip == nil or drum == nil or not drum:IsA("BasePart") then
		return
	end
	local pop = popOf(slot)
	if pop == nil then
		return
	end
	pop.coins.Text = coins
	pop.grip.Text = grip
	pop.gui.Adornee = drum
	pop.at = os.clock()
	setPop(pop, 0, 0)
	pop.gui.Enabled = true
	wake()
end

-- A few sparkles over a squishy (what a visitor sees of a squeeze).
local function sparkle(squishy: Model?)
	if squishy == nil or not hasParts(squishy) then
		return
	end
	local box, size = squishy:GetBoundingBox()
	FxPool.default():emit(box.Position + Vector3.new(0, size.Y / 2, 0), C.sparkles, {
		Texture = Config.Vfx.Textures.sparkles,
		Lifetime = NumberRange.new(PARTICLES.lifetimeMin, PARTICLES.lifetimeMax),
		Size = NumberSequence.new(C.sparkleStuds, PARTICLES.sizeTo),
		Speed = NumberRange.new(PARTICLES.speedMin, PARTICLES.speedMax),
		SpreadAngle = Vector2.new(PARTICLES.spreadDeg, PARTICLES.spreadDeg),
		Color = ColorSequence.new(Theme.Colors.white),
	})
end

-- An owner's capsule squeezed `squeezes` times (their SD_Squeezes<slot> rose).
local function onSqueezed(owner: Player, slot: number, squeezes: number)
	local plot = owner:GetAttribute(ATTR_PLOT)
	local folder = if type(plot) == "number" then folderOf(plot) else nil
	local capsule = modelIn(folder, "Capsule" .. slot)
	if capsule == nil or not visible(capsule) then
		return
	end
	local squishy = modelIn(folder, "Squishy" .. slot)
	play("squeeze", capsule, squishy)
	if owner == Players.LocalPlayer then
		showPop(slot, capsule, squeezes)
	else
		sparkle(squishy)
	end
end

local function watchPlayer(player: Player)
	local pc = Cleanup.new()
	playerCleanups[player] = pc
	for slot = 1, SLOTS do
		local name = ATTR_SQUEEZES .. slot
		local first = player:GetAttribute(name)
		local seen = if type(first) == "number" then first else 0
		pc:add(player:GetAttributeChangedSignal(name):Connect(function()
			local value = player:GetAttribute(name)
			if type(value) ~= "number" then
				return
			end
			local added = value - seen
			seen = value
			if added > 0 then
				onSqueezed(player, slot, added)
			end
		end))
	end
end

-- The upgrade burst on a redrawn capsule (the bigger one for a new tier look).
local function burst(capsule: Model, squishy: Model?, evolve: boolean)
	if Tweens.reducedMotion() or not visible(capsule) then
		return
	end
	play(if evolve then "evolve" else "upgrade", capsule, squishy)
	local plate = capsule:FindFirstChild("Level", true)
	if plate and plate:IsA("GuiObject") then
		UiFx.punch(plate, C.platePop, C.platePopMs)
	end
	local pivot = capsule:GetPivot()
	local trim = capsule:FindFirstChild("DrumTrim")
	local ringAt = pivot.Position + pivot.UpVector * RING_STUDS
	local ringColor = if trim and trim:IsA("BasePart") then trim.Color else Theme.Colors.white
	FxShapes.ring(ringAt, pivot.UpVector, C.ringStuds, C.ringMs / 1000, ringColor)
	if evolve then
		local wide, slow = C.ringStuds * SECOND_RING, C.ringMs * SECOND_RING / 1000
		FxShapes.ring(ringAt, pivot.UpVector, wide, slow, Theme.Colors.white)
	end
	local colors: { Color3 } = {}
	for _, name in BRICK_PARTS do
		local part = capsule:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(colors, part.Color)
		end
	end
	if #colors == 0 then
		return
	end
	local from = pivot.Position + pivot.UpVector * BRICK_STUDS
	local rng = Random.new()
	local pool = FxPool.default()
	local now = os.clock()
	for index = 1, if evolve then C.evolveBricks else C.bricks do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local out = rng:NextNumber(CONFETTI.outMin, CONFETTI.outMax)
		local spin = math.rad(rng:NextNumber(CONFETTI.spinMinDeg, CONFETTI.spinMaxDeg))
		table.insert(bricks, {
			part = pool:acquirePart({
				Name = "CapsuleBrick",
				Size = C.brickSize,
				Color = colors[(index - 1) % #colors + 1],
				CFrame = CFrame.new(from),
			}),
			from = from,
			velocity = Vector3.new(
				math.cos(angle) * out,
				rng:NextNumber(CONFETTI.upMin, CONFETTI.upMax),
				math.sin(angle) * out
			),
			spin = Vector3.new(spin, spin / 2, 0),
			at = now,
		})
	end
	wake()
end

-- A visitor's view of the plot's capsules (its models' SD_Level / SD_Squishy), shaped as the capsules state field.
local function capsulesFromPlot(plot: number): any
	local folder = folderOf(plot)
	local list = {}
	for slot = 1, SLOTS do
		local capsule = modelIn(folder, "Capsule" .. slot)
		if capsule == nil then
			break
		end
		list[slot] = { level = capsule:GetAttribute(ATTR_LEVEL), squishyId = capsule:GetAttribute(ATTR_SQUISHY) }
	end
	return { slots = math.max(1, #list), list = list }
end

-- Card -------------------------------------------------------------------------------------------------------------

local refreshCard: () -> ()

local function open(plot: number, slot: number)
	UIController.open(SCREEN, { plot = plot, slot = slot })
end

-- The prompt in front of a capsule or a lock, on its host part (again whenever that part streams back in).
local function addPrompt(fc: Cleanup.Cleanup, plot: number, slot: number, model: Model, hostName: string)
	local function attach(host: Instance)
		if host.Name ~= hostName or not host:IsA("BasePart") or host:FindFirstChild(PROMPT_NAME) then
			return
		end
		local attachment: Attachment = Create("Attachment", {
			Name = PROMPT_NAME,
			CFrame = host.CFrame:ToObjectSpace(model:GetPivot() * PROMPT_OFFSET),
		})
		local prompt: ProximityPrompt = Create("ProximityPrompt", {
			ActionText = Strings.capsule.prompt,
			ObjectText = "",
			HoldDuration = 0,
			KeyboardKeyCode = Enum.KeyCode.E,
			GamepadKeyCode = Enum.KeyCode.ButtonX,
			MaxActivationDistance = C.promptStuds,
			RequiresLineOfSight = false,
			Parent = attachment,
		})
		fc:add(prompt.Triggered:Connect(function()
			open(plot, slot)
		end))
		attachment.Parent = host
		fc:add(attachment)
	end
	local host = model:FindFirstChild(hostName)
	if host then
		attach(host)
	end
	fc:add(model.ChildAdded:Connect(attach))
end

-- A plot's Capsules folder appeared (a redraw, or the first look): its prompts, and the upgrade bursts.
local function onFolder(plot: number, folder: Instance)
	local old = plotCleanups[plot]
	if old then
		old:clean()
	end
	local fc = Cleanup.new()
	plotCleanups[plot] = fc
	local owner = ownerOf(plot)
	local userId = if owner then owner.UserId else 0
	local known = levels[plot]
	if known == nil or known.owner ~= userId then
		known = { owner = userId, slots = {} }
		levels[plot] = known
	end
	local slots = (known :: Levels).slots
	local function onChild(child: Instance)
		local kind, digit = string.match(child.Name, "^(%a+)(%d)$")
		local slot = tonumber(digit)
		if slot == nil or not child:IsA("Model") then
			return
		end
		if kind == "Capsule" then
			addPrompt(fc, plot, slot, child, "Drum")
			local level = child:GetAttribute(ATTR_LEVEL)
			local before = slots[slot]
			if type(level) == "number" then
				if type(before) == "number" and level > before then
					local evolve = CapsuleMath.tier(level) ~= CapsuleMath.tier(before)
					burst(child, modelIn(folder, "Squishy" .. slot), evolve)
				end
				slots[slot] = level
			end
		elseif kind == "Lock" then
			addPrompt(fc, plot, slot, child, "Post")
			slots[slot] = nil
		end
	end
	for _, child in folder:GetChildren() do
		onChild(child)
	end
	fc:add(folder.ChildAdded:Connect(onChild))
	if shown and shown.plot == plot then
		refreshCard()
	end
end

local function watchPlot(c: Cleanup.Cleanup, model: Instance)
	local plot = model:GetAttribute(ATTR_PLOT_MODEL)
	if type(plot) ~= "number" or not model:IsA("Model") then
		return
	end
	plots[plot] = model
	local folder = model:FindFirstChild(FOLDER)
	if folder then
		onFolder(plot, folder)
	end
	c:add(model.ChildAdded:Connect(function(child: Instance)
		if child.Name == FOLDER then
			onFolder(plot, child)
		end
	end))
end

local function gripLevel(): number
	local grip = StateController.get("grip")
	return if type(grip) == "table" and type(grip.total) == "number" then GripMath.levelFor(grip.total) else 1
end

local function cardModel(): CapsuleFormat.Card?
	local s = shown
	local owner = if s then ownerOf(s.plot) else nil
	if s == nil or owner == nil then
		return nil
	end
	local own = owner == Players.LocalPlayer
	return CapsuleFormat.card({
		slot = s.slot,
		capsules = if own then StateController.get("capsules") else capsulesFromPlot(s.plot),
		own = own,
		ownerName = owner.DisplayName,
		coins = StateController.coins(),
		gripLevel = gripLevel(),
		status = StateController.dataStatus(),
		pending = pending,
	})
end

-- The owned squishies this capsule can take (every one but the squishy already in it).
local function swapChoices(slot: number): { CapsuleFormat.SwapEntry }
	local choices = {}
	for _, entry in CapsuleFormat.swapList(StateController.owned(), StateController.get("capsules"), slot) do
		if not entry.here then
			table.insert(choices, entry)
		end
	end
	return choices
end

local function setText(label: TextLabel, text: string?)
	label.Visible = text ~= nil
	label.Text = text or ""
end

-- The panel's width (CapsuleFormat.cardWidth), the body's height (within heightShare of the screen, the rest scrolls)
-- and the panel's place: centred with what hangs above it (the header tab, Close), as the Daily panel.
local function fit()
	local r = refs
	if r == nil then
		return
	end
	local gui = UIController.screenGui(MODAL_GUI)
	local scale = UIController.scale()
	local pop = r.root:FindFirstChild("SD_OpenScale")
	local s = scale * (if pop and pop:IsA("UIScale") then pop.Scale else 1)
	local screen = gui.AbsoluteSize
	if not (scale > 0) or not (s > 0) or screen.X <= 0 or screen.Y <= 0 then
		return
	end
	local width = UDim2.fromOffset(math.floor(CapsuleFormat.cardWidth(screen.X, scale)), 0)
	if r.root.Size ~= width then
		r.root.Size = width
	end
	local above = math.max(r.tab.AbsoluteSize.Y / s, TOUCH.closeButton) / 2
	local position = UDim2.new(0.5, 0, 0.5, math.floor(above / 2 + 0.5))
	if r.root.Position ~= position then
		r.root.Position = position
	end
	local current = r.body.AbsoluteSize.Y / s
	local chrome = r.root.AbsoluteSize.Y / s - current + above
	local content = r.bodyList.AbsoluteContentSize.Y / s + 2 * BODY_PAD_PX
	local height = math.ceil(DailyFormat.bodyHeight(screen.Y / scale, content, chrome, C.heightShare, TOUCH.minTarget))
	if math.abs(height - current) >= 1 then
		r.body.Size = UDim2.new(1, 0, 0, height)
	end
end

local swapTo: (squishyId: string) -> ()

-- The swap buttons (rebuilt only when the choices change, so a Coins tick never drops the gamepad focus).
local function fillSwap(r: CardRefs, choices: { CapsuleFormat.SwapEntry })
	local keys = {}
	for _, entry in choices do
		table.insert(keys, entry.id .. "=" .. (entry.note or ""))
	end
	local signature = table.concat(keys, ",")
	if signature == swapSignature then
		return
	end
	swapSignature = signature
	local rows = swapRows or Cleanup.new()
	rows:clean()
	swapRows = rows
	firstSwap = nil
	for index, entry in choices do
		local button = rows:add(Button.new({
			name = "Capsule_Pick" .. index .. "Button",
			text = entry.name,
			subtext = entry.note or entry.power, -- where it sits matters more: picking it empties that capsule
			kind = "secondary",
			height = TOUCH.minTarget,
			layoutOrder = index,
			parent = r.swapList,
			onActivated = function()
				swapTo(entry.id)
			end,
		}))
		firstSwap = firstSwap or button.root
	end
end

refreshCard = function()
	local r = refs
	local s = shown
	if r == nil or s == nil or not UIController.isOpen(SCREEN) then
		return
	end
	local model = cardModel()
	if model == nil then
		UIController.close(SCREEN, "gone")
		return
	end
	local own = model.visitorText == nil
	local choices = if own and not model.locked then swapChoices(s.slot) else {}
	local canSwap = #choices > 0
	local swap = swapping and canSwap
	r.title.Text = model.title
	r.info.Visible = not swap
	r.swapTitle.Visible = swap
	r.swapList.Visible = swap
	r.back.root.Visible = swap
	r.squishyRow.Visible = not model.locked
	r.squishyRow.Interactable = canSwap
	r.squishyRow.Selectable = canSwap
	r.icon.root.Visible = model.squishyId ~= nil
	if model.squishyId then
		r.icon:setSquishy(model.squishyId)
	end
	setText(r.name, model.squishyName)
	setText(r.swapHint, if canSwap then model.swapText else nil)
	r.lockRow.Visible = model.locked
	r.lockText.Text = model.lockedText or ""
	setText(r.tier, model.tierText)
	setText(r.evolve, model.evolveText)
	setText(r.speed, model.speedText)
	setText(r.coins, model.coinsText)
	setText(r.grip, model.gripText)
	setText(r.empty, model.emptyText)
	local buttonShown = model.buttonText ~= nil and not swap
	r.confirm.root.Visible = buttonShown
	if buttonShown then
		r.confirm:setText(model.buttonText)
		r.confirm:setPrice(model.price, math.max(0, StateController.coins() or 0))
		local blocked = model.state == "gripLocked" or model.state == "notNext" or model.state == "paused"
		r.confirm:setDisabled(if blocked then model.reason or "" else nil)
		r.confirm:setLoading(model.state == "pending")
	end
	setText(r.note, if swap then nil else model.maxText or model.visitorText)
	if swap then
		fillSwap(r, choices)
	end
	fit()
end

local function showSwap(on: boolean)
	swapping = on
	refreshCard()
	local r = refs
	if r then
		r.body.CanvasPosition = Vector2.zero
		Focus.select(if on then firstSwap else r.squishyRow)
	end
end

-- Sends the card's buy (CapsuleUpgrade or CapsuleUnlock with the price shown); the server decides.
local function buy()
	local model = cardModel()
	local r = refs
	if model == nil or r == nil or pending or model.state ~= "ready" or model.action == nil then
		return
	end
	pending = true
	refreshCard()
	local remote = if model.action == "unlock" then "CapsuleUnlock" else "CapsuleUpgrade"
	local result = NetController.invokeAsync(remote, model.slot, model.price)
	pending = false
	r.confirm:setLoading(false)
	if result.ok then
		local at: GuiObject = if r.tier.Visible then r.tier else r.root
		UiFx.burst(at, if model.action == "upgrade" then "medium" else "large", Theme.Colors.gold)
		UiFx.punch(at)
		SoundController.play(SOUND_PURCHASE)
	else
		NotifyController.showResult(result)
	end
	refreshCard()
end

swapTo = function(squishyId: string)
	local s = shown
	local r = refs
	if s == nil or r == nil or pending then
		return
	end
	pending = true
	refreshCard()
	local result = NetController.invokeAsync("CapsuleSet", s.slot, squishyId)
	pending = false
	if result.ok then
		showSwap(false)
		UiFx.punch(r.icon.root)
	else
		NotifyController.showResult(result)
		refreshCard()
	end
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local panel = Theme.panel({
		Name = "Capsule",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.floor(CapsuleFormat.cardWidth(gui.AbsoluteSize.X, UIController.scale())), 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.panel, Theme.Padding.large)
	c:add(panel)
	-- Room at the top for Close's lower half, then the header tab (it raises the padding for its own half).
	local pad = panel:FindFirstChildOfClass("UIPadding") :: UIPadding
	pad.PaddingTop = UDim.new(0, math.ceil(TOUCH.closeButton / 2) + Theme.Padding.small)
	local tab, title = Theme.headerTab(panel, "", { accent = "mint" })
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = panel,
	})
	local contentList =
		Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, content, Enum.HorizontalAlignment.Center)
	local close = Button.new({
		name = "Capsule_CloseButton",
		text = Strings.common.close,
		kind = "close",
		height = TOUCH.closeButton,
		parent = panel,
		sound = false, -- UIController.close plays ui.back
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	close.root.AnchorPoint = Vector2.new(1, 0.5)
	close.root.Position = UDim2.new(1, Theme.Padding.large - CLOSE_INSET, 0, -pad.PaddingTop.Offset)
	close.root.ZIndex = tab.ZIndex
	close.root.Modal = true -- frees the cursor in shift lock / first person
	c:add(close)

	-- The body scrolls when the screen is too short (fit); the footer stays under it.
	local body: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Body",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		LayoutOrder = 1,
		Parent = content,
	})
	local bodyList = Theme.list(
		Enum.FillDirection.Vertical,
		Theme.Padding.small,
		body,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Top
	)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, BODY_PAD_PX),
		PaddingBottom = UDim.new(0, BODY_PAD_PX),
		PaddingRight = UDim.new(0, SCROLLBAR_PX),
		Parent = body,
	})
	local info: Frame = Create("Frame", {
		Name = "Info",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 1,
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, info, Enum.HorizontalAlignment.Center)

	-- The squishy: its picture, its name and "Tap to swap" (a raised row, a button only when there is something to swap).
	local squishyRow: TextButton = Create("TextButton", {
		Name = "Capsule_SwapButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = Theme.Colors.panelAlt,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = info,
	})
	Theme.corner(Theme.Radius.button, squishyRow)
	Theme.padding(Theme.Padding.small, squishyRow)
	Theme.list(Enum.FillDirection.Horizontal, ROW_GAP, squishyRow, Enum.HorizontalAlignment.Left)
	Focus.decorate(squishyRow, Theme.Radius.button)
	c:add(Button.decorate(squishyRow))
	local icon = StaticIcon.new({
		name = "Icon",
		squishyId = Catalog.starterId(),
		sizePx = C.iconPx,
		layoutOrder = 1,
		parent = squishyRow,
	})
	c:add(icon)
	local names: Frame = Create("Frame", {
		Name = "Texts",
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Size = UDim2.new(1, -(C.iconPx + ROW_GAP), 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = squishyRow,
	})
	Theme.list(Enum.FillDirection.Vertical, 2, names, Enum.HorizontalAlignment.Left)
	local name =
		Theme.label({ Name = "Name", LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Left, Parent = names }, "H2")
	local swapHint = Theme.label(
		{ Name = "SwapHint", LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Left, Parent = names },
		"Small",
		nil,
		Theme.Colors.ink2
	)
	c:add(squishyRow.Activated:Connect(function()
		showSwap(true)
	end))

	-- A locked slot: the lock and its word (never the lock alone, §17.7), light on the dark panel.
	local lockRow: Frame = Create("Frame", {
		Name = "Locked",
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = info,
	})
	Theme.list(Enum.FillDirection.Horizontal, ROW_GAP, lockRow)
	c:add(
		LockIcon.new({ name = "Lock", sizePx = LOCK_PX, color = Theme.Colors.text, layoutOrder = 1, parent = lockRow })
	)
	local lockText = Theme.label({
		Name = "Text",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = lockRow,
	}, "H2")

	local function line(labelName: string, order: number, kind: Theme.TextKind, color: Color3?): TextLabel
		return Theme.label({ Name = labelName, LayoutOrder = order, Parent = info }, kind, nil, color)
	end
	local tier = line("Tier", 3, "H2")
	local evolve = line("Evolve", 4, "Small", Theme.Colors.ink2)
	local speed = line("Speed", 5, "Body")
	local coins = line("CoinsPerHour", 6, "Body")
	local grip = line("GripPerHour", 7, "Body")
	local empty = line("Empty", 8, "Body", Theme.Colors.ink2)

	-- The swap view: its title and the owned squishies' buttons (fillSwap).
	local swapTitle = Theme.label({
		Name = "SwapTitle",
		Text = Strings.capsule.pick,
		LayoutOrder = 2,
		Visible = false,
		Parent = body,
	}, "H2")
	local swapList: Frame = Create("Frame", {
		Name = "SwapList",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Visible = false,
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, swapList, Enum.HorizontalAlignment.Center)

	-- The pinned footer: the one action, Back in the swap view, or the top-level / visitor line.
	local footer: Frame = Create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 2,
		Parent = content,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, footer, Enum.HorizontalAlignment.Center)
	local confirm = ConfirmButton.new({
		name = "Capsule_UpgradeButton",
		text = "",
		price = 0,
		balance = 0,
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = footer,
		onConfirm = buy,
	})
	c:add(confirm)
	local back = Button.new({
		name = "Capsule_BackButton",
		text = Strings.capsule.back,
		kind = "secondary",
		height = TOUCH.minTarget,
		layoutOrder = 2,
		parent = footer,
		onActivated = function()
			showSwap(false)
		end,
	})
	back.root.Visible = false
	c:add(back)
	local note = Theme.label({ Name = "Note", LayoutOrder = 3, Parent = footer }, "Body", Enum.FontWeight.Bold)

	refs = {
		root = panel,
		title = title,
		tab = tab,
		close = close,
		body = body,
		bodyList = bodyList,
		info = info,
		squishyRow = squishyRow,
		icon = icon,
		name = name,
		swapHint = swapHint,
		lockRow = lockRow,
		lockText = lockText,
		tier = tier,
		evolve = evolve,
		speed = speed,
		coins = coins,
		grip = grip,
		empty = empty,
		swapTitle = swapTitle,
		swapList = swapList,
		confirm = confirm,
		back = back,
		note = note,
	}
	c:add(bodyList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit))
	c:add(contentList:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fit))
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit))
	return panel
end

-- Pointer -----------------------------------------------------------------------------------------------------------

-- The plot and slot of the capsule a hit part belongs to (Capsule<slot> in a plot's Capsules folder), or nil.
local function capsuleAt(part: Instance): (number?, number?)
	local model = part.Parent
	local folder = if model then model.Parent else nil
	local plotModel = if folder then folder.Parent else nil
	if model == nil or folder == nil or plotModel == nil or folder.Name ~= FOLDER or not RAY_PARTS[part.Name] then
		return nil, nil
	end
	local plot = plotModel:GetAttribute(ATTR_PLOT_MODEL)
	local slot = tonumber(string.match(model.Name, "^Capsule(%d)$"))
	return if type(plot) == "number" then plot else nil, slot
end

-- ControlsController's pointer claim: a world press on a capsule waits to open its card (it is no squeeze).
local function claim(input: InputObject): boolean
	local camera = Workspace.CurrentCamera
	if camera == nil or StateController.isLobbyLocked() then
		return false
	end
	local ignore: { Instance } = {}
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(ignore, character)
	end
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	if fx then
		table.insert(ignore, fx)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * C.clickStuds, params)
	if hit == nil then
		return false
	end
	local plot, slot = capsuleAt(hit.Instance)
	if plot == nil or slot == nil then
		return false
	end
	pendingTap = { input = input, from = input.Position, at = os.clock(), plot = plot, slot = slot }
	return true
end

local function onInputEnded(input: InputObject)
	local tap = pendingTap
	local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
	if tap == nil or (not mouse and input ~= tap.input) then
		return
	end
	pendingTap = nil
	local moved = (input.Position - tap.from).Magnitude
	if moved <= TAP.tapMaxPixels and (os.clock() - tap.at) * 1000 <= TAP.tapMaxMs then
		open(tap.plot, tap.slot)
	end
end

-- An accepted own squeeze in the own plot: every own capsule with a squishy gets the small squish.
local function onSqueezeResult(result: SqueezeController.Result)
	local player = Players.LocalPlayer
	local plot = player:GetAttribute(ATTR_PLOT)
	local root = if player.Character then player.Character:FindFirstChild("HumanoidRootPart") else nil
	if not result.ok or type(plot) ~= "number" or root == nil or not root:IsA("BasePart") then
		return
	end
	if not WorldLayout.inPlot(plot, root.Position) then
		return
	end
	local folder = folderOf(plot)
	for slot = 1, SLOTS do
		local capsule = modelIn(folder, "Capsule" .. slot)
		local squishy = modelIn(folder, "Squishy" .. slot)
		if capsule and squishy then
			play("tap", capsule, squishy)
		end
	end
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function CapsuleController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function(params: any?)
			local own = Players.LocalPlayer:GetAttribute(ATTR_PLOT)
			local plot = if type(params) == "table" then params.plot else own
			local slot = if type(params) == "table" then params.slot else 1
			if type(plot) ~= "number" or type(slot) ~= "number" then
				UIController.close(SCREEN, "gone")
				return
			end
			shown = { plot = plot, slot = slot }
			swapping = false
			refreshCard()
		end,
		onClose = function()
			shown, swapping = nil, false
			local r = refs
			if r and not pending then
				r.confirm:reset() -- an armed confirm never survives a close
			end
		end,
		primary = function(): GuiObject?
			local r = refs
			if r == nil then
				return nil
			elseif r.confirm.root.Visible then
				return r.confirm.button.root
			end
			return r.close.root
		end,
	}))
	for _, field in { "capsules", "coins", "grip", "dataStatus", "owned" } do
		c:add(StateController.changed(field):connect(refreshCard))
	end
	c:add(UIController.LayoutChanged:connect(fit))
	c:add(function()
		for capsule, motion in motions do
			rest(capsule, motion)
		end
		table.clear(motions)
		local pool = FxPool.default()
		for _, brick in bricks do
			pool:release(brick.part)
		end
		table.clear(bricks)
		for _, pop in pops do
			pop.gui:Destroy()
		end
		table.clear(pops)
		local handle = effect
		if handle then
			handle:disconnect()
		end
		for plot in plotCleanups do
			local fc = plotCleanups[plot]
			fc:clean()
		end
		for player in playerCleanups do
			local pc = playerCleanups[player]
			pc:clean()
		end
		local rows = swapRows
		if rows then
			rows:clean()
		end
		table.clear(plotCleanups)
		table.clear(playerCleanups)
		table.clear(plots)
		table.clear(levels)
		effect, refs, swapRows, swapSignature, firstSwap, shown, pendingTap = nil, nil, nil, nil, nil, nil, nil
		swapping, pending = false, false
	end)
end

function CapsuleController.start()
	local c = cleanup
	if c == nil then
		return
	end
	for _, model in CollectionService:GetTagged(TAG_BASE) do
		watchPlot(c, model)
	end
	c:add(CollectionService:GetInstanceAddedSignal(TAG_BASE):Connect(function(model: Instance)
		watchPlot(c, model)
	end))
	c:add(CollectionService:GetInstanceRemovedSignal(TAG_BASE):Connect(function(model: Instance)
		local plot = model:GetAttribute(ATTR_PLOT_MODEL)
		if type(plot) == "number" and plots[plot] == model then
			plots[plot], levels[plot] = nil, nil
			local fc = plotCleanups[plot]
			if fc then
				fc:clean()
				plotCleanups[plot] = nil
			end
		end
	end))
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	c:add(Players.PlayerAdded:Connect(watchPlayer))
	c:add(Players.PlayerRemoving:Connect(function(player: Player)
		local pc = playerCleanups[player]
		if pc then
			pc:clean()
			playerCleanups[player] = nil
		end
		local s = shown
		if s and player:GetAttribute(ATTR_PLOT) == s.plot then
			UIController.close(SCREEN, "gone") -- the owner left: their base is open again
		end
	end))
	c:add(SqueezeController.ResultReceived:connect(onSqueezeResult))
	ControlsController.setPointerClaim(claim)
	c:add(function()
		ControlsController.setPointerClaim(nil)
	end)
	c:add(UserInputService.InputEnded:Connect(onInputEnded))
end

function CapsuleController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return CapsuleController
