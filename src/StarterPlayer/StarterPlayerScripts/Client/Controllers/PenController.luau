--!strict
-- PenController (client only). Pens3 phase 1 (build plan work/pens3/PLAN.md "PHASE 1" Add 5; lobby design v6, approved
-- by the owner: `K:n` = kit.json line n, `P3D:n` = "Squishy Lobby 3D.html" line n). The island's pens on this client:
-- every base's walking squishies with their coin labels, and the own PEN SPACE sign. Nothing here decides anything:
-- the sign only sends PenBuySpot and shows the server's answer; the walking is cosmetic.
-- * Bases: every plot Model tagged WorldLayout.Tags.Base (attribute Plot), watched as CapsuleController did. Its
--   attributes SD_PenSpots and SD_Pen (BaseService: PenMath.encode of the placed items) say what walks there; a change
--   queues one sync of that base (task.defer, so one server render is one sync). A sync keeps every walker whose look
--   (kind.form.coat) is still placed, gives the rest back to a pool (unparented, kept for the next sync) and takes the
--   missing ones from the pool, or clones them: SquishyCache "World" (a model slot replaces the blueprint), scaled so
--   its longest side is Config.UI.Pen.rarityStuds of its rarity (K:4052-4081), its bottom on the plot floor, under
--   Workspace.SD_PenClient (SquishyCache builds every part CanCollide / CanQuery / CanTouch false).
-- * Walk (P3D:829-833; Config.UI.Pen): a new walker stands somewhere in its walk area (PenMath.wanderRect of the pen's
--   spots and its studs), waits 0..firstWaitMax s, then walks speedMin..speedMax studs/s to a random spot of the area,
--   facing the way it walks; within arriveStuds it waits waitMin..waitMax s and picks the next spot. While it walks it
--   hops (A17 PenWanderHop, K:5890-5954: hopHeight × its size over hopSeconds, Sine Out up, Sine In down); none under
--   ReducedMotion (it glides). Placeholder: A17's squash track is skipped (the squishies are built of parts).
-- * Distance (K:5897; one Scheduler render effect for the whole controller, no per-walker loop or connection): a base
--   whose pen centre is within animateStuds of the camera and on the screen (AmbientMath.sphereOnScreen) steps its
--   walkers; any other base's stand still. A base past cullStuds has its models unparented (kept), parented again
--   when the camera comes back.
-- * Coin label (K:4266-4270): one BillboardGui per walker (built with it, pooled with it), labelSize studs, its bottom
--   labelLift over the model's top, the coin icon (AssetTable img.coin) and "+{coins}/s" (Strings pen.rate, the whole
--   Coins a second of PenMath.itemRate) in the display font, white with the PenLabelStroke outline, both labelInner of
--   its height and measured with Theme.textBounds (no AutomaticSize). It does not hop (the design's sprite rides the
--   walker, not its body). MaxDistance labelMaxStuds, labelMaxStudsLow when MeshQuality.forCamera() is "Low". Its text
--   changes only on a sync.
-- * Own sign (K:4239-4265: trim colour + icon + text, never colour alone): on the local player's plot (Player
--   attribute SD_Plot) the Sign's Trim takes signState's colour, its Icon its picture and its Line its text (Walk up to
--   buy / Need N more / none at MAX), on every Coins or pen change and whenever a part of it streams in. Everyone else
--   sees BaseService's face (the title and the price, MAX at 12 spots).
-- * Buying: every other base's PenPrompt is turned off on this client (the server buys only the caller's own spot
--   anyway); the own one stays as the server made it (off at MAX). ProximityPromptService.PromptTriggered on the own
--   prompt sends PenBuySpot(the Sign's SD_Price) once at a time; an accepted buy plays ui.purchase and the price face's
--   pop (A13 UpgradeBuyPunch, Config.UI.Pen.signPop; none under ReducedMotion; HudController squashes the coin pill on
--   the spend), a refusal shows its reason (NotifyController.showResult).
-- * Coins while away (pens3 phase 4): the state field awayGift {coins, seconds} (PenService, once per load) shows a
--   stand-in pop-up, Diego's congrats overlay (UI/CongratsOverlay, the shop's, in its SD_Prompt layer): "You got" the
--   Coins (common.coinsAmount), the line away.body with the time away in words, the best pen squishy in the disc, the
--   ui.coin sound and the overlay's rain (Config.UI.Pen.awayRain). A tap, AWESOME! or back closes it. The Coins are
--   already in the pill (the server paid them on load): nothing to claim, no timer. A gift shows when it arrives (or is
--   there at start); StateController fires only on a new value, so a resent one never shows twice.
-- * No result before its reveal (pens3 phase 5, §9.11 "no fake-outs"): a box result is a new pen item (a copy when
--   the kind is owned), and BaseService draws it on the plot at once; so while BoxController's "boxReveal" screen is
--   open the own pen's sync waits (its walkers keep walking as they were) and runs when the reveal closes (syncWaits).
--   shortcut: only the reveal screen is watched; a free reward drawn before its reveal opens (the day-7 Treat Box
--   behind the Daily window) still walks in first; hold on StateController's reveal holds if that matters.
-- * The pen screen (pens3 phase 6; a STAND-IN from Diego's parts, UI/PenScreen, until he draws it): the "pen" modal,
--   opened from a tap or click on one of the own walking squishies (params {itemId}: PenFormat.walkerItem maps the
--   walker to its pen squishy) and from the Squishies window's MY PEN button ({kind}: PenFormat.pickFor). It draws
--   PenFormat.view of StateController's `pen` (again on every pen change and after every reply) and sends PenPlace
--   (PLACE into the first free spot, PUT AWAY = slot 0, MOVE / SWAP then a tap on a pen spot) and PenLock, one at a
--   time (the buttons show the spinner meanwhile); a refusal shows its reason (NotifyController.showResult).
--   The tap: ControlsController.setPointerClaim (CapsuleController's way, one claim at a time) sees every world press
--   that would squeeze first (never a key, so Diego's slide on C / Ctrl / ButtonB, LobbyMoveController, is
--   untouched; never a press on the UI, the thumbstick or jump, or in the practice box, and never during a duel or a
--   match: StateController.isLobbyLocked). It takes the press when it lands within tapMinPx screen px of an own
--   walker's middle (or its drawn size when bigger; tapHit, pure) within tapStuds of the camera (the walkers are out
--   of every query, so this is a screen-space test, not a ray), so that press never squeezes; on its release the
--   screen opens when it was a tap (Config.Inspect.Input tapMaxPixels and tapMaxMs), else it was a camera drag.
-- * Pens3 phases 7-8 (selling, the 10-minute buy-back, fusion; stand-ins in the same screen): PenFormat.view also gets
--   StateController's buyBack and coins, the server's time (Workspace:GetServerTimeNow), the selected sold card and
--   the confirm step open. SELL / SELL ALL / BUY BACK / FUSE open the confirm; its confirm sends SellItems(ids, a new
--   requestId GUID), SellAll(a new GUID), BuyBack(the sold id) or Fuse(the 3 ids), one at a time like PenPlace;
--   CANCEL (or a tap on a card) closes it. A hold action (selling Golden, Rainbow, Lv 10+ or Epic+) confirms only after
--   its press is held Config.UI.Pen.screen.holdSeconds: the screen reports the press and the release, the one
--   Scheduler effect (step) times it and fills the screen's hold bar. A sale plays ui.coin and floats "+N" from the
--   count line (UiFx.float), a buy-back ui.purchase, a fusion ui.levelTone with UiFx.burst (large for Golden, huge for
--   Rainbow) and the toast "You made a {name}!", and selects the result. The same effect redraws the screen once a
--   minute while it is open (the sold cards' minutes: plain numbers, no ticking countdown).
-- * Pens3 phase 8, the walking looks (K:3882-3920; Config.UI.Pen.forms): a Golden or Rainbow walker's parts, except
--   the face's (isFace), take formColor (Golden: blend 0.7 toward PenFormGolden; Rainbow: blend 0.75 toward the
--   PenFormRainbow band of the part's middle in the model's height) and the form's material, reflectance and
--   transparency when it is built (a hidden part stays hidden). Nothing else: no extra meshes, no sparkle yet.
-- * Pens3 phase 9 (food and levels; stand-ins in the same screen): PenFormat.view also gets StateController's food
--   and the selected BUY FOOD card (foodId; a tap on one, onFood, selects it). FEED sends Feed(the squishy, a
--   requestId), FEED ALL FeedAll(), BUY few / many BuyFood(the food, the count, its price × count, a requestId), one at
--   a time like PenPlace. A requestId is kept (PenFormat.requestFor) until the server answers, so a press after an
--   answer that never came is the same request (the server replays it, never twice); the Feed key holds the level, so
--   a press after the new level arrived is a new request. A feed plays ui.levelTone and floats "+N level(s)" from the
--   count line; a buy ui.purchase. The walker's coin label, the card's "Lv N" and the pen's +N/s follow the level by
--   the paths they already use (SD_Pen, PenFormat.cardText, PenMath.itemRate).
-- Public: the pure parts (signState, studsOf, hopLift, labelText, labelLayout, newWalk, stepWalker, awayText,
-- syncWaits, tapHit, isFace, formColor), init(), start(), destroy() (tests and leak checks; the bootstrap never calls
-- it), debugState().

-- Services

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local TimeUtil = require(Shared.Util.TimeUtil)
local WorldLayout = require(Shared.World.WorldLayout)

local Client = script.Parent.Parent
local AmbientMath = require(Client.Anim.AmbientMath)
local MeshQuality = require(Client.Anim.MeshQuality)
local Scheduler = require(Client.Anim.Scheduler)
local Timeline = require(Client.Anim.Timeline)
local Tweens = require(Client.Anim.Tweens)
local SquishyCache = require(Client.Models.SquishyCache)
local CongratsOverlay = require(Client.UI.CongratsOverlay)
local PenFormat = require(Client.UI.PenFormat)
local PenScreen = require(Client.UI.PenScreen)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local ControlsController = require(script.Parent.ControlsController)
local NetController = require(script.Parent.NetController)
local NotifyController = require(script.Parent.NotifyController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

-- Where a walker is and what it does (plot-local studs; yaw about +Y, its LookVector the way it walks).
export type Walk = {
	x: number,
	z: number,
	yaw: number,
	tx: number?, -- the spot it walks to (nil: none yet)
	tz: number?,
	wait: number, -- seconds left to stand still
	speed: number, -- studs a second
	rect: PenMath.Rect,
}

type Walker = Walk & {
	key: string, -- kind.form.coat: the model's look
	look: PenMath.Look, -- pens3 phase 6: what it shows now (the screen finds its squishy from it)
	index: number, -- pens3 phase 6: its place in the base's SD_Pen list (the placed order)
	model: Model,
	root: BasePart,
	studs: number,
	lift: number, -- the root's height over the model's bottom
	labelY: number, -- the label's centre over the root
	gui: BillboardGui,
	text: TextLabel,
	icon: ImageLabel,
	hop: number, -- 0..1 through the hop loop
	lastLift: number,
}

type Pen = {
	plot: number,
	model: Model,
	frame: CFrame,
	walkers: { Walker },
	shown: boolean, -- models parented (within cullStuds at the last frame)
	queued: boolean, -- a sync is deferred
	centre: Vector3,
	radius: number,
	cleanup: any, -- Cleanup.Cleanup: its connections and walkers
}

export type SignState = { state: "canBuy" | "tooExpensive" | "max", trim: string, icon: string, line: string }
export type TapPoint = { x: number, y: number, radius: number } -- pens3 phase 6: a walker on the screen (px)
export type LabelLayout = { icon: number, gap: number, text: number, height: number } -- shares of the label

export type DebugState = {
	ok: boolean,
	started: boolean,
	pens: number,
	walkers: number,
	pooled: number,
	shownPens: number,
	ownPlot: number?,
}

-- Constants

local P = Config.UI.Pen
local LAYOUT = WorldLayout.Bases.pen
local TAG_BASE = WorldLayout.Tags.Base
local ATTR_PLOT_MODEL = WorldLayout.Attributes.Plot
local ATTR_PLOT = "SD_Plot" -- the local player's plot (BaseService)
local ATTR_SPOTS = "SD_PenSpots"
local ATTR_PEN = "SD_Pen"
local ATTR_PRICE = "SD_Price"
local FOLDER_NAME = "SD_PenClient"
local PEN_FOLDER = "Pen" -- BaseService's folder on a plot model
local SIGN_NAME = "Sign"
local PROMPT_NAME = "PenPrompt"
local REMOTE_BUY = "PenBuySpot"
local SOUND_PURCHASE = "ui.purchase"
local SOUND_AWAY = "ui.coin" -- pens3 phase 4: the away pop-up opens
local FIELD_AWAY = "awayGift"
local REVEAL_SCREEN = "boxReveal" -- pens3 phase 5: BoxController's box reveal (the own pen waits for it)
local CONFIRM = Config.UI.confirm -- the congrats overlay's layer (ShopController's)
local LABEL_KIND: Theme.TextKind = "Coin"
local COMMON_STUDS = P.rarityStuds.Common
local MAX_SPOTS = Config.Economy.Pen.maxSpots
local SIGN_POP = Timeline.new(P.signPop)
local CENTRE_UP = 1.5 -- reading: the pen's bounding sphere sits this high, its radius the half diagonal + SPHERE_PAD
local SPHERE_PAD = 3
local SCREEN = "pen" -- pens3 phase 6: the stand-in pen screen
local MODAL_GUI = "SD_Modal"
local REMOTE_PLACE = "PenPlace"
local REMOTE_LOCK = "PenLock"
local TAP = Config.Inspect.Input -- a tap: under tapMaxPixels and tapMaxMs (the old capsule card's rule)
-- Pens3 phases 7-8.
local REMOTE_SELL = "SellItems"
local REMOTE_SELL_ALL = "SellAll"
local REMOTE_BUY_BACK = "BuyBack"
local REMOTE_FUSE = "Fuse"
local FIELD_BUY_BACK = "buyBack"
local REMOTE_BUY_FOOD = "BuyFood" -- pens3 phase 9
local REMOTE_FEED = "Feed"
local REMOTE_FEED_ALL = "FeedAll"
local FIELD_FOOD = "food"
local FOOD_BUY = P.screen.foodBuy
local SOUND_SELL = "ui.coin"
local SOUND_FUSE = "ui.levelTone"
local FORMS = P.forms
local RAINBOW = {
	Palette.PenFormRainbow1,
	Palette.PenFormRainbow2,
	Palette.PenFormRainbow3,
	Palette.PenFormRainbow4,
	Palette.PenFormRainbow5,
	Palette.PenFormRainbow6,
	Palette.PenFormRainbow7,
}

-- Module table

local PenController = {}

-- Private

local log = Log.new("Pen")
local cleanup: Cleanup.Cleanup? = nil
local folder: Folder? = nil
local pens: { [number]: Pen } = {}
local pool: { [string]: { Walker } } = {}
local effect: Scheduler.Handle? = nil
local random = Random.new()
local pending = false -- a PenBuySpot is running
local pop: { face: BasePart, size: Vector3, at: number }? = nil
local awayOverlay: CongratsOverlay.CongratsOverlay? = nil -- pens3 phase 4: the open away pop-up
local awayBack: (() -> ())? = nil -- its back handler (UIController.pushBack)
-- Pens3 phase 6: the pen screen.
local screen: PenScreen.PenScreen? = nil
local selectedId: number? = nil
local picking = false -- MOVE / SWAP: the next pen spot tapped takes the selected squishy
local busy = false -- a PenPlace / PenLock (pens3 phases 7-8: or a sell, buy-back or fuse) is running
local soldId: number? = nil -- pens3 phase 7: the selected sold card
local confirm: PenFormat.ConfirmKind? = nil -- the confirm step open
local holdAt: number? = nil -- os.clock() of a hold action's press
local soldMinute = -1 -- the server minute the screen was last drawn in (the sold cards' minutes)
local foodId: string? = nil -- pens3 phase 9: the selected BUY FOOD card
local pendingReq: PenFormat.Pending? = nil -- the request a BuyFood / Feed press reuses until the server answers
local pendingTap: { input: InputObject, from: Vector3, at: number, index: number, look: PenMath.Look }? = nil

local function rnd(): number
	return random:NextNumber()
end

local function ownPlot(): number?
	local player = Players.LocalPlayer
	local plot = if player then player:GetAttribute(ATTR_PLOT) else nil
	return if type(plot) == "number" then plot else nil
end

local function maxDistance(): number
	return if MeshQuality.forCamera(Workspace.CurrentCamera) == "Low" then P.labelMaxStudsLow else P.labelMaxStuds
end

local function lookKey(look: PenMath.Look): string
	return `{look.kind}.{look.form}.{look.coat}`
end

-- The coin label's text and its measured layout (see the header).
local function setLabel(w: Walker, look: PenMath.Look)
	local text = PenController.labelText(look)
	w.gui.MaxDistance = maxDistance()
	if w.text.Text == text then
		return
	end
	local bounds = Theme.textBounds(text, LABEL_KIND)
	local layout = PenController.labelLayout(if bounds.Y > 0 then bounds.X / bounds.Y else 0)
	w.text.Text = text
	w.icon.Size = UDim2.fromScale(layout.icon, layout.height)
	w.text.Size = UDim2.fromScale(layout.text, layout.height)
	local list = w.gui:FindFirstChildOfClass("UIListLayout")
	if list then
		list.Padding = UDim.new(layout.gap, 0)
	end
end

-- A walker's model and label (see the header).
local function build(look: PenMath.Look): Walker?
	local model = SquishyCache.clone(look.kind, "World")
	local root = model.PrimaryPart
	if root == nil then
		model:Destroy()
		return nil
	end
	local studs = PenController.studsOf(look.kind)
	local extents = model:GetExtentsSize()
	local longest = math.max(extents.X, extents.Y, extents.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * studs / longest)
	end
	local box, size = model:GetBoundingBox()
	-- Pens3 phase 8: a Golden or Rainbow look (see the header).
	local form = if look.form == 1 then FORMS.golden elseif look.form == 2 then FORMS.rainbow else nil
	if form then
		local bottom = box.Position.Y - size.Y / 2
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 and not PenController.isFace(part.Name) then
				local share = if size.Y > 0 then (part.Position.Y - bottom) / size.Y else 0
				part.Color = PenController.formColor(part.Color, look.form, share) or part.Color
				part.Material = (Enum.Material :: any)[form.material]
				part.Reflectance = form.reflectance
				part.Transparency = form.transparency
			end
		end
	end
	local bottom = model:GetPivot():PointToObjectSpace(box.Position).Y - size.Y / 2
	local gui = Instance.new("BillboardGui")
	gui.Name = "SD_PenRate"
	gui.Size = UDim2.fromScale(P.labelSize.X, P.labelSize.Y) -- studs (a BillboardGui's scale)
	local labelY = bottom + size.Y + P.labelLift + P.labelSize.Y / 2
	gui.StudsOffsetWorldSpace = Vector3.new(0, labelY, 0)
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = maxDistance()
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local icon = Instance.new("ImageLabel")
	icon.Name = "Coin"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = AssetTable.image("img.coin") or ""
	icon.LayoutOrder = 1
	icon.Parent = gui
	local text = Instance.new("TextLabel")
	text.Name = "Rate"
	text.BackgroundTransparency = 1
	text.FontFace = Theme.font(LABEL_KIND)
	text.TextScaled = true
	text.TextColor3 = Palette.PenLabelText
	text.Text = ""
	text.LayoutOrder = 2
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.PenLabelStroke
	stroke.Thickness = P.labelStrokePx
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = text
	text.Parent = gui
	gui.Parent = root
	local walker: any = {
		key = lookKey(look),
		look = look,
		index = 0,
		model = model,
		root = root,
		studs = studs,
		lift = -bottom,
		labelY = labelY,
		gui = gui,
		text = text,
		icon = icon,
		hop = 0,
		lastLift = 0,
	}
	return walker
end

local function release(w: Walker)
	w.model.Parent = nil
	w.gui.StudsOffsetWorldSpace = Vector3.new(0, w.labelY, 0) -- it may leave mid-hop
	w.lastLift = 0
	local list = pool[w.key]
	if list == nil then
		list = {}
		pool[w.key] = list
	end
	if #list >= MAX_SPOTS then
		w.model:Destroy() -- a pool holds at most a full pen of one look; more would only be memory
	else
		table.insert(list, w)
	end
end

-- The root and the label at the walker's spot, `lift` up (the hop; the label stays put).
local function place(pen: Pen, w: Walker, lift: number)
	w.root.CFrame = pen.frame * CFrame.new(w.x, w.lift + lift, w.z) * CFrame.Angles(0, w.yaw, 0)
	if lift ~= w.lastLift then
		w.gui.StudsOffsetWorldSpace = Vector3.new(0, w.labelY - lift, 0)
		w.lastLift = lift
	end
end

local function show(pen: Pen, shown: boolean)
	pen.shown = shown
	for _, w in pen.walkers do
		w.model.Parent = if shown then folder else nil
	end
end

-- The walkers of a base from its attributes (see the header).
local function sync(pen: Pen)
	local spots = pen.model:GetAttribute(ATTR_SPOTS)
	local step = if type(spots) == "number" then LAYOUT.steps[spots] else nil
	local looks: { PenMath.Look } = if step then PenMath.decode(pen.model:GetAttribute(ATTR_PEN)) else {}
	local free: { [string]: { Walker } } = {}
	for _, w in pen.walkers do
		local list = free[w.key] or {}
		free[w.key] = list
		table.insert(list, w)
	end
	local kept: { Walker } = {}
	for index, look in looks do
		local key = lookKey(look)
		local same = free[key]
		local w = if same and #same > 0 then table.remove(same) else nil
		local fresh = w == nil
		if w == nil then
			local list = pool[key]
			w = if list and #list > 0 then table.remove(list) else build(look)
		end
		local rect = if w then PenMath.wanderRect(spots :: number, w.studs) else nil
		if w and rect then
			w.rect = rect
			if fresh then
				local walk = PenController.newWalk(rect, rnd)
				w.x, w.z, w.yaw, w.tx, w.tz = walk.x, walk.z, walk.yaw, nil, nil
				w.wait, w.speed, w.hop, w.lastLift = walk.wait, walk.speed, rnd(), 0
			else
				w.x = math.clamp(w.x, rect.minX, rect.maxX)
				w.z = math.clamp(w.z, rect.minZ, rect.maxZ)
			end
			setLabel(w, look)
			w.look, w.index = look, index
			table.insert(kept, w)
			place(pen, w, 0)
			w.model.Parent = if pen.shown then folder else nil
		elseif w then
			release(w)
		end
	end
	for _, list in free do
		for _, w in list do
			release(w)
		end
	end
	pen.walkers = kept
	if step then
		pen.centre = (pen.frame * CFrame.new(0, CENTRE_UP, LAYOUT.frontZ - step.d / 2)).Position
		pen.radius = math.sqrt((step.w / 2) ^ 2 + (step.d / 2) ^ 2) + SPHERE_PAD
	end
end

local function queueSync(pen: Pen)
	if pen.queued then
		return
	end
	pen.queued = true
	task.defer(function()
		pen.queued = false
		if
			pens[pen.plot] == pen
			and not PenController.syncWaits(pen.plot, ownPlot(), UIController.isOpen(REVEAL_SCREEN))
		then
			local ok, err = pcall(function()
				sync(pen)
			end)
			if not ok then
				log:warn(`could not show the pen of plot {pen.plot}:`, err)
			end
		end
	end)
end

local function signOf(pen: Pen?): Instance?
	local found = if pen then pen.model:FindFirstChild(PEN_FOLDER) else nil
	return if found then found:FindFirstChild(SIGN_NAME) else nil
end

-- The own sign's trim, icon and line (see the header); nothing while it has not streamed in.
local function paintOwnSign()
	local plot = ownPlot()
	local sign = signOf(if plot then pens[plot] else nil)
	if sign == nil then
		return
	end
	local price = sign:GetAttribute(ATTR_PRICE)
	local state = PenController.signState(if type(price) == "number" then price else nil, StateController.coins())
	local trim = sign:FindFirstChild("Trim")
	if trim and trim:IsA("BasePart") and trim.Color ~= Palette[state.trim] then
		trim.Color = Palette[state.trim]
	end
	local icon = sign:FindFirstChild("Icon", true)
	local image = AssetTable.image(state.icon) or ""
	if icon and icon:IsA("ImageLabel") and icon.Image ~= image then
		icon.Image = image
	end
	local line = sign:FindFirstChild("Line", true)
	if line and line:IsA("TextLabel") and line.Text ~= state.line then
		line.Text = state.line
	end
end

-- Another base's prompt is off here; the own one is on unless the sign is at MAX (as BaseService made it).
local function setPrompt(pen: Pen, prompt: ProximityPrompt)
	if pen.plot == ownPlot() then
		local sign = prompt:FindFirstAncestor(SIGN_NAME)
		prompt.Enabled = sign ~= nil and type(sign:GetAttribute(ATTR_PRICE)) == "number"
	else
		prompt.Enabled = false
	end
end

local function setPrompts(pen: Pen)
	local found = pen.model:FindFirstChild(PEN_FOLDER)
	if found then
		for _, d in found:GetDescendants() do
			if d:IsA("ProximityPrompt") and d.Name == PROMPT_NAME then
				setPrompt(pen, d)
			end
		end
	end
end

local function watch(model: Instance)
	local plot = model:GetAttribute(ATTR_PLOT_MODEL)
	local frame = if type(plot) == "number" then WorldLayout.plotFrame(plot) else nil
	local c = cleanup
	if c == nil or frame == nil or not model:IsA("Model") or pens[plot :: number] ~= nil then
		return
	end
	local pc = Cleanup.new()
	local pen: Pen = {
		plot = plot :: number,
		model = model,
		frame = frame,
		walkers = {},
		shown = false,
		queued = false,
		centre = frame.Position,
		radius = 0,
		cleanup = pc,
	}
	pens[pen.plot] = pen
	for _, name in { ATTR_SPOTS, ATTR_PEN } do
		pc:add(model:GetAttributeChangedSignal(name):Connect(function()
			queueSync(pen)
		end))
	end
	pc:add(model.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("ProximityPrompt") and d.Name == PROMPT_NAME then
			setPrompt(pen, d)
		end
		if pen.plot == ownPlot() and d:FindFirstAncestor(PEN_FOLDER) then
			paintOwnSign() -- a part of the own sign streamed in, or BaseService drew it again
		end
	end))
	pc:add(function()
		for _, w in pen.walkers do
			w.model:Destroy()
		end
		table.clear(pen.walkers)
	end)
	setPrompts(pen)
	queueSync(pen)
end

local function unwatch(model: Instance)
	local plot = model:GetAttribute(ATTR_PLOT_MODEL)
	local pen = if type(plot) == "number" then pens[plot] else nil
	if pen and pen.model == model then
		pens[pen.plot] = nil
		pen.cleanup:clean()
	end
end

-- The price face's pop after an own buy (A13; the one effect steps it).
local function startPop()
	local plot = ownPlot()
	local sign = signOf(if plot then pens[plot] else nil)
	local face = if sign then sign:FindFirstChild("Face") else nil
	if Tweens.reducedMotion() or face == nil or not face:IsA("BasePart") then
		return
	end
	local running = pop
	local size = if running and running.face == face then running.size else face.Size
	pop = { face = face, size = size, at = os.clock() }
end

local function stepPop()
	local p = pop
	if p == nil then
		return
	end
	local ms = (os.clock() - p.at) * 1000
	if not p.face:IsDescendantOf(Workspace) or SIGN_POP:isDone(ms) then
		if p.face:IsDescendantOf(Workspace) then
			p.face.Size = p.size
		end
		pop = nil
		return
	end
	local scale = SIGN_POP:eval(ms)
	p.face.Size = Vector3.new(p.size.X * scale, p.size.Y * scale, p.size.Z)
end

-- Pens3 phases 7-8: the pen screen's part of the effect (set with the screen's code below).
local stepScreen: () -> ()

-- One frame of every pen near the camera and of the sign pop (see the header).
local function step(dt: number, _now: number): boolean
	stepPop()
	stepScreen() -- pens3 phases 7-8
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return true
	end
	local eye = camera.CFrame.Position
	local reduced = Tweens.reducedMotion()
	local viewport = camera.ViewportSize
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	for _, pen in pens do
		local distance = (pen.centre - eye).Magnitude
		local near = distance <= P.cullStuds
		if near ~= pen.shown then
			show(pen, near)
		end
		if near and distance <= P.animateStuds and #pen.walkers > 0 then
			local point = camera:WorldToViewportPoint(pen.centre)
			if AmbientMath.sphereOnScreen(point.X, point.Y, point.Z, pen.radius, viewport, tanHalf) then
				for _, w in pen.walkers do
					local moving = PenController.stepWalker(w, dt, rnd)
					local lift = 0
					if moving then
						w.hop = (w.hop + dt / P.hopSeconds) % 1
						lift = PenController.hopLift(w.hop * P.hopSeconds, w.studs, reduced)
					end
					if moving or w.lastLift ~= 0 then
						place(pen, w, lift)
					end
				end
			end
		end
	end
	return true
end

local function buy(prompt: ProximityPrompt)
	local plot = ownPlot()
	local pen = if plot then pens[plot] else nil
	local sign = signOf(pen)
	local price = if sign then sign:GetAttribute(ATTR_PRICE) else nil
	if pending or sign == nil or not prompt:IsDescendantOf(sign) or type(price) ~= "number" then
		return
	end
	pending = true
	local result = NetController.invokeAsync(REMOTE_BUY, price)
	pending = false
	if cleanup == nil then
		return -- destroyed meanwhile
	end
	if result.ok then
		SoundController.play(SOUND_PURCHASE)
		startPop()
	else
		NotifyController.showResult(result)
	end
	paintOwnSign()
end

-- Pens3 phase 4: the away pop-up is gone (closed, replaced or destroyed): its back handler goes with it.
local function dropAway()
	local popBack = awayBack
	awayBack, awayOverlay = nil, nil
	if popBack then
		popBack()
	end
end

-- Pens3 phase 4: a gift that paid, as the stand-in pop-up (see the header).
local function showAway(gift: any)
	local title, body = PenController.awayText(gift)
	if title == nil or body == nil then
		return
	end
	local old = awayOverlay
	if old then
		old:destroy()
		dropAway()
	end
	local best = PenMath.placed(StateController.get("pen"))[1]
	SoundController.play(SOUND_AWAY)
	local overlay: CongratsOverlay.CongratsOverlay
	overlay = CongratsOverlay.show({
		layer = UIController.screenGui(CONFIRM.layerName, CONFIRM.layer),
		catalogId = if best then best.kind else nil,
		title = title,
		description = body,
		scale = UIController.scale(),
		trackScale = UIController.trackScale,
		sound = function(key: string)
			SoundController.play(key)
		end,
		onClose = function()
			if awayOverlay == overlay then
				dropAway()
			end
		end,
	})
	awayOverlay = overlay
	awayBack = UIController.pushBack(function()
		overlay:close(true) -- UIController.back plays ui.back for it
	end)
	task.delay(P.awayRainDelayMs / 1000, function()
		overlay:rain(P.awayRain)
	end)
end

-- Pens3 phase 6: the pen screen (see the header) ---------------------------------------------------------------------

local function currentView(): PenFormat.View
	return PenFormat.view(StateController.get("pen"), selectedId, picking, {
		buyBack = StateController.get(FIELD_BUY_BACK),
		now = Workspace:GetServerTimeNow(),
		coins = StateController.get("coins"),
		soldId = soldId,
		confirm = confirm,
		food = StateController.get(FIELD_FOOD), -- pens3 phase 9
		foodId = foodId,
	})
end

local function render()
	local s = screen
	if s and UIController.isOpen(SCREEN) then
		local view = currentView()
		if view.selected == nil then
			selectedId, picking = nil, false -- the squishy is gone
		end
		if view.soldSelected == nil then
			soldId = nil -- bought back, or its time is over
		end
		if view.foodSelected == nil then
			foodId = nil -- pens3 phase 9: no longer on sale, or another card was picked
		end
		confirm = view.confirm -- a confirm that cannot open any more is closed
		s:render(view, busy)
	end
end

-- One PenPlace / PenLock (pens3 phases 7-8: or SellItems / SellAll / BuyBack / Fuse) at a time; the server decides,
-- the state delta redraws the screen. Returns the result (nil when another one runs or the controller went away).
local function send(remote: string, ...: any): any
	if busy then
		return nil
	end
	busy = true
	holdAt = nil
	render()
	local result = NetController.invokeAsync(remote, ...)
	busy = false
	if cleanup == nil then
		return nil -- destroyed meanwhile
	end
	picking, confirm = false, nil
	if not result.ok then
		NotifyController.showResult(result)
	end
	render()
	return result
end

-- Pens3 phases 7-8: the feel of an accepted sale, buy-back or fusion (see the header).
local function celebrate(kind: PenFormat.ConfirmKind, data: any)
	local s = screen
	local at = if s then s.statusRoot else nil
	if kind == "fuse" then
		local item = PenMath.find(data.pen, data.id)
		SoundController.play(SOUND_FUSE)
		if item and at then
			local rainbow = item.form >= 2
			local tier: UiFx.Tier = if rainbow then "huge" else "large"
			UiFx.burst(at, tier, if rainbow then RAINBOW[1] else Palette.PenFormGolden)
		end
		if item then
			NotifyController.show("pen.screen.fused", { name = PenFormat.formName(item) }, "success")
			selectedId = item.id -- the result stays selected
		end
	elseif kind == "buyBack" then
		SoundController.play(SOUND_PURCHASE)
	else
		SoundController.play(SOUND_SELL)
		if at and type(data.coins) == "number" and data.coins > 0 then
			UiFx.float(at, "+" .. Format.coins(data.coins))
		end
	end
	render()
end

local function sendFor(kind: PenFormat.ConfirmKind, remote: string, ...: any)
	local result = send(remote, ...)
	if result and result.ok and type(result.data) == "table" then
		celebrate(kind, result.data)
	end
end

-- Pens3 phase 9: the feel of an accepted feed or buy (see the header).
local function celebrateFood(kind: string, data: any)
	local s = screen
	if kind == "buy" then
		SoundController.play(SOUND_PURCHASE)
	elseif type(data.levels) == "number" and data.levels > 0 then
		SoundController.play(SOUND_FUSE) -- ui.levelTone: the level-up tone
		if s then
			local up = Strings.pen.screen.levelsUp
			UiFx.float(s.statusRoot, Strings.format(Strings.plural(data.levels, up.one, up.many), { n = data.levels }))
		end
	end
	render()
end

local function newRequestId(): string
	return HttpService:GenerateGUID(false)
end

-- Pens3 phase 9: one BuyFood / Feed (key = what it does: its requestId, appended last, is the pending one for the same
-- key until the server answers) or FeedAll (no key).
local function sendFood(kind: string, remote: string, key: string?, ...: any)
	local args = { ... }
	if key ~= nil then
		local request
		request, pendingReq = PenFormat.requestFor(pendingReq, key, newRequestId)
		table.insert(args, request)
	end
	local result = send(remote, table.unpack(args))
	if result == nil then
		return
	end
	if result.ok or result.charged ~= nil then
		pendingReq = nil -- the server answered: the next press is a new request
	end
	if result.ok and type(result.data) == "table" then
		celebrateFood(kind, result.data)
	end
end

-- The confirm step's confirm: what the view says to send.
local function confirmNow()
	local view = currentView()
	local kind = view.confirm
	if kind == "sell" and view.sellIds then
		task.spawn(sendFor, kind, REMOTE_SELL, view.sellIds, HttpService:GenerateGUID(false))
	elseif kind == "sellAll" then
		task.spawn(sendFor, kind, REMOTE_SELL_ALL, HttpService:GenerateGUID(false))
	elseif kind == "buyBack" and view.soldSelected then
		task.spawn(sendFor, kind, REMOTE_BUY_BACK, view.soldSelected.id)
	elseif kind == "fuse" and view.fuseIds then
		local ids = view.fuseIds
		task.spawn(sendFor, kind, REMOTE_FUSE, ids[1], ids[2], ids[3])
	end
end

-- A hold action's press (true) or release (false); the step times it.
local function onHold(_id: string, down: boolean)
	holdAt = if down and not busy then os.clock() else nil
	local s = screen
	if s and not down then
		s:setHold(nil)
	end
end

-- The screen's part of the one effect: the hold, and a redraw once a minute (the sold cards' minutes).
function stepScreen()
	local s = screen
	if s == nil then
		return
	end
	local started = holdAt
	if started ~= nil then
		local fraction = PenFormat.holdFraction(started, os.clock())
		s:setHold(fraction)
		if fraction >= 1 then
			holdAt = nil
			s:setHold(nil)
			confirmNow()
		end
	end
	local minute = math.floor(Workspace:GetServerTimeNow() / 60)
	if minute ~= soldMinute then
		soldMinute = minute
		render()
	end
end

local function onCard(slot: number?, itemId: number?)
	local what, a, b = PenFormat.tap(currentView(), slot, itemId)
	if what == "place" then
		task.spawn(send, REMOTE_PLACE, a, b)
	elseif what == "select" then
		selectedId, picking, soldId, confirm, foodId = a, false, nil, nil, nil
		render()
	end
end

-- Pens3 phase 7: a sold card.
local function onSold(itemId: number)
	selectedId, picking, soldId, confirm, foodId = nil, false, itemId, nil, nil
	render()
end

-- Pens3 phase 9: a BUY FOOD card.
local function onFood(id: string)
	selectedId, picking, soldId, confirm, foodId = nil, false, nil, nil, id
	render()
end

local function onAction(id: string)
	-- Pens3 phases 7-8: the confirm steps.
	if id == "sell" or id == "sellAll" or id == "buyBack" or id == "fuse" then
		confirm = id :: any
		render()
		return
	elseif id == "confirm" then
		confirmNow()
		return
	end
	local view = currentView()
	local item = view.selected
	if id == "cancel" then
		picking, confirm = false, nil
		render()
		return
	elseif id == "feedAll" then
		task.spawn(sendFood, "feed", REMOTE_FEED_ALL, nil) -- pens3 phase 9
		return
	elseif (id == "buyFew" or id == "buyMany") and view.foodSelected then
		local card = view.foodSelected
		local n = if id == "buyFew" then FOOD_BUY.few else FOOD_BUY.many
		task.spawn(sendFood, "buy", REMOTE_BUY_FOOD, `buy:{card.id}:{n}`, card.id, n, card.price * n)
		return
	end
	if item == nil then
		return
	end
	if id == "feed" then
		task.spawn(sendFood, "feed", REMOTE_FEED, `feed:{item.id}:{item.level}`, item.id)
		return
	end
	if id == "place" then
		task.spawn(send, REMOTE_PLACE, item.id, PenMath.freeSlot(StateController.get("pen")))
	elseif id == "putAway" then
		task.spawn(send, REMOTE_PLACE, item.id, 0)
	elseif id == "move" or id == "swap" then
		picking = true
		render()
	elseif id == "lock" or id == "unlock" then
		task.spawn(send, REMOTE_LOCK, item.id, id == "lock")
	end
end

local function buildScreen(parent: Instance): GuiObject
	local c = cleanup :: Cleanup.Cleanup
	local gui = UIController.screenGui(MODAL_GUI)
	local made = PenScreen.new({
		parent = parent,
		scale = UIController.scale,
		onCard = onCard,
		onSold = onSold,
		onAction = onAction,
		onHold = onHold,
		onFood = onFood, -- pens3 phase 9
		onClose = function()
			UIController.close(SCREEN, "button")
		end,
	})
	c:add(made)
	screen = made
	made:fit(gui.AbsoluteSize)
	c:add(gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		made:fit(gui.AbsoluteSize)
	end))
	return made.root
