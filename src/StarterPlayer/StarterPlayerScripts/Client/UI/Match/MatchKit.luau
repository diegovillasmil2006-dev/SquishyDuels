--!strict
-- MatchKit (client only). Match HUD M6 / M7 (2026-10-17; plan work/matchhud2/PLAN.md §4 M6, M7; v1 §1.6, §1.8,
-- §1.11; M = "Squishy Duels Match HUD.dc.html"): the small builders the kill feed (KillFeed) and the "squished by"
-- card (DeathCard) share, all from UI/Create, UI/Theme and Art/Palette:
--   who(ctx, view, userId) -> Who      a player as the screens name them: the view's players, else the roster (a player
--                                      who left keeps a name, v1 §2.4); you are "You" (M:651); their look
--                                      (MatchHudFormat.playerLook: TDM team, FFA slot)
--   label(spec) -> (TextLabel, Vector2)   one line in a Config.UI.Sticker.text role, sized from Theme.textWidth /
--                                      lineHeight (AutomaticSize off: it is wrong under the scaled HUD layers)
--   gradient(frame, look, rotation?)   the 180deg CSS gradient of a look (top, mid at 58%, end) on `frame`
--   inner(stroke)                      the stroke drawn inside the box (CSS border-box)
--   head(spec) -> Frame                a player's head in an ink-bordered box (M:123, M:131, M:177): the avatar head
--                                      (rbxthumb, v1 §1.8) for a real player, else their squishy's picture; `dead`
--                                      greys the box and the picture (v1 §1.11, M:131) and `squash` squashes the
--                                      picture inside a rounded CanvasGroup (v1 §1.6)
--   chip(spec) -> (Frame, number)      a pill / tag: ink border inside, a top -> end gradient, a role's text; its width
-- Every frame is Active = false (SD_MatchHud draws over the touch buttons: no frame here may take their taps).

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local MatchHudFormat = require(UI.MatchHudFormat)
local Theme = require(UI.Theme)
local SquishyImage = require(UI.Components.SquishyImage)

-- Types

export type Who = {
	userId: number,
	name: string, -- "You" for you
	squishyId: string,
	team: string?,
	you: boolean,
	player: Player?, -- a real player in this server (nil: a bot, a pretend player, someone who left)
	look: MatchHudFormat.PlayerLook,
}

export type LabelSpec = {
	name: string,
	text: string,
	role: string,
	color: Color3?, -- the player's colour (roles with no drop only: a drop's copies keep the role's)
	z: number,
	parent: Instance?,
}

export type HeadSpec = {
	name: string,
	who: Who,
	size: number, -- the box, border included
	border: number,
	radius: number,
	z: number,
	dead: { gray: number, brightness: number, inkAlpha: number }?,
	squash: { sx: number, sy: number, y: number }?, -- the picture squashed and moved down (base px at `size`)
	parent: Instance?,
}

export type ChipSpec = {
	name: string,
	text: string,
	role: string,
	height: number,
	padX: number,
	border: number,
	radius: number?, -- default: a full pill
	top: Color3,
	faceEnd: Color3,
	z: number,
	parent: Instance?,
}

-- Constants

