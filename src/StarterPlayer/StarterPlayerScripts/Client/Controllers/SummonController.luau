--[[
	SummonController
	Banner selection, rates/pool display, pity counters, x1 / x10 summons and the result reveal.
	The reveal is intentionally isolated in PlayReveal(results) so a cinematic animation (egg hatch,
	portal, etc.) can replace it later without touching the request flow.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Banners = require(Shared.Config.Banners)
local Units = require(Shared.Config.Units)
local Rarities = require(Shared.Config.Rarities)
local Traits = require(Shared.Config.Traits)
local Requirements = require(Shared.Modules.Requirements)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local SummonController = {
	Name = "SummonController",
	Priority = 22,
}

SummonController.SelectedBanner = nil :: string?
SummonController.Busy = false

function SummonController:Summon(count: number)
	if self.Busy or not self.SelectedBanner then
		return
	end
	self.Busy = true
	local response = State.Request("Summon", self.SelectedBanner, count)
	self.Busy = false
	if response.ok then
		self:PlayReveal(response.data.Results)
	end
end

-- Default reveal: cards pop in one by one, best rarity last gets a highlight.
function SummonController:PlayReveal(results)
	local overlay = self.Controllers.UIController.Overlay
	local panel = C.Frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 330), BackgroundColor3 = Theme.Colors.Background, ZIndex = 51 })
	C.Corner(panel)
	C.Stroke(panel, Theme.Colors.Accent, 2)
	C.Label(panel, "Summon Results", { Position = UDim2.fromOffset(16, 8), Font = Theme.Fonts.Title, TextSize = 22, ZIndex = 52, Size = UDim2.new(1, -32, 0, 30) })
	local grid = C.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 46), Size = UDim2.new(1, -32, 1, -100), ZIndex = 52 })
	C.Grid(grid, UDim2.fromOffset(110, 110), 8)
	for i, result in results do
		local def = Units.Get(result.UnitId)
		local trait = result.Trait and Traits.Get(result.Trait)
		local card = C.Frame(grid, { BackgroundColor3 = Theme.Colors.PanelLight, LayoutOrder = i, ZIndex = 53, BackgroundTransparency = 1 })
		C.Corner(card, UDim.new(0, 8))
		C.Stroke(card, Theme.Rarity(result.Rarity), if Rarities.AtLeast(result.Rarity, "Legendary") then 3 else 1.5)
		C.Label(card, if def then def.Name else result.UnitId, { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 40), TextWrapped = true, TextSize = 14, Font = Theme.Fonts.Bold, ZIndex = 54, TextYAlignment = Enum.TextYAlignment.Top })
		C.Label(card, result.Rarity, { Position = UDim2.new(0, 6, 1, -40), Size = UDim2.new(1, -12, 0, 16), TextSize = 13, Font = Theme.Fonts.Bold, TextColor3 = Theme.Rarity(result.Rarity), ZIndex = 54 })
		C.Label(card, if result.AutoDeleted then "Auto-sold" elseif trait then trait.Name else "", { Position = UDim2.new(0, 6, 1, -22), Size = UDim2.new(1, -12, 0, 16), TextSize = 12, TextColor3 = Theme.Colors.TextDim, ZIndex = 54 })
		TweenService:Create(card, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
		task.wait(if #results > 1 then 0.08 else 0.2)
	end
	C.Button(panel, "OK", function()
		panel:Destroy()
	end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(140, 36), ZIndex = 55, BackgroundColor3 = Theme.Colors.Accent, TextColor3 = Theme.Colors.Background })
	task.delay(12, function()
		if panel.Parent then
			panel:Destroy()
		end
	end)
end

function SummonController:RenderBannerList(data)
	C.Clear(self.BannerList)
	for i, banner in Banners.List do
		local ok = Requirements.Check(data, banner.Requirements)
		local button = C.Button(self.BannerList, banner.Name, function()
			self.SelectedBanner = banner.Id
			self:Render()
		end, { Size = UDim2.new(1, -6, 0, 40), TextSize = 13, TextWrapped = true, LayoutOrder = i })
		if not ok then
			button.TextColor3 = Theme.Colors.TextDim
		end
		if banner.Id == self.SelectedBanner then
			button.BackgroundColor3 = Theme.Colors.Accent
			button.TextColor3 = Theme.Colors.Background
		end
	end
end

function SummonController:RenderBanner(data)
	C.Clear(self.Info)
	local banner = self.SelectedBanner and Banners.Get(self.SelectedBanner)
	if not banner then
		return
	end
	local ok, reason = Requirements.Check(data, banner.Requirements)
	C.Label(self.Info, banner.Name, { Font = Theme.Fonts.Title, TextSize = 20, LayoutOrder = 1 })
	C.Label(self.Info, ("Cost: %s %s  •  x10: %s %s"):format(NumberFormat.Abbreviate(banner.CostSingle), banner.Currency, NumberFormat.Abbreviate(banner.CostMulti), banner.Currency), { TextSize = 14, TextColor3 = Theme.Currency(banner.Currency), Font = Theme.Fonts.Bold, LayoutOrder = 2 })
	if not ok then
		C.Label(self.Info, "Locked: " .. tostring(reason), { TextColor3 = Theme.Colors.Bad, Font = Theme.Fonts.Bold, LayoutOrder = 3 })
	end

	local rates = Banners.GetDisplayRates(banner.Id)
	local rarityIds = {}
	for rarity in rates do
		table.insert(rarityIds, rarity)
	end
	table.sort(rarityIds, function(a, b)
		return Rarities.GetOrder(a) < Rarities.GetOrder(b)
	end)
	for i, rarity in rarityIds do
		local names = {}
		for _, unitId in banner.Pool[rarity] or {} do
			local def = Units.Get(unitId)
			table.insert(names, if def then def.Name else unitId)
		end
		C.Label(self.Info, ("%s  %.2f%%  —  %s"):format(rarity, rates[rarity], table.concat(names, ", ")), { TextSize = 13, TextColor3 = Theme.Rarity(rarity), TextWrapped = true, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 10 + i })
	end

	local pity = (data.SummonPity or {})[banner.Id] or {}
	for i, rule in banner.Pity do
		C.Label(self.Info, ("Pity %s: %d / %d"):format(rule.Rarity, pity[rule.Rarity] or 0, rule.Threshold), { TextSize = 13, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 30 + i })
	end
	if banner.MultiGuarantee then
		C.Label(self.Info, "x10 guarantees at least one " .. banner.MultiGuarantee .. " or better.", { TextSize = 12, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 40 })
	end

	local buttons = C.Frame(self.Info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 44), LayoutOrder = 50 })
	C.List(buttons, Enum.FillDirection.Horizontal, 10)
	C.Button(buttons, "Summon x1", function()
		self:Summon(1)
	end, { Size = UDim2.fromOffset(150, 40), BackgroundColor3 = Theme.Colors.Info })
	C.Button(buttons, "Summon x10", function()
		self:Summon(10)
	end, { Size = UDim2.fromOffset(150, 40), BackgroundColor3 = Theme.Colors.Accent, TextColor3 = Theme.Colors.Background })
end

function SummonController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	self:RenderBannerList(data)
	self:RenderBanner(data)
end

function SummonController:Init(controllers)
	self.Controllers = controllers
	self.Window = controllers.UIController:CreateWindow("Summon", "Summon", UDim2.fromOffset(760, 480), function(bannerId)
		local data = State.Data
		if bannerId then
			self.SelectedBanner = bannerId
		elseif not self.SelectedBanner and data then
			-- Default to the banner of the current world.
			for _, banner in Banners.List do
				if banner.World == data.CurrentWorld then
					self.SelectedBanner = banner.Id
				end
			end
		end
		self:Render()
	end)
	local content = self.Window.Content
	self.BannerList = C.Scroll(content, { Size = UDim2.new(0.3, 0, 1, 0) })
	C.List(self.BannerList, Enum.FillDirection.Vertical, 6)
	self.Info = C.Scroll(content, { Position = UDim2.fromScale(0.32, 0), Size = UDim2.new(0.68, 0, 1, 0) })
	C.List(self.Info, Enum.FillDirection.Vertical, 6)
end

function SummonController:Start()
	State.Observe({ "SummonPity", "Currencies", "UnlockedWorlds" }, function()
		self:Render()
	end)
end

return SummonController
