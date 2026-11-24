--[[
	CombatController
	Manual targeting: click/tap an enemy to send every equipped unit after it (SetTarget). The server
	validates zone and distance. Right click or X clears the target. The target is highlighted locally.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage.Shared.Remotes.Net)

local CombatController = {
	Name = "CombatController",
	Priority = 40,
}

CombatController.TargetModel = nil :: Model?

local RAY_LENGTH = 500

local function findEnemyModel(instance: Instance?): Model?
	while instance and instance ~= Workspace do
		if instance:IsA("Model") and instance:GetAttribute("RuntimeId") then
			return instance
		end
		instance = instance.Parent
	end
	return nil
end

function CombatController:SetTarget(model: Model?)
	if self.Highlight then
		self.Highlight:Destroy()
		self.Highlight = nil
	end
	self.TargetModel = model
	if model then
		local highlight = Instance.new("Highlight")
		highlight.FillTransparency = 0.7
		highlight.OutlineColor = Color3.fromRGB(255, 200, 40)
		highlight.Parent = model
		self.Highlight = highlight
		Net.Send("SetTarget", model:GetAttribute("RuntimeId"))
		model.AncestryChanged:Once(function()
			if self.TargetModel == model then
				self:SetTarget(nil)
			end
		end)
	else
		Net.Send("SetTarget", nil)
	end
end

function CombatController:TrySelectAt(screenPosition: Vector2)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local enemies = Workspace:FindFirstChild("Enemies")
	if not enemies then
		return
	end
	local ray = camera:ViewportPointToRay(screenPosition.X, screenPosition.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { enemies }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_LENGTH, params)
	local model = result and findEnemyModel(result.Instance)
	if model then
		self:SetTarget(model)
	end
end

function CombatController:Start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:TrySelectAt(Vector2.new(input.Position.X, input.Position.Y))
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 or input.KeyCode == Enum.KeyCode.X then
			if self.TargetModel then
				self:SetTarget(nil)
			end
		end
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		self:SetTarget(nil)
	end)
end

return CombatController
