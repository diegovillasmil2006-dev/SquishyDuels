--!strict
-- SkyMapFxController (client only). Diego's sky maps (NEW MAPS FINALS zip, 2026-10-30) move like his demos
-- (updateAnim / animX in "Squishy Duels {Duel,TDM,FFA} Demo.dc.html", his SquishyMapFX.client.lua pattern): the parts
-- SkyMapBuilder tagged SquishyFX_<Kind> animate on this screen only. Colliders never move, so gameplay is unaffected.
--   Squish  round wall / cover: scale (1 + .6 a v, 1 - a v) from its bottom, its hull, cap and face with it
--   Bob     knobs, flag tops: y + sin(t sp + ph) amp          Float  sky props: bob, spin rs, roll sin(.7 t sp + ph) .18
--   Flag    pennants swing sin(t 2.4 + ph) .28 at the hang    SpinY  the carousel's slab turns at sp rad/s
--   Bulb    string lights blink in a chase                    Chase  a white flash runs up each stair
--   Pulse   spawn plates grow 1 -> 1.12 and fade              Shimmer zones flicker .8 + .15 sin
--   Amb     falling / rising bits with wobble                 Spark  sparkles rise 30 studs
--   Cloud   blocky clouds drift +X (wrap at 900) and bob
--   Pod     Squish Pods (2026-11-01, his TDM Demo :983 pad anim): the cake bobs .35 at 2.2, turns .9 rad/s, wobbles
--           (squash q = .1 sin 4.4t + .025 sin 9.1t, tilt .08 sin 1.7t); the beam's opacity .1 + .07 sin 3t; the
--           ring grows 1 -> 2.3 and fades .85 -> 0 (u = .8t % 1). SkyMapFxController.Collect(pod, seconds) (the
--           match's pad pickup, MatchController.syncPads): his shatter (:938, 18 cubes) and the cake and beam hidden
--           for `seconds`, then his pop back (:983, easeOutBack over 1 / 2.2 s).
-- Only the map nearest the camera (within ACTIVE_RANGE of its centre) animates. The place streams, so items join and
-- leave with CollectionService signals. Time = server time, so every screen shows the same pose.

-- Services

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- Constants

local PREFIX = "SquishyFX_"
local KINDS =
	{ "Squish", "Bob", "Float", "Flag", "SpinY", "Bulb", "Chase", "Pulse", "Shimmer", "Amb", "Spark", "Cloud", "Pod" }
local INK = Color3.fromHex("1c1530")
local WHITE = Color3.new(1, 1, 1)
local ACTIVE_RANGE = 900 -- studs from a map's centre (his maps are <= 270 wide; their sky props reach ~400)
local EPOCH = 1_793_000_000 -- keeps t small (CFrame angles are float32)
local TAU = 2 * math.pi

-- Module table

local SkyMapFxController = {}

-- Private

type Item = {
	kind: string,
	inst: Instance,
	root: Model?, -- the map (attribute MapId) it belongs to
	ph: number,
	sp: number,
	amp: number,
	base: CFrame?,
	size: Vector3?,
	parts: { BasePart }?,
	cfs: { CFrame }?,
	sizes: { Vector3 }?,
	attrs: { [string]: any },
	color: Color3?,
	tr: number?,
	-- Pod: the cake's parts (it.parts / cfs relative to the cake's centre, it.base / sizes), the beam and the ring
	beam: BasePart?,
	ring: BasePart?,
	ringSize: Vector3?,
	hiddenUntil: number?, -- server time (- EPOCH) the cake pops back after a pickup
	hidden: boolean?,
}

-- Squish Pods: a shard of his shatter (a cube with its ink hull), flying on its own (every map, not only the active one).
type Shard = { part: BasePart, hull: BasePart?, v: Vector3, av: Vector3, life: number, max: number, size: Vector3 }
local shards: { Shard } = {}

local items: { [Instance]: Item } = {}
local byMap: { [Model]: { [Instance]: Item } } = {} -- the same items, by map
local conn: RBXScriptConnection? = nil

