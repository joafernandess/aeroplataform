--[[
	ZoneController
	Small top-centre pill telling the player where they are, recomputed every 0.25s from the character's
	HumanoidRootPart (horizontal distance only):
	  boss arena   within BOSS_RADIUS of a world boss position     -> "BOSS • Bandit King"
	  spawn area   within the area's Radius + AREA_MARGIN          -> "ZONE 2 • Ninja Camp" (numbered by config order)
	  world spawn  within SPAWN_RADIUS of the world's Spawn        -> "Shinobi Valley • Spawn"
	  elsewhere                                                     -> "Shinobi Valley"
	  inside a raid (RaidController.Active)                         -> "RAID • Abyssal Gate"
	Map overrides (Workspace.Worlds.<WorldId>.SpawnAreas.<AreaId>) move the area centres, like on the server.

	When the zone changes the pill pulses and a toast announces it ("Entering Zone 2 • Ninja Camp").
	Hidden while a window is open. ZoneController.Resolve is pure and unit-tested.

	Top-centre stack (shared anchor at y = 10, so the stack keeps its proportions under the HUD UIScale):
	  zone pill y 10 · target panel y 46 (TargetPanelController) · toasts y 112 (NotificationController)
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Config.Worlds)
local Enemies = require(Shared.Config.Enemies)
local Raids = require(Shared.Config.Raids)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local ZoneController = {
	Name = "ZoneController",
	Priority = 12,
}

export type Zone = {
	Key: string, -- stable identity ("W1:Zone:Camp", "W1:Boss:W1_SnakeSage", "W1:Spawn", "W1", "Raid:RAID_Abyss")
	Kind: string, -- "Zone" | "Boss" | "Spawn" | "World" | "Raid"
	WorldId: string?,
	Index: number?, -- zone number (Kind "Zone")
	Name: string,
	Text: string, -- pill caption
	Toast: string?, -- announcement when entering (nil = silent)
}

ZoneController.AREA_MARGIN = 10
ZoneController.BOSS_RADIUS = 26
ZoneController.SPAWN_RADIUS = 50
ZoneController.INTERVAL = 0.25
ZoneController.TOAST_COOLDOWN = 8 -- seconds before the same zone can be announced again

ZoneController.Current = nil :: Zone?

local PILL_SIZE = Vector2.new(260, 30)

-- Badge glyph / fill / glyph colour per zone kind (palette only).
local BADGES = {
	Zone = { Glyph = Theme.Icons.Worlds, Fill = Theme.Colors.Blue500, Color = Theme.Colors.White },
	Spawn = { Glyph = Theme.Icons.Worlds, Fill = Theme.Colors.Blue500, Color = Theme.Colors.White },
	World = { Glyph = Theme.Icons.Worlds, Fill = Theme.Colors.Blue500, Color = Theme.Colors.White },
	Boss = { Glyph = "!", Fill = Theme.Colors.Cyan, Color = Theme.Colors.Ink },
	Raid = { Glyph = Theme.Icons.Raids, Fill = Theme.Colors.Blue900, Color = Theme.Colors.Cyan },
}

local function planar(x1: number, z1: number, x2: number, z2: number): number
	local dx, dz = x1 - x2, z1 - z2
	return math.sqrt(dx * dx + dz * dz)
end

--[[
	Pure: which zone of `worldId` contains `position` (anything with X/Z, e.g. a Vector3).
	`centers` optionally overrides spawn-area centres by area id (map parts).
]]
function ZoneController.Resolve(worldId: string?, position: Vector3, centers: { [string]: Vector3 }?): Zone
	local world = (worldId and Worlds.Get(worldId)) or Worlds.List[1]
	local px, pz = position.X, position.Z
	for _, boss in world.Bosses do
		if planar(px, pz, boss.Position[1], boss.Position[3]) <= ZoneController.BOSS_RADIUS then
			local def = Enemies.Get(boss.Enemy)
			local name = if def then def.Name else boss.Enemy
			return {
				Key = world.Id .. ":Boss:" .. boss.Enemy,
				Kind = "Boss",
				WorldId = world.Id,
				Name = name,
				Text = "BOSS • " .. name,
				Toast = "Entering Boss Arena • " .. name,
			}
		end
	end
	for index, area in world.SpawnAreas do
		local override = centers and centers[area.Id]
		local cx = if override then override.X else area.Center[1]
		local cz = if override then override.Z else area.Center[3]
		if planar(px, pz, cx, cz) <= area.Radius + ZoneController.AREA_MARGIN then
			local name = area.Name or area.Id
			return {
				Key = world.Id .. ":Zone:" .. area.Id,
				Kind = "Zone",
				WorldId = world.Id,
				Index = index,
				Name = name,
				Text = ("ZONE %d • %s"):format(index, name),
				Toast = ("Entering Zone %d • %s"):format(index, name),
			}
		end
	end
	if planar(px, pz, world.Spawn[1], world.Spawn[3]) <= ZoneController.SPAWN_RADIUS then
		return { Key = world.Id .. ":Spawn", Kind = "Spawn", WorldId = world.Id, Name = world.Name, Text = world.Name .. " • Spawn" }
	end
	return { Key = world.Id, Kind = "World", WorldId = world.Id, Name = world.Name, Text = world.Name }
end

-- Map overrides for the spawn-area centres of a world (Workspace.Worlds.<WorldId>.SpawnAreas.<AreaId>).
local function mapCenters(worldId: string): { [string]: Vector3 }?
	local worlds = Workspace:FindFirstChild("Worlds")
	local world = worlds and worlds:FindFirstChild(worldId)
	local areas = world and world:FindFirstChild("SpawnAreas")
	if not areas then
		return nil
	end
	local out = {}
	for _, part in areas:GetChildren() do
		if part:IsA("BasePart") then
			out[part.Name] = part.Position
		end
	end
	return out
end

local function characterPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root then (root :: BasePart).Position else nil
end

-- Zone for the local player right now (nil while there is no character).
function ZoneController:Compute(): Zone?
	local raidController = self.Controllers and self.Controllers.RaidController
	local raid = raidController and raidController.Active
	if raid then
		local def = Raids.Get(raid.Raid)
		local name = if def then def.Name else "Raid"
		return { Key = "Raid:" .. tostring(raid.Raid), Kind = "Raid", Name = name, Text = "RAID • " .. name, Toast = "Entering Raid • " .. name }
	end
	local position = characterPosition()
	if not position then
		return nil
	end
	local data = State.Data
	local worldId = if data and data.CurrentWorld then data.CurrentWorld else Worlds.List[1].Id
	return ZoneController.Resolve(worldId, position, mapCenters(worldId))
end

function ZoneController:Render(zone: Zone)
	local badge = BADGES[zone.Kind] or BADGES.World
	self.Label.Text = zone.Text
	self.Badge.BackgroundColor3 = badge.Fill
	self.BadgeGlyph.Text = badge.Glyph
	self.BadgeGlyph.TextColor3 = badge.Color
	self.Container.Visible = not self.WindowOpen
end

-- Brief scale + colour pulse on change (the pill grows, flashes blue with a cyan rim, then settles).
function ZoneController:Pulse()
	local P = Theme.Colors
	self.PulseScale.Scale = 1.1 -- stays clear of the target panel 6px below
	self.Pill.BackgroundColor3 = P.Blue700
	self.PillStroke.Color = P.Cyan
	local info = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.PulseScale, info, { Scale = 1 }):Play()
	TweenService:Create(self.Pill, info, { BackgroundColor3 = P.Panel }):Play()
	TweenService:Create(self.PillStroke, info, { Color = P.Ink }):Play()
