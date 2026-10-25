--!strict
-- LevelUpShow (client only). The new short level-up (2026-10-25, owner: "Yes, build the new short level-up like that.
-- You can upload the 3 pictures."; `L:n` = Diego's "Squishy Duels LOBBY HUD.dc.html" line n: the markup L:586-611,
-- lvPlay L:927-956; every number in Config.UI.Sticker.levelUp, the FX in Config.UI.Fx.events.levelUp). It replaced
-- the long dark 4.2 s show (UI FINAL R9): a small GRIP badge at (50%, 34%) of the screen, no scrim, never a tap target.
--   LevelUpShow.play({ layer = gui, prev = 4, level = 5, unlock = "Firm Grip", uiScale = UIController.scale,
--     target = function() return gripRow end, onCue = fn, onDone = fn })
--   LevelUpShow.stop();   LevelUpShow.isPlaying()
-- * The badge (img.lv.badge) pops in squashing (420 ms); inside its round opening (a CanvasGroup, so the parts are cut
--   to the circle) the stripes turn (img.lv.spin, 6 s a turn), the old level flies up and out, the new one bounces in
--   gold, then a gloss crosses it; the GRIP chip sits on its top. Around it the ring grows and fades (img.lv.ring)
--   and 8 rays shoot out from their foot. Under it LEVEL UP! unrolls and, for a real unlock (a rank), "Unlocked
--   {item}" with the gift drops in.
-- * Cues (onCue): "tone" at toneMs (the rising tone), "main" at atMs (the jingle; here the ring, the burst and a 3 px
--   jolt of the badge, UiFx: the jolt only with Screen shake on), "arrive" when the badge reaches the Grip bar (the bar
--   swells and pops: the caller's).
-- * At holdMs (holdUnlockMs with an unlock line) the badge flies to spec.target() (its left + fly.toX, top + fly.toY;
--   up fly.fallbackDy without one), lifting first and shrinking to .18 as it fades; the ribbon and the unlock line
--   drop out; the show is gone endAfterMs later (onDone).
-- * ReducedMotion (Anim/Tweens): nothing moves, the parts only fade; no ring, rays, burst or jolt (the cues still come).
-- Pure (unit-tested): holdMs(unlock), cues(unlock), flightFrames(dx, dy), merge(pending, prev, level, unlock).

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
local Layout = require(UI.Layout)
local SegmentedTabs = require(UI.Components.SegmentedTabs)
local Theme = require(UI.Theme)
local UiFx = require(UI.UiFx)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Cue = "tone" | "main" | "arrive"

export type Spec = {
	layer: ScreenGui,
	prev: number,
	level: number,
	unlock: string?, -- the item a real unlock names, else nil
	uiScale: () -> number,
	target: (() -> GuiObject?)?, -- the Grip bar the badge flies into
	onCue: ((cue: Cue) -> ())?,
	onDone: (() -> ())?,
}

-- A show waiting for its turn (merge).
export type Pending = { prev: number, level: number, unlock: string? }

type Track = {
	poser: Tweens.Poser?,
	fade: Tweens.FadeGroup?,
	frames: { Tweens.Pose },
	delayMs: number,
	ms: number,
	curve: string, -- the whole run's easing (the design's animate() `easing` option)
}

-- Constants

local LOOK = Config.UI.Sticker.levelUp
local FX = Config.UI.Fx.events.levelUp
local WHITE = Palette.White
local INK = Palette.StickerInk
local MEASURE_MARGIN_PX = 6 -- scaled text draws a little wider than TextService measures

-- Module table

local LevelUpShow = {}

-- Private

local playing: { root: Frame, stop: () -> () }? = nil

local function color(name: string): Color3
	local value = (Palette :: any)[name]
	return if typeof(value) == "Color3" then value else WHITE
end

local function clear(name: string, props: { [string]: any }): Frame
	local frame: Frame = Create("Frame", { Name = name, BackgroundTransparency = 1, Active = false })
	for property, value in props do
		if property ~= "Parent" then
			(frame :: any)[property] = value
		end
	end
	frame.Parent = props.Parent
	return frame
