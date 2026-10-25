--!strict
-- ControlsController (client only). DESIGN §2.4, §5.10, §10.4 step 2, §11.7. The one Controls module: every
-- ContextActionService binding goes through it.
--
-- Input map (§11.7) as data: action -> context, keys, priority. Features bind an action by name with a handler; the
-- keys live only here.
-- Contexts: world contexts Lobby / Duel / Practice and overlay contexts Modal / Inspect, each on or off (Lobby is on
-- by default). Every action stays bound; outside its context it returns Pass (§11.7):
--   world actions (Medium priority) run only while their context is on and nothing holds a block;
--   overlay actions (High priority) run while their context is on, and Sink only then.
--   The CAS Cancel state always reaches the handler (Cancel = abort) and passes.
--   End is treated like Cancel when the action is not live (Part 5, §17.3.2): it still reaches the handler and
--   passes, so a hold that began while the action was live (hold-to-squeeze) always sees its release, even after a
--   block, a context change or a focused TextBox came in between. pressAction() follows the same rule.
--   Keyboard shortcuts are ignored while a TextBox is focused (chat).
-- Duel and Practice (Part 4, §5.10, §11.7):
--   * Throw / PracticeThrow = MouseButton1, ButtonR2, the touch Throw button; Ultimate / PracticeUltimate = X (Q until
--     the Duel HUD, owner 2026-10-24), ButtonL2, the touch Ultimate button; Dash / PracticeDash = E and Left Shift (C
--     until 2026-10-24; Medium + 1 so Shift beats the Shift Lock switch), ButtonB, the touch Dash button (spec phase 5,
--     user decision 2026-10-11; ButtonB stays the Modal context's Back while a modal is open: ModalBack is High and
--     sinks it). Duel actions run in the Duel context, Practice actions in the Practice one.
--   * Feature 1 (2026-10-11; design: the combat-effects page "Squishy Combat FP v2.html", html:88, 96, 393-398): Catch =
--     Q (E until 2026-10-24), ButtonL1 (build choice, NOT IN DESIGN: no Duel action uses it), the touch Catch button and the right mouse
--     button, in the Duel context only (nothing throws at you in practice). The right button comes from
--     UserInputService.InputBegan, like the world click below, never from a ContextActionService binding: it never
--     sinks, so the third-person camera keeps its right-button drag. E left DuelSqueeze (the design's squish key is F,
--     html:399, its catch key E, html:398); PracticeSqueeze keeps it. The touch Catch button (catchButton × UIScale) sits
--     above Throw, toward the jump button (CATCH_DIRECTIONS, kept clear like Dash; on the big screens' crowded corner
--     one step further out, CATCH_STRETCHES) and shows only in the Duel context.
--   * Triggers (ButtonR2 / ButtonL2) count as pressed above Config.Combat.Aim.triggerThreshold (0.5), or above the
--     action's own triggerThreshold (InspectZoomTriggers: Config.Inspect.Input.triggerDeadzone): the handler sees one
--     Begin when the trigger crosses it and one End when it drops back (triggerEdge, pure).
--   * A Throw press that began over an interactive GuiObject (a button, a text box, an Active frame) is ignored.
--   * The Duel context follows the server-written LocalPlayer attributes SD_MatchId / SD_DuelPhase
--     (contextsForPhase, pure): Duel on from Preparing through Result, Lobby off from Preparing until SD_DuelPhase is
--     "" again (lobby actions are locked from Matched through Returning, §5.4). Practice is set by PracticeController
--     (inside SD_PracticeZone and not in a match). Duels never call block() (§11.7), so no menu freezes a duelist.
--   * Touch buttons (§5.10, §11.2): ScreenGui SD_Touch (reading: DisplayOrder 12, between SD_DuelHud and the dimmer)
--     with Throw (104 px × UIScale, never below 72) and Ultimate (80 px × UIScale) above-left of it, inside the safe
--     insets, outside the thumbstick zone (lower-left 40% × 45%) and the jump button (read from
--     PlayerGui.TouchGui.TouchControlFrame.JumpButton, else Roblox's default spot), 16 px apart (touchLayout, pure).
--     UIScale here is touchScale(screen) (pure), the HUD's own UI scale (UI/Layout.uiScale of the width and the
--     height, UI FINAL R2's PR1), so the HUD, the practice panel and the first-person pad, which lay out around
--     touchLayout(screen, UIController.scale()), keep clear of the very boxes drawn.
--     Shown only while PreferredInput is Touch and the Duel or Practice context is live; Ultimate only while
--     setTouchAvailable("Ultimate", true) (the locked loadout has an ultimate). Spec phase 5: a third round button, Dash
--     (dashButton × UIScale, in Sky), left of Throw and a little lower, else above it (touchLayout keeps it `gap` from
--     Throw, Ultimate and the jump button and out of the thumbstick zone). touchButtonsShown() says whether they
--     are up and TouchButtonsChanged fires when that changes (no HUD user since the lobby HUD of 2026-10-11 dropped
--     the phone dock). A touch button presses the live
--     action through pressAction(), exactly like a key. setTouchState() draws the cooldown: a vertical UIGradient
--     transparency edge at 1 - progress over the round button plus a text (§11.6, no images).
--     Foam UI restyle (spec 2026-10-09; look only: sizes, places, input and the cooldown unchanged): each round button
--     is an opaque foam disc (Theme.foam: InkUI outline, top highlight, bevel and ink drop drawn once for its base
--     size, so they scale with it): Throw in Strawberry, Ultimate in its gold (TOUCH_ACCENTS), the label in the display
--     font, white with the InkUI outline (the outlined-text rule), the cooldown shade in InkUI.
-- * Ref-counted block(reason) -> release(): the first block disables character movement through
--   PlayerModule:GetControls():Disable(), the last release re-enables it. Releases are idempotent.
-- * Duel freeze (§5.4 Positioning "clients disable PlayerModule controls", Countdown "frozen"): while SD_DuelPhase is
--   Positioning or Countdown the PlayerModule controls are disabled too (movementFrozenForPhase, pure), without
--   blocking any input; they come back with the next phase. The server also holds WalkSpeed / JumpHeight at 0.
--   Fallback (Part 4 test play): current Roblox runs the default controls internally and puts no PlayerModule in
--   PlayerScripts. Then movement is stopped by sinking the movement keys at a high ContextActionService priority
--   ("SD_MoveSink": WASD, arrows, Space, Thumbstick1; ButtonA stays free for gamepad UI selection).
-- * PreferredInput tracking (UserInputService.PreferredInput), with a change signal.
-- Inspect (Part 6, §10.6): the Inspect context's actions (InspectRotateKeys arrows, InspectZoomIn = / keypad +,
--   InspectZoomOut - / keypad -, InspectWheel, InspectSqueeze F / ButtonX, InspectReset R / ButtonY, InspectStick
--   Thumbstick2, InspectZoomTriggers R2 / L2 with the trigger edges above at the small Config.Inspect.Input.
--   triggerDeadzone, so the zoom speed follows Position.Z from the first bit of travel) are overlay actions (High
--   priority, Sink only while the context is on and the handler handles them). Reading: the SD_MoveSink fallback sits
--   at High + 100 and sinks the arrow keys whenever movement is blocked, which is always the case while Inspect is
--   open, so an action with aboveMoveSink = true (the arrows) is bound one step above the sink; a handler that passes
--   hands them on to it. Knead (spec phase2-squeeze §3.6): InspectPalms (Q / ButtonL1, held) and InspectRewax (W /
--   ButtonR1, aboveMoveSink); while Inspect kneads, InspectSqueeze (F / ButtonX) is the thumb crunch.
-- First person (spec 2026-10-10 §3.1, §3.5): DuelSqueeze = F, ButtonX (E until feature 1) and DuelForfeit = Backspace (keyboard only) in
--   the Duel context; PracticeSqueeze = F, ButtonX (E until 2026-10-24) in the Practice context, bound one step above the lobby actions
--   (aboveLobby: Medium + 1, still under the High overlay actions), so in the practice throw box it sees F, E and
--   ButtonX before the lobby Squeeze whatever the bind order (a handler that passes hands them on to it: the lobby
--   Squeeze takes F, E and ButtonX since spec 2026-10-11 §3.8). Backspace reaches DuelForfeit only while no back
--   handler holds the Modal context (ModalBack is High and sinks it first).
--   Final polish (2026-10-11): HandInspect = R (the design's inspect key, fp.js:656) and ButtonL1 (build choice, NOT IN
--   DESIGN: no world action uses it; the Backpack is off) in the Lobby context, so it is live in the lobby look and in
--   the practice range and never in a match; ViewmodelController plays the held toy's showcase with it (its touch way
--   is the overlay's own Inspect button).
-- Movement overhaul (2026-10-17): LobbySlide = C, Left Ctrl, ButtonB in the Lobby context (LobbyMoveController's power
--   slide; the handler passes in the practice throw box, so PracticeDash keeps C and ButtonB there).
-- Tap or click to squeeze (lobby HUD spec 2026-10-11 §2): a left click or a touch on the 3D world presses the lobby
--   Squeeze through pressAction() (so the Lobby context, blocks and the End rule decide as for a key), with the
--   InputObject (SqueezeController holds while it is down). It comes from UserInputService.InputBegan, never from a
--   ContextActionService binding (the last bound action sees an input first, so a bound left button would take
--   practice-box clicks before PracticeThrow), and it never sinks anything (Roblox's camera drag is untouched). A press
--   counts unless (worldPointerPresses, pure) the game already took it (gameProcessedEvent), it is on the UI
--   (pointerOnGui, pure: a shown button, text box, Active object or a surface with a background, so a toast or the
--   coach card's body never squeezes), the Practice context is on (a click throws there; the first-person pad and the
--   keys squeeze there), or it is a touch in the thumbstick zone (inThumbZone, pure: touchLayout's lower-left zone) or
--   on the jump button, or a second world touch while the first is down. The press's release (InputEnded) is sent as
--   its End. Phase 5 (lobby bases spec 2026-10-11 §9): a press that would squeeze is first offered to the pointer claim
--   (setPointerClaim, one owner: CapsuleController); when it takes it (a tap on a capsule opens its card), nothing is
--   pressed.
-- Pens3 phase 13 (the throw on the launch deck's open area): the world context Highway, set by HighwayThrowController
--   while the local character stands in the throw area (WorldLayout.Highway.throwArea). HighwayThrow = MouseButton1,
--   ButtonR2 and the touch Throw button there (Medium, ignoreOverGui, as PracticeThrow); a world click there throws,
--   never squeezes (worldPointerPresses' `practice` fact is the Practice or the Highway context). The touch buttons
--   show on touch in it too, only Throw (touchContextAllows: Catch in a duel only, Ultimate and Dash in a duel or the
--   practice range).
--
-- A handler returns true when it handled the input (Sink); anything else passes it on. Virtual presses (touch
-- buttons, Studio AutoDriver) call the handler with input = nil.

-- Services

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local AbilityBarFormat = require(Client.UI.AbilityBarFormat)
local Layout = require(Client.UI.Layout)
local Theme = require(Client.UI.Theme)

-- Types

export type Context = "Lobby" | "Duel" | "Practice" | "Highway" | "Modal" | "Inspect"
export type Handler = (inputState: Enum.UserInputState, input: InputObject?) -> boolean?
export type TouchButton = "Throw" | "Ultimate" | "Dash" | "Catch"
-- A screen rectangle in pixels (top-left corner and size).
export type Rect = { x: number, y: number, w: number, h: number }
-- `jump` is the jump button's box the buttons were laid out against (on large screens it is taller than Throw).
export type TouchLayout = { throw: Rect, ultimate: Rect, dash: Rect, catch: Rect, jump: Rect }
-- What worldPointerPresses() checks for one left click or touch (lobby HUD spec 2026-10-11 §2).
export type PointerFacts = {
	kind: Enum.UserInputType,
	processed: boolean, -- UserInputService's gameProcessedEvent: a button, Roblox's own UI or a sinking action took it
	onGui: boolean, -- pointerOnGui() under it (a toast or the coach card's body is no button)
	practice: boolean, -- the Practice or (pens3 phase 13) the Highway context is on (a click throws there)
	thumbZone: boolean, -- a touch in the thumbstick zone (inThumbZone)
	onJump: boolean, -- a touch on the jump button
	touchDown: boolean, -- a touch while an earlier world touch is still down (only the first one counts)
}
type Input = Enum.KeyCode | Enum.UserInputType

type ActionDef = {
	context: Context,
	inputs: { Input },
	ignoreOverGui: boolean?, -- §5.10: a press that began over an interactive GuiObject is ignored
	touch: TouchButton?, -- the on-screen touch button that presses this action
	aboveMoveSink: boolean?, -- bound one step above SD_MoveSink (Inspect's arrow keys, §10.6)
	aboveLobby: boolean?, -- bound one step above the lobby actions (PracticeSqueeze, first-person spec §3.5)
	triggerThreshold: number?, -- R2 / L2 count as pressed above this (default Config.Combat.Aim.triggerThreshold)
}

type Binding = {
	action: string,
	casName: string,
	def: ActionDef,
	handler: Handler,
	triggers: { [Enum.KeyCode]: boolean }, -- analog triggers currently past the threshold
	ignored: { [InputObject]: boolean }, -- presses that began over a GuiObject (their End is dropped too)
}

type TouchWidget = {
	button: TextButton,
	shade: Frame,
	gradient: UIGradient,
	label: TextLabel,
	progress: number,
	text: string,
}

-- Constants

local CAS_PREFIX = "SD_"
local PLAYER_MODULE_WAIT_SECONDS = Config.UI.Controls.playerModuleWaitSeconds
local OVERLAY: { [Context]: boolean } = { Modal = true, Inspect = true }
local ALL_CONTEXTS: { Context } = { "Lobby", "Duel", "Practice", "Highway", "Modal", "Inspect" }
local TRIGGER_THRESHOLD = Config.Combat.Aim.triggerThreshold
local TRIGGERS: { [Enum.KeyCode]: boolean } = { [Enum.KeyCode.ButtonR2] = true, [Enum.KeyCode.ButtonL2] = true }
local TOUCH = Config.UI.Touch
local ATTR_MATCH_ID = "SD_MatchId"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
-- Phases with the Duel context on (§5.4): the HUD and the throw keys belong to the duel from Preparing to Result.
local DUEL_PHASES: { [string]: boolean } = {
	Preparing = true,
	Positioning = true,
	Countdown = true,
	Active = true,
	SuddenDeath = true,
	Result = true,
}
-- Phases whose character movement is frozen on the client too (§5.4 Positioning: "clients disable PlayerModule
-- controls"; Countdown: "frozen"); the server holds WalkSpeed / JumpHeight at 0 and checks the spot (CombatService).
local FROZEN_PHASES: { [string]: boolean } = { Positioning = true, Countdown = true }
local TOUCH_GUI_NAME = "SD_Touch"
-- reading (not in DESIGN, provisional): the touch buttons' ScreenGui sits above SD_DuelHud (11), below the dimmer (19).
local TOUCH_DISPLAY_ORDER = 12
-- reading (not in DESIGN, provisional): Roblox's default touch jump button when TouchGui is missing (TouchJumpController:
-- 70 px at x = W - 95, y = H - 90 on screens whose short side is <= 500 px, else 120 px at W - 170, H - 210).
local SMALL_SCREEN_AXIS = 500
local JUMP_SMALL = { size = 70, right = 95, bottom = 90 }
local JUMP_LARGE = { size = 120, right = 170, bottom = 210 }
-- reading: Ultimate sits up and to the left of Throw along this direction (more up than left).
local ULT_DIRECTION = Vector2.new(-0.6, -0.8)
-- Spec phase 5 (reading): Dash's places around Throw, in order: left and a little lower, above and a little right, left
-- and a little higher; the first that keeps every touchLayout rule wins.
local DASH_DIRECTIONS: { Vector2 } = { Vector2.new(-1, 0.25), Vector2.new(0.15, -1), Vector2.new(-1, -0.25) }
-- Feature 1 (build choice 2026-10-11, NOT IN DESIGN): Catch's places around Throw, in order: above toward the jump
-- button (phones), steeper (the larger jump button of big screens), straight up, then right and up.
local CATCH_DIRECTIONS: { Vector2 } =
	{ Vector2.new(0.5, -1), Vector2.new(0.35, -1), Vector2.new(0.15, -1), Vector2.new(1, -0.6) }
-- Feature 1 (build choice 2026-10-11): where no direction fits at the touching distance (the 120 px jump button of a
-- big screen sits right of Throw, Ultimate above-left, Dash left), the directions are tried again this many times as
-- far out (checked over 21 screens from 568×320 to 3840×2160).
local CATCH_STRETCHES: { number } = { 1, 1.35, 1.7 }
local NO_STRETCH: { number } = { 1 }
-- Feature 1: a touch button that shows only in some contexts (Catch: nothing throws at you in practice). Pens3 phase
-- 13: the Highway context shows only Throw (touchContextAllows).
-- Duel HUD part 2 (2026-10-24): in duels and matches AbilityBarController's arc draws Catch, Ultimate and Dash, so these
-- three show only in the practice range now (Catch: never).
local TOUCH_CONTEXTS: { [string]: { Context } } = { Catch = {}, Ultimate = { "Practice" }, Dash = { "Practice" } }
local GAP_MARGIN_PX = 0.01 -- keeps the two round buttons at least TOUCH.gap apart after single-precision rounding
local TOUCH_SHADE_TRANSPARENCY = 0.45 -- the cooling-down part of a round button
local TOUCH_TEXT_SIZE = Config.UI.TextSize.Button
local MIN_TEXT_SIZE = Config.UI.minTextSize
-- Foam UI: each round button's accent and the base size its foam bands are drawn for (they scale with the button).
-- UI FINAL R1: the Ultimate in its gold (H:234), never the lilac of a disabled button (H:246).
local TOUCH_ACCENTS: { [string]: Theme.AccentName } =
	{ Throw = "strawberry", Ultimate = "ult", Dash = "sky", Catch = "mint" }
local TOUCH_BASE_SIZES: { [string]: number } =
	{ Throw = TOUCH.throwButton, Ultimate = TOUCH.ultButton, Dash = TOUCH.dashButton, Catch = TOUCH.catchButton }

-- §11.7 input map. The lobby Squeeze also takes F (spec 2026-10-11 §3.8: the design's squish key, as in duels; no
-- other Lobby action uses F, and Inspect's F is an overlay action that sinks only while Inspect is open).
local ACTIONS: { [string]: ActionDef } = {
	Squeeze = { context = "Lobby", inputs = { Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.ButtonX } },
	Squishies = { context = "Lobby", inputs = { Enum.KeyCode.I } },
	InspectEquipped = { context = "Lobby", inputs = { Enum.KeyCode.V, Enum.KeyCode.ButtonY } },
	FocusHud = { context = "Lobby", inputs = { Enum.KeyCode.DPadUp } },
	-- Final polish (2026-10-11): the first-person Inspect showcase (ViewmodelController).
	HandInspect = { context = "Lobby", inputs = { Enum.KeyCode.R, Enum.KeyCode.ButtonL1 } },
	-- Movement overhaul (2026-10-17): the lobby's power slide (LobbyMoveController; it passes in the practice throw
	-- box, where C and ButtonB are PracticeDash).
	LobbySlide = { context = "Lobby", inputs = { Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB } },
	Throw = {
		context = "Duel",
		inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		ignoreOverGui = true,
		touch = "Throw",
	},
	-- Duel HUD (owner 2026-10-24, "Design keys"; design: Duel HUD.dc.html:323): X is the ultimate (was Q).
	Ultimate = { context = "Duel", inputs = { Enum.KeyCode.X, Enum.KeyCode.ButtonL2 }, touch = "Ultimate" },
	PracticeThrow = {
		context = "Practice",
		inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		ignoreOverGui = true,
		touch = "Throw",
	},
	PracticeUltimate = { context = "Practice", inputs = { Enum.KeyCode.X, Enum.KeyCode.ButtonL2 }, touch = "Ultimate" },
	-- Pens3 phase 13: the throw on the launch deck's open area (HighwayThrowController).
	HighwayThrow = {
		context = "Highway",
		inputs = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
		ignoreOverGui = true,
		touch = "Throw",
	},
	-- Spec phase 5 (user decision 2026-10-11): the dash (DashController).
	-- Duel HUD (owner 2026-10-24, "Design keys"; design: Duel HUD.dc.html:323): E and Left Shift dash (was C), bound
	-- one step above Medium so Shift beats Roblox's Shift Lock switch while the dash is live (it passes otherwise).
	Dash = {
		context = "Duel",
		inputs = { Enum.KeyCode.E, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB },
		touch = "Dash",
		aboveLobby = true,
	},
	PracticeDash = {
		context = "Practice",
		inputs = { Enum.KeyCode.E, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonB },
		touch = "Dash",
		aboveLobby = true,
	},
	-- Feature 1 (2026-10-11): the catch (CatchController); the right mouse button comes from UserInputService (header).
	-- Duel HUD (owner 2026-10-24): Q catches (was E); the right mouse button stays.
	Catch = { context = "Duel", inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 }, touch = "Catch" },
	-- First person (spec 2026-10-10 §3.1, §3.5): the hand's squeeze and the PC forfeit key (E is the catch since
	-- feature 1).
	DuelSqueeze = { context = "Duel", inputs = { Enum.KeyCode.F, Enum.KeyCode.ButtonX } },
	DuelForfeit = { context = "Duel", inputs = { Enum.KeyCode.Backspace } },
	PracticeSqueeze = {
		context = "Practice",
		inputs = { Enum.KeyCode.F, Enum.KeyCode.ButtonX }, -- E left it for PracticeDash (Duel HUD, 2026-10-24)
		aboveLobby = true,
	},
	ModalBack = { context = "Modal", inputs = { Enum.KeyCode.Backspace, Enum.KeyCode.ButtonB } },
	ModalTabPrevious = { context = "Modal", inputs = { Enum.KeyCode.ButtonL1 } },
	ModalTabNext = { context = "Modal", inputs = { Enum.KeyCode.ButtonR1 } },
	-- §10.6 Inspect (InspectController binds them; live only while the Inspect context is on).
	InspectRotateKeys = {
		context = "Inspect",
		inputs = { Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down },
		aboveMoveSink = true,
	},
	InspectZoomIn = { context = "Inspect", inputs = { Enum.KeyCode.Equals, Enum.KeyCode.KeypadPlus } },
	InspectZoomOut = { context = "Inspect", inputs = { Enum.KeyCode.Minus, Enum.KeyCode.KeypadMinus } },
	InspectWheel = { context = "Inspect", inputs = { Enum.UserInputType.MouseWheel } },
	InspectSqueeze = { context = "Inspect", inputs = { Enum.KeyCode.F, Enum.KeyCode.ButtonX } },
	InspectReset = { context = "Inspect", inputs = { Enum.KeyCode.R, Enum.KeyCode.ButtonY } },
	InspectStick = { context = "Inspect", inputs = { Enum.KeyCode.Thumbstick2 } },
	-- R2 / L2 zoom from the first bit of travel (§10.6: the speed follows Position.Z), not from the 0.5 throw edge.
	InspectZoomTriggers = {
		context = "Inspect",
		inputs = { Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2 },
		triggerThreshold = Config.Inspect.Input.triggerDeadzone,
	},
	-- Spec phase2-squeeze §3.6, Inspect's knead (InspectController binds them): Q hold = the palm squeeze, W = re-wax (W
	-- one step above SD_MoveSink, like the arrows). The gamepad buttons are a build choice (NOT IN DESIGN): L1 / R1 are
	-- ModalTabPrevious / Next, which pass while Inspect (no tabs) is the top modal.
	InspectPalms = { context = "Inspect", inputs = { Enum.KeyCode.Q, Enum.KeyCode.ButtonL1 } },
	InspectRewax = { context = "Inspect", inputs = { Enum.KeyCode.W, Enum.KeyCode.ButtonR1 }, aboveMoveSink = true },
}
-- UI FINAL R4 (H:653-654, plan R4 "Keys 1-5"): the keys 1-5 open the HUD's windows (Squishies, Boxes, Shop, Quests,
-- Daily) in the lobby (NavN, Lobby) and switch between them while one is open (ModalNavN, Modal); keyboard only, never
-- in a duel or practice (HudController binds them). Nothing else uses One..Five.
local NAV_KEYS: { Enum.KeyCode } =
	{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
for index, key in NAV_KEYS do
	ACTIONS["Nav" .. index] = { context = "Lobby", inputs = { key } }
	ACTIONS["ModalNav" .. index] = { context = "Modal", inputs = { key } }
end
-- Lobby HUD spec 2026-10-11 §2: the action a left click or a touch on the 3D world presses (UserInputService, not a
-- binding: see the header).
local WORLD_POINTER_ACTION = "Squeeze"
-- Touch buttons in a fixed order, with their Strings label keys.
local TOUCH_BUTTONS: { string } = { "Throw", "Ultimate", "Dash", "Catch" }
local TOUCH_LABEL_KEYS: { [string]: string } =
	{ Throw = "controls.throw", Ultimate = "controls.ultimate", Dash = "controls.dash", Catch = "controls.catch" }
-- Feature 1: the action the right mouse button presses (from UserInputService, see the header).
local RIGHT_BUTTON_ACTION = "Catch"

-- Module table

local ControlsController = {}

-- Fired with (context, active) when a context turns on or off.
ControlsController.ContextChanged = Signal.new() :: Signal.Signal<Context, boolean>
-- Fired with (blocked) when the block count goes 0 -> 1 or 1 -> 0.
ControlsController.BlockChanged = Signal.new() :: Signal.Signal<boolean>
-- Fired with (preferredInput) when UserInputService.PreferredInput changes.
ControlsController.PreferredInputChanged = Signal.new() :: Signal.Signal<Enum.PreferredInput>
-- Fired with (shown) when the touch Throw / Ultimate buttons show or hide (touchButtonsShown).
ControlsController.TouchButtonsChanged = Signal.new() :: Signal.Signal<boolean>

-- Private

local log = Log.new("Controls")
local cleanup: Cleanup.Cleanup? = nil
local active: { [string]: boolean } = { Lobby = true }
local bindings: { [string]: Binding } = {}
local blockCount = 0
local blockReasons: { [string]: number } = {}
local movementFrozen = false -- Positioning / Countdown (movementFrozenForPhase): movement only, no input block
local preferred: Enum.PreferredInput? = nil
local controls: any = nil -- PlayerModule controls, resolved in start()
local useMoveSink = false -- start() found no PlayerModule: block movement with the SD_MoveSink binding instead
local moveSinkBound = false
local MOVE_SINK_ACTION = "SD_MoveSink"
local MOVE_SINK_PRIORITY = Enum.ContextActionPriority.High.Value + 100
local MOVE_SINK_KEYS: { Enum.KeyCode } = {
	Enum.KeyCode.W,
	Enum.KeyCode.A,
	Enum.KeyCode.S,
	Enum.KeyCode.D,
	Enum.KeyCode.Up,
	Enum.KeyCode.Down,
	Enum.KeyCode.Left,
	Enum.KeyCode.Right,
	Enum.KeyCode.Space,
	Enum.KeyCode.Thumbstick1,
}
local touchAvailable: { [string]: boolean } = { Throw = true, Ultimate = false, Dash = true, Catch = true }
local rightMouse = false -- feature 1: a right click pressed Catch, until the button lifts
local touchOwner: { [string]: string } = {} -- the action a touch button's Begin went to (its End goes there too)
local touchGui: ScreenGui? = nil
local touchWidgets: { [string]: TouchWidget } = {}
local touchCleanup: Cleanup.Cleanup? = nil
local touchShown = false -- the last shouldShowTouch() answer (TouchButtonsChanged)
local worldTouch: InputObject? = nil -- the world touch that pressed the lobby Squeeze, until it lifts
local worldMouse = false -- a left click on the world pressed the lobby Squeeze, until the button lifts
local pointerClaim: ((input: InputObject) -> boolean)? = nil -- Phase 5: setPointerClaim

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	if template == nil then
		return ""
	end
	return Strings.format(template, args)
end

local function setMoveSink(on: boolean)
	if on == moveSinkBound then
		return
	end
	moveSinkBound = on
	if on then
		ContextActionService:BindActionAtPriority(MOVE_SINK_ACTION, function()
			return Enum.ContextActionResult.Sink
		end, false, MOVE_SINK_PRIORITY, table.unpack(MOVE_SINK_KEYS))
	else
		ContextActionService:UnbindAction(MOVE_SINK_ACTION)
	end
end

local function applyMovement()
	if controls == nil then
		if useMoveSink then
			setMoveSink(blockCount > 0 or movementFrozen)
		end
		return -- otherwise applied once start() resolves the controls
	end
	local ok, err = pcall(function()
		if blockCount > 0 or movementFrozen then
			controls:Disable()
		else
			controls:Enable()
		end
	end)
	if not ok then
		log:warn("could not change the movement controls:", err)
	end
end

local function isKeyboard(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Keyboard
end

local function isLive(def: ActionDef): boolean
	if active[def.context] ~= true then
		return false
	end
	if OVERLAY[def.context] then
		return true
	end
	return blockCount == 0
end

-- The PlayerGui's GuiObjects under a mouse or touch press at `input` (PlayerGui finds them in the GUI inset's space,
-- like InputObject.Position); nil for other inputs or without a PlayerGui.
local function guiObjectsAt(input: InputObject): { GuiObject }?
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
		return nil
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	local position = input.Position
	local ok, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(position.X, position.Y)
	end)
	return if ok and type(objects) == "table" then objects else nil
end

-- True when a mouse or touch press at `input` landed on an interactive GuiObject of the PlayerGui.
local function beganOverGui(input: InputObject): boolean
	local objects = guiObjectsAt(input)
	if objects == nil then
		return false
	end
	for _, object in objects do
		if object:IsA("GuiButton") or object:IsA("TextBox") or object.Active then
			return true
		end
	end
	return false
end

-- The level above which an action's R2 / L2 count as pressed: its own triggerThreshold, else the 0.5 aim threshold.
local function triggerThresholdOf(def: ActionDef): number
	return def.triggerThreshold or TRIGGER_THRESHOLD
end

local function runHandler(binding: Binding, inputState: Enum.UserInputState, input: InputObject?): boolean
	local ok, handled = pcall(binding.handler, inputState, input)
	if not ok then
		log:error(`action {binding.action} failed:`, handled)
		return false
	end
	return handled == true
end

local function casHandler(binding: Binding)
	return function(_: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
		if inputState == Enum.UserInputState.Cancel then
			table.clear(binding.triggers)
			table.clear(binding.ignored)
			local ok, err = pcall(binding.handler, inputState, input)
			if not ok then
				log:error(`action {binding.action} failed on Cancel:`, err)
			end
			return Enum.ContextActionResult.Pass
		end
		-- Analog triggers: one Begin when the threshold is crossed, one End when it drops back.
		local state = inputState
		local keyCode = input.KeyCode
		if TRIGGERS[keyCode] then
			local wasDown = binding.triggers[keyCode] == true
			local threshold = triggerThresholdOf(binding.def)
			local down, edge = ControlsController.triggerEdge(wasDown, inputState, input.Position.Z, threshold)
			if down then
				binding.triggers[keyCode] = true
			else
				binding.triggers[keyCode] = nil
			end
			if edge == nil then
				return if down and isLive(binding.def)
					then Enum.ContextActionResult.Sink
					else Enum.ContextActionResult.Pass
			end
			state = edge
		end
		if state == Enum.UserInputState.End and binding.ignored[input] then
			-- Its Begin never reached the handler (a press over a GuiObject), so there is nothing to end.
			binding.ignored[input] = nil
			return Enum.ContextActionResult.Pass
		end
		if not isLive(binding.def) or (isKeyboard(input) and UserInputService:GetFocusedTextBox() ~= nil) then
			-- §17.3.2: End always reaches the handler (like Cancel), then passes; Begin and Change do not.
			if state == Enum.UserInputState.End then
				runHandler(binding, state, input)
			end
			return Enum.ContextActionResult.Pass
		end
		if state == Enum.UserInputState.Begin and binding.def.ignoreOverGui and beganOverGui(input) then
			binding.ignored[input] = true
			return Enum.ContextActionResult.Pass
		end
		local handled = runHandler(binding, state, input)
		return if handled then Enum.ContextActionResult.Sink else Enum.ContextActionResult.Pass
	end
end

local function priorityOf(def: ActionDef): number
	if def.aboveMoveSink then
		return MOVE_SINK_PRIORITY + 1
	end
	if def.aboveLobby then
		return Enum.ContextActionPriority.Medium.Value + 1
	end
	return if OVERLAY[def.context]
		then Enum.ContextActionPriority.High.Value
		else Enum.ContextActionPriority.Medium.Value
end

-- Touch buttons ---------------------------------------------------------------------------------------------------

-- UI FINAL R2 (PR1): the UI scale of `screen` (the HUD's, Layout.uiScale: width and height).
function ControlsController.touchScale(screen: Vector2): number
	return Layout.uiScale(screen.Y, screen.X)
end

-- The jump button's rectangle in `gui` space, read from the TouchGui when it exists.
local function jumpRect(gui: ScreenGui): Rect?
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	local touchGuiRoot = playerGui and playerGui:FindFirstChild("TouchGui")
	local frame = touchGuiRoot and touchGuiRoot:FindFirstChild("TouchControlFrame")
	local jump = frame and frame:FindFirstChild("JumpButton")
	if jump == nil or not jump:IsA("GuiObject") or not jump.Visible then
		return nil
	end
	local origin = gui.AbsolutePosition
	return {
		x = jump.AbsolutePosition.X - origin.X,
		y = jump.AbsolutePosition.Y - origin.Y,
		w = jump.AbsoluteSize.X,
		h = jump.AbsoluteSize.Y,
	}
end

local function shouldShowTouch(): boolean
	if ControlsController.preferredInput() ~= Enum.PreferredInput.Touch then
		return false
	end
	local duel = active.Duel == true
	local practice = (active.Practice == true or active.Highway == true) and blockCount == 0
	return duel or practice
end

local function setGradient(widget: TouchWidget, progress: number)
	-- Top part (1 - progress) shaded, bottom part clear: the clear part grows upward as the cooldown runs out.
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
	widget.gradient.Transparency = NumberSequence.new(keys)
end

local function layoutTouch()
	local gui = touchGui
	if gui == nil then
		return
	end
	local size = gui.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return
	end
	local scale = ControlsController.touchScale(size)
	local arcLeft = if active.Duel then AbilityBarFormat.phoneArcLeft(size) else nil
	local layout = ControlsController.touchLayout(size, scale, jumpRect(gui), arcLeft)
	local rects: { [string]: Rect } =
		{ Throw = layout.throw, Ultimate = layout.ultimate, Dash = layout.dash, Catch = layout.catch }
	for name, widget in touchWidgets do
		local rect = rects[name]
		widget.button.Position = UDim2.fromOffset(rect.x, rect.y)
		widget.button.Size = UDim2.fromOffset(rect.w, rect.h)
		widget.label.TextSize = math.max(MIN_TEXT_SIZE, math.floor(TOUCH_TEXT_SIZE * scale))
	end
end

local function refreshTouchVisibility()
	local show = shouldShowTouch()
	if show ~= touchShown then
		touchShown = show
		ControlsController.TouchButtonsChanged:fire(show)
	end
	local gui = touchGui
	if gui == nil then
		return
	end
	gui.Enabled = show
	for name, widget in touchWidgets do
		widget.button.Visible = show
			and touchAvailable[name] == true
			and ControlsController.touchContextAllows(name, active :: any)
	end
	if show then
		layoutTouch()
	end
end

local function pressTouch(button: string, inputState: Enum.UserInputState)
	if inputState == Enum.UserInputState.Begin then
		for action, binding in bindings do
			if binding.def.touch == button and isLive(binding.def) then
				touchOwner[button] = action
				ControlsController.pressAction(action, inputState)
				return
			end
		end
		return
	end
	local owner = touchOwner[button]
	touchOwner[button] = nil
	if owner then
		ControlsController.pressAction(owner, inputState)
	end
end

local function buildTouchWidget(name: string, parent: Instance, c: Cleanup.Cleanup): TouchWidget
	local button = Instance.new("TextButton")
	button.Name = "Touch_" .. name .. "Button"
	button.AutoButtonColor = false
	button.BackgroundTransparency = 0
	button.Text = ""
	button.Visible = false
	-- Foam UI: an opaque foam disc in the button's accent (the corner is fully round at any size).
	local bands = Theme.Foam.tile
	Theme.foam(button, {
		radius = Theme.Radius.pill,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.accentColors(TOUCH_ACCENTS[name], true),
		fixedHeight = TOUCH_BASE_SIZES[name],
	})

	local shade = Instance.new("Frame")
	shade.Name = "Cooldown"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.Colors.inkUI
	shade.BackgroundTransparency = 0
	shade.BorderSizePixel = 0
	shade.Active = false
	local shadeCorner = Instance.new("UICorner")
	shadeCorner.CornerRadius = UDim.new(0.5, 0)
	shadeCorner.Parent = shade
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90 -- keypoint 0 at the top, 1 at the bottom
	gradient.Parent = shade
	shade.Parent = button

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	-- Centred on the face: raised by half the bands (a share of the size, so it follows the button).
	label.Position = UDim2.fromScale(0, -(bands.bevel + bands.drop - bands.top) / 2 / TOUCH_BASE_SIZES[name])
	label.FontFace = Theme.font("Button")
	label.TextSize = TOUCH_TEXT_SIZE
	label.TextWrapped = true
	label.Text = text(TOUCH_LABEL_KEYS[name])
	label.ZIndex = 2
	-- The outlined-text rule: white with the 2 px InkUI outline (the Button kind is display text of 20 base px).
	Theme.textOnColor(label, "Button")
	label.Parent = button

	c:add(button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			pressTouch(name, Enum.UserInputState.Begin)
		end
	end))
	c:add(button.InputEnded:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
			pressTouch(name, Enum.UserInputState.End)
		end
	end))
	button.Parent = parent

	local widget: TouchWidget = {
		button = button,
		shade = shade,
		gradient = gradient,
		label = label,
		progress = 1,
		text = label.Text,
	}
	setGradient(widget, 1)
	return widget
end

local function ensureTouchGui(playerGui: Instance)
	if touchGui ~= nil then
		return
	end
	local c = Cleanup.new()
	touchCleanup = c
	local gui = Instance.new("ScreenGui")
	gui.Name = TOUCH_GUI_NAME
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = TOUCH_DISPLAY_ORDER
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	gui.Enabled = false
	c:add(gui)
	touchGui = gui
	for _, name in TOUCH_BUTTONS do
		touchWidgets[name] = buildTouchWidget(name, gui, c)
	end
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutTouch))
	c:add(function()
		touchGui = nil
		table.clear(touchWidgets)
		table.clear(touchOwner)
	end)
	gui.Parent = playerGui
	refreshTouchVisibility()
