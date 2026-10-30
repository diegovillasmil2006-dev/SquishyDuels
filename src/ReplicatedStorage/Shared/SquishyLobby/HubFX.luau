--!nonstrict
-- HubFX: client-side animation + effects for the Squishy Duels hub props, portals and practice arena.
-- Evaluates the same specs as the design preview (HubFXSpec.luau is generated from hubprops.js).
-- Start it from a LocalScript:  require(ReplicatedStorage.SquishyLobby.HubFX).start(workspace.SquishyDuelsLobby)
-- Everything is anchored and moved locally with BulkMoveTo, so it costs no network traffic.
-- Time comes from workspace:GetServerTimeNow(), so every client (and the server, for hit checks) agrees.
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Spec = require(script.Parent.HubFXSpec) -- @require

local HubFX = {}
HubFX.EPOCH = 1.7e9
HubFX.CullDistance = 450
HubFX.Textures = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	soft = "rbxasset://textures/particles/smoke_main.dds",
	heart = "rbxasset://textures/particles/sparkles_main.dds", -- swap for an uploaded heart decal id
}

local TAU = math.pi * 2
local boost, waves = {}, {}
-- Portal copies placed outside the lobby (e.g. the LobbyPortal on the highway): tag the Model with CLONE_TAG and
-- set its "Source" attribute to the spec path it was copied from (default "Hub/HighwayPortal"). It then gets the
-- same animation, bulb chase and portal effects as the original.
HubFX.CLONE_TAG = "SquishyPortalClone"
local function clones()
	local out = {}
	for _, m in CollectionService:GetTagged(HubFX.CLONE_TAG) do
		if m:IsA("Model") then
			local src = string.split(m:GetAttribute("Source") or "Hub/HighwayPortal", "/")
			table.insert(out, { model = m, src = src })
		end
	end
	return out
end
-- spec path -> instance inside a clone (nil if the path isn't under the clone's source)
local function inClone(cl, path)
	for i, n in cl.src do if path[i] ~= n then return nil end end
	local o = cl.model
	for i = #cl.src + 1, #path do o = o and o:FindFirstChild(path[i]) end
	return o
end
local function frac(x) return x - math.floor(x) end
local function hex(h) return Color3.fromHex(h) end

function HubFX.now() return workspace:GetServerTimeNow() - HubFX.EPOCH end
function HubFX.setPortalBoost(name, v) boost[name] = v end
-- One-shot shockwave from a portal ("Portal" or "ReturnPortal"); the cinematic calls this on enter/arrive.
function HubFX.portalWave(name) waves[name] = os.clock() end
local function trailingNumber(s) return tonumber(string.match(s, "(%d+)$")) or 0 end
local function axisScale(a, s) return math.sqrt((a.X * s.X) ^ 2 + (a.Y * s.Y) ^ 2 + (a.Z * s.Z) ^ 2) end

