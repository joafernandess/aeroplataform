local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	local function setup()
		local h = ServerHarness.new()
		h.Services.SummonService.Random = h.Mocks.Random.new(7)
		h.Services.UnitService.Random = h.Mocks.Random.new(8)
		local player, data = h:AddPlayer(300)
		return h, player, data, h.Services.SummonService
	end

	t.describe("SummonService", function()
		t.it("charges the banner cost and creates units", function()
			local h, player, data = setup()
			data.Currencies.Gems = 1000
			local response = h:Invoke(player, "Summon", "B_W1", 10)
			expect(response.ok).toBe(true)
			expect(#response.data.Results).toBe(10)
			expect(data.Currencies.Gems).toBe(1000 - 450)
			expect(data.Stats.TotalSummons).toBe(10)
			expect(#data.SummonHistory).toBe(10)
			for _, result in response.data.Results do
				expect(data.Inventory.Units[result.Uid]).toBeTruthy()
			end
		end)

		t.it("rejects invalid input, locked banners and insufficient funds without charging", function()
			local h, player, data = setup()
			data.Currencies.Gems = 40
			expect(h:Invoke(player, "Summon", "B_W1", 1).error).toBe("NotEnoughCurrency")
			expect(h:Invoke(player, "Summon", "B_W1", 5).error).toBe("InvalidAmount")
			expect(h:Invoke(player, "Summon", "B_W1", 0 / 0).error).toBe("InvalidArguments")
			expect(h:Invoke(player, "Summon", "Nope", 1).error).toBe("BannerNotFound")
			data.Currencies.Gems = 10000
			expect(h:Invoke(player, "Summon", "B_W2", 1).error).toBe("RequirementsNotMet")
			expect(data.Currencies.Gems).toBe(10000)
		end)

		t.it("refuses to summon when storage cannot hold the pulls", function()
			local h, player, data = setup()
			data.Currencies.Gems = 10000
			for _ = 1, 95 do
				h.Services.UnitService:CreateUnit(player, "SS_Kenta")
			end
			expect(h:Invoke(player, "Summon", "B_W1", 10).error).toBe("InventoryFull")
			expect(data.Currencies.Gems).toBe(10000)
		end)

		t.it("guarantees MultiGuarantee rarity in every x10", function()
			local h = setup()
			local Summon = h.Services.SummonService
			local Banners = h.Runtime:Require("ReplicatedStorage/Shared/Config/Banners")
			local Rarities = h.Runtime:Require("ReplicatedStorage/Shared/Config/Rarities")
			local banner = Banners.Get("B_W1")
			-- A generator that always rolls 0 picks the first (alphabetical) key: "Common".
			local alwaysLow = h.Mocks.ScriptedRandom({ 0 })
			local pity = {}
			local results = Summon.RollMany(alwaysLow, banner, pity, 1, 10)
			local best = 0
			for _, r in results do
				best = math.max(best, Rarities.GetOrder(r.Rarity))
			end
			expect(best >= Rarities.GetOrder("Rare")).toBe(true)
		end)

		t.it("forces the pity rarity at the threshold and resets the counter", function()
			local h = setup()
			local Summon = h.Services.SummonService
			local Banners = h.Runtime:Require("ReplicatedStorage/Shared/Config/Banners")
			local banner = Banners.Get("B_W1")
			local pity = { Legendary = 73, Mythical = 10 }
			local gen = h.Mocks.ScriptedRandom({ 0 })
			local first = Summon.RollRarity(gen, banner, pity, 1)
			expect(first).toBe("Common")
			expect(pity.Legendary).toBe(74)
			local forced = Summon.RollRarity(gen, banner, pity, 1)
			expect(forced == "Legendary" or forced == "Mythical").toBe(true)
			expect(pity.Legendary).toBe(0)
		end)

		t.it("matches configured rates statistically and luck increases rare odds", function()
			local h = setup()
			local Summon = h.Services.SummonService
			local Banners = h.Runtime:Require("ReplicatedStorage/Shared/Config/Banners")
			local banner = Banners.Get("B_W1")
			local function sample(luck)
				local gen = h.Mocks.Random.new(1234)
				local counts = {}
				local N = 20000
				for _ = 1, N do
					local pity = {}
					local r = Summon.RollRarity(gen, banner, pity, luck)
					counts[r] = (counts[r] or 0) + 1
				end
				return counts, N
			end
			local counts, N = sample(1)
			expect(math.abs(counts.Common / N - 0.60) < 0.02).toBe(true)
			expect(math.abs(counts.Rare / N - 0.28) < 0.02).toBe(true)
			expect(math.abs(counts.Epic / N - 0.09) < 0.01).toBe(true)
			local lucky = sample(3)
			expect(lucky.Epic > counts.Epic * 2).toBe(true)
		end)

		t.it("auto-deletes configured rarities into Yen", function()
			local h, player, data = setup()
			data.Currencies.Gems = 10000
			data.Settings.AutoDeleteCommon = true
			local yen = data.Currencies.Yen
			local response = h:Invoke(player, "Summon", "B_W1", 10)
			expect(response.ok).toBe(true)
			local autoDeleted = 0
			for _, r in response.data.Results do
				if r.AutoDeleted then
					autoDeleted += 1
					expect(r.Rarity).toBe("Common")
					expect(r.Uid).toBeNil()
				end
			end
			if autoDeleted > 0 then
				expect(data.Currencies.Yen > yen).toBe(true)
			end
		end)

		t.it("persists pity per banner across summons", function()
			local h, player, data = setup()
			data.Currencies.Gems = 100000
			h:Invoke(player, "Summon", "B_W1", 10)
			h:Invoke(player, "Summon", "B_W1", 10)
			local pity = data.SummonPity.B_W1
			expect(pity).toBeTruthy()
			expect(pity.Legendary ~= nil).toBe(true)
		end)
	end)
end
