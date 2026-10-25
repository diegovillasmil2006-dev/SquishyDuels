--!strict
-- MatchFoundShow (client only). Round 2 of the match flow (2026-10-25, owner: "build round 2 like that, 1v1 included";
-- `L:n` = "Squishy Duels LOBBY HUD.dc.html" line n, ALL HUDS zip: the markup L:626-741, the timeline L:1024-1051):
-- Diego's MATCH FOUND show over the lobby when the queue starts a duel or a match (HudController plays it on
-- StateController.MatchFoundReceived, after the waiting bar's fill-up; the server holds the teleport meanwhile).
--   local show = MatchFoundShow.play({ layer = gui, view = view, you = userId, play = function(key, fallback) end,
--     fxScale = 1 / uiScale, ready = function() return inTheArena end, onDone = function() end })
--   show:close()   (at once, quietly)
-- * The stage: the design's 1440 x 810 px, centred, under a UIScale (stageScale: the design's sp(), L:629); the dim
--   covers the screen and 80 px past it (L:628). Every number is Config.UI.MatchFound's (or Fx.events.matchFound's).
-- * In order: the dim fades in; the charge (UiFx.converge into the centre, the orb, its sound); the impact at .47 s
--   (the white flash over the screen, the rays and warm glow growing in, then turning; the three rings, the burst, the
--   rain, the jolt, its sound); the ribbon unrolling from its middle with its shine, MATCH FOUND! dropping in letter by
--   letter then waving; the tails; the emblem slamming down then bobbing; the mode pill rising; the twinkles; the
--   players row: DUEL and TEAM each team sliding in from its side and VS slamming in between (its sound, ring, burst and
--   jolt), FREE FOR ALL each tile popping in (with a second run of letter notes and a chime); your tile wears YOU. At 3
--   s the block flies up (whoosh); the dim, rays and row stay until spec.ready() says the arena is on (the match or duel
--   past Positioning) or exit.holdMaxS, then fade out and the show ends (onDone).
-- * Round 3 of the match flow (2026-10-25, the map vote for Team and Free for All, L:1056-1147): with a vote (spec.vote,
--   or show:setVote later) the block's flight waits for the vote (Config.UI.MatchFound.vote.leadMs before it opens),
--   then the rays move down and dim, the row moves down and UI/MatchVoteBoard runs the vote on the stage; 3.1 s after
--   the reveal the whole show fades out growing a little (.42 s ease-in) and spec.toast says where the teleport goes.
--   A vote that ends early ({}: called off, or you left) fades the show out at once.
-- * The row (order): DUEL you on the left (red) against the opponent (blue); TEAM the Strawberry half on the left, the
--   Blueberry half on the right (Config.Match.teamNames), as the waiting bar draws them; FREE FOR ALL you first.
-- * A tile: the team's (or Free for All slot's) colours (MatchHudFormat.playerLook), the squishy (SquishyImage), the
--   Grip level badge; names are not drawn (the design keeps them for a tooltip).
-- * Under ReducedMotion (Anim/Tweens): no white flash and no UiFx effects; the keyframes only fade; the loops rest.
-- Pure (unit-tested): stageScale(screen), order(view, you), chipGradient(mode, width, height).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local Create = require(script.Parent.Create)
local Layout = require(script.Parent.Layout)
local MatchHudFormat = require(script.Parent.MatchHudFormat)
local SegmentedTabs = require(script.Parent.Components.SegmentedTabs)
local SquishyImage = require(script.Parent.Components.SquishyImage)
local Theme = require(script.Parent.Theme)
local MatchVoteBoard = require(script.Parent.MatchVoteBoard)
local UiFx = require(script.Parent.UiFx)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type View = Types.MatchFoundView

export type Spec = {
	layer: ScreenGui, -- Config.UI.MatchFound.layer
	view: View,
	you: number, -- the local player's userId
	play: (key: string, fallback: string, pitch: number?) -> (), -- a sound (its look-alike while its id is missing)
	fxScale: number?, -- 1 / the effect layer's UI scale (UiFx sizes are its base px)
	ready: (() -> boolean)?, -- the arena is on: the show may go (default: at once after the flight)
	onDone: (() -> ())?,
	-- Round 3 of the match flow: the map vote (Team / Free for All), the vote's tap, the server's clock and the toast.
	vote: Types.MatchVoteView?,
	castVote: ((card: number) -> ())?,
	now: (() -> number)?, -- default Workspace:GetServerTimeNow
	toast: ((text: string) -> ())?,
}

export type Show = {
	root: Frame,
	close: (self: Show) -> (),
	setVote: (self: Show, view: Types.MatchVoteView) -> (), -- round 3: every MatchVoteState ({} = over)
}

-- One tile of the row (order): its player, colours, where it comes in from and when.
export type Entry = {
	player: Types.MatchFoundPlayer,
	team: number?, -- DUEL and TEAM: 1 (left) / 2 (right)
	slot: number?, -- FREE FOR ALL: the colour slot (1..)
	from: "left" | "right" | "pop",
	delayMs: number,
}
export type Order = { entries: { Entry }, vsAfter: number? }

-- Constants

