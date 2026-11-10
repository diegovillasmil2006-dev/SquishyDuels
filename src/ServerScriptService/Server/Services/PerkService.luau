--!strict
-- PerkService (server only). Big job item 4 (2026-11-10; the owner: "A bonus for joining my Roblox group (DIJAY
-- Studios)"): the perk for members of the game's owner group (Config.Bonus.Group). LihFolk vault "Roblox Communities
-- as Your On-Platform Hub": a modest perk for members, membership checked on the server with the async API, kept for
-- the visit, and checked again only when the player asks.
-- * On join the server asks Roblox once (Player:IsInGroupAsync, in its own thread; a call that fails counts as not a
--   member for now).
-- * A member's pen pays penBoost more: penBoost(p) is what PenService adds to the Friend Boost. The Player attribute
--   SD_GroupBoost holds it in whole percent (0 = not a member, or not known yet) for the client's pill and Settings row.
-- * The gift: giftSqueezes x the squeeze value in Coins (reason "group"), once per account (profile.gifts.group, set
--   in the same step), a "soon" save and the toast bonus.groupGift. It is given as soon as a member's profile is READY:
--   tried after every answer from Roblox and on every profile load or status change; gift() never yields.
-- * GroupCheck (RF, no arguments): "I joined" (the client calls it after its join prompt). A player not known as a
--   member is asked about again with a fresh call (GroupService:GetGroupsAsync: IsInGroupAsync keeps its first answer
--   for the whole visit), at most once every recheckSeconds (else net.rateLimited). Replies ok { member, coins }
--   (coins = the gift, when this call gave it).
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
	spawn: (fn: (...any) -> ...any, ...any) -> (),
	clock: () -> number, -- os.clock: the re-check spacing
}

-- Constants

local GROUP = Bonus.Group
local REMOTE = "GroupCheck"
local ATTR_BOOST = "SD_GroupBoost"
local BOOST_PERCENT = math.floor(GROUP.penBoost * 100 + 0.5)
local GIFT_KEY = "group" -- profile.gifts.group
local STATUS_READY = "ready"
local COIN_REASON = "group"
local SAVE_SOON = "soon"
local NOTICE_GIFT = "bonus.groupGift"
local CODE_WAIT = "net.rateLimited"
local CODE_FAILED = "error.generic"

-- Module table

local PerkService = {}

-- Private

local log = Log.new("Perks")

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
		spawn = function(fn: (...any) -> ...any, ...: any)
			task.spawn(fn, ...)
		end,
		clock = os.clock,
	}
end

local deps: Deps = defaultDeps()
local members: { [number]: boolean } = {} -- userId -> a member, for the players here
local lastAsk: { [number]: number } = {} -- userId -> the clock of their last GroupCheck question

-- Remembers Roblox's answer for a player who is still here and shows it (SD_GroupBoost).
local function learn(player: any, member: boolean)
	local userId = player.UserId
	if members[userId] == nil then
		return -- left during the call
	end
	members[userId] = member
	player:SetAttribute(ATTR_BOOST, if member then BOOST_PERCENT else 0)
end

-- The once-per-account gift of a member whose profile is READY. Returns the Coins given now (0: not a member, not
-- ready, or given before). Never yields.
local function gift(player: any): number
	if members[player.UserId] ~= true or deps.data.status(player) ~= STATUS_READY then
		return 0
	end
	local ok, fresh = deps.data.mutate(player, function(profile: any): boolean
		local gifts = profile.gifts
		if type(gifts) ~= "table" then
			gifts = {}
			profile.gifts = gifts
		end
		if gifts[GIFT_KEY] then
			return false -- given (anything but false or nothing counts as given: never twice)
		end
		gifts[GIFT_KEY] = true
		return true
	end)
	if not ok or fresh ~= true then
		return 0
	end
	local amount = EconomyService.rewardCoins(deps.data.getProfile(player), GROUP.giftSqueezes)
	local coins, failure = deps.grantCoins(player, amount, COIN_REASON)
	if failure ~= nil then
		log:error(`user {player.UserId}: the group gift's Coins were not granted ({failure})`)
	end
	deps.data.requestSave(player, SAVE_SOON)
	local args: Types.NotifyArgs = { coins = Format.coins(coins), percent = BOOST_PERCENT }
	deps.notify(player, NOTICE_GIFT, args, "success")
	log:info(`user {player.UserId} got the group gift: {coins} Coins`)
	return coins
end

-- The join's question to Roblox (its own thread).
local function ask(player: any)
	local ok, yes = pcall(deps.isMember, player)
	if not ok then
		log:warn(`IsInGroupAsync failed for user {player.UserId}:`, yes)
		return
	end
	learn(player, yes == true)
	gift(player)
end

-- Public

-- What a member's pen pay grows by (0 for anyone else); PenService adds it to the Friend Boost.
function PerkService.penBoost(player: any): number
	return if members[player.UserId] == true then GROUP.penBoost else 0
end

-- The GroupCheck RF (see the header). Yields only when it asks Roblox again.
function PerkService.check(player: any): any
	local userId: number = player.UserId
	if members[userId] ~= true then
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
		learn(player, yes == true)
	end
	return NetService.ok({ member = members[userId] == true, coins = gift(player) })
end

-- Tests: other dependencies (nil = the real ones) and nobody remembered.
function PerkService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	for key, value in overrides or {} do
		fresh[key] = value
	end
	deps = fresh
	members = {}
	lastAsk = {}
end

-- Lifecycle

function PerkService.init()
	NetService.onInvoke(REMOTE, function(player: Player): any
		return PerkService.check(player)
	end)
	-- A member whose profile became READY after Roblox answered gets the gift then.
	deps.data.onLoaded(gift)
	deps.data.onStatusChanged(gift)
end

function PerkService.playerAdded(player: Player)
	members[player.UserId] = false
	player:SetAttribute(ATTR_BOOST, 0)
	deps.spawn(ask, player)
end

function PerkService.playerRemoving(player: Player)
	members[player.UserId] = nil
	lastAsk[player.UserId] = nil
end

return PerkService
