--[[
	Components
	UI factory used by every controller (see docs/ui/UI_RESEARCH.md §5). Creates real Instances only;
	nothing here talks to the server.

	Buttons are "3D": a face (vertical gradient + gloss + 3px ink border) sitting on a darker 4px lip. The label
	is a child TextLabel with its own outline, so use C.SetText(button, text) / C.SetKind(button, kind) /
	C.SetDisabled(button, bool) instead of touching button.Text or button.BackgroundColor3.
	Kinds: "Primary" (blue) · "Secondary" (white) · "Accent" (cyan) · "Dark" · "Danger" (inverted, 2-tap confirm).

	Icons come from UI/Icons (vector drawings, or uploaded images listed in Theme.IconAssets). Every component
	that used to take a glyph (Theme.Icons.X) also accepts an icon name ("summon"); unknown text still renders
	as text. C.Icon(parent, nameOrGlyph, props) creates a standalone icon; C.Button takes an `Icon` prop.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local C = {}
C.Icons = Icons

local P = Theme.Colors
local G = Theme.Gradients

-- Per-button parts, keyed weakly by the TextButton.
local buttons: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
-- Side-menu button states (C.NavButton), keyed weakly by the TextButton.
local navStates: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

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

local function tween(instance: Instance, seconds: number, goals: { [string]: any })
	TweenService:Create(instance, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
end

-- Primitives -----------------------------------------------------------------------------------------------------

-- Standalone icon (see UI/Icons.luau): props = Size (number px or UDim2), Position, AnchorPoint, ZIndex, Color...
function C.Icon(parent: Instance, nameOrGlyph: string, props: { [string]: any }?)
	return Icons.Create(nameOrGlyph, parent, props)
end

-- Square icon centred in `parent` (badges, tiles, button faces).
local function centeredIcon(parent: Instance, name: string, px: number, props: { [string]: any }?)
	local p = table.clone(props or {})
	p.Size = px
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = p.Position or UDim2.fromScale(0.5, 0.5)
	return Icons.Create(name, parent, p)
end

function C.Corner(parent: Instance, radius: UDim | number | nil)
	local value = if typeof(radius) == "number" then UDim.new(0, radius :: number) else (radius :: UDim?) or Theme.CornerRadius
	return C.Create("UICorner", { CornerRadius = value, Parent = parent })
end

-- Border stroke around a frame/button.
function C.Stroke(parent: Instance, color: Color3?, thickness: number?)
	return C.Create("UIStroke", {
		Color = color or P.Ink,
		Thickness = thickness or Theme.Stroke.Button,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = parent,
	})
end

-- Thick outline around the glyphs of a TextLabel.
function C.Outline(label: Instance, thickness: number?, color: Color3?)
	return C.Create("UIStroke", {
		Color = color or P.Ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Parent = label,
	})
end

-- Gradient with real colours (the object's BackgroundColor3 should be white). Rotation 90 = top -> bottom.
function C.Gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	return C.Create("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90, Parent = parent })
end

-- Legacy helper: subtle vertical shading that multiplies the current BackgroundColor3.
function C.Gloss(parent: Instance, sequence: ColorSequence?)
	return C.Create("UIGradient", { Color = sequence or ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 210, 235)), Rotation = 90, Parent = parent })
end

-- White highlight over the top 45% of a rounded element.
function C.Shine(parent: Instance, radius: number, transparency: number?)
	local shine = C.Create("Frame", {
		Name = "Shine",
		BackgroundColor3 = P.White,
		BackgroundTransparency = transparency or 0.82,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0.45),
		ZIndex = 2,
		Parent = parent,
	})
	C.Corner(shine, radius)
	return shine
end

function C.Padding(parent: Instance, px: number)
	local u = UDim.new(0, px)
	return C.Create("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u, Parent = parent })
end

function C.List(parent: Instance, direction: Enum.FillDirection?, padding: number?, align: Enum.HorizontalAlignment?)
	return C.Create("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function C.Grid(parent: Instance, cellSize: UDim2, padding: number?)
	return C.Create("UIGridLayout", {
		CellSize = cellSize,
		CellPadding = UDim2.fromOffset(padding or 10, padding or 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

function C.Frame(parent: Instance, props: { [string]: any }?)
	local frame = C.Create("Frame", { BackgroundColor3 = P.Panel, BorderSizePixel = 0, Parent = parent })
	return apply(frame, props)
end

-- Body text (BuilderSans Bold).
function C.Label(parent: Instance, text: string, props: { [string]: any }?)
	local label = C.Create("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = P.White,
		Font = Theme.Fonts.Body,
		TextSize = Theme.TextSize.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 22),
		Parent = parent,
	})
	return apply(label, props)
end

-- Display/UI text (FredokaOne by default) with an ink outline sized to the text.
function C.Title(parent: Instance, text: string, props: { [string]: any }?, outline: number?)
	local label = C.Label(parent, text, { Font = Theme.Fonts.Title, TextSize = 20 })
	apply(label, props)
	C.Outline(label, outline or Theme.OutlineFor(label.TextSize))
	return label
end

-- Big numbers (BuilderSans ExtraBold) with outline.
function C.Number(parent: Instance, text: string, props: { [string]: any }?)
	local label = C.Label(parent, text, { Font = Theme.Fonts.Number, TextSize = 24 })
	apply(label, props)
	C.Outline(label, Theme.OutlineFor(label.TextSize) - 0.5)
	return label
end

-- Panel row used by list windows (quests, shop, worlds...).
function C.Row(parent: Instance, props: { [string]: any }?)
	local row = C.Frame(parent, { BackgroundColor3 = P.PanelAlt, Size = UDim2.new(1, -8, 0, 64) })
	apply(row, props)
	C.Corner(row, Theme.Radius.Card)
	C.Stroke(row, P.Ink, Theme.Stroke.Card)
	return row
end

-- Decorative diagonal "speed-lines" (signature element). Parent should clip descendants.
function C.SpeedLines(parent: Instance, count: number, options: { Start: number?, Spacing: number?, Width: number?, Length: number?, Transparency: number?, ZIndex: number? }?)
	local o = options or {}
	local start, spacing = o.Start or 0, o.Spacing or 28
	for i = 0, count - 1 do
		C.Create("Frame", {
			Name = "SpeedLine",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(start, i * spacing, 0.5, 0),
			Size = UDim2.fromOffset(o.Width or 2, o.Length or 120),
			Rotation = 25,
			BackgroundColor3 = P.White,
			BackgroundTransparency = o.Transparency or 0.88,
			BorderSizePixel = 0,
			ZIndex = o.ZIndex or 2,
			Parent = parent,
		})
	end
end

-- Buttons --------------------------------------------------------------------------------------------------------

local function labelStyle(kind: string, textSize: number)
	if kind == "Secondary" then
		return P.SecondaryText, 0
	elseif kind == "Disabled" then
		return P.TextMuted, 1.5
	end
	return P.White, Theme.OutlineFor(textSize)
end

local function paint(parts)
	local kind = if parts.Disabled then "Disabled" else parts.Kind
	local g = G[kind] or G.Primary
	parts.Gradient.Color = ColorSequence.new(g.Top, g.Bottom)
	parts.Lip.BackgroundColor3 = g.Lip or g.Bottom
	parts.Lip.Visible = g.Lip ~= nil
	parts.Stroke.Color = if kind == "Danger" then P.White else P.Ink
	parts.Stroke.Thickness = if kind == "Danger" then 2.5 elseif kind == "Disabled" then 1.5 else parts.StrokeThickness
	local color, outline = labelStyle(kind, parts.Label.TextSize)
	parts.Label.TextColor3 = color
	parts.LabelStroke.Enabled = outline > 0
	parts.LabelStroke.Thickness = math.max(outline, 1)
	if parts.Sub then
		parts.Sub.TextColor3 = color
		parts.SubStroke.Enabled = outline > 0
	end
	if parts.Icon then
		Icons.SetColors(parts.Icon, { Color = if kind == "Secondary" then P.SecondaryText else color })
	end
end

-- Pixel size of an offset-based UDim2 (`fallback` for scale-based sizes).
local function offsetOf(size: UDim2?, fallback: number): (number, number)
	if not size or size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
		return fallback, fallback
	end
	return size.X.Offset, size.Y.Offset
end

--[[
	C.Button(parent, text, onClick?, props?)
	props: any TextButton property plus
	  Kind       "Primary" | "Secondary" | "Accent" | "Dark" | "Danger" (default "Primary")
	  TextSize   label size (default 20)
	  Subtext    optional second line (e.g. a price)
	  Radius     corner radius (default 12)
	  Confirm    Danger buttons ask "Confirm?" for 3s before running onClick (default true for Danger)
	  Icon       icon name or glyph: centred when text is "", otherwise drawn left of the label
	  IconSize   icon size in px (default 62% of the face when alone, 56% of its height next to text)
]]
function C.Button(parent: Instance, text: string, onClick: (() -> ())?, props: { [string]: any }?)
	props = table.clone(props or {})
	local kind = props.Kind or "Primary"
	local textSize = props.TextSize or Theme.TextSize.Button
	local subtext = props.Subtext
	local radius = props.Radius or Theme.Radius.Button
	local confirm = if props.Confirm == nil then kind == "Danger" else props.Confirm
	local strokeThickness = props.StrokeThickness or Theme.Stroke.Button
	local iconName = if props.Icon then Icons.Resolve(props.Icon) or props.Icon else nil
	local iconSize = props.IconSize
	for _, key in { "Kind", "TextSize", "Subtext", "Radius", "Confirm", "StrokeThickness", "TextColor3", "Font", "TextWrapped", "Icon", "IconSize" } do
		props[key] = nil
	end

	local button = C.Create("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromOffset(160, 48),
		Parent = parent,
	})
	apply(button, props)
	local scale = C.Create("UIScale", { Parent = button })

	local lip = C.Frame(button, { Name = "Lip", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 1, -4) })
	C.Corner(lip, radius)
	C.Stroke(lip, P.Ink, strokeThickness)
	local face = C.Frame(button, { Name = "Face", BackgroundColor3 = P.White, Size = UDim2.new(1, 0, 1, -4), ZIndex = (button.ZIndex or 1) + 1 })
	C.Corner(face, radius)
	local stroke = C.Stroke(face, P.Ink, strokeThickness)
	local gradient = C.Create("UIGradient", { Rotation = 90, Parent = face })
	C.Shine(face, radius)

	local label = C.Label(face, text, {
		Name = "Label",
		Font = Theme.Fonts.Bold,
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = if subtext then UDim2.new(1, -8, 0.58, 0) else UDim2.new(1, -8, 1, 0),
		Position = UDim2.fromOffset(4, 0),
		ZIndex = face.ZIndex + 2,
	})
	local labelStroke = C.Outline(label, Theme.OutlineFor(textSize))
	local sub, subStroke = nil, nil
	if subtext then
		sub = C.Label(face, subtext, {
			Name = "Subtext",
			Font = Theme.Fonts.Number,
			TextSize = math.max(14, math.floor(textSize * 0.68)),
			TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 4, 0.52, 0),
			Size = UDim2.new(1, -8, 0.4, 0),
			ZIndex = face.ZIndex + 2,
		})
		subStroke = C.Outline(sub, 1.5)
	end
	local icon = nil
	if iconName then
		local w, h = offsetOf(button.Size, 48)
		local faceH = h - 4
		if text == "" then
			icon = centeredIcon(face, iconName, iconSize or math.floor(math.min(w, faceH) * 0.62 + 0.5), { ZIndex = face.ZIndex + 2 })
		else
			local px = iconSize or math.floor(faceH * 0.56 + 0.5)
			icon = centeredIcon(face, iconName, px, { ZIndex = face.ZIndex + 2, Position = UDim2.new(0, 10 + px / 2, 0.5, 0) })
			label.Position = UDim2.fromOffset(px + 14, 0)
			label.Size = UDim2.new(1, -(px + 18), label.Size.Y.Scale, label.Size.Y.Offset)
		end
	end

	local parts = {
		Face = face,
		Lip = lip,
		Label = label,
		LabelStroke = labelStroke,
		Sub = sub,
		SubStroke = subStroke,
		Stroke = stroke,
		Gradient = gradient,
		Scale = scale,
		Kind = kind,
		Text = text,
		Disabled = false,
		StrokeThickness = strokeThickness,
		Icon = icon,
		IconOnly = icon ~= nil and text == "",
	}
	buttons[button] = parts
	paint(parts)

	-- Manual states: hover grows, press sinks the face onto the lip.
	button.MouseEnter:Connect(function()
		if not parts.Disabled then
			tween(scale, 0.08, { Scale = 1.04 })
		end
	end)
	button.MouseLeave:Connect(function()
		tween(scale, 0.08, { Scale = 1 })
		face.Position = UDim2.new()
	end)
	button.MouseButton1Down:Connect(function()
		if not parts.Disabled then
			face.Position = UDim2.fromOffset(0, 3)
			tween(scale, 0.06, { Scale = 0.95 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		face.Position = UDim2.new()
		tween(scale, 0.08, { Scale = 1 })
	end)

	if onClick then
		local armedUntil = 0
		button.Activated:Connect(function()
			if parts.Disabled then
				return
			end
			if confirm then
				local now = os.clock()
				if now > armedUntil then
					armedUntil = now + 3
					label.Text = "Confirm?"
					parts.Stroke.Color = P.Cyan
					task.delay(3, function()
						if os.clock() >= armedUntil and label.Parent then
							label.Text = parts.Text
							paint(parts)
						end
					end)
					return
				end
				armedUntil = 0
				label.Text = parts.Text
				paint(parts)
			end
			onClick()
		end)
	end
	return button
end

function C.SetText(button: Instance, text: string, subtext: string?)
	local parts = buttons[button]
	if not parts then
		(button :: any).Text = text
		return
	end
	if parts.IconOnly and parts.Icon then
		-- Icon buttons: a glyph/icon name swaps the icon; any other text replaces it.
		local name = Icons.Resolve(text)
		if name then
			parts.Icon = Icons.Swap(parts.Icon, name)
			paint(parts)
			return
		end
		parts.Icon:Destroy()
		parts.Icon, parts.IconOnly = nil, false
	end
	parts.Text = text
	parts.Label.Text = text
	if subtext and parts.Sub then
		parts.Sub.Text = subtext
	end
end

function C.SetKind(button: Instance, kind: string)
	local parts = buttons[button]
	if parts then
		parts.Kind = kind
		paint(parts)
	end
end

function C.SetDisabled(button: Instance, disabled: boolean)
	local parts = buttons[button]
	if parts then
		parts.Disabled = disabled
		paint(parts)
	end
end

-- Cyan outline marking a selected/toggled button.
function C.SetSelected(button: Instance, selected: boolean)
	local parts = buttons[button]
	if parts then
		paint(parts)
		if selected then
			parts.Stroke.Color = P.Cyan
		end
	end
end

--[[
	HUD tile look (side menus, currency box, Update Log card, window title tiles).
	With `color`: dark face tinted by the colour, thick border in the colour, a thin inner glow, a dark rim around
	it and a soft shadow under it. Without: the monochrome version (Theme.MenuButton).
	Returns paint(state) for "Idle" | "Hover" | "Press", and the shadow frame.
]]
function C.MenuTile(button: GuiObject, radius: number, color: Color3?)
	local M = Theme.MenuButton
	local ink = P.Ink
	local faces = if color
		then {
			Idle = { color:Lerp(ink, 0.6), color:Lerp(ink, 0.86) },
			Hover = { color:Lerp(ink, 0.44), color:Lerp(ink, 0.76) },
			Press = { color:Lerp(ink, 0.78), color:Lerp(ink, 0.92) },
		}
		else { Idle = { M.Top, M.Bottom }, Hover = { M.HoverTop, M.HoverBottom }, Press = { M.PressTop, M.PressBottom } }
	local border = color or M.Border
	local borderHover = if color then color:Lerp(P.White, 0.35) else M.BorderHover
	C.Corner(button, UDim.new(0, radius))
	local gradient = C.Gradient(button, faces.Idle[1], faces.Idle[2])
	local stroke = C.Stroke(button, border, if color then 3 else 2.5)
	local parent = button.Parent :: Instance
	local z = math.max(button.ZIndex - 1, 1)
	local shadow = C.Frame(parent, {
		Name = "Shadow",
		BackgroundColor3 = M.Shadow,
		BackgroundTransparency = M.ShadowTransparency,
		AnchorPoint = button.AnchorPoint,
		Position = button.Position + UDim2.fromOffset(0, 5),
		Size = button.Size + UDim2.fromOffset(4, 4),
		ZIndex = z,
	})
	C.Corner(shadow, UDim.new(0, radius + 2))
	if color then
		-- dark rim outside the coloured border, then a faint inner glow line
		local rim = C.Frame(parent, {
			Name = "Rim",
			BackgroundColor3 = ink,
			AnchorPoint = button.AnchorPoint,
			Position = button.Position,
			Size = button.Size + UDim2.fromOffset(10, 10),
			ZIndex = z,
		})
		rim.Position = button.Position - UDim2.fromOffset(5 - 10 * button.AnchorPoint.X, 5 - 10 * button.AnchorPoint.Y)
		C.Corner(rim, UDim.new(0, radius + 5))
		local glow = C.Frame(button, {
			Name = "InnerGlow",
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(3, 3),
			Size = UDim2.new(1, -6, 1, -6),
			ZIndex = button.ZIndex,
		})
		C.Corner(glow, UDim.new(0, math.max(radius - 3, 2)))
		local glowStroke = C.Stroke(glow, color:Lerp(P.White, 0.5), 1.5)
		glowStroke.Transparency = 0.55
	end
	local function paint(state: string)
		local face = faces[if state == "Selected" then "Hover" else state] or faces.Idle
		gradient.Color = ColorSequence.new(face[1], face[2])
		stroke.Color = if state == "Idle" then border elseif state == "Selected" then P.White else borderHover
	end
	return paint, shadow
end

-- Light sweep that crosses a tile every few seconds (idle "shine"). Kept off the rounded corners.
function C.ShineSweep(tile: GuiObject, every: number?)
	-- Inner clipping frame (inset past the rounded corners), so the tile itself never clips its badges.
	local clipper = C.Frame(tile, {
		Name = "SweepClip",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 1, -12),
		ClipsDescendants = true,
		ZIndex = tile.ZIndex + 1,
	})
	local sweep = C.Frame(clipper, {
		Name = "Sweep",
		BackgroundColor3 = P.White,
		BackgroundTransparency = 0.45,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(-0.3, 0, 0.5, 0),
		Size = UDim2.new(0, 22, 1, 0),
		ZIndex = tile.ZIndex + 2,
	})
	C.Create("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = sweep,
	})
	task.spawn(function()
		while sweep.Parent do
			task.wait((every or 3.5) + math.random() * 1.5)
			sweep.Position = UDim2.new(-0.3, 0, 0.5, 0)
			TweenService:Create(sweep, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(1.3, 0, 0.5, 0) }):Play()
		end
	end)
	return sweep
end

-- Marks a side-menu button as the one whose window is open (lit face, white border, slightly bigger).
function C.SetNavSelected(button: Instance, selected: boolean)
	local state = navStates[button]
	if state and state.Selected ~= selected then
		state.Selected = selected
		state.Settle(0.16)
	end
end

function C.IsNavSelected(button: Instance): boolean
	local state = navStates[button]
	return state ~= nil and state.Selected
end

--[[
	Side-menu button. info = { Icon, Label?, Key?, Wide?, Width, Height, ShowLabel?, ShowKey? }
	Square: big icon with the name inside at the bottom. Wide (full row): icon on the left, big name beside it,
	plus an idle light sweep. The icon's colour (Theme.IconColors) tints the face and draws the border.
	Animations: hover grows the tile and lifts/enlarges the icon, press squashes and darkens it.
	Returns (container, button). The FX use their own UIScales, so they never fight the responsive UIScale that
	UIController puts on the whole menu.
]]
function C.NavButton(parent: Instance, info, onClick: (() -> ())?)
	local w, h = info.Width or 70, info.Height or info.Width or 70
	local container = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h) })
	local button = C.Create("TextButton", {
		Name = "Button",
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = P.White,
		Size = UDim2.fromOffset(w, h),
		ZIndex = 3,
		Parent = container,
	})
	local color = Theme.IconColors[info.Icon] or P.White
	local paint = C.MenuTile(button, 14, color)
	local iconSize = if info.Wide then h - 12 elseif info.ShowLabel then math.floor(h * 0.6) else math.floor(h * 0.74)
	local iconHolder = C.Frame(button, {
		Name = "IconHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = if info.Wide then UDim2.new(0, 6 + iconSize / 2, 0.5, 0) elseif info.ShowLabel then UDim2.new(0.5, 0, 0.41, 0) else UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(iconSize, iconSize),
		ZIndex = 4,
	})
	local iconFx = C.Create("UIScale", { Name = "IconFX", Parent = iconHolder })
	C.Icon(iconHolder, info.Icon, {
		Name = "Icon",
		Size = iconSize,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Color = color,
		Accent = color:Lerp(P.White, 0.55),
		ZIndex = 5,
	})
	if info.ShowLabel and info.Label then
		local label = C.Title(button, info.Label, {
			Name = "Caption",
			AnchorPoint = if info.Wide then Vector2.new(0, 0.5) else Vector2.new(0.5, 1),
			Position = if info.Wide then UDim2.new(0, iconSize + 12, 0.5, 0) else UDim2.new(0.5, 0, 1, -4),
			Size = if info.Wide then UDim2.new(1, -(iconSize + 20), 0, 30) else UDim2.new(1, -8, 0, 16),
			TextSize = if info.Wide then 26 else 14,
			TextScaled = true,
			TextXAlignment = if info.Wide then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center,
			ZIndex = 6,
		}, if info.Wide then 2.5 else 2)
		C.Create("UITextSizeConstraint", { MaxTextSize = if info.Wide then 26 else 14, MinTextSize = 8, Parent = label })
	end
	if info.ShowKey and info.Key then
		local key = C.Frame(button, {
			Name = "KeyBadge",
			BackgroundColor3 = P.Ink,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(20, 20),
			ZIndex = 8,
		})
		C.Corner(key, 5)
		C.Stroke(key, P.White, 1.5)
		C.Title(key, info.Key, { Size = UDim2.fromScale(1, 1), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 9 }, 0.01)
	end
	if info.Wide then
		C.ShineSweep(button)
	end

	local fx = C.Create("UIScale", { Name = "FX", Parent = button })
	local state = { Selected = false, Hovering = false }
	local function to(target: Instance, goals: { [string]: any }, time: number, style: Enum.EasingStyle?)
		TweenService:Create(target, TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals):Play()
	end
	local rest = iconHolder.Position
	local lifted = rest - UDim2.fromOffset(0, 3)
	-- Resting look: idle, or "selected" (lit face, white border, slightly bigger) while its window is open.
	local function settle(time: number)
		local up = state.Hovering or state.Selected
		paint(if state.Hovering then "Hover" elseif state.Selected then "Selected" else "Idle")
		to(fx, { Scale = if state.Hovering then 1.06 elseif state.Selected then 1.04 else 1 }, time, Enum.EasingStyle.Back)
		to(iconFx, { Scale = if up then 1.12 else 1 }, time, Enum.EasingStyle.Back)
		to(iconHolder, { Position = if up then lifted else rest }, time)
	end
	state.Settle = settle
	navStates[button] = state
	button.MouseEnter:Connect(function()
		state.Hovering = true
		settle(0.16)
	end)
	button.MouseLeave:Connect(function()
		state.Hovering = false
		settle(0.14)
	end)
	button.MouseButton1Down:Connect(function()
		paint("Press")
		to(fx, { Scale = 0.9 }, 0.06)
		to(iconFx, { Scale = 0.94 }, 0.06)
	end)
	button.MouseButton1Up:Connect(function()
		settle(0.18)
	end)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return container, button
