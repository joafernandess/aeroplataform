--[[
	Render (Lune)
	Approximates Roblox's 2D GUI layout for the subset the game uses and emits absolutely-positioned HTML.
	Supported: UDim2 Size/Position, AnchorPoint, Visible, ZIndex (sibling), UIListLayout, UIGridLayout,
	UIPadding, UICorner, UIStroke, UISizeConstraint, AutomaticSize, ClipsDescendants/ScrollingFrame clipping,
	UIGradient colours, Rotation (around the centre, also combined with a UIScale on the same object), text props,
	ImageLabel/ImageButton (a local file path renders as <img>, tinted by ImageColor3; an rbxassetid:// shows a
	dashed placeholder box). Not supported: BillboardGuis (3D), UIGradient transparency.
]]

local process = require("@lune/process")

local Fake = require("./FakeRoblox")

local Render = {}

local function enumName(value): string
	return if value == nil then "" else tostring(value.Name)
end

local function rgba(c, transparency: number?): string
	local a = 1 - (transparency or 0)
	return string.format("rgba(%d,%d,%d,%.3f)", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), a)
end

local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function udim(u, size: number): number
	return u.Scale * size + u.Offset
end

local function findComponent(inst, className)
	for _, child in inst:GetChildren() do
		if Fake.Data(child).ClassName == className then
			return child
		end
	end
	return nil
end

local function isRenderable(inst): boolean
	return Fake.IsGui(inst) and inst.Visible ~= false
end

local function guiChildren(inst, hasLayout: boolean)
	local list = {}
	for _, child in inst:GetChildren() do
		if isRenderable(child) then
			table.insert(list, child)
		end
	end
	table.sort(list, function(a, b)
		if hasLayout then
			if a.LayoutOrder ~= b.LayoutOrder then
				return a.LayoutOrder < b.LayoutOrder
			end
		elseif a.ZIndex ~= b.ZIndex then
			return a.ZIndex < b.ZIndex
		end
		return Fake.Data(a).Order < Fake.Data(b).Order
	end)
	return list
end

local computeChildRects

-- Size of `inst` inside a container rect, including AutomaticSize and UISizeConstraint.
local function resolveSize(inst, cw: number, ch: number): (number, number)
	local w = udim(inst.Size.X, cw)
	local h = udim(inst.Size.Y, ch)
	local constraint = findComponent(inst, "UISizeConstraint")
	if constraint then
		local max = constraint.MaxSize
		local min = constraint.MinSize
		if max then
			w, h = math.min(w, max.X), math.min(h, max.Y)
		end
		if min then
			w, h = math.max(w, min.X), math.max(h, min.Y)
		end
	end
	local auto = enumName(inst.AutomaticSize)
	if auto == "Y" or auto == "XY" then
		local _, extent = computeChildRects(inst, { x = 0, y = 0, w = w, h = h })
		h = math.max(h, extent)
	end
	return w, h
end

