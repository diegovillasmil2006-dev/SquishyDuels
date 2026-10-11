--!strict
-- Log (shared: server and client). Tagged logging: every line starts with "[SD][<Tag>]".
-- Levels: debug (print; Studio only and only while Config.Debug.logDebug is true), info (print),
-- warn (warn), error (raised in a separate thread so it shows red in the Output and in error reports,
-- without stopping the caller). Arguments are joined with spaces through tostring.
-- Config is required lazily on the first debug call (never at require time), so Config modules can
-- require Log without a cycle. If Config is missing or fails to load, debug stays off.

-- Services

local RunService = game:GetService("RunService")

-- Types

type LoggerData = {
	_prefix: string,
}

-- Constants

local PREFIX = "[SD]"
local IS_STUDIO = RunService:IsStudio()

-- Module table

local LoggerClass = {}
LoggerClass.__index = LoggerClass

export type Logger = typeof(setmetatable({} :: LoggerData, LoggerClass))

local Log = {}

-- Private

local debugEnabled: boolean? = nil -- cached once Config has loaded

local function isDebugEnabled(): boolean
	if not IS_STUDIO then
		return false
	end
	if debugEnabled ~= nil then
		return debugEnabled
	end
	local utilFolder = script.Parent
	local sharedFolder = utilFolder and utilFolder.Parent
	local configModule = sharedFolder and sharedFolder:FindFirstChild("Config")
	if not configModule or not configModule:IsA("ModuleScript") then
		return false
	end
	local requireAny: (ModuleScript) -> any = require
	local ok, config = pcall(requireAny, configModule)
	if not ok then
		return false -- not cached: Config may still be loading (recursive require); try again next time
	end
	local debugSection = if type(config) == "table" then config.Debug else nil
	local enabled = type(debugSection) == "table" and debugSection.logDebug == true
	debugEnabled = enabled
	return enabled
end

local function compose(prefix: string, ...: any): string
	local count = select("#", ...)
	local parts = table.create(count + 1)
	parts[1] = prefix
	for i = 1, count do
		parts[i + 1] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

-- Logger methods

function LoggerClass.debug(self: Logger, ...: any)
	if isDebugEnabled() then
		print(compose(self._prefix, ...))
	end
end

function LoggerClass.info(self: Logger, ...: any)
	print(compose(self._prefix, ...))
end

function LoggerClass.warn(self: Logger, ...: any)
	warn(compose(self._prefix, ...))
end

function LoggerClass.error(self: Logger, ...: any)
	task.spawn(error, compose(self._prefix, ...), 0)
end

-- Public

function Log.new(tag: string): Logger
	local logger: LoggerData = {
		_prefix = PREFIX .. "[" .. tag .. "]",
	}
	return setmetatable(logger, LoggerClass)
end

return Log