end

--[[
	Rounded-square icon button with a caption (menu, HUD actions). Returns (container, button).
	`kindOrColor` is a button kind ("Primary"/"Accent"/...) — a Color3 is accepted for old call sites (=> Primary).
]]
function C.IconButton(parent: Instance, icon: string, caption: string?, kindOrColor: any, onClick: (() -> ())?, size: number?)
	local d = size or 68
	local kind = if type(kindOrColor) == "string" then kindOrColor else "Primary"
	local captionHeight = if caption then 20 else 0
	local container = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(math.max(d, 84), d + 4 + captionHeight) })
	local iconName = Icons.Resolve(icon)
	local button = C.Button(container, if iconName then "" else icon, onClick, {
		Kind = kind,
		TextSize = math.floor(d * 0.47),
		Radius = math.floor(d * 0.3),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(d, d + 4),
		Confirm = false,
		Icon = iconName,
		IconSize = math.floor(d * 0.6 + 0.5),
	})
	if caption then
		C.Title(container, caption, {
			Name = "Caption",
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.new(1, 0, 0, 18),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 4,
		}, 1.5)
	end
	return container, button
end

-- Small square toolbar button (sort/filter/modes). Use C.SetToolActive to toggle.
function C.ToolButton(parent: Instance, glyph: string, onClick: (() -> ())?, props: { [string]: any }?)
	local iconName = Icons.Resolve(glyph)
	local button = C.Button(parent, if iconName then "" else glyph, onClick, {
		Kind = "Dark",
		TextSize = 20,
		Radius = Theme.Radius.Tool,
		Size = UDim2.fromOffset(40, 44),
		Confirm = false,
		Icon = iconName,
		IconSize = 26,
	})
	apply(button, props)
	return button
