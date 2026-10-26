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
--     come with it and go at your respawn (with ui.pop); nothing in Lighting is left behind;
--   * the storm bar (storm fix, owner 2026-10-26): while you stand in the TDM storm, IN THE STORM! with a fill = the
--     health the storm leaves you and the purple tint in Lighting; none with no storm, knocked out or with no
--     character; both go back inside the safe circle;
--   * the live top bar (2026-10-26): TDM your team left (you in Slot1, nearest the score, with YOU), 6 heads a side,
--     both scores, the clock and FIRST TO {target}; a squished head shows its seconds; Free for All the leader (the
--     runner-up when you lead) vs you with places; nothing before the 3-2-1; OVERTIME; power-up pills; it tells the
--     feed where it ends (shared.topBarBottom) and the feed starts there.

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
local STORM_TINT = "SD_MatchStorm" -- the storm fix: the storm's purple tint

return function(t: Context)
	local expect = t.expect
	local Fixtures = t.requireClient("Studio/MatchHudFixtures")
	local Format = t.requireClient("UI/MatchHudFormat")
	local KillFeed = t.requireClient("UI/Match/KillFeed")
	local DeathCard = t.requireClient("UI/Match/DeathCard")
	local RespawnBar = t.requireClient("UI/Match/RespawnBar")
	local StormBar = t.requireClient("UI/Match/StormBar")
	local TopBar = t.requireClient("UI/Match/TopBar")
	local MatchIntro = t.requireClient("UI/Match/MatchIntro")
	local MatchEnd = t.requireClient("UI/Match/MatchEnd")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local Lighting = game:GetService("Lighting")

	local function clearLighting()
		for _, child in Lighting:GetChildren() do
			if child.Name == CORRECTION_NAME or child.Name == BLUR_NAME or child.Name == STORM_TINT then
				child:Destroy()
			end
		end
	end

	-- Builds `module`'s piece for `state` and plays the state as the controller does; returns what the test needs.
	local function run(module: any, state: string, compact: boolean?, position: (() -> Vector3?)?): any
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
			position = position,
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
		local far = function(): Vector3?
			return Vector3.new(1e5, 3, 0) -- outside every safe circle: the storm bar shows where it can
		end
		for _, module in { RespawnBar, StormBar, TopBar, DeathCard, KillFeed, MatchIntro, MatchEnd } do
			for _, state in Fixtures.STATES do
				for _, compact in { false, true } do
					local r = run(module, state, compact, far)
					expect.equal(finish(r), 0)
				end
			end
		end
		expect.equal(Lighting:FindFirstChild(CORRECTION_NAME), nil)
		expect.equal(Lighting:FindFirstChild(BLUR_NAME), nil)
		expect.equal(Lighting:FindFirstChild(STORM_TINT), nil)
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

	t.test(
		"storm: the bar (fill = the health left) and the tint while you stand in the storm; gone back inside",
		function()
			local fixture = assert(Fixtures.build("tdm_storm", NOW, { youId = YOU, youName = "Tester" }))
			local centre = fixture.view.arena.centre
			local where = centre + Vector3.new(10000, 3, 0) -- far outside the safe circle
			local r = run(StormBar, "tdm_storm", false, function(): Vector3?
				return where
			end)
			local ok, err = pcall(function()
				local bar = assert(r.root:FindFirstChild("MatchStorm")) :: Frame
				expect.equal(bar.Visible, true)
				local label = assert(bar:FindFirstChild("Label", true)) :: TextLabel
				expect.equal(label.Text, Strings.matchHud.storm.label)
				local fill = assert(bar:FindFirstChild("Fill", true)) :: Frame
				local cfg = Config.UI.Match.respawn
				local inner = cfg.width - 2 * cfg.bar.border
				expect.equal(fill.Size.X.Offset, math.round(inner * (1 - r.fixture.view.you.stormBar)))
				expect.truthy(Lighting:FindFirstChild(STORM_TINT) ~= nil)
				where = centre + Vector3.new(0, 3, 0) -- back in the safe circle
				r.piece:update(r.fixture.view, NOW)
				expect.equal(bar.Visible, false)
				expect.equal(Lighting:FindFirstChild(STORM_TINT), nil)
			end)
			finish(r)
			expect.equal(Lighting:FindFirstChild(STORM_TINT), nil)
			if not ok then
				error(err, 0)
			end
		end
	)

	-- The live top bar (2026-10-26) -------------------------------------------------------------------------------------

	local function topText(root: Instance, holder: string, name: string): string?
		local bar = root:FindFirstChild("MatchTopBar", true) or root -- a slot: look inside it
		local box = bar:FindFirstChild(holder, true)
		local label = box and box:FindFirstChild(name, true)
		return if label and label:IsA("TextLabel") then label.Text else nil
	end

	local function slots(root: Instance, side: string): { Instance }
		local heads = assert(root:FindFirstChild(side, true), side)
		local out = {}
		for index = 1, 6 do
			local slot = heads:FindFirstChild("Slot" .. index)
			if slot then
				table.insert(out, slot)
			end
		end
		return out
	end

	local function guarded(r: any, fn: () -> ())
		local ok, err = pcall(fn)
		finish(r)
		if not ok then
			error(err, 0)
		end
	end

	t.test(
		"top: TDM: your team left with you nearest the score, 6 heads a side, the scores, the clock, FIRST TO 30",
		function()
			local r = run(TopBar, "tdm_score")
			guarded(r, function()
				local view = r.fixture.view
				local bar = assert(r.root:FindFirstChild("MatchTopBar")) :: Frame
				expect.equal(bar.Visible, true)
				local left, right = slots(r.root, "HeadsLeft"), slots(r.root, "HeadsRight")
				expect.equal(#left, 6)
				expect.equal(#right, 6)
				expect.equal(left[1]:GetAttribute("UserId"), view.you.userId) -- Slot1 is nearest the score
				expect.equal(topText(left[1], "Tag", "Text"), Strings.matchHud.top.you)
				local mine, theirs = view.you.team, nil
				for team in view.teamScore do
					if team ~= mine then
						theirs = team
					end
				end
				expect.equal(topText(r.root, "ScoreLeft", "Score"), tostring(view.teamScore[mine]))
				expect.equal(topText(r.root, "ScoreRight", "Score"), tostring(view.teamScore[theirs]))
				expect.equal(topText(r.root, "Timer", "Time"), Format.topBarTime(view, NOW))
				expect.equal(
					topText(r.root, "Goal", "Text"),
					Strings.format(Strings.matchHud.top.goal, { target = view.koTarget })
				)
				expect.truthy(type(r.ctx.shared.topBarBottom) == "number" and r.ctx.shared.topBarBottom > 0)
			end)
		end
	)

	t.test("top: a squished player's head shows the seconds until they are back", function()
		local r = run(TopBar, "tdm_knockedOut")
		guarded(r, function()
			local mine = slots(r.root, "HeadsLeft")[1]
			local you = r.fixture.view.you
			expect.equal(topText(mine, "Respawn", "Seconds"), tostring(Format.respawnLeft(you.respawnAt, NOW)))
			local back = alive(r.fixture.view)
			back.players = table.clone(back.players)
			for index, player in back.players do
				if player.userId == you.userId then
					local up = table.clone(player)
					up.alive = true
					up.respawnAt = nil
					back.players[index] = up
				end
			end
			r.piece:update(back, NOW)
			expect.equal(mine:FindFirstChild("Respawn", true), nil)
		end)
	end)

	t.test("top: Free for All: the leader (the runner-up when you lead) vs you, each with their place", function()
		local r = run(TopBar, "ffa_score")
		guarded(r, function()
			local view = r.fixture.view
			local rival = assert(Format.ffaRival(view))
			local left, right = slots(r.root, "HeadsLeft"), slots(r.root, "HeadsRight")
			expect.equal(#left, 1)
			expect.equal(#right, 1)
			expect.equal(left[1]:GetAttribute("UserId"), rival.userId)
			expect.equal(right[1]:GetAttribute("UserId"), view.you.userId)
			expect.equal(topText(r.root, "ScoreLeft", "Score"), tostring(rival.kos))
			local mine = 0
			for _, player in view.players do
				if player.userId == view.you.userId then
					mine = player.kos
				end
			end
			expect.equal(topText(r.root, "ScoreRight", "Score"), tostring(mine))
			expect.equal(topText(left[1], "Tag", "Text"), MatchEnd.ordinal(Format.placeOf(view, rival.userId)))
			expect.equal(topText(right[1], "Tag", "Text"), MatchEnd.ordinal(Format.placeOf(view, view.you.userId)))
		end)
	end)

	t.test("top: not before the 3-2-1; OVERTIME in overtime; your power-ups as pills under it", function()
		local waiting = run(TopBar, "tdm_waiting")
		local bar = waiting.root:FindFirstChild("MatchTopBar")
		local shown = bar ~= nil and (bar :: Frame).Visible
		local bottom = waiting.ctx.shared.topBarBottom
		finish(waiting)
		expect.equal(shown, false)
		expect.equal(bottom, nil) -- the feed keeps its own top
		local over = run(TopBar, "tdm_overtime")
		guarded(over, function()
			expect.equal(topText(over.root, "Timer", "Time"), Strings.matchHud.top.overtime)
		end)
		local boosted = run(TopBar, "tdm_powerUps")
		guarded(boosted, function()
			local pills = assert(boosted.root:FindFirstChild("Boosts", true))
			local texts = {}
			for _, d in pills:GetDescendants() do
				if d:IsA("TextLabel") then
					table.insert(texts, d.Text)
				end
			end
			expect.truthy(#texts > 0)
			expect.truthy(string.find(table.concat(texts, " "), Strings.match.readout.powerUpName.speed, 1, true))
		end)
	end)

	t.test("feed: under the top bar while it shows", function()
		local r = run(KillFeed, "tdm_firstBlood")
		guarded(r, function()
			local list = assert(r.root:FindFirstChild("MatchFeed")) :: Frame
			local top = list.Position.Y.Offset
			r.ctx.shared.topBarBottom = top + 100
			r.piece:update(r.fixture.view, NOW)
			expect.equal(list.Position.Y.Offset, top + 100)
			r.ctx.shared.topBarBottom = nil
			r.piece:update(r.fixture.view, NOW)
			expect.equal(list.Position.Y.Offset, top)
		end)
	end)

	t.test("storm: hidden with no storm, while knocked out and with no character", function()
		for _, state in { "ffa_live", "tdm_knockedOutStorm", "tdm_storm" } do
			local far = if state == "tdm_storm" then nil else Vector3.new(1e5, 3, 0)
			local r = run(StormBar, state, false, function(): Vector3?
				return far
			end)
			local shown = (r.root:FindFirstChild("MatchStorm") :: Frame).Visible
			finish(r)
			expect.equal(shown, false)
		end
	end)
end
