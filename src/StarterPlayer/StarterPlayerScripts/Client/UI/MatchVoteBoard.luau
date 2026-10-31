--!strict
-- MatchVoteBoard (client only). Round 3 of the match flow (2026-10-25, owner: "Yes, build round 3 like that. 1v1 keeps
-- the show only, no map vote."; `L:n` = "Squishy Duels LOBBY HUD.dc.html" line n, `lib:n` = its uploads/hud-lib.js):
-- Diego's map vote on the MATCH FOUND show's stage. UI/MatchFoundShow starts it at the swap (L:1056-1065) with its own
-- helpers (track / add / loop, so the show's close stops it too) and ends the show 3.1 s after the reveal.
--   local board = MatchVoteBoard.new(context)   (Context below)
--   board:setView(view)   every MatchVoteState (Types.MatchVoteView: who voted where, the result and its times)
--   board:endsAt() -> the server time the show goes (nil before the result); board:winnerName() -> the toast's map
--   board:destroy()
-- * The head (the mode's pill with its tails, the name and chip), the line under it (VOTE FOR A MAP with the timer
--   until the result, then MAP CHOSEN! / IT'S A TIE! / RANDOM PICK!), a card per offered map (its card picture and
--   floating board, by Workspace.SquishyMaps model name; a plain card with the name when there is no picture).
-- * Tapping a card while the vote is open votes for it at once (Config.UI.MatchFound.vote.tapGapMs apart): your pick
--   lifts and glows with YOUR VOTE and your chip flies there from your tile; the server's next views confirm it (or
--   put it back once pickHoldS has passed). Anyone else's vote in a view flies from their tile; a moved vote leaves
--   its old card at once; each landing sticks the chip in the card's strip, pops or squashes its count (gold for the
--   single leader), puts a check on the voter's tile, sounds its note (higher for each voter) and bursts.
-- * The result, on the server's times: the line changes and the stamp sounds at `at`; a tie's roulette lights each
--   step's card (its blip); at revealAt the winner moves to the middle with LET'S GO! and the others go down, grey and
--   faded (a grey tint here: Roblox cannot desaturate a picture); the fanfare, then the burst, rings, rain and jolt.
-- * The timer: the whole seconds left, ticking with a sound and a pop, red and pulsing from timer.urgentAt; its ring runs
--   out over the vote a second behind the number (the design's 1 s stroke transition, L:684).
-- * Under ReducedMotion (the show's `reduced`): no flights (the votes land at once), no burst or jolt.
-- Pure (unit-tested): clock(view, now), cardPose(index, state), leader(counts), landPitch(n).

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local Types = require(Shared.Types)

local Client = script.Parent.Parent
local Create = require(script.Parent.Create)
local Layout = require(script.Parent.Layout)
local SegmentedTabs = require(script.Parent.Components.SegmentedTabs)
local SquishyImage = require(script.Parent.Components.SquishyImage)
local Theme = require(script.Parent.Theme)
local UiFx = require(script.Parent.UiFx)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Voter = {
	tile: GuiObject?, -- the voter's roster tile: the chip flies from it, the check goes on it
	colors: Theme.StickerColors, -- the tile's colours (the chip's too)
	squishy: string,
	team: number?, -- Team Deathmatch: 1 / 2
}

export type Context = {
	stage: Frame, -- the show's 1440 x 810 stage
	mode: string, -- "tdm" | "ffa"
	view: Types.MatchVoteView,
	you: number,
	voters: { [number]: Voter },
	now: () -> number, -- the server's clock
	play: (key: string, fallback: string, pitch: number?) -> (),
	vote: (card: number) -> (), -- MatchVote
	reduced: boolean,
	k: number, -- the stage's scale (text is measured at it)
	fxK: number, -- UiFx's px per stage px
	-- The show's helpers (UI/MatchFoundShow): a design @keyframes track with its fade, a render effect, an idle loop.
	track: (holder: GuiObject, frames: any, ms: number, delayMs: number, curve: string?) -> (),
	add: (effect: any) -> (), -- a (dt) -> keepGoing function or a Tweens.keyframes track
	loop: (handle: UiIdle.Handle?) -> (),
	onReveal: () -> (), -- the winner is out (the rays come back)
}

export type Board = {
	setView: (self: Board, view: Types.MatchVoteView) -> (),
	endsAt: (self: Board) -> number?,
	winnerName: (self: Board) -> string?,
	destroy: (self: Board) -> (),
}

-- A card's state for its look (cardPose): the cards' count, your pick, the roulette's lit card, the revealed winner and
-- whether the result is out.
export type CardState = { count: number, mine: number?, lit: number?, won: number?, result: boolean }
-- A card's look: its move from its place (stage px), scale, tint (1 = as drawn), alpha, glow (0..1) and z.
export type CardPose = { x: number, y: number, scale: number, tint: number, alpha: number, glow: number, z: number }

type Flight = {
	userId: number,
	card: number,
	chip: Frame,
	scale: UIScale,
	from: Vector2,
	to: Vector2,
	top: number,
	ms: number,
	elapsed: number,
	mine: boolean,
	puffs: number,
}

type Card = {
	holder: Frame,
	pose: Frame,
	scale: UIScale,
	glow: ImageLabel,
	glowScale: UIScale,
	pictures: { ImageLabel },
	hit: ImageButton,
	strip: Frame,
	chips: { { userId: number, holder: Frame } },
	count: Frame,
	countFaces: { Frame }, -- lilac, gold (the single leader)
	countSquash: Frame,
	squash: Tweens.Keyframes?, -- the count's running squash
	countLabel: TextLabel,
	mine: Frame,
	go: Frame,
	shown: CardPose, -- what is drawn now
	from: CardPose, -- the transition's start
	target: CardPose,
	moveElapsed: number,
	fade: Tweens.FadeGroup?,
}

-- Constants

local V = Config.UI.MatchFound.vote
local STAGE_W = Config.UI.MatchFound.stage.width
local INK = Palette.StickerInk
local WHITE = Palette.White
local MEASURE_MARGIN_PX = 6 -- scaled text draws a little wider than TextService measures (as MatchFoundShow)
local REST: CardPose = { x = 0, y = 0, scale = 1, tint = 1, alpha = 1, glow = 0, z = 1 }

-- Module table

local MatchVoteBoard = {}

-- Private

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

local function lerp(a: number, b: number, u: number): number
	return a + (b - a) * u
end

local function mapName(model: string): string
	return (Strings.hud.foundShow.vote.maps :: any)[model] or model
end

-- A sticker pill or badge face: the ink outline inside, the highlight band and the lip (Layout.stickerBands).
local function sticker(
	frame: Frame,
	spec: any,
	radius: number,
	face: Color3,
	faceEnd: Color3,
	mid: Color3?,
	midAt: number?
)
	local bands = Layout.stickerBands(spec.border, spec.highlightPx, 0, spec.lip)
	Theme.foam(
		frame,
		{
			radius = radius,
			stroke = spec.border,
			inner = true,
			top = bands.top,
			drop = bands.drop,
			colors = {
				face = face,
				faceEnd = faceEnd,
				mid = mid,
				midAt = midAt,
				top = face:Lerp(WHITE, spec.highlightAlpha),
			},
		} :: any
	)
	return bands
end

-- A voter's chip (lib:364: 46 px, border 4, radius 15, the voter's colours, the lip and highlight, the squishy 40).
local function chipOf(voter: Voter?, parent: Instance, z: number): Frame
	local s = V.strip
	local bands = Layout.stickerBands(s.border, s.highlightPx, 0, s.lip)
	local frame: Frame = Create("Frame", {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(s.px, s.px + bands.drop - s.border),
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	})
	local colors = if voter then voter.colors else { face = WHITE }
	Theme.foam(
		frame,
		{
			radius = s.radius,
			stroke = s.border,
			inner = true,
			top = bands.top,
			drop = bands.drop,
			colors = {
				face = colors.face,
				mid = colors.mid,
				midAt = colors.midAt,
				faceEnd = colors.faceEnd,
				top = colors.face:Lerp(WHITE, s.highlightAlpha),
			},
		} :: any
	)
	local id = if voter and Catalog.isValidId(voter.squishy) then voter.squishy else Catalog.starterId()
	local image = SquishyImage.new(id, { size = s.picPx, parent = frame })
	image.root.AnchorPoint = Vector2.new(0.5, 0.5)
	image.root.Position = UDim2.fromOffset(s.px / 2, s.px / 2)
	image.root.ZIndex = z + 1
	return frame
