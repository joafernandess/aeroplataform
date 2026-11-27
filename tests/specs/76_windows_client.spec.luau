-- Window system (template, open/close animation, drag, Escape, selected menu button) and the window contents of the
-- UI rework, on the REAL client bridged to the REAL server (tools/ui-preview/Session).
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Session = require("../../tools/ui-preview/Session")

local CLIENT = "StarterPlayer/StarterPlayerScripts/Client/"

local function find(root, name: string)
	for _, child in root:GetDescendants() do
		if child.Name == name then
			return child
		end
	end
	return nil
end

local function count(root, predicate): number
	local n = 0
	for _, child in root:GetDescendants() do
		if predicate(child) then
			n += 1
		end
	end
	return n
end

return function(t)
	local expect = t.expect

	t.describe("window system", function()
		t.it("uses one template: blue title bar, gold accents, red X, fading group", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Theme = s.Runtime:Require(CLIENT .. "UI/Theme")
			for name, window in UI.Windows do
				expect(window.Group ~= nil and window.Group.ClassName == "CanvasGroup").toBe(true)
				expect(find(window.Header, "GoldLine").BackgroundColor3).toBe(Theme.Colors.Gold)
				expect(find(window.Group, "GoldRim") ~= nil).toBe(true)
				expect(window.CloseButton.Name).toBe("Close")
				-- the X sits inside the title bar (the group clips anything outside the window)
				expect(window.CloseButton.Parent).toBe(window.Group)
				local _ = name
			end
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("fades windows in and out, hides them after closing and never duplicates them", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local window = UI.Windows.Quests
			local before = 0
			for _ in UI.Windows do
				before += 1
			end
			UI:Open("Quests")
			task.wait(0.05)
			expect(window.Frame.Visible).toBe(true)
			expect(window.Group.GroupTransparency).toBe(0)
			UI:Close()
			expect(UI:IsOpen("Quests")).toBe(false)
			task.wait(0.05)
			expect(window.Frame.Visible).toBe(false)
			expect(window.Group.GroupTransparency).toBe(1)
			expect(UI.Scrim.Visible).toBe(false)
			-- reopening restores it; opening another window closes the first one
			UI:Open("Quests")
			UI:Open("Stats")
			task.wait(0.05)
			expect(window.Frame.Visible).toBe(false)
			expect(UI.Windows.Stats.Frame.Visible).toBe(true)
			local after = 0
			for _ in UI.Windows do
				after += 1
			end
			expect(after).toBe(before)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("closes the open window with Escape and keeps its menu button highlighted while open", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local C = s.Runtime:Require(CLIENT .. "UI/Components")
			local UIS = s.Services.UserInputService
			UI.MenuButtons.Codes.Activated:Fire()
			task.wait(0.03)
			expect(UI:IsOpen("Codes")).toBe(true)
			expect(C.IsNavSelected(UI.MenuButtons.Codes)).toBe(true)
			expect(C.IsNavSelected(UI.MenuButtons.Shop)).toBe(false)
			UIS.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.Escape, UserInputType = roblox.Enum.UserInputType.Keyboard }, true)
			task.wait(0.03)
			expect(UI:IsOpen("Codes")).toBe(false)
			expect(C.IsNavSelected(UI.MenuButtons.Codes)).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("drags a window by its title bar and keeps it on screen", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local UIS = s.Services.UserInputService
			local Enum = roblox.Enum
			local window = UI.Windows.Index
			UI:Open("Index")
			task.wait(0.03)
			local start = window.Frame.Position
			local down = { UserInputType = Enum.UserInputType.MouseButton1, Position = roblox.Vector3.new(400, 120, 0) }
			window.Header.InputBegan:Fire(down)
			UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = roblox.Vector3.new(460, 150, 0) })
			task.wait(0.02)
			expect(window.Frame.Position.X.Offset - start.X.Offset).toBe(60)
			expect(window.Frame.Position.Y.Offset - start.Y.Offset).toBe(30)
			-- dragging far away is clamped: the title bar stays reachable
			UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = roblox.Vector3.new(5000, -5000, 0) })
			task.wait(0.02)
			local root = UI:GetRootSize()
			local scale = window.Frame:FindFirstChildOfClass("UIScale").Scale
			local cx = root.X * window.Frame.Position.X.Scale + window.Frame.Position.X.Offset
			local cy = root.Y * window.Frame.Position.Y.Scale + window.Frame.Position.Y.Offset
			expect(cx - window.Frame.Size.X.Offset * scale / 2 <= root.X - 60 + 0.01).toBe(true)
			expect(cy - window.Frame.Size.Y.Offset * scale / 2 >= -0.01).toBe(true)
			UIS.InputEnded:Fire(down)
			-- after release, moving the mouse no longer moves it
			local held = window.Frame.Position
			UIS.InputChanged:Fire({ UserInputType = Enum.UserInputType.MouseMovement, Position = roblox.Vector3.new(0, 0, 0) })
			task.wait(0.02)
			expect(window.Frame.Position).toBe(held)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)

	t.describe("window contents", function()
		t.it("Teleport lists the current world's areas and the other worlds locked with their requirements", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local TP = s.Controller("TeleportController")
			local Worlds = s.Runtime:Require("ReplicatedStorage/Shared/Config/Worlds")
			UI:Open("Teleport")
			task.wait(0.05)
			for _, world in Worlds.List do
				if world.Id ~= "W1" then
					local row = TP.List:FindFirstChild("World_" .. world.Id)
					expect(row ~= nil).toBe(true)
					expect(find(row, "Locked") ~= nil).toBe(true)
					local requirement = find(row, "Requirement").Text
					expect(string.find(requirement, "Coming soon", 1, true) ~= nil).toBe(true)
					if world.Requirements.Level then
						expect(string.find(requirement, "Level " .. world.Requirements.Level, 1, true) ~= nil).toBe(true)
					end
				end
			end
			expect(TP.RequirementText(Worlds.Get("W2"))).toBe("25K Yen · Level 10 · Unlock Shinobi Valley")
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("Stats counts Yen spent this session and shows lifetime damage", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Stats = s.Controller("SessionStatsController")
			s.Harness.Services.EconomyService:Remove(s.Player, "Yen", 280, "Test")
			task.wait(0.1)
			expect(Stats.YenSpent).toBe(280)
			UI:Open("Stats")
			task.wait(0.05)
			expect(Stats.SessionLabels["Yen spent"].Text).toBe("280")
			expect(find(Stats.List, "Damage") ~= nil).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("Index has world tabs; Update Log shows its sections", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Index = s.Controller("IndexController")
			local Log = s.Controller("UpdateLogController")
			local UpdateLog = s.Runtime:Require("ReplicatedStorage/Shared/Config/UpdateLog")
			UI:Open("Index")
			task.wait(0.05)
			expect(find(Index.Window.Content, "WorldTabs") ~= nil).toBe(true)
			expect(Index.SelectedWorld).toBe("Shinobi Valley")
			UI:Open("UpdateLog")
			task.wait(0.05)
			local entry = UpdateLog.GetLatest()
			local card = Log.List:FindFirstChild(entry.Id)
			expect(count(card, function(c)
				return c.Name == "Section"
			end)).toBe(#entry.Sections)
			expect(find(card, "Section").Text).toBe(string.upper(entry.Sections[1].Title))
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("open Shop shows category tabs, item cards with prices and buys through the server", function()
			local s = Session.new()
			local Features = s.Runtime:Require("ReplicatedStorage/Shared/Config/Features")
			local ServerFeatures = s.Harness.Runtime:Require("ReplicatedStorage/Shared/Config/Features")
			Features.Shop, ServerFeatures.Shop = true, true
			local UI = s.Controller("UIController")
			local ShopC = s.Controller("ShopController")
			local Shop = s.Runtime:Require("ReplicatedStorage/Shared/Config/Shop")
			UI:Open("Shop")
			task.wait(0.05)
			expect(ShopC.Body.Visible).toBe(true)
			expect(find(ShopC.Body, "Categories") ~= nil).toBe(true)
			local first = Shop.Items[1]
			local card = ShopC.Grid:FindFirstChild(first.Id)
			expect(card ~= nil).toBe(true)
			expect(find(card, "Price") ~= nil).toBe(true)
			s.Data.Currencies.Yen = 100000
			local before = s.Data.Inventory.Items[next(first.Grants.Items)] or 0
			find(card, "Buy1").Activated:Fire()
			task.wait(0.1)
			expect((s.Data.Inventory.Items[next(first.Grants.Items)] or 0) - before).toBe(1)
			Features.Shop, ServerFeatures.Shop = false, false
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("Inventory shows owned items as a grid with a details panel when items exist", function()
			local s = Session.new()
			local Features = s.Runtime:Require("ReplicatedStorage/Shared/Config/Features")
			Features.Items = true
			local UI = s.Controller("UIController")
			local Items = s.Controller("ItemsController")
			s.Data.Inventory.Items.EvolutionStone = 3
			s.Data.Inventory.Items.XPPotionSmall = 12
			s.Harness.Services.DataService:MarkDirty(s.Player, "Inventory")
			task.wait(0.1)
			UI:Open("Items")
			task.wait(0.05)
			expect(Items.ItemsPane.Visible).toBe(true)
			expect(Items.Grid:FindFirstChild("EvolutionStone") ~= nil).toBe(true)
			expect(Items.Grid:FindFirstChild("XPPotionSmall") ~= nil).toBe(true)
			-- best rarity first is selected; the details panel shows it with its actions
			expect(Items.SelectedItem).toBe("EvolutionStone")
			expect(find(Items.Details, "ItemName").Text).toBe("Evolution Stone")
			expect(find(Items.Details, "Lock") ~= nil).toBe(true)
			Items.Grid:FindFirstChild("XPPotionSmall").Activated:Fire()
			task.wait(0.03)
			expect(find(Items.Details, "ItemName").Text).toBe("Small XP Potion")
			Features.Items = false
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("Mounts renders owned mounts with Equip once a mount system provides them", function()
			local s = Session.new()
			local Mounts = s.Runtime:Require("ReplicatedStorage/Shared/Config/Mounts")
			local def = { Id = "M_Test", Name = "Test Cloud", Rarity = "Epic" }
			table.insert(Mounts.List, def)
			Mounts.ById.M_Test = def
			local UI = s.Controller("UIController")
			local MountsC = s.Controller("MountsController")
			local State = s.Runtime:Require(CLIENT .. "State")
			State.Data.Mounts = { M_Test = true }
			UI:Open("Mounts")
			task.wait(0.05)
			expect(MountsC.Grid.Visible).toBe(true)
			local card = MountsC.Grid:FindFirstChild("M_Test")
			expect(card ~= nil and find(card, "Equip") ~= nil).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
