--!strict
-- DataService_Test: the FakeDataStore suite of DESIGN §13.2 Part 5 for server Services/DataService (§3), run on
-- DataService.newCore with a fake clock, fake waits (recorded, never slept), a fixed random (0.5), fake players and a
-- quiet logger. Server only (ServerStorage.UnitTest); Edit mode: no real DataStore, no Players, no remotes.
-- Covered: fresh key; returning profile; v1 -> v2 on the next save (migratedFrom); foreign lock -> wait -> released /
-- OFFLINE -> stale takeover by the background retry; stale lock taken over at once; ghost writes (load, save and
-- release); a transform run twice by UpdateAsync (only the last run counts); throttle 304 (doubled delay);
-- non-retryable 105 (load and save); newer schema -> READONLY; FAILING LOADS -> ZERO WRITES; leaving during an OFFLINE
-- background retry; lost lock (owner and saveSeq); snapshot at job start and "now" coalescing; "soon" timer; autosave
-- and the request budget; release on leave; close (releaseAll) folding redundant saves; join while closing; a
-- cancelled load; mutate rules; pending receipts; waitForProfileAsync; memory mode; store selection and the _STUDIO
-- guard; the Studio reload hook; Studio forced save failures (memory failNext -> savePending -> a "soon" retry clears
-- it); pens3 phase 4: every save stamps pen.awayRate (the pen's rate) next to lastSeenAt. Tables are compared by
-- value. UpdateAsync only: the fake fails loudly on any other API.
-- With random() = 0.5: lock poll waits 6 s (6 + (0.5 * 2 - 1) * 2); retry delays 1.25, 2.5, 5, 10 s (throttle x2);
-- the first autosave is due 60 s after the load.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
	requireShared: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local T0 = 1_800_000_000
local KEY = "User_101"
local ME = "job-test/00000001" -- the first session's owner in every harness
local OTHER = "other-job/ffff0000"

return function(t: Context)
	local expect = t.expect
	local DataService = t.requireServer("Services/DataService")
	local DataStoreAdapter = t.requireServer("Data/DataStoreAdapter")
	local InMemoryAdapter = t.requireServer("Data/InMemoryAdapter")
	local ProfileSchema = t.requireServer("Logic/ProfileSchema")
	local TableUtil = t.requireShared("Util/TableUtil")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")
	local FakeDataStore = t.requireFake("FakeDataStore")

	local function player(userId: number?): any
		local id = userId or 101
		return { UserId = id, Name = `Tester{id}` }
	end

	local function join(...: any): string
		local parts = {}
		for i = 1, select("#", ...) do
			table.insert(parts, tostring((select(i, ...))))
		end
		return table.concat(parts, " ")
	end

	local function hasLine(lines: { string }, text: string): boolean
		for _, line in lines do
			if string.find(line, text, 1, true) then
				return true
			end
		end
		return false
	end

	-- A stored profile (current schema) with some fields changed.
	local function storedProfile(changes: { [string]: any }?): any
		local profile = ProfileSchema.defaults(T0 - 5000)
		local list: { [string]: any } = changes or {}
		for key, value in list do
			profile[key] = value
		end
		return profile
	end

	-- A stored ProfileV1 (schemaVersion 1, no grip).
	local function storedV1(squeezes: number, coins: number): any
		local profile = ProfileSchema.defaults(T0 - 9000)
		profile.schemaVersion = 1
		profile.grip = nil
		profile.lastSeenAt = T0 - 500
		profile.saveSeq = 12
		profile.coins = coins
		profile.stats.squeezes = squeezes
		return profile
	end

	local function newHarness(opts: { [string]: any }?): any
		local o: { [string]: any } = opts or {}
		local clock = FakeClock.new(T0)
		local store = o.store or FakeDataStore.new("PlayerData_test")
		local h: any = {
			clock = clock,
			store = store,
			waits = {},
			notices = {},
			loaded = {},
			statuses = {},
			logs = {},
			closing = false,
		}
		local nonces = 0
		local logger = {
			debug = function() end,
			info = function(_self: any, ...: any)
				table.insert(h.logs, "info " .. join(...))
			end,
			warn = function(_self: any, ...: any)
				table.insert(h.logs, "warn " .. join(...))
			end,
			error = function(_self: any, ...: any)
				table.insert(h.logs, "error " .. join(...))
			end,
		}
		h.core = DataService.newCore({
			now = clock.now,
			wait = function(seconds: number)
				table.insert(h.waits, seconds)
				clock.advance(seconds)
			end,
			random = function(): number
				return 0.5
			end,
			storeFor = o.storeFor or function(_userId: number): any
				return store
			end,
			jobId = "job-test",
			newNonce = function(): string
				nonces += 1
				return string.format("%08x", nonces)
			end,
			notify = function(_player: any, code: string)
				table.insert(h.notices, code)
			end,
			isClosing = function(): boolean
				return h.closing
			end,
			config = o.config,
			log = logger :: any,
			defer = function(fn: () -> ())
				fn()
			end,
		})
		h.core.Loaded:connect(function(_player: any, _profile: any, status: string)
			table.insert(h.loaded, status)
		end)
		h.core.StatusChanged:connect(function(_player: any, dataStatus: any)
			table.insert(h.statuses, TableUtil.deepCopy(dataStatus))
		end)
		return h
	end

	local function outcomes(store: any): { string }
		local list = {}
		for _, call in store.history do
			table.insert(list, call.outcome)
		end
		return list
	end

	-- Load ----------------------------------------------------------------------------------------------------------

	t.test("a fresh key gets defaults atomically, with our lock and {userId}, through UpdateAsync only", function()
		local h = newHarness()
		local p = player()
		expect.equal(h.core.getStatus(p), nil)
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(h.core.getProfile(p), ProfileSchema.defaults(T0))
		expect.deepEqual(h.core.dataStatus(p), { status = "ready", persisted = true, savePending = false })
		expect.deepEqual(h.loaded, { "ready" })
		expect.equal(h.store.writes, 1)
		local value, metadata, userIds = h.store.getRaw(KEY)
		expect.deepEqual(value, ProfileSchema.defaults(T0))
		expect.deepEqual(metadata, { lock = { o = ME, t = T0 } })
		expect.deepEqual(userIds, { 101 })
		expect.equal(h.store.forbiddenCalls, 0)
		expect.deepEqual(h.notices, {})
		expect.equal(h.core.migratedFrom(p), nil)
		expect.equal(h.core.statusReason(p), nil)
	end)

	t.test("a stored profile loads as stored; a save writes saveSeq + 1 and keeps the other metadata", function()
		local h = newHarness()
		local stored = storedProfile({ coins = 500, saveSeq = 7 })
		h.store.setRaw(KEY, stored, { note = "keep" }, { 101 })
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.equal(h.core.getProfile(p).coins, 500)
		expect.equal(h.core.inspect(p).saveSeq, 7)
		local value, metadata = h.store.getRaw(KEY)
		expect.deepEqual(value, stored) -- the load only takes the lock
		expect.deepEqual(metadata, { note = "keep", lock = { o = ME, t = T0 } })

		local ok, result = h.core.mutate(p, function(profile: any): any
			profile.coins += 10
			return profile.coins
		end)
		expect.equal(ok, true)
		expect.equal(result, 510)
		h.clock.advance(10)
		expect.equal(h.core.saveNowAsync(p), true)
		value, metadata = h.store.getRaw(KEY)
		expect.equal(value.coins, 510)
		expect.equal(value.saveSeq, 8)
		expect.equal(value.lastSeenAt, T0 + 10)
		expect.deepEqual(metadata, { note = "keep", lock = { o = ME, t = T0 + 10 } })
		expect.deepEqual(h.store.lastUserIds, { 101 })
		expect.equal(h.core.getProfile(p).saveSeq, 8)
		expect.equal(h.core.inspect(p).saveSeq, 8)
		expect.equal(h.store.forbiddenCalls, 0)
	end)

	t.test("a v1 profile is migrated in memory and written as v2 on the next save; migratedFrom = 1", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedV1(300, 1234), {}, { 101 })
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.equal(h.core.migratedFrom(p), 1)
		local profile = h.core.getProfile(p)
		expect.equal(profile.schemaVersion, 2)
		expect.equal(profile.coins, 1234)
		expect.deepEqual(profile.grip, {
			total = 3000,
			trainer = 1,
			rested = { value = 1200, at = T0 - 500 },
			afk = { value = 120, at = T0 - 500 },
		})
		expect.equal(h.store.getRaw(KEY).schemaVersion, 1) -- written on the next save (§3.3)
		expect.equal(h.core.saveNowAsync(p), true)
		local value = h.store.getRaw(KEY)
		expect.equal(value.schemaVersion, 2)
		expect.equal(value.grip.total, 3000)
		expect.equal(value.saveSeq, 13)
		-- the next session finds v2: no migration, no second head start
		expect.equal(h.core.releaseAsync(p), true)
		expect.equal(h.core.loadAsync(p), "ready")
		expect.equal(h.core.migratedFrom(p), nil)
		expect.equal(h.core.getProfile(p).grip.total, 3000)
	end)

	t.test("a fresh foreign lock: wait 6 +- 2 s and retry; the other server lets go", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 42 }), { lock = { o = OTHER, t = T0 } }, { 101 })
		h.store.onCall(function(callNumber: number, key: string)
			if callNumber == 3 then
				h.store.setMetadata(key, {}) -- the other server released the key
			end
		end)
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(h.waits, { 6, 6 })
		expect.equal(h.clock.now(), T0 + 12)
		expect.equal(h.store.calls, 3)
		expect.equal(h.store.writes, 1)
		expect.deepEqual(h.notices, { "data.waitingOtherServer" }) -- once, not on every poll
		expect.equal(h.core.getProfile(p).coins, 42)
		expect.deepEqual(select(2, h.store.getRaw(KEY)), { lock = { o = ME, t = T0 + 12 } })
	end)

	t.test(
		"a foreign lock past 45 s: OFFLINE with nothing written; a background retry takes over once stale",
		function()
			local h = newHarness()
			h.store.setRaw(KEY, storedProfile({ coins = 900 }), { lock = { o = OTHER, t = T0 } }, { 101 })
			local p = player()
			expect.equal(h.core.loadAsync(p), "offline")
			expect.equal(h.store.calls, 9) -- at 0, 6, ..., 48 s
			expect.equal(#h.waits, 8)
			expect.equal(h.clock.now(), T0 + 48)
			expect.equal(h.store.writes, 0)
			expect.deepEqual(h.notices, { "data.waitingOtherServer" })
			expect.equal(h.core.statusReason(p), "retrying")
			expect.equal(h.core.getProfile(p).coins, 0) -- defaults in memory, never saved
			local ok, reason = h.core.mutate(p, function(profile: any)
				profile.coins = 5
			end)
			expect.equal(ok, false)
			expect.equal(reason, "data.offline")
			expect.equal(h.core.saveNowAsync(p), false)

			for _ = 1, 600 do
				if h.core.getStatus(p) == "ready" then
					break
				end
				h.clock.advance(1)
				h.core.tick()
			end
			-- retries every 60 s from T0 + 48 (108, 168, 228, 288 still foreign); at 348 the lock is 348 s old: stale
			expect.equal(h.core.getStatus(p), "ready")
			expect.equal(h.clock.now(), T0 + 348)
			expect.equal(h.store.calls, 14)
			expect.equal(h.core.getProfile(p).coins, 900)
			expect.deepEqual(select(2, h.store.getRaw(KEY)), { lock = { o = ME, t = T0 + 348 } })
			expect.truthy(hasLine(h.logs, "took over a stale lock"))
			expect.deepEqual(h.loaded, { "offline", "ready" })
		end
	)

	t.test("a stale lock (>= 300 s) is taken over at once and logged", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 500 }), { lock = { o = OTHER, t = T0 - 300 } }, { 101 })
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(h.waits, {})
		expect.deepEqual(h.notices, {})
		expect.equal(h.core.getProfile(p).coins, 500)
		expect.deepEqual(select(2, h.store.getRaw(KEY)), { lock = { o = ME, t = T0 } })
		expect.truthy(hasLine(h.logs, "took over a stale lock from " .. OTHER))
	end)

	-- Retries and error classes ---------------------------------------------------------------------------------------

	t.test("ghost write on load (written, reported failed): the retry sees our own lock and proceeds", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 77 }), {}, { 101 })
		h.store.ghostNext(1)
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(outcomes(h.store), { "ghost", "write" })
		expect.deepEqual(h.waits, { 1.25 })
		expect.equal(h.core.getProfile(p).coins, 77)
		expect.deepEqual(h.loaded, { "ready" })
	end)

	t.test("ghost write on save: the retry is accepted because the stored saveSeq equals ours", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		h.store.ghostNext(1)
		h.core.mutate(p, function(profile: any)
			profile.coins = 50
		end)
		expect.equal(h.core.saveNowAsync(p), true)
		expect.deepEqual(outcomes(h.store), { "write", "ghost", "write" })
		local value = h.store.getRaw(KEY)
		expect.equal(value.saveSeq, 1)
		expect.equal(value.coins, 50)
		expect.equal(h.core.getStatus(p), "ready") -- not mistaken for a lost lock
		expect.equal(h.core.isSavePending(p), false)
		expect.equal(h.core.inspect(p).saveSeq, 1)
	end)

	t.test("ghost write on release: the retry finds its own final write and succeeds without writing again", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		h.core.mutate(p, function(profile: any)
			profile.coins = 40
		end)
		h.store.ghostNext(1)
		expect.equal(h.core.releaseAsync(p), true)
		expect.deepEqual(outcomes(h.store), { "write", "ghost", "cancel" })
		expect.deepEqual(h.waits, { 1.25 })
		local value, metadata = h.store.getRaw(KEY)
		expect.equal(value.coins, 40)
		expect.equal(value.saveSeq, 1)
		expect.deepEqual(metadata, {})
		expect.deepEqual(h.notices, {}) -- not mistaken for a lost lock
		expect.equal(h.core.getStatus(p), nil)
		expect.equal(hasLine(h.logs, "lock was lost"), false)
		expect.truthy(hasLine(h.logs, "info User_101 release: the write reported as failed had landed"))
		-- without that exact snapshot in the store (no lock, other saveSeq) a release is a lost lock: nothing written
		local q = player(102)
		h.core.loadAsync(q)
		h.store.setRaw("User_102", storedProfile({ saveSeq = 5 }), {}, { 102 })
		expect.equal(h.core.releaseAsync(q), false)
		expect.equal(h.store.getRaw("User_102").saveSeq, 5)
	end)

	t.test("UpdateAsync may run a transform twice: only the last run counts (load and save)", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 5 }), {}, { 101 })
		local function otherServerLocks(key: string)
			h.store.setMetadata(key, { lock = { o = OTHER, t = h.clock.now() } })
		end
		h.store.onCall(function(callNumber: number, key: string)
			if callNumber == 2 then
				h.store.setMetadata(key, {}) -- the other server let go before our next poll
			end
		end)
		-- the first run sees a free key, the second (after a concurrent lock) a foreign one: no write, wait, retry
		h.store.repeatTransformNext(1, otherServerLocks)
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(outcomes(h.store), { "cancel", "write" })
		expect.deepEqual(h.waits, { 6 })
		expect.deepEqual(h.notices, { "data.waitingOtherServer" })
		expect.deepEqual(select(2, h.store.getRaw(KEY)), { lock = { o = ME, t = T0 + 6 } })
		h.store.onCall(nil)
		-- a save whose last run finds another server's lock writes nothing and reads as a lost lock
		h.core.mutate(p, function(profile: any)
			profile.coins = 9
		end)
		h.store.repeatTransformNext(1, otherServerLocks)
		expect.equal(h.core.saveNowAsync(p), false)
		expect.equal(h.core.getStatus(p), "readonly")
		expect.equal(h.core.statusReason(p), "lost")
		expect.equal(h.store.getRaw(KEY).coins, 5)
		expect.equal(h.store.writes, 1)
	end)

	t.test("throttle 304 is retried with a doubled delay (load and save)", function()
		local h = newHarness()
		h.store.failNext(2, 304, "Request was throttled")
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(h.waits, { 2.5, 5 })
		h.store.failNext(1, 304)
		expect.equal(h.core.saveNowAsync(p), true)
		expect.deepEqual(h.waits, { 2.5, 5, 2.5 })
		expect.equal(h.store.getRaw(KEY).saveSeq, 1)
	end)

	t.test("non-retryable 105 on a save: one attempt; savePending until a later save succeeds", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		h.store.failNext(1, 105, "Serialized value converted byte size exceeds max size")
		h.core.mutate(p, function(profile: any)
			profile.coins = 5
		end)
		local callsBefore = h.store.calls
		expect.equal(h.core.saveNowAsync(p), false)
		expect.equal(h.store.calls, callsBefore + 1)
		expect.deepEqual(h.waits, {})
		expect.truthy(hasLine(h.logs, "error User_101 now save failed (fatal: 105")) -- never retried: an error
		expect.equal(h.core.isSavePending(p), true)
		expect.deepEqual(h.core.dataStatus(p), { status = "ready", persisted = true, savePending = true })
		expect.deepEqual(h.statuses[#h.statuses], { status = "ready", persisted = true, savePending = true })
		expect.equal(h.core.inspect(p).soonAt, T0 + 6) -- a "soon" retry is scheduled
		expect.equal(h.store.getRaw(KEY).coins, 0)
		h.clock.set(T0 + 6)
		h.core.tick()
		expect.equal(h.store.getRaw(KEY).coins, 5)
		expect.equal(h.core.isSavePending(p), false)
		expect.deepEqual(h.statuses[#h.statuses], { status = "ready", persisted = true, savePending = false })
	end)

	t.test("non-retryable 105 on load: OFFLINE at once with zero writes", function()
		local h = newHarness()
		h.store.failNext(1, 105)
		local p = player()
		expect.equal(h.core.loadAsync(p), "offline")
		expect.equal(h.store.calls, 1)
		expect.deepEqual(h.waits, {})
		expect.equal(h.store.writes, 0)
		expect.truthy(hasLine(h.logs, "error User_101 OFFLINE (fatal: 105")) -- never retried: an error
	end)

	-- Never saved -----------------------------------------------------------------------------------------------------

	t.test("a newer stored schema is READONLY: shown, never saved, the lock is never taken", function()
		local h = newHarness()
		local v3 = storedProfile({ coins = 999, schemaVersion = 3 })
		v3.futureThing = { keep = true }
		h.store.setRaw(KEY, v3, { note = "theirs" }, { 101 })
		local p = player()
		expect.equal(h.core.loadAsync(p), "readonly")
		expect.equal(h.core.statusReason(p), "newer")
		expect.deepEqual(h.loaded, { "readonly" })
		local profile = h.core.getProfile(p)
		expect.equal(profile.coins, 999)
		expect.equal(profile.schemaVersion, 3)
		local ok, reason = h.core.mutate(p, function(d: any)
			d.coins = 0
		end)
		expect.equal(ok, false)
		expect.equal(reason, "data.readOnly")
		h.core.requestSave(p, "soon")
		h.core.requestSave(p, "autosave")
		h.core.requestSave(p, "now")
		expect.equal(h.core.saveNowAsync(p), false)
		for _ = 1, 400 do
			h.clock.advance(1)
			h.core.tick()
		end
		expect.equal(h.core.releaseAsync(p), true)
		expect.equal(h.store.writes, 0)
		local value, metadata = h.store.getRaw(KEY)
		expect.deepEqual(value, v3)
		expect.deepEqual(metadata, { note = "theirs" })
		expect.deepEqual(h.notices, {}) -- the "new version" text is StateService's banner (statusReason "newer")
	end)

	t.test("FAILING LOADS -> ZERO WRITES: OFFLINE defaults, no save of any reason, retries run out", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 4321 }), {}, { 101 })
		h.store.failAlways(503, "Internal error")
		local p = player()
		expect.equal(h.core.loadAsync(p), "offline")
		expect.equal(h.store.calls, 5)
		expect.deepEqual(h.waits, { 1.25, 2.5, 5, 10 })
		expect.truthy(hasLine(h.logs, "warn User_101 OFFLINE (retry: 503")) -- retried codes: a warning
		expect.deepEqual(h.loaded, { "offline" })
		expect.deepEqual(h.core.getProfile(p), ProfileSchema.defaults(T0 + 18.75))
		expect.equal(h.core.statusReason(p), "retrying")
		local ok, reason = h.core.mutate(p, function(profile: any)
			profile.coins = 1
		end)
		expect.equal(ok, false)
		expect.equal(reason, "data.offline")
		for _, why in { "soon", "now", "autosave" } do
			h.core.requestSave(p, why :: any)
		end
		expect.equal(h.core.saveNowAsync(p), false)
		local statusEvents = #h.statuses
		for _ = 1, 900 do
			h.clock.advance(1)
			h.core.tick()
		end
		expect.equal(h.store.calls, 5 + 5 * 5) -- 5 background retries of 5 attempts each
		expect.equal(h.core.statusReason(p), "exhausted")
		expect.equal(#h.statuses, statusEvents + 1) -- one status change when the retries ran out
		expect.equal(h.core.releaseAsync(p), true)
		expect.equal(h.core.getStatus(p), nil)
		expect.equal(h.store.writes, 0)
		for _, outcome in outcomes(h.store) do
			expect.equal(outcome, "fail")
		end
		expect.equal(h.store.getRaw(KEY).coins, 4321) -- defaults never overwrote the real data
	end)

	t.test("an OFFLINE session swaps in its real profile when a background retry succeeds", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 777 }), {}, { 101 })
		h.store.failNext(5, 503)
		local p = player()
		expect.equal(h.core.loadAsync(p), "offline")
		local offlineProfile = h.core.getProfile(p)
		expect.equal(offlineProfile.coins, 0)
		expect.equal(h.store.writes, 0)
		h.clock.advance(60)
		h.core.tick()
		expect.equal(h.core.getStatus(p), "ready")
		expect.equal(h.core.statusReason(p), nil)
		expect.equal(h.core.getProfile(p).coins, 777)
		expect.truthy(h.core.getProfile(p) ~= offlineProfile)
		expect.deepEqual(h.loaded, { "offline", "ready" })
		expect.equal(h.store.writes, 1)
		expect.deepEqual(h.notices, {}) -- "Progress loaded!" is StateService's Notify
	end)

	t.test("leaving during an OFFLINE background retry waits for it and gives back the lock it got", function()
		local h = newHarness()
		local stored = storedProfile({ coins = 321 })
		h.store.setRaw(KEY, stored, {}, { 101 })
		h.store.failNext(5, 503)
		local p = player()
		expect.equal(h.core.loadAsync(p), "offline")
		h.store.pause()
		h.clock.advance(60)
		h.core.tick() -- the background retry starts and blocks in the store
		expect.equal(h.store.blockedCount(), 1)
		local released = nil
		task.spawn(function()
			released = h.core.releaseAsync(p)
		end)
		expect.equal(released, nil) -- waits for the retry
		h.store.resume()
		expect.equal(released, true)
		expect.equal(h.core.getStatus(p), nil)
		expect.deepEqual(h.loaded, { "offline" }) -- the real profile was never swapped in
		local value, metadata = h.store.getRaw(KEY)
		expect.deepEqual(value, stored)
		expect.deepEqual(metadata, {}) -- the lock that retry took is gone
		expect.equal(h.store.writes, 2) -- the retry's lock, then the unlock; never a profile
	end)

	t.test("lost lock: another server owns the key -> READONLY, data.openedElsewhere, nothing overwritten", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile({ coins = 500 }), {}, { 101 })
		local p = player()
		h.core.loadAsync(p)
		h.core.mutate(p, function(profile: any)
			profile.coins = 600
		end)
		h.store.setMetadata(KEY, { lock = { o = OTHER, t = T0 } })
		expect.equal(h.core.saveNowAsync(p), false)
		expect.equal(h.core.getStatus(p), "readonly")
		expect.equal(h.core.statusReason(p), "lost")
		expect.deepEqual(h.notices, { "data.openedElsewhere" })
		local ok, reason = h.core.mutate(p, function(profile: any)
			profile.coins = 700
		end)
		expect.equal(ok, false)
		expect.equal(reason, "data.readOnly")
		expect.equal(h.core.releaseAsync(p), true)
		expect.equal(h.store.writes, 1) -- the load only
		local value, metadata = h.store.getRaw(KEY)
		expect.equal(value.coins, 500)
		expect.deepEqual(metadata, { lock = { o = OTHER, t = T0 } })
	end)

	t.test("lost lock: a stored saveSeq above ours also aborts the save (READONLY)", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		local owner = h.core.inspect(p).owner
		expect.equal(owner, ME)
		h.store.setRaw(KEY, storedProfile({ saveSeq = 99, coins = 5 }), { lock = { o = owner, t = T0 } }, { 101 })
		expect.equal(h.core.saveNowAsync(p), false)
		expect.equal(h.core.getStatus(p), "readonly")
		local value = h.store.getRaw(KEY)
		expect.equal(value.saveSeq, 99)
		expect.equal(value.coins, 5)
	end)

	-- Save timing -----------------------------------------------------------------------------------------------------

	t.test("a save takes its snapshot when it STARTS; 'now' joins a queued save behind a running one", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		h.store.pause()
		h.core.requestSave(p, "autosave") -- starts at once (snapshot: coins 0) and blocks in the store
		h.core.mutate(p, function(profile: any)
			profile.coins = 10
		end)
		local first, second = nil, nil
		task.spawn(function()
			first = h.core.saveNowAsync(p)
		end)
		h.core.mutate(p, function(profile: any)
			profile.coins = 20 -- after the "now" request, before its job starts
		end)
		task.spawn(function()
			second = h.core.saveNowAsync(p)
		end)
		expect.equal(h.core.counts().queuedJobs, 1) -- both "now" calls share one queued job
		expect.equal(first, nil)
		h.store.resume()
		expect.equal(first, true)
		expect.equal(second, true)
		expect.equal(h.store.writes, 3) -- load, autosave, one "now"
		local value = h.store.getRaw(KEY)
		expect.equal(value.coins, 20)
		expect.equal(value.saveSeq, 2)
	end)

	-- Pens3 phase 4: the next load pays the time away at the rate the pen had when it was saved.
	t.test("every save stamps pen.awayRate = the pen's Coins a second (PenMath.rate) next to lastSeenAt", function()
		local h = newHarness()
		h.store.setRaw(KEY, storedProfile(), {}, { 101 })
		local p = player()
		h.core.loadAsync(p)
		expect.equal(h.core.getProfile(p).pen.awayRate, 0) -- a new pen: nothing saved yet
		h.core.mutate(p, function(profile: any)
			profile.owned.butter = { at = T0, src = "box" }
			table.insert(
				profile.pen.items,
				{ id = 2, kind = "butter", form = 0, level = 1, coat = 0, slot = 2, locked = false }
			)
		end)
		h.clock.advance(10)
		expect.equal(h.core.saveNowAsync(p), true)
		local value = h.store.getRaw(KEY)
		expect.equal(value.pen.awayRate, 50) -- Kitty Bread 10 + Butter 40
		expect.equal(value.lastSeenAt, T0 + 10)
		expect.equal(h.core.getProfile(p).pen.awayRate, 50) -- the profile in memory matches the save
		expect.truthy(h.core.releaseAsync(p))
		expect.equal(h.store.getRaw(KEY).pen.awayRate, 50) -- the final write too
	end)

	t.test("'soon' saves run at max(now + 6, lastWriteAt + 6) and later requests join them", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p) -- lastWriteAt = T0
		h.clock.advance(1)
		h.core.requestSave(p, "soon")
		expect.equal(h.core.inspect(p).soonAt, T0 + 7)
		h.clock.advance(3)
		h.core.requestSave(p, "soon") -- joins the timer
		expect.equal(h.core.inspect(p).soonAt, T0 + 7)
		h.clock.set(T0 + 6.5)
		h.core.tick()
		expect.equal(h.store.writes, 1)
		h.clock.set(T0 + 7)
		h.core.tick()
		expect.equal(h.store.writes, 2)
		expect.equal(h.core.inspect(p).soonAt, nil)
		-- a "now" save before the timer is due takes the timer's place
		h.core.requestSave(p, "soon")
		expect.equal(h.core.inspect(p).soonAt, T0 + 13)
		expect.equal(h.core.saveNowAsync(p), true)
		expect.equal(h.core.inspect(p).soonAt, nil)
		h.clock.set(T0 + 20)
		h.core.tick()
		expect.equal(h.store.writes, 3)
	end)

	t.test("autosave every 120 s after a random first offset; a low request budget delays it 15 s", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		expect.equal(h.core.inspect(p).nextAutosaveAt, T0 + 60) -- random() 0.5 x 120
		h.clock.set(T0 + 59)
		h.core.tick()
		expect.equal(h.store.writes, 1)
		h.clock.set(T0 + 60)
		h.core.tick()
		expect.equal(h.store.writes, 2) -- always writes (refreshes the lock), even without changes
		expect.deepEqual(select(2, h.store.getRaw(KEY)), { lock = { o = ME, t = T0 + 60 } })
		expect.equal(h.core.inspect(p).nextAutosaveAt, T0 + 180)
		h.store.setBudget(Config.Data.autosaveBudgetFloor - 1)
		h.clock.set(T0 + 180)
		h.core.tick()
		expect.equal(h.store.writes, 2)
		expect.equal(h.core.inspect(p).nextAutosaveAt, T0 + 195)
		h.store.setBudget(math.huge)
		h.clock.set(T0 + 195)
		h.core.tick()
		expect.equal(h.store.writes, 3)
	end)

	-- Leave and close -------------------------------------------------------------------------------------------------

	t.test("release on leave: one final write without the lock; idempotent; concurrent calls share it", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		h.core.mutate(p, function(profile: any)
			profile.coins = 30
		end)
		h.store.pause()
		local first, second = nil, nil
		task.spawn(function()
			first = h.core.releaseAsync(p)
		end)
		task.spawn(function()
			second = h.core.releaseAsync(p)
		end)
		-- the final snapshot is taken: later changes would be lost, so they are refused
		local ok, reason = h.core.mutate(p, function(profile: any)
			profile.coins = 31
		end)
		expect.equal(ok, false)
		expect.equal(reason, "data.notReady")
		expect.equal(h.core.getStatus(p), "ready") -- the releasing state of a ready session
		h.store.resume()
		expect.equal(first, true)
		expect.equal(second, true)
		expect.equal(h.store.writes, 2)
		local value, metadata, userIds = h.store.getRaw(KEY)
		expect.equal(value.coins, 30)
		expect.equal(value.saveSeq, 1)
		expect.deepEqual(metadata, {})
		expect.deepEqual(userIds, { 101 })
		expect.equal(h.core.getStatus(p), nil)
		expect.equal(h.core.getProfile(p), nil)
		expect.equal(h.core.releaseAsync(p), true)
		expect.equal(h.store.writes, 2)

		-- playerRemoving releases too (deferred; the harness runs deferred work at once)
		local p2 = player(102)
		h.core.loadAsync(p2)
		h.core.playerRemoving(p2)
		expect.equal(h.core.getStatus(p2), nil)
		expect.equal(h.store.writesFor("User_102"), 2)
		expect.deepEqual(select(2, h.store.getRaw("User_102")), {})
	end)

	t.test("close: releaseAll writes each ready session once, folds pending saves, skips OFFLINE / READONLY", function()
		local storeA = FakeDataStore.new("A")
		local storeB = FakeDataStore.new("B")
		local h = newHarness({
			store = storeA,
			storeFor = function(userId: number): any
				return if userId == 104 then storeB else storeA
			end,
		})
		local v3 = storedProfile({ schemaVersion = 3 })
		storeA.setRaw("User_103", v3, {}, { 103 })
		storeB.failAlways(503)
		local p1, p2, p3, p4 = player(101), player(102), player(103), player(104)
		expect.equal(h.core.loadAsync(p1), "ready")
		expect.equal(h.core.loadAsync(p2), "ready")
		expect.equal(h.core.loadAsync(p3), "readonly")
		expect.equal(h.core.loadAsync(p4), "offline")
		expect.equal(storeA.writes, 2)

		storeA.pause()
		h.core.requestSave(p1, "autosave") -- running, blocked in the store
		local nowResult = nil
		task.spawn(function()
			nowResult = h.core.saveNowAsync(p1) -- queued behind it
		end)
		h.closing = true
		local released = nil
		task.spawn(function()
			released = h.core.releaseAllAsync()
		end)
		-- the queued "now" save became p1's final write; nothing new starts while closing
		h.core.requestSave(p2, "soon")
		h.clock.advance(30)
		h.core.tick()
		h.core.mutate(p1, function(profile: any)
			profile.coins = 33 -- before p1's final snapshot is taken: included
		end)
		expect.equal(released, nil)
		storeA.resume()
		expect.equal(released, 4)
		expect.equal(nowResult, true)
		expect.equal(storeA.writes, 5) -- 2 loads + p1 autosave + p1 final + p2 final
		local value1, meta1 = storeA.getRaw(KEY)
		expect.equal(value1.coins, 33)
		expect.equal(value1.saveSeq, 2)
		expect.deepEqual(meta1, {})
		expect.deepEqual(select(2, storeA.getRaw("User_102")), {})
		expect.equal(storeA.writesFor("User_103"), 0)
		expect.deepEqual(storeA.getRaw("User_103"), v3)
		expect.equal(storeB.writes, 0)
		for _, p in { p1, p2, p3, p4 } do
			expect.equal(h.core.getStatus(p), nil)
		end
		expect.equal(h.core.releaseAllAsync(), 0)
	end)

	t.test("a player who joins while the server is closing is released right after the load", function()
		local h = newHarness()
		h.closing = true
		local p = player()
		expect.equal(h.core.loadAsync(p), nil) -- already released
		expect.equal(h.core.getStatus(p), nil)
		expect.equal(h.store.writes, 2)
		expect.deepEqual(select(2, h.store.getRaw(KEY)), {})
	end)

	t.test("a load cancelled by leaving never saves the profile and gives the lock back", function()
		local h = newHarness()
		local stored = storedProfile({ coins = 500 })
		h.store.setRaw(KEY, stored, {}, { 101 })
		local p = player()
		h.store.pause()
		task.spawn(function()
			h.core.loadAsync(p)
		end)
		expect.equal(h.core.getStatus(p), "loading")
		local released = nil
		task.spawn(function()
			released = h.core.releaseAsync(p)
		end)
		expect.equal(released, nil) -- waits for the load to finish
		h.store.resume()
		expect.equal(released, true)
		expect.equal(h.core.getStatus(p), nil)
		expect.deepEqual(h.loaded, {}) -- never became ready
		local value, metadata = h.store.getRaw(KEY)
		expect.deepEqual(value, stored)
		expect.deepEqual(metadata, {})
	end)

	-- API rules -------------------------------------------------------------------------------------------------------

	t.test("mutate: refused while loading; runs synchronously when ready; errors are contained", function()
		local h = newHarness()
		local p = player()
		local ok, reason = h.core.mutate(p, function() end)
		expect.equal(ok, false)
		expect.equal(reason, "data.notReady") -- no session
		h.store.pause()
		task.spawn(function()
			h.core.loadAsync(p)
		end)
		ok, reason = h.core.mutate(p, function() end)
		expect.equal(ok, false)
		expect.equal(reason, "data.notReady") -- loading
		h.store.resume()
		local result
		ok, result = h.core.mutate(p, function(profile: any): any
			profile.coins = 42
			return "done"
		end)
		expect.equal(ok, true)
		expect.equal(result, "done")
		expect.equal(h.core.getProfile(p).coins, 42)
		ok, reason = h.core.mutate(p, function()
			error("boom")
		end)
		expect.equal(ok, false)
		expect.equal(reason, "error.generic")
		expect.truthy(hasLine(h.logs, "error mutate failed"))
		expect.equal(DataService.update, DataService.mutate)
	end)

	t.test("pending receipts are captured by the save snapshot and cleared only by a successful save", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		h.core.addPendingReceipt(p, "purchase-1")
		expect.equal(h.core.isReceiptPending(p, "purchase-1"), true)
		h.store.failNext(1, 105)
		expect.equal(h.core.saveNowAsync(p), false)
		expect.equal(h.core.isReceiptPending(p, "purchase-1"), true)
		expect.equal(h.core.saveNowAsync(p), true)
		expect.equal(h.core.isReceiptPending(p, "purchase-1"), false)
	end)

	t.test("waitForProfileAsync returns a ready profile and nil otherwise", function()
		local h = newHarness()
		local p = player()
		h.core.loadAsync(p)
		expect.equal(h.core.waitForProfileAsync(p), h.core.getProfile(p))
		expect.equal(h.core.waitForProfileAsync(player(555), 1), nil) -- never joined: times out
		local failing = newHarness()
		failing.store.failAlways(503)
		local q = player(102)
		failing.core.loadAsync(q)
		expect.equal(failing.core.waitForProfileAsync(q), nil) -- OFFLINE
	end)

	-- Stores ----------------------------------------------------------------------------------------------------------

	t.test("memory mode: InMemoryAdapter sessions are ready but not persisted", function()
		local memory = InMemoryAdapter.new("Memory")
		local h = newHarness({ store = memory })
		local p = player()
		expect.equal(h.core.loadAsync(p), "ready")
		expect.deepEqual(h.core.dataStatus(p), { status = "ready", persisted = false, savePending = false })
		h.core.mutate(p, function(profile: any)
			profile.coins = 5
		end)
		expect.equal(h.core.saveNowAsync(p), true)
		local value, info = memory.peek(KEY)
		expect.equal(value.coins, 5)
		expect.deepEqual(info, { metadata = { lock = { o = ME, t = T0 } }, userIds = { 101 } })
		expect.equal(h.core.releaseAsync(p), true)
		expect.deepEqual(select(2, memory.peek(KEY)), { metadata = {}, userIds = { 101 } })
		-- multi-client test players (userId <= 0) always use memory
		local chosen = { kind = "datastore", name = "PlayerData_v1", probe = false }
		expect.equal(DataService.storeKindFor(-1, chosen), "memory")
		expect.equal(DataService.storeKindFor(0, chosen), "memory")
		expect.equal(DataService.storeKindFor(101, chosen), "datastore")
	end)

	t.test("store selection: memory by default in Studio, _STUDIO only, live PlayerData_v1", function()
		local base = { studioMode = "memory", storeName = "PlayerData_v1", studioStoreName = "PlayerData_v1_STUDIO" }
		local function pick(isStudio: boolean, mode: string): any
			local ctx = table.clone(base) :: any
			ctx.isStudio = isStudio
			ctx.studioMode = mode
			return DataService.selectStore(ctx)
		end
		expect.deepEqual(pick(false, "memory"), { kind = "datastore", name = "PlayerData_v1", probe = false })
		expect.deepEqual(pick(true, "memory"), { kind = "memory", name = "Memory", probe = false })
		expect.deepEqual(pick(true, "datastore"), { kind = "datastore", name = "PlayerData_v1_STUDIO", probe = true })
		expect.equal(Config.Data.studioMode, "memory")
		expect.equal(string.sub(Config.Data.studioStoreName, -7), "_STUDIO")
		expect.equal(DataStoreAdapter.isSafeName("PlayerData_v1", true), false)
		expect.equal(DataStoreAdapter.isSafeName("PlayerData_v1_STUDIO", true), true)
		expect.equal(DataStoreAdapter.isSafeName("PlayerData_v1", false), true)
		expect.equal(DataStoreAdapter.isSafeName("", false), false)
		expect.throws(function()
			DataStoreAdapter.assertSafeName("PlayerData_v1", true)
		end, "_STUDIO")
		-- the guard runs before the service is touched
		local touched = false
		local service = {
			GetDataStore = function(): any
				touched = true
				return nil
			end,
		}
		expect.throws(function()
			DataStoreAdapter.open("PlayerData_v1", { isStudio = true, service = service :: any })
		end, "_STUDIO")
		expect.equal(touched, false)
	end)

	t.test("debugReloadAsync migrates a stored v1 fixture through the real pipeline (memory store only)", function()
		local memory = InMemoryAdapter.new("Memory")
		local h = newHarness({ store = memory })
		local p = player()
		h.core.loadAsync(p)
		local reply = h.core.debugReloadAsync(p, storedV1(1200, 50))
		expect.deepEqual(reply, { ok = true, status = "ready", migratedFrom = 1 })
		expect.equal(h.core.getProfile(p).grip.total, 12000)
		expect.equal(h.core.getProfile(p).coins, 50)
		expect.deepEqual(h.loaded, { "ready", "ready" })
		-- a persisted store is never reloaded this way
		local persisted = newHarness()
		local q = player(102)
		persisted.core.loadAsync(q)
		expect.equal(persisted.core.debugReloadAsync(q, storedV1(1, 1)).ok, false)
		expect.equal(persisted.store.writes, 1)
	end)

	t.test(
		"forced save failure (memory failNext): a 'now' save sets savePending, a later 'soon' retry clears it",
		function()
			local memory = InMemoryAdapter.new("Memory")
			local h = newHarness({ store = memory })
			local p = player()
			h.core.loadAsync(p)
			local message = "105: Studio test forced save failure"
			expect.deepEqual(h.core.debugFailSaves(p, 2, message), { ok = true, count = 2 })
			h.core.mutate(p, function(profile: any)
				profile.coins = 7
			end)
			expect.equal(h.core.saveNowAsync(p), false)
			expect.deepEqual(h.waits, {}) -- 105 is never retried: no backoff, the failure is immediate
			expect.truthy(hasLine(h.logs, "error User_101 now save failed (fatal: " .. message))
			expect.equal(h.core.isSavePending(p), true)
			expect.deepEqual(h.statuses[#h.statuses], { status = "ready", persisted = false, savePending = true })
			expect.equal(h.core.inspect(p).soonAt, T0 + 6)
			expect.equal(memory.peek(KEY).coins, 0)
			-- the first "soon" retry uses the second forced failure and schedules the next retry
			h.clock.set(T0 + 6)
			h.core.tick()
			expect.equal(h.core.isSavePending(p), true)
			expect.equal(memory.peek(KEY).coins, 0)
			expect.equal(h.core.inspect(p).soonAt, T0 + 12)
			-- the failures are used up: the next "soon" retry writes and clears savePending
			h.clock.set(T0 + 12)
			h.core.tick()
			expect.equal(memory.peek(KEY).coins, 7)
			expect.equal(h.core.isSavePending(p), false)
			expect.deepEqual(h.statuses[#h.statuses], { status = "ready", persisted = false, savePending = false })
			-- count 0 clears forced failures that were not used
			h.core.debugFailSaves(p, 3, message)
			expect.deepEqual(h.core.debugFailSaves(p, 0, message), { ok = true, count = 0 })
			expect.equal(h.core.saveNowAsync(p), true)
			-- a persisted store never fails on purpose
			local persisted = newHarness()
			local q = player(102)
			persisted.core.loadAsync(q)
			expect.equal(persisted.core.debugFailSaves(q, 1, message).ok, false)
			expect.equal(persisted.core.saveNowAsync(q), true)
		end
	)
end
