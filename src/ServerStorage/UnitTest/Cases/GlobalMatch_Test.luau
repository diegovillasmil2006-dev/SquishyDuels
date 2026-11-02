--!strict
-- GlobalMatch_Test: ServerScriptService.Server.Logic.GlobalMatch (the queue shared by every server, 2026-11-01).
-- Contract: arrival order; 1v1 pairs and a lone player waits; Team / Free for All start full at once, else everyone
-- once the oldest waited gatherSeconds.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local GlobalMatch = t.requireServer("Logic/GlobalMatch")
	local expect = t.expect

	local function ids(group: { any }): { number }
		local out = {}
		for _, ticket in group do
			table.insert(out, ticket.u)
		end
		return out
	end

	t.test("1v1 pairs in arrival order and a lone player keeps waiting", function()
		local tickets = {
			{ u = 3, at = 102, h = "b" },
			{ u = 1, at = 100, h = "a" },
			{ u = 2, at = 101, h = "a" },
		}
		local groups = GlobalMatch.groups(tickets, 1000, 2, 10)
		expect.equal(#groups, 1)
		expect.deepEqual(ids(groups[1]), { 1, 2 })
		expect.equal(#GlobalMatch.groups({ { u = 9, at = 0, h = "a" } }, 1000, 2, 10), 0)
	end)

	t.test("Free for All starts full at once, the rest waits for the gather", function()
		local tickets = {}
		for i = 1, 13 do
			table.insert(tickets, { u = i, at = 100 + i, h = "x" })
		end
		local groups = GlobalMatch.groups(tickets, 105, 12, 10)
		expect.equal(#groups, 1)
		expect.equal(#groups[1], 12)
		local later = GlobalMatch.groups(tickets, 113 + 10, 12, 10)
		expect.equal(#later, 2)
		expect.deepEqual(ids(later[2]), { 13 })
	end)

	t.test("a few Team players start together once the oldest waited the gather", function()
		local tickets = { { u = 7, at = 50, h = "a" }, { u = 4, at = 55, h = "b" } }
		expect.equal(#GlobalMatch.groups(tickets, 59, 12, 10), 0)
		local groups = GlobalMatch.groups(tickets, 60, 12, 10)
		expect.equal(#groups, 1)
		expect.deepEqual(ids(groups[1]), { 7, 4 })
	end)
end
