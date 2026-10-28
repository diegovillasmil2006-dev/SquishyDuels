--!strict
-- HighwayFxController (client only; 2026-10-28, the physics upgrade's part 4: the highway throw; owner: "Yes, build part
-- 4"). The co-owner's Claude Design page docs/squishy-fx-spec/highway.html (numbers in Config.HighwayFx) on the own
-- highway throw, added on top of HighwayThrowController (Config.HighwayFx's header says what is ported). That module
-- calls this one at its beats with a per-throw State:
-- * windup(): at the press: the thrower's wind-up moment (sparkles drawn into the held squishy, the gold ring closing on
--   the feet, the movie bars) and the held squishy's windupSquish (a HeldSquishyController overlay).
-- * launch(state, model, plan, kind): at the release: the wind-up's "launch" (the floor shockwave and dust at the feet)
--   and the flight moment on the flying squishy (actor: lane space, the lane's forward, the zone's colour, its own
--   camera hooks); "sonic" when the landing is at least sonicFrom. A SquishDeformer on the flying model plays the
--   squash tracks (launchStretch, then the bounces and the stop) times the flightWobble: on the tumbling squishy the
--   design's up share goes to its axis nearest the world's up, the travel share to the one nearest the lane
--   (squashAxes, pure).
-- * clock(state, serverNow, dt): the drawn flight's clock. A slow motion (FeelFx.timeScale) holds it back; after it the
--   drawn clock runs catchUp x real time until it is back on the server's (lagStep, pure), so the landing and the boost
--   window stay the server's.
-- * flight(state, plan, at, inAir, drawnNow): the beats from the drawn path: "fast" (edge lines while the arc is faster
--   than fastFrom), "apex" per arc ("apexLong" the first time when the landing is at least hangFrom), "bounce1" when
--   the air ends ("impactBig" from impactFrom), "bounceN" at each hop of the roll, "lastBounce" and "roll" at its last
--   hop (hopAt, pure: HighwayMath.planAt's hops).
-- * zone(state, biome): "zoneExit", "zone", "zone_<id>" with the zone's colour (rings, sparkles, warp lines).
-- * land(state, studs): "stop" (the finish; the distance pop's text is the game's "{distance} studs!") and the hero
--   shot's start.
-- * camera(state, dt, fov0): this frame's camera turn (the shakes) and FOV (the kicks; the hero's FOV once landed);
--   hero(state, p, eye, look): the hero shot blended from the camera at the landing (Config.HighwayFx.hero).
-- * finish(state): every run stopped, the overlay and the deformer gone.
-- Off when Config.HighwayFx.enabled is false (windup returns nil and every call with a nil state does nothing).
-- API: lagStep, hopAt, squashAxes (pure); windup, launch, clock, flight, zone, land, camera, hero, finish, debugState.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)
local HIGHWAY_FX = require(Shared.Config.HighwayFx)

local Client = script.Parent.Parent
local FeelFx = require(Client.Anim.FeelFx)
local SquishDeformer = require(Client.Anim.SquishDeformer)
local Tweens = require(Client.Anim.Tweens)
local FlightFxController = require(script.Parent.FlightFxController)
local HeldSquishyController = require(script.Parent.HeldSquishyController)
local MoveFxController = require(script.Parent.MoveFxController)

-- Constants

local FX = HIGHWAY_FX
local MOMENTS = FX.moments
local SQUASHES = FX.squashes
local FLIGHT = Config.Economy.Highway.flight
local OVERLAY = "highwayWindup"
local LANE_TOP = 1 -- the lane's top in lane space (HighwayMath's LANE_Y, a local there)
local FLOOR_LIFT = 0.04
local DESIGN_RADIUS = 1.2 -- the design's squishy (CONFIG.highway.radius): pops sit over a squishy this big
local UP = Vector3.yAxis

-- Module table

local HighwayFxController = {}

-- Types

