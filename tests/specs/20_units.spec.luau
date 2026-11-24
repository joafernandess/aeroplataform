local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	local function setup(userId)
		local h = ServerHarness.new()
		h.Services.UnitService.Random = h.Mocks.Random.new(42)
		local player, data = h:AddPlayer(userId or 100)
		return h, player, data, h.Services.UnitService
	end

	t.describe("UnitService", function()
		t.it("gives new players their starter unit, equipped", function()
			local _, _, data = setup()
			local count = 0
			for _ in data.Inventory.Units do
				count += 1
			end
			expect(count).toBe(1)
			expect(#data.EquippedUnits).toBe(1)
			expect(data.Inventory.Units[data.EquippedUnits[1]].UnitId).toBe("SS_GeninRecruit")
		end)

		t.it("creates units with unique uids and respects storage capacity", function()
			local h, player, data, Unit = setup()
			local ok, a = Unit:CreateUnit(player, "SS_Kenta")
			local _, b = Unit:CreateUnit(player, "SS_Kenta")
			expect(ok).toBe(true)
			expect(a.Uid ~= b.Uid).toBe(true)
			data.Upgrades.UnitStorage = 0
			for _ = 1, 200 do
				Unit:CreateUnit(player, "SS_Kenta")
			end
			expect(h.Services.InventoryService:GetUnitCount(player)).toBe(h.GameConfig.Units.BaseUnitStorage)
			local okFull, err = Unit:CreateUnit(player, "SS_Kenta")
			expect(okFull).toBe(false)
			expect(err).toBe("InventoryFull")
			expect((Unit:CreateUnit(player, "SS_Kenta", { IgnoreCapacity = true }))).toBe(true)
		end)

		t.it("enforces equip slots and equip/unequip rules through remotes", function()
			local h, player, data, Unit = setup()
			local uids = {}
			for _ = 1, 5 do
				local _, u = Unit:CreateUnit(player, "SS_Hikari")
				table.insert(uids, u.Uid)
			end
			expect(h:Invoke(player, "EquipUnit", uids[1]).ok).toBe(true)
			expect(h:Invoke(player, "EquipUnit", uids[1]).error).toBe("AlreadyEquipped")
			expect(h:Invoke(player, "EquipUnit", uids[2]).ok).toBe(true)
			expect(h:Invoke(player, "EquipUnit", uids[3]).error).toBe("EquipLimit")
			expect(h:Invoke(player, "EquipUnit", "U99999").error).toBe("UnitNotFound")
			expect(h:Invoke(player, "EquipUnit", { "hack" }).error).toBe("InvalidArguments")
			expect(h:Invoke(player, "UnequipUnit", uids[1]).ok).toBe(true)
			expect(#data.EquippedUnits).toBe(2)
			data.Upgrades.EquipSlots = 2
			expect(Unit:GetEquipSlots(player)).toBe(5)
		end)

		t.it("only the first EquipSlots units fight when slots shrink", function()
			local _, player, data, Unit = setup()
			for _ = 1, 4 do
				local _, u = Unit:CreateUnit(player, "SS_Hikari")
				table.insert(data.EquippedUnits, u.Uid)
			end
			expect(#data.EquippedUnits).toBe(5)
			expect(#Unit:GetEquippedUnits(player)).toBe(3)
		end)

		t.it("equips the strongest units with EquipBest", function()
			local h, player, data, Unit = setup()
			local _, best = Unit:CreateUnit(player, "SS_Kurogane", { Trait = "Strong" })
			local _, second = Unit:CreateUnit(player, "SS_Raizen", { Trait = "Strong" })
			Unit:CreateUnit(player, "SS_Kenta", { Trait = "Strong" })
			local response = h:Invoke(player, "EquipBest")
			expect(response.ok).toBe(true)
			expect(data.EquippedUnits[1]).toBe(best.Uid)
			expect(data.EquippedUnits[2]).toBe(second.Uid)
			expect(#data.EquippedUnits).toBe(3)
		end)

		t.it("deletes units for Yen, skipping locked and equipped ones", function()
			local h, player, data, Unit = setup()
			local _, a = Unit:CreateUnit(player, "SS_Kenta")
			local _, b = Unit:CreateUnit(player, "SS_Kenta")
			local equipped = data.EquippedUnits[1]
			Unit:SetLocked(player, b.Uid, true)
			local yen = data.Currencies.Yen
			local response = h:Invoke(player, "DeleteUnits", { a.Uid, b.Uid, equipped })
			expect(response.ok).toBe(true)
			expect(response.data.Deleted).toBe(1)
			expect(response.data.Skipped[b.Uid]).toBe("UnitLocked")
			expect(response.data.Skipped[equipped]).toBe("UnitEquipped")
			expect(data.Currencies.Yen > yen).toBe(true)
			expect(data.Inventory.Units[a.Uid]).toBeNil()
			expect(h:Invoke(player, "DeleteUnits", { a.Uid, a.Uid }).error).toBe("InvalidArguments")
		end)

		t.it("levels units with XP and stops at the rarity max level", function()
			local _, player, _, Unit = setup()
			local _, u = Unit:CreateUnit(player, "SS_Kenta")
			local ok, result = Unit:AddUnitXP(player, u.Uid, 1e9)
			expect(ok).toBe(true)
			expect(u.Level).toBe(25)
			expect(result.LevelsGained).toBe(24)
			local ok2, err = Unit:AddUnitXP(player, u.Uid, 10)
			expect(ok2).toBe(false)
			expect(err).toBe("MaxLevel")
		end)

		t.it("fuses fodder into XP and stars and protects locked fodder", function()
			local h, player, data, Unit = setup()
			local _, target = Unit:CreateUnit(player, "SS_Hikari")
			local _, same = Unit:CreateUnit(player, "SS_Hikari")
			local _, other = Unit:CreateUnit(player, "SS_Kenta")
			local _, locked = Unit:CreateUnit(player, "SS_Kenta")
			Unit:SetLocked(player, locked.Uid, true)
			expect(h:Invoke(player, "FuseUnits", target.Uid, { locked.Uid }).error).toBe("UnitLocked")
			expect(h:Invoke(player, "FuseUnits", target.Uid, { target.Uid }).error).toBe("CannotFuse")
			local response = h:Invoke(player, "FuseUnits", target.Uid, { same.Uid, other.Uid })
			expect(response.ok).toBe(true)
			expect(response.data.StarsGained).toBe(1)
			expect(target.Stars).toBe(1)
			expect(target.Level > 1).toBe(true)
			expect(data.Inventory.Units[same.Uid]).toBeNil()
			expect(data.Inventory.Units[other.Uid]).toBeNil()
			expect(data.Inventory.Units[locked.Uid]).toBeTruthy()
			expect(data.Stats.UnitsFused).toBe(1)
		end)

		t.it("evolves a max-level unit, paying Yen and materials atomically", function()
			local h, player, data, Unit = setup()
			local Inventory = h.Services.InventoryService
			local _, raizen = Unit:CreateUnit(player, "SS_Raizen")
			expect(h:Invoke(player, "EvolveUnit", raizen.Uid).error).toBe("NotMaxLevel")
			Unit:AddUnitXP(player, raizen.Uid, 1e12)
			expect(h:Invoke(player, "EvolveUnit", raizen.Uid).error).toBe("MissingMaterials")
			Inventory:AddItem(player, "ShinobiScroll", 5)
			Inventory:AddItem(player, "EvolutionStone", 1)
			data.Currencies.Yen = 10
			expect(h:Invoke(player, "EvolveUnit", raizen.Uid).error).toBe("NotEnoughCurrency")
			expect(Inventory:GetItemCount(player, "ShinobiScroll")).toBe(5)
			data.Currencies.Yen = 60000
			local response = h:Invoke(player, "EvolveUnit", raizen.Uid)
			expect(response.ok).toBe(true)
			expect(raizen.UnitId).toBe("SS_RaizenStorm")
			expect(raizen.Level).toBe(1)
			expect(data.Currencies.Yen).toBe(10000)
			expect(Inventory:GetItemCount(player, "ShinobiScroll")).toBe(0)
			expect(data.Stats.UnitsEvolved).toBe(1)
			expect(h:Invoke(player, "EvolveUnit", raizen.Uid).error).toBe("CannotEvolve")
		end)
	end)

	t.describe("InventoryService", function()
		t.it("respects max stack and removal rules", function()
			local h, player = setup()
			local Inventory = h.Services.InventoryService
			Inventory:AddItem(player, "DamageBoost2x", 500)
			expect(Inventory:GetItemCount(player, "DamageBoost2x")).toBe(99)
			local ok, err = Inventory:AddItem(player, "DamageBoost2x", 1)
			expect(ok).toBe(false)
			expect(err).toBe("StackLimit")
			expect((Inventory:RemoveItem(player, "DamageBoost2x", 100))).toBe(false)
			expect((Inventory:RemoveItems(player, { DamageBoost2x = 10, EvolutionStone = 1 }))).toBe(false)
			expect(Inventory:GetItemCount(player, "DamageBoost2x")).toBe(99)
		end)

		t.it("uses XP potions on a unit and only consumes them on success", function()
			local h, player, data, Unit = setup()
			local uid = data.EquippedUnits[1]
			local before = h.Services.InventoryService:GetItemCount(player, "XPPotionSmall")
			local response = h:Invoke(player, "UseItem", "XPPotionSmall", uid, 2)
			expect(response.ok).toBe(true)
			expect(h.Services.InventoryService:GetItemCount(player, "XPPotionSmall")).toBe(before - 2)
			expect(data.Inventory.Units[uid].Level > 1).toBe(true)
			-- Missing target: nothing consumed
			local bad = h:Invoke(player, "UseItem", "XPPotionSmall", "U9999", 1)
			expect(bad.ok).toBe(false)
			expect(h.Services.InventoryService:GetItemCount(player, "XPPotionSmall")).toBe(before - 2)
			local _ = Unit
		end)

		t.it("activates boosts and stacks duration", function()
			local h, player, data = setup()
			local Inventory = h.Services.InventoryService
			Inventory:AddItem(player, "YenBoost2x", 2)
			expect(h:Invoke(player, "UseItem", "YenBoost2x").ok).toBe(true)
			expect(h:Invoke(player, "UseItem", "YenBoost2x").ok).toBe(true)
			expect(data.ActiveBoosts.Yen.ExpiresAt).toBe(h.Now + 1800)
			local mult = h.Services.BoostService:GetMultiplier(player, "Yen")
			expect(mult >= 2).toBe(true)
			h:Advance(1801)
			expect(h.Services.BoostService:GetMultiplier(player, "Yen") < 2).toBe(true)
		end)

		t.it("sells unlocked items only", function()
			local h, player, data = setup()
			h.Services.InventoryService:AddItem(player, "EvolutionStone", 3)
			expect(h:Invoke(player, "LockItem", "EvolutionStone", true).ok).toBe(true)
			expect(h:Invoke(player, "SellItem", "EvolutionStone", 1).error).toBe("ItemLocked")
			h:Invoke(player, "LockItem", "EvolutionStone", false)
			local yen = data.Currencies.Yen
			expect(h:Invoke(player, "SellItem", "EvolutionStone", 2).ok).toBe(true)
			expect(data.Currencies.Yen).toBe(yen + 400)
		end)
	end)
end
