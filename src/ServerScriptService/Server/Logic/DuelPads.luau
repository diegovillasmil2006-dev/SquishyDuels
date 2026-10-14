--!strict
-- DuelPads: the rules of the duel pads under the Duel tower (Batch 3, review #6; user decision Q1 A). Server only,
-- pure: no instances, no yields; time, positions and who stands where come in. Services/FriendDuelService checks who
-- stands where Config.Social.Pads.checkHz times a second, calls step and performs the effects.
--   lanes(pads)                          -> { {mint = index, strawberry = index} } by lane (WorldLayout.QueuePads)
--   padAt(pads, position, cfg)           -> the pad a root at `position` stands on, or nil: within cfg.radiusStuds of
--                                           its centre horizontally and 0..cfg.heightStuds above its top
--   new()                                -> a State
--   step(state, pads, standing, now, cfg) -> { Effect }   standing = { [userId] = pad index } (players who may stand)
--   retry(state, lane)                   a start that may work later (cooldown, no free arena) fires again next step
-- Rules: a pad belongs to the first player on it (two arriving in one check: the lower userId); a second player on it
-- is ignored. A lane whose two pads are owned is ready: it starts holdSeconds after its owners last changed, once.
-- Effects, only on a change: glow {pad, look = "off" | "on" | "ready"} (the design's pad colours, lobby.js:197-199);
-- waiting {userId, team} when a player takes a pad whose partner pad is empty, at most once per
-- cfg.waitingToastSeconds per player; ready {lane, mint = userId, strawberry = userId} when a lane's two pads get their
-- owners (the countdown starts); start {lane, mint, strawberry} holdSeconds later.

-- Types

export type Pad = { position: Vector3, team: string, lane: number }
export type Look = "off" | "on" | "ready"
export type Lane = { mint: number, strawberry: number }
export type Effect = {
	kind: string, -- "glow" | "waiting" | "ready" | "start"
	pad: number?,
	look: Look?,
	userId: number?,
	team: string?,
	lane: number?,
	mint: number?,
	strawberry: number?,
}
export type State = {
	owners: { [number]: number }, -- pad index -> userId
	pairs: { [number]: string }, -- lane -> "mint:strawberry" userIds while both pads are owned
	readyAt: { [number]: number }, -- lane -> when it starts
	fired: { [number]: boolean }, -- lane -> its start was sent for these owners
	looks: { [number]: Look }, -- pad index -> the look shown (nil = off, as built)
	toastAt: { [number]: number }, -- userId -> the last waiting toast
}
export type PadConfig = {
	holdSeconds: number,
	radiusStuds: number,
	heightStuds: number,
	waitingToastSeconds: number,
}

-- Module table

local DuelPads = {}

-- Public

function DuelPads.lanes(pads: { Pad }): { Lane }
	local found: { [number]: { [string]: number } } = {}
	for index, pad in pads do
		local lane = found[pad.lane] or {}
		lane[pad.team] = index
		found[pad.lane] = lane
	end
	local lanes: { Lane } = {}
	for lane = 1, #pads // 2 do
		local pair: { [string]: number } = found[lane] or {}
		table.insert(lanes, { mint = pair.mint, strawberry = pair.strawberry })
	end
	return lanes
end

function DuelPads.padAt(pads: { Pad }, position: Vector3, cfg: PadConfig): number?
	for index, pad in pads do
		local offset = position - pad.position
		if
			offset.Y >= 0
			and offset.Y <= cfg.heightStuds
			and Vector2.new(offset.X, offset.Z).Magnitude <= cfg.radiusStuds
		then
			return index
		end
	end
	return nil
end

function DuelPads.new(): State
	return { owners = {}, pairs = {}, readyAt = {}, fired = {}, looks = {}, toastAt = {} }
end

function DuelPads.retry(state: State, lane: number)
	state.fired[lane] = nil
end

function DuelPads.step(
	state: State,
	pads: { Pad },
	standing: { [number]: number },
	now: number,
	cfg: PadConfig
): { Effect }
	local effects: { Effect } = {}
	-- An owner who left the pad frees it.
	for pad, userId in table.clone(state.owners) do
		if standing[userId] ~= pad then
			state.owners[pad] = nil
		end
	end
	-- A free pad goes to the player on it (the lower userId when two arrive in one check).
	local arrived: { [number]: number } = {}
	for userId, pad in standing do
		if pads[pad] ~= nil and state.owners[pad] == nil and (arrived[pad] == nil or userId < arrived[pad]) then
			arrived[pad] = userId
		end
	end
	for pad, userId in arrived do
		state.owners[pad] = userId
	end
	for lane, pair in DuelPads.lanes(pads) do
		local mint, berry = state.owners[pair.mint], state.owners[pair.strawberry]
		local key = if mint ~= nil and berry ~= nil then `{mint}:{berry}` else nil
		if key ~= state.pairs[lane] then
			state.fired[lane] = nil
			if key then
				state.pairs[lane], state.readyAt[lane] = key, now + cfg.holdSeconds
				table.insert(effects, { kind = "ready", lane = lane, mint = mint, strawberry = berry })
			else
				state.pairs[lane], state.readyAt[lane] = nil, nil
			end
		end
		for _, pad in { pair.mint, pair.strawberry } do
			local owner = state.owners[pad]
			local look: Look = if key then "ready" elseif owner ~= nil then "on" else "off"
			if look ~= (state.looks[pad] or "off") then
				state.looks[pad] = look
				table.insert(effects, { kind = "glow", pad = pad, look = look })
			end
		end
		for _, pad in { pair.mint, pair.strawberry } do
			local owner = arrived[pad]
			local last = if owner then state.toastAt[owner] else nil
			if owner and key == nil and (last == nil or now - last >= cfg.waitingToastSeconds) then
				state.toastAt[owner] = now
				table.insert(effects, { kind = "waiting", userId = owner, team = pads[pad].team })
			end
		end
		local readyAt = state.readyAt[lane]
		if key and readyAt and now >= readyAt and not state.fired[lane] then
			state.fired[lane] = true
			table.insert(effects, { kind = "start", lane = lane, mint = mint, strawberry = berry })
		end
	end
	return effects
end

return table.freeze(DuelPads)
