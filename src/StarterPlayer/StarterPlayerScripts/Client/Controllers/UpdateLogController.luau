--[[
	UpdateLogController
	Top-right "UPDATE LOG" card (latest update's title) and the Update Log window.

	Content comes from Shared/Config/UpdateLog (newest entry first, each entry split in sections such as New features /
	Improvements / Bug fixes); nothing is hard-coded here. The card shows a
	cyan NEW tag until the player opens the window once for the latest entry; that is remembered on the server
	in Settings.LastSeenUpdate (UpdateSetting), so it survives rejoining.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local UpdateLog = require(ReplicatedStorage.Shared.Config.UpdateLog)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local UpdateLogController = {
	Name = "UpdateLogController",
	Priority = 30,
}

local CARD_W, CARD_H = 216, 62
local CHARS_PER_LINE = 62 -- rough wrap estimate for 16px body text at the window's width
local LINE_H = 21

local P = Theme.Colors

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

-- Height of a wrapped bullet line (estimate; the label wraps for real, this only sizes its row).
local function itemHeight(text: string): number
	local lines = math.max(1, math.ceil((utf8.len(text) or #text) / CHARS_PER_LINE))
	return lines * LINE_H + 4
end

function UpdateLogController:IsUnseen(): boolean
	local latest = UpdateLog.GetLatest()
	local data = State.Data
	if not latest or not data or self.SeenLocally == latest.Id then
		return false
	end
	return (data.Settings.LastSeenUpdate or "") ~= latest.Id
end

function UpdateLogController:RefreshCard()
	local latest = UpdateLog.GetLatest()
	self.CardTitle.Text = if latest then latest.Title else "No updates yet"
	self.NewTag.Visible = self:IsUnseen()
end

-- Marks the latest entry as read (optimistically hides NEW, then stores it on the server).
function UpdateLogController:MarkSeen()
	local latest = UpdateLog.GetLatest()
	if not latest or not self:IsUnseen() then
		return
	end
	self.SeenLocally = latest.Id
	self:RefreshCard()
	task.spawn(State.Request, "UpdateSetting", "LastSeenUpdate", latest.Id)
end

-- Window ---------------------------------------------------------------------------------------------------------

local SECTION_H = 30

function UpdateLogController:_entry(entry, order: number, latest: boolean)
	local height = 52
	for _, section in entry.Sections do
		height += SECTION_H
		for _, item in section.Items do
			height += itemHeight(item)
		end
	end
	local card = C.Row(self.List, { Name = entry.Id, Size = UDim2.new(1, -8, 0, height + 10), LayoutOrder = order })
	if latest then
		card:FindFirstChildOfClass("UIStroke").Color = P.Yellow
	end
	C.Title(card, entry.Title, { Name = "EntryTitle", Position = UDim2.fromOffset(16, 8), Size = UDim2.new(1, -200, 0, 30), TextSize = 24 }, 2.5)
	-- Right side: LATEST tag and/or the date.
	local tags = C.Frame(card, { BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(190, 26) })
	C.List(tags, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Right)
	if entry.Date then
		local date = C.Frame(tags, { Name = "Date", BackgroundColor3 = P.Bg, Size = UDim2.fromOffset(104, 26), LayoutOrder = 2 })
		C.Corner(date, UDim.new(0.5, 0))
		C.Stroke(date, P.Line, 1.5)
		C.Label(date, entry.Date, { Size = UDim2.fromScale(1, 1), TextSize = 14, TextColor3 = P.TextDim, TextXAlignment = Enum.TextXAlignment.Center })
	end
	if latest then
		local tag = C.Frame(tags, { Name = "Latest", BackgroundColor3 = P.Yellow, Size = UDim2.fromOffset(72, 26), LayoutOrder = 1 })
		C.Corner(tag, UDim.new(0.5, 0))
		C.Stroke(tag, P.Ink, 2)
		C.Title(tag, "LATEST", { Size = UDim2.fromScale(1, 1), TextSize = 14, TextColor3 = P.Ink, TextXAlignment = Enum.TextXAlignment.Center }, 0.01)
	end
	local y = 46
	local n = 0
	for _, section in entry.Sections do
		-- Section heading: gold caps ("NEW FEATURES", "IMPROVEMENTS", "BUG FIXES"...)
		C.Title(card, string.upper(section.Title), {
			Name = "Section",
			Position = UDim2.fromOffset(16, y + 4),
			Size = UDim2.new(1, -32, 0, 22),
			TextSize = 15,
			TextColor3 = P.Yellow,
		}, 1.5)
		y += SECTION_H
		for _, item in section.Items do
			n += 1
			local h = itemHeight(item)
			local dot = C.Frame(card, { Name = "Bullet", BackgroundColor3 = P.Yellow, Position = UDim2.fromOffset(22, y + 8), Size = UDim2.fromOffset(7, 7) })
			C.Corner(dot, UDim.new(0.5, 0))
			C.Label(card, item, {
				Name = "Item" .. n,
				Position = UDim2.fromOffset(38, y),
				Size = UDim2.new(1, -54, 0, h),
				TextSize = 16,
				TextColor3 = P.Ice,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
			})
			y += h
		end
	end
end

function UpdateLogController:Render()
	if not self.Window.Frame.Visible then
		return
	end
	C.Clear(self.List)
	if #UpdateLog.Entries == 0 then
		C.EmptyState(self.List, "update", "No updates yet", "Patch notes will show up here.")
		return
	end
	for i, entry in UpdateLog.Entries do
		self:_entry(entry, i, i == 1)
	end
end

-- Top-right card ---------------------------------------------------------------------------------------------------

function UpdateLogController:_buildCard(root: Instance)
	local ui = self.Controllers.UIController
	local holder = C.Frame(root, {
		Name = "UpdateLogCard",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 10),
		Size = UDim2.fromOffset(CARD_W, CARD_H + 6),
	})
	local card = C.Create("TextButton", {
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = P.White,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		ZIndex = 2,
		Parent = holder,
	})
	-- Same monochrome look as the side menu buttons; the bell is the only colour.
	local paint = C.MenuTile(card, Theme.Radius.Card, Theme.IconColors.update)
	local scale = C.Create("UIScale", { Name = "FX", Parent = card })
	local bell = Theme.IconColors.update
	C.Icon(card, "update", {
		Size = 44,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Color = bell,
		Accent = bell:Lerp(P.White, 0.55),
		ZIndex = 3,
	})

	C.Title(card, "UPDATE LOG", { Name = "Heading", Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -70, 0, 18), TextSize = 14, TextColor3 = bell }, 1.5)
	self.CardTitle = C.Title(card, "", {
		Name = "Latest",
		Position = UDim2.fromOffset(62, 26),
		Size = UDim2.new(1, -70, 0, 26),
		TextSize = 21,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, 2)

	local new = C.Frame(card, { Name = "NewTag", BackgroundColor3 = Theme.Colors.Alert, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 4, 0, 2), Size = UDim2.fromOffset(46, 22), ZIndex = 5, Visible = false })
	C.Corner(new, UDim.new(0.5, 0))
	C.Stroke(new, P.Ink, 2)
	C.Title(new, "NEW", { Size = UDim2.fromScale(1, 1), TextSize = 13, TextColor3 = P.White, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 6 }, 1.5)
	self.NewTag = new
	local newScale = C.Create("UIScale", { Parent = new })
	TweenService:Create(newScale, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.12 }):Play()
	C.ShineSweep(card, 4.5)

	local hovering = false
	card.MouseEnter:Connect(function()
		hovering = true
		paint("Hover")
		tween(scale, 0.12, { Scale = 1.04 })
	end)
	card.MouseLeave:Connect(function()
		hovering = false
		paint("Idle")
		tween(scale, 0.12, { Scale = 1 })
	end)
	card.MouseButton1Down:Connect(function()
		paint("Press")
		tween(scale, 0.06, { Scale = 0.95 })
	end)
	card.MouseButton1Up:Connect(function()
		paint(if hovering then "Hover" else "Idle")
		tween(scale, 0.14, { Scale = if hovering then 1.04 else 1 }, Enum.EasingStyle.Back)
	end)
	card.Activated:Connect(function()
		ui:Toggle("UpdateLog")
	end)
	self.Card = card
	self.CardHolder = holder
	local holderScale = ui:AddScaled(holder, "Hud")
	-- The right menu column stays below this card.
	ui:AvoidForNav("Right", function()
		return holder.Position.Y.Offset + (CARD_H + 6) * holderScale.Scale
	end)
end

-- Lifecycle --------------------------------------------------------------------------------------------------------

function UpdateLogController:Init(controllers)
	self.Controllers = controllers
	local ui = controllers.UIController
	self.Window = ui:CreateWindow("UpdateLog", "Update Log", UDim2.fromOffset(640, 460), function()
		self:Render()
		self:MarkSeen()
	end)
	self.List = C.Scroll(self.Window.Content)
	C.List(self.List, Enum.FillDirection.Vertical, 10)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = self.List })
	self:_buildCard(ui:GetRoot())
	self:RefreshCard()
end

function UpdateLogController:Start()
	State.Observe({ "Settings" }, function()
		self:RefreshCard()
	end)
end

return UpdateLogController
