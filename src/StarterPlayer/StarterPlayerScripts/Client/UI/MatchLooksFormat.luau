--!strict
-- MatchLooksFormat (client only, pure). Big job item 7 (2026-11-10): who gets which look in a Team or Free for All
-- match (Config/MatchLooks; drawn by Controllers/MatchLooksController).
--   cues(view, localUserId, now, teamNames)  the OTHER standing fighters of a running match, each with: relation
--                                            ("mate" = the local player's team in a team match, else "foe"), team
--                                            (1 / 2 in a team match), powers (the live timed power-ups at server time
--                                            `now`, sorted) and protected (spawn protection still running).
--   tag(cue, looks)                          a fighter's name tag: its Palette colour token, the teammate heart,
--                                            whether it shows through walls, and how far.
-- The local player gets no look of their own (the HUD shows their team, power-up and spawn protection).

export type Cue = {
	userId: number,
	name: string,
	relation: "mate" | "foe",
	team: number?,
	powers: { string },
	protected: boolean,
}

export type Tag = { color: string, heart: boolean, throughWalls: boolean, maxDistance: number }

-- The wire phases (Types.DuelPhase, MatchService.wirePhase) in which the fighters are in the map and playing.
local PLAY_PHASES: { [string]: boolean } = { Countdown = true, Active = true, SuddenDeath = true }

local MatchLooksFormat = {}

function MatchLooksFormat.cues(view: any, localUserId: number?, now: number, teamNames: { string }): { Cue }
	local list: { Cue } = {}
	if type(view) ~= "table" or PLAY_PHASES[view.phase] ~= true or type(view.players) ~= "table" then
		return list
	end
	local myTeam = if type(view.you) == "table" then view.you.team else nil
	for _, p in view.players do
		if type(p) ~= "table" or p.userId == localUserId or p.alive ~= true or p.out == true or p.arrived == false then
			continue
		end
		local powers: { string } = {}
		if type(p.buffs) == "table" then
			for kind, untilAt in p.buffs do
				if type(kind) == "string" and type(untilAt) == "number" and untilAt > now then
					table.insert(powers, kind)
				end
			end
			table.sort(powers)
		end
		table.insert(list, {
			userId = p.userId,
			name = if type(p.displayName) == "string" then p.displayName else "",
			relation = if myTeam ~= nil and p.team == myTeam then "mate" else "foe",
			team = if type(p.team) == "string" then table.find(teamNames, p.team) else nil,
			powers = powers,
			protected = type(p.protectUntil) == "number" and p.protectUntil > now,
		})
	end
	return list
end

function MatchLooksFormat.tag(cue: Cue, looks: any): Tag
	local mate = cue.relation == "mate"
	local teamColor = if cue.team ~= nil then looks.teams[cue.team] else nil
	return {
		color = if type(teamColor) == "string" then teamColor else looks.foe,
		heart = mate,
		throughWalls = mate,
		maxDistance = if mate then looks.Tag.mateMaxDistance else looks.Tag.maxDistance,
	}
end

return MatchLooksFormat
