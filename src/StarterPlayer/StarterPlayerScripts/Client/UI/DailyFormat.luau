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
--   model(daily, now, pen?)          the 7 day cards (daily.dayLabel, Coins, daily.treatBox on the free box
--                                    day; today highlighted with daily.today; claimed days with a check and
--                                    common.claimed), the claim state, the welcome back line (daily.welcomeBack with
--                                    the waiting day, while it is claimable after a missed day) and "Come
--                                    back in {time}". Phase 5 (progression spec 2026-10-12 §9): a day's Coins are its
--                                    squeezes (coinsByDay) × the squeeze value of `pen` (pens3 phase 1: the player's pen
--                                    state; PenMath.rewardCoins, as the server pays at claim time)
--   signText(daily, now)             the stand sign's status line: daily.ready / the countdown; nil = unknown
--   bodyHeight(screenH, contentH, chromeH, maxShare, minH)   Part 8: a scrolling panel part (CapsuleController's): the
--                                    content's height, capped so the whole panel stays within maxShare of the screen
-- UI FINAL R8 (the design's Daily window, plan work/ui/PLAN.md R8; `H:n` = "Squishy Duels HUD.dc.html" line n;
-- Config.UI.Daily):
--   a DayCard also says `next` (the day tomorrow's claim gives, "Tomorrow", H:403), `locked` (a later day: the lock,
--   H:399), its value (the day's Coins as a number beside the coin, H:401, or "Treat Box" on the box day [FD7]) and its
--   foot (Claimed / Claim! / Tomorrow / Locked, H:964); the Model its streak pill ("Day {n}" [FD6], H:390) and timer
--   line ("Your reward is ready!" / "Next reward in h:mm:ss", H:1029; nil while unknown)
--   cardLook(card)                   the card's face (Palette names of its two stops), border and name colours and
--                                    its icon's alpha (H:965-966): a claimed day the lilac with the dark name and the
--                                    icon at .5, today's claimable day the yellow with the white border, else the
--                                    purple card; the box day's card draws its own face (Config.UI.Daily.day7)
--   cardFace(nameH, valueH)          a day card's natural face height (base px): its padding, border, the name, the
--                                    icon, the value and the chip, 4 apart (H:395-402)
--   day7Face(titleH, nameH, footH)   day 7's natural face height (H:406-416, the art at its 170 px)
--   gridLayout(width, room, compact, cardFace, day7Face)   the grid's boxes (each face + lip; H:393: 1fr 1fr 1fr
--                                    1.25fr, 2 rows, gap 14, day 7 over both rows): the faces share `room`, never under
--                                    their natural height; compact (phones, plan R8): 3 columns, day 7 under them at
--                                    its natural height; and the height the grid takes
-- Readings: a daily value of the wrong shape counts as unknown (no claim offered, the sign stays as it is). The
-- free-box day and the squeezes per day come from Config.Economy.Daily (coinsByDay, freeBoxDay).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local PenMath = require(Shared.PenMath)
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
	next: boolean, -- UI FINAL R8: the day tomorrow's claim gives ("Tomorrow", H:403)
	locked: boolean, -- UI FINAL R8: a later day (the lock, H:399)
	valueText: string, -- UI FINAL R8: "200" beside the coin, or "Treat Box" on the box day (H:401)
	foot: string, -- UI FINAL R8: Claimed / Claim! / Tomorrow / Locked (H:964; day 7 shows it)
}

-- UI FINAL R8 (H:965-966): a day card's look as Art/Palette names: its face's two stops, its border, its name.
export type CardLook = { top: string, bottom: string, border: string, name: string, iconAlpha: number }

-- UI FINAL R8: a box in the grid (base px, from the grid's top-left).
export type Rect = { x: number, y: number, w: number, h: number }
export type GridLayout = { cards: { Rect }, day7: Rect, height: number }

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
	streakText: string, -- UI FINAL R8: "Day {n}" (the day being claimed or claimed today; FD6)
	timerText: string?, -- UI FINAL R8: daily.readyNow / daily.wait {time}; nil while unknown
}

