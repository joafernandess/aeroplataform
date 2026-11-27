--[[
	Net
	Single networking layer for client and server.

	Server:
	  Net.Handle(name, handler, options?)   handler(player, ...) -> (ok: boolean, dataOrErrorCode)
	  Net.On(name, handler, options?)       handler(player, ...) for ClientEvents
	  Net.Fire(player, name, ...) / Net.FireAll(name, ...)
	Client:
	  Net.Request(name, ...) -> { ok, data?, error? }
	  Net.Connect(name, fn)
	  Net.Send(name, ...)

	Every server entry point is rate limited per player and wrapped in pcall: a bug in one handler returns
	"InternalError" to the caller instead of throwing on the client or killing the server thread.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = script.Parent.Parent
local GameConfig = require(Shared.Config.GameConfig)
local RateLimiter = require(Shared.Modules.RateLimiter)
local RemoteNames = require(script.Parent.RemoteNames)

local IS_SERVER = RunService:IsServer()
local NETWORK = GameConfig.Network

local Net = {}

local folder: Instance? = nil
local remotes: { [string]: Instance } = {}
local limiters: { [string]: any } = {}

local KIND: { [string]: string } = {}
for _, name in RemoteNames.Functions do
	KIND[name] = "RemoteFunction"
end
for _, name in RemoteNames.ServerEvents do
	KIND[name] = "RemoteEvent"
end
for _, name in RemoteNames.ClientEvents do
	KIND[name] = "RemoteEvent"
end

local function getFolder(): Instance
	if folder then
		return folder
	end
	if IS_SERVER then
		local existing = ReplicatedStorage:FindFirstChild(NETWORK.FolderName)
		if not existing then
			existing = Instance.new("Folder")
			existing.Name = NETWORK.FolderName
			existing.Parent = ReplicatedStorage
		end
		folder = existing
		for name, className in KIND do
			if not existing:FindFirstChild(name) then
				local remote = Instance.new(className)
				remote.Name = name
				remote.Parent = existing
			end
		end
	else
		folder = ReplicatedStorage:WaitForChild(NETWORK.FolderName)
	end
	return folder :: Instance
end

local function getRemote(name: string): any
	local cached = remotes[name]
	if cached then
		return cached
	end
	assert(KIND[name], "Unknown remote: " .. tostring(name))
	local parent = getFolder()
	local remote = if IS_SERVER then parent:FindFirstChild(name) else parent:WaitForChild(name)
	assert(remote, "Remote missing: " .. name)
	remotes[name] = remote
	return remote
end

local function getLimiter(name: string, options: { RateLimit: number?, Burst: number? }?)
	local limiter = limiters[name]
	if not limiter then
		local rate = (options and options.RateLimit) or NETWORK.DefaultRateLimit
		local burst = (options and options.Burst) or math.max(rate * 2, NETWORK.DefaultBurst)
		limiter = RateLimiter.new(rate, burst)
		limiters[name] = limiter
	end
	return limiter
end

-- Server ---------------------------------------------------------------------------------

function Net.Init()
	if IS_SERVER then
		getFolder()
	end
end

function Net.Handle(name: string, handler: (Player, ...any) -> (boolean, any), options: { RateLimit: number?, Burst: number? }?)
	assert(IS_SERVER, "Net.Handle is server-only")
	assert(KIND[name] == "RemoteFunction", name .. " is not a RemoteFunction")
	local limiter = getLimiter(name, options)
	local remote = getRemote(name)
	remote.OnServerInvoke = function(player: Player, ...)
		if not limiter:Check(player) then
			return { ok = false, error = "RateLimited" }
		end
		local success, ok, result = pcall(handler, player, ...)
		if not success then
			warn(("[Net] %s handler errored for %s: %s"):format(name, player.Name, tostring(ok)))
			return { ok = false, error = "InternalError" }
		end
		if ok then
			return { ok = true, data = result }
		end
		return { ok = false, error = if type(result) == "string" then result else "InternalError" }
	end
end

function Net.On(name: string, handler: (Player, ...any) -> (), options: { RateLimit: number?, Burst: number? }?)
	assert(IS_SERVER, "Net.On is server-only")
	assert(table.find(RemoteNames.ClientEvents, name), name .. " is not a client event")
	local limiter = getLimiter(name, options)
	return getRemote(name).OnServerEvent:Connect(function(player: Player, ...)
		if not limiter:Check(player) then
			return
		end
		local success, err = pcall(handler, player, ...)
		if not success then
			warn(("[Net] %s event errored for %s: %s"):format(name, player.Name, tostring(err)))
		end
	end)
end

function Net.Fire(player: Player, name: string, ...: any)
	getRemote(name):FireClient(player, ...)
end

function Net.FireAll(name: string, ...: any)
	getRemote(name):FireAllClients(...)
end

function Net.CleanupPlayer(player: Player)
	for _, limiter in limiters do
		limiter:Remove(player)
	end
end

-- Client ---------------------------------------------------------------------------------

function Net.Request(name: string, ...: any): { ok: boolean, data: any?, error: string? }
	assert(not IS_SERVER, "Net.Request is client-only")
	local remote = getRemote(name)
	local success, response = pcall(remote.InvokeServer, remote, ...)
	if not success or type(response) ~= "table" then
		return { ok = false, error = "InternalError" }
	end
	return response
end

function Net.Connect(name: string, fn: (...any) -> ())
	assert(not IS_SERVER, "Net.Connect is client-only")
	return getRemote(name).OnClientEvent:Connect(fn)
end

function Net.Send(name: string, ...: any)
	assert(not IS_SERVER, "Net.Send is client-only")
	getRemote(name):FireServer(...)
end

return Net
