--!strict
-- SqueezeController (client only). DESIGN §6.3, §9.6, §11.6 ("Near mats"), §11.7, §17.3.2 (hold-to-squeeze),
-- §17.7 ("At a pad"); spec 2026-10-11 §5 (squeeze anywhere, Coins every time) and §3.8 (the first-person "+N"); lobby
-- HUD spec 2026-10-11 §2 (tap or click to squeeze, the info on the squishy).
-- The lobby squeeze: the floating label on the held squishy, the local squeeze feel, SqueezeRequest / SqueezeResult,
-- the popups, hold-to-squeeze and other players' squeezes.
--
-- * Tap or click to squeeze (lobby HUD spec §2): there is no squeeze panel and no Squeeze button any more. The lobby
--   "Squeeze" action takes F / E / ButtonX, and ControlsController presses it for a left click or a touch on the 3D
--   world with that InputObject (never one on the UI, in the practice box, in the thumbstick zone or on the jump
--   button, nor a second finger), as does the first-person touch pad (ViewmodelController.pressPad) with its finger.
--   A key press waits while another ProximityPrompt shows (ProximityPromptService.PromptShown / PromptHidden: E and
--   ButtonX are the prompt's); a click or a touch never does.
-- * The floating label (lobby HUD spec §2, point 4; "like steal an egg or ride a pet"): one BillboardGui
--   (SD_SqueezeLabel in Workspace.SD_ClientFx, client-made, so only this player sees it) on the held model's Root,
--   pointed at the new model on HeldSquishyController.HeldChanged: a Px size (the same size at any distance, labelSize,
--   pure), AlwaysOnTop, LightInfluence 0 and the nameplates' foam chip (Frosting, the chip bands and outline, the Chip
--   text in InkUI), its bottom Vfx.CoinPopup.startStuds above the Root. Its text (panelLabel, pure, named for the old
--   panel) is what one own squeeze pays, the same anywhere (Phase 5; since Phase 3 a pad no longer changes it):
--   grip.stationLabelBase with the Coins (PenMath.rewardCoins of one squeeze at PenMath.squeezeValue) and the Grip
--   (PenMath.squeezeGrip) of StateController's `pen` field (pens3 phase 1), re-read with the station check. Shown
--   (labelShownFor, pure) only while holding, out of a match, with the lobby unlocked, no screen open (no block) and no
--   first-person look; it is built once and shown or hidden with Enabled.
-- * Sending (§17.3.2, §9.6; Batch 1 #2: squeezes pay up to the hold rhythm): there is no squeeze timer and no
--   cooldown strip, ring or disabled button between squeezes. Every press (F / E / ButtonX, a click, a tap, the pad)
--   squeezes IMMEDIATELY: the local squeeze restarts from the top (play) and a SqueezeRequest (no argument: the server
--   finds the pad itself) goes at once, without waiting for the last reply. It is sent while the client is under the
--   server's paid-squeeze cap (Config.Squeeze: 2 at once, then 1 per cycleSeconds = Hold.repeatSeconds): it never
--   sends more than Config.Squeeze.bucketCapacity requests inside bucketCapacity × cycleSeconds (0.9 s, underCap,
--   pure). Auto-clicker check (2026-10-16): a fresh press over it is still sent, so the server sees the real press
--   rhythm (it pays nothing: squeeze.tooFast, no "+N", nothing negative shown), at most
--   Config.Net.AutoClick.clientPressesPerSecond inside any rolling second and none while a reply is late by more than
--   Hold.repeatSeconds + replyGraceSeconds (pressSendable, pure: a network stall would queue them up against the
--   remote's flood limits); past that it only squishes on screen. A hold repeat over the cap is still not sent.
--   Review fix (2026-10-16): none at all while the check is off (pressCap: Config.Net.AutoClick.enabled false, or a
--   config Config/ValidateAutoClick refuses, as the server's check does).
--   While held, the repeat goes at a relaxed rhythm of one full squeeze animation: max(nextAt +
--   Hold.leadSeconds, lastSend + Hold.repeatSeconds) (SqueezeResult.nextAt is SERVER time,
--   Workspace:GetServerTimeNow()); with no SqueezeResult within repeatSeconds + Hold.replyGraceSeconds (a flood-guard
--   drop has no reply) the next repeat goes anyway (sendDue, pure). Clicking pays no faster than holding. "+N Coins"
--   only when SqueezeResult.coins > 0; "+N Grip" /
--   "+N Grip (xM)" when grip > 0 (doubled). A rejection other than squeeze.tooFast stops the hold and shows its reason
--   once (tooFast is silent: the client shows nothing for it).
-- * Hold stop rules (§17.3.2; holdStopReason, pure, plus events): End / Cancel (ControlsController delivers End even
--   when the action is no longer live; a click's or a touch's End only for its own finger, buttonReleases), the input no
--   longer physically held (UserInputService:IsKeyDown, IsGamepadButtonDown on the pressing gamepad,
--   IsMouseButtonPressed for a click, and for a touch touchHeld: its InputObject not End or Cancel and moved less than
--   Config.Inspect.Input.tapMaxPixels (8 px) from where it began; past that it is a camera drag and the hold ends, the
--   first squeeze already happened), Config.Grip.Hold.maxSeconds (600) of continuous hold, WindowFocusReleased,
--   a match (SD_DuelPhase / SD_MatchId), ControlsController.BlockChanged(true) (any modal, the idle card included),
--   ContextChanged("Lobby", false), any rejection but tooFast, and Searching in the queue with Hold.queuedSeconds (60)
--   since the last fresh press (reading: the queue state comes from StateController.queue(), the one reducer of
--   QueueStatus from NetController). Where the player stands never stops a hold (spec 2026-10-11 §5: no "station" or
--   "locked" stop). Only a fresh Begin starts a hold again. When the hold stops by
--   itself (600 s, the queue rule, focus lost, a modal) the toast grip.holdPaused appears (reading: not after the
--   player's own release, a match or a rejection, which shows its own reason). Every message here (a rejection's
--   reason, grip.holdPaused) goes through NotifyController.show, so it sounds
--   like any toast and grip.* codes are held back from Matched through Returning (§17.2).
-- * The squeeze feel (§9.6; squishy overhaul spec 2026-10-09 §3.2): play(player) is a tap on the rig of the player's
--   held model (Controllers/SqueezeFeel, the squeeze glue; HeldSquishyController owns and steps the rig): the
--   Config.Anim.squeeze.phases press scaled to the toy, its own springy recovery, the rarity flourishes, the squish
--   face. Sounds, puffs, the steam, the release pop and the rhythm fire from the rig's one-shot events at today's
--   timing points (sfx.squish at the end of anticipation, puffs at peak compression, sfx.squeezeRelease and the pop at
--   the release pop end); the arms hold still (spec 2026-10-11 §4: only the squishy squeezes). Sounds go through
--   SoundController (silent until vetted ids exist). Other players' squeezes come from their character's
--   server-written SD_SqueezeAt (only fresh changes, within Config.Squeeze.othersCullStuds = 60 studs, §9.6; their
--   sounds within Config.Audio.Spatial.othersSqueezeStuds, at most othersSqueezeMax at once, §11.9).
--   Every press squishes (SqueezeFeel.startKind / interruptFx): the local player's own squeeze restarts the rig on
--   every press, even mid-squeeze, from where it is so nothing jumps; another player's waits for its running squeeze's
--   release pop end ("busy"). An own squeeze cut short before its pop end merges its release pop (the big pop on every
--   8th) and, at most once per release pop, its puffs into the press. Budgets at 12 presses a second (a human's fastest;
--   presses over the paid cap still play): sfx.squish and
--   sfx.squeezeRelease keep their 90 ms key cooldown (Config.Audio), puffs come no faster than back-to-back full
--   squeezes, every burst goes through FxPool's live-particle caps, the "+N" pool keeps coinPopupMaxVisible lines of a
--   kind, a reply within foldSeconds of the newest line of its kind folds its amount into that line (foldsInto: same
--   totals, fewer lines, no smear), and a Foam Mat pulses at most once per MAT_MERGE_SECONDS (under 3 Hz, §18.1 #4).
-- * Signals for higher layers: ResultReceived(result) after every SqueezeResult (CapsuleController's home tap).
--   Build plan Phase 6: slow training is gone, and popup() (its line) with it.
--   Studio: debugHold(on) / debugPress() drive the same rules with a virtual input (DebugHooks).
-- * Part 8 (§17.12 L5), kept for the world touch: the pure buttonReleases(held, pressed, ended, kind) decides which
--   ended input releases a pointer hold (the finger that pressed, wherever it lifts; any left mouse release), and
--   buttonStillDown(held, state) counts the pressing finger's InputObject as released once its UserInputState is End
--   or Cancel (Reading: a touch the engine cancels, e.g. one taken over by the camera, may never send its end), so the
--   hold check (isHeld, every frame) stops it either way.
-- Feel pass (DESIGN §18.5.1 A1-A4; cosmetic only, never affects sending: sendDue and holdStopReason ignore it):
--   * Others (A1): play(player, {particles, other = true}) gives another player's squeeze Effects.othersSqueezePuffs
--     (4) puffs only within Effects.othersSqueezeStuds (40) of this client (othersPuffs), no steam, no release pop and
--     no rhythm; the animation still plays out to Config.Squeeze.othersCullStuds (60).
--   * Release pop (A1): at the release pop end the own squeeze emits sparkles (SqueezeFeel's RELEASE_POP look, the
--     squishy's accent, White for a Common) with sfx.squeezeRelease.
--   * Rhythm (A2, Anim/SqueezeRhythm in SqueezeFeel, own squeezes only): sfx.squish and sfx.squeezeRelease pitch
--     follows the streak pattern (with the random variance cut once the streak is >= 2); every 8th squeeze the big pop
--     (4 sparkles in place of the release pop's 2) plus sfx.pop; any rejection but squeeze.tooFast resets the streak.
--   * Mat pulse (A3): an own accepted squeeze on a Foam Mat, or another player's SD_SqueezeAt change within
--     othersSqueezeStuds whose root is on a mat (the WorldLayout mat within stationRadius + radiusTolerance), pulses
--     that mat's Color base -> base:Lerp(Palette[SqueezeZone.pulseColor], MatPulse.towardPulseColor) -> base
--     (matPulseColor; the base is always Palette[SqueezeZone.matColor], never read back) and grows an FxShapes ring on
--     the mat top at the squeezer's feet; one pulse and one ring per mat, a new trigger restarts them, at most once
--     per MAT_MERGE_SECONDS per mat (faster triggers merge into the running pulse: fast clicking never strobes the
--     mat). ReducedMotion: the colour pulse at most once per MAT_REDUCED_GAP per mat, no ring. The mat's Color is the
--     only property written on the lobby's mats (§18.1 #3), and
--     always restored.
--   * "+N" above the squishy (A4; lobby HUD spec §2: the Grip lines too, from the one pool): an own
--     SqueezeResult.ok shows "+N" (a coin icon and common.plusAmount) when coins > 0 and "+N Grip" / "+N Grip (xM)"
--     when grip > 0, from a pool of POPUP_POOL BillboardGuis (a share of
--     Effects.coinPopupMaxVisible per kind; the oldest is reused) on the local held model's Root, else the
--     HumanoidRootPart, rising and popping in (coinPopupSample), fading at the end. Each starts above the floating
--     label, Coins first, then Grip one step higher (lineLiftPx, pure; the label is px-sized, so
--     the lift is in px: the BillboardGui is that much taller with the line at its top). The Grip lines keep the old
--     panel's look: the kind's colour (popupColor, pure: Grip Mint) with the
--     InkUI outline; "+N" keeps its coin icon and white outline. A reply within foldSeconds("coins") of the newest line
--     of its kind adds its amount to that line's number instead.
--     First person (spec 2026-10-11 §3.8): while FirstPersonController.look() is on, the held model is hidden and the
--     toy shows in the overlay, so the lines float at the overlay toy instead ("+N Coins", common.coinsGain): the
--     point on ViewmodelController.toyScreenPoint() (hudOffsetOf, pure), Grip one step higher, as the design's floats
--     (UI FINAL R2: UI/UiFx.float, the kind's colour, the size and drift of Config.UI.Fx.events.squeeze; still and
--     fading under ReducedMotion), a reply within half a coinCounter float folding into it (foldsInto). All are read
--     through inline requires, so this module adds no top-level local; with no toy point it falls back to the
--     billboard.

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PenMath = require(Shared.PenMath)
local Signal = require(Shared.Util.Signal)
local Strings = require(Shared.Strings)
local ValidateAutoClick = require(Shared.Config.ValidateAutoClick)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local FxShapes = require(Client.Anim.FxShapes)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local CoinIcon = require(Client.UI.Components.CoinIcon)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local ControlsController = require(script.Parent.ControlsController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SqueezeFeel = require(script.Parent.SqueezeFeel)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

-- A SqueezeResult as the client keeps it (normalizeResult). nextAt is server time (§17.10).
export type Result = {
	ok: boolean,
	coins: number,
	total: number?,
	limit: number?,
	reason: string?,
	nextAt: number?,
	grip: number,
	gripTotal: number?,
	doubled: boolean,
}

-- play() options (§18.5.1 A1): SqueezeFeel's.
export type PlayOptions = SqueezeFeel.PlayOptions

-- One frame of the "+N" popup (coinPopupSample): its height above the adornee, its UIScale, how far it has faded
-- (0 = solid, 1 = gone) and whether it is over.
export type CoinPopupSample = { offsetY: number, scale: number, fade: number, done: boolean }

-- What sendDue() needs: the last send (server time), whether its reply came, and the server's nextAt.
export type SendState = { lastSendAt: number?, replied: boolean, nextAt: number }

-- What holdStopReason() checks every frame while a hold runs.
export type HoldCheck = {
	held: boolean, -- the pressing input is still physically held
	heldFor: number, -- seconds since the press that started the hold
	sinceFresh: number, -- seconds since the last fresh press
	inMatch: boolean,
	lobbyLive: boolean, -- the Lobby context is on
	blocked: boolean, -- ControlsController.block() is held (a modal)
	queued: boolean, -- the queue state is Searching
}

export type StopReason = "released" | "match" | "context" | "blocked" | "focus" | "maxTime" | "queued" | "rejected"

export type PopupKind = "coins" | "grip"

-- What labelShownFor() checks (lobby HUD spec 2026-10-11 §2: the floating label on the held squishy).
export type LabelFacts = {
	holding: boolean, -- the local player shows a held model (HeldSquishyController.isHolding)
	inMatch: boolean,
	lobbyLocked: boolean, -- StateController.isLobbyLocked()
	blocked: boolean, -- ControlsController.block() is held (a screen is open)
	firstPerson: boolean, -- a first-person look is on (the held model is hidden; the toy shows in the overlay)
}

type HoldConfig = {
	maxSeconds: number,
	queuedSeconds: number,
	repeatSeconds: number,
	leadSeconds: number,
	replyGraceSeconds: number,
}
type HoldSource = "keyboard" | "gamepad" | "mouse" | "touch" | "virtual"
-- Which physical input pressed Squeeze (the hold checks that this exact input is still down): a click or a touch keeps
-- its InputObject, a touch also where it began.
type PressInput = {
	source: HoldSource,
	keyCode: Enum.KeyCode?,
	gamepad: Enum.UserInputType?,
	input: InputObject?,
	from: Vector3?,
}
type Hold = {
	source: HoldSource,
	keyCode: Enum.KeyCode?,
	gamepad: Enum.UserInputType?,
	input: InputObject?, -- the click or the finger that pressed
	from: Vector3?, -- where that finger began
	startedAt: number, -- os.clock() of the press that started it
	freshAt: number, -- os.clock() of the last fresh press
}

-- A "+N" BillboardGui of the pool (A4; since the lobby HUD spec any kind of line) and the transparency values its fade
-- starts from.
type FadeTarget = { object: Instance, property: string, base: number }
type CoinPopup = {
	gui: BillboardGui,
	scale: UIScale,
	label: TextLabel,
	icon: GuiObject, -- the coin icon (Coins only)
	stroke: UIStroke, -- the line's outline
	kind: PopupKind, -- the look it has now (stylePopup)
	fades: { FadeTarget },
	startedAt: number?, -- os.clock(); nil while unused
	reduced: boolean, -- started under ReducedMotion
}
-- The newest line of a kind (its pool slot, or index 0 for a first-person line with its label and start), with the
-- amount it shows, so a fast reply folds into it (foldsInto) instead of starting another line.
type Fold = { index: number, amount: number, doubled: boolean, label: TextLabel?, startedAt: number? }

-- The colour pulse and ring of one Foam Mat (A3).
type MatPulse = {
	part: BasePart,
	startedAt: number,
	ring: FxShapes.Ring?,
	handle: Scheduler.Handle?,
	lastAt: number, -- os.clock() of the last pulse (MAT_MERGE_SECONDS, or the ReducedMotion gap)
}

-- Lobby HUD spec 2026-10-11 §2: the floating label on the held squishy, and the full-HUD frame for the lines that
-- float at the first-person toy (spec 2026-10-11 §3.8).
type FloatLabel = {
	overlay: Frame,
	gui: BillboardGui,
	chip: Frame,
	text: TextLabel,
	px: number, -- the chip's height (labelSize), so the "+N" lines start above it
}

-- Constants

local STATION_RADIUS = Config.Squeeze.stationRadius
-- The client side of the server's paid-squeeze cap (Batch 1 #2): at most CAP sends inside CAP_WINDOW seconds
-- (bucketCapacity in bucketCapacity × cycleSeconds = 2 in 0.9 s). Auto-clicker check (2026-10-16): a fresh press over
-- it is still sent (pressSendable): at most PRESS_CAP a second, none once a reply is STALL_SECONDS late. Review fix
-- (2026-10-16): PRESS_CAP is pressCap's, set by init(): 0 while the check is off.
local CAP = Config.Squeeze.bucketCapacity
local CAP_WINDOW = Config.Squeeze.bucketCapacity * Config.Squeeze.cycleSeconds
local PRESS_CAP = 0
local STALL_SECONDS = Config.Grip.Hold.repeatSeconds + Config.Grip.Hold.replyGraceSeconds
local OTHERS_CULL_STUDS = Config.Squeeze.othersCullStuds
local HOLD: HoldConfig = Config.Grip.Hold
local RESTED_MULT = Config.Grip.Rested.mult
local FLOAT = Config.UI.motion.coinCounter
local ACTION = "Squeeze"
local HUD_GUI = "SD_Hud"
local ROOT_PART = "HumanoidRootPart"
local ATTR_SQUEEZE_AT = "SD_SqueezeAt"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local ATTR_MATCH_ID = "SD_MatchId"
local REASON_TOO_FAST = "squeeze.tooFast"
local REASON_GENERIC = "error.generic"
-- Messages go through NotifyController.show (the ui.toast sound; grip.* codes are held back during a match, §17.2).
local NOTICE_HOLD_PAUSED = "grip.holdPaused"
-- Stops that show grip.holdPaused (the hold ended by itself, not by the player's own action).
local PAUSE_TOAST: { [string]: boolean } = { maxTime = true, queued = true, focus = true, blocked = true }
local STATION_CHECK_SECONDS = 0.1 -- the station under the player is re-checked this often (cheap, 9 stations)
-- The box (px) a Grip or first-person line is centred in: wide enough for "+1,500 Grip (x2)" (the old panel's width).
local LINE_WIDTH = 300
local POPUP_STEP_PX = 30 -- the kinds of a reply start this much apart (lineLiftPx), Coins lowest
local MAX_POPUPS = 6
-- reading: other players' SD_SqueezeAt older than this (a character streaming in with an old value) is not played.
local OTHERS_MAX_AGE_SECONDS = 1
-- The squeeze's sounds play in SqueezeFeel (from the rig's events); ui.coin plays with the HUD's Coins change
-- (HudController), not here.
-- Feel pass (§18.5.1 A1-A4).
local EFFECTS = Config.Vfx.Effects
local MAT_PULSE = Config.Vfx.MatPulse
local COIN_POPUP = Config.Vfx.CoinPopup
local REDUCED_FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local TAG_STATION = WorldLayout.Tags.SqueezeStation
local ATTR_STATION_ID = WorldLayout.Attributes.StationId
-- A3: the ring sits on the mat top (§18.5.1 A3 "Y 0.32": WorldLayout's mat height plus 0.02).
local MAT_RING_Y = WorldLayout.SqueezeZone.matHeight + 0.02
local MAT_REDUCED_GAP = 1.5 -- seconds: ReducedMotion keeps the colour pulse at most this often per mat (A3)
-- Reading (every click pays): a mat pulses at most once per ring life (0.35 s, under 3 pulses a second, §18.1 #4);
-- triggers in between merge into the running pulse, so 12 squeezes a second never strobe a mat.
local MAT_MERGE_SECONDS = MAT_PULSE.ringSeconds
local CAP_EDGE_SECONDS = 1e-6 -- a send exactly CAP_WINDOW old is out of the window (float slack, underCap)
-- A4: "+N" timing, from Effects (rise, seconds, max visible) and Vfx.CoinPopup (start, size, pop, fade).
local POPUP_REDUCED_HOLD = 0.5 -- seconds shown under ReducedMotion before the short fade (A4)
local POPUP_GUI = "SD_CoinPopup"
local BACK_OVERSHOOT = 1.70158 -- TweenService's Back easing constant (Back Out, computed here so the sample is pure)

-- Module table

local SqueezeController = {}

-- Fired with (result: Result) after every SqueezeResult, once its popups are shown.
SqueezeController.ResultReceived = Signal.new() :: Signal.Signal<Result>
-- The "+N" pool's size (lobby HUD spec §2): a share of Effects.coinPopupMaxVisible for each kind of line (Coins and
-- Grip; Phase 6 removed the slow-training share), so a reply's lines never take each other's slots early.
SqueezeController.POPUP_POOL = EFFECTS.coinPopupMaxVisible * 2

-- Private

local log = Log.new("Squeeze")
local cleanup: Cleanup.Cleanup? = nil
local watchers: { [Player]: () -> () } = {} -- other players' SD_SqueezeAt watchers (unwatch functions)
local warnedKeys: { [string]: boolean } = {}
local lastStepError: string? = nil

local currentStation: WorldLayout.Station? = nil
local shownPrompts: { [ProximityPrompt]: boolean } = {}
local hold: Hold? = nil
local labelShown = false -- the floating label shows (labelShownFor)
local virtualHeld = false
local sendState: SendState = { lastSendAt = nil, replied = true, nextAt = 0 }
local recentSends: { number } = {} -- os.clock() of the last CAP sends (underCap)
local pressSends: { number } = {} -- os.clock() of the last PRESS_CAP sends (pressSendable)
local waitingSince: number? = nil -- os.clock() of the first send since the last reply (nil: none waits)
local sends = 0
local lastStopReason: StopReason? = nil
local lastResult: Result? = nil
local floatLabel: FloatLabel? = nil
local stationClock = 0
local matPulses: { [BasePart]: MatPulse } = {} -- A3, one per mat
local coinPopups: { CoinPopup } = {} -- A4 pool (at most POPUP_POOL)
local popupsHandle: Scheduler.Handle? = nil -- the one Scheduler effect that runs every live popup
local lineFolds: { [string]: Fold } = {} -- the newest line of each kind (a fast reply folds into it)

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	if template == nil then
		if not warnedKeys[key] then
			warnedKeys[key] = true
			log:warn(`no Strings text for {key}`)
		end
		return ""
	end
	return Strings.format(template, args)
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function localPlayer(): Player?
	return Players.LocalPlayer
end

local function rootOf(character: Model?): BasePart?
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function localRoot(): BasePart?
	local player = localPlayer()
	return rootOf(if player then player.Character else nil)
end

local function inMatch(): boolean
	local player = localPlayer()
	if player == nil then
		return false
	end
	local phase = player:GetAttribute(ATTR_DUEL_PHASE)
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	return (type(phase) == "string" and phase ~= "") or (type(matchId) == "string" and matchId ~= "")
end

local function promptShown(): boolean
	for prompt in shownPrompts do
		if prompt.Parent ~= nil and prompt.Enabled then
			return true
		end
		shownPrompts[prompt] = nil
	end
	return false
end

-- Popups ------------------------------------------------------------------------------------------------------------

-- Spec 2026-10-11 §3.8: one line floating at the first-person toy, `at` (an SD_Hud offset) in the SqueezeOverlayPopups
-- frame, a Grip line one step higher (lineLiftPx's steps), at most MAX_POPUPS at once (the oldest goes). UI FINAL R2
-- (plan §2.1 squeeze row, H:703-704): drawn by UI/UiFx.float in that frame (so it keeps SD_Hud's layer and hides
-- with the HUD), the design's float (the Sticker role "float": a 6 px ink stroke and a 3 px drop; it pops in,
-- rises and fades, lib:255-268) centred on that point, in the design's colour, size and drift of
-- Config.UI.Fx.events.squeeze (coinFloat / gripFloat; popupColor when the colour is unknown). Read through an inline
-- require (no top-level local). Returns its label (a fold changes its Text), nil when nothing is drawn. AFFECTED
-- 2026-10-15; pens3 phase 1: the amounts are the server's, paid at the pen's squeeze value.
local function showOverlayLine(line: string, kind: PopupKind, at: Vector2): TextLabel?
	local l = floatLabel
	if l == nil or line == "" then
		return nil
	end
	local container = l.overlay
	local existing = container:GetChildren()
	if #existing >= MAX_POPUPS then
		existing[1]:Destroy()
	end
	local y = at.Y - (SqueezeController.lineLiftPx(kind, 0) - SqueezeController.lineLiftPx("coins", 0))
	local float = Config.UI.Fx.events.squeeze[if kind == "coins" then "coinFloat" else "gripFloat"]
	-- The design's float colour (H:703 #FFE36B, H:704 #9EF7D2), else the kind's popup colour.
	local named = (Palette :: any)[float.color]
	local color = if typeof(named) == "Color3" then named else SqueezeController.popupColor(kind)
	local UiFx = require(script.Parent.Parent.UI.UiFx)
	local options = { dx = float.dx, parent = container :: GuiObject }
	return UiFx.float(Vector2.new(at.X, y), line, color, float.kind, options)
end

-- Feel: Foam Mat pulse (§18.5.1 A3) ---------------------------------------------------------------------------------

local function paletteColor(token: string, fallback: Color3): Color3
	local value = (Palette :: any)[token]
	return if typeof(value) == "Color3" then value else fallback
end

-- The mat part of a Foam Mat station (tagged SD_SqueezeStation with its StationId), or nil while it is streamed out.
local function matPart(stationId: string): BasePart?
	for _, instance in CollectionService:GetTagged(TAG_STATION) do
		if instance:IsA("BasePart") and instance:GetAttribute(ATTR_STATION_ID) == stationId then
			return instance
		end
	end
	return nil
end

-- Ends a mat's pulse and ring at once and writes its base colour back.
local function stopMatPulse(pulse: MatPulse)
	local handle = pulse.handle
	pulse.handle = nil
	if handle then
		handle:disconnect()
	end
	local ring = pulse.ring
	pulse.ring = nil
	if ring then
		ring:stop()
	end
	if pulse.part.Parent ~= nil then
		pulse.part.Color = SqueezeController.matPulseColor(math.huge)
	end
end

-- Forgets the pulses of mats that streamed out: their parts are gone, and a mat that streams back in is a new part, so
-- an entry kept for a gone part would only pin it for the session.
local function forgetGoneMats()
	for part, pulse in matPulses do
		if part.Parent == nil then
			stopMatPulse(pulse)
			matPulses[part] = nil
		end
	end
end

-- Pulses the Foam Mat `stationId` (A3) and grows a ring at the squeezer's feet `at` (its X/Z). A new trigger on the
-- same mat restarts both, at most once per MAT_MERGE_SECONDS (MAT_REDUCED_GAP under ReducedMotion): triggers in
-- between merge into the running pulse, so fast clicking never strobes the mat.
local function pulseMat(stationId: string, at: Vector3)
	local station = WorldLayout.station(stationId)
	if station == nil then
		return
	end
	forgetGoneMats()
	local part = matPart(stationId)
	if part == nil then
		return
	end
	local now = os.clock()
	local reduced = Tweens.reducedMotion()
	local existing = matPulses[part]
	if existing and now - existing.lastAt < (if reduced then MAT_REDUCED_GAP else MAT_MERGE_SECONDS) then
		return
	end
	local pulse: MatPulse = existing or { part = part, startedAt = now, ring = nil, handle = nil, lastAt = now }
	matPulses[part] = pulse
	pulse.startedAt = now
	pulse.lastAt = now
	local ring = pulse.ring
	pulse.ring = nil
	if ring then
		ring:stop()
	end
	if not reduced then
		pulse.ring = FxShapes.ring(
			Vector3.new(at.X, MAT_RING_Y, at.Z),
			Vector3.yAxis,
			MAT_PULSE.ringToStuds,
			MAT_PULSE.ringSeconds,
			Palette.White,
			MAT_PULSE.ringTransparencyFrom
		)
	end
	if pulse.handle == nil then
		pulse.handle = Scheduler.add(function(_dt: number, clock: number): boolean
			if pulse.part.Parent == nil then
				-- Streamed out mid-pulse: this entry goes (its ring too), so the gone part is not kept.
				pulse.handle = nil
				stopMatPulse(pulse)
				if matPulses[pulse.part] == pulse then
					matPulses[pulse.part] = nil
				end
				return false
			end
			local color, done = SqueezeController.matPulseColor((clock - pulse.startedAt) * 1000)
			pulse.part.Color = color
			if done then
				pulse.handle = nil
				return false
			end
			return true
		end, "render")
	end
end

-- Feel: "+N" above the squishy (§18.5.1 A4) ---------------------------------------------------------------------------

local function clientFxFolder(): Instance
	local folder = Workspace:FindFirstChild("SD_ClientFx")
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = "SD_ClientFx"
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

-- A pool popup, built as a Coins "+N". Its line sits at the top of the BillboardGui (the gui is made taller to lift it,
-- floatLine), so it pops around its own centre.
local function buildCoinPopup(): CoinPopup
	local gui = Instance.new("BillboardGui")
	gui.Name = POPUP_GUI
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ClipsDescendants = false
	gui.Size = UDim2.fromOffset(COIN_POPUP.widthPx, COIN_POPUP.heightPx)
	gui.StudsOffsetWorldSpace = Vector3.new(0, COIN_POPUP.startStuds, 0)
	gui.Enabled = false
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, COIN_POPUP.heightPx / 2),
		Size = UDim2.new(1, 0, 0, COIN_POPUP.heightPx),
		Parent = gui,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = content
	Theme.list(Enum.FillDirection.Horizontal, Theme.Padding.small, content)
	local icon = CoinIcon.new({ name = "CoinIcon", sizePx = COIN_POPUP.iconPx, layoutOrder = 1, parent = content })
	local label = Theme.label({
		Name = "Amount",
		LayoutOrder = 2,
		Size = UDim2.fromOffset(0, COIN_POPUP.heightPx),
		AutomaticSize = Enum.AutomaticSize.X,
		TextWrapped = false,
		Parent = content,
	}, "HudNumber")
	local stroke = Theme.stroke(Palette.White, Theme.Stroke.medium, label)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	-- The fade writes every visible transparency from its built value toward 1.
	local fades: { FadeTarget } = {}
	local function fadeOf(object: Instance, property: string, base: number)
		table.insert(fades, { object = object, property = property, base = base })
	end
	for _, descendant in content:GetDescendants() do
		if descendant:IsA("TextLabel") then
			fadeOf(descendant, "TextTransparency", descendant.TextTransparency)
		elseif descendant:IsA("ImageLabel") then
			fadeOf(descendant, "ImageTransparency", descendant.ImageTransparency)
		elseif descendant:IsA("Frame") and descendant.BackgroundTransparency < 1 then
			fadeOf(descendant, "BackgroundTransparency", descendant.BackgroundTransparency)
		elseif descendant:IsA("UIStroke") then
			fadeOf(descendant, "Transparency", descendant.Transparency)
		end
	end
	gui.Parent = clientFxFolder()
	return {
		gui = gui,
		scale = scale,
		label = label,
		icon = icon.root,
		stroke = stroke,
		kind = "coins",
		fades = fades,
		startedAt = nil,
		reduced = false,
	}
end

-- Gives a pool popup the look of its kind (lobby HUD spec 2026-10-11 §2): "+N" keeps the coin icon and the InkUI
-- number with the white outline (A4); a Grip line is the Mint numeral (popupColor) with the InkUI outline (the old
-- station panel's lines).
local function stylePopup(popup: CoinPopup, kind: PopupKind)
	if popup.kind == kind then
		return
	end
	popup.kind = kind
	local coins = kind == "coins"
	popup.icon.Visible = coins
	popup.label.TextColor3 = if coins then Theme.Colors.inkUI else SqueezeController.popupColor(kind)
	popup.label.TextSize = Theme.textSize("HudNumber")
	popup.stroke.Color = if coins then Palette.White else Theme.Colors.inkUI
	popup.stroke.Thickness = if coins then Theme.Stroke.medium else Theme.Stroke.text
end

local function setFade(popup: CoinPopup, fade: number)
	for _, target in popup.fades do
		(target.object :: any)[target.property] = target.base + (1 - target.base) * fade
	end
end

-- One frame of every live popup (one Scheduler effect while any runs).
local function stepCoinPopups(_dt: number, now: number): boolean
	local live = false
	for _, popup in coinPopups do
		local started = popup.startedAt
		if started == nil then
			continue
		end
		local sample = SqueezeController.coinPopupSample(now - started, popup.reduced)
		local adornee: Instance? = popup.gui.Adornee
		if sample.done or adornee == nil or adornee.Parent == nil then
			popup.startedAt = nil
			popup.gui.Enabled = false
			(popup.gui :: any).Adornee = nil -- the engine type has no optional Adornee
			continue
		end
		live = true
		popup.gui.StudsOffsetWorldSpace = Vector3.new(0, sample.offsetY, 0)
		popup.scale.Scale = sample.scale
		setFade(popup, sample.fade)
	end
	if not live then
		popupsHandle = nil
	end
	return live
end

-- The local held model's Root, else the HumanoidRootPart (A4).
local function popupAdornee(): BasePart?
	local player = localPlayer()
	if player == nil then
		return nil
	end
	local model = HeldSquishyController.getModel(player)
	local root = if model and HeldSquishyController.isHolding(player) then model.PrimaryPart else nil
	return root or localRoot()
end

-- Floats one line of `kind` up from the squishy (A4; lobby HUD spec 2026-10-11 §2: the Grip lines too, from the one
-- pool): `amount` as lineText words it. It starts above the floating label (lineLiftPx). A reply within
-- foldSeconds("coins") of the newest line of its kind on the same model, with the same doubling, adds its amount to
-- that line's number (its rise goes on), so a burst of replies never reuses a slot before its popup ends (a review
-- fix from the every-click-pays days, against the old snap back to the start at full opacity; with the Batch 1 paid
-- cap a click burst still brings its 2 replies at once, which fold into one line). The amounts shown are unchanged in
-- total.
-- First person (spec 2026-10-11 §3.8): while a look is on, the line floats at the overlay toy instead (the held model
-- is hidden); a reply within half its float (foldSeconds("grip"), a floating line's window) folds into it. Inline
-- requires: this module adds no top-level local, and neither controller requires it back.
local function floatLine(kind: PopupKind, amount: number, doubled: boolean)
	local now = os.clock()
	local fold = lineFolds[kind]
	local l = floatLabel
	local point = if l and require(script.Parent.FirstPersonController).look() ~= nil
		then require(script.Parent.ViewmodelController).toyScreenPoint()
		else nil
	if l and point then
		local foldLabel = if fold then fold.label else nil
		if
			fold ~= nil
			and foldLabel ~= nil
			and foldLabel.Parent ~= nil
			and fold.doubled == doubled
			and SqueezeController.foldsInto(fold.startedAt, now, SqueezeController.foldSeconds("grip"))
		then
			fold.amount += amount
			foldLabel.Text = SqueezeController.lineText(kind, fold.amount, doubled, true)
			return
		end
		local inset = (game:GetService("GuiService"):GetGuiInset())
		local at = SqueezeController.hudOffsetOf(point, inset, l.overlay.AbsolutePosition, UIController.scale())
		local label = showOverlayLine(SqueezeController.lineText(kind, amount, doubled, true), kind, at)
		lineFolds[kind] = { index = 0, amount = amount, doubled = doubled, label = label, startedAt = now }
		return
	end
	local adornee = popupAdornee()
	if adornee == nil then
		return
	end
	local newest = if fold and fold.index > 0 then coinPopups[fold.index] else nil
	if
		fold ~= nil
		and newest ~= nil
		and newest.kind == kind
		and newest.gui.Adornee == adornee
		and fold.doubled == doubled
		and SqueezeController.foldsInto(newest.startedAt, now, SqueezeController.foldSeconds("coins"))
	then
		fold.amount += amount
		newest.label.Text = SqueezeController.lineText(kind, fold.amount, doubled, false)
		return
	end
	local startedAts: { [number]: number } = {}
	for index, popup in coinPopups do
		if popup.startedAt ~= nil then
			startedAts[index] = popup.startedAt :: number
		end
	end
	local index = SqueezeController.popupSlot(startedAts, SqueezeController.POPUP_POOL)
	local popup = coinPopups[index]
	if popup == nil then
		popup = buildCoinPopup()
		coinPopups[index] = popup
	end
	local reduced = Tweens.reducedMotion()
	stylePopup(popup, kind)
	popup.startedAt = now
	popup.reduced = reduced
	popup.label.Text = SqueezeController.lineText(kind, amount, doubled, false)
	-- Lifted above the label (in px, as the label): the gui grows by twice the lift with the line at its top.
	local lift = SqueezeController.lineLiftPx(kind, if l and labelShown then l.px else 0)
	local width = if kind == "coins" then COIN_POPUP.widthPx else LINE_WIDTH
	popup.gui.Size = UDim2.fromOffset(width, COIN_POPUP.heightPx + 2 * lift)
	popup.gui.Adornee = adornee
	local first = SqueezeController.coinPopupSample(0, reduced)
	popup.gui.StudsOffsetWorldSpace = Vector3.new(0, first.offsetY, 0)
	popup.scale.Scale = first.scale
	setFade(popup, 0)
	popup.gui.Enabled = true
	lineFolds[kind] = { index = index, amount = amount, doubled = doubled }
	if popupsHandle == nil then
		popupsHandle = Scheduler.add(stepCoinPopups, "render")
	end
end

-- The floating label ----------------------------------------------------------------------------------------------

-- The pad the local root stands on, or nil (spec 2026-10-11 §5: the server's own test, WorldLayout.stationUnder with
-- Config.Squeeze's padMargin / heightAbove, so the label shows the boost exactly where the server pays it).
local function updateStation()
	local root = localRoot()
	local station: WorldLayout.Station? = nil
	if root then
		station = WorldLayout.stationUnder(root.Position, Config.Squeeze.padMargin, Config.Squeeze.heightAbove)
	end
	currentStation = station
end

-- Shows or hides the floating label (labelShownFor) on the held model's Root and keeps its text (panelLabel) and its
-- px size (labelSize) current. Built once (buildLabel): only Enabled, Adornee, the text and the size change.
-- Never shown while Config.Squeeze.floatingLabel is false (off since 2026-10-15).
local function refreshLabel()
	local l = floatLabel
	if l == nil then
		return
	end
	local player = localPlayer()
	local model = if player then HeldSquishyController.getModel(player) else nil
	local root = if model then model.PrimaryPart else nil
	local shown = Config.Squeeze.floatingLabel
		and SqueezeController.labelShownFor({
			holding = root ~= nil and player ~= nil and HeldSquishyController.isHolding(player),
			inMatch = inMatch(),
			lobbyLocked = StateController.isLobbyLocked(),
			blocked = ControlsController.isBlocked(),
			firstPerson = require(script.Parent.FirstPersonController).look() ~= nil,
		})
	labelShown = false
	if not shown or root == nil then
		l.gui.Enabled = false
		local gui: any = l.gui -- the engine type has no optional Adornee
		if gui.Adornee ~= nil then
			gui.Adornee = nil -- a gone model's Root is never kept
		end
		return
	end
	if l.gui.Adornee ~= root then
		l.gui.Adornee = root
	end
	local line = SqueezeController.panelLabel(StateController.get("pen"))
	if l.text.Text ~= line then
		l.text.Text = line
		l.text.TextSize = Theme.textSize("Chip")
		local size = SqueezeController.labelSize(Theme.textBounds(line, "Chip"))
		-- The chip fills the gui's top half, so its bottom sits on the gui's centre: the anchor above the Root.
		l.chip.Size = UDim2.fromOffset(size.X, size.Y)
		l.gui.Size = UDim2.fromOffset(size.X, 2 * size.Y)
		l.px = size.Y
	end
	labelShown = line ~= ""
	l.gui.Enabled = labelShown
end

-- Sending and holding -----------------------------------------------------------------------------------------------

local function stopHold(reason: StopReason)
	if hold == nil then
		return
	end
	hold = nil
	lastStopReason = reason
	if PAUSE_TOAST[reason] then
		NotifyController.show(NOTICE_HOLD_PAUSED, nil, "info")
	end
end

-- Sends one SqueezeRequest if it is due (a fresh press always is; a hold repeat follows sendDue) and the client is
-- under the paid-squeeze cap (underCap); anywhere in the lobby (spec 2026-10-11 §5: the server finds the pad).
-- Plays the local squeeze at once (it restarts from the top on every press). Returns true when it was sent.
-- Auto-clicker check (2026-10-16): a fresh press over the cap is still sent while pressSendable (it pays nothing and
-- shows no "+N": the server only times it); one past that, or a hold repeat over the cap, only squishes on screen.
local function trySend(fresh: boolean): boolean
	local now = serverNow()
	if now < SqueezeController.sendDue(sendState, fresh, HOLD) then
		return false
	end
	local clock = os.clock()
	if
		not SqueezeController.underCap(recentSends, clock, CAP, CAP_WINDOW)
		and not (fresh and SqueezeController.pressSendable(pressSends, clock, waitingSince, PRESS_CAP, STALL_SECONDS))
	then
		if fresh then
			SqueezeController.playLocal()
		end
		return false
	end
	if not NetController.squeezeRequest() then
		return false
	end
	table.insert(recentSends, clock)
	while #recentSends > CAP do
		table.remove(recentSends, 1)
	end
	table.insert(pressSends, clock)
	while #pressSends > PRESS_CAP do
		table.remove(pressSends, 1)
	end
	if waitingSince == nil then
		waitingSince = clock
	end
	sendState.lastSendAt = now
	sendState.replied = false
	sends += 1
	SqueezeController.playLocal()
	return true
end

local function isHeld(h: Hold): boolean
	if h.source == "keyboard" then
		local key = h.keyCode
		return key ~= nil and UserInputService:IsKeyDown(key)
	elseif h.source == "gamepad" then
		local key, pad = h.keyCode, h.gamepad
		return key ~= nil and pad ~= nil and UserInputService:IsGamepadButtonDown(pad, key)
	elseif h.source == "mouse" then
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	elseif h.source == "touch" then
		local input, from = h.input, h.from
		return input ~= nil
			and from ~= nil
			and SqueezeController.touchHeld(
				input.UserInputState,
				from,
				input.Position,
				Config.Inspect.Input.tapMaxPixels
			)
	end
	return virtualHeld
end

-- A fresh press (Begin): starts (or restarts) the hold and squeezes at once on screen; sends (and pays) while under the
-- paid cap, anywhere.
local function freshPress(press: PressInput): boolean
	local now = os.clock()
	hold = {
		source = press.source,
		keyCode = press.keyCode,
		gamepad = press.gamepad,
		input = press.input,
		from = press.from,
		startedAt = now,
		freshAt = now,
	}
	trySend(true)
	return true
end

-- Ends the hold a release belongs to: any hold for a nil source; else one of that source, and a click's or a touch's
-- only for its own finger (buttonReleases: the pressing touch wherever it lifts, any left mouse release).
local function release(source: HoldSource?, input: InputObject?)
	local h = hold
	if h == nil or (source ~= nil and h.source ~= source) then
		return
	end
	local pressed = h.input
	if input and pressed and not SqueezeController.buttonReleases(true, pressed, input, input.UserInputType) then
		return
	end
	stopHold("released")
end

local function onAction(inputState: Enum.UserInputState, input: InputObject?): boolean?
	if inputState == Enum.UserInputState.Begin then
		local press = SqueezeController.pressOf(input)
		-- A key waits while another prompt shows (the prompt gets E / ButtonX); a click or a tap on the world never does.
		if promptShown() and press.source ~= "mouse" and press.source ~= "touch" then
			return false
		end
		return freshPress(press)
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		local press = if input then SqueezeController.pressOf(input) else nil
		release(if press then press.source else nil, if press then press.input else nil)
	end
	return false
end

local function holdCheck(h: Hold): HoldCheck
	local now = os.clock()
	return {
		held = isHeld(h),
		heldFor = now - h.startedAt,
		sinceFresh = now - h.freshAt,
		inMatch = inMatch(),
		lobbyLive = ControlsController.isContextActive("Lobby"),
		blocked = ControlsController.isBlocked(),
		queued = StateController.queue().state == "Searching",
	}
end

local function step(dt: number)
	stationClock += dt
	if stationClock >= STATION_CHECK_SECONDS then
		stationClock = 0
		updateStation()
		refreshLabel()
	end
	local h = hold
	if h then
		local reason: StopReason? = SqueezeController.holdStopReason(holdCheck(h), HOLD)
		if reason then
			stopHold(reason)
		else
			trySend(false)
		end
	end
end

local function onResult(raw: unknown)
	local result = SqueezeController.normalizeResult(raw)
	if result == nil then
		return
	end
	lastResult = result
	sendState.replied = true
	waitingSince = nil -- a reply came: no stall (pressSendable)
	local nextAt = result.nextAt
	if nextAt then
		sendState.nextAt = nextAt
	end
	if result.ok then
		-- A4 (lobby HUD spec §2: the Grip line too): "+N" when Coins > 0, "+N Grip" / "+N Grip (xM)" when Grip > 0.
		if result.coins > 0 then
			floatLine("coins", result.coins, false)
		end
		if result.grip > 0 then
			floatLine("grip", result.grip, result.doubled)
		end
		-- A3: the own mat pulses (the station under the player now).
		local stationId = SqueezeController.currentStationId()
		local root = localRoot()
		if stationId and root then
			pulseMat(stationId, root.Position)
		end
	else
		SqueezeFeel.reject(result.reason) -- A2: any rejection but squeeze.tooFast ends the streak
	end
	if not result.ok and result.reason ~= REASON_TOO_FAST then
		stopHold("rejected")
		-- A code without a text still says something (error.generic), as Strings.reasonText would.
		local code = result.reason
		local known = code ~= nil and (Strings.resolve("reason." .. code) ~= nil or Strings.resolve(code) ~= nil)
		NotifyController.show(if known then code :: string else REASON_GENERIC, nil, "info")
	end
	SqueezeController.ResultReceived:fire(result)
end

-- Other players -------------------------------------------------------------------------------------------------

local function onOtherSqueeze(player: Player, character: Model)
	local at = character:GetAttribute(ATTR_SQUEEZE_AT)
	if not finite(at) or serverNow() - (at :: number) > OTHERS_MAX_AGE_SECONDS then
		return
	end
	local root = rootOf(character)
	local viewer = localRoot()
	local from = if viewer
		then viewer.Position
		elseif Workspace.CurrentCamera then (Workspace.CurrentCamera :: Camera).CFrame.Position
		else nil
	if root == nil or from == nil then
		return
	end
	local distance = (root.Position - from).Magnitude
	if distance > OTHERS_CULL_STUDS then
		return
	end
	-- A1: 4 puffs within 40 studs, none farther out (the animation still plays to othersCullStuds).
	SqueezeController.play(player, { particles = SqueezeController.othersPuffs(distance), other = true })
	-- A3: their Foam Mat pulses too, within the same 40 studs.
	if distance <= EFFECTS.othersSqueezeStuds then
		local station = WorldLayout.nearestStation(root.Position, STATION_RADIUS + Config.Squeeze.radiusTolerance)
		if station then
			pulseMat(station.id, root.Position)
		end
	end
end

local function unwatchPlayer(player: Player)
	local unwatch = watchers[player]
	if unwatch then
		watchers[player] = nil
		unwatch()
	end
end

local function watchPlayer(player: Player)
	if player == localPlayer() or watchers[player] ~= nil then
		return
	end
	local characterConnection: RBXScriptConnection? = nil
	local function bind(character: Model?)
		if characterConnection then
			characterConnection:Disconnect()
			characterConnection = nil
		end
		if character then
			characterConnection = character:GetAttributeChangedSignal(ATTR_SQUEEZE_AT):Connect(function()
				onOtherSqueeze(player, character)
			end)
		end
	end
	local added = player.CharacterAdded:Connect(bind)
	bind(player.Character)
	watchers[player] = function()
		added:Disconnect()
		bind(nil)
	end
end

-- UI -------------------------------------------------------------------------------------------------------------

-- Builds the floating label (lobby HUD spec 2026-10-11 §2) once, hidden: a BillboardGui in Workspace.SD_ClientFx (made
-- here, so only this player sees it) holding the nameplates' foam chip with the Chip text, and the full-HUD frame for
-- the lines at the first-person toy (spec 2026-10-11 §3.8: no input, never hidden).
local function buildLabel(c: Cleanup.Cleanup)
	local overlay: Frame = Create("Frame", {
		Name = "SqueezeOverlayPopups",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Interactable = false,
		Parent = UIController.screenGui(HUD_GUI),
	})
	c:add(overlay)
	local gui: BillboardGui = Create("BillboardGui", {
		Name = "SD_SqueezeLabel",
		AlwaysOnTop = true,
		LightInfluence = 0,
		ClipsDescendants = false,
		Active = false,
		StudsOffsetWorldSpace = Vector3.new(0, COIN_POPUP.startStuds, 0),
		Enabled = false,
	})
	-- The chip fills the gui's top half (refreshLabel sizes both), so its bottom sits on the anchor.
	local chip: Frame = Create("Frame", {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		BackgroundColor3 = Theme.Colors.frosting,
		BorderSizePixel = 0,
		Parent = gui,
	})
	local bands = Theme.Foam.chip
	Theme.foam(chip, {
		radius = Theme.Radius.chip,
		stroke = Theme.Stroke.bar,
		mode = "tint",
		bevel = bands.bevel,
		drop = bands.drop,
		-- Candy UI (2026-10-11): a light sticker in the world, dark text.
		colors = Theme.stickerColors(),
	})
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, Theme.Padding.medium),
		PaddingRight = UDim.new(0, Theme.Padding.medium),
		PaddingTop = UDim.new(0, Theme.Padding.small),
		PaddingBottom = UDim.new(0, Theme.Padding.small + bands.bevel + bands.drop),
		Parent = chip,
	})
	local label = Theme.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = chip,
	}, "Chip", nil, Theme.Colors.inkUI)
	gui.Parent = clientFxFolder()
	c:add(gui)
	floatLabel = { overlay = overlay, gui = gui, chip = chip, text = label, px = 0 }
	c:add(function()
		floatLabel = nil
		labelShown = false
	end)
	refreshLabel()
end

-- Public: pure helpers (unit-tested) --------------------------------------------------------------------------------

-- §17.3.2 (Batch 1 #2: squeezes pay up to the hold rhythm): the server time at which the next SqueezeRequest may go
-- out. A fresh press goes at once (-math.huge: it never waits for a reply, the server's nextAt or the hold rhythm; only
-- underCap and, over the cap, pressSendable can hold it back). A hold repeat goes at max(nextAt + leadSeconds,
-- lastSend + repeatSeconds): one full squeeze animation per repeat (Config.Grip.Hold.repeatSeconds), later only while
-- the cap's bucket is empty. While the
-- reply to the last send is missing, a hold repeat waits until lastSend + repeatSeconds + replyGraceSeconds (a
-- flood-guard drop has no reply, so the hold never stalls).
-- Reading: DESIGN's "max(nextAt, serverNow) + 0.05 s" is evaluated every frame, so "serverNow + 0.05" would never be
-- reached; the lead is added to nextAt (a token still missing) and the repeat floor covers the case where a token is
-- already there.
function SqueezeController.sendDue(s: SendState, fresh: boolean, hold: HoldConfig): number
	local last = s.lastSendAt
	if fresh or last == nil then
		return -math.huge
	end
	if not s.replied then
		return last + hold.repeatSeconds + hold.replyGraceSeconds
	end
	return math.max(s.nextAt + hold.leadSeconds, last + hold.repeatSeconds)
end

-- The client side of the server's paid-squeeze cap: true when a send at `now` keeps fewer than
-- `capacity` sends inside the last `windowSeconds` (`sentAt` = the clock times of the recent sends; one exactly
-- windowSeconds old is out). With Config.Squeeze's bucketCapacity in bucketCapacity × cycleSeconds (2 in 0.9 s) the
-- client stays inside the server's bucket (2 at once, then 1 per 0.45 s) and far below its flood guard (20/s).
function SqueezeController.underCap(sentAt: { number }, now: number, capacity: number, windowSeconds: number): boolean
	local inWindow = 0
	local after = now - windowSeconds + CAP_EDGE_SECONDS
	for _, at in sentAt do
		if at > after then
			inWindow += 1
		end
	end
	return inWindow < capacity
end

-- Auto-clicker check (2026-10-16): whether a fresh press over the paid cap is still sent (it pays nothing; the server
-- times the presses, server AutoClickService): fewer than `capacity` sends inside the last second (`sentAt`, the clock
-- times of the recent sends; Config.Net.AutoClick.clientPressesPerSecond, under the server's flood guard) and no reply
-- late: `waitingSince` (the clock time of the first send since the last reply, nil when none waits) at most
-- `stallSeconds` ago. In a network stall the presses would queue up and arrive at once, over the remote's limits.
function SqueezeController.pressSendable(
	sentAt: { number },
	now: number,
	waitingSince: number?,
	capacity: number,
	stallSeconds: number
): boolean
	if waitingSince ~= nil and now - waitingSince > stallSeconds then
		return false
	end
	return SqueezeController.underCap(sentAt, now, capacity, 1)
end

-- Review fix (2026-10-16, job autoclick): pressSendable's capacity: `rules.clientPressesPerSecond` while the check is
-- on (rules.enabled and no `problems` from Config/ValidateAutoClick, the server's own check), else 0 (the off switch:
-- the server would only answer them squeeze.tooFast, so none is sent).
function SqueezeController.pressCap(
	rules: { enabled: boolean, clientPressesPerSecond: number },
	problems: { string }
): number
	return if rules.enabled == true and #problems == 0 then rules.clientPressesPerSecond else 0
end

-- §17.3.2: why a running hold must stop now, or nil to keep going (checked every frame and before every send). Where
-- the player stands never stops it (spec 2026-10-11 §5: squeeze anywhere).
function SqueezeController.holdStopReason(c: HoldCheck, hold: HoldConfig): StopReason?
	if not c.held then
		return "released"
	end
	if c.inMatch then
		return "match"
	end
	if not c.lobbyLive then
		return "context"
	end
	if c.blocked then
		return "blocked"
	end
	if c.heldFor >= hold.maxSeconds then
		return "maxTime"
	end
	if c.queued and c.sinceFresh >= hold.queuedSeconds then
		return "queued"
	end
	return nil
end

-- §17.12 Part 8 L5 (kept for the world click and touch, lobby HUD spec §2): whether an input that ended releases a
-- pointer hold. Only while it is held, only a touch or the left mouse button: a touch only when it is the finger that
-- pressed (Roblox keeps one InputObject per touch from Begin to End and reports it wherever the finger lifts; another
-- finger lifting never releases it); any left mouse release does. A press with no recorded input (nil) is released by
-- any of them.
function SqueezeController.buttonReleases(held: boolean, pressed: any?, ended: any, kind: Enum.UserInputType): boolean
	if not held then
		return false
	end
	if kind == Enum.UserInputType.MouseButton1 then
		return true
	end
	if kind ~= Enum.UserInputType.Touch then
		return false
	end
	return pressed == nil or pressed == ended
end

-- Whether a pointer hold still counts as held: its flag is set and the pressing input's UserInputState (nil when
-- unknown) is not End or Cancel (a cancelled touch may never send its end, §17.12 Part 8 L5).
function SqueezeController.buttonStillDown(held: boolean, state: Enum.UserInputState?): boolean
	return held and state ~= Enum.UserInputState.End and state ~= Enum.UserInputState.Cancel
end

-- Which physical input pressed Squeeze (`input` nil for a virtual press): a key with its KeyCode, a gamepad button with
-- its gamepad, and (lobby HUD spec 2026-10-11 §2) a left click with its InputObject or a touch with its InputObject and
-- where it began (touchHeld). Anything else is a virtual press.
function SqueezeController.pressOf(input: any?): PressInput
	if input == nil then
		return { source = "virtual" }
	end
	local kind: Enum.UserInputType = input.UserInputType
	if kind == Enum.UserInputType.Keyboard then
		return { source = "keyboard", keyCode = input.KeyCode }
	end
	if string.sub(kind.Name, 1, 7) == "Gamepad" then
		return { source = "gamepad", keyCode = input.KeyCode, gamepad = kind }
	end
	if kind == Enum.UserInputType.MouseButton1 then
		return { source = "mouse", input = input }
	end
	if kind == Enum.UserInputType.Touch then
		return { source = "touch", input = input, from = input.Position }
	end
	return { source = "virtual" }
end

-- Lobby HUD spec 2026-10-11 §2: whether a world touch still holds its squeeze: its InputObject is not End or Cancel
-- (`state`, buttonStillDown) and it is less than `maxPixels` (Config.Inspect.Input.tapMaxPixels) from where it began
-- (`from`, `at`: InputObject.Position). Past that it is a camera drag: the hold ends (the first squeeze already
-- happened).
function SqueezeController.touchHeld(
	state: Enum.UserInputState?,
	from: Vector3,
	at: Vector3,
	maxPixels: number
): boolean
	local moved = Vector2.new(at.X - from.X, at.Y - from.Y).Magnitude
	return SqueezeController.buttonStillDown(true, state) and moved < maxPixels
end

-- Normalizes a SqueezeResult payload {ok, coins, total, limit, reason?, nextAt, grip, gripTotal, doubled} (§17.10),
-- or nil when it is malformed. Counts are floored; a non-finite nextAt is dropped.
function SqueezeController.normalizeResult(raw: unknown): Result?
	if type(raw) ~= "table" then
		return nil
	end
	local r = raw :: any
	if type(r.ok) ~= "boolean" then
		return nil
	end
	local function count(value: unknown): number?
		return if finite(value) and (value :: number) >= 0 then math.floor(value :: number) else nil
	end
	return {
		ok = r.ok,
		coins = count(r.coins) or 0,
		total = count(r.total),
		limit = if finite(r.limit) then r.limit else nil,
		reason = if type(r.reason) == "string" and r.reason ~= "" then r.reason else nil,
		nextAt = if finite(r.nextAt) then r.nextAt else nil,
		grip = count(r.grip) or 0,
		gripTotal = count(r.gripTotal),
		doubled = r.doubled == true,
	}
end

-- The words of a floating line (§6.3, §17.7): Coins "+N" above the squishy (common.plusAmount: the coin icon says what
-- it is) or "+N Coins" at the first-person toy (`overlay`, common.coinsGain); Grip "+N Grip" or "+N Grip (x{mult})"
-- when doubled (Config.Grip.Rested.mult). Amounts use Format.coins.
function SqueezeController.lineText(kind: PopupKind, amount: number, doubled: boolean, overlay: boolean): string
	local n = Format.coins(amount)
	if kind == "coins" then
		return if overlay then text("common.coinsGain", { coins = n }) else text("common.plusAmount", { n = n })
	end
	return if doubled then text("grip.popupDouble", { n = n, mult = RESTED_MULT }) else text("grip.popup", { n = n })
end

-- Lobby HUD spec 2026-10-11 §2: how far (px) above the floating label's anchor (its bottom, Vfx.CoinPopup.startStuds
-- above the held Root) a line of `kind` starts, as the height of its centre: above the label (`labelPx` tall, 0 while
-- it is hidden) and a Theme.Padding.small gap, half a line up so its bottom sits there, and Coins lowest, then Grip
-- POPUP_STEP_PX higher, so a reply's lines never start on each other.
function SqueezeController.lineLiftPx(kind: PopupKind, labelPx: number): number
	local above = if labelPx > 0 then labelPx + Theme.Padding.small else 0
	local steps = if kind == "coins" then 0 else 1
	return above + COIN_POPUP.heightPx / 2 + steps * POPUP_STEP_PX
end

-- Foam UI: the colour of a floating line (with the InkUI outline): Coins in CoinGold (the coin colour, used only for
-- Coins, §7.2), Grip in the UI Mint, anything else in Lilac (the old slow-training kind "afk"; none since Phase 6);
-- the line's words always say which it is. UI FINAL R2: the world floats (kept in the world, plan §4; the squeeze
-- button that anchors the design's floats stays removed, Q2) take the design's float colours: Grip the "+N Grip" mint
-- (H:704), anything else the float's default white (lib:255); Coins stay CoinGold.
function SqueezeController.popupColor(kind: string): Color3
	if kind == "coins" then
		return Palette.CoinGold
	elseif kind == "grip" then
		return Palette.StickerGripFloat
	end
	return Palette.White
end

-- Puffs for another player's squeeze `distance` studs from this client (§18.5.1 A1): Effects.othersSqueezePuffs
-- within Effects.othersSqueezeStuds, none farther out.
function SqueezeController.othersPuffs(distance: number): number
	if distance == distance and distance <= EFFECTS.othersSqueezeStuds then
		return EFFECTS.othersSqueezePuffs
	end
	return 0
end

-- How far a Foam Mat's colour has moved toward the pulse colour `tMs` after the trigger (§18.5.1 A3): up to
-- MatPulse.towardPulseColor in upMs (Quad Out), back to 0 over downMs (Quad In), 0 before and after.
function SqueezeController.matPulseMix(tMs: number): number
	local up, down = MAT_PULSE.upMs, MAT_PULSE.downMs
	local peak = MAT_PULSE.towardPulseColor
	if not (tMs > 0) or tMs >= up + down then
		return 0
	end
	if tMs < up then
		local u = tMs / up
		return peak * (1 - (1 - u) * (1 - u))
	end
	local u = (tMs - up) / down
	return peak * (1 - u * u)
end

-- A Foam Mat's colour `tMs` after the trigger, and whether the pulse is over: the base is always
-- Palette[SqueezeZone.matColor] (never read back from the part), lerped toward Palette[SqueezeZone.pulseColor].
function SqueezeController.matPulseColor(tMs: number): (Color3, boolean)
	local zone = WorldLayout.SqueezeZone
	local base = paletteColor(zone.matColor, Palette.White)
	local done = not (tMs < MAT_PULSE.upMs + MAT_PULSE.downMs)
	if done then
		return base, true
	end
	return base:Lerp(paletteColor(zone.pulseColor, base), SqueezeController.matPulseMix(tMs)), false
end

-- One frame of the "+N" popup `t` seconds after it appeared (§18.5.1 A4). Normal: StudsOffsetWorldSpace Y from
-- CoinPopup.startStuds up by Effects.coinPopupRiseStuds over Effects.coinPopupSeconds (Quad Out), UIScale
-- CoinPopup.popFrom -> 1 over popMs (Back Out), faded from fadeFromSeconds to the end. ReducedMotion: no rise and no
-- pop, shown POPUP_REDUCED_HOLD s, then faded within reducedMotionMaxFadeMs.
function SqueezeController.coinPopupSample(t: number, reduced: boolean): CoinPopupSample
	local start = COIN_POPUP.startStuds
	local time = if t == t then math.max(t, 0) else 0
	if reduced then
		local fadeSeconds = REDUCED_FADE_MS / 1000
		local fade = if time <= POPUP_REDUCED_HOLD
			then 0
			else math.clamp((time - POPUP_REDUCED_HOLD) / fadeSeconds, 0, 1)
		return { offsetY = start, scale = 1, fade = fade, done = time >= POPUP_REDUCED_HOLD + fadeSeconds }
	end
	local life = EFFECTS.coinPopupSeconds
	local x = math.clamp(time / life, 0, 1)
	local rise = EFFECTS.coinPopupRiseStuds * (1 - (1 - x) * (1 - x))
	local u = math.clamp(time * 1000 / COIN_POPUP.popMs, 0, 1) - 1
	local backOut = 1 + (BACK_OVERSHOOT + 1) * u * u * u + BACK_OVERSHOOT * u * u
	local fadeFrom = COIN_POPUP.fadeFromSeconds
	local fade = if time <= fadeFrom then 0 else math.clamp((time - fadeFrom) / (life - fadeFrom), 0, 1)
	return {
		offsetY = start + rise,
		scale = COIN_POPUP.popFrom + (1 - COIN_POPUP.popFrom) * backOut,
		fade = fade,
		done = time >= life,
	}
end

-- How long after the newest line of a kind a new reply folds into it instead of starting another line (a review fix
-- from the every-click-pays days; the paid cap's 2 replies at once still fold). "coins", every line above the
-- squishy (lobby HUD spec §2): one pool slot's share of a popup's
-- life (Effects.coinPopupSeconds / coinPopupMaxVisible = 0.2 s), so a slot is never reused before its popup has
-- ended; "grip", a line at the first-person toy: half its float (coinCounter.floatMs / 2 = 0.35 s), so the line before
-- has risen 3/4 of floatPx and faded 3/4 of the way when the next one starts below it.
function SqueezeController.foldSeconds(kind: PopupKind): number
	if kind == "coins" then
		return EFFECTS.coinPopupSeconds / math.max(1, EFFECTS.coinPopupMaxVisible)
	end
	return FLOAT.floatMs / 1000 / 2
end

-- Whether a reply at `now` folds into the newest line of its kind, started at `newestAt` (nil = none showing): while
-- that line is younger than `windowSeconds` (foldSeconds). A fold adds the amount to that line's number and leaves its
-- motion alone, so the amounts shown are unchanged in total; only fewer lines carry them.
function SqueezeController.foldsInto(newestAt: number?, now: number, windowSeconds: number): boolean
	return newestAt ~= nil and now >= newestAt and now - newestAt < windowSeconds
end

-- The pool slot for a new "+N" (§18.5.1 A4): `startedAts[i]` is the start of the popup in slot i while it shows (nil
-- when the slot is free or unbuilt). The first free slot of `max`, else the oldest one (it is reused).
function SqueezeController.popupSlot(startedAts: { [number]: number }, max: number): number
	local oldest, oldestAt = 1, math.huge
	for index = 1, math.max(1, max) do
		local startedAt = startedAts[index]
		if startedAt == nil then
			return index
		end
		if startedAt < oldestAt then
			oldest, oldestAt = index, startedAt
		end
	end
	return oldest
end

-- Lobby HUD spec 2026-10-11 §2: whether the floating label shows on the held squishy: while holding, out of a match,
-- with the lobby unlocked, no screen open (no block) and no first-person look (the held model is hidden then).
function SqueezeController.labelShownFor(c: LabelFacts): boolean
	return c.holding and not c.inMatch and not c.lobbyLocked and not c.blocked and not c.firstPerson
end

-- Lobby HUD spec 2026-10-11 §2: the floating label's chip size in px (a BillboardGui Offset size: the same on screen at
-- any distance) around its text's bounds (Theme.textBounds, the Chip kind), as the nameplates': Theme.Padding.medium
-- and the chip outline on each side, Theme.Padding.small and the outline above and below plus the chip's foam bands
-- under the text. A bad measure gives the empty chip.
function SqueezeController.labelSize(textBounds: Vector2): Vector2
	local x = if finite(textBounds.X) and textBounds.X > 0 then math.ceil(textBounds.X) else 0
	local y = if finite(textBounds.Y) and textBounds.Y > 0 then math.ceil(textBounds.Y) else 0
	local bands = Theme.Foam.chip
	return Vector2.new(
		x + 2 * (Theme.Padding.medium + Theme.Stroke.bar),
		y + 2 * (Theme.Padding.small + Theme.Stroke.bar) + bands.bevel + bands.drop
	)
end

-- The floating label's text (named for the old squeeze panel's pad label): what one own squeeze pays for the `pen`
-- state field (pens3 phase 1), the same anywhere: grip.stationLabelBase with the whole Coins and Grip the server pays
-- at the pen's squeeze value (PenMath; a new player's 10 and 10 before the state arrives).
function SqueezeController.panelLabel(pen: any?): string
	return text("grip.stationLabelBase", {
		coins = Format.coins(PenMath.rewardCoins(1, PenMath.squeezeValue(pen))),
		grip = Format.coins(PenMath.squeezeGrip(pen)),
	})
end

-- Spec 2026-10-11 §3.8: the SD_Hud offset (base px under its UIScale `scale`) of a viewport point (the overlay toy's
-- ViewmodelController.toyScreenPoint, Camera:WorldToViewportPoint pixels): minus the GUI inset (GuiService:GetGuiInset,
-- the viewport -> AbsolutePosition step DuelController's reticle uses) and the HUD frame's AbsolutePosition `origin`.
function SqueezeController.hudOffsetOf(point: Vector2, inset: Vector2, origin: Vector2, scale: number): Vector2
	local s = if finite(scale) and scale > 0 then scale else 1
	return (point - inset - origin) / s
end

-- Public: the squeeze ---------------------------------------------------------------------------------------------

-- Plays the §9.6 squeeze on a player's held model: SqueezeFeel.play, a tap on its rig (the local player's for
-- prediction, others' from SD_SqueezeAt with opts = { particles = othersPuffs(distance), other = true }, §18.5.1 A1).
-- The local player's squeeze counts in the rhythm streak (A2) and always plays at once (a squeeze it cuts short merges
-- its release pop into this press). Returns false and a reason when it cannot play now ("noHeldModel"; "busy" for
-- another player's squeeze while theirs is before its release pop end).
function SqueezeController.play(player: Player, opts: PlayOptions?): (boolean, string?)
	return SqueezeFeel.play(player, opts)
end

-- Plays the squeeze on the local player's held model (prediction; DebugHooks "squeeze").
function SqueezeController.playLocal(): (boolean, string?)
	local player = localPlayer()
	if player == nil then
		return false, "noHeldModel"
	end
	return SqueezeController.play(player)
end

-- Public: station, popups, state ------------------------------------------------------------------------------------

-- The id of the pad the local player stands on (WorldLayout.stationUnder, as the server measures it), or nil.
function SqueezeController.currentStationId(): string?
	local station = currentStation
	return if station then station.id else nil
end

-- True while a hold-to-squeeze runs.
function SqueezeController.isHolding(): boolean
	return hold ~= nil
end

-- Studio (DebugHooks): a virtual hold where the player stands (anywhere in the lobby, spec 2026-10-11 §5) under the
-- same rules; false stops it at the next frame.
function SqueezeController.debugHold(on: boolean): (boolean, string?)
	if not on then
		virtualHeld = false
		return true, nil
	end
	updateStation()
	if not ControlsController.isActionLive(ACTION) then
		return false, "notLive"
	end
	virtualHeld = true
	freshPress({ source = "virtual" })
	return true, nil
end

-- Studio (DebugHooks): one fresh press and release where the player stands. Returns whether a request was sent.
function SqueezeController.debugPress(): (boolean, string?)
	updateStation()
	local before = sends
	virtualHeld = true
	freshPress({ source = "virtual" })
	virtualHeld = false
	release("virtual", nil)
	return sends > before, nil
end

-- Small table for Studio debug hooks and tests.
function SqueezeController.debugState(): { [string]: any }
	local feel = SqueezeFeel.debugState(localPlayer())
	local h = hold
	local result = lastResult
	local mats = 0
	for _ in matPulses do
		mats += 1
	end
	return {
		active = feel.active,
		squishyId = feel.squishyId,
		rarity = feel.rarity,
		tMs = feel.tMs,
		c = feel.c,
		w = feel.w,
		recovering = feel.recovering,
		station = SqueezeController.currentStationId(),
		promptShown = promptShown(),
		holding = h ~= nil,
		holdSource = if h then h.source else nil,
		heldFor = if h then os.clock() - h.startedAt else nil,
		lastStopReason = lastStopReason,
		sends = sends,
		recentSends = #recentSends, -- sends kept for the paid-squeeze cap (at most bucketCapacity)
		lastSendAt = sendState.lastSendAt,
		replied = sendState.replied,
		nextAt = sendState.nextAt,
		serverNow = serverNow(),
		lastResult = if result then table.clone(result) else nil,
		othersSqueezing = feel.othersSqueezing,
		matPulses = mats, -- Foam Mats with a pulse entry (at most the mats streamed in; leak check)
		labelShown = labelShown, -- lobby HUD spec §2: the floating label on the held squishy
		labelText = if floatLabel then floatLabel.text.Text else nil,
		popups = #coinPopups, -- "+N" pool slots built (at most POPUP_POOL; leak check)
	}
end

-- Lifecycle

function SqueezeController.init()
	PRESS_CAP = SqueezeController.pressCap(Config.Net.AutoClick, ValidateAutoClick(Config, Strings))
	local c = Cleanup.new()
	cleanup = c
	c:add(ControlsController.bindAction(ACTION, onAction))
	c:add(NetController.onSqueezeResult(onResult))
	c:add(ControlsController.BlockChanged:connect(function(blocked: boolean)
		if blocked then
			stopHold("blocked")
		end
		refreshLabel() -- a screen opened or closed: the label hides or comes back at once
	end))
	c:add(ControlsController.ContextChanged:connect(function(context: string, on: boolean)
		if context == "Lobby" and not on then
			stopHold("context")
		end
	end))
	c:add(UserInputService.WindowFocusReleased:Connect(function()
		stopHold("focus")
	end))
	c:add(ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = true
	end))
	c:add(ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		shownPrompts[prompt] = nil
	end))
	c:add(StateController.changed("grip"):connect(refreshLabel))
	c:add(StateController.changed("pen"):connect(refreshLabel)) -- pens3 phase 1: a new spot or squishy changes the pay
	-- The label follows the own held model (a rebuild on an equip or a respawn, or none).
	c:add(HeldSquishyController.HeldChanged:connect(function(player: Player)
		if player == localPlayer() then
			refreshLabel()
		end
	end))
	c:add(function()
		SqueezeFeel.clear() -- every squeeze stops, a fresh streak
		hold = nil
		currentStation = nil
		labelShown = false
		table.clear(shownPrompts)
		-- Feel pass: mats back to their colour, popups and their effect gone.
		for _, pulse in matPulses do
			stopMatPulse(pulse)
		end
		table.clear(matPulses)
		local handle = popupsHandle
		popupsHandle = nil
		if handle then
			handle:disconnect()
		end
		for _, popup in coinPopups do
			popup.gui:Destroy()
		end
		table.clear(coinPopups)
		table.clear(lineFolds)
		table.clear(recentSends)
		table.clear(pressSends)
		waitingSince = nil
	end)
end

function SqueezeController.start()
	local c = cleanup
	if c == nil then
		return
	end
	buildLabel(c)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	c:add(Players.PlayerAdded:Connect(watchPlayer))
	c:add(Players.PlayerRemoving:Connect(function(player: Player)
		unwatchPlayer(player)
		SqueezeFeel.forget(player)
	end))
	c:add(function()
		for player in table.clone(watchers) do
			unwatchPlayer(player)
		end
	end)
	c:add(RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(function(): any
			step(dt)
			return nil
		end)
		if not ok then
			-- Once per distinct error, so a lasting failure does not flood the output every frame.
			local message = tostring(err)
			if message ~= lastStepError then
				lastStepError = message
				log:error("squeeze step failed:", message)
			end
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function SqueezeController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return SqueezeController
