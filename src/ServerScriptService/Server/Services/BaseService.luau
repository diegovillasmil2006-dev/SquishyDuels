--!strict
-- BaseService (server only). Lobby bases spec 2026-10-11 §2, §4, §6, §8; build plan Phases 3 and 4; Neon Sugar lobby
-- part 4 (2026-10-24, owner: "yes, start part 4 like that"): the plots are Diego's 12 pens (WorldLayout.Bases), one
-- per player in the server:
-- * playerAdded: the lowest free plot. It goes to the Player attribute SD_Plot (1..12; clients read it) and the
--   pen's arch nameplate shows the player's DisplayName (the owner view below). The player spawns in front of the
--   pen's arch (its SpawnLocation, WorldLayout.Tags.BaseSpawn with the Plot attribute) once the world has one;
--   without it CharacterService's lobby spawn stays. With no plot free (a player who left is freed on their leave
--   hook, so only briefly, or in a Studio test with more players than plots), it tries again every RETRY_SECONDS for
--   RETRY_FOR_SECONDS while the player waits in the hub; a plot found later is used from their next respawn.
-- * Batch 3 (friends, review #6): a player who joined from a friend's invite (GetJoinData().ReferredByPlayerId) or
--   followed a friend in (Player.FollowUserId) while that friend has a plot here gets the free plot nearest to the
--   friend's on the ring (min(|i - p|, PLOT_COUNT - |i - p|); a tie takes the lower number) instead of the lowest one.
-- * playerRemoving: the plot is free again (OPEN PLOT, a blank board, every cubby locked). Rejoining gives the lowest
--   free plot again (maybe another one); the pen lives in the profile, so it comes back wherever the player lands.
-- * The owner view: render(plot) shows on the plot's pen Model (Tags.Base with that Plot) who owns it: the "Text"
--   label of Diego's Label_OpenPlot reads the owner's DisplayName, or Strings base.openPlot. No plot colours (owner
--   2026-10-24).
-- * The pen (pens3, wb: the whole base is the pen, owner 2026-10-17): a "Pen" Folder, replaced on every render, holds
--   what the owner's pen draws (drawPen), in the plot's frame from WorldLayout.Bases.pen and its steps[spots] (the
--   tier):
--   - Board: Diego's pen board (World/PenBoard) as the SurfaceGui "Board", its Adornee the pen's SignFace: row 1 PEN
--     SPACE, row 2 SHELF SPOTS (owner 2026-10-24; boardRows), each "buy" or "max" for everyone; the owner's client
--     repaints its own rows' buttons for its Coins ("need", Controllers/PenController).
--   - Buy spots: the Models "Sign" (PEN SPACE) and "ShelfSign" (SHELF SPOTS), each an invisible "Face" part at its
--     row (Bases.pen.signs) with attributes SD_PenSign / SD_ShelfSign = plot and SD_Price = the next buy's price (none
--     at MAX: PenMath.spotPrice, PenMath.shelfPrice) and its prompt (PenPrompt on E, ShelfPrompt on F: one board, so
--     two keys), a hold of Config.Economy.Pen.signHoldSeconds, off at MAX. The owner's client buys with them.
--   - Gate (pens3 phase 10; owner 2026-10-24 "Keep the photo gate sign", no bulbs or bow): the Model "Gate" (LK:87-96
--     pen_gate, K:700) at Bases.pen.gate: 2 GatePosts (they block) with their balls in the tier's post colour (L:187
--     GatePost tints), the SignFrame, the OwnerSign (P3D:245-251: the headshot in a PenOwnerDisc<n> disc, the display
--     name, "BASE n"), the NumberBadge disc reading the base number (P3D:268) and the VisitorBoard (a heart and "0
--     visitors" until phase 18, P3D:277); its GUIs as K:7872-7873 says (PixelsPerStud 25, hidden beyond 150 studs),
--     on P3D's planes 0.1 stud inside each face. The headshot (K:4271): deps.headshotOf(userId)
--     (Players:GetUserThumbnailAsync on its own thread, pcall), asked once per user and cached for the server's life,
--     painted on that owner's gate when it comes (after a failure it is asked again on the next draw).
--   - Shelf (pens3 phase 11): Diego's 12 cubbies (the pen's ShelfSlots) show which pen slots are open: cubby k is slot
--     maxSpots + k (Bases.pen.shelf; Neon Sugar part 5: the shelf spots in cubbies 1..11, the TOP spot in 12). An
--     open cubby hides its Lock and turns its ShelfBack PenShelfBackOn, a closed one shows them PenShelfBackOff (his
--     SquishyLobby.setSlotUnlocked); an open plot has every cubby closed.
--   - The base Model's attributes for every client's squishies (PenController): SD_PenSpots, SD_Pen (the walkers:
--     PenMath.encode of PenMath.inPen), SD_Shelf (the shelf's and the TOP spot's: PenMath.encodeShelf of
--     PenMath.onShelf; the clients stand them in their cubbies), SD_ShelfRows, SD_ShelfTop, SD_PenRate (every placed
--     squishy's, PenMath.rate), SD_PenIncome (INCOME step 2: PenMath.rateBoost, the coin labels' boost), SD_PenTier
--     and SD_PenOwner (the owner's UserId, for the gate motion, Controllers/PenLookController); none on an open plot.
--   A plot renders when it is handed out or freed, when its owner's profile loads (the data port's Loaded) and on
--   refresh(player) after a pen change (PenService: a spot bought, a squishy granted). Until the profile is ready a plot
--   shows its owner's name only; without the pen Model or with a broken pen nothing is drawn and nothing fails.
-- No remote ever names a plot: PenBuySpot always buys the caller's own next spot.
-- Dependencies are injectable (useDeps) so unit tests run without the world or the task scheduler; a player is only a
-- table key (an Instance also gets the attribute; a Player also gets the spawn). playerAdded / playerRemoving never
-- yield.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local PenBoard = require(Shared.World.PenBoard)
local PenMath = require(Shared.PenMath)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local StateService = require(script.Parent.StateService)
local WorldService = require(script.Parent.WorldService)

