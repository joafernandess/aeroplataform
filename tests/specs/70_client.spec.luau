-- Runs the REAL client (Main.client.luau + every controller) on fake Instances, bridged to the real server
-- services. Catches runtime errors in UI code that compile/lint checks cannot see.
local task = require("@lune/task")
local roblox = require("@lune/roblox")
local Session = require("../../tools/ui-preview/Session")
local Fake = require("../../tools/ui-preview/FakeRoblox")

return function(t)
	local expect = t.expect

	t.describe("client", function()
		t.it("boots every controller, mirrors the profile and opens every window without errors", function()
			local s = Session.new()
			local State = s.Runtime:Require("StarterPlayer/StarterPlayerScripts/Client/State")
			expect(State.Data ~= nil).toBe(true)
			expect(State.Data.Currencies.Yen).toBe(s.Data.Currencies.Yen)

			local UI = s.Controller("UIController")
			for _, name in { "Inventory", "Summon", "Worlds", "Quests", "Shop", "Upgrades", "Settings", "Raids" } do
				UI:Open(name)
				task.wait(0.02)
				expect(UI.Windows[name].Frame.Visible).toBe(true)
				expect(UI:IsOpen(name)).toBe(true)
			end
			UI:Close()
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("summons through the UI and receives the server's DataChanged updates", function()
			local s = Session.new()
			local State = s.Runtime:Require("StarterPlayer/StarterPlayerScripts/Client/State")
			local UI = s.Controller("UIController")
			local Summon = s.Controller("SummonController")
			local gems = State.Data.Currencies.Gems
			UI:Open("Summon", "B_W1")
			task.spawn(Summon.Summon, Summon, 10)
			task.wait(1.2)
			expect(State.Data.Currencies.Gems).toBe(gems - 450)
			expect(State.Data.Currencies.Gems).toBe(s.Data.Currencies.Gems)
			-- Reveal panel was shown in the overlay
			expect(#UI.Overlay:GetChildren() > 0).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("scales windows and HUD to fit a phone screen", function()
			local s = Session.new()
			local UI = s.Controller("UIController")
			local window = UI.Windows.Inventory.Frame
			local scale = window:FindFirstChildOfClass("UIScale")
			expect(scale.Scale).toBe(1)
			Fake.SetProperty(s.Camera, "ViewportSize", roblox.Vector2.new(844, 390))
			task.wait(0.02)
			expect(scale.Scale < 0.7).toBe(true)
			-- 820x520 window must fit inside 844x(390-58)
			expect(520 * scale.Scale <= 390 - 58).toBe(true)
			expect(UI.Menu:FindFirstChildOfClass("UIScale").Scale < 1).toBe(true)
		end)
	end)
end
