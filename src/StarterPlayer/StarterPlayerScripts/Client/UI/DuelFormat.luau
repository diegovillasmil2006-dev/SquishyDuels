--!strict
-- DuelFormat (client only, pure). DESIGN §5.2, §5.4, §5.9, §5.10, §9.14, §11.6: what the duel HUD and the result
-- panel show, as plain data, so it is unit-tested in Edit mode. Times are server times (GetServerTimeNow).
--   timerText(phase, phaseEndsAt, now, rules)   "m:ss": the time left in Active / SuddenDeath; the full match length
--                                               before Active; nil (hidden) from Result on
--   countdown(endsAt, now, seconds)             "3", "2", "1", then "Throw!" for one tick from the end, then nil
--   sideText / nameText / livesText             side labels (text, never colour alone), the opponent's name (a Studio
--                                               test dummy is always labelled "TEST DUMMY (Studio)"), "3 lives"
--   hintKeys(preferredInput, hasUltimate, squeeze?)   the bottom dock's keycaps (foam UI): the throw, ultimate, dash
--                                               and squeeze keys ("Click" / "Q" / "C" / "F", "R2" / "L2" / "B" / "X";
--                                               nil on touch); no ultimate key for a loadout without an ultimate, the
--                                               squeeze key only in first person (final polish 2026-10-11)
--   sideColors(side)                            a side's pip / icon colour and its top bar card's face (foam UI)
--   cooldownSeconds(squishyId, phase, rules)    the throw cooldown the server applies (clamp × sudden-death mult.)
--   progress(endsAt, now, duration)             0..1 fill of a cooldown bar
--   ultimateOf(squishyId) / chargeFraction      the locked loadout's ultimate (nil = none) and its meter
--   reticleText(aim, now)                       the reticle's state as text (ready / "0.4s" / rooted / can't throw)
--   pieRotations(progress)                      the two UIGradient rotations of the reticle's cooldown arc
--   forfeitNote(phase, phaseEndsAt, now, rules) what a forfeit does now: cancel (before 20 s of Active) or lose
--   result(payload, questName?)                 the result panel lines, from DuelResult only; `rewardNote` is the
--                                               reason that rides along with Coins that were paid (e.g. the same-pair
--                                               reduction duel.rewardsReduced, §6.7; reading, Part 5)
--   endPoses(outcome) / endPoseWeight(t, n)     §9.14 result poses (the winner cheers, a draw shrugs) and their weight
--   edgeArrow(point, viewport, margin)          the off-screen arrow to the opponent (position + rotation)
--   forfeitAllowed(phase) / isLive(phase)
-- Feel pass (§18.5.2 B6-B7, §18.6):
--   countdownCue(text)                          the sound and look of a countdown text: "3" / "2" / "1" -> a
--                                               duel.countdownTick at 1.00 / 1.06 / 1.12 with its bubble colour
--                                               (Strawberry / Lemon / Mint) and tilt (-6° / +6°, alternating);
--                                               "Throw!" -> duel.go at pitch 1; anything else -> nil
--   resultStyle(outcome)                        the title's colour (VICTORY Lemon, DEFEAT Lavender, DRAW Sky, with an
--                                               Ink stroke), its pop size (DEFEAT softer), the jingle (duel.win /
--                                               duel.lose / duel.draw; none for cancelled / void) and the confetti
--                                               (18 on a win, 6 on a draw, none otherwise)
--   rewardText(outcome, coins)                  the reward line for a count-up value ("+0 Coins (win)" ...)
--   popLook(t, from, ms, tiltDeg, reduced)      a pop: scale from -> 1 (Back Out) with a tilt tiltDeg -> 0
--   hitTextPop(t, sign, reduced)                "Hit!" (§18.4.2): 1.3 -> 1 in 200 ms, tilt ±6° -> 0
--   readyPop(t, reduced)                        READY and the opponent's ready chip (§18.5.2 B8): 1.3 -> 1, 220 ms
--   countdownLook(t, cue, reduced)              a countdown text's scale, tilt, fade and bubble at t (B6)
--   burstLook(t, reduced)                       the old bubble bursting when the next number arrives (B6)
--   lineLook(t, reduced)                        a result line fading in and sliding up (B7)
--   rewardCount(t, coins, reduced) / rewardPulse(t, reduced)   the reward count-up and its pulse (B7)
--   meterDrain(from, to, t)                     the ultimate meter draining when the charge is spent (§18.4.7)
-- Every look is 1 / no tilt under ReducedMotion (`reduced`); fades are then capped at reducedMotionMaxFadeMs.
-- Part 8 layout (§11.2, §11.6; base px under the ScreenGui UIScale, so 667×375 is a 785×441 canvas; unit-tested at
-- 667×375, 1280×720, 1920×1080 and the largest text):
--   topBarPlacement(screen, bar, avoid?)        where the top-centre bar (sides + timer) goes: centred on the top row,
--                                               moved right just enough to clear the top-left Forfeit button, or under
--                                               that button when the row has no room
--   resultLayout(screenH, contentH, chromeH)    the result panel's height and centre: its lines scroll when they do not
--                                               fit, the Queue again / Close row stays pinned under them, and the panel
--                                               stays on screen (centred 55% down when it can)
--   slideLook(t, px, ms, reduced)               the result panel's slide-in offset (Back Out; 0 under ReducedMotion)
--   countdownCenterY(screenH, barBottom, boxH)  the countdown's centre: 40% down the screen (as built), lower when
--                                               its bubble would reach the top bar (a phone, the largest text)
-- Overlays fix (2026-10-09; the dialogs never cut into the top bar, two rows a side card on phones):
--   sideCardWidth(input)                        the side cards' width on the compact layout, where the lives row also
--                                               holds the side icon and word: wide enough for it, capped so the bar
--                                               still fits beside the Forfeit button
--   panelBelowBar(screenH, barBottom, h, overhang, share)   the forfeit dialog's centre: under the top bar, or
--                                               clearsBar = false (the caller hides the bar while it shows)
--   resultLayout(..., barBottom?)               the result card starts under the top bar when its lines fit there
--                                               whole, else clearsBar = false
--   reticleLabelOffset(aimX, textW, screenW, scale, margin)   the reticle's state text moved in from a screen edge
-- Foam fix 2 (2026-10-09; look and layout only):
--   sideNeed(input)                             what a side card needs on either layout: its widest content (regular:
--                                               the name on one line or the lives row; compact: the lives row with
--                                               the side icon and word), from the texts' sizes, never the drawn rows
--                                               (a popping pip)
--   sideCardWidth(input)                        now on both layouts (the PC cards fit the opponent's whole name)
--   resultWait(koUntil, now, most)              how long the result card waits for the eliminator's "K.O.!" banner
--   result(...).questDone                       which quest lines this duel finished (the card marks them)
--   aimBlocked(objects)                         whether a reticle's point sits on a HUD button or an open dialog (the
--                                               duel and practice reticles hide there)
-- Feature 1 (2026-10-11, the charge throw and the catch; Config.UI.Reticle; design: the combat-effects page
-- "Squishy Combat FP v2.html"):
--   hintKeys(...)                               a fifth value: the catch key ("RMB/E" / "L1"; nil on touch, where the
--                                               Catch button shows instead)
--   reticleText(aim, now)                       "Your hands are busy." while the hands are open or crushing (throw.busy)
--   chargeLook(c, t, reduced)                   the reticle's charge fill (the cooldown pie's two rotations, filled to
--                                               c) and its scale: chargeFullScale + chargePulse·sin(rate·t) at full
--                                               (design: html:670-671), 1 under ReducedMotion
--   catchPrompt(key, t, reduced)                the "Catch!" prompt's text (with the catch key for the input) and its
--                                               text transparency (design: html:88, 674; steady under ReducedMotion)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local TimeUtil = require(Shared.Util.TimeUtil)
local Types = require(Shared.Types)

