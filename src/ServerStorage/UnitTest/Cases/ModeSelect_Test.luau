--!strict
-- ModeSelect_Test: unit tests for StarterPlayerScripts.Client.UI.ModeSelect. Server only (ServerStorage.UnitTest).
-- Contract (2026-10-24; L = Diego's "Squishy Duels LOBBY HUD.dc.html"): the cards are min(66vh, 600) tall at .66 wide,
-- 1.2vw apart, centred above the 7vh padding (L:182-184), and shrink to fit a narrow screen; Left / Right stop at the
-- ends; the seeded field is the design's own (Park-Miller seed 11, its values as JavaScript draws them); the screen
-- builds the three cards with PLAY on the picked one only (TDM first) and no wrapping text, a pick moves PLAY, PLAY
-- closes the screen and hands its card's id to onPlay once.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local ModeSelect = t.requireClient("UI/ModeSelect")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local MS = Config.UI.ModeSelect

	local function near(a: number, b: number, eps: number?): boolean
		return math.abs(a - b) <= (eps or 1e-3)
	end

	t.test("layout: the design's card size, gap and centring at 1440x810, the 600 px cap at 1920x1080", function()
		local L = ModeSelect.layout(Vector2.new(1440, 810))
		expect.truthy(near(L.cardH, 534.6))
		expect.truthy(near(L.cardW, 534.6 * 0.66))
		expect.truthy(near(L.gap, 17.28))
		expect.truthy(near(L.left, (1440 - (3 * L.cardW + 2 * L.gap)) / 2))
		expect.truthy(near(L.top, (810 - 56.7 - 534.6) / 2))
		expect.truthy(near(L.contentScale, (534.6 - 12) / MS.inner.refHeight))
		expect.truthy(near(L.raysPx, 1440 * 1.8))
		expect.truthy(near(L.titleScale, 35.64 / 40))
		local big = ModeSelect.layout(Vector2.new(1920, 1080))
		expect.equal(big.cardH, 600)
		expect.truthy(near(big.titleScale, 1)) -- clamp(22, 4.4vh, 40) at 47.5 px -> 40
	end)

	t.test("layout: a narrow screen shrinks the row inside its margins; a tiny one keeps a card", function()
		local L = ModeSelect.layout(Vector2.new(400, 800))
		expect.truthy(L.left >= MS.card.edgeMargin - 1e-6)
		expect.truthy(L.left + 3 * L.cardW + 2 * L.gap <= 400 - MS.card.edgeMargin + 1e-6)
		local phone = ModeSelect.layout(Vector2.new(844, 390))
		expect.truthy(near(phone.cardH, 390 * 0.66))
		expect.truthy(near(phone.titleScale, 22 / 40)) -- 4.4vh = 17.2 px -> the 22 px floor
		local tiny = ModeSelect.layout(Vector2.new(0, 0))
		expect.truthy(tiny.cardH > 2 * MS.card.border)
	end)

	t.test("step: Left / Right move one card and stop at the ends", function()
		expect.equal(ModeSelect.step(2, -1), 1)
		expect.equal(ModeSelect.step(1, -1), 1)
		expect.equal(ModeSelect.step(3, 1), 3)
		expect.equal(ModeSelect.step(2, 1, 3), 3)
	end)

	t.test("field: the design's seeded values (L:993-1002, as JavaScript draws them), the same every time", function()
		local field = ModeSelect.field()
		expect.equal(#field.shards, 10)
		expect.equal(#field.bubbles, 16)
		expect.equal(#field.sparks, 14)
		expect.equal(#field.toys, 7)
		expect.equal(field.shards[1].dur, 3)
		expect.equal(field.shards[1].delay, -1.79)
		expect.equal(field.shards[10].dur, 3.44)
		expect.equal(field.shards[10].delay, -2.94)
		expect.deepEqual(field.bubbles[1], { x = 59.2, size = 31, dur = 13.3, delay = -4.2 })
		expect.deepEqual(field.bubbles[16], { x = 10.6, size = 24, dur = 10.6, delay = -10.3 })
		expect.deepEqual(field.sparks[1], { x = 54.7, y = 85.4, size = 12, dur = 3.56, delay = -2.98 })
		expect.deepEqual(field.sparks[14], { x = 38.4, y = 13.2, size = 20, dur = 2.5, delay = -0.59 })
		expect.equal(field.toys[1].id, "cloud_bunny")
		expect.equal(field.toys[1].dur, 6.5)
		expect.equal(field.toys[1].delay, -4.6)
		expect.equal(field.toys[7].id, "mochi_fox")
		expect.equal(field.toys[7].dur, 7.1)
		expect.equal(field.toys[7].delay, -2.8)
		expect.deepEqual(ModeSelect.field(), field)
	end)

	t.test("open: three cards, PLAY on TEAM DEATHMATCH; a pick moves it; PLAY closes and plays once", function()
		local layer = Instance.new("Frame")
		layer.Size = UDim2.fromOffset(1440, 810)
		local played: { string } = {}
		local closes = 0
		local screen = ModeSelect.open({
			layer = layer,
			onPlay = function(id: string)
				table.insert(played, id)
			end,
			onClose = function()
				closes += 1
			end,
		})
		local root = screen.root
		expect.equal(root.Parent, layer)
		local row = root:FindFirstChild("Mode_Cards") :: Frame
		local function playBox(id: string): Frame
			return (row:FindFirstChild("Mode_" .. id) :: any).Pop.Pick.Body.Ref.Column.PlayBox
		end
		for _, id in MS.cards do
			expect.truthy(row:FindFirstChild("Mode_" .. id) ~= nil)
		end
		expect.equal(screen:picked(), "tdm")
		expect.falsy(playBox("1v1").Visible)
		expect.truthy(playBox("tdm").Visible)
		expect.falsy(playBox("ffa").Visible)
		expect.truthy(root:FindFirstChild("Mode_Close") ~= nil)
		expect.equal((root:FindFirstChild("Mode_Title") :: TextLabel).Text, "SELECT A GAME MODE")
		-- Found by playing at phone size (2026-10-24): a wrapping label under a UIScale dropped "MODE". No text wraps.
		local closeX = root:FindFirstChild("Mode_Close") :: Instance
		for _, text in root:GetDescendants() do
			if text:IsA("TextLabel") and text.Text ~= "" and not text:IsDescendantOf(closeX) then
				expect.equal(text.TextWrapped, false)
			end
		end
		screen:pick(1)
		expect.equal(screen:picked(), "1v1")
		expect.truthy(playBox("1v1").Visible)
		expect.falsy(playBox("tdm").Visible)
		screen:play()
		screen:play()
		expect.deepEqual(played, { "1v1" })
		expect.equal(closes, 1)
		expect.falsy(screen:isOpen())
		expect.equal(root.Parent, nil)
		screen:close()
		expect.equal(closes, 1)
		layer:Destroy()
	end)
end