export type State = {
	windupRun: any,
	run: any?,
	actor: any?,
	model: Model?,
	deformer: any?,
	released: boolean,
	launchedAt: number,
	studs: number,
	accent: Color3?,
	squash: { def: any, start: number }?,
	arcSeen: number, -- the arcs whose apex was sent
	apexLong: boolean,
	inAir: boolean,
	hop: number, -- the roll's hop drawn last (-1 = still in the air)
	lastFast: number,
	lag: number,
	shakes: { { spec: any, age: number, phases: { number } } },
	kicks: { { spec: any, age: number } },
	heroAt: number?,
	heroEye: Vector3?,
	heroLook: Vector3?,
	stopped: boolean,
}

local log = Log.new("HighwayFx")
local stats = { windups = 0, launches = 0, zones = 0, bounces = 0, stops = 0, apexes = 0, fasts = 0, lagMax = 0 }
local rng = Random.new()
local live: State? = nil -- the throw in the air (Studio's debugSignal)

-- Pure -------------------------------------------------------------------------------------------------------------------

-- The drawn clock's lag behind the server's after `dt` real seconds at the effects' speed `scale`, and the drawn
-- clock's rate this frame: slowed below 1, catchUp x until the lag is gone, else 1.
function HighwayFxController.lagStep(lag: number, dt: number, scale: number, catchUp: number): (number, number)
	if scale < 1 - 1e-6 then
		return lag + dt * (1 - scale), scale
	end
	if lag > 0 and dt > 0 then
		local gained = dt * (catchUp - 1)
		if gained >= lag then
			return 0, 1 + lag / dt
		end
		return lag - gained, catchUp
	end
	return 0, 1
end

-- The roll's hop at distance d after the last arc's carry (HighwayMath.planAt's hops): (its index from 0, the hops);
-- (-1, 0) while still in the carry or with no roll.
function HighwayFxController.hopAt(carry: number, studs: number, d: number): (number, number)
	local rest = studs - carry
	if rest <= 0 or d < carry then
		return -1, 0
	end
	local hops = math.max(1, math.floor(rest / FLIGHT.hopEvery + 0.5))
	local length = rest / hops
	return math.clamp(math.floor((d - carry) / length), 0, hops - 1), hops
end

-- A design squash (x across, y up, z along the travel) in the pivot space of `pivot`: y on its axis nearest the world's
-- up, z on the remaining one nearest `travel`, x on the last.
function HighwayFxController.squashAxes(pivot: CFrame, travel: Vector3, s: Vector3): Vector3
	local axes = { pivot.XVector, pivot.YVector, pivot.ZVector }
	local up, best = 1, -1
	for i, axis in axes do
		local d = math.abs(axis:Dot(UP))
		if d > best then
			up, best = i, d
		end
	end
	local along, bestAlong = 0, -1
	for i, axis in axes do
		if i ~= up then
			local d = math.abs(axis:Dot(travel))
			if d > bestAlong then
				along, bestAlong = i, d
			end
		end
	end
	local out = { s.X, s.X, s.X }
	out[up] = s.Y
	out[along] = s.Z
	return Vector3.new(out[1], out[2], out[3])
end

-- Private ----------------------------------------------------------------------------------------------------------------

local function laneSpace(): CFrame
	return (WorldLayout.Highway.origin :: CFrame).Rotation
end

local function floorAt(at: Vector3): Vector3
	return WorldLayout.highwayCFrame(at.X, LANE_TOP + FLOOR_LIFT, at.Z).Position
end

local function rootOf(model: Model?): BasePart?
	local root = model and model.PrimaryPart
	return if root and root:IsA("BasePart") then root else nil
end

local function signal(state: State, name: string)
	local run = state.run
	if run then
		run:signal(name)
	end
end

local function startSquash(state: State, name: string)
	if not Tweens.reducedMotion() then
		state.squash = { def = SQUASHES[name], start = os.clock() }
	end
end

local function addShake(state: State, spec: any)
	local phases = {}
	for i = 1, 6 do
		phases[i] = rng:NextNumber() * 2 * math.pi
	end
	table.insert(state.shakes, { spec = spec, age = 0, phases = phases })
end

-- The flying model's squash this frame (pivot space).
local function stepShape(state: State)
	local deformer, model = state.deformer, state.model
	if deformer == nil or model == nil or model.Parent == nil then
		return
	end
	local s = Vector3.one
	local squash = state.squash
	if squash then
		local t = os.clock() - squash.start
		s = FlightFxController.squashAt(squash.def, t)
		if not squash.def.hold and t > squash.def.keys[#squash.def.keys][1] then
			state.squash = nil
			s = Vector3.one
		end
	end
	if not state.stopped then
		s *= FlightFxController.wobbleAt(FX.wobbles.flightWobble, os.clock() - state.launchedAt)
	end
	local ok, err = pcall(function()
		deformer:setScale(HighwayFxController.squashAxes(model:GetPivot(), laneSpace().LookVector, s))
	end)
	if not ok then
		log:warn("squash failed:", err)
		state.deformer = nil
	end
end

-- Public -------------------------------------------------------------------------------------------------------------------

function HighwayFxController.windup(): State?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not FX.enabled or player == nil or character == nil or root == nil or not root:IsA("BasePart") then
		return nil
	end
	stats.windups += 1
	local state: State = {
		windupRun = nil,
		run = nil,
		actor = nil,
		model = nil,
		deformer = nil,
		released = false,
		launchedAt = os.clock(),
		studs = 0,
		accent = MoveFxController.squishyTint(player),
		squash = nil,
		arcSeen = 0,
		apexLong = false,
		inAir = true,
		hop = -1,
		lastFast = -math.huge,
		lag = 0,
		shakes = {},
		kicks = {},
		heroAt = nil,
		heroEye = nil,
		heroLook = nil,
		stopped = false,
	}
	local start = os.clock()
	local reduced = Tweens.reducedMotion()
	HeldSquishyController.setOverlay(player, OVERLAY, {
		step = function(_dt: number, _now: number, _out: any): (Vector3, number, boolean)
			local s = if reduced then Vector3.one else FlightFxController.squashAt(SQUASHES.windupSquish, os.clock() - start)
			return s, 0, not state.released and not state.stopped
		end,
	})
	state.windupRun = FeelFx.play(
		MOMENTS.windup,
		MoveFxController.actorFor(player, character, root, { held = HeldSquishyController.getModel(player) }),
		FX
	)
	return state
end

-- The release: the flying `model` of squishy `kind` on `plan` (Types.HighwayPlan).
function HighwayFxController.launch(state: State?, model: Model?, plan: any, kind: string?)
	if state == nil then
		return
	end
	state.released = true
	state.windupRun:signal("launch")
	local root = rootOf(model)
	if model == nil or root == nil then
		return
	end
	stats.launches += 1
	state.model = model
	state.studs = plan.studs
	state.launchedAt = os.clock()
	local def: any = if kind then Catalog.get(kind) else nil
	local accent = def and def.visuals and def.visuals.accent
	if type(accent) == "string" then
		state.accent = Color3.fromHex(accent)
	end
	local ok, deformer = pcall(SquishDeformer.attach, model, { scaleMax = FX.scaleMax })
	state.deformer = if ok then deformer else nil
	local extents = model:GetExtentsSize()
	state.actor = {
		character = model,
		root = root,
		player = Players.LocalPlayer,
		own = true,
		priority = 1,
		dir = laneSpace().LookVector,
		space = laneSpace(),
		tint = FX.zones[1].color,
		floor = MoveFxController.floorColor(root),
		hitAt = floorAt(Vector3.new(0, 0, 0)),
		texts = {},
		popLift = math.max(extents.Y / 2 - DESIGN_RADIUS, 0),
		camera = {
			dip = function() end,
			punch = function() end,
			shake = function(spec: any)
				addShake(state, spec)
			end,
			fov = function(spec: any)
				table.insert(state.kicks, { spec = spec, age = 0 })
			end,
		},
	}
	state.run = FeelFx.play(MOMENTS.flight, state.actor, FX)
	live = state
	startSquash(state, "launchStretch")
	if plan.studs >= FX.sonicFrom then
		signal(state, "sonic")
	end
end

-- The drawn clock (see the header): (the drawn server time, the drawn clock's rate this frame).
function HighwayFxController.clock(state: State?, serverNow: number, dt: number): (number, number)
	if state == nil or not state.released then
		return serverNow, 1
	end
	local lag, rate = HighwayFxController.lagStep(state.lag, dt, FeelFx.timeScale(), FX.catchUp)
	state.lag = lag
	stats.lagMax = math.max(stats.lagMax, lag)
	return serverNow - lag, rate
end

-- One frame of the drawn flight: `at` lane space (x, y, d), `inAir` from HighwayMath.planAt at the drawn time.
function HighwayFxController.flight(state: State?, plan: any, at: Vector3, inAir: boolean, drawnNow: number)
	if state == nil or state.run == nil or state.stopped then
		return
	end
	local actor = state.actor
	actor.hitAt = floorAt(at)
	state.studs = plan.studs
	local arcs = plan.arcs
	local index = 1
	while arcs[index + 1] ~= nil and drawnNow >= arcs[index + 1].startAt do
		index += 1
	end
	local arc = arcs[index]
	if inAir then
		local u = (drawnNow - arc.startAt) / math.max(arc.air, 1e-3)
		if u >= 0.5 and index > state.arcSeen then
			state.arcSeen = index
			stats.apexes += 1
			signal(state, "apex")
			if not state.apexLong and plan.studs >= FX.hangFrom then
				state.apexLong = true
				signal(state, "apexLong")
			end
		end
		local speed = (arc.carry - arc.from) / math.max(arc.air, 1e-3)
		local now = os.clock()
		if speed >= FX.fastFrom and now - state.lastFast >= FX.fastLinesEvery then
			state.lastFast = now
			stats.fasts += 1
			signal(state, "fast")
		end
	elseif state.inAir then
		-- The air ends: the crater landing.
		state.inAir = false
		stats.bounces += 1
		actor.tint = state.accent -- the landing's jelly drops are the squishy's colour
		signal(state, "bounce1")
		if plan.studs >= FX.impactFrom then
			signal(state, "impactBig")
		end
		startSquash(state, "bounceSquashBig")
		local hop, hops = HighwayFxController.hopAt(arc.carry, plan.studs, at.Z)
		state.hop = math.max(hop, 0)
		if hops <= 1 then
			signal(state, "lastBounce")
			signal(state, "roll")
		end
	else
		local hop, hops = HighwayFxController.hopAt(arc.carry, plan.studs, at.Z)
		if hop > state.hop then
			state.hop = hop
			stats.bounces += 1
			signal(state, "bounceN")
			startSquash(state, "bounceSquashSmall")
			if hop == hops - 1 then
				signal(state, "lastBounce")
				signal(state, "roll")
			end
		end
	end
	stepShape(state)
end

-- The squishy drew into zone `biome` (1..7).
function HighwayFxController.zone(state: State?, biome: number)
	local zone = FX.zones[biome]
	if state == nil or state.actor == nil or zone == nil or state.stopped then
		return
	end
	stats.zones += 1
	state.actor.tint = zone.color
	signal(state, "zoneExit")
	signal(state, "zone")
	signal(state, "zone_" .. zone.id)
end

-- The stop (the drawn landing at `studs`).
function HighwayFxController.land(state: State?, studs: number)
	if state == nil or state.actor == nil or state.stopped then
		return
	end
	stats.stops += 1
	state.actor.texts.distancePop =
		Strings.format(Strings.highway.pop.landed, { distance = Format.distance(studs) })
	startSquash(state, "stopSquash")
	signal(state, "stop")
	state.stopped = true
	state.heroAt = os.clock()
	stepShape(state)
end

-- The camera's turn (shakes, a CFrame to put on the shot) and FOV this frame; `fov0` = the FOV before the throw.
function HighwayFxController.camera(state: State?, dt: number, fov0: number): (CFrame, number)
	if state == nil then
		return CFrame.identity, fov0
	end
	local turn = Vector3.zero
	for i = #state.shakes, 1, -1 do
		local s = state.shakes[i]
		s.age += dt
		if s.age >= s.spec.time then
			table.remove(state.shakes, i)
		else
			turn += FeelFx.shakeAt(s.spec, s.age, s.phases)
		end
	end
	local fov = fov0
	for i = #state.kicks, 1, -1 do
		local k = state.kicks[i]
		k.age += dt
		local s = k.spec
		if k.age >= s.attack + s.hold + s.release then
			table.remove(state.kicks, i)
		else
			fov += s.delta * FeelFx.envelope(k.age, s.attack, s.hold, s.release, s.attackEasing, s.releaseEasing)
		end
	end
	local heroAt = state.heroAt
	if heroAt then
		local hero = FX.hero
		fov += (hero.fov - fov0) * FeelFx.ease(hero.easing, (os.clock() - heroAt) / hero.time)
	end
	return CFrame.Angles(math.rad(turn.X), math.rad(turn.Y), math.rad(turn.Z)), fov
end

-- The hero shot once landed: (eye, look) blended from (eye, look) = where the camera was at the landing; nil before.
function HighwayFxController.hero(state: State?, p: Vector3, eye: Vector3, look: Vector3): (Vector3?, Vector3?)
	local heroAt = state and state.heroAt
	if state == nil or heroAt == nil then
		return nil, nil
	end
	local fromEye = state.heroEye or eye
	local fromLook = state.heroLook or look
	state.heroEye, state.heroLook = fromEye, fromLook
	local hero = FX.hero
	local goalEye = WorldLayout.highwayCFrame(p.X + hero.side, p.Y + hero.up, p.Z + hero.front).Position
	local goalLook = WorldLayout.highwayCFrame(p.X, p.Y, p.Z).Position
	local e = FeelFx.ease(hero.easing, (os.clock() - heroAt) / hero.time)
	return fromEye:Lerp(goalEye, e), fromLook:Lerp(goalLook, e)
end

function HighwayFxController.finish(state: State?)
	if state == nil then
		return
	end
	if live == state then
		live = nil
	end
	state.stopped = true
	state.released = true -- the wind-up overlay goes on its next step
	state.windupRun:stop()
	local run = state.run
	if run then
		run:stop()
	end
	local deformer = state.deformer
	state.deformer = nil
	if deformer then
		pcall(function()
			deformer:destroy()
		end)
	end
end

function HighwayFxController.debugState(): { [string]: any }
	local state = live
	return {
		enabled = FX.enabled,
		flying = state ~= nil,
		lag = if state then state.lag else 0,
		stats = table.clone(stats),
		feel = FeelFx.counts(),
		timeScale = FeelFx.timeScale(),
	}
end

-- Studio (DebugHooks "highwayFx"): a beat on the throw in the air, for the moments a Studio throw cannot reach (a
-- landing at 2,000+ studs needs gear): "zone<n>" (zone n's theme), "sonic", "apexLong", "fast", "impactBig".
function HighwayFxController.debugSignal(name: string): boolean
	local state = live
	if state == nil then
		return false
	end
	local n = tonumber(string.match(name, "^zone(%d)$"))
	if n then
		HighwayFxController.zone(state, n)
	else
		signal(state, name)
	end
	return true
end

return HighwayFxController
