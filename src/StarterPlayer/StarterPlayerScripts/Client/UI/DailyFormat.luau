--!strict
-- DailyFormat (client only, pure). DESIGN §6.9 (daily rewards), §11.6 (Daily screen), §7.7 (the daily stand sign's
-- status line), §11.3 (states). What the Daily panel and the stand sign show, as plain data. The server decides every
-- claim (DailyRewardService + Logic/DailyLogic); this module only displays.
-- Reading: it repeats the trivial display math of the server's Logic/DailyLogic (claim eligibility and the next
-- streak day), because the client cannot require server Logic. Times are server times (workspace:GetServerTimeNow(),
-- the Unix scale): the client clock is never used (§6.9); the UTC day is TimeUtil.utcDay(now).
--   today(now)                       the UTC day index of a server time
--   canClaim(daily, today)           today > daily.lastClaimDay (§2.8 DailyClaim)
--   welcomeBack(daily, today)        a day was missed since the last claim (review quick win 2026-10-14: that only
--                                    pauses the streak; the panel and the join toast say daily.welcomeBack)
--   nextDay(daily, today)            the streak day the next claim gives: streakDay % 7 + 1 after any claim, also
--                                    after a missed day; Day 1 for a first claim; while claimed today, today's day
--   countdownText(now)               "5:03:12" until the next 00:00 UTC (TimeUtil.formatCountdown)
--   model(daily, now, capsules?)     the 7 day cards (daily.dayLabel, Coins, daily.treatBox on the free box
--                                    day; today highlighted with daily.today; claimed days with a check and
--                                    common.claimed), the claim state, the welcome back line (daily.welcomeBack with
--                                    the waiting day, while it is claimable after a missed day) and "Come
--                                    back in {time}". Phase 5 (progression spec 2026-10-12 §9): a day's Coins are its
--                                    squeezes (coinsByDay) × the squeeze value of `capsules` (the player's capsules state;
--                                    CapsuleMath.rewardCoins, as the server pays at claim time)
--   signText(daily, now)             the stand sign's status line: daily.ready / daily.wait {time}; nil = unknown
-- Part 8 layout (§11.2; base px under the ScreenGui UIScale; unit-tested at 667×375, 1280×720, 1920×1080 and the
-- largest text):
--   cardWidth(base, textScale)       a day card's width: the base width grown with the text size (PreferredTextSize),
--                                    so "Claimed" and "500 Coins" still fit their card at the largest text
--   cardsPerRow(rowWidth, card, gap) how many day cards fit on one line of the wrapping row (at least 1)
--   bodyHeight(screenH, contentH, chromeH, maxShare, minH)   the scrolling part of the panel: the content's height,
--                                    capped so the whole panel stays within maxShare of the screen height
-- Foam UI restyle (spec 2026-10-09):
--   cardLook(card)                   a day card's face and outline: today = the Daily tile's Sky blue with the thick
--                                    outline (claimed today too), the free Treat Box day = the Boxes tile's Lilac, a
--                                    day already claimed = Biscuit (recessed), else Frosting. Each look comes with its
--                                    word on the card (Today, Treat Box, Claimed), never colour alone
-- Readings: a daily value of the wrong shape counts as unknown (no claim offered, the sign stays as it is). The
-- free-box day and the squeezes per day come from Config.Economy.Daily (coinsByDay, freeBoxDay).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local CapsuleMath = require(Shared.CapsuleMath)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)
local TimeUtil = require(Shared.Util.TimeUtil)

-- Types

export type DailyLike = { lastClaimDay: number, streakDay: number, totalClaims: number? }

export type DayCard = {
	day: number, -- 1..#coinsByDay
	label: string, -- "Day 3"
	coins: number,
	coinsText: string, -- "200 Coins"
	treat: boolean, -- the free Treat Box day
	treatText: string?, -- "Treat Box" (daily.treatBox; "Free Treat Box" before foam fix round 2)
	today: boolean, -- the day claimable now, or claimed today
	todayText: string?, -- daily.today
	claimed: boolean, -- claimed in the current cycle (check + text)
	claimedText: string?, -- common.claimed
}

