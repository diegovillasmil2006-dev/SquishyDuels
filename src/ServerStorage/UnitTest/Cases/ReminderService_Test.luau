--!strict
-- ReminderService_Test: unit tests for ServerScriptService.Server.Services.ReminderService (come-back reminders) with
-- a fake MemoryStore sorted map and a fake Open Cloud sender. Server only (ServerStorage.UnitTest). Edit mode: start()
-- is never called (sendDue is called directly); players are plain tables.
-- Contract:
--   * jobFor (at leave): the pen's away Coins for the send time (PenMath, Format.coins) when they reach minPenCoins,
--     else the daily reward's next day when it can be claimed on the send day, else nothing; an empty id skips that
--     reminder;
--   * leaving stores the job under "u<userId>", sorted by its due time; nothing without a READY profile or while off;
--   * joining removes the player's job;
--   * sendDue sends the due jobs only (MOMENT, the parameters, the analytics category) and removes them; a player who
--     is in this server gets nothing; a job another server just claimed is left alone; a failing store or sender never
--     breaks the game.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ReminderService = t.requireServer("Services/ReminderService")
	local PenMath = t.requireShared("PenMath")
	local Format = t.requireShared("Util/Format")

	local CFG = {
		penMessageId = "pen-id",
		dailyMessageId = "daily-id",
		sendAfterSeconds = 72000,
		minPenCoins = 1000,
	}
	local DAY = 20000
	local LATE = DAY * 86400 + 36000 -- 10:00 UTC: the send time falls on the next day
	local EARLY = DAY * 86400 + 1000 -- 00:16 UTC: the send time is still today

	local function pen(kind: string?): any
		local items = {}
		if kind then
			items[1] = { id = 1, kind = kind, form = 0, level = 1, coat = 0, slot = 1, locked = false }
		end
		return { spots = 3, nextId = 100, items = items }
	end

	local function profile(kind: string?, lastClaimDay: number?, streakDay: number?): any
		return { pen = pen(kind), daily = { lastClaimDay = lastClaimDay or DAY, streakDay = streakDay or 3 } }
	end

	-- A MemoryStore sorted map in memory. Values are copied in and out, as the real store serializes them.
	local function fakeQueue(options: { [string]: any }?): any
		local opts = options or {}
		local items: { [string]: { value: any, sortKey: number } } = {}
		local queue: any = { items = items }
		local function check()
			if opts.fail then
				error("memory store down")
			end
		end
		function queue.SetAsync(_self: any, key: string, value: any, _expiration: number, sortKey: number)
			check()
			items[key] = { value = table.clone(value), sortKey = sortKey }
			return true
		end
		function queue.RemoveAsync(_self: any, key: string)
			check()
			items[key] = nil
		end
		function queue.GetRangeAsync(_self: any, _direction: any, count: number, _lower: any, upper: any)
			check()
			local list = {}
			for key, entry in items do
				if entry.sortKey < upper.sortKey then
					table.insert(list, { key = key, value = table.clone(entry.value), sortKey = entry.sortKey })
				end
			end
			table.sort(list, function(a: any, b: any): boolean
				return a.sortKey < b.sortKey
			end)
			while #list > count do
				table.remove(list)
			end
			return list
		end
		function queue.UpdateAsync(_self: any, key: string, transform: any, _expiration: number)
			check()
			local entry = items[key]
			local value, sortKey = transform(if entry then table.clone(entry.value) else nil, entry and entry.sortKey)
			if value == nil then
				return nil
			end
			items[key] = { value = table.clone(value), sortKey = sortKey }
			return table.clone(value)
		end
		return queue
	end

	-- Fresh fakes: a queue, sent notifications in `sent` as { userId, payload }, spawned functions run at once.
	local function setup(options: { [string]: any }?): (any, { any })
		local opts = options or {}
		local queue = opts.queue or fakeQueue()
		local sent: { any } = {}
		ReminderService.useDeps({
			config = CFG,
			queue = queue,
			send = function(userId: number, notification: any): any
				if opts.sendFails then
					error("open cloud down")
				end
				table.insert(sent, { userId, notification.payload })
				return { statusCode = 200 }
			end,
			profileOf = function(player: any): any
				return player.profile
			end,
			isHere = function(userId: number): boolean
				return (opts.here or {})[userId] == true
			end,
			now = function(): number
				return opts.now or LATE
			end,
			spawn = function(fn: () -> ())
				fn()
			end,
		})
		return queue, sent
	end

	t.test("jobFor: the pen's away Coins for the send time when they reach minPenCoins", function()
		local p = profile("dragon")
		local job, dueAt = ReminderService.jobFor(p, LATE, CFG)
		local coins = PenMath.awayCoins(PenMath.rate(p.pen), LATE, LATE, LATE + 72000)
		expect.equal(dueAt, LATE + 72000)
		expect.truthy(coins >= 1000)
		expect.deepEqual(job, {
			messageId = "pen-id",
			category = "pen",
			parameters = { coins = { stringValue = Format.coins(coins) } },
		})
	end)

	t.test("jobFor: the daily reward's next day when the pen made too little and it can be claimed then", function()
		local job = ReminderService.jobFor(profile(nil, DAY, 3), LATE, CFG)
		expect.deepEqual(job, {
			messageId = "daily-id",
			category = "daily",
			parameters = { day = { stringValue = "4" } },
		})
	end)

	t.test("jobFor: nothing when the pen made too little and the daily reward is still claimed on the send day", function()
		expect.equal(ReminderService.jobFor(profile(nil, DAY, 3), EARLY, CFG), nil)
		expect.equal(ReminderService.jobFor(nil, LATE, CFG), nil)
	end)

	t.test("jobFor: an empty id skips that reminder", function()
		local noPen = table.clone(CFG)
		noPen.penMessageId = ""
		local job = ReminderService.jobFor(profile("dragon", DAY, 3), LATE, noPen)
		expect.equal(job and job.category, "daily")
		local noDaily = table.clone(CFG)
		noDaily.dailyMessageId = ""
		expect.equal(ReminderService.jobFor(profile(nil, DAY, 3), LATE, noDaily), nil)
	end)

	t.test("leaving stores the job under u<userId>, sorted by its due time", function()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 42, profile = profile("dragon") } :: any)
		local entry = queue.items.u42
		expect.truthy(entry)
		expect.equal(entry.sortKey, LATE + 72000)
		expect.equal(entry.value.category, "pen")
		ReminderService.useDeps(nil)
	end)

	t.test("leaving without a READY profile or while off stores nothing", function()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 1, profile = nil } :: any)
		expect.equal(next(queue.items), nil)
		-- The default deps are off in Studio (no queue, no sender).
		ReminderService.useDeps({
			profileOf = function(player: any): any
				return player.profile
			end,
		})
		ReminderService.playerRemoving({ UserId = 2, profile = profile("dragon") } :: any) -- no error, nothing stored
		ReminderService.sendDue()
		ReminderService.useDeps(nil)
	end)

	t.test("joining removes the player's job", function()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 7, profile = profile("dragon") } :: any)
		ReminderService.playerAdded({ UserId = 7 } :: any)
		expect.equal(queue.items.u7, nil)
		ReminderService.useDeps(nil)
	end)

	t.test("sendDue sends the due jobs only, as MOMENT with the parameters and category, and removes them", function()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 5, profile = profile("dragon") } :: any)
		local _, sent = setup({ queue = queue, now = LATE + 71999 })
		ReminderService.sendDue()
		expect.equal(#sent, 0)
		expect.truthy(queue.items.u5)
		_, sent = setup({ queue = queue, now = LATE + 72000 })
		ReminderService.sendDue()
		expect.equal(#sent, 1)
		expect.equal(sent[1][1], 5)
		local payload = sent[1][2]
		expect.equal(payload.messageId, "pen-id")
		expect.equal(payload.type, "MOMENT")
		expect.equal(payload.analyticsData.category, "pen")
		expect.equal(type(payload.parameters.coins.stringValue), "string")
		expect.equal(queue.items.u5, nil)
		ReminderService.useDeps(nil)
	end)

	t.test("sendDue skips a player who is in this server and drops the job", function()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 9, profile = profile("dragon") } :: any)
		local _, sent = setup({ queue = queue, now = LATE + 80000, here = { [9] = true } })
		ReminderService.sendDue()
		expect.equal(#sent, 0)
		expect.equal(queue.items.u9, nil)
		ReminderService.useDeps(nil)
	end)

	t.test("sendDue leaves a job another server just claimed", function()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 3, profile = profile("dragon") } :: any)
		local now = LATE + 80000
		queue.items.u3.value.claimedBy = "other-server"
		queue.items.u3.value.claimedAt = now - 10
		local _, sent = setup({ queue = queue, now = now })
		ReminderService.sendDue()
		expect.equal(#sent, 0)
		expect.truthy(queue.items.u3)
		ReminderService.useDeps(nil)
	end)

	t.test("a failing store or sender never breaks the game", function()
		local broken = fakeQueue({ fail = true })
		setup({ queue = broken })
		ReminderService.playerRemoving({ UserId = 4, profile = profile("dragon") } :: any)
		ReminderService.playerAdded({ UserId = 4 } :: any)
		ReminderService.sendDue()
		local queue = setup()
		ReminderService.playerRemoving({ UserId = 6, profile = profile("dragon") } :: any)
		setup({ queue = queue, now = LATE + 80000, sendFails = true })
		ReminderService.sendDue()
		expect.equal(queue.items.u6, nil) -- tried once, never retried
		ReminderService.useDeps(nil)
	end)
end
