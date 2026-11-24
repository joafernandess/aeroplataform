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

function Session.new()
	-- 1. Server with a mid-game player --------------------------------------------------------------------
	local h = ServerHarness.new()
	local V = h.Vector3
	h.Services.UnitService.Random = h.Mocks.Random.new(21)
	h.Services.SummonService.Random = h.Mocks.Random.new(22)
	h.Services.EnemyService.Random = h.Mocks.Random.new(23)
	while h.Clock.Weekday(h.Now) ~= 7 do -- Saturday: the weekend Yen event is active
		h:Advance(86400)
	end
	local player, data = h:AddPlayer(4242, "PreviewPlayer", V.new(0, 3, 0))
	local S = h.Services

	data.Level = 25
	data.UnlockedWorlds.W2 = true
	data.UnlockedWorlds.W3 = true
	data.ClearedWorlds.W1 = true
	data.CurrentWorld = "W2"
	S.EconomyService:Add(player, "Gems", 20000, "Preview")
	for _ = 1, 3 do
		S.SummonService:Summon(player, "B_W1", 10)
	end
	for _ = 1, 2 do
		S.SummonService:Summon(player, "B_W2", 10)
	end
	S.SummonService:Summon(player, "B_W3", 10)
	local _, raizen = S.UnitService:CreateUnit(player, "SS_Raizen", { Trait = "Swift", IgnoreCapacity = true })
	local _, leviath = S.UnitService:CreateUnit(player, "GT_Leviath", { Trait = "Mighty", IgnoreCapacity = true })
	S.UnitService:CreateUnit(player, "SR_Hollowking", { Trait = "Golden", IgnoreCapacity = true })
	S.UnitService:AddUnitXP(player, raizen.Uid, 400000)
	S.UnitService:AddUnitXP(player, leviath.Uid, 90000)
	raizen.Stars = 2
	S.ProgressionService:AddPlayerXP(player, 70000)
	data.Upgrades = { Damage = 12, Yen = 8, Luck = 3, EquipSlots = 1, UnitStorage = 2, XP = 4 }
	data.Damage = 12
	S.UnitService:EquipBest(player)
	for itemId, count in { XPPotionSmall = 14, XPPotionMedium = 5, EvolutionStone = 2, ShinobiScroll = 3, TideCompass = 4, TraitCrystal = 1, DamageBoost2x = 2, YenBoost2x = 1, GemPouch = 3 } do
		S.InventoryService:AddItem(player, itemId, count, "Preview")
	end
	S.BoostService:Activate(player, "Yen", 2, 640)
	data.Currencies.Yen = 1284500
	data.Currencies.Gems = 3450
	data.Currencies.Gold = 820
	data.Currencies.Tokens = 140
	for _ = 1, 7 do
		local enemy = S.EnemyService:Spawn("W1_Bandit", V.new(3, 3, 0), "World:W1")
		S.EnemyService:ApplyDamage(player, enemy, 1e9)
	end
	data.Stats.TotalKills = 1840
	data.Stats.BossKills = 12
	data.Currencies.Yen = 1284500

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
		Units = { Raizen = raizen, Leviath = leviath },
	}
end

return Session
