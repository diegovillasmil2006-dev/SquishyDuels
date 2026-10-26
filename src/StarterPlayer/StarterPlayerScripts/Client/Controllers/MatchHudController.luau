--!strict
-- MatchHudController (client only). Match HUD M4 (2026-10-16; plan work/matchhud2/PLAN.md §4 M4 = v1 M3a, v1 §1.3,
-- §1.9, §2.4): the base layer of every in-match screen of Diego's "Squishy Duels Match HUD.dc.html" (M). It draws
-- nothing of M itself: each later step adds one piece module to PIECES (M6 kill feed and medal, M7 knocked-out card
-- and respawn bar, M8 boot cover / intro / countdown, M9 end splash and results, M10 podium, M13 replay; M5's top bar
-- waits for Diego) with its Config.UI.Match.enabled switch. Match HUD M6 / M7 (2026-10-17): PIECES = the RESPAWNING
-- bar with the vignette ("respawn", drawn first: the vignette is behind everything), the "squished by" card ("card")
-- and the kill feed ("feed"), in UI/Match; M6's SQUISHED! medal is not built (Diego's kill banner is that moment).
-- Round 1 of the match screens (2026-10-26): the Loading arena cover, the intro and the 3-2-1 ("intro", drawn last;
-- ctx.loop gives it the crowd murmur's loop). End screens round A (2026-10-26): VICTORY! / DEFEAT, the results bar,
-- the buttons and the scoreboard ("finish", drawn last; ctx.act = LOBBY / PLAY AGAIN through MatchLeave / MatchJoin,
-- ctx.gripTotal = GripController.total for its Grip bar). Storm fix (2026-10-26): the IN THE STORM! health bar and
-- tint ("storm", UI/Match/StormBar, after the RESPAWNING bar; ctx.position = your character's root position). End
-- screens round B1 (2026-10-26): ctx.podium starts the finish piece's 3D podium (UI/Match/MatchPodium) with the
-- camera (CameraController.save / restore), the held squishies (HeldSquishyController.setHidden / gripC0), the hands
-- (FirstPersonController.setAway) and the settings' camera shake, which a UI module may not reach itself. The live top
-- bar (2026-10-26): "topBar" (UI/Match/TopBar, before the feed, which starts under it; ctx.toastsBelow). ctx
-- also gives the pieces play (SoundController.play, else a fallback key while the design's sound has no id),
-- touchAreas (with touch input: the thumbstick zone and ControlsController.touchLayout's buttons, base px; the card and
-- the bar keep off them), toastsBeside (UIController's) and `shared` (one table per session).
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

local Players = game:GetService("Players")
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
local DeathCard = require(Client.UI.Match.DeathCard)
local KillFeed = require(Client.UI.Match.KillFeed)
local MatchEnd = require(Client.UI.Match.MatchEnd)
local MatchIntro = require(Client.UI.Match.MatchIntro)
local MatchPodium = require(Client.UI.Match.MatchPodium)
local RespawnBar = require(Client.UI.Match.RespawnBar)
local StormBar = require(Client.UI.Match.StormBar)
local TopBar = require(Client.UI.Match.TopBar)
local CameraController = require(script.Parent.CameraController)
local ControlsController = require(script.Parent.ControlsController)
local FirstPersonController = require(script.Parent.FirstPersonController)
local GripController = require(script.Parent.GripController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
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
local TOUCH = Config.UI.Touch
local GUI_NAME = "SD_MatchHud"
local ROOT_NAME = "Root"
local FIXTURES = "MatchHudFixtures" -- Client/Studio, required only by a Studio preview
local REMOTE_JOIN = "MatchJoin" -- end screens round A: PLAY AGAIN (MatchController's chat commands use the same)
local REMOTE_LEAVE = "MatchLeave"
local ATTR_MATCH_ID = "SD_MatchId" -- MatchService's marks of a player in a match
local ATTR_PHASE = "SD_DuelPhase"
local AGAIN_WAIT_SECONDS = 6 -- PLAY AGAIN joins at the latest this long after its leave
local DEBUG_ONLY = "debugShow needs Studio with Config.Debug.debugHooks"
local PODIUM_HIDE = "podium" -- HeldSquishyController.setHidden's reason
local PODIUM_DEPS: MatchPodium.Deps = {
	saveCamera = CameraController.save,
	restoreCamera = CameraController.restore,
	setHeldHidden = function(player: Player, hidden: boolean)
		HeldSquishyController.setHidden(player, PODIUM_HIDE, hidden)
	end,
	gripC0 = HeldSquishyController.gripC0,
	setAway = FirstPersonController.setAway,
}

-- `require` with a runtime-found ModuleScript; the analyzer cannot resolve the Studio folder's path statically.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local MatchHudController = {}

-- The pieces, in draw order (a later one draws over an earlier one). Each later step adds its module's spec here.
local PIECES: { MatchHudFormat.PieceSpec } = {
	{ name = "respawn", new = RespawnBar.new }, -- M7
	{ name = "storm", new = StormBar.new }, -- storm fix: IN THE STORM! health bar and tint
	{ name = "topBar", new = TopBar.new }, -- the live top bar (before the feed: it tells the feed where it ends)
	{ name = "card", new = DeathCard.new }, -- M7
	{ name = "feed", new = KillFeed.new }, -- M6
	{ name = "intro", new = MatchIntro.new }, -- round 1 of the match screens: cover, intro, 3-2-1
	{ name = "finish", new = MatchEnd.new }, -- end screens round A: VICTORY! / DEFEAT, results, scoreboard
}
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

-- Match HUD M6 / M7: a piece's sound; `fallback` plays while `key` has nothing to play (no id yet: the design's
-- sounds wait for the owner's upload). A sound never stops a piece.
local function playSound(key: string, opts: { [string]: any }?, fallback: string?)
	local ok, played = pcall(SoundController.play, key, opts :: any)
	if fallback and not (ok and played) then
		pcall(SoundController.play, fallback, opts :: any)
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
		play = playSound,
		touchAreas = function(): { MatchHudFormat.Area }
			if ControlsController.preferredInput() ~= Enum.PreferredInput.Touch then
				return {}
			end
			local size, scale = gui.AbsoluteSize, UIController.scale()
			return MatchHudFormat.touchAreas(size, scale, ControlsController.touchLayout(size, scale, nil), TOUCH)
		end,
		toastsBeside = function(key: string, object: GuiObject?)
			UIController.toastsBeside(key, object)
		end,
		toastsBelow = function(key: string, object: GuiObject?)
			UIController.toastsBelow(key, object)
		end,
		shared = {},
		loop = function(key: string): any
			local ok, loop = pcall(SoundController.playLoop, key)
			return if ok then loop else nil
		end,
		act = function(action: string, mode: string?)
			if preview then
				return -- a Studio preview has no match to leave
			end
			NetController.fire(REMOTE_LEAVE) -- Remotes: MatchLeave() (the Result phase: back to the lobby now)
			if action == "again" and mode then
				-- The server refuses a join while it still marks you in the match (its return clears that a moment
				-- after the leave): wait for the marks to go, then join.
				task.spawn(function()
					local player = Players.LocalPlayer
					local deadline = os.clock() + AGAIN_WAIT_SECONDS
					while
						os.clock() < deadline
						and (
							(player:GetAttribute(ATTR_MATCH_ID) or "") ~= ""
							or (player:GetAttribute(ATTR_PHASE) or "") ~= ""
						)
					do
						task.wait(0.1)
					end
					NetController.fire(REMOTE_JOIN, mode) -- Remotes: MatchJoin(mode: string): queued again
				end)
			end
		end,
		gripTotal = GripController.total,
		podium = function(spec: any): any
			spec.shake = StateController.settings().cameraShake ~= false
			return MatchPodium.new(spec, PODIUM_DEPS)
		end,
		position = function(): Vector3?
			local character = Players.LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			return if root and root:IsA("BasePart") then root.Position else nil
		end,
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
