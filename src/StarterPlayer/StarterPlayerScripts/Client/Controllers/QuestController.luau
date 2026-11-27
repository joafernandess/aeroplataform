--[[
	QuestController
	"Quests" window: the current main quest and the daily quests (with the reset countdown), each with progress
	and Claim (ClaimQuest).
	The Quests menu button shows a badge with the number of quests ready to claim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Features = require(Shared.Config.Features)
local Quests = require(Shared.Config.Quests)
local Rewards = require(Shared.Modules.Rewards)
local Clock = require(Shared.Modules.Clock)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local QuestController = {
	Name = "QuestController",
	Priority = 24,
}

local function progressText(progress: number, target: number): string
	return ("%s / %s"):format(NumberFormat.Abbreviate(math.min(progress, target)), NumberFormat.Abbreviate(target))
end

-- Sorted ids of the active daily quests.
local function dailyIds(data): { string }
	local ids = {}
	for questId in data.Quests.Active do
		local def = Quests.Get(questId)
		if def and def.Category == "Daily" then
			table.insert(ids, questId)
		end
	end
	table.sort(ids)
	return ids
end

-- Quests completed but not claimed yet (main + daily).
function QuestController.ClaimableCount(data): number
	local count = 0
	for questId, entry in data.Quests.Active do
		if entry.Completed and not entry.Claimed and Quests.Get(questId) then
			count += 1
		end
	end
	return count
end

function QuestController:_row(order: number, questId: string, def, entry)
	C.ClaimRow(self.List, {
		Name = questId,
		Order = order,
		Title = def.Title,
		Description = def.Description,
		Rewards = Rewards.Describe(def.Rewards),
		Progress = entry.Progress,
		Target = def.Target,
		ProgressText = progressText(entry.Progress, def.Target),
		CanClaim = entry.Completed,
		Claimed = entry.Claimed,
	}, function()
		State.Request("ClaimQuest", questId)
	end)
end

function QuestController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	if not Features.Quests then
		C.EmptyState(self.List, "quests", "Quests are not available yet", "Quests will appear here once they are added to the game.")
		return
	end
	C.Section(self.List, "Main quest", 0)
	local main = data.Quests.MainCurrent
	local mainDef = main ~= "" and Quests.Get(main)
	if mainDef then
		local entry = data.Quests.Active[main] or { Progress = 0, Completed = false, Claimed = false }
		self:_row(1, main, mainDef, entry)
	else
		C.Label(self.List, "All main quests completed!", { TextColor3 = Theme.Colors.Cyan, LayoutOrder = 1, Font = Theme.Fonts.Bold })
	end

	local resetIn = Clock.SecondsUntilNextDay(math.floor(workspace:GetServerTimeNow()), GameConfig.Quests.DailyResetOffsetSeconds)
	C.Section(self.List, "Daily quests  ·  reset in " .. NumberFormat.Duration(resetIn), 10)
	local ids = dailyIds(data)
	if #ids == 0 then
		C.Label(self.List, "No daily quests right now.", { TextColor3 = Theme.Colors.TextDim, LayoutOrder = 11 })
	end
	for i, questId in ids do
		self:_row(10 + i, questId, Quests.Get(questId), data.Quests.Active[questId])
	end
end

function QuestController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Quests", "Quests", UDim2.fromOffset(680, 500), function()
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 8)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4), Parent = self.List })
end

function QuestController:Start()
	State.Observe({ "Quests" }, function(data)
		self.Controllers.UIController:SetMenuBadge("Quests", if Features.Quests then QuestController.ClaimableCount(data) else 0)
		self:Render()
	end)
end

return QuestController
