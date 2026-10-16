--!strict
-- QueueFormat (client only, pure). DESIGN §5.4 (queue conditions and texts), §11.6 (queue pill), §7.7 (queue board):
-- what QueueController shows, as plain data, so it is unit-tested in Edit mode. Times are server times
-- (workspace:GetServerTimeNow(); reading: QueueStatus.joinedAt is a server time like every gameplay time, §2.11).
--   pill(view, now, aloneSince, hintDismissedAt)  the queue pill: title "Looking for an opponent… 0:23", one detail
--        line and which buttons show. The "no opponent" hint (Keep waiting / Practice / Cancel) appears when the
--        server says so (messageKey queue.noOpponent) or once the player has been the only searching ticket for
--        Config.Duel.Matchmaking.NoOpponentHintSeconds (20 s); Keep waiting hides it for another 20 s. Detail: the
--        hint text, else "All arenas are in use. You're next." (the server's messageKey, or no arena free while this
--        ticket is one of the first two), else "You're #{n} in the queue".
--   searchLine(view)                  UI FINAL R4: that detail without the hint (the arena or the position line, or
--                                     nil): the DUEL search bar's second line (H:142; plan FD1, the real queue line)
--   nextAloneSince(prev, view, now)   when the "alone" clock started (nil = someone else is searching / not queued)
--   boardText(liveKey, counts, max)   the podium board's live lines (SD_LiveKey queue.boardWaiting / boardActive)
--   promptAttribute(state)            which baked prompt key to show: SD_AltTextKey ("Leave Queue") while Searching
--   joinErrorText(reason)             a QueueJoin failure: its reason text, or "Couldn't join the queue. Try again."
--   messageText(key)                  a queue message (fills {minutes} of queue.timedOut from Config)
--   toastKey(old, new)                the message of a QueueStatus update that should pop a toast, if any (never the
--                                     arena wait or the no-opponent hint: the pill shows those itself)
--   matchedText(name)                 UI FINAL R4 (H:151, plan FD2): MATCH FOUND's second line, "Opponent: {name}", or
--                                     "" before the name is known (the bar's title already says it)
--   pillPlacement(input)              where the pill goes in SD_Hud's base px (Part 8; foam restyle, spec 2026-10-09:
--                                     the Duel CTA shows the queued state; lobby HUD, spec 2026-10-11: the CTA sits at
--                                     the top middle): right under the Duel CTA, centred on it, when that spot is free;
--                                     else right above the CTA, right-aligned with it; else the top band, centred
--                                     between the HUD groups it meets; else left of the CTA, bottom-aligned with it;
--                                     with no free spot the top centre, fits = false. Free = inside the HUD's edges and
--                                     over none of the blockers (the HUD groups, the coach card, the touch areas kept
--                                     clear). Its width is PILL_WIDTH, narrower down to PILL_MIN_WIDTH when the room is
--                                     narrower
-- Overlays fix (2026-10-09; the pill hugs its contents instead of a fixed 460 / 520 with an empty gap before Cancel):
--   pillWidth(parts, cap)             the pill's width from its parts: the paddings, the clock, the wider of the title
--                                     and the detail line, Cancel and the gaps (or the hint row's buttons when wider),
--                                     never wider than `cap` (today's widths); pillPlacement takes it as its width and
--                                     never asks for more room than that
--   measureSample(text)               the text a width is measured from: every digit as "8", so the ticking clock and
--                                     a new queue position never change the pill's width

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

-- Types

-- The fields of StateController.QueueView that matter here.
export type QueueLike = {
	state: Types.QueueState,
	position: number?,
	joinedAt: number?,
	messageKey: string?,
	searching: number,
	arenasFree: number,
}

export type CountsLike = { searching: number, duelsInProgress: number, arenasFree: number }

export type Pill = {
	visible: boolean,
	title: string,
	detail: string?,
	showCancel: boolean,
	showHint: boolean, -- Keep waiting + Practice
}

-- A rectangle in SD_Hud's base px (AbsolutePosition / AbsoluteSize divided by the UI scale).
export type Rect = { x: number, y: number, w: number, h: number }

-- What pillPlacement reads: the SD_Hud canvas, the Duel CTA and what the pill must not cover (nil or empty rects = not
-- on screen).
export type PillInput = {
	screen: Vector2,
	cta: Rect?, -- Hud_DuelButton, the Duel CTA (the pill's first spot is right under it)
	blockers: { Rect }?, -- the HUD groups, the coach card, the touch areas kept clear
	width: number?, -- the preferred width (default PILL_WIDTH)
	height: number?, -- the pill's height (default PILL_HEIGHT)
}

export type PillSpot = "belowCta" | "aboveCta" | "top" | "besideCta"

export type PillPlacement = {
	x: number, -- the pill's centre
	y: number, -- its top
	width: number,
	spot: PillSpot,
	fits: boolean, -- false: no free spot (the top centre, over something)
}

-- What pillWidth reads (base px at the player's text size).
export type PillParts = {
	padding: number, -- the pill's inner padding (each side)
	icon: number, -- the clock
	gap: number, -- between the clock, the texts and Cancel
	text: number, -- the wider of the title and the detail line, each on one line (measureSample)
	cancel: number, -- Cancel's width
	hint: number?, -- Keep waiting + Practice and the gap between them, while they show
}

-- Constants

local MATCHMAKING = Config.Duel.Matchmaking
local HINT_SECONDS = MATCHMAKING.NoOpponentHintSeconds
local SECONDS_PER_MINUTE = 60
local WAITING_ARENA = "queue.waitingArena"
local NO_OPPONENT = "queue.noOpponent"
local TIMED_OUT = "queue.timedOut"
local GENERIC = "error.generic"
local ATTR_TEXT_KEY = "SD_TextKey"
local ATTR_ALT_TEXT_KEY = "SD_AltTextKey"
local LIVE_WAITING = "queue.boardWaiting"
local LIVE_ACTIVE = "queue.boardActive"
local HEAD_PAIR = 2 -- the first two tickets are the next pair
-- Pill placement (readings: §11.6 says "top-centre", not these numbers). Base px under SD_Hud's UIScale.
local PILL_TOP = 12 -- the HUD's edge distance (HudFormat.COLUMN.edge)
local PILL_EDGE = 12
local PILL_GAP = 8 -- the HUD's gap between groups (HudFormat.COLUMN.rowGap)
local PILL_WIDTH = 460
-- Narrowest pill: the title wraps and the three buttons wrap to two lines; under this it would be all wrapping.
local PILL_MIN_WIDTH = 320
-- The pill's height until it is measured: its title, its detail line and one row of buttons.
local PILL_HEIGHT = 150
-- pillWidth (readings): slack over the measured text so a rounding never wraps it; the measuring digit.
local PILL_TEXT_SLACK = 4
local SAMPLE_DIGIT = "8"

-- Module table

local QueueFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The rect when it is on screen (finite, with a size), else nil.
local function present(rect: Rect?): Rect?
	if rect == nil or not (finite(rect.x) and finite(rect.y) and finite(rect.w) and finite(rect.h)) then
		return nil
	end
	return if rect.w > 0 and rect.h > 0 then rect else nil
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- The span (low, high) free for a pill at [y, y + h]: the screen's edges, cut by every blocker that meets the band (a
-- blocker left of the screen's centre pushes `low` right of it, one right of the centre pulls `high` left of it).
local function spanAt(screen: Vector2, y: number, h: number, blockers: { Rect }): (number, number)
	local low, high = PILL_EDGE, screen.X - PILL_EDGE
	local centre = screen.X / 2
	for _, rect in blockers do
		if rect.y < y + h and y < rect.y + rect.h then
			if rect.x + rect.w / 2 < centre then
				low = math.max(low, rect.x + rect.w + PILL_GAP)
			else
				high = math.min(high, rect.x - PILL_GAP)
			end
		end
	end
	return low, high
end

-- Public

function QueueFormat.nextAloneSince(previous: number?, view: QueueLike, now: number): number?
	if view.state ~= "Searching" or view.searching > 1 then
		return nil
	end
	return previous or now
end

function QueueFormat.pill(view: QueueLike, now: number, aloneSince: number?, hintDismissedAt: number?): Pill
	if view.state ~= "Searching" then
		return { visible = false, title = "", detail = nil, showCancel = false, showHint = false }
	end
	local title = Strings.queue.searching
	if view.joinedAt then
		title = Strings.format(Strings.queue.searchingTime, { time = Format.clock(now - view.joinedAt) })
	end
	local snoozed = hintDismissedAt ~= nil and now - hintDismissedAt < HINT_SECONDS
	local due = view.messageKey == NO_OPPONENT or (aloneSince ~= nil and now - aloneSince >= HINT_SECONDS)
	local showHint = due and not snoozed
	local detail = if showHint then Strings.queue.noOpponent else QueueFormat.searchLine(view)
	return { visible = true, title = title, detail = detail, showCancel = true, showHint = showHint }
end

-- UI FINAL R4: the queue's own line without the hint (see the header); nil when not Searching or nothing to say.
function QueueFormat.searchLine(view: QueueLike): string?
	if view.state ~= "Searching" then
		return nil
	end
	if
		view.messageKey == WAITING_ARENA
		or (view.arenasFree <= 0 and view.searching >= HEAD_PAIR and (view.position or math.huge) <= HEAD_PAIR)
	then
		return Strings.queue.waitingArena
	elseif view.position then
		return Strings.format(Strings.queue.position, { n = view.position })
	end
	return nil
end

function QueueFormat.boardText(liveKey: unknown, counts: CountsLike, maxSlots: number): string?
	if liveKey == LIVE_WAITING then
		return Strings.format(Strings.queue.boardWaiting, { count = counts.searching })
	elseif liveKey == LIVE_ACTIVE then
		return Strings.format(Strings.queue.boardActive, { count = counts.duelsInProgress, max = maxSlots })
	end
	return nil
end

function QueueFormat.promptAttribute(state: Types.QueueState): string
	return if state == "Searching" then ATTR_ALT_TEXT_KEY else ATTR_TEXT_KEY
end

function QueueFormat.messageText(key: string): string
	local args = if key == TIMED_OUT then { minutes = MATCHMAKING.QueueMaxSeconds / SECONDS_PER_MINUTE } else nil
	return Strings.format(Strings.reasonText(key), args)
end

function QueueFormat.joinErrorText(reason: string?): string
	if reason == nil or reason == GENERIC then
		return Strings.queue.joinFailed
	end
	if Strings.resolve("reason." .. reason) == nil and Strings.resolve(reason) == nil then
		return Strings.queue.joinFailed
	end
	return QueueFormat.messageText(reason)
end

-- The message of an owner update that should pop a toast: a new messageKey (or the same one with a state change),
-- except the arena wait and the no-opponent hint, which the pill shows itself.
function QueueFormat.toastKey(old: QueueLike, new: QueueLike): string?
	local key = new.messageKey
	if key == nil or key == WAITING_ARENA or key == NO_OPPONENT then
		return nil
	end
	if key ~= old.messageKey or new.state ~= old.state then
		return key
	end
	return nil
end

function QueueFormat.matchedText(name: string?): string
	if name and name ~= "" then
		return Strings.format(Strings.hud.matchOpponent, { name = name })
	end
	return ""
end

-- Where the pill goes (see the header). In order, the first free spot wins:
--   1. "belowCta" (lobby HUD, spec 2026-10-11): PILL_GAP under the Duel CTA at the top middle, centred on it and moved
--      into the span its band leaves between the blockers (the CTA shows the queued state, the pill the details and
--      Cancel; the coach card waits while queued);
--   2. "aboveCta": right above the Duel CTA, its right edge on the CTA's, PILL_GAP between them (a CTA lower down);
--   3. "top": the top band (y = PILL_TOP), centred between the blockers it meets;
--   4. "besideCta": left of the CTA, bottom-aligned with it;
--   5. none is free: the top band's span (or the screen) centred, fits = false.
-- The width is PILL_WIDTH, narrower (down to PILL_MIN_WIDTH) where the room is narrower; a pill asking for less than
-- PILL_MIN_WIDTH (pillWidth: it hugs its contents) needs only its own width.
function QueueFormat.pillPlacement(input: PillInput): PillPlacement
	local screen = input.screen
	local want = if finite(input.width) and (input.width :: number) > 0 then input.width :: number else PILL_WIDTH
	local least = math.min(PILL_MIN_WIDTH, want)
	local h = if finite(input.height) and (input.height :: number) > 0 then input.height :: number else PILL_HEIGHT
	local blockers: { Rect } = {}
	local given: { Rect } = input.blockers or {}
	for _, rect in given do
		local shown = present(rect)
		if shown then
			table.insert(blockers, shown)
		end
	end
	local cta = present(input.cta)
	if cta then
		table.insert(blockers, cta)
	end
	local function free(rect: Rect): boolean
		if rect.w < least - 1e-6 then
			return false
		end
		if rect.x < PILL_EDGE - 1e-6 or rect.y < PILL_TOP - 1e-6 then
			return false
		end
		if rect.x + rect.w > screen.X - PILL_EDGE + 1e-6 or rect.y + rect.h > screen.Y - PILL_EDGE + 1e-6 then
			return false
		end
		for _, other in blockers do
			if overlaps(rect, other) then
				return false
			end
		end
		return true
	end
	local function placed(rect: Rect, spot: PillSpot, fits: boolean): PillPlacement
		return { x = rect.x + rect.w / 2, y = rect.y, width = rect.w, spot = spot, fits = fits }
	end

	if cta then
		local y = cta.y + cta.h + PILL_GAP
		local low, high = spanAt(screen, y, h, blockers)
		local width = math.max(0, math.min(want, high - low))
		local x = math.clamp(cta.x + cta.w / 2 - width / 2, low, math.max(low, high - width))
		local below = { x = x, y = y, w = width, h = h }
		if free(below) then
			return placed(below, "belowCta", true)
		end
	end

	if cta then
		local right = cta.x + cta.w
		local width = math.min(want, right - PILL_EDGE)
		local above = { x = right - width, y = cta.y - PILL_GAP - h, w = width, h = h }
		if free(above) then
			return placed(above, "aboveCta", true)
		end
	end

	local low, high = spanAt(screen, PILL_TOP, h, blockers)
	local topWidth = math.max(0, math.min(want, high - low))
	local top = {
		x = math.clamp(screen.X / 2 - topWidth / 2, low, math.max(low, high - topWidth)),
		y = PILL_TOP,
		w = topWidth,
		h = h,
	}
	if free(top) then
		return placed(top, "top", true)
	end

	if cta then
		local right = cta.x - PILL_GAP
		local width = math.min(want, right - PILL_EDGE)
		local beside = { x = right - width, y = cta.y + cta.h - h, w = width, h = h }
		if free(beside) then
			return placed(beside, "besideCta", true)
		end
	end

	local width = if topWidth >= least then topWidth else math.max(0, math.min(want, screen.X - 2 * PILL_EDGE))
	local x = if topWidth >= least then top.x else (screen.X - width) / 2
	return placed({ x = x, y = PILL_TOP, w = width, h = h }, "top", false)
end

-- The text a pill width is measured from: every digit replaced by SAMPLE_DIGIT (a wide one), so "0:23" -> "0:24" or
-- "#2" -> "#3" never changes the measured width (the pill would twitch every second).
function QueueFormat.measureSample(text: string): string
	local sample = string.gsub(text, "%d", SAMPLE_DIGIT)
	return sample
end

-- The pill's width hugging its contents (base px): the top row is the paddings, the clock, the texts (parts.text plus
-- PILL_TEXT_SLACK) and Cancel with a gap between each; the hint row (Keep waiting, Practice) when it shows and is
-- wider. Rounded up to whole px, never wider than `cap` (the pill's width before the overlays fix: PILL_WIDTH on
-- phones, QueueController's wider one on PCs); bad numbers count as 0, a bad cap as PILL_WIDTH.
function QueueFormat.pillWidth(parts: PillParts, cap: number): number
	local function n(value: number?): number
		return if finite(value) then math.max(0, value :: number) else 0
	end
	local limit = if finite(cap) and cap > 0 then cap else PILL_WIDTH
	local padding = 2 * n(parts.padding)
	local row = padding + n(parts.icon) + 2 * n(parts.gap) + n(parts.text) + PILL_TEXT_SLACK + n(parts.cancel)
	local hint = padding + n(parts.hint)
	return math.min(limit, math.ceil(math.max(row, hint)))
end

return QueueFormat
