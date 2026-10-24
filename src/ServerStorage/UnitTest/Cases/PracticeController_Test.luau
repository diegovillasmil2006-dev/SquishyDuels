--!strict
-- PracticeController_Test: unit tests for the pure parts of StarterPlayerScripts.Client.Controllers.PracticeController.
-- Server only (ServerStorage.UnitTest). Edit mode: init() is not called (no zone checks, no GUIs, no remotes).
-- Contract (DESIGN §5.11, §7.6, §9.8 practice target row, §11.6 practice panel):
--   * a hit target tips back "down" and stays down for Config.Combat.Practice.targetDownSeconds (the server's down
--     time), then springs back up; its body squashes and wobbles back to rest;
--   * the target pivot slides only along Z (the moving target's rail) and tips back away from the thrower (-X);
--   * accuracy is whole percent of hits / throws (0 with no throws);
--   * an impact without targetId matches the nearest target at the impact's server time, within a few studs (the
--     moving target is found where PracticeTargets puts it at that time);
--   * the practice reticle (§5.10, §11.6): hidden outside the Practice context; ready = dot + "Ready", cooling =
--     fill + remaining seconds, blocked = cross + the reason; never colour alone; the hit marker pops 1.3 -> 1 in
--     250 ms (§9.8), not at all under ReducedMotion;
--   * the reticle's "Hit!" (§18.4.2) pops 1.3 -> 1 (Back Out, 200 ms) and tilts ±6° -> 0 (the sign alternates per
--     hit), with no scale or tilt under ReducedMotion;
--   * Part 8 (§11.2): the practice panel finds a free spot (under the left HUD column, else at the right edge under the
--     top-right row, the data line and the queue pill) at 667×375, 1280×720 and 1920×1080, Medium and the largest
--     text, mouse and touch: inside the screen, over nothing (equipped card, thumbstick zone, touch buttons); with no
--     free spot it stays on screen at the left and says so (fits = false);
--   * foam fix 2: the panel keeps its title on every layout; a third spot on the top row, left of the top-right items,
--     takes it when the left and right spots are not free, so on phones it stays out of the thumbstick zone (a share of
--     the whole screen's height, HudFormat.thumbstickZone);
--   * lobby HUD (spec 2026-10-11): the Duel CTA at the top middle is one of the frames above the panel; on phones the
--     right edge under the Settings tile is free.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local PracticeController = t.requireClient("Controllers/PracticeController")
	local PracticeTargets = t.requireShared("Practice/PracticeTargets")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local downSeconds = Config.Combat.Practice.targetDownSeconds

	t.test("a hit target falls back, stays down for targetDownSeconds, then rises to rest", function()
		local start = PracticeController.downAngle(0)
		expect.near(start, 0, 1e-9)
		local down = PracticeController.downAngle(downSeconds / 2)
		expect.truthy(down > 45)
		local justBefore, doneBefore = PracticeController.downAngle(downSeconds - 0.01)
		expect.near(justBefore, down, 1e-9)
		expect.falsy(doneBefore)
		local rising, risingDone = PracticeController.downAngle(downSeconds + 0.1)
		expect.truthy(rising < down)
		expect.falsy(risingDone)
		local rest, done = PracticeController.downAngle(downSeconds + 5)
		expect.equal(rest, 0)
		expect.truthy(done)
		-- The down time is the server's (PracticeService keeps a hit target down for the same time).
		local longer = PracticeController.downAngle(2.5, 3)
		expect.near(longer, down, 1e-9)
	end)

	t.test("the body squashes at the hit and wobbles back to 1", function()
		local c0 = PracticeController.squashAt(0)
		expect.truthy(c0 < 0.75)
		local before = PracticeController.squashAt(-1)
		expect.equal(before, 1)
		local c, done = PracticeController.squashAt(5)
		expect.equal(c, 1)
		expect.truthy(done)
		for i = 0, 40 do
			local value = PracticeController.squashAt(i / 50)
			expect.truthy(value > 0.5 and value < 1.5)
		end
	end)

	t.test("accuracy is whole percent of hits over throws", function()
		expect.equal(PracticeController.accuracyPercent(0, 0), 0)
		expect.equal(PracticeController.accuracyPercent(1, 3), 33)
		expect.equal(PracticeController.accuracyPercent(2, 3), 67)
		expect.equal(PracticeController.accuracyPercent(4, 4), 100)
		expect.equal(PracticeController.accuracyPercent(5, 4), 100) -- never above 100
	end)

	t.test("the target pivot slides along Z and tips back away from the thrower", function()
		-- Targets face the thrower (+X): the builder's pivot looks along +X.
		local base = CFrame.lookAt(Vector3.new(-44, 0.06, -37), Vector3.new(-43, 0.06, -37))
		local slid = PracticeController.pivotAt(base, 2.5, 0)
		expect.near((slid.Position - base.Position).Z, 2.5, 1e-5)
		expect.near((slid.Position - base.Position).X, 0, 1e-5)
		local tipped = PracticeController.pivotAt(base, 0, 70)
		local top = tipped:PointToWorldSpace(Vector3.new(0, 5, 0))
		expect.truthy(top.X < base.Position.X - 3) -- the top went back toward -X
		expect.near(top.Z, base.Position.Z, 1e-4) -- not sideways
	end)

	t.test("an impact without targetId finds the nearest target where it was at that server time", function()
		-- Diego's targets stand still (owner 2026-10-23); a rail target from attributes still slides.
		local defs = table.clone(PracticeTargets.list())
		expect.truthy(#defs > 0)
		local moving = PracticeTargets.fromAttributes(
			{ TargetId = "target_rail", Distance = 20, Moving = true, RailLength = 12, Period = 9.42 },
			Vector3.new(45, 0.9, 30)
		)
		expect.truthy(moving ~= nil)
		table.insert(defs, moving)
		local serverTime = 1.8e9 + moving.period / 4 -- a quarter period: near the end of its rail
		local at = PracticeTargets.positionAt(moving, serverTime)
		local found = PracticeController.nearestTarget(defs, at + Vector3.new(0.3, 2, 0.2), serverTime)
		expect.equal(found and found.id, moving.id)
		-- Far from every target: nothing.
		expect.equal(PracticeController.nearestTarget(defs, Vector3.new(0, 0, 0), serverTime), nil)
		-- maxStuds bounds the match.
		local static = defs[1]
		local near = static.position + Vector3.new(4, 0, 0)
		expect.equal(PracticeController.nearestTarget({ static }, near, 0, 3), nil)
		expect.equal(PracticeController.nearestTarget({ static }, near, 0, 5), static)
	end)

	-- Reticle -----------------------------------------------------------------------------------------------------------

	local function aim(state: string, reason: string?, readyAt: number?, progress: number?): any
		return {
			state = state,
			reason = reason,
			screenPosition = Vector2.new(400, 300),
			centered = false,
			aimPoint = nil,
			readyAt = readyAt or 0,
			nextThrowAt = 0,
			progress = progress or 1,
			kind = "practice",
		}
	end

	t.test("the practice reticle is hidden outside the Practice context", function()
		expect.falsy(PracticeController.reticleView(aim("ready"), false, 0).visible)
		expect.falsy(PracticeController.reticleView(aim("hidden"), true, 0).visible)
		expect.truthy(PracticeController.reticleView(aim("ready"), true, 0).visible)
	end)

	t.test("the reticle state is an icon plus text, never colour alone", function()
		local ready = PracticeController.reticleView(aim("ready"), true, 0)
		expect.equal(ready.icon, "dot")
		expect.equal(ready.textKey, "duel.reticle.ready")
		local cooling = PracticeController.reticleView(aim("cooling", nil, 10.4, 0.25), true, 10)
		expect.equal(cooling.icon, "fill")
		expect.equal(cooling.textKey, "common.secondsShort")
		expect.near(cooling.seconds, 0.4, 1e-9)
		expect.near(cooling.fill, 0.25, 1e-9)
		local rooted = PracticeController.reticleView(aim("blocked", "throw.rooted"), true, 0)
		expect.equal(rooted.icon, "cross")
		expect.equal(rooted.textKey, "duel.reticle.rooted")
		local zone = PracticeController.reticleView(aim("blocked", "throw.context"), true, 0)
		expect.equal(zone.icon, "cross")
		expect.equal(zone.textKey, "duel.reticle.wrongZone")
		local direction = PracticeController.reticleView(aim("blocked", "throw.direction"), true, 0)
		expect.equal(direction.icon, "cross")
		expect.equal(direction.reasonCode, "throw.direction")
		-- Every text it can show exists.
		local Strings = t.requireShared("Strings")
		for _, key in { "duel.reticle.ready", "duel.reticle.rooted", "duel.reticle.wrongZone", "common.secondsShort" } do
			expect.truthy(Strings.resolve(key) ~= nil)
		end
		expect.truthy(Strings.reasonText("throw.direction") ~= "")
	end)

	t.test("the hit marker pops 1.3 -> 1 over 250 ms, and not at all under ReducedMotion", function()
		local hit = Config.Vfx.Hit
		local duration = hit.hitMarkerMs / 1000
		expect.near(PracticeController.hitMarkerScale(0, false), hit.hitMarkerScaleFrom, 1e-9)
		expect.near(PracticeController.hitMarkerScale(duration / 2, false), (hit.hitMarkerScaleFrom + 1) / 2, 1e-9)
		expect.equal(PracticeController.hitMarkerScale(duration, false), 1)
		expect.equal(PracticeController.hitMarkerScale(0, true), 1)
		expect.equal(PracticeController.hitMarkerScale(-math.huge, false), 1)
		expect.equal(PracticeController.hitMarkerScale(math.huge, false), 1)
	end)

	t.test("Hit! pops 1.3 -> 1 in 200 ms and tilts ±6° -> 0, and not at all under ReducedMotion", function()
		local hit = Config.Vfx.Hit
		expect.equal(hit.hitTextPopFrom, 1.3)
		expect.equal(hit.hitTextPopMs, 200)
		expect.equal(hit.hitTextTiltDeg, 6)
		local scale, rotation = PracticeController.hitTextPop(0, 1, false)
		expect.near(scale, 1.3, 1e-9)
		expect.near(rotation, 6, 1e-9)
		local _, other = PracticeController.hitTextPop(0, -1, false)
		expect.near(other, -6, 1e-9)
		-- Back Out: it overshoots below 1 on the way, then rests at exactly 1 with no tilt.
		local lowest = math.huge
		for ms = 0, 200, 5 do
			local s = PracticeController.hitTextPop(ms / 1000, 1, false)
			lowest = math.min(lowest, s)
			expect.truthy(s <= 1.3 + 1e-9)
		end
		expect.truthy(lowest < 1)
		local final, finalRotation = PracticeController.hitTextPop(0.2, 1, false)
		expect.equal(final, 1)
		expect.equal(finalRotation, 0)
		local calm, calmRotation = PracticeController.hitTextPop(0, 1, true)
		expect.equal(calm, 1)
		expect.equal(calmRotation, 0)
		-- It lasts no longer than the "Hit!" text itself.
		expect.truthy(hit.hitTextPopMs <= hit.hitTextMs)
	end)

	-- Part 8: the panel's place (panelPlacement) ------------------------------------------------------------------------

	local Layout = t.requireClient("UI/Layout")
	local Controls = t.requireClient("Controllers/ControlsController")
	local UI = Config.UI
	local LARGEST = UI.PreferredTextScale.Largest
	local SCREENS = { Vector2.new(667, 375), Vector2.new(1280, 720), Vector2.new(1920, 1080) }
	local function overlaps(a: any, b: any): boolean
		return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
	end
	-- The SD_Hud around the panel on one screen (base px): the left column (Coins pill + Grip card, + the onboarding
	-- card on the larger screens), the nav row and the Studio data line at the top right, the equipped card at the
	-- bottom (centred on mouse; right of the thumbstick zone on touch or compact), on touch the thumbstick zone and the
	-- touch buttons from ControlsController.touchLayout. `pill`: the queue pill under the row (queued while practising).
	local function scene(actual: Vector2, textScale: number, touch: boolean, pill: boolean): any
		local scale = Layout.uiScale(actual.Y)
		local screen = actual / scale
		local compact = Layout.layoutClass(actual.X, actual.Y) == "compact"
		local left = { x = 12, y = 12, w = 270, h = if compact then 110 else 290 }
		local above = {
			{ x = screen.X - 12 - 500, y = 12, w = 500, h = 52 },
			{ x = screen.X - 12 - 320, y = 72, w = 320, h = 40 * textScale },
		}
		if pill then
			table.insert(above, { x = screen.X - 12 - 460, y = 120, w = 460, h = 170 * textScale })
		end
		local avoid = {}
		local cardHeight = 96 * textScale
		if touch then
			local zoneHeight = screen.Y * UI.Touch.thumbstickZoneHeight
			table.insert(
				avoid,
				{ x = 0, y = screen.Y - zoneHeight, w = screen.X * UI.Touch.thumbstickZoneWidth, h = zoneHeight }
			)
			local buttons = Controls.touchLayout(actual, scale, nil)
			for _, rect in { buttons.throw, buttons.ultimate } do
				table.insert(avoid, { x = rect.x / scale, y = rect.y / scale, w = rect.w / scale, h = rect.h / scale })
			end
		end
		if touch or compact then
			-- HudController's narrow card: right of the thumbstick zone, as wide as the room before the touch buttons.
			local cardLeft = screen.X * UI.Touch.thumbstickZoneWidth + UI.Touch.gap
			table.insert(avoid, { x = cardLeft, y = screen.Y - 16 - cardHeight, w = 180, h = cardHeight })
		else
			table.insert(avoid, { x = screen.X / 2 - 220, y = screen.Y - 12 - cardHeight, w = 440, h = cardHeight })
		end
		-- The panel: 190 wide; the title (foam fix 2: on every layout) and three rows of 1.25 lines of text each, the
		-- accuracy row wrapping to two lines at the larger text sizes; 4 px between rows, 12 px padding.
		local line = 1.25 * textScale
		local rows = 3 * line * UI.TextSize.Body + (if textScale >= 1.3 then line * UI.TextSize.Body else 0)
		local title = line * UI.TextSize.H2 + 4
		return {
			screen = screen,
			size = Vector2.new(190, title + rows + 2 * 4 + 2 * 12),
			left = left,
			above = above,
			avoid = avoid,
		}
	end
	local function clear(input: any, place: any)
		local rect = { x = place.x, y = place.y, w = input.size.X, h = input.size.Y }
		expect.truthy(rect.x >= 16 - 1e-6 and rect.y >= 16 - 1e-6)
		expect.truthy(rect.x + rect.w <= input.screen.X - 16 + 1e-6)
		expect.truthy(rect.y + rect.h <= input.screen.Y - 16 + 1e-6)
		expect.falsy(overlaps(rect, input.left))
		for _, list in { input.above, input.avoid } do
			for _, other in list do
				expect.falsy(overlaps(rect, other))
			end
		end
	end

	t.test("practice panel (Part 8): a free spot at every size and the largest text, mouse and touch", function()
		for _, actual in SCREENS do
			for _, textScale in { 1, LARGEST } do
				for _, touch in { false, true } do
					local input = scene(actual, textScale, touch, false)
					local place = PracticeController.panelPlacement(input)
					if actual == SCREENS[1] and textScale == LARGEST and touch then
						-- Foam fix 2: with its title back, a 667×375 phone on touch at the largest text has no free
						-- spot (Part 8 fitted it there only without the title); it stays on screen (below).
						expect.equal(place.fits, false)
						continue
					end
					expect.equal(place.fits, true)
					clear(input, place)
				end
				-- Queued while practising on a mouse: still free (under the left column).
				local queued = scene(actual, textScale, false, true)
				local queuedPlace = PracticeController.panelPlacement(queued)
				expect.equal(queuedPlace.fits, true)
				clear(queued, queuedPlace)
			end
		end
		-- 1920×1080 on a mouse: right under the left column (before: 42% down, overlapping the column's lower cards).
		local big = scene(SCREENS[3], 1, false, false)
		local place = PracticeController.panelPlacement(big)
		expect.equal(place.slot, "left")
		expect.equal(place.x, 16)
		expect.near(place.y, big.left.y + big.left.h + 8, 1e-6)
		-- 667×375 on touch: at Medium text the titled panel (foam fix 2) reaches the thumbstick zone under the left
		-- column, so it goes to the right under the row.
		local phone = PracticeController.panelPlacement(scene(SCREENS[1], 1, true, false))
		expect.equal(phone.slot, "right")
	end)

	t.test("practice panel (Part 8): with no free spot it stays on screen at the left, fits = false", function()
		-- A phone on touch, queued (the pill under the row) at the largest text: neither spot is free.
		local crowded = scene(SCREENS[1], LARGEST, true, true)
		local place = PracticeController.panelPlacement(crowded)
		expect.equal(place.fits, false)
		expect.equal(place.slot, "left")
		expect.truthy(place.y >= 16 and place.y + crowded.size.Y <= crowded.screen.Y - 16 + 1e-6)
		-- No HUD around it (hidden): the top-left corner.
		local bare = PracticeController.panelPlacement({
			screen = Vector2.new(800, 450),
			size = Vector2.new(190, 130),
			left = nil,
			above = {},
			avoid = {},
		})
		expect.equal(bare.x, 16)
		expect.equal(bare.y, 16)
		expect.equal(bare.fits, true)
	end)

	-- Integration (foam HUD, 2026-10-09): the left side is Hud_Left plus the tiles under it; the Duel CTA is avoided.

	t.test("unionRect: the box around the usable rects, nil without any", function()
		local union = PracticeController.unionRect({
			{ x = 12, y = 12, w = 270, h = 110 },
			{ x = 12, y = 128, w = 555, h = 64 },
		})
		expect.deepEqual(union, { x = 12, y = 12, w = 555, h = 180 })
		expect.equal(PracticeController.unionRect({}), nil)
		-- A rect without a size or with bad numbers is left out.
		local one = PracticeController.unionRect({
			{ x = 12, y = 12, w = 270, h = 110 },
			{ x = 400, y = 0, w = 0, h = 50 },
			{ x = 0 / 0, y = 0, w = 10, h = 10 },
		})
		expect.deepEqual(one, { x = 12, y = 12, w = 270, h = 110 })
	end)

	t.test("practice panel (integration): clear of the foam HUD's tiles and the top-middle Duel CTA", function()
		local HudFormat = t.requireClient("UI/HudFormat")
		local COLUMN = HudFormat.COLUMN
		for _, actual in SCREENS do
			for _, touch in { false, true } do
				local scale = Layout.uiScale(actual.Y)
				local screen = actual / scale
				local compact = Layout.layoutClass(actual.X, actual.Y) == "compact"
				local narrow = compact or touch
				-- The left side from the HUD's own plan: the coin capsule and the Grip card, then the tiles.
				local plan =
					HudFormat.leftColumnPlan(actual, if compact then "compact" else "regular", 1, { touch = touch })
				local leftColumn = { x = 12, y = 12, w = plan.width, h = plan.leftBottom - 12 }
				local tiles = { x = 12, y = plan.tilesTop, w = plan.tilesWidth, h = plan.tilesHeight }
				-- Top right: the Settings tile, and the quest tracker except on the compact layout.
				local rightWidth = if compact then COLUMN.settingsSize else COLUMN.trackerWidth
				local right = {
					x = screen.X - 12 - rightWidth,
					y = 12,
					w = rightWidth,
					h = if compact then COLUMN.settingsSize else COLUMN.settingsSize + 8 + 100,
				}
				-- The touch buttons and the Duel CTA at the top middle (lobby HUD, spec 2026-10-11: one of the frames
				-- above the panel, as layoutPanel reads Hud_DuelButton).
				local buttons = Controls.touchLayout(actual, scale, nil)
				local reserved = {}
				for _, rect in { buttons.throw, buttons.ultimate } do
					table.insert(
						reserved,
						{ x = rect.x / scale, y = rect.y / scale, w = rect.w / scale, h = rect.h / scale }
					)
				end
				local ctaSize = Vector2.new(
					HudFormat.ctaWidth(compact, 1),
					if compact then COLUMN.ctaCompactHeight else COLUMN.ctaHeight
				)
				local ctaPlace = HudFormat.ctaPlacement({
					canvas = screen,
					size = ctaSize,
					blockers = { leftColumn, tiles, right },
				})
				local cta = { x = ctaPlace.x, y = ctaPlace.y, w = ctaSize.X, h = ctaSize.Y }
				local avoid = {}
				if narrow then
					-- Foam fix 2: on every narrow layout (compact or touch), as layoutPanel.
					local zoneHeight = screen.Y * UI.Touch.thumbstickZoneHeight
					table.insert(avoid, {
						x = 0,
						y = screen.Y - zoneHeight,
						w = screen.X * UI.Touch.thumbstickZoneWidth,
						h = zoneHeight,
					})
					for _, rect in reserved do
						table.insert(avoid, rect)
					end
				end
				-- The panel at Medium text: the title (foam fix 2: on every layout) and three rows (see `scene`).
				local line = 1.25
				local rows = 3 * line * UI.TextSize.Body
				local title = line * UI.TextSize.H2 + 4
				local input = {
					screen = screen,
					size = Vector2.new(190, title + rows + 2 * 4 + 2 * 12),
					left = PracticeController.unionRect({ leftColumn, tiles }),
					above = { tiles, right, cta },
					avoid = avoid,
				}
				local place = PracticeController.panelPlacement(input)
				expect.equal(place.fits, true)
				clear(input, place)
				-- The left spot sits under the tiles, never between the column and them.
				if place.slot == "left" then
					expect.truthy(place.y >= tiles.y + tiles.h + 8 - 1e-6)
				end
			end
		end
	end)

	-- Foam fix 2 (2026-10-09): the title chip on every layout, the whole-screen thumbstick zone, the top spot.

	t.test("practice panel (foam fix 2): the top spot, left of the top-right row, when the others are taken", function()
		local input = {
			screen = Vector2.new(993, 390),
			size = Vector2.new(190, 120),
			left = { x = 12, y = 12, w = 440, h = 115 }, -- the coin capsule, the Grip card and the tiles under them
			above = {
				{ x = 12, y = 70, w = 440, h = 57 }, -- the tiles
				{ x = 910, y = 12, w = 71, h = 64 }, -- the Settings tile
			},
			avoid = {
				{ x = 0, y = 390 - 200, w = 397, h = 200 }, -- the thumbstick zone
				{ x = 840, y = 166, w = 138, h = 64 }, -- the Duel CTA
			},
		}
		local place = PracticeController.panelPlacement(input)
		expect.equal(place.slot, "top")
		expect.equal(place.fits, true)
		expect.near(place.x, 910 - 8 - 190, 1e-6)
		expect.near(place.y, 16, 1e-6)
		clear(input, place)
		-- The left spot still wins when it is free (a PC).
		local pc = table.clone(input)
		pc.screen = Vector2.new(1536, 864)
		pc.avoid = {}
		expect.equal(PracticeController.panelPlacement(pc).slot, "left")
	end)

	t.test(
		"practice panel (foam fix 2): on phones, with its title, clear of the whole-screen thumbstick zone",
		function()
			local HudFormat = t.requireClient("UI/HudFormat")
			local COLUMN = HudFormat.COLUMN
			local INSET = 58 -- Roblox's top bar, which SD_Hud (CoreUISafeInsets) leaves out
			-- The phone lobby HUD around the panel at Medium text (HudController's own plan), as layoutPanel reads it.
			local function phone(actual: Vector2): any
				local hudPx = Vector2.new(actual.X, actual.Y - INSET)
				local scale = Layout.uiScale(hudPx.Y)
				local screen = hudPx / scale
				local plan = HudFormat.leftColumnPlan(hudPx, "compact", 1, { touch = true, screenHeight = actual.Y })
				local leftColumn = { x = 12, y = 12, w = plan.width, h = plan.leftBottom - 12 }
				local tiles = { x = 12, y = plan.tilesTop, w = plan.tilesWidth, h = plan.tilesHeight }
				local right = {
					x = screen.X - 12 - COLUMN.settingsSize,
					y = 12,
					w = COLUMN.settingsSize,
					h = COLUMN.settingsSize,
				}
				local buttons = Controls.touchLayout(hudPx, scale, nil)
				local reserved = {}
				for _, rect in { buttons.throw, buttons.ultimate, buttons.jump } do
					table.insert(
						reserved,
						{ x = rect.x / scale, y = rect.y / scale, w = rect.w / scale, h = rect.h / scale }
					)
				end
				-- The Duel CTA at the top middle (lobby HUD, spec 2026-10-11), at its widest (queued).
				local ctaSize = Vector2.new(HudFormat.ctaWidth(true, 1), COLUMN.ctaCompactHeight)
				local ctaPlace = HudFormat.ctaPlacement({
					canvas = screen,
					size = ctaSize,
					blockers = { leftColumn, tiles, right },
				})
				local cta = { x = ctaPlace.x, y = ctaPlace.y, w = ctaSize.X, h = ctaSize.Y }
				local zone = HudFormat.thumbstickZone(screen, actual.Y, scale)
				local avoid = { zone }
				for _, rect in reserved do
					table.insert(avoid, rect)
				end
				local line = 1.25
				return {
					screen = screen,
					size = Vector2.new(190, line * UI.TextSize.H2 + 4 + 3 * line * UI.TextSize.Body + 2 * 4 + 2 * 12),
					left = PracticeController.unionRect({ leftColumn, tiles }),
					above = { tiles, right, cta },
					avoid = avoid,
				}
			end
			-- Common phones: a free spot, over nothing (the zone is a share of the whole screen, the 844×390 shot's panel
			-- reached about 40 px into it).
			for _, actual in
				{
					Vector2.new(740, 360),
					Vector2.new(800, 360),
					Vector2.new(844, 390),
					Vector2.new(896, 414),
					Vector2.new(932, 430),
				}
			do
				local input = phone(actual)
				local place = PracticeController.panelPlacement(input)
				expect.equal(place.fits, true)
				clear(input, place)
			end
			-- Lobby HUD (spec 2026-10-11): with the Duel CTA at the top middle the right edge under the Settings tile is
			-- free (the two tile columns fill the left side down to the zone), on 844×390 and now on 667×375 too.
			for _, actual in { Vector2.new(844, 390), Vector2.new(667, 375) } do
				local input = phone(actual)
				local place = PracticeController.panelPlacement(input)
				expect.equal(place.slot, "right")
				expect.equal(place.fits, true)
				expect.near(place.y, 12 + COLUMN.settingsSize + 8, 1e-6)
				clear(input, place)
			end
		end
	)
end
