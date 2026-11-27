--[[
	Session (Lune)
	A full client+server session for previews and client tests:
	  - REAL server services (tests/harness/ServerHarness) with a mid-game player
	  - REAL client (Main.client.luau + every controller) on fake Instances (FakeRoblox)
	  - in-process network bridge: client requests -> server handlers, server events -> client listeners
	Returns { Harness, Player, Data, Runtime, PlayerGui, Services, Camera, Controller(name), Units }.
]]

local task = require("@lune/task")

local Runtime = require("../../tests/harness/Runtime")
local ServerHarness = require("../../tests/harness/ServerHarness")
local Fake = require("./FakeRoblox")

local Session = {}

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[deepCopy(k)] = deepCopy(v)
	end
	return out
end

-- options.IconAssets: { [iconName] = local PNG path } shown instead of rbxassetids (preview of uploaded icons).
function Session.new(options: { IconAssets: { [string]: string }? }?)
	-- 1. Server with a world-1 player a few minutes into the game --------------------------------------------
	local h = ServerHarness.new({ BaseGame = true })
	local V = h.Vector3
	h.Services.UnitService.Random = h.Mocks.Random.new(21)
	h.Services.SummonService.Random = h.Mocks.Random.new(22)
	h.Services.EnemyService.Random = h.Mocks.Random.new(23)
	local player, data = h:AddPlayer(4242, "PreviewPlayer", V.new(0, 3, 0))
	local S = h.Services

	S.EconomyService:Add(player, "Yen", 5000, "Preview")
	for _ = 1, 8 do
		S.SummonService:Summon(player, "B_W1", 3)
	end
	local _, raizen = S.UnitService:CreateUnit(player, "SS_Raizen", { IgnoreCapacity = true, Source = "Preview" })
	local _, tetsuo = S.UnitService:CreateUnit(player, "SS_Tetsuo", { IgnoreCapacity = true, Source = "Preview" })
	S.UnitService:AddUnitXP(player, raizen.Uid, 6000)
	S.UnitService:AddUnitXP(player, tetsuo.Uid, 2500)
	S.UnitService:EquipBest(player)
	for _ = 1, 25 do
		local enemy = S.EnemyService:Spawn("W1_Bandit", V.new(3, 3, 0), "World:W1")
		S.EnemyService:ApplyDamage(player, enemy, 1e9)
	end
	data.Currencies.Yen = 2350

	-- 2. Network bridge ---------------------------------------------------------------------------------------
	local listeners: { [string]: { (...any) -> () } } = {}
	local function deliver(name, ...)
		for _, fn in listeners[name] or {} do
			task.spawn(fn, table.unpack(deepCopy(table.pack(...)), 1, select("#", ...)))
		end
	end
	local serverFire = h.Net.Fire
	h.Net.Fire = function(target, name, ...)
		serverFire(target, name, ...)
		if target == player then
			deliver(name, ...)
		end
	end
	local serverFireAll = h.Net.FireAll
	h.Net.FireAll = function(name, ...)
		serverFireAll(name, ...)
		deliver(name, ...)
	end

	local clientNet = {}
	function clientNet.Init() end
	function clientNet.Request(name, ...)
		return deepCopy(h.Net.Invoke(player, name, table.unpack(deepCopy(table.pack(...)), 1, select("#", ...))))
	end
	function clientNet.Connect(name, fn)
		listeners[name] = listeners[name] or {}
		table.insert(listeners[name], fn)
		return { Disconnect = function() end }
	end
	function clientNet.Send(name, ...)
		h.Net.Send(player, name, ...)
	end

	-- 3. Client ------------------------------------------------------------------------------------------------
	local rt = Runtime.new({ IsServer = false })
	local services, _, playerGui = Fake.CreateClientServices(function()
		return h.Now
	end)
	for name, service in services do
		rt.Services[name] = service
	end
	rt.Globals.workspace = services.Workspace
	rt.Globals.Instance = { new = Fake.new }
	rt.Globals.TweenInfo = Fake.TweenInfo
	rt.Globals.RaycastParams = Fake.RaycastParams
	rt:Mock("ReplicatedStorage/Shared/Remotes/Net", clientNet)
	if options and options.IconAssets then
		local assets = rt:Require("StarterPlayer/StarterPlayerScripts/Client/UI/IconAssets")
		for name, path in options.IconAssets do
			assets[name] = path
		end
	end

	rt:Run("StarterPlayer/StarterPlayerScripts/Client/Main")
	task.wait(0.3)

	local function controller(name)
		return rt:Require("StarterPlayer/StarterPlayerScripts/Client/Controllers/" .. name)
	end

	return {
		Harness = h,
		Player = player,
		Data = data,
		Runtime = rt,
		PlayerGui = playerGui,
		Services = services,
		Camera = services.Workspace.CurrentCamera,
		Net = clientNet,
		Controller = controller,
		Units = { Raizen = raizen, Tetsuo = tetsuo },
	}
end

return Session
