--!strict
-- DailyRewardService_Test: unit tests for ServerScriptService.Server.Services.DailyRewardService with injected fakes (a
-- fake data port, a fake Unix clock, a Coin recorder, a fake BoxService.grantFree and a fake "now" save; the player
-- is a plain table). Server only (ServerStorage.UnitTest). Edit mode: init() is never called.
-- Contract (DESIGN §6.9, §2.8 DailyClaim, §3.4 daily row, §3.11):
--   * one claim per UTC day (os.time; 23:59:59 and 00:00:00 are different days); a second claim the same day is
--     daily.alreadyClaimed and changes nothing;
--   * the streak continues the day after a claim (after day 7 back to Day 1), restarts at Day 1 after a missed day
--     (daily.streakReset toast, streakReset = true), and a first claim starts at Day 1 without the reset sentence;
--   * Coins by day 100..500 with reason "daily"; day 7 also grants the free Treat Box through
--     BoxService.grantFree(p, "treat", "daily:<day>") in the same flow; one awaited "now" save; the reply is
--     {streakDay, coins, treat, streakReset, treatRequestId} and a failed save shows as treat.savePending;
--   * not ready -> data.notReady; a pending failed save -> box.saving; neither changes anything;
--   * status() reports the same rules; debugSetState sets the record (Studio only).

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
	requireFake: (name: string) -> any,
}

local DAY = 20000
local DAY_SECONDS = 86400

