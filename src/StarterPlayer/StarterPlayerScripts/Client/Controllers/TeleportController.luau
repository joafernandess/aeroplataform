--[[
	TeleportController
	"Teleport" window (TP button), organised by world:
	  current world  every area from Worlds.GetTeleportPoints (spawn, summon orb, each zone, each boss) with GO;
	                 the server (WorldService:TeleportToPoint) checks the point belongs to the player's world
	  other worlds   TRAVEL when unlocked (TeleportWorld, server-validated), otherwise LOCKED with the unlock
	                 requirements from Config/Worlds ("Coming soon" while Features.MultipleWorlds is off)
	The window closes after a successful teleport.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Config.Worlds)
local Enemies = require(Shared.Config.Enemies)
local Features = require(Shared.Config.Features)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local TeleportController = {
	Name = "TeleportController",
	Priority = 32,
}

local P = Theme.Colors

local KIND_ICON = { Spawn = "worlds", Summon = "summon", Zone = "zone", Boss = "boss" }
local KIND_ACCENT = { Spawn = P.White, Summon = P.Cyan, Zone = P.Blue400, Boss = P.Ice }
local TIER_LABEL = { MiniBoss = "Mini boss", WorldBoss = "World boss", RaidBoss = "Raid boss" }

local function enemyName(id: string): string
	local def = Enemies.Get(id)
	return if def then def.Name else id
end

-- "Bandit, Rogue Ninja" (most common first).
local function zoneEnemies(area): string
	local list = {}
	for id, weight in area.Enemies or {} do
		table.insert(list, { Name = enemyName(id), Weight = weight })
	end
	table.sort(list, function(a, b)
		if a.Weight == b.Weight then
			return a.Name < b.Name
		end
		return a.Weight > b.Weight
	end)
	local names = {}
	for _, entry in list do
		table.insert(names, entry.Name)
	end
	return table.concat(names, ", ")
end

-- Display name and subtitle for a point.
function TeleportController.Describe(world, point): (string, string)
	if point.Kind == "Spawn" then
		return "Spawn", "Start of " .. world.Name
	elseif point.Kind == "Summon" then
		return point.Name, "Open stars with Yen"
	elseif point.Kind == "Zone" then
		for _, area in world.SpawnAreas do
			if "zone_" .. area.Id == point.Id then
				return point.Name, zoneEnemies(area)
			end
		end
		return point.Name, "Enemy zone"
	elseif point.Kind == "Boss" then
		local def = Enemies.Get(point.Name)
		return enemyName(point.Name), (def and TIER_LABEL[def.Tier or ""]) or "Boss"
	end
	return point.Name, ""
end

function TeleportController:Go(pointId: string)
	local response = State.Request("TeleportToPoint", pointId)
	if response.ok then
		self.Controllers.UIController:Close("Teleport")
	end
end

-- "25K Yen · Level 10 · Unlock Shinobi Valley" (empty when the world is free).
function TeleportController.RequirementText(world): string
	local parts = {}
	local cost = world.UnlockCost
	if cost and cost.Amount and cost.Amount > 0 then
		table.insert(parts, NumberFormat.Abbreviate(cost.Amount) .. " " .. cost.Currency)
	end
	local req = world.Requirements or {}
	if req.Level then
		table.insert(parts, "Level " .. req.Level)
	end
	if req.WorldUnlocked then
		local other = Worlds.Get(req.WorldUnlocked)
		table.insert(parts, "Unlock " .. (if other then other.Name else req.WorldUnlocked))
	end
	return table.concat(parts, " · ")
end

-- One teleport point of the current world (area icon, name, what is there, GO).
function TeleportController:_pointRow(world, point, order: number)
	local name, subtitle = TeleportController.Describe(world, point)
	local row = C.Row(self.List, { Name = point.Id, Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order })
	local tile = C.Frame(row, { BackgroundColor3 = P.Bg, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(50, 50) })
	C.Corner(tile, Theme.Radius.Tool)
	C.Stroke(tile, KIND_ACCENT[point.Kind] or P.Line, 2)
	C.Icon(tile, KIND_ICON[point.Kind] or "teleport", { Size = 34, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = KIND_ACCENT[point.Kind] or P.White })
	C.Title(row, name, { Name = "PointName", Position = UDim2.fromOffset(74, 9), Size = UDim2.new(1, -210, 0, 28), TextSize = 21, TextTruncate = Enum.TextTruncate.AtEnd }, 2)
	C.Label(row, subtitle, { Name = "Subtitle", Position = UDim2.fromOffset(74, 37), Size = UDim2.new(1, -210, 0, 22), TextSize = 15, TextColor3 = P.TextDim, TextTruncate = Enum.TextTruncate.AtEnd })
	C.Button(row, "GO", function()
		task.spawn(self.Go, self, point.Id)
	end, {
		Name = "Go",
		Kind = if point.Kind == "Boss" then "Accent" else "Primary",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(112, 48),
		TextSize = 20,
		Confirm = false,
	})
end

-- Another world: travel button when it is unlocked, otherwise a locked row with its requirements.
function TeleportController:_worldRow(data, world, order: number)
	local unlocked = data.UnlockedWorlds[world.Id] == true and Features.MultipleWorlds
	local row = C.Row(self.List, { Name = "World_" .. world.Id, Size = UDim2.new(1, -8, 0, 70), LayoutOrder = order })
	local tile = C.Frame(row, { BackgroundColor3 = P.Bg, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(50, 50) })
	C.Corner(tile, Theme.Radius.Tool)
	C.Stroke(tile, if unlocked then P.Gold else P.Line, 2)
	C.Icon(tile, if unlocked then "worlds" else "lock", { Size = 32, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = if unlocked then P.Gold else P.TextDim })
	C.Title(row, ("World %d · %s"):format(world.Order, world.Name), { Name = "WorldName", Position = UDim2.fromOffset(74, 9), Size = UDim2.new(1, -230, 0, 28), TextSize = 20, TextColor3 = if unlocked then P.White else P.TextDim, TextTruncate = Enum.TextTruncate.AtEnd }, 2)
	local requirement = TeleportController.RequirementText(world)
	local subtitle = if unlocked
		then "Unlocked"
		elseif not Features.MultipleWorlds then "Coming soon" .. (if requirement ~= "" then " · needs " .. requirement else "")
		else "Needs " .. requirement
	C.Label(row, subtitle, { Name = "Requirement", Position = UDim2.fromOffset(74, 37), Size = UDim2.new(1, -230, 0, 22), TextSize = 15, TextColor3 = if unlocked then P.Cyan else P.Gold, TextTruncate = Enum.TextTruncate.AtEnd })
	local button = C.Button(row, if unlocked then "TRAVEL" else "LOCKED", if unlocked
		then function()
			task.spawn(function()
				if State.Request("TeleportWorld", world.Id).ok then
					self.Controllers.UIController:Close("Teleport")
				end
			end)
		end
		else nil, {
		Name = if unlocked then "Travel" else "Locked",
		Kind = if unlocked then "Primary" else "Dark",
		Icon = if unlocked then nil else "lock",
		IconSize = 18,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(132, 48),
		TextSize = 18,
		Confirm = false,
	})
	if not unlocked then
		C.SetDisabled(button, true)
	end
end

function TeleportController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	local current = Worlds.Get(data.CurrentWorld)
	if not current then
		C.EmptyState(self.List, "teleport", "Nowhere to go", "Teleport points will appear once you are in a world.")
		return
	end
	-- Current world: its areas (spawn, summon orb, zones, bosses)
	C.Section(self.List, ("World %d · %s  ·  you are here"):format(current.Order, current.Name), 0)
	local order = 0
	for _, point in Worlds.GetTeleportPoints(current.Id) do
		order += 1
		self:_pointRow(current, point, order)
	end
	-- Every other world, in order: travel (unlocked) or locked with its requirements
	local others = {}
	for _, world in Worlds.List do
		if world.Id ~= current.Id then
			table.insert(others, world)
		end
	end
	table.sort(others, function(a, b)
		return a.Order < b.Order
	end)
	if #others > 0 then
		order += 1
		C.Section(self.List, "Other worlds", order)
		for _, world in others do
			order += 1
			self:_worldRow(data, world, order)
		end
	end
end

function TeleportController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Teleport", "Teleport", UDim2.fromOffset(600, 500), function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = self.List })
end

function TeleportController:Start()
	State.Observe({ "CurrentWorld", "UnlockedWorlds", "Level" }, function()
		self:Render()
	end)
end

return TeleportController
