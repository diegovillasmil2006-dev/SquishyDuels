--!strict
-- PenService (server only). Pens3 phase 1 (work/pens3/PLAN.md, 2026-10-17): the pen of every player in the server pays
-- its Coins every second, and the one pen remote buys only the caller's own next spot (no remote takes a base, plot
-- or player id). Built from CapsuleService's patterns (its tick, pay, spend and buy; useDeps / reset; sessions).
-- * Config.Economy.Pen (Config/Pen) is checked by Config/ValidatePen in init: any problem stops with an error (the pen
--   is the Coin source of the game; the shipped table is pinned by ValidatePen_Test).
-- * The tick (start: every Pen.tickSeconds, step(dt) with the time that really passed): for each player in the server
--   with a READY profile, PenMath.payStep(carry, PenMath.rate(pen), dt) (at most Pen.maxTickSeconds of time at once)
--   and ONE EconomyService.grantCoins(p, coins, "pen") per player and tick, each player in its own pcall. The pen pays
--   no Grip. The carry (a part of a Coin) lives in this session only: it starts at 0 on join, time while not ready or
--   out of the server never pays here (the time away pays once on the next load, below).
-- * PenBuySpot(expectedPrice) (RF; Config.Net: 1 a second, one in flight), refusals in the CapsuleUnlock order: (1)
--   expectedPrice not whole Coins -> net.invalid; (2) no READY profile -> data.notReady; (3) PenMath.buyDecision ->
--   pen.max / pen.priceChanged (the price is compared, never charged); (4) a pending failed save, the server closing,
--   a restart pending, or less than Pen.buyCooldownSeconds since this player's last buy -> pen.paused; (5)
--   SD_DuelPhase ~= "" -> inventory.lockedInDuel; (6) EconomyService.trySpend(p, price, "pen") (else
--   economy.notEnoughCoins; "savePending" -> pen.paused). Then spots + 1 through DataService.mutate, nothing yielding
--   in between, the base redrawn and the `pen` field sent (BaseService.refresh + StateService.markDirty, deps.showPen),
--   a log line, and the awaited "now" save before the reply ok({pen, charged = true, savePending}). Every refusal
--   carries charged = false and writes nothing.
-- * EconomyService.SquishyGranted (a new squishy: its pen item was added in that grant's own step) redraws the base
--   and sends the `pen` field (showPen).
-- * Pens3 phase 4, coins while away: on DataService.Loaded, EconomyService.grantAway pays 5% of the pen's rate at the
--   last save for every second since it (PenMath.awayCoins; no limit, no idle rule) and stamps lastSeenAt in the same
--   step, so a second Loaded of the same profile pays nothing. A gift that paid goes to the owner's client as the
--   session field awayGift {coins, seconds} (StateService), which shows it once. This handler runs after
--   GripService's (it connects in an earlier init), whose welcome toasts read the loaded lastSeenAt.
-- * Pens3 phase 5 (copies, D1:254-258): a bought spot makes room in the Toy Box, so the buy drops queued gifts in
--   (EconomyService.dropGifts) before the reply's pen is copied; a load drops them in too. The free Frog gift
--   (Pen.frogGift, SIM:226): the tick asks EconomyService.grantGift(p, "frog", kind) once a session, frogGift.seconds
--   after the player joined, while the profile is READY; grantGift keeps it once per account (profile.gifts.frog).
--   Reading: "minute 3 of the first play" is minute 3 of the first session that lasts that long (play time is not
--   saved).
-- Every profile write goes through DataService.mutate (the data port). Dependencies are injectable (useDeps) so unit
-- tests run with fake profiles and players (plain tables); init() never yields; playerAdded / playerRemoving never
-- yield.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)
local ValidatePen = require(Shared.Config.ValidatePen)
local Validate = require(Shared.Util.Validate)

