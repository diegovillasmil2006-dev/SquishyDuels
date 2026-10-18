--!strict
-- BaseService_Test: unit tests for ServerScriptService.Server.Services.BaseService with injected fakes (a recorded
-- task.delay that the test runs by hand, a fake plot spawn); players are Folder instances (they carry the SD_Plot
-- attribute) or plain tables. Server only (ServerStorage.UnitTest). Edit mode: no Player, no world.
-- Contract (lobby bases spec 2026-10-11 §2, §4, §6; build plan Phase 3):
--   * 10 plots (WorldLayout.Bases); a joining player gets the lowest free plot, shown in the SD_Plot attribute; a plot
--     freed on leave is handed out again; rejoining gives the lowest free plot (the pen lives in the profile);
--   * with no plot free the player waits in the hub: the service tries again every 0.5 s for 5 s (10 tries) and gives
--     the plot that frees meanwhile; after 5 s it stops; a waiting player who leaves stops the retries;
--   * the plot's spawn is asked for the plot handed out and used only once the world has one (Phase 4);
--   * the owner view (Phase 4, spec §4, §8): a plot with an owner shows their display name on its name sign and its
--     colour (Bases.colors) on every SD_BaseTint part; an open plot shows "Open plot" and the grey;
--   * pens3 phase 1 (the pen replaced the capsules and the statue): the owner's pen from their ready profile, in a
--     "Pen" Folder (lobby design v6; wb, owner 2026-10-17: the pen is the whole base, so no pen fence, rails or
--     colliders at any spot count: the plot's own fence holds it), the PEN SPACE sign at Bases.pen.signs.pen
--     (SD_PenSign = plot, SD_Price = the next spot's price, its hold prompt; MAX with the prompt off at 12 spots) and
--     the base Model's SD_PenSpots / SD_Pen / SD_PenRate / SD_PenTier for the clients' walking squishies;
--     refresh(player) redraws (no duplicates); an open plot, a profile that is not ready or a missing plot model draws
--     no pen and nothing fails;
--   * pens3 phase 3: no pen draws more parts than WorldLayout.Bases.pen.maxParts (the lobby budget's worst plot),
--     and the full 12-spot pen draws exactly that many.
--   * pens3 phase 10 (the pen look, lobby design v6): the gate (LK:87-96) at Bases.pen.gate (wb: the front-right
--     corner): posts in the tier's post colour, the sign frame in the plot's colour, the owner sign (display name,
--     "BASE n", the headshot asked once per user and cached), the number badge n and the visitor board ("0 visitors"
--     until phase 18); the tier decor of PenMath.decorOf (tier 2: 7 gate bulbs + 2 lollipop lamps; tier 3: + the bow +
--     2 gumdrop trees) where L puts it; the base Model's SD_PenOwner (the owner's UserId); the full pen plus the plot's
--     80 static parts stays within Budgets.baseParts.
--   * pens3 phase 11 (the shelf rows + the TOP spot, lobby design v6): every base draws its "Shelf" at Bases.pen.shelf
--     (LK:182-189: the back in the plot's colour, the Frosting frame of 11 boards, the bow, one invisible 27.4 × 15.6 ×
--     6 collider: K's "block"), a glass "Lock" (K:98 Glass, the img.icon.lock picture, CHK:57) over every cubby that is
--     not open, the TOP spot's pedestal (placeholder) with a lock picture until it is bought; the SHELF SPOTS sign at
--     Bases.pen.signs.shelf (SD_ShelfSign = plot, SD_Price = the next row's or the TOP spot's price, ShelfPrompt; MAX
--     with the prompt off once all is open); the base Model's SD_Pen holds the pen's walkers only, SD_Shelf
--     (PenMath.encodeShelf) the shelf's and the TOP spot's, SD_ShelfRows / SD_ShelfTop the open rows and the TOP spot,
--     SD_PenRate every placed squishy's Coins a second; no state (any spots x rows x TOP) draws more than
--     Bases.pen.maxParts, the worst draws exactly that many, and it fits Budgets.baseParts with the plot's 80.
--   * wb: every part BaseService draws (signs, gate, tier decor, shelf) stands on the plot's fenced floor
--     (Bases.pen.walk), clear of what LobbyBuilder stands there (Bases.props: the spawn, the arch's pillars, the
--     mailbox, the flower box, the bench, the planter) and inside a walk block (no squishy walks through it); parts
--     per state: 48 at tier I with the start row, 59 at tier II, 84 at tier III (the worst), 78 with everything bought.
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
		for index = 1, 10 do
			local player = newPlayer(w, "P" .. index)
			BaseService.playerAdded(player)
			players[index] = player
		end
		return players
	end

	t.test("10 plots, the lowest free one per joining player, in the SD_Plot attribute; leaving frees it", function()
		local w = fresh()
		expect.equal(#WorldLayout.Bases.frames, 10)
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
			w.friends[wrap] = players[1] -- on plot 1: plot 10 is taken, 9 is two away round the ring, 2 is one away
			BaseService.playerAdded(wrap)
			expect.equal(BaseService.plotOf(wrap), 2)
			BaseService.playerRemoving(players[10])
			local ring = newPlayer(w, "Ring")
			w.friends[ring] = players[1] -- plot 10 (one away round the ring) beats plot 3 (two away)
			BaseService.playerAdded(ring)
			expect.equal(BaseService.plotOf(ring), 10)
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

	-- The owner view (Phase 4) -----------------------------------------------------------------------------------

	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local Format = t.requireShared("Util/Format")
	local Config = t.requireShared("Config")
	local PenMath = t.requireShared("PenMath")
	local PEN = WorldLayout.Bases.pen
	local PRICES = Config.Economy.Pen.spotPrices
	local TIERS = { -- the gate posts' tier colours (wb: no pen fence)
		{ post = Palette.PenFenceWaferPost },
		{ post = Palette.PenFenceMintPost },
		{ post = Palette.PenFenceRoyalPost },
	}

	-- A plot model like the generated one: tinted parts (two "full", one "light") and a name sign's Owner label.
	local function plotModel(w: World, plot: number): Model
		local model = Instance.new("Model")
		model.Name = string.format("Base_%02d", plot)
		for _, which in { "full", "full", "light" } do
			local part = Instance.new("Part")
			part:SetAttribute("SD_BaseTint", which)
			part.Parent = model
		end
		local sign = Instance.new("Part")
		sign.Name = "NameSign"
		local gui = Instance.new("SurfaceGui")
		gui.Parent = sign
		local owner = Instance.new("TextLabel")
		owner.Name = "Owner"
		owner.Text = "Open plot"
		owner.Parent = gui
		sign.Parent = model
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

	local function tints(model: Model): { [string]: Color3 }
		local found: { [string]: Color3 } = {}
		for _, part in model:GetChildren() do
			local which = part:GetAttribute("SD_BaseTint")
			if part:IsA("BasePart") and type(which) == "string" then
				local previous = found[which] :: Color3?
				if previous ~= nil and previous ~= part.Color then
					error(`two {which} parts differ`)
				end
				found[which] = part.Color
			end
		end
		return found
	end

	local function ownerText(model: Model): string
		return (model:FindFirstChild("Owner", true) :: TextLabel).Text
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

	t.test(
		'an owned plot shows its owner\'s name and colour; an open plot "Open plot" and the grey (§4, §8)',
		function()
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			BaseService.playerAdded(a)
			expect.equal(ownerText(model), "Name of A")
			local colors = WorldLayout.Bases.colors[1]
			expect.equal(tints(model).full, Palette[colors.full])
			expect.equal(tints(model).light, Palette[colors.light])
			BaseService.playerRemoving(a)
			expect.equal(ownerText(model), Strings.resolve("base.openPlot"))
			expect.equal(tints(model).full, Palette.BaseOpen)
			expect.equal(tints(model).light, Palette.BaseOpenLight)
			-- The second plot gets its own colour.
			local model2 = plotModel(w, 2)
			BaseService.playerAdded(newPlayer(w, "B"))
			BaseService.playerAdded(newPlayer(w, "C"))
			expect.equal(ownerText(model2), "Name of C")
			expect.equal(tints(model2).full, Palette[WorldLayout.Bases.colors[2].full])
			finish(w)
		end
	)

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

	-- Wb (owner 2026-10-17: the pen is the whole base): the plot's own fence holds it; BaseService draws none.
	t.test("wb: no pen fence at any spot count: no Fence, Rails or Collider in the Pen folder", function()
		for spots = 3, 12 do
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(spots)
			BaseService.playerAdded(a)
			local folder = model:FindFirstChild("Pen")
			expect.truthy(folder ~= nil)
			for _, d in (folder :: Instance):GetDescendants() do
				if d.Name == "Fence" or d.Name == "Rails" or d.Name == "Collider" or d.Name == "Segment" then
					error(`{spots} spots: a pen fence piece {d:GetFullName()}`)
				end
			end
			finish(w)
		end
	end)

	-- Pens3 phase 10: the pen look (lobby design v6) ------------------------------------------------------------

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

	t.test(
		"the gate (LK:87-96): posts, the frame in the plot's colour, the owner sign, the badge, 0 visitors",
		function()
			local w = fresh()
			local model2 = plotModel(w, 2)
			local model = plotModel(w, 1)
			local a = { UserId = 77 } -- a plain-table player with a UserId (Folder players have none)
			w.pens[a] = pen(3)
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
				expect.equal(post.Color, TIERS[1].post)
				expect.truthy(post.CanCollide)
			end
			local balls = named(gate, "GatePostTop")
			expect.equal(#balls, 2)
			expect.near(balls[1].Size.X, 1.6, 1e-3)
			expect.near(localOf(at, balls[1]).Y, 12.3, 1e-3)
			-- The sign frame (8.4 × 3.6 × 0.3 from y 8.4, z 0.3) in the plot's colour.
			local frameBox = named(gate, "SignFrame")[1]
			expect.truthy(vectorNear(frameBox.Size, Vector3.new(8.4, 3.6, 0.3)))
			expect.truthy(vectorNear(localOf(at, frameBox), Vector3.new(0, 10.2, 0.3)))
			expect.equal(frameBox.Color, Palette[WorldLayout.Bases.colors[1].full])
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
			-- Every part but the posts stays out of collisions; none is queried, touched or casts a shadow.
			for _, d in gate:GetDescendants() do
				if d:IsA("BasePart") then
					expect.truthy(d.Anchored)
					expect.falsy(d.CanQuery or d.CanTouch or d.CastShadow)
					expect.equal(d.CanCollide, d.Name == "GatePost")
				end
			end
			-- The plot's name sign still shows the owner (no gate label is called "Owner").
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
		end
	)

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

	t.test(
		"tier decor (K:4170-4189 at L:187-193): none at tier 1, bulbs + 2 lamps at 2, + bow + 2 trees at 3",
		function()
			for spots = 3, 12 do
				local w = fresh()
				local model = plotModel(w, 1)
				local a = newPlayer(w, "A")
				w.pens[a] = pen(spots)
				BaseService.playerAdded(a)
				local folder = model:FindFirstChild("Pen") :: Instance
				local tier = PEN.steps[spots].tier
				local gate = folder:FindFirstChild("Gate") :: Model
				local at = (WorldLayout.plotFrame(1) :: CFrame) * PEN.gate
				local bulbs = named(gate, "GateBulb")
				expect.equal(#bulbs, if tier >= 2 then 7 else 0)
				for _, bulb in bulbs do
					local p = localOf(at, bulb)
					expect.near(p.Y, 12.15, 1e-3)
					expect.near(p.Z, 0.1, 1e-3)
					expect.truthy(math.abs(p.X) <= 3.6 + 1e-3)
					expect.near(bulb.Size.X, 0.5, 1e-3)
					expect.equal(bulb.Material, Enum.Material.Neon)
					expect.equal(bulb.Color, Palette.PenGateGlow)
				end
				local bow = gate:FindFirstChild("Bow") :: Model?
				expect.equal(bow ~= nil, tier >= 3)
				if bow then
					expect.truthy(vectorNear(at:PointToObjectSpace(bow.WorldPivot.Position), Vector3.new(0, 13.5, 0)))
					expect.equal(#named(bow, "BowLoop"), 12)
					expect.equal(#named(bow, "BowKnot"), 1)
					for _, d in bow:GetDescendants() do
						if d:IsA("BasePart") then
							expect.equal(d.Color, Palette.PenDecorIcing)
						end
					end
				end
				local lamps, trees = {}, {}
				for _, child in folder:GetChildren() do
					if child.Name == "Lamp" then
						table.insert(lamps, child :: Model)
					elseif child.Name == "Tree" then
						table.insert(trees, child :: Model)
					end
				end
				expect.equal(#lamps, if tier >= 2 then 2 else 0)
				expect.equal(#trees, if tier >= 3 then 2 else 0)
				local frame = WorldLayout.plotFrame(1) :: CFrame
				for index, lamp in lamps do
					local want = frame * PEN.lamps[index]
					expect.near((lamp.WorldPivot.Position - want.Position).Magnitude, 0, 1e-3)
					local pole = named(lamp, "LampPole")[1]
					expect.near(pole.Size.X, 8.2, 1e-3)
					expect.near(localOf(want, pole).Y, 4.1, 1e-3)
					expect.equal(pole.Color, Palette.PenDecorFrosting)
					expect.truthy(pole.CanCollide)
					local candy = named(lamp, "LampCandy")[1]
					expect.truthy(vectorNear(localOf(want, candy), Vector3.new(0, 9.2, 0)))
					expect.equal(candy.Material, Enum.Material.Neon)
					expect.equal(candy.Color, Palette.PenGateGlow)
					local swirl = candy:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
					local rings = 0
					for _, d in swirl:GetDescendants() do
						if d:IsA("UIStroke") then
							rings += 1
							expect.equal(d.Color, Palette.PenDecorIcing)
						end
					end
					expect.equal(rings, 2) -- the swirl's 2 rings are drawn on the candy's front, not built
				end
				for index, tree in trees do
					local want = frame * PEN.trees[index].at
					expect.near((tree.WorldPivot.Position - want.Position).Magnitude, 0, 1e-3)
					local trunk = named(tree, "Trunk")[1]
					expect.near(trunk.Size.X, 5, 1e-3)
					expect.equal(trunk.Color, Palette.PenDecorFrosting)
					expect.truthy(trunk.CanCollide)
					expect.equal(#named(tree, "TrunkStripe"), 3)
					local top = named(tree, "CanopyTop")[1]
					expect.truthy(vectorNear(top.Size, Vector3.new(6, 4.2, 6)))
					expect.near(localOf(want, top).Y, 6.7, 1e-3)
					expect.equal(
						(top:FindFirstChildOfClass("SpecialMesh") :: SpecialMesh).MeshType,
						Enum.MeshType.Sphere
					)
					expect.equal(top.Color, Palette[PEN.trees[index].color])
					expect.equal(named(tree, "CanopyBase")[1].Color, Palette[PEN.trees[index].color])
				end
				for _, d in folder:GetDescendants() do
					local parent = d.Parent
					if d:IsA("BasePart") and parent and (parent.Name == "Lamp" or parent.Name == "Tree") then
						expect.falsy(d.CanQuery or d.CanTouch or d.CastShadow)
						expect.equal(d.CanCollide, d.Name == "LampPole" or d.Name == "Trunk")
					end
				end
				finish(w)
			end
		end
	)

	t.test("the decor follows the owner's tier on a redraw; an empty base shows none", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		local function decor(): { [string]: number }
			local found = { Lamp = 0, Tree = 0, Bow = 0 }
			local folder = model:FindFirstChild("Pen")
			if folder then
				for _, d in folder:GetDescendants() do
					if found[d.Name] ~= nil and d:IsA("Model") then
						found[d.Name] += 1
					end
				end
			end
			return found
		end
		w.pens[a] = pen(9)
		BaseService.playerAdded(a)
		expect.deepEqual(decor(), { Lamp = 2, Tree = 0, Bow = 0 })
		w.pens[a] = pen(10) -- a spot bought: tier III
		BaseService.refresh(a)
		expect.deepEqual(decor(), { Lamp = 2, Tree = 2, Bow = 1 })
		BaseService.playerRemoving(a) -- the base is empty: no pen, no gate, no decor
		expect.equal(model:FindFirstChild("Pen"), nil)
		expect.deepEqual(decor(), { Lamp = 0, Tree = 0, Bow = 0 })
		finish(w)
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

	-- Pens3 phase 3: LobbyBuilder's part budget counts every plot with this many runtime parts.
	t.test("no pen state draws more parts than Bases.pen.maxParts; the worst draws exactly that many", function()
		-- Pens3 phase 10: with the plot's 80 static parts (WorldLayout Budgets' note) a full pen fits baseParts.
		expect.truthy(PEN.maxParts + 80 <= WorldLayout.Budgets.baseParts)
		-- Pens3 phase 11: every spot count x every shelf row count x the TOP spot (the shelf and its locks count).
		local worst = 0
		for spots = 3, 12 do
			for rows = 1, Config.Economy.Pen.shelfMaxRows do
				for _, top in { false, true } do
					local w = fresh()
					local model = plotModel(w, 1)
					local a = newPlayer(w, "A")
					w.pens[a] = pen(spots, nil, rows, top)
					BaseService.playerAdded(a)
					local parts = 0
					for _, d in (model:FindFirstChild("Pen") :: Instance):GetDescendants() do
						if d:IsA("BasePart") then
							parts += 1
						end
					end
					expect.truthy(parts <= PEN.maxParts)
					worst = math.max(worst, parts)
					finish(w)
				end
			end
		end
		expect.equal(worst, PEN.maxParts)
	end)

	-- Wb: the parts per state (NOTES.md's table), the plot's fenced floor, LobbyBuilder's props and the walk blocks.
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

	t.test("wb: parts per state: 48 at tier I, 59 at tier II, 84 at tier III (the worst), 78 all bought", function()
		for _, case in
			{
				{ spots = 3, rows = 1, top = false, parts = 48 },
				{ spots = 6, rows = 1, top = false, parts = 59 },
				{ spots = 12, rows = 1, top = false, parts = 84 },
				{ spots = 12, rows = 4, top = true, parts = 78 },
			}
		do
			local w, model = drawn(case.spots, case.rows, case.top)
			expect.equal(#partsIn(model:FindFirstChild("Pen") :: Instance), case.parts)
			finish(w)
		end
	end)

	t.test("wb: every drawn part stands on the fenced floor, clear of LobbyBuilder's props, in a walk block", function()
		local frame = WorldLayout.plotFrame(1) :: CFrame
		local walk = PEN.walk
		local function overlaps(a: any, b: any): boolean
			return a.minX < b.maxX - 1e-3
				and b.minX < a.maxX - 1e-3
				and a.minZ < b.maxZ - 1e-3
				and b.minZ < a.maxZ - 1e-3
		end
		for _, spots in { 3, 12 } do -- tier I, and tier III with every decor piece
			local w, model = drawn(spots, 1, false)
			for _, part in partsIn(model:FindFirstChild("Pen") :: Instance) do
				-- The part's box on the plot's floor (its 8 corners in plot studs).
				local box = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
				local half = part.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p = frame:PointToObjectSpace(
								part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
							)
							box.minX, box.maxX = math.min(box.minX, p.X), math.max(box.maxX, p.X)
							box.minZ, box.maxZ = math.min(box.minZ, p.Z), math.max(box.maxZ, p.Z)
						end
					end
				end
				local name = part:GetFullName()
				local onFloor = box.minX >= walk.minX - 1e-3
					and box.maxX <= walk.maxX + 1e-3
					and box.minZ >= walk.minZ - 1e-3
					and box.maxZ <= walk.maxZ + 1e-3
				if not onFloor then
					error(`{spots} spots: {name} is off the fenced floor`)
				end
				for _, prop in WorldLayout.Bases.props do
					if overlaps(box, prop) then
						error(`{spots} spots: {name} stands in the {prop.name}`)
					end
				end
				local blocked = false
				for _, block in PEN.blocks do
					if
						box.minX >= block.minX - 1e-3
						and box.maxX <= block.maxX + 1e-3
						and box.minZ >= block.minZ - 1e-3
						and box.maxZ <= block.maxZ + 1e-3
					then
						blocked = true
					end
				end
				if not blocked then
					error(`{spots} spots: {name} is in no walk block (a squishy could walk through it)`)
				end
			end
			finish(w)
		end
	end)

	-- Pens3 phase 11: the shelf, its locks, the TOP spot and the SHELF SPOTS sign ------------------------------------

	local AssetTable = t.requireShared("AssetTable")

	local function shelfOf(model: Model): Model
		return (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Shelf") :: Model
	end

	t.test(
		"the shelf (LK:182-189): the back in the plot's colour, the frame, the bow, one collider, at its spot",
		function()
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(3)
			BaseService.playerAdded(a)
			local shelf = shelfOf(model)
			expect.truthy((shelf :: Model?) ~= nil and shelf:IsA("Model"))
			local frame = WorldLayout.plotFrame(1) :: CFrame
			local at = frame * PEN.shelf.at
			expect.truthy(vectorNear(shelf.WorldPivot.Position, at.Position))
			expect.truthy(vectorNear(shelf.WorldPivot.LookVector, at.LookVector))
			local back = shelf:FindFirstChild("ShelfBack") :: BasePart
			expect.equal(back.Color, Palette[WorldLayout.Bases.colors[1].full])
			expect.truthy(vectorNear(back.Size, Vector3.new(27.4, 15.6, 0.6)))
			expect.truthy(vectorNear(localOf(at, back), Vector3.new(0, 7.8, 2.7)))
			local boards = named(shelf, "ShelfFrame")
			expect.equal(#boards, 11) -- 2 sides, the bottom, the middle, the top, 6 dividers (LK:184-185)
			for _, board in boards do
				expect.equal(board.Color, Palette.PenDecorFrosting)
			end
			local bow = shelf:FindFirstChild("ShelfBow") :: Model
			expect.truthy(vectorNear(at:PointToObjectSpace(bow.WorldPivot.Position), Vector3.new(0, 15.6, -0.5)))
			local colliders = named(shelf, "ShelfCollider")
			expect.equal(#colliders, 1)
			local collider = colliders[1]
			expect.truthy(vectorNear(collider.Size, Vector3.new(27.4, 15.6, 6)))
			expect.truthy(collider.CanCollide and collider.Transparency == 1)
			-- Every visible part is decor (the collider holds players off, K: "block").
			for _, part in shelf:GetDescendants() do
				if part:IsA("BasePart") and part ~= collider then
					expect.falsy(part.CanCollide or part.CanQuery or part.CanTouch or part.CastShadow)
					expect.truthy(part.Anchored)
				end
			end
			finish(w)
		end
	)

	t.test(
		"a glass lock with the lock picture over every closed cubby; the TOP spot's lock until it is bought",
		function()
			local function locks(model: Model): { [number]: BasePart }
				local found = {}
				for _, part in named(shelfOf(model), "Lock") do
					found[part:GetAttribute("SD_ShelfSlot") :: number] = part
				end
				return found
			end
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(3, nil, 1, false)
			BaseService.playerAdded(a)
			local frame = WorldLayout.plotFrame(1) :: CFrame
			local at = frame * PEN.shelf.at
			local closed = locks(model)
			local slots = {}
			for slot in closed do
				table.insert(slots, slot)
			end
			table.sort(slots)
			expect.deepEqual(slots, { 15, 16, 17, 18, 19, 20 }) -- row 1 (13, 14) is open
			local lock = closed[15]
			local cubby = PEN.shelf.cubbies[3]
			expect.truthy(vectorNear(lock.Size, Vector3.new(5.8, 6.3, 0.15))) -- LK:191
			expect.truthy(vectorNear(localOf(at, lock), Vector3.new(cubby.X, cubby.Y + 0.1 + 3.15, -3.125))) -- L:247
			expect.equal(lock.Material, Enum.Material.Glass)
			expect.equal(lock.Color, Palette.PenShelfGlass)
			expect.near(lock.Transparency, 0.5, 1e-6)
			local picture = lock:FindFirstChildWhichIsA("ImageLabel", true) :: ImageLabel
			expect.equal(picture.Image, AssetTable.image("img.icon.lock"))
			expect.equal((lock:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui).Face, Enum.NormalId.Front)
			local top = shelfOf(model):FindFirstChild("Top") :: Model
			expect.truthy((top :: Model?) ~= nil)
			expect.truthy(top:FindFirstChild("TopLock", true) ~= nil) -- the TOP spot: closed
			-- Row 3 bought: 2 locks left; the TOP spot bought: no lock picture on it.
			w.pens[a] = pen(3, nil, 3, true)
			BaseService.refresh(a)
			slots = {}
			for slot in locks(model) do
				table.insert(slots, slot)
			end
			table.sort(slots)
			expect.deepEqual(slots, { 19, 20 })
			expect.equal((shelfOf(model):FindFirstChild("Top") :: Model):FindFirstChild("TopLock", true), nil)
			finish(w)
		end
	)

	t.test("the SHELF SPOTS sign: the next row's price, then the TOP spot's; MAX with the prompt off", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(3)
		BaseService.playerAdded(a)
		local folder = model:FindFirstChild("Pen") :: Instance
		local sign = folder:FindFirstChild("ShelfSign") :: Model
		expect.truthy((sign :: Model?) ~= nil and sign:IsA("Model"))
		expect.equal(sign:GetAttribute("SD_ShelfSign"), 1)
		expect.equal(sign:GetAttribute("SD_Price"), 31_000_000)
		local frame = WorldLayout.plotFrame(1) :: CFrame
		local want = frame * PEN.signs.shelf
		expect.truthy(vectorNear(sign.WorldPivot.Position, want.Position))
		expect.truthy(vectorNear(sign.WorldPivot.LookVector, want.LookVector))
		expect.equal((sign:FindFirstChild("Title", true) :: TextLabel).Text, Strings.pen.shelfSign.title)
		expect.equal((sign:FindFirstChild("Price", true) :: TextLabel).Text, Format.coins(31_000_000))
		local prompt = sign:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt
		expect.equal(prompt.Name, "ShelfPrompt")
		expect.truthy(prompt.Enabled)
		expect.equal(prompt.ObjectText, Strings.pen.shelfPrompt.object)
		expect.equal(prompt.HoldDuration, Config.Economy.Pen.signHoldSeconds)
		-- The PEN SPACE sign is still its own (the left one).
		expect.equal((folder:FindFirstChild("Sign") :: Model):GetAttribute("SD_PenSign"), 1)
		-- Everything open: MAX, no price, the prompt off (the trillions of rows 3-4 and the TOP spot: Studio, see the
		-- PEN SPACE sign's 32-bit note).
		w.pens[a] = pen(3, nil, 4, true)
		BaseService.refresh(a)
		sign = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("ShelfSign") :: Model
		expect.equal(sign:GetAttribute("SD_Price"), nil)
		expect.equal((sign:FindFirstChild("Price", true) :: TextLabel).Text, Strings.pen.sign.max)
		expect.equal((sign:FindFirstChild("Trim") :: BasePart).Color, Palette.PenSignMax)
		expect.falsy((sign:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt).Enabled)
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

	t.test("the PEN SPACE sign: the next spot's price and its hold prompt; MAX with the prompt off at 12", function()
		local w = fresh()
		local model = plotModel(w, 1)
		local a = newPlayer(w, "A")
		w.pens[a] = pen(3)
		BaseService.playerAdded(a)
		local sign = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Sign") :: Model
		expect.truthy((sign :: Model?) ~= nil and sign:IsA("Model"))
		expect.equal(sign:GetAttribute("SD_PenSign"), 1)
		expect.equal(sign:GetAttribute("SD_Price"), 1_500)
		local frame = WorldLayout.plotFrame(1) :: CFrame
		local want = frame * PEN.signs.pen
		expect.near((sign.WorldPivot.Position - want.Position).Magnitude, 0, 1e-3)
		expect.near((sign.WorldPivot.LookVector - want.LookVector).Magnitude, 0, 1e-3)
		local face = sign:FindFirstChild("Face") :: BasePart
		local gui = face:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
		expect.equal(gui.Face, Enum.NormalId.Front)
		expect.equal((gui:FindFirstChild("Title", true) :: TextLabel).Text, Strings.pen.sign.title)
		expect.equal((gui:FindFirstChild("Price", true) :: TextLabel).Text, Format.coins(1_500))
		expect.equal((gui:FindFirstChild("Line", true) :: TextLabel).Text, "") -- the owner's client writes it
		expect.equal((sign:FindFirstChild("Trim") :: BasePart).Color, Palette.PenSignCanBuy)
		local prompt = face:FindFirstChildOfClass("ProximityPrompt") :: ProximityPrompt
		expect.truthy(prompt.Enabled)
		expect.equal(prompt.ActionText, Strings.pen.prompt.action)
		expect.equal(prompt.ObjectText, Strings.pen.prompt.object)
		expect.equal(prompt.HoldDuration, Config.Economy.Pen.signHoldSeconds)
		expect.equal(prompt.MaxActivationDistance, 10)
		expect.equal(prompt.RequiresLineOfSight, false)
		for _, part in sign:GetDescendants() do
			if part:IsA("BasePart") then
				expect.falsy(part.CanTouch or part.CastShadow)
			end
		end
		-- 6 spots: the 7th spot's price (reading: the offline runner keeps a number attribute in 32 bits, so the
		-- trillions of spots 11-12 are checked in Studio); 12: MAX, no price, the prompt off, the gold trim.
		w.pens[a] = pen(6)
		BaseService.refresh(a)
		sign = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Sign") :: Model
		expect.equal(sign:GetAttribute("SD_Price"), PRICES[7])
		expect.equal((sign:FindFirstChild("Price", true) :: TextLabel).Text, Format.coins(PRICES[7]))
		w.pens[a] = pen(12)
		BaseService.refresh(a)
		sign = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Sign") :: Model
		expect.equal(sign:GetAttribute("SD_Price"), nil)
		expect.equal((sign:FindFirstChild("Price", true) :: TextLabel).Text, Strings.pen.sign.max)
		expect.equal((sign:FindFirstChild("Trim") :: BasePart).Color, Palette.PenSignMax)
		expect.falsy((sign:FindFirstChildWhichIsA("ProximityPrompt", true) :: ProximityPrompt).Enabled)
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
			BaseService.playerAdded(b) -- the profile is still loading: name and colour only
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

	t.test("a full server: the 11th waits in the hub, retries every 0.5 s and gets the plot that frees", function()
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
