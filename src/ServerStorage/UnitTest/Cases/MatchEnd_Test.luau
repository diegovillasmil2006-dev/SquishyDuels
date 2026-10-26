--!strict
-- MatchEnd_Test: unit tests for StarterPlayerScripts.Client.UI.Match.MatchEnd (end screens round A, 2026-10-26; S =
-- Diego's "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html"). Contract: places read 1ST 2ND 3RD 4TH ...; Team: VICTORY!
-- for the winning team, DEFEAT for the other, "STRAWBERRY WINS" and the two scores; Free for All (owner 2026-10-26):
-- VICTORY! for 1st, else your place ("2ND PLACE"), "{NAME} WINS" / YOU WIN; a draw reads DRAW; the MVP is the winning
-- team's most squishes (ties: fewer times squished, then the best streak), Free for All's winner; the scoreboard lists
-- the winning team first, its players by squishes, WIN / LOSS, Free for All 1st-6th then 7th-12th; the Grip bar fills
-- from before the match to now inside the level (from 0 after a level-up); the streak line grows, resets or holds; the
-- piece builds the title's letters and the three buttons and leaves nothing behind.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local NOW = 1.8e9
local YOU = 4242

return function(t: Context)
	local expect = t.expect
	local MatchEnd = t.requireClient("UI/Match/MatchEnd")
	local Fixtures = t.requireClient("Studio/MatchHudFixtures")
	local Config = t.requireShared("Config")
	local RED, BLUE = Config.Match.teamNames[1], Config.Match.teamNames[2]

	local function s(userId: number, kos: number, knockedOut: number, best: number?, grip: number?): any
		return { userId = userId, kos = kos, knockedOut = knockedOut, bestStreak = best or 0, grip = grip }
	end

	local function who(userId: number): any
		return { name = if userId == YOU then "You" else "P" .. userId, look = {}, team = nil, you = userId == YOU }
	end

	t.test("places read 1ST 2ND 3RD, then 4TH ... 11TH", function()
		expect.equal(MatchEnd.ordinal(1), "1ST")
		expect.equal(MatchEnd.ordinal(2), "2ND")
		expect.equal(MatchEnd.ordinal(3), "3RD")
		expect.equal(MatchEnd.ordinal(4), "4TH")
		expect.equal(MatchEnd.ordinal(11), "11TH")
	end)

	t.test("Team: VICTORY! for the winners, DEFEAT for the others; the winner's line and both scores", function()
		local view: any = {
			mode = "tdm",
			you = { userId = YOU, team = RED },
			teamScore = { [RED] = 30, [BLUE] = 24 },
			players = {},
			outcome = { kind = "win", winnerTeam = RED, standings = {} },
		}
		local r = MatchEnd.resultOf(view, who)
		expect.equal(r.kind, "victory")
		expect.equal(r.title, "VICTORY!")
		expect.equal(r.line, "STRAWBERRY WINS")
		expect.equal(r.winScore, 30)
		expect.equal(r.loseScore, 24)
		view.you = { userId = YOU, team = BLUE }
		r = MatchEnd.resultOf(view, who)
		expect.equal(r.kind, "defeat")
		expect.equal(r.title, "DEFEAT")
		expect.equal(r.line, "STRAWBERRY WINS")
	end)

	t.test("Free for All: VICTORY! for 1st, else your place; the winner's name or YOU WIN", function()
		local view: any = {
			mode = "ffa",
			you = { userId = YOU },
			players = {},
			outcome = { kind = "win", winnerUserId = 7, standings = { s(7, 25, 3), s(YOU, 20, 5), s(9, 12, 8) } },
		}
		local r = MatchEnd.resultOf(view, who)
		expect.equal(r.kind, "defeat")
		expect.equal(r.title, "2ND PLACE")
		expect.equal(r.line, "P7 WINS")
		expect.equal(r.winScore, 25)
		expect.equal(r.loseScore, nil)
		view.outcome.winnerUserId = YOU
		r = MatchEnd.resultOf(view, who)
		expect.equal(r.kind, "victory")
		expect.equal(r.title, "VICTORY!")
		expect.equal(r.line, "YOU WIN")
	end)

	t.test("a draw reads DRAW with both scores", function()
		local view: any = {
			mode = "tdm",
			you = { userId = YOU, team = BLUE },
			teamScore = { [RED] = 22, [BLUE] = 22 },
			players = {},
			outcome = { kind = "draw", standings = {} },
		}
		local r = MatchEnd.resultOf(view, who)
		expect.equal(r.kind, "draw")
		expect.equal(r.title, "DRAW")
		expect.equal(r.winScore, 22)
		expect.equal(r.loseScore, 22)
	end)

	t.test("MVP: the winning team's most squishes; ties to fewer times squished, then the best streak", function()
		local teams = { [1] = RED, [2] = RED, [3] = RED, [4] = BLUE }
		local function teamOf(userId: number): string?
			return teams[userId]
		end
		local view: any = {
			mode = "tdm",
			outcome = {
				kind = "win",
				winnerTeam = RED,
				standings = { s(4, 12, 1), s(1, 8, 4, 2), s(2, 8, 3, 1), s(3, 8, 3, 5) },
			},
		}
		expect.equal(MatchEnd.mvp(view, teamOf), 3) -- 8 squishes, 3 squished, the best streak 5
		view.outcome = { kind = "draw", standings = view.outcome.standings }
		expect.equal(MatchEnd.mvp(view, teamOf), nil)
		view.mode = "ffa"
		view.outcome = { kind = "win", winnerUserId = 9, standings = {} }
		expect.equal(MatchEnd.mvp(view, teamOf), 9)
	end)

	t.test("the scoreboard: the winners first by squishes, WIN / LOSS; Free for All 1st-6th, 7th-12th", function()
		local teams = { [1] = RED, [2] = BLUE, [3] = RED, [YOU] = BLUE }
		local function whoTeam(userId: number): any
			local w = who(userId)
			w.team = teams[userId]
			return w
		end
		local view: any = {
			mode = "tdm",
			you = { userId = YOU, team = BLUE },
			teamScore = { [RED] = 24, [BLUE] = 30 },
			outcome = {
				kind = "win",
				winnerTeam = BLUE,
				standings = { s(1, 9, 2), s(2, 6, 1, 0, 160), s(3, 4, 4), s(YOU, 10, 3, 0, 230) },
			},
		}
		local columns = MatchEnd.columns(view, whoTeam)
		expect.equal(columns[1].title, "BLUEBERRY")
		expect.equal(columns[1].score, 30)
		expect.equal(columns[1].res, "WIN")
		expect.equal(columns[2].res, "LOSS")
		expect.equal(columns[1].rows[1].userId, YOU)
		expect.equal(columns[1].rows[1].mvp, true)
		expect.equal(columns[1].rows[1].grip, 230)
		expect.equal(columns[1].rows[2].userId, 2)
		expect.equal(columns[2].rows[1].userId, 1)
		local standings = {}
		for id = 1, 12 do
			table.insert(standings, s(id, 20 - id, id))
		end
		view.mode = "ffa"
		view.outcome = { kind = "win", winnerUserId = 1, standings = standings }
		columns = MatchEnd.columns(view, whoTeam)
		expect.equal(#columns[1].rows, 6)
		expect.equal(#columns[2].rows, 6)
		expect.equal(columns[1].rows[1].userId, 1)
		expect.equal(columns[2].rows[1].userId, 7)
		expect.equal(columns[1].title, "1ST – 6TH")
	end)

	t.test("the Grip bar: before -> now inside the level, from 0 after a level-up; nothing without a total", function()
		local totals = Config.Grip.LevelTotals
		local span = totals[3] - totals[2]
		local level, from, to = MatchEnd.gripBar(totals[2] + span * 0.75, span * 0.5)
		expect.equal(level, 2)
		expect.near(from, 0.25, 0.01) -- Grip is whole numbers
		expect.near(to, 0.75, 0.01)
		level, from, to = MatchEnd.gripBar(totals[2] + span * 0.1, span * 0.5)
		expect.equal(level, 2)
		expect.equal(from, 0)
		expect.near(to, 0.1, 0.01)
		expect.equal((MatchEnd.gripBar(nil, 100)), nil)
	end)

	t.test("the streak line: it grew (the flame lights), it reset, it held; nothing without a pay", function()
		local text, lit = MatchEnd.streakLine({ coins = 1, grip = 1, streakBefore = 2, streakAfter = 3 })
		expect.equal(text, "Win streak 3")
		expect.equal(lit, true)
		text, lit = MatchEnd.streakLine({ coins = 1, grip = 1, streakBefore = 3, streakAfter = 0 })
		expect.equal(text, "Streak reset")
		expect.equal(lit, false)
		text, lit = MatchEnd.streakLine({ coins = 1, grip = 1, streakBefore = 0, streakAfter = 0 })
		expect.equal(text, "Win streak 0")
		expect.equal(lit, false)
		expect.equal((MatchEnd.streakLine(nil)), nil)
	end)

	t.test(
		"the piece: the title's letters and the three buttons on a win, DEFEAT on a loss; nothing left after",
		function()
			for _, case in { { "tdm_endWin", "VICTORY!" }, { "tdm_endLose", "DEFEAT" }, { "ffa_endWin", "VICTORY!" } } do
				for _, compact in { false, true } do
					local fixture = assert(Fixtures.build(case[1], NOW, { youId = YOU, youName = "Tester" }))
					local root = Instance.new("Frame")
					root.Size = UDim2.fromOffset(1440, 810)
					local ctx = {
						root = root,
						preview = true,
						canvas = function(): Vector2
							return Vector2.new(1440, 810)
						end,
						compact = function(): boolean
							return compact
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
						play = function(_key: string, _opts: any?, _fallback: string?) end,
						touchAreas = function(): { any }
							return {}
						end,
						toastsBeside = function(_key: string, _object: GuiObject?) end,
						shared = {},
					}
					local piece = MatchEnd.new(ctx :: any)
					piece:update(fixture.view, NOW)
					local letters, buttons = 0, 0
					for _, d in root:GetDescendants() do
						if d.Name == "Letter" then
							letters += 1
						elseif
							d:IsA("TextButton")
							and (d.Name == "Scoreboard" or d.Name == "Lobby" or d.Name == "PlayAgain")
						then
							buttons += 1
						end
					end
					expect.equal(letters, utf8.len(case[2]))
					expect.equal(buttons, 3)
					piece:destroy()
					expect.equal(#root:GetChildren(), 0)
					root:Destroy()
				end
			end
		end
	)
end
