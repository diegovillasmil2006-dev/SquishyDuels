--!strict
-- ControlsController_Test: unit tests for StarterPlayerScripts.Client.Controllers.ControlsController (Part 2 base).
-- Server only (ServerStorage.UnitTest). Edit mode: init()/start() are not called and nothing is bound to
-- ContextActionService here; only the pure parts of the contract are tested.
-- Contract (DESIGN §2.4, §10.4 step 2, §10.10, §11.7):
--   * block(reason) is ref-counted: the first block reports blocked, the last release unblocks; each release
--     function works once (a second call is a no-op); BlockChanged fires only on 0 -> 1 and 1 -> 0;
--   * the Lobby context is on by default; contexts switch on/off and fire ContextChanged only on a real change;
--     an unknown context is an error;
--   * the §11.7 input map: Squeeze = E / ButtonX, plus F (spec 2026-10-11 §3.8: the design's squish key, as in duels;
--     no other Lobby action takes F), Squishies = I, Inspect equipped = V / ButtonY, Throw = MouseButton1 / ButtonR2,
--     Ultimate = Q / ButtonL2, Modal back = Backspace / ButtonB.
-- Part 4 (DESIGN §5.4, §5.10, §11.2, §11.7):
--   * Duel and Practice contexts: Throw / Ultimate in Duel, PracticeThrow / PracticeUltimate in Practice, same keys;
--   * the Duel context follows SD_MatchId / SD_DuelPhase: on from Preparing through Result; Lobby off from Matched
--     through Returning; movement (PlayerModule controls) is frozen in Positioning and Countdown only;
--   * analog triggers (R2 / L2) count as pressed above Config.Combat.Aim.triggerThreshold, with one Begin / End edge;
--   * touch buttons: Throw 104 px × UIScale (never below 72), Ultimate 80 px × UIScale above-left of it, 16 px from
--     the jump button, inside the screen and out of the lower-left thumbstick zone (40% × 45%); UI FINAL R2 (PR1):
--     their UIScale is touchScale(screen), the HUD's own (Layout.uiScale of the width and the height), so every
--     touchLayout caller (the HUD, the practice panel, the first-person pad) models the boxes drawn.
-- Part 5 (DESIGN §17.3.2, §17.12): End is treated like Cancel: Begin -> block -> End reaches the handler and passes;
--   a Begin that arrives while the action is not live never does. Driven through casCallbackFor() (no CAS binding).
-- Part 6 (DESIGN §10.6): Inspect's R2 / L2 zoom begins past Config.Inspect.Input.triggerDeadzone (0.05), so its speed
--   follows Position.Z from the start; Throw / Ultimate keep the 0.5 edge.
-- First person (spec 2026-10-10 §3.1, §3.5): DuelSqueeze (F, ButtonX; feature 1 moved E to the catch) and DuelForfeit
--   (Backspace) live only in the Duel context; PracticeSqueeze (F, E, ButtonX) only in the Practice context, bound at Medium + 1 (aboveLobby): above
--   the lobby Squeeze, under every High action; Inspect's F still passes while Inspect is closed; with a back handler
--   pushed (the Modal context on) Backspace reaches ModalBack and never DuelForfeit, with none DuelForfeit runs.
-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): a left click or a touch on the 3D world presses the lobby
--   Squeeze (worldPointerPresses, pure): never one the game already took (gameProcessedEvent), one on the UI
--   (pointerOnGui: a shown button, text box, Active object or a surface with a background, so a toast or the coach
--   card's body never squeezes), in the practice box (a click throws there), a touch in the thumbstick zone (the
--   lower-left 40% × 45%, inThumbZone) or on the jump button, nor a second world touch; the Squeeze action itself keeps
--   its keys only, so PracticeThrow keeps the left mouse button.
-- Final polish (2026-10-11): the first-person Inspect showcase, HandInspect = R (the design's key, fp.js:656) and
--   ButtonL1 (build choice, NOT IN DESIGN), in the Lobby context (live in the lobby look and the practice range, never
--   from Matched through Returning); no other world action takes R or ButtonL1 (Inspect's R and the Modal tabs'
--   ButtonL1 are overlay actions, and an open modal or Inspect blocks every world action; feature 1's Catch takes
--   ButtonL1 in the Duel context only, which is never on with the Lobby context).
-- Feature 1 (2026-10-11, the catch; design: the combat-effects page "Squishy Combat FP v2.html", html:96, 395-398): Catch
--   is E and ButtonL1 in the Duel context (the right mouse button comes through UserInputService, as the world clicks);
--   no other duel action takes them; the touch Catch button (catchButton × UIScale, at least minTargetFloor) sits on
--   screen, out of the thumbstick zone and `gap` from Throw, Ultimate, Dash and the jump button.
-- Pens3 phase 13 (the throw on the launch deck's open area): a Highway context (HighwayThrowController turns it on
--   while the local character stands in the throw area); HighwayThrow = the left mouse button, ButtonR2 and the touch
--   Throw button there (Medium, like PracticeThrow; a press over a button is ignored); the touch buttons show on touch
--   in it, only Throw (Catch in a duel only, Ultimate and Dash in a duel or the practice range).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local Controls = t.requireClient("Controllers/ControlsController")
	local Config = t.requireShared("Config")
	local expect = t.expect

	t.test("block is ref-counted and each release works once", function()
		expect.falsy(Controls.isBlocked())
		local changes: { boolean } = {}
		local connection = Controls.BlockChanged:connect(function(blocked: boolean)
			table.insert(changes, blocked)
		end)
		local releaseModal = Controls.block("modal")
		local releaseInspect = Controls.block("inspect")
		expect.truthy(Controls.isBlocked())
		expect.deepEqual(Controls.blockReasons(), { "inspect", "modal" })
		releaseModal()
		releaseModal() -- no-op
		expect.truthy(Controls.isBlocked())
		expect.deepEqual(Controls.blockReasons(), { "inspect" })
		releaseInspect()
		expect.falsy(Controls.isBlocked())
		expect.deepEqual(Controls.blockReasons(), {})
		expect.deepEqual(changes, { true, false })
		connection:disconnect()
	end)

	t.test("the same reason can hold two blocks", function()
		local a = Controls.block("modal")
		local b = Controls.block("modal")
		a()
		expect.truthy(Controls.isBlocked())
		b()
		expect.falsy(Controls.isBlocked())
	end)

	t.test("block needs a reason", function()
		expect.throws(function()
			Controls.block("")
		end)
	end)

	t.test("Lobby is on by default and contexts switch with one change event each", function()
		expect.truthy(Controls.isContextActive("Lobby"))
		expect.falsy(Controls.isContextActive("Duel"))
		local events: { string } = {}
		local connection = Controls.ContextChanged:connect(function(context: string, on: boolean)
			table.insert(events, context .. "=" .. tostring(on))
		end)
		Controls.setContext("Duel", true)
		Controls.setContext("Duel", true) -- no change
		Controls.setContext("Lobby", false)
		expect.deepEqual(Controls.activeContexts(), { "Duel" })
		Controls.setContext("Lobby", true)
		Controls.setContext("Duel", false)
		expect.deepEqual(Controls.activeContexts(), { "Lobby" })
		expect.deepEqual(events, { "Duel=true", "Lobby=false", "Lobby=true", "Duel=false" })
		connection:disconnect()
		expect.throws(function()
			Controls.setContext("Nowhere", true)
		end, "context")
	end)

	t.test("the touch Throw / Ultimate buttons are up only on touch in the Duel or Practice context", function()
		-- Edit mode runs on the server: the preferred input is not Touch, so a live Duel context never shows them and
		-- TouchButtonsChanged never fires.
		local touch = Controls.preferredInput() == Enum.PreferredInput.Touch
		local changes: { boolean } = {}
		local connection = Controls.TouchButtonsChanged:connect(function(shown: boolean)
			table.insert(changes, shown)
		end)
		expect.falsy(Controls.touchButtonsShown()) -- the lobby: no Duel / Practice context
		Controls.setContext("Duel", true)
		expect.equal(Controls.touchButtonsShown(), touch)
		Controls.setContext("Duel", false)
		expect.falsy(Controls.touchButtonsShown())
		connection:disconnect()
		expect.deepEqual(changes, if touch then { true, false } else {})
	end)

	t.test("the input map follows §11.7", function()
		local function has(action: string, input: EnumItem): boolean
			local inputs = Controls.inputsOf(action)
			return inputs ~= nil and table.find(inputs, input) ~= nil
		end
		expect.truthy(has("Squeeze", Enum.KeyCode.E))
		expect.truthy(has("Squeeze", Enum.KeyCode.ButtonX))
		expect.truthy(has("Squishies", Enum.KeyCode.I))
		expect.truthy(has("InspectEquipped", Enum.KeyCode.V))
		expect.truthy(has("InspectEquipped", Enum.KeyCode.ButtonY))
		expect.truthy(has("Throw", Enum.UserInputType.MouseButton1))
		expect.truthy(has("Throw", Enum.KeyCode.ButtonR2))
		expect.truthy(has("Ultimate", Enum.KeyCode.Q))
		expect.truthy(has("Ultimate", Enum.KeyCode.ButtonL2))
		expect.truthy(has("ModalBack", Enum.KeyCode.Backspace))
		expect.truthy(has("ModalBack", Enum.KeyCode.ButtonB))
		expect.equal(Controls.inputsOf("NoSuchAction"), nil)
	end)

	t.test("F squeezes in the lobby too (spec 2026-10-11 §3.8), and no other Lobby action takes F", function()
		local inputs = Controls.inputsOf("Squeeze") :: { EnumItem }
		expect.truthy(table.find(inputs, Enum.KeyCode.F) ~= nil)
		for _, action in { "Squishies", "InspectEquipped", "FocusHud" } do
			expect.equal(Controls.contextOf(action), "Lobby")
			expect.equal(table.find(Controls.inputsOf(action) :: { EnumItem }, Enum.KeyCode.F), nil)
		end
	end)

	t.test(
		"UI FINAL R4 (H:653-654): keys 1-5 open the HUD's windows in the lobby, and switch them over a window",
		function()
			local keys =
				{ Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five }
			for index, key in keys do
				expect.equal(Controls.contextOf("Nav" .. index), "Lobby")
				expect.deepEqual(Controls.inputsOf("Nav" .. index), { key })
				expect.equal(Controls.contextOf("ModalNav" .. index), "Modal")
				expect.deepEqual(Controls.inputsOf("ModalNav" .. index), { key })
			end
			expect.equal(Controls.contextOf("Nav6"), nil)
			-- No other action takes a number key (keyboard only: no gamepad button, no touch button).
			local others =
				{ "Squeeze", "Squishies", "InspectEquipped", "FocusHud", "ModalBack", "Throw", "Ultimate", "Catch" }
			for _, action in others do
				local inputs = Controls.inputsOf(action) :: { EnumItem }
				for _, key in keys do
					expect.equal(table.find(inputs, key), nil)
				end
			end
			-- Over a window the switch is an overlay action: it sinks the key only while the Modal context is on.
			expect.equal(Controls.priorityOfAction("ModalNav1"), Enum.ContextActionPriority.High.Value)
			expect.equal(Controls.priorityOfAction("Nav1"), Controls.priorityOfAction("Squishies"))
		end
	)

	t.test("binding an unknown action is an error", function()
		expect.throws(function()
			Controls.bindAction("NoSuchAction", function()
				return true
			end)
		end, "unknown action")
	end)

	-- Part 4: Duel and Practice ----------------------------------------------------------------------------------------

	t.test("Duel and Practice actions share the §5.10 keys, each in its own context", function()
		local function has(action: string, input: EnumItem): boolean
			local inputs = Controls.inputsOf(action)
			return inputs ~= nil and table.find(inputs, input) ~= nil
		end
		expect.truthy(has("PracticeThrow", Enum.UserInputType.MouseButton1))
		expect.truthy(has("PracticeThrow", Enum.KeyCode.ButtonR2))
		expect.truthy(has("PracticeUltimate", Enum.KeyCode.Q))
		expect.truthy(has("PracticeUltimate", Enum.KeyCode.ButtonL2))
		expect.equal(Controls.contextOf("Throw"), "Duel")
		expect.equal(Controls.contextOf("Ultimate"), "Duel")
		expect.equal(Controls.contextOf("PracticeThrow"), "Practice")
		expect.equal(Controls.contextOf("PracticeUltimate"), "Practice")
		expect.equal(Controls.contextOf("Squeeze"), "Lobby")
		expect.equal(Controls.contextOf("NoSuchAction"), nil)
		-- Pressing an action nobody bound does nothing.
		expect.falsy(Controls.pressAction("NoSuchAction", Enum.UserInputState.Begin))
	end)

	t.test("the Duel context follows the duel attributes; Lobby is off from Matched through Returning", function()
		local idle = Controls.contextsForPhase("", "")
		expect.deepEqual(idle, { Duel = false, Lobby = true, inMatch = false })
		for _, phase in { "Preparing", "Positioning", "Countdown", "Active", "SuddenDeath", "Result" } do
			local view = Controls.contextsForPhase("m1", phase)
			expect.truthy(view.Duel)
			expect.falsy(view.Lobby)
		end
		for _, phase in { "Returning", "Cancelled", "Void" } do
			local view = Controls.contextsForPhase("m1", phase)
			expect.falsy(view.Duel)
			expect.falsy(view.Lobby)
			expect.truthy(view.inMatch)
		end
		-- A match id without a phase yet (Matched) already locks the lobby.
		expect.deepEqual(Controls.contextsForPhase("m1", ""), { Duel = false, Lobby = false, inMatch = true })
	end)

	t.test("movement is frozen on the client in Positioning and Countdown only (§5.4); never in the lobby", function()
		expect.falsy(Controls.movementFrozenForPhase("", ""))
		for _, phase in { "Positioning", "Countdown" } do
			expect.truthy(Controls.movementFrozenForPhase("m1", phase))
		end
		for _, phase in { "", "Preparing", "Active", "SuddenDeath", "Result", "Returning", "Cancelled", "Void" } do
			expect.falsy(Controls.movementFrozenForPhase("m1", phase))
		end
	end)

	t.test("analog triggers report one Begin above the threshold and one End below it", function()
		local threshold = Config.Combat.Aim.triggerThreshold
		local Change, Begin, End, Cancel =
			Enum.UserInputState.Change, Enum.UserInputState.Begin, Enum.UserInputState.End, Enum.UserInputState.Cancel
		local down, edge = Controls.triggerEdge(false, Change, threshold + 0.1, threshold)
		expect.truthy(down)
		expect.equal(edge, Begin)
		down, edge = Controls.triggerEdge(true, Change, threshold + 0.3, threshold)
		expect.truthy(down)
		expect.equal(edge, nil)
		down, edge = Controls.triggerEdge(true, Change, threshold - 0.2, threshold)
		expect.falsy(down)
		expect.equal(edge, End)
		down, edge = Controls.triggerEdge(false, Change, threshold - 0.1, threshold)
		expect.falsy(down)
		expect.equal(edge, nil)
		-- A digital trigger (Begin with no level) counts as fully pressed; End and Cancel release.
		down, edge = Controls.triggerEdge(false, Begin, 0, threshold)
		expect.truthy(down)
		expect.equal(edge, Begin)
		down, edge = Controls.triggerEdge(true, End, 1, threshold)
		expect.falsy(down)
		expect.equal(edge, End)
		down, edge = Controls.triggerEdge(true, Cancel, 1, threshold)
		expect.falsy(down)
		expect.equal(edge, End)
		down, edge = Controls.triggerEdge(false, Change, 0 / 0, threshold)
		expect.falsy(down)
		expect.equal(edge, nil)
	end)

	t.test("touch buttons: sizes, the jump-button gap, on screen and out of the thumbstick zone", function()
		local touch = Config.UI.Touch
		local screens =
			{ Vector2.new(1280, 720), Vector2.new(667, 375), Vector2.new(1920, 1080), Vector2.new(812, 375) }
		for _, screen in screens do
			local scale = Controls.touchScale(screen)
			local layout = Controls.touchLayout(screen, scale, nil)
			local throw, ult = layout.throw, layout.ultimate
			expect.near(throw.w, math.max(touch.throwButton * scale, touch.throwButtonMin), 1e-9)
			expect.truthy(throw.w >= touch.throwButtonMin)
			expect.near(ult.w, math.max(touch.ultButton * scale, touch.minTargetFloor), 1e-9)
			for _, rect in { throw, ult } do
				expect.truthy(rect.x >= 0 and rect.y >= 0)
				expect.truthy(rect.x + rect.w <= screen.X + 1e-6)
				expect.truthy(rect.y + rect.h <= screen.Y + 1e-6)
				-- Out of the thumbstick zone (lower-left 40% × 45%).
				local inZone = rect.x < screen.X * touch.thumbstickZoneWidth
					and rect.y + rect.h > screen.Y * (1 - touch.thumbstickZoneHeight)
				expect.falsy(inZone)
			end
			-- Ultimate sits above-left of Throw, the two round buttons at least `gap` apart.
			local throwCentre = Vector2.new(throw.x + throw.w / 2, throw.y + throw.h / 2)
			local ultCentre = Vector2.new(ult.x + ult.w / 2, ult.y + ult.h / 2)
			expect.truthy(ultCentre.X < throwCentre.X and ultCentre.Y < throwCentre.Y)
			expect.truthy((ultCentre - throwCentre).Magnitude >= throw.w / 2 + ult.w / 2 + touch.gap - 1e-6)
			-- The jump box it used (Roblox's default spot here): Throw sits `gap` left of it, bottoms aligned.
			local jump = layout.jump
			expect.near(throw.x + throw.w + touch.gap, jump.x, 1e-6)
			expect.near(throw.y + throw.h, jump.y + jump.h, 1e-6)
		end
		-- A jump box the caller passes (the real TouchGui button) comes back as it is.
		local given = { x = 500, y = 200, w = 90, h = 90 }
		expect.deepEqual(Controls.touchLayout(Vector2.new(1280, 720), 0.9, given).jump, given)
	end)

	-- Part 5 (§17.3.2, §17.12): End is treated like Cancel, so a hold always sees its release ----------------------

	-- A stand-in for the InputObject ContextActionService passes (gamepad ButtonX: no TextBox check, no trigger).
	local function gamepadX(): any
		return {
			KeyCode = Enum.KeyCode.ButtonX,
			UserInputType = Enum.UserInputType.Gamepad1,
			Position = Vector3.zero,
		}
	end

	t.test("Begin -> block -> End reaches the handler (and passes)", function()
		local Begin, End = Enum.UserInputState.Begin, Enum.UserInputState.End
		Controls.setContext("Lobby", true)
		local seen: { Enum.UserInputState } = {}
		local callback = Controls.casCallbackFor("Squeeze", function(state: Enum.UserInputState): boolean?
			table.insert(seen, state)
			return true
		end)
		local input = gamepadX()
		expect.equal(callback("SD_Squeeze", Begin, input), Enum.ContextActionResult.Sink)
		local release = Controls.block("modal")
		local ok, result = pcall(callback, "SD_Squeeze", End, input)
		release()
		expect.truthy(ok)
		expect.equal(result, Enum.ContextActionResult.Pass)
		expect.deepEqual(seen, { Begin, End })
	end)

	t.test("while not live, Begin never reaches the handler; End after a context change does", function()
		local Begin, End = Enum.UserInputState.Begin, Enum.UserInputState.End
		Controls.setContext("Lobby", true)
		local seen: { Enum.UserInputState } = {}
		local callback = Controls.casCallbackFor("Squeeze", function(state: Enum.UserInputState): boolean?
			table.insert(seen, state)
			return true
		end)
		local input = gamepadX()
		local release = Controls.block("modal")
		local okBlocked, blockedResult = pcall(callback, "SD_Squeeze", Begin, input)
		release()
		expect.truthy(okBlocked)
		expect.equal(blockedResult, Enum.ContextActionResult.Pass)
		expect.deepEqual(seen, {})
		-- A live Begin, then the Lobby context goes off (a match was found), then the release.
		expect.equal(callback("SD_Squeeze", Begin, input), Enum.ContextActionResult.Sink)
		Controls.setContext("Lobby", false)
		local okEnd, endResult = pcall(callback, "SD_Squeeze", End, input)
		Controls.setContext("Lobby", true)
		expect.truthy(okEnd)
		expect.equal(endResult, Enum.ContextActionResult.Pass)
		expect.deepEqual(seen, { Begin, End })
	end)

	-- Part 6 (§10.6, §11.7): the Inspect context ------------------------------------------------------------------------

	local INSPECT_ACTIONS: { [string]: { EnumItem } } = {
		InspectRotateKeys = { Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Up, Enum.KeyCode.Down },
		InspectZoomIn = { Enum.KeyCode.Equals, Enum.KeyCode.KeypadPlus },
		InspectZoomOut = { Enum.KeyCode.Minus, Enum.KeyCode.KeypadMinus },
		InspectWheel = { Enum.UserInputType.MouseWheel },
		InspectSqueeze = { Enum.KeyCode.F, Enum.KeyCode.ButtonX },
		InspectReset = { Enum.KeyCode.R, Enum.KeyCode.ButtonY },
		InspectStick = { Enum.KeyCode.Thumbstick2 },
		InspectZoomTriggers = { Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonL2 },
	}

	t.test("the eight §10.6 Inspect actions exist in the Inspect context with their keys", function()
		for action, keys in INSPECT_ACTIONS do
			expect.equal(Controls.contextOf(action), "Inspect")
			local inputs = Controls.inputsOf(action)
			expect.truthy(inputs ~= nil)
			expect.equal(#(inputs :: { any }), #keys)
			for _, key in keys do
				expect.truthy(table.find(inputs :: { any }, key) ~= nil)
			end
		end
	end)

	t.test("Inspect actions sink only while the Inspect context is on (and the handler handles them)", function()
		local Begin, End = Enum.UserInputState.Begin, Enum.UserInputState.End
		local Change = Enum.UserInputState.Change
		local Sink, Pass = Enum.ContextActionResult.Sink, Enum.ContextActionResult.Pass
		expect.falsy(Controls.isContextActive("Inspect"))
		local seen: { string } = {}
		local answer: boolean? = true
		local function handler(action: string)
			return function(state: Enum.UserInputState): boolean?
				table.insert(seen, action .. ":" .. state.Name)
				return answer
			end
		end
		local squeeze = Controls.casCallbackFor("InspectSqueeze", handler("squeeze"))
		local wheel = Controls.casCallbackFor("InspectWheel", handler("wheel"))
		local stick = Controls.casCallbackFor("InspectStick", handler("stick"))
		local buttonX =
			{ KeyCode = Enum.KeyCode.ButtonX, UserInputType = Enum.UserInputType.Gamepad1, Position = Vector3.zero }
		-- A wheel input has no key (KeyCode Unknown / None: neither name exists in every engine, so it is left out).
		local wheelInput = { UserInputType = Enum.UserInputType.MouseWheel, Position = Vector3.new(0, 0, 1) }
		local stickInput = {
			KeyCode = Enum.KeyCode.Thumbstick2,
			UserInputType = Enum.UserInputType.Gamepad1,
			Position = Vector3.new(0.5, 0, 0),
		}
		-- Context off: Pass, and only End reaches the handler.
		expect.equal(squeeze("SD_InspectSqueeze", Begin, buttonX :: any), Pass)
		expect.equal(wheel("SD_InspectWheel", Change, wheelInput :: any), Pass)
		expect.equal(stick("SD_InspectStick", Change, stickInput :: any), Pass)
		expect.deepEqual(seen, {})
		expect.equal(squeeze("SD_InspectSqueeze", End, buttonX :: any), Pass)
		expect.deepEqual(seen, { "squeeze:End" })
		table.clear(seen)
		-- Context on (with the modal block held, as while Inspect is open): Sink when the handler handles it.
		local release = Controls.block("inspect")
		Controls.setContext("Inspect", true)
		local okOn, results = pcall(function()
			return {
				squeeze("SD_InspectSqueeze", Begin, buttonX :: any),
				wheel("SD_InspectWheel", Change, wheelInput :: any),
				stick("SD_InspectStick", Change, stickInput :: any),
			}
		end)
		-- A handler that passes (e.g. Inspect is not the top modal, or the pointer is off the viewport) passes it on.
		answer = nil
		local okPass, passed = pcall(squeeze, "SD_InspectSqueeze", Begin, buttonX :: any)
		answer = true
		Controls.setContext("Inspect", false)
		release()
		expect.truthy(okOn)
		expect.deepEqual(results, { Sink, Sink, Sink })
		expect.truthy(okPass)
		expect.equal(passed, Pass)
		expect.deepEqual(seen, { "squeeze:Begin", "wheel:Change", "stick:Change", "squeeze:Begin" })
		expect.falsy(Controls.isContextActive("Inspect"))
		expect.falsy(Controls.isBlocked())
	end)

	t.test("Inspect's R2 / L2 zoom starts past the small deadzone; the throw keeps its 0.5 edge (§10.6)", function()
		local Change, Begin, End = Enum.UserInputState.Change, Enum.UserInputState.Begin, Enum.UserInputState.End
		local deadzone = Config.Inspect.Input.triggerDeadzone
		local throwEdge = Config.Combat.Aim.triggerThreshold
		expect.equal(deadzone, 0.05)
		expect.truthy(deadzone < throwEdge)
		expect.equal(Controls.triggerThresholdOf("InspectZoomTriggers"), deadzone)
		for _, action in { "Throw", "Ultimate", "PracticeThrow", "PracticeUltimate" } do
			expect.equal(Controls.triggerThresholdOf(action), throwEdge)
		end
		expect.equal(Controls.triggerThresholdOf("NoSuchAction"), nil)
		-- A 40 % press: the zoom begins (and then reads Position.Z each frame); the throw does not.
		local zoomDown, zoomEdge = Controls.triggerEdge(false, Change, 0.4, deadzone)
		expect.truthy(zoomDown)
		expect.equal(zoomEdge, Begin)
		local throwDown, throwEdgeState = Controls.triggerEdge(false, Change, 0.4, throwEdge)
		expect.falsy(throwDown)
		expect.equal(throwEdgeState, nil)
		-- Inside the deadzone nothing begins; letting go into it ends the zoom.
		local restDown, restEdge = Controls.triggerEdge(false, Change, deadzone / 2, deadzone)
		expect.falsy(restDown)
		expect.equal(restEdge, nil)
		local _, releaseEdge = Controls.triggerEdge(true, Change, deadzone / 2, deadzone)
		expect.equal(releaseEdge, End)
	end)

	t.test("Inspect's arrow keys sit above SD_MoveSink; the other actions keep their priorities", function()
		local high = Enum.ContextActionPriority.High.Value
		local medium = Enum.ContextActionPriority.Medium.Value
		local sink = Controls.moveSinkPriority()
		expect.equal(sink, high + 100)
		expect.truthy((Controls.priorityOfAction("InspectRotateKeys") :: number) > sink)
		for action in INSPECT_ACTIONS do
			if action ~= "InspectRotateKeys" then
				expect.equal(Controls.priorityOfAction(action), high)
			end
		end
		for _, action in { "ModalBack", "ModalTabPrevious", "ModalTabNext" } do
			expect.equal(Controls.priorityOfAction(action), high)
		end
		for _, action in
			{
				"Squeeze",
				"Squishies",
				"InspectEquipped",
				"FocusHud",
				"Throw",
				"Ultimate",
				"PracticeThrow",
				"PracticeUltimate",
			}
		do
			expect.equal(Controls.priorityOfAction(action), medium)
		end
		expect.equal(Controls.priorityOfAction("NoSuchAction"), nil)
	end)

	-- First person (spec 2026-10-10 §3.1, §3.5) ------------------------------------------------------------------------

	t.test(
		"DuelSqueeze and DuelForfeit sit in the Duel context, PracticeSqueeze in Practice, with their keys",
		function()
			-- Feature 1: E is the duel's catch (design: html:96), so DuelSqueeze keeps F and ButtonX.
			expect.deepEqual(Controls.inputsOf("DuelSqueeze"), { Enum.KeyCode.F, Enum.KeyCode.ButtonX })
			expect.deepEqual(
				Controls.inputsOf("PracticeSqueeze"),
				{ Enum.KeyCode.F, Enum.KeyCode.E, Enum.KeyCode.ButtonX }
			)
			expect.deepEqual(Controls.inputsOf("DuelForfeit"), { Enum.KeyCode.Backspace }) -- keyboard only
			expect.equal(Controls.contextOf("DuelSqueeze"), "Duel")
			expect.equal(Controls.contextOf("DuelForfeit"), "Duel")
			expect.equal(Controls.contextOf("PracticeSqueeze"), "Practice")
		end
	)

	t.test("PracticeSqueeze binds one step above the lobby Squeeze and under every High action", function()
		local medium = Enum.ContextActionPriority.Medium.Value
		local practice = Controls.priorityOfAction("PracticeSqueeze") :: number
		expect.equal(practice, medium + 1)
		expect.truthy(practice > (Controls.priorityOfAction("Squeeze") :: number))
		local highs = { "ModalBack", "ModalTabPrevious", "ModalTabNext" }
		for action in INSPECT_ACTIONS do
			table.insert(highs, action)
		end
		for _, action in highs do
			expect.truthy(practice < (Controls.priorityOfAction(action) :: number))
		end
		expect.equal(Controls.priorityOfAction("DuelSqueeze"), medium)
		expect.equal(Controls.priorityOfAction("DuelForfeit"), medium)
	end)

	t.test("the first-person squeezes run only in their own context; Inspect's F passes while it is closed", function()
		local Begin = Enum.UserInputState.Begin
		local Sink, Pass = Enum.ContextActionResult.Sink, Enum.ContextActionResult.Pass
		local seen: { string } = {}
		local function handler(name: string)
			return function(state: Enum.UserInputState): boolean?
				table.insert(seen, name .. ":" .. state.Name)
				return true
			end
		end
		local duel = Controls.casCallbackFor("DuelSqueeze", handler("duel"))
		local practice = Controls.casCallbackFor("PracticeSqueeze", handler("practice"))
		local inspect = Controls.casCallbackFor("InspectSqueeze", handler("inspect"))
		local input = gamepadX()
		local function pressAll(): { Enum.ContextActionResult }
			return {
				duel("SD_DuelSqueeze", Begin, input),
				practice("SD_PracticeSqueeze", Begin, input),
				inspect("SD_InspectSqueeze", Begin, input),
			}
		end
		local lobby = pressAll()
		Controls.setContext("Duel", true)
		local okDuel, inDuel = pcall(pressAll)
		Controls.setContext("Duel", false)
		Controls.setContext("Practice", true)
		local okPractice, inPractice = pcall(pressAll)
		Controls.setContext("Practice", false)
		expect.deepEqual(lobby, { Pass, Pass, Pass })
		expect.truthy(okDuel and okPractice)
		expect.deepEqual(inDuel, { Sink, Pass, Pass })
		expect.deepEqual(inPractice, { Pass, Sink, Pass })
		expect.deepEqual(seen, { "duel:Begin", "practice:Begin" })
	end)

	t.test("Backspace: ModalBack takes it while a back handler is pushed, else DuelForfeit runs", function()
		local Begin = Enum.UserInputState.Begin
		local Sink = Enum.ContextActionResult.Sink
		local seen: { string } = {}
		local function handler(name: string)
			return function(_state: Enum.UserInputState): boolean?
				table.insert(seen, name)
				return true
			end
		end
		local bound = {
			{ name = "ModalBack", callback = Controls.casCallbackFor("ModalBack", handler("ModalBack")) },
			{ name = "DuelForfeit", callback = Controls.casCallbackFor("DuelForfeit", handler("DuelForfeit")) },
		}
		-- ContextActionService offers a key to its bound actions from the highest priority down until one sinks.
		table.sort(bound, function(a: any, b: any): boolean
			return (Controls.priorityOfAction(a.name) :: number) > (Controls.priorityOfAction(b.name) :: number)
		end)
		-- A Backspace stand-in that is not typed Keyboard, so no TextBox check runs in Edit mode.
		local backspace: any =
			{ KeyCode = Enum.KeyCode.Backspace, UserInputType = Enum.UserInputType.Gamepad1, Position = Vector3.zero }
		local function dispatch(): string?
			for _, entry in bound do
				if entry.callback("SD_" .. entry.name, Begin, backspace) == Sink then
					return entry.name
				end
			end
			return nil
		end
		Controls.setContext("Duel", true)
		local okNone, withoutBack = pcall(dispatch)
		Controls.setContext("Modal", true) -- UIController.pushBack turns the Modal context on
		local okPushed, withBack = pcall(dispatch)
		Controls.setContext("Modal", false)
		Controls.setContext("Duel", false)
		expect.truthy(okNone and okPushed)
		expect.equal(withoutBack, "DuelForfeit")
		expect.equal(withBack, "ModalBack")
		expect.deepEqual(seen, { "DuelForfeit", "ModalBack" })
	end)

	-- Lobby HUD (spec 2026-10-11 lobby-hud-tap-squeeze §2): tap or click the world to squeeze --------------------------

	-- A pointer press on the 3D world in the lobby with nothing in the way.
	local function worldPress(kind: Enum.UserInputType): { [string]: any }
		return {
			kind = kind,
			processed = false,
			onGui = false,
			practice = false,
			thumbZone = false,
			onJump = false,
			touchDown = false,
		}
	end

	t.test("a left click or a touch on the world presses the lobby Squeeze; other inputs never do", function()
		expect.truthy(Controls.worldPointerPresses(worldPress(Enum.UserInputType.MouseButton1) :: any))
		expect.truthy(Controls.worldPointerPresses(worldPress(Enum.UserInputType.Touch) :: any))
		for _, kind in
			{
				Enum.UserInputType.MouseButton2, -- Roblox turns the camera with it
				Enum.UserInputType.MouseButton3,
				Enum.UserInputType.MouseMovement,
				Enum.UserInputType.Keyboard,
				Enum.UserInputType.Gamepad1,
			}
		do
			expect.falsy(Controls.worldPointerPresses(worldPress(kind) :: any))
		end
	end)

	t.test("never on the UI, in the practice box, on the thumbstick or jump button, nor a second finger", function()
		for _, kind in { Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch } do
			for _, field in { "processed", "onGui", "practice", "thumbZone", "onJump", "touchDown" } do
				local press = worldPress(kind)
				press[field] = true
				if Controls.worldPointerPresses(press :: any) then
					error(`a {kind.Name} press squeezed with {field} = true`)
				end
			end
		end
	end)

	t.test("the thumbstick zone is the lower-left 40% × 45% (touchLayout's zone)", function()
		local touch = Config.UI.Touch
		local screen = Vector2.new(1000, 400)
		local right, top = screen.X * touch.thumbstickZoneWidth, screen.Y * (1 - touch.thumbstickZoneHeight)
		expect.truthy(Controls.inThumbZone(Vector2.new(10, screen.Y - 10), screen)) -- the lower-left corner
		expect.truthy(Controls.inThumbZone(Vector2.new(right - 1, top + 1), screen))
		expect.falsy(Controls.inThumbZone(Vector2.new(right + 1, top + 1), screen)) -- right of it
		expect.falsy(Controls.inThumbZone(Vector2.new(right - 1, top - 1), screen)) -- above it (the tiles' band)
		expect.falsy(Controls.inThumbZone(Vector2.new(screen.X / 2, screen.Y / 2), screen)) -- the middle
		expect.falsy(Controls.inThumbZone(Vector2.new(10, 10), Vector2.zero)) -- no screen yet
	end)

	t.test(
		"pointerOnGui: a shown button, text box, Active object or a surface counts; clear or hidden ones do not",
		function()
			-- The GuiObjects PlayerGui:GetGuiObjectsAtPosition finds under the press.
			local clear: GuiObject = Instance.new("Frame") -- a full-HUD holder or the first-person overlay: no background
			clear.BackgroundTransparency = 1
			local text: GuiObject = Instance.new("TextLabel") -- a floating "+N" line
			text.BackgroundTransparency = 1
			local toast: GuiObject = Instance.new("Frame") -- a toast's panel or the coach card's body: a plain Frame
			local catcher: GuiObject = Instance.new("Frame") -- an Active click catcher, fully clear
			catcher.Active = true
			catcher.BackgroundTransparency = 1
			local hidden: GuiObject = Instance.new("TextButton")
			hidden.Visible = false
			local hiddenPanel: GuiObject = Instance.new("Frame")
			hiddenPanel.Visible = false
			expect.falsy(Controls.pointerOnGui({}))
			expect.falsy(Controls.pointerOnGui({ clear, text, hidden, hiddenPanel }))
			expect.truthy(Controls.pointerOnGui({ clear, toast }))
			expect.truthy(Controls.pointerOnGui({ catcher }))
			expect.truthy(Controls.pointerOnGui({ clear, Instance.new("TextButton") }))
			expect.truthy(Controls.pointerOnGui({ Instance.new("ImageButton") }))
			expect.truthy(Controls.pointerOnGui({ Instance.new("TextBox") }))
		end
	)

	t.test("the lobby Squeeze keeps its keys: world clicks come through UserInputService, not this binding", function()
		-- Binding the left mouse button to Squeeze would take practice-box clicks before PracticeThrow (the most
		-- recently bound action sees an input first), so the world pointer never goes through ContextActionService.
		local inputs = Controls.inputsOf("Squeeze") :: { EnumItem }
		expect.deepEqual(inputs, { Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.ButtonX })
		expect.truthy(table.find(Controls.inputsOf("PracticeThrow") :: { EnumItem }, Enum.UserInputType.MouseButton1))
	end)

	-- Spec phase 5 (user decision 2026-10-11): the dash is C and ButtonB in the Duel and Practice contexts, and a third
	-- round touch button in the Throw / Ultimate cluster.
	t.test("the dash: C and ButtonB in the Duel and Practice contexts, and no other duel action takes them", function()
		local function has(action: string, input: EnumItem): boolean
			local inputs = Controls.inputsOf(action)
			return inputs ~= nil and table.find(inputs, input) ~= nil
		end
		for _, action in { "Dash", "PracticeDash" } do
			expect.truthy(has(action, Enum.KeyCode.C))
			expect.truthy(has(action, Enum.KeyCode.ButtonB))
		end
		expect.equal(Controls.contextOf("Dash"), "Duel")
		expect.equal(Controls.contextOf("PracticeDash"), "Practice")
		for _, action in
			{
				"Throw",
				"Ultimate",
				"DuelSqueeze",
				"DuelForfeit",
				"PracticeThrow",
				"PracticeUltimate",
				"PracticeSqueeze",
				"Catch",
			}
		do
			expect.falsy(has(action, Enum.KeyCode.C))
			expect.falsy(has(action, Enum.KeyCode.ButtonB))
		end
	end)

	-- Feature 1 (2026-10-11): the catch.
	t.test("the catch: E and ButtonL1 in the Duel context, and no other duel action takes them", function()
		expect.deepEqual(Controls.inputsOf("Catch"), { Enum.KeyCode.E, Enum.KeyCode.ButtonL1 })
		expect.equal(Controls.contextOf("Catch"), "Duel")
		expect.equal(Controls.priorityOfAction("Catch"), Enum.ContextActionPriority.Medium.Value)
		for _, action in { "Throw", "Ultimate", "Dash", "DuelSqueeze", "DuelForfeit" } do
			local inputs = Controls.inputsOf(action) :: { EnumItem }
			expect.equal(table.find(inputs, Enum.KeyCode.E), nil)
			expect.equal(table.find(inputs, Enum.KeyCode.ButtonL1), nil)
		end
	end)

	t.test("the touch Catch button: its size, on screen, out of the thumbstick zone, apart from the others", function()
		local touch = Config.UI.Touch
		-- The phones, then big screens whose 120 px jump button crowds Throw's corner (the catch goes further out).
		local screens = {
			Vector2.new(1280, 720),
			Vector2.new(667, 375),
			Vector2.new(1920, 1080),
			Vector2.new(812, 375),
			Vector2.new(844, 390),
			Vector2.new(568, 320),
			Vector2.new(1024, 768),
			Vector2.new(1440, 900),
			Vector2.new(1024, 600),
			Vector2.new(2560, 1440),
		}
		for _, screen in screens do
			local scale = Controls.touchScale(screen)
			local layout = Controls.touchLayout(screen, scale, nil)
			local catch = layout.catch
			expect.near(catch.w, math.max(touch.catchButton * scale, touch.minTargetFloor), 1e-9)
			expect.truthy(catch.x >= 0 and catch.y >= 0)
			expect.truthy(catch.x + catch.w <= screen.X + 1e-6 and catch.y + catch.h <= screen.Y + 1e-6)
			local inZone = catch.x < screen.X * touch.thumbstickZoneWidth
				and catch.y + catch.h > screen.Y * (1 - touch.thumbstickZoneHeight)
			expect.falsy(inZone)
			local centre = Vector2.new(catch.x + catch.w / 2, catch.y + catch.h / 2)
			for _, other in { layout.throw, layout.ultimate, layout.dash } do
				local otherCentre = Vector2.new(other.x + other.w / 2, other.y + other.h / 2)
				expect.truthy((centre - otherCentre).Magnitude >= catch.w / 2 + other.w / 2 + touch.gap - 1e-3)
			end
			local jump = layout.jump
			local apart = catch.x + catch.w + touch.gap <= jump.x + 1e-6
				or jump.x + jump.w + touch.gap <= catch.x + 1e-6
				or catch.y + catch.h + touch.gap <= jump.y + 1e-6
				or jump.y + jump.h + touch.gap <= catch.y + 1e-6
			expect.truthy(apart)
		end
	end)

	t.test("the hand inspect: R and ButtonL1 in the Lobby context; no other world action takes them", function()
		expect.deepEqual(Controls.inputsOf("HandInspect"), { Enum.KeyCode.R, Enum.KeyCode.ButtonL1 })
		expect.equal(Controls.contextOf("HandInspect"), "Lobby")
		expect.equal(Controls.priorityOfAction("HandInspect"), Enum.ContextActionPriority.Medium.Value)
		for _, action in
			{
				"Squeeze",
				"Squishies",
				"InspectEquipped",
				"FocusHud",
				"Throw",
				"Ultimate",
				"PracticeThrow",
				"PracticeUltimate",
				"Dash",
				"PracticeDash",
				"DuelSqueeze",
				"DuelForfeit",
				"PracticeSqueeze",
			}
		do
			local inputs = Controls.inputsOf(action) :: { EnumItem }
			expect.equal(table.find(inputs, Enum.KeyCode.R), nil)
			expect.equal(table.find(inputs, Enum.KeyCode.ButtonL1), nil)
		end
		-- The overlay actions that share them only run while their own screen is open.
		expect.equal(Controls.contextOf("InspectReset"), "Inspect")
		expect.equal(Controls.contextOf("ModalTabPrevious"), "Modal")
		-- Feature 1: Catch takes ButtonL1 only in the Duel context, never on with the Lobby one; never R.
		expect.equal(Controls.contextOf("Catch"), "Duel")
		expect.equal(table.find(Controls.inputsOf("Catch") :: { EnumItem }, Enum.KeyCode.R), nil)
	end)

	t.test("the touch Dash button: its size, on screen, out of the thumbstick zone, apart from the others", function()
		local touch = Config.UI.Touch
		local screens = {
			Vector2.new(1280, 720),
			Vector2.new(667, 375),
			Vector2.new(1920, 1080),
			Vector2.new(812, 375),
			Vector2.new(844, 390),
		}
		for _, screen in screens do
			local scale = Controls.touchScale(screen)
			local layout = Controls.touchLayout(screen, scale, nil)
			local dash = layout.dash
			expect.near(dash.w, math.max(touch.dashButton * scale, touch.minTargetFloor), 1e-9)
			expect.truthy(dash.x >= 0 and dash.y >= 0)
			expect.truthy(dash.x + dash.w <= screen.X + 1e-6 and dash.y + dash.h <= screen.Y + 1e-6)
			local inZone = dash.x < screen.X * touch.thumbstickZoneWidth
				and dash.y + dash.h > screen.Y * (1 - touch.thumbstickZoneHeight)
			expect.falsy(inZone)
			local centre = Vector2.new(dash.x + dash.w / 2, dash.y + dash.h / 2)
			for _, other in { layout.throw, layout.ultimate } do
				local otherCentre = Vector2.new(other.x + other.w / 2, other.y + other.h / 2)
				expect.truthy((centre - otherCentre).Magnitude >= dash.w / 2 + other.w / 2 + touch.gap - 1e-3)
			end
			local jump = layout.jump
			local apart = dash.x + dash.w + touch.gap <= jump.x + 1e-6
				or jump.x + jump.w + touch.gap <= dash.x + 1e-6
				or dash.y + dash.h + touch.gap <= jump.y + 1e-6
				or jump.y + jump.h + touch.gap <= dash.y + 1e-6
			expect.truthy(apart)
		end
	end)

	-- UI FINAL R2 (PR1): one scale for the touch buttons and every layout that keeps clear of them.
	t.test("touchScale is the HUD's UI scale (Layout.uiScale of the width and the height)", function()
		local Layout = t.requireClient("UI/Layout")
		for _, screen in
			{
				Vector2.new(1280, 720),
				Vector2.new(1920, 1080),
				Vector2.new(1024, 768),
				Vector2.new(844, 390),
				Vector2.new(390, 844),
			}
		do
			expect.near(Controls.touchScale(screen), Layout.uiScale(screen.Y, screen.X), 1e-12)
		end
		-- A tablet: the width decides (1024 / 1440 = .71, held at the floor .85), as the HUD's own scale.
		expect.near(Controls.touchScale(Vector2.new(1024, 768)), Config.UI.Scale.min, 1e-12)
	end)

	t.test("touch buttons keep 16 px from the jump button read from TouchGui", function()
		local touch = Config.UI.Touch
		local screen = Vector2.new(1280, 720)
		local jump = { x = 1100, y = 560, w = 120, h = 120 }
		local layout = Controls.touchLayout(screen, 1, jump)
		local throw = layout.throw
		expect.near(throw.x + throw.w + touch.gap, jump.x, 1e-9)
		expect.near(throw.y + throw.h, jump.y + jump.h, 1e-9) -- bottoms aligned
		expect.near(throw.w, touch.throwButton, 1e-9)
	end)
	-- Pens3 phase 13 ------------------------------------------------------------------------------------------------

	t.test("pens3 phase 13: HighwayThrow = left mouse, ButtonR2 and the touch Throw in the Highway context", function()
		local inputs = Controls.inputsOf("HighwayThrow") :: { EnumItem }
		expect.truthy(table.find(inputs, Enum.UserInputType.MouseButton1) ~= nil)
		expect.truthy(table.find(inputs, Enum.KeyCode.ButtonR2) ~= nil)
		expect.equal(Controls.contextOf("HighwayThrow"), "Highway")
		expect.equal(Controls.priorityOfAction("HighwayThrow"), Enum.ContextActionPriority.Medium.Value)
	end)

	t.test(
		"pens3 phase 13: the Highway context switches on and off (engine only: it refreshes the touch gui)",
		function()
			Controls.setContext("Highway", true)
			expect.truthy(Controls.isContextActive("Highway"))
			expect.truthy(table.find(Controls.activeContexts(), "Highway") ~= nil)
			Controls.setContext("Highway", false)
			expect.falsy(Controls.isContextActive("Highway"))
		end
	)

	t.test("pens3 phase 13: the Highway context shows only the touch Throw button", function()
		local highway = { Lobby = true, Highway = true }
		expect.truthy(Controls.touchContextAllows("Throw", highway))
		for _, button in { "Ultimate", "Dash", "Catch" } do
			expect.falsy(Controls.touchContextAllows(button, highway))
		end
		local duel = { Duel = true }
		for _, button in { "Throw", "Ultimate", "Dash", "Catch" } do
			expect.truthy(Controls.touchContextAllows(button, duel))
		end
		local practice = { Lobby = true, Practice = true }
		expect.truthy(Controls.touchContextAllows("Dash", practice))
		expect.truthy(Controls.touchContextAllows("Ultimate", practice))
		expect.falsy(Controls.touchContextAllows("Catch", practice)) -- nothing throws at you in practice
	end)
end