-- A day card's look (foam UI): a Theme accent name ("sky", "lilac", "frosting") or "biscuit" (Theme.Colors.biscuit),
-- and whether its outline is the thick one.
export type CardFace = "frosting" | "sky" | "lilac" | "biscuit"
export type CardLook = { face: CardFace, thick: boolean }

export type Model = {
	known: boolean, -- false: no daily state yet (loading or a profile that did not load)
	canClaim: boolean,
	nextDay: number, -- the day the next claim gives (today's day while claimed today)
	coins: number, -- the Coins of `nextDay`
	treat: boolean, -- `nextDay` is the free Treat Box day
	cards: { DayCard },
	welcomeBack: boolean, -- back after a missed day and today is claimable: show the welcome back line
	welcomeText: string?, -- daily.welcomeBack with the waiting day
	countdownText: string?, -- "Come back in {time}" once today is claimed
	secondsLeft: number, -- until the next 00:00 UTC
}

-- Constants

local DAILY = Config.Economy.Daily
local COINS_BY_DAY: { number } = DAILY.coinsByDay
local DAYS = #COINS_BY_DAY
local FREE_BOX_DAY: number = DAILY.freeBoxDay

-- Module table

local DailyFormat = {}

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

-- The daily value if it has the §3.2 shape, else nil.
local function valid(daily: unknown): DailyLike?
	if type(daily) ~= "table" then
		return nil
	end
	local d = daily :: any
	if not finite(d.lastClaimDay) or not finite(d.streakDay) then
		return nil
	end
	return d :: DailyLike
end

local function clampDay(day: number): number
	return math.clamp(math.floor(day), 1, DAYS)
end

-- Public

function DailyFormat.today(now: number): number
	return TimeUtil.utcDay(now)
end

function DailyFormat.canClaim(daily: unknown, today: number): boolean
	local d = valid(daily)
	return d ~= nil and finite(today) and today > d.lastClaimDay
end

-- True when the player is back after a missed day (a first-ever claim is not one). A missed day only pauses the
-- streak: the next claim still pays the next day.
function DailyFormat.welcomeBack(daily: unknown, today: number): boolean
	local d = valid(daily)
	if d == nil or not finite(today) or d.lastClaimDay < 0 or today <= d.lastClaimDay then
		return false
	end
	return today - d.lastClaimDay > 1
end

function DailyFormat.nextDay(daily: unknown, today: number): number
	local d = valid(daily)
	if d == nil or not finite(today) then
		return 1
	end
	if today <= d.lastClaimDay then
		return clampDay(math.max(1, d.streakDay)) -- claimed today: today's card is the day just claimed
	end
	if d.lastClaimDay < 0 or d.streakDay < 1 then
		return 1
	end
	return clampDay(math.floor(d.streakDay) % DAYS + 1)
end

-- Seconds until the next 00:00 UTC and its "h:mm:ss" text.
function DailyFormat.countdownText(now: number): string
	return TimeUtil.formatCountdown(TimeUtil.secondsUntilNextUtcDay(now))
end

-- The Daily panel.
function DailyFormat.model(daily: unknown, now: number, capsules: any?): Model
	local seconds = if finite(now) then TimeUtil.secondsUntilNextUtcDay(now) else 0
	local value = CapsuleMath.squeezeValue(capsules)
	local d = valid(daily)
	local today = if finite(now) then TimeUtil.utcDay(now) else 0
	local known = d ~= nil and finite(now)
	local can = known and DailyFormat.canClaim(d, today)
	local day = DailyFormat.nextDay(d, today)
	local welcome = can and DailyFormat.welcomeBack(d, today)
	-- Days already claimed in this cycle: before today's claim, the days before the next one;
	-- once today is claimed, every day up to and including it.
	local claimedUpTo = if not known then 0 elseif can then day - 1 else day
	local cards: { DayCard } = {}
	local todayWord = Strings.daily.today
	for n = 1, DAYS do
		local coins = CapsuleMath.rewardCoins(COINS_BY_DAY[n], value)
		local isToday = known and n == day
		local claimed = n <= claimedUpTo
		table.insert(cards, {
			day = n,
			label = Strings.format(Strings.daily.dayLabel, { n = n }),
			coins = coins,
			coinsText = Strings.format(Strings.common.coinsAmount, { coins = Format.coins(coins) }),
			treat = n == FREE_BOX_DAY,
			treatText = if n == FREE_BOX_DAY then Strings.daily.treatBox else nil,
			today = isToday,
			todayText = if isToday then todayWord else nil,
			claimed = claimed,
			claimedText = if claimed then Strings.common.claimed else nil,
		})
	end
	return {
		known = known,
		canClaim = can,
		nextDay = day,
		coins = CapsuleMath.rewardCoins(COINS_BY_DAY[day], value),
		treat = day == FREE_BOX_DAY,
		cards = cards,
		welcomeBack = welcome,
		welcomeText = if welcome then Strings.format(Strings.daily.welcomeBack, { n = day }) else nil,
		countdownText = if known and not can
			then Strings.format(Strings.daily.comeBack, { time = TimeUtil.formatCountdown(seconds) })
			else nil,
		secondsLeft = seconds,
	}
end

-- A day card's face and outline (foam UI): today first (claimed today or not), then a day already claimed (the Treat
-- Box day too), then the free Treat Box day still to come, else plain.
function DailyFormat.cardLook(card: DayCard): CardLook
	if card.today then
		return { face = "sky", thick = true }
	elseif card.claimed then
		return { face = "biscuit", thick = false }
	elseif card.treat then
		return { face = "lilac", thick = false }
	end
	return { face = "frosting", thick = false }
