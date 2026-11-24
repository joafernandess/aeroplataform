--[[
	Theme
	Colours, fonts and sizes for code-built UI. Change the look of the whole game here.

	Style: "arcade simulator" — chunky outlined text, glossy gradient buttons, round icon buttons and
	bold currency pills. Original palette (deep indigo panels, electric cyan accent, hot orange CTAs).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(20, 18, 40),
	Panel = Color3.fromRGB(34, 30, 66),
	PanelLight = Color3.fromRGB(50, 45, 92),
	Button = Color3.fromRGB(88, 80, 150),
	Stroke = Color3.fromRGB(12, 10, 26),
	Outline = Color3.fromRGB(12, 10, 26), -- text outlines
	Text = Color3.fromRGB(255, 255, 255),
	TextDim = Color3.fromRGB(176, 170, 220),
	Accent = Color3.fromRGB(46, 230, 255),
	Header = Color3.fromRGB(110, 70, 255),
	Cta = Color3.fromRGB(255, 140, 30),
	Good = Color3.fromRGB(70, 220, 110),
	Bad = Color3.fromRGB(255, 70, 110),
	Info = Color3.fromRGB(60, 150, 255),
	Yen = Color3.fromRGB(255, 205, 50),
	Gems = Color3.fromRGB(70, 210, 255),
	Gold = Color3.fromRGB(255, 160, 40),
	Tokens = Color3.fromRGB(190, 100, 255),
	XP = Color3.fromRGB(110, 255, 150),
	Crit = Color3.fromRGB(255, 70, 50),
}

Theme.Fonts = {
	Display = Enum.Font.LuckiestGuy, -- big titles
	Title = Enum.Font.FredokaOne,
	Bold = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
}

-- Icons are emoji so the UI works with zero uploaded assets. Replace with rbxassetid images later
-- (see docs/STUDIO_SETUP.md) — every icon is referenced from this table only.
Theme.Icons = {
	Yen = "¥",
	Gems = "💎",
	Gold = "🪙",
	Tokens = "🎟️",
	Inventory = "🎒",
	Summon = "✨",
	Worlds = "🌍",
	Quests = "📜",
	Shop = "🛒",
	Upgrades = "⬆️",
	Raids = "⚔️",
	Settings = "⚙️",
	Power = "💥",
	Auto = "⚔️",
	Lock = "🔒",
	Equipped = "✔",
	Star = "★",
}

Theme.MenuColors = {
	Inventory = Color3.fromRGB(70, 160, 255),
	Summon = Color3.fromRGB(255, 90, 200),
	Worlds = Color3.fromRGB(60, 200, 120),
	Quests = Color3.fromRGB(255, 190, 40),
	Shop = Color3.fromRGB(255, 120, 40),
	Upgrades = Color3.fromRGB(150, 90, 255),
	Raids = Color3.fromRGB(230, 60, 80),
	Settings = Color3.fromRGB(120, 130, 170),
}

Theme.CornerRadius = UDim.new(0, 14)
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

function Theme.Darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

return Theme