end

-- Duel context from the server-written attributes.
local function applyPhaseContexts()
	local player = Players.LocalPlayer
	if player == nil then
		return
	end
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	local phase = player:GetAttribute(ATTR_DUEL_PHASE)
	local wanted = ControlsController.contextsForPhase(
		if type(matchId) == "string" then matchId else "",
		if type(phase) == "string" then phase else ""
	)
	ControlsController.setContext("Duel", wanted.Duel)
	ControlsController.setContext("Lobby", wanted.Lobby)
	if wanted.inMatch then
		ControlsController.setContext("Practice", false)
	end
	local frozen = ControlsController.movementFrozenForPhase(
		if type(matchId) == "string" then matchId else "",
		if type(phase) == "string" then phase else ""
	)
	if frozen ~= movementFrozen then
		movementFrozen = frozen
		applyMovement()
	end
end

-- Lobby HUD spec 2026-10-11 §2: a left click or a touch on the 3D world presses the lobby Squeeze (see the header).
-- Never sinks: it only listens. Feature 1: a right click the game did not take presses Catch (header).
local function onPointerBegan(input: InputObject, processed: boolean)
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton2 then
		if not processed and ControlsController.pressAction(RIGHT_BUTTON_ACTION, Enum.UserInputState.Begin, input) then
			rightMouse = true
		end
		return
	end
	local touch = kind == Enum.UserInputType.Touch
	if kind ~= Enum.UserInputType.MouseButton1 and not touch then
		return
	end
	local down = worldTouch
	if
		down and (down.UserInputState == Enum.UserInputState.End or down.UserInputState == Enum.UserInputState.Cancel)
	then
		worldTouch = nil -- the engine ended it without an InputEnded (e.g. taken over by the camera)
	end
	local zone, jump = false, false
	local gui = touchGui
	if touch and gui then
		-- touchLayout's space: the SD_Touch gui (safe insets); InputObject.Position is in the GUI inset's space.
		local at = Vector2.new(input.Position.X, input.Position.Y) - gui.AbsolutePosition
		zone = ControlsController.inThumbZone(at, gui.AbsoluteSize)
		local box = jumpRect(gui)
		jump = box ~= nil and at.X >= box.x and at.X <= box.x + box.w and at.Y >= box.y and at.Y <= box.y + box.h
	end
	local presses = ControlsController.worldPointerPresses({
		kind = kind,
		processed = processed,
		onGui = not processed and ControlsController.pointerOnGui(guiObjectsAt(input) or {}),
		practice = active.Practice == true or active.Highway == true, -- pens3 phase 13: a click throws on the deck
		thumbZone = zone,
		onJump = jump,
		touchDown = touch and worldTouch ~= nil,
	})
	local claim = pointerClaim
	if presses and claim and claim(input) then
		return -- Phase 5: taken (a tap on a capsule opens its card), so it is no squeeze
	end
	if presses and ControlsController.pressAction(WORLD_POINTER_ACTION, Enum.UserInputState.Begin, input) then
		if touch then
			worldTouch = input
		else
			worldMouse = true
		end
	end
