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

-- Side bar colour + icon glyph per kind (all within the black/white/blue palette).
local KINDS = {
	Info = { Bar = Theme.Colors.Blue500, Glyph = "i" },
	Success = { Bar = Theme.Colors.Cyan, Glyph = "✓" },
	Warning = { Bar = Theme.Colors.White, Glyph = "!" },
	Error = { Bar = Theme.Colors.Ink, Glyph = "!", Inverted = true },
	Quest = { Bar = Theme.Colors.Blue500, Glyph = "☰" },
	Level = { Bar = Theme.Colors.Cyan, Glyph = "▲" },
}

local MAX_TOASTS = 3
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
	local style = KINDS[kind or "Info"] or KINDS.Info
	local P = Theme.Colors
	local toast = C.Frame(container, { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = P.Panel, LayoutOrder = counter })
	C.Corner(toast, Theme.Radius.Toast)
	C.Stroke(toast, if style.Inverted then P.White else P.Ink, if style.Inverted then 2.5 else 3)
	local bar = C.Frame(toast, { BackgroundColor3 = style.Bar, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0, 6, 1, -16), ZIndex = 2 })
	C.Corner(bar, UDim.new(0.5, 0))
	if style.Inverted then
		C.Stroke(bar, P.White, 1.5)
	end
	local icon = C.Frame(toast, { BackgroundColor3 = P.White, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 22, 0.5, 0), Size = UDim2.fromOffset(32, 32), ZIndex = 2 })
	C.Corner(icon, UDim.new(0.5, 0))
	C.Stroke(icon, P.Ink, 2.5)
	C.Title(icon, style.Glyph, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 18, TextColor3 = P.Blue500, ZIndex = 3 }, 0.01)
	local label = C.Title(toast, text, {
		Font = Theme.Fonts.Body,
		Position = UDim2.fromOffset(64, 0),
		Size = UDim2.new(1, -74, 1, 0),
		TextWrapped = true,
		TextSize = 17,
		ZIndex = 2,
	}, 1.5)
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
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 70),
		Size = UDim2.fromOffset(360, 180),
		ZIndex = 60,
	})
	C.List(self.Container, Enum.FillDirection.Vertical, 8)
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
