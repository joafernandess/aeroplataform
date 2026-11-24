--[[
	EnemyHealthController
	Adds a name + health bar billboard to every enemy model in Workspace.Enemies, driven by the
	model's Health/MaxHealth attributes (set by the server). Also keeps a RuntimeId -> model registry
	used by the damage indicators.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Enemies = require(Shared.Config.Enemies)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local EnemyHealthController = {
	Name = "EnemyHealthController",
	Priority = 41,
}

EnemyHealthController.Models = {} :: { [string]: Model }

function EnemyHealthController:GetModel(runtimeId: string): Model?
	local model = self.Models[runtimeId]
	if model and model.Parent then
		return model
	end
	return nil
end

function EnemyHealthController:Attach(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local runtimeId = model:GetAttribute("RuntimeId")
	if not runtimeId then
		return
	end
	self.Models[runtimeId] = model
	local tier = Enemies.Tiers[model:GetAttribute("Tier") or "Normal"]
	local isBoss = tier and tier.IsBoss
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	local gui = C.Create("BillboardGui", {
		Name = "HealthBar",
		Size = UDim2.fromOffset(if isBoss then 240 else 110, if isBoss then 50 else 32),
		StudsOffsetWorldSpace = Vector3.new(0, 3.2 * (if tier then tier.Scale else 1), 0),
		MaxDistance = if isBoss then 250 else 65, -- only nearby enemies show bars, so crowds stay readable
		AlwaysOnTop = true,
		Adornee = root,
		Parent = model,
	})
	local tierColor = if tier and isBoss then Color3.fromRGB(tier.Color[1], tier.Color[2], tier.Color[3]) else Theme.Colors.Text
	C.Title(gui, model:GetAttribute("DisplayName") or model.Name, {
		Size = UDim2.new(1, 0, 0.5, 0),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextScaled = true,
		TextColor3 = tierColor,
	}, 2)
	local bar = C.ProgressBar(gui, Theme.Colors.Bad, { Position = UDim2.fromScale(0, 0.52), Size = UDim2.fromScale(1, 0.46) })
	local function update()
		local health = model:GetAttribute("Health") or 0
		local maxHealth = math.max(model:GetAttribute("MaxHealth") or 1, 1)
		bar.Set(health / maxHealth, NumberFormat.Abbreviate(health) .. " / " .. NumberFormat.Abbreviate(maxHealth))
	end
	update()
	model:GetAttributeChangedSignal("Health"):Connect(update)
end

function EnemyHealthController:Start()
	local folder = Workspace:WaitForChild("Enemies", 60)
	if not folder then
		warn("[EnemyHealthController] Workspace.Enemies not found")
		return
	end
	for _, child in folder:GetChildren() do
		self:Attach(child)
	end
	folder.ChildAdded:Connect(function(child)
		self:Attach(child)
	end)
	folder.ChildRemoved:Connect(function(child)
		local runtimeId = child:GetAttribute("RuntimeId")
		if runtimeId then
			self.Models[runtimeId] = nil
		end
	end)
end

return EnemyHealthController
