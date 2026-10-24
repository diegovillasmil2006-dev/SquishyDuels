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
--     waitMin..waitMax s; wb (the pen is the whole base): a target is a walkable spot it reaches in a straight line
--     past every block (PenMath.clearPath), else it tries another; with none in its tries it waits waitMin s and looks
--     again; a walker stays on PenMath.walkArea's floor and out of its blocks for any number of steps (the whole base,
--     every rarity);
--   * newWalk(area, random): a fresh walker on a walkable spot of its area (the area's middle when its tries find
--     none), its first wait 0..firstWaitMax s, its speed speedMin..speedMax studs/s;
--   * wb: shelfCall(view): what the MY PEN window's shelf BUY button sends: PenBuyShelf with the price it shows (the
--     SHELF SPOTS sign's call); nothing when the button is disabled (short of Coins, MAX) or not there;
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
--     the band of the part's height (7 bands, bottom #FF6FA3 .. top #B98CFF), plain = nil (K:3882-3920);
--   * pens3 phase 11: shelfPlace(frame, slot, lift): a shelf squishy stands in its cubby (WorldLayout
--     Bases.pen.shelf.cubbies, Diego's 12, slot 13 + k - 1; Neon Sugar part 5: the TOP spot 24 is cubby 12), its bottom
--     on the cubby's floor (the root `lift` over it), facing the arch like the shelf; its coin label on the board above
--     the cubby (CHK:57: labelOver over the floor, labelZ in front); nil for any other slot;
--     start() builds no shelf squishy in Edit mode (no SD_Shelf on any base there, even with the 10 tagged bases).
--   * owner 2026-10-17 (shadows by the graphics level; Config.UI.Pen.shadows = {offAtOrBelow = 3, automatic = true}):
--     shadowsOn(setting, config): off at levels 1..offAtOrBelow, on above; Automatic (or no readable setting) as
--     config.automatic says; setShadows(model, on): off = no BasePart of a pen model casts a shadow, on = back exactly
--     as SquishyCache built it (the Root and the faces stay without one), any number of times, another model untouched;
--     applyShadows(pens, pool, on): every walker, shelf, TOP and pooled model gets setShadows, a model in none of them
--     keeps its own; refreshShadows(setting): the controller's state follows the level (debugState().shadows) and only
--     a change goes to applyShadows; start() watches the level (when it can be read) and destroy() lets go (engine
--     only). Edit mode has no live pen, so build()'s line and the real settings signal are checked in a Play test.

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

	t.test("a walker stays on the whole base's floor and out of its blocks for any number of steps (wb)", function()
		-- One of each rarity, read back from the base attribute.
		local looks = PenMath.decode("dragon.0.1.0;kitty_bread.0.1.0;butter.0.1.0;bird.0.1.0")
		expect.equal(#looks, 4)
		local rng = Random.new(7)
		local function random(): number
			return rng:NextNumber()
		end
		for _, look in looks do
			local studs = PenController.studsOf(look.kind)
			local area = PenMath.walkArea(studs)
			expect.truthy(area.minX < area.maxX and area.minZ < area.maxZ)
			local walk = PenController.newWalk(area, random)
			expect.truthy(walk.wait >= 0 and walk.wait <= P.firstWaitMax)
			expect.truthy(walk.speed >= P.speedMin and walk.speed <= P.speedMax)
			local minZ, maxZ = math.huge, -math.huge
			for _ = 1, 4000 do
				PenController.stepWalker(walk, 1 / 20, random)
				if not PenMath.walkable(area, walk.x, walk.z) then
					error(`{look.kind} stepped off its floor or into a block at ({walk.x}, {walk.z})`)
				end
				minZ, maxZ = math.min(minZ, walk.z), math.max(maxZ, walk.z)
			end
			expect.truthy(maxZ - minZ > 10) -- it roams the base, not one corner
		end
	end)

	t.test("stepWalker round the blocks: a target past one is not taken; with none it waits and looks again", function()
		-- A floor 10 × 10 with a wall down its middle (x 4..6, the whole depth).
		local area: any = {
			minX = 0,
			maxX = 10,
			minZ = 0,
			maxZ = 10,
			blocks = { { minX = 4, maxX = 6, minZ = -1, maxZ = 11 } },
		}
		local walk: any = { x = 1, z = 1, yaw = 0, wait = 0, speed = 2, rect = area }
		-- (9, 9) is across the wall: refused; (2, 8) is on this side: taken.
		expect.equal(PenController.stepWalker(walk, 0.1, randoms({ 0.9, 0.9, 0.2, 0.8 })), true)
		expect.near(walk.tx, 2, 1e-9)
		expect.near(walk.tz, 8, 1e-9)
		-- Every try across the wall: it stands waitMin s with no target, then looks again.
		local stuck: any = { x = 1, z = 1, yaw = 0, wait = 0, speed = 2, rect = area }
		local function across(): number
			return 0.9
		end
		expect.equal(PenController.stepWalker(stuck, 0.1, across), false)
		expect.equal(stuck.tx, nil)
		expect.near(stuck.wait, P.waitMin, 1e-9)
		expect.near(stuck.x, 1, 1e-9)
	end)

	t.test("newWalk starts on a walkable spot: a spot in a block is tried again (wb)", function()
		local area: any = {
			minX = 0,
			maxX = 10,
			minZ = 0,
			maxZ = 10,
			blocks = { { minX = 4, maxX = 6, minZ = 4, maxZ = 6 } },
		}
		local walk = PenController.newWalk(area, randoms({ 0.5, 0.5, 0.1, 0.2 })) -- (5, 5) is in the block
		expect.near(walk.x, 1, 1e-9)
		expect.near(walk.z, 2, 1e-9)
		-- No walkable spot in its tries: the area's middle (on the real base, always walkable: PenMath_Test).
		local open: any =
			{ minX = 0, maxX = 10, minZ = 0, maxZ = 4, blocks = { { minX = -1, maxX = 11, minZ = -1, maxZ = 5 } } }
		local fallback = PenController.newWalk(open, randoms(table.create(16, 0.1))) -- every try lands at (1, 0.4)
		expect.near(fallback.x, 5, 1e-9)
		expect.near(fallback.z, 2, 1e-9)
	end)

	t.test(
		"shelfCall: the window's shelf BUY button sends PenBuyShelf with the price it shows; nothing disabled",
		function()
			local remote, price = PenController.shelfCall({
				actions = {
					{ id = "sellAll", text = "SELL ALL", kind = "secondary" },
					{ id = "buyShelf", text = "BUY ROW 31M", kind = "secondary", price = 31_000_000 },
				},
			} :: any)
			expect.equal(remote, "PenBuyShelf")
			expect.equal(price, 31_000_000)
			-- Disabled (short of Coins, or MAX with no price) or not there: nothing to send.
			local short = {
				{
					id = "buyShelf",
					text = "BUY ROW 31M",
					kind = "secondary",
					reason = "Need 1 more Coin",
					price = 31_000_000,
				},
			}
			expect.equal(PenController.shelfCall({ actions = short } :: any), nil)
			local max = { { id = "buyShelf", text = "SHELF MAX", kind = "secondary", reason = "All open" } }
			expect.equal(PenController.shelfCall({ actions = max } :: any), nil)
			expect.equal(PenController.shelfCall({ actions = {} } :: any), nil)
		end
	)

	t.test("init / start / destroy run cleanly in Edit mode and leave nothing behind", function()
		local Workspace = game:GetService("Workspace")
		local effects = Scheduler.count()
		PenController.init()
		PenController.start()
		expect.truthy(Workspace:FindFirstChild("SD_PenClient") ~= nil)
		expect.equal(PenController.debugState().walkers, 0) -- no pen attributes in Edit mode: nothing is built
		expect.equal(PenController.debugState().shelved, 0) -- pens3 phase 11: nor on the shelves
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
	t.test(
		"pens3 phase 11: shelfPlace stands a squishy in its cubby facing the gate, its label above the cubby",
		function()
			local WorldLayout = t.requireShared("World/WorldLayout")
			local SHELF = WorldLayout.Bases.pen.shelf
			local frame = WorldLayout.plotFrame(3) :: CFrame
			local at = frame * SHELF.at
			local function near(a: Vector3, b: Vector3)
				expect.near((a - b).Magnitude, 0, 1e-3)
			end
			-- Slot 13: Diego's ShelfSlot_01, the bottom left seen from the pen floor (plot (-11.25, 2.7, -21.1)).
			local rest, label = PenController.shelfPlace(frame, 13, 0.9)
			near((rest :: CFrame).Position, frame * Vector3.new(-11.25, 2.7 + 0.9, -21.1))
			near((rest :: CFrame).LookVector, at.LookVector) -- toward the arch, like the shelf
			local over = SHELF.labelOver
			near((rest :: CFrame).Position + (label :: Vector3), at * Vector3.new(11.25, 2.7 + over, SHELF.labelZ))
			-- Slot 20: the 8th cubby (the right of the middle row); 21: the 9th (the top row's left); the TOP spot (24): the
			-- 12th (the top row's right).
			near((PenController.shelfPlace(frame, 20, 0) :: CFrame).Position, frame * Vector3.new(11.25, 9.7, -21.1))
			near((PenController.shelfPlace(frame, 21, 0) :: CFrame).Position, frame * Vector3.new(-11.25, 16.7, -21.1))
			local top, topLabel = PenController.shelfPlace(frame, 24, 1.5)
			near((top :: CFrame).Position, frame * Vector3.new(11.25, 16.7 + 1.5, -21.1))
			near((top :: CFrame).Position + (topLabel :: Vector3), at * Vector3.new(-11.25, 16.7 + over, SHELF.labelZ))
			for _, slot in { 0, 1, 12, 25 } do
				expect.equal(PenController.shelfPlace(frame, slot, 0), nil)
			end
		end
	)

	-- Owner 2026-10-17: the pen, shelf and TOP squishies cast shadows only on higher graphics.
	local Q = Enum.SavedQualitySetting

	-- Every BasePart's CastShadow, in GetDescendants order (two clones of one template list them alike).
	local function shadowFlags(model: Model): { boolean }
		local list = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(list, (d :: BasePart).CastShadow)
			end
		end
		return list
	end

	t.test("shadows: Config.UI.Pen.shadows is off at level 3 and below, on for Automatic", function()
		expect.deepEqual(P.shadows, { offAtOrBelow = 3, automatic = true })
	end)

	t.test(
		"shadowsOn: off at or below offAtOrBelow, on above it; Automatic or no setting as `automatic` says",
		function()
			local config = P.shadows
			expect.equal(PenController.shadowsOn(Q.Automatic, config), true)
			expect.equal(PenController.shadowsOn(Q.QualityLevel1, config), false)
			expect.equal(PenController.shadowsOn(Q.QualityLevel3, config), false)
			expect.equal(PenController.shadowsOn(Q.QualityLevel4, config), true)
			expect.equal(PenController.shadowsOn(Q.QualityLevel10, config), true)
			expect.equal(PenController.shadowsOn(nil, config), true) -- the setting cannot be read: like Automatic
			-- One switch: the same table decides the cut and Automatic.
			local other = { offAtOrBelow = 0, automatic = false }
			expect.equal(PenController.shadowsOn(Q.Automatic, other), false)
			expect.equal(PenController.shadowsOn(nil, other), false)
			expect.equal(PenController.shadowsOn(Q.QualityLevel1, other), true)
		end
	)

	t.test("setShadows: off = no part of a pen model casts one; on = back as built; other models untouched", function()
		local SquishyCache = t.requireClient("Models/SquishyCache")
		local model = SquishyCache.clone("kitty_bread", "World")
		local other = SquishyCache.clone("kitty_bread", "World")
		local built = shadowFlags(model)
		expect.truthy(table.find(built, true) ~= nil) -- the body casts one
		expect.truthy(table.find(built, false) ~= nil) -- the Root (and the faces) do not
		PenController.setShadows(model, false)
		PenController.setShadows(model, false) -- twice is fine
		for _, on in shadowFlags(model) do
			expect.equal(on, false)
		end
		expect.deepEqual(shadowFlags(other), built)
		PenController.setShadows(model, true)
		expect.deepEqual(shadowFlags(model), built) -- the Root and the faces stay without one
		PenController.setShadows(model, true)
		expect.deepEqual(shadowFlags(model), built)
		model:Destroy()
		other:Destroy()
	end)

	t.test("applyShadows: every walker, shelf, TOP and pooled model follows; other models are untouched", function()
		local SquishyCache = t.requireClient("Models/SquishyCache")
		local walker = SquishyCache.clone("kitty_bread", "World")
		local shelf = SquishyCache.clone("kitty_bread", "World")
		local top = SquishyCache.clone("kitty_bread", "World")
		local pooled = SquishyCache.clone("kitty_bread", "World")
		local other = SquishyCache.clone("kitty_bread", "World")
		local built = shadowFlags(other)
		local shelfSlots = { [13] = { model = shelf }, [21] = { model = top } } -- a shelf cubby and the TOP spot
		local pens = { [1] = { walkers = { { model = walker } }, shelf = shelfSlots } }
		local pool = { kitty_bread = { { model = pooled } } }
		local followers = { walker, shelf, top, pooled }
		PenController.applyShadows(pens, pool, false)
		for _, model in followers do
			for _, on in shadowFlags(model) do
				expect.equal(on, false)
			end
		end
		expect.deepEqual(shadowFlags(other), built)
		PenController.applyShadows(pens, pool, true)
		for _, model in followers do
			expect.deepEqual(shadowFlags(model), built)
		end
		expect.deepEqual(shadowFlags(other), built)
		for _, model in { walker, shelf, top, pooled, other } do
			model:Destroy()
		end
	end)

	t.test("refreshShadows: the level's answer goes to the pens (applyShadows) only when it changes", function()
		PenController.refreshShadows(Q.QualityLevel10) -- a known start: on
		local real = PenController.applyShadows
		local sent = {}
		PenController.applyShadows = function(_pens: any, _pool: any, on: boolean)
			table.insert(sent, on)
		end
		local ok, err = pcall(function()
			for _, step in
				{
					{ level = Q.QualityLevel1, on = false },
					{ level = Q.QualityLevel2, on = false },
					{ level = Q.QualityLevel8, on = true },
					{ level = Q.QualityLevel3, on = false },
					{ level = Q.Automatic, on = true },
					{ level = Q.QualityLevel4, on = true },
				}
			do
				PenController.refreshShadows(step.level)
				expect.equal(PenController.debugState().shadows, step.on)
			end
		end)
		PenController.applyShadows = real
		if not ok then
			error(err, 0)
		end
		expect.deepEqual(sent, { false, true, false, true })
	end)

	t.test("start() watches the graphics level and destroy() lets go (engine only)", function()
		local readable = pcall(function()
			return UserSettings():GetService("UserGameSettings").SavedQualityLevel
		end)
		PenController.start()
		expect.equal(PenController.debugState().watchingQuality, readable)
		PenController.destroy()
		expect.equal(PenController.debugState().watchingQuality, false)
	end)
end