end

-- The release of a world press sent as its End (it always reaches the handler, §17.3.2).
local function onPointerEnded(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if rightMouse then
			rightMouse = false
			ControlsController.pressAction(RIGHT_BUTTON_ACTION, Enum.UserInputState.End, input)
		end
		return
	end
	local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
	if input == worldTouch or (mouse and worldMouse) then
		if mouse then
			worldMouse = false
		else
			worldTouch = nil
		end
		ControlsController.pressAction(WORLD_POINTER_ACTION, Enum.UserInputState.End, input)
	end
end

-- Public: pure helpers

-- One analog trigger sample: returns whether the trigger is now pressed and the edge (Begin / End) to report, or nil
-- when nothing crossed the threshold. A Begin that reports no analog level counts as fully pressed (digital
-- triggers); End and Cancel count as released.
function ControlsController.triggerEdge(
	wasDown: boolean,
	inputState: Enum.UserInputState,
	level: number,
	threshold: number
): (boolean, Enum.UserInputState?)
	local value = if level == level then level else 0
	if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		value = 0
	elseif inputState == Enum.UserInputState.Begin and not (value > 0) then
		value = 1
	end
	local down = value > threshold
	if down == wasDown then
		return wasDown, nil
	end
	return down, if down then Enum.UserInputState.Begin else Enum.UserInputState.End
end

-- Which world contexts the duel attributes call for: Duel from Preparing through Result; Lobby off while in a match
-- (any non-empty SD_DuelPhase, or a match id), i.e. from Matched through Returning.
function ControlsController.contextsForPhase(
	matchId: string,
	phase: string
): { Duel: boolean, Lobby: boolean, inMatch: boolean }
	local inMatch = matchId ~= "" or phase ~= ""
	return {
		Duel = inMatch and DUEL_PHASES[phase] == true,
		Lobby = not inMatch,
		inMatch = inMatch,
	}
end

-- Whether the duel attributes freeze character movement (PlayerModule controls off, input still live): Positioning
-- and Countdown of a match (§5.4). Not a block(): the throw keys and the HUD stay live (§11.7), and the freeze ends by
-- itself with the phase (Active, Cancelled, Void, or the attributes cleared).
function ControlsController.movementFrozenForPhase(matchId: string, phase: string): boolean
	return (matchId ~= "" or phase ~= "") and FROZEN_PHASES[phase] == true
end

-- §5.10 touch layout in `screen` pixels (the safe-inset area): Throw (throwButton × uiScale, at least throwButtonMin)
-- left of the jump button, bottoms aligned, `gap` apart; Ultimate (ultButton × uiScale) up and to the left, its centre
-- throwRadius + ultRadius + gap from Throw's centre. Both stay on screen and out of the thumbstick zone. Spec phase 5:
-- Dash (dashButton × uiScale) beside Throw (DASH_DIRECTIONS), apart from the others; feature 1: Catch (catchButton ×
-- uiScale) the same way (CATCH_DIRECTIONS), apart from Dash too. `jump` in the result is the jump button's box used (the
-- given one, else Roblox's default spot), so HUD layouts keep clear of it.
-- Duel HUD part 2 (2026-10-24): `arcLeft` (px), the ability bar's arc's left edge in a duel or match: Throw keeps `gap`
-- left of it (the arc wraps the jump button where Throw stood).
function ControlsController.touchLayout(screen: Vector2, uiScale: number, jump: Rect?, arcLeft: number?): TouchLayout
	local gap = TOUCH.gap
	local throwSize = math.max(TOUCH.throwButton * uiScale, TOUCH.throwButtonMin)
	local ultSize = math.max(TOUCH.ultButton * uiScale, TOUCH.minTargetFloor)
	local jumpBox = jump
	if jumpBox == nil then
		local spec = if math.min(screen.X, screen.Y) <= SMALL_SCREEN_AXIS then JUMP_SMALL else JUMP_LARGE
		jumpBox = {
			x = screen.X - spec.right,
			y = screen.Y - spec.bottom,
			w = spec.size,
			h = spec.size,
		}
	end
	local jb = jumpBox :: Rect
	local throwX = jb.x - gap - throwSize
	if arcLeft then
		throwX = math.min(throwX, arcLeft - gap - throwSize)
	end
	local throwY = jb.y + jb.h - throwSize
	throwX = math.clamp(throwX, 0, math.max(screen.X - throwSize, 0))
	throwY = math.clamp(throwY, 0, math.max(screen.Y - throwSize, 0))

	local throwCentre = Vector2.new(throwX + throwSize / 2, throwY + throwSize / 2)
	-- GAP_MARGIN_PX: Vector2 is single precision, so the exact distance can round a hair below `gap`.
	local distance = throwSize / 2 + ultSize / 2 + gap + GAP_MARGIN_PX
	local ultCentre = throwCentre + ULT_DIRECTION.Unit * distance
	local ultX = math.clamp(ultCentre.X - ultSize / 2, 0, math.max(screen.X - ultSize, 0))
	local ultY = math.clamp(ultCentre.Y - ultSize / 2, 0, math.max(screen.Y - ultSize, 0))
	-- Keep it out of the thumbstick zone (lower-left): push it right of the zone if it reaches into it.
	local zoneRight = screen.X * TOUCH.thumbstickZoneWidth
	local zoneTop = screen.Y * (1 - TOUCH.thumbstickZoneHeight)
	if ultX < zoneRight + gap and ultY + ultSize > zoneTop then
		ultX = zoneRight + gap
	end
	local throwRect: Rect = { x = throwX, y = throwY, w = throwSize, h = throwSize }
	local ultRect: Rect = { x = ultX, y = ultY, w = ultSize, h = ultSize }
	local jumpRect: Rect = { x = jb.x, y = jb.y, w = jb.w, h = jb.h }
	-- Spec phase 5: Dash, a round button `gap` from Throw and Ultimate (centre distance), `gap` from the jump box, on
	-- screen and out of the thumbstick zone, at the first of DASH_DIRECTIONS around Throw that keeps all of that.
	local dashSize = math.max(TOUCH.dashButton * uiScale, TOUCH.minTargetFloor)
	local function centreOf(rect: Rect): Vector2
		return Vector2.new(rect.x + rect.w / 2, rect.y + rect.h / 2)
	end
	local function fits(rect: Rect, others: { Rect }): boolean
		local centre = centreOf(rect)
		for _, other in others do
			if (centre - centreOf(other)).Magnitude < rect.w / 2 + other.w / 2 + gap then
				return false
			end
		end
		local apartFromJump = rect.x + rect.w + gap <= jumpRect.x
			or jumpRect.x + jumpRect.w + gap <= rect.x
			or rect.y + rect.h + gap <= jumpRect.y
			or jumpRect.y + jumpRect.h + gap <= rect.y
		local inZone = rect.x < zoneRight + gap and rect.y + rect.h > zoneTop
		return apartFromJump and not inZone
	end
	-- A round button of `size` beside Throw: the first of `directions` whose place keeps every rule (else the first);
	-- feature 1: each of `stretches` (× the touching distance) in turn, nearest first.
	local function place(size: number, directions: { Vector2 }, others: { Rect }, stretches: { number }): Rect
		local chosen: Rect? = nil
		for _, stretch in stretches do
			for _, direction in directions do
				local reach = (throwSize / 2 + size / 2 + gap + GAP_MARGIN_PX) * stretch
				local centre = throwCentre + direction.Unit * reach
				local rect: Rect = {
					x = math.clamp(centre.X - size / 2, 0, math.max(screen.X - size, 0)),
					y = math.clamp(centre.Y - size / 2, 0, math.max(screen.Y - size, 0)),
					w = size,
					h = size,
				}
				if fits(rect, others) then
					return rect
				end
				chosen = chosen or rect
			end
		end
		return chosen :: Rect
	end
	local dashRect = place(dashSize, DASH_DIRECTIONS, { throwRect, ultRect }, NO_STRETCH)
	-- Feature 1: Catch, apart from Throw, Ultimate and Dash too (CATCH_DIRECTIONS, CATCH_STRETCHES).
	local catchSize = math.max(TOUCH.catchButton * uiScale, TOUCH.minTargetFloor)
	local catchRect = place(catchSize, CATCH_DIRECTIONS, { throwRect, ultRect, dashRect }, CATCH_STRETCHES)
	return {
		throw = throwRect,
		ultimate = ultRect,
		dash = dashRect,
		catch = catchRect,
		jump = jumpRect,
	}
end

-- Lobby HUD spec 2026-10-11 §2: whether a left click or a touch presses the lobby Squeeze: one on the 3D world that
-- nothing else took (see PointerFacts); any other input never does.
function ControlsController.worldPointerPresses(f: PointerFacts): boolean
	if f.kind ~= Enum.UserInputType.MouseButton1 and f.kind ~= Enum.UserInputType.Touch then
		return false
	end
	return not (f.processed or f.onGui or f.practice or f.thumbZone or f.onJump or f.touchDown)
end

-- Feature 1 / pens3 phase 13: whether the touch button `button` may show while `contexts` ({[Context] = true}) are on:
-- Catch in a duel only, Ultimate and Dash in a duel or the practice range, Throw in any (the Highway context too).
function ControlsController.touchContextAllows(button: string, contexts: { [string]: boolean }): boolean
	local only = TOUCH_CONTEXTS[button]
	if only == nil then
		return true
	end
	for _, context in only do
		if contexts[context] == true then
			return true
		end
	end
	return false
end

-- Whether `point` (px in `screen`, the touch buttons' safe-inset space) is in the thumbstick zone touchLayout keeps
-- clear: the lower-left Config.UI.Touch.thumbstickZoneWidth × thumbstickZoneHeight (40% × 45%).
function ControlsController.inThumbZone(point: Vector2, screen: Vector2): boolean
	return point.X < screen.X * TOUCH.thumbstickZoneWidth and point.Y > screen.Y * (1 - TOUCH.thumbstickZoneHeight)
end

-- Whether a press on these GuiObjects (PlayerGui:GetGuiObjectsAtPosition's) is on the UI: one of them shows and is a
-- button, a text box, an Active object or a surface with a background (a toast's panel or the coach card's body are
-- plain Frames, and a press on them is not a game-processed one). Clear holders and floating text let it through.
function ControlsController.pointerOnGui(objects: { GuiObject }): boolean
	for _, object in objects do
		if not object.Visible then
			continue
		end
		if object:IsA("GuiButton") or object:IsA("TextBox") or object.Active or object.BackgroundTransparency < 1 then
			return true
		end
	end
	return false
end

-- Public: bindings

-- Phase 5: `claim(input)` sees every left click or touch that would press the lobby Squeeze first; returning true takes
-- it (nothing is pressed). One claim at a time; nil removes it.
function ControlsController.setPointerClaim(claim: ((input: InputObject) -> boolean)?)
	pointerClaim = claim
end

-- Binds an action of the input map to a handler. Returns an idempotent unbind function. Binding an action that is
-- already bound replaces the old handler (with a warning).
function ControlsController.bindAction(action: string, handler: Handler): () -> ()
	local def = ACTIONS[action]
	assert(def ~= nil, `[SD][Controls] unknown action {tostring(action)}`)
	assert(type(handler) == "function", "[SD][Controls] handler must be a function")
	if bindings[action] ~= nil then
		log:warn(`action {action} was bound twice; the newer handler replaces the older one`)
		ControlsController.unbindAction(action)
	end
	local binding: Binding = {
		action = action,
		casName = CAS_PREFIX .. action,
		def = def,
		handler = handler,
		triggers = {},
		ignored = {},
	}
	bindings[action] = binding
	ContextActionService:BindActionAtPriority(
		binding.casName,
		casHandler(binding),
		false,
		priorityOf(def),
		table.unpack(def.inputs)
	)
	return function()
		if bindings[action] == binding then
			ControlsController.unbindAction(action)
		end
	end
end

function ControlsController.unbindAction(action: string)
	local binding = bindings[action]
	if binding == nil then
		return
	end
	bindings[action] = nil
	ContextActionService:UnbindAction(binding.casName)
end

-- Presses a bound action without its own key (touch buttons, Studio AutoDriver): the handler gets (inputState, input)
-- under the same context and block rules as a key; input is nil, or the key of another action that hands its press on
-- (ViewmodelController's PracticeSqueeze, spec 2026-10-11 §5: a held key keeps squeezing). Cancel always reaches it;
-- so does End (§17.3.2), which then returns false while the action is not live. Returns true when the handler
-- handled it.
function ControlsController.pressAction(action: string, inputState: Enum.UserInputState, input: InputObject?): boolean
	local binding = bindings[action]
	if binding == nil then
		return false
	end
	if inputState ~= Enum.UserInputState.Cancel and not isLive(binding.def) then
		if inputState == Enum.UserInputState.End then
			runHandler(binding, inputState, input)
		end
		return false
	end
	return runHandler(binding, inputState, input)
end

-- The ContextActionService callback bindAction() would install for `action` with `handler`, without binding
-- anything (unit tests drive it with stand-in input objects in Edit mode). Errors for an unknown action.
function ControlsController.casCallbackFor(
	action: string,
	handler: Handler
): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
	local def = ACTIONS[action]
	assert(def ~= nil, `[SD][Controls] unknown action {tostring(action)}`)
	return casHandler({
		action = action,
		casName = CAS_PREFIX .. action,
		def = def,
		handler = handler,
		triggers = {},
		ignored = {},
	})
end

-- True when `action` is bound and its context is live now (it would run on a key press).
function ControlsController.isActionLive(action: string): boolean
	local binding = bindings[action]
	return binding ~= nil and isLive(binding.def)
end

-- Bound action names, sorted (debug state).
function ControlsController.boundActions(): { string }
	local names = {}
	for name in bindings do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

-- The keys of an action (for prompts and hints), or nil for an unknown action.
function ControlsController.inputsOf(action: string): { Input }?
	local def = ACTIONS[action]
	return if def then table.clone(def.inputs) else nil
end

-- The R2 / L2 level above which `action` counts its trigger as pressed (triggerEdge's threshold), or nil for an
-- unknown action.
function ControlsController.triggerThresholdOf(action: string): number?
	local def = ACTIONS[action]
	return if def then triggerThresholdOf(def) else nil
end

-- The context of an action, or nil for an unknown action.
function ControlsController.contextOf(action: string): Context?
	local def = ACTIONS[action]
	return if def then def.context else nil
end

-- The ContextActionService priority an action is bound at (Medium for world actions, High for overlay ones, one step
-- above SD_MoveSink for aboveMoveSink ones, Medium + 1 for aboveLobby ones), or nil for an unknown action.
function ControlsController.priorityOfAction(action: string): number?
	local def = ACTIONS[action]
	return if def then priorityOf(def) else nil
end

-- The SD_MoveSink fallback's priority (High + 100, §10.4 step 2).
function ControlsController.moveSinkPriority(): number
	return MOVE_SINK_PRIORITY
end

-- Public: touch buttons

-- The jump button's box in `gui` space (the TouchGui's JumpButton while it shows), else nil (touchLayout then takes
-- Roblox's default spot). 2026-10-17: the lobby's touch Slide button (LobbyMoveController) sits beside it.
function ControlsController.jumpRectIn(gui: ScreenGui): Rect?
	return jumpRect(gui)
end

-- Shows or hides a touch button whenever touch controls are up (Ultimate only for a loadout with an ultimate).
function ControlsController.setTouchAvailable(button: TouchButton, available: boolean)
	if touchAvailable[button] == available then
		return
	end
	touchAvailable[button] = available
	refreshTouchVisibility()
end

-- Cooldown look of a touch button: progress 0 (just used) .. 1 (ready) and its text (nil = the button's name).
function ControlsController.setTouchState(button: TouchButton, progress: number, label: string?)
	local widget = touchWidgets[button]
	if widget == nil then
		return
	end
	local p = if progress == progress then math.clamp(progress, 0, 1) else 1
	if math.abs(p - widget.progress) > 0.002 or (p >= 1) ~= (widget.progress >= 1) then
		widget.progress = p
		setGradient(widget, p)
	end
	local wanted = label or text(TOUCH_LABEL_KEYS[button])
	if wanted ~= widget.text then
		widget.text = wanted
		widget.label.Text = wanted
	end
end

-- Public: contexts

function ControlsController.setContext(context: Context, on: boolean)
	assert(table.find(ALL_CONTEXTS, context) ~= nil, `[SD][Controls] unknown context {tostring(context)}`)
	local was = active[context] == true
	if was == on then
		return
	end
	active[context] = on
	ControlsController.ContextChanged:fire(context, on)
	refreshTouchVisibility()
end

function ControlsController.isContextActive(context: Context): boolean
	return active[context] == true
end

-- Active contexts, in a fixed order (debug state).
function ControlsController.activeContexts(): { Context }
	local list: { Context } = {}
	for _, context in ALL_CONTEXTS do
		if active[context] == true then
			table.insert(list, context)
		end
	end
	return list
end

-- Public: block

-- Blocks world input and character movement until every block is released. Returns the release function.
function ControlsController.block(reason: string): () -> ()
	assert(type(reason) == "string" and reason ~= "", "[SD][Controls] block needs a reason")
	blockCount += 1
	blockReasons[reason] = (blockReasons[reason] or 0) + 1
	if blockCount == 1 then
		applyMovement()
		ControlsController.BlockChanged:fire(true)
		refreshTouchVisibility()
	end
	local released = false
	return function()
		if released then
			return
		end
		released = true
		blockCount -= 1
		local left = (blockReasons[reason] or 1) - 1
		if left > 0 then
			blockReasons[reason] = left
		else
			blockReasons[reason] = nil
		end
		if blockCount == 0 then
			applyMovement()
			ControlsController.BlockChanged:fire(false)
			refreshTouchVisibility()
		end
	end
end

function ControlsController.isBlocked(): boolean
	return blockCount > 0
end

-- Reasons currently holding a block, sorted (one entry per reason, whatever its count).
function ControlsController.blockReasons(): { string }
	local list = {}
	for reason in blockReasons do
		table.insert(list, reason)
	end
	table.sort(list)
	return list
end

-- Public: preferred input

function ControlsController.preferredInput(): Enum.PreferredInput
	return preferred or UserInputService.PreferredInput
end

-- Whether the touch Throw / Ultimate buttons are up now: touch input and the Duel or Practice context live (§5.10).
-- Their box is touchLayout's whether or not they show; TouchButtonsChanged fires on a change.
function ControlsController.touchButtonsShown(): boolean
	return shouldShowTouch()
end

-- Small table for Studio debug hooks.
function ControlsController.debugState(): { [string]: any }
	local gui = touchGui
	return {
		contexts = ControlsController.activeContexts(),
		actions = ControlsController.boundActions(),
		touchShown = gui ~= nil and gui.Enabled,
		movementFrozen = movementFrozen,
		moveSink = moveSinkBound,
		touchAvailable = table.clone(touchAvailable),
	}
end

-- Lifecycle

function ControlsController.init()
	local c = Cleanup.new()
	cleanup = c
	preferred = UserInputService.PreferredInput
	c:add(UserInputService:GetPropertyChangedSignal("PreferredInput"):Connect(function()
		local now = UserInputService.PreferredInput
		if now ~= preferred then
			preferred = now
			ControlsController.PreferredInputChanged:fire(now)
			refreshTouchVisibility()
		end
	end))
	local player = Players.LocalPlayer
	if player then
		c:add(player:GetAttributeChangedSignal(ATTR_MATCH_ID):Connect(applyPhaseContexts))
		c:add(player:GetAttributeChangedSignal(ATTR_DUEL_PHASE):Connect(applyPhaseContexts))
		applyPhaseContexts()
	end
	c:add(UserInputService.InputBegan:Connect(onPointerBegan))
	c:add(UserInputService.InputEnded:Connect(onPointerEnded))
	c:add(function()
		worldTouch = nil
		worldMouse = false
		rightMouse = false
		for action in table.clone(bindings) do
			ControlsController.unbindAction(action)
		end
		local tc = touchCleanup
		touchCleanup = nil
		if tc then
			tc:clean()
		end
		touchShown = false
	end)
end

function ControlsController.start()
	local player = Players.LocalPlayer
	local playerGui = player and player:WaitForChild("PlayerGui", PLAYER_MODULE_WAIT_SECONDS)
	if playerGui and cleanup ~= nil then
		ensureTouchGui(playerGui)
	end
	local playerScripts = player and player:FindFirstChildOfClass("PlayerScripts")
	local playerModule = playerScripts and playerScripts:WaitForChild("PlayerModule", PLAYER_MODULE_WAIT_SECONDS)
	if playerModule == nil or not playerModule:IsA("ModuleScript") then
		log:info("no PlayerModule in PlayerScripts (built-in controls); movement blocks use the SD_MoveSink binding")
		useMoveSink = true
		applyMovement()
		return
	end
	local ok, result = pcall(function()
		return (require :: (ModuleScript) -> any)(playerModule):GetControls()
	end)
	if not ok or result == nil then
		log:warn("could not read the PlayerModule controls:", result, "- movement blocks use the SD_MoveSink binding")
		useMoveSink = true
		applyMovement()
		return
	end
	controls = result
	if blockCount > 0 or movementFrozen then
		applyMovement()
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function ControlsController.destroy()
	setMoveSink(false)
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return ControlsController
