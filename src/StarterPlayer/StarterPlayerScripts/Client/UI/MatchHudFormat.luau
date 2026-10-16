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
}

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

return MatchHudFormat
