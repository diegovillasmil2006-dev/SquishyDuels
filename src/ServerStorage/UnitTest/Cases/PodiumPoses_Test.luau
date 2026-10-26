--!strict
-- PodiumPoses_Test: unit tests for StarterPlayerScripts.Client.Anim.PodiumPoses (end screens round B1, 2026-10-26;
-- P = Diego's uploads/sd/poses.js). Contract: the leg IK, the loop frames, a pose and a prop sample all equal the
-- numbers Diego's own poses.js gives (run in node, rounded to 1e-4); every clip names all 15 joints in every key; the
-- design's 180°-turned axes: X and Z angles negated, Y kept, the offset's X and Z negated.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-3

-- node: legIK / frameAt / samplePose / sampleProp of poses.js (2026-10-26).
local GOLDEN_IK = {
	{ { 0, 0, 0 }, { -1.6363, 3.3439, -1.7075 } },
	{ { 0.65, 0, 14 }, { -56.5123, 87.3522, -44.8399 } },
	{ { 1.0, 1.3, 24 }, { -104.1128, 74.2322, 5.8805 } },
}
local GOLDEN_FRAMES =
	{ { "squishSlam", 0.5, 15 }, { "squishSlam", 3.0, 54 }, { "shrug", 2.5, 15 }, { "slowClap", 1.7, 3 } }
local GOLDEN_POSES: { any } = {
	{
		"squishSlam",
		25,
		{
			off = { 0, -1, 0 },
			root = { 24, 360, 0 },
			waist = { 14, 0, 0 },
			neck = { -26, 0, 0 },
			lShoulder = { 42, 0, 55 },
			lElbow = { -22, 0, 0 },
			rShoulder = { -38, 0, -10 },
			rElbow = { -8, 0, 0 },
			lHip = { -14, 0, 4 },
			lKnee = { 80, 0, 0 },
			lAnkle = { 0, 0, 0 },
			rHip = { -104.1128, 0, -6 },
			rKnee = { 74.2322, 0, 0 },
			rAnkle = { 5.8805, 0, 0 },
		},
	},
	{
		"squishSlam",
		16,
		{ off = { 0, 2.45, 0 }, root = { 0, 210, 0 }, lShoulder = { -172, 0, 14 }, lKnee = { 110, 0, 0 } },
	},
	{
		"doubleFlex",
		40.5,
		{
			off = { 0, -0.063, 0 },
			waist = { -8, -7.4074, 0 },
			neck = { -8, -9.2593, 0 },
			lShoulder = { -90, 0, 97.5556 },
			lElbow = { -120.6667, 0, 0 },
			rShoulder = { -90, 0, -92 },
			lHip = { -12.9722, 0, 4 },
			lKnee = { 26.5191, 0, 0 },
			lAnkle = { -13.5469, 0, 0 },
		},
	},
	{ "plushToss", 20, { root = { 0, 241.4815, 0 }, neck = { -16.5926, 0, 0 }, rShoulder = { -60, 0, -50 } } },
	{
		"headPat",
		33,
		{ neck = { 11.688, 0, -8.208 }, lShoulder = { -150, 0.624, 40.416 }, lElbow = { -112.96, 0, 0 } },
	},
}

return function(t: Context)
	local expect = t.expect
	local PodiumPoses = t.requireClient("Anim/PodiumPoses")

	local function near3(a: { number }, b: { number }, what: string)
		for i = 1, 3 do
			expect.near(a[i], b[i], EPS, what .. "[" .. i .. "]")
		end
	end

	t.test("the leg IK equals the design's", function()
		for _, row in GOLDEN_IK do
			local i = row[1]
			local hip, knee, ankle = PodiumPoses.legIK(i[1], i[2], i[3])
			near3({ hip, knee, ankle }, row[2], "legIK")
		end
	end)

	t.test("a clip holds its loop after its length", function()
		for _, row in GOLDEN_FRAMES do
			expect.near(PodiumPoses.frameAt(PodiumPoses.CLIPS[row[1]], row[2]), row[3], EPS)
		end
		expect.equal(PodiumPoses.frameAt(PodiumPoses.CLIPS.squishSlam, -1), 0)
	end)

	t.test("a sampled pose equals the design's", function()
		for _, row in GOLDEN_POSES do
			local pose = PodiumPoses.samplePose(PodiumPoses.CLIPS[row[1]], row[2])
			for name, want in row[3] do
				near3(pose[name], want, row[1] .. "@" .. row[2] .. "." .. name)
			end
		end
	end)

	t.test("a prop sample carries the design's anchors, offsets and turns", function()
		local A, B, share = PodiumPoses.sampleProp(PodiumPoses.CLIPS.doubleFlex, 10)
		expect.equal(A.m, "air")
		near3(A.o, { 0, 7.6, 0.2 }, "air o")
		expect.equal(B.m, "head")
		near3(B.o, { 0, 0, 0 }, "head o")
		near3(B.sc, { 1.3, 0.7, 1.3 }, "head sc")
		expect.near(share, 0.064, EPS)
		local A2, B2, share2 = PodiumPoses.sampleProp(PodiumPoses.CLIPS.plushToss, 25)
		near3(A2.r, { 360, 0, 0 }, "toss r")
		near3(A2.o, { -0.4, 12, 0.6 }, "toss o")
		expect.equal(B2.m, "hand")
		near3(B2.r, { 720, 0, 0 }, "catch r")
		expect.near(share2, 0.125, EPS)
		local _, _, share3 = PodiumPoses.sampleProp(PodiumPoses.CLIPS.squishyHug, 14)
		expect.near(share3, 0.352, EPS)
	end)

	t.test("every key of every clip names all the joints", function()
		local count = 0
		for _ in PodiumPoses.JOINTS do
			count += 1
		end
		expect.equal(count, 15)
		for _, list in { PodiumPoses.VICTORY_ORDER, PodiumPoses.DEFEAT_ORDER } do
			expect.equal(#list, 6)
			for _, id in list do
				local clip = PodiumPoses.CLIPS[id]
				expect.truthy(clip, id)
				for _, key in clip.keys do
					expect.equal(#key.pose.off, 3)
					for name in PodiumPoses.JOINTS do
						expect.equal(#key.pose[name], 3, id .. " " .. name)
					end
				end
			end
		end
		expect.equal(PodiumPoses.CLIPS.squishSlam.hit, 25)
		expect.equal(PodiumPoses.CLIPS.shrug.hit, nil)
	end)

	t.test("the design's axes are turned 180° about Y", function()
		local cf = PodiumPoses.jointCFrame({ 30, 20, 10 })
		local rx, ry, rz = cf:ToEulerAnglesXYZ()
		expect.near(math.deg(rx), -30, EPS)
		expect.near(math.deg(ry), 20, EPS)
		expect.near(math.deg(rz), -10, EPS)
		-- A design shoulder at -172° X lifts the arm overhead and a little forward: forward is -Z here.
		local hang = PodiumPoses.jointCFrame({ -172, 0, 14 }):VectorToWorldSpace(Vector3.new(0, -1, 0))
		expect.truthy(hang.Y > 0.9, "overhead")
		expect.truthy(hang.Z < 0, "forward is -Z")
		local v = PodiumPoses.flip({ 1, 2, 3 })
		expect.equal(v, Vector3.new(-1, 2, -3))
	end)
end
