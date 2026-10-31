--!strict
-- MatchTicket_Test: ServerScriptService.Server.Logic.MatchTicket (one match per server, Diego's NEW MAPS FINALS,
-- 2026-10-30). Contract: a lobby's ticket reads back the same after a JSON trip (TeleportData); anything a client or a
-- bug could bend is refused: the wrong version, a mode / kind / map that do not fit, bad or repeated user ids, more than
-- 12 players, a team for someone not in the match, empty ids.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local MatchTicket = t.requireServer("Logic/MatchTicket")
	local MapData = t.requireShared("Maps/MapData")
	local HttpService = game:GetService("HttpService")
	local expect = t.expect
	local maps = MapData.maps

	local function trip(ticket: any): any
		return HttpService:JSONDecode(HttpService:JSONEncode(ticket))
	end

	t.test("a Team ticket and a 1v1 ticket read back the same after a JSON trip", function()
		local team = MatchTicket.make("match", "tdm", "T2", "m-1", { 11, 22 }, { [11] = "Strawberry", [22] = "Blueberry" }, "job-1")
		local back, why = MatchTicket.read(trip(team), maps)
		expect.equal(why, nil)
		expect.equal(back.mapId, "T2")
		expect.deepEqual(back.players, { 11, 22 })
		expect.equal(back.teams["22"], "Blueberry")
		expect.equal(back.home, "job-1")
		local duel = MatchTicket.make("duel", "1v1", "D3", "d-1", { 5, 6 }, nil, "job-2")
		local d = MatchTicket.read(trip(duel), maps)
		expect.equal(d.kind, "duel")
		expect.equal(d.mapId, "D3")
	end)

	t.test("bent tickets are refused", function()
		local function bent(change: (any) -> ()): string?
			local ticket = trip(MatchTicket.make("match", "ffa", "F1", "m-2", { 1, 2, 3 }, nil, "job"))
			change(ticket)
			local ok, why = MatchTicket.read(ticket, maps)
			expect.equal(ok, nil)
			return why
		end
		expect.equal(bent(function(x) x.v = 2 end), "version")
		expect.equal(bent(function(x) x.mode = "duel" end), "mode")
		expect.equal(bent(function(x) x.kind = "duel" end), "mode")
		expect.equal(bent(function(x) x.mapId = "T1" end), "map") -- a Team map for a Free for All
		expect.equal(bent(function(x) x.mapId = "Nope" end), "map")
		expect.equal(bent(function(x) x.players = { 1, 1 } end), "players")
		expect.equal(bent(function(x) x.players = { 1.5 } end), "players")
		expect.equal(bent(function(x) x.players = {} end), "players")
		expect.equal(bent(function(x)
			x.players = {}
			for i = 1, 13 do
				x.players[i] = i
			end
		end), "players")
		expect.equal(bent(function(x) x.teams = { ["99"] = "Strawberry" } end), "teams")
		expect.equal(bent(function(x) x.home = "" end), "ids")
		expect.equal(MatchTicket.read("hello", maps), nil)
	end)
end
