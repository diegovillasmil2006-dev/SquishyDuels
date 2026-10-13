--!strict
-- CapsuleService (server only). Lobby bases spec 2026-10-11 §5.1-§5.3, §6; big-number progression spec 2026-10-12
-- §3-§7, §10; build plan Phase 3. The capsules of every player in the server squeeze on their own and pay, and the
-- three capsule remotes change only the caller's own capsules (no remote takes a base, plot or player id).
-- * The tick (start: every Config.Grip.Capsule.tickSeconds, step(dt) with the time that really passed): for each
--   player in the server with a READY profile, every capsule that holds a squishy moves dt / CapsuleMath.seconds(level)
--   of a squeeze forward; each full squeeze pays CapsuleMath.capsuleCoins(squishy, level) Coins (one
--   EconomyService.grantCoins per player and tick, reason "capsule") and CapsuleMath.power(level) Grip
--   (GripService.addFromCapsule: never doubled, lobby spec §5.4), and adds 1 to the Player attribute
--   SD_Squeezes<slot> (the client animates the capsule from it, Phase 5). The progress lives in this session only: no
--   pay for time out of the server (no offline pay), it starts at 0 on join, and an empty capsule keeps none.
-- * Home taps, push(p, rootPosition) (SqueezeService, on every paid own squeeze): when that server-side root stands in
--   the caller's own plot (BaseService.plotOf + WorldLayout.inPlot), every capsule that holds a squishy moves
--   Capsule.tapPush of a squeeze forward (the next tick pays it). Anywhere else nothing happens.
-- * CapsuleUpgrade(slot, expectedPrice) / CapsuleUnlock(slot, expectedPrice) (RFs; Config.Net: 1 a second, one in
--   flight), in GripService.upgradeTrainer's order: (2) the argument range, then CapsuleMath.upgradeDecision /
--   unlockDecision with (3) the ready profile (data.notReady) checked between them (an unlock of a slot that is already
--   open is a replay: ok, charged = false); (8) a pending failed save, the server closing or a restart pending ->
--   capsule.paused; (9) SD_DuelPhase ~= "" -> inventory.lockedInDuel; (10) EconomyService.trySpend(p, cost,
--   "capsule") (else economy.notEnoughCoins; "savePending" -> capsule.paused), then the capsule's next level or the
--   new slot (an empty Lv 1 capsule) through DataService.mutate, nothing yielding in between, and the awaited "now"
--   save before the reply ok({capsules, charged = true, savePending}).
-- * CapsuleSet(slot, squishyId) (RF, same limits): (2) slot 1..#slotPrices and a Catalog squishy, else net.invalid;
--   (3) data.notReady; (4) that squishy already in that capsule -> ok, nothing changes; the slot is open, else
--   capsule.locked; the squishy is owned, else inventory.notOwned; (9) inventory.lockedInDuel; then it goes in (a
--   capsule that held it is left empty: one capsule per squishy, spec 2026-10-12 §6) with a "soon" save; reply
--   ok({capsules, charged = false, savePending}).
-- Every refusal carries charged = false. Every profile write goes through DataService.mutate (the data port).
-- Phase 4: every capsule change (a bought level or slot, a squishy set) redraws the caller's own base at once
-- (BaseService.refresh, deps.showCapsules); a refusal, a replay or a squishy already there draws nothing.
-- Dependencies are injectable (useDeps) so unit tests run with fake profiles and players (plain tables); init() never
-- yields; playerAdded / playerRemoving never yield.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local TableUtil = require(Shared.Util.TableUtil)
local Types = require(Shared.Types)
local WorldLayout = require(Shared.World.WorldLayout)

