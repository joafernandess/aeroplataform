--[[
	QuestController
	Main quest, daily quests (with reset countdown) and achievements, each with progress and Claim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Quests = require(Shared.Config.Quests)
local Achievements = require(Shared.Config.Achievements)
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

QuestController.Tab = "Quests"

local function questRow(parent, order: number, title: string, description: string, progress: number, target: number, rewards, canClaim: boolean, claimed: boolean, onClaim: () -> ())
	local row = C.Row(parent, { Size = UDim2.new(1, -8, 0, 92), LayoutOrder = order })
	C.Label(row, title, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 22), Font = Theme.Fonts.Bold, TextSize = 17 })
	C.Label(row, description, { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -170, 0, 18), TextSize = 13, TextColor3 = Theme.Colors.TextDim })
	C.Label(row, "Rewards: " .. Rewards.Describe(rewards), { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -170, 0, 18), TextSize = 12, TextColor3 = Theme.Colors.Accent })
	local bar = C.ProgressBar(row, Theme.Colors.Good, { Position = UDim2.fromOffset(12, 68), Size = UDim2.new(1, -170, 0, 14) })
	bar.Set(progress / target, ("%s / %s"):format(NumberFormat.Abbreviate(progress), NumberFormat.Abbreviate(target)))
	local button = C.Button(row, if claimed then "Claimed" elseif canClaim then "Claim" else "In progress", if canClaim and not claimed then onClaim else nil, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(140, 40),
		Kind = if canClaim and not claimed then "Primary" else "Dark",
	})
	button.AutoButtonColor = canClaim and not claimed
end

function QuestController:RenderQuests(data)
	local order = 0
	local main = data.Quests.MainCurrent
	local mainDef = main ~= "" and Quests.Get(main)
	C.Label(self.List, "Main Quest", { Font = Theme.Fonts.Title, TextSize = 18, LayoutOrder = 0 })
	if mainDef then
		local entry = data.Quests.Active[main] or { Progress = 0, Completed = false, Claimed = false }
		order += 1
		questRow(self.List, order, mainDef.Title, mainDef.Description, entry.Progress, mainDef.Target, mainDef.Rewards, entry.Completed, entry.Claimed, function()
			State.Request("ClaimQuest", main)
		end)
	else
		C.Label(self.List, "All main quests completed!", { TextColor3 = Theme.Colors.Good, LayoutOrder = 1 })
	end

	local resetIn = Clock.SecondsUntilNextDay(math.floor(workspace:GetServerTimeNow()), GameConfig.Quests.DailyResetOffsetSeconds)
	C.Label(self.List, "Daily Quests  (reset in " .. NumberFormat.Duration(resetIn) .. ")", { Font = Theme.Fonts.Title, TextSize = 18, LayoutOrder = 10 })
	local ids = {}
	for questId in data.Quests.Active do
		local def = Quests.Get(questId)
		if def and def.Category == "Daily" then
			table.insert(ids, questId)
		end
	end
	table.sort(ids)
	for i, questId in ids do
		local def = Quests.Get(questId)
		local entry = data.Quests.Active[questId]
		questRow(self.List, 10 + i, def.Title, def.Description, entry.Progress, def.Target, def.Rewards, entry.Completed, entry.Claimed, function()
			State.Request("ClaimQuest", questId)
		end)
	end
end

function QuestController:RenderAchievements(data)
	for i, def in Achievements.List do
		local claimedTier = data.Achievements[def.Id] or 0
		local tier = def.Tiers[claimedTier + 1]
		local value = if def.Stat == "Level" then data.Level else (data.Stats[def.Stat] or 0)
		if tier then
			questRow(self.List, i, ("%s (%d/%d)"):format(def.Name, claimedTier, #def.Tiers), def.Description, math.min(value, tier.Goal), tier.Goal, tier.Rewards, value >= tier.Goal, false, function()
				State.Request("ClaimAchievement", def.Id)
			end)
		else
			C.Label(self.List, def.Name .. " — all tiers completed!", { TextColor3 = Theme.Colors.Good, LayoutOrder = i, Font = Theme.Fonts.Bold })
		end
	end
end

function QuestController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	if self.Tab == "Quests" then
		self:RenderQuests(data)
	else
		self:RenderAchievements(data)
	end
end

function QuestController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Quests", "Quests", UDim2.fromOffset(680, 500), function()
		self:Render()
	end)
	local tabs = C.Tabs(self.Window.Content, { "Quests", "Achievements" }, function(name)
		self.Tab = name
		self:Render()
	end)
	self.List = C.Scroll(self.Window.Content, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40) })
	C.List(self.List, Enum.FillDirection.Vertical, 8)
	tabs.Select("Quests")
end

function QuestController:Start()
	State.Observe({ "Quests", "Achievements", "Stats", "Level" }, function()
		self:Render()
	end)
end

return QuestController
