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
-- Public: the pure parts (signState, studsOf, hopLift, labelText, labelLayout, newWalk, stepWalker, awayText), init(),
-- start(), destroy() (tests and leak checks; the bootstrap never calls it), debugState().

-- Services

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
local Theme = require(Client.UI.Theme)
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
local CONFIRM = Config.UI.confirm -- the congrats overlay's layer (ShopController's)
local LABEL_KIND: Theme.TextKind = "Coin"
local COMMON_STUDS = P.rarityStuds.Common
local MAX_SPOTS = Config.Economy.Pen.maxSpots
local SIGN_POP = Timeline.new(P.signPop)
local CENTRE_UP = 1.5 -- reading: the pen's bounding sphere sits this high, its radius the half diagonal + SPHERE_PAD
local SPHERE_PAD = 3

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
	for _, look in looks do
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
		if pens[pen.plot] == pen then
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

-- One frame of every pen near the camera and of the sign pop (see the header).
local function step(dt: number, _now: number): boolean
	stepPop()
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
	-- Nothing to register: the pens are world objects, the sign's prompt is BaseService's.
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
