--!strict
-- PracticeScoreBox (client only). Diego's practice score box, TIME! card and hit pop (FULL FINAL lobby zip,
-- reference-preview "Hub Props.html": .score :93-98 / :385-390, .result :94 / :393-397, .pop :448-450; owner
-- 2026-10-30 "Yes, add them"). Sizes in Config.PracticeScore, colours in Palette (Practice*). PracticeController owns
-- them: the box replaces its old stats panel (same placement), the card and the pops live in their own ScreenGui.
-- The numbers come from his PracticeRange's player attributes on the server (PracticeScore, PracticeRoundEnds and
-- PracticeLastHit in HubFX.now() seconds, PracticeCombo) and the PracticeHit remote; view() is pure.

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Palette = require(Shared.Art.Palette)
local PracticeRange = require(Shared.SquishyLobby.PracticeRange)
local SIZE = require(Shared.Config.PracticeScore)
local Strings = require(Shared.Strings)

local Create = require(script.Parent.Create)
local Theme = require(script.Parent.Theme)

-- Types

export type View = {
	score: string,
	time: string,
	timeFraction: number, -- the bar's fill, 1 = the whole round left
	combo: string, -- "" when no combo runs
	best: string,
}

export type Box = {
	root: Frame,
	score: TextLabel,
	time: TextLabel,
	fill: Frame,
	combo: TextLabel,
	best: TextLabel,
}

export type Card = { root: CanvasGroup, scale: UIScale, score: TextLabel, sub: TextLabel }

-- Constants

local B = SIZE.box
local C = SIZE.card
local P = SIZE.pop
local ROUND = PracticeRange.RoundTime
local MAX_COMBO = PracticeRange.MaxCombo
local COMBO_WINDOW = PracticeRange.ComboWindow

-- Module table

local PracticeScoreBox = {}

-- Private

local function label(name: string, size: number, color: Color3, props: { [string]: any }): TextLabel
	local l: TextLabel = Create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		FontFace = Theme.font("Body", Enum.FontWeight.Bold),
		TextSize = size,
		TextColor3 = color,
		Text = "",
	})
	for key, value in props do
		(l :: any)[key] = value
	end
	return l
end

local function stroke(color: Color3, px: number, parent: Instance)
	Create("UIStroke", { Color = color, Thickness = px, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = parent })
end

-- A card face: the shadow (box-shadow 0 Npx 0) under a bordered, rounded face.
local function face(name: string, size: Vector2, radius: number, border: number, borderColor: Color3, shadow: number, parent: Instance?): Frame
	local root: Frame = Create("Frame", { Name = name, BackgroundTransparency = 1, Size = UDim2.fromOffset(size.X, size.Y + shadow) })
	local under: Frame = Create("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Palette.PracticeBoxShadow,
		Position = UDim2.fromOffset(0, shadow),
		Size = UDim2.fromOffset(size.X, size.Y),
		Parent = root,
	})
	Theme.corner(radius, under)
	local top: Frame = Create("Frame", {
		Name = "Face",
		BackgroundColor3 = Palette.PracticeBoxBg,
		Size = UDim2.fromOffset(size.X, size.Y),
		Parent = root,
	})
	Theme.corner(radius, top)
	Create("UIStroke", { Color = borderColor, Thickness = border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = top })
	root.Parent = parent
	return root
end

-- Public: pure ---------------------------------------------------------------------------------------------------------

