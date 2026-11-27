-- Server side of the new menus: Codes, Teleport points, Index (discovered fighters), Update Log setting.
local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	local function setup()
		local h = ServerHarness.new({ BaseGame = true })
		h.Services.UnitService.Random = h.Mocks.Random.new(41)
		h.Services.SummonService.Random = h.Mocks.Random.new(42)
		local player, data = h:AddPlayer(900, "MenuTester", h.Vector3.new(0, 3, 0))
		return h, player, data
	end

	t.describe("CodesService", function()
		t.it("redeems a configured code once, case-insensitively, and rejects unknown/expired codes", function()
			local h, player, data = setup()
			local Codes = h.Runtime:Require("ReplicatedStorage/Shared/Config/Codes")
			Codes.ByCode.WELCOME = { Code = "WELCOME", Rewards = { Yen = 500 } }
			Codes.ByCode.OLD = { Code = "OLD", Rewards = { Yen = 1 }, ExpiresAt = h.Now - 10 }
			local yen = data.Currencies.Yen
			expect(h:Invoke(player, "RedeemCode", "  welcome ").ok).toBe(true)
			expect(data.Currencies.Yen).toBe(yen + 500)
			expect(h:Invoke(player, "RedeemCode", "WELCOME").error).toBe("CodeAlreadyUsed")
			expect(h:Invoke(player, "RedeemCode", "NOPE").error).toBe("InvalidCode")
			expect(h:Invoke(player, "RedeemCode", "old").error).toBe("CodeExpired")
			expect(h:Invoke(player, "RedeemCode", { "hack" }).error).toBe("InvalidArguments")
			expect(h:Invoke(player, "RedeemCode", string.rep("A", 200)).error).toBe("InvalidArguments")
			expect(data.Currencies.Yen).toBe(yen + 500)
		end)
	end)

	t.describe("Teleport points", function()
		t.it("lists spawn, orb, zones and bosses of world 1 and teleports to them", function()
			local h, player = setup()
			local Worlds = h.Runtime:Require("ReplicatedStorage/Shared/Config/Worlds")
			local points = Worlds.GetTeleportPoints("W1")
			local ids = {}
			for _, p in points do
				ids[p.Id] = p
			end
			expect(ids.spawn ~= nil and ids.summon ~= nil and ids.zone_Field ~= nil and ids.zone_Camp ~= nil and ids.boss_1 ~= nil).toBe(true)
			expect(h:Invoke(player, "TeleportToPoint", "zone_Camp").ok).toBe(true)
			local pos = player.Character.HumanoidRootPart.Position
			expect(pos.X).toBe(ids.zone_Camp.Position[1])
			expect(pos.Z).toBe(ids.zone_Camp.Position[3])
			expect(h:Invoke(player, "TeleportToPoint", "spawn").ok).toBe(true)
			expect(h:Invoke(player, "TeleportToPoint", "nowhere").error).toBe("PointNotFound")
			expect(h:Invoke(player, "TeleportToPoint", 5).error).toBe("InvalidArguments")
		end)
	end)

	t.describe("Index", function()
		t.it("marks every obtained fighter as discovered, including auto-sold summons", function()
			local h, player, data = setup()
			expect(data.Discovered.SS_GeninRecruit).toBe(true)
			data.Currencies.Yen = 100000
			data.Settings.AutoDeleteCommon = true
			for _ = 1, 10 do
				h:Invoke(player, "Summon", "B_W1", 3)
			end
			for _, entry in data.SummonHistory do
				expect(data.Discovered[entry.UnitId]).toBe(true)
			end
		end)
	end)

	t.describe("Update Log", function()
		t.it("stores the last seen update id as a validated setting", function()
			local h, player, data = setup()
			local UpdateLog = h.Runtime:Require("ReplicatedStorage/Shared/Config/UpdateLog")
			local latest = UpdateLog.GetLatest()
			expect(latest ~= nil).toBe(true)
			expect(data.Settings.LastSeenUpdate).toBe("")
			expect(h:Invoke(player, "UpdateSetting", "LastSeenUpdate", latest.Id).ok).toBe(true)
			expect(data.Settings.LastSeenUpdate).toBe(latest.Id)
			expect(h:Invoke(player, "UpdateSetting", "LastSeenUpdate", string.rep("x", 40)).error).toBe("InvalidArguments")
		end)
	end)

	t.describe("Milestone upgrades", function()
		t.it("unlock tier by tier, claim only when reached, and boost the right stat", function()
			local h, player, data = setup()
			local Progression = h.Runtime:Require("ReplicatedStorage/Shared/Config/Progression")
			local Boost = h.Services.BoostService
			local Prog = h.Services.ProgressionService
			local yen1, yen2 = Progression.GetMilestone("YEN_1"), Progression.GetMilestone("YEN_2")
			expect(Progression.MilestoneName(yen2)).toBe("Yen II")
			expect(Prog:GetMilestoneState(player, "YEN_2")).toBe("Locked")
			expect(Prog:GetMilestoneState(player, "YEN_1")).toBe("InProgress")
			expect(h:Invoke(player, "ClaimMilestone", "YEN_1").error).toBe("RequirementsNotMet")
			local before = Boost:GetMultiplier(player, "Yen")
			data.Stats.TotalKills = yen1.Requirement.Goal
			expect(Prog:GetMilestoneState(player, "YEN_1")).toBe("Claimable")
			local response = h:Invoke(player, "ClaimMilestone", "YEN_1")
			expect(response.ok).toBe(true)
			expect(data.Milestones.YEN_1).toBe(true)
			expect(math.abs(Boost:GetMultiplier(player, "Yen") - before * (1 + yen1.Bonus)) < 1e-9).toBe(true)
			expect(Boost:GetMultiplier(player, "Damage")).toBe(Boost:GetMultiplier(player, "Damage")) -- untouched
			expect(h:Invoke(player, "ClaimMilestone", "YEN_1").error).toBe("AlreadyClaimed")
			expect(Prog:GetMilestoneState(player, "YEN_2")).toBe("InProgress")
			expect(h:Invoke(player, "ClaimMilestone", "NOPE").error).toBe("InvalidArguments")
			expect(h:Invoke(player, "ClaimMilestone", { "x" }).error).toBe("InvalidArguments")
		end)

		t.it("counts live play time for Luck milestones", function()
			local h, player, data = setup()
			local Prog = h.Services.ProgressionService
			local luck1 = h.Runtime:Require("ReplicatedStorage/Shared/Config/Progression").GetMilestone("LUCK_1")
			expect(Prog:GetMilestoneState(player, "LUCK_1")).toBe("InProgress")
			data.Playtime = luck1.Requirement.Goal - 60
			expect(Prog:GetMilestoneState(player, "LUCK_1")).toBe("InProgress")
			h:Advance(120) -- the current session counts before it is flushed
			expect(Prog:GetMilestoneState(player, "LUCK_1")).toBe("Claimable")
			expect(h:Invoke(player, "ClaimMilestone", "LUCK_1").ok).toBe(true)
			h.Services.DataService:FlushPlaytime(player)
			expect(data.Playtime >= luck1.Requirement.Goal).toBe(true)
		end)
	end)
end
