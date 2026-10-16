--!strict
-- UiIdle_Test: StarterPlayerScripts.Client.Anim.UiIdle, the UI FINAL R2 idle loops (plan work/ui/PLAN.md §2: the
-- design's perpetual @keyframes sdBob, sdCoin, sdFloat, sdPulse, sdBadge, sdShine, sdSpin, sdDot, sdRing, sdTwinkle,
-- H:23-43, and any other looping @keyframes through addFrames / addGradientWindow, H:51-68). Server only
-- (ServerStorage.UnitTest), Edit mode: holders live in an unparented ScreenGui; UiIdle.step(now) is called by hand with
-- made-up clocks; every case starts and ends with UiIdle.clear().
-- Contract:
--   * every kind and every Config.UI.motion.loops entry loops at or under 3 Hz (§9.12, §18.1 #4; a faster period a
--     caller passes is held to 3 Hz, a spin excepted) and a kind's pose at the end of a period is its pose at the
--     start;
--   * the poses are the design's: bob 6 px up and -2° at half (H:23), coin -8° -> 8° and 3 px up (H:24), float 12 px
--     up and -3° -> 3° (H:34), pulse 1.07 (H:29), badge 1.3 / -12° at 78%, 10° at 86%, -4° at 93% (H:32), dot .35 ->
--     1 and .8 -> 1.15 (H:35), ring .9 -> 1.5 while fading (H:43), twinkle clear -> whole and turned 90° (H:40), spin
--     a whole turn (H:30), shine at -200% of its strip until 55% then across to 900% (H:28);
--   * add() writes an inner holder only: its own Position / Rotation plus the pose, its SD_Pose scale, its
--     transparency; a shine moves its px strip by shares of the strip's own width (whatever it crosses); never an
--     object a layout places (add / addFrames return nil and nothing is written);
--   * an entry starts with its first step and waits out its delay at rest; invisible holders are skipped;
--   * ReducedMotion (Roblox's or UiPrefs' reduceMotion, also when it flips mid-run) rests every entry at its keyframe
--     0% pose (T11, PR9: a twinkle hidden, a shine's strip out of sight), one added while it is on too;
--   * addFrames plays a track on a loop (alternate runs every other period backwards; the delay held);
--     addGradientWindow slides a window of a longer gradient (sdLvGrad H:519);
--   * an entry ends with its object (Destroying) or remove(), the holder back at its own pose; Theme.rays spins its
--     picture with UiIdle. The loops run in a private, never-connected Scheduler (UiIdle.setScheduler), so only the
--     test's own steps (made-up clocks) move them.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local GuiService = game:GetService("GuiService")

local MAX_HZ = 3

return function(t: Context)
	local expect = t.expect
	local UiIdle = t.requireClient("Anim/UiIdle")
	local Scheduler = t.requireClient("Anim/Scheduler")
	local UiPrefs = t.requireClient("UI/UiPrefs")
	local Theme = t.requireClient("UI/Theme")
	local Config = t.requireShared("Config")
	local AssetTable = t.requireShared("AssetTable")
	local IDLE = Config.UI.motion.idle
	local LOOPS = Config.UI.motion.loops
	local systemReduced = GuiService.ReducedMotionEnabled

	-- A visible holder in an unparented ScreenGui, at (10, 20) in its parent; no entry left from another case.
	local function stage(): (ScreenGui, Frame)
		UiIdle.clear()
		UiIdle.setScheduler(Scheduler.new(false))
		local gui = Instance.new("ScreenGui")
		local holder = Instance.new("Frame")
		holder.Name = "Holder"
		holder.Position = UDim2.fromOffset(10, 20)
		holder.Size = UDim2.fromOffset(40, 40)
		holder.Parent = gui
		return gui, holder
	end

	local function done(gui: Instance)
		UiIdle.clear()
		UiIdle.setScheduler(Scheduler.new(false)) -- the later cases' loops stay off the frame events too
		UiPrefs.set("reduceMotion", false)
		gui:Destroy()
	end

	local function moving(): boolean
		return not (systemReduced or UiPrefs.get("reduceMotion"))
	end

	t.test("every kind and every design loop at or under 3 Hz; a kind ends each period where it started", function()
		for _, kind in UiIdle.KINDS do
			local spec = IDLE[kind]
			expect.truthy(spec ~= nil)
			expect.truthy(1 / spec.periodS <= MAX_HZ + 1e-9)
			local first, last = UiIdle.poseAt(kind, 0), UiIdle.poseAt(kind, 1)
			for _, field in { "x", "y", "scale", "rot", "alpha" } do
				local a, b = (first :: any)[field], (last :: any)[field]
				if kind == "spin" and field == "rot" then
					expect.near(b - a, 360, 1e-6) -- a whole turn is the same pose
				elseif kind == "ring" or kind == "shine" then
					continue -- these restart from their first pose (the design's 0% after 100%)
				else
					expect.truthy((a == nil and b == nil) or math.abs(a - b) < 1e-6)
				end
			end
		end
		for name, loop in LOOPS do
			local swingsPerSecond = 1 / (loop.periodS * (if loop.alternate then 2 else 1))
			if swingsPerSecond > MAX_HZ + 1e-9 then
				error(`loops.{name} is above 3 Hz`)
			end
		end
	end)

	t.test("the design's poses at the keyframes", function()
		local bob = UiIdle.poseAt("bob", 0.5)
		expect.near(bob.y, -IDLE.bob.risePx, 1e-6)
		expect.near(bob.rot, -IDLE.bob.rotDeg, 1e-6)
		expect.equal(IDLE.bob.risePx, 6)
		local coin = UiIdle.poseAt("coin", 0.5)
		expect.near(coin.rot, 8, 1e-6)
		expect.near(coin.y, -3, 1e-6)
		expect.near(UiIdle.poseAt("coin", 0).rot, -8, 1e-6)
		local float = UiIdle.poseAt("float", 0.5)
		expect.near(float.y, -12, 1e-6)
		expect.near(float.rot, 3, 1e-6)
		expect.near(UiIdle.poseAt("float", 0).rot, -3, 1e-6)
		expect.near(UiIdle.poseAt("pulse", 0.5).scale, 1.07, 1e-6)
		expect.near(UiIdle.poseAt("pulse", 0).scale, 1, 1e-6)
		local badgeUp = UiIdle.poseAt("badge", 0.78)
		expect.near(badgeUp.scale, 1.3, 1e-6)
		expect.near(badgeUp.rot, -12, 1e-6)
		expect.near(UiIdle.poseAt("badge", 0.86).rot, 10, 1e-6)
		expect.near(UiIdle.poseAt("badge", 0.93).rot, -4, 1e-6)
		expect.near(UiIdle.poseAt("badge", 0.93).scale, 1, 1e-6) -- a transform naming the rotation only: scale 1
		expect.near(UiIdle.poseAt("badge", 0.5).scale, 1, 1e-6) -- still for the first 70%
		local dotHalf, dotStart = UiIdle.poseAt("dot", 0.5), UiIdle.poseAt("dot", 0)
		expect.near(dotHalf.alpha, 1, 1e-6)
		expect.near(dotHalf.scale, 1.15, 1e-6)
		expect.near(dotStart.alpha, 0.35, 1e-6)
		expect.near(dotStart.scale, 0.8, 1e-6)
		local ringStart, ringEnd = UiIdle.poseAt("ring", 0), UiIdle.poseAt("ring", 1)
		expect.near(ringStart.scale, 0.9, 1e-6)
		expect.near(ringStart.alpha, 0.9, 1e-6)
		expect.near(ringEnd.scale, 1.5, 1e-6)
		expect.near(ringEnd.alpha, 0, 1e-6)
		local twinkle = UiIdle.poseAt("twinkle", 0.5)
		expect.near(twinkle.alpha, 1, 1e-6)
		expect.near(twinkle.scale, 1, 1e-6)
		expect.near(twinkle.rot, 90, 1e-6)
		expect.near(UiIdle.poseAt("twinkle", 0).alpha, 0, 1e-6)
		expect.near(UiIdle.poseAt("spin", 0.25).rot, 90, 1e-6)
		-- The shine strip: shares of its own width (H:28: -200% held to 55%, then to 900%).
		expect.near(UiIdle.poseAt("shine", 0).x, -2, 1e-6)
		expect.near(UiIdle.poseAt("shine", IDLE.shine.holdShare).x, -2, 1e-6)
		expect.near(UiIdle.poseAt("shine", 1).x, 9, 1e-6)
	end)

	t.test("add + step: the inner holder bobs from its own place, after its delay, at its period", function()
		local gui, holder = stage()
		local handle = UiIdle.add(holder, "bob", { periodS = 2, delayS = 0.5 })
		expect.truthy(handle ~= nil)
		expect.equal(UiIdle.count(), 1)
		UiIdle.step(100) -- the first step starts the clock
		expect.equal(holder.Position, UDim2.fromOffset(10, 20))
		UiIdle.step(100.4) -- still in the delay: at rest
		expect.equal(holder.Position, UDim2.fromOffset(10, 20))
		UiIdle.step(101.5) -- half a period after the delay
		if moving() then
			expect.near(holder.Position.Y.Offset, 20 - IDLE.bob.risePx, 1e-3)
			expect.near(holder.Rotation, -IDLE.bob.rotDeg, 1e-3)
			-- The caller re-places the holder: the loop goes on from the new place.
			holder.Position = UDim2.fromOffset(10, 50 - IDLE.bob.risePx)
			UiIdle.step(102.5) -- a whole period after the delay
			expect.near(holder.Position.Y.Offset, 50, 1e-3)
			expect.near(holder.Rotation, 0, 1e-3)
		end
		if handle then
			handle:remove()
		end
		expect.equal(UiIdle.count(), 0)
		expect.near(holder.Rotation, 0, 1e-3)
		done(gui)
	end)

	t.test("never a laid-out object: add and addFrames return nil and write nothing", function()
		UiIdle.clear()
		UiIdle.setScheduler(Scheduler.new(false))
		local gui = Instance.new("ScreenGui")
		local list = Instance.new("Frame")
		list.Parent = gui
		Instance.new("UIListLayout").Parent = list
		local child = Instance.new("Frame")
		child.Parent = list
		for _, kind in UiIdle.KINDS do
			expect.equal(UiIdle.add(child, kind), nil)
		end
		expect.equal(UiIdle.addFrames(child, LOOPS.hint.frames, { periodS = 1 }), nil)
		expect.equal(UiIdle.count(), 0)
		UiIdle.step(5)
		expect.equal(child.Position, UDim2.new())
		expect.equal(child.Rotation, 0)
		expect.equal(child:FindFirstChildOfClass("UIScale"), nil)
		done(gui)
	end)

	t.test("invisible holders are skipped; a pulse scales an SD_Pose UIScale", function()
		if systemReduced then
			return
		end
		local gui, holder = stage()
		UiIdle.add(holder, "pulse", { periodS = 1 })
		UiIdle.step(10)
		UiIdle.step(10.5)
		local found = holder:FindFirstChild("SD_Pose")
		expect.truthy(found ~= nil and found:IsA("UIScale"))
		local scale = found :: UIScale
		expect.near(scale.Scale, 1.07, 1e-4)
		holder.Visible = false
		UiIdle.step(11) -- at rest in the design, but not written while hidden
		expect.near(scale.Scale, 1.07, 1e-4)
		holder.Visible = true
		gui.Enabled = false -- a disabled ScreenGui hides it too
		UiIdle.step(11)
		expect.near(scale.Scale, 1.07, 1e-4)
		gui.Enabled = true
		UiIdle.step(11)
		expect.near(scale.Scale, 1, 1e-4)
		done(gui)
	end)

	t.test("ReducedMotion flipped on mid-run rests every loop at its 0% pose (T11, PR9)", function()
		local gui, holder = stage()
		local other = Instance.new("Frame")
		other.Rotation = 7
		other.Parent = gui
		local star = Instance.new("ImageLabel")
		star.ImageTransparency = 0
		star.Parent = gui
		UiIdle.add(holder, "float")
		UiIdle.add(other, "spin", { periodS = 4 })
		UiIdle.add(star, "twinkle")
		UiIdle.step(0)
		UiIdle.step(IDLE.float.periodS / 2)
		UiPrefs.set("reduceMotion", true)
		UiIdle.step(IDLE.float.periodS * 0.75)
		-- float's 0%: in place, turned -3° (H:34); spin's 0%: its own turn; twinkle's 0%: clear (H:40).
		expect.equal(holder.Position, UDim2.fromOffset(10, 20))
		expect.near(holder.Rotation, -IDLE.float.rotDeg, 1e-4)
		expect.near(other.Rotation, 7, 1e-4)
		expect.near(star.ImageTransparency, 1, 1e-4)
		UiIdle.step(IDLE.float.periodS * 2.3)
		expect.equal(holder.Position, UDim2.fromOffset(10, 20))
		expect.near(other.Rotation, 7, 1e-4)
		expect.equal(UiIdle.count(), 3) -- they stay registered and move again when it is off
		-- Removed: back at their own (authored) pose.
		UiIdle.clear()
		expect.near(holder.Rotation, 0, 1e-4)
		expect.near(star.ImageTransparency, 0, 1e-4)
		done(gui)
	end)

	t.test("a shine moves its px strip by its own width, out of sight at rest (G4.13)", function()
		local gui, clip = stage()
		clip.ClipsDescendants = true
		clip.Size = UDim2.fromOffset(300, 20) -- a short fill or a wide one: the strip's travel is its own width's
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 22, 1, 0)
		strip.Parent = clip
		UiIdle.add(strip, "shine", { periodS = 2 })
		UiIdle.step(0)
		expect.equal(strip.Position.X.Offset, -2 * 22) -- the 0% pose: -200%
		if moving() then
			local u = IDLE.shine.holdShare + (1 - IDLE.shine.holdShare) / 2
			UiIdle.step(2 * u) -- the middle of the crossing: ease-in-out at half = half the way
			expect.near(strip.Position.X.Offset, math.round(22 * (-2 + 11 / 2)), 1)
		end
		clip.Size = UDim2.fromOffset(60, 20) -- the fill shrinks: the strip keeps its width and travel
		expect.equal(strip.Size.X.Offset, 22)
		UiPrefs.set("reduceMotion", true)
		UiIdle.step(5)
		expect.equal(strip.Position.X.Offset, -2 * 22)
		done(gui)
	end)

	t.test("an entry added while ReducedMotion is on starts at rest (a shine's strip out of sight)", function()
		local gui, holder = stage()
		local strip = Instance.new("Frame")
		strip.Size = UDim2.new(0, 54, 1, 0)
		strip.Parent = holder
		UiPrefs.set("reduceMotion", true)
		UiIdle.step(0) -- a frame under ReducedMotion before the entry comes
		UiIdle.add(strip, "shine")
		UiIdle.step(1)
		expect.equal(strip.Position.X.Offset, -2 * 54)
		expect.equal(holder.Position, UDim2.fromOffset(10, 20))
		done(gui)
	end)

	t.test("a period faster than 3 Hz is held to 3 Hz", function()
		if systemReduced then
			return
		end
		local gui, holder = stage()
		UiIdle.add(holder, "pulse", { periodS = 0.25 }) -- 4 Hz asked
		UiIdle.step(0)
		UiIdle.step(1 / 6) -- half of a 1/3 s period: the pulse's peak
		local found = holder:FindFirstChild("SD_Pose")
		expect.truthy(found ~= nil and found:IsA("UIScale"))
		expect.near((found :: UIScale).Scale, IDLE.pulse.scale, 1e-4)
		done(gui)
	end)

	t.test("addFrames: a design loop (sdHint H:68) with its delay, alternate runs back (sdLvIdle H:51)", function()
		if systemReduced then
			return
		end
		local gui, holder = stage()
		local hint = LOOPS.hint
		UiIdle.addFrames(holder, hint.frames, { periodS = hint.periodS, delayS = 0.5, curve = hint.curve })
		UiIdle.step(0)
		UiIdle.step(0.4) -- the delay: the 0% pose (opacity .6)
		expect.near(holder.BackgroundTransparency, 1 - 0.6, 1e-4)
		UiIdle.step(0.5 + hint.periodS / 2) -- its middle: opacity 1, scale 1.08
		expect.near(holder.BackgroundTransparency, 0, 1e-4)
		expect.near((holder:FindFirstChild("SD_Pose") :: UIScale).Scale, 1.08, 1e-4)
		done(gui)

		local gui2, idle = stage()
		idle.Size = UDim2.fromOffset(100, 100)
		local lv = LOOPS.lvIdle
		UiIdle.addFrames(idle, lv.frames, { periodS = lv.periodS, alternate = true, curve = "linear" })
		UiIdle.step(0)
		UiIdle.step(lv.periodS * 0.5) -- forward, halfway: 8 px up
		expect.near(idle.Position.Y.Offset, 20 - 8, 1)
		UiIdle.step(lv.periodS * 1.25) -- the next period runs back: a quarter back from the top = 12 px up
		expect.near(idle.Position.Y.Offset, 20 - 12, 1)
		expect.near(idle.Size.X.Offset, 100 * (1 + (0.94 - 1) * 0.75), 1) -- sx .94 at the top (H:51)
		done(gui2)
	end)

	t.test("addGradientWindow: the visible window of a longer gradient slides along it (sdLvGrad H:519)", function()
		local stops = {
			{ pos = 0, color = Color3.fromHex("#FFFBD0") },
			{ pos = 0.5, color = Color3.fromHex("#FF9CC2") },
			{ pos = 1, color = Color3.fromHex("#9AF5D2") },
		}
		-- Pure: half of the gradient seen from its start ends at the middle stop; from 0.5 it starts there.
		local function same(a: Color3, b: Color3): boolean
			return math.abs(a.R - b.R) < 1e-3 and math.abs(a.G - b.G) < 1e-3 and math.abs(a.B - b.B) < 1e-3
		end
		local first = UiIdle.gradientWindow(stops, 0, 0.5)
		expect.truthy(same(first.Keypoints[1].Value, stops[1].color))
		expect.truthy(same(first.Keypoints[#first.Keypoints].Value, stops[2].color))
		local second = UiIdle.gradientWindow(stops, 0.5, 0.5)
		expect.truthy(same(second.Keypoints[1].Value, stops[2].color))
		expect.truthy(same(second.Keypoints[#second.Keypoints].Value, stops[3].color))
		if systemReduced then
			return
		end
		local gui, holder = stage()
		local gradient = Instance.new("UIGradient")
		gradient.Parent = holder
		UiIdle.addGradientWindow(gradient, stops, { periodS = 2.4, curve = "linear", windowShare = 0.5 })
		UiIdle.step(0)
		expect.truthy(same(gradient.Color.Keypoints[1].Value, stops[1].color))
		UiIdle.step(2.4 * 0.999) -- the end of the period: the window at the gradient's end
		local points = gradient.Color.Keypoints
		local last = points[#points].Value
		expect.near(last.G, stops[3].color.G, 0.02)
		done(gui)
	end)

	t.test("an entry ends with its object", function()
		local gui, holder = stage()
		UiIdle.add(holder, "twinkle")
		expect.equal(UiIdle.count(), 1)
		holder:Destroy()
		if UiIdle.count() ~= 0 then
			task.wait() -- Destroying may run deferred
		end
		expect.equal(UiIdle.count(), 0)
		done(gui)
	end)

	t.test("Theme.rays spins its picture through UiIdle, centred at its centreY (P4)", function()
		if AssetTable.image("img.fx.rays") == nil then
			return -- no picture, no rays (Theme_Test covers it)
		end
		UiIdle.clear()
		UiIdle.setScheduler(Scheduler.new(false))
		local gui = Instance.new("ScreenGui")
		local plate = Instance.new("Frame")
		plate.Parent = gui
		local rays = Theme.rays(plate, "img.fx.rays", 200, 0.5, 18, 0.55)
		expect.truthy(rays ~= nil)
		expect.equal((rays :: ImageLabel).Position, UDim2.fromScale(0.5, 0.55))
		expect.equal(UiIdle.count(), 1)
		UiIdle.step(0)
		expect.near((rays :: ImageLabel).Rotation, 0, 1e-4)
		if moving() then
			UiIdle.step(4.5)
			expect.near((rays :: ImageLabel).Rotation, 90, 1e-3)
		end
		done(gui)
	end)
end
