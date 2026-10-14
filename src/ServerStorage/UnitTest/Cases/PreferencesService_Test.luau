--!strict
-- PreferencesService_Test: unit tests for ServerScriptService.Server.Services.PreferencesService.
-- Server only (ServerStorage.UnitTest). Edit mode: init() is never called (no remotes); DataService is a fake data
-- port and StateService a recorder (useDeps); players are plain tables.
-- Contract (DESIGN §2.8 SetSettings / OnboardingStep, §3.2, §11.6, §11.8):
--   * SetSettings: at most the 4 keys music, sfx, cameraShake, showTips; volumes whole numbers clamped to 0-100;
--     anything else drops the whole payload; only the keys sent change; a change marks "settings" and saves "soon"
--     (ready profiles only, through DataService.mutate; OFFLINE keeps it in memory; loading has nothing to change);
--   * onboarding: markStep is idempotent and saves once; the client may record only welcome and inspect; server steps
--     come from the wiring (the first capsule spend, the first squishy from a box or the shop, a squeeze, a queue join);
--     onboarding never pays Coins; the skip id (Config.Onboarding.skipStepId, Part 7) sets onboarding.skipped once
--     ("soon" save, idempotent) and marks no step;
--   * end to end through a real DataService core (memory store): settings and steps survive a release and a reload.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

type World = {
	profiles: { [any]: any },
	statuses: { [any]: string },
	frozen: { [any]: boolean },
	dirty: { string },
	saves: { string },
	mutations: number,
}

local NOW = 1_790_000_000

