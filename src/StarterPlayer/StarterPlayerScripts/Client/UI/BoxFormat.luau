--!strict
-- BoxFormat (client only, pure). DESIGN §6.4 (boxes, presentation contract), §6.5 (duplicate refunds), §6.10 (the
-- eligibility table and the odds disclosure items 1-7), §7.6 / §7.7 (the box counter prompt and the in-world odds
-- board), §9.11 (the reveal timeline), §18.1 (ReducedMotion), §18.6 (box.shake / box.open / reveal.<rarity> rows).
-- What BoxController shows, as plain data; every number and text comes from Boxes, Catalog, Rarity, Pricing, Config
-- and Strings (the same data the server draws from), nothing is typed here:
--   boxName(boxId) / priceText(boxId)        "Snack Box" / "400 Coins" (common.coinsAmount; box.freeOnly when free)
--   oddsRows(boxId, owned)                   §6.10 #4: one row per item in Boxes order (name, rarity text + pips,
--                                            the exact percent text "32.00%", Owned, the refund line, Inspect)
--   raritySummary(boxId) / totalText(boxId)  §6.10 #2 "Chances by rarity: Epic 6.00% · …" / #5 "Total: 100.00%"
--   openView(input)                          the area under the disclosure (§6.10 table, §11.5, §11.6), see OpenView
--   retryWait(now, retryAt, unknownAt)       seconds before Try again may be pressed (see the function)
--   revealTimes(reduced) / revealPhase(t, reduced) / wobble(t, reduced) / soundCues(rarity, reduced)
--                                            the §9.11 timeline in ms (ReducedMotion: anticipation 300 ms without
--                                            hops, then the same phases shifted earlier; the reveal is a crossfade)
--   revealSoundKey(rarity) / resultText(isDuplicate, refund)   reveal.<rarity> / "NEW!" or "Already owned: +N Coins"
--   boardText(policy, boxId)                 the in-world odds board's live line (or the restricted / unknown note)
--   oddsLines(items)                         the board's odds lines: one per rarity when its items share one weight
--                                            (spec 2026-10-09 §3.3), else one per item
--   promptKey(policy) / standScreen(policy)  the counter prompt's text key and the screen it opens (§7.6)
--   revealFromEntry(entry) / pendingReveals(unseen, skip)   the unseen-reveal replay rule (see BoxController)
--   isIndeterminate(reason)                  a BoxOpen reply that does not settle the request (retry with the same id)
--   REVEAL_PANEL / revealStageHeight(screenBaseHeight, parts, class)   Part 8: the reveal panel's 3D stage height,
--                                            the class height unless the rest of the panel (title, result info,
--                                            saving note, wrapped buttons, gaps, padding) would push the panel past
--                                            REVEAL_PANEL.heightShare of the screen (the largest text on a phone did:
--                                            about 517 base px on a 441 px tall screen); then it shrinks, never below
--                                            REVEAL_PANEL.stageMin (fix round 2: heightShare is the Boxes panel's,
--                                            less shorterBy, so on a phone the reveal ends inside the Boxes panel)
-- Foam UI restyle (spec 2026-10-09):
--   costText(boxId)                          a paid box's cost as a bare number ("400") beside the coin icon on its
--                                            card (fewer words); nil for a free-only box (it shows box.freeOnly)
--   The reveal's title is a header tab (Theme.headerTab, the box name) straddling the panel's top edge: RevealParts
--   .title is the whole tab. revealStageHeight's sum (title + 4 gaps + 2 paddings) still covers the panel with its tab
--   (half the tab above the panel, the other half and the 6 px tab gap inside its top padding, 3 gaps between the 4
--   rows, the bottom padding): about 11 base px to spare.
-- Readings (DESIGN is silent; each marked where it applies):
--   * §9.11 "3 accelerating wobbles (c 0.92 ↔ 1.06)" over 0-900 ms with box.shake at 0 / 300 / 600 (§18.6), under
--     §18.1 #4's "nothing wobbles faster than 3 Hz": each 300 ms wobble is one half-swing (squash, stretch with a small
--     hop, squash), so c swings once per 600 ms (1.7 Hz); "accelerating" = each swing stronger (WOBBLE_STRENGTH).
--   * ReducedMotion: the wobble and the hops are off (§18.1: scale pops and bounces off); the 300 ms anticipation keeps
--     its neutral glow and its three box.shake cues (sounds never change), 100 ms apart.
--   * The checking state's note is Strings.reasonText("box.checking") (Strings has the text only under reason.box).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Pricing = require(Shared.Pricing)
local Rarity = require(Shared.Rarity)
local Strings = require(Shared.Strings)

