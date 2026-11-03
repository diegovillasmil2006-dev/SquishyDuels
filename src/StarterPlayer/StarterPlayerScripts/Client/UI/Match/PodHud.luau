--!strict
-- PodHud (client only). Squish Pods HUD (2026-11-03; `H:n` = "Squishy Duels In-Game HUD.dc.html" line n), a
-- MatchHudController piece ("pod"): the "You grabbed X" toast (H:190-191) at the right (Config.UI.Pod.toast; under the
-- kill feed while its rows reach down there, ctx.shared.feedBottom), from each landing for 3 s (H:22 hg-toast) while
-- the power-up is shown (an instant one shows it only while it lands, as H:190), and the screen edge of Shield, Speed
-- and Super Jump (H:188-189: img.pod.edge tinted, pulsing as H:23) while it lasts. It reads the view's you.rolling and
-- you.buffs through UI/PodFormat, as the dial does (AbilityBarController).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local MatchHudFormat = require(UI.MatchHudFormat)
local PodFormat = require(UI.PodFormat)
local Theme = require(UI.Theme)

-- Constants

local POD = Config.UI.Pod
local T = POD.toast
local POWER_UPS = Config.Match.PowerUps
local TEXT = Strings.match.pod
local INK = Palette.PodInk
local WHITE = Palette.White
local Z_EDGE = 1 -- under every other piece
local Z_TOAST = 40
local function easeOut(x: number): number -- CSS ease-out, close enough at toast speed: 1 - (1 - x)^2
	return 1 - (1 - x) * (1 - x)
end

-- Module table

local PodHud = {}

-- Private

local function textWidth(text: string, px: number): number
	return Theme.textWidth(text, "Chip") * px / Theme.textSize("Chip")
end

local function text(name: string, weight: Enum.FontWeight, color: Color3, z: number, parent: Instance): TextLabel
	return Create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = Theme.font("Button", weight),
		TextSize = T.textPx,
		TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = z,
		Parent = parent,
	})
end

-- Public

