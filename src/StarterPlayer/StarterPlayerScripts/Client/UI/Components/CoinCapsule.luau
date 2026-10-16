--!strict
-- CoinCapsule (client only). DESIGN §11.6 (the Coins pill), §7.2 (Coin colours only for Coins, always with the coin
-- icon). UI FINAL R4 (plan work/ui/PLAN.md R4 "Coin pill"; `H:n` = "Squishy Duels HUD.dc.html" line n): the design's
-- coin pill (H:75-81) and its landing flash (coinFlash, H:562-578).
--   local coins = CoinCapsule.new({ name = "Hud_CoinsButton", text = HudFormat.coinsText(nil), parent = holder })
--   coins:setText(Format.coins(n));   coins:flash(big, combo);   coins:squash(0.8);   coins:shake()
--   local feel = Button.decorate(coins.root, { sound = false })     -- the hover and press feel (the caller)
-- root is a transparent TextButton (the tap target, named spec.name, the focus ring with pill corners), as tall as the
-- pill's frame: its 58 px face and the 5 px ink lip under it (G4.23), at least 220 wide (H:75), wider when the number
-- needs it. Inside it SD_Visual (the squash and the shake play on it, never on the laid-out root) holds:
--   * Ring: the pill's yellow ring (H:575: box-shadow 0 0 0 Npx rgba(255,227,107,a)), a rounded frame of the face's
--     size behind the face (the lip draws over it, as the CSS shadow list does) with an outer UIStroke;
--   * Face: the purple pill (#9775FF -> #6C47F5, H:75): a 4 px ink border drawn inside, the 3 px highlight at .14, the
--     lip, radius half the face; its number (Amount, the Sticker text role "coin": Coin 32 px, #FFE36B, stroke 6, drop
--     3, H:79) after a 68 px left padding, 10 on the right; the number grows from its left middle (H:79
--     transform-origin 0 50%: the list keeps its left edge and centres it);
--   * Coin: the 78 px coin at (-14, -12) of the pill's padding edge (H:78; inside its border) with, behind it, the
--     landing's glow (106 px at (-28, -26), the radial img.fx.radial.coinGlow or Theme.radial's fallback, H:76), rays
--     (146 px at (-48, -46), img.fx.raysCoin, else img.fx.rays tinted #FFF08C, H:77) and halo (the drop-shadow(0 0 10px
--     #FFF3A0) at the flip's peak: img.fx.glow tinted, H:568), and in front of it SD_Idle (the sdCoin loop, H:24,
--     UiIdle "coin") > Flip (the coin's width |cos| of the turn x its scale; the coin, CoinIcon, `disc`, and its white
--     copy img.coin.white for the brightness, pack 2, none while nil).
-- flash(big, combo): one landing's bright parts (Config.UI.motion.coinCounter.flash): the flip (rotateY 0 -> 360,
-- scale 1 -> 1.45 -> .9 -> 1, flipMs or comboFlipMs, coinFlip curve over the whole run), the halo, the number's pop
-- (1.22, 3 px up, #FFE36B -> white -> #FFF3A0 -> #FFE36B, numberMs, the search curve), the ring (0 -> 8 px at .7 ->
-- 16 px clear, ringMs), the glow (scale .4 -> 1.15 -> 1.5, glowMs) and the rays (.3 -> 1 -> 1.25, 0 -> 40 -> 90
-- degrees, raysMs), each a Web Animations run (one easing for the whole run). The caller decides when (PR7) and plays
-- the sparks. Under ReducedMotion nothing moves (the number still changes). The rays and the halo stay drawn only
-- while their picture has an id.
-- squash(factor): the design's press squash (PR4: Config.UI.motion.buttonPress, amount x factor) on SD_Visual, e.g.
-- the spend's .8 (H:674); shake(): the "no" shake at the pill's 12 px (PR5, H:676). Both are off under ReducedMotion.
-- Pure: flashTrack(frames, u, curve) (unit-tested).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local AssetTable = require(Shared.AssetTable)
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)

