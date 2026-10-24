--!strict
-- PenBoard (shared). Neon Sugar lobby part 4 (2026-10-24): Diego's pen upgrade board, his SquishyLobby PenSign
-- ("Squishy Duels Lobby Redesign.zip" src/shared/SquishyLobby/PenSign.luau, design 1b), pixel for pixel on its 1024 ×
-- 640 canvas: a SurfaceGui for a pen's SignFace (12.8 × 8 studs) with two rows. BaseService draws it (owner
-- 2026-10-24: row 1 PEN SPACE, row 2 SHELF SPOTS); PenController repaints the own rows' buttons.
-- Changes from his file: the colours are Palette tokens (his Theme.Sign.Colors); the cards are named Row1 / Row2 so a
-- client finds its row again; the From, To and Price texts get their width from TextService instead of AutomaticSize
-- (AutomaticSize text inside a UIScale sizes wrong, and PenController's buy pop scales the button).
-- Public: build(parent) (the "Board" SurfaceGui, rows empty, no Adornee: the caller sets it), row(board, index),
-- setRow(card, row) (a whole row), setState(card, state, need) (only its button and caption: "buy", "need" with the
-- "Need N more" line, "max").

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

-- Types

export type State = "buy" | "need" | "max"
-- His row data: `from` -> `to` (the current and the next), `filled` of `total` progress segments, the price text.
export type Row = {
	title: string,
	icon: "shelf" | "income",
	from: string,
	to: string,
	filled: number,
	total: number,
	progress: string,
	price: string,
	state: State,
	need: string?,
}

-- Constants

local CANVAS = Vector2.new(1024, 640)
local FONT = Enum.Font.FredokaOne -- his Theme.Font (Fredoka One)
local ROWS_Y = { 24, 332 } -- each card's top on the canvas
local BAR_W, BAR_H, SEG_GAP = 280, 40, 7
local DETAIL_PX, PRICE_PX = 42, 62 -- the From / To and the Price text sizes
local PRICE_H = 72

-- Module table

local PenBoard = {}

-- Private

local function corner(parent: Instance, px: number?, scale: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = if scale then UDim.new(scale, 0) else UDim.new(0, px or 0)
	c.Parent = parent
end

local function box(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3,
	radius: number?,
	z: number?
): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.ZIndex = z or 1
	if radius then
		corner(f, radius)
	end
	f.Parent = parent
	return f
end

local function clear(f: Frame): Frame
	f.BackgroundTransparency = 1
	return f
end

local function label(
	parent: Instance,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	size: number,
	color: Color3,
	align: Enum.TextXAlignment?,
	z: number?
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.Text = ""
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = align or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Position = UDim2.fromOffset(x, y)
	t.Size = UDim2.fromOffset(w, h)
	t.ZIndex = z or 1
	t.Parent = parent
	return t
end

-- Sets a one-line text and its label's width to the text's (what his AutomaticSize X did).
local function fit(t: TextLabel, text: string)
	t.Text = text
	local ok, size = pcall(function(): Vector2
		return TextService:GetTextSize(text, t.TextSize, FONT, Vector2.new(4000, 4000))
	end)
	local width = if ok and typeof(size) == "Vector2" then size.X else #text * t.TextSize * 0.6
	t.Size = UDim2.fromOffset(math.ceil(width), t.Size.Y.Offset)
end

local function coin(parent: Instance, x: number, y: number, r: number, z: number): Frame
	local rim = box(parent, "Coin", x, y, r * 2, r * 2, Palette.PenBoardCoinRim, nil, z)
	corner(rim, nil, 0.5)
	local face =
		box(rim, "Face", r - r * 0.82, r - r * 0.06 - r * 0.82, r * 1.64, r * 1.64, Palette.PenBoardCoin, nil, z + 1)
	corner(face, nil, 0.5)
	local shine = math.max(2, r * 0.1)
	box(rim, "Shine", r - r * 0.14, r - r * 0.5, r * 0.28, r * 0.88, Palette.PenBoardCoinShine, shine, z + 2)
	return rim
end

-- His blocky right-pointing arrow (a stepped triangle).
local function stepRight(parent: Instance, w: number, h: number, color: Color3, z: number): Frame
	local holder = clear(box(parent, "Arrow", 0, 0, w, h, color, nil, z))
	local steps = 4
	for i = 0, steps - 1 do
		local sh = h * (1 - i / steps)
		box(holder, "Step" .. i, i * w / steps, (h - sh) / 2, w / steps + 0.5, sh, color, nil, z)
	end
	return holder
end

-- His blocky up arrow (a stepped head and a stem), centred on (ax, ay) = the head's base.
local function stepUp(parent: Instance, ax: number, ay: number, a: number, color: Color3, z: number)
	local steps, headH, headW = 4, a * 1.6, a * 2.6
	for j = 0, steps - 1 do
		local w = headW * (j + 1) / steps
		box(parent, "Head" .. j, ax - w / 2, ay - headH + j * headH / steps, w, headH / steps + 0.5, color, nil, z)
	end
	box(parent, "Stem", ax - a * 0.5, ay, a, a * 1.5, color, nil, z)
end

local function buildRow(parent: Instance, index: number)
	local card = box(parent, "Row" .. index, 24, ROWS_Y[index], 976, 284, Palette.PenBoardCard, 24, 2)

	-- The icon tile (canvas: 48, y + 34, 196 × 196, a 12 px drop).
	box(card, "IconShadow", 24, 46, 196, 196, Palette.PenBoardTileDark, 26, 3)
	local tile = box(card, "Icon", 24, 34, 196, 196, Palette.PenBoardTile, 26, 4)
	local s, cx, cy = 196, 98, 98

	local shelf = clear(box(tile, "ShelfGlyph", 0, 0, 196, 196, Palette.PenBoardTile, nil, 5))
	local q, g = s * 0.26, s * 0.08
	for i = 0, 1 do
		for j = 0, 1 do
			local x, y = cx - q - g / 2 + i * (q + g), cy - q - g / 2 + j * (q + g)
			box(shelf, "Spot", x, y, q, q, Palette.PenBoardGlyph, q * 0.18, 5)
		end
	end
	box(shelf, "Shelf", cx - s * 0.34, cy + q + g, s * 0.68, s * 0.07, Palette.PenBoardGlyph, 4, 5)

	local income = clear(box(tile, "IncomeGlyph", 0, 0, 196, 196, Palette.PenBoardTile, nil, 5))
	local cr = s * 0.27
	coin(income, cx - s * 0.08 - cr, cy + s * 0.04 - cr, cr, 5)
	local ax, ay, a = cx + s * 0.24, cy - s * 0.18, s * 0.13
	-- the outline pass, then the fill pass
	local outline = clear(box(income, "ArrowOutline", -4, -4, 196, 196, Palette.PenBoardTileDark, nil, 8))
	stepUp(outline, ax + 4, ay + 4, a * 1.12, Palette.PenBoardTileDark, 8)
	stepUp(income, ax, ay, a, Palette.PenBoardGlyph, 9)

	-- The text column.
	label(card, "Title", 252, 46, 440, 60, 60, Palette.PenBoardInk, nil, 3)
	local detail = clear(box(card, "Detail", 252, 121, 440, 44, Palette.PenBoardCard, nil, 3))
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 12)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = detail
	label(detail, "From", 0, 0, 0, 44, DETAIL_PX, Palette.PenBoardSub, nil, 3).LayoutOrder = 1
	stepRight(detail, 21, 23, Palette.PenBoardArrow, 3).LayoutOrder = 2
	label(detail, "To", 0, 0, 0, 44, DETAIL_PX, Palette.PenBoardSub, nil, 3).LayoutOrder = 3

	clear(box(card, "Progress", 252, 186, BAR_W, BAR_H, Palette.PenBoardCard, nil, 3))
	label(card, "ProgressText", 548, 190, 150, 34, 34, Palette.PenBoardSub, nil, 3)

	-- The price button (canvas: 724, y + 38, 252 × 132, a 12 px drop).
	box(card, "ButtonShadow", 700, 50, 252, 132, Palette.PenBoardGoDark, 22, 3)
	local button = box(card, "Button", 700, 38, 252, 132, Palette.PenBoardGo, 22, 4)
	local content = clear(box(button, "Content", 0, 0, 252, 132, Palette.PenBoardGo, nil, 5))
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Center
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	row.Padding = UDim.new(0, 14)
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Parent = content
	local coinHolder = clear(box(content, "CoinHolder", 0, 0, 57, 57, Palette.PenBoardGo, nil, 5))
	coinHolder.LayoutOrder = 1
	coin(coinHolder, 0, 0, 28.5, 5)
	local price = label(content, "Price", 0, 0, 0, PRICE_H, PRICE_PX, Palette.White, Enum.TextXAlignment.Center, 6)
	price.LayoutOrder = 2
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 6
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Color = Palette.PenBoardGoDark
	stroke.Parent = price

	label(card, "Caption", 700, 209, 252, 34, 32, Palette.PenBoardInk, Enum.TextXAlignment.Center, 3)
end

local function child(parent: Instance, ...: string): any
	local found: Instance? = parent
	for _, name in { ... } do
		found = if found then found:FindFirstChild(name) else nil
	end
	return found
end

-- Public

function PenBoard.build(parent: Instance): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = CANVAS
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ClipsDescendants = true
	local bg = box(gui, "Background", 0, 0, CANVAS.X, CANVAS.Y, Palette.PenBoardBg, nil, 1)
	for index = 1, #ROWS_Y do
		buildRow(bg, index)
	end
	gui.Parent = parent
	return gui
end

-- Row `index` (1 or 2) of a board, or nil (not there, or not streamed in yet).
function PenBoard.row(board: Instance, index: number): Frame?
	local card = child(board, "Background", "Row" .. index)
	return if card and card:IsA("Frame") then card else nil
end

function PenBoard.setRow(card: Frame, d: Row)
	local maxed = d.state == "max"
	child(card, "Title").Text = d.title
	child(card, "Icon", "ShelfGlyph").Visible = d.icon == "shelf"
	child(card, "Icon", "IncomeGlyph").Visible = d.icon ~= "shelf"
	local from: TextLabel = child(card, "Detail", "From")
	fit(from, d.from)
	from.Visible = not maxed
	child(card, "Detail", "Arrow").Visible = not maxed
	fit(child(card, "Detail", "To"), d.to)

	local bar: Frame = child(card, "Progress")
	bar:ClearAllChildren()
	local n = math.max(1, d.total)
	local sw = (BAR_W - SEG_GAP * (n - 1)) / n
	for k = 1, n do
		local color = if maxed or k <= d.filled then Palette.PenBoardFill else Palette.PenBoardTrack
		box(bar, "Seg" .. k, (k - 1) * (sw + SEG_GAP), 0, sw, BAR_H, color, 5, 3)
	end
	child(card, "ProgressText").Text = d.progress
	fit(child(card, "Button", "Content", "Price"), d.price)
	PenBoard.setState(card, d.state, d.need)
end

function PenBoard.setState(card: Frame, state: State, need: string?)
	local maxed = state == "max"
	local face, dark = Palette.PenBoardGo, Palette.PenBoardGoDark
	if state == "need" then
		face, dark = Palette.PenBoardNo, Palette.PenBoardNoDark
	elseif maxed then
		face, dark = Palette.PenBoardMax, Palette.PenBoardMaxDark
	end
	-- A client paints its own row while the board streams in: a piece not there yet is skipped.
	local button, shadow = child(card, "Button"), child(card, "ButtonShadow")
	local price, coinHolder = child(card, "Button", "Content", "Price"), child(card, "Button", "Content", "CoinHolder")
	local stroke, caption = child(card, "Button", "Content", "Price", "UIStroke"), child(card, "Caption")
	if button and shadow and price and coinHolder and stroke and caption then
		button.BackgroundColor3 = face
		shadow.BackgroundColor3 = dark
		stroke.Color = dark
		coinHolder.Visible = not maxed
		if maxed then
			fit(price, Strings.pen.sign.max)
		end
		caption.Text = if maxed then "" elseif state == "need" then need or "" else Strings.pen.board.buy
		caption.TextColor3 = if state == "need" then Palette.PenBoardNeed else Palette.PenBoardInk
	end
end

return table.freeze(PenBoard)