-- Types

export type Deps = {
	delay: (seconds: number, fn: () -> ()) -> (), -- task.delay
	spawnOf: (plot: number) -> SpawnLocation?, -- the plot's SpawnLocation in the generated world, or nil
	plotModel: (plot: number) -> Instance?, -- the plot's generated Model, or nil
	penOf: (player: any) -> any, -- the pen (Types.PenState) of the player's READY profile, or nil
	displayNameOf: (player: any) -> string,
	friendOf: (player: any) -> any?, -- Batch 3: the friend in this server who invited the player (or was followed)
	-- Pens3 phase 10: asks for the user's headshot and calls done with it later (nil when it could not be had).
	headshotOf: (userId: number, done: (image: string?) -> ()) -> (),
}

-- Constants

local PLOT_COUNT = #WorldLayout.Bases.frames
local ATTR_PLOT = "SD_Plot"
local TAG_SPAWN = WorldLayout.Tags.BaseSpawn
local ATTR_SPAWN_PLOT = WorldLayout.Attributes.Plot
local RETRY_FOR_SECONDS = 5 -- lobby spec §6: "it tries again for up to 5 s"
local RETRY_SECONDS = 0.5 -- reading (the spec gives no step)
local TAG_BASE = WorldLayout.Tags.Base
-- Neon Sugar part 4: the parts of Diego's pen Model the owner view writes on (his SquishyLobby API's names).
local OWNER_PLATE = "Label_OpenPlot" -- the arch nameplate; its LabelGui's TextLabel "Text"
local BOARD_FACE = "SignFace" -- the board's part
local SHELF_SLOTS = "ShelfSlots" -- ShelfSlot_01..12, each with a Lock Model and a ShelfBack part
-- Pens3 phase 1: the pen (see the header).
local PEN = WorldLayout.Bases.pen
local PEN_FOLDER = "Pen"
local PEN_ATTRS = {
	"SD_PenSpots",
	"SD_Pen",
	"SD_PenRate",
	"SD_PenIncome",
	"SD_PenTier",
	"SD_PenOwner",
	"SD_Shelf",
	"SD_ShelfRows",
	"SD_ShelfTop",
}
local TIER_COLORS = { -- K:4170-4189: the gate posts' colour per tier (L:187 GatePost tints)
	{ post = "PenFenceWaferPost" },
	{ post = "PenFenceMintPost" },
	{ post = "PenFenceRoyalPost" },
}
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Roblox cylinder runs along X: this stands it up
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a quarter turn about Y: a piece's X along the plot's Z
-- The gate's texts (Kit/Signs' look: LightInfluence 0.15, Fredoka One, ink text).
local SIGN_LIGHT = 0.15
local SIGN_FONT = Enum.Font.FredokaOne
local PROMPT_STUDS = 10 -- the plan
local BUY_SPOT_SIZE = Vector3.new(1, 1, 0.2) -- a buy spot's invisible Face (its prompt's anchor)
-- Reading (play test 2026-10-24): half the default prompt's width (158 px), so the prompt starts at its buy spot, right
-- of the board, and never covers a price.
local PROMPT_SHIFT = Vector2.new(80, 0)
-- Pens3 phase 10 (see the header): LK's pieces in piece studs (front -Z, the GUIs' side; turned like the board). A
-- cylinder turned by ALONG_Z has its +X end (the Right face) toward the front.
local GATE = { -- LK:87-96 pen_gate
	postSize = Vector3.new(12, 1.2, 1.2), -- r 0.6, 12 tall at x ±4
	postX = 4,
	ballSize = Vector3.new(1.6, 1.6, 1.6), -- r 0.8 at y 12.3
	ballY = 12.3,
	frameSize = Vector3.new(8.4, 3.6, 0.3), -- from y 8.4, at z 0.3
	frame = CFrame.new(0, 8.4 + 3.6 / 2, 0.3),
	signSize = Vector3.new(7.4, 3, 0.4),
	sign = CFrame.new(0, 10.2, 0),
	badgeSize = Vector3.new(0.4, 2.2, 2.2), -- a disc r 1.1, 0.4 thick, facing the front
	badge = CFrame.new(0, 12.6, -0.1) * ALONG_Z,
	boardSize = Vector3.new(2.6, 1.2, 0.25),
	board = CFrame.new(-2.3, 7.55, -0.05),
}
-- K:7872-7873: the gate's SurfaceGuis at PixelsPerStud 25, hidden beyond 150 studs; P3D draws them on planes
-- GUI_INSET inside each face (P3D:267-269).
local GATE_PX_PER_STUD = 25
local GATE_GUI_STUDS = 150
local GUI_INSET = 0.1
-- P3D:245-251 the owner sign (shares of its 7.2 × 2.8 plane; text: P3D's canvas px over its 112-px height): the disc
-- r 0.36 h at (0.48 h, 0.5 h) with a 6-px ink ring (0.15 stud), the name at (0.6 w, 0.42 h) 88 px (74 past 5
-- letters), "BASE n" at (0.6 w, 0.8 h) 30 px. Reading: each text box 0.54 wide, from the disc to the right edge.
local OWNER_GUI = {
	disc = { x = 0.48 * 2.8 / 7.2, d = 0.72, ring = 0.15 },
	name = { x = 0.6, y = 0.42, w = 0.54, h = 0.66, short = 88 / 112, long = 74 / 112, shortLetters = 5 },
	base = { x = 0.6, y = 0.8, w = 0.54, h = 0.27, px = 30 / 112 },
}
local BADGE_GUI = { x = 0.5, y = 0.55, w = 1, h = 0.675, px = 54 / 80, stroke = 0.11 } -- P3D:268 on its 2-stud plane
local BOARD_GUI = { -- P3D:277 on its 2.4 × 1 plane (40 px tall): the heart 30 px at 0.28 w, the count 16 px at 0.62 w
	heart = { x = 0.28, y = 0.54, w = 0.24, h = 0.75, px = 30 / 40 },
	count = { x = 0.62, y = 0.54, w = 0.72, h = 0.4, px = 16 / 40 },
}
local HEADSHOT_TYPE = Enum.ThumbnailType.HeadShot
local HEADSHOT_SIZE = Enum.ThumbnailSize.Size150x150
local OWNER_DISCS = 6 -- Palette PenOwnerDisc1..6 (P3D:244)
local VISITORS_TODAY = 0 -- shortcut: phase 18 (visits) counts the visitors; the board reads 0 until then
-- The board's two buy spots (see the header): PEN SPACE and SHELF SPOTS, one key each (both on one board).
type SignKind = {
	model: string,
	at: CFrame,
	prompt: string,
	object: string,
	attribute: string,
	key: Enum.KeyCode,
	pad: Enum.KeyCode,
}
local SIGNS: { pen: SignKind, shelf: SignKind } = {
	pen = {
		model = "Sign",
		at = PEN.signs.pen,
		prompt = "PenPrompt",
		object = Strings.pen.prompt.object,
		attribute = "SD_PenSign",
		key = Enum.KeyCode.E,
		pad = Enum.KeyCode.ButtonX,
	},
	shelf = {
		model = "ShelfSign",
		at = PEN.signs.shelf,
		prompt = "ShelfPrompt",
		object = Strings.pen.shelfPrompt.object,
		attribute = "SD_ShelfSign",
		key = Enum.KeyCode.F,
		pad = Enum.KeyCode.ButtonY,
	},
}

-- Module table

local BaseService = {}

-- Private

local log = Log.new("Base")
local owners: { [number]: any } = {} -- plot -> player
local plots: { [any]: number } = {} -- player -> plot
local waiting: { [any]: boolean } = {} -- players with no plot yet, still retrying
local headshots: { [number]: string } = {} -- pens3 phase 10: UserId -> its headshot (kept for the server's life)
local asking: { [number]: boolean } = {} -- UserIds whose headshot is on its way

local function defaultDeps(): Deps
	return {
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
		spawnOf = function(plot: number): SpawnLocation?
			for _, instance in WorldService.stations(TAG_SPAWN) do
				if instance:IsA("SpawnLocation") and instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		plotModel = function(plot: number): Instance?
			for _, instance in WorldService.stations(TAG_BASE) do
				if instance:GetAttribute(ATTR_SPAWN_PLOT) == plot then
					return instance
				end
			end
			return nil
		end,
		penOf = function(player: any): any
			local port = StateService.dataPort()
			if port.status(player) ~= "ready" then
				return nil
			end
			local profile = port.getProfile(player)
			return if type(profile) == "table" then profile.pen else nil
		end,
		displayNameOf = function(player: any): string
			local ok, name = pcall(function(): any
				return player.DisplayName
			end)
			return if ok and type(name) == "string" then name else tostring(player)
		end,
		friendOf = function(player: any): any?
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return nil
			end
			local ok, data = pcall(player.GetJoinData, player) -- never yields
			local id = if ok and type(data) == "table" then (data :: any).ReferredByPlayerId else nil
			if type(id) ~= "number" or id <= 0 then
				id = player.FollowUserId
			end
			return if type(id) == "number" and id > 0 then Players:GetPlayerByUserId(id) else nil
		end,
		headshotOf = function(userId: number, done: (image: string?) -> ())
			task.spawn(function()
				local ok, image = pcall(function(): any
					return Players:GetUserThumbnailAsync(userId, HEADSHOT_TYPE, HEADSHOT_SIZE)
				end)
				done(if ok and type(image) == "string" then image else nil)
			end)
		end,
	}
end

local deps: Deps = defaultDeps()

-- Writes `text` on the pen's arch nameplate (Diego's SquishyLobby.setOwnerText).
local function setOwnerPlate(model: Instance, text: string)
	local plate = model:FindFirstChild(OWNER_PLATE)
	local label = if plate then plate:FindFirstChild("Text", true) else nil
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

-- A visual part of the pen: anchored, out of collisions, queries, touches and shadows.
local function piece(
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- The part blocks players but stays out of queries (Kit/Prims' barrier order: CanQuery false after CanCollide).
local function block(part: Part): Part
	part.CanCollide = true
	part.CanQuery = false
	return part
end

-- A TextLabel of the sign face, scaled to its box under the text size `px`.
local function signLabel(name: string, text: string, px: number, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = SIGN_FONT
	label.Text = text
	label.TextColor3 = Palette.PenSignText
	label.TextScaled = true
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = px
	cap.Parent = label
	label.Parent = parent
	return label
end

-- Neon Sugar part 4 (see the header): a board row's buy spot, `kind` (PEN SPACE or SHELF SPOTS); `price` is the next
-- buy's, nil at MAX.
local function drawBuySpot(folder: Instance, frame: CFrame, plot: number, price: number?, kind: SignKind)
	local at = frame * kind.at
	local sign = Instance.new("Model")
	sign.Name = kind.model
	local face = piece("Face", Enum.PartType.Block, BUY_SPOT_SIZE, at, Palette.PenBoardBg, sign)
	face.Transparency = 1
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = kind.prompt
	prompt.ActionText = Strings.pen.prompt.action -- "Buy" (pen.shelfPrompt.action says the same)
	prompt.ObjectText = kind.object
	prompt.HoldDuration = Config.Economy.Pen.signHoldSeconds
	prompt.MaxActivationDistance = PROMPT_STUDS
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = kind.key
	prompt.GamepadKeyCode = kind.pad
	prompt.UIOffset = PROMPT_SHIFT
	prompt.Enabled = price ~= nil
	prompt.Parent = face
	sign:SetAttribute(kind.attribute, plot)
	sign:SetAttribute("SD_Price", price)
	sign.WorldPivot = at
	sign.Parent = folder
end

-- Diego's board on the pen's SignFace, both rows as everyone sees them (see the header).
local function drawBoard(folder: Instance, model: Instance, pen: any)
	local board = PenBoard.build(folder)
	local face = model:FindFirstChild(BOARD_FACE)
	board.Adornee = if face and face:IsA("BasePart") then face else nil
	local penRow, shelfRow = BaseService.boardRows(pen)
	PenBoard.setRow(PenBoard.row(board, 1) :: Frame, penRow)
	PenBoard.setRow(PenBoard.row(board, 2) :: Frame, shelfRow)
end

-- Diego's cubbies show which shelf slots are open (see the header); `pen` nil: an open plot, every cubby closed.
local function paintSlots(model: Instance, pen: any?)
	local slots = model:FindFirstChild(SHELF_SLOTS)
	if slots == nil then
		return
	end
	for index in PEN.shelf.cubbies do
		local slot = slots:FindFirstChild(string.format("ShelfSlot_%02d", index))
		local open = pen ~= nil and PenMath.isOpen(pen, Config.Economy.Pen.maxSpots + index)
		local lock = if slot then slot:FindFirstChild("Lock") else nil
		if lock then
			for _, part in lock:GetDescendants() do
				if part:IsA("BasePart") then
					part.Transparency = if open then 1 else 0
					part.CanCollide = not open
				end
			end
		end
		local back = if slot then slot:FindFirstChild("ShelfBack") else nil
		if back and back:IsA("BasePart") then
			back.Color = if open then Palette.PenShelfBackOn else Palette.PenShelfBackOff
		end
	end
end

-- Pens3 phase 10 (see the header) -----------------------------------------------------------------------------------

-- The player's UserId, or nil (a test's Folder player has none).
local function userIdOf(player: any): number?
	local ok, id = pcall(function(): any
		return player.UserId
	end)
	return if ok and type(id) == "number" and id > 0 then id else nil
end


-- A SurfaceGui on `face` (`width` × `height` studs) of `part`, K:7872-7873's way, and its design plane `inset` studs
-- inside the face (P3D's).
local function gateGui(part: BasePart, face: Enum.NormalId, width: number, height: number, inset: number): Frame
	local gui = Instance.new("SurfaceGui")
	gui.Name = "GateGui"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = GATE_PX_PER_STUD
	gui.LightInfluence = SIGN_LIGHT
	gui.MaxDistance = GATE_GUI_STUDS
	local plane = Instance.new("Frame")
	plane.Name = "Plane"
	plane.BackgroundTransparency = 1
	plane.AnchorPoint = Vector2.new(0.5, 0.5)
	plane.Position = UDim2.fromScale(0.5, 0.5)
	plane.Size = UDim2.fromScale((width - 2 * inset) / width, (height - 2 * inset) / height)
	plane.Parent = gui
	gui.Parent = part
	return plane
end

-- A label on a plane `height` studs tall: its centre and size as shares of the plane, its text at most `share` of
-- the plane's height.
local function planeLabel(name: string, text: string, plane: Frame, height: number, box: any, share: number): TextLabel
	local label = signLabel(name, text, math.floor(share * height * GATE_PX_PER_STUD), plane)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(box.x, box.y)
	label.Size = UDim2.fromScale(box.w, box.h)
	return label
end

local function round(gui: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = gui
end

-- Paints a user's headshot on every gate of theirs on the island now (it came after the gate was drawn).
local function paintHeadshot(userId: number, image: string)
	for plot, owner in owners do
		if userIdOf(owner) == userId then
			local model = deps.plotModel(plot)
			local pen = if model then model:FindFirstChild(PEN_FOLDER) else nil
			local gate = if pen then pen:FindFirstChild("Gate") else nil
			local label = if gate then gate:FindFirstChild("Headshot", true) else nil
			if label and label:IsA("ImageLabel") then
				label.Image = image
			end
		end
	end
end

-- The owner's headshot when the server has it, else "" (and it is asked for, once at a time).
local function headshotFor(owner: any): string
	local id = userIdOf(owner)
	if id == nil then
		return ""
	end
	if headshots[id] == nil and not asking[id] then
		asking[id] = true
		deps.headshotOf(id, function(image: string?)
			asking[id] = nil
			if image ~= nil then
				headshots[id] = image
				paintHeadshot(id, image)
			end
		end)
	end
	return headshots[id] or "" -- read again: a dep may answer at once
end

-- The owner sign's face (P3D:245-251, OWNER_GUI).
local function drawOwnerGui(sign: BasePart, plot: number, name: string, image: string)
	local size = GATE.signSize
	local plane = gateGui(sign, Enum.NormalId.Front, size.X, size.Y, GUI_INSET)
	local height = size.Y - 2 * GUI_INSET
	local disc = Instance.new("Frame")
	disc.Name = "HeadshotDisc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(OWNER_GUI.disc.x, 0.5)
	disc.Size = UDim2.fromScale(OWNER_GUI.disc.d * height / (size.X - 2 * GUI_INSET), OWNER_GUI.disc.d)
	disc.BackgroundColor3 = Palette["PenOwnerDisc" .. (plot - 1) % OWNER_DISCS + 1]
	round(disc)
	local ring = Instance.new("UIStroke")
	ring.Color = Palette.PenSignText
	ring.Thickness = OWNER_GUI.disc.ring * GATE_PX_PER_STUD
	ring.Parent = disc
	local headshot = Instance.new("ImageLabel")
	headshot.Name = "Headshot"
	headshot.BackgroundTransparency = 1
	headshot.Size = UDim2.fromScale(1, 1)
	headshot.ScaleType = Enum.ScaleType.Crop
	headshot.Image = image
	round(headshot)
	headshot.Parent = disc
	disc.Parent = plane
	local n = OWNER_GUI.name
	local letters = utf8.len(name) or #name
	local share = if letters > n.shortLetters then n.long else n.short
	planeLabel("OwnerName", name, plane, height, n, share)
	local base = Strings.format(Strings.pen.gate.base, { n = plot })
	planeLabel("BaseLine", base, plane, height, OWNER_GUI.base, OWNER_GUI.base.px).TextColor3 = Palette.PenGateBaseText
end

-- The gate (see the header): posts, frame, owner sign, number badge and visitor board.
local function drawGate(folder: Instance, at: CFrame, plot: number, step: WorldLayout.PenStep, owner: any, name: string)
	local post = Palette[(TIER_COLORS[step.tier] or TIER_COLORS[1]).post]
	local gate = Instance.new("Model")
	gate.Name = "Gate"
	for _, x in { -GATE.postX, GATE.postX } do
		local base = at * CFrame.new(x, 0, 0)
		local size = GATE.postSize
		block(
			piece("GatePost", Enum.PartType.Cylinder, size, base * CFrame.new(0, size.X / 2, 0) * UPRIGHT, post, gate)
		)
		piece("GatePostTop", Enum.PartType.Ball, GATE.ballSize, base * CFrame.new(0, GATE.ballY, 0), post, gate)
	end
	piece("SignFrame", Enum.PartType.Block, GATE.frameSize, at * GATE.frame, Palette.PenBoardFrame, gate)
	local sign = piece("OwnerSign", Enum.PartType.Block, GATE.signSize, at * GATE.sign, Palette.PenSignFace, gate)
	drawOwnerGui(sign, plot, name, headshotFor(owner))
	local badge =
		piece("NumberBadge", Enum.PartType.Cylinder, GATE.badgeSize, at * GATE.badge, Palette.PenGateBadge, gate)
	local badgeSide = GATE.badgeSize.Y
	local badgePlane = gateGui(badge, Enum.NormalId.Right, badgeSide, badgeSide, GUI_INSET)
	local b = BADGE_GUI
	local number = planeLabel("Number", tostring(plot), badgePlane, badgeSide - 2 * GUI_INSET, b, b.px)
	number.TextColor3 = Palette.PenLabelText
	local stroke = Instance.new("UIStroke")
	stroke.Color = Palette.PenLabelStroke
	stroke.Thickness = b.stroke * b.px * (badgeSide - 2 * GUI_INSET) * GATE_PX_PER_STUD
	stroke.Parent = number
	local board =
		piece("VisitorBoard", Enum.PartType.Block, GATE.boardSize, at * GATE.board, Palette.PenGateBoard, gate)
	local boardPlane = gateGui(board, Enum.NormalId.Front, GATE.boardSize.X, GATE.boardSize.Y, GUI_INSET)
	boardPlane.BackgroundTransparency = 0
	boardPlane.BackgroundColor3 = Palette.PenGateBoardFace
	boardPlane.BorderSizePixel = 0
	local boardHeight = GATE.boardSize.Y - 2 * GUI_INSET
	local heart = BOARD_GUI.heart
	planeLabel("Heart", Strings.pen.gate.heart, boardPlane, boardHeight, heart, heart.px).TextColor3 =
		Palette.PenGateHeart
	local count = BOARD_GUI.count
	planeLabel("Count", BaseService.visitorText(VISITORS_TODAY), boardPlane, boardHeight, count, count.px)
	gate.WorldPivot = at
	gate.Parent = folder
end

-- The owner's pen on the plot (see the header): a fresh "Pen" Folder, the cubbies and the base Model's pen attributes.
-- False (and nothing drawn) for a spot count with no step.
local function drawPen(model: Instance, plot: number, pen: any, owner: any, name: string): boolean
	local step = PEN.steps[pen.spots]
	local frame = WorldLayout.plotFrame(plot)
	if step == nil or frame == nil then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = PEN_FOLDER
	drawBoard(folder, model, pen)
	drawBuySpot(folder, frame, plot, PenMath.spotPrice(pen.spots + 1), SIGNS.pen)
	drawBuySpot(folder, frame, plot, PenMath.shelfPrice(pen), SIGNS.shelf)
	drawGate(folder, frame * PEN.gate, plot, step, owner, name)
	folder.Parent = model
	paintSlots(model, pen)
	model:SetAttribute("SD_PenSpots", pen.spots)
	model:SetAttribute("SD_Pen", PenMath.encode(PenMath.inPen(pen))) -- pens3 phase 11: the walkers only
	model:SetAttribute("SD_Shelf", PenMath.encodeShelf(PenMath.onShelf(pen)))
	model:SetAttribute("SD_ShelfRows", pen.shelfRows)
	model:SetAttribute("SD_ShelfTop", pen.top == true)
	model:SetAttribute("SD_PenRate", PenMath.rate(pen))
	model:SetAttribute("SD_PenIncome", PenMath.rateBoost(pen))
	model:SetAttribute("SD_PenTier", step.tier)
	model:SetAttribute("SD_PenOwner", userIdOf(owner))
	return true
end

-- Shows the plot's owner on its pen Model, or an open plot (see the header). Never throws.
local function render(plot: number)
	local ok, err = pcall(function(): any
		local model = deps.plotModel(plot)
		if model == nil then
			return nil
		end
		local owner = owners[plot]
		local name = if owner ~= nil then deps.displayNameOf(owner) else Strings.resolve("base.openPlot") or ""
		setOwnerPlate(model, name)
		local old = model:FindFirstChild(PEN_FOLDER)
		if old then
			old:Destroy()
		end
		local pen = if owner ~= nil then deps.penOf(owner) else nil
		if type(pen) ~= "table" or not drawPen(model, plot, pen, owner, name) then
			paintSlots(model, nil)
			for _, attribute in PEN_ATTRS do
				model:SetAttribute(attribute, nil) -- not cleared before a draw, so a client never sees a gap
			end
		end
		return nil
	end)
	if not ok then
		log:warn(`could not draw plot {plot}:`, err)
	end
end

-- The free plot for the player: the one nearest their friend's plot on the ring (Batch 3; a tie takes the lower
-- number), else the lowest free one; nil when all are taken.
local function freePlot(player: any): number?
	local friend = deps.friendOf(player)
	local near = if friend ~= nil then plots[friend] else nil
	local best, bestGap = nil, math.huge
	for plot = 1, PLOT_COUNT do
		if owners[plot] == nil then
			if near == nil then
				return plot
			end
			local gap = math.abs(plot - near)
			gap = math.min(gap, PLOT_COUNT - gap)
			if gap < bestGap then
				best, bestGap = plot, gap
			end
		end
	end
	return best
end

-- Gives the player a free plot (freePlot, and its spawn, when the world has it). Returns it, or nil when all are taken.
local function assign(player: any): number?
	local plot = freePlot(player)
	if plot == nil then
		return nil
	end
	owners[plot] = player
	plots[player] = plot
	if typeof(player) == "Instance" then
		(player :: Instance):SetAttribute(ATTR_PLOT, plot)
		local spawn = deps.spawnOf(plot)
		if spawn and (player :: Instance):IsA("Player") then
			(player :: Player).RespawnLocation = spawn
		end
	end
	render(plot)
	return plot
end

-- Public

-- The player's plot (1..12), or nil while they have none.
function BaseService.plotOf(player: any): number?
	return plots[player]
end

-- The player on plot `plot`, or nil for an open plot.
function BaseService.ownerOf(plot: number): any?
	return owners[plot]
end

-- Redraws the player's plot (their profile loaded, or their pen changed). Nothing for a player without a plot.
function BaseService.refresh(player: any)
	local plot = plots[player]
	if plot ~= nil then
		render(plot)
	end
end

-- Replaces dependencies (fields not given keep their defaults). nil restores every default.
function BaseService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	if overrides then
		for key, value in overrides do
			fresh[key] = value
		end
	end
	deps = fresh
end

-- Pens3 phase 10: the visitor board's line (P3D:277): "1 visitor", else "N visitors".
function BaseService.visitorText(count: number): string
	local text = if count == 1 then Strings.pen.gate.visitor else Strings.pen.gate.visitors
	return Strings.format(text, { count = count })
end

-- Neon Sugar part 4: a pen's two board rows as everyone sees them (owner 2026-10-24). Row 1 PEN SPACE: the open spots
-- of maxSpots and the next spot's price. Row 2 SHELF SPOTS: the open shelf spots of all of them with the TOP spot,
-- the next row's (or the TOP spot's) price. "buy", or "max" with nothing left to buy (its count stays after the arrow).
function BaseService.boardRows(pen: any): (PenBoard.Row, PenBoard.Row)
	local P = Config.Economy.Pen
	local function row(title: string, open: number, nextOpen: number, total: number, price: number?): PenBoard.Row
		return {
			title = title,
			icon = "shelf", -- both rows buy spots (Diego's other picture is for an income upgrade)
			from = tostring(open),
			to = Strings.format(Strings.pen.board.spots, { n = if price then nextOpen else open }),
			filled = open,
			total = total,
			progress = Strings.format(Strings.pen.board.progress, { n = open, total = total }),
			price = if price then Format.coins(price) else "",
			state = if price then "buy" else "max",
		}
	end
	local spots = pen.spots
	local rows = if type(pen.shelfRows) == "number" then pen.shelfRows else 0
	local shelfOpen = rows * P.shelfRowSpots + (if pen.top == true then 1 else 0)
	local shelfNext = shelfOpen + (if rows < P.shelfMaxRows then P.shelfRowSpots else 1)
	return row(Strings.pen.sign.title, spots, spots + 1, P.maxSpots, PenMath.spotPrice(spots + 1)),
		row(
			Strings.pen.shelfSign.title,
			shelfOpen,
			shelfNext,
			P.shelfMaxRows * P.shelfRowSpots + 1,
			PenMath.shelfPrice(pen)
		)
end

-- Frees every plot and stops every retry (tests; not called by the bootstrap).
function BaseService.reset()
	table.clear(owners)
	table.clear(plots)
	table.clear(waiting)
	table.clear(headshots) -- pens3 phase 10
	table.clear(asking)
end

-- Lifecycle

function BaseService.init()
	StateService.dataPort().onLoaded(function(player: any)
		BaseService.refresh(player)
	end)
end

function BaseService.playerAdded(player: Player)
	if plots[player] ~= nil or assign(player) ~= nil then
		return
	end
	waiting[player] = true
	local triesLeft = math.floor(RETRY_FOR_SECONDS / RETRY_SECONDS)
	local function retry()
		if not waiting[player] then
			return -- left (or reset) meanwhile
		end
		triesLeft -= 1
		if assign(player) ~= nil then
			waiting[player] = nil
		elseif triesLeft <= 0 then
			waiting[player] = nil
			log:warn(`no free plot for {tostring(player)} after {RETRY_FOR_SECONDS} s; they stay in the hub`)
		else
			deps.delay(RETRY_SECONDS, retry)
		end
	end
	deps.delay(RETRY_SECONDS, retry)
end

function BaseService.playerRemoving(player: Player)
	waiting[player] = nil
	local plot = plots[player]
	if plot ~= nil then
		plots[player] = nil
		owners[plot] = nil
		render(plot)
	end
end

return BaseService