local UI = script.Parent.Parent
local Client = UI.Parent
local CoinIcon = require(script.Parent.CoinIcon)
local Create = require(UI.Create)
local Focus = require(UI.Focus)
local Layout = require(UI.Layout)
local Theme = require(UI.Theme)
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)
local UiIdle = require(Client.Anim.UiIdle)

-- Types

export type Spec = {
	name: string,
	text: string,
	layoutOrder: number?,
	parent: Instance?,
}

export type CoinCapsule = {
	root: TextButton,
	visual: Frame, -- SD_Visual: what the squash and the shake move
	capsule: Frame, -- the pill's face
	disc: CoinIcon.CoinIcon, -- the coin (the flights land on it)
	label: TextLabel,
	setText: (self: CoinCapsule, text: string) -> (),
	flash: (self: CoinCapsule, big: boolean, combo: boolean) -> (),
	squash: (self: CoinCapsule, factor: number) -> (),
	shake: (self: CoinCapsule) -> (),
	destroy: (self: CoinCapsule) -> (),
}

-- Constants

local STICKER = Config.UI.Sticker
local HUD = STICKER.hud.coins
local MOTION = Config.UI.motion
local FLASH = MOTION.coinCounter.flash
local PRESS = MOTION.buttonPress
local SHAKE = MOTION.buttonShake
local FACE = HUD.face -- H:75
local LIP = STICKER.lip.button -- H:75: 0 5px 0 #1E1428
local BORDER = STICKER.border.normal -- H:75
local COIN_IMAGE_WHITE = "img.coin.white"
local GLOW_KEY = "img.fx.radial.coinGlow"
local RAYS_KEY = "img.fx.raysCoin"
local RAYS_FALLBACK_KEY = "img.fx.rays"
local HALO_KEY = "img.fx.glow"
local COIN_IDLE_PERIOD = MOTION.idle.coin.periodS -- H:78: sdCoin 4.5s

-- Module table

local CoinCapsule = {}

-- Public: pure

-- One frame of a flash track (Config.UI.motion.coinCounter.flash.*Frames) at u (0..1): a Web Animations run, the
-- whole run eased by `curve`, the frames linear (Anim/Tweens.poseAt with wholeRun).
function CoinCapsule.flashTrack(frames: any, u: number, curve: string): Tweens.Pose
	return Tweens.poseAt(frames, math.clamp(u, 0, 1), "linear", curve)
end

-- The number's colour at u (0..1) of its pop: FLASH.numberColors at the number frames' times, the run eased by the
-- number curve (H:574).
local function numberColor(u: number): Color3
	local frames = FLASH.numberFrames
	local names = FLASH.numberColors
	local e = Tweens.curve(FLASH.numberCurve)(math.clamp(u, 0, 1))
	local index = 1
	while index < #frames - 1 and e > (frames[index + 1].at :: number) do
		index += 1
	end
	local a, b = frames[index].at :: number, frames[index + 1].at :: number
	local k = if b > a then math.clamp((e - a) / (b - a), 0, 1) else 1
	local from = (Palette :: any)[names[index]] :: Color3
	local to = (Palette :: any)[names[index + 1]] :: Color3
	return from:Lerp(to, k)
end

-- Public: component