end

function C.SetToolActive(button: Instance, active: boolean)
	C.SetKind(button, if active then "Primary" else "Dark")
	C.SetSelected(button, active)
end

-- HUD widgets -----------------------------------------------------------------------------------------------------

--[[
	Currency pill: dark pill with a round badge overlapping its left edge, big outlined number and an optional "+".
	`icon` is a glyph (Theme.Icons.Yen) or icon name ("yen"). GlyphColor tints the icon; an Ink GlyphColor (a dark
	glyph on a light badge, e.g. Gold) keeps the outlined icon white. Returns { Frame, Set(text), Icon }.
]]
function C.CurrencyPill(parent: Instance, icon: string, color: Color3, width: number?, options: { Plus: (() -> ())?, GlyphColor: Color3?, Height: number? }?)
	local o = options or {}
	local w, h = width or 200, o.Height or 40
	local container = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h + 4) })
	local bar = C.Frame(container, { BackgroundColor3 = P.Panel, BackgroundTransparency = 0.1, Position = UDim2.fromOffset(16, 2), Size = UDim2.new(1, -16, 0, h) })
	C.Corner(bar, UDim.new(0.5, 0))
	C.Stroke(bar, P.Ink, Theme.Stroke.Button)
	local badgeSize = h + 4
	local badge = C.Frame(container, { BackgroundColor3 = color, Size = UDim2.fromOffset(badgeSize, badgeSize), ZIndex = 3 })
	C.Corner(badge, UDim.new(0.5, 0))
	C.Stroke(badge, P.Ink, Theme.Stroke.Button)
	C.Shine(badge, badgeSize // 2, 0.8)
	local iconName = Icons.Resolve(icon)
	local glyph
	if iconName then
		local color = if o.GlyphColor and o.GlyphColor ~= P.Ink then o.GlyphColor else P.White
		glyph = centeredIcon(badge, iconName, math.floor(badgeSize * 0.74 + 0.5), {
			ZIndex = 4,
			Color = color,
			Accent = if color == P.Cyan then P.White else nil,
		})
	else
		glyph = C.Title(badge, icon, {
			Size = UDim2.fromScale(1, 1),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextSize = 22,
			TextColor3 = o.GlyphColor or P.White,
			ZIndex = 4,
		}, 2)
	end
	local value = C.Number(bar, "0", {
		Position = UDim2.fromOffset(badgeSize - 8, 0),
		Size = UDim2.new(1, -(badgeSize - 8) - (if o.Plus then 40 else 10), 1, 0),
		TextSize = 24,
		ZIndex = 3,
	})
	if o.Plus then
		local plus = C.Button(bar, "", o.Plus, {
			Kind = "Primary",
			TextSize = 22,
			Radius = 15,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -5, 0.5, 0),
			Size = UDim2.fromOffset(30, 32),
			StrokeThickness = 2.5,
			Confirm = false,
			ZIndex = 4,
			Icon = "plus",
			IconSize = 18,
		})
		plus.Name = "Plus"
	end
	return {
		Frame = container,
		Icon = glyph,
		Set = function(text: string)
			value.Text = text
		end,
	}
