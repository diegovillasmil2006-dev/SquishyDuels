--!strict
-- MatchHudPieces_Test: the Match HUD M6 / M7 pieces (2026-10-17; plan work/matchhud2/PLAN.md §4 M6, M7): Client.UI.Match
-- KillFeed, DeathCard and RespawnBar, each built in a pretend piece context (a plain Frame, no ScreenGui: Edit mode has
-- no LocalPlayer) and driven by Studio/MatchHudFixtures states exactly as MatchHudController drives them (update, the
-- state's moments, update). Server only (ServerStorage.UnitTest), Edit mode. Contract:
--   * the feed: one row per K.O. moment, the storm / fall one included (owner: a line with nobody to blame); FIRST
--     BLOOD on the first, DOUBLE! / TRIPLE! on your three in a row; a click per row and the splat only for others' K.O.s;
--     at most compactMaxRows rows stay on a compact screen (the older ones leave); destroy leaves nothing;
--   * the card: for your K.O. by someone ("squished by", the info row, the knocked-out sounds), for a fall (the cause
--     pill, no info row), never for your own squish or the final K.O.; its rect goes to ctx.shared; it leaves at your
--     respawn;
--   * the bar: while you wait, its number = the whole seconds left; the vignette and the client ColorCorrectionEffect
--     come with it and go at your respawn (with ui.pop); nothing in Lighting is left behind.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local NOW = 1.8e9
local YOU = 4242
local CORRECTION_NAME = "SD_MatchKnockedOut"
local BLUR_NAME = "SD_MatchIntroBlur" -- round 1 of the match screens: the intro's blur

return function(t: Context)
	local expect = t.expect
	local Fixtures = t.requireClient("Studio/MatchHudFixtures")
	local Format = t.requireClient("UI/MatchHudFormat")
	local KillFeed = t.requireClient("UI/Match/KillFeed")
	local DeathCard = t.requireClient("UI/Match/DeathCard")
	local RespawnBar = t.requireClient("UI/Match/RespawnBar")
	local MatchIntro = t.requireClient("UI/Match/MatchIntro")
	local MatchEnd = t.requireClient("UI/Match/MatchEnd")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local Lighting = game:GetService("Lighting")

	local function clearLighting()
		for _, child in Lighting:GetChildren() do
			if child.Name == CORRECTION_NAME or child.Name == BLUR_NAME then
				child:Destroy()
			end
		end
	end

	-- Builds `module`'s piece for `state` and plays the state as the controller does; returns what the test needs.
	local function run(module: any, state: string, compact: boolean?): any
		local fixture = assert(Fixtures.build(state, NOW, { youId = YOU, youName = "Tester" }), state)
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
		local piece = module.new(ctx)
		piece:update(fixture.view, NOW)
		for _, moment in fixture.moments do
			if piece.onMoment then -- optional in the piece contract (MatchHudFormat: onMoment?)
				piece:onMoment(moment, fixture.view)
			end
		end
		piece:update(fixture.view, NOW)
		return { fixture = fixture, root = root, played = played, ctx = ctx, piece = piece }
	end

	-- Ends the piece; returns how many children it left in the root.
	local function finish(r: any): number
		r.piece:destroy()
		local left = #r.root:GetChildren()
		r.root:Destroy()
		clearLighting()
		return left
	end

	local function count(list: { string }, value: string): number
		local n = 0
		for _, item in list do
			if item == value then
				n += 1
			end
		end
		return n
	end

	local function rows(root: Instance): { Instance }
		local list = root:FindFirstChild("MatchFeed")
		local out = {}
		if list then
			for _, child in list:GetChildren() do
				if child.Name == "Row" then
					table.insert(out, child)
				end
			end
		end
		return out
	end

	local function tags(root: Instance): { string }
		local out = {}
		for _, row in rows(root) do
			for _, d in row:GetDescendants() do
				if d.Name == "Tag" then
					local label = d:FindFirstChild("Text")
					if label and label:IsA("TextLabel") then
						table.insert(out, label.Text)
					end
				end
			end
		end
		return out
	end

	local function alive(view: any): any
		local back = table.clone(view)
		back.you = table.clone(view.you)
		back.you.alive = true
		back.you.respawnAt = nil
		return back
	end

	t.test("feed: a row per K.O. (the fall too), FIRST BLOOD on the first, the splat only for others' K.O.s", function()
		local r = run(KillFeed, "tdm_feedBusy")
		local ok, err = pcall(function()
			expect.equal(#rows(r.root), 3)
			local all = tags(r.root)
			expect.equal(all[1], Strings.matchHud.feed.firstBlood)
			expect.truthy(table.find(all, Strings.matchHud.feed.cause.outOfBounds) ~= nil)
			expect.equal(count(r.played, "ui.click"), 3)
			expect.equal(count(r.played, "match.splat"), 2) -- the fall has nobody to splat
		end)
		local left = finish(r)
		if not ok then
			error(err, 0)
		end
		expect.equal(left, 0)
	end)

	t.test("card and bar: destroy leaves nothing in the root", function()
		for _, module in { DeathCard, RespawnBar } do
			local r = run(module, "tdm_knockedOut")
			expect.equal(finish(r), 0)
		end
	end)

	t.test("every piece plays every fixture state without an error and leaves nothing behind", function()
		for _, module in { RespawnBar, DeathCard, KillFeed, MatchIntro, MatchEnd } do
			for _, state in Fixtures.STATES do
				for _, compact in { false, true } do
					local r = run(module, state, compact)
					expect.equal(finish(r), 0)
				end
			end
		end
		expect.equal(Lighting:FindFirstChild(CORRECTION_NAME), nil)
		expect.equal(Lighting:FindFirstChild(BLUR_NAME), nil)
	end)

	t.test("feed: your three in a row read FIRST BLOOD, DOUBLE!, TRIPLE!; no splat for your own", function()
		local r = run(KillFeed, "ffa_score")
		local ok, err = pcall(function()
			local words = Strings.matchHud.feed
			expect.deepEqual(tags(r.root), { words.firstBlood, words.double, words.triple })
			expect.equal(count(r.played, "match.splat"), 0)
		end)
		finish(r)
		if not ok then
			error(err, 0)
		end
	end)

	t.test("feed: on a compact screen the older rows leave at once and go", function()
		local r = run(KillFeed, "ffa_score", true)
		local ok, err = pcall(function()
			expect.equal(#rows(r.root), 3) -- leaving, not gone yet
			task.wait(Config.UI.Match.feed.leave.ms / 1000 + 0.1)
			r.piece:update(r.fixture.view, NOW)
			expect.equal(#rows(r.root), Config.UI.Match.feed.compactMaxRows)
		end)
		finish(r)
		if not ok then
			error(err, 0)
		end
	end)

	t.test("card: squished by someone: the header, the info row, the knocked-out sounds, its rect shared", function()
		local r = run(DeathCard, "tdm_knockedOut")
		local ok, err = pcall(function()
			local card = r.root:FindFirstChild("MatchDeathCard")
			expect.truthy(card ~= nil)
			local by = (card :: Instance):FindFirstChild("By", true)
			expect.equal((by :: TextLabel).Text, Strings.matchHud.card.squishedBy)
			expect.truthy((card :: Instance):FindFirstChild("Info", true) ~= nil)
			expect.truthy((card :: Instance):FindFirstChild("Toy", true) ~= nil)
			expect.truthy(r.ctx.shared.cardRect ~= nil)
			for _, key in { "match.knockedOut", "match.splat", "match.whoosh" } do
				expect.equal(count(r.played, key), 1)
			end
		end)
		finish(r)
		if not ok then
			error(err, 0)
		end
	end)

	t.test("card: a fall has the cause pill and no info row", function()
		local r = run(DeathCard, "ffa_knockedOutFall")
		local ok, err = pcall(function()
			local card = assert(r.root:FindFirstChild("MatchDeathCard"))
			expect.equal(card:FindFirstChild("Info", true), nil)
			local texts = {}
			for _, d in card:GetDescendants() do
				if d:IsA("TextLabel") then
					texts[d.Text] = true
				end
			end
			expect.truthy(texts[Strings.matchHud.card.cause.outOfBounds.pill])
			expect.truthy(texts[Strings.matchHud.card.cause.outOfBounds.name])
		end)
		finish(r)
		if not ok then
			error(err, 0)
		end
	end)

	t.test("card: none for your own squish or the final K.O.; it leaves at your respawn", function()
		for _, state in { "ffa_yourSquish", "tdm_endLose", "ffa_live" } do
			local r = run(DeathCard, state)
			local none = r.root:FindFirstChild("MatchDeathCard") == nil
			finish(r)
			expect.truthy(none)
		end
		local r = run(DeathCard, "tdm_knockedOutStorm")
		local ok, err = pcall(function()
			expect.truthy(r.root:FindFirstChild("MatchDeathCard") ~= nil)
			local back = alive(r.fixture.view)
			r.piece:update(back, NOW)
			task.wait(Config.UI.Match.card.hide.ms / 1000 + 0.1)
			r.piece:update(back, NOW)
			expect.equal(r.root:FindFirstChild("MatchDeathCard"), nil)
			expect.equal(r.ctx.shared.cardRect, nil)
		end)
		finish(r)
		if not ok then
			error(err, 0)
		end
	end)

	t.test(
		"bar: the seconds left, the vignette and the colour change while you wait; all gone at the respawn",
		function()
			local r = run(RespawnBar, "tdm_knockedOut")
			local ok, err = pcall(function()
				local bar = assert(r.root:FindFirstChild("MatchRespawn")) :: Frame
				expect.equal(bar.Visible, true)
				local number = assert(bar:FindFirstChild("Number", true)) :: TextLabel
				local respawnAt = r.fixture.view.you.respawnAt
				expect.equal(number.Text, tostring(Format.respawnLeft(respawnAt, NOW)))
				expect.equal((assert(r.root:FindFirstChild("MatchVignette")) :: Frame).Visible, true)
				expect.truthy(Lighting:FindFirstChild(CORRECTION_NAME) ~= nil)
				r.piece:update(alive(r.fixture.view), NOW)
				expect.equal(bar.Visible, false)
				expect.equal(Lighting:FindFirstChild(CORRECTION_NAME), nil)
				expect.equal(count(r.played, "ui.pop"), 1)
			end)
			finish(r)
			expect.equal(Lighting:FindFirstChild(CORRECTION_NAME), nil)
			if not ok then
				error(err, 0)
			end
		end
	)

	t.test("bar: hidden while you stand", function()
		local r = run(RespawnBar, "tdm_live")
		local shown = (r.root:FindFirstChild("MatchRespawn") :: Frame).Visible
		finish(r)
		expect.equal(shown, false)
	end)
end