-- Types

export type OddsRow = {
	id: string, -- squishy id
	name: string,
	rarity: string, -- "Common" ... "Exclusive"
	rarityText: string, -- the rarity name ("Epic"); shown with pips and colour (§4.3)
	pips: number,
	weight: number,
	percent: string, -- Boxes.percentText: "32.00"
	percentText: string, -- "32.00%"
	owned: boolean,
	ownedText: string?, -- common.owned when owned
	refund: number, -- Pricing.duplicateRefund(boxId): a share of the box price, the same on every row (spec 2026-10-12 §8)
	refundText: string, -- box.refundLine "If you already own it: +37,500 Coins"
	inspect: boolean, -- Inspect is offered for every row, owned or not (§6.10 #4)
}

-- The reveal panel's rows other than the stage, in base px at the player's text size (revealStageHeight).
export type RevealParts = {
	title: number, -- the box name: the whole header tab (its H2 line, padding and foam bands)
	name: number, -- the squishy name (Title)
	rarity: number, -- the rarity tag
	result: number, -- "NEW!" / "Already owned: +N Coins"
	saving: number, -- the "Saving your collection…" note (reserved: it may show)
	buttons: number, -- the result buttons, wrapped (Layout.wrapRow height)
}

-- Which control the open area shows: the two-step ConfirmButton, the Try again button, the shop button, or none.
export type OpenButton = "confirm" | "retry" | "shop"

export type OpenKind =
	"open"
	| "confirm"
	| "checking"
	| "retry"
	| "shopDirect"
	| "complete"
	| "saving"
	| "needCoins"
	| "freeOnly"

export type OpenInput = {
	box: string, -- box id
	policy: string?, -- StateDelta.policy: checking / eligible / restricted / unknown (anything else = checking)
	coins: number?,
	owned: { [string]: any }?,
	savePending: boolean?, -- dataStatus.savePending (§3.11)
	inLobby: boolean?, -- false from Matched through Returning (default true)
	profileReady: boolean?, -- dataStatus.status == "ready" (default true)
	armed: boolean?, -- the ConfirmButton is waiting for its second press
	retryWaitSeconds: number?, -- seconds before Try again works again (Config.Monetization.Policy.manualRetryMinSeconds)
}

export type OpenView = {
	kind: OpenKind,
	button: OpenButton?, -- nil = no control (free-only box)
	text: string, -- the control's label (free-only: the box.freeOnly note)
	enabled: boolean,
	reason: string?, -- shown under a disabled control's label (§9.13)
	note: string?, -- the message line under the control (§6.10 "Message")
	price: number, -- the box's Coin cost (0 when free)
	missing: number, -- Coins still missing (0 when they cover the price)
	howToEarn: boolean, -- show the "How to earn Coins" text button
}

export type RevealPhase = "anticipation" | "pop" | "reveal" | "highlight" | "result"

export type RevealTimes = {
	anticipationEnd: number, -- ms from the reply
	popEnd: number,
	revealEnd: number,
	highlightEnd: number,
}

export type SoundCue = { atMs: number, key: string, variance: number? }

-- One reveal to play: from a BoxOpen reply or a StateDelta.unseenReveals entry.
export type Reveal = {
	requestId: string, -- the GUID, or "daily:<day>" for the free Treat Box
	boxId: string,
	squishyId: string,
	isDuplicate: boolean,
	refund: number,
}

-- Constants

local REVEAL = Config.Anim.boxReveal
local POLICY_STATES: { [string]: boolean } = { checking = true, eligible = true, restricted = true, unknown = true }
local LINE_BREAK = "\n"
-- reading (§9.11 gives "small hops", no number): the stretch wobble's hop at its peak, studs at gift-box scale 1.
local HOP_STUDS = 0.12
-- reading: each wobble stronger than the last ("accelerating").
local WOBBLE_STRENGTH = { 0.5, 0.75, 1 }
local SHAKE_COUNT = 3
-- The reveal sound of each rarity (§18.6); quoted so tools/check.ps1 check (f) finds every key asked for.
local REVEAL_SOUNDS: { [string]: string } = {
	Common = "reveal.common",
	Uncommon = "reveal.uncommon",
	Epic = "reveal.epic",
	Exclusive = "reveal.exclusive",
}
local SOUND_SHAKE = "box.shake"
local SOUND_OPEN = "box.open"
-- Reply reasons that do not settle a BoxOpen (no answer, or the request never reached the server): the next press
-- reuses the same requestId, so the server returns the stored result instead of opening a second box (§3.4).
local INDETERMINATE: { [string]: boolean } = {
	["error.generic"] = true,
	["error.connect"] = true,
	["net.rateLimited"] = true,
	["net.invalid"] = true,
}
local REQUEST_ID_PATTERN = "^%x+%-%x+%-%x+%-%x+%-%x+$"
local DAILY_ID_PATTERN = "^daily:%d+$"
-- The reveal panel (base px; BoxController builds it). Readings: the width and the two stage heights are Part 7's; the
-- panel is alone and centred, so it may use heightShare of the screen; stageMin keeps a stage a phone player can tap
-- (about 100 actual px at scale 0.85, like InspectPanel_Test's floor).
-- Fix batch (2026-10-09): the outlined rarity tag and result chip touched with infoGap 2 and the result buttons read
-- as one joined button at 6, so infoGap is 6 and the buttons have their own buttonGap 10 (both counted below).
-- Fix round 2 (2026-10-09): on a phone the reveal was as tall as the Boxes panel behind it, so the two outlines doubled
-- up at the corners. The reveal now keeps within the Boxes panel's share (0.88, was 0.94) less shorterBy (15 base =
-- 12.75 px at the phone's 0.85), and stageMin is 88 (75 px at 0.85; was 120, the reading above): on phones the stage
-- sits at its minimum, so the panel ends inside the Boxes one. Still a stage that shows the squishy and takes the tap.
local REVEAL_PANEL = {
	width = 560,
	stage = 340,
	stageCompact = 200,
	stageMin = 88,
	heightShare = 0.88,
	shorterBy = 15,
	padding = 12, -- Theme.Padding.medium
	gap = 6, -- Theme.Padding.small, between the panel's rows
	infoGap = 6, -- between the name, the rarity tag and the result line
	buttonGap = 10, -- between the result buttons (and their rows when they wrap)
}

-- Module table

local BoxFormat = {}

BoxFormat.REVEAL_SOUNDS = REVEAL_SOUNDS
BoxFormat.SOUND_SHAKE = SOUND_SHAKE
BoxFormat.SOUND_OPEN = SOUND_OPEN
BoxFormat.REVEAL_PANEL = REVEAL_PANEL

-- Private

local function finite(n: unknown): boolean
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function wholeCoins(n: unknown): number
	if not finite(n) then
		return 0
	end
	return math.max(0, math.floor(n :: number))
end

local function textOf(key: string?): string
	if key == nil then
		return ""
	end
	return Strings.resolve(key) or key
end

local function rarityName(rarity: string): string
	local info = Rarity.get(rarity)
	return if info then textOf(info.nameKey) else rarity
end

local function squishyName(id: string): string
	local def = Catalog.get(id)
	return if def then textOf(def.nameKey) else id
end

local function coinsText(coins: number): string
	return Strings.format(Strings.common.coinsAmount, { coins = Format.coins(coins) })
end

local function percentText(percent: string): string
	return Strings.format(Strings.common.percent, { value = percent })
end

-- Public: the disclosure ---------------------------------------------------------------------------------------------

function BoxFormat.boxName(boxId: string): string
	local box = Boxes.get(boxId)
	return if box then textOf(box.nameKey) else boxId
end

-- §6.10 #1: the price ("400 Coins"); a free-only box shows box.freeOnly instead (it can never be bought).
function BoxFormat.priceText(boxId: string): string
	local box = Boxes.get(boxId)
	local cost = if box then box.cost else nil
	if box == nil or cost == nil or not box.paid then
		return Strings.box.freeOnly
	end
	return coinsText(cost)
end

-- A paid box's cost as a bare number ("400", Format.coins) for its card, beside the coin icon; nil for a free-only box.
function BoxFormat.costText(boxId: string): string?
	local box = Boxes.get(boxId)
	local cost = if box then box.cost else nil
	if box == nil or cost == nil or not box.paid then
		return nil
	end
	return Format.coins(wholeCoins(cost))
end

-- §6.10 #4: one row per item, in Boxes order. `owned` is profile.owned (squishyId -> entry).
function BoxFormat.oddsRows(boxId: string, owned: { [string]: any }?): { OddsRow }
	local have = owned or {}
	local rows: { OddsRow } = {}
	local refund = Pricing.duplicateRefund(boxId)
	for _, odds in Boxes.odds(boxId) do
		local def = Catalog.get(odds.id)
		local rarity = if def then def.rarity else ""
		local info = Rarity.get(rarity)
		local isOwned = have[odds.id] ~= nil
		table.insert(rows, {
			id = odds.id,
			name = squishyName(odds.id),
			rarity = rarity,
			rarityText = rarityName(rarity),
			pips = if info then info.pips else 0,
			weight = odds.weight,
			percent = odds.text,
			percentText = percentText(odds.text),
			owned = isOwned,
			ownedText = if isOwned then Strings.common.owned else nil,
			refund = refund,
			refundText = Strings.format(Strings.box.refundLine, { coins = Format.coins(refund) }),
			inspect = true,
		})
	end
	return rows
end

-- §6.10 #2: "Chances by rarity: Epic 6.00% · Uncommon 30.00% · Common 64.00%" (rarity descending, Boxes.byRarity).
function BoxFormat.raritySummary(boxId: string): string
	local parts: { string } = {}
	for _, row in Boxes.byRarity(boxId) do
		table.insert(
			parts,
			Strings.format(Strings.box.rarityChance, { rarity = rarityName(row.rarity), percent = row.text })
		)
	end
	return Strings.format(Strings.box.chancesByRarity, { list = table.concat(parts, Strings.box.listSeparator) })
end

-- §6.10 #5: "Total: 100.00%".
function BoxFormat.totalText(boxId: string): string
	return Strings.format(Strings.box.total, { percent = Boxes.totalText(boxId) or Boxes.percentText(0) })
end

-- Public: the open area (§6.10 table, §11.5, §11.6) --------------------------------------------------------------------

-- What the area under the disclosure shows. Order: free-only, then the policy (restricted, unknown, anything but
-- eligible = checking), then the profile (not ready, save pending), complete, the lobby lock, the Coins, the armed
-- confirm, open.
function BoxFormat.openView(input: OpenInput): OpenView
	local box = Boxes.get(input.box)
	local cost = if box then box.cost else nil
	local price = if cost then wholeCoins(cost) else 0
	local coins = wholeCoins(input.coins)
	local missing = math.max(0, price - coins)
	local openText = Strings.format(Strings.box.openButton, { cost = Format.coins(price) })
	local view: OpenView = {
		kind = "open",
		button = "confirm",
		text = openText,
		enabled = false,
		reason = nil,
		note = nil,
		price = price,
		missing = missing,
		howToEarn = false,
	}
	if box == nil or cost == nil or not box.paid then
		view.kind = "freeOnly"
		view.button = nil
		view.text = Strings.box.freeOnly
		return view
	end
	local policy = if type(input.policy) == "string" and POLICY_STATES[input.policy] then input.policy else "checking"
	if policy == "restricted" then
		view.kind = "shopDirect"
		view.button = "shop"
		view.text = Strings.box.shopDirect
		view.enabled = true
		view.note = Strings.box.restrictedNote
		return view
	elseif policy == "unknown" then
		local wait = if finite(input.retryWaitSeconds) then math.ceil(input.retryWaitSeconds :: number) else 0
		view.kind = "retry"
		view.button = "retry"
		view.text = Strings.common.tryAgain
		view.enabled = wait <= 0
		view.reason = if wait > 0 then Strings.format(Strings.common.secondsShort, { seconds = wait }) else nil
		view.note = Strings.box.unknownNote
		return view
	elseif policy ~= "eligible" then
		view.kind = "checking"
		view.text = Strings.box.checkingButton
		view.note = Strings.reasonText("box.checking")
		return view
	end
	if input.profileReady == false then
		view.reason = Strings.data.loadFailed
		return view
	end
	if input.savePending == true then
		view.kind = "saving"
		view.reason = Strings.reasonText("box.saving")
		return view
	end
	if Boxes.isComplete(input.box, input.owned or {}) and not Config.Economy.AllowOpenWhenComplete then
		view.kind = "complete"
		view.reason = Strings.reasonText("box.complete")
		return view
	end
	if input.inLobby == false then
		view.reason = Strings.common.lockedInDuel
		return view
	end
	if missing > 0 then
		view.kind = "needCoins"
		view.reason = Strings.format(
			Strings.plural(missing, Strings.box.needCoins.one, Strings.box.needCoins.many),
			{ missing = Format.coins(missing) }
		)
		view.howToEarn = true
		return view
	end
	view.enabled = true
	if input.armed == true then
		view.kind = "confirm"
		view.text = Strings.format(Strings.spend.confirm, { price = Format.coins(price) })
		view.note = Strings.format(Strings.spend.balanceAfter, { balance = Format.coins(coins - price) })
	end
	return view
end

-- Seconds before Try again may be pressed (OpenInput.retryWaitSeconds; 0 = now). The server takes a PolicyRetry only
-- >= minSeconds (Config.Monetization.Policy.manualRetryMinSeconds) after its LAST policy check (§2.8), automatic join
-- checks included, and drops an early one silently; the client cannot see that time, so it waits minSeconds from the
-- later of its own last press (`retryAt`) and the moment the "unknown" state arrived (`unknownAt`): both come at or
-- after a server check (Part 7 review fix: counting only the press let the first press after "unknown" be dropped,
-- then greyed the button for 30 s). Times are one client clock (os.clock); nil anchors are ignored.
function BoxFormat.retryWait(now: number, retryAt: number?, unknownAt: number?, minSeconds: number?): number
	local span = if finite(minSeconds) then minSeconds :: number else Config.Monetization.Policy.manualRetryMinSeconds
	local function left(at: number?): number
		return if finite(at) then span - (now - (at :: number)) else 0
	end
	return math.max(0, left(retryAt), left(unknownAt))
end

-- True once the reveal's result buttons may take a press: `guardMs` (Config.Anim.boxReveal.resultInputGuardMs) after
-- they appeared at `shownAt` (os.clock seconds). They take Skip's place, so the press that skipped would otherwise land
-- on one of them (Part 8 acceptance fix). No anchor yet = open; a bad guard counts as none.
function BoxFormat.resultInputOpen(shownAt: number?, now: number, guardMs: number?): boolean
	if not finite(shownAt) or not finite(now) then
		return true
	end
	local guard = if finite(guardMs) and (guardMs :: number) > 0 then guardMs :: number else 0
	return (now - (shownAt :: number)) * 1000 >= guard - 1e-6 -- float slack: 10.35 - 10 is 349.9999... ms
end

-- The box.needCoins text for `missing` Coins (the ConfirmButton's reason line).
function BoxFormat.needCoinsText(missing: number): string
	local n = wholeCoins(missing)
	return Strings.format(Strings.plural(n, Strings.box.needCoins.one, Strings.box.needCoins.many), {
		missing = Format.coins(n),
	})
end

-- Public: the reveal timeline (§9.11) -----------------------------------------------------------------------------------

-- The phase boundaries in ms after the reply. ReducedMotion: anticipation reducedMotionAnticipationMs, the rest keeps
-- its durations, shifted earlier by the difference.
function BoxFormat.revealTimes(reduced: boolean): RevealTimes
	local anticipation = if reduced then REVEAL.reducedMotionAnticipationMs else REVEAL.anticipationEndMs
	local shift = REVEAL.anticipationEndMs - anticipation
	return {
		anticipationEnd = anticipation,
		popEnd = REVEAL.popEndMs - shift,
		revealEnd = REVEAL.revealEndMs - shift,
		highlightEnd = REVEAL.highlightEndMs - shift,
	}
end

-- The phase at `tMs` and the progress inside it (0..1; the result phase reports 1).
function BoxFormat.revealPhase(tMs: number, reduced: boolean): (RevealPhase, number)
	local times = BoxFormat.revealTimes(reduced)
	local t = if finite(tMs) then math.max(0, tMs) else 0
	local function progress(from: number, to: number): number
		return if to > from then math.clamp((t - from) / (to - from), 0, 1) else 1
	end
	if t < times.anticipationEnd then
		return "anticipation", progress(0, times.anticipationEnd)
	elseif t < times.popEnd then
		return "pop", progress(times.anticipationEnd, times.popEnd)
	elseif t < times.revealEnd then
		return "reveal", progress(times.popEnd, times.revealEnd)
	elseif t < times.highlightEnd then
		return "highlight", progress(times.revealEnd, times.highlightEnd)
	end
	return "result", 1
end

-- The anticipation wobble at `tMs`: (c, hop) = the gift box's scale on its up axis (the other axes get 1/√c) and its
-- hop in studs at scale 1. (1, 0) outside the anticipation and under ReducedMotion. See the header's reading: three
-- half-swings (squash, stretch with a hop, squash), each stronger, c always within [wobbleCMin, wobbleCMax].
function BoxFormat.wobble(tMs: number, reduced: boolean): (number, number)
	if reduced or not finite(tMs) then
		return 1, 0
	end
	local total = REVEAL.anticipationEndMs
	if tMs <= 0 or tMs >= total then
		return 1, 0
	end
	local count = math.max(1, REVEAL.anticipationWobbles)
	local window = total / count
	local index = math.min(count - 1, math.floor(tMs / window))
	local u = (tMs - index * window) / window
	local strength = WOBBLE_STRENGTH[math.min(index + 1, #WOBBLE_STRENGTH)] or 1
	local wave = math.sin(math.pi * u) * strength
	if index % 2 == 0 then
		return 1 - (1 - REVEAL.wobbleCMin) * wave, 0
	end
	return 1 + (REVEAL.wobbleCMax - 1) * wave, HOP_STUDS * wave
end

-- The reveal's sounds (§18.6): box.shake at each wobble (0 / 300 / 600 ms; 0 / 100 / 200 under ReducedMotion), box.open
-- at the pop, reveal.<rarity> at the reveal. box.open and reveal.* play with no pitch variation.
function BoxFormat.soundCues(rarity: string, reduced: boolean): { SoundCue }
	local times = BoxFormat.revealTimes(reduced)
	local cues: { SoundCue } = {}
	for i = 0, SHAKE_COUNT - 1 do
		table.insert(cues, { atMs = times.anticipationEnd * i / SHAKE_COUNT, key = SOUND_SHAKE })
	end
	table.insert(cues, { atMs = times.anticipationEnd, key = SOUND_OPEN, variance = 0 })
	table.insert(cues, { atMs = times.popEnd, key = BoxFormat.revealSoundKey(rarity), variance = 0 })
	return cues
end

-- reveal.<rarity> for the server's rarity (the Common sound for anything unknown).
function BoxFormat.revealSoundKey(rarity: string): string
	return REVEAL_SOUNDS[rarity] or REVEAL_SOUNDS.Common
end

-- "NEW!" or "Already owned: +{coins} Coins" (§9.11 rarity highlight).
function BoxFormat.resultText(isDuplicate: boolean, refund: number): string
	if isDuplicate then
		return Strings.format(Strings.box.revealDuplicate, { coins = Format.coins(wholeCoins(refund)) })
	end
	return Strings.box.revealNew
end

-- Public: the world (§7.6, §7.7) ---------------------------------------------------------------------------------------

-- The odds board's lines for a box's items, in item order (spec 2026-10-09 §3.3: 13 lines would crowd the 7×8-stud
-- board). A rarity with two or more items that all share one weight is one box.boardGroupLine at its first item
-- ("Common 64.00% — 16.00% each: Toast, Banana, …"), so every item's chance is still shown; any other item keeps its
-- own box.boardLine.
function BoxFormat.oddsLines(items: { Boxes.BoxItem }): { string }
	local groups: { [string]: { total: number, weight: number, same: boolean, names: { string } } } = {}
	for _, entry in items do
		local def = Catalog.get(entry.id)
		if def then
			local group = groups[def.rarity]
			if group == nil then
				group = { total = 0, weight = entry.weight, same = true, names = {} }
				groups[def.rarity] = group
			end
			group.total += entry.weight
			group.same = group.same and entry.weight == group.weight
			table.insert(group.names, squishyName(entry.id))
		end
	end
	local lines: { string } = {}
	local written: { [string]: boolean } = {}
	for _, entry in items do
		local def = Catalog.get(entry.id)
		local rarity = if def then def.rarity else ""
		local group = groups[rarity]
		if group and group.same and #group.names > 1 then
			if not written[rarity] then
				written[rarity] = true
				table.insert(
					lines,
					Strings.format(Strings.box.boardGroupLine, {
						rarity = rarityName(rarity),
						total = Boxes.percentText(group.total),
						each = Boxes.percentText(group.weight),
						names = table.concat(group.names, Strings.box.boardNameSeparator),
					})
				)
			end
		else
			table.insert(
				lines,
				Strings.format(Strings.box.boardLine, {
					name = squishyName(entry.id),
					rarity = if def then rarityName(rarity) else "",
					percent = Boxes.percentText(entry.weight),
				})
			)
		end
	end
	return lines
end

-- The odds board's live line: box.restrictedNote / box.unknownNote, else box.boardHeader and the box's oddsLines
-- (checking shows the odds too: §6.10 "Odds list: shown" in every state).
function BoxFormat.boardText(policy: string?, boxId: string): string
	if policy == "restricted" then
		return Strings.box.restrictedNote
	elseif policy == "unknown" then
		return Strings.box.unknownNote
	end
	local box = Boxes.get(boxId)
	if box == nil then
		return ""
	end
	local name = textOf(box.nameKey)
	local lines: { string } = {}
	local cost = box.cost
	if cost ~= nil and box.paid then
		table.insert(lines, Strings.format(Strings.box.boardHeader, { box = name, cost = Format.coins(cost) }))
	else
		table.insert(lines, name)
	end
	for _, line in BoxFormat.oddsLines(box.items) do
		table.insert(lines, line)
	end
	return table.concat(lines, LINE_BREAK)
end

-- The counter prompt's text key (§7.6): "Shop Squishies" for restricted AND unknown, else "See Boxes".
function BoxFormat.promptKey(policy: string?): string
	if policy == "restricted" or policy == "unknown" then
		return "prompt.shopDirect"
	end
	return "prompt.seeBoxes"
end

-- The screen the counter opens: the shop (filtered to the stand's box) for restricted and unknown, else the boxes.
function BoxFormat.standScreen(policy: string?): string
	return if BoxFormat.promptKey(policy) == "prompt.shopDirect" then "shop" else "boxes"
end

-- Public: replies and the unseen-reveal replay ------------------------------------------------------------------------

-- True for a BoxOpen reply reason that does not settle the request (retry with the same requestId).
function BoxFormat.isIndeterminate(reason: string?): boolean
	return reason == nil or INDETERMINATE[reason] == true
end

-- A Reveal from a StateDelta.unseenReveals entry (a boxLog entry with seen = false), or nil when it is malformed.
function BoxFormat.revealFromEntry(entry: unknown): Reveal?
	if type(entry) ~= "table" then
		return nil
	end
	local e = entry :: { [string]: any }
	local req, box, squishy = e.req, e.box, e.squishy
	if type(req) ~= "string" or #req > 40 then
		return nil
	end
	if string.match(req, REQUEST_ID_PATTERN) == nil and string.match(req, DAILY_ID_PATTERN) == nil then
		return nil
	end
	if type(box) ~= "string" or Boxes.get(box) == nil or not Catalog.isValidId(squishy) then
		return nil
	end
	return {
		requestId = req,
		boxId = box,
		squishyId = squishy :: string,
		isDuplicate = e.dup == true,
		refund = wholeCoins(e.refund),
	}
end

-- The unseen reveals to queue, in list order: valid entries whose requestId `skip(requestId)` does not exclude (in
-- flight from this client, already played this session, or already queued), each requestId once.
function BoxFormat.pendingReveals(unseen: unknown, skip: (requestId: string) -> boolean): { Reveal }
	local list: { Reveal } = {}
	if type(unseen) ~= "table" then
		return list
	end
	local seen: { [string]: boolean } = {}
	for _, entry in unseen :: { any } do
		local reveal = BoxFormat.revealFromEntry(entry)
		if reveal and not seen[reveal.requestId] and not skip(reveal.requestId) then
			seen[reveal.requestId] = true
			table.insert(list, reveal)
		end
	end
	return list
end

-- Part 8: the reveal panel's stage height -------------------------------------------------------------------------------

-- The 3D stage's height (base px) in the reveal panel on a screen `screenBaseHeight` base px tall: the class height
-- (REVEAL_PANEL.stage, or stageCompact when `class` is "compact") unless the panel's other rows (`parts`, with the gaps
-- and padding) leave less room under REVEAL_PANEL.heightShare of the screen less shorterBy (fix round 2: inside the
-- Boxes panel behind it); never below REVEAL_PANEL.stageMin.
function BoxFormat.revealStageHeight(screenBaseHeight: number, parts: RevealParts, class: string): number
	local maxStage = if class == "compact" then REVEAL_PANEL.stageCompact else REVEAL_PANEL.stage
	local function px(n: number): number
		return if finite(n) and n > 0 then n else 0
	end
	local info = px(parts.name) + px(parts.rarity) + px(parts.result) + 2 * REVEAL_PANEL.infoGap
	-- Five rows (title, stage, info, saving, buttons): four gaps, and the padding above and below.
	local other = px(parts.title)
		+ info
		+ px(parts.saving)
		+ px(parts.buttons)
		+ 4 * REVEAL_PANEL.gap
		+ 2 * REVEAL_PANEL.padding
	local height = if finite(screenBaseHeight) and screenBaseHeight > 0 then screenBaseHeight else 0
	local room = math.floor(height * REVEAL_PANEL.heightShare - REVEAL_PANEL.shorterBy - other)
	return math.clamp(room, REVEAL_PANEL.stageMin, maxStage)
end

return BoxFormat
