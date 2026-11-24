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
local Features = require(Shared.Config.Features)
local GameConfig = require(Shared.Config.GameConfig)
local Units = require(Shared.Config.Units)
local Rarities = require(Shared.Config.Rarities)
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

-- Default reveal: rarity cards pop in one by one. Replace this function for a cinematic animation.
function SummonController:PlayReveal(results)
	local overlay = self.Controllers.UIController.Overlay
	local panel = C.Frame(overlay, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 360), BackgroundColor3 = Theme.Colors.Panel, ZIndex = 51 })
	self.Controllers.UIController:AddScaled(panel, "Window")
	C.Corner(panel, UDim.new(0, 16))
	C.Stroke(panel, Theme.Colors.Stroke, 3.5)
	local header = C.Frame(panel, { BackgroundColor3 = Theme.MenuColors.Summon, Size = UDim2.new(1, 0, 0, 50), ZIndex = 52 })
	C.Corner(header, UDim.new(0, 16))
	C.Gloss(header)
	local title = C.Label(header, "SUMMON RESULTS", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 28, ZIndex = 53 })
	C.Outline(title, 2.5)
	local grid = C.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.fromOffset(18, 62), Size = UDim2.new(1, -36, 1, -122), ZIndex = 52 })
	C.Grid(grid, UDim2.fromOffset(112, 112), 8)
	for i, result in results do
		local def = Units.Get(result.UnitId)
		local card = C.UnitCard(grid, {
			Name = if def then def.Name else result.UnitId,
			Rarity = result.Rarity,
			Level = 1,
			Stars = 0,
			Locked = false,
			Equipped = false,
			Trait = result.Trait,
			Badge = if result.AutoDeleted then "SOLD" else string.upper(result.Rarity),
		})
		card.LayoutOrder = i
		card.ZIndex = 53
		if Rarities.AtLeast(result.Rarity, "Legendary") then
			C.HighlightCard(card, "Selected")
		end
		if result.AutoDeleted then
			C.Frame(card, { BackgroundColor3 = Theme.Colors.Background, BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 6 })
		end
		TweenService:Create(card, TweenInfo.new(0.2), { BackgroundTransparency = 0 }):Play()
		task.wait(if #results > 1 then 0.08 else 0.2)
	end
	C.Button(panel, "OK", function()
		panel:Destroy()
	end, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(160, 42), TextSize = 22, ZIndex = 55, BackgroundColor3 = Theme.Colors.Good })
	task.delay(12, function()
		if panel.Parent then
			panel:Destroy()
		end
	end)
end

-- Banners the player can see: the base game only has the starting world's star.
local function visibleBanners()
	local list = {}
	for _, banner in Banners.List do
		if Features.MultipleWorlds or banner.World == GameConfig.Start.World then
			table.insert(list, banner)
		end
	end
	return list
end

local function price(amount: number, currency: string): string
	return NumberFormat.Abbreviate(amount) .. " " .. (Theme.Icons[currency] or currency)
end

function SummonController:RenderBannerList(data)
	C.Clear(self.BannerList)
	for i, banner in visibleBanners() do
		local ok = Requirements.Check(data, banner.Requirements)
		local button = C.Button(self.BannerList, banner.Name, function()
			self.SelectedBanner = banner.Id
			self:Render()
		end, { Size = UDim2.new(1, -6, 0, 40), TextSize = 13, TextWrapped = true, LayoutOrder = i })
		if not ok then
			button.TextColor3 = Theme.Colors.TextDim
		end
		if banner.Id == self.SelectedBanner then
			button.BackgroundColor3 = Theme.Colors.Cta
		end
	end
end

