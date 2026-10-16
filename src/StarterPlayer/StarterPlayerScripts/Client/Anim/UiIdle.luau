--!strict
-- UiIdle (client only). UI FINAL R2 (plan work/ui/PLAN.md §2: the design's perpetual @keyframes, "Squishy Duels
-- HUD.dc.html" H:23-68): the UI's idle loops, all driven by ONE Scheduler render effect while any runs (not "Idle":
-- Anim/IdleRig is the squishies' own).
--   UiIdle.add(holder, kind, { periodS?, delayS? }?) -> Handle?   handle:remove()
--     kind     bob, coin, float, pulse, badge, shine, spin, dot, ring, twinkle (Config.UI.motion.idle: each kind's
--              poses, curve and default period; a caller passes the period and delay of its design line)
--     holder   an INNER holder no layout places: the pose is written through Tweens.poser (its own Position and
--              Rotation plus the move, a caller's re-place kept; its SD_Pose UIScale; its transparency). A shine's
--              holder is the px strip itself (G4.13): its Position moves from fromShare to toShare of its own width
--              inside a ClipsDescendants parent (the strip's width never depends on what it crosses). Stable names
--              (Hud_*Button, Quest_<id>, ...) stay on the outer object. A holder whose parent holds a layout is
--              refused (nil).
--   UiIdle.addFrames(holder, frames, { periodS, delayS?, alternate?, curve? }) -> Handle?   any looping @keyframes
--              (G2.4; Config.UI.motion.loops): Tweens.poseAt's groups on a loop, `alternate` = CSS alternate
--              (forward, then back), `curve` each segment's easing (default CSS ease)
--   UiIdle.addGradientWindow(gradient, stops, { periodS, alternate?, curve?, windowShare }) -> Handle?   the visible
--              window of a longer gradient (sdLvGrad, H:519: background-size 220%, position 0 -> 100%): every frame
--              the UIGradient's Color is the stops seen through a window windowShare of the whole, sliding from its
--              top to its bottom
-- Every period under 1/3 s is held at 1/3 s (<= 3 Hz, §9.12; a spin excepted, it does not swing). An entry starts with
-- its first frame, waits out its delay at rest and loops; a hidden holder (Visible off up its tree, a disabled
-- ScreenGui, or not under one) is skipped. Under ReducedMotion (Anim/Tweens.reducedMotion: Roblox's setting or
-- UiPrefs' reduceMotion, read every frame, so a switch mid-run counts at once) every entry rests at its keyframe 0%
-- pose (plan T11, PR9: a twinkle hidden, a shine's strip out of sight); the loops go on when it is off again. An entry
-- ends with its holder (Destroying) or remove(); one whose frame errors is dropped (logged) and the others go on.
-- Pure: poseAt(kind, u), gradientWindow(stops, offset, share) (unit-tested in Edit mode); step(now) runs one frame by
-- hand and setScheduler(scheduler?) drives the loops from a private Scheduler (tests: Scheduler.new(false), so only
-- their own steps run; nil = the default one).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)
local Log = require(ReplicatedStorage.Shared.Util.Log)
local Scheduler = require(script.Parent.Scheduler)
local Tweens = require(script.Parent.Tweens)

-- Types

export type Kind = "bob" | "coin" | "float" | "pulse" | "badge" | "shine" | "spin" | "dot" | "ring" | "twinkle"

export type Options = { periodS: number?, delayS: number? }

export type FramesOptions = { periodS: number, delayS: number?, alternate: boolean?, curve: string? }

-- One colour stop of a gradient (pos 0..1 along it).
export type Stop = { pos: number, color: Color3 }

export type WindowOptions = { periodS: number, alternate: boolean?, curve: string?, windowShare: number }

export type Handle = { remove: (self: Handle) -> () }

type Entry = {
	holder: Instance,
	visibleObject: GuiObject?, -- what shown() checks (the gradient's parent for a window)
	label: string, -- the kind, "frames" or "window" (logs)
	periodS: number,
	delayS: number,
	alternate: boolean,
	start: number?, -- the clock of its first frame
	pose: (u: number) -> Tweens.Pose, -- the pose u (0..1) into the period (not for a window)
	poser: Tweens.Poser?,
	window: ((u: number) -> ())?, -- a gradient window's frame
	resting: boolean,
	destroying: RBXScriptConnection?,
}

-- Constants

local IDLE = Config.UI.motion.idle
local KINDS: { Kind } = { "bob", "coin", "float", "pulse", "badge", "shine", "spin", "dot", "ring", "twinkle" }
local MIN_PERIOD = 1 / 3 -- §9.12: no loop above 3 Hz

-- Module table

local UiIdle = {}

UiIdle.KINDS = table.freeze(KINDS)
UiIdle.MIN_PERIOD = MIN_PERIOD

-- Private

local log = Log.new("UiIdle")
local entries: { Entry } = {}
local driver: Scheduler.Handle? = nil
local scheduler: Scheduler.Scheduler? = nil -- setScheduler's; nil = Scheduler.default()

-- 0 at the ends of a period, 1 at its middle, each half eased by `curve` (the design's "0%,100% / 50%" loops).
local function swing(u: number, curve: Tweens.Curve): number
	return if u < 0.5 then curve(u * 2) else curve((1 - u) * 2)
end

local function laidOut(holder: Instance): boolean
	local parent = holder.Parent
	return parent ~= nil and parent:FindFirstChildWhichIsA("UIGridStyleLayout") ~= nil
end

-- On screen: every GuiObject up the tree Visible, under an enabled ScreenGui (or other LayerCollector).
local function shown(object: GuiObject?): boolean
	local node: Instance? = object
	while node ~= nil do
		if node:IsA("LayerCollector") then
			return (node :: LayerCollector).Enabled
		elseif node:IsA("GuiObject") and not (node :: GuiObject).Visible then
			return false
		end
		node = node.Parent
	end
	return false
end

-- The loop's place u (0..1) into its keyframes at time t (after its delay): CSS alternate runs every other period
-- backwards.
local function loopU(t: number, periodS: number, alternate: boolean): number
	local cycles = t / periodS
	local u = cycles % 1
	if alternate and math.floor(cycles) % 2 == 1 then
		return 1 - u
	end
	return u
end

local function rest(entry: Entry)
	if entry.resting then
		return
	end
	entry.resting = true
	local window = entry.window
	if window then
		window(0)
		return
	end
	local poser = entry.poser
	if poser then
		poser:set(entry.pose(0)) -- T11: the keyframe's 0% pose
	end
end

local function apply(entry: Entry, now: number)
	local start = entry.start
	if start == nil then
		entry.start = now
		start = now
	end
	local t = now - (start :: number) - entry.delayS
	if t < 0 then
		rest(entry)
		return
	end
	entry.resting = false
	local u = loopU(t, entry.periodS, entry.alternate)
	local window = entry.window
	if window then
		window(u)
	else
		(entry.poser :: Tweens.Poser):set(entry.pose(u))
	end
end

local function removeEntry(entry: Entry)
	local index = table.find(entries, entry)
	if index == nil then
		return
	end
	table.remove(entries, index)
	local connection = entry.destroying
	if connection then
		connection:Disconnect()
	end
	-- Back to the holder's own (authored) pose; a gradient window back to its first window.
	if entry.holder.Parent ~= nil then
		local poser, window = entry.poser, entry.window
		if poser then
			poser:rest()
		elseif window then
			window(0)
		end
	end
end

local function holdPeriod(label: string, name: string, period: number, swings: boolean): number
	if swings and period > 0 and period < MIN_PERIOD then
		log:warn(`{name}: a {label} loop of {period} s is above 3 Hz; held to {MIN_PERIOD} s`)
		return MIN_PERIOD
	end
	return period
end

local function insert(entry: Entry): Handle
	entry.destroying = entry.holder.Destroying:Connect(function()
		removeEntry(entry)
	end)
	table.insert(entries, entry)
	if driver == nil then
		driver = (scheduler or Scheduler.default()):add(function(_dt: number, now: number): boolean
			UiIdle.step(now)
			if #entries == 0 then
				driver = nil
				return false
			end
			return true
		end, "render")
	end
	local handle = {} :: Handle
	function handle.remove(_: Handle)
		removeEntry(entry)
	end
	return handle
end

-- Public: pure -------------------------------------------------------------------------------------------------------

-- The pose of `kind` at u (0..1) of its period, from Config.UI.motion.idle (only the fields the kind moves). A
-- shine's x is a share of its strip's width.
function UiIdle.poseAt(kind: string, u: number): Tweens.Pose
	local spec = IDLE[kind]
	local curve = Tweens.curve(spec.curve)
	if kind == "bob" then
		local k = swing(u, curve)
		return { y = -spec.risePx * k, rot = -spec.rotDeg * k } -- H:23
	elseif kind == "coin" or kind == "float" then
		local k = swing(u, curve)
		return { y = -spec.risePx * k, rot = spec.rotDeg * (2 * k - 1) } -- H:24, H:34
	elseif kind == "pulse" then
		return { scale = 1 + (spec.scale - 1) * swing(u, curve) } -- H:29
	elseif kind == "badge" then
		return Tweens.poseAt(spec.frames, u, spec.curve) -- H:32
	elseif kind == "dot" then
		local k = swing(u, curve)
		return {
			alpha = spec.alphaFrom + (1 - spec.alphaFrom) * k,
			scale = spec.scaleFrom + (spec.scaleTo - spec.scaleFrom) * k,
		} -- H:35
	elseif kind == "twinkle" then
		local k = swing(u, curve)
		return { alpha = k, scale = spec.scaleFrom + (1 - spec.scaleFrom) * k, rot = spec.rotDeg * k } -- H:40
	elseif kind == "ring" then
		local e = curve(math.clamp(u, 0, 1))
		-- H:43
		return { scale = spec.scaleFrom + (spec.scaleTo - spec.scaleFrom) * e, alpha = spec.alphaFrom * (1 - e) }
	elseif kind == "spin" then
		return { rot = 360 * curve(math.clamp(u, 0, 1)) } -- H:30
	elseif kind == "shine" then
		local hold = spec.holdShare
		local x = if u <= hold
			then spec.fromShare
			else spec.fromShare + (spec.toShare - spec.fromShare) * curve((u - hold) / (1 - hold))
		return { x = x } -- H:28
	end
	return {}
end

-- The ColorSequence of a gradient's window: `share` (0..1] of the gradient seen from `offset` (0..1 - share) along it.
function UiIdle.gradientWindow(stops: { Stop }, offset: number, share: number): ColorSequence
	local function colorAt(pos: number): Color3
		if pos <= stops[1].pos then
			return stops[1].color
		end
		for index = 2, #stops do
			local a, b = stops[index - 1], stops[index]
			if pos <= b.pos then
				local span = b.pos - a.pos
				return a.color:Lerp(b.color, if span > 0 then (pos - a.pos) / span else 1)
			end
		end
		return stops[#stops].color
	end
	local width = math.clamp(share, 0.01, 1)
	local from = math.clamp(offset, 0, 1 - width)
	local points = { ColorSequenceKeypoint.new(0, colorAt(from)) }
	for _, stop in stops do
		local at = (stop.pos - from) / width
		if at > 0.001 and at < 0.999 then
			table.insert(points, ColorSequenceKeypoint.new(at, stop.color))
		end
	end
	table.insert(points, ColorSequenceKeypoint.new(1, colorAt(from + width)))
	return ColorSequence.new(points)
end

-- Public -------------------------------------------------------------------------------------------------------------

-- One frame of every entry at clock `now` (the driver's Scheduler effect; tests call it by hand).
function UiIdle.step(now: number)
	if Tweens.reducedMotion() then
		for _, entry in entries do
			rest(entry) -- once per entry: rest() skips one already resting
		end
		return
	end
	-- Backwards: a failing entry is removed on the way.
	for index = #entries, 1, -1 do
		local entry = entries[index]
		if entry and shown(entry.visibleObject) then
			local ok, err = pcall(apply :: any, entry, now) -- any: apply returns nothing; err is pcall's 2nd value
			if not ok then
				log:warn(`the {entry.label} loop of {entry.holder:GetFullName()} failed and was removed:`, err)
				removeEntry(entry)
			end
		end
	end
end

function UiIdle.add(holder: GuiObject, kind: Kind, opts: Options?): Handle?
	local spec = IDLE[kind]
	assert(spec ~= nil, `[SD][UiIdle] unknown kind {tostring(kind)}`)
	if laidOut(holder) then
		log:warn(`{holder:GetFullName()} is placed by a layout: give the {kind} loop an inner holder`)
		return nil
	end
	local o: Options = opts or {}
	local period = holdPeriod(kind, holder:GetFullName(), o.periodS or spec.periodS, kind ~= "spin")
	local width = if kind == "shine" then holder.Size.X.Offset else 0
	local entry: Entry = {
		holder = holder,
		visibleObject = holder,
		label = kind,
		periodS = if period > 0 then period else spec.periodS,
		delayS = math.max(0, o.delayS or 0),
		alternate = false,
		start = nil,
		pose = if kind == "shine"
			then function(u: number): Tweens.Pose
				local pose = UiIdle.poseAt(kind, u)
				return { x = (pose.x :: number) * width }
			end
			else function(u: number): Tweens.Pose
				return UiIdle.poseAt(kind, u)
			end,
		poser = Tweens.poser(holder),
		window = nil,
		resting = false, -- so the first rest() puts it at rest (a shine's strip out of sight)
		destroying = nil,
	}
	return insert(entry)
end

function UiIdle.addFrames(holder: GuiObject, frames: { Tweens.Pose }, opts: FramesOptions): Handle?
	if laidOut(holder) then
		log:warn(`{holder:GetFullName()} is placed by a layout: give the loop an inner holder`)
		return nil
	end
	local alternate = opts.alternate == true
	-- An alternate loop swings once a period, a plain one once a cycle (§9.12 counts the swings).
	local period = holdPeriod("frames", holder:GetFullName(), opts.periodS, true)
	if alternate and period < MIN_PERIOD / 2 then
		period = MIN_PERIOD / 2
	end
	local curve = opts.curve
	local entry: Entry = {
		holder = holder,
		visibleObject = holder,
		label = "frames",
		periodS = if period > 0 then period else 1,
		delayS = math.max(0, opts.delayS or 0),
		alternate = alternate,
		start = nil,
		pose = function(u: number): Tweens.Pose
			return Tweens.poseAt(frames, u, curve)
		end,
		poser = Tweens.poser(holder),
		window = nil,
		resting = false,
		destroying = nil,
	}
	return insert(entry)
end

function UiIdle.addGradientWindow(gradient: UIGradient, stops: { Stop }, opts: WindowOptions): Handle?
	if #stops < 2 then
		log:warn(`{gradient:GetFullName()}: a gradient window needs two stops or more`)
		return nil
	end
	local parent = gradient.Parent
	local alternate = opts.alternate == true
	local period = holdPeriod("gradient window", gradient:GetFullName(), opts.periodS, true)
	local ease = Tweens.curve(opts.curve)
	local share = opts.windowShare
	local entry: Entry = {
		holder = gradient,
		visibleObject = if parent and parent:IsA("GuiObject") then parent else nil,
		label = "window",
		periodS = if period > 0 then period else 1,
		delayS = 0,
		alternate = alternate,
		start = nil,
		pose = function(_u: number): Tweens.Pose
			return {}
		end,
		poser = nil,
		window = function(u: number)
			gradient.Color = UiIdle.gradientWindow(stops, ease(u) * (1 - share), share)
		end,
		resting = false,
		destroying = nil,
	}
	return insert(entry)
end

-- The Scheduler the loops' one effect runs in (tests pass Scheduler.new(false)); nil: the default one. The running
-- effect moves over at the next add after clear().
function UiIdle.setScheduler(s: Scheduler.Scheduler?)
	scheduler = s
end

-- Entries running now (tests and leak checks).
function UiIdle.count(): number
	return #entries
end

-- Removes every entry, each holder at rest, and stops the driver (tests; the next add starts it again, in the
-- setScheduler one).
function UiIdle.clear()
	for index = #entries, 1, -1 do
		removeEntry(entries[index])
	end
	local running = driver
	driver = nil
	if running then
		running:disconnect()
	end
end

return UiIdle
