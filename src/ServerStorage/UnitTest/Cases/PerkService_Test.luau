--!strict
-- PerkService_Test: ServerScriptService.Server.Services.PerkService (big job item 4, 2026-11-10: the bonus for members
-- of the game's owner group) with injected fakes (FakePlayers, a fake data port, Roblox's two answers, a spawn that
-- keeps the calls until a case runs them, a clock, a toast and a Coin recorder). Edit mode: init() is never called.
-- Contract (LihFolk vault "Roblox Communities as Your On-Platform Hub"):
--   * a join asks Roblox once; a member's pen boost and SD_GroupBoost turn on; anyone else stays at 0; a call that
--     fails counts as not a member;
--   * the gift: once per account (profile.gifts.group, set first), giftSqueezes x the squeeze value with reason
--     "group", a "soon" save and the toast; only for a member whose profile is READY, so one that loads later gets it
--     then; a broken flag counts as given;
--   * GroupCheck: a member is never asked about again; anyone else is asked with the fresh call, at most once every
--     recheckSeconds (else net.rateLimited); a fresh call that fails answers error.generic;
--   * leaving forgets the player, also for an answer that comes back after they left.
-- Big job item 5 (Roblox Plus subscribers and the members Premium still has; vault "Subscriptions and Premium
-- Payouts"):
--   * a subscriber gets the Plus pen boost, SD_PlusBoost and the Plus gift once ("plus"); nobody else does;
--   * subscribing during the visit turns it on when Roblox says so; a subscription that ends turns the boost off; the
--     gift never comes twice;
--   * a read that fails changes nothing (a perk is never taken away by an error);
--   * the boosts of the group and of Plus add up; leaving stops following the subscription.

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
	local PerkService = t.requireServer("Services/PerkService")
	local Bonus = t.requireShared("Config/Bonus")
	local FakeClock = t.requireFake("FakeClock")
	local FakePlayer = t.requireFake("FakePlayer")

	local GROUP = Bonus.Group
	local PLUS = Bonus.Plus
	local PERCENT = math.floor(GROUP.penBoost * 100 + 0.5)
	local PLUS_PERCENT = math.floor(PLUS.penBoost * 100 + 0.5)
	local GIFT = GROUP.giftSqueezes * VALUE
	local PLUS_GIFT = PLUS.giftSqueezes * VALUE

	-- member[userId] = Roblox's answer on join; memberNow[userId] = its fresh answer; plus[userId] = the subscription
	-- ("error" = the call or the read fails). watching[userId] = the change handler while the player is followed.
	local function setup(): any
		local w: any = {
			clock = FakeClock.new(500),
			member = {},
			memberNow = {},
			plus = {},
			watching = {},
			asked = 0,
			askedNow = 0,
			calls = {},
			status = {},
			profiles = {},
			grants = {},
			saves = {},
			toasts = {},
		}
		local function profileOf(player: any): any
			local profile = w.profiles[player.UserId]
			if profile == nil then
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
				}
				w.profiles[player.UserId] = profile
			end
			return profile
		end
		w.profileOf = profileOf
		local function statusOf(player: any): string
			return w.status[player.UserId] or "ready"
		end
		local function answer(list: any, player: any): boolean
			local value = list[player.UserId]
			if value == "error" then
				error("web call failed")
			end
			return value == true
		end
		PerkService.useDeps({
			data = {
				getProfile = profileOf,
				status = statusOf,
				persisted = function(_player: any): boolean
					return true
				end,
				savePending = function(_player: any): boolean
					return false
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				mutate = function(player: any, fn: (profile: any) -> any): (boolean, any)
					if statusOf(player) ~= "ready" then
						return false, "data.notReady"
					end
					return true, fn(profileOf(player))
				end,
				requestSave = function(player: any, reason: string)
					table.insert(w.saves, { userId = player.UserId, reason = reason })
				end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			grantCoins = function(player: any, amount: number, reason: string): (number, string?)
				profileOf(player).coins += amount
				table.insert(w.grants, { userId = player.UserId, amount = amount, reason = reason })
				return amount, nil
			end,
			notify = function(player: any, code: string, args: any, kind: any)
				table.insert(w.toasts, { userId = player.UserId, code = code, args = args, kind = kind })
			end,
			isMember = function(player: any): boolean
				w.asked += 1
				return answer(w.member, player)
			end,
			isMemberNow = function(player: any): boolean
				w.askedNow += 1
				return answer(w.memberNow, player)
			end,
			isSubscriber = function(player: any): boolean
				return answer(w.plus, player)
			end,
			watchSubscriber = function(player: any, changed: () -> ()): () -> ()
				w.watching[player.UserId] = changed
				return function()
					w.watching[player.UserId] = nil
				end
			end,
			spawn = function(fn: (...any) -> ...any, ...: any)
				table.insert(w.calls, { fn = fn, args = table.pack(...) })
			end,
			clock = w.clock.now,
		})
		function w.join(userId: number): any
			local player = FakePlayer.new(userId)
			PerkService.playerAdded(player)
			return player
		end
		-- Roblox answers every question still in the air.
		function w.answer()
			local calls = w.calls
			w.calls = {}
			for _, call in calls do
				call.fn(table.unpack(call.args, 1, call.args.n))
			end
		end
		-- Roblox changes a player's subscription and tells the server.
		function w.setPlus(player: any, value: any)
			w.plus[player.UserId] = value
			local changed = w.watching[player.UserId]
			if changed then
				changed()
			end
		end
		function w.done()
			PerkService.useDeps(nil)
		end
		return w
	end

	t.test("a join asks Roblox once; only a member gets the pen boost and SD_GroupBoost", function()
		local w = setup()
		w.member[1] = true
		local one, two = w.join(1), w.join(2)
		expect.equal(one:GetAttribute("SD_GroupBoost"), 0) -- set on join, before any answer
		expect.equal(PerkService.penBoost(one), 0)
		w.answer()
		expect.equal(w.asked, 2)
		expect.equal(PerkService.penBoost(one), GROUP.penBoost)
		expect.equal(one:GetAttribute("SD_GroupBoost"), PERCENT)
		expect.equal(PerkService.penBoost(two), 0)
		expect.equal(two:GetAttribute("SD_GroupBoost"), 0)
		expect.equal(PerkService.penBoost({ UserId = 99 }), 0) -- someone who is not here
		w.done()
	end)

	t.test("a call that fails counts as not a member: no boost, no gift", function()
		local w = setup()
		w.member[3] = "error"
		local three = w.join(3)
		w.answer()
		expect.equal(PerkService.penBoost(three), 0)
		expect.equal(three:GetAttribute("SD_GroupBoost"), 0)
		expect.equal(#w.grants, 0)
		w.done()
	end)

	t.test("the gift: once per account, the squeezes' worth with 'group', a soon save and the toast", function()
		local w = setup()
		w.member[1] = true
		local one = w.join(1)
		w.answer()
		expect.deepEqual(w.grants, { { userId = 1, amount = GIFT, reason = "group" } })
		expect.equal(w.profileOf(one).gifts.group, true)
		expect.equal(w.profileOf(one).gifts.frog, false) -- the other gifts are untouched
		expect.deepEqual(w.saves, { { userId = 1, reason = "soon" } })
		expect.equal(#w.toasts, 1)
		expect.equal(w.toasts[1].code, "bonus.groupGift")
		expect.equal(w.toasts[1].kind, "success")
		expect.equal(w.toasts[1].args.percent, PERCENT)
		-- Asking again (the row's button) gives nothing more, and Roblox is not asked about a member again.
		local reply = PerkService.check(one)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { member = true, coins = 0 })
		expect.equal(#w.grants, 1)
		expect.equal(w.askedNow, 0)
		-- A new visit of the same account: the boost again, never the gift.
		PerkService.playerRemoving(one)
		local again = w.join(1)
		w.answer()
		expect.equal(PerkService.penBoost(again), GROUP.penBoost)
		expect.equal(#w.grants, 1)
		expect.equal(#w.toasts, 1)
		w.done()
	end)

	t.test("a member whose profile is not READY yet gets the gift once it is", function()
		local w = setup()
		w.member[1] = true
		w.status[1] = "loading"
		local one = w.join(1)
		w.answer()
		expect.equal(PerkService.penBoost(one), GROUP.penBoost) -- the boost needs no profile
		expect.equal(#w.grants, 0)
		expect.deepEqual(PerkService.check(one).data, { member = true, coins = 0 })
		w.status[1] = "ready"
		expect.deepEqual(PerkService.check(one).data, { member = true, coins = GIFT })
		expect.equal(#w.grants, 1)
		w.done()
	end)

	t.test("a broken gift flag counts as given: never twice", function()
		local w = setup()
		w.member[1] = true
		local one = FakePlayer.new(1)
		w.profileOf(one).gifts.group = "yes"
		PerkService.playerAdded(one)
		w.answer()
		expect.equal(#w.grants, 0)
		expect.equal(PerkService.penBoost(one), GROUP.penBoost)
		w.done()
	end)

	t.test("GroupCheck: someone who just joined the group is asked about with the fresh call and gets it all", function()
		local w = setup()
		local two = w.join(2)
		w.answer()
		expect.equal(PerkService.penBoost(two), 0)
		w.memberNow[2] = true -- they joined the group during the visit
		local reply = PerkService.check(two)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { member = true, coins = GIFT })
		expect.equal(w.askedNow, 1)
		expect.equal(PerkService.penBoost(two), GROUP.penBoost)
		expect.equal(two:GetAttribute("SD_GroupBoost"), PERCENT)
		w.done()
	end)

	t.test("GroupCheck: not a member answers so; asking again too soon is net.rateLimited", function()
		local w = setup()
		local two = w.join(2)
		w.answer()
		expect.deepEqual(PerkService.check(two).data, { member = false, coins = 0 })
		local soon = PerkService.check(two)
		expect.equal(soon.ok, false)
		expect.equal(soon.reason, "net.rateLimited")
		expect.equal(w.askedNow, 1)
		w.clock.advance(GROUP.recheckSeconds + 0.1)
		w.memberNow[2] = true
		expect.deepEqual(PerkService.check(two).data, { member = true, coins = GIFT })
		expect.equal(w.askedNow, 2)
		w.done()
	end)

	t.test("GroupCheck: a fresh call that fails answers error.generic and changes nothing", function()
		local w = setup()
		local three = w.join(3)
		w.answer()
		w.memberNow[3] = "error"
		local reply = PerkService.check(three)
		expect.equal(reply.ok, false)
		expect.equal(reply.reason, "error.generic")
		expect.equal(PerkService.penBoost(three), 0)
		expect.equal(#w.grants, 0)
		w.done()
	end)

	t.test("leaving forgets the player, also for an answer that comes back after they left", function()
		local w = setup()
		w.member[1] = true
		local one = w.join(1)
		PerkService.playerRemoving(one)
		w.answer() -- Roblox answers after they left
		expect.equal(PerkService.penBoost(one), 0)
		expect.equal(one:GetAttribute("SD_GroupBoost"), 0)
		expect.equal(#w.grants, 0)
		w.done()
	end)

	-- Big job item 5: Roblox Plus (and legacy Premium) subscribers.

	t.test("a subscriber gets the Plus pen boost, SD_PlusBoost and the Plus gift once; nobody else does", function()
		local w = setup()
		w.plus[1] = true
		local one, two = w.join(1), w.join(2)
		expect.equal(PerkService.penBoost(one), PLUS.penBoost) -- known on join: it is read, not asked
		expect.equal(one:GetAttribute("SD_PlusBoost"), PLUS_PERCENT)
		expect.equal(one:GetAttribute("SD_GroupBoost"), 0)
		expect.deepEqual(w.grants, { { userId = 1, amount = PLUS_GIFT, reason = "plus" } })
		expect.equal(w.profileOf(one).gifts.plus, true)
		expect.equal(w.profileOf(one).gifts.group, nil) -- each perk has its own gift
		expect.equal(w.toasts[1].code, "bonus.plusGift")
		expect.equal(w.toasts[1].args.percent, PLUS_PERCENT)
		expect.equal(PerkService.penBoost(two), 0)
		expect.equal(two:GetAttribute("SD_PlusBoost"), 0)
		-- A new visit: the boost again, never the gift.
		PerkService.playerRemoving(one)
		local again = w.join(1)
		expect.equal(PerkService.penBoost(again), PLUS.penBoost)
		expect.equal(#w.grants, 1)
		w.done()
	end)

	t.test("subscribing during the visit turns the perk on; a subscription that ends turns the boost off", function()
		local w = setup()
		local two = w.join(2)
		expect.equal(PerkService.penBoost(two), 0)
		w.setPlus(two, true)
		expect.equal(PerkService.penBoost(two), PLUS.penBoost)
		expect.equal(two:GetAttribute("SD_PlusBoost"), PLUS_PERCENT)
		expect.equal(#w.grants, 1)
		w.setPlus(two, false)
		expect.equal(PerkService.penBoost(two), 0)
		expect.equal(two:GetAttribute("SD_PlusBoost"), 0)
		w.setPlus(two, true) -- back again: the boost, not a second gift
		expect.equal(PerkService.penBoost(two), PLUS.penBoost)
		expect.equal(#w.grants, 1)
		w.done()
	end)

	t.test("a subscription read that fails changes nothing: a perk is never taken away by an error", function()
		local w = setup()
		w.plus[1] = true
		local one = w.join(1)
		w.setPlus(one, "error")
		expect.equal(PerkService.penBoost(one), PLUS.penBoost)
		expect.equal(one:GetAttribute("SD_PlusBoost"), PLUS_PERCENT)
		-- And someone whose first read fails simply has no perk yet.
		w.plus[3] = "error"
		local three = w.join(3)
		expect.equal(PerkService.penBoost(three), 0)
		w.setPlus(three, true)
		expect.equal(PerkService.penBoost(three), PLUS.penBoost)
		w.done()
	end)

	t.test("the group's and Plus's boosts add up, each with its own gift; leaving stops following", function()
		local w = setup()
		w.member[1] = true
		w.plus[1] = true
		local one = w.join(1)
		w.answer()
		expect.near(PerkService.penBoost(one), GROUP.penBoost + PLUS.penBoost, 1e-9)
		expect.equal(#w.grants, 2)
		expect.equal(w.profileOf(one).gifts.group, true)
		expect.equal(w.profileOf(one).gifts.plus, true)
		expect.truthy(w.watching[1] ~= nil)
		PerkService.playerRemoving(one)
		expect.equal(w.watching[1], nil)
		expect.equal(PerkService.penBoost(one), 0)
		w.done()
	end)

	t.test("a subscriber whose profile is not READY yet gets the Plus gift once it is", function()
		local w = setup()
		w.plus[1] = true
		w.status[1] = "loading"
		local one = w.join(1)
		expect.equal(PerkService.penBoost(one), PLUS.penBoost)
		expect.equal(#w.grants, 0)
		w.status[1] = "ready"
		w.setPlus(one, true) -- any later look gives it (in the game: the profile's Loaded signal)
		expect.deepEqual(w.grants, { { userId = 1, amount = PLUS_GIFT, reason = "plus" } })
		w.done()
	end)
end
