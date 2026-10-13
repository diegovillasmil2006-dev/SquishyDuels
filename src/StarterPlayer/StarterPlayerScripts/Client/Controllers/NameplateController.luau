--!strict
-- NameplateController (client only). DESIGN §17.7 "World → Nameplate", §17.2 rule 1, §7.7 (the lobby's SurfaceGui
-- budget: nameplates are BillboardGuis built by the client, never SurfaceGuis), §17.1 ("It shows above your head").
-- * One BillboardGui per player character (the local player's too), in this client's PlayerGui with the character's
--   Head (else its HumanoidRootPart) as Adornee: "Lv 23 · Strong Grip" (grip.nameplate, the rank from GripMath) on a
--   plate in the rank's colour, always text plus colour (§17.3.3). Shown within Config.Grip.Nameplate.maxDistance
--   (60 studs, BillboardGui.MaxDistance).
-- * The level is the server-written Player attribute SD_GripLevel (§17.10); a player without it shows no plate.
-- * Hidden while the viewer's or the target's SD_DuelPhase is not "" (§17.2 rule 1: Grip is never visible in duels).
-- * A level change pops the plate (UIScale Nameplate.popScale -> 1 over popSeconds, Back Out); under ReducedMotion it
--   stays still (Anim/Tweens). It sits Nameplate.headOffsetStuds above the head.
-- * Config.Grip.Nameplate.enabled = false turns every nameplate off (nothing is created).
-- reading: DESIGN gives no rank colours; RANK_COLORS picks light Palette tokens so the Ink text keeps its contrast.
-- * Part 8 polish (§17.11 "nameplate polish and ReducedMotion"; DESIGN lists no details, so Readings, the simplest):
--   - A soft fade over the last Config.Grip.Nameplate.fadeStuds (10) studs before maxDistance (fadeTransparency,
--     pure): the plate, its stroke and its text go from solid to clear as the camera moves away, so it never pops out
--     at 60 studs. One task loop refreshes every plate every checkSeconds (0.25 s), never per frame. Transparency only,
--     no motion, so it also runs under ReducedMotion (the level pop stays off there, as built).
--   - The plate is sized to its text at every GuiService.PreferredTextSize (plateSize, pure, from the label's
--     TextBounds; an estimate until the text is measured): "Lv 50 · Squish Master" never clips. The text size follows
--     a PreferredTextSize change.
--   - The local player's own plate hides while the camera is within ownHideStuds (1.5) of its Head (first person,
--     ownHidden, pure), checked by the same loop. Foam fix 2 (2026-10-09): it also stays hidden on the compact layout
--     (UIController.layoutClass, phones): the HUD's tile row sits at its height in the lobby (the Daily tile covered
--     its start) and the compact Grip card beside the coin capsule shows the same "Lv 8 · Soft Grip". Other players
--     still see it (their clients draw it).
-- * Foam UI restyle (2026-10-09; spec docs/superpowers/specs/2026-10-09-foam-ui-restyle-design.md; look only): the
--   plate is a foam chip (UI/Theme.foam "tint": the rank colour stays its face, with the chip's bevel and InkUI drop
--   bands along its bottom and the InkUI 2 px outline of chips), its text the Chip display kind (Fredoka One) in
--   InkUI, raised above the bands; plateSize counts the bands. Visibility, the fade, the pop and the sizes' rules are
--   unchanged.

-- Services

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local GripMath = require(Shared.GripMath)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Tweens = require(Client.Anim.Tweens)
local Create = require(Client.UI.Create)
local Theme = require(Client.UI.Theme)
local UIController = require(script.Parent.UIController)

-- Types

-- A Util/Cleanup as stored in records (its generic add<T>() trips the exact record comparison of the type checker).
type Trove = {
	add: (self: any, item: any) -> any,
	clean: (self: any) -> (),
}

