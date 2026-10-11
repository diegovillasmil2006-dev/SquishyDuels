--!strict
-- NotifyFormat (client only, pure). DESIGN §2.8 (Notify(code, args?, kind)), §2.10 (reason codes; "No Coins were spent"
-- only when the server says charged = false), §11.3 (error state), §17.2 / §17.7 (grip.* toasts held back from Matched
-- through Returning, at most 3, merged into one). What NotifyController shows, as plain data:
--   textFor(code, args)      the toast text of a Notify code, or nil for anything that is not a known Strings key
--                            (reason.<code> or the plain key). queue.* and duel.* codes are worded exactly as
--                            QueueController words them (UI/QueueFormat.messageText), so the copy it still shows is
--                            the same text and UIController merges the two into one toast
--   kindOf(kind)             the toast kind (info / success / warn / error; anything else -> info)
--   isHeldBack(code)         true for the codes held back during a match (grip.*; since the overlays fix of
--                            2026-10-09 also quest.*, so "Quest complete!" never covers the duel result card)
--   pushHeld(list, text, max) the held texts after one more arrives: newest last, at most `max`, no duplicates
--   merge(list)              the held texts as one toast (one per line)
--   resultText(result)       a failed Result's reason text, plus "No Coins were spent." when charged == false
--   areaOf(code)             the code's area prefix including the dot ("queue.") or nil
-- Foam UI restyle (spec 2026-10-09; UIController draws the toasts):
--   toastAccent(kind)        the accent stripe of a toast kind: info "sky", success "mint", warn "strawberry",
--                            error "danger" (Danger is reserved for errors, §7.2); CoinGold never marks a toast
--   toastTop(canvasH, belowBottom?, defaultTop, gap)   the top of the toast column (base px): defaultTop, or `gap`
--                            under `belowBottom` (the bottom of what toasts must not cover, e.g. the lobby's coach
--                            card) when that is lower; never past the middle of the canvas (spec: the coach card never
--                            overlaps toasts)
--   toastClearance(rects, canvasW, columnW, defaultTop, gap?)   integration (2026-10-09): the lowest bottom of the rects
--                            that hang into the centred toast column from above (they share its columns and start at or
--                            above defaultTop: the Duel CTA at the top middle, the duel top bar), or nil; a rect lower
--                            down never moves the toasts. Lobby HUD (spec 2026-10-11): they chain, so a rect starting
--                            at or above `gap` under one that counts counts too (the coach card or the queue pill right
--                            under the CTA): the toasts go under the CTA, then the coach card, then the pill
-- Overlays fix (2026-10-09; toasts never cover the HUD):
--   toastColumn(input)       where the toast column goes (base px): its top as toastTop / toastClearance give it
--                            (under what hangs in from above), and sideways clear of the `beside` rects its band
--                            meets (the HUD groups: on a phone the tile row runs under the centred column): centred
--                            when the room between them allows, else moved aside, else narrowed down to minWidth;
--                            with even less room it goes under them (full width, centred)

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local QueueFormat = require(script.Parent.QueueFormat)

-- Types

export type ToastKind = Types.NotifyKind
-- A Theme accent name, or "danger" (Theme.Colors.danger, errors only).
export type ToastAccent = "sky" | "mint" | "strawberry" | "danger"
-- A box in base px (toastClearance).
export type Rect = { x: number, y: number, w: number, h: number }

-- What toastColumn reads (base px of the overlay canvas).
export type ColumnInput = {
	canvas: Vector2,
	width: number, -- the column's preferred width (UIController TOAST_WIDTH)
	minWidth: number, -- the narrowest it gets beside the HUD before it goes under it instead
	height: number, -- the column's height now (at least one toast), the band it must keep clear
	defaultTop: number,
	gap: number, -- between the column and what it keeps clear
	edge: number, -- the screen edge distance
	above: { Rect }, -- toastsBelow: what hangs into the column from above (it starts under them)
	beside: { Rect }, -- toastsBeside: what it keeps beside (the HUD groups)
}

-- Where the toast column goes: its left edge, its top and its width (base px).
export type Column = { x: number, y: number, width: number }

-- Constants

local MAX_CODE_LENGTH = 64
local CODE_PATTERN = "^[%w_]+%.[%w_%.]+$"
-- Overlays fix: quest.* too ("Quest complete!" arrived during Result and covered the result card on a phone; the card
-- lists the quest progress itself).
local HELD_AREAS: { string } = { "grip.", "quest." }
-- Areas QueueController also toasts (with UI/QueueFormat wording).
local QUEUE_WORDED_AREAS: { string } = { "queue.", "duel." }
local LINE_BREAK = "\n"
local SENTENCE_GAP = " "
local GENERIC = "error.generic"
local TOAST_ACCENTS: { [string]: ToastAccent } = {
	info = "sky",
	success = "mint",
	warn = "strawberry",
	error = "danger",
}
local TOAST_MAX_TOP_SHARE = 0.5 -- toastTop: the column never starts past the middle of the canvas
-- toastColumn: moving the column aside can make it meet something above it it missed while centred; it is placed
-- this many times at most (each pass only moves it down).
local COLUMN_PASSES = 3

