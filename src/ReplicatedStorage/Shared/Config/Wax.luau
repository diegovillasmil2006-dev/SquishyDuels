--!strict
-- Config.Wax: the knead screen's wax coat (spec phase2-squeeze §1.13-§1.14, §3.4, §3.11). Shared, data only. Read by
-- the client Anim/WaxCoat (cells, stress, cracks, wear, re-wax) and Anim/CrackNetwork (the crack lines and their colour
-- rule). Every number is the design's own with its "design: squish.js:<line>" (the 3D Lab package sd/squish.js);
-- "proposal" marks a Roblox-side value (spec phase2 §3). Lengths are shares of the toy's maxDim, or of one crack cell
-- (coats.<feel>.cell·maxDim) in `lines`; times in seconds.
-- Not here: the audio fields of the design's WAX (modes to gain, squish.js:42-48: they shape the pre-rendered sounds,
-- spec §3.10; their mix is Config.Audio.wax), the HUD layout (Config.UI.Knead), the coat labels and notes
-- (Strings.knead). Phase 2b (the Inspect integration): flakes, jolt, sparkle, hud and canvas below.

export type Coat = { cell: number, th: number, wear: number, gloss: number }

local Wax = {
	-- Per material (design: squish.js:37-48): cell = the crack-line cell size × maxDim, th = the stress a cell takes
	-- before it cracks, wear = the coat lost per crack per unit of energy, gloss = the wax shine.
	coats = {
		foam = { cell = 0.075, th = 1.45, wear = 0.05, gloss = 0.6 }, -- design: squish.js:41
		mochi = { cell = 0.06, th = 2.6, wear = 0.045, gloss = 0.9 }, -- design: squish.js:43
		jelly = { cell = 0.095, th = 2.8, wear = 0.065, gloss = 1 }, -- design: squish.js:45
		plush = { cell = 0.07, th = 2.4, wear = 0.06, gloss = 0.35 }, -- design: squish.js:47
	} :: { [string]: Coat },
	-- proposal (spec phase2 §3.4): one global factor on every th, so that a 3 s thumb crunch on a fresh Butter gives the
	-- design's 30-45 cracks a second (HANDOFF.md:38) on our shell, whose vertex density and normals differ from the
	-- design's three.js meshes. Calibrated offline (Lune, 2026-10-11, 60 fps, 30 seeds): 35.4 cracks a second on the
	-- High shell (39.3 on Low); at 1 it was 27.6 (29.0). Check it in Studio (spec §3.14) and tune only this.
	thScale = 0.93,
	-- Cells (design: squish.js:231-265): Poisson-disk samples at least spacing·maxDim apart over the coat's vertices, at
	-- most maxCells; each th = coat th·thScale·exp(thSpread·gauss); neighbours = the cells within neighbourRadius ×
	-- spacing; the footprint = every coat vertex within footprintRadius × spacing, weight (1 - d² / rc²)².
	cells = {
		spacing = 0.085, -- dc (design: squish.js:232)
		maxCells = 480, -- MAXC (design: squish.js:233)
		thSpread = 0.35, -- design: squish.js:245, 289
		neighbourRadius = 2, -- design: squish.js:250
		footprintRadius = 1.7, -- design: squish.js:252
	},
	-- Stress (design: squish.js:274-281): the load is bend·(the normal's chord since last frame) + |Δ|x|| / rF; s =
	-- s·exp(-relax·dt) + load·(worn + (1 - worn)·I).
	stress = {
		relax = 1.4, -- design: squish.js:274
		bend = 1.3, -- design: squish.js:279
		worn = 0.3, -- design: squish.js:281
	},
	-- Cracks (design: squish.js:282-295), biggest s / th first: E = clamp((s / th)·exp(energySpread·gauss), energyMin,
	-- energyMax)·(energyWorn + (1 - energyWorn)·I); s = max(0, s - th·U(dropMin, 1)); a new th. Only the first
	-- `sounding` cracks of a frame go on: crunchiness += (I - crunchiness)·crunchinessRate, I = max(0, I - wear·E), each
	-- footprint vertex's damage += damage·E·weight (<= 1), each neighbour's s += its th·cascade·U(0, 1)·its I.
	cracks = {
		energySpread = 0.45, -- design: squish.js:288
		energyMin = 0.3, -- design: squish.js:288
		energyMax = 3, -- design: squish.js:288
		energyWorn = 0.45, -- design: squish.js:288
		dropMin = 0.75, -- design: squish.js:289
		sounding = 6, -- design: squish.js:290
		crunchinessRate = 0.04, -- the design's `local` (design: squish.js:291)
		damage = 0.14, -- design: squish.js:268
		cascade = 0.07, -- design: squish.js:292
	},
	driveStrain = 3, -- the audio beds' drive = min(1, strain / dt / cells / driveStrain) (design: squish.js:632)
	-- The fresh-coat shine (design: squish.js:308, 627-628): re-wax sets 1, it falls shineDecay a second, and the gloss is
	-- gloss·(1 + shineGain·shine).
	shineDecay = 1.1, -- design: squish.js:627
	shineGain = 2.5, -- design: squish.js:628
	-- The crack lines (design: squish.js:72-93; spec §1.14, §3.4). Rest space is measured in cells (1 / (coat cell ×
	-- maxDim)). Voronoi seeds at cell + hash3(cell)·seedJitter + seedOffset; a.x = F2 - F1, a.y = a random value per edge.
	-- Below skipBelow the crack value shows nothing. Octave 1: rv = smoothstep(revealLow + revealSpan·a.y, revealHigh +
	-- revealSpan·a.y, crack); width w = width·(widthBase + pressWiden·press); halo out to haloWidth·w. Octave 2 past
	-- octave2Gate: Voronoi of q·octave2Scale + octave2Offset, rv2 = smoothstep(octave2Low + octave2Span·b.y, octave2High +
	-- octave2Span·b.y, crack), width octave2Width·w, halo octave2HaloWidth·w2, its line × octave2Line and halo ×
	-- octave2Halo. Colour: whiten toward min(col·haloMul + haloAdd, 1) by clamp(halo·haloWhiten + crack·crackWhiten, 0, 1),
	-- then darken to col·lineDarken by line·lineAlpha.
	lines = {
		seedJitter = 0.85, -- design: squish.js:75
		seedOffset = 0.075, -- design: squish.js:75
		skipBelow = 0.015, -- design: squish.js:83
		revealLow = 0.03, -- design: squish.js:85
		revealHigh = 0.1, -- design: squish.js:85
		revealSpan = 0.8, -- design: squish.js:85
		width = 0.045, -- design: squish.js:85
		widthBase = 0.75, -- design: squish.js:85
		pressWiden = 1.6, -- design: squish.js:85
		haloWidth = 3.2, -- design: squish.js:86
		octave2Gate = 0.38, -- design: squish.js:87
		octave2Scale = 2.3, -- design: squish.js:88
		octave2Offset = 7.13, -- design: squish.js:88
		octave2Low = 0.38, -- design: squish.js:88
		octave2High = 0.46, -- design: squish.js:88
		octave2Span = 0.55, -- design: squish.js:88
		octave2Width = 0.65, -- design: squish.js:88
		octave2HaloWidth = 3, -- design: squish.js:90
		octave2Line = 0.85, -- design: squish.js:89
		octave2Halo = 0.6, -- design: squish.js:90
		haloWhiten = 0.6, -- design: squish.js:92
		crackWhiten = 0.1, -- a smooth term: a vertex colour, not a line (design: squish.js:92; spec §3.4)
		haloMul = 1.1, -- design: squish.js:92
		haloAdd = 0.08, -- design: squish.js:92
		lineDarken = 0.38, -- design: squish.js:93
		lineAlpha = 0.92, -- design: squish.js:93
		-- proposal (spec phase2 §3.4): the lines are a precomputed network drawn into the colour atlas. Each shell
		-- triangle is split so the marching lattice has at least pointsPerCell points per crack cell along the longest
		-- shell edge (the spec's "refined 2×" leaves octave 2's cells, 1/2.3 as big, unresolved; offline 2026-10-11 on
		-- Butter's High shell 2 finds 95% of the edge length a 4× finer lattice finds, in 0.5 s native), and a segment
		-- is redrawn when its reveal crosses a step of alphaStep.
		pointsPerCell = 2,
		alphaStep = 0.25,
	},
	-- Phase 2b: the flakes a crack throws (spec §1.15, §3.5; design: fp.js:676-684, fx.js:64-67, 94-95, 134-141). A crack
	-- of energy E >= minEnergy throws flakes with chance chanceBase + chanceIntact·I (I = the cell's coat left), one plus
	-- one more with chance extraChance·E, in the cracked part's colour lerped `whiten` toward white, from the cell
	-- `offset` out along its normal, at normal·U(speedMin, speedMax) + (U(±sideways), U(upMin, upMax), U(±depth)) in the
	-- camera's right / up / toward-the-viewer axes. Size U(sizeMin, sizeMax)·max(1, zoomShare·kz), life U(lifeMin,
	-- lifeMax), gravity along the camera's up, drag (v ×= e^(-drag·dt)), spin U(spinMin, spinMax) rad/s about a random
	-- axis from a random angle in [0, startAngleMax). Lengths in du (KneadMath.duToStuds). The chip: the outline radii
	-- `chip` at every 60°, extruded chipDepth (fx.js:67); a pooled thin block of its bounding box stands in for it.
	-- Scale over u = age / life: popPeak·sin(u / popEnd·popArc·π) before popEnd, 1, then 1 - ((u - fadeStart) / (1 -
	-- fadeStart))^fadePower (fx.js:139). cap (proposal, spec §3.5): live flakes; a new one past it is dropped.
	flakes = {
		minEnergy = 0.6, -- design: fp.js:679
		chanceBase = 0.25, -- design: fp.js:679
		chanceIntact = 0.4, -- design: fp.js:679
		extraChance = 0.3, -- design: fp.js:682
		whiten = 0.3, -- design: fp.js:681
		offset = 0.002, -- design: fp.js:683
		speedMin = 0.1, -- design: fp.js:683
		speedMax = 0.28, -- design: fp.js:683
		sideways = 0.08, -- design: fp.js:683
		upMin = 0.02, -- design: fp.js:683
		upMax = 0.12, -- design: fp.js:683
		depth = 0.04, -- design: fp.js:683
		sizeMin = 0.0016, -- design: fp.js:683
		sizeMax = 0.0032, -- design: fp.js:683
		zoomShare = 0.8, -- design: fp.js:682
		lifeMin = 0.5, -- design: fp.js:683
		lifeMax = 0.9, -- design: fp.js:683
		gravity = -1.1, -- design: fp.js:683
		drag = 1.4, -- design: fp.js:683
		spinMin = 8, -- design: fp.js:683
		spinMax = 18, -- design: fp.js:683
		startAngleMax = 6, -- design: fx.js:94
		chip = { 1, 0.7, 0.95, 0.62, 0.9, 0.74 }, -- design: fx.js:67
		chipDepth = 0.16, -- design: fx.js:67
		popEnd = 0.12, -- design: fx.js:139
		popPeak = 1.25, -- design: fx.js:139
		popArc = 0.62, -- design: fx.js:139
		fadeStart = 0.6, -- design: fx.js:139
		fadePower = 1.6, -- design: fx.js:139
		cap = 40, -- proposal (spec §3.5)
	},
	-- Phase 2b: a crack with E > minEnergy jolts the toy: jolt = max(jolt, gain·E·(intactBase + (1 - intactBase)·I)) du,
	-- shown as a random offset of ±jolt / 2 on the camera's x and y each frame, ×= e^(-decay·dt) (design: fp.js:678,
	-- 480). Off under ReducedMotion (a shake).
	jolt = { minEnergy = 1.4, gain = 0.0005, intactBase = 0.4, decay = 30 },
	-- Phase 2b: the re-wax sparkle (design: fp.js:687, fx.js:97-107): `count` stars at the toy's centre, each `spread` ×
	-- half the toy's width out along a random direction, at speed·U(0.45, 1.2) du/s, size sizeDu·U(0.6, 1.4) du, life
	-- life·U(0.7, 1.3), no gravity, drag `drag`. The star (fx.js:65, 68: 5 points, radii 1 / 0.46, extruded 0.25 with a
	-- 0.14 / 0.12 bevel) is a pooled block of its bounding box `star` (derived).
	sparkle = {
		count = 10, -- design: fp.js:687
		speed = 0.22, -- design: fp.js:687
		sizeDu = 0.004, -- design: fp.js:687
		life = 0.45, -- design: fp.js:687
		drag = 2.5, -- design: fp.js:687
		spread = 0.7, -- design: fp.js:687
		star = Vector3.new(2.14, 2.05, 0.53), -- derived from fx.js:65, 68
	},
	-- Phase 2b: the HUD's state word from the crunchiness (design: fp.js:701): Crunchy above `crunchy`, Crackled above
	-- `crackled`, else Soft.
	hud = { crunchy = 0.7, crackled = 0.4 },
	-- Phase 2b (proposal, spec §3.4): the crack canvas draws at most drawPerFrame segment changes a frame (the rest wait,
	-- in order); each draws the halo at offsets 0 and ±haloOffsets px across the line (the outermost pair at haloFalloff
	-- of the halo: the design's smoothstep halo, squish.js:86), then the line. The crack network builds within
	-- buildMsPerFrame[quality] a frame until it is done (offline: about 0.5 s native / 1.3 s interpreted on High, so
	-- about 3-7 s of frames; Low about half the work at half the budget).
	canvas = {
		drawPerFrame = 60,
		haloOffsets = { 1, 2 },
		haloFalloff = 0.5,
		buildMsPerFrame = { High = 3, Low = 1.5 },
	},
}

return Wax
