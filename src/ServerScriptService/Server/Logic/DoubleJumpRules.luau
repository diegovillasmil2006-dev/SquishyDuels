--!strict
-- DoubleJumpRules: validation of one DoubleJumpRequest (2026-10-15, VillasmilGaming: a double jump "only when
-- dueling"; numbers in Config.Duel.Rules.DoubleJump). Server only, pure (no instances, no yields). Used by
-- DoubleJumpService. The jumper's own client moves its HumanoidRootPart (it owns its physics, like the dash and
-- knockback); the server only decides whether the other players are told, so a refused request is just not shown.
-- The movement guard needs nothing: it checks horizontal speed, and the arena's zones, dividers and ceiling are 40
-- studs tall, far above a double jump's top.
--
-- Checks, cheapest first; the first failure refuses with a reason code:
--   1. Rate bucket (Config.Net.Remotes.DoubleJumpRequest): NetService drops silently, before this module.
--   2. Payload: seq an integer above lastSeq; key one of "F", "B", "L", "R"; clientTime a server timestamp
--      ........................................................................................................ net.invalid
--      (a payload violation for NetService's abuse count). lastSeq advances as soon as seq passes.
--   3. Context: a registered duel in Active or SuddenDeath; alive ..................................... jump.context
--   4. Not rooted (an ultimate's wind-up or recovery: its JumpHeight is 0) ................................ jump.busy
--   5. Interval: now >= lastJumpAt + serverIntervalSeconds (one per air time; the client allows maxPerAir) . jump.cooldown
-- Not checked: being in the air. The server's HRP lags the client's by the replication delay, so right after the
-- first jump it can still look grounded; a refusal there would only hide an honest jump.
--
-- API:
--   DoubleJumpRules.validate(input, state, cfg?, now) -> Decision (state is never modified)
--   DoubleJumpRules.isKey(value) -> boolean
-- `cfg` is a table with Config's Duel section (a test's copy of Config); nil = the live Config.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Validate = require(Shared.Util.Validate)

-- Types

export type JumpInput = { seq: unknown, key: unknown, clientTime: unknown }

export type JumpState = {
	lastSeq: number, -- 0 before the first double jump of the session
	lastJumpAt: number, -- server time of the last accepted double jump (-math.huge before one)
	inDuel: boolean, -- a registered duel fighter
	matchPhase: string?, -- Types.DuelPhase
	alive: boolean,
	rooted: boolean, -- an ultimate's telegraph or recovery (rootedUntil)
}

export type Decision = {
	ok: boolean,
	reason: string?,
	violation: boolean, -- a payload failure: an abuse violation for NetService
	seq: number?,
	lastSeq: number, -- the new JumpState.lastSeq
	key: string?, -- accepted only: the flip's key
}

export type JumpConfig = { Duel: any }

-- Constants

local REASON_INVALID = "net.invalid"
local REASON_CONTEXT = "jump.context"
local REASON_BUSY = "jump.busy"
local REASON_COOLDOWN = "jump.cooldown"
local LIVE_PHASES: { [string]: boolean } = { Active = true, SuddenDeath = true }
local KEYS: { [string]: boolean } = { F = true, B = true, L = true, R = true }

-- Module table

local DoubleJumpRules = {}

-- Private

local function config(cfg: JumpConfig?): JumpConfig
	return if cfg ~= nil then cfg else Config
end

local function refuse(state: JumpState, reason: string, seq: number?, violation: boolean): Decision
	return {
		ok = false,
		reason = reason,
		violation = violation,
		seq = seq,
		lastSeq = if seq ~= nil then math.max(state.lastSeq, seq) else state.lastSeq,
	}
end

-- Public

function DoubleJumpRules.isKey(value: unknown): boolean
	return type(value) == "string" and KEYS[value] == true
end

function DoubleJumpRules.validate(input: JumpInput, state: JumpState, cfg: JumpConfig?, now: number): Decision
	local rules = config(cfg).Duel.Rules.DoubleJump

	-- 2. Payload and replay.
	local seq = Validate.integer(input.seq)
	if seq == nil or seq <= state.lastSeq then
		return refuse(state, REASON_INVALID, nil, true)
	end
	if not DoubleJumpRules.isKey(input.key) or Validate.serverTime(input.clientTime) == nil then
		return refuse(state, REASON_INVALID, seq, true)
	end

	-- 3. Context.
	if not state.inDuel or not LIVE_PHASES[state.matchPhase or ""] or not state.alive then
		return refuse(state, REASON_CONTEXT, seq, false)
	end

	-- 4. Busy.
	if state.rooted then
		return refuse(state, REASON_BUSY, seq, false)
	end

	-- 5. Interval.
	if now < state.lastJumpAt + rules.serverIntervalSeconds then
		return refuse(state, REASON_COOLDOWN, seq, false)
	end

	return { ok = true, violation = false, seq = seq, lastSeq = seq, key = input.key :: string }
end

return table.freeze(DoubleJumpRules)
