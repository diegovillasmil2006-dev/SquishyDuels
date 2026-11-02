--!strict
-- Config/VoteCards: the sky maps' map vote cards (2026-11-01, owner: "implement the thumbnails for each map"). Each is
-- Diego's Duel demo PICK A MAP card (img.vote.card.<Model> with his photo a, img.vote.cardB.<Model> with photo b), and
-- photo b fades in and out over photo a like his sq-xfade (12 s ease-in-out, each card 1.7 s ahead of the one before;
-- 0-42 % hidden, 50-92 % shown). Shared, data only. A child module required directly by UI/MatchVoteBoard:
-- Config/UI.luau is at Roblox's 200,000-character Source limit.

local VoteCards = {
	photoFadeS = 12,
	photoFadeStepS = 1.7,
	photoFadeCurve = "easeInOut",
	photoFade = {
		{ at = 0, alpha = 0 },
		{ at = 0.42, alpha = 0 },
		{ at = 0.5, alpha = 1 },
		{ at = 0.92, alpha = 1 },
		{ at = 1, alpha = 0 },
	},
}

return VoteCards
