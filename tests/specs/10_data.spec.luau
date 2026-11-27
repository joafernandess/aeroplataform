local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	t.describe("DataService", function()
		t.it("creates a new profile from the template and locks the session", function()
			local h = ServerHarness.new()
			local player, data = h:AddPlayer(1)
			expect(data.Level).toBe(1)
			expect(data.Currencies.Gems).toBe(h.GameConfig.Start.Currencies.Gems)
			expect(data.UnlockedWorlds.W1).toBe(true)
			local profile = h.Services.DataService:GetProfile(player)
			expect(profile.IsNew).toBe(true)
			local store = h.DataStores[h.GameConfig.Data.StoreName]
			expect(store.Data["Player_1"].Session.JobId).toBe("test-job")
		end)

		t.it("saves and reloads data, releasing the lock on leave", function()
			local h = ServerHarness.new()
			local player, data = h:AddPlayer(2)
			data.Currencies.Yen = 777
			data.Level = 9
			h:Advance(60)
			h.Services.DataService:ReleaseProfile(player)
			local store = h.DataStores[h.GameConfig.Data.StoreName]
			local record = store.Data["Player_2"]
			expect(record.Session).toBeNil()
			expect(record.Data.Currencies.Yen).toBe(777)
			expect(record.Data.Playtime).toBe(60)

			-- Rejoin on a fresh server using the same store contents
			local h2 = ServerHarness.new()
			h2.Services.DataService:SetStore(store)
			local _, data2 = h2:AddPlayer(2)
			expect(data2.Currencies.Yen).toBe(777)
			expect(data2.Level).toBe(9)
			expect(h2.Services.DataService:GetProfile(h2.Players:GetPlayers()[1]).IsNew).toBe(false)
		end)

		t.it("refuses to load a profile locked by another live server and kicks", function()
			local h = ServerHarness.new()
			h.GameConfig.Data.SessionLockWaitAttempts = 2
			local store = h.Services.DataService:_getStore()
			store.Data["Player_3"] = { Data = { Level = 50 }, Session = { JobId = "other-server", LockedAt = h.Now - 10 } }
			local player = h.Mocks.FakePlayer(3)
			local profile = h.Services.DataService:LoadProfile(player)
			expect(profile).toBeNil()
			expect(player.Kicked).toBeTruthy()
			-- The other server's data must be untouched
			expect(store.Data["Player_3"].Data.Level).toBe(50)
			expect(store.Data["Player_3"].Session.JobId).toBe("other-server")
		end)

		t.it("steals a stale lock", function()
			local h = ServerHarness.new()
			local store = h.Services.DataService:_getStore()
			store.Data["Player_4"] = { Data = { Level = 12 }, Session = { JobId = "dead-server", LockedAt = h.Now - 99999 } }
			local _, data = h:AddPlayer(4)
			expect(data.Level).toBe(12)
			expect(store.Data["Player_4"].Session.JobId).toBe("test-job")
		end)

		t.it("retries transient DataStore errors and kicks after exhausting retries", function()
			local h = ServerHarness.new()
			local store = h.Services.DataService:_getStore()
			store.FailNext.UpdateAsync = 2
			local _, data = h:AddPlayer(5)
			expect(data).toBeTruthy()

			store.FailNext.UpdateAsync = 999
			local player = h.Mocks.FakePlayer(6)
			expect(h.Services.DataService:LoadProfile(player)).toBeNil()
			expect(player.Kicked).toBeTruthy()
			store.FailNext.UpdateAsync = 0
		end)

		t.it("does not save once the lock was taken by another server", function()
			local h = ServerHarness.new()
			local player, data = h:AddPlayer(7)
			local store = h.Services.DataService:_getStore()
			store.Data["Player_7"].Session = { JobId = "intruder", LockedAt = h.Now }
			data.Currencies.Yen = 123456
			local saved = h.Services.DataService:SaveProfile(player)
			expect(saved).toBe(false)
			local saved7 = store.Data["Player_7"].Data
			expect(saved7 == nil or saved7.Currencies.Yen ~= 123456).toBe(true)
			expect(player.Kicked).toBeTruthy()
		end)

		t.it("reconciles old profiles with new template fields and sanitises bad values", function()
			local h = ServerHarness.new()
			local store = h.Services.DataService:_getStore()
			store.Data["Player_8"] = {
				Data = {
					DataVersion = 1,
					Level = 3,
					Currencies = { Yen = -50, Gems = 10 },
					Inventory = { Units = { U1 = { UnitId = "DoesNotExist" }, U2 = { UnitId = "SS_Kenta", Level = 2, XP = 0, Stars = 0 } }, Items = { Junk = 3 } },
					EquippedUnits = { "U1", "U2", "U2" },
					CurrentWorld = "W9",
					UnlockedWorlds = { W1 = true },
				},
			}
			local _, data = h:AddPlayer(8)
			expect(data.Level).toBe(3)
			expect(data.Currencies.Yen).toBe(0)
			expect(data.Currencies.Tokens).toBe(0)
			expect(data.Inventory.Units.U1).toBeNil()
			expect(data.Inventory.Units.U2.Uid).toBe("U2")
			expect(data.Inventory.Items.Junk).toBeNil()
			expect(#data.EquippedUnits).toBe(1)
			expect(data.CurrentWorld).toBe("W1")
			expect(data.Settings.DamageNumbers).toBe(true)
		end)

		t.it("refuses profiles written by a newer data version", function()
			local h = ServerHarness.new()
			local store = h.Services.DataService:_getStore()
			store.Data["Player_9"] = { Data = { DataVersion = 999, Level = 1 } }
			local player = h.Mocks.FakePlayer(9)
			expect(h.Services.DataService:LoadProfile(player)).toBeNil()
			expect(player.Kicked).toBeTruthy()
		end)

		t.it("GetProfile remote returns a snapshot without private keys", function()
			local h = ServerHarness.new()
			local player = h:AddPlayer(10)
			local response = h:Invoke(player, "GetProfile")
			expect(response.ok).toBe(true)
			expect(response.data.Currencies).toBeTruthy()
			expect(response.data.ProcessedReceipts).toBeNil()
			expect(response.data.ClaimedRewards).toBeNil()
		end)
	end)

	t.describe("EconomyService", function()
		t.it("adds and removes currency with validation", function()
			local h = ServerHarness.new()
			local Economy = h.Services.EconomyService
			local player, data = h:AddPlayer(20)
			local startYen = data.Currencies.Yen
			expect((Economy:Add(player, "Yen", 100, "Test"))).toBe(true)
			expect(data.Currencies.Yen).toBe(startYen + 100)
			local ok, err = Economy:Remove(player, "Yen", startYen + 101, "Test")
			expect(ok).toBe(false)
			expect(err).toBe("NotEnoughCurrency")
			expect((Economy:Remove(player, "Yen", 100, "Test"))).toBe(true)
			expect(data.Currencies.Yen).toBe(startYen)
		end)

		t.it("rejects invalid currencies and amounts (NaN, inf, negative, zero)", function()
			local h = ServerHarness.new()
			local Economy = h.Services.EconomyService
			local player = h:AddPlayer(21)
			for _, bad in { 0 / 0, math.huge, -5, 0, 0.4, "10" } do
				local ok = Economy:Add(player, "Yen", bad :: any, "Test")
				expect(ok).toBe(false)
			end
			expect((Economy:Add(player, "Robux", 10, "Test"))).toBe(false)
		end)

		t.it("caps balances at MaxBalance", function()
			local h = ServerHarness.new()
			local Economy = h.Services.EconomyService
			local player, data = h:AddPlayer(22)
			data.Currencies.Gems = h.GameConfig.Economy.MaxBalance - 5
			Economy:Add(player, "Gems", 1000, "Test")
			expect(data.Currencies.Gems).toBe(h.GameConfig.Economy.MaxBalance)
		end)

		t.it("refunds a purchase when the grant fails", function()
			local h = ServerHarness.new()
			local Economy = h.Services.EconomyService
			local player, data = h:AddPlayer(23)
			data.Currencies.Gems = 100
			local ok, err = Economy:Purchase(player, { Currency = "Gems", Amount = 60 }, "TestBuy", function()
				return false, "InventoryFull"
			end)
			expect(ok).toBe(false)
			expect(err).toBe("InventoryFull")
			expect(data.Currencies.Gems).toBe(100)
			local ok2 = Economy:Purchase(player, { Currency = "Gems", Amount = 60 }, "TestBuy", function()
				error("boom")
			end)
			expect(ok2).toBe(false)
			expect(data.Currencies.Gems).toBe(100)
			local ok3 = Economy:Purchase(player, { Currency = "Gems", Amount = 60 }, "TestBuy", function()
				return true, "done"
			end)
			expect(ok3).toBe(true)
			expect(data.Currencies.Gems).toBe(40)
		end)

		t.it("grants rewards once per OnceKey", function()
			local h = ServerHarness.new()
			local Economy = h.Services.EconomyService
			local player, data = h:AddPlayer(24)
			local gems = data.Currencies.Gems
			local ok = Economy:GrantRewards(player, { Gems = 10, Items = { XPPotionSmall = 2 } }, { Reason = "Test", OnceKey = "k1" })
			expect(ok).toBe(true)
			local ok2, err2 = Economy:GrantRewards(player, { Gems = 10 }, { Reason = "Test", OnceKey = "k1" })
			expect(ok2).toBe(false)
			expect(err2).toBe("AlreadyClaimed")
			expect(data.Currencies.Gems).toBe(gems + 10)
			expect(data.Inventory.Items.XPPotionSmall).toBe(h.GameConfig.Start.StarterItems.XPPotionSmall + 2)
		end)

		t.it("keeps a bounded transaction log and skips noisy reasons", function()
			local h = ServerHarness.new()
			local Economy = h.Services.EconomyService
			local player, data = h:AddPlayer(25)
			for _ = 1, 70 do
				Economy:Add(player, "Yen", 1, "Test")
			end
			Economy:Add(player, "Yen", 1, "EnemyKill")
			expect(#data.TransactionLog).toBe(h.GameConfig.Data.TransactionLogLimit)
			expect(data.TransactionLog[#data.TransactionLog].Reason).toBe("Test")
		end)
	end)
end
