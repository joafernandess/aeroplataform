--[[
	RemoteNames
	The complete network surface of the game. The server creates exactly these remotes; anything not listed
	here cannot be called. Keep handlers thin: validate, then call a service.
]]

return {
	-- Client -> Server requests (RemoteFunction). Every response is { ok, data?, error? }.
	Functions = {
		"GetProfile",
		"GetServerInfo",
		-- Units
		"EquipUnit",
		"UnequipUnit",
		"EquipBest",
		"UnequipAll",
		"LockUnit",
		"DeleteUnits",
		"FuseUnits",
		"EvolveUnit",
		-- Inventory
		"UseItem",
		"SellItem",
		"LockItem",
		-- Summon
		"Summon",
		-- Worlds
		"UnlockWorld",
		"TeleportWorld",
		"TeleportToPoint",
		-- Codes
		"RedeemCode",
		-- Quests / achievements
		"ClaimQuest",
		"ClaimAchievement",
		-- Shop / upgrades
		"BuyShopItem",
		"BuyUpgrade",
		-- Settings
		"UpdateSetting",
		-- Raids
		"StartRaid",
		"LeaveRaid",
		-- Admin (gated server-side)
		"AdminCommand",
	},

	-- Server -> Client notifications (RemoteEvent).
	ServerEvents = {
		"DataChanged", -- (key, value) top-level profile key replicated
		"Notify", -- (payload { Text, Kind, Duration? })
		"DamageNumbers", -- ({ { Enemy, Amount, Crit, Special? } })
		"AbilityCast", -- (payload { UnitUid, Ability, Enemy })
		"RaidUpdate", -- (payload { State, Raid, Wave, Waves, EndsAt })
		"LevelUp", -- (payload { Level })
		"EventsChanged", -- (activeEvents)
		"EnemyDefeated", -- ({ Enemy, Position = {x,y,z}, Yen, Boss }) cosmetic coin burst for the killer(s)
	},

	-- Client -> Server fire-and-forget (RemoteEvent).
	ClientEvents = {
		"SetTarget", -- (enemyRuntimeId | nil)
	},
}
