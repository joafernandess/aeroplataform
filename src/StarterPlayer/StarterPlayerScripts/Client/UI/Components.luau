--[[
	Components
	UI factory used by every controller so windows look consistent and stay short.
	All functions create real Instances; nothing here talks to the server.

	Visual language ("arcade simulator"): glossy gradient buttons with thick dark borders, outlined
	display text, round icon buttons, bold currency pills, rarity-coloured unit cards.
]]

local Theme = require(script.Parent.Theme)

local C = {}

local GLOSS = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 205))
local CARD_SHADE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(105, 100, 130))

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

local function apply(instance: Instance, props: { [string]: any }?)
	for k, v in props or {} do
		(instance :: any)[k] = v
	end
	return instance
end

function C.Corner(parent: Instance, radius: UDim?)
	return C.Create("UICorner", { CornerRadius = radius or Theme.CornerRadius, Parent = parent })
end

-- Border stroke around a frame/button.
function C.Stroke(parent: Instance, color: Color3?, thickness: number?)
	return C.Create("UIStroke", { Color = color or Theme.Colors.Stroke, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

-- Thick outline around the glyphs of a TextLabel (the chunky "simulator" look).
function C.Outline(label: Instance, thickness: number?, color: Color3?)
	return C.Create("UIStroke", { Color = color or Theme.Colors.Outline, Thickness = thickness or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = label })
end

-- Vertical gradient that multiplies the BackgroundColor3 (light top, darker bottom).
function C.Gloss(parent: Instance, sequence: ColorSequence?)
	return C.Create("UIGradient", { Color = sequence or GLOSS, Rotation = 90, Parent = parent })
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
	return apply(frame, props)
end

-- Body text.
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
	return apply(label, props)
end

-- Display text: rounded bold font with a thick outline.
function C.Title(parent: Instance, text: string, props: { [string]: any }?, outline: number?)
	local label = C.Label(parent, text, { Font = Theme.Fonts.Title, TextSize = 20 })
	apply(label, props)
	C.Outline(label, outline or 2)
	return label
end

--[[
	Glossy button. The label is drawn by the TextButton itself (controllers may change .Text later) with a
	built-in text stroke; the box gets a thick dark border and a gloss gradient.
]]
function C.Button(parent: Instance, text: string, onClick: (() -> ())?, props: { [string]: any }?)
	local button = C.Create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Theme.Colors.Button,
		Text = text,
		TextColor3 = Theme.Colors.Text,
		TextStrokeColor3 = Theme.Colors.Outline,
		TextStrokeTransparency = 0.2,
		Font = Theme.Fonts.Bold,
		TextSize = 17,
		Size = UDim2.fromOffset(120, 36),
		Parent = parent,
	})
	apply(button, props)
	C.Corner(button, UDim.new(0, 10))
	C.Stroke(button, Theme.Colors.Stroke, 2.5)
	C.Gloss(button)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

--[[
	Round icon button with a caption underneath (menu, HUD actions).
	Returns (container, button). `size` is the circle diameter.
]]
function C.IconButton(parent: Instance, icon: string, caption: string?, color: Color3, onClick: (() -> ())?, size: number?)
	local d = size or 64
	local container = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(d + 12, d + (if caption then 14 else 0)) })
	local button = C.Create("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = color,
		Text = icon,
		TextSize = math.floor(d * 0.46),
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.Colors.Text,
		TextStrokeColor3 = Theme.Colors.Outline,
		TextStrokeTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(d, d),
		Parent = container,
	})
	C.Corner(button, UDim.new(0.5, 0))
	C.Stroke(button, Theme.Colors.Stroke, 3)
	C.Gloss(button)
	if caption then
		C.Title(container, caption, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 8, 0, 18),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		}, 1.5)
	end
	if onClick then
		button.Activated:Connect(onClick)
	end
	return container, button
end

