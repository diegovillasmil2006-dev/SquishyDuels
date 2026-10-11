--!strict
-- SoundPicker (client only, Studio only). DESIGN §18.7 (the Studio sound picker), §18.10 L6.
-- The panel the user listens to candidate sounds in, during Studio Play. SoundPickerModel holds the state; this module
-- draws it, plays the sounds and answers tools/mcp/sound-picker.mjs.
-- * Gate: RunService:IsStudio() AND Config.Debug.soundPicker (always false outside Studio); init() and every command
--   check both. init() only creates the BindableFunction PlayerScripts.SD_SoundPicker (the SD_DebugClient pattern):
--   no UI exists until "load", so normal play tests and the teammate never see it. No remotes, no server code, no
--   DataStore; nothing made in Play persists (§1.2 #6).
-- * Commands (every reply is a table { ok, ... }):
--     SD_SoundPicker:Invoke("load", data)   data in candidates.json's shape (§18.7), up to 10 keys a call. Another
--                                            builtAt (a new round) or `reset = true` starts a new key list, else the
--                                            keys are added. Decisions: the injected ones, but this session's own win
--                                            (same builtAt), in every chunk of the round (the pure mergeLoad).
--                                            The panel opens at the first unfinished key and plays nothing yet.
--                                            -> { ok, problems, done, total, key }
--     SD_SoundPicker:Invoke("export")        -> { ok, done, total, export = SoundPickerModel.jsonExport(...) }
--     SD_SoundPicker:Invoke("state")         -> { ok, loaded, open, hidden, done, total, key, index, count, auditions,
--                                               voices, ... }
--     SD_SoundPicker:Invoke("close")         closes the panel: clearAuditions(), then the current zone is re-applied;
--                                            the decisions stay for "export"
-- * The panel: ScreenGui SD_SoundPicker (DisplayOrder 35, ResetOnSpawn false; outside Config.UI.ScreenGuis like the
--   other Studio overlays), on the right, PANEL_WIDTH px wide; buttons at least BUTTON_HEIGHT px tall with large text;
--   mouse only (not selectable, no keyboard shortcuts, so it never clashes with E, Space or clicks in the game). Its
--   own buttons are silent (Button.decorate with sound = false); only the sample Button of the Buttons section has its
--   sound on, because that sample is the "Try it" of ui.click, ui.hover and ui.error.
-- * Every sound goes through SoundController: the candidate under the cursor is auditioned for its key
--   (SoundController.audition), so "Play again" and every "Try it in the game" runner use the real groups, caps and
--   pitch rules. Reading: an approved key keeps its first pick auditioned until the picker closes or finishes, so the
--   storyboards and the game sound like the final list as it grows; a skipped or "None of these fit" key is silent.
-- * After an approval: a gentle glow (25% opacity at most, one fade, no flash), then the next key after
--   ADVANCE_SECONDS. Reading: the next key's (or the next variant's) first sound then plays at once, like "Next sound".
-- * Timed beats (the advance, storyboards, the Settings close, the loop clock) are Scheduler effects (§18.1 #2).
-- * Every decision prints "[SD][SoundPicker] decision {json}" (the backup get_console_output can recover).
-- Its labels are Studio-only developer text, not player-facing, so they stay here (§18.7 reading of §0.3 #6).

-- Services

local HttpService = game:GetService("HttpService")
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
local Theme = require(Client.UI.Theme)
local Button = require(Client.UI.Components.Button)
local HeldSquishyController = require(Client.Controllers.HeldSquishyController)
local PracticeController = require(Client.Controllers.PracticeController)
local SoundController = require(Client.Controllers.SoundController)
local SqueezeController = require(Client.Controllers.SqueezeController)
local UIController = require(Client.Controllers.UIController)
local WorldBinder = require(Client.Controllers.WorldBinder)
local AutoDriver = require(script.Parent.AutoDriver)
local SoundPickerModel = require(script.Parent.SoundPickerModel)

-- Types

type Model = SoundPickerModel.Model
type Reply = { [string]: any }

-- The data merged from every "load" of this round (the chunks of 10 keys). `sessionKeys` / `session`: this Play
-- session's own decisions (an undone key has none) when the round began, which win over the files for every chunk.
type Loaded = {
	builtAt: string,
	keys: { any },
	index: { [string]: number },
	decisions: { [string]: any },
	sessionKeys: { string },
	session: { [string]: any },
}

type Storyboard = {
	handle: Scheduler.Handle?,
	releases: { () -> () },
}

type Panel = {
	cleanup: Cleanup.Cleanup,
	gui: ScreenGui,
	frame: Frame,
	tab: TextButton,
	glow: Frame,
	glowTween: Tween?,
	progress: TextLabel,
	fill: Frame,
	section: TextLabel,
	title: TextLabel,
	when: TextLabel,
	soundLine: TextLabel,
	candidate: TextLabel,
	hint: TextLabel,
	status: TextLabel,
	volume: TextLabel,
	variantLine: TextLabel,
	problems: TextLabel,
	rows: { [string]: Frame },
	buttons: { [string]: TextButton },
	sample: Button.Button,
	reasonsOpen: boolean,
	hidden: boolean,
}

-- A sample toast for the toast runner (a real Strings code, so it is exactly what a player sees).
type ToastSample = { code: string, args: { [string]: any }?, kind: UIController.ToastKind }

-- Constants

local FUNCTION_NAME = "SD_SoundPicker"
local GUI_NAME = "SD_SoundPicker"
local DISPLAY_ORDER = 35
local PANEL_WIDTH = 440
local MARGIN = 16
local GAP = 8
local SCROLL_BAR = 6
local BUTTON_HEIGHT = 64
local BIG_BUTTON_HEIGHT = 84
local BAR_HEIGHT = 14
local TAB_WIDTH = 260
local GLOW_TRANSPARENCY = 0.75 -- the approval glow at its brightest: 25% opacity (§9.12: overlays <= 30%)
local GLOW_MS = 600
local GLOW_Z = 5
local ADVANCE_SECONDS = 0.6 -- the next key after an approval (§18.7)
local AHEAD_STUDS = 12 -- "Anywhere else it plays 3D 12 studs in front of the camera"
local SETTINGS_SCREEN = "settings"
local SETTINGS_CLOSE_SECONDS = 1.2 -- reading: the open / back runners close Settings again after this
local SILENT_CLOSE = "picker" -- a close reason that plays no ui.back
local BACK_CLOSE = "button" -- a close reason that plays ui.back (UIController's BACK_REASONS)
local BACK_KEY = "ui.back"
local ERROR_KEY = "ui.error"
local POP_PRIORITY = 1 -- ThrowController's pop-in plays sfx.pop with priority 1
local HALF = 0.5
local THIRD = 1 / 3
local WHOLE = 1
local TOAST_SAMPLES: { [string]: ToastSample } = {
	["ui.gripUnlock"] = { code = "grip.levelUp", args = { level = 2 }, kind = "success" },
	["ui.toast"] = { code = "queue.opponentFound", kind = "info" },
}
local REASON_LAYOUT = { { 1, 2 }, { 3, 4 } } -- the four reason chips in two rows

-- Module table

local SoundPicker = {}

-- Private

local log = Log.new("SoundPicker")
local cleanup: Cleanup.Cleanup? = nil -- the BindableFunction
local model: Model? = nil
local problems: { string } = {}
local loaded: Loaded? = nil
local panel: Panel? = nil
local auditioned: { [string]: { id: number, volume: number } } = {}
local loopKey: string? = nil
local loopClock: Scheduler.Handle? = nil
local storyboard: Storyboard? = nil
local beat: Scheduler.Handle? = nil
local settingsBeat: Scheduler.Handle? = nil
local busy = false -- the approval glow is running; every button but Hide waits for it

local function enabled(): boolean
	return RunService:IsStudio() and Config.Debug.soundPicker == true
end

local function safely(name: string, fn: () -> ())
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		log:warn(`{name} failed:`, err)
	end
end

local function setStatus(text: string)
	local p = panel
	if p then
		p.status.Text = text
		p.status.Visible = text ~= ""
	end
end

-- Auditions ---------------------------------------------------------------------------------------------------------------

-- Auditions `id` for `key` (nil drops it), only when it changes: re-auditioning a playing music or ambience key
-- restarts its crossfade.
local function setAudition(key: string, id: number?, volume: number?)
	local current = auditioned[key]
	if id == nil then
		if current ~= nil then
			auditioned[key] = nil
			SoundController.audition(key, nil)
		end
		return
	end
	local level = volume or 1
	if current and current.id == id and current.volume == level then
		return
	end
	if SoundController.audition(key, id, level) then
		auditioned[key] = { id = id, volume = level }
	end
end

local function clearAuditions()
	table.clear(auditioned)
	SoundController.clearAuditions()
end

-- Approved keys keep their first pick; every other key but the current one is silent.
local function syncAuditions(m: Model)
	local current = m:currentKey()
	for _, key in m:export().keys do
		local decision = m:decision(key)
		local picks = if decision and decision.status == "approved" then decision.picks else nil
		local first = picks and picks[1]
		if first then
			setAudition(key, first.id, first.volume)
		elseif key ~= current then
			setAudition(key, nil)
		end
	end
end

-- The candidate under the cursor, at its volume.
local function auditionCurrent(m: Model)
	local view = m:view()
	local candidate = view.candidate
	if view.key and candidate then
		setAudition(view.key, candidate.id, view.volume)
	end
end

local function reapplyZone()
	SoundController.applyZone(WorldBinder.currentZone())
end

-- Runners -------------------------------------------------------------------------------------------------------------------

local function aheadPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end
	local frame = camera.CFrame
	return frame.Position + frame.LookVector * AHEAD_STUDS
end

-- 3D 12 studs in front of the camera (a 2D slot ignores the position).
local function playAhead(key: string)
	local at = aheadPoint()
	SoundController.play(key, if at then { at = at } else nil)
end

local function stopLoopClock()
	local handle = loopClock
	loopClock = nil
	if handle then
		handle:disconnect()
	end
end

-- Leaves a music or ambience key the picker started: the zone's own loops again.
local function leaveLoop()
	stopLoopClock()
	if loopKey ~= nil then
		loopKey = nil
		reapplyZone()
	end
end

-- Music and ambience: setMusic / setAmbience through the audition, with a clock in the status line.
local function startLoop(key: string, group: string)
	if group == "Music" then
		SoundController.setMusic(key)
	else
		SoundController.setAmbience(key)
	end
	loopKey = key
	stopLoopClock()
	local role = SoundPickerModel.loopRole(key) or key
	local started = os.clock()
	local shown = -1
	local handle: Scheduler.Handle? = nil
	handle = Scheduler.add(function(_dt: number): boolean
		if loopKey ~= key then
			if loopClock == handle then
				loopClock = nil
			end
			return false
		end
		local whole = math.floor(os.clock() - started)
		if whole ~= shown then
			shown = whole
			setStatus(`Playing as {role}: walk around · {SoundPickerModel.clockText(whole)}`)
		end
		return true
	end, "render")
	loopClock = handle
end

local function stopStoryboard()
	local board = storyboard
	if board == nil then
		return
	end
	storyboard = nil
	if board.handle then
		board.handle:disconnect()
		board.handle = nil
	end
	for _, release in board.releases do
		release()
	end
	table.clear(board.releases)
end

-- A sound-only storyboard with the real timings (SoundPickerModel.storyboard): plays, ducks and their releases.
local function runStoryboard(cues: { SoundPickerModel.Cue })
	stopStoryboard()
	local board: Storyboard = { handle = nil, releases = {} }
	local index = 1
	local elapsed = 0
	board.handle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		while index <= #cues and cues[index].at <= elapsed do
			local cue = cues[index]
			index += 1
			if cue.kind == "play" and cue.key then
				SoundController.play(cue.key, { pitch = cue.pitch })
			elseif cue.kind == "duck" and cue.reason then
				table.insert(board.releases, SoundController.duck(cue.reason))
			elseif cue.kind == "unduck" then
				local release = table.remove(board.releases, 1)
				if release then
					release()
				end
			end
		end
		if index <= #cues then
			return true
		end
		if storyboard == board then
			storyboard = nil
		end
		board.handle = nil
		for _, release in board.releases do
			release()
		end
		table.clear(board.releases)
		return false
	end, "render")
	storyboard = board
end

local function stopSettingsBeat()
	local handle = settingsBeat
	settingsBeat = nil
	if handle then
		handle:disconnect()
	end
end

-- ui.open / ui.back: the Settings screen opens (ui.open), then closes after SETTINGS_CLOSE_SECONDS, like the Back
-- button for ui.back (ui.back), quietly for ui.open.
local function runSettings(key: string)
	stopSettingsBeat()
	if UIController.isOpen(SETTINGS_SCREEN) then
		UIController.close(SETTINGS_SCREEN, SILENT_CLOSE)
	end
	if not UIController.open(SETTINGS_SCREEN) then
		setStatus("Settings can't open right now (in a duel?)")
		return
	end
	local reason = if key == BACK_KEY then BACK_CLOSE else SILENT_CLOSE
	local elapsed = 0
	local handle: Scheduler.Handle? = nil
	handle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		if elapsed < SETTINGS_CLOSE_SECONDS then
			return true
		end
		if settingsBeat == handle then
			settingsBeat = nil
		end
		UIController.close(SETTINGS_SCREEN, reason)
		return false
	end, "render")
	settingsBeat = handle
	setStatus(if key == BACK_KEY then "Settings opens, then closes like the Back button" else "Settings opens")
end

local function runSqueeze(key: string)
	local ok, reason = SqueezeController.playLocal()
	if ok then
		setStatus("Your squishy squeezes (the feel only, nothing is sent)")
		return
	end
	setStatus(`No squeeze ({reason or "unknown"}): played it in front of you instead`)
	playAhead(key)
end

-- Reading: ThrowController's pop-in has no public trigger; this is the call it makes (3D at the own held squishy,
-- priority 1), so the sound is heard exactly as when a throw is ready again.
local function runPop(key: string)
	local player = Players.LocalPlayer
	local held = HeldSquishyController.getModel(player)
	local at: BasePart? = if held then held.PrimaryPart else nil
	if at == nil then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		at = if root and root:IsA("BasePart") then root else nil
	end
	if at == nil then
		playAhead(key)
		return
	end
	SoundController.play(key, { at = at, priority = POP_PRIORITY })
	setStatus("Played at your hand, like a throw that is ready again")
