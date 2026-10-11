--!strict
-- PowerBudget_Test: unit tests for ServerScriptService.Server.Logic.PowerBudget. Server only
-- (ServerStorage.UnitTest).
-- Contract (DESIGN §5.8): with D = 40, V = 16 and the Kitty Bread baseline (95, 1.0, 1.00, 0.18),
-- Ps = 16·40·(1/95 − 1/speed)/0.4, Pr = (radius − 1.0)/0.4, Pw = 16·(0.18 − windup)/0.4, Pc = (1.00/cooldown − 1)/0.05,
-- Σ = Ps + Pr + Pw + Pc; flight(40) = 40/speed; slack(40) = (windup + 40/speed − 0.25)·16 − (radius + 1.3).
-- The §5.8 table reproduces within 0.01. Rules: no ability → |Σ| ≤ 0.5; with an ultimate → |Σ + ultimateCost| ≤ 0.5
-- (Dragon Rush costs 2.0); every throw stat inside its band (speed 85–115, radius 0.8–1.4, cooldown 0.9–1.2,
-- windup 0.15–0.22, gravity 20–50). Every catalog squishy passes. check() never raises on a malformed def.
-- Every call passes the Config under test (`cfg`), so the module's own live Config is never what is tested.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	Shared: Instance?,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

type Row = {
	id: string,
	speed: number,
	radius: number,
	cooldown: number,
	windup: number,
	Ps: number,
	Pr: number,
	Pw: number,
	Pc: number,
	sum: number,
	ult: number,
	net: number,
	flight: number,
	slack: number,
}

-- DESIGN §5.8 table, with each squishy's throw stats from §4.2 (gravity costs 0 points).
-- stylua: ignore
local TABLE: { Row } = {
	{ id = "kitty_bread", speed = 95, radius = 1.0, cooldown = 1.00, windup = 0.18, Ps = 0, Pr = 0, Pw = 0, Pc = 0, sum = 0.00, ult = 0, net = 0.00, flight = 0.421, slack = 3.32 },
	{ id = "toast", speed = 105, radius = 0.8, cooldown = 1.05, windup = 0.18, Ps = 1.60, Pr = -0.50, Pw = 0, Pc = -0.95, sum = 0.15, ult = 0, net = 0.15, flight = 0.381, slack = 2.88 },
	{ id = "banana", speed = 88, radius = 1.2, cooldown = 0.95, windup = 0.18, Ps = -1.34, Pr = 0.50, Pw = 0, Pc = 1.05, sum = 0.21, ult = 0, net = 0.21, flight = 0.455, slack = 3.65 },
	{ id = "butter", speed = 95, radius = 0.9, cooldown = 1.05, windup = 0.15, Ps = 0, Pr = -0.25, Pw = 1.20, Pc = -0.95, sum = 0.00, ult = 0, net = 0.00, flight = 0.421, slack = 2.94 },
	{ id = "chocolate", speed = 90, radius = 1.4, cooldown = 1.00, windup = 0.18, Ps = -0.94, Pr = 1.00, Pw = 0, Pc = 0, sum = 0.06, ult = 0, net = 0.06, flight = 0.444, slack = 3.29 },
	{ id = "bird", speed = 110, radius = 0.9, cooldown = 1.10, windup = 0.18, Ps = 2.30, Pr = -0.25, Pw = 0, Pc = -1.82, sum = 0.23, ult = 0, net = 0.23, flight = 0.364, slack = 2.50 },
	{ id = "donut", speed = 92, radius = 1.3, cooldown = 1.00, windup = 0.19, Ps = -0.55, Pr = 0.75, Pw = -0.40, Pc = 0, sum = -0.20, ult = 0, net = -0.20, flight = 0.435, slack = 3.40 },
	{ id = "dragon", speed = 92, radius = 1.0, cooldown = 1.05, windup = 0.19, Ps = -0.55, Pr = 0, Pw = -0.40, Pc = -0.95, sum = -1.90, ult = 2.00, net = 0.10, flight = 0.435, slack = 3.70 },
	-- Spec 2026-10-09 §3.3: each new squishy's throw copies a same-rarity sibling's, so it scores that sibling's row.
	{ id = "boba_bear", speed = 95, radius = 1.0, cooldown = 1.00, windup = 0.18, Ps = 0, Pr = 0, Pw = 0, Pc = 0, sum = 0.00, ult = 0, net = 0.00, flight = 0.421, slack = 3.32 },
	{ id = "pancake_pup", speed = 105, radius = 0.8, cooldown = 1.05, windup = 0.18, Ps = 1.60, Pr = -0.50, Pw = 0, Pc = -0.95, sum = 0.15, ult = 0, net = 0.15, flight = 0.381, slack = 2.88 },
	{ id = "mochi_fox", speed = 95, radius = 0.9, cooldown = 1.05, windup = 0.15, Ps = 0, Pr = -0.25, Pw = 1.20, Pc = -0.95, sum = 0.00, ult = 0, net = 0.00, flight = 0.421, slack = 2.94 },
	{ id = "strawberry_frog", speed = 90, radius = 1.4, cooldown = 1.00, windup = 0.18, Ps = -0.94, Pr = 1.00, Pw = 0, Pc = 0, sum = 0.06, ult = 0, net = 0.06, flight = 0.444, slack = 3.29 },
	{ id = "cloud_bunny", speed = 110, radius = 0.9, cooldown = 1.10, windup = 0.18, Ps = 2.30, Pr = -0.25, Pw = 0, Pc = -1.82, sum = 0.23, ult = 0, net = 0.23, flight = 0.364, slack = 2.50 },
	{ id = "cupcake_axolotl", speed = 92, radius = 1.3, cooldown = 1.00, windup = 0.19, Ps = -0.55, Pr = 0.75, Pw = -0.40, Pc = 0, sum = -0.20, ult = 0, net = -0.20, flight = 0.435, slack = 3.40 },
}

