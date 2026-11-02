--!strict
-- GlobalMatch (server only, pure): who of one mode's shared queue (every lobby server's players, GlobalQueueService)
-- starts a match now. Owner 2026-11-01: "every time you hit queue, it pairs you with people playing the game across all
-- of the servers". Tickets go in arrival order (at, then user id). A 1v1 (size 2) takes pairs; a lone ticket waits (its
-- lobby's practice bot takes it). Team / Free for All (size 12) take a full group at once, else everyone waiting once
-- the oldest has waited gatherSeconds (the match server's bots fill the rest).
--   groups(tickets, now, size, gatherSeconds) -> { { Ticket } }

export type Ticket = { u: number, at: number, h: string } -- user id, os.time() of the join, home lobby JobId

local GlobalMatch = {}

function GlobalMatch.groups(tickets: { Ticket }, now: number, size: number, gatherSeconds: number): { { Ticket } }
	local list = table.clone(tickets)
	table.sort(list, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.u < b.u
	end)
	local groups: { { Ticket } } = {}
	local first = 1
	while #list - first + 1 >= size do
		table.insert(groups, table.move(list, first, first + size - 1, 1, {}))
		first += size
	end
	if size > 2 and first <= #list and now - list[first].at >= gatherSeconds then
		table.insert(groups, table.move(list, first, #list, 1, {}))
	end
	return groups
end

return GlobalMatch