type Plate = {
	player: Player,
	character: Model?, -- the character the plate is attached to
	gui: BillboardGui?,
	frame: Frame?,
	label: TextLabel?,
	stroke: UIStroke?,
	scale: UIScale?,
	shownLevel: number?,
	isHead: boolean, -- the Adornee is the Head (else the root part, ROOT_TO_HEAD_STUDS below it)
	baseVisible: boolean, -- visible() says it shows (the camera checks come on top)
	ownHidden: boolean, -- Part 8: the local player's own plate while the camera is in the head
	fade: number, -- Part 8: the transparency the distance fade last applied
	cleanup: Trove,
	characterCleanup: Trove?,
}

-- Constants

local NAMEPLATE = Config.Grip.Nameplate
local ATTR_LEVEL = "SD_GripLevel"
local ATTR_DUEL_PHASE = "SD_DuelPhase"
local GUI_PREFIX = "SD_Nameplate_"
local HEAD = "Head"
local ROOT_PART = "HumanoidRootPart"
local HEAD_WAIT_SECONDS = 5 -- reading: how long a streamed-in character may take to get its Head
-- reading (DESIGN gives no sizes): without a Head the plate hangs this much higher above the root part (the root is
-- about 2 studs below the head on R15 and R6).
local ROOT_TO_HEAD_STUDS = 2
-- Part 8 (plateSize): the plate around its text in px, the BillboardGui's own size: the frame's left and right padding
-- (Theme.Padding.medium) and stroke, a little slack, at least MIN_PLATE_HEIGHT tall (the built 30 px).
local PLATE_PADDING_X = 12
local PLATE_PADDING_Y = 4
local PLATE_STROKE_PX = Theme.Stroke.bar
local PLATE_SLACK_PX = 2
local MIN_PLATE_HEIGHT = 30
-- Foam UI: the chip's bevel and drop bands (Theme.Foam.chip) along the plate's bottom; the text sits above them.
local PLATE_BANDS = Theme.Foam.chip
local PLATE_BANDS_PX = PLATE_BANDS.bevel + PLATE_BANDS.drop
local TEXT_KIND: Theme.TextKind = "Chip"
local ESTIMATE_EM = 0.6 -- the text width estimate (per character, × the size) until TextBounds is known
local FADE_STEP = 0.01 -- a fade change smaller than this is not written
local STUDS_OFFSET_HEAD = Vector3.new(0, NAMEPLATE.headOffsetStuds, 0)
local STUDS_OFFSET_ROOT = Vector3.new(0, NAMEPLATE.headOffsetStuds + ROOT_TO_HEAD_STUDS, 0)
local POP: Tweens.Spec = {
	ms = NAMEPLATE.popSeconds * 1000,
	style = Enum.EasingStyle.Back,
	direction = Enum.EasingDirection.Out,
}
local POP_FROM = NAMEPLATE.popScale
local RANK_COLORS: { [string]: Color3 } = {
	soft = Palette.Cream,
	firm = Palette.MintCream,
	strong = Palette.Sky,
	iron = Palette.Lavender,
	titan = Palette.Bubblegum,
	master = Palette.Lemon,
	-- Spec 2026-10-12 §10's ranks above Lv 50 (Phase 5): their own light faces.
	legend = Palette.RankLegend,
	mythic = Palette.RankMythic,
	cosmic = Palette.RankCosmic,
	galaxy = Palette.RankGalaxy,
	infinite = Palette.RankInfinite,
}

-- Module table

local NameplateController = {}

-- Part 8: the plate's padding around its label (each side) and its smallest height, in px (tests read them); foam UI:
-- the bands under its text.
NameplateController.PLATE =
	table.freeze({ paddingX = PLATE_PADDING_X, minHeight = MIN_PLATE_HEIGHT, bandsPx = PLATE_BANDS_PX })

-- Private

local log = Log.new("Nameplate")
local cleanup: Cleanup.Cleanup? = nil
local plates: { [Player]: Plate } = {}
local warnedKeys: { [string]: boolean } = {}

