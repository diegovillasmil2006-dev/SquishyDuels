--!strict
-- PracticeController (client only). DESIGN §5.11, §7.6, §9.8 (practice target row), §11.6 (practice panel), §5.10.
-- The practice range client. The server (PracticeService / CombatService) decides every hit; this module only
-- presents.
--
-- * Zone: every ZONE_CHECK_SECONDS the local HumanoidRootPart is tested against the throw box
--   (PracticeTargets.inThrowBox, the same box as SD_PracticeZone and the server check). Inside, alive and not in a
--   match (SD_MatchId and SD_DuelPhase empty) -> ControlsController Practice context on (Throw / Ultimate keys and
--   the touch buttons; ThrowController throws); otherwise off. A found match ends the session (§5.11).
-- * Targets (tag SD_PracticeTarget, streamed in and out): each target's definition comes from
--   PracticeTargets.get(TargetId) (the server's data), else its attributes. The moving target slides on
--   PracticeTargets.positionAt(def, workspace:GetServerTimeNow()) - the server's hit position - with no replication.
--   Parts are placed from their streamed-in frames relative to the model pivot (BulkMoveTo), never incrementally; the
--   pivot faces the thrower (against the range's throwDirection), so "down" tips it back about its pivot's X axis.
-- * Hit reaction (ThrowImpact kind "target", every nearby client): the target's Body squashes and wobbles (from its
--   SpecialMesh's stored base values) and the target tips back "down" for Config.Combat.Practice.targetDownSeconds,
--   then springs back up (downAngle / squashAt, pure). The hit target is impact.targetId, else the target nearest the
--   impact (nearestTarget, pure).
-- * Reticle (practice only; the duel reticle is DuelController's, both read ThrowController.getAimState()):
--   ScreenGui SD_PracticeReticle (reading: full-bleed, DisplayOrder 13, above SD_DuelHud 11 and the touch buttons 12)
--   with a dot and a ring at the aim's screen position (the mouse on PC, the centre on touch, gamepad and shift lock).
--   Its state is an icon plus text, never colour alone (reticleView, pure): ready = dot + "Ready"; cooling down = the
--   ring fills bottom-up as the cooldown runs out (a UIGradient edge, no images) + the remaining seconds; blocked = a
--   cross + the reason ("Rooted", "Can't throw here", the throw.direction reason). Hidden while a modal blocks input.
-- * Thrower feedback (§9.8): an own hit (ThrowController.HitConfirmed, kind "target") pops the reticle ring 1.3 -> 1
--   over 250 ms (no scale under ReducedMotion), shows "Hit!" at the reticle for 400 ms, and "Hit!" plus the target's
--   distance ("{distance} studs", practice.distanceLabel) above the target while it is down.
--   Feel pass (§18.4.2, §18.6): the reticle's "Hit!" pops 1.3 -> 1 (Back Out, 200 ms) and tilts ±6° -> 0, the other
--   way on each hit (hitTextPop, pure: UI/DuelFormat's, shared with the duel reticle; none under ReducedMotion), and
--   ui.hitConfirm plays on the contact frame (2D, the thrower only).
-- * Panel (SD_Hud, §11.6): throws, hits, accuracy of the session. Server-counted: StateDelta.practice
--   (StateController "practice") when the server sends it; until then (reading: Part 4 has no StateService) the same
--   numbers from server-confirmed events - own accepted practice throws (ThrowStarted) and own confirmed target hits.
--   Reset on leaving the zone. Practice never pays Coins (the range sign says so).
-- Part 8 (layout pass, §11.2):
-- * The panel's place is panelPlacement (pure, unit-tested at 667×375, 1280×720, 1920×1080 and the largest text):
--   first under the HUD's top-left column (Hud_Left), else at the right edge under the top-right row, its data line
--   and the queue pill (practising while queued is allowed, §5.11), never over, on touch, the thumbstick zone and the
--   Throw / Ultimate buttons (ControlsController.touchLayout). Before, it sat at 42% of the height on the left, under
--   the Coins pill and the Grip card on a phone. Re-placed on every zone check while shown.
--   On compact screens the panel dropped its title (the range's sign names it); foam fix 2 shows it again (below).
-- * The reticle gets the UI scale like the duel reticle (UIController.trackScale), so its texts follow the screen.
-- Foam UI restyle (spec 2026-10-09; the panel only, placement and numbers unchanged): the panel is a foam card whose
-- title is a Sky blue chip (the range's trim colour) over its InkUI rows. The reticle keeps the duel
-- reticle's look (DuelController draws the same one), so the two stay alike.
-- Integration (2026-10-09, the foam HUD moved things): the left spot goes under the whole left side, Hud_Left plus the
-- tile group Hud_Nav under it (unionRect); the right spot also goes under the coach card (Hud_OnboardingCard); the
-- panel never covers the Duel CTA (UI FINAL R4: the whole DUEL area Hud_CtaWrap, the button, the search bar and the
-- testers' mode picker; at the top middle since spec 2026-10-11, one of the frames above it). The reticle follows the
-- duel reticle's foam look: InkUI outlines with round joins, the state text in the Chip
-- display kind.
-- Overlays fix (2026-10-09): the reticle's state text moves in from a screen edge so it is never cut off
-- (DuelFormat.reticleLabelOffset, shared with the duel reticle).
-- Foam fix 2 (2026-10-09; look and layout only):
-- * The panel keeps its Sky title chip on every layout (§11.10; Part 8 dropped it on compact screens), its rows
--   left-aligned under it. On narrow layouts (compact or touch) it keeps clear of the thumbstick zone measured on the
--   whole screen (HudFormat.thumbstickZone; a share of SD_Hud alone, which leaves out the top bar inset, put it about
--   40 px into the zone on a phone) and of the touch Throw / Ultimate / jump buttons; a third spot on the top row, left
--   of the top-right items, takes it when the left and right ones are not free (phones). Toasts keep beside it
--   (UIController.toastsBeside "practice"). Reading: at the larger text sizes on phones no spot may be free (the HUD
--   fills the screen) and the panel keeps the Part 8 fallback (fits = false). Lobby HUD (spec 2026-10-11): with the Duel
--   CTA at the top middle, the right edge under the Settings tile is free on phones at the standard size (667×375 too).
-- * The reticle hides while its point is on a HUD button or an open dialog (DuelFormat.aimBlocked, as the duel
--   reticle), and its small state text has the thin InkUI outline (the 2 px one closed the gaps between words).
-- Feature 1 (2026-10-11, the charge throw; design: the combat-effects page "Squishy Combat FP v2.html", html:670-671):
-- while charging (ThrowController's AimState) the reticle's fill grows from its top to c in the held toy's colour at
-- Config.UI.Reticle.chargeFillTransparency and the ring pulses at full (DuelFormat.chargeLook, as the duel reticle;
-- none under ReducedMotion). The catch is duel-only: the range has no catch prompt.

-- Services

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local Chip = require(Client.UI.Components.Chip)
local DuelFormat = require(Client.UI.DuelFormat)
local HudFormat = require(Client.UI.HudFormat)
local Theme = require(Client.UI.Theme)
local ControlsController = require(script.Parent.ControlsController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local UIController = require(script.Parent.UIController)

-- Types

type BodyMesh = { mesh: SpecialMesh, scale: Vector3, offset: Vector3, height: number }

type TargetState = {
	model: Model,
	def: PracticeTargets.TargetDef,
	basePivot: CFrame,
	parts: { BasePart },
	rel: { CFrame },
	index: { [BasePart]: number },
	body: BodyMesh?,
	hitClock: number?, -- os.clock() of the last hit
	moving: boolean,
	resting: boolean, -- the last write was the rest pose
	connections: { RBXScriptConnection },
}

export type Tally = { throws: number, hits: number }

-- What the reticle shows this frame (reticleView, pure).
export type ReticleIcon = "dot" | "fill" | "cross"
export type ReticleView = {
	visible: boolean,
	icon: ReticleIcon,
	textKey: string?, -- a Strings key (common.secondsShort takes { seconds }), nil = no text
	reasonCode: string?, -- shown through Strings.reasonText instead of textKey
	seconds: number?, -- cooling down: remaining seconds
	fill: number, -- 0 (just thrown) .. 1 (ready)
}

-- A rectangle in SD_Hud's base px (Part 8 panel placement).
export type Rect = { x: number, y: number, w: number, h: number }

export type PanelInput = {
	screen: Vector2, -- SD_Hud's canvas in base px
	size: Vector2, -- the panel's size
	left: Rect?, -- Hud_Left: the first spot is under it
	above: { Rect }, -- the right-hand spot goes under those of these it shares columns with (row, data line, pill)
	avoid: { Rect }, -- what the panel never covers (equipped card; on touch the thumbstick zone and buttons)
}

export type PanelPlacement = {
	x: number, -- the panel's top-left
	y: number,
	slot: "left" | "right" | "top",
	fits: boolean, -- false: no spot was free (the left one, kept on screen)
}

type Reticle = {
	gui: ScreenGui,
	root: Frame,
	ringScale: UIScale,
	fillGradient: UIGradient,
	dot: Frame,
	cross: Frame,
	label: TextLabel,
	labelWidth: number, -- the state text's width (base px) as last measured
	hit: TextLabel,
	hitScale: UIScale,
	hitStart: number, -- os.clock()
	hitUntil: number, -- os.clock()
	lastFill: number,
}

-- Constants

local RANGE = WorldLayout.PracticeRange
local ATTRIBUTES = WorldLayout.Attributes
local DOWN_SECONDS = Config.Combat.Practice.targetDownSeconds
local ZONE_CHECK_SECONDS = 0.15 -- reading (not in DESIGN, provisional)
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
-- reading (not in DESIGN, provisional): the "down" look: tip back DOWN_DEG in FALL_SECONDS, stay down until
-- targetDownSeconds, then spring back up (ω RISE_OMEGA, ζ RISE_ZETA) for RISE_SECONDS.
local DOWN_DEG = 70
local FALL_SECONDS = 0.15
local RISE_OMEGA = 12
local RISE_ZETA = 0.45
local RISE_SECONDS = 0.9
-- reading: the Body squash at the hit (c = 1 - SQUASH_AMOUNT, volume-preserving w), wobbling back (ω, ζ).
local SQUASH_AMOUNT = 0.3
local SQUASH_OMEGA = 18
local SQUASH_ZETA = 0.35
local SQUASH_SECONDS = 0.9
-- reading: moving / reacting targets animate only within this distance of the camera.
local ANIMATE_STUDS = 160
local BODY_NAME = "Body"
local NEAREST_STUDS = 6 -- reading: an impact without targetId matches a target within this (horizontal) distance
local LABEL_LIFT = 8 -- studs above the target floor point for the "Hit!" billboard
local HUD_GUI = "SD_Hud"
local HIT = Config.Vfx.Hit
-- Reticle (reading: sizes in px and the DisplayOrder are not in DESIGN).
local RETICLE_GUI = "SD_PracticeReticle"
local RETICLE_DISPLAY_ORDER = 13
local RETICLE_SIZE = 36
local RETICLE_DOT = 6
local RETICLE_CROSS = 18
local RETICLE_FILL_TRANSPARENCY = 0.55
local RETICLE_CHARGE = Config.UI.Reticle -- feature 1: the charge fill
local RETICLE_TEXT_WIDTH = 220
local RETICLE_TEXT_GAP = 6 -- the state text under the ring
local RETICLE_TEXT_EDGE = 12 -- overlays fix: the state text keeps this far (base px) inside the screen's edges
local SOUND_HIT_CONFIRM = "ui.hitConfirm" -- §18.6: the thrower's own hit cue
-- Part 8 panel placement (readings: §11.6 says "in the practice zone", not where). Base px under SD_Hud's UIScale.
local PANEL_NAME = "Practice_Panel"
local PANEL_WIDTH = 190
local PANEL_EDGE = 16 -- as built (x 16)
local PANEL_GAP = 8 -- HudController's row gap
-- SD_Hud frames of other modules the panel keeps clear of (stable names: HudController's, QueueController's pill,
-- OnboardingController's coach card). Lobby HUD (spec 2026-10-11): the Duel CTA sits at the top middle, so the right
-- spot goes under it where they share columns and the top spot slides left past it.
local HUD_FRAMES_ABOVE = { "Hud_Nav", "Hud_Right", "QueuePill", "Hud_OnboardingCard", "Hud_CtaWrap" }
-- Integration (foam HUD): the left side is the column (Hud_Left) and the tiles under it (Hud_Nav); the first spot goes
-- under both (unionRect).
local HUD_LEFT_FRAMES = { "Hud_Left", "Hud_Nav" }
-- Never covered: other HUD frames that are not above it (none since the lobby HUD of spec 2026-10-11 removed the
-- equipped dock and moved the Duel CTA to the top; the touch areas are added on narrow layouts).
local HUD_AVOID_FRAMES: { string } = {}

-- Module table

local PracticeController = {}

-- Fired with (inside) when the local player enters or leaves the practice zone.
PracticeController.ZoneChanged = Signal.new() :: Signal.Signal<boolean>

-- Private

local log = Log.new("Practice")
local cleanup: Cleanup.Cleanup? = nil
local targets: { [Model]: TargetState } = {}
local inZone = false
local zoneTimer = 0
local tally: Tally = { throws = 0, hits = 0 }
local panel: Frame? = nil
local panelRows: { [string]: TextLabel } = {}
local hitBoards: { [BillboardGui]: thread } = {}
local reticle: Reticle? = nil
local hitTiltSign = 1 -- "Hit!" tilts the other way on each hit (§18.4.2)
local connections: { Signal.Connection } = {}
local stats = { reactions = 0, ownHits = 0, entered = 0 }

-- Pure helpers ------------------------------------------------------------------------------------------------------

-- Tilt of a hit target `elapsed` seconds after the hit (degrees, + = tipped back): falls to DOWN_DEG, stays down for
-- downSeconds, then springs back up (damped cosine). Returns the angle and whether the reaction is over.
function PracticeController.downAngle(elapsed: number, downSeconds: number?): (number, boolean)
	local down = downSeconds or DOWN_SECONDS
	if elapsed < 0 then
		return 0, false
	end
	if elapsed < FALL_SECONDS then
		local u = TweenService:GetValue(elapsed / FALL_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		return DOWN_DEG * u, false
	end
	if elapsed < down then
		return DOWN_DEG, false
	end
	local t = elapsed - down
	if t >= RISE_SECONDS then
		return 0, true
	end
	local damped = RISE_OMEGA * math.sqrt(1 - RISE_ZETA * RISE_ZETA)
	return DOWN_DEG * math.exp(-RISE_ZETA * RISE_OMEGA * t) * math.cos(damped * t), false
end

-- Body squash (scale on the vertical axis) `elapsed` seconds after the hit: 1 - SQUASH_AMOUNT at the hit, wobbling
-- back to 1. Returns c and whether it is over.
function PracticeController.squashAt(elapsed: number): (number, boolean)
	if elapsed < 0 then
		return 1, false
	end
	if elapsed >= SQUASH_SECONDS then
		return 1, true
	end
	local damped = SQUASH_OMEGA * math.sqrt(1 - SQUASH_ZETA * SQUASH_ZETA)
	return 1 - SQUASH_AMOUNT * math.exp(-SQUASH_ZETA * SQUASH_OMEGA * elapsed) * math.cos(damped * elapsed), false
end

-- Accuracy in whole percent (0 with no throws).
function PracticeController.accuracyPercent(hits: number, throws: number): number
	if not (throws > 0) then
		return 0
	end
	return math.floor(math.clamp(hits / throws, 0, 1) * 100 + 0.5)
end

-- The target whose floor point at `serverTime` is nearest `position` horizontally, within maxStuds.
function PracticeController.nearestTarget(
	defs: { PracticeTargets.TargetDef },
	position: Vector3,
	serverTime: number,
	maxStuds: number?
): PracticeTargets.TargetDef?
	local best: PracticeTargets.TargetDef? = nil
	local bestDistance = maxStuds or NEAREST_STUDS
	for _, def in defs do
		local at = PracticeTargets.positionAt(def, serverTime)
		local distance = Vector3.new(at.X - position.X, 0, at.Z - position.Z).Magnitude
		if distance <= bestDistance then
			best, bestDistance = def, distance
		end
	end
	return best
end

-- What the practice reticle shows (§5.10, §11.6). `aim` is ThrowController.getAimState(); `active` = the Practice
-- context is on and no modal blocks input.
function PracticeController.reticleView(aim: ThrowController.AimState, active: boolean, now: number): ReticleView
	if not active or aim.state == "hidden" then
		return { visible = false, icon = "dot", fill = 1 }
	end
	if aim.state == "blocked" then
		if aim.reason == "throw.rooted" then
			return { visible = true, icon = "cross", textKey = "duel.reticle.rooted", fill = 1 }
		elseif aim.reason == "throw.direction" then
			return { visible = true, icon = "cross", reasonCode = "throw.direction", fill = 1 }
		end
		return { visible = true, icon = "cross", textKey = "duel.reticle.wrongZone", fill = 1 }
	elseif aim.state == "cooling" then
		return {
			visible = true,
			icon = "fill",
			textKey = "common.secondsShort",
			seconds = math.max(aim.readyAt - now, 0),
			fill = math.clamp(if aim.progress == aim.progress then aim.progress else 1, 0, 1),
		}
	end
	return { visible = true, icon = "dot", textKey = "duel.reticle.ready", fill = 1 }
end

-- Hit-marker ring scale `elapsed` seconds after an own hit: hitMarkerScaleFrom -> 1 over hitMarkerMs (1 when reduced).
function PracticeController.hitMarkerScale(elapsed: number, reducedMotion: boolean): number
	local duration = HIT.hitMarkerMs / 1000
	if reducedMotion or not (elapsed >= 0) or elapsed >= duration then
		return 1
	end
	return HIT.hitMarkerScaleFrom + (1 - HIT.hitMarkerScaleFrom) * (elapsed / duration)
end

-- The reticle's "Hit!" `elapsed` seconds after an own hit (§18.4.2): (scale, rotationDeg). It pops
-- Vfx.Hit.hitTextPopFrom -> 1 over hitTextPopMs (Back Out) and tilts sign × hitTextTiltDeg -> 0; (1, 0) under
-- ReducedMotion. The same spec as the duel reticle's (DuelFormat.hitTextPop).
function PracticeController.hitTextPop(elapsed: number, sign: number, reducedMotion: boolean): (number, number)
	local scale, rotation = DuelFormat.hitTextPop(elapsed, sign, reducedMotion)
	return scale, rotation
end

-- The frame of a target's pivot: the rest pivot slid along Z by the moving target's offset, tipped back `angleDeg`
-- about the pivot's own X axis (the pivot faces the thrower).
function PracticeController.pivotAt(basePivot: CFrame, offsetZ: number, angleDeg: number): CFrame
	return (basePivot + Vector3.new(0, 0, offsetZ)) * CFrame.Angles(math.rad(angleDeg), 0, 0)
end

local function usable(rect: Rect?): boolean
	return rect ~= nil and rect.w > 0 and rect.h > 0 and rect.x == rect.x and rect.y == rect.y
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Where the practice panel goes (Part 8, base px, top-left corner). Three spots, the first free one wins:
--   "left":  PANEL_EDGE from the left, PANEL_GAP under Hud_Left (or PANEL_EDGE from the top without it);
--   "right": PANEL_EDGE from the right, PANEL_GAP under every `above` rect that shares its columns;
--   "top":   (foam fix 2) PANEL_EDGE from the top, PANEL_GAP left of every `above` rect that shares its rows (a phone,
--            where the titled panel fits neither under the left side nor between the Settings tile and the Duel CTA).
-- A spot is free when it stays PANEL_EDGE inside the screen and covers none of `left`, `above` and `avoid`. With no
-- free spot the left one is kept on screen and fits = false.
function PracticeController.panelPlacement(input: PanelInput): PanelPlacement
	local screen, size = input.screen, input.size
	local blockers: { Rect } = {}
	local left = input.left
	if left and usable(left) then
		table.insert(blockers, left)
	end
	for _, list in { input.above, input.avoid } do
		for _, rect in list do
			if usable(rect) then
				table.insert(blockers, rect)
			end
		end
	end
	local function free(x: number, y: number): boolean
		if x < PANEL_EDGE - 1e-6 or y < PANEL_EDGE - 1e-6 then
			return false
		end
		if x + size.X > screen.X - PANEL_EDGE + 1e-6 or y + size.Y > screen.Y - PANEL_EDGE + 1e-6 then
			return false
		end
		local spot: Rect = { x = x, y = y, w = size.X, h = size.Y }
		for _, rect in blockers do
			if overlaps(spot, rect) then
				return false
			end
		end
		return true
	end

	local leftY = PANEL_EDGE
	if left and usable(left) then
		leftY = math.max(leftY, left.y + left.h + PANEL_GAP)
	end
	if free(PANEL_EDGE, leftY) then
		return { x = PANEL_EDGE, y = leftY, slot = "left", fits = true }
	end

	local rightX = screen.X - PANEL_EDGE - size.X
	local rightY = PANEL_EDGE
	for _, rect in input.above do
		if usable(rect) and rect.x < rightX + size.X and rightX < rect.x + rect.w then
			rightY = math.max(rightY, rect.y + rect.h + PANEL_GAP)
		end
	end
	if free(rightX, rightY) then
		return { x = rightX, y = rightY, slot = "right", fits = true }
	end

	-- Moved left past each `above` rect it meets on the top row, until it meets none (at most once per rect).
	local topX = screen.X - PANEL_EDGE - size.X
	for _ = 1, #input.above do
		local moved = false
		for _, rect in input.above do
			local spot: Rect = { x = topX, y = PANEL_EDGE, w = size.X, h = size.Y }
			if usable(rect) and overlaps(spot, rect) then
				topX = rect.x - PANEL_GAP - size.X
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	if free(topX, PANEL_EDGE) then
		return { x = topX, y = PANEL_EDGE, slot = "top", fits = true }
	end

	local y = math.max(PANEL_EDGE, math.min(leftY, screen.Y - PANEL_EDGE - size.Y))
	return { x = PANEL_EDGE, y = y, slot = "left", fits = false }
end

-- The smallest rect around every usable rect of `rects` (nil when none is usable). Integration (foam HUD): the left
-- side panelPlacement goes under is Hud_Left plus the tiles (Hud_Nav) under it.
function PracticeController.unionRect(rects: { Rect }): Rect?
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, rect in rects do
		if usable(rect) then
			x0, y0 = math.min(x0, rect.x), math.min(y0, rect.y)
			x1, y1 = math.max(x1, rect.x + rect.w), math.max(y1, rect.y + rect.h)
		end
	end
	if x0 > x1 then
		return nil
	end
	return { x = x0, y = y0, w = x1 - x0, h = y1 - y0 }
end

-- Runtime helpers ---------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	return if template then Strings.format(template, args) else ""
end

local function track(connection: Signal.Connection)
	table.insert(connections, connection)
	local c = cleanup
	if c then
		c:add(connection)
	end
end

local function inMatch(): boolean
	local player = Players.LocalPlayer
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	local phase = player:GetAttribute(ATTR_DUEL_PHASE)
	return (type(matchId) == "string" and matchId ~= "") or (type(phase) == "string" and phase ~= "")
end

local function localRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function cameraPosition(): Vector3
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else Vector3.zero
end

-- Targets -----------------------------------------------------------------------------------------------------------

local function addPart(state: TargetState, part: BasePart)
	if state.index[part] ~= nil then
		return
	end
	table.insert(state.parts, part)
	-- Streamed-in parts arrive at their server frame; the server never moves a target.
	table.insert(state.rel, state.basePivot:ToObjectSpace(part.CFrame))
	state.index[part] = #state.parts
	if part.Name == BODY_NAME and state.body == nil then
		local mesh = part:FindFirstChildWhichIsA("SpecialMesh")
		if mesh then
			state.body = { mesh = mesh, scale = mesh.Scale, offset = mesh.Offset, height = part.Size.Y }
		end
	end
	state.resting = false
end

local function removePart(state: TargetState, part: BasePart)
	local index = state.index[part]
	if index == nil then
		return
	end
	table.remove(state.parts, index)
	table.remove(state.rel, index)
	table.clear(state.index)
	for i, p in state.parts do
		state.index[p] = i
	end
	local body = state.body
	if body and body.mesh.Parent == part then
		state.body = nil
	end
end

local function defFor(model: Model, basePivot: CFrame): PracticeTargets.TargetDef?
	local id = model:GetAttribute(ATTRIBUTES.TargetId)
	if type(id) == "string" then
		local def = PracticeTargets.get(id)
		if def then
			return def
		end
	end
	return PracticeTargets.fromAttributes(model:GetAttributes(), basePivot.Position)
end

local function bindTarget(instance: Instance)
	if not instance:IsA("Model") or targets[instance] ~= nil then
		return
	end
	local model = instance :: Model
	local basePivot = model:GetPivot()
	local def = defFor(model, basePivot)
	if def == nil then
		log:warn(`practice target {model:GetFullName()} has no valid TargetId`)
		return
	end
	local state: TargetState = {
		model = model,
		def = def,
		basePivot = basePivot,
		parts = {},
		rel = {},
		index = {},
		body = nil,
		hitClock = nil,
		moving = def.moving and def.railLength > 0 and def.period > 0,
		resting = true,
		connections = {},
	}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			addPart(state, descendant)
		end
	end
	table.insert(
		state.connections,
		model.DescendantAdded:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				addPart(state, descendant)
			end
		end)
	)
	table.insert(
		state.connections,
		model.DescendantRemoving:Connect(function(descendant: Instance)
			if descendant:IsA("BasePart") then
				removePart(state, descendant)
			end
		end)
	)
	targets[model] = state
end

local function unbindTarget(instance: Instance)
	local state = if instance:IsA("Model") then targets[instance :: Model] else nil
	if state == nil then
		return
	end
	targets[state.model] = nil
	for _, connection in state.connections do
		connection:Disconnect()
	end
	table.clear(state.connections)
end

local function targetById(id: string): TargetState?
	for _, state in targets do
		if state.def.id == id then
			return state
		end
	end
	return nil
end

-- The target a ThrowImpact names (targetId), else the one nearest its position.
local function targetOf(impact: Types.ThrowImpactPayload): TargetState?
	local id = impact.targetId
	if type(id) == "string" then
		local named = targetById(id)
		if named then
			return named
		end
	end
	local list: { PracticeTargets.TargetDef } = {}
	for _, candidate in targets do
		table.insert(list, candidate.def)
	end
	local def = PracticeController.nearestTarget(list, impact.position, serverNow())
	return if def then targetById(def.id) else nil
end

local function writeTarget(state: TargetState, now: number, clock: number): boolean
	local offset = PracticeTargets.positionAt(state.def, now) - state.def.position
	local angle, squash = 0, 1
	local reacting = false
	local hitClock = state.hitClock
	if hitClock ~= nil then
		local elapsed = clock - hitClock
		local a, downDone = PracticeController.downAngle(elapsed)
		local c, squashDone = PracticeController.squashAt(elapsed)
		angle, squash = a, c
		reacting = not (downDone and squashDone)
		if not reacting then
			state.hitClock = nil
		end
	end
	local pivot = PracticeController.pivotAt(state.basePivot, offset.Z, angle)
	local frames = table.create(#state.parts)
	for i, rel in state.rel do
		frames[i] = pivot * rel
	end
	if #state.parts > 0 then
		Workspace:BulkMoveTo(state.parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	local body = state.body
	if body and body.mesh.Parent ~= nil then
		local w = 1 / math.sqrt(math.max(squash, 0.05))
		body.mesh.Scale = Vector3.new(body.scale.X * w, body.scale.Y * squash, body.scale.Z * w)
		body.mesh.Offset = body.offset + Vector3.new(0, -(1 - squash) * body.height / 2, 0)
	end
	return reacting
end

local function stepTargets(now: number, clock: number)
	local camera = cameraPosition()
	for _, state in targets do
		local active = state.moving or state.hitClock ~= nil
		if not active then
			if not state.resting then
				writeTarget(state, now, clock)
				state.resting = true
			end
			continue
		end
		if (state.basePivot.Position - camera).Magnitude > ANIMATE_STUDS then
			continue
		end
		writeTarget(state, now, clock)
		state.resting = false
	end
end

-- UI ------------------------------------------------------------------------------------------------------------------

local function ensurePanel(): Frame?
	local current = panel
	if current and current.Parent ~= nil then
		return current
	end
	local ok, result = pcall(UIController.screenGui, HUD_GUI)
	if not ok or typeof(result) ~= "Instance" then
		return nil
	end
	local hud = result :: Instance
	-- Placed by layoutPanel (panelPlacement) while it shows.
	local frame = Theme.panel({
		Name = PANEL_NAME,
		Position = UDim2.fromOffset(PANEL_EDGE, PANEL_EDGE),
		Size = UDim2.fromOffset(PANEL_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
	})
	Theme.list(Enum.FillDirection.Vertical, 4, frame, Enum.HorizontalAlignment.Left)
	-- Foam UI: the title as a Sky blue chip (the range's trims are Sky; Chip kind, InkUI by the outlined-text rule).
	Chip.new({ name = "Title", text = text("practice.panelTitle"), accent = "sky", parent = frame })
	panelRows = {}
	for order, key in { "throws", "hits", "accuracy" } do
		-- Foam fix 2: left-aligned under the chip (centred rows under a left chip looked lopsided).
		panelRows[key] = Theme.label({
			Name = "Row_" .. key,
			LayoutOrder = order + 1,
			Text = "",
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		}, "Body")
	end
	frame.Parent = hud
	panel = frame
	-- Foam fix 2: on a phone it may take the top row, where toasts arrive; they keep beside it.
	UIController.toastsBeside("practice", frame)
	return frame
end

-- `object`'s rect in `gui`'s base px, when it is a visible GuiObject with a size.
local function hudRect(gui: ScreenGui, object: Instance?, scale: number): Rect?
	if object == nil or not object:IsA("GuiObject") or not object.Visible then
		return nil
	end
	local size = object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local position = object.AbsolutePosition - gui.AbsolutePosition
	return { x = position.X / scale, y = position.Y / scale, w = size.X / scale, h = size.Y / scale }
end

-- Places the shown panel (panelPlacement) from the HUD frames read now.
local function layoutPanel()
	local frame = panel
	if frame == nil or not frame.Visible then
		return
	end
	local gui = frame:FindFirstAncestorOfClass("ScreenGui")
	local scale = UIController.scale()
	if gui == nil or not (scale > 0) then
		return
	end
	local absolute = gui.AbsoluteSize
	if absolute.X <= 0 or absolute.Y <= 0 then
		return
	end
	local screen = absolute / scale
	local above: { Rect } = {}
	for _, name in HUD_FRAMES_ABOVE do
		local rect = hudRect(gui, gui:FindFirstChild(name), scale)
		if rect then
			table.insert(above, rect)
		end
	end
	local avoid: { Rect } = {}
	for _, name in HUD_AVOID_FRAMES do
		local rect = hudRect(gui, gui:FindFirstChild(name), scale)
		if rect then
			table.insert(avoid, rect)
		end
	end
	if UIController.layoutClass() == "compact" or ControlsController.preferredInput() == Enum.PreferredInput.Touch then
		-- §11.2 phone zones on narrow layouts (compact or touch, as HudController): the thumbstick (lower-left 40% ×
		-- 45% of the whole screen, foam fix 2: HudFormat.thumbstickZone with the camera's height, since SD_Hud leaves
		-- out the top bar inset) and the touch Throw / Ultimate / jump buttons (reading: their default spot next to
		-- Roblox's jump button; ControlsController reads the real jump button itself).
		local camera = Workspace.CurrentCamera
		table.insert(avoid, HudFormat.thumbstickZone(screen, if camera then camera.ViewportSize.Y else nil, scale))
		local touch = ControlsController.touchLayout(absolute, scale, nil)
		for _, rect in { touch.throw, touch.ultimate, touch.jump } do
			table.insert(avoid, { x = rect.x / scale, y = rect.y / scale, w = rect.w / scale, h = rect.h / scale })
		end
	end
	local leftParts: { Rect } = {}
	for _, name in HUD_LEFT_FRAMES do
		local rect = hudRect(gui, gui:FindFirstChild(name), scale)
		if rect then
			table.insert(leftParts, rect)
		end
	end
	local place = PracticeController.panelPlacement({
		screen = screen,
		size = frame.AbsoluteSize / scale,
		left = PracticeController.unionRect(leftParts),
		above = above,
		avoid = avoid,
	})
	local position = UDim2.fromOffset(math.floor(place.x + 0.5), math.floor(place.y + 0.5))
	if frame.Position ~= position then
		frame.Position = position
	end
end

local function currentStats(): (number, number)
	local fromServer = StateController.get("practice")
	if type(fromServer) == "table" and type(fromServer.throws) == "number" and type(fromServer.hits) == "number" then
		return fromServer.throws, fromServer.hits
	end
	return tally.throws, tally.hits
end

local function refreshPanel()
	local frame = ensurePanel()
	if frame == nil then
		return
	end
	frame.Visible = inZone
	if not inZone then
		return
	end
	local throws, hits = currentStats()
	local percent = text("common.percent", { value = PracticeController.accuracyPercent(hits, throws) })
	local rows: { [string]: string } = {
		throws = `{text("stats.throws")}: {throws}`,
		hits = `{text("stats.hits")}: {hits}`,
		accuracy = `{text("stats.accuracy")}: {percent}`,
	}
	for key, label in panelRows do
		label.Text = rows[key] or ""
	end
	layoutPanel()
end

-- Reticle -----------------------------------------------------------------------------------------------------------

local function outlinedLabel(
	name: string,
	kind: Theme.TextKind,
	color: Color3,
	strokePx: number,
	props: { [string]: any }
): TextLabel
	local label = Theme.label(props, kind, nil, color)
	label.Name = name
	label.TextXAlignment = Enum.TextXAlignment.Center
	-- The foam kit's outlined text, as on the duel reticle (InkUI, round joins); UI FINAL R1: its only outline.
	Theme.noOutline(label)
	local stroke = Theme.stroke(Theme.Colors.inkUI, strokePx, label)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	return label
end

local function roundFrame(name: string, size: UDim2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = size
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	Theme.corner(RETICLE_SIZE, frame)
	frame.Parent = parent
	return frame
end

local function crossIcon(parent: Instance): Frame
	local cross = Instance.new("Frame")
	cross.Name = "Cross"
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromOffset(RETICLE_CROSS, RETICLE_CROSS)
	cross.BackgroundTransparency = 1
	cross.Visible = false
	for index, rotation in { 45, -45 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar" .. index
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(1, 0, 0, 3)
		bar.Rotation = rotation
		bar.BackgroundColor3 = Palette.White
		bar.BorderSizePixel = 0
		Theme.stroke(Theme.Colors.inkUI, 1, bar)
		bar.Parent = cross
	end
	cross.Parent = parent
	return cross
end

local function ensureReticle(): Reticle?
	local current = reticle
	if current and current.gui.Parent ~= nil then
		return current
	end
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = RETICLE_GUI
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = RETICLE_DISPLAY_ORDER
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.Enabled = false

	local root = Instance.new("Frame")
	root.Name = "Reticle"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(RETICLE_SIZE, RETICLE_SIZE)
	root.BackgroundTransparency = 1
	root.Active = false
	-- Part 8: the UI scale, like the duel reticle (this full-bleed gui has no UIScale of its own).
	local rootScale = Instance.new("UIScale")
	rootScale.Parent = root
	UIController.trackScale(rootScale)

	-- Cooldown fill: the ring's inside, cleared from the bottom up as the cooldown runs out.
	local fill = roundFrame("Fill", UDim2.fromScale(1, 1), root)
	fill.BackgroundColor3 = Palette.White
	fill.BackgroundTransparency = RETICLE_FILL_TRANSPARENCY
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90 -- keypoint 0 at the top, 1 at the bottom
	fillGradient.Parent = fill

	local ring = roundFrame("Ring", UDim2.fromScale(1, 1), root)
	Theme.stroke(Palette.White, 3, ring)
	local ringScale = Instance.new("UIScale")
	ringScale.Parent = ring
	local outline = roundFrame("Outline", UDim2.new(1, 6, 1, 6), ring) -- an Ink edge so the ring reads on light floors
	Theme.stroke(Theme.Colors.inkUI, 1, outline)

	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(RETICLE_DOT, RETICLE_DOT)
	dot.BackgroundColor3 = Palette.White
	dot.BorderSizePixel = 0
	Theme.corner(RETICLE_DOT, dot)
	Theme.stroke(Theme.Colors.inkUI, 1, dot)
	dot.Parent = root

	local cross = crossIcon(root)
	-- Foam fix 2: the small state text has the thin outline (the 2 px one closed the gaps between its words).
	local label = outlinedLabel("State", "Chip", Palette.White, Theme.Stroke.thin, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, RETICLE_TEXT_GAP),
		Size = UDim2.fromOffset(RETICLE_TEXT_WIDTH, 0),
		Text = "",
	})
	label.Parent = root
	local hit = outlinedLabel("Hit", "H2", Palette.Lemon, Theme.Stroke.text, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -6),
		Size = UDim2.fromOffset(RETICLE_TEXT_WIDTH, 0),
		Text = text("combat.hit"),
		Visible = false,
	})
	hit.Parent = root
	local hitScale = Instance.new("UIScale")
	hitScale.Name = "Pop"
	hitScale.Parent = hit

	root.Parent = screen
	screen.Parent = playerGui
	local made: Reticle = {
		gui = screen,
		root = root,
		ringScale = ringScale,
		fillGradient = fillGradient,
		dot = dot,
		cross = cross,
		label = label,
		labelWidth = 0,
		hit = hit,
		hitScale = hitScale,
		hitStart = -math.huge,
		hitUntil = -math.huge,
		lastFill = -1,
	}
	reticle = made
	return made
end

local function setReticleFill(r: Reticle, progress: number)
	if math.abs(progress - r.lastFill) < 0.002 then
		return
	end
	r.lastFill = progress
	-- The top (1 - progress) stays filled; the cleared part grows upward as the cooldown runs out.
	local edge = math.clamp(1 - progress, 0, 1)
	local keys: { NumberSequenceKeypoint }
	if edge <= 0.001 then
		keys = { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) }
	elseif edge >= 0.999 then
		keys = { NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) }
	else
		keys = {
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(edge, 0),
			NumberSequenceKeypoint.new(math.min(edge + 0.001, 0.999), 1),
			NumberSequenceKeypoint.new(1, 1),
		}
	end
	r.fillGradient.Transparency = NumberSequence.new(keys)
end

-- Foam fix 2: whether `point` (viewport px, GetMouseLocation space) is on a HUD button or an open dialog
-- (DuelFormat.aimBlocked). PlayerGui finds its GuiObjects in the GUI inset's space, like InputObject.Position.
local function aimOverGui(point: Vector2): boolean
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return false
	end
	local at = point - GuiService:GetGuiInset()
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(at.X, at.Y)
	end)
	return ok and type(objects) == "table" and DuelFormat.aimBlocked(objects)
end

local function stepReticle(now: number)
	local aim = ThrowController.getAimState()
	local active = inZone and ControlsController.isContextActive("Practice") and not ControlsController.isBlocked()
	local shown = PracticeController.reticleView(aim, active, now)
	-- Foam fix 2: never drawn over a HUD button (it cut the Settings tile's label) or an open dialog.
	local visible = shown.visible and not aimOverGui(aim.screenPosition)
	local existing = reticle
	if existing == nil and not visible then
		return -- built on first use
	end
	local r = existing or ensureReticle()
	if r == nil then
		return
	end
	r.gui.Enabled = visible
	if not visible then
		return
	end
	r.root.Position = UDim2.fromOffset(aim.screenPosition.X, aim.screenPosition.Y)
	r.dot.Visible = shown.icon ~= "cross"
	r.cross.Visible = shown.icon == "cross"
	-- Feature 1: while charging the fill grows to c in the toy's colour (the top c filled) and the ring pulses at full.
	local charging = aim.charging and shown.icon == "dot"
	setReticleFill(r, if charging then 1 - aim.charge elseif shown.icon == "fill" then shown.fill else 1)
	local fillFrame = r.fillGradient.Parent
	if fillFrame and fillFrame:IsA("Frame") then
		local colour = if charging then aim.chargeColor or Palette.White else Palette.White
		local alpha = if charging then RETICLE_CHARGE.chargeFillTransparency else RETICLE_FILL_TRANSPARENCY
		if fillFrame.BackgroundColor3 ~= colour then
			fillFrame.BackgroundColor3 = colour
		end
		if fillFrame.BackgroundTransparency ~= alpha then
			fillFrame.BackgroundTransparency = alpha
		end
	end
	local label = ""
	if shown.reasonCode then
		label = Strings.reasonText(shown.reasonCode)
	elseif shown.textKey then
		label = text(shown.textKey, { seconds = string.format("%.1f", shown.seconds or 0) })
	end
	if r.label.Text ~= label then
		r.label.Text = label
		-- Chip is a display kind, so the measure never yields; the text wraps past RETICLE_TEXT_WIDTH.
		r.labelWidth = math.min(RETICLE_TEXT_WIDTH, Theme.textWidth(label, "Chip") + 2 * Theme.Stroke.thin)
	end
	-- Overlays fix: the state text moves in from a screen edge (it ran off the right edge by the Settings tile).
	local offset = DuelFormat.reticleLabelOffset(
		aim.screenPosition.X,
		r.labelWidth,
		r.gui.AbsoluteSize.X,
		UIController.scale(),
		RETICLE_TEXT_EDGE
	)
	local position = UDim2.new(0.5, math.floor(offset + 0.5), 1, RETICLE_TEXT_GAP)
	if r.label.Position ~= position then
		r.label.Position = position
	end
	local clock = os.clock()
	local reduced = Tweens.reducedMotion()
	local _, _, pulse = DuelFormat.chargeLook(if charging then aim.charge else 0, clock, reduced)
	r.ringScale.Scale = PracticeController.hitMarkerScale(clock - r.hitStart, reduced) * pulse
	r.hit.Visible = clock < r.hitUntil
	if r.hit.Visible then
		local scale, rotation = PracticeController.hitTextPop(clock - r.hitStart, hitTiltSign, reduced)
		r.hitScale.Scale = scale
		r.hit.Rotation = rotation
	end
end

-- "Hit!" and the target's distance above a target the local player hit, while it is down.
local function targetLabel(state: TargetState)
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local anchor: BasePart? = state.parts[1]
	if playerGui == nil or anchor == nil then
		return
	end
	local board = Instance.new("BillboardGui")
	board.Name = "SD_PracticeHit"
	board.Adornee = anchor
	board.AlwaysOnTop = true
	board.LightInfluence = 0
	board.ResetOnSpawn = false
	board.Size = UDim2.fromScale(6, 2.4)
	board.StudsOffsetWorldSpace = Vector3.new(0, LABEL_LIFT, 0)
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = board
	local function line(order: number, value: string, height: number, color: Color3)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, height)
		label.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = value
		local stroke = Instance.new("UIStroke")
		stroke.Color = Palette.Ink
		stroke.Thickness = 2
		stroke.Parent = label
		label.Parent = board
	end
	line(1, text("combat.hit"), 0.6, Palette.Lemon)
	line(2, text("practice.distanceLabel", { distance = state.def.distance }), 0.4, Palette.White)
	board.Parent = playerGui
	hitBoards[board] = task.delay(DOWN_SECONDS, function()
		hitBoards[board] = nil
		board:Destroy()
	end)
end

local function clearHitBoards()
	for board, timer in hitBoards do
		if coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
		board:Destroy()
	end
	table.clear(hitBoards)
end

-- Zone --------------------------------------------------------------------------------------------------------------

local function setZone(inside: boolean)
	if inside == inZone then
		return
	end
	inZone = inside
	ControlsController.setContext("Practice", inside)
	if inside then
		stats.entered += 1
	else
		tally.throws, tally.hits = 0, 0
	end
	refreshPanel()
	PracticeController.ZoneChanged:fire(inside)
end

local function checkZone()
	local root = localRoot()
	local inside = root ~= nil and PracticeTargets.inThrowBox(root.Position) and not inMatch()
	setZone(inside)
end

-- Events ------------------------------------------------------------------------------------------------------------

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	if payload == nil or payload.kind ~= "practice" then
		return
	end
	if payload.throwerId == Players.LocalPlayer.UserId and inZone then
		tally.throws += 1
		refreshPanel()
	end
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact == nil or impact.kind ~= "target" then
		return
	end
	local state = targetOf(impact)
	if state then
		state.hitClock = os.clock()
		state.resting = false
		stats.reactions += 1
	end
end

local function onHitConfirmed(impact: Types.ThrowImpactPayload)
	if impact.kind ~= "target" then
		return
	end
	-- §18.4.4 / §18.6: the thrower's hit cue lands on the contact frame (it never waits for the hit-stop).
	SoundController.play(SOUND_HIT_CONFIRM)
	hitTiltSign = -hitTiltSign
	stats.ownHits += 1
	if inZone then
		tally.hits += 1
		refreshPanel()
	end
	local state = targetOf(impact)
	if state then
		targetLabel(state)
	end
	local r = reticle
	if r then
		local clock = os.clock()
		r.hitStart = clock
		r.hitUntil = clock + HIT.hitTextMs / 1000
	end
end

-- Frame step --------------------------------------------------------------------------------------------------------

local function step(dt: number, clock: number): boolean
	local now = serverNow()
	zoneTimer += dt
	if zoneTimer >= ZONE_CHECK_SECONDS then
		zoneTimer = 0
		checkZone()
		if inZone then
			layoutPanel() -- the HUD around it can change (the queue pill, the cards in the left column)
		end
	end
	stepTargets(now, clock)
	stepReticle(now)
	return true
end

-- Public ------------------------------------------------------------------------------------------------------------

-- True while the local player is inside the practice zone (and not in a match).
function PracticeController.isInZone(): boolean
	return inZone
end

-- The practice targets this client knows (streamed in), as { id, distance, position (floor point now) }.
function PracticeController.targets(): { { id: string, distance: number, position: Vector3 } }
	local list = {}
	local now = serverNow()
	for _, state in targets do
		table.insert(list, {
			id = state.def.id,
			distance = state.def.distance,
			position = PracticeTargets.positionAt(state.def, now),
		})
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Studio / debug counters.
function PracticeController.counts(): { [string]: any }
	local bound, moving = 0, 0
	for _, state in targets do
		bound += 1
		if state.moving then
			moving += 1
		end
	end
	local connected = 0
	for _, connection in connections do
		if connection.connected then
			connected += 1
		end
	end
	local boards = 0
	for _ in hitBoards do
		boards += 1
	end
	local throws, hits = currentStats()
	local r = reticle
	return {
		inZone = inZone,
		reticleShown = r ~= nil and r.gui.Enabled,
		targets = bound,
		movingTargets = moving,
		reactions = stats.reactions,
		ownHits = stats.ownHits,
		entered = stats.entered,
		throws = throws,
		hits = hits,
		hitBoards = boards,
		connections = connected,
	}
end

-- Lifecycle

function PracticeController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "render"))
	c:add(CollectionService:GetInstanceAddedSignal(RANGE.targetTag):Connect(bindTarget))
	c:add(CollectionService:GetInstanceRemovedSignal(RANGE.targetTag):Connect(unbindTarget))
	for _, instance in CollectionService:GetTagged(RANGE.targetTag) do
		bindTarget(instance)
	end
	track(NetController.on("ThrowStarted", onThrowStarted))
	track(NetController.on("ThrowImpact", onThrowImpact))
	track(ThrowController.HitConfirmed:connect(onHitConfirmed))
	track(StateController.changed("practice"):connect(function()
		refreshPanel()
	end))
	c:add(function()
		setZone(false)
		for model in table.clone(targets) do
			unbindTarget(model)
		end
		table.clear(connections)
		clearHitBoards()
		local current = panel
		panel = nil
		if current then
			current:Destroy()
		end
		local r = reticle
		reticle = nil
		if r then
			r.gui:Destroy()
		end
	end)
end

function PracticeController.start()
	if cleanup ~= nil then
		ensurePanel()
	end
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function PracticeController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return PracticeController