local Services = script.Parent
local BaseService = require(Services.BaseService)
local DataService = require(Services.DataService)
local EconomyService = require(Services.EconomyService)
local GripService = require(Services.GripService)
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
	gripLevelOf: (player: any) -> number, -- GripService.levelOf
	plotOf: (player: any) -> number?, -- BaseService.plotOf
	trySpend: (player: any, amount: number, reason: string) -> (boolean, string?),
	grantCoins: (player: any, amount: number, reason: string) -> number, -- the Coins really added
	addGrip: (player: any, amount: number) -> number, -- GripService.addFromCapsule
	saveNow: (player: any) -> boolean, -- DataService.saveNowAsync (yields)
	requestSave: (player: any, reason: string) -> (),
	setAttribute: (player: any, name: string, value: number) -> (),
	showCapsules: (player: any) -> (), -- BaseService.refresh: the player's base shows their capsules again
}

-- What the remotes answer: NetService.ok(Types.CapsuleResult) or NetService.err(reason, false).
export type Reply = { ok: boolean, data: Types.CapsuleResult?, reason: string?, charged: boolean? }

type Session = {
	progress: { [any]: number }, -- slot -> part of a squeeze done
	squeezes: { [any]: number }, -- slot -> squeezes this session (SD_Squeezes<slot>)
}

-- Constants

local CAPSULE = Config.Grip.Capsule
local COIN_REASON = "capsule"
local STATUS_READY = "ready"
local ATTR_PHASE = "SD_DuelPhase"
local ATTR_SQUEEZES = "SD_Squeezes" -- .. slot
local SAVE_SOON = "soon"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_PAUSED = "capsule.paused"
local CODE_LOCKED = "capsule.locked"
local CODE_IN_DUEL = "inventory.lockedInDuel"
local CODE_NOT_OWNED = "inventory.notOwned"
local CODE_NOT_ENOUGH = "economy.notEnoughCoins"

-- Module table

local CapsuleService = {}

-- Private

local log = Log.new("Capsule")
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
		gripLevelOf = function(player: any): number
			return GripService.levelOf(player)
		end,
		plotOf = function(player: any): number?
			return BaseService.plotOf(player)
		end,
		trySpend = function(player: any, amount: number, reason: string): (boolean, string?)
			return EconomyService.trySpend(player, amount, reason)
		end,
		grantCoins = function(player: any, amount: number, reason: string): number
			local added = EconomyService.grantCoins(player, amount, reason)
			return added
		end,
		addGrip = function(player: any, amount: number): number
			return GripService.addFromCapsule(player, amount)
		end,
		saveNow = function(player: any): boolean
			return DataService.saveNowAsync(player)
		end,
		requestSave = function(player: any, reason: string)
			StateService.dataPort().requestSave(player, reason)
		end,
		setAttribute = function(player: any, name: string, value: number)
			if typeof(player) == "Instance" then
				(player :: Instance):SetAttribute(name, value)
			end
		end,
		showCapsules = function(player: any)
			BaseService.refresh(player)
		end,
	}
end

local deps: Deps = defaultDeps()

-- The capsules of a READY profile (the only state that pays or changes), or nil.
local function readyCapsules(player: any): Types.CapsulesState?
	if deps.statusOf(player) ~= STATUS_READY then
		return nil
	end
	local profile = deps.profileOf(player)
	local capsules = if type(profile) == "table" then profile.capsules else nil
	if type(capsules) ~= "table" or type(capsules.list) ~= "table" or type(capsules.slots) ~= "number" then
		return nil
	end
	return capsules
end

-- The seconds between two squeezes of a capsule that squeezes (a known level and a squishy), else nil.
local function intervalOf(capsule: any): number?
	if type(capsule) ~= "table" or not Catalog.isValidId(capsule.squishyId) then
		return nil
	end
	return CapsuleMath.seconds(capsule.level)
end

-- The reply data: a copy of the caller's capsules as they are now.
local function result(player: any, charged: boolean, savePending: boolean): Types.CapsuleResult
	return {
		capsules = TableUtil.deepCopy(deps.profileOf(player).capsules),
		charged = charged,
		savePending = savePending,
	}
end

