--!strict
-- CatchHud (client only). Rework Option A, the catch (owner 2026-11-12 "Yes, build it"; Claude Design's canvas
-- "Squishy Duels: catch squishies on the highway": Main, Landing, Catch, Rare, NewZone, Home and its CatchCard part,
-- drawn at 844x390, a phone in landscape: 1 canvas px = 1 / 0.85 base px). The catch's screen parts in SD_Highway
-- (HighwayCatchController owns them); sizes and text kinds in Config.Economy.Catch.ui, base px under the gui's UIScale.
-- * The CATCH meter (setMeter(view), nil hides it), upper right: a purple sticker, "CATCH" ("SURE CATCH!" in coin
--   yellow when the next catch is sure) and "{have}/{total} here"; under them the bar (pink to gold, full and gold
--   when sure) and the star.
-- * The chip (setChip(on)), under the meter: "Your first catch here is sure!" on gold, gently pulsing (NewZone).
-- * The card (showCard(view)), in the meter's place (the meter hides while it shows): it slides in from the right
--   (inMs, Back Out), holds holdMs and slides out (outMs); hideCard() slides it out at once (the shot ends: the bubble
--   flies home, Home shows no card). Rare and up: the rarity ring and glow; Epic and up: two twinkling stars;
--   Legendary: turning rays behind it. NEW! when the player had none.
-- * The fly (fly(kind, color, target)): the caught squishy in a bubble flies from the screen's upper middle to `target`
--   (the HUD's Squishies button) on a curve, then "+1" pops beside it inside a white halo (Home).
-- ReducedMotion: no slide, no flight: the card shows and hides, "+1" shows at the target.
-- Pure: meterView, cardView (unit-tested).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Rarity = require(Shared.Rarity)
local RarityStyle = require(Shared.Art.RarityStyle)
local Strings = require(Shared.Strings)

local UI = script.Parent
local Client = UI.Parent
local Create = require(UI.Create)
local SquishyImage = require(UI.Components.SquishyImage)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type MeterView = { title: string, here: string, fill: number, sure: boolean }
export type CardView = {
	kind: string,
	title: string,
	name: string,
	label: string,
	pips: number,
	color: Color3,
	light: Color3,
	rank: number, -- 1 Common .. 5 Legendary
	isNew: boolean,
	zone: string,
	fill: number,
}
export type Spec = {
	gui: Instance,
	scale: (() -> number)?, -- the gui's UI scale (text measuring, the fly's points); default 1
	scheduler: Scheduler.Scheduler?, -- default: the client's
	reduced: (() -> boolean)?, -- ReducedMotion; default Tweens.reducedMotion
}
export type Hud = {
	setMeter: (self: Hud, view: MeterView?) -> (),
	setChip: (self: Hud, shown: boolean) -> (),
	showCard: (self: Hud, view: CardView) -> (),
	hideCard: (self: Hud) -> (),
	cardShowing: (self: Hud) -> boolean,
	fly: (self: Hud, kind: string, color: Color3, target: GuiObject?) -> (),
	destroy: (self: Hud) -> (),
}

-- Constants

local C = Config.Economy.Catch.ui
local METER = C.meter
local CHIP = C.chip
local CARD = C.card
local FLY = C.fly
local INK = Palette.StickerInk
local WHITE = Palette.White
local YELLOW = Palette.StickerCoinText
local TROUGH_ALPHA = 0.45 -- rgba(30, 20, 40, .55)
local BACK = 1.70158 -- Back Out's overshoot
local MS = 1000
local STAR = "img.icon.star"
local GLOW = "img.fx.glow"
local RAYS = "img.fx.rays"
local MARGIN = 2 -- base px around a measured label

-- Module table

local CatchHud = {}

-- Private

local function backOut(u: number): number
	local v = u - 1
	return 1 + (BACK + 1) * v * v * v + BACK * v * v
end

