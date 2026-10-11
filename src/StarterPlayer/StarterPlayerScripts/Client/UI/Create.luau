--!strict
-- Create (client only). DESIGN §11.1: the one UI construction helper (no framework).
--   local frame: Frame = Create("Frame", { Name = "Panel", Size = UDim2.fromScale(1, 1), Parent = gui }, { child })
-- Every property except Parent is set first, then the children are parented to the new instance, then Parent is set
-- last, so a tree is complete before it reaches the PlayerGui (one replication/layout pass, no half-built flashes).
-- Events are never wired here: each screen connects them explicitly into its own Cleanup (§11.1).
-- Text objects should go through UI/Theme (Theme.text) so FontFace and TextSize are always set: new TextButtons
-- default to the Legacy font at size 8 (V).

-- Types

export type Props = { [string]: any }

-- Constants

local PARENT = "Parent"

-- Public

-- Creates `className` with `props` and `children`. Returns `any` so the caller can annotate the concrete class.
local function Create(className: string, props: Props?, children: { Instance }?): any
	local instance = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == PARENT then
				parent = value
			else
				(instance :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

return Create
