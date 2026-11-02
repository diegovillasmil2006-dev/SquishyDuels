--!strict
-- PowerUpRules: the power-up pads of Free for All / Team Deathmatch (Config.Match.PowerUps; jayyyyy 2026-10-15:
-- "random between shield, speed boost, throw boost like it throws harder, ult charge, dash boost", plus rapid throw
-- and super jump; a kind marked teamsOnly is offered in TDM only). Server only, pure (no instances, no yields;
-- randomness comes in as a number).
-- What a power-up does once taken is MatchRules' job (the pickup event); this module only answers which kinds a mode
-- offers, which one a roll picks (equal chance) and whether a pad is ready.
--
-- API (`match` = a Config.Match-shaped table; nil = the live Config.Match):
--   PowerUpRules.kindsFor(modeId, match?, hasUlt?) -> { string }  PowerUps.order, without teamsOnly kinds in a no-team
--                                                              mode, without the ult charge when hasUlt is false
--   PowerUpRules.roll(modeId, r, match?, hasUlt?) -> string    r in [0, 1) (Random:NextNumber()) picks one kind
--   PowerUpRules.canGrab(buffs, rollingUntil?, now) -> boolean no live timed power-up and no roll still spinning
--   PowerUpRules.newPad() -> Pad                               ready at once
--   PowerUpRules.isReady(pad, now) -> boolean
--   PowerUpRules.take(pad, now, match?) -> (boolean, Pad)      taken only when ready; the pad refills padRefillSeconds
--                                                              later (the given pad is never modified)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Pad = { readyAt: number }

local PowerUpRules = {}

function PowerUpRules.kindsFor(modeId: string, match: any?, hasUlt: boolean?): { string }
	local cfg = match or Config.Match
	local mode = cfg.Modes[modeId]
	assert(mode, `PowerUpRules: unknown mode {modeId}`)
	local out: { string } = {}
	for _, kind in cfg.PowerUps.order do
		local row = cfg.PowerUps.kinds[kind]
		if (mode.teams or not row.teamsOnly) and not (hasUlt == false and row.ultFraction) then
			table.insert(out, kind)
		end
	end
	return out
end

function PowerUpRules.roll(modeId: string, r: number, match: any?, hasUlt: boolean?): string
	local kinds = PowerUpRules.kindsFor(modeId, match, hasUlt)
	local index = math.clamp(math.floor(r * #kinds) + 1, 1, #kinds)
	return kinds[index]
end

-- Squish Pods (owner 2026-11-01): one power-up at a time: no grab while a timed one runs or the dial still rolls.
function PowerUpRules.canGrab(buffs: { [string]: number? }, rollingUntil: number?, now: number): boolean
	if rollingUntil ~= nil and now < rollingUntil then
		return false
	end
	for _, untilAt in buffs do
		if type(untilAt) == "number" and untilAt > now then
			return false
		end
	end
	return true
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
