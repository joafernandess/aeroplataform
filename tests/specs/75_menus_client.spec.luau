-- Reworked HUD on the REAL client bridged to the REAL server (tools/ui-preview/Session): side menu grids, top-right
-- Update Log card, minimal player info, the Fighters NEW badge and every new window (Codes, Teleport, Index,
-- Inventory, Achievements, Stats, Mounts, Shop closed state).
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Session = require("../../tools/ui-preview/Session")
local Fake = require("../../tools/ui-preview/FakeRoblox")

local CLIENT = "StarterPlayer/StarterPlayerScripts/Client/"

local function isInside(instance, ancestor): boolean
	local node = instance.Parent
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end

local function find(root, name: string)
	for _, child in root:GetDescendants() do
		if child.Name == name then
			return child
		end
	end
	return nil
end

local function countNamed(root, name: string): number
	local n = 0
	for _, child in root:GetDescendants() do
		if child.Name == name then
			n += 1
		end
	end
	return n
end

local function hasButtons(root): boolean
	for _, child in root:GetDescendants() do
		if child.ClassName == "TextButton" then
			return true
		end
	end
	return false
end

return function(t)
	local expect = t.expect

	t.describe("side menus", function()
		t.it("builds both menus in the requested order, in the reference style, and every button opens a real window", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Navigation = s.Runtime:Require(CLIENT .. "UI/Navigation")
			-- Reading order of a grid: rows top to bottom, buttons left to right; also returns the row sizes.
			local function order(grid)
				local rows = {}
				for _, child in grid:GetChildren() do
					if child.ClassName == "Frame" then
						table.insert(rows, child)
					end
				end
				table.sort(rows, function(a, b)
					return a.LayoutOrder < b.LayoutOrder
				end)
				local names, sizes = {}, {}
				for _, row in rows do
					local buttons = {}
					for _, child in row:GetChildren() do
						if child.ClassName == "Frame" then
							table.insert(buttons, child)
						end
					end
					table.sort(buttons, function(a, b)
						return a.LayoutOrder < b.LayoutOrder
					end)
					for _, button in buttons do
						table.insert(names, button.Name)
					end
					table.insert(sizes, tostring(#buttons))
				end
				return table.concat(names, ","), table.concat(sizes, ",")
			end
			local left, leftRows = order(UI.LeftNav)
			local right, rightRows = order(UI.RightNav)
			expect(left).toBe("Shop,Fighters,Settings,Codes,Quests,Teleport")
			expect(leftRows).toBe("1,2,2,1") -- wide Shop, 2x2, wide Teleport
			expect(right).toBe("Items,Mounts,Achievements,Stats,Index")
			expect(rightRows).toBe("2,2,1") -- 2x2, wide Index
			-- Reference style: face tinted by the icon colour, border in that colour, dark rim + shadow, the name
			-- inside the button and the key badge (PC).
			local Theme = s.Runtime:Require(CLIENT .. "UI/Theme")
			local P = Theme.Colors
			for _, side in { Navigation.Left, Navigation.Right } do
				for _, entry in side do
					local button = UI.MenuButtons[entry.Window]
					local color = Theme.IconColors[entry.Icon]
					expect(button:FindFirstChildOfClass("UIStroke").Color).toBe(color)
					expect(button:FindFirstChildOfClass("UIGradient").Color.Keypoints[1].Value).toBe(color:Lerp(P.Ink, 0.6))
					expect(button.Parent:FindFirstChild("Rim") ~= nil).toBe(true)
					expect(button.Parent:FindFirstChild("Shadow") ~= nil).toBe(true)
					expect(find(button, "Caption").Text).toBe(entry.Label)
					local key = find(button, "KeyBadge")
					expect(key ~= nil and key:FindFirstChildOfClass("TextLabel").Text == entry.Key.Name).toBe(true)
					expect(find(button, "Icon") ~= nil).toBe(true)
					-- wide buttons fill the row and get the idle light sweep
					expect(find(button, "SweepClip") ~= nil).toBe(entry.Wide == true)
				end
			end
			expect(UI.MenuButtons.Shop.Size.X.Offset).toBe(UI.LeftNav.Size.X.Offset)
			-- Hotkeys: one per button, none on Roblox's default keys (WASD, I/O zoom) or X (clear target).
			local count = 0
			for key in Navigation.Hotkeys do
				count += 1
				expect(table.find({ "W", "A", "S", "D", "I", "O", "X" }, key.Name)).toBeNil()
			end
			expect(count).toBe(11)
			-- hover lightens the face, press darkens it, leaving restores it
			local shop = UI.MenuButtons.Shop
			local function top()
				return shop:FindFirstChildOfClass("UIGradient").Color.Keypoints[1].Value
			end
			local color = Theme.IconColors.shop
			shop.MouseEnter:Fire()
			task.wait(0.02)
			expect(top()).toBe(color:Lerp(P.Ink, 0.44))
			shop.MouseButton1Down:Fire()
			task.wait(0.02)
			expect(top()).toBe(color:Lerp(P.Ink, 0.78))
			shop.MouseButton1Up:Fire()
			shop.MouseLeave:Fire()
			task.wait(0.02)
			expect(top()).toBe(color:Lerp(P.Ink, 0.6))
			expect(UI.LeftNav.AnchorPoint.X).toBe(0)
			expect(UI.RightNav.AnchorPoint.X).toBe(1)
			for _, side in { Navigation.Left, Navigation.Right } do
				for _, entry in side do
					expect(UI.Windows[entry.Window] ~= nil).toBe(true)
					UI.MenuButtons[entry.Window].Activated:Fire()
					task.wait(0.03)
					expect(UI:IsOpen(entry.Window)).toBe(true)
					-- Second press closes it again (toggle).
					UI.MenuButtons[entry.Window].Activated:Fire()
					task.wait(0.02)
					expect(UI:IsOpen(entry.Window)).toBe(false)
				end
			end
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("opens windows at their responsive scale; the HUD keeps only the Yen pill top-left", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local HUD = s.Controller("HUDController")
			UI:Open("Codes")
			-- (FakeRoblox tweens jump to their goal: the pop from 86% ends on the responsive scale and the scrim fades in.)
			local scale = UI.Windows.Codes.Frame:FindFirstChildOfClass("UIScale")
			task.wait(0.05)
			expect(math.abs(scale.Scale - 1) < 1e-3).toBe(true)
			expect(UI.Scrim.BackgroundTransparency).toBe(0.55)
			UI:Close()
			local root = UI:GetRoot()
			local info = find(root, "PlayerInfo")
			expect(info ~= nil).toBe(true)
			expect(isInside(HUD.CurrencyPills.Yen.Frame, info)).toBe(true)
			-- Removed: Power pill, Yen/min caption, AUTO button, fighter slot bar, STATS toggle.
			expect(HUD.PowerPill).toBeNil()
			expect(HUD.Animated.Power).toBeNil()
			for _, name in { "YenPerMinute", "Auto", "TeamBar", "StatsToggle", "PowerRow" } do
				expect(find(root, name)).toBeNil()
			end
			-- The left grid sits below the player info, the right grid below the Update Log card.
			local navScale = UI.LeftNav:FindFirstChild("NavScale").Scale
			local leftTop = UI.LeftNav.Position.Y.Offset - UI.LeftNav.Size.Y.Offset * navScale / 2
			expect(leftTop >= HUD:InfoBottom()).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("counts fighters obtained this session on the Fighters button and clears it when Fighters opens", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Inventory = s.Controller("InventoryController")
			local button = UI.MenuButtons.Fighters
			expect(UI.MenuBadges.Fighters or 0).toBe(0)
			expect(s.Net.Request("Summon", "B_W1", 3).ok).toBe(true)
			task.wait(0.1)
			expect(UI.MenuBadges.Fighters).toBe(3)
			expect(Inventory:NewCount()).toBe(3)
			local badge = button:FindFirstChild("Badge")
			expect(badge.Visible).toBe(true)
			expect(badge.Count.Text).toBe("3")
			UI:Open("Fighters")
			task.wait(0.05)
			expect(UI.MenuBadges.Fighters).toBe(0)
			expect(badge.Visible).toBe(false)
			UI:Close()
			-- Already-seen fighters stay seen; only later pulls count again.
			s.Net.Request("Summon", "B_W1", 1)
			task.wait(0.1)
			expect(UI.MenuBadges.Fighters).toBe(1)
			-- Badge text caps at 99+ and hides at 0.
			UI:SetMenuBadge("Settings", 120)
			expect(UI.MenuButtons.Settings:FindFirstChild("Badge").Count.Text).toBe("99+")
			UI:SetMenuBadge("Settings", 0)
			expect(UI.MenuButtons.Settings:FindFirstChild("Badge").Visible).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("fits both grids on a phone without covering the Yen pill or the Update Log card", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local HUD = s.Controller("HUDController")
			local Log = s.Controller("UpdateLogController")
			Fake.SetProperty(s.Camera, "ViewportSize", roblox.Vector2.new(667, 375))
			task.wait(0.05)
			local rootHeight = UI:GetRootSize().Y
			for _, pair in { { UI.LeftNav, HUD:InfoBottom() }, { UI.RightNav, Log.CardHolder.Position.Y.Offset + Log.CardHolder.Size.Y.Offset * Log.CardHolder:FindFirstChildOfClass("UIScale").Scale } } do
				local grid, above = pair[1], pair[2]
				local scale = grid:FindFirstChild("NavScale").Scale
				local half = grid.Size.Y.Offset * scale / 2
				expect(scale < 1).toBe(true)
				expect(grid.Position.Y.Offset - half >= above).toBe(true)
				expect(grid.Position.Y.Offset + half <= rootHeight).toBe(true)
			end
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)

	t.describe("update log", function()
		t.it("shows the latest update on the card, lists every entry and remembers that it was read", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Log = s.Controller("UpdateLogController")
			local UpdateLog = s.Runtime:Require("ReplicatedStorage/Shared/Config/UpdateLog")
			local latest = UpdateLog.GetLatest()
			expect(Log.CardHolder.AnchorPoint.X).toBe(1)
			expect(Log.CardTitle.Text).toBe(latest.Title)
			expect(Log.NewTag.Visible).toBe(true)
			Log.Card.Activated:Fire()
			task.wait(0.1)
			expect(UI:IsOpen("UpdateLog")).toBe(true)
			expect(Log.NewTag.Visible).toBe(false)
			expect(s.Data.Settings.LastSeenUpdate).toBe(latest.Id)
			for _, entry in UpdateLog.Entries do
				local card = Log.List:FindFirstChild(entry.Id)
				expect(card ~= nil).toBe(true)
				expect(countNamed(card, "Bullet")).toBe(#entry.Items)
			end
			expect(find(Log.List, "Latest") ~= nil).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)

	t.describe("windows", function()
		t.it("redeems a code from the Codes window and reports server errors inline", function()
			local s = Session.new()
			local Codes = s.Controller("CodesController")
			local ServerCodes = s.Harness.Runtime:Require("ReplicatedStorage/Shared/Config/Codes")
			ServerCodes.ByCode.TESTER = { Code = "TESTER", Rewards = { Yen = 123 } }
			s.Controller("UIController"):Open("Codes")
			local yen = s.Data.Currencies.Yen
			Codes.Input.Text = "  tester "
			Codes:Redeem()
			expect(s.Data.Currencies.Yen).toBe(yen + 123)
			expect(string.find(Codes.Status.Text, "redeemed", 1, true) ~= nil).toBe(true)
			expect(Codes.Input.Text).toBe("")
			Codes.Input.Text = "TESTER"
			Codes:Redeem()
			expect(Codes.Status.Text).toBe("You already redeemed that code.")
			Codes.Input.Text = "   "
			Codes:Redeem()
			expect(Codes.Status.Text).toBe("Type a code first.")
			expect(s.Data.Currencies.Yen).toBe(yen + 123)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("lists world 1 teleport points and teleports with GO", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local TP = s.Controller("TeleportController")
			local Worlds = s.Runtime:Require("ReplicatedStorage/Shared/Config/Worlds")
			UI:Open("Teleport")
			task.wait(0.05)
			local points = Worlds.GetTeleportPoints("W1")
			for _, point in points do
				expect(TP.List:FindFirstChild(point.Id) ~= nil).toBe(true)
			end
			local camp
			for _, point in points do
				if point.Id == "zone_Camp" then
					camp = point
				end
			end
			find(TP.List:FindFirstChild("zone_Camp"), "Go").Activated:Fire()
			task.wait(0.1)
			local pos = s.Player.Character.HumanoidRootPart.Position
			expect(pos.X).toBe(camp.Position[1])
			expect(pos.Z).toBe(camp.Position[3])
			expect(UI:IsOpen("Teleport")).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("shows discovered fighters and ??? silhouettes in the Index", function()
			local s = Session.new()
			local Index = s.Controller("IndexController")
			local State = s.Runtime:Require(CLIENT .. "State")
			s.Controller("UIController"):Open("Index")
			task.wait(0.05)
			local found, total = Index.Progress(State.Data)
			expect(total > 0).toBe(true)
			expect(found >= 1 and found <= total).toBe(true)
			local hidden = 0
			for _, child in Index.List:GetDescendants() do
				if string.sub(child.Name, 1, 7) == "Hidden_" then
					hidden += 1
				end
			end
			expect(hidden).toBe(total - found)
			for unitId in State.Data.Discovered do
				expect(find(Index.List, unitId) ~= nil).toBe(true)
			end
			expect(Index.Percent.Text).toBe(("%d%%"):format(math.floor(found / total * 100)))
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("shows the wallet in the Inventory window and an honest empty state while items are off", function()
			local s = Session.new()
			local Items = s.Controller("ItemsController")
			local NumberFormat = s.Runtime:Require("ReplicatedStorage/Shared/Modules/NumberFormat")
			s.Controller("UIController"):Open("Items")
			task.wait(0.05)
			local tile = find(Items.List, "Yen")
			expect(tile ~= nil).toBe(true)
			expect(tile:FindFirstChild("Value").Text).toBe(NumberFormat.Abbreviate(s.Data.Currencies.Yen))
			expect(find(Items.List, "EmptyState") ~= nil).toBe(true)
			expect(hasButtons(Items.List)).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("badges claimable achievements and claims them from the Achievements window", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Ach = s.Controller("AchievementsController")
			local State = s.Runtime:Require(CLIENT .. "State")
			s.Data.Stats.TotalKills = math.max(s.Data.Stats.TotalKills, 100)
			s.Harness.Services.DataService:MarkDirty(s.Player, "Stats")
			task.wait(0.1)
			local claimable = Ach.ClaimableCount(State.Data)
			expect(claimable >= 1).toBe(true)
			expect(UI.MenuBadges.Achievements).toBe(claimable)
			UI:Open("Achievements")
			task.wait(0.05)
			find(Ach.List:FindFirstChild("A_Kills"), "Claim").Activated:Fire()
			task.wait(0.1)
			expect(s.Data.Achievements.A_Kills).toBe(1)
			expect(UI.MenuBadges.Achievements).toBe(claimable - 1)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("keeps the Quests badge in sync with claimable quests", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Quests = s.Controller("QuestController")
			local State = s.Runtime:Require(CLIENT .. "State")
			expect(UI.MenuBadges.Quests or 0).toBe(Quests.ClaimableCount(State.Data))
			UI:Open("Quests")
			task.wait(0.05)
			expect(Quests.List:FindFirstChild(State.Data.Quests.MainCurrent) ~= nil).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("prepared menus (Mounts, Shop while closed) say so and have no dead buttons", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			for _, pair in { { "Mounts", "MountsController" }, { "Shop", "ShopController" } } do
				UI:Open(pair[1])
				task.wait(0.03)
				local list = s.Controller(pair[2]).List
				expect(find(list, "EmptyState") ~= nil).toBe(true)
				expect(hasButtons(list)).toBe(false)
			end
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
