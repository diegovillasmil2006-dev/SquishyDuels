-- Studio side of the snapshot tool. tools/snapshot/snap.mjs serves this file; the bootstraps in CLAUDE.md load it with
-- loadstring and call it with "snapshot" or "restore" while HttpService.HttpEnabled is switched on.
--   snapshot: sends every script (as text, to src/) and every other top-level object (as .rbxm, to world/) to the helper.
--   restore:  makes Studio match src/ and world/ on disk: changed scripts get their old source back, missing objects
--             come back, objects that are not in the files are removed. Only scripts, folders and world items are touched.
local HttpService = game:GetService("HttpService")
local SerializationService = game:GetService("SerializationService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local Players = game:GetService("Players")

local BASE = "http://127.0.0.1:34901"
local BATCH_BYTES = 300000

-- Code folders: every script and folder inside is saved as text under src/<path>.
local CODE_ROOTS = {
	{ path = "ReplicatedStorage/Shared", parent = game:GetService("ReplicatedStorage"), name = "Shared" },
	{ path = "ServerScriptService/Server", parent = game:GetService("ServerScriptService"), name = "Server" },
	{ path = "ServerStorage/UnitTest", parent = game:GetService("ServerStorage"), name = "UnitTest" },
	{ path = "ServerStorage/SDTools", parent = game:GetService("ServerStorage"), name = "SDTools" },
	{ path = "StarterPlayer/StarterPlayerScripts/Client", parent = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"), name = "Client" },
}

-- World containers: each direct child (other than the code folders) is saved as world/<container>/<name>.rbxm.
local WORLD = {
	{ name = "Workspace", inst = workspace },
	{ name = "ReplicatedStorage", inst = game:GetService("ReplicatedStorage") },
	{ name = "ReplicatedFirst", inst = game:GetService("ReplicatedFirst") },
	{ name = "ServerScriptService", inst = game:GetService("ServerScriptService") },
	{ name = "ServerStorage", inst = game:GetService("ServerStorage") },
	{ name = "StarterGui", inst = game:GetService("StarterGui") },
	{ name = "StarterPack", inst = game:GetService("StarterPack") },
	{ name = "StarterPlayerScripts", inst = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts") },
	{ name = "StarterCharacterScripts", inst = game:GetService("StarterPlayer"):WaitForChild("StarterCharacterScripts") },
	{ name = "Lighting", inst = game:GetService("Lighting") },
	{ name = "SoundService", inst = game:GetService("SoundService") },
	{ name = "Teams", inst = game:GetService("Teams") },
	{ name = "MaterialService", inst = game:GetService("MaterialService") },
}

local SUFFIX = { ModuleScript = "", Script = ".server", LocalScript = ".client" }
local CLASS_BY_SUFFIX = { [""] = "ModuleScript", [".server"] = "Script", [".client"] = "LocalScript" }

local function isCodeRoot(inst: Instance): boolean
	for _, root in CODE_ROOTS do
		if inst.Parent == root.parent and inst.Name == root.name then
			return true
		end
	end
	return false
end

local function skipWorldItem(inst: Instance): boolean
	return inst:IsA("Terrain")
		or inst:IsA("Camera")
		or inst.Name == "__Rojo_SessionLock"
		or isCodeRoot(inst)
		or Players:GetPlayerFromCharacter(inst) ~= nil
		or not inst.Archivable
end

-- base64 ------------------------------------------------------------------------------------------------------------

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local ENC, DEC = {}, {}
for i = 1, 64 do
	local c = string.byte(ALPHABET, i)
	ENC[i - 1] = c
	DEC[c] = i - 1
end
local PAD = string.byte("=")

local function toBase64(data: buffer): string
	local n = buffer.len(data)
	local out = buffer.create(math.ceil(n / 3) * 4)
	local o = 0
	for i = 0, n - 1, 3 do
		local b1 = if i + 1 < n then buffer.readu8(data, i + 1) else 0
		local b2 = if i + 2 < n then buffer.readu8(data, i + 2) else 0
		local v = bit32.bor(bit32.lshift(buffer.readu8(data, i), 16), bit32.lshift(b1, 8), b2)
		buffer.writeu8(out, o, ENC[bit32.rshift(v, 18)])
		buffer.writeu8(out, o + 1, ENC[bit32.band(bit32.rshift(v, 12), 63)])
		buffer.writeu8(out, o + 2, if i + 1 < n then ENC[bit32.band(bit32.rshift(v, 6), 63)] else PAD)
		buffer.writeu8(out, o + 3, if i + 2 < n then ENC[bit32.band(v, 63)] else PAD)
		o += 4
	end
	return buffer.tostring(out)
end

local function fromBase64(s: string): buffer
	local len = #s
	local pad = (if string.byte(s, len) == PAD then 1 else 0) + (if string.byte(s, len - 1) == PAD then 1 else 0)
	local out = buffer.create(len // 4 * 3 - pad)
	local size, o = buffer.len(out), 0
	for i = 1, len, 4 do
		local v = bit32.bor(
			bit32.lshift(DEC[string.byte(s, i)], 18),
			bit32.lshift(DEC[string.byte(s, i + 1)], 12),
			bit32.lshift(DEC[string.byte(s, i + 2)] or 0, 6),
			DEC[string.byte(s, i + 3)] or 0
		)
		for shift = 16, 0, -8 do
			if o < size then
				buffer.writeu8(out, o, bit32.band(bit32.rshift(v, shift), 255))
				o += 1
			end
		end
	end
	return out
end

-- http --------------------------------------------------------------------------------------------------------------

local function request(method: string, route: string, payload: any?): any
	local res = HttpService:RequestAsync({
		Url = BASE .. route,
		Method = method,
		Body = if payload ~= nil then HttpService:JSONEncode(payload) else nil,
		Headers = if payload ~= nil then { ["Content-Type"] = "application/json" } else nil,
	})
	if not res.Success then
		error(string.format("%s %s failed (%d): %s", method, route, res.StatusCode, res.Body), 0)
	end
	return HttpService:JSONDecode(res.Body)
end

local function batcher(route: string)
	local batch, size = {}, 0
	local self = {}
	function self.add(entry, bytes: number)
		if size + bytes > BATCH_BYTES and #batch > 0 then
			self.flush()
		end
		table.insert(batch, entry)
		size += bytes
	end
	function self.flush()
		if #batch > 0 then
			request("POST", route, { files = batch })
			batch, size = {}, 0
		end
	end
	return self
end

-- snapshot ----------------------------------------------------------------------------------------------------------

-- Names become file names, so they must be safe and unique among siblings (Windows ignores case).
local function checkChildren(inst: Instance, problems: { string })
	local seen = {}
	for _, c in inst:GetChildren() do
		if c:IsA("LuaSourceContainer") or c:IsA("Folder") then
			if c.Name == "" or c.Name:find('[/\\:%*%?"<>|%.%c]') or c.Name:match("^%s") or c.Name:match("%s$") then
				table.insert(problems, "bad name (no dots, slashes or edge spaces): " .. c:GetFullName())
			end
			local key = c.Name:lower()
			if seen[key] then
				table.insert(problems, "two siblings share the name '" .. c.Name .. "' in " .. inst:GetFullName())
			end
			seen[key] = true
		end
	end
end

local function exportCode(notes: { string }): number
	local out = batcher("/code")
	local problems, count = {}, 0
	local function emit(inst: Instance, path: string, isRoot: boolean)
		checkChildren(inst, problems)
		local kids = inst:GetChildren()
		if inst:IsA("Folder") then
			local dir = if isRoot then path else path .. "/" .. inst.Name
			if #kids == 0 then
				out.add({ path = dir, dir = true }, 64)
			end
			for _, c in kids do
				emit(c, dir, false)
			end
		elseif SUFFIX[inst.ClassName] then
			local source = (inst :: any).Source
			local file, dir
			if isRoot or #kids > 0 then
				dir = if isRoot then path else path .. "/" .. inst.Name
				file = dir .. "/init" .. SUFFIX[inst.ClassName] .. ".luau"
			else
				file = path .. "/" .. inst.Name .. SUFFIX[inst.ClassName] .. ".luau"
			end
			out.add({ path = file, source = source }, #source + #file + 64)
			count += 1
			for _, c in kids do
				emit(c, dir, false)
			end
		else
			table.insert(notes, "not saved (only scripts and folders are, inside code folders): " .. inst:GetFullName())
		end
	end
	for _, root in CODE_ROOTS do
		local inst = root.parent:FindFirstChild(root.name)
		assert(inst, "code folder missing in Studio: " .. root.path)
		emit(inst, root.path, true)
	end
	if #problems > 0 then
		error("rename these first:\n" .. table.concat(problems, "\n"), 0)
	end
	out.flush()
	return count
end

local function safeFileName(name: string): string
	local s = name:gsub("[^%w%-_ ]", "_"):sub(1, 80)
	return if s == "" then "_" else s
end

local function sortedWorldItems(container: Instance): { Instance }
	local items = {}
	for _, c in container:GetChildren() do
		if not skipWorldItem(c) then
			table.insert(items, c)
		end
	end
	-- stable order so index.json and the "~2" suffixes do not shuffle between snapshots
	table.sort(items, function(a, b)
		if a.Name ~= b.Name then
			return a.Name < b.Name
		end
		return a.ClassName < b.ClassName
	end)
	return items
end

local function exportWorld(): number
	local out = batcher("/world")
	local index = {}
	for _, w in WORLD do
		local used = {}
		for _, item in sortedWorldItems(w.inst) do
			local base = w.name .. "/" .. safeFileName(item.Name)
			local file, n = base .. ".rbxm", 1
			while used[file:lower()] do
				n += 1
				file = base .. "~" .. n .. ".rbxm"
			end
			used[file:lower()] = true
			local encoded = toBase64(SerializationService:SerializeInstancesAsync({ item }))
			out.add({ path = file, base64 = encoded }, #encoded + #file + 64)
			table.insert(index, { container = w.name, name = item.Name, class = item.ClassName, file = file })
		end
	end
	out.flush()
	request("POST", "/index", { index = index })
	return #index
end

local function snapshot(): string
	local notes = {}
	request("POST", "/begin", {})
	local ok, err = pcall(function()
		local scripts = exportCode(notes)
		local items = exportWorld()
		table.insert(notes, 1, string.format("(%d scripts, %d world items)", scripts, items))
	end)
	if not ok then
		request("POST", "/abort", { error = tostring(err) })
		error(err, 0)
	end
	local res = request("POST", "/end", {})
	return res.result .. "\n" .. table.concat(notes, "\n")
end

-- restore -----------------------------------------------------------------------------------------------------------

local function parseFile(p: string): (string, string)
	local dir, file = p:match("^(.*)/([^/]+)$")
	local base, suffix = file:match("^(.-)(%.server)%.luau$")
	if not base then
		base, suffix = file:match("^(.-)(%.client)%.luau$")
	end
	if not base then
		base, suffix = file:match("^(.-)%.luau$"), ""
	end
	if base == "init" then
		return dir, CLASS_BY_SUFFIX[suffix]
	end
	return dir .. "/" .. base, CLASS_BY_SUFFIX[suffix]
end

local function restoreCode(manifest, stats)
	local nodes, children = {}, {}
	local function addNode(path: string, class: string, source: string?)
		local existing = nodes[path]
		if existing and existing.class ~= "Folder" and class == "Folder" then
			return -- a script with children: its init file already gave the class
		end
		nodes[path] = { class = class, source = source }
	end
	for _, dir in manifest.dirs do
		addNode(dir, "Folder", nil)
	end
	for part = 0, manifest.codeChunks - 1 do
		for _, f in request("GET", "/code?part=" .. part).files do
			local path, class = parseFile(f.path)
			addNode(path, class, f.source)
		end
	end
	for path in nodes do
		local parent, name = path:match("^(.*)/([^/]+)$")
		if parent and nodes[parent] then
			children[parent] = children[parent] or {}
			children[parent][name] = path
		end
	end

	local function sync(inst: Instance, path: string)
		local node = nodes[path]
		if node.source and (inst :: any).Source ~= node.source then
			(inst :: any).Source = node.source
			stats.updated += 1
		end
		local want = children[path] or {}
		local have = {}
		for _, c in inst:GetChildren() do
			if c:IsA("LuaSourceContainer") or c:IsA("Folder") then
				if want[c.Name] then
					have[c.Name] = c
				else
					c:Destroy()
					stats.removed += 1
				end
			end
		end
		for name, childPath in want do
			local class = nodes[childPath].class
			local c = have[name]
			if c and c.ClassName ~= class then
				local replacement = Instance.new(class)
				replacement.Name = name
				for _, grandchild in c:GetChildren() do
					grandchild.Parent = replacement
				end
				c:Destroy()
				replacement.Parent = inst
				c = replacement
				stats.updated += 1
			elseif not c then
				c = Instance.new(class)
				c.Name = name
				c.Parent = inst
				stats.added += 1
			end
			sync(c, childPath)
		end
	end

	for _, root in CODE_ROOTS do
		local inst = root.parent:FindFirstChild(root.name)
		local node = nodes[root.path]
		assert(inst and node, "code folder missing: " .. root.path)
		assert(inst.ClassName == node.class, "code folder changed class: " .. root.path)
		sync(inst, root.path)
	end
end

local function restoreWorld(manifest, stats)
	local byContainer = {}
	for _, entry in manifest.index do
		byContainer[entry.container] = byContainer[entry.container] or {}
		table.insert(byContainer[entry.container], entry)
	end
	for _, w in WORLD do
		local current = {}
		for _, item in sortedWorldItems(w.inst) do
			current[item.Name] = current[item.Name] or {}
			table.insert(current[item.Name], item)
		end
		for _, entry in byContainer[w.name] or {} do
			local data = fromBase64(request("GET", "/worldfile?file=" .. HttpService:UrlEncode(entry.file)).base64)
			local matches = current[entry.name]
			local existing = matches and table.remove(matches, 1)
			if existing and buffer.tostring(SerializationService:SerializeInstancesAsync({ existing })) == buffer.tostring(data) then
				continue
			end
			local restored = SerializationService:DeserializeInstancesAsync(data)[1]
			restored.Parent = w.inst
			if existing then
				existing:Destroy()
				stats.updated += 1
			else
				stats.added += 1
			end
		end
		for _, leftovers in current do
			for _, item in leftovers do
				item:Destroy()
				stats.removed += 1
			end
		end
	end
end

local function restore(): string
	local manifest = request("GET", "/manifest")
	local stats = { added = 0, updated = 0, removed = 0 }
	-- one undo step in Studio (Ctrl+Z) when the calling context is allowed to record history
	local canRecord, recording = pcall(ChangeHistoryService.TryBeginRecording, ChangeHistoryService, "Snapshot restore")
	local ok, err = pcall(function()
		restoreCode(manifest, stats)
		restoreWorld(manifest, stats)
	end)
	if canRecord and recording then
		local operation = if ok then Enum.FinishRecordingOperation.Commit else Enum.FinishRecordingOperation.Cancel
		pcall(ChangeHistoryService.FinishRecording, ChangeHistoryService, recording, operation)
	end
	local summary = string.format("%d added, %d changed, %d removed", stats.added, stats.updated, stats.removed)
	if not ok then
		summary = "FAILED after " .. summary .. ": " .. tostring(err)
	end
	return request("POST", "/end", { result = summary }).result
end

return function(mode: string): string
	if mode == "snapshot" then
		return snapshot()
	elseif mode == "restore" then
		return restore()
	end
	error("unknown mode: " .. tostring(mode), 0)
end