--[[
	Currency pill: coloured bar with a round icon badge overlapping its left edge.
	Returns { Frame, Set(text) }.
]]
function C.CurrencyPill(parent: Instance, icon: string, color: Color3, width: number?)
	local w = width or 190
	local container = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, 40) })
	local bar = C.Frame(container, { BackgroundColor3 = color, Position = UDim2.fromOffset(18, 5), Size = UDim2.new(1, -18, 0, 30) })
	C.Corner(bar, UDim.new(0, 10))
	C.Stroke(bar, Theme.Colors.Stroke, 2.5)
	C.Gloss(bar)
	local badge = C.Frame(container, { BackgroundColor3 = Theme.Colors.Background, Size = UDim2.fromOffset(40, 40), ZIndex = 2 })
	C.Corner(badge, UDim.new(0.5, 0))
	C.Stroke(badge, Theme.Colors.Stroke, 2.5)
	C.Title(badge, icon, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 20, TextColor3 = color, ZIndex = 3 }, 1.5)
	local value = C.Title(bar, "0", {
		Position = UDim2.fromOffset(28, 0),
		Size = UDim2.new(1, -36, 1, 0),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 3,
	}, 2)
	return {
		Frame = container,
		Set = function(text: string)
			value.Text = text
		end,
	}
end

function C.Scroll(parent: Instance, props: { [string]: any }?)
	local scroll = C.Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, -- content never sits under the scrollbar
		ScrollBarImageColor3 = Theme.Colors.Accent,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	return apply(scroll, props)
end

-- Removes every child except UI components (layouts, padding, corners, strokes, UIScale, constraints).
function C.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIComponent") then
			child:Destroy()
		end
	end
end

function C.ProgressBar(parent: Instance, color: Color3?, props: { [string]: any }?)
	local back = C.Frame(parent, { BackgroundColor3 = Theme.Colors.Background, Size = UDim2.new(1, 0, 0, 16) })
	apply(back, props)
	C.Corner(back, UDim.new(0.5, 0))
	C.Stroke(back, Theme.Colors.Stroke, 2)
	local fill = C.Frame(back, { BackgroundColor3 = color or Theme.Colors.XP, Size = UDim2.fromScale(0, 1) })
	C.Corner(fill, UDim.new(0.5, 0))
	C.Gloss(fill)
	local text = C.Title(back, "", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 13, ZIndex = 3 }, 1.5)
	return {
		Frame = back,
		Set = function(fraction: number, caption: string?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.001
			text.Text = caption or ""
		end,
	}
end

-- Horizontal tab strip. Returns { Select(name), Frame }.
function C.Tabs(parent: Instance, names: { string }, onSelect: (string) -> ())
	local strip = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36) })
	C.List(strip, Enum.FillDirection.Horizontal, 8)
	local buttons = {}
	local api = {}
	function api.Select(name: string)
		for tabName, button in buttons do
			button.BackgroundColor3 = if tabName == name then Theme.Colors.Cta else Theme.Colors.Button
		end
		onSelect(name)
	end
	for i, name in names do
		buttons[name] = C.Button(strip, name, function()
			api.Select(name)
		end, { LayoutOrder = i, Size = UDim2.fromOffset(130, 32), TextSize = 16 })
	end
	api.Frame = strip
	return api
end

--[[
	Standard window: centred panel with a gradient header band, outlined display title and a round close
	button. Returns { Frame, Content, Title, Header, CloseButton }. Windows are registered in UIController.
]]
function C.Window(parent: Instance, title: string, size: UDim2?)
	local frame = C.Frame(parent, {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = size or Theme.WindowSize,
		Visible = false,
		BackgroundColor3 = Theme.Colors.Panel,
	})
	C.Corner(frame, UDim.new(0, 16))
	C.Stroke(frame, Theme.Colors.Stroke, 3.5)
	C.Create("UISizeConstraint", { MaxSize = Vector2.new(900, 640), Parent = frame })
	local header = C.Frame(frame, { BackgroundColor3 = Theme.Colors.Header, Size = UDim2.new(1, 0, 0, 52) })
	C.Corner(header, UDim.new(0, 16))
	C.Gloss(header, ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 200)))
	local titleLabel = C.Label(header, title, {
		Font = Theme.Fonts.Display,
		TextSize = 30,
		Position = UDim2.fromOffset(18, 2),
		Size = UDim2.new(1, -90, 1, 0),
		ZIndex = 2,
	})
	C.Outline(titleLabel, 2.5)
	local close = C.Button(header, "✕", nil, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(1, -6, 0, 6),
		Size = UDim2.fromOffset(44, 44),
		BackgroundColor3 = Theme.Colors.Bad,
		TextSize = 22,
		ZIndex = 4,
	})
	close:FindFirstChildOfClass("UICorner").CornerRadius = UDim.new(0.5, 0)
	local content = C.Frame(frame, { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 1, -76) })
	return {
		Frame = frame,
		Content = content,
		Title = titleLabel,
		Header = header,
		CloseButton = close,
	}
