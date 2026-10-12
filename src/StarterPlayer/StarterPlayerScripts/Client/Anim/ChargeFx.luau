--!strict
-- ChargeFx (client only): the charge's and the crush's effect parts inside the first-person overlay's ViewportFrame
-- (feature 1, 2026-10-11; design: the combat-effects page "Squishy Combat FP v2.html", html:191-196, 508-514, 544-545,
-- 559; numbers in Config.FirstPerson.charge / crush, poses in Anim/ChargePoses). Particles draw nothing in a
-- ViewportFrame, so every effect is a small part, as the Inspect specks are (ViewmodelController draws those):
--   * glow(at, radius, colour, opacity)   a Neon ball round the toy (the design's additive sphere, html:192)
--   * outline(at, radius, on)             a flat white disc behind the toy (the design's white back-face shell at full
--       charge, html:193; a ViewportFrame has no back faces or outlines of its own: the closest option)
--   * orbit(at, radius, angle, scale, colours, on)   seven small diamonds round the toy (the design's octahedra,
--       html:195), tilted orbitTilt, turned `angle` about its up axis
--   * ring(at, colour, from, to, seconds)  a flat ring that grows and fades (the design's shock rings, opacity
--       (1 - t)^1.4, html:514, 559), facing the camera
--   * step(dt) the rings; clear() hides everything; destroy() removes every part.
-- Positions and sizes are in du; U = studs per du. Every part is anchored Neon (it glows, as the design's unlit
-- materials do) and takes no collision, touch, query or shadow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Palette = require(ReplicatedStorage.Shared.Art.Palette)

-- Types

type Ring = { part: BasePart, from: number, to: number, seconds: number, age: number }

export type ChargeFx = {
	glow: (self: ChargeFx, at: Vector3, radius: number, colour: Color3, opacity: number) -> (),
	outline: (self: ChargeFx, at: Vector3, radius: number, on: boolean) -> (),
	orbit: (
		self: ChargeFx,
		at: Vector3,
		radius: number,
		angle: number,
		scale: number,
		colours: { Color3 },
		on: boolean
	) -> (),
	ring: (self: ChargeFx, at: Vector3, colour: Color3, from: number, to: number, seconds: number) -> (),
	step: (self: ChargeFx, dt: number) -> (),
	clear: (self: ChargeFx) -> (),
	destroy: (self: ChargeFx) -> (),
	ringCount: (self: ChargeFx) -> number,
}

-- Constants

local CHARGE = Config.FirstPerson.charge
local MIN_PART = 0.001 -- studs: Roblox's smallest part size
local RING_THICKNESS = 0.02 -- the flat ring's depth, as a share of its diameter (reading: thin, as FxShapes' ring)
local OUTLINE_BEHIND = 1.02 -- the disc sits this share of the toy's radius behind its centre
local RING_FADE_POWER = 1.4 -- design: squishy-lib-v2.js:326
local RING_EASE_POWER = 3 -- design: squishy-lib-v2.js:326 (1 - (1 - t)^3)
local FACE_CAMERA = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's axis is its X: turned to point along Z
local DIAMOND = CFrame.Angles(math.pi / 4, 0, math.pi / 4) -- a cube on its corner reads as the design's octahedron

-- Module table

local ChargeFx = {}

-- Private

