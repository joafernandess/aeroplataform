-- End-to-end checks: the real server entry point boots every service, and a full play session works
-- across services (combat -> rewards -> quests -> summon -> equip -> progression -> worlds -> raid -> save).
local Runtime = require("../harness/Runtime")
local Mocks = require("../harness/Mocks")
local ServerHarness = require("../harness/ServerHarness")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

return function(t)
	local expect = t.expect

	t.describe("boot", function()
		t.it("Main.server loads, inits and starts every service without errors", function()
			local rt = Runtime.new({ IsServer = true })
			local net = Mocks.FakeNet()
			rt:Mock("ReplicatedStorage/Shared/Remotes/Net", net)
			rt:Mock("ServerScriptService/Server/Combat/EnemyVisuals", {
				Create = function()
					return nil
				end,
				Update = function() end,
				Destroy = function() end,
				GetAreaCenter = function()
					return nil
				end,
			})
			-- A real (Lune) Workspace so MapService can build the greybox map.
			local dataModel = roblox.Instance.new("DataModel")
			local workspace = dataModel:GetService("Workspace")
			rt.Services.Workspace = workspace
			rt.Globals.workspace = workspace

			rt:Run("ServerScriptService/Server/Main")
			task.wait(0.05)

			for _, warning in rt.Mocks.Warnings do
				expect(string.find(string.lower(warning), "failed", 1, true) == nil).toBe(true)
			end
			for _, name in { "GetProfile", "Summon", "EquipUnit", "UnlockWorld", "ClaimQuest", "StartRaid", "BuyShopItem", "BuyUpgrade", "UpdateSetting", "AdminCommand" } do
				expect(net.Handlers[name] ~= nil).toBe(true)
			end
			expect(net.EventHandlers.SetTarget ~= nil).toBe(true)

			-- Base game greybox: world 1 only, with the summon orb (prompt role "Summon"), zones and decor
			local worlds = workspace:FindFirstChild("Worlds")
			expect(worlds ~= nil).toBe(true)
			expect(worlds:FindFirstChild("W2")).toBeNil()
			local w1 = worlds:FindFirstChild("W1")
			expect(w1:FindFirstChild("Spawn") ~= nil).toBe(true)
			local orb = w1:FindFirstChild("NPCs"):FindFirstChild("W1_SummonOrb")
			expect(orb ~= nil).toBe(true)
			local prompt = orb:FindFirstChildWhichIsA("ProximityPrompt", true)
			expect(prompt ~= nil and prompt:GetAttribute("Role") == "Summon").toBe(true)
			expect(#w1:FindFirstChild("NPCs"):GetChildren()).toBe(1)
			expect(#w1:FindFirstChild("Decor"):GetChildren() > 40).toBe(true)

			-- A joining player gets a profile through the real PlayerAdded wiring
			local players = rt:GetService("Players")
			local player = Mocks.FakePlayer(9001, "Booted")
			players:AddPlayer(player)
			local response = net.Invoke(player, "GetProfile")
			expect(response.ok).toBe(true)
			expect(#response.data.EquippedUnits).toBe(1)
			expect(response.data.Quests.MainCurrent).toBe("M01")
		end)
	end)

	t.describe("full session", function()
		t.it("plays through the core loop and persists everything", function()
			local h = ServerHarness.new()
			local V = h.Vector3
			h.Services.EnemyService.Random = h.Mocks.Random.new(11)
			h.Services.UnitService.Random = h.Mocks.Random.new(12)
			h.Services.SummonService.Random = h.Mocks.Random.new(13)
			h.Services.CombatService.Random = h.Mocks.Random.new(14)
			h.Services.RaidService.EndDelay = 0
			local player, data = h:AddPlayer(4242, "Hero", V.new(60, 3, 0))
			local Enemy, Combat = h.Services.EnemyService, h.Services.CombatService

			-- 1. Fight: spawn world enemies and let units auto-attack until M01 (10 Bandits) is done.
			Enemy:StepSpawners(h.PreciseNow)
			local guard = 0
			while not data.Quests.Active.M01.Completed and guard < 20000 do
				guard += 1
				h:Advance(0.1)
				Combat:Step(h.PreciseNow)
				Enemy:StepSpawners(h.PreciseNow)
				-- walk to the nearest enemy, like a real player would
				local nearest = Enemy:FindNearest("World:W1", player.Character.HumanoidRootPart.Position, 1000)
				if nearest then
					player.Character.HumanoidRootPart.Position = nearest.Position + V.new(2, 0, 0)
				end
			end
			expect(data.Quests.Active.M01.Completed).toBe(true)
			expect(data.Stats.TotalKills >= 10).toBe(true)
			expect(data.Currencies.Yen > 250).toBe(true)

			-- 2. Claim the quest, which unlocks M02 (summon 3 units).
			expect(h:Invoke(player, "ClaimQuest", "M01").ok).toBe(true)
			expect(data.Quests.MainCurrent).toBe("M02")

			-- 3. Summon x1 three times with starting gems + quest gems.
			data.Currencies.Yen += 500
			for _ = 1, 3 do
				expect(h:Invoke(player, "Summon", "B_W1", 1).ok).toBe(true)
			end
			expect(data.Quests.Active.M02.Completed).toBe(true)
			expect(h:Invoke(player, "ClaimQuest", "M02").ok).toBe(true)

			-- 4. Equip best + buy a damage upgrade.
			expect(h:Invoke(player, "EquipBest").ok).toBe(true)
			expect(#data.EquippedUnits).toBe(3)
			expect(h:Invoke(player, "BuyUpgrade", "Damage").ok).toBe(true)

			-- 5. Level up through XP, unlock + teleport to world 2.
			h.Services.ProgressionService:AddPlayerXP(player, 50000)
			expect(data.Level >= 10).toBe(true)
			data.Currencies.Yen += 25000
			expect(h:Invoke(player, "UnlockWorld", "W2").ok).toBe(true)
			expect(h:Invoke(player, "TeleportWorld", "W2").ok).toBe(true)
			expect(h.Services.WorldService:GetZoneKey(player)).toBe("World:W2")

			-- 6. Raid (admin unlocks W3 to reach the raid requirements).
			expect(h:Invoke(player, "AdminCommand", "unlockall").ok).toBe(true)
			expect(h:Invoke(player, "AdminCommand", "level", { Level = 30 }).ok).toBe(true)
			expect(h:Invoke(player, "StartRaid", "RAID_Abyss").ok).toBe(true)
			local zone = h.Services.WorldService:GetZoneKey(player)
			for _ = 1, 3 do
				for _, enemy in Enemy:GetEnemiesInZone(zone) do
					Enemy:ApplyDamage(player, enemy, 1e15)
				end
			end
			task.wait(0.05)
			expect(data.Stats.RaidsCompleted).toBe(1)
			expect(h.Services.WorldService:GetZoneKey(player)).toBe("World:W2")

			-- 7. Leave: everything persists and reloads identically on another server.
			local snapshot = h.Runtime:Require("ReplicatedStorage/Shared/Modules/TableUtil").DeepCopy(data)
			h.Services.DataService:ReleaseProfile(player)
			local store = h.Services.DataService:_getStore()
			local h2 = ServerHarness.new()
			h2.Services.DataService:SetStore(store)
			local _, reloaded = h2:AddPlayer(4242, "Hero")
			for _, key in { "Level", "CurrentWorld", "NextUnitSerial" } do
				expect(reloaded[key]).toBe(snapshot[key])
			end
			expect(reloaded.Currencies.Yen).toBe(snapshot.Currencies.Yen)
			expect(reloaded.Currencies.Gems).toBe(snapshot.Currencies.Gems)
			expect(reloaded.Stats.RaidsCompleted).toBe(1)
			expect(reloaded.Quests.MainCompleted.M02).toBe(true)
			expect(#reloaded.EquippedUnits).toBe(3)
			for uid, unit in snapshot.Inventory.Units do
				expect(reloaded.Inventory.Units[uid].UnitId).toBe(unit.UnitId)
				expect(reloaded.Inventory.Units[uid].Level).toBe(unit.Level)
			end
		end)
	end)
end
