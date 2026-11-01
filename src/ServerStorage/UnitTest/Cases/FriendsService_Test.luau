--!strict
-- FriendsService_Test: ServerScriptService.Server.Services.FriendsService, who is friends with whom in this server
-- (2026-10-31, the owner's plan step 1). Server only (ServerStorage.UnitTest). Edit mode: init() is never called;
-- the players are FakePlayers, isFriendsWith is a fake and spawn keeps the calls until a case runs them.
-- Contract:
--   * a join asks once for every other player here; a yes counts both ways, a no or an error counts as not friends;
--   * areFriends never yields and is false for anyone not here;
--   * leaving forgets the player, also for an answer that comes back after they left.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local FriendsService = t.requireServer("Services/FriendsService")
	local FakePlayer = t.requireFake("FakePlayer")

	-- Players 1 and 2 are friends; asking about player 3 errors; everyone else is not friends.
	local function setup(): any
		local w: any = { players = {}, calls = {}, asked = 0 }
		FriendsService.useDeps({
			players = function(): { any }
				return w.players
			end,
			isFriendsWith = function(player: any, userId: number): boolean
				w.asked += 1
				if player.UserId == 3 or userId == 3 then
					error("web call failed")
				end
				return (player.UserId == 1 and userId == 2) or (player.UserId == 2 and userId == 1)
			end,
			spawn = function(fn: (...any) -> ...any, ...: any)
				table.insert(w.calls, { fn = fn, args = table.pack(...) })
			end,
		})
		function w.join(userId: number): any
			local player = FakePlayer.new(userId, `P{userId}`)
			table.insert(w.players, player)
			FriendsService.playerAdded(player)
			return player
		end
		function w.leave(player: any)
			table.remove(w.players, table.find(w.players, player) :: number)
			FriendsService.playerRemoving(player)
		end
		function w.answer()
			local calls = w.calls
			w.calls = {}
			for _, call in calls do
				call.fn(table.unpack(call.args, 1, call.args.n))
			end
		end
		return w
	end

	t.test("a join asks about everyone here; friends count both ways, a no or an error does not", function()
		local w = setup()
		w.join(1)
		expect.equal(#w.calls, 0) -- alone: nobody to ask about
		w.join(2)
		w.join(3)
		w.join(4)
		expect.equal(#w.calls, 1 + 2 + 3)
		expect.equal(FriendsService.areFriends(1, 2), false) -- no answer yet
		w.answer()
		expect.equal(w.asked, 6)
		expect.equal(FriendsService.areFriends(1, 2), true)
		expect.equal(FriendsService.areFriends(2, 1), true)
		expect.equal(FriendsService.areFriends(1, 3), false)
		expect.equal(FriendsService.areFriends(2, 4), false)
		expect.equal(FriendsService.areFriends(1, 99), false)
	end)

	t.test("leaving forgets the player, also for an answer that comes back after they left", function()
		local w = setup()
		local one = w.join(1)
		w.join(2)
		w.answer()
		w.leave(one)
		expect.equal(FriendsService.areFriends(1, 2), false)
		expect.equal(FriendsService.areFriends(2, 1), false)
		-- 1 comes back, then leaves before Roblox answers.
		one = w.join(1)
		w.leave(one)
		w.answer()
		expect.equal(FriendsService.areFriends(1, 2), false)
		expect.equal(FriendsService.areFriends(2, 1), false)
	end)
end
