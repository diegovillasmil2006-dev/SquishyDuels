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
--   revealSoundKey(rarity) / resultText(isDuplicate, refund)   reveal.<rarity> / "NEW!" or the duplicate line
--                                            "Already in your collection · +N Coins" (PR21)
--   boardText(policy, boxId)                 the in-world odds board's live line (or the restricted / unknown note)
--   oddsLines(items)                         the board's odds lines: one per rarity when its items share one weight
--                                            (spec 2026-10-09 §3.3), else one per item
--   promptKey(policy) / standScreen(policy)  the counter prompt's text key and the screen it opens (§7.6)
--   revealFromEntry(entry) / pendingReveals(unseen, skip)   the unseen-reveal replay rule (see BoxController)
--   isIndeterminate(reason)                  a BoxOpen reply that does not settle the request (retry with the same id)
-- Foam UI restyle (spec 2026-10-09):
--   costText(boxId)                          a paid box's cost as a bare number ("400") beside the coin icon on its
--                                            card (fewer words); nil for a free-only box (it shows box.freeOnly)
-- UI FINAL R7 (plan work/ui/PLAN.md R7; `H:n` = "Squishy Duels HUD.dc.html" line n, `stage:n` = its
-- uploads/box-stage.html line n; numbers in Config.UI.Boxes and Config.Anim.boxReveal):
--   the window: cardColumns(inner, count, selected, gap, minFr) (H:262, PR20: the selected card 2fr, sideways scroll
--   when the row does not fit), cardLayout(height, parts) (the plate and the tiles in a short body), cardOdds(boxId)
--   (H:271: one row per rarity, lowest first, the exact percent, the bar max(minPct, p)%), toyTiles(boxId, owned, max)
--   (H:945: rarest first), tilesThatFit(width), subtitleShown(owned) (H:260, FD5);
--   the reveal: revealStart() / revealAdvance(state, dt, tapped, replied) / revealSkip(state) (the drop, the idle and
--   its three taps, the burst once the reply is in, the result idle; stage:254-332, G7.20), the curves bounceOut,
--   elastic, dropPose, idlePose, lidTarget, boxExit, toyPose, resultBob, beamPose, wavePose, seamAlpha, spring,
--   flashAlpha (PR16), soundCue(event, rarity) (§18.6, RL8), the §9.15 frame ledger budgetFree / budgetTake with
--   burstPieces / rainPieces (PR18), and orbitStart / orbitStep / orbitEye (stage:45-48, T14).
-- Readings (DESIGN is silent; each marked where it applies):
--   * The checking state's note is Strings.reasonText("box.checking") (Strings has the text only under reason.box).
--   * A third tap before the BoxOpen reply holds the box in its idle (its last tap's shake) until the reply (G7.20).

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

-- UI FINAL R7: the card row (cardColumns), a card's vertical parts (cardLayout), its odds rows and toy tiles.
export type CardColumns = { fr: number, widths: { number }, total: number, scroll: boolean }
export type CardParts = {
	name: number, -- the box name's line (base px)
	odds: number, -- the odds rows block
	tiles: number, -- the toy tiles' row
	open: number, -- OPEN's face and lip
}
export type CardLayout = { plate: number, tiles: boolean }
export type CardOdds = { rarity: string, text: string, share: number }
export type ToyTile = { id: string, owned: boolean }

-- UI FINAL R7: the reveal's timeline (revealAdvance) and its events, the orbit, the frame ledger.
export type RevealStage = "drop" | "idle" | "open" | "inspect"
export type RevealState = {
	phase: RevealStage,
	t: number, -- seconds in the drop / the idle, or since the burst (open and inspect)
	total: number, -- seconds since the drop began (the idle waves)
	taps: number, -- 0..Config.Anim.boxReveal.taps
	auto: number, -- seconds since the last tap (the automatic tap at autoTapS)
	held: boolean, -- the last tap came before the BoxOpen reply: the burst waits for it
}
export type RevealEvent = { kind: "land" | "tap" | "burst" | "ready", tap: number? } -- tap: 0, 1, 2 (H:812's j)
export type SoundEvent = "land" | "tap" | "burst" | "reveal" | "close"
export type SoundCue = { key: string, pitch: number?, variance: number?, delayMs: number? }
export type Orbit = { theta: number, phi: number, radius: number, dTheta: number, dPhi: number, auto: boolean }
export type OrbitInput = {
	dragX: number?, -- px moved this frame
	dragY: number?,
	height: number?, -- the stage's height in px (a drag of one height turns 2 pi)
	zoom: number?, -- wheel ticks (+ in) or a pinch's scale change
	padX: number?, -- the right stick, -1..1
	padY: number?,
}
export type Ledger = { { n: number, untilS: number } }

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
local BOXES_UI = Config.UI.Boxes
local BURST = Config.UI.Fx.events.boxBurst
local POLICY_STATES: { [string]: boolean } = { checking = true, eligible = true, restricted = true, unknown = true }
local LINE_BREAK = "\n"
local SOUND_LAND = "ui.click" -- RL8: the design's stamp (lib:184) is a low ui.click (REVEAL.landPitch)
local SOUND_CLOSE = "ui.pop" -- H:835: NICE! / the close
local PHI_EPSILON = 1e-6 -- OrbitControls' polar limits keep the camera off the poles
local DAMPING_FPS = 60 -- OrbitControls damps once a frame at 60 fps
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

-- Module table

local BoxFormat = {}

BoxFormat.REVEAL_SOUNDS = REVEAL_SOUNDS
BoxFormat.SOUND_SHAKE = SOUND_SHAKE
BoxFormat.SOUND_OPEN = SOUND_OPEN

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

-- Public: the Boxes window (UI FINAL R7) --------------------------------------------------------------------------------

-- H:262 + PR20: the widths of `count` cards on a row `inner` base px wide with `gap` between them. The selected card
-- (index `selected`) is 2fr + gap (its own card column as wide as the others, the stats well beside it), the others
-- 1fr; fr is never under `minFr`, and `scroll` says the row is then wider than `inner` (it scrolls sideways).
function BoxFormat.cardColumns(inner: number, count: number, selected: number, gap: number, minFr: number): CardColumns
	local n = math.max(1, math.floor(if finite(count) then count else 1))
	local g = if finite(gap) then math.max(0, gap) else 0
	local room = if finite(inner) then math.max(0, inner) else 0
	local fr = math.max(if finite(minFr) then minFr else 0, (room - n * g) / (n + 1))
	local widths: { number } = {}
	for i = 1, n do
		widths[i] = if i == selected then 2 * fr + g else fr
	end
	local total = (n + 1) * fr + n * g
	return { fr = fr, widths = widths, total = total, scroll = total > room + 0.5 }
end

-- A card `height` base px tall (its face and lip, H:264): the plate's height and whether the toy tiles show. The
-- plate takes what the other parts leave, at most Config.UI.Boxes.card.plate; under plateMin the tiles go first, then
-- the plate (readings: a short phone body keeps the name, the odds and OPEN).
function BoxFormat.cardLayout(height: number, parts: CardParts): CardLayout
	local card = BOXES_UI.card
	local h = if finite(height) then height else 0
	local function px(n: number): number
		return if finite(n) and n > 0 then n else 0
	end
	-- padding and border twice, the lip, and the column gaps between plate, name, odds, tiles and OPEN
	local frame = 2 * (card.pad + card.border) + card.lip
	local without = frame + px(parts.name) + px(parts.odds) + px(parts.open) + 3 * card.gap
	local withTiles = without + px(parts.tiles) + card.gap
	local function plateFor(used: number): number
		return math.min(card.plate, math.floor(h - used))
	end
	if plateFor(withTiles) >= card.plateMin then
		return { plate = plateFor(withTiles), tiles = true }
	elseif plateFor(without) >= card.plateMin then
		return { plate = plateFor(without), tiles = false }
	end
	return { plate = 0, tiles = false }
end

-- H:271 (lib:44-46 odds): one row per rarity in the box, lowest first, with the exact percent ("80.00%") and the bar's
-- share max(minPct, p) / 100.
function BoxFormat.cardOdds(boxId: string): { CardOdds }
	local rows = Boxes.byRarity(boxId)
	local list: { CardOdds } = {}
	for i = #rows, 1, -1 do
		local row = rows[i]
		table.insert(list, {
			rarity = row.rarity,
			text = percentText(row.text),
			share = math.clamp(math.max(BOXES_UI.odds.minPct, row.percent) / 100, 0, 1),
		})
	end
	return list
end

-- H:945: the box's items rarest first (item order inside a rarity), at most `max`, each with whether it is owned (a
-- silhouette when not, H:948).
function BoxFormat.toyTiles(boxId: string, owned: { [string]: any }?, max: number?): { ToyTile }
	local box = Boxes.get(boxId)
	local have = owned or {}
	local ranked: { { id: string, rank: number, order: number } } = {}
	for order, entry in (if box then box.items else {}) :: { Boxes.BoxItem } do
		local def = Catalog.get(entry.id)
		table.insert(ranked, { id = entry.id, rank = if def then Rarity.index(def.rarity) or 0 else 0, order = order })
	end
	table.sort(ranked, function(a, b): boolean
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.order < b.order
	end)
	local limit = if finite(max) then math.max(0, math.floor(max :: number)) else BOXES_UI.toys.max
	local tiles: { ToyTile } = {}
	for _, item in ranked do
		if #tiles >= limit then
			break
		end
		table.insert(tiles, { id = item.id, owned = have[item.id] ~= nil })
	end
	return tiles
end

-- How many toy tiles fit a column `width` base px wide (H:273: 42 px apart by 4), never more than toys.max.
function BoxFormat.tilesThatFit(width: number): number
	local toys = BOXES_UI.toys
	local w = if finite(width) then width else 0
	return math.clamp(math.floor((w + toys.gap) / (toys.tile + toys.gap)), 0, toys.max)
end

-- H:260 (FD5): the band's subtitle shows while a box can still give a new squishy.
function BoxFormat.subtitleShown(owned: { [string]: any }?): boolean
	for _, box in Boxes.list() do
		if not Boxes.isComplete(box.id, owned or {}) then
			return true
		end
	end
	return false
end

-- Public: the reveal (UI FINAL R7; stage:254-342) -----------------------------------------------------------------------

function BoxFormat.revealStart(): RevealState
	return { phase = "drop", t = 0, total = 0, taps = 0, auto = 0, held = false }
end

-- One frame (`dt` seconds) of the reveal's timeline (stage:254-263, 301-332): the drop lands after dropMs; in the idle
-- each tap (`tapped`: the player's, this frame) or an automatic one every autoTapS advances ONE tap (never a skip); the
-- last tap bursts, but only once the BoxOpen reply is in (`replied`, G7.20; before it the box is held in its idle);
-- resultAtS after the burst the result idle begins ("ready"). Changes `state`; returns this frame's events in order.
function BoxFormat.revealAdvance(state: RevealState, dt: number, tapped: boolean, replied: boolean): { RevealEvent }
	local events: { RevealEvent } = {}
	local step = if finite(dt) then math.max(0, dt) else 0
	state.total += step
	state.t += step
	local function burst()
		state.phase = "open"
		state.t = 0
		state.held = false
		table.insert(events, { kind = "burst" })
	end
	if state.phase == "drop" then
		if state.t >= REVEAL.dropMs / 1000 then
			state.phase = "idle"
			state.t = 0
			state.auto = 0
			table.insert(events, { kind = "land" })
		end
	elseif state.phase == "idle" then
		if state.held then
			if replied then
				burst()
			end
		else
			state.auto += step
			if tapped or state.auto > REVEAL.autoTapS then
				state.taps += 1
				state.auto = 0
				table.insert(events, { kind = "tap", tap = state.taps - 1 })
				if state.taps >= REVEAL.taps then
					if replied then
						burst()
					else
						state.held = true
					end
				end
			end
		end
	elseif state.phase == "open" then
		if state.t > REVEAL.resultAtS then
			state.phase = "inspect"
			table.insert(events, { kind = "ready" })
		end
	end
	return events
end

-- Skip (PR21): straight to the result idle with every move done (the caller checks the reply is in).
function BoxFormat.revealSkip(state: RevealState)
	state.phase = "inspect"
	state.taps = REVEAL.taps
	state.held = false
	state.auto = 0
	state.t = math.max(REVEAL.resultAtS, REVEAL.toy.fromS + REVEAL.toy.growS, REVEAL.coins.lifeS)
end

-- stage:286: easeOutBounce (n 7.5625, d 2.75; Roblox's Bounce Out).
function BoxFormat.bounceOut(x: number): number
	local n, d = 7.5625, 2.75
	local u = math.clamp(if finite(x) then x else 0, 0, 1)
	if u < 1 / d then
		return n * u * u
	elseif u < 2 / d then
		u -= 1.5 / d
		return n * u * u + 0.75
	elseif u < 2.5 / d then
		u -= 2.25 / d
		return n * u * u + 0.9375
	end
	u -= 2.625 / d
	return n * u * u + 0.984375
end

-- stage:287: the design's elastic out (not Roblox's): 2^(-10x) sin((10x - .75) 2 pi / 3) + 1, 0 at 0, 1 from 1.
function BoxFormat.elastic(x: number): number
	if not finite(x) or x <= 0 then
		return 0
	elseif x >= 1 then
		return 1
	end
	return 2 ^ (-10 * x) * math.sin((x * 10 - 0.75) * (2 * math.pi / 3)) + 1
end

-- stage:302-303: the drop `t` seconds in: the box's height (units), yaw (radians) and the floor blob's scale and alpha.
function BoxFormat.dropPose(t: number): (number, number, number, number)
	local k = math.clamp((if finite(t) then t else 0) / (REVEAL.dropMs / 1000), 0, 1)
	local floor = REVEAL.floor
	return REVEAL.dropHeight * (1 - BoxFormat.bounceOut(k)),
		REVEAL.restYaw + (1 - k) * math.pi * REVEAL.dropTurns,
		floor.from + k * (1 - floor.from),
		k
end

-- stage:306-308: the idle's bob (units, added to the hop), roll (radians) and yaw at `total` seconds after `taps` taps.
function BoxFormat.idlePose(total: number, taps: number): (number, number, number)
	local idle = REVEAL.idle
	local time = if finite(total) then total else 0
	local w = idle.roll + taps * idle.rollPerTap
	return math.sin(time * idle.bobRate) * idle.bobY,
		math.sin(time * (idle.rollRate + taps * idle.rollRatePerTap)) * w,
		REVEAL.restYaw + math.sin(time * REVEAL.idleYaw.rate) * REVEAL.idleYaw.amp
end

-- stage:309, 320: where the lid spring aims: ajar by taps in the idle, open after the burst ("royal" opens less).
function BoxFormat.lidTarget(phase: RevealStage, taps: number, kind: string?): number
	local lid = REVEAL.lid
	if phase == "open" or phase == "inspect" then
		return if kind == "royal" then lid.openRoyal else lid.open
	end
	return lid.rest + taps * lid.perTap
end

-- stage:324-325: the box's exit `t` seconds after the burst: its scale factor, whether it spins and whether it is gone.
function BoxFormat.boxExit(t: number): (number, boolean, boolean)
	local exit = REVEAL.exit
	local sk = math.clamp(((if finite(t) then t else 0) - exit.fromS) / exit.spanS, 0, 1)
	if sk >= 1 then
		return 0, false, true
	elseif sk <= 0 then
		return 1, false, false
	end
	return math.max(0.001, (1 + math.sin(sk * math.pi) * exit.swell) * (1 - sk * sk)), true, false
end

-- stage:326: true once the exit is far enough for its poof.
function BoxFormat.exitPoofs(t: number): boolean
	local exit = REVEAL.exit
	return math.clamp(((if finite(t) then t else 0) - exit.fromS) / exit.spanS, 0, 1) >= exit.poofAt
end

-- stage:327-330: the squishy `t` seconds after the burst: its scale (a share of its fit, the elastic), its centre's
-- height (units), its yaw (radians, 3 pi -> 0) and its opacity (0 -> 1 over toyFadeS).
function BoxFormat.toyPose(t: number): (number, number, number, number)
	local toy = REVEAL.toy
	local time = if finite(t) then t else 0
	local tk = math.clamp((time - toy.fromS) / toy.growS, 0, 1)
	return math.max(0.001, BoxFormat.elastic(tk)),
		toy.y + math.min(1, tk * toy.riseRate) * toy.rise,
		(1 - math.min(1, tk * toy.spinRate)) * math.pi * toy.spins,
		math.clamp((time - toy.fromS) / REVEAL.toyFadeS, 0, 1)
end

-- stage:328: the result idle's bob (units) at `total` seconds.
function BoxFormat.resultBob(total: number): number
	return math.sin((if finite(total) then total else 0) * REVEAL.resultBob.rate) * REVEAL.resultBob.amp
end

-- stage:323: the beam `t` seconds after the burst: its width and height factors and its alpha.
function BoxFormat.beamPose(t: number): (number, number, number)
	local beam = REVEAL.beam
	local time = if finite(t) then t else 0
	local bk = math.clamp(time / beam.growS, 0, 1)
	return 0.2 + bk * 0.9, 0.01 + bk, beam.alpha * (1 - math.clamp((time - beam.fadeFromS) / beam.fadeS, 0, 1))
end

-- stage:342: the floor ring wave at `w` (0..1, w += rate / s): its scale and alpha (gone at 1).
function BoxFormat.wavePose(w: number): (number, number)
	local wave = REVEAL.wave
	local u = if finite(w) then w else 1
	if u >= 1 then
		return wave.from + wave.grow, 0
	end
	return wave.from + math.max(0, u) * wave.grow, wave.alpha * (1 - math.max(0, u))
end

-- stage:311: Royal's seam glow alpha at `total` seconds after `taps` taps.
function BoxFormat.seamAlpha(total: number, taps: number): number
	local seam = REVEAL.seam
	local time = if finite(total) then total else 0
	return math.clamp(seam.base + taps * seam.perTap + math.sin(time * seam.rate) * seam.wave, 0, 1)
end

-- stage:294-295: one step of x'' = -k (x - target) - c x' (semi-implicit Euler, as the design): the new x and x'.
function BoxFormat.spring(x: number, v: number, target: number, k: number, c: number, dt: number): (number, number)
	local a = -k * (x - target) - c * v
	local nv = v + a * dt
	return x + nv * dt, nv
end

-- PR16: the burst's flash alpha `ms` after it: the design's 0 -> .85 at 10% -> 0 over 700 ms with `ease` on the whole
-- run (H:822), drawn under Config.Vfx.Flash: the peak at most maxOverlayOpacity, never before minPeakMs.
function BoxFormat.flashAlpha(ms: number, ease: (number) -> number): number
	local flash = BOXES_UI.reveal.flash
	local cap = Config.Vfx.Flash
	local t = if finite(ms) then ms else flash.ms
	if t <= 0 or t >= flash.ms then
		return 0
	end
	local peak = math.min(flash.designPeak, cap.maxOverlayOpacity)
	-- the peak's place on the eased run: the design's 10%, or later so it is reached at minPeakMs at the earliest
	local at = math.max(flash.designPeakAt, ease(math.clamp(cap.minPeakMs / flash.ms, 0, 1)))
	local p = ease(t / flash.ms)
	if p < at then
		return peak * p / at
	end
	return peak * math.max(0, 1 - (p - at) / (1 - at))
end

-- §18.6 / RL8: each reveal moment's sound: the landing's low stamp, a tap's rattle (box.shake), the burst's pop
-- (box.open), reveal.<rarity> revealDelayMs later (H:827-828), the close's pop (H:835).
function BoxFormat.soundCue(event: SoundEvent, rarity: string?): SoundCue
	if event == "land" then
		return { key = SOUND_LAND, pitch = REVEAL.landPitch }
	elseif event == "tap" then
		return { key = SOUND_SHAKE }
	elseif event == "burst" then
		return { key = SOUND_OPEN, variance = 0 }
	elseif event == "reveal" then
		return { key = BoxFormat.revealSoundKey(rarity or ""), variance = 0, delayMs = REVEAL.revealDelayMs }
	end
	return { key = SOUND_CLOSE }
end

-- §9.15 / PR18: the animated UI frames still free at `now` (seconds) out of `total`, given the ledger of what is alive.
function BoxFormat.budgetFree(ledger: Ledger, now: number, total: number): number
	local used = 0
	for _, entry in ledger do
		if entry.untilS > now then
			used += entry.n
		end
	end
	return math.max(0, total - used)
end

-- Takes up to `want` frames for `lifeS` seconds from `now`: records them and returns how many were granted.
function BoxFormat.budgetTake(ledger: Ledger, now: number, want: number, lifeS: number, total: number): number
	for i = #ledger, 1, -1 do
		if ledger[i].untilS <= now then
			table.remove(ledger, i)
		end
	end
	local n =
		math.min(math.max(0, math.floor(if finite(want) then want else 0)), BoxFormat.budgetFree(ledger, now, total))
	if n > 0 then
		table.insert(ledger, { n = n, untilS = now + math.max(0, lifeS) })
	end
	return n
end

-- PR18 (H:829): the burst's pieces for the rarity `rarity`: 30 + 12 x its index (Common 0), within the free frames
-- and Config.UI.Fx.events.boxBurst.maxPieces.
function BoxFormat.burstPieces(rarity: string, free: number): number
	local idx = (Rarity.index(rarity) or 1) - 1
	return math.max(0, math.min(BURST.sparks.n + BURST.perRarity * idx, BURST.maxPieces, math.floor(free)))
end

-- PR18 (H:830): the rain once the burst's pieces are gone: Epic and Exclusive only, within the free frames.
function BoxFormat.rainPieces(rarity: string, free: number): number
	local idx = (Rarity.index(rarity) or 1) - 1
	local rain = BURST.rarityRain
	if idx < rain.fromRarity then
		return 0
	end
	return math.max(0, math.min(rain.n + rain.perRarity * idx, math.floor(free)))
end

-- stage:44, 248: the orbit at the design's camera (the eye around the target, OrbitControls' spherical angles).
function BoxFormat.orbitStart(): Orbit
	local offset = REVEAL.camera.eye - REVEAL.camera.target
	local radius = offset.Magnitude
	return {
		theta = math.atan2(offset.X, offset.Z),
		phi = math.acos(math.clamp(offset.Y / radius, -1, 1)),
		radius = radius,
		dTheta = 0,
		dPhi = 0,
		auto = false,
	}
end

-- T14 (stage:45-48): one frame of the orbit: a drag turns it (2 pi per stage height), the right stick turns it, the
-- wheel / pinch zooms (zoomStep per tick, the distance in [minDist, maxDist] units), the turntable adds
-- autoRotateDegS while `auto`; the turn eases out with OrbitControls' damping (per 60 fps frame).
function BoxFormat.orbitStep(orbit: Orbit, dt: number, input: OrbitInput?): Orbit
	local o = REVEAL.orbit
	local step = if finite(dt) then math.max(0, dt) else 0
	local i: OrbitInput = input or {}
	local height = if finite(i.height) and (i.height :: number) > 0 then i.height :: number else 1
	local dTheta = orbit.dTheta - 2 * math.pi * (i.dragX or 0) / height
	local dPhi = orbit.dPhi - 2 * math.pi * (i.dragY or 0) / height
	dTheta -= (i.padX or 0) * o.padTurnRadS * step
	dPhi -= (i.padY or 0) * o.padTurnRadS * step
	if orbit.auto then
		dTheta -= math.rad(o.autoRotateDegS) * step
	end
	local share = 1 - (1 - o.damping) ^ (step * DAMPING_FPS)
	local zoom = i.zoom or 0
	local radius = orbit.radius * (if zoom ~= 0 then o.zoomStep ^ zoom else 1)
	return {
		theta = orbit.theta + dTheta * share,
		phi = math.clamp(orbit.phi + dPhi * share, PHI_EPSILON, math.pi - PHI_EPSILON),
		radius = math.clamp(radius, o.minDist, o.maxDist),
		dTheta = dTheta * (1 - share),
		dPhi = dPhi * (1 - share),
		auto = orbit.auto,
	}
end

-- The orbit's eye in the design's units (OrbitControls: from the target along its spherical angles).
function BoxFormat.orbitEye(orbit: Orbit): Vector3
	local s = math.sin(orbit.phi)
	return REVEAL.camera.target
		+ Vector3.new(s * math.sin(orbit.theta), math.cos(orbit.phi), s * math.cos(orbit.theta)) * orbit.radius
end

-- reveal.<rarity> for the server's rarity (the Common sound for anything unknown).
function BoxFormat.revealSoundKey(rarity: string): string
	return REVEAL_SOUNDS[rarity] or REVEAL_SOUNDS.Common
end

-- "NEW!", or the duplicate line (H:492) "Already in your collection" with our refund after it (PR21:
-- "· +{coins} Coins" when there is one).
function BoxFormat.resultText(isDuplicate: boolean, refund: number): string
	if isDuplicate then
		local coins = wholeCoins(refund)
		if coins > 0 then
			return Strings.box.revealDuplicate
				.. Strings.box.listSeparator
				.. Strings.format(Strings.box.revealRefund, { coins = Format.coins(coins) })
		end
		return Strings.box.revealDuplicate
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

return BoxFormat