-- Returns { {child, rect} }, contentExtent (height used by children, incl. padding).
function computeChildRects(inst, rect)
	local list = findComponent(inst, "UIListLayout")
	local grid = findComponent(inst, "UIGridLayout")
	local padding = findComponent(inst, "UIPadding")
	local pt, pb, pl, pr = 0, 0, 0, 0
	if padding then
		pt, pb = udim(padding.PaddingTop, rect.h), udim(padding.PaddingBottom, rect.h)
		pl, pr = udim(padding.PaddingLeft, rect.w), udim(padding.PaddingRight, rect.w)
	end
	local content = { x = rect.x + pl, y = rect.y + pt, w = rect.w - pl - pr, h = rect.h - pt - pb }
	local children = guiChildren(inst, list ~= nil or grid ~= nil)
	local out = {}
	local maxBottom = content.y

	if list then
		local gap = udim(list.Padding, if enumName(list.FillDirection) == "Horizontal" then content.w else content.h)
		local halign = enumName(list.HorizontalAlignment)
		if enumName(list.FillDirection) == "Horizontal" then
			local sizes, total = {}, 0
			for i, child in children do
				local w, h = resolveSize(child, content.w, content.h)
				sizes[i] = { w, h }
				total += w + (if i > 1 then gap else 0)
			end
			local x = content.x
			if halign == "Center" then
				x = content.x + (content.w - total) / 2
			elseif halign == "Right" then
				x = content.x + content.w - total
			end
			for i, child in children do
				local w, h = sizes[i][1], sizes[i][2]
				table.insert(out, { child, { x = x, y = content.y, w = w, h = h } })
				maxBottom = math.max(maxBottom, content.y + h)
				x += w + gap
			end
		else
			local y = content.y
			for _, child in children do
				local w, h = resolveSize(child, content.w, content.h)
				local x = content.x
				if halign == "Center" then
					x = content.x + (content.w - w) / 2
				elseif halign == "Right" then
					x = content.x + content.w - w
				end
				table.insert(out, { child, { x = x, y = y, w = w, h = h } })
				maxBottom = math.max(maxBottom, y + h)
				y += h + gap
			end
		end
	elseif grid then
		local cw, ch = udim(grid.CellSize.X, content.w), udim(grid.CellSize.Y, content.h)
		local gx, gy = udim(grid.CellPadding.X, content.w), udim(grid.CellPadding.Y, content.h)
		local perRow = math.max(1, math.floor((content.w + gx) / (cw + gx)))
		for i, child in children do
			local col = (i - 1) % perRow
			local row = (i - 1) // perRow
			local r = { x = content.x + col * (cw + gx), y = content.y + row * (ch + gy), w = cw, h = ch }
			table.insert(out, { child, r })
			maxBottom = math.max(maxBottom, r.y + ch)
		end
	else
		for _, child in children do
			local w, h = resolveSize(child, content.w, content.h)
			local anchor = child.AnchorPoint
			local x = content.x + udim(child.Position.X, content.w) - anchor.X * w
			local y = content.y + udim(child.Position.Y, content.h) - anchor.Y * h
			table.insert(out, { child, { x = x, y = y, w = w, h = h } })
			maxBottom = math.max(maxBottom, y + h)
		end
	end
	return out, (maxBottom - rect.y) + pb
end

local EMOJI = "'Noto Color Emoji'"
local FONTS = {
	GothamBlack = { "Inter", 900 },
	GothamBold = { "Inter", 700 },
	GothamMedium = { "Inter", 500 },
	BuilderSansExtraBold = { "Inter", 800 },
	BuilderSansBold = { "Inter", 700 },
	BuilderSans = { "Inter", 500 },
	Gotham = { "Inter", 400 },
	FredokaOne = { "'Fredoka'", 600 },
	LuckiestGuy = { "'Luckiest Guy'", 400 },
	Legacy = { "Inter", 400 },
}

-- Outline ring made of text-shadows (Roblox UIStroke with ApplyStrokeMode = Contextual on text).
local function outlineShadow(color: string, thickness: number): string
	local parts = {}
	local steps = 16
	for i = 0, steps - 1 do
		local a = (i / steps) * math.pi * 2
		table.insert(parts, string.format("%.2fpx %.2fpx 0 %s", math.cos(a) * thickness, math.sin(a) * thickness, color))
	end
	return table.concat(parts, ",")
end

local function strokes(inst)
	local border, text = nil, nil
	for _, child in inst:GetChildren() do
		if Fake.Data(child).ClassName == "UIStroke" and child.Enabled ~= false then
			local mode = enumName(child.ApplyStrokeMode)
			local cls = Fake.Data(inst).ClassName
			local isText = cls == "TextLabel" or cls == "TextButton" or cls == "TextBox"
			if mode == "Border" or not isText then
				border = border or child
			else
				text = text or child
			end
		end
	end
	return border, text
end