end

--[[
	Currency counter box (HUD): a rounded-square charcoal tile like the side menu buttons (light border, soft black
	shadow) with the currency icon on the left (full-colour PNG from UI/IconAssets, else the vector coin, in
	Theme.IconColors) and the amount on the right (scaled down to fit long numbers).
	Same API as C.CurrencyPill: { Frame, Box, Icon, Set(text) }. options: { Height, Plus }.
]]
function C.CurrencyBox(parent: Instance, icon: string, width: number?, options: { Height: number?, Plus: (() -> ())? }?)
	local o = options or {}
	local w, h = width or 156, o.Height or 58
	local container = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h + 4) })
	local box = C.Frame(container, { Name = "Box", BackgroundColor3 = P.White, Size = UDim2.fromOffset(w, h), ZIndex = 2 })
	local name = Icons.Resolve(icon) or icon
	local tint = Theme.IconColors[name] or P.White
	C.MenuTile(box, 16, tint)
	local glyph = C.Icon(box, name, {
		Size = h - 12,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 7, 0.5, 0),
		Color = tint,
		Accent = tint:Lerp(P.White, 0.55),
		ZIndex = 3,
	})
	local right = if o.Plus then 44 else 12
	local value = C.Number(box, "0", {
		Name = "Value",
		Position = UDim2.fromOffset(h + 2, 0),
		Size = UDim2.new(1, -(h + 2) - right, 1, 0),
		TextSize = 28,
		TextScaled = true,
		ZIndex = 3,
	})
	C.Create("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 12, Parent = value })
	if o.Plus then
		local plus = C.Button(box, "", o.Plus, {
			Kind = "Dark",
			Radius = 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(32, 34),
			StrokeThickness = 2,
			Confirm = false,
			ZIndex = 4,
			Icon = "plus",
			IconSize = 18,
		})
		plus.Name = "Plus"
	end
	return {
		Frame = container,
		Box = box,
		Icon = glyph,
		Set = function(text: string)
			value.Text = text
		end,
	}
end

-- Capacity counter pill ("▦ 87/120"). state: "Normal" | "Near" (≥90%) | "Full".
function C.Counter(parent: Instance, glyph: string, props: { [string]: any }?)
	local pill = C.Frame(parent, { BackgroundColor3 = P.PanelAlt, Size = UDim2.fromOffset(120, 34) })
	apply(pill, props)
	C.Corner(pill, UDim.new(0.5, 0))
	local stroke = C.Stroke(pill, P.Ink, 2.5)
	local iconName = Icons.Resolve(glyph)
	local icon = if iconName
		then Icons.Create(iconName, pill, { Size = 20, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
		else C.Title(pill, glyph, { Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(20, 34), TextSize = 16, TextXAlignment = Enum.TextXAlignment.Center }, 1.5)
	local value = C.Number(pill, "0/0", { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -40, 1, 0), TextSize = 18 })
	return {
		Frame = pill,
		Set = function(text: string, state: string?)
			value.Text = text
			local full = state == "Full"
			pill.BackgroundColor3 = if full then P.Ice else P.PanelAlt
			value.TextColor3 = if full then P.Ink else P.White
			if iconName then
				Icons.SetColors(icon, { Color = if full then P.Blue500 else P.White })
			else
				icon.TextColor3 = if full then P.Ink else P.White
			end
			stroke.Color = if state == "Near" then P.Cyan else P.Ink
		end,
	}
end

-- Lists, bars, tabs, toggles ---------------------------------------------------------------------------------------

function C.Scroll(parent: Instance, props: { [string]: any }?)
	local scroll = C.Create("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, -- content never sits under the scrollbar
		ScrollBarImageColor3 = P.Blue400,
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

-- Pill progress bar: ink track, cyan -> blue fill with gloss, outlined caption.
function C.ProgressBar(parent: Instance, _color: Color3?, props: { [string]: any }?)
	local back = C.Frame(parent, { BackgroundColor3 = P.Ink, Size = UDim2.new(1, 0, 0, 18) })
	apply(back, props)
	C.Corner(back, UDim.new(0.5, 0))
	C.Stroke(back, P.Ink, 2.5)
	local fill = C.Frame(back, { BackgroundColor3 = P.White, Size = UDim2.fromScale(0, 1) })
	C.Corner(fill, UDim.new(0.5, 0))
	C.Gradient(fill, G.Progress.Top, G.Progress.Bottom, 0)
	C.Shine(fill, 9, 0.75)
	local text = C.Title(back, "", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 14, ZIndex = 3 }, 1.5)
	return {
		Frame = back,
		Set = function(fraction: number, caption: string?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			fill.Visible = fraction > 0.001
			text.Text = caption or ""
		end,
	}
end

-- Segmented tab strip in an ink well. Returns { Select(name), Frame }.
function C.Tabs(parent: Instance, names: { string }, onSelect: (string) -> ())
	local well = C.Frame(parent, { BackgroundColor3 = P.Bg, Size = UDim2.fromOffset(#names * 140 + 8, 44) })
	C.Corner(well, Theme.Radius.Header)
	C.Stroke(well, P.Ink, 3)
	C.Padding(well, 4)
	C.List(well, Enum.FillDirection.Horizontal, 4)
	local tabs = {}
	local api = {}
	function api.Select(name: string)
		for tabName, tab in tabs do
			local active = tabName == name
			tab.Button.BackgroundTransparency = if active then 0 else 1
			tab.Gradient.Enabled = active
			tab.Label.TextColor3 = if active then P.White else P.TextDim
			tab.Stroke.Enabled = active
			tab.Underline.Visible = active
		end
		onSelect(name)
	end
	for i, name in names do
		local button = C.Create("TextButton", {
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = P.White,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(136, 36),
			LayoutOrder = i,
			Parent = well,
		})
		C.Corner(button, Theme.Radius.Tool)
		local gradient = C.Gradient(button, G.Primary.Top, G.Primary.Bottom)
		local label = C.Label(button, name, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, Font = Theme.Fonts.Bold, TextSize = 18 })
		local stroke = C.Outline(label, 2)
		-- Gold underline marks the active tab (yellow = selected).
		local underline = C.Frame(button, { Name = "Underline", BackgroundColor3 = P.Gold, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.new(1, -24, 0, 3), Visible = false, ZIndex = 3 })
		C.Corner(underline, UDim.new(0.5, 0))
		tabs[name] = { Button = button, Gradient = gradient, Label = label, Stroke = stroke, Underline = underline }
		button.Activated:Connect(function()
			api.Select(name)
		end)
	end
	api.Frame = well
	return api
end

-- Pill toggle (settings). Returns the button; onClick receives nothing (caller flips its own state).
function C.Toggle(parent: Instance, on: boolean, onClick: (() -> ())?, props: { [string]: any }?)
	local button = C.Create("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = if on then P.Blue500 else P.PanelAlt,
		Size = UDim2.fromOffset(64, 32),
		Parent = parent,
	})
	apply(button, props)
	C.Corner(button, UDim.new(0.5, 0))
	C.Stroke(button, P.Ink, 3)
	local knob = C.Frame(button, {
		BackgroundColor3 = P.White,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = if on then UDim2.new(1, -28, 0.5, 0) else UDim2.new(0, 4, 0.5, 0),
		Size = UDim2.fromOffset(24, 24),
		ZIndex = 3,
	})
	C.Corner(knob, UDim.new(0.5, 0))
	C.Stroke(knob, P.Ink, 2)
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

-- Window building blocks -------------------------------------------------------------------------------------------

-- Section heading inside list windows: upper-case title over a short cyan underline.
function C.Section(parent: Instance, text: string, order: number?, props: { [string]: any }?)
	local holder = C.Frame(parent, { Name = "Section", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 32), LayoutOrder = order or 0 })
	apply(holder, props)
	C.Title(holder, string.upper(text), { Name = "Text", Size = UDim2.new(1, 0, 0, 26), TextSize = 18, TextColor3 = P.Ice }, 2)
	local line = C.Frame(holder, { Name = "Underline", BackgroundColor3 = P.Cyan, Position = UDim2.new(0, 0, 1, -4), Size = UDim2.fromOffset(44, 3) })
	C.Corner(line, UDim.new(0.5, 0))
	return holder
end

--[[
	Empty / "not available yet" state: a title and a short message, centred (no icon: the window's menu button
	already shows it). Used whenever a window has nothing real to show, so a menu button never opens a blank or
	fake screen. (`_icon` is kept in the signature so callers can stay unchanged.)
]]
function C.EmptyState(parent: Instance, _icon: string, title: string, message: string, props: { [string]: any }?)
	local holder = C.Frame(parent, { Name = "EmptyState", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 150) })
	apply(holder, props)
	C.Title(holder, title, {
		Name = "Title",
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 0, 34),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, 2.5)
	C.Frame(holder, { Name = "GoldLine", BackgroundColor3 = P.Gold, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 72), Size = UDim2.fromOffset(56, 3) })
	C.Label(holder, message, {
		Name = "Message",
		Position = UDim2.new(0.1, 0, 0, 86),
		Size = UDim2.new(0.8, 0, 0, 60),
		TextSize = 17,
		TextColor3 = P.TextDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	return holder
end

-- Stat tile: small caption on top, big number under it. Returns (frame, value label).
function C.StatTile(parent: Instance, caption: string, value: string, props: { [string]: any }?)
	local frame = C.Frame(parent, { Name = "Stat", BackgroundColor3 = P.PanelAlt, Size = UDim2.fromOffset(150, 60) })
	apply(frame, props)
	C.Corner(frame, 10)
	C.Stroke(frame, P.Ink, 2)
	C.Title(frame, string.upper(caption), { Name = "Caption", Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -16, 0, 16), TextSize = 12, TextColor3 = P.TextDim }, 1.5)
	local label = C.Number(frame, value, {
		Name = "Value",
		Position = UDim2.fromOffset(10, 22),
		Size = UDim2.new(1, -16, 0, 32),
		TextSize = 22,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return frame, label
end

--[[
	Progress row with a claim button (quests, achievements).
	info = { Title, Description, Rewards (text), Progress, Target, ProgressText?, CanClaim, Claimed, Order, Name? }
]]
function C.ClaimRow(parent: Instance, info, onClaim: (() -> ())?)
	local row = C.Row(parent, { Name = info.Name or "ClaimRow", Size = UDim2.new(1, -8, 0, 92), LayoutOrder = info.Order or 0 })
	if info.CanClaim and not info.Claimed then
		row:FindFirstChildOfClass("UIStroke").Color = P.Cyan
	end
	C.Title(row, info.Title, { Name = "RowTitle", Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -170, 0, 22), TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd }, 2)
	C.Label(row, info.Description, { Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -170, 0, 18), TextSize = 14, TextColor3 = P.TextDim, TextTruncate = Enum.TextTruncate.AtEnd })
	C.Label(row, "Rewards: " .. info.Rewards, { Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -170, 0, 18), TextSize = 13, TextColor3 = P.Cyan })
	local bar = C.ProgressBar(row, nil, { Position = UDim2.fromOffset(12, 68), Size = UDim2.new(1, -170, 0, 14) })
	local target = math.max(info.Target, 1)
	bar.Set(math.min(info.Progress, target) / target, info.ProgressText or ("%d / %d"):format(math.min(info.Progress, target), target))
	local claimable = info.CanClaim and not info.Claimed
	local button = C.Button(row, if info.Claimed then "Claimed" elseif info.CanClaim then "Claim" else "In progress", if claimable then onClaim else nil, {
		Name = "Claim",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(140, 44),
		TextSize = 18,
		Kind = if claimable then "Primary" else "Dark",
		Confirm = false,
	})
	if not claimable then
		C.SetDisabled(button, true)
	end
	return row
end

-- Text input: dark rounded box with a light outline (cyan while focused) and a dim placeholder.
function C.TextInput(parent: Instance, placeholder: string, props: { [string]: any }?)
	local box = C.Create("TextBox", {
		Name = "Input",
		BackgroundColor3 = P.Bg,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = placeholder,
		PlaceholderColor3 = P.TextMuted,
		TextColor3 = P.White,
		Font = Theme.Fonts.Title,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Size = UDim2.fromOffset(320, 52),
		Parent = parent,
	})
	apply(box, props)
	C.Corner(box, Theme.Radius.Button)
	local stroke = C.Stroke(box, P.White, 2.5)
	stroke.Transparency = 0.35
	C.Create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = box })
	box.Focused:Connect(function()
		stroke.Color = P.Cyan
		stroke.Transparency = 0
	end)
	box.FocusLost:Connect(function()
		stroke.Color = P.White
		stroke.Transparency = 0.35
	end)
	return box
