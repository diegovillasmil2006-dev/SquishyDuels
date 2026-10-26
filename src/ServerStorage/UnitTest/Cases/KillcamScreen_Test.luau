--!strict
-- KillcamScreen_Test: unit tests for StarterPlayerScripts.Client.UI.Match.KillcamScreen (killcam step 2, 2026-10-26;
-- S = Diego's "Squishy Duels LOADING SCREEN Y MATCH HUD.dc.html"). Contract: it builds the bars, the KILLCAM pill
-- (YOUR VIEW / NAME'S VIEW), the SLOW-MO pill, FINAL KILL letter by letter and the killer's card, plays the card sound
-- at once; SLOW-MO shows only while slow; the squish places and shows SQUISHED! with the boom and the splat; finish()
-- takes it out and it is done goneS later.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local Config = t.requireShared("Config")
	local Strings = t.requireShared("Strings")
	local KillcamScreen = t.requireClient("UI/Match/KillcamScreen")
	local MatchHudFormat = t.requireClient("UI/MatchHudFormat")
	local CFG = Config.UI.Match.finish.killcam.screen
	local TEXT = Strings.matchHud.killcam

	local function who(userId: number, name: string, you: boolean): any
		return {
			userId = userId,
			name = name,
			squishyId = "",
			team = "Strawberry",
			you = you,
			player = nil,
			look = MatchHudFormat.playerLook("tdm", "Strawberry", nil),
		}
	end

	local function make(killerIsYou: boolean): (any, Frame, { string })
		local root = Instance.new("Frame")
		local played: { string } = {}
		local ctx: any = {
			root = root,
			canvas = function(): Vector2
				return Vector2.new(1440, 900)
			end,
			play = function(key: string)
				table.insert(played, key)
			end,
		}
		local screen = KillcamScreen.new(ctx, {
			killer = who(-1, "NoodleKid_920", killerIsYou),
			victim = who(-2, "PuffyBear_15", false),
			reduced = true,
			compact = false,
		})
		return screen, root, played
	end

	local function texts(root: Instance): string
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("TextLabel") then
				table.insert(out, d.Text)
			end
		end
		return table.concat(out, "")
	end

	t.test("it builds Diego's pieces and plays the card sound at once (S:195-229, S:754)", function()
		local screen, root, played = make(false)
		local layer = assert(root:FindFirstChild("SD_KillcamScreen"))
		expect.truthy(layer:FindFirstChild("BarTop", true) ~= nil)
		expect.truthy(layer:FindFirstChild("BarBottom", true) ~= nil)
		local all = texts(layer)
		local view = Strings.format(TEXT.view, { name = "NOODLEKID_920" })
		expect.truthy(string.find(all, (string.gsub(view, " ", "")), 1, true) ~= nil) -- the pill's letters, one each
		expect.truthy(string.find(all, "NoodleKid_920", 1, true) ~= nil)
		expect.truthy(string.find(all, "PuffyBear_15", 1, true) ~= nil)
		local title = assert(layer:FindFirstChild("Title", true))
		local n = 0
		for _, child in title:GetChildren() do
			if child.Name == "Letter" then
				n += 1
			end
		end
		expect.equal(n, #string.gsub(TEXT.title, " ", ""))
		expect.deepEqual(played, { "match.vote.card" })
		screen:destroy()
		local mine, mineRoot = make(true)
		expect.truthy(string.find(texts(mineRoot), (string.gsub(TEXT.yourView, " ", "")), 1, true) ~= nil)
		mine:destroy()
	end)

	t.test("SLOW-MO only while slow; the squish shows SQUISHED! with the boom and the splat; finish ends it", function()
		local screen, root, played = make(false)
		local slow = assert(root:FindFirstChild("SlowPill", true)) :: Frame
		local now = os.clock()
		screen:update(now + 1)
		expect.equal(slow.BackgroundTransparency, 1)
		screen:slow(true)
		screen:update(os.clock() + 1)
		expect.truthy(slow.BackgroundTransparency < 1)
		screen:slow(false)
		screen:update(os.clock() + 1)
		expect.equal(slow.BackgroundTransparency, 1)
		local stamp = assert(root:FindFirstChild("Stamp", true)) :: Frame
		expect.falsy(stamp.Visible)
		screen:impact(Vector3.new(0, 5, 0))
		expect.truthy(stamp.Visible)
		expect.truthy(table.find(played, "match.found.impact") ~= nil)
		expect.truthy(table.find(played, "match.splat") ~= nil)
		local at = os.clock()
		screen:finish(at)
		screen:update(at + 0.1)
		expect.falsy(screen:done())
		screen:update(at + CFG.goneS + 0.01)
		expect.truthy(screen:done())
		screen:destroy()
	end)
end