end

local function runToast(key: string)
	local sample = TOAST_SAMPLES[key]
	if sample == nil then
		SoundController.play(key)
		return
	end
	UIController.notify(sample.code, sample.args, sample.kind, { sound = key })
	setStatus("A sample message pops up at the top")
end

-- Practice range: a real throw (AutoDriver: ThrowStarted / ThrowImpact); anywhere else 12 studs ahead.
local function runThrow(key: string, aim: string)
	if not PracticeController.isInZone() then
		setStatus("Walk to the Practice Range for the real thing (played in front of you)")
		playAhead(key)
		return
	end
	local reply = AutoDriver.fireOnce(aim)
	if reply.ok then
		setStatus(if aim == "backstop" then "Threw at the back wall" else "Threw at a practice target")
		return
	end
	setStatus(`No throw ({tostring(reply.reason or reply.error)}): played it in front of you instead`)
	playAhead(key)
end

-- Panel flow ----------------------------------------------------------------------------------------------------------------

local render: () -> ()

-- Only the progress line, its bar and the tab (the rest keeps showing the key just picked during the glow).
local function renderProgress()
	local p = panel
	local m = model
	if p == nil or m == nil then
		return
	end
	local done, total = m:progress()
	p.tab.Text = SoundPickerModel.tabText(done, total)
	p.progress.Text = SoundPickerModel.progressText(done, total)
	p.fill.Size = UDim2.fromScale(if total > 0 then done / total else 0, 1)
