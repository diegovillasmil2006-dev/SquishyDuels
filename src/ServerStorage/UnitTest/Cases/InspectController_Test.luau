--!strict
-- InspectController_Test: unit tests for StarterPlayerScripts.Client.Controllers.InspectController (Part 6).
-- Server only (ServerStorage.UnitTest). Edit mode: no UIController, viewport stage, camera, prompt or input is touched:
-- useDeps() swaps every side-effecting surface for a recording stand-in, and screenSpec() hands over the handlers that
-- init() registers, so the tests drive onOpen / onClose the way UIController does.
-- Contract (DESIGN §10.1, §10.4, §10.10, §10.11, §9.11 handoff):
--   * open takes the restore snapshot first (CameraController.save, block("inspect"), ProximityPromptService.Enabled
--     saved then false), freezes the world camera (Scriptable), builds the model on the stage, turns the Inspect
--     context on and ducks the music;
--   * close restores in §10.10's order: camera -> block release -> prompts -> Inspect context off, music back; then the
--     deformer, the stage model, its layers and look go, the stage detaches and the per-open render effect is removed;
--   * a second close is a no-op;
--   * selecting another squishy swaps the model with no second snapshot (one save, one block, one duck); the same id
--     does nothing; the close after it restores once;
--   * the screen spec asks for closeOnCover (another modal opening over Inspect closes it first, §10.10);
--   * a close for a found match shows "Opponent found!";
--   * from the box reveal the stage's model is adopted (no rebuild) and shown as owned (the reveal's owned = true);
--   * while the box reveal holds the stage, Inspect takes nothing;
--   * the squeeze preview (§10.7) on the toy's rig (squishy overhaul spec 2026-10-09 §3.2): a press before the running
--     squeeze's pop end merges into it (the mashing cap, first-person spec 2026-10-10 §3.7: mashing F gives at most 3
--     squeezes a second), only a squeeze that starts counts as a preview, one sfx.squish on the UI group (the rig's
--     squish event), 2D dots at the peak that all go away, then back to the lobby breathing; the rarity flourish: the
--     Uncommon / Epic twist is one half-swing of 6°, Dragon's wings and tail flare as sections (the hero model); under
--     ReducedMotion (§18.1) no twist and no sections, the squash still plays;
--   * F / ButtonX (first-person spec §3.7): a press let go before the release start is exactly a tap (frame for frame),
--     a held one presses until it is let go;
--   * every rig squeezes on Y (Banana too; its Catalog axis stays Z for third person), a rig adopted from the box reveal
--     finishes its squeeze on its own axis first; the debug pose and the contact shadow read the rig's axis;
--   * no hand (spec 2026-10-11 §6, a real Viewport build): a squeeze shows none and the view keeps turning while it
--     plays;
--   * the faces: wow on open, the squish face at the peak, normal between squeezes;
--   * the hold gesture: a press on the model held 300 ms with < 8 px of movement presses the rig (counted once against
--     maxPerSecond) until the finger lifts; moving 8 px lets go and the drag turns the view;
--   * takeRig: the box reveal's rig goes on in Inspect (it is stepped from the adoption on, no new rig), and with the
--     reveal's breath the first frame shows that breath, going the same way (no jump at the hand-off);
--   * while open Inspect counts as one hero rig (Anim/HeroRigs) in the rig budget, until it closes;
--   * the debug pose (rigPose): squash at the toy's depth with its widen, the face, the blink, sections at ±max;
--   * gestures (§10.6): a drag turns the yaw by dx / H × dragYawDegPerHeight (front follows the finger), a two-finger
--     pinch sets zoom = startZoom × startDist / currentDist without turning, and close drops every listener (§10.11);
--     nothing moves while another modal is on top of Inspect.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

type Options = {
	revealOpen: boolean?,
	owns: boolean?,
	stageModel: Model?,
	reduced: boolean?, -- ReducedMotion
	makeModel: ((id: string) -> Model)?, -- what Cache.clone builds (default: an empty model)
}

