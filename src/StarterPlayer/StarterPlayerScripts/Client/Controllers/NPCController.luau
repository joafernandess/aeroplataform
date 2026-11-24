--[[
	NPCController
	Opens the right window when a world NPC's ProximityPrompt is triggered. Prompts carry a "Role"
	attribute (and optionally "WorldId"), set by MapService or by hand in Studio.
]]

local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Worlds = require(ReplicatedStorage.Shared.Config.Worlds)

local NPCController = {
	Name = "NPCController",
	Priority = 50,
}

local ROLE_TO_WINDOW = {
	Summon = "Summon",
	Quest = "Quests",
	Shop = "Shop",
	Upgrade = "Upgrades",
	Teleport = "Worlds",
	Raid = "Raids",
}

function NPCController:Init(controllers)
	self.Controllers = controllers
end

function NPCController:Start()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		local role = prompt:GetAttribute("Role")
		local windowName = role and ROLE_TO_WINDOW[role]
		if not windowName then
			return
		end
		if role == "Summon" then
			local world = Worlds.Get(prompt:GetAttribute("WorldId") or "")
			self.Controllers.UIController:Open(windowName, world and world.Banner)
		else
			self.Controllers.UIController:Open(windowName)
		end
	end)
end

return NPCController
