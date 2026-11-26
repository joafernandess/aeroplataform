--[[
	UI preview scene: zone pill, target panel and boss alerts (Lune).
	Stages a fight in Shinobi Valley with fake enemy models and a fake character, then renders the HUD.

	Usage (repo root):
	  lune run tools/ui-preview/scenes/target [outputDir]
	  node tools/ui-preview/screenshot.js [outputDir] [deviceScaleFactor]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Fake = require("../FakeRoblox")
local Render = require("../Render")
local Session = require("../Session")

local OUT = process.args[1] or "ui-preview-out"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end

local Vector3 = roblox.Vector3

local session = Session.new()
local services, playerGui, rt = session.Services, session.PlayerGui, session.Runtime
local controller = session.Controller
local UI = controller("UIController")
local Combat = controller("CombatController")
local h, player = session.Harness, session.Player

local function shot(name: string, caption: string, width: number?, height: number?)
	local html = Render.Page(playerGui, { Width = width or 1280, Height = height or 720, Caption = caption })
	fs.writeFile(OUT .. "/" .. name .. ".html", html)
	print("wrote " .. name)
end

-- Fake character standing at `position` (HumanoidRootPart is all the zone pill needs).
local character = Fake.new("Model")
character.Name = "PreviewPlayer"
local root = Fake.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.Parent = character
character.Parent = services.Workspace
services.Players.LocalPlayer.Character = character

local function moveTo(x: number, y: number, z: number)
	root.Position = Vector3.new(x, y, z)
	root.CFrame = roblox.CFrame.new(x, y, z)
end

-- Fake enemy model with the attributes EnemyVisuals sets on the server.
local enemyCount = 0
local function spawnEnemy(enemyId: string, name: string, tier: string, health: number, maxHealth: number, position: Vector3)
	enemyCount += 1
	local model = Fake.new("Model")
	model.Name = name
	model:SetAttribute("RuntimeId", "E" .. enemyCount)
	model:SetAttribute("EnemyId", enemyId)
	model:SetAttribute("DisplayName", name)
	model:SetAttribute("Tier", tier)
	model:SetAttribute("Health", health)
	model:SetAttribute("MaxHealth", maxHealth)
	model:SetAttribute("Zone", "World:W1")
	local part = Fake.new("Part")
	part.Name = "HumanoidRootPart"
	part.Size = Vector3.new(2, 2, 1)
	part.Position = position
	part.Parent = model
	model.PrimaryPart = part
	model.Parent = services.Workspace.Enemies
	return model
end

-- Server-side attribute change + the signal Roblox would fire.
local function setHealth(model, value: number)
	model:SetAttribute("Health", value)
	model:GetAttributeChangedSignal("Health"):Fire()
end

-- Damage batch exactly as CombatService sends it (through the session's network bridge).
local function hit(model, amount: number, crit: boolean?)
	setHealth(model, math.max(0, model:GetAttribute("Health") - amount))
	h.Net.Fire(player, "DamageNumbers", { { Enemy = model:GetAttribute("RuntimeId"), Amount = amount, Crit = crit == true, Special = false } })
end

-- 1. Fighting a Rogue Ninja in Zone 1 (picked from the damage numbers, trail visible right after the hit)
moveTo(60, 5, 0)
task.wait(0.4)
local ninja = spawnEnemy("W1_RogueNinja", "Rogue Ninja", "Normal", 180, 180, Vector3.new(70, 3, 4))
spawnEnemy("W1_Bandit", "Bandit", "Normal", 60, 60, Vector3.new(50, 3, -6))
task.wait(0.1)
hit(ninja, 40)
task.wait(0.5)
hit(ninja, 38, true)
task.wait(0.05)
shot("01_target_zone1", "Zona 1 + painel do alvo (Rogue Ninja, rastro de dano logo após o golpe)")

-- 2. Elite target selected by click (CombatController.TargetModel)
local elite = spawnEnemy("W1_MaskedElite", "Masked Elite", "Elite", 900, 900, Vector3.new(65, 3, 10))
Combat:SetTarget(elite)
task.wait(0.15)
hit(elite, 310)
task.wait(0.5)
shot("02_target_elite", "Alvo clicado: Masked Elite (tag ELITE)")

-- 2b. Long display name (truncation next to the tag)
local brute = spawnEnemy("W4_Nomu", "Bio-Engineered Brute", "Elite", 2600000, 2600000, Vector3.new(62, 3, 12))
Combat:SetTarget(brute)
task.wait(0.15)
hit(brute, 1150000)
task.wait(0.5)
shot("02b_long_name", "Nome longo truncado ao lado da tag")
Combat:SetTarget(elite)
task.wait(0.15)

-- 3. Zone change: walk to the Ninja Camp -> pill pulse + toast. The fake TweenService applies goals at once, so
-- freeze tweens for this frame to capture the start of the pulse (bigger pill, blue fill, cyan rim).
local tweenService = services.TweenService
local realCreate = tweenService.Create
tweenService.Create = function(_, instance, _info, _goals)
	return { Completed = Fake.Signal(), Play = function() end, Instance = instance }
end
moveTo(150, 5, 60)
task.wait(0.35)
shot("03_zone_change", "Mudança de zona: pulso da pílula + toast 'Entering Zone 2 • Ninja Camp'")
tweenService.Create = realCreate
task.wait(0.3)

-- 4. Boss appears -> alert toast; fight it
local boss = spawnEnemy("W1_SnakeSage", "Bandit King", "MiniBoss", 8000, 8000, Vector3.new(220, 3, -80))
task.wait(0.05)
moveTo(214, 5, -70)
task.wait(0.35)
Combat:SetTarget(boss)
task.wait(0.15)
hit(boss, 2650)
task.wait(0.5)
hit(boss, 420)
task.wait(0.05)
shot("04_boss_alert", "Boss apareceu: toast de alerta + painel MINI BOSS + pílula BOSS")

-- 5. Boss defeated -> toast with the Yen reward, panel fades out
setHealth(boss, 0)
h.Net.Fire(player, "EnemyDefeated", { Enemy = boss:GetAttribute("RuntimeId"), Position = { 220, 3, -80 }, Yen = 600, Boss = true })
task.wait(0.5)
shot("05_boss_defeated", "Boss derrotado: toast '+600 ¥', painel do alvo some")

-- 6. A window is open: zone pill + target panel hidden
local bandit2 = spawnEnemy("W1_Bandit", "Bandit", "Normal", 60, 60, Vector3.new(214, 3, -74))
hit(bandit2, 20)
task.wait(0.15)
UI:Open("Inventory")
task.wait(0.05)
shot("06_window_open", "Janela aberta: pílula de zona e painel ocultos")
UI:Close()

-- 7. World boss with a long name in the boss arena + phone-sized viewport
local warlord = spawnEnemy("W1_NineTails", "Oni Warlord", "WorldBoss", 60000, 60000, Vector3.new(300, 3, 0))
moveTo(296, 5, 8)
task.wait(0.35)
Combat:SetTarget(warlord)
task.wait(0.15)
hit(warlord, 12500)
task.wait(0.5)
shot("07_world_boss", "World boss (tag BOSS) na arena")
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(844, 390))
task.wait(0.05)
hit(warlord, 4000)
task.wait(0.5)
shot("08_phone", "Celular 844x390 — pílula, painel e toasts", 844, 390)
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(1280, 720))

print("")
print(("client warnings: %d"):format(#rt.Mocks.Warnings))
for _, w in rt.Mocks.Warnings do
	print("  " .. w)
end
process.exit(0)
