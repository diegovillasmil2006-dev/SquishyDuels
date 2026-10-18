--!strict
-- PressSpeed (shared, pure): the auto-clicker check's speed count, kept by each client on its own clock (p13v3; owner
-- 2026-10-18: "Yes, above 20 a second"; Config.Net.AutoClick.speed). SqueezeController and HighwayThrowController feed
-- it every real press (also the ones they do not send); each SqueezeRequest / HighwayThrow reports `peak`, and the
-- server (AutoClickRules.speed) catches a report of speed.seconds or more. Verification fix: counted by the second a
-- request reached the server, a person at 16-18 a second was caught after a lag spike (held requests arriving at once);
-- on the client's own clock a stall, a late reply or a draining network never makes presses look faster.
--   new() -> State
--   press(state, now)  one real press at `now` (the client's os.clock): counted in its whole second; `streak` = the
--     whole seconds right before it that each had more than speed.perSecond presses (an empty or a slower second
--     starts it again); `peak` = the most seconds in a row since the last send (the current second counts once it is
--     over the line).
--   sent(state)  after a send that carried `peak`: the next one reports from the run so far.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Config = require(ReplicatedStorage.Shared.Config)

-- Types

export type State = {
	second: number, -- the whole second (math.floor of the press time) being counted
	count: number, -- its presses so far
	streak: number, -- the seconds right before it with more than speed.perSecond presses each
	peak: number, -- what the next send reports
}

-- Constants

local PER_SECOND: number = Config.Net.AutoClick.speed.perSecond

-- Module table

local PressSpeed = {}

-- Private

-- The seconds in a row over the line, as of the latest press.
local function run(state: State): number
	return state.streak + (if state.count > PER_SECOND then 1 else 0)
end

-- Public

function PressSpeed.new(): State
	return { second = -math.huge, count = 0, streak = 0, peak = 0 }
end

function PressSpeed.press(state: State, now: number)
	local second = math.floor(now)
	if second ~= state.second then
		local hot = state.count > PER_SECOND and second == state.second + 1
		state.streak = if hot then state.streak + 1 else 0
		state.second, state.count = second, 0
	end
	state.count += 1
	state.peak = math.max(state.peak, run(state))
end

function PressSpeed.sent(state: State)
	state.peak = run(state)
end

return table.freeze(PressSpeed)
