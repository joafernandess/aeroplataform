--[[
	Icon gallery (Lune)
	Renders every UI/Icons icon at 24/48/72 px on a dark panel and on a blue button, colour variants used by the
	components (header tile, close button, currency badges, unit-card badges), the image-override path, and the
	real HUD + Fighters window built by the controllers.

	Usage (repo root):
	  lune run tools/ui-preview/scenes/icons [outputDir]
	  node tools/ui-preview/screenshot.js [outputDir] [deviceScaleFactor]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Fake = require("../FakeRoblox")
local Render = require("../Render")
local Session = require("../Session")

local OUT = process.args[1] or "ui-preview-out/icons"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end

local session = Session.new()
local rt, playerGui = session.Runtime, session.PlayerGui
local UI = session.Controller("UIController")
local C = rt:Require("StarterPlayer/StarterPlayerScripts/Client/UI/Components")
local Icons = rt:Require("StarterPlayer/StarterPlayerScripts/Client/UI/Icons")
local Theme = rt:Require("StarterPlayer/StarterPlayerScripts/Client/UI/Theme")
local P = Theme.Colors
local UDim2, Vector2, Enum = roblox.UDim2, roblox.Vector2, roblox.Enum

local function write(name: string, html: string)
	fs.writeFile(OUT .. "/" .. name .. ".html", html)
	print("wrote " .. name)
end

-- A page that shows only `build`'s ScreenGui (the game UI is hidden while it renders).
local function galleryPage(name: string, width: number, height: number, build: (any) -> ())
	local gui = Fake.new("ScreenGui")
	gui.Name = "Gallery"
	local bg = C.Frame(gui, { BackgroundColor3 = P.Bg, Size = UDim2.fromScale(1, 1) })
	build(bg)
	UI.Root.Enabled = false
	gui.Parent = playerGui
	write(name, Render.Page(playerGui, { Width = width, Height = height, Inset = 0, Caption = "" }))
	gui:Destroy()
	UI.Root.Enabled = true
end

local function caption(parent, text: string, props)
	local label = C.Title(parent, text, { TextSize = 16, Size = UDim2.fromOffset(110, 20) }, 1.5)
	for k, v in props or {} do
		label[k] = v
	end
	return label
end

local SIZES = { 24, 48, 72 }

-- One row: name | 24/48/72 on Panel | 24/48/72 on a Primary (Blue500) button.
local function iconRow(parent, name: string, order: number)
	local row = C.Frame(parent, { BackgroundTransparency = 1, Size = UDim2.fromOffset(620, 96), LayoutOrder = order })
	caption(row, name, { Position = UDim2.fromOffset(4, 38), TextSize = 18 })
	local panel = C.Frame(row, { BackgroundColor3 = P.Panel, Position = UDim2.fromOffset(112, 4), Size = UDim2.fromOffset(196, 88) })
	C.Corner(panel, 12)
	C.Stroke(panel, P.Line, 1.5)
	local x = 10
	for _, px in SIZES do
		Icons.Create(name, panel, { Size = px, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, x, 0.5, 0) })
		x += px + 12
	end
	x = 320
	for _, px in SIZES do
		local d = px + 16
		local button = C.Button(row, "", nil, { Kind = "Primary", Size = UDim2.fromOffset(d, d + 4), Position = UDim2.fromOffset(x, 48 - (d + 4) / 2), Radius = math.floor(d * 0.28), Confirm = false })
		Icons.Create(name, button.Face, { Size = px, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5) })
		x += d + 14
	end
	return row
end

