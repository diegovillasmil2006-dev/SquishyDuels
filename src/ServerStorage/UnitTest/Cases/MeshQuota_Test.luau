--!strict
-- MeshQuota_Test: unit tests for StarterPlayerScripts.Client.Anim.MeshQuota (the editable-mesh slots shared by the
-- jelly ripple's skin and Inspect's knead shell; the giant pads' 3 went with them, build plan Phase 6). Server only
-- (ServerStorage.UnitTest). Private quotas (MeshQuota.new), so the client's shared quota is never touched, except to
-- read its limit.
-- Contract (DESIGN §18.3.4, §18.9, §18.11):
--   * at most Config.Vfx.Budgets.editableMeshes (2: a ripple skin + the knead shell, spec phase2-squeeze §3.2) slots per
--     client: 2 acquired, the 3rd refused;
--   * a release frees a slot; a key already held answers true and takes no second slot; an unknown release does
--     nothing; count() and keys() follow.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local MeshQuota = t.requireClient("Anim/MeshQuota")
	local Config = t.requireShared("Config")
	local LIMIT = Config.Vfx.Budgets.editableMeshes

	-- Spec phase2-squeeze §3.2: one more slot, "soft", for Inspect's knead shell.
	t.test("the shared limit is Config.Vfx.Budgets.editableMeshes (2: a ripple skin and the knead shell)", function()
		expect.equal(LIMIT, 2)
		expect.equal(MeshQuota.limit(), LIMIT)
	end)

	t.test("2 acquired, the 3rd refused", function()
		local quota = MeshQuota.new(LIMIT)
		for _, key in { "arena", "soft" } do
			expect.truthy(quota:tryAcquire(key))
		end
		expect.equal(quota:count(), 2)
		expect.falsy(quota:tryAcquire("backstop"))
		expect.equal(quota:count(), 2)
		expect.falsy(quota:holds("backstop"))
	end)

	t.test("a release frees a slot", function()
		local quota = MeshQuota.new(LIMIT)
		for _, key in { "backstop", "soft" } do
			quota:tryAcquire(key)
		end
		expect.falsy(quota:tryAcquire("arena"))
		quota:release("backstop")
		expect.equal(quota:count(), 1)
		expect.truthy(quota:tryAcquire("arena"))
		expect.deepEqual(quota:keys(), { "arena", "soft" })
	end)

	t.test("a held key takes no second slot; an unknown release does nothing", function()
		local quota = MeshQuota.new(2)
		expect.truthy(quota:tryAcquire("arena"))
		expect.truthy(quota:tryAcquire("arena"))
		expect.equal(quota:count(), 1)
		quota:release("nothing")
		expect.equal(quota:count(), 1)
		quota:release("arena")
		quota:release("arena")
		expect.equal(quota:count(), 0)
		expect.deepEqual(quota:keys(), {})
	end)

	t.test("bad keys and limits are refused", function()
		expect.throws(function()
			MeshQuota.new(-1)
		end)
		expect.throws(function()
			MeshQuota.new(1.5)
		end)
		expect.throws(function()
			MeshQuota.new(1):tryAcquire("")
		end)
	end)
end
