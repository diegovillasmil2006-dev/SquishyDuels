--!strict
-- MatchServerService_Test: ServerScriptService.Server.Services.MatchServerService.kindOf (owner bug 2026-11-02: Studio's
-- Team Test server has a PrivateServerId and no owner, like a reserved match server, so QUEUE / PLAY tried to teleport
-- "home" there and matchmaking never started). Contract: only a reserved server a match ticket reached is a match
-- server; a public server and a player's VIP server are lobbies; a reserved server with no ticket yet is "reserved".

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local MatchServerService = t.requireServer("Services/MatchServerService")
	local expect = t.expect

	t.test("kindOf: a public server and a VIP server are lobbies, ticket or not", function()
		expect.equal(MatchServerService.kindOf("", 0, false), "lobby")
		expect.equal(MatchServerService.kindOf("", 0, true), "lobby")
		expect.equal(MatchServerService.kindOf("vip-1", 12345, false), "lobby")
		expect.equal(MatchServerService.kindOf("vip-1", 12345, true), "lobby")
	end)

	t.test("kindOf: a reserved server is a match server only once a match ticket reached it (Team Test never)", function()
		expect.equal(MatchServerService.kindOf("guid-1", 0, false), "reserved")
		expect.equal(MatchServerService.kindOf("guid-1", 0, true), "match")
	end)

	t.test("in Studio (no private server, no ticket) the server is neither reserved nor a match server", function()
		expect.falsy(MatchServerService.isReservedServer())
		expect.falsy(MatchServerService.isMatchServer())
	end)
end