local ULTIMATE: { [string]: string } = { dragon = "dragon_rush" }

local TOLERANCE = 0.01 -- the table is rounded to 2 decimals
local FLIGHT_TOLERANCE = 0.001 -- flight times are rounded to 3 decimals

-- DESIGN §5.8 bands.
local BANDS: { [string]: { number } } = {
	speed = { 85, 115 },
	radius = { 0.8, 1.4 },
	cooldown = { 0.9, 1.2 },
	windup = { 0.15, 0.22 },
	gravity = { 20, 50 },
}

-- A catalog-shaped def around a throw; budget-neutral baseline stats unless overridden.
local function makeDef(overrides: { [string]: any }?, ultimateId: string?): any
	local throw = { speed = 95, gravity = 35, radius = 1.0, cooldown = 1.0, windup = 0.18 }
	if overrides then
		for stat, value in overrides do
			(throw :: any)[stat] = value
		end
	end
	return { id = "test_squishy", rarity = "Common", throw = throw, ultimateId = ultimateId }
end

local function mentions(problems: { string }, ...: string): boolean
	local needles = { ... }
	for _, problem in problems do
		local all = true
		for _, needle in needles do
			if string.find(problem, needle, 1, true) == nil then
				all = false
				break
			end
		end
		if all then
			return true
		end
	end
	return false
end

