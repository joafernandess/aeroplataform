--[[
	UnitDetailsController
	Renders the details panel for one unit (inside the Units window): stats, abilities, comparison with
	the weakest equipped unit, and actions (equip, lock, sell, fuse, evolve, XP potions, trait reroll).
	All actions are server requests; the panel re-renders when DataChanged arrives.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local Items = require(Shared.Config.Items)
local Traits = require(Shared.Config.Traits)
local Abilities = require(Shared.Config.Abilities)
local UnitStats = require(Shared.Modules.UnitStats)
local Formulas = require(Shared.Modules.Formulas)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local UnitDetailsController = {
	Name = "UnitDetailsController",
	Priority = 21,
}

local POTIONS = { "XPPotionSmall", "XPPotionMedium", "XPPotionLarge" }

local function weakestEquipped(data, exceptUid: string)
	local weakest, weakestPower = nil, math.huge
	for _, uid in data.EquippedUnits do
		local unit = data.Inventory.Units[uid]
		if unit and uid ~= exceptUid then
			local stats = UnitStats.Compute(unit)
			if stats and stats.Power < weakestPower then
				weakest, weakestPower = unit, stats.Power
			end
		end
	end
	return weakest
end

local function statLine(parent, label: string, value: string, order: number, color: Color3?)
	local row = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), LayoutOrder = order })
	C.Label(row, label, { Size = UDim2.new(0.5, 0, 1, 0), TextSize = 13, TextColor3 = Theme.Colors.TextDim })
	C.Label(row, value, { Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.5, 0, 1, 0), TextSize = 13, Font = Theme.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = color or Theme.Colors.Text })
end

