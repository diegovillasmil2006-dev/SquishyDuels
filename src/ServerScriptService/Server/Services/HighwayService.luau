--!strict
-- HighwayService (server only). Pens3 phase 13 (2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's
-- corrections, work/pens3/p13v2/NOTES.md): the throw for distance from the launch deck. The server decides everything;
-- Shared/HighwayMath has the math, Config.Economy.Highway every number (checked by Config/ValidateHighway in init: any
-- problem stops with an error, like PenService's).
-- * One open throw area (owner 2026-10-18: "it should be a general area where they walk up and everybody can throw";
--   2026-10-15: "One big launch area where everyone throws at the same time, with no waiting or queue"): anyone whose
--   server-side character root is inside WorldLayout.Highway.throwArea (areaMarginStuds bigger) may throw, everyone at
--   once; no spots, no queue. The only pacing is one throw in flight per player.
-- * HighwayThrow(clientTime) (RF; Config.Net 14 a second, burst 30: the client sends every THROW press in the area, the
--   presses during its own flight too, so the auto-clicker check sees the real rhythm; one in flight is this service's
--   own check), refusals in PenBuySpot's order: (1) clientTime not a finite number -> net.invalid (it is never trusted:
--   no timing reads it); (2) AutoClickService.checkThrow first for every arrival (its reason: highway.autoClick, the
--   calm warning of a catch, or highway.tooFast during its pause; owner 2026-10-16 "punishes step by step"); (3) no
--   READY profile -> data.notReady; (4) the decision: a throw still in flight -> highway.inFlight (answered at once,
--   nothing written: the client's presses during a flight end here); no living character root in the throw area ->
--   highway.notInArea; (5) a pending failed save, the server closing or a restart pending -> highway.paused; (6)
--   SD_DuelPhase ~= "" -> inventory.lockedInDuel. Every refusal carries charged = false and writes nothing.
--   P13v3 (owner 2026-10-18: "Yes, above 20 a second"): HighwayThrow(clientTime, fastSeconds): fastSeconds (the
--   client's speed report, Shared/PressSpeed; a Net-checked integer) goes to checkThrow only (its speed rule; a catch
--   answers highway.superFast); nothing else reads it.
-- * A throw: power = HighwayMath.power(GripService.levelOf) (phase 14 multiplies the gear in), the landing
--   HighwayMath.landing(power) and its biome b, the flight HighwayMath.flight(studs).total (the player's next throw
--   waits for it, less inFlightGraceSeconds). It pays in full (owner 2026-10-16: "No daily limits on squeezes or
--   throwing"; no time share, no cap): HighwayMath.landingCoins(SV, studs) Coins with the "highway" reason (p13v3,
--   owner 2026-10-18: by distance, farther pays more) and
--   GripService.addFromHighway(pay.grip). Then ONE mutate when something saved changes: highway.best and
--   highway.biome rise (only up: HighwayMath.reached, 8 = the Golden Gates), and a Food Bag's food (below). The
--   biome gifts of every biome this throw reaches first, once each (the saved biome only rises, so they are never
--   given twice), through EconomyService.grantSquishy(p, kind, "grant", true): a full Toy Box queues them (pens3 phase
--   5). The `highway` (and `food`) fields sent, a "soon" save (reading: a landing only grants, nothing is spent, so
--   no awaited "now" save: one per throw would wait on the DataStore's 6 s rule for one key every few seconds and hold
--   the throw back; PenPlace / Feed's reading), and the reply ok(Types.HighwayResult, charged = false).
-- * The Food Bag (V3:185, SIM:239): the flight time of paid throws adds up in the session; every foodBag.seconds of it
--   the throw that crosses the line also gives HighwayMath.foodBag(pen, SV) (the weakest placed squishy's band food,
--   at least 1 piece, at most Food.maxPieces held; the reply names the pieces that fit). Time not thrown never counts
--   (an idle player on the deck earns none); a bag that finds no food (nothing placed, or past the last band) or no
--   room (the stock full) is skipped.
-- * The launch board (owner 2026-10-15: "The launch gate board shows the last throws and the server best"): the last
--   WorldLayout.Highway.boardRows throws of anyone in the server, newest first (the thrower's display name and the
--   distance), and the server best (this server's farthest landing), written by the server on the board's live lines
--   (deps.writeBoard: every SD_LaunchBoard's TextLabels by name; they replicate to everyone) after each landing;
--   start() writes the empty board (Strings highway.board.empty on the first row). The server's own memory: a new
--   server starts empty.
-- Dependencies are injectable (useDeps) so unit tests run with fake profiles and players (plain tables); init() never
-- yields; playerAdded / playerRemoving never yield.

-- Services

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local HighwayMath = require(Shared.HighwayMath)
local Log = require(Shared.Util.Log)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)
local ValidateHighway = require(Shared.Config.ValidateHighway)
local WorldLayout = require(Shared.World.WorldLayout)

local Services = script.Parent
local AutoClickService = require(Services.AutoClickService)
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
	clock: () -> number, -- os.clock: the flights
	serverNow: () -> number, -- Workspace:GetServerTimeNow(): the reply's landsAt
	rootOf: (player: any) -> Vector3?, -- the living character's HumanoidRootPart position (server side)
	gripLevel: (player: any) -> number, -- GripService.levelOf
	grantCoins: (player: any, amount: number, reason: string) -> number, -- the Coins really added
	addGrip: (player: any, squeezes: number) -> number, -- GripService.addFromHighway
	grantSquishy: (player: any, kind: string) -> boolean, -- EconomyService.grantSquishy(p, kind, "grant", true)
	checkThrow: (player: any, now: number, fastSeconds: number?) -> string?, -- AutoClickService.checkThrow
	requestSave: (player: any, reason: string) -> (),
	markDirty: (player: any, field: string) -> (), -- StateService.markDirty
	nameOf: (player: any) -> string, -- the board's name: the player's DisplayName
	writeBoard: (lines: { [string]: string }) -> (), -- the launch board's live lines, by name
}

-- What the remote answers: NetService.ok(Types.HighwayResult) or NetService.err(reason, false).
export type Reply = { ok: boolean, data: Types.HighwayResult?, reason: string?, charged: boolean? }

type Session = {
	flyingUntil: number, -- deps.clock() from when the next throw may go
	thrownSeconds: number, -- flight time of paid throws not yet in a Food Bag
}

type Row = { name: string, studs: number }

-- Constants

local H = Config.Economy.Highway
local FOOD = Config.Economy.Food
local LAYOUT = WorldLayout.Highway
local REMOTE = "HighwayThrow"
local COIN_REASON = "highway"
local SAVE_SOON = "soon"
local FIELD_HIGHWAY = "highway"
local FIELD_FOOD = "food"
local STATUS_READY = "ready"
local ATTR_PHASE = "SD_DuelPhase"
local GIFT_SOURCE = "grant"
local CODE_INVALID = "net.invalid"
local CODE_NOT_READY = "data.notReady"
local CODE_IN_FLIGHT = "highway.inFlight"
local CODE_NOT_IN_AREA = "highway.notInArea"
local CODE_PAUSED = "highway.paused"
local CODE_IN_DUEL = "inventory.lockedInDuel"

-- Module table

local HighwayService = {}

-- Private

local log = Log.new("Highway")
local sessions: { [any]: Session } = {}
local recent: { Row } = {} -- the board's last throws, newest first
local best: Row? = nil -- this server's farthest landing

local function isFinite(v: unknown): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function userIdOf(player: any): number
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" then id else 0
end

local function rootPosition(player: any): Vector3?
	local character = if typeof(player) == "Instance" then (player :: Player).Character else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil
	end
	return (root :: BasePart).Position
end

-- Every launch board in the place (one, Verify), its live lines by name.
local function writeBoardLines(lines: { [string]: string })
	for _, board in CollectionService:GetTagged(WorldLayout.Tags.LaunchBoard) do
		for name, text in lines do
			local label = board:FindFirstChild(name, true)
			if label and label:IsA("TextLabel") then
				label.Text = text
			end
		end
	end
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
		duelPhaseOf = function(player: any): string
			local phase = if typeof(player) == "Instance" then (player :: Instance):GetAttribute(ATTR_PHASE) else nil
			return if type(phase) == "string" then phase else ""
		end,
		clock = os.clock,
		serverNow = function(): number
			return Workspace:GetServerTimeNow()
		end,
		rootOf = rootPosition,
		gripLevel = function(player: any): number
			return GripService.levelOf(player)
		end,
		grantCoins = function(player: any, amount: number, reason: string): number
			local added = EconomyService.grantCoins(player, amount, reason)
			return added
		end,
		addGrip = function(player: any, squeezes: number): number
			return GripService.addFromHighway(player, squeezes)
		end,
		grantSquishy = function(player: any, kind: string): boolean
			local grant = EconomyService.grantSquishy(player, kind, GIFT_SOURCE, true)
			return grant.refused == nil
		end,
		checkThrow = function(player: any, now: number, fastSeconds: number?): string?
			return AutoClickService.checkThrow(player, now, fastSeconds)
		end,
		requestSave = function(player: any, reason: string)
			StateService.dataPort().requestSave(player, reason)
		end,
		markDirty = function(player: any, field: string)
			StateService.markDirty(player, field)
		end,
		nameOf = function(player: any): string
			local ok, name = pcall(function(): any
				return player.DisplayName
			end)
			return if ok and type(name) == "string" then name else ""
		end,
		writeBoard = function(lines: { [string]: string })
			local ok, err = pcall(function(): any
				writeBoardLines(lines)
				return nil
			end)
			if not ok then
				log:warn("could not write the launch board:", err)
			end
		end,
	}
end

local deps: Deps = defaultDeps()

local function sessionOf(player: any): Session
	local session = sessions[player]
	if session == nil then
		session = { flyingUntil = -math.huge, thrownSeconds = 0 }
		sessions[player] = session
	end
	return session
end

local function studsText(studs: number): string
	return Strings.format(Strings.highway.studs, { distance = Format.distance(studs) })
end

-- The board's lines now (see the header).
local function boardLines(): { [string]: string }
	local lines: { [string]: string } = {}
	for row = 1, LAYOUT.boardRows do
		local entry = recent[row]
		lines[`Last{row}Who`] = if entry then entry.name else ""
		lines[`Last{row}Distance`] = if entry then studsText(entry.studs) else ""
	end
	if #recent == 0 then
		lines.Last1Who = Strings.highway.board.empty
	end
	lines.BestWho = if best then best.name else ""
	lines.BestDistance = if best then studsText(best.studs) else ""
	return lines
end

local function onBoard(name: string, studs: number)
	table.insert(recent, 1, { name = name, studs = studs })
	while #recent > LAYOUT.boardRows do
		table.remove(recent)
	end
	if best == nil or studs > best.studs then
		best = { name = name, studs = studs }
	end
	deps.writeBoard(boardLines())
end

-- (3)-(6): the refusal code, or nil when the throw may go (see the header).
local function refused(player: any, session: Session, now: number): string?
	local profile = deps.profileOf(player)
	if deps.statusOf(player) ~= STATUS_READY or type(profile) ~= "table" then
		return CODE_NOT_READY
	end
	if now < session.flyingUntil then
		return CODE_IN_FLIGHT
	end
	local root = deps.rootOf(player)
	if root == nil or not HighwayMath.inThrowArea(root, H.areaMarginStuds) then
		return CODE_NOT_IN_AREA
	end
	if deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return CODE_PAUSED
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL
	end
	return nil
end

-- The saved highway as stored (a broken one reads as none: sanitize repairs it on load).
local function savedHighway(profile: any): Types.HighwayState
	local h = if type(profile) == "table" then profile.highway else nil
	local bestStuds = if type(h) == "table" and isFinite(h.best) then h.best else 0
	local biome = if type(h) == "table" and isFinite(h.biome) then h.biome else 1
	return { best = bestStuds, biome = biome }
end

-- The gifts of every biome after `from` up to `to` (Config's order; each `count` times).
local function giftsBetween(from: number, to: number): { string }
	local list: { string } = {}
	for _, gift in H.gifts do
		if gift.biome > from and gift.biome <= to then
			for _ = 1, gift.count do
				table.insert(list, gift.kind)
			end
		end
	end
	return list
end

-- Public: the remote (see the header for the order of the checks) ----------------------------------------------------

function HighwayService.throw(player: any, clientTime: any, fastSeconds: number?): Reply
	if not isFinite(clientTime) then
		return NetService.err(CODE_INVALID, false)
	end
	local now = deps.clock()
	local cheat = deps.checkThrow(player, now, fastSeconds)
	if cheat ~= nil then
		return NetService.err(cheat, false)
	end
	local session = sessionOf(player)
	local refusal = refused(player, session, now)
	if refusal ~= nil then
		return NetService.err(refusal, false)
	end

	local power = HighwayMath.power(deps.gripLevel(player))
	local studs = HighwayMath.landing(power)
	local biome = HighwayMath.biomeAt(studs)
	local flight = HighwayMath.flight(studs).total
	session.flyingUntil = now + flight - H.inFlightGraceSeconds

	local profile = deps.profileOf(player)
	local sv = PenMath.squeezeValue(profile.pen)
	local coins = deps.grantCoins(player, HighwayMath.landingCoins(sv, studs), COIN_REASON)
	local grip = deps.addGrip(player, H.pay.grip)

	local before = savedHighway(profile)
	local reached = HighwayMath.reached(studs)
	session.thrownSeconds += flight
	local bag: { id: string, count: number }? = nil
	if session.thrownSeconds >= H.foodBag.seconds then
		session.thrownSeconds -= H.foodBag.seconds
		local food, pieces = HighwayMath.foodBag(profile.pen, sv)
		if food ~= nil then
			bag = { id = food.id, count = pieces }
		end
	end
	local newBest = studs > before.best
	local firstBiome = reached > before.biome
	if newBest or firstBiome or bag ~= nil then
		local added = 0 -- the Food Bag's pieces that fit under maxPieces
		local written = deps.mutate(player, function(live: any): boolean
			local h = if type(live.highway) == "table" then live.highway else { best = 0, biome = 1 }
			h.best = math.max(if isFinite(h.best) then h.best else 0, studs)
			h.biome = math.max(if isFinite(h.biome) then h.biome else 1, reached)
			live.highway = h
			local food = live.food
			if bag ~= nil and type(food) == "table" then
				local have = if isFinite(food[bag.id]) then food[bag.id] else 0
				food[bag.id] = math.max(have, math.min(FOOD.maxPieces, have + bag.count))
				added = food[bag.id] - have
			end
			return true
		end)
		if bag ~= nil then
			-- Verification fix: the reply names the pieces really added; none (a full stock) = no bag.
			bag = if added > 0 then { id = bag.id, count = added } else nil
		end
		if not written then
			-- Cannot happen without a yield after the checks (the session was ready a moment ago); logged loudly.
			log:error(
				`user {userIdOf(player)}: a {studs}-stud landing paid but its best / biome / food was not written`
			)
		end
		deps.markDirty(player, FIELD_HIGHWAY)
		if bag ~= nil then
			deps.markDirty(player, FIELD_FOOD)
		end
	end
	local gifts: { string } = {}
	if firstBiome then
		-- shortcut: a gift refused (a full Toy Box with Pen.giftQueueMax gifts already queued) is not retried; give the
		-- biome gifts profile.gifts keys (EconomyService.grantGift) if that queue can ever fill in real play.
		for _, kind in giftsBetween(before.biome, reached) do
			if deps.grantSquishy(player, kind) then
				table.insert(gifts, kind)
			end
		end
	end
	onBoard(deps.nameOf(player), studs)
	deps.requestSave(player, SAVE_SOON)
	local data: Types.HighwayResult = {
		studs = studs,
		biome = biome,
		power = power,
		flight = flight,
		landsAt = deps.serverNow() + flight,
		coins = coins,
		grip = grip,
		best = math.max(before.best, studs),
		newBest = newBest,
		reached = if firstBiome then reached else nil,
		gifts = gifts,
		food = bag,
		charged = false,
		savePending = deps.savePending(player),
	}
	return NetService.ok(data)
end

-- Public: tests -----------------------------------------------------------------------------------------------------

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function HighwayService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Forgets every session and the board (tests; not called by the bootstrap).
function HighwayService.reset()
	table.clear(sessions)
	table.clear(recent)
	best = nil
end

-- Lifecycle ---------------------------------------------------------------------------------------------------------

function HighwayService.init()
	local problems = ValidateHighway(Config, Catalog)
	if #problems > 0 then
		error(`[SD][Highway] Config.Economy.Highway is invalid: {table.concat(problems, "; ")}`)
	end
	NetService.onInvoke(REMOTE, function(player: Player, clientTime: any, fastSeconds: number): any
		return HighwayService.throw(player, clientTime, fastSeconds)
	end)
end

function HighwayService.start()
	deps.writeBoard(boardLines())
end

function HighwayService.playerAdded(player: Player)
	sessionOf(player)
end

function HighwayService.playerRemoving(player: Player)
	sessions[player] = nil
end

return HighwayService
