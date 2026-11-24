--[[
	Shop
	In-game currency shop + Robux products.

	Robux products require real ids created on the Roblox website (Creator Dashboard > Monetization).
	While an id is 0 the product is hidden from the UI and ignored by the server.
]]

export type ShopItem = {
	Id: string,
	Name: string,
	Currency: string,
	Price: number,
	Grants: { [string]: any }, -- shared reward format
	MaxPerPurchase: number,
	Requirements: { [string]: any }?,
	Category: string,
}

export type DevProduct = { Id: string, ProductId: number, Name: string, Grants: { [string]: any } }
export type GamePass = { Id: string, PassId: number, Name: string, Description: string, Perks: { [string]: any } }

local Shop = {}

Shop.Items = {
	{ Id = "S_XPSmall", Name = "Small XP Potion", Currency = "Yen", Price = 500, Grants = { Items = { XPPotionSmall = 1 } }, MaxPerPurchase = 100, Category = "Potions" },
	{ Id = "S_XPMedium", Name = "XP Potion", Currency = "Yen", Price = 3500, Grants = { Items = { XPPotionMedium = 1 } }, MaxPerPurchase = 100, Category = "Potions" },
	{ Id = "S_XPLarge", Name = "Large XP Potion", Currency = "Gold", Price = 25, Grants = { Items = { XPPotionLarge = 1 } }, MaxPerPurchase = 50, Category = "Potions" },
	{ Id = "S_EvoStone", Name = "Evolution Stone", Currency = "Gold", Price = 120, Grants = { Items = { EvolutionStone = 1 } }, MaxPerPurchase = 10, Category = "Materials" },
	{ Id = "S_TraitCrystal", Name = "Trait Crystal", Currency = "Tokens", Price = 60, Grants = { Items = { TraitCrystal = 1 } }, MaxPerPurchase = 10, Category = "Materials" },
	{ Id = "S_DmgBoost", Name = "2x Damage (15m)", Currency = "Gems", Price = 120, Grants = { Items = { DamageBoost2x = 1 } }, MaxPerPurchase = 10, Category = "Boosts" },
	{ Id = "S_YenBoost", Name = "2x Yen (15m)", Currency = "Gems", Price = 100, Grants = { Items = { YenBoost2x = 1 } }, MaxPerPurchase = 10, Category = "Boosts" },
	{ Id = "S_LuckBoost", Name = "2x Luck (15m)", Currency = "Tokens", Price = 40, Grants = { Items = { LuckBoost2x = 1 } }, MaxPerPurchase = 10, Category = "Boosts" },
	{ Id = "S_GoldPack", Name = "Gold Pack", Currency = "Gems", Price = 200, Grants = { Gold = 50 }, MaxPerPurchase = 10, Category = "Currency" },
} :: { ShopItem }

-- Robux developer products (ProcessReceipt). ProductId 0 = not configured yet.
Shop.DevProducts = {
	{ Id = "P_Gems500", ProductId = 0, Name = "500 Gems", Grants = { Gems = 500 } },
	{ Id = "P_Gems2500", ProductId = 0, Name = "2,500 Gems", Grants = { Gems = 2500 } },
	{ Id = "P_Founder", ProductId = 0, Name = "Founder Unit", Grants = { Units = { "EX_Founder" } } },
} :: { DevProduct }

-- Game passes. PassId 0 = not configured yet. Perks are read by BoostService / UnitService.
Shop.GamePasses = {
	{ Id = "GP_2xYen", PassId = 0, Name = "2x Yen", Description = "Permanently doubles Yen.", Perks = { YenMultiplier = 2 } },
	{ Id = "GP_2xDamage", PassId = 0, Name = "2x Damage", Description = "Permanently doubles damage.", Perks = { DamageMultiplier = 2 } },
	{ Id = "GP_ExtraEquip", PassId = 0, Name = "+2 Equip Slots", Description = "Equip two more units.", Perks = { ExtraEquipSlots = 2 } },
	{ Id = "GP_Lucky", PassId = 0, Name = "Lucky", Description = "+50% summon luck.", Perks = { LuckMultiplier = 1.5 } },
} :: { GamePass }

Shop.ItemsById = {} :: { [string]: ShopItem }
for _, item in Shop.Items do
	assert(Shop.ItemsById[item.Id] == nil, "Duplicate shop item " .. item.Id)
	assert(item.Price > 0, "Shop price must be positive: " .. item.Id)
	Shop.ItemsById[item.Id] = item
end

Shop.ProductsByProductId = {} :: { [number]: DevProduct }
for _, product in Shop.DevProducts do
	if product.ProductId ~= 0 then
		Shop.ProductsByProductId[product.ProductId] = product
	end
end

function Shop.GetItem(id: string): ShopItem?
	return Shop.ItemsById[id]
end

return Shop
