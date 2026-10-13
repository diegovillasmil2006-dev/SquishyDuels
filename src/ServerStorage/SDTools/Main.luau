--!strict
-- SDTools Main: entry point of the edit-time world generators (DESIGN §1.7).
-- Server only, Edit mode only (ServerStorage.SDTools); runtime code never requires it.
-- Called on a CLONE of SDTools (and of ReplicatedStorage.Shared) through execute_luau in Edit
-- (tools/mcp/build.mjs), or from the command bar:  require(tools.Main).run({ target = "shapes" }, { Shared = shared })
-- Relative requires only (or the injected deps.Shared): an absolute require would return a stale cached copy
-- after a Rojo edit.
-- Pipeline (§1.7): 1 guards → 2 ChangeHistoryService recording (nil under MCP: the Assistant makes the whole call
-- one undo step) → 3 build the new tree unparented → 4 Verify (any problem aborts, place unchanged) → 5 swap the
-- old roots (Parent = nil, undoable) for the new tree, then Verify.afterSwap (checks that need the tree in
-- Workspace; reported as warnings, never rolled back) → 6 FinishRecording Commit/Cancel → 7 report.
-- Never throws: refusals, build failures and Verify problems come back as a report with ok = false.
-- Targets (one per call):
--   "shapes"  Builders/ShapesBuilder -> ReplicatedStorage.SD_ShapeLibrary (Part 2)
--   "lobby"   Builders/LobbyBuilder  -> Workspace.SD_Lobby (Part 3; Squish Island since build plan Phase 4)
--   "capsules" Builders/CapsuleBuilder -> ServerStorage.SD_Templates.Capsules (Phase 4): the capsule, lock, squishy and
--             statue templates BaseService clones onto the plots.
--   "arena"   Builders/ArenaBuilder  -> ServerStorage.SD_Templates.Arena_CandyCourt (Part 3). SD_Templates is a plain
--             holder Folder, not generated content: it is created when missing and never removed or replaced.
--   "arena_sweetshop_stadium", "arena_pinewood_camp", "arena_pillow_fort_park", "arena_bubble_reef_court",
--   "arena_arcade_toyworks"   Builders/Arenas/<Name> -> ServerStorage.SD_Templates.Arena_<Name>: the 5 design arenas
--             (phase 4 spec 2026-10-11 §5.2; World/Arenas names them). Each has its own generator id, so building one
--             never removes Candy Court or another arena.
-- Builders are required lazily, per target, so a broken builder only breaks its own target.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Generated = require(script.Parent.Generated)
local Verify = require(script.Parent.Verify)

-- Types

export type Options = {
	target: string?,
}

export type Deps = {
	Shared: Instance?,
}

-- §1.7 step 7 report. `ok` and `error` are added so a refusal or a failed build is reported honestly instead of
-- looking like an empty successful build.
export type Report = {
	ok: boolean,
	target: string,
	version: number?,
	parts: number,
	removedRoots: number,
	durationMs: number,
	warnings: { string },
	error: string?,
}

-- What every builder module exports (Generated holds the build contract).
type Builder = {
	VERSION: number,
	build: (ctx: Generated.BuildContext) -> Generated.BuildResult,
}

-- A registered generator target.
type Target = {
	load: () -> any, -- requires the builder module (lazily: a broken builder only breaks its own target)
	parent: (report: Report) -> (Instance?, string?), -- where the new root goes, or why it cannot go anywhere
}

-- Constants

local PLACE_ID = 98945316226507
local SPLIT_TARGET_MS = 90000 -- §1.7: split a target whose build takes longer (the MCP helper times out at 120 s)
local TEMPLATES_FOLDER = "SD_Templates" -- ServerStorage holder of the arena template (§1.5, §5.3)

-- `require` with a runtime-chosen ModuleScript (the injected Shared clone); the analyzer cannot resolve it.
local dynamicRequire = require :: (ModuleScript) -> any

-- Module table

local Main = {}

-- Private

-- ServerStorage.SD_Templates, created when missing. It is not generated content (no SD_Generated tag), so swaps never
-- remove it; a non-Folder with that name is refused instead of being replaced.
local function templatesFolder(report: Report): (Instance?, string?)
	local existing = ServerStorage:FindFirstChild(TEMPLATES_FOLDER)
	if existing then
		if not existing:IsA("Folder") then
			return nil,
				string.format(
					"ServerStorage.%s exists but is a %s, not a Folder; it was left untouched, place unchanged",
					TEMPLATES_FOLDER,
					existing.ClassName
				)
		end
		return existing, nil
	end
	local folder = Instance.new("Folder")
	folder.Name = TEMPLATES_FOLDER
	folder.Parent = ServerStorage
	table.insert(report.warnings, string.format("created ServerStorage.%s (holder folder)", TEMPLATES_FOLDER))
	return folder, nil
end

