--!strict
-- MatchHudController (client only). Match HUD M4 (2026-10-16; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.3,
-- §1.9, §2.4): the base layer of every in-match screen of Diego's "Squishy Duels Match HUD.dc.html" (M). It draws
-- nothing of M itself: each later step adds one piece module to PIECES (M6 kill feed and medal, M7 knocked-out card
-- and respawn bar, M8 boot cover / intro / countdown, M9 end splash and results, M10 podium, M13 replay; M5's top bar
-- waits for Diego) with its Config.UI.Match.enabled switch. Today the list is empty, so a real match shows nothing new.
-- * Layer: the ScreenGui SD_MatchHud (spec Config.UI.Match.gui: DisplayOrder 14, over the touch buttons' SD_Touch 12
--   and SD_PracticeReticle 13, under SD_Dimmer 19; CoreUISafeInsets, so Roblox's top-left buttons and the notch stay
--   clear and UIController gives it the shared UIScale), made on first use through UIController.screenGui with that
--   spec as its fallback. Reading (plan v1 §1.9 said a Config.UI.ScreenGuis entry): a layer a controller owns stays
--   out of that table, which UIController creates at boot (DuelController:336-339's rule, as SD_DuelReticle, SD_Touch,
--   SD_Vfx), so nothing is made until a piece is. Over SD_Touch, a piece's non-button frames keep Active = false (the
--   default), so they never take a tap meant for the Throw / Ult / Dash buttons under them.
-- * Session: one per match (StateController.MatchChanged; MatchHudFormat.sessionAction): built at the match's first
--   view, rebuilt for another match, ended with the view. It builds the pieces whose enabled switch is on
--   (MatchHudFormat.build) in a "Root" frame (the whole safe area); with none it makes nothing (no ScreenGui, no frame,
--   no per-frame effect). Every piece call is in its own pcall: an error warns once per piece and call, never stops
--   the others or the session.
-- * Pieces (MatchHudFormat.Piece): new(ctx) builds it; update(view, now) right after the build and then every frame
--   from one Anim/Scheduler "render" effect (now = server time); onMoment(moment, view) for each new HUD moment
--   (StateController.MatchMoments: K.O.s with cause, streak, lives left, the final squish); layout() when the safe area
--   or the layout class changes; destroy() when the session ends.
-- * ctx (MatchHudFormat.Context): root; canvas() = the safe area in base px (v1 §1.3); compact() = the compact layout
--   class (Config.UI.Breakpoints: phones in landscape); reduced() = Anim/Tweens.reducedMotion() (Roblox's Reduce
--   Motion or the in-game switch: pieces skip scale effects and shorten fades, as Tweens and UiFx do); fit(base,
--   useHeight?) = the nested UIScale of a piece bigger than the safe area (v1 §1.3b, Config.UI.Match.compact.fitMin);
--   roster() / result() = StateController.matchRoster() / matchResult() (everyone seen this match; the first view with
--   an outcome, the Result freeze of v1 §2.4: the end screens read it, never a later view); preview.
-- * Studio preview (v1 §1.9: the MCP drives one client, and most states need another player): debugShow(state, opts?)
--   (Studio with Config.Debug.debugHooks only; DebugHooks' "matchHud" command) shows one Studio/MatchHudFixtures state
--   with pretend players: the fixture's view, roster and Result freeze stand in for StateController's, every piece is
--   built whatever its switch says (switched-off pieces can be checked before they go live), and the state's moments
--   play once. Refused while a real match is on; a real match view ends a preview. debugShow(nil) ends the preview and
--   lists the states, so one harness loops them all (with LayoutAudit at each screen size).
-- API: PIECES (the piece list; tests add fake pieces), debugShow(state?, opts?), debugState(), init(), start(),
-- destroy(). Require direction (§7): StateController and UIController (plus Anim and UI helpers); nothing requires it
-- but the bootstrap and DebugHooks (looked up at run time).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local Create = require(Client.UI.Create)
local MatchHudFormat = require(Client.UI.MatchHudFormat)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

type Live = { spec: MatchHudFormat.PieceSpec, piece: MatchHudFormat.Piece }

type Session = {
	matchId: string,
	preview: boolean,
	cleanup: Cleanup.Cleanup,
	live: { Live },
	view: () -> any, -- the view the pieces draw now
	effect: boolean, -- the per-frame effect runs
}

-- Constants

local HUD = Config.UI.Match
local GUI_NAME = "SD_MatchHud"
local ROOT_NAME = "Root"
local FIXTURES = "MatchHudFixtures" -- Client/Studio, required only by a Studio preview
local DEBUG_ONLY = "debugShow needs Studio with Config.Debug.debugHooks"

-- `require` with a runtime-found ModuleScript; the analyzer cannot resolve the Studio folder's path statically.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local MatchHudController = {}

-- The pieces, in draw order (a later one draws over an earlier one). Each later step adds its module's spec here.
local PIECES: { MatchHudFormat.PieceSpec } = {}
MatchHudController.PIECES = PIECES

-- Private

local log = Log.new("MatchHud")
local cleanup: Cleanup.Cleanup? = nil
local current: Session? = nil
local warned: { [string]: boolean } = {}

-- One piece call in its own pcall (a missing optional method is skipped); an error warns once per piece and call.
local function call(live: Live, method: string, ...: any)
	local fn = (live.piece :: any)[method]
	if type(fn) ~= "function" then
		return
	end
	local ok, err = pcall(fn, live.piece, ...)
	if not ok then
		local key = live.spec.name .. "." .. method
		if not warned[key] then
			warned[key] = true
			log:warn(`match HUD piece {key} failed:`, err)
		end
	end
end

local function step(session: Session): boolean
	if current ~= session then
		return false
	end
	local view = session.view()
	if view == nil then
		return true -- the session ends with MatchChanged(nil)
	end
	local now = Workspace:GetServerTimeNow()
	for _, live in session.live do
		call(live, "update", view, now)
	end
	return true
end

local function stopSession()
	local session = current
	current = nil
	if session then
		session.cleanup:clean()
	end
end

local function startSession(matchId: string, preview: boolean, view: () -> any, roster: () -> any, result: () -> any)
	local session: Session = {
		matchId = matchId,
		preview = preview,
		cleanup = Cleanup.new(),
		live = {},
		view = view,
		effect = false,
	}
	current = session
	local specs = MatchHudFormat.build(PIECES, HUD.enabled, preview)
	if #specs == 0 then
		return session -- nothing to draw: no ScreenGui, no frame, no effect
	end
	local sc = session.cleanup
	local gui = UIController.screenGui(GUI_NAME, HUD.gui)
	local root: Frame = Create("Frame", {
		Name = ROOT_NAME,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})
	sc:add(root)
	local function canvas(): Vector2
		return MatchHudFormat.canvas(gui.AbsoluteSize, UIController.scale())
	end
	local ctx: MatchHudFormat.Context = {
		root = root,
		preview = preview,
		canvas = canvas,
		compact = function(): boolean
			return UIController.layoutClass() == "compact"
		end,
		reduced = Tweens.reducedMotion,
		fit = function(pieceBase: Vector2, useHeight: boolean?): number
			return MatchHudFormat.fitScale(pieceBase, canvas(), HUD.compact.fitMin, useHeight)
		end,
		roster = roster,
		result = result,
	}
	for _, spec in specs do
		local ok, piece = pcall(spec.new, ctx)
		if ok and type(piece) == "table" then
			table.insert(session.live, { spec = spec, piece = piece })
		else
			log:warn(`match HUD piece {spec.name} was not built:`, piece)
		end
	end
	sc:add(function()
		for index = #session.live, 1, -1 do
			call(session.live[index], "destroy")
		end
		table.clear(session.live)
	end)
	local function layout()
		for _, live in session.live do
			call(live, "layout")
		end
	end
	sc:add(UIController.LayoutChanged:connect(layout))
	sc:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout))
	step(session) -- the first frame is drawn at once
	sc:add(Scheduler.add(function(): boolean
		return step(session)
	end, "render"))
	session.effect = true
	sc:add(function()
		session.effect = false
	end)
	return session
