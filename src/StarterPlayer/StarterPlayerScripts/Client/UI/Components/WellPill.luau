--!strict
-- WellPill (client only). UI FINAL R8 (plan work/ui/PLAN.md R8; `H:n` = "Squishy Duels HUD.dc.html" line n): the
-- design's pill of a picture and a text: the quests' reset pill (H:359), a quest's reward (H:369), the daily streak
-- (H:390) and timer (H:391). `look` (Config.UI.Daily.timer and the like): `height` high with its `border` px ink
-- border drawn inside (CSS border-box), full radius, padding 0 padRight 0 padLeft inside the border, the picture
-- iconPx square (raised iconRaise px, H:390's margin-top -4) and the text in the Config.UI.Sticker text role
-- textRole, `gap` apart. The face is the well #5B36D9 (StickerWell), or spec.colors' two stops with their inset
-- highlight (the streak). The width follows the text, measured (Theme.textWidth): no AutomaticSize, which mis-sizes
-- under a scaled ScreenGui; setText measures again. The caller places root.
--   local pill = WellPill.new({ name = "Reward", look = Config.UI.Quests.reward, icon = "img.coin", parent = row })
--   pill:setText("120");   pill.icon (the picture's holder, for an idle loop);   pill:destroy()
-- WellPill.width(look, text, hasIcon) is root's width for that text (base px), pure but for the text measure.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local IconGlyph = require(script.Parent.IconGlyph)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)

-- Types

export type Look = {
	height: number,
	padLeft: number,
	padRight: number,
	gap: number,
	border: number,
	iconPx: number,
	textRole: string,
	-- iconRaise: number? (read loosely: the Config tables are sealed)
}

export type Spec = {
	name: string,
	look: Look,
	icon: string?, -- an AssetTable image key (IconGlyph.image); nil = no picture
	colors: { top: Color3, bottom: Color3, inset: { px: number, alpha: number } }?, -- default the well
	layoutOrder: number?,
	parent: Instance?,
}

export type WellPill = {
	root: Frame,
	label: TextLabel,
	icon: Frame?,
	setText: (self: WellPill, text: string) -> (),
	destroy: (self: WellPill) -> (),
}

-- Constants

local MEASURE_MARGIN_PX = 2 -- reading: TextService rounding
local WHITE = Color3.new(1, 1, 1)

-- Module table

local WellPill = {}

-- Private

local function kindOf(look: Look): Theme.TextKind
	local role = Config.UI.Sticker.text[look.textRole]
	return (if role then role.kind else "Small") :: Theme.TextKind
end

-- Public

function WellPill.width(look: Look, text: string, hasIcon: boolean): number
	local textWidth = math.ceil(Theme.textWidth(text, kindOf(look))) + MEASURE_MARGIN_PX
	local icon = if hasIcon then look.iconPx + look.gap else 0
	return 2 * look.border + look.padLeft + icon + textWidth + look.padRight
end

function WellPill.new(spec: Spec): WellPill
	local cleanup = Cleanup.new()
	local look = spec.look
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(look.height, look.height),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	local colors = spec.colors
	local bands = Layout.stickerBands(look.border, if colors then colors.inset.px else 0, 0, 0)
	local face: Theme.FoamColors = { face = Palette.StickerWell }
	if colors then
		face = { face = colors.top, faceEnd = colors.bottom, top = colors.top:Lerp(WHITE, colors.inset.alpha) }
	end
	Theme.foam(root, {
		radius = look.height,
		stroke = look.border,
		inner = true,
		top = bands.top,
		colors = face,
	})
	local x = look.border + look.padLeft
	local icon: Frame? = nil
	if spec.icon then
		local slot: Frame = Create("Frame", {
			Name = "IconSlot",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, x, 0.5, -((look :: any).iconRaise or 0)),
			Size = UDim2.fromOffset(look.iconPx, look.iconPx),
			Parent = root,
		})
		local image = IconGlyph.image(spec.icon, { name = "Icon", sizePx = look.iconPx, parent = slot })
		image.AnchorPoint = Vector2.new(0.5, 0.5) -- an idle loop scales it about its centre
		image.Position = UDim2.fromScale(0.5, 0.5)
		icon = image
		x += look.iconPx + look.gap
	end
	local kind: Theme.TextKind = kindOf(look)
	local label = Theme.label({
		Name = "Text",
		Text = "",
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, x, 0.5, 0),
		Size = UDim2.fromOffset(0, math.ceil(Theme.lineHeight(kind))),
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = root,
	}, kind)
	Theme.stickerText(label, look.textRole)
	label.TextWrapped = false

	local self = {} :: WellPill
	self.root = root
	self.label = label
	self.icon = icon

	function self.setText(_: WellPill, text: string)
		label.Text = text
		local textWidth = math.ceil(Theme.textWidth(text, kind)) + MEASURE_MARGIN_PX
		label.Size = UDim2.fromOffset(textWidth, math.ceil(Theme.lineHeight(kind)))
		root.Size = UDim2.fromOffset(WellPill.width(look, text, icon ~= nil), look.height)
	end

	function self.destroy(_: WellPill)
		cleanup:clean()
	end

	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return WellPill