-- Target id -> generator.
local TARGETS: { [string]: Target } = {
	shapes = {
		load = function(): any
			return require(script.Parent.Builders.ShapesBuilder)
		end,
		parent = function(_report: Report): (Instance?, string?)
			return ReplicatedStorage, nil
		end,
	},
	lobby = {
		load = function(): any
			return require(script.Parent.Builders.LobbyBuilder)
		end,
		parent = function(_report: Report): (Instance?, string?)
			return Workspace, nil
		end,
	},
	capsules = {
		load = function(): any
			return require(script.Parent.Builders.CapsuleBuilder)
		end,
		parent = templatesFolder,
	},
	arena = {
		load = function(): any
			return require(script.Parent.Builders.ArenaBuilder)
		end,
		parent = templatesFolder,
	},
	arena_sweetshop_stadium = {
		load = function(): any
			return require(script.Parent.Builders.Arenas.SweetshopStadium)
		end,
		parent = templatesFolder,
	},
	arena_pinewood_camp = {
		load = function(): any
			return require(script.Parent.Builders.Arenas.PinewoodCamp)
		end,
		parent = templatesFolder,
	},
	arena_pillow_fort_park = {
		load = function(): any
			return require(script.Parent.Builders.Arenas.PillowFortPark)
		end,
		parent = templatesFolder,
	},
	arena_bubble_reef_court = {
		load = function(): any
			return require(script.Parent.Builders.Arenas.BubbleReefCourt)
		end,
		parent = templatesFolder,
	},
	arena_arcade_toyworks = {
		load = function(): any
			return require(script.Parent.Builders.Arenas.ArcadeToyworks)
		end,
		parent = templatesFolder,
	},
}

local function registeredTargets(): string
	local ids = {}
	for id in TARGETS do
		table.insert(ids, id)
	end
	table.sort(ids)
	return if #ids == 0 then "none" else table.concat(ids, ", ")
end

local function newReport(target: string): Report
	return {
		ok = false,
		target = target,
		version = nil,
		parts = 0,
		removedRoots = 0,
		durationMs = 0,
		warnings = {},
		error = nil,
	}
end

local function finish(report: Report, started: number, errorMessage: string?): Report
	report.ok = errorMessage == nil
	report.error = errorMessage
	report.durationMs = math.floor((os.clock() - started) * 1000 + 0.5)
	if report.durationMs > SPLIT_TARGET_MS then
		table.insert(
			report.warnings,
			string.format("build took %d ms (over %d): split this target (§1.7)", report.durationMs, SPLIT_TARGET_MS)
		)
	end
	return report
end

-- RunService:IsEdit() needs Plugin security (command bar, plugins, MCP execute_luau). Any other caller gets an
-- error, so it is called in pcall: nil means "could not check", which refuses like "not in Edit mode".
-- The `any` cast is needed because the type checker's None-security API has no IsEdit.
local function isEditMode(): boolean?
	local ok, result = pcall(function(): any
		return (RunService :: any):IsEdit()
	end)
	if ok and type(result) == "boolean" then
		return result
	end
	return nil
end

-- Returns why building must be refused here, or nil when it is safe (§1.7 step 1).
local function refusal(): string?
	local editMode = isEditMode()
	if editMode == nil then
		return "refused: cannot check Edit mode (RunService:IsEdit needs plugin security: use the command bar or "
			.. "execute_luau)"
	end
	if not editMode then
		return "refused: Studio is not in Edit mode"
	end
	if RunService:IsRunning() then
		return "refused: the game is running (stop Play first)"
	end
	if game.PlaceId ~= PLACE_ID then
		return string.format("refused: wrong place (PlaceId %d, expected %d)", game.PlaceId, PLACE_ID)
	end
	return nil
end

-- Requires Util/Cleanup from the injected Shared clone (relative to it, so never a stale cached copy).
local function loadCleanup(shared: Instance): (any, string?)
	local util = shared:FindFirstChild("Util")
	local module = util and util:FindFirstChild("Cleanup")
	if module == nil or not module:IsA("ModuleScript") then
		return nil, "deps.Shared has no Util/Cleanup module"
	end
	local ok, result = pcall(dynamicRequire, module)
	if not ok then
		return nil, "could not load Shared Util/Cleanup: " .. tostring(result)
	end
	return result, nil
end

-- Step 2. ChangeHistoryService has plugin-only members (the `any` cast) and returns nil under MCP.
local function beginRecording(name: string, report: Report): string?
	local ok, result = pcall(function(): any
		return (ChangeHistoryService :: any):TryBeginRecording(name)
	end)
	if ok and type(result) == "string" then
		return result
	end
	table.insert(
		report.warnings,
		if ok
			then "no undo recording (expected under MCP, where the whole call is one undo step)"
			else "no undo recording: " .. tostring(result)
	)
	return nil
end

-- Step 6.
local function finishRecording(recording: string?, committed: boolean, report: Report)
	if recording == nil then
		return
	end
	local operation = if committed then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
	local ok, err = pcall(function()
		(ChangeHistoryService :: any):FinishRecording(recording, operation)
	end)
	if not ok then
		table.insert(report.warnings, "FinishRecording failed: " .. tostring(err))
	end
end

