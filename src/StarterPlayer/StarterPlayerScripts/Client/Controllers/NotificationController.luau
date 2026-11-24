--[[
	NotificationController
	Toast notifications (server "Notify" remote, level ups, request errors through State.Notify).
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)
local Net = require(ReplicatedStorage.Shared.Remotes.Net)

local NotificationController = {
	Name = "NotificationController",
	Priority = 2,
}

local KIND_COLORS = {
	Info = Theme.Colors.Info,
	Success = Theme.Colors.Good,
	Error = Theme.Colors.Bad,
	Quest = Theme.Colors.Accent,
	Level = Theme.Colors.XP,
}

local MAX_TOASTS = 5
local counter = 0

function NotificationController:Show(text: string, kind: string?, duration: number?)
	local container = self.Container
	local toasts = {}
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts >= MAX_TOASTS then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	counter += 1
	local toast = C.Frame(container, { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Theme.Colors.Panel, LayoutOrder = counter })
	C.Corner(toast)
	C.Stroke(toast, KIND_COLORS[kind or "Info"] or Theme.Colors.Info, 2)
	local label = C.Label(toast, text, { Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextWrapped = true, TextSize = 15, Font = Theme.Fonts.Bold })
	task.delay(duration or 3, function()
		if toast.Parent then
			local tween = TweenService:Create(toast, TweenInfo.new(0.3), { BackgroundTransparency = 1 })
			TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			tween:Play()
			tween.Completed:Wait()
			toast:Destroy()
		end
	end)
end

function NotificationController:Init(controllers)
	self.Controllers = controllers
	self.Container = C.Frame(controllers.UIController:GetRoot(), {
		Name = "Notifications",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 90),
		Size = UDim2.fromOffset(300, 300),
		ZIndex = 60,
	})
	C.List(self.Container, Enum.FillDirection.Vertical, 6)
	controllers.UIController:AddScaled(self.Container, "Hud")
	State.Notify = function(text, kind)
		self:Show(text, kind)
	end
end

function NotificationController:Start()
	Net.Connect("Notify", function(payload)
		if type(payload) == "table" and type(payload.Text) == "string" then
			self:Show(payload.Text, payload.Kind, payload.Duration)
		end
	end)
	Net.Connect("LevelUp", function(payload)
		self:Show(("Level up! You are now level %d"):format(payload.Level), "Level", 4)
	end)
end

return NotificationController
