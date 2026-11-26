-- Team bar (bottom-centre HUD), "better fighter" hint and the NEW badge on the Fighters menu button.
-- Runs the REAL client controllers against the real server services (tools/ui-preview/Session).
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Session = require("../../tools/ui-preview/Session")
local Fake = require("../../tools/ui-preview/FakeRoblox")

local function childrenNamed(parent, name: string)
	local out = {}
	for _, child in parent:GetChildren() do
		if child.Name == name then
			table.insert(out, child)
		end
	end
	table.sort(out, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return out
end

local function count(t): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

return function(t)
	local expect = t.expect

	t.describe("team bar", function()
		t.it("shows one card per equipped fighter in equip order, plus dashed empty slots", function()
			local s = Session.new()
			local State = s.Runtime:Require("StarterPlayer/StarterPlayerScripts/Client/State")
			local TeamBar = s.Controller("TeamBarController")
			local equipped = State.Data.EquippedUnits
			expect(#equipped > 0).toBe(true)

			local cards = childrenNamed(TeamBar.Slots, "FighterCard")
			expect(#cards).toBe(#equipped)
			for i, card in cards do
				expect(card:GetAttribute("Uid")).toBe(equipped[i])
			end
			expect(#childrenNamed(TeamBar.Slots, "EmptySlot")).toBe(0) -- 3/3 slots filled

			-- Bench one fighter: one card fewer, one dashed slot more.
			s.Net.Request("UnequipUnit", equipped[1])
			task.wait(0.1)
			expect(#childrenNamed(TeamBar.Slots, "FighterCard")).toBe(#equipped - 1)
			expect(#childrenNamed(TeamBar.Slots, "EmptySlot")).toBe(1)

			-- Equip-slot upgrade: more empty slots, wider bar.
			local width = TeamBar.Bar.Size.X.Offset
			s.Data.Upgrades.EquipSlots = 2
			s.Harness.Services.DataService:MarkDirty(s.Player, "Upgrades")
			task.wait(0.1)
			expect(#childrenNamed(TeamBar.Slots, "EmptySlot")).toBe(3)
			expect(TeamBar.Bar.Size.X.Offset > width).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("opens Fighters with the tapped fighter selected", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local TeamBar = s.Controller("TeamBarController")
			local Inventory = s.Controller("InventoryController")
			local card = childrenNamed(TeamBar.Slots, "FighterCard")[2]
			card.Activated:Fire()
			task.wait(0.05)
			expect(UI:IsOpen("Inventory")).toBe(true)
			expect(Inventory.SelectedUid).toBe(card:GetAttribute("Uid"))
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("shows the better-fighter hint only while Equip Best would improve the team; tapping it equips", function()
			local s = Session.new()
			local State = s.Runtime:Require("StarterPlayer/StarterPlayerScripts/Client/State")
			local UnitStats = s.Runtime:Require("ReplicatedStorage/Shared/Modules/UnitStats")
			local TeamBar = s.Controller("TeamBarController")
			-- The session starts after EquipBest: nothing to suggest.
			expect(TeamBar.HintVisible).toBe(false)
			expect(TeamBar.Hint.Visible).toBe(false)

			-- Swap the strongest member for the weakest benched fighter.
			local data = State.Data
			local benched = {}
			for uid, unit in data.Inventory.Units do
				if not table.find(data.EquippedUnits, uid) then
					table.insert(benched, { Uid = uid, Power = UnitStats.Compute(unit).Power })
				end
			end
			table.sort(benched, function(a, b)
				return a.Power < b.Power
			end)
			local strongest = data.EquippedUnits[1]
			s.Net.Request("UnequipUnit", strongest)
			s.Net.Request("EquipUnit", benched[1].Uid)
			task.wait(0.1)
			expect(TeamBar.Suggestion(State.Data)).toBe("Better")
			expect(TeamBar.Hint.Visible).toBe(true)

			TeamBar.HintButton.Activated:Fire()
			task.wait(0.1)
			expect(table.find(State.Data.EquippedUnits, strongest) ~= nil).toBe(true)
			expect(TeamBar.Suggestion(State.Data)).toBe(nil)
			expect(TeamBar.Hint.Visible).toBe(false)

			-- An empty slot with fighters on the bench suggests filling it.
			s.Net.Request("UnequipUnit", State.Data.EquippedUnits[1])
			task.wait(0.1)
			expect(TeamBar.Suggestion(State.Data)).toBe("FreeSlot")
			expect(TeamBar.Hint.Visible).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("counts fighters summoned this session on the Fighters button and clears when Fighters opens", function()
			local s = Session.new()
			local State = s.Runtime:Require("StarterPlayer/StarterPlayerScripts/Client/State")
			local UI = s.Controller("UIController")
			local TeamBar = s.Controller("TeamBarController")
			local button = UI.MenuButtons.Inventory
			expect(button ~= nil).toBe(true)
			expect(UI.MenuBadges.Inventory or 0).toBe(0)
			local badge = button:FindFirstChild("Badge")
			expect(badge == nil or badge.Visible == false).toBe(true)

			local before = count(State.Data.Inventory.Units)
			local response = s.Net.Request("Summon", "B_W1", 3)
			expect(response.ok).toBe(true)
			task.wait(0.1)
			local gained = count(State.Data.Inventory.Units) - before
			expect(gained).toBe(3)
			expect(UI.MenuBadges.Inventory).toBe(3)
			expect(TeamBar:NewCount()).toBe(3)
			badge = button:FindFirstChild("Badge")
			expect(badge.Visible).toBe(true)
			expect(badge.Count.Text).toBe("3")

			-- Another pull adds up.
			s.Net.Request("Summon", "B_W1", 1)
			task.wait(0.1)
			expect(UI.MenuBadges.Inventory).toBe(4)
			expect(badge.Count.Text).toBe("4")

			-- Opening Fighters (here through the menu button) clears it.
			UI:Open("Inventory")
			task.wait(0.05)
			expect(UI.MenuBadges.Inventory).toBe(0)
			expect(badge.Visible).toBe(false)
			UI:Close()
			-- Fighters already owned stay "seen"; only later pulls count again.
			s.Net.Request("Summon", "B_W1", 1)
			task.wait(0.1)
			expect(UI.MenuBadges.Inventory).toBe(1)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("SetMenuBadge caps the text at 99+, hides at 0 and keeps counts for buttons not added yet", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			UI:SetMenuBadge("Settings", 120)
			local badge = UI.MenuButtons.Settings:FindFirstChild("Badge")
			expect(badge.Visible).toBe(true)
			expect(badge.Count.Text).toBe("99+")
			UI:SetMenuBadge("Settings", 0)
			expect(badge.Visible).toBe(false)
			-- Unknown / not-yet-created buttons keep the count for later.
			UI:SetMenuBadge("Raids", 2)
			expect(UI.MenuBadges.Raids).toBe(2)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("stays clear of the menu and sits above the level bar when it is enabled", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local TeamBar = s.Controller("TeamBarController")
			local Features = s.Runtime:Require("ReplicatedStorage/Shared/Config/Features")
			-- Widest bar (8 slots) on a small phone (iPhone SE landscape).
			s.Data.Upgrades.EquipSlots = 5
			s.Harness.Services.DataService:MarkDirty(s.Player, "Upgrades")
			Fake.SetProperty(s.Camera, "ViewportSize", roblox.Vector2.new(667, 375))
			task.wait(0.1)
			TeamBar:Layout()
			local container = TeamBar.Container
			expect(#childrenNamed(TeamBar.Slots, "EmptySlot")).toBe(8 - #childrenNamed(TeamBar.Slots, "FighterCard"))
			local function leftEdgeAndMenuRight(viewportWidth: number)
				local scale = TeamBar.Scale.Scale
				local left = viewportWidth / 2 + container.Position.X.Offset - container.Size.X.Offset * scale / 2
				local menuScale = UI.Menu:FindFirstChildOfClass("UIScale").Scale
				return left, UI.Menu.Position.X.Offset + UI.Menu.Size.X.Offset * menuScale
			end
			local left, menuRight = leftEdgeAndMenuRight(667)
			expect(TeamBar.Scale.Scale < 1).toBe(true)
			expect(container.Position.X.Offset).toBe(0) -- centred: there is room
			expect(left >= menuRight).toBe(true)
			expect(container.Position.Y.Offset).toBe(-12)

			-- Narrower than any phone: the HUD scale bottoms out, so the bar is nudged right of the menu.
			Fake.SetProperty(s.Camera, "ViewportSize", roblox.Vector2.new(420, 375))
			task.wait(0.05)
			TeamBar:Layout()
			left, menuRight = leftEdgeAndMenuRight(420)
			expect(container.Position.X.Offset > 0).toBe(true)
			expect(left >= menuRight).toBe(true)

			Features.PlayerLevel = true
			TeamBar:Layout()
			-- Bottom of the bar is above the 52px level bar (scaled) that sits 12px from the bottom.
			expect(-container.Position.Y.Offset >= 12 + 52 * TeamBar.Scale.Scale).toBe(true)
			Features.PlayerLevel = false
			TeamBar:Layout()
			expect(container.Position.Y.Offset).toBe(-12)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
