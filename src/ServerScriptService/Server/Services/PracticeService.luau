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
-- playerAdded/playerRemoving never yield. start() runs the session watcher.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local PracticeTargets = require(Shared.Practice.PracticeTargets)
local Signal = require(Shared.Util.Signal)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)
local CharacterService = require(script.Parent.CharacterService)
local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Stats = Types.DuelStats
export type TargetDef = PracticeTargets.TargetDef

type Session = {
	throws: number,
	hits: number,
}

-- Constants

local ZONE_TAG = WorldLayout.PracticeRange.zoneTag -- "SD_PracticeZone"
local RANGE_MODEL = WorldLayout.PracticeRange.model -- "PracticeRange"
local ATTR_MATCH_ID = "SD_MatchId"
-- Solid parts of the generated range that practice projectiles splat on (LobbyBuilder names). The targets are
-- cosmetic (their hitbox is the capsule) and the throw box is a volume, so neither is in the list.
local RANGE_GEOMETRY = { "LaneFloor", "FiringLine", "Backstop", "Hedge" }
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

-- Include lists of the range's solid parts, built once from the generated lobby (nil when it is not built).
local function buildRangeParams(): (RaycastParams?, OverlapParams?)
	local lobby = WorldService.lobby()
	local range = if lobby then lobby:FindFirstChild(RANGE_MODEL, true) else nil
	if range == nil then
		return nil, nil
	end
	local include: { Instance } = {}
	for _, name in RANGE_GEOMETRY do
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

-- Every practice target (frozen definitions from PracticeTargets).
function PracticeService.targets(): { TargetDef }
	return PracticeTargets.list()
end

-- True while the target is "down" after a hit (it cannot be hit again until then).
function PracticeService.isTargetDown(targetId: string, t: number): boolean
	local untilTime = downUntil[targetId]
	return untilTime ~= nil and t < untilTime
end

-- The target's hitbox at server time t: capsule axis (bottom, top) and radius (§5.5).
function PracticeService.capsuleAt(target: TargetDef, t: number): (Vector3, Vector3, number)
	return PracticeTargets.capsuleAt(target, t)
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
-- is not a throw, so it counts neither in the session stats nor for the quest (reading).
function PracticeService.registerHit(player: Player, targetId: string, t: number, fromLane: boolean?): boolean
	if PracticeTargets.get(targetId) == nil or PracticeService.isTargetDown(targetId, t) then
		return false
	end
	downUntil[targetId] = t + TARGET_DOWN_SECONDS
	if fromLane == true then
		PracticeService.TargetHit:fire(player, targetId, t, false)
		return true
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
	if rangeParams == nil and WorldService.lobby() ~= nil then
		log:warn(`no {RANGE_MODEL} geometry found in the lobby; practice projectiles only splat on the floor`)
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
	PracticeService.StatsChanged:disconnectAll()
	PracticeService.TargetHit:disconnectAll()
end

return PracticeService
