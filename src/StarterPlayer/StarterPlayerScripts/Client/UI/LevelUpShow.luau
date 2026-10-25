--!strict
-- LevelUpShow (client only). UI FINAL R9 (plan work/ui/PLAN.md R9 "Level-up: the full show", G9.10-G9.25, UD8: the
-- user's Q3, the design's whole show; `H:n` = "Squishy Duels HUD.dc.html" line n; every number in
-- Config.UI.Sticker.levelUp, each with its H line): the design's Grip level-up banner (H:506-535, its keyframes
-- H:44-65, its timers H:715-731, its lists H:999-1002), 4.2 s over everything, never a tap target (H:507
-- pointer-events: none: every part Active false).
--   local show = LevelUpShow.play({ layer = gui, prev = 4, level = 5, unlock = "Firm Grip", squishyId = "toast",
--       uiScale = UIController.scale, safe = function() return overlay.AbsoluteSize end, onCue = fn, onDone = fn })
--   LevelUpShow.stop();   LevelUpShow.isPlaying()
-- * The layer (G9.14): a full-screen ScreenGui (Config.UI.Sticker.levelUp.layer: ScreenInsets None, above the windows)
--   for the scrim, the rays and the bubbles; the content centred at (50%, 44%) of the screen (H:509, H:511) under a
--   UIScale = the UI scale x fitScale (G9.15, PR1: the design's fit, clamped: its 500 x 560 box inside the safe area
--   less 32), recomputed on resize. The rays, bubbles and the FX take the UI scale.
-- * The parts, each a design element on its own holder (its pose through Anim/Tweens.poser, its fade over everything
--   in it through Tweens.fadeGroup, times the exit's fade), driven by ONE Scheduler render effect: the scrim (the
--   radial img.fx.radial.levelScrim, else Theme.radial's fallback; sdFade .3 s); the rays (img.fx.raysLevelUp, none
--   while it has no id; sdLvRays); 16 bubbles (img.fx.radial.bubble, else a ring with its 12% white dot; sdLvBubble,
--   randomised once per session, H:1000); 10 suck dots (sdLvSuck, each along its angle); the ring (sdLvRing: the ink
--   circle 30, the white .25 circle 18, the yellow arc 18 sweeping clockwise from 12 o'clock over .45 s from .55 s,
--   drawn as two half rings each clipped to its half and shown through a UIGradient's hard step turned with the arc,
--   with 18 px dots for its round caps; the pink dashed ring only with img.fx.dashRing, none while it has no id); the
--   flash disc (img.fx.radial.flashDisc, else the fallback; sdLvFlash at 1 s, held small before it, PR17: its opacity
--   at most Config.Vfx.Flash.maxOverlayOpacity); 6 stars (sdLvTw, then sdLvPulse); the number (210 px = TextSize 100
--   x a 2.1 UIScale: the ink copy with its 10 px outline and 12 px drop, the face with the 6-stop gradient seen through
--   a sliding window, sdLvGrad; sdLvInflate then sdLvJelly, the text taking their uniform part); the equipped squishy
--   (UI/Components/SquishyImage 160 with its 6 px drop at .45; sdLvSq exact by its squash, then sdLvIdle; its
--   brightness as the white copy img.squishy.<id>.white at brightness - 1, or the 3D fallback's lights rising to
--   white; pictures cannot go above 1); the ribbon (img.fx.ribbon, else the band and gloss as frames, no tails;
--   sdLvUnfurl as a clip growing about its centre; "GRIP LEVEL UP!" letter by letter, sdLvLetIn then sdLvWave); the
--   pill "Grip {prev} → {level}" (sdUp at 1.5 s) and, for a real unlock (a rank, FD8), "Unlocked {item}" with the
--   gift (sdUp at 1.75 s).
-- * Cues (G9.12, H:719-728; Config.UI.Fx.events.levelUp): at slamMs the slam (onCue "slam") and the 5 px jolt; at
--   toneMs the rising tone (onCue "tone"); at atMs onCue "main", the rings white / #FFE36B / #9AF5D2 (420 / 620 / 820,
--   0 / 110 / 220 ms), the burst (48), the rain (80) and the 14 px jolt (UI/UiFx: the jolt only with Screen shake on).
-- * Exit (G9.22, H:65): sdLvWrap: whole until 88%, then the whole show fades and grows to 1.3 about the screen centre;
--   removed at lifeMs (onDone).
-- * ReducedMotion (G9.23, PR9, decided): the scrim, still rays, the stars, the number, the ribbon, the pill and the
--   unlock line at their final poses and the squishy at (0, -200) x .55, the whole fading in and out at most
--   reducedMotionMaxFadeMs; no dots, bubbles, flash disc, ring, burst, rain or jolt (the cues' sounds still play).
-- Pure (unit-tested): fitScale, cues, gradWindow, bubbles, letters, merge.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local IconGlyph = require(UI.Components.IconGlyph)
local SquishyImage = require(UI.Components.SquishyImage)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Cue = "slam" | "tone" | "main"

export type Spec = {
	layer: ScreenGui,
	prev: number,
	level: number,
	unlock: string?, -- the item a real unlock names (FD8), else nil
	squishyId: string?, -- the equipped squishy
	uiScale: () -> number,
	safe: () -> Vector2, -- the safe area's size (px)
	onCue: ((cue: Cue) -> ())?,
	onDone: (() -> ())?,
}

-- One randomised bubble (H:1000): left in % of the width, size px, period and delay s.
export type Bubble = { x: number, size: number, period: number, delay: number }
-- One ribbon letter (H:999): its character and its two delays (s).
export type Letter = { char: string, delay: number, wave: number }
-- A show waiting for its turn (merge).
export type Pending = { prev: number, level: number, unlock: string? }

type Track = {
	poser: Tweens.Poser?,
	fade: Tweens.FadeGroup?,
	frames: { Tweens.Pose },
	delay: number,
	duration: number, -- a one-shot's length, or a loop's period
	curve: string?,
	loop: boolean,
	alternate: boolean,
	uniform: boolean, -- sx / sy as their uniform part (a text)
	alphaMul: number,
	write: ((pose: Tweens.Pose, alpha: number, u: number) -> ())?, -- a part drawn its own way
}

-- Constants

local LOOK = Config.UI.Sticker.levelUp
local LOOPS = Config.UI.motion.loops
local FX = Config.UI.Fx.events.levelUp
local LIFE = LOOK.lifeMs / 1000
local REDUCED_FADE = Config.UI.motion.reducedMotionMaxFadeMs / 1000
local FLASH_CAP = Config.Vfx.Flash.maxOverlayOpacity -- PR17
local WHITE = Color3.new(1, 1, 1)
local INK = Palette.StickerInk
local SCRIM_KEY = "img.fx.radial.levelScrim"
local RAYS_KEY = "img.fx.raysLevelUp"
local BUBBLE_KEY = "img.fx.radial.bubble"
local FLASH_KEY = "img.fx.radial.flashDisc"
local RIBBON_KEY = "img.fx.ribbon"
local DASH_KEY = "img.fx.dashRing"
local STAR_KEY = "img.icon.star"
local GIFT_KEY = "img.icon.gift"
local PILL_KIND: Theme.TextKind = "Big" -- H:530: 24 px
local LETTER_KIND: Theme.TextKind = "Ribbon" -- H:527: 38 px
local UNLOCK_KIND: Theme.TextKind = "Large" -- H:531: 28 px
local MEASURE_MARGIN_PX = 2

-- Module table

local LevelUpShow = {}

-- Private

local playing: { stop: () -> () }? = nil
local cachedBubbles: { Bubble }? = nil -- H:1000: randomised once and kept

local function finite(n: number): boolean
	return n == n and n > -math.huge and n < math.huge
end

local function color(name: string): Color3
	local value = (Palette :: any)[name]
	return if typeof(value) == "Color3" then value else WHITE
end

-- A clear holder (no layout places it), centred on (x, y) of its parent's top-left, `w` x `h`.
local function holder(name: string, parent: Instance, x: number, y: number, w: number, h: number, z: number?): Frame
	return Create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		Active = false,
		ZIndex = z or 1,
		Parent = parent,
	})
