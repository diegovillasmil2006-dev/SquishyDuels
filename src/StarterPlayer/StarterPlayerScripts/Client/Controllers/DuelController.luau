--!strict
-- DuelController (client only). DESIGN §5.2 (reset during a duel), §5.4, §5.9, §5.10, §9.8 (attacker feedback), §9.14,
-- §11.6 (duel HUD, result panel), §11.7. Follows StateController's duel view (DuelState + ThrowImpact lives +
-- UltimateCharge) and DuelResult, and reads ThrowController's aim / cooldown hooks (ThrowController owns throw input
-- and timing; this module only draws).
--
-- * Match start (first DuelState of a match): SD_DuelHud on; the Reset button is intercepted with
--   StarterGui:SetCore("ResetButtonCallback", BindableEvent) (retried until CoreGui accepts), so Reset opens our
--   "Forfeit the duel?" confirmation. Input contexts belong to ControlsController, which follows SD_MatchId /
--   SD_DuelPhase (Lobby off from Matched through Returning, Duel on Preparing..Result); this module never sets them.
--   Duels never call ControlsController.block (§11.7): no dialog here freezes the player. The §5.4 Positioning /
--   Countdown freeze ("clients disable PlayerModule controls") is ControlsController's too, from the same attributes
--   (movementFrozenForPhase: movement only, input stays live), on top of the server's WalkSpeed / JumpHeight 0.
-- * HUD (§11.6; UI/DuelFormat): top centre "You" and the opponent's name (a Studio test dummy is always labelled
--   "TEST DUMMY (Studio)"), each with life pips plus "3 lives" and the side label ("Strawberry side" / "Mint side"
--   text plus a berry / mint-leaf icon, never colour alone, §7.8; UI/Components/SideIcon); the timer (m:ss to
--   phaseEndsAt); top left Forfeit (Preparing..SuddenDeath); the opponent's "Dragon Rush ready" chip when their
--   charge is full; bottom centre the key hints ("Click" Throw · "Q" Ultimate / "R2" · "L2" as keycaps since the foam
--   restyle, without the ultimate for a loadout without one) with the throw cooldown bar and the ultimate meter
--   ("READY" + a 0.9 s pulse, static under ReducedMotion) on mouse / gamepad (touch has ControlsController's Throw /
--   Ult buttons instead). Lives pop when lost (UI/Components/Pips).
-- * Reticle and edge arrow (reading: a full-bleed overlay SD_DuelReticle, DisplayOrder of SD_DuelHud, ScreenInsets
--   None, so its pixels are viewport pixels like ThrowController's screenPosition and Camera:WorldToViewportPoint): in
--   Active / SuddenDeath a dot + ring at ThrowController.getAimState().screenPosition (the mouse; the centre on touch,
--   gamepad and shift lock), the cooldown arc while cooling (a clockwise pie: two UIGradient half discs, no images)
--   and the state as text (ready / seconds left / rooted / can't throw here, §5.10). An own hit
--   (ThrowController.HitConfirmed) pops the ring 1.3 -> 1 (250 ms) and shows "Hit!" for 400 ms (§9.8). The off-screen
--   arrow points to the opponent, in Danger while their Dragon Rush telegraph runs (the lane starts at them).
-- * Countdown (§9.14): "3", "2", "1" pop 1.3 -> 1.0 (250 ms, Back Out), "Throw!" exactly at the Countdown's
--   phaseEndsAt (server time); the countdown is the only TextScaled text (with a UITextSizeConstraint).
-- * Banners: sudden death (`duel.suddenDeath`); "Dragon Rush incoming!" (the opponent's ability incomingKey) from the
--   UltimateEvent telegraph until telegraphEndsAt, dismissed on release / cancel.
-- * Forfeit: the HUD button and the intercepted Reset open one confirmation: "Forfeit the duel?", what it does now
--   (cancelled before EarlyForfeitSeconds of Active, else the opponent wins) and Keep playing / Forfeit. Backspace,
--   ButtonB and the Roblox menu close it (UIController.pushBack); gamepad focus starts on Keep playing. Forfeit sends
--   DuelForfeit.
-- * Result (§9.14): the winner's character cheers (Config.Anim.duel.cheerBounces bounces) and a draw shrugs, on both
--   participants' clients (joint layer "duelEnd", blended out on Returning / at the end). Result panel in SD_Modal
--   (not a modal: the player can move during Result): VICTORY / DEFEAT / DRAW (or "Duel cancelled" / "Duel didn't
--   count"), the reason, stats (throws, hits, accuracy), the reward line from DuelResult only (0 Coins with the blocked
--   reason), quest lines and the loss tip; the title pops (Back Out 300 ms), lines appear with a 150 ms stagger. After
--   the return it gains Queue again (UIController.open("queue")) and Close, answers Back / ButtonB, takes gamepad
--   focus, and closes itself Config.UI.Result.autoCloseAfterReturnSeconds later (Batch 3: once someone pressed
--   Rematch, when the rematch offer ends instead; see the Batch 3 paragraph). A modal opened over it meanwhile
--   (Inspect) gets Back first (UIController) and keeps its focus when the card closes.
-- * Returning (§9.14): fade to the dark transition colour over Config.Duel.Positioning.ReturnFadeSeconds, the server
--   repositions, then the fade lifts when the match view ends (SD_DuelPhase cleared). Reading: a fade still dark after
--   StreamAroundTimeoutSeconds + PositioningTimeoutSeconds lifts anyway, so a lost message never leaves the screen
--   dark.
-- * Match end: SD_DuelHud and the reticle off, the default Reset restored.
-- * Dragon Rush refusals sent as Notify (`ult.*`, e.g. "Not enough room. Step away from the wall.") show as toasts.
-- Feel pass (§18.4.2, §18.4.7, §18.5.2 B6-B8, §18.6; the looks are pure in UI/DuelFormat, drawn from the HUD's one
-- Scheduler effect or the result panel's own; every sound is silent until the picker approves an id):
-- * Countdown: a round bubble behind each number (Strawberry / Lemon / Mint for 3 / 2 / 1) pops with it while both
--   tilt -6° / +6° -> 0; the old bubble bursts when the next number arrives; "Throw!" pops, holds, then grows while
--   fading. duel.countdownTick at 1.00 / 1.06 / 1.12 on 3, 2, 1 (DuelFormat.countdownCue), duel.go on "Throw!", and
--   duel.go at suddenDeathGoPitch with the sudden-death banner.
-- * Own hit: "Hit!" pops 1.3 -> 1 and tilts ±6° -> 0 (alternating per hit); ui.hitConfirm on the contact frame.
-- * Meters: the ultimate meter drains over DragonRush.meterDrainMs when the charge is spent (a rise shows at once);
--   READY pops 1.3 -> 1 before its 0.9 s pulse; the own ultimate becoming ready plays sfx.pop (2D, also on touch,
--   where READY is not shown); the opponent's ready chip pops the same way, silently.
-- * Result panel: the title in Lemon / Lavender / Sky (VICTORY / DEFEAT / DRAW) with a 3 px Ink stroke, popping and
--   tilting -4° -> 0 (DEFEAT from 1.15); duel.win / duel.lose / duel.draw at the title pop (nothing for cancelled or
--   void); 2D confetti inside the panel (UI/Confetti2D: 18 on a win, 6 on a draw, none on a defeat); the lines fade in
--   and slide up 10 px, 150 ms apart; the reward counts "+0" -> "+N Coins" over 600 ms with ui.coin ticks (at most one
--   per coinBatchSeconds), then pulses. The reward label is handed to HudController.setGainSource (cleared when the
--   panel closes), so the duel's Coins fly from it into the pill once the lobby HUD shows again (§18.5.2 B1).
-- * ReducedMotion: no scale, tilt, slide or confetti; fades <= 120 ms; the reward number is set at once; sounds stay.
-- Part 7 (§6.13, §11.6 result panel, §6.8):
-- * Quest lines name their quest: DuelFormat.result gets UI/QuestFormat.namer(StateController.get("quests")), so a
--   line reads "{quest}: 3/5" (just "3/5" for a quest the state does not know).
-- * The loss tip (DuelResult.tip = "duel.lossTip", decided by the server's TipService) gets three buttons under it:
--   Result_TipShowWayButton (tip.showWay: a client-only waypoint to WorldLayout.waypoint("practice"); reading: it lasts
--   until the player reaches the range (Waypoint's hide distance) or the next match begins), Result_TipGotItButton
--   (common.gotIt: hides the tip) and Result_TipDontShowButton (tip.dontShow: SetSettings {showTips = false}, then
--   hides the tip; the server stops sending tips).
-- Part 8 (layout pass, §11.2; the placement maths is pure and unit-tested in UI/DuelFormat):
-- * The top bar clears the top-left Forfeit button (DuelFormat.topBarPlacement): centred when there is room, moved
--   right just enough on narrow screens (667×375), under the button when even that does not fit. The countdown and
--   its bubbles stay under the bar (DuelFormat.countdownCenterY; 40% down as before when there is room).
-- * Readings (audited, unchanged): the bottom key hints show only on mouse / gamepad and the touch Throw / Ultimate
--   buttons only on touch (PreferredInput), so the two never share the screen; the opponent's Rush chip sits in the
--   top bar's opponent column (placed with it); banners (sudden death, Rush incoming) are UIController's transient
--   SD_Overlay banners; the edge arrow is a non-interactive overlay.
-- * The forfeit dialog sits in SD_Modal above the touch Throw / Ultimate buttons (SD_Touch), Active, its two buttons
--   wrapping at the largest text; Keep playing is still the gamepad primary and Back / ButtonB still close it.
-- * The result panel's lines scroll in a body sized by DuelFormat.resultLayout, with Queue again / Close pinned under
--   it and the panel kept on screen; the gamepad primary is Queue again, else Close (Batch 3: Rematch first while it
--   shows).
-- Batch 3 (friends, review #6): the result card's row starts with Result_RematchButton while FriendDuelService offers
-- a rematch with this opponent (the LocalPlayer's SD_RematchWith = their userId; never the Studio test dummy). A press
-- sends RematchRequest (no arguments); DuelFormat.rematchView words it: "Rematch"; once pressed "Waiting…" (disabled)
-- with the line "Waiting for {name}…" over the row; "{name} wants a rematch!" (the button pulses,
-- Config.UI.Result.rematchPulse, not under ReducedMotion) once the opponent's SD_RematchWant names this player; both:
-- the spinner and "Starting…" (the server waits out the requeue cooldown). The gamepad primary is Rematch while it
-- shows (when it hides while selected, the focus moves to Queue again or Close). If someone pressed Rematch by the
-- auto-close, the card waits until the server ends the offer; otherwise it closes as before; a new match closes it
-- anyway. A card closed while this player still wants the rematch sends RematchRequest again, which takes the wish
-- back (the server toggles it).
-- Foam UI restyle (2026-10-09; spec docs/superpowers/specs/2026-10-09-foam-ui-restyle-design.md, the kit in
-- 2026-10-09-foam-ui-components.md). Look and layout only: every timing, name, focus and behaviour above stays.
-- * Top bar: each side is a foam card (Theme.panel) tinted with the side's light colour (DuelFormat.sideColors:
--   Bubblegum / MintCream; team colour blocking, always with the side text and icon, §7.8); the timer is a Frosting
--   foam pill at least TIMER_MIN_WIDTH wide, so its digits never nudge the cards; the opponent's "Dragon Rush ready"
--   is a lilac Chip under their card. The bar keeps its width (two SIDE_WIDTH cards and the timer), so
--   DuelFormat.topBarPlacement and countdownCenterY work as before.
-- * Bottom dock (mouse / gamepad): a foam panel with one meter per action, each a Keycap (DuelFormat.hintKeys) beside
--   its caption over a ProgressBar (throw Sky, ultimate Lilac); READY is a raised Frosting chip centred on the
--   ultimate's bar, so it appearing never moves the dock.
-- * Countdown: the bubbles are foam discs (their §18.5.2 B6 colour with a white highlight, a shade band, the InkUI drop
--   and outline); the digits and "Throw!" are white with a thick InkUI outline (the outlined-text rule at countdown
--   size; reading: B6's "Ink digit with a white stroke" becomes the foam kit's outlined numeral).
-- * Reticle, "Hit!" and the edge arrow: InkUI outlines with round joins instead of the world Ink / white.
-- * Forfeit dialog: a foam panel whose question is its header tab (Theme.headerTab); the note and the buttons sit in
--   its Body frame.
-- * Result card: InkUI outlines and scroll bar; the stats sit in a Biscuit inset that fades in with its line; the
--   reward note and the quest lines are captions in Ink2.
-- Overlays fix (2026-10-09; look and layout only):
-- * A side card's name stays on one line, cut with "…" when too long (a long name made the cards uneven). On the
--   compact layout (phones) each card has two rows: the name, and the lives row, which also takes the side word and
--   icon (§7.8: text and icon, never colour alone), the pips nearest the timer; both cards are as wide as the wider
--   row needs (DuelFormat.sideCardWidth: at least SIDE_WIDTH, capped so the bar stays beside the Forfeit button).
-- * The forfeit dialog (DuelFormat.panelBelowBar) and the result card (DuelFormat.resultLayout with the bar's bottom)
--   start under the top bar; when one cannot fit there, the top bar hides while it shows (barHidden).
-- * The result card holds the notices NotifyController holds back during a match (NotifyController.holdBack) until it
--   closes, so "Quest complete!" never lands on it.
-- * The reticle's state text moves in from a screen edge so it is never cut off (DuelFormat.reticleLabelOffset).
-- Foam fix 2 (2026-10-09; look and layout only):
-- * Side cards on both layouts: both as wide as the wider one's content needs (DuelFormat.sideNeed through
--   sideCardWidth, at least SIDE_WIDTH, capped beside Forfeit), from the texts at rest: on a PC the name's one-line
--   width (it holds the opponent's whole name) or the lives row; on phones the lives row with the side icon and word
--   (a longer name is cut with "…"); the pips at their resting width (Pips.rowWidth). The widest need of a match is
--   kept, so a popping pip or "1 life" never moves the cards. The rows sit SIDE_ROW_GAP 6 apart and the pips 6 px
--   apart outside their outlines (UI/Components/Pips), so nothing touches.
-- * The result card waits until the eliminator's "K.O.!" banner has gone (VfxController.koBannerUntil,
--   DuelFormat.resultWait, at most RESULT_WAIT_MAX); the poses start at once. A quest this duel finished is marked on
--   it: a Mint disc with the Quests screen's InkUI check beside the line in InkUI bold (the other quest lines stay Ink2
--   captions).
-- * The reticle hides while the forfeit dialog is open and while its point is on a HUD button or an open dialog
--   (DuelFormat.aimBlocked); its state text has the thin InkUI outline.
-- Foam fix 3 (2026-10-10; look only): the top bar's OpponentColumn (the opponent's card and its "Dragon Rush ready"
-- chip) is as wide as the cards (layoutTopBar), not automatic: on a PC its automatic width grew about 34 base past the
-- card once the card held the opponent's whole name, so the centred bar's timer sat about 22 px left of the screen's
-- centre (the countdown, "Throw!" and the Forfeit box are centred).
-- First person (spec 2026-10-10 §3.1; FirstPersonController owns the camera, reached by inline requires): the
-- Countdown facing is FirstPersonController.faceOpponent (a level look ahead in first person, today's look from behind
-- otherwise); the forfeit dialog's two buttons are Modal only while it shows (the locked mouse comes free) and tell
-- FirstPersonController.setDialogOpen (the cursor shows); Backspace (DuelForfeit, keyboard) opens the confirmation, and
-- in first person on PC the Forfeit button shows that key.
-- Final polish (2026-10-11):
-- * The bottom dock also names the dash (C / B) and, in first person, the squeeze (F / X): a keycap and its caption
--   each, no bar (DuelFormat.hintKeys; mouse / gamepad only, as before: touch shows no key hints).
-- * "In the lane!" (duel.inLane, Palette.Danger, Config.UI.LaneCue; UI/LaneCue): while the opponent's lane ultimate's
--   telegraph runs (Dragon Rush, Sprinkle Roller: the UltimateEvent's own lane numbers) and the local body is inside its
--   lane, a warning under the duel bar, or under the banner that shows there; it pops in (not under ReducedMotion) and
--   hides at the release, the cancel, telegraphEndsAt, out of the lane and out of the duel.
-- Feature 1 (2026-10-11, the charge throw and the catch; design: the combat-effects page "Squishy Combat FP v2.html";
-- CatchController by inline requires: no new top-level local):
-- * The dock: throw, catch (its keycap "RMB/E" / "L1" and its cooldown bar, CatchController.state().progress: empty
--   while the hands crush), ultimate, dash, squeeze (design: html:96).
-- * The reticle: while charging, the pie fills clockwise to c in the toy's colour (Config.UI.Reticle
--   chargeFillTransparency) and pulses at full (DuelFormat.chargeLook; design: html:670-671); "Your hands are busy."
--   while they are open or crushing; "Catch! RMB/E" (the key for the input; "Catch!" on touch) pulsing in place of the
--   state text while an opponent's throw comes at you and the catch is ready (DuelFormat.catchPrompt; design: html:88,
--   673-674).
-- * "CAUGHT!" and "SQUISHED!" (design: html:352, 563): banners under the duel bar in the caught toy's colour for
--   bigWordSeconds, for both duelists, at CatchController.Caught / Burst (none over the "Dragon Rush incoming!" banner;
--   no "SQUISHED!" when the burst takes the thrower's last life: VfxController's "K.O.!" says it). The catcher's hit
--   marker and ui.hitConfirm at the burst (design: html:365), while the match is live.
-- FFA/TDM v1 (2026-10-15; the 12-player Free for All / Team Deathmatch, SPEC D13): this module still follows only the
-- duel view; MatchController draws the "match look" with this HUD's pieces (the reticle, "Hit!", the key dock without
-- the catch meter, the 3-2-1 countdown), handed over by one attachDuelHud call in init (no new top-level local: about
-- 180 of Luau's 200). The own hit marker also shows in a match (onHitConfirmed). Review fix: the match hides the top
-- bar with hideBar(h, "match", ...) (so a result card's layout never shows it again) and closes a 1v1 result card
-- left open from a duel just before (closeResult).
-- UI FINAL R3 (the window frame, plan work/ui/PLAN.md R3; `H:n` = "Squishy Duels HUD.dc.html" line n): the forfeit
-- dialog is a Theme.window (kind "duel": the DUEL pink band, H:126, with the duel sticker and Settings' small band, a
-- reading: the design has no forfeit dialog) of the kind's 600 px width (the nearest design window, H:426), shrunk
-- to fit with its chrome at the window's chrome scale like every window (Layout.windowFit, Theme.fitWindow); the
-- question is its band's title; its sticker flies in on every open (Theme.playSticker); placeDialog keeps what the
-- sticker hangs above it (Theme.fittedChrome) on the screen; its note on the pink body takes the window's text colour
-- (H:196).
-- AFFECTED 2026-10-15: a 1v1 dialog; the TDM / FFA leave flow comes later (work/tdmffa/PLAN.md).
-- UI FINAL R9 (plan R9 "Screens the design lacks", readings built from the kit): the result card is a Theme.window
-- (kind "duel") with the DUEL band (Strings.hud.duelCta) and its img.nav.duel sticker, the outcome title, its pop and
-- its lines on the pink body (the window's text colour, H:196), Rematch the green primary, Queue again the gold
-- (H:498), Close the band's 76 px X (it shows with the pinned row, after the return); the layout counts the band, what
-- hangs above it and the lip. The forfeit dialog's buttons take the design's kinds (CANCEL lilac, the green, 24 px,
-- H:462-463). AFFECTED 2026-10-15: 1v1 screens; the TDM / FFA results and leave flow come with work/tdmffa T6.

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local Button = require(Client.UI.Components.Button)
local Chip = require(Client.UI.Components.Chip)
local Confetti2D = require(Client.UI.Confetti2D)
local Create = require(Client.UI.Create)
local DuelFormat = require(Client.UI.DuelFormat)
local Focus = require(Client.UI.Focus)
local Keycap = require(Client.UI.Components.Keycap)
local LaneCue = require(Client.UI.LaneCue)
local Pips = require(Client.UI.Components.Pips)
local ProgressBar = require(Client.UI.Components.ProgressBar)
local QuestFormat = require(Client.UI.QuestFormat)
local SideIcon = require(Client.UI.Components.SideIcon)
local Theme = require(Client.UI.Theme)
local Waypoint = require(Client.UI.Waypoint)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local UIController = require(script.Parent.UIController)
local VfxController = require(script.Parent.VfxController)

-- Types

type Meter = {
	frame: Frame,
	keycap: Keycap.Keycap,
	key: string?, -- the key the keycap shows (nil = hidden)
	bar: ProgressBar.ProgressBar,
	ready: Chip.Chip?,
	readyScale: UIScale?,
	readySince: number?, -- os.clock() when READY appeared (its pop, then the pulse)
	drains: boolean, -- the ultimate meter drains when the charge is spent (§18.4.7)
	value: number?, -- the fill shown last frame
	drainFrom: number,
	drainTo: number?, -- the running drain's target (nil = none)
	drainStart: number,
}

-- A countdown bubble (§18.5.2 B6): two take turns, the current one and the one bursting. A foam disc whose outline
-- fades with it.
type Bubble = { frame: Frame, scale: UIScale, foam: Theme.Foam, stroke: UIStroke }

-- A result line that fades in and slides up (§18.5.2 B7); `fills` are the frames whose background fades with it (the
-- stats' inset).
type ResultLine = { texts: { TextLabel }, fills: { Frame }, slide: UIPadding }

type Side = {
	card: Frame,
	name: TextLabel,
	sideRow: Frame,
	side: TextLabel,
	icon: SideIcon.SideIcon,
	row: Frame, -- the lives row (on the compact layout it also holds the side icon and word)
	pips: Pips.Pips,
	lives: TextLabel,
	left: boolean, -- the opponent's card (left-aligned, beside the timer on its left edge)
	-- Foam fix 2 (cardNeed): the pips' count and the name's one-line width (base px) for the name and text size in
	-- nameKey.
	pipCount: number,
	nameKey: string?,
	nameWidth: number,
}

type Reticle = {
	root: Frame,
	ringScale: UIScale,
	pie: Frame,
	pieScale: UIScale, -- feature 1: the charge's pulse at full
	pieRight: UIGradient,
	pieLeft: UIGradient,
	dot: Frame,
	label: TextLabel,
	hit: TextLabel,
	hitScale: UIScale,
}

type Hud = {
	gui: ScreenGui,
	overlay: ScreenGui,
	top: Frame,
	timerPanel: Frame,
	timer: TextLabel,
	you: Side,
	opponent: Side,
	opponentColumn: Frame, -- the opponent's card and its "Dragon Rush ready" chip, as wide as the cards (foam fix 3)
	chip: Chip.Chip,
	chipScale: UIScale,
	forfeit: Button.Button,
	hints: Frame,
	throwMeter: Meter,
	catchMeter: Meter, -- feature 1 (2026-10-11): the catch key and its cooldown
	ultMeter: Meter,
	dashMeter: Meter, -- final polish 2026-10-11: the dash and squeeze keys (a keycap and caption, no bar)
	squeezeMeter: Meter,
	laneCue: TextLabel, -- final polish 2026-10-11: "In the lane!"
	laneCueScale: UIScale,
	lane: LaneCue.Lane?, -- the opponent's lane telegraph running now
	countdown: TextLabel,
	countdownScale: UIScale,
	countdownStroke: UIStroke,
	bubbles: { Bubble },
	arrow: Frame,
	reticle: Reticle,
	dialog: Frame,
	dialogTab: Frame,
	dialogNote: TextLabel,
	dialogConfirm: Button.Button,
	dialogCancel: Button.Button,
}

type ResultPanel = {
	frame: Frame,
	buttons: Frame,
	queueAgain: Button.Button,
	close: Button.Button,
	cleanup: Cleanup.Cleanup,
	afterReturn: boolean,
	rematch: Button.Button, -- Batch 3
	closeWithOffer: boolean, -- Batch 3: the auto-close came after a Rematch press; close when the offer ends
	rematchAsked: () -> boolean, -- Batch 3: either player pressed Rematch
}

-- Constants

local DUEL_ANIM = Config.Anim.duel
local DUEL_CONFIG = Config.Duel
local RULES = DUEL_CONFIG.Rules
local POSITIONING = DUEL_CONFIG.Positioning
local UI_CONFIG = Config.UI
local TOUCH = UI_CONFIG.Touch
local HIT = Config.Vfx.Hit
local DUEL_GUI = "SD_DuelHud"
local MODAL_GUI = "SD_Modal"
-- reading (not in the §11.1 table): the reticle / arrow overlay is full-bleed so its pixels are viewport pixels, and
-- draws with the duel HUD. It stays out of Config.UI.ScreenGuis on purpose: that table is exactly §11.1 (UIController
-- creates each entry at boot and Config.validate wants unique DisplayOrders), like SD_Touch, SD_PracticeReticle and
-- SD_Vfx, the other overlays their controllers own.
local RETICLE_GUI = "SD_DuelReticle"
local RETICLE_GUI_SPEC: UIController.ScreenGuiSpec = {
	displayOrder = UI_CONFIG.ScreenGuis[DUEL_GUI].displayOrder,
	insets = Enum.ScreenInsets.None,
}
local QUEUE_SCREEN = "queue"
local RESET_CALLBACK = "ResetButtonCallback"
local RESET_RETRY_SECONDS = 0.5 -- SetCore fails until the CoreGui registers the callback; try again this often
-- The duel screens' sizes and looks, kept in one table: this module is near Luau's 200-locals-per-function limit, and
-- one local per number pushed it over (Studio then refuses to load the whole client).
local LAYOUT = table.freeze({
	EDGE = 12,
	ARROW_PX = 36,
	ARROW_MARGIN_PX = 48,
	ARROW_BAR_PX = 8, -- the chevron's bars
	METER_WIDTH = 150,
	-- Foam UI (readings; the design has no duel screens yet): the meter's caption row and its bar this far apart, so
	-- the READY chip centred on the bar clears the caption; the READY chip's height.
	METER_ROW_GAP = 8,
	READY_CHIP_PX = 24,
	DIALOG_ANCHOR_Y = 0.5, -- the forfeit dialog's centre, as built (moved under the top bar when it reaches it)
	RESULT_WIDTH = 460,
	RESULT_SLIDE_PX = 40,
	RESULT_ANCHOR_Y = 0.55, -- before the first layout pass (DuelFormat.resultLayout takes over)
	SCROLLBAR_PX = 6, -- the result lines' scroll bar (as the Quests body)
	-- Foam fix 2 (readings): the longest the result card waits for the eliminator's "K.O.!" banner (1.2 s after a
	-- 0.1 s hold); a finished quest's mark on the card (a Mint disc with an InkUI check of two bars, as the Quests
	-- screen's).
	RESULT_WAIT_MAX = 1.5,
	QUEST_CHECK_PX = 18,
	QUEST_CHECK_BAR_PX = 3,
	SIDE_WIDTH = 220, -- a side's card in the top bar, its padding included
	-- Foam UI (readings): the side card's rows SIDE_ROW_GAP apart (foam fix 2: 6, so the pips' outlines never touch
	-- the side icon above them; it was 2), its side icon and life pips; the timer pill's smallest width (wider than
	-- "0:00" at the default text size, so a changing digit never moves the cards beside it).
	SIDE_ROW_GAP = 6,
	SIDE_ICON_PX = 22,
	-- Overlays fix (reading): layout passes (frames) the compact cards wait before measuring their rows again.
	SIDE_SETTLE_PASSES = 2,
	PIP_PX = 20,
	TIMER_MIN_WIDTH = 96,
	-- Foam UI (reading: the kit's outlined-text rule is 2 px at 18-30 px; the 96 px countdown keeps the design's ratio
	-- of an outline to its numeral): the digits' and "Throw!"'s InkUI outline. The bubble's bevel shade: its face this
	-- far towards InkUI (as Chip:setColor's shade).
	COUNTDOWN_OUTLINE_PX = 5,
	BUBBLE_SHADE_MIX = 0.15,
	RETICLE_PX = 40,
	RETICLE_LABEL_WIDTH = 220,
	DOT_PX = 6,
	RING_STROKE_PX = 3,
	-- reading: the cooldown arc is a soft white pie inside the ring (§5.10 "ring fill from nextThrowAt").
	PIE_TRANSPARENCY = 0.55,
	PIE_EDGE = 0.5, -- the gradient mask's hard edge (first half opaque, second half clear)
	READY_PULSE_SCALE = 0.08, -- reading: §11.6 gives the 0.9 s period of the READY pulse, not its size
})
local COUNTDOWN_BOX = Vector2.new(320, 150)
local ROOT_PART = "HumanoidRootPart"
local ARROW_PHASES: { [string]: boolean } = { Countdown = true, Active = true, SuddenDeath = true }
-- Dragon Rush refusals (ult.noRoom, ult.notReady, ...) arrive as Notify to the caster (§5.9, AbilityService); they
-- become toasts here, in duels and on the practice range (the same text from a later NotifyController is de-duplicated
-- by UIController).
local ULT_NOTIFY_AREA = "ult."
local TOAST_KINDS: { [string]: boolean } = { info = true, success = true, warn = true, error = true }
local POSE_LAYER = "duelEnd"
local POSE_BLEND_SECONDS = Config.Anim.joints.duelEndBlendMs / 1000
-- The dark duel transition colour #2B2440 (§9.12, §9.14).
local FADE_COLOR: Color3 = Palette.DuelFade
-- Feel pass (§18.4.2, §18.5.2 B6-B8, §18.6).
local AUDIO = Config.Audio
local MOTION = UI_CONFIG.motion
local BUBBLE = DUEL_ANIM.countdownBubble
local RESULT = DUEL_ANIM.result
local COUNTDOWN_POSITION = UDim2.fromScale(0.5, 0.4)
local DRAIN_EPSILON = 1e-4 -- a charge drop smaller than this is not a drain
local SOUND_GO = "duel.go"
local SOUND_HIT_CONFIRM = "ui.hitConfirm"
local SOUND_POP = "sfx.pop"
local SOUND_COIN = "ui.coin"
-- The loss tip's buttons (§6.13).
local PRACTICE_WAYPOINT = "practice"
local SETTINGS_REMOTE = "SetSettings"
local QUESTS_FIELD = "quests"
local TIP_WAY_CHECK_SECONDS = 0.5 -- reading: how often the tip's waypoint checks whether the range was reached

-- Module table

local DuelController = {}

-- Private

local log = Log.new("Duel")
local cleanup: Cleanup.Cleanup? = nil
local matchCleanup: Cleanup.Cleanup? = nil
local poseCleanup: Cleanup.Cleanup? = nil
local hud: Hud? = nil
local resultPanel: ResultPanel? = nil
local resetBindable: BindableEvent? = nil
local resetToken = 0
local countdownEndsAt: number? = nil
local countdownText: string? = nil
local telegraphUntil: number? = nil
local incomingBanner: UIController.BannerHandle? = nil
local dialogPop: (() -> ())? = nil
local dialogFocus: Focus.Token? = nil
local faded = false
local fadeSafety: thread? = nil
local hitClock = -math.huge -- os.clock() of the last own hit
local hitTiltSign = 1 -- "Hit!" tilts the other way on each hit
local countdownCue: DuelFormat.CountdownCue? = nil -- the countdown text on screen (or "Throw!" fading out)
local countdownStart = -math.huge -- os.clock() when it appeared
local bubbleIndex = 1 -- the bubble behind the current digit
local burstIndex: number? = nil -- the bubble bursting, if any
local burstStart = -math.huge
local ultFull = false -- the own ultimate is ready (sfx.pop once per charge)
local tipWay: Waypoint.Handle? = nil -- the loss tip's "Show me the way" waypoint
local tipWayCheck: thread? = nil
-- Overlays fix: the side cards' layout (nil until the first layout pass), what the wider card needs (base px; foam fix
-- 2: from the texts, DuelFormat.sideNeed, so it holds still through the match), why the top bar hides ("dialog",
-- "result": a panel that cannot fit under it) and the reticle state text last measured.
local sideCompact: boolean? = nil
local sideNeed = 0
local sideSettle = 0 -- layout passes to skip before measuring (a moved or retexted label is laid out a frame later)
local barHidden: { [string]: boolean? } = {}
-- Review fix: the top bar's bottom (actual px) as last drawn, kept while barHidden hides it (barBottomIn).
local barBottomPx: number? = nil
local stateText: string? = nil
local stateTextWidth = 0
local resultWait: thread? = nil -- foam fix 2: the result card waiting for the "K.O.!" banner to go

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function clearTipWay()
	local check = tipWayCheck
	tipWayCheck = nil
	if check and check ~= coroutine.running() then
		task.cancel(check)
	end
	local handle = tipWay
	tipWay = nil
	if handle then
		handle:destroy()
	end
end

-- The loss tip's "Show me the way" (§6.13): a client-only waypoint to the practice range, removed once the local
-- character reaches it (Waypoint's hide distance) or the next match begins.
local function showTipWay()
	clearTipWay()
	local target = WorldLayout.waypoint(PRACTICE_WAYPOINT)
	if target == nil then
		return
	end
	tipWay = Waypoint.show(target)
	tipWayCheck = task.spawn(function()
		while tipWay do
			task.wait(TIP_WAY_CHECK_SECONDS)
			local player = Players.LocalPlayer
			local character = if player then player.Character else nil
			local root = if character then character:FindFirstChild(ROOT_PART) else nil
			if root and root:IsA("BasePart") and Waypoint.shouldHide(root.Position, target) then
				clearTipWay()
				return
			end
		end
	end)
end

local function fadeSeconds(): number
	local seconds = POSITIONING.ReturnFadeSeconds
	return if type(seconds) == "number" and seconds > 0 then seconds else DUEL_ANIM.fadeMs / 1000
end

-- The side's own colour (pips, the edge arrow); its light colour is the card's face (applySides).
local function sideColor(side: string): Color3
	local color = DuelFormat.sideColors(side)
	return color
end

-- The foam colours of a countdown bubble: its digit's colour (DuelFormat.countdownCue) as the face, with the kit's
-- white top highlight, the face shaded towards InkUI as the bevel and the InkUI drop.
local function bubbleColors(face: Color3): Theme.FoamColors
	return {
		face = face,
		top = face:Lerp(Theme.Colors.white, Theme.Foam.highlight),
		bevel = face:Lerp(Theme.Colors.inkUI, LAYOUT.BUBBLE_SHADE_MIX),
		drop = Theme.Colors.inkUI,
	}
end

local function toastKind(kind: unknown): UIController.ToastKind
	return if type(kind) == "string" and TOAST_KINDS[kind] then kind :: UIController.ToastKind else "info"
end

local function circle(parent: Instance)
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = parent })
end

-- The foam kit's outlined text (InkUI, round joins) on a text over the arena or a coloured face. UI FINAL R1: it is the
-- text's only outline (Theme's own goes), so the fades below that write this stroke reach the whole outline.
local function outline(text: GuiObject, px: number): UIStroke
	Theme.noOutline(text)
	local stroke = Theme.stroke(Theme.Colors.inkUI, px, text)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	return stroke
end

-- Writes a property only when it changes (the layout passes run every frame).
local function setIfChanged(object: any, property: string, value: any)
	if object[property] ~= value then
		object[property] = value
	end
end

-- Builders -----------------------------------------------------------------------------------------------------------

-- One side's card in the top bar (foam UI): a panel whose face applySides tints with the side's light colour (team
-- colour blocking), holding the name, the side row and the lives row, aligned towards the timer.
local function buildSide(parent: Instance, name: string, order: number, alignment: Enum.TextXAlignment): Side
	local card = Theme.panel({
		Name = name,
		LayoutOrder = order,
		Size = UDim2.fromOffset(LAYOUT.SIDE_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	}, Theme.Radius.tile, Theme.Padding.medium)
	local horizontal = if alignment == Enum.TextXAlignment.Left
		then Enum.HorizontalAlignment.Left
		else Enum.HorizontalAlignment.Right
	Theme.list(Enum.FillDirection.Vertical, LAYOUT.SIDE_ROW_GAP, card, horizontal)
	-- Overlays fix: one line, cut with "…" (a long display name wrapped and made the two cards uneven).
	local nameLabel = Theme.label({
		Name = "Name",
		LayoutOrder = 1,
		TextXAlignment = alignment,
		TextWrapped = false,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	}, "H2")
	local left = alignment == Enum.TextXAlignment.Left
	-- §7.8: the side is labelled with text and an icon (never colour alone); both icons sit next to the timer. The
	-- text wraps beside the icon at a large text size instead of leaving the card.
	local sideRow: Frame = Create("Frame", {
		Name = "SideRow",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = card,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, sideRow, horizontal)
	local icon = SideIcon.new({
		name = "SideIcon",
		side = if left then "B" else "A",
		sizePx = LAYOUT.SIDE_ICON_PX,
		layoutOrder = if left then 1 else 2,
		parent = sideRow,
	})
	local sideLabel = Theme.label({
		Name = "Side",
		LayoutOrder = if left then 2 else 1,
		TextXAlignment = alignment,
		Size = UDim2.new(1, -(LAYOUT.SIDE_ICON_PX + Theme.Padding.small), 0, 0),
		Parent = sideRow,
	}, "Small")
	local row: Frame = Create("Frame", {
		Name = "Lives",
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = card,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row, horizontal)
	local pips = Pips.new({
		name = "Pips",
		count = RULES.Lives,
		filled = RULES.Lives,
		color = Theme.Colors.sideA,
		sizePx = LAYOUT.PIP_PX,
		layoutOrder = if left then 1 else 2,
		parent = row,
	})
	local lives = Theme.label({
		Name = "Count",
		LayoutOrder = if left then 2 else 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = row,
	}, "Body", Enum.FontWeight.Bold)
	return {
		card = card,
		name = nameLabel,
		sideRow = sideRow,
		side = sideLabel,
		icon = icon,
		row = row,
		pips = pips,
		lives = lives,
		left = left,
		pipCount = RULES.Lives,
		nameKey = nil,
		nameWidth = 0,
	}
end

-- Overlays fix: a side card's rows for the layout class. Compact (phones): two rows, the name and the lives row, which
-- also takes the side word and icon (SideRow hides), from the card's outer edge to the timer "Mint side ◇ 3 lives
-- ●●●" / "●●● 3 lives ◇ Strawberry side", wrapping inside the card at a large text size. Regular: the three rows as
-- built (SideRow under the name, its word wrapping beside the icon).
local function arrangeSide(side: Side, compact: boolean)
	local left = side.left
	local label, icon, row = side.side, side.icon.root, side.row
	if compact then
		icon.Parent = row
		label.Parent = row
		label.Size = UDim2.fromOffset(0, 0)
		label.AutomaticSize = Enum.AutomaticSize.XY
		label.TextWrapped = false
		side.pips.root.LayoutOrder = if left then 1 else 4
		side.lives.LayoutOrder = if left then 2 else 3
		icon.LayoutOrder = if left then 3 else 2
		label.LayoutOrder = if left then 4 else 1
		row.Size = UDim2.fromScale(1, 0)
		row.AutomaticSize = Enum.AutomaticSize.Y
	else
		icon.Parent = side.sideRow
		label.Parent = side.sideRow
		label.Size = UDim2.new(1, -(LAYOUT.SIDE_ICON_PX + Theme.Padding.small), 0, 0)
		label.AutomaticSize = Enum.AutomaticSize.Y
		label.TextWrapped = true
		side.pips.root.LayoutOrder = if left then 1 else 2
		side.lives.LayoutOrder = if left then 2 else 1
		icon.LayoutOrder = if left then 1 else 2
		label.LayoutOrder = if left then 2 else 1
		row.Size = UDim2.fromOffset(0, 0)
		row.AutomaticSize = Enum.AutomaticSize.XY
	end
	side.sideRow.Visible = not compact
	local list = row:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Wraps = compact
	end
end

-- Foam fix 2: the width (base px) a side card needs on either layout (DuelFormat.sideNeed), from its content at rest:
-- the name's one-line width (the H2 display kind measures without yielding; again only when the name or the text size
-- changes), the side word and "N lives" as laid out (both size to their text), the pips' resting row (Pips.rowWidth: a
-- lost pip's pop never widens the cards) and the icon. Replaces the overlays fix's measure of the drawn row.
local function cardNeed(side: Side, compact: boolean, scale: number): number
	local name = side.name.Text
	local key = name .. "\0" .. Theme.textSize("H2")
	if side.nameKey ~= key then
		side.nameKey = key
		side.nameWidth = Theme.textWidth(name, "H2")
	end
	return DuelFormat.sideNeed({
		compact = compact,
		name = side.nameWidth,
		word = side.side.AbsoluteSize.X / scale,
		lives = side.lives.AbsoluteSize.X / scale,
		pips = Pips.rowWidth(side.pipCount, LAYOUT.PIP_PX),
		icon = LAYOUT.SIDE_ICON_PX,
		gap = Theme.Padding.small,
		padding = Theme.Padding.medium,
	})
end

-- A meter of the bottom dock (the throw cooldown, the ultimate meter; foam UI): the keycap of its key for the active
-- input (updateHints, DuelFormat.hintKeys) beside its caption, over a ProgressBar in `accent`. The ultimate's also has
-- READY, a raised Frosting chip centred on its bar, so it appearing never moves the dock.
local function buildMeter(
	parent: Instance,
	name: string,
	order: number,
	caption: string,
	accent: Theme.AccentName,
	withReady: boolean,
	c: Cleanup.Cleanup
): Meter
	local frame: Frame = Create("Frame", {
		Name = name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(LAYOUT.METER_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Vertical, LAYOUT.METER_ROW_GAP, frame)
	local captionRow: Frame = Create("Frame", {
		Name = "Caption",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, captionRow)
	local keycap = c:add(Keycap.new({ name = "Key", layoutOrder = 1, parent = captionRow }))
	Theme.label({
		Name = "Text",
		LayoutOrder = 2,
		Text = caption,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = captionRow,
	}, "Chip")
	local bar = c:add(ProgressBar.new({ name = "Bar", fraction = 1, accent = accent, layoutOrder = 2, parent = frame }))
	-- The meter with READY is the ultimate's: it also drains (§18.4.7).
	local meter: Meter = {
		frame = frame,
		keycap = keycap,
		key = nil,
		bar = bar,
		drains = withReady,
		value = nil,
		drainFrom = 0,
		drainTo = nil,
		drainStart = -math.huge,
	}
	if withReady then
		local ready = c:add(Chip.new({
			name = "Ready",
			text = Strings.duel.ultReady,
			raised = true,
			heightPx = LAYOUT.READY_CHIP_PX,
			parent = bar.root,
		}))
		ready.root.AnchorPoint = Vector2.new(0.5, 0.5)
		ready.root.Position = UDim2.fromScale(0.5, 0.5)
		ready.root.ZIndex = 2 -- over the bar's fill
		ready.root.Visible = false
		meter.ready = ready
		meter.readyScale = Create("UIScale", { Name = "Pop", Parent = ready.root })
	end
	return meter
end

-- One half of the cooldown pie: a clipped half-width window onto a full disc whose UIGradient mask is opaque on its
-- first half; rotating the mask reveals the disc clockwise (DuelFormat.pieRotations).
local function buildPieHalf(parent: Instance, name: string, rightSide: boolean): UIGradient
	local half: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromScale(if rightSide then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		Parent = parent,
	})
	local disc: Frame = Create("Frame", {
		Name = "Disc",
		BackgroundColor3 = Theme.Colors.white,
		BackgroundTransparency = LAYOUT.PIE_TRANSPARENCY,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(if rightSide then -1 else 0, 0),
		Size = UDim2.fromScale(2, 1),
		Parent = half,
	})
	circle(disc)
	return Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(LAYOUT.PIE_EDGE, 0),
			NumberSequenceKeypoint.new(LAYOUT.PIE_EDGE + 0.001, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = 0,
		Parent = disc,
	})
end

local function buildReticle(parent: Instance, c: Cleanup.Cleanup): Reticle
	local root: Frame = Create("Frame", {
		Name = "Reticle",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(LAYOUT.RETICLE_PX, LAYOUT.RETICLE_PX),
		Active = false,
		Visible = false,
		Parent = parent,
	})
	c:add(root)
	UIController.trackScale(Create("UIScale", { Parent = root }))

	local pie: Frame = Create("Frame", {
		Name = "Cooldown",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})
	local pieRight = buildPieHalf(pie, "Right", true)
	local pieLeft = buildPieHalf(pie, "Left", false)
	local pieScale: UIScale = Create("UIScale", { Name = "Charge", Parent = pie })

	local ring: Frame = Create("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	circle(ring)
	Theme.stroke(Theme.Colors.white, LAYOUT.RING_STROKE_PX, ring)
	local inner: Frame = Create("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -LAYOUT.RING_STROKE_PX * 2, 1, -LAYOUT.RING_STROKE_PX * 2),
		Parent = ring,
	})
	circle(inner)
	Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.thin, inner)
	local ringScale: UIScale = Create("UIScale", { Parent = ring })

	local dot: Frame = Create("Frame", {
		Name = "Dot",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(LAYOUT.DOT_PX, LAYOUT.DOT_PX),
		BackgroundColor3 = Theme.Colors.white,
		BorderSizePixel = 0,
		Parent = root,
	})
	circle(dot)
	Theme.stroke(Theme.Colors.inkUI, 1, dot)

	local label = Theme.label({
		Name = "State",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 1, Theme.Padding.small),
		Size = UDim2.fromOffset(LAYOUT.RETICLE_LABEL_WIDTH, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	}, "Chip", nil, Theme.Colors.white)
	-- Foam fix 2: the thin outline on this small text (the 2 px one closed the gaps between its words).
	outline(label, Theme.Stroke.thin)
	local hit = Theme.label({
		Name = "Hit",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -Theme.Padding.small),
		Size = UDim2.fromOffset(LAYOUT.RETICLE_LABEL_WIDTH, 0),
		Text = Strings.combat.hit,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = root,
	}, "H2", nil, Theme.Colors.lemon)
	outline(hit, Theme.Stroke.text)
	local hitScale: UIScale = Create("UIScale", { Name = "Pop", Parent = hit })

	return {
		root = root,
		ringScale = ringScale,
		pie = pie,
		pieScale = pieScale,
		pieRight = pieRight,
		pieLeft = pieLeft,
		dot = dot,
		label = label,
		hit = hit,
		hitScale = hitScale,
	}
end

local function buildArrow(parent: Instance, c: Cleanup.Cleanup): Frame
	local arrow: Frame = Create("Frame", {
		Name = "OpponentArrow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(LAYOUT.ARROW_PX, LAYOUT.ARROW_PX),
		Visible = false,
		Parent = parent,
	})
	c:add(arrow)
	UIController.trackScale(Create("UIScale", { Parent = arrow }))
	-- A ">" chevron (two rounded bars), pointing right at Rotation 0, outlined in InkUI like the foam bars.
	for i, angle in { 40, -40 } do
		local bar: Frame = Create("Frame", {
			Name = "Bar" .. i,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.85, 0.5),
			Size = UDim2.new(0.62, 0, 0, LAYOUT.ARROW_BAR_PX),
			Rotation = angle,
			BackgroundColor3 = Theme.Colors.sideA,
			BorderSizePixel = 0,
			Parent = arrow,
		})
		Theme.corner(LAYOUT.ARROW_BAR_PX / 2, bar)
		Theme.stroke(Theme.Colors.inkUI, Theme.Stroke.bar, bar)
	end
	return arrow
end

-- Overlays fix: the top bar hides while a panel that cannot fit under it shows (`reason`: "dialog", "result").
local function hideBar(h: Hud, reason: string, hidden: boolean)
	barHidden[reason] = if hidden then true else nil
	setIfChanged(h.top, "Visible", next(barHidden) == nil)
end

-- The top bar's bottom in `gui`'s base px while the duel HUD shows (nil otherwise). Both guis use CoreUISafeInsets and
-- the same UI scale; each box is read from its own gui's origin. Review fix: measured while the bar shows and
-- remembered while barHidden hides it (the hidden bar's automatic size may not be laid out; a bottom read from it could
-- show the bar again, which then hides again, every frame).
local function barBottomIn(h: Hud, gui: LayerCollector, scale: number): number?
	if not h.gui.Enabled or not (scale > 0) then
		return nil
	end
	if h.top.Visible and h.top.AbsoluteSize.Y > 0 then
		barBottomPx = h.top.AbsolutePosition.Y + h.top.AbsoluteSize.Y
	end
	local bottom = barBottomPx
	if bottom == nil then
		return nil
	end
	return (bottom - gui.AbsolutePosition.Y) / scale
end

-- Overlays fix: the forfeit dialog centred as built, or under the top bar when it would cut into it
-- (DuelFormat.panelBelowBar; its header tab's upper half hangs above its box); the bar hides when it cannot fit.
local function placeDialog(h: Hud)
	local scale = UIController.scale()
	local gui = UIController.screenGui(MODAL_GUI)
	local screen = gui.AbsoluteSize
	if not (scale > 0) or screen.Y <= 0 or h.dialog.AbsoluteSize.Y <= 0 then
		return
	end
	local centre, clears = DuelFormat.panelBelowBar(
		screen.Y / scale,
		barBottomIn(h, gui, scale),
		h.dialog.AbsoluteSize.Y / scale,
		Theme.fittedChrome(h.dialog).above, -- UI FINAL R3: its sticker (and the X's room) above it
		LAYOUT.DIALOG_ANCHOR_Y
	)
	setIfChanged(h.dialog, "Position", UDim2.new(0.5, 0, 0, math.floor(centre + 0.5)))
	hideBar(h, "dialog", not clears)
end

local function closeDialog()
	local h = hud
	if h == nil or not h.dialog.Visible then
		return
	end
	h.dialog.Visible = false
	-- First person: Modal only while the dialog shows, so it never frees the locked mouse otherwise.
	h.dialogCancel.root.Modal = false
	h.dialogConfirm.root.Modal = false
	require(script.Parent.FirstPersonController).setDialogOpen(false)
	hideBar(h, "dialog", false)
	if dialogPop then
		dialogPop()
		dialogPop = nil
	end
	if dialogFocus then
		Focus.restore(dialogFocus)
		dialogFocus = nil
	end
end

local function refreshDialogNote(h: Hud, view: StateController.DuelView)
	h.dialogNote.Text = DuelFormat.forfeitNote(view.phase, view.phaseEndsAt, serverNow(), view.rules) or ""
end

local function openDialog()
	local h = hud
	local view = StateController.duel()
	if h == nil or view == nil or not DuelFormat.forfeitAllowed(view.phase) or h.dialog.Visible then
		return
	end
	refreshDialogNote(h, view)
	dialogFocus = Focus.capture()
	h.dialog.Visible = true
	-- First person: the two buttons free the locked mouse while the dialog shows (and the cursor comes back).
	h.dialogCancel.root.Modal = true
	h.dialogConfirm.root.Modal = true
	require(script.Parent.FirstPersonController).setDialogOpen(true)
	placeDialog(h) -- again every frame while it shows (updateFrame), once its size is known
	Theme.playSticker(h.dialog) -- UI FINAL R3: sdStick on every open (H:251)
	dialogPop = UIController.pushBack(closeDialog)
	Focus.select(h.dialogCancel.root)
end

-- Part 8 (reading): the dialog lives in SD_Modal (DisplayOrder 20), not SD_DuelHud (11). On a phone the touch
-- Ultimate button (SD_Touch, 12) sat over the right half of the dialog and took the taps meant for Forfeit; above it,
-- and Active (so a tap on its background never reaches a touch button under it), both buttons are always reachable.
-- It is still not a modal (duels never call ControlsController.block, §11.7); Back / ButtonB still close it.
-- Foam UI: the question is the panel's header tab (Theme.headerTab; UI FINAL R3: the window's band); the note and the
-- buttons sit in Body, since a panel with a header tab holds no UIListLayout itself.
local function buildDialog(gui: ScreenGui, c: Cleanup.Cleanup): (Frame, Frame, TextLabel, Button.Button, Button.Button)
	local dialog = Theme.window({
		Name = "ForfeitDialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, LAYOUT.DIALOG_ANCHOR_Y),
		Size = UDim2.fromOffset(Config.UI.Sticker.window.kinds.duel.width, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Active = true,
		Visible = false,
		Parent = gui,
	}, "duel", Theme.Padding.large)
	c:add(dialog)
	Focus.prepareGroup(dialog)
	local tab = Theme.headerTab(dialog, Strings.duel.forfeitConfirm)
	-- UI FINAL R3: the kind's width and chrome scale for this screen (Layout.windowFit), again when the screen changes
	-- (not in the every-frame placeDialog: fitWindow measures text).
	local Layout = require(Client.UI.Layout)
	local function fitDialog()
		local fit = Layout.windowFit(gui.AbsoluteSize, "duel")
		dialog.Size = UDim2.fromOffset(fit.width, 0)
		Theme.fitWindow(dialog, fit.k)
	end
	fitDialog()
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitDialog))
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = dialog,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.medium, body)
	local note = Theme.label({
		Name = "Note",
		LayoutOrder = 1,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = body,
	}, "Body")
	Theme.textOnWindow(note) -- UI FINAL R3: on the pink body (H:196)
	local row: Frame = Create("Frame", {
		Name = "Buttons",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	-- Wraps: at the largest text the two buttons go on two lines instead of out of the dialog.
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, row).Wraps = true
	local cancel = Button.new({
		name = "Duel_ForfeitCancelButton",
		text = Strings.duel.forfeitNo,
		kind = "cancel", -- UI FINAL R9: CANCEL's lilac (H:462)
		textRole = "button", -- H:462: 24 px, stroke 5
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = row,
		onActivated = closeDialog,
	})
	c:add(cancel)
	local confirm = Button.new({
		name = "Duel_ForfeitConfirmButton",
		text = Strings.duel.forfeitYes,
		kind = "primary",
		textRole = "button", -- UI FINAL R9: H:463's green, 24 px
		height = TOUCH.primaryButton,
		layoutOrder = 2,
		parent = row,
		onActivated = function()
			closeDialog()
			NetController.duelForfeit()
		end,
	})
	c:add(confirm)
	return dialog, tab, note, confirm, cancel
end

local function buildHud(c: Cleanup.Cleanup): Hud
	local gui = UIController.screenGui(DUEL_GUI)
	gui.Enabled = false
	local overlay = UIController.screenGui(RETICLE_GUI, RETICLE_GUI_SPEC)
	overlay.Enabled = false

	-- Top centre; layoutTopBar moves it clear of the Forfeit button on narrow screens (DuelFormat.topBarPlacement).
	-- Stable name: VfxController keeps its "K.O.!" banner under SD_DuelHud.TopBar.
	local top: Frame = Create("Frame", {
		Name = "TopBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, LAYOUT.EDGE),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = gui,
	})
	c:add(top)
	-- Integration (foam UI): the side cards made the bar about 102-135 base px tall, so the duel toasts start under it
	-- instead of at the fixed 110 (they covered the lives row on a phone at a large text size).
	UIController.toastsBelow("duel", top)
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, top, nil, Enum.VerticalAlignment.Top)
	local you = buildSide(top, "You", 1, Enum.TextXAlignment.Right)
	-- The timer pill: at least TIMER_MIN_WIDTH wide, its digits centred (a list), so "1:59" -> "1:58" moves nothing.
	local timerPanel = Theme.panel({
		Name = "Timer",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(LAYOUT.TIMER_MIN_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Parent = top,
	}, Theme.Radius.pill, Theme.Padding.medium)
	Theme.list(Enum.FillDirection.Horizontal, 0, timerPanel)
	local timer = Theme.label({
		Name = "Text",
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = timerPanel,
	}, "HudNumber")
	-- Foam fix 3: as wide as the cards (layoutTopBar sets both). With an automatic width it grew past the card on a PC
	-- once the card held the opponent's whole name (about 34 base at the 1.25 scale), and the centred bar's timer sat
	-- left of the screen's centre.
	local opponentColumn: Frame = Create("Frame", {
		Name = "OpponentColumn",
		LayoutOrder = 3,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(LAYOUT.SIDE_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = top,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, opponentColumn, Enum.HorizontalAlignment.Left)
	local opponent = buildSide(opponentColumn, "Opponent", 1, Enum.TextXAlignment.Left)
	-- The opponent's "Dragon Rush ready": a chip under their card (UI FINAL R1: the Ultimate's gold, H:234; the
	-- design's lilac is its disabled colour).
	local chip = c:add(Chip.new({ name = "UltReadyChip", text = "", accent = "ult", layoutOrder = 2 }))
	chip.root.Visible = false
	chip.root.Parent = opponentColumn
	local chipScale: UIScale = Create("UIScale", { Name = "Pop", Parent = chip.root })

	local forfeit = Button.new({
		name = "Duel_ForfeitButton",
		text = Strings.duel.forfeit,
		height = TOUCH.closeButton,
		keycap = "", -- Backspace in first person on PC (showForfeitKey)
		parent = gui,
		onActivated = openDialog,
	})
	c:add(forfeit)
	forfeit.root.Position = UDim2.fromOffset(LAYOUT.EDGE, LAYOUT.EDGE)
	-- First person (spec 2026-10-10 §3.1): the locked mouse cannot click the button on PC, so it shows its key and
	-- Backspace (DuelForfeit) opens the same confirmation; Backspace again closes it (ModalBack sinks it first).
	local FirstPersonController = require(script.Parent.FirstPersonController)
	local function showForfeitKey()
		local mouse = ControlsController.preferredInput() == Enum.PreferredInput.KeyboardAndMouse
		local firstPerson = FirstPersonController.mode() == "duel"
		forfeit:setKeycap(if mouse and firstPerson then Strings.controls.key.backKeyboard else nil)
	end
	c:add(FirstPersonController.Changed:connect(showForfeitKey))
	c:add(ControlsController.PreferredInputChanged:connect(showForfeitKey))
	c:add(ControlsController.bindAction("DuelForfeit", function(inputState: Enum.UserInputState): boolean
		if inputState ~= Enum.UserInputState.Begin then
			return false
		end
		openDialog()
		local h = hud
		return h ~= nil and h.dialog.Visible
	end))

	-- The bottom dock (mouse / gamepad): the throw meter and the ultimate meter side by side.
	local hints = Theme.panel({
		Name = "Hints",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -LAYOUT.EDGE),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Visible = false,
		Parent = gui,
	}, Theme.Radius.tile, Theme.Padding.medium)
	c:add(hints)
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.large, hints, nil, Enum.VerticalAlignment.Top)
	local throwMeter = buildMeter(hints, "ThrowMeter", 1, Strings.controls.throw, "sky", false, c)
	-- Feature 1 (2026-10-11): the catch and its cooldown bar after the throw (design: html:96).
	local catchMeter = buildMeter(hints, "CatchMeter", 2, Strings.controls.catch, "mint", false, c)
	local ultMeter = buildMeter(hints, "UltimateMeter", 3, Strings.controls.ultimate, "lilac", true, c)
	-- Final polish (2026-10-11): the dash and squeeze keys after them, each a keycap and its caption (no bar).
	local dashMeter = buildMeter(hints, "DashKey", 4, Strings.controls.dash, "sky", false, c)
	local squeezeMeter = buildMeter(hints, "SqueezeKey", 5, Strings.controls.squeeze, "mint", false, c)
	for _, meter in { dashMeter, squeezeMeter } do
		meter.bar.root.Visible = false
		meter.frame.Size = UDim2.fromOffset(0, 0)
		meter.frame.AutomaticSize = Enum.AutomaticSize.XY
	end
	-- Final polish (2026-10-11): "In the lane!" (updateLaneCue places it), in Danger with the InkUI outline.
	local laneCue = Theme.label({
		Name = "LaneCue",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Text = Strings.duel.inLane,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Visible = false,
		Parent = gui,
	}, "Title", nil, Palette.Danger)
	c:add(laneCue)
	outline(laneCue, Theme.Stroke.text)
	local laneCueScale: UIScale = Create("UIScale", { Name = "Pop", Parent = laneCue })

	-- The countdown bubbles (§18.5.2 B6): round foam discs, countdownBubble.px, behind the number (ZIndex 1 under its
	-- 2); startCue paints each in its digit's colour.
	local bubbles: { Bubble } = {}
	for i = 1, 2 do
		local bubble: Frame = Create("Frame", {
			Name = "CountdownBubble" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = COUNTDOWN_POSITION,
			Size = UDim2.fromOffset(BUBBLE.px, BUBBLE.px),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 1,
			Parent = gui,
		})
		c:add(bubble)
		local bands = Theme.Foam.cta
		local foam = Theme.foam(bubble, {
			radius = Theme.Radius.pill,
			stroke = Theme.Stroke.thick,
			top = bands.top,
			bevel = bands.bevel,
			drop = bands.drop,
			colors = bubbleColors(Theme.Colors.white),
			fixedHeight = BUBBLE.px,
		})
		table.insert(bubbles, {
			frame = bubble,
			scale = Create("UIScale", { Parent = bubble }),
			foam = foam,
			stroke = foam.stroke :: UIStroke,
		})
	end
	local countdown: TextLabel = Create("TextLabel", {
		Name = "Countdown",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = COUNTDOWN_POSITION,
		Size = UDim2.fromOffset(COUNTDOWN_BOX.X, COUNTDOWN_BOX.Y),
		Text = "",
		Visible = false,
		ZIndex = 2,
		Parent = gui,
	})
	c:add(countdown)
	Theme.text(countdown, "Countdown", nil, Theme.Colors.white)
	countdown.TextScaled = true
	Create("UITextSizeConstraint", { MaxTextSize = Theme.textSize("Countdown"), Parent = countdown })
	local countdownStroke = outline(countdown, LAYOUT.COUNTDOWN_OUTLINE_PX)
	local countdownScale: UIScale = Create("UIScale", { Parent = countdown })

	local dialog, dialogTab, dialogNote, dialogConfirm, dialogCancel = buildDialog(UIController.screenGui(MODAL_GUI), c)

	return {
		gui = gui,
		overlay = overlay,
		top = top,
		timerPanel = timerPanel,
		timer = timer,
		you = you,
		opponent = opponent,
		opponentColumn = opponentColumn,
		chip = chip,
		chipScale = chipScale,
		forfeit = forfeit,
		hints = hints,
		throwMeter = throwMeter,
		catchMeter = catchMeter,
		ultMeter = ultMeter,
		dashMeter = dashMeter,
		squeezeMeter = squeezeMeter,
		laneCue = laneCue,
		laneCueScale = laneCueScale,
		lane = nil,
		countdown = countdown,
		countdownScale = countdownScale,
		countdownStroke = countdownStroke,
		bubbles = bubbles,
		arrow = buildArrow(overlay, c),
		reticle = buildReticle(overlay, c),
		dialog = dialog,
		dialogTab = dialogTab,
		dialogNote = dialogNote,
		dialogConfirm = dialogConfirm,
		dialogCancel = dialogCancel,
	}
end

-- Reset intercept (§5.2) ---------------------------------------------------------------------------------------------

-- Sets the Reset callback (the bindable in a match, true = Roblox's default), retrying until CoreGui accepts it. A
-- newer call supersedes an older retry loop.
local function setResetCallback(inMatch: boolean)
	resetToken += 1
	local token = resetToken
	local value: any = if inMatch then resetBindable else true
	task.spawn(function()
		while token == resetToken do
			local ok = pcall(function()
				StarterGui:SetCore(RESET_CALLBACK, value)
			end)
			if ok then
				return
			end
			task.wait(RESET_RETRY_SECONDS)
		end
	end)
end

-- Result poses (§9.14) -----------------------------------------------------------------------------------------------

local function stopPoses()
	local pc = poseCleanup
	if pc then
		poseCleanup = nil
		pc:clean()
	end
end

-- Plays `pose` on `player`'s joint layer (rise, bounces for the cheer, hold); blended out by stopPoses().
local function playPose(pc: Cleanup.Cleanup, player: Player?, pose: string, bounces: number)
	if player == nil then
		return -- e.g. the Studio test dummy (not a Player)
	end
	local layer = CharacterAnimController.getLayer(player)
	if layer == nil then
		return
	end
	layer:setPose(POSE_LAYER, pose, 0)
	local started = os.clock()
	pc:add(Scheduler.add(function(): boolean
		if CharacterAnimController.getLayer(player) ~= layer or not layer:has(POSE_LAYER) then
			return false
		end
		local weight, done = DuelFormat.endPoseWeight(os.clock() - started, bounces)
		layer:setWeight(POSE_LAYER, weight)
		return not done
	end, "joint"))
	pc:add(function()
		if CharacterAnimController.getLayer(player) == layer and layer:has(POSE_LAYER) then
			layer:blendWeight(POSE_LAYER, 0, POSE_BLEND_SECONDS, true)
		end
	end)
end

local function startPoses(outcome: string, view: StateController.DuelView)
	stopPoses()
	local selfPose, opponentPose = DuelFormat.endPoses(outcome)
	if selfPose == nil and opponentPose == nil then
		return
	end
	local pc = Cleanup.new()
	poseCleanup = pc
	local bouncesFor = function(pose: string): number
		return if pose == "cheer" then DUEL_ANIM.cheerBounces else 0
	end
	if selfPose then
		playPose(pc, Players.LocalPlayer, selfPose, bouncesFor(selfPose))
	end
	if opponentPose then
		playPose(pc, Players:GetPlayerByUserId(view.opponent.userId), opponentPose, bouncesFor(opponentPose))
	end
end

-- Result panel -------------------------------------------------------------------------------------------------------

local function closeResult()
	local waiting = resultWait
	resultWait = nil
	if waiting and waiting ~= coroutine.running() then
		task.cancel(waiting)
	end
	local panel = resultPanel
	if panel then
		resultPanel = nil
		panel.cleanup:clean() -- also takes the reward label back from HudController.setGainSource
	end
end

-- A result line's texts, the opaque frames that fade with them (`fills`, e.g. the stats' inset) and its slide padding.
-- The slide moves the content down by `slide` with a matching negative bottom padding, so the line's height (and the
-- panel's) never changes while it slides (reading: a UIListLayout owns every line's Position).
local function resultLine(root: GuiObject, fills: { Frame }?): ResultLine
	local texts: { TextLabel } = {}
	if root:IsA("TextLabel") then
		table.insert(texts, root)
	end
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("TextLabel") then
			table.insert(texts, descendant)
		end
	end
	return { texts = texts, fills = fills or {}, slide = Create("UIPadding", { Name = "Slide", Parent = root }) }
end

local function applyLine(line: ResultLine, transparency: number, slide: number)
	for _, text in line.texts do
		text.TextTransparency = transparency
	end
	for _, fill in line.fills do
		fill.BackgroundTransparency = transparency
	end
	line.slide.PaddingTop = UDim.new(0, slide)
	line.slide.PaddingBottom = UDim.new(0, -slide)
end

local function updateQueueAgain(panel: ResultPanel)
	panel.queueAgain.root.Visible = StateController.queue().state == "Idle"
end

-- Shows Queue again / Close, answers Back, takes gamepad focus, and closes itself after autoCloseAfterReturnSeconds
-- (Batch 3: Rematch first, and once someone pressed it the close waits for the rematch offer to end).
local function resultAfterReturn(panel: ResultPanel)
	if panel.afterReturn then
		return
	end
	panel.afterReturn = true
	panel.buttons.Visible = true
	updateQueueAgain(panel)
	local token = Focus.capture()
	panel.cleanup:add(function()
		-- Only while the card still holds the focus: a modal opened over it since (Inspect by V / ButtonY within the
		-- 6 s) owns the focus now and gives it back itself (Part 6 review: the card's auto-close must not clear it).
		Focus.restoreWithin(token, panel.frame)
	end)
	panel.cleanup:add(UIController.pushBack(closeResult))
	-- Gamepad: Queue again, or Close while already queued (Queue again hides then), so a primary is always selected.
	Focus.follow(panel.frame, function(): GuiObject?
		if panel.rematch.root.Visible then
			return panel.rematch.root -- Batch 3: Rematch first while it is offered
		end
		return if panel.queueAgain.root.Visible then panel.queueAgain.root else panel.close.root
	end, panel.cleanup)
	panel.cleanup:add(StateController.QueueChanged:connect(function()
		updateQueueAgain(panel)
	end))
	panel.cleanup:add(task.delay(UI_CONFIG.Result.autoCloseAfterReturnSeconds, function()
		if resultPanel == panel and panel.rematch.root.Visible and panel.rematchAsked() then
			panel.closeWithOffer = true -- Batch 3: someone pressed Rematch: wait for the server to end the offer
		elseif resultPanel == panel then
			closeResult()
		end
	end))
end

-- Foam fix 2: a finished quest's line on the result card: the Mint check disc (the Quests screen's check of two InkUI
-- bars, on a disc so it reads on the Frosting card) beside the line in InkUI bold, centred like the other lines and
-- wrapping inside the card. Returns the row and the frames that fade with it.
local function questDoneLine(parent: Instance, order: number, text: string): (Frame, { Frame })
	local row: Frame = Create("Frame", {
		Name = "Line" .. order,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, row)
	local disc: Frame = Create("Frame", {
		Name = "Check",
		LayoutOrder = 1,
		BackgroundColor3 = Theme.Colors.mint,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(LAYOUT.QUEST_CHECK_PX, LAYOUT.QUEST_CHECK_PX),
		Parent = row,
	})
	circle(disc)
	local fills = { disc }
	for _, bar in { { 0.36, 0.58, 0.32, 45 }, { 0.58, 0.49, 0.56, -50 } } do
		table.insert(
			fills,
			Create("Frame", {
				Name = "Bar",
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(bar[1], bar[2]),
				Size = UDim2.fromOffset(LAYOUT.QUEST_CHECK_PX * bar[3], LAYOUT.QUEST_CHECK_BAR_PX),
				Rotation = bar[4],
				BackgroundColor3 = Theme.Colors.inkUI,
				BorderSizePixel = 0,
				Parent = disc,
			})
		)
	end
	local label = Theme.label({
		Name = "Text",
		LayoutOrder = 2,
		Text = text,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = row,
	}, "Small", Enum.FontWeight.Bold)
	-- The card's lines are RESULT_WIDTH less its paddings and the scroll bar; the text wraps beside the disc in that.
	Create("UISizeConstraint", {
		MaxSize = Vector2.new(
			LAYOUT.RESULT_WIDTH
				- 2 * Theme.Padding.large
				- LAYOUT.SCROLLBAR_PX
				- LAYOUT.QUEST_CHECK_PX
				- Theme.Padding.small,
			math.huge
		),
		Parent = label,
	})
	return row, fills
end

-- Builds and shows the result card for `model` (showResult; after the "K.O.!" banner when there is one). Batch 3:
-- `opponent` (a real player) may be offered a rematch.
local function openResult(model: DuelFormat.ResultModel, opponent: { userId: number, name: string }?)
	local style = DuelFormat.resultStyle(model.outcome)
	local reduced = Tweens.reducedMotion()

	local panelCleanup = Cleanup.new()
	local modalGui = UIController.screenGui(MODAL_GUI)
	local frame = Theme.window({
		Name = "DuelResult",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, LAYOUT.RESULT_ANCHOR_Y, if reduced then 0 else LAYOUT.RESULT_SLIDE_PX),
		Size = UDim2.fromOffset(LAYOUT.RESULT_WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = modalGui,
	}, "duel", Theme.Padding.large)
	panelCleanup:add(frame)
	Focus.prepareGroup(frame)
	-- UI FINAL R9: the DUEL band and its sticker (H:126-130's pink), at the kind's chrome scale for this screen.
	Theme.headerTab(frame, Strings.hud.duelCta)
	Theme.fitWindow(frame, require(Client.UI.Layout).windowFit(modalGui.AbsoluteSize, "duel").k)
	Theme.playSticker(frame)
	-- Part 8 (DuelFormat.resultLayout): Stack holds the title (pinned on top, so its pop is never clipped by the
	-- scroll), the lines in Content inside the Body scroll, and the Queue again / Close row pinned under it, so on a
	-- phone at the largest text the lines scroll while the title and the buttons stay in view. The confetti layer
	-- covers the panel above them, outside the lists (§18.5.2 B7: "parented to the panel, not full-screen"; a
	-- scale-sized child adds nothing to the panel's height).
	local stack: Frame = Create("Frame", {
		Name = "Stack",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, stack)
	local body: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Body",
		LayoutOrder = 1,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = LAYOUT.SCROLLBAR_PX,
		ScrollBarImageColor3 = Theme.Colors.inkUI,
		Parent = stack,
	})
	Create("UIPadding", { PaddingRight = UDim.new(0, LAYOUT.SCROLLBAR_PX), Parent = body })
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = body,
	})
	Theme.list(Enum.FillDirection.Vertical, Theme.Padding.small, content)
	local confettiLayer: Frame = Create("Frame", {
		Name = "Confetti",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 2,
		Parent = frame,
	})

	-- §18.5.2 B7: VICTORY Lemon, DEFEAT Lavender, DRAW Sky, each with a 3 px outline (InkUI since the foam restyle;
	-- cancelled / void stay InkUI text with no outline).
	local title = Theme.label({
		Name = "Title",
		LayoutOrder = 0,
		Text = model.title,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = stack,
	}, "Title", nil, style.color)
	if style.color then
		outline(title, Theme.Stroke.thick)
	end
	local titleScale: UIScale = Create("UIScale", { Parent = title })

	local lines: { ResultLine } = {}
	local order = 1
	local function addLine(text: string, kind: Theme.TextKind, color: Color3?): (TextLabel, number)
		order += 1
		local label = Theme.label({
			Name = "Line" .. order,
			LayoutOrder = order,
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = content,
		}, kind, nil, color)
		if color == nil then
			Theme.textOnWindow(label) -- UI FINAL R9: on the pink body (H:196)
		end
		table.insert(lines, resultLine(label))
		return label, #lines
	end
	if model.reason then
		addLine(model.reason, "Body")
	end
	if #model.stats > 0 then
		-- Foam UI: the stats sit in a Biscuit inset (Box), which fades in with them; Stats (transparent) is the line
		-- that slides, since the inset's own UIPadding is its padding.
		order += 1
		local row: Frame = Create("Frame", {
			Name = "Stats",
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = content,
		})
		local box = Theme.inset({
			Name = "Box",
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = row,
		}, Theme.Radius.button, Theme.Padding.medium)
		Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.large, box)
		for i, stat in model.stats do
			local cell: Frame = Create("Frame", {
				Name = "Stat" .. i,
				LayoutOrder = i,
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Parent = box,
			})
			Theme.list(Enum.FillDirection.Vertical, 0, cell)
			Theme.label({
				Name = "Value",
				LayoutOrder = 1,
				Text = stat.value,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Parent = cell,
			}, "HudNumber")
			Theme.label({
				Name = "Label",
				LayoutOrder = 2,
				Text = stat.label,
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				Parent = cell,
			}, "Small")
		end
		table.insert(lines, resultLine(row, { box }))
	end
	-- The paid reward counts up from "+0" (§18.5.2 B7); a blocked line ("0 Coins: why") is shown as it is.
	local rewardCoins = model.rewardCoins
	local rewardLabel: TextLabel? = nil
	local rewardIndex = 0
	local rewardScale: UIScale? = nil
	if model.reward then
		local startText = if rewardCoins then DuelFormat.rewardText(model.outcome, 0) else nil
		local label, index = addLine(startText or model.reward, "H2")
		if rewardCoins then
			rewardLabel, rewardIndex = label, index
			rewardScale = Create("UIScale", { Name = "Pulse", Parent = label })
			-- After Returning, the held duel Coins fly from this label into the pill (HudController owns the flight).
			HudController.setGainSource(label)
			panelCleanup:add(function()
				HudController.setGainSource(nil)
			end)
		end
	end
	-- Captions under the reward: Ink2 on the Frosting panel (5.6:1).
	if model.rewardNote then
		addLine(model.rewardNote, "Small", Theme.Colors.ink2)
	end
	for index, quest in model.quests do
		if model.questDone[index] then
			-- Foam fix 2: a quest this duel finished is marked (its "Quest complete!" toast waits for the lobby).
			order += 1
			local row, fills = questDoneLine(content, order, quest)
			table.insert(lines, resultLine(row, fills))
		else
			addLine(quest, "Small", Theme.Colors.ink2)
		end
	end
	if model.tip then
		-- §6.13: the tip and its three buttons (Show me the way / Got it / Don't show tips) under it.
		local tipLabel = addLine(model.tip, "Body")
		order += 1
		local tipRow: Frame = Create("Frame", {
			Name = "TipButtons",
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = content,
		})
		Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, tipRow).Wraps = true
		local function hideTip()
			tipLabel.Visible = false
			tipRow.Visible = false
		end
		local tipButtons = {
			{
				name = "Result_TipShowWayButton",
				text = Strings.tip.showWay,
				onActivated = showTipWay,
			},
			{
				name = "Result_TipGotItButton",
				text = Strings.common.gotIt,
				onActivated = hideTip,
			},
			{
				name = "Result_TipDontShowButton",
				text = Strings.tip.dontShow,
				onActivated = function()
					if not NetController.fire(SETTINGS_REMOTE, { showTips = false }) then
						log:warn("SetSettings (showTips = false) was not sent")
					end
					hideTip()
				end,
			},
		}
		for index, spec in tipButtons do
			panelCleanup:add(Button.new({
				name = spec.name,
				text = spec.text,
				textKind = "Small",
				height = TOUCH.minTarget,
				layoutOrder = index,
				parent = tipRow,
				onActivated = spec.onActivated,
			}))
		end
		table.insert(lines, resultLine(tipRow))
	end

	-- Pinned under the scrolling lines (Stack), shown after the return.
	local buttons: Frame = Create("Frame", {
		Name = "Buttons",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = stack,
	})
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.medium, buttons).Wraps = true
	local queueAgain = Button.new({
		name = "Result_QueueAgainButton",
		text = Strings.duel.queueAgain,
		kind = "primary",
		accent = "gold", -- UI FINAL R9: the design's gold (H:498, AGAIN)
		height = TOUCH.primaryButton,
		layoutOrder = 1,
		parent = buttons,
		sound = false, -- opens the queue: ui.open plays instead (§18.6, one sound per action)
		onActivated = function()
			closeResult()
			UIController.open(QUEUE_SCREEN)
		end,
	})
	panelCleanup:add(queueAgain)
	local close = Button.new({
		name = "Result_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI FINAL R9: the band's X (H:252)
		sound = false, -- a Close button plays ui.back (§18.6), as Back / ButtonB do through UIController.back
		onActivated = function()
			closeResult()
			SoundController.play("ui.back")
		end,
	})
	Theme.attachClose(frame, close.root)
	panelCleanup:add(close)
	-- UI FINAL R9: the X shows with the pinned row (after the return), as Close did in it.
	close.root.Visible = buttons.Visible
	panelCleanup:add(buttons:GetPropertyChangedSignal("Visible"):Connect(function()
		close.root.Visible = buttons.Visible
	end))
	-- Batch 3 (friends): Rematch and the opponent's ask over the row (see the header).
	local rematchLine = Theme.label({
		Name = "RematchLine",
		LayoutOrder = -1,
		Text = "",
		Visible = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = buttons,
	}, "Body", Enum.FontWeight.Bold)
	Theme.textOnWindow(rematchLine) -- UI FINAL R9: on the pink body (H:196)
	local rematch: Button.Button
	rematch = Button.new({
		name = "Result_RematchButton",
		text = Strings.duel.rematch,
		kind = "primary", -- UI FINAL R9: the green (H:245)
		height = TOUCH.primaryButton,
		layoutOrder = 0,
		parent = buttons,
		onActivated = function()
			-- One press only until the server answers: a second RematchRequest would take the wish back.
			rematch:setState("disabled")
			NetController.fire("RematchRequest")
		end,
	})
	rematch.root.Visible = false
	panelCleanup:add(rematch)
	local rematchAsked = false -- either player pressed Rematch (the auto-close then waits for the offer to end)
	local function refreshRematch()
		local me = Players.LocalPlayer
		local other = if opponent then Players:GetPlayerByUserId(opponent.userId) else nil
		local offered = me ~= nil and opponent ~= nil and me:GetAttribute("SD_RematchWith") == opponent.userId
		if me == nil or opponent == nil or not offered then
			rematchAsked = false
			if rematch.root.Visible and GuiService.SelectedObject == rematch.root then
				Focus.select(if queueAgain.root.Visible then queueAgain.root else close.root)
			end
			rematch.root.Visible = false
			rematchLine.Visible = false
			local panel = resultPanel
			if panel and panel.rematch == rematch and panel.closeWithOffer then
				closeResult()
			end
			return
		end
		local iWant = me:GetAttribute("SD_RematchWant") == opponent.userId
		local theyWant = other ~= nil and other:GetAttribute("SD_RematchWant") == me.UserId
		local view = DuelFormat.rematchView(iWant, theyWant, opponent.name)
		rematchAsked = iWant or theyWant
		rematch.root.Visible = true
		rematch:setText(view.text)
		rematch:setState(view.state)
		if theyWant and not iWant and not rematchLine.Visible then
			local pulse = UI_CONFIG.Result.rematchPulse
			rematch:pulse(pulse.scale, pulse.upMs, pulse.downMs)
		end
		rematchLine.Text = view.line or ""
		rematchLine.Visible = view.line ~= nil
	end
	-- Closing the card (Close, Back, Queue again) while this player still wants the rematch takes the wish back.
	panelCleanup:add(function()
		local me = Players.LocalPlayer
		if
			me
			and opponent
			and me:GetAttribute("SD_RematchWith") == opponent.userId
			and me:GetAttribute("SD_RematchWant") == opponent.userId
		then
			NetController.fire("RematchRequest")
		end
	end)
	local localPlayer = Players.LocalPlayer
	if localPlayer and opponent then
		for _, name in { "SD_RematchWith", "SD_RematchWant" } do
			panelCleanup:add(localPlayer:GetAttributeChangedSignal(name):Connect(refreshRematch))
		end
		local other = Players:GetPlayerByUserId(opponent.userId)
		if other then
			panelCleanup:add(other:GetAttributeChangedSignal("SD_RematchWant"):Connect(refreshRematch))
		end
	end
	refreshRematch()

	-- §18.5.2 B7 at the title pop: the jingle (none for cancelled / void) and the confetti inside the panel.
	if style.jingle then
		SoundController.play(style.jingle)
	end
	if style.confetti > 0 then
		local colors = if model.outcome == "draw" then Confetti2D.DRAW_COLORS else Confetti2D.WIN_COLORS
		local burst = Confetti2D.play(confettiLayer, title, style.confetti, colors, UIController.scale())
		if burst then
			panelCleanup:add(function()
				burst:stop()
			end)
		end
	end

	-- Part 8 layout (DuelFormat.resultLayout): the body's height and the panel's centre follow the lines, the pinned
	-- row (once it shows) and the screen; the intro's slide rides on top of that centre.
	local slide = if reduced then 0 else LAYOUT.RESULT_SLIDE_PX
	local centerY: number? = nil
	local function place()
		local y = centerY
		local position = if y
			then UDim2.new(0.5, 0, 0, math.floor(y + slide + 0.5))
			else UDim2.new(0.5, 0, LAYOUT.RESULT_ANCHOR_Y, math.floor(slide + 0.5))
		if frame.Position ~= position then
			frame.Position = position
		end
	end
	local function layout()
		local scale = UIController.scale()
		local screen = modalGui.AbsoluteSize
		if not (scale > 0) or screen.Y <= 0 then
			return
		end
		-- The pinned title's height without its pop (its own UIScale is divided out). UI FINAL R9: the window's top
		-- (its border, the band and the body's padding), what hangs above it and its bottom padding with the lip.
		local titlePop = if titleScale.Scale > 0 then titleScale.Scale else 1
		local fitted = Theme.fittedChrome(frame)
		local chrome = fitted.top
			+ fitted.above
			+ Theme.Padding.large
			+ UI_CONFIG.Sticker.lip.window
			+ title.AbsoluteSize.Y / (scale * titlePop)
			+ Theme.Padding.small
		if buttons.Visible then
			chrome += Theme.Padding.small + buttons.AbsoluteSize.Y / scale
		end
		-- Overlays fix: under the duel HUD's top bar while it shows (the Result phase); the bar hides when the card's
		-- lines do not fit under it whole.
		local h = hud
		local barBottom = if h then barBottomIn(h, modalGui, scale) else nil
		local fit = DuelFormat.resultLayout(screen.Y / scale, content.AbsoluteSize.Y / scale, chrome, barBottom)
		if h then
			hideBar(h, "result", not fit.clearsBar)
		end
		local size = UDim2.new(1, 0, 0, math.ceil(fit.bodyHeight))
		if body.Size ~= size then
			body.Size = size
		end
		centerY = fit.centerY
		place()
	end
	panelCleanup:add(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	panelCleanup:add(buttons:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	panelCleanup:add(buttons:GetPropertyChangedSignal("Visible"):Connect(layout))
	panelCleanup:add(modalGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	panelCleanup:add(UIController.LayoutChanged:connect(function()
		layout()
	end))
	local barHud = hud
	if barHud then
		-- The top bar it starts under: its size (the layout pass) and the duel HUD showing or not (the return).
		panelCleanup:add(barHud.top:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
		panelCleanup:add(barHud.gui:GetPropertyChangedSignal("Enabled"):Connect(layout))
		panelCleanup:add(function()
			hideBar(barHud, "result", false)
		end)
	end
	-- Overlays fix: the notices NotifyController holds back during a match wait until this card closes too.
	panelCleanup:add(NotifyController.holdBack("result"))
	layout()

	-- One effect runs the panel's intro (§18.1 #2): the slide in (Back Out over resultBannerMs, none under
	-- ReducedMotion), the title pop and tilt; the lines fading in and sliding up one after another (§9.14 "150 ms
	-- stagger"; all at once under ReducedMotion); the reward counting up from its line's turn, with ui.coin ticks, then
	-- its pulse.
	local hiddenTransparency, hiddenSlide = DuelFormat.lineLook(-1, reduced)
	for _, line in lines do
		applyLine(line, hiddenTransparency, hiddenSlide)
	end
	local started = os.clock()
	local stagger = DUEL_ANIM.rewardLineStaggerMs / 1000
	local shownCoins = -1
	local lastTickAt = -math.huge
	local countEndedAt: number? = nil
	panelCleanup:add(Scheduler.add(function(): boolean
		local clock = os.clock()
		local t = clock - started
		local slidePx, slideDone = DuelFormat.slideLook(t, LAYOUT.RESULT_SLIDE_PX, DUEL_ANIM.resultBannerMs, reduced)
		if slidePx ~= slide then
			slide = slidePx
			place()
		end
		local scale, rotation, titleDone =
			DuelFormat.popLook(t, style.popFrom, DUEL_ANIM.resultBannerMs, -RESULT.titleTiltDeg, reduced)
		titleScale.Scale = scale
		title.Rotation = rotation
		local busy = not titleDone or not slideDone
		for i, line in lines do
			local transparency, slide, lineDone = DuelFormat.lineLook(if reduced then t else t - i * stagger, reduced)
			applyLine(line, transparency, slide)
			busy = busy or not lineDone
		end
		local label, pulse = rewardLabel, rewardScale
		if label and pulse and rewardCoins then
			local since = if reduced then t else t - rewardIndex * stagger
			if since < 0 then
				return true
			end
			local value, countDone = DuelFormat.rewardCount(since, rewardCoins, reduced)
			local whole = math.floor(value + 0.5)
			if whole ~= shownCoins then
				shownCoins = whole
				label.Text = DuelFormat.rewardText(model.outcome, whole) or label.Text
				if whole > 0 and clock - lastTickAt >= AUDIO.coinBatchSeconds then
					lastTickAt = clock
					SoundController.play(SOUND_COIN)
				end
			end
			if not countDone then
				return true
			end
			local endedAt = countEndedAt or clock
			countEndedAt = endedAt
			local pulseScale, pulseDone = DuelFormat.rewardPulse(clock - endedAt, reduced)
			pulse.Scale = pulseScale
			busy = busy or not pulseDone
		end
		return busy
	end, "render"))

	local panel: ResultPanel = {
		frame = frame,
		buttons = buttons,
		queueAgain = queueAgain,
		close = close,
		cleanup = panelCleanup,
		afterReturn = false,
		rematch = rematch,
		closeWithOffer = false,
		rematchAsked = function(): boolean
			return rematchAsked
		end,
	}
	resultPanel = panel
	if StateController.duel() == nil then
		resultAfterReturn(panel)
	end
end

local function showResult(payload: Types.DuelResultPayload)
	closeResult()
	local model = DuelFormat.result(payload, QuestFormat.namer(StateController.get(QUESTS_FIELD)))
	local view = StateController.duel()
	if view and view.matchId == payload.matchId then
		startPoses(model.outcome, view)
	end
	-- Batch 3: who the card may offer a rematch with (never the Studio test dummy).
	local opponent = if view
			and view.matchId == payload.matchId
			and not view.opponent.isTestDummy
		then { userId = view.opponent.userId, name = DuelFormat.nameText(view.opponent) }
		else nil
	-- Foam fix 2: the eliminator's "K.O.!" banner (SD_Vfx, drawn over SD_Modal) ends first, so it never sits on the
	-- card's title (the impact that set it arrives before DuelResult).
	local wait = DuelFormat.resultWait(VfxController.koBannerUntil(), os.clock(), LAYOUT.RESULT_WAIT_MAX)
	if wait <= 0 then
		openResult(model, opponent)
		return
	end
	resultWait = task.delay(wait, function()
		resultWait = nil
		openResult(model, opponent)
	end)
end

-- Per-frame HUD ------------------------------------------------------------------------------------------------------

-- The fill a draining meter shows (§18.4.7): a drop (the charge was spent) drains from what is shown over
-- DragonRush.meterDrainMs; a rise, or no change, shows at once. Reading: the drain also runs under ReducedMotion (it
-- is a slow bar change, not a scale pop).
local function meterFill(meter: Meter, target: number, clock: number): number
	local shown = meter.value or target
	if target < shown - DRAIN_EPSILON then
		if meter.drainTo ~= target then
			meter.drainFrom, meter.drainTo, meter.drainStart = shown, target, clock
		end
		local value, done = DuelFormat.meterDrain(meter.drainFrom, target, clock - meter.drainStart)
		if done then
			meter.drainTo = nil
		end
		return value
	end
	meter.drainTo = nil
	return target
end

local function setMeter(meter: Meter, visible: boolean, fraction: number, clock: number)
	meter.frame.Visible = visible
	local target = math.clamp(fraction, 0, 1)
	local shown = if meter.drains then meterFill(meter, target, clock) else target
	meter.value = shown
	-- Written only when it changes (this runs every frame); at once, never eased (the drain is the meter's own motion).
	if visible and math.abs(meter.bar:get() - shown) > DRAIN_EPSILON then
		meter.bar:set(shown, false)
	end
end

-- The keycap of the meter's key for the active input (DuelFormat.hintKeys; nil hides it), written only on a change.
local function setKey(meter: Meter, key: string?)
	if meter.key ~= key then
		meter.key = key
		meter.keycap:setText(key)
	end
end

local function resetMeter(meter: Meter)
	meter.value = nil
	meter.drainTo = nil
	meter.readySince = nil
end

-- READY (§18.5.2 B8): pops readyPop.from -> 1 when it appears, then the 0.9 s pulse (static under ReducedMotion)
-- starts from 1, so the two join without a jump.
local function setReady(meter: Meter, full: boolean, clock: number)
	local ready, readyScale = meter.ready, meter.readyScale
	if ready == nil or readyScale == nil then
		return
	end
	ready.root.Visible = full
	if not full then
		meter.readySince = nil
		readyScale.Scale = 1
		return
	end
	local since = meter.readySince or clock
	meter.readySince = since
	local reduced = Tweens.reducedMotion()
	local scale, _, popDone = DuelFormat.readyPop(clock - since, reduced)
	if not popDone then
		readyScale.Scale = scale
	elseif reduced then
		readyScale.Scale = 1
	else
		local period = MOTION.ultReadyPulseSeconds
		local phase = ((clock - since - MOTION.readyPop.ms / 1000) % period) / period
		readyScale.Scale = 1 + LAYOUT.READY_PULSE_SCALE * math.sin(phase * 2 * math.pi)
	end
end

-- The own ultimate's charge as a meter fraction (0 for a loadout without one).
local function ultFraction(view: StateController.DuelView): (number, boolean)
	local _, ability = DuelFormat.ultimateOf(view.you.squishyId)
	if ability == nil then
		return 0, false
	end
	return DuelFormat.chargeFraction(StateController.charge(view.you.userId), ability.chargeMax), true
end

-- sfx.pop (2D, own player only, §18.6) once each time the own ultimate becomes ready; also on touch, where the READY
-- label is not shown (reading: the sound belongs to the ultimate being ready, not to the label).
local function updateUltReady(view: StateController.DuelView)
	local fraction, has = ultFraction(view)
	local full = has and fraction >= 1
	if full and not ultFull then
		SoundController.play(SOUND_POP, { priority = 1 }) -- an own sound (§18.6 priority 1)
	end
	ultFull = full
end

local function updateHints(h: Hud, view: StateController.DuelView, aim: ThrowController.AimState)
	local ultimateId = DuelFormat.ultimateOf(view.you.squishyId)
	-- Final polish (2026-10-11): the squeeze key only in first person (DuelSqueeze squeezes the overlay's toy).
	local firstPerson = require(script.Parent.FirstPersonController).mode() == "duel"
	local throwKey, ultimateKey, dashKey, squeezeKey, catchKey =
		DuelFormat.hintKeys(ControlsController.preferredInput().Name, ultimateId ~= nil, firstPerson)
	local phaseShows = DuelFormat.isLive(view.phase) or view.phase == "Countdown"
	if throwKey == nil or not phaseShows then
		h.hints.Visible = false
		return
	end
	local clock = os.clock()
	h.hints.Visible = true
	setKey(h.throwMeter, throwKey)
	setKey(h.catchMeter, catchKey)
	setKey(h.ultMeter, ultimateKey)
	setKey(h.dashMeter, dashKey)
	setKey(h.squeezeMeter, squeezeKey)
	h.dashMeter.frame.Visible = dashKey ~= nil
	h.squeezeMeter.frame.Visible = squeezeKey ~= nil
	setMeter(h.throwMeter, true, if aim.state == "hidden" then 1 else aim.progress, clock)
	-- Feature 1: the catch's cooldown (empty while the hands crush a caught toy).
	setMeter(h.catchMeter, true, require(script.Parent.CatchController).state().progress, clock)
	local fraction, has = ultFraction(view)
	setMeter(h.ultMeter, has, fraction, clock)
	setReady(h.ultMeter, has and fraction >= 1, clock)
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

local function updateReticle(h: Hud, view: StateController.DuelView, aim: ThrowController.AimState, now: number)
	local r = h.reticle
	local text = if DuelFormat.isLive(view.phase) then DuelFormat.reticleText(aim, now) else nil
	-- Foam fix 2: hidden while the forfeit dialog is open and over a HUD button (it cut the Forfeit button's label).
	if text == nil or h.dialog.Visible or aimOverGui(aim.screenPosition) then
		r.root.Visible = false
		return
	end
	r.root.Visible = true
	r.root.Position = UDim2.fromOffset(aim.screenPosition.X, aim.screenPosition.Y)
	-- Feature 1: "Catch!" with its key in place of the state text while an opponent's throw comes at you and the
	-- catch is ready (design: html:88, 673-674), pulsing (DuelFormat.catchPrompt).
	local promptFade = 0
	local catch = require(script.Parent.CatchController)
	if catch.incoming() and catch.state().ready then
		local _, _, _, _, catchKey = DuelFormat.hintKeys(ControlsController.preferredInput().Name, false, false)
		text, promptFade = DuelFormat.catchPrompt(catchKey, os.clock(), Tweens.reducedMotion())
	end
	if r.label.TextTransparency ~= promptFade then
		r.label.TextTransparency = promptFade
		local stroke = r.label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = promptFade
		end
	end
	r.label.Text = text
	-- Overlays fix: the state text moves in from a screen edge (DuelFormat.reticleLabelOffset; it wraps past
	-- RETICLE_LABEL_WIDTH). Chip is a display kind, so the measure never yields.
	if stateText ~= text then
		stateText = text
		stateTextWidth = math.min(LAYOUT.RETICLE_LABEL_WIDTH, Theme.textWidth(text, "Chip") + 2 * Theme.Stroke.thin)
	end
	local offset = DuelFormat.reticleLabelOffset(
		aim.screenPosition.X,
		stateTextWidth,
		h.overlay.AbsoluteSize.X,
		UIController.scale(),
		LAYOUT.EDGE
	)
	setIfChanged(r.label, "Position", UDim2.new(0.5, math.floor(offset + 0.5), 1, Theme.Padding.small))
	local cooling = aim.state == "cooling"
	-- Feature 1: while charging the pie fills to c in the toy's colour and pulses at full (DuelFormat.chargeLook); the
	-- cooldown's white pie otherwise.
	local charging = aim.charging and not cooling
	r.pie.Visible = cooling or charging
	if cooling or charging then
		local right, left = DuelFormat.pieRotations(aim.progress)
		local scale, colour, fill = 1, Theme.Colors.white, LAYOUT.PIE_TRANSPARENCY
		if charging then
			right, left, scale = DuelFormat.chargeLook(aim.charge, os.clock(), Tweens.reducedMotion())
			colour, fill = aim.chargeColor or Theme.Colors.white, UI_CONFIG.Reticle.chargeFillTransparency
		end
		r.pieRight.Rotation = right
		r.pieLeft.Rotation = left
		setIfChanged(r.pieScale, "Scale", scale)
		for _, gradient in { r.pieRight, r.pieLeft } do
			local disc = gradient.Parent
			setIfChanged(disc, "BackgroundColor3", colour)
			setIfChanged(disc, "BackgroundTransparency", fill)
		end
	end
	r.dot.BackgroundColor3 = if aim.state == "blocked" then Theme.Colors.danger else Theme.Colors.white
	local sinceHit = os.clock() - hitClock
	r.hit.Visible = sinceHit < HIT.hitTextMs / 1000
	if r.hit.Visible then
		-- §18.4.2: "Hit!" pops 1.3 -> 1 and tilts ±6° -> 0.
		local scale, rotation = DuelFormat.hitTextPop(sinceHit, hitTiltSign, Tweens.reducedMotion())
		r.hitScale.Scale = scale
		r.hit.Rotation = rotation
	end
end

local function updateArrow(h: Hud, view: StateController.DuelView, now: number)
	local camera = Workspace.CurrentCamera
	local opponentPlayer = Players:GetPlayerByUserId(view.opponent.userId)
	local character = if opponentPlayer then opponentPlayer.Character else nil
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	if camera == nil or root == nil or not root:IsA("BasePart") or not ARROW_PHASES[view.phase] then
		h.arrow.Visible = false
		return
	end
	local point = camera:WorldToViewportPoint(root.Position)
	local visible, position, rotation = DuelFormat.edgeArrow(point, camera.ViewportSize, LAYOUT.ARROW_MARGIN_PX)
	h.arrow.Visible = visible
	if not visible then
		return
	end
	h.arrow.Position = UDim2.fromOffset(position.X, position.Y)
	h.arrow.Rotation = rotation
	local until_ = telegraphUntil
	local color = if until_ ~= nil and now < until_ then Theme.Colors.danger else sideColor(view.opponent.side)
	for _, bar in h.arrow:GetChildren() do
		if bar:IsA("Frame") then
			bar.BackgroundColor3 = color
		end
	end
end

local function hideCountdown(h: Hud)
	countdownCue = nil
	burstIndex = nil
	h.countdown.Visible = false
	h.countdownScale.Scale = 1
	h.countdown.Rotation = 0
	for _, bubble in h.bubbles do
		bubble.frame.Visible = false
	end
end

-- A new countdown text (§18.5.2 B6): the bubble behind the old digit bursts, the new digit gets the other bubble, and
-- its sound plays (duel.countdownTick at its pitch, or duel.go).
local function startCue(h: Hud, cue: DuelFormat.CountdownCue, text: string, clock: number)
	local previous = countdownCue
	if previous and previous.bubble then
		burstIndex, burstStart = bubbleIndex, clock
		bubbleIndex = 3 - bubbleIndex
	end
	countdownCue, countdownStart = cue, clock
	h.countdown.Text = text
	local bubble = h.bubbles[bubbleIndex]
	if cue.bubble then
		bubble.foam:paint(bubbleColors(cue.bubble))
	else
		bubble.frame.Visible = false
	end
	SoundController.play(cue.key, { pitch = cue.pitch })
end

-- A bubble's fade: its foam face and its outline together.
local function setBubbleTransparency(bubble: Bubble, transparency: number)
	bubble.frame.BackgroundTransparency = transparency
	bubble.stroke.Transparency = transparency
end

-- Draws the countdown from its cue's start (the HUD effect's step: no tweens, no timers).
local function drawCountdown(h: Hud, clock: number)
	local reduced = Tweens.reducedMotion()
	local cue = countdownCue
	if cue then
		local look = DuelFormat.countdownLook(clock - countdownStart, cue, reduced)
		if cue.digit == nil and look.done then
			countdownCue = nil -- "Throw!" has faded out
			h.countdown.Visible = false
		else
			h.countdown.Visible = true
			h.countdownScale.Scale = look.textScale
			h.countdown.Rotation = look.rotation
			h.countdown.TextTransparency = look.textTransparency
			h.countdownStroke.Transparency = look.textTransparency
			local bubble = h.bubbles[bubbleIndex]
			bubble.frame.Visible = cue.bubble ~= nil
			bubble.scale.Scale = look.bubbleScale
			bubble.frame.Rotation = look.rotation
			setBubbleTransparency(bubble, look.bubbleTransparency)
		end
	end
	local index = burstIndex
	if index then
		local bubble = h.bubbles[index]
		local scale, transparency, done = DuelFormat.burstLook(clock - burstStart, reduced)
		bubble.frame.Visible = not done
		bubble.scale.Scale = scale
		setBubbleTransparency(bubble, transparency)
		if done then
			burstIndex = nil
		end
	end
end

-- The countdown text follows the server's phaseEndsAt (one change per second, DuelFormat.countdown); "Throw!" then
-- plays its own pop, hold and fade, which can outlast its one-second tick.
local function updateCountdown(h: Hud, now: number)
	local endsAt = countdownEndsAt
	local text = if endsAt then DuelFormat.countdown(endsAt, now, RULES.CountdownSeconds) else nil
	if text == nil and endsAt and now > endsAt then
		countdownEndsAt = nil -- "Throw!" has had its tick
	end
	local clock = os.clock()
	if text ~= countdownText then
		countdownText = text
		local cue = DuelFormat.countdownCue(text)
		if cue and text then
			startCue(h, cue, text, clock)
		elseif countdownCue and countdownCue.digit ~= nil then
			hideCountdown(h) -- a digit with no text after it: the countdown stopped
		end
	end
	drawCountdown(h, clock)
end

-- `object`'s rect in `gui`'s base px (nil while it has no size).
local function rectIn(object: GuiObject, gui: LayerCollector, scale: number): DuelFormat.Rect?
	local size = object.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return nil
	end
	local position = object.AbsolutePosition - gui.AbsolutePosition
	return { x = position.X / scale, y = position.Y / scale, w = size.X / scale, h = size.Y / scale }
end

-- Part 8 (integrator): the duel HUD's top bar while the HUD is built; the duel banners (UIController.banner `below`)
-- sit under it so they never cover the lives row (at 667×375, 20% down was inside the bar).
local function topBar(): GuiObject?
	local h = hud
	return if h then h.top else nil
end

-- Part 8: the top bar clears the top-left Forfeit button (DuelFormat.topBarPlacement). At 667×375 the centred bar
-- (2 × SIDE_WIDTH + the timer, about 560 base px on a 785 px canvas) reached under the button. Run every frame
-- with the HUD: a few reads, and a write only when the place changes.
local function layoutTopBar(h: Hud)
	local scale = UIController.scale()
	local size = h.gui.AbsoluteSize
	if not (scale > 0) or size.X <= 0 or size.Y <= 0 then
		return
	end
	local avoid = if h.forfeit.root.Visible then rectIn(h.forfeit.root, h.gui, scale) else nil
	-- Overlays fix: two rows a side card on the compact layout. Foam fix 2: on both layouts both cards are as wide as
	-- the wider one's content needs (cardNeed: the PC cards hold the opponent's whole name, a phone's are as wide as
	-- the longer lives row), measured once the texts are laid out and only while the bar shows (a hidden bar's labels
	-- may not be laid out); it still only grows within a match, so "1 life" never shrinks the cards.
	local compact = UIController.layoutClass() == "compact"
	if compact ~= sideCompact then
		sideCompact = compact
		sideNeed = 0
		sideSettle = LAYOUT.SIDE_SETTLE_PASSES
		arrangeSide(h.you, compact)
		arrangeSide(h.opponent, compact)
	end
	if sideSettle > 0 then
		sideSettle -= 1
	elseif h.top.Visible then
		sideNeed = math.max(sideNeed, cardNeed(h.you, compact, scale), cardNeed(h.opponent, compact, scale))
	end
	local cardWidth = DuelFormat.sideCardWidth({
		screenWidth = size.X / scale,
		need = sideNeed,
		minWidth = LAYOUT.SIDE_WIDTH,
		middle = if h.timerPanel.Visible then h.timerPanel.AbsoluteSize.X / scale else 0,
		gap = Theme.Padding.medium,
		avoid = avoid,
	})
	local cardSize = UDim2.fromOffset(cardWidth, 0)
	setIfChanged(h.you.card, "Size", cardSize)
	setIfChanged(h.opponent.card, "Size", cardSize)
	setIfChanged(h.opponentColumn, "Size", cardSize) -- foam fix 3: so the bar's box is the drawn cards, centred
	local bar = h.top.AbsoluteSize / scale
	local place = DuelFormat.topBarPlacement(size / scale, bar, avoid)
	local position = UDim2.fromOffset(math.floor(place.x + 0.5), math.floor(place.y + 0.5))
	if h.top.Position ~= position then
		h.top.Position = position
	end
	-- The countdown and its bubbles stay under the bar (DuelFormat.countdownCenterY): on a phone at the largest text
	-- the 150 px bubble 40% down reached the bar's lives row.
	local centreY = DuelFormat.countdownCenterY(size.Y / scale, place.y + bar.Y, math.max(COUNTDOWN_BOX.Y, BUBBLE.px))
	local countdownPosition = UDim2.new(0.5, 0, 0, math.floor(centreY + 0.5))
	if h.countdown.Position ~= countdownPosition then
		h.countdown.Position = countdownPosition
		for _, bubble in h.bubbles do
			bubble.frame.Position = countdownPosition
		end
	end
end

-- Final polish (2026-10-11): "In the lane!" while the opponent's lane telegraph runs and the own body is in its lane
-- (LaneCue.shows), Config.UI.LaneCue.gapPx under the duel bar or under the banner that shows there (UIController's
-- "Banner" in SD_Overlay: the telegraph's own "incoming" one), popping in as it appears.
local function updateLaneCue(h: Hud, now: number)
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	local body = if root and root:IsA("BasePart") then root.Position else nil
	local label = h.laneCue
	local scale = UIController.scale()
	if not LaneCue.shows(h.lane, body, now) or not (scale > 0) then
		label.Visible = false
		return
	end
	local origin = h.gui.AbsolutePosition.Y
	local barBottom = (h.top.AbsolutePosition.Y + h.top.AbsoluteSize.Y - origin) / scale
	local banner = UIController.screenGui("SD_Overlay"):FindFirstChild("Banner")
	local bannerTop: number?, bannerBottom: number? = nil, nil
	if banner and banner:IsA("GuiObject") and banner.Visible then
		bannerTop = (banner.AbsolutePosition.Y - origin) / scale
		bannerBottom = (banner.AbsolutePosition.Y + banner.AbsoluteSize.Y - origin) / scale
	end
	local top = LaneCue.top(barBottom, bannerTop, bannerBottom, UI_CONFIG.LaneCue.gapPx)
	setIfChanged(label, "Position", UDim2.new(0.5, 0, 0, math.floor(top + 0.5)))
	if not label.Visible then
		label.Visible = true
		Tweens.scale(h.laneCueScale, MOTION.readyPop.from, 1, {
			ms = MOTION.readyPop.ms,
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
		})
	end
end

local function updateFrame()
	local h = hud
	local view = StateController.duel()
	if h == nil or view == nil then
		return
	end
	local now = serverNow()
	local timer = DuelFormat.timerText(view.phase, view.phaseEndsAt, now, view.rules)
	h.timerPanel.Visible = timer ~= nil
	h.timer.Text = timer or ""
	layoutTopBar(h)
	updateCountdown(h, now)
	updateUltReady(view)
	local aim = ThrowController.getAimState()
	updateHints(h, view, aim)
	updateReticle(h, view, aim, now)
	updateArrow(h, view, now)
	updateLaneCue(h, now)
	if h.dialog.Visible then
		refreshDialogNote(h, view)
		placeDialog(h)
	end
end

-- Match lifecycle ----------------------------------------------------------------------------------------------------

local function liftFade()
	if fadeSafety then
		task.cancel(fadeSafety)
		fadeSafety = nil
	end
	if faded then
		faded = false
		UIController.fadeTo(1, fadeSeconds(), FADE_COLOR)
	end
end

local function darken()
	if faded then
		return
	end
	faded = true
	UIController.fadeTo(0, fadeSeconds(), FADE_COLOR)
	fadeSafety = task.delay(POSITIONING.StreamAroundTimeoutSeconds + RULES.PositioningTimeoutSeconds, function()
		fadeSafety = nil
		liftFade()
	end)
end

-- One side's look: its text and icon, its pips in the side colour and its card tinted with the side's light colour
-- (foam UI; the panel's bevel follows the tint).
local function paintSide(side: Side, sideName: string, lives: number)
	local color = DuelFormat.sideColors(sideName)
	side.side.Text = DuelFormat.sideText(sideName)
	side.icon:setSide(sideName)
	-- UI overhaul (2026-10-11, Candy UI): the side's own colour is the card's face (bold team colour blocking; the side
	-- is still named in words and by its icon, §7.8); the texts follow the face and the filled lives are white on it
	-- (an empty life is its outline only), so they read against the team colour.
	side.card.BackgroundColor3 = color
	for _, text in { side.name, side.side, side.lives } do
		Theme.textOnColor(text, nil, color)
	end
	side.pips:setCount(lives)
	side.pipCount = lives
	for _, pip in side.pips.root:GetChildren() do
		if pip:IsA("Frame") then
			pip.BackgroundColor3 = Theme.Colors.white
		end
	end
end

local function applySides(h: Hud, view: StateController.DuelView)
	local lives = (view.rules and view.rules.Lives) or RULES.Lives
	h.you.name.Text = Strings.duel.you
	h.opponent.name.Text = DuelFormat.nameText(view.opponent)
	paintSide(h.you, view.you.side, lives)
	paintSide(h.opponent, view.opponent.side, lives)
end

local function beginMatch(view: StateController.DuelView)
	local h = hud
	if h == nil then
		return
	end
	if matchCleanup then
		matchCleanup:clean()
	end
	closeResult()
	stopPoses()
	clearTipWay()
	local mc = Cleanup.new()
	matchCleanup = mc
	-- A new opponent's name and side: the cards are measured again once the new texts are laid out (and the bar's
	-- bottom with them).
	sideNeed, sideSettle, barBottomPx = 0, LAYOUT.SIDE_SETTLE_PASSES, nil
	countdownEndsAt = nil
	countdownText = nil
	telegraphUntil = nil
	h.lane = nil
	h.laneCue.Visible = false
	hitClock = -math.huge
	hideCountdown(h)
	resetMeter(h.ultMeter)
	resetMeter(h.throwMeter)
	ultFull = false
	h.gui.Enabled = true
	h.overlay.Enabled = true
	setResetCallback(true)
	applySides(h, view)
	h.you.pips:set(view.you.lives, false)
	h.opponent.pips:set(view.opponent.lives, false)
	mc:add(Scheduler.add(function(): boolean
		local ok, err = pcall(function(): any
			updateFrame()
			return nil
		end)
		if not ok then
			log:error("duel HUD update failed:", err)
		end
		return true
	end, "render"))
	mc:add(closeDialog)
	mc:add(stopPoses)
	mc:add(function()
		if incomingBanner then
			incomingBanner:dismiss()
			incomingBanner = nil
		end
	end)
end

local function applyView(view: StateController.DuelView, old: StateController.DuelView?)
	local h = hud
	if h == nil then
		return
	end
	local sameMatch = old ~= nil and old.matchId == view.matchId
	h.you.pips:set(view.you.lives, sameMatch)
	h.opponent.pips:set(view.opponent.lives, sameMatch)
	h.you.lives.Text = DuelFormat.livesText(view.you.lives)
	h.opponent.lives.Text = DuelFormat.livesText(view.opponent.lives)

	local _, opponentAbility = DuelFormat.ultimateOf(view.opponent.squishyId)
	local chipVisible = opponentAbility ~= nil and view.opponent.ultReady
	local chipAppears = chipVisible and not h.chip.root.Visible
	h.chip.root.Visible = chipVisible
	if chipVisible then
		h.chip:setText(Strings.resolve(opponentAbility.readyKey) or Strings.resolve(opponentAbility.nameKey) or "")
	end
	if chipAppears then
		-- §18.5.2 B8: the opponent's chip pops like READY, silently.
		Tweens.scale(h.chipScale, MOTION.readyPop.from, 1, {
			ms = MOTION.readyPop.ms,
			style = Enum.EasingStyle.Back,
			direction = Enum.EasingDirection.Out,
		})
	end

	local allowed = DuelFormat.forfeitAllowed(view.phase)
	h.forfeit.root.Visible = allowed
	if not allowed then
		closeDialog()
	end

	local phaseChanged = not sameMatch or (old ~= nil and old.phase ~= view.phase)
	if not phaseChanged then
		return
	end
	if view.phase == "Countdown" then
		countdownEndsAt = view.phaseEndsAt
		-- First person (spec 2026-10-10 §3.1): a level look ahead there; today's look from behind otherwise.
		require(script.Parent.FirstPersonController).faceOpponent(
			POSITIONING.CameraBehindStuds,
			POSITIONING.CameraHeightStuds
		)
	elseif view.phase == "SuddenDeath" then
		UIController.banner(Strings.duel.suddenDeath, {
			seconds = UI_CONFIG.motion.toast.autoDismissSeconds,
			color = Theme.Colors.danger,
			below = topBar(), -- Part 8: never over the lives (a phone's top bar reaches 20% down)
		})
		SoundController.play(SOUND_GO, { pitch = AUDIO.suddenDeathGoPitch }) -- §18.6: duel.go, lower
	elseif view.phase == "Returning" or view.phase == "Cancelled" or view.phase == "Void" then
		stopPoses()
		if view.positioned then
			darken()
		end
	end
end

local function endMatch()
	local h = hud
	if matchCleanup then
		matchCleanup:clean()
		matchCleanup = nil
	end
	if h then
		h.gui.Enabled = false
		h.overlay.Enabled = false
		hideCountdown(h)
		h.arrow.Visible = false
		h.reticle.root.Visible = false
		h.lane = nil
		h.laneCue.Visible = false
	end
	countdownEndsAt = nil
	countdownText = nil
	telegraphUntil = nil
	setResetCallback(false)
	liftFade()
	local panel = resultPanel
	if panel then
		resultAfterReturn(panel)
	end
end

local function onDuelChanged(new: StateController.DuelView?, old: StateController.DuelView?)
	if new then
		if old == nil or old.matchId ~= new.matchId then
			beginMatch(new)
		end
		applyView(new, old)
	elseif old then
		endMatch()
	end
end

local function onUltimateEvent(event: Types.UltimateEventPayload)
	local view = StateController.duel()
	if view == nil or type(event) ~= "table" or event.casterId ~= view.opponent.userId then
		return
	end
	-- Final polish (2026-10-11): the lane of the opponent's lane telegraph for "In the lane!"; any other phase or kind
	-- clears it.
	local h = hud
	if h then
		local _, ability = ThrowController.eventAbility(event :: any)
		h.lane = LaneCue.laneOf(event, if ability then ability.kind else nil)
	end
	if event.phase == "telegraph" then
		telegraphUntil = event.telegraphEndsAt
		local _, ability = DuelFormat.ultimateOf(view.opponent.squishyId)
		local text = if ability then Strings.resolve(ability.incomingKey) else nil
		local seconds = if type(event.telegraphEndsAt) == "number" then event.telegraphEndsAt - serverNow() else 0
		if text and seconds > 0 then
			incomingBanner =
				UIController.banner(text, { seconds = seconds, color = Theme.Colors.danger, below = topBar() })
		end
	else
		telegraphUntil = nil
		if incomingBanner then
			incomingBanner:dismiss()
			incomingBanner = nil
		end
	end
end

-- An own projectile hit the opponent (ThrowController.HitConfirmed): the hit marker at the reticle (§9.8 attacker).
local function onHitConfirmed(impact: Types.ThrowImpactPayload)
	local h = hud
	if
		h == nil
		or (StateController.duel() or StateController.match()) == nil
		or type(impact) ~= "table"
		or impact.kind ~= "player"
	then
		return
	end
	hitClock = os.clock()
	hitTiltSign = -hitTiltSign
	Tweens.scale(h.reticle.ringScale, HIT.hitMarkerScaleFrom, 1, { ms = HIT.hitMarkerMs })
	-- §18.4.4 / §18.6: the attacker's hit cue lands on the contact frame (it never waits for the hit-stop).
	SoundController.play(SOUND_HIT_CONFIRM)
end

-- Public -----------------------------------------------------------------------------------------------------------

-- Opens the "Forfeit the duel?" confirmation (the HUD button and the intercepted Reset). Ignored outside
-- Preparing..SuddenDeath.
function DuelController.openForfeitConfirm()
	openDialog()
end

-- True while the duel HUD is shown (debug state).
function DuelController.isHudVisible(): boolean
	local h = hud
	return h ~= nil and h.gui.Enabled
end

-- Small table for Studio debug hooks.
function DuelController.debugState(): { [string]: any }
	local h = hud
	return {
		hud = h ~= nil and h.gui.Enabled,
		reticle = h ~= nil and h.reticle.root.Visible,
		dialog = h ~= nil and h.dialog.Visible,
		result = resultPanel ~= nil,
		faded = faded,
		poses = poseCleanup ~= nil,
	}
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function DuelController.init()
	local c = Cleanup.new()
	cleanup = c
	hud = buildHud(c)
	c:add(function()
		hud = nil
		sideCompact, sideNeed, sideSettle, stateText, barBottomPx = nil, 0, 0, nil, nil
		table.clear(barHidden)
	end)
	-- FFA/TDM v1 (see the header): the match look's hooks into this HUD.
	c:add(require(script.Parent.MatchController).attachDuelHud({
		hud = function(): Hud?
			return hud
		end,
		reticle = updateReticle,
		hints = updateHints,
		countdown = updateCountdown,
		ultReady = updateUltReady,
		hideCountdown = hideCountdown,
		setCountdown = function(endsAt: number?)
			countdownEndsAt, countdownText = endsAt, nil
		end,
		reset = function(h: Hud)
			resetMeter(h.ultMeter)
			resetMeter(h.throwMeter)
			ultFull, hitClock = false, -math.huge
		end,
		hideBar = hideBar, -- review fix: the top bar hides through barHidden (reason "match")
		closeResult = closeResult, -- review fix: a 1v1 result card still open closes when a match starts
	}))

	local bindable = Instance.new("BindableEvent")
	bindable.Name = "SD_ResetIntercept"
	resetBindable = bindable
	c:add(bindable)
	c:add(bindable.Event:Connect(openDialog))

	c:add(StateController.DuelChanged:connect(onDuelChanged))
	c:add(StateController.DuelResultReceived:connect(showResult))
	c:add(NetController.onUltimateEvent(onUltimateEvent))
	c:add(ThrowController.HitConfirmed:connect(onHitConfirmed))
	-- Feature 1 (2026-10-11): the catch's big words and the catcher's hit marker (header; an inline require).
	local CatchController = require(script.Parent.CatchController)
	local function bigWord(text: string, event: CatchController.Event)
		if StateController.duel() == nil or (incomingBanner ~= nil and incomingBanner:isShown()) then
			return
		end
		local def = require(Shared.Catalog).get(event.squishyId)
		UIController.banner(text, {
			seconds = UI_CONFIG.Reticle.bigWordSeconds,
			color = if def then Color3.fromHex(def.visuals.accent) else nil,
			below = topBar(),
		})
	end
	c:add(CatchController.Caught:connect(function(event: CatchController.Event)
		bigWord(Strings.duel.caught, event) -- design: html:352
	end))
	c:add(CatchController.Burst:connect(function(event: CatchController.Event)
		local view = StateController.duel()
		if view == nil or not DuelFormat.isLive(view.phase) then
			return -- the match ended meanwhile: no life lost
		end
		local thrower = if event.throwerId == view.you.userId then view.you else view.opponent
		if thrower.lives > 1 then
			bigWord(Strings.duel.squished, event) -- design: html:563
		end
		local localPlayer = Players.LocalPlayer
		if localPlayer ~= nil and event.catcherId == localPlayer.UserId then
			onHitConfirmed({ projId = event.projId, kind = "player", position = event.position }) -- design: html:365
		end
	end))
	c:add(NetController.onNotify(function(code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind)
		if type(code) == "string" and string.sub(code, 1, #ULT_NOTIFY_AREA) == ULT_NOTIFY_AREA then
			UIController.notify(code, if type(args) == "table" then args else nil, toastKind(kind))
		end
	end))
	c:add(function()
		closeResult()
		stopPoses()
		clearTipWay()
		if matchCleanup then
			matchCleanup:clean()
			matchCleanup = nil
		end
		liftFade()
		resetToken += 1 -- stops a pending SetCore retry loop
	end)
end

function DuelController.start()
	-- A match already running when this client starts (a late start) still gets its HUD.
	local view = StateController.duel()
	if view then
		onDuelChanged(view, nil)
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function DuelController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return DuelController
