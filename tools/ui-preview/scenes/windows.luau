--[[
	Scene: window layouts that the base game keeps switched off (Lune)
	Renders the game pass Shop with example pass ids, the Inventory item grid with its details panel (Features.Items
	on), and the Teleport list with the other worlds.

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

-- Game pass shop with two released passes (fake ids; prices filled in as Roblox would return them)
local Shop = session.Runtime:Require("ReplicatedStorage/Shared/Config/Shop")
local ShopC = session.Controller("ShopController")
Shop.GamePasses[1].PassId, Shop.GamePasses[2].PassId, Shop.GamePasses[3].PassId = 101, 102, 103
ShopC.Info[101] = { PriceInRobux = 199 }
ShopC.Info[102] = { PriceInRobux = 299 }
ShopC.Info[103] = { PriceInRobux = 149 }
ShopC.Owned[103] = true
ShopC.Refresh = function(self)
	self:Render()
end
UI:Open("Shop")
task.wait(0.1)
shot("01_shop_passes", "Shop de game passes (ids de exemplo): preço em Robux, BUY / OWNED")

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