local MEASURE_MARGIN_PX = 2 -- TextService rounding (QuestPop's)
local MID_AT = 0.58 -- M:389-390: the team gradients' middle stop
local HEAD_URL = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150" -- v1 §1.8
local WHITE = Color3.new(1, 1, 1)
local FIRST_REAL_ID = 1 -- bots and the Studio fixtures' pretend players have ids below this

-- Module table

local MatchKit = {}

-- Public

function MatchKit.who(ctx: MatchHudFormat.Context, view: any, userId: number): Who
	local found: any = nil
	if type(view) == "table" and type(view.players) == "table" then
		for _, player in view.players do
			if player.userId == userId then
				found = player
				break
			end
		end
	end
	local roster = ctx.roster()
	local entry = if type(roster) == "table" and type(roster.entries) == "table" then roster.entries[userId] else nil
	local you = type(view) == "table" and type(view.you) == "table" and view.you.userId == userId
	local source = found or entry
	local name = if source then source.displayName else "" -- never in a real view: every K.O. names a seen player
	local slot = if entry then entry.slot else nil
	local player = if userId >= FIRST_REAL_ID then Players:GetPlayerByUserId(userId) else nil
	local mode = if type(view) == "table" then view.mode else nil
	local team = if source then source.team else nil
	return {
		userId = userId,
		name = if you then Strings.matchHud.you else name,
		squishyId = if source then source.squishyId else "",
		team = team,
		you = you,
		player = player,
		look = MatchHudFormat.playerLook(mode, team, slot),
	}
end

function MatchKit.label(spec: LabelSpec): (TextLabel, Vector2)
	local role = Config.UI.Sticker.text[spec.role]
	local kind: Theme.TextKind = (if role then role.kind else "Small") :: any
	local width = math.ceil(Theme.textWidth(spec.text, kind)) + MEASURE_MARGIN_PX
	local height = math.ceil(Theme.lineHeight(kind))
	local label = Theme.label({
		Name = spec.name,
		Text = spec.text,
		AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromOffset(width, height),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = spec.z,
		Active = false,
	}, kind)
	Theme.stickerText(label, spec.role)
	label.TextWrapped = false
	if spec.color then
		label.TextColor3 = spec.color
	end
	if spec.parent then
		label.Parent = spec.parent
	end
	return label, Vector2.new(width, height)
end

function MatchKit.gradient(frame: GuiObject, look: MatchHudFormat.PlayerLook, rotation: number?): UIGradient
	frame.BackgroundColor3 = WHITE
	local keys = { ColorSequenceKeypoint.new(0, look.top) }
	if look.mid then
		table.insert(keys, ColorSequenceKeypoint.new(MID_AT, look.mid))
	end
	table.insert(keys, ColorSequenceKeypoint.new(1, look.faceEnd))
	return Create("UIGradient", { Rotation = rotation or 90, Color = ColorSequence.new(keys), Parent = frame })
end

function MatchKit.inner(stroke: UIStroke)
	pcall(function()
		(stroke :: any).BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end)
end

-- The look of a greyed box: the gradient stops through MatchHudFormat.deadColor.
local function deadLook(look: MatchHudFormat.PlayerLook, gray: number, brightness: number): MatchHudFormat.PlayerLook
	return {
		text = look.text,
		top = MatchHudFormat.deadColor(look.top, gray, brightness),
		mid = if look.mid then MatchHudFormat.deadColor(look.mid, gray, brightness) else nil,
		faceEnd = MatchHudFormat.deadColor(look.faceEnd, gray, brightness),
	}
end

function MatchKit.head(spec: HeadSpec): Frame
	local who = spec.who
	local dead = spec.dead
	local box: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(spec.size, spec.size),
		ZIndex = spec.z,
		Active = false,
	})
	Theme.corner(spec.radius, box)
	MatchKit.gradient(box, if dead then deadLook(who.look, dead.gray, dead.brightness) else who.look)
	local innerSize = spec.size - 2 * spec.border
	-- The picture's holder: a rounded CanvasGroup (ClipsDescendants ignores UICorner, v1 §1.6) so a squashed or
	-- greyed picture stays inside the box.
	local clip: CanvasGroup = Create("CanvasGroup", {
		Name = "Picture",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(innerSize, innerSize),
		ZIndex = spec.z,
		Active = false,
		Parent = box,
	})
	Theme.corner(math.max(spec.radius - spec.border, 0), clip)
	local squash = spec.squash
	local share = innerSize / spec.size
	local sx, sy = if squash then squash.sx else 1, if squash then squash.sy else 1
	local dy = if squash then math.round(squash.y * share) else 0
	if who.player then
		Create("ImageLabel", {
			Name = "Head",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 0.5, dy),
			Size = UDim2.fromScale(sx, sy),
			Image = string.format(HEAD_URL, who.userId),
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = spec.z,
			Active = false,
			Parent = clip,
		})
	elseif who.squishyId ~= "" then
		-- M:409: no avatar head (a bot, a pretend player): the squishy's picture.
		local image = SquishyImage.new(who.squishyId, { name = "Toy", size = innerSize })
		image.root.AnchorPoint = Vector2.new(0.5, 0.5)
		image.root.Position = UDim2.new(0.5, 0, 0.5, dy)
		if squash then
			image:squash(sx, sy)
		end
		image.root.Parent = clip
	end
	if dead then
		clip.GroupColor3 = Color3.new(dead.brightness, dead.brightness, dead.brightness)
		Create("Frame", {
			Name = "Ink",
			BackgroundColor3 = Theme.Colors.inkUI,
			BackgroundTransparency = 1 - dead.inkAlpha,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = spec.z,
			Active = false,
			Parent = clip,
		})
	end
	local stroke = Theme.stroke(Theme.Colors.inkUI, spec.border, box)
	MatchKit.inner(stroke)
	if spec.parent then
		box.Parent = spec.parent
	end
	return box
end

function MatchKit.chip(spec: ChipSpec): (Frame, number)
	local role = Config.UI.Sticker.text[spec.role]
	local kind: Theme.TextKind = (if role then role.kind else "Small") :: any
	local textWidth = math.ceil(Theme.textWidth(spec.text, kind)) + MEASURE_MARGIN_PX
	local width = textWidth + 2 * (spec.padX + spec.border)
	local chip: Frame = Create("Frame", {
		Name = spec.name,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(width, spec.height),
		ZIndex = spec.z,
		Active = false,
	})
	Theme.corner(spec.radius or math.floor(spec.height / 2), chip)
	MatchKit.gradient(chip, { text = WHITE, top = spec.top, faceEnd = spec.faceEnd })
	MatchKit.inner(Theme.stroke(Theme.Colors.inkUI, spec.border, chip))
	local label = MatchKit.label({ name = "Text", text = spec.text, role = spec.role, z = spec.z })
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Parent = chip
	if spec.parent then
		chip.Parent = spec.parent
	end
	return chip, width
end

return MatchKit