local function mapOf(inst: Instance): Model?
	local node = inst.Parent
	while node and node ~= Workspace do
		if node:IsA("Model") and node:GetAttribute("MapId") ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function partsOf(inst: Instance): { BasePart }
	local list: { BasePart } = {}
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function add(kind: string, inst: Instance)
	local it: Item = {
		kind = kind,
		inst = inst,
		root = mapOf(inst),
		ph = inst:GetAttribute("Phase") or 0,
		sp = inst:GetAttribute("Speed") or 1,
		amp = inst:GetAttribute("Amp") or 0.5,
		attrs = inst:GetAttributes(),
	}
	if inst:IsA("Model") then
		it.base = inst:GetPivot()
		it.parts = partsOf(inst)
		local cfs = {}
		for i, p in it.parts :: { BasePart } do
			cfs[i] = p.CFrame
		end
		it.cfs = cfs
	elseif inst:IsA("BasePart") then
		it.base = inst.CFrame
		it.size = inst.Size
		it.color = inst.Color
		it.tr = inst.Transparency
		if kind == "Squish" then
			-- its hull, cap and face: offsets from the bottom centre and sizes, scaled with it
			local kids: { BasePart } = {}
			local cfs: { CFrame } = {}
			local sizes: { Vector3 } = {}
			for _, d in inst:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(kids, d)
					table.insert(cfs, d.CFrame)
					table.insert(sizes, d.Size)
				end
			end
			it.parts, it.cfs, it.sizes = kids, cfs, sizes
		end
	end
	if kind == "Pod" then
		-- the cake's parts relative to its centre (the body's), so it turns, bobs and squashes around it
		local gem = inst:FindFirstChild("Gem")
		local body = gem and gem:FindFirstChild("body")
		local kids: { BasePart } = {}
		local cfs: { CFrame } = {}
		local sizes: { Vector3 } = {}
		if gem and body and body:IsA("BasePart") then
			local centre = CFrame.new(body.Position)
			it.base = centre
			for _, p in partsOf(gem) do
				table.insert(kids, p)
				table.insert(cfs, centre:ToObjectSpace(p.CFrame))
				table.insert(sizes, p.Size)
			end
		end
		it.parts, it.cfs, it.sizes = kids, cfs, sizes
		local fx = inst:FindFirstChild("Fx")
		local beam, ring = fx and fx:FindFirstChild("beam"), fx and fx:FindFirstChild("ring")
		it.beam = if beam and beam:IsA("BasePart") then beam else nil
		if ring and ring:IsA("BasePart") then
			it.ring, it.ringSize = ring, ring.Size
		end
	end
	items[inst] = it
	local root = it.root
	if root then
		local bucket = byMap[root] or {}
		byMap[root] = bucket
		bucket[inst] = it
	end
end

local function remove(inst: Instance)
	local it = items[inst]
	items[inst] = nil
	local root = it and it.root
	local bucket = root and byMap[root]
	if bucket then
		bucket[inst] = nil
		if next(bucket) == nil then
			byMap[root :: Model] = nil
		end
	end
end

-- A part's local axes scaled by (sxz across, sy up), for a part whose axes lie along the world's.
local function scaledSize(cf: CFrame, size: Vector3, sxz: number, sy: number): Vector3
	local function f(v: Vector3): number
		return if math.abs(v.Y) > 0.7 then sy else sxz
	end
	return Vector3.new(size.X * f(cf.RightVector), size.Y * f(cf.UpVector), size.Z * f(-cf.LookVector))
end

local function activeMap(): Model?
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return nil
	end
	local camPos = cam.CFrame.Position
	local best: Model?, bestD = nil, ACTIVE_RANGE
	for root in byMap do
		local d = (root:GetPivot().Position - camPos).Magnitude
		if d < bestD then
			best, bestD = root, d
		end
	end
	return best
end

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

local function move(parts: { BasePart }, cfs: { CFrame }, delta: CFrame)
	for i, p in parts do
		table.insert(moveParts, p)
		table.insert(moveCFrames, delta * cfs[i])
	end
end

