--[[
	RigBuilder
	Builds a blocky humanoid placeholder (head, torso, arms, legs, eyes, hair) out of anchored Parts.
	Used for enemies (server) and fighters (client) until real character models exist in Assets.

	The model's PrimaryPart is an invisible "HumanoidRootPart" at the torso centre, so
	  model:PivotTo(CFrame.new(x, groundY + RigBuilder.RootHeight(scale), z))
	stands the rig on the ground. Front of the rig is -Z (Roblox LookVector).
]]

local RigBuilder = {}

export type Options = {
	Name: string?,
	Scale: number?,
	Skin: Color3?,
	Shirt: Color3,
	Pants: Color3?,
	Hair: Color3?,
	Material: Enum.Material?,
}

-- name, size (studs at scale 1), offset from root, colour slot
local PARTS = {
	{ "Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), "Shirt" },
	{ "Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.65, 0), "Skin" },
	{ "Left Arm", Vector3.new(1, 2, 1), Vector3.new(-1.5, 0, 0), "Shirt" },
	{ "Right Arm", Vector3.new(1, 2, 1), Vector3.new(1.5, 0, 0), "Shirt" },
	{ "Left Leg", Vector3.new(1, 2, 1), Vector3.new(-0.5, -2, 0), "Pants" },
	{ "Right Leg", Vector3.new(1, 2, 1), Vector3.new(0.5, -2, 0), "Pants" },
	{ "Hair", Vector3.new(1.45, 0.45, 1.45), Vector3.new(0, 2.35, 0.05), "Hair" },
	{ "LeftEye", Vector3.new(0.18, 0.32, 0.05), Vector3.new(-0.28, 1.72, -0.66), "Eye" },
	{ "RightEye", Vector3.new(0.18, 0.32, 0.05), Vector3.new(0.28, 1.72, -0.66), "Eye" },
}

-- Distance from the ground to the root (torso centre) at a given scale.
function RigBuilder.RootHeight(scale: number?): number
	return 3 * (scale or 1)
end

function RigBuilder.Build(options: Options): Model
	local scale = options.Scale or 1
	local colors = {
		Skin = options.Skin or Color3.fromRGB(255, 214, 170),
		Shirt = options.Shirt,
		Pants = options.Pants or Color3.fromRGB(45, 45, 60),
		Hair = options.Hair or Color3.fromRGB(40, 30, 25),
		Eye = Color3.fromRGB(20, 20, 25),
	}
	local model = Instance.new("Model")
	model.Name = options.Name or "Rig"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1) * scale
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.new()
	root.Parent = model

	for _, spec in PARTS do
		local part = Instance.new("Part")
		part.Name = spec[1]
		part.Size = spec[2] * scale
		part.CFrame = CFrame.new(spec[3] * scale)
		part.Color = colors[spec[4]]
		part.Material = options.Material or Enum.Material.SmoothPlastic
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = spec[4] ~= "Eye"
		part.Parent = model
	end

	model.PrimaryPart = root
	return model
end

return RigBuilder