end

local function onMatchChanged(view: StateController.MatchView?, _old: StateController.MatchView?)
	local session = current
	local action = MatchHudFormat.sessionAction(
		if session then { matchId = session.matchId, preview = session.preview } else nil,
		if view then view.matchId else nil
	)
	if action == "stop" then
		stopSession()
	elseif (action == "start" or action == "restart") and view ~= nil then
		stopSession()
		startSession(
			view.matchId,
			false,
			StateController.match,
			StateController.matchRoster,
			StateController.matchResult
		)
	end
end

local function onMoments(moments: { StateController.MatchMoment }, view: StateController.MatchView)
	local session = current
	if session == nil or session.preview or session.matchId ~= view.matchId then
		return
	end
	for _, moment in moments do
		for _, live in session.live do
			call(live, "onMoment", moment, view)
		end
	end
end

local function fixtures(): any
	local studio = Client:FindFirstChild("Studio")
	local module = if studio then studio:FindFirstChild(FIXTURES) else nil
	if module == nil or not module:IsA("ModuleScript") then
		return nil
	end
	return dynamicRequire(module)
end

local function pieceNames(session: Session?): { string }
	local names: { string } = {}
	if session then
		for _, live in session.live do
			table.insert(names, live.spec.name)
		end
	end
	return names
