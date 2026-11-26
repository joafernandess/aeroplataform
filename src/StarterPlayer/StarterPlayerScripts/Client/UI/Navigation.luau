--[[
	Navigation
	The two side menus of the HUD. Edit this table to add, remove or reorder menu buttons — UIController builds
	the columns from it (no other code changes needed as long as the window exists).

	  Window   id of the window opened by the button (created by the window's controller)
	  Icon     UI/Icons name
	  Accent   small identity detail on the button (palette only)
	A system that is switched off in Config/Features keeps its button: its window shows its own "not available
	yet" state instead (no fake functionality, no dead buttons).
	Left  = main menus;  Right = the player's own management screens (Index is always the last one).
]]

local Theme = require(script.Parent.Theme)

local P = Theme.Colors

export type Entry = { Window: string, Label: string, Icon: string, Accent: Color3 }

local Navigation = {}

Navigation.Left = {
	{ Window = "Shop", Label = "Shop", Icon = "shop", Accent = P.Cyan },
	{ Window = "Fighters", Label = "Fighters", Icon = "fighters", Accent = P.Blue400 },
	{ Window = "Settings", Label = "Settings", Icon = "settings", Accent = P.TextDim },
	{ Window = "Codes", Label = "Codes", Icon = "codes", Accent = P.Cyan },
	{ Window = "Quests", Label = "Quests", Icon = "quests", Accent = P.Blue400 },
	{ Window = "Teleport", Label = "TP", Icon = "teleport", Accent = P.Cyan },
} :: { Entry }

Navigation.Right = {
	{ Window = "Items", Label = "Inventory", Icon = "inventory", Accent = P.Blue400 },
	{ Window = "Mounts", Label = "Mounts", Icon = "mounts", Accent = P.TextDim },
	{ Window = "Achievements", Label = "Achievements", Icon = "achievements", Accent = P.Cyan },
	{ Window = "Stats", Label = "Stats", Icon = "stats", Accent = P.Blue400 },
	{ Window = "Index", Label = "Index", Icon = "index", Accent = P.Cyan },
} :: { Entry }

-- Keyboard shortcuts (PC). Windows that aren't created are ignored.
Navigation.Hotkeys = {
	[Enum.KeyCode.F] = "Fighters",
	[Enum.KeyCode.I] = "Items",
	[Enum.KeyCode.Q] = "Quests",
	[Enum.KeyCode.T] = "Teleport",
	[Enum.KeyCode.B] = "Shop",
}

-- Button geometry at the 1280x720 design size (the whole column is scaled with the HUD on small screens).
Navigation.ButtonSize = 58
Navigation.CellHeight = 76
Navigation.Gap = 4
Navigation.Margin = 12
Navigation.CenterY = 0.56 -- vertical centre of both columns (scale of the screen height)

return Navigation
