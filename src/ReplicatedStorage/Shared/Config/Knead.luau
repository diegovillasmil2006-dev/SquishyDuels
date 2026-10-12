--!strict
-- Config.Knead: the knead screen's soft body (spec phase2-squeeze §1.2-§1.12, §3.2, §3.3, §3.11). Shared, data only.
-- Read by the client Anim/SoftBody (the port of the 3D Lab's SoftSquish), Anim/ShellGeometry and Anim/WaxCoat (pan).
-- Every number is the design's own, with its "design: <file>:<line>" (the 3D Lab package sd/squish.js and sd/fp.js);
-- "proposal" marks a Roblox-side value the design has no counterpart for (spec phase2 §3).
-- Units: soft-body lengths are shares of the toy's own box (the bounds of its soft shells: maxDim, minDim and the size
-- s.x, s.y, s.z), so they port to studs unchanged; times in seconds; springs { k, c } (x'' = -k x - c x').
-- The design frame: the design's toys face +Z and ours -Z, so SoftBody runs every formula in the model frame turned 180°
-- about Y (x and z negated, spec "Axes"); "front", "the left thumb" and "toward the camera" keep their meaning.
-- 3 Hz rule (Config.validate): every spring here is <= 3 Hz except jelly's per-vertex spring (k 520, c 7: 3.59 Hz), the
-- design's own "springs straight back and wobbles", kept as a documented exception (see Config.validate).
-- Not here: the whole-toy jiggle of the design's FEELS (jig, wob) is Config.Anim.rig.feels (the same numbers); the
-- shading fields (crease, pore, poreF, gloss, squish.js:95-120) have no shader to drive (spec §3.4); the labels and
-- notes (squish.js:29-32) are Strings.knead. Phase 2b (the Inspect integration): `view` (the knead camera, fp.js:81-91)
-- and kickVelocity below.

export type Feel = {
	rise: number,
	fast: number,
	k: number,
	c: number,
	beta: number,
	gamma: number,
	smear: number,
	pull: number,
	pullR: number,
	neck: number,
	plastic: number,
	lump: number,
}

local Knead = {
	-- Per material (design: squish.js:28-33): rise = the memory's slow-rise time; fast = the share of a dent NOT kept in
	-- memory; k, c = the per-vertex spring; beta = the dent rim; gamma = the volume bulge gain; smear = the drag smear
	-- share; pull, pullR = the stretch's reach and radius (× maxDim); neck = necking; plastic = the share of a pull kept;
	-- lump = the per-vertex noise amplitude. The toys' blueprints carry their feel as motion.feel (design: squish.js:34).
	feels = {
		foam = {
			rise = 1.9,
			fast = 0.12,
			k = 300,
			c = 20,
			beta = 0.7,
			gamma = 2,
			smear = 0.62,
			pull = 0.36,
			pullR = 0.17,
			neck = 0.6,
			plastic = 0.08,
			lump = 0.32,
		}, -- design: squish.js:29
		mochi = {
			rise = 2.7,
			fast = 0.05,
			k = 190,
			c = 11,
			beta = 1,
			gamma = 2.3,
			smear = 0.95,
			pull = 0.62,
			pullR = 0.2,
			neck = 0.85,
			plastic = 0.22,
			lump = 0.18,
		}, -- design: squish.js:30
		jelly = {
			rise = 0.4,
			fast = 0.8,
			k = 520,
			c = 7,
			beta = 1.05,
			gamma = 2.7,
			smear = 0.45,
			pull = 0.3,
			pullR = 0.17,
			neck = 0.45,
			plastic = 0,
			lump = 0.08,
		}, -- design: squish.js:31
		plush = {
			rise = 1.1,
			fast = 0.32,
			k = 320,
			c = 22,
			beta = 0.7,
			gamma = 1.8,
			smear = 0.42,
			pull = 0.3,
			pullR = 0.19,
			neck = 0.5,
			plastic = 0.06,
			lump = 0.28,
		}, -- design: squish.js:32
	} :: { [string]: Feel },
	defaultFeel = "foam", -- an unknown toy is foam (design: squish.js:35)
	brushSlots = 4, -- MAXB: live brushes at once (design: squish.js:13)
	-- The finger (design: squish.js:173, 325): radius rF = radius·maxDim, depth dF = min(depthOfRadius·rF,
	-- depthOfMinDim·minDim), depth falloff T = falloff·rF.
	finger = { radius = 0.15, depthOfRadius = 0.95, depthOfMinDim = 0.42, falloff = 1.4 },
	-- The two palms (design: squish.js:392): at box.min.x and box.max.x pressing inward; radius = radius·min(s.y, s.z),
	-- falloff T = falloff·s.x, depth min(depthOfX·s.x, (1 - the toy's squeeze depth)·depthOfSqueeze·s.x), rim beta ×
	-- betaShare, profile power `power`.
	palm = { radius = 0.5, falloff = 0.55, depthOfX = 0.3, depthOfSqueeze = 0.55, betaShare = 0.35, power = 1.5 },
	-- The two thumbs (design: squish.js:425, 428): radius rT = radius·maxDim, falloff T = falloff·rT, depth
	-- min(depthOfRadius·rT, depthOfMinDim·minDim), rim beta × betaShare.
	thumb = { radius = 0.11, falloff = 1.35, depthOfRadius = 0.9, depthOfMinDim = 0.3, betaShare = 0.6 },
	-- A brush's depth (design: squish.js:529-534): target dMax·amt·sm((t - delay) / rise)·(settle + (1 - settle)·sm((t -
	-- delay) / creepSeconds)); the depth follows it on `spring`, substepsPerSecond; a released brush retires below
	-- retireDepth·dMax when slower than retireSpeed·dMax a second.
	depth = {
		delayFinger = 0.035, -- finger and thumb (design: squish.js:531)
		delayPalm = 0.03, -- design: squish.js:531
		riseFinger = 0.09, -- finger and thumb (design: squish.js:531)
		risePalm = 0.16, -- design: squish.js:531
		settle = 0.86, -- design: squish.js:531
		creepSeconds = 1.2, -- design: squish.js:531
		spring = { 650, 50 }, -- 0.8 Hz, ζ 0.98 (design: squish.js:533)
		substepsPerSecond = 240, -- design: squish.js:532
		retireDepth = 0.01, -- design: squish.js:534
		retireSpeed = 0.3, -- design: squish.js:534
	},
	-- The memory field (design: squish.js:174, 336-337, 488-517): a stroke is stamped every stampSpacing·rF; a finger
	-- move longer than maxStrokeOfRadius·rF jumps without a stroke; a vertex is left alone when its stamp is at most
	-- keepBelow × its faded memory and no smear applies; the smear applies where exp(-smearSideways·s - q) >= smearMin;
	-- |M| <= capOfRadius·rF.
	memory = {
		stampSpacing = 0.28, -- design: squish.js:512
		maxStrokeOfRadius = 3.5, -- design: squish.js:337
		keepBelow = 0.85, -- design: squish.js:503
		smearMin = 0.03, -- design: squish.js:503, 505
		smearSideways = 0.7, -- design: squish.js:502
		capOfRadius = 1.1, -- design: squish.js:174
	},
	lumpScale = 0.55, -- the lump noise frequency is 1 / (lumpScale·rF) (design: squish.js:176)
	springSubstepsPerSecond = 90, -- the per-vertex springs (design: squish.js:555)
	restEpsilon = 2e-4, -- eps = restEpsilon·maxDim (design: squish.js:174)
	movingEpsilon = 20, -- a vertex moves while |v| > movingEpsilon·eps (design: squish.js:555)
	-- The volume bulge (design: squish.js:555, 595, 611): infl follows gamma·vol / area at rate `rate`; a vertex is pushed
	-- out by infl·(1 - min(1, |x| / (dentShare·dF))).
	bulge = { rate = 30, dentShare = 0.25 },
	-- The stretch (design: squish.js:356-357, 369-370, 378-383, 544-545, 586): it slips past slip·maxPull; the field
	-- radius is rP·(1 + radiusGrowth·L / maxPull); the body tug moves the rest by tug·(1 - w); necking neck·neckGain·
	-- min(1, L / rp)·w·(1 - w); a pull longer than plasticMin·maxPull keeps `plastic` of itself where w >=
	-- plasticWeightMin.
	pull = { slip = 1.75, radiusGrowth = 0.5, tug = 0.08, neckGain = 2, plasticMin = 0.05, plasticWeightMin = 0.02 },
	-- The thumb crunch (design: squish.js:420-458, 472-478). Thumb A at frontPoint(-(gap - slide·P) + ju, height + jv),
	-- B at frontPoint(+(gap - slide·P) + ju, height + jv); frontPoint(u, w) = the body vertex with rest normal z >=
	-- frontMinZ nearest to (ctr.x + u·spanX·s.x, ctr.y + w·spanY·s.y). P follows the rhythm's target at rate `follow`.
	crunch = {
		period = 0.56, -- one press (design: squish.js:444)
		jitterU = 0.06, -- ju = U(-jitterU, jitterU) each cycle after the first (design: squish.js:445)
		jitterV = 0.08, -- design: squish.js:445
		low = 0.42, -- the target's floor after the first cycle (design: squish.js:446)
		pressEnd = 0.5, -- the target eases low -> 1 over phase 0..pressEnd (design: squish.js:447)
		holdEnd = 0.7, -- holds 1 until holdEnd (design: squish.js:447)
		releaseDrop = 0.58, -- then eases down by releaseDrop to the cycle's end (design: squish.js:447)
		follow = 22, -- P += (target - P)·min(1, follow·dt) (design: squish.js:448)
		gap = 0.48, -- design: squish.js:426-427, 449
		slide = 0.2, -- design: squish.js:426, 449
		height = 0.12, -- design: squish.js:427, 449
		spanX = 0.36, -- design: squish.js:426, 473
		spanY = 0.32, -- design: squish.js:473
		frontMinZ = 0.55, -- design: squish.js:475
		startAmount = 0.3, -- the thumbs' amt = startAmount + (1 - startAmount)·P (design: squish.js:430, 454)
		releaseRate = 1.6, -- off: P -= P·min(1, releaseRate·dt / max(releaseMinRise, rise)) (design: squish.js:457)
		releaseMinRise = 0.3, -- design: squish.js:457
		snap = 1e-3, -- a smaller P snaps to 0 (design: squish.js:457)
	},
	-- The pinch field (design: squish.js:549-574) while P > active. s = x - ctr.x, yN = 2(y - ctr.y) / s.y, zN = 2(z -
	-- ctr.z) / s.z, fr = sm((zN + frontStart) / frontSpan), g0 = crunch.gap·crunch.spanX·s.x, shift =
	-- crunch.slide·crunch.spanX·s.x. Between the thumbs (|s| < g0, qq = 1 - (s / g0)²): dx = -shift·P·s / g0; z +=
	-- ridge·s.z·P·qq²·(ridgeBase + (1 - ridgeBase)·fr)·exp(-ridgeWidth·(yN - centreY)²); y -= dip·s.y·P·qq·sm((yN +
	-- dipStart) / dipSpan)·(dipBase + (1 - dipBase)·fr). Outside (oo = (|s| - g0) / (pullIn·s.x)): dx = -sign(s)·shift·
	-- P·exp(-oo²); e = swell·P·sm((|s| - g0) / (s.x / 2 - g0)); y += (y - ctr.y)·e, z += (z - ctr.z)·e. Then x += dx·
	-- (dxBase + (1 - dxBase)·fr)·(dxFloor + (1 - dxFloor)·exp(-dxWidth·(yN - centreY)²)); ee = (2s / s.x)²: z +=
	-- curlZ·s.z·P·ee, y += curlY·s.y·P·ee.
	pinch = {
		active = 1e-4, -- design: squish.js:549
		ridge = 0.3, -- design: squish.js:553
		ridgeBase = 0.3, -- design: squish.js:570
		ridgeWidth = 1.5, -- design: squish.js:570
		centreY = 0.1, -- design: squish.js:570, 572
		dip = 0.16, -- design: squish.js:553
		dipStart = 0.1, -- design: squish.js:570
		dipSpan = 1.1, -- design: squish.js:570
		dipBase = 0.4, -- design: squish.js:570
		pullIn = 0.35, -- design: squish.js:552
		swell = 0.08, -- design: squish.js:553
		frontStart = 0.4, -- design: squish.js:568
		frontSpan = 1.4, -- design: squish.js:568
		dxBase = 0.6, -- design: squish.js:572
		dxFloor = 0.35, -- design: squish.js:572
		dxWidth = 1.2, -- design: squish.js:572
		curlZ = 0.14, -- design: squish.js:553
		curlY = 0.06, -- design: squish.js:553
	},
	-- Kicks out (design: squish.js:327, 350, 364, 372, 395, 401, 431, 436): `soft` on the toy's jiggle along the press
	-- axis (palms X, thumbs Z), `squisher` on its squash spring; the stretch's end kicks soft·a + softBase and
	-- squisher·a, a = L / maxPull. The rig converts them (spec phase2 §3.3).
	kicks = {
		fingerDown = { soft = 0.022, squisher = -0.6 }, -- design: squish.js:327
		fingerUp = { soft = -0.016, squisher = 0.7 }, -- design: squish.js:364
		pullStart = { squisher = -0.3 }, -- no soft kick (design: squish.js:350)
		pullEnd = { soft = -0.05, softBase = -0.012, squisher = 1.2 }, -- design: squish.js:372
		palmsOn = { soft = 0.05, squisher = -0.6 }, -- design: squish.js:395
		palmsOff = { soft = -0.045, squisher = 0.8 }, -- design: squish.js:401
		thumbsOn = { soft = 0.035, squisher = -0.5 }, -- design: squish.js:431
		thumbsOff = { soft = -0.03, squisher = 0.6 }, -- design: squish.js:436
	},
	-- Sound events (design: squish.js:319, 363-365, 373, 399-402, 437): the release amount of a finger is clamp(d / dMax,
	-- fingerUpMin, 1) with air × fingerAir; a snap's air is snapAir·a; the palms' clamp(palm press, palmsOffMin, 1); the
	-- thumbs release thumbsOff. pan = clamp((x - ctr.x) / (s.x / 2), -1, 1)·pan.
	sounds = {
		fingerUpMin = 0.25, -- design: squish.js:363
		fingerAir = 0.6, -- design: squish.js:365
		snapAir = 0.4, -- design: squish.js:373
		palmsOffMin = 0.3, -- design: squish.js:399
		thumbsOff = 0.8, -- design: squish.js:437
		pan = 0.55, -- the FP page's panK (design: fp.js:103)
	},
	-- The squish face (design: squish.js:189-192, 615-621): on while the palms press past palmOn (until they drop to
	-- palmOff), a finger presses past fingerDepth·dMax on jelly or within reach·faceR of the face centre, a pull is
	-- longer than pull·maxPull or the crunch P is past crunch. Without face parts the face centre is (ctr.x, ctr.y +
	-- fallbackLift·s.y, front) and faceR = fallbackRadius·s.x; with them faceR = max(|face size| / 2, minRadius·s.x).
	face = {
		palmOn = 0.3, -- design: squish.js:616
		palmOff = 0.18, -- design: squish.js:616
		fingerDepth = 0.4, -- design: squish.js:618
		reach = 1.5, -- design: squish.js:618
		pull = 0.3, -- design: squish.js:619
		crunch = 0.3, -- design: squish.js:620
		fallbackLift = 0.15, -- design: squish.js:191
		fallbackRadius = 0.3, -- design: squish.js:192
		minRadius = 0.18, -- design: squish.js:192
	},
	sleepSeconds = 0.12, -- at rest this long, the soft body snaps to rest and stops (design: squish.js:640-641)
	-- The soft shell (proposal, spec phase2 §3.2, §3.4): one closed shell per body part with about highVertices (High)
	-- or lowVertices (Low) vertices per toy, at least minSegments per side of each part; 8 bounds anchors with legs of
	-- anchorLeg studs at the rest bounds widened by anchorReach·maxDim (derived: mochi's pull 0.62·maxDim with its 22%
	-- plastic memory and 25% spring overshoot reaches about 0.95·maxDim), so the MeshPart never rescales; the UV atlas
	-- is atlas[quality] texels wide (the crack canvas' EditableImage) with gutterTexels between its rectangles.
	shell = {
		highVertices = 2000,
		lowVertices = 800,
		minSegments = 2,
		anchorReach = 1,
		anchorLeg = 0.01,
		atlas = { High = 1024, Low = 512 },
		gutterTexels = 2,
		-- Phase 2b (proposal): true flips the atlas' v (1 - v) when the shell's UVs are written, in case EditableMesh
		-- samples with v up (Studio check: the part colours and crack lines land on the wrong tiles).
		uvFlipV = false,
	},
	-- Phase 2b: the soft jiggle kick kick(v) adds jv += kickVelocity·v (design: squish.js:321); KneadMath.kickPeak turns
	-- it into the rig's kick amount (spec §3.3).
	kickVelocity = 20,
	-- Phase 2b: the knead view in Inspect (spec §1.17, §3.6; design: fp.js:81-91, 302, 482-486, 685-686). The orbit
	-- camera stands in for the design's toy rotation: home = face front (yaw 0, the top tilted homePitch toward the
	-- camera, fp.js:83), crunch = the tilt that shows the top while the thumbs crunch (fp.js:81). While crunching and not
	-- dragging, the view eases toward crunch at crunchRate (1 - e^(-rate·dt) a frame); the crunch's end eases it home at
	-- homeRate for settleSeconds. The knead fit (fp.js:85-91) only sizes the flakes and the jolt (du -> studs,
	-- KneadMath): the toy is fitWidth / fitHeight of the free area at fitDepth du in the cameraFovDeg viewmodel camera,
	-- never below zoom 1, and toyLongestDu·zoom du long.
	view = {
		homePitchRad = 0.16, -- design: fp.js:83
		crunchPitchRad = 0.45, -- design: fp.js:81
		crunchRate = 5, -- design: fp.js:484
		homeRate = 8, -- design: fp.js:483
		settleSeconds = 0.9, -- design: fp.js:686
		fitDepth = 0.42, -- design: fp.js:86
		fitWidth = 0.82, -- design: fp.js:90
		fitHeight = 0.74, -- design: fp.js:90
		toyLongestDu = 0.19, -- K = toyLongestDu / maxDim (design: fp.js:100)
		cameraFovDeg = 70, -- the viewmodel camera (design: fp.js:28)
	},
}

return Knead
