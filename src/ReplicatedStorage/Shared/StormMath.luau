--!strict
-- StormMath: the Team Deathmatch storm (Config.Match.Storm; jayyyyy 2026-10-15: "a zone like a fortnite storm that
-- deals damage to the players and gets smaller into the center"). Shared and pure (no instances, no yields): the
-- server's MatchRules decides storm K.O.s with it and the client draws the wall, the timer and the storm bar with the
-- same numbers.
-- The safe circle is centred on the map's centre. It starts as the circle around the whole map (startRadius: half the
-- diagonal of the map's floor footprint) and from Storm.stormStartSeconds shrinks step by step: step i shrinks
-- linearly from the previous radius to radiusFraction_i x startRadius over [shrinkAt_i, shrinkAt_i + shrinkSeconds_i].
-- A player is in the storm when their horizontal distance from the centre is greater than the radius (height is
-- ignored). The storm bar (0..1) fills by dt / barFillSeconds while in the storm and drains by dt / barDrainSeconds
-- outside it; at 1 the player is knocked out.
--
-- API (`t` = seconds since the match's Active phase began; `storm` = a Config.Match.Storm-shaped table):
--   StormMath.startRadius(footprint: Vector3) -> number          half of the X/Z diagonal
--   StormMath.shown(storm, t) -> boolean                         the wall is up (t >= stormStartSeconds)
--   StormMath.radiusAt(storm, startRadius, t) -> number          the safe circle's radius at t
--   StormMath.nextShrink(storm, t) -> (number?, number?)         seconds until the next shrink starts and its step
--                                                                index; nil once every shrink has started
--   StormMath.inStorm(center, radius, position) -> boolean
--   StormMath.stepBar(storm, bar, inStorm, dt) -> number         the bar after dt seconds, clamped to 0..1

local StormMath = {}

function StormMath.startRadius(footprint: Vector3): number
	return math.sqrt(footprint.X * footprint.X + footprint.Z * footprint.Z) / 2
end

function StormMath.shown(storm: any, t: number): boolean
	return t >= storm.stormStartSeconds
end

function StormMath.radiusAt(storm: any, startRadius: number, t: number): number
	local radius = startRadius
	for _, step in storm.steps do
		local target = step.radiusFraction * startRadius
		if t <= step.shrinkAt then
			return radius
		end
		local done = t - step.shrinkAt
		if done < step.shrinkSeconds then
			return radius + (target - radius) * (done / step.shrinkSeconds)
		end
		radius = target
	end
	return radius
end

function StormMath.nextShrink(storm: any, t: number): (number?, number?)
	for index, step in storm.steps do
		if t < step.shrinkAt then
			return step.shrinkAt - t, index
		end
	end
	return nil, nil
end

function StormMath.inStorm(center: Vector3, radius: number, position: Vector3): boolean
	local dx, dz = position.X - center.X, position.Z - center.Z
	return dx * dx + dz * dz > radius * radius
end

function StormMath.stepBar(storm: any, bar: number, inStorm: boolean, dt: number): number
	if dt <= 0 then
		return math.clamp(bar, 0, 1)
	end
	if inStorm then
		return math.clamp(bar + dt / storm.barFillSeconds, 0, 1)
	end
	return math.clamp(bar - dt / storm.barDrainSeconds, 0, 1)
end

return StormMath
