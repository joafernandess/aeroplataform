--[[
	Scene: reward feedback & the Stats window (Lune)
	Kills enemies on the REAL server so EnemyDefeated + Currencies/Inventory updates reach the REAL client, then
	renders the HUD mid-ticker, the Stats window after a boss kill and a phone screen with an active boost.

	Usage (repo root):
	  lune run tools/ui-preview/scenes/feedback [outputDir]
	  node tools/ui-preview/screenshot.js [outputDir] [scale]

	The fake TweenService applies goals instantly, so a shot taken right after a gain shows the ticker at the end
	of its rise (it only fades TICKER_HOLD seconds later) and the pill number already at its final value.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Fake = require("../FakeRoblox")
local Render = require("../Render")
local Session = require("../Session")

local OUT = process.args[1] or "ui-preview-out/feedback"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end

local session = Session.new()
local S = session.Harness.Services
local V = session.Harness.Vector3
local rt = session.Runtime
local Stats = session.Controller("SessionStatsController")

local width, height = 1280, 720

local function shot(name: string, caption: string)
	local html = Render.Page(session.PlayerGui, { Width = width, Height = height, Caption = caption })
	fs.writeFile(OUT .. "/" .. name .. ".html", html)
	print("wrote " .. name)
end

local function kill(enemyId: string, count: number)
	for _ = 1, count do
		local enemy = S.EnemyService:Spawn(enemyId, V.new(3, 3, 0), "World:W1")
		S.EnemyService:ApplyDamage(session.Player, enemy, 1e9)
	end
end

-- Pretend the session has been running for a few minutes (the rate uses the last 60s, at least 15s).
Stats.StartedAt -= 4 * 60 + 12

shot("01_idle", "HUD — antes de farmar")

-- A burst of kills in the same frame merges into one ticker.
kill("W1_Bandit", 4)
kill("W1_RogueNinja", 2)
task.wait(0.2)
shot("02_ticker", "Ganho de Yen: pílula pulsa, número sobe, \"+X\" flutua ao lado")

-- Boss kill, then the Stats window (session counters, lifetime stats, team power).
task.wait(0.9)
kill("W1_SnakeSage", 1)
task.wait(0.15)
session.Controller("UIController"):Open("Stats")
task.wait(0.05)
shot("03_stats_window", "Janela Stats depois de um chefe")
session.Controller("UIController"):Close()

-- Phone (landscape) with an active boost: the boost pill sits under Yen and the left menu moves down.
S.BoostService:Activate(session.Player, "Damage", 2, 600)
width, height = 844, 390
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(width, height))
task.wait(0.2)
kill("W1_Bandit", 3)
task.wait(0.15)
shot("04_phone_boost", "Celular 844x390 — ticker e boost ativo")

print("")
print(("kills %d · bosses %d · earned %d · rate %.1f/min"):format(Stats.Kills, Stats.Bosses, Stats.YenEarned, Stats:YenPerMinute()))
print(("client warnings: %d"):format(#rt.Mocks.Warnings))
for _, w in rt.Mocks.Warnings do
	print("  " .. w)
end
process.exit(0)
