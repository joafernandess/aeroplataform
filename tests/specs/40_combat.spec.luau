local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	local function setup()
		local h = ServerHarness.new()
		local V = h.Vector3
		h.Services.EnemyService.Random = h.Mocks.Random.new(1)
		h.Services.CombatService.Random = h.Mocks.ScriptedRandom({ 0.99 }) -- never crit unless 100%
		h.Services.UnitService.Random = h.Mocks.Random.new(2)
		local player, data = h:AddPlayer(400, "Fighter", V.new(0, 3, 0))
		return h, player, data, V
	end

	local function run(h, seconds)
		local Combat = h.Services.CombatService
		local steps = math.floor(seconds / 0.1)
		for _ = 1, steps do
			h:Advance(0.1)
			Combat:Step(h.PreciseNow)
		end
	end

	t.describe("EnemyService + CombatService", function()
		t.it("units auto-attack the nearest enemy in range and the killer gets rewards", function()
			local h, player, data, V = setup()
			local Enemy = h.Services.EnemyService
			local enemy = Enemy:Spawn("W1_Bandit", V.new(5, 3, 0), "World:W1", { WorldId = "W1" })
			local yen, kills = data.Currencies.Yen, data.Stats.TotalKills
			run(h, 30)
			expect(enemy.Alive).toBe(false)
			expect(data.Stats.TotalKills).toBe(kills + 1)
			expect(data.Currencies.Yen > yen).toBe(true)
			expect(data.Experience > 0).toBe(true)
			local fired = h.Net.Fired[player].DamageNumbers
			expect(fired ~= nil and #fired > 0).toBe(true)
		end)

		t.it("ignores enemies out of range or in other zones", function()
			local h, _, _, V = setup()
			local Enemy = h.Services.EnemyService
			local far = Enemy:Spawn("W1_Bandit", V.new(500, 3, 0), "World:W1")
			local otherZone = Enemy:Spawn("W2_Pirate", V.new(3, 3, 0), "World:W2")
			run(h, 5)
			expect(far.Health).toBe(far.MaxHealth)
			expect(otherZone.Health).toBe(otherZone.MaxHealth)
		end)

		t.it("manual target validates distance/zone", function()
			local h, player, _, V = setup()
			local Enemy = h.Services.EnemyService
			local tooFar = Enemy:Spawn("W1_Bandit", V.new(1000, 3, 0), "World:W1")
			local wrongZone = Enemy:Spawn("W1_Bandit", V.new(2, 3, 0), "World:W2")
			local good = Enemy:Spawn("W1_Bandit", V.new(4, 3, 0), "World:W1")
			expect((h.Services.CombatService:SetTarget(player, tooFar.Id))).toBe(false)
			expect((h.Services.CombatService:SetTarget(player, wrongZone.Id))).toBe(false)
			h.Net.Send(player, "SetTarget", good.Id)
			expect(h.Services.CombatService:GetState(player).Target).toBe(good.Id)
			h.Net.Send(player, "SetTarget", { "garbage" }) -- ignored safely
			run(h, 30)
			expect(good.Alive).toBe(false)
			expect(h.Services.CombatService:GetState(player).Target).toBe(nil)
		end)

		t.it("clicker: fighters attack at full speed while clicking, half speed otherwise, always with Auto Clicker", function()
			local h, player, _, V = setup()
			local Enemy, Combat = h.Services.EnemyService, h.Services.CombatService
			local idleSpeed = h.GameConfig.Combat.IdleAttackSpeed
			expect(idleSpeed < 1).toBe(true)
			local function damageOver(seconds: number, click: boolean): number
				Combat.Random = h.Mocks.Random.new(77)
				local enemy = Enemy:Spawn("W1_NineTails", V.new(4, 3, 0), "World:W1")
				local steps = math.floor(seconds / 0.1)
				for i = 1, steps do
					if click and i % 3 == 0 then
						h.Net.Send(player, "Click")
					end
					h:Advance(0.1)
					Combat:Step(h.PreciseNow)
				end
				local dealt = enemy.MaxHealth - enemy.Health
				Enemy:Despawn(enemy)
				return dealt
			end
			local idle = damageOver(20, false)
			h:Advance(2)
			local clicking = damageOver(20, true)
			expect(idle > 0).toBe(true)
			expect(clicking / idle > 1.6).toBe(true)
			-- the Click event only refreshes the timer (rate-limited); IsClicking reflects it
			h.Net.Send(player, "Click")
			expect(Combat:IsClicking(player, h.PreciseNow)).toBe(true)
			expect(Combat:IsClicking(player, h.PreciseNow + h.GameConfig.Combat.ClickActiveWindow + 0.1)).toBe(false)
			-- Auto Clicker pass: always clicking
			local shop = h.Services.ShopService
			local original = shop.GetPerkValue
			shop.GetPerkValue = function(self, p, perk, default)
				if perk == "AutoClicker" then
					return 1
				end
				return original(self, p, perk, default)
			end
			expect(Combat:IsClicking(player, h.PreciseNow + 100)).toBe(true)
			shop.GetPerkValue = original
		end)

		t.it("defense reduces damage and every hit deals at least 1", function()
			local h = setup()
			local Formulas = h.Runtime:Require("ReplicatedStorage/Shared/Modules/Formulas")
			expect(Formulas.DamageAfterDefense(1000, 0)).toBe(1000)
			expect(Formulas.DamageAfterDefense(1000, 1000)).toBe(500)
			expect(Formulas.DamageAfterDefense(1000, 1e9)).toBe(250)
			expect(Formulas.DamageAfterDefense(0.1, 0)).toBe(1)
		end)

		t.it("boss rewards are shared by every contributor above the threshold", function()
			local h, p1, d1, V = setup()
			local p2, d2 = h:AddPlayer(401, "Helper", V.new(0, 3, 0))
			local p3, d3 = h:AddPlayer(402, "Leech", V.new(0, 3, 0))
			local Enemy = h.Services.EnemyService
			local boss = Enemy:Spawn("W1_SnakeSage", V.new(5, 3, 0), "World:W1")
			Enemy:ApplyDamage(p2, boss, boss.MaxHealth * 0.5)
			Enemy:ApplyDamage(p3, boss, 10)
			local kills1, kills2, kills3 = d1.Stats.BossKills, d2.Stats.BossKills, d3.Stats.BossKills
			Enemy:ApplyDamage(p1, boss, boss.MaxHealth * 10)
			expect(boss.Alive).toBe(false)
			expect(d1.Stats.BossKills).toBe(kills1 + 1)
			expect(d2.Stats.BossKills).toBe(kills2 + 1)
			expect(d3.Stats.BossKills).toBe(kills3)
		end)

		t.it("cleave specials hit every enemy around the target", function()
			local h, player, data, V = setup()
			local Unit = h.Services.UnitService
			local _, kurogane = Unit:CreateUnit(player, "SS_Kurogane", { Trait = "Strong" })
			data.EquippedUnits = { kurogane.Uid }
			local Enemy = h.Services.EnemyService
			local a = Enemy:Spawn("W1_MaskedElite", V.new(5, 3, 0), "World:W1")
			local b = Enemy:Spawn("W1_MaskedElite", V.new(8, 3, 4), "World:W1")
			run(h, 5) -- special is ready 2s after the unit first acts (attacks are slower without clicking)
			local casts = h.Net.Fired[player].AbilityCast
			expect(casts ~= nil and #casts > 0).toBe(true)
			expect(a.Health < a.MaxHealth).toBe(true)
			expect(b.Health < b.MaxHealth).toBe(true)
		end)

		t.it("spawners fill areas and respawn after RespawnTime", function()
			local h, _, _, V = setup()
			local Enemy = h.Services.EnemyService
			Enemy:StepSpawners(h.PreciseNow)
			local count = Enemy:CountInZone("World:W1")
			-- 2 areas (12 + 5) + 2 bosses
			expect(count).toBe(19)
			local victim = Enemy:GetEnemiesInZone("World:W1")[1]
			local killer = h.Players:GetPlayers()[1]
			Enemy:ApplyDamage(killer, victim, 1e15)
			Enemy:StepSpawners(h.PreciseNow)
			expect(Enemy:CountInZone("World:W1")).toBe(18)
			h:Advance(victim.Def.RespawnTime + 0.1)
			Enemy:StepSpawners(h.PreciseNow)
			expect(Enemy:CountInZone("World:W1")).toBe(19)
			local _ = V
		end)

		t.it("aggressive bosses damage nearby players", function()
			local h, player, _, V = setup()
			local Enemy = h.Services.EnemyService
			Enemy:Spawn("W1_SnakeSage", V.new(3, 3, 0), "World:W1")
			h:Advance(5)
			Enemy:StepAggression(h.PreciseNow)
			expect(player.Character.Humanoid.Damage > 0).toBe(true)
		end)
	end)

	t.describe("WorldService", function()
		t.it("unlocks worlds in order with level and cost requirements", function()
			local h, player, data = setup()
			expect(h:Invoke(player, "UnlockWorld", "W3").error).toBe("RequirementsNotMet")
			expect(h:Invoke(player, "UnlockWorld", "W2").error).toBe("RequirementsNotMet") -- level 10 needed
			data.Level = 10
			data.Currencies.Yen = 100
			expect(h:Invoke(player, "UnlockWorld", "W2").error).toBe("NotEnoughCurrency")
			data.Currencies.Yen = 30000
			expect(h:Invoke(player, "UnlockWorld", "W2").ok).toBe(true)
			expect(data.Currencies.Yen).toBe(5000)
			expect(h:Invoke(player, "UnlockWorld", "W2").error).toBe("AlreadyUnlocked")
		end)

		t.it("teleports only to unlocked worlds and changes the combat zone", function()
			local h, player, data = setup()
			local World = h.Services.WorldService
			expect(h:Invoke(player, "TeleportWorld", "W2").error).toBe("WorldLocked")
			data.UnlockedWorlds.W2 = true
			expect(h:Invoke(player, "TeleportWorld", "W2").ok).toBe(true)
			expect(World:GetZoneKey(player)).toBe("World:W2")
			expect(player.Character.HumanoidRootPart.Position.X).toBe(1000)
		end)

		t.it("grants the world clear reward once", function()
			local h, player, data, V = setup()
			local Enemy = h.Services.EnemyService
			data.Level = 150 -- max level: isolate from level-up gem rewards
			local gems = data.Currencies.Gems
			for _ = 1, 2 do
				local boss = Enemy:Spawn("W1_NineTails", V.new(3, 3, 0), "World:W1")
				Enemy:ApplyDamage(player, boss, 1e15)
			end
			expect(data.ClearedWorlds.W1).toBe(true)
			-- 50 clear gems once + 10 boss gems per kill (x2)
			expect(data.Currencies.Gems).toBe(gems + 50 + 20)
		end)
	end)

	t.describe("ProgressionService", function()
		t.it("levels up the player and grants level rewards once", function()
			local h, player, data = setup()
			local gems = data.Currencies.Gems
			local ok, result = h.Services.ProgressionService:AddPlayerXP(player, 1e6)
			expect(ok).toBe(true)
			expect(result.LevelsGained > 5).toBe(true)
			expect(data.Currencies.Gems > gems).toBe(true)
			expect(h.Net.LastFired(player, "LevelUp")).toBeTruthy()
		end)

		t.it("buys upgrades with growing cost until max", function()
			local h, player, data = setup()
			data.Currencies.Yen = 1e9
			local before = h.Services.BoostService:GetMultiplier(player, "Damage")
			expect(h:Invoke(player, "BuyUpgrade", "Damage").ok).toBe(true)
			expect(data.Upgrades.Damage).toBe(1)
			expect(data.Damage).toBe(1)
			expect(h.Services.BoostService:GetMultiplier(player, "Damage") > before).toBe(true)
			data.Upgrades.EquipSlots = 5
			data.Currencies.Gems = 1e9
			expect(h:Invoke(player, "BuyUpgrade", "EquipSlots").error).toBe("MaxUpgrade")
			expect(h:Invoke(player, "BuyUpgrade", "Nope").error).toBe("InvalidArguments")
		end)
	end)

	t.describe("ShopService + EventService", function()
		t.it("buys shop items with quantity and validates input", function()
			local h, player, data = setup()
			data.Currencies.Yen = 10000
			local response = h:Invoke(player, "BuyShopItem", "S_XPSmall", 3)
			expect(response.ok).toBe(true)
			expect(data.Currencies.Yen).toBe(8500)
			expect(h:Invoke(player, "BuyShopItem", "S_XPSmall", 1000).error).toBe("InvalidAmount")
			expect(h:Invoke(player, "BuyShopItem", "S_Nope", 1).error).toBe("ShopItemNotFound")
		end)

		t.it("applies game pass perks", function()
			local h, player = setup()
			local Shop = h.Services.ShopService
			expect(h.Services.UnitService:GetEquipSlots(player)).toBe(3)
			Shop:_setOwnedPasses(player, { GP_ExtraEquip = true, GP_2xYen = true })
			expect(h.Services.UnitService:GetEquipSlots(player)).toBe(5)
			expect(Shop:GetPerkValue(player, "YenMultiplier", 1)).toBe(2)
		end)

		t.it("activates weekend events by weekday and runtime events", function()
			local h = setup()
			local Event = h.Services.EventService
			local Clock = h.Clock
			-- Find a Saturday
			while Clock.Weekday(h.Now) ~= 7 do
				h:Advance(86400)
			end
			expect(Event:GetModifier("Yen")).toBe(2)
			h:Advance(86400 * 2) -- Monday
			expect(Event:GetModifier("Yen")).toBe(1)
			Event:StartEvent("Admin2x", 60, { Modifiers = { Damage = 2 } })
			expect(Event:GetModifier("Damage")).toBe(2)
			h:Advance(61)
			expect(Event:GetModifier("Damage")).toBe(1)
		end)
	end)
end
