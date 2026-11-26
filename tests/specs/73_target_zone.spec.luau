-- Zone pill, target panel and boss alerts (ZoneController / TargetPanelController / NotificationController),
-- run on the REAL client bridged to the real server (tools/ui-preview/Session).
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Session = require("../../tools/ui-preview/Session")
local Fake = require("../../tools/ui-preview/FakeRoblox")

local Vector3 = roblox.Vector3

local function addCharacter(s, x: number, z: number)
	local character = Fake.new("Model")
	local root = Fake.new("Part")
	root.Name = "HumanoidRootPart"
	root.Position = Vector3.new(x, 5, z)
	root.Parent = character
	character.Parent = s.Services.Workspace
	s.Services.Players.LocalPlayer.Character = character
	return root
end

local enemyCount = 0
local function addEnemy(s, name: string, tier: string, health: number, maxHealth: number, zone: string?)
	enemyCount += 1
	local model = Fake.new("Model")
	model.Name = name
	model:SetAttribute("RuntimeId", "T" .. enemyCount)
	model:SetAttribute("EnemyId", "Test")
	model:SetAttribute("DisplayName", name)
	model:SetAttribute("Tier", tier)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", maxHealth)
	model:SetAttribute("Zone", zone or "World:W1")
	local part = Fake.new("Part")
	part.Name = "HumanoidRootPart"
	part.Size = Vector3.new(2, 2, 1)
	part.Position = Vector3.new(60, 3, 0)
	part.Parent = model
	model.PrimaryPart = part
	model.Parent = s.Services.Workspace.Enemies
	return model
end

local function setHealth(model, value: number)
	model:SetAttribute("Health", value)
	model:GetAttributeChangedSignal("Health"):Fire()
end

local function damage(s, model, amount: number)
	s.Harness.Net.Fire(s.Player, "DamageNumbers", { { Enemy = model:GetAttribute("RuntimeId"), Amount = amount, Crit = false, Special = false } })
end

-- Texts of the live toasts (top-centre notification stack).
local function toastTexts(s): { string }
	local container = s.Controller("NotificationController").Container
	local out = {}
	for _, toast in container:GetChildren() do
		if toast:IsA("Frame") then
			local message = toast:FindFirstChild("Message")
			if message then
				table.insert(out, message.Text)
			end
		end
	end
	return out
end

local function hasToast(s, fragment: string): boolean
	for _, text in toastTexts(s) do
		if string.find(text, fragment, 1, true) then
			return true
		end
	end
	return false
end

