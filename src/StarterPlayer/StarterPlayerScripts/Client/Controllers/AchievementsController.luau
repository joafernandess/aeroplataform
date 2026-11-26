--[[
	AchievementsController
	"Achievements" window: every achievement of Config/Achievements with its current tier, progress towards the
	next goal and Claim (ClaimAchievement, server-validated). Completed achievements show all tiers done.
	The Achievements menu button shows a badge with the number of tiers ready to claim.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Features = require(Shared.Config.Features)
local Achievements = require(Shared.Config.Achievements)
local Rewards = require(Shared.Modules.Rewards)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local AchievementsController = {
	Name = "AchievementsController",
	Priority = 35,
}

local P = Theme.Colors

-- Current value of the stat an achievement tracks.
local function valueOf(data, def): number
	if def.Stat == "Level" then
		return data.Level
	end
	return data.Stats[def.Stat] or 0
end

-- { Def, ClaimedTier, Tier (next, or nil when done), Value, CanClaim } for each achievement.
function AchievementsController.Entries(data)
	local list = {}
	for _, def in Achievements.List do
		local claimed = data.Achievements[def.Id] or 0
		local tier = def.Tiers[claimed + 1]
		local value = valueOf(data, def)
		table.insert(list, { Def = def, ClaimedTier = claimed, Tier = tier, Value = value, CanClaim = tier ~= nil and value >= tier.Goal })
	end
	return list
end

function AchievementsController.ClaimableCount(data): number
	local count = 0
	for _, entry in AchievementsController.Entries(data) do
		if entry.CanClaim then
			count += 1
		end
	end
	return count
end

function AchievementsController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	if not Features.Achievements then
		C.EmptyState(self.List, "achievements", "Achievements are not available yet", "Achievements will be listed here once they are added to the game.")
		return
	end
	local entries = AchievementsController.Entries(data)
	local done, total = 0, 0
	for _, entry in entries do
		done += entry.ClaimedTier
		total += #entry.Def.Tiers
	end
	self.Summary.Set(if total > 0 then done / total else 0, ("%d / %d tiers completed"):format(done, total))
	for i, entry in entries do
		local def = entry.Def
		local tierCount = #def.Tiers
		if entry.Tier then
			C.ClaimRow(self.List, {
				Name = def.Id,
				Order = i,
				Title = ("%s  (%d/%d)"):format(def.Name, entry.ClaimedTier, tierCount),
				Description = def.Description,
				Rewards = Rewards.Describe(entry.Tier.Rewards),
				Progress = entry.Value,
				Target = entry.Tier.Goal,
				ProgressText = ("%s / %s"):format(NumberFormat.Abbreviate(math.min(entry.Value, entry.Tier.Goal)), NumberFormat.Abbreviate(entry.Tier.Goal)),
				CanClaim = entry.CanClaim,
				Claimed = false,
			}, function()
				State.Request("ClaimAchievement", def.Id)
			end)
		else
			local row = C.Row(self.List, { Name = def.Id, Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i })
			C.Icon(row, "achievements", { Size = 30, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Color = P.Cyan })
			C.Title(row, def.Name, { Position = UDim2.fromOffset(52, 0), Size = UDim2.new(1, -220, 1, 0), TextSize = 18 }, 2)
			C.Title(row, ("ALL %d TIERS DONE"):format(tierCount), {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -16, 0.5, 0),
				Size = UDim2.fromOffset(170, 24),
				TextSize = 15,
				TextColor3 = P.Cyan,
				TextXAlignment = Enum.TextXAlignment.Right,
			}, 2)
		end
	end
end

function AchievementsController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Achievements", "Achievements", UDim2.fromOffset(680, 520), function()
		self:Render()
	end)
	local content = self.Window.Content
	self.Summary = C.ProgressBar(content, nil, { Name = "Summary", Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 24) })
	self.List = C.Scroll(content, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40) })
	C.List(self.List, Enum.FillDirection.Vertical, 8)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 4), Parent = self.List })
end

function AchievementsController:Start()
	State.Observe({ "Achievements", "Stats", "Level" }, function(data)
		self.Controllers.UIController:SetMenuBadge("Achievements", if Features.Achievements then AchievementsController.ClaimableCount(data) else 0)
		self:Render()
	end)
end

return AchievementsController
