--[[
	Mocks (Lune)
	In-memory stand-ins for the Roblox services/globals the game code touches.
]]

local serde = require("@lune/serde")

local Mocks = {}

-- Random --------------------------------------------------------------------------------
-- Deterministic LCG so seeded tests are reproducible. Mirrors Roblox's Random API.
local RandomClass = {}
RandomClass.__index = RandomClass

local seedCounter = 12345

function RandomClass.new(seed: number?)
	if seed == nil then
		seedCounter += 7919
		seed = seedCounter
	end
	return setmetatable({ _state = math.floor(seed :: number) % 2147483647 + 1 }, RandomClass)
end

function RandomClass:_next(): number
	self._state = (self._state * 48271) % 2147483647
	return (self._state - 1) / 2147483646
end

function RandomClass:NextNumber(min: number?, max: number?): number
	local r = self:_next()
	if min and max then
		return min + r * (max - min)
	end
	return r
end

function RandomClass:NextInteger(min: number, max: number): number
	return min + math.floor(self:_next() * (max - min + 1))
end

Mocks.Random = RandomClass

-- Scripted generator: returns the given NextNumber values in order (then repeats the last one).
function Mocks.ScriptedRandom(values: { number })
	local index = 0
	return {
		NextNumber = function(_, min, max)
			index = math.min(index + 1, #values)
			local r = values[index]
			if min and max then
				return min + r * (max - min)
			end
			return r
		end,
		NextInteger = function(_, min, max)
			index = math.min(index + 1, #values)
			return min + math.floor(values[index] * (max - min + 1))
		end,
	}
end

-- Signals ------------------------------------------------------------------------------
function Mocks.FakeSignal()
	local signal = { _handlers = {} }
	function signal:Connect(fn)
		local connection = { Connected = true }
		function connection.Disconnect()
			connection.Connected = false
		end
		table.insert(self._handlers, { fn = fn, connection = connection })
		return connection
	end
	function signal:Fire(...)
		for _, entry in table.clone(self._handlers) do
			if entry.connection.Connected then
				entry.fn(...)
			end
		end
	end
	function signal:Wait()
		return nil
	end
	return signal
end

-- Players -------------------------------------------------------------------------------
function Mocks.FakePlayer(userId: number, name: string?)
	local player = {
		UserId = userId,
		Name = name or ("Player" .. userId),
		DisplayName = name or ("Player" .. userId),
		Character = nil,
		Parent = true,
		Kicked = nil,
		_attributes = {},
		CharacterAdded = Mocks.FakeSignal(),
	}
	function player:Kick(message)
		self.Kicked = message or true
	end
	function player:GetAttribute(key)
		return self._attributes[key]
	end
	function player:SetAttribute(key, value)
		self._attributes[key] = value
	end
	function player:IsA(className)
		return className == "Player"
	end
	return player
end

-- Character stub with a HumanoidRootPart at `position` (a Vector3).
function Mocks.FakeCharacter(position)
	local humanoid = { Health = 100, MaxHealth = 100, Damage = 0 }
	function humanoid:TakeDamage(amount)
		self.Health = math.max(0, self.Health - amount)
		self.Damage += amount
	end
	local root = { Position = position }
	local character = { HumanoidRootPart = root, Humanoid = humanoid, Parent = true }
	function character:FindFirstChild(name)
		return self[name]
	end
	function character:FindFirstChildOfClass(className)
		if className == "Humanoid" then
			return humanoid
		end
		return nil
	end
	function character:PivotTo(cframe)
		root.Position = cframe.Position
	end
	return character
end

-- DataStore -------------------------------------------------------------------------------
local function roundTrip(value)
	if value == nil then
		return nil
	end
	-- Serialising mimics the DataStore: non-JSON-able data fails here just like in Roblox.
	return serde.decode("json", serde.encode("json", value))
end

function Mocks.FakeDataStore(name: string)
	local store = { Name = name, Data = {}, FailNext = {}, Calls = {} }
	local function maybeFail(method)
		store.Calls[method] = (store.Calls[method] or 0) + 1
		local remaining = store.FailNext[method]
		if remaining and remaining > 0 then
			store.FailNext[method] = remaining - 1
			error("Mock DataStore failure (" .. method .. ")")
		end
	end
	function store:GetAsync(key)
		maybeFail("GetAsync")
		return roundTrip(self.Data[key])
	end
	function store:SetAsync(key, value)
		maybeFail("SetAsync")
		self.Data[key] = roundTrip(value)
	end
	function store:UpdateAsync(key, transform)
		maybeFail("UpdateAsync")
		local result = transform(roundTrip(self.Data[key]))
		if result ~= nil then
			self.Data[key] = roundTrip(result)
		end
		return roundTrip(self.Data[key])
	end
	function store:RemoveAsync(key)
		maybeFail("RemoveAsync")
		local old = self.Data[key]
		self.Data[key] = nil
		return old
	end
	return store
end

-- Service mocks ------------------------------------------------------------------------------
function Mocks.create(runtime)
	local context = { Warnings = {}, CloseCallbacks = {}, Stores = {} }

	local players = { _list = {}, PlayerAdded = Mocks.FakeSignal(), PlayerRemoving = Mocks.FakeSignal(), LocalPlayer = nil }
	function players:GetPlayers()
		return table.clone(self._list)
	end
	function players:GetPlayerByUserId(userId)
		for _, p in self._list do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end
	function players:AddPlayer(player)
		table.insert(self._list, player)
		self.PlayerAdded:Fire(player)
	end
	function players:RemovePlayer(player)
		self.PlayerRemoving:Fire(player)
		local index = table.find(self._list, player)
		if index then
			table.remove(self._list, index)
		end
		player.Parent = nil
	end

	local dataStoreService = {}
	function dataStoreService:GetDataStore(name)
		local store = context.Stores[name]
		if not store then
			store = Mocks.FakeDataStore(name)
			context.Stores[name] = store
		end
		return store
	end

	local runService = { Heartbeat = Mocks.FakeSignal(), Stepped = Mocks.FakeSignal(), RenderStepped = Mocks.FakeSignal() }
	function runService:IsServer()
		return runtime.IsServer
	end
	function runService:IsClient()
		return not runtime.IsServer
	end
	function runService:IsStudio()
		return true
	end

	local guidCounter = 0
	local httpService = {}
	function httpService:JSONEncode(value)
		return serde.encode("json", value)
	end
	function httpService:JSONDecode(text)
		return serde.decode("json", text)
	end
	function httpService:GenerateGUID(wrap)
		guidCounter += 1
		local guid = string.format("00000000-0000-0000-0000-%012d", guidCounter)
		return if wrap == false then guid else "{" .. guid .. "}"
	end

	local marketplace = { Owned = {}, PromptGamePassPurchaseFinished = Mocks.FakeSignal() }
	function marketplace:UserOwnsGamePassAsync(userId, passId)
		return self.Owned[userId .. ":" .. passId] == true
	end

	local workspace = { Name = "Workspace", _children = {} }
	function workspace:FindFirstChild(name)
		return self._children[name]
	end
	function workspace:WaitForChild(name)
		return self._children[name]
	end

	context.Services = {
		Players = players,
		DataStoreService = dataStoreService,
		RunService = runService,
		HttpService = httpService,
		MarketplaceService = marketplace,
		Workspace = workspace,
	}
	return context
end

-- Net fake ----------------------------------------------------------------------------------
-- Mirrors Shared/Remotes/Net's server API and response envelope, but stores handlers in a table
-- so tests can call them exactly like a client would.
function Mocks.FakeNet()
	local net = { Handlers = {}, EventHandlers = {}, Fired = {}, FiredAll = {} }
	function net.Init() end
	function net.Handle(name, handler)
		net.Handlers[name] = handler
	end
	function net.On(name, handler)
		net.EventHandlers[name] = handler
	end
	function net.Fire(player, name, ...)
		net.Fired[player] = net.Fired[player] or {}
		net.Fired[player][name] = net.Fired[player][name] or {}
		table.insert(net.Fired[player][name], table.pack(...))
	end
	function net.FireAll(name, ...)
		net.FiredAll[name] = net.FiredAll[name] or {}
		table.insert(net.FiredAll[name], table.pack(...))
	end
	function net.CleanupPlayer() end
	-- Simulates a client request; returns the same envelope as the real Net.
	function net.Invoke(player, name, ...)
		local handler = net.Handlers[name]
		assert(handler, "No handler registered for " .. name)
		local success, ok, result = pcall(handler, player, ...)
		if not success then
			return { ok = false, error = "InternalError", trace = ok }
		end
		if ok then
			return { ok = true, data = result }
		end
		return { ok = false, error = result }
	end
	function net.Send(player, name, ...)
		local handler = net.EventHandlers[name]
		assert(handler, "No event handler registered for " .. name)
		handler(player, ...)
	end
	function net.LastFired(player, name)
		local list = net.Fired[player] and net.Fired[player][name]
		return list and list[#list]
	end
	return net
end

return Mocks
