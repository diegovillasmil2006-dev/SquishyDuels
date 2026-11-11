--!strict
-- MatchLooksController (client only). Big job item 7 (2026-11-10; the owner's "Match looks: power-ups shown on the
-- player, teammate and enemy colours, spawn protection"; Diego drew none of it, so the look is the game's own: his team
-- colours and pod pictures, the lobby nameplate's foam chip, the candy kit's ring, heart and sparkle).
-- What every OTHER standing fighter of a running Team / Free for All match gets on this client (players and bots; who
-- and what = UI/MatchLooksFormat.cues from the match view; the numbers = Config/MatchLooks):
-- * A name tag over the head: a foam chip in the team's colour (Free for All: the enemy colour). A teammate's has the
--   candy heart (a second sign beside the colour) and shows through walls; an enemy's is hidden by walls and by
--   distance. Roblox's own overhead name is switched off on a tagged fighter and put back after.
-- * A ring on the floor in the same colour (an ImageHandleAdornment on the root: nothing is welded to the body).
-- * A live power-up: its HUD icon in a bubble over the tag (UI/PodFormat.look: Diego's pod pictures and colours) and a
--   few sparkles in that colour; the shield also gets a see-through shell (Material ForceField) that grows in.
-- * Spawn protection: a pale blinking shell until hits count again (the view's protectUntil).
-- The server sends every fighter's live power-ups (MatchParticipantView.buffs) and protectUntil; the ends are read
-- against the server clock here, so nothing waits for a new view. One Anim/Scheduler "render" effect while a match view
-- exists: the shells follow their fighter every frame; who has what is looked at again every refreshSeconds (a
-- respawned character, a power-up that ran out). The local player gets no look of their own (the HUD shows theirs).
-- Everything is client-made: the guis in PlayerGui (SD_MatchTag_<userId>, SD_MatchPower_<userId>), the rest in
-- Workspace.SD_MatchLooks (Ring_, Shield_, Protect_<userId>) and one Attachment (SD_MatchAura) under the root.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local LOOKS = require(Shared.Config.MatchLooks)
local Palette = require(Shared.Art.Palette)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Create = require(Client.UI.Create)
local MatchLooksFormat = require(Client.UI.MatchLooksFormat)
local MatchPodium = require(Client.UI.Match.MatchPodium)
local PodFormat = require(Client.UI.PodFormat)
local Theme = require(Client.UI.Theme)
local StateController = require(script.Parent.StateController)

-- Types

type Look = {
	userId: number,
	key: string, -- relation, team and name: a change rebuilds the tag and the ring
	model: Model,
	root: BasePart,
	humanoid: Humanoid?,
	display: Enum.HumanoidDisplayDistanceType?, -- Roblox's own overhead name, as it was
	tag: BillboardGui?,
	ring: ImageHandleAdornment?,
	power: string?,
	powerGui: BillboardGui?,
	aura: Attachment?,
	shield: BasePart?,
	bubble: BasePart?,
}

-- Constants

local FOLDER = "SD_MatchLooks"
local TAG_PREFIX = "SD_MatchTag_"
local POWER_PREFIX = "SD_MatchPower_"
local AURA_NAME = "SD_MatchAura"
local ROOT_PART = "HumanoidRootPart"
local TEXT_KIND: Theme.TextKind = "Chip"
local BANDS = Theme.Foam.chip
local BANDS_PX = BANDS.bevel + BANDS.drop
local PAD_X = 10
local GAP_PX = 4
local SHIELD_START = 0.05 -- the vault: the shell grows from 5 percent
local ICON_SHARE = 0.78 -- the icon inside its bubble

-- Module table

local MatchLooksController = {}

-- State

local log = Log.new("MatchLooks")
local cleanup: any = nil
local looks: { [number]: Look } = {}
local stepHandle: Scheduler.Handle? = nil
local lastRefresh = -math.huge
local preview: MatchLooksFormat.Cue? = nil -- Studio (debugShow): one pretend look on the local character

-- Private

local function colorOf(token: string): Color3
	local found = (Palette :: any)[token]
	return if typeof(found) == "Color3" then found else Palette.Cream
end

local function folder(): Instance
	local found = Workspace:FindFirstChild(FOLDER)
	if found == nil then
		local created = Instance.new("Folder")
		created.Name = FOLDER
		created.Parent = Workspace
		found = created
	end
	return found :: Instance
end

local function playerGui(): PlayerGui?
	local player = Players.LocalPlayer
	return if player then player:FindFirstChildOfClass("PlayerGui") else nil
end

-- The part a gui hangs over, and how far above it (a rig without a Head: the root, a little higher).
local function adornee(look: Look, headOffset: number): (BasePart, Vector3)
	local head = look.model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head, Vector3.new(0, headOffset, 0)
	end
	return look.root, Vector3.new(0, headOffset + LOOKS.Tag.rootToHeadStuds, 0)
end

-- A see-through shell that follows a fighter (step moves it; never welded).
local function shell(name: string, diameter: number, tint: Color3, transparency: number, at: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.ForceField
	part.Color = tint
	part.Transparency = transparency
	part.Size = Vector3.one * diameter
	part.CFrame = CFrame.new(at)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder()
	return part
end

local function buildTag(look: Look, cue: MatchLooksFormat.Cue)
	local gui = playerGui()
	if gui == nil then
		return
	end
	local T = LOOKS.Tag
	local spec = MatchLooksFormat.tag(cue, LOOKS)
	local heart = if spec.heart then AssetTable.image("img.kit.heart") else nil
	local heartPx = if heart then T.heartPx + GAP_PX else 0
	local stroke = Theme.Stroke.bar
	local width = math.ceil(Theme.textBounds(cue.name, TEXT_KIND).X + heartPx + 2 * PAD_X + 2 * stroke)
	local part, offset = adornee(look, T.headOffsetStuds)
	local board: BillboardGui = Create("BillboardGui", {
		Name = TAG_PREFIX .. cue.userId,
		Adornee = part,
		Size = UDim2.fromOffset(width, T.heightPx + BANDS_PX),
		StudsOffset = offset,
		MaxDistance = spec.maxDistance,
		AlwaysOnTop = spec.throughWalls,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Active = false,
	})
	local frame: Frame = Create("Frame", {
		Name = "Plate",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		Parent = board,
	})
	-- The lobby nameplate's foam chip ("tint": the face is the frame's own colour, the bands darken it).
	Theme.foam(frame, {
		radius = Theme.Radius.pill,
		stroke = stroke,
		mode = "tint",
		bevel = BANDS.bevel,
		drop = BANDS.drop,
		colors = { face = Theme.Colors.frosting, bevel = Theme.Colors.stickerBevel, drop = Theme.Colors.inkUI },
	})
	frame.BackgroundColor3 = colorOf(spec.color)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PAD_X),
		PaddingRight = UDim.new(0, PAD_X),
		PaddingBottom = UDim.new(0, BANDS_PX),
		Parent = frame,
	})
	if heart then
		Create("ImageLabel", {
			Name = "Heart",
			BackgroundTransparency = 1,
			Image = heart,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(T.heartPx, T.heartPx),
			Parent = frame,
		})
	end
	local label = Theme.label({
		Name = "Text",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.new(1, -heartPx, 1, 0),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, TEXT_KIND, nil, Palette.Cream)
	label.Text = cue.name
	board.Parent = gui
	look.tag = board
	-- Roblox's own overhead name would double the tag.
	local humanoid = look.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		look.humanoid, look.display = humanoid, humanoid.DisplayDistanceType
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function buildRing(look: Look, cue: MatchLooksFormat.Cue)
	local image = AssetTable.image("img.kit.ring")
	if image == nil then
		return
	end
	local R = LOOKS.Ring
	local ring = Instance.new("ImageHandleAdornment")
	ring.Name = "Ring_" .. cue.userId
	ring.Adornee = look.root
	ring.Image = image
	ring.Color3 = colorOf(MatchLooksFormat.tag(cue, LOOKS).color)
	ring.Size = Vector2.new(R.diameterStuds, R.diameterStuds)
	-- flat under the feet, its picture side up (an adornment's picture shows from one side only: seen 2026-11-10)
	ring.CFrame = CFrame.new(0, -R.belowRootStuds, 0) * CFrame.Angles(math.rad(90), 0, 0)
	ring.Transparency = R.transparency
	ring.AlwaysOnTop = false
	ring.Parent = folder()
	look.ring = ring
end

-- The power-up shown on a fighter (nil = none): its icon bubble, its sparkles and, for the shield, its shell.
local function setPower(look: Look, kind: string?)
	if look.power == kind then
		return
	end
	for _, piece in { look.powerGui, look.aura, look.shield } :: { Instance? } do
		if piece then
			piece:Destroy()
		end
	end
	look.power, look.powerGui, look.aura, look.shield = kind, nil, nil, nil
	if kind == nil then
		return
	end
	local P = LOOKS.Power
	local pod = PodFormat.look(kind)
	local tint = if pod then pod.color else Palette.Cream
	local gui = playerGui()
	local icon = if pod then AssetTable.image(pod.icon) else nil
	if gui and icon then
		-- At the tag's own spot, lifted by its own size in px (SizeOffset), so it sits just over the tag at any
		-- distance (two stud offsets would drift apart up close and overlap far away).
		local part, offset = adornee(look, LOOKS.Tag.headOffsetStuds)
		local lift = ((LOOKS.Tag.heightPx + BANDS_PX) / 2 + P.gapPx) / P.iconPx + 0.5
		local board: BillboardGui = Create("BillboardGui", {
			Name = POWER_PREFIX .. look.userId,
			Adornee = part,
			Size = UDim2.fromOffset(P.iconPx, P.iconPx),
			StudsOffset = offset,
			SizeOffset = Vector2.new(0, lift),
			MaxDistance = P.maxDistance,
			AlwaysOnTop = false,
			LightInfluence = 0,
			ResetOnSpawn = false,
			Active = false,
		})
		local disc: Frame = Create("Frame", {
			Name = "Disc",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
			Parent = board,
		})
		Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = disc })
		Create("UIStroke", { Color = Theme.Colors.inkUI, Thickness = Theme.Stroke.bar, Parent = disc })
		Create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = icon,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(ICON_SHARE, ICON_SHARE),
			Parent = disc,
		})
		board.Parent = gui
		look.powerGui = board
	end
	local sparkle = AssetTable.image("img.kit.sparkle")
	if sparkle then
		local at = Instance.new("Attachment")
		at.Name = AURA_NAME
		local emitter = Instance.new("ParticleEmitter")
		emitter.Texture = sparkle
		emitter.Color = ColorSequence.new(tint)
		emitter.Rate = P.sparkleRate
		emitter.Lifetime = P.sparkleLifetime
		emitter.Speed = P.sparkleSpeed
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Drag = P.sparkleDrag
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-90, 90)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.25, P.sparkleSizeStuds),
			NumberSequenceKeypoint.new(1, 0),
		})
		emitter.LightEmission = 0.3
		emitter.LightInfluence = 0
		emitter.ZOffset = 1.5 -- in front of the body, never inside it
		emitter.LockedToPart = true
		emitter.Parent = at
		at.Parent = look.root
		look.aura = at
	end
	if kind == "shield" then
		local S = LOOKS.Shield
		local small = S.diameterStuds * SHIELD_START
		local part = shell("Shield_" .. look.userId, small, tint, S.transparency, look.root.Position)
		local grow = TweenInfo.new(S.growSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		TweenService:Create(part, grow, { Size = Vector3.one * S.diameterStuds }):Play()
		look.shield = part
	end
end

local function setProtected(look: Look, on: boolean)
	local bubble = look.bubble
	if on == (bubble ~= nil) then
		return
	end
	if bubble then
		bubble:Destroy()
		look.bubble = nil
		return
	end
	local P = LOOKS.Protect
	local at = look.root.Position
	look.bubble = shell("Protect_" .. look.userId, P.diameterStuds, colorOf(P.color), P.transparencyMin, at)
end

local function clear(userId: number)
	local look = looks[userId]
	if look == nil then
		return
	end
	looks[userId] = nil
	setPower(look, nil)
	setProtected(look, false)
	for _, piece in { look.tag, look.ring } :: { Instance? } do
		if piece then
			piece:Destroy()
		end
	end
	local humanoid = look.humanoid
	if humanoid and humanoid.Parent ~= nil and look.display then
		humanoid.DisplayDistanceType = look.display
	end
end

local function refresh()
	local view: any = StateController.match()
	local player = Players.LocalPlayer
	local cues: { MatchLooksFormat.Cue } = {}
	if LOOKS.enabled and view ~= nil then
		local now = Workspace:GetServerTimeNow()
		cues = MatchLooksFormat.cues(view, if player then player.UserId else nil, now, Config.Match.teamNames)
	end
	if preview then
		table.insert(cues, preview)
	end
	local wanted: { [number]: boolean } = {}
	for _, cue in cues do
		local model: Model? = nil
		if cue == preview then
			model = if player then player.Character else nil
		else
			model = MatchPodium.sourceCharacter(view, false, cue.userId)
		end
		local root = if model then model:FindFirstChild(ROOT_PART) else nil
		if model == nil or root == nil or not root:IsA("BasePart") then
			continue -- not streamed in, or between two characters: next look
		end
		wanted[cue.userId] = true
		local key = `{cue.relation}|{cue.team}|{cue.name}`
		local look = looks[cue.userId]
		if look and (look.model ~= model or look.root ~= root or look.key ~= key) then
			clear(cue.userId)
			look = nil
		end
		if look == nil then
			local made: Look = { userId = cue.userId, key = key, model = model, root = root }
			looks[cue.userId] = made
			if LOOKS.Tag.enabled then
				buildTag(made, cue)
			end
			if LOOKS.Ring.enabled then
				buildRing(made, cue)
			end
			look = made
		end
		setPower(look :: Look, if LOOKS.Power.enabled then cue.powers[1] else nil)
		setProtected(look :: Look, LOOKS.Protect.enabled and cue.protected)
	end
	for userId in table.clone(looks) do
		if not wanted[userId] then
			clear(userId)
		end
	end
end

-- Every frame while a match view exists: the shells follow their fighter, the protection shell blinks.
local function step(): boolean
	local now = os.clock()
	if now - lastRefresh >= LOOKS.refreshSeconds then
		lastRefresh = now
		refresh()
	end
	local P = LOOKS.Protect
	local wave = 0.5 + 0.5 * math.sin(now * P.blinkHz * 2 * math.pi)
	for _, look in looks do
		local shield, bubble = look.shield, look.bubble
		if shield or bubble then
			local at = CFrame.new(look.root.Position)
			if shield then
				shield.CFrame = at
			end
			if bubble then
				bubble.CFrame = at
				bubble.Transparency = P.transparencyMin + (P.transparencyMax - P.transparencyMin) * wave
			end
		end
	end
	return StateController.match() ~= nil or preview ~= nil or next(looks) ~= nil
end

local function ensureStepping()
	if stepHandle ~= nil then
		return
	end
	stepHandle = Scheduler.add(function(): boolean
		local ok, alive = pcall(step)
		if not ok then
			log:error("match looks update failed:", alive)
		end
		local keep = ok and alive == true
		if not keep then
			stepHandle = nil
		end
		return keep
	end, "render")
end

-- Public

-- Studio checks: how many fighters have a look, and what each shows.
function MatchLooksController.debugState(): { [string]: any }
	local fighters: { [string]: any } = {}
	local count = 0
	for userId, look in looks do
		count += 1
		fighters[tostring(userId)] = {
			tag = look.tag ~= nil,
			ring = look.ring ~= nil,
			power = look.power,
			shield = look.shield ~= nil,
			protected = look.bubble ~= nil,
		}
	end
	return { count = count, fighters = fighters, stepping = stepHandle ~= nil }
end

-- Studio (SD_DebugClient "matchLooks"): one pretend look on the local character, for a picture outside a match:
-- spec = { relation = "mate" | "foe", team = 1 | 2, power = a power-up kind, protected = true, name = text }; nil ends
-- it. Returns debugState() after the look is drawn.
function MatchLooksController.debugShow(spec: { [string]: any }?): { [string]: any }
	preview = nil
	if type(spec) == "table" then
		preview = {
			userId = 0,
			name = if type(spec.name) == "string" then spec.name else "Squishy_Fan",
			relation = if spec.relation == "mate" then "mate" else "foe",
			team = if spec.team == 1 or spec.team == 2 then spec.team else nil,
			powers = if type(spec.power) == "string" then { spec.power } else {},
			protected = spec.protected == true,
		}
		ensureStepping()
	end
	refresh()
	return MatchLooksController.debugState()
end

-- Lifecycle

function MatchLooksController.init()
	cleanup = Cleanup.new()
end

function MatchLooksController.start()
	local c = cleanup
	if c == nil then
		return
	end
	c:add(StateController.MatchChanged:connect(function()
		lastRefresh = -math.huge -- look again on the next frame
		if StateController.match() ~= nil then
			ensureStepping()
		end
	end))
	c:add(function()
		for userId in table.clone(looks) do
			clear(userId)
		end
		local handle = stepHandle
		if handle then
			handle:disconnect()
			stepHandle = nil
		end
	end)
	if StateController.match() ~= nil then
		ensureStepping()
	end
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function MatchLooksController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return MatchLooksController
