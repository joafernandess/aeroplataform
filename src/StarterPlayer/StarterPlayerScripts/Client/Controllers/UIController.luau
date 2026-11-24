--[[
	UIController
	Owns the root ScreenGui, the left menu and the window registry. Only one window is open at a time.

	  UI:CreateWindow(name, title, size?, onOpen?) -> window { Frame, Content, Title }
	  UI:Open(name, ...)  UI:Close(name?)  UI:Toggle(name)  UI:IsOpen(name)
	  UI:AddMenuButton(name, label, order)
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)

local UIController = {
	Name = "UIController",
	Priority = 1,
}

UIController.Windows = {}
UIController.Current = nil :: string?

local HOTKEYS = {
	[Enum.KeyCode.I] = "Inventory",
	[Enum.KeyCode.Q] = "Quests",
	[Enum.KeyCode.M] = "Worlds",
	[Enum.KeyCode.B] = "Shop",
}

function UIController:GetRoot(): ScreenGui
	return self.Root
end

function UIController:CreateWindow(name: string, title: string, size: UDim2?, onOpen: ((...any) -> ())?)
	local window = C.Window(self.Root, title, size)
	window.Name = name
	window.OnOpen = onOpen
	window.CloseButton.Activated:Connect(function()
		self:Close(name)
	end)
	self.Windows[name] = window
	return window
end

function UIController:IsOpen(name: string): boolean
	return self.Current == name
end

function UIController:Open(name: string, ...: any)
	local window = self.Windows[name]
	if not window then
		warn("[UIController] Unknown window " .. tostring(name))
		return
	end
	if self.Current and self.Current ~= name then
		self:Close(self.Current)
	end
	self.Current = name
	window.Frame.Visible = true
	if window.OnOpen then
		task.spawn(window.OnOpen, ...)
	end
end

function UIController:Close(name: string?)
	local target = name or self.Current
	if not target then
		return
	end
	local window = self.Windows[target]
	if window then
		window.Frame.Visible = false
		if window.OnClose then
			task.spawn(window.OnClose)
		end
	end
	if self.Current == target then
		self.Current = nil
	end
end

function UIController:Toggle(name: string, ...: any)
	if self:IsOpen(name) then
		self:Close(name)
	else
		self:Open(name, ...)
	end
end

function UIController:AddMenuButton(name: string, label: string, order: number)
	C.Button(self.Menu, label, function()
		self:Toggle(name)
	end, { LayoutOrder = order, Size = UDim2.fromOffset(110, 38), TextSize = 15 })
end

function UIController:Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	self.Root = C.Create("ScreenGui", {
		Name = "AnimeFightersUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	self.Menu = C.Frame(self.Root, {
		Name = "Menu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(110, 420),
	})
	C.List(self.Menu, Enum.FillDirection.Vertical, 6)
	-- Effects layer (popups that sit above windows, e.g. summon reveal)
	self.Overlay = C.Frame(self.Root, { Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50 })
	local _ = Theme
end

function UIController:Start()
	local order = {
		{ "Inventory", "Units" },
		{ "Summon", "Summon" },
		{ "Worlds", "Worlds" },
		{ "Quests", "Quests" },
		{ "Shop", "Shop" },
		{ "Upgrades", "Upgrades" },
		{ "Raids", "Raids" },
		{ "Settings", "Settings" },
	}
	for i, entry in order do
		if self.Windows[entry[1]] then
			self:AddMenuButton(entry[1], entry[2], i)
		end
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local windowName = HOTKEYS[input.KeyCode]
		if windowName and self.Windows[windowName] then
			self:Toggle(windowName)
		end
	end)
end

return UIController
