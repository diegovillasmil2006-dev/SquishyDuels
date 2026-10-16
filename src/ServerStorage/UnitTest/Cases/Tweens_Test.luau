--!strict
-- Tweens_Test: the UI FINAL R2 motion of StarterPlayerScripts.Client.Anim.Tweens (plan work/ui/PLAN.md §0 easing
-- rule, §2 one-shot keyframes; `H:n` = "Squishy Duels HUD.dc.html" line n). Server only (ServerStorage.UnitTest), Edit
-- mode: holders are built unparented and destroyed; the keyframe effects are stepped by hand, never added to the
-- Scheduler.
-- Contract:
--   * bezier(x1, y1, x2, y2) is the CSS cubic-bezier: 0 at 0, 1 at 1, ease-in-out .5 at .5, and the design's
--     overshoot curves peak where the plan measured them (±.002); curve(name) is the Config.UI.curves entry;
--   * poseAt(frames, u, curve?, wholeRun?): the property groups (x / y / sx / sy / scale / rot one transform, alpha,
--     color) each interpolate only between the frames that name them (a frame naming any transform field sets the
--     others to identity; a group missing at 0 or 1 starts or ends at rest), each segment eased by `curve`; with
--     `wholeRun` the run is eased first and the segments are linear; fields no frame names are left out;
--   * keyframes(holder, frames, opts): the first frame at once (CSS fill "both"), then the track over opts.ms after
--     opts.delayMs, ending exactly on the last frame; Position and Rotation stay the holder's own plus the pose (a
--     caller's move in between is kept), the scale is its SD_Pose UIScale, sx / sy its Size about its AnchorPoint (a
--     TextLabel takes √(sx·sy) on SD_Pose instead), alpha its own transparency from the value it had;
--   * under ReducedMotion nothing moves (the holder rests) and only the fades are left, each at most
--     Config.UI.motion.reducedMotionMaxFadeMs (a toast still shows for its life);
--   * fadeGroup(holder) fades every transparency of the holder and its descendants and restores them;
--   * finish() jumps to the last frame; cancel() stops writing.

type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local GuiService = game:GetService("GuiService")

local LINEAR = { ms = 400, curve = "linear" }

