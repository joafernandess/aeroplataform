--[[
	MapService
	Builds a playable greybox map from Config/Worlds when the place has no hand-made map.

	If Workspace.Worlds already exists (built in Studio), nothing is generated and the map's parts are used:
	  Workspace.Worlds.<WorldId>.Spawn                    BasePart — teleport point
	  Workspace.Worlds.<WorldId>.SpawnAreas.<AreaId>      BasePart — enemy area centre
	  Workspace.Worlds.<WorldId>.NPCs.<NpcId>             Model/Part with attributes Role + WorldId
	Otherwise, per world: grass ground, dirt paths spawn -> zones -> bosses, trees, zone signs, boss arenas,
	the summon orb next to the spawn and NPC pillars for enabled systems (Features). Base game = world 1 only.

	NPC interaction is client-side: prompts carry the attributes Role/WorldId and the client opens the
	matching window (Summon/Quest/Shop/Upgrade/Teleport/Raid) when a prompt is triggered.
]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Features = require(Shared.Config.Features)
local Worlds = require(Shared.Config.Worlds)
local Banners = require(Shared.Config.Banners)
local Enemies = require(Shared.Config.Enemies)

local MapService = {
	Name = "MapService",
	Priority = 0,
}

local ROLE_COLORS = {
	Quest = Color3.fromRGB(80, 200, 255),
	Shop = Color3.fromRGB(120, 255, 120),
	Upgrade = Color3.fromRGB(255, 120, 80),
	Teleport = Color3.fromRGB(180, 120, 255),
	Raid = Color3.fromRGB(200, 40, 200),
}

-- NPC roles only appear when their system is enabled.
local ROLE_FEATURE = { Quest = "Quests", Shop = "Shop", Upgrade = "Upgrades", Teleport = "MultipleWorlds", Raid = "Raids" }

local GROUND_TOP = 2 -- greybox ground surface height (config Y = 3 is one stud above it)

local function vec(v): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

local function flat(v: Vector3, y: number): Vector3
	return Vector3.new(v.X, y, v.Z)
end

local function part(props): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local parent = props.Parent
	props.Parent = nil
	for key, value in props do
		(p :: any)[key] = value
	end
	p.Parent = parent
	return p
end

local function addLabel(adornee: BasePart, text: string, color: Color3?, height: number?, size: number?)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(size or 220, 44)
	gui.StudsOffset = Vector3.new(0, height or (adornee.Size.Y / 2 + 2), 0)
	gui.MaxDistance = 160
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = color or Color3.new(1, 1, 1)
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(12, 10, 26)
	stroke.Parent = label
	label.Parent = gui
	gui.Parent = adornee
end

local function addPrompt(parent: Instance, role: string, worldId: string?, action: string, object: string)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("Role", role)
	if worldId then
		prompt:SetAttribute("WorldId", worldId)
	end
	prompt.Parent = parent
end

-- Dirt path between two points on the ground.
local function path(parent: Instance, from: Vector3, to: Vector3, width: number)
	local a, b = flat(from, GROUND_TOP + 0.05), flat(to, GROUND_TOP + 0.05)
	local length = (b - a).Magnitude
	if length < 1 then
		return
	end
	part({
		Name = "Path",
		Size = Vector3.new(width, 0.1, length + width),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = Color3.fromRGB(196, 160, 110),
		Material = Enum.Material.Ground,
		CanCollide = false,
		Parent = parent,
	})
end

local function tree(parent: Instance, at: Vector3, size: number, leaf: Color3)
	local model = Instance.new("Model")
	model.Name = "Tree"
	part({ Name = "Trunk", Size = Vector3.new(1.6, 7, 1.6) * size, CFrame = CFrame.new(flat(at, GROUND_TOP + 3.5 * size)), Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood, Parent = model })
	part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(8, 8, 8) * size, CFrame = CFrame.new(flat(at, GROUND_TOP + 8.5 * size)), Color = leaf, Material = Enum.Material.Grass, Parent = model })
	part({ Name = "Leaves2", Shape = Enum.PartType.Ball, Size = Vector3.new(5.5, 5.5, 5.5) * size, CFrame = CFrame.new(flat(at, GROUND_TOP + 11.5 * size) + Vector3.new(1, 0, -0.5) * size), Color = leaf:Lerp(Color3.new(1, 1, 1), 0.12), Material = Enum.Material.Grass, Parent = model })
	model.Parent = parent
end