end

-- ControlsController's pointer claim: a world press on an own walking squishy waits to open the screen.
local function claim(input: InputObject): boolean
	local plot = ownPlot()
	local pen = if plot then pens[plot] else nil
	local camera = Workspace.CurrentCamera
	if pen == nil or not pen.shown or camera == nil or StateController.isLobbyLocked() then
		return false
	end
	local points: { TapPoint } = {}
	local walkers: { Walker } = {}
	local tanHalf = math.tan(math.rad(camera.FieldOfView) / 2)
	local halfHeight = camera.ViewportSize.Y / 2
	for _, w in pen.walkers do
		local at, onScreen = camera:WorldToScreenPoint(w.root.Position)
		if onScreen and at.Z > 0 and at.Z <= P.tapStuds then
			table.insert(points, { x = at.X, y = at.Y, radius = w.studs / 2 / (at.Z * tanHalf) * halfHeight })
			table.insert(walkers, w)
		end
	end
	local hit = PenController.tapHit(Vector2.new(input.Position.X, input.Position.Y), points, P.tapMinPx)
	local w = if hit then walkers[hit] else nil
	if w == nil then
		return false
	end
	pendingTap = { input = input, from = input.Position, at = os.clock(), index = w.index, look = w.look }
	return true
end

local function onInputEnded(input: InputObject)
	local tap = pendingTap
	local mouse = input.UserInputType == Enum.UserInputType.MouseButton1
	if tap == nil or (not mouse and input ~= tap.input) then
		return
	end
	pendingTap = nil
	local moved = (input.Position - tap.from).Magnitude
	if moved <= TAP.tapMaxPixels and (os.clock() - tap.at) * 1000 <= TAP.tapMaxMs then
		UIController.open(SCREEN, { itemId = PenFormat.walkerItem(StateController.get("pen"), tap.index, tap.look) })
	end
