local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	local function setup(options)
		local h = ServerHarness.new(options)
		h.Services.SummonService.Random = h.Mocks.Random.new(7)
		h.Services.UnitService.Random = h.Mocks.Random.new(8)
		local player, data = h:AddPlayer(300)
		return h, player, data, h.Services.SummonService
	end

	t.describe("SummonService — world 1 star (Yen, x1/x3)", function()
		t.it("charges Yen and creates units for x1 and x3", function()
			local h, player, data = setup()
			data.Currencies.Yen = 1000
			local one = h:Invoke(player, "Summon", "B_W1", 1)
			expect(one.ok).toBe(true)
			expect(data.Currencies.Yen).toBe(900)
			local three = h:Invoke(player, "Summon", "B_W1", 3)
			expect(three.ok).toBe(true)
			expect(#three.data.Results).toBe(3)
			expect(data.Currencies.Yen).toBe(620)
			expect(data.Stats.TotalSummons).toBe(4)
			expect(#data.SummonHistory).toBe(4)
			for _, result in three.data.Results do
				expect(data.Inventory.Units[result.Uid]).toBeTruthy()
			end
		end)

		t.it("rejects other counts, invalid input and insufficient Yen without charging", function()
			local h, player, data = setup()
			data.Currencies.Yen = 50
			expect(h:Invoke(player, "Summon", "B_W1", 1).error).toBe("NotEnoughCurrency")
			expect(h:Invoke(player, "Summon", "B_W1", 10).error).toBe("InvalidAmount")
			expect(h:Invoke(player, "Summon", "B_W1", 2).error).toBe("InvalidAmount")
			expect(h:Invoke(player, "Summon", "B_W1", 0 / 0).error).toBe("InvalidArguments")
			expect(h:Invoke(player, "Summon", "Nope", 1).error).toBe("BannerNotFound")
			expect(data.Currencies.Yen).toBe(50)
		end)

		t.it("refuses to summon when storage cannot hold the pulls", function()
			local h, player, data = setup()
			data.Currencies.Yen = 10000
			for _ = 1, 98 do
				h.Services.UnitService:CreateUnit(player, "SS_Kenta")
			end
			expect(h:Invoke(player, "Summon", "B_W1", 3).error).toBe("InventoryFull")
			expect(data.Currencies.Yen).toBe(10000)
		end)

		t.it("auto-deletes configured rarities into Yen", function()
			local h, player, data = setup()
			data.Currencies.Yen = 10000
			data.Settings.AutoDeleteCommon = true
			local autoDeleted = 0
			for _ = 1, 5 do
				local response = h:Invoke(player, "Summon", "B_W1", 3)
				expect(response.ok).toBe(true)
				for _, r in response.data.Results do
					if r.AutoDeleted then
						autoDeleted += 1
						expect(r.Rarity).toBe("Common")
						expect(r.Uid).toBeNil()
					end
				end
			end
			expect(autoDeleted > 0).toBe(true)
		end)

		t.it("persists pity per banner across summons", function()
			local h, player, data = setup()
			data.Currencies.Yen = 100000
			h:Invoke(player, "Summon", "B_W1", 3)
			h:Invoke(player, "Summon", "B_W1", 3)
			local pity = data.SummonPity.B_W1
			expect(pity).toBeTruthy()
			expect(pity.Legendary ~= nil).toBe(true)
		end)

		t.it("base game: only the world-1 star is available", function()
			local h, player, data = setup({ BaseGame = true })
			data.Currencies.Yen = 1000
			data.Currencies.Gems = 10000
			data.UnlockedWorlds.W2 = true
			expect(h:Invoke(player, "Summon", "B_W1", 1).ok).toBe(true)
			expect(h:Invoke(player, "Summon", "B_W2", 1).error).toBe("BannerUnavailable")
			expect(h:Invoke(player, "Summon", "B_Raid", 1).error).toBe("BannerUnavailable")
		end)
	end)

	t.describe("SummonService — gem banners (x10)", function()
		t.it("charges the x10 price and validates requirements", function()
			local h, player, data = setup()
			data.Currencies.Gems = 10000
			expect(h:Invoke(player, "Summon", "B_W2", 10).error).toBe("RequirementsNotMet")
			data.UnlockedWorlds.W2 = true
			local response = h:Invoke(player, "Summon", "B_W2", 10)
			expect(response.ok).toBe(true)
			expect(#response.data.Results).toBe(10)
			expect(data.Currencies.Gems).toBe(10000 - 540)
			expect(h:Invoke(player, "Summon", "B_W2", 3).error).toBe("InvalidAmount")
		end)

		t.it("guarantees MultiGuarantee rarity in every x10", function()
			local h = setup()
			local Summon = h.Services.SummonService
			local Banners = h.Runtime:Require("ReplicatedStorage/Shared/Config/Banners")
			local Rarities = h.Runtime:Require("ReplicatedStorage/Shared/Config/Rarities")
			local banner = Banners.Get("B_W2")
			-- A generator that always rolls 0 picks the first (alphabetical) key: "Common".
			local alwaysLow = h.Mocks.ScriptedRandom({ 0 })
			local results = Summon.RollMany(alwaysLow, banner, {}, 1, 10)
			local best = 0
			for _, r in results do
				best = math.max(best, Rarities.GetOrder(r.Rarity))
			end
			expect(best >= Rarities.GetOrder("Rare")).toBe(true)
		end)
	end)

	t.describe("roll math", function()
		t.it("forces the pity rarity at the threshold and resets the counter", function()
			local h = setup()
			local Summon = h.Services.SummonService
			local Banners = h.Runtime:Require("ReplicatedStorage/Shared/Config/Banners")
			local banner = Banners.Get("B_W1")
			local pity = { Legendary = 73, Mythical = 10 }
			local gen = h.Mocks.ScriptedRandom({ 0 })
			expect(Summon.RollRarity(gen, banner, pity, 1)).toBe("Common")
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
					local r = Summon.RollRarity(gen, banner, {}, luck)
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
	end)
end