function HubFX.eval(a, t)
	local dx, dy, dz, rx, ry, rz, sx, sy, sz = 0, 0, 0, 0, 0, 0, 1, 1, 1
	local function w(p, ph) return math.sin(TAU * (t / p + (ph or 0))) end
	if a.bob then dy += a.bob[1] * w(a.bob[2], a.bob[3]) end
	-- Game fix (2026-10-30): t is ~9e7 s since EPOCH, and CFrame angles are float32, so a raw spin * t jumps in 2+ rad
	-- steps; wrapping it to one turn (in double precision) keeps the same smooth motion on every client and the server.
	if a.spin then ry += (a.spin * t) % TAU end
	if a.spinZ then rz += (a.spinZ * t) % TAU end
	if a.sway then ry += a.sway[1] * w(a.sway[2], a.sway[3]) end
	if a.flap then ry += a.flap[3] * a.flap[1] * w(a.flap[2]) end
	if a.slideX then dx += a.slideX[1] * w(a.slideX[2], a.slideX[3]) end
	if a.squish then
		local s = a.squish[1] * w(a.squish[2], a.squish[3])
		sy *= 1 - s; sx *= 1 + s * 0.8; sz *= 1 + s * 0.8
	end
	if a.hop then
		local h, every, dur, ph = a.hop[1], a.hop[2], a.hop[3], a.hop[4] or 0
		local c = frac(t / every + ph) * every
		if c < dur then
			local u = c / dur
			dy += h * math.sin(math.pi * u)
			ry += 0.35 * math.sin(3 * math.pi * u) * (1 - u)
		end
	end
	if a.popup then
		local c = frac(t / a.popup[1] + (a.popup[2] or 0))
		local k = 0
		if c >= 0.6 and c < 0.68 then k = ((c - 0.6) / 0.08) ^ 2
		elseif c >= 0.68 and c < 0.88 then k = 1
		elseif c >= 0.88 then local u = (c - 0.88) / 0.12; k = 1 - u * u * (3 - 2 * u) end
		rx -= 1.4 * k
	end
	if a.kf then
		local c = frac(t / a.kf[1] + a.kf[2])
		for key, keys in a.kf[3] do
			local v = HubFX.track(keys, c)
			if key == "shake" then rz += v * math.sin(t * 47); rx += v * 0.6 * math.sin(t * 39 + 1)
			elseif key == "dx" then dx += v elseif key == "dy" then dy += v elseif key == "dz" then dz += v
			elseif key == "rx" then rx += v elseif key == "ry" then ry += v elseif key == "rz" then rz += v
			elseif key == "sx" then sx *= v elseif key == "sy" then sy *= v elseif key == "sz" then sz *= v end
		end
	end
	if a.blink then
		local c = frac(t / a.blink[1] + (a.blink[2] or 0)) * a.blink[1]
		if c < 0.16 then sy *= 1 - 0.88 * math.sin(math.pi * c / 0.16) end
	end
	return dx, dy, dz, rx, ry, rz, sx, sy, sz
end

