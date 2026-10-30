--!strict
-- BoxController (client only). DESIGN §6.4 (boxes, presentation contract), §6.10 (paid random items: the policy table and
-- the odds disclosure items 1-7), §7.6 / §7.7 (the box counter prompt and the in-world odds board), §9.11 (the box
-- reveal), §9.15 (1 viewport, <= 24 UI frames), §11.1-§11.6 (Boxes screen, states, focus, spend confirmation), §18.1
-- (ReducedMotion), §18.6 (box.shake / box.open / reveal.<rarity>). Words and numbers come from UI/BoxFormat (pure).
-- The client only sends intents (a box id and a request id); the server decides the price, the policy, the draw and
-- the save (§6.1, §12). Lobby only: UIController refuses and closes both screens from Matched through
-- Returning (lobbyOnly), and the reveal queue waits for the lobby.
--
-- UI FINAL R7 (Diego's Boxes window and box reveal, plan work/ui/PLAN.md R7; `H:n` = "Squishy Duels HUD.dc.html"
-- line n; the window frame is R3's):
-- * "boxes" (modal, registered in init so the HUD Boxes button appears): the design's window (Theme.window "boxes",
--   H:255-287: the cyan band "SQUISHY BOXES" with the subtitle "Every box can hold a new squishy" while a box can
--   still give a new squishy, H:260 / FD5; the sticker; the 76 px X), its body (H:262: padding 22 24 26, gap 20) the
--   three design cards (UI/BoxCard, H:264-278: the plate with the rays and the floating box art, the name, one odds row
--   per rarity with the exact percent, the toy tiles, OPEN with its price pill). PR20: the selected card is 2fr and
--   carries §6.10 items 3-6 on its right in the design's stats well (H:236: "What's inside & chances", one row per item
--   in the odds-row look with its toy tile, the exact percent, Owned and Inspect; the note and the
--   status; "Total: 100.00%"; the footer); an unselected card's OPEN selects it first (L1 / R1 cycle too). A row too
--   narrow for minFr cards scrolls sideways (with its scroll bar). Compact: box.details shows / hides items 3-5 in the
--   well (items 1, 2 and 6 stay).
-- * OPEN on the selected card (PR13): eligible -> the design's confirm dialog (UI/Components/ConfirmDialog: the box art
--   in the medallion, the box name, "Balance after", BUY with the coin and the price); its BUY starts the reveal at once
--   and sends BoxOpen (G7.20: no wait before the drop). Not enough Coins (P11) -> OPEN keeps its green face, its price
--   StickerPriceShort; a press plays ui.error and the shake (Button's off state), then HudController.denyCoins (the
--   pill's shake and "Not enough coins!", whose tap is "How to earn Coins": the Waypoint to the Squeeze mat). The other
--   §6.10 states stay on the selected card's Open area: checking (disabled "Checking…" + the note), unknown (Try again,
--   fires PolicyRetry, disabled with the seconds left until Config.Monetization.Policy.manualRetryMinSeconds after the
--   later of the last press and the arrival of "unknown", BoxFormat.retryWait), the Treat Box (box.freeOnly, no Open),
--   Toy Box full (pens3 phase 5, reason.inventory.full) / saving / duel / profile not ready (disabled with the reason).
--   No Robux upsell and no Coin Store link anywhere here (§6.10). Pens3 phase 5, restricted accounts (the fixed order,
--   never random, D1:235): OPEN works as for eligible ones, the card shows the next squishy first (BoxFormat.openView's
--   nextText from the boxOrder state field, BoxCard's stand-in line) and the reveal has no AGAIN (the next squishy is
--   seen on the card before every open).
-- * BoxOpen: a new HttpService GUID per open, reused on the next open when the last reply did not settle the request
--   (BoxFormat.isIndeterminate); NetController.invokeAsync("BoxOpen", boxId, requestId) while the reveal already plays.
--   A refusal closes the reveal (unseen, unacknowledged) and toasts its reason (NotifyController.showResult:
--   common.noCoinsSpent only when charged == false). No reply after Config.UI.Boxes.stillCheckingSeconds, or an
--   error.generic reply: box.stillChecking, and the outcome comes from the unseen reveals (below); the client never
--   claims a result itself.
-- * Reveal ("boxReveal", modal, over Boxes or on its own): UI/BoxReveal draws it in its own full-screen layer
--   (Config.UI.Boxes.reveal.layer, between SD_Modal and the confirm dialog's SD_Prompt); the screen's own root is an
--   empty placeholder in SD_Modal (the modal stack, the lobby lock, Back and the focus stay UIController's). Skip (PR21:
--   the reset pill, bottom right, from 0 ms, the gamepad's first focus) and Backspace / ButtonB while it animates jump to
--   the result with the identical result; a tap on the box advances one tap. At the result: EQUIP (when the squishy is
--   not equipped; not on a preview), AGAIN (a paid box: short of Coins -> deny; else the confirm dialog over the reveal,
--   whose BUY closes it and opens the next 40 ms later, H:1020), NICE! (closes it with ui.pop, H:835), a tap on the
--   squishy = Inspect (params {squishyId, owned = true, source = "boxReveal"}; the stage keeps the model for it), drag /
--   wheel / pinch to look around. SoundController.duck("boxReveal") until the result. A duplicate is a copy for the pen
--   (pens3 phase 5: no Coins come back). AckReveal(requestId) is sent once per reveal when its result is on screen;
--   closing or skipping never calls a reward remote.
-- * Unseen replay (one rule for rejoin, the day-7 Treat Box "daily:<day>" and the BoxOpen timeout): every
--   StateController unseenReveals entry whose requestId is not in this client's in-flight BoxOpen set and was not played
--   this session is queued and played one at a time (BoxFormat.pendingReveals). debugHoldReveals(true) pauses the
--   unseen ones (reply reveals still play).
-- * World: WorldBinder.registerStand("SD_BoxStand"): eligible / checking / restricted (pens3 phase 5) open "boxes" on
--   the stand's BoxId box; unknown opens "shop" filtered to it (the boxes screen when no shop exists). Like
--   QueueController does for its podium, the prompt is relabelled locally from its SD_TextKey / SD_AltTextKey
--   ("See Boxes" / "Shop Squishies",
--   BoxFormat.promptKey) and Diego's odds sign plaques (Label_OddsCommon / Rare / Legend in the stand's Hub prop) show
--   BoxFormat.signLines, on policy changes, stream-in and once a second.
-- Readings (DESIGN is silent):
--   * A reveal closed by a match before its result is not acknowledged: it plays again after the duel (still unseen).
--     Any other close counts as seen (AckReveal), like a skip. While it animates, Backspace / ButtonB skip to the result
--     (a UIController.pushBack handler) instead of closing it unseen; at the result they close it.
--   * No result before the reveal (§9.11 "no fake-outs"; Part 7 review fix): StateController holds each new unseen
--     result (the odds rows, Squishies and the NEW badge do not show the new squishy) until ack() releases it at the
--     result or on a close counted as seen; PenController keeps the own pen as it was while the reveal plays (a copy
--     walks in once it closes). A reveal closed by a match keeps its hold (Config.UI.Boxes.revealHoldMaxSeconds at
--     most).
--   * Reveals wait while Inspect is open (the two share the one viewport stage); init pumps again when Inspect closes.
-- Studio: debugRevealPreview(id) queues a local reveal of the squishy (source "preview": no remote, no grant, no hold,
-- nothing acknowledged; no EQUIP or AGAIN) in a box that holds it (snack otherwise).
-- History kept from the Candy UI: each box keeps its own colour on its plate (lib:44-46 now), the reveal's escalation is
-- the design's own FX (UiFx's design effects replace BOX_LOOK's tiers, plan §2.1).
-- Stable names: Boxes_CloseButton, Boxes_Box_<id> (with Boxes_OpenButton / Boxes_RetryButton),
-- Boxes_DetailsButton, Boxes_Row_<i> (with Boxes_InspectButton); Reveal_SkipButton, Reveal_EquipButton,
-- Reveal_AgainButton, Reveal_NiceButton; the dialog's Confirm_BuyButton / Confirm_CancelButton.

-- Services

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Boxes = require(Shared.Boxes)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local BoxCard = require(Client.UI.BoxCard)
local BoxFormat = require(Client.UI.BoxFormat)
local BoxReveal = require(Client.UI.BoxReveal)
local Button = require(Client.UI.Components.Button)
local ConfirmDialog = require(Client.UI.Components.ConfirmDialog)
local Create = require(Client.UI.Create)
local IconGlyph = require(Client.UI.Components.IconGlyph)
local KeyText = require(Client.UI.KeyText)
local Layout = require(Client.UI.Layout)
local RarityTag = require(Client.UI.Components.RarityTag)
local SquishyImage = require(Client.UI.Components.SquishyImage)
local Theme = require(Client.UI.Theme)
local ViewportStage = require(Client.UI.ViewportStage)
local Waypoint = require(Client.UI.Waypoint)
local HudController = require(script.Parent.HudController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)
local WorldBinder = require(script.Parent.WorldBinder)

-- Types

-- A stats well row (§6.10 item 4, PR20).
type Row = {
	root: Frame,
	tile: SquishyImage.SquishyImage,
	name: TextLabel,
	rarity: RarityTag.RarityTag,
	percent: TextLabel,
	owned: TextLabel,
	inspect: Button.Button,
	squishyId: string?,
}

-- The selected card's stats well (§6.10 items 3-6) and the window's other parts.
type Well = {
	root: ScrollingFrame,
	details: Button.Button,
	heading: TextLabel,
	rows: Frame,
	note: TextLabel,
	status: TextLabel,
	total: TextLabel,
	footer: TextLabel,
	subtitle: TextLabel,
	cards: ScrollingFrame,
}

type QueueEntry = {
	reveal: BoxFormat.Reveal?, -- nil while the BoxOpen reply is on its way (a pending open's reveal)
	boxId: string,
	requestId: string,
	source: "reply" | "unseen" | "preview",
	savePending: boolean,
}

type Run = {
	entry: QueueEntry,
	view: BoxReveal.Run,
	acked: boolean,
	equipped: boolean,
	duckRelease: (() -> ())?,
	popBack: (() -> ())?, -- while animating, Backspace / ButtonB skip instead of closing (UIController.pushBack)
}

-- Constants

local SCREEN = "boxes"
local REVEAL_SCREEN = "boxReveal"
local SHOP_SCREEN = "shop"
local SQUISHIES_SCREEN = "squishies" -- owner 2026-10-22: buying squishies with Coins happens there
local INSPECT_SCREEN = "inspect"
local MODAL_GUI = "SD_Modal"
local STAND_TAG = "SD_BoxStand"
local ATTR_BOX_ID = WorldLayout.Attributes.BoxId
local ATTR_TEXT_KEY = "SD_TextKey"
local ATTR_ALT_TEXT_KEY = "SD_AltTextKey"
local SIGN_PLAQUES = { "Label_OddsCommon", "Label_OddsRare", "Label_OddsLegend" } -- Diego's OddsSign, top to bottom
local PLAQUE_TEXT = "Text" -- the TextLabel his Labels.build puts in each plaque's LabelGui
local SHOP_PROMPT_KEY = "prompt.shopDirect"
local SQUEEZE_WAYPOINT = "squeeze"
local HANDOFF_REASON = "inspect"
local INSPECT_SOURCE = "boxReveal"
local EQUIPPED_TOAST = "inspect.equippedToast"
local GENERIC = "error.generic"
local POLICY_UNKNOWN = "unknown"
local ROOT_PART = "HumanoidRootPart"
local SOUND_BACK = "ui.back" -- H:886: the confirm dialog's CANCEL / scrim
local TOUCH = Config.UI.Touch
local RETRY_SECONDS = Config.Monetization.Policy.manualRetryMinSeconds
local STILL_CHECKING_SECONDS = Config.UI.Boxes.stillCheckingSeconds
local BOXES_UI = Config.UI.Boxes
local REVEAL_UI = BOXES_UI.reveal
local CONFIRM = Config.UI.confirm
local WINDOW_KIND = "boxes" -- UI FINAL R3: the Boxes window's Config.UI.Sticker.window kind (H:255-287)
local WINDOW_BORDER = Config.UI.Sticker.border.heavy
local WAYPOINT_MAX_SECONDS = 120
local WAYPOINT_CHECK_SECONDS = 0.5
local WORLD_REFRESH_SECONDS = 1
local TICK_SECONDS = 1 -- the open area's countdowns (Try again)
local ROW_TILE = BOXES_UI.toys.tile
local ROW_GAP = 8 -- H:271: the odds row's gap
local MAX_HEIGHT_SHARE = 0.88

-- Module table

local BoxController = {}

-- Private

local log = Log.new("Boxes")
local cleanup: Cleanup.Cleanup? = nil
local openCleanup: Cleanup.Cleanup? = nil
local panel: Frame? = nil
local loadingLabel: TextLabel? = nil
local body: Frame? = nil
local cards: { [string]: BoxCard.BoxCard } = {}
local rows: { Row } = {}
local well: Well? = nil
local selectedBox: string = "snack"
local listShown = true -- the selected card's "What's inside & chances" list; a tap on that card hides / shows it
local detailsOpen = false
local retryAt: number? = nil -- os.clock() of the last Try again
local unknownAt: number? = nil -- os.clock() when the policy state last became "unknown" (BoxFormat.retryWait)
local statusText: string? = nil
local statusRequest: string? = nil
local opening: { boxId: string, requestId: string }? = nil
local pendingIds: { [string]: string } = {} -- boxId -> requestId to reuse on the next open
local inFlight: { [string]: boolean } = {}
local played: { [string]: boolean } = {}
local queuedIds: { [string]: boolean } = {}
local queue: { QueueEntry } = {}
local holdReveals = false
local current: Run? = nil
local starting: QueueEntry? = nil
local waypoint: Waypoint.Handle? = nil
local lastResult: { [string]: any }? = nil
local dialog: ConfirmDialog.ConfirmDialog? = nil
local popDialogBack: (() -> ())? = nil
local layoutNow: () -> () = function() end -- the window's layout (build sets it)
local wellWidth = 0 -- the well's inner width as laid out last (base px)
local layoutWell: (width: number) -> () -- the well's rows for its width (defined with the builders)

-- Runs `fn` in pcall; a failure is logged under `label`. Returns whether it ran without an error.
local function guarded(label: string, fn: () -> ()): boolean
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		log:error(`{label} failed:`, err)
	end
	return ok
end

local function firstPaidBox(): string
	for _, box in Boxes.list() do
		if box.paid then
			return box.id
		end
	end
	return Boxes.List[1].id
end

local function validBox(id: unknown): string?
	if type(id) == "string" and Boxes.get(id) ~= nil then
		return id
	end
	return nil
end

local function standBoxId(stand: Instance): string
	return validBox(stand:GetAttribute(ATTR_BOX_ID)) or firstPaidBox()
end

local function retryWait(): number
	return BoxFormat.retryWait(os.clock(), retryAt, unknownAt, RETRY_SECONDS)
end

local function coins(): number
	return StateController.coins() or 0
end

-- The Open area's view of `boxId` (default the selected box).
local function currentView(boxId: string?): BoxFormat.OpenView
	local status = StateController.dataStatus()
	return BoxFormat.openView({
		box = boxId or selectedBox,
		policy = StateController.get("policy"),
		coins = StateController.coins(),
		owned = StateController.owned(),
		savePending = status ~= nil and status.savePending,
		inLobby = not StateController.isLobbyLocked(),
		profileReady = StateController.isProfileReady(),
		armed = false, -- UI FINAL R7: the confirm dialog is the second step (PR13)
		retryWaitSeconds = retryWait(),
		pen = StateController.get("pen"), -- pens3 phase 5: the Toy Box full block
		boxOrder = StateController.get("boxOrder"), -- pens3 phase 5: a restricted account's next squishy
	})
end

local function clearWaypoint()
	if waypoint then
		waypoint:destroy()
		waypoint = nil
	end
end

local function rootPosition(): Vector3?
	local player = Players.LocalPlayer
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild(ROOT_PART) else nil
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- "How to earn Coins": a waypoint to the nearest Squeeze mat, removed once reached, after WAYPOINT_MAX_SECONDS or when a
-- match starts.
local function showEarnWaypoint()
	clearWaypoint()
	local target = WorldLayout.waypoint(SQUEEZE_WAYPOINT)
	if target == nil then
		return
	end
	local handle = Waypoint.show(target)
	waypoint = handle
	local startedAt = os.clock()
	task.spawn(function()
		while waypoint == handle do
			task.wait(WAYPOINT_CHECK_SECONDS)
			if waypoint ~= handle then
				return
			end
			local position = rootPosition()
			if
				(position and Waypoint.shouldHide(position, target))
				or os.clock() - startedAt > WAYPOINT_MAX_SECONDS
			then
				clearWaypoint()
			end
		end
	end)
end

-- P11 / G7.16: a spend the Coins do not cover (the press already played ui.error and the shake): the pill's shake and
-- "Not enough coins!", whose tap is "How to earn Coins" (it closes the Boxes screen and shows the Waypoint).
local function deny()
	HudController.denyCoins(function()
		UIController.close(SCREEN, "howToEarn")
		if UIController.isOpen(REVEAL_SCREEN) then
			UIController.close(REVEAL_SCREEN, "howToEarn")
		end
		showEarnWaypoint()
	end)
end

-- The Boxes screen ----------------------------------------------------------------------------------------------------

local function setStatus(text: string?, requestId: string?)
	statusText = text
	statusRequest = requestId
end

local function refreshRows()
	local w = well
	if w == nil then
		return
	end
	local list = BoxFormat.oddsRows(selectedBox, StateController.owned())
	local inspectable = UIController.isRegistered(INSPECT_SCREEN)
	for index, row in rows do
		local data = list[index]
		row.root.Visible = data ~= nil
		if data then
			row.squishyId = data.id
			row.tile:setCatalogId(data.id)
			row.tile:setOwned(data.owned)
			row.name.Text = data.name
			row.rarity:setRarity(data.rarity)
			row.percent.Text = data.percentText
			row.owned.Text = data.ownedText or ""
			row.owned.Visible = data.ownedText ~= nil
			row.inspect.root.Visible = inspectable and data.inspect
		else
			row.squishyId = nil
		end
	end
end

local function refresh()
	local root = panel
	if root == nil then
		return
	end
	local loaded = StateController.isLoaded()
	if loadingLabel then
		loadingLabel.Visible = not loaded
	end
	if body then
		body.Visible = loaded
	end
	local owned = StateController.owned()
	for id, card in cards do
		card:paint(currentView(id), owned)
	end
	local w = well
	if w then
		w.subtitle.Visible = BoxFormat.subtitleShown(owned)
		local compact = UIController.layoutClass() == "compact"
		local showList = not compact or detailsOpen
		w.details.root.Visible = compact
		w.heading.Visible = showList
		w.rows.Visible = showList
		w.total.Visible = showList
		w.total.Text = BoxFormat.totalText(selectedBox)
		local view = currentView()
		local note = if view.kind == "freeOnly" then nil else view.note
		w.note.Text = note or ""
		w.note.Visible = note ~= nil
		w.status.Text = statusText or ""
		w.status.Visible = statusText ~= nil
		refreshRows()
		if wellWidth > 0 then
			layoutWell(wellWidth) -- the rows' texts changed: their measured sizes follow
		end
	end
	local run = current
	if run then
		local box = Boxes.get(run.entry.boxId)
		run.view:setAgainOff(box ~= nil and box.cost ~= nil and coins() < box.cost)
	end
end

local function selectBox(id: string)
	if id == selectedBox and listShown then
		return
	end
	listShown = true
	selectedBox = id
	if statusRequest == nil or pendingIds[id] ~= statusRequest then
		setStatus(nil, nil)
	end
	layoutNow()
	refresh()
end

local function cycleBox(direction: number)
	local list = Boxes.list()
	local index = 1
	for i, box in list do
		if box.id == selectedBox then
			index = i
		end
	end
	local nextIndex = (index - 1 + direction) % #list + 1
	selectBox(list[nextIndex].id)
end

-- A tap on a card (owner 2026-10-17): another box shows its list; the open box's list hides, then shows again.
local function tapBox(id: string)
	if id == selectedBox and listShown then
		listShown = false
		layoutNow()
		refresh()
	else
		selectBox(id)
	end
end

-- Reveals ------------------------------------------------------------------------------------------------------------

local pump: () -> ()
local openPaid: (boxId: string) -> { [string]: any }

local function enqueue(entry: QueueEntry, front: boolean)
	local id = entry.requestId
	if entry.reveal == nil or queuedIds[id] or played[id] then
		return
	end
	queuedIds[id] = true
	if front then
		table.insert(queue, 1, entry)
	else
		table.insert(queue, entry)
	end
end

local function entryOf(
	reveal: BoxFormat.Reveal,
	source: "reply" | "unseen" | "preview",
	savePending: boolean
): QueueEntry
	return {
		reveal = reveal,
		boxId = reveal.boxId,
		requestId = reveal.requestId,
		source = source,
		savePending = savePending,
	}
end

-- Queues every unseen reveal that is not in flight, not played this session and not queued yet (§3.11 replay).
local function scanUnseen()
	local list = BoxFormat.pendingReveals(StateController.get("unseenReveals"), function(id: string): boolean
		return inFlight[id] == true or played[id] == true or queuedIds[id] == true
	end)
	for _, reveal in list do
		enqueue(entryOf(reveal, "unseen", false), false)
	end
	pump()
end

-- Seen: AckReveal once, and StateController shows the result it held back until now (the new squishy in owned and as
-- NEW; reveal holds, Part 7 review fix).
local function ack(run: Run)
	local reveal = run.entry.reveal
	if run.acked or reveal == nil then
		return
	end
	run.acked = true
	if run.entry.source == "preview" then
		return -- a Studio preview: no remote, nothing held
	end
	NetController.fire("AckReveal", reveal.requestId)
	StateController.releaseReveal(reveal.requestId)
end

-- Ends what the animation holds: the music duck (§11.9) and the back handler (Back skips while animating).
local function releaseHolds(run: Run)
	local release = run.duckRelease
	if release then
		run.duckRelease = nil
		release()
	end
	local popBack = run.popBack
	if popBack then
		run.popBack = nil
		popBack()
	end
end

-- The result is on screen (BoxReveal): the holds end, then AckReveal.
local function reachedResult(run: Run)
	releaseHolds(run)
	ack(run)
end

-- Skip / Backspace / ButtonB / ButtonA while animating: the result with the identical result. False when nothing runs.
local function skip(): boolean
	local run = current
	if run == nil or run.view:isFinal() then
		return false
	end
	return run.view:skip()
end

local function closeDialog()
	local d = dialog
	dialog = nil
	local pop = popDialogBack
	popDialogBack = nil
	if pop then
		pop()
	end
	if d then
		d:close()
	end
end

-- The design's confirm dialog for a coin spend on `boxId` (PR13: OPEN, AGAIN): the box art, its name, "Balance after",
-- BUY with the coin and the price; BUY closes it and runs `onBuy` at once.
local function openConfirm(boxId: string, onBuy: () -> ())
	local box = Boxes.get(boxId)
	local cost = if box then box.cost else nil
	if box == nil or cost == nil or dialog ~= nil then
		return
	end
	local price: number = cost
	local key = BoxCard.artKey(boxId)
	local d = ConfirmDialog.open({
		layer = UIController.screenGui(CONFIRM.layerName, CONFIRM.layer),
		title = BoxFormat.boxName(boxId),
		description = ConfirmDialog.balanceText(coins(), price),
		price = price,
		picture = function(parent: Frame, sizePx: number)
			IconGlyph.image(key, { name = "Box", sizePx = sizePx, parent = parent })
		end,
		scale = UIController.scale(),
		trackScale = UIController.trackScale,
		onBuy = function()
			closeDialog()
			onBuy()
		end,
		onCancel = function(reason: string)
			dialog = nil
			local pop = popDialogBack
			popDialogBack = nil
			if pop then
				pop()
			end
			if reason ~= "back" then
				SoundController.play(SOUND_BACK) -- UIController.back plays it for Backspace / ButtonB
			end
		end,
	})
	dialog = d
	popDialogBack = UIController.pushBack(function()
		d:cancel("back")
	end)
end

local function equipRevealed()
	local run = current
	local reveal = if run then run.entry.reveal else nil
	if run == nil or reveal == nil or run.equipped then
		return
	end
	run.view:setEquip("loading")
	local result = NetController.equipSquishyAsync(reveal.squishyId)
	if current ~= run then
		return
	end
	if result.ok then
		run.equipped = true
		run.view:setEquip("equipped")
		NotifyController.show(EQUIPPED_TOAST, nil, "success")
	else
		run.view:setEquip("normal")
		local reason = result.reason
		local known = type(reason) == "string" and reason ~= GENERIC and KeyText.has("reason." .. reason)
		UIController.toast(
			if known then Strings.reasonText(reason) else Strings.inspect.equipFailed,
			"warn",
			{ sound = "ui.error" }
		)
	end
end

-- AGAIN (H:1020): short of Coins -> deny; else the confirm dialog over the reveal; its BUY closes this reveal at once
-- and opens the next one againDelayMs later.
local function again()
	local run = current
	if run == nil then
		return
	end
	local boxId = run.entry.boxId
	local box = Boxes.get(boxId)
	if box == nil or box.cost == nil then
		return
	end
	if coins() < box.cost then
		deny()
		return
	end
	openConfirm(boxId, function()
		UIController.close(REVEAL_SCREEN, "again")
		task.delay(REVEAL_UI.againDelayMs / 1000, function()
			openPaid(boxId)
		end)
	end)
end

local function startRun(entry: QueueEntry): boolean
	local box = Boxes.get(entry.boxId)
	local reveal = entry.reveal
	local preview = entry.source == "preview"
	local run: Run
	local ok, result = pcall(function(): BoxReveal.Run
		return BoxReveal.start({
			layer = UIController.screenGui(REVEAL_UI.layerName, REVEAL_UI.layer),
			safeArea = UIController.screenGui(MODAL_GUI),
			boxId = entry.boxId,
			reveal = reveal,
			savePending = entry.savePending,
			canEquip = not preview,
			equipped = reveal ~= nil and StateController.equipped() == reveal.squishyId,
			-- pens3 phase 5: no AGAIN for a fixed order (restricted): its card shows the next squishy before each open
			againPrice = if box
					and box.paid
					and not preview
					and StateController.get("policy") == "eligible"
				then box.cost
				else nil,
			againOff = box ~= nil and box.cost ~= nil and coins() < box.cost,
			inspectable = UIController.isRegistered(INSPECT_SCREEN),
			scale = UIController.scale(),
			trackScale = UIController.trackScale,
			sound = function(cue: BoxFormat.SoundCue)
				-- The fancier reveal: the first of the cue's key and its fallbacks that has an id plays.
				local key = cue.key
				if not SoundController.hasSound(key) then
					for _, fallback in cue.fallbacks or {} do
						if SoundController.hasSound(fallback) then
							key = fallback
							break
						end
					end
				end
				SoundController.play(key, { pitch = cue.pitch, variance = cue.variance })
			end,
			onResult = function()
				if current == run then
					reachedResult(run)
				end
			end,
			onEquip = function()
				equipRevealed()
			end,
			onAgain = function()
				again()
			end,
			onNice = function()
				UIController.close(REVEAL_SCREEN, "nice")
			end,
			onInspect = function()
				local id = if run.entry.reveal then (run.entry.reveal :: BoxFormat.Reveal).squishyId else nil
				if id == nil then
					return
				end
				-- The stage keeps the squishy for Inspect (§9.11 "hands the same model to Inspect without rebuilding").
				UIController.close(REVEAL_SCREEN, HANDOFF_REASON)
				UIController.open(INSPECT_SCREEN, { squishyId = id, owned = true, source = INSPECT_SOURCE })
			end,
			onSkip = function()
				skip()
			end,
		})
	end)
	if not ok then
		log:warn("reveal could not start:", result)
		played[entry.requestId] = true -- not retried this session (it stays unseen for the next one)
		return false
	end
	run = {
		entry = entry,
		view = result,
		acked = false,
		equipped = false,
		duckRelease = SoundController.duck("boxReveal"),
		popBack = nil,
	}
	current = run
	if reveal then
		played[entry.requestId] = true
	end
	if statusRequest == entry.requestId then
		setStatus(nil, nil)
		refresh()
	end
	-- Reading: while the reveal animates, Backspace / ButtonB skip to the result (like Skip) instead of closing it
	-- unseen; at the result they close it as usual.
	run.popBack = UIController.pushBack(function()
		if current == run then
			skip()
		end
	end)
	return true
end

-- Plays the next queued reveal when nothing is playing, the lobby is free and the screen exists. Unseen reveals wait
-- while debugHoldReveals is on. Part 6: reveals also wait while Inspect is open (the two share the one viewport stage,
-- and a reveal opened over a lone Inspect would destroy its model); init pumps again when Inspect closes.
pump = function()
	if current ~= nil or starting ~= nil or StateController.isLobbyLocked() then
		return
	end
	if UIController.isOpen(INSPECT_SCREEN) then
		return
	end
	if not UIController.isRegistered(REVEAL_SCREEN) then
		return
	end
	local index: number? = nil
	for i, entry in queue do
		if not (holdReveals and entry.source == "unseen") then
			index = i
			break
		end
	end
	if index == nil then
		return
	end
	local entry = table.remove(queue, index) :: QueueEntry
	queuedIds[entry.requestId] = nil
	if played[entry.requestId] then
		pump()
		return
	end
	starting = entry
	local opened = UIController.open(REVEAL_SCREEN, { requestId = entry.requestId })
	starting = nil
	if not opened or current == nil then
		if current == nil then
			-- Refused (e.g. a match just started): back to the front of the queue.
			enqueue(entry, true)
		end
		return
	end
end

-- The open (G7.20) --------------------------------------------------------------------------------------------------------

-- The confirm dialog's BUY on `boxId` (or AGAIN's): the reveal starts at once with the drop, and BoxOpen goes out; its
-- reply fills the reveal (the burst waits for it) or closes it. Yields until the reply. Returns a summary for the debug
-- hooks: { ok, reason?, requestId?, squishyId? }.
openPaid = function(boxId: string): { [string]: any }
	if opening ~= nil then
		return { ok = false, reason = "net.rateLimited" }
	end
	local view = currentView(boxId)
	if view.kind ~= "open" and view.kind ~= "confirm" then
		refresh()
		return { ok = false, reason = view.kind }
	end
	local requestId = pendingIds[boxId] or HttpService:GenerateGUID(false)
	pendingIds[boxId] = requestId
	inFlight[requestId] = true
	local attempt = { boxId = boxId, requestId = requestId }
	opening = attempt
	setStatus(nil, nil)
	-- The reveal plays while the request is in flight (a pending entry: no reveal yet, never queued).
	local pending: QueueEntry =
		{ reveal = nil, boxId = boxId, requestId = requestId, source = "reply", savePending = false }
	if current == nil and starting == nil and not UIController.isOpen(INSPECT_SCREEN) then
		starting = pending
		UIController.open(REVEAL_SCREEN, { requestId = requestId })
		starting = nil
	end
	local function pendingRun(): Run?
		local run = current
		return if run and run.entry == pending then run else nil
	end
	local still = task.delay(STILL_CHECKING_SECONDS, function()
		if opening == attempt then
			-- No reply yet: say so, and let the unseen reveals deliver the outcome (§11.6 "Timeout").
			inFlight[requestId] = nil
			setStatus(Strings.box.stillChecking, requestId)
			refresh()
			scanUnseen()
		end
	end)

	local result = NetController.invokeAsync("BoxOpen", boxId, requestId)

	if coroutine.status(still) == "suspended" then
		task.cancel(still)
	end
	opening = nil
	lastResult = { ok = result.ok, reason = result.reason, requestId = requestId, boxId = boxId }
	local summary: { [string]: any } = { ok = result.ok, reason = result.reason, requestId = requestId }
	local function abandon()
		-- the reveal ends unseen and unacknowledged (nothing to show yet)
		if pendingRun() then
			UIController.close(REVEAL_SCREEN, "failed")
		end
	end
	if result.ok then
		pendingIds[boxId] = nil
		inFlight[requestId] = nil
		local data: { [string]: any } = if type(result.data) == "table" then result.data :: { [string]: any } else {}
		local squishyId = data.squishyId
		summary.squishyId = squishyId
		if Catalog.isValidId(squishyId) then
			local reveal: BoxFormat.Reveal = {
				requestId = requestId,
				boxId = boxId,
				squishyId = squishyId,
				isDuplicate = data.isDuplicate == true,
			}
			if statusRequest == requestId then
				setStatus(nil, nil)
			end
			local run = pendingRun()
			if run then
				pending.reveal = reveal
				pending.savePending = data.savePending == true
				played[requestId] = true
				run.view:setResult(reveal, pending.savePending)
			else
				enqueue(entryOf(reveal, "reply", data.savePending == true), true)
			end
		else
			log:warn("BoxOpen replied without a valid squishy; waiting for the unseen reveals")
			abandon()
			setStatus(Strings.box.stillChecking, requestId)
			scanUnseen()
		end
	else
		abandon()
		local reason = result.reason
		if reason == GENERIC then
			-- Maybe opened: the outcome comes from the unseen reveals; the next open reuses this requestId.
			inFlight[requestId] = nil
			setStatus(Strings.box.stillChecking, requestId)
			scanUnseen()
		elseif BoxFormat.isIndeterminate(reason) then
			-- Never reached the server (refused locally): nothing happened; the next open reuses the id.
			inFlight[requestId] = nil
			NotifyController.showResult(result, "warn")
		else
			pendingIds[boxId] = nil
			inFlight[requestId] = nil
			NotifyController.showResult(result, "warn")
		end
	end
	refresh()
	pump()
	return summary
end

-- OPEN on a card: an unselected card is selected first (PR20); the selected one opens the confirm dialog, or denies
-- when short (P11: the off press already played ui.error and the shake).
local function pressOpen(boxId: string)
	if boxId ~= selectedBox then
		selectBox(boxId)
		return
	end
	local view = currentView(boxId)
	if view.kind == "open" or view.kind == "confirm" then
		openConfirm(boxId, function()
			openPaid(boxId)
		end)
	elseif view.kind == "needCoins" then
		deny()
	end
end

-- Builders: the Boxes screen ---------------------------------------------------------------------------------------------

-- A measured label (no AutomaticSize: it comes out wrong under the window's UIScale), `width` wide or its text's.
local function measuredLabel(
	parent: Instance,
	name: string,
	text: string,
	kind: Theme.TextKind,
	width: number?,
	role: string?
): TextLabel
	local bounds = Theme.textBounds(text, kind, nil, width)
	local label = Theme.label({
		Name = name,
		Text = text,
		Size = UDim2.fromOffset(width or (math.ceil(bounds.X) + 6), math.ceil(bounds.Y) + 2),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = width ~= nil,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = parent,
	}, kind)
	if role then
		Theme.stickerText(label, role)
	end
	return label
end

-- One stats well row (PR20): the toy tile, the rarity pill, the name, the exact percent; Owned; Inspect. Placed by
-- layoutWell.
local function buildRow(c: Cleanup.Cleanup, parent: Instance, index: number): Row
	local root: Frame = Create("Frame", {
		Name = "Boxes_Row_" .. index,
		BackgroundTransparency = 1,
		LayoutOrder = index,
		Visible = false,
		Parent = parent,
	})
	local tileFrame: Frame = Create("Frame", {
		Name = "Tile",
		BackgroundColor3 = Palette.StickerToyTile,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(ROW_TILE, ROW_TILE),
		Parent = root,
	})
	Theme.corner(BOXES_UI.toys.radius, tileFrame)
	local stroke = Theme.stroke(Theme.Colors.inkUI, BOXES_UI.toys.border, tileFrame)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
	local tile = SquishyImage.new(Catalog.starterId(), { size = BOXES_UI.toys.px, parent = tileFrame :: Instance })
	tile.root.AnchorPoint = Vector2.new(0.5, 0.5)
	tile.root.Position = UDim2.fromScale(0.5, 0.5)
	c:add(tile)
	local rarity = RarityTag.new({ name = "Rarity", rarity = "Common", variant = "detail", parent = root })
	c:add(rarity)
	local name = measuredLabel(root, "Name", "", "Small", nil, BOXES_UI.oddsPctRole)
	local percent = measuredLabel(root, "Percent", "100.00%", "Small", nil, BOXES_UI.oddsPctRole)
	percent.TextXAlignment = Enum.TextXAlignment.Right
	local owned = measuredLabel(root, "Owned", Strings.common.owned, "Small", nil, "confirmDesc")
	local row: Row
	local inspect = Button.new({
		name = "Boxes_InspectButton",
		text = Strings.common.inspect,
		size = "chip",
		parent = root,
		sound = false, -- opens a screen: ui.open plays instead (§18.5.2 B3)
		onActivated = function()
			local id = row.squishyId
			if id then
				UIController.open(INSPECT_SCREEN, { squishyId = id, owned = StateController.owns(id), source = SCREEN })
			end
		end,
	})
	inspect.root.Visible = false
	c:add(inspect)
	row = {
		root = root,
		tile = tile,
		name = name,
		rarity = rarity,
		percent = percent,
		owned = owned,
		inspect = inspect,
		squishyId = nil,
	}
	return row
end

-- The well's rows and texts placed for its inner `width` (base px): line 1 the tile, the pill, the name and the percent
-- (right); line 2 Owned and Inspect (right). Returns nothing; the list stacks the rows.
layoutWell = function(width: number)
	local w = well
	if w == nil then
		return
	end
	local line1 = math.max(RarityTag.measurePill("Exclusive", "detail").pillHeight, Theme.lineHeight("Small") + 2)
	local inspectHeight = TOUCH.minTarget
	for _, row in rows do
		local x = ROW_TILE + ROW_GAP
		local pillWidth = 0
		local name = row.squishyId
		if name then
			local def = Catalog.get(name)
			pillWidth = if def then RarityTag.measurePill(def.rarity, "detail").pillWidth else 0
		end
		row.rarity.root.Position = UDim2.fromOffset(x, 0)
		local percentWidth = math.ceil(Theme.textBounds(row.percent.Text, "Small").X) + 6
		row.percent.Size = UDim2.fromOffset(percentWidth, line1)
		row.percent.Position = UDim2.fromOffset(width - percentWidth, 0)
		local nameX = x + pillWidth + ROW_GAP
		row.name.Position = UDim2.fromOffset(nameX, 0)
		row.name.Size = UDim2.fromOffset(math.max(0, width - percentWidth - ROW_GAP - nameX), line1)
		row.name.TextTruncate = Enum.TextTruncate.AtEnd
		local inspectShown = row.inspect.root.Visible
		local beside = width - x - 120
		-- Too little room beside Inspect (narrow cards): Owned goes under it at full width.
		local stacked = inspectShown and beside < 140
		local textWidth = math.max(0, if inspectShown and not stacked then beside else width - x)
		local textTop = line1 + 4 + (if stacked then inspectHeight + 4 else 0)
		local ownedHeight = if row.owned.Visible then math.ceil(Theme.lineHeight("Small")) + 2 else 0
		row.owned.Position = UDim2.fromOffset(x, textTop)
		row.owned.Size = UDim2.fromOffset(textWidth, ownedHeight)
		row.inspect.root.AnchorPoint = Vector2.new(1, 0)
		row.inspect.root.Position = UDim2.fromOffset(width, line1 + 2)
		local height = math.max(
			ROW_TILE,
			if stacked
				then textTop + ownedHeight
				else line1 + 4 + math.max(ownedHeight, if inspectShown then inspectHeight else 0)
		)
		row.root.Size = UDim2.fromOffset(width, height)
	end
	for _, label in { w.heading, w.note, w.status, w.total, w.footer } do
		local bounds = Theme.textBounds(label.Text, "Small", nil, width)
		label.Size = UDim2.fromOffset(width, math.ceil(bounds.Y) + 2)
	end
	w.details.root.Size = UDim2.fromOffset(width, w.details.root.Size.Y.Offset)
end

-- The design's body (H:262): the three cards side by side (PR20: the selected one 2fr with the well), measured in base
-- px from the body's size (its UIScale and the window's open pop taken out), on every size, layout or text change.
local function layoutBody()
	local content = body
	local w = well
	if content == nil or w == nil or panel == nil then
		return
	end
	local pop = (panel :: Frame):FindFirstChild("SD_OpenScale")
	local s = UIController.scale() * (if pop and pop:IsA("UIScale") then pop.Scale else 1)
	if not (s > 0) or content.AbsoluteSize.X <= 0 then
		return
	end
	local pad = Theme.Padding.medium
	local b = BOXES_UI.body
	local insetX = WINDOW_BORDER + b.padSide - pad
	local insetTop = b.padTop - pad
	local insetBottom = WINDOW_BORDER + b.padBottom - pad
	local width = content.AbsoluteSize.X / s - 2 * insetX
	local height = content.AbsoluteSize.Y / s - insetTop - insetBottom
	local list = Boxes.list()
	local selectedIndex = 1
	for i, box in list do
		if box.id == selectedBox then
			selectedIndex = i
		end
	end
	local columns = BoxFormat.cardColumns(width, #list, if listShown then selectedIndex else 0, b.gap, b.minFr)
	local frame = BOXES_UI.card.pad + BOXES_UI.card.border
	local column = columns.fr - 2 * frame
	local x = 0
	for i, box in list do
		local card = cards[box.id]
		if card then
			local cardHeight = if columns.scroll then height - Theme.SCROLLBAR_PX else height
			local parts = BoxFormat.cardLayout(cardHeight, card:parts())
			card:layout(columns.widths[i], cardHeight, column, parts.plate, parts.tiles)
			card.root.Position = UDim2.fromOffset(x, 0)
			card.side.Visible = listShown and box.id == selectedBox
			if box.id == selectedBox then
				w.root.Parent = card.side
			end
			x += columns.widths[i] + b.gap
		end
	end
	w.cards.Position = UDim2.fromOffset(insetX, insetTop)
	w.cards.Size = UDim2.fromOffset(width, height)
	w.cards.CanvasSize = UDim2.fromOffset(if columns.scroll then columns.total else 0, 0)
	w.cards.ScrollingEnabled = columns.scroll
	if not listShown then
		return
	end
	local sideWidth = columns.widths[selectedIndex] - 2 * frame - column - BOXES_UI.card.gap
	local wellPad = BOXES_UI.well.pad + BOXES_UI.well.border
	wellWidth = math.max(0, sideWidth - 2 * wellPad - Theme.SCROLLBAR_PX)
	layoutWell(wellWidth)
end

local function build(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local root = Theme.window({
		Name = "Boxes",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, Config.UI.modalMaxWidth, MAX_HEIGHT_SHARE, 0),
		Parent = parent,
	}, WINDOW_KIND, Theme.Padding.medium)
	c:add(root)
	-- UI FINAL R3: the cyan band (H:258-259) and the 76 px X in it (H:285); R7: the subtitle at its right end (H:260).
	local subtitleSize = Theme.textBounds(Strings.box.subtitle, BOXES_UI.subtitleKind :: any)
	local subtitle = Theme.label({
		Name = "Subtitle",
		Text = Strings.box.subtitle,
		Size = UDim2.fromOffset(math.ceil(subtitleSize.X) + 4, math.ceil(subtitleSize.Y) + 2),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, BOXES_UI.subtitleKind :: any, nil, Palette.StickerBoxHeaderText)
	Theme.noOutline(subtitle) -- H:260: plain dark text on the band
	Theme.headerTab(root, Strings.box.title, { extra = subtitle :: GuiObject })
	local close = Button.new({
		name = "Boxes_CloseButton",
		text = Strings.common.close,
		kind = "close", -- UI overhaul: the chunky red X
		parent = root,
		sound = false, -- closing plays ui.back (UIController.close, reason "button")
		onActivated = function()
			UIController.close(SCREEN, "button")
		end,
	})
	Theme.attachClose(root, close.root)
	close.root.Modal = true -- frees the cursor in shift lock / first person (§10.4 step 4)
	c:add(close)
	-- UI FINAL R3: the design's 1060 x 650 face (its lip under it) shrunk to fit, its chrome at the window's scale,
	-- its face's top 310 above the middle (H:256; Layout.windowFit, Theme.fitWindow).
	local function fitWidth()
		local fit = Layout.windowFit(gui.AbsoluteSize, WINDOW_KIND)
		root.Size = UDim2.fromOffset(fit.width, fit.height + Config.UI.Sticker.lip.window)
		Theme.fitWindow(root, fit.k)
		root.Position = UDim2.new(0.5, 0, 0.5, fit.shift)
	end
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitWidth))
	c:add(UIController.LayoutChanged:connect(function()
		fitWidth()
		layoutBody()
		refresh()
	end))
	local okSignal, textSizeChanged = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if okSignal then
		c:add(textSizeChanged:Connect(function()
			fitWidth()
			layoutBody()
		end))
	end
	fitWidth()

	local content: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = root,
	})
	body = content

	-- H:262: the cards' row (it scrolls sideways when minFr cards do not fit, PR20 / compact)
	local row: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = Theme.SCROLLBAR_PX,
		ElasticBehavior = Enum.ElasticBehavior.Never,
		Selectable = false,
		ClipsDescendants = false,
		Parent = content,
	})
	Theme.scrollbar(row) -- the sideways scroll shows its bar (a ScrollHint is vertical-only)
	for index, box in Boxes.list() do
		local boxId = box.id
		local card = BoxCard.new({
			boxId = boxId,
			index = index,
			parent = row,
			onOpen = function()
				pressOpen(boxId)
			end,
			onSelect = function()
				tapBox(boxId)
			end,
			onRetry = function()
				if retryWait() > 0 then
					return
				end
				retryAt = os.clock()
				NetController.fire("PolicyRetry")
				refresh()
			end,
			scale = UIController.scale, -- pens3 phase 5: the next squishy's line is measured at the drawn size
		})
		c:add(card)
		cards[boxId] = card
	end

	-- H:236 + PR20: the stats well (§6.10 items 3-6), moved into the selected card's side
	local wellRoot: ScrollingFrame = Create("ScrollingFrame", {
		Name = "Well",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
	})
	local wl = BOXES_UI.well
	Theme.foam(wellRoot, {
		radius = wl.radius,
		stroke = wl.border,
		inner = true,
		top = wl.border + wl.inset.px,
		colors = { face = Palette.StickerWell, top = Palette.StickerWell:Lerp(Theme.Colors.inkUI, wl.inset.alpha) },
	})
	Theme.scrollbar(wellRoot)
	Create("UIPadding", {
		PaddingTop = UDim.new(0, wl.pad + wl.border),
		PaddingBottom = UDim.new(0, wl.pad + wl.border),
		PaddingLeft = UDim.new(0, wl.pad + wl.border),
		PaddingRight = UDim.new(0, wl.pad + wl.border),
		Parent = wellRoot,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		wl.rowGap,
		wellRoot,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local details = Button.new({
		name = "Boxes_DetailsButton",
		text = Strings.box.details,
		size = "chip",
		layoutOrder = 1,
		parent = wellRoot,
		onActivated = function()
			detailsOpen = not detailsOpen
			refresh()
		end,
	})
	details.root.Visible = false
	c:add(details)
	local heading = measuredLabel(wellRoot, "Heading", Strings.box.insideHeading, "Small", 200, "confirmDesc")
	heading.LayoutOrder = 2
	local rowsFrame: Frame = Create("Frame", {
		Name = "Rows",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 3,
		Parent = wellRoot,
	})
	Theme.list(
		Enum.FillDirection.Vertical,
		wl.rowGap,
		rowsFrame,
		Enum.HorizontalAlignment.Left,
		Enum.VerticalAlignment.Top
	)
	local most = 0
	for _, box in Boxes.list() do
		most = math.max(most, #box.items)
	end
	for index = 1, most do
		table.insert(rows, buildRow(c, rowsFrame, index))
	end
	local note = measuredLabel(wellRoot, "Note", "", "Small", 200, "confirmDesc")
	note.LayoutOrder = 4
	note.Visible = false
	local status = measuredLabel(wellRoot, "Status", "", "Small", 200, "confirmDesc")
	status.LayoutOrder = 5
	status.Visible = false
	local total = measuredLabel(wellRoot, "Total", "", "Small", 200, BOXES_UI.oddsPctRole)
	total.LayoutOrder = 6
	local footer = measuredLabel(wellRoot, "Footer", Strings.box.footer, "Small", 200, "confirmDesc")
	footer.LayoutOrder = 7

	well = {
		root = wellRoot,
		details = details,
		heading = heading,
		rows = rowsFrame,
		note = note,
		status = status,
		total = total,
		footer = footer,
		subtitle = subtitle,
		cards = row,
	}

	loadingLabel = Theme.label({
		Name = "Loading",
		Text = Strings.common.loading,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.6),
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = root,
	}, "H2")
	Theme.textOnWindow(loadingLabel :: TextLabel)

	panel = root
	layoutNow = layoutBody
	c:add(content:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutBody))
	refresh()
	layoutBody()
	return root
end

-- The reveal screen's own root: an empty placeholder in SD_Modal (UI/BoxReveal draws in its own layer).
local function buildReveal(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local root: Frame = Create("Frame", {
		Name = "BoxReveal",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(1, 1),
		Active = false,
		Parent = parent,
	})
	c:add(root)
	return root
end

-- World: the box counter prompt and the odds board ----------------------------------------------------------------------

-- The odds sign's plaque labels of a stand (its Hub prop, the stand marker's Model ancestor), top to bottom; a plaque
-- not streamed in yet is skipped.
local function signLabels(stand: Instance): { [number]: TextLabel }
	local found: { [number]: TextLabel } = {}
	local model = stand:FindFirstAncestorOfClass("Model")
	for index, name in SIGN_PLAQUES do
		local plaque = if model then model:FindFirstChild(name, true) else nil
		local label = if plaque then plaque:FindFirstChild(PLAQUE_TEXT, true) else nil
		if label and label:IsA("TextLabel") then
			found[index] = label
		end
	end
	return found
end

local function refreshWorld()
	local policy = StateController.get("policy")
	local key = BoxFormat.promptKey(policy)
	local attribute = if key == SHOP_PROMPT_KEY then ATTR_ALT_TEXT_KEY else ATTR_TEXT_KEY
	local fallback = Strings.resolve(key)
	for _, stand in CollectionService:GetTagged(STAND_TAG) do
		local candidates = stand:GetDescendants()
		table.insert(candidates, stand)
		for _, candidate in candidates do
			if candidate:IsA("ProximityPrompt") then
				local baked = candidate:GetAttribute(attribute)
				local text = (if type(baked) == "string" then Strings.resolve(baked) else nil) or fallback
				if text and candidate.ActionText ~= text then
					candidate.ActionText = text
				end
			end
		end
		local lines = BoxFormat.signLines(standBoxId(stand))
		for index, label in signLabels(stand) do
			if label.Text ~= lines[index] then
				label.Text = lines[index]
			end
		end
	end
end

local function guardedRefreshWorld()
	guarded("box counter update", refreshWorld)
end

-- Public ---------------------------------------------------------------------------------------------------------------

-- Opens the Boxes screen, optionally on one box. Returns UIController.open's result.
function BoxController.open(boxId: string?): boolean
	return UIController.open(SCREEN, if boxId then { boxId = boxId } else nil)
end

-- Small table for Studio debug hooks (SD_DebugClient "boxes").
function BoxController.debugState(): { [string]: any }
	local view = currentView()
	local queued = {}
	for _, entry in queue do
		table.insert(queued, { requestId = entry.requestId, source = entry.source })
	end
	local function keys(set: { [string]: boolean }): { string }
		local list = {}
		for key in set do
			table.insert(list, key)
		end
		table.sort(list)
		return list
	end
	local run = current
	local runState: { [string]: any }? = nil
	if run then
		local reveal = run.entry.reveal
		local state = run.view:debug()
		state.requestId = run.entry.requestId
		state.boxId = run.entry.boxId
		state.squishyId = if reveal then reveal.squishyId else nil
		state.isDuplicate = if reveal then reveal.isDuplicate else nil
		state.source = run.entry.source
		state.acked = run.acked
		runState = state
	end
	local prompts = {}
	local boards = {}
	for _, stand in CollectionService:GetTagged(STAND_TAG) do
		for _, descendant in stand:GetDescendants() do
			if descendant:IsA("ProximityPrompt") then
				table.insert(prompts, descendant.ActionText)
			end
		end
		for _, label in signLabels(stand) do
			table.insert(boards, label.Text)
		end
	end
	local stageExists = ViewportStage.exists()
	local stage = if stageExists then ViewportStage.get() else nil
	return {
		built = panel ~= nil,
		open = UIController.isOpen(SCREEN),
		revealOpen = UIController.isOpen(REVEAL_SCREEN),
		selected = selectedBox,
		policy = StateController.get("policy"),
		coins = StateController.coins(),
		serverCoins = StateController.serverValue("coins"),
		ownedShown = keys(StateController.owned() :: any),
		heldReveals = StateController.heldRevealIds(),
		view = {
			kind = view.kind,
			nextText = view.nextText,
			button = view.button,
			text = view.text,
			enabled = view.enabled,
			reason = view.reason,
			note = view.note,
			howToEarn = view.howToEarn,
		},
		status = statusText,
		retryWait = retryWait(),
		detailsOpen = detailsOpen,
		layout = UIController.layoutClass(),
		opening = if opening then { boxId = opening.boxId, requestId = opening.requestId } else nil,
		pendingIds = table.clone(pendingIds),
		inFlight = keys(inFlight),
		played = keys(played),
		queue = queued,
		held = holdReveals,
		reveal = runState,
		lastResult = lastResult,
		dialog = dialog ~= nil,
		stage = {
			exists = stageExists,
			attached = stage ~= nil and stage:isAttached(),
			hasModel = stage ~= nil and stage:model() ~= nil,
		},
		prompts = prompts,
		boards = boards,
		waypoint = waypoint ~= nil,
	}
end

-- Studio (SD_DebugClient "openBox"): the real flow on `boxId` from the confirm dialog's BUY on: the screen opens on it,
-- the Open area must allow it (eligible or restricted, enough Coins, the Toy Box not full, not saving), then the reveal
-- starts and BoxOpen is sent. Yields until the reply.
function BoxController.debugOpen(boxId: unknown): { [string]: any }
	local id = validBox(boxId)
	if id == nil then
		return { ok = false, error = "unknown box " .. tostring(boxId) }
	end
	if not UIController.open(SCREEN, { boxId = id }) then
		return { ok = false, error = "the boxes screen was refused" }
	end
	selectBox(id)
	local view = currentView()
	if view.kind ~= "open" and view.kind ~= "confirm" then
		return { ok = false, error = "not openable: " .. view.kind, reason = view.reason, note = view.note }
	end
	return openPaid(id)
end

-- Studio (SD_DebugClient "holdReveals"; R8's Daily window holds the day-7 Treat Box reveal while it shows): true
-- pauses the unseen reveals (reply reveals still play); false resumes.
function BoxController.debugHoldReveals(on: boolean)
	holdReveals = on == true
	if not holdReveals then
		scanUnseen()
	end
end

-- Studio (SD_DebugClient "skipReveal"): jumps the running reveal to its final state. False when none is running.
function BoxController.debugSkip(): boolean
	return skip()
end

-- Studio only: plays the box reveal of `squishyId` as a local preview (no remote, no grant; spec 2026-10-09 §6 Studio
-- check 3): queued first, as a new squishy, in the first box that holds it (snack otherwise). It
-- plays when the queue does (the lobby, the reveal screen, Inspect closed); `playing` says whether it started now.
function BoxController.debugRevealPreview(squishyId: unknown): { [string]: any }
	local def = if type(squishyId) == "string" then Catalog.get(squishyId) else nil
	if def == nil then
		return { ok = false, error = `unknown squishy {tostring(squishyId)}` }
	end
	if not game:GetService("RunService"):IsStudio() then
		return { ok = false, error = "Studio only" }
	end
	local containing = Boxes.containing(def.id)
	local boxId = if #containing > 0 then containing[1].boxId else firstPaidBox()
	local requestId = "preview:" .. HttpService:GenerateGUID(false)
	enqueue(
		entryOf({ requestId = requestId, boxId = boxId, squishyId = def.id, isDuplicate = false }, "preview", false),
		true
	)
	pump()
	local run = current
	return {
		ok = true,
		requestId = requestId,
		squishyId = def.id,
		boxId = boxId,
		playing = run ~= nil and run.entry.requestId == requestId,
		queued = queuedIds[requestId] == true, -- still waiting for its turn
	}
end

-- Lifecycle ------------------------------------------------------------------------------------------------------------

function BoxController.init()
	local c = Cleanup.new()
	cleanup = c
	selectedBox = firstPaidBox()
	listShown = true

	c:add(UIController.registerScreen(SCREEN, {
		build = build,
		onOpen = function(params: any?)
			local wanted = if type(params) == "table" then validBox(params.boxId) else nil
			if wanted then
				selectBox(wanted)
			end
			local oc = Cleanup.new()
			if openCleanup then
				openCleanup:clean()
			end
			openCleanup = oc
			clearWaypoint()
			-- The Try again countdown follows the clock while the screen is open (one more refresh when it ends).
			oc:add(task.spawn(function()
				local cooling = false
				while true do
					task.wait(TICK_SECONDS)
					local waiting = retryWait() > 0
					if waiting or cooling then
						guarded("open area update", refresh)
					end
					cooling = waiting
				end
			end))
			layoutBody()
			refresh()
			for _, card in cards do
				card:rise() -- H:264: sdRise on every open
			end
		end,
		onClose = function()
			if openCleanup then
				openCleanup:clean()
				openCleanup = nil
			end
			detailsOpen = false
			if current == nil then
				closeDialog()
			end
		end,
		primary = function(): GuiObject?
			local card = cards[selectedBox]
			if card == nil then
				return nil
			end
			local view = currentView()
			if view.button == "retry" then
				return card.retry.root
			end
			return card.open.root
		end,
		onTab = function(direction: number)
			cycleBox(direction)
		end,
	}))

	c:add(UIController.registerScreen(REVEAL_SCREEN, {
		build = buildReveal,
		onOpen = function()
			local entry = starting
			if entry == nil or current ~= nil then
				return
			end
			if not startRun(entry) then
				task.defer(function()
					if current == nil then
						UIController.close(REVEAL_SCREEN, "failed")
						pump()
					end
				end)
			end
		end,
		onClose = function(reason: string)
			local run = current
			if run == nil then
				return
			end
			current = nil
			local final = run.view:isFinal()
			if reason == "matched" and not final then
				-- Not seen yet: no AckReveal; it plays again after the duel (it is still unseen on the server).
				played[run.entry.requestId] = nil
				if run.entry.source == "reply" and run.entry.reveal ~= nil then
					enqueue(run.entry, true)
				end
			elseif reason ~= "failed" then
				ack(run) -- any other close counts as seen, like a skip
			end
			releaseHolds(run)
			closeDialog()
			local closeReason: BoxReveal.Reason = if reason == "nice"
				then "nice"
				elseif reason == HANDOFF_REASON then "inspect"
				elseif reason == "again" then "again"
				elseif reason == "matched" then "matched"
				elseif reason == "failed" then "failed"
				elseif reason == "back" then "back"
				else "close"
			guarded("reveal close", function()
				run.view:close(closeReason)
			end)
			task.defer(pump)
		end,
		primary = function(): GuiObject?
			local run = current
			return if run then run.view:primary() else nil
		end,
	}))

	c:add(WorldBinder.registerStand(STAND_TAG, function(stand: Instance)
		local boxId = standBoxId(stand)
		if
			BoxFormat.standScreen(StateController.get("policy")) == SHOP_SCREEN
			and UIController.isRegistered(SQUISHIES_SCREEN)
		then
			UIController.open(SQUISHIES_SCREEN) -- owner 2026-10-22: the coin BUY moved there from the shop
		else
			UIController.open(SCREEN, { boxId = boxId })
		end
	end))

	for _, field in { "coins", "owned", "dataStatus", "pen", "boxOrder" } do -- pens3 phase 5: pen, boxOrder
		c:add(StateController.changed(field):connect(function()
			refresh()
		end))
	end
	c:add(StateController.changed("policy"):connect(function(policy: any)
		if policy == POLICY_UNKNOWN then
			unknownAt = os.clock() -- Try again waits from here too (BoxFormat.retryWait)
		end
		refresh()
		guardedRefreshWorld()
	end))
	if StateController.get("policy") == POLICY_UNKNOWN then
		unknownAt = os.clock() -- already unknown before this listener existed: wait the full time from now
	end
	c:add(StateController.changed("unseenReveals"):connect(function()
		scanUnseen()
	end))
	c:add(StateController.Loaded:connect(function()
		refresh()
		guardedRefreshWorld()
		scanUnseen()
	end))
	c:add(StateController.LobbyLockChanged:connect(function(locked: boolean)
		if locked then
			clearWaypoint()
		else
			scanUnseen()
		end
		refresh()
	end))
	c:add(CollectionService:GetInstanceAddedSignal(STAND_TAG):Connect(function()
		task.defer(guardedRefreshWorld) -- after WorldBinder re-applies the baked prompt text on stream-in
	end))
	-- A reveal that waited for Inspect (pump) plays once Inspect has closed and given the stage back.
	c:add(UIController.ScreenClosed:connect(function(name: string)
		if name == INSPECT_SCREEN then
			task.defer(pump)
		end
	end))
	c:add(function()
		if openCleanup then
			openCleanup:clean()
			openCleanup = nil
		end
		clearWaypoint()
		closeDialog()
		local run = current
		current = nil
		if run then
			releaseHolds(run)
			guarded("reveal teardown", function()
				run.view:destroy()
			end)
		end
		table.clear(cards)
		table.clear(rows)
		table.clear(queue)
		table.clear(queuedIds)
		panel, loadingLabel, body, well = nil, nil, nil, nil
		layoutNow = function() end
	end)
	log:debug("ready")
end

function BoxController.start()
	local c = cleanup
	if c == nil then
		return
	end
	task.defer(guardedRefreshWorld)
	scanUnseen()
	c:add(task.spawn(function()
		while true do
			task.wait(WORLD_REFRESH_SECONDS)
			-- A counter that streams in later gets its baked prompt text back from WorldBinder; put the live one on.
			guardedRefreshWorld()
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function BoxController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return BoxController
