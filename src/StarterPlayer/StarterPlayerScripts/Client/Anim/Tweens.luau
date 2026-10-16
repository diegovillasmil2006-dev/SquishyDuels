--!strict
-- Tweens (client only). Small UI tween helpers on TweenService (DESIGN §9.13, §11.1) that apply the ReducedMotion rules
-- in one place: scale effects are off (the end value is set at once) and fades are capped at
-- Config.UI.motion.reducedMotionMaxFadeMs.
--   Tweens.play(gui, 180, { Position = ... }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
--   Tweens.playSpec(gui, Config.UI.motion.modalClose, { GroupTransparency = 1 })
--   Tweens.fade(dimmer, { BackgroundTransparency = 0.45 }, 180)
--   Tweens.scale(uiScale, 0.94, 1, Config.UI.motion.modalOpen)
--   Scheduler.add(Tweens.countUp(120, 380, 400, function(n) label.Text = Format.coins(n) end), "render")
-- Every Tween is created and played here and returned, so the owner can put it in its Cleanup (Tween is an Instance).
-- UI number count-ups are Scheduler render effects (PreRender, §9.1 #3), not Tween instances.
-- UI FINAL R2 (plan work/ui/PLAN.md §0 easing rule, §2 one-shot keyframes; `H:n` = "Squishy Duels HUD.dc.html" line n):
--   Tweens.bezier(x1, y1, x2, y2) -> (u) -> eased   a CSS cubic-bezier played exactly (x solved for t: Newton, then
--            bisection; y returned); Tweens.curve(name) the Config.UI.curves entry of that name (or a curve function)
--   Tweens.poseAt(frames, u, curve?, wholeRun?) -> Pose   a design @keyframes at u: a Pose is { at, x, y = base px, sx,
--            sy, scale, rot = degrees, alpha, color } and its fields form groups that each interpolate only between the
--            frames naming them (CSS: x / y / sx / sy / scale / rot are one `transform`, so a frame naming any of them
--            sets the others to identity; alpha; color), each segment eased by `curve` (default CSS `ease`); a group
--            with no frame at 0 or 1 starts or ends at rest (the element's own value). `wholeRun` eases the whole run
--            first and the segments stay linear (a Web Animations `easing` option, H:566-575, H:687, H:837, H:878)
--   Tweens.poser(holder)   writes poses on an inner holder no layout places: its Position and Rotation plus the
--            pose's move (a caller's own move in between is kept), the uniform scale on its SD_Pose UIScale, sx / sy
--            as its Size about its AnchorPoint (a TextLabel, TextButton or ViewportFrame cannot squash out of shape:
--            it takes the uniform part √(sx·sy) on the UIScale, plan §1.4), alpha on its own transparency, color on
--            its TextColor3, ImageColor3 or BackgroundColor3
--   Scheduler.add(Tweens.keyframes(holder, frames, { ms, delayMs?, curve?, wholeRun? }), "render")   the track as a
--            render effect: the first frame at once (CSS fill "both"), held through the delay, the last frame exactly
--            at the end; under ReducedMotion (PR9) nothing moves (the holder rests) and only the fades are left, each
--            at most reducedMotionMaxFadeMs: up to the track's peak alpha at the start, down to the last frame's at
--            the end of opts.ms. finish() jumps to the end, cancel() stops writing.
--   Tweens.fadeGroup(holder) -> { setAlpha(a), restore() }   the fade of an element CSS fades as a whole: every
--            Background / Image / Text / TextStroke / UIStroke transparency of the holder and its descendants (as
--            they are when it is made) set to 1 - (1 - base) · a.
-- A holder runs one pose at a time (nest holders to combine a loop and a one-shot) and is never placed by a layout.

-- Services

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UiPrefs = require(script.Parent.Parent.UI.UiPrefs)

-- Types

export type Spec = {
	ms: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
}

export type CountUp = {
	step: (self: CountUp, dt: number, now: number) -> boolean,
	finish: (self: CountUp) -> (),
	cancel: (self: CountUp) -> (),
}

-- UI FINAL R2: an easing (u 0..1 -> eased), a design pose (see the header) and what plays it.
export type Curve = (u: number) -> number

export type Pose = {
	at: number?,
	x: number?,
	y: number?,
	sx: number?,
	sy: number?,
	scale: number?,
	rot: number?,
	alpha: number?,
	color: Color3?,
}

export type KeyframeOptions = {
	ms: number,
	delayMs: number?,
	curve: (string | Curve)?, -- each segment's easing (default CSS `ease`)
	wholeRun: (string | Curve)?, -- the whole run's easing (segments linear)
}

export type Keyframes = {
	step: (self: Keyframes, dt: number, now: number) -> boolean,
	finish: (self: Keyframes) -> (),
	cancel: (self: Keyframes) -> (),
}

export type Poser = {
	set: (self: Poser, pose: Pose) -> (),
	rest: (self: Poser) -> (),
}

export type FadeGroup = {
	setAlpha: (self: FadeGroup, alpha: number) -> (),
	restore: (self: FadeGroup) -> (),
}

-- Constants

local DEFAULT_STYLE = Enum.EasingStyle.Quad
local DEFAULT_DIRECTION = Enum.EasingDirection.Out
local MAX_FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
-- UI FINAL R2: the pose groups (header), the rest value of each field, the uniform scale's UIScale.
local TRANSFORM_FIELDS = { "x", "y", "sx", "sy", "scale", "rot" }
local REST: { [string]: number } = { x = 0, y = 0, sx = 1, sy = 1, scale = 1, rot = 0, alpha = 1 }
local POSE_SCALE_NAME = "SD_Pose"
local DEFAULT_CURVE = "ease" -- CSS animation-timing-function's default
local BEZIER_EPSILON = 1e-7
local NEWTON_STEPS = 8
local BISECTION_STEPS = 50
-- fadeGroup: the transparency properties of each class it fades.
local FADE_PROPERTIES: { { class: string, property: string } } = {
	{ class = "GuiObject", property = "BackgroundTransparency" },
	{ class = "ImageLabel", property = "ImageTransparency" },
	{ class = "ImageButton", property = "ImageTransparency" },
	{ class = "TextLabel", property = "TextTransparency" },
	{ class = "TextButton", property = "TextTransparency" },
	{ class = "TextBox", property = "TextTransparency" },
	{ class = "TextLabel", property = "TextStrokeTransparency" },
	{ class = "TextButton", property = "TextStrokeTransparency" },
	{ class = "UIStroke", property = "Transparency" },
}

-- Module table

local Tweens = {}

-- Private

local function seconds(ms: number): number
	if not (ms > 0) then
		return 0
	end
	return ms / 1000
end

-- Public

-- True while scale effects must be skipped and fades shortened: Roblox's own GuiService.ReducedMotionEnabled (§9.12),
-- or (UI overhaul 2026-10-11) the in-game Settings "Reduce motion" switch (UI/UiPrefs.reduceMotion).
function Tweens.reducedMotion(): boolean
	return GuiService.ReducedMotionEnabled or UiPrefs.get("reduceMotion")
end

function Tweens.info(ms: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): TweenInfo
	return TweenInfo.new(seconds(ms), style or DEFAULT_STYLE, direction or DEFAULT_DIRECTION)
end

-- Creates, plays and returns a tween of `instance` to `goals` over `ms`.
function Tweens.play(
	instance: Instance,
	ms: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local tween = TweenService:Create(instance, Tweens.info(ms, style, direction), goals)
	tween:Play()
	return tween
end

-- Same with a { ms, style?, direction? } spec, e.g. an entry of Config.UI.motion.
function Tweens.playSpec(instance: Instance, spec: Spec, goals: { [string]: any }): Tween
	return Tweens.play(instance, spec.ms, goals, spec.style, spec.direction)
end

-- A transparency/colour fade; capped at reducedMotionMaxFadeMs under ReducedMotion.
function Tweens.fade(
	instance: Instance,
	goals: { [string]: any },
	ms: number,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): Tween
	local duration = if Tweens.reducedMotion() then math.min(ms, MAX_FADE_MS) else ms
	return Tweens.play(instance, duration, goals, style, direction)
end

-- A UIScale pop from `from` to `to`. Under ReducedMotion the scale is set to `to` at once and nil is returned.
function Tweens.scale(uiScale: UIScale, from: number, to: number, spec: Spec): Tween?
	if Tweens.reducedMotion() then
		uiScale.Scale = to
		return nil
	end
	uiScale.Scale = from
	return Tweens.playSpec(uiScale, spec, { Scale = to })
end

-- Cancels a tween if there is one (nil-safe).
function Tweens.cancel(tween: Tween?)
	if tween then
		tween:Cancel()
	end
end

-- A number count-up effect for the Scheduler render phase: calls onValue(value) every frame with
-- from → to eased by TweenService:GetValue over `ms`, and exactly `to` on the last frame. Under ReducedMotion it
-- jumps to `to` on its first step. finish() jumps to the end now; cancel() stops without another call.
function Tweens.countUp(
	from: number,
	to: number,
	ms: number,
	onValue: (value: number) -> (),
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
): CountUp
	local easing = style or DEFAULT_STYLE
	local easingDirection = direction or DEFAULT_DIRECTION
	local duration = seconds(ms)
	local elapsed = 0
	local done = false
	local effect = {} :: CountUp

	function effect.step(_: CountUp, dt: number, _now: number): boolean
		if done then
			return false
		end
		elapsed += dt
		if duration <= 0 or elapsed >= duration or Tweens.reducedMotion() then
			done = true
			onValue(to)
			return false
		end
		local alpha = TweenService:GetValue(elapsed / duration, easing, easingDirection)
		onValue(from + (to - from) * alpha)
		return true
	end

	function effect.finish(_: CountUp)
		if not done then
			done = true
			onValue(to)
		end
	end

	function effect.cancel(_: CountUp)
		done = true
	end

	return effect
end

-- UI FINAL R2
-- ----------------------------------------------------------------------------------------------------------

local curveCache: { [string]: Curve } = {}

local function linear(u: number): number
	return u
end

-- A CSS cubic-bezier(x1, y1, x2, y2) (x1 and x2 in 0..1): u (the time share, clamped to 0..1) -> the eased progress,
-- which may leave 0..1 when y1 or y2 does (an overshoot).
function Tweens.bezier(x1: number, y1: number, x2: number, y2: number): Curve
	if x1 == y1 and x2 == y2 then
		return function(u: number): number
			return if u > 0 then math.min(u, 1) else 0 -- on the diagonal: y = x exactly (also NaN -> 0)
		end
	end
	local cx = 3 * x1
	local bx = 3 * (x2 - x1) - cx
	local ax = 1 - cx - bx
	local cy = 3 * y1
	local by = 3 * (y2 - y1) - cy
	local ay = 1 - cy - by
	local function sampleX(t: number): number
		return ((ax * t + bx) * t + cx) * t
	end
	local function sampleY(t: number): number
		return ((ay * t + by) * t + cy) * t
	end
	local function slopeX(t: number): number
		return (3 * ax * t + 2 * bx) * t + cx
	end
	return function(u: number): number
		if not (u > 0) then
			return 0 -- also NaN
		elseif u >= 1 then
			return 1
		end
		local t = u
		for _ = 1, NEWTON_STEPS do
			local err = sampleX(t) - u
			if math.abs(err) < BEZIER_EPSILON then
				return sampleY(t)
			end
			local slope = slopeX(t)
			if math.abs(slope) < 1e-6 then
				break
			end
			t -= err / slope
			if t < 0 or t > 1 then
				break
			end
		end
		local low, high = 0, 1
		t = u
		for _ = 1, BISECTION_STEPS do
			local x = sampleX(t)
			if math.abs(x - u) < BEZIER_EPSILON then
				break
			end
			if x < u then
				low = t
			else
				high = t
			end
			t = (low + high) / 2
		end
		return sampleY(t)
	end
end

-- The easing of a Config.UI.curves name (cached), or `curve` itself when it is a function; an unknown name is a
-- linear easing (Config F9 checks every name).
function Tweens.curve(curve: (string | Curve)?): Curve
	if type(curve) == "function" then
		return curve
	end
	local name = if type(curve) == "string" then curve else DEFAULT_CURVE
	local cached = curveCache[name]
	if cached then
		return cached
	end
	local numbers = (Config.UI.curves :: any)[name]
	local made: Curve = if type(numbers) == "table"
		then Tweens.bezier(numbers[1], numbers[2], numbers[3], numbers[4])
		else linear
	curveCache[name] = made
	return made
end

local function namesTransform(frame: Pose): boolean
	for _, field in TRANSFORM_FIELDS do
		if (frame :: any)[field] ~= nil then
			return true
		end
	end
	return false
end

local function namesAlpha(frame: Pose): boolean
	return frame.alpha ~= nil
end

local function namesColor(frame: Pose): boolean
	return frame.color ~= nil
end

-- The segment of one group around time t: its frames (those `names` keeps), with a rest frame added at 0 and at 1
-- where none is when `implicit`; nil when no frame names the group. k is t's share of the segment (outside 0..1 when
-- t is: an overshooting whole-run easing extrapolates the end segments).
local function groupSegment(
	frames: { Pose },
	t: number,
	names: (Pose) -> boolean,
	implicit: boolean
): (Pose?, Pose?, number)
	local list: { Pose } = {}
	for _, frame in frames do
		if names(frame) then
			table.insert(list, frame)
		end
	end
	if #list == 0 then
		return nil, nil, 0
	end
	if implicit and (list[1].at or 0) > 0 then
		table.insert(list, 1, { at = 0 })
	end
	if implicit and (list[#list].at or 1) < 1 then
		table.insert(list, { at = 1 })
	end
	if #list == 1 then
		return list[1], list[1], 1
	end
	local index = 1
	while index < #list - 1 and t > (list[index + 1].at or 1) do
		index += 1
	end
	local from, to = list[index], list[index + 1]
	local a, b = from.at or 0, to.at or 1
	local k = if b > a then (t - a) / (b - a) else 1
	if t >= 0 and t <= 1 then
		k = math.clamp(k, 0, 1)
	end
	return from, to, k
end

-- Every transform field any frame of the track names (the poser leaves the others alone).
local function transformFieldsOf(frames: { Pose }): { string }
	local named: { string } = {}
	for _, field in TRANSFORM_FIELDS do
		for _, frame in frames do
			if (frame :: any)[field] ~= nil then
				table.insert(named, field)
				break
			end
		end
	end
	return named
end

-- The pose of a track at u (0..1, clamped; see the header).
function Tweens.poseAt(frames: { Pose }, u: number, curve: (string | Curve)?, wholeRun: (string | Curve)?): Pose
	local t = if u == u then math.clamp(u, 0, 1) else 1
	local ease: Curve = linear
	if wholeRun ~= nil then
		t = Tweens.curve(wholeRun)(t)
	else
		ease = Tweens.curve(curve)
	end
	local pose: { [string]: any } = {}
	local from, to, k = groupSegment(frames, t, namesTransform, true)
	if from and to then
		local e = ease(k)
		for _, field in transformFieldsOf(frames) do
			local a = (from :: any)[field] or REST[field]
			local b = (to :: any)[field] or REST[field]
			pose[field] = a + (b - a) * e
		end
	end
	local alphaFrom, alphaTo, alphaK = groupSegment(frames, t, namesAlpha, true)
	if alphaFrom and alphaTo then
		local a = alphaFrom.alpha or REST.alpha
		local b = alphaTo.alpha or REST.alpha
		pose.alpha = a + (b - a) * ease(alphaK)
	end
	local colorFrom, colorTo, colorK = groupSegment(frames, t, namesColor, false)
	if colorFrom and colorTo then
		pose.color = (colorFrom.color :: Color3):Lerp(colorTo.color :: Color3, math.clamp(ease(colorK), 0, 1))
	end
	return pose :: Pose
end

-- Writes poses on an inner holder (see the header). Moves are whole base px (a UDim offset is an integer), added to the
-- holder's Position less the move it last added, so a caller's own move in between is kept; likewise the rotation and
-- (sx, sy) the Size it last set (a Size the caller changed becomes the new base). Alpha scales the opacity the holder
-- had when it first faded: a CanvasGroup's group, a text's or an image's own, else a frame's background and its
-- UIStrokes (a clear frame stays clear). Color sets TextColor3 / ImageColor3 / BackgroundColor3 (rest: the first one).
function Tweens.poser(holder: GuiObject): Poser
	local lastX, lastY, lastRot = 0, 0, 0
	local uiScale: UIScale? = nil
	local isText = holder:IsA("TextLabel") or holder:IsA("TextButton") or holder:IsA("TextBox")
	local squashes = not (isText or holder:IsA("ViewportFrame"))
	local baseSize: UDim2? = nil
	local lastSize: UDim2? = nil
	local uniform, squash = 1, 1 -- the pose's scale and (text, viewport) √(sx·sy)
	local fades: { { object: Instance, property: string, rest: number } }? = nil
	local colorProperty = if isText
		then "TextColor3"
		elseif holder:IsA("ImageLabel") or holder:IsA("ImageButton") then "ImageColor3"
		else "BackgroundColor3"
	local baseColor: Color3? = nil

	local function fadeTargets(): { { object: Instance, property: string, rest: number } }
		local known = fades
		if known then
			return known
		end
		local list = {}
		local function add(object: Instance, property: string)
			table.insert(list, { object = object, property = property, rest = (object :: any)[property] })
		end
		if holder:IsA("CanvasGroup") then
			add(holder, "GroupTransparency")
		elseif isText then
			add(holder, "TextTransparency")
		elseif holder:IsA("ImageLabel") or holder:IsA("ImageButton") then
			add(holder, "ImageTransparency")
		else
			add(holder, "BackgroundTransparency")
			for _, child in holder:GetChildren() do
				if child:IsA("UIStroke") then
					add(child, "Transparency")
				end
			end
		end
		fades = list
		return list
	end

	local function scaleObject(): UIScale
		local current = uiScale
		if current then
			return current
		end
		local found = holder:FindFirstChild(POSE_SCALE_NAME)
		if found and found:IsA("UIScale") then
			uiScale = found
			return found
		end
		local made = Instance.new("UIScale")
		made.Name = POSE_SCALE_NAME
		made.Parent = holder
		uiScale = made
		return made
	end

	local poser = {} :: Poser

	function poser.set(_: Poser, pose: Pose)
		if pose.x ~= nil or pose.y ~= nil then
			local x, y = math.round(pose.x or 0), math.round(pose.y or 0)
			local p = holder.Position
			holder.Position = UDim2.new(p.X.Scale, p.X.Offset - lastX + x, p.Y.Scale, p.Y.Offset - lastY + y)
			lastX, lastY = x, y
		end
		local rot = pose.rot
		if rot ~= nil then
			holder.Rotation = holder.Rotation - lastRot + rot
			lastRot = rot
		end
		local rescale = pose.scale ~= nil
		if pose.sx ~= nil or pose.sy ~= nil then
			local sx, sy = pose.sx or 1, pose.sy or 1
			if squashes then
				local current = holder.Size
				if baseSize == nil or current ~= lastSize then
					baseSize = current
				end
				local b = baseSize :: UDim2
				local size =
					UDim2.new(b.X.Scale * sx, math.round(b.X.Offset * sx), b.Y.Scale * sy, math.round(b.Y.Offset * sy))
				holder.Size = size
				lastSize = size
			else
				squash = math.sqrt(math.max(0, sx * sy))
				rescale = true
			end
		end
		if pose.scale ~= nil then
			uniform = pose.scale
		end
		if rescale then
			scaleObject().Scale = uniform * squash
		end
		local alpha = pose.alpha
		if alpha ~= nil then
			for _, target in fadeTargets() do
				(target.object :: any)[target.property] = 1 - (1 - target.rest) * alpha
			end
		end
		local color = pose.color
		if color ~= nil then
			if baseColor == nil then
				baseColor = (holder :: any)[colorProperty]
			end
			(holder :: any)[colorProperty] = color
		end
	end

	-- Back to the holder's own pose (only what this poser changed).
	function poser.rest(_: Poser)
		local p = holder.Position
		if lastX ~= 0 or lastY ~= 0 then
			holder.Position = UDim2.new(p.X.Scale, p.X.Offset - lastX, p.Y.Scale, p.Y.Offset - lastY)
			lastX, lastY = 0, 0
		end
		if lastRot ~= 0 then
			holder.Rotation -= lastRot
			lastRot = 0
		end
		local base = baseSize
		if base and holder.Size == lastSize then
			holder.Size = base
		end
		baseSize, lastSize = nil, nil
		uniform, squash = 1, 1
		local current = uiScale
		if current then
			current.Scale = 1
		end
		local list = fades
		if list then
			for _, target in list do
				(target.object :: any)[target.property] = target.rest
			end
		end
		if baseColor ~= nil then
			(holder :: any)[colorProperty] = baseColor
		end
	end

	return poser
end

-- A track played on `holder` (see the header), as a Scheduler render effect the caller adds.
function Tweens.keyframes(holder: GuiObject, frames: { Pose }, opts: KeyframeOptions): Keyframes
	local poser = Tweens.poser(holder)
	local curve, wholeRun = opts.curve, opts.wholeRun
	local duration = seconds(opts.ms)
	local delay = seconds(opts.delayMs or 0)
	local first = Tweens.poseAt(frames, 0, curve, wholeRun)
	local last = Tweens.poseAt(frames, 1, curve, wholeRun)
	local reduced = Tweens.reducedMotion()
	-- ReducedMotion (PR9): nothing moves and only the fades are left, each at most MAX_FADE_MS: from the first frame's
	-- alpha up to the track's peak at the start, down to the last frame's at the end of opts.ms (a toast still shows).
	local fadeFrom, fadeTo = first.alpha, last.alpha
	local peak: number? = nil
	if fadeFrom ~= nil then
		-- The peak: the first, the last (a group's implicit end at rest) and every frame that names alpha.
		local top = math.max(fadeFrom, fadeTo or fadeFrom)
		for _, frame in frames do
			top = math.max(top, frame.alpha or top)
		end
		peak = top
	end
	local fadeIn, fadeOut = fadeFrom ~= peak, fadeTo ~= peak
	local fadeSeconds = math.min(if fadeIn and fadeOut then duration / 2 else duration, MAX_FADE_MS / 1000)
	local elapsed = 0
	local done = false

	if reduced then
		poser:set({ alpha = fadeFrom })
		done = fadeFrom == nil or not (fadeIn or fadeOut)
	else
		poser:set(first)
	end

	local effect = {} :: Keyframes

	function effect.step(_: Keyframes, dt: number, _now: number): boolean
		if done then
			return false
		end
		elapsed += math.max(0, dt)
		local t = elapsed - delay
		if t < 0 then
			return true -- the first frame holds through the delay
		end
		if reduced then
			local a, top, b = fadeFrom :: number, peak :: number, fadeTo :: number
			local alpha = top
			if fadeIn and t < fadeSeconds then
				alpha = a + (top - a) * t / fadeSeconds
			elseif fadeOut and t >= duration - fadeSeconds then
				local k = if fadeSeconds > 0 then math.min((t - (duration - fadeSeconds)) / fadeSeconds, 1) else 1
				alpha = top + (b - top) * k
			end
			poser:set({ alpha = alpha })
			done = if fadeOut then t >= duration else t >= fadeSeconds
			return not done
		end
		if duration <= 0 or t >= duration then
			poser:set(last)
			done = true
			return false
		end
		poser:set(Tweens.poseAt(frames, t / duration, curve, wholeRun))
		return true
	end

	function effect.finish(_: Keyframes)
		if not done then
			done = true
			poser:set(if reduced then { alpha = fadeTo } else last)
		end
	end

	function effect.cancel(_: Keyframes)
		done = true
	end

	return effect
end

-- The fade of a whole element (see the header): every transparency of `holder` and its descendants as they are now.
function Tweens.fadeGroup(holder: Instance): FadeGroup
	local targets: { { object: Instance, property: string, base: number } } = {}
	local function record(object: Instance)
		for _, entry in FADE_PROPERTIES do
			if object:IsA(entry.class) then
				table.insert(
					targets,
					{ object = object, property = entry.property, base = (object :: any)[entry.property] }
				)
			end
		end
	end
	record(holder)
	for _, descendant in holder:GetDescendants() do
		record(descendant)
	end
	local group = {} :: FadeGroup
	function group.setAlpha(_: FadeGroup, alpha: number)
		local a = if alpha == alpha then math.clamp(alpha, 0, 1) else 1
		for _, target in targets do
			(target.object :: any)[target.property] = 1 - (1 - target.base) * a
		end
	end
	function group.restore(_: FadeGroup)
		for _, target in targets do
			(target.object :: any)[target.property] = target.base
		end
	end
	return group
end

return Tweens