local EASE = {
	lin = function(u) return u end, ["in"] = function(u) return u * u * u end, out = function(u) return 1 - (1 - u) ^ 3 end,
	io = function(u) return u < 0.5 and 4 * u * u * u or 1 - (-2 * u + 2) ^ 3 / 2 end,
	back = function(u) return 1 + 2.70158 * (u - 1) ^ 3 + 1.70158 * (u - 1) ^ 2 end,
	bounce = function(u)
		local n, d = 7.5625, 2.75
		if u < 1 / d then return n * u * u elseif u < 2 / d then u -= 1.5 / d; return n * u * u + 0.75
		elseif u < 2.5 / d then u -= 2.25 / d; return n * u * u + 0.9375 end
		u -= 2.625 / d; return n * u * u + 0.984375
	end,
}
-- keyframe track: { {time 0..1, value, ease}, ... } (same as kfTrack in hubprops.js)
function HubFX.track(keys, c)
	if c <= keys[1][1] then return keys[1][2] end
	for i = 2, #keys do
		local k1 = keys[i]
		if c <= k1[1] then
			local k0 = keys[i - 1]
			local u = k1[1] > k0[1] and (c - k0[1]) / (k1[1] - k0[1]) or 1
			return k0[2] + (k1[2] - k0[2]) * EASE[k1[3] or "io"](u)
		end
	end
	return keys[#keys][2]
end

function HubFX.hopAmount(a, t)
	local every, dur, ph = a.hop[2], a.hop[3], a.hop[4] or 0
	local c = frac(t / every + ph) * every
	return c < dur and math.sin(math.pi * c / dur) or 0
end

function HubFX.resolve(root, path)
	local o = root
	for _, n in path do o = o and o:FindFirstChild(n) end
	return o
end
local resolve = HubFX.resolve

function HubFX.findSpec(pathStr)
	for _, a in Spec.Anim do if table.concat(a.path, "/") == pathStr then return a end end
	return nil
end

-- World CFrame of an animated model at time t (server-side hit validation, no instances touched).
function HubFX.cframeAt(lobby, model, t)
	local chain = {}
	local m = model
	while m and m ~= lobby do
		local pv = m:FindFirstChild("Pivot")
		if pv then
			local p = {}
			local o = m
			while o and o ~= lobby do table.insert(p, 1, o.Name); o = o.Parent end
			local a = HubFX.findSpec(table.concat(p, "/"))
			if a then table.insert(chain, 1, { a = a, rest = pv.CFrame }) end
		end
		m = m.Parent
	end
	local cf, prevRest = CFrame.identity, nil
	for _, c in chain do
		local rel = prevRest and prevRest:ToObjectSpace(c.rest) or c.rest
		local dx, dy, dz, rx, ry, rz = HubFX.eval(c.a, t)
		cf = cf * rel * CFrame.new(dx, dy, dz) * CFrame.fromEulerAnglesYXZ(rx, ry, rz)
		prevRest = c.rest
	end
	return cf
end

---------------------------------------------------------------- effect helpers
local fxFolder
local function fxPart(cf, size, props)
	local p = Instance.new("Part")
	p.Name = "FX"; p.Anchored = true; p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
	p.Transparency = 1; p.Size = size; p.CFrame = cf
	if props then for k, v in props do p[k] = v end end
	p.Parent = fxFolder
	return p
end
local function emitter(parent, o)
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.texture or HubFX.Textures.sparkle
	e.Color = ColorSequence.new(o.color or Color3.new(1, 1, 1), o.color2 or o.color or Color3.new(1, 1, 1))
	e.LightEmission = o.light or 1
	local s = o.size or 0.6
	e.Size = o.sizeSeq or NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, s), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(o.alpha or 0.1, 1)
	e.Lifetime = NumberRange.new(o.life or 1.2, (o.life or 1.2) * 1.4)
	e.Rate = o.rate or 20
	e.Speed = NumberRange.new(o.speed or 1)
	e.SpreadAngle = o.spread or Vector2.new(180, 180)
	e.Acceleration = o.accel or Vector3.zero
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-90, 90)
	if o.shape then e.Shape = o.shape end
	if o.inOut then e.ShapeInOut = o.inOut end
	if o.style then e.ShapeStyle = o.style end
	if o.dir then e.EmissionDirection = o.dir end
	if o.orient then e.Orientation = o.orient end
	if o.drag then e.Drag = o.drag end
	e.Parent = parent
	return e
end
local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color; l.Range = range; l.Brightness = brightness; l.Shadows = false
	l.Parent = parent
	return l
end
local function marker(model, name)
	local m = model and model:FindFirstChild("Markers")
	return m and m:FindFirstChild(name)
end

