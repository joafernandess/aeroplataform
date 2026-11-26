--[[
	TeamBarController
	Fighter slots: bottom-centre HUD strip with the equipped team, plus two nudges that keep the core loop moving.

	  slots           one card per equipped fighter (equip order): portrait on a vibrant rarity backdrop, level,
	                  rarity name, individual Power and (PC) the hotkey 1-8. Dashed empty slots fill up to the
	                  equip-slot count. Click a card -> select it and open Fighters with it; hotkey -> select it
	                  (press the same key again to open it). The selected slot gets a cyan outline.
	  action slot     the AUTO toggle (owned by HUDController) docks to the right of the bar.
	  better hint     pulsing "▲ Better fighter available — Equip Best" pill above the bar while an unequipped
	                  fighter has more Power than the weakest equipped one ("▲ Free team slot — Equip Best" while
	                  a slot is empty and a benched fighter could fill it). Tapping it sends EquipBest.
	  NEW badge       fighters obtained during this session (uids that appear after the first snapshot) are
	                  counted on the Fighters menu button (UIController:SetMenuBadge). Opening Fighters clears it.

	Layout: anchored bottom-centre, scaled with the other HUD blocks (UIController:AddScaled "Hud"). It sits
	above the level bar when Features.PlayerLevel is on and shifts right if a narrow screen would push it into
	the bottom-left menu. The AUTO button (right-centre) and the mobile jump button (bottom-right) stay clear.
]]

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Units = require(Shared.Config.Units)
local Features = require(Shared.Config.Features)
local Formulas = require(Shared.Modules.Formulas)
local UnitStats = require(Shared.Modules.UnitStats)
local NumberFormat = require(Shared.Modules.NumberFormat)

local Client = script.Parent.Parent
local C = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local State = require(Client.State)

local TeamBarController = {
	Name = "TeamBarController",
	Priority = 12,
}

local P = Theme.Colors

local CARD_W, CARD_H = 70, 86
local CARD_GAP = 6
local BAR_PAD = 6
local BAR_H = CARD_H + BAR_PAD * 2
local HINT_H = 38
local HINT_GAP = 10
local EDGE = 12 -- distance from the bottom of the screen (matches the menu and the level bar)
local LEVEL_BAR_H = 52 -- HUDController's level badge + XP bar (bottom-centre) when Features.PlayerLevel is on
local MENU_GAP = 8
local HINT_TEXT = {
	Better = "▲ Better fighter available — Equip Best",
	FreeSlot = "▲ Free team slot — Equip Best",
}
local HINT_W = { Better = 360, FreeSlot = 290 }

TeamBarController.KnownUids = nil :: { [string]: boolean }? -- every uid seen so far (nil until the first snapshot)
TeamBarController.NewUids = {} :: { [string]: boolean } -- obtained this session and not yet seen in Fighters
TeamBarController.HintVisible = false
TeamBarController.SelectedUid = nil :: string?
TeamBarController.Team = {} :: { any }

local ACTION_W = 84 -- docked AUTO button
local HOTKEYS = {
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
}

local function initials(name: string): string
	local letters = {}
	for word in string.gmatch(name, "%a+") do
		table.insert(letters, string.upper(string.sub(word, 1, 1)))
		if #letters == 2 then
			break
		end
	end
	return table.concat(letters)
end

local function powerOf(unit): number
	local stats = unit and UnitStats.Compute(unit)
	return if stats then stats.Power else 0
end

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

-- Slight grow on hover / sink on press (same feel as C.Button, without the 3D lip).
local function hoverable(button: GuiButton, scale: UIScale)
	button.MouseEnter:Connect(function()
		tween(scale, 0.08, { Scale = 1.06 })
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.08, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.08, { Scale = 1 })
	end)
end

