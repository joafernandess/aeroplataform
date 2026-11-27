-- UI/Icons: every icon name draws with real (Lune) Instances, so wrong property names or types fail here;
-- uploaded-image override, glyph -> name lookup and recolouring.
local roblox = require("@lune/roblox")
local Runtime = require("../harness/Runtime")

local ICONS = "StarterPlayer/StarterPlayerScripts/Client/UI/Icons"
local THEME = "StarterPlayer/StarterPlayerScripts/Client/UI/Theme"

local function load()
	local rt = Runtime.new({ IsServer = false })
	return rt:Require(ICONS), rt:Require(THEME)
end

local function screen()
	local gui = roblox.Instance.new("ScreenGui")
	local holder = roblox.Instance.new("Frame")
	holder.Size = roblox.UDim2.fromOffset(200, 200)
	holder.Parent = gui
	return holder
end

local function countClass(root, className: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.ClassName == className then
			n += 1
		end
	end
	return n
end

return function(t)
	local expect = t.expect

	t.describe("icons", function()
		t.it("draws every contract name with primitives at 24, 48 and 72 px", function()
			local Icons, Theme = load()
			expect(#Icons.Names).toBe(38) -- 28 HUD icons + 8 navigation icons + luck + click
			local holder = screen()
			for _, name in Icons.Names do
				expect(Icons.Has(name)).toBe(true)
				expect(Theme.IconAssets[name]).toBe("")
				for _, px in { 24, 48, 72 } do
					local icon = Icons.Create(name, holder, { Size = px })
					expect(icon.ClassName).toBe("Frame")
					expect(icon.Parent).toBe(holder)
					expect(icon.Size).toBe(roblox.UDim2.fromOffset(px, px))
					expect(icon:GetAttribute("Icon")).toBe(name)
					local parts = icon:GetDescendants()
					expect(#parts > 2).toBe(true)
					-- Scale-based geometry only, so the drawing follows the container size.
					for _, part in parts do
						if part:IsA("GuiObject") then
							expect(part.Size.X.Offset).toBe(0)
							expect(part.Size.Y.Offset).toBe(0)
							expect(part.Position.X.Offset).toBe(0)
						end
					end
					expect(countClass(icon, "ImageLabel")).toBe(0)
				end
			end
		end)

		t.it("uses an uploaded full-colour image (untinted) when Theme.IconAssets has an asset id", function()
			local Icons, Theme = load()
			Theme.IconAssets.yen = "rbxassetid://1234567"
			local icon = Icons.Create("yen", screen(), { Size = 40, Color = Theme.Colors.Cyan })
			expect(icon.ClassName).toBe("ImageLabel")
			expect(icon.Image).toBe("rbxassetid://1234567")
			expect(icon.ImageColor3).toBe(Theme.Colors.White) -- the PNG keeps its own colours
			expect(icon.BackgroundTransparency).toBe(1)
			expect(icon.Size).toBe(roblox.UDim2.fromOffset(40, 40))
			expect(Icons.Create("yen", screen(), { Color = Theme.Colors.Cyan, Tint = true }).ImageColor3).toBe(Theme.Colors.Cyan)
			Theme.IconAssets.yen = ""
			expect(Icons.Create("yen", screen()).ClassName).toBe("Frame")
		end)

		t.it("gives every HUD menu icon its own colour, a PNG in assets/UI_Icons and an IconAssets slot", function()
			local _, Theme = load()
			local fs = require("@lune/fs")
			local serde = require("@lune/serde")
			local manifest = serde.decode("json", fs.readFile("assets/UI_Icons/manifest.json"))
			local seen = {}
			for _, name in { "shop", "fighters", "settings", "codes", "quests", "teleport", "inventory", "mounts", "upgrades", "stats", "index", "update", "yen" } do
				local color = Theme.IconColors[name]
				expect(color ~= nil).toBe(true)
				local key = string.format("%.3f,%.3f,%.3f", color.R, color.G, color.B)
				expect(seen[key]).toBeNil() -- no two icons share a colour
				seen[key] = true
				expect(Theme.IconAssets[name]).toBe("")
				expect(manifest[name] ~= nil).toBe(true)
				expect(fs.isFile("assets/UI_Icons/" .. manifest[name].png)).toBe(true)
			end
		end)

		t.it("draws flat (no outline around the shapes) unless Bordered is asked for", function()
			local Icons = load()
			local flat = Icons.Create("shop", screen(), { Size = 48 })
			local bordered = Icons.Create("shop", screen(), { Size = 48, Bordered = true })
			expect(countClass(bordered, "Frame") > countClass(flat, "Frame")).toBe(true)
		end)

		t.it("resolves names, Theme.Icons keys and glyphs (reverse lookup)", function()
			local Icons, Theme = load()
			expect(Icons.Resolve("settings")).toBe("settings")
			expect(Icons.Resolve("Settings")).toBe("settings")
			expect(Icons.Resolve("Inventory")).toBe("fighters")
			expect(Icons.Resolve("Equipped")).toBe("check")
			expect(Icons.Resolve(Theme.Icons.Inventory)).toBe("fighters")
			expect(Icons.Resolve(Theme.Icons.Yen)).toBe("yen")
			expect(Icons.Resolve(Theme.Icons.Equipped)).toBe("check")
			expect(Icons.Resolve(Theme.Icons.Raids)).toBe("raids")
			expect(Icons.Resolve(Theme.Icons.Close)).toBe("close")
			expect(Icons.Resolve(Theme.Icons.Settings)).toBe("settings")
			expect(Icons.Resolve(Theme.Icons.Power)).toBe("power")
			expect(Icons.Resolve(Theme.Icons.Sort)).toBe("sort")
			expect(Icons.Resolve(Theme.Icons.Plus)).toBe("plus")
			expect(Icons.Resolve("nope")).toBeNil()
			expect(Icons.Resolve("")).toBeNil()
			expect(Icons.Resolve(nil)).toBeNil()
			expect(Icons.Glyph("yen")).toBe("¥")
			-- Every glyph maps to at most one icon, so menus never show the wrong icon.
			local seen = {}
			for key, glyph in Theme.Icons do
				expect(seen[glyph]).toBeNil()
				seen[glyph] = key
			end
			-- Glyph and name give the same drawing.
			local holder = screen()
			expect(Icons.Create(Theme.Icons.Upgrades, holder):GetAttribute("Icon")).toBe("upgrades")
		end)

		t.it("falls back to a glyph label for unknown names and recolours icons", function()
			local Icons, Theme = load()
			local holder = screen()
			local filter = Icons.Create(Theme.Icons.Filter, holder, { Size = 24 })
			expect(filter.ClassName).toBe("TextLabel")
			expect(filter.Text).toBe(Theme.Icons.Filter)
			local text = Icons.Create("?", holder)
			expect(text.Text).toBe("?")

			local icon = Icons.Create("check", holder, { Size = 32 })
			Icons.SetColors(icon, { Color = Theme.Colors.Blue500 })
			local blue = 0
			for _, d in icon:GetDescendants() do
				if d:IsA("Frame") and d.BackgroundColor3 == Theme.Colors.Blue500 then
					blue += 1
				end
			end
			expect(blue).toBe(2)
			local swapped = Icons.Swap(icon, "close")
			expect(swapped:GetAttribute("Icon")).toBe("close")
			expect(swapped.Parent).toBe(holder)
			expect(icon.Parent).toBeNil()
			expect(Icons.Create("lock", holder, { Outline = false }):FindFirstChildWhichIsA("Frame") ~= nil).toBe(true)
		end)
	end)
end
