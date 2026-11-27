-- The shipped BASE GAME (Config/Features defaults): world 1 core loop only.
local ServerHarness = require("../harness/ServerHarness")

return function(t)
	local expect = t.expect

	local function setup()
		local h = ServerHarness.new({ BaseGame = true })
		h.Services.EnemyService.Random = h.Mocks.Random.new(31)
		h.Services.UnitService.Random = h.Mocks.Random.new(32)
		h.Services.SummonService.Random = h.Mocks.Random.new(33)
		h.Services.CombatService.Random = h.Mocks.Random.new(34)
		local player, data = h:AddPlayer(800, "Rookie", h.Vector3.new(0, 3, 0))
		return h, player, data, h.Vector3
	end

	t.describe("base game", function()
		t.it("starts with Yen, one equipped fighter and no items or traits", function()
			local h, _, data = setup()
			expect(data.Currencies.Yen).toBe(h.GameConfig.Start.Currencies.Yen)
			expect(#data.EquippedUnits).toBe(1)
			expect(next(data.Inventory.Items)).toBeNil()
			expect(data.Inventory.Units[data.EquippedUnits[1]].Trait).toBeNil()
		end)

		t.it("only populates world 1", function()
			local h = setup()
			h.Services.EnemyService:StepSpawners(h.PreciseNow)
			expect(h.Services.EnemyService:CountInZone("World:W1") > 0).toBe(true)
			for _, zone in { "World:W2", "World:W3", "World:W4", "World:W5" } do
				expect(h.Services.EnemyService:CountInZone(zone)).toBe(0)
			end
		end)

		t.it("disabled systems answer FeatureDisabled", function()
			local h, player, data = setup()
			data.Currencies.Yen = 1e9
			data.Currencies.Gems = 1e9
			data.Level = 99
			data.UnlockedWorlds.W3 = true
			local Unit = h.Services.UnitService
			local _, a = Unit:CreateUnit(player, "SS_Kenta")
			local _, b = Unit:CreateUnit(player, "SS_Kenta")
			for _, call in {
				{ "StartRaid", "RAID_Abyss" },
				{ "UnlockWorld", "W2" },
				{ "TeleportWorld", "W1" },
				{ "BuyShopItem", "S_XPSmall", 1 },
				{ "BuyUpgrade", "Damage" },
				{ "FuseUnits", a.Uid, { b.Uid } },
				{ "EvolveUnit", a.Uid },
				{ "UseItem", "XPPotionSmall", a.Uid, 1 },
			} do
				local response = h:Invoke(player, table.unpack(call))
				expect(response.error).toBe("FeatureDisabled")
			end
			expect(h.Services.EventService:GetModifier("Yen")).toBe(1)
		end)

		t.it("kills burst coins: the killer gets Yen and an EnemyDefeated event, no item drops", function()
			local h, player, data, V = setup()
			local Enemy = h.Services.EnemyService
			local yen = data.Currencies.Yen
			for _ = 1, 30 do
				local enemy = Enemy:Spawn("W1_MaskedElite", V.new(5, 3, 0), "World:W1")
				Enemy:ApplyDamage(player, enemy, 1e9)
			end
			expect(data.Currencies.Yen).toBe(yen + 30 * 70)
			expect(next(data.Inventory.Items)).toBeNil()
			local event = h.Net.LastFired(player, "EnemyDefeated")
			expect(event ~= nil).toBe(true)
			local payload = event[1]
			expect(payload.Yen).toBe(70)
			expect(payload.Position[1]).toBe(5)
			expect(payload.Boss).toBe(false)
		end)

		t.it("fighters run to a clicked enemy within reach and auto-target nearby ones", function()
			local h, player, _, V = setup()
			local Enemy, Combat = h.Services.EnemyService, h.Services.CombatService
			local reach = h.GameConfig.Combat.FighterReach
			local clicked = Enemy:Spawn("W1_Bandit", V.new(reach - 5, 3, 0), "World:W1")
			Combat:SetTarget(player, clicked.Id)
			for _ = 1, 400 do
				h:Advance(0.1)
				Combat:Step(h.PreciseNow)
			end
			expect(clicked.Alive).toBe(false)
			-- Fighters only pick enemies inside AutoTargetRange on their own
			local far = Enemy:Spawn("W1_Bandit", V.new(h.GameConfig.Combat.AutoTargetRange + 10, 3, 0), "World:W1")
			for _ = 1, 50 do
				h:Advance(0.1)
				Combat:Step(h.PreciseNow)
			end
			expect(far.Health).toBe(far.MaxHealth)
		end)

		t.it("core loop: farm Yen -> open the star x3 -> equip best -> stronger team", function()
			local h, player, data, V = setup()
			local Enemy, Combat = h.Services.EnemyService, h.Services.CombatService
			local UnitStats = h.Runtime:Require("ReplicatedStorage/Shared/Modules/UnitStats")
			local function teamPower()
				local total = 0
				for _, unit in h.Services.UnitService:GetEquippedUnits(player) do
					total += UnitStats.Compute(unit).Power
				end
				return total
			end
			local powerBefore = teamPower()
			-- Farm until the x3 star is affordable (auto-attack, standing next to the spawned enemies).
			local guard = 0
			while data.Currencies.Yen < 280 * 2 and guard < 30000 do
				guard += 1
				h:Advance(0.1)
				Combat:Step(h.PreciseNow)
				if Enemy:CountInZone("World:W1") == 0 then
					Enemy:Spawn("W1_Bandit", V.new(4, 3, 0), "World:W1")
				end
			end
			expect(data.Currencies.Yen >= 560).toBe(true)
			for _ = 1, 2 do
				expect(h:Invoke(player, "Summon", "B_W1", 3).ok).toBe(true)
			end
			expect(h:Invoke(player, "EquipBest").ok).toBe(true)
			expect(#data.EquippedUnits).toBe(3)
			expect(teamPower() > powerBefore).toBe(true)
		end)
	end)
end
