--[[
	UnitDetailsController
	Renders the details panel for one unit (inside the Units window): stats, abilities, comparison with
	the weakest equipped unit, and actions (equip, lock, sell, fuse, evolve, XP potions, trait reroll).
	All actions are server requests; the panel re-renders when DataChanged arrives.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local Features = require(Shared.Config.Features)
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
	local row = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order })
	C.Label(row, label, { Size = UDim2.new(0.42, 0, 1, 0), TextSize = 15, TextColor3 = Theme.Colors.TextDim })
	C.Number(row, value, {
		Position = UDim2.fromScale(0.42, 0),
		Size = UDim2.new(0.58, -2, 1, 0),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = color or Theme.Colors.White,
	})
end

function UnitDetailsController:Render(container: Frame, uid: string?)
	C.Clear(container)
	local data = State.Data
	local unit = data and uid and data.Inventory.Units[uid]
	if not unit then
		C.Title(container, "Select a fighter", { TextSize = 20, Size = UDim2.new(1, 0, 0, 28) })
		C.Label(container, "Tap a card to see its stats and actions.", {
			Position = UDim2.fromOffset(0, 30),
			TextColor3 = Theme.Colors.TextDim,
			TextSize = 15,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 40),
		})
		return
	end
	local def = Units.Get(unit.UnitId)
	local stats = UnitStats.Compute(unit)
	if not def or not stats then
		return
	end
	local inventory = self.Controllers.InventoryController
	local equipped = table.find(data.EquippedUnits, uid) ~= nil
	local rarityColor = Theme.Rarity(def.Rarity)

	local scroll = C.Scroll(container)
	C.List(scroll, Enum.FillDirection.Vertical, 6)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end

	-- Header: name + rarity pill + series
	C.Title(scroll, def.Name, {
		Font = Theme.Fonts.Display,
		TextSize = 26,
		LayoutOrder = nextOrder(),
		TextWrapped = true,
		Size = UDim2.new(1, 0, 0, 30),
	}, 3)
	local tagRow = C.Frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder() })
	local pill = C.Frame(tagRow, { BackgroundColor3 = Theme.Colors.PanelAlt, Size = UDim2.fromOffset(110, 24) })
	C.Corner(pill, UDim.new(0.5, 0))
	C.Stroke(pill, Theme.Colors.Ink, 2)
	local dot = C.Frame(pill, { BackgroundColor3 = rarityColor, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(12, 12) })
	C.Corner(dot, UDim.new(0.5, 0))
	C.Title(pill, def.Rarity, { Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), TextSize = 14 }, 1.5)
	C.Label(tagRow, def.Anime .. (if def.Evolved then " • Evolved" else ""), {
		Position = UDim2.fromOffset(118, 0),
		Size = UDim2.new(1, -118, 1, 0),
		TextSize = 14,
		TextColor3 = Theme.Colors.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local maxLevel = Formulas.UnitMaxLevel(def.Rarity)
	local bar = C.ProgressBar(scroll, nil, { LayoutOrder = nextOrder() })
	if unit.Level >= maxLevel then
		bar.Set(1, ("Lv %d (MAX)"):format(unit.Level))
	else
		local needed = Formulas.UnitXPToNext(unit.Level, def.Rarity)
		bar.Set(unit.XP / needed, ("Lv %d/%d • %s/%s XP"):format(unit.Level, maxLevel, NumberFormat.Abbreviate(unit.XP), NumberFormat.Abbreviate(needed)))
	end

	-- Stats well
	local well = C.Frame(scroll, { BackgroundColor3 = Theme.Colors.PanelAlt, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	C.Corner(well, Theme.Radius.Card)
	C.Stroke(well, Theme.Colors.Ink, 2.5)
	C.Padding(well, 8)
	C.List(well, Enum.FillDirection.Vertical, 2)
	local stars = unit.Stars or 0
	statLine(well, "Stars", string.rep("★", stars) .. string.rep("☆", 5 - stars), 1, if stars >= 5 then Theme.Colors.Cyan else Theme.Colors.White)
	local trait = unit.Trait and Traits.Get(unit.Trait)
	if Features.Traits then
		statLine(well, "Trait", if trait then trait.Name .. " (" .. trait.Description .. ")" else "None", 2, Theme.Colors.Cyan)
	end
	statLine(well, "Power", NumberFormat.Abbreviate(stats.Power), 3, Theme.Colors.Cyan)
	statLine(well, "Damage", NumberFormat.Abbreviate(stats.Damage), 4)
	statLine(well, "Attack speed", ("%.2f/s"):format(stats.AttackSpeed), 5)
	statLine(well, "Range", ("%d studs"):format(math.floor(stats.Range)), 6)
	statLine(well, "Crit chance", NumberFormat.Percent(stats.CritChance), 7)

	local passive = Abilities.GetPassive(def.Passive)
	local special = Abilities.GetSpecial(def.Special)
	if passive then
		C.Label(scroll, "Passive: " .. passive.Name .. " — " .. passive.Description, { TextSize = 14, TextWrapped = true, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder() })
	end
	if special then
		C.Label(scroll, ("Special: %s — %s (%ds cd)"):format(special.Name, special.Description, special.Cooldown), {
			TextSize = 14,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = nextOrder(),
		})
	end

	-- Comparison against the weakest equipped unit
	local other = weakestEquipped(data, uid)
	if other and not equipped then
		local diffs = UnitStats.Compare(other, unit)
		if diffs then
			local power = diffs[1]
			local better = power.Difference > 0
			C.Title(scroll, ("vs weakest equipped: %s%s Power"):format(if better then "+" else "", NumberFormat.Abbreviate(power.Difference)), {
				TextSize = 15,
				TextColor3 = if better then Theme.Colors.Cyan else Theme.Colors.TextDim,
				LayoutOrder = nextOrder(),
			}, 2)
		end
	end

	-- Actions
	local actions = C.Frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	C.Grid(actions, UDim2.new(0.5, -5, 0, 48), 10)
	C.Button(actions, if equipped then "Unequip" else "Equip", function()
		State.Request(if equipped then "UnequipUnit" else "EquipUnit", uid)
	end, { Kind = if equipped then "Secondary" else "Primary", TextSize = 18 })
	C.Button(actions, if unit.Locked then "Unlock" else "Lock", function()
		State.Request("LockUnit", uid, not unit.Locked)
	end, { Kind = "Dark", TextSize = 18 })
	if Features.Fusion then
		C.Button(actions, "Fuse", function()
			inventory:SetMode("Fuse")
		end, { Kind = "Accent", TextSize = 18 })
	end
	C.Button(actions, "Sell", function()
		local response = State.Request("DeleteUnits", { uid })
		if response.ok and response.data.Deleted == 0 and State.Notify then
			State.Notify("Can't sell: unit is locked or equipped.", "Error")
		end
	end, {
		Kind = "Danger",
		TextSize = 17,
		Subtext = NumberFormat.Abbreviate(Formulas.UnitSellValue(def.Rarity, unit.Level, unit.Stars or 0)) .. " " .. Theme.Icons.Yen,
	})

	if Features.Evolution and def.EvolvesTo and def.EvolutionCost then
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
		C.Label(scroll, "Evolve: " .. table.concat(parts, ", "), {
			TextSize = 14,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 34),
			LayoutOrder = nextOrder(),
			TextColor3 = Theme.Colors.TextDim,
		})
		local evolve = C.Button(scroll, if unit.Level >= maxLevel then "EVOLVE" else ("Evolve at Lv %d"):format(maxLevel), function()
			local response = State.Request("EvolveUnit", uid)
			if response.ok and State.Notify then
				State.Notify(def.Name .. " evolved!", "Success")
			end
		end, { Kind = "Primary", Size = UDim2.new(1, 0, 0, 52), TextSize = 20, LayoutOrder = nextOrder() })
		C.SetDisabled(evolve, unit.Level < maxLevel)
	end

	-- Consumables on this unit
	local consumables = C.Frame(scroll, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
	C.Grid(consumables, UDim2.new(0.5, -5, 0, 46), 10)
	for _, itemId in if Features.Items then POTIONS else {} do
		local have = data.Inventory.Items[itemId] or 0
		if have > 0 then
			local itemDef = Items.Get(itemId)
			C.Button(consumables, ("%s (%d)"):format(itemDef.Name, have), function()
				State.Request("UseItem", itemId, uid, 1)
			end, { Kind = "Dark", TextSize = 13 })
		end
	end
	if Features.Items and Features.Traits and (data.Inventory.Items.TraitCrystal or 0) > 0 then
		C.Button(consumables, ("Reroll Trait (%d)"):format(data.Inventory.Items.TraitCrystal), function()
			local response = State.Request("UseItem", "TraitCrystal", uid, 1)
			if response.ok and State.Notify then
				local newTrait = Traits.Get(response.data)
				State.Notify("New trait: " .. (if newTrait then newTrait.Name else tostring(response.data)), "Success")
			end
		end, { Kind = "Accent", TextSize = 13 })
	end
end

function UnitDetailsController:Init(controllers)
	self.Controllers = controllers
end

return UnitDetailsController