end

-- Windows -------------------------------------------------------------------------------------------------------------

--[[
	Standard window (one template for every menu):
	  Frame   transparent holder: position, size, responsive UIScale, the dark outer outline
	  Group   CanvasGroup with the whole window inside, so it can fade (GroupTransparency) while it scales
	  Header  bright blue gradient title bar with speed-lines, a thin gold line under it, the title and a red round
	          close button (X) inside the bar (it is also the drag handle). No icon: the menu button already has it.
	  Content dark navy area for the window's own UI; a thin gold rim runs inside the window border
	Returns { Frame, Group, Content, Title, Header, CloseButton }.
]]
function C.Window(parent: Instance, title: string, size: UDim2?)
	local frame = C.Frame(parent, {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = size or Theme.WindowSize,
		Visible = false,
		BackgroundTransparency = 1,
		ZIndex = 10,
	})
	C.Corner(frame, Theme.Radius.Window)
	C.Stroke(frame, P.Ink, Theme.Stroke.Window)
	C.Create("UISizeConstraint", { MaxSize = Vector2.new(960, 640), Parent = frame })
	local group = C.Create("CanvasGroup", {
		Name = "Group",
		BackgroundColor3 = P.White,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 10,
		Parent = frame,
	})
	C.Corner(group, Theme.Radius.Window)
	C.Gradient(group, G.WindowBody.Top, G.WindowBody.Bottom)
	local rim = C.Frame(group, { Name = "GoldRim", BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), ZIndex = 11 })
	C.Corner(rim, Theme.Radius.Window - 3)
	local rimStroke = C.Stroke(rim, P.Gold, 2)
	rimStroke.Transparency = 0.35

	local header = C.Frame(group, { Name = "Header", BackgroundColor3 = P.White, Size = UDim2.new(1, 0, 0, 56), ClipsDescendants = true, Active = true, ZIndex = 12 })
	C.Gradient(header, G.WindowHeader.Top, G.WindowHeader.Bottom)
	C.SpeedLines(header, 8, { Start = 0.55, Spacing = 28, ZIndex = 13 })
	C.Frame(header, { Name = "GoldLine", BackgroundColor3 = P.Gold, Position = UDim2.new(0, 0, 1, -3), Size = UDim2.new(1, 0, 0, 3), ZIndex = 14 })

	local titleLabel = C.Label(header, title, {
		Font = Theme.Fonts.Display,
		TextSize = Theme.TextSize.Display,
		Position = UDim2.fromOffset(20, 1),
		Size = UDim2.new(1, -130, 1, 0),
		ZIndex = 15,
	})
	C.Outline(titleLabel, 3)

	local close = C.Button(group, "", nil, {
		Kind = "Close",
		Icon = "close",
		IconSize = 20,
		TextSize = 24,
		Radius = 20,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0, 27),
		Size = UDim2.fromOffset(40, 42),
		StrokeThickness = 2.5,
		Confirm = false,
		ZIndex = 20,
	})
	close.Name = "Close"
	local content = C.Frame(group, { Name = "Content", BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 70), Size = UDim2.new(1, -32, 1, -84), ZIndex = 11 })
	return {
		Frame = frame,
		Group = group,
		Content = content,
		Title = titleLabel,
		Header = header,
		CloseButton = close,
	}
