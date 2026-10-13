--!strict
-- ConfirmButton (client only). DESIGN §11.5 (inline two-step spend confirmation, one pattern for boxes, the shop and
-- the capsules), §11.1 (UI/Components: ConfirmButton), §11.3 (Locked: disabled + reason), §9.13 / §18.5.2 B3 (the
-- Button press feel, sounds and the "no" wiggle all come from Button, unchanged).
--   local confirm = ConfirmButton.new({ name = "Shop_BuyButton", text = Strings.shop.buy, price = 1200, balance = 3000,
--       onConfirm = function() confirm:setLoading(true); ...; confirm:setLoading(false) end, parent = column })
--   confirm:setPrice(price, balance)   -- after a Coins or price change (a change of price while armed disarms it)
--   confirm:setDisabled(reasonText)    -- disabled by the caller with that reason ("" = no reason line); nil = enabled
--   confirm:setLoading(true / false)   -- the 3-dot spinner, not activatable (the caller sets it in onConfirm)
--   confirm:reset() / confirm:setText(text?) / confirm:destroy()
-- Behaviour (§11.5): the first press turns the button into "Confirm: {price} Coins" (spend.confirm) for
-- Config.UI.confirmSeconds (3 s) with "Balance after: {balance}" (spend.balanceAfter) under it; a second press inside
-- that window calls onConfirm; otherwise it reverts to its idle text. Not enough Coins -> disabled with the missing
-- amount (common.needCoins, or spec.needText(missing), e.g. the box panel's BoxFormat.needCoinsText). The component
-- never decides a price, a balance or an outcome: the caller passes the Config price and StateController's Coins, and
-- the server checks everything again (§6.1, §12).
-- Readings (DESIGN is silent):
-- * The state machine is the pure ConfirmButton.step(state, event, now, cfg) (unit-tested), and ConfirmButton.view(state)
--   turns a state into what the button shows. Priority: loading > disabled by the caller > not enough Coins > armed.
-- * A second press within GUARD_SECONDS (0.3 s) of the first is ignored, so an accidental double click or double tap
--   never spends Coins; a press after the window has passed (before the revert timer ran) arms again.
-- * A price change while armed disarms it (the player confirms the price they read); a balance change keeps it armed
--   while it still covers the price (the "Balance after" line follows), else it disarms.
-- * A confirm returns the button to idle; it does not enter loading by itself. The caller calls setLoading(true) in
--   onConfirm before it yields and setLoading(false) (or reset()) afterwards, so a caller that forgets can never leave
--   the button stuck in loading. reset() clears an arm and loading and keeps the price, balance and setDisabled reason.
-- * root is a transparent holder (the Button above the "Balance after" line); `button` is the Button itself (its
--   .root is the TextButton to focus, named spec.name). The idle label is spec.text, else "{price} Coins"
--   (common.coinsAmount). Amounts use Format.coins.
-- Part 8: confirm:setWidth(px?) gives the holder, the Button and the "Balance after" line a fixed width (the texts wrap
-- inside it; nil = automatic again), for a narrow column at a large text size (the shop's pinned Buy). SUB_GAP is the
-- gap above the "Balance after" line (base px).
-- Foam UI (spec 2026-10-09): the Button is a foam button (spec.accent picks its face); the "Balance after" line is
-- InkUI on the panel.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Cleanup = require(Shared.Util.Cleanup)
local Config = require(Shared.Config)
local Format = require(Shared.Util.Format)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local Button = require(script.Parent.Button)
local Create = require(UI.Create)
local Theme = require(UI.Theme)

-- Types

export type Phase = "idle" | "armed" | "loading"

export type State = {
	phase: Phase,
	price: number, -- whole Coins, >= 0
	balance: number, -- whole Coins, >= 0
	armedAt: number?, -- the clock time of the arming press (phase "armed" only)
	blocked: string?, -- the caller's disabled reason ("" = disabled with no reason line); nil = not disabled
}

-- press | tick | price (price, balance) | disable (reason) | enable | loading (on) | reset
export type EventKind = "press" | "tick" | "price" | "disable" | "enable" | "loading" | "reset"
export type Event = { kind: EventKind, price: number?, balance: number?, reason: string?, on: boolean? }

-- What a step did: arm (now waiting for the second press), confirm (call onConfirm), revert (back to idle without a
-- confirm), denied (a press while disabled), ignored (a press that changes nothing: loading or the double-click guard).
export type Action = "arm" | "confirm" | "revert" | "denied" | "ignored"

export type StepConfig = { confirmSeconds: number, guardSeconds: number? }

export type Mode = "idle" | "armed" | "needCoins" | "blocked" | "loading"

export type View = {
	mode: Mode,
	buttonState: Button.State,
	missing: number, -- Coins still missing (0 when the balance covers the price)
	balanceAfter: number, -- balance - price, never below 0
	confirmText: string?, -- spend.confirm while armed
	balanceText: string?, -- spend.balanceAfter while armed
	needText: string?, -- common.needCoins while the Coins do not cover the price
	reason: string?, -- the disabled reason shown under the label (blocked or needCoins)
}

export type Spec = {
	name: string, -- the Button's stable test name (`<Screen>_<Action>Button`, §2.11)
	price: number,
	balance: number,
	onConfirm: () -> (), -- runs on the confirming press (inside Button's own thread; may yield)
	text: string?, -- the idle label; nil = "{price} Coins"
	kind: Button.Kind?, -- default "primary" (a spend is the screen's main action)
	accent: Theme.AccentName?, -- the foam face (default the kind's; foam UI restyle)
	width: number?, -- base px; nil = automatic width
	height: number?, -- base px (raised to the touch minimum by Button)
	textKind: Theme.TextKind?,
	needText: ((missing: number) -> string)?, -- the not-enough-Coins reason; nil = common.needCoins
	layoutOrder: number?,
	parent: Instance?,
}

export type ConfirmButton = {
	root: Frame,
	button: Button.Button,
	setPrice: (self: ConfirmButton, price: number, balance: number) -> (),
	setDisabled: (self: ConfirmButton, reason: (string | boolean)?) -> (),
	setLoading: (self: ConfirmButton, on: boolean) -> (),
	setText: (self: ConfirmButton, text: string?) -> (),
	setWidth: (self: ConfirmButton, widthPx: number?) -> (),
	reset: (self: ConfirmButton) -> (),
	getState: (self: ConfirmButton) -> State,
	getView: (self: ConfirmButton) -> View,
	destroy: (self: ConfirmButton) -> (),
}

-- Constants

-- Reading: a second press this soon after the first is an accidental double click / tap, never a confirm.
local GUARD_SECONDS = 0.3
local SUB_GAP = 2
local MIN_RECHECK_SECONDS = 0.05 -- a revert timer that woke early checks again after at least this long

-- Module table

local ConfirmButton = {}

ConfirmButton.GUARD_SECONDS = GUARD_SECONDS
ConfirmButton.SUB_GAP = SUB_GAP

-- Private

-- A whole, finite, non-negative Coin amount (anything else counts as 0).
local function coins(value: unknown): number
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.max(0, math.floor(value))
end

local function copy(state: State): State
	return {
		phase = state.phase,
		price = state.price,
		balance = state.balance,
		armedAt = state.armedAt,
		blocked = state.blocked,
	}
end

local function defaultConfig(): StepConfig
	return { confirmSeconds = Config.UI.confirmSeconds, guardSeconds = GUARD_SECONDS }
end

local function missingOf(state: State): number
	return math.max(0, state.price - state.balance)
end

local function disarm(state: State)
	state.phase = "idle"
	state.armedAt = nil
end

-- Public: pure state machine (unit-tested) ----------------------------------------------------------------------------

-- A fresh idle state for a price and a balance.
function ConfirmButton.initial(price: number, balance: number): State
	return { phase = "idle", price = coins(price), balance = coins(balance), armedAt = nil, blocked = nil }
end

-- One step of the two-step confirm. `now` is a clock in seconds (os.clock() in the component); `cfg` defaults to
-- Config.UI.confirmSeconds and the double-click guard. Returns the new state (a copy; the input is never changed)
-- and what the step did (nil when nothing happened, e.g. a tick that is not due).
function ConfirmButton.step(state: State, event: Event, now: number, cfg: StepConfig?): (State, Action?)
	local c = cfg or defaultConfig()
	local window = c.confirmSeconds
	local guard = c.guardSeconds or 0
	local s = copy(state)
	local kind = event.kind
	local action: Action? = nil

	if kind == "press" then
		local armedAt = s.armedAt
		local elapsed = if s.phase == "armed" and armedAt ~= nil then now - armedAt else nil
		local denied = s.blocked ~= nil or missingOf(s) > 0
		if s.phase == "loading" or (not denied and elapsed ~= nil and elapsed < guard) then
			action = "ignored" -- loading, or the double-click guard
		elseif denied then
			disarm(s)
			action = "denied"
		elseif elapsed ~= nil and elapsed < window then
			disarm(s)
			action = "confirm"
		else
			-- Idle, or armed with the window already over (the revert timer has not run yet): arm (again).
			s.phase = "armed"
			s.armedAt = now
			action = "arm"
		end
	elseif kind == "tick" then
		local armedAt = s.armedAt
		if s.phase == "armed" and armedAt ~= nil and now - armedAt >= window then
			disarm(s)
			action = "revert"
		end
	elseif kind == "price" then
		local newPrice = coins(event.price)
		s.balance = coins(event.balance)
		local priceChanged = newPrice ~= s.price
		s.price = newPrice
		if s.phase == "armed" and (priceChanged or missingOf(s) > 0) then
			disarm(s)
			action = "revert"
		end
	elseif kind == "disable" then
		s.blocked = if type(event.reason) == "string" then event.reason else ""
		if s.phase == "armed" then
			disarm(s)
			action = "revert"
		end
	elseif kind == "enable" then
		s.blocked = nil
	elseif kind == "loading" then
		if event.on == true then
			s.phase = "loading"
			s.armedAt = nil
		elseif s.phase == "loading" then
			s.phase = "idle"
		end
	elseif kind == "reset" then
		if s.phase == "armed" then
			action = "revert"
		end
		disarm(s)
	end
	return s, action
end

-- What a state shows: the mode, the Button state, the missing Coins, the balance after a confirm and the texts
-- (spend.confirm / spend.balanceAfter while armed, common.needCoins while the Coins are short).
function ConfirmButton.view(state: State): View
	local missing = missingOf(state)
	local after = math.max(0, state.balance - state.price)
	local needText = if missing > 0
		then Strings.format(
			Strings.plural(missing, Strings.common.needCoins.one, Strings.common.needCoins.many),
			{ missing = Format.coins(missing) }
		)
		else nil
	local view: View = {
		mode = "idle",
		buttonState = "normal",
		missing = missing,
		balanceAfter = after,
		needText = needText,
	}
	if state.phase == "loading" then
		view.mode = "loading"
		view.buttonState = "loading"
	elseif state.blocked ~= nil then
		view.mode = "blocked"
		view.buttonState = "disabled"
		view.reason = if state.blocked ~= "" then state.blocked else nil
	elseif missing > 0 then
		view.mode = "needCoins"
		view.buttonState = "disabled"
		view.reason = needText
	elseif state.phase == "armed" then
		view.mode = "armed"
		view.confirmText = Strings.format(Strings.spend.confirm, { price = Format.coins(state.price) })
		view.balanceText = Strings.format(Strings.spend.balanceAfter, { balance = Format.coins(after) })
	end
	return view
end

-- Public: component ----------------------------------------------------------------------------------------------------

function ConfirmButton.new(spec: Spec): ConfirmButton
	local cleanup = Cleanup.new()
	local state = ConfirmButton.initial(spec.price, spec.balance)
	local idleText: string? = spec.text
	local revertToken = 0
	local button: Button.Button
	local subLabel: TextLabel

	local root: Frame = Create("Frame", {
		Name = spec.name .. "Holder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(spec.width or 0, 0),
		AutomaticSize = if spec.width then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY,
		LayoutOrder = spec.layoutOrder or 0,
	})
	cleanup:add(root)
	Theme.list(Enum.FillDirection.Vertical, SUB_GAP, root, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Top)

	local function label(): string
		local text = idleText
		if text ~= nil then
			return text
		end
		return Strings.format(Strings.common.coinsAmount, { coins = Format.coins(state.price) })
	end

	-- What the Button shows now; it is only touched when that changes (a refresh on every StateDelta must not restart
	-- the spinner or the press feel).
	local shownText: string? = nil
	local shownState: Button.State? = nil
	local shownReason: string? = nil

	local function apply()
		local view = ConfirmButton.view(state)
		local text = if view.mode == "armed" then view.confirmText or label() else label()
		if text ~= shownText then
			shownText = text
			button:setText(text)
		end
		local reason = view.reason
		if view.mode == "needCoins" and spec.needText then
			reason = spec.needText(view.missing)
		end
		if view.buttonState ~= shownState or reason ~= shownReason then
			shownState, shownReason = view.buttonState, reason
			button:setState(view.buttonState, reason)
		end
		local sub = if view.mode == "armed" then view.balanceText else nil
		subLabel.Text = sub or ""
		subLabel.Visible = sub ~= nil
	end

	local function run(event: Event): Action?
		local newState, action = ConfirmButton.step(state, event, os.clock())
		state = newState
		apply()
		return action :: Action?
	end

	-- The revert timer of the current arm (a newer arm, a confirm, loading or reset cancel it through the token). A
	-- timer that wakes a little early waits out the rest, so an arm never stays up.
	local function scheduleRevert(delaySeconds: number?)
		if delaySeconds == nil then
			revertToken += 1
		end
		local token = revertToken
		task.delay(delaySeconds or Config.UI.confirmSeconds, function()
			if token ~= revertToken then
				return
			end
			run({ kind = "tick" })
			local armedAt = state.armedAt
			if state.phase == "armed" and armedAt ~= nil and token == revertToken then
				scheduleRevert(math.max(MIN_RECHECK_SECONDS, Config.UI.confirmSeconds - (os.clock() - armedAt)))
			end
		end)
	end
	cleanup:add(function()
		revertToken += 1
	end)

	button = Button.new({
		name = spec.name,
		text = label(),
		kind = spec.kind or "primary",
		accent = spec.accent,
		width = spec.width,
		height = spec.height,
		textKind = spec.textKind,
		layoutOrder = 1,
		parent = root,
		onActivated = function()
			local action = run({ kind = "press" })
			if action == "arm" then
				scheduleRevert()
			elseif action == "confirm" then
				revertToken += 1
				spec.onConfirm()
			end
		end,
	})
	cleanup:add(button)

	subLabel = Theme.label({
		Name = "BalanceAfter",
		Text = "",
		Visible = false,
		LayoutOrder = 2,
		Size = UDim2.fromScale(if spec.width then 1 else 0, 0),
		AutomaticSize = if spec.width then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = root,
	}, "Small", Enum.FontWeight.Bold)

	apply()
	if spec.parent then
		root.Parent = spec.parent
	end

	local self = {} :: ConfirmButton
	self.root = root
	self.button = button

	function self.setPrice(_: ConfirmButton, price: number, balance: number)
		run({ kind = "price", price = price, balance = balance })
	end

	function self.setDisabled(_: ConfirmButton, reason: (string | boolean)?)
		if reason == nil or reason == false then
			run({ kind = "enable" })
		else
			run({ kind = "disable", reason = if type(reason) == "string" then reason else nil })
		end
	end

	function self.setLoading(_: ConfirmButton, on: boolean)
		if on == true then
			revertToken += 1 -- loading clears an arm; setLoading(false) on an armed button must keep its revert timer
		end
		run({ kind = "loading", on = on == true })
	end

	function self.setText(_: ConfirmButton, text: string?)
		idleText = text
		apply()
	end

	function self.setWidth(_: ConfirmButton, widthPx: number?)
		local fixed = widthPx ~= nil
		button:setWidth(widthPx)
		root.Size = UDim2.fromOffset(widthPx or 0, 0)
		root.AutomaticSize = if fixed then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY
		subLabel.Size = UDim2.fromScale(if fixed then 1 else 0, 0)
		subLabel.AutomaticSize = if fixed then Enum.AutomaticSize.Y else Enum.AutomaticSize.XY
	end

	function self.reset(_: ConfirmButton)
		revertToken += 1
		run({ kind = "reset" })
	end

	function self.getState(_: ConfirmButton): State
		return copy(state)
	end

	function self.getView(_: ConfirmButton): View
		return ConfirmButton.view(state)
	end

	function self.destroy(_: ConfirmButton)
		cleanup:clean()
	end

	return self
end

return ConfirmButton