end

-- Public: the pure parts -------------------------------------------------------------------------------------------

-- The own sign's state for the next spot's price (nil at MAX) and the Coins now (nil = 0).
function PenController.signState(price: number?, coins: number?): SignState
	if price == nil then
		return { state = "max", trim = "PenSignMax", icon = "img.icon.star", line = "" }
	end
	local have = if type(coins) == "number" and coins == coins then coins else 0
	if have >= price then
		return { state = "canBuy", trim = "PenSignCanBuy", icon = "img.coin", line = Strings.pen.sign.canBuy }
	end
	local need = Strings.format(Strings.pen.sign.needMore, { coins = Format.coins(price - math.max(have, 0)) })
	return { state = "tooExpensive", trim = "PenSignTooExpensive", icon = "img.icon.lock", line = need }
end

-- The longest side (studs) of a squishy of `kind` (Config.UI.Pen.rarityStuds; the Common's for an unknown kind).
function PenController.studsOf(kind: string): number
	local def = Catalog.get(kind)
	return (if def then P.rarityStuds[def.rarity] else nil) or COMMON_STUDS
end

-- A17's hop at `t` s into the loop for a squishy `studs` long: hopHeight × studs / the Common's × sin(π t / loop) is
-- exactly its Sine Out rise to the middle and Sine In fall; 0 under ReducedMotion.
function PenController.hopLift(t: number, studs: number, reduced: boolean): number
	if reduced then
		return 0
	end
	local u = (t % P.hopSeconds) / P.hopSeconds
	return P.hopHeight * studs / COMMON_STUDS * math.sin(math.pi * u)
end

-- Pens3 phase 5: true while the pen of `plot` must keep its walkers as they are: it is the own plot (`own`) and the box
-- reveal plays (`revealOpen`; see the header).
function PenController.syncWaits(plot: number, own: number?, revealOpen: boolean): boolean
	return revealOpen and plot == own
end

-- Pens3 phase 4: the away pop-up's prize line and body for a gift {coins, seconds}; nil when it paid no whole Coins.
function PenController.awayText(gift: any): (string?, string?)
	local coins = if type(gift) == "table" then gift.coins else nil
	if type(coins) ~= "number" or not (coins >= 1) then
		return nil, nil
	end
	local h, m = TimeUtil.splitDuration(tonumber(gift.seconds) or 0)
	local away = Strings.away
	local time = if h > 0 and m > 0
		then Strings.format(away.hoursMinutes, { h = h, m = m })
		elseif h > 0 then Strings.format(away.hours, { h = h })
		elseif m > 0 then Strings.format(away.minutes, { m = m })
		else away.underMinute
	return Strings.format(Strings.common.coinsAmount, { coins = Format.coins(coins) }),
		Strings.format(away.body, { time = time })
end

-- Pens3 phase 6: the walker a tap at `tap` (screen px) lands on: the nearest whose middle is within its radius, or
-- minPx when that is bigger (a finger is wider than a far squishy); nil when none.
function PenController.tapHit(tap: Vector2, points: { TapPoint }, minPx: number): number?
	local best, bestShare = nil, math.huge
	for index, point in points do
		local reach = math.max(point.radius, minPx)
		local share = (Vector2.new(point.x, point.y) - tap).Magnitude / reach
		if share <= 1 and share < bestShare then
			best, bestShare = index, share
		end
	end
	return best
end

-- Pens3 phase 8: true for a part of the face (Config.UI.Pen.forms.faceWords in its lower-case name): it keeps its look.
function PenController.isFace(name: string): boolean
	local lower = string.lower(name)
	for _, word in FORMS.faceWords do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

-- Pens3 phase 8: a part's colour on a Golden (form 1) or Rainbow (form 2) squishy, `share` (0 bottom .. 1 top) up the
-- model; nil for a plain one (K:3882-3920).
function PenController.formColor(color: Color3, form: number, share: number): Color3?
	if form == 1 then
		return color:Lerp(Palette.PenFormGolden, FORMS.golden.blend)
	elseif form == 2 then
		local bands = FORMS.rainbow.bands
		local band = math.clamp(math.floor(share * bands), 0, bands - 1) + 1
		return color:Lerp(RAINBOW[band], FORMS.rainbow.blend)
	end
	return nil
end

-- "+{coins}/s": the whole Coins a second of a look.
function PenController.labelText(look: any): string
	return Strings.format(Strings.pen.rate, { coins = Format.coins(math.floor(PenMath.itemRate(look))) })
end

-- The coin label's insides for a text `aspect` (its width over its height): the icon and the text labelInner of the
-- label's height, the text as wide as the aspect asks but within the label (shares of the label's width; height a
-- share of its height).
function PenController.labelLayout(aspect: number): LabelLayout
	local w, h = P.labelSize.X, P.labelSize.Y
	local icon = P.labelInner * h
	local gap = P.labelGap * h
	local wanted = if aspect == aspect and aspect > 0 then aspect * P.labelInner * h else 0
	local text = math.clamp(wanted, 0, math.max(0, w - icon - gap))
	return { icon = icon / w, gap = gap / w, text = text / w, height = P.labelInner }
