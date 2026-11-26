--[[
	Navigation
	The two side menus of the HUD: icon-only square buttons in a grid of `PerRow` per row, read left-to-right,
	top-to-bottom. Edit these tables to add, remove or reorder buttons — UIController builds the grids from them
	(no other code changes needed as long as the window exists).

	  Window   id of the window opened by the button (created by the window's controller)
	  Label    the menu's name (accessibility / tests; buttons show only the icon)
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

-- Grid geometry at the 1280x720 design size (scaled with the HUD on small screens, see UIController:LayoutNav).
Navigation.PerRow = 2
Navigation.ButtonSize = 66
Navigation.Gap = 10
Navigation.Margin = 14
Navigation.CenterY = 0.5 -- preferred vertical centre of both grids (scale of the screen height)

return Navigation
