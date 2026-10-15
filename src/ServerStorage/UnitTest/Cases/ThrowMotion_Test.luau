--!strict
-- ThrowMotion_Test: unit tests for StarterPlayerScripts.Client.Anim.ThrowMotion (the 2026-10-15 full-body throws) and
-- the pieces that play it: ThrowController.motionDegrees / setStyle and ThrowTracks.flairAt. Server only
-- (ServerStorage.UnitTest). Pure: no instances but a plain Part for setStyle's root.
-- Contract:
--   * one clip per ThrowTracks style; STRIKE and SETTLE are Config.Anim.throw's releaseSnapMs and returnEndMs;
--   * every clip starts its windup on the hold (Config.Anim.poses.hold) and ends its release on it, and the release
--     starts exactly where the windup ends (no pop at the release);
--   * every joint it writes is a Config.Anim.joints.R15 joint; legs only when asked; every angle finite and within 190°;
--   * motionDegrees: R15 with a styled windup only (R6, the ultimate and an unstyled windup fall back to the poses);
--   * setStyle: the toy's ThrowTracks style, legs only for a thrower slower than 4 studs/s;
--   * flairAt: (1, 1, 1) at 0 and for sling / shove, the squash at cock, the stretch at rel, back to 1 after it.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-6

local function close(a: Vector3, b: Vector3, eps: number?): boolean
	return (a - b).Magnitude <= (eps or EPS)
end

