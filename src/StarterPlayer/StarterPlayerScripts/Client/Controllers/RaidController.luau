--[[
	RaidController
	Raid list (requirements, cooldown, entry cost) and the in-raid HUD (wave, timer, remaining, Leave).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Raids = require(Shared.Config.Raids)
local Requirements = require(Shared.Modules.Requirements)
local Rewards = require(Shared.Modules.Rewards)
local NumberFormat = require(Shared.Modules.NumberFormat)
local Net = require(Shared.Remotes.Net)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local RaidController = {
	Name = "RaidController",
	Priority = 28,
}

RaidController.Active = nil :: { [string]: any }?

function RaidController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	local now = math.floor(workspace:GetServerTimeNow())
	for i, raid in Raids.List do
		local row = C.Frame(self.List, { Size = UDim2.new(1, -8, 0, 96), BackgroundColor3 = Theme.Colors.PanelLight, LayoutOrder = i })
		C.Corner(row)
		C.Label(row, raid.Name, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -180, 0, 24), Font = Theme.Fonts.Bold, TextSize = 18 })
		C.Label(row, ("%d waves • %s limit • Entry: %s"):format(#raid.Waves, NumberFormat.Duration(raid.TimeLimit), if raid.EntryCost then NumberFormat.Abbreviate(raid.EntryCost.Amount) .. " " .. raid.EntryCost.Currency else "Free"), { Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -180, 0, 18), TextSize = 13, TextColor3 = Theme.Colors.TextDim })
		C.Label(row, "Rewards: " .. Rewards.Describe(raid.Rewards), { Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -180, 0, 18), TextSize = 12, TextColor3 = Theme.Colors.Accent })
		local ok, reason = Requirements.Check(data, raid.Requirements)
		local cooldown = (data.RaidCooldowns[raid.Id] or 0) - now
		local status = if not ok then "Locked: " .. tostring(reason) elseif cooldown > 0 then "Cooldown: " .. NumberFormat.Duration(cooldown) else "Ready"
		C.Label(row, status, { Position = UDim2.fromOffset(12, 72), Size = UDim2.new(1, -180, 0, 18), TextSize = 13, TextColor3 = if status == "Ready" then Theme.Colors.Good else Theme.Colors.Bad })
		C.Button(row, "Start", function()
			local response = State.Request("StartRaid", raid.Id)
			if response.ok then
				self.Controllers.UIController:Close("Raids")
			end
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(140, 44), BackgroundColor3 = if status == "Ready" then Theme.Colors.Accent else Theme.Colors.Panel })
	end
end

function RaidController:RenderHUD()
	local active = self.Active
	self.HUD.Visible = active ~= nil
	if not active then
		return
	end
	local raid = Raids.Get(active.Raid)
	local remaining = math.max(0, (active.EndsAt or math.floor(workspace:GetServerTimeNow())) - math.floor(workspace:GetServerTimeNow()))
	self.HUDTitle.Text = (if raid then raid.Name else "Raid") .. ("  •  Wave %d/%d"):format(active.Wave or 0, active.Waves or 0)
	self.HUDInfo.Text = ("Time left: %s  •  Enemies: %d"):format(NumberFormat.Duration(remaining), active.Remaining or 0)
end

function RaidController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Raids", "Raids", nil, function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8)

	local root = controllers.UIController:GetRoot()
	self.HUD = C.Frame(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90), Size = UDim2.fromOffset(380, 76), Visible = false })
	controllers.UIController:AddScaled(self.HUD, "Hud")
	C.Corner(self.HUD)
	C.Stroke(self.HUD, Theme.Colors.Tokens, 2)
	self.HUDTitle = C.Label(self.HUD, "", { Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -110, 0, 26), Font = Theme.Fonts.Bold })
	self.HUDInfo = C.Label(self.HUD, "", { Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -110, 0, 22), TextSize = 14, TextColor3 = Theme.Colors.TextDim })
	C.Button(self.HUD, "Leave", function()
		State.Request("LeaveRaid")
	end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(90, 40), BackgroundColor3 = Theme.Colors.Bad })
end

function RaidController:Start()
	Net.Connect("RaidUpdate", function(payload)
		if type(payload) ~= "table" then
			return
		end
		if payload.State == "Ended" then
			self.Active = nil
		elseif payload.State == "Completed" then
			if State.Notify then
				State.Notify("Raid cleared! " .. Rewards.Describe(payload.Rewards or {}), "Success", 6)
			end
			self.Active = payload
		elseif payload.State == "Failed" then
			if State.Notify then
				State.Notify("Raid failed: " .. tostring(payload.Reason), "Error", 5)
			end
			self.Active = nil
		else
			self.Active = payload
		end
		self:RenderHUD()
	end)
	State.Observe({ "RaidCooldowns", "Level", "UnlockedWorlds" }, function()
		self:Render()
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			self:RenderHUD()
			if self.Window.Frame.Visible then
				self:Render()
			end
		end
	end)
end

return RaidController
