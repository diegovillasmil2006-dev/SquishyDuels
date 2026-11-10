--!strict
-- PerkService (server only). The perks a player has for who they are (Config.Bonus), each a pen boost while it lasts and
-- one gift per account:
--   group  big job item 4 (2026-11-10; the owner: "A bonus for joining my Roblox group (DIJAY Studios)"): members of
--          the game's owner group. LihFolk vault "Roblox Communities as Your On-Platform Hub": a modest perk, the
--          membership checked on the server with the async API, kept for the visit, checked again only when the
--          player asks.
--   plus   big job item 5 (the owner: "Perks for Roblox Premium players"): Roblox Plus subscribers and the members
--          Premium still has. LihFolk vault "Subscriptions and Premium Payouts": read Player.HasRobloxSubscription on
--          the server, follow its changes, give a reward only once the server sees the subscription, and never take a
--          perk away because a read failed.
-- * A perk's pen boost: penBoost(p) is the sum for the perks the player has; PenService adds it to the Friend Boost.
--   The Player attributes SD_GroupBoost and SD_PlusBoost hold each in whole percent (0 = not theirs, or not known
--   yet) for the client's pills and the Settings row.
-- * A perk's gift: its giftSqueezes x the squeeze value in Coins (reasons "group" / "plus"), once per account
--   (profile.gifts.group / .plus, set in the same step), a "soon" save and a toast (bonus.groupGift / bonus.plusGift).
--   It is given as soon as the player has the perk and a READY profile: tried after every answer and on every profile
--   load or status change. Never yields.
-- * group: on join the server asks Roblox once (Player:IsInGroupAsync, in its own thread; a call that fails counts as
--   not a member for now). GroupCheck (RF, no arguments) is "I joined" (the client calls it after its join prompt): a
--   player not known as a member is asked about again with a fresh call (GroupService:GetGroupsAsync: IsInGroupAsync
--   keeps its first answer for the whole visit), at most once every recheckSeconds (else net.rateLimited). Replies
--   ok { member, coins } (coins = the gift, when this call gave it).
-- * plus: read on join and again whenever Roblox changes the player's subscription (subscribing during a visit turns
--   the perk on at once; a subscription that ends turns the boost off).
-- Collaborators are injectable (useDeps) so unit tests run with fake players and answers.

-- Services

local GroupService = game:GetService("GroupService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Bonus = require(Shared.Config.Bonus)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Types = require(Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)

-- Types

export type Deps = {
	data: StateService.DataPort,
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
	notify: (player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?) -> (),
	isMember: (player: any) -> boolean, -- Player:IsInGroupAsync (yields, may error; one answer per visit)
	isMemberNow: (player: any) -> boolean, -- a fresh answer (yields, may error)
	isSubscriber: (player: any) -> boolean, -- Roblox Plus, or legacy Premium (never yields; may error)
	watchSubscriber: (player: any, changed: () -> ()) -> () -> (), -- calls `changed` on a change; returns its stop
	spawn: (fn: (...any) -> ...any, ...any) -> (),
	clock: () -> number, -- os.clock: the re-check spacing
}

-- One perk: its pen boost, its attribute, its gift and that gift's flag, Coin reason and toast.
type Perk = { boost: number, attr: string, giftSqueezes: number, giftKey: string, reason: string, notice: string }

-- Constants

local GROUP = Bonus.Group
local PERKS: { [string]: Perk } = {
	group = {
		boost = GROUP.penBoost,
		attr = "SD_GroupBoost",
		giftSqueezes = GROUP.giftSqueezes,
		giftKey = "group", -- profile.gifts.group
		reason = "group",
		notice = "bonus.groupGift",
	},
	plus = {
		boost = Bonus.Plus.penBoost,
		attr = "SD_PlusBoost",
		giftSqueezes = Bonus.Plus.giftSqueezes,
		giftKey = "plus", -- profile.gifts.plus
		reason = "plus",
		notice = "bonus.plusGift",
	},
}
local REMOTE = "GroupCheck"
local STATUS_READY = "ready"
local SAVE_SOON = "soon"
local CODE_WAIT = "net.rateLimited"
local CODE_FAILED = "error.generic"

-- Module table

local PerkService = {}

-- Private

local log = Log.new("Perks")

local function percentOf(perk: Perk): number
	return math.floor(perk.boost * 100 + 0.5)
end

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		grantCoins = function(player: any, amount: number, reason: string): (number, string?)
			return EconomyService.grantCoins(player, amount, reason)
		end,
		notify = function(player: any, code: string, args: Types.NotifyArgs?, kind: Types.NotifyKind?)
			NetService.notify(player, code, args, kind)
		end,
		isMember = function(player: any): boolean
			return player:IsInGroupAsync(GROUP.id) -- IsInGroup is the deprecated name
		end,
		isMemberNow = function(player: any): boolean
			for _, group in GroupService:GetGroupsAsync(player.UserId) do
				if group.Id == GROUP.id then
					return true
				end
			end
			return false
		end,
		isSubscriber = function(player: any): boolean
			-- Roblox Plus; Premium (closed to new members since 2026-04-30) through its older property.
			return player.HasRobloxSubscription == true or player.MembershipType == Enum.MembershipType.Premium
		end,
		watchSubscriber = function(player: any, changed: () -> ()): () -> ()
			local plus = player:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(changed)
			local premium = player:GetPropertyChangedSignal("MembershipType"):Connect(changed)
			return function()
				plus:Disconnect()
				premium:Disconnect()
			end
		end,
		spawn = function(fn: (...any) -> ...any, ...: any)
			task.spawn(fn, ...)
		end,
		clock = os.clock,
	}