-- Equipped team in equip order (uids that still exist). Slots come from the upgrade formula; taking the max with
-- `#team` keeps every member visible when a game-pass bonus (not visible to the client) adds slots.
local function teamOf(data)
	local team = {}
	for _, uid in data.EquippedUnits or {} do
		local unit = data.Inventory.Units[uid]
		local def = unit and Units.Get(unit.UnitId)
		if def then
			table.insert(team, { Uid = uid, Unit = unit, Def = def, Power = powerOf(unit) })
		end
	end
	local slots = math.max(Formulas.EquipSlots(data.Upgrades.EquipSlots or 0, 0), #team)
	return team, slots
end

--[[
	What "Equip Best" would improve, or nil:
	  "Better"    an unequipped fighter has more Power than the weakest equipped one
	  "FreeSlot"  a slot is empty and an unequipped fighter could fill it
]]
function TeamBarController.Suggestion(data): string?
	local team, slots = teamOf(data)
	local equipped, weakest = {}, math.huge
	for _, member in team do
		equipped[member.Uid] = true
		weakest = math.min(weakest, member.Power)
	end
	local freeSlot = #team < slots
	for uid, unit in data.Inventory.Units do
		if not equipped[uid] then
			if freeSlot then
				return "FreeSlot"
			elseif powerOf(unit) > weakest then
				return "Better"
			end
		end
	end
	return nil
end

-- Widgets (built locally from C.* primitives) -----------------------------------------------------------------

-- Fighter card: light-outlined dark tile, portrait on a vibrant rarity backdrop, level pill, hotkey (PC),
-- rarity name and the fighter's own Power.
function TeamBarController:_card(parent: Instance, member, order: number)
	local rarity = Theme.Rarity(member.Def.Rarity)
	local selected = member.Uid == self.SelectedUid
	local card = C.Create("TextButton", {
		Name = "FighterCard",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = P.White,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		LayoutOrder = order,
		Parent = parent,
	})
	card:SetAttribute("Uid", member.Uid)
	C.Corner(card, 12)
	C.Gradient(card, P.PanelLight, P.Bg)
	local stroke = C.Stroke(card, if selected then P.Cyan else P.White, if selected then 3.5 else 2)
	stroke.Transparency = if selected then 0 else 0.2
	local scale = C.Create("UIScale", { Parent = card, Scale = if selected then 1.06 else 1 })
	hoverable(card, scale)

	local portrait = C.Frame(card, { Name = "Portrait", BackgroundColor3 = P.White, Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 0, 46), ZIndex = 2 })
	C.Corner(portrait, 9)
	C.Gradient(portrait, rarity, Theme.Darken(rarity, 0.62))
	C.Stroke(portrait, P.Ink, 2)
	C.Title(portrait, initials(member.Def.Name), {
		Name = "Initials",
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 1, -8),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Display,
		TextSize = 24,
		ZIndex = 3,
	}, 2.5)
	local level = C.Frame(portrait, { Name = "Level", BackgroundColor3 = P.Ink, BackgroundTransparency = 0.2, Position = UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(34, 15), ZIndex = 4 })
	C.Corner(level, UDim.new(0.5, 0))
	C.Title(level, "Lv " .. tostring(member.Unit.Level or 1), { Size = UDim2.fromScale(1, 1), TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 }, 1.5)
	if UserInputService.KeyboardEnabled and HOTKEYS[order] then
		local key = C.Frame(portrait, { Name = "Hotkey", BackgroundColor3 = P.White, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2), Size = UDim2.fromOffset(15, 15), ZIndex = 4 })
		C.Corner(key, 4)
		C.Stroke(key, P.Ink, 1.5)
		C.Label(key, tostring(order), { Size = UDim2.fromScale(1, 1), TextSize = 11, Font = Theme.Fonts.Bold, TextColor3 = P.Ink, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 5 })
	end

	C.Title(card, string.upper(member.Def.Rarity), {
		Name = "Rarity",
		Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 0, 13),
		TextSize = 10,
		TextColor3 = rarity,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	}, 1.5)

	-- Power: icon + number, centred as a pair (widths estimated; no AutomaticSize needed).
	local value = NumberFormat.Abbreviate(member.Power, 1)
	local numberWidth = #value * 8 + 2
	local power = C.Frame(card, { Name = "Power", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 16), ZIndex = 3 })
	C.List(power, Enum.FillDirection.Horizontal, 2, Enum.HorizontalAlignment.Center)
	C.Icon(power, "power", { Size = 14, LayoutOrder = 1, ZIndex = 3 })
	C.Title(power, value, { Name = "Value", Font = Theme.Fonts.Number, Size = UDim2.fromOffset(numberWidth, 16), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 2, ZIndex = 3 }, 1.5)

	card.Activated:Connect(function()
		self:Select(member.Uid)
		self:OpenFighter(member.Uid)
	end)
	return card
