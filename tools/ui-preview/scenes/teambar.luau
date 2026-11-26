--[[
	Team bar preview (Lune)
	Renders the bottom-centre team bar, the "better fighter" hint and the NEW badge on the Fighters button,
	using the REAL client + server (Session) like preview.luau.

	Usage (repo root):
	  lune run tools/ui-preview/scenes/teambar [outputDir]
	  node tools/ui-preview/screenshot.js [outputDir] [deviceScaleFactor]
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local task = require("@lune/task")
local roblox = require("@lune/roblox")

local Fake = require("../FakeRoblox")
local Render = require("../Render")
local Session = require("../Session")

local OUT = process.args[1] or "ui-preview-out"
if not fs.isDir(OUT) then
	fs.writeDir(OUT)
end

local session = Session.new()
local rt = session.Runtime
local UI = session.Controller("UIController")
local TeamBar = session.Controller("TeamBarController")
local Summon = session.Controller("SummonController")
local State = rt:Require("StarterPlayer/StarterPlayerScripts/Client/State")
local Features = rt:Require("ReplicatedStorage/Shared/Config/Features")

local function shot(name: string, caption: string, width: number?, height: number?)
	local html = Render.Page(session.PlayerGui, { Width = width or 1280, Height = height or 720, Caption = caption })
	fs.writeFile(OUT .. "/" .. name .. ".html", html)
	print(("wrote %s  (badge %d, hint %s, team %d)"):format(name, UI.MenuBadges.Inventory or 0, tostring(TeamBar.HintVisible), #State.Data.EquippedUnits))
end

local function clearOverlay()
	for _, child in UI.Overlay:GetChildren() do
		child:Destroy()
	end
end

-- 1. Fresh session: equipped team (best already equipped) and nothing new yet.
shot("01_teambar_hud", "Team bar — equipped fighters (bottom centre)")

-- 2. A lucky Summon x3 through the real Summon window, then back to the HUD: NEW badge + better-fighter hint.
-- Pick the first summon seed whose x3 pulls (level 1, no traits in the base game) beat the weakest team member,
-- so the hint appears for the real reason instead of a staged team change.
local h = session.Harness
local serverUnitStats = h.Runtime:Require("ReplicatedStorage/Shared/Modules/UnitStats")
local banner = h.Runtime:Require("ReplicatedStorage/Shared/Config/Banners").Get("B_W1")
local weakest = math.huge
for _, uid in session.Data.EquippedUnits do
	weakest = math.min(weakest, serverUnitStats.Compute(session.Data.Inventory.Units[uid]).Power)
end
for seed = 1, 5000 do
	local rolls = h.Services.SummonService.RollMany(h.Mocks.Random.new(seed), banner, table.clone(session.Data.SummonPity.B_W1 or {}), 1, 3)
	local best = 0
	for _, roll in rolls do
		best = math.max(best, serverUnitStats.Compute({ UnitId = roll.UnitId, Level = 1, Stars = 0 }).Power)
	end
	if best > weakest then
		h.Services.SummonService.Random = h.Mocks.Random.new(seed)
		print(("summon seed %d (best pull %d > weakest equipped %d)"):format(seed, best, weakest))
		break
	end
end
UI:Open("Summon", "B_W1")
task.wait(0.05)
task.spawn(Summon.Summon, Summon, 3)
task.wait(1.2)
shot("02_summon_reveal", "Summon x3 reveal (the team bar stays under the overlay)")
clearOverlay()
UI:Close()
task.wait(0.1)
shot("03_after_summon", "After Summon x3 — NEW badge on Fighters + Better fighter hint")

-- 3. Phone (landscape) with the same state.
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(844, 390))
task.wait(0.05)
shot("04_phone_after_summon", "Phone 844x390 — team bar, hint and badge", 844, 390)
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(1280, 720))
task.wait(0.05)

-- 4. Tap the first team card: Fighters opens with that fighter selected and the badge clears.
local firstCard = nil
for _, child in TeamBar.Slots:GetChildren() do
	if child.Name == "FighterCard" and (firstCard == nil or child.LayoutOrder < firstCard.LayoutOrder) then
		firstCard = child
	end
end
firstCard.Activated:Fire()
task.wait(0.1)
shot("05_card_opens_fighters", "Tapping a team card opens Fighters with it selected (badge cleared)")
UI:Close()
task.wait(0.05)

-- 5. Tap the hint: Equip Best fills the team and the hint goes away.
TeamBar.HintButton.Activated:Fire()
task.wait(0.1)
shot("06_after_equip_best", "After tapping the hint (Equip Best)")

-- 6. Two more equip slots (upgrade level 2): dashed empty slots + the "free slot" variant of the hint.
session.Data.Upgrades.EquipSlots = 2
h.Services.DataService:MarkDirty(session.Player, "Upgrades")
task.wait(0.1)
shot("07_empty_slots", "Equip-slot upgrade: dashed empty slots + Free team slot hint")

-- 7. With Features.PlayerLevel on, the bar (and hint) sit above the level bar.
Features.PlayerLevel = true
for _, child in UI:GetRoot():GetChildren() do
	if child:IsA("Frame") and child.Size == roblox.UDim2.fromOffset(460, 52) then
		child.Visible = true
	end
end
TeamBar:Layout()
shot("08_with_level_bar", "Features.PlayerLevel on — team bar above the level bar")
Fake.SetProperty(session.Camera, "ViewportSize", roblox.Vector2.new(844, 390))
task.wait(0.05)
TeamBar:Layout()
shot("09_phone_level_bar", "Phone 844x390 — empty slots, hint and level bar", 844, 390)

print("")
print(("client warnings: %d"):format(#rt.Mocks.Warnings))
for _, w in rt.Mocks.Warnings do
	print("  " .. w)
end
process.exit(0)