local function step(t: number, active: Model)
	table.clear(moveParts)
	table.clear(moveCFrames)
	local blinkStep = math.floor(t * 5)
	for inst, it in byMap[active] or {} do
		if inst.Parent == nil then
			remove(inst)
			continue
		end
		local k, a = it.kind, it.attrs
		if k == "Squish" then
			local part = inst :: BasePart
			local v = math.sin(t * it.sp + it.ph)
			local sxz, sy = 1 + it.amp * 0.6 * v, 1 - it.amp * v
			local base, size = it.base :: CFrame, it.size :: Vector3
			local bottom = Vector3.new(base.X, base.Y - size.X / 2, base.Z) -- a stood-up cylinder: its height is X
			part.Size = scaledSize(base, size, sxz, sy)
			part.CFrame = CFrame.new(bottom + Vector3.new(0, (base.Y - bottom.Y) * sy, 0)) * base.Rotation
			for i, kid in it.parts :: { BasePart } do
				local cf = (it.cfs :: { CFrame })[i]
				local o = cf.Position - bottom
				kid.Size = scaledSize(cf, (it.sizes :: { Vector3 })[i], sxz, sy)
				kid.CFrame = CFrame.new(bottom + Vector3.new(o.X * sxz, o.Y * sy, o.Z * sxz)) * cf.Rotation
			end
		elseif k == "Bob" then
			move(it.parts :: { BasePart }, it.cfs :: { CFrame }, CFrame.new(0, math.sin(t * it.sp + it.ph) * it.amp, 0))
		elseif k == "Float" then
			local base = it.base :: CFrame
			local y = math.sin(t * it.sp + it.ph) * it.amp
			local spin = ((a.Spin or 0) * t) % TAU
			local roll = math.sin(t * it.sp * 0.7 + it.ph) * 0.18
			local pivot = CFrame.new(base.Position + Vector3.new(0, y, 0))
				* CFrame.fromEulerAnglesXYZ(a.RX or 0, (a.RY or 0) + spin, roll)
			move(it.parts :: { BasePart }, it.cfs :: { CFrame }, pivot * base:Inverse())
		elseif k == "Flag" then
			local hang = it.base :: CFrame
			move(it.parts :: { BasePart }, it.cfs :: { CFrame }, hang * CFrame.Angles(0, 0, math.sin(t * it.sp + it.ph) * 0.28) * hang:Inverse())
		elseif k == "SpinY" then
			local pivot = it.base :: CFrame
			move(it.parts :: { BasePart }, it.cfs :: { CFrame }, pivot * CFrame.Angles(0, (t * it.sp) % TAU, 0) * pivot:Inverse())
		elseif k == "Bulb" then
			local i = a.Index or 0
			local on = (blinkStep + i) % 4 ~= 0 and math.sin(t * 2.2 + i * 0.9) > -0.6
			local baseColor = a.BaseColor or it.color
			;(inst :: BasePart).Color = if on then baseColor else baseColor:Lerp(INK, 0.6)
		elseif k == "Chase" then
			local u = ((t * 0.9 + it.ph) - (a.Index or 0) / (a.Count or 6) * 0.6) % 1
			local g = if u < 0.18 then 0.45 * math.sin(math.pi * u / 0.18) else 0
			;(inst :: BasePart).Color = (it.color :: Color3):Lerp(WHITE, g)
		elseif k == "Pulse" then
			local part = inst :: BasePart
			local u = (t * it.sp + it.ph) % 1
			local s = 1 + 0.12 * u
			local size = it.size :: Vector3
			part.Size = Vector3.new(size.X * s, size.Y, size.Z * s)
			part.Transparency = 1 - 0.55 * (1 - u)
		elseif k == "Shimmer" then
			(inst :: BasePart).Transparency = 1 - (0.8 + 0.15 * math.sin(t * it.sp + it.ph))
		elseif k == "Amb" then
			local part = inst :: BasePart
			local u = (t * it.sp + it.ph) % 1
			-- X / Y0 / Z are where the builder put it: base is that spot wherever the map now stands (a 1v1 slot)
			local home = (it.base :: CFrame).Position
			local y = if a.Up then home.Y + u * a.Span else home.Y + a.Span * (1 - u)
			local wf, wa = a.WobbleF or 0, a.WobbleA or 0
			local s = (a.Scale or 1) * math.max(0.02, math.min(1, math.sin(math.pi * u) * 3))
			part.Size = (it.size :: Vector3) * s
			part.CFrame = CFrame.new(home.X + math.sin(t * wf + it.ph * 6) * wa, y, home.Z + math.cos(t * wf + it.ph * 6) * wa)
				* CFrame.Angles(((a.RotX or 0) * t) % TAU, ((a.RotY or 0) * t) % TAU, 0)
		elseif k == "Spark" then
			local part = inst :: BasePart
			local u = (t * it.sp + it.ph) % 1
			local s = math.sin(math.pi * u)
			local base = it.base :: CFrame
			part.Size = (it.size :: Vector3) * (0.4 + s)
			part.CFrame = CFrame.new(base.X, base.Y + u * 30, base.Z) * CFrame.Angles((t * 2) % TAU, (t * 3) % TAU, 0)
			part.Transparency = 1 - s
		elseif k == "Cloud" then
			local base = it.base :: CFrame
			-- his drift is around the map's corner; a 1v1 clone stands elsewhere, so shift the corner with it
			local corner = (a.CornerX or 0) + base.X - (a.BuildX or base.X)
			local localX = base.X - corner
			local x = (localX + it.sp * t + 900) % 1800 - 900
			local y = -math.cos(t * 0.3 + it.ph) * 0.8 / 0.3
			move(it.parts :: { BasePart }, it.cfs :: { CFrame }, CFrame.new(x - localX, y, 0))
		elseif k == "Pod" then
			local hid = it.hiddenUntil
			local hidden = hid ~= nil and t < hid
			if hidden ~= (it.hidden == true) then
				it.hidden = hidden
				local m = if hidden then 1 else 0
				for _, p in it.parts :: { BasePart } do
					p.LocalTransparencyModifier = m
				end
				if it.beam then
					it.beam.LocalTransparencyModifier = m
				end
			end
			local ring, ringSize = it.ring, it.ringSize
			if ring and ringSize then
				local u = (t * 0.8 + it.ph) % 1
				ring.Size = Vector3.new(ringSize.X * (1 + 1.3 * u), ringSize.Y, ringSize.Z * (1 + 1.3 * u))
				ring.Transparency = 1 - 0.85 * (1 - u)
			end
			if not hidden and it.base then
				if it.beam then
					it.beam.Transparency = 1 - (0.1 + 0.07 * math.sin(t * 3 + it.ph))
				end
				local ps = 1 -- his pop back: easeOutBack over 1 / 2.2 s
				if hid then
					local x = math.min(1, (t - hid) * 2.2)
					if x >= 1 then
						it.hiddenUntil = nil
					end
					local x1 = x - 1
					ps = 1 + 2.7 * x1 * x1 * x1 + 1.7 * x1 * x1
				end
				local q = math.sin(t * 4.4 + it.ph) * 0.1 + math.sin(t * 9.1 + it.ph) * 0.025
				local sxz, sy = ps * (1 + q), ps * (1 - q)
				local base = it.base :: CFrame
				local pivot = CFrame.new(base.Position + Vector3.new(0, math.sin(t * 2.2 + it.ph) * 0.35, 0))
					* CFrame.Angles(0, (t * 0.9) % TAU, 0)
					* CFrame.Angles(0, 0, math.sin(t * 1.7 + it.ph) * 0.08)
				local cfs, sizes = it.cfs :: { CFrame }, it.sizes :: { Vector3 }
				for i, p in it.parts :: { BasePart } do
					local cf = cfs[i]
					local o = cf.Position
					p.Size = scaledSize(cf, sizes[i], sxz, sy)
					table.insert(moveParts, p)
					table.insert(moveCFrames, pivot * CFrame.new(o.X * sxz, o.Y * sy, o.Z * sxz) * cf.Rotation)
				end
			end
		end
	end
	if #moveParts > 0 then
		Workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- Squish Pods: his updateShards (:947-950): gravity 38, spin, shrink after 55% of the life.