local function text(key: string, args: { [string]: any }?): string
	local template = Strings.resolve(key)
	if template == nil then
		if not warnedKeys[key] then
			warnedKeys[key] = true
			log:warn(`no Strings text for {key}`)
		end
		return ""
	end
	return Strings.format(template, args)
end

local function phaseOf(player: Player?): string
	local phase = if player then player:GetAttribute(ATTR_DUEL_PHASE) else nil
	return if type(phase) == "string" then phase else ""
end

local function levelOf(player: Player): number?
	local value = player:GetAttribute(ATTR_LEVEL)
	if type(value) == "number" and value == value and value >= 1 and value < math.huge then
		return math.floor(value)
	end
	return nil
end

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Part 8: the BillboardGui follows its text (plateSize): TextBounds once measured, else an estimate.
local function resize(plate: Plate)
	local gui, label = plate.gui, plate.label
	if gui == nil or label == nil then
		return
	end
	local bounds = label.TextBounds
	if not (bounds.X > 0 and bounds.Y > 0) then
		local size = label.TextSize
		bounds = Vector2.new(utf8.len(label.Text) or #label.Text, 1) * Vector2.new(size * ESTIMATE_EM, size)
	end
	local px = NameplateController.plateSize(bounds)
	local wanted = UDim2.fromOffset(px.X, px.Y)
	if gui.Size ~= wanted then
		gui.Size = wanted
	end
end

local function applyEnabled(plate: Plate)
	local gui = plate.gui
	if gui then
		gui.Enabled = plate.baseVisible and not plate.ownHidden
	end
end

-- Part 8: the distance fade (transparency only, so it runs under ReducedMotion too).
local function applyFade(plate: Plate, transparency: number)
	local frame, label, stroke = plate.frame, plate.label, plate.stroke
	-- Tiny steps are skipped, but the ends (solid and clear) are always reached exactly.
	local tiny = math.abs(transparency - plate.fade) < FADE_STEP and transparency > 0 and transparency < 1
	if frame == nil or label == nil or transparency == plate.fade or tiny then
		return
	end
	plate.fade = transparency
	frame.BackgroundTransparency = transparency
	label.TextTransparency = transparency
	if stroke then
		stroke.Transparency = transparency
	end
end

local function refresh(plate: Plate)
	local gui, frame, label = plate.gui, plate.frame, plate.label
	if gui == nil or frame == nil or label == nil then
		return
	end
	local level = levelOf(plate.player)
	local visible =
		NameplateController.visible(NAMEPLATE.enabled, phaseOf(Players.LocalPlayer), phaseOf(plate.player), level)
	plate.baseVisible = visible
	applyEnabled(plate)
	if level == nil then
		plate.shownLevel = nil
		return
	end
	local line = NameplateController.text(level)
	if label.Text ~= line then
		label.Text = line
		resize(plate)
	end
	frame.BackgroundColor3 = NameplateController.rankColor(level)
	local previous = plate.shownLevel
	plate.shownLevel = level
	local uiScale = plate.scale
	if previous ~= nil and previous ~= level and visible and uiScale then
		Tweens.scale(uiScale, POP_FROM, 1, POP)
	end
end

local function buildGui(plate: Plate, adornee: BasePart, isHead: boolean, c: Trove)
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return
	end
	-- Part 8: the BillboardGui is sized to its text (resize, plateSize) and the plate fills it.
	local gui: BillboardGui = Create("BillboardGui", {
		Name = GUI_PREFIX .. plate.player.UserId,
		Adornee = adornee,
		Size = UDim2.fromOffset(MIN_PLATE_HEIGHT, MIN_PLATE_HEIGHT),
		StudsOffset = if isHead then STUDS_OFFSET_HEAD else STUDS_OFFSET_ROOT,
		MaxDistance = NAMEPLATE.maxDistance,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		ClipsDescendants = false,
		Active = false,
		Enabled = false,
	})
	local frame: Frame = Create("Frame", {
		Name = "Plate",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Palette.Cream,
		BorderSizePixel = 0,
		Parent = gui,
	})
	-- "tint": refresh() sets the rank colour as BackgroundColor3 and the bands darken it (Theme.panel's colours).
	local foam = Theme.foam(frame, {
		radius = Theme.Radius.pill,
		stroke = PLATE_STROKE_PX,
		mode = "tint",
		bevel = PLATE_BANDS.bevel,
		drop = PLATE_BANDS.drop,
		-- Candy UI (2026-10-11): world plates keep the light sticker bands.
		colors = { face = Theme.Colors.frosting, bevel = Theme.Colors.stickerBevel, drop = Theme.Colors.inkUI },
	})
	local stroke = foam.stroke
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, PLATE_PADDING_X),
		PaddingRight = UDim.new(0, PLATE_PADDING_X),
		PaddingBottom = UDim.new(0, PLATE_BANDS_PX),
		Parent = frame,
	})
	local uiScale: UIScale = Create("UIScale", { Name = "Pop", Parent = frame })
	local label = Theme.label({
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		AutomaticSize = Enum.AutomaticSize.None,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = frame,
	}, TEXT_KIND, nil, Theme.Colors.inkUI) -- dark text on the light rank plate (the screen UI's default is light)
	gui.Parent = playerGui
	c:add(gui)
	plate.gui, plate.frame, plate.label, plate.stroke, plate.scale = gui, frame, label, stroke, uiScale
	plate.isHead, plate.fade, plate.ownHidden = isHead, 0, false
	c:add(label:GetPropertyChangedSignal("TextBounds"):Connect(function()
		resize(plate)
	end))
	c:add(function()
		if plate.gui == gui then
			plate.gui, plate.frame, plate.label, plate.stroke, plate.scale = nil, nil, nil, nil, nil
			plate.shownLevel = nil
		end
	end)
	refresh(plate)
	resize(plate)
end

local function attach(plate: Plate, character: Model?)
	if character ~= nil and character == plate.character and plate.characterCleanup ~= nil then
		return -- already attached (CharacterAdded and the Character property both report it)
	end
	local old = plate.characterCleanup
	plate.character = character
	if old then
		plate.characterCleanup = nil
		old:clean()
	end
	if character == nil then
		return
	end
	local c: Trove = Cleanup.new() :: any
	plate.characterCleanup = c
	c:add(character.Destroying:Connect(function()
		if plate.characterCleanup == c then
			plate.characterCleanup = nil
			plate.character = nil
			c:clean()
		end
	end))
	c:add(task.spawn(function()
		local head = character:WaitForChild(HEAD, HEAD_WAIT_SECONDS)
		if plate.characterCleanup ~= c then
			return
		end
		if head and head:IsA("BasePart") then
			buildGui(plate, head, true, c)
			return
		end
		local root = character:FindFirstChild(ROOT_PART)
		if root and root:IsA("BasePart") then
			buildGui(plate, root, false, c)
		end
	end))
end

local function track(player: Player)
	if plates[player] ~= nil then
		return
	end
	local c: Trove = Cleanup.new() :: any
	local plate: Plate = {
		player = player,
		character = nil,
		gui = nil,
		frame = nil,
		label = nil,
		stroke = nil,
		scale = nil,
		shownLevel = nil,
		isHead = true,
		baseVisible = false,
		ownHidden = false,
		fade = 0,
		cleanup = c,
		characterCleanup = nil,
	}
	plates[player] = plate
	c:add(player.CharacterAdded:Connect(function(character: Model)
		attach(plate, character)
	end))
	c:add(player.CharacterRemoving:Connect(function()
		attach(plate, nil)
	end))
	-- reading: with streaming, another player's character can leave and come back without CharacterAdded; the
	-- Character property still changes, so the plate follows it too.
	c:add(player:GetPropertyChangedSignal("Character"):Connect(function()
		attach(plate, player.Character)
	end))
	c:add(player:GetAttributeChangedSignal(ATTR_LEVEL):Connect(function()
		refresh(plate)
	end))
	c:add(player:GetAttributeChangedSignal(ATTR_DUEL_PHASE):Connect(function()
		refresh(plate)
	end))
	c:add(function()
		attach(plate, nil)
	end)
	attach(plate, player.Character)
end

local function untrack(player: Player)
	local plate = plates[player]
	if plate then
		plates[player] = nil
		plate.cleanup:clean()
	end
end

local function refreshAll()
	for _, plate in plates do
		refresh(plate)
	end
end

-- Part 8: one pass of the camera checks (every Nameplate.checkSeconds): the distance fade on every plate and the own
-- plate's first-person hiding.
local function checkCamera()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local localPlayer = Players.LocalPlayer
	local compact = UIController.layoutClass() == "compact"
	for _, plate in plates do
		local gui = plate.gui
		local adornee = if gui then gui.Adornee else nil
		if gui and adornee and adornee:IsA("BasePart") then
			local base = (adornee :: BasePart).Position
			local head = if plate.isHead then base else base + Vector3.new(0, ROOT_TO_HEAD_STUDS, 0)
			local plateAt = base + Vector3.new(0, gui.StudsOffset.Y, 0)
			applyFade(
				plate,
				NameplateController.fadeTransparency(
					(plateAt - eye).Magnitude,
					NAMEPLATE.maxDistance,
					NAMEPLATE.fadeStuds
				)
			)
			local hidden = plate.player == localPlayer
				and NameplateController.ownHidden((head - eye).Magnitude, NAMEPLATE.ownHideStuds, compact)
			if hidden ~= plate.ownHidden then
				plate.ownHidden = hidden
				applyEnabled(plate)
			end
		end
	end
end

-- Part 8: the plates' text size follows the player's GuiService.PreferredTextSize (resize follows TextBounds).
local function refreshTextSize()
	local size = Theme.textSize(TEXT_KIND)
	for _, plate in plates do
		local label = plate.label
		if label and label.TextSize ~= size then
			label.TextSize = size
		end
	end
end

-- Public: pure helpers (unit-tested) --------------------------------------------------------------------------------

-- Whether a nameplate shows (§17.7): nameplates on, the target has a level, and neither the viewer nor the target is
-- in a match (SD_DuelPhase ~= ""). The 60-stud distance is BillboardGui.MaxDistance.
function NameplateController.visible(
	enabled: boolean,
	viewerPhase: string,
	targetPhase: string,
	level: number?
): boolean
	return enabled and level ~= nil and viewerPhase == "" and targetPhase == ""
end

-- The plate text: grip.nameplate "Lv {level} · {rank}".
function NameplateController.text(level: number): string
	local rank = GripMath.rankFor(level)
	return text("grip.nameplate", { level = level, rank = text("grip.rank." .. rank.key) })
end

-- The plate colour of a level's rank (always shown with the rank's name, never alone).
function NameplateController.rankColor(level: number): Color3
	local rank = GripMath.rankFor(level)
	return RANK_COLORS[rank.key] or Palette.Cream
