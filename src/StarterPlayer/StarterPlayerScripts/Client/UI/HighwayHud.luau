--!strict
-- HighwayHud (client only). P13v4 (owner 2026-10-19: copy the TikTok throw's "camera, screen and big pops"; work/pens3/
-- p13v4/SPEC.md 4.5, 4.6): the throw screen in SD_Highway (UIController.screenGui("SD_Highway",
-- Config.UI.Highway.gui)).
-- Diego has no highway HUD yet: every part is a [P] stand-in in his sticker look (Theme kinds, Palette tokens named in
-- Config.UI.Highway, his cta Button), sized from Theme.textBoundsAt (no AutomaticSize under the UIScale).
--   * The flight lines (setFlight(view), nil hides them): the distance "{distance} studs" top centre (hud.topPx), the
--     zone "Zone {n} • {biome}" under it, the rings "RINGS {hit}/{total}" under that (hud.gapPx apart); punch("rings" |
--     "zone") nudges one (Config.UI.motion.toast's nudgeScale over nudgeMs [P]). The boost button bottom centre
--     (hud.boost) while view.boost is given: Diego's cta Button as is, its label by input (boostText), its subtext the
--     fuel or "NO FUEL" (then disabled); not selectable (R2 boosts on a gamepad); its press calls onBoost.
--   * The timing bar (setBar(shown, value)), bottom centre (hud.bar): the trough, the PERFECT part centred (barZone)
--     with its "PERFECT" chip, the marker at value (0..1).
--   * Pops (pop(lines)): 1-3 lines centred at pop.centreY, but never over the flight lines (popShift: a phone's short
--     canvas puts centreY on them), a big kind then small ones; scale fromScale -> 1 (Back Out)
--     over inMs, held holdMs, faded out over outMs, then removed; a new pop replaces the old one. ReducedMotion: no
--     scale, a fade in and out only.
-- Phone first: the kinds switch to their *Compact ones while compact() (UIController.layoutClass() == "compact").
-- API: HighwayHud.new(spec) -> Hud; hud:setBar(shown, value?); hud:setFlight(view?); hud:pop(lines);
-- hud:punch(line); hud:destroy(); pure zoneText(n), ringsText(hit, total), boostText(fuel, input), barZone(),
-- popShift(canvas, height, floor).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)
local WorldLayout = require(Shared.World.WorldLayout)

local UI = script.Parent
local Client = UI.Parent
local Button = require(UI.Components.Button)
local Create = require(UI.Create)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

export type Line = { text: string, big: boolean, color: string } -- color: a Palette token name
-- Claude Design's zone banner (zoneBanner): the zone's name in its colour (a Palette token), "Recommended:" and the
-- value, ready (green tick) or too weak (red "!"), and the difficulty 1..7 (face, tag colour) with its tag text.
export type Banner = {
	name: string,
	nameColor: string,
	label: string,
	value: string,
	ready: boolean,
	difficulty: number,
	tag: string,
}
export type View = {
	studs: number,
	biome: number,
	ringsHit: number,
	ringsTotal: number,
	boost: { fuel: number, input: Enum.PreferredInput }?,
}
export type Spec = {
	gui: Instance,
	onBoost: () -> (),
	scheduler: Scheduler.Scheduler?, -- default: the client's
	scale: (() -> number)?, -- the gui's UI scale (text measuring); default 1
	compact: (() -> boolean)?, -- the phone layout; default false
	reduced: (() -> boolean)?, -- ReducedMotion; default Tweens.reducedMotion
}
export type Hud = {
	setBar: (self: Hud, shown: boolean, value: number?) -> (),
	setFlight: (self: Hud, view: View?) -> (),
	pop: (self: Hud, lines: { Line }) -> (),
	zoneBanner: (self: Hud, banner: Banner?) -> (),
	punch: (self: Hud, line: "rings" | "zone") -> (),
	destroy: (self: Hud) -> (),
}

-- Constants

