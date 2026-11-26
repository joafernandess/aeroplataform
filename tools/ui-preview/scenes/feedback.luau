--[[
	Scene: reward feedback & session stats (Lune)
	Kills enemies on the REAL server so EnemyDefeated + Currencies/Inventory updates reach the REAL client, then
	renders the HUD mid-ticker, with the session stats panel expanded, AUTO off and on a phone screen.

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
local State = rt:Require("StarterPlayer/StarterPlayerScripts/Client/State")
local Stats = session.Controller("SessionStatsController")
local RunService = session.Services.RunService

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

shot("01_idle", "HUD — antes de farmar (stats recolhido, 0 ¥/min)")

-- A burst of kills in the same frame merges into one ticker; a level-up raises team Power.
kill("W1_Bandit", 4)
kill("W1_RogueNinja", 2)
S.UnitService:AddUnitXP(session.Player, session.Units.Raizen.Uid, 4000)
task.wait(0.2)
shot("02_ticker", "Ganho de Yen e Power: pílula pulsa, número sobe, \"+X\" flutua ao lado")

-- Boss kill, then expand the stats panel; spin the AUTO icon a little (RenderStepped is driven by hand here).
task.wait(0.9)
kill("W1_SnakeSage", 1)
task.wait(0.15)
Stats:SetExpanded(true)
RunService.RenderStepped:Fire(0.35)
shot("03_stats_expanded", "Painel de sessão expandido + ticker do chefe; ícone AUTO girando")

-- Auto-attack off: Dark button, inverted status pill, icon back upright.
State.Request("UpdateSetting", "AutoAttack", false)
task.wait(1)
shot("04_auto_off", "AUTO OFF (botão Dark, pílula invertida)")
State.Request("UpdateSetting", "AutoAttack", true)

-- Phone (landscape) with an active boost so the right column is at its tallest.
S.BoostService:Activate(session.Player, "Damage", 2, 600)
width, height = 844, 390
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(width, height))
task.wait(0.2)
kill("W1_Bandit", 3)
task.wait(0.15)
shot("05_phone_expanded", "Celular 844x390 — ticker, boost e painel de sessão expandido")
Stats:SetExpanded(false)
task.wait(0.8)
shot("06_phone_collapsed", "Celular 844x390 — painel recolhido")

print("")
print(("kills %d · bosses %d · earned %d · rate %.1f/min"):format(Stats.Kills, Stats.Bosses, Stats.YenEarned, Stats:YenPerMinute()))
print(("client warnings: %d"):format(#rt.Mocks.Warnings))
for _, w in rt.Mocks.Warnings do
	print("  " .. w)
end
process.exit(0)
