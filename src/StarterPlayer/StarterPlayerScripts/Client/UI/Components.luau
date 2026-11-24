--[[
	Components
	Small UI factory used by every controller so windows look consistent and stay short.
	All functions create real Instances; nothing here talks to the server.
]]

local Theme = require(script.Parent.Theme)

local C = {}

function C.Create(className: string, props: { [string]: any }?): any
	local instance = Instance.new(className)
	local parent = nil
	for key, value in props or {} do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

function C.Corner(parent: Instance, radius: UDim?)
	return C.Create("UICorner", { CornerRadius = radius or Theme.CornerRadius, Parent = parent })
end

function C.Stroke(parent: Instance, color: Color3?, thickness: number?)
	return C.Create("UIStroke", { Color = color or Theme.Colors.Stroke, Thickness = thickness or 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

function C.Padding(parent: Instance, px: number)
	local u = UDim.new(0, px)
	return C.Create("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u, Parent = parent })
end

function C.List(parent: Instance, direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?)
	return C.Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function C.Grid(parent: Instance, cellSize: UDim2, padding: number?)
	return C.Create("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(padding or 6, padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function C.Frame(parent: Instance, props: { [string]: any }?)
	local frame = C.Create("Frame", { BackgroundColor3 = Theme.Colors.Panel, BorderSizePixel = 0, Parent = parent })
	for k, v in props or {} do
		frame[k] = v
	end
	return frame
end

function C.Label(parent: Instance, text: string, props: { [string]: any }?)
	local label = C.Create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		Font = Theme.Fonts.Body,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = parent,
	})
	for k, v in props or {} do
		label[k] = v
	end
	return label
end

function C.Button(parent: Instance, text: string, onClick: (() -> ())?, props: { [string]: any }?)
	local button = C.Create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Theme.Colors.PanelLight,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		Font = Theme.Fonts.Bold,
		TextSize = 16,
		Size = UDim2.fromOffset(120, 36),
		Parent = parent,
	})
	for k, v in props or {} do
		button[k] = v
	end
	C.Corner(button, UDim.new(0, 8))
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

function C.Scroll(parent: Instance, props: { [string]: any }?)
	local scroll = C.Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	for k, v in props or {} do
		scroll[k] = v
	end
	return scroll
end

-- Removes every child except layouts/padding/corners.
function C.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if not (child:IsA("UIGridStyleLayout") or child:IsA("UIPadding") or child:IsA("UICorner") or child:IsA("UIStroke")) then
			child:Destroy()
		end
	end
end

function C.ProgressBar(parent: Instance, color: Color3?, props: { [string]: any }?)
	local back = C.Frame(parent, { BackgroundColor3 = Theme.Colors.Background, Size = UDim2.new(1, 0, 0, 14) })
	for k, v in props or {} do
		back[k] = v
	end
	C.Corner(back, UDim.new(0, 7))
	local fill = C.Frame(back, { BackgroundColor3 = color or Theme.Colors.XP, Size = UDim2.fromScale(0, 1) })
	C.Corner(fill, UDim.new(0, 7))
	local text = C.Label(back, "", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, Font = Theme.Fonts.Bold, ZIndex = 3 })
	return {
		Frame = back,
		Set = function(fraction: number, caption: string?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			text.Text = caption or ""
		end,
	}
end

-- Horizontal tab strip. Returns { Select(name) }.
function C.Tabs(parent: Instance, names: { string }, onSelect: (string) -> ())
	local strip = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34) })
	C.List(strip, Enum.FillDirection.Horizontal, 6)
	local buttons = {}
	local api = {}
	function api.Select(name: string)
		for tabName, button in buttons do
			button.BackgroundColor3 = if tabName == name then Theme.Colors.Accent else Theme.Colors.PanelLight
			button.TextColor3 = if tabName == name then Theme.Colors.Background else Theme.Colors.Text
		end
		onSelect(name)
	end
	for i, name in names do
		buttons[name] = C.Button(strip, name, function()
			api.Select(name)
		end, { LayoutOrder = i, Size = UDim2.fromOffset(110, 30), TextSize = 14 })
	end
	api.Frame = strip
	return api
end

--[[
	Standard window: centred panel with title bar and close button.
	Returns { Frame, Content, Title, SetVisible(bool) }. Windows are registered in UIController.
]]
function C.Window(parent: Instance, title: string, size: UDim2?)
	local frame = C.Frame(parent, {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = size or Theme.WindowSize,
		Visible = false,
		BackgroundColor3 = Theme.Colors.Panel,
	})
	C.Corner(frame)
	C.Stroke(frame, Theme.Colors.Stroke, 2)
	C.Create("UISizeConstraint", { MaxSize = Vector2.new(900, 640), Parent = frame })
	local header = C.Frame(frame, { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, 0, 0, 44) })
	C.Corner(header)
	local titleLabel = C.Label(header, title, { Font = Theme.Fonts.Title, TextSize = 22, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -70, 1, 0) })
	local close = C.Button(header, "X", nil, { Size = UDim2.fromOffset(36, 36), Position = UDim2.new(1, -42, 0, 4), BackgroundColor3 = Theme.Colors.Bad })
	local content = C.Frame(frame, { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 54), Size = UDim2.new(1, -24, 1, -66) })
	return {
		Frame = frame,
		Content = content,
		Title = titleLabel,
		CloseButton = close,
	}
end

-- A unit card for grids: coloured by rarity, shows name/level/stars/lock/equipped.
function C.UnitCard(parent: Instance, info: { Name: string, Rarity: string, Level: number, Stars: number, Locked: boolean, Equipped: boolean, Trait: string? }, onClick: (() -> ())?)
	local card = C.Create("TextButton", { Text = "", AutoButtonColor = true, BackgroundColor3 = Theme.Colors.PanelLight, Parent = parent })
	C.Corner(card, UDim.new(0, 8))
	C.Stroke(card, Theme.Rarity(info.Rarity), if info.Equipped then 3 else 1.5)
	C.Label(card, info.Name, { Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 32), TextWrapped = true, TextSize = 13, Font = Theme.Fonts.Bold, TextYAlignment = Enum.TextYAlignment.Top })
	C.Label(card, "Lv " .. info.Level .. "  " .. string.rep("★", info.Stars), { Position = UDim2.new(0, 6, 1, -40), Size = UDim2.new(1, -12, 0, 16), TextSize = 12, TextColor3 = Theme.Colors.TextDim })
	C.Label(card, info.Rarity, { Position = UDim2.new(0, 6, 1, -22), Size = UDim2.new(1, -12, 0, 16), TextSize = 12, Font = Theme.Fonts.Bold, TextColor3 = Theme.Rarity(info.Rarity) })
	local badges = {}
	if info.Equipped then
		table.insert(badges, "E")
	end
	if info.Locked then
		table.insert(badges, "🔒")
	end
	if info.Trait then
		table.insert(badges, "T")
	end
	if #badges > 0 then
		C.Label(card, table.concat(badges, " "), { Position = UDim2.new(1, -46, 1, -22), Size = UDim2.fromOffset(40, 16), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12, Font = Theme.Fonts.Bold, TextColor3 = Theme.Colors.Accent })
	end
	if onClick then
		card.Activated:Connect(onClick)
	end
	return card
end

return C
