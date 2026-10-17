--!strict
-- QuestPop (client only). UI FINAL R9 (plan work/ui/PLAN.md R9 "Quest-complete pop", G9.1-G9.3; `H:n` = "Squishy Duels
-- HUD.dc.html" line n; Config.UI.Sticker.qpop, Config.UI.motion.qpop): the design's quest-complete pop (H:161-162,
-- H:739), drawn in the HUD quest tracker's slot: at its top-right corner (right 0, top 0), above it, while the tracker
-- itself fades out for the pop's 2.8 s (the slot shows only the pop, as in the design) and comes back after.
--   QuestPop.show({ anchor = trackerRoot, title = "Squeeze 50 times", onChime = function() ... end })
--   QuestPop.stop()
-- The look (H:162): 60 + the 5 px lip, border 4, full radius, the mint #6FE8BC -> #20A574 with the 3 px highlight at
-- .45, padding 0 18 0 8, the check 42, gap 10; the text column (gap 3): "QUEST COMPLETE" (the qpopTag role, 13 px ->
-- 16, #E6FFF4; its letter-spacing is not drawn, RL2) over the quest's title (qpopTitle, 19 px, stroke 5); its width
-- measured (no AutomaticSize). Never a tap target (H:162 pointer-events: none).
-- The motion: sdQPop (H:67, 2.8 s `ease` per keyframe) on its pose holder with the fade over the whole pop; removed at
-- lifeMs. onChime runs chimeDelayMs (150) after it shows (H:739: the chime, the caller's ui.toast). A new pop replaces
-- the old one and restarts its 2.8 s. ReducedMotion: no pose, the fade in and out at most reducedMotionMaxFadeMs.
-- Pure: QuestPop.width(tagWidth, titleWidth) (base px).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local IconGlyph = require(UI.Components.IconGlyph)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Spec = {
	anchor: GuiObject, -- the tracker (Hud_QuestTracker): the pop sits on its top-right corner
	title: string,
	onChime: (() -> ())?,
}

type Current = {
	pop: Frame,
	handle: Scheduler.Handle,
	trackerFade: Tweens.FadeGroup,
	chime: thread?,
}

-- Constants

local LOOK = Config.UI.Sticker.qpop
local MOTION = Config.UI.motion.qpop
local SURFACE = Config.UI.Sticker.surfaces.qpop -- H:162: inset 0 3px 0 rgba(255,255,255,.45)
local TAG_ROLE = "qpopTag"
local TITLE_ROLE = "qpopTitle"
local TAG_KIND: Theme.TextKind = "Small" -- qpopTag's kind (13 px -> 16)
local TITLE_KIND: Theme.TextKind = "D19" -- qpopTitle's kind (19 px)
local CHECK_KEY = "img.icon.check" -- H:162
local LIFE = MOTION.lifeMs / 1000
local REDUCED_FADE = Config.UI.motion.reducedMotionMaxFadeMs / 1000
local MEASURE_MARGIN_PX = 2
local WHITE = Color3.new(1, 1, 1)
local POP_Z = 5 -- above the tracker's own parts

-- Module table

local QuestPop = {}

-- Private

local current: Current? = nil

-- Public

-- The pop's width (base px) for its two lines' widths: border, padding 0 18 0 8, the check 42, gap 10, the wider line.
function QuestPop.width(tagWidth: number, titleWidth: number): number
	local text = math.max(tagWidth, titleWidth, 0)
	return 2 * LOOK.border + LOOK.padLeft + LOOK.check + LOOK.gap + text + LOOK.padRight
end

-- Ends the pop now (the tracker comes back).
function QuestPop.stop()
	local shown = current
	current = nil
	if shown == nil then
		return
	end
	shown.handle:disconnect()
	if shown.chime then
		task.cancel(shown.chime)
	end
	shown.trackerFade:restore()
	shown.pop:Destroy()
end

function QuestPop.show(spec: Spec)
	QuestPop.stop()
	local anchor = spec.anchor
	-- The tracker fades out under the pop (G9.3): its own parts, made before the pop exists.
	local trackerFade = Tweens.fadeGroup(anchor)
	trackerFade:setAlpha(0)
	local tagText = Strings.quest.completeTag
	local tagWidth = math.ceil(Theme.textWidth(tagText, TAG_KIND)) + MEASURE_MARGIN_PX
	local titleWidth = math.ceil(Theme.textWidth(spec.title, TITLE_KIND)) + MEASURE_MARGIN_PX
	local tagHeight = math.ceil(Theme.lineHeight(TAG_KIND))
	local titleHeight = math.ceil(Theme.lineHeight(TITLE_KIND))
	local pop: Frame = Create("Frame", {
		Name = "Hud_QuestPop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(QuestPop.width(tagWidth, titleWidth), LOOK.face + LOOK.lip),
		Active = false,
		ZIndex = POP_Z,
	})
	local pose: Frame = Create("Frame", {
		Name = "SD_Pop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = POP_Z,
		Parent = pop,
	})
	local face: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = POP_Z,
		Parent = pose,
	})
	local top, bottom = Palette.StickerToastMintTop, Palette.StickerToastMintEnd
	local bands = Layout.stickerBands(LOOK.border, SURFACE.highlightPx, 0, LOOK.lip)
	Theme.foam(face, {
		radius = LOOK.face,
		stroke = LOOK.border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		colors = {
			face = top,
			faceEnd = bottom,
			top = top:Lerp(WHITE, SURFACE.highlightAlpha),
			drop = Theme.Colors.inkUI,
		},
	})
	local check = IconGlyph.image(CHECK_KEY, { name = "Check", sizePx = LOOK.check, parent = face })
	check.AnchorPoint = Vector2.new(0, 0.5)
	check.Position = UDim2.new(0, LOOK.border + LOOK.padLeft, 0.5, -LOOK.lip / 2)
	check.ZIndex = POP_Z
	local left = LOOK.border + LOOK.padLeft + LOOK.check + LOOK.gap
	local columnHeight = tagHeight + LOOK.textGap + titleHeight
	local column: Frame = Create("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, left, 0.5, -LOOK.lip / 2),
		Size = UDim2.fromOffset(math.max(tagWidth, titleWidth), columnHeight),
		ZIndex = POP_Z,
		Parent = face,
	})
	local tag = Theme.label({
		Name = "Tag",
		Text = tagText,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(tagWidth, tagHeight),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = POP_Z,
		Parent = column,
	}, TAG_KIND)
	Theme.stickerText(tag, TAG_ROLE)
	tag.TextWrapped = false
	local title = Theme.label({
		Name = "Title",
		Text = spec.title,
		AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.fromOffset(0, tagHeight + LOOK.textGap),
		Size = UDim2.fromOffset(titleWidth, titleHeight),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = POP_Z,
		Parent = column,
	}, TITLE_KIND)
	Theme.stickerText(title, TITLE_ROLE)
	title.TextWrapped = false
	pop.Parent = anchor

	-- sdQPop (H:67) on the pose holder, the fade over the whole pop; removed at lifeMs.
	local poser = Tweens.poser(pose)
	local fade = Tweens.fadeGroup(pose)
	local function frameAt(t: number)
		if Tweens.reducedMotion() then
			fade:setAlpha(math.clamp(math.min(t, LIFE - t) / REDUCED_FADE, 0, 1))
			poser:rest()
			return
		end
		local at = Tweens.poseAt((MOTION.frames :: any) :: { Tweens.Pose }, math.clamp(t / LIFE, 0, 1), MOTION.curve)
		fade:setAlpha(at.alpha or 1)
		at.alpha = nil
		poser:set(at)
	end
	frameAt(0)
	local elapsed = 0
	local handle = Scheduler.add(function(dt: number): boolean
		if pop.Parent == nil then
			return false
		end
		elapsed += dt
		if elapsed >= LIFE then
			task.defer(function()
				local shown = current
				if shown and shown.pop == pop then
					QuestPop.stop()
				end
			end)
			return false
		end
		frameAt(elapsed)
		return true
	end, "render")
	local onChime = spec.onChime
	current = {
		pop = pop,
		handle = handle,
		trackerFade = trackerFade,
		chime = if onChime then task.delay(LOOK.chimeDelayMs / 1000, onChime) else nil,
	}
end

return QuestPop
