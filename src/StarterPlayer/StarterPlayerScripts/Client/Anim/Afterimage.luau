--!strict
-- Afterimage (client only; 2026-10-15 dash + double jump overhaul). A ghost of a character at this instant: an
-- anchored copy of its visible body parts and accessory handles in one flat colour (Neon), fading out where it stood.
-- Cosmetic only, under Workspace.SD_ClientFx.Afterimages (CanCollide / CanQuery / CanTouch false, no shadows), never
-- replicated. Numbers in Config.Vfx.Afterimage, the colour from the caller (the mover's team tint, Art/Palette).
-- Each copy is a Clone() of the part with every child removed except its mesh (a SpecialMesh keeps the accessory's
-- shape), textures cleared so the colour shows. The HumanoidRootPart and fully transparent parts are left out, and so
-- is a part the local camera hides (LocalTransparencyModifier >= 0.5: the own body in first person), so the own ghost
-- never fills the screen.
--
-- API
--   Afterimage.spawn(character, color, opts?) -> boolean   one ghost (false when the budget is full or nothing shows)
--   Afterimage.fadeAt(t, from, seconds) -> number          pure: the ghost's Transparency t seconds after it appeared
--   Afterimage.counts() -> { ghosts }  / Afterimage.clear()

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Scheduler = require(script.Parent.Scheduler)

-- Types

export type Options = {
	transparency: number?, -- the start (default Config.Vfx.Afterimage.transparency)
	seconds: number?, -- the fade (default Config.Vfx.Afterimage.seconds)
	drift: Vector3?, -- studs/s the ghost slides while it fades (default none)
}

type Ghost = {
	model: Model,
	parts: { BasePart },
	from: number,
	seconds: number,
	drift: Vector3,
	born: number,
	origin: { CFrame },
}

-- Constants

local CFG = Config.Vfx.Afterimage
local FX_FOLDER = "SD_ClientFx"
local OWN_FOLDER = "Afterimages"
local ROOT_NAME = "HumanoidRootPart"
local HIDDEN_LOCAL = 0.5

-- Module table

local Afterimage = {}

-- Private state

local folder: Folder? = nil
local ghosts: { Ghost } = {}
local stepping = false

-- Pure

function Afterimage.fadeAt(t: number, from: number, seconds: number): number
	if not (seconds > 0) then
		return 1
	end
	local u = math.clamp(t / seconds, 0, 1)
	return from + (1 - from) * u * u -- Quad In: it holds a moment, then goes
end

-- Private

local function ownFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local fx = Workspace:FindFirstChild(FX_FOLDER)
	if fx == nil then
		local made = Instance.new("Folder")
		made.Name = FX_FOLDER
		made.Parent = Workspace
		fx = made
	end
	local own = (fx :: Instance):FindFirstChild(OWN_FOLDER)
	if own == nil or not own:IsA("Folder") then
		local made = Instance.new("Folder")
		made.Name = OWN_FOLDER
		made.Parent = fx
		own = made
	end
	folder = own :: Folder
	return own :: Folder
end

local function shows(part: BasePart): boolean
	return part.Name ~= ROOT_NAME and part.Transparency < 0.95 and part.LocalTransparencyModifier < HIDDEN_LOCAL
end

local function copyOf(part: BasePart, color: Color3, transparency: number): BasePart
	local copy = part:Clone()
	for _, child in copy:GetChildren() do
		if child:IsA("SpecialMesh") then
			child.TextureId = ""
			child.VertexColor = Vector3.one
		else
			child:Destroy()
		end
	end
	if copy:IsA("MeshPart") then
		pcall(function()
			(copy :: MeshPart).TextureID = ""
		end)
	end
	copy.Anchored = true
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.CastShadow = false
	copy.Massless = true
	copy.Material = Enum.Material.Neon
	copy.Color = color
	copy.Transparency = transparency
	copy.Reflectance = 0
	copy.LocalTransparencyModifier = 0
	return copy
end

local function step(_dt: number, now: number): boolean
	for index = #ghosts, 1, -1 do
		local ghost = ghosts[index]
		local t = now - ghost.born
		if t >= ghost.seconds or ghost.model.Parent == nil then
			ghost.model:Destroy()
			table.remove(ghosts, index)
			continue
		end
		local transparency = Afterimage.fadeAt(t, ghost.from, ghost.seconds)
		local offset = ghost.drift * t
		for i, part in ghost.parts do
			part.Transparency = transparency
			if offset ~= Vector3.zero then
				part.CFrame = ghost.origin[i] + offset
			end
		end
	end
	if #ghosts == 0 then
		stepping = false
		return false
	end
	return true
end

-- Public

function Afterimage.spawn(character: Model, color: Color3, opts: Options?): boolean
	if #ghosts >= CFG.maxLive then
		return false
	end
	local from = if opts and opts.transparency then opts.transparency else CFG.transparency
	local model = Instance.new("Model")
	model.Name = character.Name .. "_Ghost"
	local parts: { BasePart } = {}
	local origin: { CFrame } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and shows(d) then
			local copy = copyOf(d, color, from)
			copy.Parent = model
			table.insert(parts, copy)
			table.insert(origin, copy.CFrame)
		end
	end
	if #parts == 0 then
		model:Destroy()
		return false
	end
	model.Parent = ownFolder()
	table.insert(ghosts, {
		model = model,
		parts = parts,
		from = from,
		seconds = if opts and opts.seconds then opts.seconds else CFG.seconds,
		drift = if opts and opts.drift then opts.drift else Vector3.zero,
		born = os.clock(),
		origin = origin,
	})
	if not stepping then
		stepping = true
		Scheduler.add(step, "render")
	end
	return true
end

function Afterimage.counts(): { [string]: number }
	return { ghosts = #ghosts }
end

function Afterimage.clear()
	for _, ghost in ghosts do
		ghost.model:Destroy()
	end
	table.clear(ghosts)
end

return Afterimage