function PodHud.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local edge: ImageLabel = Create("ImageLabel", {
		Name = "PodEdge",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = AssetTable.image("img.pod.edge") or "",
		ScaleType = Enum.ScaleType.Stretch,
		Visible = false,
		ZIndex = Z_EDGE,
		Parent = ctx.root,
	})

	local faceH = T.heightPx - 2 * T.border
	local toast: CanvasGroup = Create("CanvasGroup", {
		Name = "PodToast",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = Z_TOAST,
		Parent = ctx.root,
	})
	local drop: Frame = Create("Frame", { -- H:190 box-shadow 0 3px 0 ink
		Name = "Drop",
		Position = UDim2.fromOffset(T.border, T.border + T.drop),
		BackgroundColor3 = INK,
		ZIndex = Z_TOAST,
		Parent = toast,
	})
	Theme.corner(T.radius, drop)
	Theme.stroke(INK, T.border, drop)
	local face: Frame = Create("Frame", {
		Name = "Face",
		Position = UDim2.fromOffset(T.border, T.border),
		BackgroundColor3 = Palette.PodToast,
		ZIndex = Z_TOAST + 1,
		Parent = toast,
	})
	Theme.corner(T.radius, face)
	local faceStroke = Theme.stroke(WHITE, T.border, face)
	local iconPx = T.iconPx - 2 * T.iconBorder -- H:191 iconTile(res, {round 8px}): a 4 px ink border in its 28 px
	local icon: Frame = Create("Frame", {
		Name = "Icon",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, T.padLeft - T.border + T.iconBorder, 0.5, 0),
		Size = UDim2.fromOffset(iconPx, iconPx),
		BackgroundColor3 = WHITE,
		ZIndex = Z_TOAST + 2,
		Parent = face,
	})
	Theme.corner(T.iconRadius, icon)
	Theme.stroke(INK, T.iconBorder, icon)
	local iconGradient: UIGradient = Create("UIGradient", { Rotation = POD.tileRotation, Parent = icon })
	local glyphPx = T.iconPx * POD.iconShare * POD.glyphBox
	local glyph: ImageLabel = Create("ImageLabel", {
		Name = "Glyph",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(glyphPx, glyphPx),
		BackgroundTransparency = 1,
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = Z_TOAST + 3,
		Parent = icon,
	})
	local grabbed = text("Grabbed", Enum.FontWeight.SemiBold, WHITE, Z_TOAST + 2, face)
	grabbed.Text = TEXT.grabbed
	local name = text("Name", Enum.FontWeight.Bold, WHITE, Z_TOAST + 2, face)

	local memory: PodFormat.Memory = {}
	local builtFor: string? = nil

	local function build(power: string)
		if builtFor == power then
			return
		end
		builtFor = power
		local look = PodFormat.look(power)
		if look == nil then
			return
		end
		faceStroke.Color = look.bottom -- H:190 the border in the power-up's colour
		iconGradient.Color = ColorSequence.new(look.top, look.bottom)
		glyph.Image = AssetTable.image(look.icon) or ""
		name.Text = TEXT.name[power] or power
		name.TextColor3 = look.color
		local x = T.padLeft - T.border + T.iconPx
		local w1 = textWidth(grabbed.Text, T.textPx)
		grabbed.Position = UDim2.fromOffset(x + T.gap, 0)
		grabbed.Size = UDim2.new(0, math.ceil(w1), 1, 0)
		local w2 = textWidth(name.Text, T.textPx)
		name.Position = UDim2.fromOffset(x + T.gap + w1 + T.gap, 0)
		name.Size = UDim2.new(0, math.ceil(w2), 1, 0)
		local width = x + 2 * T.gap + w1 + w2 + T.padRight - T.border
		face.Size = UDim2.fromOffset(math.ceil(width), faceH)
		drop.Size = face.Size
		toast.Size = UDim2.fromOffset(math.ceil(width) + 2 * T.border, faceH + 2 * T.border + T.drop)
	end

	local piece = {}

	function piece.update(_self: any, view: any, now: number)
		local you = view.you
		local live = view.matchPhase == "Active" or view.matchPhase == "Overtime"
		if type(you) ~= "table" or not live then
			edge.Visible, toast.Visible = false, false
			return
		end
		memory = PodFormat.remember(memory, you.rolling, you.alive ~= false, now)
		local state = PodFormat.state(memory, you.buffs or {}, now, POWER_UPS)
		local reduced = ctx.reduced()

		-- the edge (H:188-189)
		local color = if state.phase == "active" and state.power then PodFormat.edgeColor(state.power) else nil
		edge.Visible = color ~= nil
		if color then
			local wave = if reduced then 0.5 else (1 - math.cos(2 * math.pi * (os.clock() * 1000 % POD.edge.pulseMs) / POD.edge.pulseMs)) / 2
			edge.ImageColor3 = color
			edge.ImageTransparency = 1 - (POD.edge.low + (1 - POD.edge.low) * wave)
		end

		-- the toast (H:190, H:22)
		local power = memory.power
		local since = if memory.landsAt then now - memory.landsAt else -1
		local shownNow = power ~= nil and state.power == power and (state.phase == "landed" or state.phase == "active")
		local u = since * 1000 / T.ms
		toast.Visible = shownNow and u >= 0 and u < 1
		if toast.Visible and power then
			build(power)
			local width = toast.Size.X.Offset
			local x = if reduced then 0 else PodFormat.keyed({ { 0, 1.2 * width }, { 0.12, -6 }, { 0.18, 0 } }, u, easeOut)
			toast.GroupTransparency = 1 - PodFormat.keyed({ { 0, 1 }, { 0.85, 1 }, { 1, 0 } }, u, easeOut)
			local below = ctx.shared.feedBottom
			local top = if type(below) == "number" then math.max(T.top, below + T.belowFeedPx) else T.top
			toast.Position = UDim2.new(1, -T.right + x, 0, top)
		end
	end

	function piece.destroy(_self: any)
		edge:Destroy()
		toast:Destroy()
	end

	return piece :: any
end

return PodHud
