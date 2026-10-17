--!strict
-- MotionTrack (client only). UI FINAL R8 (plan work/ui/PLAN.md R8): plays one design @keyframes track (a Config
-- MotionPose list: sdRise, sdStamp) on an inner holder no layout places: its poses through Anim/Tweens.poser, its
-- alpha over the holder and everything in it through Tweens.fadeGroup, after delayMs, each segment eased `curve`.
-- Nothing moves under ReducedMotion (the holder rests, PR9). A new track on a holder first puts the last one at rest;
-- stop(holder) does too, and a holder that goes away drops its track. (InventoryController's local playTrack, R5, is
-- the same rule; it keeps its own copy.)
--   MotionTrack.play(card.rise, Config.UI.motion.cardIn.frames, 450, 50 * (i - 1), "rise")
--   MotionTrack.stop(card.rise)

-- Requires

local Client = script.Parent.Parent
local Scheduler = require(Client.Anim.Scheduler)
local Tweens = require(Client.Anim.Tweens)

-- Types

type Track = { handle: Scheduler.Handle, poser: Tweens.Poser, fade: Tweens.FadeGroup }

-- Module table

local MotionTrack = {}

-- Private

local tracks: { [GuiObject]: Track } = setmetatable({}, { __mode = "k" }) :: any

-- Public

-- Stops `holder`'s track and puts it at rest (its pose and every transparency it faded).
function MotionTrack.stop(holder: GuiObject)
	local track = tracks[holder]
	if track then
		tracks[holder] = nil
		track.handle:disconnect()
		track.poser:rest()
		track.fade:restore()
	end
end

-- Plays `frames` on `holder` over `ms` after `delayMs` (the first frame held through the delay, CSS fill: both).
function MotionTrack.play(holder: GuiObject, frames: { any }, ms: number, delayMs: number, curve: string?)
	MotionTrack.stop(holder)
	if Tweens.reducedMotion() or ms <= 0 then
		return
	end
	local poser = Tweens.poser(holder)
	local fade = Tweens.fadeGroup(holder)
	local function apply(u: number)
		local pose = Tweens.poseAt(frames :: { Tweens.Pose }, u, curve)
		fade:setAlpha(pose.alpha or 1)
		pose.alpha = nil
		poser:set(pose)
	end
	apply(0)
	local elapsed = 0
	local handle = Scheduler.add(function(dt: number): boolean
		if holder.Parent == nil then
			tracks[holder] = nil
			return false
		end
		elapsed += dt
		local u = (elapsed * 1000 - delayMs) / ms
		if u < 0 then
			return true
		end
		if u >= 1 then
			MotionTrack.stop(holder)
			return false
		end
		apply(u)
		return true
	end, "render")
	tracks[holder] = { handle = handle, poser = poser, fade = fade }
end

return MotionTrack