local function gradient(top: Color3, bottom: Color3, parent: Instance, rotation: number?): UIGradient
	return Create("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

local function image(key: string): string?
	return AssetTable.image(key)
end

-- Public: pure

-- The meter's lines: CATCH (or SURE CATCH! when the next catch is sure), "{have}/{total} here", the fill miss / need.
function CatchHud.meterView(miss: number, need: number, have: number, total: number, sure: boolean): MeterView
	local s = Strings.highway.catch
	return {
		title = if sure then s.sure else s.meter,
		here = Strings.format(s.here, { have = have, total = total }),
		fill = if sure then 1 elseif need > 0 then math.clamp(miss / need, 0, 1) else 0,
		sure = sure,
	}
end

-- The card of a caught `kind` (CatchCard): its title by rarity, name, rarity pill, NEW!, "{have}/{total} in this
-- zone" and its share; nil for an unknown squishy.
function CatchHud.cardView(kind: string, isNew: boolean, have: number, total: number): CardView?
	local def = Catalog.get(kind)
	local style = if def then RarityStyle.get(def.rarity) else nil
	local info = if def then Rarity.get(def.rarity) else nil
	if def == nil or style == nil or info == nil then
		return nil
	end
	local s = Strings.highway.catch
	return {
		kind = kind,
		title = s.title[def.rarity] or s.title.Common,
		name = Strings.resolve(def.nameKey) or kind,
		label = Strings.resolve(info.labelKey) or def.rarity,
		pips = info.pips,
		color = style.color,
		light = style.ui.light or WHITE,
		rank = Rarity.index(def.rarity) or 1,
		isNew = isNew,
		zone = Strings.format(s.inZone, { have = have, total = total }),
		fill = if total > 0 then math.clamp(have / total, 0, 1) else 0,
	}
end

-- Public: the screen

function CatchHud.new(spec: Spec): Hud
	local scheduler = spec.scheduler or Scheduler.default()
	local scaleOf = spec.scale or function(): number
		return 1
	end
	local reducedOf = spec.reduced or Tweens.reducedMotion
	local runs: { [string]: Scheduler.Handle } = {}

	local root: Frame = Create("Frame", {
		Name = "CatchHud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = spec.gui,
	})

	-- A one-line label sized from Theme.textBoundsAt (no AutomaticSize under the UIScale); returns it and its size.
	local function label(name: string, text: string, kind: string, tone: Color3, parent: Instance): (TextLabel, Vector2)
		local bounds = Theme.textBoundsAt(text, kind :: any, nil, scaleOf())
		local made = Theme.label({
			Name = name,
			Text = text,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(bounds.X + MARGIN, bounds.Y),
			Parent = parent,
		}, kind :: any, nil, tone)
		made.TextWrapped = false
		return made, bounds
	end

	-- A sticker (a gradient face with an ink border over an ink lip `lip` px below) `size`; returns its holder and face.
	local function sticker(
		name: string,
		size: Vector2,
		top: Color3,
		bottom: Color3,
		radius: number,
		border: number,
		lip: number,
		parent: Instance
	): (Frame, Frame)
		local holder: Frame = Create("Frame", {
			Name = name,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size.X, size.Y),
			Parent = parent,
		})
		if lip > 0 then
			local under: Frame = Create("Frame", {
				Name = "Lip",
				BackgroundColor3 = INK,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, lip),
				Size = UDim2.fromScale(1, 1),
				Parent = holder,
			})
			Theme.corner(radius, under)
		end
		local face: Frame = Create("Frame", {
			Name = "Face",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = holder,
		})
		Theme.corner(radius, face)
		gradient(top, bottom, face)
		local stroke = Theme.stroke(INK, border, face)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		return holder, face
	end

	-- A scheduler run of `seconds`: fn(u) every frame (u 0..1), done() at the end; replaces the run named `name`.
	local function run(name: string, seconds: number, fn: (u: number) -> (), done: (() -> ())?)
		local old = runs[name]
		if old then
			old:disconnect()
		end
		local elapsed = 0
		fn(if seconds > 0 then 0 else 1)
		if seconds <= 0 then
			runs[name] = nil
			if done then
				done()
			end
			return
		end
		runs[name] = scheduler:add(function(dt: number): boolean
			elapsed += dt
			local u = math.min(elapsed / seconds, 1)
			fn(u)
			if u >= 1 then
				runs[name] = nil
				if done then
					done()
				end
			end
			return u < 1
		end, "render")
	end

	-- The meter (Main, Landing): built once, its texts re-measured on change.
	local titleText, titleBounds = Strings.highway.catch.meter, Vector2.zero
	local rowHeight = Theme.textBoundsAt(titleText, METER.titleKind :: any, nil, scaleOf()).Y
	local meterHeight = METER.padTop + rowHeight + METER.gap + METER.barHeight + METER.padBottom
	local meter, meterFace = sticker(
		"CatchMeter",
		Vector2.new(METER.width, meterHeight),
		Palette.StickerCardTop,
		Palette.StickerCardBottom,
		METER.radius,
		METER.border,
		METER.lip,
		root
	)
	meter.AnchorPoint = Vector2.new(1, 0)
	meter.Position = UDim2.new(1, -METER.right, 0, METER.top)
	meter.Visible = false
	local title, _ = label("Title", titleText, METER.titleKind, WHITE, meterFace)
	title.Position = UDim2.fromOffset(METER.padX, METER.padTop)
	local here, _ = label("Here", "", METER.hereKind, YELLOW, meterFace)
	here.AnchorPoint = Vector2.new(1, 0)
	here.TextXAlignment = Enum.TextXAlignment.Right
	local starPx = METER.starPx
	local barY = METER.padTop + rowHeight + METER.gap
	local trough: Frame = Create("Frame", {
		Name = "Bar",
		BackgroundColor3 = INK,
		BackgroundTransparency = TROUGH_ALPHA,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(METER.padX, barY),
		Size = UDim2.new(1, -(2 * METER.padX + starPx), 0, METER.barHeight),
		ClipsDescendants = true,
		Parent = meterFace,
	})
	Theme.corner(METER.barHeight / 2, trough)
	Theme.stroke(INK, METER.barBorder, trough).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local fill: Frame = Create("Frame", {
		Name = "Fill",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = trough,
	})
	Theme.corner(METER.barHeight / 2, fill)
	local fillGradient = gradient(Palette.CatchBarPink, Palette.CatchBarGold, fill, 0)
	Create("ImageLabel", {
		Name = "Star",
		BackgroundTransparency = 1,
		Image = image(STAR) or "",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -METER.padX + starPx / 4, 0, barY + METER.barHeight / 2),
		Size = UDim2.fromOffset(starPx, starPx),
		Parent = meterFace,
	})
	local meterShown = { title = "", here = "", sure = false }

	-- The chip (NewZone): built on first use.
	local chip: Frame? = nil
	local chipPulse: UiIdle.Handle? = nil

	-- The card (Catch, Rare): rebuilt for every catch.
	local card: Frame? = nil
	local cardOn = false
	local cardOut: (() -> ())? = nil -- slides the shown card out now

	-- The fly (Home).
	local flyFrame: Frame? = nil

	local hud = {} :: Hud

	function hud.setMeter(_: Hud, view: MeterView?)
		local on = view ~= nil and not cardOn
		meter.Visible = on
		if view == nil then
			return
		end
		if view.title ~= meterShown.title then
			meterShown.title = view.title
			titleBounds = Theme.textBoundsAt(view.title, METER.titleKind :: any, nil, scaleOf())
			title.Text = view.title
			title.Size = UDim2.fromOffset(titleBounds.X + MARGIN, titleBounds.Y)
		end
		if view.sure ~= meterShown.sure then
			meterShown.sure = view.sure
			title.TextColor3 = if view.sure then YELLOW else WHITE
			fillGradient.Color = if view.sure
				then ColorSequence.new(Palette.CatchBarGold, Palette.StickerCreamYellow)
				else ColorSequence.new(Palette.CatchBarPink, Palette.CatchBarGold)
		end
		if view.here ~= meterShown.here then
			meterShown.here = view.here
			local bounds = Theme.textBoundsAt(view.here, METER.hereKind :: any, nil, scaleOf())
			here.Text = view.here
			here.Size = UDim2.fromOffset(bounds.X + MARGIN, bounds.Y)
			here.Position = UDim2.fromOffset(METER.width - METER.padX, METER.padTop + (rowHeight - bounds.Y) / 2)
		end
		fill.Size = UDim2.fromScale(view.fill, 1)
		fill.Visible = view.fill > 0
	end

	function hud.setChip(_: Hud, shown: boolean)
		local made = chip
		if made == nil and not shown then
			return
		end
		if made == nil then
			local text = Strings.highway.catch.sureZone
			local bounds = Theme.textBoundsAt(text, CHIP.kind :: any, nil, scaleOf())
			local width = CHIP.padX + CHIP.starPx + CHIP.gap + bounds.X + MARGIN + CHIP.padX * 1.5
			local holder: Frame = Create("Frame", {
				Name = "CatchChip",
				BackgroundTransparency = 1,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -METER.right, 0, METER.top + meterHeight + METER.lip + CHIP.below),
				Size = UDim2.fromOffset(width, CHIP.height),
				Parent = root,
			})
			local pill, face = sticker(
				"Pill",
				Vector2.new(width, CHIP.height),
				Palette.StickerHeaderGoldTop,
				Palette.StickerHeaderGoldEnd,
				CHIP.height / 2,
				CHIP.border,
				CHIP.border,
				holder
			)
			Create("ImageLabel", {
				Name = "Star",
				BackgroundTransparency = 1,
				Image = image(STAR) or "",
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, CHIP.padX, 0.5, 0),
				Size = UDim2.fromOffset(CHIP.starPx, CHIP.starPx),
				Parent = face,
			})
			local line, _ = label("Text", text, CHIP.kind, WHITE, face)
			line.AnchorPoint = Vector2.new(0, 0.5)
			line.Position = UDim2.new(0, CHIP.padX + CHIP.starPx + CHIP.gap, 0.5, 0)
			made = holder
			chip = holder
			if not reducedOf() then
				chipPulse = UiIdle.add(pill, "pulse", { periodS = CHIP.pulseS })
			end
		end
		(made :: Frame).Visible = shown and not cardOn
	end

	function hud.cardShowing(_: Hud): boolean
		return cardOn
	end

	function hud.showCard(_: Hud, view: CardView)
		local old = card
		if old then
			old:Destroy()
		end
		cardOn = true
		meter.Visible = false
		if chip then
			(chip :: Frame).Visible = false
		end
		local w, h = CARD.width, CARD.height
		local holder: Frame = Create("Frame", {
			Name = "CatchCard",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -METER.right, 0, METER.top),
			Size = UDim2.fromOffset(w, h),
			Parent = root,
		})
		card = holder
		local rare = view.rank >= 3
		if view.rank >= 5 then -- Legendary: the turning rays behind it
			Theme.rays(holder, RAYS, CARD.raysPx, CARD.raysAlpha, CARD.raysPeriodS)
		end
		if rare then -- the rarity ring outside the ink border (a UIStroke draws outside its frame) and its glow
			local reach = CARD.border + CARD.ring
			local glowId = image(GLOW)
			if glowId then
				Create("ImageLabel", {
					Name = "Glow",
					BackgroundTransparency = 1,
					Image = glowId,
					ImageColor3 = view.color,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, CARD.glowPx * 2, 1, CARD.glowPx * 2),
					Parent = holder,
				})
			end
			local ring: Frame = Create("Frame", {
				Name = "Ring",
				BackgroundColor3 = view.color,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, reach * 2, 1, reach * 2),
				Parent = holder,
			})
			Theme.corner(CARD.radius + reach, ring)
		end
		local _, face = sticker(
			"Body",
			Vector2.new(w, h),
			Palette.StickerCardTop,
			Palette.StickerCardBottom,
			CARD.radius,
			CARD.border,
			CARD.lip,
			holder
		)
		-- The picture tile: the squishy on the rarity's light-to-main gradient.
		local pic = CARD.picPx
		local tile: Frame = Create("Frame", {
			Name = "Tile",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, CARD.pad, 0.5, 0),
			Size = UDim2.fromOffset(pic, pic),
			ClipsDescendants = true,
			Parent = face,
		})
		Theme.corner(CARD.picRadius, tile)
		gradient(view.light, view.color, tile)
		Theme.stroke(INK, CARD.picBorder, tile).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		local art = SquishyImage.new(view.kind, { size = math.floor(pic * 0.9), name = "Squishy", parent = tile })
		art.root.AnchorPoint = Vector2.new(0.5, 0.5)
		art.root.Position = UDim2.fromScale(0.5, 0.5)
		-- The text column.
		local x = CARD.pad + pic + CARD.gap
		local columnW = w - x - CARD.pad
		local y = CARD.pad
		local head, headSize = label("Title", view.title, CARD.titleKind, if rare then view.light else WHITE, face)
		head.Position = UDim2.fromOffset(x, y)
		y += headSize.Y + CARD.rowGap
		local nameKind = CARD.nameKind
		if Theme.textBoundsAt(view.name, nameKind :: any, nil, scaleOf()).X > columnW then
			nameKind = CARD.nameKindLong
		end
		local name, nameSize = label("Name", view.name, nameKind, WHITE, face)
		name.Position = UDim2.fromOffset(x, y)
		y += nameSize.Y + CARD.rowGap
		-- The rarity pill: white pips and the label on the rarity colour.
		local pipsW = view.pips * (CARD.pipPx + 2)
		local labelBounds = Theme.textBoundsAt(view.label, CARD.pillKind :: any, nil, scaleOf())
		local pill: Frame = Create("Frame", {
			Name = "Rarity",
			BackgroundColor3 = view.color,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(x, y),
			Size = UDim2.fromOffset(CARD.pillPadX * 2 + pipsW + 4 + labelBounds.X + MARGIN, CARD.pillHeight),
			Parent = face,
		})
		Theme.corner(CARD.pillHeight / 2, pill)
		Theme.stroke(INK, 2, pill).ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		for i = 1, view.pips do
			local pip: Frame = Create("Frame", {
				Name = "Pip" .. i,
				BackgroundColor3 = WHITE,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, CARD.pillPadX + (i - 1) * (CARD.pipPx + 2), 0.5, 0),
				Size = UDim2.fromOffset(CARD.pipPx, CARD.pipPx),
				Parent = pill,
			})
			Theme.corner(CARD.pipPx / 2, pip)
			Theme.stroke(INK, 1.5, pip)
		end
		local pillText, _ = label("Label", view.label, CARD.pillKind, WHITE, pill)
		pillText.AnchorPoint = Vector2.new(0, 0.5)
		pillText.Position = UDim2.new(0, CARD.pillPadX + pipsW + 4, 0.5, 0)
		y += CARD.pillHeight + CARD.rowGap
		-- "{have}/{total} in this zone" and its bar.
		local zone, zoneSize = label("Zone", view.zone, CARD.zoneKind, Palette.StickerTextSoft, face)
		zone.Position = UDim2.fromOffset(x, y)
		local barX = x + zoneSize.X + MARGIN + 6
		local bar: Frame = Create("Frame", {
			Name = "ZoneBar",
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromOffset(barX, y + zoneSize.Y / 2),
			Size = UDim2.fromOffset(math.max(w - CARD.pad - barX, 0), CARD.barHeight),
			ClipsDescendants = true,
			Parent = face,
		})
		Theme.corner(CARD.barHeight / 2, bar)
		Create("Frame", {
			Name = "Fill",
			BackgroundColor3 = YELLOW,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(view.fill, 1),
			Parent = bar,
		})
		-- NEW! over the top right corner.
		if view.isNew then
			local text = Strings.highway.catch.new
			local bounds = Theme.textBoundsAt(text, CARD.badgeKind :: any, nil, scaleOf())
			local badge, badgeFace = sticker(
				"New",
				Vector2.new(bounds.X + MARGIN + CARD.badgePadX * 2, CARD.badgeHeight),
				Palette.StickerRedTop,
				Palette.StickerRedEnd,
				CARD.badgeHeight / 2,
				3,
				3,
				holder
			)
			badge.AnchorPoint = Vector2.new(1, 0.5)
			badge.Position = UDim2.new(1, CARD.badgePadX / 2, 0, 0)
			badge.Rotation = CARD.badgeTurn
			local badgeText, _ = label("Text", text, CARD.badgeKind, WHITE, badgeFace)
			badgeText.AnchorPoint = Vector2.new(0.5, 0.5)
			badgeText.Position = UDim2.fromScale(0.5, 0.5)
		end
		-- Epic and up: two twinkling stars at its corners.
		if view.rank >= 4 and image(STAR) then
			for i, px in CARD.starPx do
				local twinkle: ImageLabel = Create("ImageLabel", {
					Name = "Star" .. i,
					BackgroundTransparency = 1,
					Image = image(STAR) :: string,
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = if i == 1 then UDim2.fromOffset(0, 0) else UDim2.new(1, -px, 1, 0),
					Size = UDim2.fromOffset(px, px),
					ZIndex = 3,
					Parent = holder,
				})
				if not reducedOf() then
					UiIdle.add(twinkle, "twinkle", { delayS = (i - 1) * 0.7 })
				end
			end
		end
		-- In, hold, out.
		local reduced = reducedOf()
		local inS, holdS, outS = CARD.inMs / MS, CARD.holdMs / MS, CARD.outMs / MS
		local function place(dx: number)
			holder.Position = UDim2.new(1, -METER.right + dx, 0, METER.top)
		end
		local function gone()
			if card == holder then
				card = nil
				cardOn = false
			end
			holder:Destroy()
		end
		local leaving = false
		local function out()
			if leaving or card ~= holder then
				return
			end
			leaving = true
			if reducedOf() then
				run("card", 0, function() end, gone)
				return
			end
			local from = holder.Position.X.Offset + METER.right
			run("card", outS, function(u: number)
				place(from + (w + METER.right + CARD.slidePx - from) * u * u)
			end, gone)
		end
		cardOut = out
		if reduced then
			run("card", holdS + inS, function() end, out)
			return
		end
		run("card", inS, function(u: number)
			place(CARD.slidePx * (1 - backOut(u)))
		end, function()
			run("card", holdS, function() end, out)
		end)
	end

	function hud.hideCard(_: Hud)
		local out = cardOut
		if out and cardOn then
			out()
		end
	end

	function hud.fly(_: Hud, kind: string, color: Color3, target: GuiObject?)
		local old = flyFrame
		if old then
			old:Destroy()
		end
		local scale = math.max(scaleOf(), 1e-3)
		local base = root.AbsolutePosition
		local area = root.AbsoluteSize / scale
		local to = if target
			then (target.AbsolutePosition + target.AbsoluteSize / 2 - base) / scale
			else Vector2.new(FLY.px, area.Y / 2)
		local from = Vector2.new(area.X * FLY.fromX, area.Y * FLY.fromY)
		local holder: Frame = Create("Frame", {
			Name = "CatchFly",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Parent = root,
		})
		flyFrame = holder
		-- The halo round the Squishies button and "+1" beside it (shown when the bubble arrives).
		local targetSize = if target then target.AbsoluteSize / scale else Vector2.new(FLY.px, FLY.px)
		local halo: Frame = Create("Frame", {
			Name = "Halo",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(to.X, to.Y),
			Size = UDim2.fromOffset(targetSize.X, targetSize.Y),
			Visible = false,
			Parent = holder,
		})
		Theme.corner(math.min(targetSize.X, targetSize.Y) * 0.28, halo)
		local haloStroke = Theme.stroke(WHITE, FLY.halo, halo)
		local plus, plusSize = label("Plus", Strings.highway.catch.plusOne, FLY.plusKind, YELLOW, holder)
		plus.AnchorPoint = Vector2.new(0, 0.5)
		plus.Position = UDim2.fromOffset(to.X + targetSize.X / 2 + 4, to.Y - targetSize.Y / 2 + plusSize.Y / 2)
		plus.Visible = false
		local pop: UIScale = Create("UIScale", { Parent = plus })
		-- A curve through a point arc x the distance above the middle (a quadratic Bezier).
		local mid = (from + to) / 2 - Vector2.new(0, (from - to).Magnitude * FLY.arc)
		local function curve(s: number): Vector2
			return from:Lerp(mid, s):Lerp(mid:Lerp(to, s), s)
		end
		-- Home's dotted flight line: a white dot every dotGap px along the curve (none at its two ends), each gone as
		-- the bubble passes it. Made before the bubble so the bubble draws over them.
		local dots: { { s: number, dot: Frame } } = {}
		if not reducedOf() then
			local steps = math.max(8, math.ceil(((from - mid).Magnitude + (mid - to).Magnitude) / 4))
			local length, last = 0, from
			for i = 1, steps do
				local p = curve(i / steps)
				length += (p - last).Magnitude
				last = p
			end
			local walked, nextAt = 0, FLY.dotGap
			last = from
			for i = 1, steps do
				local s = i / steps
				local p = curve(s)
				walked += (p - last).Magnitude
				last = p
				if walked >= nextAt and walked <= length - FLY.dotGap then
					nextAt += FLY.dotGap
					local dot: Frame = Create("Frame", {
						Name = "Dot",
						BackgroundColor3 = WHITE,
						AnchorPoint = Vector2.new(0.5, 0.5),
						Position = UDim2.fromOffset(p.X, p.Y),
						Size = UDim2.fromOffset(FLY.dotPx, FLY.dotPx),
						Parent = holder,
					})
					Theme.corner(FLY.dotPx / 2, dot)
					Theme.stroke(INK, 1.5, dot)
					table.insert(dots, { s = s, dot = dot })
				end
			end
		end
		local bubble: Frame = Create("Frame", {
			Name = "Bubble",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.75,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(from.X, from.Y),
			Size = UDim2.fromOffset(FLY.px, FLY.px),
			Parent = holder,
		})
		Theme.corner(FLY.px / 2, bubble)
		Theme.stroke(color, 3, bubble)
		local art = SquishyImage.new(kind, { size = math.floor(FLY.px * 0.7), name = "Squishy", parent = bubble })
		art.root.AnchorPoint = Vector2.new(0.5, 0.5)
		art.root.Position = UDim2.fromScale(0.5, 0.5)
		local function arrive()
			bubble.Visible = false
			halo.Visible = true
			plus.Visible = true
			run("plus", FLY.plusMs / MS, function(u: number)
				pop.Scale = if reducedOf() then 1 else 0.3 + 0.7 * backOut(math.min(u * 2.5, 1))
				local fade = math.clamp((u - 0.6) / 0.4, 0, 1)
				plus.TextTransparency = fade
				haloStroke.Transparency = fade
			end, function()
				if flyFrame == holder then
					flyFrame = nil
				end
				holder:Destroy()
			end)
		end
		if reducedOf() then
			arrive()
			return
		end
		run("fly", FLY.ms / MS, function(u: number)
			local e = 1 - (1 - u) * (1 - u)
			local p = curve(e)
			bubble.Position = UDim2.fromOffset(p.X, p.Y)
			for _, d in dots do
				if d.s <= e then
					d.dot.Visible = false
				end
			end
			local s = 1 - 0.35 * e
			bubble.Size = UDim2.fromOffset(FLY.px * s, FLY.px * s)
		end, arrive)
	end

	function hud.destroy(_: Hud)
		for _, handle in runs do
			handle:disconnect()
		end
		table.clear(runs)
		if chipPulse then
			chipPulse:remove()
			chipPulse = nil
		end
		card, flyFrame, chip, cardOn, cardOut = nil, nil, nil, false, nil
		root:Destroy()
	end

	return hud
end

return CatchHud
