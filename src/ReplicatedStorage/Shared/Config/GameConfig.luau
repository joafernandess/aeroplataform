--[[
	GameConfig
	Global tuning constants shared by server and client.
	Everything here is safe to read on the client: no secrets live in ReplicatedStorage.
]]

local GameConfig = {}

-- Data ---------------------------------------------------------------------
GameConfig.Data = {
	-- Changing the store name wipes progress for everyone. Bump DataVersion + add a migration instead.
	StoreName = "AnimeFighters_PlayerData_v1",
	KeyPrefix = "Player_",
	AutoSaveInterval = 120, -- seconds
	MaxLoadAttempts = 5,
	MaxSaveAttempts = 5,
	RetryBaseDelay = 1, -- seconds, doubles every attempt
	SessionLockTimeout = 1800, -- seconds; a lock older than this is considered stale and can be stolen
	SessionLockWaitAttempts = 4, -- how many times to retry while another server holds a fresh lock
	SummonHistoryLimit = 100,
	TransactionLogLimit = 50,
	ProcessedReceiptLimit = 100,
}

-- Starting values for new players ---------------------------------------------
GameConfig.Start = {
	World = "W1",
	Currencies = { Yen = 250, Gems = 100, Gold = 0, Tokens = 0 },
	StarterUnits = { "SS_GeninRecruit" },
	StarterItems = { XPPotionSmall = 3 },
}

-- Units / inventory -------------------------------------------------------------
GameConfig.Units = {
	BaseEquipSlots = 3,
	MaxEquipSlots = 8,
	BaseUnitStorage = 100,
	MaxUnitStorage = 500,
	MaxStars = 5,
	StarDamageBonus = 0.2, -- +20% damage per star
	LevelDamageBonus = 0.08, -- +8% base damage per level above 1
	MaxTraitsPerUnit = 1,
	MaxFodderPerFuse = 20,
	MaxDeletePerRequest = 50,
}

-- Combat -------------------------------------------------------------------------
GameConfig.Combat = {
	TickRate = 0.1, -- seconds between combat simulation steps
	BaseCritChance = 0.05,
	BaseCritMultiplier = 2,
	MaxCritChance = 0.75,
	MaxTargetSelectDistance = 150, -- studs: how far from the character a manual target may be
	UnitRangeOrigin = "Character", -- ranges are measured from the player's HumanoidRootPart
	MinAttackSpeed = 0.1,
	MaxAttackSpeed = 10,
	DamageNumberBatchLimit = 40, -- max indicators sent per player per tick
	RewardContributionThreshold = 0.1, -- min share of a boss's HP a player must deal to receive rewards
}

-- Economy ------------------------------------------------------------------------
GameConfig.Economy = {
	Currencies = { "Yen", "Gems", "Gold", "Tokens" },
	MaxBalance = 1e15,
	MaxSingleTransaction = 1e13,
	-- Reasons that are too frequent to keep in the per-player transaction log.
	UnloggedReasons = {
		EnemyKill = true,
		RaidWaveKill = true,
	},
}

-- Quests -------------------------------------------------------------------------
GameConfig.Quests = {
	DailyQuestCount = 3,
	DailyResetOffsetSeconds = 0, -- 0 = reset at 00:00 UTC
}

-- Network ------------------------------------------------------------------------
GameConfig.Network = {
	DefaultRateLimit = 10, -- requests per second per remote per player
	DefaultBurst = 20,
	FolderName = "Remotes",
}

-- Admin --------------------------------------------------------------------------
GameConfig.Admin = {
	-- UserIds allowed to run admin commands in live servers. In Studio every player is admin.
	UserIds = {},
}

return GameConfig