end

-- "Play again": the candidate itself (2D), or as the loop it is for music and ambience.
local function playCurrent(m: Model)
	local view = m:view()
	local key = view.key
	if key == nil or view.candidate == nil then
		return
	end
	stopStoryboard()
	auditionCurrent(m)
	local entry = m:entry(key)
	if view.runner == "loop" and entry then
		startLoop(key, entry.group)
		return
	end
	SoundController.play(key)
end

-- "Try it in the game" (§18.7): every runner goes through the audition.
local function tryCurrent(m: Model)
	local view = m:view()
	local key = view.key
	local candidate = view.candidate
	if key == nil or candidate == nil then
		return
	end
	stopStoryboard()
	auditionCurrent(m)
	local runner = view.runner
	if runner == "squeeze" then
		runSqueeze(key)
	elseif runner == "pop" then
		runPop(key)
	elseif runner == "toast" then
		runToast(key)
	elseif runner == "button" then
		setStatus(
			if key == ERROR_KEY then "Press the grey sample button below" else "Hover and click the sample button below"
		)
	elseif runner == "screen" then
		runSettings(key)
	elseif runner == "target" or runner == "backstop" then
		runThrow(key, runner)
	elseif runner == "ahead" then
		setStatus("Played in front of you")
		playAhead(key)
	elseif runner == "storyboard" then
		local cues = SoundPickerModel.storyboard(key, candidate.seconds)
		if cues then
			setStatus("Plays with the real timing")
			runStoryboard(cues)
		end
	elseif runner == "loop" then
		local entry = m:entry(key)
		if entry then
			startLoop(key, entry.group)
		end
	else
		setStatus("No scene for this one yet: it plays as it will in the game")
		SoundController.play(key)
	end
