--[[
	Cards
	Reusable pieces of the collection-style windows (Upgrades, Fighter Index), black and yellow like the windows:
	  Cards.UpgradeCard(parent, info, onClick)       milestone card: icon, name, progress pill, state look
	  Cards.UpgradeDetailsPanel(parent)              right panel: name, category, bonus, requirement, bar, state
	  Cards.FighterIndexCard(parent, info, onClick)  fighter card: 3D thumbnail (or dark silhouette) + rarity bar
	  Cards.IndexWorldPanel(parent, onWorld)         right panel: world banners ("???" for unknown ones) + info box
	  Cards.LabeledBar(parent, props)                wide progress bar with a label on the left and a count on the right
	Everything shown comes from the caller (config / player data): no fixed texts or values here.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local C = require(script.Parent.Components)
local FighterModel = require(script.Parent.FighterModel)

local Cards = {}

local P = Theme.Colors

local function tween(instance: Instance, seconds: number, goals: { [string]: any }, style: Enum.EasingStyle?)
	TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

-- Hover / press "juice" on a card (own UIScale).
local function hoverable(button: GuiButton)
	local scale = C.Create("UIScale", { Name = "Hover", Parent = button })
	button.MouseEnter:Connect(function()
		tween(scale, 0.12, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.12, { Scale = 1 })
	end)
	button.MouseButton1Down:Connect(function()
		tween(scale, 0.06, { Scale = 0.95 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(scale, 0.12, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	return scale
end

-- Faint diagonal texture inside a card (clipped).
local function texture(card: Instance, z: number)
	local clip = C.Frame(card, { Name = "Texture", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ClipsDescendants = true, ZIndex = z })
	for k = 0, 9 do
		C.Frame(clip, {
			BackgroundColor3 = P.White,
			BackgroundTransparency = 0.95,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, -20 + k * 22, 0.5, 0),
			Size = UDim2.new(0, 7, 1.8, 0),
			Rotation = 35,
			ZIndex = z,
		})
	end
end

-- Pops a card (feedback when it completes / is discovered).
function Cards.Pop(card: Instance)
	local scale = card:FindFirstChild("Hover")
	if scale then
		scale.Scale = 1.18
		tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	end
end

-- Upgrades ---------------------------------------------------------------------------------------------------------

local STATE_TEXT = { Locked = "LOCKED", InProgress = "IN PROGRESS", Claimable = "READY TO CLAIM", Completed = "COMPLETED" }
Cards.StateText = STATE_TEXT

--[[
	info = { Id, Name, Icon, Color, State ("Locked" | "InProgress" | "Claimable" | "Completed"), ProgressText,
	         Selected }
]]
function Cards.UpgradeCard(parent: Instance, info, onClick: (() -> ())?)
	local state = info.State
	local color = info.Color
	local locked = state == "Locked"
	local card = C.Create("TextButton", { Name = info.Id, Text = "", AutoButtonColor = false, BackgroundColor3 = P.White, Parent = parent })
	C.Corner(card, 6)
	C.Gradient(card, if locked then P.Panel else P.PanelAlt, P.Bg)
	local border = if info.Selected then P.White
		elseif state == "Completed" then color
		elseif state == "Claimable" then P.Yellow
		elseif locked then P.Line
		else color:Lerp(P.Ink, 0.35)
	C.Stroke(card, border, if info.Selected or state == "Claimable" then 3.5 else 2.5)
	texture(card, card.ZIndex)
	C.Icon(card, info.Icon, {
		Name = "Icon",
		Size = 66,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 52),
		Color = if locked then P.TextMuted else color,
		Accent = if locked then P.Line else color:Lerp(P.White, 0.55),
		Tint = locked, -- uploaded PNG icons keep their colours; greyed out while locked
		ZIndex = 3,
	})
	C.Title(card, info.Name, {
		Name = "UpgradeName",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(1, -8, 0, 28),
		TextSize = 22,
		TextColor3 = if locked then P.TextMuted else color,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	}, 2.5)
	-- progress pill
	local pill = C.Frame(card, {
		Name = "Progress",
		BackgroundColor3 = if state == "Completed" then color else P.Bg,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -7),
		Size = UDim2.new(1, -16, 0, 24),
		ZIndex = 3,
	})
	C.Corner(pill, UDim.new(0.5, 0))
	C.Stroke(pill, P.Ink, 2)
	C.Title(pill, if state == "Completed" then "COMPLETED" else info.ProgressText, {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		TextSize = 14,
		TextColor3 = if state == "Completed" then P.Ink else P.White,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	}, if state == "Completed" then 0.01 else 1.5)
	if locked then
		C.LockBadge(card, UDim2.fromOffset(8, 8), 6)
	elseif state == "Claimable" then
		local tag = C.Frame(card, { Name = "ClaimTag", BackgroundColor3 = P.Alert, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -6), Size = UDim2.fromOffset(62, 22), ZIndex = 6 })
		C.Corner(tag, UDim.new(0.5, 0))
		C.Stroke(tag, P.Ink, 2)
		C.Title(tag, "CLAIM!", { Size = UDim2.fromScale(1, 1), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 7 }, 1.5)
		local pulse = C.Create("UIScale", { Parent = tag })
		TweenService:Create(pulse, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 }):Play()
	elseif state == "Completed" then
		local check = C.Frame(card, { Name = "Done", BackgroundColor3 = color, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(24, 24), ZIndex = 6 })
		C.Corner(check, UDim.new(0.5, 0))
		C.Stroke(check, P.Ink, 2)
		C.Icon(check, "check", { Size = 16, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), ZIndex = 7 })
	end
	hoverable(card)
	if onClick then
		card.Activated:Connect(onClick)
	end
	return card