-- Types

export type ParticipantLike = { displayName: string, isTestDummy: boolean, side: Types.Side }

export type StatLine = { label: string, value: string }

-- The fields of ThrowController.AimState the reticle text reads (same state names).
export type AimStateName = "hidden" | "ready" | "cooling" | "blocked"
export type AimLike = { state: AimStateName, reason: string?, readyAt: number }

-- Optional: the display text of a quest (Part 7 QuestController); nil = progress only.
export type QuestNamer = (questId: string) -> string?

export type ResultModel = {
	outcome: string,
	title: string,
	reason: string?,
	stats: { StatLine },
	reward: string?,
	rewardCoins: number?, -- the paid Coins behind `reward` (the line counts up to it, §18.5.2 B7); nil when none
	rewardNote: string?, -- the reason shown under a paid reward (duel.rewardsReduced); nil otherwise
	quests: { string },
	questDone: { boolean }, -- foam fix 2: per quest line, whether this duel finished it
	tip: string?,
}

-- A countdown text's sound and look (§18.5.2 B6, §18.6).
export type CountdownCue = {
	key: string, -- the sound key
	pitch: number,
	digit: number?, -- 3, 2, 1 (nil for "Throw!")
	bubble: Color3?, -- the bubble behind a digit
	tiltDeg: number, -- the starting tilt (0 for "Throw!")
}

-- The result title's look and sound (§18.5.2 B7).
export type ResultStyle = {
	color: Color3?, -- title text colour; nil = Ink, no stroke (cancelled / void)
	popFrom: number,
	jingle: string?,
	confetti: number, -- 2D confetti pieces (UI/Confetti2D: WIN_COLORS on a win, DRAW_COLORS on a draw)
}

-- A rectangle in base px, in its ScreenGui's space (Part 8 layout).
export type Rect = { x: number, y: number, w: number, h: number }

-- Where the duel HUD's top bar goes (topBarPlacement).
export type TopBarPlacement = {
	x: number, -- the bar's centre
	y: number, -- its top
	row: "top" | "below", -- beside the Forfeit button, or under it
	fits: boolean, -- false: wider than the screen (centred anyway)
}

-- The result panel's size and place (resultLayout).
export type ResultLayout = {
	bodyHeight: number, -- the scrolling lines
	panelHeight: number,
	centerY: number, -- the panel's centre, from the top
	scrolls: boolean, -- the lines are taller than the body
	clearsBar: boolean, -- false: it does not fit under the given top bar (placed as if there were none)
}

-- What sideCardWidth reads (base px of SD_DuelHud).
export type SideWidthInput = {
	screenWidth: number,
	need: number, -- the wider side card's widest row, its paddings included
	minWidth: number, -- the regular card (DuelController SIDE_WIDTH)
	middle: number, -- the timer pill's width
	gap: number, -- between the cards and the timer
	avoid: Rect?, -- the Forfeit button while it shows
}

-- What sideNeed reads (base px of SD_DuelHud): one side card's content at rest.
export type SideNeedInput = {
	compact: boolean, -- the compact layout: the side word and icon join the lives row
	name: number, -- the name's one-line width
	word: number, -- the side word ("Strawberry side")
	lives: number, -- the "N lives" text
	pips: number, -- the pips' row, every dot at full size (Pips.rowWidth)
	icon: number, -- the side icon
	gap: number, -- between a row's items
	padding: number, -- the card's padding on each side
}

-- A countdown text's look at one moment (§18.5.2 B6).
export type CountdownLook = {
	textScale: number,
	rotation: number, -- degrees, for the number and its bubble
	textTransparency: number,
	bubbleScale: number,
	bubbleTransparency: number, -- 1 = no bubble ("Throw!")
	done: boolean, -- a digit: its pop is over (it stays until the next text); "Throw!": gone
}

-- Constants

local RULES = Config.Duel.Rules
local ABILITIES = Config.Abilities
local LIVE: { [string]: boolean } = { Active = true, SuddenDeath = true }
local BEFORE_ACTIVE: { [string]: boolean } = { Preparing = true, Positioning = true, Countdown = true }
local FORFEIT_PHASES: { [string]: boolean } =
	{ Preparing = true, Positioning = true, Countdown = true, Active = true, SuddenDeath = true }
