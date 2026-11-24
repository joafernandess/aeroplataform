--[[
	DamageIndicatorController
	Floating damage numbers over enemies (batched DamageNumbers remote). Crits are larger and red,
	specials are gold. The number of simultaneous indicators is capped for performance.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local NumberFormat = require(Shared.Modules.NumberFormat)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local DamageIndicatorController = {
	Name = "DamageIndicatorController",
	Priority = 42,
}

local MAX_ACTIVE = 60
local LIFETIME = 0.9
local active = 0

function DamageIndicatorController:Show(model: Model, amount: number, crit: boolean, special: boolean)
	if active >= MAX_ACTIVE then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not root then
		return
	end
	active += 1
	local offset = Vector3.new(math.random(-20, 20) / 10, root.Size.Y / 2 + 1, math.random(-20, 20) / 10)
	local gui = C.Create("BillboardGui", {
		Size = UDim2.fromOffset(if crit then 120 else 90, if crit then 40 else 30),
		StudsOffsetWorldSpace = offset,
		AlwaysOnTop = true,
		MaxDistance = 150,
		Adornee = root,
		Parent = self.Folder,
	})
	local color = if crit then Theme.Colors.Crit elseif special then Theme.Colors.Accent else Color3.new(1, 1, 1)
	local label = C.Label(gui, NumberFormat.Abbreviate(amount) .. (if crit then "!" else ""), {
		Size = UDim2.fromScale(1, 1),
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Title,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
	})
	TweenService:Create(gui, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffsetWorldSpace = offset + Vector3.new(0, 3, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(LIFETIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(LIFETIME, function()
		gui:Destroy()
		active -= 1
	end)
end

function DamageIndicatorController:Init(controllers)
	self.Controllers = controllers
	self.Folder = C.Create("Folder", { Name = "DamageNumbers", Parent = controllers.UIController:GetRoot() })
end

function DamageIndicatorController:Start()
	local health = self.Controllers.EnemyHealthController
	Net.Connect("DamageNumbers", function(list)
		local data = State.Data
		if type(list) ~= "table" or (data and data.Settings.DamageNumbers == false) then
			return
		end
		for _, entry in list do
			local model = health:GetModel(entry.Enemy)
			if model then
				self:Show(model, entry.Amount, entry.Crit == true, entry.Special == true)
			end
		end
	end)
end

return DamageIndicatorController
