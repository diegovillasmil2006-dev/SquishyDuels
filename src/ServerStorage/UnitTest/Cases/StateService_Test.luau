--!strict
-- StateService_Test: unit tests for ServerScriptService.Server.Services.StateService.
-- Server only (ServerStorage.UnitTest). Edit mode: init()/start() are never called; DataService is a fake data port
-- (or a real DataService core on a memory store, through portFrom), remotes are a recorder, players are plain tables
-- and deferred flushes run only when a case runs them.
-- Contract (DESIGN §2.7 state versioning, §2.8 RequestSnapshot / StateDelta, §3.1 / §3.13 / §11.3 banners, §17.10):
--   * RequestSnapshot: {status = "loading"} while loading, the full Snapshot when loaded;
--   * the Snapshot holds every field: profile projections (quests with starter, unseenReveals = boxLog entries with
--     seen = false, grip = {total, trainer, rested}: Phase 6, an old save's grip.afk is not sent), session fields
--     (policy "checking", monetization with no
--     offers, practice zeros until PracticeService sets it), dataStatus {status, persisted, savePending, banner};
--   * Loaded sends one full StateDelta; later changes go out as one partial StateDelta per batch with v + 1, only for
--     fields whose value changed; nothing partial before the first full state; the sweep catches unmarked changes;
--   * an OFFLINE session that loads later gets the full state again and Notify data.loaded (sent only here);
--   * banners: Studio memory mode, OFFLINE (retrying / gave up), READONLY (newer schema / lock lost / corrupt);
--   * portFrom reads DataService's API (getStatus, isPersisted, isSavePending, statusReason, mutate, signals).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

type World = {
	port: any,
	profiles: { [any]: any },
	statuses: { [any]: string },
	persisted: { [any]: boolean },
	pending: { [any]: boolean },
	reasons: { [any]: string },
	sent: { { name: string, player: any, v: number, fields: any, full: boolean? } },
	notices: { { player: any, code: string, kind: string? } },
	deferred: { () -> () },
}

local NOW = 1_790_000_000

return function(t: Context)
	local expect = t.expect
	local StateService = t.requireServer("Services/StateService")

	local function fakeProfile(): any
		return {
			schemaVersion = 2,
			createdAt = 1,
			lastSeenAt = 1,
			saveSeq = 0,
			coins = 120,
			owned = { kitty_bread = { at = 1, src = "starter" } },
			equipped = "kitty_bread",
			stats = {
				coinsEarned = 0,
				coinsSpent = 0,
				squeezes = 0,
				duelsPlayed = 0,
				duelsWon = 0,
				duelsLost = 0,
				duelsDrawn = 0,
				eliminations = 0,
				boxesOpened = 0,
			},
			squeezeLimit = { value = 300, at = 1 },
			quests = { day = 5, swapsUsed = 0, active = {} },
			starter = { progress = { starter_squeeze = 2 }, claimed = {} },
			daily = { lastClaimDay = -1, streakDay = 0, totalClaims = 0 },
			settings = { music = 40, sfx = 70, cameraShake = true, showTips = true },
			onboarding = { v = 1, done = {}, skipped = false },
			boxLog = {
				{
					req = "seen-one",
					box = "snack",
					squishy = "toast",
					dup = false,
					refund = 0,
					cost = 400,
					at = 2,
					seen = true,
				},
				{
					req = "new-one",
					box = "snack",
					squishy = "banana",
					dup = false,
					refund = 0,
					cost = 400,
					at = 3,
					seen = false,
				},
			},
			shopLog = {},
			receipts = {},
			duelLog = {},
			-- An old save (Phase 6): it still holds the slow-training bank, which is never sent.
			grip = { total = 50, trainer = 1, rested = { value = 1200, at = 1 }, afk = { value = 120, at = 1 } },
			capsules = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } },
		}
	end

	local function recorderDeps(w: World, port: any): any
		return {
			data = port,
			fire = function(name: string, player: any, v: number, fields: any, full: boolean?)
				table.insert(w.sent, { name = name, player = player, v = v, fields = fields, full = full })
			end,
			notify = function(player: any, code: string, _args: any, kind: string?)
				table.insert(w.notices, { player = player, code = code, kind = kind })
			end,
			isPlayer = function(_player: any): boolean
				return true
			end,
			defer = function(fn: () -> ())
				table.insert(w.deferred, fn)
			end,
		}
	end

	local function setup(): World
		local w: World = {
			port = nil,
			profiles = {},
			statuses = {},
			persisted = {},
			pending = {},
			reasons = {},
			sent = {},
			notices = {},
			deferred = {},
		}
		w.port = {
			getProfile = function(player: any): any?
				return w.profiles[player]
			end,
			status = function(player: any): string
				return w.statuses[player] or "loading"
			end,
			persisted = function(player: any): boolean
				local value = w.persisted[player]
				return if value == nil then true else value
			end,
			savePending = function(player: any): boolean
				return w.pending[player] == true
			end,
			statusReason = function(player: any): string?
				return w.reasons[player]
			end,
			mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
				return true, fn(w.profiles[player])
			end,
			requestSave = function(_player: any, _reason: string) end,
			onLoaded = function(_handler: any) end,
			onStatusChanged = function(_handler: any) end,
		}
		StateService.useDeps(recorderDeps(w, w.port))
		return w
	end

	local function runDeferred(w: World)
		local list = w.deferred
		w.deferred = {}
		for _, fn in list do
			fn()
		end
	end

	local function keysOf(t: { [string]: any }): { string }
		local list = {}
		for key in t do
			table.insert(list, key)
		end
		table.sort(list)
		return list
	end

	-- A player with a ready (memory-mode) profile that got its full state.
	local function loadedPlayer(w: World, persisted: boolean?): (any, any)
		local player = { UserId = 7 }
		local profile = fakeProfile()
		w.profiles[player] = profile
		w.statuses[player] = "ready"
		w.persisted[player] = if persisted == nil then false else persisted
		StateService.playerAdded(player)
		StateService.loaded(player)
		return player, profile
	end

	-- RequestSnapshot -------------------------------------------------------------------------------------------------

	t.test("RequestSnapshot answers loading while the profile loads", function()
		local w = setup()
		local player = { UserId = 1 }
		StateService.playerAdded(player)
		local reply = StateService.requestSnapshot(player)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { status = "loading" })
		expect.equal(StateService.snapshot(player), nil)
		expect.equal(#w.sent, 0)
	end)

	t.test("a loading session shows no profile even when one is already in memory", function()
		local w = setup()
		local player = { UserId = 2 }
		w.profiles[player] = fakeProfile()
		StateService.playerAdded(player)
		expect.deepEqual(StateService.requestSnapshot(player).data, { status = "loading" })
		StateService.loaded(player)
		expect.equal(#w.sent, 0)
	end)

	t.test("a Snapshot holds every field, and Studio memory mode carries its banner", function()
		local w = setup()
		local player = { UserId = 3 }
		w.profiles[player] = fakeProfile()
		w.statuses[player] = "ready"
		w.persisted[player] = false
		StateService.playerAdded(player)
		local reply = StateService.requestSnapshot(player)
		expect.equal(reply.ok, true)
		local snap = reply.data
		expect.deepEqual(keysOf(snap), {
			"capsules",
			"coins",
			"daily",
			"dataStatus",
			"equipped",
			"grip",
			"monetization",
			"onboarding",
			"owned",
			"policy",
			"practice",
			"quests",
			"settings",
			"squeezeLimit",
			"stats",
			"unseenReveals",
		}) -- every Types.Snapshot field
		expect.equal(snap.coins, 120)
		expect.equal(snap.equipped, "kitty_bread")
		expect.deepEqual(snap.owned, { kitty_bread = { at = 1, src = "starter" } })
		expect.deepEqual(snap.quests, {
			day = 5,
			swapsUsed = 0,
			active = {},
			starter = { progress = { starter_squeeze = 2 }, claimed = {} },
		})
		expect.equal(#snap.unseenReveals, 1)
		expect.equal(snap.unseenReveals[1].req, "new-one")
		expect.deepEqual(snap.grip, { total = 50, trainer = 1, rested = { value = 1200, at = 1 } }) -- no afk (Phase 6)
		-- Phase 5: the owner's capsules as stored (the capsule card, the squeeze value of the reward texts).
		expect.deepEqual(snap.capsules, { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } })
		expect.equal(snap.policy, "checking")
		expect.deepEqual(snap.monetization, { bundles = {}, passes = {} })
		expect.deepEqual(snap.practice, { throws = 0, hits = 0, accuracy = 0 })
		expect.deepEqual(
			snap.dataStatus,
			{ status = "ready", persisted = false, savePending = false, banner = "data.studioMemory" }
		)
	end)

	t.test("the Snapshot is a copy: later profile changes never change what was sent", function()
		local w = setup()
		local player = { UserId = 4 }
		local profile = fakeProfile()
		w.profiles[player] = profile
		w.statuses[player] = "ready"
		StateService.playerAdded(player)
		local snap = StateService.requestSnapshot(player).data
		profile.owned.toast = { at = 9, src = "shop" }
		profile.grip.rested.value = 5
		expect.equal(snap.owned.toast, nil)
		expect.equal(snap.grip.rested.value, 1200)
	end)

	-- Loaded and deltas -----------------------------------------------------------------------------------------------

	t.test("Loaded sends one full StateDelta with v = 1; the version is Result.v", function()
		local w = setup()
		local player = loadedPlayer(w)
		expect.equal(#w.sent, 1)
		local delta = w.sent[1]
		expect.equal(delta.name, "StateDelta")
		expect.equal(delta.player, player)
		expect.equal(delta.v, 1)
		expect.equal(delta.full, true)
		expect.equal(delta.fields.coins, 120)
		expect.equal(delta.fields.dataStatus.banner, "data.studioMemory")
		expect.equal(StateService.version(player), 1)
		-- A second Loaded (or StatusChanged) for the same profile table sends no second full state.
		StateService.loaded(player)
		StateService.statusChanged(player)
		runDeferred(w)
		expect.equal(#w.sent, 1)
		expect.equal(#w.notices, 0)
	end)

	t.test("changes go out as one partial StateDelta per batch, only for values that changed", function()
		local w = setup()
		local player, profile = loadedPlayer(w)
		profile.coins = 200
		StateService.markDirty(player, "coins")
		StateService.markDirty(player, "coins")
		StateService.markDirty(player, "settings") -- marked but unchanged: not sent
		expect.equal(#w.deferred, 1) -- one flush per batch
		runDeferred(w)
		expect.equal(#w.sent, 2)
		local delta = w.sent[2]
		expect.equal(delta.v, 2)
		expect.equal(delta.full, nil)
		expect.deepEqual(delta.fields, { coins = 200 })
		expect.equal(StateService.version(player), 2)
		-- Nothing changed: marking again sends nothing and keeps the version.
		StateService.markDirty(player, "coins")
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.equal(StateService.version(player), 2)
	end)

	t.test("markDirty(nil) checks every field; an unknown field is ignored", function()
		local w = setup()
		local player, profile = loadedPlayer(w)
		StateService.markDirty(player, "notAField")
		expect.equal(#w.deferred, 0) -- nothing scheduled
		profile.coins = 7
		profile.settings.music = 5
		profile.grip.trainer = 2
		StateService.markDirty(player)
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.deepEqual(keysOf(w.sent[2].fields), { "coins", "grip", "settings" })
	end)

	t.test("no partial StateDelta goes out before the client got its first full state", function()
		local w = setup()
		local player = { UserId = 8 }
		w.profiles[player] = fakeProfile()
		w.statuses[player] = "ready"
		StateService.playerAdded(player)
		StateService.markDirty(player, "coins")
		runDeferred(w)
		expect.equal(#w.sent, 0)
		StateService.loaded(player)
		expect.equal(#w.sent, 1)
		expect.equal(w.sent[1].full, true)
	end)

	t.test("a Snapshot reply counts as the full state; later changes go out as partial deltas", function()
		local w = setup()
		local player = { UserId = 9 }
		local profile = fakeProfile()
		w.profiles[player] = profile
		w.statuses[player] = "ready"
		StateService.playerAdded(player)
		StateService.requestSnapshot(player)
		expect.equal(StateService.version(player), 0) -- the reply carries the current version
		profile.equipped = "toast"
		profile.owned.toast = { at = 4, src = "shop" }
		StateService.markDirty(player, "equipped")
		StateService.markDirty(player, "owned")
		runDeferred(w)
		expect.equal(#w.sent, 1)
		expect.equal(w.sent[1].v, 1)
		expect.deepEqual(keysOf(w.sent[1].fields), { "equipped", "owned" })
	end)

	t.test("the sweep sends a change nobody marked (nested values included)", function()
		local w = setup()
		local _, profile = loadedPlayer(w)
		profile.grip.total = 99
		profile.squeezeLimit.value = 12
		StateService.sweep()
		expect.equal(#w.sent, 2)
		expect.deepEqual(keysOf(w.sent[2].fields), { "grip", "squeezeLimit" })
		expect.equal(w.sent[2].fields.grip.total, 99)
		StateService.sweep()
		expect.equal(#w.sent, 2) -- nothing new
	end)

	t.test("the sweep sends the first full state when no Loaded signal came", function()
		local w = setup()
		local player = { UserId = 10 }
		StateService.playerAdded(player)
		StateService.sweep()
		expect.equal(#w.sent, 0) -- still loading
		w.profiles[player] = fakeProfile()
		w.statuses[player] = "ready"
		StateService.sweep()
		expect.equal(#w.sent, 1)
		expect.equal(w.sent[1].full, true)
	end)

	t.test("savePending and status changes reach dataStatus", function()
		local w = setup()
		local player = loadedPlayer(w, true)
		w.pending[player] = true
		StateService.statusChanged(player)
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.deepEqual(w.sent[2].fields, { dataStatus = { status = "ready", persisted = true, savePending = true } })
	end)

	t.test("a lost lock makes the session READONLY: the banner says rejoin, the profile stays", function()
		local w = setup()
		local player = loadedPlayer(w, true)
		w.statuses[player] = "readonly"
		w.reasons[player] = "lost"
		StateService.statusChanged(player)
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.deepEqual(
			w.sent[2].fields,
			{ dataStatus = { status = "readonly", persisted = true, savePending = false, banner = "data.rejoin" } }
		)
		expect.equal(#w.notices, 0)
	end)

	t.test("an OFFLINE session shows defaults, and gets the full state and data.loaded when it loads later", function()
		local w = setup()
		local player = { UserId = 11 }
		w.statuses[player] = "offline"
		w.reasons[player] = "retrying"
		local defaults = fakeProfile()
		defaults.coins = 0
		w.profiles[player] = defaults -- DataService keeps defaults in memory for an OFFLINE session (§3.13)
		StateService.playerAdded(player)
		StateService.statusChanged(player)
		StateService.loaded(player)
		expect.equal(#w.sent, 1)
		expect.equal(w.sent[1].fields.coins, 0)
		expect.equal(w.sent[1].fields.dataStatus.banner, "data.offlineRetrying")
		-- The background retry loads the real profile (StatusChanged first, then Loaded, as DataService fires them).
		w.profiles[player] = fakeProfile()
		w.statuses[player] = "ready"
		w.reasons[player] = nil
		StateService.statusChanged(player)
		StateService.loaded(player)
		expect.equal(#w.sent, 2)
		expect.equal(w.sent[2].full, true)
		expect.equal(w.sent[2].v, 2)
		expect.equal(w.sent[2].fields.coins, 120)
		expect.equal(w.sent[2].fields.dataStatus.banner, nil)
		expect.equal(#w.notices, 1)
		expect.equal(w.notices[1].code, "data.loaded")
		expect.equal(w.notices[1].kind, "success")
	end)

	t.test("an OFFLINE session whose retries ran out gets the load-failed banner and no notice", function()
		local w = setup()
		local player = { UserId = 12 }
		w.statuses[player] = "offline"
		w.reasons[player] = "retrying"
		w.profiles[player] = fakeProfile()
		StateService.playerAdded(player)
		StateService.statusChanged(player)
		w.reasons[player] = "exhausted"
		StateService.statusChanged(player)
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.equal(w.sent[2].fields.dataStatus.banner, "data.loadFailed")
		expect.equal(#w.notices, 0)
	end)

	t.test("session fields: practice starts at zero and is sent when set; only session fields may be set", function()
		local w = setup()
		local player = loadedPlayer(w)
		expect.deepEqual(w.sent[1].fields.practice, { throws = 0, hits = 0, accuracy = 0 })
		StateService.setSessionField(player, "practice", { throws = 0, hits = 0, accuracy = 0 })
		runDeferred(w)
		expect.equal(#w.sent, 1) -- unchanged: nothing sent
		local stats = { throws = 4, hits = 1, accuracy = 25 }
		StateService.setSessionField(player, "practice", stats)
		stats.throws = 99 -- copied
		StateService.setSessionField(player, "policy", "eligible")
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.deepEqual(w.sent[2].fields, { practice = { throws = 4, hits = 1, accuracy = 25 }, policy = "eligible" })
		expect.throws(function()
			StateService.setSessionField(player, "coins", 5)
		end, "session field")
	end)

	t.test("playerRemoving forgets the player; late changes and status signals never bring it back", function()
		local w = setup()
		local player, profile = loadedPlayer(w)
		StateService.playerRemoving(player)
		expect.equal(StateService.version(player), 0)
		runDeferred(w)
		expect.equal(#w.sent, 1)
		-- The player object is still in the game for a moment (isPlayer stays true in this fake).
		profile.coins = 999
		StateService.markDirty(player, "coins")
		w.pending[player] = true -- a failed final save
		StateService.statusChanged(player)
		StateService.loaded(player)
		StateService.sweep()
		runDeferred(w)
		expect.equal(#w.sent, 1)
		expect.equal(StateService.version(player), 0)
		-- Rejoining (a new playerAdded) starts a fresh session.
		StateService.playerAdded(player)
		StateService.loaded(player)
		expect.equal(#w.sent, 2)
		expect.equal(w.sent[2].full, true)
	end)

	-- Pure helpers ----------------------------------------------------------------------------------------------------

	t.test("bannerFor: the honest status banner for each state", function()
		expect.equal(StateService.bannerFor("ready", true, nil), nil)
		expect.equal(StateService.bannerFor("ready", false, nil), "data.studioMemory")
		expect.equal(StateService.bannerFor("loading", false, nil), nil)
		expect.equal(StateService.bannerFor("offline", true, nil), "data.offlineRetrying")
		expect.equal(StateService.bannerFor("offline", true, "retrying"), "data.offlineRetrying")
		expect.equal(StateService.bannerFor("offline", true, "exhausted"), "data.loadFailed")
		expect.equal(StateService.bannerFor("readonly", true, "newer"), "data.newerVersion")
		expect.equal(StateService.bannerFor("readonly", true, "lost"), "data.rejoin")
		expect.equal(StateService.bannerFor("readonly", true, "corrupt"), "data.loadFailed")
		expect.equal(StateService.bannerFor("readonly", true, nil), "data.loadFailed")
	end)

	t.test("normalizeStatus keeps DataService's four statuses and fails closed", function()
		for _, status in { "loading", "ready", "offline", "readonly" } do
			expect.equal(StateService.normalizeStatus(status), status)
		end
		expect.equal(StateService.normalizeStatus("READY"), "loading")
		expect.equal(StateService.normalizeStatus("weird"), "loading")
		expect.equal(StateService.normalizeStatus(nil), "loading")
	end)

	t.test("the field list is DESIGN's StateDelta list plus grip and capsules", function()
		expect.deepEqual(StateService.fields(), {
			"coins",
			"owned",
			"equipped",
			"stats",
			"squeezeLimit",
			"quests",
			"daily",
			"settings",
			"onboarding",
			"policy",
			"dataStatus",
			"monetization",
			"unseenReveals",
			"practice",
			"grip",
			"capsules",
		})
	end)

	-- Phase 5: a capsule change reaches the owner's client like any other field (CapsuleService marks it; the sweep
	-- catches it anyway).
	t.test("a changed capsule goes out in the next partial StateDelta", function()
		local w = setup()
		local player, profile = loadedPlayer(w)
		profile.capsules.list[1].level = 2
		StateService.markDirty(player, "capsules")
		runDeferred(w)
		expect.equal(#w.sent, 2)
		expect.deepEqual(
			w.sent[2].fields,
			{ capsules = { slots = 1, list = { { level = 2, squishyId = "kitty_bread" } } } }
		)
	end)

	-- The DataService reading -----------------------------------------------------------------------------------------

	t.test("portFrom reads DataService's API (statuses fail closed; mutate passes through)", function()
		local Signal = t.requireShared("Util/Signal")
		local player = { UserId = 13 }
		local profile = fakeProfile()
		local saves: { string } = {}
		local source = {
			getProfile = function(_p: any): any
				return profile
			end,
			getStatus = function(_p: any): string?
				return nil -- no session yet
			end,
			isPersisted = function(_p: any): boolean
				return false
			end,
			isSavePending = function(_p: any): boolean
				return true
			end,
			statusReason = function(_p: any): string?
				return "retrying"
			end,
			mutate = function(_p: any, fn: (profile: any) -> any): (boolean, any)
				return true, fn(profile)
			end,
			requestSave = function(_p: any, reason: string)
				table.insert(saves, reason)
			end,
			Loaded = Signal.new(),
			StatusChanged = Signal.new(),
		}
		local port = StateService.portFrom(source)
		expect.equal(port.status(player), "loading")
		expect.equal(port.persisted(player), false)
		expect.equal(port.savePending(player), true)
		expect.equal(port.statusReason(player), "retrying")
		expect.equal(port.getProfile(player), profile)
		local ok, result = port.mutate(player, function(p: any): any
			p.coins += 1
			return "done"
		end)
		expect.equal(ok, true)
		expect.equal(result, "done")
		expect.equal(profile.coins, 121)
		port.requestSave(player, "soon")
		expect.deepEqual(saves, { "soon" })
		local seen: { { kind: string, player: any } } = {}
		port.onLoaded(function(p: any)
			table.insert(seen, { kind = "loaded", player = p })
		end)
		port.onStatusChanged(function(p: any)
			table.insert(seen, { kind = "status", player = p })
		end)
		source.StatusChanged:fire(player, { status = "ready" })
		source.Loaded:fire(player, profile, "ready")
		expect.deepEqual(seen, { { kind = "status", player = player }, { kind = "loaded", player = player } })
	end)

	t.test(
		"wired to a real DataService core (memory store): the load sends the full state with the Studio banner",
		function()
			local DataService = t.requireServer("Services/DataService")
			local InMemoryAdapter = t.requireServer("Data/InMemoryAdapter")
			local store = InMemoryAdapter.new("Memory")
			local core = DataService.newCore({
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
				jobId = "state-test",
				newNonce = function(): string
					return "0a1b2c3d"
				end,
				notify = function() end,
				spawn = function(fn: () -> ())
					fn()
				end,
				defer = function(fn: () -> ())
					fn()
				end,
			})
			local w = setup()
			local port = StateService.portFrom(core)
			StateService.useDeps(recorderDeps(w, port))
			port.onStatusChanged(StateService.statusChanged)
			port.onLoaded(StateService.loaded)
			local player = { UserId = 14 }
			StateService.playerAdded(player)
			expect.equal(core.loadAsync(player), "ready")
			expect.equal(#w.sent, 1)
			local first = w.sent[1]
			expect.equal(first.full, true)
			expect.equal(first.fields.equipped, "kitty_bread")
			expect.deepEqual(
				first.fields.dataStatus,
				{ status = "ready", persisted = false, savePending = false, banner = "data.studioMemory" }
			)
			expect.equal(type(first.fields.grip), "table")
			-- A change through the port reaches the client as a partial delta.
			local ok = port.mutate(player, function(profile: any): any
				profile.coins = 42
				return nil
			end)
			expect.truthy(ok)
			StateService.markDirty(player, "coins")
			runDeferred(w)
			expect.equal(#w.sent, 2)
			expect.deepEqual(w.sent[2].fields, { coins = 42 })
			expect.equal(#w.notices, 0)
			core.releaseAsync(player)
		end
	)
end