end

local function logDecision(m: Model, key: string)
	local ok, json = pcall(function(): string
		return HttpService:JSONEncode(SoundPickerModel.jsonDecision(key, m:decision(key)))
	end)
	if ok then
		log:info("decision", json)
	else
		log:warn("decision of", key, "could not be encoded:", json)
	end
end

local function stopBeat()
	local handle = beat
	beat = nil
	busy = false
	if handle then
		handle:disconnect()
	end
end

-- Everything that runs for one key stops; at the end, clearAuditions() and the zone again.
local function finish()
	stopStoryboard()
	leaveLoop()
	clearAuditions()
	reapplyZone()
end

-- Shows the key the model is on now. `autoplay`: its first sound plays at once.
local function advance(m: Model, autoplay: boolean)
	stopStoryboard()
	local view = m:view()
	if view.key ~= loopKey then
		leaveLoop()
	end
	setStatus("")
	if view.finished then
		finish()
		render()
		return
	end
	syncAuditions(m)
	render()
	if autoplay then
		playCurrent(m)
	end
end

local function glow()
	local p = panel
	if p == nil then
		return
	end
	Tweens.cancel(p.glowTween)
	p.glow.Visible = true
	p.glow.BackgroundTransparency = GLOW_TRANSPARENCY
	p.glowTween = Tweens.fade(p.glow, { BackgroundTransparency = 1 }, GLOW_MS)
end

-- After a decision: the Output line, then (after the glow, for a pick) the next key.
local function decided(m: Model, key: string, withGlow: boolean)
	logDecision(m, key)
	local p = panel
	if p then
		p.reasonsOpen = false
	end
	if not withGlow then
		advance(m, true)
		return
	end
	stopBeat()
	busy = true
	glow()
	setStatus("Picked!")
	renderProgress()
	local elapsed = 0
	local handle: Scheduler.Handle? = nil
	handle = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		if elapsed < ADVANCE_SECONDS then
			return true
		end
		if beat == handle then
			beat = nil
			busy = false
			local shown = panel
			if shown then
				shown.glow.Visible = false
			end
			local current = model
			if current then
				advance(current, true)
			end
		end
		return false
	end, "render")
	beat = handle
end

-- A button action on the current model; ignored while the approval glow runs.
local function act(name: string, fn: (m: Model) -> ())
	safely(name, function()
		local m = model
		if m == nil or busy then
			return
		end
		fn(m)
	end)
end

local function likeIt(m: Model)
	local view = m:view()
	local key = view.key
	local candidate = view.candidate
	if key == nil or candidate == nil then
		return
	end
	local ok: boolean, reason: string?
	if view.picking then
		ok, reason = m:addVariant(key, candidate.id, view.volume)
	else
		ok, reason = m:approve(key, candidate.id, view.volume)
	end
	if not ok then
		setStatus(`Not picked: {reason or "unknown"}`)
		return
	end
	decided(m, key, true)
end