-- What the box shows (preview :385-390): the score, the seconds left (rounded up, the round's 30 before a hit) and the
-- bar, COMBO xN while a combo (2+) runs, the best. `attributes` = the player's Practice* attributes, `now` = HubFX.now().
function PracticeScoreBox.view(attributes: { [string]: any }, now: number, best: number): View
	local ends = attributes.PracticeRoundEnds
	local left = if type(ends) == "number" then math.clamp(ends - now, 0, ROUND) else ROUND
	local combo = attributes.PracticeCombo
	local last = attributes.PracticeLastHit
	local comboOn = type(combo) == "number" and combo > 1 and type(last) == "number" and now - last < COMBO_WINDOW
	local score = attributes.PracticeScore
	return {
		score = tostring(if type(score) == "number" then score else 0),
		time = tostring(math.ceil(left)),
		timeFraction = left / ROUND,
		combo = if comboOn then Strings.format(Strings.practice.box.combo, { n = math.min(MAX_COMBO, combo) }) else "",
		best = Strings.format(Strings.practice.box.best, { n = best }),
	}
end

-- The pop's two lines (preview :448): the callout over "+points (xN)", or that line alone; big for a 100.
function PracticeScoreBox.popText(points: number, callout: string?, combo: number): (string, string?, boolean)
	local line = if combo > 1
		then Strings.format(Strings.practice.pop.combo, { points = points, combo = combo })
		else Strings.format(Strings.practice.pop.points, { points = points })
	local big = points >= P.bigPoints * math.max(1, combo) or (callout ~= nil and callout == PracticeRange.Rings[1][3])
	if callout and callout ~= "" then
		return callout, line, big
	end
	return line, nil, big
end

-- Public: the box ------------------------------------------------------------------------------------------------------

function PracticeScoreBox.buildBox(name: string): Box
	local inner = B.width - 2 * B.padX - 2 * B.border
	local height = 2 * B.padY + 2 * B.border + B.labelLine + B.scoreSize + B.barTop + B.barHeight + B.comboTop + B.comboLine + B.labelLine
	local root = face(name, Vector2.new(B.width, height), B.radius, B.border, Palette.PracticeBoxBorder, B.shadow, nil)
	root.Visible = false
	local body: Frame = Create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(B.padX + B.border, B.padY + B.border),
		Size = UDim2.fromOffset(inner, height - 2 * (B.padY + B.border)),
		Parent = (root :: any).Face,
	})
	local y = 0
	local function row(h: number): number
		local at = y
		y += h
		return at
	end
	local labelsY = row(B.labelLine)
	label("ScoreLabel", B.labelSize, Palette.PracticeBoxLabel, {
		Text = Strings.practice.box.score,
		Position = UDim2.fromOffset(0, labelsY),
		Size = UDim2.fromOffset(inner / 2, B.labelLine),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	label("TimeLabel", B.labelSize, Palette.PracticeBoxLabel, {
		Text = Strings.practice.box.time,
		Position = UDim2.fromOffset(inner / 2, labelsY),
		Size = UDim2.fromOffset(inner / 2, B.labelLine),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = body,
	})
	local numbersY = row(B.scoreSize)
	local score = label("Score", B.scoreSize, Palette.PracticeBoxInk, {
		Position = UDim2.fromOffset(0, numbersY),
		Size = UDim2.fromOffset(inner * 0.7, B.scoreSize),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local time = label("Time", B.timeSize, Palette.PracticeBoxTime, {
		Position = UDim2.fromOffset(inner * 0.7, numbersY),
		Size = UDim2.fromOffset(inner * 0.3, B.scoreSize),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Bottom, -- align-items: baseline
		Parent = body,
	})
	y += B.barTop
	local track: Frame = Create("Frame", {
		Name = "TimeBar",
		BackgroundColor3 = Palette.PracticeBoxTrack,
		Position = UDim2.fromOffset(0, row(B.barHeight)),
		Size = UDim2.fromOffset(inner, B.barHeight),
		ClipsDescendants = true,
		Parent = body,
	})
	Theme.corner(B.barRadius, track)
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	})
	Theme.corner(B.barRadius, fill)
	Create("UIGradient", {
		Color = ColorSequence.new(Palette.PracticeBoxFillFrom, Palette.PracticeBoxFillTo),
		Parent = fill,
	})
	y += B.comboTop
	local combo = label("Combo", B.comboSize, Palette.PracticeBoxCombo, {
		Position = UDim2.fromOffset(0, row(B.comboLine)),
		Size = UDim2.fromOffset(inner, B.comboLine),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	local best = label("Best", B.labelSize, Palette.PracticeBoxLabel, {
		Position = UDim2.fromOffset(0, row(B.labelLine)),
		Size = UDim2.fromOffset(inner, B.labelLine),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = body,
	})
	return { root = root, score = score, time = time, fill = fill, combo = combo, best = best }
end

function PracticeScoreBox.setBox(box: Box, view: View)
	if box.score.Text ~= view.score then box.score.Text = view.score end
	if box.time.Text ~= view.time then box.time.Text = view.time end
	if box.combo.Text ~= view.combo then box.combo.Text = view.combo end
	if box.best.Text ~= view.best then box.best.Text = view.best end
	local size = UDim2.fromScale(math.clamp(view.timeFraction, 0, 1), 1)
	if box.fill.Size ~= size then box.fill.Size = size end
end

-- Public: the TIME! card -----------------------------------------------------------------------------------------------

function PracticeScoreBox.buildCard(parent: Instance): Card
	local width = 300
	local height = 2 * (C.padY + C.border) + C.titleLine + C.scoreLine + C.subLine
	local root: CanvasGroup = Create("CanvasGroup", {
		Name = "PracticeTimeCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(width, height + C.shadow),
		GroupTransparency = 1,
		Visible = false,
	})
	local scale: UIScale = Create("UIScale", { Scale = C.fromScale, Parent = root })
	local card = face("Card", Vector2.new(width, height), C.radius, C.border, Palette.PracticeCardBorder, C.shadow, root)
	local body = (card :: any).Face
	local y = C.padY + C.border
	local title = label("Title", C.titleSize, Palette.PracticeBoxTime, {
		Text = Strings.practice.card.title,
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, C.titleLine),
		Parent = body,
	})
	stroke(Palette.PracticeTextStroke, C.titleStroke, title)
	y += C.titleLine
	local score = label("Score", C.scoreSize, Palette.PracticeBoxInk, {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, C.scoreLine),
		Parent = body,
	})
	y += C.scoreLine
	local sub = label("Sub", C.subSize, Palette.PracticeBoxLabel, {
		Position = UDim2.fromOffset(0, y),
		Size = UDim2.new(1, 0, 0, C.subLine),
		Parent = body,
	})
	root.Parent = parent
	return { root = root, scale = scale, score = score, sub = sub }
end

-- Shows the card (preview :397): the round's score and New best!, else the best.
function PracticeScoreBox.showCard(card: Card, score: number, best: number)
	card.score.Text = tostring(score)
	card.sub.Text = if score >= best and score > 0
		then Strings.practice.card.newBest
		else Strings.format(Strings.practice.card.best, { n = best })
	card.root.Visible = true
	if GuiService.ReducedMotionEnabled then
		card.scale.Scale = 1
		card.root.GroupTransparency = 0
		return
	end
	card.scale.Scale = C.fromScale
	card.root.GroupTransparency = 1
	TweenService:Create(card.root, TweenInfo.new(C.fadeSeconds), { GroupTransparency = 0 }):Play()
	-- cubic-bezier(.2,1.5,.4,1): an overshoot, Back Out
	TweenService:Create(card.scale, TweenInfo.new(C.scaleSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function PracticeScoreBox.hideCard(card: Card)
	card.root.Visible = false
	card.root.GroupTransparency = 1
end

-- Public: the hit pop --------------------------------------------------------------------------------------------------

-- One pop at a screen point (fractions of the screen), gone after its 0.9 s.
function PracticeScoreBox.pop(parent: Instance, at: Vector2, points: number, callout: string?, combo: number)
	local top, bottom, big = PracticeScoreBox.popText(points, callout, combo)
	local size = if big then P.bigSize else P.size
	local height = size + (if bottom then P.smallSize else 0)
	local root: CanvasGroup = Create("CanvasGroup", {
		Name = "PracticePop",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(at.X, at.Y),
		Size = UDim2.fromOffset(320, height + 2 * P.stroke),
	})
	local scale: UIScale = Create("UIScale", { Scale = P.fromScale, Parent = root })
	local first = label("Top", size, Palette.PracticeBoxTime, {
		Text = top,
		Position = UDim2.fromOffset(0, P.stroke),
		Size = UDim2.new(1, 0, 0, size),
		Parent = root,
	})
	stroke(Palette.PracticeTextStroke, P.stroke, first)
	if bottom then
		local second = label("Small", P.smallSize, Palette.PracticeBoxInk, {
			Text = bottom,
			Position = UDim2.fromOffset(0, P.stroke + size),
			Size = UDim2.new(1, 0, 0, P.smallSize),
			Parent = root,
		})
		stroke(Palette.PracticeTextStroke, P.stroke, second)
	end
	root.Parent = parent
	local h = root.Size.Y.Offset
	local function at01(rise: number): UDim2
		return UDim2.new(at.X, 0, at.Y, -math.round(h * rise))
	end
	if GuiService.ReducedMotionEnabled then
		scale.Scale = 1
		TweenService:Create(root, TweenInfo.new(P.seconds), { GroupTransparency = 1 }):Play()
	else
		local up = TweenInfo.new(P.seconds * P.peakAt, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(scale, up, { Scale = P.peakScale }):Play()
		TweenService:Create(root, up, { Position = at01(P.peakRise) }):Play()
		task.delay(P.seconds * P.peakAt, function()
			if root.Parent == nil then return end
			local rest = TweenInfo.new(P.seconds * (1 - P.peakAt), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(scale, rest, { Scale = 1 }):Play()
			TweenService:Create(root, rest, { Position = at01(P.endRise), GroupTransparency = 1 }):Play()
		end)
	end
	task.delay(P.seconds + 0.05, function()
		root:Destroy()
	end)
end

return PracticeScoreBox