end

local function circle(name: string, parent: Instance, px: number, fill: Color3?, z: number?): Frame
	local frame = holder(name, parent, 0, 0, px, px, z)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	if fill then
		frame.BackgroundColor3 = fill
		frame.BackgroundTransparency = 0
	end
	Theme.corner(px, frame)
	return frame
end

-- A ring drawn as a circle's outside stroke: radius `r` at the stroke's middle, `px` thick (an SVG stroke).
local function ring(name: string, parent: Instance, r: number, px: number, strokeColor: Color3, alpha: number): Frame
	local frame = circle(name, parent, 2 * r - px)
	Theme.stroke(strokeColor, px, frame, 1 - alpha)
	return frame
end

-- The u (0..1) into a track at show time t (CSS fill both: the first frame through the delay; a loop's alternate
-- runs every other period backwards).
local function trackU(track: Track, t: number, reduced: boolean): number
	if reduced then
		return if track.loop then 0 else 1
	end
	local local_t = t - track.delay
	if local_t <= 0 or not (track.duration > 0) then
		return 0
	end
	if not track.loop then
		return math.clamp(local_t / track.duration, 0, 1)
	end
	local cycles = local_t / track.duration
	local u = cycles % 1
	if track.alternate and math.floor(cycles) % 2 == 1 then
		u = 1 - u
	end
	return u
end

-- Public: pure -------------------------------------------------------------------------------------------------------

-- G9.15 (PR1, H:624): the content's fit inside a safe area `safeW` x `safeH` px at UI scale `s`: at most 1, the
-- design's 500 x 560 box kept LOOK.fit.margin inside it. The content's UIScale is s x this.
function LevelUpShow.fitScale(safeW: number, safeH: number, s: number): number
	if not (finite(safeW) and finite(safeH) and finite(s)) or s <= 0 then
		return 1
	end
	local fit = LOOK.fit
	local k = math.min(1, (safeW - fit.margin) / (fit.width * s), (safeH - fit.margin) / (fit.height * s))
	return math.max(k, 0.01)
