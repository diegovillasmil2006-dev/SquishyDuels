--!strict
-- BaseService_Test: unit tests for ServerScriptService.Server.Services.BaseService with injected fakes (a recorded
-- task.delay that the test runs by hand, a fake plot spawn); players are Folder instances (they carry the SD_Plot
-- attribute) or plain tables. Server only (ServerStorage.UnitTest). Edit mode: no Player, no world.
-- Contract (lobby bases spec 2026-10-11 §2, §4, §6; Neon Sugar lobby part 4, 2026-10-24: the plots are Diego's pens):
--   * 12 plots (WorldLayout.Bases); a joining player gets the lowest free plot, shown in the SD_Plot attribute; a plot
--     freed on leave is handed out again; rejoining gives the lowest free plot (the pen lives in the profile);
--   * with no plot free the player waits in the hub: the service tries again every 0.5 s for 5 s (10 tries) and gives
--     the plot that frees meanwhile; after 5 s it stops; a waiting player who leaves stops the retries;
--   * the plot's spawn is asked for the plot handed out and used only once the world has one;
--   * the owner view: an owned pen's arch nameplate (Diego's Label_OpenPlot "Text") shows the owner's display name, an
--     open plot "OPEN PLOT"; no plot colours (owner 2026-10-24);
--   * the pen (pens3; wb: the pen is the whole base): the owner's pen from their ready profile, in a "Pen" Folder: the
--     base Model's SD_PenSpots / SD_Pen / SD_PenRate / SD_PenTier / SD_PenOwner for the clients; refresh(player)
--     redraws (no duplicates); an open plot, a profile that is not ready or a missing plot model draws no pen and
--     nothing fails;
--   * the gate (LK:87-96) at Bases.pen.gate: posts in the tier's post colour, the sign frame in Diego's board frame
--     colour, the owner sign (display name, "BASE n", the headshot asked once per user and cached), the number badge n
--     and the visitor board ("0 visitors" until phase 18); no bulbs, bow, lamps, trees or shelf model at any tier
--     (owner 2026-10-24);
--   * every pen state draws exactly Bases.pen.maxParts parts (the gate's 8 and the 2 buy spots), all in front of the
--     arch, off the squishies' floor, and fits Budgets.baseParts with the plot's 80;
--   * the board (Diego's PenBoard, the "Board" SurfaceGui adorned to the pen's SignFace): boardRows gives row 1 PEN
--     SPACE (open spots of maxSpots, the next spot's price) and row 2 SHELF SPOTS (the open shelf spots with the TOP
--     spot, of 9); each BUY with its price, MAX when nothing is left; PenBoard.setState paints a viewer's own state
--     (grey "Need N more", BUY, MAX) without touching the price;
--   * the buy spots: "Sign" (SD_PenSign, PenPrompt on E / ButtonX) and "ShelfSign" (SD_ShelfSign, ShelfPrompt on F /
--     ButtonY) at Bases.pen.signs, each an invisible Face with SD_Price = the next buy's price and a hold prompt; no
--     price and the prompt off at MAX;
--   * Diego's 12 cubbies: an open shelf slot's cubby hides its Lock (no collision) on a PenShelfBackOn back, a closed
--     one shows it on PenShelfBackOff; cubby k = slot maxSpots + k, the TOP spot cubby 9, 10-12 closed until part 5;
--     an open plot has every cubby closed; SD_Pen holds the pen's walkers, SD_Shelf the shelf's and the TOP spot's;
--   * Batch 3 (friends): a player who joined from a friend's invite (or followed them) gets the free plot nearest to
--     the friend's on the ring (a tie: the lower number); with the friend gone or every plot taken, as before.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireServer: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local BaseService = t.requireServer("Services/BaseService")
	local WorldLayout = t.requireShared("World/WorldLayout")

	type World = {
		delays: { { seconds: number, fn: () -> () } },
		asked: { number },
		made: { Instance },
		models: { [number]: Model }, -- the fake plot models (owner view)
		pens: { [any]: any }, -- player -> a ready profile's pen
		friends: { [any]: any }, -- player -> the friend who invited them (or whom they followed) in this server
		headshots: { { id: number, done: (image: string?) -> () } }, -- pens3 phase 10: the headshots asked for
	}

	local function fresh(): World
		local w: World = { delays = {}, asked = {}, made = {}, models = {}, pens = {}, friends = {}, headshots = {} }
		BaseService.reset()
		BaseService.useDeps({
			delay = function(seconds: number, fn: () -> ())
				table.insert(w.delays, { seconds = seconds, fn = fn })
			end,
			spawnOf = function(plot: number): any
				table.insert(w.asked, plot)
				return nil -- these cases build no plot spawn
			end,
			plotModel = function(plot: number): Model?
				return w.models[plot]
			end,
			penOf = function(player: any): any
				return w.pens[player]
			end,
			displayNameOf = function(player: any): string
				return "Name of " .. tostring(if typeof(player) == "Instance" then player.Name else "table")
			end,
			friendOf = function(player: any): any
				return w.friends[player]
			end,
			headshotOf = function(userId: number, done: (image: string?) -> ())
				table.insert(w.headshots, { id = userId, done = done })
			end,
		})
		return w
	end

	local function finish(w: World)
		BaseService.reset()
		BaseService.useDeps(nil)
		for _, instance in w.made do
			instance:Destroy()
		end
	end

	local function newPlayer(w: World, name: string): any
		local player = Instance.new("Folder")
		player.Name = name
		table.insert(w.made, player)
		return player
	end

	-- Runs the delayed calls scheduled so far (one round of retries). Returns how many ran.
	local function runDelays(w: World): number
		local due = w.delays
		w.delays = {}
		for _, call in due do
			expect.equal(call.seconds, 0.5)
			call.fn()
		end
		return #due
	end

	-- Fills every plot; returns the players in plot order.
	local function fill(w: World): { any }
		local players = {}
		for index = 1, #WorldLayout.Bases.frames do
			local player = newPlayer(w, "P" .. index)
			BaseService.playerAdded(player)
			players[index] = player
		end
		return players
	end

	t.test("12 plots (Diego's pens), the lowest free one per joining player, in the SD_Plot attribute; leaving frees it", function()
		local w = fresh()
		expect.equal(#WorldLayout.Bases.frames, 12)
		local a, b, c = newPlayer(w, "A"), newPlayer(w, "B"), newPlayer(w, "C")
		for _, player in { a, b, c } do
			BaseService.playerAdded(player)
		end
		expect.equal(BaseService.plotOf(a), 1)
		expect.equal(BaseService.plotOf(b), 2)
		expect.equal(BaseService.plotOf(c), 3)
		expect.equal(b:GetAttribute("SD_Plot"), 2)
		expect.equal(BaseService.ownerOf(3), c)
		expect.deepEqual(w.asked, { 1, 2, 3 }) -- each plot's spawn is asked for (none exists before Phase 4)
		BaseService.playerRemoving(b)
		expect.equal(BaseService.plotOf(b), nil)
		expect.equal(BaseService.ownerOf(2), nil) -- an open plot again
		local d = newPlayer(w, "D")
		BaseService.playerAdded(d)
		expect.equal(BaseService.plotOf(d), 2) -- the lowest free one
		-- Rejoining gives the lowest free plot, maybe another one (the pen lives in the profile).
		BaseService.playerAdded(b)
		expect.equal(BaseService.plotOf(b), 4)
		expect.equal(#w.delays, 0)
		-- A player who is not an Instance (a plain table) gets a plot too, without the attribute.
		local plain = { UserId = 5 }
		BaseService.playerAdded(plain :: any)
		expect.equal(BaseService.plotOf(plain), 5)
		finish(w)
	end)

	t.test(
		"a friend's invite (Batch 3): the free plot nearest the friend's on the ring; ties take the lower",
		function()
			local w = fresh()
			local players = fill(w)
			for _, plot in { 2, 3, 4, 6, 9 } do
				BaseService.playerRemoving(players[plot])
			end
			local near = newPlayer(w, "Near")
			w.friends[near] = players[5] -- on plot 5: 4 and 6 are both one away, the lower wins
			BaseService.playerAdded(near)
			expect.equal(BaseService.plotOf(near), 4)
			local wrap = newPlayer(w, "Wrap")
			w.friends[wrap] = players[1] -- on plot 1: plot 12 is taken, 3 is two away, 2 is one away
			BaseService.playerAdded(wrap)
			expect.equal(BaseService.plotOf(wrap), 2)
			BaseService.playerRemoving(players[12])
			local ring = newPlayer(w, "Ring")
			w.friends[ring] = players[1] -- plot 12 (one away round the ring) beats plot 3 (two away)
			BaseService.playerAdded(ring)
			expect.equal(BaseService.plotOf(ring), 12)
			local lone = newPlayer(w, "Lone")
			w.friends[lone] = newPlayer(w, "Gone") -- a friend without a plot (not in this server): the lowest free one
			BaseService.playerAdded(lone)
			expect.equal(BaseService.plotOf(lone), 3)
			finish(w)
		end
	)

	t.test("a friend's invite with every plot taken waits in the hub like anyone", function()
		local w = fresh()
		local players = fill(w)
		local late = newPlayer(w, "Late")
		w.friends[late] = players[4]
		BaseService.playerAdded(late)
		expect.equal(BaseService.plotOf(late), nil)
		BaseService.playerRemoving(players[8])
		runDelays(w)
		expect.equal(BaseService.plotOf(late), 8)
		finish(w)
	end)

	-- The owner view (Neon Sugar part 4: Diego's pens) --------------------------------------------------------------

	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local Format = t.requireShared("Util/Format")
	local Config = t.requireShared("Config")
	local PenMath = t.requireShared("PenMath")
	local PenBoard = t.requireShared("World/PenBoard")
	local PEN = WorldLayout.Bases.pen
	local PRICES = Config.Economy.Pen.spotPrices
	local TIERS = { -- the gate posts' tier colours (wb: no pen fence)
		{ post = Palette.PenFenceWaferPost },
		{ post = Palette.PenFenceMintPost },
		{ post = Palette.PenFenceRoyalPost },
	}

	-- A pen Model like Diego's: the arch nameplate (Label_OpenPlot > LabelGui > Background > Text, "OPEN PLOT"), the
	-- board's SignFace and the 12 ShelfSlots (each a Lock Model of 2 parts and a ShelfBack), all as he delivers them.
	local function plotModel(w: World, plot: number): Model
		local model = Instance.new("Model")
		model.Name = string.format("Pen_%02d", plot)
		local plate = Instance.new("Part")
		plate.Name = "Label_OpenPlot"
		local gui = Instance.new("SurfaceGui")
		gui.Name = "LabelGui"
		local background = Instance.new("Frame")
		background.Name = "Background"
		local text = Instance.new("TextLabel")
		text.Name = "Text"
		text.Text = "OPEN PLOT"
		text.Parent = background
		background.Parent = gui
		gui.Parent = plate
		plate.Parent = model
		local face = Instance.new("Part")
		face.Name = "SignFace"
		face.Parent = model
		local slots = Instance.new("Folder")
		slots.Name = "ShelfSlots"
		for k = 1, 12 do
			local slot = Instance.new("Model")
			slot.Name = string.format("ShelfSlot_%02d", k)
			local lock = Instance.new("Model")
			lock.Name = "Lock"
			for _ = 1, 2 do
				Instance.new("Part").Parent = lock
			end
			lock.Parent = slot
			local back = Instance.new("Part")
			back.Name = "ShelfBack"
			back.Parent = slot
			slot.Parent = slots
		end
		slots.Parent = model
		w.models[plot] = model
		table.insert(w.made, model)
		return model
	end

	-- A ready profile's pen (Types.PenState) with `spots` open spots and the given kinds (ids 1, 2, ...); pens3 phase
	-- 11: `rows` shelf rows (default the start row, as every sanitized save has) and the TOP spot `top`.
	local function pen(spots: number, kinds: { string }?, rows: number?, top: boolean?): any
		local items = {}
		for index, kind in (kinds or { "kitty_bread" }) :: { string } do
			-- Pens3 phase 6: the kinds sit in spots 1, 2, ... in order (the rest in the Toy Box).
			items[index] = {
				id = index,
				kind = kind,
				form = 0,
				level = 1,
				coat = 0,
				slot = if index <= spots then index else 0,
				locked = false,
			}
		end
		return { spots = spots, nextId = #items + 1, items = items, shelfRows = rows or 1, top = top == true }
	end

	local function ownerText(model: Model): string
		return ((model:FindFirstChild("Label_OpenPlot") :: Instance):FindFirstChild("Text", true) :: TextLabel).Text
	end

	local function count(parent: Instance, name: string): number
		local n = 0
		for _, child in parent:GetChildren() do
			if child.Name == name then
				n += 1
			end
		end
		return n
	end

	t.test("an owned pen's arch nameplate shows its owner's name; an open plot OPEN PLOT (no plot colours)", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		BaseService.playerAdded(a)
		expect.equal(ownerText(model), "Name of A")
		BaseService.playerRemoving(a)
		expect.equal(ownerText(model), "OPEN PLOT")
		expect.equal(Strings.resolve("base.openPlot"), "OPEN PLOT")
		local model2 = plotModel(w, 2)
		BaseService.playerAdded(newPlayer(w, "B"))
		BaseService.playerAdded(newPlayer(w, "C"))
		expect.equal(ownerText(model2), "Name of C")
		finish(w)
	end)

	-- Pens3 phase 1: the pen ---------------------------------------------------------------------------------------

	t.test("the base Model's pen attributes for the clients; an open plot clears them", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(3, { "kitty_bread", "butter" })
		BaseService.playerAdded(a)
		expect.equal(model:GetAttribute("SD_PenSpots"), 3)
		expect.equal(model:GetAttribute("SD_Pen"), "kitty_bread.0.1.0;butter.0.1.0") -- spot order (PenMath.placed)
		expect.equal(model:GetAttribute("SD_PenRate"), 50)
		expect.equal(model:GetAttribute("SD_PenTier"), 1)
		expect.equal(model:GetAttribute("SD_Pen"), PenMath.encode(PenMath.placed(w.pens[a])))
		w.pens[a] = pen(6, { "kitty_bread", "butter", "bird" })
		BaseService.refresh(a)
		expect.equal(model:GetAttribute("SD_PenSpots"), 6)
		expect.equal(model:GetAttribute("SD_PenTier"), 2) -- Mint from 6 spots
		expect.equal(model:GetAttribute("SD_PenRate"), 210)
		BaseService.playerRemoving(a)
		for _, name in { "SD_PenSpots", "SD_Pen", "SD_PenRate", "SD_PenTier" } do
			expect.equal(model:GetAttribute(name), nil)
		end
		expect.equal(model:FindFirstChild("Pen"), nil)
		finish(w)
	end)

	-- Pens3 phase 10: the gate with the owner's photo (owner 2026-10-24: kept, no bulbs or bow) ------------------------

	-- `part`'s centre in `at`'s frame.
	local function localOf(at: CFrame, part: Instance): Vector3
		return at:PointToObjectSpace((part :: BasePart).CFrame.Position)
	end

	local function named(parent: Instance, name: string): { BasePart }
		local list = {}
		for _, d in parent:GetDescendants() do
			if d.Name == name and d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	local function vectorNear(a: Vector3, b: Vector3): boolean
		return (a - b).Magnitude < 1e-3
	end

	t.test("the gate (LK:87-96): posts, the frame, the owner sign, the badge, 0 visitors; no bulbs or bow", function()
		local w = fresh()
		local model2 = plotModel(w, 2)
		local model = plotModel(w, 1)
		local a = { UserId = 77 } -- a plain-table player with a UserId (Folder players have none)
		w.pens[a] = pen(12) -- tier III: still no bulbs or bow
		BaseService.playerAdded(a :: any)
		local gate = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Gate") :: Model
		expect.truthy((gate :: Model?) ~= nil and gate:IsA("Model"))
		local at = (WorldLayout.plotFrame(1) :: CFrame) * PEN.gate
		expect.near((gate.WorldPivot.Position - at.Position).Magnitude, 0, 1e-3)
		expect.near((gate.WorldPivot.LookVector - at.LookVector).Magnitude, 0, 1e-3)
		expect.equal(model:GetAttribute("SD_PenOwner"), 77)
		-- The posts: r 0.6, 12 tall at x ±4, balls r 0.8 at y 12.3, in the tier's post colour; they block (K:
		-- "block").
		local posts = named(gate, "GatePost")
		expect.equal(#posts, 2)
		for _, post in posts do
			expect.near(post.Size.X, 12, 1e-3)
			expect.near(post.Size.Y, 1.2, 1e-3)
			local p = localOf(at, post)
			expect.near(math.abs(p.X), 4, 1e-3)
			expect.near(p.Y, 6, 1e-3)
			expect.equal(post.Color, TIERS[3].post)
			expect.truthy(post.CanCollide)
		end
		local balls = named(gate, "GatePostTop")
		expect.equal(#balls, 2)
		expect.near(balls[1].Size.X, 1.6, 1e-3)
		expect.near(localOf(at, balls[1]).Y, 12.3, 1e-3)
		-- The sign frame (8.4 × 3.6 × 0.3 from y 8.4, z 0.3) in Diego's board frame colour (no plot colours).
		local frameBox = named(gate, "SignFrame")[1]
		expect.truthy(vectorNear(frameBox.Size, Vector3.new(8.4, 3.6, 0.3)))
		expect.truthy(vectorNear(localOf(at, frameBox), Vector3.new(0, 10.2, 0.3)))
		expect.equal(frameBox.Color, Palette.PenBoardFrame)
		-- The owner sign (7.4 × 3 × 0.4 at y 10.2): the display name, BASE 1 and the headshot, on its front.
		local sign = named(gate, "OwnerSign")[1]
		expect.truthy(vectorNear(sign.Size, Vector3.new(7.4, 3, 0.4)))
		expect.truthy(vectorNear(localOf(at, sign), Vector3.new(0, 10.2, 0)))
		expect.equal(sign.Color, Palette.PenSignFace)
		local gui = sign:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
		expect.equal(gui.Face, Enum.NormalId.Front)
		expect.equal((gui:FindFirstChild("OwnerName", true) :: TextLabel).Text, "Name of table")
		expect.equal((gui:FindFirstChild("BaseLine", true) :: TextLabel).Text, "BASE 1")
		expect.truthy((gui:FindFirstChild("Headshot", true) :: ImageLabel):IsA("ImageLabel"))
		-- The number badge (a Lemon disc r 1.1 facing the front at y 12.6) reads the base number.
		local badge = named(gate, "NumberBadge")[1] :: Part
		expect.equal(badge.Shape, Enum.PartType.Cylinder)
		expect.truthy(vectorNear(badge.Size, Vector3.new(0.4, 2.2, 2.2)))
		expect.truthy(vectorNear(localOf(at, badge), Vector3.new(0, 12.6, -0.1)))
		expect.equal(badge.Color, Palette.PenGateBadge)
		local badgeGui = badge:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
		-- Its Right face (the cylinder's +X end) looks the way the gate's front does.
		expect.truthy(vectorNear(badge.CFrame.RightVector, at.LookVector))
		expect.equal(badgeGui.Face, Enum.NormalId.Right)
		expect.equal((badgeGui:FindFirstChild("Number", true) :: TextLabel).Text, "1")
		-- The visitor board (2.6 × 1.2 × 0.25 at (-2.3, 7.55, -0.05)): a heart and 0 visitors until phase 18.
		local board = named(gate, "VisitorBoard")[1]
		expect.truthy(vectorNear(board.Size, Vector3.new(2.6, 1.2, 0.25)))
		expect.truthy(vectorNear(localOf(at, board), Vector3.new(-2.3, 7.55, -0.05)))
		expect.equal(board.Color, Palette.PenGateBoard)
		expect.equal((board:FindFirstChild("Heart", true) :: TextLabel).Text, Strings.pen.gate.heart)
		expect.equal((board:FindFirstChild("Count", true) :: TextLabel).Text, "0 visitors")
		-- Owner 2026-10-24: no tier extras at any tier (bulbs, bow, lamps, trees).
		expect.equal(#named(gate, "GateBulb"), 0)
		expect.equal(gate:FindFirstChild("Bow"), nil)
		local folder = model:FindFirstChild("Pen") :: Instance
		expect.equal(count(folder, "Lamp") + count(folder, "Tree") + count(folder, "Shelf"), 0)
		-- Every part but the posts stays out of collisions; none is queried, touched or casts a shadow.
		for _, d in gate:GetDescendants() do
			if d:IsA("BasePart") then
				expect.truthy(d.Anchored)
				expect.falsy(d.CanQuery or d.CanTouch or d.CastShadow)
				expect.equal(d.CanCollide, d.Name == "GatePost")
			end
		end
		-- The arch nameplate still shows the owner.
		expect.equal(ownerText(model), "Name of table")
		-- The second plot reads 2.
		local b = newPlayer(w, "B")
		w.pens[b] = pen(3)
		BaseService.playerAdded(b)
		local gate2 = (model2:FindFirstChild("Pen") :: Instance):FindFirstChild("Gate") :: Model
		expect.equal((gate2:FindFirstChild("Number", true) :: TextLabel).Text, "2")
		expect.equal((gate2:FindFirstChild("BaseLine", true) :: TextLabel).Text, "BASE 2")
		expect.equal(model2:GetAttribute("SD_PenOwner"), nil) -- a Folder player has no UserId
		BaseService.playerRemoving(a :: any)
		expect.equal(model:GetAttribute("SD_PenOwner"), nil)
		finish(w)
	end)

	t.test("wb: the gate posts and their balls take the tier's post colour: Wafer, Mint, Royal (L:187)", function()
		for _, spots in { 3, 6, 10 } do
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(spots)
			BaseService.playerAdded(a)
			local gate = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Gate") :: Instance
			local parts = named(gate, "GatePost")
			table.move(named(gate, "GatePostTop"), 1, 2, 3, parts)
			expect.equal(#parts, 4)
			for _, part in parts do
				expect.equal(part.Color, TIERS[PEN.steps[spots].tier].post)
			end
			finish(w)
		end
	end)

	t.test("visitorText: the hearts board's line (P3D:277), 1 visitor or N visitors", function()
		expect.equal(BaseService.visitorText(0), "0 visitors")
		expect.equal(BaseService.visitorText(1), "1 visitor")
		expect.equal(BaseService.visitorText(3), "3 visitors")
	end)

	t.test("the headshot: asked once per user, cached, painted when it comes; asked again after a failure", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = { UserId = 77 }
		w.pens[a] = pen(3)
		BaseService.playerAdded(a :: any)
		local function image(): string
			local gate = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Gate") :: Instance
			return (gate:FindFirstChild("Headshot", true) :: ImageLabel).Image
		end
		expect.equal(#w.headshots, 1)
		expect.equal(w.headshots[1].id, 77)
		expect.equal(image(), "")
		BaseService.refresh(a :: any) -- still asking: not asked twice
		expect.equal(#w.headshots, 1)
		w.headshots[1].done("rbxthumb://type=AvatarHeadShot&id=77&w=150&h=150")
		expect.equal(image(), "rbxthumb://type=AvatarHeadShot&id=77&w=150&h=150") -- painted on the gate there now
		BaseService.refresh(a :: any)
		expect.equal(#w.headshots, 1) -- cached
		expect.equal(image(), "rbxthumb://type=AvatarHeadShot&id=77&w=150&h=150")
		-- A failed ask (nil) is asked again on the next draw; a Folder player (no UserId) asks nothing.
		plotModel(w, 2)
		plotModel(w, 3)
		local b = { UserId = 88 }
		w.pens[b] = pen(3)
		BaseService.playerAdded(b :: any)
		expect.equal(#w.headshots, 2)
		w.headshots[2].done(nil)
		BaseService.refresh(b :: any)
		expect.equal(#w.headshots, 3)
		local c = newPlayer(w, "C")
		w.pens[c] = pen(3)
		BaseService.playerAdded(c)
		expect.equal(#w.headshots, 3)
		finish(w)
	end)

	-- The parts a pen draws: the lobby budget counts every plot with Bases.pen.maxParts.
	local function drawn(spots: number, rows: number, top: boolean): (World, Model)
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(spots, nil, rows, top)
		BaseService.playerAdded(a)
		return w, model
	end

	local function partsIn(instance: Instance): { BasePart }
		local list = {}
		for _, d in instance:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
		return list
	end

	t.test("every pen state draws Bases.pen.maxParts parts (the gate's 8, 2 buy spots), none on the floor", function()
		expect.truthy(PEN.maxParts + 80 <= WorldLayout.Budgets.baseParts)
		local frame = WorldLayout.plotFrame(1) :: CFrame
		for spots = 3, 12 do
			for rows = 1, Config.Economy.Pen.shelfMaxRows do
				for _, top in { false, true } do
					local w, model = drawn(spots, rows, top)
					local parts = partsIn(model:FindFirstChild("Pen") :: Instance)
					expect.equal(#parts, PEN.maxParts)
					-- Everything stands in front of the arch, off the squishies' floor (no squishy walks through it).
					for _, part in parts do
						local p = frame:PointToObjectSpace(part.Position)
						if p.Z - part.Size.Magnitude / 2 <= PEN.walk.maxZ then
							error(`{spots} spots: {part:GetFullName()} reaches the pen's floor`)
						end
					end
					finish(w)
				end
			end
		end
	end)

	-- Neon Sugar part 4: Diego's board, its buy spots and his shelf cubbies ---------------------------------------

	local function boardOf(model: Model): SurfaceGui
		return (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Board") :: SurfaceGui
	end

	local function text(card: Instance, ...: string): string
		local found: Instance = card
		for _, name in { ... } do
			found = found:FindFirstChild(name) :: Instance
		end
		return (found :: TextLabel).Text
	end

	t.test("boardRows: PEN SPACE (spots of 12, the next spot's price), SHELF SPOTS (of 9 with the TOP spot)", function()
		local penRow, shelfRow = BaseService.boardRows(pen(3))
		expect.deepEqual(penRow, {
			title = "PEN SPACE",
			icon = "shelf",
			from = "3",
			to = "4 spots",
			filled = 3,
			total = 12,
			progress = "3/12",
			price = Format.coins(PRICES[4]),
			state = "buy",
		})
		expect.deepEqual(shelfRow, {
			title = "SHELF SPOTS",
			icon = "shelf",
			from = "2",
			to = "4 spots",
			filled = 2,
			total = 9,
			progress = "2/9",
			price = Format.coins(31_000_000),
			state = "buy",
		})
		-- Every shelf row bought: the TOP spot is next (one spot); everything bought: MAX, the count after the arrow.
		local _, beforeTop = BaseService.boardRows(pen(12, nil, 4, false))
		expect.equal(beforeTop.from, "8")
		expect.equal(beforeTop.to, "9 spots")
		local fullPen, fullShelf = BaseService.boardRows(pen(12, nil, 4, true))
		expect.equal(fullPen.state, "max")
		expect.equal(fullPen.price, "")
		expect.equal(fullPen.to, "12 spots")
		expect.equal(fullPen.progress, "12/12")
		expect.equal(fullShelf.state, "max")
		expect.equal(fullShelf.progress, "9/9")
	end)

	t.test("the board: Diego's 2 rows on the pen's SignFace for everyone, BUY with a price or MAX", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(3)
		BaseService.playerAdded(a)
		local board = boardOf(model)
		expect.truthy((board :: SurfaceGui?) ~= nil and board:IsA("SurfaceGui"))
		expect.equal(board.Adornee, model:FindFirstChild("SignFace"))
		expect.equal(board.Face, Enum.NormalId.Front)
		expect.equal(board.CanvasSize, Vector2.new(1024, 640))
		local row1, row2 = PenBoard.row(board, 1) :: Frame, PenBoard.row(board, 2) :: Frame
		expect.equal(text(row1, "Title"), "PEN SPACE")
		expect.equal(text(row2, "Title"), "SHELF SPOTS")
		expect.equal(text(row1, "Detail", "From"), "3")
		expect.equal(text(row1, "Detail", "To"), "4 spots")
		expect.equal(text(row1, "ProgressText"), "3/12")
		expect.equal(text(row1, "Button", "Content", "Price"), Format.coins(PRICES[4]))
		expect.equal(text(row1, "Caption"), "BUY")
		expect.equal((row1:FindFirstChild("Button") :: Frame).BackgroundColor3, Palette.PenBoardGo)
		local segments = (row1:FindFirstChild("Progress") :: Frame):GetChildren()
		expect.equal(#segments, 12)
		local lit = 0
		for _, segment in segments do
			if (segment :: Frame).BackgroundColor3 == Palette.PenBoardFill then
				lit += 1
			end
		end
		expect.equal(lit, 3)
		expect.equal(#(row2:FindFirstChild("Progress") :: Frame):GetChildren(), 9)
		-- Both rows bought out: MAX, gold, no coin, no caption, every segment lit.
		w.pens[a] = pen(12, nil, 4, true)
		BaseService.refresh(a)
		row1 = PenBoard.row(boardOf(model), 1) :: Frame
		expect.equal(text(row1, "Button", "Content", "Price"), Strings.pen.sign.max)
		expect.equal(text(row1, "Caption"), "")
		expect.equal((row1:FindFirstChild("Button") :: Frame).BackgroundColor3, Palette.PenBoardMax)
		expect.falsy((row1:FindFirstChild("CoinHolder", true) :: Frame).Visible)
		expect.falsy((row1:FindFirstChild("From", true) :: TextLabel).Visible)
		-- An open plot: no board (the blank SignFace).
		BaseService.playerRemoving(a)
		expect.equal(model:FindFirstChild("Pen"), nil)
		finish(w)
	end)

	t.test("PenBoard.setState: the owner's own row: grey with Need N more, back to BUY, gold MAX", function()
		local w = fresh()
		local folder = Instance.new("Folder")
		table.insert(w.made, folder)
		local row = PenBoard.row(PenBoard.build(folder), 1) :: Frame
		local penRow = BaseService.boardRows(pen(3))
		PenBoard.setRow(row, penRow)
		PenBoard.setState(row, "need", "Need 1.2K more")
		expect.equal((row:FindFirstChild("Button") :: Frame).BackgroundColor3, Palette.PenBoardNo)
		expect.equal(text(row, "Caption"), "Need 1.2K more")
		expect.equal((row:FindFirstChild("Caption") :: TextLabel).TextColor3, Palette.PenBoardNeed)
		expect.equal(text(row, "Button", "Content", "Price"), Format.coins(PRICES[4])) -- the price stays
		PenBoard.setState(row, "buy")
		expect.equal((row:FindFirstChild("Button") :: Frame).BackgroundColor3, Palette.PenBoardGo)
		expect.equal(text(row, "Caption"), "BUY")
		PenBoard.setState(row, "max")
		expect.equal(text(row, "Button", "Content", "Price"), "MAX")
		finish(w)
	end)

	t.test("the buy spots: PEN SPACE on E and SHELF SPOTS on F by their rows, the price, off at MAX", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(3)
		BaseService.playerAdded(a)
		local folder = model:FindFirstChild("Pen") :: Instance
		local frame = WorldLayout.plotFrame(1) :: CFrame
		for _, case in
			{
				{ model = "Sign", at = PEN.signs.pen, attr = "SD_PenSign", price = PRICES[4], prompt = "PenPrompt" },
				{
					model = "ShelfSign",
					at = PEN.signs.shelf,
					attr = "SD_ShelfSign",
					price = 31_000_000,
					prompt = "ShelfPrompt",
				},
			}
		do
			local sign = folder:FindFirstChild(case.model) :: Model
			expect.truthy((sign :: Model?) ~= nil and sign:IsA("Model"))
			expect.equal(sign:GetAttribute(case.attr), 1)
			expect.equal(sign:GetAttribute("SD_Price"), case.price)
			local want = frame * case.at
			expect.truthy(vectorNear(sign.WorldPivot.Position, want.Position))
			local face = sign:FindFirstChild("Face") :: BasePart
			expect.equal(face.Transparency, 1)
			expect.falsy(face.CanCollide or face.CanTouch or face.CastShadow)
			local prompt = face:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
			expect.equal(prompt.Name, case.prompt)
			expect.truthy(prompt.Enabled)
			expect.equal(prompt.ActionText, Strings.pen.prompt.action)
			expect.equal(prompt.HoldDuration, Config.Economy.Pen.signHoldSeconds)
			expect.equal(prompt.MaxActivationDistance, 10)
			expect.equal(prompt.RequiresLineOfSight, false)
			expect.equal(prompt.UIOffset, Vector2.new(80, 0)) -- it starts right of the board, never over a price
		end
		local penPrompt = folder:FindFirstChild("PenPrompt", true) :: ProximityPrompt
		local shelfPrompt = folder:FindFirstChild("ShelfPrompt", true) :: ProximityPrompt
		expect.equal(penPrompt.ObjectText, Strings.pen.prompt.object)
		expect.equal(shelfPrompt.ObjectText, Strings.pen.shelfPrompt.object)
		-- One board, two keys (owner 2026-10-24).
		expect.equal(penPrompt.KeyboardKeyCode, Enum.KeyCode.E)
		expect.equal(penPrompt.GamepadKeyCode, Enum.KeyCode.ButtonX)
		expect.equal(shelfPrompt.KeyboardKeyCode, Enum.KeyCode.F)
		expect.equal(shelfPrompt.GamepadKeyCode, Enum.KeyCode.ButtonY)
		-- 6 spots: the 7th spot's price (reading: the offline runner keeps a number attribute in 32 bits, so the
		-- trillions of spots 11-12 are checked in Studio); everything bought: no price, both prompts off.
		w.pens[a] = pen(6)
		BaseService.refresh(a)
		folder = model:FindFirstChild("Pen") :: Instance
		expect.equal((folder:FindFirstChild("Sign") :: Model):GetAttribute("SD_Price"), PRICES[7])
		w.pens[a] = pen(12, nil, 4, true)
		BaseService.refresh(a)
		folder = model:FindFirstChild("Pen") :: Instance
		for _, name in { "Sign", "ShelfSign" } do
			local sign = folder:FindFirstChild(name) :: Model
			expect.equal(sign:GetAttribute("SD_Price"), nil)
			expect.falsy((sign:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt).Enabled)
		end
		finish(w)
	end)

	t.test("Diego's cubbies: open ones hide the lock on a blue back, closed ones show it on pink; 10-12 closed", function()
		local function state(model: Model): { string }
			local list = {}
			for k = 1, 12 do
				local slots = model:FindFirstChild("ShelfSlots") :: Instance
				local slot = slots:FindFirstChild(string.format("ShelfSlot_%02d", k))
				local lock = (slot :: Instance):FindFirstChild("Lock") :: Instance
				local back = (slot :: Instance):FindFirstChild("ShelfBack") :: BasePart
				for _, part in lock:GetChildren() do
					local open = (part :: BasePart).Transparency == 1
					expect.equal((part :: BasePart).CanCollide, not open)
					expect.equal(back.Color, if open then Palette.PenShelfBackOn else Palette.PenShelfBackOff)
				end
				list[k] = if (lock:GetChildren()[1] :: BasePart).Transparency == 1 then "open" else "closed"
			end
			return list
		end
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(3, nil, 1, false) -- the start row: cubbies 1-2
		BaseService.playerAdded(a)
		local want = table.create(12, "closed")
		want[1], want[2] = "open", "open"
		expect.deepEqual(state(model), want)
		w.pens[a] = pen(3, nil, 4, true) -- every row and the TOP spot (cubby 9)
		BaseService.refresh(a)
		want = table.create(12, "open")
		want[10], want[11], want[12] = "closed", "closed", "closed" -- until the shelf grows (part 5)
		expect.deepEqual(state(model), want)
		BaseService.playerRemoving(a) -- an open plot: every cubby closed
		expect.deepEqual(state(model), table.create(12, "closed"))
		finish(w)
	end)

	t.test("SD_Pen holds the walkers, SD_Shelf the shelf's and TOP squishies; SD_PenRate counts them all", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		local p = pen(3, { "kitty_bread", "butter", "toast", "bird", "dragon" }, 1, true)
		p.items[3].slot, p.items[4].slot, p.items[5].slot = 13, 0, 21
		w.pens[a] = p
		BaseService.playerAdded(a)
		expect.equal(model:GetAttribute("SD_Pen"), "kitty_bread.0.1.0;butter.0.1.0")
		expect.equal(model:GetAttribute("SD_Shelf"), "13=toast.0.1.0;21=dragon.0.1.0")
		expect.equal(model:GetAttribute("SD_ShelfRows"), 1)
		expect.equal(model:GetAttribute("SD_ShelfTop"), true)
		expect.equal(model:GetAttribute("SD_PenRate"), 10 + 40 + 10 + 640)
		BaseService.playerRemoving(a)
		for _, name in { "SD_Shelf", "SD_ShelfRows", "SD_ShelfTop" } do
			expect.equal(model:GetAttribute(name), nil)
		end
		finish(w)
	end)

	t.test(
		"refresh redraws one pen; the profile can come later; nothing without a model or for an open plot",
		function()
			local w = fresh()
			local a = newPlayer(w, "A")
			w.pens[a] = pen(3)
			BaseService.playerAdded(a) -- no plot model: nothing to draw, nothing fails
			expect.equal(BaseService.plotOf(a), 1)
			local model = plotModel(w, 1)
			local b = newPlayer(w, "B")
			local model2 = plotModel(w, 2)
			BaseService.playerAdded(b) -- the profile is still loading: the name only
			expect.equal(ownerText(model2), "Name of B")
			expect.equal(model2:FindFirstChild("Pen"), nil)
			w.pens[b] = pen(4)
			BaseService.refresh(b) -- the profile loaded (the data port's Loaded)
			BaseService.refresh(b) -- PenService: a spot bought
			expect.equal(count(model2, "Pen"), 1)
			BaseService.refresh(a)
			expect.equal(count(model, "Pen"), 1)
			-- Never the capsules or the statue any more (pens3 phase 1).
			expect.equal(model:FindFirstChild("Capsules"), nil)
			-- An open plot draws no pen.
			local model3 = plotModel(w, 3)
			BaseService.refresh(newPlayer(w, "Nobody")) -- a player without a plot: nothing happens
			expect.equal(model3:FindFirstChild("Pen"), nil)
			-- A broken pen draws nothing and fails nothing.
			w.pens[b] = { spots = 99, items = "x" }
			BaseService.refresh(b)
			expect.equal(model2:FindFirstChild("Pen"), nil)
			expect.equal(model2:GetAttribute("SD_Pen"), nil)
			finish(w)
		end
	)

	t.test("a full server: the 13th waits in the hub, retries every 0.5 s and gets the plot that frees", function()
		local w = fresh()
		local players = fill(w)
		local late = newPlayer(w, "Late")
		BaseService.playerAdded(late)
		expect.equal(BaseService.plotOf(late), nil)
		expect.equal(late:GetAttribute("SD_Plot"), nil)
		expect.equal(#w.delays, 1)
		for _ = 1, 3 do
			expect.equal(runDelays(w), 1) -- still full: the next retry is scheduled
			expect.equal(BaseService.plotOf(late), nil)
		end
		BaseService.playerRemoving(players[7])
		expect.equal(runDelays(w), 1)
		expect.equal(BaseService.plotOf(late), 7)
		expect.equal(late:GetAttribute("SD_Plot"), 7)
		expect.equal(#w.delays, 0) -- found: no more retries
		finish(w)
	end)

	t.test("no plot frees within 5 s: 10 tries, then the player stays in the hub; leaving stops the retries", function()
		local w = fresh()
		fill(w)
		local late = newPlayer(w, "Late")
		BaseService.playerAdded(late)
		local tries = 0
		while #w.delays > 0 do
			tries += runDelays(w)
		end
		expect.equal(tries, 10) -- every 0.5 s for 5 s
		expect.equal(BaseService.plotOf(late), nil)
		-- A waiting player who leaves: the pending retry does nothing and schedules no other.
		local gone = newPlayer(w, "Gone")
		BaseService.playerAdded(gone)
		BaseService.playerRemoving(gone)
		expect.equal(runDelays(w), 1)
		expect.equal(#w.delays, 0)
		expect.equal(BaseService.plotOf(gone), nil)
		finish(w)
	end)
end
