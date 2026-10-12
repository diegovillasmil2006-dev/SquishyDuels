--!strict
-- CrackCanvas (client only). Spec phase2-squeeze §1.14, §3.4 "Crack canvas" 3-4: the knead shell's colour atlas, one
-- EditableImage (Config.Knead.shell.atlas: 1024 on High, 512 on Low) shown as the shell MeshPart's TextureContent. Each
-- part's tile (Anim/ShellGeometry's UV rectangle) is filled with that part's colour; the crack lines Anim/CrackNetwork
-- reveals are drawn into it with the design's colour rules (sqWax, squish.js:86-93): a halo whitened toward min(colour ×
-- haloMul + haloAdd, 1), then the line darkened to colour × lineDarken. No shader and no per-pixel Voronoi: 1 px
-- DrawLine calls along the precomputed segments.
--
-- Pure (unit-tested):
--   CrackCanvas.lineColor(base) / haloColor(base) -> Color3
--   CrackCanvas.stepAlpha(new, previous) -> number   what one more blend adds so the total is `new`: (new - previous) /
--     (1 - previous), at least 0 (a segment's alpha only grows until re-wax)
--   CrackCanvas.ops(change, base, size) -> { Op }    the DrawLine calls of one CrackNetwork Change on a size² atlas: the
--     halo across the line (offsets 0 and ±Config.Wax.canvas.haloOffsets px, the outermost pair at haloFalloff: the
--     design's smoothstep halo, squish.js:86), then the line; "across" is y for a mostly horizontal segment, else x;
--     each op's transparency is 1 - stepAlpha(its alpha now, its alpha at change.previous); every point is clamped
--     into [0, size - 1] (EditableImage:DrawLine errors on a point outside the image, which stopped the knead)
--   CrackCanvas.fills(shell, colors, size) -> { Fill }   the whole image in colors[1], then each part's tile one pixel
--     wider each side (the shelf packer's gutters) in colors[part]
-- The atlas:
--   CrackCanvas.new(shell, colors, size) -> Canvas?   nil when the EditableImage cannot be made (the knead then falls
--                                                     back); filled at once
--   canvas.image, canvas:fill() (re-wax), canvas:queue(changes), canvas:draw(budget) -> drawn changes (in order, at most
--   `budget`), canvas:clear() (drops the queue), canvas:pending() -> number, canvas:destroy()
-- Not here (spec §3.4 step 5): the smooth terms (the dent darkening, the crack whitening crack × crackWhiten, the rim
-- highlight) would be vertex colours. TODO(Studio): check whether EditableMesh vertex colours multiply with
-- TextureContent before adding them (the docs only say they multiply the part colour).

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Change = {
	segment: number,
	octave: number,
	part: number,
	u0: number,
	v0: number,
	u1: number,
	v1: number,
	alpha: number,
	previous: number,
	line: number,
	halo: number,
}

export type Op = { from: Vector2, to: Vector2, color: Color3, transparency: number }

export type Fill = { position: Vector2, size: Vector2, color: Color3 }

-- What fills() reads of an Anim/ShellGeometry shell.
export type ShellLike = { parts: { { tile: { number } } } }

type CanvasData = {
	image: EditableImage,
	_shell: ShellLike,
	_colors: { Color3 },
	_size: number,
	_queue: { Change },
	_head: number,
	_dead: boolean,
}

local LINES = Config.Wax.lines
local CANVAS = Config.Wax.canvas
local WHITE = Color3.new(1, 1, 1)

local CanvasClass = {}
CanvasClass.__index = CanvasClass

export type Canvas = typeof(setmetatable({} :: CanvasData, CanvasClass))

local CrackCanvas = {}

-- Public: pure

function CrackCanvas.lineColor(base: Color3): Color3
	local k = LINES.lineDarken
	return Color3.new(base.R * k, base.G * k, base.B * k)
end

function CrackCanvas.haloColor(base: Color3): Color3
	local function channel(x: number): number
		return math.min(x * LINES.haloMul + LINES.haloAdd, 1)
	end
	return Color3.new(channel(base.R), channel(base.G), channel(base.B))
end

function CrackCanvas.stepAlpha(new: number, previous: number): number
	if new <= previous or previous >= 1 then
		return 0
	end
	return (new - previous) / (1 - previous)
end

function CrackCanvas.ops(change: Change, base: Color3, size: number): { Op }
	local from = Vector2.new(change.u0 * size, change.v0 * size)
	local to = Vector2.new(change.u1 * size, change.v1 * size)
	local across = if math.abs(to.X - from.X) >= math.abs(to.Y - from.Y) then Vector2.yAxis else Vector2.xAxis
	-- The share of `change.halo` / `change.line` the step started from (alpha is linear in both).
	local before = if change.alpha > 0 then change.previous / change.alpha else 0
	local ops: { Op } = {}
	local haloColor = CrackCanvas.haloColor(base)
	-- A tile on the atlas' far edge ends 2 px (gutterTexels) inside it, so a halo offset can reach x or y = size.
	local edge = size - 1
	local function inside(point: Vector2): Vector2
		return Vector2.new(math.clamp(point.X, 0, edge), math.clamp(point.Y, 0, edge))
	end
	local function add(offset: number, color: Color3, target: number)
		local step = CrackCanvas.stepAlpha(target, target * before)
		if step > 0 then
			table.insert(ops, {
				from = inside(from + across * offset),
				to = inside(to + across * offset),
				color = color,
				transparency = 1 - step,
			})
		end
	end
	add(0, haloColor, change.halo)
	local offsets = CANVAS.haloOffsets
	for index, offset in offsets do
		local share = if index == #offsets and #offsets > 1 then CANVAS.haloFalloff else 1
		add(offset, haloColor, change.halo * share)
		add(-offset, haloColor, change.halo * share)
	end
	add(0, CrackCanvas.lineColor(base), change.line)
	return ops
end

function CrackCanvas.fills(shell: ShellLike, colors: { Color3 }, size: number): { Fill }
	local fills: { Fill } = {
		{ position = Vector2.zero, size = Vector2.new(size, size), color = colors[1] or WHITE },
	}
	for index, part in shell.parts do
		local tile = part.tile
		local x0 = math.max(0, math.floor(tile[1] * size + 1e-9) - 1)
		local y0 = math.max(0, math.floor(tile[2] * size + 1e-9) - 1)
		local x1 = math.min(size, math.ceil(tile[3] * size - 1e-9) + 1)
		local y1 = math.min(size, math.ceil(tile[4] * size - 1e-9) + 1)
		table.insert(fills, {
			position = Vector2.new(x0, y0),
			size = Vector2.new(x1 - x0, y1 - y0),
			color = colors[index] or colors[1] or WHITE,
		})
	end
	return fills
end

-- Public: the atlas

function CrackCanvas.new(shell: ShellLike, colors: { Color3 }, size: number): Canvas?
	local ok, made = pcall(function(): EditableImage?
		return AssetService:CreateEditableImage({ Size = Vector2.new(size, size) })
	end)
	local image: EditableImage? = if ok then made else nil
	if image == nil then
		return nil
	end
	local data: CanvasData = {
		image = image,
		_shell = shell,
		_colors = colors,
		_size = size,
		_queue = {},
		_head = 1,
		_dead = false,
	}
	local canvas = setmetatable(data, CanvasClass)
	canvas:fill()
	return canvas
end

function CanvasClass.fill(self: Canvas)
	if self._dead then
		return
	end
	for _, fill in CrackCanvas.fills(self._shell, self._colors, self._size) do
		self.image:DrawRectangle(fill.position, fill.size, fill.color, 0, Enum.ImageCombineType.Overwrite)
	end
end

function CanvasClass.queue(self: Canvas, changes: { Change })
	local queue = self._queue
	for _, change in changes do
		table.insert(queue, change)
	end
end

function CanvasClass.pending(self: Canvas): number
	return #self._queue - self._head + 1
end

function CanvasClass.draw(self: Canvas, budget: number): number
	if self._dead then
		return 0
	end
	local queue, image, size, colors = self._queue, self.image, self._size, self._colors
	local drawn = 0
	while drawn < budget and self._head <= #queue do
		local change = queue[self._head]
		self._head += 1
		drawn += 1
		local base = colors[change.part] or colors[1] or WHITE
		for _, op in CrackCanvas.ops(change, base, size) do
			image:DrawLine(op.from, op.to, op.color, op.transparency, Enum.ImageCombineType.BlendSourceOver)
		end
	end
	if self._head > #queue then
		table.clear(queue)
		self._head = 1
	end
	return drawn
end

function CanvasClass.clear(self: Canvas)
	table.clear(self._queue)
	self._head = 1
end

function CanvasClass.destroy(self: Canvas)
	if self._dead then
		return
	end
	self._dead = true
	self:clear()
	pcall(function()
		self.image:Destroy()
	end)
end

return CrackCanvas
