--!strict
-- PodDial (client only). Squish Pods HUD (2026-11-03; `H:n` = "Squishy Duels In-Game HUD.dc.html" line n): Diego's pod
-- dial (H:166-185), built by AbilityBarController on its canvas (Config.UI.Pod) and drawn each frame from
-- PodFormat.state. Idle: the box glyph and POD. Rolling: the dial grows to 1.12 inside a turning rainbow ring (H:178),
-- the power-up icons roll in from the top on H:130's slowing schedule (another one each time, H:157) and 8 shards fly
-- out (H:176). Landed: the result pops in (H:16) with the white burst ring (H:179), the body's pop (H:18) and the chip
-- over the dial (H:184). Active: the ring round the icon drains in the power-up's colour (H:181) and the tag counts
-- the seconds (H:183). Every motion is worked out from the state's times (no tweens to track); Reduce Motion shows
-- the resting look. Every H px is scaled by size / Pod.designPx.
-- API: PodDial.new(parent, size) -> dial; dial.frame (the caller places it; AnchorPoint centre); dial:update(state,
-- clock); dial:destroy().

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent
local AbilityBarFormat = require(UI.AbilityBarFormat)
local Create = require(UI.Create)
local PodFormat = require(UI.PodFormat)
local Theme = require(UI.Theme)
local Tweens = require(UI.Parent.Anim.Tweens)

-- Types

export type Dial = {
	frame: Frame,
	update: (self: Dial, state: PodFormat.State, clock: number) -> (),
	destroy: (self: Dial) -> (),
}

-- Constants

local POD = Config.UI.Pod
local POWER_UPS = Config.Match.PowerUps
local INK = Palette.PodInk
local WHITE = Palette.White
local REST = Palette.PodDial:Lerp(WHITE, 0.08) -- H:181 rgba(255,255,255,.08) over the dial
local SCHEDULE = PodFormat.rollSchedule(POWER_UPS.rollSeconds * 1000)
local SHARD_COLORS = { -- H:176
	Palette.PodSpinPink,
	Palette.PodTag,
	Palette.PodSpinBlue,
	Palette.PodSpinMint,
	Palette.PodSpinLilac,
	Palette.PodThrowBoostEnd,
	WHITE,
	Palette.PodTag,
}
local SPIN = ColorSequence.new({ -- H:178 conic-gradient(#ff8fb8,#ffd95e,#9ff0c8,#7fd0ff,#c6a6ff,#ff8fb8)
	ColorSequenceKeypoint.new(0, Palette.PodSpinPink),
	ColorSequenceKeypoint.new(0.2, Palette.PodSpinYellow),
	ColorSequenceKeypoint.new(0.4, Palette.PodSpinMint),
	ColorSequenceKeypoint.new(0.6, Palette.PodSpinBlue),
	ColorSequenceKeypoint.new(0.8, Palette.PodSpinLilac),
	ColorSequenceKeypoint.new(1, Palette.PodSpinPink),
})
local LAND_EASE = Tweens.bezier(0.22, 1, 0.36, 1) -- H:16, H:18, H:19
local GROW_EASE = Tweens.bezier(0.3, 1.4, 0.5, 1) -- H:180
local SHARD_EASE = Tweens.bezier(0.2, 0.8, 0.4, 1) -- H:176
local EASE_OUT = Tweens.bezier(0, 0, 0.58, 1) -- CSS ease-out (H:179)

-- Module table

local PodDial = {}

-- Private

local function round(object: GuiObject, radius: UDim?)
	Create("UICorner", { CornerRadius = radius or UDim.new(0.5, 0), Parent = object })
end

-- A centred square `px` wide in `parent`.
local function centred(className: string, name: string, px: number, z: number, parent: Instance): any
	return Create(className, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(px, px),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = parent,
	})
end

-- One half of the drain's "rest" disc (AbilityBarController's sweepHalf: its mask clear on its first half).
local function sweepHalf(parent: Instance, rightSide: boolean, z: number): UIGradient
	local half: Frame = Create("Frame", {
		Name = if rightSide then "Right" else "Left",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromScale(if rightSide then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		ZIndex = z,
		Parent = parent,
	})
	local disc: Frame = Create("Frame", {
		Name = "Disc",
		BackgroundColor3 = REST,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(if rightSide then -1 else 0, 0),
		Size = UDim2.fromScale(2, 1),
		ZIndex = z,
		Parent = half,
	})
	round(disc)
	return Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(0.501, 0),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = disc,
	})
end

local function label(name: string, z: number, parent: Instance): TextLabel
	return Create("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.font("Button"),
		TextColor3 = INK,
		Text = "",
		ZIndex = z,
		Parent = parent,
	})
