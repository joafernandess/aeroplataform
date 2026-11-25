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
	self.LastCount = count
	local response = State.Request("Summon", self.SelectedBanner, count)
	self.Busy = false
	if response.ok then
		self:PlayReveal(response.data.Results)
	end
end

-- Default reveal: speed-line burst behind a row of cards popping in one by one.
-- Replace this function for a cinematic animation; the request flow stays the same.
function SummonController:PlayReveal(results)
	local ui = self.Controllers.UIController
	local P = Theme.Colors
	local overlay = ui.Overlay
	local reveal = C.Frame(overlay, { Name = "Reveal", BackgroundColor3 = P.Ink, BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), ZIndex = 50 })
	-- Burst of speed-lines radiating from the centre.
	for k = 0, 15 do
		C.Frame(reveal, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(4, 900),
			Rotation = k * 22.5,
			BackgroundColor3 = P.White,
			BackgroundTransparency = 0.86,
			ZIndex = 51,
		})
	end
	local panel = C.Frame(reveal, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(760, 420), ZIndex = 52 })
	ui:AddScaled(panel, "Window")
	local title = C.Label(panel, "NEW FIGHTERS!", {
		Size = UDim2.new(1, 0, 0, 56),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Display,
		TextSize = 44,
		ZIndex = 53,
	})
	C.Outline(title, 3)
	local many = #results > 5
	local row = C.Frame(panel, { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, if many then 320 else 160), ZIndex = 53 })
	if many then
		C.Grid(row, UDim2.fromOffset(120, 150), 12)
	else
		C.List(row, Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center)
	end
	for i, result in results do
		local def = Units.Get(result.UnitId)
		local holder = C.Frame(row, { BackgroundTransparency = 1, Size = UDim2.fromOffset(120, 150), LayoutOrder = i, ZIndex = 54 })
		local card = C.UnitCard(holder, {
			Name = if def then def.Name else result.UnitId,
			Rarity = result.Rarity,
			Level = 1,
			Stars = 0,
			Locked = false,
			Equipped = false,
			New = not result.AutoDeleted,
			HideLevel = true,
			Footer = string.upper(result.Rarity),
			FooterColor = Theme.Rarity(result.Rarity),
			FooterFont = Theme.Fonts.Display,
		})
		card.Size = UDim2.fromScale(1, 1)
		if Rarities.AtLeast(result.Rarity, "Legendary") then
			C.HighlightCard(card, "Selected")
		end
		if result.AutoDeleted then
			local dim = C.Frame(card, { BackgroundColor3 = P.Ink, BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
			C.Corner(dim, Theme.Radius.Card)
			local ribbon = C.Frame(card, {
				BackgroundColor3 = P.Ink,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.42),
				Size = UDim2.new(1, 16, 0, 26),
				Rotation = -12,
				ZIndex = 10,
			})
			C.Stroke(ribbon, P.White, 2)
			C.Title(ribbon, "SOLD", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16, ZIndex = 11 }, 2)
		end
		local scale = card:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.2
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = if Rarities.AtLeast(result.Rarity, "Legendary") then 1.04 else 1 }):Play()
		end
		task.wait(if #results > 1 then 0.12 else 0.2)
	end
	local buttons = C.Frame(panel, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 0, 56), ZIndex = 55 })
	C.List(buttons, Enum.FillDirection.Horizontal, 16, Enum.HorizontalAlignment.Center)
	C.Button(buttons, "OK", function()
		reveal:Destroy()
	end, { Kind = "Secondary", Size = UDim2.fromOffset(170, 52), TextSize = 22, LayoutOrder = 1 })
	C.Button(buttons, "OPEN AGAIN", function()
		reveal:Destroy()
		self:Summon(self.LastCount or 1)
	end, { Kind = "Primary", Size = UDim2.fromOffset(210, 52), TextSize = 22, LayoutOrder = 2 })
	task.delay(15, function()
		if reveal.Parent then
			reveal:Destroy()
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
		end, { Kind = if banner.Id == self.SelectedBanner then "Primary" else "Dark", Size = UDim2.new(1, -8, 0, 48), TextSize = 15, LayoutOrder = i })
		C.SetDisabled(button, not ok and banner.Id ~= self.SelectedBanner)
		C.SetSelected(button, banner.Id == self.SelectedBanner)
	end
end