end

-- Part 8: the plate's transparency at a camera distance (studs): solid up to maxDistance - fadeStuds, then a linear
-- fade to clear at maxDistance (BillboardGui.MaxDistance hides it beyond). No fade with fadeStuds <= 0; a NaN
-- distance counts as near (solid).
function NameplateController.fadeTransparency(distance: number, maxDistance: number, fadeStuds: number): number
	if distance ~= distance then
		return 0
	end
	if distance >= maxDistance then
		return 1
	end
	if not finite(fadeStuds) or fadeStuds <= 0 then
		return 0
	end
	local start = maxDistance - fadeStuds
	if distance <= start then
		return 0
	end
	return math.clamp((distance - start) / fadeStuds, 0, 1)
end

-- Part 8: whether the local player's own plate hides: the camera is within `thresholdStuds` of the Head (first
-- person). Non-finite input never hides it. Foam fix 2: it also hides on the compact layout (`compact`, phones), where
-- the HUD's tile row sits at the plate's height and the compact Grip card beside the coin capsule reads the same line.
function NameplateController.ownHidden(cameraToHeadStuds: number, thresholdStuds: number, compact: boolean?): boolean
	if compact == true then
		return true
	end
	return finite(cameraToHeadStuds) and finite(thresholdStuds) and cameraToHeadStuds <= thresholdStuds
