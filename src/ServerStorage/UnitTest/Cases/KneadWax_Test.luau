--!strict
-- KneadWax_Test: the wax switch of the knead screen (Config.Wax.enabled; user 2026-10-12: the wax crunch is off, one
-- flag brings it back). Server only (ServerStorage.UnitTest). Edit mode: StarterPlayerScripts.Client.Controllers.
-- KneadController's handle on a built Butter (Art/SquishyBuilder, foam) with recording stand-ins for its engine-only
-- surfaces (KneadController.useDeps: the shell's EditableMesh, the crack atlas' EditableImage, the atlas on the shell,
-- the sound player), the real UI/KneadOverlay and Anim/FlakePool on plain GUI objects, and UI/InspectPanel built in a
-- Folder. Contract:
--   * the wax off (args.wax false): the handle goes live with no crack network and no coat (no segments, no cracks),
--     the atlas still on the shell and never queued, drawn, cleared or refilled; no wax HUD (no WaxMeter on the stage's
--     front layer) and no flakes folder; the view has no Coat row, no Re-wax, Thumb press and a press help line; the
--     palms and the thumb press still knead (the mesh is written) with their two thumps, taps, the body loop and the
--     softened let-go ticks, and no crack burst, haze or re-wax sound; rewax() changes nothing;
--   * the wax on (args.wax true): the network builds and the atlas is drawn, the WaxMeter and the flakes folder are
--     there, the view has the Coat row, Re-wax and Thumb crunch; rewax() clears and refills the atlas and plays the
--     sparkle;
--   * UI/KneadOverlay: hud false makes no WaxMeter (setHud and setCompact do nothing), hud true makes one, no option
--     follows the switch;
--   * UI/InspectPanel:setKnead: the thumb button takes the view's label, Re-wax shows only with view.rewax and the Coat
--     row only with a view.coat; nil hides them all.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local FRAME = 1 / 60
local TOY = "butter" -- a foam toy with three shell parts (KneadController_Test)

