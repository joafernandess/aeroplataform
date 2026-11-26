--[[
	Icons
	Bold, outlined icons drawn with GUI primitives only (Frames + UICorner, rotated Frames, ClipsDescendants
	frames and UIStroke rings). Every icon is a square container whose children use Scale-based UDim2s, so an
	icon scales with whatever size it is given (24-72 px is the design range).

	  Icons.Create(nameOrGlyph, parent?, props?) -> GuiObject
	      props: Size (UDim2 or a number of px; default 32x32), Position, AnchorPoint, ZIndex, Name, LayoutOrder,
	             Visible, Rotation, plus
	        Color         main fill (default White)
	        Accent        secondary fill (default Cyan)
	        Outline       outline + inner-detail colour (default Ink); false = no outline
	        OutlineScale  multiplies the outline thickness (default 1; 6% of the icon size, at least 1 px)
	  Icons.Resolve(nameOrGlyph) -> name?    accepts an icon name, a Theme.Icons key ("Inventory") or glyph ("▦")
	  Icons.Glyph(name) -> string            text fallback for a name (for prices/labels in plain text)
	  Icons.SetColors(icon, { Color?, Accent?, Outline? })
	  Icons.Swap(icon, nameOrGlyph) -> GuiObject   replaces an icon in place, keeping its props
	  Icons.Names                            every drawable name (contract shared with docs/ui/ICONS.md)

	Resolution order: Theme.IconAssets[name] (uploaded full-colour image -> ImageLabel, untinted unless
	props.Tint) -> vector drawing
	-> Theme.Icons glyph (TextLabel) -> the raw text.

	Drawing model: every primitive is placed on a 100x100 unit grid. Shapes are drawn twice: first an
	"outline copy" (the same shape grown by the outline thickness, in the Outline colour), then the fill on top.
	All outline copies of a layer sit under all fills of that layer, so overlapping shapes merge into one clean
	silhouette; a higher layer gets its own outline over the lower ones.
]]

local Theme = require(script.Parent.Theme)

local Icons = {}

local SQRT2 = math.sqrt(2)
local OUTLINE = 6 -- outline thickness in grid units (1/100 of the icon size)
local ROOT = { 0, 0, 100, 100 } -- x, y, w, h of the grid in units

Icons.Names = {
	"yen",
	"gems",
	"gold",
	"tokens",
	"power",
	"fighters",
	"summon",
	"settings",
	"auto",
	"sort",
	"lock",
	"check",
	"close",
	"plus",
	"quests",
	"shop",
	"upgrades",
	"worlds",
	"raids",
	"boss",
	"zone",
	"target",
	"team",
	"timer",
	"sell",
	"new",
	"star",
	"kills",
	"codes",
	"mounts",
	"index",
	"achievements",
	"stats",
	"teleport",
	"update",
	"inventory",
}

-- Theme.Icons key -> icon name (keys without an entry, e.g. Filter, stay glyph-only).
local THEME_KEYS = {
	Yen = "yen",
	Gems = "gems",
	Gold = "gold",
	Tokens = "tokens",
	Power = "power",
	Inventory = "fighters",
	Fighters = "fighters",
	Summon = "summon",
	Settings = "settings",
	Auto = "auto",
	Sort = "sort",
	Lock = "lock",
	Equipped = "check",
	Check = "check",
	Close = "close",
	Plus = "plus",
	Fuse = "plus",
	Quests = "quests",
	Shop = "shop",
	Upgrades = "upgrades",
	Worlds = "worlds",
	Raids = "raids",
	Boss = "boss",
	Zone = "zone",
	Target = "target",
	Team = "team",
	Timer = "timer",
	Sell = "sell",
	New = "new",
	Star = "star",
	Kills = "kills",
	Codes = "codes",
	Mounts = "mounts",
	Index = "index",
	Achievements = "achievements",
	Stats = "stats",
	Teleport = "teleport",
	Update = "update",
	Bag = "inventory",
}

type Opts = {
	Fill: any?, -- "Color" | "Accent" | "Outline" | Color3
	Layer: number?,
	Outline: boolean?,
	OutlineScale: number?,
	Rot: number?,
	Radius: number?, -- corner radius as a fraction of the shorter side (0.5 = pill/circle)
	Transparency: number?,
}

-- Parts of each icon, for recolouring: icon -> { Parts = { {instance, property, role} }, Colors, Props, Name }
local registry: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any

-- Drawing context ----------------------------------------------------------------------------------------------

local Draw = {}
Draw.__index = Draw

function Draw:_paint(instance: Instance, property: string, fill: any)
	if typeof(fill) == "Color3" then
		(instance :: any)[property] = fill
		return
	end
	local role = fill or "Color"
	(instance :: any)[property] = self.Colors[role]
	table.insert(self.Parts, { instance, property, role })
end

-- Group transform (rotation/scale around a pivot) applied to a primitive's centre, size and rotation.
function Draw:_xf(cx: number, cy: number, w: number, h: number, rot: number)
	local g = self.Xf
	if not g then
		return cx, cy, w, h, rot
	end
	local dx, dy = (cx - g.X) * g.Scale, (cy - g.Y) * g.Scale
	local a = math.rad(g.Rot)
	local c, s = math.cos(a), math.sin(a)
	return g.X + dx * c - dy * s, g.Y + dx * s + dy * c, w * g.Scale, h * g.Scale, rot + g.Rot
