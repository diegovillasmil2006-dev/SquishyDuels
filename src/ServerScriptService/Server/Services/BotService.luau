--!strict
-- BotService (server only). The 1v1 PRACTICE BOT (owner 2026-10-16; the Free for All / Team Deathmatch match bots are
-- MatchBotService's, 2026-10-17: they are bots of this module too, see "the match bots' kit" below). Numbers:
-- Config.Duel.Bots (Config/Bots, [P], checked by Config/ValidateBots at init: any problem keeps the bots off);
-- decisions: Logic/BotRules.
-- * Filling: every checkSeconds, when exactly one player is Searching in the 1v1 queue, an arena slot is free and no
--   shutdown or restart is pending, that player's lone-wait timer runs (BotRules.watch: a random fillDelay, 8-10 s).
--   When it is due a bot is built and QueueService.startWithBot starts the duel; startWithBot refuses unless the
--   player is still the only one Searching, so a real player who queues first always takes the spot (QueueService pairs
--   two tickets at once). One fill at a time.
-- * The bot is a Player-shaped table (kind "bot", like TestHarness's Studio dummy): a random UserId of -200001 or below
--   (never a real player's, a Studio test player's -1, -2, ... or a dummy's -100001, ...), a random real-looking name
--   (BotRules.name from the Strings.bot word lists), a random catalog squishy each duel, Character = a plain Roblox
--   character (the default HumanoidDescription) in Workspace.SD_Bots, Parent = that folder while it lives. The rig
--   waits anchored out of sight until the duel's pad teleport, joins SD_Characters (so the arena dividers stop it) and,
--   once free, its physics is owned by the server (no client can push it). Its own idle and walk clips (the rig's
--   Animate Animation objects; an NPC's Animate LocalScript never runs) are played on the server.
-- * DuelService takes it as the opponent (isBot): no Player, so it gets no DuelResult, no reward, no save, no quest and
--   no board entry; the human's duel pays exactly as a real duel (DuelRewards is unchanged). The client sees its name
--   (DuelParticipantView.isTestDummy stays false for a bot).
-- * The pilot (one thread per bot, every thinkSeconds, only while the duel is Active or SuddenDeath) uses the same server
--   functions the remotes use, so ThrowRules, DashRules and the ultimate gate decide every action and hits on the bot go
--   through the same sweep and DuelRules: it faces the player, walks to random spots of its own half
--   (BotRules.pickMove, sometimes one behind cover), throws a reaction time after its throw is ready, at where the
--   player will be with a random miss (BotRules.aimPoint, CombatService.requestThrow), dodges some of the player's
--   throws with a sideways dash (CombatService.ThrowAccepted, DashService.requestDash, then it moves its own root
--   along DashMath's path as a player's client does) and casts its ultimate when it is ready
--   (AbilityService.requestUltimate). No remote and no player check changed.
-- * Cleanup: the rig is destroyed as soon as DuelService no longer has the bot's match (the end, the player leaving, a
--   void at shutdown), or at once when its duel did not start; Closing stops the filling and removes every bot that is
--   not in a duel. The services' per-user memory of it (throw seq, dash state, practice caster) is forgotten too.
-- shortcut: the bot never charges a throw, catches, jumps or double-jumps; add them when it feels too easy.

-- Services

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local DashMath = require(Shared.DashMath)
local Log = require(Shared.Util.Log)
local ProjectileMath = require(Shared.ProjectileMath)
local Strings = require(Shared.Strings)
local ValidateBots = require(Shared.Config.ValidateBots)
local BotRules = require(script.Parent.Parent.Logic.BotRules)
local AbilityService = require(script.Parent.AbilityService)
local CharacterService = require(script.Parent.CharacterService)
local CombatService = require(script.Parent.CombatService)
local DashService = require(script.Parent.DashService)
local DuelService = require(script.Parent.DuelService)
local QueueService = require(script.Parent.QueueService)
local ShutdownService = require(script.Parent.ShutdownService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Bot = {
	kind: string,
	isBot: boolean,
	UserId: number,
	userId: number,
	Name: string,
	DisplayName: string,
	displayName: string,
	Character: Model?,
	character: Model?,
	Parent: Instance?,
	squishyId: string,
	GetAttribute: (self: Bot, name: string) -> any,
	SetAttribute: (self: Bot, name: string, value: any) -> (),
	RequestStreamAroundAsync: (self: Bot, position: Vector3, timeout: number?) -> (),
	IsA: (self: Bot, className: string) -> boolean,
	-- Pilot state (os.clock times, except where the fighter's server times are read)
	alive: boolean,
	opponent: Player?,
	attributes: { [string]: any },
	throwSeq: number,
	dashSeq: number,
	ultSeq: number,
	throwDueAt: number?,
	dodgeDueAt: number?,
	ultDueAt: number?,
	nextMoveAt: number,
	dashingUntil: number,
	warned: boolean,
	connections: { RBXScriptConnection },
}

-- Constants

local BOTS = Config.Duel.Bots
local DASH = Config.Duel.Rules.Dash
local WALK_SPEED = Config.Duel.Rules.Movement.WalkSpeed
local FOLDER_NAME = "SD_Bots"
local ROOT_PART = "HumanoidRootPart"
local USER_ID_MIN, USER_ID_MAX = 200001, 999999999 -- bots are -200001 .. -999999999
local HOLD_CFRAME = CFrame.new(0, 1000, 0) -- out of sight until DuelService teleports it to its pad
local FREE_PHASES: { [string]: boolean } = { Countdown = true, Active = true, SuddenDeath = true }
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local HALF_BY_SIDE: { [string]: string } = { A = "HalfA", B = "HalfB" }
local WALK_MIN_SPEED = 0.5 -- studs/s: slower counts as standing (idle clip)
local FADE_SECONDS = 0.2

-- Module table

local BotService = {}

-- Private

local log = Log.new("Bot")
local rng = Random.new()
local bots: { Bot } = {}
local watch: BotRules.Watch? = nil
local filling = false
local enabled = false
local closed = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function newUserId(): number
	local id = -rng:NextInteger(USER_ID_MIN, USER_ID_MAX)
	for _, bot in bots do
		if bot.userId == id then
			return newUserId()
		end
	end
	return id
end

local function randomSquishy(): string
	local list = Catalog.list()
	local def = list[rng:NextInteger(1, #list)]
	return if def then def.id else Catalog.starterId()
end

local function getFolder(): Instance
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = Workspace
		folder = created
	end
	return folder :: Instance
end

local function rootOf(bot: Bot): BasePart?
	local rig = bot.Character
	local root = if rig then rig:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- A plain Roblox character (the default HumanoidDescription). Yields. nil when the avatar service fails (no bot this
-- time; the next lone wait tries again).
local function buildRigAsync(): Model?
	local description = Instance.new("HumanoidDescription")
	local ok, rig = pcall(function(): Model
		return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)
	end)
	description:Destroy()
	if ok and typeof(rig) == "Instance" and rig:IsA("Model") then
		return rig
	end
	log:warn("the bot's character could not be built; no bot this time:", rig)
	return nil
end

local function makeBot(rig: Model, folder: Instance): Bot
	local userId = newUserId()
	local name = BotRules.name(rng, Strings.bot.nameStarts, Strings.bot.nameEnds, BOTS)
	local bot: Bot = {
		kind = "bot",
		isBot = true,
		UserId = userId,
		userId = userId,
		Name = name,
		DisplayName = name,
		displayName = name,
		Character = rig,
		character = rig,
		Parent = folder,
		squishyId = randomSquishy(),
		GetAttribute = function(self: Bot, key: string): any
			return self.attributes[key]
		end,
		SetAttribute = function(self: Bot, key: string, value: any)
			self.attributes[key] = value
			local model = self.Character
			if model ~= nil then
				model:SetAttribute(key, value) -- SD_MatchId / SD_DuelPhase show in the Explorer
			end
		end,
		RequestStreamAroundAsync = function(_self: Bot, _position: Vector3, _timeout: number?) end,
		IsA = function(_self: Bot, _className: string): boolean
			return false -- never a Player instance
		end,
		alive = true,
		opponent = nil,
		attributes = {},
		throwSeq = 0,
		dashSeq = 0,
		ultSeq = 0,
		throwDueAt = nil,
		dodgeDueAt = nil,
		ultDueAt = nil,
		nextMoveAt = 0,
		dashingUntil = 0,
		warned = false,
		connections = {},
	}
	return bot
end

-- The rig's own default idle and walk clips, played by the server (it owns the rig, so they replicate). No id is typed
-- here: they are the Animation objects of the rig's Animate script, whose LocalScript never runs on an NPC.
-- shortcut: idle + walk only (no jump or fall poses), until Diego designs the bot's look.
local function startAnimations(bot: Bot, rig: Model, humanoid: Humanoid)
	local animate = rig:FindFirstChild("Animate")
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator == nil then
		local created = Instance.new("Animator")
		created.Parent = humanoid
		animator = created
	end
	local function load(holderName: string): AnimationTrack?
		local holder = if animate then animate:FindFirstChild(holderName) else nil
		local clip = if holder then holder:FindFirstChildOfClass("Animation") else nil
		if clip == nil or animator == nil then
			return nil
		end
		local ok, track = pcall(function(): AnimationTrack
			return (animator :: Animator):LoadAnimation(clip)
		end)
		return if ok then track else nil
	end
	local idle, walk = load("idle"), load("walk")
	if idle then
		idle.Looped = true
		idle:Play()
	end
	if walk then
		local track: AnimationTrack = walk
		track.Looped = true
		table.insert(
			bot.connections,
			humanoid.Running:Connect(function(speed: number)
				if speed > WALK_MIN_SPEED then
					if not track.IsPlaying then
						track:Play(FADE_SECONDS)
					end
					track:AdjustSpeed(speed / WALK_SPEED)
				elseif track.IsPlaying then
					track:Stop(FADE_SECONDS)
				end
			end)
		)
	end
end

local function setupRig(bot: Bot, rig: Model, folder: Instance)
	rig.Name = bot.Name
	rig.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = bot.DisplayName
		humanoid.AutoRotate = false -- the pilot keeps it facing the player while it strafes
	end
	rig:PivotTo(HOLD_CFRAME)
	local root = rig:FindFirstChild(ROOT_PART)
	if root and root:IsA("BasePart") then
		root.Anchored = true -- held until the pad teleport (see the header)
	end
	local okGroup, registered = pcall(function(): boolean
		return PhysicsService:IsCollisionGroupRegistered(WorldService.CollisionGroups.Characters)
	end)
	if okGroup and registered then
		CharacterService.applyCollisionGroup(rig)
	end
	rig.Parent = folder
	if humanoid then
		startAnimations(bot, rig, humanoid)
	end
end

local function destroyBot(bot: Bot)
	if not bot.alive then
		return
	end
	bot.alive = false
	for _, connection in bot.connections do
		connection:Disconnect()
	end
	table.clear(bot.connections)
	local rig = bot.Character
	bot.Character = nil
	bot.character = nil
	bot.Parent = nil
	if rig then
		rig:Destroy()
	end
	local index = table.find(bots, bot)
	if index then
		table.remove(bots, index)
	end
	-- The per-user memory these services keep for a thrower, a dasher and a caster (a bot's id never comes back).
	for _, forget in { CombatService.playerRemoving, DashService.playerRemoving, AbilityService.playerRemoving } do
		pcall(forget, bot :: any)
	end
end

-- Private: the pilot ---------------------------------------------------------------------------------------------------

-- Turns the root to face `target` on the flat, keeping its position and its walk: writing a humanoid root's CFrame
-- cancels its Humanoid:MoveTo (2026-10-26: the bots never walked, they jumped in place), so the walk is given again.
local function face(root: BasePart, target: Vector3)
	local look = Vector3.new(target.X, root.Position.Y, target.Z)
	if (look - root.Position).Magnitude > 1e-3 then
		root.CFrame = CFrame.lookAt(root.Position, look)
		local rig = root.Parent
		local humanoid = if rig then rig:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			humanoid:MoveTo(humanoid.WalkToPoint)
		end
	end
end

local function throwAtPlayer(bot: Bot, root: BasePart, target: BasePart)
	local def = Catalog.get(bot.squishyId) or Catalog.get(Catalog.starterId())
	if def == nil then
		return
	end
	face(root, target.Position)
	local origin = root.CFrame * Config.Combat.ReleaseOffset -- the server's own release point (ThrowRules check 10)
	local distance = flat(target.Position - origin).Magnitude
	local flight = distance / math.max(def.throw.speed, 1)
	local aim = BotRules.aimPoint(rng, target.Position, target.AssemblyLinearVelocity, flight, distance, BOTS)
	local dir = ProjectileMath.solveLaunchDir(origin, aim, def.throw.speed, def.throw.gravity)
	bot.throwSeq += 1
	CombatService.requestThrow(bot, bot.throwSeq, dir, origin, serverNow())
end

-- A sideways dash away from the line of fire: DashService decides (and cuts) it; the bot then moves its own root
-- along the dash's path, as a player's client does.
local function dodge(bot: Bot, root: BasePart, threat: Vector3)
	bot.dashSeq += 1
	local ok, _, to =
		DashService.requestDash(bot, bot.dashSeq, BotRules.dodgeDir(rng, root.Position, threat), serverNow())
	if not ok or to == nil then
		return
	end
	local from = root.Position
	local path = flat(to - from)
	local distance = path.Magnitude
	if distance < 1e-3 then
		return
	end
	local unit = path.Unit
	local started = os.clock()
	bot.dashingUntil = started + DASH.seconds
	task.spawn(function()
		while bot.alive and root.Parent ~= nil do
			local t = math.min(os.clock() - started, DASH.seconds)
			local at = from + unit * DashMath.offsetAt(t, distance, DASH.seconds)
			root.CFrame = CFrame.new(at.X, root.Position.Y, at.Z) * root.CFrame.Rotation
			if t >= DASH.seconds then
				break
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function castAt(bot: Bot, root: BasePart, target: BasePart)
	face(root, target.Position)
	local distance = flat(target.Position - root.Position).Magnitude
	local aim = flat(BotRules.aimPoint(rng, target.Position, Vector3.zero, 0, distance, BOTS) - root.Position)
	if aim.Magnitude < 1e-3 then
		return
	end
	bot.ultSeq += 1
	AbilityService.requestUltimate(bot, bot.ultSeq, aim.Unit, serverNow())
end

-- One decision step (see the header). `now` = os.clock().
local function step(bot: Bot, now: number)
	local fighter = CombatService.getFighter(bot)
	local port = if fighter then CombatService.portOf(fighter) else nil
	local root = rootOf(bot)
	local rig = bot.Character
	local humanoid = if rig then rig:FindFirstChildOfClass("Humanoid") else nil
	if fighter == nil or port == nil or root == nil or humanoid == nil then
		return
	end
	local phase = port.phase()
	if root.Anchored and FREE_PHASES[phase] then
		-- On its pad now (Countdown keeps it frozen): free it, owned by the server.
		root.Anchored = false
		pcall(function(): any
			root:SetNetworkOwner(nil)
			return nil
		end)
	end
	local opponent = bot.opponent
	local target = if opponent then CharacterService.getRoot(opponent) else nil
	if not LIVE_PHASES[phase] or target == nil then
		return
	end
	local t = serverNow()
	local rooted = t < fighter.rootedUntil
	local dashing = now < bot.dashingUntil
	if not dashing then
		face(root, target.Position)
	end

	if not rooted and not dashing and now >= bot.nextMoveAt then
		local zone = port.arena.zones[HALF_BY_SIDE[fighter.side] or ""]
		if zone then
			local params = port.arena.raycastParams
			local eye = target.Position
			humanoid:MoveTo(BotRules.pickMove(rng, zone, root.Position, BOTS, function(point: Vector3): boolean
				return Workspace:Raycast(eye, point - eye, params) ~= nil -- cover between the player and that spot
			end))
		end
		bot.nextMoveAt = now + BotRules.between(rng, BOTS.moveMinSeconds, BOTS.moveMaxSeconds)
	end

	local dodgeAt = bot.dodgeDueAt
	if dodgeAt and now >= dodgeAt then
		bot.dodgeDueAt = nil
		if not rooted and not dashing then
			dodge(bot, root, target.Position)
			return
		end
	end

	if BOTS.useUltimate and not rooted and AbilityService.isReady(bot.userId) then
		local ultAt = bot.ultDueAt
		if ultAt == nil then
			bot.ultDueAt = now + BotRules.between(rng, BOTS.ultReactionMinSeconds, BOTS.ultReactionMaxSeconds)
		elseif now >= ultAt then
			bot.ultDueAt = nil
			castAt(bot, root, target)
			return
		end
	end

	if not rooted and t >= fighter.nextThrowAt then
		local throwReadyAt = bot.throwDueAt
		if throwReadyAt == nil then
			bot.throwDueAt = now + BotRules.between(rng, BOTS.throwReactionMinSeconds, BOTS.throwReactionMaxSeconds)
		elseif now >= throwReadyAt then
			bot.throwDueAt = nil
			throwAtPlayer(bot, root, target)
		end
	end
end

local function pilot(bot: Bot)
	while bot.alive do
		task.wait(BOTS.thinkSeconds)
		if DuelService.getMatch(bot) == nil then
			destroyBot(bot) -- the duel is over (its end, the player leaving, a void): the rig goes with it
			break
		end
		local ok, err = pcall(step :: any, bot, os.clock())
		if not ok and not bot.warned then
			bot.warned = true -- once per bot: a failing step repeats every thinkSeconds
			log:warn(`bot {bot.userId} step failed:`, err)
		end
	end
end

-- The player's throw: some of them are dodged, a reaction time later (the pilot dashes).
local function onThrowAccepted(info: any)
	if type(info) ~= "table" or info.kind ~= "throw" then
		return
	end
	for _, bot in bots do
		local opponent = bot.opponent
		if
			opponent ~= nil
			and opponent.UserId == info.userId
			and bot.dodgeDueAt == nil
			and rng:NextNumber() < BOTS.dodgeChance
		then
			bot.dodgeDueAt = os.clock()
				+ BotRules.between(rng, BOTS.dodgeReactionMinSeconds, BOTS.dodgeReactionMaxSeconds)
		end
	end
end

-- Private: filling the queue -------------------------------------------------------------------------------------------

-- The one player Searching in the 1v1 queue, or nil (nobody, or more than one: they are paired with each other).
local function loneWaiter(): Player?
	if QueueService.searchingCount() ~= 1 then
		return nil
	end
	for _, player in Players:GetPlayers() do
		if QueueService.state(player) == "Searching" then
			return player
		end
	end
	return nil
end

local function canFill(): boolean
	return enabled
		and not closed
		and not ShutdownService.isClosing()
		and not ShutdownService.isRestartPending()
		and QueueService.counts().arenasFree > 0
end

local function fillAsync(player: Player)
	local rig = buildRigAsync()
	if rig == nil then
		return
	end
	local folder = getFolder()
	local bot = makeBot(rig, folder)
	table.insert(bots, bot)
	local okSetup, setupError = pcall(setupRig :: any, bot, rig, folder)
	if not okSetup or loneWaiter() ~= player or not canFill() then
		destroyBot(bot) -- a real player came first (or the player left) while the character loaded
		if not okSetup then
			log:error("setting up the bot's character failed:", setupError)
		end
		return
	end
	local ok, why = QueueService.startWithBot(player, bot)
	if not ok then
		destroyBot(bot)
		log:info(`no bot duel for user {player.UserId}: {tostring(why)}`)
		return
	end
	bot.opponent = player
	log:info(`bot {bot.userId} ({bot.squishyId}) fills the duel of user {player.UserId}`)
	task.spawn(pilot, bot)
end

-- One fill check (every checkSeconds).
local function check()
	local waiter = if canFill() and not filling then loneWaiter() else nil
	local nextWatch, due = BotRules.watch(watch, if waiter then waiter.UserId else nil, os.clock(), rng, BOTS)
	watch = nextWatch
	if not due or waiter == nil then
		return
	end
	watch = nil
	filling = true
	task.spawn(function()
		local ok, err = pcall(fillAsync :: any, waiter)
		if not ok then
			log:error("filling a duel with a bot failed:", err)
		end
		filling = false
	end)
end

-- Public: the match bots' kit (MatchBotService, 2026-10-17) ------------------------------------------------------------
-- A match bot is a bot of this module (its name, random squishy, look and clips; in this module's list, so no id
-- repeats and Closing removes it) that MatchService plays instead of DuelService; no pilot of this module runs for it
-- (opponent stays nil). MatchBotService drives it with the same actions as the practice bot.

-- A bot around `rig` (a fresh plain character: buildRigAsync's, or a clone of one), held anchored out of sight until
-- its first teleport. nil when the rig could not be set up (nothing is left behind).
function BotService.newBot(rig: Model): Bot?
	local folder = getFolder()
	local bot = makeBot(rig, folder)
	table.insert(bots, bot)
	local ok, err = pcall(setupRig :: any, bot, rig, folder)
	if not ok then
		destroyBot(bot)
		log:error("setting up a match bot's character failed:", err)
		return nil
	end
	return bot
end

BotService.buildRigAsync = buildRigAsync -- yields; nil when the avatar service fails
BotService.destroyBot = destroyBot
BotService.face = face -- (root, point)
BotService.throwAt = throwAtPlayer -- (bot, root, targetRoot): the practice bot's aim (Config.Duel.Bots)
BotService.dodge = dodge -- (bot, root, threat): a sideways dash away from the line of fire
BotService.castAt = castAt -- (bot, root, targetRoot): the ultimate

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function BotService.init()
	local problems = ValidateBots(Config, Strings)
	for _, problem in problems do
		log:warn(problem)
	end
	enabled = BOTS.enabled == true and #problems == 0
	if BOTS.enabled == true and #problems > 0 then
		log:warn("practice bots are off: Config.Duel.Bots has problems")
	end
	CombatService.ThrowAccepted:connect(onThrowAccepted)
	ShutdownService.Closing:connect(function()
		closed = true
		for _, bot in table.clone(bots) do
			if DuelService.getMatch(bot) == nil then
				destroyBot(bot) -- the bots in a duel go when DuelService's void closes it (their pilot)
			end
		end
	end)
end

function BotService.start()
	while true do
		task.wait(BOTS.checkSeconds)
		local ok, err = pcall(check :: any)
		if not ok then
			log:error("bot check failed:", err)
		end
	end
end

return BotService
