--[[
	SettingsController
	Toggles and volume steps. Values are validated and stored by the server (UpdateSetting); client-only
	effects (volume, low graphics) are applied here.
]]

local SoundService = game:GetService("SoundService")

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local State = require(Client.State)

local SettingsController = {
	Name = "SettingsController",
	Priority = 27,
}

local TOGGLES = {
	{ Key = "AutoAttack", Label = "Auto attack nearest enemy" },
	{ Key = "DamageNumbers", Label = "Show damage numbers" },
	{ Key = "ShowOtherUnits", Label = "Show other players' units" },
	{ Key = "LowGraphics", Label = "Low graphics mode" },
	{ Key = "AutoDeleteCommon", Label = "Auto-sell Common summons" },
	{ Key = "AutoDeleteRare", Label = "Auto-sell Rare summons" },
}
local VOLUMES = {
	{ Key = "MusicVolume", Label = "Music volume" },
	{ Key = "SFXVolume", Label = "Effects volume" },
}
local STEPS = { 0, 0.25, 0.5, 0.75, 1 }

-- Client-side effects of settings. Sound groups named "Music"/"SFX" in SoundService are respected if present.
function SettingsController:Apply(settings)
	local music = SoundService:FindFirstChild("Music")
	if music and music:IsA("SoundGroup") then
		music.Volume = settings.MusicVolume or 0.5
	end
	local sfx = SoundService:FindFirstChild("SFX")
	if sfx and sfx:IsA("SoundGroup") then
		sfx.Volume = settings.SFXVolume or 0.5
	end
end

function SettingsController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	local settings = data.Settings
	for i, toggle in TOGGLES do
		local row = C.Row(self.List, { Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i })
		C.Title(row, toggle.Label, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -110, 1, 0), TextSize = 18 }, 2)
		local on = settings[toggle.Key] == true
		C.Toggle(row, on, function()
			State.Request("UpdateSetting", toggle.Key, not on)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0) })
	end
	for i, volume in VOLUMES do
		local row = C.Row(self.List, { Size = UDim2.new(1, -8, 0, 60), LayoutOrder = 100 + i })
		C.Title(row, volume.Label, { Position = UDim2.fromOffset(16, 0), Size = UDim2.new(0.4, 0, 1, 0), TextSize = 18 }, 2)
		local steps = C.Frame(row, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(360, 44) })
		C.List(steps, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
		for j, step in STEPS do
			local active = math.abs((settings[volume.Key] or 0) - step) < 0.01
			local button = C.Button(steps, tostring(math.floor(step * 100)) .. "%", function()
				State.Request("UpdateSetting", volume.Key, step)
			end, { Kind = if active then "Primary" else "Dark", Size = UDim2.fromOffset(64, 44), TextSize = 15, LayoutOrder = j })
			C.SetSelected(button, active)
		end
	end
end

function SettingsController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Settings", "Settings", nil, function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 6)
end

function SettingsController:Start()
	State.Observe({ "Settings" }, function(data)
		self:Apply(data.Settings)
		self:Render()
	end)
end

return SettingsController