end

-- Part 8: the BillboardGui's size in px around a text of `textBounds` px (TextLabel.TextBounds): the text plus the
-- plate's padding and stroke on both sides and a little slack; at least the built 30 px tall. Foam UI: plus the bands
-- under the text.
function NameplateController.plateSize(textBounds: Vector2): Vector2
	local x = if finite(textBounds.X) and textBounds.X > 0 then textBounds.X else 0
	local y = if finite(textBounds.Y) and textBounds.Y > 0 then textBounds.Y else 0
	return Vector2.new(
		math.ceil(x) + 2 * (PLATE_PADDING_X + PLATE_STROKE_PX) + PLATE_SLACK_PX,
		math.max(MIN_PLATE_HEIGHT, math.ceil(y) + 2 * (PLATE_PADDING_Y + PLATE_STROKE_PX) + PLATE_BANDS_PX)
	)
end

-- Small table for Studio debug hooks.
function NameplateController.debugState(): { [string]: any }
	local shown, total = 0, 0
	local own: { [string]: any }? = nil
	for player, plate in plates do
		local gui = plate.gui
		if gui then
			total += 1
			if gui.Enabled then
				shown += 1
			end
			if player == Players.LocalPlayer then
				own = {
					enabled = gui.Enabled,
					ownHidden = plate.ownHidden,
					fade = plate.fade,
					sizePx = { gui.Size.X.Offset, gui.Size.Y.Offset },
					text = if plate.label then plate.label.Text else nil,
				}
			end
		end
	end
	return { enabled = NAMEPLATE.enabled, plates = total, shown = shown, own = own }
