--!strict
-- CodeService_Test: ServerScriptService.Server.Services.CodeService (big job item 4, 2026-11-10: the redeem codes) with
-- injected fakes (a fake data port, a fake clock, a Coin recorder, a live-codes value; the player is a plain table).
-- Edit mode: init() is never called.
-- Contract (LihFolk vault "Codes Redemption System End to End"):
--   * a code that is open pays its squeezes x the squeeze value of that moment with reason "code", once per account
--     (profile.gifts["code:<CODE>"], set before the Coins), and asks for a "soon" save; typing is forgiven;
--   * a used code answers code.used, pays nothing and is not a miss; a broken flag counts as used (never twice);
--   * a wrong, a badly typed and a closed code all answer code.invalid;
--   * missLimit misses inside missWindowSeconds lock redeeming (also of a good code) for lockSeconds: code.wait; the
--     lock outlives a rejoin;
--   * live codes work at once and a live 0 closes a built-in code;
--   * a profile that is not READY answers data.notReady and nothing changes.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

-- The squeeze value of the test profile's pen: Kitty Bread (10) + Butter (20) a second.
local VALUE = 30

return function(t: Context)
	local expect = t.expect
	local CodeService = t.requireServer("Services/CodeService")
	local Codes = t.requireServer("Logic/Codes")
	local Bonus = t.requireShared("Config/Bonus")
	local FakeClock = t.requireFake("FakeClock")

	local RULES = Bonus.Codes
	local WELCOME = Codes.BUILT_IN.WELCOME

	local function fresh(): any
		local w: any = {
			clock = FakeClock.new(1000),
			player = { UserId = 41 },
			status = "ready",
			live = nil,
			grants = {},
			saves = {},
			profile = {
				coins = 0,
				gifts = { frog = false },
				pen = {
					spots = 3,
					nextId = 3,
					items = {
						{ id = 1, kind = "kitty_bread", form = 0, level = 1, coat = 0, slot = 1, locked = false },
						{ id = 2, kind = "butter", form = 0, level = 1, coat = 0, slot = 2, locked = false },
					},
				},
			},
		}
		CodeService.useDeps({
			data = {
				getProfile = function(_player: any): any
					return w.profile
				end,
				status = function(_player: any): string
					return w.status
				end,
				persisted = function(_player: any): boolean
					return true
				end,
				savePending = function(_player: any): boolean
					return false
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
					if w.status ~= "ready" or w.closing then
						return false, "data.notReady"
					end
					return true, fn(w.profile)
				end,
				requestSave = function(_player: any, reason: string)
					table.insert(w.saves, reason)
				end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			grantCoins = function(_player: any, amount: number, reason: string): (number, string?)
				w.profile.coins += amount
				table.insert(w.grants, { amount = amount, reason = reason })
				return amount, nil
			end,
			liveCodes = function(): any
				return w.live
			end,
			clock = w.clock.now,
		})
		function w.redeem(typed: any): any
			return CodeService.redeem(w.player, typed)
		end
		return w
	end

	local function finish()
		CodeService.useDeps(nil)
	end

	t.test("an open code pays its squeezes x the squeeze value once, with 'code', and saves soon", function()
		local w = fresh()
		local reply = w.redeem("WELCOME")
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { coins = WELCOME * VALUE })
		expect.equal(w.profile.gifts["code:WELCOME"], true)
		expect.equal(w.profile.gifts.frog, false) -- the other gifts are untouched
		expect.deepEqual(w.grants, { { amount = WELCOME * VALUE, reason = "code" } })
		expect.deepEqual(w.saves, { "soon" })
		finish()
	end)

	t.test("typing is forgiven: small letters, spaces and dashes", function()
		local w = fresh()
		expect.equal(w.redeem("  wel-come ").ok, true)
		expect.equal(w.profile.gifts["code:WELCOME"], true)
		finish()
	end)

	t.test("a used code answers code.used, pays nothing more and never counts as a wrong guess", function()
		local w = fresh()
		expect.equal(w.redeem("WELCOME").ok, true)
		for _ = 1, RULES.missLimit + 2 do
			local again = w.redeem("welcome")
			expect.equal(again.ok, false)
			expect.equal(again.reason, "code.used")
		end
		expect.equal(#w.grants, 1)
		expect.equal(#w.saves, 1)
		expect.equal(w.redeem("DIJAY").ok, true) -- not locked: another code still works
		finish()
	end)

	t.test("a broken flag counts as used: never twice", function()
		local w = fresh()
		w.profile.gifts["code:WELCOME"] = "yes"
		expect.equal(w.redeem("WELCOME").reason, "code.used")
		expect.equal(#w.grants, 0)
		finish()
	end)

	t.test("a wrong, a badly typed and a closed code all answer code.invalid and change nothing", function()
		local w = fresh()
		w.live = { WELCOME = 0 } -- closed from the Configs page
		for _, typed in { "NOPE123", "ab", "WELCOME" } :: { any } do
			local reply = w.redeem(typed)
			expect.equal(reply.ok, false)
			expect.equal(reply.reason, "code.invalid")
		end
		expect.equal(w.redeem(42).reason, "code.invalid") -- not a text (NetService stops it earlier in a live game)
		expect.equal(#w.grants, 0)
		expect.equal(#w.saves, 0)
		expect.equal(w.profile.gifts["code:WELCOME"], nil)
		finish()
	end)

	t.test("missLimit wrong codes lock redeeming for lockSeconds, a good code too; then it opens again", function()
		local w = fresh()
		for _ = 1, RULES.missLimit do
			expect.equal(w.redeem("WRONG1").reason, "code.invalid")
		end
		expect.equal(w.redeem("WELCOME").reason, "code.wait")
		expect.equal(w.redeem("WRONG1").reason, "code.wait")
		w.clock.advance(RULES.lockSeconds - 1)
		expect.equal(w.redeem("WELCOME").reason, "code.wait")
		w.clock.advance(1.1)
		expect.equal(w.redeem("WELCOME").ok, true)
		finish()
	end)

	t.test("misses older than the window no longer count", function()
		local w = fresh()
		for _ = 1, RULES.missLimit - 1 do
			w.redeem("WRONG1")
		end
		w.clock.advance(RULES.missWindowSeconds + 1)
		expect.equal(w.redeem("WRONG1").reason, "code.invalid") -- the first of a new window
		expect.equal(w.redeem("WELCOME").ok, true)
		finish()
	end)

	t.test("a running lock outlives a rejoin; another player is never locked by it", function()
		local w = fresh()
		for _ = 1, RULES.missLimit do
			w.redeem("WRONG1")
		end
		CodeService.playerRemoving(w.player)
		expect.equal(w.redeem("WELCOME").reason, "code.wait")
		expect.equal(CodeService.redeem({ UserId = 42 }, "WELCOME").ok, true)
		finish()
	end)

	t.test("live codes work at once; a name the list skipped is no code", function()
		local w = fresh()
		w.live = { party = 300, BIG = RULES.maxSqueezes + 1 }
		local reply = w.redeem("Party")
		expect.equal(reply.ok, true)
		expect.equal(reply.data.coins, 300 * VALUE)
		expect.equal(w.profile.gifts["code:PARTY"], true)
		expect.equal(w.redeem("BIG").reason, "code.invalid")
		w.live = "PARTY=300" -- a config of the wrong type: no live codes, the built-in ones still work
		expect.equal(w.redeem("DIJAY").ok, true)
		finish()
	end)

	t.test("not ready is data.notReady, also when the session stops taking changes; nothing changes", function()
		local w = fresh()
		w.status = "loading"
		expect.equal(w.redeem("WELCOME").reason, "data.notReady")
		w.status = "ready"
		w.closing = true -- the final save started: mutate refuses
		expect.equal(w.redeem("WELCOME").reason, "data.notReady")
		expect.equal(#w.grants, 0)
		expect.equal(w.profile.gifts["code:WELCOME"], nil)
		w.closing = false
		expect.equal(w.redeem("WELCOME").ok, true) -- neither refusal was a miss or a use
		finish()
	end)
end