end

local function picture(name: string, key: string, props: { [string]: any }): ImageLabel
	local label: ImageLabel = Create("ImageLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Image = AssetTable.image(key) or "",
		ScaleType = Enum.ScaleType.Stretch,
		Active = false,
	})
	for property, value in props do
		if property ~= "Parent" then
			(label :: any)[property] = value
		end
	end
	label.Parent = props.Parent
	return label
end

local function oneLine(label: TextLabel)
	label.TextWrapped = false
	for _, text in label:GetDescendants() do
		if text:IsA("TextLabel") then
			text.TextWrapped = false
		end
	end
end

-- The frames without their alpha (the motion; the fade is the whole holder's, Tweens.fadeGroup).
local function motionOf(frames: { Tweens.Pose }): { Tweens.Pose }
	local out: { Tweens.Pose } = {}
	for _, frame in frames do
		local copy = table.clone(frame)
		copy.alpha = nil
		table.insert(out, copy)
	end
	return out
end

-- Public: pure -------------------------------------------------------------------------------------------------------

-- L:931: how long the badge stays before it flies to the Grip bar (longer with an unlock line).
function LevelUpShow.holdMs(unlock: boolean): number
	return if unlock then LOOK.holdUnlockMs else LOOK.holdMs
end

-- The cues in time order (ms from the start; see the header).
function LevelUpShow.cues(unlock: boolean): { { ms: number, cue: Cue } }
	return {
		{ ms = FX.toneMs, cue = "tone" },
		{ ms = FX.atMs, cue = "main" },
		{ ms = LevelUpShow.holdMs(unlock) + LOOK.arrive.atMs, cue = "arrive" },
	}
end

-- L:948-949: the badge's flight by (dx, dy) base px: lifting a little first (liftShare of the way, liftUp higher,
-- liftScale), then all the way, shrunk to endScale and faded.
function LevelUpShow.flightFrames(dx: number, dy: number): { Tweens.Pose }
	local fly = LOOK.fly
	return {
		{ at = 0, alpha = 1, x = 0, y = 0, scale = 1 },
		{
			at = fly.liftAt,
			alpha = 1,
			x = dx * fly.liftShare,
			y = dy * fly.liftShare - fly.liftUp,
			scale = fly.liftScale,
		},
		{ at = 1, alpha = 0, x = dx, y = dy, scale = fly.endScale },
	}
end

