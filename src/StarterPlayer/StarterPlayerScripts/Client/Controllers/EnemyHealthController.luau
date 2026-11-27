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
	-- Enemy bars are WHITE: blue is reserved for everything that belongs to the player.
	local P = Theme.Colors
	local width = if isBoss then 240 else 170
	local gui = C.Create("BillboardGui", {
		Name = "HealthBar",
		Size = UDim2.fromOffset(width, if isBoss then 52 else 40),
		StudsOffsetWorldSpace = Vector3.new(0, 3.2 * (if tier then tier.Scale else 1), 0),
		MaxDistance = if isBoss then 250 else 65, -- 80 (brief) overlapped badly in crowds
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = root,
		Parent = model,
	})
	C.Title(gui, model:GetAttribute("DisplayName") or model.Name, {
		Font = if isBoss then Theme.Fonts.Display else Theme.Fonts.Title,
		Size = UDim2.new(1, 0, 0, if isBoss then 26 else 20),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextSize = if isBoss then 22 else 14,
	}, if isBoss then 2.5 else 1.5)
	local track = C.Frame(gui, {
		BackgroundColor3 = P.Ink,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -2),
		Size = UDim2.fromOffset(width - 10, if isBoss then 20 else 14),
	})
	C.Corner(track, UDim.new(0.5, 0))
	C.Stroke(track, P.Ink, 2)
	local fill = C.Frame(track, { BackgroundColor3 = P.White, Size = UDim2.fromScale(1, 1), ZIndex = 2 })
	C.Corner(fill, UDim.new(0.5, 0))
	C.Gradient(fill, Theme.Gradients.EnemyHealth.Top, Theme.Gradients.EnemyHealth.Bottom)
	local hpText = C.Number(track, "", { Size = UDim2.fromScale(1, 1), TextSize = if isBoss then 13 else 11, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local bar = {
		Set = function(fraction: number, caption: string)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.001
			hpText.Text = caption
		end,
	}
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