local function buildEffects(lobby, effects)
	-- Mystery box: sparkles, lid-pop burst + light column
	local box = resolve(lobby, { "Hub", "MysteryBox" })
	local bc = marker(box, "BoxCenter")
	if bc then
		local cf = bc.CFrame
		emitter(fxPart(cf, Vector3.new(16, 14, 16)), { color = hex("ff5cc8"), color2 = hex("ffe14d"), size = 0.7, rate = 14, speed = 0.5, life = 2, accel = Vector3.new(0, 1.5, 0) })
		local burst = emitter(fxPart(cf * CFrame.new(0, 5, 0), Vector3.new(4, 1, 4)), { color = hex("fff3a0"), color2 = hex("ff5cc8"), size = 1, rate = 0, speed = 18, life = 0.8, spread = Vector2.new(35, 35), dir = Enum.NormalId.Top, accel = Vector3.new(0, -25, 0) })
		local column = fxPart(cf * CFrame.new(0, 13, 0) * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(16, 6, 6), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = hex("ffe14d") })
		light(bc, hex("ff5cc8"), 24, 2)
		local lid = HubFX.findSpec("Hub/MysteryBox/Box/Lid")
		local wasOpen = false
		table.insert(effects, function(t)
			local h = 0
			if lid and lid.kf then h = math.clamp(HubFX.track(lid.kf[3].dy, frac(t / lid.kf[1] + lid.kf[2])) / 4.4, 0, 1)
			elseif lid and lid.hop then h = HubFX.hopAmount(lid, t) end
			column.Transparency = 1 - h * 0.55
			local open = h > 0.05
			if open and not wasOpen then burst:Emit(45) end
			wasOpen = open
		end)
	end

	-- Daily reward + shop coin + quest "!": sparkles and lights
	local dr = resolve(lobby, { "Hub", "DailyReward", "Gift" })
	if dr then
		local cf = dr:GetPivot()
		emitter(fxPart(cf * CFrame.new(0, 3, 0), Vector3.new(11, 9, 11)), { color = hex("ffe14d"), color2 = hex("3fd8ff"), size = 0.6, rate = 12, speed = 0.4, life = 2 })
		light(dr:FindFirstChild("Pivot") or dr.PrimaryPart, hex("ffd23f"), 18, 2)
	end
	local coin = resolve(lobby, { "Hub", "Shop", "Coin" })
	if coin then emitter(fxPart(coin:GetPivot(), Vector3.new(8, 6, 3)), { color = hex("fff1a8"), color2 = hex("ffd23f"), size = 0.6, rate = 8, speed = 0.6, life = 1.6, accel = Vector3.new(0, 2, 0) }) end
	local alert = resolve(lobby, { "Hub", "QuestBoard", "Alert" })
	if alert and alert:FindFirstChild("Pivot") then light(alert.Pivot, hex("ffe14d"), 16, 3) end

	-- Fountain: four arcing jets, overflow from the top bowl, ripples
	local fountain = resolve(lobby, { "Hub", "Fountain" })
	if fountain then
		local center = fountain:GetPivot().Position
		local poolTop = center.Y
		for _, d in fountain:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "Water" and d.Size.Y > 0.6 then poolTop = math.max(poolTop, d.Position.Y + d.Size.Y / 2) end
		end
		local spouts = fountain:FindFirstChild("Spouts")
		if spouts then
			for _, s in spouts:GetChildren() do
				if s:IsA("BasePart") and s.Material == Enum.Material.Neon then
					local from = s.Position + Vector3.new(0, 0.3, 0)
					local aim = Vector3.new(center.X, from.Y + 7, center.Z)
					emitter(fxPart(CFrame.lookAt(from, aim), Vector3.new(0.4, 0.4, 0.4)), { texture = HubFX.Textures.soft, color = hex("bff4ff"), color2 = hex("7fe6ff"), light = 0.5, size = 0.7, rate = 45, speed = 13, life = 0.9, spread = Vector2.new(3, 3), dir = Enum.NormalId.Front, accel = Vector3.new(0, -32, 0), alpha = 0.2 })
				end
			end
		end
		local top = resolve(fountain, { "Topper" })
		if top then
			emitter(fxPart(CFrame.new(center.X, top:GetPivot().Y - 0.2, center.Z), Vector3.new(3.4, 0.2, 3.4)), { texture = HubFX.Textures.soft, color = hex("bff4ff"), light = 0.4, size = 0.5, rate = 30, speed = 2, life = 0.8, accel = Vector3.new(0, -14, 0), alpha = 0.3 })
		end
		emitter(fxPart(CFrame.new(center.X, poolTop + 0.05, center.Z), Vector3.new(8, 0.1, 8)), {
			texture = HubFX.Textures.soft, color = hex("e6fbff"), light = 0.3, rate = 1.2, speed = 0.01, life = 2.4, dir = Enum.NormalId.Top,
			orient = Enum.ParticleOrientation.VelocityPerpendicular, alpha = 0.55,
			sizeSeq = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 6) }),
		})
	end

	-- Kitty Bread: hearts
	local kitty = resolve(lobby, { "Hub", "KittyBread", "Kitty" })
	if kitty then
		emitter(fxPart(kitty:GetPivot() * CFrame.new(0, 12, 2), Vector3.new(14, 1, 6)), { texture = HubFX.Textures.heart, color = hex("ff5c9e"), color2 = hex("ffb3d1"), size = 1.4, rate = 3, speed = 2.5, life = 3.5, dir = Enum.NormalId.Top, spread = Vector2.new(15, 15) })
	end

	-- Squish Square: four swaying sky beams + sparkles round the statue
	local mon = resolve(lobby, { "Hub", "Monument" })
	if mon then
		local base = mon:GetPivot().Position
		local beams = {}
		for k, c in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
			local p0 = fxPart(CFrame.new(base + Vector3.new(c[1] * 10, 2, c[2] * 10)), Vector3.one)
			local p1 = fxPart(CFrame.new(base + Vector3.new(c[1] * 22, 60, c[2] * 22)), Vector3.one)
			local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
			a0.Parent = p0; a1.Parent = p1
			local b = Instance.new("Beam")
			b.Attachment0 = a0; b.Attachment1 = a1; b.FaceCamera = true; b.LightEmission = 1; b.Segments = 1
			b.Width0 = 3; b.Width1 = 9
			b.Color = ColorSequence.new(k % 2 == 1 and hex("ff5cc8") or hex("3fd8ff"))
			b.Transparency = NumberSequence.new(0.55, 1)
			b.Parent = p0
			table.insert(beams, { p1 = p1, c = c, k = k })
		end
		table.insert(effects, function(t)
			for _, q in beams do
				local lean = 0.22 + 0.1 * math.sin(t * 0.7 + q.k * 1.6)
				q.p1.CFrame = CFrame.new(base + Vector3.new(q.c[1] * (10 + 42 * lean), 60, q.c[2] * (10 + 42 * lean)))
			end
		end)
		local top = marker(mon, "StatueTop")
		if top then emitter(fxPart(top.CFrame * CFrame.new(0, -6, 0), Vector3.new(18, 18, 18)), { color = hex("3fd8ff"), color2 = hex("ff5cc8"), size = 0.8, rate = 16, speed = 0.4, life = 2.2 }) end
	end

	-- Portals: inward particle pull, rotating spiral arms, shockwave rings, light. Speeds up with setPortalBoost().
	local portalFx = { { path = { "Hub", "Portal" }, a = hex("c64dff"), b = hex("ff5cc8") }, { path = { "PracticeArena", "ReturnPortal" }, a = hex("3fd8ff"), b = hex("7dffea") }, { path = { "Hub", "HighwayPortal" }, a = hex("ff9a3c"), b = hex("ffe14d") } }
	for _, cl in clones() do
		local srcKey = table.concat(cl.src, "/")
		for _, ps in table.clone(portalFx) do
			if table.concat(ps.path, "/") == srcKey then table.insert(portalFx, { model = cl.model, a = ps.a, b = ps.b }) end
		end
	end
	for _, ps in portalFx do
		local pm = ps.model or resolve(lobby, ps.path)
		local c = marker(pm, "PortalCenter")
		if c then
			local cf, key = c.CFrame, pm.Name
			boost[key] = boost[key] or 1
			local suck = emitter(fxPart(cf, Vector3.new(14, 14, 1)), {
				color = ps.b, color2 = Color3.new(1, 1, 1), size = 0.5, rate = 60, speed = 7, life = 1,
				shape = Enum.ParticleEmitterShape.Sphere, inOut = Enum.ParticleEmitterShapeInOut.Inward, style = Enum.ParticleEmitterShapeStyle.Surface,
			})
			local pl = light(c, ps.a, 30, 2.5)
			-- three spiral arms of neon beads (log spiral), both faces
			local beads = {}
			for arm = 0, 2 do
				for k = 1, 8 do
					local u = k / 8
					for _, side in { 1, -1 } do
						local d = 0.35 + u * 0.55
						local p = fxPart(cf, Vector3.new(d, d, d), { Shape = Enum.PartType.Ball, Transparency = 0.1 + u * 0.35, Material = Enum.Material.Neon, Color = ps.a:Lerp(ps.b, u) })
						table.insert(beads, { p = p, r = 0.8 + u * 5.6, a = arm * TAU / 3 + u * 2.6, z = side * 0.45 })
					end
				end
			end
			-- shockwave rings: thin neon discs in the portal plane that grow and fade
			local rings = {}
			for k = 1, 3 do
				table.insert(rings, fxPart(cf, Vector3.new(0.05, 1, 1), { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = ps.b, Transparency = 1 }))
			end
			local phase, lastT = 0, nil
			local parts, cfs = {}, {}
			local face = cf * CFrame.Angles(0, math.pi / 2, 0) -- cylinder axis (X) along the portal normal
			table.insert(effects, function(t, cp)
				local dt = lastT and math.clamp(t - lastT, 0, 0.1) or 0
				lastT = t
				local b = boost[key] or 1
				phase += dt * b
				if (cf.Position - cp).Magnitude > HubFX.CullDistance then return end
				table.clear(parts); table.clear(cfs)
				for _, q in beads do
					local a = q.a - phase * 1.6
					table.insert(parts, q.p)
					table.insert(cfs, cf * CFrame.new(math.cos(a) * q.r, math.sin(a) * q.r, q.z))
				end
				workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
				local shot = waves[key] and (os.clock() - waves[key]) / 0.9 or 2
				for k, r in rings do
					local u, size, alpha
					if k == 3 and shot >= 0 and shot < 1 then
						u = shot; size = 4 + (1 - (1 - u) ^ 3) * 26; alpha = u
					else
						u = frac(phase / 1.6 + k / 3); size = 13.8 + u * 11; alpha = 0.55 + 0.45 * u
					end
					r.Size = Vector3.new(0.05, size, size)
					r.CFrame = face * CFrame.new(-0.5 - k * 0.02, 0, 0)
					r.Transparency = math.clamp(alpha, 0, 1)
				end
				suck.Rate = 60 * b
				pl.Brightness = 2 + b * 0.5
			end)
		end
	end

	-- Practice arena: burst when a target's HitAt attribute changes (set by PracticeRange.registerHit)
	local arena = lobby:FindFirstChild("PracticeArena")
	if arena then
		local bp = fxPart(CFrame.new(arena:GetPivot().Position), Vector3.new(2, 2, 2))
		local hitBurst = emitter(bp, { color = hex("ffe14d"), color2 = hex("ff5cc8"), size = 0.9, rate = 0, speed = 14, life = 0.6, accel = Vector3.new(0, -20, 0), drag = 3 })
		for _, m in arena:GetDescendants() do
			if m:IsA("Model") and (string.match(m.Name, "^Target_") or string.match(m.Name, "^Dummy_")) then
				m:GetAttributeChangedSignal("HitAt"):Connect(function()
					local cf, size = m:GetBoundingBox()
					bp.CFrame = cf * CFrame.new(0, size.Y * 0.2, 0)
					hitBurst:Emit(40)
				end)
			end
		end
	end