return function(t: Context)
	local PowerBudget = t.requireServer("Logic/PowerBudget")
	local Config = t.requireShared("Config")
	local Catalog = t.requireShared("Catalog")
	local expect = t.expect

	local function nearOrFail(label: string, actual: number, wanted: number, tolerance: number)
		if not (math.abs(actual - wanted) <= tolerance) then
			error(
				string.format("%s = %.4f, DESIGN §5.8 says %.2f (tolerance %g)", label, actual, wanted, tolerance),
				2
			)
		end
	end

	-- Formulas against the §5.8 table ---------------------------------------------------------------------------

	t.test("Kitty Bread, the baseline, scores 0 on every term", function()
		local points = PowerBudget.points({ speed = 95, radius = 1.0, cooldown = 1.0, windup = 0.18 }, Config)
		for _, term in { "Ps", "Pr", "Pw", "Pc", "sum" } do
			expect.near(points[term], 0, 1e-9)
		end
	end)

	t.test("the §5.8 table reproduces within 0.01", function()
		for _, row in TABLE do
			local throw = { speed = row.speed, radius = row.radius, cooldown = row.cooldown, windup = row.windup }
			local points = PowerBudget.points(throw, Config)
			for _, term in { "Ps", "Pr", "Pw", "Pc", "sum" } do
				nearOrFail(`{row.id} {term}`, points[term], (row :: any)[term], TOLERANCE)
			end
			local ult = PowerBudget.ultimateCost(ULTIMATE[row.id], Config)
			nearOrFail(`{row.id} ult`, ult, row.ult, TOLERANCE)
			nearOrFail(`{row.id} net`, points.sum + ult, row.net, TOLERANCE)
			nearOrFail(
				`{row.id} flight 40`,
				PowerBudget.flightTime(row.speed, nil, Config),
				row.flight,
				FLIGHT_TOLERANCE
			)
			nearOrFail(`{row.id} slack 40`, PowerBudget.dodgeSlack(throw, nil, Config), row.slack, TOLERANCE)
		end
	end)

	t.test("flight time and dodge slack take an explicit distance", function()
		local throw = { speed = 95, radius = 1.0, cooldown = 1.0, windup = 0.18 }
		expect.near(PowerBudget.flightTime(95, 19, Config), 0.2, 1e-9)
		-- At the 16-stud minimum distance the baseline slack is negative (only pre-emptive movement dodges).
		expect.truthy(PowerBudget.dodgeSlack(throw, 16, Config) < 0)
		expect.near(PowerBudget.dodgeSlack(throw, 16, Config), (0.18 + 16 / 95 - 0.25) * 16 - 2.3, 1e-9)
	end)

	t.test("every catalog squishy scores its §5.8 row", function()
		local rows: { [string]: Row } = {}
		for _, row in TABLE do
			rows[row.id] = row
		end
		local defs = Catalog.list()
		expect.equal(#defs, #TABLE)
		for _, def in defs do
			local row = rows[def.id]
			assert(row ~= nil, def.id .. " has no §5.8 row")
			local points = PowerBudget.points(def.throw, Config)
			nearOrFail(`{def.id} sum`, points.sum, row.sum, TOLERANCE)
			local cost = PowerBudget.ultimateCost(def.ultimateId, Config)
			nearOrFail(`{def.id} net`, points.sum + cost, row.net, TOLERANCE)
		end
	end)

	-- Rules --------------------------------------------------------------------------------------------------------

	t.test("every catalog squishy passes the budget rules", function()
		for _, def in Catalog.list() do
			local ok, problems = PowerBudget.check(def, Config)
			if not ok then
				error(def.id .. ": " .. table.concat(problems, "; "))
			end
			expect.equal(#problems, 0)
		end
	end)

	t.test("ultimateCost: Dragon Rush costs 2.0 (its Config budgetCost), no ultimate 0, unknown nil", function()
		expect.near(PowerBudget.ultimateCost("dragon_rush", Config), 2.0, 1e-9)
		expect.equal(PowerBudget.ultimateCost("dragon_rush", Config), Config.Abilities.dragon_rush.budgetCost)
		expect.equal(PowerBudget.ultimateCost(nil, Config), 0)
		expect.equal(PowerBudget.ultimateCost("laser_eyes", Config), nil)
	end)

	t.test("no ability: |Σ| up to 0.5 passes, above fails", function()
		-- Pc = (1/cooldown − 1)/0.05, so cooldown = 1/(1 + 0.05·Σ) gives exactly Σ.
		expect.truthy((PowerBudget.check(makeDef({ cooldown = 1 / (1 + 0.05 * 0.45) }), Config)))
		expect.truthy((PowerBudget.check(makeDef({ cooldown = 1 / (1 - 0.05 * 0.45) }), Config)))
		local ok, problems = PowerBudget.check(makeDef({ cooldown = 1 / (1 + 0.05 * 0.55) }), Config)
		expect.falsy(ok)
		expect.truthy(mentions(problems, "power budget"))
		local okLow = PowerBudget.check(makeDef({ cooldown = 1 / (1 - 0.05 * 0.55) }), Config)
		expect.falsy(okLow)
	end)

	t.test("with an ultimate its cost is added: Dragon's throw passes with Dragon Rush, fails without", function()
		local dragonThrow = { speed = 92, gravity = 35, radius = 1.0, cooldown = 1.05, windup = 0.19 }
		expect.truthy((PowerBudget.check(makeDef(dragonThrow, "dragon_rush"), Config)))
		local ok, problems = PowerBudget.check(makeDef(dragonThrow, nil), Config)
		expect.falsy(ok)
		expect.truthy(mentions(problems, "power budget"))
		-- A budget-neutral throw plus Dragon Rush is +2.0: over.
		expect.falsy((PowerBudget.check(makeDef(nil, "dragon_rush"), Config)))
	end)

	t.test("an unknown ultimate fails the check", function()
		local ok, problems = PowerBudget.check(makeDef(nil, "laser_eyes"), Config)
		expect.falsy(ok)
		expect.truthy(mentions(problems, "laser_eyes"))
	end)

	t.test("bands come from Config.Combat and match DESIGN §5.8", function()
		for stat, band in BANDS do
			expect.equal(Config.Combat.Bands[stat].min, band[1])
			expect.equal(Config.Combat.Bands[stat].max, band[2])
		end
	end)

	t.test("a stat on its band edge passes the band rule; just outside is reported by name", function()
		for stat, band in BANDS do
			for _, edge in band do
				local _, problems = PowerBudget.check(makeDef({ [stat] = edge }), Config)
				if mentions(problems, `throw.{stat}`) then
					error(
						string.format("%s = %g (band edge) was reported: %s", stat, edge, table.concat(problems, "; "))
					)
				end
			end
			for _, outside in { band[1] - 0.01, band[2] + 0.01 } do
				local ok, problems = PowerBudget.check(makeDef({ [stat] = outside }), Config)
				expect.falsy(ok)
				if not mentions(problems, `throw.{stat}`, "band") then
					error(
						string.format(
							"%s = %g (outside the band) not reported: %s",
							stat,
							outside,
							table.concat(problems, "; ")
						)
					)
				end
			end
		end
	end)

	t.test("arc costs 0 points: gravity changes nothing in Σ", function()
		local low = PowerBudget.points(makeDef({ gravity = 20 }).throw, Config)
		local high = PowerBudget.points(makeDef({ gravity = 50 }).throw, Config)
		expect.near(low.sum, high.sum, 1e-12)
	end)

	t.test("malformed defs are reported, never raised", function()
		local cases: { any } = {
			{ id = "no_throw", rarity = "Common" },
			makeDef({ speed = 0 / 0 }),
			makeDef({ radius = "1" }),
			makeDef({ cooldown = 0 }),
			makeDef({ windup = math.huge }),
			{},
		}
		for index, def in cases do
			local okCall, ok, problems = pcall(PowerBudget.check, def, Config)
			if not okCall then
				error(string.format("case %d raised: %s", index, tostring(ok)))
			end
			expect.falsy(ok)
			expect.truthy(#problems > 0)
		end
	end)
end
