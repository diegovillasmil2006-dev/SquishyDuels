--!strict
-- KneadMesh_Test: the knead screen on a mesh body (a model slot's uploaded toy, SD_Shape "M"; Kitty Bread test
-- 2026-11-06). Server only (ServerStorage.UnitTest). Edit mode: StarterPlayerScripts.Client.Controllers.KneadController's
-- handle on a hand-made slot-style model with recording stand-ins for its engine-only surfaces (useDeps). Contract:
--   * the build reads the mesh for its quality (Shell.readMesh) and goes live with a shell of that mesh, its stored colours
--     and, with an outline part, the dark copy; no atlas is made or put on the shell; the wax stays off whatever args.wax
--     says; the second open of the same toy reads nothing;
--   * live, the body and its outline hide; a press moves the shell; a teardown shows them again;
--   * shareAnchors: a rider group's parts (an ear, its rim) take one anchor vertex, so they never slip apart under a dent;
--     a rider with no section keeps its own, and so do an old toy's riders;
--   * a mesh that cannot be read, a second shell part, an outline no bigger than the body or a mesh over the quality's
--     budget end the knead with no error: the model is as it was (today's squeeze);
--   * closed while the read is going: nothing is built after it and the quota slot is free.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FRAME = 1 / 60
local KIND = "kitty_bread"
-- Part of the shell cache's key with the scale (below), so a second run on the same modules misses the first's shells.
local RUN = os.clock() % 1000 / 1e6

return function(t: Context)
	local Knead = t.requireClient("Controllers/KneadController")
	local OrbitCamera = t.requireClient("UI/OrbitCamera")
	local MeshQuota = t.requireClient("Anim/MeshQuota")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect

	local function octahedron(): any
		local positions = {
			Vector3.new(1, 0, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 1, 0),
			Vector3.new(0, -1, 0),
			Vector3.new(0, 0, 1),
			Vector3.new(0, 0, -1),
		}
		local tris = { 1, 3, 5, 3, 2, 5, 2, 4, 5, 4, 1, 5, 3, 1, 6, 2, 3, 6, 4, 2, 6, 1, 4, 6 }
		return { positions = positions, colors = table.create(6, Color3.new(0.8, 0.5, 0.25)), tris = tris }
	end

	-- `points` / 4 closed tetrahedra in a row: a mesh of any size.
	local function tetrahedra(points: number): any
		local positions: { Vector3 } = {}
		local tris: { number } = {}
		for k = 0, points // 4 - 1 do
			local at = Vector3.new(k, 0, 0)
			local base = #positions
			table.insert(positions, at + Vector3.new(0.2, 0.2, 0.2))
			table.insert(positions, at + Vector3.new(-0.2, -0.2, 0.2))
			table.insert(positions, at + Vector3.new(-0.2, 0.2, -0.2))
			table.insert(positions, at + Vector3.new(0.2, -0.2, -0.2))
			for _, index in { 1, 2, 4, 1, 4, 3, 1, 3, 2, 2, 3, 4 } do
				table.insert(tris, base + index)
			end
		end
		return { positions = positions, colors = table.create(#positions, Color3.new(1, 1, 1)), tris = tris }
	end

	local function standIns(readMesh: (string) -> any): any
		local rec: any = { mesh = nil, canvases = 0, textures = 0, reads = {}, shell = nil, writes = 0 }
		Knead.useDeps({
			Shell = {
				readMesh = function(uri: string): any
					table.insert(rec.reads, uri)
					return readMesh(uri)
				end,
				create = function(shell: any, _flipV: boolean): (any, string?)
					rec.shell = shell
					local mesh: any = { part = {}, destroyed = false }
					function mesh.write(_self: any)
						rec.writes += 1
					end
					function mesh.raycast(_self: any): (number?, Vector3?)
						return nil, nil
					end
					function mesh.destroy(_self: any)
						mesh.destroyed = true
					end
					rec.mesh = mesh
					return mesh, nil
				end,
			},
			Canvas = {
				new = function(): any
					rec.canvases += 1
					local atlas: any = { image = "atlas" }
					function atlas.draw(_self: any, _budget: number): number
						return 0
					end
					function atlas.pending(_self: any): number
						return 0
					end
					function atlas.destroy(_self: any) end
					return atlas
				end,
			},
			Texture = function()
				rec.textures += 1
			end,
			Sound = {
				play = function(): boolean
					return true
				end,
				playLoop = function(): any
					local loop: any = {}
					function loop.setVolume(_self: any, _volume: number) end
					function loop.stop(_self: any) end
					return loop
				end,
			},
		})
		return rec
	end

	local function addFileMeshPart(model: Model, name: string, attributes: { [string]: any }, at: Vector3)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = Vector3.one * 0.3
		part.CFrame = CFrame.new(at)
		part.Anchored = true
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.FileMesh
		mesh.Parent = part
		for key, value in attributes do
			part:SetAttribute(key, value)
		end
		part.Parent = model
	end

	-- `scale`: part of the shell cache's key, so a test can miss the cache of the one before.
	local function toyModel(scale: number): (Model, MeshPart, MeshPart)
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.one * 0.2
		root.Anchored = true
		root.Parent = model
		model.PrimaryPart = root
		model:SetAttribute("SD_Scale", scale + RUN)
		local body = Instance.new("MeshPart")
		body.Name = "Body"
		body.Size = Vector3.new(2, 2, 2)
		body.Anchored = true
		body:SetAttribute("SD_Body", true)
		body:SetAttribute("SD_Shape", "M")
		body:SetAttribute("SD_ShellLow", "rbxassetid://5")
		body.Parent = model
		local outline = Instance.new("MeshPart")
		outline.Name = "BodyOutline"
		outline.Size = Vector3.new(2.2, 2.2, 2.2)
		outline.Anchored = true
		outline:SetAttribute("SD_Outline", true)
		outline.Parent = model
		local up = Vector3.new(0, -1, 0)
		addFileMeshPart(model, "EarOuterL", { SD_Section = "EarL", SD_Contact = up }, Vector3.new(0.7, 0.8, 0))
		addFileMeshPart(model, "EarOutlineL", { SD_Section = "EarL", SD_Contact = up }, Vector3.new(0.1, 0.9, 0.2))
		return model, body, outline
	end

	local function open(model: Model, wax: boolean?): any
		local def = Catalog.get(KIND)
		local w: any = { views = {}, model = model }
		w.stage = {
			viewport = Instance.new("ViewportFrame"),
			front = Instance.new("Frame"),
			root = Instance.new("Frame"),
			camera = { CFrame = CFrame.new(0, 0, -10), FieldOfView = 30 },
		}
		w.handle = Knead.start({
			model = model,
			def = def,
			stage = w.stage,
			orbit = OrbitCamera.new(def.inspect.yaw, def.inspect.pitch),
			rig = function(): any
				return nil
			end,
			deformer = function(): any
				return nil
			end,
			reattach = function() end,
			onView = function(view: any)
				table.insert(w.views, if view then view else false)
			end,
			reduced = function(): boolean
				return false
			end,
			wax = wax,
		})
		return w
	end

	local function close(w: any)
		if w.handle then
			w.handle:destroy()
			w.handle = nil
		end
		w.model:Destroy()
		for _, key in { "viewport", "front", "root" } do
			w.stage[key]:Destroy()
		end
	end

	-- Runs a test's body, then always closes the toy and the stand-ins, then fails if the body did.
	local function run(w: any, body: any)
		local ok, err = pcall(body)
		close(w)
		Knead.useDeps(nil)
		if not ok then
			error(err, 0)
		end
	end

	t.test("a mesh body goes live: its mesh read, no atlas, the wax off, body and outline hidden, back on destroy", function()
		local rec = standIns(function(_uri: string): any
			return octahedron()
		end)
		local model, body, outline = toyModel(1)
		local w = open(model, true) -- even with the wax asked for
		run(w, function()
			expect.truthy(w.handle ~= nil)
			local state = w.handle:debugState()
			expect.equal(state.state, "ready")
			expect.equal(state.wax, false)
			expect.equal(#rec.reads, 1)
			expect.equal(rec.reads[1], if state.quality == "Low" then "rbxassetid://5" else body.MeshId)
			expect.equal(rec.shell.count, 6)
			expect.truthy(rec.shell.colors ~= nil)
			expect.truthy(rec.shell.hull ~= nil)
			expect.near(rec.shell.hull.thickness, 0.1, 1e-5)
			w.handle:step(FRAME, 0)
			expect.truthy(w.handle:isLive())
			expect.equal(rec.canvases, 0)
			expect.equal(rec.textures, 0)
			expect.equal(body.Transparency, 1)
			expect.equal(outline.Transparency, 1)
			local mesh = rec.mesh
			w.handle:destroy()
			w.handle = nil
			expect.equal(body.Transparency, 0)
			expect.equal(outline.Transparency, 0)
			expect.truthy(mesh.destroyed)
		end)
	end)

	t.test("a press on a mesh body writes the shell every frame, with no wax, atlas or error", function()
		local rec = standIns(function(_uri: string): any
			return octahedron()
		end)
		local model = toyModel(1.5)
		local w = open(model)
		run(w, function()
			w.handle:step(FRAME, 0)
			expect.truthy(w.handle:isLive())
			w.handle:palms(true)
			for k = 1, 20 do
				w.handle:step(FRAME, k * FRAME)
			end
			w.handle:palms(false)
			w.handle:crunch(true)
			for k = 21, 40 do
				w.handle:step(FRAME, k * FRAME)
			end
			w.handle:crunch(false)
			expect.truthy(w.handle:isLive())
			expect.truthy(rec.writes > 0)
			expect.equal(w.handle:debugState().cracks, 0)
		end)
	end)

	t.test("the second open of the same toy goes live with no second read", function()
		local rec = standIns(function(_uri: string): any
			return octahedron()
		end)
		local first = open((toyModel(3)))
		local ok, err = pcall(function()
			expect.equal(first.handle:debugState().state, "ready")
		end)
		close(first)
		local w = open((toyModel(3)))
		run(w, function()
			if not ok then
				error(err, 0)
			end
			expect.equal(w.handle:debugState().state, "ready")
			expect.equal(#rec.reads, 1)
		end)
	end)

	t.test("anchors: an ear and its rim share one vertex on a mesh body; an old toy's keep their own", function()
		standIns(function(_uri: string): any
			return octahedron()
		end)
		local model = toyModel(4)
		local w = open(model)
		run(w, function()
			local anchors = w.handle._kit.anchors
			expect.equal(#anchors, 2)
			expect.equal(anchors[1], anchors[2])
		end)
		standIns(function(_uri: string): any
			error("an old toy reads no mesh", 0)
		end)
		local oldModel, body, outline = toyModel(5)
		outline:Destroy()
		local ball = Instance.new("Part")
		ball.Name = "Body"
		ball.Size = body.Size
		ball.Anchored = true
		ball:SetAttribute("SD_Body", true)
		ball:SetAttribute("SD_Shape", "E")
		body:Destroy()
		ball.Parent = oldModel
		local old = open(oldModel, false)
		run(old, function()
			local state = old.handle:debugState()
			expect.equal(state.state, "ready")
			local anchors = old.handle._kit.anchors
			expect.equal(#anchors, 2)
			expect.truthy(anchors[1] ~= anchors[2])
		end)
	end)

	t.test("shareAnchors: a section's parts take its first part's vertex; a rider with no section keeps its own", function()
		local riders = {
			{ group = "EarL", section = true },
			{ group = "EyeL", section = false },
			{ group = "EarL", section = true },
			{ group = "EyeL", section = false },
			{ group = "EarL", section = true },
		}
		local anchors = { 11, 22, 33, 44, 55 }
		Knead.shareAnchors(riders :: any, anchors)
		expect.deepEqual(anchors, { 11, 22, 11, 44, 11 })
	end)

	local function expectRefused(w: any, reason: string, body: BasePart, outline: BasePart)
		local state = w.handle:debugState()
		expect.equal(state.state, "off")
		expect.truthy(string.find(state.reason, reason, 1, true) ~= nil)
		w.handle:step(FRAME, 0)
		expect.falsy(w.handle:isLive())
		expect.equal(body.Transparency, 0)
		expect.equal(outline.Transparency, 0)
		expect.falsy(MeshQuota.holds("soft"))
	end

	t.test("a mesh that cannot be read ends the knead with no error, the model as it was", function()
		standIns(function(_uri: string): any
			error("mesh permission", 0)
		end)
		local model, body, outline = toyModel(2)
		local w = open(model)
		run(w, function()
			expectRefused(w, "mesh permission", body, outline)
		end)
	end)

	t.test("a second shell part beside the mesh body ends the knead before any read", function()
		local rec = standIns(function(_uri: string): any
			return octahedron()
		end)
		local model, body, outline = toyModel(6)
		local extra = Instance.new("Part")
		extra.Name = "Zest"
		extra.Size = Vector3.one * 0.3
		extra.Anchored = true
		extra:SetAttribute("SD_Shape", "E")
		extra.Parent = model
		local w = open(model)
		run(w, function()
			expectRefused(w, "only shell part", body, outline)
			expect.equal(#rec.reads, 0)
			expect.equal(extra.Transparency, 0)
		end)
	end)

	t.test("an outline no bigger than the body ends the knead", function()
		standIns(function(_uri: string): any
			return octahedron()
		end)
		local model, body, outline = toyModel(7)
		outline.Size = Vector3.new(1.8, 1.8, 1.8)
		local w = open(model)
		run(w, function()
			expectRefused(w, "outline", body, outline)
		end)
	end)

	t.test("a mesh over its quality's budget ends the knead: a phone never gets the heavy one", function()
		local rec = standIns(function(_uri: string): any
			return tetrahedra(Config.Knead.shell.highVertices + 4)
		end)
		local model, body, outline = toyModel(8)
		local w = open(model)
		run(w, function()
			expectRefused(w, "budget", body, outline)
			expect.equal(rec.shell, nil)
		end)
	end)

	t.test("closed while the mesh loads: nothing is built after the read and the slot is free", function()
		local thread: thread? = nil
		local rec = standIns(function(_uri: string): any
			thread = coroutine.running()
			coroutine.yield()
			return octahedron()
		end)
		local model = toyModel(9)
		local w = open(model)
		run(w, function()
			expect.equal(w.handle:debugState().state, "building")
			w.handle:destroy()
			w.handle = nil
			expect.falsy(MeshQuota.holds("soft"))
			task.spawn(thread :: thread)
			expect.equal(rec.shell, nil)
			expect.falsy(MeshQuota.holds("soft"))
		end)
	end)
end