local U = Config.UI.Highway
local HUD = U.hud
local POP = U.pop
local NUDGE = Config.UI.motion.toast -- [P] the line punch reuses the toast nudge (nudgeScale over nudgeMs)
local HALF = Config.Economy.Highway.timing.perfectHalfWidth
local MEASURE_MARGIN_PX = 2
local CHIP_KIND: Theme.TextKind = HUD.bar.labelKind :: any
local BACK = 1.70158 -- Back Out's overshoot (Enum.EasingStyle.Back's)

-- Module table

local HighwayHud = {}

-- Private

local function color(token: string): Color3
	return (Palette :: any)[token] or Palette.White
end

local function backOut(u: number): number
	local v = u - 1
	return 1 + (BACK + 1) * v * v * v + BACK * v * v
end

-- Public: pure

function HighwayHud.zoneText(biome: number): string
	local def = WorldLayout.Highway.biomes[biome] or WorldLayout.Highway.biomes[1]
	return Strings.format(Strings.highway.screen.zone, { n = biome, biome = Strings.resolve(def.nameKey) or "" })
end

function HighwayHud.ringsText(hit: number, total: number): string
	return Strings.format(Strings.highway.screen.rings, { hit = hit, total = total })
end

function HighwayHud.boostText(fuel: number, input: Enum.PreferredInput): (string, string)
	local s = Strings.highway.screen
	local action = if input == Enum.PreferredInput.Touch
		then s.boost.touch
		elseif input == Enum.PreferredInput.Gamepad then s.boost.gamepad
		else s.boost.mouse
	local line = if fuel > 0 then Strings.format(s.fuel, { fuel = fuel }) else s.noFuel
	return action, line
end

function HighwayHud.barZone(): (number, number)
	return 0.5 - HALF, 2 * HALF
end

