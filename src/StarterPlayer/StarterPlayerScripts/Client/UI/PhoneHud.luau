--!strict
-- PhoneHud (client only). Phone HUD B (the owner's pick, 2026-10-17; plan work/phonehud/PROPOSAL.md Part 2 §3): the
-- phone-only parts of the lobby HUD. Phones are the compact layout class (UIController.layoutClass, as every phone rule
-- of the HUD); PCs, consoles and tablets keep Diego's layout. HudController places them:
-- * The tiles of HudFormat.PHONE_RIGHT (Daily) sit in Hud_Right before Settings, which turns into a row (the quest
--   tracker hides on phones); on other layouts they go back to the tile grid at their NAV place.
--   PhoneHud.placeTiles(compact, tiles, labels, nav, right, scale)
-- (2026-10-24: the mode chip under the DUEL button is gone; Diego's full-screen mode select, UI/ModeSelect, picks the
-- mode on every device.)

-- Requires

local UI = script.Parent
local Button = require(UI.Components.Button)
local HudFormat = require(UI.HudFormat)
local Layout = require(UI.Layout)

-- Constants

local COLUMN = HudFormat.COLUMN

-- Module table

local PhoneHud = {}

-- Public

-- The PHONE_RIGHT tiles: on phones in Hud_Right before Settings, a phone tile (the minimal phone HUD, 2026-10-17: an
-- icon-only square, HudController.layoutTiles hides the label); else back in the tile grid at their NAV place.
-- Hud_Right is a row on phones, else Diego's column. `scale`: the HUD's UIScale (the tile stays a touch target).
function PhoneHud.placeTiles(
	isCompact: boolean,
	tiles: { [string]: Button.Button },
	_labels: { [string]: string },
	nav: Frame,
	right: Frame,
	scale: number
)
	local side = Layout.touchBase(COLUMN.tileSizeCompact, scale)
	for index, item in HudFormat.NAV do
		local tile = tiles[item.id]
		if tile and table.find(HudFormat.PHONE_RIGHT, item.id) then
			local root = tile.root
			local parent = if isCompact then right else nav
			if root.Parent ~= parent then
				root.LayoutOrder = if isCompact then 0 else index
				root.Parent = parent
			end
			if isCompact then
				local size = UDim2.fromOffset(side, side)
				if root.Size ~= size then
					root.Size = size
				end
			end
		end
	end
	local list = right:FindFirstChildOfClass("UIListLayout")
	if list then
		list.FillDirection = if isCompact then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
		list.VerticalAlignment = if isCompact then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top
	end
end

return PhoneHud
