--[[
	MapService
	Builds a playable greybox map from Config/Worlds when the place has no hand-made map.

	If Workspace.Worlds already exists (built in Studio), nothing is generated and the map's parts are used:
	  Workspace.Worlds.<WorldId>.Spawn                    BasePart — teleport point
	  Workspace.Worlds.<WorldId>.SpawnAreas.<AreaId>      BasePart — enemy area centre
	  Workspace.Worlds.<WorldId>.NPCs.<NpcId>             Model/Part with attributes Role + WorldId
	Otherwise it creates, per world: a ground plate, a spawn pad, NPC pillars with ProximityPrompts and
	markers for spawn areas/bosses; plus raid arena plates.

	NPC interaction is client-side: prompts carry the attributes Role/WorldId and the client opens the
	matching window (Summon/Quest/Shop/Upgrade/Teleport/Raid) when a prompt is triggered.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Worlds = require(Shared.Config.Worlds)

local MapService = {
	Name = "MapService",
	Priority = 0,
}

local ROLE_COLORS = {
	Summon = Color3.fromRGB(255, 200, 60),
	Quest = Color3.fromRGB(80, 200, 255),
	Shop = Color3.fromRGB(120, 255, 120),
	Upgrade = Color3.fromRGB(255, 120, 80),
	Teleport = Color3.fromRGB(180, 120, 255),
	Raid = Color3.fromRGB(200, 40, 200),
}

local function vec(v): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(p :: any)[key] = value
	end
	return p
end

local function addLabel(adornee: BasePart, text: string)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, adornee.Size.Y / 2 + 2, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
	gui.Parent = adornee
end

function MapService:BuildGreybox(): Folder
	local root = Instance.new("Folder")
	root.Name = "Worlds"

	for _, world in Worlds.List do
		local folder = Instance.new("Folder")
		folder.Name = world.Id
		folder.Parent = root

		local spawnPos = vec(world.Spawn)
		local theme = Color3.fromRGB(world.Theme[1], world.Theme[2], world.Theme[3])

		part({ Name = "Ground", Size = Vector3.new(460, 2, 340), CFrame = CFrame.new(spawnPos.X + 130, 1, 0), Color = theme, Material = Enum.Material.Grass, Parent = folder })

		-- The first world's pad is a real SpawnLocation so characters spawn on the map, not in the void.
		local spawnPad = Instance.new(if world.Order == 1 then "SpawnLocation" else "Part")
		spawnPad.Name = "Spawn"
		spawnPad.Anchored = true
		spawnPad.Size = Vector3.new(14, 1, 14)
		spawnPad.CFrame = CFrame.new(Vector3.new(spawnPos.X, 2.5, spawnPos.Z))
		spawnPad.Color = Color3.fromRGB(240, 240, 240)
		spawnPad.Material = Enum.Material.Neon
		spawnPad.Parent = folder
		addLabel(spawnPad, world.Name)

		local areas = Instance.new("Folder")
		areas.Name = "SpawnAreas"
		areas.Parent = folder
		for _, area in world.SpawnAreas do
			local marker = part({ Name = area.Id, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, area.Radius * 2, area.Radius * 2), CFrame = CFrame.new(vec(area.Center) - Vector3.new(0, 0.95, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = theme:Lerp(Color3.new(0, 0, 0), 0.25), CanCollide = false, Material = Enum.Material.SmoothPlastic, Parent = areas })
			marker.Transparency = 0.3
		end

		local npcs = Instance.new("Folder")
		npcs.Name = "NPCs"
		npcs.Parent = folder
		for _, npc in world.NPCs do
			local body = part({ Name = npc.Id, Size = Vector3.new(4, 7, 4), CFrame = CFrame.new(vec(npc.Position) + Vector3.new(0, 2.5, 0)), Color = ROLE_COLORS[npc.Role] or Color3.new(1, 1, 1), Material = Enum.Material.SmoothPlastic, Parent = npcs })
			body:SetAttribute("Role", npc.Role)
			body:SetAttribute("WorldId", world.Id)
			addLabel(body, npc.Name)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = npc.Role
			prompt.ObjectText = npc.Name
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 12
			prompt:SetAttribute("Role", npc.Role)
			prompt:SetAttribute("WorldId", world.Id)
			prompt.Parent = body
		end
	end

	-- Raid lobby NPC in world 3 and raid arena plates.
	local origin = vec(Worlds.RaidArenaOrigin)
	local arenas = Instance.new("Folder")
	arenas.Name = "RaidArenas"
	arenas.Parent = root
	for slot = 0, 7 do
		part({ Name = "Arena" .. slot, Size = Vector3.new(160, 2, 160), CFrame = CFrame.new(origin + Vector3.new(slot * 400, -2, 30)), Color = Color3.fromRGB(40, 20, 60), Material = Enum.Material.Slate, Parent = arenas })
	end
	local w3 = Worlds.Get("W3")
	if w3 then
		local raidNpc = part({ Name = "RaidGate", Size = Vector3.new(6, 10, 2), CFrame = CFrame.new(vec(w3.Spawn) + Vector3.new(-25, 1.5, 45)), Color = ROLE_COLORS.Raid, Material = Enum.Material.Neon, Parent = root:FindFirstChild("W3") })
		addLabel(raidNpc, "Raid Gate")
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Raids"
		prompt.ObjectText = "Raid Gate"
		prompt.HoldDuration = 0
		prompt:SetAttribute("Role", "Raid")
		prompt.Parent = raidNpc
	end

	root.Parent = Workspace
	return root
end

function MapService:Start()
	if Workspace:FindFirstChild("Worlds") then
		return
	end
	local ok, err = pcall(self.BuildGreybox, self)
	if not ok then
		warn("[MapService] Failed to build greybox map: " .. tostring(err))
	end
end

return MapService
