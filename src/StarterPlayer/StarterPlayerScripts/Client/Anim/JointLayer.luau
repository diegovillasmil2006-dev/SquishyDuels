--!strict
-- JointLayer (client only). Procedural joint layering for one character (DESIGN §9.4, §9.16): named layers of poses
-- composed on top of whatever the Animator wrote, written to joint.Transform once per frame in PreSimulation.
--
-- Joints are found by name (Config.Anim.joints: R15 and the R6 fallback) and accepted when they are an
-- AnimationConstraint or a Motor6D (both have .Transform). C0/C1/Part0/Part1 and rig attachments are never written.
--
-- Write-guard, per joint and frame:
--   base = (lastWritten ~= nil and joint.Transform == lastWritten) and lastBase or joint.Transform
--   out  = compose(base, layers); joint.Transform = out; lastBase = base; lastWritten = joint.Transform (read back)
-- so when the Animator did not write this frame our offset is not stacked on our own output. When no layer touches
-- a joint any more, its base is put back once (if our output is still there) and the joint is left alone.
-- Composition: override layers in ascending priority (then insertion order): out = out:Lerp(poseCF, w), w in [0, 1];
-- then additive layers in insertion order: out = out * CFrame.fromEulerAnglesYXZ(rx·w, ry·w, rz·w).
-- Pose layers take mode, priority, sway (dizzy: sine on one joint axis, added as an additive term) and spring (flinch)
-- from PoseLibrary/Config.Anim.poses. kick() drives a layer's weight with that spring from `amount` back to 0 and
-- removes the layer once it settles.
--
-- Lifecycle: JointLayer.new(character) never yields. It resolves the Humanoid and every joint of the rig now or as
-- they arrive, for up to Config.Anim.joints.waitSeconds; otherwise it logs one warning and the layer is disabled.
-- Its `cleanup` (a Util/Cleanup) is public: the owner adds timelines, indicator parts and connections to it. The held
-- model is not in it: HeldSquishyController owns it (one Cleanup per held model, also cleaned on the character's
-- Destroying). The character's Destroying destroys the layer; the owner also calls destroy() on CharacterRemoving or
-- PlayerRemoving. Joints are re-resolved lazily when one is re-parented or replaced. Frames are skipped while the
-- Animator reports EvaluationThrottled or the character is farther than Config.Anim.joints.cullStuds from the camera
-- (weights, blends and springs still advance). By default the layer steps on the default Scheduler's joint phase.

-- Services

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Requires

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Cleanup = require(Shared.Util.Cleanup)
local Log = require(Shared.Util.Log)
local Spring = require(Shared.Util.Spring)
local PoseLibrary = require(script.Parent.PoseLibrary)
local Scheduler = require(script.Parent.Scheduler)

-- Types

export type Mode = "override" | "additive"

export type Options = {
	autoStep: boolean?, -- default true: steps on the joint phase of `scheduler` (default: Scheduler.default())
	scheduler: Scheduler.Scheduler?,
	cullStuds: number?, -- default Config.Anim.joints.cullStuds; math.huge = never culled
	waitSeconds: number?, -- default Config.Anim.joints.waitSeconds
}

type JointState = {
	name: string,
	path: { string },
	part: Instance?,
	joint: any, -- Motor6D or AnimationConstraint
	lastBase: CFrame?,
	lastWritten: CFrame?,
}

type Sway = {
	joint: string,
	axis: "X" | "Y" | "Z",
	amplitude: number, -- radians
	omega: number, -- rad/s
}

type Layer = {
	id: string,
	mode: Mode,
	priority: number,
	order: number,
	poseName: string?,
	angles: { [string]: Vector3 }?, -- custom layers: radians per logical joint
	cframes: { [string]: CFrame }?, -- custom override layers
	weight: number,
	blendFrom: number,
	blendTo: number,
	blendElapsed: number,
	blendDuration: number, -- > 0 while blending
	clearAfterBlend: boolean,
	sway: Sway?,
	swayStart: number?,
	spring: Spring.Spring<number>?,
}

