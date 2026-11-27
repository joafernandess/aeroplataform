-- Reworked HUD on the REAL client bridged to the REAL server (tools/ui-preview/Session): side menu grids, top-right
-- Update Log card, minimal player info, the Fighters NEW badge and every new window (Codes, Teleport, Index,
-- Inventory, Upgrades, Stats, Mounts, Shop closed state).
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
			expect(right).toBe("Items,Mounts,Upgrades,Stats,Index")
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
				expect(countNamed(card, "Bullet")).toBe(UpdateLog.ItemCount(entry))
				expect(countNamed(card, "Section")).toBe(#entry.Sections)
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

		t.it("shows discovered fighters and ??? silhouettes in the Fighter Index, with filters and the discovered bar", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Index = s.Controller("IndexController")
			local State = s.Runtime:Require(CLIENT .. "State")
			local Units = s.Runtime:Require("ReplicatedStorage/Shared/Config/Units")
			UI:Open("Index")
			task.wait(0.05)
			local found, total = Index.Progress(State.Data)
			expect(total > 0).toBe(true)
			expect(found >= 1 and found <= total).toBe(true)
			expect(find(Index.Bar.Frame, "Label").Text).toBe("Fighters discovered")
			expect(find(Index.Bar.Frame, "Count").Text).toBe(("%d / %d"):format(found, total))
			-- The selected world's cards: discovered ones by id, the others as Hidden_<Rarity> silhouettes ("???")
			local group = Index:_group()
			local worldFound, worldTotal = Index.Progress(State.Data, group.World)
			local hidden, cards = 0, 0
			for _, child in Index.Grid:GetChildren() do
				if child.ClassName == "TextButton" then
					cards += 1
					if string.sub(child.Name, 1, 7) == "Hidden_" then
						hidden += 1
						expect(find(child, "FighterName").Text).toBe("???")
					end
				end
			end
			expect(cards).toBe(worldTotal)
			expect(hidden).toBe(worldTotal - worldFound)
			for _, def in group.Units do
				if State.Data.Discovered[def.Id] then
					expect(find(find(Index.Grid, def.Id), "FighterName").Text).toBe(def.Name)
				end
			end
			-- Rarity filter: only that rarity's cards stay
			local rarity = group.Units[1].Rarity
			Index:SetFilter(rarity)
			for _, child in Index.Grid:GetChildren() do
				if child.ClassName == "TextButton" then
					local def = Units.Get(child.Name)
					expect(if def then def.Rarity else string.sub(child.Name, 8)).toBe(rarity)
				end
			end
			Index:SetFilter("All")
			-- Clicking a card fills the info box (rarity, world, how to obtain it)
			Index.Grid:FindFirstChildWhichIsA("TextButton").Activated:Fire()
			task.wait(0.02)
			expect(Index.Selected ~= nil).toBe(true)
			expect(find(Index.WorldPanel.Info, "Obtain") ~= nil).toBe(true)
			expect(find(Index.WorldPanel.Info, "World") ~= nil).toBe(true)
			-- One banner per world; worlds without a collection in this build are "???"
			local banners = 0
			for _, child in Index.WorldPanel.List:GetChildren() do
				if child.ClassName == "TextButton" then
					banners += 1
				end
			end
			expect(banners).toBe(#s.Runtime:Require("ReplicatedStorage/Shared/Config/Worlds").List)
			expect(find(Index.WorldPanel.List, group.World) ~= nil).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("announces new discoveries with an Index badge and pops their card", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Index = s.Controller("IndexController")
			local Units = s.Runtime:Require("ReplicatedStorage/Shared/Config/Units")
			local group = Index:_group()
			local newId = nil
			for _, def in group.Units do
				if not s.Data.Discovered[def.Id] then
					newId = def.Id
					break
				end
			end
			expect(newId ~= nil).toBe(true)
			s.Harness.Services.UnitService.MarkDiscovered(s.Player, s.Data, newId)
			task.wait(0.1)
			expect(UI.MenuBadges.Index).toBe(1)
			expect(Index.Fresh[newId]).toBe(true)
			UI:Open("Index")
			task.wait(0.05)
			expect(UI.MenuBadges.Index).toBe(0)
			expect(find(find(Index.Grid, newId), "FighterName").Text).toBe(Units.Get(newId).Name)
			expect(next(Index.Fresh)).toBeNil()
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("keeps the Inventory to items only (no wallet) with an honest empty state while items are off", function()
			local s = Session.new()
			local Items = s.Controller("ItemsController")
			s.Controller("UIController"):Open("Items")
			task.wait(0.05)
			expect(Items.Wallet).toBeNil()
			expect(find(Items.Window.Content, "Yen")).toBeNil()
			expect(find(Items.List, "EmptyState") ~= nil).toBe(true)
			expect(hasButtons(Items.List)).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("Upgrades: milestone cards with real states, the details panel, CLAIM and the menu badge", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Up = s.Controller("UpgradeController")
			local State = s.Runtime:Require(CLIENT .. "State")
			local Progression = s.Runtime:Require("ReplicatedStorage/Shared/Config/Progression")
			s.Data.Stats.TotalKills = 60 -- Yen I needs 50 kills, Damage I needs 500
			s.Harness.Services.DataService:MarkDirty(s.Player, "Stats")
			task.wait(0.1)
			local _, total, claimable = Up:Counts(State.Data)
			expect(total).toBe(#Progression.Milestones)
			expect(claimable >= 1).toBe(true)
			expect(UI.MenuBadges.Upgrades).toBe(claimable)
			UI:Open("Upgrades")
			task.wait(0.05)
			-- One card per milestone, names generated from the config ("Yen I"), states from the shared rules
			local cards = 0
			for _, child in Up.Grid:GetChildren() do
				if child.ClassName == "TextButton" then
					cards += 1
				end
			end
			expect(cards).toBe(total)
			expect(find(find(Up.Grid, "YEN_1"), "UpgradeName").Text).toBe("Yen I")
			expect(find(find(Up.Grid, "YEN_1"), "ClaimTag") ~= nil).toBe(true)
			expect(Up:Info(State.Data, Progression.GetMilestone("YEN_2")).State).toBe("Locked")
			expect(Up:Info(State.Data, Progression.GetMilestone("DMG_1")).State).toBe("InProgress")
			expect(Up:Info(State.Data, Progression.GetMilestone("DMG_1")).ProgressText).toBe("60 / 500")
			-- Default selection = first claimable; the panel shows the bonus, requirement and state
			expect(Up.Selected).toBe("YEN_1")
			local panel = Up.Details.Frame
			expect(find(panel, "DetailName").Text).toBe("Yen I")
			expect(find(panel, "Bonus").Text).toBe("+5% YEN")
			expect(find(panel, "Requirement").Text).toBe("Defeat 50 enemies.")
			expect(find(panel, "State").Text).toBe("READY TO CLAIM")
			expect(Up.Details.ClaimButton.Visible).toBe(true)
			-- Server rejects a locked milestone
			expect(State.Request("ClaimMilestone", "YEN_3").ok).toBe(false)
			expect(s.Data.Milestones.YEN_3).toBeNil()
			-- CLAIM
			Up.Details.ClaimButton.Activated:Fire()
			task.wait(0.1)
			expect(s.Data.Milestones.YEN_1).toBe(true)
			expect(find(panel, "State").Text).toBe("COMPLETED")
			expect(find(panel, "Total").Text).toBe("Active Yen bonus: +5%")
			expect(UI.MenuBadges.Upgrades).toBe(claimable - 1)
			expect(find(Up.Bar.Frame, "Count").Text).toBe(("1 / %d"):format(total))
			expect(Up:Info(State.Data, Progression.GetMilestone("YEN_2")).State).toBe("InProgress")
			-- Selecting a locked card: no CLAIM, says what to do first
			find(Up.Grid, "YEN_3").Activated:Fire()
			task.wait(0.02)
			expect(find(panel, "State").Text).toBe("LOCKED")
			expect(find(panel, "Note").Text).toBe("Claim Yen II first.")
			expect(Up.Details.ClaimButton.Visible).toBe(false)
			-- Play time milestones read hours
			expect(find(find(Up.Grid, "LUCK_1"), "Text").Text).toBe("0h / 2h")
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

		t.it("prepared menus (Mounts, Shop without game passes yet) say so and have no dead buttons", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			UI:Open("Mounts")
			task.wait(0.03)
			local mounts = s.Controller("MountsController")
			expect(find(mounts.List, "EmptyState") ~= nil).toBe(true)
			expect(hasButtons(mounts.Window.Content)).toBe(false)
			UI:Open("Shop")
			task.wait(0.03)
			local shop = s.Controller("ShopController")
			expect(shop.Empty.Visible).toBe(true)
			expect(shop.List.Visible).toBe(false)
			expect(hasButtons(shop.Window.Content)).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