return function(t: Context)
	local Knead = t.requireClient("Controllers/KneadController")
	local KneadOverlay = t.requireClient("UI/KneadOverlay")
	local KneadFormat = t.requireClient("UI/KneadFormat")
	local InspectPanel = t.requireClient("UI/InspectPanel")
	local OrbitCamera = t.requireClient("UI/OrbitCamera")
	local MeshQuota = t.requireClient("Anim/MeshQuota")
	local Builder = t.requireShared("Art/SquishyBuilder")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local expect = t.expect
	local K = Strings.knead
	local GRAIN_START = Config.Audio.wax.grainStart -- the sheet's grains (ticks) and taps come after its bursts

	local function rethrow(ok: boolean, err: any)
		if not ok then
			error(err, 0)
		end
	end

	-- Recording stand-ins for the handle's engine-only surfaces (KneadController.useDeps).
	local function standIns(): any
		local rec: any = { mesh = nil, canvas = nil, plays = {}, loops = {} }
		local shell = {
			create = function(_shell: any, _flipV: boolean): (any, string?)
				local mesh: any = { part = {}, writes = 0, destroyed = false }
				function mesh.write(_self: any)
					mesh.writes += 1
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
		}
		local canvas = {
			new = function(_shell: any, _colors: { Color3 }, _size: number): any
				local atlas: any = { image = "atlas", queued = 0, draws = 0, clears = 0, fills = 0, destroyed = false }
				function atlas.queue(_self: any, changes: { any })
					atlas.queued += #changes
				end
				function atlas.draw(_self: any, _budget: number): number
					atlas.draws += 1
					return 0
				end
				function atlas.clear(_self: any)
					atlas.clears += 1
				end
				function atlas.fill(_self: any)
					atlas.fills += 1
				end
				function atlas.pending(_self: any): number
					return 0
				end
				function atlas.destroy(_self: any)
					atlas.destroyed = true
				end
				rec.canvas = atlas
				return atlas
			end,
		}
		local player = {
			play = function(key: string, options: any): boolean
				table.insert(rec.plays, { key = key, options = options })
				return true
			end,
			playLoop = function(key: string, options: any): any
				local loop: any = { key = key, volume = options.volume or 0, stopped = false }
				function loop.setVolume(_self: any, volume: number)
					loop.volume = volume
				end
				function loop.stop(_self: any)
					loop.stopped = true
				end
				table.insert(rec.loops, loop)
				return loop
			end,
		}
		Knead.useDeps({
			Shell = shell,
			Canvas = canvas,
			Texture = function(part: any, image: any)
				part.texture = image
			end,
			Sound = player,
		})
		return rec
	end

	-- A knead session on a built Butter with a plain stage; w.views records every onView (false for nil).
	local function session(wax: boolean): any
		local def = Catalog.get(TOY)
		local w: any = { views = {} }
		w.model = Builder.build(def.blueprintId, "Viewport", 1)
		w.stage = {
			viewport = Instance.new("ViewportFrame"),
			front = Instance.new("Frame"),
			root = Instance.new("Frame"),
			camera = { CFrame = CFrame.new(0, 0, 10), FieldOfView = 30 },
		}
		w.handle = Knead.start({
			model = w.model,
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

	local function finish(w: any)
		if w.handle then
			w.handle:destroy()
		end
		w.model:Destroy()
		for _, key in { "viewport", "front", "root" } do
			w.stage[key]:Destroy()
		end
		Knead.useDeps(nil)
	end

	local function frames(handle: any, n: number)
		for _ = 1, n do
			handle:step(FRAME, 0)
		end
	end

	local function live(handle: any)
		assert(handle ~= nil, "no knead handle (no soft mesh slot?)")
		local before = handle:debugState()
		assert(before.state == "ready", `the build did not finish: {before.state} ({before.reason})`)
		handle:step(FRAME, 0)
		assert(handle:isLive(), `not live: {handle:debugState().reason}`)
	end

	t.test("the wax off: no network, coat, lines, HUD, flakes or re-wax; the soft body kneads and sounds", function()
		local rec = standIns()
		local w = session(false)
		local ok, err = pcall(function()
			local handle = w.handle
			live(handle)
			local state = handle:debugState()
			expect.equal(state.wax, false)
			expect.equal(state.segments, 0)
			expect.equal(state.networkFinished, false)
			expect.equal(state.cracks, 0)
			expect.equal(state.flakes, 0)
			expect.equal(state.reason, nil)
			expect.equal(rec.mesh.part.texture, rec.canvas.image) -- the atlas still colours the shell
			-- No wax HUD and no flakes folder; the overlay itself (its ring) is there.
			expect.equal(w.stage.front:FindFirstChild("WaxMeter"), nil)
			expect.truthy(w.stage.front:FindFirstChild("KneadRing") ~= nil)
			expect.equal(w.stage.viewport:FindFirstChild("SD_KneadFlakes"), nil)
			-- The panel's view: the Squeeze row only, no Re-wax, the press wording.
			local view = w.views[#w.views]
			expect.truthy(type(view) == "table")
			expect.equal(view.coat, nil)
			expect.equal(view.rewax, false)
			expect.equal(view.thumb, K.thumbPress)
			expect.equal(view.squeeze, KneadFormat.rows("foam", false).squeeze)
			expect.truthy(
				view.help == K.helpNoWax.keyboard or view.help == K.helpNoWax.touch or view.help == K.helpNoWax.gamepad
			)
			-- The palms, then the thumb press: the soft body moves, nothing cracks, no line is queued or drawn.
			handle:palms(true)
			frames(handle, 30)
			handle:palms(false)
			handle:crunch(true)
			frames(handle, 60)
			handle:crunch(false)
			frames(handle, 30)
			expect.truthy(handle:isLive())
			expect.truthy(rec.mesh.writes > 0)
			expect.equal(handle:debugState().cracks, 0)
			expect.equal(handle:debugState().segments, 0)
			expect.equal(rec.canvas.queued, 0)
			expect.equal(rec.canvas.draws, 0)
			-- The sound: the two presses' thumps and taps, the softened let-go ticks (grains; user 2026-10-12), the body
			-- loop, no burst, no haze, no sparkle.
			local thumps = 0
			for _, play in rec.plays do
				expect.truthy(play.key ~= "sfx.wax.rewax")
				if play.key == "sfx.wax.thump" then
					thumps += 1
				elseif play.options.region ~= nil then
					expect.truthy(play.options.region.Min >= GRAIN_START - 1e-9) -- a tap or a tick, never a burst
				end
			end
			expect.equal(thumps, 2) -- the palms' press and the thumbs' press
			local bodies, hazes = 0, 0
			for _, loop in rec.loops do
				if string.find(loop.key, "sfx.wax.body.", 1, true) then
					bodies += 1
				elseif string.find(loop.key, "sfx.wax.haze.", 1, true) then
					hazes += 1
				end
			end
			expect.equal(bodies, 1)
			expect.equal(hazes, 0)
			-- Re-wax does nothing: no sound, the atlas untouched, no sparkle.
			local plays = #rec.plays
			handle:rewax()
			frames(handle, 2)
			expect.equal(rec.canvas.clears, 0)
			expect.equal(rec.canvas.fills, 0)
			expect.equal(handle:debugState().flakes, 0)
			for k = plays + 1, #rec.plays do
				expect.truthy(rec.plays[k].key ~= "sfx.wax.rewax")
			end
		end)
		finish(w)
		expect.falsy(MeshQuota.holds("soft")) -- the slot went with the handle
		rethrow(ok, err)
	end)

	t.test("the wax on: the network, the WaxMeter, the flakes, Coat, Re-wax and Thumb crunch; rewax resets", function()
		local rec = standIns()
		local w = session(true)
		local ok, err = pcall(function()
			local handle = w.handle
			live(handle)
			expect.equal(handle:debugState().wax, true)
			expect.truthy(w.stage.front:FindFirstChild("WaxMeter") ~= nil)
			expect.truthy(w.stage.viewport:FindFirstChild("SD_KneadFlakes") ~= nil)
			local view = w.views[#w.views]
			expect.truthy(type(view) == "table")
			expect.equal(view.coat, KneadFormat.rows("foam", true).coat)
			expect.equal(view.rewax, true)
			expect.equal(view.thumb, K.thumbCrunch)
			-- The network builds a few ms a frame; the atlas is drawn every frame.
			frames(handle, 5)
			local state = handle:debugState()
			expect.truthy(state.segments > 0 or state.networkFinished)
			expect.truthy(rec.canvas.draws > 0)
			-- Re-wax: the atlas clears and refills and the sparkle plays.
			handle:rewax()
			expect.equal(rec.canvas.clears, 1)
			expect.equal(rec.canvas.fills, 1)
			local sparkles = 0
			for _, play in rec.plays do
				if play.key == "sfx.wax.rewax" then
					sparkles += 1
				end
			end
			expect.equal(sparkles, 1)
			expect.truthy(handle:isLive())
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("KneadOverlay: no WaxMeter with hud false (setHud, setCompact do nothing); one with hud true", function()
		local front = Instance.new("Frame")
		local stage = { front = front, root = Instance.new("Frame") }
		local ok, err = pcall(function()
			local off = KneadOverlay.new(stage, { hud = false })
			expect.equal(front:FindFirstChild("WaxMeter"), nil)
			off:setHud(KneadFormat.hud(0.5, 0.5, 3), false)
			off:setCompact(true)
			expect.equal(front:FindFirstChild("WaxMeter"), nil)
			expect.truthy(front:FindFirstChild("KneadRing") ~= nil)
			off:destroy()
			local on = KneadOverlay.new(stage, { hud = true })
			expect.truthy(front:FindFirstChild("WaxMeter") ~= nil)
			on:setHud(KneadFormat.hud(0.5, 0.5, 3), false)
			on:destroy()
			expect.equal(front:FindFirstChild("WaxMeter"), nil)
			-- No option: the switch.
			local switched = KneadOverlay.new(stage)
			expect.equal(front:FindFirstChild("WaxMeter") ~= nil, Config.Wax.enabled)
			switched:destroy()
		end)
		front:Destroy()
		stage.root:Destroy()
		rethrow(ok, err)
	end)

	t.test("InspectPanel:setKnead: the thumb label, Re-wax only with view.rewax, Coat only with a coat", function()
		local holder = Instance.new("Folder")
		local noop = function() end
		local panel = InspectPanel.new(holder, {
			onClose = noop,
			onSqueeze = noop,
			onResetView = noop,
			onEquip = noop,
			onViewInShop = noop,
		})
		local ok, err = pcall(function()
			local function labelOf(button: any): string
				local label = button.root:FindFirstChild("Label", true)
				assert(label ~= nil and label:IsA("TextLabel"), "no Label in the button")
				return label.Text
			end
			local squeezeRow = panel.info:FindFirstChild("KneadSqueeze") :: TextLabel
			local coatRow = panel.info:FindFirstChild("KneadCoat") :: TextLabel
			-- The wax off: Thumb press, no Re-wax, the Squeeze row without the Coat row.
			panel:setKnead({ squeeze = "S", coat = nil, help = "H", thumb = K.thumbPress, rewax = false })
			expect.truthy(panel.crunchButton.root.Visible)
			expect.equal(labelOf(panel.crunchButton), K.thumbPress)
			expect.falsy(panel.rewaxButton.root.Visible)
			expect.truthy(squeezeRow.Visible)
			expect.falsy(coatRow.Visible)
			-- The wax on: Thumb crunch, Re-wax and the Coat row.
			panel:setKnead({ squeeze = "S", coat = "C", help = "H", thumb = K.thumbCrunch, rewax = true })
			expect.equal(labelOf(panel.crunchButton), K.thumbCrunch)
			expect.truthy(panel.rewaxButton.root.Visible)
			expect.truthy(coatRow.Visible)
			expect.equal(coatRow.Text, "C")
			-- nil hides them all.
			panel:setKnead(nil)
			expect.falsy(panel.crunchButton.root.Visible)
			expect.falsy(panel.rewaxButton.root.Visible)
			expect.falsy(squeezeRow.Visible)
			expect.falsy(coatRow.Visible)
		end)
		panel:destroy()
		holder:Destroy()
		rethrow(ok, err)
	end)
end