function SummonController:RenderBanner(data)
	C.Clear(self.Pool)
	C.Clear(self.Actions)
	local banner = self.SelectedBanner and Banners.Get(self.SelectedBanner)
	if not banner then
		return
	end
	local P = Theme.Colors
	local multi = Banners.GetMultiCount(banner)
	local ok, reason = Requirements.Check(data, banner.Requirements)

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
	for i, entry in entries do
		local def = Units.Get(entry.UnitId)
		local chance = if entry.Chance >= 1 then ("%.0f%%"):format(entry.Chance) else ("%.2f%%"):format(entry.Chance)
		local autoSold = data.Settings["AutoDelete" .. entry.Rarity] == true
		local card = C.UnitCard(self.Pool, {
			Name = if def then def.Name else entry.UnitId,
			Rarity = entry.Rarity,
			Level = 1,
			Stars = 0,
			Locked = false,
			Equipped = false,
			HideLevel = true,
			Footer = chance,
		})
		card.LayoutOrder = i
		if autoSold then
			local dim = C.Frame(card, { BackgroundColor3 = P.Ink, BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), ZIndex = 9 })
			C.Corner(dim, Theme.Radius.Card)
			local tag = C.Frame(card, { BackgroundColor3 = P.Ink, Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(46, 18), ZIndex = 10 })
			C.Corner(tag, UDim.new(0.5, 0))
			C.Stroke(tag, P.White, 2)
			C.Label(tag, "AUTO", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, Font = Theme.Fonts.Bold, ZIndex = 11 })
		end
	end

	-- Actions column
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	-- With a single banner its name is already the window title.
	if #visibleBanners() > 1 then
		C.Title(self.Actions, banner.Name, { Font = Theme.Fonts.Display, TextSize = 28, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = nextOrder() }, 3)
	end
	C.Label(self.Actions, "Spend the Yen your enemies drop to recruit new fighters.", {
		TextSize = 15,
		TextWrapped = true,
		TextColor3 = P.TextDim,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = nextOrder(),
	})
	if not ok then
		C.Title(self.Actions, "Locked: " .. tostring(reason), { TextSize = 16, TextColor3 = P.Ice, LayoutOrder = nextOrder() }, 2)
	end
	local balance = (data.Currencies or {})[banner.Currency] or 0
	for _, option in { { Count = 1, Cost = banner.CostSingle, Kind = "Secondary" }, { Count = multi, Cost = banner.CostMulti, Kind = "Primary" } } do
		local button = C.Button(self.Actions, ("OPEN x%d"):format(option.Count), function()
			self:Summon(option.Count)
		end, {
			Kind = option.Kind,
			Size = UDim2.new(1, 0, 0, 64),
			TextSize = 24,
			Subtext = price(option.Cost, banner.Currency),
			LayoutOrder = nextOrder(),
		})
		local short = option.Cost - balance
		C.SetDisabled(button, not ok or short > 0)
		if ok and short > 0 then
			C.Label(self.Actions, "Need " .. price(short, banner.Currency) .. " more", {
				TextSize = 14,
				TextColor3 = P.TextDim,
				TextXAlignment = Enum.TextXAlignment.Center,
				Size = UDim2.new(1, 0, 0, 18),
				LayoutOrder = nextOrder(),
			})
		end
	end

	if Features.SummonPity then
		local pity = (data.SummonPity or {})[banner.Id] or {}
		for _, rule in banner.Pity do
			C.Label(self.Actions, ("Pity %s: %d / %d"):format(rule.Rarity, pity[rule.Rarity] or 0, rule.Threshold), { TextSize = 14, TextColor3 = P.TextDim, LayoutOrder = nextOrder() })
		end
	end
	if banner.MultiGuarantee then
		C.Label(self.Actions, ("x%d guarantees at least one %s or better."):format(multi, banner.MultiGuarantee), {
			TextSize = 14,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 34),
			TextColor3 = P.TextDim,
			LayoutOrder = nextOrder(),
		})
	end

	-- Auto-sell chips (server-side settings, applied while summoning).
	C.Title(self.Actions, "Auto-sell", { TextSize = 17, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder() }, 2)
	for _, rarity in { "Common", "Rare" } do
		local key = "AutoDelete" .. rarity
		local on = data.Settings[key] == true
		local chip = C.Create("TextButton", {
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = P.PanelAlt,
			Size = UDim2.fromOffset(200, 36),
			LayoutOrder = nextOrder(),
			Parent = self.Actions,
		})
		C.Corner(chip, UDim.new(0.5, 0))
		C.Stroke(chip, P.Ink, 2.5)
		local box = C.Frame(chip, { BackgroundColor3 = if on then P.Blue500 else P.Panel, Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(26, 26) })
		C.Corner(box, 7)
		C.Stroke(box, P.Ink, 2.5)
		if on then
			C.Title(box, Theme.Icons.Equipped, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 16 }, 1.5)
		end
		local dot = C.Frame(chip, { BackgroundColor3 = Theme.Rarity(rarity), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 42, 0.5, 0), Size = UDim2.fromOffset(12, 12) })
		C.Corner(dot, UDim.new(0.5, 0))
		C.Title(chip, rarity, { Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -66, 1, 0), TextSize = 16 }, 2)
		chip.Activated:Connect(function()
			State.Request("UpdateSetting", key, not on)
		end)
	end
end

function SummonController:Render()
	local data = State.Data
	if not data or not self.Window.Frame.Visible then
		return
	end
	-- Single banner (base game): pool | actions. Several banners: list | pool | actions.
	local single = #visibleBanners() <= 1
	self.BannerList.Visible = not single
	if single then
		self.Pool.Position, self.Pool.Size = UDim2.new(), UDim2.new(0.6, 0, 1, 0)
		self.Actions.Position, self.Actions.Size = UDim2.fromScale(0.62, 0), UDim2.new(0.38, 0, 1, 0)
	else
		self.Pool.Position, self.Pool.Size = UDim2.fromScale(0.24, 0), UDim2.new(0.44, 0, 1, 0)
		self.Actions.Position, self.Actions.Size = UDim2.fromScale(0.7, 0), UDim2.new(0.3, 0, 1, 0)
		self:RenderBannerList(data)
	end
	self:RenderBanner(data)
end

function SummonController:Init(controllers)
	self.Controllers = controllers
	local single = #visibleBanners() <= 1
	local size = if single then UDim2.fromOffset(860, 450) else UDim2.fromOffset(940, 560)
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
	self.BannerList = C.Scroll(content, { Size = UDim2.new(0.22, 0, 1, 0) })
	C.List(self.BannerList, Enum.FillDirection.Vertical, 8)
	self.Pool = C.Scroll(content)
	C.Grid(self.Pool, UDim2.fromOffset(112, 140), 10)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), Parent = self.Pool })
	self.Actions = C.Frame(content, { BackgroundTransparency = 1 })
	C.List(self.Actions, Enum.FillDirection.Vertical, 8)
end

function SummonController:Start()
	State.Observe({ "SummonPity", "Currencies", "UnlockedWorlds", "Settings" }, function()
		self:Render()
	end)
end

return SummonController
