--!strict
-- MatchHudFormat (client only, pure). Match HUD M4 (2026-10-16; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.3,
-- §1.9): the base rules of the in-match screens of Diego's "Squishy Duels Match HUD.dc.html" (MatchHudController) and
-- the piece contract every later step builds on. Plain data in and out (views are StateController.MatchView tables, as
-- in UI/MatchFormat), so it is unit-tested in Edit mode (MatchHudFormat_Test).
--   Piece contract (types): a piece module's new(ctx: Context) builds the piece under ctx.root and returns a Piece:
--     update(view, now)        every frame while the session lasts (view = the match view; now = server time)
--     onMoment?(moment, view)  each new HUD moment (StateController.MatchMoments: K.O.s, ...)
--     layout?()                the safe area or the layout class changed
--     destroy()                the session ends
--   canvas(size, scale) -> Vector2     the safe area in base px: the pieces sit under the shared UIScale, so a
--                                      ScreenGui of `size` actual px holds size / scale base px (v1 §1.3, HudController
--                                      layoutAll's canvas); zero for a bad size or scale
--   fitScale(pieceBase, canvas, fitMin, useHeight?) -> number
--                                      v1 §1.3b: a piece bigger than the safe area gets its own nested UIScale =
--                                      clamp(canvas / pieceBase, fitMin, 1) on width, and on height too when
--                                      useHeight (the smaller of the two); 1 for a bad size
--   build(specs, enabled, preview) -> { PieceSpec }
--                                      the pieces a session builds, in list order: all of them in a Studio preview,
--                                      in a real match only those whose Config.UI.Match.enabled switch is true
--   sessionAction(session, matchId) -> "keep" | "start" | "restart" | "stop"
--                                      what a real match view of `matchId` (nil = no view) does to the running
--                                      session: a first view starts one, another match restarts it, a real view ends a
--                                      Studio preview (restart as real), no view stops a real session and leaves a
--                                      preview alone
-- Match HUD M6 / M7 (2026-10-17; plan work/matchhud2/PLAN.md §4 M6 = v1 M4, M7 = v1 M5, §12; M = "Squishy Duels Match
-- HUD.dc.html"): the rules of the kill feed (UI/Match/KillFeed), the "squished by" card (UI/Match/DeathCard) and the
-- RESPAWNING bar with the vignette (UI/Match/RespawnBar). The base gives every piece three more helpers (Context:
-- play, touchAreas, toastsBeside) and one table per session (shared: the card publishes its rect there, the bar
-- keeps clear of it).
--   newFeedMemory() / feedLine(memory, moment, youId, windowS, streakMin) -> FeedLine?
--                                      one feed line per K.O. moment (M:516-533): no attacker (storm, fall; owner
--                                      2026-10-16: a line for them too, [P]) = a cause line with no tag that never
--                                      uses up FIRST BLOOD; else the tag, first that applies: final -> FINAL KILL,
--                                      the match's first K.O. with an attacker -> FIRST BLOOD (only when this
--                                      client saw the match's first moment, seq 1: a late start never calls a later
--                                      K.O. first blood), the attacker's 3rd+ K.O. each under windowS after the last
--                                      (by the moments' server time) -> TRIPLE!, the 2nd -> DOUBLE!, the attacker's
--                                      streak >= streakMin -> "{n} STREAK"; mine = "by" / "victim" when that is you
--   tagText(line) -> string?            the tag's words (Strings.matchHud.feed)
--   feedPose(age, leaveAt, cfg) -> (phase, u)   a feed row `age` s after it came in: "in" (u 0..1 over
--                                      enter.ms), "hold", "out" (u over leave.ms from the earlier of leave.atMs and
--                                      leaveAt, an early leave when the list is full), "gone"
--   playerLook(mode, team, slot) -> PlayerLook   a player's colours (M:389-397): TDM by team (Strawberry /
--                                      Blueberry), FFA by slot (M's 6 colours in turn); the name colour and the
--                                      head / pill gradient stops
--   deadColor(color, gray, brightness) -> Color3   v1 §1.11: CSS grayscale(gray) brightness(b) of one colour
--   cardShows(moment, view) -> boolean  the "squished by" card: you are the victim of a K.O. that did not end the
--                                      match, in Active / Overtime (M:536; with or without an attacker, owner)
--   squishyTitle(catalogId) / causeCard(cause)   the card's quoted title (M:388) / its words for a K.O. with no
--                                      attacker (storm, fall, other) [P]
--   respawnShows(view) / respawnLeft(respawnAt, now) / respawnShare(respawnAt, now, total)
--                                      the bar shows while you are knocked out, not out of lives, with a respawn
--                                      time, in Active / Overtime; its number = whole seconds left, at least 1
--                                      (M:641); its fill = the share of the wait gone (v1 §1.11: server time)
--   touchAreas(screen, scale, layout, touch) -> { Area }   touch input: the thumbstick zone (Config.UI.Touch's
--                                      lower-left share) and the Throw / Ultimate / Dash / jump buttons
--                                      (ControlsController.touchLayout, px) as base px rects
--   cardPlace(canvas, areas, size, cfg) -> Place   the card at the bottom-left (M:156), or, with touch areas, just
--                                      above the thumbstick zone (owner 2026-10-16: it never covers the thumbstick
--                                      corner), shrunk to fit (fitMin floor; compact screens: compactShare of the
--                                      height, v1 §1.3e)
--   barPlace(canvas, areas, card, size, cfg) -> Place   the bar centred at the bottom (M:196); v1 §1.3h: beside the
--                                      card, else above it, when they would meet; never on an area (RespawnBar gives
--                                      it the thumbstick zone only [P]: the touch buttons do nothing while you are
--                                      knocked out and the bar is gone at the respawn); each place tried at each of
--                                      cfg.scales (down to fitMin) before the next
--   trackPose(frames, t, ms, curve, wholeRun, reduced, fadeMs) -> Pose   one-shot @keyframes at t seconds
--                                      (Anim/Tweens.poseAt), the ReducedMotion way of Tweens.keyframes: only the
--                                      fade moves, at most fadeMs
--   clipText(text, maxWidth, measure) -> string   cut with "…" to fit (measure = Theme.textWidth in the game)

-- Requires

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local Tweens = require(script.Parent.Parent.Anim.Tweens)

-- Types

-- What the base gives every piece (MatchHudController builds it per session).
export type Context = {
	root: Frame, -- the pieces' parent: SD_MatchHud's whole safe area, under the shared UIScale
	preview: boolean, -- a Studio preview (MatchHudController.debugShow), not a real match
	canvas: () -> Vector2, -- the safe area in base px (canvas above)
	compact: () -> boolean, -- Config.UI.Breakpoints' compact class (UIController.layoutClass)
	reduced: () -> boolean, -- reduced motion: skip scale effects, shorten fades (Anim/Tweens.reducedMotion)
	fit: (pieceBase: Vector2, useHeight: boolean?) -> number, -- fitScale on this canvas and the Config fitMin
	roster: () -> any, -- StateController.MatchRoster? (every player seen this match)
	result: () -> any, -- StateController.MatchView? (the first view with an outcome: the Result freeze)
	-- Match HUD M6 / M7:
	play: (key: string, opts: { [string]: any }?, fallback: string?) -> (), -- a sound; `fallback` while it has no id
	touchAreas: () -> { Area }, -- touch input: the thumbstick zone and the touch buttons (base px); else none
	toastsBeside: (key: string, object: GuiObject?) -> (), -- the toast column keeps clear of `object` (nil: drop it)
	shared: { [string]: any }, -- one table per session, for the pieces (the card's rect: `cardRect`)
}

-- Match HUD M6 / M7: a rect in base px, top-left origin (the safe area).
export type Area = { x: number, y: number, w: number, h: number, kind: string? } -- kind: touchAreas' "zone" / "button"

-- A piece's place: its top-left (base px) and its nested UIScale.
export type Place = { x: number, y: number, scale: number, kind: string }

export type FeedMemory = {
	started: boolean, -- a moment was seen
	sawStart: boolean, -- the first one seen was the match's first (seq 1)
	firstBlood: boolean, -- FIRST BLOOD is used up
	multi: { [number]: { at: number, n: number } }, -- attacker -> their last K.O. time and run
}

export type FeedLine = {
	victim: number,
	by: number?, -- nil: storm, fall (`cause`)
	cause: string,
	tag: string?, -- "final" | "firstBlood" | "triple" | "double" | "streak"
	streak: number?, -- the attacker's streak (the "{n} STREAK" tag)
	mine: string?, -- "by" | "victim": you squished / were squished
}

export type PlayerLook = { text: Color3, top: Color3, mid: Color3?, faceEnd: Color3 }

export type CardWords = { pill: string, name: string, line: string }

export type Piece = {
	update: (self: any, view: any, now: number) -> (),
	onMoment: ((self: any, moment: any, view: any) -> ())?,
	layout: ((self: any) -> ())?,
	destroy: (self: any) -> (),
}

-- One entry of MatchHudController's piece list: `name` = its Config.UI.Match.enabled switch.
export type PieceSpec = {
	name: string,
	new: (ctx: Context) -> Piece,
}

export type Session = { matchId: string, preview: boolean }
export type SessionAction = "keep" | "start" | "restart" | "stop"

-- Constants

local TEAM_NAMES = Config.Match.teamNames
local LIVE_PHASES: { [string]: boolean } = { Active = true, Overtime = true }
-- M:389-390 TEAM (Strawberry, Blueberry: txt, then the 180deg bg stops 0%, 58%, 100%).
local TEAM_LOOKS: { PlayerLook } = {
	{
		text = Palette.MatchTeamRedText,
		top = Palette.MatchTeamRedTop,
		mid = Palette.StickerTdmRed,
		faceEnd = Palette.MatchTeamRedEnd,
	},
	{
		text = Palette.MatchTeamBlueText,
		top = Palette.MatchTeamBlueTop,
		mid = Palette.StickerTdmBlue,
		faceEnd = Palette.MatchTeamBlueEnd,
	},
}
-- M:392-395 FFA (hex = the name, bg = its 180deg top -> hex), in turn by roster slot.
local FFA_LOOKS: { PlayerLook } = {
	{ text = Palette.StickerFxPink, top = Palette.MatchFfaPinkTop, faceEnd = Palette.StickerFxPink },
	{ text = Palette.MatchFfaCyan, top = Palette.MatchFfaCyanTop, faceEnd = Palette.MatchFfaCyan },
	{ text = Palette.StickerGoldMid, top = Palette.StickerCreamYellow, faceEnd = Palette.StickerGoldMid },
	{ text = Palette.MatchFfaMint, top = Palette.MatchFfaMintTop, faceEnd = Palette.MatchFfaMint },
	{ text = Palette.MatchFfaPurple, top = Palette.MatchFfaPurpleTop, faceEnd = Palette.MatchFfaPurple },
	{ text = Palette.MatchFfaOrange, top = Palette.MatchFfaOrangeTop, faceEnd = Palette.MatchFfaOrange },
}
-- Reading: someone with no team or slot (never in a real view) gets the purple card's colours.
local NEUTRAL_LOOK: PlayerLook =
	{ text = Palette.StickerTextSoft, top = Palette.StickerCardTop, faceEnd = Palette.StickerCardBottom }
local TOUCH_BUTTONS = { "throw", "ultimate", "dash", "jump", "catch" } -- qb1: Catch too (catching works in a match)
local ELLIPSIS = "…"

-- Module table

local MatchHudFormat = {}

-- Private

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

-- Public

function MatchHudFormat.canvas(size: Vector2, scale: number): Vector2
	if not (finite(scale) and scale > 0 and finite(size.X) and finite(size.Y) and size.X > 0 and size.Y > 0) then
		return Vector2.zero
	end
	return size / scale
end

function MatchHudFormat.fitScale(pieceBase: Vector2, canvas: Vector2, fitMin: number, useHeight: boolean?): number
	local function share(room: number, need: number): number
		if not (finite(room) and finite(need) and room > 0 and need > 0) then
			return 1
		end
		return room / need
	end
	local fit = share(canvas.X, pieceBase.X)
	if useHeight then
		fit = math.min(fit, share(canvas.Y, pieceBase.Y))
	end
	local low = if finite(fitMin) then math.clamp(fitMin, 0, 1) else 1
	return math.clamp(fit, low, 1)
end

function MatchHudFormat.build(specs: { PieceSpec }, enabled: { [string]: boolean }, preview: boolean): { PieceSpec }
	local out: { PieceSpec } = {}
	for _, spec in specs do
		if preview or enabled[spec.name] == true then
			table.insert(out, spec)
		end
	end
	return out
end

function MatchHudFormat.sessionAction(session: Session?, matchId: string?): SessionAction
	if session == nil then
		return if matchId ~= nil then "start" else "keep"
	end
	if matchId == nil then
		return if session.preview then "keep" else "stop"
	end
	if session.preview or session.matchId ~= matchId then
		return "restart"
	end
	return "keep"
end

-- Match HUD M6: the kill feed ------------------------------------------------------------------------------------

function MatchHudFormat.newFeedMemory(): FeedMemory
	return { started = false, sawStart = false, firstBlood = false, multi = {} }
end

function MatchHudFormat.feedLine(
	memory: FeedMemory,
	moment: any,
	youId: number?,
	windowS: number,
	streakMin: number
): FeedLine?
	if type(moment) ~= "table" or moment.kind ~= "ko" or type(moment.victim) ~= "number" then
		return nil
	end
	if not memory.started then
		memory.started = true
		memory.sawStart = moment.seq == 1
	end
	local victim: number = moment.victim
	local by: number? = if type(moment.by) == "number" then moment.by else nil
	local mine = if by ~= nil and by == youId then "by" elseif victim == youId then "victim" else nil
	local cause = if type(moment.cause) == "string" then moment.cause else "hit"
	if by == nil then
		-- M:517 drops these; the owner wants a line (nobody to blame): no tag, FIRST BLOOD kept for later.
		return { victim = victim, by = nil, cause = cause, tag = nil, streak = nil, mine = mine }
	end
	local at = if type(moment.at) == "number" then moment.at else 0
	local last = memory.multi[by]
	local run = if last and at - last.at < windowS then last.n + 1 else 1
	memory.multi[by] = { at = at, n = run }
	local streak = if type(moment.streak) == "number" then moment.streak else 1
	local tag: string? = nil
	if moment.final == true then
		tag = "final"
	elseif not memory.firstBlood and memory.sawStart then
		tag = "firstBlood"
	elseif run >= 3 then
		tag = "triple"
	elseif run == 2 then
		tag = "double"
	elseif streak >= streakMin then
		tag = "streak"
	end
	memory.firstBlood = true -- M:528: the first K.O. with an attacker uses it up, whatever its tag
	return { victim = victim, by = by, cause = cause, tag = tag, streak = streak, mine = mine }
end

function MatchHudFormat.tagText(line: FeedLine): string?
	local tag = line.tag
	if tag == nil then
		return nil
	end
	local words = Strings.matchHud.feed
	if tag == "streak" then
		return Strings.format(words.streak, { n = line.streak or 0 })
	end
	local text = (words :: any)[tag]
	return if type(text) == "string" then text else nil
end

function MatchHudFormat.feedPose(age: number, leaveAt: number?, cfg: any): (string, number)
	local inS = cfg.enter.ms / 1000
	local outS = cfg.leave.ms / 1000
	local leave = math.min(leaveAt or math.huge, cfg.leave.atMs / 1000)
	if age >= leave then
		local u = if outS > 0 then (age - leave) / outS else 1
		if u >= 1 then
			return "gone", 1
		end
		return "out", u
	end
	if inS > 0 and age < inS then
		return "in", math.max(age, 0) / inS
	end
	return "hold", 1
end

function MatchHudFormat.playerLook(mode: string?, team: string?, slot: number?): PlayerLook
	if mode == "tdm" then
		if team ~= nil and team == TEAM_NAMES[1] then
			return TEAM_LOOKS[1]
		elseif team ~= nil and team == TEAM_NAMES[2] then
			return TEAM_LOOKS[2]
		end
		return NEUTRAL_LOOK
	end
	if type(slot) == "number" and finite(slot) and slot >= 1 then
		return FFA_LOOKS[(math.floor(slot) - 1) % #FFA_LOOKS + 1]
	end
	return NEUTRAL_LOOK
end

function MatchHudFormat.deadColor(color: Color3, gray: number, brightness: number): Color3
	local g = if finite(gray) then math.clamp(gray, 0, 1) else 0
	local b = if finite(brightness) then math.max(brightness, 0) else 1
	local l = 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B -- CSS grayscale's luminance
	local function channel(c: number): number
		return math.clamp((c + (l - c) * g) * b, 0, 1)
	end
	return Color3.new(channel(color.R), channel(color.G), channel(color.B))
end

-- Match HUD M7: the "squished by" card and the RESPAWNING bar ------------------------------------------------------

function MatchHudFormat.cardShows(moment: any, view: any): boolean
	return type(moment) == "table"
		and moment.kind == "ko"
		and type(view) == "table"
		and type(view.you) == "table"
		and moment.victim == view.you.userId
		and moment.final ~= true
		and LIVE_PHASES[view.matchPhase] == true
end

function MatchHudFormat.squishyTitle(catalogId: string?): string
	local titles = Strings.matchHud.titles :: { [string]: string }
	local title = if catalogId then titles[catalogId] else nil
	return title or titles.fallback
end

function MatchHudFormat.causeCard(cause: string?): CardWords
	local words = Strings.matchHud.card.cause :: { [string]: CardWords }
	return (if cause then words[cause] else nil) or words.other
end

function MatchHudFormat.respawnShows(view: any): boolean
	local you = if type(view) == "table" then view.you else nil
	return type(you) == "table"
		and you.alive == false
		and you.out ~= true
		and type(you.respawnAt) == "number"
		and LIVE_PHASES[view.matchPhase] == true
end

function MatchHudFormat.respawnLeft(respawnAt: number, now: number): number
	local left = respawnAt - now
	if not finite(left) then
		return 1
	end
	return math.max(1, math.ceil(left))
end

function MatchHudFormat.respawnShare(respawnAt: number, now: number, total: number): number
	if not (finite(total) and total > 0) then
		return 1
	end
	local share = 1 - (respawnAt - now) / total
	if not finite(share) then
		return 1
	end
	return math.clamp(share, 0, 1)
end

function MatchHudFormat.touchAreas(screen: Vector2, scale: number, layout: any, touch: any): { Area }
	local s = if finite(scale) and scale > 0 then scale else 1
	local zoneW = screen.X * touch.thumbstickZoneWidth
	local zoneH = screen.Y * touch.thumbstickZoneHeight
	local areas: { Area } = { { x = 0, y = (screen.Y - zoneH) / s, w = zoneW / s, h = zoneH / s, kind = "zone" } }
	if type(layout) == "table" then
		for _, key in TOUCH_BUTTONS do
			local r = layout[key]
			if type(r) == "table" then
				table.insert(areas, { x = r.x / s, y = r.y / s, w = r.w / s, h = r.h / s, kind = "button" })
			end
		end
	end
	return areas
end

local function meets(a: Area, b: Area, margin: number): boolean
	return a.x < b.x + b.w + margin
		and b.x < a.x + a.w + margin
		and a.y < b.y + b.h + margin
		and b.y < a.y + a.h + margin
end

function MatchHudFormat.cardPlace(canvas: Vector2, areas: { Area }, size: Vector2, cfg: any): Place
	local floor = canvas.Y - cfg.bottom
	local kind = "corner"
	for _, area in areas do
		-- an area under the card's column (M:156's bottom-left corner) lifts the card's bottom above it
		if area.x < cfg.left + size.X and area.x + area.w > cfg.left and area.y - cfg.gap < floor then
			floor = area.y - cfg.gap
			kind = "aboveTouch"
		end
	end
	local scale = 1
	if size.X > 0 and size.Y > 0 then
		scale = math.min(1, (canvas.X - 2 * cfg.left) / size.X, (floor - cfg.top) / size.Y)
		if cfg.compact then
			scale = math.min(scale, cfg.compactShare * canvas.Y / size.Y)
		end
	end
	scale = if finite(scale) then math.clamp(scale, cfg.fitMin, 1) else 1
	return { x = cfg.left, y = math.max(floor - size.Y * scale, 0), scale = scale, kind = kind }
end

function MatchHudFormat.barPlace(canvas: Vector2, areas: { Area }, card: Area?, size: Vector2, cfg: any): Place
	local function fits(rect: Area): boolean
		if rect.x < 0 or rect.x + rect.w > canvas.X or rect.y < cfg.top or rect.y + rect.h > canvas.Y then
			return false
		end
		if card and meets(rect, card, cfg.gap - 1e-6) then
			return false
		end
		for _, area in areas do
			if meets(rect, area, cfg.gap - 1e-6) then
				return false
			end
		end
		return true
	end
	-- Where each place puts a w x h bar (nil: not available).
	local function at(kind: string, w: number, h: number): Area?
		local floor = canvas.Y - cfg.bottom
		if kind == "centre" then
			return { x = (canvas.X - w) / 2, y = floor - h, w = w, h = h }
		elseif kind == "beside" and card then
			return { x = card.x + card.w + cfg.gap, y = math.min(floor, card.y + card.h) - h, w = w, h = h }
		elseif kind == "above" and card then
			return { x = (canvas.X - w) / 2, y = card.y - cfg.gap - h, w = w, h = h }
		elseif kind == "lifted" then
			local x = (canvas.X - w) / 2
			local top = floor
			for _, area in areas do
				if area.x < x + w + cfg.gap and x < area.x + area.w + cfg.gap then
					top = math.min(top, area.y - cfg.gap)
				end
			end
			return { x = x, y = top - h, w = w, h = h }
		end
		return nil
	end
	local widthFit = if size.X > 0 then (canvas.X - 2 * cfg.gap) / size.X else 1
	for _, kind in { "centre", "beside", "above", "lifted" } do
		for _, s in cfg.scales do
			local scale = math.clamp(math.min(s, widthFit), cfg.fitMin, 1)
			local rect = at(kind, size.X * scale, size.Y * scale)
			if rect and fits(rect) then
				return { x = rect.x, y = rect.y, scale = scale, kind = kind }
			end
		end
	end
	local scale = math.clamp(widthFit, cfg.fitMin, 1)
	local rect = at("centre", size.X * scale, size.Y * scale) :: Area
	return { x = rect.x, y = rect.y, scale = scale, kind = "centre" }
end

function MatchHudFormat.trackPose(
	frames: any, -- { Tweens.Pose } (Config tables)
	t: number,
	ms: number,
	curve: string?,
	wholeRun: string?,
	reduced: boolean,
	fadeMs: number
): Tweens.Pose
	local duration = math.max(ms / 1000, 0)
	local u = if duration > 0 then math.clamp(t / duration, 0, 1) else 1
	if not reduced then
		return Tweens.poseAt(frames, u, curve, wholeRun)
	end
	-- ReducedMotion (Tweens.keyframes' PR9 rule): nothing moves; the fade in and out, each at most fadeMs.
	local first = Tweens.poseAt(frames, 0, curve, wholeRun).alpha
	local last = Tweens.poseAt(frames, 1, curve, wholeRun).alpha
	if first == nil then
		return {}
	end
	local peak = math.max(first, last or first)
	for _, frame in frames do
		peak = math.max(peak, frame.alpha or peak)
	end
	local fade = math.min(math.max(fadeMs, 0) / 1000, duration / 2)
	local alpha = peak
	if first < peak and fade > 0 and t < fade then
		alpha = first + (peak - first) * math.max(t, 0) / fade
	elseif last ~= nil and last < peak and t > duration - fade then
		local k = if fade > 0 then math.min((t - (duration - fade)) / fade, 1) else 1
		alpha = peak + (last - peak) * k
	end
	return { alpha = alpha }
end

function MatchHudFormat.clipText(text: string, maxWidth: number, measure: (text: string) -> number): string
	if measure(text) <= maxWidth then
		return text
	end
	local count = utf8.len(text) or #text
	for keep = count - 1, 1, -1 do
		local stop = utf8.offset(text, keep + 1) or (#text + 1)
		local cut = string.sub(text, 1, stop - 1) .. ELLIPSIS
		if measure(cut) <= maxWidth then
			return cut
		end
	end
	return ELLIPSIS
end

return MatchHudFormat
