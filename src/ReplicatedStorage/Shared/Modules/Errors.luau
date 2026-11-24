--[[
	Errors
	Stable error codes returned by server requests. The client maps them to messages.
	Codes are strings so logs stay readable.
]]

local Errors = {
	InvalidArguments = "Invalid request.",
	RateLimited = "You're doing that too fast.",
	DataNotLoaded = "Your data is still loading.",
	InternalError = "Something went wrong. Please try again.",
	NotEnoughCurrency = "You can't afford that.",
	InvalidCurrency = "Invalid currency.",
	UnitNotFound = "Unit not found.",
	UnitLocked = "That unit is locked.",
	UnitEquipped = "Unequip that unit first.",
	EquipLimit = "All equip slots are full.",
	AlreadyEquipped = "Unit already equipped.",
	NotEquipped = "Unit is not equipped.",
	InventoryFull = "Your unit storage is full.",
	ItemNotFound = "You don't have that item.",
	ItemNotUsable = "That item can't be used.",
	ItemLocked = "That item is locked.",
	StackLimit = "You can't hold more of that item.",
	MaxLevel = "Already at max level.",
	NotMaxLevel = "Unit must be max level.",
	CannotEvolve = "This unit can't evolve.",
	MissingMaterials = "Missing materials.",
	CannotFuse = "Those units can't be fused.",
	BannerNotFound = "Banner not found.",
	BannerUnavailable = "That banner isn't available.",
	InvalidAmount = "Invalid amount.",
	WorldNotFound = "World not found.",
	WorldLocked = "World is locked.",
	AlreadyUnlocked = "Already unlocked.",
	RequirementsNotMet = "Requirements not met.",
	QuestNotFound = "Quest not found.",
	QuestNotComplete = "Quest not complete yet.",
	AlreadyClaimed = "Already claimed.",
	EnemyNotFound = "Target not found.",
	OutOfRange = "Target is too far away.",
	RaidNotFound = "Raid not found.",
	RaidOnCooldown = "That raid is on cooldown.",
	AlreadyInRaid = "You are already in a raid.",
	NotInRaid = "You are not in a raid.",
	ShopItemNotFound = "Item not for sale.",
	MaxUpgrade = "Upgrade already maxed.",
	NotAdmin = "Not allowed.",
	FeatureDisabled = "Coming soon!",
}

local Codes = {}
for code in Errors do
	Codes[code] = code
end

return {
	Messages = Errors,
	Codes = Codes,
	Message = function(code: string?): string
		return (code and Errors[code]) or Errors.InternalError
	end,
}
