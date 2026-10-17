--!strict
-- Config.Onboarding: tutorial tip-card steps (DESIGN §11.8). Shared, data only. Onboarding never pays Coins;
-- the Coin-paying starter tasks are in QuestDefs.luau. Steps can complete in any order; the card shows the lowest
-- incomplete step. Only steps with recordedBy = "client" and skipStepId ("Skip tutorial", Part 7) are accepted from the
-- OnboardingStep remote.

export type Step = {
	id: string,
	textKey: string,
	recordedBy: "client" | "server",
	guidance: "none" | "waypointMat" | "waypointShop" | "pulseSquishies" | "waypointPodium",
}

local Onboarding = {
	version = 1, -- ProfileV1.onboarding.v

	Steps = {
		-- Completes when "Got it" is pressed.
		{ id = "welcome", textKey = "onboarding.welcome", recordedBy = "client", guidance = "none" },
		-- First accepted squeeze.
		{ id = "squeeze", textKey = "onboarding.squeeze", recordedBy = "server", guidance = "waypointMat" },
		-- Pens3 phase 1: the first pen spot bought at the sign (replaces Batch 1's capsule step; an old save keeps its
		-- done.capsule, which nothing reads). A new player spawns facing their own pen, so no waypoint.
		{ id = "pen", textKey = "onboarding.pen", recordedBy = "server", guidance = "none" },
		-- Inspect opened. Lobby HUD (spec 2026-10-11): no dock, so the Squishies tile pulses (its list has Inspect).
		{ id = "inspect", textKey = "onboarding.inspect", recordedBy = "client", guidance = "pulseSquishies" },
		-- QueueJoin accepted.
		{ id = "duel", textKey = "onboarding.duel", recordedBy = "server", guidance = "waypointPodium" },
		-- First box opened or first shop purchase. Batch 1 (review #1): last, so no long goal hides the duel card, and
		-- everyone is pointed to the Shop and its cheapest squishy (a 10,000 Common), never the 150,000 Snack Box.
		{ id = "firstBox", textKey = "onboarding.firstBox", recordedBy = "server", guidance = "waypointShop" },
	} :: { Step },

	-- Reading (PROGRESS Part 5 open item; DESIGN gives `onboarding.skipped` no remote): the "Skip tutorial" link sends
	-- OnboardingStep(skipStepId). The server sets onboarding.skipped = true (idempotent, a "soon" save, never Coins).
	-- It is not a Steps id (Config.validate checks both), so it never shows as a card or counts as a done step.
	skipStepId = "skip",

	doneToastKey = "onboarding.done",
	waypointHideStuds = 8, -- the waypoint beam hides within this distance of its target
}

return Onboarding