end

-- Highlights a slot (hotkeys / clicks). Re-renders so the outline moves.
function TeamBarController:Select(uid: string?)
	if self.SelectedUid == uid then
		return
	end
	self.SelectedUid = uid
	self.Signature = nil
	if State.Data then
		self:Render(State.Data)
	end
end

-- Hotkey n: first press selects slot n, a second press opens that fighter.
function TeamBarController:Hotkey(index: number)
	local member = self.Team[index]
	if not member then
		return
	end
	if self.SelectedUid == member.Uid then
		self:OpenFighter(member.Uid)
	else
		self:Select(member.Uid)
	end
end

-- Empty slot: translucent tile with a dashed outline (short Frames; UIStroke has no dash style) and a "+".
function TeamBarController:_emptySlot(parent: Instance, order: number)
	local slot = C.Create("TextButton", {
		Name = "EmptySlot",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = P.Bg,
		BackgroundTransparency = 0.45,
		Size = UDim2.fromOffset(CARD_W, CARD_H),
		LayoutOrder = order,
		Parent = parent,
	})
	C.Corner(slot, 10)
	hoverable(slot, C.Create("UIScale", { Parent = slot }))
	local dash, gap, inset = 7, 5, 9
	-- `edge` is 0 (top/left) or 1 (bottom/right); dashes sit 2px inside that edge.
	local function line(horizontal: boolean, length: number, edge: number)
		local at = inset
		while at + dash <= length - inset + 0.5 do
			C.Frame(slot, {
				Name = "Dash",
				BackgroundColor3 = P.TextDim,
				BackgroundTransparency = 0.15,
				Position = if horizontal then UDim2.new(0, at, edge, -2 * edge) else UDim2.new(edge, -2 * edge, 0, at),
				Size = if horizontal then UDim2.fromOffset(dash, 2) else UDim2.fromOffset(2, dash),
				ZIndex = 2,
			})
			at += dash + gap
		end
	end
	line(true, CARD_W, 0)
	line(true, CARD_W, 1)
	line(false, CARD_H, 0)
	line(false, CARD_H, 1)
	C.Title(slot, Theme.Icons.Plus, { Size = UDim2.fromScale(1, 1), TextSize = 26, TextColor3 = P.TextDim, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, 2)
	slot.Activated:Connect(function()
		self:OpenFighter(nil)
	end)
	return slot
end

-- Actions ------------------------------------------------------------------------------------------------------

function TeamBarController:OpenFighter(uid: string?)
	local ui = self.Controllers.UIController
	ui:Open("Fighters")
	local inventory = self.Controllers.InventoryController
	if uid and inventory then
		inventory:Select(uid)
	end
end

function TeamBarController:EquipBest()
	State.Request("EquipBest")
end

-- Rendering ------------------------------------------------------------------------------------------------------

function TeamBarController:Render(data)
	local team, slots = teamOf(data)
	self.Team = team
	-- Rebuild only when something visible changed (Inventory updates on every unit XP tick).
	local parts = { tostring(slots), tostring(self.SelectedUid) }
	for _, member in team do
		table.insert(parts, ("%s:%s:%d:%d"):format(member.Uid, member.Def.Id, member.Unit.Level or 1, member.Power))
	end
	local signature = table.concat(parts, "|")
	if signature ~= self.Signature then
		self.Signature = signature
		C.Clear(self.Slots)
		for i, member in team do
			self:_card(self.Slots, member, i)
		end
		for i = #team + 1, slots do
			self:_emptySlot(self.Slots, i)
		end
		self.Bar.Size = UDim2.fromOffset(slots * CARD_W + math.max(slots - 1, 0) * CARD_GAP + BAR_PAD * 2, BAR_H)
	end
	local suggestion = TeamBarController.Suggestion(data)
	self.HintVisible = suggestion ~= nil
	self.Hint.Visible = self.HintVisible
	if suggestion then
		local width = HINT_W[suggestion]
		C.SetText(self.HintButton, HINT_TEXT[suggestion])
		self.Hint.Size = UDim2.fromOffset(width, HINT_H + 4)
		self.HintButton.Size = UDim2.fromOffset(width, HINT_H + 4)
	end
	-- The bar stays centred; the docked AUTO button sticks out on its right (width counted on both sides).
	self.ActionSlot.Position = UDim2.new(0.5, self.Bar.Size.X.Offset / 2 + 8, 1, 0)
	local width = math.max(self.Bar.Size.X.Offset + 2 * (ACTION_W + 8), if suggestion then HINT_W[suggestion] else 0)
	self.Container.Size = UDim2.fromOffset(width, BAR_H + HINT_GAP + HINT_H + 4)
	self:Layout()
end

-- Bottom offset (above the level bar when it is shown). On very narrow screens the bar is nudged so it never
-- slides under a side menu column (only when the two actually share the same height band).
function TeamBarController:Layout()
	local ui = self.Controllers.UIController
	local scale = self.Scale.Scale
	local bottom = EDGE
	if Features.PlayerLevel then
		bottom += LEVEL_BAR_H * scale + 8
	end
	local viewport = ui:GetViewportSize()
	local halfWidth = self.Container.Size.X.Offset * scale / 2
	local barTop = viewport.Y - bottom - BAR_H * scale
	local shift
	local function edges(column: GuiObject?): { Left: number, Right: number, Bottom: number }?
		if not column then
			return nil
		end
		local columnScale = column:FindFirstChildOfClass("UIScale")
		local s = if columnScale then columnScale.Scale else 1
		local width, height = column.Size.X.Offset * s, column.Size.Y.Offset * s
		local x = column.Position.X.Offset + column.Position.X.Scale * viewport.X - column.AnchorPoint.X * width
		return { Left = x, Right = x + width, Bottom = viewport.Y * column.Position.Y.Scale + height / 2 }
	end
	local left = viewport.X / 2 - halfWidth
	local right = viewport.X / 2 + halfWidth
	-- Allowed sideways range: right of the left column, left of the right column (when they reach the bar).
	local minShift, maxShift = -math.huge, math.huge
	local leftNav = edges(ui.LeftNav)
	if leftNav and leftNav.Bottom > barTop then
		minShift = leftNav.Right + MENU_GAP - left
	end
	local rightNav = edges(ui.RightNav)
	if rightNav and rightNav.Bottom > barTop then
		maxShift = rightNav.Left - MENU_GAP - right
	end
	if minShift <= maxShift then
		shift = math.clamp(0, minShift, maxShift)
	else
		shift = minShift -- no room for both: never cover the left column (main menus)
	end
	self.Container.Position = UDim2.new(0.5, shift, 1, -bottom)
end

-- NEW badge ------------------------------------------------------------------------------------------------------

function TeamBarController:TrackNew(data)
	local units = data.Inventory.Units
	local ui = self.Controllers.UIController
	if self.KnownUids == nil then
		-- First snapshot: everything owned before this session is "old".
		local known = {}
		for uid in units do
			known[uid] = true
		end
		self.KnownUids = known
		return
	end
	local known = self.KnownUids :: { [string]: boolean }
	local fightersOpen = ui:IsOpen("Fighters")
	for uid in units do
		if not known[uid] then
			known[uid] = true
			if not fightersOpen then
				self.NewUids[uid] = true
			end
		end
	end
	-- Sold / fused away before being seen: stop counting them.
	for uid in self.NewUids do
		if not units[uid] then
			self.NewUids[uid] = nil
		end
	end
	self:_publishBadge()
end

function TeamBarController:NewCount(): number
	local count = 0
	for _ in self.NewUids do
		count += 1
	end
	return count
end

function TeamBarController:ClearNew()
	self.NewUids = {}
	self:_publishBadge()
end

function TeamBarController:_publishBadge()
	self.Controllers.UIController:SetMenuBadge("Fighters", self:NewCount())
end

-- Lifecycle ------------------------------------------------------------------------------------------------------

function TeamBarController:Init(controllers)
	self.Controllers = controllers
	local ui = controllers.UIController
	local root = ui:GetRoot()

	local container = C.Frame(root, {
		Name = "TeamBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -EDGE),
		Size = UDim2.fromOffset(HINT_W.Better, BAR_H + HINT_GAP + HINT_H + 4),
	})
	self.Container = container

	local bar = C.Frame(container, {
		Name = "Bar",
		BackgroundColor3 = P.Panel,
		BackgroundTransparency = 0.25,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(CARD_W + BAR_PAD * 2, BAR_H),
	})
	C.Corner(bar, Theme.Radius.Header)
	local barStroke = C.Stroke(bar, P.White, 2)
	barStroke.Transparency = 0.6
	self.Bar = bar
	-- Dock for the AUTO toggle (HUDController parents it here in its Start).
	self.ActionSlot = C.Frame(container, {
		Name = "ActionSlot",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0.5, CARD_W, 1, 0),
		Size = UDim2.fromOffset(ACTION_W, BAR_H),
	})
	local slots = C.Frame(bar, { Name = "Slots", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
	C.Padding(slots, BAR_PAD)
	C.List(slots, Enum.FillDirection.Horizontal, CARD_GAP, Enum.HorizontalAlignment.Center)
	self.Slots = slots

	-- "Better fighter" pill: accent button inside a holder whose UIScale breathes (1 <-> 1.06).
	local hint = C.Frame(container, {
		Name = "BetterHint",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(BAR_H + HINT_GAP)),
		Size = UDim2.fromOffset(HINT_W.Better, HINT_H + 4),
		Visible = false,
	})
	self.Hint = hint
	self.HintButton = C.Button(hint, HINT_TEXT.Better, function()
		self:EquipBest()
	end, {
		Name = "EquipBestHint",
		Kind = "Accent",
		TextSize = 16,
		Radius = HINT_H // 2,
		Size = UDim2.fromOffset(HINT_W.Better, HINT_H + 4),
		Confirm = false,
	})
	local pulse = C.Create("UIScale", { Parent = hint })
	TweenService:Create(pulse, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()

	self.Scale = ui:AddScaled(container, "Hud")
	self.Scale:GetPropertyChangedSignal("Scale"):Connect(function()
		self:Layout()
	end)
end

function TeamBarController:Start()
	local ui = self.Controllers.UIController
	State.Observe({ "EquippedUnits", "Inventory", "Upgrades" }, function(data)
		self:TrackNew(data)
		self:Render(data)
	end)
	ui.WindowChanged:Connect(function(name)
		if name == "Fighters" then
			self:ClearNew()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local index = table.find(HOTKEYS, input.KeyCode)
		if index then
			self:Hotkey(index)
		end
	end)
end

return TeamBarController