function CoinCapsule.new(spec: Spec): CoinCapsule
	local cleanup = Cleanup.new()
	local frame = FACE + LIP
	local root: TextButton = Create("TextButton", {
		Name = spec.name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(HUD.minWidth, math.max(frame, Config.UI.Touch.minTarget)),
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Focus.decorate(root, Theme.Radius.pill)

	local visual: Frame = Create("Frame", {
		Name = "SD_Visual",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, 0, 0, frame),
		Active = false,
		Parent = root,
	})

	-- H:575: the ring around the face (its size, not the lip's), behind it.
	local ring: Frame = Create("Frame", {
		Name = "Ring",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, FACE),
		Active = false,
		ZIndex = 0,
		Parent = visual,
	})
	Theme.corner(math.floor(FACE / 2), ring)
	local ringStroke: UIStroke = Create("UIStroke", {
		Color = Palette.StickerCoinText,
		Thickness = 0,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = ring,
	})

	-- H:75: the pill's face with its lip, border, highlight and padding; the number in the coin role (H:79).
	local face: Frame = Create("Frame", {
		Name = "Capsule",
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 1,
		Parent = visual,
	})
	local bands = Layout.stickerBands(BORDER, STICKER.surfaces.coinPill.highlightPx, 0, LIP)
	Theme.foam(face, {
		radius = math.floor(FACE / 2),
		stroke = BORDER,
		inner = true,
		top = bands.top,
		bevel = bands.bevel,
		drop = bands.drop,
		colors = Theme.surfaceColors(Theme.accent("plum"), "coinPill", true),
	})
	-- CSS paddings sit inside the border (H:18 box-sizing: border-box); the border is drawn inside the face here.
	local padding: UIPadding = Create("UIPadding", {
		PaddingLeft = UDim.new(0, BORDER + HUD.padLeft),
		PaddingRight = UDim.new(0, BORDER + HUD.padRight),
		PaddingBottom = UDim.new(0, LIP),
		Parent = face,
	})
	Theme.list(Enum.FillDirection.Horizontal, HUD.gap, face, Enum.HorizontalAlignment.Left)
	local label = Theme.label({
		Name = "Amount",
		Text = spec.text,
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		TextWrapped = false,
		LayoutOrder = 1,
		Parent = face,
	}, "Coin")
	Theme.stickerText(label, "coin")
	label.TextWrapped = false
	local pop: UIScale = Create("UIScale", { Name = "SD_Pop", Parent = label })

	-- H:76-78: the coin with its glow, rays and halo behind it, over the face; CSS absolute offsets are from the
	-- padding edge, inside the 4 px border.
	local coinPx = HUD.coinPx
	local coin: Frame = Create("Frame", {
		Name = "Coin",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(BORDER + HUD.coinX, BORDER + HUD.coinY),
		Size = UDim2.fromOffset(coinPx, coinPx),
		Active = false,
		ZIndex = 3,
		Parent = visual,
	})
	local glow: Frame = Create("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(HUD.glowX - HUD.coinX + HUD.glowPx / 2, HUD.glowY - HUD.coinY + HUD.glowPx / 2),
		Size = UDim2.fromOffset(HUD.glowPx, HUD.glowPx),
		Active = false,
		ZIndex = 0,
		Parent = coin,
	})
	-- H:76: radial-gradient(circle, rgba(255,246,170,.95) 0%, rgba(255,214,60,.55) 40%, rgba(255,214,60,0) 70%).
	Theme.radial(glow, GLOW_KEY, {
		inner = Palette.StickerCoinGlowIn,
		innerAlpha = 0.95,
		mid = Palette.StickerCoinGlowMid,
		midAt = 0.4,
		midAlpha = 0.55,
		outer = Palette.StickerCoinGlowMid,
		outerAlpha = 0,
	})
	local glowFade = Tweens.fadeGroup(glow)
	glowFade:setAlpha(0)
	local glowScale: UIScale = Create("UIScale", { Parent = glow })
	local raysId = AssetTable.image(RAYS_KEY)
	local raysImage = raysId or AssetTable.image(RAYS_FALLBACK_KEY)
	local rays: ImageLabel? = nil
	if raysImage then
		rays = Create("ImageLabel", {
			Name = "Rays",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(HUD.raysX - HUD.coinX + HUD.raysPx / 2, HUD.raysY - HUD.coinY + HUD.raysPx / 2),
			Size = UDim2.fromOffset(HUD.raysPx, HUD.raysPx),
			Image = raysImage,
			-- the pack 2 picture has the colour and the mask baked; the fallback is the white rays tinted (H:77)
			ImageColor3 = if raysId then Palette.White else Palette.StickerCoinRays,
			ImageTransparency = 1,
			Active = false,
			ZIndex = 0,
			Parent = coin,
		})
	end
	local raysScale: UIScale? = if rays then Create("UIScale", { Parent = rays }) else nil
	local haloImage = AssetTable.image(HALO_KEY)
	local halo: ImageLabel? = nil
	if haloImage then
		halo = Create("ImageLabel", {
			Name = "Halo",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 2 * HUD.haloPx, 1, 2 * HUD.haloPx),
			Image = haloImage,
			ImageColor3 = Palette.StickerCoinFlash,
			ImageTransparency = 1,
			Active = false,
			ZIndex = 0,
			Parent = coin,
		})
	end
	local idle: Frame = Create("Frame", {
		Name = "SD_Idle",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Active = false,
		ZIndex = 1,
		Parent = coin,
	})
	local idleHandle = UiIdle.add(idle, "coin", { periodS = COIN_IDLE_PERIOD })
	cleanup:add(function()
		if idleHandle then
			idleHandle:remove()
		end
	end)
	local flip: Frame = Create("Frame", {
		Name = "Flip",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Active = false,
		Parent = idle,
	})
	local icon = CoinIcon.new({ name = "CoinIcon", sizePx = coinPx, parent = flip })
	cleanup:add(icon)
	icon.root.Size = UDim2.fromScale(1, 1)
	local whiteId = AssetTable.image(COIN_IMAGE_WHITE)
	local white: ImageLabel? = nil
	if whiteId then
		white = Create("ImageLabel", {
			Name = "White",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = whiteId,
			ImageTransparency = 1,
			Active = false,
			ZIndex = 2,
			Parent = flip,
		})
	end

	-- The width: the number's (Theme.textWidth: never the popped size), the paddings and the border, at least
	-- minWidth (H:75, a border-box width).
	local function fitWidth()
		local inner = HUD.padLeft + Theme.textWidth(label.Text, "Coin") + HUD.padRight
		local width = math.max(HUD.minWidth, math.ceil(2 * BORDER + inner))
		if root.Size.X.Offset ~= width then
			root.Size = UDim2.fromOffset(width, root.Size.Y.Offset)
		end
	end
	fitWidth()

	-- One Scheduler effect plays a flash; a new flash restarts it.
	local flashHandle: Scheduler.Handle? = nil
	local function rest()
		flip.Size = UDim2.fromScale(1, 1)
		pop.Scale = 1
		padding.PaddingBottom = UDim.new(0, LIP)
		label.TextColor3 = Palette.StickerCoinText
		ringStroke.Thickness = 0
		ringStroke.Transparency = 1
		glowFade:setAlpha(0)
		glowScale.Scale = 1
		local r = rays
		if r then
			r.ImageTransparency = 1
		end
		local h = halo
		if h then
			h.ImageTransparency = 1
		end
		local w = white
		if w then
			w.ImageTransparency = 1
		end
	end
	local function stopFlash()
		local current = flashHandle
		flashHandle = nil
		if current then
			current:disconnect()
		end
	end
	cleanup:add(stopFlash)

	-- The press squash / the "no" shake on SD_Visual (Tweens.keyframes; a new one replaces the running one).
	local motion: Tweens.Keyframes? = nil
	local motionHandle: Scheduler.Handle? = nil
	local function playOnVisual(frames: { Tweens.Pose }, ms: number, curve: string)
		if Tweens.reducedMotion() then
			return
		end
		if motion then
			motion:finish()
		end
		if motionHandle then
			motionHandle:disconnect()
		end
		local track = Tweens.keyframes(visual, frames, { ms = ms, curve = curve })
		motion = track
		motionHandle = Scheduler.add(track, "render")
	end
	cleanup:add(function()
		if motionHandle then
			motionHandle:disconnect()
			motionHandle = nil
		end
	end)

	local self = {} :: CoinCapsule
	self.root = root
	self.visual = visual
	self.capsule = face
	self.disc = icon
	self.label = label

	function self.setText(_: CoinCapsule, text: string)
		label.Text = text
		fitWidth()
	end

	function self.flash(_: CoinCapsule, _big: boolean, combo: boolean)
		stopFlash()
		rest()
		if Tweens.reducedMotion() then
			return
		end
		local reducedRays = rays == nil
		local flipMs = if combo then FLASH.comboFlipMs else FLASH.flipMs
		local longest = math.max(flipMs, FLASH.numberMs, FLASH.ringMs, FLASH.glowMs, FLASH.raysMs)
		local started = os.clock()
		flashHandle = Scheduler.add(function(_dt: number, now: number): boolean
			local ms = (now - started) * 1000
			-- The flip (H:566-571): the coin's width |cos turn| x its scale; the white copy at brightness - 1.
			local f = CoinCapsule.flashTrack(FLASH.flipFrames, ms / flipMs, FLASH.curve)
			local s = f.scale or 1
			local turn = math.rad(f.rot or 0)
			flip.Size = UDim2.fromScale(math.abs(math.cos(turn)) * s, s)
			local w = white
			if w then
				w.ImageTransparency = 1 - (f.alpha or 0)
			end
			local h = halo
			if h then
				local a = CoinCapsule.flashTrack(FLASH.haloFrames, ms / flipMs, FLASH.curve).alpha or 0
				h.ImageTransparency = 1 - a
			end
			-- The number (H:574): its pop, its rise (the face's bottom padding moves it up) and its colour.
			local nu = ms / FLASH.numberMs
			local n = CoinCapsule.flashTrack(FLASH.numberFrames, nu, FLASH.numberCurve)
			pop.Scale = n.scale or 1
			padding.PaddingBottom = UDim.new(0, LIP - 2 * math.round(n.y or 0))
			label.TextColor3 = numberColor(nu)
			-- The ring (H:575).
			local r = CoinCapsule.flashTrack(FLASH.ringFrames, ms / FLASH.ringMs, FLASH.ringCurve)
			ringStroke.Thickness = r.x or 0
			ringStroke.Transparency = 1 - (r.alpha or 0)
			-- The glow (H:572) and the rays (H:573).
			local g = CoinCapsule.flashTrack(FLASH.glowFrames, ms / FLASH.glowMs, FLASH.glowCurve)
			glowFade:setAlpha(g.alpha or 0)
			glowScale.Scale = g.scale or 1
			local ray = rays
			if ray and raysScale and not reducedRays then
				local p = CoinCapsule.flashTrack(FLASH.raysFrames, ms / FLASH.raysMs, FLASH.raysCurve)
				ray.ImageTransparency = 1 - HUD.raysAlpha * (p.alpha or 0)
				raysScale.Scale = p.scale or 1
				ray.Rotation = p.rot or 0
			end
			if ms >= longest then
				rest()
				flashHandle = nil
				return false
			end
			return true
		end, "render")
	end

	function self.squash(_: CoinCapsule, factor: number)
		local a = PRESS.amount * factor
		local frames: { Tweens.Pose } = {}
		for _, f in PRESS.frames do
			table.insert(frames, { at = f.at, sx = 1 + a * (f.sx or 0), sy = 1 + a * (f.sy or 0) })
		end
		playOnVisual(frames, PRESS.ms, PRESS.curve)
	end

	function self.shake(_: CoinCapsule)
		local steps = SHAKE.steps
		local frames: { Tweens.Pose } = {}
		for index, v in steps do
			table.insert(frames, { at = (index - 1) / (#steps - 1), x = v * SHAKE.pillPx, rot = v * SHAKE.rotDeg })
		end
		playOnVisual(frames, SHAKE.ms, SHAKE.curve)
	end

	function self.destroy(_: CoinCapsule)
		cleanup:clean()
	end

	if spec.parent then
		root.Parent = spec.parent
	end
	return self
end

return CoinCapsule
