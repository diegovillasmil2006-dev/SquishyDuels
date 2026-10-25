--!strict
-- AbilityBarController (client only). Duel HUD part 2 (owner 2026-10-24, "yes, start part 2"; `D:n` = "Squishy Duels
-- Duel HUD.dc.html" line n, the co-owner's Duel HUD export, ported 1:1; superprompt §4): the Catch / Ultimate / Dash
-- ability bar in duels, TDM and FFA (the Duel context with a duel or match view in Countdown, Active or SuddenDeath).
-- It replaces DuelController's bottom key dock (hidden) and, on touch, ControlsController's round Catch / Ultimate /
-- Dash buttons there (those stay for the practice range); the touch Throw button moves left of the arc.
-- * Layout (UI/AbilityBarFormat.form): desk = a centred row at the bottom (Catch 84, Ultimate 104, Dash 84, key labels
--   under them, the ultimate's name tag over it, D:116-142); phone (touch, or narrower than 1000) = the arc from the
--   bottom-right corner, no key labels and no name tag (D:196-217). One UIScale per form = min(width / W, height / H)
--   of the design canvas (1440x810 / 844x390), in SD_AbilityBar (CoreUISafeInsets, like SD_Touch).
-- * Each button: the baked face (img.duel.btn.*: radial + stripes + rim + inner shade + gloss), the Ink border, the
--   Ink drop, the icon (img.duel.icon.*; the ultimate's by the equipped squishy), the dark sweep of the cooldown left
--   (two half discs, AbilityBarFormat.sweepRotations, every frame), the grey icon and the countdown (whole seconds, one
--   decimal under 1 s) while cooling; the ready ultimate glows gold over the spinning rays; the open catch window draws
--   the cream ring, the gold glow and a CATCH! tag (D:390-402).
-- * Motion (D:346-360, Config.UI.AbilityBar): a press squashes, a refused one (cooling, the hands open, knocked out)
--   shakes; back to ready = the pop, the white flash, a white ring (the ultimate: bigger, a gold ring and sparks,
--   UI/UiFx) and a tick. Tags pop in (dhTag). Under ReducedMotion nothing moves and the rays stand still.
-- * Timers: CatchController.state (left, open), DashController.cooldownLeft, the ultimate's meter (StateController
--   charge, run on between messages by AbilityBarFormat.ultLeft). The server stays the judge of every press: a touch or
--   click on a button presses the same Controls action as its key.

-- Services

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Log = require(Shared.Util.Log)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local AbilityBarFormat = require(Client.UI.AbilityBarFormat)
local Create = require(Client.UI.Create)
local DuelFormat = require(Client.UI.DuelFormat)
local KeyText = require(Client.UI.KeyText)
local MotionTrack = require(Client.UI.MotionTrack)
local Theme = require(Client.UI.Theme)
local UiFx = require(Client.UI.UiFx)
local CatchController = require(script.Parent.CatchController)
local ControlsController = require(script.Parent.ControlsController)
local DashController = require(script.Parent.DashController)
local SoundController = require(script.Parent.SoundController)
local StateController = require(script.Parent.StateController)
local UIController = require(script.Parent.UIController)

-- Types

type Id = AbilityBarFormat.AbilityId

type Button = {
	id: Id,
	slot: Frame,
	holder: Frame,
	poser: Tweens.Poser,
	face: ImageLabel,
	icon: ImageLabel,
	sweep: Frame,
	sweepRight: UIGradient,
	sweepLeft: UIGradient,
	flash: Frame,
	flashPoser: Tweens.Poser,
	number: TextLabel,
	glow: ImageLabel?,
	rays: ImageLabel?,
	ring: Frame?,
	tag: Frame,
	tagLabel: TextLabel,
	tagText: string,
	key: TextLabel?,
	busy: boolean?, -- nil until the first frame shown (no pop for what was already cooling)
	motion: Scheduler.Handle?,
	flashMotion: Scheduler.Handle?,
}

type View = { squishyId: string, userId: number, phase: string, alive: boolean, charge: number? }

-- Constants

local BAR = Config.UI.AbilityBar
local GUI_NAME = "SD_AbilityBar"
local IDS: { Id } = { "catch", "ult", "dash" }
local ACTIONS: { [Id]: string } = { catch = "Catch", ult = "Ultimate", dash = "Dash" }
local INK = Palette.StickerInk
local SHOW_PHASES: { [string]: boolean } = { Countdown = true, Active = true, SuddenDeath = true }
local SOUND_TICK = "ui.click" -- D:358 snd.tick (hi on ready, low on a refusal, D:350)
local TICK_HIGH, TICK_LOW = 1.25, 0.8
local WHITE = Palette.White
-- D:346 squash, D:349 shake, D:354 pop: each animation's `easing` is its whole run (Web Animations), segments linear.
local SQUASH: { Tweens.Pose } = {
	{ at = 0, sx = 1, sy = 1 },
	{ at = 0.3, sx = 0.84, sy = 0.8 },
	{ at = 0.65, sx = 1.08, sy = 1.1 },
	{ at = 1, sx = 1, sy = 1 },
}
local DENY_STEPS = { 0, -1, 1, -0.7, 0.5, -0.2, 0 }
-- D:25 dhTag (a CSS animation: its curve eases each segment)
local TAG_IN: { Tweens.Pose } = {
	{ at = 0, alpha = 0, y = 8, scale = 0.7 },
	{ at = 0.6, alpha = 1, y = -2, scale = 1.08 },
	{ at = 1, alpha = 1, y = 0, scale = 1 },
}

-- Module table

local AbilityBarController = {}

-- State

local log = Log.new("AbilityBar")
local cleanup: any = nil
local gui: ScreenGui? = nil
local root: Frame? = nil
local rootScale: UIScale? = nil
local builtForm: AbilityBarFormat.Form? = nil
local buttons: { [Id]: Button } = {}
local shown = false
local lastCharge: number? = nil
local lastChargeAt = 0
local builtUlt: string? = nil -- the ultimate the bar was drawn for (its icon and name)

-- Private: building

local function image(key: string): string
	return AssetTable.image(key) or ""
end

local function round(object: GuiObject)
	Create("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = object })
end

-- Fredoka text with the Ink outline (D: -webkit-text-stroke Npx = a UIStroke of N / 2 around the glyphs).
local function outlined(props: { [string]: any }, sizePx: number, strokePx: number, color: Color3): TextLabel
	props.BackgroundTransparency = 1
	props.FontFace = Theme.font("Button")
	props.TextSize = sizePx
	props.TextColor3 = color
	props.TextWrapped = false
	local label: TextLabel = Create("TextLabel", props)
	Create("UIStroke", {
		Color = INK,
		Thickness = strokePx / 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
	return label
end

-- One half of the sweep (DuelController's buildPieHalf, its mask clear on its first half: AbilityBarFormat).
local function sweepHalf(parent: Instance, rightSide: boolean): UIGradient
	local half: Frame = Create("Frame", {
		Name = if rightSide then "Right" else "Left",
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromScale(if rightSide then 0.5 else 0, 0),
		Size = UDim2.fromScale(0.5, 1),
		Parent = parent,
	})
	local disc: Frame = Create("Frame", {
		Name = "Disc",
		BackgroundColor3 = Palette.AbilitySweep,
		BackgroundTransparency = BAR.sweepTransparency,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(if rightSide then -1 else 0, 0),
		Size = UDim2.fromScale(2, 1),
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

-- A centred piece `px` wide on a holder `size` wide (scale sizes, so the squash scales it too).
local function centred(className: string, name: string, px: number, size: number, z: number, parent: Instance): any
	return Create(className, {
		Name = name,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(px / size, px / size),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = parent,
	})
end

local function buildTag(slot: Frame, spec: any): (Frame, TextLabel)
	local tag: Frame = Create("Frame", {
		Name = "Tag",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -(spec.gapPx + spec.borderPx)), -- the border-box's bottom gapPx over the slot
		Size = UDim2.fromOffset(spec.heightPx * 2, spec.heightPx),
		BackgroundColor3 = INK,
		Visible = false,
		ZIndex = 20,
		Parent = slot,
	})
	round(tag)
	Create("UIStroke", { Color = INK, Thickness = spec.borderPx, Parent = tag })
	local label: TextLabel = Create("TextLabel", { -- D:120 the tag's text has no outline
		Name = "Text",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = Theme.font("Button"),
		TextSize = spec.textPx,
		TextColor3 = WHITE,
		ZIndex = 21,
		Parent = tag,
	})
	return tag, label
end

local function buildButton(id: Id, form: AbilityBarFormat.Form, parent: Frame, ultIcon: string?): Button
	local spec = BAR[form]
	local size = if form == "desk" then spec.sizes[id] else spec.places[id].size
	local border = spec.borderPx
	local inner = size - 2 * border
	local slot: Frame
	if form == "desk" then
		slot = Create("Frame", {
			Name = "Slot_" .. id,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(size, size + spec.keyPx - spec.keyOverlapPx),
			LayoutOrder = table.find(IDS, id) or 0,
			Parent = parent,
		})
	else
		local place = spec.places[id]
		slot = Create("Frame", {
			Name = "Slot_" .. id,
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -place.right, 1, -place.bottom),
			Size = UDim2.fromOffset(size, size),
			Parent = parent,
		})
	end
	local holder: Frame = Create("Frame", {
		Name = "Ability_" .. id,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(size / 2, size / 2),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		Active = true, -- a press here is the button's, never a throw (ControlsController ignoreOverGui)
		Parent = slot,
	})
	local rays: ImageLabel? = nil
	local glow: ImageLabel? = nil
	local ring: Frame? = nil
	if id == "ult" then
		rays = centred("ImageLabel", "Rays", spec.raysPx, size, 1, holder)
		local r = rays :: ImageLabel
		r.Image = image("img.duel.rays")
		r.ImageTransparency = BAR.raysTransparency
		r.Visible = false
		local glowKey = if form == "desk" then "img.duel.glow.ultDesk" else "img.duel.glow.ultPhone"
		glow = centred("ImageLabel", "Glow", spec.glowPx.ult, size, 2, holder)
		local g = glow :: ImageLabel
		g.Image = image(glowKey)
		g.ImageColor3 = Palette.AbilityUltGlow
		g.ImageTransparency = BAR.ultGlowTransparency
		g.Visible = false
	elseif id == "catch" then
		local glowKey = if form == "desk" then "img.duel.glow.catchDesk" else "img.duel.glow.catchPhone"
		glow = centred("ImageLabel", "Glow", spec.glowPx.catch, size, 2, holder)
		local g = glow :: ImageLabel
		g.Image = image(glowKey)
		g.ImageColor3 = Palette.Lemon
		g.ImageTransparency = BAR.catchGlowTransparency
		g.Visible = false
		ring = centred("Frame", "WindowRing", size + 2 * spec.catchRingPx, size, 3, holder)
		local w = ring :: Frame
		w.BackgroundColor3 = Palette.Frosting
		w.BackgroundTransparency = 0
		w.Visible = false
		round(w)
	end
	local drop: Frame = centred("Frame", "Drop", size, size, 4, holder)
	drop.Position = UDim2.new(0.5, 0, 0.5 + spec.dropPx / size, 0)
	drop.BackgroundColor3 = INK
	drop.BackgroundTransparency = 0
	round(drop)
	local disc: Frame = centred("Frame", "Border", size, size, 5, holder)
	disc.BackgroundColor3 = INK
	disc.BackgroundTransparency = 0
	round(disc)
	local face: ImageLabel = centred("ImageLabel", "Face", inner, size, 6, holder)
	face.Image = image(`img.duel.btn.{id}{if form == "desk" then "Desk" else "Phone"}`)
	round(face)
	local pad = math.floor(size * BAR.iconInset[id] + 0.5) -- D:392 Math.round
	local icon: ImageLabel = centred("ImageLabel", "Icon", inner - 2 * pad, inner, 7, face)
	icon.Image = if id == "ult" then ultIcon or "" elseif id == "catch" then image("img.duel.icon.catch") else image("img.duel.icon.dash")
	icon.ScaleType = Enum.ScaleType.Fit
	local sweep: Frame = centred("Frame", "Sweep", inner, inner, 8, face)
	sweep.Visible = false
	local sweepRight = sweepHalf(sweep, true)
	local sweepLeft = sweepHalf(sweep, false)
	local flash: Frame = centred("Frame", "Flash", inner, inner, 9, face)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 0
	round(flash)
	local flashPoser = Tweens.poser(flash)
	flashPoser:set({ alpha = 0 })
	local number = outlined({
		Name = "Count",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Text = "",
		ZIndex = 10,
		Parent = holder,
	}, spec.numberPx[id], spec.numberStrokePx, WHITE)
	local key: TextLabel? = nil
	if form == "desk" then
		key = outlined({
			Name = "Key",
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, size - spec.keyOverlapPx),
			Size = UDim2.fromOffset(size, spec.keyPx),
			Text = "",
			ZIndex = 11,
			Parent = slot,
		}, spec.keyPx, spec.keyStrokePx, WHITE)
	end
	local tag, tagLabel = buildTag(slot, spec.tag)
	return {
		id = id,
		slot = slot,
		holder = holder,
		poser = Tweens.poser(holder),
		face = face,
		icon = icon,
		sweep = sweep,
		sweepRight = sweepRight,
		sweepLeft = sweepLeft,
		flash = flash,
		flashPoser = flashPoser,
		number = number,
		glow = glow,
		rays = rays,
		ring = ring,
		tag = tag,
		tagLabel = tagLabel,
		tagText = "",
		key = key,
		busy = nil,
		motion = nil,
		flashMotion = nil,
	}
end

-- Private: motion

-- Plays `frames` on the button (whole-run `curve`), first putting its last motion at rest.
local function animate(button: Button, frames: { Tweens.Pose }, ms: number, curve: string)
	if button.motion then
		button.motion:disconnect()
		button.motion = nil
	end
	button.poser:rest()
	if Tweens.reducedMotion() then
		return
	end
	local elapsed = 0
	button.motion = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = math.min(elapsed * 1000 / ms, 1)
		button.poser:set(Tweens.poseAt(frames, u, "linear", curve))
		if u >= 1 then
			button.poser:rest()
			button.motion = nil
			return false
		end
		return true
	end, "render")
end

local function deny(button: Button)
	local frames: { Tweens.Pose } = {}
	for i, v in DENY_STEPS do
		table.insert(frames, { at = (i - 1) / (#DENY_STEPS - 1), x = v * BAR.denyPx, rot = v * BAR.denyDeg })
	end
	animate(button, frames, BAR.denyMs, "easeOut")
	SoundController.play(SOUND_TICK, { pitch = TICK_LOW })
end

local function scaleNow(): number
	local s = rootScale
	return (if s then s.Scale else 1) / math.max(UIController.scale(), 1e-3)
end

local function readyFx(button: Button)
	local id = button.id
	local peak = BAR.readyPeak[id]
	animate(button, {
		{ at = 0, scale = 1 },
		{ at = 0.35, scale = peak },
		{ at = 0.7, scale = 0.95 },
		{ at = 1, scale = 1 },
	}, BAR.readyMs[id], "search")
	if button.flashMotion then
		button.flashMotion:disconnect()
	end
	local elapsed = 0
	local ms = BAR.flashMs[id]
	local ease = Tweens.curve("easeOut")
	button.flashMotion = Scheduler.add(function(dt: number): boolean
		elapsed += dt
		local u = math.min(elapsed * 1000 / ms, 1)
		button.flashPoser:set({ alpha = (1 - BAR.flashFrom) * (1 - ease(u)) })
		if u >= 1 then
			button.flashMotion = nil
			return false
		end
		return true
	end, "render")
	local k = scaleNow()
	UiFx.ring(button.holder, WHITE, BAR.ringPx[id] * k)
	if id == "ult" then
		task.delay(BAR.ultGoldRingDelay, function()
			if button.holder.Parent then
				UiFx.ring(button.holder, Palette.Lemon, BAR.ultGoldRingPx * k)
			end
		end)
		local s = BAR.ultSparks
		UiFx.sparks(button.holder, { n = s.n, spread = s.spread * k, size = s.size * k, up = s.up * k })
	else
		SoundController.play(SOUND_TICK, { pitch = TICK_HIGH }) -- the ultimate's own ready sound is DuelController's
	end
end

-- Private: state

local function currentView(): View?
	local player = Players.LocalPlayer
	if player == nil then
		return nil
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local standing = humanoid ~= nil and humanoid.Health > 0
	local duel = StateController.duel()
	if duel then
		return {
			squishyId = duel.you.squishyId,
			userId = duel.you.userId,
			phase = duel.phase,
			alive = standing,
			charge = duel.charges[duel.you.userId],
		}
	end
	local match = StateController.match()
	if match then
		local you = match.you
		return {
			squishyId = you.squishyId,
			userId = you.userId,
			phase = match.phase,
			alive = standing and you.alive and not you.out,
			charge = match.charges[you.userId],
		}
	end
	return nil
end

-- (seconds left, the whole cooldown, the catch window open) of one ability; nil = this loadout has none.
local function timerOf(id: Id, view: View): (number?, number, boolean)
	if id == "catch" then
		local state = CatchController.state()
		return state.left, Config.Combat.Catch.cooldownSeconds, state.open
	elseif id == "dash" then
		local left, total = DashController.cooldownLeft()
		return left, total, false
	end
	local _, ability = DuelFormat.ultimateOf(view.squishyId)
	if ability == nil then
		return nil, 1, false
	end
	-- before the first UltimateCharge (the server sends it once the match is live) the meter is where every match starts
	local charge = view.charge or ability.startCharge
	if charge ~= lastCharge then
		lastCharge, lastChargeAt = charge, os.clock()
	end
	local rate = ability.chargePerSecond
	local live = DuelFormat.isLive(view.phase)
	local since = os.clock() - lastChargeAt
	-- a received whole number: the true meter is in [charge, charge + 1), so start from its middle (±0.5 point)
	local left = if view.charge ~= nil and charge < ability.chargeMax
		-- never "ready" before the server's full meter arrives (a press then would be refused)
		then math.max(AbilityBarFormat.ultLeft(charge + 0.5, ability.chargeMax, rate, since, live, 0.5), 0.05)
		else AbilityBarFormat.ultLeft(charge, ability.chargeMax, rate, since, live)
	return left, if rate > 0 then ability.chargeMax / rate else 1, false
end

local function setTag(button: Button, text: string, bg: Color3, fg: Color3, spec: any)
	if text == button.tagText then
		return
	end
	button.tagText = text
	local tag = button.tag
	if text == "" then
		MotionTrack.stop(tag)
		tag.Visible = false
		return
	end
	tag.BackgroundColor3 = bg
	button.tagLabel.TextColor3 = fg
	button.tagLabel.Text = text
	-- CSS border-box: heightPx holds the border, which the UIStroke draws outside the frame
	local width = Theme.textWidth(text, "Chip") * spec.textPx / Theme.textSize("Chip")
	tag.Size = UDim2.fromOffset(math.ceil(width) + 2 * spec.padPx, spec.heightPx - 2 * spec.borderPx)
	tag.Visible = true
	MotionTrack.play(tag, TAG_IN, BAR.tagMs, 0, "search")
end

local function updateButton(button: Button, view: View, form: AbilityBarFormat.Form, keyText: string?, clock: number)
	local left, total, open = timerOf(button.id, view)
	local slotShown = left ~= nil
	button.slot.Visible = slotShown
	if not slotShown then
		return
	end
	local cooling = (left :: number) > 0 and not open
	local busy = cooling or open
	if button.busy == true and not busy then
		readyFx(button)
	end
	button.busy = busy
	local fraction = if cooling then AbilityBarFormat.sweepFraction(left :: number, total) else 0
	button.sweep.Visible = fraction > 0
	if fraction > 0 then
		local right, leftDeg = AbilityBarFormat.sweepRotations(fraction)
		button.sweepRight.Rotation = right
		button.sweepLeft.Rotation = leftDeg
	end
	button.icon.ImageColor3 = if cooling then Palette.AbilityIconCooling else WHITE
	local text = if cooling then AbilityBarFormat.cooldownText(left :: number) else ""
	if button.number.Text ~= text then
		button.number.Text = text
	end
	local ready = not busy
	if button.id == "ult" then
		local glow, rays = button.glow :: ImageLabel, button.rays :: ImageLabel
		glow.Visible = ready
		rays.Visible = ready
		if ready and not Tweens.reducedMotion() then
			rays.Rotation = (clock / BAR.raysTurnSeconds * 360) % 360
		end
	elseif button.id == "catch" then
		(button.glow :: ImageLabel).Visible = open;
		(button.ring :: Frame).Visible = open
	end
	local spec = BAR[form].tag
	if button.id == "catch" then
		setTag(button, if open then Strings.duel.abilityCatchTag else "", Palette.Lemon, INK, spec)
	elseif button.id == "ult" and form == "desk" then
		local _, ability = DuelFormat.ultimateOf(view.squishyId)
		local name = if ability then string.upper(KeyText.get(ability.nameKey)) else ""
		setTag(button, name, INK, Palette.Lemon, spec)
	end
	local key = button.key
	if key and key.Text ~= (keyText or "") then
		key.Text = keyText or ""
	end
end

local function clearButtons()
	for _, button in buttons do
		if button.motion then
			button.motion:disconnect()
		end
		if button.flashMotion then
			button.flashMotion:disconnect()
		end
		MotionTrack.stop(button.tag)
	end
	table.clear(buttons)
	if root then
		for _, child in root:GetChildren() do
			if child ~= rootScale then -- the canvas UIScale stays
				child:Destroy()
			end
		end
	end
	builtForm = nil
	builtUlt = nil
end

local function pressFeedback(id: Id): boolean
	local button = buttons[id]
	local view = currentView()
	if button == nil or view == nil or not shown then
		return false
	end
	-- The state drawn last frame: the action's own handler may already have run for this input.
	local ok = view.alive and button.busy == false and button.slot.Visible
	if ok then
		animate(button, SQUASH, BAR.pressMs, "easeOut")
	else
		deny(button)
	end
	return ok
end

local function build(form: AbilityBarFormat.Form, ultimateId: string?)
	clearButtons()
	local r = root :: Frame
	local spec = BAR[form]
	local parent: Frame = r
	if form == "desk" then
		local width = spec.sizes.catch + spec.sizes.ult + spec.sizes.dash + 2 * spec.gapPx
		local height = spec.sizes.ult + spec.keyPx - spec.keyOverlapPx
		parent = Create("Frame", {
			Name = "Row",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -spec.bottomPx),
			Size = UDim2.fromOffset(width, height),
			BackgroundTransparency = 1,
			Parent = r,
		})
		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, spec.gapPx),
			Parent = parent,
		})
	end
	local ultIcon = AbilityBarFormat.ultIconKey(ultimateId)
	for _, id in IDS do
		local button = buildButton(id, form, parent, ultIcon and image(ultIcon) or nil)
		buttons[id] = button
		local action = ACTIONS[id]
		button.holder.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
				pressFeedback(id)
				ControlsController.pressAction(action, Enum.UserInputState.Begin)
			end
		end)
		button.holder.InputEnded:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 then
				ControlsController.pressAction(action, Enum.UserInputState.End)
			end
		end)
	end
	builtForm = form
	builtUlt = ultimateId
end

-- SD_AbilityBar in the PlayerGui, made the first time there is one (never waits for it).
local function ensureGui()
	local player = Players.LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if gui ~= nil or playerGui == nil or cleanup == nil then
		return
	end
	local screen: ScreenGui = Create("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		DisplayOrder = BAR.displayOrder,
		Enabled = false,
	})
	local frame: Frame = Create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = screen,
	})
	rootScale = Create("UIScale", { Parent = frame })
	gui, root = screen, frame
	screen.Parent = playerGui
	cleanup:add(screen)