local function noneFit(reason: string)
	act("needsMore", function(m: Model)
		local key = m:currentKey()
		if key == nil then
			return
		end
		local ok, why = m:needsMore(key, reason)
		if not ok then
			setStatus(`Not saved: {why or "unknown"}`)
			return
		end
		decided(m, key, false)
	end)
end

local function skip(m: Model)
	local key = m:currentKey()
	if key == nil then
		return
	end
	local ok, why = m:skip(key)
	if not ok then
		setStatus(`Not skipped: {why or "unknown"}`)
		return
	end
	decided(m, key, false)
end

local function enough(m: Model)
	local key = m:currentKey()
	if key and m:enough(key) then
		advance(m, true)
	end
end

local function undo(m: Model)
	local key = m:undo()
	if key == nil then
		return
	end
	logDecision(m, key)
	local p = panel
	if p then
		p.reasonsOpen = false
	end
	advance(m, false)
end

local function step(m: Model, delta: number)
	if delta > 0 then
		m:nextCandidate()
	else
		m:prevCandidate()
	end
	setStatus("")
	render()
	playCurrent(m)
end

local function changeVolume(m: Model, steps: number)
	m:volumeStep(steps)
	render()
	playCurrent(m)
end

local function setHidden(hidden: boolean)
	local p = panel
	if p == nil then
		return
	end
	p.hidden = hidden
	p.frame.Visible = not hidden
	p.tab.Visible = hidden
	if hidden then
		p.glow.Visible = false
	end
end

-- Closes the panel; the model stays for "export", and a later "load" opens it again.
local function closePanel()
	stopBeat()
	stopSettingsBeat()
	finish()
	local p = panel
	panel = nil
	if p then
		Tweens.cancel(p.glowTween)
		p.cleanup:clean()
	end
end

-- Panel building ------------------------------------------------------------------------------------------------------------

local function row(parent: Instance, name: string, order: number, height: number): Frame
	local frame: Frame = Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -(SCROLL_BAR + GAP), 0, height),
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.list(Enum.FillDirection.Horizontal, GAP, frame, Enum.HorizontalAlignment.Left)
	return frame
end

