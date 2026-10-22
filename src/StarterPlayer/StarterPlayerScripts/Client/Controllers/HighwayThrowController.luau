--!strict
-- HighwayThrowController (client only). Pens3 phase 13 (2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's
-- corrections, work/pens3/p13v2/NOTES.md); p13v4 (owner 2026-10-19, the TikTok throw: work/pens3/p13v4/SPEC.md 4): the
-- throw for distance on this client. The server decides everything (HighwayService: the plan, PERFECT, the boosts, the
-- rings, the pay); this module asks and shows. K = the lobby design v6's kit.json.
-- * The deck (one Scheduler render effect): the local root against WorldLayout.Highway.throwArea (HighwayMath.inArea,
--   no margin: the server allows a little more). While alive, not in a match and (in the area or launching):
--   ControlsController's Highway context is on (HighwayThrow: a left click on the world, ButtonR2, the touch Throw
--   button); FirstPersonController.setAway(true) (owner 2026-10-19: "the hands are still there and looks so bad": the
--   first-person hands overlay hides while the camera is not the player's own first person); unless first person is
--   on, the player's zoom is held at least Config.UI.Highway.deck.zoomStuds (third person on the deck), and afterwards
--   held at the saved distance for deck.restoreFrames render steps, then the saved limits exactly
--   (FirstPersonController's exit pattern: a player who came in first person goes back into it); the held squishy is
--   deck.heldScale bigger (a HeldSquishyController overlay). In the area and not launching: the PERFECT timing bar
--   (HighwayHud) at HighwayMath.barAt(server time).
-- * A launch = from a press (HighwayThrow Begin with no own throw going) until finish(): ScreenHold hides every other
--   SD_ gui, UIController.holdToasts(true) holds the toasts, the Lobby context is off (its keys open no hidden window;
--   back at the end, unless a match turned it off), the flight lines show, the camera (CameraController.save,
--   Scriptable) takes the throw shot. The press sends HighwayThrow(GetServerTimeNow(), fastSeconds) in its own thread
--   and the hand winds up at once: Diego's ThrowMotion (the equipped toy's style, Anim/ThrowTracks.styleOf) on a
--   CharacterAnimController joint layer over releaseSeconds, held cocked while the reply is late, then its release
--   clip faded out from ThrowMotion.FOLLOW to SETTLE (R15 only). A refusal finishes it and shows its reason
--   (NotifyController.showResult; highway.inFlight, highway.noFuel and net.rateLimited silently).
-- * The release (the windup done and the plan in): a World clone of the equipped squishy (SquishyCache) flyScale
--   bigger, with K's E5 trail (FxPool, white, flyScale wide); the held toy hides; sfx.throw, and "PERFECT!" when the
--   server graded it so. The throw shot holds holdAfterRelease, then the chase (rigid, high behind the squishy; its
--   first blendSeconds smoothstepped from the throw shot).
-- * The flight, on the server's clock: HighwayMath.planAt(plan, GetServerTimeNow()) (tumbling: Config.UI.Highway
--   spin; none under ReducedMotion). The flight lines: the distance, the zone (punched and ui.pop on a new one), the
--   rings hit so far over the rings of the zones reached (HighwayMath.ringsHit, = the rings paid; punched with
--   sfx.inspect.ring as each is passed), the boost button until HighwayMath.airEnd (fuel, or NO FUEL). Presses during
--   the flight go to the server as today (cap, late replies; also with AutoClick off: they are the boost); its
--   answers: boosted = the new plan (the drawn point blends over boostBlendSeconds; "SQUISH!", + "LAST ONE!" at no
--   fuel; ignored once this client drew the landing); ok = it reached the server as the flight ended (a new throw:
--   the old one lands first); highway.autoClick / highway.superFast = that warning (shown when the toast hold lets go).
-- * The landing (server time >= landsAt): the landing shot (eased at posRate), a debris burst in the landing biome's
--   lane colour, "{N} studs!"; HighwayLanded (the server's settle, the pay) for this throw within landingWaitSeconds
--   pops "BULLSEYE!" (else the distance again) with "{hit}/{total} RINGS" and "NEW BEST!". holdSeconds after the
--   landing finish(): the camera back, the holds released, the held toy back, then the landing's toasts
--   (landingToasts) if its payload is in, else when it comes. A press in the landing shot starts the next launch at
--   once: the toast hold and the Lobby context's mute stay on, so those toasts play when that launch ends. A
--   HighwayLanded for any other throw (an older one, one finished meanwhile) shows its toasts at once.
-- * finish() also runs on death, the character gone, a duel starting (StateController.isLobbyLocked, SD_MatchId /
--   SD_DuelPhase) and destroy().
-- * ReducedMotion: no camera shots (the camera stays the player's third person) and no tumble; the rest as usual.
-- * Launchers (held and platform) and gear are phase 14: nothing here changes for them but the trail's colour and the
--   launcher motion (the hook: `release`).
-- Public: the pure parts (mayForward, shotGoal, landingToasts), init(), start(scheduler?), destroy() (tests and leak
-- checks; the bootstrap never calls it), debugState(), useDeps() (Edit-mode tests: see REAL_DEPS).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local HighwayMath = require(Shared.HighwayMath)
local Palette = require(Shared.Art.Palette)
local PenMath = require(Shared.PenMath)
local PressSpeed = require(Shared.PressSpeed)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local FxPool = require(Client.Anim.FxPool)
local Scheduler = require(Client.Anim.Scheduler)
local ThrowMotion = require(Client.Anim.ThrowMotion)
local ThrowTracks = require(Client.Anim.ThrowTracks)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local HighwayHud = require(Client.UI.HighwayHud)
local NotifyFormat = require(Client.UI.NotifyFormat)
local ScreenHold = require(Client.UI.ScreenHold)
local CameraController = require(script.Parent.CameraController)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local FirstPersonController = require(script.Parent.FirstPersonController)
local GripController = require(script.Parent.GripController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

export type Toast = { text: string, kind: Types.NotifyKind }
export type Shot = "throw" | "chase" | "landing"
export type DebugState = {
	started: boolean,
	inArea: boolean,
	throwing: boolean,
	landsAt: number?,
	id: number?,
	arcs: number?,
	hasLanding: boolean,
}

type Throw = {
	pressedAt: number, -- deps.clock() of the press
	style: string, -- ThrowMotion's clip (the equipped toy's)
	kind: string, -- the squishy thrown (its look)
	legs: boolean, -- standing when it began (ThrowMotion's legs)
	plan: Types.HighwayPlan?, -- the server's answer (a boost replaces it)
	hits: { number }?, -- HighwayMath.ringsHit(plan), per plan
	passed: { [number]: boolean }, -- the hit rings already passed (their punch played)
	biome: number?, -- the zone drawn last
	blendFrom: Vector3?, -- the point drawn when a boost swapped the plan
	blendAt: number?, -- server time of that swap
	drawn: Vector3?, -- the lane-local point drawn last
	releasedAt: number?, -- clock of the release (the hand's clip)
	model: Model?,
	trail: Trail?,
	spin: number,
	landed: boolean,
	landedAt: number?,
	doneAt: number?, -- clock when the landing shot lets go
	landing: Types.HighwayLanding?, -- HighwayLanded's payload
	popped: boolean, -- its pops shown
	hold: ScreenHold.Hold?,
	camera: CameraController.Snapshot?,
	shotEye: Vector3?,
	shotLook: Vector3?,
	eye: Vector3?,
	look: Vector3?,
}

-- Constants

local U = Config.UI.Highway
local H = Config.Economy.Highway
local AREA_CONTEXT: ControlsController.Context = "Highway"
local ACTION = "HighwayThrow"
local REMOTE = "HighwayThrow"
local LANDED_REMOTE = "HighwayLanded"
local GUI = "SD_Highway"
local LAYER = "highwayThrow"
local LAYER_PRIORITY = Config.Anim.poses.throwWindup.priority or 2 -- ThrowController's throw layer's
local RIG_R15 = "R15"
local HIDE_REASON = "highwayThrow"
local OVERLAY_BIG = "highwayBig"
local CLIENT_FX = "SD_ClientFx"
local RELEASE = H.flight.releaseSeconds
local STAND_STILL = 0.1 -- Humanoid.MoveDirection below this: standing (ThrowMotion's legs)
local BURST = Vector2.new(180, 180) -- every direction (CatchFx's bursts)
local SILENT: { [string]: boolean } =
	{ ["highway.inFlight"] = true, ["highway.noFuel"] = true, ["net.rateLimited"] = true }
-- The auto-clicker check's catches (AutoClickService.checkThrow): rule B / the flood rule, and p13v3's speed rule.
local WARNINGS: { [string]: boolean } = { ["highway.autoClick"] = true, ["highway.superFast"] = true }
local KEEP: { [string]: boolean } = {}
for _, name in U.keepGuis do
	KEEP[name] = true
end
-- Verification fix: the rings in biomes 1..n (a throw's rings are counted over every zone it reached, so the count
-- matches the rings paid: each zone's rings sit on the arcs that land in the next zone).
local RINGS_UPTO: { [number]: number } = {}
for _, ring in WorldLayout.Highway.rings do
	for biome = ring.biome, #WorldLayout.Highway.biomes do
		RINGS_UPTO[biome] = (RINGS_UPTO[biome] or 0) + 1
	end
end

-- Module table

local HighwayThrowController = {}

-- Private

local function localPlayer(): Player?
	return Players.LocalPlayer
end

local function clientFx(): Instance
	local folder = Workspace:FindFirstChild(CLIENT_FX)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = CLIENT_FX
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

-- The client-only surfaces, swappable in Edit-mode tests (useDeps).
local REAL_DEPS = {
	isClient = function(): boolean
		return Players.LocalPlayer ~= nil
	end,
	bindAction = ControlsController.bindAction,
	setContext = ControlsController.setContext,
	input = ControlsController.preferredInput,
	invoke = NetController.invokeAsync,
	showResult = NotifyController.showResult,
	toast = UIController.toast,
	clock = os.clock, -- p13v3: the presses' time (the rolling second)
	serverNow = function(): number
		return Workspace:GetServerTimeNow()
	end,
	-- The local root's world position (nil without one) and whether the character is alive.
	body = function(): (Vector3?, boolean)
		local player = Players.LocalPlayer
		local character = if player then player.Character else nil
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if root == nil or not root:IsA("BasePart") then
			return nil, false
		end
		local humanoid = (character :: Model):FindFirstChildOfClass("Humanoid")
		return root.Position, humanoid ~= nil and humanoid.Health > 0
	end,
	-- A match ahead or on (the lobby locked, or the server's SD_MatchId / SD_DuelPhase set).
	locked = function(): boolean
		local player = Players.LocalPlayer
		if StateController.isLobbyLocked() then
			return true
		end
		return player ~= nil
			and FirstPersonController.inMatchFrom(
				player:GetAttribute("SD_MatchId"),
				player:GetAttribute("SD_DuelPhase")
			)
	end,
	blocked = ControlsController.isBlocked,
	-- Whether the Lobby context should be on (ControlsController's own rule: off in a match).
	lobbyWanted = function(): boolean
		local player = Players.LocalPlayer
		return player == nil
			or not FirstPersonController.inMatchFrom(
				player:GetAttribute("SD_MatchId"),
				player:GetAttribute("SD_DuelPhase")
			)
	end,
	reducedMotion = Tweens.reducedMotion,
	gripLevel = function(): number
		return GripController.level() or 1
	end,
	fpActive = FirstPersonController.isActive,
	player = function(): any?
		return Players.LocalPlayer
	end,
	camera = function(): any?
		return Workspace.CurrentCamera
	end,
	setAway = FirstPersonController.setAway,
	holdToasts = UIController.holdToasts,
	newHold = function(): ScreenHold.Hold
		local player = Players.LocalPlayer
		local gui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
		return ScreenHold.new(gui or Instance.new("Folder"), KEEP) -- no PlayerGui yet: nothing to hide
	end,
	heldHidden = function(hidden: boolean)
		local player = Players.LocalPlayer
		if player then
			HeldSquishyController.setHidden(player, HIDE_REASON, hidden)
		end
	end,
	heldOverlay = function(overlay: HeldSquishyController.Overlay?): boolean
		local player = Players.LocalPlayer
		return player ~= nil and HeldSquishyController.setOverlay(player, OVERLAY_BIG, overlay)
	end,
	onLanded = function(handler: (landing: any) -> ()): () -> ()
		local connection = NetController.on(LANDED_REMOTE, handler)
		return function()
			connection:disconnect()
		end
	end,
	-- The flying squishy: a World clone of `kind`, flyScale bigger, with K's E5 trail (white, flyScale wide).
	spawn = function(kind: string): (Model?, Trail?)
		local model = SquishyCache.clone(kind, "World")
		if U.flyScale ~= 1 then
			model:ScaleTo(model:GetScale() * U.flyScale)
		end
		model.Parent = clientFx()
		local body = model.PrimaryPart
		if body == nil then
			return model, nil
		end
		local half = Vector3.new(0, U.trail.width * U.flyScale / 2, 0) -- as wide as its two attachments are apart
		return model,
			FxPool.default():acquireTrail(body, half, -half, {
				Lifetime = U.trail.lifetime,
				WidthScale = NumberSequence.new(1, 0),
				Color = ColorSequence.new(Color3.new(1, 1, 1)),
			})
	end,
	-- The landing's debris burst (Config.UI.Highway.debris) at a world point in a colour.
	burst = function(at: Vector3, color: Color3)
		local d = U.debris
		FxPool.default():emit(at, d.count, {
			Texture = Config.Vfx.Textures.smoke,
			Lifetime = NumberRange.new(d.lifetime),
			Speed = NumberRange.new(d.speed),
			Size = NumberSequence.new(d.size),
			SpreadAngle = BURST,
			Color = ColorSequence.new(color),
		})
	end,
	newHud = function(onBoost: () -> ()): HighwayHud.Hud
		return HighwayHud.new({
			gui = UIController.screenGui(GUI, U.gui),
			onBoost = onBoost,
			scale = UIController.scale,
			compact = function(): boolean
				return UIController.layoutClass() == "compact"
			end,
		})
	end,
}
local deps: typeof(REAL_DEPS) = REAL_DEPS

local cleanup: Cleanup.Cleanup? = nil
local effect: Scheduler.Handle? = nil
local unbind: (() -> ())? = nil
local hud: HighwayHud.Hud? = nil
local inArea = false
local contextOn = false
local awayOn = false
local lobbyOff = false -- the Lobby context switched off by a launch
local big = false
local current: Throw? = nil
local sent: { number } = {} -- clock of the presses sent during the own flights (the rolling second)
local pending: { [number]: number } = {} -- id -> clock of a sent press still unanswered
local nextPending = 0
local speed = PressSpeed.new() -- p13v3: every real THROW press on this client's clock (each send reports it)
-- The deck zoom: the limits and distance saved on the deck; then the restore's steps left and its limits.
local zoom: { saved: { min: number, max: number, distance: number }?, frames: number?, min: number, max: number } =
	{ saved = nil, frames = nil, min = 0, max = 0 }

local function oldestPending(): number?
	local oldest: number? = nil
	for _, at in pending do
		if oldest == nil or at < oldest then
			oldest = at
		end
	end
	return oldest
end

local function play(key: string)
	SoundController.play(key)
end

local function pop(lines: { HighwayHud.Line })
	local h = hud
	if h then
		h:pop(lines)
	end
end

-- Lane-local (x, y, d) of a world point.
local function laneOf(world: Vector3): Vector3
	local l = (WorldLayout.Highway.origin :: CFrame):PointToObjectSpace(world)
	return Vector3.new(l.X, l.Y, -l.Z)
end

-- The hand: ThrowMotion's pose on the joint layer (R15), or the layer cleared (weight 0).
local function pose(degrees: { [string]: Vector3 }?, weight: number)
	local player = localPlayer()
	local layer = if player then CharacterAnimController.getLayer(player) else nil
	if layer == nil then
		return
	end
	if degrees == nil or weight <= 0.001 then
		if layer:has(LAYER) then
			layer:clear(LAYER)
		end
		return
	end
	if not layer:isReady() or layer:getRig() ~= RIG_R15 then
		return
	end
	local anyLayer: any = layer
	anyLayer:setAngles(LAYER, "override", degrees, weight, LAYER_PRIORITY)
end

local function showToasts(landing: Types.HighwayLanding)
	for _, toast in HighwayThrowController.landingToasts(landing) do
		deps.toast(toast.text, NotifyFormat.kindOf(toast.kind))
	end
end

-- The deck zoom (see the header): `want` raises it, else the restore runs its steps.
local function stepZoom(want: boolean)
	local player = deps.player()
	if player == nil then
		return
	end
	local deck = U.deck
	if want then
		if zoom.frames ~= nil then -- a restore still waiting: the saved limits go back first
			zoom.frames = nil
			player.CameraMaxZoomDistance = zoom.max
			player.CameraMinZoomDistance = zoom.min
		end
		if zoom.saved == nil then
			local camera = deps.camera()
			local min, max = player.CameraMinZoomDistance, player.CameraMaxZoomDistance
			zoom.saved = {
				min = min,
				max = max,
				distance = if camera then (camera.CFrame.Position - camera.Focus.Position).Magnitude else min,
			}
			player.CameraMaxZoomDistance = math.max(max, deck.zoomStuds)
			player.CameraMinZoomDistance = math.max(min, deck.zoomStuds)
		end
		return
	end
	local saved = zoom.saved
	if saved ~= nil then
		zoom.saved = nil
		local hold = math.clamp(saved.distance, saved.min, math.max(saved.min, saved.max))
		player.CameraMinZoomDistance = hold
		player.CameraMaxZoomDistance = hold
		zoom.frames, zoom.min, zoom.max = deck.restoreFrames, saved.min, saved.max
		return
	end
	local frames = zoom.frames
	if frames ~= nil then
		zoom.frames = if frames > 1 then frames - 1 else nil
		if zoom.frames == nil then
			player.CameraMaxZoomDistance = zoom.max
			player.CameraMinZoomDistance = zoom.min
		end
	end
end

-- destroy(): the saved zoom limits back at once.
local function flushZoom()
	local player = deps.player()
	local saved = zoom.saved
	if player ~= nil and saved ~= nil then
		zoom.frames, zoom.min, zoom.max = 1, saved.min, saved.max
	end
	zoom.saved = nil
	if player ~= nil and zoom.frames ~= nil then
		player.CameraMaxZoomDistance = zoom.max
		player.CameraMinZoomDistance = zoom.min
	end
	zoom.frames = nil
end

-- The held squishy deck.heldScale bigger while `want` (re-added when its overlay goes away while still wanted).
local function stepBig(want: boolean)
	if want and not big then
		local scale = Vector3.one * U.deck.heldScale
		big = deps.heldOverlay({
			step = function(): (Vector3, number, boolean)
				return scale, 0, true
			end,
			removed = function()
				big = false
			end,
		})
	elseif not want and big then
		big = false
		deps.heldOverlay(nil)
	end
end

-- Verification fix: the lobby's own keys (Inspect V / Y, I, the Nav keys, the slide and its touch button) stay off
-- for a launch, so no hidden window or camera save opens under it; back to ControlsController's own rule after.
local function muteLobby(on: boolean)
	if on ~= lobbyOff then
		lobbyOff = on
		deps.setContext("Lobby", not on and deps.lobbyWanted())
	end
end

-- Ends a launch (see the header). `chained`: the next launch starts at once (its holds keep the toasts queued).
local function finish(throw: Throw, chained: boolean?)
	if current == throw then
		current = nil
	end
	local trail = throw.trail
	if trail then
		FxPool.default():release(trail)
		throw.trail = nil
	end
	local model = throw.model
	if model then
		model:Destroy()
		throw.model = nil
	end
	local snapshot = throw.camera
	if snapshot then
		throw.camera = nil
		CameraController.restore(snapshot)
	end
	local hold = throw.hold
	if hold then
		throw.hold = nil
		hold:release()
	end
	if not chained then
		deps.holdToasts(false)
		muteLobby(false)
	end
	deps.heldHidden(false)
	pose(nil, 0)
	local h = hud
	if h then
		h:setFlight(nil)
	end
	local landing = throw.landing
	if landing then
		throw.landing = nil
		showToasts(landing)
	end
end

-- A launch starts at the press (see the header); `root` = the root's world position then.
local function launch(throw: Throw, root: Vector3?)
	local hold = deps.newHold()
	throw.hold = hold
	hold:step()
	deps.holdToasts(true)
	muteLobby(true)
	local h = hud
	if h then
		h:setBar(false)
	end
	local camera = deps.camera()
	if root == nil or camera == nil or deps.reducedMotion() then
		return
	end
	throw.camera = CameraController.save()
	camera.CameraType = Enum.CameraType.Scriptable
	local eye, look = HighwayThrowController.shotGoal("throw", laneOf(root))
	throw.shotEye, throw.shotLook, throw.eye, throw.look = eye, look, eye, look
	camera.CFrame = CFrame.lookAt(eye, look)
end

-- The release (where phase 14's A3 / A4 launcher clips would play): the model, the trail, the PERFECT pop.
local function release(throw: Throw, now: number)
	local plan = throw.plan :: Types.HighwayPlan
	throw.releasedAt = now
	throw.model, throw.trail = deps.spawn(throw.kind)
	deps.heldHidden(true)
	play(U.sounds.throw)
	if plan.perfect then
		pop({ { text = Strings.highway.pop.perfect, big = true, color = U.pop.colors.perfect } })
		play(U.sounds.perfect)
	end
end

-- The landing's pops with its payload (see the header).
local function landingPops(throw: Throw)
	local landing = throw.landing
	if landing == nil or throw.popped then
		return
	end
	throw.popped = true
	local s, colors = Strings.highway.pop, U.pop.colors
	local lines: { HighwayHud.Line } = {}
	if landing.bullseye then
		table.insert(lines, { text = s.bullseye, big = true, color = colors.bullseye })
		play(U.sounds.bullseye)
	else
		local distance = Format.distance(landing.studs)
		table.insert(
			lines,
			{ text = Strings.format(s.landed, { distance = distance }), big = true, color = colors.landed }
		)
	end
	local hit = 0
	for _, index in landing.rings do
		if WorldLayout.Highway.rings[index] ~= nil then
			hit += 1
		end
	end
	local total = RINGS_UPTO[landing.biome] or 0
	table.insert(
		lines,
		{ text = Strings.format(s.rings, { hit = hit, total = total }), big = false, color = colors.rings }
	)
	if landing.newBest then
		table.insert(lines, { text = s.newBest, big = false, color = colors.newBest })
		play(U.sounds.newBest)
	end
	pop(lines)
end

local function land(throw: Throw, now: number, p: Vector3)
	local plan = throw.plan :: Types.HighwayPlan
	throw.landed = true
	throw.landedAt = now
	throw.doneAt = now + U.landingShot.holdSeconds
	local trail = throw.trail
	if trail then
		FxPool.default():release(trail)
		throw.trail = nil
	end
	local biome = WorldLayout.Highway.biomes[plan.biome]
	local tone = if biome and biome.laneTop then (Palette :: any)[biome.laneTop] else nil
	deps.burst(WorldLayout.highwayCFrame(p.X, p.Y, p.Z).Position, tone or Palette.White)
	play(U.sounds.landed)
	if throw.landing ~= nil then
		landingPops(throw)
	else
		local text = Strings.format(Strings.highway.pop.landed, { distance = Format.distance(plan.studs) })
		pop({ { text = text, big = true, color = U.pop.colors.landed } })
	end
end

local function smoothstep(u: number): number
	local v = math.clamp(u, 0, 1)
	return v * v * (3 - 2 * v)
end

-- The camera's shot this frame (see the header); `p` = the squishy (lane-local), nil before the release.
local function drawCamera(throw: Throw, dt: number, now: number, p: Vector3?)
	local camera = deps.camera()
	if throw.camera == nil or camera == nil or throw.shotEye == nil or throw.shotLook == nil then
		return
	end
	local shotEye, shotLook = throw.shotEye :: Vector3, throw.shotLook :: Vector3
	local eye, look = shotEye, shotLook
	local released = throw.releasedAt
	if p ~= nil and throw.landed then
		local goalEye, goalLook = HighwayThrowController.shotGoal("landing", p)
		local a = 1 - math.exp(-dt * U.landingShot.posRate)
		eye = (throw.eye or shotEye):Lerp(goalEye, a)
		look = (throw.look or shotLook):Lerp(goalLook, a)
	elseif p ~= nil and released ~= nil and now >= released + U.throwShot.holdAfterRelease then
		local goalEye, goalLook = HighwayThrowController.shotGoal("chase", p)
		local u = smoothstep((now - released - U.throwShot.holdAfterRelease) / U.chase.blendSeconds)
		eye, look = shotEye:Lerp(goalEye, u), shotLook:Lerp(goalLook, u)
	end
	throw.eye, throw.look = eye, look
	camera.CFrame = CFrame.lookAt(eye, look)
end

-- The flight lines for a squishy at d (lane-local), `boost` while it may boost.
local function drawFlight(throw: Throw, d: number, boost: boolean)
	local h = hud
	if h == nil then
		return
	end
	local biome = HighwayMath.biomeAt(d)
	if throw.biome ~= biome then
		if throw.biome ~= nil then
			h:punch("zone")
			play(U.sounds.zone)
			pop(HighwayThrowController.zoneBanner(biome, deps.gripLevel()))
		end
		throw.biome = biome
	end
	local hit = 0
	local hits: { number } = throw.hits or {}
	for _, index in hits do
		local ring = WorldLayout.Highway.rings[index]
		if ring ~= nil and ring.d <= d then
			if not throw.passed[index] then
				throw.passed[index] = true
				h:punch("rings")
				play(U.sounds.ring)
			end
			hit += 1
		end
	end
	local plan = throw.plan
	h:setFlight({
		studs = math.floor(d),
		biome = biome,
		ringsHit = hit,
		ringsTotal = RINGS_UPTO[biome] or 0,
		boost = if boost and plan ~= nil then { fuel = plan.fuel, input = deps.input() } else nil,
	})
end

-- One throw's frame (see the header).
local function stepThrow(throw: Throw, dt: number, now: number, serverNow: number)
	local hold = throw.hold
	if hold then
		hold:step()
	end
	local plan = throw.plan
	-- The hand.
	if throw.releasedAt == nil then
		local u = math.clamp((now - throw.pressedAt) / RELEASE, 0, 1)
		pose(ThrowMotion.windup(throw.style, u, throw.legs), 1)
		if u >= 1 and plan ~= nil then
			release(throw, now)
		else
			drawFlight(throw, 0, false)
			drawCamera(throw, dt, now, nil)
			return
		end
	end
	local handT = now - (throw.releasedAt :: number)
	if handT <= ThrowMotion.SETTLE then
		local fade = math.clamp((handT - ThrowMotion.FOLLOW) / (ThrowMotion.SETTLE - ThrowMotion.FOLLOW), 0, 1)
		pose(ThrowMotion.release(throw.style, handT, throw.legs), 1 - fade)
	else
		pose(nil, 0)
	end
	-- The flight, on the server's clock.
	local p = plan :: Types.HighwayPlan
	local at, inAir = HighwayMath.planAt(p, serverNow)
	local from, blendAt = throw.blendFrom, throw.blendAt
	if from ~= nil and blendAt ~= nil then
		local u = (serverNow - blendAt) / U.boostBlendSeconds
		if u < 1 then
			at = from:Lerp(at, math.max(u, 0))
		else
			throw.blendFrom, throw.blendAt = nil, nil
		end
	end
	throw.drawn = at
	if not throw.landed and not deps.reducedMotion() then
		if inAir then
			throw.spin += dt * U.spinAir
		else
			local v = math.clamp((serverNow - HighwayMath.airEnd(p)) / math.max(p.roll, 1e-3), 0, 1)
			throw.spin += dt * (U.spinRoll * (1 - v) + U.spinRollMin)
		end
	end
	local model = throw.model
	if model then
		model:PivotTo(WorldLayout.highwayCFrame(at.X, at.Y, at.Z) * CFrame.Angles(-throw.spin, math.pi, 0))
	end
	drawFlight(throw, math.max(at.Z, 0), not throw.landed and serverNow < HighwayMath.airEnd(p))
	if not throw.landed and serverNow >= p.landsAt then
		land(throw, now, at)
	end
	drawCamera(throw, dt, now, at)
	if throw.doneAt ~= nil and now >= throw.doneAt then
		finish(throw)
	end
end

-- The one effect (see the header).
local function step(dt: number, now: number): boolean
	local position, alive = deps.body()
	local inside = alive
		and position ~= nil
		and HighwayMath.inArea((WorldLayout.Highway.origin :: CFrame):PointToObjectSpace(position), 0)
	local locked = deps.locked()
	local throw = current
	if throw ~= nil and (not alive or locked) then
		finish(throw)
		throw = nil
	end
	inArea = inside
	local live = alive and not locked and (inside or throw ~= nil)
	if live ~= contextOn then
		contextOn = live
		deps.setContext(AREA_CONTEXT, live)
	end
	if live ~= awayOn then
		awayOn = live
		deps.setAway(live)
	end
	stepZoom(live and not deps.fpActive())
	stepBig(live)
	local serverNow = deps.serverNow()
	local h = hud
	if h then
		local bar = inside and throw == nil and not locked and not deps.blocked()
		h:setBar(bar, if bar then HighwayMath.barAt(serverNow) else nil)
	end
	if throw then
		stepThrow(throw, dt, now, serverNow)
	end
	return true
end

-- P13v3: what a send reports (Shared/PressSpeed); the next send reports from the current run on.
local function takeReport(): number
	local report = speed.peak
	PressSpeed.sent(speed)
	return report
end

-- A new throw pressed at `now` (deps.clock): the equipped squishy, the hand's style and legs.
local function newThrow(now: number): Throw
	local equipped = StateController.get("equipped")
	local kind = if type(equipped) == "string" and Catalog.get(equipped) ~= nil then equipped else Catalog.starterId()
	local player = localPlayer()
	local character = if player then player.Character else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return {
		pressedAt = now,
		style = ThrowTracks.styleOf(kind),
		kind = kind,
		legs = humanoid ~= nil and humanoid.MoveDirection.Magnitude < STAND_STILL,
		passed = {},
		spin = 0,
		landed = false,
		popped = false,
	}
end

-- A boost's answer: the same throw's new plan (see the header).
local function boosted(plan: Types.HighwayPlan)
	local throw = current
	local old = if throw then throw.plan else nil
	-- Verification fix: a reply after this client drew the landing keeps it (HighwayLanded brings the boosted result).
	if throw == nil or old == nil or old.id ~= plan.id or throw.landed then
		return
	end
	throw.blendFrom, throw.blendAt = throw.drawn, deps.serverNow()
	throw.plan = plan
	throw.hits = HighwayMath.ringsHit(plan)
	local s, colors = Strings.highway.pop, U.pop.colors
	local lines: { HighwayHud.Line } = { { text = s.boost, big = true, color = colors.boost } }
	play(U.sounds.boost)
	if plan.fuel <= 0 then
		table.insert(lines, { text = s.lastOne, big = false, color = colors.lastOne })
		play(U.sounds.lastOne)
	end
	pop(lines)
end

-- A press while the own throw flies, sent for the auto-clicker check and as a boost (see the header). Sent even with
-- the auto-clicker check switched off (Config.Net.AutoClick.enabled): it is the boost now.
local function forward(now: number)
	local cap = H.autoClick.clientPressesPerSecond
	if not HighwayThrowController.mayForward(sent, oldestPending(), now, cap, U.lateReplySeconds) then
		return
	end
	table.insert(sent, now)
	nextPending += 1
	local id = nextPending
	pending[id] = now
	local report = takeReport()
	task.spawn(function()
		local result = deps.invoke(REMOTE, deps.serverNow(), report)
		pending[id] = nil
		if cleanup == nil then
			return -- destroyed meanwhile
		end
		if result.ok and type(result.data) == "table" then
			local plan = result.data :: Types.HighwayPlan
			if plan.boosted then
				boosted(plan)
				return
			end
			-- Verification fix: it reached the server as the flight ended, so the server threw it: show it, the old
			-- throw landing first.
			local old = current
			if old ~= nil then
				if old.plan ~= nil and not old.landed then
					land(old, deps.clock(), old.drawn or Vector3.new(0, 0, (old.plan :: Types.HighwayPlan).studs))
				end
				finish(old, true)
			end
			local throw = newThrow(now)
			throw.plan = plan
			throw.hits = HighwayMath.ringsHit(plan)
			current = throw
			launch(throw, (deps.body()))
		elseif WARNINGS[result.reason or ""] then
			deps.showResult(result) -- a catch's calm warning (each catch answers it once)
		end
	end)
end

-- `old`: a throw still in its landing shot, finished (chained) only when the new one goes.
local function begin(now: number, old: Throw?)
	-- Verification fix: a throw's first press counts toward the cap too (and keeps `sent` to the last second).
	if
		not HighwayThrowController.mayForward(sent, nil, now, H.autoClick.clientPressesPerSecond, U.lateReplySeconds)
	then
		return
	end
	if old ~= nil then
		finish(old, true)
	end
	local throw = newThrow(now)
	current = throw
	launch(throw, (deps.body()))
	table.insert(sent, now)
	local report = takeReport()
	task.spawn(function()
		local result = deps.invoke(REMOTE, deps.serverNow(), report)
		if current ~= throw then
			return -- destroyed or replaced meanwhile
		end
		if result.ok and type(result.data) == "table" then
			local plan = result.data :: Types.HighwayPlan
			throw.plan = plan
			throw.hits = HighwayMath.ringsHit(plan)
			return
		end
		finish(throw)
		if not SILENT[result.reason or ""] then
			deps.showResult(result)
		end
	end)
end

local function onPress(state: Enum.UserInputState): boolean?
	if state ~= Enum.UserInputState.Begin then
		return nil
	end
	local now = deps.clock()
	PressSpeed.press(speed, now)
	local throw = current
	if throw ~= nil and not throw.landed then
		forward(now)
		return true
	end
	begin(now, throw) -- a throw still in its landing shot: the next one takes over
	return true
end

-- HighwayLanded: the server's settle of one of this player's throws (see the header).
local function onLanded(landing: any)
	if type(landing) ~= "table" or type(landing.id) ~= "number" then
		return
	end
	local throw = current
	local plan = if throw then throw.plan else nil
	if throw ~= nil and plan ~= nil and plan.id == landing.id then
		throw.landing = landing
		local at = throw.landedAt
		if throw.landed and at ~= nil and deps.clock() - at <= U.landingWaitSeconds then
			landingPops(throw)
		end
		return
	end
	showToasts(landing)
end

-- Public: the pure parts -------------------------------------------------------------------------------------------

-- Whether a press may be sent now (see the header). `sent` keeps only the last second's.
function HighwayThrowController.mayForward(
	list: { number },
	oldest: number?,
	now: number,
	cap: number,
	late: number
): boolean
	local kept = 0
	for _, at in list do
		if now - at < 1 then
			kept += 1
			list[kept] = at
		end
	end
	for index = #list, kept + 1, -1 do
		list[index] = nil
	end
	if oldest ~= nil and now - oldest > late then
		return false
	end
	return #list < cap
end

-- A shot's eye and the point it looks at (world) for lane-local p = (x, y, d): "throw" (p = the root at the press),
-- "chase" and "landing" (p = the squishy); Config.UI.Highway's offsets.
function HighwayThrowController.shotGoal(kind: Shot, p: Vector3): (Vector3, Vector3)
	local eye: Vector3, look: Vector3
	if kind == "throw" then
		local s = U.throwShot
		eye, look = Vector3.new(p.X + s.side, p.Y + s.up, p.Z + s.front), Vector3.new(p.X, p.Y + s.lookUp, p.Z)
	elseif kind == "chase" then
		local c = U.chase
		eye, look = Vector3.new(p.X, p.Y + c.up, p.Z - c.back), Vector3.new(p.X, p.Y + c.lookUp, p.Z + c.lookAhead)
	else
		local l = U.landingShot
		eye, look = Vector3.new(p.X + l.side, p.Y + l.up, p.Z - l.back), p
	end
	return WorldLayout.highwayCFrame(eye.X, eye.Y, eye.Z).Position,
		WorldLayout.highwayCFrame(look.X, look.Y, look.Z).Position
end

-- Owner 2026-10-22 (Break and Steal an Egg): the banner as the squishy enters `biome`, its name and the throw power the
-- zone starts at, green when a Grip `level` throw reaches it, red when not.
function HighwayThrowController.zoneBanner(biome: number, level: number): { HighwayHud.Line }
	local def = WorldLayout.Highway.biomes[biome]
	local wall = H.walls[biome]
	if def == nil or wall == nil then
		return {}
	end
	local ready = HighwayMath.power(level) >= wall
	return {
		{ text = Strings.resolve(def.nameKey) or "", big = true, color = def.nameColor },
		{
			text = Strings.format(Strings.highway.screen.recommended, { power = Format.power(wall) }),
			big = false,
			color = if ready then U.pop.colors.zoneReady else U.pop.colors.zoneTooWeak,
		},
	}
end

-- The landing's toasts (see the header).
function HighwayThrowController.landingToasts(data: Types.HighwayLanding): { Toast }
	local h = Strings.highway
	local distance = Format.distance(data.studs)
	local toasts: { Toast } = {
		{
			text = Strings.format(
				h.landed,
				{ distance = distance, coins = Format.coins(data.coins), grip = Format.coins(data.grip) }
			),
			kind = "success",
		},
	}
	if data.newBest then
		table.insert(toasts, { text = Strings.format(h.newBest, { distance = distance }), kind = "success" })
	end
	local biome = if data.reached then WorldLayout.Highway.biomes[data.reached] else nil
	if biome ~= nil then
		local name = Strings.resolve(biome.nameKey) or ""
		table.insert(toasts, { text = Strings.format(h.reached, { biome = name }), kind = "info" })
	end
	local counts: { [string]: number } = {}
	local order: { string } = {}
	for _, kind in data.gifts do
		if counts[kind] == nil then
			table.insert(order, kind)
		end
		counts[kind] = (counts[kind] or 0) + 1
	end
	for _, kind in order do
		local def = Catalog.get(kind)
		local name = if def then Strings.resolve(def.nameKey) or kind else kind
		local count = counts[kind]
		local text = Strings.format(Strings.plural(count, h.gift.one, h.gift.many), { count = count, name = name })
		table.insert(toasts, { text = text, kind = "success" })
	end
	local bag = data.food
	if bag ~= nil then
		local food = PenMath.food(bag.id)
		local name = if food then Strings.resolve(food.nameKey) or bag.id else bag.id
		table.insert(toasts, { text = Strings.format(h.foodBag, { count = bag.count, food = name }), kind = "info" })
	end
	return toasts
end

function HighwayThrowController.debugState(): DebugState
	local throw = current
	local plan = if throw then throw.plan else nil
	return {
		started = cleanup ~= nil,
		inArea = inArea,
		throwing = throw ~= nil,
		landsAt = if plan then plan.landsAt else nil,
		id = if plan then plan.id else nil,
		arcs = if plan then #plan.arcs else nil,
		hasLanding = throw ~= nil and throw.landing ~= nil,
	}
end

-- Test seam (Edit mode): replaces some of the client-only surfaces (REAL_DEPS' keys; nil = the real ones again).
function HighwayThrowController.useDeps(overrides: { [string]: any }?)
	if overrides == nil then
		deps = REAL_DEPS
		return
	end
	local merged: { [string]: any } = table.clone(REAL_DEPS :: any)
	for key, value in overrides do
		assert(merged[key] ~= nil, `[SD][HighwayThrow] unknown dependency {key}`)
		merged[key] = value
	end
	deps = merged :: any
end

-- Lifecycle

function HighwayThrowController.init()
	-- Nothing to register: the action is bound at start (on a client).
end

-- `scheduler` defaults to the client's (tests pass a private one).
function HighwayThrowController.start(scheduler: Scheduler.Scheduler?)
	if cleanup ~= nil then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	c:add(function()
		local throw = current
		if throw then
			finish(throw)
		end
		local handle = effect
		if handle then
			handle:disconnect()
		end
		effect = nil
		local undo = unbind
		unbind = nil
		if undo then
			undo()
		end
		inArea = false
		if contextOn then
			contextOn = false
			deps.setContext(AREA_CONTEXT, false)
		end
		if awayOn then
			awayOn = false
			deps.setAway(false)
		end
		flushZoom()
		stepBig(false)
		local h = hud
		hud = nil
		if h then
			h:destroy()
		end
		table.clear(sent)
		table.clear(pending)
		speed = PressSpeed.new()
	end)
	if not deps.isClient() then
		return -- not a client (Edit-mode tests): no character to watch, nothing to throw
	end
	hud = deps.newHud(function()
		onPress(Enum.UserInputState.Begin)
	end)
	c:add(deps.onLanded(onLanded))
	unbind = deps.bindAction(ACTION, function(state: Enum.UserInputState): boolean?
		return onPress(state)
	end)
	effect = (scheduler or Scheduler.default()):add(step, "render")
end

function HighwayThrowController.destroy()
	local c = cleanup
	if c then
		cleanup = nil
		c:clean()
	end
end

return HighwayThrowController
