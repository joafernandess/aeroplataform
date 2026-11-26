-- Reworked HUD on the REAL client bridged to the REAL server (tools/ui-preview/Session): side menus, top-right Update
-- Log card, player info stack, docked AUTO, fighter slot selection and every new window (Codes, Teleport, Index,
-- Inventory, Achievements, Stats, Mounts, Shop closed state).
local task = require("@lune/task")
local Session = require("../../tools/ui-preview/Session")

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
		t.it("builds both columns in the requested order and every button opens a real window", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local Navigation = s.Runtime:Require(CLIENT .. "UI/Navigation")
			local function order(column)
				local names = {}
				local list = {}
				for _, child in column:GetChildren() do
					if child.ClassName == "Frame" then
						table.insert(list, child)
					end
				end
				table.sort(list, function(a, b)
					return a.LayoutOrder < b.LayoutOrder
				end)
				for _, child in list do
					table.insert(names, child.Name)
				end
				return table.concat(names, ",")
			end
			expect(order(UI.LeftNav)).toBe("Shop,Fighters,Settings,Codes,Quests,Teleport")
			expect(order(UI.RightNav)).toBe("Items,Mounts,Achievements,Stats,Index")
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

		t.it("opens windows at their responsive scale and keeps the old top-right Power/STATS out", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local HUD = s.Controller("HUDController")
			local TeamBar = s.Controller("TeamBarController")
			UI:Open("Codes")
			-- (FakeRoblox tweens jump to their goal: the pop from 86% ends on the responsive scale and the scrim fades in.)
			local scale = UI.Windows.Codes.Frame:FindFirstChildOfClass("UIScale")
			task.wait(0.05)
			expect(math.abs(scale.Scale - 1) < 1e-3).toBe(true)
			expect(UI.Scrim.BackgroundTransparency).toBe(0.55)
			UI:Close()
			-- Player info: Power lives under the Yen pill (top-left), not in a top-right column.
			local info = find(UI:GetRoot(), "PlayerInfo")
			expect(info ~= nil).toBe(true)
			expect(isInside(HUD.PowerPill.Frame, info)).toBe(true)
			expect(HUD.RightTools).toBeNil()
			expect(find(UI:GetRoot(), "StatsToggle")).toBeNil()
			-- AUTO is docked next to the fighter slots.
			expect(HUD.AutoContainer.Parent).toBe(TeamBar.ActionSlot)
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

	t.describe("fighter slots", function()
		t.it("selects a slot with its hotkey and opens the fighter on the second press", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local TeamBar = s.Controller("TeamBarController")
			local first = TeamBar.Team[1]
			expect(first ~= nil).toBe(true)
			TeamBar:Hotkey(1)
			task.wait(0.02)
			expect(TeamBar.SelectedUid).toBe(first.Uid)
			expect(UI:IsOpen("Fighters")).toBe(false)
			TeamBar:Hotkey(1)
			task.wait(0.05)
			expect(UI:IsOpen("Fighters")).toBe(true)
			expect(s.Controller("InventoryController").SelectedUid).toBe(first.Uid)
			-- Out-of-range hotkeys do nothing.
			UI:Close()
			TeamBar:Hotkey(8)
			task.wait(0.02)
			expect(UI:IsOpen("Fighters")).toBe(false)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