end

-- Unit cards ---------------------------------------------------------------------------------------------------------

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

-- Padlock drawn from primitives (emoji locks ignore TextColor3).
function C.LockBadge(parent: Instance, position: UDim2, zIndex: number?)
	local z = zIndex or 6
	local badge = C.Frame(parent, { BackgroundColor3 = P.Ink, Position = position, Size = UDim2.fromOffset(22, 22), ZIndex = z })
	C.Corner(badge, UDim.new(0.5, 0))
	C.Stroke(badge, P.White, 2)
	centeredIcon(badge, "lock", 16, { ZIndex = z + 1, Position = UDim2.fromScale(0.5, 0.47) })
	return badge
end

--[[
	Unit card: dark tile, portrait well (initials until art exists), thin rarity strip, level, stars, name,
	equipped check, lock, optional NEW tag and footer (e.g. summon chance or reveal rarity).
	info: { Name, Rarity, Level, Stars, Locked, Equipped, Trait?, New?, Footer?, FooterColor?, FooterFont?, Badge? }
	(`Badge` is the legacy name of Footer.)
]]
function C.UnitCard(
	parent: Instance,
	info: {
		Name: string,
		Rarity: string,
		Level: number,
		Stars: number,
		Locked: boolean,
		Equipped: boolean,
		Trait: string?,
		New: boolean?,
		Footer: string?,
		FooterColor: Color3?,
		FooterFont: Enum.Font?,
		FooterSize: number?,
		Badge: string?,
		HideLevel: boolean?,
	},
	onClick: (() -> ())?
)
	local rarityColor = Theme.Rarity(info.Rarity)
	local footer = info.Footer or info.Badge
	local card = C.Create("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = P.PanelAlt, Parent = parent })
	C.Corner(card, Theme.Radius.Card)
	C.Stroke(card, P.Ink, Theme.Stroke.Card)
	C.Create("UIScale", { Parent = card })

	local portrait = C.Frame(card, { Name = "Portrait", BackgroundColor3 = P.White, Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 76), ZIndex = 2 })
	C.Corner(portrait, 10)
	C.Gradient(portrait, Theme.Gradients.Portrait.Top, Theme.Gradients.Portrait.Bottom)
	C.Title(portrait, initials(info.Name), {
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Theme.Fonts.Display,
		TextSize = 28,
		TextColor3 = P.White,
		ZIndex = 3,
	}, 2.5)
	if not info.HideLevel then
		C.Title(portrait, "Lv " .. info.Level, { Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(60, 16), TextSize = 13, ZIndex = 4 }, 1.5)
	end
	if info.Stars > 0 then
		local stars = C.Frame(portrait, {
			Name = "Stars",
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -2),
			Size = UDim2.new(1, 0, 0, 14),
			ZIndex = 4,
		})
		C.List(stars, Enum.FillDirection.Horizontal, 1, Enum.HorizontalAlignment.Center)
		-- No outline: the portrait is already dark, and it halves the instances on big inventories.
		for i = 1, info.Stars do
			Icons.Create("star", stars, { Size = 14, LayoutOrder = i, ZIndex = 4, Outline = false, Color = if info.Stars >= 5 then P.Cyan else P.White })
		end
	end
	-- Rarity accent: thin strip under the portrait.
	local strip = C.Frame(card, { BackgroundColor3 = rarityColor, Position = UDim2.fromOffset(8, 87), Size = UDim2.new(1, -16, 0, 5), ZIndex = 2 })
	C.Corner(strip, UDim.new(0.5, 0))

	C.Title(card, info.Name, {
		Font = Theme.Fonts.Body,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if footer then -26 else -6),
		Size = UDim2.new(1, -8, 0, 20),
		TextSize = 13,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 3,
	}, 1.5).UIStroke.Color = Theme.Darken(rarityColor, 0.4)
	if footer then
		C.Title(card, footer, {
			Font = info.FooterFont or Theme.Fonts.Number,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -8, 0, 22),
			TextSize = info.FooterSize or 19,
			TextColor3 = info.FooterColor or P.White,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
		}, 2)
	end

	if info.Equipped then
		local check = C.Frame(card, { BackgroundColor3 = P.White, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(26, 26), ZIndex = 6 })
		C.Corner(check, UDim.new(0.5, 0))
		C.Stroke(check, P.Ink, 2.5)
		C.Gradient(check, Theme.Gradients.Primary.Top, Theme.Gradients.Primary.Bottom)
		centeredIcon(check, "check", 18, { ZIndex = 7 })
	end
	if info.Locked then
		C.LockBadge(card, UDim2.fromOffset(6, 38), 6) -- left edge of the portrait, clear of the star row
	end
	if info.New then
		local tag = C.Frame(card, { BackgroundColor3 = P.Cyan, Position = UDim2.new(1, -46, 0, 10), Size = UDim2.fromOffset(40, 16), ZIndex = 6 })
		C.Corner(tag, UDim.new(0.5, 0))
		C.Stroke(tag, P.Ink, 2)
		C.Label(tag, "NEW", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, TextColor3 = P.Ink, Font = Theme.Fonts.Bold, ZIndex = 7 })
	end
	if onClick then
		card.Activated:Connect(onClick)
	end
	return card
end

-- Selection feedback on a unit card: "Selected" (inspecting) or "Marked" (chosen for fuse/sell).
function C.HighlightCard(card: Instance, mode: string?)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	local scale = card:FindFirstChildOfClass("UIScale")
	if not stroke then
		return
	end
	if mode == "Selected" then
		stroke.Color = P.Gold -- yellow accent = selected
		stroke.Thickness = 3
		if scale then
			scale.Scale = 1.04
		end
	elseif mode == "Marked" then
		stroke.Color = P.Cyan
		local overlay = C.Frame(card, { BackgroundColor3 = P.Blue500, BackgroundTransparency = 0.5, Size = UDim2.fromScale(1, 1), ZIndex = 8 })
		C.Corner(overlay, Theme.Radius.Card)
		centeredIcon(overlay, "check", 40, { ZIndex = 9 })
	end
end

return C