end

-- G9.12 (H:719-728): the show's cues in time order (ms from its start).
function LevelUpShow.cues(): { { ms: number, cue: Cue } }
	return {
		{ ms = FX.slamMs, cue = "slam" },
		{ ms = FX.toneMs, cue = "tone" },
		{ ms = FX.atMs, cue = "main" },
	}
end

-- G9.11 (H:519, sdLvGrad): the number's gradient window at p (0..1 of the slide): its offset and its share of the
-- 220% gradient.
function LevelUpShow.gradWindow(p: number): (number, number)
	local share = LOOK.number.gradShare
	return (1 - share) * math.clamp(if finite(p) then p else 0, 0, 1), share
end

-- G9.19 (H:510, H:1000): the 16 bubbles, randomised by `rng` (Random) and, without one, once per session and kept.
function LevelUpShow.bubbles(rng: Random?): { Bubble }
	if rng == nil and cachedBubbles then
		return cachedBubbles :: { Bubble }
	end
	local random = rng or Random.new()
	local spec = LOOK.bubbles
	local list: { Bubble } = {}
	for i = 0, spec.n - 1 do
		table.insert(list, {
			x = spec.xFrom + spec.xStep * i + random:NextNumber() * spec.xJitter,
			size = math.round(spec.sizeFrom + random:NextNumber() * spec.sizeJitter),
			period = spec.periodFrom + random:NextNumber() * spec.periodJitter,
			delay = spec.delayFrom + random:NextNumber() * spec.delayJitter,
		})
	end
	if rng == nil then
		cachedBubbles = list
	end
	return list
end

-- G9.18 (H:999): the ribbon's letters with their sdLvLetIn and sdLvWave delays.
function LevelUpShow.letters(text: string): { Letter }
	local spec = LOOK.ribbon
	local wave = LOOPS.lvWave
	local list: { Letter } = {}
	local i = 0
	for _, code in utf8.codes(text) do
		table.insert(list, {
			char = utf8.char(code),
			delay = spec.letterDelayS + spec.letterStepS * i,
			wave = wave.delayS + wave.delayStepS * i,
		})
		i += 1
	end
	return list
end

-- G9.13: a level-up that waits (from Matched to Returning, under a box reveal) merged with the next one: the lowest
-- level it started from, the newest level, the newest unlock (or the older one).
function LevelUpShow.merge(pending: Pending?, prev: number, level: number, unlock: string?): Pending
	if pending == nil then
		return { prev = prev, level = level, unlock = unlock }
	end
	return {
		prev = math.min(pending.prev, prev),
		level = math.max(pending.level, level),
		unlock = unlock or pending.unlock,
	}
end

-- Public -------------------------------------------------------------------------------------------------------------

function LevelUpShow.isPlaying(): boolean
	return playing ~= nil
end

function LevelUpShow.stop()
	local current = playing
	playing = nil
	if current then
		current.stop()
	end
end

