--!strict
-- Config.Data: store selection, autosave, session lock, retries and log caps (DESIGN §3.1, §3.6, §3.9, §3.14).
-- Shared, data only. All [P] except the Roblox error-code classes.
-- Guard (§3.1): in Studio the selected store name must end in "_STUDIO" (checked at boot and by Config.validate()).

local Data = {
	storeName = "PlayerData_v1", -- live servers; key keyPrefix .. userId, no scope
	studioStoreName = "PlayerData_v1_STUDIO", -- Studio with studioMode = "datastore"
	studioMode = "memory" :: "memory" | "datastore", -- Studio default: InMemoryAdapter (persisted = false)
	keyPrefix = "User_",

	autosaveInterval = 120, -- seconds; the first autosave is at a random 0..autosaveInterval offset
	autosaveBudgetFloor = 10, -- StandardWrite / StandardRead budget below this delays the autosave ...
	autosaveBudgetRetrySeconds = 15, -- ... by this many seconds
	saveSoonDelay = 6, -- "soon" saves run at max(now + saveSoonDelay, lastWriteAt + minWriteGap)
	minWriteGap = 6,

	lockStaleAfter = 300, -- a foreign lock older than this is taken over (logged)
	lockWaitMax = 45, -- wait this long for a fresh foreign lock, then OFFLINE
	lockPoll = 6, -- seconds between lock retries while waiting ...
	lockPollJitter = 2, -- ... ± this

	retryAttempts = 5, -- per request
	retryCap = 16, -- delay min(retryCap, 2^(n-1)) * (1 + random() * retryJitter) s; throttle codes double it
	retryJitter = 0.5,
	offlineRetry = 60, -- OFFLINE sessions retry the load every offlineRetry seconds ...
	offlineRetryCount = 5, -- ... this many times
	closeDeadline = 25, -- BindToClose release deadline (Roblox allows 30 s)

	-- samePair = opponents in the same-pair record (§6.7; each keeps at most Economy.DuelRewards.samePairFullRewards
	-- times). Reading: DESIGN gives no number; times older than the rolling hour are dropped on every duel result, so
	-- even ~105 results an hour stay below 128 opponents. Over the cap, the opponents last met longest ago go first.
	caps = { boxLog = 50, shopLog = 20, receipts = 100, duelLog = 30, samePair = 128 },

	-- §3.5 size budget: a maximal profile (every cap full) must encode with HttpService:JSONEncode below this many
	-- characters (the Part 5 size test). The DataStore limit is 4,194,304.
	profileSizeLimitBytes = 100_000,
	-- §17.9 #6 sanitize: a saved timer `at` (squeezeLimit, grip.rested, grip.afk) that is not finite or lies more than
	-- this many seconds after now becomes now.
	timestampSkewSeconds = 300,

	-- DataStore error classes (§3.6). Any code not listed here (404, 501-505, unknown) is retried.
	ErrorCodes = {
		throttle = { 301, 302, 303, 304, 305, 306 }, -- retried with a doubled delay
		notRetried = { 101, 102, 103, 104, 105, 106, 107, 403, 509, 511, 512, 513 }, -- logged as errors
		shutdown = { 401, 402 }, -- stop all work
	},

	-- ProfileV1.settings defaults (§3.2, §11.6). music / sfx are integers in [settingsMin, settingsMax].
	DefaultSettings = {
		music = 40,
		sfx = 70,
		cameraShake = true,
		showTips = true,
	},
	settingsMin = 0,
	settingsMax = 100,
}

return Data
