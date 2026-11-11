--!strict
-- MatchLooksFormat_Test: unit tests for StarterPlayerScripts.Client.UI.MatchLooksFormat and Shared.Config.MatchLooks
-- (big job item 7, 2026-11-10: the match looks). Server only (ServerStorage.UnitTest). Pure: runs in Edit mode.
-- Contract:
--   * a look goes to every OTHER standing fighter of a running match (Countdown, Active, SuddenDeath): never the local
--     player, a knocked-out or out player, one who has not arrived, or anyone before the start or on the end screens;
--   * a teammate (the local player's team in a team match) is a "mate", everyone else a "foe"; Free for All: all foes;
--   * a fighter's power-ups are the timed ones still running at the server time given, sorted; spawn protection is on
--     until protectUntil;
--   * a tag is in the team's colour (Free for All: the enemy colour); only a teammate's has the heart and shows
--     through walls, and it shows from farther;
--   * the config's colours are Art/Palette colours, the bots' clothes are positive whole asset ids, and no field is
--     named "...Key" (Config.validate would read it as a Strings path).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Format = t.requireClient("UI/MatchLooksFormat")
	local LOOKS = t.requireShared("Config/MatchLooks")
	local Config = t.requireShared("Config")
	local Palette = t.requireShared("Art/Palette")
	local TEAMS = Config.Match.teamNames
	local NOW = 1000

	local function fighter(userId: number, team: string?, extra: { [string]: any }?): { [string]: any }
		local p: { [string]: any } = {
			userId = userId,
			displayName = "P" .. userId,
			team = team,
			alive = true,
			out = false,
			arrived = true,
			protectUntil = 0,
			buffs = {},
		}
		for key, value in extra or {} do
			p[key] = value
		end
		return p
	end

	local function view(phase: string, myTeam: string?, players: { any }): { [string]: any }
		return { phase = phase, you = { userId = 1, team = myTeam }, players = players }
	end

	local function byId(cues: { any }): { [number]: any }
		local map = {}
		for _, cue in cues do
			map[cue.userId] = cue
		end
		return map
	end

	t.test("cues: every other standing fighter of a running match, mates and foes", function()
		local players = {
			fighter(1, TEAMS[1]), -- the local player
			fighter(2, TEAMS[1]),
			fighter(3, TEAMS[2]),
			fighter(-5, TEAMS[2]), -- a bot
			fighter(6, TEAMS[2], { alive = false }),
			fighter(7, TEAMS[1], { out = true }),
			fighter(8, TEAMS[1], { arrived = false }),
		}
		local cues = byId(Format.cues(view("Active", TEAMS[1], players), 1, NOW, TEAMS))
		expect.equal(cues[1], nil)
		expect.equal(cues[6], nil)
		expect.equal(cues[7], nil)
		expect.equal(cues[8], nil)
		expect.equal(cues[2].relation, "mate")
		expect.equal(cues[2].team, 1)
		expect.equal(cues[2].name, "P2")
		expect.equal(cues[3].relation, "foe")
		expect.equal(cues[3].team, 2)
		expect.equal(cues[-5].relation, "foe")
		for _, phase in { "Countdown", "Active", "SuddenDeath" } do
			expect.equal(#Format.cues(view(phase, TEAMS[1], players), 1, NOW, TEAMS), 3)
		end
		for _, phase in { "Preparing", "Positioning", "Result", "Returning", "Cancelled", "Void" } do
			expect.equal(#Format.cues(view(phase, TEAMS[1], players), 1, NOW, TEAMS), 0)
		end
		expect.equal(#Format.cues(nil, 1, NOW, TEAMS), 0)
		expect.equal(#Format.cues({ phase = "Active" }, 1, NOW, TEAMS), 0)
	end)

	t.test("cues: Free for All has no teams, so everyone else is a foe", function()
		local cues = Format.cues(view("Active", nil, { fighter(1, nil), fighter(2, nil), fighter(-3, nil) }), 1, NOW, TEAMS)
		expect.equal(#cues, 2)
		for _, cue in cues do
			expect.equal(cue.relation, "foe")
			expect.equal(cue.team, nil)
			expect.equal(Format.tag(cue, LOOKS).color, LOOKS.foe)
		end
	end)

	t.test("cues: the power-ups still running and the spawn protection, by the server time", function()
		local players = {
			fighter(1, nil),
			fighter(2, nil, { buffs = { speed = NOW + 3, shield = NOW + 1, superJump = NOW - 0.1 } }),
			fighter(3, nil, { protectUntil = NOW + 1.5 }),
			fighter(4, nil, { protectUntil = NOW - 0.01, buffs = nil }),
		}
		local cues = byId(Format.cues(view("Active", nil, players), 1, NOW, TEAMS))
		expect.deepEqual(cues[2].powers, { "shield", "speed" })
		expect.equal(cues[2].protected, false)
		expect.deepEqual(cues[3].powers, {})
		expect.equal(cues[3].protected, true)
		expect.equal(cues[4].protected, false)
		expect.deepEqual(cues[4].powers, {})
		-- later: the shield ran out, then the protection
		local later = byId(Format.cues(view("Active", nil, players), 1, NOW + 2, TEAMS))
		expect.deepEqual(later[2].powers, { "speed" })
		expect.equal(later[3].protected, false)
	end)

	t.test("tag: the team's colour; only a teammate's has the heart, shows through walls and from farther", function()
		local players = { fighter(1, TEAMS[2]), fighter(2, TEAMS[2]), fighter(3, TEAMS[1]) }
		local cues = byId(Format.cues(view("Active", TEAMS[2], players), 1, NOW, TEAMS))
		local mate, foe = Format.tag(cues[2], LOOKS), Format.tag(cues[3], LOOKS)
		expect.equal(mate.color, LOOKS.teams[2])
		expect.equal(mate.heart, true)
		expect.equal(mate.throughWalls, true)
		expect.equal(mate.maxDistance, LOOKS.Tag.mateMaxDistance)
		expect.equal(foe.color, LOOKS.teams[1])
		expect.equal(foe.heart, false)
		expect.equal(foe.throughWalls, false)
		expect.equal(foe.maxDistance, LOOKS.Tag.maxDistance)
		expect.truthy(LOOKS.Tag.mateMaxDistance > LOOKS.Tag.maxDistance)
	end)

	t.test("Config.MatchLooks: Palette colours, a colour per team, whole asset ids, no '...Key' field", function()
		expect.equal(#LOOKS.teams, #TEAMS)
		expect.truthy(LOOKS.teams[1] ~= LOOKS.teams[2])
		for _, token in { LOOKS.teams[1], LOOKS.teams[2], LOOKS.foe, LOOKS.Protect.color } do
			expect.equal(typeof(Palette[token]), "Color3")
		end
		local B = LOOKS.Bots
		expect.truthy(B.templates >= 1 and B.hatChance >= 0 and B.hatChance <= 1)
		expect.truthy(#B.skins >= 2)
		for _, list in { B.shirts, B.pants, B.hair, B.hats } do
			expect.truthy(#list >= 1)
			local seen: { [number]: boolean } = {}
			for _, id in list do
				expect.truthy(type(id) == "number" and id >= 1 and math.floor(id) == id)
				expect.falsy(seen[id])
				seen[id] = true
			end
		end
		-- the vault's budget for a lasting layer, and a refresh a few times a second
		expect.truthy(LOOKS.Power.sparkleRate >= 3 and LOOKS.Power.sparkleRate <= 8)
		expect.truthy(LOOKS.refreshSeconds > 0 and LOOKS.refreshSeconds <= 0.5)
		expect.truthy(LOOKS.Protect.transparencyMin < LOOKS.Protect.transparencyMax)
		local function walk(value: any, path: string)
			if type(value) ~= "table" then
				return
			end
			for key, child in value do
				if type(key) == "string" and string.sub(key, -3) == "Key" then
					error(`{path}.{key} would be read as a Strings path`)
				end
				walk(child, `{path}.{tostring(key)}`)
			end
		end
		walk(LOOKS, "MatchLooks")
	end)
end
