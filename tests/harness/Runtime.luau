--[[
	Runtime (Lune)
	Loads the game's real Luau modules outside Roblox.

	- Builds a virtual instance tree that mirrors default.project.json (ReplicatedStorage.Shared, ...)
	- Implements `require(instance)`, `script`, `game:GetService` and the Roblox globals the code uses
	- Provides in-memory mocks for Players, DataStoreService, RunService, HttpService, MarketplaceService
	- Lets a test replace any module with a fake (runtime:Mock("ReplicatedStorage/Shared/Remotes/Net", fake))

	Each Runtime has its own module cache, so tests are isolated from each other.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local Mocks = require("./Mocks")

local Runtime = {}
Runtime.__index = Runtime

local MAPPING = {
	{ Service = "ReplicatedStorage", Child = "Shared", Path = "src/ReplicatedStorage/Shared" },
	{ Service = "ServerScriptService", Child = "Server", Path = "src/ServerScriptService/Server" },
	{ Service = "ServerStorage", Child = "Assets", Path = "src/ServerStorage/Assets" },
	{ Service = "StarterPlayer", Child = "StarterPlayerScripts", Path = "src/StarterPlayer/StarterPlayerScripts", Nested = true },
}

-- Virtual instances ----------------------------------------------------------------------

local internals = setmetatable({}, { __mode = "k" })
local NodeMethods = {}
local NodeMeta = {}

local function newNode(name: string, className: string, parent: any?, file: string?)
	local node = setmetatable({}, NodeMeta)
	internals[node] = { Name = name, ClassName = className, Parent = parent, Children = {}, File = file, Attributes = {} }
	if parent then
		internals[parent].Children[name] = node
	end
	return node
end

function NodeMeta.__index(self, key)
	local data = internals[self]
	if key == "Name" or key == "ClassName" or key == "Parent" then
		return data[key]
	end
	if NodeMethods[key] then
		return NodeMethods[key]
	end
	local child = data.Children[key]
	if child then
		return child
	end
	error(("%s is not a valid member of %s"):format(tostring(key), NodeMethods.GetFullName(self)), 2)
end

function NodeMeta.__tostring(self)
	return internals[self].Name
end

function NodeMethods.FindFirstChild(self, name)
	return internals[self].Children[name]
end

function NodeMethods.WaitForChild(self, name)
	local child = internals[self].Children[name]
	if not child then
		error(("WaitForChild: %s has no child %s (would yield forever)"):format(NodeMethods.GetFullName(self), tostring(name)), 2)
	end
	return child
end

function NodeMethods.GetChildren(self)
	local out = {}
	for _, child in internals[self].Children do
		table.insert(out, child)
	end
	table.sort(out, function(a, b)
		return internals[a].Name < internals[b].Name
	end)
	return out
end

function NodeMethods.GetDescendants(self)
	local out = {}
	local function walk(node)
		for _, child in NodeMethods.GetChildren(node) do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

function NodeMethods.IsA(self, className)
	local own = internals[self].ClassName
	if own == className then
		return true
	end
	if className == "LuaSourceContainer" then
		return own == "ModuleScript" or own == "Script" or own == "LocalScript"
	end
	return false
end

function NodeMethods.GetFullName(self)
	local parts = {}
	local node = self
	while node do
		table.insert(parts, 1, internals[node].Name)
		node = internals[node].Parent
	end
	return table.concat(parts, ".")
end

function NodeMethods.GetAttribute(self, name)
	return internals[self].Attributes[name]
end

function NodeMethods.SetAttribute(self, name, value)
	internals[self].Attributes[name] = value
end

local function scriptClassFor(fileName: string): (string?, string?)
	local base = string.match(fileName, "^(.+)%.luau$") or string.match(fileName, "^(.+)%.lua$")
	if not base then
		return nil, nil
	end
	local serverName = string.match(base, "^(.+)%.server$")
	if serverName then
		return serverName, "Script"
	end
	local clientName = string.match(base, "^(.+)%.client$")
	if clientName then
		return clientName, "LocalScript"
	end
	return base, "ModuleScript"
end

local function buildDirectory(dirPath: string, node)
	local entries = fs.readDir(dirPath)
	table.sort(entries)
	for _, entry in entries do
		local full = dirPath .. "/" .. entry
		if fs.isDir(full) then
			buildDirectory(full, newNode(entry, "Folder", node))
		else
			local name, className = scriptClassFor(entry)
			if name and className then
				newNode(name, className, node, full)
			end
		end
	end
end

-- Runtime ---------------------------------------------------------------------------------

function Runtime.new(options: { IsServer: boolean?, Root: string? }?)
	options = options or {}
	local self = setmetatable({}, Runtime)
	self.Root = (options :: any).Root or "."
	self.IsServer = if (options :: any).IsServer == nil then true else (options :: any).IsServer
	self.Cache = {}
	self.Loading = {}
	self.Overrides = {}
	self.Services = {}

	-- Build service roots
	for _, map in MAPPING do
		local service = self.Services[map.Service]
		if not service then
			service = newNode(map.Service, map.Service, nil)
			self.Services[map.Service] = service
		end
		local childNode = newNode(map.Child, "Folder", service)
		-- Empty folders are not tracked by git, so a fresh clone may lack some of them.
		local dir = self.Root .. "/" .. map.Path
		if fs.isDir(dir) then
			buildDirectory(dir, childNode)
		end
	end

	self.Mocks = Mocks.create(self)
	for name, mock in self.Mocks.Services do
		if not self.Services[name] then
			self.Services[name] = mock
		end
	end

	local runtime = self
	self.Game = setmetatable({
		JobId = "test-job",
		PlaceId = 0,
		GetService = function(_, name)
			local service = runtime.Services[name]
			if not service then
				error("Runtime has no mock for service " .. tostring(name), 2)
			end
			return service
		end,
		BindToClose = function(_, fn)
			table.insert(runtime.Mocks.CloseCallbacks, fn)
		end,
	}, {})

	self.Globals = {
		game = self.Game,
		workspace = self.Services.Workspace,
		task = task,
		warn = function(...)
			table.insert(runtime.Mocks.Warnings, table.concat(table.pack(...) :: any, " ", 1, select("#", ...)))
		end,
		Random = Mocks.Random,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		UDim2 = roblox.UDim2,
		UDim = roblox.UDim,
		Vector2 = roblox.Vector2,
		Enum = roblox.Enum,
		Instance = roblox.Instance,
		NumberRange = roblox.NumberRange,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		TweenInfo = roblox.TweenInfo or nil,
		time = function()
			return os.clock()
		end,
		tick = function()
			return os.clock()
		end,
	}
	return self
end

function Runtime:GetService(name: string)
	return self.Game:GetService(name)
end

-- "ReplicatedStorage/Shared/Config/Units" -> node
function Runtime:Find(path: string)
	local node = nil
	for part in string.gmatch(path, "[^/]+") do
		if node == nil then
			node = self.Services[part]
		else
			node = NodeMethods.FindFirstChild(node, part)
		end
		if node == nil then
			error("Runtime:Find could not resolve " .. path, 2)
		end
	end
	return node
end

function Runtime:Mock(path: string, value: any)
	self.Overrides[self:Find(path)] = value
end

function Runtime:Require(target: any)
	if type(target) == "string" then
		target = self:Find(target)
	end
	local override = self.Overrides[target]
	if override ~= nil then
		return override
	end
	local cached = self.Cache[target]
	if cached ~= nil then
		return cached
	end
	local data = internals[target]
	if not data or not data.File then
		error("Attempted to require a non-module: " .. tostring(target), 2)
	end
	if data.ClassName ~= "ModuleScript" then
		error("Attempted to require a " .. data.ClassName .. ": " .. tostring(target), 2)
	end
	if self.Loading[target] then
		error("Cyclic require detected at " .. NodeMethods.GetFullName(target), 2)
	end
	self.Loading[target] = true
	local result = self:_execute(target)
	self.Loading[target] = nil
	if result == nil then
		error("Module did not return a value: " .. NodeMethods.GetFullName(target), 2)
	end
	self.Cache[target] = result
	return result
end

-- Runs a Script/LocalScript/ModuleScript node and returns its result.
function Runtime:_execute(node)
	local data = internals[node]
	local source = fs.readFile(data.File)
	local env = table.clone(self.Globals)
	env.script = node
	env.require = function(target)
		return self:Require(target)
	end
	local chunk = luau.load(source, { debugName = data.File, environment = env })
	return chunk()
end

function Runtime:Run(path: string)
	return self:_execute(self:Find(path))
end

function Runtime.Internals(node)
	return internals[node]
end

-- Utility: source paths of every Luau file in the project (for compile checks).
function Runtime.ListSourceFiles(root: string?): { string }
	local out = {}
	local function walk(dir)
		local entries = fs.readDir(dir)
		table.sort(entries)
		for _, entry in entries do
			local full = dir .. "/" .. entry
			if fs.isDir(full) then
				walk(full)
			elseif string.match(entry, "%.luau$") then
				table.insert(out, full)
			end
		end
	end
	walk((root or ".") .. "/src")
	return out
end

Runtime.serde = serde

return Runtime
