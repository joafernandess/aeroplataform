--[[
	UnitVisualController
	The visible side of the core loop: your equipped fighters as characters in the world.
	  - Idle: they follow you in a formation behind your character.
	  - Fighting: when the server reports damage on an enemy (DamageNumbers) or you click one, they run to
	    it, surround it and keep lunging at it until it dies or the fight stops.
	Purely cosmetic: the server simulates combat independently (CombatService) and is authoritative.

	Models: ReplicatedStorage.Assets.Units.<UnitId> (a Model with a PrimaryPart) when it exists, otherwise a
	blocky humanoid in the unit's rarity colours (RigBuilder) with its name above the head.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local RigBuilder = require(Shared.Modules.RigBuilder)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local UnitVisualController = {
	Name = "UnitVisualController",
	Priority = 43,
}

UnitVisualController.Visuals = {} :: { [string]: { Model: Model, Scale: number, Position: Vector3? } }
UnitVisualController.FightTarget = nil :: string?
UnitVisualController.LastHitAt = 0

local FIGHTER_SCALE = 0.75
local RUN_SPEED = 38 -- studs per second
local FIGHT_MEMORY = 1.5 -- seconds without damage before fighters return to the player
local FORMATION_SPACING = 3.6
local FORMATION_BACK = 5

local function findAsset(unitId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local units = assets and assets:FindFirstChild("Units")
	local model = units and units:FindFirstChild(unitId)
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

function UnitVisualController:CreateVisual(unit)
	local def = Units.Get(unit.UnitId)
	if not def then
		return nil
	end
	local rarity = Theme.Rarity(def.Rarity)
	local model: Model
	local asset = findAsset(unit.UnitId)
	if asset then
		model = asset:Clone()
	else
		model = RigBuilder.Build({
			Name = def.Name,
			Scale = FIGHTER_SCALE,
			Shirt = rarity,
			Pants = Theme.Darken(rarity, 0.55),
			Hair = Theme.Darken(rarity, 0.25),
		})
	end
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	local head = model:FindFirstChild("Head") or model.PrimaryPart
	local gui = C.Create("BillboardGui", { Size = UDim2.fromOffset(120, 22), StudsOffset = Vector3.new(0, 1.6, 0), MaxDistance = 70, Adornee = head, Parent = model })
	C.Title(gui, def.Name, { Size = UDim2.fromScale(1, 1), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center }, 1.5)
	model.Name = unit.Uid
	model:SetAttribute("UnitId", unit.UnitId)
	model.Parent = self.Folder
	return { Model = model, Scale = if asset then 1 else FIGHTER_SCALE, Position = nil }
end

function UnitVisualController:Sync(data)
	local wanted = {}
	for _, uid in data.EquippedUnits do
		local unit = data.Inventory.Units[uid]
		if unit then
			wanted[uid] = unit
		end
	end
	for uid, visual in self.Visuals do
		local unit = wanted[uid]
		if not unit or visual.Model:GetAttribute("UnitId") ~= unit.UnitId then
			visual.Model:Destroy()
			self.Visuals[uid] = nil
		end
	end
	for uid, unit in wanted do
		if not self.Visuals[uid] then
			self.Visuals[uid] = self:CreateVisual(unit)
		end
	end
end

-- Enemy the fighters should be fighting right now (clicked target first, then whatever is taking damage).
function UnitVisualController:GetFightModel(): Model?
	local health = self.Controllers.EnemyHealthController
	local combat = self.Controllers.CombatController
	if combat and combat.TargetModel and combat.TargetModel.Parent then
		return combat.TargetModel
	end
	if self.FightTarget and os.clock() - self.LastHitAt < FIGHT_MEMORY then
		return health and health:GetModel(self.FightTarget)
	end
	return nil
end

function UnitVisualController:Step(dt: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local data = State.Data
	if not root or not data then
		return
	end
	local groundY = root.Position.Y - 3
	local fightModel = self:GetFightModel()
	local fightPart = fightModel and (fightModel.PrimaryPart or fightModel:FindFirstChildWhichIsA("BasePart"))
	local count = #data.EquippedUnits
	local t = os.clock()

	for index, uid in data.EquippedUnits do
		local visual = self.Visuals[uid]
		if visual and visual.Model.PrimaryPart then
			local goal: Vector3
			local face: Vector3
			local attacking = false
			if fightPart then
				-- Surround the enemy.
				local angle = (index / math.max(count, 1)) * math.pi * 2
				local radius = fightPart.Size.X / 2 + 2.5
				goal = fightPart.Position + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				face = fightPart.Position
				attacking = true
			else
				-- Formation behind the player.
				local offset = Vector3.new((index - (count + 1) / 2) * FORMATION_SPACING, 0, FORMATION_BACK + ((index - 1) % 2) * 1.5)
				goal = (root.CFrame * CFrame.new(offset)).Position
				face = goal + root.CFrame.LookVector
			end
			local rootHeight = RigBuilder.RootHeight(visual.Scale)
			goal = Vector3.new(goal.X, groundY + rootHeight, goal.Z)

			local current = visual.Position or goal
			local delta = goal - current
			local distance = delta.Magnitude
			local step = math.min(distance, RUN_SPEED * dt)
			local position = if distance > 0.01 then current + delta.Unit * step else goal
			visual.Position = position

			local moving = distance > 0.5
			local bob = if moving then math.abs(math.sin(t * 14 + index)) * 0.35 else 0
			local lookAt = if moving and not attacking then position + delta.Unit else Vector3.new(face.X, position.Y, face.Z)
			local cframe = CFrame.lookAt(position + Vector3.new(0, bob, 0), lookAt + Vector3.new(0, bob, 0))
			if attacking and not moving then
				-- Punch rhythm: lunge toward the enemy.
				local lunge = math.max(0, math.sin(t * 9 + index * 1.7)) * 0.9
				cframe *= CFrame.new(0, 0, -lunge)
			end
			visual.Model:PivotTo(cframe)
		end
	end
end

function UnitVisualController:PlayCast(payload)
	local visual = self.Visuals[payload.UnitUid]
	local health = self.Controllers.EnemyHealthController
	local target = health and health:GetModel(payload.Enemy)
	if not visual or not visual.Model.PrimaryPart or not target then
		return
	end
	local targetPart = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart")
	if not targetPart then
		return
	end
	-- Special ability flash: a bright burst on the enemy.
	local burst = C.Create("Part", {
		Shape = Enum.PartType.Ball,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Material = Enum.Material.Neon,
		Color = Theme.Colors.Accent,
		Size = Vector3.new(2, 2, 2),
		CFrame = targetPart.CFrame,
		Transparency = 0.2,
		Parent = self.Folder,
	})
	TweenService:Create(burst, TweenInfo.new(0.35), { Size = Vector3.new(9, 9, 9), Transparency = 1 }):Play()
	task.delay(0.4, function()
		burst:Destroy()
	end)
end

function UnitVisualController:Init(controllers)
	self.Controllers = controllers
	self.Folder = C.Create("Folder", { Name = "LocalFighters", Parent = Workspace })
end

function UnitVisualController:Start()
	State.Observe({ "EquippedUnits", "Inventory" }, function(data)
		self:Sync(data)
	end)
	RunService.RenderStepped:Connect(function(dt)
		self:Step(dt)
	end)
	Net.Connect("DamageNumbers", function(list)
		if type(list) == "table" and list[1] then
			self.FightTarget = list[1].Enemy
			self.LastHitAt = os.clock()
		end
	end)
	Net.Connect("AbilityCast", function(payload)
		if type(payload) == "table" then
			self:PlayCast(payload)
		end
	end)
end

return UnitVisualController