-- The summon orb: a glowing star-orb on a stone pedestal, opened with a ProximityPrompt.
local function summonOrb(parent: Instance, world, position: Vector3)
	local model = Instance.new("Model")
	model.Name = world.Id .. "_SummonOrb"
	local base = part({ Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 14, 14), CFrame = CFrame.new(flat(position, GROUND_TOP + 1)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(120, 115, 140), Material = Enum.Material.Slate, Parent = model })
	part({ Name = "Pillar", Size = Vector3.new(3, 5, 3), CFrame = CFrame.new(flat(position, GROUND_TOP + 4.5)), Color = Color3.fromRGB(140, 135, 160), Material = Enum.Material.Slate, Parent = model })
	local orbCenter = flat(position, GROUND_TOP + 10.5)
	local orb = part({ Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.new(7, 7, 7), CFrame = CFrame.new(orbCenter), Color = Color3.fromRGB(255, 120, 220), Material = Enum.Material.Neon, CanCollide = false, Parent = model })
	part({ Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 11, 11), CFrame = CFrame.new(orbCenter) * CFrame.Angles(math.rad(20), 0, math.rad(90)), Color = Color3.fromRGB(255, 220, 90), Material = Enum.Material.Neon, CanCollide = false, Transparency = 0.25, Parent = model })
	local light = Instance.new("PointLight")
	light.Color = orb.Color
	light.Range = 18
	light.Brightness = 2
	light.Parent = orb
	local banner = Banners.Get(world.Banner)
	local price = if banner then ("%d %s"):format(banner.CostSingle, if banner.Currency == "Yen" then "¥" else banner.Currency) else ""
	addLabel(orb, (if banner then banner.Name else "Summon") .. "\n" .. price, Color3.fromRGB(255, 220, 90), 6, 240)
	addPrompt(base, "Summon", world.Id, "Open", if banner then banner.Name else "Summon")
	model.PrimaryPart = base
	model.Parent = parent
end

local function enabledWorlds()
	local list = {}
	for _, world in Worlds.List do
		if Features.MultipleWorlds or world.Id == GameConfig.Start.World then
			table.insert(list, world)
		end
	end
	return list
end