local function textHtml(inst, rect, placeholder: boolean?): string
	local text = tostring(if placeholder then inst.PlaceholderText else inst.Text or "")
	if text == "" then
		return ""
	end
	local xa = enumName(inst.TextXAlignment)
	local ya = enumName(inst.TextYAlignment)
	local size = inst.TextSize
	if inst.TextScaled then
		local longest = 0
		for line in string.gmatch(text, "[^\n]+") do
			longest = math.max(longest, utf8.len(line) or #line)
		end
		size = math.min(rect.h * 0.82, rect.w / math.max(longest, 1) * 1.75, 100)
		for _, child in inst:GetChildren() do
			if Fake.Data(child).ClassName == "UITextSizeConstraint" then
				size = math.clamp(size, child.MinTextSize or 1, child.MaxTextSize or 100)
			end
		end
	end
	local stroke = ""
	local _, textStroke = strokes(inst)
	if textStroke then
		stroke = "text-shadow:" .. outlineShadow(rgba(textStroke.Color, textStroke.Transparency), textStroke.Thickness) .. ";"
	else
		local strokeT = inst.TextStrokeTransparency or 1
		if strokeT < 1 then
			stroke = "text-shadow:" .. outlineShadow(rgba(inst.TextStrokeColor3 or { R = 0, G = 0, B = 0 }, strokeT), 1.2) .. ";"
		end
	end
	local justify = if xa == "Left" then "flex-start" elseif xa == "Right" then "flex-end" else "center"
	local align = if ya == "Top" then "flex-start" elseif ya == "Bottom" then "flex-end" else "center"
	local wrap = if inst.TextWrapped or inst.TextScaled then "white-space:normal;" else "white-space:nowrap;"
	local body = escape(text)
	if enumName(inst.TextTruncate) == "AtEnd" then
		wrap ..= "overflow:hidden;"
		body = '<span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:100%">' .. body .. "</span>"
	end
	return string.format(
		'<div class="t" style="justify-content:%s;align-items:%s;text-align:%s;font-size:%.1fpx;font-family:%s;font-weight:%d;color:%s;%s%s">%s</div>',
		justify,
		align,
		string.lower(if xa == "" then "center" else xa),
		size,
		(FONTS[enumName(inst.Font)] or FONTS.Gotham)[1] .. "," .. EMOJI,
		(FONTS[enumName(inst.Font)] or FONTS.Gotham)[2],
		rgba(if placeholder then inst.PlaceholderColor3 else inst.TextColor3, inst.TextTransparency),
		wrap,
		stroke,
		body
	)
end

local FIT = { Fit = "contain", Crop = "cover", Stretch = "fill" }

-- ImageLabel content: local files render (tinted like Roblox's ImageColor3 multiply); asset ids can't be
-- fetched offline, so they show a dashed placeholder box.
local function imageHtml(inst): string
	local image = tostring(inst.Image or "")
	if image == "" then
		return ""
	end
	local opacity = 1 - (inst.ImageTransparency or 0)
	if string.match(image, "^rbxasset") or string.match(image, "^https?:") then
		return string.format(
			'<div class="t" style="border:1.5px dashed rgba(255,255,255,%.2f);border-radius:inherit;justify-content:center;align-items:center;font:700 9px Inter,sans-serif;color:rgba(255,255,255,.8);box-sizing:border-box" title="%s">IMG</div>',
			0.9 * opacity,
			escape(image)
		)
	end
	local path = if string.sub(image, 1, 1) == "/" then image else process.cwd .. "/" .. image
	local url = "file://" .. path:gsub("^file://", "")
	local fit = FIT[enumName(inst.ScaleType)] or "fill"
	local parts = {
		string.format('<img src="%s" style="position:absolute;inset:0;width:100%%;height:100%%;object-fit:%s;opacity:%.3f">', url, fit, opacity),
	}
	local tint = inst.ImageColor3
	if tint and (tint.R < 0.999 or tint.G < 0.999 or tint.B < 0.999) then
		local size = if fit == "fill" then "100% 100%" else fit
		table.insert(
			parts,
			string.format(
				'<div style="position:absolute;inset:0;background:%s;mix-blend-mode:multiply;opacity:%.3f;-webkit-mask:url(%s) center/%s no-repeat;mask:url(%s) center/%s no-repeat"></div>',
				rgba(tint),
				opacity,
				url,
				size,
				url,
				size
			)
		)
	end
	return table.concat(parts)
end

local function nodeHtml(inst, rect, parentRect): string
	local styles = {
		string.format("left:%.1fpx;top:%.1fpx;width:%.1fpx;height:%.1fpx;", rect.x - parentRect.x, rect.y - parentRect.y, rect.w, rect.h),
	}
	if inst.BackgroundTransparency < 1 then
		local gradient = findComponent(inst, "UIGradient")
		if gradient and gradient.Enabled ~= false then
			-- UIGradient multiplies the background colour; Rotation 0 = left->right, 90 = top->bottom.
			local bg = inst.BackgroundColor3
			local stops = {}
			if gradient.Color then
				for _, keypoint in gradient.Color.Keypoints do
					local c = keypoint.Value
					local mixed = { R = bg.R * c.R, G = bg.G * c.G, B = bg.B * c.B }
					table.insert(stops, string.format("%s %.1f%%", rgba(mixed, inst.BackgroundTransparency), keypoint.Time * 100))
				end
			else
				-- Transparency-only gradient: alpha = (1 - BackgroundTransparency) * (1 - keypoint).
				for _, keypoint in gradient.Transparency.Keypoints do
					local t = 1 - (1 - inst.BackgroundTransparency) * (1 - keypoint.Value)
					table.insert(stops, string.format("%s %.1f%%", rgba(bg, t), keypoint.Time * 100))
				end
			end
			table.insert(styles, string.format("background:linear-gradient(%ddeg,%s);", (gradient.Rotation or 0) + 90, table.concat(stops, ",")))
		else
			table.insert(styles, "background:" .. rgba(inst.BackgroundColor3, inst.BackgroundTransparency) .. ";")
		end
	end
	local corner = findComponent(inst, "UICorner")
	if corner then
		local r = udim(corner.CornerRadius, math.min(rect.w, rect.h))
		table.insert(styles, string.format("border-radius:%.1fpx;", math.min(r, math.min(rect.w, rect.h) / 2)))
	end
	local stroke = strokes(inst)
	if stroke then
		table.insert(styles, string.format("box-shadow:0 0 0 %.1fpx %s;", stroke.Thickness, rgba(stroke.Color, stroke.Transparency)))
	end
	local uiScale = findComponent(inst, "UIScale")
	local scale = if uiScale then uiScale.Scale else 1
	local rotation = tonumber(inst.Rotation) or 0
	local scaled, rotated = math.abs(scale - 1) > 1e-3, math.abs(rotation) > 1e-3
	if scaled or rotated then
		-- Roblox scales around the AnchorPoint (Position stays fixed) and rotates around the (scaled) centre.
		-- CSS applies the list right to left with the origin at the top-left corner of the box.
		local ax, ay = inst.AnchorPoint.X * rect.w, inst.AnchorPoint.Y * rect.h
		local cx, cy = ax + scale * (rect.w / 2 - ax), ay + scale * (rect.h / 2 - ay)
		local list = {}
		if rotated then
			table.insert(list, string.format("translate(%.2fpx,%.2fpx) rotate(%.2fdeg) translate(%.2fpx,%.2fpx)", cx, cy, rotation, -cx, -cy))
		end
		if scaled then
			table.insert(list, string.format("translate(%.2fpx,%.2fpx) scale(%.4f) translate(%.2fpx,%.2fpx)", ax, ay, scale, -ax, -ay))
		end
		table.insert(styles, "transform:" .. table.concat(list, " ") .. ";transform-origin:0 0;")
	end
	local className = Fake.Data(inst).ClassName
	local clips = className == "ScrollingFrame" or className == "CanvasGroup" or inst.ClipsDescendants == true
	if clips then
		table.insert(styles, "overflow:hidden;")
	end
	if className == "CanvasGroup" and (inst.GroupTransparency or 0) > 0 then
		table.insert(styles, string.format("opacity:%.3f;", 1 - inst.GroupTransparency))
	end
	local parts = { '<div class="g" style="' .. table.concat(styles) .. '">' }
	if className == "TextLabel" or className == "TextButton" then
		table.insert(parts, textHtml(inst, rect))
	elseif className == "TextBox" then
		-- Empty box: Roblox shows the placeholder text in PlaceholderColor3.
		table.insert(parts, textHtml(inst, rect, tostring(inst.Text or "") == ""))
	elseif className == "ImageLabel" or className == "ImageButton" then
		table.insert(parts, imageHtml(inst))
	end
	local childRects, extent = computeChildRects(inst, rect)
	if className == "ScrollingFrame" and extent > rect.h + 1 and enumName(inst.VerticalScrollBarInset) == "ScrollBar" then
		-- Canvas shrinks by the scrollbar width, like Roblox with VerticalScrollBarInset = ScrollBar.
		local inner = { x = rect.x, y = rect.y, w = rect.w - inst.ScrollBarThickness - 2, h = rect.h }
		childRects, extent = computeChildRects(inst, inner)
	end
	for _, entry in childRects do
		table.insert(parts, nodeHtml(entry[1], entry[2], rect))
	end
	if className == "ScrollingFrame" and extent > rect.h + 1 then
		local barH = math.max(20, rect.h * rect.h / extent)
		table.insert(parts, string.format('<div class="g" style="left:%.1fpx;top:0;width:%dpx;height:%.1fpx;border-radius:3px;background:%s;"></div>', rect.w - 6, 6, barH, rgba(inst.ScrollBarImageColor3 or { R = 0.5, G = 0.5, B = 0.5 }, 0)))
	end
	table.insert(parts, "</div>")
	return table.concat(parts)
end

--[[
	Renders every enabled ScreenGui under playerGui into a full HTML page.
	options: { Width, Height, Inset, Caption }
]]
function Render.Page(playerGui, options): string
	local W, H, inset = options.Width, options.Height, options.Inset or 58
	local screen = { x = 0, y = inset, w = W, h = H - inset }
	local body = {}
	for _, gui in playerGui:GetChildren() do
		if Fake.Data(gui).ClassName == "ScreenGui" and gui.Enabled ~= false then
			local rects = computeChildRects(gui, screen)
			for _, entry in rects do
				table.insert(body, nodeHtml(entry[1], entry[2], { x = 0, y = 0 }))
			end
		end
	end
	return string.format(
		[[<!doctype html><html><head><meta charset="utf-8">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@500;600;700&family=Luckiest+Guy&family=Noto+Color+Emoji&display=block" rel="stylesheet">
<style>
html,body{margin:0;padding:0}
body{width:%dpx;height:%dpx;position:relative;overflow:hidden;font-family:Inter,"DejaVu Sans",sans-serif;
%s}
.g{position:absolute;box-sizing:border-box}
.t{position:absolute;inset:0;display:flex;line-height:1.15;overflow:visible}
.topbar{position:absolute;left:0;top:0;width:100%%;height:%dpx;background:rgba(0,0,0,.35);color:#fff;font:600 13px Inter,sans-serif;display:flex;align-items:center;padding-left:16px;box-sizing:border-box}
</style></head><body>%s%s</body></html>]],
		W,
		H,
		if options.Transparent
			then "background:transparent"
			else "background:linear-gradient(180deg,#7ec8f0 0%,#bfe6f7 52%,#6fb35a 52.2%,#4f8f3d 100%)",
		inset,
		if options.Transparent then "" else '<div class="topbar">' .. escape(options.Caption or "") .. "</div>",
		table.concat(body)
	)
end

return Render
