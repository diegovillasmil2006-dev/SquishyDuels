-- Labels: text plaques (OPEN PLOT, SHOP, QUESTS ...) as SurfaceGuis on "Label_*" parts.
local Theme = require(script.Parent.Theme) -- @require

local Labels = {}

function Labels.build(part, spec)
	spec = spec or Theme.Labels[part.Name]
	if not spec then return nil end
	local old = part:FindFirstChild("LabelGui")
	if old then old:Destroy() end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "LabelGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Brightness = 1
	gui.Parent = part
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BorderSizePixel = 0
	bg.BackgroundColor3 = spec.bg
	bg.Parent = gui
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.BackgroundTransparency = 1
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = UDim2.fromScale(0.5, 0.52)
	t.Size = UDim2.fromScale(0.88, 1)
	t.FontFace = Theme.Font
	t.Text = spec.text
	t.TextColor3 = spec.fg
	t.TextScaled = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = math.min(100, math.floor(part.Size.Y * 50 * spec.size))
	c.Parent = t
	t.Parent = bg
	return t
end

function Labels.setText(part, text)
	local gui = part and part:FindFirstChild("LabelGui")
	local t = gui and gui:FindFirstChild("Text", true)
	if t then t.Text = text end
end

function Labels.buildAll(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and Theme.Labels[d.Name] then
			Labels.build(d)
		end
	end
end

return Labels