end

function ZoneController:Announce(zone: Zone, previous: Zone)
	local notifications = self.Controllers and self.Controllers.NotificationController
	if not notifications or not notifications.Container then
		return
	end
	local text = zone.Toast
	if not text and zone.WorldId and zone.WorldId ~= previous.WorldId then
		text = "Entering " .. zone.Name -- teleported to another world
	end
	if not text then
		return
	end
	local now = os.clock()
	local last = self.Announced[zone.Key]
	if last and now - last < ZoneController.TOAST_COOLDOWN then
		return -- walking back and forth over a border: don't spam
	end
	self.Announced[zone.Key] = now
	notifications:Show(text, "Zone", 2.5)
end

function ZoneController:Update()
	local zone = self:Compute()
	if not zone then
		return
	end
	local previous = self.Current
	if previous and previous.Key == zone.Key and previous.Text == zone.Text then
		return
	end
	self.Current = zone
	self:Render(zone)
	if previous then
		self:Pulse()
		self:Announce(zone, previous)
	end
end

function ZoneController:Init(controllers)
	self.Controllers = controllers
	self.Announced = {}
	self.WindowOpen = false
	local ui = controllers.UIController
	local P = Theme.Colors

	self.Container = C.Frame(ui:GetRoot(), {
		Name = "ZonePill",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(PILL_SIZE.X, PILL_SIZE.Y),
		Visible = false, -- shown once the first zone is known
	})
	ui:AddScaled(self.Container, "Hud")

	self.Pill = C.Frame(self.Container, {
		Name = "Pill",
		BackgroundColor3 = P.Panel,
		BackgroundTransparency = 0.08,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	})
	C.Corner(self.Pill, UDim.new(0.5, 0))
	self.PillStroke = C.Stroke(self.Pill, P.Ink, 2.5)
	self.PulseScale = C.Create("UIScale", { Parent = self.Pill })

	self.Badge = C.Frame(self.Pill, {
		Name = "Badge",
		BackgroundColor3 = P.Blue500,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(22, 22),
		ZIndex = 2,
	})
	C.Corner(self.Badge, UDim.new(0.5, 0))
	C.Stroke(self.Badge, P.Ink, Theme.Stroke.Badge)
	self.BadgeGlyph = C.Label(self.Badge, Theme.Icons.Worlds, {
		Font = Theme.Fonts.Title,
		Size = UDim2.fromScale(1, 1),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	})

	self.Label = C.Title(self.Pill, "", {
		Name = "Caption",
		Position = UDim2.fromOffset(30, 0),
		Size = UDim2.new(1, -40, 1, 0),
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 2,
	}, 2)
end

function ZoneController:Start()
	self.Controllers.UIController.WindowChanged:Connect(function(name)
		self.WindowOpen = name ~= nil
		self.Container.Visible = self.Current ~= nil and not self.WindowOpen
	end)
	State.Changed:Connect(function(key)
		if key == "CurrentWorld" then
			self:Update()
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(self.Update, self)
			if not ok then
				warn("[ZoneController] " .. tostring(err))
				task.wait(5)
			end
			task.wait(ZoneController.INTERVAL)
		end
	end)
end

return ZoneController