-- Constants

local DAILY = Config.Economy.Daily
local COINS_BY_DAY: { number } = DAILY.coinsByDay
local DAYS = #COINS_BY_DAY
local FREE_BOX_DAY: number = DAILY.freeBoxDay
local UI = Config.UI.Daily
local LOOK_CLAIMED: CardLook = {
	top = "StickerDayClaimedTop",
	bottom = "StickerDayClaimedEnd",
	border = "StickerInk",
	name = "StickerDayClaimedText",
	iconAlpha = UI.card.claimedIconAlpha,
}
local LOOK_TODAY: CardLook = {
	top = "StickerCreamYellow",
	bottom = "StickerGoldMid",
	border = "White",
	name = "StickerFoundText",
	iconAlpha = 1,
}
local LOOK_PLAIN: CardLook =
	{ top = "StickerCardTop", bottom = "StickerCardBottom", border = "StickerInk", name = "White", iconAlpha = 1 }

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
function DailyFormat.model(daily: unknown, now: number, pen: any?): Model
	local seconds = if finite(now) then TimeUtil.secondsUntilNextUtcDay(now) else 0
	local value = PenMath.squeezeValue(pen)
	local d = valid(daily)
	local today = if finite(now) then TimeUtil.utcDay(now) else 0
	local known = d ~= nil and finite(now)
	local can = known and DailyFormat.canClaim(d, today)
	local day = DailyFormat.nextDay(d, today)
	local welcome = can and DailyFormat.welcomeBack(d, today)
	-- Days already claimed in this cycle: before today's claim, the days before the next one;
	-- once today is claimed, every day up to and including it.
	local claimedUpTo = if not known then 0 elseif can then day - 1 else day
	-- UI FINAL R8 (H:963-964): once today is claimed the day after it is "Tomorrow"; the days after that are locked.
	local nextDay = if known and not can then day + 1 else nil
	local lockedFrom = if not known then math.huge elseif can then day + 1 else day + 2
	local cards: { DayCard } = {}
	local todayWord = Strings.daily.today
	for n = 1, DAYS do
		local coins = PenMath.rewardCoins(COINS_BY_DAY[n], value)
		local isToday = known and n == day
		local claimed = n <= claimedUpTo
		local isNext = n == nextDay
		local locked = n >= lockedFrom
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
			next = isNext,
			locked = locked,
			valueText = if n == FREE_BOX_DAY then Strings.daily.treatBox else Format.coins(coins),
			foot = if claimed
				then Strings.common.claimed
				elseif isToday then Strings.daily.footClaim
				elseif isNext then Strings.daily.tomorrow
				else Strings.daily.footLocked,
		})
	end
	return {
		known = known,
		canClaim = can,
		nextDay = day,
		coins = PenMath.rewardCoins(COINS_BY_DAY[day], value),
		treat = day == FREE_BOX_DAY,
		cards = cards,
		welcomeBack = welcome,
		welcomeText = if welcome then Strings.format(Strings.daily.welcomeBack, { n = day }) else nil,
		countdownText = if known and not can
			then Strings.format(Strings.daily.comeBack, { time = TimeUtil.formatCountdown(seconds) })
			else nil,
		secondsLeft = seconds,
		streakText = Strings.format(Strings.daily.dayLabel, { n = day }),
		timerText = if not known
			then nil
			elseif can then Strings.daily.readyNow
			else Strings.format(Strings.daily.wait, { time = TimeUtil.formatCountdown(seconds) }),
	}
end

-- UI FINAL R8 (H:965-966): a claimed day first (claimed today too), then today's claimable day, else the purple card.
function DailyFormat.cardLook(card: DayCard): CardLook
	if card.claimed then
		return LOOK_CLAIMED
	elseif card.today then
		return LOOK_TODAY
	end
	return LOOK_PLAIN
