--!strict
-- ShowOffTracks_Test: unit tests for StarterPlayerScripts.Client.Anim.ShowOffTracks (pens3 phase 11: the shelf's
-- show-off loops, lobby design v6 kit.json "showoff", K:6982-7829). Server only (ServerStorage.UnitTest). Pure.
-- Contract: one loop per Catalog squishy (14, K:6982), each verbatim from K (length, keys in time order inside the
-- loop); poseAt(kind, t, studs) loops over the length and gives the lift (posY × studs / 2, P3D:401's k) and the turn
-- (rotY as K has it, rotX and rotZ the other way round: the Roblox squishy faces -Z, the design's toy +Z, so a nod or a
-- roll reads the same); keys are eased the way they say (K's "Sine InOut" etc., P3D:485 EASE; "-" linear) and a track
-- that ends early holds its last value; the scale tracks are kept but not shown (no deform slot for shelf squishies:
-- a scale-only loop stands still); an unknown kind stands still.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

return function(t: Context)
	local expect = t.expect
	local ShowOffTracks = t.requireClient("Anim/ShowOffTracks")
	local Catalog = t.requireShared("Catalog")

	local function angles(turn: CFrame): (number, number, number)
		local x, y, z = turn:ToEulerAnglesXYZ()
		return math.deg(x), math.deg(y), math.deg(z)
	end

	t.test("one loop per Catalog squishy (K:6982), each with a length and keys in order inside it", function()
		local ids = {}
		for _, def in Catalog.list() do
			table.insert(ids, def.id)
		end
		table.sort(ids)
		expect.deepEqual(ShowOffTracks.ids(), ids)
		expect.equal(#ids, 14)
		for _, id in ids do
			local loop = ShowOffTracks.get(id)
			expect.truthy(loop.length > 0)
			expect.truthy(#loop.tracks > 0)
			for _, track in loop.tracks do
				local last = -1
				for _, key in track.keys do
					expect.truthy(key[1] >= last and key[1] <= loop.length)
					last = key[1]
				end
			end
		end
		expect.equal(ShowOffTracks.get("unicorn"), nil)
	end)

	t.test(
		"poseAt: Toast's Pop-Up Flip (K:7035): up 1.2 × studs / 2 at 0.35 s, a full flip by 0.7 s, looped",
		function()
			local lift, turn = ShowOffTracks.poseAt("toast", 0, 2)
			expect.near(lift, 0, 1e-6)
			expect.near(select(1, angles(turn)), 0, 1e-3)
			lift = ShowOffTracks.poseAt("toast", 0.35, 2)
			expect.near(lift, 1.2, 1e-6) -- a Common is 2 studs: k = 1
			expect.near(ShowOffTracks.poseAt("toast", 0.35, 5), 3, 1e-6) -- k = studs / 2
			expect.near(ShowOffTracks.poseAt("toast", 2.8 + 0.35, 2), 1.2, 1e-6) -- the loop starts again
			-- Quad Out: past halfway up after a quarter of the rise.
			local quarter = ShowOffTracks.poseAt("toast", 0.35 / 4, 2)
			expect.truthy(quarter > 1.2 / 4)
			-- The flip ends where it began (360°) and holds to the loop's end.
			local _, done = ShowOffTracks.poseAt("toast", 1.5, 2)
			local x, y, z = angles(done)
			expect.truthy(math.abs(x) < 1e-3 or math.abs(math.abs(x) - 360) < 1e-3)
			expect.near(y, 0, 1e-3)
			expect.near(z, 0, 1e-3)
		end
	)

	t.test("poseAt: rotY as K has it; rotX and rotZ flipped, so the Dragon still lifts its head (K:7339)", function()
		-- Banana's Peel Twirl (K:7091): Sine InOut 0 -> 360 over 1.2 s: 180° at 0.6 s, and its 0.3 hop.
		local lift, turn = ShowOffTracks.poseAt("banana", 0.6, 2)
		expect.near(lift, 0.3, 1e-6)
		expect.near((turn.LookVector - Vector3.new(0, 0, 1)).Magnitude, 0, 1e-3) -- half a turn about its up
		-- Dragon's Roar Puff: rotX -10° at 0.4 s in the design's frame -> +10° about the Roblox model's X.
		local _, roar = ShowOffTracks.poseAt("dragon", 0.4, 5)
		local rx = angles(roar)
		expect.near(rx, 10, 1e-3)
		-- Cloud Bunny's Float Bob (K:7693): rotZ starts at -3° -> +3° here.
		local _, bob = ShowOffTracks.poseAt("cloud_bunny", 0, 2)
		local _, _, rz = angles(bob)
		expect.near(rz, 3, 1e-3)
		-- Banana's hop track ends at 1.2 s: it holds 0 to the loop's end.
		expect.near(ShowOffTracks.poseAt("banana", 2, 2), 0, 1e-6)
	end)

	t.test("poseAt: the scale tracks are not shown (a scale-only loop stands still); an unknown kind too", function()
		for _, time in { 0, 0.7, 1.1, 2 } do
			local lift, turn = ShowOffTracks.poseAt("kitty_bread", time, 2)
			expect.equal(lift, 0)
			expect.equal(turn, CFrame.identity)
		end
		local lift, turn = ShowOffTracks.poseAt("unicorn", 1, 2)
		expect.equal(lift, 0)
		expect.equal(turn, CFrame.identity)
	end)
end