return function(t: Context)
	local expect = t.expect
	local PreferencesService = t.requireServer("Services/PreferencesService")
	local Config = t.requireShared("Config")

	local function setup(): World
		local w: World = { profiles = {}, statuses = {}, frozen = {}, dirty = {}, saves = {}, mutations = 0 }
		PreferencesService.useDeps({
			data = {
				getProfile = function(player: any): any?
					return w.profiles[player]
				end,
				status = function(player: any): string
					return w.statuses[player] or "loading"
				end,
				persisted = function(_player: any): boolean
					return true
				end,
				savePending = function(_player: any): boolean
					return false
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				-- Like DataService.mutate: READY sessions only, and none once the final leave snapshot is taken.
				mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
					if w.statuses[player] ~= "ready" or w.frozen[player] then
						return false, "data.notReady"
					end
					w.mutations += 1
					return true, fn(w.profiles[player])
				end,
				requestSave = function(_player: any, reason: string)
					table.insert(w.saves, reason)
				end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			markDirty = function(_player: any, field: string)
				table.insert(w.dirty, field)
			end,
		})
		return w
	end

	local function readyPlayer(w: World, status: string?): (any, any)
		local player = { UserId = 5 }
		local profile = {
			coins = 0,
			settings = { music = 40, sfx = 70, cameraShake = true, showTips = true },
			onboarding = { v = 1, done = {}, skipped = false },
		}
		w.profiles[player] = profile
		w.statuses[player] = status or "ready"
		return player, profile
	end

	-- Settings --------------------------------------------------------------------------------------------------------

	t.test("SetSettings changes only the keys sent, clamps volumes, marks settings and saves soon", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		expect.truthy(PreferencesService.setSettings(player, { music = 150, cameraShake = false }))
		expect.deepEqual(profile.settings, { music = 100, sfx = 70, cameraShake = false, showTips = true })
		expect.equal(w.mutations, 1)
		expect.deepEqual(w.dirty, { "settings" })
		expect.deepEqual(w.saves, { "soon" })
		expect.truthy(PreferencesService.setSettings(player, { sfx = -20 }))
		expect.equal(profile.settings.sfx, 0)
		expect.deepEqual(PreferencesService.getSettings(player), profile.settings)
	end)

	t.test("SetSettings drops a payload with an unknown key, a wrong type or too many keys", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		local bad: { any } = {
			"loud",
			{ music = "50" },
			{ music = 50.5 },
			{ cameraShake = 1 },
			{ reducedMotion = true },
			{ music = 10, sfx = 10, cameraShake = true, showTips = true, extra = 1 },
			{ [1] = 5 },
		}
		for _, payload in bad do
			expect.falsy(PreferencesService.setSettings(player, payload))
		end
		expect.deepEqual(profile.settings, { music = 40, sfx = 70, cameraShake = true, showTips = true })
		expect.equal(#w.dirty, 0)
		expect.equal(#w.saves, 0)
	end)

	t.test("SetSettings with unchanged values saves nothing", function()
		local w = setup()
		local player = readyPlayer(w)
		expect.truthy(PreferencesService.setSettings(player, { music = 40, showTips = true }))
		expect.truthy(PreferencesService.setSettings(player, {}))
		expect.equal(#w.dirty, 0)
		expect.equal(#w.saves, 0)
	end)

	t.test("OFFLINE keeps settings in memory without saving; loading has nothing to change", function()
		local w = setup()
		local player, profile = readyPlayer(w, "offline")
		expect.truthy(PreferencesService.setSettings(player, { music = 10 }))
		expect.equal(profile.settings.music, 10)
		expect.deepEqual(w.dirty, { "settings" })
		expect.equal(#w.saves, 0)
		local loading = { UserId = 6 }
		expect.truthy(PreferencesService.setSettings(loading, { music = 10 }))
		expect.deepEqual(PreferencesService.getSettings(loading), {
			music = Config.Data.DefaultSettings.music,
			sfx = Config.Data.DefaultSettings.sfx,
			cameraShake = Config.Data.DefaultSettings.cameraShake,
			showTips = Config.Data.DefaultSettings.showTips,
		})
	end)

	-- Onboarding ------------------------------------------------------------------------------------------------------

	t.test("markStep records a step once, marks onboarding and saves soon; unknown steps are refused", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		expect.truthy(PreferencesService.markStep(player, "squeeze"))
		expect.falsy(PreferencesService.markStep(player, "squeeze"))
		expect.truthy(profile.onboarding.done.squeeze)
		expect.truthy(PreferencesService.isStepDone(player, "squeeze"))
		expect.deepEqual(w.dirty, { "onboarding" })
		expect.deepEqual(w.saves, { "soon" })
		expect.falsy(PreferencesService.markStep(player, "teleport"))
		expect.equal(profile.coins, 0) -- onboarding never pays Coins
	end)

	t.test("the client may record only its own steps (welcome, inspect)", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		expect.truthy(PreferencesService.clientStep(player, "welcome"))
		expect.truthy(PreferencesService.clientStep(player, "inspect"))
		for _, serverStep in { "squeeze", "capsule", "firstBox", "duel" } do
			expect.falsy(PreferencesService.clientStep(player, serverStep))
		end
		expect.falsy(PreferencesService.clientStep(player, 3))
		expect.deepEqual(profile.onboarding.done, { welcome = true, inspect = true })
	end)

	t.test("Skip tutorial (skipStepId): sets skipped once, saves soon once, marks no step, never pays", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		local skipId = Config.Onboarding.skipStepId
		expect.truthy(PreferencesService.clientStep(player, "welcome"))
		expect.truthy(PreferencesService.clientStep(player, skipId))
		expect.falsy(PreferencesService.clientStep(player, skipId)) -- idempotent
		expect.falsy(PreferencesService.skip(player))
		expect.equal(profile.onboarding.skipped, true)
		expect.deepEqual(profile.onboarding.done, { welcome = true }) -- the done steps are kept, no step for skip
		expect.deepEqual(w.dirty, { "onboarding", "onboarding" })
		expect.deepEqual(w.saves, { "soon", "soon" })
		expect.equal(profile.coins, 0)
		expect.falsy(PreferencesService.markStep(player, skipId)) -- skip is not a step
	end)

	t.test("Skip tutorial: OFFLINE keeps it in memory unsaved; loading and frozen sessions change nothing", function()
		local w = setup()
		local player, profile = readyPlayer(w, "offline")
		expect.truthy(PreferencesService.clientStep(player, Config.Onboarding.skipStepId))
		expect.equal(profile.onboarding.skipped, true)
		expect.equal(#w.saves, 0)
		local frozen, frozenProfile = readyPlayer(w)
		w.frozen[frozen] = true
		expect.falsy(PreferencesService.skip(frozen))
		expect.equal(frozenProfile.onboarding.skipped, false)
		expect.falsy(PreferencesService.skip({ UserId = 77 })) -- loading: no profile
		expect.equal(#w.saves, 0)
	end)

	t.test("server-observed steps: the first capsule buy, the first box or shop squishy, a squeeze, a join", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		PreferencesService.onCoinsChanged(player, 10, 10, "capsule")
		expect.equal(profile.onboarding.done.capsule, nil) -- a capsule's pay is no buy
		PreferencesService.onCoinsChanged(player, 0, -10_000, "shop")
		expect.equal(profile.onboarding.done.capsule, nil) -- another spend does not count
		PreferencesService.onCoinsChanged(player, 0, -1_000, "capsule")
		PreferencesService.onSquishyGranted(player, "toast", "grant")
		expect.equal(profile.onboarding.done.firstBox, nil) -- a debug grant does not count
		PreferencesService.onSquishyGranted(player, "toast", "box")
		PreferencesService.onSqueezed(player)
		PreferencesService.onQueueJoined(player)
		expect.deepEqual(profile.onboarding.done, { capsule = true, firstBox = true, squeeze = true, duel = true })
		expect.equal((PreferencesService :: any).onEquipped, nil) -- Batch 1: there is no equip step any more
		expect.equal(profile.coins, 0) -- onboarding never pays Coins
	end)

	t.test("a session that takes no more changes stores nothing and saves nothing", function()
		local w = setup()
		local player, profile = readyPlayer(w)
		w.frozen[player] = true
		expect.truthy(PreferencesService.setSettings(player, { music = 5 }))
		expect.falsy(PreferencesService.markStep(player, "welcome"))
		expect.equal(profile.settings.music, 40)
		expect.equal(profile.onboarding.done.welcome, nil)
		expect.equal(#w.dirty, 0)
		expect.equal(#w.saves, 0)
	end)

	t.test("READONLY keeps a recorded step in memory without saving", function()
		local w = setup()
		local player, profile = readyPlayer(w, "readonly")
		expect.truthy(PreferencesService.markStep(player, "inspect"))
		expect.truthy(profile.onboarding.done.inspect)
		expect.deepEqual(w.dirty, { "onboarding" })
		expect.equal(#w.saves, 0)
	end)

	t.test("no profile: nothing is recorded", function()
		setup()
		local loading = { UserId = 9 }
		expect.falsy(PreferencesService.markStep(loading, "welcome"))
		expect.falsy(PreferencesService.isStepDone(loading, "welcome"))
	end)

	-- End to end through a real DataService core ----------------------------------------------------------------------

	t.test("memory mode end to end: settings and onboarding steps survive a release and a reload", function()
		local DataService = t.requireServer("Services/DataService")
		local StateService = t.requireServer("Services/StateService")
		local InMemoryAdapter = t.requireServer("Data/InMemoryAdapter")
		local store = InMemoryAdapter.new("Memory")
		local function newCore(nonce: string): any
			return DataService.newCore({
				now = function(): number
					return NOW
				end,
				wait = function(_seconds: number) end,
				random = function(): number
					return 0
				end,
				storeFor = function(_userId: number): any
					return store
				end,
				jobId = "preferences-test",
				newNonce = function(): string
					return nonce
				end,
				notify = function() end,
				spawn = function(fn: () -> ())
					fn()
				end,
				defer = function(fn: () -> ())
					fn()
				end,
			})
		end
		local function useCore(core: any)
			PreferencesService.useDeps({
				data = StateService.portFrom(core),
				markDirty = function(_player: any, _field: string) end,
			})
		end
		local player = { UserId = 6160 }
		local first = newCore("1111aaaa")
		expect.equal(first.loadAsync(player), "ready")
		useCore(first)
		expect.truthy(PreferencesService.setSettings(player, { music = 15, cameraShake = false }))
		expect.truthy(PreferencesService.markStep(player, "welcome"))
		expect.truthy(first.releaseAsync(player))

		local second = newCore("2222bbbb")
		expect.equal(second.loadAsync(player), "ready")
		useCore(second)
		local defaults = Config.Data.DefaultSettings
		expect.deepEqual(
			PreferencesService.getSettings(player),
			{ music = 15, sfx = defaults.sfx, cameraShake = false, showTips = defaults.showTips }
		)
		expect.truthy(PreferencesService.isStepDone(player, "welcome"))
		expect.falsy(PreferencesService.isStepDone(player, "inspect"))
		second.releaseAsync(player)
		PreferencesService.useDeps(nil)
	end)
end