end

---------------------------------------------------------------- start
function HubFX.start(lobby)
	assert(RunService:IsClient(), "HubFX.start runs on the client (LocalScript)")
	if HubFX._conn then HubFX._conn:Disconnect() end
	if fxFolder then fxFolder:Destroy() end
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "SquishyLobbyFX"
	fxFolder.Parent = workspace

	local nodes, byModel = {}, {}
	for _, a in Spec.Anim do
		local m = resolve(lobby, a.path)
		if m and m:IsA("Model") then
			local pv = m:FindFirstChild("Pivot")
			local n = { a = a, model = m, rest = pv and pv.CFrame or m:GetPivot(), scaled = (a.squish ~= nil) or (a.blink ~= nil) }
			n.cf, n.scale = n.rest, Vector3.one
			table.insert(nodes, n)
			byModel[m] = n
		else
			warn("[HubFX] missing animated model " .. table.concat(a.path, "."))
		end
	end
	local cloneList = clones()
	for _, cl in cloneList do
		for _, a in Spec.Anim do
			local m = inClone(cl, a.path)
			if m and m:IsA("Model") then
				local pv = m:FindFirstChild("Pivot")
				local n = { a = a, model = m, rest = pv and pv.CFrame or m:GetPivot(), scaled = (a.squish ~= nil) or (a.blink ~= nil) }
				n.cf, n.scale = n.rest, Vector3.one
				table.insert(nodes, n)
				byModel[m] = n
			end
		end
	end
	for _, n in nodes do
		local p = n.model.Parent
		while p and p ~= lobby and not byModel[p] do p = p.Parent end
		n.parent = (p and byModel[p]) or nil
		n.rel = n.parent and n.parent.rest:ToObjectSpace(n.rest) or n.rest
		n.parts, n.offsets, n.sizes, n.axes = {}, {}, {}, {}
		for _, d in n.model:GetDescendants() do
			if d:IsA("BasePart") then
				local o = d.Parent
				while o ~= n.model and not byModel[o] do o = o.Parent end
				if o == n.model then
					local off = n.rest:ToObjectSpace(d.CFrame)
					table.insert(n.parts, d)
					table.insert(n.offsets, off)
					table.insert(n.sizes, d.Size)
					table.insert(n.axes, { off.RightVector, off.UpVector, off.LookVector })
				end
			end
		end
	end
	local function depth(n) local d, p = 0, n.parent; while p do d += 1; p = p.parent end; return d end
	for _, n in nodes do
		n.depth = depth(n)
		local p, sc = n.parent, n.scaled
		while p do sc = sc or p.scaled; p = p.parent end
		n.scaledTree = sc
	end
	table.sort(nodes, function(x, y) return x.depth < y.depth end)

	local pulses = {}
	local pulseSrc = {}
	for _, P in Spec.Pulse do
		table.insert(pulseSrc, { P = P, f = resolve(lobby, P.path) })
		for _, cl in cloneList do local f = inClone(cl, P.path); if f then table.insert(pulseSrc, { P = P, f = f }) end end
	end
	for _, src in pulseSrc do
		local P, f = src.P, src.f
		if f then
			local parts = {}
			for _, c in f:GetChildren() do if c:IsA("BasePart") then table.insert(parts, c) end end
			table.sort(parts, function(x, y) return trailingNumber(x.Name) < trailingNumber(y.Name) end)
			local base, idx = {}, {}
			for i, p in parts do base[i] = p.Color; idx[i] = math.max(0, trailingNumber(p.Name) - 1) end
			table.insert(pulses, { P = P, parts = parts, base = base, idx = idx, last = -1, anchor = parts[1] and parts[1].Position or Vector3.zero })
		end
	end

	local effects = {}
	buildEffects(lobby, effects)

	-- black outlines: Highlights on the nearest outlined models (Roblox renders at most 31 at once)
	local outlineModels, pool = {}, {}
	for _, p in Spec.Outline or {} do local m = resolve(lobby, p); if m then table.insert(outlineModels, m) end end
	for i = 1, math.min(28, #outlineModels) do
		local h = Instance.new("Highlight")
		h.FillTransparency = 1; h.OutlineTransparency = 0; h.OutlineColor = Color3.fromHex("1c1326")
		h.DepthMode = Enum.HighlightDepthMode.Occluded; h.Parent = fxFolder
		pool[i] = h
	end
	-- the enclosure wall rings the camera, so distance sorting doesn't fit it: it gets its own permanent Highlight
	local enc = lobby:FindFirstChild("Enclosure")
	if enc then
		local h = Instance.new("Highlight")
		h.FillTransparency = 1; h.OutlineTransparency = 0; h.OutlineColor = Color3.fromHex("1c1326")
		h.DepthMode = Enum.HighlightDepthMode.Occluded; h.Adornee = enc; h.Parent = fxFolder
	end
	local lastOutline = 0
	table.insert(effects, function(t, cp)
		if os.clock() - lastOutline < 0.5 then return end
		lastOutline = os.clock()
		table.sort(outlineModels, function(a, b) return (a:GetPivot().Position - cp).Magnitude < (b:GetPivot().Position - cp).Magnitude end)
		for i, h in pool do
			local m = outlineModels[i]
			h.Adornee = (m and (m:GetPivot().Position - cp).Magnitude < HubFX.CullDistance) and m or nil
		end
	end)

	local cam = workspace.CurrentCamera
	local bulkParts, bulkCF = {}, {}
	HubFX._conn = RunService.RenderStepped:Connect(function()
		local t = HubFX.now()
		local cp = (workspace.CurrentCamera or cam).CFrame.Position
		table.clear(bulkParts); table.clear(bulkCF)
		for _, n in nodes do
			if (n.rest.Position - cp).Magnitude < HubFX.CullDistance then
				local dx, dy, dz, rx, ry, rz, sx, sy, sz = HubFX.eval(n.a, t)
				local hitAt = n.model:GetAttribute("HitAt")
				if hitAt then
					local u = (t - hitAt) / 0.9
					if u >= 0 and u < 1 then ry += TAU * 2 * (1 - (1 - u) ^ 3) end
				end
				local pcf, ps = CFrame.identity, Vector3.one
				if n.parent then pcf, ps = n.parent.cf, n.parent.scale end
				local cf = pcf * CFrame.new(n.rel.Position * ps) * n.rel.Rotation * CFrame.new(dx, dy, dz) * CFrame.fromEulerAnglesYXZ(rx, ry, rz)
				local s = ps * Vector3.new(sx, sy, sz)
				n.cf, n.scale = cf, s
				if n.scaledTree then
					for i, p in n.parts do
						local o = n.offsets[i]
						table.insert(bulkParts, p)
						table.insert(bulkCF, cf * CFrame.new(o.Position * s) * o.Rotation)
						local ax, sz = n.axes[i], n.sizes[i]
						p.Size = Vector3.new(sz.X * axisScale(ax[1], s), sz.Y * axisScale(ax[2], s), sz.Z * axisScale(ax[3], s))
					end
				else
					for i, p in n.parts do
						table.insert(bulkParts, p)
						table.insert(bulkCF, cf * n.offsets[i])
					end
				end
			end
		end
		if #bulkParts > 0 then workspace:BulkMoveTo(bulkParts, bulkCF, Enum.BulkMoveMode.FireCFrameChanged) end

		for _, q in pulses do
			if (q.anchor - cp).Magnitude < HubFX.CullDistance then
				local P = q.P
				if P.chase then
					local step = math.floor(t / P.chase[1])
					if step ~= q.last then
						q.last = step
						for i, p in q.parts do p.Color = ((step - q.idx[i]) % P.chase[2] == 0) and P.on or P.off end
					end
				elseif P.pulse then
					for i, p in q.parts do
						local w = 0.5 + 0.5 * math.sin(TAU * (t / P.pulse[1] - q.idx[i] * P.pulse[2]))
						p.Color = q.base[i]:Lerp(P.to, w * 0.6)
					end
				end
			end
		end

		for _, f in effects do f(t, cp) end
	end)
	return HubFX
end

return HubFX
