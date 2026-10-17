--!strict
-- ViewmodelMath_Test: unit tests for StarterPlayerScripts.Client.Anim.ViewmodelMath (first-person spec 2026-10-10
-- §3.2, §3.3, §6). Server only (ServerStorage.UnitTest). Builds the 14 Catalog toys in "Viewport" mode (unparented).
-- The 3D Lab FP viewmodel (spec 2026-10-11 §3; each value from Config.FirstPerson, its design line):
--   * spring: the design's semi-implicit Euler in substeps <= 1/240 s (one frame worked by hand), stable on a long
--     frame, every Config spring settles; ease (cosine in-out) and backOut (c = 1.9: 0, 1.1125 at 0.5, peak 1.1208);
--   * toyBox: the box round every part but the Root (SD_Body does not narrow it; an "E" part by its ellipsoid), the
--     body (SD_HalfExtents) fitting in it for all 14 toys;
--   * sides: toy ± (hw + 0.05), -0.035, +0.035 (a 0.18-du toy puts the hands on fp.js:144's RH0 / LH0); palms: each
--     palm at the shown side + 0.05 minus 0.94 of that side's narrowing (S.X / k), y -0.02, z +0.03, rolls ±(0.4 +
--     0.3c), the tremor ±0.0008c at 53 / 49 rad/s (toy ×0.6 at 47) after 0.3 s and never under ReducedMotion;
--   * overlayCamera: the inverse of the overlay's idle offset and kick (fp.js:660); toyFrame turns our -Z-facing toys
--     like the design's; scaledFrame shows a uniform scale as a move along each ray from the eye;
--   * overlayLight (§3.1's closest option), shakeFor (the design's shake curve is CameraController's), screenPoint;
--   * touchPadRect (over the toy, clear of the touch controls) and releasePoint (the own projectile's start);
--   * inspectButtonRect (final polish 2026-10-11): the touch Inspect button at the bottom middle, never in the
--     thumbstick zone nor on Throw, Ultimate, Dash or Jump, always on screen;
--   * throttle (phone speed fix 2026-10-16): at a 1/30 s interval, 60 Hz frames step every 2nd frame, 45 Hz frames 2 of
--     every 3, 30 Hz and slower every frame; no interval steps every frame; stepInterval: 1 / hz, 0 (off) for 0, below
--     0 or not a number, so lowTier.stepHz = 0 never freezes the hands; Config.FirstPerson.lowTier is 30 Hz (0 or
--     15..60 allowed) with half the throw specks (speckShare 0.5, batch B 2026-10-17).

-- Shape of the context RunUnitTest passes in (restated: Luau has no type-only imports).
type Context = {
	test: (name: string, fn: () -> ()) -> (),
	expect: any,
	requireShared: (path: string) -> any,
	requireClient: (path: string) -> any,
}

local EPS = 1e-3 -- studs (Vector3 and CFrame are float32)

return function(t: Context)
	local ViewmodelMath = t.requireClient("Anim/ViewmodelMath")
	local Builder = t.requireShared("Art/SquishyBuilder")
	local Catalog = t.requireShared("Catalog")
	local Config = t.requireShared("Config")
	local expect = t.expect
	local FP = Config.FirstPerson
	local U = FP.overlayStudsPerDu

	local function failIfAny(problems: { string })
		if #problems > 0 then
			error(`{#problems} problem(s):\n` .. table.concat(problems, "\n", 1, math.min(#problems, 12)))
		end
	end

	-- Lane V (spec 2026-10-11 §3): the 3D Lab FP viewmodel's maths, the touch pad and the release point ---------------

	local ControlsController = t.requireClient("Controllers/ControlsController")

	t.test("spring: the design's semi-implicit Euler in substeps of at most 1/240 s", function()
		-- One 1/60-s frame of the hand spring (520, 40) from rest toward 1 is 4 substeps of 1/240 s (fp.js:16-18),
		-- worked by hand: v += ((1 - p)·520 - v·40)/240; p += v/240.
		local p, v = ViewmodelMath.spring(0, 0, 1, FP.springs.hand, 1 / 60)
		expect.near(p, 0.075382, 1e-5)
		expect.near(v, 6.567048, 1e-4)
		-- Vector3: the same on each axis.
		local pv, vv = ViewmodelMath.spring(Vector3.zero, Vector3.zero, Vector3.new(1, -1, 2), FP.springs.hand, 1 / 60)
		expect.truthy((pv - Vector3.new(0.075382, -0.075382, 0.150764)).Magnitude < 1e-4)
		expect.truthy((vv - Vector3.new(6.567048, -6.567048, 13.134096)).Magnitude < 1e-3)
		-- dt 0 changes nothing; a long frame stays stable (it is cut into substeps), and every spring settles in 3 s.
		local p0, v0 = ViewmodelMath.spring(0.3, 2, 1, FP.springs.hand, 0)
		expect.equal(p0, 0.3)
		expect.equal(v0, 2)
		for name, row in FP.springs do
			local x, xv = 0, 0
			x, xv = ViewmodelMath.spring(x, xv, 1, row, 0.5)
			for _ = 1, 150 do
				x, xv = ViewmodelMath.spring(x, xv, 1, row, 1 / 60)
			end
			if math.abs(x - 1) > 1e-3 or math.abs(xv) > 1e-2 then
				error(`spring {name} did not settle: {x}, {xv}`)
			end
		end
	end)

	t.test("ease and backOut: the design's cosine in-out and its pop-in overshoot (c = 1.9)", function()
		expect.near(ViewmodelMath.ease(0), 0, 1e-12)
		expect.near(ViewmodelMath.ease(0.25), 0.5 - 0.5 * math.cos(math.pi / 4), 1e-12)
		expect.near(ViewmodelMath.ease(0.5), 0.5, 1e-12)
		expect.near(ViewmodelMath.ease(1), 1, 1e-12)
		expect.near(ViewmodelMath.ease(-1), 0, 1e-12)
		expect.near(ViewmodelMath.ease(2), 1, 1e-12)
		expect.equal(FP.equip.backOutC, 1.9)
		expect.near(ViewmodelMath.backOut(0), 0, 1e-12)
		expect.near(ViewmodelMath.backOut(0.5), 1.1125, 1e-9)
		expect.near(ViewmodelMath.backOut(1), 1, 1e-12)
		-- The peak: 1.1208 at u = 1 - 2c / (3(c + 1)) = 0.5632.
		expect.near(ViewmodelMath.backOut(1 - 3.8 / 8.7), 1.120831, 1e-5)
		for i = 0, 20 do
			expect.truthy(ViewmodelMath.backOut(i / 20) <= 1.120832)
		end
	end)

	t.test("toyBox: the box round every part but the Root, in pivot space; the body fits in it", function()
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.one * 5 -- never counted
		root.Parent = model
		model.PrimaryPart = root
		local a = Instance.new("Part")
		a.Size = Vector3.new(2, 2, 2)
		a.CFrame = CFrame.new(3, 0, 0)
		a.Parent = model
		local b = Instance.new("Part")
		b.Size = Vector3.new(2, 4, 2)
		b.CFrame = CFrame.new(-1, 1, 0)
		b:SetAttribute("SD_Body", true) -- the body mark does not narrow the toy's box
		b.Parent = model
		local centre, size = ViewmodelMath.toyBox(model)
		expect.truthy((centre - Vector3.new(1, 1, 0)).Magnitude < 1e-4)
		expect.truthy((size - Vector3.new(6, 4, 2)).Magnitude < 1e-4)
		model:Destroy()
		-- The 14 toys: the body (2 · SD_HalfExtents, the SD_Body box) fits in the toy's box on every axis.
		for _, def in Catalog.list() do
			local built = Builder.build(def.blueprintId, "Viewport", 1)
			local _, s = ViewmodelMath.toyBox(built)
			local half = built:GetAttribute("SD_HalfExtents") :: Vector3
			built:Destroy()
			if s.X < 2 * half.X - EPS or s.Y < 2 * half.Y - EPS or s.Z < 2 * half.Z - EPS then
				error(`{def.id}: the body {2 * half} is bigger than the toy's box {s}`)
			end
		end
	end)

	t.test("sides: the hands at the toy's sides; a toy 0.18 du wide puts them on the design's RH0 / LH0", function()
		local hold = FP.held.pos
		local left, right = ViewmodelMath.sides(hold, 0.08)
		expect.truthy((left - Vector3.new(-0.13, -0.165, -0.465)).Magnitude < 1e-6)
		expect.truthy((right - Vector3.new(0.13, -0.165, -0.465)).Magnitude < 1e-6)
		-- fp.js:144's hands at the press, RH0 (0.14, -0.165, -0.465) and LH0, are these sides for hw = 0.09.
		left, right = ViewmodelMath.sides(hold, 0.09)
		expect.truthy((left - Vector3.new(-0.14, -0.165, -0.465)).Magnitude < 1e-6)
		expect.truthy((right - Vector3.new(0.14, -0.165, -0.465)).Magnitude < 1e-6)
	end)

	t.test(
		"palms: both palms on the shown sides, rolled by the press; the tremor after 0.3 s, never reduced",
		function()
			local focus = FP.focus.pos
			-- Half width 0.08 du, the rig's S.X 0.8 at k 1: each side moved in 0.016 du; the palms go 0.94 of it.
			local l, r, lRoll, rRoll, dx =
				ViewmodelMath.palms(focus, 0.08, Vector3.new(0.8, 1.2, 1.2), 1, 0.5, 0.1, 3, false)
			local g = 0.08 + 0.05 - 0.94 * 0.016
			expect.truthy((l - (focus + Vector3.new(-g, -0.02, 0.03))).Magnitude < 1e-6)
			expect.truthy((r - (focus + Vector3.new(g, -0.02, 0.03))).Magnitude < 1e-6)
			expect.near(lRoll, 0.4 + 0.3 * 0.5, 1e-9)
			expect.near(rRoll, -(0.4 + 0.3 * 0.5), 1e-9)
			expect.equal(dx, 0) -- no tremor before 0.3 s
			-- The uniform part k is not a squeeze: S = 0.4, 0.6 at k 0.5 is the same narrowing.
			local l2 = ViewmodelMath.palms(focus, 0.08, Vector3.new(0.4, 0.6, 0.6), 0.5, 0.5, 0.1, 3, false)
			expect.truthy((l2 - l).Magnitude < 1e-6)
			-- A widened X (the release jiggle) never pulls the palms out past the toy's side gap.
			local wide = ViewmodelMath.palms(focus, 0.08, Vector3.new(1.1, 1, 1), 1, 0.1, 0.1, 3, false)
			expect.near(wide.X, focus.X - 0.13, 1e-6)
			-- After 0.3 s: ±0.0008·c at 53 and 49 rad/s on the hands, ×0.6 at 47 rad/s on the toy.
			local now = 1.7
			local tl, tr, _, _, tdx =
				ViewmodelMath.palms(focus, 0.08, Vector3.new(0.8, 1.2, 1.2), 1, 0.5, 0.4, now, false)
			local amp = 0.0008 * 0.5
			expect.near(tl.X, focus.X - g + math.sin(now * 53) * amp, 1e-7)
			expect.near(tr.X, focus.X + g - math.sin(now * 49) * amp, 1e-7)
			expect.near(tdx, math.sin(now * 47) * amp * 0.6, 1e-9)
			-- ReducedMotion: no tremor.
			local _, _, _, _, rdx = ViewmodelMath.palms(focus, 0.08, Vector3.new(0.8, 1.2, 1.2), 1, 0.5, 0.4, now, true)
			expect.equal(rdx, 0)
		end
	)

	t.test("overlayCamera: the whole overlay's idle and kick, as the inverse on the overlay camera", function()
		expect.truthy(ViewmodelMath.overlayCamera(0, 0, U):FuzzyEq(CFrame.identity, 1e-6))
		local now, kick = 1.3, -0.4
		local offset = Vector3.new(0.002 * math.sin(0.9 * now), 0.003 * math.sin(1.7 * now) + 0.01 * kick, 0) * U
		local scene = CFrame.new(offset) * CFrame.Angles(0.02 * kick, 0, 0)
		local camera = ViewmodelMath.overlayCamera(now, kick, U)
		expect.truthy((camera * scene):FuzzyEq(CFrame.identity, 1e-6))
		-- A point of the overlay seen through it is where the design's moved scene shows it.
		local p = Vector3.new(0.13, -0.165, -0.465) * U
		expect.truthy((camera:PointToObjectSpace(p) - scene:PointToWorldSpace(p)).Magnitude < 1e-5)
	end)

	t.test(
		"toyFrame turns our -Z-facing toys like the design's +Z ones; scaledFrame shows a scale by distance",
		function()
			local frame = ViewmodelMath.toyFrame(FP.held.pos, FP.held.rot, U)
			expect.truthy((frame.Position - FP.held.pos * U).Magnitude < 1e-5)
			-- The design's +Z (its face) is our toy's -Z, turned by the hold's yaw 0.25.
			local design = CFrame.Angles(FP.held.rot.X, FP.held.rot.Y, FP.held.rot.Z)
			expect.truthy((frame:VectorToWorldSpace(Vector3.new(0, 0, -1)) - design.ZVector).Magnitude < 1e-5)
			-- A uniform scale s about the frame's origin, seen from the eye: the same picture with the toy at full size
			-- moved along each ray (perspective is all the scale there is).
			local eye = Vector3.new(0.01, -0.02, 0)
			for _, s in { 0.0001, 0.3, 1, 1.12 } do
				local placed = ViewmodelMath.scaledFrame(frame, eye, s)
				for _, x in { Vector3.new(0.2, 0.1, -0.3), Vector3.new(-0.25, 0.3, 0.2), Vector3.zero } do
					local shown = frame.Position + frame:VectorToWorldSpace(x * s)
					local ours = placed:PointToWorldSpace(x)
					local a, b = (shown - eye).Unit, (ours - eye).Unit
					if a:Dot(b) < 1 - 1e-6 then
						error(`scale {s}: {x} is not on the same ray`)
					end
				end
			end
			expect.truthy(ViewmodelMath.scaledFrame(frame, eye, 1):FuzzyEq(frame, 1e-6))
		end
	)

	t.test(
		"overlayLight: the Ambient and light colour matched to the design shot, the design key's direction",
		function()
			local light = FP.light
			local ambient, colour, direction = ViewmodelMath.overlayLight()
			expect.equal(ambient, light.viewportAmbient)
			expect.equal(colour, light.viewportLight)
			-- Below white, so the skin is not clipped to pale yellow (Studio 2026-10-11).
			expect.truthy(colour.R < 1 and colour.G < 1 and colour.B < 1)
			expect.truthy((direction - -light.keyFrom.Unit).Magnitude < 1e-6)
		end
	)

	t.test("shakeFor: the design's shake value as CameraController.shake's amplitude and length", function()
		-- fp.js:652-655: rotation ±(random - 0.5)·shake²·0.03 rad, the value falling 1.4 a second. CameraController's
		-- a·(1 - t/dur)² is the same curve: (shake - 1.4t)² = shake²·(1 - t/dur)² with dur = shake / 1.4.
		for _, value in { 0.025, 0.12, 0.18 } do
			local amplitudeDeg, seconds = ViewmodelMath.shakeFor(value)
			expect.near(seconds, value / 1.4, 1e-9)
			for i = 0, 10 do
				local at = seconds * i / 10
				local design = 0.5 * 0.03 * math.max(0, value - 1.4 * at) ^ 2
				local ours = math.rad(amplitudeDeg) * (1 - at / seconds) ^ 2
				expect.near(ours, design, 1e-9)
			end
		end
		local zeroAmp, zeroSeconds = ViewmodelMath.shakeFor(0)
		expect.equal(zeroAmp, 0)
		expect.equal(zeroSeconds, 0)
	end)

	t.test("screenPoint: a camera-space point in pixels (vertical FOV); nil behind the camera", function()
		local screen = Vector2.new(1920, 1080)
		local centre = ViewmodelMath.screenPoint(Vector3.new(0, 0, -2), screen, 70) :: Vector2
		expect.truthy((centre - screen / 2).Magnitude < 1e-4)
		local focal = 540 / math.tan(math.rad(35))
		local p = ViewmodelMath.screenPoint(Vector3.new(0.3, -0.2, -0.5), screen, 70) :: Vector2
		expect.near(p.X, 960 + 0.6 * focal, 1e-3)
		expect.near(p.Y, 540 + 0.4 * focal, 1e-3)
		expect.equal(ViewmodelMath.screenPoint(Vector3.new(0, 0, 1), screen, 70), nil)
		-- The same pixels as screenBox's for a tiny box there.
		local box = ViewmodelMath.screenBox(CFrame.new(0.3, -0.2, -0.5), Vector3.one * 1e-4, screen, 70) :: any
		expect.near(box.x + box.w / 2, p.X, 1e-2)
		expect.near(box.y + box.h / 2, p.Y, 1e-2)
	end)

	t.test(
		"touchPadRect: over the toy, never on the thumbstick zone, Throw, Ultimate or Jump; empty when covered",
		function()
			local problems: { string } = {}
			local TOUCHING = 1e-6 -- a pad edge on a blocker's edge is clear (x + w rounds a hair past it)
			local function overlaps(a: any, b: any): boolean
				return a.x < b.x + b.w - TOUCHING
					and b.x < a.x + a.w - TOUCHING
					and a.y < b.y + b.h - TOUCHING
					and b.y < a.y + a.h - TOUCHING
			end
			local cases = {
				{ screen = Vector2.new(667, 375) },
				{ screen = Vector2.new(844 - 2 * 47, 390) }, -- a notch: 47-px side insets
				{ screen = Vector2.new(1280, 720) },
			}
			local rng = Random.new(11)
			local padded = 0
			for _, case in cases do
				local screen = case.screen
				for _, uiScale in { 0.85, 1.25 } do
					local layout = ControlsController.touchLayout(screen, uiScale, nil)
					local zone = {
						x = 0,
						y = screen.Y * (1 - Config.UI.Touch.thumbstickZoneHeight),
						w = screen.X * Config.UI.Touch.thumbstickZoneWidth,
						h = screen.Y * Config.UI.Touch.thumbstickZoneHeight,
					}
					local boxes = {
						{ x = screen.X * 0.42, y = screen.Y * 0.62, w = screen.X * 0.16, h = screen.Y * 0.3 }, -- the held toy
					}
					for _ = 1, 60 do
						local w, h = rng:NextNumber(20, screen.X * 0.5), rng:NextNumber(20, screen.Y * 0.5)
						table.insert(boxes, {
							x = rng:NextNumber(-w / 2, screen.X - w / 2),
							y = rng:NextNumber(-h / 2, screen.Y - h / 2),
							w = w,
							h = h,
						})
					end
					for _, box in boxes do
						local pad = ViewmodelMath.touchPadRect(box, screen, layout)
						if pad then
							padded += 1
							for name, blocker in
								{ zone = zone, throw = layout.throw, ultimate = layout.ultimate, jump = layout.jump }
							do
								if overlaps(pad, blocker) then
									table.insert(problems, `{screen} x{uiScale}: the pad overlaps {name}`)
								end
							end
							-- Inside the toy's box and on screen.
							if pad.x < box.x - 1e-6 or pad.y < box.y - 1e-6 or pad.x + pad.w > box.x + box.w + 1e-6 then
								table.insert(problems, `{screen} x{uiScale}: the pad leaves the toy's box`)
							end
							if
								pad.x < -1e-6
								or pad.y < -1e-6
								or pad.x + pad.w > screen.X + 1e-6
								or pad.y + pad.h > screen.Y + 1e-6
							then
								table.insert(problems, `{screen} x{uiScale}: the pad leaves the screen`)
							end
						end
					end
					-- The held toy's own box always leaves a pad; a box fully under the Throw button leaves none.
					expect.truthy(ViewmodelMath.touchPadRect(boxes[1], screen, layout) ~= nil)
					local throw = layout.throw
					expect.equal(
						ViewmodelMath.touchPadRect(
							{ x = throw.x + 2, y = throw.y + 2, w = throw.w - 4, h = throw.h - 4 },
							screen,
							layout
						),
						nil
					)
					expect.equal(ViewmodelMath.touchPadRect(nil, screen, layout), nil)
				end
			end
			expect.truthy(padded > 50)
			failIfAny(problems)
		end
	)

	t.test("inspectButtonRect: bottom middle, clear of the thumbstick zone and the touch buttons, on screen", function()
		local problems: { string } = {}
		local touch = Config.UI.Touch
		local function overlaps(a: any, b: any): boolean
			return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
		end
		local inset = touch.inspectButtonInset
		expect.truthy(type(inset) == "number" and inset >= 0)
		for _, screen in
			{ Vector2.new(667, 375), Vector2.new(844 - 2 * 47, 390), Vector2.new(1280, 720), Vector2.new(768, 1024) }
		do
			for _, uiScale in { 0.85, 1.25 } do
				local layout = ControlsController.touchLayout(screen, uiScale, nil)
				local size = Vector2.new(120, 52) * uiScale
				local rect = ViewmodelMath.inspectButtonRect(screen, size, inset * uiScale, layout)
				local label = `{screen} x{uiScale}`
				if
					rect.x < 0
					or rect.y < 0
					or rect.x + rect.w > screen.X + 1e-6
					or rect.y + rect.h > screen.Y + 1e-6
				then
					table.insert(problems, `{label}: off screen`)
				end
				local zone = {
					x = 0,
					y = screen.Y * (1 - touch.thumbstickZoneHeight),
					w = screen.X * touch.thumbstickZoneWidth,
					h = screen.Y * touch.thumbstickZoneHeight,
				}
				for name, blocker in
					{
						zone = zone,
						throw = layout.throw,
						ultimate = layout.ultimate,
						dash = layout.dash,
						jump = layout.jump,
					}
				do
					if overlaps(rect, blocker) then
						table.insert(problems, `{label}: the Inspect button overlaps {name}`)
					end
				end
			end
		end
		-- On a wide screen nothing is in the way: centred, `inset` above the bottom.
		local wide = ViewmodelMath.inspectButtonRect(Vector2.new(1920, 1080), Vector2.new(120, 52), 16, nil)
		expect.near(wide.x, 900)
		expect.near(wide.y, 1080 - 16 - 52)
		failIfAny(problems)
	end)

	t.test("releasePoint: on the camera ray through the overlay toy, as big as the held model; cut by cover", function()
		local camera = CFrame.lookAt(Vector3.new(10, 5, 3), Vector3.new(10, 5, -20))
		local toyCam = FP.held.pos * U -- the overlay toy in camera space (studs)
		local ratio = 0.47 -- overlay build scale ÷ held build scale
		local d0 = toyCam.Magnitude / ratio
		local point, factor = ViewmodelMath.releasePoint(camera, toyCam, ratio, nil)
		expect.near(factor, 1, 1e-9)
		expect.near((point - camera.Position).Magnitude, d0, 1e-3)
		expect.truthy(camera:VectorToObjectSpace((point - camera.Position).Unit):Dot(toyCam.Unit) > 1 - 1e-5)
		-- A wall 3 studs away along that ray: 0.5 in front of it, the size factor D / D0.
		local cut, cutFactor = ViewmodelMath.releasePoint(camera, toyCam, ratio, 3)
		expect.near((cut - camera.Position).Magnitude, 2.5, 1e-3)
		expect.near(cutFactor, 2.5 / d0, 1e-6)
		-- Never nearer than 1.5 studs; a hit beyond D0 changes nothing.
		local _, near1 = ViewmodelMath.releasePoint(camera, toyCam, ratio, 0.4)
		expect.near(near1, 1.5 / d0, 1e-6)
		local _, far = ViewmodelMath.releasePoint(camera, toyCam, ratio, d0 + 10)
		expect.near(far, 1, 1e-9)
	end)

	t.test("throttle (phone speed fix 2026-10-16): one step per interval on a phase clock", function()
		local interval = 1 / 30
		-- Which of n frames of dt step, from a phase that starts due (as the overlay's).
		local function steps(dt: number, n: number): { boolean }
			local phase = interval
			local list: { boolean } = {}
			for i = 1, n do
				local due, carried = ViewmodelMath.throttle(phase, dt, interval)
				expect.truthy(carried >= 0 and carried <= interval)
				phase = carried
				list[i] = due
			end
			return list
		end
		expect.deepEqual(steps(1 / 60, 6), { true, true, false, true, false, true }) -- every 2nd frame: 30 Hz
		expect.deepEqual(steps(1 / 45, 6), { true, true, true, false, true, true }) -- 2 of every 3: 30 Hz
		expect.deepEqual(steps(1 / 30, 4), { true, true, true, true })
		expect.deepEqual(steps(1 / 20, 4), { true, true, true, true }) -- a slow phone is never held back
		-- The skipped frame's phase is the time since the last step.
		local due, phase = ViewmodelMath.throttle(0, 1 / 60, interval)
		expect.falsy(due)
		expect.near(phase, 1 / 60, 1e-12)
		-- No interval: every frame steps.
		local always, rest = ViewmodelMath.throttle(0.5, 1 / 60, 0)
		expect.truthy(always)
		expect.equal(rest, 0)
	end)

	t.test("stepInterval (phone speed fix 2026-10-16): 1 / hz; 0, below 0 or no number switches the cap off", function()
		expect.near(ViewmodelMath.stepInterval(30), 1 / 30, 1e-12)
		expect.near(ViewmodelMath.stepInterval(45), 1 / 45, 1e-12)
		for _, case in { { 0 }, { -5 }, { 0 / 0 }, { nil }, { "30" } } :: { { any } } do
			local interval = ViewmodelMath.stepInterval(case[1])
			expect.equal(interval, 0)
			-- Off: every frame steps (the review's case: 1 / 0 = inf was never due, so the hands froze).
			for _ = 1, 3 do
				local due = ViewmodelMath.throttle(0, 1 / 60, interval)
				expect.truthy(due)
			end
		end
	end)

	t.test("Config.FirstPerson.lowTier: a 30 Hz step cap (0 = off, else 15..60) and half the throw specks", function()
		local hz = FP.lowTier.stepHz
		expect.equal(hz, 30)
		expect.truthy(hz == 0 or (hz >= 15 and hz <= 60))
		-- Batch B (owner 2026-10-17: "throws make half the sparkles" on phones and tablets); 1 = off, never above.
		local share = FP.lowTier.speckShare
		expect.equal(share, 0.5)
		expect.truthy(share > 0 and share <= 1)
	end)
end
