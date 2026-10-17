--!strict
-- PenController_Test: unit tests for StarterPlayerScripts.Client.Controllers.PenController (pens3 phase 1: the walking
-- pen squishies, their coin labels and the own PEN SPACE sign). Server only (ServerStorage.UnitTest). Edit mode: no
-- LocalPlayer and no running BaseService, so start() builds no squishy and owns no sign; its pure parts are tested here.
-- Contract (build plan work/pens3/PLAN.md "PHASE 1" Add 5; lobby design v6 kit.json K, "Squishy Lobby 3D.html" P3D):
--   * signState(price, coins): the own sign's state, trim colour + icon + text, never colour alone (K:4239-4265):
--     canBuy (PenSignCanBuy, img.coin, "Walk up to buy") once the Coins cover the price, tooExpensive
--     (PenSignTooExpensive, img.icon.lock, "Need {coins} more" with the missing Coins), max (PenSignMax, img.icon.star,
--     no line) without a price; no Coins yet count as 0;
--   * studsOf(kind): the longest side of a squishy by its rarity (Config.UI.Pen.rarityStuds, K:4052-4081): Common 2,
--     Uncommon 2.8, Epic 3.8, Exclusive 5; an unknown kind the Common's;
--   * hopLift(t, studs, reduced): A17 PenWanderHop (K:5890-5954): 0 at the loop's ends, hopHeight × the size (studs
--     over the Common's, P3D:834) at its middle, Sine Out up and Sine In down, the loop hopSeconds long; 0 under
--     ReducedMotion;
--   * labelText(look): "+{coins}/s" with Format.coins of the whole Coins a second (PenMath.itemRate);
--   * labelLayout(aspect): the coin icon and the text inside the 3.2 × 1.2 stud label, labelInner of its height, the
--     text as wide as its aspect asks, never past the label's width;
--   * stepWalker(walk, dt, random) (P3D:829-833): a wait counts down first; then a target inside the walk area; it
--     walks at its speed (never past the target), faces the way it walks (LookVector) and, within arriveStuds, waits
--     waitMin..waitMax s; a walker stays inside PenMath.wanderRect for any number of steps (a decode / wanderRect
--     bounds check with the plan's pen);
--   * newWalk(rect, random): a fresh walker somewhere in its area, its first wait 0..firstWaitMax s, its speed
--     speedMin..speedMax studs/s;
--   * init / start / destroy run cleanly in Edit mode and leave nothing behind (no Workspace.SD_PenClient, no Scheduler
--     effect). Engine only: the offline runner has no engine signals;
--   * pens3 phase 4: awayText(gift): the away pop-up's prize line ("{coins} Coins") and its body with the time away in
--     words (h, h + min, min, under a minute); nil (nothing to show) for a gift of no whole Coins; a gift in the state
--     shows the pop-up (Diego's congrats overlay in the SD_Prompt layer) once, a new gift replaces it, destroy() takes
--     it away. Engine only (the offline runner has no Destroying signal or CollectionService);
--   * pens3 phase 5: syncWaits(plot, own, revealOpen): the own pen's walkers wait while the box reveal plays (a copy
--     never walks in before its reveal; the reveal's close syncs it); every other base syncs at once;
--   * pens3 phase 6: tapHit(tap, points, minPx): the walker a tap lands on: the nearest whose middle is within its
--     drawn radius or minPx (whichever is bigger), none when the tap is past every reach; start() registers the "pen"
--     screen and destroy() takes it away (engine only, with the lifecycle case);
--   * pens3 phase 8: isFace(name): a part named with a face word (eye, mouth, shine, tongue, nostril, ... any case)
--     keeps its look; formColor(color, form, share): Golden = 0.7 of the way to #FFC93C, Rainbow = 0.75 of the way to
--     the band of the part's height (7 bands, bottom #FF6FA3 .. top #B98CFF), plain = nil (K:3882-3920).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local PenController = t.requireClient("Controllers/PenController")
	local StateController = t.requireClient("Controllers/StateController")
	local UIController = t.requireClient("Controllers/UIController")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local Config = t.requireShared("Config")
	local Format = t.requireShared("Util/Format")
	local PenMath = t.requireShared("PenMath")
	local Strings = t.requireShared("Strings")
	local P = Config.UI.Pen

	-- A scripted random source: the given values in turn, then 0.5.
	local function randoms(list: { number }): () -> number
		local index = 0
		return function(): number
			index += 1
			return list[index] or 0.5
		end
	end

	t.test("signState: trim colour, icon and text for can buy, too expensive and MAX (K:4239-4265)", function()
		expect.deepEqual(PenController.signState(1_500, 1_500), {
			state = "canBuy",
			trim = "PenSignCanBuy",
			icon = "img.coin",
			line = Strings.pen.sign.canBuy,
		})
		expect.deepEqual(PenController.signState(1_500, 1_200), {
			state = "tooExpensive",
			trim = "PenSignTooExpensive",
			icon = "img.icon.lock",
			line = Strings.format(Strings.pen.sign.needMore, { coins = Format.coins(300) }),
		})
		expect.equal(PenController.signState(1_500, 1_200).line, "Need 300 more")
		expect.deepEqual(PenController.signState(nil, 99), {
			state = "max",
			trim = "PenSignMax",
			icon = "img.icon.star",
			line = "",
		})
		-- No Coins state yet: 0 Coins.
		expect.equal(
			PenController.signState(1_500, nil).line,
			Strings.format(Strings.pen.sign.needMore, { coins = "1,500" })
		)
		expect.equal(PenController.signState(2_300_000, 1e9).state, "canBuy")
	end)

	t.test("studsOf: the longest side by rarity (K:4052-4081)", function()
		expect.equal(PenController.studsOf("kitty_bread"), 2)
		expect.equal(PenController.studsOf("butter"), 2.8)
		expect.equal(PenController.studsOf("bird"), 3.8)
		expect.equal(PenController.studsOf("dragon"), 5)
		expect.equal(PenController.studsOf("not_a_squishy"), 2)
	end)

	t.test(
		"hopLift: A17's hop, 0 at the ends and hopHeight × the size in the middle; flat under ReducedMotion",
		function()
			local half = P.hopSeconds / 2
			expect.near(PenController.hopLift(0, 2, false), 0, 1e-9)
			expect.near(PenController.hopLift(half, 2, false), P.hopHeight, 1e-9) -- a Common: size 1
			expect.near(PenController.hopLift(half, 5, false), P.hopHeight * 2.5, 1e-9) -- an Exclusive: size 2.5
			expect.near(PenController.hopLift(P.hopSeconds, 2, false), 0, 1e-9)
			-- Sine Out up: past the straight line on the way up; Sine In down: the mirror image.
			local quarter = PenController.hopLift(half / 2, 2, false)
			expect.near(quarter, P.hopHeight * math.sin(math.pi / 4), 1e-9)
			expect.near(PenController.hopLift(half * 1.5, 2, false), quarter, 1e-9)
			expect.truthy(quarter > P.hopHeight / 2)
			-- It loops.
			expect.near(PenController.hopLift(P.hopSeconds + half, 2, false), P.hopHeight, 1e-9)
			expect.equal(PenController.hopLift(half, 2, true), 0)
		end
	)

	t.test("labelText: +{coins}/s with the whole Coins a second", function()
		expect.equal(PenController.labelText({ kind = "kitty_bread", form = 0, level = 1, coat = 0 }), "+10/s")
		expect.equal(PenController.labelText({ kind = "dragon", form = 0, level = 1, coat = 0 }), "+640/s")
		-- Lv 2 earns 11.5: the label shows 11, as the pen pays whole Coins.
		expect.equal(PenController.labelText({ kind = "kitty_bread", form = 0, level = 2, coat = 0 }), "+11/s")
		local big = { kind = "dragon", form = 2, level = 70, coat = 7 }
		expect.equal(
			PenController.labelText(big),
			Strings.format(Strings.pen.rate, { coins = Format.coins(math.floor(PenMath.itemRate(big))) })
		)
	end)

	t.test("labelLayout: icon and text labelInner of the label's height, never wider than the label", function()
		local W, H = P.labelSize.X, P.labelSize.Y
		local short = PenController.labelLayout(1.5)
		expect.near(short.icon, P.labelInner * H / W, 1e-9)
		expect.near(short.gap, P.labelGap * H / W, 1e-9)
		expect.near(short.text, 1.5 * P.labelInner * H / W, 1e-9)
		expect.equal(short.height, P.labelInner)
		expect.truthy(short.icon + short.gap + short.text <= 1)
		local long = PenController.labelLayout(40)
		expect.near(long.icon + long.gap + long.text, 1, 1e-9)
		local broken = PenController.labelLayout(0 / 0)
		expect.truthy(broken.text >= 0 and broken.text <= 1)
	end)

	t.test(
		"stepWalker: wait first, then walk to a target at its speed, facing it, and wait on arrival (P3D:829-833)",
		function()
			local rect = { minX = 0, maxX = 10, minZ = 0, maxZ = 10 }
			local walk: any = { x = 0, z = 0, yaw = 0, wait = 0.5, speed = 2, rect = rect }
			-- Waiting: no move.
			expect.equal(PenController.stepWalker(walk, 0.2, randoms({})), false)
			expect.near(walk.wait, 0.3, 1e-9)
			expect.equal(PenController.stepWalker(walk, 0.3, randoms({})), false)
			-- A target at (10, 0) (random 1 then 0), then 1 s at 2 studs/s: 2 studs toward it, facing +X.
			expect.equal(PenController.stepWalker(walk, 1, randoms({ 1, 0 })), true)
			expect.near(walk.x, 2, 1e-9)
			expect.near(walk.z, 0, 1e-9)
			local look = CFrame.Angles(0, walk.yaw, 0).LookVector
			expect.near(look.X, 1, 1e-6)
			expect.near(look.Z, 0, 1e-6)
			-- Never past the target: 10 s more lands on it exactly.
			expect.equal(PenController.stepWalker(walk, 10, randoms({})), true)
			expect.near(walk.x, 10, 1e-9)
			-- Arrived: it waits waitMin + random × (waitMax - waitMin).
			expect.equal(PenController.stepWalker(walk, 0.1, randoms({ 0.5 })), false)
			expect.near(walk.wait, P.waitMin + 0.5 * (P.waitMax - P.waitMin), 1e-9)
			expect.equal(walk.tx, nil)
		end
	)

	t.test("a walker stays inside its walk area for any number of steps (decode / wanderRect bounds)", function()
		-- The plan's pen: Kitty Bread and the Dragon at 3 spots, read back from the base attribute.
		local looks = PenMath.decode("dragon.0.1.0;kitty_bread.0.1.0")
		expect.equal(#looks, 2)
		local rng = Random.new(7)
		local function random(): number
			return rng:NextNumber()
		end
		for _, look in looks do
			local studs = PenController.studsOf(look.kind)
			local rect: any = PenMath.wanderRect(3, studs)
			expect.truthy(rect ~= nil and rect.minX < rect.maxX and rect.minZ < rect.maxZ)
			local walk = PenController.newWalk(rect, random)
			expect.truthy(walk.wait >= 0 and walk.wait <= P.firstWaitMax)
			expect.truthy(walk.speed >= P.speedMin and walk.speed <= P.speedMax)
			for _ = 1, 2000 do
				PenController.stepWalker(walk, 1 / 20, random)
				local outside = walk.x < rect.minX - 1e-9 or walk.x > rect.maxX + 1e-9
				if outside or walk.z < rect.minZ - 1e-9 or walk.z > rect.maxZ + 1e-9 then
					error(`{look.kind} left its area at ({walk.x}, {walk.z})`)
				end
			end
		end
	end)

	t.test("init / start / destroy run cleanly in Edit mode and leave nothing behind", function()
		local Workspace = game:GetService("Workspace")
		local effects = Scheduler.count()
		PenController.init()
		PenController.start()
		expect.truthy(Workspace:FindFirstChild("SD_PenClient") ~= nil)
		expect.equal(PenController.debugState().walkers, 0) -- no pen attributes in Edit mode: nothing is built
		expect.equal(UIController.isRegistered("pen"), true) -- pens3 phase 6: the pen screen
		PenController.destroy()
		expect.equal(UIController.isRegistered("pen"), false)
		expect.equal(Workspace:FindFirstChild("SD_PenClient"), nil)
		expect.equal(Scheduler.count(), effects)
		expect.equal(PenController.debugState().started, false)
		PenController.destroy() -- twice is fine
	end)

	t.test(
		"tapHit: the nearest walker within its drawn radius or minPx; none past every reach (pens3 phase 6)",
		function()
			local points = {
				{ x = 100, y = 100, radius = 10 }, -- far: smaller than a finger
				{ x = 160, y = 100, radius = 60 }, -- near: big on the screen
			}
			expect.equal(PenController.tapHit(Vector2.new(100, 120), points, 28), 1) -- within minPx of the far one
			expect.equal(PenController.tapHit(Vector2.new(110, 130), points, 28), 2) -- past minPx: the near one's reach
			expect.equal(PenController.tapHit(Vector2.new(120, 100), points, 28), 2) -- both reach: the nearer share
			expect.equal(PenController.tapHit(Vector2.new(400, 400), points, 28), nil)
			expect.equal(PenController.tapHit(Vector2.new(100, 100), {}, 28), nil)
		end
	)

	t.test("syncWaits: only the own pen waits, and only while the box reveal plays (pens3 phase 5)", function()
		expect.equal(PenController.syncWaits(3, 3, true), true) -- a copy waits for its reveal
		expect.equal(PenController.syncWaits(3, 3, false), false)
		expect.equal(PenController.syncWaits(4, 3, true), false) -- another base: at once
		expect.equal(PenController.syncWaits(3, nil, true), false) -- no plot yet: nothing is own
	end)

	-- Pens3 phase 4: the coins-while-away pop-up (a stand-in on Diego's congrats overlay).
	t.test("awayText: the Coins as the prize and the time away in words; nothing to show for no Coins", function()
		local function line(time: string): string
			return Strings.format(Strings.away.body, { time = time })
		end
		local title, body = PenController.awayText({ coins = 1_800, seconds = 3600 })
		expect.equal(title, "1,800 Coins")
		expect.equal(body, line("1 h"))
		title, body = PenController.awayText({ coins = 12_345, seconds = 3725 })
		expect.equal(title, "12,345 Coins")
		expect.equal(body, line("1 h 2 min"))
		expect.equal(select(2, PenController.awayText({ coins = 50, seconds = 600 })), line("10 min"))
		expect.equal(select(2, PenController.awayText({ coins = 5, seconds = 30 })), line(Strings.away.underMinute))
		expect.equal(
			(PenController.awayText({ coins = 2_850_000_000_000_000, seconds = 90 * 86400 })),
			`{Format.coins(2_850_000_000_000_000)} Coins`
		)
		for _, gift in
			{ nil, {}, { coins = 0, seconds = 99 }, { coins = -3, seconds = 9 }, { coins = 0 / 0 } } :: { any }
		do
			expect.equal((PenController.awayText(gift)), nil)
		end
	end)

	t.test("a gift shows the away pop-up once; a new gift replaces it; destroy takes it away (engine only)", function()
		local layer = UIController.screenGui(Config.UI.confirm.layerName, Config.UI.confirm.layer)
		local function overlays(): number
			local count = 0
			for _, child in layer:GetChildren() do
				if child.Name == "SD_Congrats" then
					count += 1
				end
			end
			return count
		end
		local before = overlays()
		PenController.start()
		StateController.setOverride("awayGift", { coins = 1_800, seconds = 3600 })
		expect.equal(overlays(), before + 1)
		local column = (layer:FindFirstChild("SD_Congrats") :: any).Column
		expect.equal(column.Title.Pose.Text.Text, "1,800 Coins")
		expect.equal(column.Description.Pose.Text.Text, Strings.format(Strings.away.body, { time = "1 h" }))
		StateController.setOverride("awayGift", { coins = 1_800, seconds = 3600 }) -- the same gift: no second pop-up
		expect.equal(overlays(), before + 1)
		StateController.setOverride("awayGift", { coins = 2_000, seconds = 4000 }) -- a new gift replaces it
		expect.equal(overlays(), before + 1)
		PenController.destroy()
		expect.equal(overlays(), before)
		StateController.setOverride("awayGift", nil)
	end)

	t.test(
		"pens3 phase 8: isFace keeps the face; formColor blends Golden 0.7 and Rainbow 0.75 by height band",
		function()
			for _, name in
				{ "EyeL", "MouthL", "ShineR", "Tongue", "NostrilL", "SquishMouth", "Pupil", "BrowL", "Blush" }
			do
				expect.truthy(PenController.isFace(name))
			end
			for _, name in { "Body", "Head", "EarL", "Tail1", "Wrapper" } do
				expect.falsy(PenController.isFace(name))
			end
			local white = Color3.new(1, 1, 1)
			local function same(a: Color3?, b: Color3): boolean
				return a ~= nil
					and math.abs(a.R - b.R) < 1e-6
					and math.abs(a.G - b.G) < 1e-6
					and math.abs(a.B - b.B) < 1e-6
			end
			expect.equal(PenController.formColor(white, 0, 0.5), nil)
			expect.truthy(same(PenController.formColor(white, 1, 0.5), white:Lerp(Color3.fromHex("#FFC93C"), 0.7)))
			expect.truthy(same(PenController.formColor(white, 2, 0), white:Lerp(Color3.fromHex("#FF6FA3"), 0.75)))
			expect.truthy(same(PenController.formColor(white, 2, 0.5), white:Lerp(Color3.fromHex("#8DF27A"), 0.75)))
			expect.truthy(same(PenController.formColor(white, 2, 1), white:Lerp(Color3.fromHex("#B98CFF"), 0.75)))
			expect.truthy(same(PenController.formColor(white, 2, -1), white:Lerp(Color3.fromHex("#FF6FA3"), 0.75)))
		end
	)
end
