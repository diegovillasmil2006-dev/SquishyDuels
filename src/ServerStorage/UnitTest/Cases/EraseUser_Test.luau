--!strict
-- EraseUser_Test (audit row 26, 2026-11-12): ServerStorage.SDTools.EraseUser's plan, what a right-to-erasure request
-- deletes. Server only (ServerStorage.UnitTest). Pure: run() is never called (it reaches the live data stores).
-- Contract:
--   * the save first: Config.Data.storeName, key keyPrefix .. userId, no scope, not ordered;
--   * then the weekly wins board: Config.Social.Board.storeName, ordered, key tostring(userId), one scope "w<week>" per
--     week with no gap, from FIRST_WEEK_TIME's week up to ShowOffService's week of `now`;
--   * a userId that is not a whole number above 0 is refused (an error), never a key like "User_0" or "User_1.5".

local ServerStorage = game:GetService("ServerStorage")

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

-- `require` with a ModuleScript found at run time; the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local ShowOffService = t.requireServer("Services/ShowOffService")
	local tools = ServerStorage:FindFirstChild("SDTools")
	local module = tools and tools:FindFirstChild("EraseUser")
	assert(module and module:IsA("ModuleScript"), "ServerStorage.SDTools.EraseUser is missing")
	local EraseUser = dynamicRequire(module)

	t.test("plan: the save, then every week of the wins board up to now", function()
		local now = 1_794_000_000 -- 2026-11-06
		local plan = EraseUser.plan(123456789, now, Config)
		local save = plan[1]
		expect.equal(save.store, Config.Data.storeName)
		expect.equal(save.key, Config.Data.keyPrefix .. "123456789")
		expect.equal(save.scope, nil)
		expect.equal(save.ordered, false)
		local first = ShowOffService.weekIndex(EraseUser.FIRST_WEEK_TIME)
		local last = ShowOffService.weekIndex(now)
		expect.equal(#plan, 1 + (last - first + 1))
		for i = 2, #plan do
			local target = plan[i]
			expect.equal(target.store, Config.Social.Board.storeName)
			expect.equal(target.ordered, true)
			expect.equal(target.key, "123456789")
			expect.equal(target.scope, "w" .. (first + i - 2))
		end
	end)

	t.test("plan: a bad userId is refused", function()
		for _, bad in { 0, -3, 1.5, 0 / 0 } do
			expect.equal((pcall(EraseUser.plan, bad, 1_794_000_000, Config)), false)
		end
		expect.equal((pcall(EraseUser.plan, "123" :: any, 1_794_000_000, Config)), false)
	end)
end