local NO_STATS: { [string]: boolean } = { cancelled = true, void = true }
-- The countdown counts whole seconds; "Throw!" stays for one of those ticks (§9.14 gives no other length; reading).
local COUNTDOWN_TICK_SECONDS = 1
local PERCENT = 100
local EPSILON = 1e-9
local HALF_TURN = 180
local FULL_TURN = 360
-- ThrowController.AimState reason codes (§2.10 throw.*) with their own reticle text.
local REASON_ROOTED = "throw.rooted"
local REASON_DIRECTION = "throw.direction"
local REASON_BUSY = "throw.busy" -- feature 1: the hands are open for a catch or crushing a caught toy
local RETICLE = Config.UI.Reticle -- feature 1: the charge fill and the catch prompt
-- §9.14 result poses (Config.Anim.poses). Reading (DESIGN gives "2 spring bounces", no timing): the arms rise in
-- POSE_RISE_SECONDS, then dip POSE_DIP of the way down and back once per bounce, POSE_BOUNCE_SECONDS each, then hold.
local POSE_CHEER = "cheer"
local POSE_SHRUG = "shrug"
local POSE_RISE_SECONDS = 0.15
local POSE_BOUNCE_SECONDS = 0.4
local POSE_DIP = 0.45
-- Feel pass (§18.5.2 B6-B7, §18.6). Sound keys are written out so every wired key appears as a quoted string.
local TICK_SOUND = "duel.countdownTick"
local GO_SOUND = "duel.go"
local DUEL_ANIM = Config.Anim.duel
local COUNTDOWN_PITCH: { number } = Config.Audio.countdownPitch
-- Bubble colours by digit: 1 Mint, 2 Lemon, 3 (and any higher digit, reading) Strawberry.
local BUBBLE_COLORS: { [number]: Color3 } = { [1] = Palette.Mint, [2] = Palette.Lemon, [3] = Palette.Strawberry }
local RESULT_STYLES: { [string]: { color: Color3, jingle: string } } = {
	win = { color = Palette.Lemon, jingle = "duel.win" },
	loss = { color = Palette.Lavender, jingle = "duel.lose" },
	draw = { color = Palette.Sky, jingle = "duel.draw" },
}
local HIT = Config.Vfx.Hit
local READY_POP = Config.UI.motion.readyPop
local METER_DRAIN_MS = Config.Vfx.DragonRush.meterDrainMs
local MAX_FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local MS = 1000
-- reading (DESIGN: "pulses 1 -> 1.12 -> 1 (Back Out, 200 ms)"): the first PULSE_RISE of the time goes up (Quad Out),
-- the rest comes back (Back Out).
local PULSE_RISE = 0.3
local BACK = Enum.EasingStyle.Back
local QUAD = Enum.EasingStyle.Quad
local OUT = Enum.EasingDirection.Out
-- Part 8 layout (readings: DESIGN gives the areas, §11.6, not these numbers).
local LAYOUT_EDGE = 12 -- the HUD's distance from the screen edge (DuelController / HudController EDGE)
local LAYOUT_GAP = 8 -- between a placed panel and what it clears (HudController's row gap)
-- The top bar's width counts in steps of this, so the timer's changing digits never nudge a moved bar.
local BAR_WIDTH_STEP = 16
local RESULT_ANCHOR_Y = 0.55 -- the result panel's centre, 55% down the screen (as built since Part 4)
local RESULT_MARGIN = 12 -- the result panel keeps this far from the top and the bottom
local RESULT_MIN_BODY = Config.UI.Touch.minTarget -- the scrolling lines are never shorter than a touch target
local COUNTDOWN_ANCHOR_Y = 0.4 -- the countdown's centre, 40% down the screen (as built since Part 4)
-- Overlays fix (reading): the compact side cards' width counts in steps of this, so a slightly different measure never
-- nudges the bar.
local SIDE_WIDTH_STEP = 8
-- Foam fix 2 (reading): a side card keeps this much spare beside its measured content, so a rounded measure never cuts
-- the name with "…".
local SIDE_SPARE = 2

-- Module table

local DuelFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function rule(rules: { [string]: any }?, key: string): any
	local value = if rules then rules[key] else nil
	if value == nil then
		value = (RULES :: any)[key]
	end
	return value
end

local function ease(alpha: number, style: Enum.EasingStyle): number
	return TweenService:GetValue(math.clamp(alpha, 0, 1), style, OUT)
end

-- A fade's length (ms) under ReducedMotion: never above reducedMotionMaxFadeMs (§9.12, §9.13).
local function reducedFadeMs(ms: number): number
	return math.min(ms, MAX_FADE_MS)
end

local function resolveKey(key: unknown): string?
	if type(key) ~= "string" or key == "" then
		return nil
	end
	return Strings.resolve(key) or Strings.resolve("reason." .. key)
end

-- Public: phases

function DuelFormat.isLive(phase: string): boolean
	return LIVE[phase] == true
end

function DuelFormat.forfeitAllowed(phase: string): boolean
	return FORFEIT_PHASES[phase] == true
end

-- Public: HUD texts

function DuelFormat.timerText(phase: string, phaseEndsAt: number, now: number, rules: { [string]: any }?): string?
	if LIVE[phase] then
		return TimeUtil.formatCountdown(math.max(0, phaseEndsAt - now))
	elseif BEFORE_ACTIVE[phase] then
		return TimeUtil.formatCountdown(rule(rules, "MatchSeconds"))
	end
	return nil
end

function DuelFormat.countdown(endsAt: number, now: number, seconds: number): string?
	local remaining = endsAt - now
	if remaining > 0 then
		return tostring(math.clamp(math.ceil(remaining - EPSILON), 1, math.max(1, seconds)))
	elseif remaining > -COUNTDOWN_TICK_SECONDS then
		return Strings.duel.countdownGo
	end
	return nil
end

function DuelFormat.sideText(side: string): string
	return if side == "B" then Strings.duel.sideB else Strings.duel.sideA
end

function DuelFormat.nameText(participant: ParticipantLike): string
	if participant.isTestDummy then
		return Strings.duel.testDummy
	end
	return participant.displayName
end

-- "3 lives" / "1 life" next to the pips (§11.6 "life pips plus a number"); never below 0.
function DuelFormat.livesText(lives: number): string
	local n = if finite(lives) then math.max(0, math.floor(lives)) else 0
	return Strings.format(Strings.plural(n, Strings.duel.lives.one, Strings.duel.lives.many), { n = n })
end

-- The bottom dock's keycaps for "KeyboardAndMouse" / "Gamepad" (Enum.PreferredInput names): (throw key, ultimate key,
-- dash key, squeeze key, catch key), the keys of duel.hintMouse / hintGamepad drawn one beside each caption (foam UI).
-- All nil on touch (ControlsController's round buttons instead); the ultimate key is nil for a loadout without an
-- ultimate (its meter hides); final polish (2026-10-11): the squeeze key only when `squeeze` (first person:
-- DuelSqueeze squeezes the toy in the overlay's hands, nothing otherwise); feature 1 (2026-10-11): the catch key last,
-- so the callers that read four keys are unchanged.
function DuelFormat.hintKeys(
	preferred: string,
	hasUltimate: boolean,
	squeeze: boolean?
): (string?, string?, string?, string?, string?)
	local mouse = preferred == "KeyboardAndMouse"
	if not mouse and preferred ~= "Gamepad" then
		return nil, nil, nil, nil, nil
	end
	local keys = Strings.duel.key
	local throwKey = if mouse then keys.throwMouse else keys.throwGamepad
	local ultimateKey = if mouse then keys.ultimateMouse else keys.ultimateGamepad
	local dashKey = if mouse then keys.dashMouse else keys.dashGamepad
	local squeezeKey = if mouse then keys.squeezeMouse else keys.squeezeGamepad
	local catchKey = if mouse then keys.catchMouse else keys.catchGamepad
	return throwKey, if hasUltimate then ultimateKey else nil, dashKey, if squeeze then squeezeKey else nil, catchKey
end

-- A side's colours (§7.8; unchanged by the foam restyle, and never the only sign: the side text and icon go with
-- them): (pips, icon and off-screen arrow: Strawberry / Mint; the top bar card's face: Bubblegum / MintCream, where the
-- InkUI text keeps over 10:1). "B" is the Mint side, anything else the Strawberry side (like sideText).
function DuelFormat.sideColors(side: string): (Color3, Color3)
	if side == "B" then
		return Palette.Mint, Palette.MintCream
	end
	return Palette.Strawberry, Palette.Bubblegum
end

-- The reticle's state as text, never colour alone (§5.10): ready, the seconds left while cooling down, or why a throw
-- is blocked (rooted by Dragon Rush, a direction the server refuses, or the wrong place / phase). nil while hidden.
function DuelFormat.reticleText(aim: AimLike, now: number): string?
	if aim.state == "ready" then
		return Strings.duel.reticle.ready
	elseif aim.state == "cooling" then
		local left = if finite(aim.readyAt) then math.max(0, aim.readyAt - now) else 0
		return Strings.format(Strings.common.secondsShort, { seconds = string.format("%.1f", left) })
	elseif aim.state == "blocked" then
		if aim.reason == REASON_ROOTED then
			return Strings.duel.reticle.rooted
		elseif aim.reason == REASON_DIRECTION or aim.reason == REASON_BUSY then
			return Strings.reasonText(aim.reason :: string)
		end
		return Strings.duel.reticle.wrongZone
	end
	return nil
end

-- Feature 1: the reticle while charging: the pie's two rotations filled to c (pieRotations) and the reticle's scale,
-- chargeFullScale + chargePulse·sin(chargePulseRate·t) at full (design: html:670-671), 1 below full and under
-- ReducedMotion (no pulse; the full pie still shows it).
function DuelFormat.chargeLook(c: number, t: number, reduced: boolean): (number, number, number)
	local level = if finite(c) then math.clamp(c, 0, 1) else 0
	local right, left = DuelFormat.pieRotations(level)
	if reduced or level < 1 - EPSILON then
		return right, left, 1
	end
	local wave = if finite(t) then math.sin(RETICLE.chargePulseRate * t) else 0
	return right, left, RETICLE.chargeFullScale + RETICLE.chargePulse * wave
end

-- Feature 1: the "Catch!" prompt under the reticle (design: html:88, 674): its text, with the catch key for the active
-- input ("Catch! RMB/E"; just "Catch!" without one, on touch), and its text transparency t seconds after it appeared:
-- 1 - (catchPromptFrom + (1 - catchPromptFrom)·sin(2π·catchPromptHz·t)); steady (0) under ReducedMotion.
function DuelFormat.catchPrompt(key: string?, t: number, reduced: boolean): (string, number)
	local text = if key ~= nil and key ~= ""
		then Strings.format(Strings.duel.catchPromptKey, { key = key })
		else Strings.duel.catchPrompt
	if reduced or not finite(t) then
		return text, 0
	end
	local from = RETICLE.catchPromptFrom
	local opacity = from + (1 - from) * math.sin(2 * math.pi * RETICLE.catchPromptHz * t)
	return text, 1 - math.clamp(opacity, 0, 1)
end

-- The cooldown arc of the reticle as a clockwise pie from 12 o'clock: two half discs (right, left) each masked by a
-- UIGradient whose transparency is 0 on its first half and 1 on its second; rotating that gradient by r degrees
-- reveals r degrees of the right half (0..180) and then of the left half (180..360). Returns (rightDeg, leftDeg).
function DuelFormat.pieRotations(progress: number): (number, number)
	local p = if finite(progress) then math.clamp(progress, 0, 1) else 1
	local angle = p * FULL_TURN
	return math.min(angle, HALF_TURN), math.max(angle, HALF_TURN)
end

-- What a forfeit does right now (§5.2 rules 2 and 5, §5.4): before Active, or before EarlyForfeitSeconds of Active,
-- the duel is cancelled and the bailer waits BailRequeueCooldownSeconds; later the opponent wins. nil outside
-- Preparing..SuddenDeath.
function DuelFormat.forfeitNote(phase: string, phaseEndsAt: number, now: number, rules: { [string]: any }?): string?
	if not FORFEIT_PHASES[phase] then
		return nil
	end
	local cancels = BEFORE_ACTIVE[phase] == true
	if phase == "Active" then
		local activeFor = rule(rules, "MatchSeconds") - math.max(0, phaseEndsAt - now)
		cancels = activeFor < rule(rules, "EarlyForfeitSeconds")
	end
	if cancels then
		return Strings.format(Strings.duel.forfeitCancelNote, { seconds = rule(rules, "BailRequeueCooldownSeconds") })
	end
	return Strings.duel.forfeitLoseNote
end

-- Public: cooldown and charge

function DuelFormat.cooldownSeconds(squishyId: string, phase: string, rules: { [string]: any }?): number
	local def = Catalog.get(squishyId) or Catalog.get(Catalog.starterId())
	local base = if def then def.throw.cooldown else 1
	local clamp = rule(rules, "CooldownClamp")
	local seconds = math.clamp(base, clamp.Min, clamp.Max)
	if phase == "SuddenDeath" then
		seconds *= rule(rules, "SuddenDeathCooldownMultiplier")
	end
	return seconds
end

-- Fill of a bar that is full at `endsAt` and empty `duration` seconds before it.
function DuelFormat.progress(endsAt: number?, now: number, duration: number): number
	if endsAt == nil or not finite(endsAt) or not (duration > 0) then
		return 1
	end
	return math.clamp(1 - (endsAt - now) / duration, 0, 1)
end

-- The ultimate of a squishy's locked loadout: (ultimateId, Config.Abilities entry), or nil.
function DuelFormat.ultimateOf(squishyId: string): (string?, any)
	local def = Catalog.get(squishyId)
	local ultimateId = if def then def.ultimateId else nil
	if ultimateId == nil then
		return nil, nil
	end
	local ability = ABILITIES[ultimateId]
	if ability == nil then
		return nil, nil
	end
	return ultimateId, ability
end

function DuelFormat.chargeFraction(charge: number, chargeMax: number): number
	if not (chargeMax > 0) or not finite(charge) then
		return 0
	end
	return math.clamp(charge / chargeMax, 0, 1)
end

-- Public: result panel

-- The result panel from a DuelResult payload. Stats and rewards only for real results (never for cancelled/void);
-- accuracy is shown from the payload's throws and hits (reading: the unit of `stats.accuracy` is not fixed in DESIGN).
-- A quest line is "{quest}: 3/5" when questName knows the quest's text, else "3/5". Foam fix 2: questDone says, per
-- line, whether this duel finished the quest (the line's `done`), since the "Quest complete!" toast waits for the lobby.
function DuelFormat.result(payload: any, questName: QuestNamer?): ResultModel
	local outcome = if type(payload.outcome) == "string" then payload.outcome else "void"
	local titles = Strings.duel.result :: any
	local model: ResultModel = {
		outcome = outcome,
		title = titles[outcome] or titles.void,
		reason = resolveKey(payload.reasonKey),
		stats = {},
		reward = nil,
		rewardNote = nil,
		quests = {},
		questDone = {},
		tip = resolveKey(payload.tip),
		rewardCoins = nil,
	}
	if NO_STATS[outcome] then
		return model
	end
	local stats = if type(payload.stats) == "table" then payload.stats else {}
	local throws = if finite(stats.throws) then math.max(0, math.floor(stats.throws)) else 0
	local hits = if finite(stats.hits) then math.clamp(math.floor(stats.hits), 0, throws) else 0
	local accuracy = if throws > 0 then math.floor(hits / throws * PERCENT + 0.5) else 0
	model.stats = {
		{ label = Strings.stats.throws, value = tostring(throws) },
		{ label = Strings.stats.hits, value = tostring(hits) },
		{ label = Strings.stats.accuracy, value = Strings.format(Strings.common.percent, { value = accuracy }) },
	}
	local coins = if finite(payload.coins) then math.floor(payload.coins) else 0
	local rewards = Strings.duel.reward :: any
	local hasReason = type(payload.coinsBlockedReason) == "string" and payload.coinsBlockedReason ~= ""
	if coins > 0 and rewards[outcome] then
		model.reward = Strings.format(rewards[outcome], { coins = Format.coins(coins) })
		model.rewardCoins = coins
		if hasReason then
			model.rewardNote = Strings.reasonText(payload.coinsBlockedReason)
		end
	elseif hasReason then
		model.reward =
			Strings.format(Strings.duel.rewardBlocked, { reason = Strings.reasonText(payload.coinsBlockedReason) })
	end
	if type(payload.questProgress) == "table" then
		for _, line in payload.questProgress do
			if type(line) == "table" and finite(line.progress) and finite(line.goal) then
				local name = if questName and type(line.questId) == "string" then questName(line.questId) else nil
				local args = { quest = name, progress = line.progress, goal = line.goal }
				table.insert(
					model.quests,
					Strings.format(if name then Strings.duel.questLine else Strings.common.progress, args)
				)
				table.insert(model.questDone, line.done == true)
			end
		end
	end
	return model
end

-- The reward line while it counts up to its Coins: "+{n} Coins (win)" and so on (nil for an outcome without one).
function DuelFormat.rewardText(outcome: string, coins: number): string?
	local template = (Strings.duel.reward :: any)[outcome]
	if type(template) ~= "string" then
		return nil
	end
	local n = if finite(coins) then math.max(0, math.floor(coins + 0.5)) else 0
	return Strings.format(template, { coins = Format.coins(n) })
end

-- Public: feel pass cues (§18.5.2 B6-B7, §18.6)

-- What a countdown text sounds and looks like: a digit ticks (duel.countdownTick at countdownPitch: 1.00 on 3, 1.06 on
-- 2, 1.12 on 1; reading: a longer countdown's earlier digits use the first pitch) with its bubble colour and its tilt
-- (-tiltDeg on odd digits, +tiltDeg on even ones, so 3 / 2 / 1 alternate); "Throw!" is duel.go at pitch 1. nil for
-- anything else (no text, a hidden countdown).
function DuelFormat.countdownCue(text: string?): CountdownCue?
	if type(text) ~= "string" or text == "" then
		return nil
	end
	if text == Strings.duel.countdownGo then
		return { key = GO_SOUND, pitch = 1, digit = nil, bubble = nil, tiltDeg = 0 }
	end
	local digit = tonumber(text)
	if digit == nil or digit < 1 or digit ~= math.floor(digit) then
		return nil
	end
	local index = math.clamp(#COUNTDOWN_PITCH - digit + 1, 1, #COUNTDOWN_PITCH)
	local tilt = DUEL_ANIM.countdownBubble.tiltDeg
	return {
		key = TICK_SOUND,
		pitch = COUNTDOWN_PITCH[index],
		digit = digit,
		bubble = BUBBLE_COLORS[math.min(digit, 3)],
		tiltDeg = if digit % 2 == 1 then -tilt else tilt,
	}
end

-- The result title's look and sound by outcome (cancelled / void: Ink, no jingle, no confetti).
function DuelFormat.resultStyle(outcome: string): ResultStyle
	local style = RESULT_STYLES[outcome]
	local popFrom = if outcome == "loss" then DUEL_ANIM.result.defeatPopFrom else DUEL_ANIM.countdownPopFrom
	local confetti = 0
	if outcome == "win" then
		confetti = DUEL_ANIM.confetti.pieces
	elseif outcome == "draw" then
		confetti = DUEL_ANIM.confetti.drawPieces
	end
	return {
		color = if style then style.color else nil,
		popFrom = popFrom,
		jingle = if style then style.jingle else nil,
		confetti = confetti,
	}
end

-- Public: feel pass looks (§18.4.2, §18.5.2 B6-B8; pure, `t` in seconds since the beat) -----------------------------

-- A pop `t` seconds in: scale `from` -> 1 over `ms` (Back Out) while the tilt goes tiltDeg -> 0 with it. Returns
-- (scale, rotationDeg, done). Under ReducedMotion: (1, 0, true) at once.
function DuelFormat.popLook(
	t: number,
	from: number,
	ms: number,
	tiltDeg: number,
	reduced: boolean
): (number, number, boolean)
	local duration = ms / MS
	if reduced or duration <= 0 then
		return 1, 0, true
	elseif not finite(t) or t <= 0 then
		return from, tiltDeg, false
	elseif t >= duration then
		return 1, 0, true
	end
	local alpha = ease(t / duration, BACK)
	return from + (1 - from) * alpha, tiltDeg * (1 - alpha), false
end

-- "Hit!" (§18.4.2): pops hitTextPopFrom -> 1 over hitTextPopMs and tilts sign × hitTextTiltDeg -> 0. The callers
-- alternate the sign per hit (reading: DESIGN says "±6°").
function DuelFormat.hitTextPop(t: number, sign: number, reduced: boolean): (number, number, boolean)
	local tilt = if sign < 0 then -HIT.hitTextTiltDeg else HIT.hitTextTiltDeg
	return DuelFormat.popLook(t, HIT.hitTextPopFrom, HIT.hitTextPopMs, tilt, reduced)
end

-- READY and the opponent's ready chip (§18.5.2 B8): readyPop.from -> 1 over readyPop.ms, no tilt.
function DuelFormat.readyPop(t: number, reduced: boolean): (number, number, boolean)
	return DuelFormat.popLook(t, READY_POP.from, READY_POP.ms, 0, reduced)
end

-- A countdown text `t` seconds after it appeared (§18.5.2 B6).
-- A digit: the number pops countdownPopFrom -> 1 and its bubble countdownBubble.popFrom -> 1 (Back Out,
-- countdownPopMs), both tilting cue.tiltDeg -> 0; the bubble keeps countdownBubble.transparency. It stays until the
-- next text. ReducedMotion: full size, no tilt; the number and the bubble fade in (<= reducedMotionMaxFadeMs).
-- "Throw!": pops go.popFrom -> 1 (Back Out, go.popMs), holds go.holdMs, then grows 1 -> go.outScale (Quad Out) while
-- fading over go.outMs; no bubble. ReducedMotion: no scale; it fades in and out (each <= reducedMotionMaxFadeMs).
function DuelFormat.countdownLook(t: number, cue: CountdownCue, reduced: boolean): CountdownLook
	local elapsed = if finite(t) then math.max(0, t) else 0
	if cue.digit == nil then
		local go = DUEL_ANIM.go
		local holdEnds = (go.popMs + go.holdMs) / MS
		local outSeconds = (if reduced then reducedFadeMs(go.outMs) else go.outMs) / MS
		local scale, transparency = 1, 0
		if reduced then
			local inSeconds = reducedFadeMs(go.popMs) / MS
			transparency = if inSeconds > 0 then math.clamp(1 - elapsed / inSeconds, 0, 1) else 0
		else
			scale = DuelFormat.popLook(elapsed, go.popFrom, go.popMs, 0, false)
		end
		local done = false
		if elapsed >= holdEnds then
			local u = if outSeconds > 0 then (elapsed - holdEnds) / outSeconds else 1
			done = u >= 1
			transparency = math.clamp(u, 0, 1)
			scale = if reduced then 1 else 1 + (go.outScale - 1) * ease(u, QUAD)
		end
		return {
			textScale = scale,
			rotation = 0,
			textTransparency = transparency,
			bubbleScale = 1,
			bubbleTransparency = 1,
			done = done,
		}
	end
	local bubble = DUEL_ANIM.countdownBubble
	if reduced then
		local inSeconds = reducedFadeMs(DUEL_ANIM.countdownPopMs) / MS
		local shown = if inSeconds > 0 then math.clamp(elapsed / inSeconds, 0, 1) else 1
		return {
			textScale = 1,
			rotation = 0,
			textTransparency = 1 - shown,
			bubbleScale = 1,
			bubbleTransparency = 1 - (1 - bubble.transparency) * shown,
			done = shown >= 1,
		}
	end
	local popSeconds = DUEL_ANIM.countdownPopMs / MS
	local alpha = if popSeconds > 0 and elapsed < popSeconds then ease(elapsed / popSeconds, BACK) else 1
	return {
		textScale = DUEL_ANIM.countdownPopFrom + (1 - DUEL_ANIM.countdownPopFrom) * alpha,
		rotation = cue.tiltDeg * (1 - alpha),
		textTransparency = 0,
		bubbleScale = bubble.popFrom + (1 - bubble.popFrom) * alpha,
		bubbleTransparency = bubble.transparency,
		done = popSeconds <= 0 or elapsed >= popSeconds,
	}
end

-- The previous digit's bubble `t` seconds after the next text arrived: it grows 1 -> burstScale (Quad Out) while
-- fading from countdownBubble.transparency to 1 over burstMs. Returns (scale, backgroundTransparency, done).
-- ReducedMotion: no growth; the fade is capped at reducedMotionMaxFadeMs.
function DuelFormat.burstLook(t: number, reduced: boolean): (number, number, boolean)
	local bubble = DUEL_ANIM.countdownBubble
	local duration = (if reduced then reducedFadeMs(bubble.burstMs) else bubble.burstMs) / MS
	local elapsed = if finite(t) then math.max(0, t) else duration
	if duration <= 0 or elapsed >= duration then
		return if reduced then 1 else bubble.burstScale, 1, true
	end
	local u = elapsed / duration
	local scale = if reduced then 1 else 1 + (bubble.burstScale - 1) * ease(u, QUAD)
	return scale, bubble.transparency + (1 - bubble.transparency) * u, false
end

-- A result line `t` seconds after its turn (§18.5.2 B7): TextTransparency 1 -> 0 while it slides up lineSlidePx over
-- lineMs (Quad Out). Before its turn (t < 0) it is hidden and lowered. Returns (transparency, slidePx, done).
-- ReducedMotion: no slide; the fade is capped at reducedMotionMaxFadeMs.
function DuelFormat.lineLook(t: number, reduced: boolean): (number, number, boolean)
	local result = DUEL_ANIM.result
	local slide = if reduced then 0 else result.lineSlidePx
	if not finite(t) or t < 0 then
		return 1, slide, false
	end
	local duration = (if reduced then reducedFadeMs(result.lineMs) else result.lineMs) / MS
	if duration <= 0 or t >= duration then
		return 0, 0, true
	end
	local alpha = ease(t / duration, QUAD)
	return 1 - alpha, slide * (1 - alpha), false
end

-- The reward line's number `t` seconds after it started counting: 0 -> coins over rewardCountMs (Quad Out). Returns
-- (value, done). ReducedMotion: the number at once.
function DuelFormat.rewardCount(t: number, coins: number, reduced: boolean): (number, boolean)
	local target = if finite(coins) then math.max(0, coins) else 0
	local duration = DUEL_ANIM.result.rewardCountMs / MS
	if reduced or duration <= 0 then
		return target, true
	elseif not finite(t) or t <= 0 then
		return 0, false
	elseif t >= duration then
		return target, true
	end
	return target * ease(t / duration, QUAD), false
end

-- The reward line's pulse `t` seconds after the count ended: 1 -> rewardPulseScale -> 1 over rewardPulseMs. Returns
-- (scale, done). ReducedMotion: (1, true).
function DuelFormat.rewardPulse(t: number, reduced: boolean): (number, boolean)
	local result = DUEL_ANIM.result
	local duration = result.rewardPulseMs / MS
	if reduced or duration <= 0 then
		return 1, true
	elseif not finite(t) or t <= 0 then
		return 1, false
	elseif t >= duration then
		return 1, true
	end
	local rise = duration * PULSE_RISE
	local peak = result.rewardPulseScale
	if t < rise then
		return 1 + (peak - 1) * ease(t / rise, QUAD), false
	end
	return peak + (1 - peak) * ease((t - rise) / (duration - rise), BACK), false
end

-- The ultimate meter `t` seconds into a drain from `from` to `to` (§18.4.7: DragonRush.meterDrainMs, Quad Out).
-- Returns (fill, done).
function DuelFormat.meterDrain(from: number, to: number, t: number): (number, boolean)
	local duration = METER_DRAIN_MS / MS
	if duration <= 0 or not finite(t) or t >= duration then
		return to, true
	elseif t <= 0 then
		return from, false
	end
	return from + (to - from) * ease(t / duration, QUAD), false
end

-- Public: result poses (§9.14)

-- The poses this client plays from its own DuelResult outcome: (local character, opponent). A win cheers the local
-- character, a loss cheers the opponent (the winner), a draw shrugs both; cancelled and void play nothing.
function DuelFormat.endPoses(outcome: string): (string?, string?)
	if outcome == "win" then
		return POSE_CHEER, nil
	elseif outcome == "loss" then
		return nil, POSE_CHEER
	elseif outcome == "draw" then
		return POSE_SHRUG, POSE_SHRUG
	end
	return nil, nil
end

-- The pose layer weight `t` seconds after it started, with `bounces` dips (the cheer's Config.Anim.duel.cheerBounces;
-- 0 for the shrug). Returns (weight 0..1, done): done once the weight holds at 1.
function DuelFormat.endPoseWeight(t: number, bounces: number): (number, boolean)
	if not finite(t) or t <= 0 then
		return 0, false
	elseif t < POSE_RISE_SECONDS then
		return t / POSE_RISE_SECONDS, false
	end
	local u = t - POSE_RISE_SECONDS
	if u >= math.max(0, bounces) * POSE_BOUNCE_SECONDS then
		return 1, true
	end
	local phase = (u % POSE_BOUNCE_SECONDS) / POSE_BOUNCE_SECONDS
	return 1 - POSE_DIP * math.sin(math.pi * phase), false
end

-- Public: layout (Part 8, §11.2, §11.6) -----------------------------------------------------------------------------

-- Where the top-centre bar goes on a `screen` (base px) when it is `bar` big, clearing `avoid` (the Forfeit button's
-- rect while it shows; nil = nothing to clear). The bar's width counts in BAR_WIDTH_STEP steps. On the top row it is
-- centred, or moved right just enough to clear the button; when the row between the button and the right edge is too
-- narrow it goes under the button, centred (kept on screen when it fits).
function DuelFormat.topBarPlacement(screen: Vector2, bar: Vector2, avoid: Rect?): TopBarPlacement
	local width = math.ceil(math.max(0, if finite(bar.X) then bar.X else 0) / BAR_WIDTH_STEP) * BAR_WIDTH_STEP
	local half = width / 2
	local centre = screen.X / 2
	local right = screen.X - LAYOUT_EDGE
	local left = LAYOUT_EDGE
	local fitsScreen = width <= right - left
	local blocker: Rect? = nil
	if avoid and finite(avoid.x) and finite(avoid.y) and avoid.w > 0 and avoid.h > 0 then
		blocker = avoid
		left = math.max(left, avoid.x + avoid.w + LAYOUT_GAP)
	end
	if width <= right - left then
		return { x = math.clamp(centre, left + half, right - half), y = LAYOUT_EDGE, row = "top", fits = true }
	end
	local x = if fitsScreen then math.clamp(centre, LAYOUT_EDGE + half, right - half) else centre
	if blocker then
		return {
			x = x,
			y = math.max(LAYOUT_EDGE, blocker.y + blocker.h + LAYOUT_GAP),
			row = "below",
			fits = fitsScreen,
		}
	end
	return { x = x, y = LAYOUT_EDGE, row = "top", fits = fitsScreen }
end

-- The result panel on a screen `screenHeight` base px tall: its lines (`contentHeight` tall) scroll in a body that
-- leaves RESULT_MARGIN above and below the panel; `chromeHeight` is the rest of the panel (paddings, and the pinned
-- Queue again / Close row with its gap once it shows). The panel is centred RESULT_ANCHOR_Y down the screen, moved
-- up or down to stay inside the margins. Overlays fix: with the duel top bar's bottom (`barBottom`, while the duel HUD
-- shows) the panel starts LAYOUT_GAP under it when all its lines fit there without scrolling; otherwise clearsBar is
-- false and it is placed as without a bar (the caller hides the bar while the card shows: the card is what matters at
-- the result, and a card squeezed under the bar would hide its quest lines).
function DuelFormat.resultLayout(
	screenHeight: number,
	contentHeight: number,
	chromeHeight: number,
	barBottom: number?
): ResultLayout
	local h = if finite(screenHeight) then math.max(0, screenHeight) else 0
	local content = if finite(contentHeight) then math.max(0, contentHeight) else 0
	local chrome = if finite(chromeHeight) then math.max(0, chromeHeight) else 0
	local top = RESULT_MARGIN
	local clears = true
	if finite(barBottom) then
		local under = math.max(RESULT_MARGIN, (barBottom :: number) + LAYOUT_GAP)
		if under + content + chrome + RESULT_MARGIN <= h + EPSILON then
			top = under
		else
			clears = false
		end
	end
	local room = math.max(RESULT_MIN_BODY, h - top - RESULT_MARGIN - chrome)
	local body = math.min(content, room)
	local panel = body + chrome
	local half = panel / 2
	local centre = h * RESULT_ANCHOR_Y
	if panel + top + RESULT_MARGIN <= h then
		centre = math.clamp(centre, top + half, h - RESULT_MARGIN - half)
	else
		centre = h / 2
	end
	return {
		bodyHeight = body,
		panelHeight = panel,
		centerY = centre,
		scrolls = content > body + EPSILON,
		clearsBar = clears,
	}
end

-- Overlays fix: the centre (base px from the top) of a panel `panelHeight` tall with `overhang` hanging above its box
-- (a header tab's upper half) on a screen `screenHeight` tall: `anchorShare` down, moved to stay RESULT_MARGIN inside
-- the screen and, with the duel top bar's bottom (`barBottom`), LAYOUT_GAP under the bar. Returns (centreY, clearsBar):
-- clearsBar is false when the panel cannot fit between the bar and the bottom margin (it is then placed as without a
-- bar, and the caller hides the bar while it shows). The forfeit dialog (centred, 50% down).
function DuelFormat.panelBelowBar(
	screenHeight: number,
	barBottom: number?,
	panelHeight: number,
	overhang: number,
	anchorShare: number
): (number, boolean)
	local h = if finite(screenHeight) then math.max(0, screenHeight) else 0
	local half = if finite(panelHeight) then math.max(0, panelHeight) / 2 else 0
	local over = if finite(overhang) then math.max(0, overhang) else 0
	local centre = h * (if finite(anchorShare) then anchorShare else 0.5)
	local highest = RESULT_MARGIN + over + half
	local lowest = h - RESULT_MARGIN - half
	if lowest < highest then
		return h / 2, not finite(barBottom) -- taller than the screen: centred
	end
	if finite(barBottom) then
		local under = math.max(highest, (barBottom :: number) + LAYOUT_GAP + over + half)
		if under <= lowest + EPSILON then
			return math.clamp(centre, under, math.max(under, lowest)), true
		end
		return math.clamp(centre, highest, lowest), false
	end
	return math.clamp(centre, highest, lowest), true
end

-- Foam fix 2: what one side card needs (base px): its widest content plus its paddings and SIDE_SPARE. Compact
-- (phones): the lives row, which holds the pips, "N lives", the icon and the side word; a longer name is cut with "…"
-- instead of widening both cards. Regular: the name on one line (a PC has room for it), or the pips and "N lives" (the
-- side word wraps beside its icon as built, so it never widens the card). Made from the texts' sizes and the pips'
-- resting row, so a popping pip never changes it (DuelController keeps the widest need of a match, so "1 life" never
-- shrinks the cards either). Bad numbers count as 0.
function DuelFormat.sideNeed(input: SideNeedInput): number
	local function size(n: number): number
		return if finite(n) then math.max(0, n) else 0
	end
	local gap = size(input.gap)
	local lives = size(input.pips) + gap + size(input.lives)
	local content = if input.compact
		then lives + gap + size(input.icon) + gap + size(input.word)
		else math.max(size(input.name), lives)
	return content + 2 * size(input.padding) + SIDE_SPARE
end

-- Overlays fix: the side cards' width (base px; foam fix 2: on both layouts, from sideNeed): `need` rounded up to
-- SIDE_WIDTH_STEP, never below `minWidth`, and never so wide that the bar (two cards, the timer and the two gaps,
-- rounded up to BAR_WIDTH_STEP like topBarPlacement does) leaves the top row beside the Forfeit button (`avoid`). A
-- `need` that is not finite gives minWidth.
function DuelFormat.sideCardWidth(input: SideWidthInput): number
	local minWidth = if finite(input.minWidth) then math.max(0, input.minWidth) else 0
	local need = if finite(input.need) then input.need else 0
	local middle = if finite(input.middle) then math.max(0, input.middle) else 0
	local gap = if finite(input.gap) then math.max(0, input.gap) else 0
	local left = LAYOUT_EDGE
	local avoid = input.avoid
	if avoid and finite(avoid.x) and finite(avoid.w) and avoid.w > 0 and avoid.h > 0 then
		left = math.max(left, avoid.x + avoid.w + LAYOUT_GAP)
	end
	local right = (if finite(input.screenWidth) then input.screenWidth else 0) - LAYOUT_EDGE
	local most = math.floor((right - left - BAR_WIDTH_STEP - middle - 2 * gap) / 2)
	local want = math.ceil(need / SIDE_WIDTH_STEP) * SIDE_WIDTH_STEP
	return math.max(minWidth, math.min(want, most))
end

-- Overlays fix: the x offset (base px, from the reticle's centre; the reticle's UIScale applies) of its state text, so
-- the whole text stays `margin` base px inside the screen: 0 while it fits centred under the reticle, else moved in just
-- enough. `aimX` and `screenWidth` are viewport px (the full-bleed reticle gui), `textWidth` base px, `scale` the UI
-- scale. A text wider than the screen is centred on the screen. Bad numbers give 0.
function DuelFormat.reticleLabelOffset(
	aimX: number,
	textWidth: number,
	screenWidth: number,
	scale: number,
	margin: number
): number
	if not (finite(aimX) and finite(textWidth) and finite(screenWidth) and finite(scale) and scale > 0) then
		return 0
	end
	local half = math.max(0, textWidth) * scale / 2
	local inset = (if finite(margin) then math.max(0, margin) else 0) * scale
	local lowest = inset + half
	local highest = screenWidth - inset - half
	local centre = if lowest <= highest then math.clamp(aimX, lowest, highest) else screenWidth / 2
	return (centre - aimX) / scale
end

-- Foam fix 2: whether a reticle must hide because its point sits on a HUD control or an open dialog. `objects` are
-- PlayerGui:GetGuiObjectsAtPosition's at that point; one counts when it shows (its own Visible) and is a button or a
-- text box, or an Active surface that is not fully transparent (a dialog's panel; a clear click catcher does not). The
-- reticles' own pieces are never Active, so they never count.
function DuelFormat.aimBlocked(objects: { GuiObject }): boolean
	for _, object in objects do
		if not object.Visible then
			continue
		end
		if object:IsA("GuiButton") or object:IsA("TextBox") then
			return true
		elseif object.Active and object.BackgroundTransparency < 1 then
			return true
		end
	end
	return false
end

-- Foam fix 2: how long (seconds) the duel result card waits so the eliminator's "K.O.!" banner (over SD_Modal) has gone
-- before it shows: until `koUntil` (VfxController.koBannerUntil, the same os.clock as `now`), never longer than `most`.
-- A bad or endless time waits nothing.
function DuelFormat.resultWait(koUntil: number, now: number, most: number): number
	local wait = koUntil - now
	if not finite(wait) then
		return 0
	end
	return math.clamp(wait, 0, if finite(most) then math.max(0, most) else 0)
end

-- The result panel's slide `t` seconds after it appeared: `px` down at the start, back to 0 over `ms` (Back Out, so
-- it overshoots a little like the Part 4 tween). 0 under ReducedMotion.
function DuelFormat.slideLook(t: number, px: number, ms: number, reduced: boolean): (number, boolean)
	local duration = ms / MS
	if reduced or duration <= 0 then
		return 0, true
	elseif not finite(t) or t <= 0 then
		return px, false
	elseif t >= duration then
		return 0, true
	end
	return px * (1 - ease(t / duration, BACK)), false
end

-- The countdown's centre (base px from the top) on a screen `screenHeight` tall: COUNTDOWN_ANCHOR_Y down, or lower so
-- its box (`boxHeight`: the text box or the bubble, whichever is taller) starts LAYOUT_GAP under the top bar's bottom
-- (`barBottom`); never so low that the box leaves the screen (then the top bar is left behind it, as before).
function DuelFormat.countdownCenterY(screenHeight: number, barBottom: number, boxHeight: number): number
	local h = if finite(screenHeight) then math.max(0, screenHeight) else 0
	local half = if finite(boxHeight) then math.max(0, boxHeight) / 2 else 0
	local y = h * COUNTDOWN_ANCHOR_Y
	if finite(barBottom) then
		y = math.max(y, barBottom + LAYOUT_GAP + half)
	end
	return math.max(h * COUNTDOWN_ANCHOR_Y, math.min(y, h - LAYOUT_EDGE - half))
end

-- Public: off-screen arrow

-- `point` is Camera:WorldToViewportPoint's result (X, Y in px, Z = depth; Z < 0 = behind the camera). Returns
-- (visible, position, rotationDeg): hidden while the point is on screen inside `margin`; otherwise a spot on the
-- screen edge (inset by margin) in the point's direction and the clockwise angle of that direction (0 = right).
function DuelFormat.edgeArrow(point: Vector3, viewport: Vector2, margin: number): (boolean, Vector2, number)
	local cx, cy = viewport.X / 2, viewport.Y / 2
	local x, y = point.X, point.Y
	local behind = point.Z < 0
	if behind then
		-- A point behind the camera projects mirrored through the centre; flip it back to its real direction.
		x, y = 2 * cx - x, 2 * cy - y
	end
	if not behind and x >= margin and x <= viewport.X - margin and y >= margin and y <= viewport.Y - margin then
		return false, Vector2.new(x, y), 0
	end
	local dx, dy = x - cx, y - cy
	if math.abs(dx) < EPSILON and math.abs(dy) < EPSILON then
		dy = 1 -- straight behind: point down
	end
	local halfW, halfH = math.max(0, cx - margin), math.max(0, cy - margin)
	local tx = if math.abs(dx) > EPSILON then halfW / math.abs(dx) else math.huge
	local ty = if math.abs(dy) > EPSILON then halfH / math.abs(dy) else math.huge
	local t = math.min(tx, ty)
	return true, Vector2.new(cx + dx * t, cy + dy * t), math.deg(math.atan2(dy, dx))
end

return DuelFormat