type JointLayerData = {
	character: Model,
	cleanup: Cleanup.Cleanup,
	_options: Options,
	_cullStuds: number,
	_rig: string?,
	_humanoid: Humanoid?,
	_animator: Animator?,
	_joints: { JointState },
	_layers: { [string]: Layer },
	_overrides: { Layer },
	_additives: { Layer },
	_nextOrder: number,
	_ready: boolean,
	_disabled: boolean,
	_destroyed: boolean,
	_waitConnection: RBXScriptConnection?,
}

-- Constants

local OPTIONAL_JOINTS: { [string]: boolean } = (Config.Anim.joints :: any).optional or {}

local JOINTS_CONFIG = Config.Anim.joints
-- A kicked (spring) layer is removed once position and speed are below this.
local SETTLE_EPSILON = JOINTS_CONFIG.springSettleEpsilon
local DEFAULT_PRIORITY = 0

-- Module table

local JointLayerClass = {}
JointLayerClass.__index = JointLayerClass

export type JointLayer = typeof(setmetatable({} :: JointLayerData, JointLayerClass))

local JointLayer = {}

-- Private

local log = Log.new("JointLayer")

local function isJoint(instance: Instance?): boolean
	return instance ~= nil and (instance:IsA("AnimationConstraint") or instance:IsA("Motor6D"))
end

local function findJoint(character: Model, path: { string }): (Instance?, Instance?)
	local part = character:FindFirstChild(path[1])
	local joint = if part then part:FindFirstChild(path[2]) else nil
	if isJoint(joint) then
		return part, joint
	end
	return nil, nil
end

local function sortOverrides(list: { Layer })
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority < b.priority
		end
		return a.order < b.order
	end)
end

