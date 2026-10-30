--!strict
-- PracticeService (server only). DESIGN §5.11, §7.6, §2.8 (StateDelta.practice), §12 #5, #12.
-- The practice range's server side. Throws use the duel's own remote, validator, cooldown, windup and ballistics
-- (CombatService handles ThrowRequest / UltimateRequest); this module answers the practice questions:
-- * isPracticing(p): the player's server HumanoidRootPart is inside the lobby's SD_PracticeZone volume (the throw box,
--   found through WorldService) and the player is not in a match (SD_MatchId ""). Nothing else ever counts as
--   practice, so practice throws happen only inside the zone (§12 #5).
-- * Targets: the 9 targets of Shared/Practice/PracticeTargets (built from WorldLayout.PracticeRange, the same data the
--   lobby generator used), never the lobby instances: the server is the authority on where a target is. The hitbox of a
--   target is the standard player capsule (PracticeTargets.capsuleAt). A hit target stays "down" for
--   Config.Combat.Practice.targetDownSeconds; a down target cannot be hit (projectiles pass through).
-- * Session stats (throws, hits, accuracy 0-100) per player, counted only from server-accepted throws and
--   server-confirmed hits; reset when the player leaves the zone or a match starts; never saved. StatsChanged fires on
--   every change, and init() hands every change to StateService.setSessionField(p, "practice", stats), which sends it
--   as StateDelta.practice (Part 5; StateService is a lower layer, so the call goes downward, §2.6).
-- * TargetHit fires on every confirmed hit with `countsForQuest` (each target counts at most once per
--   Config.Economy.Quests.practiceTargetRepeatSeconds per player) for the `practice_hits` quest (Part 7).
-- * Practice NEVER pays Coins, never gives ult charge and never counts toward duel stats (§5.11). Practice projectiles
--   only ever test practice targets, never players (§5.3, §12 #12).
-- * FULL FINAL lobby (owner 2026-10-30, "Yes, start step 4"): the range is Diego's PracticeArena (the sky island behind
--   the TARGET PRACTICE portal). start() reads its Target_* (the wheel's Target_W* too) and Dummy_* models into the
--   targets: a ball round each one's bullseye (Markers.Bull, else its Bullseye part; a dummy: its box centre) that
--   follows his motion on the server (HubFX.cframeAt, the clock every client animates with), radius half the target's
--   width (a dummy's widest half). Projectiles splat on his arena parts (ARENA_GEOMETRY). A confirmed throw hit is
--   scored by his PracticeRange.registerHit (rings by the distance from the bullseye across the target's face,
--   combos, 30 s rounds, his score board, the target's spin) and PracticeHit tells the thrower (points, callout,
--   combo, where), for the screen pop.
-- playerAdded/playerRemoving never yield. start() runs the session watcher.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local HubFX = require(Shared.SquishyLobby.HubFX)
local Log = require(Shared.Util.Log)
local PracticeRange = require(Shared.SquishyLobby.PracticeRange)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)
local CharacterService = require(script.Parent.CharacterService)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Stats = Types.DuelStats
export type TargetDef = PracticeTargets.TargetDef

type Session = {
	throws: number,
	hits: number,
}

-- One of Diego's arena targets: its def, its model, the animated model that carries it (a Pivot part, HubFX's), the
-- ball centre and the face normal in that model's rest pivot frame, and the ball's radius.
type ArenaTarget = {
	def: TargetDef,
	model: Model,
	anchor: Model?,
	rel: CFrame,
	normal: Vector3,
	radius: number,
	dummy: boolean,
}

-- Constants

local ZONE_TAG = WorldLayout.PracticeRange.zoneTag -- "SD_PracticeZone"
local ARENA_MODEL = "PracticeArena" -- Diego's arena, a child of the lobby
local ATTR_MATCH_ID = "SD_MatchId"
-- His arena's solid parts that practice projectiles splat on (his rbxmx folder names). His targets and dummies are hit
-- by their balls and the throw box is a volume, so none of those is in the list.
local ARENA_GEOMETRY = {
	"Floor", "Grout", "BackWall", "Counters", "CounterTops", "Barrier", "WheelPost", "SlideRails", "DummyPads",
	"Rails", "RailPosts", "ScoreBoard", "ScoreFrame", "WallTargets", "Crenels",
}
local THROW_LINE_Z = 14 -- the middle of his counter line (Z 13..15): a target's distance is measured from it
local REMOTE_HIT = "PracticeHit"
local WATCH_SECONDS = 0.5 -- how often sessions are checked for "left the zone" / "match started"
local TARGET_DOWN_SECONDS = Config.Combat.Practice.targetDownSeconds
local QUEST_REPEAT_SECONDS = Config.Economy.Quests.practiceTargetRepeatSeconds
local BROADCAST_STUDS = Config.Combat.Projectile.practiceBroadcastStuds

-- Module table

local PracticeService = {}

-- (player, stats) after every change of a session (a reset sends zeros).
PracticeService.StatsChanged = Signal.new() :: Signal.Signal<Player, Stats>
-- (player, targetId, hitTime, countsForQuest) for every server-confirmed target hit.
PracticeService.TargetHit = Signal.new() :: Signal.Signal<Player, string, number, boolean>

-- Private

local log = Log.new("Practice")
local sessions: { [Player]: Session } = {}
local downUntil: { [string]: number } = {} -- targetId -> server time
local lastQuestHit: { [Player]: { [string]: number } } = {}
local rangeParams: RaycastParams? = nil
local rangeOverlap: OverlapParams? = nil
local watching = false
local lobbyRef: Instance? = nil
local arenaList: { TargetDef } = {}
local arenaById: { [string]: ArenaTarget } = {}

local function accuracy(hits: number, throws: number): number
	if throws <= 0 then
		return 0
	end
	return math.floor(math.min(1, hits / throws) * 100 + 0.5)
end

local function snapshot(session: Session?): Stats
	if session == nil then
		return { throws = 0, hits = 0, accuracy = 0 }
	end
	return { throws = session.throws, hits = session.hits, accuracy = accuracy(session.hits, session.throws) }
end

local function inMatch(player: Player): boolean
	local matchId = player:GetAttribute(ATTR_MATCH_ID)
	return type(matchId) == "string" and matchId ~= ""
end

local function resetSession(player: Player)
	if sessions[player] == nil then
		return
	end
	sessions[player] = nil
	PracticeService.StatsChanged:fire(player, snapshot(nil))
end

-- Include lists of the arena's solid parts, built once from the lobby (nil when it has no arena).
local function buildRangeParams(): (RaycastParams?, OverlapParams?)
	local lobby = WorldService.lobby()
	local range = if lobby then lobby:FindFirstChild(ARENA_MODEL) else nil
	if range == nil then
		return nil, nil
	end
	local include: { Instance } = {}
	for _, name in ARENA_GEOMETRY do
		local child = range:FindFirstChild(name)
		if child then
			table.insert(include, child)
		end
	end
	if #include == 0 then
		return nil, nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = include
	params.CollisionGroup = "Default" -- the projectile rule of §5.3
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Include
	overlap.FilterDescendantsInstances = include
	overlap.CollisionGroup = "Default"
	return params, overlap
end

-- The nearest model at or above `m` that HubFX animates (it has a Pivot part; PracticeRange's animatedAncestor).
local function animatedAncestor(lobby: Instance, m: Instance?): Model?
	while m and m ~= lobby do
		if m:IsA("Model") and m:FindFirstChild("Pivot") then
			return m
		end
		m = m.Parent
	end
	return nil
end

-- Diego's targets and dummies (see the header), in name order.
local function buildArenaTargets(lobby: Instance)
	table.clear(arenaList)
	table.clear(arenaById)
	local arena = lobby:FindFirstChild(ARENA_MODEL)
	if arena == nil then
		return
	end
	local models: { Model } = {}
	for _, m in arena:GetDescendants() do
		if m:IsA("Model") and (string.match(m.Name, "^Target_") or string.match(m.Name, "^Dummy_")) then
			table.insert(models, m)
		end
	end
	table.sort(models, function(a: Model, b: Model): boolean
		return a.Name < b.Name
	end)
	for _, m in models do
		local dummy = string.match(m.Name, "^Dummy_") ~= nil
		local box, size = m:GetBoundingBox()
		local markers = m:FindFirstChild("Markers")
		local bull = markers and markers:FindFirstChild("Bull")
		local face = bull or m:FindFirstChild("Bullseye")
		local center = if not dummy and face and face:IsA("BasePart") then face.Position else box.Position
		-- a target faces the throwers (+Z), so its width is its face; the wheel's are scaled down to 0.72 (his scoreFor)
		local radius = if dummy then math.max(size.X, size.Z) / 2 else size.X / 2
		local anchor = animatedAncestor(lobby, m)
		local rest = if anchor then (anchor :: any).Pivot.CFrame else CFrame.identity
		local def: TargetDef = table.freeze({
			id = m.Name,
			distance = math.floor(THROW_LINE_Z - center.Z + 0.5),
			position = center,
			moving = anchor ~= nil,
			railLength = 0,
			period = 0,
		})
		table.insert(arenaList, def)
		arenaById[m.Name] = {
			def = def,
			model = m,
			anchor = anchor,
			rel = rest:ToObjectSpace(CFrame.new(center)),
			normal = rest:VectorToObjectSpace(Vector3.zAxis),
			radius = radius,
			dummy = dummy,
		}
	end
end

-- An arena target's ball centre and face normal at server time t (its rest values when nothing animates it).
local function arenaPose(at: ArenaTarget, t: number): (Vector3, Vector3)
	local lobby = lobbyRef
	if at.anchor == nil or lobby == nil then
		return at.def.position, Vector3.zAxis
	end
	local pose = HubFX.cframeAt(lobby, at.anchor :: Model, t - HubFX.EPOCH)
	return (pose * at.rel).Position, pose:VectorToWorldSpace(at.normal)
end

-- Where a hit lands on the target's face: the contact point moved onto the face's plane (Diego's rings measure the
-- distance from the bullseye across the face; a ball's contact point is a radius in front of it). Pure.
function PracticeService.onFace(hit: Vector3, center: Vector3, normal: Vector3): Vector3
	local n = if normal.Magnitude > 1e-6 then normal.Unit else Vector3.zAxis
	return hit - n * (hit - center):Dot(n)
end

local function watchSessions()
	for player in table.clone(sessions) do
		if player.Parent == nil or not PracticeService.isPracticing(player) then
			resetSession(player)
		end
	end
end

-- Public: context

-- True when the player's server HRP is inside the practice zone and the player is not in a match (§5.6 #3, §5.11).
function PracticeService.isPracticing(player: Player): boolean
	if inMatch(player) or not CharacterService.isAlive(player) then
		return false
	end
	local root = CharacterService.getRoot(player)
	if root == nil then
		return false
	end
	return WorldService.zoneAt(root.Position, ZONE_TAG) ~= nil
end

-- The practice zone as ThrowRules reads it ({cframe, size} of the lobby's SD_PracticeZone volume), or nil when the
-- lobby has none (then nothing counts as practice).
function PracticeService.zone(): Types.ArenaZone?
	local volume: Instance? = WorldService.stations(ZONE_TAG)[1]
	if volume == nil or not volume:IsA("BasePart") then
		return nil
	end
	return { cframe = volume.CFrame, size = volume.Size }
end

-- The range forward (throws go toward +X since phase 3), for the practice cone check (§5.6 #6).
function PracticeService.forward(): Vector3
	return PracticeTargets.FORWARD
end

-- The lane floor top (projectiles splat on it; shadow discs sit on it).
function PracticeService.floorY(): number
	return PracticeTargets.FLOOR_Y
end

-- True while a practice projectile is still inside the range (PracticeTargets.BOUNDS).
function PracticeService.inBounds(position: Vector3): boolean
	return PracticeTargets.inBounds(position)
end

-- The range's solid parts as a Default-group Include RaycastParams (nil when the lobby is not built).
function PracticeService.raycastParams(): RaycastParams?
	return rangeParams
end

-- The same parts as OverlapParams (spawn-overlap fizzle, Dragon Rush room check).
function PracticeService.overlapParams(): OverlapParams?
	return rangeOverlap
end

-- Players who should see a practice event at `position` (within Config.Combat.Projectile.practiceBroadcastStuds),
-- plus `always` (the thrower) even when farther away.
function PracticeService.audience(position: Vector3, always: Player?): { Player }
	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player == always then
			table.insert(list, player)
		else
			local root = CharacterService.getRoot(player)
			if root and (root.Position - position).Magnitude <= BROADCAST_STUDS then
				table.insert(list, player)
			end
		end
	end
	return list
end

-- Public: targets

-- Every practice target: Diego's arena targets once start() has read them, else the old range's (PracticeTargets).
function PracticeService.targets(): { TargetDef }
	return if #arenaList > 0 then arenaList else PracticeTargets.list()
end

-- True while the target is "down" after a hit (it cannot be hit again until then).
function PracticeService.isTargetDown(targetId: string, t: number): boolean
	local untilTime = downUntil[targetId]
	return untilTime ~= nil and t < untilTime
end

-- The target's hitbox at server time t: capsule axis (bottom, top) and radius (§5.5); an arena target's is its ball
-- (a capsule 0.02 tall).
function PracticeService.capsuleAt(target: TargetDef, t: number): (Vector3, Vector3, number)
	local at = arenaById[target.id]
	if at == nil then
		return PracticeTargets.capsuleAt(target, t)
	end
	local center = arenaPose(at, t)
	local half = Vector3.new(0, 0.01, 0)
	return center - half, center + half, at.radius
end

-- Public: stats

-- A server-accepted practice throw (counted when ThrowStarted is sent).
function PracticeService.registerThrow(player: Player)
	if not PracticeService.isPracticing(player) then
		return
	end
	local session = sessions[player]
	if session == nil then
		session = { throws = 0, hits = 0 }
		sessions[player] = session
	end
	session.throws += 1
	PracticeService.StatsChanged:fire(player, snapshot(session))
end

-- A server-confirmed hit of `targetId` at server time `t` by a projectile of `player`. Returns false (and changes
-- nothing) for an unknown or down target. Marks the target down, counts the hit in the thrower's session (if it is
-- still open) and fires TargetHit. `fromLane` = a Dragon Rush rehearsal lane (§5.11): the target reacts, but the hit
-- is not a throw, so it counts neither in the session stats nor for the quest (reading). An arena target's throw hit
-- at `position` (the projectile's contact point) is also scored (see the header).
function PracticeService.registerHit(
	player: Player,
	targetId: string,
	t: number,
	fromLane: boolean?,
	position: Vector3?
): boolean
	local at = arenaById[targetId]
	if (at == nil and PracticeTargets.get(targetId) == nil) or PracticeService.isTargetDown(targetId, t) then
		return false
	end
	downUntil[targetId] = t + TARGET_DOWN_SECONDS
	if fromLane == true then
		PracticeService.TargetHit:fire(player, targetId, t, false)
		return true
	end
	local lobby = lobbyRef
	if at and lobby and position then
		local center, normal = arenaPose(at, t)
		local onFace = if at.dummy then position else PracticeService.onFace(position, center, normal)
		local part = at.model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			local points, callout, combo = PracticeRange.registerHit(lobby, player, part, onFace)
			if points > 0 then
				NetService.fire(REMOTE_HIT, player, { points = points, callout = callout, combo = combo, position = position })
			end
		end
	end
	local session = sessions[player]
	if session then
		session.hits += 1
		PracticeService.StatsChanged:fire(player, snapshot(session))
	end
	local perTarget = lastQuestHit[player]
	if perTarget == nil then
		perTarget = {}
		lastQuestHit[player] = perTarget
	end
	local last = perTarget[targetId]
	local countsForQuest = last == nil or t - last >= QUEST_REPEAT_SECONDS
	if countsForQuest then
		perTarget[targetId] = t
	end
	PracticeService.TargetHit:fire(player, targetId, t, countsForQuest)
	return true
end

-- The player's current session stats (zeros without a session).
function PracticeService.stats(player: Player): Stats
	return snapshot(sessions[player])
end

-- Lifecycle

-- The session stats reach the owner's client as StateDelta.practice (§2.8, §11.6 practice panel).
function PracticeService.init()
	PracticeService.StatsChanged:connect(function(player: Player, stats: Stats)
		StateService.setSessionField(player, "practice", stats)
	end)
end

function PracticeService.start()
	rangeParams, rangeOverlap = buildRangeParams()
	local lobby = WorldService.lobby()
	if rangeParams == nil and lobby ~= nil then
		log:warn(`no {ARENA_MODEL} geometry found in the lobby; practice projectiles only splat on the floor`)
	end
	if lobby then
		lobbyRef = lobby
		buildArenaTargets(lobby)
	end
	if watching then
		return
	end
	watching = true
	while watching do
		task.wait(WATCH_SECONDS)
		local ok, err = pcall(function(): any
			watchSessions()
			return nil
		end)
		if not ok then
			log:error("session watch failed:", err)
		end
	end
end

function PracticeService.playerRemoving(player: Player)
	sessions[player] = nil
	lastQuestHit[player] = nil
end

-- Not called by the bootstrap; used by leak checks.
function PracticeService.destroy()
	watching = false
	table.clear(sessions)
	table.clear(lastQuestHit)
	table.clear(downUntil)
	table.clear(arenaList)
	table.clear(arenaById)
	lobbyRef = nil
	PracticeService.StatsChanged:disconnectAll()
	PracticeService.TargetHit:disconnectAll()
end

return PracticeService