return function(t: Context)
	local expect = t.expect
	local ThrowMotion = t.requireClient("Anim/ThrowMotion")
	local ThrowTracks = t.requireClient("Anim/ThrowTracks")
	local Config = t.requireShared("Config")
	local HOLD = Config.Anim.poses.hold.R15

	t.test("one clip per ThrowTracks style; STRIKE and SETTLE follow Config.Anim.throw", function()
		local styles = ThrowMotion.styles()
		expect.deepEqual(styles, ThrowTracks.styles())
		expect.near(ThrowMotion.STRIKE, Config.Anim.throw.releaseSnapMs / 1000, EPS)
		expect.near(ThrowMotion.SETTLE, Config.Anim.throw.returnEndMs / 1000, EPS)
		expect.truthy(ThrowMotion.STRIKE < ThrowMotion.WHIP and ThrowMotion.WHIP < ThrowMotion.FOLLOW)
		expect.truthy(ThrowMotion.FOLLOW < ThrowMotion.SETTLE)
	end)

	t.test("each clip starts and ends on the hold, and the release starts where the windup ends", function()
		for _, style in ThrowMotion.styles() do
			for _, pose in { ThrowMotion.windup(style, 0, true), ThrowMotion.release(style, ThrowMotion.SETTLE, true) } do
				for joint, degrees in pose do
					local want = HOLD[joint] or Vector3.zero
					expect.truthy(close(degrees, want))
				end
			end
			local cocked = ThrowMotion.windup(style, 1, true)
			local released = ThrowMotion.release(style, 0, true)
			for joint, degrees in cocked do
				expect.truthy(close(degrees, released[joint]))
			end
			-- the cocked pose is not the hold, and the strike moved again
			expect.falsy(close(cocked.RightShoulder, HOLD.RightShoulder, 1))
			expect.falsy(close(ThrowMotion.release(style, ThrowMotion.STRIKE, true).RightShoulder, cocked.RightShoulder, 1))
		end
	end)

	t.test("joints are the layer's R15 joints, legs only when asked, angles finite and within 190 degrees", function()
		local known = Config.Anim.joints.R15
		for _, style in ThrowMotion.styles() do
			for _, u in { 0, 0.2, 0.45, 0.7, 1 } do
				local withLegs = ThrowMotion.windup(style, u, true)
				local noLegs = ThrowMotion.windup(style, u, false)
				for joint, degrees in withLegs do
					expect.truthy(known[joint] ~= nil)
					for _, value in { degrees.X, degrees.Y, degrees.Z } do
						expect.truthy(value == value and math.abs(value) <= 190)
					end
				end
				for joint in noLegs do
					expect.falsy(ThrowMotion.LEGS[joint])
				end
				expect.truthy(withLegs.LeftHip ~= nil and withLegs.RightKnee ~= nil)
			end
			for _, time in { 0, 0.03, 0.07, 0.1, 0.13, 0.2, 0.26, 0.35, 0.45, 2 } do
				for _, degrees in ThrowMotion.release(style, time, true) do
					expect.truthy(degrees.X == degrees.X and math.abs(degrees.X) <= 190)
				end
			end
		end
		-- NaN and out-of-range input are held, never propagated
		local nan = 0 / 0
		expect.truthy(close(ThrowMotion.windup("overhand", nan, false).RightShoulder, HOLD.RightShoulder))
		expect.truthy(close(ThrowMotion.windup("overhand", 5, false).RightShoulder, ThrowMotion.windup("overhand", 1, false).RightShoulder))
		expect.truthy(close(ThrowMotion.release("unknown_style", 0.1, false).RightShoulder, ThrowMotion.release("overhand", 0.1, false).RightShoulder))
	end)

	t.test("ThrowController.motionDegrees plays the clip only for R15 with a styled windup", function()
		local ThrowController = t.requireClient("Controllers/ThrowController")
		local w = ThrowController.newWindup(0.18, 10, false)
		local sample = ThrowController.windupSample(0.09, 0.18)
		expect.equal(sample.phase, "windup")
		expect.near(sample.t :: number, 0.5, EPS)
		expect.equal(ThrowController.motionDegrees(sample, "R15", w), nil) -- no style yet
		ThrowController.setStyle(w, "banana", nil)
		expect.equal(w.style, "spiral")
		expect.equal(w.legs, false) -- no root: no legs
		local degrees = ThrowController.motionDegrees(sample, "R15", w)
		expect.truthy(degrees ~= nil and close((degrees :: any).RightShoulder, ThrowMotion.windup("spiral", 0.5, false).RightShoulder))
		expect.equal(ThrowController.motionDegrees(sample, "R6", w), nil)
		local release = ThrowController.releaseSample(0.1)
		expect.equal(release.phase, "release")
		expect.near(release.t :: number, 0.1, EPS)
		local r = ThrowController.motionDegrees(release, "R15", w)
		expect.truthy(r ~= nil and close((r :: any).RightShoulder, ThrowMotion.release("spiral", 0.1, false).RightShoulder))
		-- the ultimate's samples carry no phase
		local ult = ThrowController.ultReleaseSample(0.05, 1)
		expect.equal(ThrowController.motionDegrees(ult, "R15", w), nil)
	end)

	t.test("setStyle: legs only for a thrower slower than 4 studs/s", function()
		local ThrowController = t.requireClient("Controllers/ThrowController")
		local root = Instance.new("Part")
		root.Anchored = true
		local w = ThrowController.newWindup(0.18, 10, false)
		ThrowController.setStyle(w, "kitty_bread", root)
		expect.equal(w.style, "overhand")
		expect.equal(w.legs, true)
		root.AssemblyLinearVelocity = Vector3.new(16, 0, 0)
		local moving = ThrowController.newWindup(0.18, 10, false)
		ThrowController.setStyle(moving, "dragon", root)
		expect.equal(moving.style, "shove")
		expect.equal(moving.legs, false)
		root:Destroy()
	end)

	t.test("flairAt squashes into the cock, stretches on the strike and comes back; none for sling and shove", function()
		for _, style in ThrowTracks.styles() do
			local track = ThrowTracks.get(style)
			if style == "sling" or style == "shove" then
				expect.truthy(close(ThrowTracks.flairAt(track, track.cock), Vector3.one))
			else
				expect.truthy(close(ThrowTracks.flairAt(track, 0), Vector3.one))
				local cocked = ThrowTracks.flairAt(track, track.cock)
				expect.truthy(cocked.Y < 1 and cocked.X > 1)
				local strike = ThrowTracks.flairAt(track, track.rel)
				expect.truthy(strike.Z > 1 and strike.X < 1)
				expect.truthy(close(ThrowTracks.flairAt(track, track.rel + 0.2), Vector3.one))
			end
		end
	end)
end
