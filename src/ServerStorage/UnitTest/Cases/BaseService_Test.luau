--!strict
-- BaseService_Test: unit tests for ServerScriptService.Server.Services.BaseService with injected fakes (a recorded
-- task.delay that the test runs by hand, a fake plot spawn); players are Folder instances (they carry the SD_Plot
-- attribute) or plain tables. Server only (ServerStorage.UnitTest). Edit mode: no Player, no world.
-- Contract (lobby bases spec 2026-10-11 §2, §4, §6; build plan Phase 3):
--   * 10 plots (WorldLayout.Bases); a joining player gets the lowest free plot, shown in the SD_Plot attribute; a plot
--     freed on leave is handed out again; rejoining gives the lowest free plot (the capsules live in the profile);
--   * with no plot free the player waits in the hub: the service tries again every 0.5 s for 5 s (10 tries) and gives
--     the plot that frees meanwhile; after 5 s it stops; a waiting player who leaves stops the retries;
--   * the plot's spawn is asked for the plot handed out and used only once the world has one (Phase 4).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BaseService = t.requireServer("Services/BaseService")
	local WorldLayout = t.requireShared("World/WorldLayout")

	type World = { delays: { { seconds: number, fn: () -> () } }, asked: { number }, made: { Instance } }

	local function fresh(): World
		local w: World = { delays = {}, asked = {}, made = {} }
		BaseService.reset()
		BaseService.useDeps({
			delay = function(seconds: number, fn: () -> ())
				table.insert(w.delays, { seconds = seconds, fn = fn })
			end,
			spawnOf = function(plot: number): any
				table.insert(w.asked, plot)
				return nil -- no plot is built before Phase 4
			end,
		})
		return w
	end

	local function finish(w: World)
		BaseService.reset()
		BaseService.useDeps(nil)
		for _, instance in w.made do
			instance:Destroy()
		end
	end

	local function newPlayer(w: World, name: string): any
		local player = Instance.new("Folder")
		player.Name = name
		table.insert(w.made, player)
		return player
	end

	-- Runs the delayed calls scheduled so far (one round of retries). Returns how many ran.
	local function runDelays(w: World): number
		local due = w.delays
		w.delays = {}
		for _, call in due do
			expect.equal(call.seconds, 0.5)
			call.fn()
		end
		return #due
	end

	-- Fills every plot; returns the players in plot order.
	local function fill(w: World): { any }
		local players = {}
		for index = 1, 10 do
			local player = newPlayer(w, "P" .. index)
			BaseService.playerAdded(player)
			players[index] = player
		end
		return players
	end

	t.test("10 plots, the lowest free one per joining player, in the SD_Plot attribute; leaving frees it", function()
		local w = fresh()
		expect.equal(#WorldLayout.Bases.frames, 10)
		local a, b, c = newPlayer(w, "A"), newPlayer(w, "B"), newPlayer(w, "C")
		for _, player in { a, b, c } do
			BaseService.playerAdded(player)
		end
		expect.equal(BaseService.plotOf(a), 1)
		expect.equal(BaseService.plotOf(b), 2)
		expect.equal(BaseService.plotOf(c), 3)
		expect.equal(b:GetAttribute("SD_Plot"), 2)
		expect.equal(BaseService.ownerOf(3), c)
		expect.deepEqual(w.asked, { 1, 2, 3 }) -- each plot's spawn is asked for (none exists before Phase 4)
		BaseService.playerRemoving(b)
		expect.equal(BaseService.plotOf(b), nil)
		expect.equal(BaseService.ownerOf(2), nil) -- an open plot again
		local d = newPlayer(w, "D")
		BaseService.playerAdded(d)
		expect.equal(BaseService.plotOf(d), 2) -- the lowest free one
		-- Rejoining gives the lowest free plot, maybe another one (the capsule levels live in the profile).
		BaseService.playerAdded(b)
		expect.equal(BaseService.plotOf(b), 4)
		expect.equal(#w.delays, 0)
		-- A player who is not an Instance (a plain table) gets a plot too, without the attribute.
		local plain = { UserId = 5 }
		BaseService.playerAdded(plain :: any)
		expect.equal(BaseService.plotOf(plain), 5)
		finish(w)
	end)

	t.test("a full server: the 11th waits in the hub, retries every 0.5 s and gets the plot that frees", function()
		local w = fresh()
		local players = fill(w)
		local late = newPlayer(w, "Late")
		BaseService.playerAdded(late)
		expect.equal(BaseService.plotOf(late), nil)
		expect.equal(late:GetAttribute("SD_Plot"), nil)
		expect.equal(#w.delays, 1)
		for _ = 1, 3 do
			expect.equal(runDelays(w), 1) -- still full: the next retry is scheduled
			expect.equal(BaseService.plotOf(late), nil)
		end
		BaseService.playerRemoving(players[7])
		expect.equal(runDelays(w), 1)
		expect.equal(BaseService.plotOf(late), 7)
		expect.equal(late:GetAttribute("SD_Plot"), 7)
		expect.equal(#w.delays, 0) -- found: no more retries
		finish(w)
	end)

	t.test("no plot frees within 5 s: 10 tries, then the player stays in the hub; leaving stops the retries", function()
		local w = fresh()
		fill(w)
		local late = newPlayer(w, "Late")
		BaseService.playerAdded(late)
		local tries = 0
		while #w.delays > 0 do
			tries += runDelays(w)
		end
		expect.equal(tries, 10) -- every 0.5 s for 5 s
		expect.equal(BaseService.plotOf(late), nil)
		-- A waiting player who leaves: the pending retry does nothing and schedules no other.
		local gone = newPlayer(w, "Gone")
		BaseService.playerAdded(gone)
		BaseService.playerRemoving(gone)
		expect.equal(runDelays(w), 1)
		expect.equal(#w.delays, 0)
		expect.equal(BaseService.plotOf(gone), nil)
		finish(w)
	end)
end