end

--[[
	Right-hand details of the selected milestone. Returns api.Show(info) with
	info = { Name, Category, Bonus, Color, Requirement, Fraction, ProgressText, State, StateNote?, Total?, OnClaim? }
]]
function Cards.UpgradeDetailsPanel(parent: Instance)
	local panel = C.Frame(parent, { Name = "Details", BackgroundColor3 = P.Panel, ZIndex = 2 })
	C.Corner(panel, 6)
	C.Stroke(panel, P.Yellow, 3)
	local name = C.Title(panel, "", { Name = "DetailName", Position = UDim2.fromOffset(18, 14), Size = UDim2.new(1, -36, 0, 40), TextSize = 34, ZIndex = 3 }, 2.5)
	local category = C.Label(panel, "", { Name = "Category", Position = UDim2.fromOffset(18, 56), Size = UDim2.new(1, -36, 0, 20), TextSize = 15, TextColor3 = P.TextDim, Font = Theme.Fonts.Bold, ZIndex = 3 })
	local bonus = C.Title(panel, "", { Name = "Bonus", Position = UDim2.fromOffset(18, 92), Size = UDim2.new(1, -36, 0, 44), TextSize = 36, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, 2.5)
	C.Frame(panel, { Name = "Divider", BackgroundColor3 = P.Line, Position = UDim2.new(0, 18, 0, 148), Size = UDim2.new(1, -36, 0, 2), ZIndex = 3 })
	local requirement = C.Title(panel, "", {
		Name = "Requirement",
		Position = UDim2.fromOffset(18, 162),
		Size = UDim2.new(1, -36, 0, 58),
		TextSize = 19,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	}, 2)
	local bar = C.ProgressBar(panel, nil, { Name = "Bar", Position = UDim2.fromOffset(18, 228), Size = UDim2.new(1, -36, 0, 26), ZIndex = 3 })
	local stateLabel = C.Title(panel, "", { Name = "State", Position = UDim2.fromOffset(18, 264), Size = UDim2.new(1, -36, 0, 24), TextSize = 18, TextColor3 = P.TextDim, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 }, 1.5)
	local note = C.Label(panel, "", { Name = "Note", Position = UDim2.fromOffset(18, 288), Size = UDim2.new(1, -36, 0, 20), TextSize = 14, TextColor3 = P.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local total = C.Label(panel, "", { Name = "Total", Position = UDim2.fromOffset(18, 318), Size = UDim2.new(1, -36, 0, 20), TextSize = 15, TextColor3 = P.TextDim, Font = Theme.Fonts.Bold, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })
	local onClaim = nil
	local claim = C.Button(panel, "CLAIM", function()
		if onClaim then
			onClaim()
		end
	end, { Name = "Claim", Kind = "Gold", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(1, -36, 0, 50), TextSize = 22, Visible = false, Confirm = false, ZIndex = 4 })
	local api = { Frame = panel, ClaimButton = claim }
	function api.Show(info)
		name.Text = info.Name
		category.Text = string.upper(info.Category)
		bonus.Text = info.Bonus
		bonus.TextColor3 = info.Color
		requirement.Text = info.Requirement
		bar.Set(info.Fraction, info.ProgressText)
		stateLabel.Text = STATE_TEXT[info.State] or info.State
		stateLabel.TextColor3 = if info.State == "Completed" then info.Color elseif info.State == "Claimable" then P.Yellow else P.TextDim
		note.Text = info.StateNote or ""
		total.Text = info.Total or ""
		onClaim = info.OnClaim
		claim.Visible = info.State == "Claimable" and onClaim ~= nil
	end
	return api
end

-- Fighter Index ------------------------------------------------------------------------------------------------------

-- 3D bust of the fighter in a ViewportFrame (dark silhouette when not discovered). nil if it can't be built.
function Cards.Thumbnail(parent: Instance, def, silhouette: boolean): ViewportFrame?
	local ok, viewport = pcall(function()
		local frame = C.Create("ViewportFrame", {
			Name = "Thumbnail",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Ambient = Color3.fromRGB(170, 170, 180),
			LightColor = Color3.fromRGB(255, 255, 255),
			LightDirection = Vector3.new(-1, -1, 1),
			ImageColor3 = if silhouette then Color3.fromRGB(58, 59, 66) else Color3.new(1, 1, 1),
			ZIndex = (parent :: any).ZIndex + 1,
			Parent = parent,
		})
		local model = FighterModel.Build(def, 1)
		model.Parent = frame
		local camera = C.Create("Camera", {
			FieldOfView = 32,
			CFrame = CFrame.lookAt(Vector3.new(0, 1.55, -7.2), Vector3.new(0, 1.05, 0)),
			Parent = frame,
		})
		frame.CurrentCamera = camera
		return frame
	end)
	return if ok then viewport else nil
end

-- Bottom rarity bar colour: solid or the rarity's multi-colour gradient (Mythical rainbow).
local function rarityFill(frame: GuiObject, rarity: string, dim: boolean)
	local gradient = Theme.RarityGradient(rarity)
	if gradient then
		frame.BackgroundColor3 = if dim then Color3.fromRGB(150, 150, 150) else P.White
		C.Create("UIGradient", { Color = gradient, Parent = frame })
	else
		frame.BackgroundColor3 = if dim then Theme.Darken(Theme.Rarity(rarity), 0.25) else Theme.Rarity(rarity)
	end
end

--[[
	info = { Def, Discovered, Selected, Name? }
	Discovered: 3D bust, name, bright rarity border.  Not discovered: dark silhouette, "???", rarity colour kept.
]]
function Cards.FighterIndexCard(parent: Instance, info, onClick: (() -> ())?)
	local def = info.Def
	local rarityColor = Theme.Rarity(def.Rarity)
	local card = C.Create("TextButton", { Name = if info.Discovered then def.Id else "Hidden_" .. def.Rarity, Text = "", AutoButtonColor = false, BackgroundColor3 = P.White, Parent = parent })
	C.Corner(card, 6)
	C.Gradient(card, P.PanelAlt, P.Ink)
	C.Stroke(card, if info.Selected then P.White elseif info.Discovered then rarityColor else Theme.Darken(rarityColor, 0.45), if info.Selected then 3.5 else 3)
	local well = C.Frame(card, { Name = "Image", BackgroundColor3 = P.White, Position = UDim2.fromOffset(7, 7), Size = UDim2.new(1, -14, 1, -50), ClipsDescendants = true, ZIndex = 2 })
	C.Corner(well, 4)
	C.Gradient(well, if info.Discovered then Theme.Darken(rarityColor, 0.55) else P.PanelLight, P.Ink)
	Cards.Thumbnail(well, def, not info.Discovered)
	local bar = C.Frame(card, { Name = "RarityBar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -7), Size = UDim2.new(1, -14, 0, 34), ZIndex = 3 })
	C.Corner(bar, 4)
	C.Stroke(bar, P.Ink, 2)
	rarityFill(bar, def.Rarity, not info.Discovered)
	C.Title(bar, if info.Discovered then (info.Name or def.Name) else "???", {
		Name = "FighterName",
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		TextSize = 16,
		TextScaled = true,
		TextColor3 = if info.Discovered then P.White else P.Ink,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 4,
	}, if info.Discovered then 2 else 0.01)
	local nameLabel = bar:FindFirstChild("FighterName")
	C.Create("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 9, Parent = nameLabel })
	hoverable(card)
	if onClick then
		card.Activated:Connect(onClick)
	end
	return card
end

--[[
	Right-hand panel of the Index: a "CATEGORIES" caption, one banner per world (clickable when it can be shown,
	"???" otherwise) and an info box. worlds = { { Id, Name, Color, Available, Selected, Count? } }.
	Returns { Frame, Info (the info box frame), SetWorlds(worlds) }.
]]
function Cards.IndexWorldPanel(parent: Instance, onWorld: (string) -> ())
	local panel = C.Frame(parent, { Name = "WorldPanel", BackgroundTransparency = 1, ZIndex = 2 })
	C.Title(panel, "CATEGORIES", { Name = "Caption", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(1, 0, 0, 22), TextSize = 16, TextColor3 = P.TextDim, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 }, 1.5)
	local list = C.Scroll(panel, { Name = "Worlds", Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0.42, -26) })
	C.List(list, Enum.FillDirection.Vertical, 8)
	C.Create("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), Parent = list })
	local info = C.Frame(panel, { Name = "Info", BackgroundColor3 = P.Panel, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.58, -10), ZIndex = 2 })
	C.Corner(info, 6)
	C.Stroke(info, P.Line, 2)
	C.Padding(info, 12)
	local api = { Frame = panel, Info = info, List = list }
	function api.SetWorlds(worlds)
		C.Clear(list)
		for i, world in worlds do
			local banner = C.Create("TextButton", {
				Name = if world.Available then world.Id else "Unknown",
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = if world.Available then P.White else P.Ink,
				Size = UDim2.new(1, -6, 0, 70),
				LayoutOrder = i,
				Parent = list,
			})
			C.Corner(banner, 6)
			C.Stroke(banner, if world.Selected then P.Yellow else P.Ink, if world.Selected then 3 else 2)
			if world.Available then
				C.Gradient(banner, world.Color:Lerp(P.White, 0.15), Theme.Darken(world.Color, 0.45))
				texture(banner, 2)
			end
			C.Title(banner, if world.Available then world.Name else "???", {
				Name = "WorldName",
				Position = UDim2.fromOffset(10, if world.Count then 6 else 0),
				Size = UDim2.new(1, -20, if world.Count then 0.6 else 1, 0),
				TextSize = 24,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 3,
			}, 2.5)
			C.Create("UITextSizeConstraint", { MaxTextSize = 24, MinTextSize = 12, Parent = banner:FindFirstChild("WorldName") })
			if world.Count then
				C.Title(banner, world.Count, {
					Name = "Count",
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.new(0.5, 0, 1, -6),
					Size = UDim2.new(1, -20, 0, 18),
					TextSize = 15,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 3,
				}, 1.5)
			end
			if world.Available then
				hoverable(banner)
				banner.Activated:Connect(function()
					onWorld(world.Id)
				end)
			end
		end
	end
	return api
end

--[[
	Row of filter chips (e.g. rarities). items = { { Id, Text, Color?, Gradient? } }. The selected chip is filled
	with its colour; the others show it as a border. Returns { Frame, Select(id), Selected }.
]]
function Cards.Chips(parent: Instance, items, onSelect: (string) -> ())
	local row = C.Frame(parent, { Name = "Chips", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), ZIndex = 2 })
	C.List(row, Enum.FillDirection.Horizontal, 8)
	local api = { Frame = row, Selected = nil :: string? }
	local chips = {}
	local function paint()
		for id, chip in chips do
			local item = chip.Item
			local selected = id == api.Selected
			local tint = item.Color or P.Yellow
			chip.Button.BackgroundColor3 = if selected then tint else P.Panel
			chip.Stroke.Color = if selected then P.Ink else tint
			chip.Label.TextColor3 = if selected then P.Ink else P.White
			chip.Gradient.Enabled = selected and item.Gradient ~= nil
		end
	end
	for i, item in items do
		local width = math.max(64, #item.Text * 10 + 26)
		local button = C.Create("TextButton", {
			Name = item.Id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = P.Panel,
			Size = UDim2.fromOffset(width, 32),
			LayoutOrder = i,
			ZIndex = 3,
			Parent = row,
		})
		C.Corner(button, 5)
		local stroke = C.Stroke(button, item.Color or P.Yellow, 2.5)
		local gradient = C.Create("UIGradient", { Color = item.Gradient or ColorSequence.new(P.White), Enabled = false, Parent = button })
		if item.Gradient then
			button.BackgroundColor3 = P.White
		end
		local label = C.Title(button, item.Text, { Size = UDim2.fromScale(1, 1), TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 }, 0.01)
		chips[item.Id] = { Button = button, Stroke = stroke, Label = label, Item = item, Gradient = gradient }
		hoverable(button)
		button.Activated:Connect(function()
			api.Select(item.Id)
			onSelect(item.Id)
		end)
	end
	function api.Select(id: string)
		api.Selected = id
		paint()
		-- gradient chips need a white base under the gradient when selected
		for chipId, chip in chips do
			if chip.Item.Gradient and chipId == id then
				chip.Button.BackgroundColor3 = P.White
			end
		end
	end
	return api
end

-- Wide bar: label on the left, "x/y" on the right, gold fill. Returns { Frame, Set(fraction, label, count) }.
function Cards.LabeledBar(parent: Instance, props: { [string]: any }?)
	local back = C.Frame(parent, { Name = "LabeledBar", BackgroundColor3 = P.PanelLight, Size = UDim2.new(1, 0, 0, 40), ZIndex = 3 })
	for k, v in props or {} do
		(back :: any)[k] = v
	end
	C.Corner(back, UDim.new(0.5, 0))
	C.Stroke(back, P.Ink, 2.5)
	local fill = C.Frame(back, { Name = "Fill", BackgroundColor3 = P.White, Size = UDim2.fromScale(0, 1), ZIndex = 3 })
	C.Corner(fill, UDim.new(0.5, 0))
	C.Gradient(fill, Theme.Gradients.Progress.Top, Theme.Gradients.Progress.Bottom)
	local label = C.Title(back, "", { Name = "Label", Position = UDim2.fromOffset(22, 0), Size = UDim2.new(0.7, -22, 1, 0), TextSize = 18, ZIndex = 5 }, 2)
	local count = C.Title(back, "", { Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 0), Size = UDim2.new(0.3, 0, 1, 0), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 5 }, 2)
	return {
		Frame = back,
		Set = function(fraction: number, text: string, countText: string)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.001
			label.Text = text
			count.Text = countText
		end,
	}
end

return Cards
