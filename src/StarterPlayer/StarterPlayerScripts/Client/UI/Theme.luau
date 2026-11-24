--[[
	Theme
	Colours, fonts and sizes for code-built UI. Change the look of the whole game here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(22, 24, 34),
	Panel = Color3.fromRGB(32, 35, 50),
	PanelLight = Color3.fromRGB(44, 48, 68),
	Button = Color3.fromRGB(66, 72, 102),
	Stroke = Color3.fromRGB(70, 76, 110),
	Text = Color3.fromRGB(240, 242, 255),
	TextDim = Color3.fromRGB(160, 166, 200),
	Accent = Color3.fromRGB(255, 170, 40),
	Good = Color3.fromRGB(90, 220, 120),
	Bad = Color3.fromRGB(240, 80, 90),
	Info = Color3.fromRGB(80, 170, 255),
	Yen = Color3.fromRGB(255, 220, 90),
	Gems = Color3.fromRGB(110, 220, 255),
	Gold = Color3.fromRGB(255, 190, 60),
	Tokens = Color3.fromRGB(200, 120, 255),
	XP = Color3.fromRGB(120, 255, 160),
	Crit = Color3.fromRGB(255, 80, 60),
}

Theme.Fonts = {
	Title = Enum.Font.GothamBlack,
	Bold = Enum.Font.GothamBold,
	Body = Enum.Font.Gotham,
}

Theme.CornerRadius = UDim.new(0, 10)
Theme.WindowSize = UDim2.fromOffset(640, 440)

function Theme.Rarity(rarityId: string): Color3
	local def = Rarities.Get(rarityId)
	if not def then
		return Theme.Colors.TextDim
	end
	return Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
end

function Theme.Currency(currency: string): Color3
	return (Theme.Colors :: any)[currency] or Theme.Colors.Text
end

return Theme
