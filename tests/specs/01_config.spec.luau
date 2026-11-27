-- Loads every config module (they self-validate with asserts) and checks cross references.
local Runtime = require("../harness/Runtime")

return function(t)
	local expect = t.expect
	local rt = Runtime.new()
	local function cfg(name)
		return rt:Require("ReplicatedStorage/Shared/Config/" .. name)
	end

	t.describe("config", function()
		for _, name in { "GameConfig", "Rarities", "Traits", "Abilities", "Units", "Items", "Enemies", "Worlds", "Banners", "Quests", "Achievements", "Progression", "Shop", "Raids", "Events" } do
			t.it(name .. " loads", function()
				expect(cfg(name)).toBeTruthy()
			end)
		end

		t.it("rarity orders are unique and increasing", function()
			local Rarities = cfg("Rarities")
			for i = 2, #Rarities.List do
				expect(Rarities.List[i].Order > Rarities.List[i - 1].Order).toBe(true)
			end
		end)

		t.it("world spawn areas and bosses reference real enemies of that world", function()
			local Worlds, Enemies, Banners = cfg("Worlds"), cfg("Enemies"), cfg("Banners")
			for _, world in Worlds.List do
				expect(Banners.Get(world.Banner)).toBeTruthy()
				for _, area in world.SpawnAreas do
					for enemyId in area.Enemies do
						local enemy = Enemies.Get(enemyId)
						expect(enemy).toBeTruthy()
						expect(enemy.World).toBe(world.Id)
					end
				end
				for _, boss in world.Bosses do
					local enemy = Enemies.Get(boss.Enemy)
					expect(enemy).toBeTruthy()
					expect(enemy.IsBoss).toBe(true)
				end
			end
		end)

		t.it("enemy drops and quest/achievement/shop rewards are valid", function()
			local Rewards = rt:Require("ReplicatedStorage/Shared/Modules/Rewards")
			local Enemies, Quests, Achievements, Shop, Raids = cfg("Enemies"), cfg("Quests"), cfg("Achievements"), cfg("Shop"), cfg("Raids")
			local Items = cfg("Items")
			for _, enemy in Enemies.List do
				for _, drop in enemy.Rewards.Drops or {} do
					expect(Items.Get(drop.Item)).toBeTruthy()
				end
			end
			for _, quest in Quests.Main do
				expect((Rewards.IsValid(quest.Rewards))).toBe(true)
			end
			for _, quest in Quests.Daily do
				expect((Rewards.IsValid(quest.Rewards))).toBe(true)
			end
			for _, ach in Achievements.List do
				for _, tier in ach.Tiers do
					expect((Rewards.IsValid(tier.Rewards))).toBe(true)
				end
			end
			for _, item in Shop.Items do
				expect((Rewards.IsValid(item.Grants))).toBe(true)
			end
			for _, raid in Raids.List do
				expect((Rewards.IsValid(raid.Rewards))).toBe(true)
			end
		end)

		t.it("evolution costs reference real items", function()
			local Units, Items = cfg("Units"), cfg("Items")
			for _, unit in Units.List do
				if unit.EvolutionCost then
					for itemId in unit.EvolutionCost.Items or {} do
						expect(Items.Get(itemId)).toBeTruthy()
					end
				end
			end
		end)

		t.it("starter units and items exist", function()
			local GameConfig, Units, Items = cfg("GameConfig"), cfg("Units"), cfg("Items")
			for _, id in GameConfig.Start.StarterUnits do
				expect(Units.Get(id)).toBeTruthy()
			end
			for id in GameConfig.Start.StarterItems do
				expect(Items.Get(id)).toBeTruthy()
			end
		end)
	end)
end
