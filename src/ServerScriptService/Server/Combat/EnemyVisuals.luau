--[[
	EnemyVisuals
	The only part of the enemy system that touches Instances. EnemyService keeps the authoritative state
	in plain tables and calls this adapter to mirror it into the Workspace.

	Model resolution:
	  1. ServerStorage.Assets.<def.Model>  (e.g. Assets/Enemies/W1_Bandit — a Model with a PrimaryPart)
	  2. Otherwise a placeholder (coloured, tier-scaled block + head) is generated so the game is playable
	     before any art exists.

	Every model gets these attributes (read by the client for health bars / targeting):
	  RuntimeId, EnemyId, DisplayName, Tier, Health, MaxHealth, Zone
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Enemies = require(ReplicatedStorage.Shared.Config.Enemies)
local RigBuilder = require(ReplicatedStorage.Shared.Modules.RigBuilder)

local EnemyVisuals = {}

local folder: Folder? = nil

local function getFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local existing = Workspace:FindFirstChild("Enemies")
	if not existing then
		existing = Instance.new("Folder")
		existing.Name = "Enemies"
		existing.Parent = Workspace
	end
	folder = existing :: Folder
	return folder :: Folder
end

local function findAsset(path: string): Instance?
	local node: Instance? = ServerStorage:FindFirstChild("Assets")
	for part in string.gmatch(path, "[^/]+") do
		if not node then
			return nil
		end
		node = node:FindFirstChild(part)
	end
	return node
end

-- Placeholder enemy: a blocky humanoid in the tier's colour, scaled by tier (bosses are giants).
local function buildPlaceholder(def, tier): Model
	local color = Color3.fromRGB(tier.Color[1], tier.Color[2], tier.Color[3])
	return RigBuilder.Build({
		Name = def.Name,
		Scale = tier.Scale,
		Shirt = color,
		Pants = color:Lerp(Color3.new(0, 0, 0), 0.6),
		Hair = color:Lerp(Color3.new(0, 0, 0), 0.75),
		Skin = Color3.fromRGB(235, 190, 150),
	})
end

function EnemyVisuals.Create(enemy): Model?
	local def = enemy.Def
	local tier = Enemies.Tiers[def.Tier]
	local model: Model
	local asset = findAsset(def.Model)
	if asset and asset:IsA("Model") then
		model = asset:Clone()
	else
		model = buildPlaceholder(def, tier)
	end
	model.Name = def.Name
	model:SetAttribute("RuntimeId", enemy.Id)
	model:SetAttribute("EnemyId", def.Id)
	model:SetAttribute("DisplayName", def.Name)
	model:SetAttribute("Tier", def.Tier)
	model:SetAttribute("Health", enemy.Health)
	model:SetAttribute("MaxHealth", enemy.MaxHealth)
	model:SetAttribute("Zone", enemy.ZoneKey)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
	if model.PrimaryPart then
		-- Config positions are 1 stud above ground level (ground top = Y - 1): stand the model on the ground,
		-- facing a random direction so groups don't look cloned.
		local ground = enemy.Position.Y - 1
		local rootHeight = if asset and asset:IsA("Model") then model.PrimaryPart.Size.Y / 2 else RigBuilder.RootHeight(tier.Scale)
		local yaw = math.rad((tonumber(string.match(enemy.Id, "%d+")) or 0) * 47 % 360)
		model:PivotTo(CFrame.new(enemy.Position.X, ground + rootHeight, enemy.Position.Z) * CFrame.Angles(0, yaw, 0))
	end
	model.Parent = getFolder()
	return model
end

function EnemyVisuals.Update(enemy)
	local model = enemy.Handle
	if model and model.Parent then
		model:SetAttribute("Health", enemy.Health)
	end
end

function EnemyVisuals.Destroy(enemy)
	local model = enemy.Handle
	if model then
		model:Destroy()
		enemy.Handle = nil
	end
end

-- Optional map overrides: Workspace.Worlds.<WorldId>.SpawnAreas.<AreaId> (BasePart) -> its position.
function EnemyVisuals.GetAreaCenter(worldId: string, areaId: string): Vector3?
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild(worldId)
	local areas = world and world:FindFirstChild("SpawnAreas")
	local part = areas and areas:FindFirstChild(areaId)
	if part and part:IsA("BasePart") then
		return part.Position
	end
	return nil
end

return EnemyVisuals