local Services = script.Parent
local BaseService = require(Services.BaseService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local NetService = require(Services.NetService)
local ShutdownService = require(Services.ShutdownService)
local StateService = require(Services.StateService)

-- Types

export type Deps = {
	statusOf: (player: any) -> string, -- DataService status: "loading" | "ready" | "offline" | "readonly"
	profileOf: (player: any) -> any, -- the profile table in memory (or nil); read only
	mutate: (player: any, fn: (profile: any) -> any) -> (boolean, any), -- DataService.mutate (READY sessions only)
	savePending: (player: any) -> boolean,
	isClosing: () -> boolean,
	isRestartPending: () -> boolean,
	duelPhaseOf: (player: any) -> string, -- SD_DuelPhase ("" outside a match)
	trySpend: (player: any, amount: number, reason: string) -> (boolean, string?),
	grantCoins: (player: any, amount: number, reason: string) -> number, -- the Coins really added
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	clock: () -> number, -- os.clock: the buy cooldown
	-- BaseService.refresh and StateService.markDirty(p, "pen"): the player's base and client show their pen again
	showPen: (player: any) -> (),
	grantAway: (player: any) -> (number, number), -- EconomyService.grantAway: (Coins added, seconds counted)
	setAwayGift: (player: any, gift: Types.AwayGift) -> (), -- StateService.setSessionField(p, "awayGift", gift)
	dropGifts: (player: any) -> number, -- pens3 phase 5: EconomyService.dropGifts (how many dropped in)
	grantGift: (player: any, key: string, kind: string) -> boolean, -- pens3 phase 5: EconomyService.grantGift
}

-- What the remote answers: NetService.ok(Types.PenResult) or NetService.err(reason, false).
export type Reply = { ok: boolean, data: Types.PenResult?, reason: string?, charged: boolean? }

type Session = {
	carry: number, -- the part of a Coin the tick owes (PenMath.payStep)
	boughtAt: number, -- deps.clock() of the last spot bought (the cooldown)
	joinedAt: number, -- pens3 phase 5: deps.clock() at playerAdded (the Frog gift's time)
	frogAsked: boolean, -- pens3 phase 5: the Frog gift was asked for this session
}

-- Constants

local PEN = Config.Economy.Pen
local FROG_KEY = "frog" -- profile.gifts.frog
local COIN_REASON = "pen"
local REMOTE_BUY = "PenBuySpot"
local FIELD_PEN = "pen"
local FIELD_AWAY_GIFT = "awayGift"
local STATUS_READY = "ready"
local ATTR_PHASE = "SD_DuelPhase"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_PAUSED = "pen.paused"
local CODE_IN_DUEL = "inventory.lockedInDuel"
local CODE_NOT_ENOUGH = "economy.notEnoughCoins"

-- Module table

local PenService = {}

-- Private

local log = Log.new("Pen")
local sessions: { [any]: Session } = {}
local loopThread: thread? = nil

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

local function duelPhaseAttribute(player: any): string
	if typeof(player) ~= "Instance" then
		return ""
	end
	local phase = (player :: Instance):GetAttribute(ATTR_PHASE)
	return if type(phase) == "string" then phase else ""
end

local function defaultDeps(): Deps
	return {
		statusOf = function(player: any): string
			return StateService.dataPort().status(player)
		end,
		profileOf = function(player: any): any
			return StateService.dataPort().getProfile(player)
		end,
		mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
			return StateService.dataPort().mutate(player, fn)
		end,
		savePending = function(player: any): boolean
			return StateService.dataPort().savePending(player)
		end,
		isClosing = function(): boolean
			return ShutdownService.isClosing()
		end,
		isRestartPending = function(): boolean
			return ShutdownService.isRestartPending()
		end,
		duelPhaseOf = duelPhaseAttribute,
		trySpend = function(player: any, amount: number, reason: string): (boolean, string?)
			return EconomyService.trySpend(player, amount, reason)
		end,
		grantCoins = function(player: any, amount: number, reason: string): number
			local added = EconomyService.grantCoins(player, amount, reason)
			return added
		end,
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		clock = os.clock,
		showPen = function(player: any)
			BaseService.refresh(player)
			StateService.markDirty(player, FIELD_PEN)
		end,
		grantAway = function(player: any): (number, number)
			return EconomyService.grantAway(player)
		end,
		setAwayGift = function(player: any, gift: Types.AwayGift)
			StateService.setSessionField(player, FIELD_AWAY_GIFT, gift)
		end,
		dropGifts = function(player: any): number
			return EconomyService.dropGifts(player)
		end,
		grantGift = function(player: any, key: string, kind: string): boolean
			return EconomyService.grantGift(player, key, kind)
		end,
	}
end

local deps: Deps = defaultDeps()

-- The pen of a READY profile (the only state that pays or changes), or nil.
local function readyPen(player: any): Types.PenState?
	if deps.statusOf(player) ~= STATUS_READY then
		return nil
	end
	local profile = deps.profileOf(player)
	local pen = if type(profile) == "table" then profile.pen else nil
	return if type(pen) == "table" then pen else nil
end

-- One tick of one player's pen (see the header).
local function pay(player: any, session: Session, dt: number)
	local pen = readyPen(player)
	if pen == nil then
		return
	end
	local coins, carry = PenMath.payStep(session.carry, PenMath.rate(pen), dt)
	session.carry = carry
	if coins > 0 then
		deps.grantCoins(player, coins, COIN_REASON)
	end
	-- Pens3 phase 5: the Frog gift, once a session (see the header).
	if not session.frogAsked and deps.clock() - session.joinedAt >= PEN.frogGift.seconds then
		session.frogAsked = true
		if deps.grantGift(player, FROG_KEY, PEN.frogGift.kind) then
			log:info(`user {userIdOf(player)} got the {PEN.frogGift.kind} gift`)
		end
	end
end

-- (4)-(6) of a buy: paused, in a duel, then the spend. Returns a refusal code, or nil once the Coins are taken.
local function spend(player: any, price: number): string?
	local session = sessions[player]
	local cooling = session ~= nil and deps.clock() - session.boughtAt < PEN.buyCooldownSeconds
	if cooling or deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return CODE_PAUSED
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL
	end
	local spent, why = deps.trySpend(player, price, COIN_REASON)
	if spent then
		return nil
	end
	return if why == "savePending"
		then CODE_PAUSED
		elseif why == "notReady" then CODE_NOT_READY
		elseif why == "notEnoughCoins" then CODE_NOT_ENOUGH
		else CODE_INVALID
end

-- Public: the tick ------------------------------------------------------------------------------------------------

-- Pays every session's pen for `dt` seconds (the loop calls it every tick).
function PenService.step(dt: number)
	for player, session in sessions do
		local ok, err = pcall(function(): any
			pay(player, session, dt)
			return nil
		end)
		if not ok then
			log:error(`pen tick failed for user {userIdOf(player)}:`, err)
		end
	end
end

-- Public: the remote (see the header for the order of the checks) ----------------------------------------------------

function PenService.buy(player: any, expectedPrice: any): Reply
	if Validate.coins(expectedPrice) == nil then
		return NetService.err(CODE_INVALID, false)
	end
	local pen = readyPen(player)
	if pen == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local decision, refused = PenMath.buyDecision(pen, expectedPrice)
	if decision == nil then
		return NetService.err(refused or CODE_INVALID, false)
	end
	local spot, price = decision.spot, decision.price
	local spendRefused = spend(player, price)
	if spendRefused ~= nil then
		return NetService.err(spendRefused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		profile.pen.spots = math.max(profile.pen.spots, spot)
		return true
	end)
	if not written then
		-- Cannot happen without a yield after the spend (the session was ready a moment ago); logged loudly.
		log:error(`user {userIdOf(player)}: pen spot {spot} was paid ({price} Coins) but could not be written`)
		return NetService.err(CODE_NOT_READY, false)
	end
	local session = sessions[player]
	if session ~= nil then
		session.boughtAt = deps.clock()
	end
	log:info(`user {userIdOf(player)} bought pen spot {spot} for {price} Coins`)
	deps.dropGifts(player) -- pens3 phase 5: the new spot makes room for a waiting gift
	deps.showPen(player)
	local data: Types.PenResult = {
		pen = TableUtil.deepCopy(deps.profileOf(player).pen), -- copied before the save yields
		charged = true,
		savePending = false,
	}
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

-- Public: coins while away (see the header) ---------------------------------------------------------------------------

-- DataService.Loaded: the Coins for the time away, and the gift for the client when they paid.
function PenService.loaded(player: any)
	local coins, seconds = deps.grantAway(player)
	if coins > 0 then
		deps.setAwayGift(player, { coins = coins, seconds = seconds })
		log:info(`user {userIdOf(player)} got {coins} Coins for {seconds} s away`)
	end
	deps.dropGifts(player) -- pens3 phase 5: gifts that waited for room
end

-- Public: tests -----------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function PenService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session (tests; not called by the bootstrap).
function PenService.reset()
	table.clear(sessions)
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function PenService.init()
	local problems = ValidatePen(Config)
	if #problems > 0 then
		error(`[SD][Pen] Config.Economy.Pen is invalid: {table.concat(problems, "; ")}`)
	end
	NetService.onInvoke(REMOTE_BUY, function(player: Player, expectedPrice: any): any
		return PenService.buy(player, expectedPrice)
	end)
	-- A new squishy (a box, the shop, a Studio grant): its pen item came in the same grant step; show it.
	EconomyService.SquishyGranted:connect(function(player: Player)
		deps.showPen(player)
	end)
	StateService.dataPort().onLoaded(function(player: any)
		PenService.loaded(player)
	end)
end

function PenService.start()
	if loopThread ~= nil then
		return
	end
	loopThread = task.spawn(function()
		while true do
			PenService.step(task.wait(PEN.tickSeconds))
		end
	end)
end

function PenService.playerAdded(player: Player)
	if sessions[player] == nil then
		sessions[player] = { carry = 0, boughtAt = -math.huge, joinedAt = deps.clock(), frogAsked = false }
	end
end

function PenService.playerRemoving(player: Player)
	sessions[player] = nil
end

return PenService
