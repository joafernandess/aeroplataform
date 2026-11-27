-- Reward feedback (Yen pill pops, count-up, "+X" tickers) and the Stats window, on the REAL
-- client bridged to the REAL server (tools/ui-preview/Session).
local task = require("@lune/task")
local Session = require("../../tools/ui-preview/Session")

local CLIENT = "StarterPlayer/StarterPlayerScripts/Client/"

local function setup()
	local s = Session.new()
	return s, s.Controller("HUDController"), s.Controller("SessionStatsController"), s.Runtime:Require(CLIENT .. "State")
end

local function kill(s, enemyId: string, count: number)
	local S = s.Harness.Services
	for _ = 1, count do
		local enemy = S.EnemyService:Spawn(enemyId, s.Harness.Vector3.new(3, 3, 0), "World:W1")
		S.EnemyService:ApplyDamage(s.Player, enemy, 1e9)
	end
end

local function tickers(holder)
	local out = {}
	for _, child in holder:GetChildren() do
		if child.Name == "Ticker" then
			table.insert(out, child)
		end
	end
	return out
end

return function(t)
	local expect = t.expect

	t.describe("reward feedback & session stats", function()
		t.it("counts kills and bosses from EnemyDefeated and tracks Yen earned without double counting", function()
			local s, _, Stats = setup()
			expect(Stats.Kills).toBe(0)
			local before = s.Data.Currencies.Yen
			kill(s, "W1_Bandit", 3)
			kill(s, "W1_SnakeSage", 1)
			task.wait(0.1)
			expect(Stats.Kills).toBe(4)
			expect(Stats.Bosses).toBe(1)
			-- Kill payloads arrive before the Currencies update; the update must not count them again.
			expect(Stats.YenEarned).toBe(s.Data.Currencies.Yen - before)
			expect(Stats:YenPerMinute() > 0).toBe(true)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("pops the Yen pill, counts to the new value and merges rapid gains into one ticker", function()
			local s, HUD = setup()
			local NumberFormat = s.Runtime:Require("ReplicatedStorage/Shared/Modules/NumberFormat")
			local yen = HUD.Animated.Yen
			local before = s.Data.Currencies.Yen
			expect(#tickers(yen.Holder)).toBe(0)
			kill(s, "W1_Bandit", 3)
			task.wait(0.1)
			local gained = s.Data.Currencies.Yen - before
			expect(gained > 0).toBe(true)
			local list = tickers(yen.Holder)
			expect(#list).toBe(1)
			expect(list[1].Text).toBe("+" .. NumberFormat.Abbreviate(gained) .. " ¥")
			expect(yen.Target).toBe(s.Data.Currencies.Yen)
			expect(yen.Value.Value).toBe(s.Data.Currencies.Yen)
			-- A second burst while the ticker is still showing adds to it instead of stacking a new one.
			kill(s, "W1_Bandit", 2)
			task.wait(0.1)
			list = tickers(yen.Holder)
			expect(#list).toBe(1)
			expect(list[1].Text).toBe("+" .. NumberFormat.Abbreviate(s.Data.Currencies.Yen - before) .. " ¥")
			-- The ticker fades out and is removed.
			task.wait(1.3)
			expect(#tickers(yen.Holder)).toBe(0)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("ignores spending: no ticker, no Yen earned, the number just counts down", function()
			local s, HUD, Stats = setup()
			s.Harness.Services.EconomyService:Remove(s.Player, "Yen", 300, "Test")
			task.wait(0.1)
			expect(#tickers(HUD.Animated.Yen.Holder)).toBe(0)
			expect(Stats.YenEarned).toBe(0)
			expect(Stats:YenPerMinute()).toBe(0)
			expect(HUD.Animated.Yen.Target).toBe(s.Data.Currencies.Yen)
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)

		t.it("shows session, lifetime and team power stats in the Stats window", function()
			local s, _, Stats, State = setup()
			local UI = s.Controller("UIController")
			kill(s, "W1_Bandit", 2)
			task.wait(0.1)
			UI:Open("Stats")
			task.wait(0.05)
			expect(UI:IsOpen("Stats")).toBe(true)
			expect(Stats.SessionLabels.Kills.Text).toBe("2")
			expect(Stats.Best ~= nil).toBe(true)
			-- One row per equipped fighter, plus the best-fighter row.
			local rows = 0
			for _, child in Stats.List:GetChildren() do
				if child.Name == "Fighter" then
					rows += 1
				end
			end
			expect(rows).toBe(#State.Data.EquippedUnits + 1)
			-- The section title shows the team total.
			local _, total = Stats.TeamBreakdown(State.Data)
			expect(total > 0).toBe(true)
			-- Live update without reopening.
			kill(s, "W1_Bandit", 1)
			task.wait(0.1)
			expect(Stats.SessionLabels.Kills.Text).toBe("3")
			expect(#s.Runtime.Mocks.Warnings).toBe(0)
		end)
	end)
end