local function gallery(index: number, names: { string })
	galleryPage(("10_icons_%d"):format(index), 1280, 760, function(bg)
		C.Title(bg, ("Icons %d/%d — 24 / 48 / 72 px on Panel and on a Primary button"):format(index, math.ceil(#Icons.Names / 14)), {
			Position = UDim2.fromOffset(20, 10),
			Size = UDim2.fromOffset(900, 34),
			TextSize = 22,
		})
		local columns = C.Frame(bg, { BackgroundTransparency = 1, Position = UDim2.fromOffset(16, 50), Size = UDim2.new(1, -32, 1, -56) })
		C.Grid(columns, UDim2.fromOffset(620, 96), 4)
		-- Column-major: first half of the names in the left column.
		local rows = math.ceil(#names / 2)
		for i = 1, rows do
			for col = 0, 1 do
				local name = names[i + col * rows]
				if name then
					iconRow(columns, name, i * 2 + col)
				end
			end
		end
	end)
end

-- 14 icons per page (7 rows x 2 columns).
local pages = {}
for i, name in Icons.Names do
	local page = math.ceil(i / 14)
	pages[page] = pages[page] or {}
	table.insert(pages[page], name)
end
for index, names in pages do
	gallery(index, names)
end

-- Variants: the colour combinations the components use + image overrides + small sizes.
local SVG = OUT .. "/_sample_icon.svg"
fs.writeFile(
	SVG,
	[[<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><circle cx="32" cy="32" r="26" fill="#fff" stroke="#05070D" stroke-width="5"/><path d="M20 33l8 8 16-18" fill="none" stroke="#05070D" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>]]
)

galleryPage("11_icon_variants", 1280, 720, function(bg)
	C.Title(bg, "Icon variants used by the components", { Position = UDim2.fromOffset(20, 10), Size = UDim2.fromOffset(900, 34), TextSize = 22 })
	local function section(title: string, y: number)
		caption(bg, title, { Position = UDim2.fromOffset(24, y), Size = UDim2.fromOffset(600, 22), TextColor3 = P.TextDim })
	end

	-- Window header tiles (blue icon on a white tile)
	section("Window header tiles (Color = Blue500 on White)", 52)
	for i, name in { "fighters", "summon", "worlds", "quests", "shop", "upgrades", "raids", "settings", "boss", "team", "timer", "kills" } do
		local tile = C.Frame(bg, { BackgroundColor3 = P.White, Position = UDim2.fromOffset(24 + (i - 1) * 56, 80), Size = UDim2.fromOffset(40, 40) })
		C.Corner(tile, Theme.Radius.Tool)
		C.Stroke(tile, P.Ink, 2.5)
		Icons.Create(name, tile, { Size = 30, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Color = P.Blue500 })
	end

	-- Currency badges
	section("Currency badges (CurrencyPill) + Power", 140)
	local pills = C.Frame(bg, { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 168), Size = UDim2.fromOffset(1200, 48) })
	C.List(pills, Enum.FillDirection.Horizontal, 16)
	for i, currency in { "Yen", "Gems", "Gold", "Tokens" } do
		local pill = C.CurrencyPill(pills, Theme.Icons[currency], Theme.Currency(currency), 200, {
			GlyphColor = Theme.CurrencyGlyphColor[currency],
			Plus = if currency == "Gems" then function() end else nil,
		})
		pill.Set(("%d.%dK"):format(i * 3, i))
		pill.Frame.LayoutOrder = i
	end
	local power = C.CurrencyPill(pills, Theme.Icons.Power, P.Ink, 240, { GlyphColor = P.Cyan })
	power.Set("367 Power")
	power.Frame.LayoutOrder = 5

	-- Buttons: menu icon buttons, tool buttons, close, disabled/secondary/dark kinds
	section("Menu / tool / close buttons and kinds (Primary, Accent, Dark, Secondary, Disabled)", 232)
	local row = C.Frame(bg, { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 262), Size = UDim2.fromOffset(1200, 100) })
	C.List(row, Enum.FillDirection.Horizontal, 14)
	local _, auto = C.IconButton(row, Theme.Icons.Auto, "AUTO", "Primary", nil, 72)
	local summon = C.IconButton(row, Theme.Icons.Summon, "Summon", Theme.MenuKinds.Summon, nil, 68)
	summon.LayoutOrder = 1
	auto.Parent.LayoutOrder = 0
	local darkAuto, darkButton = C.IconButton(row, "auto", "AUTO OFF", "Primary", nil, 72)
	C.SetKind(darkButton, "Dark")
	darkAuto.LayoutOrder = 2
	for i, name in { "Inventory", "Settings", "Raids", "Quests" } do
		local item = C.IconButton(row, Theme.Icons[name], name, "Primary", nil, 68)
		item.LayoutOrder = 2 + i
	end
	local sort = C.ToolButton(row, Theme.Icons.Sort, nil, { LayoutOrder = 10 })
	local active = C.ToolButton(row, "lock", nil, { LayoutOrder = 11 })
	C.SetToolActive(active, true)
	local secondary = C.Button(row, "", nil, { Kind = "Secondary", Icon = "close", Size = UDim2.fromOffset(44, 48), Radius = 22, LayoutOrder = 12, Confirm = false })
	local disabled = C.Button(row, "", nil, { Icon = "summon", Size = UDim2.fromOffset(56, 60), LayoutOrder = 13 })
	C.SetDisabled(disabled, true)
	local labelled = C.Button(row, "SELL", nil, { Kind = "Danger", Icon = "sell", Size = UDim2.fromOffset(140, 48), LayoutOrder = 14, Confirm = false })
	local _ = sort, secondary, labelled

	-- Unit-card badges and small sizes
	section("Unit cards (equipped check, lock, stars, NEW) and small sizes 12-20 px", 372)
	local cards = C.Frame(bg, { BackgroundTransparency = 1, Position = UDim2.fromOffset(24, 400), Size = UDim2.fromOffset(700, 130) })
	C.List(cards, Enum.FillDirection.Horizontal, 14)
	for i, info in {
		{ Name = "Raizen", Rarity = "Legendary", Level = 9, Stars = 5, Locked = true, Equipped = true },
		{ Name = "Tetsuo", Rarity = "Epic", Level = 7, Stars = 3, Locked = false, Equipped = true, New = true },
		{ Name = "Hikari", Rarity = "Rare", Level = 1, Stars = 1, Locked = true, Equipped = false },
		{ Name = "Bandit", Rarity = "Common", Level = 1, Stars = 0, Locked = false, Equipped = false, New = true },
	} do
		local holder = C.Frame(cards, { BackgroundTransparency = 1, Size = UDim2.fromOffset(100, 124), LayoutOrder = i })
		local card = C.UnitCard(holder, info :: any)
		card.Size = UDim2.fromScale(1, 1)
		if i == 4 then
			C.HighlightCard(card, "Marked")
		end
	end
	local small = C.Frame(bg, { BackgroundColor3 = P.Panel, Position = UDim2.fromOffset(740, 400), Size = UDim2.fromOffset(500, 124) })
	C.Corner(small, 12)
	for row2, px in { 12, 16, 20 } do
		for i, name in Icons.Names do
			if i <= 20 then
				Icons.Create(name, small, { Size = px, Position = UDim2.fromOffset(10 + (i - 1) * 24, 10 + (row2 - 1) * 36) })
			end
		end
	end

	-- Image overrides (Theme.IconAssets): rbxassetid -> placeholder box, local file -> <img> tinted by Color.
	section("Theme.IconAssets overrides: rbxassetid (placeholder) and a local file (tinted / untinted)", 546)
	local assets = C.Frame(bg, { BackgroundColor3 = P.Panel, Position = UDim2.fromOffset(24, 574), Size = UDim2.fromOffset(600, 100) })
	C.Corner(assets, 12)
	Theme.IconAssets.star = "rbxassetid://1234567"
	Theme.IconAssets.check = SVG
	Icons.Create("star", assets, { Size = 72, Position = UDim2.fromOffset(16, 14) })
	Icons.Create("check", assets, { Size = 72, Position = UDim2.fromOffset(110, 14) })
	Icons.Create("check", assets, { Size = 72, Position = UDim2.fromOffset(200, 14), Color = P.Cyan })
	Icons.Create("check", assets, { Size = 48, Position = UDim2.fromOffset(290, 26), Color = P.Blue500 })
	Theme.IconAssets.star = ""
	Theme.IconAssets.check = ""
	Icons.Create("star", assets, { Size = 72, Position = UDim2.fromOffset(370, 14) })
	Icons.Create("check", assets, { Size = 72, Position = UDim2.fromOffset(460, 14) })
end)

-- The real game UI built by the controllers ------------------------------------------------------------------------
local function shot(name: string, captionText: string, width: number?, height: number?)
	write(name, Render.Page(playerGui, { Width = width or 1280, Height = height or 720, Caption = captionText }))
end

shot("01_hud", "HUD (icons)")
local Inventory = session.Controller("InventoryController")
UI:Open("Fighters")
task.wait(0.05)
Inventory:Select(session.Units.Raizen.Uid)
shot("02_fighters", "Fighters window (icons)")
UI:Open("Summon", "B_W1")
task.wait(0.05)
shot("03_summon", "Summon window (icons)")
UI:Open("Settings")
task.wait(0.05)
shot("05_settings", "Settings (icons)")
UI:Close()
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(844, 390))
task.wait(0.05)
shot("06_phone_hud", "Phone 844x390 — HUD (icons)", 844, 390)
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(1280, 720))

print(("client warnings: %d"):format(#rt.Mocks.Warnings))
for _, w in rt.Mocks.Warnings do
	print("  " .. w)
end
process.exit(0)
