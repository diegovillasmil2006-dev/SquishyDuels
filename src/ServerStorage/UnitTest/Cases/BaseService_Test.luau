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
--     "Pen" Folder (lobby design v6): the fence of WorldLayout.Bases.pen.steps[spots] (kit.json's segment count, + the
--     back fence at 9-12 spots until the shelf; posts and rails in the tier's colours; every visual part out of
--     collisions, queries, touches and shadows), 5 invisible colliders (the front split by the 8-stud gate gap), the
--     PEN SPACE sign at Bases.pen.signs.pen (SD_PenSign = plot, SD_Price = the next spot's price, its hold prompt;
--     MAX with the prompt off at 12 spots) and the base Model's SD_PenSpots / SD_Pen / SD_PenRate / SD_PenTier for the
--     clients' walking squishies; refresh(player) redraws (no duplicates); an open plot, a profile that is not ready or
--     a missing plot model draws no pen and nothing fails;
--   * pens3 phase 3: no pen draws more parts than WorldLayout.Bases.pen.maxParts (the lobby budget's worst plot),
--     and the full 12-spot pen draws exactly that many.
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
	}

	local function fresh(): World
		local w: World = { delays = {}, asked = {}, made = {}, models = {}, pens = {}, friends = {} }
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
	local TIERS = {
		{ post = Palette.PenFenceWaferPost, rail = Palette.PenFenceWaferRail },
		{ post = Palette.PenFenceMintPost, rail = Palette.PenFenceMintRail },
		{ post = Palette.PenFenceRoyalPost, rail = Palette.PenFenceRoyalRail },
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

	-- A ready profile's pen (Types.PenState) with `spots` open spots and the given kinds (ids 1, 2, ...).
	local function pen(spots: number, kinds: { string }?): any
		local items = {}
		for index, kind in (kinds or { "kitty_bread" }) :: { string } do
			items[index] = { id = index, kind = kind, form = 0, level = 1, coat = 0 }
		end
		return { spots = spots, nextId = #items + 1, items = items }
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

	-- The plot-local frame of every fence segment (its Model's WorldPivot) and its parts.
	local function segments(model: Model, plot: number): { { at: CFrame, model: Model } }
		local frame = WorldLayout.plotFrame(plot) :: CFrame
		local fence = (model:FindFirstChild("Pen") :: Instance):FindFirstChild("Fence") :: Instance
		local list = {}
		for _, child in fence:GetChildren() do
			expect.truthy(child:IsA("Model") and child.Name == "Segment")
			table.insert(list, { at = frame:ToObjectSpace((child :: Model).WorldPivot), model = child :: Model })
		end
		return list
	end

	local function near(a: number, b: number): boolean
		return math.abs(a - b) < 1e-3
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
		expect.equal(model:GetAttribute("SD_Pen"), "butter.0.1.0;kitty_bread.0.1.0") -- the best first (PenMath.placed)
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

	t.test(
		"the fence: kit.json's segments on the pen's outline (+ the back fence at 9-12), the tier's colours",
		function()
			for spots = 3, 12 do
				local w = fresh()
				local model = plotModel(w, 1)
				local a = newPlayer(w, "A")
				w.pens[a] = pen(spots)
				BaseService.playerAdded(a)
				local step = PEN.steps[spots]
				local list = segments(model, 1)
				local back = if step.backWall == "shelf" then step.w / PEN.segment else 0 -- a fence until phase 11's shelf
				expect.equal(#list, step.fence + back)
				local backZ = PEN.frontZ - step.d
				local front, sides, backs = 0, 0, 0
				for _, segment in list do
					local p = segment.at.Position
					expect.near(p.Y, 0, 1e-3)
					if near(p.Z, PEN.frontZ) then
						front += 1
						expect.truthy(math.abs(p.X) >= PEN.gateWidth / 2 + PEN.segment / 2 - 1e-3) -- the gate gap stays open
						expect.truthy(math.abs(p.X) <= step.w / 2 - PEN.segment / 2 + 1e-3)
					elseif near(math.abs(p.X), step.w / 2) then
						sides += 1
						expect.truthy(
							p.Z <= PEN.frontZ - PEN.segment / 2 + 1e-3 and p.Z >= backZ + PEN.segment / 2 - 1e-3
						)
						expect.near(math.abs(segment.at.RightVector.Z), 1, 1e-3) -- turned along the side
					else
						expect.truthy(near(p.Z, backZ))
						backs += 1
					end
					-- Every visual part: rails and pickets in the tier's rail colour, posts and balls in its post colour.
					for _, part in segment.model:GetDescendants() do
						if part:IsA("BasePart") then
							expect.falsy(part.CanCollide or part.CanQuery or part.CanTouch or part.CastShadow)
							expect.truthy(part.Anchored)
							local want = if part.Name == "Post" or part.Name == "PostTop"
								then TIERS[step.tier].post
								else TIERS[step.tier].rail
							expect.equal(part.Color, want)
						end
					end
				end
				expect.equal(front, (step.w - PEN.gateWidth) / PEN.segment)
				expect.equal(sides, 2 * step.d / PEN.segment)
				expect.equal(backs, step.w / PEN.segment)
				finish(w)
			end
		end
	)

	t.test(
		"each segment is LK's pen_fence: 2 rails and 3 pickets; one post and ball top per corner, never two",
		function()
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(3)
			BaseService.playerAdded(a)
			local frame = WorldLayout.plotFrame(1) :: CFrame
			local posts: { [string]: number } = {}
			local tops = 0
			for _, segment in segments(model, 1) do
				expect.equal(count(segment.model, "Rail"), 2)
				expect.equal(count(segment.model, "Picket"), 3)
				for _, part in segment.model:GetChildren() do
					if part.Name == "Post" then
						local p = frame:PointToObjectSpace((part :: BasePart).CFrame.Position)
						local key = string.format("%.2f,%.2f", p.X, p.Z)
						posts[key] = (posts[key] or 0) + 1
						expect.near(p.Y, 1.6, 1e-3) -- 3.2 tall from the floor (LK:83)
					elseif part.Name == "PostTop" then
						tops += 1
					end
				end
			end
			local n = 0
			for key, seen in posts do
				n += 1
				if seen ~= 1 then
					error(`two posts at {key}`)
				end
			end
			-- 16 x 12: (16 + 12) × 2 / 4 = 14 post spots round the outline, but the one in the middle of the gate gap.
			expect.equal(n, 13)
			expect.equal(tops, n)
			finish(w)
		end
	)

	t.test("5 invisible colliders hold the pen's outline, the front split by the gate gap", function()
		for _, spots in { 3, 9 } do
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(spots)
			BaseService.playerAdded(a)
			local folder = model:FindFirstChild("Pen") :: Instance
			local frame = WorldLayout.plotFrame(1) :: CFrame
			local step = PEN.steps[spots]
			local colliders = {}
			for _, child in folder:GetChildren() do
				if child.Name == "Collider" then
					table.insert(colliders, child :: BasePart)
				end
			end
			expect.equal(#colliders, 5)
			local frontLength = 0
			for _, part in colliders do
				expect.equal(part.Transparency, 1)
				expect.truthy(part.CanCollide and part.Anchored)
				expect.falsy(part.CanTouch or part.CanQuery or part.CastShadow)
				expect.near(part.Size.Y, 3.2, 1e-3)
				local p = frame:PointToObjectSpace(part.CFrame.Position)
				expect.near(p.Y, 1.6, 1e-3)
				if near(p.Z, PEN.frontZ) then
					frontLength += part.Size.X
					expect.truthy(math.abs(p.X) - part.Size.X / 2 >= PEN.gateWidth / 2 - 1e-3) -- never in the gate gap
				end
			end
			expect.near(frontLength, step.w - PEN.gateWidth, 1e-3)
			finish(w)
		end
	end)

	-- Pens3 phase 3: LobbyBuilder's part budget counts every plot with this many runtime parts.
	t.test("no pen draws more parts than Bases.pen.maxParts; the full pen draws exactly that many", function()
		for spots = 3, 12 do
			local w = fresh()
			local model = plotModel(w, 1)
			local a = newPlayer(w, "A")
			w.pens[a] = pen(spots)
			BaseService.playerAdded(a)
			local parts = 0
			for _, d in (model:FindFirstChild("Pen") :: Instance):GetDescendants() do
				if d:IsA("BasePart") then
					parts += 1
				end
			end
			expect.truthy(parts <= PEN.maxParts)
			if spots == 12 then
				expect.equal(parts, PEN.maxParts)
			end
			finish(w)
		end
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