return function(t: Context)
	local expect = t.expect
	local DailyRewardService = t.requireServer("Services/DailyRewardService")
	local Config = t.requireShared("Config")
	local FakeClock = t.requireFake("FakeClock")

	local DAILY = Config.Economy.Daily

	type World = {
		clock: any,
		player: any,
		status: string,
		savePending: boolean,
		saveOk: boolean,
		profile: any,
		dirty: { string },
		notices: { string },
		grants: { { amount: number, reason: string } },
		boxes: { { boxId: string, requestId: string } },
		nowSaves: number,
		boxFails: boolean,
		debug: boolean,
	}

	local function fresh(lastClaimDay: number, streakDay: number): World
		local w: World = {
			clock = FakeClock.new(DAY * DAY_SECONDS + 10 * 3600),
			player = { UserId = 31 },
			status = "ready",
			savePending = false,
			saveOk = true,
			profile = {
				coins = 0,
				daily = { lastClaimDay = lastClaimDay, streakDay = streakDay, totalClaims = 4 },
				boxLog = {},
			},
			dirty = {},
			notices = {},
			grants = {},
			boxes = {},
			nowSaves = 0,
			boxFails = false,
			debug = true,
		}
		DailyRewardService.useDeps({
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
					return w.savePending
				end,
				statusReason = function(_player: any): string?
					return nil
				end,
				mutate = function(_player: any, fn: (profile: any) -> any): (boolean, any)
					if w.status ~= "ready" then
						return false, "data.notReady"
					end
					return true, fn(w.profile)
				end,
				requestSave = function(_player: any, _reason: string) end,
				onLoaded = function(_handler: any) end,
				onStatusChanged = function(_handler: any) end,
			},
			markDirty = function(_player: any, field: string)
				table.insert(w.dirty, field)
			end,
			notify = function(_player: any, code: string)
				table.insert(w.notices, code)
			end,
			grantCoins = function(_player: any, amount: number, reason: string): (number, string?)
				w.profile.coins += amount
				table.insert(w.grants, { amount = amount, reason = reason })
				return amount, nil
			end,
			grantFree = function(_player: any, boxId: string, requestId: string): any
				if w.boxFails then
					error("box service down")
				end
				table.insert(w.boxes, { boxId = boxId, requestId = requestId })
				table.insert(w.profile.boxLog, { req = requestId, box = boxId, squishy = "toast", seen = false })
				return { squishyId = "toast", isDuplicate = false, refund = 0, savePending = false }
			end,
			saveNow = function(_player: any): boolean
				w.nowSaves += 1
				return w.saveOk
			end,
			unixNow = w.clock.now,
			debugAllowed = function(): boolean
				return w.debug
			end,
		})
		return w
	end

	local function finish()
		DailyRewardService.useDeps(nil)
	end

	t.test("a first claim pays Day 1 with 'daily', records the day, saves now once, no reset sentence", function()
		local w = fresh(-1, 0)
		local reply = DailyRewardService.claim(w.player)
		expect.equal(reply.ok, true)
		expect.deepEqual(reply.data, { streakDay = 1, coins = DAILY.coinsByDay[1], streakReset = false })
		expect.deepEqual(w.profile.daily, { lastClaimDay = DAY, streakDay = 1, totalClaims = 5 })
		expect.deepEqual(w.grants, { { amount = DAILY.coinsByDay[1], reason = "daily" } })
		expect.deepEqual(w.dirty, { "daily" })
		expect.equal(w.nowSaves, 1)
		expect.deepEqual(w.notices, {})
		expect.equal(#w.boxes, 0)
		finish()
	end)

	t.test("a second claim the same UTC day is daily.alreadyClaimed and changes nothing", function()
		local w = fresh(-1, 0)
		DailyRewardService.claim(w.player)
		w.clock.advance(13 * 3600 + 3599) -- 23:59:59 of the same day
		local again = DailyRewardService.claim(w.player)
		expect.equal(again.ok, false)
		expect.equal(again.reason, "daily.alreadyClaimed")
		expect.equal(#w.grants, 1)
		expect.equal(w.nowSaves, 1)
		w.clock.advance(1) -- 00:00:00 UTC: a new day
		local next = DailyRewardService.claim(w.player)
		expect.equal(next.ok, true)
		expect.equal(next.data.streakDay, 2)
		expect.equal(w.profile.daily.lastClaimDay, DAY + 1)
		finish()
	end)

	t.test("the streak continues the day after a claim", function()
		local w = fresh(DAY - 1, 3)
		local reply = DailyRewardService.claim(w.player)
		expect.equal(reply.data.streakDay, 4)
		expect.equal(reply.data.coins, DAILY.coinsByDay[4])
		expect.equal(reply.data.streakReset, false)
		expect.equal(w.profile.coins, DAILY.coinsByDay[4])
		finish()
	end)

	t.test("a missed day restarts the streak at Day 1 with daily.streakReset", function()
		local w = fresh(DAY - 2, 5)
		local reply = DailyRewardService.claim(w.player)
		expect.equal(reply.data.streakDay, 1)
		expect.equal(reply.data.streakReset, true)
		expect.equal(reply.data.coins, DAILY.coinsByDay[1])
		expect.deepEqual(w.notices, { "daily.streakReset" })
		finish()
	end)

	t.test("day 7 pays 500 and opens the free Treat Box daily:<day> in the same claim", function()
		expect.equal(DAILY.freeBoxDay, 7)
		local w = fresh(DAY - 1, 6)
		local reply = DailyRewardService.claim(w.player)
		local key = "daily:" .. tostring(DAY)
		expect.equal(reply.data.streakDay, 7)
		expect.equal(reply.data.coins, DAILY.coinsByDay[7])
		expect.equal(reply.data.treatRequestId, key)
		expect.deepEqual(
			reply.data.treat,
			{ squishyId = "toast", isDuplicate = false, refund = 0, savePending = false }
		)
		expect.deepEqual(w.boxes, { { boxId = DAILY.freeBoxId, requestId = key } })
		expect.equal(w.nowSaves, 1) -- one save carries the record, the Coins and the box
		expect.equal(w.profile.boxLog[1].seen, false)
		finish()
	end)

	t.test("after day 7 the cycle restarts at Day 1 without the reset sentence", function()
		local w = fresh(DAY - 1, 7)
		local reply = DailyRewardService.claim(w.player)
		expect.equal(reply.data.streakDay, 1)
		expect.equal(reply.data.streakReset, false)
		expect.equal(#w.boxes, 0)
		expect.equal(w.profile.daily.totalClaims, 5)
		finish()
	end)

	t.test("a failed now save keeps the claim and marks the Treat Box savePending", function()
		local w = fresh(DAY - 1, 6)
		w.saveOk = false
		local reply = DailyRewardService.claim(w.player)
		expect.equal(reply.ok, true)
		expect.equal(reply.data.treat.savePending, true)
		expect.equal(w.profile.daily.lastClaimDay, DAY)
		finish()
	end)

	t.test("a Treat Box that fails to grant is logged; the Coins and the day still count", function()
		local w = fresh(DAY - 1, 6)
		w.boxFails = true
		local reply = DailyRewardService.claim(w.player)
		expect.equal(reply.ok, true)
		expect.equal(reply.data.treat, nil)
		expect.equal(reply.data.treatRequestId, nil)
		expect.equal(w.profile.coins, DAILY.coinsByDay[7])
		finish()
	end)

	t.test("not ready is data.notReady; a pending failed save is box.saving; nothing changes", function()
		local w = fresh(DAY - 1, 2)
		for _, status in { "loading", "offline", "readonly" } do
			w.status = status
			local reply = DailyRewardService.claim(w.player)
			expect.equal(reply.ok, false)
			expect.equal(reply.reason, "data.notReady")
		end
		w.status = "ready"
		w.savePending = true
		local saving = DailyRewardService.claim(w.player)
		expect.equal(saving.reason, "box.saving")
		expect.deepEqual(w.profile.daily, { lastClaimDay = DAY - 1, streakDay = 2, totalClaims = 4 })
		expect.equal(#w.grants, 0)
		expect.equal(w.nowSaves, 0)
		finish()
	end)

	t.test("status() reports the next claim; debugSetState sets the record in Studio only", function()
		local w = fresh(DAY - 1, 6)
		local s = DailyRewardService.status(w.player)
		expect.truthy(s.ready)
		expect.truthy(s.canClaim)
		expect.equal(s.today, DAY)
		expect.equal(s.nextStreakDay, 7)
		expect.equal(s.freeBox, true)
		expect.equal(s.coins, DAILY.coinsByDay[7])
		expect.equal(s.willReset, false)
		expect.equal(s.secondsUntilNext, 14 * 3600)
		expect.truthy(DailyRewardService.debugSetState(w.player, { lastClaimDay = DAY - 3, streakDay = 4 }))
		local reset = DailyRewardService.status(w.player)
		expect.equal(reset.nextStreakDay, 1)
		expect.equal(reset.willReset, true)
		expect.falsy(DailyRewardService.debugSetState(w.player, { streakDay = 9 }))
		w.debug = false
		expect.falsy(DailyRewardService.debugSetState(w.player, { lastClaimDay = DAY }))
		expect.equal(w.profile.daily.lastClaimDay, DAY - 3)
		finish()
	end)
end