local function label(parent: Instance, name: string, order: number, kind: Theme.TextKind): TextLabel
	return Theme.label({
		Name = name,
		Text = "",
		LayoutOrder = order,
		Size = UDim2.new(1, -(SCROLL_BAR + GAP), 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, kind)
end

-- A silent picker button `share` of its row wide (1/2, 1/3 or the whole row).
local function button(
	c: Cleanup.Cleanup,
	parent: Instance,
	name: string,
	text: string,
	share: number,
	order: number,
	onClick: () -> (),
	fill: Color3?,
	kind: Theme.TextKind?,
	height: number?
): TextButton
	local root: TextButton = Create("TextButton", {
		Name = name,
		Text = text,
		AutoButtonColor = false,
		Selectable = false,
		BackgroundColor3 = fill or Theme.Colors.cream,
		BorderSizePixel = 0,
		Size = UDim2.new(share, -GAP * (1 - share), 0, height or BUTTON_HEIGHT),
		LayoutOrder = order,
	})
	Theme.text(root, kind or "H2")
	Theme.corner(Theme.Radius.medium, root)
	Theme.stroke(Theme.Colors.panelStroke, Theme.Stroke.medium, root)
	c:add(Button.decorate(root, { sound = false }))
	c:add(root.Activated:Connect(function()
		safely(name, onClick)
	end))
	root.Parent = parent
	return root
end

local function buildPanel(): Panel?
	local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		log:warn("PlayerGui not found; the panel was not created")
		return nil
	end
	local old = playerGui:FindFirstChild(GUI_NAME)
	if old then
		old:Destroy()
	end
	local c = Cleanup.new()
	local gui: ScreenGui = Create("ScreenGui", {
		Name = GUI_NAME,
		DisplayOrder = DISPLAY_ORDER,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	c:add(gui)

	local frame = Theme.panel({
		Name = "Panel",
		Active = true, -- clicks on the panel never reach the game
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -MARGIN, 0, MARGIN),
		Size = UDim2.new(0, PANEL_WIDTH, 1, -2 * MARGIN),
		Parent = gui,
	}, Theme.Radius.large, Theme.Padding.medium)
	-- The approval glow covers the whole panel (a sibling drawn above it; never Active, so it takes no clicks).
	local glowFrame: Frame = Create("Frame", {
		Name = "Glow",
		Active = false,
		BackgroundColor3 = Theme.Colors.mint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AnchorPoint = frame.AnchorPoint,
		Position = frame.Position,
		Size = frame.Size,
		ZIndex = GLOW_Z,
		Visible = false,
		Parent = gui,
	})
	Theme.corner(Theme.Radius.large, glowFrame)
	local scroll: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Scroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = SCROLL_BAR,
		ScrollBarImageColor3 = Theme.Colors.ink,
		Parent = frame,
	})
	Theme.list(Enum.FillDirection.Vertical, GAP, scroll, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Top)

	local p = {} :: Panel
	p.cleanup = c
	p.gui = gui
	p.frame = frame
	p.glow = glowFrame
	p.glowTween = nil
	p.rows = {}
	p.buttons = {}
	p.reasonsOpen = false
	p.hidden = false

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Top: progress, its bar and the section.
	p.progress = label(scroll, "Progress", nextOrder(), "H2")
	local track: Frame = Create("Frame", {
		Name = "Bar",
		BackgroundColor3 = Theme.Colors.cream,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -(SCROLL_BAR + GAP), 0, BAR_HEIGHT),
		LayoutOrder = nextOrder(),
		Parent = scroll,
	})
	Theme.corner(BAR_HEIGHT // 2, track)
	p.fill = Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Theme.Colors.mint,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	})
	Theme.corner(BAR_HEIGHT // 2, p.fill)
	p.section = label(scroll, "Section", nextOrder(), "Body")

	-- The key and its candidate.
	p.title = label(scroll, "Key", nextOrder(), "Title")
	p.when = label(scroll, "When", nextOrder(), "Body")
	p.soundLine = label(scroll, "SoundLine", nextOrder(), "H2")
	p.candidate = label(scroll, "Candidate", nextOrder(), "Small")
	p.hint = label(scroll, "Hint", nextOrder(), "Small")
	p.status = label(scroll, "Status", nextOrder(), "Body")
	p.status.Visible = false

	-- Listening.
	local listen = row(scroll, "Listen", nextOrder(), BUTTON_HEIGHT)
	p.rows.listen = listen
	p.buttons.play = button(c, listen, "PlayAgain", "Play again", HALF, 1, function()
		act("play", playCurrent)
	end)
	p.buttons.try = button(c, listen, "TryIt", "Try it in the game", HALF, 2, function()
		act("try", tryCurrent)
	end)

	local volumeRow = row(scroll, "Volume", nextOrder(), BUTTON_HEIGHT)
	p.rows.volume = volumeRow
	p.buttons.quieter = button(c, volumeRow, "Quieter", "Quieter", THIRD, 1, function()
		act("quieter", function(m: Model)
			changeVolume(m, -1)
		end)
	end)
	p.volume = Theme.label({
		Name = "Level",
		Text = "",
		LayoutOrder = 2,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(THIRD, -GAP * (1 - THIRD), 0, BUTTON_HEIGHT),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = volumeRow,
	}, "H2")
	p.buttons.louder = button(c, volumeRow, "Louder", "Louder", THIRD, 3, function()
		act("louder", function(m: Model)
			changeVolume(m, 1)
		end)
	end)

	local browse = row(scroll, "Browse", nextOrder(), BUTTON_HEIGHT)
	p.rows.browse = browse
	p.buttons.back = button(c, browse, "Back", "Back", HALF, 1, function()
		act("back", function(m: Model)
			step(m, -1)
		end)
	end)
	p.buttons.next = button(c, browse, "NextSound", "Next sound", HALF, 2, function()
		act("next", function(m: Model)
			step(m, 1)
		end)
	end)

	-- Variants.
	p.variantLine = label(scroll, "Variants", nextOrder(), "H2")
	local variants = row(scroll, "VariantButtons", nextOrder(), BUTTON_HEIGHT)
	p.rows.variants = variants
	p.buttons.another = button(c, variants, "PickAnother", "Pick another", HALF, 1, function()
		act("pickAnother", playCurrent)
	end)
	p.buttons.enough = button(c, variants, "Enough", "That's enough", HALF, 2, function()
		act("enough", enough)
	end)

	-- Deciding.
	local likeRow = row(scroll, "Like", nextOrder(), BIG_BUTTON_HEIGHT)
	p.rows.like = likeRow
	p.buttons.like = button(c, likeRow, "LikeIt", "I like this one", WHOLE, 1, function()
		act("like", likeIt)
	end, Theme.Colors.mint, "Title", BIG_BUTTON_HEIGHT)

	local decide = row(scroll, "Decide", nextOrder(), BUTTON_HEIGHT)
	p.rows.decide = decide
	p.buttons.none = button(c, decide, "NoneFit", "None of these fit", HALF, 1, function()
		act("noneFit", function(_m: Model)
			local current = panel
			if current then
				current.reasonsOpen = not current.reasonsOpen
				render()
			end
		end)
	end)
	p.buttons.skip = button(c, decide, "Skip", "Skip", HALF, 2, function()
		act("skip", skip)
	end)

	for i, pair in REASON_LAYOUT do
		local chips = row(scroll, "Reasons" .. i, nextOrder(), BUTTON_HEIGHT)
		p.rows["reasons" .. i] = chips
		for slot, index in pair do
			local reason = SoundPickerModel.REASONS[index]
			button(c, chips, "Reason_" .. reason.code, reason.text, HALF, slot, function()
				noneFit(reason.code)
			end, Theme.Colors.lemon, "Button")
		end
	end

	-- The Buttons section's "Try it": a real Button with its sound on.
	local sampleRow = row(scroll, "Sample", nextOrder(), BUTTON_HEIGHT)
	p.rows.sample = sampleRow
	p.sample = Button.new({
		name = "SoundPicker_SampleButton",
		text = "Sample button",
		width = PANEL_WIDTH - 2 * Theme.Padding.medium - SCROLL_BAR - GAP,
		height = BUTTON_HEIGHT,
		onActivated = function() end,
		layoutOrder = 1,
		parent = sampleRow,
	})
	p.sample.root.Selectable = false
	c:add(p.sample)

	local tools = row(scroll, "Tools", nextOrder(), BUTTON_HEIGHT)
	p.rows.tools = tools
	p.buttons.undo = button(c, tools, "Undo", "Undo", HALF, 1, function()
		act("undo", undo)
	end)
	p.buttons.hide = button(c, tools, "Hide", "Hide", HALF, 2, function()
		setHidden(true)
	end)

	local finishRow = row(scroll, "Finish", nextOrder(), BUTTON_HEIGHT)
	p.rows.finish = finishRow
	p.buttons.close = button(c, finishRow, "Close", "Close the picker", WHOLE, 1, function()
		closePanel()
	end)

	p.problems = label(scroll, "Problems", nextOrder(), "Small")

	-- The hidden panel's tab.
	p.tab = Create("TextButton", {
		Name = "Tab",
		Text = "",
		AutoButtonColor = false,
		Selectable = false,
		Visible = false,
		BackgroundColor3 = Theme.Colors.cream,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -MARGIN, 0.5, 0),
		Size = UDim2.fromOffset(TAB_WIDTH, BUTTON_HEIGHT),
		Parent = gui,
	})
	Theme.text(p.tab, "H2")
	Theme.corner(Theme.Radius.medium, p.tab)
	Theme.stroke(Theme.Colors.panelStroke, Theme.Stroke.medium, p.tab)
	c:add(Button.decorate(p.tab, { sound = false }))
	c:add(p.tab.Activated:Connect(function()
		setHidden(false)
	end))

	gui.Parent = playerGui
	return p