function LevelUpShow.play(spec: Spec)
	LevelUpShow.stop()
	local reduced = Tweens.reducedMotion()
	local layer = spec.layer
	local s = spec.uiScale()
	local tracks: { Track } = {}
	local clocks: { (t: number) -> () } = {} -- parts on their own clock (the arc, the number's gradient)
	local function track(t: Track): Track
		table.insert(tracks, t)
		return t
	end
	local function oneShot(
		object: GuiObject?,
		fadeOf: GuiObject?,
		frames: { any },
		delayS: number,
		durationS: number,
		curve: string?,
		uniform: boolean?
	): Track
		return track({
			poser = if object then Tweens.poser(object) else nil,
			fade = if fadeOf then Tweens.fadeGroup(fadeOf) else nil,
			frames = frames :: { Tweens.Pose },
			delay = delayS,
			duration = durationS,
			curve = curve,
			loop = false,
			alternate = false,
			uniform = uniform == true,
			alphaMul = 1,
		})
	end
	local function loop(
		object: GuiObject,
		frames: { any },
		delayS: number,
		periodS: number,
		curve: string?,
		alternate: boolean?,
		uniform: boolean?
	): Track
		return track({
			poser = Tweens.poser(object),
			fade = nil,
			frames = frames :: { Tweens.Pose },
			delay = delayS,
			duration = math.max(periodS, UiIdle.MIN_PERIOD),
			curve = curve,
			loop = true,
			alternate = alternate == true,
			uniform = uniform == true,
			alphaMul = 1,
		})
	end

	-- The show's root: the whole screen, its exit scale about the centre (H:65).
	local root: Frame = Create("Frame", {
		Name = "LevelUpShow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = false,
	})
	local exitScale: UIScale = Create("UIScale", { Name = "SD_Exit", Parent = root })

	-- Scrim (G9.21, H:508): the radial, sdFade .3 s.
	local scrim: Frame = Create("Frame", {
		Name = "Scrim",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 1,
		Parent = root,
	})
	local scrimLook = LOOK.scrim
	Theme.radial(
		scrim,
		SCRIM_KEY,
		{
			outer = Palette.StickerLevelScrimOut,
			outerAlpha = scrimLook.outerAlpha,
			inner = Palette.StickerLevelScrimIn,
			innerAlpha = scrimLook.innerAlpha,
			centre = Vector2.new(0.5, LOOK.centreY),
		} :: any
	)
	oneShot(nil, scrim, { { at = 0, alpha = 0 }, { at = 1, alpha = 1 } }, 0, scrimLook.fadeMs / 1000, scrimLook.curve)

	-- Rays (H:509, sdLvRays): only with their picture.
	local raysContent = AssetTable.image(RAYS_KEY)
	if raysContent then
		local rays: ImageLabel = Create("ImageLabel", {
			Name = "Rays",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, LOOK.centreY),
			Size = UDim2.fromOffset(LOOK.rays.px * s, LOOK.rays.px * s),
			Image = raysContent,
			Active = false,
			ZIndex = 2,
			Parent = root,
		})
		oneShot(rays, rays, LOOK.rays.frames, 0, LIFE, LOOK.rays.curve)
	end

	-- Bubbles (G9.19, H:510): rising from 90 px under the bottom, each its own loop.
	if not reduced then
		local spec = LOOK.bubbles
		local height = layer.AbsoluteSize.Y
		local bubbleContent = AssetTable.image(BUBBLE_KEY)
		for i, bubble in LevelUpShow.bubbles() do
			local px = bubble.size * s
			local frame: Frame = Create("Frame", {
				Name = "Bubble" .. i,
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(bubble.x / 100, px / 2, 1, -spec.bottom * s - px / 2),
				Size = UDim2.fromOffset(px, px),
				Active = false,
				ZIndex = 3,
				Parent = root,
			})
			Theme.corner(px, frame)
			Theme.stroke(WHITE, spec.border, frame, 1 - spec.borderAlpha)
			if bubbleContent then
				Create("ImageLabel", {
					Name = "Fill",
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 1),
					Image = bubbleContent,
					Active = false,
					ZIndex = 3,
					Parent = frame,
				})
			else
				local dot = circle("Dot", frame, px * 2 * spec.dotShare, WHITE, 3)
				dot.Position = UDim2.fromScale(spec.dotX, spec.dotY)
			end
			local frames: { any } = {
				{ at = 0, alpha = 0, x = 0, y = 0, scale = 0.6 },
				{ at = 0.15, alpha = 0.9 },
				{ at = 1, alpha = 0, x = 40 * s, y = -1.15 * height, scale = 1.15 },
			}
			local t = loop(frame, frames, bubble.delay, bubble.period, LOOPS.lvBubble.curve)
			t.fade = Tweens.fadeGroup(frame)
		end
	end

	-- The content: centred at (50%, 44%), the UI scale x the fit (G9.15).
	local content: Frame = Create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, LOOK.centreY),
		Size = UDim2.fromOffset(1, 1),
		Active = false,
		ZIndex = 4,
		Parent = root,
	})
	local contentScale: UIScale = Create("UIScale", { Name = "SD_Fit", Parent = content })
	local function fit()
		local scale = spec.uiScale()
		local safe = spec.safe()
		contentScale.Scale = scale * LevelUpShow.fitScale(safe.X, safe.Y, scale)
	end
	fit()

	-- Suck dots (G9.10, H:512): each along its angle, 250 -> 30.
	if not reduced then
		local suck = LOOK.suck
		for i = 0, suck.n - 1 do
			local arm = holder("Suck" .. i, content, 0, 0, 0, 0, 1)
			arm.Rotation = i * suck.stepDeg
			local dot = holder("Dot", arm, 0, 0, suck.px, suck.px, 1)
			dot.BackgroundColor3 = color(suck.colors[(i % #suck.colors) + 1])
			dot.BackgroundTransparency = 0
			Theme.corner(suck.px, dot)
			local stroke = Theme.stroke(INK, suck.border, dot)
			pcall(function()
				(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
			end)
			local delayS = suck.delayS + (i % suck.delayCycle) * suck.delayStepS
			oneShot(dot, dot, suck.frames, delayS, suck.ms / 1000, suck.curve)
		end
	end

	-- Ring (H:513, sdLvRing; the arc G9.17).
	if not reduced then
		local r = LOOK.ring
		local box = holder("Ring", content, 0, 0, r.box, r.box, 2)
		ring("Ink", box, r.r, r.inkPx, INK, 1)
		ring("White", box, r.r, r.whitePx, WHITE, r.whiteAlpha)
		local yellow = Palette.StickerCoinText
		local reach = r.r + r.arcPx / 2
		local halves: { UIGradient } = {}
		for side = 1, 2 do
			-- side 1: the right half (12 -> 6 o'clock), side 2: the left half (6 -> 12).
			local clip: Frame = Create("Frame", {
				Name = if side == 1 then "ArcRight" else "ArcLeft",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(if side == 1 then 0 else 1, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(reach + 1, 2 * reach + 2),
				ClipsDescendants = true,
				Active = false,
				ZIndex = 2,
				Parent = box,
			})
			local arc = circle("Arc", clip, 2 * r.r - r.arcPx, nil, 2)
			arc.Position = UDim2.fromScale(if side == 1 then 0 else 1, 0.5)
			local stroke = Theme.stroke(yellow, r.arcPx, arc)
			halves[side] = Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(0.5001, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Rotation = 180 * (side - 1),
				Parent = stroke,
			})
		end
		local startCap = circle("CapStart", box, r.arcPx, yellow, 3)
		startCap.Position = UDim2.new(0.5, 0, 0.5, -r.r)
		local headCap = circle("CapHead", box, r.arcPx, yellow, 3)
		local dashContent = AssetTable.image(DASH_KEY)
		local dash: ImageLabel? = if dashContent
			then Create("ImageLabel", {
				Name = "Dash",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(2 * r.r + r.dashPx, 2 * r.r + r.dashPx),
				Image = dashContent,
				Active = false,
				ZIndex = 4,
				Parent = box,
			})
			else nil
		local arcCurve = Tweens.curve(r.arcCurve)
		oneShot(box, box, r.frames, 0, LIFE, r.curve)
		-- The arc's sweep (sdLvFill, H:53): from 12 o'clock clockwise, its own clock.
		local arcStart, arcLength = r.arcDelayMs / 1000, r.arcMs / 1000
		local function arcAt(t: number)
			local p = arcCurve(math.clamp((t - arcStart) / arcLength, 0, 1))
			local theta = 360 * p
			halves[1].Rotation = math.min(theta, 180)
			halves[2].Rotation = math.max(theta, 180)
			startCap.Visible = p > 0
			headCap.Visible = p > 0
			local rad = math.rad(theta)
			headCap.Position = UDim2.new(0.5, r.r * math.sin(rad), 0.5, -r.r * math.cos(rad))
			if dash then
				dash.Rotation = theta -- one full turn over the same .45 s (the dash offset moves a circumference)
			end
		end
		arcAt(0)
		table.insert(clocks, arcAt)
	end

	-- Flash disc (G9.25, H:514, sdLvFlash; PR17).
	if not reduced then
		local f = LOOK.flash
		local disc = holder("Flash", content, 0, 0, f.px, f.px, 3)
		Theme.corner(f.px, disc)
		Theme.radial(
			disc,
			FLASH_KEY,
			{
				outer = WHITE,
				outerAlpha = 0,
				inner = WHITE,
				innerAlpha = 1,
				mid = Palette.StickerFlashGlow,
				midAt = f.midAt,
				midAlpha = f.midAlpha,
			} :: any
		)
		local flashTrack = oneShot(disc, disc, f.frames, f.delayMs / 1000, f.ms / 1000, f.curve)
		flashTrack.alphaMul = FLASH_CAP
	end

	-- Stars (G9.10, H:515, H:1002): sdLvTw, then sdLvPulse inside.
	do
		local st = LOOK.stars
		for i, offset in st.offsets do
			local outer = holder("Star" .. i, content, offset.x, offset.y, offset.px, offset.px, 4)
			local inner = holder("Pulse", outer, offset.px / 2, offset.px / 2, offset.px, offset.px, 4)
			local image = IconGlyph.image(STAR_KEY, { name = "Image", sizePx = offset.px, parent = inner })
			image.ZIndex = 4
			local index = i - 1
			oneShot(outer, outer, st.frames, st.delayS + st.stepS * index, st.ms / 1000, st.curve)
			loop(
				inner,
				LOOPS.lvPulse.frames,
				st.pulseDelayS + st.pulseStepS * index,
				LOOPS.lvPulse.periodS,
				LOOPS.lvPulse.curve
			)
		end
	end

	-- The number (G9.11, H:516-519).
	local gradient: UIGradient
	do
		local n = LOOK.number
		local box = holder("Number", content, 0, 0, n.width, n.height, 5)
		local jelly = holder("Jelly", box, n.width / 2, n.height / 2, n.width, n.height, 5)
		local textBox = holder("Text", jelly, n.width / 2, n.height / 2, n.width / n.scale, n.height / n.scale, 5)
		Create("UIScale", { Name = "SD_Size", Scale = n.scale, Parent = textBox })
		local font = Theme.font("Hero")
		local function numberLabel(name: string, textColor: Color3, dy: number, stroke: boolean, z: number): TextLabel
			local label: TextLabel = Create("TextLabel", {
				Name = name,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, dy),
				Size = UDim2.fromScale(1, 1),
				FontFace = font,
				TextSize = n.textSize,
				Text = tostring(spec.level),
				TextColor3 = textColor,
				TextWrapped = false,
				Active = false,
				ZIndex = z,
				Parent = textBox,
			})
			if stroke then
				local outline = Theme.stroke(INK, n.inkStroke / n.scale, label)
				outline.LineJoinMode = Enum.LineJoinMode.Round
				-- Theme.stroke strokes the box (Border): the design outlines the digit, not its 2.1x frame.
				outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			end
			return label
		end
		numberLabel("Drop", INK, n.drop / n.scale, true, 5)
		numberLabel("Ink", INK, 0, true, 5)
		local face = numberLabel("Face", WHITE, 0, false, 6)
		gradient = Create("UIGradient", { Rotation = 90, Parent = face })
		oneShot(box, box, n.frames, n.delayMs / 1000, n.ms / 1000, n.curve, true)
		loop(jelly, LOOPS.lvJelly.frames, n.jellyDelayS, LOOPS.lvJelly.periodS, LOOPS.lvJelly.curve, false, true)
	end
	local gradStops: { UiIdle.Stop } = {}
	for _, stop in LOOK.number.gradStops do
		table.insert(gradStops, { pos = stop.pos, color = color(stop.color) })
	end
	local gradCurve = Tweens.curve(LOOK.number.gradCurve)
	local function gradAt(t: number)
		local period = LOOK.number.gradPeriodS
		local cycles = if reduced then 0 else t / period
		local u = cycles % 1
		if math.floor(cycles) % 2 == 1 then
			u = 1 - u
		end
		local offset, share = LevelUpShow.gradWindow(gradCurve(u))
		gradient.Color = UiIdle.gradientWindow(gradStops, offset, share)
	end
	gradAt(0)
	table.insert(clocks, gradAt)

	-- The squishy (G9.20, H:522-523).
	local squishyId = spec.squishyId
	if squishyId then
		local q = LOOK.squishy
		local outer = holder("Squishy", content, 0, 0, q.px, q.px, 6)
		local inner = holder("Idle", outer, q.px / 2, q.px / 2, q.px, q.px, 6)
		local image =
			SquishyImage.new(squishyId, { size = q.px, shadow = q.shadow, owned = true, parent = inner :: Instance })
		image.root.AnchorPoint = Vector2.new(0.5, 0.5)
		image.root.Position = UDim2.fromScale(0.5, 0.5)
		local outerTrack = oneShot(outer, outer, q.frames, 0, LIFE, q.curve)
		local idleTrack = loop(inner, LOOPS.lvIdle.frames, q.idleDelayS, LOOPS.lvIdle.periodS, LOOPS.lvIdle.curve, true)
		-- The brightness (G4.6's mapping): the white copy, made after the fade group so the glow owns its alpha.
		local whiteContent = AssetTable.image(SquishyImage.keyOf(squishyId) .. ".white")
		local pictureHolder = image.root:FindFirstChild("Holder")
		local white: ImageLabel? = if whiteContent and pictureHolder
			then Create("ImageLabel", {
				Name = "White",
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				Image = whiteContent,
				ImageTransparency = 1,
				ScaleType = Enum.ScaleType.Fit,
				Active = false,
				ZIndex = 3,
				Parent = pictureHolder,
			})
			else nil
		local viewport = image.root:FindFirstChildWhichIsA("ViewportFrame", true)
		local baseAmbient = if viewport then viewport.Ambient else WHITE
		local baseLight = if viewport then viewport.LightColor else WHITE
		local outerPoser = outerTrack.poser :: Tweens.Poser
		local idlePoser = idleTrack.poser :: Tweens.Poser
		outerTrack.poser, idleTrack.poser = nil, nil
		local idlePose: Tweens.Pose = {}
		idleTrack.write = function(pose: Tweens.Pose)
			idlePose = pose
			idlePoser:set({ y = pose.y })
		end
		outerTrack.write = function(pose: Tweens.Pose, alpha: number, u: number)
			outerPoser:set({ y = pose.y, rot = pose.rot })
			image:squash((pose.sx or 1) * (idlePose.sx or 1), (pose.sy or 1) * (idlePose.sy or 1))
			local glow = Tweens.poseAt((q.glow :: any) :: { Tweens.Pose }, u, q.curve).alpha or 0
			if white then
				white.ImageTransparency = 1 - glow * alpha
			end
			if viewport then
				-- A ViewportFrame is not in a fade group: its own image fades here.
				viewport.ImageTransparency = 1 - alpha
				viewport.Ambient = baseAmbient:Lerp(WHITE, glow)
				viewport.LightColor = baseLight:Lerp(WHITE, glow)
			end
		end
	end

	-- The ribbon (G9.18, H:525-527).
	do
		local rb = LOOK.ribbon
		local outer = holder("Ribbon", content, 0, rb.y + rb.height / 2, rb.width, rb.height, 7)
		local clip = holder("Clip", outer, rb.width / 2, rb.height / 2, 0, rb.height, 7)
		clip.ClipsDescendants = true
		local band = rb.band
		local bandCentreY = band.y + band.height / 2 - rb.height / 2
		local ribbonContent = AssetTable.image(RIBBON_KEY)
		if ribbonContent then
			local picture: ImageLabel = Create("ImageLabel", {
				Name = "Picture",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(rb.width, rb.height),
				Image = ribbonContent,
				Active = false,
				ZIndex = 7,
				Parent = clip,
			})
			picture.ScaleType = Enum.ScaleType.Stretch
			oneShot(nil, picture, {}, 0, LIFE, nil) -- the exit's fade
		else
			local face = holder("Band", clip, 0, 0, band.width, band.height, 7)
			face.Position = UDim2.new(0.5, 0, 0.5, bandCentreY)
			face.BackgroundColor3 = Palette.StickerRibbonFace
			face.BackgroundTransparency = 0
			Theme.corner(band.radius, face)
			local outline = Theme.stroke(INK, band.stroke, face)
			pcall(function()
				(outline :: any).BorderStrokePosition = Enum.BorderStrokePosition.Center -- an SVG stroke
			end)
			local g = rb.gloss
			local gloss: Frame = Create("Frame", {
				Name = "Gloss",
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1 - g.alpha,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(g.x - band.x, g.y - band.y),
				Size = UDim2.fromOffset(g.width, g.height),
				Active = false,
				ZIndex = 7,
				Parent = face,
			})
			Theme.corner(g.radius, gloss)
			oneShot(nil, face, {}, 0, LIFE, nil) -- the exit's fade
		end
		-- The letters in the band (left 32, right 32, top 8, 60 high), centred.
		local letters = LevelUpShow.letters(Strings.grip.levelUpRibbon)
		local widths: { number } = {}
		local total = 0
		for i, letter in letters do
			-- Measured as drawn under the content's UIScale (a glyph is wider there than textWidth says).
			widths[i] = math.ceil(Theme.textBoundsAt(letter.char, LETTER_KIND, nil, contentScale.Scale).X)
			total += widths[i]
		end
		local lineHeight = math.ceil(Theme.lineHeight(LETTER_KIND))
		local x = -total / 2
		for i, letter in letters do
			local w = widths[i]
			local slot = holder("Letter" .. i, clip, 0, 0, w, lineHeight, 8)
			slot.Position = UDim2.new(0.5, x + w / 2, 0.5, bandCentreY)
			local wave = holder("Wave", slot, w / 2, lineHeight / 2, w, lineHeight, 8)
			local label = Theme.label({
				Name = "Char",
				Text = letter.char,
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.fromScale(1, 1),
				TextWrapped = false,
				ZIndex = 8,
				Parent = wave,
			}, LETTER_KIND)
			Theme.stickerText(label, rb.letterRole)
			-- Theme.text turns wrapping on; a lone glyph a pixel wider than its slot would then not draw at all.
			for _, text in label:GetDescendants() do
				if text:IsA("TextLabel") then
					text.TextWrapped = false
				end
			end
			label.TextWrapped = false
			oneShot(slot, slot, rb.letter, letter.delay, rb.letterMs / 1000, rb.letterCurve)
			loop(wave, LOOPS.lvWave.frames, letter.wave, LOOPS.lvWave.periodS, LOOPS.lvWave.curve)
			x += w
		end
		-- No fade group of its own: its band and its letters fade by themselves (one writer per transparency).
		local unfurl = oneShot(outer, nil, rb.unfurl, rb.unfurlDelayMs / 1000, rb.unfurlMs / 1000, rb.unfurlCurve)
		local unfurlPoser = unfurl.poser :: Tweens.Poser
		unfurl.poser = nil
		local wide, tall = rb.width + 2 * rb.grow, rb.height + 2 * rb.grow
		unfurl.write = function(pose: Tweens.Pose)
			unfurlPoser:set({ scale = pose.scale })
			clip.Size = UDim2.fromOffset(math.max(0, wide * (pose.sx or 1)), tall * (pose.sy or 1))
		end
	end

	-- The pill and the unlock line (G9.24, H:529-531).
	do
		local pl = LOOK.pill
		local texts: { { text: string, color: Color3 } } = {
			{ text = Strings.format(Strings.grip.levelFrom, { from = spec.prev }), color = Palette.StickerTextGrey },
			{ text = Strings.grip.levelArrow, color = Palette.StickerCoinText },
			{ text = tostring(spec.level), color = Palette.StickerMintTop },
		}
		local lineHeight = math.ceil(Theme.lineHeight(PILL_KIND))
		local widths: { number } = {}
		local inner = 0
		for i, entry in texts do
			widths[i] = math.ceil(Theme.textWidth(entry.text, PILL_KIND)) + MEASURE_MARGIN_PX
			inner += widths[i] + (if i > 1 then pl.gap else 0)
		end
		local pillW = inner + 2 * (pl.padX + pl.border)
		local pillH = lineHeight + 2 * (pl.padY + pl.border)
		local pill = holder("Pill", content, 0, pl.y + pillH / 2, pillW, pillH, 8)
		pill.BackgroundColor3 = INK
		pill.BackgroundTransparency = 0
		Theme.corner(pillH, pill)
		local border = Theme.stroke(WHITE, pl.border, pill)
		pcall(function()
			(border :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
		end)
		local x = pl.border + pl.padX
		for i, entry in texts do
			local label = Theme.label({
				Name = "Part" .. i,
				Text = entry.text,
				AutomaticSize = Enum.AutomaticSize.None,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, x, 0.5, 0),
				Size = UDim2.fromOffset(widths[i], lineHeight),
				TextWrapped = false,
				ZIndex = 8,
				Parent = pill,
			}, PILL_KIND, nil, entry.color)
			Theme.noOutline(label) -- H:530: no outline
			x += widths[i] + pl.gap
		end
		oneShot(pill, pill, LOOK.up, pl.delayMs / 1000, pl.ms / 1000, pl.curve)
		local unlock = spec.unlock
		if unlock and unlock ~= "" then
			local u = LOOK.unlock
			local prefix = Strings.grip.unlockedPrefix
			local unlockHeight = math.ceil(Theme.lineHeight(UNLOCK_KIND))
			local prefixW = math.ceil(Theme.textWidth(prefix, UNLOCK_KIND)) + MEASURE_MARGIN_PX
			local itemW = math.ceil(Theme.textWidth(unlock, UNLOCK_KIND)) + MEASURE_MARGIN_PX
			local lineW = u.gift + u.gap + prefixW + itemW
			local lineH = math.max(u.gift, unlockHeight)
			local line = holder("Unlock", content, 0, pl.y + pillH + pl.columnGap + lineH / 2, lineW, lineH, 8)
			local gift = IconGlyph.image(GIFT_KEY, { name = "Gift", sizePx = u.gift, parent = line })
			gift.AnchorPoint = Vector2.new(0, 0.5)
			gift.Position = UDim2.fromScale(0, 0.5)
			local function part(name: string, text: string, px: number, w: number, tint: Color3?)
				local label = Theme.label({
					Name = name,
					Text = text,
					AutomaticSize = Enum.AutomaticSize.None,
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, px, 0.5, 0),
					Size = UDim2.fromOffset(w, unlockHeight),
					TextWrapped = false,
					ZIndex = 8,
					Parent = line,
				}, UNLOCK_KIND)
				Theme.stickerText(label, u.role)
				if tint then
					label.TextColor3 = tint
				end
			end
			part("Prefix", prefix, u.gift + u.gap, prefixW, nil)
			part("Item", unlock, u.gift + u.gap + prefixW, itemW, Palette.StickerCoinText)
			oneShot(line, line, LOOK.up, u.delayMs / 1000, u.ms / 1000, u.curve)
		end
	end

	-- A 1 px marker at the centre: the FX's spot (UiFx reads a GuiObject's centre).
	local centre = holder("Centre", content, 0, 0, 1, 1, 1)
	root.Parent = layer

	-- The driver: every track at show time t, times the exit's fade; the cues; removed at LIFE.
	local exitFrames = (LOOK.exit.frames :: any) :: { Tweens.Pose }
	local elapsed = 0
	local cueList = LevelUpShow.cues()
	local nextCue = 1
	local handle: Scheduler.Handle? = nil
	local resize = layer:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		if handle then
			handle:disconnect()
		end
		resize:Disconnect()
		root:Destroy()
		if playing and (playing :: any).root == root then
			playing = nil
		end
		local onDone = spec.onDone
		if onDone then
			task.spawn(onDone)
		end
	end
	local function cue(name: Cue)
		local onCue = spec.onCue
		if onCue then
			task.spawn(onCue, name)
		end
		if reduced then
			return
		end
		if name == "slam" then
			UiFx.jolt(content, FX.slamJolt)
		elseif name == "main" then
			for _, entry in FX.rings do
				task.delay(entry.delayMs / 1000, function()
					if not done then
						UiFx.ring(centre, color(entry.color), entry.size)
					end
				end)
			end
			local sparks = table.clone(FX.sparks) :: any
			sparks.colors = UiFx.colors(FX.sparks.colors)
			UiFx.sparks(centre, sparks)
			UiFx.rain(FX.rain)
			UiFx.jolt(content, FX.jolt)
		end
	end
	local function frameAt(t: number)
		local wrap: number
		if reduced then
			wrap = math.clamp(math.min(t, LIFE - t) / REDUCED_FADE, 0, 1)
			exitScale.Scale = 1
		else
			local exitPose = Tweens.poseAt(exitFrames, math.clamp(t / LIFE, 0, 1), LOOK.exit.curve)
			wrap = exitPose.alpha or 1
			exitScale.Scale = exitPose.scale or 1
		end
		for _, item in tracks do
			local u = trackU(item, t, reduced)
			local pose: Tweens.Pose = if #item.frames > 0 then Tweens.poseAt(item.frames, u, item.curve) else {}
			local alpha = (pose.alpha or 1) * item.alphaMul * wrap
			pose.alpha = nil
			if item.uniform and (pose.sx ~= nil or pose.sy ~= nil) then
				pose.scale = (pose.scale or 1) * math.sqrt(math.max(0, (pose.sx or 1) * (pose.sy or 1)))
				pose.sx, pose.sy = nil, nil
			end
			local fade = item.fade
			if fade then
				fade:setAlpha(alpha)
			end
			local write = item.write
			if write then
				write(pose, alpha, u)
			elseif item.poser then
				(item.poser :: Tweens.Poser):set(pose)
			end
		end
		for _, clock in clocks do
			clock(t)
		end
	end
	frameAt(0)
	handle = Scheduler.add(function(dt: number): boolean
		if root.Parent == nil then
			finish()
			return false
		end
		elapsed += dt
		while nextCue <= #cueList and elapsed * 1000 >= cueList[nextCue].ms do
			cue(cueList[nextCue].cue)
			nextCue += 1
		end
		if elapsed >= LIFE then
			finish()
			return false
		end
		frameAt(elapsed)
		return true
	end, "render")
	local show = { root = root, stop = finish }
	playing = show
end

return LevelUpShow
