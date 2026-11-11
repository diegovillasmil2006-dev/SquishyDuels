--!strict
-- JoyFx_Test: unit tests for ReplicatedStorage.Shared.Config.JoyFx (big job 2026-11-10: the everyday moments' candy
-- look). Edit mode, data only.
-- Contract:
--   * every name a moment plays exists (a FeelVfxBuilder template or a ring of this config), and Anim/FeelFx finds
--     every table it reads on a moment config;
--   * the phone budget holds: no moment emits more than Config.Vfx.Budgets.liveParticlesPerEffect particles, no piece
--     lives longer than 1 second (a short tail), and a squeeze's big pop stays within that budget too;
--   * the kit pictures the looks use have ids; no colour is a blood red.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
	requireFake: (name: string) -> any,
}

return function(t: Context)
	local JoyFx = t.requireShared("Config/JoyFx")
	local Config = t.requireShared("Config")
	local AssetTable = t.requireShared("AssetTable")
	local expect = t.expect
	local budget = Config.Vfx.Budgets.liveParticlesPerEffect

	local function builder(): any
		local SDTools = game:GetService("ServerStorage"):FindFirstChild("SDTools")
		local builders = SDTools and SDTools:FindFirstChild("Builders")
		local module = builders and builders:FindFirstChild("FeelVfxBuilder")
		return if module then (require :: any)(module:Clone()) else nil
	end

	t.test("every name a moment plays exists; a moment stays within the particle budget", function()
		local build = builder()
		expect.truthy(build ~= nil)
		local specs = build.SPECS
		for name, events in JoyFx.moments do
			local total = 0
			for _, ev in events do
				expect.truthy(type(ev.t) == "number" and ev.t >= 0 and ev.t <= 0.3) -- the whole burst starts at once
				if ev.burst then
					local spec = specs[ev.burst]
					if spec == nil or spec.Count == nil then
						error(`{name}: no burst template {ev.burst}`)
					end
					total += spec.Count
					expect.truthy(spec.Lifetime[2] <= 1)
				elseif ev.ring then
					local ring = JoyFx.rings[ev.ring]
					if ring == nil then
						error(`{name}: no ring {ev.ring}`)
					end
					expect.truthy(ring.time <= 0.5)
				else
					error(`{name}: an event that is neither a burst nor a ring`)
				end
			end
			expect.truthy(total > 0 and total <= budget)
		end
		-- The unlock adds a layer (a bigger prize): more events than the plain level-up.
		expect.truthy(#JoyFx.moments.levelUpUnlock > #JoyFx.moments.levelUp)
	end)

	t.test("Anim/FeelFx finds every table it reads on a moment config", function()
		for _, key in
			{
				"rings",
				"texts",
				"poses",
				"dips",
				"shakes",
				"fovs",
				"lines",
				"afterimages",
				"glows",
				"lights",
				"flashes",
				"screens",
				"punches",
				"slowmos",
				"sounds",
			}
		do
			expect.equal(type(JoyFx[key]), "table")
		end
		expect.equal(type(JoyFx.posePriority), "number")
	end)

	t.test("the squeeze and the pen coin: short, sized to read, within the budget", function()
		local s = JoyFx.squeeze
		expect.truthy(s.starShare > 0 and s.starShare < 1)
		for _, look in { s.puff, s.star, s.pop, s.bigPop.heart, JoyFx.penCoin } do
			expect.truthy(look.lifetime[1] > 0 and look.lifetime[1] <= look.lifetime[2] and look.lifetime[2] <= 1)
			expect.truthy(look.speed[1] <= look.speed[2])
			local peak = 0
			for _, key in look.size do
				peak = math.max(peak, key[2])
			end
			expect.truthy(peak >= 0.6 and peak <= 1.2) -- reads from the third-person camera, never covers the player
		end
		-- The biggest squeeze: the top rarity's puffs, its steam, the big pop's sparkles, hearts and stars.
		local most = Config.Vfx.Effects.squeezePuffs + s.bigPop.hearts + s.bigPop.stars
		expect.truthy(most <= budget)
		expect.truthy(JoyFx.penCoin.everySeconds >= 0.5)
	end)

	t.test("the look sparkle keeps the design's limits: 12 squishies, small, short, within the total budget", function()
		local s = JoyFx.lookSparkle
		expect.equal(s.maxActive, 12)
		expect.truthy(s.size[1] >= 0.25 and s.size[1] <= s.size[2] and s.size[2] <= 0.45)
		expect.truthy(s.lifetime[1] > 0 and s.lifetime[1] <= s.lifetime[2] and s.lifetime[2] <= 1)
		expect.truthy(s.speed[1] <= s.speed[2])
		expect.truthy(s.reach.inside < 1 and s.reach.outside >= 1)
		-- every squishy twinkling at the top rate still leaves most of the particle budget free
		expect.truthy(s.maxActive * 3 * s.lifetime[2] <= Config.Vfx.Budgets.liveParticlesTotal / 3)
	end)

	t.test("the candy kit pictures have ids; the UI numbers are sane", function()
		for _, key in { "img.kit.star", "img.kit.starGold", "img.kit.heart", "img.kit.sparkle", "img.kit.puff", "img.coin" } do
			expect.truthy(AssetTable.image(key) ~= nil)
		end
		local ui = JoyFx.ui
		expect.truthy(ui.starPx >= 24) -- the ink outline still reads at the phones' 0.65 UI scale
		expect.truthy(ui.sparkStarScale >= 1 and ui.sparkStarScale <= 2)
		expect.truthy(ui.heartEvery >= 2)
		expect.truthy(ui.coreSeconds <= 0.1 * 2) -- the hot frame: gone within 0.2 s
		expect.equal(ui.heartFromTier.small, nil) -- small prizes stay small: no hearts
		expect.equal(ui.heartFromTier.medium, nil)
	end)

	t.test("no ring is a blood red", function()
		for _, ring in JoyFx.rings do
			local h, sat = ring.color:ToHSV()
			local red = (h < 15 / 360 or h > 345 / 360) and sat > 0.45
			expect.truthy(not red)
		end
	end)
end