end

-- Public: layout (UI FINAL R8)

-- A day card's natural face (H:395-402): border, padding 10 / 10, the name, the 84 px icon, the value and the 34 px
-- CLAIM! chip (the tallest last line), 4 apart.
function DailyFormat.cardFace(nameHeight: number, valueHeight: number): number
	local c = UI.card
	return 2 * c.border + c.padTop + c.padBottom + nameHeight + c.iconPx + valueHeight + c.chipFace + 3 * c.gap
end

-- Day 7's natural face (H:406-416): border, padding 14 / 14, "Day 7", the 26 px pill, the 170 px art, the name and the
-- foot, 6 apart.
function DailyFormat.day7Face(titleHeight: number, nameHeight: number, footHeight: number): number
	local d = UI.day7
	return 2 * d.border
		+ d.padTop
		+ d.padBottom
		+ titleHeight
		+ d.pill.height
		+ d.artPx
		+ nameHeight
		+ footHeight
		+ 4 * d.gap
end

-- The grid (H:393) in a frame `width` wide with `room` base px for the two rows' faces (the lips hang below, as the
-- design's box-shadow does): boxes of face + lip, whole px. Desktop: columns 1fr 1fr 1fr 1.25fr, the six days in
-- rows of three, day 7 in the last column over both rows; the faces share the room, never under `cardFace`. Compact
-- (phones): three columns, the days at `cardFace`, day 7 the full width under them at `day7Face`.
function DailyFormat.gridLayout(
	width: number,
	room: number,
	compact: boolean,
	cardFace: number,
	day7Face: number
): GridLayout
	local gap = UI.grid.gap
	local lip, lip7 = UI.card.lip, UI.day7.lip
	local w = if finite(width) then math.max(0, width) else 0
	local cards: { Rect } = {}
	if compact then
		local columns = UI.compactColumns
		local unit = math.max(0, math.floor((w - (columns - 1) * gap) / columns))
		for i = 1, DAYS - 1 do
			local col, row = (i - 1) % columns, (i - 1) // columns
			table.insert(cards, { x = col * (unit + gap), y = row * (cardFace + gap), w = unit, h = cardFace + lip })
		end
		local rows = math.ceil((DAYS - 1) / columns)
		local top = rows * (cardFace + gap)
		return {
			cards = cards,
			day7 = { x = 0, y = top, w = w, h = day7Face + lip7 },
			height = top + day7Face + lip7,
		}
	end
	local fr = 0
	for _, share in UI.grid.columns do
		fr += share
	end
	local columns = #UI.grid.columns
	local unit = math.max(0, math.floor((w - (columns - 1) * gap) / fr))
	local share = if finite(room) then (room - gap) / 2 else 0
	local face = math.max(cardFace, math.floor(share))
	for i = 1, DAYS - 1 do
		local col, row = (i - 1) % (columns - 1), (i - 1) // (columns - 1)
		table.insert(cards, { x = col * (unit + gap), y = row * (face + gap), w = unit, h = face + lip })
	end
	local x7 = (columns - 1) * (unit + gap)
	return {
		cards = cards,
		day7 = { x = x7, y = 0, w = math.max(0, w - x7), h = 2 * face + gap + lip7 },
		height = 2 * face + gap + math.max(lip, lip7),
	}
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

-- The daily stand sign's live line (§7.7; Diego's Label_DailyTimer, FULL FINAL lobby): "READY!" or the countdown
-- alone (the plaque is small); nil while unknown (the line keeps what it shows).
function DailyFormat.signText(daily: unknown, now: number): string?
	if valid(daily) == nil or not finite(now) then
		return nil
	end
	if DailyFormat.canClaim(daily, TimeUtil.utcDay(now)) then
		return Strings.daily.ready
	end
	return DailyFormat.countdownText(now)
end

return DailyFormat
