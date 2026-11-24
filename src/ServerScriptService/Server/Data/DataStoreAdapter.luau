--[[
	DataStoreAdapter
	Returns a DataStore-like object. In live servers this is the real DataStore.
	In Studio without "Enable Studio Access to API Services", every DataStore call fails; in that case
	the adapter falls back to an in-memory store (data is NOT persisted) and warns loudly, so the game
	is still playable for testing.
]]

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local DataStoreAdapter = {}

local function createMemoryStore(name: string)
	local data = {}
	local store = { Name = name, IsMemory = true }
	function store:GetAsync(key)
		return data[key]
	end
	function store:SetAsync(key, value)
		data[key] = value
	end
	function store:UpdateAsync(key, transform)
		local result = transform(data[key])
		if result ~= nil then
			data[key] = result
		end
		return data[key]
	end
	function store:RemoveAsync(key)
		local old = data[key]
		data[key] = nil
		return old
	end
	return store
end

local function looksLikeNoApiAccess(err: any): boolean
	local text = tostring(err)
	return string.find(text, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(text, "403", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
end

function DataStoreAdapter.Get(name: string)
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(name)
	end)
	if ok and RunService:IsStudio() then
		-- Probe once: in Studio without API access, the first request fails immediately.
		local probeOk, probeErr = pcall(function()
			return store:GetAsync("__probe")
		end)
		if not probeOk and looksLikeNoApiAccess(probeErr) then
			ok = false
			store = probeErr
		end
	end
	if not ok then
		if RunService:IsStudio() then
			warn("[DataStoreAdapter] DataStores unavailable in Studio (" .. tostring(store) .. "). Using an in-memory store; progress will NOT be saved. Enable 'Studio Access to API Services' in Game Settings > Security to test saving.")
			return createMemoryStore(name)
		end
		error("[DataStoreAdapter] Could not open DataStore " .. name .. ": " .. tostring(store))
	end
	return store
end

DataStoreAdapter.CreateMemoryStore = createMemoryStore

return DataStoreAdapter
