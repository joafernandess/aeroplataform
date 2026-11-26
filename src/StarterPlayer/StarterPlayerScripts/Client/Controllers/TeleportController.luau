--[[
	TeleportController
	"Teleport" window (TP button): every point of the current world from Worlds.GetTeleportPoints — spawn, summon
	orb, each enemy zone and each boss — with a GO button. The server (WorldService:TeleportToPoint) checks the
	point belongs to the player's world and moves the character; the window closes on success.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Config.Worlds)
local Enemies = require(Shared.Config.Enemies)

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

function TeleportController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	local world = Worlds.Get(data.CurrentWorld)
	if not world then
		C.EmptyState(self.List, "teleport", "Nowhere to go", "Teleport points will appear once you are in a world.")
		return
	end
	self.Window.Title.Text = "Teleport"
	C.Section(self.List, world.Name, 0)
	for i, point in Worlds.GetTeleportPoints(world.Id) do
		local name, subtitle = TeleportController.Describe(world, point)
		local row = C.Row(self.List, { Name = point.Id, Size = UDim2.new(1, -8, 0, 70), LayoutOrder = i })
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
			Icon = "teleport",
			IconSize = 20,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0),
			Size = UDim2.fromOffset(112, 48),
			TextSize = 20,
			Confirm = false,
		})
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
	State.Observe({ "CurrentWorld" }, function()
		self:Render()
	end)
end

return TeleportController
