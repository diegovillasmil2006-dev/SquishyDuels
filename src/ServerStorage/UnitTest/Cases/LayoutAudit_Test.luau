--!strict
-- LayoutAudit_Test: StarterPlayerScripts.Client.Studio.LayoutAudit (the Studio layout audit behind SD_DebugClient
-- "layoutAudit"). Server only (ServerStorage.UnitTest), Edit mode: the rules run on plain node trees (no PlayerGui).
-- Contract (DESIGN §13.1, §11.2, §11.4; Part 8):
--   * intersection / overlapArea: touching edges do not overlap; an overlap counts only beyond 2 px on both axes;
--   * offscreen beyond 1 px of the ScreenGui's box; belowFold = not entirely inside the scroll window;
--   * tooSmall: the smaller side under the floor (52 base at scale 0.85 = 44.2 px passes, 44 base = 37.4 px fails);
--   * actualTextPx = TextSize × the UIScale product; every Config.UI.TextSize kind stays >= minTextSize at the
--     smallest UI scale;
--   * overlapRect: a button or a text object is its box; a frame with a visible text child is its box when it draws a
--     background, else the union of its text children; anything else is not compared;
--   * evaluate catches Part 6's "Not oUltimate" card tags (the "Not owned" badge and the "Ultimate" badge on a 112 px
--     card) and passes the fixed layout (InventoryFormat.cardTags' second row), without flagging the card's full-size
--     transparent Overlay against its Content; it finds offscreen, text overflow, small targets, small text, and the
--     Part 6 fold (a button under a ScrollingFrame's window: belowFold, informational); a designed cut (TextTruncate:
--     Inspect's name, the compact Grip line) is textTruncated (informational), never textOverflow; a ScrollingFrame's
--     clip hides overlaps out of view; two layer roots (stacked modals) are not compared; a list keeps maxItems items
--     and the count; hud.planFits passes HudController's column plan answer through;
--   * primaryOk and share; run() refuses bad options, lists outside the lobby and a missing PlayerGui, refuses "all"
--     and lists while a box reveal is open or waiting (without closing anything: AckReveal), skips "queue" (QueueJoin),
--     "boxReveal", non-modal screens, unknown names and an Inspect whose open is not safe without opening them, and
--     answers { ok, ran, mode = "current", views = { current } } for what shows now (Studio only: engine sizes);
--   * foam fix batch (2026-10-09; the Studio audit found 0 problems while the screenshots showed these):
--     - words / mayBreak / wordBreaks / innerWidth, and evaluate's brokenWords: the first screen's "Squishie / s" and
--       "Setting / s" (a word wider than its wrapped box; TextFits stays true) are found, the later 68 px tiles pass;
--     - pieces: a HUD group shows its buttons, texts and opaque frames, without those inside a shown ancestor's box (a
--       popup above its panel or a badge past its tile is a box of its own; a scroll window cuts them);
--     - evaluate's HUD rules on the phone shots' boxes (844×390 and 667×375, the HUD under the 58 px top bar inset):
--       hudOverlaps finds the Inspect chip over Hud_DailyButton near a mat, the three-row dock over it at 667×375 and a
--       toast over the Quests and Daily tiles (the sibling rule finds none of them), thumbZone a piece in the lower-left
--       zone on narrow layouts only (never on PC; with planFits false the left side's hits are thumbZoneExpected); the
--       fixed layouts pass; run() reports hud.narrow from the class or touch;
--     - lobby HUD (spec 2026-10-11): the dock and its dockRows rule are gone; hudOverlaps still checks the top-middle
--       stack (the Duel CTA, the coach card, the toasts);
--     - integration: the zone's height is a share of the whole screen (zoneScreenHeight, as HudFormat.thumbstickZone),
--       never less than the HUD's own share; measured so, the shot's tile row reaches into it and the "beside" row
--       does not.
-- Tables are compared by value. The dock fixtures below (Hud_EquippedCard) are the old shots' boxes: any HUD group.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local LayoutAudit = t.requireClient("Studio/LayoutAudit")
	local InventoryFormat = t.requireClient("UI/InventoryFormat")
	local Config = t.requireShared("Config")
	local UI = Config.UI
	local SCALE = UI.Scale.min -- a phone (667×375) and Studio's 893×673 window both use 0.85

	local LIMITS = {
		floorPx = UI.Touch.minTargetFloor,
		minTextPx = UI.minTextSize,
		offscreenPx = 1,
		overlapPx = 2,
		maxItems = 40,
	}
	local SCREEN = { x = 0, y = 0, w = 893, h = 673 }

	-- A plain node (see LayoutAudit.Node); `props` overrides the defaults.
	local function node(path: string, x: number, y: number, w: number, h: number, props: { [string]: any }?): any
		local n: { [string]: any } = {
			path = path,
			rect = { x = x, y = y, w = w, h = h },
			button = false,
			active = false,
			opaque = false,
			clips = false,
			children = {},
		}
		if props then
			for key, value in props do
				n[key] = value
			end
		end
		return n
	end

	local function text(path: string, x: number, y: number, w: number, h: number, value: string, props: any?): any
		local p: { [string]: any } = { text = value, textFits = true, textScaled = false, textPx = 16 * SCALE }
		for key, v in props or {} do
			p[key] = v
		end
		return node(path, x, y, w, h, p)
	end

	local function evaluate(roots: { any }, limits: any?): any
		return LayoutAudit.evaluate({ { rect = SCREEN, roots = roots } }, limits or LIMITS)
	end

	t.test("intersection and overlapArea: edges touching do not overlap; more than 2 px on both axes counts", function()
		local a = { x = 0, y = 0, w = 10, h = 10 }
		expect.deepEqual(LayoutAudit.intersection(a, { x = 5, y = 5, w = 10, h = 10 }), { x = 5, y = 5, w = 5, h = 5 })
		expect.equal(LayoutAudit.intersection(a, { x = 10, y = 0, w = 5, h = 5 }), nil)
		expect.equal(LayoutAudit.intersection(a, { x = 0, y = 20, w = 5, h = 5 }), nil)
		expect.equal(LayoutAudit.overlapArea(a, { x = 8, y = 0, w = 10, h = 10 }, 2), 0) -- 2 px wide: not more than 2
		expect.equal(LayoutAudit.overlapArea(a, { x = 7, y = 0, w = 10, h = 10 }, 2), 30)
		expect.equal(LayoutAudit.overlapArea(a, { x = 0, y = 8, w = 10, h = 10 }, 2), 0)
		expect.deepEqual(
			LayoutAudit.union({ { x = 0, y = 0, w = 5, h = 5 }, { x = 10, y = 2, w = 5, h = 10 } }),
			{ x = 0, y = 0, w = 15, h = 12 }
		)
		expect.equal(LayoutAudit.union({}), nil)
	end)

	t.test("offscreen, belowFold, tooSmall and actualTextPx", function()
		expect.falsy(LayoutAudit.offscreen({ x = 0, y = 0, w = 893, h = 673 }, SCREEN, 1))
		expect.falsy(LayoutAudit.offscreen({ x = -1, y = 0, w = 10, h = 10 }, SCREEN, 1))
		expect.truthy(LayoutAudit.offscreen({ x = -2, y = 0, w = 10, h = 10 }, SCREEN, 1))
		expect.truthy(LayoutAudit.offscreen({ x = 880, y = 600, w = 20, h = 10 }, SCREEN, 1))
		expect.truthy(LayoutAudit.offscreen({ x = 10, y = 670, w = 20, h = 10 }, SCREEN, 1))
		-- The Part 6 fold: buttons at y 637-685 under a window that ends at y 568.
		local window = { x = 600, y = 200, w = 250, h = 368 }
		expect.truthy(LayoutAudit.belowFold({ x = 610, y = 637, w = 100, h = 48 }, window))
		expect.truthy(LayoutAudit.belowFold({ x = 610, y = 540, w = 100, h = 48 }, window)) -- cut by the edge
		expect.falsy(LayoutAudit.belowFold({ x = 610, y = 500, w = 100, h = 48 }, window))
		-- Touch: 52 base at 0.85 passes the 44 px floor, the old 44 base chips (37.4 px) do not.
		expect.falsy(LayoutAudit.tooSmall(200, UI.Touch.minTarget * SCALE, UI.Touch.minTargetFloor))
		expect.truthy(LayoutAudit.tooSmall(200, 44 * SCALE, UI.Touch.minTargetFloor))
		expect.truthy(LayoutAudit.tooSmall(30, 200, UI.Touch.minTargetFloor))
		-- textFits: the engine's TextFits, or the text within 2 px of its box (the phone run's one-line "Cancel": text
		-- 47 px wide in a box a pixel short); a real overflow still fails.
		expect.truthy(LayoutAudit.textFits(true, 500, 500, 10, 10))
		expect.truthy(LayoutAudit.textFits(false, 47, 17, 46, 17))
		expect.truthy(LayoutAudit.textFits(false, 47, 17, 45, 15))
		expect.falsy(LayoutAudit.textFits(false, 47, 17, 44, 17))
		expect.falsy(LayoutAudit.textFits(false, 47, 34, 47, 17))
		expect.near(LayoutAudit.actualTextPx(16, 0.85), 13.6)
		expect.near(LayoutAudit.actualTextPx(16, 0.85 * 0.88), 11.968)
		-- Every text kind stays readable at the smallest UI scale (§11.2).
		for kind, size in UI.TextSize do
			expect.truthy(LayoutAudit.actualTextPx(size, UI.Scale.min) >= UI.minTextSize)
			expect.truthy(type(kind) == "string")
		end
	end)

	t.test("overlapRect: what a node shows for the overlap rule", function()
		local button = node("B", 0, 0, 100, 50, { button = true })
		expect.deepEqual(LayoutAudit.overlapRect(button), button.rect)
		local label = text("L", 5, 5, 60, 20, "Hello")
		expect.deepEqual(LayoutAudit.overlapRect(label), label.rect)
		expect.equal(LayoutAudit.overlapRect(text("E", 5, 5, 60, 20, "")), nil) -- an empty label shows nothing
		local a = text("H/A", 10, 10, 30, 10, "a")
		local b = text("H/B", 50, 40, 20, 10, "b")
		local holder = node("H", 0, 0, 200, 200, { children = { a, b, node("H/Icon", 0, 0, 200, 200) } })
		expect.deepEqual(LayoutAudit.overlapRect(holder), { x = 10, y = 10, w = 60, h = 40 })
		-- A scrolling holder shows its text only inside its window.
		local scrolling = node("S", 0, 0, 200, 25, {
			clips = true,
			scroll = { x = 0, y = 0, w = 194, h = 25 },
			children = { text("S/A", 10, 10, 30, 10, "a"), text("S/B", 50, 40, 20, 10, "b") },
		})
		expect.deepEqual(LayoutAudit.overlapRect(scrolling), { x = 10, y = 10, w = 60, h = 15 })
		holder.opaque = true
		expect.deepEqual(LayoutAudit.overlapRect(holder), holder.rect)
		expect.equal(LayoutAudit.overlapRect(node("F", 0, 0, 10, 10, { opaque = true })), nil)
	end)

	-- A Squishies card at scale 0.85 with its corner badges ("Not owned" with the lock, "Ultimate"), base px measured
	-- like Part 6's Studio run (79 and 58 wide, 14 tall); `ultimateY` is the rarity badge's top in base px.
	local function card(ultimateY: number): any
		local s = SCALE
		local x0, y0 = 100, 200
		local cardW, cardH = Config.UI.Inventory.cardWidth, 168
		local inset = 4
		local left = { w = 79, h = 14 }
		local right = { w = 58, h = 14 }
		local badgeText =
			text("Card/Overlay/Badge/Text", x0 + (inset + 5 + 12 + 3) * s, y0 + inset * s, 55 * s, 14 * s, "Not owned")
		local badge = node("Card/Overlay/Badge", x0 + inset * s, y0 + inset * s, left.w * s, left.h * s, {
			opaque = true,
			children = { node("Card/Overlay/Badge/Lock", x0 + 9 * s, y0 + 5 * s, 12 * s, 12 * s), badgeText },
		})
		local ultimate = text(
			"Card/Overlay/UltimateBadge",
			x0 + (cardW - inset - right.w) * s,
			y0 + ultimateY * s,
			right.w * s,
			right.h * s,
			"Ultimate",
			{ opaque = true }
		)
		local overlay = node("Card/Overlay", x0, y0, cardW * s, cardH * s, { children = { badge, ultimate } })
		local name = text("Card/Content/Name", x0 + 4 * s, y0 + 98 * s, (cardW - 8) * s, 20 * s, "Dragon")
		local content = node("Card/Content", x0, y0, cardW * s, cardH * s, {
			children = { node("Card/Content/Preview", x0 + 14 * s, y0 + 6 * s, 84 * s, 84 * s), name },
		})
		return node("Card", x0, y0, cardW * s, cardH * s, {
			button = true,
			active = true,
			opaque = true,
			children = { content, overlay },
		})
	end

	t.test("evaluate: Part 6's 'Not oUltimate' tags are an overlap; the second row (cardTags) is not", function()
		local broken = evaluate({ card(4) })
		expect.equal(broken.counts.overlaps, 1)
		expect.deepEqual(
			{ broken.overlaps[1].a, broken.overlaps[1].b },
			{ "Card/Overlay/Badge", "Card/Overlay/UltimateBadge" }
		)
		expect.truthy(broken.overlaps[1].area > 0)
		local tags = InventoryFormat.cardTags(
			Config.UI.Inventory.cardWidth,
			4,
			2,
			{ w = 79, h = 14 },
			{ w = 58, h = 14 }
		)
		expect.equal(tags.twoRows, true)
		local fixed = evaluate({ card(tags.rightY) })
		expect.equal(fixed.counts.overlaps, 0) -- and the transparent Overlay is never compared with the Content
		expect.equal(fixed.counts.checked, 9) -- Card, Content, Preview, Name, Overlay, Badge, Lock, Text, UltimateBadge
		expect.equal(fixed.counts.offscreen + fixed.counts.smallTargets + fixed.counts.textOverflow, 0)
	end)

	t.test("evaluate: offscreen, text overflow, small targets, small text and the fold", function()
		local scroll = node("Panel/Detail", 600, 200, 250, 368, {
			clips = true,
			scroll = { x = 600, y = 200, w = 244, h = 368 },
			children = {
				text("Panel/Detail/Name", 600, 210, 200, 30, "Dragon"),
				node("Panel/Detail/Equip", 610, 637, 100, 48, { button = true, active = true }),
				-- Out of view, overlapping each other: clipped away, not an overlap.
				text("Panel/Detail/A", 600, 800, 100, 30, "a"),
				text("Panel/Detail/B", 650, 800, 100, 30, "b"),
				-- Inside a ScrollingFrame nothing is offscreen.
				text("Panel/Detail/Far", 600, 2000, 100, 30, "far"),
			},
		})
		local panel = node("Panel", 20, 20, 853, 633, {
			opaque = true,
			children = {
				scroll,
				node("Panel/Chip", 30, 30, 120, 44 * SCALE, { button = true, active = true }),
				node("Panel/Decor", 30, 100, 20, 20, { button = true, active = false }), -- not a target
				text("Panel/Long", 30, 150, 100, 20, "Way too long a text", { textFits = false }),
				text("Panel/Scaled", 30, 180, 100, 20, "Scaled", { textFits = false, textScaled = true }),
				text("Panel/Tiny", 30, 210, 100, 20, "Tiny", { textPx = 14 * SCALE }),
				node("Panel/Empty", 5000, 5000, 0, 0),
			},
		})
		local wide = node("Wide", 800, 600, 200, 100, { opaque = true })
		local f = evaluate({ panel, wide })
		expect.equal(f.counts.checked, 1 + 7 + 5 + 1) -- Panel, its 7 children, the scroll's 5, Wide
		expect.deepEqual(f.offscreen, { { path = "Wide", x = 800, y = 600, w = 200, h = 100 } })
		expect.equal(#f.belowFold, 1)
		expect.equal(f.belowFold[1].path, "Panel/Detail/Equip")
		expect.equal(#f.smallTargets, 1)
		expect.equal(f.smallTargets[1].path, "Panel/Chip")
		expect.near(f.smallTargets[1].px, 37.4)
		expect.equal(f.textOverflow[1].path, "Panel/Long")
		expect.equal(f.counts.textOverflow, 1)
		expect.equal(f.counts.smallText, 1)
		expect.equal(f.smallText[1].path, "Panel/Tiny")
		expect.near(f.smallText[1].px, 11.9)
		expect.equal(f.counts.overlaps, 0)
		expect.equal(f.counts.textTruncated, 0)
		expect.deepEqual(f.textTruncated, {})
		expect.falsy(f.truncated)
	end)

	t.test("evaluate: a designed cut (TextTruncate) is textTruncated, informational, not textOverflow", function()
		-- Inspect's name in the header (TextTruncate AtEnd, fixed width) and the compact Grip card's level line cut a
		-- long text on purpose: TextFits is false there, which is not an overflow (Part 8 review).
		local header = node("SD_Modal/Inspect/Header", 20, 20, 400, 60, {
			opaque = true,
			children = {
				text(
					"SD_Modal/Inspect/Header/Name",
					30,
					30,
					200,
					40,
					"Kitty Bread",
					{ textFits = false, truncates = true }
				),
			},
		})
		local grip = text("SD_Hud/Hud_Left/Hud_GripButton/Compact/Level", 20, 200, 250, 20, "Lv 99 · Squish Master", {
			textFits = false,
			truncates = true,
		})
		local cut =
			text("SD_Hud/Plain", 20, 300, 100, 20, "Way too long a text", { textFits = false, truncates = false })
		local f = evaluate({ header, grip, cut })
		expect.equal(f.counts.textTruncated, 2)
		expect.deepEqual(
			{ f.textTruncated[1].path, f.textTruncated[2].path },
			{ "SD_Modal/Inspect/Header/Name", "SD_Hud/Hud_Left/Hud_GripButton/Compact/Level" }
		)
		-- A label without a TextTruncate that does not fit is still an overflow.
		expect.equal(f.counts.textOverflow, 1)
		expect.equal(f.textOverflow[1].path, "SD_Hud/Plain")
		-- A cut text that fits is neither.
		local fits = evaluate({ text("SD_Hud/Fits", 0, 0, 200, 20, "Toast", { truncates = true }) })
		expect.equal(fits.counts.textTruncated + fits.counts.textOverflow, 0)
	end)

	t.test("evaluate: stacked layer roots are not compared; lists keep maxItems and the count", function()
		local a = node("SD_Modal/Squishies", 50, 50, 600, 500, {
			opaque = true,
			layer = true,
			children = { text("SD_Modal/Squishies/T", 60, 60, 100, 20, "Squishies") },
		})
		local b = node("SD_Modal/Inspect", 60, 60, 600, 500, {
			opaque = true,
			layer = true,
			children = { text("SD_Modal/Inspect/T", 70, 70, 100, 20, "Inspect") },
		})
		local c = text("SD_Modal/Note", 100, 100, 100, 20, "Note")
		local f = evaluate({ a, b, c })
		-- a / b are layers (not compared); the note overlaps each of them.
		expect.equal(f.counts.overlaps, 2)
		local many = {}
		for i = 1, 5 do
			table.insert(many, node(`Off{i}`, -100, 10 * i, 50, 5))
		end
		local limited = table.clone(LIMITS)
		limited.maxItems = 2
		local g = evaluate(many, limited)
		expect.equal(#g.offscreen, 2)
		expect.equal(g.counts.offscreen, 5)
		expect.truthy(g.truncated)
	end)

	-- Foam fix batch -------------------------------------------------------------------------------------------------

	t.test("words, mayBreak, wordBreaks and innerWidth", function()
		expect.deepEqual(LayoutAudit.words("Squishies"), { "Squishies" })
		expect.deepEqual(LayoutAudit.words("  Welcome to\nSquishy Duels! "), { "Welcome", "to", "Squishy", "Duels!" })
		expect.deepEqual(LayoutAudit.words(""), {})
		-- Rich text: tags dropped (a <br /> is a space), escapes undone; plain text keeps them as written.
		expect.deepEqual(
			LayoutAudit.words("<b>Upgrade</b> ready:<br/>Sponge &amp; Ball", true),
			{ "Upgrade", "ready:", "Sponge", "&", "Ball" }
		)
		expect.deepEqual(LayoutAudit.words("a<b>c</b>"), { "a<b>c</b>" })
		-- Only a word that could be wider than its box is measured (no glyph is wider than 1.2 em).
		expect.truthy(LayoutAudit.mayBreak(9, 16 * SCALE, 48.8)) -- "Squishies" in a first-screen tile
		expect.falsy(LayoutAudit.mayBreak(3, 16 * SCALE, 48.8))
		expect.falsy(LayoutAudit.mayBreak(9, 16 * SCALE, 300))
		-- A word breaks when it is wider than its box by more than the 2 px slack; a box not laid out breaks nothing.
		expect.truthy(LayoutAudit.wordBreaks(56.1, 48.8))
		expect.falsy(LayoutAudit.wordBreaks(50.5, 48.8))
		expect.falsy(LayoutAudit.wordBreaks(56.1, 57.8))
		expect.falsy(LayoutAudit.wordBreaks(56.1, 0))
		-- The box less its UIPadding: the scale part of the box, the offset part under the UIScale.
		expect.near(LayoutAudit.innerWidth(59, 0, 12, SCALE), 48.8)
		expect.near(LayoutAudit.innerWidth(100, 0.1, 0, 1), 90)
		expect.near(LayoutAudit.innerWidth(200, 0, 0, SCALE), 200)
	end)

	-- A HUD tile at 0.85 (a button with its label in Content): `width` actual px; its label is wrapped with the 6 base px
	-- tile padding on each side; `wordPx` is the measured width of its word (nil: none may break).
	local function tile(path: string, x: number, y: number, width: number, word: string, wordPx: number?): any
		local boxPx = LayoutAudit.innerWidth(width, 0, 12, SCALE)
		local label = text(`{path}/Content/Label`, x, y + 30, width, 20, word, {
			wideWord = if wordPx then word else nil,
			wideWordPx = wordPx,
			textBoxPx = boxPx,
		})
		local content = node(`{path}/Content`, x, y, width, 54, { children = { label } })
		return node(path, x, y, width, 54, { button = true, active = true, opaque = true, children = { content } })
	end

	t.test(
		"evaluate: a word wider than its wrapped box is a broken word ('Squishie / s'), not a text overflow",
		function()
			-- The first screen at 844×390: tiles 59 px and Settings 54 px wide; "Squishies" and "Settings" are wider than
			-- their boxes (48.8 and 43.8 px), so the engine breaks them. Later shots: 68 and 60 px, the words fit.
			local first = evaluate({
				tile("SD_Hud/Hud_Nav/Hud_SquishiesButton", 10, 165, 59, "Squishies", 56.1),
				tile("SD_Hud/Hud_Right/Hud_SettingsButton", 779, 68, 54, "Settings", 50.3),
				tile("SD_Hud/Hud_Nav/Hud_BoxesButton", 78, 165, 59, "Boxes", nil), -- too short to break: not measured
			})
			expect.equal(first.counts.brokenWords, 2)
			expect.equal(first.brokenWords[1].path, "SD_Hud/Hud_Nav/Hud_SquishiesButton/Content/Label")
			expect.equal(first.brokenWords[1].word, "Squishies")
			expect.near(first.brokenWords[1].px, 56.1)
			expect.equal(first.brokenWords[2].word, "Settings")
			expect.equal(first.counts.textOverflow, 0) -- the two wrapped lines fit their box: TextFits stays true
			local later = evaluate({
				tile("SD_Hud/Hud_Nav/Hud_SquishiesButton", 10, 165, 68, "Squishies", 56.1),
				tile("SD_Hud/Hud_Right/Hud_SettingsButton", 773, 68, 60, "Settings", 50.3),
			})
			expect.equal(later.counts.brokenWords, 0)
			expect.deepEqual(later.brokenWords, {})
			-- TextScaled text shrinks to fit: not checked.
			local scaled = evaluate({
				text("SD_DuelHud/Countdown", 0, 0, 40, 40, "Throw!", {
					textScaled = true,
					wideWord = "Throw!",
					wideWordPx = 80,
					textBoxPx = 40,
				}),
			})
			expect.equal(scaled.counts.brokenWords, 0)
		end
	)

	t.test("pieces: the boxes a HUD group shows", function()
		-- A transparent row of buttons: each button (not its label, inside it).
		local row = node("SD_Hud/Hud_Nav", 10, 165, 374, 54, {
			children = {
				tile("SD_Hud/Hud_Nav/Hud_QuestsButton", 239, 165, 68, "Quests"),
				tile("SD_Hud/Hud_Nav/Hud_DailyButton", 316, 165, 68, "Daily"),
			},
		})
		local rowPieces = LayoutAudit.pieces(row)
		expect.equal(#rowPieces, 2)
		expect.equal(rowPieces[1].path, "SD_Hud/Hud_Nav/Hud_QuestsButton")
		expect.deepEqual(rowPieces[2].rect, { x = 316, y = 165, w = 68, h = 54 })
		-- An opaque panel: the panel alone (its Inspect button lies inside it).
		local chip = node("SD_Hud/Hud_EquippedCard", 351, 128, 104, 66, {
			opaque = true,
			children = { node("SD_Hud/Hud_EquippedCard/Hud_InspectButton", 361, 137, 83, 47, { button = true }) },
		})
		expect.deepEqual(LayoutAudit.pieces(chip), { { path = "SD_Hud/Hud_EquippedCard", rect = chip.rect } })
		-- A popup floating above its panel and a badge past its tile's corner are boxes of their own.
		local panel = node("SD_Hud/SqueezePanel", 478, 208, 255, 141, {
			opaque = true,
			children = {
				node("SD_Hud/SqueezePanel/Popups", 478, 208, 255, 0, {
					children = { text("SD_Hud/SqueezePanel/Popups/Popup", 640, 180, 80, 20, "+12 Grip") },
				}),
				node("SD_Hud/SqueezePanel/Hud_SqueezeButton", 478, 302, 255, 47, { button = true }),
			},
		})
		local panelPieces = LayoutAudit.pieces(panel)
		expect.equal(#panelPieces, 2)
		expect.equal(panelPieces[2].path, "SD_Hud/SqueezePanel/Popups/Popup")
		local badged = tile("SD_Hud/Hud_Nav/Hud_DailyButton", 316, 165, 68, "Daily")
		table.insert(badged.children, node("SD_Hud/Hud_Nav/Hud_DailyButton/Badge", 370, 155, 22, 22, { opaque = true }))
		expect.equal(#LayoutAudit.pieces(badged), 2)
		-- A scroll window cuts its pieces; one out of view shows nothing; empty text and bare frames show nothing.
		local list = node("SD_Hud/List", 0, 0, 200, 100, {
			clips = true,
			scroll = { x = 0, y = 0, w = 200, h = 100 },
			children = {
				node("SD_Hud/List/A", 0, 80, 200, 40, { button = true }),
				node("SD_Hud/List/B", 0, 300, 200, 40, { button = true }),
				text("SD_Hud/List/Empty", 0, 10, 200, 20, ""),
				node("SD_Hud/List/Bare", 0, 10, 200, 20),
			},
		})
		expect.deepEqual(
			LayoutAudit.pieces(list),
			{ { path = "SD_Hud/List/A", rect = { x = 0, y = 80, w = 200, h = 20 } } }
		)
	end)

	t.test("thumbZone", function()
		-- The lower-left 40% × 45% of the HUD's box (844×390: under the 58 px top bar inset).
		local zone = LayoutAudit.thumbZone({ x = 0, y = 58, w = 844, h = 312 }, 0.4, 0.45)
		expect.near(zone.x, 0)
		expect.near(zone.y, 58 + 312 * 0.55)
		expect.near(zone.w, 337.6)
		expect.near(zone.h, 140.4)
		-- Integration (foam fix batch): with the whole screen's height (844×370, Camera.ViewportSize) the zone is 45% of it,
		-- its bottom at the HUD's (HudFormat.thumbstickZone): it starts at 203.5, not 229.6.
		local whole = LayoutAudit.thumbZone({ x = 0, y = 58, w = 844, h = 312 }, 0.4, 0.45, 370)
		expect.near(whole.x, 0)
		expect.near(whole.y, 370 - 370 * 0.45)
		expect.near(whole.w, 337.6)
		expect.near(whole.h, 166.5)
		-- Never less than the HUD's own share; a bad screen height counts as the HUD's.
		expect.deepEqual(LayoutAudit.thumbZone({ x = 0, y = 58, w = 844, h = 312 }, 0.4, 0.45, 100), zone)
		expect.deepEqual(LayoutAudit.thumbZone({ x = 0, y = 58, w = 844, h = 312 }, 0.4, 0.45, 0 / 0), zone)
	end)

	-- The HUD of the 844×390 phone shots (touch, compact; actual px, SD_Hud under the 58 px top bar inset).
	local HUD_844 = { x = 0, y = 58, w = 844, h = 312 }
	local OVERLAY_844 = HUD_844
	local NARROW: any = table.clone(LIMITS)
	NARROW.narrow = true
	NARROW.zoneWidth = UI.Touch.thumbstickZoneWidth
	NARROW.zoneHeight = UI.Touch.thumbstickZoneHeight
	-- The tiles' left edges in the shots: 68 px tiles at 844×390, 60 px at 667×375.
	local TILES_844 = { 10, 86, 163, 239, 316 }
	local TILES_667 = { 10, 78, 146, 214, 282 }

	local function tileRow(xs: { number }, width: number, y: number): any
		local kids = {}
		for i, name in { "Squishies", "Boxes", "Shop", "Quests", "Daily" } do
			table.insert(kids, tile(`SD_Hud/Hud_Nav/Hud_{name}Button`, xs[i], y, width, name))
		end
		return node("SD_Hud/Hud_Nav", xs[1], y, xs[5] + width - xs[1], 54, { children = kids })
	end

	local function hudLeft(): any
		local coins = node("SD_Hud/Hud_Left/Hud_Coins", 10, 68, 124, 44, {
			children = { node("SD_Hud/Hud_Left/Hud_Coins/Hud_CoinsButton", 10, 68, 124, 44, { button = true }) },
		})
		local grip = node("SD_Hud/Hud_Left/Hud_GripButton", 10, 117, 229, 44, { button = true, opaque = true })
		return node("SD_Hud/Hud_Left", 10, 68, 229, 93, { children = { coins, grip } })
	end

	local function hudRight(): any
		return node("SD_Hud/Hud_Right", 773, 68, 60, 54, {
			children = { tile("SD_Hud/Hud_Right/Hud_SettingsButton", 773, 68, 60, "Settings") },
		})
	end

	-- The phone dock: an opaque panel with its items (`items` = { { name, x, y, w, h } }).
	local function dock(x: number, y: number, w: number, h: number, items: { { any } }): any
		local kids = {}
		for _, it in items do
			local name = it[1]
			table.insert(
				kids,
				node(`SD_Hud/Hud_EquippedCard/{name}`, it[2], it[3], it[4], it[5], { button = name ~= "Portrait" })
			)
		end
		return node("SD_Hud/Hud_EquippedCard", x, y, w, h, { opaque = true, children = kids })
	end

	local function duel(y: number): any
		return node("SD_Hud/Hud_DuelButton", 715, y, 117, 54, { button = true, active = true, opaque = true })
	end

	local function hudScreens(roots: { any }, overlayRoots: { any }?): { any }
		local screens = { { rect = HUD_844, roots = roots, name = "SD_Hud" } }
		if overlayRoots then
			table.insert(screens, { rect = OVERLAY_844, roots = overlayRoots, name = "SD_Overlay" })
		end
		return screens
	end

	t.test("evaluate HUD rules: the Inspect chip over the Daily tile near a mat (844×390, shot 05)", function()
		local chip = dock(351, 128, 104, 66, { { "Hud_InspectButton", 361, 137, 83, 47 } })
		local squeeze = node("SD_Hud/SqueezePanel", 478, 208, 255, 141, {
			opaque = true,
			children = { node("SD_Hud/SqueezePanel/Hud_SqueezeButton", 478, 302, 255, 47, { button = true }) },
		})
		local roots = { hudLeft(), tileRow(TILES_844, 68, 165), hudRight(), chip, duel(147), squeeze }
		local f = LayoutAudit.evaluate(hudScreens(roots), NARROW)
		expect.equal(f.counts.hudOverlaps, 1)
		expect.deepEqual(
			f.hudOverlaps[1],
			{ a = "SD_Hud/Hud_Nav/Hud_DailyButton", b = "SD_Hud/Hud_EquippedCard", area = 33 * 29 }
		)
		expect.equal(f.counts.overlaps, 0) -- the sibling rule never compared them (no text in the row or the chip)
		expect.equal(f.counts.thumbZone, 0) -- the tiles end at 52% of the HUD's height, the zone starts at 55%
		-- Fixed: the chip right above the panel's left edge (x 478), clear of the tiles.
		local fixed = dock(478, 128, 104, 66, { { "Hud_InspectButton", 488, 137, 83, 47 } })
		local ok = LayoutAudit.evaluate(
			hudScreens({ hudLeft(), tileRow(TILES_844, 68, 165), hudRight(), fixed, duel(147), squeeze }),
			NARROW
		)
		expect.equal(ok.counts.hudOverlaps + ok.counts.thumbZone, 0)
	end)

	t.test("evaluate HUD rules: a toast over the tiles (844×390, shot 02)", function()
		local wrapped = dock(351, 232, 232, 124, {
			{ "Portrait", 361, 240, 46, 47 },
			{ "Hud_InspectButton", 415, 240, 83, 47 },
			{ "Hud_ChangeButton", 361, 298, 85, 47 },
		})
		local coach = node("SD_Hud/Hud_OnboardingCard", 245, 68, 435, 62, {
			opaque = true,
			children = { text("SD_Hud/Hud_OnboardingCard/Text", 257, 80, 330, 40, "Welcome to Squishy Duels!") },
		})
		local toastPanel = node("SD_Overlay/Toasts/Toast/Panel", 243, 151, 357, 36, {
			opaque = true,
			children = { text("SD_Overlay/Toasts/Toast/Panel/Text", 263, 157, 327, 20, "Upgrade ready") },
		})
		local toasts = node("SD_Overlay/Toasts", 243, 151, 357, 36, {
			children = { node("SD_Overlay/Toasts/Toast", 243, 151, 357, 36, { children = { toastPanel } }) },
		})
		local roots = { hudLeft(), tileRow(TILES_844, 68, 165), hudRight(), wrapped, duel(199), coach }
		local f = LayoutAudit.evaluate(hudScreens(roots, { toasts }), NARROW)
		expect.equal(f.counts.hudOverlaps, 2)
		expect.deepEqual(
			f.hudOverlaps[1],
			{ a = "SD_Overlay/Toasts/Toast/Panel", b = "SD_Hud/Hud_Nav/Hud_QuestsButton", area = 64 * 22 }
		)
		expect.equal(f.hudOverlaps[2].b, "SD_Hud/Hud_Nav/Hud_DailyButton")
		expect.equal(f.counts.overlaps, 0) -- other ScreenGuis are never siblings
		-- Fixed: one row at the bottom, the toast column moved right of the tiles.
		local oneRow = dock(351, 300, 300, 66, {
			{ "Portrait", 361, 309, 46, 47 },
			{ "Hud_InspectButton", 419, 309, 98, 47 },
			{ "Hud_ChangeButton", 529, 309, 100, 47 },
		})
		toastPanel.rect = { x = 400, y = 151, w = 357, h = 36 }
		toasts.rect = toastPanel.rect
		toasts.children[1].rect = toastPanel.rect
		toastPanel.children[1].rect = { x = 420, y = 157, w = 327, h = 20 }
		local ok = LayoutAudit.evaluate(
			hudScreens({ hudLeft(), tileRow(TILES_844, 68, 165), hudRight(), oneRow, duel(199), coach }, { toasts }),
			NARROW
		)
		expect.equal(ok.counts.hudOverlaps + ok.counts.thumbZone, 0)
	end)

	t.test("evaluate HUD rules: a group over the Daily tile at 667×375 (the old three-row dock)", function()
		local hud667 = { x = 0, y = 58, w = 667, h = 297 }
		local stacked = dock(279, 162, 130, 178, {
			{ "Portrait", 289, 170, 48, 48 },
			{ "Hud_InspectButton", 289, 226, 87, 47 },
			{ "Hud_ChangeButton", 289, 283, 87, 47 },
		})
		local roots = { hudLeft(), tileRow(TILES_667, 60, 165), stacked }
		local f = LayoutAudit.evaluate({ { rect = hud667, roots = roots, name = "SD_Hud" } }, NARROW)
		expect.equal(f.counts.hudOverlaps, 1)
		expect.deepEqual(
			f.hudOverlaps[1],
			{ a = "SD_Hud/Hud_Nav/Hud_DailyButton", b = "SD_Hud/Hud_EquippedCard", area = 60 * 54 }
		)
	end)

	t.test(
		"evaluate HUD rules (lobby HUD 2026-10-11): the Duel CTA, the coach card and a toast at the top middle",
		function()
			local cta = node("SD_Hud/Hud_DuelButton", 300, 68, 244, 56, { button = true, active = true, opaque = true })
			local coach = node("SD_Hud/Hud_OnboardingCard", 250, 131, 435, 62, {
				opaque = true,
				children = { text("SD_Hud/Hud_OnboardingCard/Text", 262, 143, 330, 40, "Squeeze squishies anywhere") },
			})
			local function toastAt(y: number): any
				local panel = node("SD_Overlay/Toasts/Toast/Panel", 243, y, 357, 36, {
					opaque = true,
					children = { text("SD_Overlay/Toasts/Toast/Panel/Text", 263, y + 6, 327, 20, "Upgrade ready") },
				})
				return node("SD_Overlay/Toasts", 243, y, 357, 36, {
					children = { node("SD_Overlay/Toasts/Toast", 243, y, 357, 36, { children = { panel } }) },
				})
			end
			local roots = { hudLeft(), hudRight(), cta, coach }
			-- The toasts chained under the coach card (NotifyFormat): nothing overlaps.
			local ok = LayoutAudit.evaluate(hudScreens(roots, { toastAt(200) }), NARROW)
			expect.equal(ok.counts.hudOverlaps, 0)
			-- A toast at the old default top (110 base) covers the coach card under the CTA: found.
			local f = LayoutAudit.evaluate(hudScreens(roots, { toastAt(151) }), NARROW)
			expect.equal(f.counts.hudOverlaps, 1)
			expect.equal(f.hudOverlaps[1].a, "SD_Overlay/Toasts/Toast/Panel")
			expect.equal(f.hudOverlaps[1].b, "SD_Hud/Hud_OnboardingCard")
		end
	)

	t.test("evaluate HUD rules: the thumbstick zone on narrow layouts only", function()
		-- The tile row 30 px lower than in the shots (ending at 249, 61% of the HUD's height) and the practice panel of
		-- shot 25 (13, 227, 161 × 72) reach into the lower-left zone (x < 337.6, y > 229.6).
		local practice = node("SD_Hud/Practice_Panel", 13, 227, 161, 72, {
			opaque = true,
			children = { text("SD_Hud/Practice_Panel/Row_throws", 23, 237, 141, 15, "Throws: 0") },
		})
		local roots = { hudLeft(), tileRow(TILES_844, 68, 195), practice }
		local narrow = LayoutAudit.evaluate(hudScreens(roots), NARROW)
		-- Squishies, Boxes, Shop and Quests reach into it (Daily starts at x 316: 21.6 px in, also counted); the panel too.
		expect.equal(narrow.counts.thumbZone, 6)
		expect.equal(narrow.thumbZone[1].path, "SD_Hud/Hud_Nav/Hud_SquishiesButton")
		expect.near(narrow.thumbZone[1].area, 68 * (249 - (58 + 312 * 0.55)), 1)
		expect.equal(narrow.thumbZone[6].path, "SD_Hud/Practice_Panel")
		expect.equal(narrow.counts.thumbZoneExpected, 0)
		-- The tiles and the practice panel overlap each other too (different groups).
		expect.truthy(narrow.counts.hudOverlaps > 0)
		-- PC (not narrow): no zone.
		local pc = LayoutAudit.evaluate(hudScreens(roots), LIMITS)
		expect.equal(pc.counts.thumbZone + pc.counts.thumbZoneExpected, 0)
		-- No layout ends above the line (planFits false): the left side's hits are expected, the panel's are not.
		local expected = table.clone(NARROW)
		expected.zoneExpected = { Hud_Left = true, Hud_Nav = true }
		local planned = LayoutAudit.evaluate(hudScreens(roots), expected)
		expect.equal(planned.counts.thumbZoneExpected, 5)
		expect.equal(planned.counts.thumbZone, 1)
		expect.equal(planned.thumbZone[1].path, "SD_Hud/Practice_Panel")
		-- The tiles as shot (ending at 219, 52%) are clear of a zone measured in the HUD's own height.
		local shot = LayoutAudit.evaluate(hudScreens({ hudLeft(), tileRow(TILES_844, 68, 165) }), NARROW)
		expect.equal(shot.counts.thumbZone, 0)
		-- Integration (foam fix batch): run() measures the zone against the whole screen (844×370, the HUD under the 58 px
		-- inset), as HudFormat.thumbstickZone does. It starts at 203.5, so the shot's five tiles reach 15.5 px into it
		-- (the reviewers' finding).
		local whole = table.clone(NARROW)
		whole.zoneScreenHeight = 370
		local shotWhole = LayoutAudit.evaluate(hudScreens({ hudLeft(), tileRow(TILES_844, 68, 165) }), whole)
		expect.equal(shotWhole.counts.thumbZone, 5)
		expect.equal(shotWhole.thumbZone[1].path, "SD_Hud/Hud_Nav/Hud_SquishiesButton")
		expect.near(shotWhole.thumbZone[1].area, 68 * (219 - 203.5), 1)
		-- The fixed phone layout: the coin capsule and the compact Grip card side by side ("beside"), the tile row right
		-- under them, ending at 174.
		local coins = node("SD_Hud/Hud_Left/Hud_Coins", 10, 68, 124, 44, {
			children = { node("SD_Hud/Hud_Left/Hud_Coins/Hud_CoinsButton", 10, 68, 124, 44, { button = true }) },
		})
		local grip = node("SD_Hud/Hud_Left/Hud_GripSlot/Hud_GripButton", 142, 68, 180, 44, {
			button = true,
			opaque = true,
		})
		local beside = node("SD_Hud/Hud_Left", 10, 68, 312, 44, { children = { coins, grip } })
		local fixed = LayoutAudit.evaluate(hudScreens({ beside, tileRow(TILES_844, 68, 120) }), whole)
		expect.equal(fixed.counts.thumbZone + fixed.counts.hudOverlaps, 0)
	end)

	t.test("primaryOk and share", function()
		local good = { exists = true, inside = true, visible = true, selectable = true, w = 100, h = 50 }
		expect.truthy(LayoutAudit.primaryOk(good))
		for _, key in { "exists", "inside", "visible", "selectable" } do
			local bad = table.clone(good)
			bad[key] = false
			expect.falsy(LayoutAudit.primaryOk(bad))
		end
		local flat = table.clone(good)
		flat.h = 0
		expect.falsy(LayoutAudit.primaryOk(flat))
		expect.equal(LayoutAudit.share(200, 0, 375), 0.533)
		expect.equal(LayoutAudit.share(236, 36, 400), 0.5)
		expect.equal(LayoutAudit.share(200, 0, 0), nil)
		expect.equal(LayoutAudit.share(0 / 0, 0, 375), nil)
	end)

	-- Fake dependencies for run() (no UIController, no PlayerGui).
	local function fakeDeps(playerGui: Instance?, locked: boolean): any
		return {
			ui = {
				debugScreens = function()
					return {}
				end,
				open = function()
					return false
				end,
				close = function()
					return false
				end,
				closeAll = function() end,
				isOpen = function()
					return false
				end,
				openModals = function()
					return {}
				end,
				topModal = function()
					return nil
				end,
				scale = function()
					return 0.85
				end,
				layoutClass = function()
					return "compact"
				end,
			},
			playerGui = function()
				return playerGui
			end,
			isLobbyLocked = function()
				return locked
			end,
			equipped = function()
				return "toast"
			end,
			textScale = function()
				return 1
			end,
			openInspect = nil,
			inspectedId = nil,
			inspectSafe = function()
				return false, "test"
			end,
		}
	end

	t.test("run: bad options, lists outside the lobby and a missing PlayerGui are refused", function()
		local folder = Instance.new("Folder")
		for _, opts in { "all", { screens = 5 }, { maxItems = -1 }, { maxItems = 0 / 0 } } :: { any } do
			local reply = LayoutAudit.run(opts, fakeDeps(folder, false))
			expect.equal(reply.ok, false)
			expect.equal(type(reply.error), "string")
		end
		local locked = LayoutAudit.run({ screens = "all" }, fakeDeps(folder, true))
		expect.equal(locked.ok, false)
		expect.truthy(string.find(locked.error, "lobby", 1, true) ~= nil)
		local list = LayoutAudit.run({ screens = { "squishies" } }, fakeDeps(folder, true))
		expect.equal(list.ok, false)
		local none = LayoutAudit.run(nil, fakeDeps(nil, false))
		expect.equal(none.ok, false)
		expect.equal(none.error, "no PlayerGui")
		-- A box reveal open or waiting: closing it would send AckReveal, so nothing is closed.
		local closed = 0
		local busy = fakeDeps(folder, false)
		busy.revealBusy = function()
			return true
		end
		busy.ui.closeAll = function()
			closed += 1
		end
		local refused = LayoutAudit.run({ screens = "all" }, busy)
		expect.equal(refused.ok, false)
		expect.truthy(string.find(refused.error, "AckReveal", 1, true) ~= nil)
		local open = fakeDeps(folder, false)
		open.ui.openModals = function()
			return { "boxes", "boxReveal" }
		end
		open.ui.closeAll = busy.ui.closeAll
		expect.equal(LayoutAudit.run({ screens = { "boxes" } }, open).ok, false)
		expect.equal(closed, 0)
		folder:Destroy()
	end)

	t.test("run: a screen list skips what must not open and never opens it", function()
		local folder = Instance.new("Folder")
		local deps = fakeDeps(folder, false)
		local opened: { string } = {}
		deps.ui.debugScreens = function()
			return {
				{ name = "boxReveal", modal = true, open = false },
				{ name = "inspect", modal = true, open = false },
				{ name = "onboarding", modal = false, open = false },
				{ name = "queue", modal = false, open = false },
			}
		end
		deps.ui.open = function(name: string): boolean
			table.insert(opened, name)
			return false
		end
		local reply = LayoutAudit.run({ screens = { "queue", "boxReveal", "onboarding", "inspect", "nope" } }, deps)
		expect.equal(reply.ran, true)
		expect.equal(reply.mode, "list")
		expect.equal(#reply.views, 0)
		local reasons = {}
		for _, entry in reply.skipped do
			reasons[entry.name] = entry.reason
		end
		expect.truthy(string.find(reasons.queue, "QueueJoin", 1, true) ~= nil)
		expect.equal(reasons.boxReveal, "needs a box result")
		expect.equal(reasons.onboarding, "not a modal")
		expect.equal(reasons.inspect, "InspectController is not built")
		expect.equal(reasons.nope, "not registered")
		-- With Inspect built but its open not safe (the onboarding step), it is still not opened.
		deps.openInspect = function(): boolean
			table.insert(opened, "inspect")
			return true
		end
		local again = LayoutAudit.run({ screens = { "inspect" } }, deps)
		expect.equal(again.skipped[1].reason, "test")
		expect.deepEqual(opened, {})
		folder:Destroy()
	end)

	t.test("run: hud.narrow follows the compact class or touch input; the new lists are in every view", function()
		local folder = Instance.new("Folder")
		local deps = fakeDeps(folder, false)
		deps.touch = function(): boolean
			return false
		end
		local compact = LayoutAudit.run(nil, deps)
		expect.equal(compact.ran, true)
		expect.equal(compact.hud.narrow, true) -- the compact class
		expect.equal(compact.hud.thumbstickZone, nil) -- no HUD shows
		for _, key in { "brokenWords", "hudOverlaps", "thumbZone", "thumbZoneExpected" } do
			expect.equal(compact.counts[key], 0)
			expect.deepEqual(compact.views[1][key], {})
		end
		-- Lobby HUD (spec 2026-10-11): no dock, so no dockRows rule.
		expect.equal(compact.counts.dockRows, nil)
		expect.equal(compact.views[1].dockRows, nil)
		deps.ui.layoutClass = function()
			return "regular"
		end
		expect.equal(LayoutAudit.run(nil, deps).hud.narrow, false) -- PC
		deps.touch = function(): boolean
			return true
		end
		expect.equal(LayoutAudit.run(nil, deps).hud.narrow, true) -- a touch tablet
		folder:Destroy()
	end)

	-- Reading AbsoluteSize needs the engine (Studio); an offline runner without it skips this check.
	local engineSizes = pcall(function(): any
		local frame = Instance.new("Frame")
		local gui = Instance.new("ScreenGui")
		local reads: { any } = { frame.AbsoluteSize, frame.AbsolutePosition, gui.AbsoluteSize, gui.AbsolutePosition }
		table.insert(reads, gui.Enabled)
		frame:Destroy()
		gui:Destroy()
		return reads
	end)
	if engineSizes then
		t.test("run: what shows now is one 'current' view over the game's ScreenGuis", function()
			local folder = Instance.new("Folder")
			local gui = Instance.new("ScreenGui")
			gui.Name = "SD_Test"
			gui.Parent = folder
			local frame = Instance.new("Frame")
			frame.Parent = gui
			Instance.new("Frame").Parent = frame
			local hidden = Instance.new("Frame")
			hidden.Visible = false
			hidden.Parent = gui
			for _, name in { "SD_SoundPicker", "TouchGui" } do
				local other = Instance.new("ScreenGui")
				other.Name = name
				Instance.new("Frame").Parent = other
				other.Parent = folder
			end
			local reply = LayoutAudit.run(nil, fakeDeps(folder, true)) -- "current" also runs in a duel
			expect.equal(reply.ran, true)
			expect.equal(reply.mode, "current")
			expect.equal(#reply.views, 1)
			expect.equal(reply.views[1].name, "current")
			expect.equal(reply.views[1].primaryOk, nil) -- no modal open
			expect.equal(reply.counts.checked, 2) -- the two visible frames of SD_Test only
			expect.equal(reply.class, "compact")
			expect.equal(reply.scale, 0.85)
			expect.equal(reply.hud.leftMaxShare, UI.Grip.leftColumnMaxFraction)
			expect.equal(reply.hud.leftBottomShare, nil)
			expect.equal(reply.hud.planFits, nil) -- no columnFits dependency
			expect.equal(reply.counts.textTruncated, 0)
			expect.deepEqual(reply.skipped, {})
			-- The column plan's answer is passed through (false: no layout can end above the line).
			local withPlan = fakeDeps(folder, true)
			withPlan.columnFits = function(): boolean?
				return false
			end
			expect.equal(LayoutAudit.run(nil, withPlan).hud.planFits, false)
			folder:Destroy()
		end)
	end
end