function MapService:BuildGreybox(): Folder
	local root = Instance.new("Folder")
	root.Name = "Worlds"

	for _, world in enabledWorlds() do
		local folder = Instance.new("Folder")
		folder.Name = world.Id
		folder.Parent = root
		local decor = Instance.new("Folder")
		decor.Name = "Decor"
		decor.Parent = folder

		local spawnPos = vec(world.Spawn)
		local theme = Color3.fromRGB(world.Theme[1], world.Theme[2], world.Theme[3])
		local origin = spawnPos.X

		part({ Name = "Ground", Size = Vector3.new(480, 2, 360), CFrame = CFrame.new(origin + 130, GROUND_TOP - 1, 0), Color = theme, Material = Enum.Material.Grass, Parent = folder })
		-- Border: a hedge you can see plus a tall invisible wall so nobody walks off the map.
		local hedgeColor = theme:Lerp(Color3.fromRGB(20, 80, 30), 0.55)
		for _, edge in {
			{ Vector3.new(480, 5, 3), Vector3.new(origin + 130, 0, 178.5) },
			{ Vector3.new(480, 5, 3), Vector3.new(origin + 130, 0, -178.5) },
			{ Vector3.new(3, 5, 360), Vector3.new(origin + 368.5, 0, 0) },
			{ Vector3.new(3, 5, 360), Vector3.new(origin - 108.5, 0, 0) },
		} do
			local size, at = edge[1], edge[2]
			part({ Name = "Hedge", Size = size, CFrame = CFrame.new(at.X, GROUND_TOP + 2.5, at.Z), Color = hedgeColor, Material = Enum.Material.Grass, Parent = decor })
			part({ Name = "Wall", Size = Vector3.new(size.X, 60, size.Z), CFrame = CFrame.new(at.X, GROUND_TOP + 30, at.Z), Transparency = 1, Parent = decor })
		end

		-- Spawn: the first world's pad is a real SpawnLocation so characters spawn on the map.
		local spawnPad = Instance.new(if world.Order == 1 then "SpawnLocation" else "Part")
		spawnPad.Name = "Spawn"
		spawnPad.Anchored = true
		spawnPad.Size = Vector3.new(16, 1, 16)
		spawnPad.CFrame = CFrame.new(spawnPos.X, GROUND_TOP + 0.5, spawnPos.Z)
		spawnPad.Color = Color3.fromRGB(235, 235, 245)
		spawnPad.Material = Enum.Material.SmoothPlastic
		spawnPad.Parent = folder
		addLabel(spawnPad, world.Name, nil, 6, 280)

		-- Zones with signs, linked by dirt paths from the spawn.
		local areas = Instance.new("Folder")
		areas.Name = "SpawnAreas"
		areas.Parent = folder
		local previous = spawnPos
		for index, area in world.SpawnAreas do
			local center = vec(area.Center)
			local marker = part({
				Name = area.Id,
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.2, area.Radius * 2, area.Radius * 2),
				CFrame = CFrame.new(flat(center, GROUND_TOP + 0.08)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = theme:Lerp(Color3.fromRGB(90, 70, 40), 0.25),
				Material = Enum.Material.Ground,
				CanCollide = false,
				Parent = areas,
			})
			path(decor, previous, center, 10)
			previous = center
			local sign = part({ Name = "Sign", Size = Vector3.new(0.5, 6, 0.5), CFrame = CFrame.new(flat(center, GROUND_TOP + 3) + Vector3.new(-area.Radius - 3, 0, 0)), Color = Color3.fromRGB(120, 80, 50), Material = Enum.Material.Wood, Parent = decor })
			addLabel(sign, ("Zone %d • %s"):format(index, area.Name or area.Id), nil, 5, 260)
			local _ = marker
		end

		-- Boss arenas.
		for _, boss in world.Bosses do
			local position = vec(boss.Position)
			local def = Enemies.Get(boss.Enemy)
			local tier = def and Enemies.Tiers[def.Tier]
			local ring = part({
				Name = "BossArena",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.4, 34, 34),
				CFrame = CFrame.new(flat(position, GROUND_TOP + 0.1)) * CFrame.Angles(0, 0, math.rad(90)),
				Color = if tier then Color3.fromRGB(tier.Color[1], tier.Color[2], tier.Color[3]):Lerp(Color3.new(0, 0, 0), 0.4) else Color3.new(0.3, 0.1, 0.1),
				Material = Enum.Material.Slate,
				CanCollide = false,
				Parent = decor,
			})
			path(decor, previous, position, 8)
			local _ = ring
		end

		-- Trees around the edges (deterministic, never inside zones, arenas or the spawn plaza).
		local blocked = { { spawnPos, 40 } }
		for _, area in world.SpawnAreas do
			table.insert(blocked, { vec(area.Center), area.Radius + 10 })
		end
		for _, boss in world.Bosses do
			table.insert(blocked, { vec(boss.Position), 26 })
		end
		local random = Random.new(world.Order * 1013)
		local placed = 0
		for _ = 1, 400 do
			if placed >= 55 then
				break
			end
			local at = Vector3.new(origin + 130 + random:NextNumber(-230, 230), GROUND_TOP, random:NextNumber(-170, 170))
			local free = true
			for _, b in blocked do
				if (flat(at, 0) - flat(b[1], 0)).Magnitude < b[2] then
					free = false
					break
				end
			end
			if free then
				placed += 1
				tree(decor, at, random:NextNumber(0.8, 1.4), theme:Lerp(Color3.fromRGB(30, 110, 40), 0.5))
				table.insert(blocked, { at, 9 })
			end
		end

		-- Summon orb + NPCs for enabled systems.
		local npcs = Instance.new("Folder")
		npcs.Name = "NPCs"
		npcs.Parent = folder
		for _, npc in world.NPCs do
			if npc.Role == "Summon" then
				summonOrb(npcs, world, vec(npc.Position))
			else
				local feature = ROLE_FEATURE[npc.Role]
				if not feature or Features[feature] then
					local body = part({ Name = npc.Id, Size = Vector3.new(4, 7, 4), CFrame = CFrame.new(flat(vec(npc.Position), GROUND_TOP + 3.5)), Color = ROLE_COLORS[npc.Role] or Color3.new(1, 1, 1), Parent = npcs })
					body:SetAttribute("Role", npc.Role)
					body:SetAttribute("WorldId", world.Id)
					addLabel(body, npc.Name)
					addPrompt(body, npc.Role, world.Id, npc.Role, npc.Name)
				end
			end
		end
	end

	if Features.Raids then
		local origin = vec(Worlds.RaidArenaOrigin)
		local arenas = Instance.new("Folder")
		arenas.Name = "RaidArenas"
		arenas.Parent = root
		for slot = 0, 7 do
			part({ Name = "Arena" .. slot, Size = Vector3.new(160, 2, 160), CFrame = CFrame.new(origin + Vector3.new(slot * 400, -2, 30)), Color = Color3.fromRGB(40, 20, 60), Material = Enum.Material.Slate, Parent = arenas })
		end
		local w3 = root:FindFirstChild("W3")
		local w3Def = Worlds.Get("W3")
		if w3 and w3Def then
			local gate = part({ Name = "RaidGate", Size = Vector3.new(6, 10, 2), CFrame = CFrame.new(vec(w3Def.Spawn) + Vector3.new(-25, 1.5, 45)), Color = ROLE_COLORS.Raid, Material = Enum.Material.Neon, Parent = w3 })
			addLabel(gate, "Raid Gate")
			addPrompt(gate, "Raid", nil, "Raids", "Raid Gate")
		end
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
