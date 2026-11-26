--[[
	Theme
	Design tokens for code-built UI (see docs/ui/UI_RESEARCH.md). Palette: black, white and blue only.
	Rarity colours are allowed solely as small accents on unit cards, the summon pool and the reveal.

	Identity signatures: near-black panels with an inner rim, straight blue headers with speed-lines and a cyan
	energy line, white enemy health vs. blue for everything that belongs to the player, inverted (black + white
	stroke) destructive buttons, thin rarity strips instead of fully coloured cards.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rarities = require(ReplicatedStorage.Shared.Config.Rarities)

local hex = Color3.fromHex

local Theme = {}

local palette = {
	Ink = hex("05070D"),
	Bg = hex("080C16"),
	Panel = hex("0E1424"),
	PanelAlt = hex("16203A"),
	PanelLight = hex("1F2C4F"),
	Line = hex("2A3A66"),
	White = hex("FFFFFF"),
	TextDim = hex("A9B8D9"),
	TextMuted = hex("6B7BA3"),
	Blue900 = hex("0A2A6B"),
	Blue700 = hex("1546B8"),
	Blue500 = hex("1E6BFF"),
	Blue400 = hex("4A95FF"),
	Cyan = hex("4FD2FF"),
	Ice = hex("CFEFFF"),
	SecondaryText = hex("0B1A3A"),
}

-- Legacy names kept as aliases into the palette so every call site stays on-palette.
Theme.Colors = table.clone(palette)
Theme.Colors.Background = palette.Bg
Theme.Colors.Stroke = palette.Ink
Theme.Colors.Outline = palette.Ink
Theme.Colors.Text = palette.White
Theme.Colors.Accent = palette.Cyan
Theme.Colors.Header = palette.Blue500
Theme.Colors.Cta = palette.Blue500
Theme.Colors.Button = palette.Blue700
Theme.Colors.Good = palette.Cyan
Theme.Colors.Bad = palette.Ice -- attention text on dark panels (destructive buttons use the inverted "Danger" kind)
Theme.Colors.Info = palette.Blue500
Theme.Colors.Alert = hex("FF3B4E") -- notification badges (count, NEW)
Theme.Colors.XP = palette.Cyan
Theme.Colors.Crit = palette.Cyan
-- Currency badges: one shade of the palette each (§6 of the brief)
Theme.Colors.Yen = hex("FFC21A") -- gold coin (HUD counter, flying coins, wallet)
Theme.Colors.Gems = palette.Cyan
Theme.Colors.Gold = palette.White
Theme.Colors.Tokens = palette.Blue900

-- Gradients (top -> bottom) and the darker 4px "lip" under 3D buttons.
Theme.Gradients = {
	Primary = { Top = hex("4A95FF"), Bottom = hex("1652E0"), Lip = hex("0A2A6B") },
	Accent = { Top = hex("8BE6FF"), Bottom = hex("22A9E8"), Lip = hex("0B5E8A") },
	Secondary = { Top = hex("FFFFFF"), Bottom = hex("C9DAFF"), Lip = hex("6F86B8") },
	Dark = { Top = hex("233257"), Bottom = hex("151F38"), Lip = hex("070B16") },
	Danger = { Top = hex("1A1F2B"), Bottom = hex("05070D"), Lip = hex("000000") },
	Disabled = { Top = hex("3A4560"), Bottom = hex("2A3247") },
	WindowBody = { Top = hex("121A2E"), Bottom = hex("0A0F1C") },
	WindowHeader = { Top = hex("2A7BFF"), Bottom = hex("0E3A9E") },
	Progress = { Top = hex("4FD2FF"), Bottom = hex("1E6BFF") },
	Portrait = { Top = hex("1F2C4F"), Bottom = hex("0A0F1C") },
	EnemyHealth = { Top = hex("FFFFFF"), Bottom = hex("BFD6FF") },
}

-- Fonts (§4): display / UI / numbers / body.
Theme.Fonts = {
	Display = Enum.Font.LuckiestGuy,
	Title = Enum.Font.FredokaOne,
	Bold = Enum.Font.FredokaOne,
	Number = Enum.Font.BuilderSansExtraBold,
	Body = Enum.Font.BuilderSansBold,
}

Theme.Stroke = { Window = 4, Button = 3, Card = 3, Tool = 3, Badge = 2, Rim = 1.5 }
Theme.Radius = { Window = 18, Header = 14, Button = 12, Card = 12, Tool = 10, Toast = 12 }
Theme.TextSize = { Display = 34, H2 = 24, ButtonLarge = 24, Button = 20, Body = 18, Small = 15, Micro = 13 }

-- Text outline thickness by text size (§3.3).
function Theme.OutlineFor(textSize: number): number
	if textSize >= 30 then
		return 3
	elseif textSize >= 20 then
		return 2.5
	elseif textSize >= 15 then
		return 2
	end
	return 1.5
end

--[[
	Single-colour glyphs. UI/Icons.luau draws a real vector icon for each of these (Icons.Resolve maps a glyph or
	key to its icon name), so the glyphs are only a last-resort fallback and plain-text currency marks (e.g. "¥").
	Every glyph must be unique: components pass glyphs around and the icon is looked up by glyph.
]]
Theme.Icons = {
	Yen = "¥",
	Gems = "◆",
	Gold = "●",
	Tokens = "✦",
	Power = "✸",
	Inventory = "▦",
	Summon = "✪",
	Worlds = "◎",
	Quests = "☰",
	Shop = "$",
	Upgrades = "▲",
	Raids = "⚔",
	Settings = "⚙",
	Auto = "↻",
	Lock = "■",
	Equipped = "✓",
	Star = "★",
	Close = "✕",
	Sort = "⇅",
	Filter = "≡",
	Fuse = "✚",
	Plus = "+",
	Boss = "☠",
	Zone = "⌖",
	Target = "⊕",
	Team = "⁂",
	Timer = "◴",
	Sell = "⊖",
	New = "!",
	Kills = "†",
	Codes = "✉",
	Mounts = "∩",
	Index = "▤",
	Achievements = "♛",
	Stats = "▥",
	Teleport = "⇄",
	Update = "✎",
	Bag = "▣",
}

-- Uploaded icon images (asset ids), by icon name: see UI/IconAssets.luau (the file to edit after uploading).
Theme.IconAssets = require(script.Parent.IconAssets)

--[[
	Each HUD menu icon has its own colour (the buttons themselves stay black and white). Used by the vector
	fallback drawings and matches the full-colour PNGs in assets/UI_Icons.
]]
Theme.IconColors = {
	shop = hex("FFD23F"), -- gold / yellow
	fighters = hex("FF8A1F"), -- orange
	settings = hex("E9EDF3"), -- silver / white
	codes = hex("B04DFF"), -- purple
	quests = hex("3ED45E"), -- green
	teleport = hex("2ED3FF"), -- cyan
	inventory = hex("3D8BFF"), -- blue
	mounts = hex("FF4FB8"), -- pink / magenta
	achievements = hex("FFB81C"), -- gold
	stats = hex("FF4545"), -- red
	index = hex("7C5CFF"), -- violet
	update = hex("34E3A5"), -- mint
	yen = hex("FFC21A"), -- gold coin
}

-- Monochrome HUD buttons (side menus, Update Log card, window title tiles): charcoal face, light border,
-- soft black shadow; hover lifts to a lighter gray, press sinks to near-black.
Theme.MenuButton = {
	Top = hex("2A2B31"),
	Bottom = hex("0E0E11"),
	HoverTop = hex("3A3C43"),
	HoverBottom = hex("1C1D22"),
	PressTop = hex("0A0A0C"),
	PressBottom = hex("040405"),
	Border = hex("E6E7EB"),
	BorderHover = hex("FFFFFF"),
	Shadow = hex("000000"),
	ShadowTransparency = 0.45,
}

-- Currency -> icon name (HUD currency pills).
Theme.CurrencyIcons = { Yen = "yen", Gems = "gems", Gold = "gold", Tokens = "tokens", Power = "power" }

-- Menu buttons: all Primary except Summon (Accent).
Theme.MenuKinds = {
	Summon = "Accent",
}
Theme.MenuColors = setmetatable({}, {
	__index = function()
		return palette.Blue500
	end,
})

-- Currency badge fills; Gold uses an ink glyph on a white badge.
Theme.CurrencyGlyphColor = { Gold = palette.Ink }

Theme.CornerRadius = UDim.new(0, 12)
Theme.WindowSize = UDim2.fromOffset(760, 520)

function Theme.Rarity(rarityId: string): Color3
	local def = Rarities.Get(rarityId)
	if not def then
		return palette.TextDim
	end
	return Color3.fromRGB(def.Color[1], def.Color[2], def.Color[3])
end

function Theme.Currency(currency: string): Color3
	return (Theme.Colors :: any)[currency] or palette.White
end

function Theme.Darken(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(0, 0, 0), amount)
end

return Theme
