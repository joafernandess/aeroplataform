--[[
	Scene preview (Lune)
	Builds the REAL greybox map (MapService:BuildGreybox) and the same placeholder rigs the game uses
	(RigBuilder) for a staged moment of the core loop, then exports every part to a three.js page.
	The real UI (rendered by preview.luau as transparent overlays) is layered on top.

	Usage (repo root, after preview.luau wrote the overlays into outputDir):
	  lune run tools/ui-preview/scene <outputDir> <path/to/three.min.js>

	Approximation: flat colours, simple lighting, no Roblox materials/textures, billboards drawn as HTML.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local Runtime = require("../../tests/harness/Runtime")

local OUT = process.args[1] or "ui-preview-out"
local THREE = process.args[2] or "node_modules/three/build/three.min.js"

local CFrame, Vector3, Color3 = roblox.CFrame, roblox.Vector3, roblox.Color3

-- 1. Real map ---------------------------------------------------------------------------------------------------
local rt = Runtime.new({ IsServer = true })
local dataModel = roblox.Instance.new("DataModel")
local workspace = dataModel:GetService("Workspace")
rt.Services.Workspace = workspace
rt.Globals.workspace = workspace
local MapService = rt:Require("ServerScriptService/Server/Services/MapService")
local RigBuilder = rt:Require("ReplicatedStorage/Shared/Modules/RigBuilder")
local Enemies = rt:Require("ReplicatedStorage/Shared/Config/Enemies")
local Worlds = rt:Require("ReplicatedStorage/Shared/Config/Worlds")
local Rarities = rt:Require("ReplicatedStorage/Shared/Config/Rarities")
local mapRoot = MapService:BuildGreybox()

-- 2. Staged actors ------------------------------------------------------------------------------------------------
local actors = roblox.Instance.new("Folder")
actors.Name = "Actors"
actors.Parent = workspace
local labels = {}
local GROUND = 2

local function place(model, cframe)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CFrame = cframe * part.CFrame
		end
	end
	model.Parent = actors
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function enemyRig(enemyId: string, x: number, z: number, yaw: number, hpFraction: number)
	local def = Enemies.Get(enemyId)
	local tier = Enemies.Tiers[def.Tier]
	local color = rgb(tier.Color)
	local rig = RigBuilder.Build({ Scale = tier.Scale, Shirt = color, Pants = color:Lerp(Color3.new(0, 0, 0), 0.6), Hair = color:Lerp(Color3.new(0, 0, 0), 0.75), Skin = Color3.fromRGB(235, 190, 150) })
	local root = Vector3.new(x, GROUND + RigBuilder.RootHeight(tier.Scale), z)
	place(rig, CFrame.new(root) * CFrame.Angles(0, yaw, 0))
	table.insert(labels, {
		Kind = "Enemy",
		Position = { root.X, root.Y + 3.2 * tier.Scale, root.Z },
		Text = def.Name,
		Fraction = hpFraction,
		Max = def.MaxHP,
		Boss = def.IsBoss,
		Color = if def.IsBoss then tier.Color else { 255, 255, 255 },
	})
	return root
end

local function fighterRig(name: string, rarity: string, at, faceTo)
	local color = rgb(Rarities.Get(rarity).Color)
	local scale = 0.75
	local rig = RigBuilder.Build({ Scale = scale, Shirt = color, Pants = color:Lerp(Color3.new(0, 0, 0), 0.55), Hair = color:Lerp(Color3.new(0, 0, 0), 0.25) })
	local root = Vector3.new(at.X, GROUND + RigBuilder.RootHeight(scale), at.Z)
	place(rig, CFrame.lookAt(root, Vector3.new(faceTo.X, root.Y, faceTo.Z)))
	table.insert(labels, { Kind = "Fighter", Position = { root.X, root.Y + 2.9, root.Z }, Text = name, Color = Rarities.Get(rarity).Color })
end

math.randomseed(7)
local world = Worlds.Get("W1")

-- Enemies spread through both zones
for _, area in world.SpawnAreas do
	local weights = area.Enemies
	for i = 1, area.MaxEnemies do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * area.Radius
		local x = area.Center[1] + math.cos(angle) * distance
		local z = area.Center[3] + math.sin(angle) * distance
		local pick, total = nil, 0
		for _, w in weights do
			total += w
		end
		local roll = math.random() * total
		for id, w in weights do
			roll -= w
			if roll <= 0 and not pick then
				pick = id
			end
		end
		if not (math.abs(x - 50) < 8 and math.abs(z + 4) < 8) then
			enemyRig(pick or "W1_Bandit", x, z, math.random() * math.pi * 2, if i % 4 == 0 then 0.6 else 1)
		end
	end
end
for _, boss in world.Bosses do
	enemyRig(boss.Enemy, boss.Position[1], boss.Position[3], math.rad(90), 1)
end

-- The fight: the player clicked a bandit, three fighters surround it, coins from the previous kill.
local target = enemyRig("W1_Bandit", 50, -4, math.rad(-90), 0.35)
local player = RigBuilder.Build({ Skin = Color3.fromRGB(245, 205, 48), Shirt = Color3.fromRGB(13, 105, 172), Pants = Color3.fromRGB(164, 189, 71), Hair = Color3.fromRGB(245, 205, 48) })
local playerRoot = Vector3.new(36, GROUND + 3, -2)
place(player, CFrame.lookAt(playerRoot, Vector3.new(50, playerRoot.Y, -4)))
table.insert(labels, { Kind = "Yen", Position = { playerRoot.X, playerRoot.Y + 5, playerRoot.Z }, Text = "+15 ¥" })
local fighters = { { "Raizen", "Legendary" }, { "Tetsuo", "Epic" }, { "Genin Recruit", "Common" } }
for i, f in fighters do
	local angle = math.rad(150 + (i - 1) * 60)
	fighterRig(f[1], f[2], Vector3.new(target.X + math.cos(angle) * 3.5, 0, target.Z + math.sin(angle) * 3.5), target)
end
for i, dmg in { { "633", false }, { "1.27K!", true }, { "113", false } } do
	table.insert(labels, { Kind = "Damage", Position = { target.X + (i - 2) * 1.6, target.Y + 4.5 + i * 0.7, target.Z }, Text = dmg[1], Crit = dmg[2] })
end
for i = 1, 7 do
	local angle = i * 0.9
	local coin = roblox.Instance.new("Part")
	coin.Shape = roblox.Enum.PartType.Cylinder
	coin.Size = Vector3.new(0.25, 1.3, 1.3)
	coin.Color = Color3.fromRGB(30, 107, 255) -- CoinController uses Theme.Colors.Yen (Blue500)
	coin.Material = roblox.Enum.Material.Neon
	coin.CFrame = CFrame.new(42 + math.cos(angle) * 3, GROUND + 0.7 + (i % 3) * 0.6, -9 + math.sin(angle) * 3) * CFrame.Angles(0, angle, 0)
	coin.Parent = actors
end

-- A second player at the summon orb, about to open it.
local visitor = RigBuilder.Build({ Skin = Color3.fromRGB(255, 214, 170), Shirt = Color3.fromRGB(200, 40, 60), Pants = Color3.fromRGB(40, 40, 50), Hair = Color3.fromRGB(60, 40, 30) })
local visitorRoot = Vector3.new(-16, GROUND + 3, -11)
place(visitor, CFrame.lookAt(visitorRoot, Vector3.new(-25, visitorRoot.Y, -20)))
table.insert(labels, { Kind = "Prompt", Position = { -23, GROUND + 4, -18 }, Object = "Shinobi Star", Text = "Open" })

-- Map billboards (spawn name, zone signs, orb price) become HTML labels.
for _, gui in mapRoot:GetDescendants() do
	if gui:IsA("BillboardGui") and gui.Parent and gui.Parent:IsA("BasePart") then
		local label = gui:FindFirstChildOfClass("TextLabel")
		if label then
			local at = gui.Parent.CFrame.Position + gui.StudsOffset
			local c = label.TextColor3
			table.insert(labels, {
				Kind = "Sign",
				Position = { at.X, at.Y, at.Z },
				Text = label.Text,
				Size = if string.find(label.Text, "\n") then 22 else 18,
				Color = { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) },
			})
		end
	end
end

-- 3. Export -------------------------------------------------------------------------------------------------------
local parts = {}
local function collect(root)
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and part.Transparency < 0.99 then
			local shape = "Block"
			if part:IsA("Part") then
				shape = part.Shape.Name
			end
			local c = { part.CFrame:GetComponents() }
			table.insert(parts, {
				s = shape,
				z = { part.Size.X, part.Size.Y, part.Size.Z },
				m = c,
				c = { math.floor(part.Color.R * 255), math.floor(part.Color.G * 255), math.floor(part.Color.B * 255) },
				n = part.Material.Name == "Neon",
				t = part.Transparency,
			})
		end
	end
end
collect(mapRoot)
collect(actors)

local CAMERAS = {
	gameplay = { Position = { 14, 20, -14 }, LookAt = { 52, 4, -2 }, Fov = 70 },
	orb = { Position = { 4, 15, 4 }, LookAt = { -24, 8, -19 }, Fov = 70 },
	overview = { Position = { -70, 150, -190 }, LookAt = { 120, 0, 10 }, Fov = 55 },
}

local function page(name: string, cameraName: string, overlay: string?, caption: string)
	local data = serde.encode("json", { Parts = parts, Labels = labels, Camera = CAMERAS[cameraName] })
	local template = fs.readFile("tools/ui-preview/scene.html")
	local html = template:gsub("__THREE__", THREE):gsub("__CAPTION__", caption):gsub("__OVERLAY__", overlay or ""):gsub("__DATA__", function()
		return data
	end)
	fs.writeFile(OUT .. "/" .. name .. ".html", html)
	print("wrote " .. name .. " (" .. #parts .. " parts)")
end

page("20_game_fight", "gameplay", "_overlay_hud.html", "Jogo base — clique num inimigo: seus lutadores correm e batem, moedas voam até você")
page("21_game_orb", "orb", "_overlay_hud.html", "Orbe de invocação perto do spawn — Yen dos inimigos abre lutadores (x1 / x3)")
page("22_world1_map", "overview", nil, "Mundo 1 visto de cima — spawn, orbe, zonas 1 e 2, chefes (mapa greybox gerado pelo código)")
process.exit(0)