local function stepShards(dt: number)
	for i = #shards, 1, -1 do
		local s = shards[i]
		s.life += dt
		s.v -= Vector3.new(0, 38 * dt, 0)
		local cf = s.part.CFrame
		local nextCf = CFrame.new(cf.Position + s.v * dt) * cf.Rotation * CFrame.Angles(s.av.X * dt, s.av.Y * dt, s.av.Z * dt)
		local k = s.life / s.max
		local scale = if k > 0.55 then math.max(0.001, 1 - (k - 0.55) / 0.45) else 1
		s.part.Size = s.size * scale
		s.part.CFrame = nextCf
		local hull = s.hull
		if hull then
			hull.Size = (s.size + Vector3.one * 0.2) * scale
			hull.CFrame = nextCf
		end
		if k >= 1 then
			s.part:Destroy()
			if hull then
				hull:Destroy()
			end
			table.remove(shards, i)
		end
	end
end

local function shardPart(size: Vector3, color: Color3, cf: CFrame, source: BasePart?): BasePart
	local part: BasePart = if source then source:Clone() else Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = color
	part.Size = size
	part.CFrame = cf
	part.Parent = Workspace.CurrentCamera -- this screen only
	return part
end

-- Public

function SkyMapFxController.start()
	for _, kind in KINDS do
		local tagName = PREFIX .. kind
		for _, inst in CollectionService:GetTagged(tagName) do
			add(kind, inst)
		end
		CollectionService:GetInstanceAddedSignal(tagName):Connect(function(inst)
			add(kind, inst)
		end)
		CollectionService:GetInstanceRemovedSignal(tagName):Connect(remove)
	end
	conn = RunService.RenderStepped:Connect(function(dt: number)
		local active = activeMap()
		if active then
			step(Workspace:GetServerTimeNow() - EPOCH, active)
		end
		if #shards > 0 then
			stepShards(dt)
		end
	end)