function UnitDetailsController:Render(container: Frame, uid: string?)
	C.Clear(container)
	local data = State.Data
	local unit = data and uid and data.Inventory.Units[uid]
	if not unit then
		C.Label(container, "Select a unit to see its details.", { TextColor3 = Theme.Colors.TextDim, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40) })
		return
	end
	local def = Units.Get(unit.UnitId)
	local stats = UnitStats.Compute(unit)
	if not def or not stats then
		return
	end
	local inventory = self.Controllers.InventoryController
	local equipped = table.find(data.EquippedUnits, uid) ~= nil

	local scroll = C.Scroll(container)
	C.List(scroll, Enum.FillDirection.Vertical, 4)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	C.Label(scroll, def.Name, { Font = Theme.Fonts.Title, TextSize = 20, TextColor3 = Theme.Rarity(def.Rarity), LayoutOrder = nextOrder(), TextWrapped = true, Size = UDim2.new(1, 0, 0, 26) })
	C.Label(scroll, ("%s • %s%s"):format(def.Rarity, def.Anime, if def.Evolved then " • Evolved" else ""), { TextSize = 12, TextColor3 = Theme.Colors.TextDim, LayoutOrder = nextOrder() })

	local maxLevel = Formulas.UnitMaxLevel(def.Rarity)
	local bar = C.ProgressBar(scroll, Theme.Colors.XP, { LayoutOrder = nextOrder() })
	if unit.Level >= maxLevel then
		bar.Set(1, ("Lv %d (MAX)"):format(unit.Level))
	else
		local needed = Formulas.UnitXPToNext(unit.Level, def.Rarity)
		bar.Set(unit.XP / needed, ("Lv %d/%d  %s/%s XP"):format(unit.Level, maxLevel, NumberFormat.Abbreviate(unit.XP), NumberFormat.Abbreviate(needed)))
	end

	statLine(scroll, "Stars", string.rep("★", unit.Stars or 0) .. string.rep("☆", 5 - (unit.Stars or 0)), nextOrder(), Theme.Colors.Accent)
	local trait = unit.Trait and Traits.Get(unit.Trait)
	statLine(scroll, "Trait", if trait then trait.Name .. " (" .. trait.Description .. ")" else "None", nextOrder(), Theme.Colors.Accent)
	statLine(scroll, "Power", NumberFormat.Abbreviate(stats.Power), nextOrder(), Theme.Colors.Good)
	statLine(scroll, "Damage", NumberFormat.Abbreviate(stats.Damage), nextOrder())
	statLine(scroll, "Attack speed", ("%.2f/s"):format(stats.AttackSpeed), nextOrder())
	statLine(scroll, "Range", ("%d studs"):format(math.floor(stats.Range)), nextOrder())
	statLine(scroll, "Crit chance", NumberFormat.Percent(stats.CritChance), nextOrder())

	local passive = Abilities.GetPassive(def.Passive)
	local special = Abilities.GetSpecial(def.Special)
	if passive then
		C.Label(scroll, "Passive: " .. passive.Name .. " — " .. passive.Description, { TextSize = 12, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder() })
	end
	if special then
		C.Label(scroll, ("Special: %s — %s (%ds cd)"):format(special.Name, special.Description, special.Cooldown), { TextSize = 12, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder() })
	end

	-- Comparison against the weakest equipped unit
	local other = weakestEquipped(data, uid)
	if other and not equipped then
		local diffs = UnitStats.Compare(other, unit)
		if diffs then
			local power = diffs[1]
			local better = power.Difference > 0
			C.Label(scroll, ("vs weakest equipped: %s%s Power"):format(if better then "+" else "", NumberFormat.Abbreviate(power.Difference)), {
				TextSize = 13,
				Font = Theme.Fonts.Bold,
				TextColor3 = if better then Theme.Colors.Good else Theme.Colors.Bad,
				LayoutOrder = nextOrder(),
			})
		end
	end

	-- Actions
	local actions = C.Frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	C.Grid(actions, UDim2.new(0.5, -4, 0, 32), 6)
	C.Button(actions, if equipped then "Unequip" else "Equip", function()
		State.Request(if equipped then "UnequipUnit" else "EquipUnit", uid)
	end, { TextSize = 13, BackgroundColor3 = if equipped then Theme.Colors.PanelLight else Theme.Colors.Good })
	C.Button(actions, if unit.Locked then "Unlock" else "Lock", function()
		State.Request("LockUnit", uid, not unit.Locked)
	end, { TextSize = 13 })
	C.Button(actions, "Fuse", function()
		inventory:SetMode("Fuse")
	end, { TextSize = 13, BackgroundColor3 = Theme.Colors.Info })
	C.Button(actions, ("Sell (%s)"):format(NumberFormat.Abbreviate(Formulas.UnitSellValue(def.Rarity, unit.Level, unit.Stars or 0))), function()
		local response = State.Request("DeleteUnits", { uid })
		if response.ok and response.data.Deleted == 0 and State.Notify then
			State.Notify("Can't sell: unit is locked or equipped.", "Error")
		end
	end, { TextSize = 12, BackgroundColor3 = Theme.Colors.Bad })

	if def.EvolvesTo and def.EvolutionCost then
		local cost = def.EvolutionCost
		local parts = {}
		if cost.Yen then
			table.insert(parts, NumberFormat.Abbreviate(cost.Yen) .. " Yen")
		end
		if cost.Gold then
			table.insert(parts, NumberFormat.Abbreviate(cost.Gold) .. " Gold")
		end
		for itemId, count in cost.Items or {} do
			local itemDef = Items.Get(itemId)
			local have = data.Inventory.Items[itemId] or 0
			table.insert(parts, ("%s %d/%d"):format(if itemDef then itemDef.Name else itemId, have, count))
		end
		C.Label(scroll, "Evolve: " .. table.concat(parts, ", "), { TextSize = 12, TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(), TextColor3 = Theme.Colors.TextDim })
		C.Button(scroll, if unit.Level >= maxLevel then "EVOLVE" else ("Evolve at Lv %d"):format(maxLevel), function()
			local response = State.Request("EvolveUnit", uid)
			if response.ok and State.Notify then
				State.Notify(def.Name .. " evolved!", "Success")
			end
		end, { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder(), BackgroundColor3 = Theme.Colors.Accent, TextColor3 = Theme.Colors.Background })
	end

	-- Consumables on this unit
	local consumables = C.Frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	C.Grid(consumables, UDim2.new(0.5, -4, 0, 30), 6)
	for _, itemId in POTIONS do
		local have = data.Inventory.Items[itemId] or 0
		if have > 0 then
			local itemDef = Items.Get(itemId)
			C.Button(consumables, ("%s (%d)"):format(itemDef.Name, have), function()
				State.Request("UseItem", itemId, uid, 1)
			end, { TextSize = 11, BackgroundColor3 = Theme.Colors.PanelLight })
		end
	end
	if (data.Inventory.Items.TraitCrystal or 0) > 0 then
		C.Button(consumables, ("Reroll Trait (%d)"):format(data.Inventory.Items.TraitCrystal), function()
			local response = State.Request("UseItem", "TraitCrystal", uid, 1)
			if response.ok and State.Notify then
				local newTrait = Traits.Get(response.data)
				State.Notify("New trait: " .. (if newTrait then newTrait.Name else tostring(response.data)), "Success")
			end
		end, { TextSize = 11, BackgroundColor3 = Theme.Colors.Accent, TextColor3 = Theme.Colors.Background })
	end
end

function UnitDetailsController:Init(controllers)
	self.Controllers = controllers
end

return UnitDetailsController
