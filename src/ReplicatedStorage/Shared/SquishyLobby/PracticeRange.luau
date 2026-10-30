-- PracticeRange: scoring for the practice arena (server).
-- Your weapon/duel code calls PracticeRange.registerHit(lobby, player, hitPart, hitPosition) when a shot lands.
-- Ring scoring uses the distance from the target's bullseye (Markers.Bull). A hit within ComboWindow of the
-- previous one raises the combo multiplier (max 5). The first hit starts a RoundTime-second round.
local HubFX = require(script.Parent.HubFX) -- @require
local Labels = require(script.Parent.Labels) -- @require

local PracticeRange = {}
PracticeRange.Rings = { -- { max distance (studs, full-size target), points, callout }
	{ 0.45, 100, "BULLSEYE!" }, { 0.95, 50, "GREAT" }, { 1.55, 25, "NICE" }, { 2.15, 15, "" }, { 2.75, 10, "" }, { math.huge, 5, "" },
}
PracticeRange.DummyPoints = 25
PracticeRange.ComboWindow = 1.6
PracticeRange.MaxCombo = 5
PracticeRange.RoundTime = 30
PracticeRange.Best = { name = nil, score = 0 }

-- The target/dummy Model a part belongs to (works for the wheel targets too), or nil.
function PracticeRange.getTarget(lobby, part)
	local arena = lobby:FindFirstChild("PracticeArena")
	local m = part
	while m and m ~= arena do
		if m:IsA("Model") and (string.match(m.Name, "^Target_") or string.match(m.Name, "^Dummy_")) then return m end
		m = m.Parent
	end
	return nil
end

-- Nearest animated model at or above `m` (has a Pivot part).
local function animatedAncestor(lobby, m)
	while m and m ~= lobby do
		if m:FindFirstChild("Pivot") then return m end
		m = m.Parent
	end
	return nil
end

-- Where the bullseye is right now. Targets move on the clients only; this replays the same motion.
function PracticeRange.getBullPosition(lobby, target)
	local bull = target:FindFirstChild("Markers") and target.Markers:FindFirstChild("Bull")
	if not bull then return nil end
	local a = animatedAncestor(lobby, target)
	if not a then return bull.Position end
	local now = HubFX.cframeAt(lobby, a, HubFX.now())
	return (now * a.Pivot.CFrame:ToObjectSpace(bull.CFrame)).Position
end

function PracticeRange.scoreFor(lobby, target, hitPosition)
	if string.match(target.Name, "^Dummy_") then return PracticeRange.DummyPoints, "SQUISH!" end
	local bull = PracticeRange.getBullPosition(lobby, target)
	if not bull or not hitPosition then return 10, "" end
	local scale = string.match(target.Name, "^Target_W") and 0.72 or 1
	local d = (hitPosition - bull).Magnitude / scale
	for _, r in PracticeRange.Rings do if d <= r[1] then return r[2], r[3] end end
	return 5, ""
end

local function updateBoard(lobby, player)
	local arena = lobby.PracticeArena
	Labels.setText(arena:FindFirstChild("Label_PracticeScore"), player.DisplayName .. "  " .. (player:GetAttribute("PracticeScore") or 0))
	local b = PracticeRange.Best
	if b.name then Labels.setText(arena:FindFirstChild("Label_PracticeBest"), "BEST " .. b.name .. " " .. b.score) end
end

function PracticeRange.endRound(lobby, player)
	if not player:GetAttribute("PracticeRoundEnds") then return end
	player:SetAttribute("PracticeRoundEnds", nil)
	local score = player:GetAttribute("PracticeScore") or 0
	if score > PracticeRange.Best.score then PracticeRange.Best = { name = player.DisplayName, score = score } end
	player:SetAttribute("PracticeLastRound", score)
	updateBoard(lobby, player)
end

-- Returns points awarded (0 if ignored), callout text, combo.
function PracticeRange.registerHit(lobby, player, part, hitPosition)
	local target = PracticeRange.getTarget(lobby, part)
	if not target then return 0, "", 0 end
	local now = HubFX.now()
	local last = target:GetAttribute("HitAt")
	if last and now - last < 0.25 then return 0, "", 0 end
	target:SetAttribute("HitAt", now) -- clients play the spin + burst

	local ends = player:GetAttribute("PracticeRoundEnds")
	if not ends or now > ends then
		if ends then PracticeRange.endRound(lobby, player) end
		player:SetAttribute("PracticeScore", 0)
		player:SetAttribute("PracticeRoundEnds", now + PracticeRange.RoundTime)
		task.delay(PracticeRange.RoundTime, function() if player.Parent then PracticeRange.endRound(lobby, player) end end)
	end
	local lastHit = player:GetAttribute("PracticeLastHit") or -1e9
	local combo = (now - lastHit < PracticeRange.ComboWindow) and math.min(PracticeRange.MaxCombo, (player:GetAttribute("PracticeCombo") or 1) + 1) or 1
	player:SetAttribute("PracticeCombo", combo)
	player:SetAttribute("PracticeLastHit", now)

	local pts, callout = PracticeRange.scoreFor(lobby, target, hitPosition)
	local total = pts * combo
	player:SetAttribute("PracticeScore", (player:GetAttribute("PracticeScore") or 0) + total)
	updateBoard(lobby, player)
	return total, callout, combo
end

function PracticeRange.resetScore(player)
	player:SetAttribute("PracticeScore", 0)
	player:SetAttribute("PracticeCombo", 0)
	player:SetAttribute("PracticeRoundEnds", nil)
end

return PracticeRange
