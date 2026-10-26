--!strict
-- StormBar (client only). Storm fix (owner 2026-10-26: the storm "insta kills, there should be like a bar of health that
-- appears when you are in the storm and it should slowly kill you"; Diego's designs have no storm, so its look is the
-- RESPAWNING bar's in the storm card's purple [P]): a MatchHudController piece ("storm"). While you stand in the TDM
-- storm (MatchHudFormat.stormShows, your root from ctx.position) it shows the IN THE STORM! bar, its fill = the health
-- the storm leaves you (1 - your storm bar, eased toward each server value at Config.UI.Match.storm.easeRate), and a
-- purple tint (Palette.MatchStormTint as a ColorCorrectionEffect in Lighting, client only, this piece's own) faded in
-- over tintMs. Both go at once when you step back into the safe circle or are knocked out (the RESPAWNING bar then).
-- Place: centred at the bottom, over the desktop ability bar (MatchHudFormat.dockClear), never on a touch area
-- (MatchHudFormat.barPlace with all of them: you are alive, so the touch buttons work). Killcam step 2 (2026-10-26):
-- only while the match is live (Diego's end clears the HUD, S:729).

-- Services

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Palette = require(Shared.Art.Palette)
local Strings = require(Shared.Strings)

local UI = script.Parent.Parent
local MatchHudFormat = require(UI.MatchHudFormat)
local Tweens = require(UI.Parent.Anim.Tweens)
local MatchKit = require(script.Parent.MatchKit)

-- Constants

local CFG = Config.UI.Match.storm
local BAR = Config.UI.Match.respawn -- the same bar: sizes, motion and places
local STORM = Config.Match.Storm
local FADE_MS = Config.UI.motion.reducedMotionMaxFadeMs
local Z = 4 -- as the RESPAWNING bar (they never show together)
local LIVE: { [string]: boolean } = { Active = true, Overtime = true }
local TINT_NAME = "SD_MatchStorm"
local WHITE = Color3.new(1, 1, 1)

-- Module table

local StormBar = {}

-- Public

function StormBar.new(ctx: MatchHudFormat.Context): MatchHudFormat.Piece
	local made = MatchKit.statusBar(ctx.root, BAR, {
		name = "MatchStorm",
		label = Strings.matchHud.storm.label,
		top = Palette.StickerPurpleBarTop, -- the storm card's purple (DeathCard)
		faceEnd = Palette.StickerPurpleBarEnd,
		z = Z,
	})
	local poser = Tweens.poser(made.pose)
	local innerWidth = BAR.width - 2 * BAR.bar.border
	local tint: ColorCorrectionEffect? = nil
	local since: number? = nil -- os.clock() the bar came in (nil: hidden)
	local last = 0 -- os.clock() of the last shown frame
	local health = 1 -- what the fill shows, eased toward the server's

	local function hide()
		since = nil
		made.root.Visible = false
		local current = tint
		tint = nil
		if current then
			current:Destroy()
		end
	end

	local function place()
		local canvas = ctx.canvas()
		local screen = ctx.root.AbsoluteSize
		local areas = ctx.touchAreas()
		local scale = if canvas.X > 0 then screen.X / canvas.X else 0
		local bottom = math.max(BAR.bottom, MatchHudFormat.dockClear(screen, scale, #areas > 0) + BAR.gap)
		local at = MatchHudFormat.barPlace(canvas, areas, nil, made.size, {
			bottom = bottom,
			gap = BAR.gap,
			top = BAR.top,
			scales = BAR.scales,
			fitMin = Config.UI.Match.compact.fitMin,
		})
		made.root.Position = UDim2.fromOffset(math.round(at.x), math.round(at.y))
		made.fit.Scale = at.scale
	end

	local piece = {}

	function piece.update(_self: any, view: any, now: number)
		local position = if ctx.position then ctx.position() else nil
		if not LIVE[view.matchPhase] or not MatchHudFormat.stormShows(view, now, position, STORM) then
			if since ~= nil then
				hide()
			end
			return
		end
		local clock = os.clock()
		local target = 1 - math.clamp(view.you.stormBar or 0, 0, 1)
		if since == nil then
			since = clock
			health = target
			made.root.Visible = true
			local effect: ColorCorrectionEffect = Instance.new("ColorCorrectionEffect")
			effect.Name = TINT_NAME
			effect.TintColor = WHITE
			effect.Parent = Lighting
			tint = effect
		else
			health += (target - health) * math.min(1, (clock - last) * CFG.easeRate)
		end
		last = clock
		local t = clock - (since :: number)
		local reduced = ctx.reduced()
		local fadeMs = if reduced then math.min(CFG.tintMs, FADE_MS) else CFG.tintMs
		local k = if fadeMs > 0 then math.clamp(t / (fadeMs / 1000), 0, 1) else 1
		local effect = tint
		if effect then
			effect.TintColor = WHITE:Lerp(Palette.MatchStormTint, k)
		end
		local enter = BAR.enter
		poser:set(MatchHudFormat.trackPose(enter.frames, t, enter.ms, enter.curve, nil, reduced, FADE_MS))
		made.fill.Size = UDim2.fromOffset(math.round(innerWidth * health), made.fill.Size.Y.Offset)
		place()
	end

	function piece.destroy(_self: any)
		hide()
		made.root:Destroy()
	end

	return piece :: any
end

return StormBar