return function(t)
	local expect = t.expect

	t.describe("zone pill, target panel and boss alerts", function()
		t.it("resolves the zone from a position (pure function)", function()
			local s = Session.new()
			local Zone = s.Controller("ZoneController")
			local function text(worldId, x, z)
				return Zone.Resolve(worldId, Vector3.new(x, 3, z)).Text
			end
			-- World 1: Field (60,0) r45, Camp (150,60) r30, bosses at (220,-80) and (300,0), spawn (0,0)
			expect(text("W1", 60, 0)).toBe("ZONE 1 • Bandit Fields")
			expect(text("W1", 60 + 45 + 9, 0)).toBe("ZONE 1 • Bandit Fields") -- inside radius + 10
			expect(text("W1", 150, 60)).toBe("ZONE 2 • Ninja Camp")
			expect(text("W1", 220, -80 + 25)).toBe("BOSS • Bandit King")
			expect(text("W1", 300, 0)).toBe("BOSS • Oni Warlord")
			expect(text("W1", 0, 0)).toBe("Shinobi Valley • Spawn")
			expect(text("W1", -30, 10)).toBe("Shinobi Valley • Spawn") -- NPC row next to the spawn
			expect(text("W1", 500, 500)).toBe("Shinobi Valley")
			expect(text("W1", 220, -80 + 30)).toBe("Shinobi Valley") -- just outside the arena
			-- World 2 sits 1000 studs along X and uses the default area names
			expect(text("W2", 1060, 0)).toBe("ZONE 1 • Field")
			expect(text("W2", 1000, 0)).toBe("Tidebreaker Isles • Spawn")
			-- Kinds, numbering and the announcement text
			local camp = Zone.Resolve("W1", Vector3.new(150, 3, 60))
			expect(camp.Kind).toBe("Zone")
			expect(camp.Index).toBe(2)
			expect(camp.Toast).toBe("Entering Zone 2 • Ninja Camp")
			expect(Zone.Resolve("W1", Vector3.new(0, 3, 0)).Toast).toBeNil()
			-- Map overrides move the area centres
			local moved = Zone.Resolve("W1", Vector3.new(400, 3, 400), { Field = Vector3.new(400, 3, 400) })
			expect(moved.Text).toBe("ZONE 1 • Bandit Fields")
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("follows the character, toasts on zone change and hides while a window is open", function()
			local s = Session.new()
			local Zone = s.Controller("ZoneController")
			local UI = s.Controller("UIController")
			local root = addCharacter(s, 60, 0)
			task.wait(0.35)
			expect(Zone.Container.Visible).toBe(true)
			expect(Zone.Label.Text).toBe("ZONE 1 • Bandit Fields")
			expect(hasToast(s, "Entering Zone 1")).toBe(false) -- first zone after joining is silent

			root.Position = Vector3.new(150, 5, 60)
			task.wait(0.35)
			expect(Zone.Label.Text).toBe("ZONE 2 • Ninja Camp")
			expect(hasToast(s, "Entering Zone 2 • Ninja Camp")).toBe(true)

			UI:Open("Inventory")
			task.wait(0.02)
			expect(Zone.Container.Visible).toBe(false)
			UI:Close()
			task.wait(0.02)
			expect(Zone.Container.Visible).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("shows the damaged or clicked enemy and hides when it dies or is forgotten", function()
			local s = Session.new()
			local Panel = s.Controller("TargetPanelController")
			local Combat = s.Controller("CombatController")
			local UI = s.Controller("UIController")
			addCharacter(s, 60, 0)
			expect(Panel.Panel.Visible).toBe(false)

			-- picked from the damage numbers
			local ninja = addEnemy(s, "Rogue Ninja", "Normal", 180, 180)
			setHealth(ninja, 140)
			damage(s, ninja, 40)
			task.wait(0.15)
			expect(Panel.Panel.Visible).toBe(true)
			expect(Panel.Model).toBe(ninja)
			expect(Panel.NameLabel.Text).toBe("Rogue Ninja")
			expect(Panel.HealthLabel.Text).toBe("140 / 180")
			expect(Panel.Tag.Visible).toBe(false)
			expect(Panel.Fill.Size.X.Scale).toBeCloseTo(140 / 180, 1e-3)
			setHealth(ninja, 90)
			task.wait(0.05)
			expect(Panel.HealthLabel.Text).toBe("90 / 180")

			-- hidden while a window is open
			UI:Open("Inventory")
			task.wait(0.02)
			expect(Panel.Container.Visible).toBe(false)
			UI:Close()
			task.wait(0.02)
			expect(Panel.Container.Visible).toBe(true)

			-- dies -> fades out
			setHealth(ninja, 0)
			task.wait(0.2)
			expect(Panel.Model).toBeNil()
			expect(Panel.Panel.Visible).toBe(false)

			-- a clicked boss wins over damage numbers and shows its tier tag + abbreviated numbers
			local boss = addEnemy(s, "Bandit King", "MiniBoss", 5200, 8000)
			Combat:SetTarget(boss)
			task.wait(0.15)
			expect(Panel.Model).toBe(boss)
			expect(Panel.Tag.Visible).toBe(true)
			expect(Panel.TagLabel.Text).toBe("MINI BOSS")
			expect(Panel.HealthLabel.Text).toBe("5.2K / 8K")
			Combat:SetTarget(nil)
			task.wait(0.15)
			expect(Panel.Panel.Visible).toBe(false)

			-- a damage-picked target is forgotten after FORGET_AFTER seconds without hits
			Panel.FORGET_AFTER = 0.2
			local bandit = addEnemy(s, "Bandit", "Normal", 60, 60)
			damage(s, bandit, 10)
			task.wait(0.1)
			expect(Panel.Model).toBe(bandit)
			task.wait(0.45)
			expect(Panel.Model).toBeNil()
			expect(Panel.Panel.Visible).toBe(false)
			Panel.FORGET_AFTER = 2.5
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("toasts when a boss appears in your world and when you defeat one", function()
			local s = Session.new()
			addCharacter(s, 60, 0)
			addEnemy(s, "Bandit", "Normal", 60, 60)
			task.wait(0.05)
			expect(hasToast(s, "has appeared")).toBe(false)

			addEnemy(s, "Bandit King", "MiniBoss", 8000, 8000)
			task.wait(0.05)
			expect(hasToast(s, "Bandit King has appeared!")).toBe(true)

			-- bosses of another world are ignored
			addEnemy(s, "Sea Warlord", "MiniBoss", 110000, 110000, "World:W2")
			task.wait(0.05)
			expect(hasToast(s, "Sea Warlord")).toBe(false)

			s.Harness.Net.Fire(s.Player, "EnemyDefeated", { Enemy = "T1", Position = { 0, 3, 0 }, Yen = 600, Boss = true })
			task.wait(0.05)
			expect(hasToast(s, "Boss defeated! +600 ¥")).toBe(true)
			-- normal kills stay silent
			s.Harness.Net.Fire(s.Player, "EnemyDefeated", { Enemy = "T2", Position = { 0, 3, 0 }, Yen = 6, Boss = false })
			task.wait(0.05)
			expect(hasToast(s, "+6 ¥")).toBe(false)

			-- identical messages merge into one toast
			local Notifications = s.Controller("NotificationController")
			Notifications:Show("Same message", "Info")
			Notifications:Show("Same message", "Info")
			expect(hasToast(s, "Same message  x2")).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("stacks the top-centre HUD: zone pill y 10, target panel y 46, toasts y 112", function()
			local s = Session.new()
			local Zone = s.Controller("ZoneController")
			local Panel = s.Controller("TargetPanelController")
			local Notifications = s.Controller("NotificationController")
			local UI = s.Controller("UIController")
			-- all three share the same top-centre anchor so the HUD UIScale keeps the stack proportions
			for _, frame in { Zone.Container, Panel.Container, Notifications.Container } do
				expect(frame.AnchorPoint.X).toBe(0.5)
				expect(frame.AnchorPoint.Y).toBe(0)
				expect(frame.Position.Y.Offset).toBe(10)
			end
			expect(Zone.Container.Size.Y.Offset).toBe(30)
			expect(Panel.Panel.Position.Y.Offset + 10).toBe(46)
			expect(Panel.Panel.Size.Y.Offset).toBe(56)
			local padding = Notifications.Container:FindFirstChildOfClass("UIPadding")
			expect(padding.PaddingTop.Offset + 10).toBe(112)
			-- with a window open the pill/panel are hidden and toasts move to the top edge
			UI:Open("Inventory")
			task.wait(0.02)
			expect(padding.PaddingTop.Offset).toBe(0)
			UI:Close()
			task.wait(0.02)
			expect(padding.PaddingTop.Offset + 10).toBe(112)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
