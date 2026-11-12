--!strict
-- SourceSize_Test (audit rows 8 and 27, 2026-11-12): every script of the five code folders stays under Roblox's
-- 200,000-character Source limit, where the snapshot tool's go-back fails (Config/UI.luau was 206,766 until
-- Config/MatchFound moved out; Config/init 192,915 until Config/ValidateFirstPerson did).
-- Server only (ServerStorage.UnitTest). Edit mode: it reads the place's own scripts, nothing is changed.
-- Contract:
--   * every Script, LocalScript and ModuleScript under ReplicatedStorage.Shared, ServerScriptService.Server,
--     ServerStorage.UnitTest, ServerStorage.SDTools and StarterPlayerScripts.Client is shorter than 200,000 (its
--     Source in bytes, which is never less than its characters).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
}

local LIMIT = 200_000

return function(t: Context)
	local expect = t.expect

	t.test("every script of the code folders is under the 200,000-character Source limit", function()
		local ServerStorage = game:GetService("ServerStorage")
		local roots: { Instance? } = {
			game:GetService("ReplicatedStorage"):FindFirstChild("Shared"),
			game:GetService("ServerScriptService"):FindFirstChild("Server"),
			ServerStorage:FindFirstChild("UnitTest"),
			ServerStorage:FindFirstChild("SDTools"),
			game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("Client"),
		}
		local over: { string } = {}
		local seen = 0
		for _, root in roots do
			if root ~= nil then
				local list = root:GetDescendants()
				table.insert(list, root)
				for _, script in list do
					if script:IsA("LuaSourceContainer") then
						seen += 1
						local size = #(script :: any).Source
						if size >= LIMIT then
							table.insert(over, `{script:GetFullName()} ({size})`)
						end
					end
				end
			end
		end
		expect.truthy(seen > 100) -- the folders were found
		expect.equal(table.concat(over, ", "), "")
	end)
end