return function(t: Context)
	local expect = t.expect
	local Tweens = t.requireClient("Anim/Tweens")
	local UiPrefs = t.requireClient("UI/UiPrefs")
	local Config = t.requireShared("Config")
	local MAX_FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
	-- Roblox's own Reduced Motion setting on this PC can't be turned off from a test: the motion cases then check the
	-- reduced path only.
	local systemReduced = GuiService.ReducedMotionEnabled

	-- Runs `fn` with the in-game Reduce motion switch at `on`, always switching it back.
	local function withReduced(on: boolean, fn: () -> ())
		UiPrefs.set("reduceMotion", on)
		local ok, err = pcall(function(): any
			fn()
			return nil
		end)
		UiPrefs.set("reduceMotion", false)
		if not ok then
			error(err, 0)
		end
	end

	t.test("bezier: the CSS curves at their fixed points and the design's overshoot peaks (plan R2 Tests)", function()
		local easeInOut = Tweens.bezier(0.42, 0, 0.58, 1)
		expect.near(easeInOut(0), 0, 1e-9)
		expect.near(easeInOut(1), 1, 1e-9)
		expect.near(easeInOut(0.5), 0.5, 1e-6)
		expect.near(Tweens.bezier(0, 0, 1, 1)(0.3), 0.3, 1e-6) -- linear
		expect.near(Tweens.bezier(0.25, 0.1, 0.25, 1)(0.5), 0.8024, 1e-3) -- CSS ease at its middle
		expect.near(Tweens.bezier(0.5, 0, 0.75, 0)(0.5), 0.0659, 1e-3) -- the close (H:686)
		expect.equal(Tweens.bezier(0.2, 1.3, 0.4, 1)(-1), 0) -- clamped below 0 and NaN
		expect.equal(Tweens.bezier(0.2, 1.3, 0.4, 1)(0 / 0), 0)
		expect.equal(Tweens.bezier(0.2, 1.3, 0.4, 1)(2), 1)
		local peaks = {
			{ c = { 0.3, 1.9, 0.45, 1 }, peak = 1.2130 }, -- hover H:635
			{ c = { 0.3, 1.8, 0.5, 1 }, peak = 1.1772 }, -- switch H:197
			{ c = { 0.2, 1.6, 0.4, 1 }, peak = 1.1102 }, -- slot H:141
			{ c = { 0.2, 1.5, 0.4, 1 }, peak = 1.0800 }, -- stars H:515
			{ c = { 0.2, 1.4, 0.4, 1 }, peak = 1.0529 }, -- search H:136
			{ c = { 0.2, 1.35, 0.4, 1 }, peak = 1.0408 }, -- windows H:181
			{ c = { 0.2, 1.3, 0.4, 1 }, peak = 1.0299 }, -- rise H:203
			{ c = { 0.3, 1.5, 0.5, 1 }, peak = 1.0800 }, -- bars H:85
			{ c = { 0.2, 1.2, 0.4, 1 }, peak = 1.0125 }, -- coin flip H:571
		}
		for _, case in peaks do
			local c = case.c
			local curve = Tweens.bezier(c[1], c[2], c[3], c[4])
			local peak = 0
			for i = 0, 2000 do
				peak = math.max(peak, curve(i / 2000))
			end
			expect.near(peak, case.peak, 0.002)
		end
		-- curve(name): the Config.UI.curves entry (cached); a function passes through; an unknown name is linear.
		expect.near(Tweens.curve("hover")(0.5), Tweens.bezier(0.3, 1.9, 0.45, 1)(0.5), 1e-9)
		expect.equal(Tweens.curve("hover"), Tweens.curve("hover"))
		local own = function(u: number): number
			return u * u
		end
		expect.equal(Tweens.curve(own), own)
		expect.near(Tweens.curve("noSuchCurve")(0.25), 0.25, 1e-9)
	end)

	t.test(
		"poseAt: the design pop (H:25) through its frames; a frame naming the scale only puts the move at rest",
		function()
			local frames = Config.UI.motion.modalOpen.frames
			local first = Tweens.poseAt(frames, 0, "linear")
			expect.near(first.scale, 0.55, 1e-9)
			expect.near(first.y, 22, 1e-9) -- 40 px inside scale(.55) (H:25)
			local over = Tweens.poseAt(frames, 0.6, "linear")
			expect.near(over.scale, 1.035, 1e-9)
			expect.near(over.y, -4, 1e-9)
			-- 80% names only the scale: the move is at rest there (CSS: a transform list without translateY).
			local dip = Tweens.poseAt(frames, 0.8, "linear")
			expect.near(dip.scale, 0.99, 1e-9)
			expect.near(dip.y, 0, 1e-9)
			local last = Tweens.poseAt(frames, 1, "linear")
			expect.near(last.scale, 1, 1e-9)
			expect.near(last.y, 0, 1e-9)
			local half = Tweens.poseAt(frames, 0.3, "linear")
			expect.near(half.scale, (0.55 + 1.035) / 2, 1e-9)
			expect.near(half.y, 9, 1e-9)
			-- Clamped outside 0..1, and no field the frames never name.
			expect.near(Tweens.poseAt(frames, -1, "linear").scale, 0.55, 1e-9)
			expect.near(Tweens.poseAt(frames, 2, "linear").scale, 1, 1e-9)
			expect.equal(first.x, nil)
			expect.equal(first.rot, nil)
			expect.equal(first.alpha, nil)
			expect.equal(first.sx, nil)
		end
	)

	t.test("poseAt: each group between its own frames (sdLvSuck H:54, sdLvBubble H:64, G2.1)", function()
		-- sdLvSuck: alpha at 0 / 30 / 100%, the transform at 0 / 100% only: at 30% x is the 0 -> 100% interpolation.
		local suck: { any } = {
			{ at = 0, alpha = 0, x = 250, scale = 1.4 },
			{ at = 0.3, alpha = 1 },
			{ at = 1, alpha = 0, x = 30, scale = 0.4 },
		}
		local at30 = Tweens.poseAt(suck, 0.3, "linear")
		expect.near(at30.alpha, 1, 1e-9)
		expect.near(at30.x, 250 + (30 - 250) * 0.3, 1e-9) -- not at rest (0), as the R2 draft of 2026-10-14 had it
		expect.near(at30.scale, 1.4 + (0.4 - 1.4) * 0.3, 1e-9)
		-- sdLvBubble: at 15% (alpha only) y lies between its own 0% and 100% frames, not snapped to rest.
		local bubble = Config.UI.motion.loops.lvBubble.frames
		local at15 = Tweens.poseAt(bubble, 0.15, "linear")
		expect.near(at15.alpha, 0.9, 1e-9)
		expect.near(at15.y, -1.15 * 0.15, 1e-9)
		expect.near(at15.scale, 0.6 + (1.15 - 0.6) * 0.15, 1e-9)
		-- A group with no frame at 1 ends at rest (CSS: the element's own value).
		local up: { any } = { { at = 0, y = 30, alpha = 0 }, { at = 1 } }
		local mid = Tweens.poseAt(up, 0.5, "linear")
		expect.near(mid.y, 15, 1e-9)
		expect.near(mid.alpha, 0.5, 1e-9)
		-- Colour interpolates between the frames that name it (the coin number, H:574).
		local white, yellow = Color3.new(1, 1, 1), Color3.new(1, 1, 0)
		local tint = Tweens.poseAt({ { at = 0, color = yellow }, { at = 1, color = white } } :: { any }, 0.5, "linear")
		expect.near((tint.color :: Color3).B, 0.5, 1e-6)
	end)

	t.test("poseAt eases each segment by its curve; wholeRun eases the run with linear segments", function()
		local frames: { any } = { { at = 0, scale = 0.5 }, { at = 0.5, scale = 1.5 }, { at = 1, scale = 1 } }
		local easeOut = Tweens.curve("easeOut")
		local pose = Tweens.poseAt(frames, 0.25, "easeOut")
		expect.near(pose.scale, 0.5 + 1 * easeOut(0.5), 1e-6)
		local back = Tweens.poseAt(frames, 0.75, "easeOut")
		expect.near(back.scale, 1.5 - 0.5 * easeOut(0.5), 1e-6)
		-- Web Animations: the whole run eased first (u -> easeOut(u)), then the keyframes linear.
		local e = easeOut(0.25)
		local whole = Tweens.poseAt(frames, 0.25, nil, "easeOut")
		expect.near(whole.scale, 0.5 + 1 * (e / 0.5), 1e-6)
	end)

	t.test("keyframes: the from-pose at once, the delay held, the track, the last frame exactly", function()
		if systemReduced then
			return -- the reduced case below covers this PC
		end
		withReduced(false, function()
			local holder = Instance.new("Frame")
			holder.Position = UDim2.fromOffset(10, 20)
			holder.BackgroundTransparency = 0.2
			-- An sdUp (H:44): 30 px lower and clear -> in place and as it was.
			local frames: { any } = { { at = 0, y = 30, alpha = 0 }, { at = 1 } }
			local effect = Tweens.keyframes(holder, frames, { ms = 400, delayMs = 100, curve = "linear" })
			expect.equal(holder.Position, UDim2.fromOffset(10, 50))
			expect.near(holder.BackgroundTransparency, 1, 1e-4)
			expect.equal(effect:step(0.05, 0), true) -- inside the delay: the from-pose holds
			expect.equal(holder.Position, UDim2.fromOffset(10, 50))
			expect.equal(effect:step(0.25, 0), true) -- 200 ms into the 400 ms track
			expect.equal(holder.Position.Y.Offset, 35)
			expect.near(holder.BackgroundTransparency, 0.2 + 0.8 * 0.5, 1e-4)
			-- The caller moves the holder (a re-fit): the pose stays on top of the new place.
			holder.Position = UDim2.fromOffset(10, 115)
			expect.equal(effect:step(0.3, 0), false) -- past the end: the last frame, then done
			expect.equal(holder.Position, UDim2.fromOffset(10, 100))
			expect.near(holder.BackgroundTransparency, 0.2, 1e-4)
			expect.equal(effect:step(0.1, 0), false)
			holder:Destroy()
		end)
	end)

	t.test("keyframes: scale on SD_Pose, rotation added, alpha per kind of object, sx / sy as Size (G2.2)", function()
		if systemReduced then
			return
		end
		withReduced(false, function()
			local label = Instance.new("TextLabel")
			label.Rotation = 5
			label.TextTransparency = 0
			local frames: { any } = { { at = 0, scale = 0.3, rot = -30, alpha = 0 }, { at = 1 } }
			local effect = Tweens.keyframes(label, frames, LINEAR)
			local found = label:FindFirstChild("SD_Pose")
			expect.truthy(found ~= nil and found:IsA("UIScale"))
			local scale = found :: UIScale
			expect.near(scale.Scale, 0.3, 1e-4)
			expect.near(label.Rotation, -25, 1e-4)
			expect.near(label.TextTransparency, 1, 1e-4)
			effect:step(0.2, 0)
			expect.near(scale.Scale, 0.65, 1e-4)
			expect.near(label.Rotation, -10, 1e-4)
			expect.near(label.TextTransparency, 0.5, 1e-4)
			effect:finish()
			expect.near(scale.Scale, 1, 1e-4)
			expect.near(label.Rotation, 5, 1e-4)
			expect.near(label.TextTransparency, 0, 1e-4)
			label:Destroy()

			-- sx / sy on a frame (sdSlam H:45): its Size times them about its AnchorPoint; back to its own at the end.
			local holder = Instance.new("Frame")
			holder.AnchorPoint = Vector2.new(0.5, 1)
			holder.Size = UDim2.fromOffset(100, 80)
			local squash = Tweens.keyframes(holder, { { at = 0, sx = 0.9, sy = 1.15 }, { at = 1 } } :: { any }, LINEAR)
			expect.equal(holder.Size, UDim2.fromOffset(90, 92))
			expect.equal(holder:FindFirstChild("SD_Pose"), nil) -- no uniform scale named
			squash:finish()
			expect.equal(holder.Size, UDim2.fromOffset(100, 80))
			holder:Destroy()

			-- A TextLabel cannot squash out of shape: it takes the uniform part √(sx·sy) on SD_Pose (plan §1.4).
			local text = Instance.new("TextLabel")
			text.Size = UDim2.fromOffset(50, 20)
			Tweens.keyframes(text, { { at = 0, sx = 1.32, sy = 0.66 }, { at = 1 } } :: { any }, LINEAR)
			expect.equal(text.Size, UDim2.fromOffset(50, 20))
			expect.near((text:FindFirstChild("SD_Pose") :: UIScale).Scale, math.sqrt(1.32 * 0.66), 1e-4)
			text:Destroy()

			local image = Instance.new("ImageLabel")
			image.ImageTransparency = 0.4
			Tweens.keyframes(image, { { at = 0, alpha = 0 }, { at = 1 } } :: { any }, LINEAR)
			expect.near(image.ImageTransparency, 1, 1e-4)
			image:Destroy()

			-- A frame fades its background and its outline (a ring, a confetti piece).
			local ring = Instance.new("Frame")
			ring.BackgroundTransparency = 1
			local stroke = Instance.new("UIStroke")
			stroke.Parent = ring
			local fade = Tweens.keyframes(ring, { { at = 0, alpha = 1 }, { at = 1, alpha = 0 } } :: { any }, LINEAR)
			fade:step(0.2, 0)
			expect.near(stroke.Transparency, 0.5, 1e-4)
			expect.near(ring.BackgroundTransparency, 1, 1e-4) -- clear stays clear
			fade:cancel()
			expect.equal(fade:step(0.2, 0), false)
			expect.near(stroke.Transparency, 0.5, 1e-4) -- cancel stops writing where it is
			ring:Destroy()
		end)
	end)

	t.test("keyframes under ReducedMotion: at rest at once and only the fade, at most the capped time (PR9)", function()
		withReduced(true, function()
			local holder = Instance.new("TextLabel")
			holder.Position = UDim2.fromOffset(0, 0)
			holder.TextTransparency = 0
			local frames: { any } = { { at = 0, y = 30, scale = 0.5, rot = 20, alpha = 0 }, { at = 1 } }
			local effect = Tweens.keyframes(holder, frames, { ms = 600, delayMs = 50 })
			-- Moves, scales and turns are at rest at once; the text starts clear.
			expect.equal(holder.Position, UDim2.fromOffset(0, 0))
			expect.near(holder.Rotation, 0, 1e-4)
			local scale = holder:FindFirstChild("SD_Pose")
			expect.truthy(scale == nil or (scale :: UIScale).Scale == 1)
			expect.near(holder.TextTransparency, 1, 1e-4)
			expect.equal(effect:step(0.05, 0), true) -- the delay
			expect.near(holder.TextTransparency, 1, 1e-4)
			expect.equal(effect:step(MAX_FADE_MS / 2000, 0), true)
			expect.near(holder.TextTransparency, 0.5, 1e-3)
			expect.equal(effect:step(MAX_FADE_MS / 2000 + 0.001, 0), false) -- done within the capped fade
			expect.near(holder.TextTransparency, 0, 1e-4)
			holder:Destroy()

			-- A track without a fade has nothing left to play: done at once, at rest.
			local pop = Instance.new("Frame")
			local popEffect = Tweens.keyframes(pop, Config.UI.motion.modalOpen.frames, { ms = 500 })
			expect.equal(popEffect:step(0, 0), false)
			local popScale = pop:FindFirstChild("SD_Pose")
			expect.truthy(popScale == nil or (popScale :: UIScale).Scale == 1)
			expect.equal(pop.Position, UDim2.new())
			pop:Destroy()
		end)
	end)

	t.test("keyframes under ReducedMotion: a toast fades in, shows and fades out; an exit stays at rest", function()
		withReduced(true, function()
			local toast = Config.UI.motion.toast
			local life, fade = toast.lifeMs / 1000, MAX_FADE_MS / 1000
			local label = Instance.new("TextLabel")
			label.Position = UDim2.fromOffset(5, 6)
			label.TextTransparency = 0
			local effect = Tweens.keyframes(label, toast.frames, { ms = toast.lifeMs, curve = toast.curve })
			expect.near(label.TextTransparency, 1, 1e-4) -- clear at first (H:33's 0%)
			expect.equal(effect:step(fade, 0), true)
			expect.near(label.TextTransparency, 0, 1e-4) -- in within the capped fade
			expect.equal(effect:step(life / 2 - fade, 0), true)
			expect.near(label.TextTransparency, 0, 1e-4) -- shown at half its life
			expect.equal(effect:step(life / 2 - fade / 2, 0), true)
			expect.near(label.TextTransparency, 0.5, 1e-3) -- halfway out over the last capped fade
			expect.equal(effect:step(fade / 2 + 0.001, 0), false)
			expect.near(label.TextTransparency, 1, 1e-4) -- clear at the end
			-- Never moved, scaled or turned.
			expect.equal(label.Position, UDim2.fromOffset(5, 6))
			expect.near(label.Rotation, 0, 1e-4)
			local scale = label:FindFirstChild("SD_Pose")
			expect.truthy(scale == nil or (scale :: UIScale).Scale == 1)
			label:Destroy()

			-- The window close (no fade): done at once and at rest, not shrunk and lower (the caller hides it).
			local panel = Instance.new("Frame")
			local close = Tweens.keyframes(panel, Config.UI.motion.modalClose.frames, { ms = 190 })
			expect.equal(close:step(0, 0), false)
			expect.equal(panel.Position, UDim2.new())
			local closeScale = panel:FindFirstChild("SD_Pose")
			expect.truthy(closeScale == nil or (closeScale :: UIScale).Scale == 1)
			close:finish()
			expect.equal(panel.Position, UDim2.new())
			panel:Destroy()
		end)
	end)

	t.test("fadeGroup: every transparency of the element times the group alpha, then back (G4.1, G9.22)", function()
		local card = Instance.new("Frame")
		card.BackgroundTransparency = 0.2
		local stroke = Instance.new("UIStroke")
		stroke.Transparency = 0
		stroke.Parent = card
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.TextTransparency = 0
		text.Parent = card
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.ImageTransparency = 0.4
		image.Parent = card
		local group = Tweens.fadeGroup(card)
		group:setAlpha(0.5)
		expect.near(card.BackgroundTransparency, 1 - 0.8 * 0.5, 1e-4)
		expect.near(stroke.Transparency, 0.5, 1e-4)
		expect.near(text.TextTransparency, 0.5, 1e-4)
		expect.near(text.BackgroundTransparency, 1, 1e-4) -- clear stays clear
		expect.near(image.ImageTransparency, 1 - 0.6 * 0.5, 1e-4)
		group:setAlpha(0)
		expect.near(text.TextTransparency, 1, 1e-4)
		group:restore()
		expect.near(card.BackgroundTransparency, 0.2, 1e-4)
		expect.near(image.ImageTransparency, 0.4, 1e-4)
		expect.near(text.TextTransparency, 0, 1e-4)
		card:Destroy()
	end)

	t.test("the motion tracks in Config.UI.motion run from 0 to 1 in order and end at rest", function()
		local motion = Config.UI.motion :: any
		for _, name in { "modalOpen", "modalClose", "cardIn", "toast" } do
			local frames = motion[name].frames
			expect.truthy(type(frames) == "table" and #frames >= 2)
			expect.equal(frames[1].at, 0)
			expect.equal(frames[#frames].at, 1)
			for index = 2, #frames do
				expect.truthy(frames[index].at > frames[index - 1].at)
			end
		end
		-- The entrances end at rest (the window, a card, a toast's middle); the close ends shrunk and lower (H:687).
		for _, name in { "modalOpen", "cardIn" } do
			local last = Tweens.poseAt(motion[name].frames, 1)
			for field, rest in { x = 0, y = 0, scale = 1, rot = 0, alpha = 1 } do
				local value = (last :: any)[field]
				expect.truthy(value == nil or math.abs(value - rest) < 1e-9)
			end
		end
		local shown = Tweens.poseAt(motion.toast.frames, 0.5)
		expect.near(shown.y, 0, 1e-9) -- H:33: 16% .. 86% at rest
		expect.near(shown.scale, 1, 1e-9)
		local close = Tweens.poseAt(motion.modalClose.frames, 1)
		expect.near(close.scale, motion.modalClose.scaleTo, 1e-9)
		expect.near(close.y, 20, 1e-9) -- 24 px inside scale(.82) (H:687)
	end)
end