local MF = Config.UI.MatchFound
local VOTE = MF.vote
local FX = Config.UI.Fx.events.matchFound
local ROSTER = MF.roster
local STAGE_W, STAGE_H = MF.stage.width, MF.stage.height
local INK = Palette.StickerInk
local WHITE = Palette.White
local BLACK = Color3.new(0, 0, 0)
local PICKER = Config.UI.Sticker.hud.picker
local LETTER_WAVE = Config.UI.motion.loops.lvWave.frames
local MEASURE_MARGIN_PX = 6 -- scaled text draws a little wider than TextService measures (Theme.textBoundsAt)
local ROW_HEIGHT = ROSTER.vs.px -- the row's items are centred on the VS badge (L:722 align-items center)

-- Module table

local MatchFoundShow = {}

-- Private

local log = Log.new("MatchFound")

local function color(name: string): Color3
	local value = (Palette :: any)[name]
	return if typeof(value) == "Color3" then value else WHITE
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

local function inner(stroke: UIStroke)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
end

-- Theme.text turns wrapping on; under a UIScale a line draws wider than TextService measures: one line each.
local function oneLine(label: TextLabel)
	label.TextWrapped = false
	for _, text in label:GetDescendants() do
		if text:IsA("TextLabel") then
			text.TextWrapped = false
		end
	end
end

-- The frames without their alpha (the motion of a track whose fade is a whole group's, Tweens.fadeGroup).
local function motionOf(frames: { Tweens.Pose }): { Tweens.Pose }
	local out: { Tweens.Pose } = {}
	for _, frame in frames do
		local copy = table.clone(frame)
		copy.alpha = nil
		table.insert(out, copy)
	end
	return out
end

local function alphaAt(frames: { Tweens.Pose }, u: number, curve: string?): number
	return Tweens.poseAt(frames, math.clamp(u, 0, 1), curve).alpha or 1
end

-- Tweens.fadeGroup leaves a ViewportFrame's picture alone (SquishyImage's 3D stand-in): these fade with it.
local function viewportsIn(holder: Instance): { ViewportFrame }
	local list: { ViewportFrame } = {}
	for _, d in holder:GetDescendants() do
		if d:IsA("ViewportFrame") then
			table.insert(list, d)
		end
	end
	return list
end

local function fadeViewports(list: { ViewportFrame }, alpha: number)
	for _, vp in list do
		vp.ImageTransparency = 1 - alpha
	end
end

-- Public: pure -------------------------------------------------------------------------------------------------------

-- The stage's scale on a screen of `screen` px: the whole 1440 x 810 design fits (L:629).
function MatchFoundShow.stageScale(screen: Vector2): number
	return math.max(0.05, math.min(screen.X / STAGE_W, screen.Y / STAGE_H))
end

