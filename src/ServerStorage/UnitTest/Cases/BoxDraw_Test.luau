--!strict
-- BoxDraw_Test: unit tests for ServerScriptService.Server.Logic.BoxDraw. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §6.4, §13.2 Part 7 L1): pick walks the ordered items accumulating weights and returns the first id
-- with r <= acc (edges: r = 1 is the first item, r = 10000 the last, each item's last r is still that item and the
-- next r the next item; r outside 1..sum or a fraction gives nil); draw takes r = rng:NextInteger(1, 10000) (checked
-- with a scripted FakeRng) and refuses a box whose weights do not sum to 10000; 1,000,000 seeded draws per paid box
-- (250,000 for the free Treat Box) land within ±0.5 percentage points of every weight's chance.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local DRAWS = 1_000_000
local TOLERANCE_POINTS = 0.5 -- percentage points (§13.2: "within ±0.5% of weights")
local SEED = 20261007

return function(t: Context)
	local BoxDraw = t.requireServer("Logic/BoxDraw")
	local Boxes = t.requireShared("Boxes")
	local FakeRng = t.requireFake("FakeRng")
	local expect = t.expect

	t.test("pick: r = 1 is the first item and r = 10000 the last", function()
		for _, box in Boxes.list() do
			expect.equal(BoxDraw.pick(box.items, 1), box.items[1].id)
			expect.equal(BoxDraw.pick(box.items, Boxes.WeightTotal), box.items[#box.items].id)
		end
	end)

	t.test("pick: each item owns exactly its cumulative range", function()
		local items = Boxes.get("snack").items
		local acc = 0
		for index, entry in items do
			local first = acc + 1
			acc += entry.weight
			expect.equal(BoxDraw.pick(items, first), entry.id)
			expect.equal(BoxDraw.pick(items, acc), entry.id)
			if index < #items then
				expect.equal(BoxDraw.pick(items, acc + 1), items[index + 1].id)
			end
		end
		-- Soft (pens3 phase 5, ECONOMY_V3:159): toast 1..1900, banana ..3800, boba_bear ..5700, pancake_pup ..7600,
		-- butter ..8400, chocolate ..9200, mochi_fox ..9600, strawberry_frog ..10000.
		expect.equal(BoxDraw.pick(items, 1900), "toast")
		expect.equal(BoxDraw.pick(items, 1901), "banana")
		expect.equal(BoxDraw.pick(items, 7600), "pancake_pup")
		expect.equal(BoxDraw.pick(items, 7601), "butter")
		expect.equal(BoxDraw.pick(items, 9600), "mochi_fox")
		expect.equal(BoxDraw.pick(items, 9601), "strawberry_frog")
	end)

	t.test("pick: r outside 1..sum, a fraction or NaN gives nil", function()
		local items = Boxes.get("sweet").items
		expect.equal(BoxDraw.pick(items, 0), nil)
		expect.equal(BoxDraw.pick(items, -1), nil)
		expect.equal(BoxDraw.pick(items, Boxes.WeightTotal + 1), nil)
		expect.equal(BoxDraw.pick(items, 1.5), nil)
		expect.equal(BoxDraw.pick(items, 0 / 0), nil)
		expect.equal(BoxDraw.pick({}, 1), nil)
	end)

	t.test("draw asks the rng for NextInteger(1, 10000) once and returns the picked id", function()
		local box = Boxes.get("sweet")
		local low = FakeRng.new({ 1 })
		expect.equal(BoxDraw.draw(box, low), "bird") -- pens3 phase 5: the Sweet Box holds only Epics and Dragon
		expect.equal(FakeRng.calls(low), 1)
		expect.equal(BoxDraw.draw(box, FakeRng.new({ Boxes.WeightTotal })), "dragon")
		-- Sweet (pens3 phase 5): 9,997-10,000 is Dragon (0.04%); cupcake_axolotl ends at 9996.
		expect.equal(BoxDraw.draw(box, FakeRng.new({ 9996 })), "cupcake_axolotl")
		expect.equal(BoxDraw.draw(box, FakeRng.new({ 9997 })), "dragon")
		-- The scripted rng refuses values outside the requested range, so 1..10000 is what draw asked for.
		expect.throws(function()
			BoxDraw.draw(box, FakeRng.new({ Boxes.WeightTotal + 1 }))
		end)
	end)

	t.test("isValid accepts the shipped boxes; draw refuses a box that does not sum to 10000", function()
		for _, box in Boxes.list() do
			expect.truthy(BoxDraw.isValid(box))
		end
		local short = {
			id = "short",
			nameKey = "box.snack.name",
			paid = true,
			cost = 1,
			items = { { id = "toast", weight = 9999 } },
		}
		expect.falsy(BoxDraw.isValid(short :: any))
		expect.falsy(BoxDraw.isValid({ id = "empty", items = {} } :: any))
		expect.falsy(
			BoxDraw.isValid(
				{ id = "zero", items = { { id = "toast", weight = 0 }, { id = "banana", weight = 10000 } } } :: any
			)
		)
		expect.throws(function()
			BoxDraw.draw(short :: any, FakeRng.new({ 1 }))
		end, "WeightTotal")
	end)

	t.test("1,000,000 seeded draws per paid box land within ±0.5 points of every weight", function()
		for _, box in Boxes.list() do
			-- The paid boxes' odds are the published disclosure (§6.10): 1,000,000 draws each. The free Treat Box gets
			-- a quarter of that (still about 5 standard deviations inside the band) to keep the case short.
			local draws = if box.paid then DRAWS else DRAWS // 4
			local rng = Random.new(SEED)
			local counts: { [string]: number } = {}
			for _ = 1, draws do
				local id = BoxDraw.draw(box, rng)
				counts[id] = (counts[id] or 0) + 1
			end
			local seen = 0
			for _, entry in box.items do
				local share = (counts[entry.id] or 0) / draws * 100
				local expected = entry.weight / 100
				if math.abs(share - expected) > TOLERANCE_POINTS then
					error(`{box.id}/{entry.id}: {share}% drawn, {expected}% expected`)
				end
				seen += counts[entry.id] or 0
			end
			expect.equal(seen, draws) -- nothing outside the box's items
		end
	end)

	t.test("the seeded FakeRng draws are the same on every run", function()
		local box = Boxes.get("snack")
		local first, second = {}, {}
		local a, b = FakeRng.new(SEED), FakeRng.new(SEED)
		for _ = 1, 50 do
			table.insert(first, BoxDraw.draw(box, a))
			table.insert(second, BoxDraw.draw(box, b))
		end
		expect.deepEqual(first, second)
	end)
end
