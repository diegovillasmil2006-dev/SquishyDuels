--!strict
-- Config.Debug: Studio-only debug and test flags (DESIGN §13.1, §12 #21). Shared, data only.
-- Every flag reads false unless RunService:IsStudio(), so a flag left on can never reach a live server.
-- Edit STUDIO_FLAGS to turn a Studio feature off; the runtime test harness also needs its own explicit test flag.

local RunService = game:GetService("RunService")

local IS_STUDIO = RunService:IsStudio()

-- Values used in Studio only.
local STUDIO_FLAGS = {
	debugHooks = true, -- ServerStorage.SD_DebugServer / PlayerScripts.SD_DebugClient BindableFunctions
	testHarness = true, -- T2 test dummy (TestHarness); still needs the runtime test attribute set from execute_luau
	autoDriver = true, -- scripted client input for multi-client tests (acts only on Workspace.SD_TestScenario)
	failOnInvalidConfig = true, -- boot errors when Config.validate() reports problems
	checkInitYield = true, -- bootstrap runs each init() in a coroutine and errors if it yields
	cleanupLiveCount = true, -- Util/Cleanup live counter for leak tests
	netCallCounter = true, -- NetController counts outgoing calls
	warnMissingAssets = true, -- one warning per nil AssetTable id
	debugCoinReason = true, -- allows the Economy reason "debug"
	logDebug = false, -- Util/Log debug-level lines
	forcePadPathB = false, -- every giant pad skips path A (EditableMesh) and logs its path B line (§17.12 L3 check)
	-- Feel pass (§18.7, §18.3.4).
	soundPicker = true, -- PlayerScripts.SD_SoundPicker BindableFunction and SoundController auditions (Play only)
	forceRipplePathB = false, -- the jelly ripple skips path A (arena and backstop skins) and uses path B
}

local Debug = {
	isStudio = IS_STUDIO,
	debugHooks = IS_STUDIO and STUDIO_FLAGS.debugHooks,
	testHarness = IS_STUDIO and STUDIO_FLAGS.testHarness,
	autoDriver = IS_STUDIO and STUDIO_FLAGS.autoDriver,
	failOnInvalidConfig = IS_STUDIO and STUDIO_FLAGS.failOnInvalidConfig,
	checkInitYield = IS_STUDIO and STUDIO_FLAGS.checkInitYield,
	cleanupLiveCount = IS_STUDIO and STUDIO_FLAGS.cleanupLiveCount,
	netCallCounter = IS_STUDIO and STUDIO_FLAGS.netCallCounter,
	warnMissingAssets = IS_STUDIO and STUDIO_FLAGS.warnMissingAssets,
	debugCoinReason = IS_STUDIO and STUDIO_FLAGS.debugCoinReason,
	logDebug = IS_STUDIO and STUDIO_FLAGS.logDebug,
	forcePadPathB = IS_STUDIO and STUDIO_FLAGS.forcePadPathB,
	soundPicker = IS_STUDIO and STUDIO_FLAGS.soundPicker,
	forceRipplePathB = IS_STUDIO and STUDIO_FLAGS.forceRipplePathB,
}

return Debug