-- One tick of one player's capsules (see the header).
local function pay(player: any, session: Session, dt: number)
	local capsules = readyCapsules(player)
	if capsules == nil then
		return
	end
	local coins = 0
	for slot, capsule in capsules.list do
		local interval = intervalOf(capsule)
		if interval == nil then
			session.progress[slot] = nil
			continue
		end
		local progress = (session.progress[slot] or 0) + dt / interval
		local squeezes = math.floor(progress)
		session.progress[slot] = progress - squeezes
		if squeezes > 0 then
			coins += squeezes * CapsuleMath.capsuleCoins(capsule.squishyId, capsule.level)
			local power = CapsuleMath.power(capsule.level) :: number
			for _ = 1, squeezes do
				deps.addGrip(player, power) -- one Grip event per squeeze, each under maxGripPerEvent
			end
			session.squeezes[slot] = (session.squeezes[slot] or 0) + squeezes
			deps.setAttribute(player, ATTR_SQUEEZES .. tostring(slot), session.squeezes[slot])
		end
	end
	if coins > 0 then
		deps.grantCoins(player, coins, COIN_REASON)
	end
end

-- (8)-(10) of a purchase: paused, in a duel, then the spend. Returns a refusal code, or nil once the Coins are taken.
local function spend(player: any, cost: number): string?
	if deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return CODE_PAUSED
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL
	end
	local spent, why = deps.trySpend(player, cost, COIN_REASON)
	if spent then
		return nil
	end
	return if why == "savePending"
		then CODE_PAUSED
		elseif why == "notReady" then CODE_NOT_READY
		elseif why == "notEnoughCoins" then CODE_NOT_ENOUGH
		else CODE_INVALID
end

-- A checked purchase: the spend, then `write(capsules)` on the live capsules, then the awaited "now" save.
local function buy(player: any, cost: number, what: string, write: (capsules: any) -> ()): Reply
	local refused = spend(player, cost)
	if refused ~= nil then
		return NetService.err(refused, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		write(profile.capsules)
		return true
	end)
	if not written then
		-- Cannot happen without a yield after the spend (the session was ready a moment ago); logged loudly.
		log:error(`user {userIdOf(player)}: {what} was paid ({cost} Coins) but could not be written`)
		return NetService.err(CODE_NOT_READY, false)
	end
	log:info(`user {userIdOf(player)} bought {what} for {cost} Coins`)
	deps.showCapsules(player)
	local data = result(player, true, false) -- copied before the save yields
	data.savePending = not deps.saveNow(player)
	return NetService.ok(data)
end

-- Public: the tick and the home taps -------------------------------------------------------------------------------

-- Moves every session's capsules `dt` seconds forward and pays the full squeezes (the loop calls it every tick).
function CapsuleService.step(dt: number)
	for player, session in sessions do
		local ok, err = pcall(function(): any
			pay(player, session, dt)
			return nil
		end)
		if not ok then
			log:error(`capsule tick failed for user {userIdOf(player)}:`, err)
		end
	end
end

-- A paid own squeeze at `rootPosition` (server-side): pushes the caller's capsules when it stands in their own plot.
-- Returns true when it pushed.
function CapsuleService.push(player: any, rootPosition: Vector3): boolean
	local session = sessions[player]
	local plot = deps.plotOf(player)
	if session == nil or plot == nil or not WorldLayout.inPlot(plot, rootPosition) then
		return false
	end
	local capsules = readyCapsules(player)
	if capsules == nil then
		return false
	end
	for slot, capsule in capsules.list do
		if intervalOf(capsule) ~= nil then
			session.progress[slot] = (session.progress[slot] or 0) + CAPSULE.tapPush
		end
	end
	return true
end

-- Public: the remotes (see the header for the order of the checks) --------------------------------------------------

function CapsuleService.upgrade(player: any, slot: any, expectedPrice: any): Reply
	local capsules = readyCapsules(player)
	local decision = CapsuleMath.upgradeDecision(capsules, slot, expectedPrice, deps.gripLevelOf(player))
	if decision.reason == CODE_INVALID then
		return NetService.err(CODE_INVALID, false)
	end
	if capsules == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	if decision.kind ~= "buy" then
		return NetService.err(decision.reason or CODE_INVALID, false)
	end
	local level = capsules.list[slot].level
	return buy(player, decision.cost, `capsule {slot} Lv {level + 1}`, function(live: any)
		local capsule = live.list[slot]
		capsule.level = math.max(capsule.level, level + 1)
	end)