end

-- Public: pure -------------------------------------------------------------------------------------------------------

-- The timer at server time `now` (L:678-686): the whole seconds left (shown), the ring's share (a second behind the
-- number: the design's 1 s stroke transition after each tick) and whether it is urgent (red, pulsing). Full before the
-- vote opens; the vote's length is its own (closesAt - opensAt).
function MatchVoteBoard.clock(view: Types.MatchVoteView, now: number): (number, number, boolean)
	local opensAt, closesAt = view.opensAt or 0, view.closesAt or 0
	local seconds = math.max(1, math.floor(closesAt - opensAt + 0.5))
	local left = closesAt - now
	local shown = math.clamp(math.ceil(left), 0, seconds)
	local share = math.clamp((left + 1) / seconds, 0, 1)
	local urgent = now >= opensAt and view.result == nil and shown <= V.timer.urgentAt
	return shown, share, urgent
end

-- A card's look (L:1394-1398, Config.UI.MatchFound.vote.cards): revealed, the winner moves to the middle (stepX per
-- place) and the others go down, small, dim and faded; during a tie's roulette the lit card rises and the others dim;
-- else your pick lifts (glowing until the result).
function MatchVoteBoard.cardPose(index: number, s: CardState): CardPose
	local cards = V.cards
	if s.won ~= nil then
		if index == s.won then
			local w = cards.won
			return {
				x = ((s.count + 1) / 2 - index) * w.stepX,
				y = w.y,
				scale = w.scale,
				tint = 1,
				alpha = 1,
				glow = 1,
				z = 3,
			}
		end
		local l = cards.lost
		return { x = 0, y = l.y, scale = l.scale, tint = l.tint, alpha = l.alpha, glow = 0, z = 1 }
	elseif s.result and s.lit ~= nil then
		local r = cards.roulette
		if index == s.lit then
			return { x = 0, y = r.y, scale = r.scale, tint = 1, alpha = 1, glow = 1, z = 2 }
		end
		return { x = 0, y = 0, scale = 1, tint = r.others, alpha = 1, glow = 0, z = 1 }
	elseif s.mine == index then
		local m = cards.mine
		return { x = 0, y = m.y, scale = m.scale, tint = 1, alpha = 1, glow = if s.result then 0 else 1, z = 2 }
	end
	return table.clone(REST)
end

-- The card with the most votes when it is the only one (the gold count, L:1381); nil on a tie at the top or none.
function MatchVoteBoard.leader(counts: { number }): number?
	local best, at, ties = 0, nil, 0
	for index, n in counts do
		if n > best then
			best, at, ties = n, index, 1
		elseif n == best and n > 0 then
			ties += 1
		end
	end
	return if best > 0 and ties == 1 then at else nil
end

