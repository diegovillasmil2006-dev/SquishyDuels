--!strict
-- BaseService_Test: unit tests for ServerScriptService.Server.Services.BaseService with injected fakes (a recorded
-- task.delay that the test runs by hand, a fake plot spawn); players are Folder instances (they carry the SD_Plot
-- attribute) or plain tables. Server only (ServerStorage.UnitTest). Edit mode: no Player, no world.
-- Contract (lobby bases spec 2026-10-11 §2, §4, §6; build plan Phase 3):
--   * 10 plots (WorldLayout.Bases); a joining player gets the lowest free plot, shown in the SD_Plot attribute; a plot
--     freed on leave is handed out again; rejoining gives the lowest free plot (the capsules live in the profile);
--   * with no plot free the player waits in the hub: the service tries again every 0.5 s for 5 s (10 tries) and gives
--     the plot that frees meanwhile; after 5 s it stops; a waiting player who leaves stops the retries;
--   * the plot's spawn is asked for the plot handed out and used only once the world has one (Phase 4);
--   * the owner view (Phase 4, spec §4, §8): a plot with an owner shows their display name on its name sign and its
--     colour (Bases.colors) on every SD_BaseTint part; an open plot shows "Open plot" and the grey; the owner's capsules
--     from their ready profile: an open slot holds its tier's capsule template (Capsule_<look>) on its spot with
--     "Lv <level>" and its squishy (Squishy_<id>) on the seat, a locked slot the Lock with "Unlock · <price>", and
--     capsule 1's squishy stands as the statue (Statue_<id>); refresh(player) redraws (no duplicates); without the
--     templates, the plot's model or a ready profile, only the name and colour change and nothing fails;
--   * Phase 5: every capsule carries its level (SD_Level) and its squishy (SD_Squishy, none when empty), so every
--     client can show a read-only card and play the upgrade burst for any base.

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
		templates: Instance?,
		capsules: { [any]: any }, -- player -> a ready profile's capsules
	}

	local function fresh(): World
		local w: World = { delays = {}, asked = {}, made = {}, models = {}, templates = nil, capsules = {} }
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
			templates = function(): Instance?
				return w.templates
			end,
			capsulesOf = function(player: any): any
				return w.capsules[player]
			end,
			displayNameOf = function(player: any): string
				return "Name of " .. tostring(if typeof(player) == "Instance" then player.Name else "table")
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
		-- Rejoining gives the lowest free plot, maybe another one (the capsule levels live in the profile).
		BaseService.playerAdded(b)
		expect.equal(BaseService.plotOf(b), 4)
		expect.equal(#w.delays, 0)
		-- A player who is not an Instance (a plain table) gets a plot too, without the attribute.
		local plain = { UserId = 5 }
		BaseService.playerAdded(plain :: any)
		expect.equal(BaseService.plotOf(plain), 5)
		finish(w)
	end)

	-- The owner view (Phase 4) -----------------------------------------------------------------------------------

	local Palette = t.requireShared("Art/Palette")
	local Strings = t.requireShared("Strings")
	local Format = t.requireShared("Util/Format")
	local CapsuleMath = t.requireShared("CapsuleMath")

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

	-- Templates like CapsuleBuilder's: a capsule per look with a Level label and SD_SeatY, the Lock with its Price
	-- label, squishies and statues (one part each).
	local function templates(w: World): Folder
		local root = Instance.new("Folder")
		root.Name = "Capsules"
		local function template(name: string, label: string?): Model
			local model = Instance.new("Model")
			model.Name = name
			local part = Instance.new("Part")
			part.Parent = model
			if label then
				local gui = Instance.new("SurfaceGui")
				gui.Parent = part
				local text = Instance.new("TextLabel")
				text.Name = label
				text.Parent = gui
			end
			model.WorldPivot = CFrame.identity
			model.Parent = root
			return model
		end
		for _, look in { "foam", "jelly", "marshmallow" } do
			template("Capsule_" .. look, "Level"):SetAttribute("SD_SeatY", 1.5)
		end
		template("Lock", "Price")
		template("Squishy_kitty_bread")
		template("Statue_kitty_bread")
		template("Squishy_toast")
		template("Statue_toast")
		w.templates = root
		table.insert(w.made, root)
		return root
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

	local function labelOf(model: Instance, name: string): string
		return (model:FindFirstChild(name, true) :: TextLabel).Text
	end

	local function near(a: CFrame, b: CFrame): boolean
		return (a.Position - b.Position).Magnitude < 1e-3 and (a.LookVector - b.LookVector).Magnitude < 1e-3
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

	t.test(
		"the owner's capsules: tier look with Lv, the squishy on the seat, locks with prices, the statue (§4)",
		function()
			local w = fresh()
			local model = plotModel(w, 1)
			templates(w)
			local a = newPlayer(w, "A")
			local list: { any } = { { level = 3, squishyId = "kitty_bread" }, { level = 15 } }
			w.capsules[a] = { slots = 2, list = list }
			BaseService.playerAdded(a)
			local folder = model:FindFirstChild("Capsules") :: Folder
			expect.truthy((folder :: Folder?) ~= nil)
			local frame = WorldLayout.plotFrame(1) :: CFrame
			local spots = WorldLayout.Bases.capsuleSpots
			-- Slot 1: Lv 3 is Foam (tier 1), holding Kitty Bread on its seat (1.5 up).
			local first = folder:FindFirstChild("Capsule1") :: Model
			expect.truthy((first :: Model?) ~= nil)
			expect.truthy(near(first:GetPivot(), frame * spots[1]))
			expect.equal(
				labelOf(first, "Level"),
				Strings.format(Strings.resolve("base.capsuleLevel") :: string, { level = 3 })
			)
			local squishy = folder:FindFirstChild("Squishy1") :: Model
			expect.truthy(
				(squishy :: Model?) ~= nil and near(squishy:GetPivot(), frame * spots[1] * CFrame.new(0, 1.5, 0))
			)
			-- Slot 2: Lv 15 is Jelly (tier 2), empty.
			local second = folder:FindFirstChild("Capsule2") :: Model
			expect.truthy((second :: Model?) ~= nil)
			expect.equal(second:GetAttribute("SD_SeatY"), 1.5)
			expect.equal(CapsuleMath.tier(15), 2)
			expect.equal(labelOf(second, "Level"), "Lv 15")
			expect.equal(folder:FindFirstChild("Squishy2"), nil)
			-- Slots 3 and 4 are locked: the Lock with the slot's price.
			for slot = 3, 4 do
				local lock = folder:FindFirstChild("Lock" .. slot) :: Model
				expect.truthy((lock :: Model?) ~= nil and near(lock:GetPivot(), frame * spots[slot]))
				local price = CapsuleMath.slotPrice(slot) :: number
				local want =
					Strings.format(Strings.resolve("base.unlockPrice") :: string, { coins = Format.coins(price) })
				expect.equal(labelOf(lock, "Price"), want)
			end
			-- The statue: capsule 1's squishy on the back wall's plinth.
			local statue = folder:FindFirstChild("Statue") :: Model
			expect.truthy((statue :: Model?) ~= nil and near(statue:GetPivot(), frame * WorldLayout.Bases.statue))
			expect.equal(#folder:GetChildren(), 6) -- 2 capsules, 1 squishy, 2 locks, the statue
			-- Which template each came from: the look by the tier, the squishy by its id.
			expect.equal(first:GetAttribute("SD_Template"), "Capsule_foam")
			expect.equal(second:GetAttribute("SD_Template"), "Capsule_jelly")
			expect.equal(squishy:GetAttribute("SD_Template"), "Squishy_kitty_bread")
			expect.equal(statue:GetAttribute("SD_Template"), "Statue_kitty_bread")
			-- Leaving clears it all.
			BaseService.playerRemoving(a)
			expect.equal(model:FindFirstChild("Capsules"), nil)
			finish(w)
		end
	)

	t.test("every capsule carries its level and squishy for the clients' cards (Phase 5)", function()
		local w = fresh()
		local model = plotModel(w, 1)
		templates(w)
		local a = newPlayer(w, "A")
		local list: { any } = { { level = 3, squishyId = "kitty_bread" }, { level = 15 } }
		w.capsules[a] = { slots = 2, list = list }
		BaseService.playerAdded(a)
		local folder = model:FindFirstChild("Capsules") :: Folder
		local first = folder:FindFirstChild("Capsule1") :: Model
		local second = folder:FindFirstChild("Capsule2") :: Model
		expect.equal(first:GetAttribute("SD_Level"), 3)
		expect.equal(first:GetAttribute("SD_Squishy"), "kitty_bread")
		expect.equal(second:GetAttribute("SD_Level"), 15)
		expect.equal(second:GetAttribute("SD_Squishy"), nil) -- empty
		finish(w)
	end)

	t.test("refresh(player) redraws after a capsule change, without duplicates; the profile can come later", function()
		local w = fresh()
		local model = plotModel(w, 1)
		templates(w)
		local a = newPlayer(w, "A")
		BaseService.playerAdded(a) -- the profile is still loading: name and colour only
		expect.equal(ownerText(model), "Name of A")
		expect.equal(model:FindFirstChild("Capsules"), nil)
		w.capsules[a] = { slots = 1, list = { { level = 1 } } }
		BaseService.refresh(a) -- the profile loaded (the data port's Loaded)
		local folder = model:FindFirstChild("Capsules") :: Folder
		expect.equal(#folder:GetChildren(), 4) -- 1 capsule, 3 locks; no squishy, no statue
		local list: { any } = { { level = 2, squishyId = "toast" }, { level = 1 } }
		w.capsules[a] = { slots = 2, list = list }
		BaseService.refresh(a) -- CapsuleService: an unlock and a set
		local capsules = 0
		for _, child in model:GetChildren() do
			if child.Name == "Capsules" then
				capsules += 1
			end
		end
		expect.equal(capsules, 1)
		folder = model:FindFirstChild("Capsules") :: Folder
		expect.equal(#folder:GetChildren(), 6) -- 2 capsules, the toast, 2 locks, the statue
		expect.equal((folder:FindFirstChild("Statue") :: Instance):GetAttribute("SD_Template"), "Statue_toast")
		expect.equal(labelOf(folder:FindFirstChild("Capsule1") :: Instance, "Level"), "Lv 2")
		-- A player without a plot: nothing happens.
		BaseService.refresh(newPlayer(w, "Nobody"))
		finish(w)
	end)

	t.test("without templates, the plot's model or a known squishy, only what can be drawn is drawn", function()
		local w = fresh()
		local a = newPlayer(w, "A")
		w.capsules[a] = { slots = 1, list = { { level = 1, squishyId = "kitty_bread" } } }
		BaseService.playerAdded(a) -- no plot model: nothing to draw, nothing fails
		expect.equal(BaseService.plotOf(a), 1)
		local model = plotModel(w, 1)
		BaseService.refresh(a) -- no templates: the name and the colour only
		expect.equal(ownerText(model), "Name of A")
		expect.equal(model:FindFirstChild("Capsules"), nil)
		templates(w)
		w.capsules[a] = { slots = 1, list = { { level = 1, squishyId = "not_a_squishy" } } }
		BaseService.refresh(a)
		local folder = model:FindFirstChild("Capsules") :: Folder
		expect.truthy(folder:FindFirstChild("Capsule1") ~= nil)
		expect.equal(folder:FindFirstChild("Squishy1"), nil)
		expect.equal(folder:FindFirstChild("Statue"), nil)
		finish(w)
	end)

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