local function tryResolve(self: JointLayer): boolean
	if self._ready or self._destroyed then
		return self._ready
	end
	local humanoid = self.character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return false
	end
	local rig = PoseLibrary.rigOf(humanoid)
	local states: { JointState } = {}
	for name, path in PoseLibrary.joints(rig) do
		local part, joint = findJoint(self.character, path)
		if joint == nil then
			if OPTIONAL_JOINTS[name] then
				continue -- a rig without it keeps every other joint (Config.Anim.joints.optional: the throw's legs)
			end
			return false
		end
		table.insert(states, { name = name, path = path, part = part, joint = joint })
	end
	table.sort(states, function(a, b)
		return a.name < b.name
	end)
	self._humanoid = humanoid
	self._rig = rig
	self._joints = states
	self._ready = true
	local connection = self._waitConnection
	if connection then
		connection:Disconnect()
		self._waitConnection = nil
	end
	return true
end

-- Re-finds a joint that was re-parented or replaced. Returns the joint, or nil to skip it this frame.
local function liveJoint(self: JointLayer, state: JointState): any
	local joint = state.joint
	if joint ~= nil and joint.Parent == state.part and state.part ~= nil and state.part.Parent == self.character then
		return joint
	end
	local part, found = findJoint(self.character, state.path)
	state.part = part
	state.joint = found
	state.lastBase = nil
	state.lastWritten = nil
	return found
end

local function animatorThrottled(self: JointLayer): boolean
	local humanoid = self._humanoid
	if humanoid == nil then
		return false
	end
	local animator = self._animator
	if animator == nil or animator.Parent ~= humanoid then
		animator = humanoid:FindFirstChildOfClass("Animator")
		self._animator = animator
	end
	return animator ~= nil and animator.EvaluationThrottled
end

local function culled(self: JointLayer): boolean
	if self._cullStuds == math.huge then
		return false
	end
	local camera = Workspace.CurrentCamera
	local humanoid = self._humanoid
	local root: BasePart? = self.character.PrimaryPart or (if humanoid then humanoid.RootPart else nil)
	if camera == nil or root == nil then
		return false
	end
	return (camera.CFrame.Position - root.Position).Magnitude > self._cullStuds
end

local function effectiveWeight(layer: Layer): number
	local spring = layer.spring
	return if spring then layer.weight * spring.position else layer.weight
end

local function layerAngles(layer: Layer, rig: string): { [string]: Vector3 }
	local custom = layer.angles
	if custom then
		return custom
	end
	return PoseLibrary.angles(layer.poseName :: string, rig)
end

local function layerCFrames(layer: Layer, rig: string): { [string]: CFrame }
	local custom = layer.cframes
	if custom then
		return custom
	end
	return PoseLibrary.cframes(layer.poseName :: string, rig)
end

local function swayAngles(layer: Layer, joint: string, now: number, base: Vector3?): Vector3?
	local sway = layer.sway
	if sway == nil or sway.joint ~= joint then
		return base
	end
	local start = layer.swayStart or now
	local angle = sway.amplitude * math.sin(sway.omega * (now - start))
	local extra = if sway.axis == "X"
		then Vector3.new(angle, 0, 0)
		elseif sway.axis == "Y" then Vector3.new(0, angle, 0)
		else Vector3.new(0, 0, angle)
	return (base or Vector3.zero) + extra
end

local function removeFromList(list: { Layer }, layer: Layer)
	local index = table.find(list, layer)
	if index then
		table.remove(list, index)
	end
end

local function removeLayer(self: JointLayer, id: string)
	local layer = self._layers[id]
	if layer == nil then
		return
	end
	self._layers[id] = nil
	removeFromList(if layer.mode == "override" then self._overrides else self._additives, layer)
end

local function putLayer(self: JointLayer, layer: Layer)
	local existing = self._layers[layer.id]
	if existing then
		layer.order = existing.order -- keep its place in the composition order
		removeLayer(self, layer.id)
	else
		layer.order = self._nextOrder
		self._nextOrder += 1
	end
	self._layers[layer.id] = layer
	if layer.mode == "override" then
		table.insert(self._overrides, layer)
		sortOverrides(self._overrides)
	else
		table.insert(self._additives, layer)
		table.sort(self._additives, function(a, b)
			return a.order < b.order
		end)
	end
end

local function newLayer(id: string, mode: Mode, priority: number, weight: number): Layer
	assert(type(id) == "string" and id ~= "", "[SD][JointLayer] layer id must be a non-empty string")
	assert(mode == "override" or mode == "additive", `[SD][JointLayer] mode must be override or additive`)
	return {
		id = id,
		mode = mode,
		priority = priority,
		order = 0,
		poseName = nil,
		angles = nil,
		cframes = nil,
		weight = weight,
		blendFrom = weight,
		blendTo = weight,
		blendElapsed = 0,
		blendDuration = 0,
		clearAfterBlend = false,
		sway = nil,
		swayStart = nil,
		spring = nil,
	}
end

local function clampWeight(weight: number?): number
	local w = if weight == nil then 1 else weight
	if w ~= w then
		return 0
	end
	return math.clamp(w, 0, 1)
end

local function poseLayer(id: string, poseName: string, weight: number): Layer
	local pose = PoseLibrary.get(poseName)
	local layer = newLayer(id, pose.mode, pose.priority or DEFAULT_PRIORITY, weight)
	layer.poseName = poseName
	local sway = pose.sway
	if sway then
		layer.sway = {
			joint = sway.joint,
			axis = sway.axis,
			amplitude = math.rad(sway.amplitudeDeg),
			omega = 2 * math.pi * sway.hz,
		}
	end
	return layer
end

-- Advances blends and springs; removes finished layers. Allocates only on a frame where a layer finishes.
local function advance(self: JointLayer, dt: number, now: number)
	local finished: { string }? = nil
	for id, layer in self._layers do
		local done = false
		if layer.blendDuration > 0 then
			layer.blendElapsed += dt
			local alpha = math.min(layer.blendElapsed / layer.blendDuration, 1)
			layer.weight = layer.blendFrom + (layer.blendTo - layer.blendFrom) * alpha
			if alpha >= 1 then
				layer.blendDuration = 0
				done = layer.clearAfterBlend
			end
		end
		local spring = layer.spring
		if spring then
			spring:step(dt)
			if spring:isSettled(SETTLE_EPSILON) then
				done = true
			end
		end
		if layer.sway and layer.swayStart == nil then
			layer.swayStart = now
		end
		if done then
			local list = finished or {}
			finished = list
			table.insert(list, id)
		end
	end
	if finished then
		for _, id in finished do
			removeLayer(self, id)
		end
	end
end

local function compose(self: JointLayer, rig: string, name: string, base: CFrame, now: number): (CFrame, boolean)
	local out = base
	local touched = false
	for _, layer in self._overrides do
		local w = math.clamp(effectiveWeight(layer), 0, 1)
		if w > 0 then
			local poseCF = layerCFrames(layer, rig)[name]
			if poseCF then
				out = out:Lerp(poseCF, w)
				touched = true
			end
		end
	end
	for _, layer in self._additives do
		local w = effectiveWeight(layer)
		if w ~= 0 then
			local radians = swayAngles(layer, name, now, layerAngles(layer, rig)[name])
			if radians then
				out = out * PoseLibrary.toCFrame(radians, w)
				touched = true
			end
		end
	end
	return out, touched
end

local function restoreJoints(self: JointLayer)
	for _, state in self._joints do
		local joint = state.joint
		local lastWritten = state.lastWritten
		if joint ~= nil and lastWritten ~= nil and joint.Transform == lastWritten then
			joint.Transform = state.lastBase
		end
		state.lastBase = nil
		state.lastWritten = nil
	end
end

-- Methods

-- Sets (or replaces) layer `id` to the pose `poseName` at `weight` (default 1, clamped 0-1). Mode, priority, sway
-- and spring come from the pose. Cancels a running blend of that layer.
function JointLayerClass.setPose(self: JointLayer, id: string, poseName: string, weight: number?)
	putLayer(self, poseLayer(id, poseName, clampWeight(weight)))
end

-- Sets layer `id` to custom angles in degrees ({ [logical joint]: Vector3 }, joint space), e.g. computed each frame.
function JointLayerClass.setAngles(
	self: JointLayer,
	id: string,
	mode: Mode,
	degrees: { [string]: Vector3 },
	weight: number?,
	priority: number?
)
	local layer = newLayer(id, mode, priority or DEFAULT_PRIORITY, clampWeight(weight))
	local angles: { [string]: Vector3 } = {}
	local cframes: { [string]: CFrame } = {}
	for joint, value in degrees do
		local radians = Vector3.new(math.rad(value.X), math.rad(value.Y), math.rad(value.Z))
		angles[joint] = radians
		cframes[joint] = PoseLibrary.toCFrame(radians, 1)
	end
	layer.angles = angles
	layer.cframes = cframes
	putLayer(self, layer)
end

-- Spring impulse (flinch): layer `id` with pose `poseName` whose weight starts at `amount` (default 1) and springs
-- back to 0 with the pose's spring (omega, zeta); removed once settled. Kicking again restarts it.
function JointLayerClass.kick(self: JointLayer, id: string, poseName: string, amount: number?)
	local pose = PoseLibrary.get(poseName)
	local springConfig = pose.spring
	assert(springConfig, `[SD][JointLayer] pose {poseName} has no spring`)
	local layer = poseLayer(id, poseName, 1)
	layer.spring = Spring.new(if amount == nil then 1 else amount, springConfig.omega, springConfig.zeta, 0)
	putLayer(self, layer)
end

-- Sets the weight of layer `id` at once (clamped 0-1); cancels its blend. No-op for an unknown id.
function JointLayerClass.setWeight(self: JointLayer, id: string, weight: number)
	local layer = self._layers[id]
	if layer then
		layer.weight = clampWeight(weight)
		layer.blendDuration = 0
	end
end

-- Blends the weight of layer `id` linearly to `target` over `seconds`; clearAtEnd removes the layer when done.
function JointLayerClass.blendWeight(
	self: JointLayer,
	id: string,
	target: number,
	seconds: number,
	clearAtEnd: boolean?
)
	local layer = self._layers[id]
	if layer == nil then
		return
	end
	local to = clampWeight(target)
	if not (seconds > 0) then
		layer.weight = to
		layer.blendDuration = 0
		if clearAtEnd then
			removeLayer(self, id)
		end
		return
	end
	layer.blendFrom = layer.weight
	layer.blendTo = to
	layer.blendElapsed = 0
	layer.blendDuration = seconds
	layer.clearAfterBlend = clearAtEnd == true
end

-- Blends every layer to `target` (duel end: 0 over Config.Anim.joints.duelEndBlendMs).
function JointLayerClass.blendAll(self: JointLayer, target: number, seconds: number, clearAtEnd: boolean?)
	local ids: { string } = {}
	for id in self._layers do
		table.insert(ids, id)
	end
	for _, id in ids do
		self:blendWeight(id, target, seconds, clearAtEnd)
	end
end

-- Current weight of layer `id` (spring included), or nil if there is no such layer.
function JointLayerClass.getWeight(self: JointLayer, id: string): number?
	local layer = self._layers[id]
	return if layer then effectiveWeight(layer) else nil
end

function JointLayerClass.has(self: JointLayer, id: string): boolean
	return self._layers[id] ~= nil
end

function JointLayerClass.clear(self: JointLayer, id: string)
	removeLayer(self, id)
end

function JointLayerClass.clearAll(self: JointLayer)
	table.clear(self._layers)
	table.clear(self._overrides)
	table.clear(self._additives)
end

function JointLayerClass.isReady(self: JointLayer): boolean
	return self._ready
end

function JointLayerClass.isDisabled(self: JointLayer): boolean
	return self._disabled
end

function JointLayerClass.getRig(self: JointLayer): string?
	return self._rig
end

-- One frame (the Scheduler joint-phase effect). Returns false once destroyed or disabled.
function JointLayerClass.step(self: JointLayer, dt: number, now: number): boolean
	if self._destroyed or self._disabled then
		return false
	end
	advance(self, dt, now)
	if not self._ready and not tryResolve(self) then
		return true
	end
	if animatorThrottled(self) or culled(self) then
		return true
	end
	local rig = self._rig :: string
	for _, state in self._joints do
		local joint = liveJoint(self, state)
		if joint == nil then
			continue
		end
		local current: CFrame = joint.Transform
		local lastWritten = state.lastWritten
		local base: CFrame = if lastWritten ~= nil and current == lastWritten then state.lastBase :: CFrame else current
		local out, touched = compose(self, rig, state.name, base, now)
		if touched then
			joint.Transform = out
			state.lastBase = base
			state.lastWritten = joint.Transform
		elseif lastWritten ~= nil then
			if current == lastWritten then
				joint.Transform = base -- no layer left: put the base back once
			end
			state.lastBase = nil
			state.lastWritten = nil
		end
	end
	return true
end

-- Puts every joint's base back (where our output is still there), drops all layers and cleans `cleanup`.
function JointLayerClass.destroy(self: JointLayer)
	if self._destroyed then
		return
	end
	self._destroyed = true
	restoreJoints(self)
	self:clearAll()
	self.cleanup:clean()
end

-- Public

function JointLayer.new(character: Model, options: Options?): JointLayer
	assert(typeof(character) == "Instance" and character:IsA("Model"), "[SD][JointLayer] new needs a character Model")
	local opts: Options = options or {}
	local data: JointLayerData = {
		character = character,
		cleanup = Cleanup.new(),
		_options = opts,
		_cullStuds = opts.cullStuds or JOINTS_CONFIG.cullStuds,
		_rig = nil,
		_humanoid = nil,
		_animator = nil,
		_joints = {},
		_layers = {},
		_overrides = {},
		_additives = {},
		_nextOrder = 1,
		_ready = false,
		_disabled = false,
		_destroyed = false,
		_waitConnection = nil,
	}
	local self = setmetatable(data, JointLayerClass)
	local cleanup = self.cleanup

	cleanup:add(character.Destroying:Connect(function()
		self:destroy()
	end))

	if not tryResolve(self) then
		local connection = character.DescendantAdded:Connect(function()
			tryResolve(self)
		end)
		self._waitConnection = connection
		cleanup:add(connection)
		local waitSeconds = opts.waitSeconds or JOINTS_CONFIG.waitSeconds
		cleanup:add(task.delay(waitSeconds, function()
			if not tryResolve(self) and not self._destroyed then
				self._disabled = true
				local waiting = self._waitConnection
				if waiting then
					waiting:Disconnect()
					self._waitConnection = nil
				end
				log:warn(`{character.Name}: no Humanoid or joints after {waitSeconds} s; joint layer disabled`)
			end
		end))
	end

	if opts.autoStep ~= false then
		local scheduler = opts.scheduler or Scheduler.default()
		cleanup:add(scheduler:add(self :: any, "joint"))
	end
	return self
end

return JointLayer