end

-- A fresh walker somewhere in `rect`: random spot and facing, its first wait 0..firstWaitMax s, its speed (P3D:398).
function PenController.newWalk(rect: PenMath.Rect, random01: () -> number): Walk
	return {
		x = rect.minX + random01() * (rect.maxX - rect.minX),
		z = rect.minZ + random01() * (rect.maxZ - rect.minZ),
		yaw = random01() * 2 * math.pi,
		wait = random01() * P.firstWaitMax,
		speed = P.speedMin + random01() * (P.speedMax - P.speedMin),
		rect = rect,
	}
end

-- One step of a walker (P3D:829-833): true while it moved. random01 gives numbers in [0, 1).
function PenController.stepWalker(walk: Walk, dt: number, random01: () -> number): boolean
	if walk.wait > 0 then
		walk.wait -= dt
		return false
	end
	local rect = walk.rect
	if walk.tx == nil or walk.tz == nil then
		walk.tx = rect.minX + random01() * (rect.maxX - rect.minX)
		walk.tz = rect.minZ + random01() * (rect.maxZ - rect.minZ)
	end
	local dx, dz = (walk.tx :: number) - walk.x, (walk.tz :: number) - walk.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < P.arriveStuds then
		walk.tx, walk.tz = nil, nil
		walk.wait = P.waitMin + random01() * (P.waitMax - P.waitMin)
		return false
	end
	local move = math.min(distance, walk.speed * dt)
	walk.x += dx / distance * move
	walk.z += dz / distance * move
	walk.yaw = math.atan2(-dx, -dz)
	return true