end

-- Public: layout (Part 8)

-- A day card's width for the player's text-size multiplier (Theme text size / Config base size; 1 = Medium): never
-- narrower than `baseWidth`, wider in step with the text, whole px.
function DailyFormat.cardWidth(baseWidth: number, textScale: number): number
	local scale = if finite(textScale) then math.max(1, textScale) else 1
	return math.ceil(math.max(0, baseWidth) * scale - 1e-9)
end

-- How many cards of `cardWidth` with `gap` between them fit on a row `rowWidth` wide (at least one).
function DailyFormat.cardsPerRow(rowWidth: number, cardWidth: number, gap: number): number
	if not (cardWidth > 0) or not finite(rowWidth) then
		return 1
	end
	return math.max(1, math.floor((rowWidth + math.max(0, gap) + 1e-9) / (cardWidth + math.max(0, gap))))
end

-- The height of a panel's scrolling body: its content, capped so the panel (body + `chromeHeight`, the header, the
-- buttons and the paddings) stays within `maxShare` of a screen `screenHeight` tall; never under `minHeight`.
function DailyFormat.bodyHeight(
	screenHeight: number,
	contentHeight: number,
	chromeHeight: number,
	maxShare: number,
	minHeight: number
): number
	local room = (if finite(screenHeight) then screenHeight else 0) * maxShare
		- (if finite(chromeHeight) then chromeHeight else 0)
	local content = if finite(contentHeight) then math.max(0, contentHeight) else 0
	return math.max(minHeight, math.min(content, room))
end

-- The daily stand sign's live line (§7.7): "Ready to claim!" or "Next reward in {time}"; nil while unknown (the line
-- keeps what it shows: built empty).
function DailyFormat.signText(daily: unknown, now: number): string?
	if valid(daily) == nil or not finite(now) then
		return nil
	end
	if DailyFormat.canClaim(daily, TimeUtil.utcDay(now)) then
		return Strings.daily.ready
	end
	return Strings.format(Strings.daily.wait, { time = DailyFormat.countdownText(now) })
end

return DailyFormat