end

local function step(_dt: number, _now: number): boolean
	ensureGui()
	local g, r, scale = gui, root, rootScale
	if g == nil or r == nil or scale == nil then
		return true
	end
	local view = currentView()
	local show = view ~= nil and ControlsController.isContextActive("Duel") and SHOW_PHASES[view.phase] == true
	if show ~= shown then
		shown = show
		g.Enabled = show
		if not show then
			for _, button in buttons do
				button.busy = nil
			end
		end
	end
	if not show or view == nil then
		return true
	end
	local size = g.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return true
	end
	local preferred = ControlsController.preferredInput()
	local form = AbilityBarFormat.form(size.X, preferred == Enum.PreferredInput.Touch)
	local ultimateId = DuelFormat.ultimateOf(view.squishyId)
	if form ~= builtForm or ultimateId ~= builtUlt then
		build(form, ultimateId)
	end
	local k = AbilityBarFormat.canvasScale(form, size)
	if scale.Scale ~= k then
		scale.Scale = k
		r.Size = UDim2.fromScale(1 / k, 1 / k)
	end
	local _, ultKey, dashKey, _, catchKey = DuelFormat.hintKeys(preferred.Name, ultimateId ~= nil, false)
	local keys: { [Id]: string? } = { catch = catchKey, ult = ultKey, dash = dashKey }
	local clock = os.clock()
	for id, button in buttons do
		updateButton(button, view, form, keys[id], clock)
	end
	return true
