--!strict
-- ValidateHighway_Test: unit tests for ReplicatedStorage.Shared.Config.ValidateHighway (the highway's distances, pens3
-- phase 12). Server only (ServerStorage.UnitTest). Pure: broken copies of Config.Economy.Highway.
-- Contract (Config/ValidateHighway header; work/pens3/PLAN.md "PHASE 12"; PR3:36): the shipped Config is valid and
-- holds the 7 biome starts 0 / 300 / 800 / 1,500 / 2,500 / 4,000 / 6,000 with the Golden Gates at 8,500 (so the
-- biomes are 300 / 500 / 700 / 1,000 / 1,500 / 2,000 / 2,500 long); a missing section is one problem; each broken
-- value is reported by name.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local validate = t.requireShared("Config/ValidateHighway")

	-- A Config-shaped copy with Economy.Highway changed.
	local function broken(changes: { [string]: any }): any
		local highway = table.clone(Config.Economy.Highway)
		for key, value in changes do
			highway[key] = value
		end
		return { Economy = { Highway = highway } }
	end

	local function mentions(problems: { string }, text: string): boolean
		for _, problem in problems do
			if string.find(problem, text, 1, true) then
				return true
			end
		end
		return false
	end

	t.test("the shipped Config is valid: 7 biomes from 0 to 6,000, the Golden Gates at 8,500 (PR3:36)", function()
		expect.deepEqual(validate(Config), {})
		local highway = Config.Economy.Highway
		expect.deepEqual(highway.starts, { 0, 300, 800, 1500, 2500, 4000, 6000 })
		expect.equal(highway.gatesAt, 8500)
		local lengths: { number } = {}
		for index, start in highway.starts do
			table.insert(lengths, (highway.starts[index + 1] or highway.gatesAt) - start)
		end
		expect.deepEqual(lengths, { 300, 500, 700, 1000, 1500, 2000, 2500 }) -- PLAN phase 13 (V4:76)
	end)

	t.test("a missing section is one problem", function()
		local problems = validate({ Economy = {} })
		expect.equal(#problems, 1)
		expect.truthy(mentions(problems, "Config.Economy.Highway is missing"))
		expect.equal(#validate(nil), 1)
	end)

	t.test("each broken value is reported by name", function()
		local cases: { { changes: { [string]: any }, field: string } } = {
			{ changes = { starts = {} }, field = "starts" },
			{ changes = { starts = "0" }, field = "starts" },
			{ changes = { starts = { 50, 300 } }, field = "starts[1]" }, -- the first biome starts at the gate
			{ changes = { starts = { 0, 300, 300 } }, field = "starts[3]" }, -- an empty biome
			{ changes = { starts = { 0, 800, 300 } }, field = "starts[3]" }, -- not rising
			{ changes = { starts = { 0, 300.5 } }, field = "starts[2]" },
			{ changes = { starts = { 0, 0 / 0 } }, field = "starts[2]" },
			{ changes = { gatesAt = 6000 }, field = "gatesAt" }, -- the last biome would be empty
			{ changes = { gatesAt = 8500.5 }, field = "gatesAt" },
			{ changes = { gatesAt = "8500" }, field = "gatesAt" },
			{ changes = { gatesAt = math.huge }, field = "gatesAt" },
		}
		for _, case in cases do
			local problems = validate(broken(case.changes))
			if not mentions(problems, case.field) then
				error(`expected a problem naming {case.field}, got: {table.concat(problems, "; ")}`)
			end
		end
	end)
end
