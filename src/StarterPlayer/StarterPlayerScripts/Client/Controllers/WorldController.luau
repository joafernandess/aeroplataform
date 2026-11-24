--[[
	WorldController
	World list with unlock requirements, costs, teleport and unlock buttons.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Config.Worlds)
local Requirements = require(Shared.Modules.Requirements)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local WorldController = {
	Name = "WorldController",
	Priority = 23,
}

function WorldController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	for i, world in Worlds.List do
		local unlocked = data.UnlockedWorlds[world.Id] == true
		local current = data.CurrentWorld == world.Id
		local row = C.Frame(self.List, { Size = UDim2.new(1, -8, 0, 70), BackgroundColor3 = Theme.Colors.PanelLight, LayoutOrder = i })
		C.Corner(row)
		C.Stroke(row, Color3.fromRGB(world.Theme[1], world.Theme[2], world.Theme[3]), if current then 3 else 1.5)
		C.Label(row, ("%d. %s%s"):format(world.Order, world.Name, if current then "  (you are here)" else ""), { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -200, 0, 26), Font = Theme.Fonts.Bold, TextSize = 18 })
		local status
		if unlocked then
			status = if data.ClearedWorlds[world.Id] then "Unlocked • Cleared" else "Unlocked"
		else
			local previous = Worlds.GetPrevious(world.Id)
			local ok, reason = Requirements.Check(data, world.Requirements)
			if previous and not data.UnlockedWorlds[previous.Id] then
				status = "Locked: unlock " .. previous.Name .. " first"
			elseif not ok then
				status = "Locked: " .. tostring(reason)
			else
				status = ("Cost: %s %s"):format(NumberFormat.Abbreviate(world.UnlockCost.Amount), world.UnlockCost.Currency)
			end
		end
		C.Label(row, status, { Position = UDim2.fromOffset(12, 36), Size = UDim2.new(1, -200, 0, 22), TextSize = 14, TextColor3 = if unlocked then Theme.Colors.Good else Theme.Colors.TextDim })
		if unlocked then
			C.Button(row, "Teleport", function()
				local response = State.Request("TeleportWorld", world.Id)
				if response.ok then
					self.Controllers.UIController:Close("Worlds")
				end
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 40), BackgroundColor3 = Theme.Colors.Info })
		else
			C.Button(row, "Unlock", function()
				local response = State.Request("UnlockWorld", world.Id)
				if response.ok and State.Notify then
					State.Notify(world.Name .. " unlocked!", "Success")
				end
			end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 40), BackgroundColor3 = Theme.Colors.Accent, TextColor3 = Theme.Colors.Background })
		end
	end
end

function WorldController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Worlds", "Worlds", nil, function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8)
end

function WorldController:Start()
	State.Observe({ "UnlockedWorlds", "CurrentWorld", "Level", "Currencies", "ClearedWorlds" }, function()
		self:Render()
	end)
end

return WorldController
