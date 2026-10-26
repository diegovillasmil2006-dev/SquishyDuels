--!strict
-- HighwayThrowController_Test: unit tests for StarterPlayerScripts.Client.Controllers.HighwayThrowController (pens3
-- phase 13: the throw on the launch deck's open area, this client's side; p13v4: the TikTok throw, work/pens3/p13v4/
-- SPEC.md 4). Server only (ServerStorage.UnitTest). Edit mode: no LocalPlayer, so start() binds nothing and finds no
-- character; its pure parts are tested here, and the press, the deck and the launch through useDeps (a client, a body
-- in or out of the throw area, scripted replies, stand-ins for the player's zoom, the camera, the HUD, the holds
-- and the held toy) and a private scheduler ticked by hand (ReducedMotion on, so no camera shot is taken).
-- Contract:
--   * shotGoal(kind, p): the three shots (Config.UI.Highway, lane-local): "throw" right of, above and in front of the
--     player looking at it; "chase" high behind the squishy looking down the lane past it; "landing" right of,
--     above and behind it looking at it;
--   * mayForward(sent, oldestPending, now, cap, late): a press during the own flight is sent for the auto-clicker check
--     at most `cap` times in any rolling second, never while a reply is more than `late` seconds late (the list keeps
--     only the last second's sends);
--   * landingToasts(landing): the landing (distance, Coins, Grip), then a new best, a new biome (its name; none for the
--     Golden Gates), the gifts (one line a kind, with its count) and the Food Bag, each only when it happened;
--   * zoneBanner(biome, level) (Claude Design's zone banner): the zone's name in its colour, "Recommended:" and its
--     power wall, ready from the first Grip level whose throw reaches the wall, its difficulty and tag; nil for no zone;
--   * init / start / destroy run cleanly in Edit mode and leave nothing behind (no Scheduler effect, the Highway
--     context off; with no LocalPlayer start binds no action and adds no effect: it only works for a client);
--   * the deck (owner 2026-10-19: no first-person hands while the camera is not the player's own first person): in the
--     area (alive) the player's zoom is raised to deck.zoomStuds (third person), held at the saved distance for
--     deck.restoreFrames steps after leaving, then written back exactly; never while first person is on; `away`
--     (FirstPersonController.setAway) follows "in the area or launching";
--   * a press launches at once: the screen hold (every other SD_ gui hidden) and the toast hold; finish (here: dying
--     mid-flight) releases both and shows the held toy again;
--   * replies during the own flight: boosted -> the plan swaps and "SQUISH!" pops (+ "LAST ONE!" with no fuel left);
--     highway.noFuel is silent; an auto-clicker catch shows its warning; an ok (not boosted) reply is the new throw;
--   * the flight (server time): the lines count the distance, the zone and the rings hit so far (ring 1 of
--     WorldLayout.Highway.rings is passed through at d 81) with the boost button until the air ends; at landsAt the
--     landing pops "{N} studs!" and bursts; HighwayLanded then pops BULLSEYE! with the rings and NEW BEST!; the
--     landing shot lets go holdSeconds later (finish: the toasts);
--   * HighwayLanded: for the current throw it is kept (its pops and toasts come with the landing); for any other id
--     (an older throw, one already finished) its toasts show at once;
--   * p13v3 (owner 2026-10-18: "Yes, above 20 a second"): every real THROW press counts on the client's clock
--     (Shared/PressSpeed), the ones during a flight and the ones the cap holds back too; each send reports the seconds
--     in a row over 20 presses; a press the server answers highway.superFast shows that warning, during a flight too.

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
	local origin: CFrame = WorldLayout.Highway.origin
	local AREA = WorldLayout.Highway.throwArea
	local IN_AREA = origin:PointToWorldSpace(AREA.position)
	local OUTSIDE = origin:PointToWorldSpace(AREA.position + Vector3.new(0, 0, 60))

	-- Lane-local (x, y, d) of a world point.
	local function lane(world: Vector3): Vector3
		local l = origin:PointToObjectSpace(world)
		return Vector3.new(l.X, l.Y, -l.Z)
	end

	t.test("shotGoal: the throw shot, the chase and the landing shot (Config.UI.Highway, lane-local)", function()
		local p = Vector3.new(2, 3, 500)
		local eye, look = HighwayThrowController.shotGoal("throw", p)
		local s = U.throwShot
		expect.near((lane(eye) - Vector3.new(2 + s.side, 3 + s.up, 500 + s.front)).Magnitude, 0, 1e-3)
		expect.near((lane(look) - Vector3.new(2, 3 + s.lookUp, 500)).Magnitude, 0, 1e-3)
		eye, look = HighwayThrowController.shotGoal("chase", p)
		local c = U.chase
		expect.near((lane(eye) - Vector3.new(2, 3 + c.up, 500 - c.back)).Magnitude, 0, 1e-3)
		expect.near((lane(look) - Vector3.new(2, 3 + c.lookUp, 500 + c.lookAhead)).Magnitude, 0, 1e-3)
		expect.truthy((look - eye).Unit:Dot(origin.LookVector) > 0.5) -- it looks down the lane
		eye, look = HighwayThrowController.shotGoal("landing", p)
		local l = U.landingShot
		expect.near((lane(eye) - Vector3.new(2 + l.side, 3 + l.up, 500 - l.back)).Magnitude, 0, 1e-3)
		expect.near((lane(look) - p).Magnitude, 0, 1e-3)
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

	local function landingOf(id: number): any
		return {
			id = id,
			studs = 213,
			biome = 1,
			coins = 1065,
			grip = 600,
			best = 213,
			newBest = false,
			gifts = {},
			rings = {},
			bullseye = false,
			perfect = false,
			boosts = 0,
		}
	end

	t.test("landingToasts: the landing, then a best, a biome, the gifts and the Food Bag when they happened", function()
		local base = landingOf(1)
		base.studs, base.coins = 21, 700
		local plain = HighwayThrowController.landingToasts(base)
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

	t.test("zoneBanner: the zone's name, its Recommended power, ready from the first Grip level that reaches it", function()
		local HighwayMath = t.requireShared("HighwayMath")
		local wall = Config.Economy.Highway.walls[3]
		local def = WorldLayout.Highway.biomes[3]
		local s = Strings.highway.screen
		local level = 1
		while HighwayMath.power(level) < wall and level < 1000 do
			level += 1
		end
		expect.truthy(level > 1 and level < 1000)
		local banner = HighwayThrowController.zoneBanner(3, level) :: any
		expect.equal(banner.name, Strings.resolve(def.nameKey))
		expect.equal(banner.nameColor, def.nameColor)
		expect.equal(banner.label, s.recommended)
		expect.equal(banner.value, Strings.format(s.recommendedValue, { power = Format.power(wall) }))
		expect.equal(banner.difficulty, 3)
		expect.equal(banner.tag, s.difficulty[3])
		expect.truthy(banner.ready)
		expect.falsy((HighwayThrowController.zoneBanner(3, level - 1) :: any).ready)
		expect.equal(HighwayThrowController.zoneBanner(99, 1), nil)
		-- Gear step 2: the gear counts too (a whole held launcher line at Lv 1 is past zone 3's wall).
		local gear = { held = 36, platform = 0, arm = 0, armor = 0 }
		expect.truthy((HighwayThrowController.zoneBanner(3, 1, gear) :: any).ready)
		expect.falsy((HighwayThrowController.zoneBanner(3, 1, nil) :: any).ready)
	end)

	t.test("gear step 3: the trail is the held launcher's zone colour, white without one", function()
		local Palette = t.requireShared("Art/Palette")
		local biomes = WorldLayout.Highway.biomes
		expect.equal(HighwayThrowController.trailColor(nil), Color3.new(1, 1, 1))
		expect.equal(HighwayThrowController.trailColor({ held = 0, platform = 4, arm = 4, armor = 1 }), Color3.new(1, 1, 1))
		expect.equal(HighwayThrowController.trailColor({ held = 1 }), (Palette :: any)[biomes[1].nameColor])
		expect.equal(HighwayThrowController.trailColor({ held = 36 }), (Palette :: any)[biomes[7].nameColor])
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

	-- The press path and the deck, driven through useDeps and a private scheduler.

	local SAVED_MIN, SAVED_MAX, DISTANCE = 0.5, 128, 0.5 -- a player in their own first person (zoomed into the head)

	local function driven(replies: { any }, otherwise: any?): any
		local w: any = {
			action = nil,
			handler = nil,
			unbound = 0,
			sent = 0,
			shown = {},
			toasts = {},
			reports = {},
			now = 10,
			server = 1000,
			body = nil,
			alive = true,
			fp = false,
			aways = {},
			toastHolds = {},
			holds = {},
			hidden = {},
			pops = {},
			writes = {},
			contexts = {},
			liveToasts = {}, -- toasts shown while the toast hold was off (UIController queues the others)
			queued = {},
		}
		-- The player's zoom limits, every write counted by key.
		local zoom = { CameraMinZoomDistance = SAVED_MIN, CameraMaxZoomDistance = SAVED_MAX }
		w.zoom = zoom
		w.player = setmetatable({}, {
			__index = zoom,
			__newindex = function(_, key: string, value: any)
				zoom[key] = value
				w.writes[key] = (w.writes[key] or 0) + 1
			end,
		})
		w.camera = { CFrame = CFrame.new(0, 10, DISTANCE), Focus = CFrame.new(0, 10, 0) }
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
				local reply = table.remove(replies, 1) or otherwise or { ok = false, reason = "highway.inFlight" }
				return if type(reply) == "function" then reply() else reply -- a function: a slow reply
			end,
			showResult = function(result: any): boolean
				table.insert(w.shown, result.reason)
				return true
			end,
			toast = function(text: string)
				table.insert(w.toasts, text)
				table.insert(if w.holding then w.queued else w.liveToasts, text)
			end,
			clock = function(): number
				return w.now
			end,
			setContext = function(context: string, on: boolean)
				w.contexts[context] = on
			end,
			lobbyWanted = function(): boolean
				return true
			end,
			input = function(): Enum.PreferredInput
				return Enum.PreferredInput.Touch
			end,
			serverNow = function(): number
				return w.server
			end,
			body = function(): (Vector3?, boolean)
				return w.body, w.alive
			end,
			locked = function(): boolean
				return false
			end,
			blocked = function(): boolean
				return false
			end,
			reducedMotion = function(): boolean
				return true
			end,
			fpActive = function(): boolean
				return w.fp
			end,
			player = function(): any
				return w.player
			end,
			camera = function(): any
				return w.camera
			end,
			setAway = function(on: boolean)
				table.insert(w.aways, on)
			end,
			holdToasts = function(on: boolean)
				table.insert(w.toastHolds, on)
				w.holding = on
				if not on then
					for _, text in w.queued do
						table.insert(w.liveToasts, text)
					end
					table.clear(w.queued)
				end
			end,
			newHold = function(): any
				local hold = { steps = 0, released = false }
				function hold.step(self: any)
					self.steps += 1
				end
				function hold.release(self: any)
					self.released = true
				end
				table.insert(w.holds, hold)
				return hold
			end,
			heldHidden = function(hidden: boolean)
				table.insert(w.hidden, hidden)
			end,
			heldOverlay = function(_overlay: any): boolean
				return true
			end,
			burst = function(at: Vector3)
				w.burst = at
			end,
			spawn = function(kind: string): (any, any)
				w.spawned = kind
				return nil, nil
			end,
			onLanded = function(handler: any): () -> ()
				w.landed = handler
				return function()
					w.landed = nil
				end
			end,
			newHud = function(_onBoost: () -> ()): any
				local hud = {}
				function hud.setBar(_: any, shown: boolean)
					w.bar = shown
				end
				function hud.setFlight(_: any, view: any)
					w.flight = view
				end
				function hud.pop(_: any, lines: { any })
					local texts = {}
					for _, line in lines do
						table.insert(texts, line.text)
					end
					table.insert(w.pops, texts)
				end
				function hud.punch() end
				function hud.zoneBanner() end -- Claude Design's zone banner (HighwayThrowController.zoneBanner's own test)
				function hud.destroy()
					w.hudDestroyed = true
				end
				return hud
			end,
		})
		w.scheduler = Scheduler.new(false)
		HighwayThrowController.start(w.scheduler)
		function w.tick(frames: number?)
			for _ = 1, frames or 1 do
				w.scheduler:tick("render", 1 / 60, w.now)
			end
		end
		return w
	end

	local function stop()
		HighwayThrowController.destroy()
		HighwayThrowController.useDeps(nil)
	end

	-- An ok reply: throw `id`, released 0.42 s after server time `t0` and stopping `seconds` after it.
	local function thrown(id: number, t0: number, seconds: number, fuel: number?, boosted: boolean?): any
		local arcs = {
			{ startAt = t0 + 0.42, from = -34.25, y0 = 7, carry = 191, air = 2.3, peak = 39.5 },
		}
		if boosted then
			table.insert(arcs, { startAt = t0 + 1.42, from = 60, y0 = 40, carry = 271, air = 1.4, peak = 36 })
		end
		return {
			ok = true,
			data = {
				id = id,
				perfect = false,
				x0 = 0,
				arcs = arcs,
				roll = 0.6,
				studs = if boosted then 301 else 213,
				biome = 1,
				landsAt = t0 + seconds,
				fuel = fuel or 1,
				boosted = boosted == true,
				charged = false,
				savePending = false,
			},
		}
	end

	t.test("start binds the THROW, makes the HUD and adds one effect; destroy removes them", function()
		local w = driven({})
		expect.equal(w.action, "HighwayThrow")
		expect.equal(w.scheduler:count("render"), 1)
		expect.equal(type(w.landed), "function")
		stop()
		expect.equal(w.unbound, 1)
		expect.equal(w.scheduler:count("render"), 0)
		expect.equal(w.landed, nil)
		expect.equal(w.hudDestroyed, true)
		expect.equal(HighwayThrowController.debugState().started, false)
		expect.equal(HighwayThrowController.debugState().inArea, false)
	end)

	t.test("the deck: third person at deckZoom, then the saved zoom held 2 steps and written back exactly", function()
		local w = driven({})
		local z = U.deck.zoomStuds
		w.body = IN_AREA
		w.tick()
		expect.equal(HighwayThrowController.debugState().inArea, true)
		expect.equal(w.zoom.CameraMinZoomDistance, math.max(SAVED_MIN, z))
		expect.equal(w.zoom.CameraMaxZoomDistance, math.max(SAVED_MAX, z))
		expect.equal(w.bar, true) -- the timing bar on the deck
		w.tick(3) -- written once
		expect.equal(w.writes.CameraMinZoomDistance, 1)
		w.body = OUTSIDE
		w.tick()
		expect.equal(w.zoom.CameraMinZoomDistance, DISTANCE) -- held at the saved distance (back into the head)
		expect.equal(w.zoom.CameraMaxZoomDistance, DISTANCE)
		w.tick()
		expect.equal(w.zoom.CameraMaxZoomDistance, DISTANCE)
		w.tick()
		expect.equal(w.zoom.CameraMinZoomDistance, SAVED_MIN)
		expect.equal(w.zoom.CameraMaxZoomDistance, SAVED_MAX)
		table.clear(w.writes)
		w.tick(3)
		expect.deepEqual(w.writes, {})
		stop()
	end)

	t.test("the deck: never touches the zoom while first person is on; destroy writes the saved zoom back", function()
		local w = driven({})
		w.fp = true
		w.body = IN_AREA
		w.tick(3)
		expect.deepEqual(w.writes, {})
		w.fp = false
		w.tick()
		expect.equal(w.zoom.CameraMaxZoomDistance, math.max(SAVED_MAX, U.deck.zoomStuds))
		stop()
		expect.equal(w.zoom.CameraMinZoomDistance, SAVED_MIN)
		expect.equal(w.zoom.CameraMaxZoomDistance, SAVED_MAX)
	end)

	t.test("away follows in the area or launching, and clears on destroy", function()
		local w = driven({ thrown(1, 1000, 50) })
		w.body = IN_AREA
		w.tick()
		expect.deepEqual(w.aways, { true })
		w.body = OUTSIDE
		w.tick()
		expect.deepEqual(w.aways, { true, false })
		w.body = IN_AREA
		w.tick()
		w.handler(Enum.UserInputState.Begin) -- a launch
		w.body = OUTSIDE -- walked off the deck mid-launch: still away
		w.tick(3)
		expect.deepEqual(w.aways, { true, false, true })
		stop()
		expect.deepEqual(w.aways, { true, false, true, false })
	end)

	t.test("a press holds the screen and the toasts; dying mid-flight releases both and shows the held toy", function()
		local w = driven({ thrown(1, 1000, 50) })
		w.body = IN_AREA
		w.tick()
		w.handler(Enum.UserInputState.Begin)
		expect.equal(#w.holds, 1)
		expect.deepEqual(w.toastHolds, { true })
		w.tick()
		expect.truthy(w.holds[1].steps >= 1)
		expect.equal(w.bar, false) -- no timing bar while launching
		expect.truthy(w.flight ~= nil) -- the flight lines instead
		w.alive = false
		w.tick()
		expect.equal(HighwayThrowController.debugState().throwing, false)
		expect.equal(w.holds[1].released, true)
		expect.deepEqual(w.toastHolds, { true, false })
		expect.equal(w.hidden[#w.hidden], false)
		expect.equal(w.flight, nil)
		stop()
	end)

	t.test("a boosted reply swaps the plan and pops SQUISH! + LAST ONE!; noFuel stays silent", function()
		local w = driven({
			thrown(7, 1000, 50, 1),
			thrown(7, 1000, 51, 0, true),
			{ ok = false, reason = "highway.noFuel" },
		})
		w.body = IN_AREA
		w.handler(Enum.UserInputState.Begin)
		expect.equal(HighwayThrowController.debugState().arcs, 1)
		w.handler(Enum.UserInputState.Begin) -- a boost
		expect.equal(HighwayThrowController.debugState().arcs, 2)
		expect.equal(HighwayThrowController.debugState().landsAt, 1051)
		local pop = Strings.highway.pop
		expect.deepEqual(w.pops[#w.pops], { pop.boost, pop.lastOne })
		local popped = #w.pops
		w.handler(Enum.UserInputState.Begin) -- no fuel left
		expect.deepEqual(w.shown, {})
		expect.equal(#w.pops, popped)
		stop()
	end)

	t.test(
		"a flight: lines, rings and boost; the landing pops and bursts; BULLSEYE with the payload; then finish",
		function()
			local reply = thrown(3, 1000, 3.0)
			reply.data.arcs[1].peak = 45 -- through ring 1 (d 81, y 55.2): y 49.4 there
			local w = driven({ reply })
			w.body = IN_AREA
			w.handler(Enum.UserInputState.Begin)
			w.tick()
			expect.deepEqual(w.flight, { studs = 0, biome = 1, ringsHit = 0, ringsTotal = 3 }) -- before the release
			w.now = 10.5 -- the windup is done and the plan is in: the release
			w.tick()
			expect.equal(type(w.spawned), "string")
			expect.equal(w.hidden[#w.hidden], true) -- the held toy hides
			w.server = 1000 + 0.42 + 1.2 -- mid-air, past ring 1
			w.tick()
			expect.equal(w.flight.studs, 83)
			expect.equal(w.flight.ringsHit, 1)
			expect.deepEqual(w.flight.boost, { fuel = 1, input = Enum.PreferredInput.Touch })
			w.server = 1003.1 -- past landsAt
			w.tick()
			local pop = Strings.highway.pop
			expect.deepEqual(w.pops[#w.pops], { Strings.format(pop.landed, { distance = "213" }) })
			expect.truthy(w.burst ~= nil)
			expect.equal(w.flight.boost, nil)
			local landing = landingOf(3)
			landing.bullseye, landing.rings, landing.newBest = true, { 1 }, true
			w.landed(landing)
			expect.deepEqual(
				w.pops[#w.pops],
				{ pop.bullseye, Strings.format(pop.rings, { hit = 1, total = 3 }), pop.newBest }
			)
			expect.deepEqual(w.toasts, {})
			w.now += U.landingShot.holdSeconds + 0.05
			w.tick()
			expect.equal(HighwayThrowController.debugState().throwing, false)
			expect.equal(w.toasts[1], HighwayThrowController.landingToasts(landing)[1].text)
			expect.equal(w.hidden[#w.hidden], false)
			stop()
		end
	)

	t.test("HighwayLanded: kept for the current throw; another id's toasts show at once", function()
		local w = driven({ thrown(7, 1000, 50) })
		w.body = IN_AREA
		w.handler(Enum.UserInputState.Begin)
		w.landed(landingOf(7))
		expect.deepEqual(w.toasts, {})
		expect.equal(HighwayThrowController.debugState().hasLanding, true)
		local older = landingOf(6)
		w.landed(older)
		expect.equal(w.toasts[1], HighwayThrowController.landingToasts(older)[1].text)
		w.landed("not a landing") -- ignored
		expect.equal(#w.toasts, 1)
		stop() -- finishing the throw shows the kept landing's toasts
		expect.equal(w.toasts[2], HighwayThrowController.landingToasts(landingOf(7))[1].text)
	end)

	t.test(
		"a press during the flight: an auto-clicker catch shows its warning; an ok reply is the new throw",
		function()
			local first, second = thrown(1, 1000, 50), thrown(2, 1000, 53)
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
			expect.truthy(w.burst ~= nil) -- the old one landed (its debris burst)
			expect.equal(HighwayThrowController.debugState().id, 2)
			expect.deepEqual(w.toastHolds, { true, true }) -- chained: the hold stays on into the new launch
			w.landed(landingOf(1)) -- the old throw's pay: its toasts, queued until the new launch ends
			expect.equal(w.toasts[1], HighwayThrowController.landingToasts(landingOf(1))[1].text)
			expect.deepEqual(w.liveToasts, {})
			expect.equal(w.sent, 4)
			stop()
		end
	)

	t.test("p13v3: every press counts on the client's clock, the ones during a flight and past the cap too", function()
		local cap = Config.Economy.Highway.autoClick.clientPressesPerSecond
		local w = driven({ thrown(1, 1000, 50) }) -- one throw; every press during its flight is answered inFlight
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
		local w = driven({ thrown(1, 1000, 50), { ok = false, reason = "highway.superFast" } })
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
		expect.equal(#w.holds, cap) -- each launched and let go
		expect.equal(w.toastHolds[#w.toastHolds], false)
		stop()
	end)

	-- Verification fixes (p13v4).

	-- Through a release and the client's landing (thrown's plan: released at 1000.42, down at 1003).
	local function toLanding(w: any)
		w.body = IN_AREA
		w.handler(Enum.UserInputState.Begin)
		w.tick()
		w.now = 10.5
		w.tick()
		w.server = 1003.1
		w.tick()
	end

	t.test("the landing pop counts every ring paid: Lv 1 PERFECT + boost, rings 1-3, lands in zone 2 -> 3/6", function()
		local reply = thrown(4, 1000, 3.0)
		reply.data.studs, reply.data.biome = 301, 2
		local w = driven({ reply })
		toLanding(w)
		local landing = landingOf(4)
		landing.studs, landing.biome, landing.rings = 301, 2, { 1, 2, 3 }
		w.landed(landing)
		local pop = Strings.highway.pop
		expect.deepEqual(w.pops[#w.pops], {
			Strings.format(pop.landed, { distance = "301" }),
			Strings.format(pop.rings, { hit = 3, total = 6 }),
		})
		stop()
	end)

	t.test("a launch turns the lobby's own keys off (Inspect, windows, slide) and back on when it ends", function()
		local w = driven({ thrown(1, 1000, 50), thrown(2, 1100, 50) })
		w.body = IN_AREA
		w.tick()
		expect.equal(w.contexts.Lobby, nil) -- on the deck: untouched
		w.handler(Enum.UserInputState.Begin)
		expect.equal(w.contexts.Lobby, false)
		w.alive = false -- the launch ends
		w.tick()
		expect.equal(w.contexts.Lobby, true)
		w.alive = true
		w.handler(Enum.UserInputState.Begin)
		expect.equal(w.contexts.Lobby, false)
		stop() -- destroyed mid-launch
		expect.equal(w.contexts.Lobby, true)
	end)

	t.test(
		"a press during the landing shot keeps the toast hold: the landing's toasts wait for the next end",
		function()
			local w = driven({ thrown(3, 1000, 3.0), thrown(4, 1004, 3.0) })
			toLanding(w)
			w.landed(landingOf(3))
			w.handler(Enum.UserInputState.Begin) -- the next throw takes over
			expect.equal(HighwayThrowController.debugState().id, 4)
			expect.deepEqual(w.liveToasts, {}) -- not shown under the next launch's hidden screen
			expect.equal(w.contexts.Lobby, false)
			w.alive = false -- the next launch ends: they play
			w.tick()
			expect.equal(w.liveToasts[1], HighwayThrowController.landingToasts(landingOf(3))[1].text)
			stop()
		end
	)

	t.test("a boost reply that comes after this client drew the landing keeps the landing", function()
		local w: any
		w = driven({
			thrown(5, 1000, 3.0),
			function(): any
				w.slow = coroutine.running()
				coroutine.yield()
				return thrown(5, 1000, 4.0, 0, true)
			end,
		})
		w.body = IN_AREA
		w.handler(Enum.UserInputState.Begin)
		w.tick()
		w.now = 10.5
		w.tick() -- released
		w.server = 1001.2
		w.tick()
		w.handler(Enum.UserInputState.Begin) -- the boost press; its reply is slow
		w.server = 1003.1 -- the first plan lands here
		w.tick()
		local landed = w.pops[#w.pops]
		coroutine.resume(w.slow)
		expect.equal(HighwayThrowController.debugState().landsAt, 1003)
		expect.equal(w.pops[#w.pops], landed)
		stop()
	end)
end
