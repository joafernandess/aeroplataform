--[[
	IconAssets
	Uploaded icon images, by icon name. THIS IS THE ONLY FILE TO EDIT AFTER UPLOADING THE ICONS.

	The HUD menu icons are full-colour PNGs in assets/UI_Icons (512x512, transparent background):
	  1. Roblox Studio → View → Asset Manager → Bulk Import (or Creator Hub → Creations → Development Items →
	     Images → Upload) and upload every Icon_*.png.
	  2. Copy each image's asset id (right click → Copy Asset ID) and paste it below as "rbxassetid://<id>".
	Leave a name "" while its PNG is not uploaded: the vector drawing in UI/Icons.luau is shown instead, in the
	same colour (Theme.IconColors), so the UI never shows a broken image.

	Uploaded images are full-colour art and are displayed as-is (never tinted).
]]

return {
	-- HUD menus · assets/UI_Icons/<file> · button that shows it ------------------------------------------------
	shop = "", --          Icon_Shop.png           left menu  · Shop (also the Shop window title)
	fighters = "", --      Icon_Fighters.png       left menu  · Fighters (also the Fighters window title)
	settings = "", --      Icon_Settings.png       left menu  · Settings
	codes = "", --         Icon_Codes.png          left menu  · Codes
	quests = "", --        Icon_Quests.png         left menu  · Quests
	teleport = "", --      Icon_Teleport.png       left menu  · TP
	inventory = "", --     Icon_Inventory.png      right menu · Inventory
	mounts = "", --        Icon_Mounts.png         right menu · Mounts
	achievements = "", --  Icon_Achievements.png   right menu · Achievements
	stats = "", --         Icon_Stats.png          right menu · Stats
	index = "", --         Icon_Index.png          right menu · Index
	update = "", --        Icon_UpdateLog.png      top-right Update Log card

	-- Other icons (currencies, small tools, window details) · assets/icons/png -----------------------------------
	yen = "",
	gems = "",
	gold = "",
	tokens = "",
	power = "",
	summon = "",
	auto = "",
	sort = "",
	lock = "",
	check = "",
	close = "",
	plus = "",
	upgrades = "",
	worlds = "",
	raids = "",
	boss = "",
	zone = "",
	target = "",
	team = "",
	timer = "",
	sell = "",
	new = "",
	star = "",
	kills = "",
}
