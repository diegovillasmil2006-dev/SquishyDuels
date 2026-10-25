--!strict
-- MatchFoundRoster (server only, pure). Round 2 of the match flow (2026-10-25, owner: Diego's MATCH FOUND show for every
-- mode; LOBBY HUD L:722-735 the players row): the MatchFound payload a duel (DuelService) or a match (MatchService)
-- sends its players when it starts from the queue: the mode and every player in the given order (userId, name, squishy,
-- Grip level, team 1 / 2 in Team Deathmatch). A bot has no Grip: it shows a level from 1 to the highest player's,
-- drawn from `rng` (the design gives every player a level, L:1031).
--   MatchFoundRoster.build("tdm", { { userId, name, squishy, level?, team? } }, rng) -> Types.MatchFoundView

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)

export type Entry = { userId: number, name: string, squishy: string, level: number?, team: number? }

local MatchFoundRoster = {}

local function whole(level: number): number
	return if level == level and math.abs(level) < math.huge then math.max(1, math.floor(level)) else 1
end

function MatchFoundRoster.build(mode: Types.MatchFoundMode, entries: { Entry }, rng: Random): Types.MatchFoundView
	local top = 1
	for _, entry in entries do
		if entry.level ~= nil then
			top = math.max(top, whole(entry.level))
		end
	end
	local players: { Types.MatchFoundPlayer } = {}
	for _, entry in entries do
		table.insert(players, {
			userId = entry.userId,
			name = entry.name,
			squishy = entry.squishy,
			level = if entry.level ~= nil then whole(entry.level) else rng:NextInteger(1, top),
			team = entry.team,
		})
	end
	return { mode = mode, players = players }
end

return MatchFoundRoster
