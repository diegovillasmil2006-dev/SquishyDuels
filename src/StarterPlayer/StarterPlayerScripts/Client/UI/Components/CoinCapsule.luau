--!strict
-- CoinCapsule (client only). Foam UI restyle (spec 2026-10-09, "Coin capsule: the shape-built coin disc overlapping a
-- cream capsule; count-up, flights and bounce unchanged"); DESIGN §11.6 (the Coins pill), §7.2 (Coin colours only for
-- Coins, always with the coin icon).
--   local coins = CoinCapsule.new({ name = "Hud_CoinsButton", text = HudFormat.coinsText(nil), parent = holder })
--   coins:setText(Format.coins(n))   -- or write coins.label.Text from a count-up
--   local feel = Button.decorate(coins.root, { sound = false })     -- the press feel and the gain bounce (the caller)
-- root is a transparent TextButton (the tap target, named spec.name, focus ring with pill corners): the CoinIcon disc
-- (discPx, ZIndex 2, `disc.root` for the icon wiggle) at its left edge, over the left end of a Frosting foam capsule
-- (heightPx tall, bevel 5, drop 4) that starts under the disc's centre and grows with the number (HudNumber kind, the
-- display font). The root is discPx tall (the touch target: at least Config.UI.Touch.minTarget).
-- Candy UI (UI overhaul 2026-10-11): the capsule is a dark window pill (Theme.panelColors, the inner rim) and the number
-- a Coin-gold gradient (GOLD_TOP -> GOLD_BOTTOM over the white text) with the PlumInk outline of the HudNumber kind,
-- the bold currency read of the references; the coin disc keeps the game's coin tokens.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)

local UI = script.Parent.Parent
local CoinIcon = require(script.Parent.CoinIcon)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Theme = require(UI.Theme)

-- Types

export type Spec = {
	name: string,
	text: string,
	discPx: number?, -- the coin disc (base px); default 52, at least the touch minimum
	heightPx: number?, -- the capsule (base px); default 44
	textKind: Theme.TextKind?, -- default "HudNumber"
	layoutOrder: number?,
	parent: Instance?,
}

export type CoinCapsule = {
	root: TextButton,
	capsule: Frame,
	disc: CoinIcon.CoinIcon,
	label: TextLabel,
	setText: (self: CoinCapsule, text: string) -> (),
	destroy: (self: CoinCapsule) -> (),
}

-- Constants

local DEFAULT_DISC_PX = 52
local DEFAULT_HEIGHT_PX = 44
local TEXT_GAP_PX = 8 -- between the disc's right edge and the number
local PADDING_RIGHT_PX = 18
-- Candy UI: the number's gold gradient (Coins only, §7.2: the coin colours stay with the coin).
local GOLD_TOP = Color3.fromHex("#FFF4B8")
local GOLD_BOTTOM = Color3.fromHex("#FFC63A")

-- Module table

local CoinCapsule = {}

-- Public

function CoinCapsule.new(spec: Spec): CoinCapsule
	local cleanup = Cleanup.new()
	local disc = math.max(spec.discPx or DEFAULT_DISC_PX, Config.UI.Touch.minTarget)
	local height = math.min(spec.heightPx or DEFAULT_HEIGHT_PX, disc)
	local bands = Theme.Foam.panel
	local top = Theme.Foam.button.top
	local root: TextButton = Create("TextButton", {
		Name = spec.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(0, disc),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Focus.decorate(root, Theme.Radius.pill)

	local capsule: Frame = Create("Frame", {
		Name = "Capsule",
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, disc / 2, 0.5, 0),
		Size = UDim2.fromOffset(0, height),
		-- Taller than heightPx only when the player's text size needs it (centred on the disc).
		AutomaticSize = Enum.AutomaticSize.XY,
		Active = false,
		Parent = root,
	})
	Theme.foam(capsule, {
		radius = Theme.Radius.pill,
		top = top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.panelColors(),
	})
	Theme.rim(capsule)
	Create("UIPadding", {
		PaddingLeft = UDim.new(0, disc / 2 + TEXT_GAP_PX),
		PaddingRight = UDim.new(0, PADDING_RIGHT_PX),
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bands.bevel + bands.drop),
		Parent = capsule,
	})
	Theme.list(Enum.FillDirection.Horizontal, 0, capsule, Enum.HorizontalAlignment.Left)
	local label = Theme.label({
		Name = "Amount",
		Text = spec.text,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		Parent = capsule,
	}, spec.textKind or "HudNumber")
	Create("UIGradient", {
		Name = "SD_GoldText",
		Rotation = 90,
		Color = ColorSequence.new(GOLD_TOP, GOLD_BOTTOM),
		Parent = label,
	})

	local icon = CoinIcon.new({ name = "CoinIcon", sizePx = disc, parent = root })
	cleanup:add(icon)
	icon.root.AnchorPoint = Vector2.new(0, 0.5)
	icon.root.Position = UDim2.fromScale(0, 0.5)
	icon.root.ZIndex = 2

	local self = {} :: CoinCapsule
	self.root = root
	self.capsule = capsule
	self.disc = icon
	self.label = label

	function self.setText(_: CoinCapsule, text: string)
		label.Text = text
	end

	function self.destroy(_: CoinCapsule)
		cleanup:clean()
	end

	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return CoinCapsule