return function(t: Context)
	local Inspect = t.requireClient("Controllers/InspectController")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local expect = t.expect

	local CLOSE_ORDER = {
		"camera",
		"release",
		"prompts:true",
		"context:Inspect=false",
		"unduck",
		"deformer:destroy",
		"clearModel",
		"clearLayers",
		"resetLook",
		"detach",
		"effect:disconnect",
	}

	-- A stand-in for an RBXScriptSignal (Connect) and a Util/Signal (connect), with fire() for the tests.
	local function signal(): any
		local handlers: { (...any) -> () } = {}
		local function add(fn: (...any) -> ()): () -> ()
			table.insert(handlers, fn)
			return function()
				local index = table.find(handlers, fn)
				if index then
					table.remove(handlers, index)
				end
			end
		end
		return {
			Connect = function(_self: any, fn: (...any) -> ()): any
				return { Disconnect = add(fn) }
			end,
			connect = function(_self: any, fn: (...any) -> ()): any
				return { disconnect = add(fn) }
			end,
			fire = function(_self: any, ...: any)
				for _, fn in table.clone(handlers) do
					fn(...)
				end
			end,
			count = function(): number
				return #handlers
			end,
		}
	end

	-- Re-raises a check that failed inside pcall (the controller is closed first, so the next test starts clean).
	local function rethrow(ok: boolean, err: any)
		if not ok then
			error(err, 0)
		end
	end

	local function count(list: { string }, item: string): number
		local n = 0
		for _, entry in list do
			if entry == item then
				n += 1
			end
		end
		return n
	end

	local function modelFor(id: string): Model
		local model = Instance.new("Model")
		model.Name = id
		model:SetAttribute("SD_BlueprintId", Catalog.get(id).blueprintId)
		return model
	end

	-- Installs recording stand-ins for every dependency and returns the world they share.
	local function fresh(opts: Options?): any
		local o: Options = opts or {}
		local log: { string } = {}
		local function note(entry: string)
			table.insert(log, entry)
		end
		local w: any = {
			log = log,
			lastView = nil,
			effect = nil,
			sets = 0,
			rests = 0,
			top = "inspect",
			lastScale = Vector3.one, -- the deformer's last scale
			lastTwist = 0, -- and twist
			lastFace = "normal", -- and face (apply)
			lastBlink = 1,
			lastSections = nil :: { number }?, -- the section angles of the last apply with sectionsOn (a copy)
			lastPress = 0, -- the last apply's pressAmount (the rig's own, no breathing in it)
			lastEvents = 0, -- and its events
			lastWiden = 1, -- the contact shadow's last width factor
		}
		w.camera = { CameraType = Enum.CameraType.Custom }
		w.front = Instance.new("Folder") -- the stage's front layer (the preview's 2D dots)
		local promptState = { Enabled = true }
		w.prompts = setmetatable({}, {
			__index = promptState,
			__newindex = function(_: any, key: string, value: any)
				note("prompts:" .. tostring(value))
				promptState[key] = value
			end,
		})

		local holder = { InputBegan = signal() }
		w.holder = holder
		w.input = {
			InputChanged = signal(),
			InputEnded = signal(),
			WindowFocusReleased = signal(),
			MouseIconEnabled = true,
			IsKeyDown = function(): boolean
				return false
			end,
			GetGamepadState = function(): { any }
				return {}
			end,
		}
		local stageModel: Model? = o.stageModel
		local stage: any = {
			root = { Parent = nil :: any, InputBegan = signal() },
			viewport = {
				InputBegan = signal(),
				AbsoluteSize = Vector2.new(400, 300),
				AbsolutePosition = Vector2.zero,
				GetDescendants = function(): { Instance }
					return {}
				end,
			},
			camera = { CFrame = CFrame.identity, FieldOfView = 30 },
			front = w.front,
		}
		function stage.attach(self: any, container: any): boolean
			self.root.Parent = container
			note("attach")
			return true
		end
		function stage.detach(self: any)
			self.root.Parent = nil
			note("detach")
		end
		function stage.isAttached(self: any): boolean
			return self.root.Parent ~= nil
		end
		function stage.isAlive(): boolean
			return true
		end
		function stage.setModel(_: any, model: Model): any
			if stageModel ~= nil and stageModel ~= model then
				(stageModel :: Model):Destroy()
			end
			stageModel = model
			return { center = Vector3.zero, size = Vector3.one, radius = 1, pivotRotation = CFrame.identity }
		end
		function stage.takeModel(): Model?
			note("takeModel")
			local model = stageModel
			stageModel = nil
			return model
		end
		function stage.clearModel()
			note("clearModel")
			if stageModel ~= nil then
				(stageModel :: Model):Destroy()
			end
			stageModel = nil
		end
		function stage.model(): Model?
			return stageModel
		end
		-- The model's rest box straight ahead of the stage camera (identity, looking down -Z): a press at the middle of
		-- the viewport hits it.
		function stage.framing(): any
			if stageModel == nil then
				return nil
			end
			return {
				center = Vector3.new(0, 0, -10),
				size = Vector3.new(2, 2, 2),
				radius = 2,
				pivotRotation = CFrame.identity,
			}
		end
		function stage.setView() end
		function stage.view(): (number, number, number)
			return 0, 0, 1
		end
		function stage.setRarity() end
		function stage.setShadowWiden(_: any, factor: number)
			w.lastWiden = factor
		end
		function stage.resetLook()
			note("resetLook")
		end
		function stage.clearLayers()
			note("clearLayers")
		end
		w.stageModel = function(): Model?
			return stageModel
		end
		w.stage = stage

		local panel: any = {
			root = Instance.new("Frame"),
			stageHolder = holder,
			show = function(_: any, view: any)
				w.lastView = view
				note("show:" .. view.id)
			end,
			setEquip = function(_: any, state: string)
				note("equipState:" .. state)
			end,
			setLayout = function() end,
			primary = function(): any
				return nil
			end,
			destroy = function() end,
		}

		Inspect.useDeps({
			Camera = {
				save = function(): any
					note("save")
					return { cameraType = w.camera.CameraType }
				end,
				restore = function(snapshot: any)
					note("camera")
					w.camera.CameraType = snapshot.cameraType
				end,
			},
			Controls = {
				block = function(reason: string): () -> ()
					note("block:" .. reason)
					local released = false
					return function()
						if not released then
							released = true
							note("release")
						end
					end
				end,
				setContext = function(context: string, on: boolean)
					note(`context:{context}={on}`)
				end,
				ContextChanged = signal(),
				isBlocked = function(): boolean
					return false
				end,
				blockReasons = function(): { string }
					return {}
				end,
				activeContexts = function(): { string }
					return {}
				end,
			},
			Sound = {
				duck = function(reason: string): () -> ()
					note("duck:" .. reason)
					return function()
						note("unduck")
					end
				end,
				play = function(key: string, options: any)
					note(`play:{key}:{if options then options.group else nil}`)
				end,
			},
			State = {
				owns = function(): boolean
					return o.owns == true
				end,
				equipped = function(): string
					return "kitty_bread"
				end,
				isLobbyLocked = function(): boolean
					return false
				end,
			},
			UI = {
				isOpen = function(name: string): boolean
					return name == "boxReveal" and o.revealOpen == true
				end,
				topModal = function(): string
					return w.top
				end,
				isRegistered = function(): boolean
					return true
				end,
				toast = function(text: string)
					note("toast:" .. text)
				end,
				close = function(name: string, reason: string?): boolean
					note(`uiclose:{name}:{reason}`)
					return true
				end,
				open = function(): boolean
					return true
				end,
			},
			Stage = {
				get = function(): any
					return stage
				end,
				exists = function(): boolean
					return true
				end,
			},
			Cache = {
				clone = function(id: string): Model
					note("clone:" .. id)
					local make: (string) -> Model = o.makeModel or modelFor
					return make(id)
				end,
			},
			Deformer = {
				attach = function(model: Model): any
					note("deformer:attach")
					-- Like SquishDeformer, every write rewrites the meshes from their base (here: Scale 1).
					local function writeBase()
						for _, descendant in model:GetDescendants() do
							if descendant:IsA("SpecialMesh") then
								descendant.Scale = Vector3.one
							end
						end
					end
					return {
						rest = function()
							w.rests += 1
							w.lastScale, w.lastTwist = Vector3.one, 0
							writeBase()
						end,
						set = function(_self: any, scale: Vector3, twist: number)
							w.sets += 1
							w.lastScale, w.lastTwist = scale, twist
							writeBase()
						end,
						-- One SquishRig frame (SquishDeformer:apply).
						apply = function(_self: any, out: any)
							w.sets += 1
							w.lastScale, w.lastTwist = out.S, out.twist
							w.lastFace, w.lastBlink = out.face, out.blink
							w.lastPress, w.lastEvents = out.pressAmount, out.events
							w.lastSections = if out.sectionsOn then table.clone(out.sections) else nil
							writeBase()
						end,
						getScale = function(): Vector3
							return w.lastScale
						end,
						destroy = function()
							note("deformer:destroy")
						end,
					}
				end,
			},
			Scheduler = {
				add = function(effect: any): any
					w.effect = effect -- the per-open render effect, stepped by hand
					note("effect:add")
					return {
						disconnect = function()
							note("effect:disconnect")
						end,
					}
				end,
			},
			Panel = {
				new = function(): any
					return panel
				end,
			},
			Input = w.input,
			Prompts = w.prompts,
			Workspace = { CurrentCamera = w.camera },
			Motion = {
				reducedMotion = function(): boolean
					return o.reduced == true
				end,
			},
			Knead = { -- no knead screen here (InspectKnead_Test covers the hooks): today's squeeze
				start = function(): any
					return nil
				end,
			},
		})
		w.spec = Inspect.screenSpec()
		w.spec.build(Instance.new("Folder"))
		w.spec.onClose("reset") -- a test that failed before may have left it open
		table.clear(log)
		return w
	end

	local function finish(w: any)
		w.spec.onClose("closed")
		Inspect.useDeps(nil)
	end

	t.test("open takes the restore snapshot first, freezes the camera and builds on the stage", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "toast", source = "squishies" })
		local ok, err = pcall(function()
			expect.truthy(Inspect.isOpen())
			expect.deepEqual({ w.log[1], w.log[2], w.log[3] }, { "save", "block:inspect", "prompts:false" })
			expect.equal(w.camera.CameraType, Enum.CameraType.Scriptable)
			expect.equal(w.prompts.Enabled, false)
			local clone = table.find(w.log, "clone:toast")
			local attach = table.find(w.log, "attach")
			expect.truthy(clone ~= nil and attach ~= nil and clone < attach)
			expect.equal(count(w.log, "context:Inspect=true"), 1)
			expect.equal(count(w.log, "duck:inspect"), 1)
			expect.equal(count(w.log, "effect:add"), 1)
			expect.equal(w.lastView.id, "toast")
			expect.falsy(w.lastView.owned)
			local state = Inspect.debugState()
			expect.equal(state.phase, "Open")
			expect.equal(state.squishyId, "toast")
			expect.equal(state.source, "squishies")
			expect.truthy(state.restorePending)
			expect.truthy(state.musicDucked)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("close restores in the §10.10 order, then frees the stage; a second close is a no-op", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "butter", source = "hud" })
		table.clear(w.log)
		w.spec.onClose("button")
		expect.deepEqual(w.log, CLOSE_ORDER)
		expect.falsy(Inspect.isOpen())
		expect.equal(w.camera.CameraType, Enum.CameraType.Custom)
		expect.equal(w.prompts.Enabled, true)
		expect.equal(w.stageModel(), nil)
		local state = Inspect.debugState()
		expect.equal(state.phase, "Closed")
		expect.falsy(state.restorePending)
		-- Again: nothing more happens.
		w.spec.onClose("button")
		w.spec.onClose("menu")
		expect.deepEqual(w.log, CLOSE_ORDER)
		finish(w)
	end)

	t.test("selecting another squishy swaps the model with one restore snapshot", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "kitty_bread", source = "hud" })
		w.spec.onOpen({ squishyId = "kitty_bread", source = "squishies" }) -- the same id: nothing
		w.spec.onOpen({ squishyId = "banana", source = "shop" })
		local ok, err = pcall(function()
			expect.equal(count(w.log, "save"), 1)
			expect.equal(count(w.log, "block:inspect"), 1)
			expect.equal(count(w.log, "prompts:false"), 1)
			expect.equal(count(w.log, "duck:inspect"), 1)
			expect.equal(count(w.log, "effect:add"), 1)
			expect.equal(count(w.log, "clone:kitty_bread"), 1)
			expect.equal(count(w.log, "clone:banana"), 1)
			expect.equal(count(w.log, "deformer:attach"), 2)
			expect.equal(count(w.log, "deformer:destroy"), 1)
			local model = w.stageModel()
			expect.truthy(model ~= nil)
			expect.equal(model:GetAttribute("SD_BlueprintId"), Catalog.get("banana").blueprintId)
			expect.equal(w.lastView.id, "banana")
			expect.equal(Inspect.debugState().squishyId, "banana")
			expect.equal(Inspect.debugState().source, "shop")
			-- The public select() swaps too, still without a new snapshot.
			expect.truthy(Inspect.select("donut"))
			expect.falsy(Inspect.select("no_such_squishy"))
			expect.equal(count(w.log, "save"), 1)
			expect.equal(Inspect.debugState().squishyId, "donut")
		end)
		w.spec.onClose("button")
		local closeOk, closeErr = pcall(function()
			expect.equal(count(w.log, "camera"), 1)
			expect.equal(count(w.log, "release"), 1)
			expect.equal(count(w.log, "prompts:true"), 1)
			expect.equal(count(w.log, "unduck"), 1)
			expect.equal(w.camera.CameraType, Enum.CameraType.Custom)
		end)
		finish(w)
		rethrow(ok, err)
		rethrow(closeOk, closeErr)
	end)

	t.test("the screen asks UIController to close it when another modal opens over it (§10.10)", function()
		local spec = Inspect.screenSpec()
		expect.equal(spec.closeOnCover, true)
		expect.equal(spec.modal, nil) -- a modal (the default)
		expect.equal(spec.lobbyOnly, nil) -- refused from Matched through Returning (the default, §10.1)
	end)

	t.test("a close for a found match shows Opponent found!", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "chocolate", source = "boxes" })
		w.spec.onClose("matched")
		expect.equal(count(w.log, "toast:" .. Strings.queue.opponentFound), 1)
		expect.falsy(Inspect.isOpen())
		finish(w)
	end)

	t.test("from the box reveal the stage's model is adopted and shown as owned", function()
		local revealed = modelFor("dragon")
		local w = fresh({ stageModel = revealed, owns = false })
		w.spec.onOpen({ squishyId = "dragon", owned = true, source = "boxReveal" })
		local ok, err = pcall(function()
			expect.equal(count(w.log, "takeModel"), 1)
			expect.equal(count(w.log, "clone:dragon"), 0)
			expect.equal(w.stageModel(), revealed)
			expect.truthy(w.lastView.owned)
			expect.truthy(Inspect.debugState().owned)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("an unknown id shows the equipped squishy; the reveal's owned is trusted only from the reveal", function()
		local w = fresh({ owns = false })
		w.spec.onOpen({ squishyId = "no_such_squishy", owned = true, source = "shop" })
		local ok, err = pcall(function()
			expect.equal(Inspect.debugState().squishyId, "kitty_bread")
			expect.falsy(w.lastView.owned)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("while the box reveal holds the stage, Inspect takes nothing", function()
		local w = fresh({ revealOpen = true })
		w.spec.onOpen({ squishyId = "bird", source = "boxes" })
		expect.equal(count(w.log, "save"), 0)
		expect.equal(count(w.log, "block:inspect"), 0)
		expect.equal(count(w.log, "clone:bird"), 0)
		expect.falsy(Inspect.isOpen())
		expect.equal(w.camera.CameraType, Enum.CameraType.Custom)
		finish(w)
	end)

	-- Squishy overhaul (spec 2026-10-09 §3.2): the preview, faces, hold, takeRig and debug pose on the toy's rig ------

	local SquishRig = t.requireClient("Anim/SquishRig")
	local Blueprints = t.requireShared("Art/SquishyBlueprints")
	local RIG = Config.Anim.rig
	local LOBBY = Config.Anim.held.lobbyIdle

	-- Steps the per-open render effect `n` frames of 1/60 s from `clock` (a table so the caller keeps the time).
	local function frames(w: any, clock: { now: number }, n: number)
		local dt = 1 / 60
		for _ = 1, n do
			clock.now += dt
			w.effect(dt, clock.now)
		end
	end

	local function touch(x: number, y: number): any
		return { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(x, y, 0) }
	end

	t.test(
		"the squeeze preview: presses before the pop end merge, one sfx.squish on UI, dots at the peak, then breathes",
		function()
			local w = fresh()
			w.spec.onOpen({ squishyId = "toast", source = "squishies" })
			local ok, err = pcall(function()
				local started = 0
				for _ = 1, 12 do
					if Inspect.squeeze() then
						started += 1
					end
				end
				-- The mashing cap (first-person spec 2026-10-10 §3.7): the 11 others merge into the running squeeze, and
				-- only a squeeze that starts counts as a preview.
				expect.equal(started, 1)
				expect.equal(Inspect.debugState().previews, started)
				expect.truthy(Inspect.debugState().squeezing)
				-- Three seconds of frames (the effect gets os.clock()-based `now`, like the Scheduler's).
				local t0 = os.clock()
				local dt = 1 / 60
				local mostDots, deepest = 0, 1
				for frame = 1, 180 do
					expect.truthy(w.effect(dt, t0 + frame * dt))
					mostDots = math.max(mostDots, Inspect.debugState().dots)
					deepest = math.min(deepest, w.lastScale.Y)
				end
				-- One squeeze plays, with one sfx.squish on UI.
				expect.equal(count(w.log, "play:sfx.squish:UI"), 1)
				expect.truthy(mostDots > 0)
				expect.equal(Inspect.debugState().dots, 0)
				expect.equal(#w.front:GetChildren(), 0)
				-- It squeezed down to the toy's own depth (the breathing rides on top) ...
				expect.truthy(deepest < Blueprints.toast.motion.squeeze.depth + 0.04)
				-- ... and is back to its lobby breathing, no squeeze playing, the normal face.
				expect.falsy(Inspect.debugState().squeezing)
				expect.truthy(math.abs(w.lastScale.Y - 1) <= LOBBY.ampY + 1e-3)
				expect.equal(w.lastFace, "normal")
			end)
			finish(w)
			rethrow(ok, err)
		end
	)

	t.test("wow on open, the squish face at the peak, the normal face between squeezes, and blinks", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "kitty_bread", source = "hud" })
		local ok, err = pcall(function()
			local clock = { now = os.clock() }
			frames(w, clock, 1)
			expect.equal(w.lastFace, "wow")
			frames(w, clock, math.ceil(RIG.face.wowSeconds * 60) + 2)
			expect.equal(w.lastFace, "normal")
			expect.truthy(Inspect.squeeze())
			local squished = false
			for _ = 1, 30 do
				frames(w, clock, 1)
				squished = squished or w.lastFace == "squish"
			end
			expect.truthy(squished)
			frames(w, clock, 180)
			expect.equal(w.lastFace, "normal")
			local blinked = false
			for _ = 1, 60 * math.ceil(RIG.blink.maxSeconds + 1) do
				frames(w, clock, 1)
				blinked = blinked or w.lastBlink < 1
			end
			expect.truthy(blinked)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	type Trace = { twistMost: number, sectionMost: number }

	-- Opens Inspect on `id`, plays one preview and steps 150 frames of 1/60 s: the largest twist and section angle.
	local function previewTrace(id: string, reduced: boolean): Trace
		local w = fresh({ reduced = reduced })
		w.spec.onOpen({ squishyId = id, source = "squishies" })
		local trace: Trace = { twistMost = 0, sectionMost = 0 }
		local ok, err = pcall(function()
			expect.truthy(Inspect.squeeze())
			local t0 = os.clock()
			local dt = 1 / 60
			for frame = 1, 150 do
				w.effect(dt, t0 + frame * dt)
				trace.twistMost = math.max(trace.twistMost, math.abs(w.lastTwist))
				for _, angle in w.lastSections or {} do
					trace.sectionMost = math.max(trace.sectionMost, math.abs(angle))
				end
			end
		end)
		finish(w)
		rethrow(ok, err)
		return trace
	end

	t.test(
		"Uncommon and Epic twist one 6° half-swing, Dragon flares its sections; ReducedMotion only squashes",
		function()
			local twistRad = math.rad(Config.Anim.squeeze.flourish.Epic.twistDeg)
			for _, id in { "bird", "butter" } do
				local full = previewTrace(id, false)
				expect.truthy(full.twistMost > twistRad * 0.9)
				expect.truthy(full.twistMost <= twistRad + 1e-6)
				expect.equal(previewTrace(id, true).twistMost, 0)
			end
			expect.equal(previewTrace("toast", false).twistMost, 0) -- a Common does not twist
			local dragon = previewTrace("dragon", false)
			expect.truthy(dragon.sectionMost > math.rad(2)) -- the hero model's wings and tail bounce and flare
			expect.equal(dragon.twistMost, 0)
			expect.equal(previewTrace("dragon", true).sectionMost, 0)
		end
	)

	t.test("a hold on the model presses the rig (counted once) until the finger lifts; moving 8 px lets go", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "kitty_bread", source = "hud" })
		local input = Config.Inspect.Input
		local ok, err = pcall(function()
			local clock = { now = os.clock() }
			local depth = Blueprints.kitty_bread.motion.squeeze.depth
			-- A finger on the middle of the viewport (on the model), held still.
			local finger = touch(200, 150)
			w.holder.InputBegan:fire(finger)
			frames(w, clock, math.floor(input.tapMaxMs / 1000 * 60) - 3) -- just under 300 ms: not yet a hold
			expect.falsy(Inspect.debugState().pressing)
			expect.equal(Inspect.debugState().previews, 0)
			frames(w, clock, 6)
			expect.truthy(Inspect.debugState().pressing)
			expect.equal(Inspect.debugState().previews, 1)
			frames(w, clock, 60) -- a second of holding: it stays at the toy's depth
			expect.near(w.lastScale.Y, depth, 0.05)
			expect.equal(Inspect.debugState().previews, 1) -- one hold counts once
			-- The finger lifts: the rig lets go (the pop, then its spring); no tap squeeze on top.
			w.input.InputEnded:fire(finger)
			expect.falsy(Inspect.debugState().pressing)
			frames(w, clock, 240)
			expect.falsy(Inspect.debugState().squeezing)
			expect.equal(Inspect.debugState().previews, 1)
			-- A hold that moves 8 px or more lets go and becomes the orbit drag.
			local yaw0 = Inspect.debugState().view.yaw
			local other = touch(200, 150)
			w.holder.InputBegan:fire(other)
			frames(w, clock, 24)
			expect.truthy(Inspect.debugState().pressing)
			other.Position = Vector3.new(200 + input.tapMaxPixels + 22, 150, 0)
			w.input.InputChanged:fire(other)
			frames(w, clock, 2)
			expect.falsy(Inspect.debugState().pressing)
			frames(w, clock, 20)
			expect.truthy(math.abs(Inspect.debugState().view.yaw - yaw0) > 1)
			w.input.InputEnded:fire(other)
			expect.equal(Inspect.debugState().previews, 2)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("takeRig: the box reveal's rig goes on in Inspect, stepped from the adoption on", function()
		local revealed = modelFor("mochi_fox")
		local w = fresh({ stageModel = revealed, owns = true })
		local def = Catalog.get("mochi_fox")
		local blueprint = Blueprints.mochi_fox
		local function rigOf(): any
			return SquishRig.new(
				blueprint.motion,
				{ axis = def.anim.squeezeAxis, rarity = def.rarity, sections = blueprint.sections }
			)
		end
		local rig = rigOf()
		rig:tap() -- the reveal left it mid-squeeze
		Inspect.takeRig(revealed, rig)
		w.spec.onOpen({ squishyId = "mochi_fox", owned = true, source = "boxReveal" })
		local ok, err = pcall(function()
			expect.equal(count(w.log, "takeModel"), 1)
			expect.equal(rig:elapsedMs(), 0)
			local clock = { now = os.clock() }
			frames(w, clock, 6)
			expect.near(rig:elapsedMs() :: number, 100, 1) -- Inspect steps the given rig
			expect.truthy(w.lastFace ~= "wow") -- no wow: the reveal had its own
			expect.equal(count(w.log, "play:sfx.squish:UI"), 1) -- its squish event sounds on the UI group
			-- Handed over while open (the same model), it takes over at once.
			local later = rigOf()
			Inspect.takeRig(revealed, later)
			later:tap()
			frames(w, clock, 3)
			expect.near(later:elapsedMs() :: number, 50, 1)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test(
		"takeRig with the reveal's breath: Inspect's first frame goes on from it (no jump at the hand-off)",
		function()
			for _, case in { { amount = 0.6, rising = true }, { amount = 0.25, rising = false } } do
				local revealed = modelFor("mochi_fox")
				local w = fresh({ stageModel = revealed, owns = true })
				local def = Catalog.get("mochi_fox")
				local blueprint = Blueprints.mochi_fox
				local rig =
					SquishRig.new(blueprint.motion, { axis = def.anim.squeezeAxis, rarity = def.rarity, blink = false })
				Inspect.takeRig(revealed, rig, case.amount, case.rising)
				w.spec.onOpen({ squishyId = "mochi_fox", owned = true, source = "boxReveal" })
				local ok, err = pcall(function()
					local clock = { now = 100.25 }
					frames(w, clock, 1)
					-- The reveal showed S.Y = 1 + ampY · amount (S.X = 1 - ampY / 2 · amount); the rig itself rests.
					expect.near(w.lastScale.Y, 1 + LOBBY.ampY * case.amount, 1e-4)
					expect.near(w.lastScale.X, 1 - LOBBY.ampY / 2 * case.amount, 1e-4)
					local first = w.lastScale.Y
					frames(w, clock, 3)
					expect.equal(w.lastScale.Y > first, case.rising) -- and it goes on the same way
				end)
				finish(w)
				rethrow(ok, err)
			end
		end
	)

	t.test("an open Inspect counts as one hero rig (HeroRigs) until it closes", function()
		local HeroRigs = t.requireClient("Anim/HeroRigs")
		local before = HeroRigs.count()
		local w = fresh()
		w.spec.onOpen({ squishyId = "toast", source = "squishies" })
		local ok, err = pcall(function()
			expect.equal(HeroRigs.count(), before + 1)
			expect.truthy(Inspect.select("banana"))
			expect.equal(HeroRigs.count(), before + 1) -- another squishy, still one rig
		end)
		w.spec.onClose("button")
		local closedOk, closedErr = pcall(function()
			expect.equal(HeroRigs.count(), before)
		end)
		finish(w)
		rethrow(ok, err)
		rethrow(closedOk, closedErr)
	end)

	t.test(
		"the debug pose freezes a frame: depth with the toy's widen, the face, the blink, sections at ±max",
		function()
			local w = fresh()
			w.spec.onOpen({ squishyId = "kitty_bread", source = "hud" })
			local ok, err = pcall(function()
				local clock = { now = os.clock() }
				local blueprint = Blueprints.kitty_bread
				local squeeze = blueprint.motion.squeeze
				expect.truthy(Inspect.debugPose({ squash = 1, face = "squish", blink = 1, sections = 1 }))
				frames(w, clock, 3)
				expect.near(w.lastScale.Y, squeeze.depth, 1e-4)
				expect.near(w.lastScale.X, 1 + (1 - squeeze.depth) * squeeze.widen, 1e-4)
				expect.equal(w.lastTwist, 0)
				expect.equal(w.lastFace, "squish")
				expect.near(w.lastBlink, RIG.blink.closedY, 1e-6)
				local names = SquishRig.sectionNames(blueprint.sections)
				local angles = w.lastSections or {}
				expect.equal(#angles, #names)
				for index, name in names do
					local section = blueprint.sections[name]
					local max = math.rad(section.maxDeg or RIG.sections.maxDeg)
					expect.near(angles[index], (section.sign or 1) * max, 1e-6)
				end
				-- -1 turns them the other way; the frame stays frozen until nil lets it live again.
				expect.truthy(Inspect.debugPose({ sections = -1 }))
				frames(w, clock, 60)
				expect.near(w.lastScale.Y, 1, 1e-6)
				expect.equal(w.lastFace, "normal")
				expect.near(
					(w.lastSections or {})[1],
					-(
							(blueprint.sections[names[1]].sign or 1)
							* math.rad(blueprint.sections[names[1]].maxDeg or RIG.sections.maxDeg)
						),
					1e-6
				)
				expect.truthy(Inspect.debugPose(nil))
				frames(w, clock, 40)
				expect.truthy(math.abs(w.lastScale.Y - 1) <= LOBBY.ampY + 1e-3)
				for _, angle in w.lastSections or {} do
					expect.equal(angle, 0) -- live again: the sections rest at their base
				end
			end)
			finish(w)
			rethrow(ok, err)
			-- Closed: nothing to pose.
			expect.falsy(Inspect.debugPose({ squash = 1 }))
		end
	)

	t.test(
		"a drag on the stage turns the view, a pinch zooms without turning, and close drops the listeners",
		function()
			local w = fresh()
			w.spec.onOpen({ squishyId = "toast", source = "squishies" })
			local input = Config.Inspect.Input
			local ok, err = pcall(function()
				local clock = { now = os.clock() }
				local yaw0 = Inspect.debugState().view.yaw
				-- One finger pressed on the stage (two layers see it: still one pointer), 60 px right, held.
				local finger = touch(200, 150)
				w.holder.InputBegan:fire(finger)
				w.stage.viewport.InputBegan:fire(finger)
				finger.Position = Vector3.new(260, 150, 0)
				w.input.InputChanged:fire(finger)
				frames(w, clock, 30)
				-- A drag to the right turns the front right on screen: the yaw falls by dx / H × dragYawDegPerHeight.
				local turned = (yaw0 - Inspect.debugState().view.yaw) % 360
				expect.near(turned, 60 / 300 * input.dragYawDegPerHeight, 0.5)
				w.input.InputEnded:fire(finger)
				frames(w, clock, 30)
				local yaw1 = Inspect.debugState().view.yaw
				-- Two fingers 200 px apart spread to 320 px: zoom = 1 × 200 / 320, and the view does not turn.
				local a, b = touch(100, 150), touch(300, 150)
				w.holder.InputBegan:fire(a)
				w.holder.InputBegan:fire(b)
				b.Position = Vector3.new(400, 150, 0)
				w.input.InputChanged:fire(b)
				a.Position = Vector3.new(80, 150, 0)
				w.input.InputChanged:fire(a)
				frames(w, clock, 60)
				local state = Inspect.debugState()
				expect.near(state.view.zoom, 200 / 320, 0.01)
				expect.near(state.view.yaw, yaw1, 0.05)
				w.input.InputEnded:fire(a)
				w.input.InputEnded:fire(b)
			end)
			w.spec.onClose("button")
			local closedOk, closedErr = pcall(function()
				expect.equal(w.holder.InputBegan:count(), 0)
				expect.equal(w.stage.viewport.InputBegan:count(), 0)
				expect.equal(w.input.InputChanged:count(), 0)
				expect.equal(w.input.InputEnded:count(), 0)
			end)
			finish(w)
			rethrow(ok, err)
			rethrow(closedOk, closedErr)
		end
	)

	t.test("Inspect input waits while another modal is on top of it", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "toast", source = "squishies" })
		local ok, err = pcall(function()
			local clock = { now = os.clock() }
			local yaw0 = Inspect.debugState().view.yaw
			w.top = "other"
			local finger = touch(200, 150)
			w.holder.InputBegan:fire(finger)
			finger.Position = Vector3.new(300, 150, 0)
			w.input.InputChanged:fire(finger)
			w.input.InputEnded:fire(finger)
			frames(w, clock, 30)
			expect.near(Inspect.debugState().view.yaw, yaw0, 1e-6)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	-- First person, step 2 (spec 2026-10-10 §3.7): F / ButtonX Begin and End, axis Y; no hand (spec 2026-10-11 §6) ----

	local Builder = t.requireShared("Art/SquishyBuilder")
	local BEGIN, CHANGE, END = Enum.UserInputState.Begin, Enum.UserInputState.Change, Enum.UserInputState.End
	local KEY_F = { KeyCode = Enum.KeyCode.F, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }

	-- A real scale-1 Viewport build (body parts, SD_HalfExtents), the kind step 2 gave a hand.
	local function builtModel(id: string): Model
		local model = Builder.build(Catalog.get(id).blueprintId, "Viewport", 1)
		model:SetAttribute("SD_BlueprintId", Catalog.get(id).blueprintId)
		return model
	end

	t.test("F / ButtonX: a quick press is exactly a tap, a held one presses until it is let go", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "mochi_fox", source = "hud" })
		local ok, err = pcall(function()
			local press = Inspect.actionHandlers().InspectSqueeze
			local def = Catalog.get("mochi_fox")
			local blueprint = Blueprints.mochi_fox
			local twin = SquishRig.new(blueprint.motion, {
				axis = "Y",
				rarity = def.rarity,
				sections = blueprint.sections,
				foamRecoveryT = def.anim.foamRecoveryT,
				blink = false,
			})
			local twinOut = SquishRig.newOut()
			local clock = { now = os.clock() }
			-- Down for 100 ms (before the release start), then up: the same squeeze a tap plays, frame for frame.
			expect.equal(press(BEGIN, KEY_F), true)
			twin:tap()
			for frame = 1, 90 do
				if frame == 7 then
					expect.equal(press(END, KEY_F), true)
				end
				frames(w, clock, 1)
				twin:step(1 / 60, twinOut)
				expect.near(w.lastPress, twinOut.pressAmount, 1e-6)
				expect.equal(w.lastEvents, twinOut.events)
			end
			expect.equal(Inspect.debugState().previews, 1)
			-- Held a second: it stays pressed at the toy's depth; let go, it pops and settles.
			frames(w, clock, 120)
			expect.falsy(Inspect.debugState().squeezing)
			expect.equal(press(BEGIN, KEY_F), true)
			frames(w, clock, 60)
			expect.truthy(Inspect.debugState().squeezing)
			expect.near(w.lastPress, 1, 0.05)
			expect.equal(press(END, KEY_F), true)
			frames(w, clock, 150)
			expect.falsy(Inspect.debugState().squeezing)
			expect.equal(Inspect.debugState().previews, 2)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("mashing F: at most 3 squeezes a second, one preview and one sfx.squish each", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "kitty_bread", source = "hud" })
		local ok, err = pcall(function()
			local press = Inspect.actionHandlers().InspectSqueeze
			local clock = { now = os.clock() }
			local startsAt: { number } = {}
			for frame = 1, 180 do -- 3 s; a press every 3 frames (20 a second), held one frame
				if frame % 3 == 1 then
					local before = Inspect.debugState().previews
					press(BEGIN, KEY_F)
					if Inspect.debugState().previews > before then
						table.insert(startsAt, clock.now)
					end
				elseif frame % 3 == 2 then
					press(END, KEY_F)
				end
				frames(w, clock, 1)
			end
			frames(w, clock, 30) -- the last squeeze reaches its anticipation end (its sfx.squish)
			for i = 4, #startsAt do
				expect.truthy(startsAt[i] - startsAt[i - 3] > 1)
			end
			expect.truthy(#startsAt >= 6 and #startsAt <= 9)
			expect.equal(Inspect.debugState().previews, #startsAt)
			expect.equal(count(w.log, "play:sfx.squish:UI"), #startsAt)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("every rig squeezes on Y (Banana too); the debug pose and the shadow read the rig's axis", function()
		expect.equal(Catalog.get("banana").anim.squeezeAxis, "Z") -- its third-person squeeze stays Z
		expect.equal(Config.Inspect.Preview.squeezeAxis, "Y") -- spec 2026-10-11 §6 (the first-person overlay's is X)
		local w = fresh()
		w.spec.onOpen({ squishyId = "banana", source = "shop" })
		local ok, err = pcall(function()
			local clock = { now = os.clock() }
			expect.truthy(Inspect.squeeze())
			local lowestY, widestZ = 2, 0
			for _ = 1, 20 do
				frames(w, clock, 1)
				lowestY = math.min(lowestY, w.lastScale.Y)
				widestZ = math.max(widestZ, w.lastScale.Z)
				expect.near(w.lastWiden, w.lastScale.X, 1e-6) -- the shadow: the scale across Y
			end
			expect.truthy(lowestY < 0.85 and widestZ > 1.05)
			local squeeze = Blueprints.banana.motion.squeeze
			expect.truthy(Inspect.debugPose({ squash = 1 }))
			frames(w, clock, 2)
			expect.near(w.lastScale.Y, squeeze.depth, 1e-4)
			expect.near(w.lastScale.Z, 1 + (1 - squeeze.depth) * squeeze.widen, 1e-4)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("a rig adopted from the box reveal finishes its squeeze on its own axis, then squeezes on Y", function()
		local revealed = modelFor("banana")
		local w = fresh({ stageModel = revealed, owns = true })
		local def = Catalog.get("banana")
		local rig = SquishRig.new(Blueprints.banana.motion, { axis = def.anim.squeezeAxis, rarity = def.rarity })
		rig:tap() -- the reveal left it mid-squeeze, on Z
		Inspect.takeRig(revealed, rig)
		w.spec.onOpen({ squishyId = "banana", owned = true, source = "boxReveal" })
		local ok, err = pcall(function()
			local clock = { now = os.clock() }
			frames(w, clock, 10)
			expect.equal(rig:axis(), "Z")
			expect.truthy(w.lastScale.Z < 0.95) -- still on Z: no jump
			frames(w, clock, 240)
			expect.equal(rig:axis(), "Y")
			expect.truthy(Inspect.squeeze())
			frames(w, clock, 15)
			expect.truthy(w.lastScale.Y < 0.9)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	-- Spec 2026-10-11 §6: the 3D Lab Inspect has no hands (main.js:95-136 builds only the toy and its pedestal).
	t.test("no hand: a squeeze on a real model shows none and the view keeps turning while it plays", function()
		local w = fresh({ makeModel = builtModel })
		w.spec.onOpen({ squishyId = "toast", source = "squishies" })
		local ok, err = pcall(function()
			local handlers = Inspect.actionHandlers()
			local clock = { now = os.clock() }
			frames(w, clock, 2)
			expect.truthy(Inspect.squeeze())
			local yaw0 = Inspect.debugState().view.yaw
			local stick = { KeyCode = Enum.KeyCode.Thumbstick2, Position = Vector3.new(1, 0, 0) }
			handlers.InspectStick(CHANGE, stick)
			frames(w, clock, 10)
			handlers.InspectStick(END, stick)
			expect.truthy(Inspect.debugState().squeezing)
			expect.truthy(math.abs(Inspect.debugState().view.yaw - yaw0) > 1)
			expect.equal(Inspect.debugState().handShown, nil)
		end)
		finish(w)
		rethrow(ok, err)
	end)
end
