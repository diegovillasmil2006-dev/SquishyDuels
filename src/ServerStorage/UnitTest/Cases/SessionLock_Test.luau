--!strict
-- SessionLock_Test: the lock decision table of DESIGN §3.7 (server Logic/SessionLock, pure).
-- Server only (ServerStorage.UnitTest). Every row of the table for held = false (load) and held = true (save), the
-- stale boundary (now - t >= staleAfter), the malformed-lock readings, and the owner / nonce helpers.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

local ME = "job-1234/abcd0123"
local OTHER = "job-9999/ffff0000"
local STALE = 300
local NOW = 1_800_000_000

return function(t: Context)
	local expect = t.expect
	local SessionLock = t.requireServer("Logic/SessionLock")

	t.test("no lock: load acquires (free), save has lost it", function()
		expect.equal(SessionLock.evaluate(nil, NOW, ME, STALE, false), "free")
		expect.equal(SessionLock.evaluate(nil, NOW, ME, STALE, true), "lost")
	end)

	t.test("own lock: mine for load (a ghost write) and for save", function()
		local lock = { o = ME, t = NOW - 10 }
		expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, false), "mine")
		expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, true), "mine")
		-- even when it is old: it is still ours
		expect.equal(SessionLock.evaluate({ o = ME, t = NOW - 10_000 }, NOW, ME, STALE, true), "mine")
	end)

	t.test("another server's fresh lock: foreign for load, lost for save", function()
		local lock = { o = OTHER, t = NOW - (STALE - 1) }
		expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, false), "foreign")
		expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, true), "lost")
	end)

	t.test("another server's lock at exactly staleAfter is stale (>=); save still lost", function()
		local lock = { o = OTHER, t = NOW - STALE }
		expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, false), "stale")
		expect.equal(SessionLock.evaluate({ o = OTHER, t = NOW - STALE - 500 }, NOW, ME, STALE, false), "stale")
		expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, true), "lost")
	end)

	t.test("malformed locks (readings): never ours, never block forever", function()
		expect.equal(SessionLock.evaluate("garbage", NOW, ME, STALE, false), "free")
		expect.equal(SessionLock.evaluate({ o = 5, t = NOW }, NOW, ME, STALE, false), "stale")
		expect.equal(SessionLock.evaluate({ o = OTHER, t = 0 / 0 }, NOW, ME, STALE, false), "stale")
		expect.equal(SessionLock.evaluate({ o = "", t = NOW }, NOW, ME, STALE, false), "stale")
		-- a stamp far in the future (broken clock) does not block the key until that time
		expect.equal(SessionLock.evaluate({ o = OTHER, t = NOW + STALE + 1 }, NOW, ME, STALE, false), "stale")
		expect.equal(SessionLock.evaluate({ o = OTHER, t = NOW + 30 }, NOW, ME, STALE, false), "foreign")
		for _, lock in { "garbage", { o = 5, t = NOW }, { o = OTHER, t = NOW } } :: { any } do
			expect.equal(SessionLock.evaluate(lock, NOW, ME, STALE, true), "lost")
		end
	end)

	t.test("newLock, owner and nonce helpers", function()
		expect.deepEqual(SessionLock.newLock(ME, NOW), { o = ME, t = NOW })
		expect.equal(SessionLock.owner("", "abcd0123"), "studio/abcd0123")
		expect.equal(SessionLock.owner(nil, "abcd0123"), "studio/abcd0123")
		expect.equal(SessionLock.owner("6f1c", "abcd0123"), "6f1c/abcd0123")
		local nonce = SessionLock.nonceFrom("{9C2D9A6E-1B2C-4D5E-8F90-ABCDEF012345}")
		expect.equal(nonce, "9c2d9a6e")
		expect.equal(#SessionLock.nonceFrom("ab"), 8)
		-- the metadata stays well under the 300-character limit (§3.7: < 120)
		local owner = SessionLock.owner(string.rep("a", 36), nonce)
		local encoded = string.format('{"lock":{"o":"%s","t":%d}}', owner, NOW)
		expect.truthy(#encoded < 120)
	end)
end
