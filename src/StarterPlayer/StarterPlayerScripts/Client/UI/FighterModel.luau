--[[
	FighterModel
	Builds the 3D model of a fighter for the client: the real model from ReplicatedStorage.Assets.Units.<UnitId>
	when it exists, otherwise the blocky placeholder rig (RigBuilder) in the unit's rarity colours.
	Used by the fighters following the player (UnitVisualController) and by the Index thumbnails (ViewportFrames).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RigBuilder = require(Shared.Modules.RigBuilder)

local Theme = require(script.Parent.Theme)

local FighterModel = {}

-- The real model for a unit, if one was added to ReplicatedStorage.Assets.Units.
function FighterModel.FindAsset(unitId: string): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local units = assets and assets:FindFirstChild("Units")
	local model = units and units:FindFirstChild(unitId)
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

-- A new (unparented) model for the unit definition `def`.
function FighterModel.Build(def, scale: number?): Model
	local asset = FighterModel.FindAsset(def.Id)
	if asset then
		return asset:Clone()
	end
	local rarity = Theme.Rarity(def.Rarity)
	return RigBuilder.Build({
		Name = def.Name,
		Scale = scale or 1,
		Shirt = rarity,
		Pants = Theme.Darken(rarity, 0.55),
		Hair = Theme.Darken(rarity, 0.25),
	})
end

return FighterModel