local function countParts(root: Instance): number
	local count = if root:IsA("BasePart") then 1 else 0
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

-- A child of `parent` with the new root's name that is not a root of this generator. Generators never touch
-- untagged instances, and two same-named roots would make runtime lookups ambiguous, so the build stops instead.
local function nameConflict(parent: Instance, name: string, target: string): Instance?
	for _, child in parent:GetChildren() do
		if child.Name == name and not Generated.isRoot(child, target) then
			return child
		end
	end
	return nil
end

-- Requires the target's builder and checks it exports the build contract.
local function loadBuilder(target: string, entry: Target): (Builder?, string?)
	local ok, result = pcall(entry.load)
	if not ok then
		return nil, string.format("could not load the builder of target %q: %s", target, tostring(result))
	end
	if type(result) ~= "table" or type(result.build) ~= "function" or type(result.VERSION) ~= "number" then
		return nil, string.format("the builder of target %q does not export VERSION and build()", target)
	end
	return result :: Builder, nil
end

-- Steps 3-5. Returns an error message, or nil when the new tree is in place. May throw (Main.run catches it).
local function buildAndSwap(
	target: string,
	entry: Target,
	builder: Builder,
	scratch: any,
	shared: Instance,
	report: Report
): string?
	-- 3. Build unparented.
	local built = builder.build({ scratch = scratch, Shared = shared })
	for _, warning in built.warnings do
		table.insert(report.warnings, warning)
	end
	if not built.ok then
		return "build failed, place unchanged: " .. (built.error or "no reason given")
	end
	local root = built.root
	if root == nil then
		return "build returned no root, place unchanged"
	end
	local swapped = false
	scratch:add(function()
		if swapped then
			return
		elseif root.Parent ~= nil then
			root.Parent = nil -- a faulty builder parented it: remove it the undoable way
		else
			root:Destroy() -- never parented: plain cleanup, nothing to undo
		end
	end)
	if root.Parent ~= nil then
		return "the builder parented its tree before the swap (it must stay unparented); it was removed again"
	end
	local info = Generated.info(root)
	if info == nil or info.generatorId ~= target or info.version ~= builder.VERSION then
		return string.format("new root is not marked as %q version %d", target, builder.VERSION)
	end

	-- 4. Verify.
	local problems = Verify.verify(target, root, { Shared = shared })
	if #problems > 0 then
		return string.format("Verify found %d problem(s), place unchanged: %s", #problems, table.concat(problems, "; "))
	end

	-- 5. Swap.
	local parent, parentError = entry.parent(report)
	if parent == nil then
		return parentError or "no parent for the new root, place unchanged"
	end
	local conflict = nameConflict(parent, root.Name, target)
	if conflict then
		return string.format(
			"%s exists but is not a generated %q root; it was left untouched (rename or remove it by hand), "
				.. "place unchanged",
			conflict:GetFullName(),
			target
		)
	end
	local parts = countParts(root)
	-- swap() either completes or rolls itself back and throws.
	report.removedRoots = Generated.swap(Generated.findRoots(target), root, parent)
	swapped = true
	report.parts = parts

	-- 5b. Checks that need the tree inside the place: reported, never rolled back.
	local checked, lines = pcall(Verify.afterSwap, target, root)
	if not checked then
		table.insert(report.warnings, "after-swap check failed to run: " .. tostring(lines))
	else
		for _, line in lines do
			table.insert(report.warnings, "after swap: " .. line)
		end
	end
	return nil
end

-- Public

-- Builds one target. Never throws: every failure is a report with ok = false.
function Main.run(opts: Options?, deps: Deps?): Report
	local started = os.clock()
	local target = if opts and type(opts.target) == "string" then opts.target else ""
	local report = newReport(target)

	-- 1. Guards.
	local refused = refusal()
	if refused then
		return finish(report, started, refused)
	end
	if target == "" then
		return finish(report, started, "no target given (opts.target)")
	end
	local entry = TARGETS[target]
	if entry == nil then
		return finish(
			report,
			started,
			string.format("unknown target %q (registered targets: %s)", target, registeredTargets())
		)
	end
	local builder, loadError = loadBuilder(target, entry)
	if builder == nil then
		return finish(report, started, loadError)
	end
	report.version = builder.VERSION
	local shared = if deps then deps.Shared else nil
	if typeof(shared) ~= "Instance" then
		return finish(report, started, "deps.Shared missing (pass { Shared = ReplicatedStorage.Shared:Clone() })")
	end
	local Cleanup, cleanupError = loadCleanup(shared)
	if Cleanup == nil then
		return finish(report, started, cleanupError)
	end

	-- 2-6.
	local recording = beginRecording("SD Build " .. target, report)
	local scratch = Cleanup.new()
	local ok, result = pcall(buildAndSwap, target, entry, builder, scratch, shared, report)
	local errorMessage: string? = if ok then result else "build threw, place unchanged: " .. tostring(result)
	scratch:clean()
	finishRecording(recording, errorMessage == nil, report)
	return finish(report, started, errorMessage)
end

return Main