end

-- Lifecycle

function NameplateController.init()
	if not NAMEPLATE.enabled then
		return
	end
	cleanup = Cleanup.new()
end

function NameplateController.start()
	local c = cleanup
	if c == nil then
		return
	end
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		localPlayer:WaitForChild("PlayerGui")
		c:add(localPlayer:GetAttributeChangedSignal(ATTR_DUEL_PHASE):Connect(refreshAll))
	end
	if cleanup ~= c then
		return -- destroyed while waiting
	end
	c:add(Players.PlayerAdded:Connect(track))
	c:add(Players.PlayerRemoving:Connect(untrack))
	c:add(function()
		for player in table.clone(plates) do
			untrack(player)
		end
	end)
	for _, player in Players:GetPlayers() do
		track(player)
	end
	-- Part 8: the text size follows PreferredTextSize; the camera checks run from one loop, never per frame.
	local textOk, textSignal = pcall(function(): RBXScriptSignal
		return GuiService:GetPropertyChangedSignal("PreferredTextSize")
	end)
	if textOk then
		c:add(textSignal:Connect(refreshTextSize))
	end
	c:add(task.spawn(function()
		local reported = false
		while true do
			task.wait(NAMEPLATE.checkSeconds)
			local ok, err = pcall(function(): any
				checkCamera()
				return nil
			end)
			if not ok and not reported then
				reported = true -- once: the loop runs 4 times a second
				log:error("nameplate camera check failed:", err)
			end
		end
	end))
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function NameplateController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return NameplateController