end

-- Squish Pods: `pod` was picked up (MatchController.syncPads): his shatter (:938-945, 18 cubes in the cake's, icing's
-- and knob's colours), then the cake and beam hide for `seconds` and pop back.
function SkyMapFxController.Collect(pod: Instance, seconds: number)
	local it = items[pod]
	if it == nil or it.kind ~= "Pod" or it.base == nil then
		return
	end
	it.hiddenUntil = Workspace:GetServerTimeNow() - EPOCH + math.max(seconds, 0)
	local gem = pod:FindFirstChild("Gem")
	local function colourOf(holder: Instance?, name: string, fallback: Color3): Color3
		local p = holder and holder:FindFirstChild(name, true)
		return if p and p:IsA("BasePart") then p.Color else fallback
	end
	local body = colourOf(gem, "body", WHITE)
	local cols = { body, colourOf(gem, "icing", WHITE), colourOf(pod, "PodKnob", body), Color3.fromHex("FFD23D"), body, body:Lerp(WHITE, 0.3) }
	local hulls = game:GetService("ReplicatedStorage"):FindFirstChild("SquishyOutlineMeshes")
	local hullBox = hulls and hulls:FindFirstChild("HullBox")
	local centre = (it.base :: CFrame).Position
	local rng = Random.new()
	for i = 1, 18 do
		local sz = rng:NextNumber(0.32, 0.7)
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1))
		dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.yAxis
		local cf = CFrame.new(centre + dir * rng:NextNumber(0.3, 1.4))
			* CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), rng:NextNumber(0, 3))
		local size = Vector3.one * sz
		local part = shardPart(size, cols[(i - 1) % #cols + 1], cf, nil)
		local hull = if hullBox and hullBox:IsA("BasePart") then shardPart(size + Vector3.one * 0.2, INK, cf, hullBox) else nil
		table.insert(shards, {
			part = part,
			hull = hull,
			v = dir * rng:NextNumber(8, 15) + Vector3.new(0, rng:NextNumber(6, 11), 0),
			av = Vector3.new(rng:NextNumber(-10, 10), rng:NextNumber(-10, 10), rng:NextNumber(-10, 10)),
			life = 0,
			max = rng:NextNumber(0.8, 1.2),
			size = size,
		})
	end
end

function SkyMapFxController.destroy()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	table.clear(items)
	table.clear(byMap)
	for _, s in shards do
		s.part:Destroy()
		if s.hull then
			s.hull:Destroy()
		end
	end
	table.clear(shards)
end

-- Studio / tests: how many items are tracked, by kind.
function SkyMapFxController.debugState(): { [string]: number }
	local counts: { [string]: number } = {}
	for _, it in items do
		counts[it.kind] = (counts[it.kind] or 0) + 1
	end
	return counts
end

return SkyMapFxController
