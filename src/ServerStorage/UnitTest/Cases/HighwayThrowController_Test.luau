--!strict
-- HighwayThrowController_Test: unit tests for StarterPlayerScripts.Client.Controllers.HighwayThrowController (pens3
-- phase 13: the throw on the launch deck's open area, this client's side). Server only (ServerStorage.UnitTest). Edit
-- mode: no LocalPlayer, so start() binds nothing and finds no character; its pure parts are tested here.
-- Contract (the lobby design v6: P3D = "Squishy Lobby 3D.html", K = kit.json):
--   * Config.UI.Highway holds P3D's follow camera (P3D:849: 6 right, 8 up, 28 behind, looking 8 ahead and 0.5 up, at
--     3.5 / 5 a second; let go 2.5 s after the landing, P3D:850), its tumble (P3D:587, :593: 7, then 8 x (1 - v) +
--     0.5) and K's E5 trail (1.2 wide, 0.4 s);
--   * mayForward(sent, oldestPending, now, cap, late): a press during the own flight is sent for the auto-clicker check
--     at most `cap` times in any rolling second, never while a reply is more than `late` seconds late (the list keeps
--     only the last second's sends);
--   * followGoal(p): the camera's goal for a squishy at lane-local (x, y, d): side right, up above and back behind it
--     (toward the deck), looking down the lane lookAhead past it;
--   * landingToasts(data): the landing (distance, Coins, Grip), then a new best, a new biome (its name; none for the
--     Golden Gates), the gifts (one line a kind, with its count) and the Food Bag, each only when it happened;
--   * pillText(d): the biome the flying squishy is over and its distance, never below 0;
--   * init / start / destroy run cleanly in Edit mode and leave nothing behind (no Scheduler effect, the Highway
--     context off; with no LocalPlayer start binds no action and adds no effect: it only works for a client);
--   * verification fixes (useDeps: a client, scripted replies, a private scheduler): start binds HighwayThrow and adds
--     one effect, destroy removes both; a press during the own flight that the server answers highway.autoClick shows
--     that warning (the 1st catch's calm notice), other refusals stay silent, and an ok answer (it reached the server
--     as the flight ended: a real throw) becomes the throw shown, the old one landing first; every send, a throw's
--     first press too, counts toward clientPressesPerSecond in a rolling second.
--   * p13v3 (owner 2026-10-18: "Yes, above 20 a second"): every real THROW press counts on the client's clock
--     (Shared/PressSpeed), the ones during a flight and the ones the cap holds back too; each send reports the seconds
--     in a row over 20 presses (25 a second for 3 s during a flight: 2 while the 3rd second is still under the line,
--     3 on the next send); a press the server answers highway.superFast (the speed rule's catch) shows that warning,
--     during a flight too.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local HighwayThrowController = t.requireClient("Controllers/HighwayThrowController")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local Format = t.requireShared("Util/Format")
	local WorldLayout = t.requireShared("World/WorldLayout")
	local U = Config.UI.Highway

	t.test("Config.UI.Highway holds P3D's follow camera and tumble and K's E5 trail", function()
		expect.deepEqual(
			U.follow,
			{ side = 6, up = 8, back = 28, lookAhead = 8, lookUp = 0.5, posRate = 3.5, lookRate = 5, holdSeconds = 2.5 }
		)
		expect.deepEqual({ U.spinAir, U.spinRoll, U.spinRollMin }, { 7, 8, 0.5 })
		expect.deepEqual(U.trail, { width = 1.2, lifetime = 0.4 })
		expect.truthy(U.lateReplySeconds > 0)
	end)

	t.test("mayForward: at most the cap in a rolling second, none while a reply is late", function()
		local sent: { number } = {}
		local cap = Config.Economy.Highway.autoClick.clientPressesPerSecond
		for i = 1, cap do
			expect.truthy(HighwayThrowController.mayForward(sent, nil, 10 + i * 0.01, cap, 1))
			table.insert(sent, 10 + i * 0.01)
		end
		expect.falsy(HighwayThrowController.mayForward(sent, nil, 10.5, cap, 1)) -- the cap inside a second
		expect.truthy(HighwayThrowController.mayForward(sent, nil, 11.015, cap, 1)) -- the oldest left the second
		expect.equal(#sent, cap - 1) -- only the last second's are kept
		expect.falsy(HighwayThrowController.mayForward({}, 20, 21.5, cap, 1)) -- a reply 1.5 s late
		expect.truthy(HighwayThrowController.mayForward({}, 20, 20.5, cap, 1))
	end)

	t.test("followGoal: right of, above and behind the squishy, looking down the lane past it", function()
		local origin: CFrame = WorldLayout.Highway.origin
		local p = Vector3.new(2, 3, 500) -- lane-local x, y and d
		local eye, look = HighwayThrowController.followGoal(p)
		local squishy = WorldLayout.highwayCFrame(2, 3, 500).Position
		local localEye = origin:PointToObjectSpace(eye)
		expect.near(localEye.X, 2 + U.follow.side, 1e-3)
		expect.near(localEye.Y, 3 + U.follow.up, 1e-3)
		expect.near(-localEye.Z, 500 - U.follow.back, 1e-3) -- behind it, toward the deck
		local localLook = origin:PointToObjectSpace(look)
		expect.near(-localLook.Z, 500 + U.follow.lookAhead, 1e-3)
		expect.near(localLook.Y, 3 + U.follow.lookUp, 1e-3)
		expect.truthy((look - eye).Unit:Dot(origin.LookVector) > 0.5) -- it looks down the lane
		expect.truthy((squishy - eye).Magnitude < U.follow.back + U.follow.up + U.follow.side)
	end)

	t.test("landingToasts: the landing, then a best, a biome, the gifts and the Food Bag when they happened", function()
		local base = {
			studs = 21,
			biome = 1,
			power = 2,
			flight = 2.1,
			landsAt = 0,
			coins = 700,
			grip = 600,
			best = 21,
			newBest = false,
			gifts = {},
			charged = false,
			savePending = false,
		}
		local plain = HighwayThrowController.landingToasts(base :: any)
		expect.equal(#plain, 1)
		expect.equal(
			plain[1].text,
			Strings.format(
				Strings.highway.landed,
				{ distance = "21", coins = Format.coins(700), grip = Format.coins(600) }
			)
		)
		expect.equal(plain[1].kind, "success")
		local all = table.clone(base) :: any
		all.newBest = true
		all.reached = 3
		all.gifts = { "boba_bear", "boba_bear", "boba_bear", "bird" }
		all.food = { id = "candy_drop", count = 2 }
		local texts = {}
		for _, toast in HighwayThrowController.landingToasts(all) do
			table.insert(texts, toast.text)
		end
		local gift = Strings.highway.gift
		local Catalog = t.requireShared("Catalog")
		local function nameOf(id: string): string
			return Strings.resolve((Catalog.get(id) :: any).nameKey) :: string
		end
		expect.deepEqual(texts, {
			plain[1].text,
			Strings.format(Strings.highway.newBest, { distance = "21" }),
			Strings.format(Strings.highway.reached, { biome = Strings.highway.biome.bobaLagoon }),
			Strings.format(gift.many, { count = 3, name = nameOf("boba_bear") }),
			Strings.format(gift.one, { count = 1, name = nameOf("bird") }),
			Strings.format(Strings.highway.foodBag, { count = 2, food = "Candy Drop" }),
		})
		local gates = table.clone(base) :: any
		gates.reached = 8 -- the Golden Gates: no biome name
		expect.equal(#HighwayThrowController.landingToasts(gates), 1)
	end)

	t.test("pillText: the biome the flying squishy is over and its distance, never below 0", function()
		local flying = Strings.highway.flying
		expect.equal(
			HighwayThrowController.pillText(1234.6),
			Strings.format(flying, { biome = Strings.highway.biome.bobaLagoon, distance = "1,234" })
		)
		expect.equal(
			HighwayThrowController.pillText(-30), -- still over the deck
			Strings.format(flying, { biome = Strings.highway.biome.candyMeadow, distance = "0" })
		)
	end)

	t.test("init / start / destroy run cleanly in Edit mode and leave nothing behind", function()
		local effects = Scheduler.count()
		HighwayThrowController.init()
		HighwayThrowController.start()
		expect.equal(HighwayThrowController.debugState().started, true)
		HighwayThrowController.destroy()
		expect.equal(Scheduler.count(), effects)
		expect.equal(HighwayThrowController.debugState().started, false)
		expect.equal(HighwayThrowController.debugState().inArea, false)
		expect.equal(HighwayThrowController.debugState().throwing, false)
		HighwayThrowController.destroy() -- twice is fine
	end)

	-- Verification fixes: the press path, driven through useDeps (a client, the action's handler kept, scripted
	-- replies) and a private scheduler.
	local Workspace = game:GetService("Workspace")

	local function driven(replies: { any }, otherwise: any?): any
		local w: any =
			{ action = nil, handler = nil, unbound = 0, sent = 0, shown = {}, toasts = {}, reports = {}, now = 10 }
		HighwayThrowController.destroy() -- a case that failed midway left it running
		HighwayThrowController.useDeps({
			isClient = function(): boolean
				return true
			end,
			bindAction = function(action: string, handler: any): () -> ()
				w.action, w.handler = action, handler
				return function()
					w.unbound += 1
				end
			end,
			invoke = function(_remote: string, _clientTime: number, fastSeconds: number?): any
				w.sent += 1
				table.insert(w.reports, fastSeconds or "none")
				return table.remove(replies, 1) or otherwise or { ok = false, reason = "highway.inFlight" }
			end,
			showResult = function(result: any): boolean
				table.insert(w.shown, result.reason)
				return true
			end,
			toast = function(text: string)
				table.insert(w.toasts, text)
			end,
			clock = function(): number
				return w.now
			end,
		})
		w.scheduler = Scheduler.new(false)
		HighwayThrowController.start(w.scheduler)
		return w
	end

	local function stop()
		HighwayThrowController.destroy()
		HighwayThrowController.useDeps(nil)
	end

	-- An ok reply: a 21-stud throw landing `seconds` from now on the server's clock.
	local function thrown(seconds: number): any
		return {
			ok = true,
			data = {
				studs = 21,
				biome = 1,
				power = 2,
				flight = 2.1,
				landsAt = Workspace:GetServerTimeNow() + seconds,
				coins = 700,
				grip = 600,
				best = 21,
				newBest = false,
				gifts = {},
				charged = false,
				savePending = false,
			},
		}
	end

	t.test("start binds the THROW and adds one effect; destroy removes both", function()
		local w = driven({})
		expect.equal(w.action, "HighwayThrow")
		expect.equal(w.scheduler:count("render"), 1)
		stop()
		expect.equal(w.unbound, 1)
		expect.equal(w.scheduler:count("render"), 0)
		expect.equal(HighwayThrowController.debugState().started, false)
		expect.equal(HighwayThrowController.debugState().inArea, false) -- its Highway context is on only while inArea
	end)

	t.test(
		"a press during the flight: an auto-clicker catch shows its warning; an ok reply is the new throw",
		function()
			local first, second = thrown(50), thrown(53)
			local w = driven({
				first,
				{ ok = false, reason = "highway.autoClick" },
				{ ok = false, reason = "highway.inFlight" },
				second,
			})
			local press = w.handler
			expect.equal(press(Enum.UserInputState.Begin), true) -- the throw
			expect.equal(HighwayThrowController.debugState().landsAt, first.data.landsAt)
			press(Enum.UserInputState.Begin) -- during its flight: the check's 1st catch, the calm warning
			expect.deepEqual(w.shown, { "highway.autoClick" })
			press(Enum.UserInputState.Begin) -- still in flight: silent
			expect.deepEqual(w.shown, { "highway.autoClick" })
			press(Enum.UserInputState.Begin) -- it reached the server as the flight ended: the server threw it
			expect.equal(HighwayThrowController.debugState().landsAt, second.data.landsAt)
			expect.equal(w.toasts[1], HighwayThrowController.landingToasts(first.data)[1].text) -- the 1st still lands
			expect.equal(w.sent, 4)
			stop()
		end
	)

	t.test("p13v3: every press counts on the client's clock, the ones during a flight and past the cap too", function()
		local cap = Config.Economy.Highway.autoClick.clientPressesPerSecond
		local w = driven({ thrown(50) }) -- one throw; every press during its flight is answered highway.inFlight
		for second = 0, 2 do -- 25 presses a second for 3 s: only `cap` of them a second are sent
			for i = 1, 25 do
				w.now = 100 + second + i / 26
				w.handler(Enum.UserInputState.Begin)
			end
		end
		expect.truthy(#w.reports <= 3 * cap)
		expect.equal(w.reports[1], 0) -- the throw's own press
		for i = 2, #w.reports do
			-- The 3rd second goes over the line at its 21st press, after its `cap` sends: 2 so far.
			expect.truthy(w.reports[i] == 0 or w.reports[i] == 1 or w.reports[i] == 2)
		end
		expect.equal(w.reports[#w.reports], 2)
		w.now = 103.2 -- the rolling second is over: the next press reports the 3rd second too
		w.handler(Enum.UserInputState.Begin)
		expect.equal(w.reports[#w.reports], 3)
		expect.equal(w.handler(Enum.UserInputState.End), nil) -- a release is no press
		stop()
	end)

	t.test("p13v3: a press the server answers highway.superFast shows that warning, during a flight too", function()
		local w = driven({ thrown(50), { ok = false, reason = "highway.superFast" } })
		w.handler(Enum.UserInputState.Begin) -- the throw
		w.handler(Enum.UserInputState.Begin) -- during its flight: the speed rule's catch
		expect.deepEqual(w.shown, { "highway.superFast" })
		stop()
		local first = driven({ { ok = false, reason = "highway.superFast" } })
		first.handler(Enum.UserInputState.Begin) -- a throw's own press
		expect.deepEqual(first.shown, { "highway.superFast" })
		stop()
	end)

	t.test("at most clientPressesPerSecond presses are sent in a rolling second, a throw's first press too", function()
		local cap = Config.Economy.Highway.autoClick.clientPressesPerSecond
		local w = driven({}, { ok = false, reason = "highway.notInArea" }) -- every press starts a throw, refused
		for _ = 1, cap + 3 do
			w.handler(Enum.UserInputState.Begin)
		end
		expect.equal(w.sent, cap)
		expect.equal(#w.shown, cap)
		stop()
	end)
end