end

render = function()
	local p = panel
	local m = model
	if p == nil or m == nil then
		return
	end
	local view = m:view()
	local hasKey = view.key ~= nil
	local candidate = view.candidate
	local deciding = hasKey and not view.picking and not busy

	renderProgress()
	p.section.Text = if hasKey then SoundPickerModel.sectionText(view.section) else ""
	p.section.Visible = hasKey
	p.title.Text = if hasKey then view.label else "All done"
	p.when.Text = if hasKey then view.when else "Every loaded sound has a decision. Export, then close the picker."
	p.soundLine.Text = if candidate
		then SoundPickerModel.soundLine(view.index, view.count, candidate.seconds)
		else "No sound to try for this one"
	p.soundLine.Visible = hasKey
	p.candidate.Text = if candidate then `"{candidate.name}" by {candidate.creator}` else ""
	p.candidate.Visible = candidate ~= nil
	p.hint.Text = view.hint
	p.hint.Visible = hasKey and view.hint ~= ""
	p.volume.Text = SoundPickerModel.volumeText(view.volume)

	p.rows.listen.Visible = candidate ~= nil
	p.rows.volume.Visible = candidate ~= nil
	p.rows.browse.Visible = candidate ~= nil
	p.rows.like.Visible = candidate ~= nil
	p.variantLine.Text = SoundPickerModel.variantText(view.picked, view.variantsWanted)
	p.variantLine.Visible = view.picking
	p.rows.variants.Visible = view.picking
	p.rows.decide.Visible = deciding
	p.buttons.skip.Visible = view.optional
	local noneShare = if view.optional then HALF else WHOLE
	p.buttons.none.Size = UDim2.new(noneShare, -GAP * (1 - noneShare), 0, BUTTON_HEIGHT)
	for i in REASON_LAYOUT do
		p.rows["reasons" .. i].Visible = deciding and p.reasonsOpen
	end
	p.rows.sample.Visible = hasKey and view.runner == "button"
	local sampleState: Button.State = if view.key == ERROR_KEY then "disabled" else "normal"
	if p.sample:getState() ~= sampleState then
		p.sample:setState(sampleState, if sampleState == "disabled" then "A disabled sample: press it" else nil)
	end
	p.buttons.undo.Visible = view.canUndo
	p.rows.finish.Visible = view.finished
	p.problems.Text = if #problems > 0 then `{#problems} problem(s) in the picker data: see the Output` else ""
	p.problems.Visible = #problems > 0
end

-- Commands --------------------------------------------------------------------------------------------------------------

local function load(data: unknown): Reply
	if type(data) ~= "table" then
		return { ok = false, error = "load needs the picker data (a table in candidates.json's shape)" }
	end
	local raw = data :: any
	local builtAt = if type(raw.builtAt) == "string" then raw.builtAt else ""
	local previous = loaded
	local m = model
	local exported = if m and previous and previous.builtAt == builtAt then m:export() else nil
	local state, known, skipped = SoundPicker.mergeLoad(previous, raw, exported)
	loaded = state

	stopBeat()
	stopStoryboard()
	leaveLoop()
	clearAuditions() -- syncAuditions below re-adds the approved keys of the new key list
	local fresh, found = SoundPickerModel.fromData({
		version = raw.version,
		builtAt = builtAt,
		keys = state.keys,
		decisions = known,
	})
	for _, problem in skipped do
		table.insert(found, problem)
	end
	model = fresh
	problems = found
	for _, problem in found do
		log:warn("data:", problem)
	end
	if panel == nil then
		panel = buildPanel()
	end
	setHidden(false)
	syncAuditions(fresh)
	render()
	local done, total = fresh:progress()
	log:info(`loaded {total} keys ({done} done), {#found} problem(s)`)
	return { ok = true, problems = found, done = done, total = total, key = fresh:currentKey() }
