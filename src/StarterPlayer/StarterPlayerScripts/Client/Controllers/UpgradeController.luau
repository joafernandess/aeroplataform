--[[
	UpgradeController
	Permanent upgrades (Config/Progression.Upgrades): level, effect, next cost, Buy.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Progression = require(Shared.Config.Progression)
local Formulas = require(Shared.Modules.Formulas)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local UpgradeController = {
	Name = "UpgradeController",
	Priority = 26,
}

function UpgradeController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	for i, upgradeId in Progression.UpgradeOrder do
		local def = Progression.Upgrades[upgradeId]
		local level = data.Upgrades[upgradeId] or 0
		local cost = Formulas.UpgradeCost(upgradeId, level)
		local row = C.Row(self.List, { Size = UDim2.new(1, -8, 0, 62), LayoutOrder = i })
		C.Label(row, ("%s  (Lv %d/%d)"):format(def.Name, level, def.MaxLevel), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -200, 0, 24), Font = Theme.Fonts.Bold })
		C.Label(row, def.Description, { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -200, 0, 20), TextSize = 13, TextColor3 = Theme.Colors.TextDim })
		local affordable = cost ~= nil and (data.Currencies[def.Currency] or 0) >= cost
		C.Button(row, if cost then ("%s %s"):format(NumberFormat.Abbreviate(cost), def.Currency) else "MAX", if cost
			then function()
				State.Request("BuyUpgrade", upgradeId)
			end
			else nil, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(170, 40),
			Kind = if affordable then "Primary" else "Dark",
		})
	end
end

function UpgradeController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Upgrades", "Upgrades", nil, function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 6)
end

function UpgradeController:Start()
	State.Observe({ "Upgrades", "Currencies" }, function()
		self:Render()
	end)
end

return UpgradeController
