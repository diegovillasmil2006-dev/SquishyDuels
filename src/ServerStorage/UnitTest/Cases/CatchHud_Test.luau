--!strict
-- CatchHud_Test: unit tests for StarterPlayerScripts.Client.UI.CatchHud (rework Option A, the catch: owner 2026-11-12
-- "Yes, build it"; Claude Design's catch canvas). Server only (ServerStorage.UnitTest). Edit mode: the screen is built
-- in a loose ScreenGui with a private scheduler ticked by hand.
-- Contract:
--   * meterView: "CATCH" and "{have}/{total} here", the fill miss / need (0 without a need, never past full); a sure
--     catch reads "SURE CATCH!" and fills the bar;
--   * cardView: the title by rarity (CAUGHT!, RARE CATCH!, EPIC CATCH!, LEGENDARY!), the squishy's name, its rarity's
--     label, pips and colour, NEW!, "{have}/{total} in this zone" and its share; nil for an unknown squishy;
--   * the screen: the meter shows and hides; the chip only when asked; a card hides the meter and the chip while it
--     shows and goes after inMs + holdMs + outMs (the meter back), or outMs after hideCard(); a Legendary card has the
--     rays, a Rare one the ring;
--     the fly ends with "+1" and leaves nothing behind; destroy removes everything.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local CatchHud = t.requireClient("UI/CatchHud")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local S = Strings.highway.catch
	local CARD = Config.Economy.Catch.ui.card

	-- The first squishy of each rarity in the catalog.
	local function ofRarity(rarity: string): string?
		for _, def in Catalog.list() do
			if def.rarity == rarity then
				return def.id
			end
		end
		return nil
	end

	local function made(): (any, ScreenGui, any)
		local gui = Instance.new("ScreenGui")
		local scheduler = Scheduler.new(false)
		local hud = CatchHud.new({
			gui = gui,
			scheduler = scheduler,
			scale = function(): number
				return 1
			end,
			reduced = function(): boolean
				return false
			end,
		})
		return hud, gui, scheduler
	end

	local function find(gui: Instance, name: string): GuiObject?
		local found = gui:FindFirstChild(name, true)
		return if found and found:IsA("GuiObject") then found else nil
	end

	local function run(scheduler: any, seconds: number)
		for _ = 1, math.ceil(seconds * 60) do
			scheduler:tick("render", 1 / 60)
		end
	end

	t.test("meterView: CATCH, x/y here and miss / need; SURE CATCH! full", function()
		local view = CatchHud.meterView(3, 8, 4, 11, false)
		expect.equal(view.title, S.meter)
		expect.equal(view.here, Strings.format(S.here, { have = 4, total = 11 }))
		expect.near(view.fill, 3 / 8, 1e-9)
		expect.equal(view.sure, false)
		expect.equal(CatchHud.meterView(0, 0, 0, 7, false).fill, 0) -- no landing yet
		expect.equal(CatchHud.meterView(12, 8, 0, 7, false).fill, 1) -- never past full
		local sure = CatchHud.meterView(0, 8, 0, 7, true)
		expect.equal(sure.title, S.sure)
		expect.equal(sure.fill, 1)
		expect.equal(S.meter, "CATCH")
		expect.equal(S.sure, "SURE CATCH!")
	end)

	t.test("cardView: the title by rarity, the name, the pill, NEW! and the zone line", function()
		local titles = { Common = "CAUGHT!", Uncommon = "CAUGHT!", Rare = "RARE CATCH!", Epic = "EPIC CATCH!" }
		titles.Exclusive = "LEGENDARY!"
		for rarity, title in titles do
			local id = ofRarity(rarity)
			if id ~= nil then
				local view = CatchHud.cardView(id, true, 5, 11)
				expect.equal(view.title, title)
				expect.equal(view.name, Strings.resolve(Catalog.get(id).nameKey))
				expect.equal(view.isNew, true)
				expect.equal(view.zone, Strings.format(S.inZone, { have = 5, total = 11 }))
				expect.near(view.fill, 5 / 11, 1e-9)
				expect.truthy(view.pips >= 1 and view.pips <= 5)
				expect.truthy(view.rank >= 1 and view.rank <= 5)
			end
		end
		expect.equal(CatchHud.cardView("no_such_squishy", true, 0, 0), nil)
		expect.equal(CatchHud.cardView(ofRarity("Common") :: string, false, 0, 0).fill, 0)
	end)

	t.test("the screen: the meter and chip; a card hides them, then goes and they come back", function()
		local hud, gui, scheduler = made()
		local meter = find(gui, "CatchMeter") :: GuiObject
		expect.equal(meter.Visible, false)
		hud:setMeter(CatchHud.meterView(1, 4, 2, 7, false))
		expect.equal(meter.Visible, true)
		expect.equal(find(gui, "CatchChip"), nil) -- built only when asked
		hud:setChip(true)
		local chip = find(gui, "CatchChip") :: GuiObject
		expect.equal(chip.Visible, true)
		local rare = ofRarity("Rare") :: string
		hud:showCard(CatchHud.cardView(rare, true, 1, 7))
		expect.equal(hud:cardShowing(), true)
		expect.equal(meter.Visible, false)
		expect.equal(chip.Visible, false)
		local card = find(gui, "CatchCard") :: GuiObject
		expect.truthy(card:FindFirstChild("Ring") ~= nil) -- Rare: the rarity ring
		expect.truthy(card:FindFirstChild("New") ~= nil)
		hud:setMeter(CatchHud.meterView(0, 4, 3, 7, false)) -- the meter stays hidden under the card
		expect.equal(meter.Visible, false)
		run(scheduler, (CARD.inMs + CARD.holdMs + CARD.outMs) / 1000 + 0.1)
		expect.equal(hud:cardShowing(), false)
		expect.equal(find(gui, "CatchCard"), nil)
		hud:setMeter(CatchHud.meterView(0, 4, 3, 7, false))
		expect.equal(meter.Visible, true)
		hud:setMeter(nil)
		expect.equal(meter.Visible, false)
		hud:showCard(CatchHud.cardView(rare, false, 2, 7)) -- hideCard: out at once (the shot ended)
		run(scheduler, CARD.inMs / 1000 / 2)
		hud:hideCard()
		run(scheduler, CARD.outMs / 1000 + 0.1)
		expect.equal(hud:cardShowing(), false)
		expect.equal(find(gui, "CatchCard"), nil)
		hud:hideCard() -- nothing shown: nothing happens
		hud:destroy()
		expect.equal(#gui:GetChildren(), 0)
		expect.equal(scheduler:count("render"), 0)
	end)

	t.test("a Legendary card turns its rays; the fly ends with +1 and leaves nothing", function()
		local hud, gui, scheduler = made()
		local legend = ofRarity("Exclusive")
		if legend ~= nil then
			hud:showCard(CatchHud.cardView(legend, false, 1, 7))
			local card = find(gui, "CatchCard") :: GuiObject
			expect.equal(card:FindFirstChild("New"), nil)
			local rays = 0
			for _, d in card:GetChildren() do
				rays += if d:IsA("ImageLabel") and d.Name ~= "Glow" and d.Name ~= "Star1" and d.Name ~= "Star2"
					then 1
					else 0
			end
			expect.truthy(rays >= 1)
		end
		local target = Instance.new("Frame")
		target.Size = UDim2.fromOffset(56, 56)
		target.Parent = gui
		hud:fly(ofRarity("Common") :: string, Color3.new(1, 1, 1), target)
		expect.truthy(find(gui, "CatchFly") ~= nil)
		run(scheduler, Config.Economy.Catch.ui.fly.ms / 1000 + 0.05)
		local plus = find(gui, "Plus")
		expect.truthy(plus ~= nil and plus.Visible)
		run(scheduler, Config.Economy.Catch.ui.fly.plusMs / 1000 + 0.05)
		expect.equal(find(gui, "CatchFly"), nil)
		hud:destroy()
		target:Destroy()
		expect.equal(#gui:GetChildren(), 0)
		expect.equal(scheduler:count("render"), 0)
	end)
end
