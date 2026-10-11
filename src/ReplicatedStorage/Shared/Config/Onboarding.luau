--!strict
-- Config.Onboarding: tutorial tip-card steps (DESIGN §11.8). Shared, data only. Onboarding never pays Coins;
-- the Coin-paying starter tasks are in QuestDefs.luau. Steps can complete in any order; the card shows the lowest
-- incomplete step. Only steps with recordedBy = "client" and skipStepId ("Skip tutorial", Part 7) are accepted from the
-- OnboardingStep remote.

export type Step = {
	id: string,
	textKey: string,
	restrictedTextKey: string?, -- shown instead when paid random boxes are restricted or unknown
	recordedBy: "client" | "server",
	guidance: "none" | "waypointMat" | "waypointBoxStand" | "pulseSquishies" | "waypointPodium",
}

local Onboarding = {
	version = 1, -- ProfileV1.onboarding.v

	Steps = {
		-- Completes when "Got it" is pressed.
		{ id = "welcome", textKey = "onboarding.welcome", recordedBy = "client", guidance = "none" },
		-- First accepted squeeze.
		{ id = "squeeze", textKey = "onboarding.squeeze", recordedBy = "server", guidance = "waypointMat" },
		-- First box opened or first shop purchase. Restricted/unknown players are pointed to the Shop.
		{
			id = "firstBox",
			textKey = "onboarding.firstBox",
			restrictedTextKey = "onboarding.firstBoxShop",
			recordedBy = "server",
			guidance = "waypointBoxStand",
		},
		-- First successful equip of a non-starter squishy.
		{ id = "equip", textKey = "onboarding.equip", recordedBy = "server", guidance = "pulseSquishies" },
		-- Inspect opened. Lobby HUD (spec 2026-10-11): no dock, so the Squishies tile pulses (its list has Inspect).
		{ id = "inspect", textKey = "onboarding.inspect", recordedBy = "client", guidance = "pulseSquishies" },
		-- QueueJoin accepted.
		{ id = "duel", textKey = "onboarding.duel", recordedBy = "server", guidance = "waypointPodium" },
	} :: { Step },

	-- Reading (PROGRESS Part 5 open item; DESIGN gives `onboarding.skipped` no remote): the "Skip tutorial" link sends
	-- OnboardingStep(skipStepId). The server sets onboarding.skipped = true (idempotent, a "soon" save, never Coins).
	-- It is not a Steps id (Config.validate checks both), so it never shows as a card or counts as a done step.
	skipStepId = "skip",

	doneToastKey = "onboarding.done",
	waypointHideStuds = 8, -- the waypoint beam hides within this distance of its target
}

return Onboarding
