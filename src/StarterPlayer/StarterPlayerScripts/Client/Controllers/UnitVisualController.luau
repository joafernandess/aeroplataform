--[[
	UnitVisualController
	Cosmetic representation of the local player's equipped units: they float in a ring behind the
	character. Purely visual — the server simulates combat independently.

	Models: ReplicatedStorage.Assets.Units.<UnitId> (a Model with a PrimaryPart) if it exists, otherwise a
	rarity-coloured placeholder orb with the unit's name. (Unit models must live in ReplicatedStorage to be
	visible to clients; see docs/STUDIO_SETUP.md.)
	When a special ability is cast (AbilityCast), the unit flashes and a beam is drawn to the target.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local UnitVisualController = {
	Name = "UnitVisualController",
	Priority = 43,
}

UnitVisualController.Visuals = {} :: { [string]: Model }

local RING_RADIUS = 6
local FOLLOW_SPEED = 8

local function findAsset(unitId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local units = assets and assets:FindFirstChild("Units")
	local model = units and units:FindFirstChild(unitId)
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

function UnitVisualController:CreateVisual(unit): Model?
	local def = Units.Get(unit.UnitId)
	if not def then
		return nil
	end
	local model: Model
	local asset = findAsset(unit.UnitId)
	if asset then
		model = asset:Clone()
	else
		model = Instance.new("Model")
		local orb = C.Create("Part", {
			Name = "Root",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(2, 2, 2),
			Color = Theme.Rarity(def.Rarity),
			Material = Enum.Material.Neon,
			Parent = model,
		})
		model.PrimaryPart = orb
		local gui = C.Create("BillboardGui", { Size = UDim2.fromOffset(110, 20), StudsOffset = Vector3.new(0, 2, 0), MaxDistance = 60, Adornee = orb, Parent = model })
		C.Label(gui, def.Name, { Size = UDim2.fromScale(1, 1), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Bold, TextColor3 = Theme.Rarity(def.Rarity), TextStrokeTransparency = 0.4 })
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CastShadow = false
		end
	end
	model.Name = unit.Uid
	model.Parent = self.Folder
	return model
end

function UnitVisualController:Sync(data)
	local wanted = {}
	for _, uid in data.EquippedUnits do
		local unit = data.Inventory.Units[uid]
		if unit then
			wanted[uid] = unit
		end
	end
	for uid, model in self.Visuals do
		local unit = wanted[uid]
		if not unit or model:GetAttribute("UnitId") ~= unit.UnitId then
			model:Destroy()
			self.Visuals[uid] = nil
		end
	end
	for uid, unit in wanted do
		if not self.Visuals[uid] then
			local model = self:CreateVisual(unit)
			if model then
				model:SetAttribute("UnitId", unit.UnitId)
				self.Visuals[uid] = model
			end
		end
	end
end

function UnitVisualController:Step(dt: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local data = State.Data
	if not data then
		return
	end
	local count = #data.EquippedUnits
	local t = os.clock()
	for index, uid in data.EquippedUnits do
		local model = self.Visuals[uid]
		if model and model.PrimaryPart then
			local angle = math.pi * (0.5 + (index - 0.5) / math.max(count, 1))
			local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 1.5 + math.sin(t * 2 + index) * 0.3, math.sin(angle) * RING_RADIUS)
			local goal = root.CFrame * CFrame.new(offset)
			local current = model:GetPivot()
			model:PivotTo(current:Lerp(CFrame.new(goal.Position, goal.Position + root.CFrame.LookVector), math.clamp(dt * FOLLOW_SPEED, 0, 1)))
		end
	end
end

function UnitVisualController:PlayCast(payload)
	local model = self.Visuals[payload.UnitUid]
	local health = self.Controllers.EnemyHealthController
	local target = health and health:GetModel(payload.Enemy)
	if not model or not model.PrimaryPart then
		return
	end
	local from = model.PrimaryPart.Position
	if target then
		local targetPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
		if targetPart then
			local to = targetPart.Position
			local beam = C.Create("Part", {
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				Material = Enum.Material.Neon,
				Color = Theme.Colors.Accent,
				Size = Vector3.new(0.4, 0.4, (to - from).Magnitude),
				CFrame = CFrame.lookAt((from + to) / 2, to),
				Parent = self.Folder,
			})
			TweenService:Create(beam, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(0.05, 0.05, beam.Size.Z) }):Play()
			task.delay(0.4, function()
				beam:Destroy()
			end)
		end
	end
end

function UnitVisualController:Init(controllers)
	self.Controllers = controllers
	self.Folder = C.Create("Folder", { Name = "LocalUnits", Parent = Workspace })
end

function UnitVisualController:Start()
	State.Observe({ "EquippedUnits", "Inventory" }, function(data)
		self:Sync(data)
	end)
	RunService.RenderStepped:Connect(function(dt)
		self:Step(dt)
	end)
	Net.Connect("AbilityCast", function(payload)
		if type(payload) == "table" then
			self:PlayCast(payload)
		end
	end)
end

return UnitVisualController
