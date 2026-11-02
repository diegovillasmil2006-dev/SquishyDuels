--!strict
-- DuelVote (server only, pure). The 1v1 map vote (2026-11-01, owner: "1v1 vote and if both vote it should be random
-- between the 2 maps"; "Short: 5 s vote"; "Every duel"): each duel's MATCH FOUND show votes between the duel maps with
-- the Team / Free for All vote's rules and screen (Logic/MatchVote, UI/MatchVoteBoard): the most voted map wins and a
-- tie is decided at random over the tied, so two different votes are a coin flip between those two maps and no vote at
-- all is any map. DuelService keeps one per duel through Preparing; cfg is Config.Match.Vote with
-- Config.Duel.Vote.seconds.
--   DuelVote.new(id, maps, arenaIds, botIds, now, rng, cfg) -> Vote   maps = the cards' Workspace.SquishyMaps names,
--                                                     arenaIds = their ArenaService ids; botIds vote by themselves
--   DuelVote.cast(vote, userId, choice, now, cfg) -> boolean   a player's vote for card `choice`: taken while open (from
--                                                     earlySeconds before opensAt until closesAt) and undecided, for a
--                                                     whole card number, at most once per minIntervalSeconds; true when
--                                                     it moved
--   DuelVote.step(vote, now, rng, cfg) -> boolean   the bots' due votes, then the result endDelaySeconds after the
--                                                     close (its times on the server clock); true when the view changed
--   DuelVote.view(vote) -> Types.MatchVoteView   DuelVote.winner(vote) -> the winning arena id (nil until decided)
--   DuelVote.holdSeconds(count, cfg) -> number    the longest a vote of `count` cards lasts, start to startsAt

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MatchVote = require(script.Parent.MatchVote)

export type Vote = {
	id: string,
	maps: { string },
	arenaIds: { string },
	votes: MatchVote.Order,
	opensAt: number,
	closesAt: number,
	botIds: { number },
	botAt: { number | false }, -- botIds[i] votes then (server time); false = never, or done
	lastVoteAt: { [number]: number },
	result: Types.MatchVoteResultView?,
}

local DuelVote = {}

function DuelVote.new(
	id: string,
	maps: { string },
	arenaIds: { string },
	botIds: { number },
	now: number,
	rng: Random,
	cfg: any
): Vote
	local opensAt = now + cfg.introSeconds
	local vote: Vote = {
		id = id,
		maps = table.clone(maps),
		arenaIds = table.clone(arenaIds),
		votes = {},
		opensAt = opensAt,
		closesAt = opensAt + cfg.seconds,
		botIds = table.clone(botIds),
		botAt = {},
		lastVoteAt = {},
		result = nil,
	}
	for index in maps do
		vote.votes[index] = {}
	end
	for index, at in MatchVote.botTimes(#botIds, cfg.seconds * 1000, rng, cfg) do
		vote.botAt[index] = if at == false then false else opensAt + at / 1000
	end
	return vote
end

function DuelVote.cast(vote: Vote, userId: number, choice: unknown, now: number, cfg: any): boolean
	if vote.result ~= nil or type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > #vote.maps then
		return false -- (NaN and ±inf fail `% 1 ~= 0`)
	end
	if now < vote.opensAt - cfg.earlySeconds or now >= vote.closesAt then
		return false
	end
	local last = vote.lastVoteAt[userId]
	if last ~= nil and now - last < cfg.minIntervalSeconds then
		return false
	end
	vote.lastVoteAt[userId] = now
	return MatchVote.cast(vote.votes, userId, choice)
end

-- The result at `now` (Logic/MatchVote), its times on the server clock (MatchService's Pend.decide).
local function decide(vote: Vote, now: number, rng: Random, cfg: any)
	local r = MatchVote.result(vote.votes, #vote.maps, rng, cfg)
	local roulette: { { choice: number, at: number } } = {}
	for _, step in r.roulette do
		table.insert(roulette, { choice = step.choice, at = now + step.atMs / 1000 })
	end
	local revealAt = now + r.revealMs / 1000
	vote.result = {
		winner = r.winner,
		kind = r.kind,
		roulette = roulette,
		at = now,
		revealAt = revealAt,
		startsAt = revealAt + cfg.startAfterRevealSeconds,
	}
end

function DuelVote.step(vote: Vote, now: number, rng: Random, cfg: any): boolean
	if vote.result ~= nil then
		return false
	end
	local changed = false
	for index, at in vote.botAt do
		if at ~= false and now >= at and now < vote.closesAt then
			vote.botAt[index] = false
			local choice = MatchVote.botPick(vote.votes, #vote.maps, rng, cfg)
			changed = MatchVote.cast(vote.votes, vote.botIds[index], choice) or changed
		end
	end
	local decideAt = vote.closesAt + cfg.endDelaySeconds
	if now >= decideAt then
		decide(vote, decideAt, rng, cfg)
		changed = true
	end
	return changed
end

function DuelVote.view(vote: Vote): Types.MatchVoteView
	local votes: { { number } } = {}
	for index, list in vote.votes do
		votes[index] = table.clone(list)
	end
	return {
		id = vote.id,
		mode = "1v1",
		maps = table.clone(vote.maps),
		opensAt = vote.opensAt,
		closesAt = vote.closesAt,
		votes = votes,
		result = vote.result,
	}
end

function DuelVote.winner(vote: Vote): string?
	local result = vote.result
	return if result then vote.arenaIds[result.winner] else nil
end

-- MatchVote.result's longest roulette: from a random start round `count` tied cards, rouletteExtra + count steps and
-- on until the winner (at most count - 1 more), each step rouletteStepMs + n² x rouletteGrowMs after the last.
function DuelVote.holdSeconds(count: number, cfg: any): number
	local ms = cfg.rouletteFirstMs
	for n = 0, cfg.rouletteExtra + 2 * count - 2 do
		ms += cfg.rouletteStepMs + n * n * cfg.rouletteGrowMs
	end
	local revealMs = math.max(cfg.chosenRevealMs, ms + cfg.rouletteRevealMs)
	return cfg.introSeconds + cfg.seconds + cfg.endDelaySeconds + revealMs / 1000 + cfg.startAfterRevealSeconds
end

return DuelVote
