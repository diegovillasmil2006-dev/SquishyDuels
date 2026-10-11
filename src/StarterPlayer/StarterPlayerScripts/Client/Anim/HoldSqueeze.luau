--!strict
-- HoldSqueeze (client only, pure): press-and-hold squeezing of one SquishRig, shared by the first-person hand
-- (ViewmodelController) and Inspect (first-person spec 2026-10-10 §3.5, §3.7). No instances, connections or clock
-- reads: the rig's own clock (rig:elapsedMs()) times everything, never os.clock or a later frame.
--
-- API
--   HoldSqueeze.begin(rig) -> boolean   a key, button or touch went down: rig:press() at once, on the rig's own axis
--                                       (its owner sets it with rig:setAxis), and true. A press before the running
--                                       squeeze's pop end merges into it instead (the mashing cap, user decision
--                                       2026-10-10: at most about 2.6 squeezes a second, under the 3 Hz rule):
--                                       nothing changes and it returns false, so a caller counts one squeeze (preview,
--                                       sound) only on true.
--   HoldSqueeze.finish(rig)             it went up: before the rig's releaseStartMs rig:endPress() makes the press
--                                       exactly a tap; later rig:release() pops it from where it is. Both do nothing
--                                       when the rig is not in a press (a merged begin, or a windup's hold took over).

-- Requires

local SquishRig = require(script.Parent.SquishRig)

-- Module table

local HoldSqueeze = {}

-- Public

function HoldSqueeze.begin(rig: SquishRig.Rig): boolean
	if rig:elapsedMs() ~= nil and not rig:isRecovering() then
		return false -- the running squeeze has not reached its pop end: merge
	end
	rig:press()
	return true
end

function HoldSqueeze.finish(rig: SquishRig.Rig)
	local elapsed = rig:elapsedMs()
	if elapsed ~= nil and elapsed < rig.timing.releaseStartMs then
		rig:endPress()
	else
		rig:release()
	end
end

return HoldSqueeze