-- How far (base px) a pop `height` high, centred at pop.centreY of a `canvas` high, moves down so its top is at least
-- `floor` (the flight lines' bottom + a gap); 0 when it already clears it.
function HighwayHud.popShift(canvas: number, height: number, floor: number): number
	return math.max(floor - (POP.centreY * canvas - height / 2), 0)
end

-- Public: the screen

function HighwayHud.new(spec: Spec): Hud
	local gui = spec.gui
	local scheduler = spec.scheduler or Scheduler.default()
	local scaleOf = spec.scale or function(): number
		return 1
	end
	local compactOf = spec.compact or function(): boolean
		return false
	end
	local reducedOf = spec.reduced or Tweens.reducedMotion

	local root: Frame = Create("Frame", {
		Name = "HighwayHud",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	})

	-- A measured one-line label (base px from Theme.textBoundsAt) in its own holder with a UIScale (the punch).
	local function textLine(name: string, kindOf: () -> Theme.TextKind, tone: Color3, parent: Instance)
		local holder: Frame = Create("Frame", {
			Name = name .. "Line",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = parent,
		})
		local punch: UIScale = Create("UIScale", { Parent = holder })
		local label = Theme.label({
			Name = name,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = holder,
		}, kindOf(), nil, tone)
		label.TextWrapped = false
		local shown: { text: string, kind: Theme.TextKind? } = { text = "", kind = nil }
		-- Sets the text (re-measured only when it or the kind changed); returns the holder's height.
		local function set(text: string): number
			local kind: Theme.TextKind = kindOf()
			if text ~= shown.text or kind ~= shown.kind then
				shown.text, shown.kind = text, kind
				if label:GetAttribute("SD_TextKind") ~= kind then
					Theme.text(label, kind, nil, tone)
					label.TextWrapped = false
				end
				label.Text = text
				local bounds = Theme.textBoundsAt(text, kind, nil, scaleOf())
				holder.Size = UDim2.fromOffset(bounds.X + MEASURE_MARGIN_PX, bounds.Y)
			end
			return holder.Size.Y.Offset
		end
		return holder, label, punch, set
	end

	local function kind(regular: string, compact: string): () -> Theme.TextKind
		return function(): Theme.TextKind
			return (if compactOf() then compact else regular) :: Theme.TextKind
		end
	end

	-- A scheduler run of `seconds`: fn(u) every frame (u 0..1), done() at the end.
	local function run(seconds: number, fn: (u: number) -> (), done: (() -> ())?): Scheduler.Handle
		local elapsed = 0
		fn(0)
		return scheduler:add(function(dt: number): boolean
			elapsed += dt
			local u = if seconds > 0 then math.min(elapsed / seconds, 1) else 1
			fn(u)
			if u >= 1 and done then
				done()
			end
			return u < 1
		end, "render")
	end

	-- The flight lines.
	local flight: Frame = Create("Frame", {
		Name = "HighwayFlight",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = root,
	})
	local textTone = color(HUD.colors.text)
	local distanceHolder, _, _, setDistance =
		textLine("Distance", kind(HUD.distanceKind, HUD.distanceKindCompact), textTone, flight)
	local zoneHolder, _, zonePunch, setZone =
		textLine("Zone", kind(HUD.zoneKind, HUD.zoneKindCompact), textTone, flight)
	local ringsHolder, _, ringsPunch, setRings =
		textLine("Rings", kind(HUD.ringsKind, HUD.ringsKindCompact), color(HUD.colors.rings), flight)
	local linesBottom = 0 -- base px: the rings line's bottom while the flight lines show
	local boost: Button.Button? = nil
	local boostShown = { action = "", fuel = "" }

	-- The timing bar.
	local bar: Frame = Create("Frame", {
		Name = "HighwayBar",
		BackgroundColor3 = color(HUD.colors.barTrack),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HUD.bar.bottomPx),
		Size = UDim2.new(HUD.bar.maxWidthShare, 0, 0, HUD.bar.heightPx),
		Visible = false,
		Parent = root,
	})
	Create("UISizeConstraint", { MaxSize = Vector2.new(HUD.bar.widthPx, HUD.bar.heightPx), Parent = bar })
	Theme.corner(HUD.bar.heightPx / 2, bar)
	local zoneLeft, zoneWidth = HighwayHud.barZone()
	local perfect: Frame = Create("Frame", {
		Name = "Perfect",
		BackgroundColor3 = color(HUD.colors.barZone),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(zoneLeft, 0),
		Size = UDim2.fromScale(zoneWidth, 1),
		Parent = bar,
	})
	local chipText = Strings.highway.screen.perfectZone
	local chipBounds = Theme.textBoundsAt(chipText, CHIP_KIND, nil, scaleOf())
	local chip = Theme.label({
		Name = "PerfectLabel",
		Text = chipText,
		AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(chipBounds.X + MEASURE_MARGIN_PX, chipBounds.Y),
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = perfect,
	}, CHIP_KIND, nil, textTone)
	chip.TextWrapped = false
	local marker: Frame = Create("Frame", {
		Name = "Marker",
		BackgroundColor3 = color(HUD.colors.barMarker),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0, HUD.bar.markerPx, 1, 0),
		Parent = bar,
	})

	local popFrame: Frame? = nil
	local popRun: Scheduler.Handle? = nil
	local punchRuns: { [string]: Scheduler.Handle } = {}

	local hud = {} :: Hud

	function hud.setBar(_: Hud, shown: boolean, value: number?)
		bar.Visible = shown
		if shown and value ~= nil then
			marker.Position = UDim2.fromScale(math.clamp(value, 0, 1), 0.5)
		end
	end

	function hud.setFlight(_: Hud, view: View?)
		flight.Visible = view ~= nil
		local wantsBoost = view ~= nil and view.boost ~= nil
		if boost then
			boost.root.Visible = wantsBoost
		end
		if view == nil then
			return
		end
		local distance = Strings.format(Strings.highway.studs, { distance = Format.distance(math.max(view.studs, 0)) })
		local y = HUD.topPx
		distanceHolder.Position = UDim2.new(0.5, 0, 0, y)
		y += setDistance(distance) + HUD.gapPx
		zoneHolder.Position = UDim2.new(0.5, 0, 0, y)
		y += setZone(HighwayHud.zoneText(view.biome)) + HUD.gapPx
		ringsHolder.Position = UDim2.new(0.5, 0, 0, y)
		linesBottom = y + setRings(HighwayHud.ringsText(view.ringsHit, view.ringsTotal))
		local fuel = view.boost
		if fuel == nil then
			return
		end
		local action, line = HighwayHud.boostText(fuel.fuel, fuel.input)
		local made = boost
		if made == nil then
			local b = HUD.boost
			made = Button.new({
				name = "HighwayBoost",
				text = action,
				kind = "cta",
				subtext = line,
				width = math.max(b.minWidthPx, Button.widthFor(action, nil, nil, "cta")),
				height = b.minHeightPx,
				onActivated = spec.onBoost,
				parent = flight,
			})
			local r = (made :: Button.Button).root
			r.AnchorPoint = Vector2.new(0.5, 1)
			r.Position = UDim2.new(0.5, 0, 1, -b.bottomPx)
			r.Selectable = false -- R2 boosts on a gamepad
			boost = made
			boostShown.action, boostShown.fuel = action, line
		end
		local button = made :: Button.Button
		button.root.Visible = true
		if action ~= boostShown.action then
			boostShown.action = action
			button:setText(action)
		end
		if line ~= boostShown.fuel then
			boostShown.fuel = line
			button:setSubtext(line)
		end
		local state: Button.State = if fuel.fuel > 0 then "normal" else "disabled"
		if button:getState() ~= state then
			button:setState(state)
		end
	end

	function hud.punch(_: Hud, which: "rings" | "zone")
		local scale = if which == "rings" then ringsPunch else zonePunch
		local previous = punchRuns[which]
		if previous then
			previous:disconnect()
		end
		if reducedOf() then
			scale.Scale = 1
			return
		end
		punchRuns[which] = run(NUDGE.nudgeMs / 1000, function(u: number)
			scale.Scale = NUDGE.nudgeScale + (1 - NUDGE.nudgeScale) * (1 - (1 - u) * (1 - u))
		end)
	end

	local function clearPop()
		local handle = popRun
		popRun = nil
		if handle then
			handle:disconnect()
		end
		local frame = popFrame
		popFrame = nil
		if frame then
			frame:Destroy()
		end
	end

	function hud.pop(_: Hud, lines: { Line })
		clearPop()
		if #lines == 0 then
			return
		end
		local compact = compactOf()
		local frame: Frame = Create("Frame", {
			Name = "HighwayPop",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, POP.centreY),
			Parent = root,
		})
		local scale: UIScale = Create("UIScale", { Parent = frame })
		local width, y = 0, 0
		for index, line in lines do
			local k: Theme.TextKind = if line.big
				then (if compact then POP.bigKindCompact else POP.bigKind) :: Theme.TextKind
				else (if compact then POP.smallKindCompact else POP.smallKind) :: Theme.TextKind
			local bounds = Theme.textBoundsAt(line.text, k, nil, scaleOf())
			local label = Theme.label({
				Name = "Line" .. index,
				Text = line.text,
				AutomaticSize = Enum.AutomaticSize.None,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, y),
				Size = UDim2.fromOffset(bounds.X + MEASURE_MARGIN_PX, bounds.Y),
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = frame,
			}, k, nil, color(line.color))
			label.TextWrapped = false
			width = math.max(width, bounds.X + MEASURE_MARGIN_PX)
			y += bounds.Y + POP.lineGapPx
		end
		local height = math.max(y - POP.lineGapPx, 0)
		frame.Size = UDim2.fromOffset(width, height)
		if flight.Visible then
			local canvas = root.AbsoluteSize.Y / math.max(scaleOf(), 1e-3) -- base px (the gui's UIScale)
			local shift = HighwayHud.popShift(canvas, height, linesBottom + POP.lineGapPx)
			frame.Position = UDim2.new(0.5, 0, POP.centreY, shift)
		end
		popFrame = frame
		local fade = Tweens.fadeGroup(frame)
		local reduced = reducedOf()
		local inS, holdS, outS = POP.inMs / 1000, POP.holdMs / 1000, POP.outMs / 1000
		local total = inS + holdS + outS
		popRun = run(total, function(u: number)
			local t = u * total
			if reduced then
				scale.Scale = 1
				fade:setAlpha(math.min(t / math.max(inS, 1e-3), 1, (total - t) / math.max(outS, 1e-3)))
			else
				scale.Scale = POP.fromScale + (1 - POP.fromScale) * backOut(math.min(t / math.max(inS, 1e-3), 1))
				fade:setAlpha(math.clamp((total - t) / math.max(outS, 1e-3), 0, 1))
			end
		end, function()
			if popFrame == frame then
				popRun = nil
				popFrame = nil
				frame:Destroy()
			end
		end)
	end

	-- Claude Design's zone banner (Config.UI.Highway.banner; see its notes there).
	local BN = U.banner
	local bannerFrame: Frame? = nil
	local bannerRun: Scheduler.Handle? = nil

	local function clearBanner()
		local handle = bannerRun
		bannerRun = nil
		if handle then
			handle:disconnect()
		end
		local frame = bannerFrame
		bannerFrame = nil
		if frame then
			frame:Destroy()
		end
	end

	local function round(object: GuiObject, scale: number)
		Create("UICorner", { CornerRadius = UDim.new(scale, 0), Parent = object })
	end

	local function shape(parent: Instance, name: string, x: number, y: number, w: number, h: number, tone: Color3): Frame
		return Create("Frame", {
			Name = name,
			BackgroundColor3 = tone,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromScale(w, h),
			Parent = parent,
		})
	end

	-- Design's difficulty face (faceVM): an ink ring, the disc in the difficulty colour with a highlight, the eyes,
	-- the brows (none, a raised left one, or both angled), the mouth (smile / frown halves, a flat pill, an open
	-- rounded box with teeth), Frames only.
	local function face(parent: Instance, px: number, level: number): Frame
		local look = BN.faces[level] or BN.faces[1]
		local ring = shape(parent, "Face", 0, 0, 0, 0, color(BN.colors.ink))
		ring.Size = UDim2.fromOffset(px, px)
		round(ring, 0.5)
		local inner = 1 - 2 * BN.ringShare
		local disc = shape(ring, "Disc", BN.ringShare, BN.ringShare, inner, inner, color(BN.difficulty[level] or BN.difficulty[1]))
		disc.ClipsDescendants = true
		round(disc, 0.5)
		local shine = shape(disc, "Shine", 0.14, 0.09, 0.34, 0.2, color(BN.colors.highlight))
		shine.BackgroundTransparency = 0.55
		shine.Rotation = -24
		round(shine, 0.5)
		local feature = color(if look.dark then BN.colors.weak else BN.colors.ink)
		local angry = look.brow >= 20
		for _, x in { 0.24, 0.61 } do
			round(shape(disc, "Eye", x, if angry then 0.38 else 0.33, 0.15, if angry then 0.13 else 0.16, feature), 0.5)
		end
		if look.brow ~= 0 then
			local left = shape(disc, "Brow", 0.18, if look.brow == -1 then 0.17 else 0.24, 0.26, 0.07, feature)
			left.Rotation = if look.brow == -1 then -12 else look.brow
			round(left, 0.5)
		end
		if look.brow > 0 then
			local right = shape(disc, "Brow", 0.56, 0.24, 0.26, 0.07, feature)
			right.Rotation = -look.brow
			round(right, 0.5)
		end
		local mouth = shape(disc, "Mouth", (50 - look.mW / 2) / 100, look.mT / 100, look.mW / 100, look.mH / 100, feature)
		if look.mouth == "smile" or look.mouth == "frown" then
			-- Half an ellipse: the mouth box clips a whole one, its lower (smile) or upper (frown) half showing.
			mouth.BackgroundTransparency = 1
			mouth.ClipsDescendants = true
			round(shape(mouth, "Curve", 0, if look.mouth == "smile" then -1 else 0, 1, 2, feature), 0.5)
		else
			mouth.ClipsDescendants = true
			round(mouth, if look.mouth == "flat" then 0.5 else 0.3)
		end
		if look.teeth then
			shape(mouth, "Teeth", 0.12, 0, 0.76, 0.34, color(BN.colors.highlight))
		end
		return ring
	end

	-- A one-line label measured for the gui's UIScale (no AutomaticSize under it).
	local function fixed(parent: Instance, name: string, text: string, textKind: Theme.TextKind, tone: Color3): (TextLabel, Vector2)
		local bounds = Theme.textBoundsAt(text, textKind, nil, scaleOf())
		local label = Theme.label({
			Name = name,
			Text = text,
			AutomaticSize = Enum.AutomaticSize.None,
			Size = UDim2.fromOffset(bounds.X + MEASURE_MARGIN_PX, bounds.Y),
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = parent,
		}, textKind, nil, tone)
		label.TextWrapped = false
		return label, Vector2.new(bounds.X + MEASURE_MARGIN_PX, bounds.Y)
	end

	function hud.zoneBanner(_: Hud, banner: Banner?)
		clearBanner()
		if banner == nil then
			return
		end
		local compact = compactOf()
		local k = if compact then BN.facePxCompact / BN.facePx else 1
		local facePx = if compact then BN.facePxCompact else BN.facePx
		local badgePx = if compact then BN.badgePxCompact else BN.badgePx
		local nameKind = (if compact then BN.nameKindCompact else BN.nameKind) :: Theme.TextKind
		local lineKind = (if compact then BN.lineKindCompact else BN.lineKind) :: Theme.TextKind
		local ink = color(BN.colors.ink)
		local valueTone = color(if banner.ready then BN.colors.ready else BN.colors.weak)

		local frame: Frame = Create("Frame", {
			Name = "ZoneBanner",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0),
			Parent = root,
		})
		local scrim: Frame = Create("Frame", {
			Name = "Scrim",
			BackgroundColor3 = ink,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Parent = frame,
		})
		Create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.19, BN.scrimEdge),
				NumberSequenceKeypoint.new(0.5, BN.scrimCentre),
				NumberSequenceKeypoint.new(0.81, BN.scrimEdge),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = scrim,
		})
		round(scrim, 0.5)

		-- The face and its tag.
		local faceHolder: Frame = Create("Frame", { Name = "FaceHolder", BackgroundTransparency = 1, Parent = frame })
		face(faceHolder, facePx, banner.difficulty)
		local tagLabel, tagSize = fixed(faceHolder, "Tag", banner.tag, BN.tagKind :: Theme.TextKind, if banner.difficulty == #BN.difficulty then color(BN.colors.tagLight) else ink)
		Theme.noOutline(tagLabel)
		local pill: Frame = Create("Frame", {
			Name = "TagPill",
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = color(BN.difficulty[banner.difficulty] or BN.difficulty[1]),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(tagSize.X + 12 * k, tagSize.Y + 2),
			Position = UDim2.new(0.5, 0, 0, facePx - math.floor(tagSize.Y * 0.5)),
			ZIndex = 2,
			Parent = faceHolder,
		})
		round(pill, 0.5)
		Theme.stroke(ink, math.max(1, 2.5 * k), pill)
		tagLabel.Parent = pill
		tagLabel.AnchorPoint = Vector2.new(0.5, 0.5)
		tagLabel.Position = UDim2.fromScale(0.5, 0.5)
		tagLabel.ZIndex = 3
		local faceH = facePx + math.ceil(tagSize.Y * 0.5) + 2

		-- The name (its colour, an ink stroke and drop) over the line.
		local column: Frame = Create("Frame", { Name = "Column", BackgroundTransparency = 1, Parent = frame })
		local drop, nameSize = fixed(column, "NameDrop", banner.name, nameKind, ink)
		local name = fixed(column, "Name", banner.name, nameKind, color(banner.nameColor))
		for _, label in { drop, name } do
			Theme.noOutline(label)
			Create("UIStroke", {
				Color = ink,
				Thickness = BN.nameStrokePx * k,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
				Parent = label,
			})
		end
		drop.Position = UDim2.fromOffset(0, BN.nameDropPx * k)
		name.ZIndex = 2
		local lineY = nameSize.Y + BN.lineGapPx * k
		local label, labelSize = fixed(column, "Label", banner.label, lineKind, color(BN.colors.label))
		local value, valueSize = fixed(column, "Value", banner.value, lineKind, valueTone)
		local pulse: UIScale = Create("UIScale", { Parent = value })
		local gap = BN.valueGapPx * k
		local lineH = math.max(labelSize.Y, badgePx)
		label.Position = UDim2.fromOffset(0, lineY + (lineH - labelSize.Y) / 2)
		value.Position = UDim2.fromOffset(labelSize.X + gap, lineY + (lineH - valueSize.Y) / 2)
		local badge: Frame = Create("Frame", {
			Name = "Badge",
			BackgroundColor3 = valueTone,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(badgePx, badgePx),
			Position = UDim2.fromOffset(labelSize.X + gap + valueSize.X + gap, lineY + (lineH - badgePx) / 2),
			Parent = column,
		})
		round(badge, 0.5)
		Theme.stroke(ink, math.max(1, 2.5 * k), badge)
		if banner.ready then
			-- Design's tick: a box's right and bottom edges turned 40 degrees.
			local tick = shape(badge, "Tick", 0.33, 0.14, 0.3, 0.52, ink)
			tick.BackgroundTransparency = 1
			tick.Rotation = 40
			local edge = math.max(2, math.floor(badgePx * 0.13))
			local right = shape(tick, "Edge", 1, 0, 0, 1, ink)
			right.AnchorPoint = Vector2.new(1, 0)
			right.Size = UDim2.new(0, edge, 1, 0)
			local bottom = shape(tick, "Edge", 0, 1, 1, 0, ink)
			bottom.AnchorPoint = Vector2.new(0, 1)
			bottom.Size = UDim2.new(1, 0, 0, edge)
		else
			local bang = fixed(badge, "Bang", "!", BN.tagKind :: Theme.TextKind, ink)
			Theme.noOutline(bang)
			bang.AnchorPoint = Vector2.new(0.5, 0.5)
			bang.Position = UDim2.fromScale(0.5, 0.5)
		end
		local columnW = math.max(nameSize.X, labelSize.X + gap + valueSize.X + gap + badgePx)
		local columnH = lineY + lineH
		column.Size = UDim2.fromOffset(columnW, columnH)

		-- The row inside the padding, both halves centred on its height.
		local padL, padR, padT, padB = BN.padLeftPx * k, BN.padRightPx * k, BN.padTopPx * k, BN.padBottomPx * k
		local rowH = math.max(faceH, columnH)
		faceHolder.Size = UDim2.fromOffset(facePx, faceH)
		faceHolder.Position = UDim2.fromOffset(padL, padT + (rowH - faceH) / 2)
		column.Position = UDim2.fromOffset(padL + facePx + BN.gapPx * k, padT + (rowH - columnH) / 2)
		frame.Size = UDim2.fromOffset(padL + facePx + BN.gapPx * k + columnW + padR, padT + rowH + padB)
		local top = (if flight.Visible then linesBottom else HUD.topPx) + BN.topGapPx
		frame.Position = UDim2.new(0.5, 0, 0, top)
		bannerFrame = frame

		local fade = Tweens.fadeGroup(frame)
		local reduced = reducedOf()
		local inS, holdS, outS = BN.inMs / 1000, BN.holdMs / 1000, BN.outMs / 1000
		local pulseS = BN.pulseMs / 1000
		local total = inS + holdS + outS
		bannerRun = run(total, function(u: number)
			local t = u * total
			local alpha = math.min(t / math.max(inS, 1e-3), 1, (total - t) / math.max(outS, 1e-3))
			fade:setAlpha(alpha)
			if reduced then
				return
			end
			local y = 0
			if t < inS then
				y = -BN.dropPx * k * (1 - backOut(t / math.max(inS, 1e-3)))
			elseif t > inS + holdS then
				y = -BN.risePx * k * ((t - inS - holdS) / math.max(outS, 1e-3))
			end
			frame.Position = UDim2.new(0.5, 0, 0, top + y)
			if not banner.ready and t >= inS and t <= inS + pulseS then
				pulse.Scale = 1 + (BN.pulseScale - 1) * math.sin(math.pi * (t - inS) / pulseS)
			else
				pulse.Scale = 1
			end
		end, function()
			if bannerFrame == frame then
				bannerRun = nil
				bannerFrame = nil
				frame:Destroy()
			end
		end)
	end

	function hud.destroy(_: Hud)
		clearBanner()
		clearPop()
		for _, handle in punchRuns do
			handle:disconnect()
		end
		table.clear(punchRuns)
		local b = boost
		boost = nil
		if b then
			b:destroy()
		end
		root:Destroy()
	end

	return hud
end

return HighwayHud
