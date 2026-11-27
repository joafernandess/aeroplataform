--[[
	MountsController
	"Mounts" window: grid of the player's mounts (icon tinted by rarity, name, rarity, equipped ✓, gold outline on
	the equipped one) with Equip / Unequip on each card.

	The game has no mount system yet (Config/Mounts is empty and profiles have no data.Mounts), so the window shows
	an honest "not available yet" state — no fake mounts, no buttons that do nothing. Config/Mounts explains how to
	connect a real mount system; this window renders it without further changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Mounts = require(Shared.Config.Mounts)
local Rarities = require(Shared.Config.Rarities)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local MountsController = {
	Name = "MountsController",
	Priority = 37,
}

local CARD = UDim2.fromOffset(122, 168)
local P = Theme.Colors

-- Owned mount definitions (best rarity first) from data.Mounts = { [mountId] = true }.
function MountsController.Owned(data): { Mounts.MountDef }
	local list = {}
	for mountId, owned in (data and data.Mounts) or {} do
		local def = owned and Mounts.Get(mountId)
		if def then
			table.insert(list, def)
		end
	end
	table.sort(list, function(a, b)
		local ra, rb = Rarities.GetOrder(a.Rarity), Rarities.GetOrder(b.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		return a.Name < b.Name
	end)
	return list
end

function MountsController:_card(def, equipped: boolean, order: number)
	local rarity = Theme.Rarity(def.Rarity)
	local card = C.Frame(self.Grid, { Name = def.Id, BackgroundColor3 = P.PanelAlt, LayoutOrder = order })
	C.Corner(card, Theme.Radius.Card)
	C.Stroke(card, if equipped then P.Yellow else P.Ink, if equipped then 3 else 2.5)
	local well = C.Frame(card, { BackgroundColor3 = P.Bg, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 70) })
	C.Corner(well, 10)
	C.Stroke(well, rarity, 2)
	C.Icon(well, "mounts", { Size = 48, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = Theme.IconColors.mounts })
	C.Title(card, def.Name, { Position = UDim2.fromOffset(8, 82), Size = UDim2.new(1, -16, 0, 20), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }, 2)
	C.Title(card, string.upper(def.Rarity), { Position = UDim2.fromOffset(8, 102), Size = UDim2.new(1, -16, 0, 14), TextSize = 11, TextColor3 = rarity, TextXAlignment = Enum.TextXAlignment.Center }, 1.5)
	C.Button(card, if equipped then "Unequip" else "Equip", function()
		task.spawn(State.Request, if equipped then "UnequipMount" else "EquipMount", def.Id)
	end, {
		Name = "Equip",
		Kind = if equipped then "Secondary" else "Primary",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -16, 0, 38),
		TextSize = 15,
		Confirm = false,
	})
end

function MountsController:Render()
	if not self.Window.Frame.Visible then
		return
	end
	local data = State.Data
	C.Clear(self.List)
	C.Clear(self.Grid)
	local owned = MountsController.Owned(data)
	if #owned == 0 then
		self.Grid.Visible = false
		self.List.Visible = true
		if #Mounts.List == 0 then
			C.EmptyState(self.List, "mounts", "Mounts are not available yet", "Mounts aren't part of the game yet. When they are added, you'll find, equip and ride them from this menu.")
		else
			C.EmptyState(self.List, "mounts", "No mounts yet", "You don't own any mounts yet.")
		end
		return
	end
	self.List.Visible = false
	self.Grid.Visible = true
	for i, def in owned do
		self:_card(def, data.EquippedMount == def.Id, i)
	end
end

function MountsController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Mounts", "Mounts", UDim2.fromOffset(640, 460), function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 30), Parent = self.List })
	self.Grid = C.Scroll(self.Window.Content, { Name = "Grid", Visible = false })
	C.Grid(self.Grid, CARD, 12)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = self.Grid })
end

function MountsController:Start()
	State.Observe({ "Mounts", "EquippedMount" }, function()
		self:Render()
	end)
end

return MountsController
