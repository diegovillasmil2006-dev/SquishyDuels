--!strict
-- PowerUpRules: the power-up pads of Free for All / Team Deathmatch (Config.Match.PowerUps; jayyyyy 2026-10-15:
-- "random between shield, speed boost, throw boost like it throws harder, ult charge, dash boost", plus rapid throw
-- and super jump; a kind marked teamsOnly is offered in TDM only). Server only, pure (no instances, no yields;
-- randomness comes in as a number).
-- What a power-up does once taken is MatchRules' job (the pickup event); this module only answers which kinds a mode
-- offers, which one a roll picks (equal chance) and whether a pad is ready.
--
-- API (`match` = a Config.Match-shaped table; nil = the live Config.Match):
--   PowerUpRules.kindsFor(modeId, match?) -> { string }        PowerUps.order, without teamsOnly kinds in a no-team mode
--   PowerUpRules.roll(modeId, r, match?) -> string             r in [0, 1) (Random:NextNumber()) picks one kind
--   PowerUpRules.newPad() -> Pad                               ready at once
--   PowerUpRules.isReady(pad, now) -> boolean
--   PowerUpRules.take(pad, now, match?) -> (boolean, Pad)      taken only when ready; the pad refills padRefillSeconds
--                                                              later (the given pad is never modified)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Pad = { readyAt: number }

local PowerUpRules = {}

function PowerUpRules.kindsFor(modeId: string, match: any?): { string }
	local cfg = match or Config.Match
	local mode = cfg.Modes[modeId]
	assert(mode, `PowerUpRules: unknown mode {modeId}`)
	local out: { string } = {}
	for _, kind in cfg.PowerUps.order do
		if mode.teams or not cfg.PowerUps.kinds[kind].teamsOnly then
			table.insert(out, kind)
		end
	end
	return out
end

function PowerUpRules.roll(modeId: string, r: number, match: any?): string
	local kinds = PowerUpRules.kindsFor(modeId, match)
	local index = math.clamp(math.floor(r * #kinds) + 1, 1, #kinds)
	return kinds[index]
end

function PowerUpRules.newPad(): Pad
	return { readyAt = -math.huge }
end

function PowerUpRules.isReady(pad: Pad, now: number): boolean
	return now >= pad.readyAt
end

function PowerUpRules.take(pad: Pad, now: number, match: any?): (boolean, Pad)
	if not PowerUpRules.isReady(pad, now) then
		return false, pad
	end
	local cfg = match or Config.Match
	return true, { readyAt = now + cfg.PowerUps.padRefillSeconds }
end

return PowerUpRules