end

local function textWidth(text: string, px: number): number
	return Theme.textWidth(text, "Chip") * px / Theme.textSize("Chip")
end

-- Public

function PodDial.new(parent: Instance, size: number): Dial
	local k = size / POD.designPx
	local rim = POD.rimPx * k
	local bodyPx = size - 2 * rim -- CSS border-box: the rim is the UIStroke outside
	local innerPx = bodyPx - 2 * POD.innerInsetPx * k

	local frame: Frame = Create("Frame", {
		Name = "PodDial",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local spin: Frame = centred("Frame", "Spin", size + 2 * POD.spinRingPx * k, 1, frame)
	spin.BackgroundTransparency = 0
	spin.BackgroundColor3 = WHITE
	spin.Visible = false
	round(spin)
	local spinGradient: UIGradient = Create("UIGradient", { Color = SPIN, Parent = spin })

	local burst: Frame = centred("Frame", "Burst", size + 2 * (POD.burst.insetPx - POD.burst.borderPx) * k, 2, frame)
	burst.Visible = false
	round(burst)
	local burstStroke = Theme.stroke(WHITE, POD.burst.borderPx * k, burst)
	local burstScale: UIScale = Create("UIScale", { Parent = burst })

	local body: Frame = centred("Frame", "Body", bodyPx, 3, frame)
	body.BackgroundTransparency = 0
	body.BackgroundColor3 = Palette.PodDial
	round(body)
	Theme.stroke(Palette.PodDialRim, rim, body)
	local bodyScale: UIScale = Create("UIScale", { Parent = body })
	local ring: Frame = centred("Frame", "Ring", bodyPx, 4, body)
	ring.BackgroundTransparency = 0
	ring.Visible = false
	round(ring)
	local rest: Frame = centred("Frame", "Rest", bodyPx, 5, body)
	local restRight = sweepHalf(rest, true, 5)
	local restLeft = sweepHalf(rest, false, 5)

	local inner: CanvasGroup = centred("CanvasGroup", "Inner", innerPx, 6, body)
	inner.BackgroundTransparency = 0
	inner.BackgroundColor3 = Palette.PodDial
	round(inner)
	local tile: Frame = centred("Frame", "Tile", innerPx, 7, inner)
	tile.BackgroundTransparency = 0
	tile.BackgroundColor3 = WHITE
	round(tile)
	local tileGradient: UIGradient = Create("UIGradient", { Rotation = POD.tileRotation, Parent = tile })
	local tileScale: UIScale = Create("UIScale", { Parent = tile })
	local glyph: ImageLabel = centred("ImageLabel", "Glyph", innerPx * POD.iconShare * POD.glyphBox, 8, tile)
	glyph.ScaleType = Enum.ScaleType.Fit
	local flash: Frame = centred("Frame", "Flash", innerPx, 9, tile)
	flash.BackgroundColor3 = WHITE
	round(flash)
	local box: ImageLabel = centred("ImageLabel", "Box", innerPx * 0.72, 8, inner) -- H:175
	box.Image = AssetTable.image("img.pod.box") or ""
	box.ImageTransparency = 0.25
	box.ScaleType = Enum.ScaleType.Fit

	local T = POD.tag
	local tag: Frame = Create("Frame", {
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, size - (T.overlapPx - T.borderPx) * k),
		BackgroundColor3 = Palette.PodTag,
		ZIndex = 11,
		Parent = frame,
	})
	round(tag)
	Theme.stroke(INK, T.borderPx * k, tag)
	local tagDrop: Frame = Create("Frame", {
		Name = "Drop",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, size - (T.overlapPx - T.borderPx - T.dropPx) * k),
		BackgroundColor3 = INK,
		ZIndex = 10,
		Parent = frame,
	})
	round(tagDrop)
	Theme.stroke(INK, T.borderPx * k, tagDrop)
	local tagText = label("Text", 12, tag)
	local tagStroke: UIStroke = Create("UIStroke", { Color = INK, Thickness = k, Enabled = false, Parent = tagText })

	local C = POD.chip
	local chip: CanvasGroup = Create("CanvasGroup", {
		Name = "Chip",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 13,
		Parent = frame,
	})
	local chipDrop: Frame = Create("Frame", { -- H:184 box-shadow 0 3px 0 ink
		Name = "Drop",
		Position = UDim2.fromOffset(C.borderPx * k, (C.borderPx + C.dropPx) * k),
		BackgroundColor3 = INK,
		ZIndex = 13,
		Parent = chip,
	})
	round(chipDrop)
	Theme.stroke(INK, C.borderPx * k, chipDrop)
	local chipFace: Frame = Create("Frame", {
		Name = "Face",
		Position = UDim2.fromOffset(C.borderPx * k, C.borderPx * k),
		ZIndex = 14,
		Parent = chip,
	})
	round(chipFace)
	Theme.stroke(INK, C.borderPx * k, chipFace)
	local chipText = label("Text", 15, chipFace)
	chipText.TextColor3 = WHITE
	Create("UIStroke", { Color = INK, Thickness = k, Parent = chipText }) -- H:184 text-shadow 0 2px 0 ink
	local chipScale: UIScale = Create("UIScale", { Parent = chip })

	local S = POD.shards
	local shards: { Frame } = {}
	for i, color in SHARD_COLORS do
		local shard: Frame = centred("Frame", "Shard" .. i, S.px * k, 16, frame) -- CSS content box: the border is outside
		shard.BackgroundTransparency = 0
		shard.BackgroundColor3 = color
		shard.Visible = false
		round(shard, if i % 2 == 1 then UDim.new(0.5, 0) else UDim.new(0, 3 * k)) -- H:176 (0-based) i%2 ? 3 : 50%
		Theme.stroke(INK, S.borderPx * k, shard)
		table.insert(shards, shard)
	end

	local random = Random.new()
	local tick, shown = -1, 1 -- the spin's last schedule step and the icon it shows (index into the order)
	local rollInAt = -math.huge
	local tagKey: string? = nil
	local chipKey: string? = nil

	local function setTile(kind: string)
		local look = PodFormat.look(kind)
		if look == nil then
			return
		end
		tileGradient.Color = ColorSequence.new(look.top, look.bottom)
		glyph.Image = AssetTable.image(look.icon) or ""
	end

	local function setTag(text: string, active: boolean, color: Color3)
		local key = text .. tostring(active) .. color:ToHex()
		if key == tagKey then
			return
		end
		tagKey = key
		local px = (if active then T.activeTextPx else T.textPx) * k
		local width = math.max(T.minPx * k, textWidth(text, px)) + 2 * T.padPx * k -- CSS min-width on the content box
		local height = (T.heightPx - 2 * T.borderPx) * k
		tag.Size = UDim2.fromOffset(width, height)
		tagDrop.Size = tag.Size
		tag.BackgroundColor3 = color
		tagText.Text = text
		tagText.TextSize = px
		tagText.TextColor3 = if active then WHITE else INK
		tagStroke.Enabled = active
		tagStroke.Thickness = 2 * k
	end

	local function setChip(text: string, color: Color3)
		if chipKey == text .. color:ToHex() then
			return
		end
		chipKey = text .. color:ToHex()
		local width = textWidth(text, C.textPx * k) + 2 * C.padX * k
		local height = (C.heightPx - 2 * C.borderPx) * k
		chipFace.Size = UDim2.fromOffset(width, height)
		chipDrop.Size = chipFace.Size
		chipFace.BackgroundColor3 = color
		chipText.Text = text
		chipText.TextSize = C.textPx * k
		chip.Size = UDim2.fromOffset(width + 2 * C.borderPx * k, height + (2 * C.borderPx + C.dropPx) * k)
	end

	local dial = { frame = frame } :: any

	function dial.update(_self: Dial, state: PodFormat.State, clock: number)
		local reduced = Tweens.reducedMotion()
		local phase = if state.power then state.phase else "idle"
		local power = state.power
		local look = if power then PodFormat.look(power) else nil
		local since = state.since or 0
		local rolling, landed = phase == "rolling", phase == "landed"

		-- the rainbow ring and the body's size (H:178, H:180, H:18)
		spin.Visible = rolling
		if rolling then
			spinGradient.Rotation = if reduced then 0 else (clock * 360 * 1000 / POD.spinTurnMs) % 360
		end
		local bodyK = 1
		if rolling and not reduced then
			bodyK = 1 + (POD.rollingScale - 1) * GROW_EASE(math.min(since * 1000 / POD.growMs, 1))
		elseif rolling then
			bodyK = POD.rollingScale
		elseif landed and not reduced then
			bodyK = PodFormat.keyed({ { 0, 1.12 }, { 0.45, 1.08 }, { 1, 1 } }, since * 1000 / POD.popMs, LAND_EASE)
		end
		bodyScale.Scale = bodyK

		-- the icon: the box when idle, the spin's icons, or the result
		box.Visible = phase == "idle"
		tile.Visible = phase ~= "idle"
		flash.BackgroundTransparency = 1
		tileScale.Scale = 1
		tile.Position = UDim2.fromScale(0.5, 0.5)
		inner.GroupTransparency = 0
		if rolling then
			local step = 0
			for _, t in SCHEDULE do
				if t <= since * 1000 then
					step += 1
				end
			end
			local order = POWER_UPS.order
			if step ~= tick then
				tick = step
				if step == 0 then
					shown = random:NextInteger(1, #order) -- H:155 a random start
				else
					shown = (shown + random:NextInteger(1, #order - 1) - 1) % #order + 1 -- H:157 never the same twice
				end
				rollInAt = clock
				setTile(order[shown])
			end
			if not reduced then
				local u = math.clamp((clock - rollInAt) * 1000 / POD.rollInMs, 0, 1) -- H:15 hg-rollin
				tile.Position = UDim2.fromScale(0.5, 0.5 - 0.8 * (1 - u))
				inner.GroupTransparency = 0.7 * (1 - u)
			end
		elseif power then
			tick = -1
			setTile(power)
			if landed and not reduced then
				local u = since * 1000 / POD.landMs -- H:16 hg-land
				tileScale.Scale = PodFormat.keyed({ { 0, 0.55 }, { 0.6, 1.06 }, { 1, 1 } }, u, LAND_EASE)
				inner.GroupTransparency = 1 - PodFormat.keyed({ { 0, 0 }, { 0.6, 1 }, { 1, 1 } }, u, LAND_EASE)
				local bright = PodFormat.keyed({ { 0, 1.8 }, { 0.6, 1.15 }, { 1, 1 } }, u, LAND_EASE)
				flash.BackgroundTransparency = 1 - math.clamp((bright - 1) / 1.6, 0, 1) -- brightness as a white wash
			end
		end

		-- the drain round the icon (H:181): the power-up's colour over the share left, the faint rest after it
		local fraction = if look and (landed or phase == "active") then state.fraction or 1 else nil
		ring.Visible = fraction ~= nil
		rest.Visible = fraction ~= nil and fraction < 1
		if look and fraction then
			ring.BackgroundColor3 = look.bottom
			local right, left = AbilityBarFormat.sweepRotations(1 - fraction)
			restRight.Rotation = right
			restLeft.Rotation = left
		end

		-- the burst ring on landing (H:179)
		local burstU = since * 1000 / POD.burst.ms
		burst.Visible = landed and not reduced and burstU < 1
		if burst.Visible then
			local e = EASE_OUT(burstU)
			burstScale.Scale = 0.5 + (POD.burst.scale - 0.5) * e
			burstStroke.Transparency = e
		end

		-- the shards of the grab (H:176)
		local shardU = since * 1000 / S.ms
		local flying = rolling and not reduced and shardU < 1
		for i, shard in shards do
			shard.Visible = flying
			if flying then
				local e = SHARD_EASE(shardU)
				local a = (i - 1) / #shards * math.pi * 2 - math.pi / 2
				local d = (S.distancePx + ((i - 1) % 3) * S.stepPx) * k * e
				shard.Position = UDim2.new(0.5, math.cos(a) * d, 0.5, math.sin(a) * d)
				shard.Rotation = 240 * e
				shard.Size = UDim2.fromOffset((S.px - 2 * S.borderPx) * k * (1 - 0.6 * e), (S.px - 2 * S.borderPx) * k * (1 - 0.6 * e))
				shard.BackgroundTransparency = e
				local stroke = shard:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Transparency = e
				end
			end
		end

		-- the chip over the dial while it has landed (H:184; H:19 hg-chip, cut where the timer starts, as in H)
		local chipU = since * 1000 / C.ms
		chip.Visible = landed and power ~= nil and look ~= nil
		if chip.Visible and power and look then
			setChip(PodFormat.chipText(power, POWER_UPS), look.bottom)
			local y = 0
			chip.GroupTransparency = 0
			chipScale.Scale = 1
			if not reduced then
				chip.GroupTransparency = 1 - PodFormat.keyed({ { 0, 0 }, { 0.22, 1 }, { 0.8, 1 }, { 1, 0 } }, chipU, LAND_EASE)
				chipScale.Scale = PodFormat.keyed({ { 0, 0.85 }, { 0.22, 1 }, { 1, 1 } }, chipU, LAND_EASE)
				y = PodFormat.keyed({ { 0, 8 }, { 0.22, 0 }, { 0.8, 0 }, { 1, -10 } }, chipU, LAND_EASE)
			end
			-- its face's bottom abovePx over the dial (the drop hangs under it)
			chip.Position = UDim2.new(0.5, 0, 0, (y - C.abovePx + C.dropPx) * k)
		end

		-- the tag under the dial (H:183)
		local active = phase == "active" and look ~= nil
		setTag(PodFormat.tagText(state), active, if active and look then look.bottom else Palette.PodTag)
	end

	function dial.destroy(_self: Dial)
		frame:Destroy()
	end

	return dial :: Dial
end

return PodDial
