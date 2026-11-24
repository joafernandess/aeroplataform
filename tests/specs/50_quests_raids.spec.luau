local ServerHarness = require("../harness/ServerHarness")
local task = require("@lune/task")

return function(t)
	local expect = t.expect

	local function setup(userId)
		local h = ServerHarness.new()
		h.Services.EnemyService.Random = h.Mocks.Random.new(3)
		h.Services.UnitService.Random = h.Mocks.Random.new(4)
		h.Services.SummonService.Random = h.Mocks.Random.new(5)
		local player, data = h:AddPlayer(userId or 500, "Quester", h.Vector3.new(0, 3, 0))
		return h, player, data, h.Vector3
	end

	local function kill(h, player, enemyId, times)
		for _ = 1, times or 1 do
			local enemy = h.Services.EnemyService:Spawn(enemyId, h.Vector3.new(3, 3, 0), "World:W1")
			h.Services.EnemyService:ApplyDamage(player, enemy, 1e15)
		end
	end

	t.describe("QuestService", function()
		t.it("starts the main chain and today's dailies on first join", function()
			local h, _, data = setup()
			expect(data.Quests.MainCurrent).toBe("M01")
			expect(data.Quests.Active.M01).toBeTruthy()
			local dailies = 0
			for id in data.Quests.Active do
				if string.sub(id, 1, 2) == "D_" then
					dailies += 1
				end
			end
			expect(dailies).toBe(h.GameConfig.Quests.DailyQuestCount)
		end)

		t.it("tracks kills with filters, claims once and advances the chain", function()
			local h, player, data = setup()
			kill(h, player, "W1_RogueNinja", 3) -- wrong enemy for M01
			expect(data.Quests.Active.M01.Progress).toBe(0)
			expect(h:Invoke(player, "ClaimQuest", "M01").error).toBe("QuestNotComplete")
			kill(h, player, "W1_Bandit", 12)
			expect(data.Quests.Active.M01.Completed).toBe(true)
			expect(data.Quests.Active.M01.Progress).toBe(10)
			local yen = data.Currencies.Yen
			expect(h:Invoke(player, "ClaimQuest", "M01").ok).toBe(true)
			expect(data.Currencies.Yen).toBe(yen + 150)
			expect(data.Quests.MainCompleted.M01).toBe(true)
			expect(data.Quests.MainCurrent).toBe("M02")
			expect(h:Invoke(player, "ClaimQuest", "M01").error).toBe("QuestNotFound")
		end)

		t.it("tracks summons for the summon quest", function()
			local h, player, data = setup()
			data.Quests.Active = {}
			data.Quests.MainCurrent = "M02"
			h.Services.QuestService:EnsureMainQuest(player)
			data.Currencies.Yen = 1000
			h:Invoke(player, "Summon", "B_W1", 1)
			h:Invoke(player, "Summon", "B_W1", 1)
			expect(data.Quests.Active.M02.Progress).toBe(2)
			h:Invoke(player, "Summon", "B_W1", 1)
			expect(data.Quests.Active.M02.Completed).toBe(true)
		end)

		t.it("ReachLevel quests use the current level on activation", function()
			local h, player, data = setup()
			data.Level = 7
			data.Quests.Active = {}
			data.Quests.MainCurrent = "M04"
			h.Services.QuestService:EnsureMainQuest(player)
			expect(data.Quests.Active.M04.Completed).toBe(true)
		end)

		t.it("rerolls dailies on a new UTC day and is deterministic per day", function()
			local h, player, data = setup(777)
			local first = {}
			for id in data.Quests.Active do
				first[id] = true
			end
			data.Quests.DailyDay = 0
			h.Services.QuestService:RefreshDailies(player)
			for id in data.Quests.Active do
				expect(first[id]).toBe(true)
			end
			local day = data.Quests.DailyDay
			h:Advance(86400)
			expect(h.Services.QuestService:RefreshDailies(player)).toBe(true)
			expect(data.Quests.DailyDay).toBe(day + 1)
			expect(data.Quests.Active.M01).toBeTruthy()
		end)

		t.it("daily claims are idempotent per day", function()
			local h, player, data = setup()
			local dailyId
			for id in data.Quests.Active do
				if string.sub(id, 1, 2) == "D_" then
					dailyId = id
					break
				end
			end
			local entry = data.Quests.Active[dailyId]
			entry.Progress = 1e9
			entry.Completed = true
			expect(h:Invoke(player, "ClaimQuest", dailyId).ok).toBe(true)
			expect(h:Invoke(player, "ClaimQuest", dailyId).error).toBe("AlreadyClaimed")
		end)
	end)

	t.describe("AchievementService", function()
		t.it("claims tiers in order when the stat goal is reached", function()
			local h, player, data = setup()
			expect(h:Invoke(player, "ClaimAchievement", "A_Kills").error).toBe("QuestNotComplete")
			data.Stats.TotalKills = 1500
			local gems = data.Currencies.Gems
			expect(h:Invoke(player, "ClaimAchievement", "A_Kills").ok).toBe(true)
			expect(h:Invoke(player, "ClaimAchievement", "A_Kills").ok).toBe(true)
			expect(h:Invoke(player, "ClaimAchievement", "A_Kills").error).toBe("QuestNotComplete")
			expect(data.Achievements.A_Kills).toBe(2)
			expect(data.Currencies.Gems).toBe(gems + 70)
		end)
	end)

	t.describe("RaidService", function()
		local function raidReady(h, player, data)
			data.UnlockedWorlds.W3 = true
			data.Level = 30
			h.Services.RaidService.EndDelay = 0
		end

		t.it("enforces requirements and cooldowns", function()
			local h, player, data = setup()
			expect(h:Invoke(player, "StartRaid", "RAID_Abyss").error).toBe("RequirementsNotMet")
			raidReady(h, player, data)
			expect(h:Invoke(player, "StartRaid", "RAID_Abyss").ok).toBe(true)
			expect(h:Invoke(player, "StartRaid", "RAID_Abyss").error).toBe("AlreadyInRaid")
			expect(h:Invoke(player, "LeaveRaid").ok).toBe(true)
			expect(h:Invoke(player, "StartRaid", "RAID_Abyss").error).toBe("RaidOnCooldown")
			h:Advance(601)
			expect(h:Invoke(player, "StartRaid", "RAID_Abyss").ok).toBe(true)
		end)

		t.it("runs waves in a private zone and grants completion rewards", function()
			local h, player, data = setup()
			raidReady(h, player, data)
			local Raid, Enemy, World = h.Services.RaidService, h.Services.EnemyService, h.Services.WorldService
			local response = h:Invoke(player, "StartRaid", "RAID_Abyss")
			expect(response.ok).toBe(true)
			local zone = World:GetZoneKey(player)
			expect(string.sub(zone, 1, 5)).toBe("Raid:")
			expect(Enemy:CountInZone(zone)).toBe(6)
			-- Another player in the world cannot target raid enemies
			local other = h:AddPlayer(501, "Outsider", h.Vector3.new(0, 3, 0))
			local raidEnemy = Enemy:GetEnemiesInZone(zone)[1]
			expect((h.Services.CombatService:SetTarget(other, raidEnemy.Id))).toBe(false)

			local tokens = data.Currencies.Tokens
			for wave = 1, 3 do
				for _, enemy in Enemy:GetEnemiesInZone(zone) do
					Enemy:ApplyDamage(player, enemy, 1e15)
				end
				if wave < 3 then
					expect(Raid:GetInstance(player).Wave).toBe(wave + 1)
				end
			end
			task.wait(0.05)
			expect(data.Stats.RaidsCompleted).toBe(1)
			expect(data.Currencies.Tokens >= tokens + 40).toBe(true)
			expect(Raid:GetPlayerZone(player)).toBeNil()
			expect(World:GetZoneKey(player)).toBe("World:W1")
			expect(Enemy:CountInZone(zone)).toBe(0)
		end)

		t.it("fails on timeout and cleans up the zone", function()
			local h, player, data = setup()
			raidReady(h, player, data)
			h:Invoke(player, "StartRaid", "RAID_Abyss")
			local zone = h.Services.WorldService:GetZoneKey(player)
			h:Advance(241)
			h.Services.RaidService:Step()
			expect(h.Services.RaidService:GetPlayerZone(player)).toBeNil()
			expect(h.Services.EnemyService:CountInZone(zone)).toBe(0)
			expect(data.Stats.RaidsCompleted).toBe(0)
		end)

		t.it("charges the entry cost and refunds nothing on voluntary leave", function()
			local h, player, data = setup()
			data.UnlockedWorlds.W5 = true
			data.Level = 80
			data.Currencies.Gold = 150
			expect(h:Invoke(player, "StartRaid", "RAID_Dread").error).toBe("NotEnoughCurrency")
			data.Currencies.Gold = 250
			expect(h:Invoke(player, "StartRaid", "RAID_Dread").ok).toBe(true)
			expect(data.Currencies.Gold).toBe(50)
		end)
	end)

	t.describe("SettingsService + AdminService", function()
		t.it("validates settings types and ranges", function()
			local h, player, data = setup()
			expect(h:Invoke(player, "UpdateSetting", "AutoAttack", false).ok).toBe(true)
			expect(data.Settings.AutoAttack).toBe(false)
			expect(h:Invoke(player, "UpdateSetting", "MusicVolume", 2).error).toBe("InvalidArguments")
			expect(h:Invoke(player, "UpdateSetting", "MusicVolume", 0 / 0).error).toBe("InvalidArguments")
			expect(h:Invoke(player, "UpdateSetting", "Currencies", 5).error).toBe("InvalidArguments")
		end)

		t.it("runs admin commands through regular services (Studio = admin)", function()
			local h, player, data = setup()
			local gems = data.Currencies.Gems
			expect(h:Invoke(player, "AdminCommand", "give", { Currency = "Gems", Amount = 100 }).ok).toBe(true)
			expect(data.Currencies.Gems).toBe(gems + 100)
			expect(h:Invoke(player, "AdminCommand", "unit", { UnitId = "DV_Celestia" }).ok).toBe(true)
			expect(h:Invoke(player, "AdminCommand", "nope").error).toBe("InvalidArguments")
			expect(h:Invoke(player, "AdminCommand", "give", { Currency = "Gems", Amount = 0 / 0 }).ok).toBe(false)
		end)
	end)
end
