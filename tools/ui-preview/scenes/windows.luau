--[[
	Scene: window layouts that the base game keeps switched off (Lune)
	Turns on Features.Shop and Features.Items (client and server) to render the open Shop (category tabs + item
	cards) and the Inventory item grid with its details panel, plus the Teleport list scrolled to the other worlds.

	Usage (repo root):
	  lune run tools/ui-preview/scenes/windows [outputDir] [--png-icons]
	  node tools/ui-preview/screenshot.js [outputDir] [scale]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local Render = require("../Render")
local Session = require("../Session")

local OUT = process.args[1] or "ui-preview-out/windows"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end
local iconAssets = nil
if table.find(process.args, "--png-icons") then
	iconAssets = {}
	for name, entry in serde.decode("json", fs.readFile("assets/UI_Icons/manifest.json")) do
		iconAssets[name] = "assets/UI_Icons/" .. entry.png
	end
end

local session = Session.new({ IconAssets = iconAssets })
local UI = session.Controller("UIController")
for _, rt in { session.Runtime, session.Harness.Runtime } do
	local Features = rt:Require("ReplicatedStorage/Shared/Config/Features")
	Features.Shop = true
	Features.Items = true
end

local function shot(name: string, caption: string)
	fs.writeFile(OUT .. "/" .. name .. ".html", Render.Page(session.PlayerGui, { Width = 1280, Height = 720, Caption = caption }))
	print("wrote " .. name)
end

UI:Open("Shop")
task.wait(0.1)
shot("01_shop_open", "Shop aberta (Features.Shop = true): abas de categoria, cards com preço e Buy")

local inv = session.Data.Inventory.Items
inv.EvolutionStone, inv.XPPotionSmall, inv.XPPotionMedium, inv.TraitCrystal, inv.ShinobiScroll = 2, 14, 3, 1, 6
session.Harness.Services.DataService:MarkDirty(session.Player, "Inventory")
task.wait(0.1)
UI:Open("Items")
task.wait(0.1)
shot("02_inventory_items", "Inventory com itens (Features.Items = true): grade + detalhes")

-- Teleport: show the other worlds (taller window just for the screenshot)
local TP = session.Controller("TeleportController")
TP.Window.Frame.Size = roblox.UDim2.fromOffset(600, 900)
UI:Open("Teleport")
task.wait(0.1)
shot("03_teleport_worlds", "Teleport: áreas do mundo atual e mundos bloqueados com requisitos")

print(("client warnings: %d"):format(#session.Runtime.Mocks.Warnings))
for _, w in session.Runtime.Mocks.Warnings do
	print("  " .. w)
end
process.exit(0)