end

-- The key presses' squash / shake (the actions themselves are the Controls bindings').
local function onInput(input: InputObject)
	if not shown or UserInputService:GetFocusedTextBox() ~= nil then
		return
	end
	for _, id in IDS do
		local inputs = ControlsController.inputsOf(ACTIONS[id])
		if inputs and table.find(inputs :: { any }, input.KeyCode) and input.KeyCode ~= Enum.KeyCode.Unknown then
			pressFeedback(id)
			return
		end
	end
end

-- Lifecycle

function AbilityBarController.init()
	cleanup = Cleanup.new()
end

function AbilityBarController.start()
	local c = cleanup
	if c == nil or Players.LocalPlayer == nil then
		return
	end
	c:add(UserInputService.InputBegan:Connect(function(input: InputObject)
		local ok, err = pcall(onInput, input)
		if not ok then
			log:error("ability bar input failed:", err)
		end
	end))
	local handle = Scheduler.add(function(dt: number, now: number): boolean
		local ok, err = pcall(step, dt, now)
		if not ok then
			log:error("ability bar update failed:", err)
		end
		return true
	end, "render")
	c:add(function()
		handle:disconnect()
		clearButtons()
		gui, root, rootScale = nil, nil, nil
		shown = false
	end)
end

-- Not called by the bootstrap (the client lives for the session); used by tests and leak checks.
function AbilityBarController.destroy()
	if cleanup then
		cleanup:clean()
		cleanup = nil
	end
end

return AbilityBarController
