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
end
