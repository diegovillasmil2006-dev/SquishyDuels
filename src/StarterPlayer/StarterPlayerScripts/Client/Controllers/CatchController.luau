--!strict
-- CatchController (client only). Feature 1 (2026-10-11, the user-approved plan; Config.Combat.Catch; design: the
-- combat-effects page "Squishy Combat FP v2.html", html:88, 342-354, 528-570, 613-614, 672-674). The catch: its input,
-- its gate, the local catcher's window and crush, and every client's view of a catch from CatchEvent. The server
-- decides every catch and every lost life (CombatService, Logic/CatchRules); this module sends intent and times looks.
--
-- * Input: the Catch action (ControlsController: E, ButtonL1, the touch Catch button, the right mouse button), Duel
--   context only. A press the gate allows (gate, pure: a live duel phase, alive, the hands not crushing, not rooted
--   by an ultimate, not in a throw windup, cooldownSeconds since the last press, the server's own rules) sends
--   CatchRequest(clientTime), drops a running charge (ThrowController.cancelCharge; design: html:344) and keeps the
--   hands busy for the window (ThrowController.setHandsBusy). The press is taken (sunk) in a live duel even when the
--   gate refuses it (the cooldown): no other duel action uses those keys.
-- * CatchEvent "caught": every client keeps the crush (its server times) and fires Caught; at burstAt (server time) it
--   fires Burst once (the visual burst everywhere: the overlay, the drawn toy, the world effects, the banners). For the
--   local catcher: the hands stay busy until the catch + handsBackSeconds (no throw, catch, dash or ultimate), the
--   catch sound (2D) and hit-stop (Config.FirstPerson.catch.hitStopSeconds), the charge tone again rising with the
--   crush's e (design: html:351, 552), the squeak at squeakAt (design: html:553), then at the burst the burst sound,
--   the burst hit-stop (Catch.burstHitStopSeconds) and a flash in the caught toy's colour (design: html:560; held to
--   Config.Vfx.Flash: at most maxOverlayOpacity, its peak no faster than minPeakMs; none under ReducedMotion). Other
--   clients (the thrower) hear the catch and the burst 3D at the catch. A CatchEvent "burst" before the local burst
--   time (clock skew) fires Burst at once. The lives come from the server: StateController and VfxController read
--   CatchEvent "burst" themselves.
-- * The "Catch!" prompt (incoming, design: html:672-674): the opponent's own throws are followed from ThrowStarted
--   (ProjectileMath, the server's path) until their ThrowImpact, their CatchEvent or ProjectileMaxLifetime; incoming()
--   is true while one is within Config.UI.Reticle.catchPromptStuds of the local catcher's centre and moving toward it.
-- * qb1 (owner 2026-10-18 "Yes, catching works"): a Free for All / Team Deathmatch match is live for the gate too
--   (liveIn: the duel's or the match's phase), and the prompt follows every enemy's throw there
--   (followsThrower: StateController.isEnemy; never a teammate's). Leaving the match clears the crush like a duel.
-- * HUD hooks: state() (ready, the cooldown's progress, the window, the crush) for the duel dock and the touch Catch
--   button (drawn here: ControlsController.setTouchState), localCatch() for the first-person overlay.
-- Require direction: NetController, StateController, ControlsController, SoundController, UIController and
-- ThrowController (all above it); ViewmodelController, DuelController, ProjectileRenderer and VfxController read it.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local ProjectileMath = require(Shared.ProjectileMath)
local Signal = require(Shared.Util.Signal)
local ThrowCharge = require(Shared.ThrowCharge)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local HitStop = require(Client.Anim.HitStop)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local ControlsController = require(script.Parent.ControlsController)
local NetController = require(script.Parent.NetController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local ThrowController = require(script.Parent.ThrowController)
local UIController = require(script.Parent.UIController)

-- Types

export type Event = Types.CatchEventPayload

-- What the gate reads (all server times).
export type GateFacts = {
	inDuel: boolean, -- the Duel context is on and the match is in Active or SuddenDeath
	alive: boolean,
	now: number,
	lastPressAt: number,
	handsBackAt: number, -- the own crush's end (-math.huge = none)
	rooted: boolean, -- an ultimate's telegraph or recovery
	windup: boolean, -- a throw windup
}

-- The catch for the HUD (state()).
export type CatchState = {
	ready: boolean, -- a press would be sent now
	progress: number, -- 0 (just pressed / crushing) .. 1 (ready)
	open: boolean, -- the hands are open (the window)
	crushing: boolean, -- the hands hold a caught toy (until they are back)
	left: number, -- Duel HUD part 2: seconds of the cooldown left (0 when it has run out)
}

-- One catch every client follows, from its "caught" event to its burst.
type Crush = {
	event: Event,
	local_: boolean, -- the local player is the catcher
	burst: boolean, -- Burst has fired
	squeaked: boolean,
}

-- One of the opponent's throws in flight (the prompt).
type Incoming = { trajectory: ProjectileMath.Trajectory, untilAt: number }

-- Constants

local CATCH = Config.Combat.Catch
local FP_CATCH = Config.FirstPerson.catch
local FP_CRUSH = Config.FirstPerson.crush
local RETICLE = Config.UI.Reticle
local FLASH = Config.Vfx.Flash
local RULES = Config.Duel.Rules
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local ACTION = "Catch"
local REASON_CONTEXT = "catch.context"
local REASON_BUSY = "catch.busy"
local REASON_COOLDOWN = "catch.cooldown"
local SOUND_CATCH = "sfx.catch"
local SOUND_SQUEAK = "sfx.crushSqueak"
local SOUND_BURST = "sfx.crushBurst"
local SOUND_TONE = "sfx.chargeLoop"
local TONE_STOP_MS = Config.Audio.charge.stopFadeMs
local FLASH_GUI = "SD_CatchFlash"
-- build choice 2026-10-11 (NOT IN DESIGN): the flash draws over the world and the first-person overlay (DisplayOrder
-- -1) and under every HUD (SD_Hud 10); full-bleed. Not in Config.UI.ScreenGuis (that table is §11.1's, as SD_Touch).
local FLASH_GUI_SPEC = { displayOrder = 0, insets = Enum.ScreenInsets.None }
local FLASH_DECAY = 6 -- per second after the peak (design: html:675, flashA *= exp(-dt·6))
local FLASH_GONE = 0.01
local MS = 1000

-- Module table

local CatchController = {}

-- (event) a throw was caught (every client); the event's phase is "caught".
CatchController.Caught = Signal.new() :: Signal.Signal<Event>
-- (event) the caught toy bursts now (every client, once per catch, at its burstAt); phase "burst".
CatchController.Burst = Signal.new() :: Signal.Signal<Event>

-- Private

local log = Log.new("Catch")
local cleanup: Cleanup.Cleanup? = nil
local lastPressAt = -math.huge -- server time of the last sent press
local windowUntil = -math.huge -- server time the local window closes
local handsBackAt = -math.huge -- server time the local hands are back from a crush
local crushes: { [number]: Crush } = {} -- projId -> crush
local incomings: { [number]: Incoming } = {} -- projId -> the opponent's throw in flight
local tone: SoundController.Loop? = nil
local flashFrame: Frame? = nil
local flashStart = -math.huge -- os.clock() of the flash's start
local flashColor: Color3? = nil
local stats = { pressed = 0, refused = 0, caught = 0, bursts = 0 }

-- Pure helpers (unit-tested) ------------------------------------------------------------------------------------------

-- The reason a press is refused (the server's codes, Logic/CatchRules), or nil when it may be sent.
function CatchController.gate(f: GateFacts): string?
	if not f.inDuel or not f.alive then
		return REASON_CONTEXT
	end
	if f.now < f.handsBackAt or f.rooted or f.windup then
		return REASON_BUSY
	end
	if f.now < f.lastPressAt + CATCH.cooldownSeconds then
		return REASON_COOLDOWN
	end
	return nil
end

-- The dock's and the touch button's fill: the cooldown since the last press (0 -> 1), 0 while the hands crush.
function CatchController.progress(now: number, pressedAt: number, backAt: number): number
	if now < backAt then
		return 0
	end
	if not (pressedAt > -math.huge) then
		return 1
	end
	return math.clamp((now - pressedAt) / CATCH.cooldownSeconds, 0, 1)
end

-- qb1: whether the catch is live: a duel view or (FFA/TDM) a match view in Active or SuddenDeath.
function CatchController.liveIn(duel: any?, match: any?): boolean
	return (duel ~= nil and LIVE_PHASES[duel.phase] == true) or (match ~= nil and LIVE_PHASES[match.phase] == true)
end

-- qb1: whether the prompt follows a throw by `throwerId`: the duel's opponent, else an enemy of the match.
function CatchController.followsThrower(duel: any?, match: any?, throwerId: number): boolean
	if duel ~= nil then
		return throwerId == duel.opponent.userId
	end
	return StateController.isEnemy(match, throwerId)
end

-- The crush's ease e at t seconds after the catch (design: html:538).
function CatchController.crushEase(t: number): number
	return math.clamp((t - FP_CRUSH.easeFrom) / FP_CRUSH.easeOver, 0, 1)
end

-- The design's prompt test (html:673): within `reach` of `centre` and moving toward it.
function CatchController.comingAt(position: Vector3, velocity: Vector3, centre: Vector3, reach: number): boolean
	local toMe = centre - position
	return toMe.Magnitude < reach and velocity:Dot(toMe) > 0
end

-- The flash's opacity t seconds after the burst (design: html:560 flash 0.5, html:675 exp(-6t)): up to
-- Vfx.Flash.maxOverlayOpacity over minPeakMs (never faster), then the design's decay.
function CatchController.flashOpacity(t: number): number
	if t < 0 then
		return 0
	end
	local peak = FLASH.maxOverlayOpacity
	local rise = FLASH.minPeakMs / MS
	if t < rise then
		return peak * t / rise
	end
	return peak * math.exp(-FLASH_DECAY * (t - rise))
end

local function isNumber(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A CatchEvent payload, shape-checked (server data, still checked), or nil.
function CatchController.parseEvent(raw: unknown): Event?
	if type(raw) ~= "table" then
		return nil
	end
	local e = raw :: any
	if
		(e.phase ~= "caught" and e.phase ~= "burst")
		or not isNumber(e.catcherId)
		or not isNumber(e.throwerId)
		or not isNumber(e.projId)
		or type(e.squishyId) ~= "string"
		or typeof(e.position) ~= "Vector3"
		or not isNumber(e.at)
		or not isNumber(e.burstAt)
	then
		return nil
	end
	if (e.livesLeft ~= nil and not isNumber(e.livesLeft)) or (e.invulnUntil ~= nil and not isNumber(e.invulnUntil)) then
		return nil
	end
	return e :: Event
end

-- Runtime helpers -----------------------------------------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function localPlayer(): Player?
	return Players.LocalPlayer
end

local function localId(): number?
	local player = localPlayer()
	return if player then player.UserId else nil
end

local function play(key: string, options: SoundController.PlayOptions?)
	local ok, err = pcall(SoundController.play, key, options)
	if not ok then
		log:warn(`sound {key} failed:`, err)
	end
end

local function aliveRoot(): BasePart?
	local player = localPlayer()
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return root
end

local function windupBusy(): boolean
	local tau, _, _, releaseStart, cancelled = ThrowController.localWindup()
	return tau ~= nil and releaseStart == nil and not cancelled
end

local function factsNow(now: number): GateFacts
	local live = CatchController.liveIn(StateController.duel(), StateController.match())
	return {
		inDuel = ControlsController.isContextActive("Duel") and live,
		alive = aliveRoot() ~= nil,
		now = now,
		lastPressAt = lastPressAt,
		handsBackAt = handsBackAt,
		rooted = ThrowController.rootedNow(),
		windup = windupBusy(),
	}
end

local function accentOf(squishyId: string): Color3?
	local def = Catalog.get(squishyId)
	return if def then Color3.fromHex(def.visuals.accent) else nil
end

-- The crush tone (the local catcher): the charge tone again, driven by the crush's e (design: html:351, 552).
local function setTone(e: number?, t: number)
	if e == nil then
		local loop = tone
		tone = nil
		if loop then
			loop:stop(TONE_STOP_MS)
		end
		return
	end
	if tone == nil then
		local ok, loop = pcall(SoundController.playLoop, SOUND_TONE, { volume = 0, priority = 1 })
		tone = if ok then loop else nil
	end
	local loop = tone
	if loop then
		local pitch, volume = ThrowCharge.tone(e, t)
		loop:setPitch(pitch)
		loop:setVolume(volume)
	end
end

local function ensureFlash(): Frame?
	local frame = flashFrame
	if frame and frame.Parent ~= nil then
		return frame
	end
	local ok, gui = pcall(UIController.screenGui, FLASH_GUI, FLASH_GUI_SPEC :: any)
	if not ok then
		return nil
	end
	local made = Instance.new("Frame")
	made.Name = "Flash"
	made.Size = UDim2.fromScale(1, 1)
	made.BorderSizePixel = 0
	made.BackgroundTransparency = 1
	made.Active = false
	made.Interactable = false
	made.Visible = false
	made.Parent = gui
	flashFrame = made
	return made
end

local function stepFlash()
	local frame = flashFrame
	if frame == nil or not frame.Visible then
		return
	end
	local opacity = CatchController.flashOpacity(os.clock() - flashStart)
	if opacity < FLASH_GONE and os.clock() - flashStart > FLASH.minPeakMs / MS then
		frame.Visible = false
		return
	end
	frame.BackgroundTransparency = 1 - opacity
	if flashColor and frame.BackgroundColor3 ~= flashColor then
		frame.BackgroundColor3 = flashColor
	end
end

local function startFlash(color: Color3?)
	if Tweens.reducedMotion() then
		return
	end
	local frame = ensureFlash()
	if frame == nil then
		return
	end
	flashColor = color
	flashStart = os.clock()
	frame.Visible = true
	stepFlash()
end

-- One crush's burst moment, once (Burst for every listener; the local catcher's sounds, hit-stop and flash).
local function burstNow(crush: Crush)
	if crush.burst then
		return
	end
	crush.burst = true
	stats.bursts += 1
	local event = table.clone(crush.event)
	event.phase = "burst"
	if crush.local_ then
		setTone(nil, 0)
		play(SOUND_BURST, { priority = 2 })
		HitStop.trigger("burst:" .. event.projId, CATCH.burstHitStopSeconds, os.clock(), Tweens.reducedMotion())
		startFlash(accentOf(event.squishyId))
	else
		play(SOUND_BURST, { at = event.position, priority = 1 })
	end
	CatchController.Burst:fire(event :: any)
end

local function onCaught(event: Event)
	incomings[event.projId] = nil
	if crushes[event.projId] ~= nil then
		return
	end
	local isLocal = event.catcherId == localId()
	crushes[event.projId] = { event = event, local_ = isLocal, burst = false, squeaked = false }
	stats.caught += 1
	if isLocal then
		handsBackAt = math.max(handsBackAt, event.at + CATCH.handsBackSeconds)
		windowUntil = -math.huge
		ThrowController.cancelCharge()
		ThrowController.setHandsBusy(handsBackAt)
		play(SOUND_CATCH, { priority = 2 })
		HitStop.trigger("catch:" .. event.projId, FP_CATCH.hitStopSeconds, os.clock(), Tweens.reducedMotion())
	else
		play(SOUND_CATCH, { at = event.position, priority = 1 })
	end
	CatchController.Caught:fire(event)
end

local function onEvent(raw: unknown)
	local event = CatchController.parseEvent(raw)
	if event == nil then
		return
	end
	if event.phase == "caught" then
		onCaught(event)
		return
	end
	-- "burst": the server's (lives are StateController's and VfxController's). A late "caught" never came: follow it now.
	local crush = crushes[event.projId]
	if crush == nil then
		local caught = table.clone(event)
		caught.phase = "caught"
		onCaught(caught :: any)
		crush = crushes[event.projId]
	end
	if crush then
		burstNow(crush)
	end
end

local function onThrowStarted(raw: unknown)
	local payload = ThrowController.parseThrowStarted(raw)
	local duel, match = StateController.duel(), StateController.match()
	if
		payload == nil
		or payload.kind ~= "throw"
		or not CatchController.followsThrower(duel, match, payload.throwerId)
	then
		return
	end
	incomings[payload.projId] = {
		trajectory = {
			origin = payload.origin,
			velocity = payload.velocity,
			gravity = payload.gravity,
			releaseAt = payload.releaseAt,
		},
		untilAt = payload.releaseAt + RULES.ProjectileMaxLifetime,
	}
end

local function onThrowImpact(raw: unknown)
	local impact = ThrowController.parseImpact(raw)
	if impact then
		incomings[impact.projId] = nil
	end
end

local function stepCrushes(now: number)
	for projId, crush in crushes do
		local event = crush.event
		if crush.local_ and not crush.burst then
			local t = now - event.at
			setTone(CatchController.crushEase(t), t)
			if not crush.squeaked and t >= FP_CRUSH.squeakAt then
				crush.squeaked = true
				play(SOUND_SQUEAK, { priority = 1 }) -- design: html:553
			end
		end
		if not crush.burst and now >= event.burstAt then
			burstNow(crush)
		end
		if crush.burst and now > event.at + CATCH.handsBackSeconds then
			crushes[projId] = nil
		end
	end
end

local function stepTouch(now: number)
	local progress = CatchController.progress(now, lastPressAt, handsBackAt)
	ControlsController.setTouchState("Catch", progress, nil)
end

local function step(_dt: number, _clock: number): boolean
	local now = serverNow()
	stepCrushes(now)
	for projId, incoming in incomings do
		if now > incoming.untilAt then
			incomings[projId] = nil
		end
	end
	stepFlash()
	stepTouch(now)
	return true
end

local function clearMatch()
	windowUntil = -math.huge
	handsBackAt = -math.huge
	lastPressAt = -math.huge
	table.clear(crushes)
	table.clear(incomings)
	setTone(nil, 0)
end

-- Public ----------------------------------------------------------------------------------------------------------------

-- A catch press now (the Catch action, Studio): sends it when the gate allows. Returns whether it was sent.
function CatchController.press(): boolean
	local now = serverNow()
	local reason = CatchController.gate(factsNow(now))
	if reason ~= nil then
		stats.refused += 1
		return false
	end
	if not NetController.catchRequest(now) then
		stats.refused += 1
		return false -- dropped locally (the bucket)
	end
	stats.pressed += 1
	lastPressAt = now
	windowUntil = now + CATCH.windowSeconds
	ThrowController.cancelCharge() -- design: html:344
	ThrowController.setHandsBusy(windowUntil)
	return true
end

-- Whether one of the opponent's throws within the prompt's reach comes at the local player now (design: html:673).
function CatchController.incoming(): boolean
	local root = aliveRoot()
	if root == nil then
		return false
	end
	local now = serverNow()
	local centre = root.Position + Vector3.new(0, CATCH.centreAboveRootStuds, 0)
	for _, incoming in incomings do
		local tr = incoming.trajectory
		if now >= tr.releaseAt then
			local t = now - tr.releaseAt
			local position = ProjectileMath.positionAt(tr.origin, tr.velocity, tr.gravity, t)
			local velocity = ProjectileMath.velocityAt(tr.velocity, tr.gravity, t)
			if CatchController.comingAt(position, velocity, centre, RETICLE.catchPromptStuds) then
				return true
			end
		end
	end
	return false
end

function CatchController.state(): CatchState
	local now = serverNow()
	return {
		ready = CatchController.gate(factsNow(now)) == nil,
		progress = CatchController.progress(now, lastPressAt, handsBackAt),
		open = now < windowUntil,
		crushing = now < handsBackAt,
		left = math.max(0, lastPressAt + CATCH.cooldownSeconds - now),
	}
end

-- The local catcher's hands for the first-person overlay: ("open", seconds since the press) during the window;
-- ("crush", seconds since the catch, the caught toy's id, burstAt) until the burst; ("after", seconds since the catch,
-- id, burstAt) until the hands are back; else nil.
function CatchController.localCatch(): (string?, number?, string?, number?)
	local now = serverNow()
	for _, crush in crushes do
		if crush.local_ then
			local event = crush.event
			local t = now - event.at
			if not crush.burst then
				return "crush", t, event.squishyId, event.burstAt
			elseif now < event.at + CATCH.handsBackSeconds then
				return "after", t, event.squishyId, event.burstAt
			end
		end
	end
	if now < windowUntil then
		return "open", now - lastPressAt, nil, nil
	end
	return nil, nil, nil, nil
end

-- Studio / debug counters.
function CatchController.counts(): { [string]: any }
	local live, following = 0, 0
	for _ in crushes do
		live += 1
	end
	for _ in incomings do
		following += 1
	end
	return {
		pressed = stats.pressed,
		refused = stats.refused,
		caught = stats.caught,
		bursts = stats.bursts,
		crushes = live,
		incoming = following,
	}
end

-- Lifecycle

function CatchController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(
		ControlsController.bindAction(ACTION, function(inputState: Enum.UserInputState, _input: InputObject?): boolean?
			if inputState ~= Enum.UserInputState.Begin then
				return false
			end
			CatchController.press()
			return true -- a live Duel action: the press is the catch's, sent or not (header)
		end)
	)
	c:add(Scheduler.add(step, "render"))
	c:add(NetController.onCatchEvent(onEvent :: any))
	c:add(NetController.onThrowStarted(onThrowStarted :: any))
	c:add(NetController.onThrowImpact(onThrowImpact :: any))
	c:add(StateController.DuelChanged:connect(function(view: any)
		if view == nil then
			clearMatch()
		end
	end))
	c:add(StateController.MatchChanged:connect(function(view: any) -- qb1: a match's catch ends with it
		if view == nil then
			clearMatch()
		end
	end))
	c:add(function()
		clearMatch()
		local frame = flashFrame
		flashFrame = nil
		if frame then
			frame:Destroy()
		end
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function CatchController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return CatchController
