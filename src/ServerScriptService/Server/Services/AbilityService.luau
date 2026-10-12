--!strict
-- AbilityService (server only). DESIGN §5.9, §9.10, §5.11, §12 #3, #7, #8; spec phase 5 (the four Epic ultimates).
-- Ultimates, keyed by the Catalog `ultimateId` (Config.Abilities). Each ability has a `kind` with its behaviour in
-- BEHAVIOURS: Dragon Rush is a telegraphed lane; Flock Volley, Sprinkle Roller, Rain Check and Bubble Pop are the
-- design's Epic ultimates (Config.Abilities header). Every kind shares the request gate, the charge, the root, cancel
-- and refund rules below; only the paths it checks before accepting and what it launches at the release differ.
-- * Charge is server-only: it starts at `startCharge` every match, grows by chargePerSecond in Active and SuddenDeath,
--   by chargePerHitLanded for each normal throw of the caster that hits, by chargePerLifeLost for each life the caster
--   loses, and is capped at chargeMax. Participants get UltimateCharge {ownerId, charge} at most
--   Config.Net.Broadcast.ultimateChargeMaxHz per caster; isReady(userId) feeds DuelState.ultReady.
-- * UltimateRequest(seq, aimDir, clientTime) (and the Studio test dummy, through requestUltimate), checked in §5.9
--   order: the match (brought up to the request time first, port.sync) is in Active/SuddenDeath and the caster's
--   server HRP stands inside its own half + Config.Combat.Throw.zoneToleranceStuds, the same place rule as a throw
--   (§5.6 #5, §12 #5; reading: §5.9 lists no position check, but without it a client that owns its physics could
--   start the lane from the neutral zone, past the cover that is the counterplay) (ult.context), the match snapshot
--   has the ultimate (ult.notReady), the charge is full and minIntervalSeconds passed since the last one, the caster
--   is not in a throw windup, a telegraph or its recovery (ult.notReady), alive with a server HRP (ult.context), the
--   aim flattened to horizontal keeps at
--   least minHorizontalAim (ult.direction). Then the kind's paths: a lane, the roller and the bubble start at
--   O = (HRP.X, floorY + laneHeightAboveFloor, HRP.Z) + dir × originForwardStuds; a sphere of `radius` overlapping
--   Geometry at O is ult.noRoom (no charge spent); E = the Spherecast end along dir (at most maxLength) against the
--   slot's Geometry, clamped to the arena Bounds. Flock Volley fans `count` birds over fanDeg from the same O, each
--   with its own E; Rain Check needs no room (its zone is placed at the release). A rejection is a
--   Notify(code) to the caster. clientTime is checked for shape only: the telegraph uses server time with no lag
--   compensation, so the opponent always sees it for telegraphSeconds minus their own latency.
-- * Accepted: the charge is spent, the caster is rooted (ThrowRules check 4, and WalkSpeed/JumpHeight 0 on the server)
--   until telegraphEndsAt + recoverySeconds, and UltimateEvent telegraph {casterId, ultimateId, origin, dir, length,
--   radius, telegraphEndsAt, speed} goes to both participants. At telegraphEndsAt the kind launches: the lane through
--   CombatService.launchLane (a gravity-0 sweep of `radius` from O to E at `speed`, the normal canDamage), the birds,
--   the roller and the bubble through CombatService.launchUlt (birds `staggerSeconds` apart), Rain Check's drops
--   through CombatService.launchArea around a centre on the opponent's spot at the release (clamped into its half;
--   practice: the target nearest the aim); UltimateEvent release carries the projId (lane, roller, bubble), the
--   `shots` (birds) or the `center` and `drops` (rain). A hit on the caster during the telegraph cancels it
--   (cancelOnHitDuringTelegraph): UltimateEvent cancel, refundOnCancel × chargeMax back, the root ends.
-- * Practice range (§5.11): an owner of the squishy may rehearse inside SD_PracticeZone with no charge and a
--   practiceCooldownSeconds cooldown; its hits reach practice targets only and the events go to nearby players.
--   Practice never gives charge. "A found match ends the session": attachMatch cancels a practice telegraph or
--   recovery of either player (UltimateEvent cancel, movement restored while they are still in the lobby), so a
--   practice root can never end inside the arena and unfreeze the Countdown.
-- Nothing the client sends is trusted for charge, timers, origin, length, targets or drop points (§12 #3).
-- Tests swap the clock, the sender, the scheduler and the two world queries with useDeps; setCharge fills a meter for
-- tests and Studio checks.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Types = require(Shared.Types)
local Validate = require(Shared.Util.Validate)
local HitMath = require(script.Parent.Parent.Logic.HitMath)
local UltRules = require(script.Parent.Parent.Logic.UltRules)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local InventoryService = require(script.Parent.InventoryService)
local NetService = require(script.Parent.NetService)
local PracticeService = require(script.Parent.PracticeService)

-- Types

type Fighter = CombatService.Fighter
type MatchPort = CombatService.MatchPort
type Zone = Types.ArenaZone

-- The Config.Abilities fields this module reads.
export type AbilityDef = {
	kind: string,
	chargeMax: number,
	startCharge: number,
	chargePerSecond: number,
	chargePerHitLanded: number,
	chargePerLifeLost: number,
	minIntervalSeconds: number,
	telegraphSeconds: number,
	radius: number,
	laneHeightAboveFloor: number,
	speed: number,
	maxLength: number,
	recoverySeconds: number,
	cancelOnHitDuringTelegraph: boolean,
	refundOnCancel: number,
	practiceCooldownSeconds: number,
	minHorizontalAim: number,
	originForwardStuds: number,
	count: number?,
	fanDeg: number?,
	staggerSeconds: number?,
	clearHeight: number?,
	splashRadius: number?,
	drops: number?,
	firstShadowSeconds: number?,
	dropStepSeconds: number?,
	shadowSeconds: number?,
	fallSeconds: number?,
	dropHitRadius: number?,
	dropRadii: { number }?,
	dropAngleStep: number?,
	targetRadius: number?,
}

type CasterPhase = "idle" | "telegraph" | "recovery"

-- One Flock Volley bird's path, found at the request.
type Shot = { dir: Vector3, length: number, stoppedByGeometry: boolean }

type Caster = {
	userId: number,
	player: Player?,
	fighter: Fighter?, -- duel caster
	port: MatchPort?,
	squishyId: string,
	ultimateId: string,
	ability: AbilityDef,
	charge: number,
	lastUltAt: number,
	lastSeq: number,
	phase: CasterPhase,
	token: number, -- bumped on cancel / detach so a pending release or recovery end does nothing
	event: Types.UltimateEventPayload?, -- the current telegraph (then release)
	stoppedByGeometry: boolean,
	shots: { Shot }?, -- Flock Volley: the birds' paths
	floorY: number, -- the floor of the current cast
	sentCharge: number,
	sentAt: number,
}

-- What the shared gate hands a kind: the place's floor, its world queries and its Bounds.
type CastContext = {
	floorY: number,
	raycastParams: RaycastParams?,
	overlapParams: OverlapParams?,
	bounds: Zone,
}

-- A kind's paths for the telegraph (prepare) and its projectiles at the release (launch).
type Prepared = { origin: Vector3, length: number, stoppedByGeometry: boolean, shots: { Shot }? }
type Behaviour = {
	prepare: (caster: Caster, ctx: CastContext, rootPosition: Vector3, dir: Vector3) -> (string?, Prepared?),
	launch: (caster: Caster, event: Types.UltimateEventPayload) -> Types.UltimateEventPayload,
}

-- What this module needs from the outside world (useDeps).
export type Deps = {
	now: () -> number,
	send: (remote: string, recipients: { any }, ...any) -> (),
	delay: (seconds: number, fn: (...any) -> (), ...any) -> (),
	-- True when a sphere of `radius` at `origin` overlaps the place's Geometry (GetPartBoundsInRadius).
	overlaps: (origin: Vector3, radius: number, params: OverlapParams) -> boolean,
	-- The distance at which a sphere of `radius` moved from `origin` along `direction` meets Geometry (Spherecast).
	cast: (origin: Vector3, radius: number, direction: Vector3, params: RaycastParams) -> number?,
}

-- Constants

local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local EPSILON = 1e-6
local CHARGE_TICK_SECONDS = 0.1 -- reading: how often charge grows; the broadcast is capped separately
local CHARGE_SEND_INTERVAL = 1 / Config.Net.Broadcast.ultimateChargeMaxHz
local MOVEMENT = Config.Duel.Rules.Movement
local ZONE_TOLERANCE = Config.Combat.Throw.zoneToleranceStuds -- own half + 2 studs, as for a throw (§5.6 #5)
local HALF_BY_SIDE: { [string]: string } = { A = "HalfA", B = "HalfB" }
local OTHER_SIDE: { [string]: string } = { A = "B", B = "A" }
local REASON_NOT_READY = "ult.notReady"
local REASON_CONTEXT = "ult.context"
local REASON_DIRECTION = "ult.direction"
local REASON_NO_ROOM = "ult.noRoom"
local REASON_INVALID = "net.invalid"
local REMOTE_ULTIMATE = "UltimateRequest"
-- build choice 2026-10-11 (NOT IN DESIGN): with no opponent spot (and no practice target ahead), Rain Check centres
-- this far along the aim.
local RAIN_FALLBACK_STUDS = Config.Combat.PowerBudget.referenceDistance

-- Module table

local AbilityService = {}

-- Private

local log = Log.new("Ability")
local duelCasters: { [number]: Caster } = {} -- userId -> caster (attached matches)
local practiceCasters: { [Player]: Caster } = {}
local attached: { [string]: MatchPort } = {}
local lastTick: number? = nil

local function defaultDeps(): Deps
	return {
		now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		send = function(remote: string, recipients: { any }, ...: any)
			NetService.fireMany(remote, recipients, ...)
		end,
		delay = function(seconds: number, fn: (...any) -> (), ...: any)
			task.delay(seconds, fn, ...)
		end,
		overlaps = function(origin: Vector3, radius: number, params: OverlapParams): boolean
			return #Workspace:GetPartBoundsInRadius(origin, radius, params) > 0
		end,
		cast = function(origin: Vector3, radius: number, direction: Vector3, params: RaycastParams): number?
			local hit = Workspace:Spherecast(origin, radius, direction, params)
			return if hit then hit.Distance else nil
		end,
	}
end

local deps: Deps = defaultDeps()

local function serverNow(): number
	return deps.now()
end

local function abilityOf(squishyId: string): (string?, AbilityDef?)
	local def = Catalog.get(squishyId)
	local id = if def then def.ultimateId else nil
	if id == nil then
		return nil, nil
	end
	local ability = (Config.Abilities :: any)[id]
	if ability == nil then
		return nil, nil
	end
	return id, ability :: AbilityDef
end

local function newCaster(
	userId: number,
	player: Player?,
	squishyId: string,
	ultimateId: string,
	ability: AbilityDef
): Caster
	return {
		userId = userId,
		player = player,
		fighter = nil,
		port = nil,
		squishyId = squishyId,
		ultimateId = ultimateId,
		ability = ability,
		charge = ability.startCharge,
		lastUltAt = -math.huge,
		lastSeq = 0,
		phase = "idle",
		token = 0,
		event = nil,
		stoppedByGeometry = false,
		shots = nil,
		floorY = 0,
		sentCharge = -1,
		sentAt = -math.huge,
	}
end

local function audience(caster: Caster, at: Vector3): { Player }
	local port = caster.port
	if port then
		local list: { Player } = {}
		for _, fighter in port.fighters do
			local player = fighter.player
			if player then
				table.insert(list, player)
			end
		end
		return list
	end
	return PracticeService.audience(at, caster.player)
end

-- The thrower state that holds rootedUntil / windupUntil for this caster.
local function throwerOf(caster: Caster): any
	if caster.fighter then
		return caster.fighter
	end
	local player = caster.player
	return if player then CombatService.practiceActor(player) else nil
end

local function rootPartOf(caster: Caster): BasePart?
	local fighter = caster.fighter
	if fighter then
		return fighter.getRoot()
	end
	local player = caster.player
	return if player then CharacterService.getRoot(player) else nil
end

local function isAlive(caster: Caster): boolean
	local fighter = caster.fighter
	if fighter then
		return fighter.isAlive()
	end
	local player = caster.player
	return player ~= nil and CharacterService.isAlive(player)
end

-- Server-side root while telegraphing and recovering (the client predicts the same, §9.10).
local function setRooted(caster: Caster, rooted: boolean)
	local root = rootPartOf(caster)
	local model = if root then root.Parent else nil
	local humanoid = if model then model:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil then
		return
	end
	humanoid.WalkSpeed = if rooted then 0 else MOVEMENT.WalkSpeed
	humanoid.JumpHeight = if rooted then 0 else MOVEMENT.JumpHeight
end

local function sendCharge(caster: Caster, now: number, force: boolean)
	local port = caster.port
	if port == nil then
		return
	end
	local shown = math.floor(caster.charge)
	if shown == caster.sentCharge or (not force and now - caster.sentAt < CHARGE_SEND_INTERVAL) then
		return
	end
	caster.sentCharge = shown
	caster.sentAt = now
	local payload: Types.UltimateChargePayload = { ownerId = caster.userId, charge = shown }
	deps.send("UltimateCharge", audience(caster, Vector3.zero), payload)
end

local function addCharge(caster: Caster, amount: number)
	caster.charge = math.clamp(caster.charge + amount, 0, caster.ability.chargeMax)
end

local function sendEvent(caster: Caster, event: Types.UltimateEventPayload)
	deps.send("UltimateEvent", audience(caster, event.origin), event)
end

-- A rejected request: the caster's client is told why. A payload failure is not answered; it counts as an abuse
-- violation instead (§12 #1; NetService already checked the types, so only a direct caller can get here).
local function reject(player: Player?, reason: string): (boolean, string?)
	if player and reason == REASON_INVALID then
		if typeof(player) == "Instance" and player:IsA("Player") then
			NetService.reportViolation(player, REMOTE_ULTIMATE)
		end
	elseif player then
		NetService.notify(player, reason, nil, "warn")
	end
	return false, reason
end

-- Ends a telegraph early (a hit on the caster, the match ending, a detach): UltimateEvent cancel, the root ends and
-- `refund` × chargeMax comes back.
local function cancel(caster: Caster, refund: number)
	if caster.phase ~= "telegraph" then
		return
	end
	caster.token += 1
	caster.phase = "idle"
	local thrower = throwerOf(caster)
	if thrower then
		thrower.rootedUntil = serverNow()
	end
	setRooted(caster, false)
	if caster.port then
		addCharge(caster, caster.ability.chargeMax * refund)
	end
	local event = caster.event
	if event then
		local cancelled = table.clone(event)
		cancelled.phase = "cancel"
		cancelled.projId = nil
		sendEvent(caster, cancelled)
	end
	caster.event = nil
end

local function endRecovery(caster: Caster, token: number)
	if caster.token ~= token or caster.phase ~= "recovery" then
		return
	end
	caster.phase = "idle"
	caster.event = nil
	setRooted(caster, false)
end

-- Private: the kinds ----------------------------------------------------------------------------------------------

-- A straight sweep's room and end (the Dragon Rush rule, §5.9): a sphere of `radius` overlapping Geometry at `origin`
-- is ult.noRoom (unless `room` is false: the later birds of a volley share the first one's start); the end is the
-- Spherecast distance along dir (at most maxLength), clamped to the Bounds.
local function sweepPath(
	ctx: CastContext,
	origin: Vector3,
	dir: Vector3,
	radius: number,
	maxLength: number,
	room: boolean
): (string?, number, boolean)
	local overlapParams = ctx.overlapParams
	if room and overlapParams and deps.overlaps(origin, radius, overlapParams) then
		return REASON_NO_ROOM, 0, false
	end
	local length = maxLength
	local stoppedByGeometry = false
	local raycastParams = ctx.raycastParams
	if raycastParams then
		local hit = deps.cast(origin, radius, dir * maxLength, raycastParams)
		if hit then
			length = hit
			stoppedByGeometry = true
		end
	end
	local clamped = AbilityService.clampToBounds(origin, dir, length, ctx.bounds)
	if clamped < length then
		length = clamped
		stoppedByGeometry = false
	end
	return nil, length, stoppedByGeometry
end

-- One straight sweep from O (Dragon Rush, the roller, the bubble).
local function prepareSweep(caster: Caster, ctx: CastContext, rootPosition: Vector3, dir: Vector3): (string?, Prepared?)
	local ability = caster.ability
	local origin = AbilityService.laneOrigin(rootPosition, ctx.floorY, dir, ability)
	local reason, length, stoppedByGeometry = sweepPath(ctx, origin, dir, ability.radius, ability.maxLength, true)
	if reason then
		return reason, nil
	end
	return nil, { origin = origin, length = length, stoppedByGeometry = stoppedByGeometry }
end

local function released(event: Types.UltimateEventPayload): Types.UltimateEventPayload
	local copy = table.clone(event)
	copy.phase = "release"
	return copy
end

-- An Epic ultimate's projectile along the telegraph's lane (the roller, the bubble).
local function launchAlong(caster: Caster, event: Types.UltimateEventPayload): number
	local ability = caster.ability
	return CombatService.launchUlt({
		caster = caster.fighter,
		player = caster.player,
		squishyId = caster.squishyId,
		origin = event.origin,
		direction = event.dir,
		length = event.length,
		radius = event.radius,
		speed = event.speed,
		releaseAt = event.telegraphEndsAt,
		stoppedByGeometry = caster.stoppedByGeometry,
		floorY = caster.floorY,
		flyOn = ability.kind == "roller",
		clearHeight = ability.clearHeight,
		splashRadius = ability.splashRadius,
	})
end

-- The opponent's server HRP and half (duel), or nil.
local function opponentOf(caster: Caster): (BasePart?, Zone?)
	local port, fighter = caster.port, caster.fighter
	if port == nil or fighter == nil then
		return nil, nil
	end
	local half = port.arena.zones[HALF_BY_SIDE[OTHER_SIDE[fighter.side] or ""] or ""]
	for _, other in port.fighters do
		if other ~= fighter then
			return other.getRoot(), half
		end
	end
	return nil, half
end

-- Rain Check at the release: the centre (the opponent's spot clamped into its half; practice: the target nearest the
-- aim) and its drops (design: fp.js:348-357).
local function rainDrops(caster: Caster, event: Types.UltimateEventPayload): (Vector3, { UltRules.Drop })
	local ability = caster.ability
	local floorY = caster.floorY
	local releaseAt = event.telegraphEndsAt
	local fallback = event.origin + event.dir * RAIN_FALLBACK_STUDS
	if caster.port then
		local root, half = opponentOf(caster)
		local spot = if root then root.Position else nil
		local center = UltRules.rainCenter(spot, fallback, half, floorY)
		local targets: { Vector3 } = {}
		if spot then
			table.insert(targets, UltRules.feetPoint(spot))
		end
		return center, UltRules.rainDrops(center, ability, releaseAt, targets)
	end
	local spots: { Vector3 } = {}
	for _, target in PracticeService.targets() do
		local bottom, _, radius = PracticeService.capsuleAt(target, releaseAt)
		table.insert(spots, bottom - Vector3.new(0, radius, 0))
	end
	local aimed = UltRules.practiceCenter(event.origin, event.dir, spots, ability.maxLength)
	local bounds = PracticeTargets.BOUNDS
	local zone = { cframe = CFrame.new(bounds.position), size = bounds.size }
	local center = UltRules.rainCenter(aimed, fallback, zone, floorY)
	return center, UltRules.rainDrops(center, ability, releaseAt, spots)
end

local BEHAVIOURS: { [string]: Behaviour } = {
	-- Dragon Rush (§5.9).
	lane = {
		prepare = prepareSweep,
		launch = function(caster: Caster, event: Types.UltimateEventPayload): Types.UltimateEventPayload
			local projId = CombatService.launchLane({
				caster = caster.fighter,
				player = caster.player,
				squishyId = caster.squishyId,
				origin = event.origin,
				direction = event.dir,
				length = event.length,
				radius = event.radius,
				speed = event.speed,
				releaseAt = event.telegraphEndsAt,
				stoppedByGeometry = caster.stoppedByGeometry,
			})
			local out = released(event)
			out.projId = projId
			return out
		end,
	},
	-- Flock Volley: `count` birds over fanDeg from one O, each cut at cover and the Bounds (design: ults.js:3).
	volley = {
		prepare = function(caster: Caster, ctx: CastContext, rootPosition: Vector3, dir: Vector3): (string?, Prepared?)
			local ability = caster.ability
			local origin = AbilityService.laneOrigin(rootPosition, ctx.floorY, dir, ability)
			local shots: { Shot } = {}
			local longest = 0
			for index, birdDir in UltRules.volleyDirs(dir, ability.count or 1, ability.fanDeg or 0) do
				local reason, length, stopped =
					sweepPath(ctx, origin, birdDir, ability.radius, ability.maxLength, index == 1)
				if reason then
					return reason, nil
				end
				table.insert(shots, { dir = birdDir, length = length, stoppedByGeometry = stopped })
				longest = math.max(longest, length)
			end
			return nil, { origin = origin, length = longest, stoppedByGeometry = false, shots = shots }
		end,
		launch = function(caster: Caster, event: Types.UltimateEventPayload): Types.UltimateEventPayload
			local ability = caster.ability
			local out = released(event)
			local shots: { Types.UltimateShot } = {}
			local paths: { Shot } = caster.shots or {}
			for index, shot in paths do
				local releaseAt = event.telegraphEndsAt + (ability.staggerSeconds or 0) * (index - 1)
				local projId = CombatService.launchUlt({
					caster = caster.fighter,
					player = caster.player,
					squishyId = caster.squishyId,
					origin = event.origin,
					direction = shot.dir,
					length = shot.length,
					radius = ability.radius,
					speed = ability.speed,
					releaseAt = releaseAt,
					stoppedByGeometry = shot.stoppedByGeometry,
					floorY = caster.floorY,
				})
				table.insert(shots, {
					projId = projId,
					origin = event.origin,
					dir = shot.dir,
					length = shot.length,
					releaseAt = releaseAt,
				})
			end
			out.shots = shots
			return out
		end,
	},
	-- Sprinkle Roller: one lane along the floor, flying on, jumpable (design: ults.js:4).
	roller = {
		prepare = prepareSweep,
		launch = function(caster: Caster, event: Types.UltimateEventPayload): Types.UltimateEventPayload
			local out = released(event)
			out.projId = launchAlong(caster, event)
			return out
		end,
	},
	-- Bubble Pop: one bubble that pops at its first contact, cover or after popSeconds (design: ults.js:6).
	bubble = {
		prepare = prepareSweep,
		launch = function(caster: Caster, event: Types.UltimateEventPayload): Types.UltimateEventPayload
			local out = released(event)
			out.projId = launchAlong(caster, event)
			return out
		end,
	},
	-- Rain Check: no room needed; the zone and its drops are placed at the release (design: ults.js:5).
	rain = {
		prepare = function(caster: Caster, ctx: CastContext, rootPosition: Vector3, dir: Vector3): (string?, Prepared?)
			local origin = Vector3.new(rootPosition.X, ctx.floorY, rootPosition.Z)
				+ dir * caster.ability.originForwardStuds
			return nil, { origin = origin, length = 0, stoppedByGeometry = false }
		end,
		launch = function(caster: Caster, event: Types.UltimateEventPayload): Types.UltimateEventPayload
			local ability = caster.ability
			local center, drops = rainDrops(caster, event)
			local out = released(event)
			local list: { Types.UltimateDrop } = {}
			for _, drop in drops do
				local projId = CombatService.launchArea({
					caster = caster.fighter,
					player = caster.player,
					squishyId = caster.squishyId,
					position = drop.position,
					radius = ability.dropHitRadius or 0,
					at = drop.landAt,
					floorY = caster.floorY,
				})
				table.insert(list, {
					projId = projId,
					position = drop.position,
					shadowAt = drop.shadowAt,
					landAt = drop.landAt,
				})
			end
			out.center = center
			out.drops = list
			return out
		end,
	},
}

local function release(caster: Caster, token: number)
	if caster.token ~= token or caster.phase ~= "telegraph" then
		return
	end
	local event = caster.event
	if event == nil then
		return
	end
	local port = caster.port
	if port ~= nil then
		local sync = port.sync
		if sync then
			sync(serverNow()) -- the match's timers first: a match that just ran out of time gets no lane
		end
		if caster.token ~= token or caster.phase ~= "telegraph" then
			return -- that tick cancelled or detached this caster
		end
		if not LIVE_PHASES[port.phase()] then
			cancel(caster, 0) -- the match ended during the telegraph: no lane, no refund
			return
		end
	end
	caster.phase = "recovery"
	local behaviour = BEHAVIOURS[caster.ability.kind] or BEHAVIOURS.lane
	local out = behaviour.launch(caster, event)
	caster.event = out
	sendEvent(caster, out)
	deps.delay(caster.ability.recoverySeconds, endRecovery, caster, token)
end

local function onHit(info: CombatService.HitInfo)
	local attacker = duelCasters[info.attacker.userId]
	if attacker and info.kind == "throw" then
		addCharge(attacker, attacker.ability.chargePerHitLanded)
	end
	local victim = duelCasters[info.victim.userId]
	if victim then
		if victim.phase == "telegraph" and victim.ability.cancelOnHitDuringTelegraph then
			cancel(victim, victim.ability.refundOnCancel)
		end
		addCharge(victim, victim.ability.chargePerLifeLost)
	end
end

local function tick()
	local now = serverNow()
	local previous = lastTick
	lastTick = now
	local dt = if previous then math.clamp(now - previous, 0, 1) else 0
	for _, caster in duelCasters do
		local port = caster.port
		if port and LIVE_PHASES[port.phase()] then
			addCharge(caster, caster.ability.chargePerSecond * dt)
		end
		sendCharge(caster, now, false)
	end
end

-- Public: pure helpers (unit-tested) -----------------------------------------------------------------------------------

-- The aim flattened to horizontal (unit), or nil when its horizontal part is shorter than minHorizontal (§5.9).
function AbilityService.flatAim(aimDir: Vector3, minHorizontal: number): Vector3?
	local flat = Vector3.new(aimDir.X, 0, aimDir.Z)
	local magnitude = flat.Magnitude
	if magnitude < minHorizontal or magnitude < EPSILON then
		return nil
	end
	return flat / magnitude
end

-- The lane start O: above the caster's HRP at floorY + laneHeightAboveFloor, moved originForwardStuds along dir.
function AbilityService.laneOrigin(rootPosition: Vector3, floorY: number, dir: Vector3, ability: AbilityDef): Vector3
	return Vector3.new(rootPosition.X, floorY + ability.laneHeightAboveFloor, rootPosition.Z)
		+ dir * ability.originForwardStuds
end

-- True when a duel caster's HRP at rootPosition may start a lane: inside its own half (`zones` HalfA for side "A",
-- HalfB for "B") widened by Config.Combat.Throw.zoneToleranceStuds, the throw rule of §5.6 #5. False without the zone.
function AbilityService.castFromOwnHalf(rootPosition: Vector3, zones: { [string]: Zone }, side: string): boolean
	local half = zones[HALF_BY_SIDE[side] or ""]
	return half ~= nil and HitMath.inZone(rootPosition, half, ZONE_TOLERANCE)
end

-- The longest distance (<= length) along the horizontal `dir` from `origin` that stays inside the box `zone` (X and Z
-- only: the lane flies at a fixed height). 0 when the origin is already outside.
function AbilityService.clampToBounds(origin: Vector3, dir: Vector3, length: number, zone: Zone): number
	local localOrigin = zone.cframe:PointToObjectSpace(origin)
	local localDir = zone.cframe:VectorToObjectSpace(dir)
	local half = zone.size / 2
	if math.abs(localOrigin.X) > half.X or math.abs(localOrigin.Z) > half.Z then
		return 0
	end
	local best = length
	for _, axis in { "X", "Z" } do
		local o = if axis == "X" then localOrigin.X else localOrigin.Z
		local d = if axis == "X" then localDir.X else localDir.Z
		local h = if axis == "X" then half.X else half.Z
		if math.abs(d) > EPSILON then
			local limit = ((if d > 0 then h else -h) - o) / d
			best = math.min(best, limit)
		end
	end
	return math.max(0, best)
end

-- Public: matches -----------------------------------------------------------------------------------------------------

-- A found match ends a practice session (§5.11): a practice ultimate in its telegraph is cancelled (UltimateEvent
-- cancel to the range), one in its recovery just ends; either way the root ends now, while the player is still in the
-- lobby (Preparing), and no pending release or recovery end can touch the player later.
local function endPractice(player: Player?)
	local caster = if player then practiceCasters[player] else nil
	if caster == nil or caster.phase == "idle" then
		return
	end
	if caster.phase == "telegraph" then
		cancel(caster, 0)
		return
	end
	caster.token += 1
	caster.phase = "idle"
	caster.event = nil
	local thrower = throwerOf(caster)
	if thrower then
		thrower.rootedUntil = serverNow()
	end
	setRooted(caster, false)
end

-- Starts tracking the ultimates of a registered match (DuelService, after CombatService.registerMatch).
function AbilityService.attachMatch(port: MatchPort)
	attached[port.matchId] = port
	for _, fighter in port.fighters do
		endPractice(fighter.player)
	end
	for _, fighter in port.fighters do
		local id, ability = abilityOf(fighter.squishyId)
		if id and ability and BEHAVIOURS[ability.kind] then
			local caster = newCaster(fighter.userId, fighter.player, fighter.squishyId, id, ability)
			caster.fighter = fighter
			caster.port = port
			duelCasters[fighter.userId] = caster
			sendCharge(caster, serverNow(), true)
		end
	end
end

-- Stops tracking a match: a pending telegraph is cancelled (no refund), a pending release or recovery does nothing.
function AbilityService.detachMatch(matchId: string)
	local port = attached[matchId]
	if port == nil then
		return
	end
	attached[matchId] = nil
	for userId, caster in table.clone(duelCasters) do
		if caster.port == port then
			cancel(caster, 0)
			caster.token += 1
			if caster.phase == "recovery" then
				caster.phase = "idle"
				setRooted(caster, false)
			end
			duelCasters[userId] = nil
		end
	end
end

-- True when this participant's ultimate can be used now (DuelState.ultReady).
function AbilityService.isReady(userId: number): boolean
	local caster = duelCasters[userId]
	if caster == nil then
		return false
	end
	return caster.phase == "idle"
		and caster.charge >= caster.ability.chargeMax
		and serverNow() >= caster.lastUltAt + caster.ability.minIntervalSeconds
end

-- The current charge of a participant (nil without an ultimate).
function AbilityService.chargeOf(userId: number): number?
	local caster = duelCasters[userId]
	return if caster then caster.charge else nil
end

-- Tests and Studio checks (a full meter to try an ultimate at once, e.g. from the server command bar in Play):
-- sets a participant's charge, clamped to 0..chargeMax, and sends it. False without one.
function AbilityService.setCharge(userId: number, charge: number): boolean
	local caster = duelCasters[userId]
	if caster == nil or type(charge) ~= "number" or charge ~= charge then
		return false
	end
	caster.charge = math.clamp(charge, 0, caster.ability.chargeMax)
	sendCharge(caster, serverNow(), true)
	return true
end

-- Public: requests ----------------------------------------------------------------------------------------------------

-- Validates and starts an ultimate (§5.9). `who` is the Player (UltimateRequest) or a registered fighter / its userId
-- (the Studio test dummy). Returns (accepted, reason?).
function AbilityService.requestUltimate(
	who: any,
	seq: unknown,
	aimDir: unknown,
	clientTime: unknown
): (boolean, string?)
	local now = serverNow()
	local fighter = CombatService.getFighter(who)
	local player: Player? = if fighter
		then fighter.player
		elseif typeof(who) == "Instance" and who:IsA("Player") then who
		else nil

	local validSeq = Validate.integer(seq)
	local aim = Validate.vector3(aimDir)
	if validSeq == nil or aim == nil or Validate.serverTime(clientTime) == nil then
		return reject(player, REASON_INVALID)
	end

	-- Context: a live match, or the practice range.
	local caster: Caster
	local ctx: CastContext
	if fighter then
		local port = CombatService.portOf(fighter)
		local sync = if port then port.sync else nil
		if sync then
			sync(now) -- the match's timers first, so the phase below is the one at the request time
		end
		local found = duelCasters[fighter.userId]
		if port == nil or not LIVE_PHASES[port.phase()] then
			return reject(player, REASON_CONTEXT)
		end
		-- Own half + tolerance, like a throw (§5.6 #5): the lane never starts past the opponent's cover.
		local ownRoot = fighter.getRoot()
		if ownRoot and not AbilityService.castFromOwnHalf(ownRoot.Position, port.arena.zones, fighter.side) then
			return reject(player, REASON_CONTEXT)
		end
		if found == nil then
			return reject(player, REASON_NOT_READY) -- the match snapshot has no ultimate
		end
		caster = found
		local zone = port.arena.zones.Bounds
		if zone == nil then
			return reject(player, REASON_CONTEXT)
		end
		ctx = {
			floorY = port.arena.floorY,
			raycastParams = port.arena.raycastParams,
			overlapParams = port.arena.overlapParams,
			bounds = zone,
		}
	elseif player and PracticeService.isPracticing(player) then
		local squishyId = InventoryService.getEquipped(player)
		local id, ability = abilityOf(squishyId)
		if id == nil or ability == nil or BEHAVIOURS[ability.kind] == nil then
			return reject(player, REASON_NOT_READY)
		end
		local found = practiceCasters[player]
		if found == nil or found.squishyId ~= squishyId then
			found = newCaster(player.UserId, player, squishyId, id, ability)
			practiceCasters[player] = found
		end
		caster = found
		ctx = {
			floorY = PracticeService.floorY(),
			raycastParams = PracticeService.raycastParams(),
			overlapParams = PracticeService.overlapParams(),
			bounds = { cframe = CFrame.new(PracticeTargets.BOUNDS.position), size = PracticeTargets.BOUNDS.size },
		}
	else
		return reject(player, REASON_CONTEXT)
	end

	if validSeq <= caster.lastSeq then
		return false, REASON_INVALID -- a replay: dropped silently
	end
	caster.lastSeq = validSeq

	-- Readiness: charge (duel) or the practice cooldown, the minimum interval, no windup / telegraph / recovery.
	local ability = caster.ability
	local thrower = throwerOf(caster)
	if caster.port then
		if caster.charge < ability.chargeMax or now < caster.lastUltAt + ability.minIntervalSeconds then
			return reject(player, REASON_NOT_READY)
		end
	elseif now < caster.lastUltAt + ability.practiceCooldownSeconds then
		return reject(player, REASON_NOT_READY)
	end
	if caster.phase ~= "idle" or (thrower and (now < thrower.rootedUntil or now < thrower.windupUntil)) then
		return reject(player, REASON_NOT_READY)
	end
	local root = rootPartOf(caster)
	if root == nil or not isAlive(caster) then
		return reject(player, REASON_CONTEXT)
	end
	local dir = AbilityService.flatAim(aim, ability.minHorizontalAim)
	if dir == nil then
		return reject(player, REASON_DIRECTION)
	end

	-- The kind's paths: room at O, then E (Spherecast against Geometry without Barriers, clamped to Bounds).
	local behaviour = BEHAVIOURS[ability.kind]
	local reason, prepared = behaviour.prepare(caster, ctx, root.Position, dir)
	if reason or prepared == nil then
		return reject(player, reason or REASON_NO_ROOM)
	end

	-- Accept: spend, root, telegraph.
	local telegraphEndsAt = now + ability.telegraphSeconds
	if caster.port then
		caster.charge = 0
	end
	caster.lastUltAt = now
	caster.phase = "telegraph"
	caster.token += 1
	caster.stoppedByGeometry = prepared.stoppedByGeometry
	caster.shots = prepared.shots
	caster.floorY = ctx.floorY
	if thrower then
		thrower.rootedUntil = telegraphEndsAt + ability.recoverySeconds
	end
	setRooted(caster, true)
	local event: Types.UltimateEventPayload = {
		phase = "telegraph",
		casterId = caster.userId,
		ultimateId = caster.ultimateId,
		projId = nil,
		origin = prepared.origin,
		dir = dir,
		length = prepared.length,
		radius = ability.radius,
		telegraphEndsAt = telegraphEndsAt,
		speed = ability.speed,
	}
	caster.event = event
	sendEvent(caster, event)
	sendCharge(caster, now, true)
	deps.delay(ability.telegraphSeconds, release, caster, caster.token)
	return true, nil
end

-- Swaps the clock, the sender, the scheduler and the world queries (tests). Missing fields keep the live default;
-- nil restores every default.
function AbilityService.useDeps(newDeps: {
	now: (() -> number)?,
	send: ((remote: string, recipients: { any }, ...any) -> ())?,
	delay: ((seconds: number, fn: (...any) -> (), ...any) -> ())?,
	overlaps: ((origin: Vector3, radius: number, params: OverlapParams) -> boolean)?,
	cast: ((origin: Vector3, radius: number, direction: Vector3, params: RaycastParams) -> number?)?,
}?)
	local base = defaultDeps()
	if newDeps then
		base.now = newDeps.now or base.now
		base.send = newDeps.send or base.send
		base.delay = newDeps.delay or base.delay
		base.overlaps = newDeps.overlaps or base.overlaps
		base.cast = newDeps.cast or base.cast
	end
	deps = base
end

-- Lifecycle

function AbilityService.init()
	NetService.on("UltimateRequest", function(player: Player, seq: any, aimDir: any, clientTime: any)
		AbilityService.requestUltimate(player, seq, aimDir, clientTime)
	end)
	CombatService.Hit:connect(onHit)
end

function AbilityService.start()
	while true do
		task.wait(CHARGE_TICK_SECONDS)
		local ok, err = pcall(function(): any
			tick()
			return nil
		end)
		if not ok then
			log:error("charge tick failed:", err)
		end
	end
end

function AbilityService.playerRemoving(player: Player)
	local caster = practiceCasters[player]
	if caster then
		caster.token += 1
		practiceCasters[player] = nil
	end
end

return AbilityService