end

local function exportData(): Reply
	local m = model
	if m == nil then
		return { ok = false, error = "nothing is loaded yet" }
	end
	local done, total = m:progress()
	return { ok = true, done = done, total = total, export = SoundPickerModel.jsonExport(m:export()) }
end

local function state(): Reply
	local sound = SoundController.debugState()
	local p = panel
	local reply: Reply = {
		ok = true,
		enabled = enabled(),
		loaded = model ~= nil,
		open = p ~= nil,
		hidden = p ~= nil and p.hidden,
		busy = busy,
		problems = #problems,
		auditions = sound.auditions,
		voices = sound.voices,
		music = sound.music,
		ambience = sound.ambience,
		loop = loopKey,
		storyboard = storyboard ~= nil,
	}
	local m = model
	if m then
		local view = m:view()
		reply.done = view.done
		reply.total = view.total
		reply.key = view.key
		reply.index = view.index
		reply.count = view.count
		reply.picking = view.picking
		reply.finished = view.finished
	end
	return reply
end

local function close(): Reply
	closePanel()
	return { ok = true }
end

local COMMANDS: { [string]: (...any) -> Reply } = {
	load = load,
	export = exportData,
	state = state,
	close = close,
}

local function onInvoke(command: unknown, ...: any): Reply
	if not enabled() then
		return { ok = false, error = "the sound picker is off (Studio only, Config.Debug.soundPicker)" }
	end
	local handler = if type(command) == "string" then COMMANDS[command] else nil
	if handler == nil then
		return { ok = false, error = `unknown command {tostring(command)} (load, export, state, close)` }
	end
	local ok, result = pcall(handler, ...)
	if not ok then
		log:warn(`command {command} failed:`, result)
		return { ok = false, error = tostring(result) }
	end
	return result
end

-- Public ---------------------------------------------------------------------------------------------------------------

-- Pure (unit-tested): merges one "load" (`raw`, candidates.json's shape, up to 10 keys) into the round so far.
-- `previous` is the round so far (nil = none); `exported` is the current model's export when it belongs to the same
-- round (same builtAt), else nil. Another builtAt or `raw.reset` starts a new key list. Decisions: the injected ones,
-- but this Play session's own (exported) win, undos included (a key it has with no decision), for every chunk of the
-- round. Returns the round's data, the decisions of the keys loaded so far (what the model is built from, so a later
-- chunk's decisions never show as "a decision for unknown key") and the entries that had no key.
function SoundPicker.mergeLoad(
	previous: Loaded?,
	raw: any,
	exported: SoundPickerModel.Export?
): (Loaded, { [string]: any }, { string })
	local builtAt = if type(raw.builtAt) == "string" then raw.builtAt else ""
	local state: Loaded
	if previous == nil or previous.builtAt ~= builtAt or raw.reset == true then
		state = { builtAt = builtAt, keys = {}, index = {}, decisions = {}, sessionKeys = {}, session = {} }
	else
		state = previous
	end
	if exported then
		for _, key in exported.keys do
			if table.find(state.sessionKeys, key) == nil then
				table.insert(state.sessionKeys, key)
			end
			state.session[key] = exported.decisions[key]
		end
	end
	local skipped: { string } = {}
	if type(raw.keys) == "table" then
		for _, item in raw.keys :: { any } do
			local key = if type(item) == "table" then item.key else nil
			if type(key) ~= "string" then
				table.insert(skipped, "a key entry has no key")
				continue
			end
			local at = state.index[key]
			if at then
				state.keys[at] = item
			else
				table.insert(state.keys, item)
				state.index[key] = #state.keys
			end
		end
	end
	if type(raw.decisions) == "table" then
		for key, decision in raw.decisions :: { [any]: any } do
			if type(key) == "string" then
				state.decisions[key] = decision
			end
		end
	end
	for _, key in state.sessionKeys do
		state.decisions[key] = state.session[key]
	end
	local known: { [string]: any } = {}
	for key, decision in state.decisions do
		if state.index[key] ~= nil then
			known[key] = decision
		end
	end
	return state, known, skipped
end

-- Lifecycle

-- Only the BindableFunction: no UI until "load" (§18.7 safety gate 2).
function SoundPicker.init()
	if not enabled() then
		return
	end
	local player = Players.LocalPlayer
	local playerScripts = player and player:FindFirstChildOfClass("PlayerScripts")
	if playerScripts == nil then
		log:warn("PlayerScripts not found; SD_SoundPicker not created")
		return
	end
	local c = Cleanup.new()
	cleanup = c
	local existing = playerScripts:FindFirstChild(FUNCTION_NAME)
	if existing then
		existing:Destroy()
	end
	local bindable = c:add(Instance.new("BindableFunction"))
	bindable.Name = FUNCTION_NAME
	bindable.OnInvoke = onInvoke
	bindable.Parent = playerScripts
	c:add(closePanel)
end

-- Not called by the bootstrap (the client lives for the session).
function SoundPicker.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
	closePanel()
	model = nil
	loaded = nil
	table.clear(problems)
end

return SoundPicker
