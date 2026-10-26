--!strict
-- MatchIntro_Test: unit tests for StarterPlayerScripts.Client.UI.Match.MatchIntro (round 1 of the match screens,
-- 2026-10-26; S = Diego's "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html"). Contract: the phone layout on the compact
-- class; the stage fits the whole layout; the map's name in two lines split at the middle space; your team on the left
-- with you first (Free for All: you first, half a side); the beats 3, 2, 1 0.8 s apart and SQUISH! at the end; the
-- mode and goal lines; the piece shows the cover while you load, the intro once you are in (a card each, a loading
-- one for a player on the way, the blur), the beats in the Countdown, and leaves nothing behind.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local NOW = 1.8e9
local YOU = 4242
local BLUR_NAME = "SD_MatchIntroBlur"

return function(t: Context)
	local expect = t.expect
	local MatchIntro = t.requireClient("UI/Match/MatchIntro")
	local Fixtures = t.requireClient("Studio/MatchHudFixtures")
	local Config = t.requireShared("Config")
	local Lighting = game:GetService("Lighting")
	local LAYOUTS = Config.UI.Match.intro.layouts

	local function player(userId: number, team: string?, arrived: boolean?): any
		return {
			userId = userId,
			displayName = "P" .. userId,
			squishyId = "toast",
			team = team,
			arrived = arrived ~= false,
		}
	end

	local function view(mode: string, players: { any }, extra: { [string]: any }?): any
		local v: any = { mode = mode, players = players, you = { userId = YOU }, mapName = "Sweetshop Stadium" }
		for k, value in extra or {} do
			v[k] = value
		end
		return v
	end

	local function ids(list: { any }): { number }
		local out = {}
		for _, p in list do
			table.insert(out, p.userId)
		end
		return out
	end

	-- A pretend piece context (MatchHudPieces_Test's): a plain Frame, every sound recorded.
	local function piece(fixture: any, compact: boolean?): any
		local root = Instance.new("Frame")
		root.Size = UDim2.fromOffset(1440, 810)
		local played: { string } = {}
		local ctx = {
			root = root,
			preview = true,
			canvas = function(): Vector2
				return Vector2.new(1440, 810)
			end,
			compact = function(): boolean
				return compact == true
			end,
			reduced = function(): boolean
				return false
			end,
			fit = function(): number
				return 1
			end,
			roster = function(): any
				return fixture.roster
			end,
			result = function(): any
				return fixture.result
			end,
			play = function(key: string, _opts: any?, _fallback: string?)
				table.insert(played, key)
			end,
			touchAreas = function(): { any }
				return {}
			end,
			toastsBeside = function(_key: string, _object: GuiObject?) end,
			shared = {},
		}
		return { root = root, played = played, piece = MatchIntro.new(ctx :: any) }
	end

	local function find(root: Instance, name: string): GuiObject?
		local found = root:FindFirstChild(name, true)
		return if found and found:IsA("GuiObject") then found else nil
	end

	local function count(root: Instance, name: string): number
		local n = 0
		for _, d in root:GetDescendants() do
			if d.Name == name then
				n += 1
			end
		end
		return n
	end

	local function done(r: any): number
		r.piece:destroy()
		local left = #r.root:GetChildren()
		r.root:Destroy()
		return left
	end

	t.test("the phone layout on the compact class; the stage fits the whole layout", function()
		expect.equal(MatchIntro.layoutName(true), "phone")
		expect.equal(MatchIntro.layoutName(false), "desktop")
		expect.near(MatchIntro.stageScale(Vector2.new(1440, 900), LAYOUTS.desktop), 1, 1e-9)
		expect.near(MatchIntro.stageScale(Vector2.new(1440, 810), LAYOUTS.desktop), 0.9, 1e-9)
		expect.near(MatchIntro.stageScale(Vector2.new(1500, 369), LAYOUTS.phone), 1, 1e-9)
		expect.equal(MatchIntro.stageScale(Vector2.new(0, 0), LAYOUTS.desktop), 1)
	end)

	t.test("the map's name: two capital lines split at the space nearest the middle, else one", function()
		expect.deepEqual(MatchIntro.titleLines("Sweetshop Stadium"), { "SWEETSHOP", "STADIUM" })
		expect.deepEqual(MatchIntro.titleLines("Jar"), { "JAR" })
		expect.deepEqual(MatchIntro.titleLines("Candy Cane Lane"), { "CANDY", "CANE LANE" })
	end)

	t.test("Team: your team on the left with you first, the other team on the right", function()
		local players =
			{ player(1, "Strawberry"), player(2, "Blueberry"), player(YOU, "Blueberry"), player(4, "Strawberry") }
		local c = MatchIntro.columns(view("tdm", players))
		expect.deepEqual(ids(c.left), { YOU, 2 })
		expect.deepEqual(ids(c.right), { 1, 4 })
		expect.equal(c.leftTeam, "Blueberry")
		expect.equal(c.rightTeam, "Strawberry")
	end)

	t.test("Free for All: you first, the first half on the left, six a side at most", function()
		local players = {}
		for id = 1, 11 do
			table.insert(players, player(id))
		end
		table.insert(players, player(YOU))
		local c = MatchIntro.columns(view("ffa", players))
		expect.equal(#c.left, 6)
		expect.equal(#c.right, 6)
		expect.equal(c.left[1].userId, YOU)
		expect.deepEqual(ids(c.right), { 6, 7, 8, 9, 10, 11 })
		expect.equal(c.leftTeam, nil)
	end)

	t.test("the beats: 3, 2, 1 0.8 s apart before the countdown's end, SQUISH! at it, none outside it", function()
		local function at(left: number): number?
			return MatchIntro.beat({ matchPhase = "Countdown", phaseEndsAt = NOW + left }, NOW)
		end
		expect.equal(at(3), nil)
		expect.equal(at(2.4), 3)
		expect.equal(at(2), 3)
		expect.equal(at(1.6), 2)
		expect.equal(at(1.2), 2)
		expect.equal(at(0.5), 1)
		expect.equal(at(0), 0)
		expect.equal(at(-1), 0)
		expect.equal(MatchIntro.beat({ matchPhase = "Active", phaseEndsAt = NOW }, NOW), nil)
		expect.equal(MatchIntro.beat({ matchPhase = "Countdown", phaseEndsAt = 0 }, NOW), nil)
	end)

	t.test("the mode and goal lines (S:986)", function()
		local mode, goal = MatchIntro.lines(view("tdm", {}, { koTarget = 30 }))
		expect.equal(mode, "TEAM DEATHMATCH · 6v6")
		expect.equal(goal, "FIRST TO 30 SQUISHES · 3:00")
		mode, goal = MatchIntro.lines(view("ffa", {}, { koTarget = 25 }))
		expect.equal(mode, "FREE FOR ALL · 12")
		expect.equal(goal, "FIRST TO 25 SQUISHES · 8:00")
	end)

	t.test("waiting and in: the intro with a card each, a loading card for a player on the way, the blur", function()
		for _, compact in { false, true } do
			local fixture = assert(Fixtures.build("tdm_waiting", NOW, { youId = YOU, youName = "Tester" }))
			local r = piece(fixture, compact)
			r.piece:update(fixture.view, NOW)
			local intro = find(r.root, "Intro")
			expect.truthy(intro ~= nil and intro.Visible)
			expect.equal(count(r.root, "Card"), #fixture.view.players)
			expect.equal(count(r.root, "You"), 1)
			local loading = 0
			for _, d in r.root:GetDescendants() do
				if
					d.Name == "Loading"
					and d:IsA("GuiObject")
					and d.Visible
					and d.Parent
					and d.Parent.Name ~= "Middle"
				then
					loading += 1
				end
			end
			local away = 0
			for _, p in fixture.view.players do
				if not p.arrived then
					away += 1
				end
			end
			expect.truthy(away > 0)
			expect.equal(loading, away)
			expect.truthy(Lighting:FindFirstChild(BLUR_NAME) ~= nil)
			local boot = find(r.root, "Boot")
			expect.truthy(boot ~= nil and not boot.Visible)
			expect.equal(done(r), 0)
			expect.equal(Lighting:FindFirstChild(BLUR_NAME), nil)
		end
	end)

	t.test("waiting while you load: the Loading arena cover, no intro yet", function()
		local fixture = assert(Fixtures.build("tdm_waiting", NOW, { youId = YOU, youName = "Tester" }))
		local v = table.clone(fixture.view)
		v.players = table.clone(v.players)
		for index, p in v.players do
			if p.userId == YOU then
				local copy = table.clone(p)
				copy.arrived = false
				v.players[index] = copy
			end
		end
		local r = piece(fixture)
		r.piece:update(v, NOW)
		local boot = find(r.root, "Boot")
		expect.truthy(boot ~= nil and boot.Visible)
		local intro = find(r.root, "Intro")
		expect.truthy(intro == nil or not intro.Visible)
		expect.equal(Lighting:FindFirstChild(BLUR_NAME), nil)
		expect.equal(done(r), 0)
	end)

	t.test("a countdown met late: nothing before the first beat, then the beat with its slam and tick", function()
		local fixture = assert(Fixtures.build("ffa_countdown3", NOW, { youId = YOU, youName = "Tester" }))
		local r = piece(fixture)
		local endsAt = fixture.view.phaseEndsAt
		r.piece:update(fixture.view, endsAt - 3)
		expect.equal(#r.root:GetChildren(), 0)
		r.piece:update(fixture.view, endsAt - 2)
		local stage = find(r.root, "Count")
		expect.truthy(stage ~= nil and stage.Visible)
		expect.truthy(table.find(r.played, "match.count.slam") ~= nil)
		expect.truthy(table.find(r.played, "match.vote.tickUrgent") ~= nil)
		local three = find(r.root, "Beat3")
		expect.truthy(three ~= nil and three.Visible)
		r.piece:update(fixture.view, endsAt - 1)
		local two = find(r.root, "Beat2")
		expect.truthy(two ~= nil and two.Visible)
		expect.equal(done(r), 0)
	end)

	t.test("a match met while it is on shows nothing", function()
		local fixture = assert(Fixtures.build("tdm_live", NOW, { youId = YOU }))
		local r = piece(fixture)
		r.piece:update(fixture.view, NOW)
		expect.equal(#r.root:GetChildren(), 0)
		expect.equal(done(r), 0)
	end)
end
