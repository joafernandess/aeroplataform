--[[
	UI preview (Lune)
	Runs the REAL server services (test harness) and the REAL client controllers (Main.client.luau) against
	fake Instances, connected by an in-process network bridge, then renders each screen to HTML.

	Usage (repo root):
	  lune run tools/ui-preview/preview [outputDir]
	  node tools/ui-preview/screenshot.js [outputDir]

	This is an approximation of Roblox's renderer (fonts differ: Inter instead of Gotham; no 3D world).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Fake = require("./FakeRoblox")
local Render = require("./Render")
local Session = require("./Session")

local OUT = process.args[1] or "ui-preview-out"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end

local session = Session.new()
local services, playerGui, rt, clientNet = session.Services, session.PlayerGui, session.Runtime, session.Net
local raizen = session.Units.Raizen
local controller = session.Controller
local UI = controller("UIController")


local function shot(name: string, caption: string, width: number?, height: number?)
	local html = Render.Page(playerGui, { Width = width or 1280, Height = height or 720, Caption = caption })
	fs.writeFile(OUT .. "/" .. name .. ".html", html)
	print("wrote " .. name)
end

local function clearOverlay()
	for _, child in UI.Overlay:GetChildren() do
		child:Destroy()
	end
end

-- 4. Scenes --------------------------------------------------------------------------------------------------
shot("01_hud", "HUD (no window open) — 3D world not rendered in this preview")

local Inventory = controller("InventoryController")
UI:Open("Inventory")
task.wait(0.05)
Inventory:Select(raizen.Uid)
shot("02_units", "Units window — unit selected")

Inventory.Tab = "Items"
Inventory:Render()
shot("03_items", "Units window — Items tab")
Inventory.Tab = "Units"

UI:Open("Summon", "B_W3")
task.wait(0.05)
shot("04_summon", "Summon window")

local Summon = controller("SummonController")
task.spawn(Summon.Summon, Summon, 10)
task.wait(1.5)
shot("05_summon_reveal", "Summon x10 results")
clearOverlay()

UI:Open("Worlds")
task.wait(0.05)
shot("06_worlds", "Worlds window")

UI:Open("Quests")
task.wait(0.05)
shot("07_quests", "Quests window")
local Quest = controller("QuestController")
Quest.Tab = "Achievements"
Quest:Render()
shot("08_achievements", "Quests window — Achievements tab")
Quest.Tab = "Quests"

UI:Open("Shop")
task.wait(0.05)
shot("09_shop", "Shop window")

UI:Open("Upgrades")
task.wait(0.05)
shot("10_upgrades", "Upgrades window")

UI:Open("Settings")
task.wait(0.05)
shot("11_settings", "Settings window")

UI:Open("Raids")
task.wait(0.05)
shot("12_raids", "Raids window")

UI:Close()
local raid = clientNet.Request("StartRaid", "RAID_Abyss")
task.wait(0.1)
shot("13_raid_hud", "In-raid HUD" .. (if raid.ok then "" else " (start failed: " .. tostring(raid.error) .. ")"))
clientNet.Request("LeaveRaid")
task.wait(0.1)

-- Phone-sized viewport (landscape) to check scaling
local camera = services.Workspace.CurrentCamera
Fake.SetProperty(camera, "ViewportSize", roblox.Vector2.new(844, 390))
task.wait(0.05)
UI:Open("Inventory")
task.wait(0.05)
shot("14_phone_units", "Phone landscape 844x390 — Units window", 844, 390)
UI:Close()
shot("15_phone_hud", "Phone landscape 844x390 — HUD", 844, 390)
UI:Open("Summon")
task.wait(0.05)
shot("16_phone_summon", "Phone landscape 844x390 — Summon window", 844, 390)
UI:Close()
Fake.SetProperty(camera, "ViewportSize", roblox.Vector2.new(1280, 720))

-- 5. Report client runtime warnings (errors inside controllers surface here) ---------------------------------
print("")
print(("client warnings: %d"):format(#rt.Mocks.Warnings))
for _, w in rt.Mocks.Warnings do
	print("  " .. w)
end
local _ = roblox
process.exit(0)