-- Module table

local NotifyFormat = {}

-- Private

local function startsWithAny(code: string, areas: { string }): boolean
	for _, area in areas do
		if string.sub(code, 1, #area) == area then
			return true
		end
	end
	return false
end

local function finite(n: number?): boolean
	return n ~= nil and n == n and n > -math.huge and n < math.huge
end

local function isCode(code: unknown): boolean
	return type(code) == "string" and #code > 0 and #code <= MAX_CODE_LENGTH and string.match(code, CODE_PATTERN) ~= nil
end

-- A rect that is finite and has a size (anything else counts as not shown).
local function usableRect(rect: Rect): boolean
	return finite(rect.x) and finite(rect.y) and finite(rect.w) and finite(rect.h) and rect.w > 0 and rect.h > 0
end

-- The lowest bottom of the rects that share columns with [left, right] and hang in from above; nil when none. Lobby HUD
-- (spec 2026-10-11): they chain. A rect counts when it starts at or above the running top: `defaultTop` at first, then
-- `gap` under the lowest bottom so far (the Duel CTA at the top middle, then the coach card or the queue pill right
-- under it, which start below defaultTop).
local function clearanceBetween(rects: { Rect }, left: number, right: number, defaultTop: number, gap: number): number?
	local lowest: number? = nil
	local counted: { [Rect]: boolean } = {}
	local running = defaultTop
	repeat
		local grew = false
		for _, rect in rects do
			if
				not counted[rect]
				and usableRect(rect)
				and rect.y <= running
				and rect.x < right
				and left < rect.x + rect.w
			then
				counted[rect] = true
				local bottom = rect.y + rect.h
				if lowest == nil or bottom > lowest then
					lowest = bottom
					running = math.max(running, bottom + gap)
					grew = true
				end
			end
		end
	until not grew
	return lowest
end

-- Only string and number values are used to fill placeholders.
local function cleanArgs(args: unknown): { [string]: any }?
	if type(args) ~= "table" then
		return nil
	end
	local clean: { [string]: any } = {}
	for key, value in args :: { [any]: any } do
		local kind = type(value)
		if type(key) == "string" and (kind == "string" or kind == "number") then
			clean[key] = value
		end
	end
	return clean
end

-- Public

function NotifyFormat.areaOf(code: unknown): string?
	if type(code) ~= "string" then
		return nil
	end
	local area = string.match(code, "^([%w_]+%.)")
	return area
end

-- True when the code resolves to a text (reason.<code> or the plain key).
function NotifyFormat.isKnown(code: unknown): boolean
	if not isCode(code) then
		return false
	end
	local key = code :: string
	return Strings.resolve("reason." .. key) ~= nil or Strings.resolve(key) ~= nil
end

function NotifyFormat.textFor(code: unknown, args: unknown): string?
	if not NotifyFormat.isKnown(code) then
		return nil
	end
	local key = code :: string
	local values = cleanArgs(args)
	if startsWithAny(key, QUEUE_WORDED_AREAS) then
		return Strings.format(QueueFormat.messageText(key), values)
	end
	return Strings.format(Strings.reasonText(key), values)
end

function NotifyFormat.kindOf(kind: unknown): ToastKind
	if kind == "success" then
		return "success"
	elseif kind == "warn" then
		return "warn"
	elseif kind == "error" then
		return "error"
	end
	return "info"
end

function NotifyFormat.isHeldBack(code: unknown): boolean
	return type(code) == "string" and startsWithAny(code, HELD_AREAS)
end

function NotifyFormat.pushHeld(list: { string }, text: string, max: number): { string }
	local result: { string } = {}
	for _, existing in list do
		if existing ~= text then
			table.insert(result, existing)
		end
	end
	table.insert(result, text)
	local limit = math.max(1, math.floor(max))
	while #result > limit do
		table.remove(result, 1)
	end
	return result
end

function NotifyFormat.merge(list: { string }): string?
	if #list == 0 then
		return nil
	end
	return table.concat(list, LINE_BREAK)
end

-- Text for a failed Result (§2.7): the reason's text, plus common.noCoinsSpent only when the server said charged =
-- false. A Result that is ok, or has no reason, gives the generic error text.
function NotifyFormat.resultText(result: { [string]: any }): string
	local reason = result.reason
	local text = Strings.reasonText(if type(reason) == "string" and reason ~= "" then reason else GENERIC)
	if result.charged == false then
		return text .. SENTENCE_GAP .. Strings.common.noCoinsSpent
	end
	return text
end

-- The accent stripe of a toast (foam UI): by kind, anything unknown as info.
function NotifyFormat.toastAccent(kind: unknown): ToastAccent
	return TOAST_ACCENTS[NotifyFormat.kindOf(kind)]
end

-- The top (base px) of the toast column on a canvas `canvasHeight` tall: `defaultTop`, or `gap` under `belowBottom`
-- (base px from the canvas top; nil or not finite = nothing to keep clear) when that is lower; never lower than the
-- middle of the canvas (nor than defaultTop when the canvas is shorter than twice that).
function NotifyFormat.toastTop(canvasHeight: number, belowBottom: number?, defaultTop: number, gap: number): number
	local top = if finite(defaultTop) then math.max(0, defaultTop) else 0
	local result = top
	if finite(belowBottom) then
		result = math.max(result, (belowBottom :: number) + (if finite(gap) then math.max(0, gap) else 0))
	end
	local h = if finite(canvasHeight) then math.max(0, canvasHeight) else 0
	return math.min(result, math.max(top, h * TOAST_MAX_TOP_SHARE))
end

-- The lowest bottom (base px) of the rects that hang into the toast column from above: each shares columns with the
-- column (`columnWidth` wide, centred on a canvas `canvasWidth` wide) and starts at or above `defaultTop`, or (lobby
-- HUD, spec 2026-10-11) at or above `gap` (default 0) under one that counts; nil when none does. Rects that are not
-- finite or have no size count as nothing. Feed the result to toastTop.
function NotifyFormat.toastClearance(
	rects: { Rect },
	canvasWidth: number,
	columnWidth: number,
	defaultTop: number,
	gap: number?
): number?
	if not (finite(canvasWidth) and finite(columnWidth) and finite(defaultTop)) then
		return nil
	end
	local left = (canvasWidth - columnWidth) / 2
	return clearanceBetween(
		rects,
		left,
		left + columnWidth,
		defaultTop,
		if finite(gap) then math.max(0, gap :: number) else 0
	)
end

-- Where the toast column goes (overlays fix; see the header). First its top, as toastClearance and toastTop give it for
-- the centred column; then sideways: every `beside` rect its band [top, top + height] meets narrows the room (one left
-- of the canvas centre pushes the room's left edge `gap` past its right edge, one right of it pulls the right edge in).
-- The column stays centred when the room allows, else it moves aside just enough, else it narrows to the room (not
-- below minWidth); with less room than that it goes `gap` under the lowest of them, full width and centred (never
-- past the middle of the canvas, toastTop). Moved aside, it can meet something above it the centred column missed:
-- then it starts under that too and is placed again.
function NotifyFormat.toastColumn(input: ColumnInput): Column
	local canvasWidth = if finite(input.canvas.X) then math.max(0, input.canvas.X) else 0
	local canvasHeight = input.canvas.Y
	local edge = if finite(input.edge) then math.max(0, input.edge) else 0
	local gap = if finite(input.gap) then math.max(0, input.gap) else 0
	local want =
		math.min(if finite(input.width) then math.max(0, input.width) else 0, math.max(0, canvasWidth - 2 * edge))
	local least = if finite(input.minWidth) then math.clamp(input.minWidth, 0, want) else want
	local height = if finite(input.height) then math.max(0, input.height) else 0
	local defaultTop = if finite(input.defaultTop) then input.defaultTop else 0
	local centred = (canvasWidth - want) / 2
	local x, width = centred, want
	local top = NotifyFormat.toastTop(
		canvasHeight,
		clearanceBetween(input.above, x, x + width, defaultTop, gap),
		defaultTop,
		gap
	)
	for _ = 1, COLUMN_PASSES do
		local low, high = edge, canvasWidth - edge
		local under: number? = nil
		for _, rect in input.beside do
			if usableRect(rect) and rect.y < top + height and top < rect.y + rect.h then
				if rect.x + rect.w / 2 < canvasWidth / 2 then
					low = math.max(low, rect.x + rect.w + gap)
				else
					high = math.min(high, rect.x - gap)
				end
				under = math.max(under or -math.huge, rect.y + rect.h)
			end
		end
		local room = high - low
		local pushed = false
		if room >= want then
			x, width = math.clamp(centred, low, high - want), want
		elseif room >= least and room > 0 then
			x, width = low, room
		else
			x, width = centred, want
			local below = NotifyFormat.toastTop(canvasHeight, under, top, gap)
			pushed = below > top
			top = below
		end
		local again = NotifyFormat.toastTop(
			canvasHeight,
			clearanceBetween(input.above, x, x + width, defaultTop, gap),
			defaultTop,
			gap
		)
		if again > top then
			top = again
		elseif not pushed then
			break
		end
	end
	return { x = x, y = top, width = width }
end

return NotifyFormat
