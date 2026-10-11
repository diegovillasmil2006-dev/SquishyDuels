--!strict
-- Config.Inspect: Inspect viewport framing, orbit camera, lighting, background, input and squeeze preview
-- (DESIGN §10.5-§10.7), and the Collection pedestal displays (§7.6, §7.7). Shared (read by the client
-- InspectController, UI/OrbitCamera, UI/InspectFormat, UI/CollectionFormat), data only. All [P].
-- Per-squishy default yaw/pitch come from Catalog `inspect`; Orbit defaults apply when a def has none.

local Inspect = {
	-- r = size.Magnitude/2 × squeezeWidening; fitDist = r / sin(min(vFov, hFov)/2) × fitPadding.
	-- Squishy overhaul (spec 2026-10-09 §3.2): each toy frames its own widest squeeze scale + widenMargin
	-- (SquishRig.framingWidening), never below squeezeWidening.
	Framing = {
		vFovDeg = 30, -- FieldOfViewMode Vertical
		squeezeWidening = 1.28, -- maximum squeeze widening, so a squeeze never leaves the frame
		widenMargin = 0.04,
		fitPadding = 1.12,
		zoomMin = 0.6, -- zoom multiplier range
		zoomMax = 1.5,
		minClearance = 0.75, -- dist - r >= minClearance
		nearPlane = 0.5,
	},

	-- The camera orbits; the model only deforms.
	Orbit = {
		defaultYawDeg = 25,
		defaultPitchDeg = 12,
		pitchMinDeg = -30,
		pitchMaxDeg = 65, -- yaw wraps
		rotateSmoothSeconds = 0.06, -- SmoothDamp T
		zoomSmoothSeconds = 0.1,
		inertiaDecay = 6, -- drag-release yaw velocity decays e^(-6t); none under ReducedMotion
		resetSmoothSeconds = 0.18,
	},

	-- Lighting and Atmosphere don't apply inside a ViewportFrame.
	Lighting = {
		lightColor = Color3.fromRGB(255, 244, 230),
		-- Camera-locked key light: cam.CFrame:VectorToWorldSpace(lightDirection.Unit), recomputed every frame.
		lightDirection = Vector3.new(0.45, -0.65, -0.6),
		ambient = Color3.fromRGB(150, 146, 160),
	},

	Background = {
		gradientFrom = "#EFE7FA", -- UIGradient, hex -> Color3.fromHex
		gradientTo = "#FFF4E6",
		ellipseTransparency = 0.6, -- soft white ellipse behind the model centre
		contactShadowTransparency = 0.85, -- 2D Ink contact shadow that widens with the squash
	},

	-- §10.6. H = viewport height.
	Input = {
		dragYawDegPerHeight = 300, -- yaw = dx/H × 300°
		dragPitchDegPerHeight = 180, -- pitch = dy/H × 180°
		keyDegPerSecond = 120, -- arrow keys
		stickDeadzone = 0.18, -- radial
		stickExponent = 2, -- response x²
		stickYawDegPerSecond = 200,
		stickPitchDegPerSecond = 120,
		wheelZoomFactor = 1.12, -- per notch
		triggerZoomPerSecond = 1.5, -- R2 in / L2 out at full press
		-- Reading (DESIGN silent, Part 6 review): R2 / L2 zoom as soon as Position.Z passes this small deadzone, so the
		-- speed follows the press from the start (§10.6 "1.5×/s at full press (Position.Z)"); the 0.5 trigger threshold
		-- of Config.Combat.Aim stays for Throw and Ultimate only.
		triggerDeadzone = 0.05,
		tapMaxPixels = 8, -- < 8 px and < 300 ms = tap
		tapMaxMs = 300,
		-- Reading (DESIGN silent, Part 6): the drag's yaw speed (the release inertia of §10.5) is low-pass filtered
		-- with this time constant, so one uneven frame does not fling the model and a finger that stops loses it.
		dragSpeedSmoothSeconds = 0.05,
	},

	-- Squeeze preview (§10.7): no remote, no Coins. The dot COUNT is Config.Anim.squeeze.inspectDotsMin/Max.
	Preview = {
		-- Every Inspect rig squeezes on Y, Banana too (spec 2026-10-11 §6; design: toys.js:455, the 3D Lab Inspect
		-- squashes every toy on Y). The rig switches axis only at rest.
		squeezeAxis = "Y",
		maxPerSecond = 8,
		soundCooldownMs = 90,
		-- Readings (DESIGN silent, Part 6): the 2D particle dots fly out from the model centre, slowing to a stop,
		-- shrinking and fading over dotLifeSeconds; each dot gets a speed between the min and max (px/s).
		dotSizePx = 10,
		dotSpeedMinPx = 140,
		dotSpeedMaxPx = 260,
		dotLifeSeconds = 0.45,
	},

	-- Collection pedestal displays (§7.6, §7.7; Part 6, client only). The scale (2.5) and the 60-stud build radius
	-- stay in WorldLayout.Collection (squishyScale, buildStuds). Readings (DESIGN silent): the distance is checked
	-- every checkSeconds; a built model is kept until it is hysteresisStuds past the radius (no build / destroy
	-- flicker at the edge); "animated" (§7.6) = a slow sway of swayDeg either side of the -X facing, one sway every
	-- swayPeriodSeconds, so every face stays toward the aisle (Part 6 review: not a full turn), standing still under
	-- ReducedMotion; the nameplate is a BillboardGui of nameplateSizeStuds (width, height) this far above the model's top.
	-- Squishy overhaul (spec 2026-10-09 §3.2): displays within idleStuds breathe and blink, at most idleMax of them,
	-- from the rig slots the held models leave (lowest priority).
	Collection = {
		checkSeconds = 0.5,
		hysteresisStuds = 5,
		swayDeg = 15,
		swayPeriodSeconds = 6,
		nameplateOffsetStuds = 0.8,
		nameplateSizeStuds = Vector2.new(4.5, 1.4),
		idleStuds = 20,
		idleMax = 8,
	},
}

return Inspect