end

local deps: Deps = defaultDeps()
local has: { [number]: { [string]: boolean } } = {} -- userId -> perk name -> theirs, for the players here
local lastAsk: { [number]: number } = {} -- userId -> the clock of their last GroupCheck question
local stopWatch: { [number]: () -> () } = {} -- userId -> stops following their subscription

-- Remembers whether a player who is still here has a perk and shows it (the perk's attribute).
local function learn(player: any, name: string, theirs: boolean)
	local mine = has[player.UserId]
	if mine == nil then
		return -- left during the call
	end
	local perk = PERKS[name]
	mine[name] = theirs
	player:SetAttribute(perk.attr, if theirs then percentOf(perk) else 0)
end

-- A perk's once-per-account gift, for a player who has the perk and a READY profile. Returns the Coins given now (0:
-- not theirs, not ready, or given before). Never yields.
local function gift(player: any, name: string): number
	local mine = has[player.UserId]
	if mine == nil or mine[name] ~= true or deps.data.status(player) ~= STATUS_READY then
		return 0
	end
	local perk = PERKS[name]
	local ok, fresh = deps.data.mutate(player, function(profile: any): boolean
		local gifts = profile.gifts
		if type(gifts) ~= "table" then
			gifts = {}
			profile.gifts = gifts
		end
		if gifts[perk.giftKey] then
			return false -- given (anything but false or nothing counts as given: never twice)
		end
		gifts[perk.giftKey] = true
		return true
	end)
	if not ok or fresh ~= true then
		return 0
	end
	local amount = EconomyService.rewardCoins(deps.data.getProfile(player), perk.giftSqueezes)
	local coins, failure = deps.grantCoins(player, amount, perk.reason)
	if failure ~= nil then
		log:error(`user {player.UserId}: the {name} gift's Coins were not granted ({failure})`)
	end
	deps.data.requestSave(player, SAVE_SOON)
	local args: Types.NotifyArgs = { coins = Format.coins(coins), percent = percentOf(perk) }
	deps.notify(player, perk.notice, args, "success")
	log:info(`user {player.UserId} got the {name} gift: {coins} Coins`)
	return coins
end

-- Every gift the player can get now (a profile that became READY after the perks were known).
local function giftAll(player: any)
	for name in PERKS do
		gift(player, name)
	end
end

-- The join's question to Roblox about the group (its own thread).
local function askGroup(player: any)
	local ok, yes = pcall(deps.isMember, player)
	if not ok then
		log:warn(`IsInGroupAsync failed for user {player.UserId}:`, yes)
		return
	end
	learn(player, "group", yes == true)
	gift(player, "group")
end

-- The player's subscription as Roblox has it now (on join and on every change). A read that fails changes nothing.
local function readPlus(player: any)
	local ok, yes = pcall(deps.isSubscriber, player)
	if not ok then
		log:warn(`the subscription of user {player.UserId} could not be read:`, yes)
		return
	end
	learn(player, "plus", yes == true)
	gift(player, "plus")
end

-- Public

-- What the player's perks add to their pen pay (0 without one); PenService adds it to the Friend Boost.
function PerkService.penBoost(player: any): number
	local mine = has[player.UserId]
	local total = 0
	if mine ~= nil then
		for name, perk in PERKS do
			if mine[name] == true then
				total += perk.boost
			end
		end
	end
	return total
end

-- The GroupCheck RF (see the header). Yields only when it asks Roblox again.
function PerkService.check(player: any): any
	local userId: number = player.UserId
	local mine = has[userId]
	if mine == nil or mine.group ~= true then
		local now = deps.clock()
		local last = lastAsk[userId]
		if last ~= nil and now - last < GROUP.recheckSeconds then
			return NetService.err(CODE_WAIT)
		end
		lastAsk[userId] = now
		local ok, yes = pcall(deps.isMemberNow, player)
		if not ok then
			log:warn(`the group check failed for user {userId}:`, yes)
			return NetService.err(CODE_FAILED)
		end
		learn(player, "group", yes == true)
	end
	local now = has[userId]
	return NetService.ok({ member = now ~= nil and now.group == true, coins = gift(player, "group") })
end

-- Tests: other dependencies (nil = the real ones) and nobody remembered.
function PerkService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	for key, value in overrides or {} do
		fresh[key] = value
	end
	deps = fresh
	for _, stop in stopWatch do
		stop()
	end
	has = {}
	lastAsk = {}
	stopWatch = {}
end

-- Lifecycle

function PerkService.init()
	NetService.onInvoke(REMOTE, function(player: Player): any
		return PerkService.check(player)
	end)
	-- A player whose profile became READY after their perks were known gets the gifts then.
	deps.data.onLoaded(giftAll)
	deps.data.onStatusChanged(giftAll)
end

function PerkService.playerAdded(player: Player)
	local userId = player.UserId
	has[userId] = {}
	for name in PERKS do
		learn(player, name, false)
	end
	deps.spawn(askGroup, player)
	local ok, stop = pcall(deps.watchSubscriber, player, function()
		readPlus(player)
	end)
	if ok then
		stopWatch[userId] = stop
	else
		log:warn(`the subscription of user {userId} can't be followed:`, stop)
	end
	readPlus(player)
end

function PerkService.playerRemoving(player: Player)
	local userId = player.UserId
	local stop = stopWatch[userId]
	if stop then
		stop()
	end
	stopWatch[userId] = nil
	has[userId] = nil
	lastAsk[userId] = nil
end

return PerkService
