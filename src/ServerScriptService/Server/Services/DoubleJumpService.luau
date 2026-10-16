--!strict
-- DoubleJumpService (server only; 2026-10-15, VillasmilGaming: a double jump "only when dueling"). The jumper's own
-- client moves its HumanoidRootPart and plays the jump at once (Client/Controllers/DoubleJumpController); the server
-- checks the request (Logic/DoubleJumpRules) with its own state and tells the match's players, so the opponent sees the
-- flip, its effects and hears it:
-- * DoubleJumpRequest(seq, key, clientTime) (and the Studio test dummy, through requestDoubleJump): a registered duel
--   fighter (brought up to the request time first, port.sync) in Active or SuddenDeath, alive, not rooted by an
--   ultimate, serverIntervalSeconds since its last accepted double jump.
-- * Accepted: DoubleJumped {userId, key, at, startAt} to the match's players (the jumper's client ignores its own).
-- * Refused: nothing is sent; a payload failure counts toward NetService's abuse mute.
-- Per player (userId) for the session: lastSeq and lastJumpAt; playerRemoving forgets them.
-- Tests swap the clock, the sender and the violation reporter with useDeps.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)
local DoubleJumpRules = require(script.Parent.Parent.Logic.DoubleJumpRules)
local CombatService = require(script.Parent.CombatService)
local NetService = require(script.Parent.NetService)

-- Types

export type Deps = {
	now: () -> number,
	send: (remote: string, recipients: { any }, ...any) -> (),
	reportViolation: (player: any, remote: string) -> (),
}

type JumperState = { lastSeq: number, lastJumpAt: number }

-- Constants

local REMOTE_REQUEST = "DoubleJumpRequest"
local REMOTE_JUMPED = "DoubleJumped"
local REASON_CONTEXT = "jump.context"

-- Module table

local DoubleJumpService = {}

-- Private

local states: { [number]: JumperState } = {} -- userId -> state

local function defaultDeps(): Deps
	return {
		now = function(): number
			return Workspace:GetServerTimeNow()
		end,
		send = function(remote: string, recipients: { any }, ...: any)
			NetService.fireMany(remote, recipients, ...)
		end,
		reportViolation = function(player: any, remote: string)
			if typeof(player) == "Instance" and player:IsA("Player") then
				NetService.reportViolation(player, remote)
			end
		end,
	}
end

local deps: Deps = defaultDeps()

local function stateOf(userId: number): JumperState
	local state = states[userId]
	if state == nil then
		state = { lastSeq = 0, lastJumpAt = -math.huge }
		states[userId] = state
	end
	return state
end

-- Public

-- Validates and accepts one double jump. `who` is the Player (DoubleJumpRequest) or a registered fighter / its userId
-- (the Studio test dummy). Returns (accepted, reason?).
function DoubleJumpService.requestDoubleJump(who: any, seq: unknown, key: unknown, clientTime: unknown): (boolean, string?)
	local now = deps.now()
	local fighter = CombatService.getFighter(who)
	local player: Player? = if fighter
		then fighter.player
		elseif typeof(who) == "Instance" and who:IsA("Player") then who
		else nil
	local userId = if fighter then fighter.userId elseif player then player.UserId else nil
	if userId == nil then
		return false, REASON_CONTEXT
	end
	local memory = stateOf(userId)
	local port = if fighter then CombatService.portOf(fighter) else nil
	if port then
		local sync = port.sync
		if sync then
			sync(now) -- the match's timers first, so the phase below is the one at the request time
		end
	end

	local state: DoubleJumpRules.JumpState = {
		lastSeq = memory.lastSeq,
		lastJumpAt = memory.lastJumpAt,
		inDuel = fighter ~= nil and port ~= nil,
		matchPhase = if port then port.phase() else nil,
		alive = fighter ~= nil and fighter.isAlive(),
		rooted = fighter ~= nil and now < fighter.rootedUntil,
	}
	local decision = DoubleJumpRules.validate({ seq = seq, key = key, clientTime = clientTime }, state, nil, now)
	memory.lastSeq = decision.lastSeq
	if not decision.ok then
		if decision.violation and player then
			deps.reportViolation(player, REMOTE_REQUEST)
		end
		return false, decision.reason
	end

	memory.lastJumpAt = now
	local root = if fighter then fighter.getRoot() else nil
	local payload: Types.DoubleJumpedPayload = {
		userId = userId,
		key = decision.key :: string,
		at = if root then root.Position else Vector3.zero,
		startAt = now,
	}
	local recipients: { any } = {}
	if port then
		for _, participant in port.fighters do
			if participant.player then
				table.insert(recipients, participant.player)
			end
		end
	end
	deps.send(REMOTE_JUMPED, recipients, payload)
	return true, nil
end

-- Swaps the clock, the sender and the violation reporter (tests). Missing fields keep the live default; nil restores
-- every default.
function DoubleJumpService.useDeps(newDeps: {
	now: (() -> number)?,
	send: ((remote: string, recipients: { any }, ...any) -> ())?,
	reportViolation: ((player: any, remote: string) -> ())?,
}?)
	local base = defaultDeps()
	if newDeps then
		base.now = newDeps.now or base.now
		base.send = newDeps.send or base.send
		base.reportViolation = newDeps.reportViolation or base.reportViolation
	end
	deps = base
end

-- Lifecycle

function DoubleJumpService.init()
	NetService.on(REMOTE_REQUEST, function(player: Player, seq: any, key: any, clientTime: any)
		DoubleJumpService.requestDoubleJump(player, seq, key, clientTime)
	end)
end

function DoubleJumpService.playerRemoving(player: Player)
	states[player.UserId] = nil
end

return DoubleJumpService