end

function Draw:_z(layer: number, outline: boolean): number
	return self.Z + layer * 2 + (if outline then 0 else 1)
end

-- Parent frame, its rect (units) and ZIndex for a primitive of `layer` (inside the current clip, if any).
function Draw:_target(outline: boolean, layer: number)
	local clip = self.Clipping
	if not clip then
		return self.Root, ROOT, self:_z(layer, outline)
	end
	local key = if outline then "O" else "F"
	local entry = clip[key]
	if not entry then
		local r = clip.Rect
		local e = if outline then clip.Expand else 0
		local rect = { r[1] - e, r[2] - e, r[3] - r[1] + 2 * e, r[4] - r[2] + 2 * e }
		entry = { Frame = self:_clipFrame(rect, self:_z(clip.Layer, outline)), Rect = rect }
		clip[key] = entry
	end
	return entry.Frame, entry.Rect, self:_z(clip.Layer, outline)
end

function Draw:_clipFrame(rect, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Clip"
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Position = UDim2.fromScale(rect[1] / 100, rect[2] / 100)
	frame.Size = UDim2.fromScale(rect[3] / 100, rect[4] / 100)
	frame.ZIndex = z
	frame.Parent = self.Root
	return frame
end

function Draw:_frame(parent: Instance, rect, cx: number, cy: number, w: number, h: number, rot: number, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Part"
	frame.BorderSizePixel = 0
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale((cx - rect[1]) / rect[3], (cy - rect[2]) / rect[4])
	frame.Size = UDim2.fromScale(w / rect[3], h / rect[4])
	if rot ~= 0 then
		frame.Rotation = rot
	end
	frame.ZIndex = z
	frame.Parent = parent
	return frame
end

local function corner(frame: Instance, scale: number)
	if scale > 0 then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(math.min(scale, 0.5), 0)
		c.Parent = frame
	end
end

function Draw:_thickness(o: Opts): number
	if o.Outline == false then
		return 0
	end
	return self.T * (o.OutlineScale or 1)
end

-- Filled (rounded) rectangle centred on (cx, cy).
function Draw:Box(cx: number, cy: number, w: number, h: number, o: Opts?)
	local opts: Opts = o or {}
	local layer = opts.Layer or 0
	local radius = opts.Radius or 0
	local rot
	cx, cy, w, h, rot = self:_xf(cx, cy, w, h, opts.Rot or 0)
	local t = self:_thickness(opts)
	if t > 0 then
		local parent, rect, z = self:_target(true, layer)
		local outline = self:_frame(parent, rect, cx, cy, w + 2 * t, h + 2 * t, rot, z)
		local m = math.min(w, h)
		corner(outline, (radius * m + t) / (m + 2 * t))
		self:_paint(outline, "BackgroundColor3", "Outline")
	end
	local parent, rect, z = self:_target(false, layer)
	local fill = self:_frame(parent, rect, cx, cy, w, h, rot, z)
	corner(fill, radius)
	self:_paint(fill, "BackgroundColor3", opts.Fill)
	if opts.Transparency then
		fill.BackgroundTransparency = opts.Transparency
	end
	return fill
end

function Draw:Disc(cx: number, cy: number, d: number, o: Opts?)
	local opts: Opts = table.clone(o or {})
	opts.Radius = 0.5
	return self:Box(cx, cy, d, d, opts)
end

-- Hollow rounded box (default: a circle ring) of outer size w x h and band `thick`, drawn with a UIStroke.
function Draw:Ring(cx: number, cy: number, w: number, h: number, thick: number, o: Opts?)
	local opts: Opts = o or {}
	local layer = opts.Layer or 0
	local radius = opts.Radius or 0.5
	local rot, scale = 0, if self.Xf then self.Xf.Scale else 1
	cx, cy, w, h, rot = self:_xf(cx, cy, w, h, opts.Rot or 0)
	thick *= scale
	local px = self.Px / 100
	local function piece(band: number, outline: boolean)
		local parent, rect, z = self:_target(outline, layer)
		-- The stroke grows outward from the frame, so the frame is the hole: outer size minus both bands.
		-- (The outline band is 2t wider and centred on the fill band.)
		local iw, ih = math.max(w - thick - band, 0.5), math.max(h - thick - band, 0.5)
		local frame = self:_frame(parent, rect, cx, cy, iw, ih, rot, z)
		frame.BackgroundTransparency = 1
		corner(frame, radius)
		local stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Thickness = band * px
		stroke.Parent = frame
		self:_paint(stroke, "Color", if outline then "Outline" else opts.Fill)
		return frame
	end
	local t = self:_thickness(opts)
	if t > 0 then
		piece(thick + 2 * t, true)
	end
	return piece(thick, false)
end

local DIRECTIONS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- Right-angled arrowhead: base centred on (bx, by), `half` = half the base = the height, pointing `dir`.
-- Built from a diamond inside a clipping frame (clipping works because the icon itself is not rotated).
function Draw:Tri(bx: number, by: number, half: number, dir: string, o: Opts?)
	assert(self.Xf == nil and self.Clipping == nil, "Icons: Tri can't be used inside a group or clip")
	local opts: Opts = o or {}
	local layer = opts.Layer or 0
	local u = DIRECTIONS[dir]
	local function piece(mx: number, my: number, h: number, outline: boolean)
		local x0, y0, x1, y1
		if u[1] == 0 then
			x0, x1 = mx - h, mx + h
			y0, y1 = math.min(my, my + u[2] * h), math.max(my, my + u[2] * h)
		else
			y0, y1 = my - h, my + h
			x0, x1 = math.min(mx, mx + u[1] * h), math.max(mx, mx + u[1] * h)
		end
		local rect = { x0, y0, x1 - x0, y1 - y0 }
		local z = self:_z(layer, outline)
		local clip = self:_clipFrame(rect, z)
		local diamond = self:_frame(clip, rect, mx, my, h * SQRT2, h * SQRT2, 45, z)
		corner(diamond, opts.Radius or 0)
		self:_paint(diamond, "BackgroundColor3", if outline then "Outline" else opts.Fill)
		return diamond
	end
	local t = self:_thickness(opts)
	if t > 0 then
		-- Grow the triangle around its incentre (inradius = half * (sqrt2 - 1)).
		piece(bx - t * u[1], by - t * u[2], half + t * (SQRT2 + 1), true)
	end
	return piece(bx, by, half, false)
end

-- Rectangle with one long edge on the segment (x1,y1)-(x2,y2), extending `width` along the normal (nx, ny).
function Draw:Board(x1: number, y1: number, x2: number, y2: number, nx: number, ny: number, width: number, o: Opts?)
	local opts: Opts = o or {}
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	local mx, my = (x1 + x2) / 2 + nx * width / 2, (y1 + y2) / 2 + ny * width / 2
	local inner = table.clone(opts)
	inner.Rot = math.deg(math.atan2(dy, dx))
	return self:Box(mx, my, len, width, inner)
end

-- Runs `fn` with every primitive clipped to the axis-aligned rect (x0,y0)-(x1,y1) on `layer`.
function Draw:Clip(x0: number, y0: number, x1: number, y1: number, layer: number, fn: () -> ())
	assert(self.Xf == nil and self.Clipping == nil, "Icons: clips can't be nested or rotated")
	self.Clipping = { Rect = { x0, y0, x1, y1 }, Layer = layer, Expand = self.T }
	fn()
	self.Clipping = nil
end

-- Runs `fn` with every primitive rotated by `rot` degrees (and scaled) around (px, py).
function Draw:Group(rot: number, px: number, py: number, scale: number, fn: () -> ())
	local previous = self.Xf
	self.Xf = { Rot = rot, X = px, Y = py, Scale = scale }
	fn()
	self.Xf = previous
end

-- Rounded five-point star (outer radius r, centred on the circle through its tips): the five pentagram lines
-- as round-capped bars, thick enough to fill the spikes, plus a disc filling the inner pentagon.
function Draw:Star5(cx: number, cy: number, r: number, o: Opts?)
	local w = r * 0.33 -- bar width = twice the tip rounding
	local r0 = r - w / 2 -- tip radius of the underlying sharp star
	local tips = {}
	for k = 0, 4 do
		local a = math.rad(-90 + 72 * k)
		tips[k] = { cx + r0 * math.cos(a), cy + r0 * math.sin(a) }
	end
	self:Disc(cx, cy, r0 * 0.382 * 2 + 2, o)
	local opts: Opts = table.clone(o or {})
	opts.Radius = 0.5
	for k = 0, 4 do
		local a, b = tips[k], tips[(k + 2) % 5]
		local dx, dy = b[1] - a[1], b[2] - a[2]
		opts.Rot = math.deg(math.atan2(dy, dx))
		self:Box((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, math.sqrt(dx * dx + dy * dy) + w, w, opts)
	end
end

-- Sharp four-point sparkle: in each quadrant two boards are clipped to the quadrant.
function Draw:Spike4(cx: number, cy: number, r: number, inner: number, layer: number, o: Opts?)
	local d = inner / SQRT2
	for _, q in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local sx, sy = q[1], q[2]
		local vx, vy = cx + sx * d, cy + sy * d
		self:Clip(math.min(cx, cx + sx * r), math.min(cy, cy + sy * r), math.max(cx, cx + sx * r), math.max(cy, cy + sy * r), layer, function()
			for _, tip in { { cx, cy + sy * r }, { cx + sx * r, cy } } do
				local ex, ey = vx - tip[1], vy - tip[2]
				local len = math.sqrt(ex * ex + ey * ey)
				ex, ey = ex / len, ey / len
				local nx, ny = -ey, ex
				if nx * (cx - vx) + ny * (cy - vy) < 0 then
					nx, ny = -nx, -ny
				end
				self:Board(tip[1] - ex * 4, tip[2] - ey * 4, tip[1] + ex * (len + r), tip[2] + ey * (len + r), nx, ny, r, o)
			end
		end)
	end
end

-- Burst/seal: `n` squares rotated evenly (4n points) with outer radius r.
function Draw:Burst(cx: number, cy: number, r: number, n: number, o: Opts?)
	local opts: Opts = table.clone(o or {})
	opts.Radius = opts.Radius or 0.06
	for i = 0, n - 1 do
		opts.Rot = (90 / n) * i
		self:Box(cx, cy, r * SQRT2, r * SQRT2, opts)
	end
end

-- Icon drawings (100x100 grid) ------------------------------------------------------------------------------------

local Drawings: { [string]: (any) -> () } = {}

local function coinFace(d, cx: number, cy: number, size: number)
	d:Disc(cx, cy, size, {})
	d:Disc(cx, cy, size * 0.76, { Fill = "Accent", Layer = 1, OutlineScale = 0.45 })
end

Drawings.yen = function(d)
	coinFace(d, 50, 50, 86)
	local ink = { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.35 }
	local arm = table.clone(ink)
	arm.Rot = -34
	d:Box(43, 37, 8.5, 28, arm)
	arm.Rot = 34
	d:Box(57, 37, 8.5, 28, arm)
	d:Box(50, 59, 8.5, 28, ink)
	d:Box(50, 56, 30, 6.5, ink)
	d:Box(50, 66, 30, 6.5, ink)
end

Drawings.sell = function(d)
	coinFace(d, 50, 50, 86)
	d:Box(50, 50, 40, 12, { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.4 })
end

Drawings.gems = function(d)
	-- Cut gem: a diamond (girdle at y 38, half-width 42) with its top clipped flat into a table at y 22.
	local side = 42 * SQRT2
	d:Clip(0, 22, 100, 100, 0, function()
		d:Box(50, 38, side, side, { Rot = 45, Radius = 0.06 })
	end)
	d:Clip(0, 22, 100, 38, 1, function()
		d:Box(50, 38, side, side, { Rot = 45, Radius = 0.06, Fill = "Accent", Outline = false })
	end)
	local ink = { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.5 }
	d:Box(50, 38, 82, 4.5, ink)
	local facet = table.clone(ink)
	facet.Rot = 69
	d:Box(42, 59, 45, 4, facet)
	facet.Rot = -69
	d:Box(58, 59, 45, 4, facet)
	d:Box(36, 30, 6, 6, { Rot = 45, Layer = 2, Outline = false })
end

Drawings.gold = function(d)
	-- A stack of coins seen from the side (each coin its own layer, so the outlines separate them) and one
	-- coin standing in front.
	for i, x in { 36, 40, 36, 39 } do
		d:Box(x, 83 - (i - 1) * 15, 54, 17, { Radius = 0.5, Layer = i - 1 })
	end
	d:Disc(68, 62, 48, { Layer = 4 })
	d:Disc(68, 62, 31, { Fill = "Accent", Layer = 5, OutlineScale = 0.45 })
end

Drawings.tokens = function(d)
	d:Group(-16, 50, 50, 1, function()
		d:Box(50, 50, 84, 52, { Radius = 0.18 })
		local ink = { Fill = "Outline", Layer = 1, Outline = false }
		d:Disc(8, 50, 13, ink)
		d:Disc(92, 50, 13, ink)
		local dash = { Fill = "Outline", Layer = 1, Outline = false, Radius = 0.5 }
		d:Box(31, 36, 4, 8, dash)
		d:Box(31, 50, 4, 8, dash)
		d:Box(31, 64, 4, 8, dash)
		d:Star5(61, 51.5, 18, { Fill = "Accent", Layer = 2, OutlineScale = 0.6 })
	end)
end

Drawings.power = function(d)
	-- Front-facing fist: four knuckles, back of the hand, folded thumb and a wristband.
	d:Box(53, 85, 46, 14, { Fill = "Accent", Radius = 0.25 })
	d:Box(52, 54, 66, 42, { Radius = 0.28 })
	for i, x in { 28, 44, 60, 76 } do
		d:Box(x, 31 + (if i == 1 or i == 4 then 3 else 0), 17, 30, { Radius = 0.45 })
	end
	local line = { Fill = "Outline", Layer = 1, Outline = false, Radius = 0.5 }
	d:Box(36, 28, 3.5, 18, line)
	d:Box(52, 27, 3.5, 18, line)
	d:Box(68, 28, 3.5, 18, line)
	d:Box(42, 54, 44, 15, { Radius = 0.5, Layer = 1 })
end

Drawings.fighters = function(d)
	-- Fighter bust with a flying headband.
	d:Box(79, 37, 22, 8, { Fill = "Accent", Radius = 0.5, Rot = 14 })
	d:Box(77, 47, 18, 7, { Fill = "Accent", Radius = 0.5, Rot = 42 })
	d:Clip(0, 0, 100, 90, 0, function()
		d:Box(50, 92, 76, 48, { Radius = 0.5 })
	end)
	d:Disc(50, 42, 42, { Layer = 1 })
	d:Box(50, 36, 48, 10, { Fill = "Accent", Radius = 0.3, Layer = 2, OutlineScale = 0.6 })
end

Drawings.team = function(d)
	d:Clip(0, 0, 100, 86, 0, function()
		d:Box(23, 80, 36, 36, { Fill = "Accent", Radius = 0.5 })
		d:Box(77, 80, 36, 36, { Fill = "Accent", Radius = 0.5 })
	end)
	d:Disc(23, 42, 24, { Fill = "Accent" })
	d:Disc(77, 42, 24, { Fill = "Accent" })
	d:Clip(0, 0, 100, 90, 2, function()
		d:Box(50, 86, 50, 48, { Radius = 0.5 })
	end)
	d:Disc(50, 38, 32, { Layer = 2 })
end

Drawings.summon = function(d)
	d:Disc(50, 52, 82)
	d:Disc(50, 52, 64, { Fill = "Accent", Layer = 1, OutlineScale = 0.45 })
	d:Spike4(50, 52, 25, 9, 2, { OutlineScale = 0.6 })
	d:Disc(33, 35, 8, { Layer = 3, Outline = false })
end

Drawings.settings = function(d)
	for _, rot in { 0, 45, 90, 135 } do
		d:Box(50, 50, 18, 84, { Rot = rot, Radius = 0.2 })
	end
	d:Disc(50, 50, 64)
	d:Disc(50, 50, 24, { Fill = "Outline", Layer = 1, Outline = false })
end

Drawings.auto = function(d)
	d:Clip(0, 0, 100, 38, 0, function()
		d:Ring(50, 50, 72, 72, 12)
	end)
	d:Clip(0, 62, 100, 100, 0, function()
		d:Ring(50, 50, 72, 72, 12)
	end)
	d:Tri(77.4, 38, 16, "down")
	d:Tri(22.6, 62, 16, "up")
end

Drawings.sort = function(d)
	d:Box(32, 62, 12, 34)
	d:Tri(32, 46, 18, "up")
	d:Box(68, 38, 12, 34)
	d:Tri(68, 54, 18, "down")
end

Drawings.upgrades = function(d)
	d:Box(50, 68, 28, 42, { Radius = 0.12 })
	d:Tri(50, 48, 36, "up")
	local band = { Fill = "Accent", Layer = 1, Outline = false }
	d:Box(50, 70, 28, 6, band)
	d:Box(50, 81, 28, 6, band)
end

Drawings.lock = function(d)
	d:Ring(50, 38, 42, 50, 10)
	d:Box(50, 64, 64, 44, { Radius = 0.2, Layer = 1 })
	local ink = { Fill = "Outline", Layer = 2, Outline = false }
	d:Disc(50, 60, 14, ink)
	d:Box(50, 68, 6.5, 14, { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.3 })
end

Drawings.check = function(d)
	d:Box(33, 60, 16, 36, { Rot = -45, Radius = 0.5 })
	d:Box(60, 47, 16, 64, { Rot = 45, Radius = 0.5 })
end

Drawings.close = function(d)
	d:Box(50, 50, 16, 80, { Rot = 45, Radius = 0.5 })
	d:Box(50, 50, 16, 80, { Rot = -45, Radius = 0.5 })
end

Drawings.plus = function(d)
	d:Box(50, 50, 18, 76, { Radius = 0.5 })
	d:Box(50, 50, 76, 18, { Radius = 0.5 })
end

Drawings.quests = function(d)
	d:Box(50, 50, 56, 66, { Radius = 0.06 })
	d:Box(50, 19, 74, 15, { Fill = "Accent", Radius = 0.5, Layer = 1 })
	d:Box(50, 81, 74, 15, { Fill = "Accent", Radius = 0.5, Layer = 1 })
	local ink = { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.5 }
	d:Box(50, 40, 34, 5, ink)
	d:Box(50, 50, 34, 5, ink)
	d:Box(45, 60, 24, 5, ink)
end

Drawings.shop = function(d)
	-- Storefront: building with a door under a striped, scalloped awning.
	d:Box(50, 66, 72, 42, { Radius = 0.08 })
	d:Box(50, 74, 20, 26, { Fill = "Accent", Layer = 1, Radius = 0.15, OutlineScale = 0.6 })
	d:Box(50, 30, 88, 22, { Radius = 0.2, Layer = 2 })
	for i, x in { 15.2, 32.6, 50, 67.4, 84.8 } do
		d:Disc(x, 41, 17.4, { Layer = 2, Fill = if i % 2 == 0 then "Accent" else "Color" })
	end
	local stripe = { Fill = "Accent", Layer = 3, Outline = false }
	d:Box(32.6, 30, 17.4, 22, stripe)
	d:Box(67.4, 30, 17.4, 22, stripe)
end

Drawings.worlds = function(d)
	d:Disc(50, 50, 80)
	local ink = { Fill = "Outline", Layer = 1, Outline = false }
	d:Box(50, 50, 80, 5, ink)
	d:Box(50, 32, 70, 4.5, ink)
	d:Box(50, 68, 70, 4.5, ink)
	d:Box(50, 50, 4.5, 80, ink)
	d:Ring(50, 50, 38, 80, 4.5, ink)
end

local function sword(d, rot: number, scale: number, layer: number)
	d:Group(rot, 50, 50, scale, function()
		d:Box(50, 30, 15, 52, { Layer = layer })
		d:Box(50, 4, 15 / SQRT2, 15 / SQRT2, { Rot = 45, Layer = layer })
		d:Box(50, 76, 9, 22, { Fill = "Accent", Radius = 0.2, Layer = layer })
		d:Box(50, 60, 40, 10, { Fill = "Accent", Radius = 0.5, Layer = layer + 1 })
		d:Disc(50, 88, 14, { Fill = "Accent", Layer = layer + 1 })
		d:Box(50, 33, 3, 36, { Fill = "Outline", Layer = layer + 1, Outline = false, Radius = 0.5 })
	end)
end

Drawings.kills = function(d)
	sword(d, 45, 1, 0)
end

Drawings.raids = function(d)
	sword(d, 45, 0.9, 0)
	sword(d, -45, 0.9, 2)
end

Drawings.boss = function(d)
	d:Disc(50, 42, 66)
	d:Box(50, 74, 40, 24, { Radius = 0.3 })
	local ink = { Fill = "Outline", Layer = 1, Outline = false }
	d:Disc(36, 46, 18, ink)
	d:Disc(64, 46, 18, ink)
	d:Box(50, 61, 8, 8, { Fill = "Outline", Layer = 1, Outline = false, Rot = 45, Radius = 0.2 })
	for _, x in { 42, 50, 58 } do
		d:Box(x, 80, 4, 11, { Fill = "Outline", Layer = 1, Outline = false, Radius = 0.5 })
	end
	d:Disc(36, 46, 7, { Fill = "Accent", Layer = 2, Outline = false })
	d:Disc(64, 46, 7, { Fill = "Accent", Layer = 2, Outline = false })
end

Drawings.zone = function(d)
	d:Box(50, 87, 40, 9, { Fill = "Accent", Radius = 0.5 })
	-- Pin: circle (r 29) + a diamond whose flanks are tangent to it (tip 41 units below the centre).
	d:Disc(50, 35, 58, { Layer = 1 })
	d:Box(50, 55.5, 29, 29, { Rot = 45, Layer = 1, Radius = 0.08 })
	d:Disc(50, 35, 24, { Fill = "Outline", Layer = 2, Outline = false })
end

Drawings.target = function(d)
	d:Ring(50, 50, 70, 70, 10)
	d:Box(50, 15, 10, 22, { Radius = 0.3 })
	d:Box(50, 85, 10, 22, { Radius = 0.3 })
	d:Box(15, 50, 22, 10, { Radius = 0.3 })
	d:Box(85, 50, 22, 10, { Radius = 0.3 })
	d:Disc(50, 50, 16, { Fill = "Accent", Layer = 1, OutlineScale = 0.6 })
end

Drawings.timer = function(d)
	d:Box(50, 14, 20, 10, { Radius = 0.3 })
	d:Box(50, 20, 9, 8)
	d:Box(78, 29, 13, 9, { Rot = 45, Radius = 0.3 })
	d:Disc(50, 57, 72)
	d:Disc(50, 57, 54, { Fill = "Accent", Layer = 1, OutlineScale = 0.45 })
	local hand = { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.5 }
	d:Box(50, 47, 7, 24, hand)
	d:Box(57.5, 62, 20, 7, { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.5, Rot = 35 })
	d:Disc(50, 57, 11, { Fill = "Outline", Layer = 2, Outline = false })
end

Drawings.new = function(d)
	d:Burst(50, 50, 46, 3)
	local ink = { Fill = "Outline", Layer = 1, Outline = false, Radius = 0.45 }
	d:Box(50, 42, 11, 30, ink)
	d:Disc(50, 67, 11, { Fill = "Outline", Layer = 1, Outline = false })
end

Drawings.star = function(d)
	d:Star5(50, 53.6, 46)
end

-- Resolution --------------------------------------------------------------------------------------------------------

local byLowerKey: { [string]: string } = {}
for key, name in THEME_KEYS do
	byLowerKey[string.lower(key)] = name
end
local byGlyph: { [string]: string }? = nil

local function glyphMap(): { [string]: string }
	if byGlyph then
		return byGlyph
	end
	local map = {}
	local keys = {}
	for key in Theme.Icons do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local name = THEME_KEYS[key]
		local glyph = Theme.Icons[key]
		if name and type(glyph) == "string" and glyph ~= "" and map[glyph] == nil then
			map[glyph] = name
		end
	end
	byGlyph = map
	return map
end

-- Navigation icons (side menus) -------------------------------------------------------------------------------------

Drawings.codes = function(d)
	-- Gift box: body, lid, ribbon and a two-loop bow.
	d:Box(50, 66, 68, 44, { Radius = 0.12 })
	d:Box(50, 40, 80, 18, { Fill = "Accent", Radius = 0.18, Layer = 1 })
	d:Box(50, 66, 12, 44, { Fill = "Accent", Layer = 1, Outline = false })
	d:Box(50, 40, 12, 18, { Fill = "Color", Layer = 2, Outline = false })
	d:Box(38, 24, 22, 14, { Radius = 0.5, Rot = -28, Layer = 3 })
	d:Box(62, 24, 22, 14, { Radius = 0.5, Rot = 28, Layer = 3 })
	d:Disc(50, 28, 12, { Fill = "Accent", Layer = 4 })
end

Drawings.mounts = function(d)
	-- Horseshoe: bottom half of a thick ring plus two straight arms, with nail holes.
	d:Clip(0, 46, 100, 100, 0, function()
		d:Ring(50, 52, 72, 72, 20, {})
	end)
	d:Box(24, 34, 20, 34, { Radius = 0.25 })
	d:Box(76, 34, 20, 34, { Radius = 0.25 })
	local nail = { Fill = "Accent", Layer = 1, Outline = false, Radius = 0.5 }
	for _, p in { { 24, 30 }, { 76, 30 }, { 22, 52 }, { 78, 52 }, { 33, 74 }, { 67, 74 } } do
		d:Box(p[1], p[2], 7, 7, nail)
	end
end

Drawings.index = function(d)
	-- Book: cover with a cyan spine, page block and text lines.
	d:Box(52, 50, 70, 84, { Radius = 0.1 })
	d:Box(22, 50, 14, 84, { Fill = "Accent", Radius = 0.25, Layer = 1 })
	local line = { Fill = "Outline", Layer = 2, Outline = false, Radius = 0.5 }
	d:Box(58, 30, 36, 5, line)
	d:Box(58, 44, 36, 5, line)
	d:Box(58, 58, 28, 5, line)
	d:Star5(58, 74, 11, { Fill = "Accent", Layer = 2, OutlineScale = 0.6 })
end

Drawings.achievements = function(d)
	-- Trophy: handles, cup, stem and base, with a star on the cup.
	-- Handles: short rounded bars angled into the cup (rings render as solid squares at small sizes).
	d:Box(26, 34, 22, 9, { Radius = 0.5, Rot = 20 })
	d:Box(74, 34, 22, 9, { Radius = 0.5, Rot = -20 })
	d:Box(22, 44, 9, 20, { Radius = 0.5 })
	d:Box(78, 44, 9, 20, { Radius = 0.5 })
	d:Box(50, 38, 52, 46, { Radius = 0.42, Layer = 1 })
	d:Box(50, 66, 14, 16, { Layer = 1 })
	d:Box(50, 82, 48, 14, { Fill = "Accent", Radius = 0.3, Layer = 2 })
	d:Star5(50, 37, 13, { Fill = "Accent", Layer = 2, OutlineScale = 0.6 })
end

Drawings.stats = function(d)
	-- Rising bar chart on a base line.
	d:Box(26, 66, 16, 30, { Radius = 0.2 })
	d:Box(50, 54, 16, 54, { Radius = 0.2 })
	d:Box(74, 40, 16, 82, { Fill = "Accent", Radius = 0.2 })
	d:Box(50, 86, 84, 7, { Radius = 0.5, Layer = 1 })
end

Drawings.teleport = function(d)
	-- Portal: cyan ring with a bright core and a sparkle.
	d:Ring(50, 50, 80, 88, 14, { Fill = "Accent" })
	d:Box(50, 50, 42, 52, { Radius = 0.5, Layer = 1 })
	d:Spike4(50, 50, 16, 5, 2, { Fill = "Accent" })
end

Drawings.update = function(d)
	-- Bell: dome, rim, clapper and top knob.
	d:Disc(50, 18, 14, {})
	d:Box(50, 46, 56, 52, { Radius = 0.46, Layer = 1 })
	d:Box(50, 70, 74, 14, { Radius = 0.5, Layer = 2 })
	d:Disc(50, 84, 16, { Fill = "Accent", Layer = 1 })
	d:Box(38, 42, 7, 22, { Fill = "Accent", Layer = 2, Outline = false, Radius = 0.5 })
end

Drawings.inventory = function(d)
	-- Backpack: body, top handle, flap and front pocket.
	d:Box(50, 20, 32, 18, { Radius = 0.5 })
	d:Box(50, 23, 16, 7, { Fill = "Outline", Layer = 1, Outline = false, Radius = 0.5 })
	d:Box(50, 58, 66, 70, { Radius = 0.28, Layer = 1 })
	d:Box(50, 40, 66, 26, { Fill = "Accent", Radius = 0.35, Layer = 2 })
	d:Box(50, 70, 38, 22, { Radius = 0.3, Layer = 2 })
	d:Box(50, 52, 10, 8, { Fill = "Outline", Layer = 3, Outline = false, Radius = 0.3 })
end

function Icons.Resolve(nameOrGlyph: any): string?
	if type(nameOrGlyph) ~= "string" then
		return nil
	end
	local text = string.match(nameOrGlyph, "^%s*(.-)%s*$") or ""
	if text == "" then
		return nil
	end
	-- Exact Theme.Icons keys win (legacy: "Inventory" is the Fighters icon); lowercase names are icon names.
	if THEME_KEYS[text] then
		return THEME_KEYS[text]
	end
	local lower = string.lower(text)
	if Drawings[lower] or (Theme.IconAssets and Theme.IconAssets[lower] ~= nil) then
		return lower
	end
	return byLowerKey[lower] or glyphMap()[text]
end

function Icons.Has(name: string): boolean
	return Drawings[name] ~= nil
end

function Icons.Glyph(nameOrGlyph: string): string
	local name = Icons.Resolve(nameOrGlyph)
	if name then
		for key, mapped in THEME_KEYS do
			if mapped == name and Theme.Icons[key] then
				return Theme.Icons[key]
			end
		end
	end
	return nameOrGlyph
end

-- Creation ----------------------------------------------------------------------------------------------------------

local SPECIAL = { Color = true, Accent = true, Outline = true, OutlineScale = true, Size = true, Px = true, Tint = true }

local function sizeOf(value: any): UDim2
	if type(value) == "number" then
		return UDim2.fromOffset(value, value)
	end
	return value or UDim2.fromOffset(32, 32)
end

-- Pixel size of the icon (only needed for UIStroke rings and the 1 px minimum outline).
local function pixelsOf(size: UDim2, parent: Instance?, hint: number?): number
	if hint then
		return hint
	end
	local w, h = size.X.Offset, size.Y.Offset
	if size.X.Scale ~= 0 or size.Y.Scale ~= 0 then
		local ok, parentSize = pcall(function()
			return (parent :: any).Size
		end)
		if ok and typeof(parentSize) == "UDim2" and parentSize.X.Scale == 0 then
			w += size.X.Scale * parentSize.X.Offset
			h += size.Y.Scale * parentSize.Y.Offset
		else
			return 32
		end
	end
	local px = math.min(w, h)
	return if px > 0 then px else 32
end

local function applyProps(instance: Instance, props: { [string]: any })
	for key, value in props do
		if not SPECIAL[key] then
			(instance :: any)[key] = value
		end
	end
end

local function baseZ(parent: Instance?, props: { [string]: any }): number
	if props.ZIndex then
		return props.ZIndex
	end
	if parent and parent:IsA("GuiObject") then
		return (parent :: any).ZIndex + 1
	end
	return 1
end

function Icons.Create(nameOrGlyph: string, parent: Instance?, props: { [string]: any }?): GuiObject
	local p = props or {}
	local name = Icons.Resolve(nameOrGlyph)
	local colors = {
		Color = p.Color or Theme.Colors.White,
		Accent = p.Accent or Theme.Colors.Cyan,
		Outline = if p.Outline then p.Outline else Theme.Colors.Ink,
	}
	local size = sizeOf(p.Size)
	local px = pixelsOf(size, parent, p.Px)
	local z = baseZ(parent, p)
	local entry = { Parts = {}, Colors = colors, Props = p, Name = name or nameOrGlyph }
	local asset = name and Theme.IconAssets and Theme.IconAssets[name]
	local icon: any

	if type(asset) == "string" and asset ~= "" then
		icon = Instance.new("ImageLabel")
		icon.BackgroundTransparency = 1
		icon.Image = asset
		icon.ScaleType = Enum.ScaleType.Fit
		-- Uploaded icons are full-colour art (assets/UI_Icons): shown as-is unless the caller asks for a tint.
		if p.Tint then
			icon.ImageColor3 = colors.Color
			table.insert(entry.Parts, { icon, "ImageColor3", "Color" })
		else
			icon.ImageColor3 = Theme.Colors.White
		end
	elseif name and Drawings[name] then
		icon = Instance.new("Frame")
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		local draw = setmetatable({
			Root = icon,
			Colors = colors,
			Parts = entry.Parts,
			Px = px,
			Z = z,
			T = if p.Outline == false then 0 else math.max(OUTLINE, 100 / px) * (p.OutlineScale or 1),
		}, Draw)
		Drawings[name](draw)
	else
		icon = Instance.new("TextLabel")
		icon.BackgroundTransparency = 1
		icon.Text = if name then Icons.Glyph(name) else tostring(nameOrGlyph)
		icon.TextScaled = true
		icon.Font = Theme.Fonts.Bold
		icon.TextColor3 = colors.Color
		table.insert(entry.Parts, { icon, "TextColor3", "Color" })
		if p.Outline ~= false then
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			stroke.LineJoinMode = Enum.LineJoinMode.Round
			stroke.Thickness = math.max(1, px * OUTLINE / 100)
			stroke.Color = colors.Outline
			stroke.Parent = icon
			table.insert(entry.Parts, { stroke, "Color", "Outline" })
		end
	end

	icon.Name = "Icon"
	icon.Size = size
	icon.ZIndex = z
	applyProps(icon, p)
	icon.Size = size
	icon:SetAttribute("Icon", entry.Name)
	registry[icon] = entry
	if parent then
		icon.Parent = parent
	end
	return icon
end

function Icons.SetColors(icon: Instance, colors: { Color: Color3?, Accent: Color3?, Outline: Color3? })
	local entry = registry[icon]
	if not entry then
		return
	end
	for role, value in colors do
		entry.Colors[role] = value
	end
	for _, part in entry.Parts do
		local value = entry.Colors[part[3]]
		if value then
			(part[1] :: any)[part[2]] = value
		end
	end
end

-- The name an icon was created with (nil for instances that aren't icons).
function Icons.NameOf(icon: Instance): string?
	local entry = registry[icon]
	return entry and entry.Name
end

function Icons.Swap(icon: Instance, nameOrGlyph: string): GuiObject
	local entry = registry[icon]
	local props = if entry then table.clone(entry.Props) else {}
	if entry then
		props.Color, props.Accent = entry.Colors.Color, entry.Colors.Accent
		if props.Outline ~= false then
			props.Outline = entry.Colors.Outline
		end
	end
	local gui = icon :: any
	props.Position, props.AnchorPoint, props.ZIndex = gui.Position, gui.AnchorPoint, gui.ZIndex
	props.Visible, props.LayoutOrder, props.Size = gui.Visible, gui.LayoutOrder, gui.Size
	local parent = icon.Parent
	local replacement = Icons.Create(nameOrGlyph, parent, props)
	icon:Destroy()
	return replacement
end

return Icons
