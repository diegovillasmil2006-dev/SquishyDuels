--!strict
-- MatchVote (server only, pure). Round 3 of the match flow (2026-10-25, owner: Diego's map vote for Team and Free for
-- All; `L:n` = "Squishy Duels LOBBY HUD.dc.html" line n, its vote L:1066-1142): the vote's rules. MatchService keeps
-- one Order per match about to start and feeds it; cfg is Config.Match.Vote.
--   MatchVote.tally(order, count) -> { number }       each choice's votes
--   MatchVote.cast(order, userId, choice) -> boolean  the player's vote moves to `choice` (landing last there); true when
--                                                     it changed (L:1085-1105)
--   MatchVote.result(order, count, rng, cfg) -> Result   the most voted choice; a tie (or nobody: every choice tied at
--                                                     0) is decided at random, after the design's roulette over the tied
--                                                     (L:1115-1127): `roulette` = { choice, atMs } from the result,
--                                                     revealMs = when the winner shows
--   MatchVote.botPick(order, count, rng, cfg) -> number  a bot's choice: the leader at botFollowShare, else any (L:1076)
--   MatchVote.botTimes(count, spanMs, rng, cfg) -> { number | false }   each bot's vote time into the vote (L:1070:
--                                                     botSkipShare of them never vote)

export type Order = { { number } } -- per choice, its voters' userIds in landing order
export type RouletteStep = { choice: number, atMs: number }
export type Result = { winner: number, kind: "chosen" | "tie" | "random", roulette: { RouletteStep }, revealMs: number }

local MatchVote = {}

function MatchVote.tally(order: Order, count: number): { number }
	local out: { number } = {}
	for i = 1, count do
		local list = order[i]
		out[i] = if list then #list else 0
	end
	return out
end

function MatchVote.cast(order: Order, userId: number, choice: number): boolean
	local current: number? = nil
	for i, list in order do
		local at = table.find(list, userId)
		if at then
			current = i
			if i ~= choice then
				table.remove(list, at)
			end
		end
	end
	if current == choice then
		return false
	end
	table.insert(order[choice], userId)
	return true
end

function MatchVote.result(order: Order, count: number, rng: Random, cfg: any): Result
	local counts = MatchVote.tally(order, count)
	local top = 0
	for _, n in counts do
		top = math.max(top, n)
	end
	local tied: { number } = {}
	for i = 1, count do
		if counts[i] == top then
			table.insert(tied, i)
		end
	end
	local winner = tied[rng:NextInteger(1, #tied)]
	if #tied < 2 then
		return { winner = winner, kind = "chosen", roulette = {}, revealMs = cfg.chosenRevealMs }
	end
	-- L:1122-1126: from a random tied choice round the tied ones, at least rouletteExtra + #tied steps and on until the
	-- winner, each step 80 + n² x 1.3 ms after the last.
	local roulette: { RouletteStep } = {}
	local start = rng:NextInteger(0, #tied - 1)
	local t = cfg.rouletteFirstMs
	local n = 0
	while n < cfg.rouletteExtra + #tied or roulette[#roulette].choice ~= winner do
		t += cfg.rouletteStepMs + n * n * cfg.rouletteGrowMs
		table.insert(roulette, { choice = tied[(start + n) % #tied + 1], atMs = t })
		n += 1
	end
	return {
		winner = winner,
		kind = if top == 0 then "random" else "tie",
		roulette = roulette,
		revealMs = t + cfg.rouletteRevealMs,
	}
end

function MatchVote.botPick(order: Order, count: number, rng: Random, cfg: any): number
	local counts = MatchVote.tally(order, count)
	local top, leader = 0, 1
	for i, n in counts do
		if n > top then
			top, leader = n, i
		end
	end
	if top > 0 and rng:NextNumber() < cfg.botFollowShare then
		return leader
	end
	return rng:NextInteger(1, math.max(1, count))
end

function MatchVote.botTimes(count: number, spanMs: number, rng: Random, cfg: any): { number | false }
	local out: { number | false } = {}
	for i = 1, count do
		if rng:NextNumber() > cfg.botSkipShare then
			out[i] = cfg.botFirstMs + rng:NextNumber() * math.max(cfg.botMinSpanMs, spanMs - cfg.botSpanMarginMs)
		else
			out[i] = false
		end
	end
	return out
end

return MatchVote
