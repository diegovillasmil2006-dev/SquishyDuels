--!strict
-- PhoneHud (client only). Phone HUD B (the owner's pick, 2026-10-17; plan work/phonehud/PROPOSAL.md Part 2 §3): the
-- phone-only parts of the lobby HUD. Phones are the compact layout class (UIController.layoutClass, as every phone rule
-- of the HUD); PCs, consoles and tablets keep Diego's layout. HudController builds and places them:
-- * The mode chip (Hud_ModeChip) under the DUEL button: the DUEL picker's own tabs (UI/Components/SegmentedTabs, their
--   short names) with the swap mark, only the picked one showing. A tap on it opens the 3-tab picker (Hud_DuelModes)
--   under it; a press on one of its tabs, another tap on the chip, a tap anywhere else (Hud_ModeCatcher: a clear button
--   over the whole HUD, under its groups) or a window opening (HudController) closes it. Neither shows while the 1v1
--   search bar does; the DUEL button never moves for it (HudController.layoutCta).
-- * The tiles of HudFormat.PHONE_RIGHT (Daily) sit in Hud_Right before Settings, which turns into a row (the quest
--   tracker hides on phones); on other layouts they go back to the tile grid at their NAV place.
--   PhoneHud.buildChip(c, spec)        once, with the picker (HudFormat.pickerShown)
--   PhoneHud.sync(idle, compact)       the picker parts' visibility: `idle` = the picker would show (a picker, the DUEL
--                                      area not searching); on phones the chip shows and the picker only while open
--                                      (it closes when `idle` or `compact` ends)
--   PhoneHud.setMode(id) / toggle() / close() / isOpen()
--   PhoneHud.chipSize() / chipButton() the chip as it shows: its size (base px) and its button (Vector2.zero / nil
--                                      while hidden)
--   PhoneHud.placeTiles(compact, tiles, labels, nav, right)
--   PhoneHud.debugState()

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)

local UI = script.Parent
local Button = require(UI.Components.Button)
local Create = require(UI.Create)
local HudFormat = require(UI.HudFormat)
local SegmentedTabs = require(UI.Components.SegmentedTabs)

-- Types

export type ChipSpec = {
	tabs: { SegmentedTabs.Tab }, -- the picker's tabs (their looks and short names)
	selected: string,
	wrap: Frame, -- the DUEL area (Hud_CtaWrap): the chip sits in its list
	layoutOrder: number, -- between the DUEL button and the picker
	picker: SegmentedTabs.SegmentedTabs,
	hud: ScreenGui, -- SD_Hud: the catcher covers it
	onChange: () -> (), -- the chip or the picker showed, hid or changed (HudController lays out again)
}

-- Constants

local COLUMN = HudFormat.COLUMN
local CLICK_SOUND = "ui.click"
local TAB_PITCH = Config.Audio.uiPitch.tab -- the picker's tab() sound (N:1254)

-- Module table

local PhoneHud = {}

-- Private

local chip: SegmentedTabs.SegmentedTabs? = nil
local picker: SegmentedTabs.SegmentedTabs? = nil
local catcher: TextButton? = nil
local onChange: (() -> ())? = nil
local open, idle, compact = false, false, false
local current = ""

local function apply()
	local phone = idle and compact
	open = open and phone
	local tabs = chip
	if tabs then
		tabs.root.Visible = phone
		for id, tab in tabs.tabs do
			tab.Visible = id == current
		end
	end
	local modes = picker
	if modes then
		modes.root.Visible = idle and (not compact or open)
	end
	local button = catcher
	if button then
		button.Visible = open
	end
end

local function changed()
	apply()
	local callback = onChange
	if callback then
		callback()
	end
end

-- Public

function PhoneHud.buildChip(c: Cleanup.Cleanup, spec: ChipSpec)
	local tabs = SegmentedTabs.new({
		name = "Hud_ModeChip",
		tabs = spec.tabs,
		selected = spec.selected,
		mark = "change", -- IconGlyph's two arrows
		layoutOrder = spec.layoutOrder,
		onSelect = function() end, -- only the picked tab shows: its press toggles the picker (below)
		parent = spec.wrap,
	})
	c:add(tabs)
	tabs:setShort(true)
	for _, tab in tabs.tabs do
		c:add(tab.Activated:Connect(function()
			Button.playSound(CLICK_SOUND, TAB_PITCH)
			PhoneHud.toggle()
		end))
	end
	-- A press on any of the picker's tabs closes it, the picked one too (a new pick also comes through setMode).
	for _, tab in spec.picker.tabs do
		c:add(tab.Activated:Connect(PhoneHud.close))
	end
	local button: TextButton = Create("TextButton", {
		Name = "Hud_ModeCatcher",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Selectable = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0, -- under the HUD's groups: a tap on a sticker still opens it
		Visible = false,
		Parent = spec.hud,
	})
	c:add(button)
	c:add(button.Activated:Connect(PhoneHud.close))
	chip, picker, catcher, onChange, current = tabs, spec.picker, button, spec.onChange, spec.selected
	c:add(function()
		chip, picker, catcher, onChange = nil, nil, nil, nil
		open, idle, compact, current = false, false, false, ""
	end)
	apply()
end

function PhoneHud.sync(isIdle: boolean, isCompact: boolean)
	idle, compact = isIdle, isCompact
	apply()
end

-- The picked mode (the picker's onSelect): the chip shows it and the picker closes.
function PhoneHud.setMode(id: string)
	current = id
	local tabs = chip
	if tabs then
		tabs:select(id)
	end
	open = false
	changed()
end

function PhoneHud.toggle()
	if not (idle and compact) then
		return
	end
	open = not open
	changed()
end

function PhoneHud.close()
	if open then
		open = false
		changed()
	end
end

function PhoneHud.isOpen(): boolean
	return open
end

-- The chip as it shows (the well round the picked tab, base px), Vector2.zero while hidden.
function PhoneHud.chipSize(): Vector2
	local tabs = chip
	return if tabs and tabs.root.Visible then tabs:size() else Vector2.zero
end

-- The chip's button (the picked tab) while it shows, else nil (the gamepad links).
function PhoneHud.chipButton(): GuiObject?
	local tabs = chip
	return if tabs and tabs.root.Visible then tabs.tabs[current] else nil
end

-- The PHONE_RIGHT tiles: on phones in Hud_Right before Settings, a phone tile (the minimal phone HUD, 2026-10-17: an
-- icon-only square, HudController.layoutTiles hides the label); else back in the tile grid at their NAV place.
-- Hud_Right is a row on phones, else Diego's column.
function PhoneHud.placeTiles(
	isCompact: boolean,
	tiles: { [string]: Button.Button },
	_labels: { [string]: string },
	nav: Frame,
	right: Frame
)
	local side = COLUMN.tileSizeCompact
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

function PhoneHud.debugState(): { [string]: any }
	local tabs = chip
	return { chip = tabs ~= nil and tabs.root.Visible, open = open, mode = current }
end

return PhoneHud
