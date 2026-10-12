--!strict
-- InspectKnead_Test: the knead screen's hooks in StarterPlayerScripts.Client.Controllers.InspectController (spec
-- phase2-squeeze §3.1, §3.6). Server only (ServerStorage.UnitTest). Edit mode: useDeps() swaps every side-effecting
-- surface for a recording stand-in, deps.Knead included (a fake handle; Controllers/KneadController itself is
-- KneadController_Test's and Studio's). Contract:
--   * buildModel starts the knead on its model with the stage, the orbit and live getters for the rig and deformer;
--     reattach() swaps the deformer (old destroyed, a new "pivot" one), onView() reaches the panel's setKnead; select
--     stops the old knead and starts one on the new model; close stops it before the snapshot restores;
--   * while it is live a press that hits the toy is the knead's (pointerDown, pointerMove, pointerUp; the view does not
--     turn), a miss orbits as before; the mouse hovering with nothing pressed goes to hover(); focus loss cancels;
--   * live: F / ButtonX hold the crunch, Q / ButtonL1 the palms, W / ButtonR1 re-wax (only with the wax on), the panel's
--     holds and Re-wax reach it, and nothing squeezes the rig (no hold squeeze, tap preview or Squeeze-button preview);
--     not live: F squeezes as before and Q / W pass;
--   * the wax switch (user 2026-10-12): with Config.Wax.enabled false InspectRewax has no handler (W / ButtonR1 are not
--     bound), with it true it has one;
--   * the knead steps every frame before the rig's write; debugState carries the knead's.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Inspect = t.requireClient("Controllers/InspectController")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local WAX_ON = Config.Wax.enabled -- user 2026-10-12: the wax switch (InspectRewax is bound only with it on)

	local BEGIN, END = Enum.UserInputState.Begin, Enum.UserInputState.End
	local KEY_F = { KeyCode = Enum.KeyCode.F, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }
	local KEY_Q = { KeyCode = Enum.KeyCode.Q, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }
	local KEY_W = { KeyCode = Enum.KeyCode.W, UserInputType = Enum.UserInputType.Keyboard, Position = Vector3.zero }

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
		}
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

	local function indexOf(list: { string }, item: string): number
		return table.find(list, item) or math.huge
	end

	local function rethrow(ok: boolean, err: any)
		if not ok then
			error(err, 0)
		end
	end

	local function modelFor(id: string): Model
		local model = Instance.new("Model")
		model.Name = id
		model:SetAttribute("SD_BlueprintId", Catalog.get(id).blueprintId)
		return model
	end

	-- Installs the stand-ins and returns the world they share. w.live / w.hit drive the fake knead.
	local function fresh(): any
		local log: { string } = {}
		local function note(entry: string)
			table.insert(log, entry)
		end
		local w: any = { log = log, live = false, hit = false, starts = {}, view = "unset" }
		w.camera = { CameraType = Enum.CameraType.Custom }
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
		local stageModel: Model? = nil
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
			front = Instance.new("Folder"),
		}
		function stage.attach(self: any, container: any): boolean
			self.root.Parent = container
			return true
		end
		function stage.detach(self: any)
			self.root.Parent = nil
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
			local model = stageModel
			stageModel = nil
			return model
		end
		function stage.clearModel()
			if stageModel ~= nil then
				(stageModel :: Model):Destroy()
			end
			stageModel = nil
		end
		function stage.model(): Model?
			return stageModel
		end
		-- The model's rest box straight ahead of the camera: a press in the middle of the viewport is on it.
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
		function stage.setShadowWiden() end
		function stage.resetLook() end
		function stage.clearLayers() end
		w.stage = stage
		w.stageModel = function(): Model?
			return stageModel
		end

		local panel: any = {
			root = Instance.new("Frame"),
			stageHolder = holder,
			show = function() end,
			setEquip = function() end,
			setLayout = function() end,
			setKnead = function(_: any, view: any)
				w.view = view
				note(if view then "panel:knead" else "panel:noKnead")
			end,
			primary = function(): any
				return nil
			end,
			destroy = function() end,
		}

		-- The fake knead handle (one per start), recording every hook.
		local function newKnead(args: any): any
			local handle: any = { args = args }
			function handle.isLive(): boolean
				return w.live
			end
			function handle.step()
				note("knead:step")
			end
			function handle.pointerDown(_: any, position: Vector2, touch: boolean): boolean
				note(`knead:pointerDown:{touch}`)
				w.downAt = position
				return w.live and w.hit
			end
			function handle.pointerMove(_: any, position: Vector2)
				note("knead:pointerMove")
				w.movedTo = position
			end
			function handle.pointerUp()
				note("knead:pointerUp")
			end
			function handle.hover(_: any, position: Vector2?)
				note("knead:hover")
				w.hoverAt = position
			end
			function handle.crunch(_: any, on: boolean)
				note(`knead:crunch:{on}`)
			end
			function handle.palms(_: any, on: boolean)
				note(`knead:palms:{on}`)
			end
			function handle.rewax()
				note("knead:rewax")
			end
			function handle.cancel()
				note("knead:cancel")
			end
			function handle.debugState(): { [string]: any }
				return { state = if w.live then "live" else "building" }
			end
			function handle.destroy()
				note("knead:destroy")
			end
			return handle
		end

		Inspect.useDeps({
			Camera = {
				save = function(): any
					note("save")
					return {}
				end,
				restore = function()
					note("camera")
				end,
			},
			Controls = {
				block = function(): () -> ()
					return function()
						note("release")
					end
				end,
				setContext = function() end,
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
				duck = function(): () -> ()
					return function() end
				end,
				play = function(key: string)
					note("play:" .. key)
				end,
			},
			State = {
				owns = function(): boolean
					return true
				end,
				equipped = function(): string
					return "kitty_bread"
				end,
				isLobbyLocked = function(): boolean
					return false
				end,
			},
			UI = {
				isOpen = function(): boolean
					return false
				end,
				topModal = function(): string
					return "inspect"
				end,
				isRegistered = function(): boolean
					return true
				end,
				toast = function() end,
				close = function(): boolean
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
					return modelFor(id)
				end,
			},
			Deformer = {
				attach = function(_model: Model, options: any): any
					note(`deformer:attach:{options and options.twist}`)
					local deformer: any = {}
					function deformer.apply()
						note("deformer:apply")
					end
					function deformer.rest() end
					function deformer.getScale(): Vector3
						return Vector3.one
					end
					function deformer.destroy()
						note("deformer:destroy")
					end
					return deformer
				end,
			},
			Scheduler = {
				add = function(effect: any): any
					w.effect = effect
					return { disconnect = function() end }
				end,
			},
			Panel = {
				new = function(_parent: any, callbacks: any): any
					w.callbacks = callbacks
					return panel
				end,
			},
			Input = w.input,
			Prompts = { Enabled = true },
			Workspace = { CurrentCamera = w.camera },
			Motion = {
				reducedMotion = function(): boolean
					return false
				end,
			},
			Knead = {
				start = function(args: any): any
					note("knead:start")
					table.insert(w.starts, args)
					return newKnead(args)
				end,
			},
		})
		w.spec = Inspect.screenSpec()
		w.spec.build(Instance.new("Folder"))
		w.spec.onClose("reset") -- a test that failed before may have left it open
		w.clock = os.clock()
		w.frames = function(n: number)
			for _ = 1, n do
				w.clock += 1 / 60
				w.effect(1 / 60, w.clock)
			end
		end
		w.open = function(id: string)
			w.spec.onOpen({ squishyId = id, source = "squishies" })
			table.clear(log)
		end
		return w
	end

	local function finish(w: any)
		w.spec.onClose("closed")
		Inspect.useDeps(nil)
	end

	local function touchAt(x: number, y: number): any
		return { UserInputType = Enum.UserInputType.Touch, Position = Vector3.new(x, y, 0) }
	end

	t.test("open starts the knead on the built model with live hooks; close stops it before the restore", function()
		local w = fresh()
		w.spec.onOpen({ squishyId = "toast", source = "squishies" })
		local ok, err = pcall(function()
			expect.equal(#w.starts, 1)
			local args = w.starts[1]
			expect.equal(args.model, w.stageModel())
			expect.equal(args.def.id, "toast")
			expect.equal(args.stage, w.stage)
			expect.truthy(args.orbit ~= nil and args.orbit.targetYaw ~= nil)
			expect.truthy(args.rig() ~= nil)
			local first = args.deformer()
			expect.truthy(first ~= nil)
			expect.falsy(args.reduced())
			-- reattach: the old deformer goes, a new pivot-twist one comes, and the getter sees it.
			table.clear(w.log)
			args.reattach()
			expect.deepEqual(w.log, { "deformer:destroy", "deformer:attach:pivot" })
			expect.truthy(args.deformer() ~= first)
			-- onView reaches the panel.
			args.onView({ squeeze = "s", coat = "c", help = "h" })
			expect.equal(w.view.help, "h")
			args.onView(nil)
			expect.equal(w.view, nil)
			table.clear(w.log)
			w.spec.onClose("button")
			expect.equal(count(w.log, "knead:destroy"), 1)
			expect.truthy(indexOf(w.log, "knead:destroy") < indexOf(w.log, "camera"))
			-- After the close a reattach does nothing (the session is gone).
			table.clear(w.log)
			args.reattach()
			expect.deepEqual(w.log, {})
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("select stops the old knead and starts one on the new model", function()
		local w = fresh()
		w.open("toast")
		local ok, err = pcall(function()
			expect.truthy(Inspect.select("banana"))
			expect.equal(count(w.log, "knead:destroy"), 1)
			expect.equal(count(w.log, "knead:start"), 1)
			expect.truthy(indexOf(w.log, "knead:destroy") < indexOf(w.log, "knead:start"))
			expect.equal(w.starts[2].def.id, "banana")
			expect.equal(w.starts[2].model, w.stageModel())
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("live: a press that hits the toy is the knead's and the view stays; a miss orbits as before", function()
		local w = fresh()
		w.open("toast")
		local ok, err = pcall(function()
			w.live, w.hit = true, true
			w.frames(2)
			local yaw0 = Inspect.debugState().view.yaw
			local finger = touchAt(200, 150)
			w.holder.InputBegan:fire(finger)
			expect.equal(count(w.log, "knead:pointerDown:true"), 1)
			expect.equal(w.downAt, Vector2.new(200, 150))
			finger.Position = Vector3.new(260, 150, 0)
			w.input.InputChanged:fire(finger)
			expect.equal(count(w.log, "knead:pointerMove"), 1)
			expect.equal(w.movedTo, Vector2.new(260, 150))
			w.frames(10)
			expect.near(Inspect.debugState().view.yaw, yaw0, 1e-6)
			w.input.InputEnded:fire(finger)
			expect.equal(count(w.log, "knead:pointerUp"), 1)
			expect.equal(Inspect.debugState().previews, 0)
			-- A miss: the orbit turns, the knead sees no move.
			w.hit = false
			local other = touchAt(40, 40)
			w.holder.InputBegan:fire(other)
			other.Position = Vector3.new(140, 40, 0)
			w.input.InputChanged:fire(other)
			w.frames(10)
			expect.equal(count(w.log, "knead:pointerMove"), 1)
			expect.truthy(math.abs(Inspect.debugState().view.yaw - yaw0) > 1)
			w.input.InputEnded:fire(other)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("live: the hover goes to the knead, focus loss cancels, the knead steps before the rig writes", function()
		local w = fresh()
		w.open("toast")
		local ok, err = pcall(function()
			w.live = true
			w.input.InputChanged:fire({
				UserInputType = Enum.UserInputType.MouseMovement,
				Position = Vector3.new(120, 80, 0),
			})
			expect.equal(count(w.log, "knead:hover"), 1)
			expect.equal(w.hoverAt, Vector2.new(120, 80))
			w.input.WindowFocusReleased:fire()
			expect.equal(count(w.log, "knead:cancel"), 1)
			table.clear(w.log)
			w.frames(3)
			expect.equal(count(w.log, "knead:step"), 3)
			for index, entry in w.log do
				if entry == "deformer:apply" then
					expect.equal(w.log[index - 1], "knead:step")
				end
			end
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("live: F holds the crunch, Q the palms, W re-waxes (wax on), the panel too; no rig squeeze", function()
		local w = fresh()
		w.open("toast")
		local ok, err = pcall(function()
			w.live = true
			local handlers = Inspect.actionHandlers()
			expect.equal(handlers.InspectSqueeze(BEGIN, KEY_F :: any), true)
			handlers.InspectSqueeze(END, KEY_F :: any)
			expect.equal(handlers.InspectPalms(BEGIN, KEY_Q :: any), true)
			handlers.InspectPalms(END, KEY_Q :: any)
			-- User 2026-10-12: W / ButtonR1 re-wax only with the wax on; off they have no handler (not bound).
			local keyRewaxes = 0
			if WAX_ON then
				expect.equal(handlers.InspectRewax(BEGIN, KEY_W :: any), true)
				keyRewaxes = 1
			else
				expect.equal(handlers.InspectRewax, nil)
			end
			expect.equal(count(w.log, "knead:crunch:true"), 1)
			expect.equal(count(w.log, "knead:crunch:false"), 1)
			expect.equal(count(w.log, "knead:palms:true"), 1)
			expect.equal(count(w.log, "knead:palms:false"), 1)
			expect.equal(count(w.log, "knead:rewax"), keyRewaxes)
			w.callbacks.onKneadHold("crunch", true)
			w.callbacks.onKneadHold("crunch", false)
			w.callbacks.onKneadHold("palms", true)
			w.callbacks.onRewax() -- the panel shows Re-wax only with the wax on (the knead's view); the hook still reaches it
			w.callbacks.onSqueeze()
			expect.equal(count(w.log, "knead:crunch:true"), 2)
			expect.equal(count(w.log, "knead:crunch:false"), 2)
			expect.equal(count(w.log, "knead:palms:true"), 2)
			expect.equal(count(w.log, "knead:rewax"), keyRewaxes + 1)
			-- A still press on the background and a tap on its box never squeeze while kneading.
			local finger = touchAt(200, 150)
			w.holder.InputBegan:fire(finger)
			w.frames(40)
			w.input.InputEnded:fire(finger)
			local tap = touchAt(200, 150)
			w.holder.InputBegan:fire(tap)
			w.input.InputEnded:fire(tap)
			w.frames(2)
			expect.equal(Inspect.debugState().previews, 0)
			expect.falsy(Inspect.debugState().squeezing)
			expect.equal(count(w.log, "play:sfx.squish"), 0)
		end)
		finish(w)
		rethrow(ok, err)
	end)

	t.test("not live: F squeezes as before, Q and W pass, the panel's holds do nothing", function()
		local w = fresh()
		w.open("toast")
		local ok, err = pcall(function()
			local handlers = Inspect.actionHandlers()
			expect.equal(handlers.InspectPalms(BEGIN, KEY_Q :: any), nil)
			local rewaxKey = handlers.InspectRewax -- none with the wax off (user 2026-10-12)
			if rewaxKey then
				expect.equal(rewaxKey(BEGIN, KEY_W :: any), nil)
			end
			w.callbacks.onKneadHold("crunch", true)
			w.callbacks.onRewax()
			expect.equal(count(w.log, "knead:crunch:true"), 0)
			expect.equal(count(w.log, "knead:rewax"), 0)
			handlers.InspectSqueeze(BEGIN, KEY_F :: any)
			w.frames(2)
			expect.equal(Inspect.debugState().previews, 1)
			expect.truthy(Inspect.debugState().squeezing)
			handlers.InspectSqueeze(END, KEY_F :: any)
			expect.equal(Inspect.debugState().knead.state, "building")
		end)
		finish(w)
		rethrow(ok, err)
	end)

	-- User 2026-10-12: the wax crunch off (Config.Wax.enabled false) leaves W / ButtonR1 unbound; on, they re-wax.
	t.test("the wax switch: InspectRewax has a handler only with the wax on; the other knead keys always", function()
		local handlers = Inspect.actionHandlers()
		expect.equal(handlers.InspectRewax ~= nil, WAX_ON)
		expect.equal(type(handlers.InspectPalms), "function")
		expect.equal(type(handlers.InspectSqueeze), "function")
		expect.equal(type(handlers.InspectReset), "function")
	end)
end
