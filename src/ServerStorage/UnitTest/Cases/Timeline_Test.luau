--!strict
-- Timeline_Test: unit tests for StarterPlayerScripts.Client.Anim.Timeline. Server only (ServerStorage.UnitTest).
-- Contract (DESIGN §9.2, module header): Timeline.new(keys) with { t_ms, value, style, dir }; :eval(ms) eases through
-- TweenService:GetValue(alpha, style, dir); numbers, Vector3 and CFrame. A key's style/dir shape the segment arriving
-- at it; before the first key the first value, at or after the last key exactly the last value; equal times jump to
-- the later key. Bad keys (unsorted, mixed kinds, none) are rejected.
-- Squishy overhaul (spec 2026-10-09 §3.2): Config.Anim.squeeze.phases stays the single source of the press; its shape
-- is what SquishRig reads (anticipation, compression, widening, then the release pop; the deepest c at the widening),
-- and a toy's press is the Timeline of those phases scaled to its depth.

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local TweenService = game:GetService("TweenService")

return function(t: Context)
	local Timeline = t.requireClient("Anim/Timeline")
	local Config = t.requireShared("Config")
	local expect = t.expect

	t.test("holds the first value before the first key and the last value after the last key", function()
		local line = Timeline.new({
			{ t_ms = 100, value = 2 },
			{ t_ms = 200, value = 6 },
		})
		expect.equal(line:eval(-50), 2)
		expect.equal(line:eval(100), 2)
		expect.equal(line:eval(200), 6)
		expect.equal(line:eval(9999), 6)
		expect.equal(line:eval(0 / 0), 2)
		expect.equal(line:duration(), 200)
		expect.truthy(line:isDone(200))
		expect.falsy(line:isDone(199))
	end)

	t.test("linear segments interpolate", function()
		local line = Timeline.new({
			{ t_ms = 0, value = 0 },
			{ t_ms = 100, value = 10 },
		})
		expect.near(line:eval(50), 5)
		expect.near(line:eval(25), 2.5)
	end)

	t.test("the arriving key's style and direction go through TweenService:GetValue", function()
		local line = Timeline.new({
			{ t_ms = 0, value = 0 },
			{ t_ms = 100, value = 1, style = Enum.EasingStyle.Quad, dir = Enum.EasingDirection.Out },
			{ t_ms = 300, value = 3, style = Enum.EasingStyle.Sine, dir = Enum.EasingDirection.InOut },
		})
		expect.near(line:eval(50), TweenService:GetValue(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out))
		expect.near(line:eval(50), 0.75)
		local alpha = TweenService:GetValue(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		expect.near(line:eval(150), 1 + 2 * alpha)
	end)

	t.test("Vector3 and CFrame values", function()
		local vectors = Timeline.new({
			{ t_ms = 0, value = Vector3.zero },
			{ t_ms = 100, value = Vector3.new(2, 4, 6) },
		})
		local mid = vectors:eval(50)
		expect.near(mid.X, 1, 1e-6)
		expect.near(mid.Y, 2, 1e-6)
		expect.near(mid.Z, 3, 1e-6)

		local frames = Timeline.new({
			{ t_ms = 0, value = CFrame.identity },
			{ t_ms = 100, value = CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(90), 0) },
		})
		local half = frames:eval(50)
		expect.near(half.Position.Y, 5, 1e-5)
		local _, yaw, _ = half:ToEulerAnglesYXZ()
		expect.near(yaw, math.rad(45), 1e-4)
		expect.equal(frames:eval(100), CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(90), 0))
	end)

	t.test("equal key times make an instant jump to the later key", function()
		local line = Timeline.new({
			{ t_ms = 0, value = 0 },
			{ t_ms = 100, value = 1 },
			{ t_ms = 100, value = 5 },
			{ t_ms = 200, value = 7 },
		})
		expect.near(line:eval(99.999), 1, 1e-3)
		expect.equal(line:eval(100), 5)
		expect.near(line:eval(150), 6)
	end)

	t.test("the squeeze phase table maps to one key per phase end", function()
		local keys = { { t_ms = 0, value = 1 } }
		for _, phase in Config.Anim.squeeze.phases do
			table.insert(keys, { t_ms = phase.endMs, value = phase.c, style = phase.style, dir = phase.direction })
		end
		local line = Timeline.new(keys)
		for _, phase in Config.Anim.squeeze.phases do
			expect.near(line:eval(phase.endMs), phase.c, 1e-9)
		end
		expect.equal(line:eval(0), 1)
	end)

	t.test("the squeeze phase table has the shape SquishRig reads", function()
		local phases = Config.Anim.squeeze.phases
		local names = {}
		local deepest, deepestName = math.huge, ""
		for _, phase in phases do
			table.insert(names, phase.name)
			if phase.c < deepest then
				deepest, deepestName = phase.c, phase.name
			end
		end
		expect.deepEqual(names, { "anticipation", "compression", "widening", "releasePop" })
		expect.equal(deepestName, "widening") -- the press ends at the toy's depth, the pop rises from it
		expect.truthy(phases[#phases].c > deepest)
	end)

	t.test("a toy's press is the Timeline of the Config phases scaled to its depth", function()
		local SquishRig = t.requireClient("Anim/SquishRig")
		local motion = {
			squeeze = { depth = 0.58, widen = 0.68, kRel = 36, cRel = 8.5 },
			feel = "foam",
			flight = { style = "frisbee" },
		}
		local phases = Config.Anim.squeeze.phases
		local deepest = math.huge
		for _, phase in phases do
			deepest = math.min(deepest, phase.c)
		end
		local keys = { { t_ms = 0, value = 1 } }
		for _, phase in phases do
			local c = 1 - (1 - phase.c) * (1 - motion.squeeze.depth) / (1 - deepest)
			table.insert(keys, { t_ms = phase.endMs, value = c, style = phase.style, dir = phase.direction })
		end
		local line = Timeline.new(keys)
		local rig = SquishRig.new(motion, { blink = false })
		local out = SquishRig.newOut()
		rig:tap()
		-- Up to the pop end (after it the release spring and kick take over).
		for step = 1, 38 do
			rig:step(0.01, out)
			expect.near(out.S.Y, line:eval(step * 10), 1e-3)
		end
	end)

	t.test("rejects bad keys", function()
		expect.throws(function()
			Timeline.new({})
		end)
		expect.throws(function()
			Timeline.new({ { t_ms = 100, value = 1 }, { t_ms = 50, value = 2 } })
		end, "sorted")
		local mixed: { any } = { { t_ms = 0, value = 1 }, { t_ms = 50, value = Vector3.one } }
		expect.throws(function()
			Timeline.new(mixed)
		end)
		expect.throws(function()
			Timeline.new({ { t_ms = 0, value = "a" } } :: any)
		end)
	end)
end