end

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

--[[
	Unit card for grids: rarity-coloured gradient tile, round portrait (initials until art exists),
	level, stars, name, equipped check and lock badge.
]]
function C.UnitCard(
	parent: Instance,
	info: { Name: string, Rarity: string, Level: number, Stars: number, Locked: boolean, Equipped: boolean, Trait: string?, Badge: string? },
	onClick: (() -> ())?
)
	local rarityColor = Theme.Rarity(info.Rarity)
	local card = C.Create("TextButton", { Text = "", AutoButtonColor = true, BackgroundColor3 = rarityColor, Parent = parent })
	C.Corner(card, UDim.new(0, 12))
	C.Stroke(card, Theme.Colors.Stroke, 2.5)
	C.Gloss(card, CARD_SHADE)

	local portrait = C.Frame(card, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(52, 52),
		BackgroundColor3 = Theme.Darken(rarityColor, 0.55),
	})
	C.Corner(portrait, UDim.new(0.5, 0))
	C.Stroke(portrait, Theme.Colors.Stroke, 2)
	C.Title(portrait, initials(info.Name), { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Display, TextSize = 24, TextColor3 = rarityColor }, 1.5)

	C.Title(card, info.Badge or ("Lv " .. info.Level), { Position = UDim2.fromOffset(6, 2), Size = UDim2.fromOffset(80, 16), TextSize = 13 }, 1.5)
	if info.Stars > 0 then
		C.Title(card, string.rep(Theme.Icons.Star, info.Stars), {
			Position = UDim2.new(1, -66, 0, 2),
			Size = UDim2.fromOffset(60, 16),
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = Theme.Colors.Yen,
		}, 1.5)
	end
	C.Title(card, info.Name, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -4),
		Size = UDim2.new(1, -8, 0, 30),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Bottom,
	}, 1.5)

	if info.Equipped then
		local check = C.Frame(card, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = Theme.Colors.Good, ZIndex = 3 })
		C.Corner(check, UDim.new(0.5, 0))
		C.Stroke(check, Theme.Colors.Stroke, 2)
		C.Title(check, Theme.Icons.Equipped, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, ZIndex = 4 }, 1.5)
	end
	if info.Locked then
		C.Label(card, Theme.Icons.Lock, { Position = UDim2.new(0, 4, 0, 46), Size = UDim2.fromOffset(20, 20), TextSize = 14 })
	end
	if info.Trait then
		local trait = C.Frame(card, { Position = UDim2.new(1, -20, 0, 50), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Theme.Colors.Tokens })
		C.Corner(trait, UDim.new(0.5, 0))
		C.Stroke(trait, Theme.Colors.Stroke, 1.5)
	end
	if onClick then
		card.Activated:Connect(onClick)
	end
	return card
end

-- Selection feedback on a unit card: "Selected" (inspecting) or "Marked" (chosen for fuse/sell).
function C.HighlightCard(card: Instance, mode: string?)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if not stroke then
		return
	end
	if mode == "Selected" then
		stroke.Color = Theme.Colors.Accent
		stroke.Thickness = 4
	elseif mode == "Marked" then
		stroke.Color = Theme.Colors.Cta
		stroke.Thickness = 4
		C.Frame(card, { BackgroundColor3 = Theme.Colors.Cta, BackgroundTransparency = 0.55, Size = UDim2.fromScale(1, 1), ZIndex = 5 })
	end
end

return C
