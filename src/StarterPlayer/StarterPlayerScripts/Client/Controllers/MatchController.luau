--!strict
-- MatchController (client only). FFA/TDM v1 (2026-10-15): the client side of the 12-player Free for All / Team
-- Deathmatch played inside this lobby server on Diego's maps (Workspace.DuelMaps; SPEC D5, D6, D8, D10, D11, D13; the
-- rules are Config.Match and the server's MatchService / MatchRules). It follows StateController's match view (match()
-- / MatchChanged) and sends intent only: the server decides who plays, who is hit and who wins.
--
-- * Entry (D6, no new art): the chat commands /ffa, /tdm and /leave (TextChatCommand instances made here under
--   TextChatService in a folder SD_MatchCommands; with the legacy chat, the local player's Chatted; MatchFormat
--   .commandOf) fire MatchJoin(mode "ffa" | "tdm") and MatchLeave. The server answers with match.* Notify toasts
--   (shown by NotifyController), the match view and the SD_* attributes (the Duel input context, the freeze, the locks).
-- * Match look (D13): while a match view exists, DuelController's HUD (through the hooks of attachDuelHud, called once
--   from DuelController.init) shows only the reticle with its "Hit!", the bottom key dock (qb1: catch meter too), and
--   the 3-2-1 countdown at Countdown; its 1v1 pieces (top bar, Forfeit button, edge arrow, the opponent's Rush chip,
--   "In the lane!") stay hidden. Review fix (2026-10-15): the top bar hides through DuelController's hideBar (reason
--   "match", undone when the match ends), and a 1v1 result card still open from a duel just before is closed. The
--   storm wall, the readout and the map animations each run in their own pcall, so a failure there never stops the
--   reticle, the dock or the countdown. Match HUD M7 (2026-10-17): while you are knocked out the dock hides (with
--   Config.UI.Match.enabled.respawn: MatchHudController's RESPAWNING bar sits there).
-- * Readout (D13, a TEST READOUT until Diego's arena HUD): one Components/Chip at the top centre of SD_DuelHud, its text
--   MatchFormat.readout (K.O.s and the leader, or the team lives; the timer; the storm bar; overtime; the respawn wait),
--   refreshed Config.Match.readoutHz times a second (every frame when that is missing); toasts start under it while it
--   shows (UIController.toastsBelow "match").
-- * Lighting and map animations (D10): Diego's ReplicatedStorage.DuelMapScripts.MapLighting.Apply(mapCode) when the
--   local player's match view appears and MapLighting.Reset() when it ends; MapAnimations_<mapCode>.Start(map) (the
--   Workspace.DuelMaps child whose MapCode attribute is the view's mapCode) once the phase reaches Countdown (reading:
--   the player has been moved to the map by then, so its parts are streamed in; review fix: while the map model is
--   not on this client yet, it is looked for again every ANIMATION_RETRY_SECONDS), and its stop function when the view
--   ends. This client only (on the server it would relight the whole lobby); every call in a pcall; Diego's modules
--   are never changed.
-- * Storm wall (D11, TDM; a TEST PLACEHOLDER until Diego's storm design): the safe circle's edge around the map's centre
--   (arena.centre), Config.Match.Storm.wall.heightStuds tall from the floor, in Palette[wall.color] (a token name) at
--   wall.transparency, Material ForceField, Anchored with CanCollide / CanQuery / CanTouch / CastShadow off, under
--   Workspace.SD_ClientFx; its radius every frame from StormMath.radiusAt with the server-synced Active time
--   (MatchFormat.stormRadius), shown only while StormMath.shown (and the match is live). Reading (deviation from "one
--   Cylinder Part"): a Part draws only its outside faces, so a cylinder would be invisible to everyone inside the safe
--   circle; the wall is a ring of WALL_SEGMENTS thin segments instead (drawn from both sides), with the same props.
-- * Reset (D5): StarterGui:SetCore("ResetButtonCallback", false) while a match view exists (retried until CoreGui
--   accepts it), true after; the server re-places a character that dies anyway.
-- * Catch: qb1 (owner 2026-10-18 "Yes, catching works"): catching works in a match as in a duel (CatchController's
--   gate and prompt); the dock's catch meter and the touch Catch button show as in a duel (D8's hiding is gone).
-- * Power-up pads (power-ups v1.1, 2026-10-16, SPEC P4; no new art): when a pad's readyAt (the view's pads, server
--   time) rises above the one last played and still lies ahead, Diego's MapAnimations_<mapCode>.Collect(padModel,
--   readyAt - now) plays its pop and refill timer (MatchFormat.padCollectSeconds; padModel = the map's descendant with
--   the pad's name). Only once the map animations run (their Start registers the pads): checked on every MatchChanged
--   and right after they start (a pad taken before that still shows its refill). In a pcall; Diego's modules are never
--   changed. The readout lists the own live power-ups with their seconds left (MatchFormat.readout).
--   Review fixes (2026-10-16): his refill timer gets a head start of one pickup sample (1 / Config.Match.Storm
--   .sampleHz, MatchFormat.collectRefill), so it is over before the server can report the pad taken again (his Collect
--   ignores a pad still refilling), and a refill shorter than his pop (DIEGO_POP_SECONDS) is not played. His Start
--   registers only the pads whose parts are on this client, so it waits (streaming: the pad Models are there from the
--   join, their MeshParts stream in by distance) until every pad of the view has its _Pickup, _Ring and _Fill parts,
--   at most PAD_STREAM_WAIT_SECONDS, then starts anyway (warned once). It also waits while a refill handed to his
--   Collect on the same map in an earlier match still plays (his stop() leaves it running; a Start then would record
--   the vanished pickup's size and keep that pad tiny on this client for the session).
-- * Result sting (music job, 2026-10-16): once per match, when the view's outcome first arrives, the local player's
--   result (MatchFormat.resultOf, the win streak's rule) plays a duel's jingle (DuelFormat.resultStyle: duel.win /
--   duel.lose / duel.draw) Config.Audio.matchStingDelaySeconds later (Diego's end sound starts 250 ms after the final
--   K.O., "Squishy Duels Match HUD.dc.html" M:570); nothing for a cancelled or void match, nothing once the look ended
--   (its cleanup cancels the wait). The duel music itself is SoundController's (Config.Audio.battleMusic).
-- API: attachDuelHud(hooks) -> detach (DuelController only); counts() (Studio debug); init(), start(), destroy().
-- Require direction (§7): StateController, NetController, SoundController, ThrowController and
-- UIController (plus UI helpers and shared modules); DuelController requires this module in its init, never the other
-- way round.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)

local Client = script.Parent.Parent
local Chip = require(Client.UI.Components.Chip)
local DuelFormat = require(Client.UI.DuelFormat)
local MatchFormat = require(Client.UI.MatchFormat)
local Theme = require(Client.UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local UIController = require(script.Parent.UIController)

-- Types

-- DuelController's HUD pieces for the match look (its Hud is private: `any` here).
export type DuelHudHooks = {
	hud: () -> any?,
	reticle: (h: any, view: any, aim: any, now: number) -> (),
	hints: (h: any, view: any, aim: any) -> (),
	countdown: (h: any, now: number) -> (),
	ultReady: (view: any) -> (),
	hideCountdown: (h: any) -> (),
	setCountdown: (endsAt: number?) -> (),
	reset: (h: any) -> (),
	hideBar: (h: any, reason: string, hidden: boolean) -> (), -- the top bar's barHidden bookkeeping
	closeResult: () -> (), -- closes a 1v1 result card that is still open
}

-- One match's look, from its first view to the end of the view.
type Look = {
	matchId: string,
	cleanup: Cleanup.Cleanup,
	animations: boolean, -- the map animations were started (or cannot start: no module, or Start failed)
	animationsAt: number, -- os.clock() of the next try while the map is not found yet
	wall: Model?,
	segments: { BasePart },
	wallRadius: number?, -- the radius last drawn
	readoutAt: number, -- os.clock() of the next readout refresh
	-- Power-ups v1.1: Diego's running map animations module and its map (both nil until Start ran), the readyAt last
	-- played per pad name, and the pad models found so far.
	animationsModule: any?,
	map: Instance?,
	padsShown: { [string]: number },
	padModels: { [string]: Instance },
	streamDeadline: number?, -- review fix: os.clock() after which Start no longer waits for the pads to stream in
	stung: boolean, -- music job: the result sting was handled (played or not needed)
}

-- Constants

local MATCH = Config.Match
local REMOTE_JOIN = "MatchJoin"
local REMOTE_LEAVE = "MatchLeave"
local COMMANDS_FOLDER = "SD_MatchCommands"
local COMMAND_NAMES: { [string]: string } =
	{ ["/ffa"] = "SD_MatchFfa", ["/tdm"] = "SD_MatchTdm", ["/leave"] = "SD_MatchLeave" }
local RESET_CALLBACK = "ResetButtonCallback"
local RESET_RETRY_SECONDS = 0.5 -- SetCore fails until the CoreGui registers the callback (as DuelController's)
local MAP_SCRIPTS = "DuelMapScripts"
local MAP_LIGHTING = "MapLighting"
local MAP_ANIMATIONS_PREFIX = "MapAnimations_"
local MAPS_FOLDER = "DuelMaps"
local ATTR_MAP_CODE = "MapCode"
local DUEL_GUI = "SD_DuelHud"
local READOUT_NAME = "Match_Readout"
local CLIENT_FX = "SD_ClientFx"
local WALL_NAME = "SD_StormWall"
-- The placeholder wall's drawing (not game numbers): segments in the ring, their thickness, the overlap that hides the
-- seams, and the smallest radius change that is redrawn.
local WALL_SEGMENTS = 48
local WALL_THICKNESS = 1
local WALL_OVERLAP = 1.05
local WALL_REDRAW_STUDS = 0.02
local ANIMATION_PHASES: { [string]: boolean } = { Countdown = true, Active = true }
local ANIMATION_RETRY_SECONDS = 1 -- review fix: how often a map that has not streamed in yet is looked for again
-- Power-ups v1.1 review fixes (client timing, not game numbers): the parts Diego's setupPad looks for in a pad (by name
-- ending), the longest wait for them to stream in before his Start, and his Collect's own animations (the pickup's pop
-- 0.08 + 0.1 + 0.14 s, the refill's pop 0.35 s), rounded up.
local PAD_PARTS = { "_Pickup", "_Ring", "_Fill" }
local PAD_STREAM_WAIT_SECONDS = 5
local DIEGO_POP_SECONDS = 0.4

-- `require` with a runtime-found ModuleScript (Diego's map scripts); the analyzer cannot resolve these paths.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local MatchController = {}

-- Private

local log = Log.new("Match")
local cleanup: Cleanup.Cleanup? = nil
local hooks: DuelHudHooks? = nil
local current: Look? = nil
local readout: Chip.Chip? = nil
local resetToken = 0
local warned: { [string]: boolean } = {}
local stats = { joins = 0, leaves = 0, looks = 0, lighting = 0, animations = 0, collects = 0 }
-- Power-ups v1.1 review fix: per map code, the os.clock() at which the last refill handed to Diego's Collect is over
-- (kept across matches: his stop() does not end it).
local refillEnds: { [string]: number } = {}

local function warnOnce(key: string, ...: any)
	if not warned[key] then
		warned[key] = true
		log:warn(...)
	end
end

-- Chat commands (D6) ------------------------------------------------------------------------------------------------

local function runCommand(text: unknown)
	local action, mode = MatchFormat.commandOf(text)
	if action == "join" and mode ~= nil then
		if NetController.fire(REMOTE_JOIN, mode) then -- Remotes: MatchJoin(mode: string)
			stats.joins += 1
		end
	elseif action == "leave" then
		if NetController.fire(REMOTE_LEAVE) then
			stats.leaves += 1
		end
	end
end

local function makeCommands(c: Cleanup.Cleanup)
	local okVersion, version = pcall(function(): any
		return TextChatService.ChatVersion
	end)
	if okVersion and version ~= Enum.ChatVersion.TextChatService then
		-- Legacy chat: the local player's own messages.
		local player = Players.LocalPlayer
		if player then
			c:add(player.Chatted:Connect(runCommand))
		end
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = COMMANDS_FOLDER
	for alias in MatchFormat.COMMANDS do
		local command = Instance.new("TextChatCommand")
		command.Name = COMMAND_NAMES[alias] or alias
		command.PrimaryAlias = alias
		command.SecondaryAlias = ""
		c:add(command.Triggered:Connect(function(_source: TextSource, text: string)
			runCommand(text)
		end))
		command.Parent = folder
	end
	folder.Parent = TextChatService
	c:add(folder)
end

-- Reset (D5) ----------------------------------------------------------------------------------------------------------

-- Sets the Reset button on or off, retrying until CoreGui accepts it; a newer call supersedes an older retry loop.
local function setReset(enabled: boolean)
	resetToken += 1
	local token = resetToken
	task.spawn(function()
		while token == resetToken do
			local ok = pcall(function()
				StarterGui:SetCore(RESET_CALLBACK, enabled)
			end)
			if ok then
				return
			end
			task.wait(RESET_RETRY_SECONDS)
		end
	end)
end

-- Diego's lighting and map animations (D10) ---------------------------------------------------------------------------

local function mapScript(name: string): any
	local folder = ReplicatedStorage:FindFirstChild(MAP_SCRIPTS)
	local module = if folder then folder:FindFirstChild(name) else nil
	if module == nil or not module:IsA("ModuleScript") then
		warnOnce("script:" .. name, `no {MAP_SCRIPTS}.{name}; skipped`)
		return nil
	end
	local ok, result = pcall(dynamicRequire, module)
	if not ok then
		warnOnce("require:" .. name, `{name} failed to load:`, result)
		return nil
	end
	return result
end

local function mapModel(code: string): Instance?
	local maps = Workspace:FindFirstChild(MAPS_FOLDER)
	if maps == nil then
		return nil
	end
	for _, child in maps:GetChildren() do
		if child:GetAttribute(ATTR_MAP_CODE) == code then
			return child
		end
	end
	return nil
end

local function startLighting(lc: Cleanup.Cleanup, code: string)
	if code == "" then
		return
	end
	local lighting = mapScript(MAP_LIGHTING)
	if lighting == nil or type(lighting.Apply) ~= "function" then
		return
	end
	local ok, err = pcall(lighting.Apply, code)
	if ok then
		stats.lighting += 1
	else
		log:warn(`MapLighting.Apply({code}) failed:`, err)
	end
	if type(lighting.Reset) == "function" then
		lc:add(function()
			local okReset, errReset = pcall(lighting.Reset)
			if not okReset then
				log:warn("MapLighting.Reset failed:", errReset)
			end
		end)
	end
end

-- Power-ups v1.1 review fix: whether `model` holds a BasePart whose name ends in `suffix` (as Diego's findChild).
local function hasPart(model: Instance, suffix: string): boolean
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, -#suffix) == suffix then
			return true
		end
	end
	return false
end

-- Power-ups v1.1 review fix: every pad of the view is on this client with the parts Diego's setupPad uses.
local function padsStreamed(map: Instance, view: StateController.MatchView): boolean
	for _, pad in view.pads do
		local model = map:FindFirstChild(pad.name, true)
		if model == nil then
			return false
		end
		for _, suffix in PAD_PARTS do
			if not hasPart(model, suffix) then
				return false
			end
		end
	end
	return true
end

-- Review fix: the flag is set only once Start ran, or when it cannot run at all (no code, no module, no Start, Start
-- failed); a map model that is not on this client yet (streaming) is looked for again later (stepLook). Power-ups
-- v1.1 review fixes: it also waits while a refill of an earlier match on this map still plays, and (at most
-- PAD_STREAM_WAIT_SECONDS) until the view's pads have streamed in (see the header).
local function startAnimations(state: Look, view: StateController.MatchView)
	local code = view.mapCode
	if code == "" then
		state.animations = true
		return
	end
	local animations = mapScript(MAP_ANIMATIONS_PREFIX .. code)
	if animations == nil or type(animations.Start) ~= "function" then
		state.animations = true
		return
	end
	local map = mapModel(code)
	if map == nil then
		warnOnce("map:" .. code, `no {MAPS_FOLDER} model with {ATTR_MAP_CODE} {code} yet; its animations wait for it`)
		return
	end
	local clock = os.clock()
	if clock < (refillEnds[code] or -math.huge) then
		return -- a refill handed to Collect in an earlier match on this map still plays
	end
	local deadline = state.streamDeadline
	if deadline == nil then
		deadline = clock + PAD_STREAM_WAIT_SECONDS
		state.streamDeadline = deadline
	end
	if not padsStreamed(map, view) then
		if clock < deadline then
			return
		end
		warnOnce("pads:" .. code, `{code}'s power-up pads have not all streamed in; its map animations start anyway`)
	end
	state.animations = true
	local ok, stop = pcall(animations.Start, map)
	if not ok then
		log:warn(`{MAP_ANIMATIONS_PREFIX}{code}.Start failed:`, stop)
		return
	end
	stats.animations += 1
	state.animationsModule = animations -- power-ups v1.1: the pads' Collect (syncPads)
	state.map = map
	if type(stop) == "function" then
		state.cleanup:add(function()
			local okStop, errStop = pcall(stop)
			if not okStop then
				log:warn(`{MAP_ANIMATIONS_PREFIX}{code} stop failed:`, errStop)
			end
		end)
	end
end

-- Power-ups v1.1 (SPEC P4): Diego's pad pop and refill timer for every pad whose readyAt rose since it was last played
-- (see the header). Nothing before the map animations run.
local function syncPads(state: Look, view: StateController.MatchView, now: number)
	local animations, map = state.animationsModule, state.map
	if animations == nil or map == nil or type(animations.Collect) ~= "function" then
		return
	end
	-- Review fix: one pickup sample of head start for his refill timer (see the header).
	local hz = (MATCH.Storm :: any).sampleHz
	local headStart = if type(hz) == "number" and hz > 0 then 1 / hz else 0
	for _, pad in view.pads do
		local seconds = MatchFormat.padCollectSeconds(pad.readyAt, state.padsShown[pad.name], now)
		local model = if seconds then state.padModels[pad.name] or map:FindFirstChild(pad.name, true) else nil
		if seconds and model then
			state.padModels[pad.name] = model
			state.padsShown[pad.name] = pad.readyAt
			local refill = MatchFormat.collectRefill(seconds, headStart, DIEGO_POP_SECONDS)
			if refill then
				local endsAt = os.clock() + refill + DIEGO_POP_SECONDS
				refillEnds[view.mapCode] = math.max(refillEnds[view.mapCode] or -math.huge, endsAt)
				local ok, err = pcall(animations.Collect, model, refill)
				if ok then
					stats.collects += 1
				else
					warnOnce(
						"collect:" .. pad.name,
						`{MAP_ANIMATIONS_PREFIX}{view.mapCode}.Collect({pad.name}) failed:`,
						err
					)
				end
			end
		end
	end
end

-- The storm wall (D11, a test placeholder) ----------------------------------------------------------------------------

local function wallSpec(): any
	local spec = (MATCH.Storm :: any).wall
	-- Review fix: a cached or partial Config (no heightStuds / transparency) means no wall, never an error.
	if type(spec) ~= "table" or type(spec.heightStuds) ~= "number" or type(spec.transparency) ~= "number" then
		warnOnce("wall", "Config.Match.Storm.wall is missing or incomplete; no storm wall")
		return nil
	end
	return spec
end

local function clientFx(): Instance
	local fx = Workspace:FindFirstChild(CLIENT_FX)
	if fx == nil then
		local made = Instance.new("Folder")
		made.Name = CLIENT_FX
		made.Parent = Workspace
		fx = made
	end
	return fx :: Instance
end

local function buildWall(state: Look, spec: any): Model
	local token = spec.color or spec.paletteKey -- an Art/Palette token name
	local colour = (Palette :: any)[token]
	if typeof(colour) ~= "Color3" then
		warnOnce("wallColour", `Palette has no {tostring(token)}; the storm wall is Sky`)
		colour = Palette.Sky
	end
	local model = Instance.new("Model")
	model.Name = WALL_NAME
	for index = 1, WALL_SEGMENTS do
		local part = Instance.new("Part")
		part.Name = "Segment" .. index
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.ForceField
		part.Color = colour
		part.Transparency = spec.transparency
		part.Size = Vector3.new(1, spec.heightStuds, WALL_THICKNESS)
		part.Parent = model
		table.insert(state.segments, part)
	end
	state.wall = model
	state.cleanup:add(model)
	return model
end

-- The ring at `radius` around `centre`, standing on floorY: each segment faces the centre, as wide as its share of the
-- circle (plus the overlap).
local function placeWall(segments: { BasePart }, centre: Vector3, floorY: number, radius: number, height: number)
	local count = #segments
	local width = math.max(2 * math.pi * radius / count * WALL_OVERLAP, WALL_THICKNESS)
	local y = floorY + height / 2
	local middle = Vector3.new(centre.X, y, centre.Z)
	local cframes: { CFrame } = table.create(count)
	for index, part in segments do
		local angle = (index - 0.5) / count * 2 * math.pi
		local at = Vector3.new(centre.X + math.cos(angle) * radius, y, centre.Z + math.sin(angle) * radius)
		part.Size = Vector3.new(width, height, WALL_THICKNESS)
		cframes[index] = CFrame.lookAt(at, middle)
	end
	Workspace:BulkMoveTo(segments, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

local function updateWall(state: Look, view: StateController.MatchView, now: number)
	local spec = if view.storm ~= nil then wallSpec() else nil
	local radius = if spec then MatchFormat.stormRadius(view, now, MATCH.Storm) else nil
	local centre = view.arena.centre
	if spec == nil or radius == nil or centre == nil then
		local wall = state.wall
		if wall and wall.Parent ~= nil then
			wall.Parent = nil
		end
		return
	end
	local wall = state.wall or buildWall(state, spec)
	if wall.Parent == nil then
		wall.Parent = clientFx()
	end
	local last = state.wallRadius
	if last == nil or math.abs(last - radius) > WALL_REDRAW_STUDS then
		state.wallRadius = radius
		placeWall(state.segments, centre, view.arena.floorY, radius, spec.heightStuds)
	end
end

-- The test readout (D13) ----------------------------------------------------------------------------------------------

local function ensureReadout(): Chip.Chip?
	local chip = readout
	if chip and chip.root.Parent ~= nil then
		return chip
	end
	local ok, made = pcall(function(): Chip.Chip
		local gui = UIController.screenGui(DUEL_GUI)
		local new = Chip.new({ name = READOUT_NAME, text = "", parent = gui })
		new.root.AnchorPoint = Vector2.new(0.5, 0)
		new.root.Position = UDim2.new(0.5, 0, 0, Theme.Padding.medium)
		new.root.Visible = false
		UIController.toastsBelow("match", new.root) -- the match.* toasts start under it while it shows
		return new
	end)
	if not ok then
		log:warn("match readout failed:", made)
		return nil
	end
	readout = made
	local c = cleanup
	if c then
		c:add(made)
	end
	return made
end

local function updateReadout(state: Look, view: StateController.MatchView, now: number)
	local chip = readout
	local clock = os.clock()
	if chip == nil or clock < state.readoutAt then
		return
	end
	local hz = (MATCH :: any).readoutHz
	state.readoutAt = clock + (if type(hz) == "number" and hz > 0 then 1 / hz else 0)
	chip:setText(MatchFormat.readout(view, now))
end

-- The match look (D13, D8) --------------------------------------------------------------------------------------------

local function hudOf(): (DuelHudHooks?, any)
	local hk = hooks
	return hk, if hk then hk.hud() else nil
end

local function showHud()
	local hk, h = hudOf()
	if hk == nil or h == nil then
		return
	end
	-- Review fix: a 1v1 result card still open from a duel just before closes first (its layout would show the top bar
	-- again when the HUD turns on), and the top bar hides through DuelController's own barHidden bookkeeping.
	hk.closeResult()
	h.gui.Enabled = true
	h.overlay.Enabled = true
	hk.hideBar(h, "match", true)
	h.forfeit.root.Visible = false
	h.arrow.Visible = false
	h.chip.root.Visible = false
	h.laneCue.Visible = false
	h.lane = nil
	hk.reset(h)
	hk.hideCountdown(h)
	hk.setCountdown(nil)
end

local function hideHud()
	local hk, h = hudOf()
	if hk == nil or h == nil then
		return
	end
	hk.hideCountdown(h)
	hk.setCountdown(nil)
	h.reticle.root.Visible = false
	h.hints.Visible = false
	hk.hideBar(h, "match", false)
	if StateController.duel() == nil then
		h.gui.Enabled = false
		h.overlay.Enabled = false
	end
end

-- Review fix: one optional piece of the look in its own pcall; an error warns once (per piece) and returns false.
local function guarded(key: string, piece: any, ...: any): boolean
	local ok, err = pcall(piece, ...)
	if not ok then
		warnOnce("piece:" .. key, `match {key} update failed:`, err)
	end
	return ok
end

-- One render frame of the look: the duel HUD's reticle, dock and countdown, the storm wall, the readout, the map
-- animations' start.
local function stepLook(state: Look): boolean
	local view = StateController.match()
	if current ~= state or view == nil then
		return false
	end
	local now = Workspace:GetServerTimeNow()
	local hk, h = hudOf()
	if hk and h then
		local ok, err = pcall(function(): any
			local aim = ThrowController.getAimState()
			hk.countdown(h, now)
			hk.ultReady(view)
			-- Match HUD M7: the key dock (bottom centre) hides while you are knocked out: the RESPAWNING bar is there.
			if view.you.alive or not Config.UI.Match.enabled.respawn then
				hk.hints(h, view, aim)
			else
				h.hints.Visible = false
			end
			hk.reticle(h, view, aim, now)
			return nil
		end)
		if not ok then
			warnOnce("look", "match look update failed:", err)
		end
	end
	-- Review fix: the test-only pieces each in their own pcall, so one that fails never ends this effect (the
	-- Scheduler drops an effect that errors) and the aiming HUD above keeps running.
	guarded("wall", updateWall, state, view, now)
	guarded("readout", updateReadout, state, view, now)
	-- Review fix: the map animations start once the phase reaches Countdown and the map is on this client; a map not
	-- streamed in yet is looked for again every ANIMATION_RETRY_SECONDS (power-ups v1.1: so are its pads, and an
	-- earlier match's refill on it, see startAnimations).
	local clock = os.clock()
	if not state.animations and ANIMATION_PHASES[view.phase] and clock >= state.animationsAt then
		state.animationsAt = clock + ANIMATION_RETRY_SECONDS
		if not guarded("animations", startAnimations, state, view) then
			state.animations = true -- never retried after an error
		elseif state.animationsModule ~= nil then
			guarded("pads", syncPads, state, view, now) -- power-ups v1.1: pads taken before the start
		end
	end
	return true
end

-- Music job (2026-10-16): the result sting, once per match (see the header).
local function playResultSting(state: Look, view: StateController.MatchView)
	if state.stung or view.outcome == nil then
		return
	end
	state.stung = true
	local result = MatchFormat.resultOf(view)
	local jingle = if result ~= nil then DuelFormat.resultStyle(result).jingle else nil
	if jingle == nil then
		return
	end
	local key: string = jingle
	local seconds = (Config.Audio :: any).matchStingDelaySeconds
	state.cleanup:add(task.delay(if type(seconds) == "number" and seconds > 0 then seconds else 0, function()
		SoundController.play(key)
	end))
end

local function endLook()
	local state = current
	current = nil
	if state then
		state.cleanup:clean()
	end
end

local function beginLook(view: StateController.MatchView)
	local lc = Cleanup.new()
	local state: Look = {
		matchId = view.matchId,
		cleanup = lc,
		animations = false,
		animationsAt = -math.huge,
		wall = nil,
		segments = {},
		wallRadius = nil,
		readoutAt = -math.huge,
		animationsModule = nil,
		map = nil,
		padsShown = {},
		padModels = {},
		streamDeadline = nil,
		stung = false,
	}
	current = state
	stats.looks += 1
	startLighting(lc, view.mapCode)
	setReset(false)
	lc:add(function()
		setReset(true)
	end)
	showHud()
	lc:add(hideHud)
	local chip = ensureReadout()
	if chip then
		chip.root.Visible = true
		chip:setText("")
		lc:add(function()
			chip.root.Visible = false
		end)
	end
	lc:add(Scheduler.add(function(): boolean
		return stepLook(state)
	end, "render"))
end

local function onMatchChanged(view: StateController.MatchView?, old: StateController.MatchView?)
	if view == nil then
		endLook()
		return
	end
	local state = current
	if state == nil or state.matchId ~= view.matchId then
		endLook()
		beginLook(view)
		state = current
	end
	if state ~= nil then
		guarded("pads", syncPads, state, view, Workspace:GetServerTimeNow()) -- power-ups v1.1 (SPEC P4)
		guarded("sting", playResultSting, state, view) -- music job (2026-10-16)
	end
	local phaseChanged = old == nil or old.matchId ~= view.matchId or old.phase ~= view.phase
	if not phaseChanged or state == nil then
		return
	end
	local hk = hooks
	if view.phase == "Countdown" and hk then
		hk.setCountdown(view.phaseEndsAt)
	end
	-- The map animations start from stepLook (review fix: retried while the map has not streamed in yet).
end

-- Public --------------------------------------------------------------------------------------------------------------

-- DuelController hands over its HUD pieces (once, from its init). Returns the detach function (its cleanup).
function MatchController.attachDuelHud(duelHooks: DuelHudHooks): () -> ()
	hooks = duelHooks
	return function()
		if hooks == duelHooks then
			hooks = nil
		end
	end
end

-- Studio / debug counters.
function MatchController.counts(): { [string]: any }
	local state = current
	return {
		inMatch = state ~= nil,
		matchId = if state then state.matchId else nil,
		hooked = hooks ~= nil,
		wall = state ~= nil and state.wall ~= nil and state.wall.Parent ~= nil,
		wallRadius = if state then state.wallRadius else nil,
		joins = stats.joins,
		leaves = stats.leaves,
		looks = stats.looks,
		lighting = stats.lighting,
		animations = stats.animations,
		collects = stats.collects, -- power-ups v1.1
	}
end

-- Lifecycle

function MatchController.init()
	local c = Cleanup.new()
	cleanup = c
	makeCommands(c)
	c:add(StateController.MatchChanged:connect(onMatchChanged))
	c:add(function()
		endLook()
		readout = nil
	end)
end

function MatchController.start()
	-- A match already running when this client starts (a late start) still gets its look.
	local view = StateController.match()
	if view then
		onMatchChanged(view, nil)
	end
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function MatchController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return MatchController
