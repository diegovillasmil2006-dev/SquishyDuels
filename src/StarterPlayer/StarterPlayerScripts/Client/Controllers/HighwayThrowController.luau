--!strict
-- HighwayThrowController (client only). Pens3 phase 13 (2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's
-- corrections, work/pens3/p13v2/NOTES.md): the throw for distance on this client. The server decides everything
-- (HighwayService); this module asks and shows. The lobby design v6: P3D = "Squishy Lobby 3D.html", K = kit.json.
-- * The area (owner 2026-10-18: "a general area where they walk up and everybody can throw"): one Scheduler render
--   effect checks the local character's root against WorldLayout.Highway.throwArea (HighwayMath.inArea, no margin: the
--   server allows a little more) and turns ControlsController's Highway context on inside it (HighwayThrow live: a
--   left click on the world, ButtonR2, the touch Throw button), off outside.
-- * A press (HighwayThrow Begin) with no own throw going: HighwayThrow(GetServerTimeNow()) in its own thread, and the
--   hand winds up at once: Diego's ThrowMotion (Anim/ThrowMotion, the equipped toy's style, Anim/ThrowTracks.styleOf)
--   on a CharacterAnimController joint layer, its windup over the release time (Config.Economy.Highway.flight.
--   releaseSeconds, K:5295's Release marker), held cocked while the reply is late, then its release clip faded out
--   from ThrowMotion.FOLLOW to SETTLE (R15 only). A refusal ends it and shows its reason (NotifyController.showResult;
--   highway.inFlight and net.rateLimited silently). A press while the own throw flies is sent too (the server's
--   auto-clicker check sees the real rhythm), none while a reply is Config.UI.Highway.lateReplySeconds late, none
--   while the check is off (Config.Net.AutoClick.enabled false); every send, a throw's first press too, counts toward
--   Config.Economy.Highway.autoClick.clientPressesPerSecond in any rolling second. Verification fixes: its answer
--   highway.autoClick (a catch) shows that warning; an ok answer (it reached the server as the flight ended, so the
--   server threw it and paid) becomes the throw shown, the old one landing first; other answers stay silent.
-- * The flight (P3D:575-597 through HighwayMath.at, on the server's clock: released at landsAt - flight +
--   releaseSeconds): a World clone of the equipped squishy (SquishyCache) from the throwing hand over the arc to the
--   carry and rolling to the server's landing, tumbling (Config.UI.Highway spin; none under ReducedMotion), with K's
--   E5 trail (FxPool, white: the tier colour comes with phase 14's launchers). The held toy hides from the release to
--   the end. The follow camera (P3D:849-850, Config.UI.Highway.follow; CameraController.save / restore): Scriptable,
--   easing behind the squishy, let go holdSeconds after the landing; none under ReducedMotion.
-- * HUD stand-ins (Diego draws the highway HUD; PLACEHOLDERS in work/pens3/p13v2/NOTES.md): while it flies, a WellPill
--   (the daily timer's look) top centre of SD_Hud with the biome it is in and its distance (the biome banner and the
--   distance); at the landing, toasts (UIController.toast): the landing's distance, Coins and Grip, then a new best, a
--   new biome, the biome gifts and the Food Bag when they happened (landingToasts). The launch board is the server's.
-- * Launchers (held and platform) and gear are phase 14: throwPower would multiply them on the server; nothing here
--   changes for them but the trail's colour and the launcher motion (the hook: `release`, where A3 / A4 would play).
-- One Scheduler effect (render) steps the area, the hand, the flight, the camera and the pill. Public: the pure parts
-- (mayForward, followGoal, landingToasts, pillText), init(), start(scheduler?), destroy() (tests and leak checks; the
-- bootstrap never calls it), debugState(), useDeps() (Edit-mode tests: isClient, bindAction, invoke, showResult,
-- toast).

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
local PenMath = require(Shared.PenMath)
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
local NotifyFormat = require(Client.UI.NotifyFormat)
local WellPill = require(Client.UI.Components.WellPill)
local CameraController = require(script.Parent.CameraController)
local CharacterAnimController = require(script.Parent.CharacterAnimController)
local ControlsController = require(script.Parent.ControlsController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

export type Toast = { text: string, kind: Types.NotifyKind }
export type DebugState = { started: boolean, inArea: boolean, throwing: boolean, landsAt: number? }

type Throw = {
	pressedAt: number, -- os.clock of the press
	style: string, -- ThrowMotion's clip (the equipped toy's)
	kind: string, -- the squishy thrown (its look)
	legs: boolean, -- standing when it began (ThrowMotion's legs)
	data: Types.HighwayResult?, -- the server's answer
	releasedAt: number?, -- os.clock of the release (the hand's clip)
	plan: HighwayMath.Flight?, -- the flight from the hand (the server's times, from the hand's distance)
	x0: number,
	y0: number,
	model: Model?,
	trail: Trail?,
	spin: number,
	landed: boolean,
	doneAt: number?, -- os.clock when the camera lets go
	camera: CameraController.Snapshot?,
	eye: Vector3?,
	look: Vector3?,
}

-- Constants

local U = Config.UI.Highway
local H = Config.Economy.Highway
local AREA_CONTEXT: ControlsController.Context = "Highway"
local ACTION = "HighwayThrow"
local REMOTE = "HighwayThrow"
local LAYER = "highwayThrow"
local LAYER_PRIORITY = Config.Anim.poses.throwWindup.priority or 2 -- ThrowController's throw layer's
local RIG_R15 = "R15"
local HIDE_REASON = "highwayThrow"
local HUD_GUI = "SD_Hud"
local CLIENT_FX = "SD_ClientFx"
local RELEASE = H.flight.releaseSeconds
local STAND_STILL = 0.1 -- Humanoid.MoveDirection below this: standing (ThrowMotion's legs)
local SILENT: { [string]: boolean } = { ["highway.inFlight"] = true, ["net.rateLimited"] = true }
local AUTO_CLICK = "highway.autoClick" -- the auto-clicker check's catch (AutoClickService.checkThrow)

-- Module table

local HighwayThrowController = {}

-- Private

-- Verification fix: the client-only surfaces, swappable in Edit-mode tests (useDeps).
local REAL_DEPS = {
	isClient = function(): boolean
		return Players.LocalPlayer ~= nil
	end,
	bindAction = ControlsController.bindAction,
	invoke = NetController.invokeAsync,
	showResult = NotifyController.showResult,
	toast = UIController.toast,
}
local deps: typeof(REAL_DEPS) = REAL_DEPS

local cleanup: Cleanup.Cleanup? = nil
local effect: Scheduler.Handle? = nil
local unbind: (() -> ())? = nil
local inArea = false
local current: Throw? = nil
local sent: { number } = {} -- os.clock of the presses sent during the own flights (the rolling second)
local pending: { [number]: number } = {} -- id -> os.clock of a sent press still unanswered
local nextPending = 0
local pill: WellPill.WellPill? = nil

local function rootPart(): BasePart?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function oldestPending(): number?
	local oldest: number? = nil
	for _, at in pending do
		if oldest == nil or at < oldest then
			oldest = at
		end
	end
	return oldest
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

local function setPill(text: string?)
	if text == nil then
		if pill then
			pill:destroy()
			pill = nil
		end
		return
	end
	if pill == nil then
		local made = WellPill.new({
			name = "HighwayDistance",
			look = Config.UI.Daily.timer,
			parent = UIController.screenGui(HUD_GUI),
		})
		made.root.AnchorPoint = Vector2.new(0.5, 0)
		made.root.Position = UDim2.new(0.5, 0, 0, U.pillTopPx)
		pill = made
	end
	(pill :: WellPill.WellPill):setText(text)
end

-- The hand: ThrowMotion's pose on the joint layer (R15), or the layer cleared (weight 0).
local function pose(degrees: { [string]: Vector3 }?, weight: number)
	local player = Players.LocalPlayer
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

-- Ends a throw's visuals (the model, the trail, the camera, the held toy, the hand, the pill).
local function finish(throw: Throw)
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
	local player = Players.LocalPlayer
	if player then
		HeldSquishyController.setHidden(player, HIDE_REASON, false)
	end
	pose(nil, 0)
	setPill(nil)
end

-- The release (where phase 14's A3 / A4 launcher clips would play): the model, the trail, the camera.
local function release(throw: Throw, now: number)
	local data = throw.data :: Types.HighwayResult
	throw.releasedAt = now
	local root = rootPart()
	local origin: CFrame = WorldLayout.Highway.origin
	local at = if root then origin:PointToObjectSpace(root.Position + Vector3.new(0, 1.5, 0)) else Vector3.zero
	local plan = table.clone(HighwayMath.flight(data.studs))
	plan.from = -at.Z -- from the hand: the server's times, the hand's distance
	throw.plan, throw.x0, throw.y0 = plan, at.X, at.Y
	local model = SquishyCache.clone(throw.kind, "World")
	model.Parent = clientFx()
	throw.model = model
	local body = model.PrimaryPart
	if body then
		local half = Vector3.new(0, U.trail.width / 2, 0) -- the trail is as wide as its two attachments are apart
		throw.trail = FxPool.default():acquireTrail(body, half, -half, {
			Lifetime = U.trail.lifetime,
			WidthScale = NumberSequence.new(1, 0),
			Color = ColorSequence.new(Color3.new(1, 1, 1)),
		})
	end
	local player = Players.LocalPlayer
	if player then
		HeldSquishyController.setHidden(player, HIDE_REASON, true)
	end
	if not Tweens.reducedMotion() then
		throw.camera = CameraController.save()
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CameraType = Enum.CameraType.Scriptable
			throw.eye = camera.CFrame.Position
			throw.look = camera.CFrame.Position + camera.CFrame.LookVector * U.follow.lookAhead
		end
	end
end

local function land(throw: Throw, now: number)
	throw.landed = true
	throw.doneAt = now + U.follow.holdSeconds
	for _, toast in HighwayThrowController.landingToasts(throw.data :: Types.HighwayResult) do
		deps.toast(toast.text, NotifyFormat.kindOf(toast.kind))
	end
	local trail = throw.trail
	if trail then
		FxPool.default():release(trail)
		throw.trail = nil
	end
	setPill(nil)
end

-- One throw's frame (see the header).
local function stepThrow(throw: Throw, dt: number, now: number)
	local data = throw.data
	-- The hand.
	if throw.releasedAt == nil then
		local u = math.clamp((now - throw.pressedAt) / RELEASE, 0, 1)
		pose(ThrowMotion.windup(throw.style, u, throw.legs), 1)
		if u >= 1 and data ~= nil then
			release(throw, now)
		end
		return
	end
	local handT = now - (throw.releasedAt :: number)
	if handT <= ThrowMotion.SETTLE then
		local fade = math.clamp((handT - ThrowMotion.FOLLOW) / (ThrowMotion.SETTLE - ThrowMotion.FOLLOW), 0, 1)
		pose(ThrowMotion.release(throw.style, handT, throw.legs), 1 - fade)
	else
		pose(nil, 0)
	end
	-- The flight, on the server's clock.
	local d = data :: Types.HighwayResult
	local plan = throw.plan :: HighwayMath.Flight
	local serverNow = Workspace:GetServerTimeNow()
	local t = serverNow - (d.landsAt - d.flight + RELEASE)
	local p = HighwayMath.at(plan, t, throw.x0, throw.y0)
	if not throw.landed and not Tweens.reducedMotion() then
		local rolling = t - plan.air
		throw.spin += dt * (if rolling < 0
			then U.spinAir
			else U.spinRoll * (1 - math.clamp(rolling / math.max(plan.roll, 1e-3), 0, 1)) + U.spinRollMin)
	end
	local model = throw.model
	if model then
		model:PivotTo(WorldLayout.highwayCFrame(p.X, p.Y, p.Z) * CFrame.Angles(-throw.spin, math.pi, 0))
	end
	if not throw.landed then
		setPill(HighwayThrowController.pillText(p.Z))
		if serverNow >= d.landsAt then
			land(throw, now)
		end
	end
	-- The follow camera (P3D:849).
	local camera = Workspace.CurrentCamera
	if throw.camera ~= nil and camera ~= nil and throw.eye ~= nil and throw.look ~= nil then
		local eyeGoal, lookGoal = HighwayThrowController.followGoal(p)
		local eye = (throw.eye :: Vector3):Lerp(eyeGoal, 1 - math.exp(-dt * U.follow.posRate))
		local look = (throw.look :: Vector3):Lerp(lookGoal, 1 - math.exp(-dt * U.follow.lookRate))
		throw.eye, throw.look = eye, look
		camera.CFrame = CFrame.lookAt(eye, look)
	end
	if throw.doneAt ~= nil and now >= throw.doneAt then
		finish(throw)
	end
end

-- The one effect (see the header).
local function step(dt: number, now: number): boolean
	local root = rootPart()
	local origin: CFrame = WorldLayout.Highway.origin
	local inside = root ~= nil and HighwayMath.inArea(origin:PointToObjectSpace(root.Position), 0)
	if inside ~= inArea then
		inArea = inside
		ControlsController.setContext(AREA_CONTEXT, inside)
	end
	local throw = current
	if throw then
		stepThrow(throw, dt, now)
	end
	return true
end

-- A new throw pressed at `now` (os.clock): the equipped squishy, the hand's style and legs.
local function newThrow(now: number): Throw
	local equipped = StateController.get("equipped")
	local kind = if type(equipped) == "string" and Catalog.get(equipped) ~= nil then equipped else Catalog.starterId()
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return {
		pressedAt = now,
		style = ThrowTracks.styleOf(kind),
		kind = kind,
		legs = humanoid ~= nil and humanoid.MoveDirection.Magnitude < STAND_STILL,
		spin = 0,
		x0 = 0,
		y0 = 0,
		landed = false,
	}
end

-- A press while the own throw flies, sent for the auto-clicker check (see the header).
local function forward(now: number)
	if not Config.Net.AutoClick.enabled then
		return
	end
	local cap = H.autoClick.clientPressesPerSecond
	if not HighwayThrowController.mayForward(sent, oldestPending(), now, cap, U.lateReplySeconds) then
		return
	end
	table.insert(sent, now)
	nextPending += 1
	local id = nextPending
	pending[id] = now
	task.spawn(function()
		local result = deps.invoke(REMOTE, Workspace:GetServerTimeNow())
		pending[id] = nil
		if cleanup == nil then
			return -- destroyed meanwhile
		end
		if result.ok and type(result.data) == "table" then
			-- Verification fix: it reached the server as the flight ended, so the server threw it (paid): show it, the
			-- old throw landing first.
			local old = current
			if old ~= nil then
				if old.data ~= nil and not old.landed then
					land(old, os.clock())
				end
				finish(old)
			end
			local throw = newThrow(now)
			throw.data = result.data
			current = throw
		elseif result.reason == AUTO_CLICK then
			deps.showResult(result) -- the 1st catch's calm warning (each catch answers it once)
		end
	end)
end

local function begin(now: number)
	-- Verification fix: a throw's first press counts toward the cap too (and keeps `sent` to the last second).
	if
		not HighwayThrowController.mayForward(sent, nil, now, H.autoClick.clientPressesPerSecond, U.lateReplySeconds)
	then
		return
	end
	local throw = newThrow(now)
	current = throw
	table.insert(sent, now)
	task.spawn(function()
		local result = deps.invoke(REMOTE, Workspace:GetServerTimeNow())
		if current ~= throw then
			return -- destroyed or replaced meanwhile
		end
		if result.ok and type(result.data) == "table" then
			throw.data = result.data
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
	local now = os.clock()
	local throw = current
	if throw ~= nil and not throw.landed then
		forward(now)
		return true
	end
	if throw ~= nil then
		finish(throw) -- the camera still holding after a landing: the next throw takes over
	end
	begin(now)
	return true
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

-- The follow camera's goal for a squishy at lane-local p = (x, y, d) (P3D:849): its eye and the point it looks at.
function HighwayThrowController.followGoal(p: Vector3): (Vector3, Vector3)
	local f = U.follow
	local eye = WorldLayout.highwayCFrame(p.X + f.side, p.Y + f.up, p.Z - f.back).Position
	local look = WorldLayout.highwayCFrame(p.X, p.Y + f.lookUp, p.Z + f.lookAhead).Position
	return eye, look
end

-- The landing's toasts (see the header).
function HighwayThrowController.landingToasts(data: Types.HighwayResult): { Toast }
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

-- The pill's text (see the header): the biome the squishy is over and its distance.
function HighwayThrowController.pillText(d: number): string
	local biome = WorldLayout.Highway.biomes[HighwayMath.biomeAt(d)]
	return Strings.format(
		Strings.highway.flying,
		{ biome = Strings.resolve(biome.nameKey) or "", distance = Format.distance(math.max(d, 0)) }
	)
end

function HighwayThrowController.debugState(): DebugState
	local throw = current
	local data = if throw then throw.data else nil
	return {
		started = cleanup ~= nil,
		inArea = inArea,
		throwing = throw ~= nil,
		landsAt = if data then data.landsAt else nil,
	}
end

-- Test seam (Edit mode): replaces some of the client-only surfaces (isClient, bindAction, invoke, showResult, toast;
-- nil = the real ones again).
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
		if inArea then
			inArea = false
			ControlsController.setContext(AREA_CONTEXT, false)
		end
		table.clear(sent)
		table.clear(pending)
		setPill(nil)
	end)
	if not deps.isClient() then
		return -- not a client (Edit-mode tests): no character to watch, nothing to throw
	end
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