function SummonController:RenderBanner(data)
	C.Clear(self.Info)
	local banner = self.SelectedBanner and Banners.Get(self.SelectedBanner)
	if not banner then
		return
	end
	local multi = Banners.GetMultiCount(banner)
	local ok, reason = Requirements.Check(data, banner.Requirements)
	if #visibleBanners() > 1 then
		C.Title(self.Info, banner.Name, { TextSize = 24, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 })
	end
	C.Label(self.Info, "Possible fighters and their chances:", { TextSize = 14, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 2 })
	if not ok then
		C.Title(self.Info, "Locked: " .. tostring(reason), { TextSize = 16, TextColor3 = Theme.Colors.Bad, LayoutOrder = 3 }, 1.5)
	end

	-- Pool: one card per fighter with its individual chance (rarity rate / fighters in that rarity).
	local rates = Banners.GetDisplayRates(banner.Id)
	local entries = {}
	for rarity, percent in rates do
		local pool = banner.Pool[rarity] or {}
		for _, unitId in pool do
			table.insert(entries, { UnitId = unitId, Rarity = rarity, Chance = percent / math.max(#pool, 1) })
		end
	end
	table.sort(entries, function(a, b)
		return Rarities.GetOrder(a.Rarity) < Rarities.GetOrder(b.Rarity)
	end)
	local poolFrame = C.Frame(self.Info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 10 })
	C.Grid(poolFrame, UDim2.fromOffset(100, 112), 8)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 4), Parent = poolFrame })
	for i, entry in entries do
		local def = Units.Get(entry.UnitId)
		local chance = if entry.Chance >= 1 then ("%.0f%%"):format(entry.Chance) else ("%.2f%%"):format(entry.Chance)
		local card = C.UnitCard(poolFrame, {
			Name = if def then def.Name else entry.UnitId,
			Rarity = entry.Rarity,
			Level = 1,
			Stars = 0,
			Locked = false,
			Equipped = false,
			Badge = chance,
		})
		card.LayoutOrder = i
		card.AutoButtonColor = false
	end

	if Features.SummonPity then
		local pity = (data.SummonPity or {})[banner.Id] or {}
		for i, rule in banner.Pity do
			C.Label(self.Info, ("Pity %s: %d / %d"):format(rule.Rarity, pity[rule.Rarity] or 0, rule.Threshold), { TextSize = 13, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 30 + i })
		end
	end
	if banner.MultiGuarantee then
		C.Label(self.Info, ("x%d guarantees at least one %s or better."):format(multi, banner.MultiGuarantee), { TextSize = 12, TextColor3 = Theme.Colors.TextDim, LayoutOrder = 40 })
	end

	local buttons = C.Frame(self.Info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = 50 })
	C.List(buttons, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)
	C.Button(buttons, ("Open x1  •  %s"):format(price(banner.CostSingle, banner.Currency)), function()
		self:Summon(1)
	end, { Size = UDim2.fromOffset(230, 48), TextSize = 19, BackgroundColor3 = Theme.Colors.Info, LayoutOrder = 1 })
	C.Button(buttons, ("Open x%d  •  %s"):format(multi, price(banner.CostMulti, banner.Currency)), function()
		self:Summon(multi)
	end, { Size = UDim2.fromOffset(230, 48), TextSize = 19, BackgroundColor3 = Theme.Colors.Cta, LayoutOrder = 2 })

	-- Auto-sell toggles (server-side setting, applied while summoning).
	local toggles = C.Frame(self.Info, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 60 })
	C.List(toggles, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)
	for i, rarity in { "Common", "Rare" } do
		local key = "AutoDelete" .. rarity
		local on = data.Settings[key] == true
		C.Button(toggles, ("Auto-sell %s: %s"):format(rarity, if on then "ON" else "OFF"), function()
			State.Request("UpdateSetting", key, not on)
		end, { Size = UDim2.fromOffset(230, 34), TextSize = 15, LayoutOrder = i, BackgroundColor3 = if on then Theme.Colors.Good else Theme.Colors.Button })
	end
end

function SummonController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	-- With a single banner (base game) the list is hidden and the star takes the whole window.
	local single = #visibleBanners() <= 1
	self.BannerList.Visible = not single
	self.Info.Position = if single then UDim2.new() else UDim2.fromScale(0.32, 0)
	self.Info.Size = if single then UDim2.fromScale(1, 1) else UDim2.new(0.68, 0, 1, 0)
	if not single then
		self:RenderBannerList(data)
	end
	self:RenderBanner(data)
end

function SummonController:Init(controllers)
	self.Controllers = controllers
	-- The base game's single star gets a compact window; the multi-banner view needs the list column.
	local size = if #visibleBanners() <= 1 then UDim2.fromOffset(700, 380) else UDim2.fromOffset(760, 500)
	self.Window = controllers.UIController:CreateWindow("Summon", "Summon", size, function(bannerId)
		local data = State.Data
		if bannerId then
			self.SelectedBanner = bannerId
		elseif not self.SelectedBanner and data then
			-- Default to the banner of the current world.
			for _, banner in visibleBanners() do
				if banner.World == data.CurrentWorld then
					self.SelectedBanner = banner.Id
				end
			end
		end
		local banner = self.SelectedBanner and Banners.Get(self.SelectedBanner)
		self.Window.Title.Text = if banner then banner.Name else "Summon"
		self:Render()
	end)
	local content = self.Window.Content
	self.BannerList = C.Scroll(content, { Size = UDim2.new(0.3, 0, 1, 0) })
	C.List(self.BannerList, Enum.FillDirection.Vertical, 6)
	self.Info = C.Scroll(content, { Position = UDim2.fromScale(0.32, 0), Size = UDim2.new(0.68, 0, 1, 0) })
	C.List(self.Info, Enum.FillDirection.Vertical, 8)
end

function SummonController:Start()
	State.Observe({ "SummonPity", "Currencies", "UnlockedWorlds", "Settings" }, function()
		self:Render()
	end)
end

return SummonController