end

-- Public: lifecycle --------------------------------------------------------------------------------------------------

function PenController.debugState(): DebugState
	local walkers, pooled, shown, count = 0, 0, 0, 0
	for _, pen in pens do
		count += 1
		walkers += #pen.walkers
		if pen.shown then
			shown += 1
		end
	end
	for _, list in pool do
		pooled += #list
	end
	return {
		ok = true,
		started = cleanup ~= nil,
		pens = count,
		walkers = walkers,
		pooled = pooled,
		shownPens = shown,
		ownPlot = ownPlot(),
	}
end

function PenController.init()
	-- Nothing to register here: the pens are world objects, the sign's prompt is BaseService's, and the pen screen
	-- (pens3 phase 6) registers in start() so destroy() takes it away.
end

function PenController.start()
	if cleanup ~= nil then
		return
	end
	local c = Cleanup.new()
	cleanup = c
	local made = Instance.new("Folder")
	made.Name = FOLDER_NAME
	made.Parent = Workspace
	folder = made
	c:add(function()
		for plot in table.clone(pens) do
			local pen = pens[plot]
			pens[plot] = nil
			pen.cleanup:clean()
		end
		for _, list in pool do
			for _, w in list do
				w.model:Destroy()
			end
		end
		table.clear(pool)
		local handle = effect
		if handle then
			handle:disconnect()
		end
		effect, pop, pending = nil, nil, false
		local away = awayOverlay
		if away then
			away:destroy()
			dropAway()
		end
		made:Destroy()
		folder = nil
		screen, selectedId, picking, busy, pendingTap = nil, nil, false, false, nil -- pens3 phase 6
		soldId, confirm, holdAt, soldMinute = nil, nil, nil, -1 -- pens3 phases 7-8
		foodId, pendingReq = nil, nil -- pens3 phase 9
	end)
	for _, model in CollectionService:GetTagged(TAG_BASE) do
		watch(model)
	end
	c:add(CollectionService:GetInstanceAddedSignal(TAG_BASE):Connect(watch))
	c:add(CollectionService:GetInstanceRemovedSignal(TAG_BASE):Connect(unwatch))
	c:add(ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == PROMPT_NAME then
			task.spawn(buy, prompt)
		end
	end))
	for _, field in { "coins", "pen" } do
		c:add(StateController.changed(field):connect(paintOwnSign))
	end
	c:add(StateController.changed(FIELD_AWAY):connect(showAway))
	-- Pens3 phase 6: the pen screen, the tap that opens it, and its redraw on every pen change.
	c:add(UIController.registerScreen(SCREEN, {
		build = buildScreen,
		onOpen = function(params: any?)
			local wanted = if type(params) == "table" then params else {}
			local pen = StateController.get("pen")
			selectedId = if type(wanted.itemId) == "number"
				then wanted.itemId
				elseif type(wanted.kind) == "string" then PenFormat.pickFor(pen, wanted.kind)
				else nil
			picking, soldId, confirm, holdAt, foodId = false, nil, nil, nil, nil
			render()
		end,
		primary = function(): GuiObject?
			local s = screen
			return if s then s:primary() else nil
		end,
	}))
	c:add(StateController.changed("pen"):connect(render))
	c:add(StateController.changed(FIELD_BUY_BACK):connect(render)) -- pens3 phase 7: the sold cards
	c:add(StateController.changed("coins"):connect(render)) -- BUY BACK's missing Coins and the balance after
	c:add(StateController.changed(FIELD_FOOD):connect(render)) -- pens3 phase 9: the food row, FEED and BUY FOOD
	ControlsController.setPointerClaim(claim)
	c:add(function()
		ControlsController.setPointerClaim(nil)
	end)
	c:add(UserInputService.InputEnded:Connect(onInputEnded))
	c:add(UIController.ScreenClosed:connect(function(name: string)
		local plot = ownPlot()
		local own = if name == REVEAL_SCREEN and plot then pens[plot] else nil
		if own then
			queueSync(own) -- the result the reveal showed walks in now
		end
	end))
	local player = Players.LocalPlayer
	if player then
		c:add(player:GetAttributeChangedSignal(ATTR_PLOT):Connect(function()
			for _, pen in pens do
				setPrompts(pen)
			end
			paintOwnSign()
		end))
	end
	effect = Scheduler.add(step, "render")
	paintOwnSign()
	showAway(StateController.get(FIELD_AWAY))
end

function PenController.destroy()
	local c = cleanup
	if c then
		cleanup = nil
		c:clean()
	end
end

return PenController