-- A level-up that waits (from Matched to Returning, under a box reveal) merged with the next one: the lowest level it
-- started from, the newest level, the newest unlock (or the older one).
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
	local hasUnlock = spec.unlock ~= nil and spec.unlock ~= ""
	local hold = LevelUpShow.holdMs(hasUnlock)
	local life = hold + LOOK.endAfterMs
	local tracks: { Track } = {}
	local function track(holder: GuiObject, frames: { any }, ms: number, delayMs: number, curve: string): Track
		local item: Track = {
			poser = Tweens.poser(holder),
			fade = Tweens.fadeGroup(holder),
			frames = frames :: { Tweens.Pose },
			delayMs = delayMs,
			ms = ms,
			curve = curve,
		}
		table.insert(tracks, item)
		return item
	end

	local root = clear("SD_LevelUpShow", { Size = UDim2.fromScale(1, 1), ZIndex = 1 })
	local centre = clear("Centre", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(LOOK.centreX, LOOK.centreY),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 1,
		Parent = root,
	})
	local scale: UIScale = Create("UIScale", { Scale = spec.uiScale(), Parent = centre })

	-- The ring (L:588) and the rays (L:589), behind the badge.
	local ring = LOOK.ring
	local ringHolder = clear("Ring", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(ring.px, ring.px),
		ZIndex = 1,
		Parent = centre,
	})
	local pad = (ring.picturePx - ring.px) / 2
	picture("Image", "img.lv.ring", {
		Position = UDim2.fromOffset(-pad, -pad),
		Size = UDim2.fromOffset(ring.picturePx, ring.picturePx),
		ZIndex = 1,
		Parent = ringHolder,
	})
	local rays = LOOK.rays
	local rayHolders: { Frame } = {}
	for i = 0, rays.n - 1 do
		local pivot = clear("Ray" .. i + 1, {
			Size = UDim2.fromOffset(0, 0),
			Rotation = rays.fromDeg + i * rays.stepDeg,
			ZIndex = 1,
			Parent = centre,
		})
		local length = if i % 2 == 1 then rays.short else rays.long
		-- The bar from `top` down `length`, grown about its foot (transform-origin 50% 100%).
		local bar: Frame = Create("Frame", {
			Name = "Bar",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromOffset(0, rays.top + length),
			Size = UDim2.fromOffset(rays.width, length),
			BackgroundColor3 = color(rays.colors[i % #rays.colors + 1]),
			BorderSizePixel = 0,
			ZIndex = 1,
			Parent = pivot,
		})
		Theme.corner(rays.radius, bar)
		Theme.stroke(INK, rays.border, bar)
		table.insert(rayHolders, bar)
	end

	-- The badge (L:590-597): Fly (the flight) > Pop (its entrance) > the disc, the opening, the GRIP chip.
	local b = LOOK.badge
	local fly = clear("Fly", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(b.px, b.px),
		ZIndex = 2,
		Parent = centre,
	})
	local pop = clear("Pop", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
		Parent = fly,
	})
	-- Sized in shares of the badge, so its squash (Pop's Size) squashes them too.
	local p = b.picture
	picture("Disc", "img.lv.badge", {
		Position = UDim2.fromScale(-p.x / b.px, -p.y / b.px),
		Size = UDim2.fromScale(p.width / b.px, p.height / b.px),
		ZIndex = 2,
		Parent = pop,
	})
	local opening: CanvasGroup = Create("CanvasGroup", {
		Name = "Opening",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(b.opening / b.px, b.opening / b.px),
		BackgroundTransparency = 1,
		ZIndex = 3,
		Parent = pop,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = opening })
	local spin = picture("Spin", "img.lv.spin", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = opening,
	})
	local function number(name: string, text: string, tint: Color3?): Frame
		local holder = clear(name, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = opening,
		})
		local label = Theme.label({
			Name = "Text",
			Text = text,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
			Parent = holder,
		}, "LevelNumber")
		Theme.stickerText(label, "levelNumber")
		if tint then
			label.TextColor3 = tint
		end
		oneLine(label)
		return holder
	end
	local oldNumber = number("Old", tostring(spec.prev), nil)
	local newNumber = number("New", tostring(spec.level), color(LOOK.new.color))
	-- L:595 the gloss: a white band crossing the opening once (its gradient's offset), slanted like skewX(-18deg).
	local g = LOOK.gloss
	local gloss: Frame = Create("Frame", {
		Name = "Gloss",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = opening,
	})
	local glossGradient: UIGradient = Create("UIGradient", {
		Rotation = SegmentedTabs.gradientRotation(g.skew, b.opening, b.opening),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5 - g.share / 2, 1),
			NumberSequenceKeypoint.new(0.5, g.transparency),
			NumberSequenceKeypoint.new(0.5 + g.share / 2, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = gloss,
	})
	local glossFrom = g.from * g.share + g.share / 2 - 0.5 -- the band's centre as the gradient's offset
	local glossTo = g.to * g.share + g.share / 2 - 0.5
	glossGradient.Offset = Vector2.new(glossFrom, 0)
	-- L:597 GRIP on the badge's top.
	local ch = LOOK.chip
	local chipText = Strings.grip.levelUpChip
	local chipSize = Theme.textBounds(chipText, "Small")
	local chip: Frame = Create("Frame", {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, ch.top),
		Size = UDim2.fromOffset(chipSize.X + MEASURE_MARGIN_PX + 2 * (ch.pad + ch.border), ch.height),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = pop,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = chip })
	local chipLabel = Theme.label({
		Name = "Text",
		Text = chipText,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 7,
		Parent = chip,
	}, "Small", nil, color(ch.color))
	oneLine(chipLabel)

	-- LEVEL UP! (L:599-601).
	local r = LOOK.ribbon
	local ribbonBands = Layout.stickerBands(r.border, r.highlightPx, 0, r.lip)
	local ribbon = clear("Ribbon", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(0, r.top + r.height / 2),
		Size = UDim2.fromOffset(r.width, r.height),
		ZIndex = 8,
		Parent = centre,
	})
	local ribbonFace: Frame = Create("Frame", {
		Name = "Face",
		Size = UDim2.new(1, 0, 1, ribbonBands.drop - r.border),
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = ribbon,
	})
	Theme.foam(
		ribbonFace,
		{
			radius = r.radius,
			stroke = r.border,
			inner = true,
			top = ribbonBands.top,
			drop = ribbonBands.drop,
			colors = {
				face = Palette.LevelRibbonTop,
				mid = Palette.StickerRibbonFace,
				midAt = 0.6,
				faceEnd = Palette.LevelRibbonEnd,
				top = Palette.LevelRibbonTop:Lerp(WHITE, r.highlightAlpha),
			},
		} :: any
	)
	local ribbonLabel = Theme.label({
		Name = "Text",
		Text = Strings.grip.levelUpRibbon,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 9,
		Parent = ribbon,
	}, "Big")
	Theme.stickerText(ribbonLabel, "levelRibbon")
	oneLine(ribbonLabel)

	-- The unlock line (L:602-609), for a real unlock.
	local unlockHolder: Frame? = nil
	if hasUnlock then
		local u = LOOK.unlock
		local prefix = Strings.grip.unlockedPrefix
		local item = spec.unlock :: string
		local textSize = Theme.textBounds(prefix .. item, "Small")
		local bands = Layout.stickerBands(u.border, 0, 0, u.lip)
		local width = 2 * u.border + u.padLeft + u.gift + u.gap + textSize.X + MEASURE_MARGIN_PX + u.padRight
		local holder = clear("Unlock", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(0, u.top),
			Size = UDim2.fromOffset(width, u.height),
			ZIndex = 8,
			Parent = centre,
		})
		local face: Frame = Create("Frame", {
			Name = "Face",
			Size = UDim2.new(1, 0, 1, bands.drop - u.border),
			BorderSizePixel = 0,
			ZIndex = 8,
			Parent = holder,
		})
		Theme.foam(
			face,
			{
				radius = u.height / 2,
				stroke = u.border,
				inner = true,
				drop = bands.drop,
				colors = { face = color(u.color) },
			} :: any
		)
		picture("Gift", "img.icon.gift", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(u.border + u.padLeft, u.height / 2),
			Size = UDim2.fromOffset(u.gift, u.gift),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 9,
			Parent = holder,
		})
		local itemColor = color(u.itemColor)
		local label = Theme.label({
			Name = "Text",
			Text = prefix
				.. string.format('<font color="#%s">%s</font>', itemColor:ToHex(), (string.gsub(item, "[<>&]", ""))),
			RichText = true,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(u.border + u.padLeft + u.gift + u.gap, u.height / 2),
			Size = UDim2.fromOffset(textSize.X + MEASURE_MARGIN_PX, textSize.Y),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 9,
			Parent = holder,
		}, "Small", nil, WHITE)
		oneLine(label)
		unlockHolder = holder
	end

	-- The entrances (L:932-939); every part shows its first frame from the start (fill: both).
	track(pop, LOOK.badge.frames, b.ms, 0, b.curve)
	if not reduced then
		track(ringHolder, ring.frames, ring.ms, ring.delayMs, ring.curve)
		for i, bar in rayHolders do
			track(bar, rays.frames, rays.ms, rays.delayMs + ((i - 1) % 2) * rays.oddDelayMs, rays.curve)
		end
	else
		ringHolder.Visible = false
		for _, bar in rayHolders do
			bar.Visible = false
		end
	end
	track(oldNumber, LOOK.old.frames, LOOK.old.ms, LOOK.old.delayMs, LOOK.old.curve)
	track(newNumber, LOOK.new.frames, LOOK.new.ms, LOOK.new.delayMs, LOOK.new.curve)
	track(ribbon, r.frames, r.ms, r.delayMs, r.curve)
	local unlockTrack: Track? = nil
	if unlockHolder then
		local u = LOOK.unlock
		unlockTrack = track(unlockHolder, u.frames, u.ms, u.delayMs, u.curve)
	end

	-- The driver: every track at show time t, the cues, the stripes and the gloss; the flight at the hold.
	local elapsed = 0
	local cueList = LevelUpShow.cues(hasUnlock)
	local nextCue = 1
	local flown = false
	local handle: Scheduler.Handle? = nil
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		if handle then
			handle:disconnect()
		end
		root:Destroy()
		if playing and playing.root == root then
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
		if name == "main" and not reduced then
			for _, entry in FX.rings do
				task.delay(entry.delayMs / 1000, function()
					if not done then
						UiFx.ring(fly, color(entry.color), entry.size)
					end
				end)
			end
			local sparks = table.clone(FX.sparks) :: any
			sparks.colors = UiFx.colors(FX.sparks.colors)
			UiFx.sparks(fly, sparks)
			UiFx.jolt(centre, FX.jolt)
		end
	end
	-- L:946-951: to the Grip bar (its left + toX, top + toY, in base px from the badge's centre).
	local function flyOut()
		local f = LOOK.fly
		local dx, dy = 0, f.fallbackDy
		local target = spec.target and spec.target()
		local s = scale.Scale
		if target and target.AbsoluteSize.X > 0 and s > 0 then
			local from = fly.AbsolutePosition + fly.AbsoluteSize / 2
			local to = target.AbsolutePosition + Vector2.new(f.toX, f.toY) * s
			dx, dy = (to.X - from.X) / s, (to.Y - from.Y) / s
		end
		track(fly, LevelUpShow.flightFrames(dx, dy), f.ms, elapsed * 1000, f.curve)
		local drop = LOOK.drop
		local dropFrames = drop.frames :: { any }
		track(ribbon, dropFrames, drop.ms, elapsed * 1000, drop.curve)
		if unlockHolder then
			track(unlockHolder, dropFrames, drop.ms, elapsed * 1000, drop.curve)
		end
		-- The entrances of the same holders are done; their newer tracks take over.
		for index = #tracks, 1, -1 do
			local item = tracks[index]
			if item == unlockTrack or (item.frames == r.frames) then
				table.remove(tracks, index)
			end
		end
	end
	local function frameAt(t: number)
		local ms = t * 1000
		for _, item in tracks do
			local u = if ms < item.delayMs
				then 0
				elseif reduced or item.ms <= 0 then 1
				else math.min((ms - item.delayMs) / item.ms, 1)
			local pose = Tweens.poseAt(item.frames, u, "linear", item.curve)
			local fade = item.fade
			if fade then
				fade:setAlpha(pose.alpha or 1)
			end
			local poser = item.poser
			if poser and not reduced then
				poser:set(motionOf({ pose })[1])
			end
		end
		if not reduced then
			spin.Rotation = (t / LOOK.badge.spinS) * 360 % 360
			local gu = math.clamp((ms - g.delayMs) / g.ms, 0, 1)
			local eased = Tweens.curve(g.curve)(gu)
			glossGradient.Offset = Vector2.new(glossFrom + (glossTo - glossFrom) * eased, 0)
		end
		scale.Scale = spec.uiScale()
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
		if not flown and elapsed * 1000 >= hold then
			flown = true
			flyOut()
		end
		if elapsed * 1000 >= life then
			finish()
			return false
		end
		frameAt(elapsed)
		return true
	end, "render")
	root.Parent = spec.layer
	playing = { root = root, stop = finish }
end

return LevelUpShow
