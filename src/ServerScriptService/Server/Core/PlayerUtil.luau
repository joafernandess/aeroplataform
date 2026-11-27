--[[
	PlayerUtil
	Safe accessors for a player's character. Everything returns nil instead of erroring when the
	character is missing, dead or still loading.
]]

local PlayerUtil = {}

function PlayerUtil.GetRoot(player): BasePart?
	local character = player and player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function PlayerUtil.GetPosition(player): Vector3?
	local root = PlayerUtil.GetRoot(player)
	return root and root.Position
end

function PlayerUtil.GetHumanoid(player): Humanoid?
	local character = player and player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function PlayerUtil.IsAlive(player): boolean
	local humanoid = PlayerUtil.GetHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

-- Moves the character to `position` (Vector3). Returns false if there is no character yet.
function PlayerUtil.Teleport(player, position: Vector3): boolean
	local character = player and player.Character
	if not character or not PlayerUtil.GetRoot(player) then
		return false
	end
	character:PivotTo(CFrame.new(position))
	return true
end

return PlayerUtil
