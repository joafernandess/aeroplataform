--[[
	Navigation
	The two side menus of the HUD. Square buttons go `PerRow` per row; a `Wide` button takes a whole row (icon on
	the left, name beside it). Read left-to-right, top-to-bottom. Edit these tables to add, remove or reorder
	buttons — UIController builds the menus from them (no other code changes needed as long as the window exists).

	  Window   id of the window opened by the button (created by the window's controller)
	  Label    name shown inside the button (Navigation.ShowLabels) and used by tests / accessibility
	  Icon     UI/Icons name; its colour (button border + icon) comes from Theme.IconColors, its PNG from UI/IconAssets
	  Key      keyboard shortcut (PC); shown as a small key badge on the button's corner
	  Wide     the button spans the whole row
	A system that is switched off in Config/Features keeps its button: its window shows its own "not available
	yet" state instead (no fake functionality, no dead buttons).
	Left  = main menus;  Right = the player's own management screens (Index is always the last one).
	Hotkeys avoid Roblox's defaults (WASD, Space, Shift, I/O camera zoom, Tab, Esc) and X (clear target).
]]

export type Entry = { Window: string, Label: string, Icon: string, Key: Enum.KeyCode?, Wide: boolean? }

local Navigation = {}

Navigation.Left = {
	{ Window = "Shop", Label = "Shop", Icon = "shop", Key = Enum.KeyCode.B, Wide = true },
	{ Window = "Fighters", Label = "Fighters", Icon = "fighters", Key = Enum.KeyCode.F },
	{ Window = "Settings", Label = "Settings", Icon = "settings", Key = Enum.KeyCode.P },
	{ Window = "Codes", Label = "Codes", Icon = "codes", Key = Enum.KeyCode.C },
	{ Window = "Quests", Label = "Quests", Icon = "quests", Key = Enum.KeyCode.Q },
	{ Window = "Teleport", Label = "Teleport", Icon = "teleport", Key = Enum.KeyCode.T, Wide = true },
} :: { Entry }

Navigation.Right = {
	{ Window = "Items", Label = "Inventory", Icon = "inventory", Key = Enum.KeyCode.K },
	{ Window = "Mounts", Label = "Mounts", Icon = "mounts", Key = Enum.KeyCode.N },
	{ Window = "Upgrades", Label = "Upgrades", Icon = "upgrades", Key = Enum.KeyCode.U },
	{ Window = "Stats", Label = "Stats", Icon = "stats", Key = Enum.KeyCode.V },
	{ Window = "Index", Label = "Index", Icon = "index", Key = Enum.KeyCode.G, Wide = true },
} :: { Entry }

-- Keyboard shortcuts (PC), built from the entries above. Windows that aren't created are ignored.
Navigation.Hotkeys = {}
for _, side in { Navigation.Left, Navigation.Right } do
	for _, entry in side do
		if entry.Key then
			Navigation.Hotkeys[entry.Key] = entry.Window
		end
	end
end

-- Geometry at the 1280x720 design size (scaled with the HUD on small screens, see UIController:LayoutNav).
Navigation.PerRow = 2
Navigation.ButtonSize = 70 -- square buttons
Navigation.WideHeight = 58 -- wide buttons (full row)
Navigation.Gap = 10
Navigation.Margin = 14
Navigation.CenterY = 0.5 -- preferred vertical centre of both menus (scale of the screen height)
Navigation.ShowLabels = true -- names inside the buttons; false = icon-only buttons
Navigation.ShowKeys = true -- key badges on PC (keyboard present)

return Navigation
