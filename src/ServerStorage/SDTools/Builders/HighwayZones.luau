--!strict
-- HighwayZones: builds Claude Design's highway v2 zones (owner 2026-10-23: "rebuild from Claude Design's sketches";
-- HighwayKit = the delivery's kit, ported 1:1) into the highway's biome Models: each zone's floor, walls and strips,
-- the ground and set dressing beyond the walls, every prop every 100 studs, the set pieces (volcanoes, the Golden
-- Gates), the light streams, the particles and the zone's light. Called by HighwayBuilder (edit time only); the deck,
-- the lane, the markers, the rings, the pads and the name arches stay HighwayBuilder's (Design: "kept as they are").
-- Design's rules (Highway Zones Spec v2, kit-build.js): the road is 120 between the wall faces (x +-60); nothing in
-- the flight tube (|x| < 18 below y 72); one Part per material: an asset's blocks of one material are unioned
-- (GeometryService, UsePartColor off keeps each block's colour), so a 60-block tree in Wood + LeafyGrass is 2 Parts;
-- the left-side copies are mirrored; Glass props are see-through (opacity 0.55), Glass floors and strips solid.
-- Readings: Design's y 0 (the road surface) is the highway's floor top, Y0 under the lane's foot; the ground beyond the
-- walls is Parts, not Terrain (owner 2026-10-23: snapshots do not save Terrain); the floors with Design's checker get
-- Lego studs too (owner 2026-10-23: "checkered pattern but with lego texture"); a particle's colours run over its
-- lifetime (one emitter per point, Design picks one per particle); Design's pyramids are 4 CornerWedges, its flat
-- outlines (islands, ponds) fans of wedge triangles.
-- Coordinates: x across the road (+ = right of the chase camera), y up, d along the road; lane-local CFrame
-- origin * CFrame.new(x, y + Y0, -d) (WorldLayout.highwayCFrame's frame).

local GeometryService = game:GetService("GeometryService")

local Prims = require(script.Parent.Parent.Kit.Prims)
local HighwayKit = require(script.Parent.HighwayKit)

local Core = HighwayKit.Core
type Part = typeof(Core.box("", 0, 0, 0, 0, 0, 0, "", ""))

export type Ctx = {
	origin: CFrame,
	newPiece: (piece: string, atomic: boolean, id: string?) -> Model,
	place: (model: Model, frame: CFrame, parent: Instance) -> (),
	checker: string?, -- the floors' checker Texture (AssetTable img.highway.floorChecker), nil = none
	textures: { [string]: string }, -- Config.Vfx.Textures
	warnings: { string },
}

-- Constants

local Y0 = -0.1 -- Design's road surface: the floor top, 0.1 under the lane's foot (y 0)
local SEG = 2048 -- Roblox's longest part (Design splits its long pieces there too)
local FAR = 900 -- Design's outside reach (kit-build.js:161, the full build)
local GLASS_SEE_THROUGH = 0.45 -- kit-build.js:25: Glass props at opacity 0.55
local CHECKER_TRANSPARENCY = 0.92 -- Spec v2: "black at Transparency 0.92"
local MAT_NEON, MAT_GLASS = "Neon", "Glass"
-- Roblox's Neon draws a colour far brighter than Design's renderer (pale Neon turns white: the rainbow lane, seen in
-- Studio 2026-10-23); a Neon part takes its colour this much toward black (Core.tone) to glow as Design's renders do.
local NEON_DIM = 0.35
local UNION_OPTIONS = { SplitApart = false, CollisionFidelity = Enum.CollisionFidelity.Box }
local GLOWY = { "Ember", "parkle", "Shimmer", "Star", "Glint" } -- kit-build.js:257: these particles glow
local Y_AXIS = CFrame.Angles(0, 0, math.pi / 2) -- a Cylinder's X axis onto Y
local Z_AXIS = CFrame.Angles(0, -math.pi / 2, 0) -- a Cylinder's X axis onto Z
local WEDGE_TURN = CFrame.Angles(0, math.pi / 2, 0) -- Design's wedge (right angle at +x, -y; along z) as a WedgePart
local QUARTERS = { { -1, 1, 0 }, { 1, 1, 90 }, { 1, -1, 180 }, { -1, -1, 270 } } -- a pyramid's CornerWedges

local HighwayZones = {}
HighwayZones.Core = Core

-- Private: helpers -----------------------------------------------------------------------------------------------

local function snake(name: string): string
	return (string.gsub(string.gsub(string.lower(name), "[^%w]+", "_"), "^_+", ""))
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

-- The colour a kit part of `hex` in material `mat` is given (Neon dimmed by NEON_DIM).
local function paint(hex: string, mat: string): Color3
	return Color3.fromHex(if mat == MAT_NEON then Core.tone(hex, -NEON_DIM) else hex)
end

-- A plain decor part of `class` (shadows off for Neon and Glass, kit-build.js:117).
local function newPart(class: string, name: string, size: Vector3, cf: CFrame, hex: string, mat: string): BasePart
	local p = Instance.new(class) :: BasePart
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = paint(hex, mat)
	p.Material = material(mat)
	p.Reflectance = 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = mat ~= MAT_NEON and mat ~= MAT_GLASS
	return p
end

-- `cf` reflected in its frame's x (x -> -x): the mirror of a shape that is symmetric about its own X axis.
local function mirror(cf: CFrame): CFrame
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	return CFrame.new(-x, y, z, r00, -r01, -r02, -r10, r11, r12, -r20, r21, r22)
end

-- A flat triangle a, b, c (asset-local points) `t` thick as two WedgeParts (HighwayBuilder.triangle's split).
local function triangle(out: { BasePart }, name: string, a: Vector3, b: Vector3, c: Vector3, t: number, hex: string, mat: string)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 1e-4 then
		return
	end
	table.insert(out, newPart("WedgePart", name, Vector3.new(t, height, math.abs(ab:Dot(back))), CFrame.fromMatrix((a + b) / 2, right, up, back), hex, mat))
	table.insert(out, newPart("WedgePart", name, Vector3.new(t, height, math.abs(ac:Dot(back))), CFrame.fromMatrix((a + c) / 2, -right, up, -back), hex, mat))
end

-- One kit part as Roblox parts in its asset's frame (Design's three.js frame: z = -d), mirrored when `flip`.
local function shape(p: Part, hex: string, flip: boolean): { BasePart }
	local out: { BasePart } = {}
	local r = p.r or { 0, 0, 0 }
	local frame = CFrame.new(p.at[1], p.at[2], -p.at[3]) * CFrame.Angles(math.rad(r[1]), math.rad(r[2]), math.rad(r[3]))
	local function put(class: string, size: Vector3, cf: CFrame)
		table.insert(out, newPart(class, p.n, size, if flip then mirror(cf) else cf, hex, p.m))
	end
	local d = p.d
	if p.s == "box" then
		put("Part", Vector3.new(d[1], d[2], d[3]), frame)
	elseif p.s == "ball" then
		put("Part", Vector3.new(d[1], d[1], d[1]), frame)
		;(out[#out] :: Part).Shape = Enum.PartType.Ball
	elseif p.s == "cyl" then
		put("Part", Vector3.new(d[2], d[1], d[1]), frame * (if p.axis == "y" then Y_AXIS elseif p.axis == "z" then Z_AXIS else CFrame.identity))
		;(out[#out] :: Part).Shape = Enum.PartType.Cylinder
	elseif p.s == "wedge" then
		put("WedgePart", Vector3.new(d[3], d[2], d[1]), frame * WEDGE_TURN)
	elseif p.s == "pyr" then
		local pf = if flip then mirror(frame) else frame
		local w, h, l = d[1], d[2], d[3]
		for _, q in QUARTERS do
			local size = if q[3] % 180 == 0 then Vector3.new(w / 2, h, l / 2) else Vector3.new(l / 2, h, w / 2)
			local cf = pf * CFrame.new(q[1] * w / 4, 0, q[2] * l / 4) * CFrame.Angles(0, math.rad(q[3]), 0)
			table.insert(out, newPart("CornerWedgePart", p.n, size, cf, hex, p.m))
		end
	else -- poly: a prism `d[1]` thick, its outline `pts` {x, d} around (at.x, at.d), centred at at.y
		local sx = if flip then -1 else 1
		local function point(q: { number }): Vector3
			return Vector3.new(sx * (p.at[1] + q[1]), p.at[2], -(p.at[3] + q[2]))
		end
		local centre = point({ 0, 0 })
		local pts = p.pts :: { { number } }
		for i = 1, #pts do
			triangle(out, p.n, centre, point(pts[i]), point(pts[i % #pts + 1]), d[1], hex, p.m)
		end
	end
	return out
end

-- The parts unioned by material (GeometryService; UsePartColor off keeps each block's colour); a single part, or a
-- failed union, stays as it is.
local function unionByMaterial(ctx: Ctx, label: string, parts: { BasePart }, seeThrough: boolean): { BasePart }
	local byMat: { [Enum.Material]: { BasePart } } = {}
	local order: { Enum.Material } = {}
	for _, p in parts do
		if not byMat[p.Material] then
			byMat[p.Material] = {}
			table.insert(order, p.Material)
		end
		table.insert(byMat[p.Material], p)
	end
	local out: { BasePart } = {}
	for _, mat in order do
		local list = byMat[mat]
		local result: BasePart = list[1]
		if #list > 1 then
			local rest = table.move(list, 2, #list, 1, {})
			local ok, made = pcall(function()
				return GeometryService:UnionAsync(list[1], rest, UNION_OPTIONS)
			end)
			if ok and typeof(made) == "table" and #made == 1 then
				result = made[1]
				for _, p in list do
					p:Destroy()
				end
				result.Anchored = true
				result.CanCollide = false
				result.CanQuery = false
				result.CanTouch = false
				;(result :: UnionOperation).UsePartColor = false
			else
				table.insert(ctx.warnings, string.format("highway v2: %s %s union failed (%s); kept %d parts", label, mat.Name, tostring(made), #list))
				table.move(list, 1, #list, #out + 1, out)
				continue
			end
		end
		result.Name = label .. " · " .. mat.Name
		result.Material = mat
		result.CastShadow = mat ~= Enum.Material.Neon and mat ~= Enum.Material.Glass
		if seeThrough and mat == Enum.Material.Glass then
			result.Transparency = GLASS_SEE_THROUGH
		end
		table.insert(out, result)
	end
	return out
end

-- Private: building ----------------------------------------------------------------------------------------------

type Builder = {
	ctx: Ctx,
	z: any,
	zone: Instance,
	templates: { [string]: { BasePart } },
}

local function lane(b: Builder, x: number, y: number, d: number): CFrame
	return b.ctx.origin * CFrame.new(x, y + Y0, -d)
end

-- An asset's template: its unioned parts in its own frame (mirrored or not, colours overridden), built once.
local function template(b: Builder, a: any, flip: boolean, colorFor: (any) -> string, key: string): { BasePart }
	local found = b.templates[key]
	if found then
		return found
	end
	local raw: { BasePart } = {}
	for _, p in a.parts do
		for _, part in shape(p, colorFor(p), flip) do
			table.insert(raw, part)
		end
	end
	local made = unionByMaterial(b.ctx, a.n, raw, true)
	b.templates[key] = made
	return made
end

-- One copy of `parts` (asset-frame templates) placed at lane-local (x, y, d) in a new Atomic piece.
local function instance(b: Builder, pieceName: string, parts: { BasePart }, x: number, y: number, d: number): Model
	local frame = lane(b, x, y, d)
	local model = b.ctx.newPiece(pieceName, true)
	for _, t in parts do
		local copy = t:Clone()
		copy.CFrame = frame * t.CFrame
		copy.Parent = model
	end
	b.ctx.place(model, frame, b.zone)
	return model
end

-- A long box w x h from d `a` to `b` (split at SEG) centred at (x, yc): Design's longBox.
local function longBox(out: { BasePart }, b: Builder, name: string, mat: string, hex: string, w: number, h: number, x: number, yc: number)
	local z = b.z
	local s = z.from
	while s < z.to do
		local e = math.min(z.to, s + SEG)
		table.insert(out, newPart("Part", name, Vector3.new(w, h, e - s), lane(b, x, yc, (s + e) / 2), hex, mat))
		s = e
	end
end

-- A long wedge whose right angle is at (x1, y0): its upright side at x1, its slope from (x0, y0) up to (x1, y1).
local function longWedge(out: { BasePart }, b: Builder, name: string, mat: string, hex: string, x0: number, x1: number, y0: number, y1: number)
	local z = b.z
	local turn = CFrame.Angles(0, if x1 > x0 then math.pi / 2 else -math.pi / 2, 0)
	local s = z.from
	while s < z.to do
		local e = math.min(z.to, s + SEG)
		local cf = lane(b, (x0 + x1) / 2, (y0 + y1) / 2, (s + e) / 2) * turn
		table.insert(out, newPart("WedgePart", name, Vector3.new(e - s, y1 - y0, math.abs(x1 - x0)), cf, hex, mat))
		s = e
	end
end

-- Lego studs and Design's checker on a floor's top (owner 2026-10-23). Plastic: Design's floor materials (Grass,
-- Sand, Snow...) hide Roblox's studs (seen in Studio 2026-10-23); the floor keeps Design's colour.
local function legoChecker(b: Builder, floor: BasePart, cell: number)
	floor.Material = Enum.Material.Plastic
	floor.TopSurface = Enum.SurfaceType.Studs
	local id = b.ctx.checker
	if id == nil then
		return
	end
	local tex = Instance.new("Texture")
	tex.Name = "Checker"
	tex.Face = Enum.NormalId.Top
	tex.Texture = id
	tex.StudsPerTileU = 2 * cell
	tex.StudsPerTileV = 2 * cell
	tex.Transparency = CHECKER_TRANSPARENCY
	tex.Parent = floor
end

-- The zone's floor, strips, walls (tiers, a piece per side) and outside (Design's buildZonePart + outside()).
local function buildShell(b: Builder)
	local z = b.z
	local floorPiece = b.ctx.newPiece("zone_floor", true)
	local floors: { BasePart } = {}
	longBox(floors, b, z.floor.n, z.floor.m, z.floor.c, z.floor.w, z.floor.th or 2, 0, -(z.floor.th or 2) / 2)
	for _, f in floors do
		if z.floor.checker then
			legoChecker(b, f, z.floor.checker)
		end
		f.Parent = floorPiece
	end
	for _, st in z.strips do
		local parts = {}
		for _, sd in if st.sym then { -1, 1 } else { 1 } do
			longBox(parts, b, st.n, st.m, st.c, st.x1 - st.x0, st.y1 - st.y0, sd * (st.x0 + st.x1) / 2, (st.y0 + st.y1) / 2)
		end
		for _, p in parts do
			p.Parent = floorPiece
		end
	end
	b.ctx.place(floorPiece, lane(b, 0, 0, z.from), b.zone)

	for _, sd in { -1, 1 } do
		local wallPiece = b.ctx.newPiece("zone_wall", true)
		local byUnion: { [string]: { BasePart } } = {}
		local loose: { BasePart } = {}
		for _, t in z.tiers do
			local parts = {}
			local over = t.over or 0
			local inner = Core.ROAD.inner + (t.inset or 0) - over
			if t.slope then
				longWedge(parts, b, t.n, t.m, t.c, sd * inner, sd * (inner + t.slope), t.y0, t.y1)
				longBox(parts, b, t.n, t.m, t.c, t.thick, t.y1 - t.y0, sd * (inner + t.slope + t.thick / 2), (t.y0 + t.y1) / 2)
			else
				local w = t.thick + 2 * over
				longBox(parts, b, t.n, t.m, t.c, w, t.y1 - t.y0, sd * (inner + w / 2), (t.y0 + t.y1) / 2)
			end
			if t.u then
				byUnion[t.u] = byUnion[t.u] or {}
				table.move(parts, 1, #parts, #byUnion[t.u] + 1, byUnion[t.u])
			else
				table.move(parts, 1, #parts, #loose + 1, loose)
			end
		end
		for key, parts in byUnion do
			-- Each SEG-long run is its own union (a union is one Part, at most SEG long).
			local runs: { [number]: { BasePart } } = {}
			for _, p in parts do
				local k = math.floor(p.Position.Z * 1000 + 0.5)
				runs[k] = runs[k] or {}
				table.insert(runs[k], p)
			end
			for _, run in runs do
				for _, made in unionByMaterial(b.ctx, z.name .. " " .. key, run, false) do
					made.Parent = wallPiece
				end
			end
		end
		for _, p in loose do
			p.Parent = wallPiece
		end
		b.ctx.place(wallPiece, lane(b, sd * Core.ROAD.inner, 0, z.from), b.zone)
	end

	local o = z.outside
	if o == nil then
		return
	end
	local outPiece = b.ctx.newPiece("zone_outside", true)
	local parts: { BasePart } = {}
	local r = Core.rng(z.id * 7919 + z.from)
	if o.ground then
		-- A ground at the floor's height starts at the floor's edge (Design's 66 runs 2 studs into the 136 floor: the
		-- two flickered, Flicker_Test 2026-10-23).
		local from = if o.ground.y <= 0 then math.max(o.ground.from, z.floor.w / 2) else o.ground.from
		for _, sd in { -1, 1 } do
			longBox(parts, b, "Outside ground", o.ground.m, o.ground.c, FAR - from, 2, sd * (from + FAR) / 2, o.ground.y - 1)
		end
	end
	local function blob3(name: string, mat: string, hex: string, x: number, y: number, d: number, sx: number, sy: number, sz: number)
		local part = Prims.meshPart(name, Enum.MeshType.Sphere, Vector3.new(2 * sx, 2 * sy, 2 * sz), lane(b, x, y, d), Color3.fromHex(hex), "decor")
		part.Material = material(mat)
		table.insert(parts, part)
	end
	local function boxAt(mat: string, hex: string, w: number, h: number, l: number, x: number, y: number, d: number, rot: { number })
		local cf = lane(b, x, y, d) * CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
		table.insert(parts, newPart("Part", "Outside " .. string.lower(mat), Vector3.new(w, h, l), cf, hex, mat))
	end
	if o.hills then
		local d = z.from + r() * o.hills.every
		while d < z.to do
			for _, sd in { -1, 1 } do
				local s = o.hills.size * (0.6 + r() * 0.9)
				local x = sd * (o.ground.from + 10 + s * 1.05 + r() * math.max(10, FAR - o.ground.from - s * 1.4))
				blob3("Outside hill", o.hills.m, o.hills.c, x, o.ground.y - s * 0.08, d, s, s * (0.28 + r() * 0.16), s * 1.15)
			end
			d += o.hills.every * (0.7 + r() * 0.6)
		end
	end
	if o.peaks then
		local d = z.from + r() * 120
		while d < z.to do
			for _, sd in { -1, 1 } do
				local s = 70 + r() * 70
				local x = sd * (230 + r() * 240)
				local y = if o.ground then o.ground.y else 0
				for i = 0, 3 do
					local w, h = s * (1 - i * 0.22), s * 0.34
					boxAt(o.peaks.m, o.peaks.c, w, h, w, x, y + h / 2, d, { 0, i * 17, 0 })
					boxAt("Snow", o.peaks.cap, w * 0.82, 2.2, w * 0.82, x, y + h + 1, d, { 0, i * 17 + 9, 0 })
					y += h
				end
			end
			d += 150 + r() * 120
		end
	end
	if o.clouds then
		local d = z.from + r() * 30
		while d < z.to do
			for _, sd in { -1, 1 } do
				local s = o.clouds.size * (0.5 + r())
				local x = sd * (o.clouds.from + s * 1.02 + r() * math.max(10, FAR - o.clouds.from - s))
				blob3("Outside cloud", "Snow", o.clouds.c, x, o.clouds.y + r() * 10, d, s, s * 0.45, s * 0.8)
			end
			d += 34 + r() * 30
		end
	end
	if o.spires then
		local d = z.from + r() * 60
		while d < z.to do
			for _, sd in { -1, 1 } do
				local h = 40 + r() * 90
				local w = 8 + r() * 10
				local x = sd * (96 + r() * 300)
				local ry = r() * 90
				local rx = r() * 10 - 5
				local rz = r() * 10 - 5
				boxAt("Basalt", o.spires.c, w, h, w, x, h / 2 - 4, d, { rx, ry, rz })
				boxAt("Neon", o.spires.glow, w * 0.45, w * 0.45, w * 0.45, x, h - 3, d, { 45, 45, 45 })
			end
			d += 60 + r() * 70
		end
	end
	for _, p in parts do
		p.Parent = outPiece
	end
	b.ctx.place(outPiece, lane(b, 0, 0, z.from), b.zone)
end

-- Every prop every 100 studs (Design's placement loop: alt swaps sides on odd stretches, every skips stretches, c /
-- altC override colours by part name, cyc colours cycle by arch), then the set pieces.
local function buildProps(b: Builder)
	local z = b.z
	for s = 0, (z.to - z.from) // 100 - 1 do
		local ds = z.from + s * 100
		local odd = s % 2 == 1
		for _, a in z.props do
			for _, pl in a.pl do
				if pl.every and s % pl.every ~= 0 then
					continue
				end
				local x0 = if pl.alt and odd then -pl.x else pl.x
				local ov: { [string]: string } = table.clone(pl.c or {})
				if odd then
					for k, v in pl.altC or {} do
						ov[k] = v
					end
				end
				local hasCyc = false
				for _, q in a.parts do
					hasCyc = hasCyc or q.cyc ~= nil
				end
				local cyc = if hasCyc then (s // (pl.every or 1)) % 5 else 0
				local keys = {}
				for k, v in ov do
					table.insert(keys, k .. "=" .. v)
				end
				table.sort(keys)
				local flip = x0 < 0
				local key = string.format("%d:%s:%s:%s:%d", z.id, a.n, tostring(flip), table.concat(keys, ","), cyc)
				local parts = template(b, a, flip, function(q: any): string
					return ov[q.n] or (if q.cyc then q.cyc[cyc % #q.cyc + 1] else q.c)
				end, key)
				instance(b, snake(a.n), parts, x0, pl.y or 0, ds + pl.d)
			end
		end
	end
	for _, o in z.once or {} do
		for _, ps in o.pos do
			local flip = ps.x < 0
			local parts = template(b, o, flip, function(q: any): string
				return q.c
			end, string.format("%d:once:%s:%s", z.id, o.n, tostring(flip)))
			local model = instance(b, snake(o.n), parts, ps.x, 0, z.from + ps.d)
			for _, l in z.fx.lights do
				if l.where == "gateSlit" then
					-- Spec v2: a SurfaceLight on the gates' light slit, facing the road (toward the deck).
					local host = newPart("Part", "gate_light", Vector3.new(4, 110, 0.2), lane(b, ps.x, 55, z.from + ps.d - 2.1), "#FFFFFF", "SmoothPlastic")
					host.Transparency = 1
					host.CastShadow = false
					local light = Instance.new("SurfaceLight")
					light.Name = "L_gates"
					light.Face = Enum.NormalId.Back
					light.Color = Color3.fromHex(l.c)
					light.Range = l.range
					light.Brightness = l.brightness
					light.Shadows = false
					light.Parent = host
					host.Parent = model
				end
			end
		end
	end
end

-- Design's light streams (kit-build.js:289-299): jagged Neon runs along the water channels, a union per side per
-- stretch.
local function buildBeams(b: Builder)
	local z = b.z
	local r = Core.rng(z.id * 131)
	for _, bm in z.fx.beams or {} do
		for s = 0, (z.to - z.from) // 100 - 1 do
			for _, sd in if bm.sym then { -1, 1 } else { 1 } do
				local d0 = z.from + s * 100
				local d, x, y = d0, sd * bm.x, bm.y
				local raw: { BasePart } = {}
				while d < d0 + 100 do
					local L = 2 + r() * 4
					local nx = sd * bm.x + (r() - 0.5) * bm.jag
					local ny = bm.y + (r() - 0.5) * bm.jag * 0.6
					local dx, dy = nx - x, ny - y
					local len = math.sqrt(L * L + dx * dx + dy * dy)
					local rot = CFrame.Angles(-math.atan2(dy, L), math.atan2(dx, L), 0)
					table.insert(raw, newPart("Part", bm.n, Vector3.new(bm.w, bm.w, len), lane(b, (x + nx) / 2, (y + ny) / 2, d + L / 2) * rot, bm.c, MAT_NEON))
					x, y = nx, ny
					d += L
				end
				local piece = b.ctx.newPiece(snake(bm.n), true)
				for _, p in unionByMaterial(b.ctx, bm.n, raw, false) do
					p.Parent = piece
				end
				b.ctx.place(piece, lane(b, sd * bm.x, bm.y, d0), b.zone)
			end
		end
	end
end

-- Design's particles (Spec v2 "5 · Particles"): an emitter per point per stretch, on Attachments of one invisible
-- anchor part per zone.
local function buildParticles(b: Builder)
	local z = b.z
	if #z.fx.particles == 0 then
		return
	end
	local piece = b.ctx.newPiece("zone_fx", true)
	local anchorFrame = lane(b, 0, 0, z.from)
	local anchor = newPart("Part", "fx_anchor", Vector3.new(1, 1, 1), anchorFrame, "#FFFFFF", "SmoothPlastic")
	anchor.Transparency = 1
	anchor.CastShadow = false
	for _, p in z.fx.particles do
		local glow = false
		for _, word in GLOWY do
			glow = glow or string.find(p.kind, word, 1, true) ~= nil
		end
		local keys = {}
		for i, c in p.cols do
			table.insert(keys, ColorSequenceKeypoint.new(if #p.cols == 1 then 0 else (i - 1) / (#p.cols - 1), Color3.fromHex(c)))
		end
		if #keys == 1 then
			table.insert(keys, ColorSequenceKeypoint.new(1, keys[1].Value))
		end
		local mid, env = (p.size[1] + p.size[2]) / 2, (p.size[2] - p.size[1]) / 2
		for s = 0, (z.to - z.from) // 100 - 1 do
			for _, e in p.em do
				local flip = e.alt and s % 2 == 1
				local at = Instance.new("Attachment")
				at.Name = snake(p.kind)
				at.CFrame = anchorFrame:ToObjectSpace(lane(b, if flip then -e.x else e.x, e.y, z.from + s * 100 + e.d))
				if p.dir == "down" then
					at.CFrame *= CFrame.Angles(0, 0, math.pi) -- turned over: emits downward
				end
				local em = Instance.new("ParticleEmitter")
				em.Name = p.kind
				em.Texture = if p.kind == "Smoke" then b.ctx.textures.smoke else b.ctx.textures.sparkles
				em.Color = ColorSequence.new(keys)
				em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, mid, env), NumberSequenceKeypoint.new(1, mid, env) })
				em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.75, 0.25), NumberSequenceKeypoint.new(1, 1) })
				em.Lifetime = NumberRange.new(p.life * 0.8, p.life)
				em.Rate = p.rate
				em.Speed = NumberRange.new(p.speed, p.speed * 1.6)
				em.SpreadAngle = if p.dir == "burst" then Vector2.new(180, 180) elseif p.dir == "down" then Vector2.new(40, 40) else Vector2.new(15, 15)
				em.LightEmission = if glow then 1 else 0
				em.LightInfluence = if glow then 0 else 1
				em.Parent = at
				at.Parent = anchor
			end
		end
	end
	anchor.Parent = piece
	b.ctx.place(piece, anchorFrame, b.zone)
end

-- Public ---------------------------------------------------------------------------------------------------------

-- The colour of a kit part of `hex` in material `mat` (Neon dimmed to glow like Design's renders).
HighwayZones.paint = paint

-- The kit's 7 zones from Art/Palette (HighwayKit.zones).
function HighwayZones.zones(palette: any): { any }
	return HighwayKit.zones(palette)
end

-- Builds kit zone `z` into `zone` (its biome Model). Yields (GeometryService unions).
function HighwayZones.dress(ctx: Ctx, z: any, zone: Instance)
	local b: Builder = { ctx = ctx, z = z, zone = zone, templates = {} }
	buildShell(b)
	buildProps(b)
	buildBeams(b)
	buildParticles(b)
	for _, list in b.templates do
		for _, t in list do
			t:Destroy()
		end
	end
end

-- Parts inside the flight tube, per zone (HighwayKit.Core.tubeHits): always empty.
function HighwayZones.tubeHits(z: any): { string }
	return Core.tubeHits(z)
end

return HighwayZones
