--!strict
-- KillFeed (client only). Match HUD M6 (2026-10-17; plan work/matchhud2/PLAN.md §4 M6 = v1 M4, §12; `M:n` = "Squishy
-- Duels Match HUD.dc.html" line n): the kill feed, a MatchHudController piece ("feed"). Top right (M:120: right 18,
-- top 16), newest at the bottom, one row per K.O. (MatchHudFormat.feedLine):
--   [killer head] killer name [3 speed bars + their squishy at -18deg] victim name [victim head, greyed and squashed]
--   [tag: FINAL KILL / FIRST BLOOD / TRIPLE! / DOUBLE! / "{n} STREAK"]          (M:121-134, the tags M:523-527)
--   [STORM / FELL chip] victim name [victim head]          a K.O. with nobody to blame (owner 2026-10-16, [P])
-- Names in the player's colour (TDM team, FFA slot; yours #FFE36B and "You", M:651); the border #FFE36B with its .3
-- glow when you squished them, #FF5A6E when they squished you, ink otherwise (M:656). In: smFeedIn 0.5 s; out at 4.6 s
-- (smFeedOut 0.4 s); gone at 5.0 s (M:531-532); at most Config.UI.Match.feed.maxRows (compact screens
-- compactMaxRows: phones keep the feed clear of the touch buttons), the oldest leaving early. Shown in Active,
-- Overtime and Result (M:653). Each row is a CanvasGroup (its fade); each piece of it a MatchKit builder.
-- Sounds: every row ui.click at Config.Audio.uiPitch.card (M:533); another player's K.O. (not by you, not of you)
-- match.splat at matchHud.splatOthers (M:537), sfx.impactSoft while that has no id. Your own K.O.s: Diego's kill
-- banner plays their sound and burst (KillBannerController), so nothing more here; M's SQUISHED! medal is that same
-- moment and is not built (plan M6 medal: skipped, Diego's banner).
-- While it lives: the Roblox player list is off (v1 §1.4: on PC it opens over the feed), its earlier state back at the
-- end; the toast column keeps beside the feed (UIController.toastsBeside "matchFeed").

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Create = require(UI.Create)
local Layout = require(UI.Layout)
local MatchHudFormat = require(UI.MatchHudFormat)
local Theme = require(UI.Theme)
local SquishyImage = require(UI.Components.SquishyImage)
local Tweens = require(UI.Parent.Anim.Tweens)
local MatchKit = require(script.Parent.MatchKit)

-- Types

type Item = { object: any, width: number } -- one piece of a row and its width

type Row = {
	holder: Frame, -- placed by the list
	pose: CanvasGroup, -- the track's holder (its fade)
	poser: Tweens.Poser,
	width: number, -- the row's face width
	born: number, -- os.clock() it came in
	leaveAt: number?, -- its age when the full list made it leave early
	held: boolean, -- the hold pose is set
}

-- Constants

local CFG = Config.UI.Match.feed
local AUDIO = Config.Audio
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local SHOWN_PHASES: { [string]: boolean } = { Active = true, Overtime = true, Result = true }
local Z = 2
local TOAST_KEY = "matchFeed"
local SOUND_ROW = "ui.click"
local SOUND_SPLAT = "match.splat"
local SOUND_SPLAT_FALLBACK = "sfx.impactSoft"
local TAG_COLORS: { [string]: { Color3 } } = {
	final = { Palette.StickerYellowTop, Palette.StickerYellowEnd }, -- M:523
	firstBlood = { Palette.StickerRedTop, Palette.StickerRedEnd }, -- M:524
	triple = { Palette.MatchTripleTop, Palette.MatchTripleEnd }, -- M:525
	double = { Palette.StickerCyanTop, Palette.StickerCyanEnd }, -- M:526
	streak = { Palette.StickerStreakTop, Palette.StickerStreakEnd }, -- M:527
}
-- [P] the cause chips of a K.O. with nobody to blame (not in M): the storm purple, a fall sky blue.
local CAUSE_COLORS: { [string]: { Color3 } } = {
	storm = { Palette.StickerPurpleBarTop, Palette.StickerPurpleBarEnd },
	outOfBounds = { Palette.StickerBlueBarTop, Palette.StickerBlueBarEnd },
	other = { Palette.StickerCardTop, Palette.StickerCardBottom },
}
local WHITE = Color3.new(1, 1, 1)

-- Module table

local KillFeed = {}

-- Private

-- The pieces of one row, left to right, each { object, width } (built unparented, then placed).
local function rowItems(ctx: MatchHudFormat.Context, line: MatchHudFormat.FeedLine, view: any): { Item }
	local items: { Item } = {}
	local victim = MatchKit.who(ctx, view, line.victim)
	local head = CFG.head
	local function name(who: MatchKit.Who): Item
		local label, size = MatchKit.label({
			name = "Name",
			text = who.name,
			role = CFG.nameRole,
			color = if who.you then Palette.StickerCoinText else who.look.text,
			z = Z,
		})
		return { object = label, width = size.X }
	end
	local function chip(text: string, colors: { Color3 }): Item
		local frame, width = MatchKit.chip({
			name = "Tag",
			text = text,
			role = CFG.tag.role,
			height = CFG.tag.height,
			padX = CFG.tag.padX,
			border = CFG.tag.border,
			radius = CFG.tag.radius,
			top = colors[1],
			faceEnd = colors[2],
			z = Z,
		})
		return { object = frame, width = width }
	end
	local by = line.by
	if by == nil then
		local causes = Strings.matchHud.feed.cause :: { [string]: string }
		local key = if causes[line.cause] then line.cause else "other"
		table.insert(items, chip(causes[key], CAUSE_COLORS[key] or CAUSE_COLORS.other))
	else
		local killer = MatchKit.who(ctx, view, by)
		local killerHead = MatchKit.head({
			name = "KillerHead",
			who = killer,
			size = head.size,
			border = head.border,
			radius = head.radius,
			z = Z,
		})
		table.insert(items, { object = killerHead, width = head.size })
		table.insert(items, name(killer))
		-- M:125-128: the "weapon": three speed bars and the killer's squishy, turned -18deg with its 2 px ink drop.
		local weapon = CFG.weapon
		local box: Frame = Create("Frame", {
			Name = "Weapon",
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(weapon.width, weapon.height),
			ZIndex = Z,
			Active = false,
		})
		for index, bar in weapon.bars do
			local strip: Frame = Create("Frame", {
				Name = "Bar" .. index,
				BackgroundColor3 = WHITE,
				BackgroundTransparency = 1 - bar.alpha,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(bar.x, bar.y),
				Size = UDim2.fromOffset(bar.w, weapon.barHeight),
				ZIndex = Z,
				Active = false,
				Parent = box,
			})
			Theme.corner(weapon.barHeight / 2, strip)
		end
		if killer.squishyId ~= "" then
			local toy = SquishyImage.new(
				killer.squishyId,
				{ name = "Toy", size = weapon.toy, shadow = { px = weapon.toyDrop, alpha = 1 } }
			)
			toy.root.AnchorPoint = Vector2.new(1, 0)
			toy.root.Position = UDim2.fromScale(1, 0)
			toy.root.Rotation = weapon.toyRot
			toy.root.Parent = box
		end
		table.insert(items, { object = box, width = weapon.width })
	end
	table.insert(items, name(victim))
	local victimHead = MatchKit.head({
		name = "VictimHead",
		who = victim,
		size = head.size,
		border = head.border,
		radius = head.radius,
		z = Z,
		dead = CFG.victim,
		squash = CFG.victim,
	})
	table.insert(items, { object = victimHead, width = head.size })
	local tag = MatchHudFormat.tagText(line)
	if tag and line.tag then
		table.insert(items, chip(tag, TAG_COLORS[line.tag] or TAG_COLORS.streak))
	end
	return items
end

local function buildRow(ctx: MatchHudFormat.Context, line: MatchHudFormat.FeedLine, view: any, list: Frame): Row
	local items = rowItems(ctx, line, view)
	local b, pad, gap, glow = CFG.border, CFG.padX, CFG.gap, CFG.glow
	local width = 2 * (b + pad) + gap * math.max(#items - 1, 0)
	for _, item in items do
		width += item.width
	end
	local height = CFG.face + CFG.lip
	local holder: Frame = Create("Frame", {
		Name = "Row",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Size = UDim2.fromOffset(width + 2 * glow, height + 2 * glow),
		ZIndex = Z,
		Active = false,
	})
	-- M:122 transform-origin 100% 50%: the pose turns and scales about the row's right middle.
	local pose: CanvasGroup = Create("CanvasGroup", {
		Name = "Pose",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z,
		Active = false,
		Parent = holder,
	})
	local border = if line.mine == "by"
		then Palette.StickerCoinText
		elseif line.mine == "victim" then Palette.MatchFeedYouDown
		else Theme.Colors.inkUI
	if line.mine then
		-- M:656: 0 0 0 3px at .3 round the face (not the lip)
		local ring: Frame = Create("Frame", {
			Name = "Glow",
			BackgroundColor3 = border,
			BackgroundTransparency = 1 - CFG.glowAlpha,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(width + 2 * glow, CFG.face + 2 * glow),
			ZIndex = Z,
			Active = false,
			Parent = pose,
		})
		Theme.corner(CFG.radius + glow, ring)
	end
	local face: Frame = Create("Frame", {
		Name = "Face",
		BackgroundTransparency = 1 - CFG.fillAlpha,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(glow, glow),
		Size = UDim2.fromOffset(width, height),
		ZIndex = Z,
		Active = false,
		Parent = pose,
	})
	local bands = Layout.stickerBands(b, 0, 0, CFG.lip)
	Theme.foam(face, {
		radius = CFG.radius,
		stroke = b,
		strokeColor = border,
		inner = true,
		top = bands.top,
		drop = bands.drop,
		fixedHeight = height,
		colors = { face = Palette.MatchFeedRow, drop = Theme.Colors.inkUI },
	})
	local x = b + pad
	for _, item in items do
		local object = item.object :: GuiObject
		object.AnchorPoint = Vector2.new(0, 0.5)
		object.Position = UDim2.fromOffset(x, CFG.face / 2)
		object.Parent = face
		x += item.width + gap
	end
	holder.Parent = list
	return {
		holder = holder,
		pose = pose,
		poser = Tweens.poser(pose),
		width = width,
		born = os.clock(),
		leaveAt = nil,
		held = false,
	}
end

-- Public

function KillFeed.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local list: Frame = Create("Frame", {
		Name = "MatchFeed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -CFG.right, 0, CFG.top),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = Z,
		Active = false,
		Parent = ctx.root,
	})
	local rows: { Row } = {}
	local memory = MatchHudFormat.newFeedMemory()
	local listOk, listWas = pcall(function(): boolean
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	end)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	ctx.toastsBeside(TOAST_KEY, list)

	local function place()
		local glow = CFG.glow
		local pitch = CFG.face + CFG.rowGap
		local width = 0
		for index, row in rows do
			row.holder.Position = UDim2.new(1, glow, 0, (index - 1) * pitch - glow)
			width = math.max(width, row.width)
		end
		local height = if #rows > 0 then (#rows - 1) * pitch + CFG.face + CFG.lip else 0
		list.Size = UDim2.fromOffset(width, height)
	end

	local piece = {}

	function piece.update(_self: any, view: any, _now: number)
		list.Visible = SHOWN_PHASES[view.matchPhase] == true
		local clock = os.clock()
		local reduced = ctx.reduced()
		local removed = false
		for index = #rows, 1, -1 do
			local row = rows[index]
			local age = clock - row.born
			local phase, _u = MatchHudFormat.feedPose(age, row.leaveAt, CFG)
			if phase == "gone" then
				row.holder:Destroy()
				table.remove(rows, index)
				removed = true
			elseif phase == "in" then
				local enter = CFG.enter
				row.poser:set(MatchHudFormat.trackPose(enter.frames, age, enter.ms, enter.curve, nil, reduced, FADE_MS))
			elseif phase == "hold" then
				if not row.held then
					row.held = true
					local enter = CFG.enter
					row.poser:set(
						MatchHudFormat.trackPose(
							enter.frames,
							enter.ms / 1000,
							enter.ms,
							enter.curve,
							nil,
							reduced,
							FADE_MS
						)
					)
				end
			else
				local leave = CFG.leave
				local from = math.min(row.leaveAt or math.huge, leave.atMs / 1000)
				row.poser:set(
					MatchHudFormat.trackPose(leave.frames, age - from, leave.ms, leave.curve, nil, reduced, FADE_MS)
				)
			end
		end
		if removed then
			place()
		end
	end

	function piece.onMoment(_self: any, moment: any, view: any)
		local line = MatchHudFormat.feedLine(memory, moment, view.you.userId, CFG.multiWindowS, CFG.streakMin)
		if line == nil then
			return
		end
		local made = buildRow(ctx, line, view, list)
		local enter = CFG.enter
		-- Its first frame at once (CSS fill "both"): it never shows a frame at rest before the next update.
		made.poser:set(MatchHudFormat.trackPose(enter.frames, 0, enter.ms, enter.curve, nil, ctx.reduced(), FADE_MS))
		table.insert(rows, made)
		-- The list is full: the oldest rows still in it leave now (smFeedOut), the newest stay.
		local limit = if ctx.compact() then CFG.compactMaxRows else CFG.maxRows
		local clock = os.clock()
		local naturalOut = CFG.leave.atMs / 1000
		local staying = 0
		for index = #rows, 1, -1 do
			local row = rows[index]
			if row.leaveAt == nil and clock - row.born < naturalOut then
				staying += 1
				if staying > limit then
					row.leaveAt = clock - row.born
				end
			end
		end
		place()
		ctx.play(SOUND_ROW, { pitch = AUDIO.uiPitch.card })
		if line.by ~= nil and line.mine == nil then
			ctx.play(SOUND_SPLAT, { volume = AUDIO.matchHud.splatOthers }, SOUND_SPLAT_FALLBACK)
		end
	end

	function piece.destroy(_self: any)
		ctx.toastsBeside(TOAST_KEY, nil)
		if listOk then
			pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, listWas)
			end)
		end
		table.clear(rows)
		list:Destroy()
	end

	return piece :: any
end

return KillFeed