end

-- Public

-- Studio preview (see the header). state nil ends the preview and lists the states; opts = MatchHudFixtures.Options
-- (players = 4..12, ...). Reply { ok, state?, states?, pieces?, phase?, matchPhase?, players?, moments?, outcome?,
-- compact?, scale?, error? }.
function MatchHudController.debugShow(state: string?, opts: any?): { [string]: any }
	if not (RunService:IsStudio() and Config.Debug.debugHooks) then
		return { ok = false, error = DEBUG_ONLY }
	end
	local Fixtures = fixtures()
	if Fixtures == nil then
		return { ok = false, error = `no Client.Studio.{FIXTURES}` }
	end
	local session = current
	if state == nil then
		if session and session.preview then
			stopSession()
		end
		return { ok = true, states = table.clone(Fixtures.STATES) }
	end
	if StateController.match() ~= nil or (session ~= nil and not session.preview) then
		return { ok = false, error = "a real match is on; no preview" }
	end
	local fixture = Fixtures.build(state, Workspace:GetServerTimeNow(), opts)
	if fixture == nil then
		return { ok = false, error = `unknown state {tostring(state)}`, states = table.clone(Fixtures.STATES) }
	end
	stopSession()
	local view = fixture.view
	local preview = startSession(view.matchId, true, function(): any
		return view
	end, function(): any
		return fixture.roster
	end, function(): any
		return fixture.result
	end)
	for _, moment in fixture.moments do
		for _, live in preview.live do
			call(live, "onMoment", moment, view)
		end
	end
	return {
		ok = true,
		state = state,
		pieces = pieceNames(preview),
		phase = view.phase,
		matchPhase = view.matchPhase,
		players = #view.players,
		moments = #fixture.moments,
		outcome = if view.outcome then view.outcome.kind else nil,
		compact = UIController.layoutClass() == "compact",
		scale = UIController.scale(),
	}
end

-- Studio / leak checks: the running session, its pieces and whether its per-frame effect runs.
function MatchHudController.debugState(): { [string]: any }
	local session = current
	return {
		matchId = if session then session.matchId else nil,
		preview = if session then session.preview else false,
		pieces = pieceNames(session),
		effect = session ~= nil and session.effect,
	}
end

-- Lifecycle

function MatchHudController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(StateController.MatchChanged:connect(onMatchChanged))
	c:add(StateController.MatchMoments:connect(onMoments))
	c:add(stopSession)
end

function MatchHudController.start()
	-- A match already running when this client starts (a late start) still gets its session.
	local view = StateController.match()
	if view then
		onMatchChanged(view, nil)
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function MatchHudController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
	stopSession()
end

return MatchHudController