end

function CapsuleService.unlock(player: any, slot: any, expectedPrice: any): Reply
	local capsules = readyCapsules(player)
	local decision = CapsuleMath.unlockDecision(capsules, slot, expectedPrice)
	if decision.reason == CODE_INVALID then
		return NetService.err(CODE_INVALID, false)
	end
	if capsules == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	if decision.kind == "replay" then
		return NetService.ok(result(player, false, deps.savePending(player)))
	end
	if decision.kind ~= "buy" then
		return NetService.err(decision.reason or CODE_INVALID, false)
	end
	return buy(player, decision.cost, `capsule slot {slot}`, function(live: any)
		live.slots = math.max(live.slots, slot)
		live.list[slot] = live.list[slot] or { level = 1 } -- a new capsule starts empty at Lv 1 (spec 2026-10-12 §7)
	end)
end

function CapsuleService.set(player: any, slot: any, squishyId: any): Reply
	if CapsuleMath.slotPrice(slot) == nil or not Catalog.isValidId(squishyId) then
		return NetService.err(CODE_INVALID, false)
	end
	local capsules = readyCapsules(player)
	if capsules == nil then
		return NetService.err(CODE_NOT_READY, false)
	end
	local capsule = if slot <= capsules.slots then capsules.list[slot] else nil
	if type(capsule) == "table" and capsule.squishyId == squishyId then
		return NetService.ok(result(player, false, deps.savePending(player))) -- already there: nothing changes
	end
	if type(capsule) ~= "table" then
		return NetService.err(CODE_LOCKED, false)
	end
	local owned = deps.profileOf(player).owned
	if type(owned) ~= "table" or owned[squishyId] == nil then
		return NetService.err(CODE_NOT_OWNED, false)
	end
	if deps.duelPhaseOf(player) ~= "" then
		return NetService.err(CODE_IN_DUEL, false)
	end
	local written = deps.mutate(player, function(profile: any): boolean
		for _, other in profile.capsules.list do
			if type(other) == "table" and other.squishyId == squishyId then
				other.squishyId = nil -- one capsule per squishy: it moves
			end
		end
		profile.capsules.list[slot].squishyId = squishyId
		return true
	end)
	if not written then
		return NetService.err(CODE_NOT_READY, false)
	end
	deps.showCapsules(player)
	deps.requestSave(player, SAVE_SOON)
	return NetService.ok(result(player, false, deps.savePending(player)))
end

-- Public: tests -----------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function CapsuleService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session (tests; not called by the bootstrap).
function CapsuleService.reset()
	table.clear(sessions)
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function CapsuleService.init()
	NetService.onInvoke("CapsuleUpgrade", function(player: Player, slot: any, expectedPrice: any): any
		return CapsuleService.upgrade(player, slot, expectedPrice)
	end)
	NetService.onInvoke("CapsuleUnlock", function(player: Player, slot: any, expectedPrice: any): any
		return CapsuleService.unlock(player, slot, expectedPrice)
	end)
	NetService.onInvoke("CapsuleSet", function(player: Player, slot: any, squishyId: any): any
		return CapsuleService.set(player, slot, squishyId)
	end)
end

function CapsuleService.start()
	if loopThread ~= nil then
		return
	end
	loopThread = task.spawn(function()
		while true do
			CapsuleService.step(task.wait(CAPSULE.tickSeconds))
		end
	end)
end

function CapsuleService.playerAdded(player: Player)
	if sessions[player] == nil then
		sessions[player] = { progress = {}, squeezes = {} }
	end
end

function CapsuleService.playerRemoving(player: Player)
	sessions[player] = nil
end

return CapsuleService
