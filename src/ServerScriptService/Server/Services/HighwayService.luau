--!strict
-- HighwayService (server only). Pens3 phase 13 (2026-10-18; work/pens3/PLAN.md "PHASE 13" with the owner's
-- corrections, work/pens3/p13v2/NOTES.md): the throw for distance from the launch deck. The server decides everything;
-- Shared/HighwayMath has the math, Config.Economy.Highway every number (checked by Config/ValidateHighway in init: any
-- problem stops with an error, like PenService's).
-- P13v4 (owner 2026-10-19: copy the TikTok duck throw; work/pens3/p13v4/SPEC.md 2, 3, 5): the reply is the flight plan
-- (Types.HighwayPlan) and the pay moves to the landing (the boost and the rings are only known then); the PERFECT bar,
-- one boost a throw, the rings' share of the Coins, the BULLSEYE pads, and the new HighwayLanded remote.
-- * One open throw area (owner 2026-10-18: "it should be a general area where they walk up and everybody can throw";
--   2026-10-15: "One big launch area where everyone throws at the same time, with no waiting or queue"): anyone whose
--   server-side character root is inside WorldLayout.Highway.throwArea (areaMarginStuds bigger) may throw, everyone at
--   once; no spots, no queue. The only pacing is one throw in flight per player.
-- * HighwayThrow(clientTime, fastSeconds) (RF; Config.Net 14 a second, burst 30: the client sends every THROW press in
--   the area, the presses during its own flight too, so the auto-clicker check sees the real rhythm), in this order:
--   (1) clientTime not a finite number -> net.invalid (it is never trusted: no timing reads it); (2)
--   AutoClickService.checkThrow first for every arrival (its reason: highway.autoClick, the calm warning of a catch,
--   highway.tooFast during its pause, highway.superFast for the speed rule: fastSeconds, the client's speed report
--   (Shared/PressSpeed; a Net-checked integer), goes to checkThrow only); (3) no READY profile -> data.notReady; (4)
--   the player's open flight: an arrival within inFlightGraceSeconds of its landing settles it (below) and goes on as
--   a new press; any earlier one asks for the boost: no fuel left -> highway.noFuel, HighwayMath.boost refusing (too
--   soon after the release, too close to the carry, rolling) -> highway.inFlight, else ok(the plan after the boost,
--   boosted = true); (5) no living character root in the throw area -> highway.notInArea; (6) a pending failed save,
--   the server closing or a restart pending -> highway.paused; (7) SD_DuelPhase ~= "" -> inventory.lockedInDuel.
--   Every refusal carries charged = false and writes nothing.
-- * A throw (at the arrival's server time t): PERFECT when HighwayMath.isPerfect(t - one way), one way = half the
--   player's ping (Player:GetNetworkPing is the round trip; 0 when it fails, at most timing.maxOneWaySeconds): the
--   client's own clock is never read. power = HighwayMath.power(GripService.levelOf) (x timing.perfectPower when
--   PERFECT; phase 14 multiplies the gear in), the plan HighwayMath.newPlan(power, the root lane-local, t +
--   releaseSeconds) with boost.fuel boosts; the settle is scheduled at its landsAt (deps.after = task.delay). The
--   reply: ok(the plan); nothing is paid yet.
-- * A boost (a press during the own flight): HighwayMath.boost(plan, power, t), power x boost.power, one fuel less;
--   the settle moves to the new landsAt (an older schedule finds it stale and does nothing). Nothing is written.
-- * The settle (at the landing, or at once when the player leaves; a profile that is not READY then pays nothing,
--   logged): it pays in full (owner 2026-10-16: "No daily limits on squeezes or throwing"; no time share, no cap):
--   HighwayMath.landingCoins(SV, studs, rings) Coins with the "highway" reason (p13v3: by distance; p13v4: + a share a
--   ring flown through, HighwayMath.ringsHit) and GripService.addFromHighway(pay.grip). Then ONE mutate when
--   something saved changes: highway.best and highway.biome rise (only up: HighwayMath.reached, 8 = the Golden
--   Gates), and a Food Bag's food (below). The biome gifts of every biome this throw reaches first, once each (the
--   saved biome only rises, so they are never given twice), through EconomyService.grantSquishy(p, kind, "grant",
--   true): a full Toy Box queues them (pens3 phase 5). The `highway` (and `food`) fields sent, a "soon" save (reading:
--   a landing only grants, nothing is spent, so no awaited "now" save: one per throw would wait on the DataStore's 6 s
--   rule for one key every few seconds; PenPlace / Feed's reading), the board, and HighwayLanded(Types.HighwayLanding)
--   to the thrower (not when the player is leaving).
-- * The Food Bag (V3:185, SIM:239): the flight time of paid throws (press to landing) adds up in the session; every
--   foodBag.seconds of it the landing that crosses the line also gives HighwayMath.foodBag(pen, SV) (the weakest placed
--   squishy's band food, at least 1 piece, at most Food.maxPieces held; the landing names the pieces that fit). Time
--   not thrown never counts (an idle player on the deck earns none); a bag that finds no food (nothing placed, or past
--   the last band) or no room (the stock full) is skipped.
-- * The launch board (owner 2026-10-15: "The launch gate board shows the last throws and the server best"): the last
--   WorldLayout.Highway.boardRows landings of anyone in the server, newest first (the thrower's display name and the
--   distance), and the server best (this server's farthest landing), written by the server on the board's live lines
--   (deps.writeBoard: every SD_LaunchBoard's TextLabels by name; they replicate to everyone) after each landing;
--   start() writes the empty board (Strings highway.board.empty on the first row). The server's own memory: a new
--   server starts empty.
-- Dependencies are injectable (useDeps) so unit tests run with fake profiles, players and timers (plain tables);
-- init() never yields; playerAdded / playerRemoving never yield (playerRemoving settles an open flight first: services
-- leave in reverse order, so DataService still holds the profile).

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
	clock: () -> number, -- os.clock: the auto-clicker check's clock
	serverNow: () -> number, -- Workspace:GetServerTimeNow(): every flight time (the plans are on it)
	rootOf: (player: any) -> Vector3?, -- the living character's HumanoidRootPart position (server side)
	gripLevel: (player: any) -> number, -- GripService.levelOf
	pingOf: (player: any) -> number, -- p13v4: Player:GetNetworkPing (seconds, the round trip; 0 when it fails)
	after: (seconds: number, fn: () -> ()) -> (), -- p13v4: task.delay (the settle at the landing)
	fireLanded: (player: any, landing: Types.HighwayLanding) -> (), -- p13v4: NetService.fire("HighwayLanded", ...)
	grantCoins: (player: any, amount: number, reason: string) -> number, -- the Coins really added
	addGrip: (player: any, squeezes: number) -> number, -- GripService.addFromHighway
	grantSquishy: (player: any, kind: string) -> boolean, -- EconomyService.grantSquishy(p, kind, "grant", true)
	checkThrow: (player: any, now: number, fastSeconds: number?) -> string?, -- AutoClickService.checkThrow
	requestSave: (player: any, reason: string) -> (),
	markDirty: (player: any, field: string) -> (), -- StateService.markDirty
	nameOf: (player: any) -> string, -- the board's name: the player's DisplayName
	writeBoard: (lines: { [string]: string }) -> (), -- the launch board's live lines, by name
}

-- What the remote answers: NetService.ok(Types.HighwayPlan) or NetService.err(reason, false).
export type Reply = { ok: boolean, data: Types.HighwayPlan?, reason: string?, charged: boolean? }

-- The open flight: the plan last sent (never changed: a boost makes a new one), the power so far (PERFECT and boosts
-- in), the press's server time and the number of its current settle schedule.
type Flight = { plan: Types.HighwayPlan, power: number, pressedAt: number, schedule: number }

type Session = {
	flight: Flight?,
	thrownSeconds: number, -- flight time of paid throws not yet in a Food Bag
	throws: number, -- the last throw's id
	schedules: number, -- the last settle schedule's number
}

type Row = { name: string, studs: number }

-- Constants

local H = Config.Economy.Highway
local FOOD = Config.Economy.Food
local LAYOUT = WorldLayout.Highway
local REMOTE = "HighwayThrow"
local LANDED_REMOTE = "HighwayLanded"
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
local CODE_NO_FUEL = "highway.noFuel"
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
		pingOf = function(player: any): number
			local ok, ping = pcall(function(): any
				return (player :: Player):GetNetworkPing()
			end)
			return if ok and isFinite(ping) then ping else 0
		end,
		after = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		fireLanded = function(player: any, landing: Types.HighwayLanding)
			NetService.fire(LANDED_REMOTE, player, landing)
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
		session = { flight = nil, thrownSeconds = 0, throws = 0, schedules = 0 }
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

-- (5)-(7): the refusal code, or nil and the root's world position when a new throw may go (see the header).
local function refused(player: any): (string?, Vector3?)
	local root = deps.rootOf(player)
	if root == nil or not HighwayMath.inThrowArea(root, H.areaMarginStuds) then
		return CODE_NOT_IN_AREA, nil
	end
	if deps.savePending(player) or deps.isClosing() or deps.isRestartPending() then
		return CODE_PAUSED, nil
	end
	if deps.duelPhaseOf(player) ~= "" then
		return CODE_IN_DUEL, nil
	end
	return nil, root
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

-- The landing of the open flight (see the header): pays, saves, writes the board, and fires HighwayLanded when `fire`.
local function settle(player: any, session: Session, fire: boolean)
	local flight = session.flight
	if flight == nil then
		return
	end
	session.flight = nil
	local plan = flight.plan
	local studs = plan.studs
	local profile = deps.profileOf(player)
	if deps.statusOf(player) ~= STATUS_READY or type(profile) ~= "table" then
		log:warn(`user {userIdOf(player)}: a {studs}-stud landing found no ready profile; nothing paid`)
		return
	end
	local rings = HighwayMath.ringsHit(plan)
	local sv = PenMath.squeezeValue(profile.pen)
	local coins = deps.grantCoins(player, HighwayMath.landingCoins(sv, studs, #rings), COIN_REASON)
	local grip = deps.addGrip(player, H.pay.grip)

	local before = savedHighway(profile)
	local reached = HighwayMath.reached(studs)
	session.thrownSeconds += plan.landsAt - flight.pressedAt
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
			-- Verification fix: the landing names the pieces really added; none (a full stock) = no bag.
			bag = if added > 0 then { id = bag.id, count = added } else nil
		end
		if not written then
			-- Cannot happen without a yield after the check above (the session was ready a moment ago); logged loudly.
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
	if fire then
		deps.fireLanded(player, {
			id = plan.id,
			studs = studs,
			biome = plan.biome,
			coins = coins,
			grip = grip,
			best = math.max(before.best, studs),
			newBest = newBest,
			reached = if firstBiome then reached else nil,
			gifts = gifts,
			food = bag,
			rings = rings,
			bullseye = HighwayMath.bullseye(studs),
			perfect = plan.perfect,
			boosts = #plan.arcs - 1,
		})
	end
end

-- Schedules the settle at the flight's landing; an older schedule (before a boost, or of a flight already settled, or
-- of a session that ended) does nothing.
local function schedule(player: any, session: Session, flight: Flight, now: number)
	session.schedules += 1
	local mine = session.schedules
	flight.schedule = mine
	deps.after(math.max(flight.plan.landsAt - now, 0), function()
		if sessions[player] == session and session.flight == flight and flight.schedule == mine then
			settle(player, session, true)
		end
	end)
end

-- (4) A press during the own flight: the boost (see the header).
local function boost(player: any, session: Session, flight: Flight, now: number): Reply
	local plan = flight.plan
	if plan.fuel <= 0 then
		return NetService.err(CODE_NO_FUEL, false)
	end
	local core = HighwayMath.boost(plan, flight.power, now)
	if core == nil then
		return NetService.err(CODE_IN_FLIGHT, false)
	end
	local boosted: Types.HighwayPlan = {
		id = plan.id,
		perfect = plan.perfect,
		x0 = core.x0,
		arcs = core.arcs,
		roll = core.roll,
		studs = core.studs,
		biome = HighwayMath.biomeAt(core.studs),
		landsAt = core.landsAt,
		fuel = plan.fuel - 1,
		boosted = true,
		charged = false,
		savePending = deps.savePending(player),
	}
	flight.plan = boosted
	flight.power *= H.boost.power
	schedule(player, session, flight, now)
	return NetService.ok(boosted)
end

-- A new throw from the root's world position (see the header).
local function launch(player: any, session: Session, root: Vector3, now: number): Reply
	local ping = deps.pingOf(player)
	local oneWay = if isFinite(ping) then math.clamp(ping / 2, 0, H.timing.maxOneWaySeconds) else 0
	local perfect = HighwayMath.isPerfect(now - oneWay)
	local power = HighwayMath.power(deps.gripLevel(player)) * (if perfect then H.timing.perfectPower else 1)
	local core = HighwayMath.newPlan(power, LAYOUT.origin:PointToObjectSpace(root), now + H.flight.releaseSeconds)
	session.throws += 1
	local plan: Types.HighwayPlan = {
		id = session.throws,
		perfect = perfect,
		x0 = core.x0,
		arcs = core.arcs,
		roll = core.roll,
		studs = core.studs,
		biome = HighwayMath.biomeAt(core.studs),
		landsAt = core.landsAt,
		fuel = H.boost.fuel,
		boosted = false,
		charged = false,
		savePending = deps.savePending(player),
	}
	local flight: Flight = { plan = plan, power = power, pressedAt = now, schedule = 0 }
	session.flight = flight
	schedule(player, session, flight, now)
	return NetService.ok(plan)
end

-- Public: the remote (see the header for the order of the checks) ----------------------------------------------------

function HighwayService.throw(player: any, clientTime: any, fastSeconds: number?): Reply
	if not isFinite(clientTime) then
		return NetService.err(CODE_INVALID, false)
	end
	local cheat = deps.checkThrow(player, deps.clock(), fastSeconds)
	if cheat ~= nil then
		return NetService.err(cheat, false)
	end
	local session = sessionOf(player)
	if deps.statusOf(player) ~= STATUS_READY or type(deps.profileOf(player)) ~= "table" then
		return NetService.err(CODE_NOT_READY, false)
	end
	local now = deps.serverNow()
	local flight = session.flight
	if flight ~= nil then
		if now < flight.plan.landsAt - H.inFlightGraceSeconds then
			return boost(player, session, flight, now)
		end
		settle(player, session, true)
	end
	local refusal, root = refused(player)
	if refusal ~= nil or root == nil then
		return NetService.err(refusal or CODE_NOT_IN_AREA, false)
	end
	return launch(player, session, root, now)
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

-- Forgets every session and the board (tests; not called by the bootstrap). Pending settles find no session.
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

-- An open flight lands at once (paid, no HighwayLanded: the player is leaving), then the session goes.
function HighwayService.playerRemoving(player: Player)
	local session = sessions[player]
	if session ~= nil then
		settle(player, session, false)
	end
	sessions[player] = nil
end

return HighwayService
