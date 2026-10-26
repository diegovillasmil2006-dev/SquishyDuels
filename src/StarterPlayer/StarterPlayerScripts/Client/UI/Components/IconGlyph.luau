--!strict
-- IconGlyph (client only). Foam UI restyle (spec 2026-10-09, user decision 2): the UI icons. Each icon reads its
-- AssetTable image slot first (`img.nav.*`, `img.icon.*`; all nil today) and shows that image when a vetted id is
-- there (no code change); until then it draws a placeholder from UI shapes (no image ids, §11.2). Text labels always
-- stay next to an icon (§7.1 pillar 4).
--   local icon = IconGlyph.new({ name = "Icon", icon = "boxes", sizePx = 36, tone = "light", parent = tile })
--   icon:setIcon("shop");   icon:setTone("dark");   icon:destroy()
-- Names (IconGlyph.NAMES): squishies, boxes, shop, quests, daily, settings, duel (alias swords), change, clock,
-- upgrade, inspect; UI overhaul (2026-10-11): close (the windows' chunky X, alias x) and check (a claimed or owned
-- state).
-- Access2 (2026-10-18): highway (the HUD's HIGHWAY stand-in button under Settings). INCOME step 2 (2026-10-26): income
-- (the HUD's INCOME sticker: the coin picture, img.coin, until Diego draws one).
-- Tones: "light" = a white glyph with an InkUI outline and InkUI details (on an accent face, like the design's outlined
-- icons); "dark" = an InkUI glyph with Frosting details and no outline (on Frosting); "disabled" = DisabledText with
-- DisabledFace details.
-- How a placeholder is drawn: a glyph is a list of parts (rectangles and circles in the icon's 0..1 box, with a centre,
-- a size, a rotation and a corner as a share of the shorter side). Silhouette parts are drawn twice, first InkUI and
-- grown by the outline on every side (ZIndex 1), then in the fill (ZIndex 2), so the outline traces the union of the
-- shapes; detail parts (ZIndex 3) are marks on top (eyes, a ribbon, clock hands). The part lists are pure data
-- (IconGlyph.parts(name)), unit-tested in Edit mode.
-- UI FINAL R1 (plan work/ui/PLAN.md §3): IconGlyph.image(key, props) is an image-only icon (a design picture with no
-- drawn placeholder: lock, star, bolt, flame, gift, sound, squeeze, match, the boxes): the AssetTable picture, with an
-- optional drop shadow (the design's filter: drop-shadow, H:100), hidden while the id is nil (the text beside it
-- carries the meaning). Those keys are not IconGlyph.NAMES (every name has a drawn placeholder). The "disabled" tone is
-- the light look (a white glyph with the ink outline) on the disabled lilac (H:246).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Log = require(Shared.Util.Log)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Tone = "light" | "dark" | "disabled"

-- One shape of a glyph, in the icon's 0..1 box: centre (x, y), size (w, h), rotation in degrees, corner radius as a
-- share of the shorter side (0.5 = a circle or pill). `detail` parts are marks drawn on top of the silhouette; a
-- `ring` detail is an outline only.
export type Part = {
	x: number,
	y: number,
	w: number,
	h: number,
	rotation: number?,
	corner: number?,
	detail: boolean?,
	ring: boolean?,
}

export type Spec = {
	name: string,
	icon: string,
	sizePx: number?,
	tone: Tone?, -- default "light"
	layoutOrder: number?,
	parent: Instance?,
}

-- UI FINAL R1: IconGlyph.image's options; `shadow` = the drop shadow (px lower, alpha, colour; default the ink).
export type ImageProps = {
	name: string,
	sizePx: number?,
	layoutOrder: number?,
	parent: Instance?,
	shadow: { px: number, alpha: number, color: Color3? }?,
}

export type IconGlyph = {
	root: Frame,
	setIcon: (self: IconGlyph, icon: string) -> (),
	setTone: (self: IconGlyph, tone: Tone) -> (),
	icon: (self: IconGlyph) -> string,
	destroy: (self: IconGlyph) -> (),
}

-- Constants

local DEFAULT_SIZE_PX = 32
local OUTLINE_SHARE = 0.06 -- the outline, as a share of the icon size ...
local OUTLINE_MIN_PX = 1.5 -- ... between these
local OUTLINE_MAX_PX = 3
local Z_OUTLINE, Z_FILL, Z_DETAIL = 1, 2, 3

-- Icon name -> AssetTable image slot.
local SLOTS: { [string]: string } = {
	squishies = "img.nav.squishies",
	boxes = "img.nav.boxes",
	shop = "img.nav.shop",
	quests = "img.nav.quests",
	daily = "img.nav.daily",
	settings = "img.nav.settings",
	duel = "img.nav.duel",
	change = "img.icon.change",
	clock = "img.icon.clock",
	upgrade = "img.icon.upgrade",
	inspect = "img.icon.inspect",
	close = "img.icon.close",
	check = "img.icon.check",
	highway = "img.nav.highway", -- access2
	income = "img.coin", -- INCOME step 2: the coin picture until Diego draws the INCOME sticker
}
local ALIASES: { [string]: string } = { swords = "duel", x = "close" }

local function part(x: number, y: number, w: number, h: number, rotation: number?, corner: number?): Part
	return { x = x, y = y, w = w, h = h, rotation = rotation, corner = corner }
end

local function detail(x: number, y: number, w: number, h: number, rotation: number?, corner: number?): Part
	return { x = x, y = y, w = w, h = h, rotation = rotation, corner = corner, detail = true }
end

-- The placeholder glyphs (readings: shapes chosen to echo the design's Material icons; the user may replace any of them
-- with an uploaded image through its slot).
local GLYPHS: { [string]: { Part } } = {
	-- A bread-loaf squishy with cat ears and a face (the design's "bakery" tile).
	squishies = {
		part(0.3, 0.3, 0.22, 0.22, 45, 0.2),
		part(0.7, 0.3, 0.22, 0.22, 45, 0.2),
		part(0.5, 0.6, 0.84, 0.56, 0, 0.45),
		detail(0.38, 0.6, 0.09, 0.09, 0, 0.5),
		detail(0.62, 0.6, 0.09, 0.09, 0, 0.5),
		detail(0.5, 0.7, 0.12, 0.05, 0, 0.5),
	},
	-- A gift box: a bow, a lid and a box with a ribbon.
	boxes = {
		part(0.38, 0.19, 0.24, 0.16, -25, 0.5),
		part(0.62, 0.19, 0.24, 0.16, 25, 0.5),
		part(0.5, 0.38, 0.9, 0.2, 0, 0.25),
		part(0.5, 0.67, 0.76, 0.42, 0, 0.15),
		detail(0.5, 0.62, 0.1, 0.52, 0, 0),
	},
	-- A little storefront: a wide awning with a scalloped edge hanging over a narrower shop with a window and a door.
	-- Foam fix: no stripes cutting the awning into blocks and a gap (drawn as the outline) between the scallops and the
	-- shop, so it no longer reads as a castle's battlements.
	shop = {
		part(0.5, 0.24, 0.96, 0.22, 0, 0.3),
		part(0.14, 0.36, 0.24, 0.2, 0, 0.5),
		part(0.38, 0.36, 0.24, 0.2, 0, 0.5),
		part(0.62, 0.36, 0.24, 0.2, 0, 0.5),
		part(0.86, 0.36, 0.24, 0.2, 0, 0.5),
		part(0.5, 0.71, 0.72, 0.42, 0, 0.12),
		detail(0.32, 0.66, 0.2, 0.16, 0, 0.25),
		detail(0.64, 0.75, 0.18, 0.3, 0, 0.25),
	},
	-- A clipboard checklist: a board, a clip, a tick and two lines.
	quests = {
		part(0.5, 0.55, 0.7, 0.8, 0, 0.14),
		part(0.5, 0.15, 0.34, 0.14, 0, 0.3),
		detail(0.3, 0.45, 0.06, 0.14, -45, 0.5),
		detail(0.37, 0.41, 0.06, 0.24, 40, 0.5),
		detail(0.6, 0.42, 0.26, 0.07, 0, 0.5),
		detail(0.5, 0.62, 0.46, 0.07, 0, 0.5),
		detail(0.5, 0.77, 0.46, 0.07, 0, 0.5),
	},
	-- A calendar: two binder rings, a page with a header line and a grid of days.
	daily = {
		part(0.5, 0.58, 0.82, 0.72, 0, 0.15),
		part(0.32, 0.2, 0.1, 0.2, 0, 0.5),
		part(0.68, 0.2, 0.1, 0.2, 0, 0.5),
		detail(0.5, 0.38, 0.82, 0.06, 0, 0),
		detail(0.32, 0.55, 0.1, 0.1, 0, 0.3),
		detail(0.5, 0.55, 0.1, 0.1, 0, 0.3),
		detail(0.68, 0.55, 0.1, 0.1, 0, 0.3),
		detail(0.32, 0.72, 0.1, 0.1, 0, 0.3),
		detail(0.5, 0.72, 0.1, 0.1, 0, 0.3),
	},
	-- A gear: four bars as eight teeth behind a round hub with a hole.
	settings = {
		part(0.5, 0.5, 0.24, 0.92, 0, 0.2),
		part(0.5, 0.5, 0.24, 0.92, 45, 0.2),
		part(0.5, 0.5, 0.24, 0.92, 90, 0.2),
		part(0.5, 0.5, 0.24, 0.92, 135, 0.2),
		part(0.5, 0.5, 0.7, 0.7, 0, 0.5),
		detail(0.5, 0.5, 0.28, 0.28, 0, 0.5),
	},
	-- Two crossed swords (blade, guard, grip, pommel each), the duel.
	duel = {
		part(0.56, 0.4, 0.13, 0.62, 45, 0.4),
		part(0.33, 0.63, 0.34, 0.09, 45, 0.5),
		part(0.22, 0.74, 0.09, 0.18, 45, 0.3),
		part(0.15, 0.81, 0.12, 0.12, 0, 0.5),
		part(0.44, 0.4, 0.13, 0.62, -45, 0.4),
		part(0.67, 0.63, 0.34, 0.09, -45, 0.5),
		part(0.78, 0.74, 0.09, 0.18, -45, 0.3),
		part(0.85, 0.81, 0.12, 0.12, 0, 0.5),
	},
	-- Two arrows, right then left (swap).
	change = {
		part(0.44, 0.34, 0.56, 0.14, 0, 0.5),
		part(0.7, 0.34, 0.3, 0.3, 45, 0.15),
		part(0.56, 0.68, 0.56, 0.14, 0, 0.5),
		part(0.3, 0.68, 0.3, 0.3, 45, 0.15),
	},
	-- A clock face with two hands.
	clock = {
		part(0.5, 0.5, 0.86, 0.86, 0, 0.5),
		detail(0.5, 0.35, 0.08, 0.3, 0, 0.5),
		detail(0.62, 0.5, 0.26, 0.08, 0, 0.5),
		detail(0.5, 0.5, 0.12, 0.12, 0, 0.5),
	},
	-- An up arrow in a circle (upgrade ready).
	upgrade = {
		part(0.5, 0.5, 0.86, 0.86, 0, 0.5),
		detail(0.5, 0.6, 0.14, 0.34, 0, 0.3),
		detail(0.5, 0.39, 0.3, 0.3, 45, 0.1),
	},
	-- A magnifying glass: a lens with a glass ring and a handle.
	inspect = {
		part(0.74, 0.74, 0.16, 0.4, -45, 0.5),
		part(0.42, 0.42, 0.64, 0.64, 0, 0.5),
		{ x = 0.42, y = 0.42, w = 0.38, h = 0.38, corner = 0.5, detail = true, ring = true },
	},
	-- A chunky X: two rounded bars crossed at the centre.
	close = {
		part(0.5, 0.5, 0.86, 0.26, 45, 0.5),
		part(0.5, 0.5, 0.86, 0.26, -45, 0.5),
	},
	-- A tick: a short bar down to the joint and a long bar up to the right.
	check = {
		part(0.3, 0.6, 0.38, 0.22, 45, 0.5),
		part(0.6, 0.49, 0.64, 0.22, -50, 0.5),
	},
	-- Access2 (2026-10-18): the HIGHWAY stand-in tile, PLACEHOLDER: the lobby design v6's launch-spot arrow (LK:39
	-- arrowShape: a 1.8-wide shaft under a 3.2-wide head, 3.5 tall, the throw's way) pointing up, read as this file's
	-- other arrows are (change, upgrade): a bar under a square turned 45°.
	highway = {
		part(0.5, 0.7, 0.44, 0.46, 0, 0.12),
		part(0.5, 0.43, 0.56, 0.56, 45, 0.12),
	},
	-- INCOME step 2 (2026-10-26): a coin with a rim (drawn only while img.coin has no id).
	income = {
		part(0.5, 0.5, 0.86, 0.86, 0, 0.5),
		{ x = 0.5, y = 0.5, w = 0.56, h = 0.56, corner = 0.5, detail = true, ring = true },
	},
}

local NAMES: { string } = {
	"squishies",
	"boxes",
	"shop",
	"quests",
	"daily",
	"settings",
	"duel",
	"change",
	"clock",
	"upgrade",
	"inspect",
	"close",
	"check",
	"highway", -- access2
	"income", -- INCOME step 2
}

-- Module table

local IconGlyph = {}

IconGlyph.NAMES = table.freeze(table.clone(NAMES))

-- Private

local log = Log.new("IconGlyph")
local warned: { [string]: boolean } = {}

-- fill, line (outline and details) and whether the outline shows, per tone.
local function toneColors(tone: Tone): (Color3, Color3, boolean)
	if tone == "dark" then
		return Theme.Colors.inkUI, Theme.Colors.frosting, false
	elseif tone == "disabled" then
		return Theme.Colors.disabledText, Theme.Colors.inkUI, true -- UI FINAL R1: white with the ink outline (H:246)
	end
	return Theme.Colors.white, Theme.Colors.inkUI, true
end

-- Public: pure data

-- The canonical name of an icon (aliases resolved), or nil for an unknown icon.
function IconGlyph.canonical(icon: string): string?
	local name = ALIASES[icon] or icon
	return if GLYPHS[name] then name else nil
end

-- The AssetTable image slot an icon reads first, or nil for an unknown icon.
function IconGlyph.slotOf(icon: string): string?
	local name = IconGlyph.canonical(icon)
	return if name then SLOTS[name] else nil
end

-- The placeholder parts of an icon (a copy), or an empty list for an unknown icon.
function IconGlyph.parts(icon: string): { Part }
	local name = IconGlyph.canonical(icon)
	local list = if name then GLYPHS[name] else nil
	if list == nil then
		return {}
	end
	local copy: { Part } = {}
	for _, p in list do
		table.insert(copy, table.clone(p))
	end
	return copy
end

-- The outline thickness (px) of a placeholder `sizePx` wide.
function IconGlyph.outlinePx(sizePx: number): number
	return math.clamp(sizePx * OUTLINE_SHARE, OUTLINE_MIN_PX, OUTLINE_MAX_PX)
end

-- Public: component

-- UI FINAL R1: an image-only icon (see the header): a holder `sizePx` square (default 32) named props.name, with the
-- AssetTable picture `key` ("Image", fitted) and, with props.shadow, a copy of it ("Shadow": the shadow colour at
-- shadow.alpha, shadow.px lower, behind). Hidden while the id is nil. Returns the holder.
function IconGlyph.image(key: string, props: ImageProps): Frame
	local size = props.sizePx or DEFAULT_SIZE_PX
	local content = AssetTable.image(key)
	local holder: Frame = Create("Frame", {
		Name = props.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = props.layoutOrder or 0,
		Visible = content ~= nil,
	})
	local shadow = props.shadow
	if shadow then
		Create("ImageLabel", {
			Name = "Shadow",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, shadow.px),
			Size = UDim2.fromScale(1, 1),
			Image = content or "",
			ImageColor3 = shadow.color or Theme.Colors.inkUI,
			ImageTransparency = 1 - shadow.alpha,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = Z_OUTLINE,
			Parent = holder,
		})
	end
	Create("ImageLabel", {
		Name = "Image",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Image = content or "",
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = Z_FILL,
		Parent = holder,
	})
	if props.parent then
		holder.Parent = props.parent
	end
	return holder
end

function IconGlyph.new(spec: Spec): IconGlyph
	local cleanup = Cleanup.new()
	local size = spec.sizePx or DEFAULT_SIZE_PX
	local root: Frame = Create("Frame", {
		Name = spec.name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)

	local current = spec.icon
	local tone: Tone = spec.tone or "light"
	local outlines: { Frame } = {}
	local fills: { Frame } = {}
	local details: { GuiObject } = {}
	local rings: { UIStroke } = {}
	local image: ImageLabel? = nil

	local function clear()
		for _, child in root:GetChildren() do
			child:Destroy()
		end
		table.clear(outlines)
		table.clear(fills)
		table.clear(details)
		table.clear(rings)
		image = nil
	end

	local function paint()
		local fill, line, outlined = toneColors(tone)
		for _, frame in outlines do
			frame.Visible = outlined
			frame.BackgroundColor3 = line
		end
		for _, frame in fills do
			frame.BackgroundColor3 = fill
		end
		for _, object in details do
			object.BackgroundColor3 = line
		end
		for _, stroke in rings do
			stroke.Color = line
		end
		local shown = image
		if shown then
			shown.ImageTransparency = 0
		end
	end

	local function shape(p: Part, grow: number, zIndex: number): Frame
		local frame: Frame = Create("Frame", {
			Name = if p.detail then "Detail" elseif grow > 0 then "Outline" else "Fill",
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(p.x, p.y),
			Size = UDim2.new(p.w, grow * 2, p.h, grow * 2),
			Rotation = p.rotation or 0,
			ZIndex = zIndex,
			Parent = root,
		})
		local corner = p.corner or 0
		if corner > 0 then
			-- A corner as a share of the shorter side, kept concentric when the outline copy is grown.
			local short = math.min(p.w, p.h) * size
			local px = corner * short + grow
			Create("UICorner", { CornerRadius = UDim.new(px / math.max(1, short + grow * 2), 0), Parent = frame })
		end
		return frame
	end

	local function build(icon: string)
		clear()
		current = icon
		if IconGlyph.canonical(icon) == nil and not warned[icon] then
			warned[icon] = true
			log:warn(`unknown icon {icon}`)
		end
		local slot = IconGlyph.slotOf(icon)
		local content = if slot then AssetTable.image(slot) else nil
		if content then
			image = Create("ImageLabel", {
				Name = "Image",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = content,
				ScaleType = Enum.ScaleType.Fit,
				Parent = root,
			})
			paint()
			return
		end
		local outlinePx = IconGlyph.outlinePx(size)
		for _, p in IconGlyph.parts(icon) do
			if p.detail then
				local mark = shape(p, 0, Z_DETAIL)
				if p.ring then
					mark.BackgroundTransparency = 1
					table.insert(rings, Theme.stroke(Theme.Colors.inkUI, outlinePx, mark))
				else
					table.insert(details, mark)
				end
			else
				table.insert(outlines, shape(p, outlinePx, Z_OUTLINE))
				table.insert(fills, shape(p, 0, Z_FILL))
			end
		end
		paint()
	end

	build(current)
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: IconGlyph
	self.root = root

	function self.setIcon(_: IconGlyph, icon: string)
		if icon ~= current then
			build(icon)
		end
	end

	function self.setTone(_: IconGlyph, newTone: Tone)
		if newTone ~= tone then
			tone = newTone
			paint()
		end
	end

	function self.icon(_: IconGlyph): string
		return current
	end

	function self.destroy(_: IconGlyph)
		cleanup:clean()
	end

	return self
end

return IconGlyph
