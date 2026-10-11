--!strict
-- ReceiptLogic_Test: unit tests for ServerScriptService.Server.Logic.ReceiptLogic. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §3.10, §3.4, §13.2 Part 7 L1): decide follows the §3.10 order (unknown product -> no player -> not
-- ready -> already in receipts: pending -> awaitSave (the pending-receipt save path), saved -> alreadyGranted ->
-- grant); it never reads CurrencySpent (a 0-Robux AdReward / CommerceProduct receipt is granted like any other);
-- entry() builds the receipts row {id = PurchaseId, product = ProductId, coins, at}. The bundle here is a test fixture
-- (ProductId 0); no product id is ever configured (§3.10 "Studio receipt test", §6.11).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireServer: (path: string) -> any,
}

local NOW = 1_790_000_000
local PURCHASE_ID = "purchase-1"
-- A test fixture bundle, never part of Config.Monetization (whose productIds all stay nil).
local FIXTURE_BUNDLE = { key = "coins_fixture", nameKey = "bundle.handful", productId = 0, coins = 1000, onSale = true }

return function(t: Context)
	local ReceiptLogic = t.requireServer("Logic/ReceiptLogic")
	local expect = t.expect

	local function info(purchaseId: string?, currencySpent: number?): any
		return { PurchaseId = purchaseId or PURCHASE_ID, ProductId = 0, PlayerId = 42, CurrencySpent = currencySpent }
	end

	local function ready(): any
		return { bundle = FIXTURE_BUNDLE, playerPresent = true, status = "ready" }
	end

	local function profile(receipts: { any }?): any
		return { receipts = receipts or {} }
	end

	local function action(state: any, prof: any, pending: any, receipt: any): string
		return ReceiptLogic.decide(state, prof, pending, receipt).action
	end

	t.test("an unknown product is unknownProduct, before every other check", function()
		local state = { bundle = nil, playerPresent = false, status = "loading" }
		expect.deepEqual(ReceiptLogic.decide(state, nil, nil, info()), { action = "unknownProduct" })
	end)

	t.test("a buyer who is not in this server is noPlayer", function()
		local state = { bundle = FIXTURE_BUNDLE, playerPresent = false, status = nil }
		expect.equal(action(state, nil, nil, info()), "noPlayer")
	end)

	t.test("no profile, or a profile that is not ready, is notReady", function()
		expect.equal(action(ready(), nil, {}, info()), "notReady")
		for _, status in { "loading", "offline", "readonly", "releasing" } do
			local state = ready()
			state.status = status
			expect.equal(action(state, profile(), {}, info()), "notReady")
		end
	end)

	t.test("a new purchase on a ready profile is grant", function()
		expect.deepEqual(ReceiptLogic.decide(ready(), profile(), {}, info()), { action = "grant" })
		-- Other receipts and other pending ids don't matter.
		local others = profile({ { id = "older", product = 0, coins = 1000, at = NOW } })
		expect.equal(action(ready(), others, { older = true }, info()), "grant")
	end)

	t.test("a purchase already recorded and saved is alreadyGranted", function()
		local saved = profile({ { id = PURCHASE_ID, product = 0, coins = 1000, at = NOW } })
		expect.equal(action(ready(), saved, {}, info()), "alreadyGranted")
		expect.equal(action(ready(), saved, nil, info()), "alreadyGranted")
	end)

	t.test("the pending-receipt save path: recorded but not yet saved is awaitSave", function()
		-- §3.10: the grant is in memory and its id is pending until a save succeeds; a retry must not grant again,
		-- it waits for the save (PurchaseGranted only after it succeeds).
		local granted = profile({ { id = PURCHASE_ID, product = 0, coins = 1000, at = NOW } })
		expect.equal(action(ready(), granted, { [PURCHASE_ID] = true }, info()), "awaitSave")
		-- Once the save cleared the pending id, the same receipt is simply already granted.
		expect.equal(action(ready(), granted, { [PURCHASE_ID] = false }, info()), "alreadyGranted")
	end)

	t.test("a grant followed by the same receipt never grants twice (grant -> awaitSave -> alreadyGranted)", function()
		local prof = profile()
		local pending: { [string]: boolean } = {}
		local receipt = info()
		expect.equal(action(ready(), prof, pending, receipt), "grant")
		table.insert(prof.receipts, ReceiptLogic.entry(receipt, FIXTURE_BUNDLE, NOW))
		pending[PURCHASE_ID] = true
		expect.equal(action(ready(), prof, pending, receipt), "awaitSave")
		pending[PURCHASE_ID] = nil
		expect.equal(action(ready(), prof, pending, receipt), "alreadyGranted")
	end)

	t.test("CurrencySpent is never assumed > 0: a 0-Robux receipt is granted like any other", function()
		expect.equal(action(ready(), profile(), {}, info(nil, 0)), "grant")
		expect.equal(action(ready(), profile(), {}, info(nil, nil)), "grant")
	end)

	t.test("entry builds the receipts row from the receipt, the bundle and now", function()
		expect.deepEqual(
			ReceiptLogic.entry(info(), FIXTURE_BUNDLE, NOW),
			{ id = PURCHASE_ID, product = 0, coins = 1000, at = NOW }
		)
	end)

	t.test("malformed receipts in the profile are skipped, not errors", function()
		local rows: { any } = { "garbage", { id = 5 }, { id = PURCHASE_ID, product = 0, coins = 1000, at = NOW } }
		local odd = profile(rows)
		expect.equal(action(ready(), odd, {}, info()), "alreadyGranted")
		expect.equal(action(ready(), { receipts = "nope" }, {}, info()), "grant")
	end)
end
