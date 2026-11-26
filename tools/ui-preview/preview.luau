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
local services, playerGui, rt = session.Services, session.PlayerGui, session.Runtime
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

-- 4. Scenes (base game: world 1 core loop) ---------------------------------------------------------------------
-- Transparent overlays for the 3D scene composites (scene.luau)
local function overlay(name: string)
	fs.writeFile(OUT .. "/" .. name .. ".html", Render.Page(playerGui, { Width = 1280, Height = 720, Transparent = true }))
end

overlay("_overlay_hud")
shot("01_hud", "HUD do jogo base (sem janela aberta)")

local Inventory = controller("InventoryController")
UI:Open("Fighters")
task.wait(0.05)
Inventory:Select(raizen.Uid)
shot("02_fighters", "Fighters — lutador selecionado")

UI:Open("Summon", "B_W1")
task.wait(0.05)
overlay("_overlay_orb")
shot("03_summon_orb", "Orbe de invocação (aberto pelo ProximityPrompt no mapa)")

local Summon = controller("SummonController")
task.spawn(Summon.Summon, Summon, 3)
task.wait(1.2)
shot("04_summon_reveal", "Resultado de uma abertura x3")
clearOverlay()

UI:Open("Settings")
task.wait(0.05)
shot("05_settings", "Settings")
UI:Close()

-- New menus (side columns + top-right Update Log card)
local windows = {
	{ "UpdateLog", "08_update_log", "Update Log (card no canto superior direito)" },
	{ "Codes", "09_codes", "Codes" },
	{ "Teleport", "10_teleport", "TP — pontos do mundo 1" },
	{ "Index", "11_index", "Index — lutadores descobertos e ???" },
	{ "Items", "12_inventory", "Inventory — carteira e itens" },
	{ "Achievements", "13_achievements", "Achievements" },
	{ "Stats", "14_stats", "Stats — poder do time, sessão e totais" },
	{ "Quests", "15_quests", "Quests" },
	{ "Mounts", "16_mounts", "Mounts (preparado, sistema ainda não existe)" },
	{ "Shop", "17_shop", "Shop (fechada enquanto Features.Shop = false)" },
}
for _, entry in windows do
	UI:Open(entry[1])
	task.wait(0.05)
	shot(entry[2], entry[3])
end
UI:Close()

-- Phone-sized viewport (landscape) to check scaling
local camera = services.Workspace.CurrentCamera
Fake.SetProperty(camera, "ViewportSize", roblox.Vector2.new(844, 390))
task.wait(0.05)
shot("06_phone_hud", "Celular 844x390 — HUD", 844, 390)
UI:Open("Fighters")
task.wait(0.05)
shot("07_phone_fighters", "Celular 844x390 — Fighters", 844, 390)
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