local function newPart(name: string, shape: Enum.PartType, material: Enum.Material, parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = Vector3.one * MIN_PART
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function hide(part: BasePart?)
	if part and part.Transparency ~= 1 then
		part.Transparency = 1
	end
end

-- Public

-- The ring's radius share and opacity t seconds into `seconds` (design: squishy-lib-v2.js:326). Pure.
function ChargeFx.ringSample(age: number, seconds: number): (number, number)
	local t = if seconds > 0 then math.clamp(age / seconds, 0, 1) else 1
	return 1 - (1 - t) ^ RING_EASE_POWER, (1 - t) ^ RING_FADE_POWER
end

-- The orbit pieces' offsets round the centre, before the tilt and turn (design: html:195): piece i at angle a = i/n·2π,
-- (cos a·r, sin 2a·wave, sin a·r). Pure.
function ChargeFx.orbitOffsets(count: number, radius: number, wave: number): { Vector3 }
	local list: { Vector3 } = {}
	for i = 0, count - 1 do
		local a = i / count * 2 * math.pi
		table.insert(list, Vector3.new(math.cos(a) * radius, math.sin(a * 2) * wave, math.sin(a) * radius))
	end
	return list
end

function ChargeFx.new(viewport: Instance, U: number): ChargeFx
	local glowPart: BasePart? = nil
	local outlinePart: BasePart? = nil
	local pieces: { BasePart } = {}
	local rings: { Ring } = {}
	local self = {} :: ChargeFx

	function self.glow(_: ChargeFx, at: Vector3, radius: number, colour: Color3, opacity: number)
		if not (opacity > 0.001) then
			hide(glowPart)
			return
		end
		local part = glowPart or newPart("ChargeGlow", Enum.PartType.Ball, Enum.Material.Neon, viewport)
		glowPart = part
		part.Color = colour
		part.Size = Vector3.one * math.max(2 * radius * U, MIN_PART)
		part.CFrame = CFrame.new(at * U)
		part.Transparency = 1 - math.clamp(opacity, 0, 1)
	end

	function self.outline(_: ChargeFx, at: Vector3, radius: number, on: boolean)
		if not on then
			hide(outlinePart)
			return
		end
		local part = outlinePart or newPart("ChargeOutline", Enum.PartType.Cylinder, Enum.Material.Neon, viewport)
		outlinePart = part
		part.Color = Palette.White
		local d = math.max(2 * radius * U, MIN_PART)
		part.Size = Vector3.new(math.max(d * RING_THICKNESS, MIN_PART), d, d)
		-- Behind the toy along the view (the overlay camera looks down -Z from about the origin).
		local behind = at + at.Unit * radius * OUTLINE_BEHIND
		part.CFrame = CFrame.new(behind * U) * FACE_CAMERA
		part.Transparency = 1 - 0.95 -- design: html:193 (opacity 0.95)
	end

	function self.orbit(
		_: ChargeFx,
		at: Vector3,
		radius: number,
		angle: number,
		scale: number,
		colours: { Color3 },
		on: boolean
	)
		if not on then
			for _, piece in pieces do
				hide(piece)
			end
			return
		end
		local count = CHARGE.orbitCount
		local offsets = ChargeFx.orbitOffsets(count, CHARGE.orbitRadius * radius, CHARGE.orbitWave * radius)
		local frame = CFrame.new(at * U) * CFrame.Angles(CHARGE.orbitTilt, angle, 0) -- design: html:510
		local size = math.max(2 * CHARGE.orbitPiece * radius * scale * U, MIN_PART)
		for i, offset in offsets do
			local found: BasePart? = pieces[i]
			local p = found or newPart("ChargeOrbit", Enum.PartType.Block, Enum.Material.Neon, viewport)
			pieces[i] = p
			p.Color = colours[(i - 1) % math.max(#colours, 1) + 1] or Palette.White
			p.Size = Vector3.one * size
			p.CFrame = frame * CFrame.new(offset * scale * U) * DIAMOND
			p.Transparency = 0
		end
	end

	function self.ring(_: ChargeFx, at: Vector3, colour: Color3, from: number, to: number, seconds: number)
		local part = newPart("ChargeRing", Enum.PartType.Ball, Enum.Material.Neon, viewport)
		part.Color = colour
		part.CFrame = CFrame.new(at * U)
		table.insert(rings, { part = part, from = from, to = to, seconds = seconds, age = 0 })
		self:step(0)
	end

	function self.step(_: ChargeFx, dt: number)
		for i = #rings, 1, -1 do
			local ring = rings[i]
			ring.age += dt
			if ring.age >= ring.seconds then
				ring.part:Destroy()
				table.remove(rings, i)
			else
				local share, opacity = ChargeFx.ringSample(ring.age, ring.seconds)
				local radius = ring.from + (ring.to - ring.from) * share
				local d = math.max(2 * radius * U, MIN_PART)
				ring.part.Size = Vector3.new(d, d, math.max(d * RING_THICKNESS, MIN_PART))
				ring.part.Transparency = 1 - opacity
			end
		end
	end

	function self.ringCount(_: ChargeFx): number
		return #rings
	end

	function self.clear(_: ChargeFx)
		hide(glowPart)
		hide(outlinePart)
		for _, piece in pieces do
			hide(piece)
		end
		for _, ring in rings do
			ring.part:Destroy()
		end
		table.clear(rings)
	end

	function self.destroy(_: ChargeFx)
		self:clear()
		for _, part in { glowPart, outlinePart } do
			if part then
				part:Destroy()
			end
		end
		glowPart, outlinePart = nil, nil
		for _, piece in pieces do
			piece:Destroy()
		end
		table.clear(pieces)
	end

	return self
end

return ChargeFx
