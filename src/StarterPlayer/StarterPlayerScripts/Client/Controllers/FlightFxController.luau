--!strict
-- FlightFxController (client only; 2026-10-28, the physics upgrade's part 3: squishies flying in duels; owner: "Yes,
-- build part 3"). The co-owner's Claude Design page docs/squishy-fx-spec/duelflight.html (numbers in Config.FlightFx),
-- added on top of the game's own throw, charge, miss and catch looks (Config.FlightFx's header says what is ported).
-- * flightShape (pure): a drawn throw tau s after its release: the release pop (squash keys divided by their last key,
--   so the game's own cruise stretch stays), the flight jiggle (scale) and the barrel spin (radians of roll), put on top
--   of its flight style by ProjectileRenderer. squashAt / wobbleAt: the design's squash tracks and wobbles (pure).
-- * release(thrower, from, velocity, charged): the release moment at the hand (ProjectileRenderer's release beat): the
--   puff and, for the own third-person throw, the camera kick (first person keeps Diego's kick).
-- * flying(model, root, still): a charged throw's gold halo and sparkle trail, stopped once still() is false (it touched
--   something, landed, hit or was caught) or the model is gone.
-- * bigBounce(model, root, floor, tint): a miss's floor contact from Config.FlightFx.bounce.bigFrom: BOING! and jelly
--   drops in the thrown squishy's colour (Anim/GroundBounce keeps its own dust, squash and sounds).
-- * The own charge (ThrowController.localCharge, every frame; other clients never see a charge start): the held
--   squishy's overlay "flightCharge" (chargeGrow x chargeJiggle, no jiggle under ReducedMotion; the first-person hands
--   mirror the own model's scale), the charge moment's sparkles and, at full, its "full" signal; in first person the
--   ready ring and sparkles go to the hands' toy (HeldSquishyController.mirrorFx) and MAX! to the screen. It ends with
--   the charge (a throw, a catch press, a cancel).
-- * Catches (CatchController.Caught / Burst, every client): the catch moment on the catcher's body (players only: a
--   bot's rig has no pose layer): the clamp, the jelly leaking, at the burst the release; the catcher's own screen
--   gets CAUGHT! and the camera absorb.
-- Off when Config.FlightFx.enabled is false.
-- API: squashAt, wobbleAt, flightShape, isCharged, bigFrom (pure); release, flying, bigBounce, debugState; init(),
--   destroy().

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Log = require(Shared.Util.Log)
local FLIGHT_FX = require(Shared.Config.FlightFx)

local Client = script.Parent.Parent
local FeelFx = require(Client.Anim.FeelFx)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local CatchController = require(script.Parent.CatchController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local MoveFxController = require(script.Parent.MoveFxController)
local ThrowController = require(script.Parent.ThrowController)

-- Constants

local SQUASHES = FLIGHT_FX.squashes
local WOBBLES = FLIGHT_FX.wobbles
local MOMENTS = FLIGHT_FX.moments
local OVERLAY = "flightCharge"
local CATCH_FORGET_SECONDS = 5 -- a catch whose burst never comes (the match ended) is forgotten
local TAU = 2 * math.pi

-- Module table

local FlightFxController = {}

-- Private state

type Charge = { run: any, start: number, full: boolean }
type Flight = { run: any, model: Model, root: BasePart, still: () -> boolean }

local log = Log.new("FlightFx")
local cleanup: Cleanup.Cleanup? = nil
local charge: Charge? = nil
local flights: { Flight } = {}
local catches: { [number]: any } = {} -- projId -> the catch's run
local stats = { releases = 0, charges = 0, fulls = 0, flights = 0, bounces = 0, catches = 0, bursts = 0 }
local debugCharge: { start: number, seconds: number }? = nil -- Studio (debugPlay "charge"): a charge with no throw
local debugSerial = 0

-- Pure -------------------------------------------------------------------------------------------------------------------

-- A squash track at `t` (squishy-fx.js squash): the key pair around t, eased by the earlier key's easing.
function FlightFxController.squashAt(def: any, t: number): Vector3
	local keys = def.keys
	local i = 1
	while i < #keys and t >= keys[i + 1][1] do
		i += 1
	end
	local a, b = keys[i], keys[math.min(i + 1, #keys)]
	local u = if a == b then 1 else FeelFx.ease(a[5], (t - a[1]) / (b[1] - a[1]))
	return Vector3.new(a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u, a[4] + (b[4] - a[4]) * u)
end

-- A wobble at `t` (squishy-fx.js wobble): X and Z x (1 + k), Y x (1 - k axisRatio); 1 outside [0, time].
function FlightFxController.wobbleAt(def: any, t: number): Vector3
	if t < 0 or t > def.time then
		return Vector3.one
	end
	local k = def.amplitude * math.exp(-def.decay * t) * math.sin(TAU * def.frequency * t)
	return Vector3.new(1 + k, 1 - k * def.axisRatio, 1 + k)
end

-- A drawn throw `tau` s after its release: (its scale multiplier in pivot space, its extra roll in radians).
function FlightFxController.flightShape(tau: number, charged: boolean): (Vector3, number)
	local def = if charged then SQUASHES.releaseStretchBig else SQUASHES.releaseStretch
	local last = def.keys[#def.keys]
	local t = math.max(tau, 0)
	local pop = FlightFxController.squashAt(def, t) / Vector3.new(last[2], last[3], last[4])
	local spin = math.rad(if charged then FLIGHT_FX.spin.charged else FLIGHT_FX.spin.tap) * t
	return pop * FlightFxController.wobbleAt(WOBBLES.flightJiggle, t), spin
end

-- Whether a throw's charge share (ThrowStarted's power) is the design's charged throw.
function FlightFxController.isCharged(power: number?): boolean
	return (power or 0) >= FLIGHT_FX.chargedFrom
end

-- The floor contact speed (studs/s) from which a miss's bounce is the big one.
function FlightFxController.bigFrom(): number
	return FLIGHT_FX.bounce.bigFrom
end

function FlightFxController.enabled(): boolean
	return FLIGHT_FX.enabled
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function rootOf(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- The run's own `call` events: first person's ready moment on the hands' toy.
local function onCall(name: string, _actor: any, _ev: any)
	if name == "readyMirror" then
		local m = FLIGHT_FX.mirror
		HeldSquishyController.mirrorFx("ring", 1, m.ring)
		HeldSquishyController.mirrorFx("sparkles", m.sparkles, m.sparkleColor)
	end
end

local function startCharge()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = rootOf(character)
	if character == nil or root == nil then
		return
	end
	local start = os.clock()
	local state: Charge = { run = nil, start = start, full = false }
	charge = state
	stats.charges += 1
	local reduced = Tweens.reducedMotion()
	HeldSquishyController.setOverlay(player, OVERLAY, {
		step = function(_dt: number, _now: number, _out: any): (Vector3, number, boolean)
			local t = os.clock() - start
			local s = FlightFxController.squashAt(SQUASHES.chargeGrow, t)
			if not reduced then
				s *= FlightFxController.wobbleAt(WOBBLES.chargeJiggle, t)
			end
			return s, 0, charge == state
		end,
	})
	state.run = FeelFx.play(
		MOMENTS.charge,
		MoveFxController.actorFor(player, character, root, {
			held = HeldSquishyController.getModel(player),
			call = onCall,
		}),
		FLIGHT_FX
	)
end

local function stepCharge()
	local c, _, full = ThrowController.localCharge()
	local fake = debugCharge
	if fake and c == nil then
		local t = os.clock() - fake.start
		if t < fake.seconds then
			c, full = math.min(t, 1), t >= 1
		else
			debugCharge = nil
		end
	end
	local state = charge
	if c ~= nil and state == nil then
		startCharge()
	elseif c == nil and state ~= nil then
		charge = nil -- the overlay goes on its next step
		if state.run then
			state.run:stop()
		end
	elseif state and full and not state.full then
		state.full = true
		stats.fulls += 1
		if state.run then
			state.run:signal("full")
		end
	end
end

local function stepFlights()
	local i = 1
	while i <= #flights do
		local f = flights[i]
		if f.model.Parent == nil or f.root.Parent == nil or not f.still() then
			f.run:stop()
			table.remove(flights, i)
		else
			i += 1
		end
	end
end

local function step(_dt: number, _now: number): boolean
	if not FLIGHT_FX.enabled then
		return true
	end
	local ok, err = pcall(stepCharge)
	if not ok then
		log:warn("charge step failed:", err)
	end
	ok, err = pcall(stepFlights)
	if not ok then
		log:warn("flight step failed:", err)
	end
	return true
end

local function onCaught(event: CatchController.Event)
	if not FLIGHT_FX.enabled then
		return
	end
	local catcher = Players:GetPlayerByUserId(event.catcherId)
	local character = catcher and catcher.Character
	local root = rootOf(character)
	if catcher == nil or character == nil or root == nil then
		return
	end
	local def: any = Catalog.get(event.squishyId)
	local accent = def and def.visuals and def.visuals.accent
	local run = FeelFx.play(
		MOMENTS.catch,
		MoveFxController.actorFor(catcher, character, root, {
			view = if catcher == Players.LocalPlayer then "R1P" else "OBS",
			tint = if type(accent) == "string" then Color3.fromHex(accent) else nil,
		}),
		FLIGHT_FX
	)
	local projId = event.projId
	catches[projId] = run
	stats.catches += 1
	task.delay(CATCH_FORGET_SECONDS, function()
		if catches[projId] == run then
			catches[projId] = nil
		end
	end)
end

local function onBurst(event: CatchController.Event)
	local run = catches[event.projId]
	catches[event.projId] = nil
	if run then
		stats.bursts += 1
		run:signal("burst")
	end
end

-- Public -------------------------------------------------------------------------------------------------------------------

-- The release moment at the hand (`from`), on the throw's first drawn frame.
function FlightFxController.release(thrower: Player?, from: Vector3, velocity: Vector3, charged: boolean)
	local character = thrower and thrower.Character
	local root = rootOf(character)
	if not FLIGHT_FX.enabled or thrower == nil or character == nil or root == nil then
		return
	end
	stats.releases += 1
	FeelFx.play(
		if charged then MOMENTS.releaseCharged else MOMENTS.release,
		MoveFxController.actorFor(thrower, character, root, { hitAt = from, dir = velocity }),
		FLIGHT_FX
	)
end

-- A charged throw's halo and sparkle trail while still() holds.
function FlightFxController.flying(model: Model, root: BasePart, still: () -> boolean)
	if not FLIGHT_FX.enabled then
		return
	end
	local actor: any = { character = model, root = root, own = false, view = "OBS", priority = -1 }
	table.insert(flights, { run = FeelFx.play(MOMENTS.chargedFlight, actor, FLIGHT_FX), model = model, root = root, still = still })
	stats.flights += 1
end

-- BOING! and jelly drops at `floor` (a miss's big bounce).
function FlightFxController.bigBounce(model: Model, root: BasePart, floor: Vector3, tint: Color3?)
	if not FLIGHT_FX.enabled then
		return
	end
	local actor: any = { character = model, root = root, own = false, view = "OBS", priority = -1, hitAt = floor, tint = tint }
	FeelFx.play(MOMENTS.missBig, actor, FLIGHT_FX)
	stats.bounces += 1
end

-- Studio (DebugHooks "flightFx"): one piece on the local player. "charge" (a charge with no throw for opts.seconds,
-- default 1.4: the puff-up, sparkles, full at 1 s), "release" (opts.charged), "bounce" (BOING! 8 studs ahead), "catch"
-- (a catch in the own hands, the burst after opts.burstAfter, default 1.02 s). opts.photoAt: the effects stand still
-- from then for opts.photoHold s (default 15), for a screen capture.
function FlightFxController.debugPlay(kind: string, opts: { [string]: any }?): (boolean, string?)
	local o: { [string]: any } = opts or {}
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = rootOf(character)
	if character == nil or root == nil then
		return false, "no character"
	end
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	if kind == "charge" then
		debugCharge = { start = os.clock(), seconds = if type(o.seconds) == "number" then o.seconds else 1.4 }
	elseif kind == "release" then
		local held = HeldSquishyController.getModel(player)
		local from = if held then held:GetPivot().Position else root.Position + flat * 1.5
		FlightFxController.release(player, from, flat * 100, o.charged == true)
	elseif kind == "bounce" then
		local ahead = root.Position + flat * 8
		local hit = Workspace:Raycast(ahead + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0))
		FlightFxController.bigBounce(character, root, if hit then hit.Position else ahead, MoveFxController.squishyTint(player))
	elseif kind == "catch" then
		debugSerial += 1
		local projId = -debugSerial -- never a server projId
		onCaught({ catcherId = player.UserId, projId = projId, squishyId = HeldSquishyController.getSquishyId(player) or "" } :: any)
		task.delay(if type(o.burstAfter) == "number" then o.burstAfter else 1.02, function()
			onBurst({ projId = projId } :: any)
		end)
	else
		return false, `unknown piece {kind}`
	end
	if type(o.photoAt) == "number" then
		task.delay(o.photoAt, function()
			FeelFx.freeze(if type(o.photoHold) == "number" then o.photoHold else 15, true)
		end)
	end
	return true, nil
end

function FlightFxController.debugState(): { [string]: any }
	return {
		enabled = FLIGHT_FX.enabled,
		charging = charge ~= nil,
		full = charge ~= nil and (charge :: Charge).full,
		flying = #flights,
		stats = table.clone(stats),
		feel = FeelFx.counts(),
	}
end

-- Lifecycle ----------------------------------------------------------------------------------------------------------------

function FlightFxController.init()
	local c = Cleanup.new()
	cleanup = c
	c:add(Scheduler.add(step, "render"))
	c:add(CatchController.Caught:connect(onCaught))
	c:add(CatchController.Burst:connect(onBurst))
	c:add(function()
		local state = charge
		charge = nil
		if state and state.run then
			state.run:stop()
		end
		for _, f in flights do
			f.run:stop()
		end
		table.clear(flights)
		table.clear(catches)
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by leak checks.
function FlightFxController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return FlightFxController
