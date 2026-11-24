--[[
	Requirements
	Declarative unlock checks shared by worlds, banners, raids, quests and shop items.
	Supported keys:
	  Level          minimum player level
	  WorldUnlocked  world id that must be unlocked
	  QuestCompleted main quest id that must be completed
	Returns ok, reasonText so the UI can display why something is locked.
]]

local Requirements = {}

function Requirements.Check(data: { [string]: any }, requirements: { [string]: any }?): (boolean, string?)
	if not requirements then
		return true, nil
	end
	if requirements.Level and (data.Level or 1) < requirements.Level then
		return false, ("Requires level %d"):format(requirements.Level)
	end
	if requirements.WorldUnlocked then
		local unlocked = data.UnlockedWorlds or {}
		if not unlocked[requirements.WorldUnlocked] then
			return false, ("Requires world %s"):format(requirements.WorldUnlocked)
		end
	end
	if requirements.QuestCompleted then
		local quests = data.Quests or {}
		local completed = quests.MainCompleted or {}
		if not completed[requirements.QuestCompleted] then
			return false, ("Requires quest %s"):format(requirements.QuestCompleted)
		end
	end
	return true, nil
end

return Requirements
