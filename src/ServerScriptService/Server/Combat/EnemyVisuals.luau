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

local function buildPlaceholder(def, tier): Model
	local scale = tier.Scale
	local color = Color3.fromRGB(tier.Color[1], tier.Color[2], tier.Color[3])
	local model = Instance.new("Model")

	local body = Instance.new("Part")
	body.Name = "HumanoidRootPart"
	body.Size = Vector3.new(2, 3, 1.5) * scale
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(1.6, 1.6, 1.6) * scale
	head.Color = color:Lerp(Color3.new(1, 1, 1), 0.3)
	head.Anchored = true
	head.CanCollide = false
	head.CFrame = body.CFrame * CFrame.new(0, (body.Size.Y + head.Size.Y) / 2, 0)
	head.Parent = model

	model.PrimaryPart = body
	model.Name = def.Name
	return model
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
		model:PivotTo(CFrame.new(enemy.Position + Vector3.new(0, model.PrimaryPart.Size.Y / 2, 0)))
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
