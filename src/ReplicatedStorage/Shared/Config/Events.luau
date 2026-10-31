--!strict
-- Config.Events (2026-10-31, owner: "can we have all?", "Yes, build it"; LihFolk check: Grow a Garden's shared timer).
-- Shared, data only. The server-wide timed events (Shared/EventSchedule, Server/Services/EventService,
-- Client/Controllers/EventController). An event starts every loopSeconds on the UTC clock (:00, :15, :30, :45), the
-- same in every lobby server, and runs liveSeconds; the countdown shows the rest of the loop. `kinds` take turns in
-- order; golden luck, double coins and the shop restock join later (until then every event is candy rain).
local Events = {
	loopSeconds = 15 * 60, -- owner: "next event is 10 minutes apart" (5 live + 10 waiting)
	liveSeconds = 5 * 60, -- owner: "every event should last i think 5 or 10 minutes" (5 picked with "Yes, build it")
	kinds = { "candyRain", "goldenLuck" },

	-- Golden luck (owner: "1 in 10", "Also a rare Rainbow"): while it is live, a box opened at random (not a fixed
	-- order: PolicyService-restricted accounts keep theirs) gives its squishy Rainbow 1 in 100, else Golden 1 in 10.
	GoldenLuck = {
		rainbowChance = 0.01,
		goldenChance = 0.10,
	},

	-- Candy rain: candy falls around the dragon Monument in Squish Square; the first player within grabRadius of a
	-- landed candy gets it (the server checks); it pays penSeconds of that player's pen Coins a second, at least
	-- minCoins (owner: "10 s of your pen"). perPlayer candies fall for each player in the server over the event (owner:
	-- "got to be enough for everyone in the server"); grabCap per player per event stops a teleporting cheat from
	-- taking them all. A candy nobody grabs goes after lifeSeconds.
	CandyRain = {
		centre = Vector3.new(0, 0, 0), -- Workspace.SquishyDuelsLobby.Hub.Monument
		innerRadius = 20, -- clear of the Monument, its gems and the duel pads
		outerRadius = 68, -- inside the square, before the pens (r 75)
		maxFloorY = 3, -- a landing higher than this is on a prop (a bench, a stall): another spot is tried
		perPlayer = 30,
		grabCap = 60,
		penSeconds = 10,
		minCoins = 100,
		grabRadius = 5,
		lifeSeconds = 20,
		fallSeconds = 1.2, -- the client's drop from dropHeight; the candy can be grabbed once it has landed
		dropHeight = 40,
		size = 3,
	},
}

return table.freeze(Events)
