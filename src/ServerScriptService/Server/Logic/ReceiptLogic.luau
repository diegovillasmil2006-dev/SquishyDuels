--!strict
-- ReceiptLogic (server only, pure): the developer product receipt decision (DESIGN §3.10). No instances, no yields,
-- no MarketplaceService: MonetizationService looks things up and acts on the decision.
--
-- API:
--   ReceiptLogic.decide(state, profile, pendingIds, info) -> Decision {action}, the first that applies (§3.10 order):
--     "unknownProduct"  state.bundle is nil (no configured bundle has info.ProductId): log, NotProcessedYet
--     "noPlayer"        state.playerPresent is false (the buyer is not in this server): NotProcessedYet
--     "notReady"        no profile, or state.status ~= "ready" (OFFLINE, READONLY, loading): NotProcessedYet
--     "awaitSave"       info.PurchaseId is in profile.receipts AND in pendingIds (granted, not saved yet):
--                       PurchaseGranted only if DataService.saveNowAsync succeeds, else NotProcessedYet
--     "alreadyGranted"  info.PurchaseId is in profile.receipts and not pending (recorded and saved): PurchaseGranted
--     "grant"           otherwise: grant bundle.coins (reason "robux") and push entry(...) in one mutation, mark the id
--                       pending, then PurchaseGranted only after a successful saveNowAsync
--   ReceiptLogic.entry(info, bundle, now) -> ReceiptEntry {id = PurchaseId, product = ProductId, coins, at = now}
--
-- Never assumes CurrencySpent > 0 (AdReward and CommerceProduct channels exist, §3.10): no decision reads it, so a
-- receipt with CurrencySpent = 0 is granted like any other. The idempotency key is receipts.id = PurchaseId (§3.4).

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Types = require(Shared.Types)

-- Types

-- The shape of a Config.Monetization coin bundle (restated: the section module is only read through Config).
export type CoinBundle = { key: string, nameKey: string, productId: number?, coins: number, onSale: boolean }
export type ReceiptEntry = Types.ReceiptEntry

-- The fields of ProcessReceipt's receiptInfo this module reads (Roblox sends more; CurrencySpent is never read).
export type ReceiptInfo = {
	PurchaseId: string,
	ProductId: number,
	PlayerId: number,
	CurrencySpent: number?,
}

export type DecideState = {
	bundle: CoinBundle?, -- Config.Monetization.byProductId[info.ProductId] (or a Studio fixture bundle)
	playerPresent: boolean, -- Players:GetPlayerByUserId(info.PlayerId) ~= nil
	status: string?, -- DataService.getStatus(player): "ready", "offline", "readonly", "loading"
}

-- The profile fields decide reads (a ProfileV1 has them).
export type ReceiptProfile = { receipts: { ReceiptEntry } }

export type Action = "unknownProduct" | "noPlayer" | "notReady" | "alreadyGranted" | "awaitSave" | "grant"
export type Decision = { action: Action }

-- Constants

local READY = "ready"

-- Module table

local ReceiptLogic = {}

-- Private

local function recorded(profile: ReceiptProfile, purchaseId: string): boolean
	local receipts = profile.receipts
	if type(receipts) ~= "table" then
		return false
	end
	for _, receipt in receipts do
		if type(receipt) == "table" and receipt.id == purchaseId then
			return true
		end
	end
	return false
end

-- Public

function ReceiptLogic.decide(
	state: DecideState,
	profile: ReceiptProfile?,
	pendingIds: { [string]: boolean }?,
	info: ReceiptInfo
): Decision
	if state.bundle == nil then
		return { action = "unknownProduct" }
	end
	if not state.playerPresent then
		return { action = "noPlayer" }
	end
	if profile == nil or state.status ~= READY then
		return { action = "notReady" }
	end
	if recorded(profile, info.PurchaseId) then
		if pendingIds ~= nil and pendingIds[info.PurchaseId] == true then
			return { action = "awaitSave" }
		end
		return { action = "alreadyGranted" }
	end
	return { action = "grant" }
end

function ReceiptLogic.entry(info: ReceiptInfo, bundle: CoinBundle, now: number): ReceiptEntry
	return { id = info.PurchaseId, product = info.ProductId, coins = bundle.coins, at = now }
end

return table.freeze(ReceiptLogic)
