--!strict
-- SwitchService_Test: unit tests for ServerScriptService.Server.Services.SwitchService and Config.Switches (big job
-- item 3, 2026-11-10: the emergency switches). Edit mode: a fake config snapshot is injected (useDeps); init() and
-- start() are never called; players are plain tables.
-- Contract:
--   * every remote a switch lists is a real client -> server remote, listed once;
--   * with no configs (never loaded, or the load failed) every switch is ON and every remote is allowed;
--   * only the boolean false turns a switch off; a missing key, true, or a wrong type (a number, a string) is ON;
--   * a switch that is off refuses its own remotes and no other; a remote outside every switch always passes;
--   * a newer snapshot value is picked up when Roblox says an update is available (refresh at once);
--   * the "closed" notice comes at most once every notifyEverySeconds per player.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local SwitchService = t.requireServer("Services/SwitchService")
	local Switches = t.requireShared("Config/Switches")
	local Remotes = t.requireShared("Remotes")
	local FakeClock = t.requireFake("FakeClock")

	-- A fake ConfigSnapshot: `live` holds what Roblox has now, `seen` what this server refreshed to.
	local function fakeConfigs(initial: { [string]: any })
		local live = table.clone(initial)
		local seen = table.clone(initial)
		local listeners: { () -> () } = {}
		local snapshot = {
			UpdateAvailable = {
				Connect = function(_: any, fn: () -> ())
					table.insert(listeners, fn)
				end,
			},
		}
		function snapshot.GetValue(_: any, key: string): any
			return seen[key]
		end
		function snapshot.Refresh(_: any)
			seen = table.clone(live)
		end
		local function publish(key: string, value: any)
			live[key] = value
			for _, fn in listeners do
				fn()
			end
		end
		return snapshot, publish
	end

	local function with(initial: { [string]: any }?, fails: boolean?): ((key: string, value: any) -> (), any)
		local snapshot, publish = fakeConfigs(initial or {})
		local clock = FakeClock.new(100)
		SwitchService.useDeps({
			getSnapshot = function()
				if fails then
					error("configs are down")
				end
				return snapshot
			end,
			clock = clock.now,
		})
		return publish, clock
	end

	t.test("every remote a switch lists is a real client -> server remote, listed once", function()
		local seen: { [string]: string } = {}
		local count = 0
		for feature, remotes in Switches.features do
			expect.truthy(string.match(feature, "^[a-z]+$") ~= nil) -- a plain config key
			expect.truthy(#remotes > 0)
			for _, name in remotes do
				local spec = Remotes.SPEC[name]
				if spec == nil or spec.dir ~= "c2s" then
					error(`{feature}: {name} is not a client -> server remote`)
				end
				if seen[name] then
					error(`{name} is in {seen[name]} and in {feature}`)
				end
				seen[name] = feature
				count += 1
				expect.equal(SwitchService.featureOf(name), feature)
			end
		end
		expect.truthy(count >= 20)
		expect.equal(SwitchService.featureOf("RequestSnapshot"), nil) -- joining can never be switched off
	end)

	t.test("no configs: every switch is ON and every remote passes (before a load and after a failed one)", function()
		with(nil, true)
		for feature in Switches.features do
			expect.equal(SwitchService.isOn(feature), true)
		end
		expect.equal(SwitchService.loadNow(), false)
		expect.equal(SwitchService.isOn("boxes"), true)
		expect.equal(SwitchService.allows("BoxOpen"), true)
		SwitchService.useDeps(nil)
	end)

	t.test("only the boolean false turns a switch off", function()
		with({ switch_boxes = false, switch_shop = true, switch_duels = 0, switch_pen = "false" })
		expect.equal(SwitchService.loadNow(), true)
		expect.equal(SwitchService.isOn("boxes"), false)
		expect.equal(SwitchService.isOn("shop"), true)
		expect.equal(SwitchService.isOn("duels"), true) -- a number: a mistyped dashboard edit closes nothing
		expect.equal(SwitchService.isOn("pen"), true) -- a string: the same
		expect.equal(SwitchService.isOn("highway"), true) -- no key
		expect.equal(SwitchService.isOn("notASwitch"), true)
		SwitchService.useDeps(nil)
	end)

	t.test("an off switch refuses its own remotes and no other", function()
		with({ switch_boxes = false })
		SwitchService.loadNow()
		expect.equal(SwitchService.allows("BoxOpen"), false)
		expect.equal(SwitchService.allows("ShopBuy"), true)
		expect.equal(SwitchService.allows("SqueezeRequest"), true)
		expect.equal(SwitchService.allows("RequestSnapshot"), true) -- outside every switch
		expect.equal(SwitchService.allows("NotARemote"), true)
		SwitchService.useDeps(nil)
	end)

	t.test("a published change is picked up at once, both ways", function()
		local publish = with({})
		SwitchService.loadNow()
		expect.equal(SwitchService.allows("HighwayThrow"), true)
		publish("switch_highway", false)
		expect.equal(SwitchService.allows("HighwayThrow"), false)
		expect.equal(SwitchService.allows("GoHighway"), false)
		publish("switch_highway", true)
		expect.equal(SwitchService.allows("HighwayThrow"), true)
		SwitchService.useDeps(nil)
	end)

	t.test("the closed notice: at most once every notifyEverySeconds per player", function()
		local _, clock = with({})
		local a, b = {} :: any, {} :: any
		expect.equal(SwitchService.refused(a), true)
		expect.equal(SwitchService.refused(a), false)
		expect.equal(SwitchService.refused(b), true) -- another player has their own clock
		clock.advance(Switches.notifyEverySeconds + 0.1)
		expect.equal(SwitchService.refused(a), true)
		SwitchService.useDeps(nil)
	end)
end
