--[[
	Types
	Shared Luau type definitions for persisted data and network payloads.
]]

export type UnitInstance = {
	Uid: string,
	UnitId: string,
	Level: number,
	XP: number,
	Stars: number,
	Trait: string?,
	Locked: boolean,
	ObtainedAt: number,
	Source: string,
}

export type QuestProgress = {
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
}

export type Boost = { Multiplier: number, ExpiresAt: number }

export type TransactionEntry = {
	Time: number,
	Currency: string,
	Delta: number,
	Balance: number,
	Reason: string,
}

export type SummonRecord = { Time: number, Banner: string, UnitId: string, Rarity: string }

export type PlayerData = {
	DataVersion: number,
	Level: number,
	Experience: number,
	Damage: number, -- mirror of Upgrades.Damage (kept for the original spec)
	Currencies: { [string]: number },
	Upgrades: { [string]: number },
	Playtime: number,
	CurrentWorld: string,
	UnlockedWorlds: { [string]: boolean },
	ClearedWorlds: { [string]: boolean },
	Inventory: {
		Units: { [string]: UnitInstance },
		Items: { [string]: number },
		LockedItems: { [string]: boolean },
	},
	EquippedUnits: { string },
	NextUnitSerial: number,
	Quests: {
		MainCurrent: string?,
		MainCompleted: { [string]: boolean },
		Active: { [string]: QuestProgress },
		DailyDay: number,
	},
	Achievements: { [string]: number }, -- highest tier claimed
	Settings: { [string]: any },
	Stats: { [string]: number },
	SummonPity: { [string]: { [string]: number } },
	SummonHistory: { SummonRecord },
	TransactionLog: { TransactionEntry },
	ClaimedRewards: { [string]: boolean },
	ActiveBoosts: { [string]: Boost },
	RaidCooldowns: { [string]: number },
	ProcessedReceipts: { string },
	FirstJoin: number,
	LastJoin: number,
}

-- Response envelope of every RemoteFunction request.
export type Response<T> = { ok: boolean, data: T?, error: string? }

return {}
