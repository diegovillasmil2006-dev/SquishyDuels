--!strict
-- CodeService (server only). Big job item 4 (2026-11-10; the owner: "redeem codes"). LihFolk vault "Codes Redemption
-- System End to End": the list stays on the server (Logic/Codes), typing is forgiven, one use per account, guessers are
-- slowed down, a wrong and a closed code get the same answer, the mark and the grant happen in one step.
-- redeem(p, typed), the CodeRedeem RF, in this order:
--   1. the profile is READY, else data.notReady;
--   2. the player is not locked for wrong guesses (Config.Bonus.Codes: missLimit misses within missWindowSeconds lock
--      for lockSeconds, kept by UserId so a rejoin does not clear it), else code.wait;
--   3. the typed text is a code that is open now (built in, or live from the experience config `codes`), else
--      code.invalid: one answer for a wrong, a badly typed and a closed code, and one miss;
--   4. in one step with nothing yielding: profile.gifts["code:<CODE>"] (the once-per-account flags; a set flag answers
--      code.used and is not a miss), then the Coins: the code's squeezes x the squeeze value now, reason "code";
--   5. a "soon" save (the flag and the Coins are saved together, or lost together); reply ok { coins }.
-- Live codes: SwitchService.value("codes") is read at every redeem, so a code added or closed in Creator Hub > Configs
-- works within about a minute, no publish (names the list skipped are logged once per change).
-- Collaborators are injectable (useDeps) so unit tests run with a fake data port and clock.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Bonus = require(Shared.Config.Bonus)
local Log = require(Shared.Util.Log)
local Codes = require(script.Parent.Parent.Logic.Codes)
local EconomyService = require(script.Parent.EconomyService)
local NetService = require(script.Parent.NetService)
local StateService = require(script.Parent.StateService)
local SwitchService = require(script.Parent.SwitchService)

-- Types

export type Deps = {
	data: StateService.DataPort,
	grantCoins: (player: any, amount: number, reason: string) -> (number, string?),
	liveCodes: () -> any, -- the experience config `codes` as stored (any value, checked by Codes.readLive)
	clock: () -> number, -- os.clock: the wrong-guess lock
}

type Guesses = { misses: { number }, lockedUntil: number }

-- Constants

local RULES = Bonus.Codes
local REMOTE = "CodeRedeem"
local LIVE_KEY = "codes"
local STATUS_READY = "ready"
local COIN_REASON = "code"
local SAVE_SOON = "soon"
local CODE_NOT_READY = "data.notReady"
local CODE_INVALID = "code.invalid"
local CODE_USED = "code.used"
local CODE_WAIT = "code.wait"

-- Module table

local CodeService = {}

-- Private

local log = Log.new("Codes")

local function defaultDeps(): Deps
	return {
		data = StateService.dataPort(),
		grantCoins = function(player: any, amount: number, reason: string): (number, string?)
			return EconomyService.grantCoins(player, amount, reason)
		end,
		liveCodes = function(): any
			return SwitchService.value(LIVE_KEY)
		end,
		clock = os.clock,
	}
end

local deps: Deps = defaultDeps()
local guesses: { [number]: Guesses } = {}
local lastSkipped = ""

local function live(): { [string]: number }
	local list, skipped = Codes.readLive(deps.liveCodes())
	table.sort(skipped)
	local names = table.concat(skipped, ", ")
	if names ~= lastSkipped then
		lastSkipped = names
		if names ~= "" then
			log:warn(`live codes skipped (a name of 3 to 20 letters or digits, a whole number up to {RULES.maxSqueezes}): {names}`)
		end
	end
	return list
end

-- One wrong guess at `now`; locks the player once missLimit of them fall inside the window.
local function miss(userId: number, now: number)
	local record = guesses[userId]
	if record == nil then
		record = { misses = {}, lockedUntil = 0 }
		guesses[userId] = record
	end
	local kept: { number } = {}
	for _, at in record.misses do
		if now - at < RULES.missWindowSeconds then
			table.insert(kept, at)
		end
	end
	table.insert(kept, now)
	if #kept >= RULES.missLimit then
		record.lockedUntil = now + RULES.lockSeconds
		kept = {}
		log:warn(`user {userId}: {RULES.missLimit} wrong codes, locked for {RULES.lockSeconds} s`)
	end
	record.misses = kept
end

-- Public

-- The CodeRedeem RF (see the header). Returns NetService.ok({ coins }) or NetService.err(reason). Never yields.
function CodeService.redeem(player: any, typed: unknown): any
	local data = deps.data
	if data.status(player) ~= STATUS_READY then
		return NetService.err(CODE_NOT_READY)
	end
	local userId: number = player.UserId
	local now = deps.clock()
	local record = guesses[userId]
	if record ~= nil and record.lockedUntil > now then
		return NetService.err(CODE_WAIT)
	end
	local code = Codes.normalize(typed)
	local squeezes = if code then Codes.find(code, live()) else nil
	if code == nil or squeezes == nil then
		miss(userId, now)
		return NetService.err(CODE_INVALID)
	end
	local key = Codes.giftKey(code)
	local ok, fresh = data.mutate(player, function(profile: any): boolean
		local gifts = profile.gifts
		if type(gifts) ~= "table" then
			gifts = {}
			profile.gifts = gifts
		end
		if gifts[key] then
			return false -- used (anything but false or nothing counts as used: never twice)
		end
		gifts[key] = true
		return true
	end)
	if not ok then
		return NetService.err(CODE_NOT_READY) -- the session stopped taking changes (its final save started)
	elseif fresh ~= true then
		return NetService.err(CODE_USED)
	end
	local amount = EconomyService.rewardCoins(data.getProfile(player), squeezes)
	local coins, failure = deps.grantCoins(player, amount, COIN_REASON)
	if failure ~= nil then
		log:error(`user {userId}: the Coins of code {code} were not granted ({failure})`)
	end
	data.requestSave(player, SAVE_SOON)
	log:info(`user {userId} redeemed {code}: {coins} Coins`)
	return NetService.ok({ coins = coins })
end

-- Tests: other dependencies (nil = the real ones) and no guesses remembered.
function CodeService.useDeps(overrides: { [string]: any }?)
	local fresh: any = defaultDeps()
	for key, value in overrides or {} do
		fresh[key] = value
	end
	deps = fresh
	guesses = {}
	lastSkipped = ""
end

-- Lifecycle

function CodeService.init()
	NetService.onInvoke(REMOTE, function(player: Player, typed: unknown): any
		return CodeService.redeem(player, typed)
	end)
end

function CodeService.playerRemoving(player: Player)
	local record = guesses[player.UserId]
	if record ~= nil and record.lockedUntil <= deps.clock() then
		guesses[player.UserId] = nil -- a running lock stays, so a rejoin does not clear it
	end
end

return CodeService