-- The n-th voter's landing note (lib:259: semitones up per voter; SoundController keeps it under Config.Audio.pitchMax).
function MatchVoteBoard.landPitch(n: number): number
	local steps = V.landSteps
	return 2 ^ (steps[math.clamp(math.floor(n), 1, #steps)] / 12)
end

-- Public -------------------------------------------------------------------------------------------------------------

function MatchVoteBoard.new(ctx: Context): Board
	local stage, k, fxK = ctx.stage, ctx.k, ctx.fxK
	local view = ctx.view
	local maps = view.maps or {}
	local count = #maps
	local tdm = ctx.mode == "tdm"
	local destroyed = false
	local made: { Instance } = {}
	local function own(object: Instance): Instance
		table.insert(made, object)
		return object
	end

	-- The head (L:666-672), about its centre (720, 80).
	local h = V.head
	local head = own(clear("VoteHead", {
		Position = UDim2.fromOffset(h.x, h.y),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 6,
		Parent = stage,
	})) :: Frame
	local tails = h.tails
	for _, side in { "L", "R" } do
		local key = if tdm
			then (if side == "L" then "img.vote.tailRed" else "img.vote.tailBlue")
			else (if side == "L" then "img.vote.tailPinkL" else "img.vote.tailPinkR")
		picture("Tail" .. side, key, {
			Position = UDim2.fromOffset(if side == "L" then tails.leftX else tails.rightX, tails.y),
			Size = UDim2.fromOffset(tails.width, tails.height),
			ZIndex = 6,
			Parent = head,
		})
	end
	local face = h.face
	local pic = h.picture
	picture("Pill", if tdm then "img.vote.headTeam" else "img.vote.headSolo", {
		Position = UDim2.fromOffset(-face.width / 2 - pic.faceX, -face.height / 2 - pic.faceY),
		Size = UDim2.fromOffset(pic.width, pic.height),
		ZIndex = 7,
		Parent = head,
	})
	-- L:670 sdShine: a white band crossing the face inside its border (held off it through 55% of each run).
	local shine = h.shine
	local innerW, innerH = face.width - 2 * face.border, face.height - 2 * face.border
	local shineFace: Frame = Create("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(innerW, innerH),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = head,
	})
	Theme.corner(face.radius - face.border, shineFace)
	local band = shine.width / innerW
	local shineGradient: UIGradient = Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5 - band / 2, 1),
			NumberSequenceKeypoint.new(0.5, shine.transparency),
			NumberSequenceKeypoint.new(0.5 + band / 2, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Rotation = SegmentedTabs.gradientRotation(20, innerW, innerH), -- skewX(-20deg)
		Offset = Vector2.new(-0.5 - band * 1.5, 0),
		Parent = shineFace,
	})
	local names, chips = Strings.hud.foundShow.names, Strings.hud.foundShow.chips
	local nameText, chipText = names[ctx.mode] or "", chips[ctx.mode] or ""
	local nameSize = Theme.textBoundsAt(nameText, "WindowSmall", nil, k)
	local chipSize = Theme.textBoundsAt(chipText, "D17", nil, k)
	local row = clear("Texts", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(innerW, innerH),
		ZIndex = 9,
		Parent = head,
	})
	Theme.list(
		Enum.FillDirection.Horizontal,
		h.gap,
		row,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local nameLabel = Theme.label({
		Name = "Mode",
		Text = nameText,
		Size = UDim2.fromOffset(nameSize.X + MEASURE_MARGIN_PX, nameSize.Y),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = 9,
		Parent = row,
	}, "WindowSmall")
	Theme.stickerText(nameLabel, "voteHead")
	oneLine(nameLabel)
	local chip: Frame = Create("Frame", {
		Name = "Chip",
		Size = UDim2.fromOffset(chipSize.X + MEASURE_MARGIN_PX + 2 * h.chipPad, h.chipHeight),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		ZIndex = 9,
		Parent = row,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = chip })
	local chipLabel = Theme.label({
		Name = "Text",
		Text = chipText,
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 10,
		Parent = chip,
	}, "D17", nil, WHITE)
	oneLine(chipLabel)
	ctx.track(head, h.frames, h.ms, h.delayMs, h.curve)

	-- The line under it (L:673-689): the text, then the timer.
	local sub = V.sub
	local subRow = own(clear("VoteLine", {
		Position = UDim2.fromOffset(0, sub.y),
		Size = UDim2.fromOffset(STAGE_W, sub.height),
		ZIndex = 6,
		Parent = stage,
	})) :: Frame
	local subList = clear("List", { Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = subRow })
	Theme.list(
		Enum.FillDirection.Horizontal,
		sub.gap,
		subList,
		Enum.HorizontalAlignment.Center,
		Enum.VerticalAlignment.Center
	)
	local voteTexts = Strings.hud.foundShow.vote
	local subLabel = Theme.label({
		Name = "Text",
		Text = voteTexts.sub,
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 1,
		ZIndex = 6,
		Parent = subList,
	}, "Title")
	Theme.stickerText(subLabel, "voteSub")
	oneLine(subLabel)
	local function setSub(text: string)
		local size = Theme.textBoundsAt(text, "Title", nil, k)
		subLabel.Text = text
		subLabel.Size = UDim2.fromOffset(size.X + MEASURE_MARGIN_PX, size.Y)
	end
	setSub(voteTexts.sub)
	local tm = V.timer
	local timer =
		clear("Timer", { Size = UDim2.fromOffset(tm.px, tm.px), LayoutOrder = 2, ZIndex = 6, Parent = subList })
	local timerIn = clear("In", { Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = timer })
	local timerScale: UIScale = Create("UIScale", { Parent = timerIn })
	local disc = tm.shadow
	local shadowDisc: Frame = Create("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(disc.x, disc.y),
		Size = UDim2.fromOffset(disc.px, disc.px),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = timerIn,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = shadowDisc })
	local outer = tm.facePx + tm.border
	local ring: Frame = Create("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(tm.px / 2, tm.px / 2),
		Size = UDim2.fromOffset(outer, outer),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = timerIn,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = ring })
	local timerFace: Frame = Create("Frame", {
		Name = "Face",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(tm.facePx - tm.border, tm.facePx - tm.border),
		BackgroundColor3 = color(tm.color),
		BorderSizePixel = 0,
		ZIndex = 8,
		Parent = ring,
	})
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = timerFace })
	picture("Track", "img.vote.ring", {
		Size = UDim2.fromOffset(tm.ringPx, tm.ringPx),
		ImageColor3 = INK,
		ImageTransparency = 1 - tm.trackAlpha,
		ZIndex = 9,
		Parent = timerIn,
	})
	-- The progress ring from 12 o'clock clockwise: each half of the ring picture shows its share through a hard-edged
	-- gradient turned to the share's angle (the right half 0-180 degrees, the left 180-360).
	local halves: { UIGradient } = {}
	for side = 1, 2 do
		local clip = clear("Half" .. side, {
			Position = UDim2.fromOffset(if side == 1 then tm.ringPx / 2 else 0, 0),
			Size = UDim2.fromOffset(tm.ringPx / 2, tm.ringPx),
			ClipsDescendants = true,
			ZIndex = 10,
			Parent = timerIn,
		})
		local half = picture("Ring", "img.vote.ring", {
			Position = UDim2.fromOffset(if side == 1 then -tm.ringPx / 2 else 0, 0),
			Size = UDim2.fromOffset(tm.ringPx, tm.ringPx),
			ZIndex = 10,
			Parent = clip,
		})
		table.insert(
			halves,
			Create("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.499, 0),
					NumberSequenceKeypoint.new(0.501, 1),
					NumberSequenceKeypoint.new(1, 1),
				}),
				Parent = half,
			})
		)
	end
	local function setRing(share: number)
		local angle = math.clamp(share, 0, 1) * 360
		halves[1].Rotation = math.clamp(angle, 0, 180)
		halves[2].Rotation = 180 + math.clamp(angle - 180, 0, 180)
	end
	local timeLabel = Theme.label({
		Name = "Time",
		Text = "",
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 11,
		Parent = timerIn,
	}, "Title")
	Theme.stickerText(timeLabel, "voteTime")
	oneLine(timeLabel)
	ctx.track(subRow, sub.frames, sub.ms, sub.delayMs, sub.curve)

	-- The flights' layer, over the cards and the row.
	local fly = own(
		clear(
			"VoteFly",
			{ Size = UDim2.fromOffset(STAGE_W, Config.UI.MatchFound.stage.height), ZIndex = 20, Parent = stage }
		)
	) :: Frame

	-- The cards (L:690-716).
	local cs = V.cards
	local rowWidth = count * cs.width + math.max(count - 1, 0) * cs.gap
	local cards: { Card } = {}
	local tap: (index: number) -> ()
	for index, model in maps do
		local cx = (STAGE_W - rowWidth) / 2 + (index - 1) * (cs.width + cs.gap) + cs.width / 2
		local holder = own(clear("Card" .. index, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cs.y + cs.height / 2),
			Size = UDim2.fromOffset(cs.width, cs.height),
			ZIndex = 6,
			Parent = stage,
		})) :: Frame
		local inHolder = clear("In", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = holder,
		})
		local pose = clear("Pose", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 6,
			Parent = inHolder,
		})
		local scale: UIScale = Create("UIScale", { Parent = pose })
		local g = cs.glow
		local glowHolder = clear("Glow", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(cs.width + 2 * (g.inset + g.pad), cs.height + 2 * (g.inset + g.pad)),
			ZIndex = 6,
			Parent = pose,
		})
		local glowScale: UIScale = Create("UIScale", { Parent = glowHolder })
		local glow = picture("Image", "img.vote.glow", {
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Rect.new(g.slice, g.slice, g.picturePx - g.slice, g.picturePx - g.slice),
			ImageColor3 = color(g.color),
			ImageTransparency = 1,
			ZIndex = 6,
			Parent = glowHolder,
		})
		local p = cs.picture
		local pictures: { ImageLabel } = {}
		local cardKey, boardKey = "img.vote.card." .. model, "img.vote.board." .. model
		if AssetTable.image(cardKey) then
			table.insert(
				pictures,
				picture("Card", cardKey, {
					Position = UDim2.fromOffset(-p.cardX, -p.cardY),
					Size = UDim2.fromOffset(p.width, p.height),
					ZIndex = 7,
					Parent = pose,
				})
			)
			local float = clear("Float", { Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = pose })
			table.insert(
				pictures,
				picture("Board", boardKey, {
					Position = UDim2.fromOffset(-p.cardX, -p.cardY),
					Size = UDim2.fromOffset(p.width, p.height),
					ZIndex = 8,
					Parent = float,
				})
			)
			local delay = (cs.floatS - (index - 1) * cs.floatStepS) % cs.floatS
			ctx.loop(UiIdle.addFrames(float, {
				{ at = 0, y = 0 },
				{ at = 0.5, y = -cs.floatPx },
				{ at = 1, y = 0 },
			}, { periodS = cs.floatS, delayS = delay, curve = "easeInOut" }))
		else
			-- A map with no picture yet: a plain card with its name.
			local plain: Frame =
				Create("Frame", { Name = "Card", Size = UDim2.fromScale(1, 1), ZIndex = 7, Parent = pose })
			Theme.foam(
				plain,
				{ radius = 28, stroke = 5, inner = true, colors = { face = Palette.StickerPickerWell } } :: any
			)
			local label = Theme.label({
				Name = "Name",
				Text = string.upper(mapName(model)),
				Size = UDim2.fromScale(1, 1),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 8,
				Parent = plain,
			}, "Large", nil, WHITE)
			oneLine(label)
		end
		for t, star in cs.twinkles do
			local px = star[3]
			local s = picture("Twinkle" .. t, "img.duel.star", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(star[1] + px / 2, star[2] + px / 2),
				Size = UDim2.fromOffset(px, px),
				ZIndex = 9,
				Parent = pose,
			})
			ctx.loop(UiIdle.add(s, "twinkle", { periodS = cs.twinkleS, delayS = star[4] }))
		end
		local hit: ImageButton = Create("ImageButton", {
			Name = "Hit",
			BackgroundTransparency = 1,
			ImageTransparency = 1,
			AutoButtonColor = false,
			Selectable = true,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 10,
			Parent = pose,
		})
		local st = V.strip
		local strip = clear("Strip", {
			Position = UDim2.fromOffset(st.left, st.top),
			Size = UDim2.fromOffset(st.px, st.px),
			ZIndex = 11,
			Parent = pose,
		})
		-- The count (L:710), popping in once it has a vote.
		local c = V.count
		local countHolder = clear("Count", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cs.width - c.right - c.px / 2, c.top + c.px / 2),
			Size = UDim2.fromOffset(c.px, c.px),
			Visible = false,
			ZIndex = 13,
			Parent = pose,
		})
		local countSquash = clear("Squash", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 13,
			Parent = countHolder,
		})
		local cb = Layout.stickerBands(c.border, c.highlightPx, 0, c.lip)
		local countFaces: { Frame } = {}
		for f, pair in { { c.top0, c.end0 }, { c.leaderTop, c.leaderEnd } } do
			local countFace: Frame = Create("Frame", {
				Name = if f == 1 then "Face" else "LeaderFace",
				Size = UDim2.new(1, 0, 1, cb.drop - c.border),
				BorderSizePixel = 0,
				Visible = f == 1,
				ZIndex = 13,
				Parent = countSquash,
			})
			sticker(countFace, c, c.px / 2, color(pair[1]), color(pair[2]))
			table.insert(countFaces, countFace)
		end
		local countLabel = Theme.label({
			Name = "Text",
			Text = "",
			Size = UDim2.fromOffset(c.px, c.px),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 14,
			Parent = countSquash,
		}, "Large")
		Theme.stickerText(countLabel, "voteCount")
		oneLine(countLabel)
		-- YOUR VOTE (L:714).
		local m = V.mine
		local mineText = voteTexts.mine
		local mineSize = Theme.textBoundsAt(mineText, "D17", nil, k)
		local mineBands = Layout.stickerBands(m.border, m.highlightPx, 0, m.lip)
		local mineW = 2 * m.border + m.padLeft + m.iconPx + m.gap + mineSize.X + MEASURE_MARGIN_PX + m.padRight
		local mineHolder = clear("Mine", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cs.width / 2, cs.height - m.bottom - m.height / 2),
			Size = UDim2.fromOffset(mineW, m.height),
			Visible = false,
			ZIndex = 13,
			Parent = pose,
		})
		local mineFace: Frame = Create("Frame", {
			Name = "Face",
			Size = UDim2.new(1, 0, 1, mineBands.drop - m.border),
			BorderSizePixel = 0,
			ZIndex = 13,
			Parent = mineHolder,
		})
		sticker(
			mineFace,
			m,
			(m.height + mineBands.drop - m.border) / 2,
			Palette.StickerGreenTop,
			Palette.StickerGreenEnd,
			Palette.StickerGreenMid,
			0.6
		)
		picture("Check", "img.icon.check", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(m.border + m.padLeft, m.height / 2),
			Size = UDim2.fromOffset(m.iconPx, m.iconPx),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 14,
			Parent = mineHolder,
		})
		local mineLabel = Theme.label({
			Name = "Text",
			Text = mineText,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(m.border + m.padLeft + m.iconPx + m.gap, m.height / 2),
			Size = UDim2.fromOffset(mineSize.X + MEASURE_MARGIN_PX, mineSize.Y),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 14,
			Parent = mineHolder,
		}, "D17")
		Theme.stickerText(mineLabel, "voteMine")
		oneLine(mineLabel)
		-- LET'S GO! (L:715).
		local go = V.go
		local goText = voteTexts.go
		local goSize = Theme.textBoundsAt(goText, "Ribbon", nil, k)
		local goBands = Layout.stickerBands(go.border, go.highlightPx, 0, go.lip)
		local goHolder = clear("Go", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cs.width / 2, go.top + go.height / 2),
			Size = UDim2.fromOffset(goSize.X + MEASURE_MARGIN_PX + 2 * (go.pad + go.border), go.height),
			Visible = false,
			ZIndex = 15,
			Parent = pose,
		})
		local goFace: Frame = Create("Frame", {
			Name = "Face",
			Size = UDim2.new(1, 0, 1, goBands.drop - go.border),
			BorderSizePixel = 0,
			ZIndex = 15,
			Parent = goHolder,
		})
		sticker(goFace, go, go.radius, Palette.StickerPinkTop, Palette.StickerPinkEnd, Palette.StickerPinkMid, 0.55)
		local goLabel = Theme.label({
			Name = "Text",
			Text = goText,
			Size = UDim2.fromOffset(goSize.X + MEASURE_MARGIN_PX + 2 * (go.pad + go.border), go.height),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 16,
			Parent = goHolder,
		}, "Ribbon")
		Theme.stickerText(goLabel, "voteGo")
		oneLine(goLabel)

		local card: Card = {
			holder = holder,
			pose = pose,
			scale = scale,
			glow = glow,
			glowScale = glowScale,
			pictures = pictures,
			hit = hit,
			strip = strip,
			chips = {},
			count = countHolder,
			countFaces = countFaces,
			countSquash = countSquash,
			squash = nil,
			countLabel = countLabel,
			mine = mineHolder,
			go = goHolder,
			shown = table.clone(REST),
			from = table.clone(REST),
			target = table.clone(REST),
			moveElapsed = math.huge,
			fade = nil,
		}
		table.insert(cards, card)
		hit.Activated:Connect(function()
			tap(index)
		end)
		ctx.track(inHolder, cs.frames, cs.ms, cs.delayMs + (index - 1) * cs.stepMs, cs.curve)
	end
	if UserInputService.GamepadEnabled and cards[1] then
		pcall(function()
			GuiService.SelectedObject = cards[1].hit
		end)
	end

	-- The swap's sounds (L:1059-1060).
	local sounds = V.sounds
	task.delay(sounds.open.atMs / 1000, function()
		if not destroyed then
			ctx.play(sounds.open.key, sounds.open.fallback)
		end
	end)
	for index = 1, count do
		task.delay((sounds.card.atMs + (index - 1) * sounds.card.stepMs) / 1000, function()
			if not destroyed then
				ctx.play(sounds.card.key, sounds.card.fallback)
			end
		end)
	end

	-- State --------------------------------------------------------------------------------------------------------------

	local landed: { [number]: number } = {} -- userId -> the card its chip sits on
	local flights: { [number]: Flight } = {}
	local pending: { [number]: number } = {} -- card -> chips flying to it
	local checked: { [number]: boolean } = {} -- roster tiles with their check
	local pick: { card: number, at: number }? = nil
	local lastTap = -math.huge
	local shownSeconds: number? = nil
	local popElapsed = math.huge
	local clockS = 0
	local passed = ctx.now()
	local resultShown = false
	local revealed = false

	local function counts(): { number }
		local out: { number } = {}
		for index, card in cards do
			out[index] = #card.chips
		end
		return out
	end

	local function paintCounts()
		local all = counts()
		local lead = MatchVoteBoard.leader(all)
		for index, card in cards do
			local n = all[index]
			card.countLabel.Text = tostring(n)
			if n > 0 and not card.count.Visible then
				card.count.Visible = true
				ctx.track(card.count, V.popFrames, V.popMs, 0, V.popCurve)
			elseif n == 0 then
				card.count.Visible = false
			end
			card.countFaces[1].Visible = lead ~= index
			card.countFaces[2].Visible = lead == index
		end
	end

	-- The chips in card `index`'s strip, laid out 28 apart (later ones on top).
	local function layoutStrip(card: Card)
		local st = V.strip
		for j, entry in card.chips do
			entry.holder.Position = UDim2.fromOffset((j - 1) * st.step + st.px / 2, st.px / 2)
			entry.holder.ZIndex = 11 + j
		end
	end

	-- Where a chip of `card` lands (stage px): its next place in the strip, the card's lift included.
	local function stageScale(): number
		local size = stage.AbsoluteSize.X
		return if size > 0 then size / STAGE_W else k
	end
	local function toStage(point: Vector2): Vector2
		return (point - stage.AbsolutePosition) / stageScale()
	end
	local function slotPoint(index: number, slot: number): Vector2
		local card = cards[index]
		local st = V.strip
		local origin = toStage(card.strip.AbsolutePosition)
		local u = card.strip.AbsoluteSize.Y / (st.px * stageScale())
		return origin + Vector2.new(((slot - 1) * st.step + st.px / 2) * u, (st.px / 2) * u)
	end

	local function removeChip(userId: number)
		local at = landed[userId]
		if at then
			landed[userId] = nil
			local card = cards[at]
			for j, entry in card.chips do
				if entry.userId == userId then
					entry.holder:Destroy()
					table.remove(card.chips, j)
					break
				end
			end
			layoutStrip(card)
		end
		local flight = flights[userId]
		if flight then
			flights[userId] = nil
			pending[flight.card] = math.max(0, (pending[flight.card] or 0) - 1)
			flight.chip:Destroy()
		end
	end

	local function land(userId: number, index: number, mine: boolean)
		local card = cards[index]
		local voter = ctx.voters[userId]
		local holder = clear("Voter" .. userId, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(V.strip.px, V.strip.px),
			ZIndex = 12,
			Parent = card.strip,
		})
		local inner = clear("Stick", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 12,
			Parent = holder,
		})
		local chipFrame = chipOf(voter, inner, 12)
		chipFrame.Position = UDim2.fromScale(0.5, 0.5)
		table.insert(card.chips, { userId = userId, holder = holder })
		landed[userId] = index
		layoutStrip(card)
		if not ctx.reduced then
			ctx.track(inner, V.strip.frames, V.strip.ms, 0, V.strip.curve)
		end
		local n = #card.chips
		local s = V.sounds
		local landSound = if mine then s.landMine else s.land
		ctx.play(landSound.key, landSound.fallback, MatchVoteBoard.landPitch(n))
		paintCounts()
		if not ctx.reduced then
			local toss = V.toss
			local burst = if mine then toss.landMine else toss.landOther
			local colors: { Color3 }
			if mine then
				colors = UiFx.colors(toss.landMine.colors)
			else
				local team = if voter then voter.team else nil
				local name = if team then toss.teamColors[team] else toss.soloColor
				colors = { color(name or toss.soloColor), WHITE }
			end
			UiFx.sparks(holder, {
				n = burst.n,
				spread = burst.spread * fxK,
				size = burst.size * fxK,
				up = burst.up * fxK,
				colors = colors,
			})
			-- One squash at a time: a new landing restarts it from rest (two posers on one holder would compound).
			local c = V.count
			local a = 0.14 * c.squash
			local running = card.squash
			if running then
				running:cancel()
			end
			card.countSquash.Size = UDim2.fromScale(1, 1)
			local squash = Tweens.keyframes(card.countSquash, {
				{ at = 0, sx = 1, sy = 1 },
				{ at = 0.2, sx = 1 + a, sy = 1 - a },
				{ at = 0.45, sx = 1 - a * 0.5, sy = 1 + a * 0.6 },
				{ at = 0.7, sx = 1 + a * 0.2, sy = 1 - a * 0.15 },
				{ at = 1, sx = 1, sy = 1 },
			}, { ms = c.squashMs, wholeRun = "easeOut" })
			card.squash = squash
			ctx.add(squash)
		end
		-- The voter's tile gets its check (L:735).
		local tile = if voter then voter.tile else nil
		if tile and not checked[userId] then
			checked[userId] = true
			local ck = V.check
			local mark = clear("Voted", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(1, -ck.right - ck.px / 2, 0, ck.top + ck.px / 2),
				Size = UDim2.fromOffset(ck.px, ck.px),
				ZIndex = 9,
				Parent = tile,
			})
			local disc2: Frame = Create("Frame", {
				Name = "Disc",
				Size = UDim2.fromScale(1, 1),
				BorderSizePixel = 0,
				ZIndex = 9,
				Parent = mark,
			})
			Theme.foam(
				disc2,
				{
					radius = ck.px / 2,
					stroke = ck.border,
					inner = true,
					colors = { face = Palette.StickerGreenTop, faceEnd = Palette.StickerGreen2End },
				} :: any
			)
			picture("Check", "img.icon.check", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(ck.iconPx, ck.iconPx),
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = 10,
				Parent = mark,
			})
			ctx.track(mark, V.popFrames, V.popMs, 0, V.popCurve)
		end
	end

	-- A vote flies from the voter's tile to card `index` (lib:361-375), or lands at once (no tile, ReducedMotion).
	local function moveTo(userId: number, index: number)
		removeChip(userId)
		local mine = userId == ctx.you
		local voter = ctx.voters[userId]
		local tile = if voter then voter.tile else nil
		if ctx.reduced or tile == nil or tile.AbsoluteSize.X <= 0 then
			land(userId, index, mine)
			return
		end
		local toss = V.toss
		local slot = #cards[index].chips + (pending[index] or 0) + 1
		pending[index] = (pending[index] or 0) + 1
		local from = toStage(tile.AbsolutePosition + tile.AbsoluteSize / 2)
		local to = slotPoint(index, slot)
		local myCard = if pick then pick.card else nil
		if mine and myCard ~= index then
			to -= Vector2.new(0, toss.raise) -- the card lifts as your pick moves to it
		end
		local arc = if mine then toss.mineArc else toss.otherArc
		local chipHolder = clear("Toss" .. userId, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(from.X, from.Y),
			Size = UDim2.fromOffset(toss.px, toss.px),
			ZIndex = 20,
			Parent = fly,
		})
		local chipScale: UIScale = Create("UIScale", { Scale = toss.frames[1].scale, Parent = chipHolder })
		local chipFrame = chipOf(voter, chipHolder, 21)
		chipFrame.Position = UDim2.fromScale(0.5, 0.5)
		flights[userId] = {
			userId = userId,
			card = index,
			chip = chipHolder,
			scale = chipScale,
			from = from,
			to = to,
			top = math.min(from.Y, to.Y) - arc,
			ms = if mine then toss.mineMs else toss.otherMs,
			elapsed = 0,
			mine = mine,
			puffs = 0,
		}
		ctx.play(V.sounds.toss.key, V.sounds.toss.fallback)
	end

	-- The server's view of who voted where against what is drawn (see the header).
	local function reconcile(now: number)
		local votes = view.votes or {}
		local inView: { [number]: number } = {}
		for index, list in votes do
			for _, userId in list do
				inView[userId] = index
			end
		end
		local holdPick = pick ~= nil and now - (pick :: any).at < V.pickHoldS
		if pick and inView[ctx.you] == pick.card then
			holdPick = false -- confirmed
			pick = nil
		end
		-- Gone or moved: off their old card at once.
		local drawn: { [number]: number } = table.clone(landed)
		for userId, flight in flights do
			drawn[userId] = flight.card
		end
		for userId, index in drawn do
			local wanted = inView[userId]
			local keep = userId == ctx.you and holdPick
			if not keep and wanted ~= index then
				removeChip(userId)
			end
		end
		-- New or moved: they fly (in the order the server lists them).
		for index, list in votes do
			for _, userId in list do
				local keep = userId == ctx.you and holdPick
				local at = landed[userId] or (if flights[userId] then flights[userId].card else nil)
				if not keep and at ~= index and index <= count then
					moveTo(userId, index)
				end
			end
		end
		if not holdPick then
			pick = nil
		end
		paintCounts()
	end

	-- Your card: the tapped one while its view comes, else the server's.
	local function myCard(): number?
		if pick then
			return pick.card
		end
		for index, list in view.votes or {} do
			if table.find(list, ctx.you) then
				return index
			end
		end
		return nil
	end

	local function isOpen(now: number): boolean
		return view.result == nil
			and now >= (view.opensAt or 0) - Config.Match.Vote.earlySeconds
			and now < (view.closesAt or 0)
	end

	tap = function(index: number)
		local now = ctx.now()
		if destroyed or not isOpen(now) or myCard() == index or os.clock() - lastTap < V.tapGapMs / 1000 then
			return
		end
		lastTap = os.clock()
		ctx.play(V.sounds.press.key, V.sounds.press.fallback)
		pick = { card = index, at = now }
		ctx.vote(index)
		moveTo(ctx.you, index)
	end

	-- The look every card should have now.
	local function retarget(now: number)
		local result = view.result
		local state: CardState = { count = count, mine = myCard(), lit = nil, won = nil, result = false }
		if result and now >= result.at then
			state.result = true
			if now >= result.revealAt then
				state.won = result.winner
			else
				for _, step in result.roulette do
					if now >= step.at then
						state.lit = step.choice
					end
				end
			end
		end
		for index, card in cards do
			local target = MatchVoteBoard.cardPose(index, state)
			local old = card.target
			if
				target.x ~= old.x
				or target.y ~= old.y
				or target.scale ~= old.scale
				or target.tint ~= old.tint
				or target.alpha ~= old.alpha
				or target.glow ~= old.glow
			then
				card.from = table.clone(card.shown)
				card.target = target
				card.moveElapsed = 0
			end
			card.holder.ZIndex = 6 + target.z
			local mine = state.mine == index
			if mine and not card.mine.Visible then
				card.mine.Visible = true
				ctx.track(card.mine, V.popFrames, V.popMs, 0, V.popCurve)
			elseif not mine then
				card.mine.Visible = false
			end
			local canTap = isOpen(now)
			card.hit.Active = canTap
			card.hit.Selectable = canTap
		end
		return state
	end

	-- The timeline crossings between the last frame and `now` (server time): the result's line and stamp, the
	-- roulette's blips, the reveal (LET'S GO!, the fanfare, the rays) and its burst.
	local function crossed(at: number, now: number): boolean
		return passed < at and now >= at
	end
	local function events(now: number)
		local result = view.result
		if result == nil then
			return
		end
		local s = V.sounds
		if not resultShown and now >= result.at then
			resultShown = true
			local key = if result.kind == "tie" then "tie" elseif result.kind == "random" then "random" else "chosen"
			setSub((voteTexts :: any)[key])
			timer.Visible = false
			if crossed(result.at, now) then
				ctx.play(s.stamp.key, s.stamp.fallback)
			end
		end
		for n, step in result.roulette do
			if crossed(step.at, now) then
				ctx.play(s.roulette.key, s.roulette.fallback, if (n - 1) % 2 == 1 then 2 ^ (V.rouletteLow / 12) else 1)
			end
		end
		if not revealed and now >= result.revealAt then
			revealed = true
			setSub(voteTexts.chosen)
			timer.Visible = false
			local winner = cards[result.winner]
			if winner then
				winner.go.Visible = true
				ctx.track(winner.go, V.go.frames, V.go.ms, V.go.delayMs, V.go.curve)
			end
			ctx.play(s.fanfare.key, s.fanfare.fallback)
			ctx.onReveal()
			task.delay(s.burst.atMs / 1000, function()
				if destroyed then
					return
				end
				ctx.play(s.burst.key, s.burst.fallback)
				if ctx.reduced then
					return
				end
				local r = V.reveal
				local point = clear("RevealPoint", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(r.x, r.y),
					Size = UDim2.fromOffset(2, 2),
					Parent = stage,
				})
				table.insert(made, point)
				UiFx.sparks(point, {
					n = r.sparks.n,
					spread = r.sparks.spread * fxK,
					size = r.sparks.size * fxK,
					ms = r.sparks.ms,
					colors = UiFx.colors(r.sparks.colors),
				})
				for _, ringSpec in r.rings do
					task.delay((ringSpec.delayMs or 0) / 1000, function()
						if not destroyed then
							UiFx.ring(point, color(ringSpec.color), ringSpec.size * fxK)
						end
					end)
				end
				UiFx.rain(r.rain)
				UiFx.jolt(stage, r.jolt * k)
			end)
		end
	end

	-- Every frame: the clock, the cards' moves, the glows, the flights, the timeline.
	ctx.add(function(dt: number): boolean
		if destroyed then
			return false
		end
		local now = ctx.now()
		-- The timer.
		local shown, share, urgent = MatchVoteBoard.clock(view, now)
		if timer.Visible then
			if shownSeconds ~= nil and shown < shownSeconds and now >= (view.opensAt or 0) then
				local tick = if shown <= tm.urgentAt then V.sounds.tickUrgent else V.sounds.tick
				ctx.play(tick.key, tick.fallback)
				popElapsed = 0
			end
			shownSeconds = shown
			timeLabel.Text = tostring(shown)
			setRing(share)
			timerFace.BackgroundColor3 = color(if urgent then tm.urgentColor else tm.color)
			popElapsed += dt
			clockS += dt
			local pop = 1
			if popElapsed * 1000 < tm.tickMs and not ctx.reduced then
				pop = lerp(tm.tickScale, 1, Tweens.curve(tm.tickCurve)(popElapsed * 1000 / tm.tickMs))
			end
			local pulse = 1
			if urgent and not ctx.reduced then
				local u = (clockS % tm.urgentPeriodS) / tm.urgentPeriodS
				pulse = 1 + (tm.urgentScale - 1) * Tweens.curve("easeInOut")(if u < 0.5 then u * 2 else (1 - u) * 2)
			end
			timerScale.Scale = pop * pulse
		end
		local held = pick
		if held and now - held.at >= V.pickHoldS then
			reconcile(now) -- the server never took it: its view again
		end
		-- The cards.
		local state = retarget(now)
		local g = cs.glow
		local pulseU = (os.clock() % g.pulseS) / g.pulseS
		local glowPulse = 1
			+ (g.pulseScale - 1) * Tweens.curve("easeInOut")(if pulseU < 0.5 then pulseU * 2 else (1 - pulseU) * 2)
		for index, card in cards do
			card.moveElapsed += dt
			local moveU = if ctx.reduced then 1 else math.min(card.moveElapsed * 1000 / cs.moveMs, 1)
			local tintU = if ctx.reduced then 1 else math.min(card.moveElapsed * 1000 / cs.tintMs, 1)
			local glowU = if ctx.reduced then 1 else math.min(card.moveElapsed * 1000 / g.fadeMs, 1)
			local eased = Tweens.curve(cs.moveCurve)(moveU)
			local tintEased = Tweens.curve("ease")(tintU)
			local from, to, shownPose = card.from, card.target, card.shown
			shownPose.x = lerp(from.x, to.x, eased)
			shownPose.y = lerp(from.y, to.y, eased)
			shownPose.scale = lerp(from.scale, to.scale, eased)
			shownPose.tint = lerp(from.tint, to.tint, tintEased)
			shownPose.alpha = lerp(from.alpha, to.alpha, tintEased)
			shownPose.glow = lerp(from.glow, to.glow, Tweens.curve("ease")(glowU))
			card.pose.Position = UDim2.new(0.5, math.round(shownPose.x), 0.5, math.round(shownPose.y))
			card.scale.Scale = shownPose.scale
			local tint = Color3.new(shownPose.tint, shownPose.tint, shownPose.tint)
			for _, image in card.pictures do
				image.ImageColor3 = tint
			end
			card.glow.ImageColor3 = color(if state.lit == index then g.rouletteColor else g.color)
			card.glow.ImageTransparency = 1 - shownPose.glow
			card.glowScale.Scale = glowPulse
			if shownPose.alpha < 1 and card.fade == nil then
				card.fade = Tweens.fadeGroup(card.pose)
			end
			local fade = card.fade
			if fade then
				fade:setAlpha(shownPose.alpha)
			end
		end
		-- The flights.
		local toss = V.toss
		for userId, flight in flights do
			flight.elapsed += dt
			local u = math.min(flight.elapsed * 1000 / flight.ms, 1)
			local x = lerp(flight.from.X, flight.to.X, Tweens.curve("mfToss")(u))
			local y: number
			if u < toss.peakAt then
				y = lerp(flight.from.Y, flight.top, Tweens.curve("mfTossUp")(u / toss.peakAt))
			else
				y = lerp(flight.top, flight.to.Y, Tweens.curve("mfTossDown")((u - toss.peakAt) / (1 - toss.peakAt)))
			end
			local pose = Tweens.poseAt(toss.frames, u, nil, "easeOut")
			flight.chip.Position = UDim2.fromOffset(x, y)
			flight.chip.Rotation = pose.rot or 0
			flight.scale.Scale = pose.scale or 1
			if flight.mine then
				local trail = toss.trail
				local due = math.floor(u * trail.puffs)
				if due > flight.puffs and flight.puffs < trail.puffs then
					flight.puffs = due
					UiFx.sparks(flight.chip, {
						n = trail.n,
						spread = trail.spread * fxK,
						size = trail.size * fxK,
						up = 0,
						ms = trail.ms,
						colors = UiFx.colors(trail.colors),
					})
				end
			end
			if u >= 1 then
				flights[userId] = nil
				pending[flight.card] = math.max(0, (pending[flight.card] or 0) - 1)
				flight.chip:Destroy()
				land(userId, flight.card, flight.mine)
			end
		end
		events(now)
		passed = now
		return true
	end)

	local board = {} :: Board
	function board.setView(_: Board, newView: Types.MatchVoteView)
		if destroyed or newView.id == nil then
			return
		end
		view = newView
		reconcile(ctx.now())
	end
	function board.endsAt(_: Board): number?
		local result = view.result
		return if result then result.revealAt + V.reveal.endAfterMs / 1000 else nil
	end
	function board.winnerName(_: Board): string?
		local result = view.result
		local model = if result then maps[result.winner] else nil
		return if model then mapName(model) else nil
	end
	function board.destroy(_: Board)
		if destroyed then
			return
		end
		destroyed = true
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(stage) then
			GuiService.SelectedObject = nil
		end
		for _, object in made do
			object:Destroy()
		end
		table.clear(made)
	end
	reconcile(ctx.now())
	-- Keep the shine moving (L:670): held off the face, then across it, every periodS from delayS.
	do
		local elapsed = 0
		local from, to = -0.5 - band * 1.5, 0.5 + band * 9.5
		local idle = Config.UI.motion.idle.shine
		ctx.add(function(dt: number): boolean
			if destroyed then
				return false
			end
			elapsed += dt
			local t = elapsed - shine.delayS
			if ctx.reduced or t < 0 then
				return true
			end
			local u = (t / shine.periodS) % 1
			local hold = idle.holdShare
			local eased = if u <= hold then 0 else Tweens.curve(idle.curve)((u - hold) / (1 - hold))
			shineGradient.Offset = Vector2.new(from + (to - from) * eased, 0)
			return true
		end)
	end
	return board
end

return MatchVoteBoard
