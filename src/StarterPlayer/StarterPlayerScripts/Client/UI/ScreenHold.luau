--!strict
-- ScreenHold (client only). P13v4 (owner 2026-10-19, the TikTok throw; the creator's note "hide everything for the
-- whole launch"; work/pens3/p13v4/SPEC.md 4.4): hides the game's other screens while the own throw flies, with no
-- edits to their owners (Diego's HUD included).
--   local hold = ScreenHold.new(playerGui, { SD_Highway = true })   -- the guis that stay
--   hold:step()      every frame of the launch: each enabled direct ScreenGui child named "SD_..." that is not kept is
--                    turned off and remembered (also one its owner turned back on meanwhile)
--   hold:release()   turns back on each remembered gui that is still off (idempotent; steps after it do nothing)
-- Roblox's own guis (TouchGui, chat: no "SD_" prefix) are never touched.
-- shortcut: an owner that switches its gui off during a launch gets it back on at release; owners refresh on their next
-- change.

-- Types

export type Hold = {
	step: (self: Hold) -> (),
	release: (self: Hold) -> (),
}

-- Constants

local PREFIX = "SD_"

-- Module table

local ScreenHold = {}

function ScreenHold.new(container: Instance, keep: { [string]: boolean }): Hold
	local hidden: { [ScreenGui]: boolean } = {}
	local released = false
	local hold = {} :: Hold

	function hold.step(_: Hold)
		if released then
			return
		end
		for _, child in container:GetChildren() do
			if child:IsA("ScreenGui") and child.Enabled and string.sub(child.Name, 1, #PREFIX) == PREFIX then
				if not keep[child.Name] then
					child.Enabled = false
					hidden[child] = true
				end
			end
		end
	end

	function hold.release(_: Hold)
		if released then
			return
		end
		released = true
		for gui in hidden do
			if not gui.Enabled then
				gui.Enabled = true
			end
		end
		table.clear(hidden)
	end

	return hold
end

return ScreenHold
