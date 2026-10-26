--!strict
-- MatchBotService (server only). The MATCH BOTS of Free for All / Team Deathmatch (owner 2026-10-17; the 1v1 practice
-- bot is BotService's). Numbers: Config.Match.Bots (Config/MatchBots, [P]; checked at init by Config/ValidateMatchBots
-- and, for the aim, reaction and name numbers they share with the practice bot, Config/ValidateBots: any problem keeps
-- the match bots off); decisions: Logic/MatchBotRules, plus the practice bot's actions (BotService's kit: BotRules'
-- reaction times, aim and dodge direction).
-- * Filling: init hands MatchService its bots (MatchService.attachBots). ready() once a plain Roblox character (the
--   default HumanoidDescription, BotService.buildRigAsync) is built (once at start, again every rigRetrySeconds until it
--   works) and nothing is closing; take(modeId, count) clones it `count` times into BotService bots (BotService.newBot:
--   a random real-looking name, a random catalog squishy, the practice bot's look and clips, held anchored out of
--   sight); MatchService puts them in the match in the same frame (its header: teams, spawns, no MatchState, no toast,
--   no pay, no streak); release() destroys one it did not take.
-- * The pilot: one loop every thinkSeconds over every match bot. It uses the same server functions the remotes use
--   (CombatService.requestThrow, DashService.requestDash, AbilityService.requestUltimate, through BotService's actions),
--   so ThrowRules, DashRules, the ultimate's gate and MatchRules decide every action, and hits on bots are the normal
--   sweep. Once its first teleport placed it on the map (the Countdown holds it there) its rig is freed, owned by the
--   server. While the match is live and the bot stands (fighter.isAlive: not knocked out):
--   - target: every targetSeconds the nearest enemy (CombatService.enemiesOf: never a teammate in TDM) that can be hit
--     now (port.canBeHit: no spawn protection) and that a ray from its head reaches unblocked by the map, within reach
--     (MatchBotRules.pickTarget); also the nearest standing enemy, seen or not (hunting). It faces the target, else
--     where it walks;
--   - moving: a new goal from MatchBotRules.pickMove (strafe at a good distance, cover, pads, hunting, roaming, the
--     storm's safe circle with look-ahead) on the raycasts below, Humanoid:MoveTo; stuck: one jump and a new goal;
--   - throwing: a reaction time (Config.Duel.Bots) after its throw is ready, at the target in reach (BotService.throwAt:
--     the lead and a random miss);
--   - dodging: an enemy's throw heading at it (MatchBotRules.threatened) is dodged with dodgeChance, a reaction time
--     later (BotService.dodge; DashService decides);
--   - the ultimate: a reaction time after it is ready, at the target (BotService.castAt);
--   - out of the map (below the kill line or outside the Bounds; the movement guard never checks a bot): the port's
--     outOfBounds, as the guard does for a player (MatchService: back on a spawn and, by Config, an out-of-bounds K.O.).
-- * Raycasts (the map's RaycastParams: map geometry only, never characters): the head-to-enemy sight line (nearest first,
--   until one is seen), the cover test (from the target), and each candidate goal's path: one waist-high ray along it
--   and a downward ray every pathStepStuds (ground above the kill line, nothing higher than climbStuds over its feet).
-- * Cleanup: a bot whose match is gone (MatchService.getMatch nil: its end and return, the void once no real player is
--   left, a shutdown) is destroyed by the next loop (BotService.destroyBot: the rig and the services' memory of it).
--   Closing stops new bots (BotService's own Closing also removes every bot that is not in a duel).
-- shortcut: straight-line goals only (no pathfinding, no ramps or platforms on purpose); use PathfindingService if bots
-- look stuck on Diego's maps.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local ProjectileMath = require(Shared.ProjectileMath)
local Strings = require(Shared.Strings)
local ValidateBots = require(Shared.Config.ValidateBots)
local ValidateMatchBots = require(Shared.Config.ValidateMatchBots)
local Logic = script.Parent.Parent.Logic
local BotRules = require(Logic.BotRules)
local MatchBotRules = require(Logic.MatchBotRules)
local Services = script.Parent
local AbilityService = require(Services.AbilityService)
local BotService = require(Services.BotService)
local CombatService = require(Services.CombatService)
local MatchService = require(Services.MatchService)
local ShutdownService = require(Services.ShutdownService)

-- Types

type Bot = BotService.Bot
type Fighter = CombatService.Fighter
type MatchPort = CombatService.MatchPort
type ArenaInfo = CombatService.ArenaInfo

-- The pilot's memory of one match bot (os.clock times).
type Pilot = {
	bot: Bot,
	target: Fighter?, -- the enemy it fights (seen at the last look)
	hunt: Vector3?, -- the nearest standing enemy at the last look, seen or not
	threat: Vector3?, -- where the throw it will dodge came from
	nextTargetAt: number,
	goal: Vector3?,
	nextMoveAt: number,
	stuckFrom: Vector3?, -- where it stood when the stuck check last started
	stuckAt: number,
	nextOobAt: number,
	standing: boolean, -- it stood at the last step (a new stand: the Active start or a respawn)
}

-- Constants

local CFG = Config.Match.Bots
local DUEL_BOTS = Config.Duel.Bots -- the practice bot's reaction times and its ultimate switch
local STORM = Config.Match.Storm
local ROOT_PART = "HumanoidRootPart"
local HEAD_STUDS = 1.5 -- reading: the eye above the HumanoidRootPart for the sight line
local OOB_RETRY_SECONDS = 1 -- reading: at most one out-of-bounds report a second
local GROUND_BELOW_STUDS = 3 -- reading: the downward path rays end this far under the kill line
local MAP_APRON_STUDS = 40 -- as MatchService: "on the map" = within the storm's start circle plus this

-- Module table

local MatchBotService = {}

-- Private

local log = Log.new("MatchBot")
local rng = Random.new()
local pilots: { Pilot } = {}
local template: Model? = nil
local enabled = false
local closed = false

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function rootOf(bot: Bot): BasePart?
	local rig = bot.Character
	local root = if rig then rig:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function newPilot(bot: Bot): Pilot
	return {
		bot = bot,
		target = nil,
		hunt = nil,
		threat = nil,
		nextTargetAt = 0,
		goal = nil,
		nextMoveAt = 0,
		stuckFrom = nil,
		stuckAt = 0,
		nextOobAt = 0,
		standing = false,
	}
end

local function forget(bot: Bot)
	for index, pilot in pilots do
		if pilot.bot == bot then
			table.remove(pilots, index)
			break
		end
	end
	BotService.destroyBot(bot)
end

-- Private: MatchService's bots (deps.bots) -------------------------------------------------------------------------

local function ready(): boolean
	return enabled
		and not closed
		and template ~= nil
		and not ShutdownService.isClosing()
		and not ShutdownService.isRestartPending()
end

local function take(_modeId: string, count: number): { any }
	local list: { any } = {}
	local source = template
	if not ready() or source == nil then
		return list
	end
	for _ = 1, count do
		local rig = source:Clone()
		local bot = if rig then BotService.newBot(rig) else nil
		if bot == nil then
			break -- fewer bots this time (newBot logged why)
		end
		table.insert(pilots, newPilot(bot))
		table.insert(list, bot)
	end
	return list
end

local function release(ref: any)
	forget(ref)
end

-- Private: raycasts ------------------------------------------------------------------------------------------------

local function sees(params: RaycastParams, from: Vector3, to: Vector3): boolean
	return Workspace:Raycast(from, to - from, params) == nil
end

-- A goal's straight path: clear at waist height (the root's), and ground under it every pathStepStuds above the kill
-- line (no hole to the void) and never more than climbStuds above the feet.
local function walkable(arena: ArenaInfo, feetY: number, from: Vector3, to: Vector3): boolean
	local path = flat(to - from)
	local length = path.Magnitude
	if length < 1e-3 then
		return true
	end
	local params = arena.raycastParams
	if Workspace:Raycast(from, path, params) ~= nil then
		return false
	end
	local steps = math.max(1, math.ceil(length / CFG.pathStepStuds))
	local down = Vector3.new(0, arena.killY - GROUND_BELOW_STUDS - from.Y, 0)
	for i = 1, steps do
		local hit = Workspace:Raycast(from + path * (i / steps), down, params)
		if hit == nil or hit.Position.Y > feetY + CFG.climbStuds then
			return false
		end
	end
	return true
end

-- Private: the pilot -----------------------------------------------------------------------------------------------

-- How far the bot fights: rangeFraction of its squishy's longest throw, at most targetMaxStuds.
local function reachOf(fighter: Fighter): number
	return math.min(
		ProjectileMath.maxRange(fighter.throw.speed, fighter.throw.gravity) * CFG.rangeFraction,
		CFG.targetMaxStuds
	)
end

-- The enemy to fight (nearest seen, hittable, in reach) and the nearest standing enemy (hunting).
local function look(port: MatchPort, fighter: Fighter, root: BasePart, reach: number, t: number): (Fighter?, Vector3?)
	local from = root.Position
	local list: { Fighter } = {}
	local positions: { Vector3 } = {}
	local hunt: Vector3? = nil
	local huntDistance = math.huge
	for _, enemy in CombatService.enemiesOf(port, fighter) do
		local enemyRoot = enemy.getRoot()
		if enemyRoot and enemy.isAlive() then
			local distance = flat(enemyRoot.Position - from).Magnitude
			if distance < huntDistance then
				hunt, huntDistance = enemyRoot.Position, distance
			end
			if port.canBeHit(enemy, t, fighter) then
				table.insert(list, enemy)
				table.insert(positions, enemyRoot.Position)
			end
		end
	end
	local eye = from + Vector3.new(0, HEAD_STUDS, 0)
	local params = port.arena.raycastParams
	local index = MatchBotRules.pickTarget(from, positions, reach, function(i: number): boolean
		return sees(params, eye, positions[i])
	end)
	return (if index then list[index] else nil), hunt
end

local function chooseGoal(
	pilot: Pilot,
	view: MatchService.BotView,
	port: MatchPort,
	root: BasePart,
	humanoid: Humanoid,
	targetRoot: BasePart?,
	reach: number
): Vector3?
	local map = view.map
	local arena = port.arena
	local feetY = root.Position.Y - (humanoid.HipHeight + root.Size.Y / 2)
	local safe = if view.stormSeconds
		then MatchBotRules.safeCircle(
			STORM,
			Vector3.new(map.centre.X, map.floorY, map.centre.Z),
			map.startRadius,
			view.stormSeconds
		)
		else nil
	local params = arena.raycastParams
	local targetAt = if targetRoot then targetRoot.Position else nil
	return MatchBotRules.pickMove(rng, {
		from = root.Position,
		bounds = map.bounds,
		safe = safe,
		target = targetAt,
		reach = reach,
		hunt = pilot.hunt,
		pads = view.pads,
		walkable = function(from: Vector3, to: Vector3): boolean
			return walkable(arena, feetY, from, to)
		end,
		covered = if targetAt
			then function(point: Vector3): boolean
				return not sees(params, targetAt, point)
			end
			else nil,
	})
end

-- One decision step (see the header). `now` = os.clock().
local function step(pilot: Pilot, now: number)
	local bot = pilot.bot
	local fighter = CombatService.getFighter(bot)
	local port = if fighter then CombatService.portOf(fighter) else nil
	local view = MatchService.botView(bot)
	local root = rootOf(bot)
	local rig = bot.Character
	local humanoid = if rig then rig:FindFirstChildOfClass("Humanoid") else nil
	if fighter == nil or port == nil or view == nil or root == nil or humanoid == nil then
		return
	end
	local map = view.map
	if
		root.Anchored
		and port.phase() ~= "Positioning"
		and flat(root.Position - map.centre).Magnitude <= map.startRadius + MAP_APRON_STUDS
	then
		-- On its spot now (the Countdown holds it there): free it, owned by the server.
		root.Anchored = false
		pcall(function(): any
			root:SetNetworkOwner(nil)
			return nil
		end)
	end
	if root.Anchored or not view.live or not fighter.isAlive() then
		if pilot.standing then
			pilot.standing = false
			pilot.target = nil
			pilot.goal = nil
			humanoid:MoveTo(root.Position) -- stop where it is (knocked out, or the match is over)
		end
		return
	end
	if not pilot.standing then
		-- Standing again (the Active start or a respawn): a fresh look and a fresh goal from here.
		pilot.standing = true
		pilot.goal = nil
		pilot.nextTargetAt = now
		pilot.nextMoveAt = now
		humanoid:MoveTo(root.Position)
	end
	local position = root.Position
	if position.Y < port.arena.killY or not MatchBotRules.insideBounds(position, map.bounds, 0) then
		if now >= pilot.nextOobAt then
			pilot.nextOobAt = now + OOB_RETRY_SECONDS
			port.outOfBounds(fighter)
		end
		return
	end

	local t = Workspace:GetServerTimeNow()
	local rooted = t < fighter.rootedUntil
	local dashing = now < bot.dashingUntil
	local reach = reachOf(fighter)
	if now >= pilot.nextTargetAt then
		pilot.nextTargetAt = now + CFG.targetSeconds
		pilot.target, pilot.hunt = look(port, fighter, root, reach, t)
	end
	local target = pilot.target
	local targetRoot = if target and target.isAlive() then target.getRoot() else nil
	if target and targetRoot == nil then
		pilot.target = nil -- knocked out (or gone) since the last look
		pilot.nextTargetAt = now
	end

	if not rooted and not dashing then
		local goal = pilot.goal
		if goal and flat(goal - position).Magnitude < CFG.arrivedStuds then
			pilot.goal = nil
		elseif goal and now - pilot.stuckAt >= CFG.stuckSeconds then
			local from = pilot.stuckFrom
			if from and flat(position - from).Magnitude < CFG.stuckStuds then
				humanoid.Jump = true
				pilot.nextMoveAt = now -- stuck: a new goal
			end
			pilot.stuckFrom, pilot.stuckAt = position, now
		end
		if now >= pilot.nextMoveAt then
			pilot.nextMoveAt = now + BotRules.between(rng, CFG.moveMinSeconds, CFG.moveMaxSeconds)
			local nextGoal = chooseGoal(pilot, view, port, root, humanoid, targetRoot, reach)
			if nextGoal then
				pilot.goal = nextGoal
				pilot.stuckFrom, pilot.stuckAt = position, now
				humanoid:MoveTo(nextGoal)
			end
		end
	end
	if not dashing then
		local lookAt = if targetRoot then targetRoot.Position else pilot.goal
		if lookAt then
			BotService.face(root, lookAt)
		end
	end

	local dodgeAt = bot.dodgeDueAt
	if dodgeAt and now >= dodgeAt then
		bot.dodgeDueAt = nil
		local threat = pilot.threat
		if threat and not rooted and not dashing then
			BotService.dodge(bot, root, threat)
			return
		end
	end
	if targetRoot == nil or rooted or dashing then
		return
	end
	if DUEL_BOTS.useUltimate and AbilityService.isReady(bot.userId) then
		local ultAt = bot.ultDueAt
		if ultAt == nil then
			bot.ultDueAt = now + BotRules.between(rng, DUEL_BOTS.ultReactionMinSeconds, DUEL_BOTS.ultReactionMaxSeconds)
		elseif now >= ultAt then
			bot.ultDueAt = nil
			BotService.castAt(bot, root, targetRoot)
			return
		end
	end
	if t >= fighter.nextThrowAt and flat(targetRoot.Position - position).Magnitude <= reach then
		local throwAt = bot.throwDueAt
		if throwAt == nil then
			bot.throwDueAt = now
				+ BotRules.between(rng, DUEL_BOTS.throwReactionMinSeconds, DUEL_BOTS.throwReactionMaxSeconds)
		elseif now >= throwAt then
			bot.throwDueAt = nil
			BotService.throwAt(bot, root, targetRoot)
		end
	end
end

local function loop()
	while true do
		task.wait(CFG.thinkSeconds)
		local now = os.clock()
		for _, pilot in table.clone(pilots) do
			if not MatchService.inVoteOrMatch(pilot.bot) then
				forget(pilot.bot) -- its vote or match is over (the end, a void, a shutdown): the rig goes with it
			else
				local ok, err = pcall(step :: any, pilot, now)
				if not ok and not pilot.bot.warned then
					pilot.bot.warned = true -- once per bot: a failing step repeats every thinkSeconds
					log:warn(`match bot {pilot.bot.userId} step failed:`, err)
				end
			end
		end
	end
end

-- An enemy's throw: the bots it heads at may dodge it, a reaction time later (the pilot dashes).
local function onThrowAccepted(info: any)
	if type(info) ~= "table" or info.kind ~= "throw" or info.matchId == nil or #pilots == 0 then
		return
	end
	local thrower = CombatService.getFighter(info.userId)
	local port = if thrower then CombatService.portOf(thrower) else nil
	local projectile = CombatService.projectileInfo(info.projId)
	if thrower == nil or port == nil or projectile == nil then
		return
	end
	for _, pilot in pilots do
		local bot = pilot.bot
		local fighter = if bot.userId ~= thrower.userId and bot.dodgeDueAt == nil -- (not its own, one at a time)
			then CombatService.getFighter(bot)
			else nil
		local root = rootOf(bot)
		if
			fighter
			and root
			and CombatService.portOf(fighter) == port
			and not (port.teams and fighter.side == thrower.side)
			and MatchBotRules.threatened(root.Position, projectile.origin, projectile.velocity)
			and rng:NextNumber() < CFG.dodgeChance
		then
			pilot.threat = projectile.origin
			bot.dodgeDueAt = os.clock()
				+ BotRules.between(rng, DUEL_BOTS.dodgeReactionMinSeconds, DUEL_BOTS.dodgeReactionMaxSeconds)
		end
	end
end

-- The plain character every match bot is a clone of; tried again every rigRetrySeconds until it is built.
local function buildTemplate()
	while template == nil and not closed do
		local rig = BotService.buildRigAsync()
		if rig then
			rig.Archivable = true -- Clone() needs it
			template = rig
		else
			task.wait(CFG.rigRetrySeconds)
		end
	end
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function MatchBotService.init()
	local problems = ValidateMatchBots(Config)
	for _, problem in ValidateBots(Config, Strings) do
		table.insert(problems, problem)
	end
	for _, problem in problems do
		log:warn(problem)
	end
	enabled = CFG.enabled == true and #problems == 0
	if CFG.enabled == true and #problems > 0 then
		log:warn("match bots are off: Config.Match.Bots or Config.Duel.Bots has problems")
	end
	if not enabled then
		return
	end
	MatchService.attachBots({ ready = ready, take = take, release = release })
	CombatService.ThrowAccepted:connect(onThrowAccepted)
	ShutdownService.Closing:connect(function()
		closed = true -- no new bots; the bots in a match go with its void (the loop)
	end)
end

function MatchBotService.start()
	if not enabled then
		return
	end
	task.spawn(buildTemplate)
	loop()
end

return MatchBotService
