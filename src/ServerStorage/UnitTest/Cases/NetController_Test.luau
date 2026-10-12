--!strict
-- NetController_Test: the pure parts of StarterPlayerScripts.Client.Controllers.NetController. Server only
-- (ServerStorage.UnitTest). Edit mode: connectAsync() is never called, so nothing can be sent.
-- Contract (DESIGN §2.7, §2.8, §5.6 #2, §12 #2):
--   * a C->S call is checked against Remotes.SPEC before sending: exact argument count, each argument's shape
--     (integers, finite numbers, server times below Net.maxAbsServerTime, Coin amounts up to Economy.maxCoins,
--     finite Vector3s, id patterns);
--   * RemoteFunction replies are normalized to {ok, v, data | reason}; anything malformed is `error.generic`;
--   * seq numbers count up by one per remote, independently for ThrowRequest and UltimateRequest;
--   * before connecting nothing is sent: fire() returns false and invokeAsync() returns `error.connect` at once;
--     a call of the wrong kind or with bad arguments is refused locally (`net.invalid`).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local NetController = t.requireClient("Controllers/NetController")
	local Config = t.requireShared("Config")
	local Remotes = t.requireShared("Remotes")

	local function check(name: string, ...: any): string?
		return NetController.checkArgs(name, { ... }, select("#", ...))
	end

	local AIM = Vector3.new(0, 0.2, -1).Unit
	local ORIGIN = Vector3.new(10, 3, -40)
	local NOW = 1.8e9

	t.test("ThrowRequest: valid arguments pass; each malformed argument is caught", function()
		expect.equal(check("ThrowRequest", 1, AIM, ORIGIN, NOW), nil)
		expect.truthy(check("ThrowRequest", 1.5, AIM, ORIGIN, NOW)) -- seq must be an integer
		expect.truthy(check("ThrowRequest", 1, Vector3.new(0 / 0, 0, 1), ORIGIN, NOW)) -- NaN aim
		expect.truthy(check("ThrowRequest", 1, AIM, Vector3.new(math.huge, 0, 0), NOW)) -- infinite origin
		expect.truthy(check("ThrowRequest", 1, AIM, ORIGIN, Config.Net.maxAbsServerTime)) -- beyond serverTime
		expect.truthy(check("ThrowRequest", 1, AIM, ORIGIN, "now")) -- wrong type
		expect.truthy(check("ThrowRequest", 1, AIM, ORIGIN)) -- missing argument
		expect.truthy(check("ThrowRequest", 1, AIM, ORIGIN, NOW, 5)) -- extra argument
		expect.truthy(check("ThrowRequest", 1, "aim", ORIGIN, NOW))
	end)

	t.test("ShopBuy: a 1.1T price is sent; a fraction, a negative or a price above maxCoins is refused", function()
		local guid = "0123abcd-4567-89ab-cdef-0123456789ab"
		expect.equal(check("ShopBuy", "dragon", 1_100_000_000_000, guid), nil) -- Dragon (spec 2026-10-12 §6)
		expect.truthy(check("ShopBuy", "dragon", 2.5, guid))
		expect.truthy(check("ShopBuy", "dragon", -1, guid))
		expect.truthy(check("ShopBuy", "dragon", Config.Economy.maxCoins + 2, guid))
	end)

	t.test("every C->S remote: the declared argument count, nothing more", function()
		expect.equal(check("QueueJoin"), nil)
		expect.truthy(check("QueueJoin", 1))
		expect.equal(check("QueueLeave"), nil)
		expect.equal(check("DuelForfeit"), nil)
		expect.equal(check("ReportIdle"), nil)
		expect.equal(check("UltimateRequest", 3, AIM, NOW), nil)
		expect.truthy(check("UltimateRequest", 3, AIM))
		expect.equal(check("EquipSquishy", "dragon"), nil)
		expect.truthy(check("EquipSquishy", "Dragon!"))
		expect.truthy(check("EquipSquishy", string.rep("a", 40)))
		expect.truthy(check("NoSuchRemote"))
		for _, name in Remotes.names("c2s") do
			local spec = Remotes.SPEC[name]
			local args = table.create(#spec.args + 1, true)
			if check(name, table.unpack(args, 1, #spec.args + 1)) == nil then
				error(`{name} accepted one argument too many`)
			end
		end
	end)

	t.test("RemoteFunction replies are normalized to the §2.7 Result shape", function()
		local ok = NetController.normalizeResult({ ok = true, v = 3, data = { position = 2 } })
		expect.equal(ok.ok, true)
		expect.equal(ok.v, 3)
		expect.equal(ok.data.position, 2)
		local refused = NetController.normalizeResult({ ok = false, v = 4, reason = "queue.cooldown" })
		expect.equal(refused.ok, false)
		expect.equal(refused.reason, "queue.cooldown")
		expect.equal(refused.v, 4)
		local charged = NetController.normalizeResult({ ok = false, v = 1, reason = "shop.owned", charged = false })
		expect.equal(charged.charged, false)
		expect.equal(NetController.normalizeResult({ ok = false }).reason, "error.generic")
		expect.equal(NetController.normalizeResult({ ok = false, reason = "" }).reason, "error.generic")
		expect.equal(NetController.normalizeResult("garbage").reason, "error.generic")
		expect.equal(NetController.normalizeResult({ v = 2 }).reason, "error.generic")
		expect.equal(NetController.normalizeResult({ ok = true, v = 0 / 0 }).v, 0)
	end)

	t.test("seq numbers count up by one, separately per remote", function()
		local first = NetController.nextSeq("ThrowRequest")
		local second = NetController.nextSeq("ThrowRequest")
		expect.equal(second, first + 1)
		local ult = NetController.nextSeq("UltimateRequest")
		local ultNext = NetController.nextSeq("UltimateRequest")
		expect.equal(ultNext, ult + 1)
		expect.equal(NetController.nextSeq("ThrowRequest"), second + 1)
		expect.truthy(first >= 1 and ult >= 1)
	end)

	t.test("before connecting nothing is sent; wrong kinds and bad arguments are refused locally", function()
		expect.equal(NetController.isConnected(), false)
		expect.equal(NetController.fire("QueueLeave"), false)
		local result = NetController.invokeAsync("QueueJoin")
		expect.equal(result.ok, false)
		expect.equal(result.reason, "error.connect")
		expect.equal(NetController.fire("QueueJoin"), false) -- a RemoteFunction, not an event
		expect.equal(NetController.invokeAsync("QueueLeave").reason, "net.invalid")
		expect.equal(NetController.invokeAsync("EquipSquishy", 5).reason, "net.invalid")
		expect.equal(NetController.throwRequest(AIM, ORIGIN, NOW), nil)
		expect.throws(function()
			NetController.on("QueueJoin", function() end)
		end, "not a server -> client remote")
		local connection = NetController.on("QueueStatus", function() end)
		connection:disconnect()
	end)
end
