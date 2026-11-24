--[[
	Rewards
	Helpers for the shared reward format used by quests, achievements, enemies, raids and shop:
	  { Yen?, Gems?, Gold?, Tokens?, XP?, Items? = { [itemId] = count }, Units? = { unitId, ... } }
	Granting is done by EconomyService:GrantRewards (server). This module only validates/merges/formats.
]]

local Config = script.Parent.Parent.Config
local GameConfig = require(Config.GameConfig)
local Items = require(Config.Items)
local Units = require(Config.Units)

local Rewards = {}

local CURRENCIES = GameConfig.Economy.Currencies

function Rewards.IsValid(rewards: any): (boolean, string?)
	if type(rewards) ~= "table" then
		return false, "Rewards must be a table"
	end
	for key, value in rewards do
		if key == "Items" then
			if type(value) ~= "table" then
				return false, "Items must be a table"
			end
			for itemId, count in value do
				if not Items.IsValid(itemId) then
					return false, "Unknown item " .. tostring(itemId)
				end
				if type(count) ~= "number" or count <= 0 or count % 1 ~= 0 then
					return false, "Invalid item count for " .. tostring(itemId)
				end
			end
		elseif key == "Units" then
			if type(value) ~= "table" then
				return false, "Units must be a list"
			end
			for _, unitId in value do
				if not Units.IsValid(unitId) then
					return false, "Unknown unit " .. tostring(unitId)
				end
			end
		elseif key == "XP" or table.find(CURRENCIES, key) then
			if type(value) ~= "number" or value < 0 or value ~= value then
				return false, "Invalid amount for " .. tostring(key)
			end
		else
			return false, "Unknown reward key " .. tostring(key)
		end
	end
	return true, nil
end

-- Returns a new table with every numeric currency/XP amount multiplied by the matching multiplier.
function Rewards.Scale(rewards: { [string]: any }, multipliers: { [string]: number }): { [string]: any }
	local out = {}
	for key, value in rewards do
		if type(value) == "number" then
			out[key] = math.floor(value * (multipliers[key] or 1))
		else
			out[key] = value
		end
	end
	return out
end

function Rewards.Merge(into: { [string]: any }, from: { [string]: any }): { [string]: any }
	for key, value in from do
		if type(value) == "number" then
			into[key] = (into[key] or 0) + value
		elseif key == "Items" then
			into.Items = into.Items or {}
			for itemId, count in value do
				into.Items[itemId] = (into.Items[itemId] or 0) + count
			end
		elseif key == "Units" then
			into.Units = into.Units or {}
			for _, unitId in value do
				table.insert(into.Units, unitId)
			end
		end
	end
	return into
end

function Rewards.IsEmpty(rewards: { [string]: any }): boolean
	return next(rewards) == nil
end

-- Human readable one-line description, e.g. "150 Yen, 50 Gems, 3x Small XP Potion".
function Rewards.Describe(rewards: { [string]: any }): string
	local parts = {}
	for _, currency in CURRENCIES do
		if rewards[currency] and rewards[currency] > 0 then
			table.insert(parts, ("%d %s"):format(rewards[currency], currency))
		end
	end
	if rewards.XP and rewards.XP > 0 then
		table.insert(parts, ("%d XP"):format(rewards.XP))
	end
	if rewards.Items then
		local ids = {}
		for itemId in rewards.Items do
			table.insert(ids, itemId)
		end
		table.sort(ids)
		for _, itemId in ids do
			local def = Items.Get(itemId)
			table.insert(parts, ("%dx %s"):format(rewards.Items[itemId], if def then def.Name else itemId))
		end
	end
	if rewards.Units then
		for _, unitId in rewards.Units do
			local def = Units.Get(unitId)
			table.insert(parts, if def then def.Name else unitId)
		end
	end
	return table.concat(parts, ", ")
end

return Rewards