-- The players row (see the header): its tiles in order with their side and entrance (L:1412-1414: a team's tiles
-- nearest the middle first, .05 s apart from 1.2 s; Free for All in order), and the tile VS follows (nil: none).
function MatchFoundShow.order(view: Types.MatchFoundView, you: number): Order
	local start, step = ROSTER.startMs, ROSTER.stepMs
	local entries: { Entry } = {}
	if view.mode == "ffa" then
		local list = table.clone(view.players)
		for index, player in list do
			if player.userId == you and index > 1 then
				table.remove(list, index)
				table.insert(list, 1, player)
				break
			end
		end
		for index, player in list do
			table.insert(entries, { player = player, slot = index, from = "pop", delayMs = start + (index - 1) * step })
		end
		return { entries = entries, vsAfter = nil }
	end
	local left, right = {}, {}
	if view.mode == "tdm" then
		for _, player in view.players do
			table.insert(if player.team == 2 then right else left, player)
		end
	else -- "1v1": you on the left
		for _, player in view.players do
			table.insert(if player.userId == you and #left == 0 then left else right, player)
		end
		if #left == 0 and #right > 0 then
			table.insert(left, table.remove(right, 1))
		end
	end
	for index, player in left do
		table.insert(entries, { player = player, team = 1, from = "left", delayMs = start + (#left - index) * step })
	end
	for index, player in right do
		table.insert(entries, { player = player, team = 2, from = "right", delayMs = start + (index - 1) * step })
	end
	return { entries = entries, vsAfter = if #left > 0 and #right > 0 then #left else nil }
end

-- The mode chip's gradient (LOBBY HUD L:763-765 MODES[].bg; the waiting bar's chip and the show's pill) on a chip
-- `width` x `height` px: DUEL the DUEL button's pink (180deg), TEAM red -> blue at 100deg, FREE FOR ALL yellow (180deg).
-- Returns the colours and the UIGradient Rotation.
function MatchFoundShow.chipGradient(mode: string, width: number, height: number): (ColorSequence, number)
	local key = ColorSequenceKeypoint.new
	if mode == "tdm" then
		local at = PICKER.tdmStops
		return ColorSequence.new({
			key(at[1], Palette.StickerTdmRedTop),
			key(at[2], Palette.StickerTdmRed),
			key(at[3], Palette.StickerTdmBlue),
			key(at[4], Palette.StickerTdmBlueEnd),
		}),
			SegmentedTabs.gradientRotation(PICKER.tdmRotation, width, height)
	elseif mode == "ffa" then
		return ColorSequence.new(Palette.StickerYellowTop, Palette.StickerGoldMid), PICKER.ffaRotation
	end
	local pink = Theme.accent("pink")
	return ColorSequence.new({ key(0, pink.top), key(pink.midAt :: number, pink.face), key(1, pink.shade) }),
		PICKER.ffaRotation
end

-- Public -------------------------------------------------------------------------------------------------------------

function MatchFoundShow.play(spec: Spec): Show
	local view = spec.view
	local mode = view.mode
	local teams = mode ~= "ffa"
	local handles: { Scheduler.Handle } = {}
	local loops: { UiIdle.Handle } = {}
	local closed = false
	local screen = spec.layer.AbsoluteSize
	local camera = Workspace.CurrentCamera
	if screen.X <= 0 and camera then
		screen = camera.ViewportSize -- a layer made this frame may not be measured yet
	end
	local k = MatchFoundShow.stageScale(screen)
	local fxK = k * (spec.fxScale or 1)
	local reduced = Tweens.reducedMotion()

	local function add(effect: any)
		table.insert(handles, Scheduler.add(effect, "render"))
	end
	local function loop(handle: UiIdle.Handle?)
		if handle then
			table.insert(loops, handle)
		end
	end
	-- A design @keyframes on `holder`: its motion (Tweens.keyframes) and its fade over the holder and all inside it (the
	-- holder is built opaque: the fade scales what it has).
	local function track(holder: GuiObject, frames: any, ms: number, delayMs: number, curve: string?)
		add(Tweens.keyframes(holder, motionOf(frames), { ms = ms, delayMs = delayMs, curve = curve }))
		local fade = Tweens.fadeGroup(holder)
		local viewports = viewportsIn(holder)
		local first = alphaAt(frames, 0, curve)
		fade:setAlpha(first)
		fadeViewports(viewports, first)
		local elapsed = 0
		add(function(dt: number): boolean
			elapsed += dt
			local t = elapsed * 1000 - delayMs
			if t < 0 then
				return true
			end
			local u = if reduced or ms <= 0 then 1 else t / ms
			local alpha = alphaAt(frames, u, curve)
			fade:setAlpha(alpha)
			fadeViewports(viewports, alpha)
			return u < 1
		end)
	end

	local root: Frame = Create("Frame", {
		Name = "SD_MatchFound",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = true, -- L:627 pointer-events auto
		ZIndex = 1,
	})
	local pad = MF.backdrop.pad
	local dim = picture("Dim", "img.mf.backdrop", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 2 * pad, 1, 2 * pad),
		ZIndex = 1,
		Parent = root,
	})
	local stage = clear("Stage", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(STAGE_W, STAGE_H),
		ZIndex = 2,
		Parent = root,
	})
	local stageScale: UIScale = Create("UIScale", { Scale = k, Parent = stage })
	local white: Frame = Create("Frame", {
		Name = "White",
		BackgroundColor3 = color(MF.white.color),
		BackgroundTransparency = if reduced then 1 else 0, -- its track fades it from 0 (none under ReducedMotion)
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = root,
	})
	-- Points the effects aim at (UiFx needs a drawn size).
	local function anchor(name: string, x: number, y: number): Frame
		return clear(name, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(2, 2),
			Parent = stage,
		})
	end
	local centre = anchor("Centre", MF.centre.x, MF.centre.y)
	local vsPoint = anchor("VsPoint", STAGE_W / 2, ROSTER.y + ROW_HEIGHT / 2)

	-- The rays group (L:630-637).
	local raysGroup = clear("Rays", { Position = UDim2.fromOffset(MF.centre.x, MF.centre.y), Parent = stage })
	local function disc(name: string, key: string, px: number, z: number): ImageLabel
		return picture(name, key, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(px, px),
			ZIndex = z,
			Parent = raysGroup,
		})
	end
	local glow = disc("Glow", "img.mf.glow", MF.glow.px, 1)
	local raysHolder = clear("RaysIn", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(MF.rays.px, MF.rays.px),
		ZIndex = 2,
		Parent = raysGroup,
	})
	local rays = picture("Spin", "img.mf.rays", { Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = raysHolder })
	local orb = disc("Orb", "img.mf.orb", MF.orb.px, 3)
	local flash = disc("Flash", "img.mf.flash", MF.flash.px, 4)

	-- The found block (L:639-662), turned about (720, originY).
	local block = clear("Block", {
		AnchorPoint = Vector2.new(0.5, MF.block.originY / MF.block.height),
		Position = UDim2.fromOffset(STAGE_W / 2, MF.block.originY),
		Size = UDim2.fromOffset(STAGE_W, MF.block.height),
		ZIndex = 3,
		Parent = stage,
	})
	local tails = MF.tails
	local tailHolders: { Frame } = {}
	for _, side in { "L", "R" } do
		local x = if side == "L" then tails.leftX else tails.rightX
		local holder = clear("Tail" .. side, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + tails.width / 2, tails.y + tails.height / 2),
			Size = UDim2.fromOffset(tails.width, tails.height),
			ZIndex = 1,
			Parent = block,
		})
		picture("Tail", "img.mf.tail" .. side, { Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = holder })
		table.insert(tailHolders, holder)
	end
	local ribbon = MF.ribbon
	local face = ribbon.face
	local faceCentre = Vector2.new(face.x + face.width / 2, face.y + face.height / 2)
	local clip = clear("RibbonClip", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(faceCentre.X, faceCentre.Y),
		Size = UDim2.fromOffset(0, face.height),
		ClipsDescendants = true,
		ZIndex = 2,
		Parent = block,
	})
	local content = clear("Face", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(face.width, face.height),
		ZIndex = 2,
		Parent = clip,
	})
	local pic = ribbon.picture
	local banner = picture("Banner", "img.mf.banner", {
		Position = UDim2.fromOffset(-pic.faceX, -pic.faceY),
		Size = UDim2.fromOffset(pic.width, pic.height),
		ImageTransparency = 1,
		ZIndex = 2,
		Parent = content,
	})
	-- L:648 sdShine: a white band (alpha .75 at its middle) crossing the face inside its border, held to 55%.
	local shine = ribbon.shine
	local shineFace: Frame = Create("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, -2 * ribbon.border, 1, -2 * ribbon.border),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 0, -- clear but for the band (its gradient), which starts off the face
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = content,
	})
	Theme.corner(ribbon.radius - ribbon.border, shineFace)
	local band = shine.width / (face.width - 2 * ribbon.border)
	local shineGradient: UIGradient = Create("UIGradient", {
		Rotation = SegmentedTabs.gradientRotation(shine.rotation, face.width, face.height),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5 - band / 2, 1),
			NumberSequenceKeypoint.new(0.5, shine.alpha),
			NumberSequenceKeypoint.new(0.5 + band / 2, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Offset = Vector2.new(-0.5 - band * 1.5, 0),
		Parent = shineFace,
	})

	-- The letters (L:651): each in a cell the row lays out, waving in a holder, dropping in on its own holder.
	local letterRow = clear("Letters", { Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = content })
	Create("UIPadding", { PaddingBottom = UDim.new(0, MF.letters.padBottom), Parent = letterRow })
	Theme.list(
		Enum.FillDirection.Horizontal,
		0,
		letterRow,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local letters = MF.letters
	local letterIndex = 0
	local letterPops: { Frame } = {}
	for _, code in utf8.codes(Strings.hud.matchFound) do
		local char = utf8.char(code)
		letterIndex += 1
		local bounds = Theme.textBoundsAt(char, "FoundTitle", nil, k)
		local width = if char == " " then letters.spacePx else bounds.X + MEASURE_MARGIN_PX
		local cell = clear("Letter" .. letterIndex, {
			Size = UDim2.fromOffset(width, bounds.Y),
			LayoutOrder = letterIndex,
			Parent = letterRow,
		})
		if char ~= " " then
			local wave = clear("Wave", { Size = UDim2.fromScale(1, 1), Parent = cell })
			local pop = clear("Pop", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
				Parent = wave,
			})
			local label = Theme.label({
				Name = "Char",
				Text = char,
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = pop,
			}, "FoundTitle")
			Theme.stickerText(label, "foundLetter")
			oneLine(label)
			loop(UiIdle.addFrames(wave, LETTER_WAVE, {
				periodS = letters.wave.periodS,
				delayS = letters.wave.delayS + (letterIndex - 1) * letters.wave.stepS,
				curve = "easeInOut",
			}))
			table.insert(letterPops, pop)
		end
	end

	-- The emblem (L:655-657): slammed in, then bobbing, over its drop shadow.
	local em = MF.emblem
	local emblem = clear("Emblem", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(em.x + em.px / 2, em.y + em.px / 2),
		Size = UDim2.fromOffset(em.px, em.px),
		ZIndex = 5,
		Parent = block,
	})
	local bob = clear("Bob", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = emblem })
	picture("Shadow", "img.nav.duel", {
		Position = UDim2.fromOffset(0, em.shadowY),
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		ImageColor3 = BLACK,
		ImageTransparency = 1 - em.shadowAlpha,
		ZIndex = 5,
		Parent = bob,
	})
	picture("Image", "img.nav.duel", {
		Size = UDim2.fromScale(1, 1),
		ScaleType = Enum.ScaleType.Fit,
		ZIndex = 6,
		Parent = bob,
	})
	loop(UiIdle.add(bob, "bob", { periodS = em.bobS, delayS = em.bobDelayS }))

	-- The mode pill (L:658-661).
	local pillSpec = MF.pill
	local names, chips = Strings.hud.foundShow.names, Strings.hud.foundShow.chips
	local chipText, nameText = chips[mode] or "", names[mode] or ""
	local chipSize = Theme.textBoundsAt(chipText, "FoundChip", nil, k)
	local nameSize = Theme.textBoundsAt(nameText, "FoundName", nil, k)
	local chipW = chipSize.X + MEASURE_MARGIN_PX + 2 * pillSpec.chipPad
	local nameW = nameSize.X + MEASURE_MARGIN_PX
	local pillW = 2 * pillSpec.border + pillSpec.padLeft + chipW + pillSpec.gap + nameW + pillSpec.padRight
	local pillBands = Layout.stickerBands(pillSpec.border, pillSpec.highlightPx, 0, pillSpec.lip)
	local pillHolder = clear("Pill", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STAGE_W / 2, pillSpec.y),
		Size = UDim2.fromOffset(pillW, pillSpec.height + pillBands.drop),
		ZIndex = 4,
		Parent = block,
	})
	local pillFace: Frame = Create("Frame", {
		Name = "Face",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
		Parent = pillHolder,
	})
	local well = color(pillSpec.color)
	Theme.foam(pillFace, {
		radius = (pillSpec.height + pillBands.drop) / 2,
		stroke = pillSpec.border,
		inner = true,
		top = pillBands.top,
		drop = pillBands.drop,
		colors = { face = well, top = well:Lerp(WHITE, pillSpec.highlightAlpha) },
	})
	local chip: Frame = Create("Frame", {
		Name = "Chip",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(pillSpec.border + pillSpec.padLeft, pillSpec.height / 2),
		Size = UDim2.fromOffset(chipW, pillSpec.chipHeight),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 5,
		Parent = pillHolder,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = chip })
	inner(Theme.stroke(INK, pillSpec.chipBorder, chip))
	local chipColors, chipRotation = MatchFoundShow.chipGradient(mode, chipW, pillSpec.chipHeight)
	Create("UIGradient", { Color = chipColors, Rotation = chipRotation, Parent = chip })
	local chipLabel = Theme.label({
		Name = "Text",
		Text = chipText,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 6,
		Parent = chip,
	}, "FoundChip")
	Theme.stickerText(chipLabel, "foundChip")
	oneLine(chipLabel)
	local nameLabel = Theme.label({
		Name = "Mode",
		Text = nameText,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromOffset(pillSpec.border + pillSpec.padLeft + chipW + pillSpec.gap, pillSpec.height / 2),
		Size = UDim2.fromOffset(nameW, nameSize.Y),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 5,
		Parent = pillHolder,
	}, "FoundName", nil, WHITE)
	oneLine(nameLabel)

	-- The twinkles (L:662).
	local twinkles: { UiIdle.Handle } = {}
	for index, row in MF.twinkles do
		local x, y, px, tint, delay = row[1], row[2], row[3], row[4], row[5]
		local star = picture("Twinkle" .. index, "img.duel.star", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(x + px / 2, y + px / 2),
			Size = UDim2.fromOffset(px, px),
			ImageColor3 = color(tint),
			ZIndex = 3,
			Parent = block,
		})
		local handle = UiIdle.add(star, "twinkle", { periodS = MF.twinkleS, delayS = delay })
		if handle then
			table.insert(twinkles, handle)
		end
	end

	-- The players row (L:722-736).
	local voters: { [number]: MatchVoteBoard.Voter } = {} -- round 3: each tile, for the map vote's chips
	local order = MatchFoundShow.order(view, spec.you)
	local row = clear("Players", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(STAGE_W / 2, ROSTER.y),
		Size = UDim2.fromOffset(STAGE_W, ROW_HEIGHT),
		ZIndex = 4,
		Parent = stage,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		ROSTER.gap,
		row,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local tileBands = Layout.stickerBands(ROSTER.border, ROSTER.highlightPx, ROSTER.shadePx, ROSTER.lip)
	local function tile(entry: Entry, index: number): Frame
		local look = if entry.team
			then MatchHudFormat.playerLook("tdm", Config.Match.teamNames[entry.team], nil)
			else MatchHudFormat.playerLook("ffa", nil, entry.slot)
		local cell = clear("Tile" .. index, {
			Size = UDim2.fromOffset(ROSTER.tile, ROSTER.tile + tileBands.drop),
			LayoutOrder = 2 * index,
			Parent = row,
		})
		local holder = clear("In", { Size = UDim2.fromScale(1, 1), Parent = cell })
		local box: Frame = Create("Frame", {
			Name = "Box",
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 4,
			Parent = holder,
		})
		local colors: Theme.StickerColors = {
			face = look.top,
			mid = look.mid,
			midAt = if look.mid then Config.UI.Sticker.hud.slots.midAt else nil,
			faceEnd = look.faceEnd,
			top = look.top:Lerp(WHITE, ROSTER.highlightAlpha),
			bevel = look.faceEnd:Lerp(BLACK, ROSTER.shadeAlpha),
		}
		Theme.foam(box, {
			radius = ROSTER.radius,
			stroke = ROSTER.border,
			inner = true,
			top = tileBands.top,
			bevel = tileBands.bevel,
			drop = tileBands.drop,
			colors = colors :: any, -- a StickerColors as a FoamColors (Theme.surfaceColors does the same)
		})
		local catalogId = entry.player.squishy
		if not Catalog.isValidId(catalogId) then
			catalogId = Catalog.starterId() -- the server's squishy is always known; an old client's catalog may lag
		end
		voters[entry.player.userId] = { tile = holder, colors = colors, squishy = catalogId, team = entry.team }
		local squishy = SquishyImage.new(catalogId, { size = ROSTER.picPx, parent = holder })
		squishy.root.AnchorPoint = Vector2.new(0.5, 0.5)
		squishy.root.Position = UDim2.fromOffset(ROSTER.tile / 2, ROSTER.tile / 2)
		squishy.root.ZIndex = 5
		local lv = ROSTER.level
		local levelText = tostring(entry.player.level)
		local levelSize = Theme.textBoundsAt(levelText, "Small", nil, k)
		local badge: Frame = Create("Frame", {
			Name = "Level",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromOffset(ROSTER.tile - lv.right, ROSTER.tile - lv.bottom),
			Size = UDim2.fromOffset(
				math.max(lv.minWidth, levelSize.X + MEASURE_MARGIN_PX + 2 * (lv.pad + lv.border)),
				lv.height
			),
			BackgroundColor3 = color(MF.pill.color),
			BorderSizePixel = 0,
			ZIndex = 7,
			Parent = holder,
		})
		Theme.corner(lv.radius, badge)
		inner(Theme.stroke(INK, lv.border, badge))
		local levelLabel = Theme.label({
			Name = "Text",
			Text = levelText,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 8,
			Parent = badge,
		}, "Small", nil, WHITE)
		oneLine(levelLabel)
		if entry.player.userId == spec.you then
			local you = ROSTER.you
			local youText = Strings.hud.foundShow.you
			local youSize = Theme.textBoundsAt(youText, "Small", nil, k)
			local youBands = Layout.stickerBands(you.border, 0, 0, you.lip)
			local tagHolder = clear("You", {
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.fromOffset(ROSTER.tile / 2, you.top),
				Size = UDim2.fromOffset(
					youSize.X + MEASURE_MARGIN_PX + 2 * (you.pad + you.border),
					you.height + youBands.drop
				),
				ZIndex = 8,
				Parent = holder,
			})
			local tag: Frame = Create("Frame", {
				Name = "Tag",
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 8,
				Parent = tagHolder,
			})
			Theme.foam(tag, {
				radius = you.radius,
				stroke = you.border,
				inner = true,
				drop = youBands.drop,
				colors = { face = Palette.StickerYellowTop, faceEnd = Palette.StickerYellowEnd },
			})
			local youLabel = Theme.label({
				Name = "Text",
				Text = youText,
				Size = UDim2.new(1, 0, 1, -youBands.drop),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 9,
				Parent = tag,
			}, "Small")
			Theme.stickerText(youLabel, "foundYou")
			oneLine(youLabel)
			loop(UiIdle.add(tag, "bob", { periodS = you.bobS }))
		end
		return holder
	end
	local tileHolders: { { holder: Frame, entry: Entry } } = {}
	for index, entry in order.entries do
		table.insert(tileHolders, { holder = tile(entry, index), entry = entry })
	end
	local vsHolder: Frame? = nil
	local vsAfter = order.vsAfter
	if vsAfter then
		local vs = ROSTER.vs
		local cell = clear("Vs", {
			Size = UDim2.fromOffset(vs.px + 2 * vs.margin, vs.px),
			LayoutOrder = 2 * vsAfter + 1,
			Parent = row,
		})
		local holder = clear("In", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(vs.px, vs.px),
			Parent = cell,
		})
		-- img.mf.vs: the 84 px badge at (8, 8) of its 100 x 106 picture.
		picture("Badge", "img.mf.vs", {
			Position = UDim2.fromOffset(-8, -8),
			Size = UDim2.fromOffset(100, 106),
			ZIndex = 6,
			Parent = holder,
		})
		vsHolder = holder
	end

	-- Motion (every track starts now and holds its first frame through its delay, CSS fill both).
	track(dim, { { at = 0, alpha = 0 }, { at = 1, alpha = 1 } }, MF.backdrop.fadeMs, 0, "easeOut")
	track(glow, MF.raysFrames, MF.glow.ms, MF.glow.delayMs, MF.glow.curve)
	track(raysHolder, MF.raysFrames, MF.rays.ms, MF.rays.delayMs, MF.rays.curve)
	loop(UiIdle.add(rays, "spin", { periodS = MF.rays.spinS }))
	track(orb, MF.orb.frames, MF.orb.ms, 0, MF.orb.curve)
	track(flash, MF.flash.frames, MF.flash.ms, MF.flash.delayMs, MF.flash.curve)
	if not reduced then
		track(white, MF.white.frames, MF.white.ms, MF.white.delayMs, MF.white.curve)
	end
	for index, holder in tailHolders do
		local frames = MF.tailFrames
		if index == 2 then
			frames = {}
			for _, frame in MF.tailFrames do
				local copy = table.clone(frame)
				copy.x = if copy.x then -copy.x else nil
				table.insert(frames, copy)
			end
		end
		track(holder, frames, tails.ms, tails.delayMs, tails.curve)
	end
	for index, pop in letterPops do
		track(pop, letters.frames, letters.ms, letters.delayMs + (index - 1) * letters.stepMs, letters.curve)
	end
	track(emblem, em.frames, em.ms, em.delayMs, em.curve)
	track(pillHolder, pillSpec.frames, pillSpec.ms, pillSpec.delayMs, pillSpec.curve)
	for _, item in tileHolders do
		local entry = item.entry
		if entry.from == "pop" then
			track(item.holder, ROSTER.revealFrames, ROSTER.revealMs, entry.delayMs, ROSTER.revealCurve)
		else
			local frames = ROSTER.slideFrames
			if entry.from == "right" then
				frames = {}
				for _, frame in ROSTER.slideFrames do
					local copy = table.clone(frame)
					copy.x = if copy.x then -copy.x else nil
					copy.rot = if copy.rot then -copy.rot else nil
					table.insert(frames, copy)
				end
			end
			track(item.holder, frames, ROSTER.slideMs, entry.delayMs, ROSTER.slideCurve)
		end
	end
	if vsHolder then
		local vs = ROSTER.vs
		track(vsHolder, ROSTER.vsFrames, vs.ms, vs.delayMs, vs.curve)
	end

	-- The ribbon: alpha and sy on its keyframes, its clip opening from the middle (sdMfUnfurl, L:645).
	do
		local elapsed = 0
		local open = face.width + 2 * ribbon.openPad
		add(function(dt: number): boolean
			elapsed += dt
			local t = elapsed * 1000 - ribbon.delayMs
			local u = if t <= 0 then 0 elseif reduced then 1 else math.min(t / ribbon.ms, 1)
			local pose = Tweens.poseAt(ribbon.frames, u, ribbon.curve)
			local sy = if reduced then 1 else pose.sy or 1
			local alpha = pose.alpha or 1
			local share = if reduced or u >= ribbon.openAt then 1 else Tweens.curve(ribbon.curve)(u / ribbon.openAt)
			clip.Size = UDim2.fromOffset(open * share, face.height + 2 * ribbon.openPad * share)
			content.Size = UDim2.fromOffset(face.width, face.height * sy)
			banner.Size = UDim2.fromOffset(pic.width, pic.height * sy)
			banner.Position = UDim2.fromOffset(-pic.faceX, -pic.faceY * sy)
			banner.ImageTransparency = 1 - alpha
			return u < 1
		end)
	end
	-- The shine: held off the face, then across it (ease-in-out), every periodS from delayS.
	do
		local elapsed = 0
		local from, to = -0.5 - band * 1.5, 0.5 + band * 9.5 -- translateX(-200%) -> 900% of the band (L:29)
		local idle = Config.UI.motion.idle.shine
		add(function(dt: number): boolean
			elapsed += dt
			local t = elapsed - shine.delayS
			if reduced or t < 0 then
				return true -- off the face
			end
			local u = (t / shine.periodS) % 1
			local hold = idle.holdShare
			local eased = if u <= hold then 0 else Tweens.curve(idle.curve)((u - hold) / (1 - hold))
			shineGradient.Offset = Vector2.new(from + (to - from) * eased, 0)
			return true
		end)
	end

	-- The timeline: sounds and effects (L:1036-1051).
	local sounds = MF.sounds
	local events: { { at: number, fn: () -> () } } = {}
	local function at(ms: number, fn: () -> ())
		table.insert(events, { at = ms, fn = fn })
	end
	local function sound(entry: any)
		at(entry.atMs, function()
			spec.play(entry.key, entry.fallback)
		end)
	end
	local function ring(target: GuiObject, list: { any }, baseMs: number)
		for _, r in list do
			at(baseMs + (r.delayMs or 0), function()
				UiFx.ring(target, color(r.color), r.size * fxK)
			end)
		end
	end
	local function burst(target: GuiObject, sparks: any)
		UiFx.sparks(target, {
			n = sparks.n,
			spread = if sparks.spread then sparks.spread * fxK else nil,
			size = if sparks.size then sparks.size * fxK else nil,
			up = if sparks.up then sparks.up * fxK else nil,
			ms = sparks.ms,
			colors = UiFx.colors(sparks.colors),
		})
	end
	sound(sounds.charge)
	at(0, function()
		local c = FX.converge
		UiFx.converge(centre, {
			n = c.n,
			reach = c.reach * fxK,
			size = c.size * fxK,
			ms = c.ms,
			colors = UiFx.colors(c.colors),
		})
	end)
	sound(sounds.impact)
	ring(centre, FX.rings, sounds.impact.atMs)
	at(sounds.impact.atMs, function()
		burst(centre, FX.sparks)
		UiFx.rain(FX.rain)
		UiFx.jolt(stage, FX.jolt * k)
	end)
	sound(sounds.letters)
	sound(sounds.chime)
	if teams and vsHolder then
		sound(sounds.whoosh)
		sound(sounds.vs)
		ring(vsPoint, FX.vs.rings, sounds.vs.atMs)
		at(sounds.vs.atMs, function()
			burst(vsPoint, FX.vs.sparks)
			UiFx.jolt(stage, FX.vs.jolt * k)
		end)
	elseif not teams then
		sound(sounds.lettersSolo)
		sound(sounds.chimeSolo)
	end

	-- Round 3 of the match flow: the map vote's state (see the header).
	local serverNow = spec.now or function(): number
		return Workspace:GetServerTimeNow()
	end
	local voteView: Types.MatchVoteView? = if spec.vote and spec.vote.id ~= nil then spec.vote else nil
	local voteClosed = false
	local board: MatchVoteBoard.Board? = nil
	local exitDue, exited = false, false
	local elapsed = 0
	local fading: Tweens.FadeGroup? = nil
	local fadingViewports: { ViewportFrame } = {}
	local fadeStart = 0
	local fadeVote = false

	local handle = {} :: Show
	handle.root = root
	local function stop()
		for _, h in handles do
			h:disconnect()
		end
		table.clear(handles)
		for _, l in loops do
			l:remove()
		end
		table.clear(loops)
		for _, l in twinkles do
			l:remove()
		end
		table.clear(twinkles)
	end
	local function finish()
		if closed then
			return
		end
		closed = true
		stop()
		local current = board
		if current then
			current:destroy()
		end
		root:Destroy()
		local done = spec.onDone
		if done then
			done()
		end
	end
	function handle.close(_: Show)
		finish()
	end

	-- Round 3 of the match flow: the swap to the vote (L:1056-1065: the rays down and dim, the row down, the board).
	local moves: { { set: (y: number) -> (), from: number, to: number, ms: number, t: number } } = {}
	local raysFade: Tweens.FadeGroup? = nil
	local raysAlpha = { from = 1, to = 1, t = math.huge }
	local function moveY(set: (y: number) -> (), from: number, to: number, ms: number)
		table.insert(moves, { set = set, from = from, to = to, ms = ms, t = 0 })
	end
	local function raysTo(alpha: number)
		if raysFade == nil then
			raysFade = Tweens.fadeGroup(raysGroup)
		end
		raysAlpha = { from = raysAlpha.to, to = alpha, t = 0 }
	end
	local function startVote(v: Types.MatchVoteView)
		if board ~= nil then
			return
		end
		raysTo(VOTE.raysAlpha)
		moveY(function(y: number)
			raysGroup.Position = UDim2.fromOffset(MF.centre.x, y)
		end, MF.centre.y, VOTE.raysY, VOTE.raysMs)
		moveY(function(y: number)
			row.Position = UDim2.fromOffset(STAGE_W / 2, y)
		end, ROSTER.y, VOTE.rosterY, VOTE.rosterMs)
		board = MatchVoteBoard.new({
			stage = stage,
			mode = mode,
			view = v,
			you = spec.you,
			voters = voters,
			now = serverNow,
			play = spec.play,
			vote = function(card: number)
				local cast = spec.castVote
				if cast then
					cast(card)
				end
			end,
			reduced = reduced,
			k = k,
			fxK = fxK,
			track = track,
			add = add,
			loop = loop,
			onReveal = function()
				raysTo(1)
			end,
		})
	end
	function handle.setVote(_: Show, newView: Types.MatchVoteView)
		if closed then
			return
		end
		if newView.id == nil then
			voteClosed = true
			return
		end
		voteView = newView
		local current = board
		if current then
			current:setView(newView)
		elseif exited and fading == nil then
			startVote(newView)
		end
	end

	-- The exit (L:1048-1051): the block flies up at exit.atMs (round 3: once the vote's swap is due); the rest waits
	-- for the arena (round 3: for the vote's end, L:1141-1147), then fades out.
	local exit = MF.exit
	local function flyOut()
		spec.play(sounds.whoosh.key, sounds.whoosh.fallback)
		for _, l in twinkles do
			l:remove()
		end
		table.clear(twinkles)
		track(block, exit.frames, exit.ms, 0, exit.curve)
	end
	at(exit.atMs, function()
		exitDue = true
	end)
	table.sort(events, function(a, b)
		return a.at < b.at
	end)
	local function startFade(vote: boolean)
		fading = Tweens.fadeGroup(root)
		fadingViewports = viewportsIn(root)
		fadeStart = elapsed
		fadeVote = vote
		if vote then
			spec.play(VOTE.sounds.whoosh.key, VOTE.sounds.whoosh.fallback)
		end
	end
	do
		local nextEvent = 1
		local leaveAt = (exit.atMs + exit.ms) / 1000
		add(function(dt: number): boolean
			if closed then
				return false
			end
			elapsed += dt
			while nextEvent <= #events and elapsed * 1000 >= events[nextEvent].at do
				local event = events[nextEvent]
				nextEvent += 1
				local ok, err = pcall(event.fn)
				if not ok then
					log:warn("a step of the show failed:", err)
				end
			end
			local v = voteView
			if exitDue and not exited then
				if v == nil or voteClosed or serverNow() >= (v.opensAt or 0) - VOTE.leadMs / 1000 then
					exited = true
					flyOut()
					if v and not voteClosed then
						local ok, err = pcall(startVote, v)
						if not ok then
							log:warn("the map vote could not start:", err)
						end
					end
				end
			end
			for index = #moves, 1, -1 do
				local m = moves[index]
				m.t += dt
				local u = if reduced then 1 else math.min(m.t * 1000 / m.ms, 1)
				m.set(m.from + (m.to - m.from) * Tweens.curve(VOTE.moveCurve)(u))
				if u >= 1 then
					table.remove(moves, index)
				end
			end
			local dimRays = raysFade
			if dimRays and raysAlpha.t * 1000 <= VOTE.raysMs then
				raysAlpha.t += dt
				local u = if reduced then 1 else math.min(raysAlpha.t * 1000 / VOTE.raysMs, 1)
				dimRays:setAlpha(raysAlpha.from + (raysAlpha.to - raysAlpha.from) * Tweens.curve("ease")(u))
			end
			local current = board
			if fading == nil and current and not voteClosed then
				local endsAt = current:endsAt()
				if endsAt and serverNow() >= endsAt then
					startFade(true)
				end
			elseif fading == nil and exited and (voteClosed or current == nil) and elapsed >= leaveAt then
				local ready = spec.ready
				local arrived = voteClosed or ready == nil or ready()
				if arrived or elapsed >= leaveAt + exit.holdMaxS then
					startFade(false)
				end
			end
			local group = fading
			if group then
				local ms = if fadeVote then VOTE.reveal.fadeMs else MF.backdrop.fadeMs
				local u = math.min((elapsed - fadeStart) * 1000 / ms, 1)
				local gone = if fadeVote then Tweens.curve(VOTE.reveal.fadeCurve)(u) else u
				group:setAlpha(1 - gone)
				fadeViewports(fadingViewports, 1 - gone)
				if fadeVote and not reduced then
					stageScale.Scale = k * (1 + (VOTE.reveal.fadeScale - 1) * gone)
				end
				if u >= 1 then
					local toast = spec.toast
					if fadeVote and toast then
						local name = if current then current:winnerName() else nil
						local text = string.gsub(Strings.hud.foundShow.vote.teleport, "{map}", function(): string
							return name or Strings.hud.foundShow.vote.arena
						end)
						toast(text)
					end
					task.defer(finish)
					return false
				end
			end
			return true
		end)
	end

	root.Parent = spec.layer
	return handle
end

return MatchFoundShow
